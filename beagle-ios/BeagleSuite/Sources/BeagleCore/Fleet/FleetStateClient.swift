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
        link = (retries == 0) ? .connecting : .reconnecting
        let t = session.webSocketTask(with: request)
        task = t
        t.resume()
        send(FleetEndpoint.listFrame())
        startLoop()
    }

    public func disconnect() {
        loop?.cancel(); loop = nil
        task?.cancel(with: .goingAway, reason: nil); task = nil
        link = .idle; retries = 0
    }

    /// Clear a waiting lane in one gesture. Returns false when the lane needs a typed answer —
    /// the UI must not present a button we cannot honestly fulfil.
    @discardableResult
    public func approve(_ lane: LaneSnapshot) -> Bool {
        guard let injection = lane.approve.injection else { return false }
        send(FleetEndpoint.inputFrame(sid: lane.sid, data: injection))
        return true
    }

    /// Answer an open question with real text (the case one keystroke cannot cover).
    public func answer(_ lane: LaneSnapshot, text: String) {
        guard !text.isEmpty else { return }
        send(FleetEndpoint.inputFrame(sid: lane.sid, data: text + "\r"))
    }

    /// Ask the broker for a fresh roster (it also pushes on its own timer).
    public func refresh() { send(FleetEndpoint.listFrame()) }

    private func send(_ frame: String) { task?.send(.string(frame)) { _ in } }

    private func startLoop() {
        loop?.cancel()
        loop = Task { [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                guard let t = self.task else { break }
                do {
                    let msg = try await t.receive()
                    if self.link != .live { self.link = .live; self.retries = 0 }
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
                peek: old.peek,
                approve: old.approve,
                observedAt: (obj["observedAt"] as? Double).map { Date(timeIntervalSince1970: $0 / 1000) }
                    ?? old.observedAt
            )
        default:
            break   // data/scrollback belong to PTYClient; the board ignores terminal bytes.
        }
    }

    private func drop(_ error: Error) {
        task = nil
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
