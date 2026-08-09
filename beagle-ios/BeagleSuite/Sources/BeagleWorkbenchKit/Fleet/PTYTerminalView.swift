#if os(iOS) || os(macOS)
import SwiftUI
import SwiftTerm
import BeagleCore
#if os(iOS)
import UIKit
public typealias _PlatformViewRepresentable = UIViewRepresentable
#else
public typealias _PlatformViewRepresentable = NSViewRepresentable
#endif

/// Bridges a SwiftTerm `TerminalView` to a `PTYClient` (Loom `/ws/loom`).
public struct PTYTerminalView: _PlatformViewRepresentable {
    private let client: PTYClient

    public init(client: PTYClient) { self.client = client }

    public func makeCoordinator() -> Coordinator { Coordinator(client: client) }

    #if os(iOS)
    public func makeUIView(context: Context) -> TerminalView { context.coordinator.makeTerminal() }
    public func updateUIView(_ uiView: TerminalView, context: Context) {}
    #else
    public func makeNSView(context: Context) -> TerminalView { context.coordinator.makeTerminal() }
    public func updateNSView(_ nsView: TerminalView, context: Context) {}
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
        public func setTerminalTitle(source: TerminalView, title: String) {}
        public func hostCurrentDirectoryUpdate(source: TerminalView, directory: String?) {}
        public func scrolled(source: TerminalView, position: Double) {}
        public func requestOpenLink(source: TerminalView, link: String, params: [String: String]) {}
        public func clipboardCopy(source: TerminalView, content: Data) {}
        public func rangeChanged(source: TerminalView, startY: Int, endY: Int) {}
        public func bell(source: TerminalView) {}
    }
}
#endif
