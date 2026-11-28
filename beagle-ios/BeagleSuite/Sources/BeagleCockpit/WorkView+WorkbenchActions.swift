//
//  WorkView+WorkbenchActions.swift
//  BeagleCockpit
//
//  Workbench session lifecycle, lane routing, agent registry,
//  memory curation, and runtime log presentation for WorkView.
//

import SwiftUI
import BeagleCore
import BeagleWorkbenchKit

extension WorkView {

    // MARK: - Workbench connection

    func prepareWorkbench(forceNew: Bool = false) async {
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

    func createWorkbenchPane(kind: String, title: String) async {
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

    func openLane(_ lane: String, startProcess: Bool, showTerminal: Bool) async {
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

    func paneForLane(_ lane: String) -> TerminalPane? {
        let role = agentRole(for: lane)
        return workspaceSession?.panes.first { pane in
            if let role {
                return pane.agentRole == role.role || normalizedLaneKind(pane.kind) == role.kind
            }
            return normalizedLaneKind(pane.kind) == normalizedLaneKind(lane)
        }
    }

    func normalizedLaneKind(_ kind: String?) -> String {
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

    func laneTitle(_ lane: String) -> String {
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

    func agentRole(for lane: String) -> AgentRole? {
        let key = lane.trimmingCharacters(in: .whitespacesAndNewlines)
        return visibleAgentRoles.first { role in
            role.role == key || role.kind == key || role.providerSlots.contains(where: { $0.id == key })
        } ?? agentRoles.first { role in
            role.role == key || role.kind == key || role.providerSlots.contains(where: { $0.id == key })
        }
    }

    func refreshAgentRegistry() async {
        let response = await CockpitClient.shared.agentRegistry(slug: activeSlug)
        if let roles = response.value?.roles, !roles.isEmpty {
            agentRoles = roles
        }
    }

    /// Builds and presents the provider Set-up sheet for a lane. Falls back to
    /// launching the lane when no configurable provider slot exists (e.g. the
    /// CLI/PATH-based or shell lanes), so the affordance never dead-ends.
    func presentProviderSetup(for laneId: String) {
        guard let role = agentRole(for: laneId) else {
            Task { await openLane(laneId, startProcess: laneId != "shell", showTerminal: true) }
            return
        }
        // Subscription / CLI lanes (Codex = ChatGPT Pro, Claude Code = Claude Max,
        // Kimi) authenticate via the CLI's own login inside the workspace terminal —
        // there is no API key to enter. Open a terminal so the user can install the
        // CLI (if missing) and run its subscription login; we never capture that session.
        if laneIsSubscriptionCLI(role.kind) {
            Task { await openLane(laneId, startProcess: false, showTerminal: true) }
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
            Task { await openLane(laneId, startProcess: false, showTerminal: true) }
            return
        }
        providerSetupTarget = target
    }

    func refreshWorkbenchBlocks() async {
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

    func rememberSelectedOrLatestBlock() async {
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

    func rememberArtifact(_ artifact: VisualWorkArtifact) async {
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

    func refreshWorkMemoryContext() async {
        async let home: Void = exocortex.refresh(activeProjectSlug: activeSlug, platform: "beagle-apple-work")
        async let graph: Void = exocortex.refreshRecentGraph(limit: 16)
        _ = await (home, graph)
    }

    func presentRuntimeLog(title: String? = nil, paneId: String? = nil) {
        runtimeLogPresentation = RuntimeLogPresentationState(
            title: title ?? activePane?.title ?? "Runtime Log",
            sessionId: workspaceSession?.id,
            paneId: paneId ?? activePane?.id,
            isRuntimePrimary: false
        )
    }
}
