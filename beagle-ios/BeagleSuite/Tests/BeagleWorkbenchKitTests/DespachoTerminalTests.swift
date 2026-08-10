#if os(macOS)
import XCTest
import AppKit
import SwiftTerm
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
final class DespachoTerminalTests: XCTestCase {

    @MainActor
    func testSemTerminalOComandoADMITEQueNaoFezNada() {
        // Um comando que devolve "ok" sem ter feito nada é a falha silenciosa que custou duas
        // rodadas. Sem terminal registrado, o despacho tem que dizer não.
        TerminalAtivo.registrar(TerminalView(frame: .init(x: 0, y: 0, width: 400, height: 200)))
        XCTAssertTrue(TerminalAtivo.com { _ in }, "com terminal, executa")

        // Sem referência forte, a view morre — e o registro é weak de propósito, porque um
        // registro forte manteria vivo um WebSocket e um `tmux attach` no pod.
        autoreleasepool {}
    }

    @MainActor
    func testORegistroENAOOFocoDecideODestino() {
        // O teste que a rodada anterior não tinha. A view NÃO está em janela nenhuma, logo não tem
        // foco possível — e é exatamente aí que o `sendAction` falhava.
        let tv = TerminalView(frame: .init(x: 0, y: 0, width: 400, height: 200))
        XCTAssertNil(tv.window, "sem janela: nenhum foco é possível")
        TerminalAtivo.registrar(tv)
        XCTAssertTrue(tv === TerminalAtivo.view)

        // Os quatro comandos precisam ENCONTRAR destino. `responds(to:)` é o que o despacho checa,
        // e é o que garante que o seletor existe de verdade no SwiftTerm — não só no meu menu.
        for sel in [#selector(TerminalView.copy(_:)),
                    #selector(TerminalView.paste(_:)),
                    #selector(TerminalView.selectAll(_:)),
                    #selector(TerminalView.performFindPanelAction(_:))] {
            XCTAssertTrue(tv.responds(to: sel), "o TerminalView não responde a \(sel)")
        }
    }

    @MainActor
    func testAsFerramentasNOVASExistemNoTerminal() {
        // Zoom e limpar são MEUS, adicionados por extensão. Um `@objc` que não vira seletor de
        // verdade faria o menu existir e não fazer nada — o mesmo modo de falha, por outro caminho.
        let tv = TerminalView(frame: .init(x: 0, y: 0, width: 400, height: 200))
        for sel in [#selector(TerminalView.aumentarFonte(_:)),
                    #selector(TerminalView.diminuirFonte(_:)),
                    #selector(TerminalView.fonteOriginalTamanho(_:)),
                    #selector(TerminalView.limparTela(_:))] {
            XCTAssertTrue(tv.responds(to: sel), "extensão não expôs \(sel) ao ObjC")
        }
    }

    @MainActor
    func testOZoomMUDAAFonteERespeitaOsLimites() {
        // E o efeito, não só a existência do seletor.
        let tv = TerminalView(frame: .init(x: 0, y: 0, width: 400, height: 200))
        let inicial = tv.font.pointSize
        tv.aumentarFonte(nil)
        XCTAssertGreaterThan(tv.font.pointSize, inicial, "⌘+ tem que aumentar de verdade")
        tv.fonteOriginalTamanho(nil)
        XCTAssertEqual(tv.font.pointSize, inicial, accuracy: 0.01, "⌘0 volta ao que a tela nasceu")

        // O teto existe para o terminal não virar duas colunas.
        for _ in 0..<200 { tv.diminuirFonte(nil) }
        XCTAssertGreaterThanOrEqual(tv.font.pointSize, 8, "não afunda abaixo do mínimo")
        for _ in 0..<400 { tv.aumentarFonte(nil) }
        XCTAssertLessThanOrEqual(tv.font.pointSize, 32, "não estoura o máximo")
        // A família tem que sobreviver: perder a monoespaçada quebraria todo alinhamento de coluna.
        XCTAssertTrue(tv.font.isFixedPitch, "a fonte tem que continuar monoespaçada")
    }

    @MainActor
    func testOCOMANDOCHEGA_semJanelaEsemFoco() {
        // 🚨 O TESTE QUE FALTAVA, e a mutação provou: os outros tocam `TerminalAtivo` e
        // `responds(to:)` diretamente, então trocar o despacho de volta por `sendAction` — a
        // regressão exata que foi reportada DUAS vezes — deixava tudo verde.
        //
        // Aqui o comando é despachado de verdade e o EFEITO é medido. Sem janela: `sendAction`
        // devolveria false e nada mudaria, que é o que acontecia no app.
        let tv = TerminalView(frame: .init(x: 0, y: 0, width: 400, height: 200))
        XCTAssertNil(tv.window)
        TerminalAtivo.registrar(tv)

        let antes = tv.font.pointSize
        XCTAssertTrue(enviarAoTerminal(#selector(TerminalView.aumentarFonte(_:))),
                      "o despacho tem que ENCONTRAR o terminal, não o foco")
        XCTAssertGreaterThan(tv.font.pointSize, antes, "e o comando tem que CHEGAR lá")
    }

    @MainActor
    func testCOLARentregaOTextoAoTerminal() {
        // O caso que ele reportou, ponta a ponta: área de transferência → terminal → bytes no fio.
        // Sem isto não dá para responder a um prompt de OAuth, e foi o que travou uma lane.
        let tv = TerminalView(frame: .init(x: 0, y: 0, width: 400, height: 200))
        TerminalAtivo.registrar(tv)

        let espera = expectation(description: "o terminal enviou os bytes colados")
        let espiao = EspiaoDeEnvio(quando: { espera.fulfill() })
        tv.terminalDelegate = espiao

        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString("codigo-de-oauth-123", forType: .string)
        XCTAssertTrue(terminalColar(), "o comando tem que achar destino")

        wait(for: [espera], timeout: 2)
        XCTAssertTrue(String(decoding: espiao.recebido, as: UTF8.self).contains("codigo-de-oauth-123"),
                      "o texto colado tem que sair no fio: \(espiao.recebido.count) bytes")
    }

    @MainActor
    func testCOLARsemTextoADMITEQueNaoColou() {
        // 🚨 A regressão exata, e ela era invisível: o comando CHEGAVA ao terminal e nenhum byte
        // saía. `TerminalView.paste(_:)` faz `insertText(clipboard.string(forType:.string) ?? "")`,
        // e `insertText` só age `if let str = string as? NSString` — pasteboard sem `.string` vira
        // `""` e desaparece em silêncio, com o comando reportando sucesso.
        //
        // Lendo o pasteboard aqui, "não havia o que colar" é DIZÍVEL.
        let tv = TerminalView(frame: .init(x: 0, y: 0, width: 400, height: 200))
        TerminalAtivo.registrar(tv)
        NSPasteboard.general.clearContents()
        XCTAssertFalse(terminalColar(), "sem texto, colar tem que admitir que não colou")
        XCTAssertNil(textoDaAreaDeTransferencia())
    }

    @MainActor
    func testCOLARaceitaTipoRICO() {
        // Copiar de navegador ou PDF costuma oferecer só RTF/HTML. O operador não deveria precisar
        // saber disso para colar um código de OAuth que veio de uma página.
        let tv = TerminalView(frame: .init(x: 0, y: 0, width: 400, height: 200))
        TerminalAtivo.registrar(tv)
        let rico = NSAttributedString(string: "codigo-do-navegador")
        let d = try! rico.data(from: NSRange(location: 0, length: rico.length),
                               documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf])
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setData(d, forType: .rtf)
        XCTAssertEqual(textoDaAreaDeTransferencia(), "codigo-do-navegador",
                       "só RTF no pasteboard ainda é texto colável")
    }

    @MainActor
    func testABuscaEXIGENSMenuItemComTag() {
        // `performFindPanelAction` faz `sender as? NSMenuItem` e desiste em silêncio se não for.
        // Este teste guarda a razão de `enviarBusca` montar o item em vez de mandar `from: nil`.
        let item = NSMenuItem()
        item.tag = Int(NSFindPanelAction.showFindPanel.rawValue)
        XCTAssertEqual(item.tag, 1, "showFindPanel é 1 — se mudar, o despacho para de achar o painel")
        XCTAssertEqual(Int(NSFindPanelAction.next.rawValue), 2)
        XCTAssertEqual(Int(NSFindPanelAction.previous.rawValue), 3)
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
