import SwiftUI
import BeagleCore

@main
struct BeagleWorkbenchApp: App {
    @StateObject private var store = WorkbenchStore()

    var body: some Scene {
        WindowGroup("Beagle") {
            WorkbenchRootView()
                .environmentObject(store)
        }
        #if os(macOS)
        .defaultSize(width: 1360, height: 860)
        #endif

        WindowGroup("Supercomputing Control", id: "supercomputing-control") {
            SupercomputingControlView()
                .environmentObject(store)
                .preferredColorScheme(.dark)
        }
        #if os(macOS)
        .windowStyle(.hiddenTitleBar)
        .windowToolbarStyle(.unifiedCompact)
        .defaultSize(width: 1280, height: 820)
        #endif
    }
}

enum FocusCanvasTab: String, CaseIterable, Identifiable {
    case chat = "Conversation"
    case artifact = "Artifact"
    case terminal = "Terminal"

    var id: String { rawValue }
}

struct FocusWorkspaceDetail: View {
    @EnvironmentObject private var store: WorkbenchStore
    @Binding var showingCommandPalette: Bool
    @Binding var showingInspector: Bool
    @Binding var showingLeaseNotice: Bool
    @State private var selectedTab: FocusCanvasTab = .chat

    var body: some View {
        ZStack {
            SystemWorkbenchBackground()

            VStack(spacing: 0) {
                WorkbenchConnectionBanner()
                FocusCanvasHeader(selectedTab: $selectedTab)
                Divider()
                TabView(selection: $selectedTab) {
                    FocusConversationCanvas()
                        .tag(FocusCanvasTab.chat)
                        .tabItem { Label("Conversation", systemImage: "bubble.left.and.bubble.right") }
                    FocusArtifactCanvas()
                        .tag(FocusCanvasTab.artifact)
                        .tabItem { Label("Artifact", systemImage: "doc.text") }
                    AgentTerminalCanvas()
                        .tag(FocusCanvasTab.terminal)
                        .tabItem { Label(store.workspace.sessionName, systemImage: "terminal") }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }

            VStack {
                AgentWorkLine()
                Spacer()
            }

            VStack {
                if showingLeaseNotice {
                    LeaseNotice()
                        .transition(.move(edge: .top).combined(with: .opacity))
                        .padding(.top, 10)
                }
                Spacer()
            }

            VStack {
                Spacer()
                ComposerCommandDeck()
                    .frame(maxWidth: 760)
                    .padding(.horizontal, 32)
                    .padding(.bottom, 28)
            }
        }
        .onChange(of: store.selectedLaneID) { _, _ in
            let state = store.selectedLane?.leaseState ?? .clear
            guard state != .clear else { return }
            withAnimation(.easeOut(duration: 0.20)) {
                showingLeaseNotice = true
            }
        }
    }
}

struct SystemWorkbenchBackground: View {
    var body: some View {
        #if os(macOS)
        Color(nsColor: .windowBackgroundColor).ignoresSafeArea()
        #else
        Color(.systemBackground).ignoresSafeArea()
        #endif
    }
}

struct FocusCanvasHeader: View {
    @EnvironmentObject private var store: WorkbenchStore
    @Binding var selectedTab: FocusCanvasTab

    var body: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 2) {
                Text(store.selectedProject?.title ?? "Beagle")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.primary)
                Text(store.workspace.isLive ? "\(store.workspace.sessionName) live" : store.workspace.source.rawValue)
                    .font(.system(size: 11, weight: .regular))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Picker("", selection: $selectedTab) {
                ForEach(FocusCanvasTab.allCases) { tab in
                    Text(tab.rawValue).tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .frame(width: 340)
        }
        .padding(.horizontal, 32)
        .padding(.vertical, 14)
    }
}

struct AgentWorkLine: View {
    @EnvironmentObject private var store: WorkbenchStore
    @State private var pulse = false

    private var activeAgent: WorkbenchAgent? {
        store.selectedAgent ?? store.activeAgents.first
    }

    var body: some View {
        Rectangle()
            .fill((activeAgent?.kind.color ?? BeagleTheme.truthObserved).opacity(pulse ? 0.55 : 0.18))
            .frame(height: 1)
            .onAppear {
                withAnimation(.easeInOut(duration: 2.0).repeatForever(autoreverses: true)) {
                    pulse = true
                }
            }
    }
}

private struct FocusArtifactCanvas: View {
    @EnvironmentObject private var store: WorkbenchStore

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                HStack(alignment: .top, spacing: 16) {
                    ArtifactDocumentIcon()
                    VStack(alignment: .leading, spacing: 6) {
                        Text(store.selectedLane?.title ?? "Workspace")
                            .font(.system(size: 22, weight: .semibold))
                            .foregroundStyle(.primary)
                        Text(store.selectedAgent?.currentTask ?? "Open an artifact, ask a question, or start from the input below.")
                            .font(.system(size: 15, weight: .regular))
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer()
                }

                FocusArtifactCard()

                HStack(spacing: 10) {
                    QuietAction(title: "Review", icon: "checkmark.shield", prompt: "Review the current artifact and point out risks before editing.")
                    QuietAction(title: "Draft", icon: "square.and.pencil", prompt: "Draft the next change as a short plan, no patch yet.")
                    QuietAction(title: "Talk it through", icon: "bubble.left.and.bubble.right", prompt: "Let's reason through this before assigning it to an agent.")
                }
            }
            .frame(maxWidth: 880, alignment: .leading)
            .padding(.top, 54)
            .padding(.horizontal, 32)
            .padding(.bottom, 128)
            .frame(maxWidth: .infinity)
        }
    }
}

private struct ArtifactDocumentIcon: View {
    var body: some View {
        RoundedRectangle(cornerRadius: 12, style: .continuous)
            .fill(.quaternary)
            .frame(width: 54, height: 54)
            .overlay {
                Image(systemName: "doc.text")
                    .font(.system(size: 22, weight: .regular))
                    .foregroundStyle(.secondary)
            }
    }
}

private struct FocusArtifactCard: View {
    @EnvironmentObject private var store: WorkbenchStore

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Current working note")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.primary)
                Spacer()
                Text(store.selectedLane?.leaseState.rawValue ?? "clear")
                    .font(.system(size: 11, weight: .regular))
                    .foregroundStyle(.secondary)
            }

            Text(store.leaseSummary)
                .font(.system(size: 15, weight: .regular))
                .foregroundStyle(.primary)
                .lineSpacing(4)
                .fixedSize(horizontal: false, vertical: true)

            Divider()

            VStack(alignment: .leading, spacing: 8) {
                Text("Files near this work")
                    .font(.system(size: 11, weight: .regular))
                    .foregroundStyle(.secondary)
                ForEach(store.selectedLane?.touchedFiles ?? [], id: \.self) { path in
                    Text(path)
                        .font(.system(size: 12, weight: .regular, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(24)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(.quaternary, lineWidth: 1)
        }
    }
}

private struct FocusTerminalCanvas: View {
    @EnvironmentObject private var store: WorkbenchStore

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 6) {
                ForEach(store.terminalLines) { line in
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Text(line.source)
                            .font(.system(size: 11, weight: .regular, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .frame(width: 120, alignment: .leading)
                        Text(line.text)
                            .font(.system(size: 13, weight: .regular, design: .monospaced))
                            .foregroundStyle(.primary)
                        Spacer(minLength: 0)
                    }
                }
            }
            .frame(maxWidth: 900, alignment: .leading)
            .padding(24)
            .background(Color.black.opacity(0.82), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .padding(.top, 48)
            .padding(.horizontal, 32)
            .padding(.bottom, 128)
            .frame(maxWidth: .infinity)
        }
    }
}

struct LeaseNotice: View {
    @EnvironmentObject private var store: WorkbenchStore

    var body: some View {
        let state = store.selectedLane?.leaseState ?? .clear
        HStack(spacing: 10) {
            Image(systemName: state == .clear ? "checkmark.circle" : "lock")
                .foregroundStyle(BeagleTheme.color(for: state.truth))
            Text(state == .clear ? "This lane is clear." : "This change needs approval.")
                .font(.system(size: 13, weight: .regular))
                .foregroundStyle(.primary)
            Spacer()
        }
        .padding(.horizontal, 14)
        .frame(height: 40)
        .frame(maxWidth: 720)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

struct AgentPresenceToolbar: View {
    @EnvironmentObject private var store: WorkbenchStore

    var body: some View {
        HStack(spacing: 4) {
            ForEach(store.activeAgents.prefix(5)) { agent in
                Circle()
                    .fill(agent.kind.color.opacity(agent.status == .running ? 0.82 : 0.36))
                    .frame(width: 10, height: 10)
                    .help("\(agent.displayName): \(agent.currentTask)")
            }
        }
        .frame(minWidth: 56)
    }
}

private struct SovereignBackground: View {
    @State private var drift = false

    var body: some View {
        ZStack {
            LiquidCodexBackground(intensity: .quiet)
            SignalField(intensity: 0.92)
                .opacity(0.22)
            RadialGradient(
                colors: [
                    WorkbenchTone.paper.opacity(drift ? 0.12 : 0.06),
                    WorkbenchTone.ember.opacity(drift ? 0.08 : 0.14),
                    .clear
                ],
                center: drift ? .bottomTrailing : .topLeading,
                startRadius: 40,
                endRadius: 760
            )
            .ignoresSafeArea()
            .blur(radius: 18)

            LinearGradient(
                colors: [
                    WorkbenchTone.void.opacity(0.54),
                    WorkbenchTone.midnight.opacity(0.42),
                    Color.black.opacity(0.46)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 8).repeatForever(autoreverses: true)) {
                drift.toggle()
            }
        }
    }
}

private struct WorkbenchTopBar: View {
    @EnvironmentObject private var store: WorkbenchStore
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        let workspace = store.workspace
        HStack(spacing: 14) {
            HStack(spacing: 10) {
                ZStack {
                    Circle()
                        .fill(WorkbenchTone.hotGradient)
                        .frame(width: 32, height: 32)
                        .shadow(color: WorkbenchTone.cyan.opacity(0.45), radius: 14)
                    Text("B")
                        .font(BeagleTheme.dataFont(size: 15, weight: .bold))
                        .foregroundStyle(WorkbenchTone.void)
                }
                VStack(alignment: .leading, spacing: 1) {
                    Text("SOUNIO IS HOME")
                        .font(BeagleTheme.uiFont(size: 11, weight: .semibold))
                        .tracking(1.7)
                        .foregroundStyle(WorkbenchTone.cyan)
                    Text(workspace.isLive ? "sounio-dev is live on \(workspace.nodeName)" : "Continue where zellij is already alive")
                        .font(BeagleTheme.displayFont(size: 19, weight: .semibold))
                        .foregroundStyle(BeagleTheme.textPrimary)
                }
            }

            Spacer()

            HStack(spacing: 12) {
                Button {
                    openWindow(id: "supercomputing-control")
                } label: {
                    Label("supercomputing", systemImage: "cpu.fill")
                        .font(BeagleTheme.dataFont(size: 11, weight: .bold))
                        .foregroundStyle(WorkbenchTone.void)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(Capsule().fill(WorkbenchTone.dreamGradient))
                        .shadow(color: WorkbenchTone.cyan.opacity(0.28), radius: 14)
                }
                .buttonStyle(.plain)

                TopBarMetric(label: "ritual", value: "Termius -> dev sounio", truth: .observed)
                TopBarMetric(label: "branch", value: workspace.branch, truth: workspace.source.truth)
                TopBarMetric(label: "zellij", value: "\(workspace.expectedTabs.count) canonical tabs", truth: workspace.source.truth)
                TopBarMetric(label: "guard", value: store.selectedLane?.leaseState.rawValue ?? "none", truth: store.selectedLane?.leaseState.truth ?? .declared)
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
        .background {
            Rectangle()
                .fill(.regularMaterial)
                .opacity(0.50)
        }
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(WorkbenchTone.hotGradient)
                .frame(height: 1)
                .opacity(0.42)
        }
    }
}

private struct TopBarMetric: View {
    let label: String
    let value: String
    let truth: TruthMode

    var body: some View {
        HStack(spacing: 7) {
            TruthBadge(truth, compact: true)
            VStack(alignment: .leading, spacing: 1) {
                Text(label.uppercased())
                    .font(BeagleTheme.dataFont(size: 8, weight: .medium))
                    .tracking(0.8)
                    .foregroundStyle(BeagleTheme.textTertiary)
                Text(value)
                    .font(BeagleTheme.dataFont(size: 11, weight: .medium))
                    .lineLimit(1)
                    .foregroundStyle(BeagleTheme.textData)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(BeagleTheme.surface1.opacity(0.66))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(BeagleTheme.color(for: truth).opacity(0.18), lineWidth: 1)
        )
    }
}

private struct SounioRitualHero: View {
    @EnvironmentObject private var store: WorkbenchStore

    var body: some View {
        let workspace = store.workspace
        LiquidGlassSurface(elevated: true, truth: .observed, depth: 2) {
            HStack(alignment: .center, spacing: 22) {
                VStack(alignment: .leading, spacing: 14) {
                    HStack(spacing: 8) {
                        Image(systemName: "house.fill")
                            .font(.system(size: 11, weight: .bold))
                        Text("SOUNIO STUDIO")
                            .font(BeagleTheme.dataFont(size: 10, weight: .bold))
                            .tracking(1.2)
                        TruthBadge(workspace.source.truth, compact: true)
                    }
                    .foregroundStyle(WorkbenchTone.paper.opacity(0.86))

                    VStack(alignment: .leading, spacing: 5) {
                        Text("Sounio")
                            .font(.system(size: 34, weight: .semibold, design: .serif))
                            .foregroundStyle(WorkbenchTone.paper)
                        Text(workspace.isLive ? "\(workspace.sessionName) is live on \(workspace.nodeName)." : "The workspace contract is ready when the bridge comes back.")
                            .font(BeagleTheme.uiFont(size: 13))
                            .foregroundStyle(BeagleTheme.textSecondary)
                    }

                    WorkspaceBrief(snapshot: workspace, lane: store.selectedLane, agentCount: store.activeAgents.count)
                    MiniCommandDeck()
                }

                Spacer(minLength: 8)

                VStack(spacing: 10) {
                    HStack(spacing: 10) {
                        if let agent = store.selectedAgent {
                            PresenceOrb(agent: agent, compact: true)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(agent.displayName)
                                    .font(BeagleTheme.uiFont(size: 13, weight: .semibold))
                                    .foregroundStyle(BeagleTheme.textPrimary)
                                Text(agent.currentTask)
                                    .font(BeagleTheme.uiFont(size: 11))
                                    .foregroundStyle(BeagleTheme.textTertiary)
                                    .lineLimit(2)
                            }
                        }
                        Spacer()
                    }
                    ZellijConstellation(tabs: workspace.expectedTabs, agents: store.agents, selectedID: store.selectedAgentID)
                        .frame(width: 220, height: 132)
                        .opacity(0.82)
                }
                .frame(width: 260)
            }
        }
    }
}

private struct WorkspaceBrief: View {
    let snapshot: SounioWorkspaceSnapshot
    let lane: WorkbenchLane?
    let agentCount: Int

    var body: some View {
        HStack(spacing: 9) {
            SoftFact(icon: "rectangle.3.group.fill", value: "\(snapshot.expectedTabs.count)", label: "tabs", truth: snapshot.source.truth)
            SoftFact(icon: "person.2.fill", value: "\(agentCount)", label: "active", truth: .remembered)
            SoftFact(icon: "lock.shield.fill", value: lane?.leaseState.rawValue ?? "clear", label: "lease", truth: lane?.leaseState.truth ?? .observed)
            SoftFact(icon: "folder.fill", value: snapshot.workspaceRoot, label: "root", truth: .remembered)
        }
    }
}

private struct SoftFact: View {
    let icon: String
    let value: String
    let label: String
    let truth: TruthMode

    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(BeagleTheme.color(for: truth))
            VStack(alignment: .leading, spacing: 0) {
                Text(value)
                    .font(BeagleTheme.dataFont(size: 10, weight: .bold))
                    .foregroundStyle(BeagleTheme.textData)
                    .lineLimit(1)
                Text(label.uppercased())
                    .font(BeagleTheme.dataFont(size: 7, weight: .medium))
                    .foregroundStyle(BeagleTheme.textTertiary)
            }
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 7)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(WorkbenchTone.paper.opacity(0.055)))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(WorkbenchTone.paper.opacity(0.10), lineWidth: 1))
    }
}

private struct SounioInstrumentDeck: View {
    let workspace: SounioWorkspaceSnapshot
    let lane: WorkbenchLane?
    let agentCount: Int

    private var liveValue: Double {
        workspace.isLive ? 1.0 : 0.38
    }

    private var leaseValue: Double {
        switch lane?.leaseState ?? .clear {
        case .clear: return 0.22
        case .owned: return 0.52
        case .overlap: return 0.76
        case .blocked: return 0.96
        }
    }

    var body: some View {
        HStack(spacing: 12) {
            InstrumentRing(
                metric: InstrumentMetric(
                    id: "workspace",
                    title: "CORE",
                    value: liveValue,
                    label: workspace.status.uppercased(),
                    truth: workspace.source.truth,
                    color: workspace.isLive ? WorkbenchTone.acid : BeagleTheme.color(for: workspace.source.truth)
                ),
                lineWidth: 8
            )
            .frame(width: 116, height: 116)

            VStack(alignment: .leading, spacing: 10) {
                Text("Sounio")
                    .font(.system(size: 38, weight: .black, design: .rounded))
                    .foregroundStyle(WorkbenchTone.hotGradient)
                    .shadow(color: WorkbenchTone.cyan.opacity(0.20), radius: 18)
                SignalRibbon(intensity: .standard)
                    .frame(height: 34)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(WorkbenchTone.cyan.opacity(0.12), lineWidth: 1))
                HStack(spacing: 8) {
                    MiniInstrument(icon: "rectangle.3.group.fill", value: "\(workspace.expectedTabs.count)", label: "tabs", truth: workspace.source.truth)
                    MiniInstrument(icon: "person.2.wave.2.fill", value: "\(agentCount)", label: "agents", truth: .remembered)
                    MiniInstrument(icon: "lock.shield.fill", value: lane?.leaseState.rawValue ?? "clear", label: "lease", truth: lane?.leaseState.truth ?? .observed)
                }
            }

            InstrumentRing(
                metric: InstrumentMetric(
                    id: "lease",
                    title: "LEASE",
                    value: leaseValue,
                    label: (lane?.leaseState.rawValue ?? "clear").uppercased(),
                    truth: lane?.leaseState.truth ?? .observed,
                    color: BeagleTheme.color(for: lane?.leaseState.truth ?? .observed)
                ),
                lineWidth: 8
            )
            .frame(width: 104, height: 104)
        }
    }
}

private struct MiniInstrument: View {
    let icon: String
    let value: String
    let label: String
    let truth: TruthMode

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(BeagleTheme.color(for: truth))
            Text(value)
                .font(BeagleTheme.dataFont(size: 11, weight: .bold))
                .foregroundStyle(BeagleTheme.textData)
            Text(label.uppercased())
                .font(BeagleTheme.dataFont(size: 8, weight: .medium))
                .foregroundStyle(BeagleTheme.textTertiary)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(RoundedRectangle(cornerRadius: 10).fill(WorkbenchTone.void.opacity(0.58)))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(BeagleTheme.color(for: truth).opacity(0.16), lineWidth: 1))
    }
}

private struct MiniCommandDeck: View {
    @EnvironmentObject private var store: WorkbenchStore

    private let commands = [
        "/whereami",
        "/doctor",
        "/lease",
        "/send",
        "/handoff"
    ]

    var body: some View {
        HStack(spacing: 8) {
            ForEach(commands, id: \.self) { command in
                Button {
                    store.useStarter(command)
                } label: {
                    Text(command)
                        .font(BeagleTheme.dataFont(size: 10, weight: .semibold))
                        .foregroundStyle(BeagleTheme.textData)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Capsule().fill(WorkbenchTone.void.opacity(0.68)))
                        .overlay(Capsule().strokeBorder(WorkbenchTone.violet.opacity(0.22), lineWidth: 1))
                }
                .buttonStyle(.plain)
            }
        }
    }
}

private struct WorkspaceLiveRibbon: View {
    let snapshot: SounioWorkspaceSnapshot

    private var statusColor: Color {
        snapshot.isLive ? WorkbenchTone.acid : BeagleTheme.color(for: snapshot.source.truth)
    }

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 16)
                    .fill(statusColor.opacity(0.11))
                    .frame(width: 66, height: 54)
                WorkspaceCorePulse(progress: snapshot.isLive ? 0.82 : 0.34, accent: statusColor)
                    .frame(width: 44, height: 44)
            }

            VStack(alignment: .leading, spacing: 7) {
                HStack(spacing: 8) {
                    StatusDot(color: statusColor, active: snapshot.isLive)
                    Text(snapshot.sessionName)
                        .font(BeagleTheme.dataFont(size: 12, weight: .bold))
                        .foregroundStyle(BeagleTheme.textData)
                    TruthBadge(snapshot.source.truth, compact: true)
                }

                HStack(spacing: 6) {
                    WorkspaceGlyph(icon: "shippingbox.fill", value: snapshot.podName, truth: snapshot.source.truth)
                    WorkspaceGlyph(icon: "server.rack", value: snapshot.nodeName, truth: snapshot.source.truth)
                    WorkspaceGlyph(icon: "folder.fill", value: snapshot.workspaceRoot, truth: .remembered)
                }
            }

            Spacer(minLength: 10)

            CanonicalTabOrbit(tabs: snapshot.expectedTabs, truth: snapshot.source.truth)
                .frame(width: 168, height: 54)
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 18)
                .fill(WorkbenchTone.void.opacity(0.58))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18)
                .strokeBorder(statusColor.opacity(snapshot.isLive ? 0.35 : 0.20), lineWidth: 1)
        )
        .shadow(color: statusColor.opacity(snapshot.isLive ? 0.18 : 0.04), radius: 18)
    }
}

private struct WorkspaceCorePulse: View {
    let progress: Double
    let accent: Color
    @State private var pulse = false

    var body: some View {
        ZStack {
            Circle()
                .stroke(accent.opacity(0.28), lineWidth: 1)
                .scaleEffect(pulse ? 1.06 : 0.92)
            Circle()
                .trim(from: 0, to: min(max(progress, 0), 1))
                .stroke(WorkbenchTone.hotGradient, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                .rotationEffect(.degrees(-90))
            Circle()
                .fill(accent.opacity(0.16))
                .frame(width: 20, height: 20)
            Text("S")
                .font(.system(size: 12, weight: .black, design: .rounded))
                .foregroundStyle(accent)
        }
        .shadow(color: accent.opacity(pulse ? 0.58 : 0.20), radius: pulse ? 12 : 4)
        .onAppear {
            withAnimation(.easeInOut(duration: 2.4).repeatForever(autoreverses: true)) {
                pulse = true
            }
        }
    }
}

private struct WorkspaceGlyph: View {
    let icon: String
    let value: String
    let truth: TruthMode

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: icon)
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(BeagleTheme.color(for: truth))
            Text(value)
                .font(BeagleTheme.dataFont(size: 9, weight: .medium))
                .foregroundStyle(BeagleTheme.textTertiary)
                .lineLimit(1)
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 5)
        .background(Capsule().fill(BeagleTheme.color(for: truth).opacity(0.07)))
    }
}

private struct CanonicalTabOrbit: View {
    let tabs: [String]
    let truth: TruthMode
    @State private var spin = false

    var body: some View {
        GeometryReader { proxy in
            let size = min(proxy.size.width, proxy.size.height)
            let center = CGPoint(x: proxy.size.width / 2, y: proxy.size.height / 2)
            let radius = size * 0.37

            ZStack {
                Capsule()
                    .strokeBorder(BeagleTheme.color(for: truth).opacity(0.22), lineWidth: 1)
                    .frame(width: proxy.size.width, height: proxy.size.height)
                ForEach(Array(tabs.enumerated()), id: \.offset) { index, tab in
                    let angle = (Double(index) / Double(max(tabs.count, 1))) * .pi * 2 + (spin ? .pi * 2 : 0)
                    let x = center.x + CGFloat(cos(angle)) * radius * 1.72
                    let y = center.y + CGFloat(sin(angle)) * radius * 0.72
                    Circle()
                        .fill(color(for: tab).opacity(tab == "repo" ? 1.0 : 0.82))
                        .frame(width: tab == "repo" ? 8 : 6, height: tab == "repo" ? 8 : 6)
                        .position(x: x, y: y)
                        .shadow(color: color(for: tab).opacity(0.55), radius: 5)
                }
                VStack(spacing: 0) {
                    Text("\(tabs.count)")
                        .font(BeagleTheme.dataFont(size: 15, weight: .bold))
                        .foregroundStyle(BeagleTheme.textData)
                    Text("tabs")
                        .font(BeagleTheme.dataFont(size: 8, weight: .medium))
                        .foregroundStyle(BeagleTheme.textTertiary)
                }
            }
        }
        .onAppear {
            withAnimation(.linear(duration: 22).repeatForever(autoreverses: false)) {
                spin = true
            }
        }
    }

    private func color(for tab: String) -> Color {
        if tab.hasPrefix("claude") { return WorkbenchTone.magenta }
        if tab.hasPrefix("codex") { return WorkbenchTone.amber }
        if tab.hasPrefix("kimi") { return WorkbenchTone.violet }
        if tab.hasPrefix("grok") { return WorkbenchTone.cyan }
        return WorkbenchTone.acid
    }
}

private struct RitualConnector: View {
    var body: some View {
        Image(systemName: "chevron.right")
            .font(.system(size: 9, weight: .bold))
            .foregroundStyle(BeagleTheme.textTertiary)
    }
}

private struct ZellijTabStrip: View {
    @EnvironmentObject private var store: WorkbenchStore

    private var tabs: [(name: String, truth: TruthMode, owner: String)] {
        let sourceTruth = store.workspace.source.truth
        return store.workspace.expectedTabs.map { tab in
            let hasAgent = store.agents.contains { $0.zellijTabName == tab }
            return (tab, hasAgent ? sourceTruth : .declared, owner(for: tab))
        }
    }

    private func owner(for tab: String) -> String {
        if tab == "repo" { return "repo" }
        if tab.hasPrefix("claude") { return "claude" }
        if tab.hasPrefix("codex") { return "codex" }
        if tab.hasPrefix("kimi") { return "kimi" }
        if tab.hasPrefix("grok") { return "grok" }
        return "pane"
    }

    var body: some View {
        let workspace = store.workspace
        LiquidGlassSurface(elevated: false, truth: .remembered) {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("ZELLIJ SESSION")
                        .font(BeagleTheme.dataFont(size: 9, weight: .bold))
                        .tracking(1.2)
                        .foregroundStyle(BeagleTheme.textTertiary)
                    Text(workspace.sessionName)
                        .font(BeagleTheme.displayFont(size: 16, weight: .semibold))
                        .foregroundStyle(BeagleTheme.textPrimary)
                }

                Spacer(minLength: 8)

                HStack(spacing: 7) {
                    StatusDot(color: BeagleTheme.color(for: workspace.source.truth), active: workspace.isLive)
                    Text(workspace.isLive ? "live contract" : workspace.source.rawValue)
                        .font(BeagleTheme.dataFont(size: 10, weight: .medium))
                        .foregroundStyle(BeagleTheme.textTertiary)
                }

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(tabs, id: \.name) { tab in
                            Button {
                                if let agent = store.agents.first(where: { $0.zellijTabName == tab.name }) {
                                    store.selectAgent(agent)
                                }
                            } label: {
                                ZellijTabPill(
                                    name: tab.name,
                                    owner: tab.owner,
                                    truth: tab.truth,
                                    selected: store.selectedAgent?.zellijTabName == tab.name
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
    }
}

private struct ZellijTabPill: View {
    let name: String
    let owner: String
    let truth: TruthMode
    let selected: Bool

    var body: some View {
        HStack(spacing: 7) {
            StatusDot(color: selected ? WorkbenchTone.cyan : BeagleTheme.color(for: truth), active: truth == .observed || selected)
            VStack(alignment: .leading, spacing: 1) {
                Text(name)
                    .font(BeagleTheme.dataFont(size: 11, weight: .semibold))
                    .foregroundStyle(selected ? BeagleTheme.textPrimary : BeagleTheme.textSecondary)
                Text(owner)
                    .font(BeagleTheme.dataFont(size: 8))
                    .foregroundStyle(BeagleTheme.textTertiary)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(selected ? WorkbenchTone.cyan.opacity(0.13) : WorkbenchTone.ink.opacity(0.54))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(selected ? WorkbenchTone.hotGradient : LinearGradient(colors: [BeagleTheme.color(for: truth).opacity(0.20), Color.white.opacity(0.04)], startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 1)
        )
        .shadow(color: (selected ? WorkbenchTone.cyan : BeagleTheme.color(for: truth)).opacity(selected ? 0.28 : 0.04), radius: selected ? 14 : 4)
    }
}

private struct WorkbenchProjectRail: View {
    @EnvironmentObject private var store: WorkbenchStore

    var body: some View {
        LiquidGlassSurface(elevated: true, truth: .observed, depth: 2) {
            VStack(alignment: .leading, spacing: 14) {
                LaneHeader(title: "Sovereign surfaces", truth: .declared)
                ForEach(store.projects) { project in
                    Button {
                        store.selectedProjectID = project.id
                    } label: {
                        ProjectRow(project: project, selected: project.id == store.selectedProjectID)
                    }
                    .buttonStyle(.plain)
                }

                Divider().overlay(Color.white.opacity(0.06))

                LaneHeader(title: "Today's hands", truth: .remembered)
                VStack(spacing: 10) {
                    ForEach(store.lanes) { lane in
                        Button {
                            store.selectLane(lane)
                        } label: {
                            LaneCard(lane: lane, selected: lane.id == store.selectedLaneID)
                        }
                        .buttonStyle(.plain)
                    }
                }

                Divider().overlay(Color.white.opacity(0.06))

                LaneHeader(title: "Zellij agents", truth: .observed)
                VStack(spacing: 8) {
                    ForEach(store.agents) { agent in
                        Button {
                            store.selectAgent(agent)
                        } label: {
                            AgentRow(agent: agent, selected: agent.id == store.selectedAgentID)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .chromaticFrame(active: false)
    }
}

private struct LaneHeader: View {
    let title: String
    let truth: TruthMode

    var body: some View {
        HStack {
            Text(title.uppercased())
                .font(BeagleTheme.uiFont(size: 10, weight: .semibold))
                .tracking(1.2)
                .foregroundStyle(BeagleTheme.textTertiary)
            Spacer()
            TruthBadge(truth, compact: true)
        }
    }
}

private struct ProjectRow: View {
    let project: WorkbenchProject
    let selected: Bool

    var body: some View {
        HStack(spacing: 10) {
            PostureIndicator(project.posture, size: 12, showLabel: false)
            VStack(alignment: .leading, spacing: 2) {
                Text(project.title)
                    .font(BeagleTheme.uiFont(size: 13, weight: .medium))
                    .foregroundStyle(selected ? BeagleTheme.textPrimary : BeagleTheme.textSecondary)
                Text(project.subtitle)
                    .font(BeagleTheme.uiFont(size: 10))
                    .lineLimit(1)
                    .foregroundStyle(BeagleTheme.textTertiary)
            }
            Spacer()
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(selected ? BeagleTheme.truthObserved.opacity(0.10) : Color.white.opacity(0.03))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(selected ? BeagleTheme.truthObserved.opacity(0.25) : Color.white.opacity(0.05), lineWidth: 1)
        )
    }
}

private struct LaneCard: View {
    let lane: WorkbenchLane
    let selected: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                Text(lane.title)
                    .font(BeagleTheme.uiFont(size: 13, weight: .semibold))
                    .foregroundStyle(BeagleTheme.textPrimary)
                Spacer()
                TruthBadge(lane.leaseState.truth, compact: true)
            }
            Text(lane.purpose)
                .font(BeagleTheme.uiFont(size: 11))
                .foregroundStyle(BeagleTheme.textSecondary)
                .lineLimit(2)
            Text(lane.touchedFiles.joined(separator: "  "))
                .font(BeagleTheme.dataFont(size: 10))
                .lineLimit(1)
                .foregroundStyle(BeagleTheme.textTertiary)
        }
        .padding(11)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(selected ? BeagleTheme.surface2.opacity(0.95) : BeagleTheme.surface1.opacity(0.55))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(BeagleTheme.color(for: lane.leaseState.truth).opacity(selected ? 0.42 : 0.16), lineWidth: 1)
        )
    }
}

private struct AgentRow: View {
    let agent: WorkbenchAgent
    let selected: Bool

    var body: some View {
        HStack(spacing: 10) {
            ZStack {
                Circle()
                    .fill(agent.kind.color.opacity(selected ? 0.22 : 0.10))
                    .frame(width: 34, height: 34)
                Text(agent.kind.shortName)
                    .font(BeagleTheme.dataFont(size: 10, weight: .bold))
                    .foregroundStyle(agent.kind.color)
            }
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(agent.displayName)
                        .font(BeagleTheme.uiFont(size: 12, weight: .semibold))
                        .foregroundStyle(BeagleTheme.textPrimary)
                    StatusDot(color: BeagleTheme.color(for: agent.status.truth), active: agent.status == .running)
                }
                Text(agent.currentTask)
                    .font(BeagleTheme.uiFont(size: 10))
                    .lineLimit(1)
                    .foregroundStyle(BeagleTheme.textTertiary)
                ProgressView(value: agent.activity)
                    .tint(agent.kind.color)
                    .scaleEffect(x: 1, y: 0.55, anchor: .center)
            }
            Spacer()
        }
        .padding(9)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(selected ? agent.kind.color.opacity(0.10) : Color.white.opacity(0.025))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(selected ? agent.kind.color.opacity(0.28) : Color.white.opacity(0.04), lineWidth: 1)
        )
    }
}

private struct StatusDot: View {
    let color: Color
    let active: Bool
    @State private var pulse = false

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: 7, height: 7)
            .shadow(color: color.opacity(active && pulse ? 0.8 : 0.2), radius: active && pulse ? 8 : 2)
            .onAppear {
                guard active else { return }
                withAnimation(.easeInOut(duration: 1.8).repeatForever(autoreverses: true)) {
                    pulse = true
                }
            }
    }
}

private struct ConversationSurface: View {
    @EnvironmentObject private var store: WorkbenchStore

    var body: some View {
        LiquidGlassSurface(elevated: true, truth: .observed, depth: 2) {
            VStack(spacing: 14) {
                ConversationHeader()
                IntentRibbon()
                LeaseBanner()
                MessageList()
                ComposerBar()
            }
        }
    }
}

private struct ConversationHeader: View {
    @EnvironmentObject private var store: WorkbenchStore

    var body: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 5) {
                Text("What are you working on?")
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(WorkbenchTone.paper)
                Text("Chat stays conversational; the canvas keeps artifacts, plans, and lease context visible before anything enters zellij.")
                    .font(BeagleTheme.uiFont(size: 12))
                    .foregroundStyle(BeagleTheme.textSecondary)
            }
            Spacer()
            if let agent = store.selectedAgent {
                HStack(spacing: 8) {
                    StatusDot(color: agent.kind.color, active: agent.status == .running)
                    VStack(alignment: .trailing, spacing: 1) {
                        Text("sending to")
                            .font(BeagleTheme.dataFont(size: 9))
                            .foregroundStyle(BeagleTheme.textTertiary)
                        Text(agent.displayName)
                            .font(BeagleTheme.dataFont(size: 12, weight: .medium))
                            .foregroundStyle(agent.kind.color)
                    }
                }
            }
        }
    }
}

private struct IntentRibbon: View {
    @EnvironmentObject private var store: WorkbenchStore

    private let intents: [(icon: String, title: String, prompt: String, truth: TruthMode)] = [
        ("text.magnifyingglass", "Understand", "explain the current lane without editing", .remembered),
        ("rectangle.and.pencil.and.ellipsis", "Draft", "draft a safe next instruction for the selected agent", .declared),
        ("checkmark.shield.fill", "Review", "review this plan for lease risk before sending", .observed)
    ]

    var body: some View {
        HStack(spacing: 10) {
            ForEach(intents, id: \.title) { intent in
                Button {
                    store.useStarter(intent.prompt)
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: intent.icon)
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(BeagleTheme.color(for: intent.truth))
                            .symbolEffect(.pulse, value: store.selectedAgentID)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(intent.title)
                                .font(BeagleTheme.uiFont(size: 12, weight: .semibold))
                                .foregroundStyle(BeagleTheme.textPrimary)
                            Text(intent.truth.rawValue)
                                .font(BeagleTheme.dataFont(size: 8, weight: .medium))
                                .foregroundStyle(BeagleTheme.textTertiary)
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .background(RoundedRectangle(cornerRadius: 13, style: .continuous).fill(WorkbenchTone.paper.opacity(0.055)))
                    .overlay(RoundedRectangle(cornerRadius: 13, style: .continuous).strokeBorder(BeagleTheme.color(for: intent.truth).opacity(0.16), lineWidth: 1))
                }
                .buttonStyle(.plain)
            }
        }
    }
}

private struct LeaseBanner: View {
    @EnvironmentObject private var store: WorkbenchStore

    var body: some View {
        let state = store.selectedLane?.leaseState ?? .clear
        HStack(spacing: 14) {
            LeaseGauge(state: state, compact: true)

            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Text("Lease guard")
                        .font(BeagleTheme.uiFont(size: 13, weight: .semibold))
                        .foregroundStyle(BeagleTheme.textPrimary)
                    TruthBadge(state.truth, compact: true)
                }
                HStack(spacing: 7) {
                    GuardGlyph(icon: "bubble.left.and.bubble.right.fill", label: "talk", truth: .observed)
                    GuardGlyph(icon: "eye.fill", label: "read", truth: .remembered)
                    GuardGlyph(icon: "pencil.and.scribble", label: "patch", truth: state.truth)
                    GuardGlyph(icon: "arrow.triangle.merge", label: "merge", truth: state == .clear ? .declared : .stale)
                }
            }

            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(WorkbenchTone.paper.opacity(0.045))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(BeagleTheme.color(for: state.truth).opacity(0.16), lineWidth: 1)
        )
    }
}

private struct GuardGlyph: View {
    let icon: String
    let label: String
    let truth: TruthMode

    var body: some View {
        VStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(BeagleTheme.color(for: truth))
                .frame(width: 24, height: 24)
                .background(Circle().fill(BeagleTheme.color(for: truth).opacity(0.11)))
            Text(label)
                .font(BeagleTheme.dataFont(size: 8, weight: .medium))
                .foregroundStyle(BeagleTheme.textTertiary)
        }
        .frame(width: 46)
    }
}

private struct MessageList: View {
    @EnvironmentObject private var store: WorkbenchStore

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 12) {
                    ForEach(store.messages) { message in
                        WorkbenchChatBubble(message: message)
                            .id(message.id)
                    }
                }
                .padding(.vertical, 4)
            }
            .onChange(of: store.messages.count) {
                if let last = store.messages.last {
                    withAnimation(.snappy) {
                        proxy.scrollTo(last.id, anchor: .bottom)
                    }
                }
            }
        }
    }
}

private struct WorkbenchChatBubble: View {
    let message: WorkbenchMessage
    @State private var cursorVisible = true

    private var isOperator: Bool {
        message.role == .operatorRole
    }

    private var accent: Color {
        if let kind = message.agentKind {
            return kind.color
        }
        return BeagleTheme.color(for: message.truth)
    }

    var body: some View {
        HStack(alignment: .top) {
            if isOperator { Spacer(minLength: 80) }
            VStack(alignment: isOperator ? .trailing : .leading, spacing: 5) {
                HStack(spacing: 7) {
                    if !isOperator {
                        AgentAvatar(kind: message.agentKind ?? .beagle)
                    }
                    VStack(alignment: isOperator ? .trailing : .leading, spacing: 1) {
                        Text(message.title ?? (isOperator ? "You" : "Beagle"))
                            .font(BeagleTheme.dataFont(size: 11, weight: .medium))
                            .foregroundStyle(accent)
                        Text(message.timestamp, style: .time)
                            .font(BeagleTheme.dataFont(size: 9))
                            .foregroundStyle(BeagleTheme.textTertiary)
                    }
                    if isOperator {
                        TruthBadge(.observed, compact: true)
                    }
                }

                Text(message.content + (message.isStreaming && cursorVisible ? " |" : ""))
                    .font(BeagleTheme.uiFont(size: 14))
                    .foregroundStyle(BeagleTheme.textPrimary)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 11)
                    .background(
                        RoundedRectangle(cornerRadius: 16)
                            .fill(isOperator ? WorkbenchTone.cyan.opacity(0.14) : WorkbenchTone.ink.opacity(0.86))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .strokeBorder(accent.opacity(isOperator ? 0.24 : 0.34), lineWidth: 1)
                    )
                    .shadow(color: accent.opacity(isOperator ? 0.10 : 0.14), radius: isOperator ? 8 : 14)
            }
            if !isOperator { Spacer(minLength: 80) }
        }
        .onAppear {
            if message.isStreaming {
                withAnimation(.easeInOut(duration: 0.53).repeatForever(autoreverses: true)) {
                    cursorVisible.toggle()
                }
            }
        }
    }
}

private struct AgentAvatar: View {
    let kind: WorkbenchAgentKind

    var body: some View {
        ZStack {
            Circle()
                .fill(kind.color.opacity(0.14))
                .frame(width: 28, height: 28)
            Text(kind.shortName)
                .font(BeagleTheme.dataFont(size: 9, weight: .bold))
                .foregroundStyle(kind.color)
        }
    }
}

private struct ComposerBar: View {
    @EnvironmentObject private var store: WorkbenchStore

    private let starters = [
        "claude-2: summarize parser risk, no patch yet.",
        "codex-1: review GPU notes without editing.",
        "/note lane decision: Sounio authority stays in project docs.",
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                ForEach(starters, id: \.self) { starter in
                    Button {
                        store.useStarter(starter)
                    } label: {
                        Text(starter)
                            .font(BeagleTheme.uiFont(size: 10, weight: .medium))
                            .lineLimit(1)
                            .foregroundStyle(BeagleTheme.textSecondary)
                            .padding(.horizontal, 9)
                            .padding(.vertical, 6)
                            .background(
                                Capsule()
                                    .fill(WorkbenchTone.paper.opacity(0.055))
                            )
                    }
                    .buttonStyle(.plain)
                }
            }

            HStack(alignment: .bottom, spacing: 10) {
                ZStack(alignment: .topLeading) {
                    TextEditor(text: $store.composerText)
                        .font(BeagleTheme.uiFont(size: 14))
                        .foregroundStyle(BeagleTheme.textPrimary)
                        .scrollContentBackground(.hidden)
                        .frame(minHeight: 58, maxHeight: 96)
                        .padding(7)
                    if store.composerText.isEmpty {
                        Text("Send into \(store.selectedAgent?.zellijTabName ?? "the selected zellij tab"). Try /whereami, /status, /note, /send.")
                            .font(BeagleTheme.uiFont(size: 13))
                            .foregroundStyle(BeagleTheme.textTertiary)
                            .padding(.horizontal, 13)
                            .padding(.vertical, 15)
                            .allowsHitTesting(false)
                    }
                }
                .background(
                    RoundedRectangle(cornerRadius: 16)
                        .fill(WorkbenchTone.paper.opacity(0.060))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .strokeBorder(WorkbenchTone.paper.opacity(0.16), lineWidth: 1)
                )

                Button {
                    store.sendComposerMessage()
                } label: {
                    let empty = store.composerText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 34, weight: .semibold))
                        .foregroundStyle(empty ? AnyShapeStyle(BeagleTheme.textTertiary) : AnyShapeStyle(WorkbenchTone.humanistGradient))
                }
                .buttonStyle(.plain)
                .disabled(store.composerText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
    }
}

private struct WorkbenchContextColumn: View {
    @EnvironmentObject private var store: WorkbenchStore

    var body: some View {
        VStack(spacing: 14) {
            AgentFocusPanel()
            WorkingCanvasPanel()
            SendSafetyPanel()
            if store.showingTerminal {
                TerminalPreviewPanel()
                    .frame(height: 210)
            }
            MemoryPanel()
        }
    }
}

private enum WorkingCanvasMode: String, CaseIterable, Identifiable {
    case artifact
    case plan
    case file

    var id: String { rawValue }

    var title: String {
        switch self {
        case .artifact: return "Artifact"
        case .plan: return "Plan"
        case .file: return "File"
        }
    }
}

private struct WorkingCanvasPanel: View {
    @EnvironmentObject private var store: WorkbenchStore
    @State private var mode: WorkingCanvasMode = .artifact

    var body: some View {
        LiquidGlassSurface(elevated: false, truth: store.selectedFile?.truth ?? .remembered) {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    LaneHeader(title: "Working canvas", truth: store.selectedFile?.truth ?? .remembered)
                    Spacer()
                    Picker("", selection: $mode) {
                        ForEach(WorkingCanvasMode.allCases) { canvasMode in
                            Text(canvasMode.title).tag(canvasMode)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .frame(width: 156)
                }

                switch mode {
                case .artifact:
                    ArtifactSketch()
                case .plan:
                    CanvasPlanView()
                case .file:
                    CompactFileCanvas()
                }
            }
        }
    }
}

private struct ArtifactSketch: View {
    @EnvironmentObject private var store: WorkbenchStore

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(WorkbenchTone.humanistGradient)
                        .opacity(0.16)
                        .frame(width: 58, height: 58)
                    Image(systemName: "sparkles.rectangle.stack.fill")
                        .font(.system(size: 22, weight: .bold))
                        .foregroundStyle(WorkbenchTone.humanistGradient)
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text(store.selectedLane?.title ?? "Workbench lane")
                        .font(BeagleTheme.displayFont(size: 16, weight: .semibold))
                        .foregroundStyle(BeagleTheme.textPrimary)
                        .lineLimit(1)
                    Text(store.selectedAgent?.currentTask ?? "Choose an agent to shape the artifact.")
                        .font(BeagleTheme.uiFont(size: 11))
                        .foregroundStyle(BeagleTheme.textSecondary)
                        .lineLimit(2)
                }
            }

            HStack(spacing: 8) {
                CanvasChip(icon: "arrow.triangle.branch", label: "forkable")
                CanvasChip(icon: "wand.and.sparkles", label: "fixable")
                CanvasChip(icon: "eye.fill", label: "preview")
            }

            SignalRibbon(intensity: .quiet)
                .frame(height: 46)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(WorkbenchTone.paper.opacity(0.12), lineWidth: 1))
        }
    }
}

private struct CanvasChip: View {
    let icon: String
    let label: String

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: icon)
                .font(.system(size: 10, weight: .bold))
            Text(label)
                .font(BeagleTheme.dataFont(size: 9, weight: .bold))
        }
        .foregroundStyle(WorkbenchTone.paper.opacity(0.82))
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(Capsule().fill(WorkbenchTone.paper.opacity(0.06)))
        .overlay(Capsule().strokeBorder(WorkbenchTone.ember.opacity(0.16), lineWidth: 1))
    }
}

private struct CanvasPlanView: View {
    @EnvironmentObject private var store: WorkbenchStore

    private var planRows: [(String, TruthMode)] {
        [
            ("Read current lane context", .observed),
            ("Draft before touching files", .remembered),
            ("Send through lease guard", store.selectedLane?.leaseState.truth ?? .declared)
        ]
    }

    var body: some View {
        VStack(spacing: 8) {
            ForEach(Array(planRows.enumerated()), id: \.offset) { index, row in
                HStack(spacing: 9) {
                    Text("\(index + 1)")
                        .font(BeagleTheme.dataFont(size: 10, weight: .bold))
                        .foregroundStyle(WorkbenchTone.void)
                        .frame(width: 22, height: 22)
                        .background(Circle().fill(BeagleTheme.color(for: row.1)))
                    Text(row.0)
                        .font(BeagleTheme.uiFont(size: 11, weight: .medium))
                        .foregroundStyle(BeagleTheme.textSecondary)
                    Spacer()
                    TruthBadge(row.1, compact: true)
                }
                .padding(8)
                .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(WorkbenchTone.ink.opacity(0.42)))
            }
        }
    }
}

private struct CompactFileCanvas: View {
    @EnvironmentObject private var store: WorkbenchStore

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            if let file = store.selectedFile {
                HStack {
                    Text(URL(fileURLWithPath: file.path).lastPathComponent)
                        .font(BeagleTheme.dataFont(size: 11, weight: .bold))
                        .foregroundStyle(BeagleTheme.textData)
                        .lineLimit(1)
                    Spacer()
                    Text(file.language.uppercased())
                        .font(BeagleTheme.dataFont(size: 9, weight: .bold))
                        .foregroundStyle(WorkbenchTone.sage)
                }
                ScrollView {
                    Text(file.body)
                        .font(BeagleTheme.dataFont(size: 10))
                        .foregroundStyle(BeagleTheme.textData)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                        .padding(10)
                }
                .frame(height: 142)
                .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(WorkbenchTone.void.opacity(0.72)))
            }
        }
    }
}

private struct SendSafetyPanel: View {
    @EnvironmentObject private var store: WorkbenchStore

    var body: some View {
        let state = store.selectedLane?.leaseState ?? .clear
        LiquidGlassSurface(elevated: false, truth: state.truth) {
            VStack(alignment: .leading, spacing: 12) {
                LaneHeader(title: "Lane radar", truth: state.truth)
                HStack(spacing: 12) {
                    LeaseCollisionGraph(lanes: store.lanes, selectedID: store.selectedLaneID)
                        .frame(width: 144)
                    VStack(spacing: 9) {
                        RouteGlyph(
                            icon: "terminal.fill",
                            value: store.selectedAgent?.zellijTabName ?? "pane",
                            truth: .observed
                        )
                        RouteGlyph(
                            icon: "eye.fill",
                            value: "read first",
                            truth: .remembered
                        )
                        RouteGlyph(
                            icon: "lock.shield.fill",
                            value: state.rawValue,
                            truth: state.truth
                        )
                    }
                }
            }
        }
    }
}

private struct RouteGlyph: View {
    let icon: String
    let value: String
    let truth: TruthMode

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(BeagleTheme.color(for: truth))
                .frame(width: 26, height: 26)
                .background(RoundedRectangle(cornerRadius: 8).fill(BeagleTheme.color(for: truth).opacity(0.10)))
            Text(value)
                .font(BeagleTheme.dataFont(size: 10, weight: .medium))
                .foregroundStyle(BeagleTheme.textData)
                .lineLimit(1)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(RoundedRectangle(cornerRadius: 11).fill(WorkbenchTone.void.opacity(0.50)))
    }
}

private struct ArtifactOrbitStrip: View {
    @EnvironmentObject private var store: WorkbenchStore

    private var artifacts: [(icon: String, title: String, level: Double, truth: TruthMode)] {
        [
            ("doc.text.magnifyingglass", "diff", 0.64, .remembered),
            ("brain.head.profile", "rag", 0.78, .remembered),
            ("lock.shield", "lease", store.selectedLane?.leaseState.rawValue == LeaseState.clear.rawValue ? 0.22 : 0.74, store.selectedLane?.leaseState.truth ?? .declared),
            ("sparkles.rectangle.stack", "agents", min(Double(store.activeAgents.count) / 6.0, 1.0), .observed)
        ]
    }

    var body: some View {
        HStack(spacing: 10) {
            ForEach(artifacts, id: \.title) { artifact in
                VStack(alignment: .leading, spacing: 8) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 9)
                            .fill(BeagleTheme.color(for: artifact.truth).opacity(0.11))
                            .frame(width: 34, height: 34)
                        Image(systemName: artifact.icon)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(BeagleTheme.color(for: artifact.truth))
                    }
                    HStack(spacing: 6) {
                        Text(artifact.title)
                            .font(BeagleTheme.dataFont(size: 10, weight: .bold))
                            .tracking(0.8)
                            .foregroundStyle(BeagleTheme.textPrimary)
                        Spacer(minLength: 0)
                        TruthBadge(artifact.truth, compact: true)
                    }
                    ProgressView(value: artifact.level)
                        .tint(BeagleTheme.color(for: artifact.truth))
                        .scaleEffect(x: 1, y: 0.55, anchor: .center)
                }
                .padding(9)
                .frame(maxWidth: .infinity)
                .background(
                    RoundedRectangle(cornerRadius: 14)
                        .fill(WorkbenchTone.midnight.opacity(0.48))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .strokeBorder(BeagleTheme.color(for: artifact.truth).opacity(0.18), lineWidth: 1)
                )
            }
        }
    }
}

private struct SafetyRow: View {
    let icon: String
    let label: String
    let value: String
    let truth: TruthMode

    var body: some View {
        HStack(spacing: 9) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(BeagleTheme.color(for: truth))
                .frame(width: 18)
            Text(label)
                .font(BeagleTheme.dataFont(size: 10))
                .foregroundStyle(BeagleTheme.textTertiary)
            Spacer()
            Text(value)
                .font(BeagleTheme.dataFont(size: 10, weight: .medium))
                .foregroundStyle(BeagleTheme.textData)
                .lineLimit(1)
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 7)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(BeagleTheme.surface0.opacity(0.50))
        )
    }
}

private struct AgentFocusPanel: View {
    @EnvironmentObject private var store: WorkbenchStore

    var body: some View {
        LiquidGlassSurface(elevated: false, truth: store.selectedAgent?.status.truth ?? .declared) {
            VStack(alignment: .leading, spacing: 10) {
                LaneHeader(title: "Selected agent", truth: store.selectedAgent?.status.truth ?? .declared)
                if let agent = store.selectedAgent {
                    HStack(spacing: 11) {
                        PresenceOrb(agent: agent, compact: true)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(agent.displayName)
                                .font(BeagleTheme.displayFont(size: 17, weight: .semibold))
                                .foregroundStyle(BeagleTheme.textPrimary)
                            Text(agent.kind.displayName)
                                .font(BeagleTheme.dataFont(size: 11))
                                .foregroundStyle(agent.kind.color)
                        }
                        Spacer()
                        TruthBadge(agent.status.truth)
                    }
                    Text(agent.currentTask)
                        .font(BeagleTheme.uiFont(size: 12))
                        .foregroundStyle(BeagleTheme.textSecondary)
                    HStack {
                        Text("zellij")
                            .font(BeagleTheme.dataFont(size: 10))
                            .foregroundStyle(BeagleTheme.textTertiary)
                        Text(agent.zellijTabName)
                            .font(BeagleTheme.dataFont(size: 11, weight: .medium))
                            .foregroundStyle(BeagleTheme.textData)
                        Spacer()
                        Text("\(Int(agent.activity * 100))%")
                            .font(BeagleTheme.dataFont(size: 11))
                            .foregroundStyle(agent.kind.color)
                    }
                    ProgressView(value: agent.activity)
                        .tint(agent.kind.color)
                }
            }
        }
    }
}

private struct FilePreviewPanel: View {
    @EnvironmentObject private var store: WorkbenchStore

    var body: some View {
        LiquidGlassSurface(elevated: false, truth: store.selectedFile?.truth ?? .declared) {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    LaneHeader(title: "Read-only file", truth: store.selectedFile?.truth ?? .declared)
                    Spacer()
                    Picker("", selection: $store.selectedFileID) {
                        ForEach(store.filePreviews) { file in
                            Text(URL(fileURLWithPath: file.path).lastPathComponent).tag(file.id)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 128)
                }
                if let file = store.selectedFile {
                    VStack(alignment: .leading, spacing: 5) {
                        Text(file.path)
                            .font(BeagleTheme.dataFont(size: 10))
                            .foregroundStyle(BeagleTheme.textTertiary)
                            .lineLimit(1)
                        HStack {
                            Text(file.language.uppercased())
                                .font(BeagleTheme.dataFont(size: 9, weight: .medium))
                                .foregroundStyle(BeagleTheme.truthRemembered)
                            Spacer()
                            Text("owner: \(store.agentName(for: file.ownerAgentID))")
                                .font(BeagleTheme.dataFont(size: 9))
                                .foregroundStyle(BeagleTheme.textTertiary)
                        }
                    }
                    ScrollView {
                        Text(file.body)
                            .font(BeagleTheme.dataFont(size: 11))
                            .foregroundStyle(BeagleTheme.textData)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .textSelection(.enabled)
                            .padding(12)
                    }
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(BeagleTheme.surface0.opacity(0.72))
                    )
                }
            }
        }
    }
}

private struct TerminalPreviewPanel: View {
    @EnvironmentObject private var store: WorkbenchStore

    var body: some View {
        LiquidGlassSurface(elevated: false, truth: .observed) {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    LaneHeader(title: "Terminal readback", truth: .observed)
                    Spacer()
                    Text(store.workspace.source.rawValue)
                        .font(BeagleTheme.dataFont(size: 10, weight: .medium))
                        .foregroundStyle(BeagleTheme.postureWarm)
                }
                ScrollView {
                    VStack(alignment: .leading, spacing: 5) {
                        ForEach(store.terminalLines) { line in
                            HStack(alignment: .firstTextBaseline, spacing: 8) {
                                Text("[\(line.source)]")
                                    .font(BeagleTheme.dataFont(size: 10, weight: .medium))
                                    .foregroundStyle(BeagleTheme.color(for: line.truth))
                                Text(line.text)
                                    .font(BeagleTheme.dataFont(size: 11))
                                    .foregroundStyle(BeagleTheme.textData)
                                Spacer(minLength: 0)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(10)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(BeagleTheme.surface0.opacity(0.80))
                )
            }
        }
    }
}

private struct MemoryPanel: View {
    var body: some View {
        LiquidGlassSurface(elevated: false, truth: .remembered) {
            VStack(alignment: .leading, spacing: 10) {
                LaneHeader(title: "Beagle memory", truth: .remembered)
                Text("Not wired in reset build.")
                    .font(BeagleTheme.uiFont(size: 11))
                    .foregroundStyle(BeagleTheme.textSecondary)
            }
        }
    }
}

private struct MemoryStat: View {
    let value: String
    let label: String

    var body: some View {
        VStack(spacing: 3) {
            Text(value)
                .font(BeagleTheme.dataFont(size: 12, weight: .bold))
                .foregroundStyle(BeagleTheme.truthRemembered)
            Text(label)
                .font(BeagleTheme.dataFont(size: 9))
                .foregroundStyle(BeagleTheme.textTertiary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(BeagleTheme.truthRemembered.opacity(0.08))
        )
    }
}
