#if os(iOS) || os(macOS)
import SwiftUI
import BeagleCore

/// Fleet Terminals screen: agent picker (status-tinted) + a ZStack of all *opened*
/// terminals (kept mounted; only the active one shown) so switching never tears down a
/// live SwiftTerm buffer — mirrors the web cockpit keep-alive invariant. Reconnects
/// dropped sessions when the app returns to the foreground.
public struct FleetTerminalsView: View {
    @State private var store = FleetTerminalStore()
    @Environment(\.scenePhase) private var scenePhase

    public init() {}

    // Palette (matches the cockpit web identity)
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
        }
        .background(Self.canvas)
        .onAppear { store.open(store.activeAgent) }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { store.reconnectStale() }
        }
        .navigationTitle("Fleet")
    }

    private var agentBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(store.agents, id: \.self) { agent in
                    let active = agent == store.activeAgent
                    Button { store.open(agent) } label: {
                        HStack(spacing: 6) {
                            if store.opened.contains(agent) {
                                Circle()
                                    .fill(stateColor(store.state(for: agent)))
                                    .frame(width: 7, height: 7)
                            }
                            Text(agent)
                                .font(.system(.caption, design: .monospaced))
                        }
                        .padding(.horizontal, 10).padding(.vertical, 6)
                        .background(active ? Self.amber.opacity(0.22) : Color.white.opacity(0.06))
                        .overlay(
                            Capsule().stroke(active ? Self.amber.opacity(0.6) : .clear, lineWidth: 1)
                        )
                        .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(color(for: agent))
                }
            }
            .padding(.horizontal, 12).padding(.vertical, 8)
        }
        .background(Self.canvas)
    }

    @ViewBuilder private var statusLine: some View {
        let s = store.state(for: store.activeAgent)
        if s != .connected {
            HStack(spacing: 6) {
                Circle().fill(stateColor(s)).frame(width: 7, height: 7)
                Text(statusText(s))
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.7))
                if case .failed = s {
                    Button("Retry") { store.client(for: store.activeAgent).connect() }
                        .font(.caption2)
                        .buttonStyle(.borderless)
                        .tint(Self.amber)
                }
                Spacer()
            }
            .padding(.horizontal, 12).padding(.vertical, 4)
            .background(Self.canvas)
        }
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
