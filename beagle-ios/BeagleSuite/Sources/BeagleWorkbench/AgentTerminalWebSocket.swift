import Foundation
import BeagleCore

@MainActor
protocol AgentTerminalWebSocketDelegate: AnyObject {
    func agentTerminalWebSocket(_ socket: AgentTerminalWebSocket, connectionChanged connected: Bool, error: String?)
    func agentTerminalWebSocket(_ socket: AgentTerminalWebSocket, receivedOutput chunk: String, snapshotReplace: Bool)
    func agentTerminalWebSocket(_ socket: AgentTerminalWebSocket, ready info: AgentTerminalReadyInfo)
}

struct AgentTerminalReadyInfo: Sendable {
    let slug: String
    let kind: String
    let pod: String?
}

@MainActor
final class AgentTerminalWebSocket {
    weak var delegate: AgentTerminalWebSocketDelegate?

    private(set) var isConnected = false
    private(set) var lastError: String?

    private var task: URLSessionWebSocketTask?
    private var receiveLoop: Task<Void, Never>?
    private var slug: String = ""
    private var kind: String = ""

    func connect(httpBase: String, slug: String, kind: String) {
        disconnect()
        self.slug = slug
        self.kind = kind

        guard let url = Self.webSocketURL(httpBase: httpBase, slug: slug, kind: kind) else {
            lastError = "invalid agent websocket URL"
            delegate?.agentTerminalWebSocket(self, connectionChanged: false, error: lastError)
            return
        }

        let session = URLSession(configuration: .default)
        let socket = session.webSocketTask(with: url)
        task = socket
        socket.resume()
        receiveLoop = Task { [weak self] in
            await self?.receiveForever()
        }
    }

    func disconnect() {
        receiveLoop?.cancel()
        receiveLoop = nil
        task?.cancel(with: .goingAway, reason: nil)
        task = nil
        if isConnected {
            isConnected = false
            delegate?.agentTerminalWebSocket(self, connectionChanged: false, error: nil)
        }
    }

    func sendInput(_ text: String) {
        guard let task else { return }
        let payload: [String: Any] = ["type": "input", "data": text]
        guard let data = try? JSONSerialization.data(withJSONObject: payload),
              let json = String(data: data, encoding: .utf8) else { return }
        task.send(.string(json)) { [weak self] error in
            Task { @MainActor in
                if let error {
                    self?.lastError = error.localizedDescription
                }
            }
        }
    }

    func resize(cols: Int = 120, rows: Int = 34) {
        guard let task else { return }
        let payload: [String: Any] = ["type": "resize", "cols": cols, "rows": rows]
        guard let data = try? JSONSerialization.data(withJSONObject: payload),
              let json = String(data: data, encoding: .utf8) else { return }
        task.send(.string(json)) { _ in }
    }

    private func receiveForever() async {
        guard let task else { return }

        while !Task.isCancelled {
            do {
                let message = try await task.receive()
                switch message {
                case .string(let text):
                    handleIncoming(text: text)
                case .data(let data):
                    handleIncoming(text: String(decoding: data, as: UTF8.self))
                @unknown default:
                    break
                }
            } catch {
                if !Task.isCancelled {
                    isConnected = false
                    lastError = error.localizedDescription
                    delegate?.agentTerminalWebSocket(self, connectionChanged: false, error: lastError)
                }
                break
            }
        }
    }

    private func handleIncoming(text: String) {
        guard let data = text.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let type = object["type"] as? String else { return }

        switch type {
        case "ready":
            isConnected = true
            lastError = nil
            let info = object["data"] as? [String: Any] ?? [:]
            delegate?.agentTerminalWebSocket(
                self,
                ready: AgentTerminalReadyInfo(
                    slug: info["slug"] as? String ?? slug,
                    kind: kind,
                    pod: info["pod"] as? String
                )
            )
            delegate?.agentTerminalWebSocket(self, connectionChanged: true, error: nil)

        case "data":
            if let chunk = object["data"] as? String, !chunk.isEmpty {
                delegate?.agentTerminalWebSocket(self, receivedOutput: chunk, snapshotReplace: false)
            }

        case "snapshot":
            if let snap = object["data"] as? [String: Any] {
                let plain = snap["plainTail"] as? String ?? snap["tail"] as? String ?? ""
                if !plain.isEmpty {
                    delegate?.agentTerminalWebSocket(self, receivedOutput: plain, snapshotReplace: true)
                }
                if let pod = snap["podName"] as? String {
                    delegate?.agentTerminalWebSocket(
                        self,
                        ready: AgentTerminalReadyInfo(slug: slug, kind: kind, pod: pod)
                    )
                }
            }

        case "error":
            lastError = (object["data"] as? String) ?? "agent terminal error"
            delegate?.agentTerminalWebSocket(self, connectionChanged: false, error: lastError)

        case "exit":
            isConnected = false
            delegate?.agentTerminalWebSocket(self, connectionChanged: false, error: "agent exited")

        default:
            break
        }
    }

    private static func webSocketURL(httpBase: String, slug: String, kind: String) -> URL? {
        let trimmed = httpBase.trimmingCharacters(in: .whitespacesAndNewlines)
        let base = trimmed.hasSuffix("/") ? String(trimmed.dropLast()) : trimmed
        guard var components = URLComponents(string: base) else { return nil }
        if components.scheme == "http" { components.scheme = "ws" }
        if components.scheme == "https" { components.scheme = "wss" }
        components.path = "/ws/projects/\(slug)/agent/\(kind)"
        components.query = nil
        return components.url
    }
}

enum AgentTerminalFormatting {
    static func stripANSI(_ text: String) -> String {
        text.replacingOccurrences(
            of: "\u{001B}\\[[0-9;?]*[ -/]*[@-~]",
            with: "",
            options: .regularExpression
        )
    }

    static func cap(_ text: String, limit: Int = 80_000) -> String {
        guard text.count > limit else { return text }
        return String(text.suffix(limit))
    }
}
