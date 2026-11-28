#if os(macOS)
import AppKit
import SwiftUI
import SwiftTerm
import BeagleCore

/// A área de terminal da aba Terminais — UM container AppKit persistente, com um terminal por
/// lane ABERTA guardado num cache. Trocar de lane é `addSubview`/`removeFromSuperview` dentro
/// do AppKit; o SwiftUI nunca vê a troca.
///
/// 🚨 Existe porque o `.id(store.activeAgent)` forçando remount (a versão anterior desta tela)
/// media certo o clique (log confirma toda troca, ida e volta) mas desenhava lixo: o terminal
/// NOVO é uma `TerminalDaFrota` vazia, e `PTYClient.connect()` é um no-op quando o client já
/// está conectado — o `subscribe` que faz o broker reenviar o scrollback só roda na PRIMEIRA
/// conexão (ver `PTYClient.swift`). Sem replay, o terminal recém-montado só recebe fatias de
/// sequência ANSI no meio do stream, num buffer virgem. "Imagem bagunçada" não era crossfade —
/// era um terminal desenhando o que sobrou de um stream que ele nunca viu começar.
///
/// A cura é não remontar NUNCA: um terminal, uma vez criado por lane, vive enquanto a lane
/// estiver aberta. Trocar de lane troca qual `TerminalDaFrota` está de subview — o resto (client,
/// conexão WebSocket, buffer de scrollback do próprio SwiftTerm) nunca é tocado. É a mesma receita
/// que já resolveu a barra lateral (`SidebarNativeView`) e os chips (`AgentTabBarNative`): sair da
/// composição SwiftUI para AppKit direto.
public struct MultiLaneTerminalView: NSViewRepresentable {
    let store: FleetTerminalStore

    public init(store: FleetTerminalStore) { self.store = store }

    public func makeCoordinator() -> Coordinator { Coordinator() }

    public func makeNSView(context: Context) -> NSView {
        let container = NSView()
        container.wantsLayer = true
        return container
    }

    public func updateNSView(_ container: NSView, context: Context) {
        let coord = context.coordinator
        // Lanes fechadas soltam o terminal e o client — `close()` do store já derruba o socket;
        // aqui só liberamos a `TerminalDaFrota` que sobraria presa no cache.
        coord.podar(mantendo: Set(store.opened))

        let ativo = store.activeAgent
        guard store.opened.contains(ativo) else {
            if !container.subviews.isEmpty { container.subviews.forEach { $0.removeFromSuperview() } }
            return
        }
        let tv = coord.terminal(para: ativo, client: store.client(for: ativo))
        print("[chipbar3] updateNSView ativo=\(ativo) subviewsAntes=\(container.subviews.count) tvIdentical=\(container.subviews.first === tv) containerBounds=\(container.bounds)")
        if container.subviews.first !== tv {
            container.subviews.forEach { $0.removeFromSuperview() }
            tv.frame = container.bounds
            tv.autoresizingMask = [.width, .height]
            container.addSubview(tv)
            print("[chipbar3] swapped in tv for \(ativo), tvFrame=\(tv.frame)")
            // 🚨 SEM ISTO a lane trocava de verdade por baixo (log confirma `activeAgent`
            // certo a cada clique) mas a TELA continuava mostrando a lane anterior — medido:
            // um `TerminalDaFrota` recolocado como subview depois de ter sido removida não se
            // redesenha sozinho neste beta; a camada (`wantsLayer`) fica com o conteúdo antigo
            // em cache até algo pedir redesenho explícito.
            tv.needsLayout = true
            tv.needsDisplay = true
            tv.layer?.setNeedsDisplay()
            container.needsDisplay = true
        }

        // Mesma reivindicação de first responder e as mesmas guardas de `PTYTerminalView` — ver
        // lá o porquê de cada uma (gaveta, janela não-chave, `set -e` do async reconferido).
        guard let window = container.window,
              window.isKeyWindow, window.attachedSheet == nil,
              window.firstResponder !== tv else { return }
        DispatchQueue.main.async { [weak tv, weak window] in
            guard let tv, let window, window.isKeyWindow, window.attachedSheet == nil,
                  window.firstResponder !== tv else { return }
            print("[chipbar2] MultiLaneTerminalView claiming firstResponder for active=\(ativo)")
            window.makeFirstResponder(tv)
        }
    }

    @MainActor
    public final class Coordinator: NSObject {
        private var terminais: [String: TerminalDaFrota] = [:]
        private var pontes: [String: PTYTerminalBridge] = [:]

        func terminal(para agent: String, client: PTYClient) -> TerminalDaFrota {
            if let existente = terminais[agent] { return existente }

            let tv = TerminalDaFrota(frame: .zero)
            let ponte = PTYTerminalBridge(client: client)
            tv.terminalDelegate = ponte
            pontes[agent] = ponte

            tv.nativeBackgroundColor = NSColor(srgbRed: 0.106, green: 0.078, blue: 0.149, alpha: 1)
            tv.nativeForegroundColor = NSColor(white: 0.92, alpha: 1)

            client.onBytes = { [weak tv] bytes in tv?.feed(byteArray: bytes[...]) }
            client.connect()
            let cols = tv.getTerminal().cols, rows = tv.getTerminal().rows
            if cols > 0 && rows > 0 { client.resize(cols: cols, rows: rows) }

            terminais[agent] = tv
            return tv
        }

        /// Solta o terminal (e sua ponte) de qualquer lane que não esteja mais em `store.opened`
        /// — `FleetTerminalStore.close(_:)` já derruba o socket/client; isto só evita um cache
        /// de `NSView` crescendo pra sempre.
        func podar(mantendo abertas: Set<String>) {
            for chave in terminais.keys where !abertas.contains(chave) {
                terminais[chave]?.removeFromSuperview()
                terminais.removeValue(forKey: chave)
                pontes.removeValue(forKey: chave)
            }
        }
    }
}

/// O mesmo `TerminalViewDelegate` que `PTYTerminalView.Coordinator` implementa, extraído pra uma
/// classe própria porque aqui existe UMA ponte por lane (várias vivas ao mesmo tempo), não uma
/// por view montada. Mesmo comportamento, mesmos comentários de por-quê — ver `PTYTerminalView.swift`.
@MainActor
final class PTYTerminalBridge: NSObject, @preconcurrency TerminalViewDelegate {
    let client: PTYClient
    init(client: PTYClient) { self.client = client }

    func send(source: TerminalView, data: ArraySlice<UInt8>) {
        client.send(Data(data))
    }
    func sizeChanged(source: TerminalView, newCols: Int, newRows: Int) {
        client.resize(cols: newCols, rows: newRows)
    }
    func setTerminalTitle(source: TerminalView, title: String) {
        let t = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return }
        client.title = t
    }
    func hostCurrentDirectoryUpdate(source: TerminalView, directory: String?) {}
    func scrolled(source: TerminalView, position: Double) {}
    func requestOpenLink(source: TerminalView, link: String, params: [String: String]) {
        guard let url = URL(string: link),
              let esquema = url.scheme?.lowercased(),
              esquema == "http" || esquema == "https" else { return }
        NSWorkspace.shared.open(url)
    }
    func clipboardCopy(source: TerminalView, content: Data) {
        guard let texto = String(data: content, encoding: .utf8), !texto.isEmpty else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(texto, forType: .string)
    }
    func rangeChanged(source: TerminalView, startY: Int, endY: Int) {}
    func bell(source: TerminalView) {
        NSSound.beep()
        NSApp.requestUserAttention(.informationalRequest)
        client.recordBell()
    }
}
#endif
