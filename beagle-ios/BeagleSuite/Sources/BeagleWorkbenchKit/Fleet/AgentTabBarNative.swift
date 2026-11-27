#if os(macOS)
import AppKit
import SwiftUI

/// Um chip da barra de lanes, já resolvido em valores prontos pra desenhar — a `NSView` não
/// conhece `FleetTerminalStore`, só isto.
public struct AgentChip: Equatable {
    public let agent: String
    public let opened: Bool
    public let active: Bool
    public let stateColor: Color
    public let familyColor: Color
    public let titulo: String?
    public let hasUnread: Bool
    public let chamou: Bool

    public init(agent: String, opened: Bool, active: Bool, stateColor: Color, familyColor: Color,
                titulo: String?, hasUnread: Bool, chamou: Bool) {
        self.agent = agent
        self.opened = opened
        self.active = active
        self.stateColor = stateColor
        self.familyColor = familyColor
        self.titulo = titulo
        self.hasUnread = hasUnread
        self.chamou = chamou
    }
}

/// A barra de lanes da aba Terminais, em AppKit de verdade.
///
/// 🚨 Existe pela MESMA razão de `SidebarNativeView` (Mission Control): clicar num chip abre a
/// lane a primeira vez, e a partir daí clicar em QUALQUER outro chip pra trocar de lane não
/// funciona mais — medido e relatado. Aqui é o pior lugar possível pra essa regressão de mouse
/// do macOS 26.2 acontecer: os chips ficam ao lado do `ZStack` de `PTYTerminalView`s empilhados
/// que já é a causa raiz documentada (`TerminalDaFrota.swift`). SwiftUI puro não escapa dela —
/// só sair pra uma `NSView` com `mouseDown` próprio resolve.
final class AgentTabBarContentView: NSView {
    var chips: [AgentChip] = [] { didSet { rebuild() } }
    var onSelect: ((String) -> Void)?

    private var chipFrames: [(agent: String, frame: NSRect)] = []
    private let chipHeight: CGFloat = 28
    private let hPad: CGFloat = 12
    private let gap: CGFloat = 8

    override var isFlipped: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    private func rebuild() {
        var x: CGFloat = 8
        var frames: [(String, NSRect)] = []
        for c in chips {
            let w = widthFor(c)
            frames.append((c.agent, NSRect(x: x, y: 6, width: w, height: chipHeight)))
            x += w + gap
        }
        chipFrames = frames
        let newWidth = max(x + 8, superview?.bounds.width ?? x + 8)
        if newWidth != frame.width {
            // 🚨 Preserva a posição de rolagem ao redimensionar. Sem isto, cada `chips = ...`
            // (o store é `@Observable` e re-renderiza a cada byte de saída de QUALQUER lane —
            // várias vezes por segundo) reatribuía `frame.size` e o `NSClipView` às vezes
            // recalculava a origem para 0 no meio do gesto: clicar num chip à ESQUERDA do
            // ativo (uma lane já rolada pra fora à esquerda) media a posição do mouse contra um
            // conteúdo que tinha acabado de "pular" de volta pra x=0 — o próximo clique parecia
            // morto porque estava medindo o chip errado. Chip à direita do ativo raramente
            // precisa rolar (cabe na janela), por isso só o lado esquerdo doía.
            let offset = enclosingScrollView?.contentView.bounds.origin
            frame.size.width = newWidth
            if let offset { enclosingScrollView?.contentView.scroll(to: offset) }
        }
        needsDisplay = true
    }

    private func widthFor(_ c: AgentChip) -> CGFloat {
        let nameW = (c.agent as NSString)
            .size(withAttributes: [.font: NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)]).width
        var w = nameW + hPad * 2
        if c.opened { w += 12 }               // ponto de estado
        if c.chamou || c.hasUnread { w += 6 }  // respiro pro badge
        return w
    }

    override func draw(_ dirtyRect: NSRect) {
        for (agent, frame) in chipFrames {
            guard let c = chips.first(where: { $0.agent == agent }) else { continue }
            let path = NSBezierPath(roundedRect: frame, xRadius: frame.height / 2, yRadius: frame.height / 2)
            NSColor(c.active ? Color(red: 1.0, green: 0.76, blue: 0.27).opacity(0.22)
                              : Color.white.opacity(0.06)).setFill()
            path.fill()
            if c.active {
                NSColor(Color(red: 1.0, green: 0.76, blue: 0.27).opacity(0.6)).setStroke()
                path.lineWidth = 1
                path.stroke()
            }

            var tx = frame.minX + hPad
            if c.opened {
                NSColor(c.stateColor).setFill()
                let dot = NSRect(x: tx, y: frame.midY - 3, width: 6, height: 6)
                NSBezierPath(ovalIn: dot).fill()
                tx += 12
            }
            let attrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.monospacedSystemFont(ofSize: 11, weight: .regular),
                .foregroundColor: NSColor(Color.white.opacity(0.92)),
            ]
            (agent as NSString).draw(at: NSPoint(x: tx, y: frame.minY + 7), withAttributes: attrs)

            if c.chamou || c.hasUnread {
                NSColor(Color(red: 1.0, green: 0.76, blue: 0.27)).setFill()
                let b = NSRect(x: frame.maxX - 6, y: frame.minY - 2, width: 8, height: 8)
                NSBezierPath(ovalIn: b).fill()
            }
        }
    }

    override func mouseDown(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        let hit = chipFrames.first(where: { $0.frame.contains(p) })
        print("[chipbar2] mouseDown p=\(p) hit=\(hit?.agent ?? "NENHUM") window=\(window?.title ?? "nil") key=\(window?.isKeyWindow ?? false)")
        guard let hit else { return }
        onSelect?(hit.agent)
    }
}

/// A ponte SwiftUI. `NSScrollView` de verdade para o scroll horizontal — não um `ScrollView`
/// do SwiftUI por cima, que reintroduziria a mesma ponte de hospedagem.
public struct AgentTabBarNative: NSViewRepresentable {
    let chips: [AgentChip]
    let onSelect: (String) -> Void

    public init(chips: [AgentChip], onSelect: @escaping (String) -> Void) {
        self.chips = chips
        self.onSelect = onSelect
    }

    public func makeNSView(context: Context) -> NSScrollView {
        let content = AgentTabBarContentView(frame: .zero)
        content.onSelect = onSelect

        let scroll = NSScrollView()
        scroll.hasHorizontalScroller = true
        scroll.hasVerticalScroller = false
        scroll.drawsBackground = false
        scroll.documentView = content
        scroll.automaticallyAdjustsContentInsets = false
        return scroll
    }

    public func updateNSView(_ scroll: NSScrollView, context: Context) {
        guard let content = scroll.documentView as? AgentTabBarContentView else { return }
        // Só escreve quando MUDA de verdade — o store dispara re-render a cada byte de saída de
        // QUALQUER lane, e reatribuir o mesmo array sempre disparava `rebuild()` à toa.
        if content.chips != chips { content.chips = chips }
        content.frame.size.height = scroll.bounds.height
    }
}
#endif
