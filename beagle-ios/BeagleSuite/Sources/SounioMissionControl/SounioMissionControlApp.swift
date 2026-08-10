#if os(macOS)
import SwiftUI
import AppKit
import BeagleCore
import BeagleWorkbenchKit

/// SOUNIO MISSION CONTROL — the macOS half of the house.
///
/// Deliberately NOT the Companion. The iPhone app is a personal partner; this is a workshop: a
/// real window, a sidebar, several terminals at once, and screens sized for a desk. They share
/// the same packages (BeagleCore / BeagleWorkbenchKit) and the same backend, and nothing here
/// touches the Companion's surface.
@main
struct SounioMissionControlApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        WindowGroup("Sounio Mission Control") {
            MissionControlWindow()
                .frame(minWidth: 980, minHeight: 640)
        }
        .defaultSize(width: 1280, height: 860)
        .commands {
            // 🚨 SEM ISTO NÃO HÁ COPIAR NEM COLAR, e a causa é estrutural, não do terminal.
            //
            // O `SwiftTerm.TerminalView` JÁ implementa `copy(_:)`, `paste(_:)` e `selectAll(_:)`
            // como `@objc open func` — a responder chain do macOS os encontraria sozinha. O que
            // faltava era o MENU: um app SwiftUI sem grupo `.pasteboard` não tem ⌘C/⌘V ligados a
            // ação nenhuma, e as teclas morrem antes de chegar no terminal.
            //
            // Consequência medida: sem colar, não dá para responder a um prompt de OAuth
            // (`Paste code here if prompted >`), nem colar caminho, nem colar código numa lane.
            // Uma lane ficou presa nesse prompt.
            //
            // `sendAction(to: nil)` percorre a responder chain — é o idioma correto e é o que faz
            // o comando chegar em QUALQUER terminal focado, sem o app saber qual é.
            CommandGroup(replacing: .pasteboard) {
                Button("Copiar") { NSApp.sendAction(#selector(NSText.copy(_:)), to: nil, from: nil) }
                    .keyboardShortcut("c", modifiers: .command)
                Button("Colar") { NSApp.sendAction(#selector(NSText.paste(_:)), to: nil, from: nil) }
                    .keyboardShortcut("v", modifiers: .command)
                Divider()
                Button("Selecionar tudo") { NSApp.sendAction(#selector(NSText.selectAll(_:)), to: nil, from: nil) }
                    .keyboardShortcut("a", modifiers: .command)
            }
            CommandGroup(after: .toolbar) {
                Button("Frota") { NotificationCenter.default.post(name: .missionControlGo, object: Section.frota) }
                    .keyboardShortcut("1", modifiers: .command)
                Button("Oficina") { NotificationCenter.default.post(name: .missionControlGo, object: Section.oficina) }
                    .keyboardShortcut("2", modifiers: .command)
                Button("Sessão") { NotificationCenter.default.post(name: .missionControlGo, object: Section.sessao) }
                    .keyboardShortcut("3", modifiers: .command)
                Button("Terminais") { NotificationCenter.default.post(name: .missionControlGo, object: Section.terminals) }
                    .keyboardShortcut("4", modifiers: .command)
            }
        }
    }
}

extension Notification.Name {
    static let missionControlGo = Notification.Name("missionControlGo")
}

/// A package executable is not a bundled app, so it starts as a background process with no menu
/// bar and no focus. Claiming `.regular` makes it behave like a real Mac app while this lives
/// outside an .app bundle.
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        setbuf(stdout, nil)   // a GUI process redirected to a file would buffer away its own logs
        NSApplication.shared.setActivationPolicy(.regular)
        NSApplication.shared.activate(ignoringOtherApps: true)
        Task { await Selftest.run() }
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}

enum Section: String, CaseIterable, Identifiable, Hashable {
    case frota, oficina, sessao, terminals
    var id: String { rawValue }

    /// Each entry names the operational question it answers — if a section cannot state one,
    /// it does not belong in the sidebar.
    var title: String {
        switch self {
        case .frota:     return "Frota"
        case .oficina:   return "Oficina"
        case .sessao:    return "Sessão"
        case .terminals: return "Terminais"
        }
    }
    var question: String {
        switch self {
        case .frota:     return "quem precisa de você"
        case .oficina:   return "está verde? o que quebrou?"
        case .sessao:    return "conversar com uma lane"
        case .terminals: return "entrar numa lane"
        }
    }
    var icon: String {
        switch self {
        case .frota:     return "dot.radiowaves.left.and.right"
        case .oficina:   return "wrench.and.screwdriver"
        case .sessao:    return "bubble.left.and.text.bubble.right"
        case .terminals: return "apple.terminal"
        }
    }
}

struct MissionControlWindow: View {
    @State private var section: Section = .frota
    @State private var openLane: String?

    private static let canvas = Color(red: 0.043, green: 0.055, blue: 0.086)

    var body: some View {
        NavigationSplitView {
            // `List(data, selection:)` binds the DATA'S ID (a String here), so binding it to a
            // `Section?` silently mismatched and the sidebar drove nothing. The ForEach + .tag
            // form is the one that selects by value.
            List(selection: $section) {
                ForEach(Section.allCases) { s in
                    Label {
                        VStack(alignment: .leading, spacing: 1) {
                            Text(s.title).font(.body)
                            Text(s.question)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    } icon: {
                        Image(systemName: s.icon)
                    }
                    .tag(s)
                }
            }
            .navigationSplitViewColumnWidth(min: 210, ideal: 230, max: 300)
        } detail: {
            Group {
                switch section {
                case .frota:
                    FrotaView(onOpenLane: { lane in
                        openLane = lane
                        section = .terminals
                    })
                case .oficina:
                    OficinaView()
                case .sessao:
                    // A lane de protocolo tem CONVERSA; a de terminal tem scrollback. As duas categorias
                    // convivem de propósito — nenhuma das 11 muda de natureza sem ele mandar.
                    SessionView(lane: FleetEndpoint.loomdLanes.first ?? "loom-1")
                case .terminals:
                    FleetTerminalsView(initialAgent: openLane)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Self.canvas)
        }
        .onReceive(NotificationCenter.default.publisher(for: .missionControlGo)) { note in
            if let s = note.object as? Section { section = s }
        }
        .task {
            // `-beagleOpen <seção>` abre direto numa tela: é como um screenshot ou um smoke test
            // alcança uma seção sem depender de clique.
            #if DEBUG
            if let raw = UserDefaults.standard.string(forKey: "beagleOpen"),
               let s = Section(rawValue: raw.lowercased()) {
                section = s
            }
            #endif
        }
    }
}
#endif
