#if os(iOS) || os(macOS)
import Testing
@testable import BeagleCore
@testable import BeagleWorkbenchKit
import Foundation

/// A aba Terminais publica `FleetTerminalStore.agents` como roster. Enquanto esse roster foi a
/// mesma lista do allowlist de AÇÃO, `loom-1` — supervisionada pelo loomd, sem sessão tmux —
/// aparecia ali e oferecia um terminal que só podia dar erro.
@Test @MainActor func oRosterDeTerminaisNaoOfereceALaneDoLoomd() {
    let store = FleetTerminalStore()
    #expect(store.agents == FleetEndpoint.terminalAgents)
    #expect(!store.agents.contains("loom-1"))
    #expect(store.agents.contains("claude-1"))
}

/// Nem pela porta dos fundos: o último agente ativo é lido de `UserDefaults`, e um valor gravado
/// por uma versão anterior do app abriria a aba direto num pty impossível.
@Test @MainActor func umAgenteSalvoSemTerminalNaoERestaurado() {
    let chave = "fleetLastAgent"
    let anterior = UserDefaults.standard.string(forKey: chave)
    defer {
        if let anterior { UserDefaults.standard.set(anterior, forKey: chave) }
        else { UserDefaults.standard.removeObject(forKey: chave) }
    }

    UserDefaults.standard.set("loom-1", forKey: chave)
    #expect(FleetTerminalStore().activeAgent != "loom-1")

    UserDefaults.standard.set("codex-2", forKey: chave)
    #expect(FleetTerminalStore().activeAgent == "codex-2")
}

/// `open` é a outra entrada. Ela criava um `PTYClient` para qualquer lane do allowlist de ação.
@Test @MainActor func abrirUmaLaneSemTerminalNaoCriaCliente() {
    let store = FleetTerminalStore()
    let antes = store.activeAgent
    store.open("loom-1")
    #expect(store.activeAgent == antes)
    #expect(store.clients["loom-1"] == nil)
}

/// Fechar uma janela flutuante (`LaneWindowView`) chama `PTYClient.disconnect()`. Se uma queda
/// recente já agendou backoff de reconexão (1s), `disconnect()` precisa cancelar esse retry e
/// nunca ressuscitar o WebSocket depois que a janela fechou.
@Test @MainActor func disconnectCancelaReconexaoEmCursoENaoRessuscitaSessao() async throws {
    let endpoint = FleetEndpoint(host: "127.0.0.1", scheme: "ws", token: "test-token")
    let client = PTYClient(agent: "claude-1", endpoint: endpoint)

    client.connect()
    #expect(client.state == .connecting)

    // Deixa a falha imediata da porta fechada disparar `handleDrop` e agendar o backoff de 1s.
    try await Task.sleep(for: .milliseconds(150))
    client.disconnect()
    #expect(client.state == .idle)

    // Mesmo após a janela do primeiro retry (1.0s), o cliente permanece `.idle`.
    try await Task.sleep(for: .milliseconds(1150))
    #expect(client.state == .idle)
}

/// Modelos puros de convés espacial (`SpatialAgentDeckSnapshot`) vivem em `BeagleCore` para
/// servir o visionOS sem puxar dependências AGPL de terminal, mantendo reexport em `BeagleWorkbenchKit`.
@Test func spatialAgentDeckSnapshotCompartilhadoEntreCoreEWorkbench() {
    let deck = SpatialAgentDeckSnapshot.fallback(
        projectSlug: "sounio",
        laneTitles: ["Claude/Codex", "Shell"]
    )
    #expect(deck.projectSlug == "sounio")
    #expect(deck.lanes.count == 2)
    #expect(deck.lanes[0].kind == "agent")
    #expect(deck.lanes[1].kind == "human")
}
#endif
