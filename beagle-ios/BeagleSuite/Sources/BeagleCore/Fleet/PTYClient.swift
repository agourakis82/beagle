import Foundation
import Observation

/// One persistent PTY WebSocket to a single fleet agent (P0 `/pty/<agent>`).
/// Main-actor isolated: it feeds bytes straight into the main-actor SwiftTerm view.
@MainActor
@Observable
public final class PTYClient {
    public enum State: Sendable, Equatable {
        case idle, connecting, connected, reconnecting, failed(String)
    }

    public private(set) var state: State = .idle
    /// Monotonic counter bumped on every output chunk — drives unread/activity badges.
    public private(set) var activity: Int = 0
    /// Set by the view: receives raw PTY output bytes (already on the main actor).
    public var onBytes: (([UInt8]) -> Void)?

    public let agent: String
    private let endpoint: FleetEndpoint
    private let session: URLSession
    private var task: URLSessionWebSocketTask?
    private var receiveLoop: Task<Void, Never>?
    private var retries = 0
    private let maxRetries = 8

    public init(agent: String, endpoint: FleetEndpoint = FleetEndpoint()) {
        self.agent = agent
        self.endpoint = endpoint
        self.session = URLSession(configuration: .default)
    }

    public func connect() {
        guard state != .connected && state != .connecting else { return }
        guard let url = endpoint.ptyURL(agent: agent) else {
            state = .failed("bad endpoint"); return
        }
        state = (retries == 0) ? .connecting : .reconnecting
        let t = session.webSocketTask(with: url)
        task = t
        t.resume()
        startReceiveLoop()
    }

    private func startReceiveLoop() {
        receiveLoop?.cancel()
        receiveLoop = Task { [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                guard let t = self.task else { break }
                do {
                    let msg = try await t.receive()
                    if self.state != .connected {
                        self.state = .connected
                        self.retries = 0
                    }
                    switch msg {
                    case .data(let d): self.activity &+= 1; self.onBytes?([UInt8](d))
                    case .string(let s): self.activity &+= 1; self.onBytes?([UInt8](Data(s.utf8)))
                    @unknown default: break
                    }
                } catch {
                    self.handleDrop(error)
                    break
                }
            }
        }
    }

    private func handleDrop(_ error: Error) {
        task = nil
        guard retries < maxRetries else {
            state = .failed(error.localizedDescription); return
        }
        retries += 1
        state = .reconnecting
        let delayMs = min(8000, 250 * (1 << min(retries, 5)))
        Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(delayMs))
            self?.connect()
        }
    }

    public func send(_ data: Data) {
        task?.send(.data(data)) { _ in }
    }

    public func resize(cols: Int, rows: Int) {
        task?.send(.string(FleetEndpoint.resizeFrame(cols: cols, rows: rows))) { _ in }
    }

    public func disconnect() {
        receiveLoop?.cancel(); receiveLoop = nil
        task?.cancel(with: .goingAway, reason: nil); task = nil
        state = .idle; retries = 0
    }
}
