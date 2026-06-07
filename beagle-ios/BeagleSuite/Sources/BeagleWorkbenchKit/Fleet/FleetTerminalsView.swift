#if os(iOS) || os(macOS)
import SwiftUI
import BeagleCore

/// Fleet Terminals screen: agent picker + a ZStack of all *opened* terminals
/// (kept mounted; only the active one shown) so switching never tears down a live
/// SwiftTerm buffer — mirrors the web cockpit keep-alive invariant.
public struct FleetTerminalsView: View {
    @State private var store = FleetTerminalStore()

    public init() {}

    public var body: some View {
        VStack(spacing: 0) {
            agentBar
            Divider()
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
        }
        .onAppear { store.open(store.activeAgent) }
        .navigationTitle("Fleet")
    }

    private var agentBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(store.agents, id: \.self) { agent in
                    Button { store.open(agent) } label: {
                        Text(agent)
                            .font(.system(.caption, design: .monospaced))
                            .padding(.horizontal, 10).padding(.vertical, 6)
                            .background(agent == store.activeAgent
                                        ? Color.accentColor.opacity(0.25)
                                        : Color.gray.opacity(0.12))
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(color(for: agent))
                }
            }
            .padding(.horizontal, 12).padding(.vertical, 8)
        }
    }

    private func color(for agent: String) -> Color {
        if agent.hasPrefix("claude") { return Color(red: 1.0, green: 0.82, blue: 0.40) }
        if agent.hasPrefix("codex") { return Color(red: 0.20, green: 0.88, blue: 0.78) }
        return Color(red: 1.0, green: 0.57, blue: 0.40)
    }
}
#endif
