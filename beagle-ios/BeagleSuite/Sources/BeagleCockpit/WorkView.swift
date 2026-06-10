//
//  WorkView.swift
//  BeagleCockpit
//
//  The Work tab. Visual-first agent lanes backed by a hidden workspace runtime.
//  Runtime logs remain available on demand, but the first surface is the bench.
//

import SwiftUI
import BeagleCore
import BeagleWorkbenchKit

struct WorkView: View {
    @Environment(CatalogStore.self) private var catalog
    @Environment(CognitiveStore.self) private var cognitive
    @Binding var bootError: String?

    @State private var terminal = TerminalStore()
    @State private var exocortex = ExocortexStore()
    @State private var terminalInputText = ""
    @State private var showAgentSession = false
    @State private var showPlatform = false
    @State private var showPaperWorkbench = false
    @State private var workMemoryStatus = "Work memory idle"
    @State private var workspaceSession: WorkspaceSession?
    @State private var activePane: TerminalPane?
    @State private var terminalBlocks: [TerminalBlock] = []
    @State private var selectedBlockId: String?
    @State private var workbenchStatus = "Preparing agent deck"
    @State private var workbenchError: String?
    @State private var isRefreshingWorkbench = false
    @State private var runtimeLogPresentation: RuntimeLogPresentationState?
    @State private var showScoutLanes = false
    @State private var showRendererBakeOff = false
    @State private var rendererJudgments: [RendererHumanJudgment] = []
    @State private var agentRoles: [AgentRole] = []
    @State private var latestRouteDecision: AgentRouteDecision?
    @State private var providerSetupTarget: ProviderSetupTarget?

    var body: some View {
        GeometryReader { proxy in
            VStack(spacing: 0) {
                WorkbenchHeader(
                    slug: activeSlug,
                    session: workspaceSession,
                    pane: activePane,
                    connectionState: terminal.connectionState,
                    status: workbenchStatus,
                    error: workbenchError,
                    blockCount: visualCanvasState.recentArtifacts.count
                )

                if proxy.size.width >= 980 {
                    VisualWorkbenchStage(
                        state: visualCanvasState,
                        onOpenLane: { lane in
                            Task { await openLane(lane.id, startProcess: false, showTerminal: false) }
                        },
                        onStartLane: { lane in
                            Task { await openLane(lane.id, startProcess: lane.kind != "human", showTerminal: false) }
                        },
                        onSetUpLane: { lane in
                            presentProviderSetup(for: lane.id)
                        },
                        onRuntimeLane: { lane in
                            Task { await openLane(lane.id, startProcess: false, showTerminal: true) }
                        },
                        onSelectArtifact: { artifact in
                            if let blockId = artifact.sourceBlockId {
                                selectedBlockId = blockId
                            }
                        },
                        onRememberArtifact: { artifact in
                            Task { await rememberArtifact(artifact) }
                        },
                        onBakeOffArtifact: { artifact in
                            if let blockId = artifact.sourceBlockId {
                                selectedBlockId = blockId
                                showRendererBakeOff = true
                            }
                        },
                        onRuntime: { presentRuntimeLog() }
                    )
                } else {
                    VStack(spacing: 0) {
                        AgentConsoleView(
                            snapshot: agentConsoleSnapshot,
                            onOpenLane: { lane in
                                Task { await openLane(lane, startProcess: false, showTerminal: false) }
                            },
                            onStartLane: { lane in
                                Task { await openLane(lane, startProcess: lane != "shell", showTerminal: false) }
                            },
                            onSetUpLane: { lane in
                                presentProviderSetup(for: lane)
                            },
                            onShowTerminal: {
                                presentRuntimeLog()
                            }
                        )
                        .padding(.horizontal, BeagleSpacing.md)
                        .padding(.vertical, BeagleSpacing.sm)
                        if !scoutAgentRoles.isEmpty {
                            ScoutLaneDrawer(
                                isExpanded: $showScoutLanes,
                                lanes: scoutAgentRoles.map(agentLaneState),
                                onOpenLane: { lane in
                                    Task { await openLane(lane, startProcess: false, showTerminal: false) }
                                },
                                onStartLane: { lane in
                                    Task { await openLane(lane, startProcess: true, showTerminal: false) }
                                },
                                onSetUpLane: { lane in
                                    presentProviderSetup(for: lane)
                                }
                            )
                            .padding(.horizontal, BeagleSpacing.md)
                            .padding(.bottom, BeagleSpacing.xs)
                        }
                        VisualWorkCanvas(
                            state: visualCanvasState,
                            onSelectArtifact: { artifact in
                                if let blockId = artifact.sourceBlockId {
                                    selectedBlockId = blockId
                                }
                            },
                            onRuntime: { presentRuntimeLog() },
                            onRemember: { Task { await rememberSelectedOrLatestBlock() } },
                            onBakeOff: {
                                if selectedBakeOffSample != nil {
                                    showRendererBakeOff = true
                                }
                            }
                        )
                        CompactEvidenceRail(
                            artifacts: visualCanvasState.recentArtifacts,
                            selectedArtifactId: visualCanvasState.selectedArtifact?.id,
                            onSelect: { artifact in
                                if let blockId = artifact.sourceBlockId {
                                    selectedBlockId = blockId
                                }
                            },
                            onRemember: { artifact in
                                Task { await rememberArtifact(artifact) }
                            },
                            onBakeOff: { artifact in
                                if let blockId = artifact.sourceBlockId {
                                    selectedBlockId = blockId
                                    showRendererBakeOff = true
                                }
                            }
                        )
                        latestWorkMemoryStrip
                    }
                }

                if proxy.size.width >= 980 {
                    VisualWorkbenchActionDock(
                        state: workbenchDockState,
                        onInterrupt: { terminal.sendSignal("SIGINT") },
                        onApprove: { terminal.approve() },
                        onRemember: { Task { await rememberSelectedOrLatestBlock() } },
                        onFocus: { Task { await openLane("primary_builder", startProcess: true, showTerminal: false) } },
                        onScout: { Task { await openLane("long_thought_architect", startProcess: true, showTerminal: false) } },
                        onCompare: { Task { await openLane("code_worker", startProcess: true, showTerminal: false) } },
                        onRuntime: { presentRuntimeLog() },
                        onRefresh: { Task { await prepareWorkbench(forceNew: false) } }
                    )
                } else {
                    AgentConsoleDock(
                        state: workbenchDockState,
                        onInput: { presentRuntimeLog() },
                        onInterrupt: { terminal.sendSignal("SIGINT") },
                        onApprove: { terminal.approve() },
                        onRemember: { Task { await rememberSelectedOrLatestBlock() } },
                        onFocus: { Task { await openLane("primary_builder", startProcess: true, showTerminal: false) } },
                        onScout: { Task { await openLane("long_thought_architect", startProcess: true, showTerminal: false) } },
                        onCompare: { Task { await openLane("code_worker", startProcess: true, showTerminal: false) } },
                        onOpenTerminal: { Task { await openLane("shell", startProcess: false, showTerminal: true) } }
                    )
                }
            }
        }
        .background(Color(red: 0.02, green: 0.03, blue: 0.06))
        .navigationTitle("Work")
        #if !os(macOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            ToolbarItem(placement: toolbarPlacement) {
                Menu {
                    Button {
                        showAgentSession = true
                    } label: {
                        Label("Agent Sessions", systemImage: "bolt.fill")
                    }
                    Button {
                        showPlatform = true
                    } label: {
                        Label("Platform", systemImage: "server.rack")
                    }
                    Button {
                        showPaperWorkbench = true
                    } label: {
                        Label("Sounio PaperRun", systemImage: "doc.richtext")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .foregroundStyle(BeagleTheme.textSecondary)
                }
            }
        }
        .task {
            await prepareWorkbench()
            await refreshWorkMemoryContext()
        }
        .sheet(isPresented: $showAgentSession) {
            NavigationStack {
                AgentSessionView(slug: activeSlug)
            }
        }
        .sheet(isPresented: $showPlatform) {
            NavigationStack {
                PlatformView()
                    .navigationDestination(for: Project.self) { project in
                        ControlRoomView(slug: project.projectSlug)
                    }
            }
        }
        .sheet(isPresented: $showPaperWorkbench) {
            NavigationStack {
                SounioPaperWorkbenchView()
            }
        }
        .sheet(item: $providerSetupTarget) { target in
            ProviderSetupView(target: target) {
                Task { await refreshAgentRegistry() }
            }
        }
        .sheet(item: $runtimeLogPresentation) { runtime in
            NavigationStack {
                terminalColumn
                    .navigationTitle(runtime.title)
                    #if !os(macOS)
                    .navigationBarTitleDisplayMode(.inline)
                    #endif
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Done") { runtimeLogPresentation = nil }
                        }
                    }
            }
        }
        .sheet(isPresented: $showRendererBakeOff) {
            if let sample = selectedBakeOffSample {
                NavigationStack {
                    RendererBakeOffSheet(
                        sample: sample,
                        judgments: rendererJudgments,
                        onRecordJudgment: { judgment in
                            rendererJudgments.insert(judgment, at: 0)
                        }
                    )
                }
            }
        }
    }

    // MARK: - Quick access strip

    private var toolbarPlacement: ToolbarItemPlacement {
        #if os(macOS)
        return .automatic
        #else
        return .topBarTrailing
        #endif
    }

    private var terminalColumn: some View {
        VStack(spacing: 0) {
            TerminalContentView(
                terminal: terminal,
                onReconnect: { Task { await prepareWorkbench(forceNew: false) } },
                sessionIdentityText: workspaceSession?.id ?? activeSlug
            )

            BeagleInputBar(
                text: $terminalInputText,
                placeholder: activePane.map { "> \($0.title.lowercased())" } ?? "> command",
                mode: .terminal,
                isEnabled: terminal.connectionState.isConnected,
                onSubmit: { text in
                    terminal.sendInput(text + "\n")
                },
                onSpecialKey: { key in
                    terminal.sendInput(key.escapeSequence)
                }
            )

            HStack(spacing: BeagleSpacing.xs) {
                Image(systemName: memoryStatusIcon)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(memoryStatusTint)
                Text(workMemoryStatus)
                    .font(BeagleFont.caption2.font)
                    .foregroundStyle(BeagleTheme.textTertiary)
                    .lineLimit(1)
                Spacer()
                Button {
                    Task { await refreshWorkbenchBlocks() }
                } label: {
                    Image(systemName: isRefreshingWorkbench ? "arrow.triangle.2.circlepath" : "arrow.clockwise")
                        .font(.system(size: 11, weight: .semibold))
                }
                .buttonStyle(.plain)
                .foregroundStyle(BeagleTheme.textTertiary)
                .disabled(isRefreshingWorkbench)
            }
            .padding(.horizontal, BeagleSpacing.md)
            .padding(.vertical, 4)
            .background(BeagleTheme.surface1.opacity(0.5))
        }
    }

    private var quickAccessStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 0) {
                quickButton("Agent", icon: runningAgentCount > 0 ? "bolt.fill" : "bolt", tint: runningAgentCount > 0 ? BeagleTheme.postureWarm : BeagleTheme.textTertiary) {
                    showAgentSession = true
                }
                quickButton("Split", icon: "rectangle.split.2x1", tint: BeagleTheme.textTertiary) {
                    Task { await createWorkbenchPane(kind: "human", title: "Shell") }
                }
                quickButton("Codex", icon: "sparkles.rectangle.stack", tint: BeagleTheme.truthRemembered) {
                    Task { await createWorkbenchPane(kind: "codex", title: "Codex") }
                }
                quickButton("Interrupt", icon: "pause.circle", tint: BeagleTheme.postureWarm) {
                    terminal.sendSignal("SIGINT")
                }
                quickButton("Approve", icon: "checkmark.circle", tint: BeagleTheme.truthObserved) {
                    terminal.approve()
                }
                quickButton("Remember", icon: "externaldrive.connected.to.line.below", tint: BeagleTheme.truthObserved) {
                    Task { await rememberSelectedOrLatestBlock() }
                }
                quickButton("Bake-off", icon: "rectangle.split.2x1", tint: BeagleTheme.truthRemembered) {
                    if selectedBakeOffSample != nil {
                        showRendererBakeOff = true
                    }
                }
                quickButton("Reconnect", icon: "arrow.clockwise", tint: terminal.connectionState.isConnected ? BeagleTheme.truthObserved : BeagleTheme.stateError) {
                    Task { await prepareWorkbench(forceNew: false) }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, BeagleSpacing.xs)
        .background(.ultraThinMaterial)
    }

    private var latestWorkMemoryStrip: some View {
        HStack(alignment: .top, spacing: BeagleSpacing.xs) {
            Image(systemName: "hammer.circle")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(BeagleTheme.truthObserved)
                .frame(width: 16)
            VStack(alignment: .leading, spacing: 2) {
                Text("Latest work memory")
                    .font(BeagleFont.caption2.font)
                    .fontWeight(.semibold)
                    .foregroundStyle(BeagleTheme.textTertiary)
                Text(latestWorkMemoryLine)
                    .font(BeagleFont.caption2.font)
                    .foregroundStyle(BeagleTheme.textSecondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: BeagleSpacing.xs)
        }
        .padding(.horizontal, BeagleSpacing.md)
        .padding(.vertical, 5)
        .background(BeagleTheme.surface0.opacity(0.55))
    }

    private func quickButton(_ label: String, icon: String, tint: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 2) {
                Image(systemName: icon)
                    .font(.system(size: 13))
                Text(label)
                    .font(BeagleFont.caption2.font)
            }
            .foregroundStyle(tint)
            .frame(width: 78)
        }
        .buttonStyle(.plain)
    }

    private var selectedBakeOffSample: WorkbenchBakeOffSample? {
        let block = selectedBlockId.flatMap { id in
            terminalBlocks.first(where: { $0.id == id })
        } ?? terminalBlocks.first
        return block.map(WorkbenchBakeOffSample.init(block:))
    }

    // MARK: - Workbench connection

    private func prepareWorkbench(forceNew: Bool = false) async {
        workbenchError = nil
        workbenchStatus = "Opening Agent Deck..."
        let slug = activeSlug
        await refreshAgentRegistry()

        let session: WorkspaceSession
        if !forceNew,
           let existing = workspaceSession,
           existing.projectSlug == slug {
            session = existing
        } else {
            if !forceNew,
               let latest = (await CockpitClient.shared.workspaceSessions(slug: slug)).value?.sessions.first {
                session = latest
            } else if let created = (await CockpitClient.shared.createWorkspaceSession(slug: slug)).value?.session {
                session = created
            } else {
                workbenchError = "Workspace agent unavailable. Runtime recovery is available."
                workbenchStatus = "Recovery runtime"
                terminal.connectTerminal(slug: slug)
                return
            }
        }

        workspaceSession = session
        let pane: TerminalPane?
        if let firstPane = session.panes.first {
            pane = firstPane
        } else {
            pane = await createPaneWithoutConnecting(sessionId: session.id)
        }
        guard let pane else {
            workbenchError = "Could not create a Notebook Terminal pane."
            terminal.connectTerminal(slug: slug)
            return
        }
        connectWorkbenchPane(pane)
        await refreshWorkbenchBlocks()
    }

    private func createPaneWithoutConnecting(sessionId: String) async -> TerminalPane? {
        let response = await CockpitClient.shared.createWorkspacePane(
            slug: activeSlug,
            sessionId: sessionId,
            kind: "human",
            title: "Shell"
        )
        if let payload = response.value {
            workspaceSession = payload.session
            return payload.pane
        }
        workbenchError = response.error
        return nil
    }

    private func createWorkbenchPane(kind: String, title: String) async {
        guard let session = workspaceSession else {
            await prepareWorkbench(forceNew: false)
            return
        }
        let response = await CockpitClient.shared.createWorkspacePane(
            slug: activeSlug,
            sessionId: session.id,
            kind: kind,
            title: title
        )
        guard let payload = response.value else {
            workbenchError = response.error ?? "Could not create pane"
            return
        }
        workspaceSession = payload.session
        connectWorkbenchPane(payload.pane)
        await refreshWorkbenchBlocks()
    }

    private func connectWorkbenchPane(_ pane: TerminalPane) {
        guard let session = workspaceSession else {
            terminal.connectTerminal(slug: activeSlug)
            return
        }
        activePane = pane
        workbenchStatus = "Attached to \(pane.title)"
        terminal.connectWorkspacePane(slug: activeSlug, sessionId: session.id, paneId: pane.id)
    }

    private func openLane(_ lane: String, startProcess: Bool, showTerminal: Bool) async {
        guard let prepared = await ensurePaneForLane(lane) else { return }
        let pane = prepared.pane
        connectWorkbenchPane(pane)
        if showTerminal {
            presentRuntimeLog(title: pane.title, paneId: pane.id)
        }
        if startProcess, let command = prepared.startCommand ?? launchCommand(for: lane) {
            try? await Task.sleep(for: .milliseconds(650))
            terminal.startProcess(command)
        }
    }

    private func ensurePaneForLane(_ lane: String) async -> (pane: TerminalPane, startCommand: String?)? {
        if let pane = paneForLane(lane) {
            return (pane, nil)
        }
        if workspaceSession == nil {
            await prepareWorkbench(forceNew: false)
        }
        guard let session = workspaceSession else { return nil }
        if let role = agentRole(for: lane) {
            let response = await CockpitClient.shared.startAgentRole(
                slug: activeSlug,
                roleOrKind: role.role,
                sessionId: session.id,
                task: "Open \(role.title) lane for Sounio Workbench"
            )
            if let payload = response.value {
                workspaceSession = payload.session
                latestRouteDecision = payload.decision
                await refreshWorkbenchBlocks()
                return (payload.pane, payload.startCommand?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false ? payload.startCommand : nil)
            }
            workbenchError = response.error ?? "Could not start \(role.title) lane"
        }
        let response = await CockpitClient.shared.createWorkspacePane(
            slug: activeSlug,
            sessionId: session.id,
            kind: paneKind(for: lane),
            title: laneTitle(lane)
        )
        guard let payload = response.value else {
            workbenchError = response.error ?? "Could not create \(laneTitle(lane)) lane"
            return nil
        }
        workspaceSession = payload.session
        await refreshWorkbenchBlocks()
        return (payload.pane, launchCommand(for: lane))
    }

    private func paneForLane(_ lane: String) -> TerminalPane? {
        let role = agentRole(for: lane)
        return workspaceSession?.panes.first { pane in
            if let role {
                return pane.agentRole == role.role || normalizedLaneKind(pane.kind) == role.kind
            }
            return normalizedLaneKind(pane.kind) == normalizedLaneKind(lane)
        }
    }

    private func normalizedLaneKind(_ kind: String?) -> String {
        switch kind {
        case "codex": return "codex"
        case "claude-code": return "claude-code"
        case "minimax": return "minimax"
        case "qwen-coder": return "qwen-coder"
        case "glm-air": return "glm-air"
        case "palmyra-x5": return "palmyra-x5"
        case "jamba": return "jamba"
        case "pegasus": return "pegasus"
        case "lfm2": return "lfm2"
        case "cursor", "opencode": return kind ?? "cursor"
        case "human", "shell": return "shell"
        default: return kind ?? "shell"
        }
    }

    private func paneKind(for lane: String) -> String {
        if let role = agentRole(for: lane) {
            return role.kind == "human" ? "human" : role.kind
        }
        return lane == "shell" ? "human" : lane
    }

    private func laneTitle(_ lane: String) -> String {
        if let role = agentRole(for: lane) {
            return role.title
        }
        switch lane {
        case "codex": return "Codex"
        case "claude-code": return "Claude Code"
        case "minimax": return "MiniMax Worker"
        case "kimi": return "Kimi Architect"
        case "qwen-coder": return "Qwen Maintainer"
        case "glm-air": return "GLM Operator"
        default: return "Shell"
        }
    }

    private func launchCommand(for lane: String) -> String? {
        if let role = agentRole(for: lane) {
            let slotCommand = role.providerSlots.first(where: { $0.enabled })?.command?.trimmingCharacters(in: .whitespacesAndNewlines)
            if let slotCommand, !slotCommand.isEmpty { return slotCommand }
            let launch = role.launchCommand?.trimmingCharacters(in: .whitespacesAndNewlines)
            return launch?.isEmpty == false ? launch : nil
        }
        switch lane {
        case "codex": return "codex"
        case "claude-code": return "claude"
        default: return nil
        }
    }

    private func agentRole(for lane: String) -> AgentRole? {
        let key = lane.trimmingCharacters(in: .whitespacesAndNewlines)
        return visibleAgentRoles.first { role in
            role.role == key || role.kind == key || role.providerSlots.contains(where: { $0.id == key })
        } ?? agentRoles.first { role in
            role.role == key || role.kind == key || role.providerSlots.contains(where: { $0.id == key })
        }
    }

    private func refreshAgentRegistry() async {
        let response = await CockpitClient.shared.agentRegistry(slug: activeSlug)
        if let roles = response.value?.roles, !roles.isEmpty {
            agentRoles = roles
        }
    }

    /// Builds and presents the provider Set-up sheet for a lane. Falls back to
    /// launching the lane when no configurable provider slot exists (e.g. the
    /// CLI/PATH-based or shell lanes), so the affordance never dead-ends.
    private func presentProviderSetup(for laneId: String) {
        guard let role = agentRole(for: laneId) else {
            Task { await openLane(laneId, startProcess: laneId != "shell", showTerminal: false) }
            return
        }
        let target = ProviderSetupTarget(
            slug: activeSlug,
            role: role.role,
            title: role.title,
            subtitle: role.subtitle,
            slots: role.providerSlots,
            setupReason: role.readiness?.reason
        )
        guard !target.configurableSlots.isEmpty else {
            Task { await openLane(laneId, startProcess: laneId != "shell", showTerminal: false) }
            return
        }
        providerSetupTarget = target
    }

    private func refreshWorkbenchBlocks() async {
        guard let session = workspaceSession else { return }
        isRefreshingWorkbench = true
        defer { isRefreshingWorkbench = false }
        let response = await CockpitClient.shared.workspaceBlocks(slug: activeSlug, sessionId: session.id)
        if let payload = response.value {
            terminalBlocks = payload.blocks
            if selectedBlockId == nil {
                selectedBlockId = payload.blocks.first?.id
            }
            workbenchStatus = payload.blocks.isEmpty ? "Notebook is live; no curated blocks yet" : "\(payload.blocks.count) curated blocks"
        } else if let error = response.error {
            workbenchError = error
        }
    }

    private func rememberSelectedOrLatestBlock() async {
        if let selectedBlockId,
           let selected = terminalBlocks.first(where: { $0.id == selectedBlockId }) {
            await rememberBlock(selected)
            return
        }
        if let selectedBlockId,
           let selected = terminal.liveBlocks.first(where: { $0.id == selectedBlockId }) {
            await rememberBlockId(
                selected.id,
                title: selected.title,
                fallbackSessionId: selected.sessionId
            )
            return
        }
        if let latest = terminalBlocks.first {
            await rememberBlock(latest)
            return
        }
        if let latest = terminal.liveBlocks.first {
            await rememberBlockId(
                latest.id,
                title: latest.title,
                fallbackSessionId: latest.sessionId
            )
            return
        }
        await recordWorkMemory()
    }

    private func rememberArtifact(_ artifact: VisualWorkArtifact) async {
        guard let blockId = artifact.sourceBlockId else {
            await recordWorkMemory()
            return
        }
        await rememberBlockId(
            blockId,
            title: artifact.title,
            fallbackSessionId: workspaceSession?.id
        )
    }

    private func rememberBlock(_ block: TerminalBlock) async {
        await rememberBlockId(block.id, title: block.title, fallbackSessionId: block.sessionId)
    }

    private func rememberBlockId(_ blockId: String, title: String, fallbackSessionId: String? = nil) async {
        guard let sessionId = workspaceSession?.id ?? fallbackSessionId else { return }
        workMemoryStatus = "Curating block..."
        let response = await CockpitClient.shared.rememberWorkspaceBlock(
            slug: activeSlug,
            sessionId: sessionId,
            blockId: blockId
        )
        if let payload = response.value {
            switch payload.memory.status {
            case "remembered":
                workMemoryStatus = "Remembered block \(title)"
            case "blocked":
                workMemoryStatus = "Blocked: restricted or secret-like content"
            case "queued":
                workMemoryStatus = "Queued until cluster token is available"
            default:
                workMemoryStatus = payload.memory.error ?? payload.memory.reason ?? payload.memory.status
            }
            await refreshWorkbenchBlocks()
            await refreshWorkMemoryContext()
        } else {
            workMemoryStatus = response.error ?? "Block memory import failed"
        }
    }

    private func recordWorkMemory() async {
        let project = catalog.projects.first(where: { $0.projectSlug == activeSlug })
        let snapshot = AgentWorkMemorySnapshot(
            projectSlug: activeSlug,
            repo: project?.repoUrl,
            branch: project?.branch ?? project?.preferredPrBase,
            sessionId: "beagle-work-\(activeSlug)-\(UUID().uuidString.lowercased())",
            agentKind: "beagle-apple-work",
            objective: "Continue work on \(activeSlug) from the Beagle app Work surface.",
            planSummary: "User opened Work surface with terminal and agent sessions available.",
            diffSummary: nil,
            testsSummary: nil,
            decisionSummary: "Record current Work context as GraphRAG++ operational memory.",
            createdAt: AssistedImportRequestFactory.isoTimestamp()
        )
        let request = AssistedImportRequestFactory.workMemory(snapshot)
        guard request.privacyClass != "restricted" else {
            workMemoryStatus = "Restricted work context held locally."
            return
        }
        let result = await BeagleClient.shared.assistedImportBatch(request)
        if let imported = result.value, imported.status == "imported" {
            let atoms = imported.projection?.atomsCreated ?? 0
            workMemoryStatus = "Work memory imported: \(atoms) atoms"
            await refreshWorkMemoryContext()
        } else {
            workMemoryStatus = result.error ?? result.value?.reason ?? "Work memory import failed"
        }
    }

    private func refreshWorkMemoryContext() async {
        async let home: Void = exocortex.refresh(activeProjectSlug: activeSlug, platform: "beagle-apple-work")
        async let graph: Void = exocortex.refreshRecentGraph(limit: 16)
        _ = await (home, graph)
    }

    private func presentRuntimeLog(title: String? = nil, paneId: String? = nil) {
        runtimeLogPresentation = RuntimeLogPresentationState(
            title: title ?? activePane?.title ?? "Runtime Log",
            sessionId: workspaceSession?.id,
            paneId: paneId ?? activePane?.id,
            isRuntimePrimary: false
        )
    }

    // MARK: - Computed

    private var activeSlug: String {
        cognitive.activeProjectSlug ?? catalog.primaryProject?.projectSlug ?? "sounio"
    }

    private var runningAgentCount: Int {
        cognitive.state.value?.agentSessions?.filter { ($0.readyReplicas ?? 0) > 0 }.count ?? 0
    }

    private var agentConsoleSnapshot: AgentConsoleSnapshot {
        AgentConsoleSnapshot(
            projectSlug: activeSlug,
            sessionId: workspaceSession?.id,
            lanes: visibleAgentRoles.map(agentLaneState),
            activeLaneKind: activePane?.agentRole ?? normalizedLaneKind(activePane?.kind),
            authority: workspaceSession?.authorityStatus?.authority,
            updatedAt: terminal.workbenchEvents.last?.at ?? workspaceSession?.updatedAt
        )
    }

    private var visualCanvasState: VisualWorkCanvasState {
        VisualWorkCanvasState.synthesized(
            projectSlug: activeSlug,
            session: workspaceSession,
            lanes: agentConsoleSnapshot.lanes,
            blocks: terminalBlocks,
            liveBlocks: terminal.liveBlocks,
            selectedBlockId: selectedBlockId,
            workMemoryLine: latestWorkMemoryLine,
            workMemoryStatus: workMemoryStatus
        )
    }

    private var workbenchDockState: WorkbenchActionDockState {
        WorkbenchActionDockState(
            canSendInput: terminal.connectionState.isConnected,
            canInterrupt: terminal.connectionState.isConnected,
            canApprove: terminal.connectionState.isConnected,
            canRemember: !terminalBlocks.isEmpty || !terminal.liveBlocks.isEmpty,
            activeLaneKind: activePane?.agentRole ?? normalizedLaneKind(activePane?.kind)
        )
    }

    private var visibleAgentRoles: [AgentRole] {
        let roles = agentRoles.isEmpty ? defaultAgentRoles : agentRoles
        let visible = roles.filter { $0.visible }
        return visible.isEmpty ? defaultAgentRoles : visible
    }

    private var scoutAgentRoles: [AgentRole] {
        guard !agentRoles.isEmpty else { return [] }
        return agentRoles.filter { !$0.visible }
    }

    private var defaultAgentRoles: [AgentRole] {
        [
            AgentRole(role: "primary_builder", kind: "codex", title: "Claude / Codex", subtitle: "High-stakes implementation", arousalRole: "phasic_focus", providerSlots: [
                AgentProviderSlot(id: "codex-cli", title: "Codex", modelId: "codex", command: "codex", runtime: "cli", costTier: "premium", latencyTier: "interactive", privacyTier: "workspace"),
                AgentProviderSlot(id: "claude-code-cli", title: "Claude Code", modelId: "claude-code", command: "claude", runtime: "cli", costTier: "premium", latencyTier: "interactive", privacyTier: "workspace")
            ], readiness: AgentReadinessState(status: "unknown")),
            AgentRole(role: "code_worker", kind: "minimax", title: "MiniMax Worker", subtitle: "Refactors, tests, compiler bugs", arousalRole: "phasic_focus", providerSlots: [AgentProviderSlot(id: "minimax-m2", title: "MiniMax-M2", modelId: "MiniMax-M2", runtime: "openai_compatible", costTier: "efficient", latencyTier: "interactive", privacyTier: "external_api")], readiness: AgentReadinessState(status: "needs_setup", reason: "provider slot not checked yet")),
            AgentRole(role: "long_thought_architect", kind: "kimi", title: "Kimi Architect", subtitle: "Sounio semantics and Claim<T>", arousalRole: "tonic_explore", providerSlots: [AgentProviderSlot(id: "kimi-k2-thinking", title: "Kimi K2 Thinking", modelId: "moonshotai/Kimi-K2-Thinking", command: "kimi", runtime: "cli_or_openai_compatible", costTier: "premium", latencyTier: "long_horizon", privacyTier: "external_api")], readiness: AgentReadinessState(status: "unknown")),
            AgentRole(role: "maintenance_agent", kind: "qwen-coder", title: "Qwen Maintainer", subtitle: "Cheap lint and repair loops", arousalRole: "phasic_focus", providerSlots: [AgentProviderSlot(id: "qwen3-coder-next", title: "Qwen3-Coder-Next", modelId: "Qwen/Qwen3-Coder-Next", runtime: "openai_compatible_or_local", costTier: "low", latencyTier: "fast", privacyTier: "provider_or_local")], readiness: AgentReadinessState(status: "needs_setup")),
            AgentRole(role: "platform_operator", kind: "glm-air", title: "GLM Operator", subtitle: "K8s, runbooks, incidents", arousalRole: "recovering", providerSlots: [AgentProviderSlot(id: "glm-4.5-air", title: "GLM-4.5-Air", modelId: "zai-org/GLM-4.5-Air", runtime: "openai_compatible_or_local", costTier: "medium", latencyTier: "interactive", privacyTier: "provider_or_local")], readiness: AgentReadinessState(status: "needs_setup")),
            AgentRole(role: "shell", kind: "human", title: "Shell", subtitle: "Human terminal", arousalRole: "phasic_focus", providerSlots: [AgentProviderSlot(id: "shell-pty", title: "Workspace Shell", modelId: "human", runtime: "pty", costTier: "none", latencyTier: "instant", privacyTier: "workspace")], readiness: AgentReadinessState(status: "ready"))
        ]
    }

    private func agentLaneState(_ role: AgentRole) -> AgentLaneState {
        let pane = paneForLane(role.role)
        let liveBlock = pane.flatMap { pane in
            terminal.liveBlocks.first(where: { $0.paneId == pane.id })
        }
        let persistedBlock = pane.flatMap { pane in
            terminalBlocks.first(where: { $0.paneId == pane.id })
        }
        let agentState = pane.flatMap { terminal.agentStates[$0.id] ?? $0.agent }
        let memoryStatus = liveBlock?.memoryStatus
            ?? persistedBlock?.memoryStatus
            ?? terminal.latestMemoryStatus?.status
        let pendingApproval = terminal.approvalRequests.values.contains { request in
            request.status == "pending" && (pane == nil || request.id.contains(pane?.id ?? ""))
        }
        let status = laneStatus(
            lane: role.role,
            pane: pane,
            role: role,
            agentState: agentState,
            liveBlock: liveBlock,
            memoryStatus: memoryStatus
        )
        let provider = role.providerSlots.first(where: { $0.enabled }) ?? role.providerSlots.first
        return AgentLaneState(
            id: role.role,
            title: role.title,
            kind: role.kind,
            paneId: pane?.id,
            status: status.label,
            detail: status.detail,
            lastBlockTitle: liveBlock?.title ?? persistedBlock?.title,
            lastBlockStatus: liveBlock?.status ?? persistedBlock?.status,
            memoryStatus: memoryStatus,
            pendingApproval: pendingApproval,
            reconnectState: pane?.reconnectState,
            isActive: pane?.id == activePane?.id,
            role: role.role,
            subtitle: role.subtitle,
            providerLabel: provider.map { "\($0.title) · \(humanRuntimeLabel($0.runtime))" },
            arousalMode: role.arousalRole,
            isScout: role.visible == false,
            readinessReason: role.readiness?.reason
        )
    }

    private func laneStatus(
        lane: String,
        pane: TerminalPane?,
        role: AgentRole?,
        agentState: AgentRunState?,
        liveBlock: TerminalBlockLiveState?,
        memoryStatus: String?
    ) -> (label: String, detail: String) {
        guard let pane else {
            if let readiness = role?.readiness, readiness.status == "needs_setup" {
                return ("needs_setup", readiness.reason ?? "Provider slot or CLI is not configured yet.")
            }
            return ("not_started", "Create a \(role?.title ?? laneTitle(lane)) lane in the workspace.")
        }
        if let agentState, !agentState.state.isEmpty {
            return (agentState.state, nonBlank(agentState.summary) ?? pane.title)
        }
        if let liveBlock {
            return (liveBlock.status, nonBlank(liveBlock.command) ?? liveBlock.title)
        }
        if let memoryStatus, memoryStatus == "blocked" {
            return ("blocked", "Latest block stayed local after secret/restricted scan.")
        }
        if terminal.connectionState.isConnected, pane.id == activePane?.id {
            return ("live", "Attached to \(pane.title).")
        }
        return (pane.status.isEmpty ? "idle" : pane.status, pane.reconnectState ?? "ready to reconnect")
    }

    private func nonBlank(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty else { return nil }
        return trimmed
    }

    /// Human-readable label for a provider runtime token. Keeps the raw runtime
    /// in logic; only the displayed half of "Title · runtime" is translated.
    private func humanRuntimeLabel(_ runtime: String) -> String {
        switch runtime {
        case "cli": return "CLI"
        case "openai_compatible": return "API"
        case "openai_compatible_or_local": return "API or local"
        case "cli_or_openai_compatible": return "CLI or API"
        case "pty": return "terminal"
        default: return runtime
        }
    }

    private var memoryStatusIcon: String {
        let value = workMemoryStatus.lowercased()
        if value.contains("blocked") || value.contains("restricted") { return "lock.shield" }
        if value.contains("failed") { return "exclamationmark.triangle" }
        if value.contains("queued") { return "clock" }
        if value.contains("imported") || value.contains("remembered") { return "checkmark.seal" }
        return "point.3.connected.trianglepath.dotted"
    }

    private var memoryStatusTint: Color {
        let value = workMemoryStatus.lowercased()
        if value.contains("blocked") || value.contains("restricted") { return BeagleTheme.postureWarm }
        if value.contains("failed") { return BeagleTheme.stateError }
        if value.contains("imported") || value.contains("remembered") { return BeagleTheme.truthObserved }
        return BeagleTheme.textTertiary
    }

    private var latestWorkMemoryLine: String {
        if let latest = exocortex.home.value?.trustContext?.latestAgentWrite?.trimmingCharacters(in: .whitespacesAndNewlines),
           !latest.isEmpty {
            return latest
        }
        if let latest = exocortex.home.value?.agentContext?.lastAgentWrite?.trimmingCharacters(in: .whitespacesAndNewlines),
           !latest.isEmpty {
            return latest
        }
        if let atom = (exocortex.recentGraph?.value?.atoms ?? []).first(where: isWorkMemoryAtom) {
            let branch = atom.tags.first(where: { $0.hasPrefix("branch:") })?.replacingOccurrences(of: "branch:", with: "")
            let branchSuffix = branch.map { " · \($0)" } ?? ""
            return "\(atom.atomType)\(branchSuffix) · \(atom.text)"
        }
        return "No Codex or Claude Code work-memory atom observed yet."
    }

    private func isWorkMemoryAtom(_ atom: MemoryAtom) -> Bool {
        let haystack = (atom.tags + [atom.atomType, atom.text]).joined(separator: " ").lowercased()
        return haystack.contains("work-memory")
            || haystack.contains("codex")
            || haystack.contains("claude-code")
            || haystack.contains("agent:")
    }
}

private struct ScoutLaneDrawer: View {
    @Binding var isExpanded: Bool
    let lanes: [AgentLaneState]
    let onOpenLane: (String) -> Void
    let onStartLane: (String) -> Void
    var onSetUpLane: (String) -> Void = { _ in }

    var body: some View {
        VStack(alignment: .leading, spacing: BeagleSpacing.xs) {
            Button {
                withAnimation(.easeInOut(duration: 0.18)) {
                    isExpanded.toggle()
                }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: isExpanded ? "tray.full" : "tray")
                        .font(.system(size: 12, weight: .semibold))
                    Text("Drawer lanes")
                        .font(BeagleFont.caption.font)
                        .fontWeight(.semibold)
                    Text("\(lanes.count)")
                        .font(BeagleFont.caption2.font)
                        .foregroundStyle(BeagleTheme.textTertiary)
                    Spacer(minLength: BeagleSpacing.xs)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 10, weight: .semibold))
                        .rotationEffect(.degrees(isExpanded ? 180 : 0))
                }
                .foregroundStyle(BeagleTheme.textSecondary)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(BeagleTheme.surface1.opacity(0.56), in: RoundedRectangle(cornerRadius: 8))
            }
            .buttonStyle(.plain)

            if isExpanded {
                VStack(spacing: BeagleSpacing.xs) {
                    ForEach(lanes) { lane in
                        AgentLaneCard(
                            lane: lane,
                            onOpen: { onOpenLane(lane.id) },
                            onStart: { onStartLane(lane.id) },
                            onSetUp: { onSetUpLane(lane.id) }
                        )
                    }
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }
}

private struct WorkbenchHeader: View {
    let slug: String
    let session: WorkspaceSession?
    let pane: TerminalPane?
    let connectionState: WebSocketState
    let status: String
    let error: String?
    let blockCount: Int

    var body: some View {
        HStack(alignment: .center, spacing: BeagleSpacing.sm) {
            HStack(alignment: .center, spacing: 11) {
                Image(systemName: "rectangle.3.group.bubble.left")
                    .font(.system(size: 19, weight: .semibold))
                    .foregroundStyle(BeagleTheme.truthObserved)
                    .frame(width: 36, height: 36)
                    .background(BeagleTheme.truthObserved.opacity(0.14), in: RoundedRectangle(cornerRadius: 8))
                VStack(alignment: .leading, spacing: 3) {
                    Text("Sounio Agent Deck")
                        .font(BeagleFont.headline.font)
                        .foregroundStyle(BeagleTheme.textPrimary)
                    Text(subtitle)
                        .font(BeagleFont.caption.font)
                        .foregroundStyle(BeagleTheme.textSecondary)
                        .lineLimit(2)
                }
            }
            Spacer(minLength: BeagleSpacing.sm)
            HStack(spacing: 6) {
                headerPill(workspaceStateLabel, icon: connectionIcon, tint: connectionTint)
                if blockCount > 0 {
                    headerPill("\(blockCount) artifacts", icon: "text.badge.checkmark", tint: BeagleTheme.truthRemembered)
                }
            }
        }
        .padding(.horizontal, BeagleSpacing.lg)
        .padding(.vertical, 12)
        .background(.ultraThinMaterial)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(BeagleTheme.hairline)
                .frame(height: 1)
        }
    }

    private var subtitle: String {
        if let error, !error.isEmpty {
            return "\(slug) needs attention · \(error.replacingOccurrences(of: "fallback", with: "recovery"))"
        }
        if case .connected = connectionState {
            let lane = pane?.title ?? "visual lanes"
            return "\(slug) is live · \(lane) ready · memory is cluster-canonical"
        }
        return "\(slug) · choose a lane to begin a focused workday"
    }

    /// Single honest workspace-state label driven by the live connection.
    /// When connected and authority is known, append a small "· workspace"/
    /// "· local" hint. The vague "warming" authority pill is never shown on its
    /// own (it disappears entirely when disconnected).
    private var workspaceStateLabel: String {
        switch connectionState {
        case .disconnected:
            return "Workspace offline"
        case .connecting, .reconnecting:
            return "Waking workspace…"
        case .failed:
            return "Workspace needs attention"
        case .connected:
            if let hint = knownAuthorityHint {
                return "Workspace live · \(hint)"
            }
            return "Workspace live"
        }
    }

    /// Returns "workspace" or "local" only when authority is actually known;
    /// nil while authority is still warming/unknown so we never surface it.
    private var knownAuthorityHint: String? {
        switch session?.authorityStatus?.authority {
        case "workspace-agent": return "workspace"
        case "cockpit-local": return "local"
        default: return nil
        }
    }

    private var connectionIcon: String {
        switch connectionState {
        case .connected: return "dot.radiowaves.left.and.right"
        case .connecting, .reconnecting: return "arrow.triangle.2.circlepath"
        case .failed: return "exclamationmark.triangle"
        case .disconnected: return "moon"
        }
    }

    private var connectionTint: Color {
        switch connectionState {
        case .connected: return BeagleTheme.truthObserved
        case .connecting, .reconnecting: return BeagleTheme.truthRemembered
        case .failed: return BeagleTheme.stateError
        case .disconnected: return BeagleTheme.textTertiary
        }
    }

    private func headerPill(_ label: String, icon: String, tint: Color) -> some View {
        HStack(spacing: 5) {
            Image(systemName: icon)
                .font(.system(size: 10, weight: .semibold))
            Text(label)
                .font(BeagleFont.caption2.font)
                .fontWeight(.semibold)
                .lineLimit(1)
        }
        .foregroundStyle(tint)
        .padding(.horizontal, 9)
        .padding(.vertical, 5)
        .background(tint.opacity(0.12), in: Capsule())
    }
}

private struct AgentConsoleView: View {
    let snapshot: AgentConsoleSnapshot
    let onOpenLane: (String) -> Void
    let onStartLane: (String) -> Void
    var onSetUpLane: (String) -> Void = { _ in }
    let onShowTerminal: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: BeagleSpacing.sm) {
            HStack(alignment: .firstTextBaseline, spacing: BeagleSpacing.sm) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Agent Console")
                        .font(BeagleFont.headline.font)
                        .foregroundStyle(BeagleTheme.textPrimary)
                    Text(subtitle)
                        .font(BeagleFont.caption.font)
                        .foregroundStyle(BeagleTheme.textSecondary)
                        .lineLimit(2)
                }
                Spacer(minLength: BeagleSpacing.sm)
                Button(action: onShowTerminal) {
                    Image(systemName: "terminal")
                        .font(.system(size: 14, weight: .semibold))
                        .frame(width: 34, height: 34)
                        .background(BeagleTheme.surface1.opacity(0.78), in: Circle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(BeagleTheme.truthObserved)
            }

            VStack(spacing: BeagleSpacing.sm) {
                ForEach(snapshot.lanes) { lane in
                    AgentLaneCard(
                        lane: lane,
                        onOpen: { onOpenLane(lane.id) },
                        onStart: { onStartLane(lane.id) },
                        onSetUp: { onSetUpLane(lane.id) }
                    )
                }
            }
        }
    }

    private var subtitle: String {
        let authority = snapshot.authority ?? "workspace"
        if snapshot.sessionId == nil {
            return "\(snapshot.projectSlug) · choose a lane to wake the workspace"
        }
        return "\(snapshot.projectSlug) · \(authority) · visual lanes ready"
    }
}

/// Maps a raw lane status token to human-readable English at render time.
/// The raw token is preserved everywhere it is used in logic; only the displayed
/// label is translated here.
private func humanLaneStatus(_ status: String) -> String {
    switch status {
    case "needs_setup": return "Needs setup"
    case "not_started": return "Not running"
    case "unknown": return "Not checked"
    case "ready": return "Ready"
    case "live", "running": return "Running"
    case "idle": return "Idle"
    case "blocked": return "Held (privacy)"
    case "failed": return "Failed"
    case "pending": return "Pending"
    default: return status
    }
}

/// Cleans machine reason/detail strings into human sentences. Pattern-based;
/// already-human sentences are returned unchanged.
private func humanLaneDetail(_ detail: String) -> String {
    let trimmed = detail.trimmingCharacters(in: .whitespacesAndNewlines)
    if trimmed.hasSuffix("is not on PATH") {
        let cli = trimmed.split(separator: " ").first.map(String.init) ?? trimmed
        return "\(cli) not installed on the workspace"
    }
    if trimmed.hasSuffix("PROVIDER_URL is not configured")
        || (trimmed.contains("PROVIDER_URL") && trimmed.hasSuffix("is not configured")) {
        return "Needs an API endpoint"
    }
    if trimmed == "provider slot not checked yet" {
        return "Not checked yet"
    }
    return detail
}

/// State-driven label for the lane action button.
private func laneActionLabel(status: String, hasPane: Bool) -> String {
    switch status {
    case "needs_setup": return "Set up"
    case "live", "running": return "Open"
    default: return hasPane ? "Open" : "Start"
    }
}

/// State-driven SF Symbol for the lane action button.
private func laneActionIcon(status: String, hasPane: Bool) -> String {
    switch status {
    case "needs_setup": return "slider.horizontal.3"
    case "live", "running": return "arrow.up.forward.app"
    default: return hasPane ? "play.circle" : "plus.circle"
    }
}

private struct AgentLaneCard: View {
    let lane: AgentLaneState
    let onOpen: () -> Void
    let onStart: () -> Void
    /// When lane.status == "needs_setup", presents the in-app provider Set-up
    /// form (API key + base URL + model) wired to the server-side per-slug
    /// provider-config path via ProviderSetupView. Falls back to onStart when
    /// no setup handler is supplied.
    var onSetUp: (() -> Void)? = nil

    var body: some View {
        Button(action: onOpen) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Image(systemName: icon)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(tint)
                        .frame(width: 22)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(lane.title)
                            .font(BeagleFont.body.font)
                            .fontWeight(.semibold)
                            .foregroundStyle(BeagleTheme.textPrimary)
                            .lineLimit(1)
                        if let provider = lane.providerLabel {
                            Text(provider)
                                .font(BeagleFont.caption2.font)
                                .foregroundStyle(BeagleTheme.textTertiary)
                                .lineLimit(1)
                        }
                        Text(humanLaneDetail(lane.detail))
                            .font(BeagleFont.caption2.font)
                            .foregroundStyle(BeagleTheme.textSecondary)
                            .lineLimit(2)
                    }
                    Spacer(minLength: 8)
                    VStack(alignment: .trailing, spacing: 4) {
                        Text(humanLaneStatus(lane.status))
                            .font(BeagleFont.caption2.font)
                            .fontWeight(.semibold)
                            .foregroundStyle(tint)
                            .lineLimit(1)
                        if let memory = lane.memoryStatus {
                            Text(memory)
                                .font(BeagleFont.caption2.font)
                                .foregroundStyle(memoryTint(memory))
                                .lineLimit(1)
                        }
                    }
                }

                HStack(spacing: 6) {
                    if let block = lane.lastBlockTitle {
                        Label(block, systemImage: "text.badge.checkmark")
                            .lineLimit(1)
                    } else {
                        Label("No block yet", systemImage: "rectangle.dashed")
                            .lineLimit(1)
                    }
                    Spacer(minLength: 4)
                    if lane.pendingApproval {
                        Label("approval", systemImage: "checkmark.circle")
                    }
                    Button(action: actionHandler) {
                        Label(
                            laneActionLabel(status: lane.status, hasPane: lane.paneId != nil),
                            systemImage: laneActionIcon(status: lane.status, hasPane: lane.paneId != nil)
                        )
                        .labelStyle(.iconOnly)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(lane.status == "needs_setup" ? BeagleTheme.postureWarm : BeagleTheme.truthObserved)
                }
                .font(BeagleFont.caption2.font)
                .foregroundStyle(BeagleTheme.textTertiary)
            }
            .padding(12)
            .background(background, in: RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(lane.isActive ? BeagleTheme.truthObserved.opacity(0.55) : BeagleTheme.hairline, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    /// needs_setup should eventually present the provider Set-up form via
    /// onSetUp; until that is wired we fall back to onStart (openLane).
    private var actionHandler: () -> Void {
        if lane.status == "needs_setup", let onSetUp { return onSetUp }
        return onStart
    }

    private var icon: String {
        switch lane.kind {
        case "codex": return "curlybraces.square"
        case "claude-code": return "bolt.square"
        case "minimax": return "hammer"
        case "kimi": return "brain.head.profile"
        case "qwen-coder": return "wrench.adjustable"
        case "glm-air": return "server.rack"
        case "palmyra-x5": return "doc.text.magnifyingglass"
        case "jamba": return "waveform.path.ecg"
        case "pegasus": return "video.badge.waveform"
        case "lfm2": return "sensor"
        case "cursor": return "cursorarrow.motionlines"
        default: return "terminal"
        }
    }

    private var tint: Color {
        if lane.memoryStatus == "blocked" || lane.status == "needs_setup" { return BeagleTheme.postureWarm }
        if lane.status == "failed" { return BeagleTheme.stateError }
        if lane.isActive || lane.status == "live" || lane.status == "running" { return BeagleTheme.truthObserved }
        return BeagleTheme.truthRemembered
    }

    private var background: Color {
        lane.isActive ? BeagleTheme.truthObserved.opacity(0.10) : BeagleTheme.surface1.opacity(0.62)
    }

    private func memoryTint(_ memory: String) -> Color {
        switch memory {
        case "remembered": return BeagleTheme.truthObserved
        case "blocked": return BeagleTheme.postureWarm
        case "failed": return BeagleTheme.stateError
        default: return BeagleTheme.textTertiary
        }
    }
}

private struct AgentConsoleDock: View {
    let state: WorkbenchActionDockState
    let onInput: () -> Void
    let onInterrupt: () -> Void
    let onApprove: () -> Void
    let onRemember: () -> Void
    let onFocus: () -> Void
    let onScout: () -> Void
    let onCompare: () -> Void
    let onOpenTerminal: () -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 0) {
                dockButton("Input", icon: "keyboard", isEnabled: state.canSendInput, action: onInput)
                dockButton("Interrupt", icon: "pause.circle", isEnabled: state.canInterrupt, action: onInterrupt)
                dockButton("Approve", icon: "checkmark.circle", isEnabled: state.canApprove, action: onApprove)
                dockButton("Remember", icon: "externaldrive.connected.to.line.below", isEnabled: state.canRemember, action: onRemember)
                dockButton("Focus", icon: "scope", action: onFocus)
                dockButton("Scout", icon: "brain.head.profile", action: onScout)
                dockButton("Compare", icon: "arrow.triangle.branch", action: onCompare)
                dockButton("Terminal", icon: "terminal", action: onOpenTerminal)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, BeagleSpacing.xs)
        .background(.ultraThinMaterial)
    }

    private func dockButton(
        _ label: String,
        icon: String,
        isEnabled: Bool = true,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(spacing: 2) {
                Image(systemName: icon)
                    .font(.system(size: 13, weight: .semibold))
                Text(label)
                    .font(BeagleFont.caption2.font)
                    .lineLimit(1)
            }
            .frame(width: 82)
        }
        .buttonStyle(.plain)
        .foregroundStyle(isEnabled ? BeagleTheme.textSecondary : BeagleTheme.textTertiary.opacity(0.55))
        .disabled(!isEnabled)
    }
}

private struct VisualWorkbenchActionDock: View {
    let state: WorkbenchActionDockState
    let onInterrupt: () -> Void
    let onApprove: () -> Void
    let onRemember: () -> Void
    let onFocus: () -> Void
    let onScout: () -> Void
    let onCompare: () -> Void
    let onRuntime: () -> Void
    let onRefresh: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            visualDockButton("Focus", icon: "scope", tint: BeagleTheme.truthObserved, action: onFocus)
            visualDockButton("Scout", icon: "brain.head.profile", tint: BeagleTheme.truthRemembered, action: onScout)
            visualDockButton("Compare", icon: "arrow.triangle.branch", tint: BeagleTheme.textData, action: onCompare)
            Divider().overlay(BeagleTheme.hairline).frame(height: 24)
            visualDockButton("Remember", icon: "externaldrive.connected.to.line.below", tint: BeagleTheme.truthObserved, isEnabled: state.canRemember, action: onRemember)
            visualDockButton("Approve", icon: "checkmark.seal", tint: BeagleTheme.truthObserved, isEnabled: state.canApprove, action: onApprove)
            visualDockButton("Interrupt", icon: "pause.circle", tint: BeagleTheme.postureWarm, isEnabled: state.canInterrupt, action: onInterrupt)
            Spacer(minLength: BeagleSpacing.md)
            visualDockButton("Refresh", icon: "arrow.clockwise", tint: BeagleTheme.textSecondary, action: onRefresh)
            visualDockButton("Runtime Log", icon: "terminal", tint: BeagleTheme.textTertiary, action: onRuntime)
        }
        .padding(.horizontal, BeagleSpacing.lg)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial)
        .overlay(alignment: .top) {
            Rectangle().fill(BeagleTheme.hairline).frame(height: 1)
        }
    }

    private func visualDockButton(
        _ label: String,
        icon: String,
        tint: Color,
        isEnabled: Bool = true,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Label(label, systemImage: icon)
                .font(BeagleFont.caption.font)
                .fontWeight(.semibold)
                .lineLimit(1)
                .padding(.horizontal, 11)
                .padding(.vertical, 8)
                .background(tint.opacity(isEnabled ? 0.13 : 0.05), in: Capsule())
        }
        .buttonStyle(.plain)
        .foregroundStyle(isEnabled ? tint : BeagleTheme.textTertiary.opacity(0.55))
        .disabled(!isEnabled)
    }
}

private struct VisualWorkbenchStage: View {
    let state: VisualWorkCanvasState
    let onOpenLane: (VisualAgentLaneSnapshot) -> Void
    let onStartLane: (VisualAgentLaneSnapshot) -> Void
    var onSetUpLane: (VisualAgentLaneSnapshot) -> Void = { _ in }
    let onRuntimeLane: (VisualAgentLaneSnapshot) -> Void
    let onSelectArtifact: (VisualWorkArtifact) -> Void
    let onRememberArtifact: (VisualWorkArtifact) -> Void
    let onBakeOffArtifact: (VisualWorkArtifact) -> Void
    let onRuntime: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            VisualAgentLaneBoard(
                lanes: state.lanes,
                onOpenLane: onOpenLane,
                onStartLane: onStartLane,
                onSetUpLane: onSetUpLane,
                onRuntime: onRuntimeLane
            )
            .frame(maxHeight: 252)

            Divider().overlay(BeagleTheme.hairline)

            HStack(spacing: 0) {
                VisualWorkCanvas(
                    state: state,
                    onSelectArtifact: onSelectArtifact,
                    onRuntime: onRuntime,
                    onRemember: {
                        if let artifact = state.selectedArtifact {
                            onRememberArtifact(artifact)
                        }
                    },
                    onBakeOff: {
                        if let artifact = state.selectedArtifact {
                            onBakeOffArtifact(artifact)
                        }
                    }
                )

                Divider().overlay(BeagleTheme.hairline)

                WorkMemoryInspector(
                    state: state,
                    selectedArtifactId: state.selectedArtifact?.id,
                    onSelect: onSelectArtifact,
                    onRemember: onRememberArtifact,
                    onBakeOff: onBakeOffArtifact,
                    onRuntime: onRuntime
                )
                .frame(width: 360)
            }
        }
    }
}

private struct VisualAgentLaneBoard: View {
    let lanes: [VisualAgentLaneSnapshot]
    let onOpenLane: (VisualAgentLaneSnapshot) -> Void
    let onStartLane: (VisualAgentLaneSnapshot) -> Void
    var onSetUpLane: (VisualAgentLaneSnapshot) -> Void = { _ in }
    let onRuntime: (VisualAgentLaneSnapshot) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: BeagleSpacing.md) {
            HStack(alignment: .firstTextBaseline) {
                Text("Agent Deck")
                    .font(BeagleFont.headline.font)
                    .foregroundStyle(BeagleTheme.textPrimary)
                Text("roles first, providers second")
                    .font(BeagleFont.caption.font)
                    .foregroundStyle(BeagleTheme.textTertiary)
                Spacer()
                Label("runtime hidden until requested", systemImage: "terminal.fill")
                    .font(BeagleFont.caption2.font)
                    .foregroundStyle(BeagleTheme.textTertiary)
            }

            ScrollView(.horizontal, showsIndicators: false) {
                LazyHGrid(
                    rows: [
                        GridItem(.fixed(92), spacing: 10),
                        GridItem(.fixed(92), spacing: 10)
                    ],
                    spacing: 10
                ) {
                    ForEach(lanes) { lane in
                        VisualAgentLaneCard(
                            lane: lane,
                            onOpen: { onOpenLane(lane) },
                            onStart: { onStartLane(lane) },
                            onRuntime: { onRuntime(lane) },
                            onSetUp: { onSetUpLane(lane) }
                        )
                        .frame(width: 260)
                    }
                }
                .padding(.trailing, BeagleSpacing.lg)
            }
        }
        .padding(BeagleSpacing.lg)
        .background(
            LinearGradient(
                colors: [BeagleTheme.surface0.opacity(0.90), BeagleTheme.surface1.opacity(0.66)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
    }
}

private struct VisualAgentLaneCard: View {
    let lane: VisualAgentLaneSnapshot
    let onOpen: () -> Void
    let onStart: () -> Void
    let onRuntime: () -> Void
    /// When the lane needs setup, presents the in-app provider Set-up form
    /// (API key + base URL + model) wired to the server-side per-slug
    /// provider-config path via ProviderSetupView. Falls back to onStart when
    /// no setup handler is supplied.
    var onSetUp: (() -> Void)? = nil

    /// True when the lane is unconfigured and should read as a Set-up affordance.
    private var needsSetup: Bool {
        lane.readiness == "needs_setup" || lane.status == "needs_setup"
    }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Button(action: onOpen) {
                HStack(alignment: .top, spacing: 9) {
                    Image(systemName: icon)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(tint)
                        .frame(width: 22)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(lane.title)
                            .font(BeagleFont.body.font)
                            .fontWeight(.semibold)
                            .foregroundStyle(BeagleTheme.textPrimary)
                            .lineLimit(1)
                        if let provider = lane.providerLabel {
                            Text(provider)
                                .font(BeagleFont.caption2.font)
                                .foregroundStyle(BeagleTheme.textTertiary)
                                .lineLimit(1)
                        }
                        Text(humanLaneDetail(lane.taskSummary))
                            .font(BeagleFont.caption2.font)
                            .foregroundStyle(BeagleTheme.textSecondary)
                            .lineLimit(3)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 4)
                    VStack(alignment: .trailing, spacing: 4) {
                        Text(humanLaneStatus(lane.status))
                            .font(BeagleFont.caption2.font)
                            .fontWeight(.semibold)
                            .foregroundStyle(tint)
                            .lineLimit(1)
                        if let memory = lane.memoryStatus {
                            Text(memory)
                                .font(BeagleFont.caption2.font)
                                .foregroundStyle(memoryTint(memory))
                                .lineLimit(1)
                        }
                    }
                }
            }
            .buttonStyle(.plain)
            .frame(maxWidth: .infinity, alignment: .leading)

            VStack(spacing: 7) {
                Button(action: actionHandler) {
                    Image(systemName: actionIcon)
                        .font(.system(size: 17, weight: .semibold))
                }
                .buttonStyle(.plain)
                .foregroundStyle(needsSetup ? BeagleTheme.postureWarm : BeagleTheme.truthObserved)
                .accessibilityLabel(Text(laneActionLabel(status: needsSetup ? "needs_setup" : lane.status, hasPane: lane.runtimeAvailable)))
                Button(action: onRuntime) {
                    Image(systemName: "terminal")
                        .font(.system(size: 13, weight: .semibold))
                }
                .buttonStyle(.plain)
                .foregroundStyle(BeagleTheme.textTertiary)
            }
        }
        .padding(11)
        .background(background, in: RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(lane.isActive ? BeagleTheme.truthObserved.opacity(0.55) : BeagleTheme.hairline, lineWidth: 1)
        )
    }

    /// needs_setup should eventually present the provider Set-up form via
    /// onSetUp; until that is wired we fall back to onStart (openLane).
    private var actionHandler: () -> Void {
        if needsSetup, let onSetUp { return onSetUp }
        return onStart
    }

    private var actionIcon: String {
        if needsSetup { return "slider.horizontal.3" }
        if lane.status == "live" || lane.status == "running" { return "arrow.up.forward.app.fill" }
        return lane.runtimeAvailable ? "play.circle.fill" : "plus.circle.fill"
    }

    private var icon: String {
        switch lane.kind {
        case "codex": return "curlybraces.square"
        case "claude-code": return "bolt.square"
        case "minimax": return "hammer"
        case "kimi": return "brain.head.profile"
        case "qwen-coder": return "wrench.adjustable"
        case "glm-air": return "server.rack"
        case "human": return "terminal"
        default: return "sparkles.rectangle.stack"
        }
    }

    private var tint: Color {
        if lane.readiness == "needs_setup" { return BeagleTheme.postureWarm }
        if lane.status == "failed" { return BeagleTheme.stateError }
        if lane.isActive || lane.status == "live" || lane.status == "running" { return BeagleTheme.truthObserved }
        return BeagleTheme.truthRemembered
    }

    private var background: Color {
        lane.isActive ? BeagleTheme.truthObserved.opacity(0.11) : BeagleTheme.surface1.opacity(0.62)
    }

    private func lanePill(_ label: String, icon: String) -> some View {
        Label(label, systemImage: icon)
            .font(BeagleFont.caption2.font)
            .lineLimit(1)
            .foregroundStyle(label == "redacted" || label == "needs_setup" ? BeagleTheme.postureWarm : BeagleTheme.textTertiary)
            .padding(.horizontal, 7)
            .padding(.vertical, 4)
            .background(BeagleTheme.surface0.opacity(0.62), in: Capsule())
    }

    private func memoryTint(_ memory: String) -> Color {
        switch memory {
        case "remembered": return BeagleTheme.truthObserved
        case "blocked": return BeagleTheme.postureWarm
        case "failed": return BeagleTheme.stateError
        default: return BeagleTheme.textTertiary
        }
    }
}

private struct VisualWorkCanvas: View {
    let state: VisualWorkCanvasState
    let onSelectArtifact: (VisualWorkArtifact) -> Void
    let onRuntime: () -> Void
    let onRemember: () -> Void
    let onBakeOff: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: BeagleSpacing.md) {
                hero
                if state.recentArtifacts.isEmpty {
                    EmptyWorkdayPanel(onStart: onRuntime)
                } else {
                    WorkArtifactStrip(
                        artifacts: state.recentArtifacts,
                        selectedArtifactId: state.selectedArtifact?.id,
                        onSelect: onSelectArtifact
                    )
                }
                selectedArtifactPanel
            }
            .padding(BeagleSpacing.lg)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            LinearGradient(
                colors: [BeagleTheme.surface0.opacity(0.86), BeagleTheme.surface1.opacity(0.56)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
    }

    private var hero: some View {
        VStack(alignment: .leading, spacing: BeagleSpacing.sm) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Active Work")
                        .font(BeagleFont.caption.font)
                        .fontWeight(.semibold)
                        .foregroundStyle(BeagleTheme.textTertiary)
                        .textCase(.uppercase)
                    Text(displayHeadline)
                        .font(BeagleFont.title2.font)
                        .foregroundStyle(BeagleTheme.textPrimary)
                        .lineLimit(3)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
                Text(state.restrictedLeakCheck)
                    .font(BeagleFont.caption2.font)
                    .foregroundStyle(state.restrictedLeakCheck.contains("redacted") ? BeagleTheme.postureWarm : BeagleTheme.truthObserved)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 5)
                    .background(BeagleTheme.surface1.opacity(0.7), in: Capsule())
            }
            Text(displayPrimaryAction)
                .font(BeagleFont.body.font)
                .foregroundStyle(BeagleTheme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 8) {
                Button(action: onRemember) {
                    Label("Remember", systemImage: "externaldrive.connected.to.line.below")
                }
                .disabled(state.selectedArtifact == nil)
                Button(action: onBakeOff) {
                    Label("Bake-off", systemImage: "rectangle.split.2x1")
                }
                .disabled(state.selectedArtifact == nil)
                Button(action: onRuntime) {
                    Label("Runtime Log", systemImage: "terminal")
                }
            }
            .font(BeagleFont.caption.font)
            .buttonStyle(.bordered)
        }
        .padding(BeagleSpacing.lg)
        .background(BeagleTheme.surface1.opacity(0.62), in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(BeagleTheme.hairline, lineWidth: 1))
    }

    private var displayHeadline: String {
        state.selectedArtifact == nil ? "Start a Sounio workday without staring at a terminal" : state.headline
    }

    private var displayPrimaryAction: String {
        state.selectedArtifact == nil
            ? "Choose Claude/Codex, MiniMax, Kimi, Qwen, GLM, or Shell. As work happens, Beagle turns meaningful blocks into visual artifacts you can remember."
            : state.primaryAction
    }

    @ViewBuilder
    private var selectedArtifactPanel: some View {
        if let artifact = state.selectedArtifact {
            VStack(alignment: .leading, spacing: BeagleSpacing.sm) {
                Text("Selected artifact")
                    .font(BeagleFont.caption.font)
                    .fontWeight(.semibold)
                    .foregroundStyle(BeagleTheme.textTertiary)
                    .textCase(.uppercase)
                HStack(alignment: .top, spacing: BeagleSpacing.sm) {
                    Image(systemName: artifactIcon(artifact.kind))
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(artifact.restrictedRedacted ? BeagleTheme.postureWarm : BeagleTheme.truthObserved)
                        .frame(width: 28)
                    VStack(alignment: .leading, spacing: 7) {
                        Text(artifact.title)
                            .font(BeagleFont.headline.font)
                            .foregroundStyle(BeagleTheme.textPrimary)
                        Text(artifact.summary)
                            .font(BeagleFont.body.font)
                            .foregroundStyle(BeagleTheme.textSecondary)
                            .textSelection(.enabled)
                            .fixedSize(horizontal: false, vertical: true)
                        if !artifact.touchedFiles.isEmpty {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Touched files")
                                    .font(BeagleFont.caption2.font)
                                    .fontWeight(.semibold)
                                    .foregroundStyle(BeagleTheme.textTertiary)
                                ForEach(artifact.touchedFiles, id: \.self) { file in
                                    Label(file, systemImage: "doc.text")
                                        .font(BeagleFont.caption2.font)
                                        .foregroundStyle(BeagleTheme.textSecondary)
                                        .lineLimit(1)
                                }
                            }
                        }
                        FlowPillRow(labels: artifact.evidenceBadges)
                    }
                }
            }
            .padding(BeagleSpacing.lg)
            .background(BeagleTheme.surface1.opacity(0.50), in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(BeagleTheme.hairline, lineWidth: 1))
        } else {
            EmptyProofPanel()
        }
    }

    private func artifactPill(_ label: String) -> some View {
        Text(label)
            .font(BeagleFont.caption2.font)
            .foregroundStyle(BeagleTheme.textTertiary)
            .lineLimit(1)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(BeagleTheme.surface0.opacity(0.65), in: Capsule())
    }
}

private struct EmptyWorkdayPanel: View {
    let onStart: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: BeagleSpacing.md) {
            Image(systemName: "play.rectangle.on.rectangle")
                .font(.system(size: 24, weight: .semibold))
                .foregroundStyle(BeagleTheme.truthRemembered)
                .frame(width: 44, height: 44)
                .background(BeagleTheme.truthRemembered.opacity(0.13), in: RoundedRectangle(cornerRadius: 8))
            VStack(alignment: .leading, spacing: 8) {
                Text("No work artifacts yet")
                    .font(BeagleFont.headline.font)
                    .foregroundStyle(BeagleTheme.textPrimary)
                Text("Start or resume a lane. The first command, agent step, test, diff, approval, or memory import will appear here as an object, not as terminal noise.")
                    .font(BeagleFont.body.font)
                    .foregroundStyle(BeagleTheme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                Button(action: onStart) {
                    Label("Open Runtime Only If Needed", systemImage: "terminal")
                }
                .font(BeagleFont.caption.font)
                .buttonStyle(.bordered)
            }
        }
        .padding(BeagleSpacing.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(BeagleTheme.surface1.opacity(0.50), in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(BeagleTheme.hairline, lineWidth: 1))
    }
}

private struct EmptyProofPanel: View {
    var body: some View {
        HStack(alignment: .top, spacing: BeagleSpacing.md) {
            Image(systemName: "doc.badge.clock")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(BeagleTheme.textTertiary)
                .frame(width: 42, height: 42)
                .background(BeagleTheme.surface1.opacity(0.72), in: RoundedRectangle(cornerRadius: 8))
            VStack(alignment: .leading, spacing: 6) {
                Text("The bench is waiting for evidence")
                    .font(BeagleFont.headline.font)
                    .foregroundStyle(BeagleTheme.textPrimary)
                Text("When a lane produces a block, this area becomes the interpreted summary: what changed, whether it touched files, memory status, provenance, and what to do next.")
                    .font(BeagleFont.body.font)
                    .foregroundStyle(BeagleTheme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(BeagleSpacing.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(BeagleTheme.surface1.opacity(0.48), in: RoundedRectangle(cornerRadius: 8))
    }
}

private struct WorkArtifactStrip: View {
    let artifacts: [VisualWorkArtifact]
    let selectedArtifactId: String?
    let onSelect: (VisualWorkArtifact) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: BeagleSpacing.sm) {
            Text("Artifacts")
                .font(BeagleFont.caption.font)
                .fontWeight(.semibold)
                .foregroundStyle(BeagleTheme.textTertiary)
                .textCase(.uppercase)
            if artifacts.isEmpty {
                Text("No curated Workbench blocks observed yet.")
                    .font(BeagleFont.caption.font)
                    .foregroundStyle(BeagleTheme.textSecondary)
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(BeagleTheme.surface1.opacity(0.45), in: RoundedRectangle(cornerRadius: 8))
            } else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 170), spacing: 10)], spacing: 10) {
                    ForEach(artifacts) { artifact in
                        Button {
                            onSelect(artifact)
                        } label: {
                            VStack(alignment: .leading, spacing: 6) {
                                HStack(spacing: 6) {
                                    Image(systemName: artifactIcon(artifact.kind))
                                        .foregroundStyle(artifact.restrictedRedacted ? BeagleTheme.postureWarm : BeagleTheme.truthRemembered)
                                    Text(artifact.kind.rawValue)
                                        .font(BeagleFont.caption2.font)
                                        .fontWeight(.semibold)
                                        .foregroundStyle(BeagleTheme.textTertiary)
                                    Spacer(minLength: 4)
                                    if artifact.id == selectedArtifactId {
                                        Image(systemName: "checkmark.circle.fill")
                                            .font(.system(size: 11, weight: .semibold))
                                            .foregroundStyle(BeagleTheme.truthObserved)
                                    }
                                }
                                Text(artifact.title)
                                    .font(BeagleFont.caption.font)
                                    .fontWeight(.semibold)
                                    .foregroundStyle(BeagleTheme.textPrimary)
                                    .lineLimit(2)
                                Text(artifact.summary)
                                    .font(BeagleFont.caption2.font)
                                    .foregroundStyle(BeagleTheme.textSecondary)
                                    .lineLimit(3)
                                if !artifact.touchedFiles.isEmpty {
                                    Label("\(artifact.touchedFiles.count) file\(artifact.touchedFiles.count == 1 ? "" : "s")", systemImage: "doc.on.doc")
                                        .font(BeagleFont.caption2.font)
                                        .foregroundStyle(BeagleTheme.textTertiary)
                                }
                            }
                            .padding(10)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(BeagleTheme.surface1.opacity(0.54), in: RoundedRectangle(cornerRadius: 8))
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(artifact.id == selectedArtifactId ? BeagleTheme.truthObserved.opacity(0.72) : BeagleTheme.hairline, lineWidth: 1)
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }
}

private struct FlowPillRow: View {
    let labels: [String]

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(labels, id: \.self) { label in
                    Text(label)
                        .font(BeagleFont.caption2.font)
                        .foregroundStyle(label.contains("restricted") ? BeagleTheme.postureWarm : BeagleTheme.textTertiary)
                        .lineLimit(1)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(BeagleTheme.surface0.opacity(0.65), in: Capsule())
                }
            }
        }
    }
}

private struct WorkMemoryInspector: View {
    let state: VisualWorkCanvasState
    let selectedArtifactId: String?
    let onSelect: (VisualWorkArtifact) -> Void
    let onRemember: (VisualWorkArtifact) -> Void
    let onBakeOff: (VisualWorkArtifact) -> Void
    let onRuntime: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: BeagleSpacing.md) {
            HStack(alignment: .center, spacing: 9) {
                Image(systemName: "externaldrive.connected.to.line.below")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(BeagleTheme.truthObserved)
                    .frame(width: 30, height: 30)
                    .background(BeagleTheme.truthObserved.opacity(0.13), in: RoundedRectangle(cornerRadius: 8))
                VStack(alignment: .leading, spacing: 2) {
                    Text("Memory & Proof")
                        .font(BeagleFont.headline.font)
                        .foregroundStyle(BeagleTheme.textPrimary)
                    Text("Cluster memory, provenance, review state.")
                        .font(BeagleFont.caption2.font)
                        .foregroundStyle(BeagleTheme.textSecondary)
                        .lineLimit(2)
                }
            }

            GlassPanel(elevation: .flush, truth: .observed) {
                VStack(alignment: .leading, spacing: 7) {
                    Text("What Beagle can safely remember")
                        .font(BeagleFont.caption2.font)
                        .fontWeight(.semibold)
                        .foregroundStyle(BeagleTheme.textTertiary)
                    Text(state.workMemoryLine)
                        .font(BeagleFont.caption.font)
                        .foregroundStyle(BeagleTheme.textSecondary)
                        .lineLimit(5)
                    Text(state.workMemoryStatus)
                        .font(BeagleFont.caption2.font)
                        .foregroundStyle(BeagleTheme.textTertiary)
                        .lineLimit(2)
                    Text(state.restrictedLeakCheck)
                        .font(BeagleFont.caption2.font)
                        .foregroundStyle(state.restrictedLeakCheck.contains("redacted") ? BeagleTheme.postureWarm : BeagleTheme.truthObserved)
                }
            }

            HStack {
                Text("Evidence Objects")
                    .font(BeagleFont.caption2.font)
                    .fontWeight(.semibold)
                    .foregroundStyle(BeagleTheme.textTertiary)
                Spacer()
                Button(action: onRuntime) {
                    Label("Runtime Log", systemImage: "terminal")
                        .labelStyle(.iconOnly)
                }
                .buttonStyle(.plain)
                .foregroundStyle(BeagleTheme.textTertiary)
            }

            ScrollView {
                LazyVStack(spacing: 8) {
                    if state.recentArtifacts.isEmpty {
                        InspectorEmptyState(hasVisualArtifacts: !state.recentArtifacts.isEmpty)
                    } else {
                        ForEach(state.recentArtifacts) { artifact in
                            VisualProofArtifactRow(
                                artifact: artifact,
                                isSelected: artifact.id == selectedArtifactId,
                                onSelect: { onSelect(artifact) },
                                onRemember: { onRemember(artifact) },
                                onBakeOff: { onBakeOff(artifact) }
                            )
                        }
                    }
                }
                .padding(.bottom, BeagleSpacing.md)
            }
        }
        .padding(BeagleSpacing.md)
        .background(BeagleTheme.surface0.opacity(0.70))
    }
}

private struct VisualProofArtifactRow: View {
    let artifact: VisualWorkArtifact
    let isSelected: Bool
    let onSelect: () -> Void
    let onRemember: () -> Void
    let onBakeOff: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            Button(action: onSelect) {
                HStack(alignment: .top, spacing: 9) {
                    Image(systemName: artifactIcon(artifact.kind))
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(tint)
                        .frame(width: 18)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(artifact.title)
                            .font(BeagleFont.caption.font)
                            .fontWeight(.semibold)
                            .foregroundStyle(BeagleTheme.textPrimary)
                            .lineLimit(2)
                        Text(artifact.summary)
                            .font(BeagleFont.caption2.font)
                            .foregroundStyle(BeagleTheme.textSecondary)
                            .lineLimit(3)
                        FlowPillRow(labels: artifact.evidenceBadges)
                    }
                    Spacer(minLength: 4)
                    if isSelected {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(BeagleTheme.truthObserved)
                    }
                }
            }
            .buttonStyle(.plain)

            HStack(spacing: 8) {
                Button(action: onRemember) {
                    Label("Remember", systemImage: "externaldrive.connected.to.line.below")
                }
                .disabled(artifact.sourceBlockId == nil)
                Button(action: onBakeOff) {
                    Label("Compare", systemImage: "rectangle.split.2x1")
                }
                .disabled(artifact.sourceBlockId == nil || artifact.restrictedRedacted)
            }
            .font(BeagleFont.caption2.font)
            .buttonStyle(.borderless)
            .foregroundStyle(BeagleTheme.truthObserved)
        }
        .padding(12)
        .background(BeagleTheme.surface1.opacity(isSelected ? 0.68 : 0.44), in: RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(isSelected ? BeagleTheme.truthObserved.opacity(0.70) : BeagleTheme.hairline, lineWidth: 1)
        )
    }

    private var tint: Color {
        if artifact.restrictedRedacted { return BeagleTheme.postureWarm }
        switch artifact.memoryStatus {
        case "remembered": return BeagleTheme.truthObserved
        case "blocked": return BeagleTheme.postureWarm
        case "failed": return BeagleTheme.stateError
        default: return BeagleTheme.truthRemembered
        }
    }
}

private struct InspectorEmptyState: View {
    let hasVisualArtifacts: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("No replay blocks yet", systemImage: "rectangle.dashed")
                .font(BeagleFont.caption.font)
                .fontWeight(.semibold)
                .foregroundStyle(BeagleTheme.textSecondary)
            Text(hasVisualArtifacts
                ? "Live artifacts are visible on the bench. Replay will fill this proof list after refresh."
                : "Start a lane. Proof blocks will appear here after Beagle observes work.")
                .font(BeagleFont.caption.font)
                .foregroundStyle(BeagleTheme.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(BeagleTheme.surface1.opacity(0.42), in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(BeagleTheme.hairline, lineWidth: 1))
    }
}

private func artifactIcon(_ kind: VisualWorkArtifactKind) -> String {
    switch kind {
    case .agent: return "sparkles.rectangle.stack"
    case .diff: return "plusminus"
    case .test: return "checklist.checked"
    case .deploy: return "shippingbox"
    case .memory: return "externaldrive.connected.to.line.below"
    case .runtime: return "terminal"
    case .approval: return "checkmark.seal"
    case .unknown: return "questionmark.square"
    }
}

private struct WorkspaceSessionRail: View {
    let session: WorkspaceSession?
    let activePaneId: String?
    let onSelectPane: (TerminalPane) -> Void
    let onNewShell: () -> Void
    let onNewCodex: () -> Void
    let onNewClaude: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: BeagleSpacing.sm) {
            Text("Workspace")
                .font(BeagleFont.caption.font)
                .fontWeight(.semibold)
                .foregroundStyle(BeagleTheme.textTertiary)
                .textCase(.uppercase)
            if let session {
                VStack(alignment: .leading, spacing: 4) {
                    Text(session.title)
                        .font(BeagleFont.body.font)
                        .foregroundStyle(BeagleTheme.textPrimary)
                        .lineLimit(1)
                    Text(session.id)
                        .font(BeagleFont.caption2.font)
                        .foregroundStyle(BeagleTheme.textTertiary)
                        .lineLimit(1)
                }
            }

            Divider().overlay(BeagleTheme.hairline)

            Text("Panes")
                .font(BeagleFont.caption2.font)
                .fontWeight(.semibold)
                .foregroundStyle(BeagleTheme.textTertiary)
            ForEach(session?.panes ?? []) { pane in
                Button {
                    onSelectPane(pane)
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: paneIcon(pane.kind))
                            .font(.system(size: 12, weight: .semibold))
                            .frame(width: 16)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(pane.title)
                                .font(BeagleFont.caption.font)
                                .foregroundStyle(BeagleTheme.textPrimary)
                                .lineLimit(1)
                            Text(pane.kind)
                                .font(BeagleFont.caption2.font)
                                .foregroundStyle(BeagleTheme.textTertiary)
                                .lineLimit(1)
                        }
                        Spacer()
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .background(
                        (pane.id == activePaneId ? BeagleTheme.truthObserved.opacity(0.12) : Color.clear),
                        in: RoundedRectangle(cornerRadius: 8)
                    )
                }
                .buttonStyle(.plain)
            }

            Spacer()

            VStack(spacing: 8) {
                Button(action: onNewShell) {
                    Label("New Shell", systemImage: "plus.square")
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                Button(action: onNewCodex) {
                    Label("Codex Pane", systemImage: "sparkles.rectangle.stack")
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                Button(action: onNewClaude) {
                    Label("Claude Pane", systemImage: "bolt.square")
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .font(BeagleFont.caption.font)
            .buttonStyle(.borderless)
            .foregroundStyle(BeagleTheme.textSecondary)
        }
        .padding(BeagleSpacing.md)
        .background(BeagleTheme.surface0.opacity(0.72))
    }

    private func paneIcon(_ kind: String) -> String {
        switch kind {
        case "codex": return "curlybraces.square"
        case "claude-code": return "bolt.square"
        case "cursor": return "cursorarrow.motionlines"
        case "opencode", "kimi": return "sparkles"
        default: return "terminal"
        }
    }
}

private struct WorkbenchInspector: View {
    let blocks: [TerminalBlock]
    let selectedBlockId: String?
    let workMemoryLine: String
    let workMemoryStatus: String
    let onSelect: (TerminalBlock) -> Void
    let onRemember: (TerminalBlock) -> Void
    let onBakeOff: (TerminalBlock) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: BeagleSpacing.md) {
            Text("Inspector")
                .font(BeagleFont.caption.font)
                .fontWeight(.semibold)
                .foregroundStyle(BeagleTheme.textTertiary)
                .textCase(.uppercase)

            GlassPanel(elevation: .flush, truth: .observed) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Latest work memory")
                        .font(BeagleFont.caption2.font)
                        .fontWeight(.semibold)
                        .foregroundStyle(BeagleTheme.textTertiary)
                    Text(workMemoryLine)
                        .font(BeagleFont.caption.font)
                        .foregroundStyle(BeagleTheme.textSecondary)
                        .lineLimit(4)
                    Text(workMemoryStatus)
                        .font(BeagleFont.caption2.font)
                        .foregroundStyle(BeagleTheme.textTertiary)
                        .lineLimit(2)
                }
            }

            Text("Notebook Blocks")
                .font(BeagleFont.caption2.font)
                .fontWeight(.semibold)
                .foregroundStyle(BeagleTheme.textTertiary)

            ScrollView {
                LazyVStack(spacing: 8) {
                    ForEach(blocks) { block in
                        TerminalBlockRow(
                            block: block,
                            isSelected: block.id == selectedBlockId,
                            onSelect: { onSelect(block) },
                            onRemember: { onRemember(block) },
                            onBakeOff: { onBakeOff(block) }
                        )
                    }
                }
                .padding(.bottom, BeagleSpacing.md)
            }
        }
        .padding(BeagleSpacing.md)
        .background(BeagleTheme.surface0.opacity(0.68))
    }
}

private struct CompactEvidenceRail: View {
    let artifacts: [VisualWorkArtifact]
    let selectedArtifactId: String?
    let onSelect: (VisualWorkArtifact) -> Void
    let onRemember: (VisualWorkArtifact) -> Void
    let onBakeOff: (VisualWorkArtifact) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: BeagleSpacing.sm) {
                if artifacts.isEmpty {
                    Text("Evidence will appear here after an agent or shell action.")
                        .font(BeagleFont.caption.font)
                        .foregroundStyle(BeagleTheme.textSecondary)
                        .padding(12)
                        .frame(width: 280, alignment: .leading)
                        .background(BeagleTheme.surface1.opacity(0.44), in: RoundedRectangle(cornerRadius: 8))
                } else {
                    ForEach(artifacts.prefix(12)) { artifact in
                        VisualProofArtifactRow(
                            artifact: artifact,
                            isSelected: artifact.id == selectedArtifactId,
                            onSelect: { onSelect(artifact) },
                            onRemember: { onRemember(artifact) },
                            onBakeOff: { onBakeOff(artifact) }
                        )
                        .frame(width: 280)
                    }
                }
            }
            .padding(.horizontal, BeagleSpacing.md)
            .padding(.vertical, BeagleSpacing.sm)
        }
        .background(BeagleTheme.surface0.opacity(0.72))
    }
}

private struct RendererBakeOffSheet: View {
    let sample: WorkbenchBakeOffSample
    let judgments: [RendererHumanJudgment]
    let onRecordJudgment: (RendererHumanJudgment) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var selectedCandidate: WorkbenchRendererCandidate = .warpDerived
    @State private var humanScore = 3
    @State private var notes = ""
    @State private var openedAt = Date()

    var body: some View {
        GeometryReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: BeagleSpacing.md) {
                    header
                    if proxy.size.width >= 940 {
                        HStack(alignment: .top, spacing: BeagleSpacing.md) {
                            BeagleRendererPane(sample: sample)
                            WarpRendererPane(sample: sample, selectedCandidate: selectedCandidate)
                        }
                    } else {
                        VStack(spacing: BeagleSpacing.md) {
                            BeagleRendererPane(sample: sample)
                            WarpRendererPane(sample: sample, selectedCandidate: selectedCandidate)
                        }
                    }
                    appleDeviceGatePanel(width: proxy.size.width)
                    scorePanel
                    recentJudgments
                }
                .padding(BeagleSpacing.lg)
            }
        }
        .navigationTitle("Renderer Bake-off")
        #if !os(macOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Record") {
                    onRecordJudgment(
                        RendererHumanJudgment(
                            sampleId: sample.id,
                            selectedCandidate: selectedCandidate,
                            score: humanScore,
                            notes: notes
                        )
                    )
                    notes = ""
                }
            }
            ToolbarItem(placement: .cancellationAction) {
                Button("Done") { dismiss() }
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: BeagleSpacing.sm) {
            Text(sample.title)
                .font(BeagleFont.title2.font)
                .foregroundStyle(BeagleTheme.textPrimary)
                .lineLimit(2)
            HStack(spacing: 8) {
                bakeOffPill("hot_path=beagle-terminal-v1", tint: BeagleTheme.truthObserved)
                bakeOffPill("warp_renderer=spike", tint: BeagleTheme.truthRemembered)
                bakeOffPill("canonical_memory=cluster-only", tint: BeagleTheme.textSecondary)
                if sample.restrictedRedacted {
                    bakeOffPill("restricted redacted", tint: BeagleTheme.postureWarm)
                }
            }
            Text("Exploratory gate: continue only if this reveals useful renderer learning; no renderer promotion occurs here.")
                .font(BeagleFont.caption.font)
                .foregroundStyle(BeagleTheme.textSecondary)
        }
    }

    private var scorePanel: some View {
        GlassPanel(elevation: .flush, truth: .observed) {
            VStack(alignment: .leading, spacing: BeagleSpacing.sm) {
                Text("Human judgment")
                    .font(BeagleFont.caption.font)
                    .fontWeight(.semibold)
                    .foregroundStyle(BeagleTheme.textTertiary)
                    .textCase(.uppercase)
                Picker("Candidate", selection: $selectedCandidate) {
                    ForEach(WorkbenchRendererCandidate.allCases, id: \.self) { candidate in
                        Text(candidate.title).tag(candidate)
                    }
                }
                .pickerStyle(.segmented)
                Stepper("UX score: \(humanScore)/5", value: $humanScore, in: 1...5)
                    .font(BeagleFont.body.font)
                    .foregroundStyle(BeagleTheme.textPrimary)
                TextField("Notes: fidelity, latency, ergonomics, surprise", text: $notes, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                HStack(spacing: 8) {
                    metricPill("sample \(sample.blockId)")
                    metricPill(sample.memoryStatus)
                    metricPill(sample.bridgeVersion)
                    metricPill("\(Int(Date().timeIntervalSince(openedAt) * 1000))ms open")
                }
            }
        }
    }

    private func appleDeviceGatePanel(width: CGFloat) -> some View {
        let gate = WorkbenchAppleDeviceGate.evaluate(
            sample: sample,
            judgments: judgments,
            viewportWidth: Double(width),
            dynamicTypeReady: true,
            touchTargetReady: true
        )
        return GlassPanel(elevation: .flush, truth: gate.status == "blocked" ? .stale : .observed) {
            VStack(alignment: .leading, spacing: BeagleSpacing.sm) {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Apple device gate")
                            .font(BeagleFont.caption.font)
                            .fontWeight(.semibold)
                            .foregroundStyle(BeagleTheme.textTertiary)
                            .textCase(.uppercase)
                        Text(gate.status.replacingOccurrences(of: "_", with: " "))
                            .font(BeagleFont.body.font)
                            .fontWeight(.semibold)
                            .foregroundStyle(gate.blockers.isEmpty ? BeagleTheme.truthObserved : BeagleTheme.postureWarm)
                    }
                    Spacer()
                    Text(gate.formFactor.rawValue)
                        .font(BeagleFont.caption2.font)
                        .foregroundStyle(BeagleTheme.textTertiary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(BeagleTheme.surface1.opacity(0.7), in: Capsule())
                }
                HStack(spacing: 8) {
                    metricPill("width \(Int(gate.viewportWidth))")
                    metricPill(gate.restrictedLeakCheck)
                    metricPill("VT \(gate.vtFidelityStatus)")
                    metricPill("latency \(gate.latencyStatus)")
                    if let score = gate.humanJudgmentScore {
                        metricPill("human \(score)/5")
                    } else {
                        metricPill("human pending")
                    }
                }
                if !gate.blockers.isEmpty {
                    Text(gate.blockers.joined(separator: " · "))
                        .font(BeagleFont.caption.font)
                        .foregroundStyle(BeagleTheme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Text("Promotion remains disabled here; this panel only proves whether the Apple surface is ready for a human device pass.")
                    .font(BeagleFont.caption2.font)
                    .foregroundStyle(BeagleTheme.textTertiary)
            }
        }
    }

    @ViewBuilder
    private var recentJudgments: some View {
        if !judgments.isEmpty {
            VStack(alignment: .leading, spacing: BeagleSpacing.xs) {
                Text("Recent local judgments")
                    .font(BeagleFont.caption.font)
                    .fontWeight(.semibold)
                    .foregroundStyle(BeagleTheme.textTertiary)
                    .textCase(.uppercase)
                ForEach(judgments.prefix(4)) { judgment in
                    HStack {
                        Text(judgment.selectedCandidate.title)
                            .font(BeagleFont.caption.font)
                            .foregroundStyle(BeagleTheme.textPrimary)
                        Spacer()
                        Text("\(judgment.score)/5")
                            .font(BeagleFont.caption.font)
                            .foregroundStyle(BeagleTheme.truthObserved)
                    }
                    .padding(8)
                    .background(BeagleTheme.surface1.opacity(0.55), in: RoundedRectangle(cornerRadius: 8))
                }
            }
        }
    }

    private func bakeOffPill(_ label: String, tint: Color) -> some View {
        Text(label)
            .font(BeagleFont.caption2.font)
            .fontWeight(.semibold)
            .foregroundStyle(tint)
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background(tint.opacity(0.12), in: Capsule())
    }

    private func metricPill(_ label: String) -> some View {
        Text(label)
            .font(BeagleFont.caption2.font)
            .foregroundStyle(BeagleTheme.textTertiary)
            .lineLimit(1)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(BeagleTheme.surface1.opacity(0.7), in: Capsule())
    }
}

private struct BeagleRendererPane: View {
    let sample: WorkbenchBakeOffSample

    var body: some View {
        rendererShell(title: "A · Beagle Terminal", subtitle: "TerminalGrid hot path") {
            Text(sample.outputPreview)
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(sample.restrictedRedacted ? BeagleTheme.postureWarm : BeagleTheme.textData)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .topLeading)
                .padding(12)
        }
    }
}

private struct WarpRendererPane: View {
    let sample: WorkbenchBakeOffSample
    let selectedCandidate: WorkbenchRendererCandidate

    var body: some View {
        rendererShell(title: "B · \(selectedCandidate.title)", subtitle: subtitle) {
            MicroMetalWarpPreview(sample: sample, candidate: selectedCandidate)
                .frame(minHeight: 220)
                .padding(10)
        }
    }

    private var subtitle: String {
        #if os(macOS)
        return "Warp Metal probe may attach partial macOS output"
        #else
        return "Native micro-renderer compatible with WarpBlock"
        #endif
    }
}

private struct MicroMetalWarpPreview: View {
    let sample: WorkbenchBakeOffSample
    let candidate: WorkbenchRendererCandidate

    var body: some View {
        Canvas { context, size in
            let bg = Path(roundedRect: CGRect(origin: .zero, size: size), cornerRadius: 12)
            context.fill(bg, with: .color(Color(red: 0.035, green: 0.045, blue: 0.07)))
            let accentRect = CGRect(x: 0, y: 0, width: 4, height: size.height)
            context.fill(Path(accentRect), with: .color(accent))
            let text = sample.restrictedRedacted
                ? "[restricted output redacted]"
                : sample.outputPreview.isEmpty ? sample.command : sample.outputPreview
            let lines = text.split(separator: "\n", omittingEmptySubsequences: false).prefix(18)
            var y: CGFloat = 14
            for line in lines {
                let attributed = AttributedString(String(line.prefix(120)))
                var resolved = context.resolve(Text(attributed).font(.system(size: 12, design: .monospaced)).foregroundStyle(textColor))
                resolved.shading = .color(sample.restrictedRedacted ? BeagleTheme.postureWarm : BeagleTheme.textData)
                context.draw(resolved, at: CGPoint(x: 16, y: y), anchor: .topLeading)
                y += 16
                if y > size.height - 20 { break }
            }
        }
        .overlay(alignment: .topTrailing) {
            Text(candidate.rawValue)
                .font(BeagleFont.caption2.font)
                .foregroundStyle(accent)
                .padding(7)
                .background(.black.opacity(0.24), in: Capsule())
                .padding(8)
        }
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(sample.restrictedRedacted ? BeagleTheme.postureWarm.opacity(0.45) : accent.opacity(0.28), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private var accent: Color {
        switch candidate {
        case .beagleTerminal: return BeagleTheme.truthObserved
        case .warpDerived: return BeagleTheme.truthRemembered
        case .warpMetalProbe: return BeagleTheme.postureWarm
        case .ipadMicroMetal: return BeagleTheme.textData
        }
    }

    private var textColor: Color {
        sample.restrictedRedacted ? BeagleTheme.postureWarm : BeagleTheme.textData
    }
}

private func rendererShell<Content: View>(
    title: String,
    subtitle: String,
    @ViewBuilder content: () -> Content
) -> some View {
    VStack(alignment: .leading, spacing: BeagleSpacing.sm) {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(BeagleFont.body.font)
                .fontWeight(.semibold)
                .foregroundStyle(BeagleTheme.textPrimary)
            Text(subtitle)
                .font(BeagleFont.caption2.font)
                .foregroundStyle(BeagleTheme.textTertiary)
        }
        content()
            .frame(maxWidth: .infinity, minHeight: 240, alignment: .topLeading)
            .background(BeagleTheme.surface0.opacity(0.82), in: RoundedRectangle(cornerRadius: 12))
    }
    .padding(12)
    .background(BeagleTheme.surface1.opacity(0.62), in: RoundedRectangle(cornerRadius: 8))
    .overlay(
        RoundedRectangle(cornerRadius: 8)
            .stroke(BeagleTheme.hairline, lineWidth: 1)
    )
}

private struct TerminalBlockRow: View {
    let block: TerminalBlock
    let isSelected: Bool
    let onSelect: () -> Void
    let onRemember: () -> Void
    let onBakeOff: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 7) {
                HStack(spacing: 6) {
                    Image(systemName: blockIcon)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(statusTint)
                    Text(block.title.isEmpty ? block.kind.capitalized : block.title)
                        .font(BeagleFont.caption.font)
                        .fontWeight(.semibold)
                        .foregroundStyle(BeagleTheme.textPrimary)
                        .lineLimit(1)
                    Spacer(minLength: 4)
                    Text(memoryLabel)
                        .font(BeagleFont.caption2.font)
                        .foregroundStyle(statusTint)
                        .lineLimit(1)
                }
                if !block.command.isEmpty {
                    Text(block.command)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(BeagleTheme.textSecondary)
                        .lineLimit(2)
                }
                HStack(spacing: 6) {
                    Text(block.status)
                    if let exitCode = block.exitCode {
                        Text("exit \(exitCode)")
                    }
                    if let duration = block.durationMs {
                        Text("\(duration / 1000)s")
                    }
                }
                .font(BeagleFont.caption2.font)
                .foregroundStyle(BeagleTheme.textTertiary)

                if block.privacyClass != "restricted_local_only" {
                    HStack(spacing: 10) {
                        Button(action: onRemember) {
                            Label("Remember", systemImage: "externaldrive.connected.to.line.below")
                                .font(BeagleFont.caption2.font)
                        }
                        .buttonStyle(.borderless)
                        .foregroundStyle(BeagleTheme.truthObserved)

                        Button(action: onBakeOff) {
                            Label("Bake-off", systemImage: "rectangle.split.2x1")
                                .font(BeagleFont.caption2.font)
                        }
                        .buttonStyle(.borderless)
                        .foregroundStyle(BeagleTheme.truthRemembered)
                    }
                } else {
                    Button(action: onBakeOff) {
                        Label("Proof only", systemImage: "lock.shield")
                            .font(BeagleFont.caption2.font)
                    }
                    .buttonStyle(.borderless)
                    .foregroundStyle(BeagleTheme.postureWarm)
                }
            }
            .padding(10)
            .background(rowBackground, in: RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(isSelected ? BeagleTheme.truthObserved.opacity(0.55) : BeagleTheme.hairline, lineWidth: 1)
            )
        }
        .contentShape(RoundedRectangle(cornerRadius: 8))
        .onTapGesture(perform: onSelect)
        .buttonStyle(.plain)
    }

    private var blockIcon: String {
        if block.privacyClass == "restricted_local_only" { return "lock.shield" }
        if block.kind == "test" { return "checkmark.rectangle.stack" }
        if block.kind == "agent" { return "sparkles.rectangle.stack" }
        return "terminal"
    }

    private var memoryLabel: String {
        switch block.memoryStatus {
        case "remembered": return "saved"
        case "blocked": return "blocked"
        case "queued": return "queued"
        case "failed": return "failed"
        default:
            return block.privacyClass == "restricted_local_only" ? "restricted" : "curated"
        }
    }

    private var statusTint: Color {
        if block.privacyClass == "restricted_local_only" || block.memoryStatus == "blocked" {
            return BeagleTheme.postureWarm
        }
        if block.memoryStatus == "failed" { return BeagleTheme.stateError }
        if block.memoryStatus == "remembered" { return BeagleTheme.truthObserved }
        return BeagleTheme.textTertiary
    }

    private var rowBackground: Color {
        isSelected ? BeagleTheme.truthObserved.opacity(0.10) : BeagleTheme.surface1.opacity(0.52)
    }
}

private struct SounioPaperWorkbenchView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var status = "Ready"
    @State private var paperRun: PaperRun?
    @State private var artifacts: PaperRunArtifactsResponse?
    @State private var theatre: PaperRunTheatreSnapshot?
    @State private var publicDigest: PublicDigestArtifact?

    var body: some View {
        List {
            Section("PaperRun") {
                Text(paperRun?.title ?? "Beagle self-writing systems paper")
                    .font(BeagleFont.body.font)
                Text(status)
                    .font(BeagleFont.caption.font)
                    .foregroundStyle(BeagleTheme.textSecondary)
                if let run = paperRun {
                    LabeledContent("Temporal", value: run.temporalStatus)
                    LabeledContent("Approval", value: run.approvalState)
                    LabeledContent("Stage", value: run.currentStage ?? run.status)
                    LabeledContent("Digest", value: run.publicDigestStatus ?? "not generated")
                    if let pending = run.pendingApprovalStep {
                        LabeledContent("Pending", value: pending)
                    }
                    if let summary = run.interactionSummary, !summary.isEmpty {
                        Text(summary)
                            .font(BeagleFont.caption.font)
                            .foregroundStyle(BeagleTheme.textSecondary)
                    }
                }
            }
            if let theatre {
                Section("Theatre") {
                    LabeledContent("Stage", value: theatre.currentStage)
                    LabeledContent("Next", value: theatre.nextAction)
                    LabeledContent("Claims", value: "\(theatre.claimGraph.claims.count)")
                    LabeledContent("Unsupported", value: "\(theatre.claimGraph.unsupportedClaimIds.count)")
                    LabeledContent("Private trace", value: theatre.privateTraceRef)
                        .font(BeagleFont.caption.font)
                    statusGrid(theatre.claimGraph.statusCounts)
                }
                if !theatre.claimGraph.claims.isEmpty {
                    Section("Claims") {
                        ForEach(theatre.claimGraph.claims) { claim in
                            VStack(alignment: .leading, spacing: 6) {
                                HStack {
                                    Text(claim.epistemicStatus.uppercased())
                                        .font(BeagleFont.caption2.font)
                                        .foregroundStyle(statusColor(claim.epistemicStatus))
                                    Spacer()
                                    Text(claim.publicationReadiness)
                                        .font(BeagleFont.caption2.font)
                                        .foregroundStyle(BeagleTheme.textTertiary)
                                }
                                Text(claim.claimText)
                                    .font(BeagleFont.caption.font)
                                Text("\(claim.evidenceRefs.count) evidence refs · confidence \(claim.confidence, specifier: "%.2f")")
                                    .font(BeagleFont.caption2.font)
                                    .foregroundStyle(BeagleTheme.textSecondary)
                            }
                            .padding(.vertical, 4)
                        }
                    }
                }
            }
            Section("Actions") {
                Button {
                    Task { await startPaperRun() }
                } label: {
                    Label("Start PaperRun", systemImage: "play.circle")
                }
                .disabled(status == "Starting")
                if let run = paperRun, let pending = run.pendingApprovalStep {
                    Button {
                        Task { await approve(run: run, step: pending) }
                    } label: {
                        Label("Approve \(pending)", systemImage: "checkmark.seal")
                    }
                }
                if let run = paperRun {
                    Button {
                        Task { await loadArtifacts(run.id) }
                    } label: {
                        Label("Load Artifacts", systemImage: "doc.text.magnifyingglass")
                    }
                    Button {
                        Task { await loadTheatre(run.id) }
                    } label: {
                        Label("Open Theatre", systemImage: "theatermasks")
                    }
                    Button {
                        Task { await addSedenionClaim(run) }
                    } label: {
                        Label("Add Sedenion SSM Claim", systemImage: "function")
                    }
                    if let firstClaim = theatre?.claimGraph.claims.first {
                        Button {
                            Task { await reviewClaim(run: run, claim: firstClaim) }
                        } label: {
                            Label("Review First Claim", systemImage: "checkmark.seal")
                        }
                    }
                    Button {
                        Task { await loadPublicDigest(run.id) }
                    } label: {
                        Label("Public Digest", systemImage: "doc.plaintext")
                    }
                }
            }
            if let artifacts {
                Section("Manuscript") {
                    Text(artifacts.manuscriptMarkdown)
                        .font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled)
                }
            }
            if let publicDigest {
                Section("Public Digest") {
                    Text(publicDigest.thesis)
                        .font(BeagleFont.caption.font)
                    Text(publicDigest.disclosure)
                        .font(BeagleFont.caption2.font)
                        .foregroundStyle(BeagleTheme.textSecondary)
                    Text(publicDigest.manuscriptExcerpt)
                        .font(.system(.caption2, design: .monospaced))
                        .textSelection(.enabled)
                }
            }
        }
        .navigationTitle("PaperRun Theatre")
        #if !os(macOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Done") { dismiss() }
            }
        }
    }

    private func startPaperRun() async {
        status = "Starting"
        let result = await BeagleClient.shared.startSounioPaperRun()
        if let run = result.value {
            paperRun = run
            status = "\(run.status) · \(run.temporalStatus)"
            await loadTheatre(run.id)
        } else {
            status = result.error ?? "PaperRun failed"
        }
    }

    private func approve(run: PaperRun, step: String) async {
        status = "Approving \(step)"
        let result = await BeagleClient.shared.approveSounioPaperRunStep(
            paperRunId: run.id,
            stepId: step,
            rationale: "Approved from Beagle Apple Paper Workbench."
        )
        if let updated = result.value {
            paperRun = updated
            status = "\(updated.status) · \(updated.temporalStatus)"
            await loadTheatre(updated.id)
        } else {
            status = result.error ?? "Approval failed"
        }
    }

    private func loadArtifacts(_ paperRunId: String) async {
        status = "Loading artifacts"
        let result = await BeagleClient.shared.sounioPaperRunArtifacts(paperRunId)
        if let response = result.value {
            artifacts = response
            status = "Artifacts loaded"
        } else {
            status = result.error ?? "Artifact load failed"
        }
    }

    private func loadTheatre(_ paperRunId: String) async {
        status = "Loading Theatre"
        let result = await BeagleClient.shared.sounioPaperRunTheatre(paperRunId)
        if let response = result.value {
            theatre = response
            paperRun = response.paperRun
            status = "Theatre loaded · \(response.currentStage)"
        } else {
            status = result.error ?? "Theatre load failed"
        }
    }

    private func addSedenionClaim(_ run: PaperRun) async {
        status = "Typing Sedenion SSM claim"
        let claim = SounioClaimInput(
            id: "claim-sedenion-ssm-arc",
            claimText: "The Sedenion SSM arc is the first strong Beagle/Sounio demonstration because it combines hypercomplex primitives, theorem-like claims, artifacts, and epistemic verification.",
            subject: "sedenion_ssm_arc",
            epistemicStatus: "contest",
            evidenceRefs: [
                "artifact:sedenion_ssm_arc",
                "theorem_refs:sedenion_ssm",
                "paperrun:beagle_self_writing_systems"
            ],
            provenance: .object([
                "source": .string("beagle-apple-paper-workbench"),
                "case": .string("sedenion-ssm-arc"),
                "independent_verification": .bool(false)
            ]),
            confidence: 0.72,
            contestation: .object([
                "reason": .string("Requires human review and independent theorem/evidence mapping before Knowledge<T>.")
            ]),
            sectionId: "Sounio IR",
            agentRefs: ["beagle-app"],
            artifactRefs: ["/orangefs/beagle-memory-lab/paperruns/\(run.id)/sedenion_ssm_public_case.json"],
            privacyClass: "sensitive",
            rationale: "This is a demonstrative claim, not yet Robust<T>."
        )
        let result = await BeagleClient.shared.addSounioClaim(paperRunId: run.id, claim: claim)
        if let added = result.value {
            status = "Claim \(added.epistemicStatus) added"
            await loadTheatre(run.id)
        } else {
            status = result.error ?? "Claim add failed"
        }
    }

    private func reviewClaim(run: PaperRun, claim: SounioClaim) async {
        status = "Reviewing claim"
        let decision = claim.epistemicStatus == "belief" || claim.epistemicStatus == "contest"
            ? "promote_to_knowledge"
            : "approved"
        let result = await BeagleClient.shared.reviewSounioClaim(
            paperRunId: run.id,
            claimId: claim.id,
            decision: decision,
            rationale: "Reviewed from iPhone/iPad PaperRun Theatre; Knowledge<T> remains evidence/provenance-gated.",
            evidenceRefs: claim.evidenceRefs,
            epistemicStatus: nil,
            publicationReadiness: nil,
            provenance: .object([
                "source": .string("beagle-apple-paper-workbench"),
                "human_review": .bool(true)
            ])
        )
        if let reviewed = result.value {
            status = "Claim reviewed as \(reviewed.epistemicStatus)"
            await loadTheatre(run.id)
        } else {
            status = result.error ?? "Claim review failed"
        }
    }

    private func loadPublicDigest(_ paperRunId: String) async {
        status = "Loading public digest"
        let result = await BeagleClient.shared.sounioPaperRunPublicDigest(paperRunId)
        if let response = result.value {
            publicDigest = response
            status = "Public digest sanitized"
            await loadTheatre(paperRunId)
        } else {
            status = result.error ?? "Public digest failed"
        }
    }

    @ViewBuilder
    private func statusGrid(_ counts: [String: Int]) -> some View {
        if counts.isEmpty {
            Text("No typed claims yet")
                .font(BeagleFont.caption2.font)
                .foregroundStyle(BeagleTheme.textTertiary)
        } else {
            HStack {
                ForEach(counts.keys.sorted(), id: \.self) { key in
                    VStack(alignment: .leading) {
                        Text(key.uppercased())
                            .font(BeagleFont.caption2.font)
                            .foregroundStyle(statusColor(key))
                        Text("\(counts[key] ?? 0)")
                            .font(BeagleFont.body.font)
                    }
                    Spacer()
                }
            }
        }
    }

    private func statusColor(_ status: String) -> Color {
        switch status.lowercased() {
        case "robust":
            return BeagleTheme.truthObserved
        case "knowledge":
            return BeagleTheme.truthRemembered
        case "contest":
            return BeagleTheme.postureWarm
        default:
            return BeagleTheme.textSecondary
        }
    }
}
