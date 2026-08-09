import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import Observation

/// The Frota board's data source: ONE Loom socket that only listens for roster/state frames
/// and never subscribes to a lane. Cheap by construction — it carries no terminal bytes, so the
/// board stays live on a phone without streaming 11 PTYs.
///
/// It publishes what the broker observed, including staleness. When the socket drops, lanes are
/// NOT cleared: they keep their last verdict and age visibly, because a board that blanks on a
/// blip is worse than one that admits its data is old.
@MainActor
@Observable
public final class FleetStateClient {
    public enum Link: Sendable, Equatable {
        case idle, connecting, live, reconnecting, failed(String)
    }

    public private(set) var link: Link = .idle
    public private(set) var lanes: [LaneSnapshot] = []
    /// When the board last heard anything at all from the broker.
    public private(set) var lastFrameAt: Date?

    private let endpoint: FleetEndpoint
    private let session: URLSession
    private var task: URLSessionWebSocketTask?
    private var loop: Task<Void, Never>?
    private var retries = 0
    private let maxRetries = 12

    public init(endpoint: FleetEndpoint = FleetEndpoint()) {
        self.endpoint = endpoint
        self.session = URLSession(configuration: .default)
    }

    /// Lanes blocked on the operator — the "PRECISA DE VOCÊ" shelf.
    public var shelf: [LaneSnapshot] { FrotaBoard.shelf(lanes) }
    /// Everything else, calm.
    public var rest: [LaneSnapshot] { FrotaBoard.rest(lanes) }
    /// What ⌘↩ would clear (nil when nothing can be honestly approved with one keystroke).
    public var nextApprovable: LaneSnapshot? { FrotaBoard.oldestApprovable(lanes) }

    public func connect() {
        guard link != .live && link != .connecting else { return }
        guard let request = endpoint.loomRequest() else { link = .failed("bad endpoint"); return }
        closedByCaller = false
        link = (retries == 0) ? .connecting : .reconnecting
        trace("connect -> \(request.url?.absoluteString ?? "?") token=\(endpoint.token == nil ? "nil" : "sim")")
        let t = session.webSocketTask(with: request)
        task = t
        t.resume()
        send(FleetEndpoint.listFrame())
        startLoop()
    }

    public func disconnect() {
        // Order matters: cancel the receive loop FIRST. Cancelling the task while the loop is
        // still awaiting `receive()` makes it throw, which used to run the drop path and
        // resurrect a client the caller had deliberately closed.
        loop?.cancel(); loop = nil
        closedByCaller = true
        task?.cancel(with: .goingAway, reason: nil); task = nil
        link = .idle; retries = 0
        trace("disconnect (pedido pelo chamador)")
    }

    /// Set by `disconnect()` so a late error from the socket cannot schedule a reconnect.
    private var closedByCaller = false

    /// What an action did, in words the card can show. An approval that did not land must never
    /// look like one that did — the old path sent a frame into `task?.send { _ in }` and threw
    /// the completion error away, so a half-open socket swallowed the keystroke in silence.
    public struct ActionResult: Sendable, Equatable {
        public let ok: Bool
        public let message: String
        public static let sent = ActionResult(ok: true, message: "")
    }

    /// Clear a waiting lane with ONE named key, over HTTP — no attach, so it never becomes a
    /// tmux client and never resizes his panes. The server re-reads the lane's screen inside the
    /// request and refuses with a reason if the key is wrong for what is on it.
    @discardableResult
    public func approve(_ lane: LaneSnapshot) async -> ActionResult {
        guard let key = lane.approve.key else {
            return ActionResult(ok: false, message: "essa lane pede uma resposta digitada — abra o terminal")
        }
        return await press(lane, key)
    }

    /// Interrupt a lane. The only key that is also valid while it is working, and it confirms
    /// nothing — the CLIs advertise it themselves ("esc to interrupt").
    @discardableResult
    public func interrupt(_ lane: LaneSnapshot) async -> ActionResult { await press(lane, .esc) }

    /// Move a lane into its own git worktree, so two agents cannot clobber one tree.
    @discardableResult
    public func isolate(_ lane: LaneSnapshot) async -> ActionResult {
        guard let req = endpoint.laneIsolateRequest(sid: lane.sid) else {
            return ActionResult(ok: false, message: "lane fora do allowlist: \(lane.sid)")
        }
        return await post(req)
    }

    public func press(_ lane: LaneSnapshot, _ key: FleetEndpoint.LaneKey) async -> ActionResult {
        guard let req = endpoint.laneKeyRequest(sid: lane.sid, key: key) else {
            return ActionResult(ok: false, message: "lane fora do allowlist: \(lane.sid)")
        }
        let out = await post(req)
        if out.ok { refresh() }   // pull the roster so the card catches up with the sweep
        return out
    }

    /// One place where a lane action becomes an HTTP call, so every failure is legible. The
    /// server's own refusal text is surfaced verbatim: it is more specific than anything the
    /// client could guess ("a lane está running, não esperando por você").
    private func post(_ request: URLRequest) async -> ActionResult {
        do {
            let (data, response) = try await session.data(for: request)
            let code = (response as? HTTPURLResponse)?.statusCode ?? 0
            let body = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
            let serverError = (body?["error"] as? String) ?? ""
            if (200..<300).contains(code) { return .sent }
            if code == 401 { return ActionResult(ok: false, message: "Token do cockpit recusado (401).") }
            return ActionResult(ok: false, message: serverError.isEmpty ? "cockpit respondeu \(code)" : serverError)
        } catch {
            return ActionResult(ok: false, message: error.localizedDescription)
        }
    }

    /// Answer an open question with real text (the case one keystroke cannot cover). This one
    /// DOES need the socket: arbitrary text is not a named key, and it belongs on the path where
    /// he can see what he is answering.
    public func answer(_ lane: LaneSnapshot, text: String) {
        guard !text.isEmpty else { return }
        send(FleetEndpoint.inputFrame(sid: lane.sid, data: text + "\r"))
    }

    /// Ask the broker for a fresh roster (it also pushes on its own timer).
    public func refresh() { send(FleetEndpoint.listFrame()) }

    private func send(_ frame: String) { task?.send(.string(frame)) { _ in } }

    /// DEBUG-only breadcrumb on stderr. A board that silently fails to connect is the worst
    /// possible outcome — it looks like "the fleet is quiet" instead of "I am blind".
    private func trace(_ message: String) {
        #if DEBUG
        FileHandle.standardError.write(Data("[loom] \(message)\n".utf8))
        #endif
    }

    private func startLoop() {
        loop?.cancel()
        loop = Task { [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                guard let t = self.task else { break }
                do {
                    let msg = try await t.receive()
                    if self.link != .live { self.link = .live; self.retries = 0; self.trace("live") }
                    switch msg {
                    case .string(let s): self.handle(s)
                    case .data(let d): self.handle(String(decoding: d, as: UTF8.self))
                    @unknown default: break
                    }
                } catch {
                    self.drop(error)
                    break
                }
            }
        }
    }

    private func handle(_ raw: String) {
        guard
            let data = raw.data(using: .utf8),
            let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let t = obj["t"] as? String
        else { return }
        lastFrameAt = Date()

        switch t {
        case "sessions":
            guard let arr = obj["sessions"] as? [[String: Any]] else { return }
            lanes = arr.compactMap(LaneSnapshot.init(loom:))
            trace("sessions: \(lanes.count) lanes, \(shelf.count) na prateleira")
        case "state":
            // A single lane changed; patch it in place so the board does not reflow.
            guard let sid = obj["sid"] as? String,
                  let idx = lanes.firstIndex(where: { $0.sid == sid }) else { return }
            let old = lanes[idx]
            lanes[idx] = LaneSnapshot(
                sid: old.sid,
                title: old.title,
                state: LaneState(rawValue: (obj["state"] as? String) ?? "") ?? .unknown,
                detail: (obj["detail"] as? String) ?? old.detail,
                peek: (obj["peek"] as? [Any])?.compactMap { $0 as? String } ?? old.peek,
                // A patch that kept the OLD affordance could leave an approve button on a lane
                // that has moved on to a question needing a typed answer.
                approve: obj["approveKey"] == nil
                    ? old.approve
                    : ApproveAffordance(approveKey: obj["approveKey"] as? String),
                atShell: (obj["atShell"] as? Bool) ?? old.atShell,
                observedAt: (obj["observedAt"] as? Double).map { Date(timeIntervalSince1970: $0 / 1000) }
                    ?? old.observedAt
            )
        default:
            break   // data/scrollback belong to PTYClient; the board ignores terminal bytes.
        }
    }

    private func drop(_ error: Error) {
        task = nil
        if closedByCaller { trace("socket fechou após disconnect — sem reconexão"); return }
        trace("drop: \(error.localizedDescription)")
        // Deliberately keep `lanes`: stale-but-labelled beats an empty board.
        guard retries < maxRetries else { link = .failed(error.localizedDescription); return }
        retries += 1
        link = .reconnecting
        let delayMs = min(10_000, 250 * (1 << min(retries, 5)))
        Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(delayMs))
            self?.connect()
        }
    }
}
