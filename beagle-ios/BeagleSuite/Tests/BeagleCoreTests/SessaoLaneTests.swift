import Foundation
import Testing
@testable import BeagleCore

/// A regra da lane exibida na Sessão — semente, roster que chega depois, escolha do operador.
///
/// Esta é a parte TESTÁVEL do conserto da gaveta. O resto (o `@State` da escolha na janela e o
/// `.id(lane)` que recria o store) é estado de view SwiftUI e não se prende em unidade sem teste
/// de fachada; está declarado no relatório da fatia.
@Suite
struct SessaoLaneTests {

    /// Sem escolha nenhuma, a tela SEGUE o roster — não fica presa numa constante.
    @Test func testSemEscolhaSegueORoster() {
        #expect(SessaoLane.exibida(roster: ["codex-4", "loom-1"], escolha: nil) == "codex-4")
    }

    /// Roster vazio (fonte muda antes de qualquer frame) cai na semente em vez de estourar.
    @Test func testRosterVazioCaiNaSemente() {
        #expect(SessaoLane.exibida(roster: [], escolha: nil) == FleetEndpoint.loomdLanes.first)
    }

    /// A escolha do operador vence o primeiro do roster. Sem isto, a gaveta abre e não faz nada.
    @Test func testEscolhaVenceORoster() {
        #expect(SessaoLane.exibida(roster: ["loom-1", "codex-4"], escolha: "codex-4") == "codex-4")
    }

    /// 🚨 O risco real do conserto: o roster chega DEPOIS do clique. Um estado semeado com a lane
    /// corrente seria sobrescrito pela atualização do roster e a escolha do operador evaporaria.
    @Test func testRosterQueChegaDepoisNaoSobrescreveAEscolha() {
        // Antes do servidor falar: a semente.
        let antes = SessaoLane.exibida(roster: FleetEndpoint.loomdLanes, escolha: nil)
        #expect(antes == "loom-1")

        // Ele escolhe.
        let escolha = "codex-4"
        #expect(SessaoLane.exibida(roster: FleetEndpoint.loomdLanes, escolha: escolha) == "codex-4")

        // Agora o servidor declara o roster — com OUTRA lane na frente. A escolha continua de pé.
        #expect(SessaoLane.exibida(roster: ["loom-1", "codex-4", "codex-7"], escolha: escolha) == "codex-4")
        // E de novo, com o roster reordenado: nenhuma atualização de roster move a tela.
        #expect(SessaoLane.exibida(roster: ["codex-7", "loom-1", "codex-4"], escolha: escolha) == "codex-4")
    }

    /// Escolha que SAI do roster cai de volta para o roster: a tela não continua exibindo uma
    /// lane que o servidor não lista. Decisão presa aqui de propósito.
    @Test func testEscolhaForaDoRosterCaiParaORoster() {
        #expect(SessaoLane.exibida(roster: ["loom-1", "codex-4"], escolha: "codex-9") == "loom-1")
    }
}
