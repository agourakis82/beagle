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
    @Environment(CatalogStore.self) var catalog
    @Environment(CognitiveStore.self) private var cognitive
    @Binding var bootError: String?

    @State var terminal = TerminalStore()
    @State var exocortex = ExocortexStore()
    @State private var terminalInputText = ""
    @State private var showAgentSession = false
    @State private var showPlatform = false
    @State private var showPaperWorkbench = false
    @State var workMemoryStatus = "Work memory idle"
    @State var workspaceSession: WorkspaceSession?
    @State var activePane: TerminalPane?
    @State var terminalBlocks: [TerminalBlock] = []
    @State var selectedBlockId: String?
    @State var workbenchStatus = "Preparing agent deck"
    @State var workbenchError: String?
    @State var isRefreshingWorkbench = false
    @State var runtimeLogPresentation: RuntimeLogPresentationState?
    @State private var showScoutLanes = false
    @State private var showRendererBakeOff = false
    @State private var rendererJudgments: [RendererHumanJudgment] = []
    @State var agentRoles: [AgentRole] = []
    @State var latestRouteDecision: AgentRouteDecision?
    @State var providerSetupTarget: ProviderSetupTarget?

    init(bootError: Binding<String?>) {
        self._bootError = bootError
    }

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

    // MARK: - Computed

    var activeSlug: String {
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

    var visibleAgentRoles: [AgentRole] {
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
            if let readiness = role?.readiness {
                // No pane yet: surface the readiness verdict directly so a freshly
                // configured/available lane reads as "Ready" (not the generic
                // "not running"). Otherwise configuring a provider would never flip
                // the card. A pane appears once the lane is actually started.
                if readiness.status == "needs_setup" {
                    return ("needs_setup", readiness.reason ?? "Provider slot or CLI is not configured yet.")
                }
                if readiness.status == "ready" {
                    return ("ready", readiness.reason ?? "Configured — start to open a lane.")
                }
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
