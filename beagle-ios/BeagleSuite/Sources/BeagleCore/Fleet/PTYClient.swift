import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking   // URLSession/URLSessionWebSocketTask live here on non-Apple platforms
#endif
import Observation

/// One view onto a single fleet agent over the **Loom** broker (`/ws/loom`).
/// Each client owns its own multiplexed connection and `subscribe`s to exactly one lane sid,
/// demultiplexing only that sid's frames. Main-actor isolated: it feeds bytes straight into the
/// main-actor SwiftTerm view. The public surface is unchanged from the old `/pty` client, so the
/// store/view layers keep working — only the transport swapped.
///
/// (A single shared connection for the whole fleet is the Phase 2 refactor; per-client
/// connections keep this repoint minimal and the broker handles many clients cleanly.)
@MainActor
@Observable
public final class PTYClient {
    public enum State: Sendable, Equatable {
        case idle, connecting, connected, reconnecting, failed(String)
    }

    public private(set) var state: State = .idle
    /// Monotonic counter bumped on every output chunk — drives unread/activity badges.
    public private(set) var activity: Int = 0

    /// O título que o processo remoto anunciou (OSC 0/2). O tmux publica ali o que a lane está
    /// fazendo — informação que existia no fio e era descartada.
    public var titulo: String?
    /// Quantas vezes o sino tocou desde a última vez que ele olhou. Um agente que termina toca o
    /// sino; contar é o que permite a aba mostrar "aconteceu algo aqui" sem roubar o foco.
    public private(set) var sinos: Int = 0

    public func tocouSino() { sinos += 1 }
    public func limparSinos() { sinos = 0 }
    /// Set by the view: receives raw lane output bytes (already on the main actor).
    public var onBytes: (([UInt8]) -> Void)?

    public let agent: String
    private let endpoint: FleetEndpoint
    private let session: URLSession
    private var task: URLSessionWebSocketTask?
    private var receiveLoop: Task<Void, Never>?
    private var retries = 0
    private let maxRetries = 8
    /// Last viewport we told the lane — replayed after each (re)subscribe so tmux repaints.
    private var lastCols = 0
    private var lastRows = 0

    public init(agent: String, endpoint: FleetEndpoint = FleetEndpoint()) {
        self.agent = agent
        self.endpoint = endpoint
        self.session = URLSession(configuration: .default)
    }

    public func connect() {
        guard state != .connected && state != .connecting else { return }
        guard let request = endpoint.loomRequest() else {
            state = .failed("bad endpoint"); return
        }
        state = (retries == 0) ? .connecting : .reconnecting
        let t = session.webSocketTask(with: request)
        task = t
        t.resume()
        // Frames queue until the socket opens; subscribe immediately, then replay the size.
        sendRaw(FleetEndpoint.subscribeFrame(sid: agent))
        if lastCols > 0 && lastRows > 0 {
            sendRaw(FleetEndpoint.resizeFrame(sid: agent, cols: lastCols, rows: lastRows))
        }
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
                    case .string(let s): self.handleFrame(s)
                    case .data(let d): self.handleFrame(String(decoding: d, as: UTF8.self))
                    @unknown default: break
                    }
                } catch {
                    self.handleDrop(error)
                    break
                }
            }
        }
    }

    /// Parse one Loom server frame and act only on those addressed to this lane's sid.
    private func handleFrame(_ raw: String) {
        guard
            let data = raw.data(using: .utf8),
            let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let t = obj["t"] as? String
        else { return }

        switch t {
        case "scrollback", "data":
            guard (obj["sid"] as? String) == agent else { return }
            if let bytes = obj["bytes"] as? String {
                if t == "data" { activity &+= 1 }
                if activity <= 3 || t == "scrollback" { trace("\(t) \(bytes.utf8.count) bytes") }
                onBytes?([UInt8](Data(bytes.utf8)))
            }
        case "exit":
            guard (obj["sid"] as? String) == agent else { return }
            state = .failed("lane exited")
        case "error":
            // A lane-scoped error (e.g. failed to attach); a connection-scoped one has no sid.
            if let sid = obj["sid"] as? String, sid == agent {
                state = .failed((obj["message"] as? String) ?? "loom error")
            }
        default:
            break   // "sessions" / "state" — not needed for a single-lane terminal view.
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

    /// DEBUG breadcrumb on stderr — a terminal that attaches to nothing looks identical to a
    /// quiet agent, and the difference matters.
    private func trace(_ m: String) {
        #if DEBUG
        FileHandle.standardError.write(Data("[pty:\(agent)] \(m)\n".utf8))
        #endif
    }

    private func sendRaw(_ frame: String) {
        task?.send(.string(frame)) { _ in }
    }

    /// Keyboard/stdin → lane, wrapped in a Loom `input` frame.
    public func send(_ data: Data) {
        sendRaw(FleetEndpoint.inputFrame(sid: agent, data: String(decoding: data, as: UTF8.self)))
    }

    public func resize(cols: Int, rows: Int) {
        lastCols = cols; lastRows = rows
        sendRaw(FleetEndpoint.resizeFrame(sid: agent, cols: cols, rows: rows))
    }

    public func disconnect() {
        receiveLoop?.cancel(); receiveLoop = nil
        sendRaw(FleetEndpoint.unsubscribeFrame(sid: agent))   // detach without killing the lane
        task?.cancel(with: .goingAway, reason: nil); task = nil
        state = .idle; retries = 0
    }
}
