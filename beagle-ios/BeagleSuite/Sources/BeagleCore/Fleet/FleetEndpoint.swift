import Foundation

/// Connection details for the fleet cockpit's native PTY transport (P0 `/pty/<agent>`).
/// No auth: the cockpit is gated at the pod (tailnet / Cloudflare Access). The device
/// must be on the tailnet to reach `host`.
public struct FleetEndpoint: Sendable {
    public static let agents: [String] = [
        "claude-1", "claude-2", "claude-3",
        "codex-1", "codex-2", "codex-3",
        "minimax", "kimi", "cursor", "grok",
    ]

    public let host: String
    public let scheme: String

    public init(host: String = "cockpit-1.tail21cbc4.ts.net", scheme: String = "ws") {
        self.host = host
        self.scheme = scheme
    }

    public static func isKnownAgent(_ agent: String) -> Bool {
        agents.contains(agent)
    }

    /// `ws://<host>/pty/<agent>` — nil for unknown/unsafe agents.
    public func ptyURL(agent: String) -> URL? {
        guard Self.isKnownAgent(agent) else { return nil }
        var c = URLComponents()
        c.scheme = scheme
        c.host = host
        c.path = "/pty/\(agent)"
        return c.url
    }

    /// Control frame the P0 gateway parses: `{"resize":[cols,rows]}`.
    public static func resizeFrame(cols: Int, rows: Int) -> String {
        #"{"resize":[\#(cols),\#(rows)]}"#
    }
}
