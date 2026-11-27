#if os(macOS)
import AppKit
import SwiftUI

/// A barra lateral do Mission Control, em AppKit de verdade — não SwiftUI.
///
/// 🚨 Existe porque o clique na barra lateral (primeiro `List(selection:)`, depois `Button`)
/// trava DEPOIS que um terminal é tocado uma vez — medido: a partir daí `AXSelected` da linha
/// nem mudava mais com o clique. É a MESMA regressão de macOS 26.2 (`NSHostingView` empilhado
/// engolindo evento de mouse) que já forçou `TerminalDaFrota` a existir — só que aqui ela vaza
/// pra fora do terminal e trava o resto da janela. Onde SwiftUI não garante entrega de evento,
/// AppKit direto resolve — mesma lição, aplicada de novo.
///
/// `mouseDown` é tratado AQUI, na própria `NSView`, sem passar pela ponte de hospedagem do
/// SwiftUI — é essa ponte, empilhada com a do terminal, que estava comendo o evento.
final class SidebarNativeView: NSView {
    var sections: [Section] = [] { didSet { needsLayout = true; needsDisplay = true } }
    var selected: Section? { didSet { needsDisplay = true } }
    var onSelect: ((Section) -> Void)?

    private var rowFrames: [(section: Section, frame: NSRect)] = []
    private let rowHeight: CGFloat = 46
    private var hovered: Section?

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func layout() {
        super.layout()
        rowFrames = sections.enumerated().map { (i, s) in
            (s, NSRect(x: 8, y: CGFloat(i) * rowHeight + 8, width: bounds.width - 16, height: rowHeight - 6))
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.clear.setFill()
        dirtyRect.fill()
        for (s, frame) in rowFrames {
            let bg: NSColor = s == selected
                ? NSColor.controlAccentColor.withAlphaComponent(0.22)
                : (s == hovered ? NSColor.labelColor.withAlphaComponent(0.06) : .clear)
            bg.setFill()
            NSBezierPath(roundedRect: frame, xRadius: 6, yRadius: 6).fill()

            if let img = NSImage(systemSymbolName: s.icon, accessibilityDescription: s.title) {
                var img2 = img
                img2 = img2.withSymbolConfiguration(.init(pointSize: 13, weight: .medium)) ?? img
                img2.isTemplate = true
                let iconRect = NSRect(x: frame.minX + 8, y: frame.minY + (frame.height - 16) / 2, width: 16, height: 16)
                NSColor.labelColor.withAlphaComponent(0.85).set()
                img2.draw(in: iconRect)
            }

            let titleAttrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 13, weight: .regular),
                .foregroundColor: NSColor.labelColor,
            ]
            (s.title as NSString).draw(at: NSPoint(x: frame.minX + 32, y: frame.minY + 6), withAttributes: titleAttrs)

            let subAttrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 10, weight: .regular),
                .foregroundColor: NSColor.secondaryLabelColor,
            ]
            (s.question as NSString).draw(at: NSPoint(x: frame.minX + 32, y: frame.minY + 24), withAttributes: subAttrs)
        }
    }

    override func mouseDown(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        guard let hit = rowFrames.first(where: { $0.frame.contains(p) }) else { return }
        selected = hit.section
        onSelect?(hit.section)
    }

    override func mouseMoved(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        let h = rowFrames.first(where: { $0.frame.contains(p) })?.section
        if h != hovered { hovered = h; needsDisplay = true }
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: bounds, options: [.mouseMoved, .activeInKeyWindow, .inVisibleRect],
                                        owner: self, userInfo: nil))
    }

    // MARK: - Acessibilidade
    // Cada linha vira um elemento de botão de verdade para VoiceOver — sem isto um NSView
    // desenhado à mão é invisível para leitor de tela, o mesmo apagamento que o app já evita em
    // outras telas (ver os `.accessibilityLabel` explícitos na Frota).
    override func accessibilityChildren() -> [Any]? {
        rowFrames.map { s, frame in
            let el = NSAccessibilityElement()
            el.setAccessibilityRole(.button)
            el.setAccessibilityLabel("\(s.title), \(s.question)")
            el.setAccessibilityFrameInParentSpace(frame)
            el.setAccessibilityParent(self)
            el.setAccessibilitySelected(s == selected)
            return el
        }
    }
    override func isAccessibilityElement() -> Bool { false }
}

/// A ponte SwiftUI — fina de propósito. Toda a lógica de clique/desenho mora na `NSView` acima;
/// isto só espelha `sections`/`selection` para dentro e fora.
struct SidebarNative: NSViewRepresentable {
    let sections: [Section]
    @Binding var selection: Section

    init(sections: [Section], selection: Binding<Section>) {
        self.sections = sections
        self._selection = selection
    }

    func makeNSView(context: Context) -> SidebarNativeView {
        let v = SidebarNativeView()
        v.sections = sections
        v.selected = selection
        v.onSelect = { selection = $0 }
        return v
    }

    func updateNSView(_ v: SidebarNativeView, context: Context) {
        v.sections = sections
        // Só escreve quando DIVERGE do que a NSView já tem: escrever sempre faria todo re-render
        // do SwiftUI (inclusive de OUTRA seção do app) invalidar o `selected` no meio de um
        // clique que a própria NSView acabou de aplicar — a NSView é quem manda no seu estado
        // visual; o binding só entra quando a mudança veio de FORA (⌘1-4, notificação).
        if v.selected != selection { v.selected = selection }
    }
}
#endif
