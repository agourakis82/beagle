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

    /// Local error for a dead socket that never throws on its own — the ping watchdog
    /// tripped instead of `receive()` (see the half-open-socket defect this file exists to fix).
    private enum KeepaliveError: LocalizedError {
        case pongTimeout
        var errorDescription: String? { "pong timeout — socket presumed half-open" }
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

    // MARK: - Keepalive (ping/pong watchdog)
    //
    // `URLSessionWebSocketTask.receive()` does not throw on a half-open socket (server gone,
    // no FIN/RST ever arrives) — it just hangs forever, and the client sits in `.connected`
    // showing a live terminal that will never receive another byte. A ping/pong heartbeat is
    // the only way to notice: if the pong never comes back within the watchdog window, we treat
    // that exactly like a `receive()` failure and go through the same drop → backoff → retry path.

    private var pingLoop: Task<Void, Never>?
    private var lastPongAt: Date = .distantPast
    private let pingIntervalSeconds: UInt64 = 15
    private let pongTimeoutSeconds: TimeInterval = 45
    /// Guards against `receive()` throwing and the ping watchdog firing for the same dead
    /// socket at nearly the same instant — without this, both paths would independently
    /// schedule a reconnect and the client would briefly run two connect attempts.
    private var dropInFlight = false

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
        dropInFlight = false
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
        startPingLoop()
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

    /// Ping every ~15s and watch for the pong. Two failure shapes matter here, both treated as
    /// a drop: `sendPing`'s own completion handler calling back with an error, and — the case
    /// that actually bit us — `sendPing` itself hanging on a half-open socket, caught by the
    /// wall-clock watchdog before the next tick fires.
    private func startPingLoop() {
        pingLoop?.cancel()
        lastPongAt = Date()   // don't fail before the first tick has a chance to ping
        pingLoop = Task { [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(self.pingIntervalSeconds))
                guard !Task.isCancelled else { break }
                guard let t = self.task else { break }

                if PTYClient.deveDerrubar(
                    ultimoPong: self.lastPongAt.timeIntervalSinceReferenceDate,
                    agora: Date().timeIntervalSinceReferenceDate,
                    tetoSegundos: self.pongTimeoutSeconds
                ) {
                    self.trace("pong watchdog expired — treating as drop")
                    self.handleDrop(KeepaliveError.pongTimeout)
                    break
                }

                t.sendPing { [weak self] error in
                    Task { @MainActor [weak self] in
                        guard let self else { return }
                        if let error {
                            self.trace("ping failed: \(error)")
                            self.handleDrop(error)
                        } else {
                            // Live socket confirmed: a connection that's been up for hours
                            // shouldn't carry a stale failure count from long ago.
                            self.lastPongAt = Date()
                            self.retries = 0
                            self.trace("pong ok")
                        }
                    }
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
        guard !dropInFlight else { return }
        dropInFlight = true
        task = nil
        receiveLoop?.cancel(); receiveLoop = nil
        pingLoop?.cancel(); pingLoop = nil
        retries += 1
        // The lane NEVER gives up for good — `.failed` is shown past `maxRetries` purely so the
        // UI can tell the operator something's wrong, but the retry loop below keeps running
        // with a capped backoff regardless, so the network coming back brings the lane back
        // without the operator reopening the app.
        state = retries >= maxRetries ? .failed(error.localizedDescription) : .reconnecting
        let delayMs = PTYClient.proximoAtrasoMs(retries: retries)
        Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(delayMs))
            self?.dropInFlight = false
            self?.connect()
        }
    }

    /// Pure: has too long passed since the last pong to still trust the socket?
    /// Extracted so the 45s watchdog window is assertable without ever sleeping 45s.
    /// `nonisolated` (and free of any instance state) so tests can call it synchronously
    /// without hopping onto the main actor.
    nonisolated static func deveDerrubar(ultimoPong: TimeInterval, agora: TimeInterval, tetoSegundos: TimeInterval) -> Bool {
        (agora - ultimoPong) > tetoSegundos
    }

    /// Pure: exponential backoff with a ~30s ceiling, floor at 500ms so it never tight-loops.
    /// No upper bound on `retries` — the client keeps retrying forever, it just stops growing
    /// the delay past the ceiling. (This is what replaces the old `retries < maxRetries`
    /// permanent give-up that made a network blip fatal to a lane forever.)
    nonisolated static func proximoAtrasoMs(retries: Int) -> Int {
        let tetoMs = 30_000
        let expoente = min(max(retries, 1), 7)
        let bruto = 250 * (1 << expoente)
        return min(tetoMs, bruto)
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
        pingLoop?.cancel(); pingLoop = nil
        sendRaw(FleetEndpoint.unsubscribeFrame(sid: agent))   // detach without killing the lane
        task?.cancel(with: .goingAway, reason: nil); task = nil
        state = .idle; retries = 0
    }
}
