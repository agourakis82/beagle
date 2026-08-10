#if os(macOS)
import AppKit
import SwiftTerm

// AS FERRAMENTAS DO TERMINAL.
//
// 🚨 A lição que este arquivo carrega: quase nada aqui é código NOVO. `SwiftTerm.TerminalView` já
// implementa copiar, colar, selecionar tudo e o painel de busca — como `@objc open func`, que a
// responder chain do macOS acha sozinha. O que faltava era o MENU: um app SwiftUI sem os grupos
// certos não liga atalho nenhum, e as teclas morrem antes de chegar ao terminal. Eu ia consertar o
// `PTYTerminalView`; o defeito estava na cena.
//
// O que É novo aqui são três coisas que o SwiftTerm não tem porque dependem da aplicação: zoom de
// fonte, limpar a tela, e rolagem por teclado.
//
// Todas entram pela responder chain (`sendAction(to: nil)`), então funcionam em QUALQUER terminal
// focado sem a cena precisar saber qual é — e continuam funcionando quando houver dois abertos.

/// O terminal ATIVO, para os comandos de menu não dependerem de quem tem o foco.
///
/// 🚨 MEDIDO no app instalado, e é a causa do "copiar e colar não funciona": o foco estava no
/// `AXOutline` — a sidebar do `NavigationSplitView` —, e `NSApp.sendAction(to: nil)` percorre a
/// responder chain A PARTIR DO FOCO. Os atalhos existiam, ligados, e morriam na sidebar. Antes
/// disso, o foco era simplesmente NULO: `AXFocusedUIElement` não existia.
///
/// Pedir foco resolve o caso de quem clicou no terminal, e só ele. Isto resolve todos: o comando
/// vai para o terminal ativo, tenha ele foco ou não — que é o que o operador quer quando aperta
/// ⌘V com a sidebar selecionada.
///
/// `weak` de propósito: a view morre quando a lane fecha, e um registro forte a manteria viva
/// segurando um WebSocket e um `tmux attach` no pod.
@MainActor
public enum TerminalAtivo {
    public private(set) static weak var view: TerminalView?

    /// Chamado pela representable quando a view aparece ou reaparece.
    public static func registrar(_ v: TerminalView) { view = v }

    /// Executa algo no terminal ativo. Devolve `false` quando não há nenhum — e o chamador PRECISA
    /// distinguir: um comando que "funcionou" sem terminal é a falha silenciosa que esta rodada
    /// inteira existe para não repetir.
    @discardableResult
    public static func com(_ acao: (TerminalView) -> Void) -> Bool {
        guard let v = view else { return false }
        acao(v)
        return true
    }
}

public extension Notification.Name {
    /// A gaveta de sessões, aberta pelo menu.
    ///
    /// Vive em `BeagleWorkbenchKit` e não na Scene por dependência: a Scene importa este módulo,
    /// nunca o contrário. E é notificação, não estado compartilhado, porque o menu não deveria
    /// guardar nada sobre uma tela que ele nem sabe se está aberta.
    static let abrirGavetaDeSessoes = Notification.Name("abrirGavetaDeSessoes")
}

// MARK: - O que o SwiftTerm não tem

extension TerminalView {
    /// Passos de fonte. Escala pequena de propósito: num terminal, um passo grande demais troca o
    /// número de colunas e reflui tudo que está na tela — o texto "pula" e se perde a linha que se
    /// estava lendo.
    private static let passoFonte: CGFloat = 1
    private static let fonteMin: CGFloat = 8
    private static let fonteMax: CGFloat = 32
    /// O tamanho de origem, para o ⌘0 ter para onde voltar. Guardado na primeira mudança, não no
    /// init: assim ele é o que a tela realmente nasceu usando.
    private static var fonteOriginal: [ObjectIdentifier: CGFloat] = [:]

    private func mudarFonte(para novo: CGFloat) {
        let atual = font
        let alvo = max(Self.fonteMin, min(Self.fonteMax, novo))
        guard abs(alvo - atual.pointSize) > 0.01 else { return }
        if Self.fonteOriginal[ObjectIdentifier(self)] == nil {
            Self.fonteOriginal[ObjectIdentifier(self)] = atual.pointSize
        }
        // `withSize` preserva a família — trocar por um `systemFont` aqui perderia a monoespaçada
        // e quebraria todo alinhamento de coluna que um terminal depende.
        font = NSFont(descriptor: atual.fontDescriptor, size: alvo) ?? atual
    }

    @objc public func aumentarFonte(_ sender: Any?) { mudarFonte(para: font.pointSize + Self.passoFonte) }
    @objc public func diminuirFonte(_ sender: Any?) { mudarFonte(para: font.pointSize - Self.passoFonte) }
    @objc public func fonteOriginalTamanho(_ sender: Any?) {
        guard let o = Self.fonteOriginal[ObjectIdentifier(self)] else { return }
        mudarFonte(para: o)
    }

    /// Limpa a tela — o `clear` que o shell não recebe quando o agente está no controle do TTY.
    ///
    /// NÃO manda `\u{c}` (form feed) pelo socket: isso seria digitar no agente, e num prompt de
    /// agente `^L` pode virar entrada em vez de comando. Aqui a limpeza é LOCAL, do que está
    /// desenhado, e não toca no processo do outro lado.
    @objc public func limparTela(_ sender: Any?) {
        terminal.resetToInitialState()
        needsDisplay = true
    }
}

// MARK: - Os comandos, para a cena montar o menu

/// Manda uma ação pela responder chain. É o idioma que faz o comando chegar ao terminal focado sem
/// a cena guardar referência a ele — e é o que continua funcionando com dois terminais abertos.
@MainActor
@discardableResult
public func enviarAoTerminal(_ sel: Selector, from: Any? = nil) -> Bool {
    // O terminal ativo PRIMEIRO. `sendAction` só como último recurso — ele depende do foco, e o
    // foco é justamente o que estava quebrado.
    if let v = TerminalAtivo.view, v.responds(to: sel) {
        _ = v.perform(sel, with: from)
        return true
    }
    return NSApp.sendAction(sel, to: nil, from: from)
}

/// A busca do SwiftTerm exige um `NSMenuItem` com `tag` — `performFindPanelAction` faz
/// `sender as? NSMenuItem` e devolve cedo se não for. Mandar `from: nil` aqui falharia em SILÊNCIO,
/// que é o modo de falha mais caro: o menu existe, o atalho responde, e nada acontece.
@MainActor
public func enviarBusca(_ acao: NSFindPanelAction) -> Bool {
    let item = NSMenuItem()
    item.tag = Int(acao.rawValue)
    return enviarAoTerminal(#selector(TerminalView.performFindPanelAction(_:)), from: item)
}

/// Copiar e colar vão pelo MESMO caminho dos outros comandos, e não por `NSText.copy/paste`.
///
/// Motivo: `NSApp.sendAction(#selector(NSText.paste(_:)))` entrega ao first responder — que era a
/// sidebar. Aqui o destino é o terminal ativo, que é onde o operador está olhando.
@MainActor @discardableResult public func terminalCopiar() -> Bool {
    enviarAoTerminal(#selector(TerminalView.copy(_:)))
}
/// Colar — LENDO o pasteboard aqui, em vez de delegar ao `paste(_:)` do SwiftTerm.
///
/// 🚨 MEDIDO com o app instrumentado: o comando CHEGAVA ao terminal (`paste: -> ENTREGUE`) e
/// nenhum byte saía no fio depois. O `paste(_:)` do SwiftTerm faz
/// `insertText(clipboard.string(forType: .string) ?? "", …)`, e o `insertText` só age
/// `if let str = string as? NSString` — pasteboard sem `.string` vira `""` e some, em silêncio.
///
/// Lendo aqui a diferença é observável: se não há texto, isto devolve `false` e o chamador pode
/// dizer por quê. Um "colar" que devolve sucesso sem colar é a falha silenciosa que já custou
/// três rodadas nesta mesma tecla.
///
/// `.string` primeiro; depois RTF/HTML convertidos para texto puro, porque copiar de um navegador
/// ou de um PDF costuma trazer só o tipo rico — e o operador não deveria precisar saber disso.
@MainActor @discardableResult public func terminalColar() -> Bool {
    guard let v = TerminalAtivo.view else { return false }
    guard let texto = textoDaAreaDeTransferencia(), !texto.isEmpty else { return false }
    v.send(txt: texto)
    return true
}

/// O texto da área de transferência, tentando as formas que importam na prática.
@MainActor public func textoDaAreaDeTransferencia() -> String? {
    let pb = NSPasteboard.general
    if let t = pb.string(forType: .string), !t.isEmpty { return t }
    // Copiar de navegador/PDF costuma oferecer só o tipo rico.
    for tipo in [NSPasteboard.PasteboardType.rtf, .html] {
        if let d = pb.data(forType: tipo),
           let a = try? NSAttributedString(data: d, options: [:], documentAttributes: nil),
           !a.string.isEmpty {
            return a.string
        }
    }
    return nil
}
@MainActor @discardableResult public func terminalSelecionarTudo() -> Bool {
    enviarAoTerminal(#selector(TerminalView.selectAll(_:)))
}
#endif
