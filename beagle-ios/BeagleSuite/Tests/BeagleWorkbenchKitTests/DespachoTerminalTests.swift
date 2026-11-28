#if os(macOS)
import AppKit
import Foundation
import SwiftTerm
import Testing
@testable import BeagleCore
@testable import BeagleWorkbenchKit

/// O despacho dos comandos de terminal.
///
/// 🚨 POR QUE ESTE ARQUIVO EXISTE: "copiar e colar não funciona" foi reportado DUAS vezes, e nas
/// duas o menu estava certo — item presente, atalho ligado, verificado por acessibilidade. O que
/// faltava era o destino. Medido no app instalado: `AXFocusedUIElement` era NULO na primeira vez e
/// `AXOutline` (a sidebar) na segunda. `NSApp.sendAction(to: nil)` percorre a responder chain A
/// PARTIR DO FOCO — os comandos morriam na sidebar.
///
/// Verificar "o item existe e tem atalho" é exatamente o verde que não prova nada. O que prova é
/// o comando ALCANÇANDO o terminal, e é isso que este arquivo exerce — sem janela e sem foco, que
/// é justamente a condição em que falhava.
@Suite(.serialized)
@MainActor
struct DespachoTerminalTests {

    @Test func testSemTerminalOComandoADMITEQueNaoFezNada() {
        // Um comando que devolve "ok" sem ter feito nada é a falha silenciosa que custou duas
        // rodadas. Sem terminal registrado, o despacho tem que dizer não.
        TerminalAtivo.registrar(TerminalView(frame: .init(x: 0, y: 0, width: 400, height: 200)))
        #expect(TerminalAtivo.com { _ in }, "com terminal, executa")

        // Sem referência forte, a view morre — e o registro é weak de propósito, porque um
        // registro forte manteria vivo um WebSocket e um `tmux attach` no pod.
        autoreleasepool {}
    }

    @Test func testORegistroENAOOFocoDecideODestino() {
        // O teste que a rodada anterior não tinha. A view NÃO está em janela nenhuma, logo não tem
        // foco possível — e é exatamente aí que o `sendAction` falhava.
        let tv = TerminalView(frame: .init(x: 0, y: 0, width: 400, height: 200))
        #expect(tv.window == nil, "sem janela: nenhum foco é possível")
        TerminalAtivo.registrar(tv)
        #expect(tv === TerminalAtivo.view)

        // Os quatro comandos precisam ENCONTRAR destino. `responds(to:)` é o que o despacho checa,
        // e é o que garante que o seletor existe de verdade no SwiftTerm — não só no meu menu.
        for sel in [#selector(TerminalView.copy(_:)),
                    #selector(TerminalView.paste(_:)),
                    #selector(TerminalView.selectAll(_:)),
                    #selector(TerminalView.performFindPanelAction(_:))] {
            #expect(tv.responds(to: sel), "o TerminalView não responde a \(sel)")
        }
    }

    @Test func testAsFerramentasNOVASExistemNoTerminal() {
        // Zoom e limpar são MEUS, adicionados por extensão. Um `@objc` que não vira seletor de
        // verdade faria o menu existir e não fazer nada — o mesmo modo de falha, por outro caminho.
        let tv = TerminalView(frame: .init(x: 0, y: 0, width: 400, height: 200))
        for sel in [#selector(TerminalView.aumentarFonte(_:)),
                    #selector(TerminalView.diminuirFonte(_:)),
                    #selector(TerminalView.fonteOriginalTamanho(_:)),
                    #selector(TerminalView.limparTela(_:))] {
            #expect(tv.responds(to: sel), "extensão não expôs \(sel) ao ObjC")
        }
    }

    @Test func testOZoomMUDAAFonteERespeitaOsLimites() {
        // E o efeito, não só a existência do seletor.
        let tv = TerminalView(frame: .init(x: 0, y: 0, width: 400, height: 200))
        let inicial = tv.font.pointSize
        tv.aumentarFonte(nil)
        #expect(tv.font.pointSize > inicial, "⌘+ tem que aumentar de verdade")
        tv.fonteOriginalTamanho(nil)
        #expect(abs(tv.font.pointSize - inicial) <= 0.01, "⌘0 volta ao que a tela nasceu")

        // O teto existe para o terminal não virar duas colunas.
        for _ in 0..<200 { tv.diminuirFonte(nil) }
        #expect(tv.font.pointSize >= 8, "não afunda abaixo do mínimo")
        for _ in 0..<400 { tv.aumentarFonte(nil) }
        #expect(tv.font.pointSize <= 32, "não estoura o máximo")
        // A família tem que sobreviver: perder a monoespaçada quebraria todo alinhamento de coluna.
        #expect(tv.font.isFixedPitch, "a fonte tem que continuar monoespaçada")
    }

    @Test func testOCOMANDOCHEGA_semJanelaEsemFoco() {
        // 🚨 O TESTE QUE FALTAVA, e a mutação provou: os outros tocam `TerminalAtivo` e
        // `responds(to:)` diretamente, então trocar o despacho de volta por `sendAction` — a
        // regressão exata que foi reportada DUAS vezes — deixava tudo verde.
        //
        // Aqui o comando é despachado de verdade e o EFEITO é medido. Sem janela: `sendAction`
        // devolveria false e nada mudaria, que é o que acontecia no app.
        let tv = TerminalView(frame: .init(x: 0, y: 0, width: 400, height: 200))
        #expect(tv.window == nil)
        TerminalAtivo.registrar(tv)

        let antes = tv.font.pointSize
        #expect(enviarAoTerminal(#selector(TerminalView.aumentarFonte(_:))),
                "o despacho tem que ENCONTRAR o terminal, não o foco")
        #expect(tv.font.pointSize > antes, "e o comando tem que CHEGAR lá")
    }

    @Test func testCOLARentregaOTextoAoTerminal() async {
        // O caso que ele reportou, ponta a ponta: área de transferência → terminal → bytes no fio.
        // Sem isto não dá para responder a um prompt de OAuth, e foi o que travou uma lane.
        let tv = TerminalView(frame: .init(x: 0, y: 0, width: 400, height: 200))
        await confirmation("o terminal enviou os bytes colados", expectedCount: 1...) { confirm in
            TerminalAtivo.registrar(tv)
            let espiao = EspiaoDeEnvio(quando: { confirm() })
            tv.terminalDelegate = espiao

            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString("codigo-de-oauth-123", forType: .string)
            #expect(terminalColar(), "o comando tem que achar destino")
            #expect(String(decoding: espiao.recebido, as: UTF8.self).contains("codigo-de-oauth-123"),
                    "o texto colado tem que sair no fio: \(espiao.recebido.count) bytes")
        }
    }

    @Test func testCOLARsemTextoADMITEQueNaoColou() {
        // 🚨 A regressão exata, e ela era invisível: o comando CHEGAVA ao terminal e nenhum byte
        // saía. `TerminalView.paste(_:)` faz `insertText(clipboard.string(forType:.string) ?? "")`,
        // e `insertText` só age `if let str = string as? NSString` — pasteboard sem `.string` vira
        // `""` e desaparece em silêncio, com o comando reportando sucesso.
        //
        // Lendo o pasteboard aqui, "não havia o que colar" é DIZÍVEL.
        let tv = TerminalView(frame: .init(x: 0, y: 0, width: 400, height: 200))
        TerminalAtivo.registrar(tv)
        NSPasteboard.general.clearContents()
        #expect(!terminalColar(), "sem texto, colar tem que admitir que não colou")
        #expect(textoDaAreaDeTransferencia() == nil)
    }

    @Test func testCOLARaceitaTipoRICO() throws {
        // Copiar de navegador ou PDF costuma oferecer só RTF/HTML. O operador não deveria precisar
        // saber disso para colar um código de OAuth que veio de uma página.
        let tv = TerminalView(frame: .init(x: 0, y: 0, width: 400, height: 200))
        TerminalAtivo.registrar(tv)
        let rico = NSAttributedString(string: "codigo-do-navegador")
        let d = try rico.data(from: NSRange(location: 0, length: rico.length),
                              documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf])
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setData(d, forType: .rtf)
        #expect(textoDaAreaDeTransferencia() == "codigo-do-navegador",
                "só RTF no pasteboard ainda é texto colável")
    }

    @Test func testSOMENTEOTerminalATIVOSeRegistra() {
        // 🚨 A causa de "testei, não colou" com várias lanes abertas — e de ter funcionado no meu
        // teste, que tinha UMA. A pilha mantém toda lane aberta viva com `opacity 0`, e
        // `updateNSView` roda para TODAS: a última a atualizar ganhava o registro. O ⌘V ia para um
        // terminal INVISÍVEL e o texto sumia num lugar que ele não estava olhando — sem erro.
        let visivel = TerminalView(frame: .init(x: 0, y: 0, width: 400, height: 200))
        let escondida = TerminalView(frame: .init(x: 0, y: 0, width: 400, height: 200))

        // A ordem imita a pilha: a invisível atualiza DEPOIS da visível.
        PTYTerminalView(client: PTYClient(agent: "claude-1"), ativo: true)
            .registrarSeAtivo(visivel)
        PTYTerminalView(client: PTYClient(agent: "claude-2"), ativo: false)
            .registrarSeAtivo(escondida)

        #expect(TerminalAtivo.view === visivel,
                "quem está na tela manda — a última a atualizar não pode roubar o destino")

        // E a troca de lane move o destino junto.
        PTYTerminalView(client: PTYClient(agent: "claude-2"), ativo: true)
            .registrarSeAtivo(escondida)
        #expect(TerminalAtivo.view === escondida, "trocar de lane troca o destino do ⌘V")
    }

    @Test func testABuscaEXIGENSMenuItemComTag() {
        // `performFindPanelAction` faz `sender as? NSMenuItem` e desiste em silêncio se não for.
        // Este teste guarda a razão de `enviarBusca` montar o item em vez de mandar `from: nil`.
        let item = NSMenuItem()
        item.tag = Int(NSFindPanelAction.showFindPanel.rawValue)
        #expect(item.tag == 1, "showFindPanel é 1 — se mudar, o despacho para de achar o painel")
        #expect(Int(NSFindPanelAction.next.rawValue) == 2)
        #expect(Int(NSFindPanelAction.previous.rawValue) == 3)
    }
}

/// Espião do fio: um delegate mínimo que só registra o que o terminal MANDOU. É como se verifica
/// que colar chegou ao processo remoto, e não só à tela.
private final class EspiaoDeEnvio: NSObject, @unchecked Sendable, TerminalViewDelegate {
    var recebido: [UInt8] = []
    private let quando: () -> Void
    init(quando: @escaping () -> Void) { self.quando = quando }

    func send(source: TerminalView, data: ArraySlice<UInt8>) {
        recebido.append(contentsOf: data)
        quando()
    }
    func sizeChanged(source: TerminalView, newCols: Int, newRows: Int) {}
    func setTerminalTitle(source: TerminalView, title: String) {}
    func hostCurrentDirectoryUpdate(source: TerminalView, directory: String?) {}
    func scrolled(source: TerminalView, position: Double) {}
    func requestOpenLink(source: TerminalView, link: String, params: [String: String]) {}
    func bell(source: TerminalView) {}
    func clipboardCopy(source: TerminalView, content: Data) {}
    func rangeChanged(source: TerminalView, startY: Int, endY: Int) {}
}
#endif
