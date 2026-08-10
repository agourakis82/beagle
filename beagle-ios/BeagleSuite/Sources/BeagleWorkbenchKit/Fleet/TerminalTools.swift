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
    NSApp.sendAction(sel, to: nil, from: from)
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
#endif
