import Foundation

/// A CI verdict. `unknown` exists so an all-skipped rollup is never dressed up as green:
/// a gate that never ran proves nothing.
public enum CIVerdict: String, Sendable, Codable {
    case red, pending, green, unknown

    /// Board order: what needs a human comes first.
    public var rank: Int {
        switch self {
        case .red: return 0
        case .pending: return 1
        case .unknown: return 2
        case .green: return 3
        }
    }

    public var label: String {
        switch self {
        case .red: return "vermelho"
        case .pending: return "rodando"
        case .green: return "verde"
        case .unknown: return "não checado"
        }
    }

    /// Third encoding (with color and position) so the verdict survives without hue.
    public var glyph: String {
        switch self {
        case .red: return "✕"
        case .pending: return "◐"
        case .green: return "✓"
        case .unknown: return "?"
        }
    }
}

/// A named failing check — "what broke" must be actionable, never a bare red dot.
public struct FailingCheck: Sendable, Identifiable, Equatable {
    public let name: String
    public let workflow: String
    public let url: String
    public var id: String { name + workflow }
}

/// One open pull request as the Oficina sees it.
public struct PRRow: Sendable, Identifiable, Equatable {
    public let number: Int
    public let title: String
    public let branch: String
    public let url: String
    public let draft: Bool
    public let verdict: CIVerdict
    public let failing: [FailingCheck]
    public let checksTotal: Int
    public let checksGreen: Int
    public let updatedAt: Date?

    public var id: Int { number }

    /// "8/15" — how much actually ran and passed. Shown because a green badge over 1/4 checks
    /// means something very different from green over 24/28.
    public var checksSummary: String { "\(checksGreen)/\(checksTotal)" }
}

/// The repo's own position — "onde estou?"
public struct RepoHead: Sendable, Equatable {
    public let branch: String
    public let sha: String
    public let subject: String
    public let committedAt: Date?
    public let dirtyFiles: Int?
}

/// The whole Oficina reading, with its provenance.
public struct OficinaState: Sendable, Equatable {
    public let prs: [PRRow]
    public let mainVerdict: CIVerdict
    public let head: RepoHead?
    public let observedAt: Date?
    /// Set when the last sweep failed: the rows below are ageing, and the UI must say so.
    public let error: String?

    public static let empty = OficinaState(prs: [], mainVerdict: .unknown, head: nil, observedAt: nil, error: nil)

    public var red: [PRRow] { prs.filter { $0.verdict == .red } }
    public var ordered: [PRRow] {
        prs.sorted { $0.verdict.rank != $1.verdict.rank ? $0.verdict.rank < $1.verdict.rank : $0.number > $1.number }
    }

    public func isStale(now: Date = Date(), toleranceSeconds: TimeInterval = 180) -> Bool {
        guard error == nil, let observedAt else { return true }
        return now.timeIntervalSince(observedAt) > toleranceSeconds
    }

    /// Decode `GET /api/mobile/v1/oficina`. Missing/garbage fields degrade to `unknown` and
    /// empty rows — never to a confident green.
    public init?(envelope: [String: Any]) {
        guard let data = envelope["data"] as? [String: Any] else { return nil }
        let meta = envelope["meta"] as? [String: Any]
        self.error = meta?["error"] as? String

        let rawPRs = (data["prs"] as? [[String: Any]]) ?? []
        self.prs = rawPRs.compactMap { pr in
            guard let number = pr["number"] as? Int, number > 0 else { return nil }
            let failing = ((pr["failing"] as? [[String: Any]]) ?? []).map {
                FailingCheck(
                    name: ($0["name"] as? String) ?? "check",
                    workflow: ($0["workflow"] as? String) ?? "",
                    url: ($0["url"] as? String) ?? ""
                )
            }
            return PRRow(
                number: number,
                title: (pr["title"] as? String) ?? "",
                branch: (pr["branch"] as? String) ?? "",
                url: (pr["url"] as? String) ?? "",
                draft: (pr["draft"] as? Bool) ?? false,
                verdict: CIVerdict(rawValue: (pr["verdict"] as? String) ?? "") ?? .unknown,
                failing: failing,
                checksTotal: (pr["checksTotal"] as? Int) ?? 0,
                checksGreen: (pr["checksGreen"] as? Int) ?? 0,
                updatedAt: Self.iso((pr["updatedAt"] as? String))
            )
        }

        let main = data["main"] as? [String: Any]
        self.mainVerdict = CIVerdict(rawValue: (main?["verdict"] as? String) ?? "") ?? .unknown

        if let h = data["head"] as? [String: Any], let branch = h["branch"] as? String, !branch.isEmpty {
            self.head = RepoHead(
                branch: branch,
                sha: (h["sha"] as? String) ?? "",
                subject: (h["subject"] as? String) ?? "",
                committedAt: Self.iso(h["committedAt"] as? String),
                dirtyFiles: h["dirtyFiles"] as? Int
            )
        } else {
            self.head = nil
        }

        if let ms = data["observedAt"] as? Double, ms > 0 {
            self.observedAt = Date(timeIntervalSince1970: ms / 1000)
        } else {
            self.observedAt = nil
        }
    }

    public init(prs: [PRRow], mainVerdict: CIVerdict, head: RepoHead?, observedAt: Date?, error: String?) {
        self.prs = prs; self.mainVerdict = mainVerdict; self.head = head
        self.observedAt = observedAt; self.error = error
    }

    /// Built per call on purpose: `ISO8601DateFormatter` is not `Sendable`, so a shared static
    /// would be a data race under Swift 6 strict concurrency (the compiler rejects it). The cost
    /// is trivial next to the network round-trip that produced these strings.
    static func iso(_ s: String?) -> Date? {
        guard let s, !s.isEmpty else { return nil }
        let withFraction = ISO8601DateFormatter()
        withFraction.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return withFraction.date(from: s) ?? ISO8601DateFormatter().date(from: s)
    }
}
