#if os(iOS) || os(macOS)
import SwiftUI
import BeagleCore
#if canImport(UIKit)
import UIKit
#endif

/// Fleet Terminals screen: status-tinted agent picker (with unread badges) + a ZStack of
/// all *opened* terminals (kept mounted; only the active shown) so switching never tears
/// down a live SwiftTerm buffer. Swipe to switch agents, ⌘K quick switcher (Mac/iPad),
/// haptics, and foreground reconnect.
public struct FleetTerminalsView: View {
    @State private var store = FleetTerminalStore()
    @State private var showSwitcher = false
    @Environment(\.scenePhase) private var scenePhase

    /// A lane to jump straight to (the Frota handing over "open this one"). Nil = last active.
    private let initialAgent: String?

    public init(initialAgent: String? = nil) { self.initialAgent = initialAgent }

    private static let canvas = Color(red: 0.106, green: 0.078, blue: 0.149)   // #1b1426
    private static let amber  = Color(red: 1.0, green: 0.76, blue: 0.27)
    private static let claude = Color(red: 1.0, green: 0.82, blue: 0.40)
    private static let codex  = Color(red: 0.20, green: 0.88, blue: 0.78)
    private static let vendor = Color(red: 1.0, green: 0.57, blue: 0.40)

    public var body: some View {
        VStack(spacing: 0) {
            agentBar
            statusLine
            Divider().overlay(Color.white.opacity(0.08))
            terminals
        }
        .background(Self.canvas)
        .onAppear { store.open(initialAgent ?? store.activeAgent) }
        .onChange(of: initialAgent) { _, lane in if let lane { store.open(lane) } }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { store.reconnectStale() }
        }
        .background(switcherShortcut)
        .sheet(isPresented: $showSwitcher) { agentSwitcher }
        .navigationTitle("Fleet")
    }

    private var terminals: some View {
        ZStack {
            ForEach(store.opened, id: \.self) { agent in
                PTYTerminalView(client: store.client(for: agent))
                    .opacity(agent == store.activeAgent ? 1 : 0)
                    .allowsHitTesting(agent == store.activeAgent)
            }
            if store.opened.isEmpty {
                ContentUnavailableView("Pick an agent", systemImage: "terminal")
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Self.canvas)
        .contentShape(Rectangle())
        // Decisive horizontal swipe switches agents; simultaneous so SwiftTerm still scrolls.
        .simultaneousGesture(
            DragGesture(minimumDistance: 30)
                .onEnded { v in
                    let dx = v.translation.width, dy = v.translation.height
                    if abs(dx) > 80, abs(dx) > abs(dy) * 1.5 {
                        store.cycle(dx < 0 ? 1 : -1)
                        haptic()
                    }
                }
        )
    }

    private var agentBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(store.agents, id: \.self) { agent in
                    chip(agent)
                }
            }
            .padding(.horizontal, 12).padding(.vertical, 8)
        }
        .background(Self.canvas)
    }

    private func chip(_ agent: String) -> some View {
        let active = agent == store.activeAgent
        return Button {
            store.open(agent); haptic()
        } label: {
            HStack(spacing: 6) {
                if store.opened.contains(agent) {
                    Circle().fill(stateColor(store.state(for: agent))).frame(width: 7, height: 7)
                }
                Text(agent).font(.system(.caption, design: .monospaced))
            }
            .padding(.horizontal, 10).padding(.vertical, 6)
            .background(active ? Self.amber.opacity(0.22) : Color.white.opacity(0.06))
            .overlay(Capsule().stroke(active ? Self.amber.opacity(0.6) : .clear, lineWidth: 1))
            .clipShape(Capsule())
            .overlay(alignment: .topTrailing) {
                if store.hasUnread(agent) {
                    Circle().fill(Self.amber)
                        .frame(width: 8, height: 8)
                        .overlay(Circle().stroke(Self.canvas, lineWidth: 1.5))
                        .offset(x: 3, y: -2)
                }
            }
        }
        .buttonStyle(.plain)
        .foregroundStyle(color(for: agent))
        // Leaving a lane must be possible, and it is not cosmetic: each open lane holds a live
        // socket AND a real `tmux attach` on the workspace pod. Closing releases both.
        .contextMenu {
            if store.opened.contains(agent) {
                Button("Fechar \(agent)", systemImage: "xmark.circle") { store.close(agent) }
                Button("Fechar as outras", systemImage: "rectangle.on.rectangle.slash") {
                    store.open(agent); store.closeAllExceptActive()
                }
            }
        }
    }

    @ViewBuilder private var statusLine: some View {
        let s = store.state(for: store.activeAgent)
        if s != .connected {
            HStack(spacing: 6) {
                Circle().fill(stateColor(s)).frame(width: 7, height: 7)
                Text(statusText(s)).font(.caption2).foregroundStyle(.white.opacity(0.7))
                if case .failed = s {
                    Button("Retry") { store.client(for: store.activeAgent).connect() }
                        .font(.caption2).buttonStyle(.borderless).tint(Self.amber)
                }
                Spacer()
            }
            .padding(.horizontal, 12).padding(.vertical, 4)
            .background(Self.canvas)
        }
    }

    // ⌘K quick switcher (Mac/iPad hardware keyboard); harmless on iPhone.
    private var switcherShortcut: some View {
        Button("Switch agent") { showSwitcher = true }
            .keyboardShortcut("k", modifiers: .command)
            .opacity(0).frame(width: 0, height: 0)
            .accessibilityHidden(true)
    }

    private var agentSwitcher: some View {
        NavigationStack {
            List(store.agents, id: \.self) { agent in
                Button {
                    store.open(agent); haptic(); showSwitcher = false
                } label: {
                    HStack {
                        Circle().fill(stateColor(store.state(for: agent))).frame(width: 8, height: 8)
                        Text(agent).font(.system(.body, design: .monospaced))
                            .foregroundStyle(color(for: agent))
                        if store.hasUnread(agent) {
                            Circle().fill(Self.amber).frame(width: 7, height: 7)
                        }
                        Spacer()
                        if agent == store.activeAgent {
                            Image(systemName: "checkmark").foregroundStyle(Self.amber)
                        }
                    }
                }
            }
            .navigationTitle("Switch agent")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { showSwitcher = false }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func haptic() {
        #if canImport(UIKit) && os(iOS)
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        #endif
    }

    private func statusText(_ s: PTYClient.State) -> String {
        switch s {
        case .idle: return "idle"
        case .connecting: return "connecting…"
        case .reconnecting: return "reconnecting…"
        case .connected: return "connected"
        case .failed(let m): return "offline — \(m)"
        }
    }

    private func stateColor(_ s: PTYClient.State) -> Color {
        switch s {
        case .connected: return Color(red: 0.20, green: 0.85, blue: 0.45)
        case .connecting, .reconnecting: return Self.amber
        case .failed: return Color(red: 0.95, green: 0.36, blue: 0.36)
        case .idle: return .gray
        }
    }

    private func color(for agent: String) -> Color {
        if agent.hasPrefix("claude") { return Self.claude }
        if agent.hasPrefix("codex") { return Self.codex }
        return Self.vendor
    }
}
#endif
