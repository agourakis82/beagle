import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import Observation

/// Lanes sharing one working tree + branch: an edit by any of them is clobberable by all.
/// Measured, never assumed — the cockpit reads it from `tmux list-panes` + `git rev-parse`.
public struct SharedTree: Sendable, Identifiable, Equatable {
    public let cwd: String
    public let branch: String
    public let lanes: [String]
    public var id: String { cwd + "|" + branch }

    /// One lane alone in a tree is safe by construction; two or more is the hazard.
    public var isHazard: Bool { lanes.count > 1 }
}

/// Two lanes have declared overlapping paths. Advisory — it warns, it does not block.
public struct ClaimConflict: Sendable, Identifiable, Equatable {
    public let lanes: [String]
    public let overlaps: [String]
    public let notes: [String]
    public var id: String { lanes.joined(separator: "↔") }
}

/// A lane's declaration of what it is touching, as a lease.
public struct Claim: Sendable, Identifiable, Equatable {
    public let lane: String
    public let globs: [String]
    public let note: String
    public let expiresAt: Date?
    public var id: String { lane }
}

public struct CoordState: Sendable, Equatable {
    public let claims: [Claim]
    public let conflicts: [ClaimConflict]
    public let sharedTrees: [SharedTree]
    public let observedAt: Date?
    public let error: String?

    public static let empty = CoordState(claims: [], conflicts: [], sharedTrees: [], observedAt: nil, error: nil)

    /// Only the groups that actually put work at risk.
    public var hazards: [SharedTree] { sharedTrees.filter(\.isHazard) }

    /// How many lanes are currently exposed to being clobbered.
    public var lanesAtRisk: Int { hazards.reduce(0) { $0 + $1.lanes.count } }

    public var isStale: Bool {
        guard error == nil, let observedAt else { return true }
        return Date().timeIntervalSince(observedAt) > 180
    }

    public init(claims: [Claim], conflicts: [ClaimConflict], sharedTrees: [SharedTree],
                observedAt: Date?, error: String?) {
        self.claims = claims; self.conflicts = conflicts; self.sharedTrees = sharedTrees
        self.observedAt = observedAt; self.error = error
    }

    /// Decode `GET /api/mobile/v1/coord`, degrading to empty rather than to a false all-clear.
    public init?(envelope: [String: Any]) {
        guard let data = envelope["data"] as? [String: Any] else { return nil }
        self.error = (envelope["meta"] as? [String: Any])?["error"] as? String

        self.sharedTrees = ((data["sharedTrees"] as? [[String: Any]]) ?? []).compactMap { t in
            guard let cwd = t["cwd"] as? String,
                  let lanes = (t["lanes"] as? [Any])?.compactMap({ $0 as? String }),
                  !lanes.isEmpty else { return nil }
            return SharedTree(cwd: cwd, branch: (t["branch"] as? String) ?? "", lanes: lanes)
        }
        self.conflicts = ((data["conflicts"] as? [[String: Any]]) ?? []).compactMap { c in
            guard let lanes = (c["lanes"] as? [Any])?.compactMap({ $0 as? String }), lanes.count == 2 else { return nil }
            let overlaps = ((c["overlaps"] as? [[String: Any]]) ?? []).compactMap { o -> String? in
                guard let a = o["a"] as? String, let b = o["b"] as? String else { return nil }
                return a == b ? a : "\(a) ∩ \(b)"
            }
            return ClaimConflict(lanes: lanes, overlaps: overlaps,
                                 notes: (c["notes"] as? [Any])?.compactMap { $0 as? String } ?? [])
        }
        self.claims = ((data["claims"] as? [[String: Any]]) ?? []).compactMap { c in
            guard let lane = c["lane"] as? String else { return nil }
            return Claim(
                lane: lane,
                globs: (c["globs"] as? [Any])?.compactMap { $0 as? String } ?? [],
                note: (c["note"] as? String) ?? "",
                expiresAt: (c["expiresAt"] as? Double).map { Date(timeIntervalSince1970: $0 / 1000) }
            )
        }
        if let ms = data["observedAt"] as? Double, ms > 0 {
            self.observedAt = Date(timeIntervalSince1970: ms / 1000)
        } else {
            self.observedAt = nil
        }
    }
}

/// Polls the coordination surface. Read-only from the app's side: the app never claims on an
/// agent's behalf — a claim is a declaration by whoever is doing the work.
@MainActor
@Observable
public final class CoordClient {
    public private(set) var state: CoordState = .empty
    public private(set) var fetchError: String?

    private let endpoint: FleetEndpoint
    private let session: URLSession
    private var timer: Task<Void, Never>?

    public init(endpoint: FleetEndpoint = FleetEndpoint()) {
        self.endpoint = endpoint
        let cfg = URLSessionConfiguration.default
        cfg.timeoutIntervalForRequest = 12
        self.session = URLSession(configuration: cfg)
    }

    public func start(intervalSeconds: UInt64 = 45) {
        guard timer == nil else { return }
        timer = Task { [weak self] in
            while !Task.isCancelled {
                await self?.refresh()
                try? await Task.sleep(for: .seconds(intervalSeconds))
            }
        }
    }
    public func stop() { timer?.cancel(); timer = nil }

    public func refresh() async {
        guard let req = endpoint.coordRequest() else { fetchError = "endpoint inválido"; return }
        do {
            let (data, _) = try await session.data(for: req)
            guard let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let decoded = CoordState(envelope: obj) else {
                fetchError = "Resposta de coordenação ilegível."; return
            }
            fetchError = nil
            state = decoded
        } catch {
            // Keep the last reading: a missed poll must not read as "all clear".
            fetchError = "Coordenação não alcançável (\(error.localizedDescription))."
        }
    }
}
