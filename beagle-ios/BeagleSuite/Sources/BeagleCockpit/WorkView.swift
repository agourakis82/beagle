//
//  WorkView.swift
//  BeagleCockpit
//
//  The Work tab. Terminal, agents, and operational access.
//  First-class terminal that connects to workspace tmux.
//  Quick access to Platform, ControlRoom, HPC, ScienceJobs.
//

import SwiftUI
import BeagleCore

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
    @State private var workbenchStatus = "Notebook terminal warming up"
    @State private var workbenchError: String?
    @State private var isRefreshingWorkbench = false
    @State private var showLaneTerminal = false
    @State private var showScoutLanes = false
    @State private var agentRoles: [AgentRole] = []
    @State private var latestRouteDecision: AgentRouteDecision?

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
                    blockCount: terminalBlocks.count
                )

                if proxy.size.width >= 980 {
                    HStack(spacing: 0) {
                        WorkspaceSessionRail(
                            session: workspaceSession,
                            activePaneId: activePane?.id,
                            onSelectPane: { pane in
                                connectWorkbenchPane(pane)
                            },
                            onNewShell: {
                                Task { await createWorkbenchPane(kind: "human", title: "Shell") }
                            },
                            onNewCodex: {
                                Task { await createWorkbenchPane(kind: "codex", title: "Codex") }
                            },
                            onNewClaude: {
                                Task { await createWorkbenchPane(kind: "claude-code", title: "Claude Code") }
                            }
                        )
                        .frame(width: 220)

                        Divider().overlay(BeagleTheme.hairline)

                        terminalColumn

                        Divider().overlay(BeagleTheme.hairline)

                        WorkbenchInspector(
                            blocks: terminalBlocks,
                            selectedBlockId: selectedBlockId,
                            workMemoryLine: latestWorkMemoryLine,
                            workMemoryStatus: workMemoryStatus,
                            onSelect: { block in selectedBlockId = block.id },
                            onRemember: { block in
                                Task { await rememberBlock(block) }
                            }
                        )
                        .frame(width: 320)
                    }
                } else {
                    VStack(spacing: 0) {
                        AgentConsoleView(
                            snapshot: agentConsoleSnapshot,
                            onOpenLane: { lane in
                                Task { await openLane(lane, startProcess: false, showTerminal: true) }
                            },
                            onStartLane: { lane in
                                Task { await openLane(lane, startProcess: lane != "shell", showTerminal: true) }
                            },
                            onShowTerminal: {
                                showLaneTerminal = true
                            }
                        )
                        .padding(.horizontal, BeagleSpacing.md)
                        .padding(.vertical, BeagleSpacing.sm)
                        if !scoutAgentRoles.isEmpty {
                            ScoutLaneDrawer(
                                isExpanded: $showScoutLanes,
                                lanes: scoutAgentRoles.map(agentLaneState),
                                onOpenLane: { lane in
                                    Task { await openLane(lane, startProcess: false, showTerminal: true) }
                                },
                                onStartLane: { lane in
                                    Task { await openLane(lane, startProcess: true, showTerminal: true) }
                                }
                            )
                            .padding(.horizontal, BeagleSpacing.md)
                            .padding(.bottom, BeagleSpacing.xs)
                        }
                        CompactBlockRail(
                            blocks: terminalBlocks,
                            selectedBlockId: selectedBlockId,
                            onSelect: { block in selectedBlockId = block.id },
                            onRemember: { block in
                                Task { await rememberBlock(block) }
                            }
                        )
                        latestWorkMemoryStrip
                    }
                }

                if proxy.size.width >= 980 {
                    quickAccessStrip
                } else {
                    AgentConsoleDock(
                        state: workbenchDockState,
                        onInput: { showLaneTerminal = true },
                        onInterrupt: { terminal.sendSignal("SIGINT") },
                        onApprove: { terminal.approve() },
                        onRemember: { Task { await rememberSelectedOrLatestBlock() } },
                        onFocus: { Task { await openLane("primary_builder", startProcess: true, showTerminal: true) } },
                        onScout: { Task { await openLane("long_thought_architect", startProcess: true, showTerminal: true) } },
                        onCompare: { Task { await openLane("code_worker", startProcess: true, showTerminal: true) } },
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
        .sheet(isPresented: $showLaneTerminal) {
            NavigationStack {
                terminalColumn
                    .navigationTitle(activePane?.title ?? "Workbench Terminal")
                    #if !os(macOS)
                    .navigationBarTitleDisplayMode(.inline)
                    #endif
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Done") { showLaneTerminal = false }
                        }
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

    // MARK: - Workbench connection

    private func prepareWorkbench(forceNew: Bool = false) async {
        workbenchError = nil
        workbenchStatus = "Opening Notebook Terminal..."
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
                workbenchError = "Workspace service unavailable; using raw terminal fallback."
                workbenchStatus = "Fallback terminal"
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
            showLaneTerminal = true
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
        if let latest = terminalBlocks.first {
            await rememberBlock(latest)
            return
        }
        await recordWorkMemory()
    }

    private func rememberBlock(_ block: TerminalBlock) async {
        guard let session = workspaceSession else { return }
        workMemoryStatus = "Curating block..."
        let response = await CockpitClient.shared.rememberWorkspaceBlock(
            slug: activeSlug,
            sessionId: session.id,
            blockId: block.id
        )
        if let payload = response.value {
            switch payload.memory.status {
            case "remembered":
                workMemoryStatus = "Remembered block \(block.title)"
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
            providerLabel: provider.map { "\($0.title) · \($0.runtime)" },
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
                            onStart: { onStartLane(lane.id) }
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
            VStack(alignment: .leading, spacing: 3) {
                Text("Sounio Workbench")
                    .font(BeagleFont.headline.font)
                    .foregroundStyle(BeagleTheme.textPrimary)
                Text(subtitle)
                    .font(BeagleFont.caption.font)
                    .foregroundStyle(BeagleTheme.textSecondary)
                    .lineLimit(1)
            }
            Spacer(minLength: BeagleSpacing.sm)
            HStack(spacing: 6) {
                headerPill(connectionLabel, icon: connectionIcon, tint: connectionTint)
                headerPill(authorityLabel, icon: "externaldrive.badge.checkmark", tint: authorityTint)
                headerPill("\(blockCount) blocks", icon: "text.badge.checkmark", tint: BeagleTheme.truthRemembered)
            }
        }
        .padding(.horizontal, BeagleSpacing.md)
        .padding(.vertical, BeagleSpacing.sm)
        .background(.ultraThinMaterial)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(BeagleTheme.hairline)
                .frame(height: 1)
        }
    }

    private var subtitle: String {
        if let error, !error.isEmpty {
            return "\(slug) · \(error)"
        }
        let sessionPart = session?.id ?? "session pending"
        let panePart = pane?.title ?? "pane pending"
        let supervisor = session?.authorityStatus?.supervisor?.status
        let authority = session?.authorityStatus?.authority
        let suffix = [authority, supervisor].compactMap { value in
            guard let value, !value.isEmpty else { return nil }
            return value
        }.joined(separator: "/")
        return "\(slug) · \(panePart) · \(sessionPart) · \(suffix.isEmpty ? status : "\(status) · \(suffix)")"
    }

    private var authorityLabel: String {
        switch session?.authorityStatus?.authority {
        case "workspace-agent": return "agent"
        case "cockpit-local": return "local"
        case let value?: return value
        case nil: return "local"
        }
    }

    private var authorityTint: Color {
        if session?.authorityStatus?.authority == "workspace-agent",
           session?.authorityStatus?.supervisor?.status == "healthy" {
            return BeagleTheme.truthObserved
        }
        if session?.authorityStatus?.authority == "workspace-agent" {
            return BeagleTheme.truthRemembered
        }
        return BeagleTheme.textTertiary
    }

    private var connectionLabel: String {
        switch connectionState {
        case .connected: return "live"
        case .connecting: return "connecting"
        case .reconnecting: return "reconnecting"
        case .failed: return "stale"
        case .disconnected: return "offline"
        }
    }

    private var connectionIcon: String {
        switch connectionState {
        case .connected: return "dot.radiowaves.left.and.right"
        case .connecting, .reconnecting: return "arrow.triangle.2.circlepath"
        case .failed: return "exclamationmark.triangle"
        case .disconnected: return "circle.dashed"
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
                        onStart: { onStartLane(lane.id) }
                    )
                }
            }
        }
    }

    private var subtitle: String {
        let authority = snapshot.authority ?? "workspace"
        let session = snapshot.sessionId ?? "session pending"
        return "\(snapshot.projectSlug) · \(authority) · \(session)"
    }
}

private struct AgentLaneCard: View {
    let lane: AgentLaneState
    let onOpen: () -> Void
    let onStart: () -> Void

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
                        Text(lane.detail)
                            .font(BeagleFont.caption2.font)
                            .foregroundStyle(BeagleTheme.textSecondary)
                            .lineLimit(2)
                    }
                    Spacer(minLength: 8)
                    VStack(alignment: .trailing, spacing: 4) {
                        Text(lane.status)
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
                    Button(action: onStart) {
                        Label(lane.paneId == nil ? "Create" : "Resume", systemImage: lane.paneId == nil ? "plus.circle" : "play.circle")
                            .labelStyle(.iconOnly)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(BeagleTheme.truthObserved)
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
                            onRemember: { onRemember(block) }
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

private struct CompactBlockRail: View {
    let blocks: [TerminalBlock]
    let selectedBlockId: String?
    let onSelect: (TerminalBlock) -> Void
    let onRemember: (TerminalBlock) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: BeagleSpacing.sm) {
                ForEach(blocks.prefix(12)) { block in
                    TerminalBlockRow(
                        block: block,
                        isSelected: block.id == selectedBlockId,
                        onSelect: { onSelect(block) },
                        onRemember: { onRemember(block) }
                    )
                    .frame(width: 260)
                }
            }
            .padding(.horizontal, BeagleSpacing.md)
            .padding(.vertical, BeagleSpacing.sm)
        }
        .background(BeagleTheme.surface0.opacity(0.72))
    }
}

private struct TerminalBlockRow: View {
    let block: TerminalBlock
    let isSelected: Bool
    let onSelect: () -> Void
    let onRemember: () -> Void

    var body: some View {
        Button(action: onSelect) {
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
                    Button(action: onRemember) {
                        Label("Remember", systemImage: "externaldrive.connected.to.line.below")
                            .font(BeagleFont.caption2.font)
                    }
                    .buttonStyle(.borderless)
                    .foregroundStyle(BeagleTheme.truthObserved)
                }
            }
            .padding(10)
            .background(rowBackground, in: RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(isSelected ? BeagleTheme.truthObserved.opacity(0.55) : BeagleTheme.hairline, lineWidth: 1)
            )
        }
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
