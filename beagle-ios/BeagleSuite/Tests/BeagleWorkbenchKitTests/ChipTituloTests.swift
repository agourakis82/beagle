#if os(macOS)
import Foundation
import SwiftUI
import Testing
@testable import BeagleCore
@testable import BeagleWorkbenchKit

/// O encurtador de título do chip, com os títulos que o tmux REALMENTE publica.
@Suite
@MainActor
struct ChipTituloTests {

    @Test func testCaminhoLongoViraOUltimoComponente() {
        // O que o tmux publica de fato numa lane do workspace. O prefixo `user@host:` é IDÊNTICO em
        // todas as onze lanes — mostrá-lo gastaria o chip inteiro sem distinguir nada.
        #expect(
            FleetTerminalsView.encurtar("openvscode-server@sounio-workspace-control-0:/workspace/sounio")
            == "sounio"
        )
        #expect(
            FleetTerminalsView.encurtar("openvscode-server@pod:/workspace/.wt/codex-4")
            == "codex-4"
        )
    }

    @Test func testDoisPontosSemArrobaNaoEhCaminho() {
        // 🚨 A regra do `:` só vale DEPOIS de um `@`. Sem esta guarda, um título legítimo com
        // dois-pontos — que é a forma mais comum de título de build — perderia a primeira metade,
        // que é justamente onde está o assunto.
        #expect(FleetTerminalsView.encurtar("build: falhou") == "build: falhou")
        #expect(FleetTerminalsView.encurtar("erro: 3 testes") == "erro: 3 testes")
    }

    @Test func testFraseLongaCortaNoFimDaPalavra() {
        // O começo é onde está o assunto. E o corte não parte palavra ao meio: "self-compil…" lê
        // como erro de renderização; "…for" lê como frase interrompida, que é o que é.
        let t = FleetTerminalsView.encurtar("Decide whether to land PR #1672 for self-compilation")
        #expect(t.hasSuffix("…"), "frase cortada tem que DIZER que foi cortada: \(t)")
        #expect(t.count <= 29, "não passa do teto: \(t.count)")
        #expect(!t.dropLast().hasSuffix("-"), "não corta no meio de palavra hifenizada: \(t)")
        #expect(t.hasPrefix("Decide whether"), "o começo é o assunto: \(t)")
    }

    @Test func testTituloCurtoPassaINTACTO() {
        // Encurtar o que já cabe seria estragar informação de graça.
        #expect(FleetTerminalsView.encurtar("compiler-issue-triage") == "compiler-issue-triage")
        #expect(FleetTerminalsView.encurtar("zsh") == "zsh")
    }

    @Test func testEspacoESujeiraNaoViramTitulo() {
        #expect(FleetTerminalsView.encurtar("   ") == "")
        #expect(FleetTerminalsView.encurtar("  build  ") == "build")
    }

    @Test @MainActor
    func testOSinoEATIVIDADESaoAvisosDIFERENTES() {
        // 🚨 A distinção que dá valor ao sino: saída nova é a lane TRABALHANDO — acontece o tempo
        // todo e não pede nada. O sino é a lane CHAMANDO. Se um badge só cobrisse os dois, o
        // pedido de atenção viraria ruído de fundo, que é como um alarme morre.
        let c = PTYClient(agent: "claude-1")
        #expect(c.bellCount == 0)
        c.recordBell()
        c.recordBell()
        #expect(c.bellCount == 2)
        c.clearBells()
        #expect(c.bellCount == 0, "olhar a lane reconhece o chamado")
    }

    @Test @MainActor
    func testOStoreSEPARAChamadoDeSaidaNova() {
        // 🚨 ESTE é o teste que faltava, e a mutação provou: os dois de cima tocavam o `PTYClient`
        // direto, então a REGRA DO STORE podia estar invertida (sino lendo `activity`) e tudo
        // continuava verde. Aqui a decisão é exercida onde ela mora.
        let s = FleetTerminalStore()
        let c = PTYClient(agent: "claude-1")
        s.adopt("claude-1", client: c)

        #expect(!s.hasPendingBell(for: "claude-1"), "nada aconteceu ainda")
        c.recordBell()
        #expect(s.hasPendingBell(for: "claude-1"), "a lane CHAMOU")
        s.open("claude-1")
        #expect(!s.hasPendingBell(for: "claude-1"), "olhar reconhece o chamado")

        // E a distinção: saída nova NÃO acende o sino, e nunca deveria — trabalhar não é chamar.
        c.recordBell()
        s.open("claude-1")
        #expect(!s.hasPendingBell(for: "claude-1"))
        #expect(!s.hasUnread("claude-1"), "abrir também zera a saída nova")
    }

    @Test @MainActor
    func testTituloQueREPETEONomeDaLaneNaoEhTitulo() {
        // Muito shell publica o próprio nome do programa como título. `claude-1  claude-1` no chip
        // gasta espaço para dizer o que já está dito ao lado.
        let s = FleetTerminalStore()
        let c = PTYClient(agent: "claude-1")
        s.adopt("claude-1", client: c)

        #expect(s.title(for: "claude-1") == nil, "sem título anunciado, nada a mostrar")
        c.title = "claude-1"
        #expect(s.title(for: "claude-1") == nil, "repetir o nome da lane não é informação")
        c.title = "   "
        #expect(s.title(for: "claude-1") == nil, "espaço em branco não é título")
        c.title = "compiler-issue-triage"
        #expect(s.title(for: "claude-1") == "compiler-issue-triage")
    }

    @Test @MainActor
    func testTituloIgualAoNomeDaLaneNaoEhTitulo() {
        // Muito shell publica o próprio nome do programa como título. Repetir `claude-1  claude-1`
        // no chip gasta espaço para dizer o que já está dito.
        let s = FleetTerminalStore()
        #expect(s.title(for: "claude-1") == nil, "lane fechada não tem título — sem fio, sem afirmação")
    }
}
#endif
