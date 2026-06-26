#if os(iOS) || os(macOS)
import Foundation
import Observation
import BeagleCore

/// Owns one PTYClient per *opened* agent so switching agents never reconnects.
/// Lazy: a client is created only when an agent is first opened (bounds memory).
/// Persists the last active agent across launches.
@MainActor
@Observable
public final class FleetTerminalStore {
    public private(set) var clients: [String: PTYClient] = [:]
    public var activeAgent: String { didSet { persistActive() } }
    public private(set) var opened: [String] = []
    /// Per-agent activity counter last "seen" (when it was active) — drives unread badges.
    private var seen: [String: Int] = [:]
    private let endpoint: FleetEndpoint
    private static let lastAgentKey = "fleetLastAgent"

    public init(endpoint: FleetEndpoint = FleetEndpoint()) {
        self.endpoint = endpoint
        let saved = UserDefaults.standard.string(forKey: Self.lastAgentKey)
        self.activeAgent = (saved.flatMap { FleetEndpoint.isKnownAgent($0) ? $0 : nil })
            ?? (FleetEndpoint.agents.first ?? "claude-1")
    }

    public var agents: [String] { FleetEndpoint.agents }

    /// Returns the (lazily created, kept-alive) client for an agent and marks it opened.
    public func client(for agent: String) -> PTYClient {
        if let c = clients[agent] { return c }
        let c = PTYClient(agent: agent, endpoint: endpoint)
        clients[agent] = c
        opened.append(agent)
        return c
    }

    public func open(_ agent: String) {
        guard FleetEndpoint.isKnownAgent(agent) else { return }
        let c = client(for: agent)
        seen[agent] = c.activity        // opening = caught up (clears unread)
        activeAgent = agent
    }

    /// Switch to the next/previous agent in the roster (for swipe).
    public func cycle(_ delta: Int) {
        let list = FleetEndpoint.agents
        guard let i = list.firstIndex(of: activeAgent) else { return }
        let n = ((i + delta) % list.count + list.count) % list.count
        open(list[n])
    }

    /// Connection state for an agent WITHOUT creating/opening it (idle if never opened).
    public func state(for agent: String) -> PTYClient.State {
        clients[agent]?.state ?? .idle
    }

    /// True when a non-active, opened agent produced output since it was last active.
    public func hasUnread(_ agent: String) -> Bool {
        guard agent != activeAgent, let c = clients[agent] else { return false }
        return c.activity > (seen[agent] ?? 0)
    }

    /// Reconnect any dropped sessions (call on foreground).
    public func reconnectStale() {
        for c in clients.values where c.state != .connected && c.state != .connecting {
            c.connect()
        }
    }

    private func persistActive() {
        UserDefaults.standard.set(activeAgent, forKey: Self.lastAgentKey)
    }
}
#endif
