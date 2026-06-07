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
        _ = client(for: agent)
        activeAgent = agent
    }

    /// Connection state for an agent WITHOUT creating/opening it (idle if never opened).
    public func state(for agent: String) -> PTYClient.State {
        clients[agent]?.state ?? .idle
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
