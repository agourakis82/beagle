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
            CommandGroup(after: .toolbar) {
                Button("Frota") { NotificationCenter.default.post(name: .missionControlGo, object: Section.frota) }
                    .keyboardShortcut("1", modifiers: .command)
                Button("Oficina") { NotificationCenter.default.post(name: .missionControlGo, object: Section.oficina) }
                    .keyboardShortcut("2", modifiers: .command)
                Button("Terminais") { NotificationCenter.default.post(name: .missionControlGo, object: Section.terminals) }
                    .keyboardShortcut("3", modifiers: .command)
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
        NSApplication.shared.setActivationPolicy(.regular)
        NSApplication.shared.activate(ignoringOtherApps: true)
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}

enum Section: String, CaseIterable, Identifiable, Hashable {
    case frota, oficina, terminals
    var id: String { rawValue }

    /// Each entry names the operational question it answers — if a section cannot state one,
    /// it does not belong in the sidebar.
    var title: String {
        switch self {
        case .frota:     return "Frota"
        case .oficina:   return "Oficina"
        case .terminals: return "Terminais"
        }
    }
    var question: String {
        switch self {
        case .frota:     return "quem precisa de você"
        case .oficina:   return "está verde? o que quebrou?"
        case .terminals: return "entrar numa lane"
        }
    }
    var icon: String {
        switch self {
        case .frota:     return "dot.radiowaves.left.and.right"
        case .oficina:   return "wrench.and.screwdriver"
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
            List(Section.allCases, selection: $section) { s in
                NavigationLink(value: s) {
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
    }
}
#endif
