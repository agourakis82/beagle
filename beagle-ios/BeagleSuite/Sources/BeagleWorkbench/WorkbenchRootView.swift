import SwiftUI
import BeagleCore

struct WorkbenchRootView: View {
    @EnvironmentObject private var store: WorkbenchStore
    @State private var showingCommandPalette = false
    @State private var showingInspector = false
    @State private var showingLeaseNotice = false
    @State private var inspectorTab: FocusInspectorTab = .agent
    @State private var columnVisibility: NavigationSplitViewVisibility = .detailOnly

    private var commandPaletteItems: [CommandPaletteItem] {
        [
            CommandPaletteItem(category: .orient, command: "/whereami", title: "Orient Sounio", subtitle: "Read workspace, branch, tab, and agent context", icon: "location.fill", truth: .observed),
            CommandPaletteItem(category: .diagnose, command: "/doctor", title: "Connection health", subtitle: "Open inspector wires and refresh Cockpit readbacks", icon: "stethoscope", truth: store.catalogWire.mode),
            CommandPaletteItem(category: .diagnose, command: "/exocortex", title: "Ask exocortex", subtitle: "POST /api/exocortex/process via Cockpit proxy", icon: "brain.head.profile", truth: store.exocortexWire.mode),
            CommandPaletteItem(category: .diagnose, command: "/graphrag", title: "Query GraphRAG", subtitle: "POST workbench context graphrag for \(store.selectedProjectID)", icon: "point.3.connected.trianglepath.dotted", truth: store.graphragWire.mode),
            CommandPaletteItem(category: .guardrail, command: "/lease", title: "Inspect Lease Guard", subtitle: "Show the selected lane owner and overlap risk", icon: "lock.shield.fill", truth: store.selectedLane?.leaseState.truth ?? .declared),
            CommandPaletteItem(category: .compose, command: "/stop", title: "Stop multimodel stream", subtitle: "Cancel active WS turn on \(store.chatProjectSlug)", icon: "stop.circle.fill", truth: store.multimodelWire.mode),
            CommandPaletteItem(category: .compose, command: "/send", title: "Send to zellij tab", subtitle: "Write into \(store.selectedAgent?.zellijTabName ?? "selected tab") on \(store.selectedProjectID)", icon: "paperplane.fill", truth: store.workspaceWire.mode),
            CommandPaletteItem(category: .compose, command: "/handoff", title: "Draft Handoff", subtitle: "Summarize current lane state for the next agent", icon: "arrow.triangle.2.circlepath", truth: .remembered),
            CommandPaletteItem(category: .compose, command: "/handoff-compile", title: "Compile handoff packet", subtitle: "RAG++ context + GraphRAG for selected handoff", icon: "doc.text.magnifyingglass", truth: store.handoffCompileWire.mode)
        ]
    }

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            FocusSidebar()
                .navigationTitle("Beagle")
        } detail: {
            FocusWorkspaceDetail(
                showingCommandPalette: $showingCommandPalette,
                showingInspector: $showingInspector,
                showingLeaseNotice: $showingLeaseNotice
            )
            .navigationTitle(store.selectedProject?.title ?? "Beagle")
            .toolbar {
                ToolbarItemGroup(placement: .primaryAction) {
                    if store.isRefreshing {
                        ProgressView()
                            .controlSize(.small)
                    }
                    Button {
                        Task { await store.refreshAll() }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .help("Refresh Cockpit")

                    AgentPresenceToolbar()
                    Button {
                        showingInspector.toggle()
                    } label: {
                        Image(systemName: "sidebar.right")
                    }
                    .keyboardShortcut("i", modifiers: [.command, .option])

                    Button {
                        showingCommandPalette = true
                    } label: {
                        Image(systemName: "command")
                    }
                    .keyboardShortcut("k", modifiers: .command)

                    Button {
                        showingLeaseNotice = true
                    } label: {
                        HStack(spacing: 6) {
                            Circle()
                                .fill(BeagleTheme.color(for: store.selectedLane?.leaseState.truth ?? .observed))
                                .frame(width: 8, height: 8)
                            Text("Status")
                        }
                    }
                }
            }
            .inspector(isPresented: $showingInspector) {
                FocusInspector(selectedTab: $inspectorTab)
                    .frame(minWidth: 280, idealWidth: 320, maxWidth: 360)
            }
        }
        .navigationSplitViewStyle(.balanced)
        .overlay {
            if showingCommandPalette {
                CommandPaletteOverlay(isPresented: $showingCommandPalette, items: commandPaletteItems) { item in
                    handlePalette(item)
                }
            }
        }
        .frame(minWidth: 1040, minHeight: 720)
        .onExitCommand {
            if showingCommandPalette {
                withAnimation(.easeOut(duration: 0.15)) {
                    showingCommandPalette = false
                }
            } else if showingInspector {
                showingInspector = false
            } else if showingLeaseNotice {
                withAnimation(.easeOut(duration: 0.15)) {
                    showingLeaseNotice = false
                }
            }
        }
        .task {
            await store.refreshAll()
        }
        .onChange(of: store.selectedProjectID) { _, slug in
            Task {
                await store.refreshWorkspace(for: slug)
                await store.refreshPresence()
                await store.refreshHandoffs()
                await store.refreshAgentSessions()
                await store.refreshZellijTransport()
            }
        }
    }

    private func handlePalette(_ item: CommandPaletteItem) {
        switch item.command {
        case "/doctor":
            inspectorTab = .connection
            showingInspector = true
            Task { await store.refreshAll() }
        case "/exocortex":
            inspectorTab = .exocortex
            showingInspector = true
            store.useStarter("/exocortex")
        case "/graphrag":
            inspectorTab = .graphrag
            showingInspector = true
            store.useStarter("/graphrag ")
        case "/lease":
            showingLeaseNotice = true
            store.useStarter(item.command)
        case "/whereami":
            Task { await store.runWhereAmI() }
        case "/send":
            store.composerDelivery = .zellijTab
            store.useStarter("/send ")
        case "/handoff":
            inspectorTab = .handoffs
            showingInspector = true
            store.composerText = "/handoff "
        case "/handoff-compile":
            inspectorTab = .handoffs
            showingInspector = true
            Task { await store.compileSelectedHandoff() }
        case "/stop", "/cancel":
            store.stopActiveMultimodelTurn()
        default:
            store.useStarter(item.command)
        }
    }
}
