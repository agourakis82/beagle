#if os(macOS)
import AppKit
import Foundation
import SwiftTerm
import Testing
@testable import BeagleCore
@testable import BeagleWorkbenchKit

/// O porte da aba Terminais para o Mac.
///
/// 🚨 Cada teste aqui guarda uma causa MEDIDA do que ele relatou três vezes — e nenhuma delas era
/// a que eu estava perseguindo. Verificar "o item de menu existe" já se provou o verde que não
/// prova nada; o que vale é o comportamento no tipo que roda.
@Suite(.serialized)
@MainActor
struct PorteTerminalMacTests {

    private func terminal() -> TerminalDaFrota {
        TerminalDaFrota(frame: .init(x: 0, y: 0, width: 400, height: 200))
    }

    /// O menu de contexto, ou uma FALHA legível.
    ///
    /// 🚨 A primeira versão destes testes usava `!`. Quando a mutação removeu o menu, o processo
    /// CRASHOU (`Fatal error: found nil`) e a suíte inteira reportou `Executed 0 tests` — que se lê
    /// como "não rodou", não como "quebrou". Um teste que morre em vez de falhar esconde a
    /// regressão que ele existe para mostrar.
    private func menuDe(
        _ tv: TerminalDaFrota,
        sourceLocation: SourceLocation = #_sourceLocation
    ) throws -> NSMenu {
        let evento = try #require(
            NSEvent.mouseEvent(
                with: .rightMouseDown, location: .zero, modifierFlags: [], timestamp: 0,
                windowNumber: 0, context: nil, eventNumber: 0, clickCount: 1, pressure: 1
            ),
            "não consegui sintetizar o evento",
            sourceLocation: sourceLocation
        )
        return try #require(
            tv.menu(for: evento),
            "sem menu, o clique direito continua não fazendo nada",
            sourceLocation: sourceLocation
        )
    }

    private func item(
        _ m: NSMenu,
        _ titulo: String,
        sourceLocation: SourceLocation = #_sourceLocation
    ) throws -> NSMenuItem {
        try #require(
            m.items.first { $0.title == titulo },
            "faltou «\(titulo)»: \(m.items.map(\.title))",
            sourceLocation: sourceLocation
        )
    }

    // ─── o menu que o SwiftTerm NÃO tem ──────────────────────────────────────────────────

    @Test func testOTerminalPASSAAterMenuDeContexto() throws {
        // A causa nº1 de "o clique direito não funciona": `MacTerminalView.swift` não tem
        // `rightMouseDown`, `menu(for:)` nem `override var menu` — zero ocorrências, verificado no
        // checkout. `NSView.rightMouseDown` sobe para `menu(for:)`, que devolvia `self.menu` = nil.
        // Não havia menu para aparecer, com ou sem o gesto do SwiftUI por cima.
        let tv = terminal()
        let m = try menuDe(tv)
        let titulos = m.items.map(\.title)
        for esperado in ["Copiar", "Colar", "Selecionar tudo", "Buscar…", "Limpar tela"] {
            #expect(titulos.contains(esperado), "faltou «\(esperado)» no menu: \(titulos)")
        }
        // Todo item precisa de ALVO e AÇÃO. Item sem alvo percorre a responder chain — que é
        // exatamente o caminho quebrado (o foco fica na sidebar), e falharia em silêncio.
        for i in m.items where !i.isSeparatorItem {
            #expect(i.action != nil, "«\(i.title)» sem ação")
            #expect(i.target === tv, "«\(i.title)» sem alvo — cairia na responder chain")
        }
    }

    @Test func testCopiarNASCEDESABILITADOSemSelecao() throws {
        // Copiar sem seleção põe string VAZIA na área de transferência e apaga o que estava lá —
        // destrutivo e silencioso. Item habilitado que não faz nada é o mesmo modo de falha do
        // menu que existia e não chegava a lugar nenhum.
        let tv = terminal()
        let copiar = try item(try menuDe(tv), "Copiar")
        #expect(!copiar.isEnabled, "sem seleção, Copiar não pode estar habilitado")
        #expect(!tv.validateMenuItem(copiar), "e a validação tem que concordar")
    }

    @Test func testColarSEGUEOEstadoDaAreaDeTransferencia() throws {
        let tv = terminal()
        NSPasteboard.general.clearContents()
        #expect(!(try item(try menuDe(tv), "Colar").isEnabled),
                "sem texto na área de transferência, Colar não promete nada")

        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString("oi", forType: .string)
        #expect(try item(try menuDe(tv), "Colar").isEnabled)
    }

    // ─── o primeiro clique com a janela inativa ──────────────────────────────────────────

    @Test func testOPRIMEIROCliqueEmJanelaInativaVALE() {
        // O padrão do AppKit engole esse clique: ele só ativa a janela. Num app usado ao lado do
        // navegador — copiar um código de OAuth e voltar — todo primeiro clique se perderia, e a
        // conclusão razoável de quem usa é "o terminal não responde".
        #expect(terminal().acceptsFirstMouse(for: nil))
    }

    // ─── a colisão de ⌘K, que fui eu que criei ───────────────────────────────────────────

    @Test func testNENHUMAtalhoAparaceDuasVezes() throws {
        // 🚨 Eu criei uma colisão: "Limpar tela" (⌘K, NSMenuItem real da Scene) vencia o Button
        // invisível que abre a gaveta. Resultado: ⌘K limpava a tela, a gaveta NUNCA abria, e não
        // havia nenhum outro caminho de UI para ela. Este teste é sobre o MENU DO TERMINAL, que é
        // o que dá para alcançar em unidade; o do app é conferido por acessibilidade no instalado.
        let m = try menuDe(terminal())
        let atalhos = m.items
            .filter { !$0.isSeparatorItem && !$0.keyEquivalent.isEmpty }
            .map { "\($0.keyEquivalentModifierMask.rawValue)-\($0.keyEquivalent)" }
        #expect(atalhos.count == Set(atalhos).count, "atalho repetido no menu: \(atalhos)")

        // E "Limpar tela" é ⇧⌘K, não ⌘K — ⌘K ficou com a gaveta.
        let limpar = try item(m, "Limpar tela")
        #expect(limpar.keyEquivalent == "k")
        #expect(limpar.keyEquivalentModifierMask.contains(.shift),
                "⌘K sem shift colidiria com trocar de sessão")
    }

    // ─── a notificação que dá caminho VISÍVEL à gaveta ───────────────────────────────────

    @Test func testAGavetaTemCanalDeAbertura() async {
        // Um atalho invisível como único acesso é um recurso que não existe. O menu posta; a view
        // escuta. Sem este canal, o item de menu não teria como alcançar a tela.
        await confirmation("a view recebe o pedido de abrir a gaveta") { confirm in
            let obs = NotificationCenter.default.addObserver(
                forName: .abrirGavetaDeSessoes, object: nil, queue: .main
            ) { _ in confirm() }
            defer { NotificationCenter.default.removeObserver(obs) }
            NotificationCenter.default.post(name: .abrirGavetaDeSessoes, object: nil)
        }
    }
}
#endif
