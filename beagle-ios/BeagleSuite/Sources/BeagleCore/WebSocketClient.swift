//
//  WebSocketClient.swift
//  BeagleCore
//
//  Actor-isolated WebSocket client for real-time terminal streaming.
//  Mirrors CockpitClient's multi-URL fallback pattern over URLSessionWebSocketTask.
//
//  Two endpoints:
//   - Agent terminal: /ws/projects/:slug/agent/:kind
//   - Workspace terminal: /ws/terminal?project=slug&sessionId=x
//   - Notebook terminal pane: /ws/workspaces/:slug/sessions/:sessionId/panes/:paneId
//

import Foundation

public actor WebSocketClient {

    private let session: URLSession

    /// Same URL resolution as CockpitClient — http→ws scheme transform.
    /// Public websocket routes are now available on the Cloudflare edge, with
    /// the older private paths retained as fallback during transition.
    private var baseURLs: [URL] = [
        URL(string: "https://beagle.chiuratto.ai")!,
        URL(string: "http://sounio-cockpit.tail21cbc4.ts.net")!,
        URL(string: "http://100.107.208.198")!,
        URL(string: "http://project-cockpit.beagle.svc.cluster.local")!
    ]

    private var task: URLSessionWebSocketTask?
    private var receiveLoop: Task<Void, Never>?
    private var keepaliveLoop: Task<Void, Never>?
    private var reconnectTask: Task<Void, Never>?
    private var continuation: AsyncStream<TerminalMessage>.Continuation?
    private var lastPath: String?
    private var userDisconnected = false

    private static let maxReconnectAttempts = 10

    private(set) public var state: WebSocketState = .disconnected

    public init() {
        let config = URLSessionConfiguration.default
        config.waitsForConnectivity = true
        self.session = URLSession(configuration: config)
    }

    public func configure(baseURLs: [URL]) {
        self.baseURLs = baseURLs
    }

    // MARK: - Connect: Agent Terminal

    /// Connect to /ws/projects/:slug/agent/:kind
    public func connectAgent(slug: String, kind: String) -> AsyncStream<TerminalMessage> {
        let path = "/ws/projects/\(slug)/agent/\(kind)"
        return connect(path: path)
    }

    /// Connect to /ws/terminal?project=slug&sessionId=id
    public func connectTerminal(slug: String, sessionId: String = "") -> AsyncStream<TerminalMessage> {
        var path = "/ws/terminal?project=\(slug)"
        if !sessionId.isEmpty { path += "&sessionId=\(sessionId)" }
        return connect(path: path)
    }

    /// Connect to /ws/workspaces/:slug/sessions/:sessionId/panes/:paneId.
    public func connectWorkspacePane(slug: String, sessionId: String, paneId: String) -> AsyncStream<TerminalMessage> {
        let path = "/ws/workspaces/\(slug)/sessions/\(sessionId)/panes/\(paneId)"
        return connect(path: path)
    }

    // MARK: - Send

    public func sendInput(_ text: String) {
        sendMessage(["type": "input", "data": text])
    }

    public func sendResize(cols: Int, rows: Int) {
        sendMessage(["type": "resize", "cols": cols, "rows": rows])
    }

    public func sendPaste(_ text: String) {
        sendMessage(["type": "paste", "data": text])
    }

    public func sendSignal(_ signal: String = "SIGINT") {
        sendMessage(["type": "signal", "signal": signal])
    }

    public func sendFocus() {
        sendMessage(["type": "focus"])
    }

    public func stopProcess() {
        sendMessage(["type": "stop_process"])
    }

    public func startProcess(_ command: String) {
        sendMessage(["type": "start_process", "command": command])
    }

    public func approve(_ text: String = "y\n") {
        sendMessage(["type": "approve", "data": text])
    }

    public func attachBlockToMemory(blockId: String) {
        sendMessage(["type": "attach_block_to_memory", "blockId": blockId])
    }

    private func sendMessage(_ payload: [String: any Sendable]) {
        guard let task, state.isConnected else { return }
        guard let data = try? JSONSerialization.data(withJSONObject: payload),
              let json = String(data: data, encoding: .utf8) else { return }
        task.send(.string(json)) { error in
            if let error { print("[WS] send error: \(error.localizedDescription)") }
        }
    }

    // MARK: - Disconnect

    public func disconnect() {
        userDisconnected = true
        disconnectInternal()
    }

    private func disconnectInternal() {
        receiveLoop?.cancel()
        keepaliveLoop?.cancel()
        reconnectTask?.cancel()
        receiveLoop = nil
        keepaliveLoop = nil
        reconnectTask = nil
        task?.cancel(with: .normalClosure, reason: nil)
        task = nil
        if userDisconnected {
            continuation?.finish()
            continuation = nil
        }
        state = .disconnected
    }

    // MARK: - Internal

    private func connect(path: String) -> AsyncStream<TerminalMessage> {
        disconnectInternal()

        let (stream, cont) = AsyncStream<TerminalMessage>.makeStream()
        self.continuation = cont
        self.lastPath = path
        self.userDisconnected = false

        let capturedBaseURLs = baseURLs
        let capturedSession = session

        let clientSelf = self
        Task {
            await clientSelf.setState(.connecting)
            var connected = false

            for base in capturedBaseURLs {
                let wsURL = Self.httpToWS(base: base, path: path)
                guard let url = wsURL else { continue }

                let wsTask = capturedSession.webSocketTask(with: url)
                wsTask.resume()

                // Wait briefly for handshake
                do {
                    try await withThrowingTaskGroup(of: Bool.self) { group in
                        group.addTask {
                            // Try to receive one message as handshake proof
                            let msg = try await wsTask.receive()
                            // Process this first message
                            await clientSelf.handleMessage(msg)
                            return true
                        }
                        group.addTask {
                            try await Task.sleep(for: .seconds(12))
                            throw CancellationError()
                        }
                        if let result = try await group.next() {
                            group.cancelAll()
                            if result {
                                await clientSelf.setConnected(task: wsTask, source: base.host ?? "unknown")
                                connected = true
                            }
                        }
                    }
                } catch {
                    wsTask.cancel(with: .abnormalClosure, reason: nil)
                    continue
                }

                if connected { break }
            }

            if !connected {
                await clientSelf.setState(.failed("no base URL reachable"))
                cont.finish()
            }
        }

        return stream
    }

    private func setConnected(task: URLSessionWebSocketTask, source: String) {
        self.task = task
        self.state = .connected(source: source)
        startReceiveLoop()
        startKeepalive()
    }

    private func setState(_ newState: WebSocketState) {
        self.state = newState
    }

    private func startReceiveLoop() {
        receiveLoop = Task { [weak task] in
            guard let task else { return }
            while !Task.isCancelled {
                do {
                    let message = try await task.receive()
                    self.handleMessage(message)
                } catch {
                    if !Task.isCancelled && !self.userDisconnected {
                        // Unexpected disconnect — attempt reconnection
                        self.attemptReconnect()
                    } else if !Task.isCancelled {
                        self.continuation?.yield(.exit(code: -1))
                        self.continuation?.finish()
                        self.state = .disconnected
                    }
                    break
                }
            }
        }
    }

    private func attemptReconnect() {
        guard let path = lastPath, !userDisconnected else { return }

        reconnectTask = Task {
            for attempt in 1...Self.maxReconnectAttempts {
                guard !Task.isCancelled && !userDisconnected else { return }

                state = .reconnecting(attempt: attempt)

                // Exponential backoff: 1s, 2s, 4s, 8s, ..., capped at 30s
                let baseDelay = min(30.0, pow(2.0, Double(attempt - 1)))
                let jitter = Double.random(in: 0...1)
                let delay = baseDelay + jitter
                try? await Task.sleep(for: .seconds(delay))

                guard !Task.isCancelled && !userDisconnected else { return }

                // Try to reconnect using the same multi-URL fallback
                var connected = false
                for base in baseURLs {
                    guard let url = Self.httpToWS(base: base, path: path) else { continue }

                    let wsTask = session.webSocketTask(with: url)
                    wsTask.resume()

                    do {
                        try await withThrowingTaskGroup(of: Bool.self) { group in
                            group.addTask {
                                let msg = try await wsTask.receive()
                                await self.handleMessage(msg)
                                return true
                            }
                            group.addTask {
                                try await Task.sleep(for: .seconds(12))
                                throw CancellationError()
                            }
                            if let result = try await group.next() {
                                group.cancelAll()
                                if result {
                                    self.task?.cancel()
                                    setConnected(task: wsTask, source: base.host ?? "unknown")
                                    connected = true
                                }
                            }
                        }
                    } catch {
                        wsTask.cancel(with: .abnormalClosure, reason: nil)
                        continue
                    }

                    if connected { break }
                }

                if connected { return }
            }

            // All attempts exhausted
            if !Task.isCancelled && !userDisconnected {
                state = .failed("reconnection failed after \(Self.maxReconnectAttempts) attempts")
                continuation?.yield(.exit(code: -1))
                continuation?.finish()
            }
        }
    }

    private func startKeepalive() {
        keepaliveLoop = Task { [weak task] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(30))
                guard let task, !Task.isCancelled else { break }
                task.sendPing { error in
                    if error != nil {
                        // Connection lost — receive loop will handle cleanup
                    }
                }
            }
        }
    }

    private func handleMessage(_ message: URLSessionWebSocketTask.Message) {
        switch message {
        case .string(let text):
            parseServerMessage(text)
        case .data(let data):
            if let text = String(data: data, encoding: .utf8) {
                parseServerMessage(text)
            }
        @unknown default:
            break
        }
    }

    private func parseServerMessage(_ text: String) {
        guard let data = text.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let type = json["type"] as? String else {
            // Raw text — treat as data
            continuation?.yield(.data(text))
            return
        }

        switch type {
        case "data":
            if let payload = json["data"] as? String {
                continuation?.yield(.data(payload))
            }
        case "raw_output":
            if let event = parseWorkbenchEvent(json) {
                continuation?.yield(.workbenchEvent(event))
            }
        case "stderr":
            if let payload = json["data"] as? String {
                continuation?.yield(.stderr(payload))
            }
        case "ready":
            let slug = (json["data"] as? [String: Any])?["projectSlug"] as? String ?? ""
            continuation?.yield(.ready(projectSlug: slug))
            if let event = parseWorkbenchEvent(json) {
                continuation?.yield(.workbenchEvent(event))
            }
        case "exit":
            let detail = json["data"] as? String
            let code = json["code"] as? Int ?? parseExitCode(from: detail) ?? 0
            continuation?.yield(.exit(code: code, detail: detail))
        case "block_started",
             "block_output",
             "block_finished",
             "agent_state",
             "approval_requested",
             "memory_imported",
             "secret_redacted",
             "warp_bridge_event":
            if let event = parseWorkbenchEvent(json) {
                continuation?.yield(.workbenchEvent(event))
            }
        case "error":
            if let payload = json["data"] as? String {
                continuation?.yield(.stderr(payload))
            }
            if let event = parseWorkbenchEvent(json) {
                continuation?.yield(.workbenchEvent(event))
            }
        default:
            if let payload = json["data"] as? String {
                continuation?.yield(.data(payload))
            }
        }
    }

    // MARK: - Helpers

    private static func httpToWS(base: URL, path: String) -> URL? {
        guard var components = URLComponents(url: base, resolvingAgainstBaseURL: false) else { return nil }
        components.scheme = (components.scheme == "https") ? "wss" : "ws"

        // Parse path and query from the path string
        if let qIdx = path.firstIndex(of: "?") {
            components.path = String(path[..<qIdx])
            components.query = String(path[path.index(after: qIdx)...])
        } else {
            components.path = path
        }

        return components.url
    }

    private func parseExitCode(from detail: String?) -> Int? {
        guard let detail else { return nil }
        let pattern = #"-?\d+"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(detail.startIndex..<detail.endIndex, in: detail)
        guard let match = regex.firstMatch(in: detail, range: range),
              let matchRange = Range(match.range, in: detail) else {
            return nil
        }
        return Int(detail[matchRange])
    }

    private func parseWorkbenchEvent(_ json: [String: Any]) -> WorkbenchLiveEvent? {
        guard let type = json["type"] as? String else { return nil }
        let readyData = json["data"] as? [String: Any]
        return WorkbenchLiveEvent(
            type: type,
            sessionId: stringValue(json["sessionId"]),
            paneId: stringValue(json["paneId"]),
            blockId: stringValue(json["blockId"]),
            at: stringValue(json["at"]),
            data: stringValue(json["data"]),
            status: stringValue(json["status"]),
            state: stringValue(json["state"]),
            command: stringValue(json["command"]),
            title: stringValue(json["title"]),
            kind: stringValue(json["kind"]),
            privacyClass: stringValue(json["privacyClass"]),
            memoryEventId: stringValue(json["memoryEventId"]),
            auditEventId: stringValue(json["auditEventId"]),
            exitCode: intValue(json["exitCode"]),
            durationMs: intValue(json["durationMs"]),
            trigger: stringValue(json["trigger"]),
            reason: stringValue(json["reason"]),
            error: stringValue(json["error"]),
            authority: stringValue(json["authority"]),
            sourceModel: stringValue(json["sourceModel"]),
            bridgeVersion: stringValue(json["bridgeVersion"]),
            reconnectState: stringValue(json["reconnectState"]) ?? stringValue(readyData?["reconnectState"]),
            tags: json["tags"] as? [String],
            blockHash: stringValue(json["blockHash"]),
            sessionHash: stringValue(json["sessionHash"]),
            rendererHint: stringValue(json["rendererHint"]),
            startedAt: stringValue(json["startedAt"]),
            finishedAt: stringValue(json["finishedAt"]),
            event: stringValue(json["event"])
        )
    }

    private func stringValue(_ value: Any?) -> String? {
        switch value {
        case let string as String:
            return string
        case let number as NSNumber:
            return number.stringValue
        default:
            return nil
        }
    }

    private func intValue(_ value: Any?) -> Int? {
        switch value {
        case let int as Int:
            return int
        case let number as NSNumber:
            return number.intValue
        case let string as String:
            return Int(string)
        default:
            return nil
        }
    }
}

// MARK: - WebSocketState helpers

extension WebSocketState {
    public var isConnected: Bool {
        if case .connected = self { return true }
        return false
    }

    public var truthMode: TruthMode {
        switch self {
        case .connected:              return .observed
        case .reconnecting:           return .remembered
        case .connecting, .disconnected: return .declared
        case .failed:                 return .stale
        }
    }
}
