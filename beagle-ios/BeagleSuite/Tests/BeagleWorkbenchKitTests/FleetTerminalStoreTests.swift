import Testing
@testable import BeagleCore
@testable import BeagleWorkbenchKit
import Foundation

/// A aba Terminais publica `FleetTerminalStore.agents` como roster. Enquanto esse roster foi a
/// mesma lista do allowlist de AÇÃO, `loom-1` — supervisionada pelo loomd, sem sessão tmux —
/// aparecia ali e oferecia um terminal que só podia dar erro.
@Test @MainActor func oRosterDeTerminaisNaoOfereceALaneDoLoomd() {
    let store = FleetTerminalStore()
    #expect(store.agents.count == 11)
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
