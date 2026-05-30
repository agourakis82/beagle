import Foundation
import BeagleCore

@MainActor
protocol MultimodelChatWebSocketDelegate: AnyObject {
    func multimodelChatWebSocket(_ socket: MultimodelChatWebSocket, didReceive event: MultimodelChatEvent)
    func multimodelChatWebSocket(_ socket: MultimodelChatWebSocket, connectionChanged connected: Bool, error: String?)
}

@MainActor
final class MultimodelChatWebSocket {
    weak var delegate: MultimodelChatWebSocketDelegate?

    private(set) var isConnected = false
    private(set) var lastError: String?
    private(set) var defaultProviderIds: [String] = []

    private var task: URLSessionWebSocketTask?
    private var receiveLoop: Task<Void, Never>?
    private var slug: String = ""

    func connect(httpBase: String, slug: String) {
        disconnect()
        self.slug = slug

        guard let url = Self.webSocketURL(httpBase: httpBase, slug: slug) else {
            lastError = "invalid websocket URL"
            delegate?.multimodelChatWebSocket(self, connectionChanged: false, error: lastError)
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
            delegate?.multimodelChatWebSocket(self, connectionChanged: false, error: nil)
        }
    }

    func sendChat(message: String, providers: [String], turnId: String = UUID().uuidString) {
        guard let task else {
            lastError = "websocket not connected"
            return
        }

        let payload: [String: Any] = [
            "type": "chat",
            "message": message,
            "providers": providers,
            "turnId": turnId,
            "history": []
        ]

        guard let data = try? JSONSerialization.data(withJSONObject: payload),
              let text = String(data: data, encoding: .utf8) else {
            lastError = "failed to encode chat payload"
            return
        }

        task.send(.string(text)) { [weak self] error in
            Task { @MainActor in
                guard let self else { return }
                if let error {
                    self.lastError = error.localizedDescription
                    self.delegate?.multimodelChatWebSocket(self, connectionChanged: false, error: self.lastError)
                }
            }
        }
    }

    func stop(turnId: String? = nil) {
        guard let task else { return }
        var payload: [String: Any] = ["type": "stop"]
        if let turnId { payload["turnId"] = turnId }
        guard let data = try? JSONSerialization.data(withJSONObject: payload),
              let text = String(data: data, encoding: .utf8) else { return }
        task.send(.string(text)) { _ in }
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
                    delegate?.multimodelChatWebSocket(self, connectionChanged: false, error: lastError)
                }
                break
            }
        }
    }

    private func handleIncoming(text: String) {
        guard let data = text.data(using: .utf8),
              let event = MultimodelChatEvent(jsonData: data) else { return }

        if event.type == "ready" {
            isConnected = true
            lastError = nil
            if let defaults = event.defaultProviders, !defaults.isEmpty {
                defaultProviderIds = defaults
            }
            delegate?.multimodelChatWebSocket(self, connectionChanged: true, error: nil)
        }

        if event.type == "error" {
            lastError = event.error ?? event.reason ?? "websocket error"
        }

        delegate?.multimodelChatWebSocket(self, didReceive: event)
    }

    private static func webSocketURL(httpBase: String, slug: String) -> URL? {
        let trimmed = httpBase.trimmingCharacters(in: .whitespacesAndNewlines)
        let base = trimmed.hasSuffix("/") ? String(trimmed.dropLast()) : trimmed
        guard var components = URLComponents(string: base) else { return nil }
        if components.scheme == "http" { components.scheme = "ws" }
        if components.scheme == "https" { components.scheme = "wss" }
        components.path = "/ws/projects/\(slug)/multimodel-chat"
        components.query = nil
        return components.url
    }
}
