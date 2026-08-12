import XCTest
@testable import BeagleCore

/// A regra da lane exibida na Sessão — semente, roster que chega depois, escolha do operador.
///
/// Esta é a parte TESTÁVEL do conserto da gaveta. O resto (o `@State` da escolha na janela e o
/// `.id(lane)` que recria o store) é estado de view SwiftUI e não se prende em unidade sem teste
/// de fachada; está declarado no relatório da fatia.
final class SessaoLaneTests: XCTestCase {

    /// Sem escolha nenhuma, a tela SEGUE o roster — não fica presa numa constante.
    func testSemEscolhaSegueORoster() {
        XCTAssertEqual(SessaoLane.exibida(roster: ["codex-4", "loom-1"], escolha: nil), "codex-4")
    }

    /// Roster vazio (fonte muda antes de qualquer frame) cai na semente em vez de estourar.
    func testRosterVazioCaiNaSemente() {
        XCTAssertEqual(SessaoLane.exibida(roster: [], escolha: nil),
                       FleetEndpoint.loomdLanes.first)
    }

    /// A escolha do operador vence o primeiro do roster. Sem isto, a gaveta abre e não faz nada.
    func testEscolhaVenceORoster() {
        XCTAssertEqual(SessaoLane.exibida(roster: ["loom-1", "codex-4"], escolha: "codex-4"),
                       "codex-4")
    }

    /// 🚨 O risco real do conserto: o roster chega DEPOIS do clique. Um estado semeado com a lane
    /// corrente seria sobrescrito pela atualização do roster e a escolha do operador evaporaria.
    func testRosterQueChegaDepoisNaoSobrescreveAEscolha() {
        // Antes do servidor falar: a semente.
        let antes = SessaoLane.exibida(roster: FleetEndpoint.loomdLanes, escolha: nil)
        XCTAssertEqual(antes, "loom-1")

        // Ele escolhe.
        let escolha = "codex-4"
        XCTAssertEqual(SessaoLane.exibida(roster: FleetEndpoint.loomdLanes, escolha: escolha),
                       "codex-4")

        // Agora o servidor declara o roster — com OUTRA lane na frente. A escolha continua de pé.
        XCTAssertEqual(SessaoLane.exibida(roster: ["loom-1", "codex-4", "codex-7"],
                                          escolha: escolha),
                       "codex-4")
        // E de novo, com o roster reordenado: nenhuma atualização de roster move a tela.
        XCTAssertEqual(SessaoLane.exibida(roster: ["codex-7", "loom-1", "codex-4"],
                                          escolha: escolha),
                       "codex-4")
    }

    /// Escolha que SAI do roster cai de volta para o roster: a tela não continua exibindo uma
    /// lane que o servidor não lista. Decisão presa aqui de propósito.
    func testEscolhaForaDoRosterCaiParaORoster() {
        XCTAssertEqual(SessaoLane.exibida(roster: ["loom-1", "codex-4"], escolha: "codex-9"),
                       "loom-1")
    }
}
