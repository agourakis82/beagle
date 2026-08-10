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
        // `hasTerminal`, não `isKnownAgent`: o allowlist de AÇÃO inclui lanes do loomd, que não
        // têm sessão tmux. Restaurar uma delas como agente ativo abriria a aba Terminais direto
        // num PTY que só pode falhar.
        self.activeAgent = (saved.flatMap { FleetEndpoint.hasTerminal($0) ? $0 : nil })
            ?? (FleetEndpoint.terminalAgents.first ?? "claude-1")
    }

    /// O roster desta aba é o de TERMINAIS. Uma lane servida por protocolo (loomd) não entra:
    /// ela não tem pty do outro lado.
    public var agents: [String] { FleetEndpoint.terminalAgents }

    /// Returns the (lazily created, kept-alive) client for an agent and marks it opened.
    public func client(for agent: String) -> PTYClient {
        if let c = clients[agent] { return c }
        let c = PTYClient(agent: agent, endpoint: endpoint)
        clients[agent] = c
        opened.append(agent)
        return c
    }

    /// Adota um cliente PARADO, sem rede — a costura de teste.
    ///
    /// 🚨 Existe porque a mutação provou que sem ela os testes eram teatro: `chamou()` e
    /// `titulo()` só podem ser exercidos com um cliente ABERTO, e criar um cliente abria
    /// WebSocket. Os testes acabaram tocando o `PTYClient` direto e passavam com a regra do store
    /// invertida — sino virando atividade, título repetindo o nome da lane. Decisão que só se
    /// alcança abrindo socket não é decisão testável; é a mesma lição que já custou o
    /// `FleetStateClient.approveTransport` e o `SessionStore.apply`.
    public func adotar(_ agent: String, _ c: PTYClient) {
        clients[agent] = c
        if !opened.contains(agent) { opened.append(agent) }
    }

    public func open(_ agent: String) {
        guard FleetEndpoint.hasTerminal(agent) else { return }
        let c = client(for: agent)
        seen[agent] = c.activity        // opening = caught up (clears unread)
        sinosVistos[agent] = c.sinos     // e reconhece o chamado: você foi ver
        activeAgent = agent
    }

    /// Switch to the next/previous agent in the roster (for swipe).
    public func cycle(_ delta: Int) {
        let list = FleetEndpoint.terminalAgents
        guard let i = list.firstIndex(of: activeAgent) else { return }
        let n = ((i + delta) % list.count + list.count) % list.count
        open(list[n])
    }

    /// Connection state for an agent WITHOUT creating/opening it (idle if never opened).
    public func state(for agent: String) -> PTYClient.State {
        clients[agent]?.state ?? .idle
    }

    /// True when a non-active, opened agent produced output since it was last active.
    /// O TÍTULO que o processo remoto anunciou (OSC 0/2) — o tmux publica ali o que a lane está
    /// fazendo. `nil` quando ele não anunciou nada, e aí o chip mostra só o nome: inventar um
    /// título seria pior que não ter, porque pareceria informação.
    ///
    /// Só para lane ABERTA: sem cliente não há fio, e um título de memória de uma lane fechada
    /// seria uma afirmação sobre o presente feita com dado velho.
    public func titulo(_ agent: String) -> String? {
        guard let t = clients[agent]?.titulo?.trimmingCharacters(in: .whitespacesAndNewlines),
              !t.isEmpty, t != agent else { return nil }
        return t
    }

    /// 🔔 O sino tocou desde a última vez que ele olhou esta lane?
    ///
    /// Separado de `hasUnread` de propósito, e a diferença é o que importa: saída nova é a lane
    /// TRABALHANDO — acontece o tempo todo e não pede nada. O sino é a lane CHAMANDO: um agente que
    /// termina, ou que travou esperando decisão. Misturar os dois num badge só transformaria o
    /// pedido de atenção em ruído de fundo, que é como um alarme morre.
    public func chamou(_ agent: String) -> Bool {
        guard let c = clients[agent] else { return false }
        return c.sinos > (sinosVistos[agent] ?? 0)
    }
    private var sinosVistos: [String: Int] = [:]

    public func hasUnread(_ agent: String) -> Bool {
        guard agent != activeAgent, let c = clients[agent] else { return false }
        return c.activity > (seen[agent] ?? 0)
    }

    /// Let a lane go: close its socket and forget it. Without this, `opened` only ever grew —
    /// walking the roster once left one live WebSocket per lane, each holding a real `tmux
    /// attach` on the workspace pod. Detaching also lets the broker dematerialize the attach,
    /// which is what stops a lane's pane from being sized by a window nobody is looking at.
    public func close(_ agent: String) {
        guard let c = clients.removeValue(forKey: agent) else { return }
        c.disconnect()
        opened.removeAll { $0 == agent }
        seen[agent] = nil
        sinosVistos[agent] = nil
        if activeAgent == agent, let next = opened.first { activeAgent = next }
    }

    /// Close everything except the lane in front of him. Cheap insurance for a long session.
    public func closeAllExceptActive() {
        for agent in opened where agent != activeAgent { close(agent) }
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
