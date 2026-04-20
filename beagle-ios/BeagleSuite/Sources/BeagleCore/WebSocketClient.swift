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

    // MARK: - Send

    public func sendInput(_ text: String) {
        guard let task, state.isConnected else { return }
        let json = "{\"type\":\"input\",\"data\":\(escapeJSON(text))}"
        task.send(.string(json)) { _ in }
    }

    public func sendResize(cols: Int, rows: Int) {
        guard let task, state.isConnected else { return }
        let json = "{\"type\":\"resize\",\"cols\":\(cols),\"rows\":\(rows)}"
        task.send(.string(json)) { _ in }
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
                    handleMessage(message)
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
                guard !Task.isCancelled && !self.userDisconnected else { return }

                self.state = .reconnecting(attempt: attempt)

                // Exponential backoff: 1s, 2s, 4s, 8s, ..., capped at 30s
                let baseDelay = min(30.0, pow(2.0, Double(attempt - 1)))
                let jitter = Double.random(in: 0...1)
                let delay = baseDelay + jitter
                try? await Task.sleep(for: .seconds(delay))

                guard !Task.isCancelled && !self.userDisconnected else { return }

                // Try to reconnect using the same multi-URL fallback
                var connected = false
                for base in self.baseURLs {
                    guard let url = Self.httpToWS(base: base, path: path) else { continue }

                    let wsTask = self.session.webSocketTask(with: url)
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
                                    self.setConnected(task: wsTask, source: base.host ?? "unknown")
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
            if !Task.isCancelled && !self.userDisconnected {
                self.state = .failed("reconnection failed after \(Self.maxReconnectAttempts) attempts")
                self.continuation?.yield(.exit(code: -1))
                self.continuation?.finish()
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
        case "stderr":
            if let payload = json["data"] as? String {
                continuation?.yield(.stderr(payload))
            }
        case "ready":
            let slug = (json["data"] as? [String: Any])?["projectSlug"] as? String ?? ""
            continuation?.yield(.ready(projectSlug: slug))
        case "exit":
            let detail = json["data"] as? String
            let code = json["code"] as? Int ?? parseExitCode(from: detail) ?? 0
            continuation?.yield(.exit(code: code, detail: detail))
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

    private func escapeJSON(_ string: String) -> String {
        let escaped = string
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: "\\n")
            .replacingOccurrences(of: "\r", with: "\\r")
            .replacingOccurrences(of: "\t", with: "\\t")
        return "\"\(escaped)\""
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
