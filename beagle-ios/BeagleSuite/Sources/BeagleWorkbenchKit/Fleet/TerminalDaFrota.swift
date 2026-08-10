#if os(macOS)
import AppKit
import SwiftTerm

/// O `TerminalView` do SwiftTerm com o que falta para ele ser um terminal no MAC.
///
/// 🚨 POR QUE UMA SUBCLASSE, e não modificadores SwiftUI. Duas razões medidas:
///
/// 1. **O SwiftTerm não tem menu de contexto.** Verificado no checkout: zero ocorrências de
///    `rightMouseDown`, `menu(for:)`, `override var menu` ou `validateMenuItem` em
///    `MacTerminalView.swift`. `NSView.rightMouseDown` sobe para `menu(for:)`, que devolve
///    `self.menu` = `nil` — não havia menu para aparecer, com ou sem gesto do SwiftUI por cima.
///    Eu removi um gesto que comia o mouse e disse que consertaria o clique direito; não podia.
///
/// 2. **A plataforma é beta.** macOS 27.0 (26A5388g), e a Apple tem regressão confirmada desde a
///    26.2 (FB21579636) em que `NSHostingView` empilhado deixa de receber eventos de mouse. Onde
///    SwiftUI não garante, AppKit direto na view resolve — e é aqui que a view mora.
public final class TerminalDaFrota: TerminalView, NSMenuItemValidation {

    // MARK: - Mouse

    /// O PRIMEIRO clique com a janela inativa passa a valer.
    ///
    /// O padrão do AppKit é engolir esse clique: ele só ativa a janela. Num app usado ao lado do
    /// navegador — que é exatamente o caso, copiar um código de OAuth e voltar — isso significa que
    /// todo primeiro clique se perde, e o operador conclui que o terminal não responde.
    public override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    // MARK: - Menu de contexto

    /// O menu que o SwiftTerm não oferece.
    ///
    /// Construído por evento, e não guardado em `self.menu`, porque o estado muda: "Copiar" só faz
    /// sentido com seleção, e um item habilitado que não faz nada é o mesmo modo de falha do menu
    /// que existia e não chegava a lugar nenhum.
    public override func menu(for event: NSEvent) -> NSMenu? {
        let m = NSMenu()
        m.autoenablesItems = false

        m.addItem(item("Copiar", #selector(copiarDaFrota(_:)), "c", habilitado: temSelecao))
        m.addItem(item("Colar", #selector(colarDaFrota(_:)), "v", habilitado: temTextoParaColar))
        m.addItem(item("Selecionar tudo", #selector(selecionarTudoDaFrota(_:)), "a"))
        m.addItem(.separator())
        m.addItem(item("Buscar…", #selector(buscarDaFrota(_:)), "f"))
        m.addItem(.separator())
        m.addItem(item("Aumentar fonte", #selector(aumentarFonte(_:)), "+"))
        m.addItem(item("Diminuir fonte", #selector(diminuirFonte(_:)), "-"))
        m.addItem(item("Tamanho original", #selector(fonteOriginalTamanho(_:)), "0"))
        m.addItem(.separator())
        m.addItem(item("Limpar tela", #selector(limparTela(_:)), "k", modificadores: [.command, .shift]))
        return m
    }

    private func item(_ titulo: String, _ acao: Selector, _ tecla: String,
                      modificadores: NSEvent.ModifierFlags = .command,
                      habilitado: Bool = true) -> NSMenuItem {
        let i = NSMenuItem(title: titulo, action: acao, keyEquivalent: tecla)
        i.keyEquivalentModifierMask = modificadores
        // `target = self` de propósito: sem alvo, o item percorre a responder chain — que é
        // exatamente o caminho que estava quebrado (o foco fica na sidebar). O menu nasce NESTA
        // view; ele não deveria precisar procurar o destino.
        i.target = self
        i.isEnabled = habilitado
        return i
    }

    /// Guarda-costas para quem esquecer `autoenablesItems = false`: o AppKit consulta isto.
    /// Vem de `NSMenuItemValidation`, não de `NSView` — daí a conformidade acima, não um `override`.
    public func validateMenuItem(_ item: NSMenuItem) -> Bool {
        switch item.action {
        case #selector(copiarDaFrota(_:)): return temSelecao
        case #selector(colarDaFrota(_:)):  return temTextoParaColar
        default: return true
        }
    }

    /// Há algo selecionado? Copiar sem seleção põe string vazia na área de transferência e APAGA
    /// o que estava lá — destrutivo e silencioso.
    ///
    /// Por `selectedRange()`, que é `open`: o `selection` do SwiftTerm é `internal` e não se
    /// alcança de fora. Menos direto, e é a API que o pacote oferece.
    private var temSelecao: Bool { selectedRange().length > 0 }

    private var temTextoParaColar: Bool {
        textoDaAreaDeTransferencia()?.isEmpty == false
    }

    // MARK: - As ações

    // Passam pelas MESMAS funções do menu principal (`TerminalTools.swift`), que já são testadas.
    // Duplicar a lógica aqui criaria dois caminhos para a mesma ação — e eles divergem.
    @objc private func copiarDaFrota(_ sender: Any?) { _ = terminalCopiar() }
    @objc private func colarDaFrota(_ sender: Any?) { _ = terminalColar() }
    @objc private func selecionarTudoDaFrota(_ sender: Any?) { _ = terminalSelecionarTudo() }
    @objc private func buscarDaFrota(_ sender: Any?) { _ = enviarBusca(.showFindPanel) }

    // MARK: - Foco

    /// Clicar no corpo do terminal reivindica o foco.
    ///
    /// `acceptsFirstResponder` já era `true` no SwiftTerm, mas o foco vinha sendo devolvido à
    /// sidebar (`NSOutlineView`) a cada redesenho. Pedir aqui, no clique, é o gesto explícito do
    /// operador — e vence qualquer disputa automática.
    public override func mouseDown(with event: NSEvent) {
        if window?.firstResponder !== self { window?.makeFirstResponder(self) }
        super.mouseDown(with: event)
    }
}
#endif
