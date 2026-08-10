#if os(macOS)
import XCTest
import SwiftUI
@testable import BeagleCore
@testable import BeagleWorkbenchKit

/// O encurtador de título do chip, com os títulos que o tmux REALMENTE publica.
final class ChipTituloTests: XCTestCase {

    func testCaminhoLongoViraOUltimoComponente() {
        // O que o tmux publica de fato numa lane do workspace. O prefixo `user@host:` é IDÊNTICO em
        // todas as onze lanes — mostrá-lo gastaria o chip inteiro sem distinguir nada.
        XCTAssertEqual(
            FleetTerminalsView.encurtar("openvscode-server@sounio-workspace-control-0:/workspace/sounio"),
            "sounio")
        XCTAssertEqual(
            FleetTerminalsView.encurtar("openvscode-server@pod:/workspace/.wt/codex-4"),
            "codex-4")
    }

    func testDoisPontosSemArrobaNaoEhCaminho() {
        // 🚨 A regra do `:` só vale DEPOIS de um `@`. Sem esta guarda, um título legítimo com
        // dois-pontos — que é a forma mais comum de título de build — perderia a primeira metade,
        // que é justamente onde está o assunto.
        XCTAssertEqual(FleetTerminalsView.encurtar("build: falhou"), "build: falhou")
        XCTAssertEqual(FleetTerminalsView.encurtar("erro: 3 testes"), "erro: 3 testes")
    }

    func testFraseLongaCortaNoFimDaPalavra() {
        // O começo é onde está o assunto. E o corte não parte palavra ao meio: "self-compil…" lê
        // como erro de renderização; "…for" lê como frase interrompida, que é o que é.
        let t = FleetTerminalsView.encurtar("Decide whether to land PR #1672 for self-compilation")
        XCTAssertTrue(t.hasSuffix("…"), "frase cortada tem que DIZER que foi cortada: \(t)")
        XCTAssertTrue(t.count <= 29, "não passa do teto: \(t.count)")
        XCTAssertFalse(t.dropLast().hasSuffix("-"), "não corta no meio de palavra hifenizada: \(t)")
        XCTAssertTrue(t.hasPrefix("Decide whether"), "o começo é o assunto: \(t)")
    }

    func testTituloCurtoPassaINTACTO() {
        // Encurtar o que já cabe seria estragar informação de graça.
        XCTAssertEqual(FleetTerminalsView.encurtar("compiler-issue-triage"), "compiler-issue-triage")
        XCTAssertEqual(FleetTerminalsView.encurtar("zsh"), "zsh")
    }

    func testEspacoESujeiraNaoViramTitulo() {
        XCTAssertEqual(FleetTerminalsView.encurtar("   "), "")
        XCTAssertEqual(FleetTerminalsView.encurtar("  build  "), "build")
    }

    @MainActor
    func testOSinoEATIVIDADESaoAvisosDIFERENTES() {
        // 🚨 A distinção que dá valor ao sino: saída nova é a lane TRABALHANDO — acontece o tempo
        // todo e não pede nada. O sino é a lane CHAMANDO. Se um badge só cobrisse os dois, o
        // pedido de atenção viraria ruído de fundo, que é como um alarme morre.
        let c = PTYClient(agent: "claude-1")
        XCTAssertEqual(c.sinos, 0)
        c.tocouSino()
        c.tocouSino()
        XCTAssertEqual(c.sinos, 2)
        c.limparSinos()
        XCTAssertEqual(c.sinos, 0, "olhar a lane reconhece o chamado")
    }

    @MainActor
    func testOStoreSEPARAChamadoDeSaidaNova() {
        // 🚨 ESTE é o teste que faltava, e a mutação provou: os dois de cima tocavam o `PTYClient`
        // direto, então a REGRA DO STORE podia estar invertida (sino lendo `activity`) e tudo
        // continuava verde. Aqui a decisão é exercida onde ela mora.
        let s = FleetTerminalStore()
        let c = PTYClient(agent: "claude-1")
        s.adotar("claude-1", c)

        XCTAssertFalse(s.chamou("claude-1"), "nada aconteceu ainda")
        c.tocouSino()
        XCTAssertTrue(s.chamou("claude-1"), "a lane CHAMOU")
        s.open("claude-1")
        XCTAssertFalse(s.chamou("claude-1"), "olhar reconhece o chamado")

        // E a distinção: saída nova NÃO acende o sino, e nunca deveria — trabalhar não é chamar.
        c.tocouSino()
        s.open("claude-1")
        XCTAssertFalse(s.chamou("claude-1"))
        XCTAssertFalse(s.hasUnread("claude-1"), "abrir também zera a saída nova")
    }

    @MainActor
    func testTituloQueREPETEONomeDaLaneNaoEhTitulo() {
        // Muito shell publica o próprio nome do programa como título. `claude-1  claude-1` no chip
        // gasta espaço para dizer o que já está dito ao lado.
        let s = FleetTerminalStore()
        let c = PTYClient(agent: "claude-1")
        s.adotar("claude-1", c)

        XCTAssertNil(s.titulo("claude-1"), "sem título anunciado, nada a mostrar")
        c.titulo = "claude-1"
        XCTAssertNil(s.titulo("claude-1"), "repetir o nome da lane não é informação")
        c.titulo = "   "
        XCTAssertNil(s.titulo("claude-1"), "espaço em branco não é título")
        c.titulo = "compiler-issue-triage"
        XCTAssertEqual(s.titulo("claude-1"), "compiler-issue-triage")
    }

    @MainActor
    func testTituloIgualAoNomeDaLaneNaoEhTitulo() {
        // Muito shell publica o próprio nome do programa como título. Repetir `claude-1  claude-1`
        // no chip gasta espaço para dizer o que já está dito.
        let s = FleetTerminalStore()
        XCTAssertNil(s.titulo("claude-1"), "lane fechada não tem título — sem fio, sem afirmação")
    }
}
#endif
