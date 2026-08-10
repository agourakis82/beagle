#if os(iOS) || os(macOS)
import SwiftUI
import SwiftTerm
#if canImport(AppKit)
import AppKit
#endif
import BeagleCore
#if os(iOS)
import UIKit
public typealias _PlatformViewRepresentable = UIViewRepresentable
#else
public typealias _PlatformViewRepresentable = NSViewRepresentable
#endif

/// Bridges a SwiftTerm `TerminalView` to a `PTYClient` (Loom `/ws/loom`).
public struct PTYTerminalView: _PlatformViewRepresentable {
    /// Esta é a lane que ele está VENDO?
    ///
    /// 🚨 MEDIDO: `updateNSView` roda para TODOS os terminais montados — a pilha mantém as lanes
    /// abertas vivas com `opacity 0`, e a última a atualizar ganhava o registro. Com uma lane só
    /// (meu teste) funcionava; com várias, o ⌘V ia para uma lane INVISÍVEL e o texto sumia num
    /// terminal que ele não estava olhando. Registrar só o ativo é o que torna "o terminal ativo"
    /// verdade em vez de aproximação.
    public var ativo: Bool = true

    private let client: PTYClient

    public init(client: PTYClient, ativo: Bool = true) {
        self.client = client
        self.ativo = ativo
    }

    public func makeCoordinator() -> Coordinator { Coordinator(client: client) }

    #if os(iOS)
    public func makeUIView(context: Context) -> TerminalView { context.coordinator.makeTerminal() }
    public func updateUIView(_ uiView: TerminalView, context: Context) {}
    #else
    /// A decisão "esta view reivindica o destino dos comandos?", separada do ciclo de vida do
    /// SwiftUI. Sem esta costura, ela só existiria dentro de `makeNSView`/`updateNSView` — e
    /// decisão que só se alcança montando uma hierarquia não é decisão testável. Foi exatamente
    /// esta regra que quebrou em produção enquanto os testes passavam.
    public func registrarSeAtivo(_ v: TerminalView) {
        if ativo { TerminalAtivo.registrar(v) }
    }

    public func makeNSView(context: Context) -> TerminalView {
        let v = context.coordinator.makeTerminal()
        registrarSeAtivo(v)
        return v
    }

    /// 🚨 O TERMINAL PRECISA VIRAR FIRST RESPONDER, e nada fazia isso.
    ///
    /// Medido no app instalado: `AXFocusedUIElement` era NULO — não havia foco em elemento nenhum.
    /// `NSApp.sendAction(to: nil)` percorre a responder chain a partir do FOCO, então ⌘C/⌘V/⌘F
    /// existiam no menu, com atalho ligado, e não chegavam a lugar nenhum. O menu estava certo; o
    /// foco é que nunca ia para o terminal.
    ///
    /// Isso também explica por que digitar podia parecer funcionar e colar não: cliques vão para a
    /// view sob o cursor, mas comando de menu só segue a chain do first responder.
    ///
    /// Feito em `updateNSView` e não só na criação porque a aba TROCA de terminal: cada vez que
    /// ele muda de lane, a view que aparece precisa reivindicar o foco de novo. E a guarda de
    /// `firstResponder != nsView` evita reivindicar a cada redesenho — pedir foco em laço briga
    /// com qualquer campo de texto que exista na mesma janela.
    public func updateNSView(_ nsView: TerminalView, context: Context) {
        guard let janela = nsView.window, janela.firstResponder !== nsView else { return }
        // Assíncrono: durante o `update` a hierarquia ainda está sendo montada, e um
        // `makeFirstResponder` aqui pode ser desfeito pelo próprio ciclo de layout.
        // Só a lane VISÍVEL reivindica: registrar uma invisível mandaria o ⌘V para um terminal
        // que ele não está olhando — e o texto sumiria sem erro nenhum.
        guard ativo else { return }
        registrarSeAtivo(nsView)
        DispatchQueue.main.async { [weak nsView] in
            guard let v = nsView, let w = v.window, w.firstResponder !== v else { return }
            w.makeFirstResponder(v)
        }
    }
    #endif

    @MainActor
    public final class Coordinator: NSObject, @preconcurrency TerminalViewDelegate {
        let client: PTYClient
        weak var terminal: TerminalView?

        init(client: PTYClient) { self.client = client }

        func makeTerminal() -> TerminalView {
            let tv = TerminalView(frame: .zero)
            tv.terminalDelegate = self
            terminal = tv
            // Cockpit identity: plum canvas, light text. This used to be iOS-only, so the Mac
            // terminal sat on SwiftTerm's default white inside a dark window — the one surface
            // in Mission Control that did not belong to the room.
            #if os(iOS)
            tv.nativeBackgroundColor = UIColor(red: 0.106, green: 0.078, blue: 0.149, alpha: 1)
            tv.nativeForegroundColor = UIColor(white: 0.92, alpha: 1)
            #else
            tv.nativeBackgroundColor = NSColor(srgbRed: 0.106, green: 0.078, blue: 0.149, alpha: 1)
            tv.nativeForegroundColor = NSColor(white: 0.92, alpha: 1)
            #endif
            // Lane output -> terminal (main actor; PTYClient is @MainActor)
            client.onBytes = { [weak tv] bytes in
                tv?.feed(byteArray: bytes[...])
            }
            client.connect()
            // Tell the lane our REAL viewport immediately. The broker's attach starts at a
            // hard-coded 120x34 (adaptedSession.mjs), and tmux sizes a window to its smallest
            // client — so an invented size briefly reshapes the pane every other client is
            // looking at. `sizeChanged` corrects it, but only after the first layout pass.
            let cols = tv.getTerminal().cols, rows = tv.getTerminal().rows
            if cols > 0 && rows > 0 { client.resize(cols: cols, rows: rows) }
            return tv
        }

        // Terminal input -> Loom `input` frame
        public func send(source: TerminalView, data: ArraySlice<UInt8>) {
            client.send(Data(data))
        }

        // Resize: terminal -> Loom `resize` frame
        public func sizeChanged(source: TerminalView, newCols: Int, newRows: Int) {
            client.resize(cols: newCols, rows: newRows)
        }

        // Unused delegate hooks (required by the protocol)
        /// O título que o processo remoto anuncia (OSC 0/2) — o `tmux` publica ali o que a lane
        /// está fazendo. Estava descartado; agora o chip da aba pode mostrá-lo.
        public func setTerminalTitle(source: TerminalView, title: String) {
            let t = title.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !t.isEmpty else { return }
            client.titulo = t
        }
        public func hostCurrentDirectoryUpdate(source: TerminalView, directory: String?) {}
        public func scrolled(source: TerminalView, position: Double) {}
        /// Um link clicado no terminal. Estava vazio — e agentes imprimem URL o tempo todo (PR,
        /// build, issue). Clicar não fazia nada, em silêncio.
        ///
        /// ⚠️ Só `http`/`https` são abertos. O terminal exibe texto de PROCESSO REMOTO: um
        /// `file://` abriria caminho da máquina local a partir de algo que veio de fora, e
        /// esquemas customizados podem disparar outro app. Aqui a regra é a mesma do resto: o que
        /// vem de fora não escolhe o que a máquina faz.
        public func requestOpenLink(source: TerminalView, link: String, params: [String: String]) {
            guard let url = URL(string: link),
                  let esquema = url.scheme?.lowercased(),
                  esquema == "http" || esquema == "https" else { return }
            #if canImport(AppKit)
            NSWorkspace.shared.open(url)
            #endif
        }
        /// O programa REMOTO pedindo para copiar (OSC 52). Estava vazio: um `tmux` ou um agente
        /// que copia para a área de transferência não chegava a lugar nenhum, em silêncio.
        public func clipboardCopy(source: TerminalView, content: Data) {
            guard let texto = String(data: content, encoding: .utf8), !texto.isEmpty else { return }
            #if canImport(AppKit)
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(texto, forType: .string)
            #elseif canImport(UIKit)
            UIPasteboard.general.string = texto
            #endif
        }
        public func rangeChanged(source: TerminalView, startY: Int, endY: Int) {}
        /// O SINO. Vazio até agora, e é o aviso mais útil que existe aqui: um agente que termina
        /// ou que precisa de decisão toca o sino, e o terminal engolia.
        ///
        /// `NSSound.beep()` e não som próprio: o sistema já respeita o volume e o modo silencioso
        /// que ele escolheu. Um som nosso ignoraria os dois.
        public func bell(source: TerminalView) {
            #if canImport(AppKit)
            NSSound.beep()
            NSApp.requestUserAttention(.informationalRequest)
            #endif
            client.tocouSino()
        }
    }
}
#endif
