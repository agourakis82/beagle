import Foundation
import SwiftUI
import BeagleCore

@MainActor
final class WorkbenchStore: ObservableObject {
    @Published var projects: [WorkbenchProject] = []
    @Published var lanes: [WorkbenchLane] = []
    @Published var agents: [WorkbenchAgent] = []
    @Published var messages: [WorkbenchMessage] = []
    @Published var filePreviews: [WorkbenchFilePreview] = []
    @Published var terminalLines: [WorkbenchTerminalLine] = []
    @Published private(set) var workspace: SounioWorkspaceSnapshot = .disconnected
    @Published var selectedProjectID: String = "sounio"
    @Published var chatProjectSlug: String = "darwin-mfc"
    @Published var selectedLaneID: String = "workspace"
    @Published var selectedAgentID: String = ""
    @Published var selectedFileID: String = ""
    @Published var composerText: String = ""
    @Published var composerDelivery: ComposerDelivery = .auto
    @Published var showingTerminal: Bool = true
    @Published var showingFilePreview: Bool = true
    @Published private(set) var isRefreshing = false
    @Published private(set) var isExocortexLoading = false
    @Published private(set) var catalogTruth: TruthMode = .declared
    @Published private(set) var lastError: String?
    @Published var cockpitEndpoint: String
    @Published var pendingLeaseGateText: String?
    @Published private(set) var presenceClients: [WorkbenchContextClient] = []
    @Published private(set) var contextRecords: [WorkbenchContextRecord] = []
    @Published private(set) var handoffItems: [WorkbenchHandoffItem] = []
    @Published private(set) var multimodelProviders: [MultimodelProvider] = []
    @Published var selectedProviderIds: Set<String> = []
    @Published private(set) var agentSessions: [AgentSessionRecord] = []
    @Published private(set) var zellijStatusWire: Truthful<WorkspaceZellijStatusResponse> = WorkbenchWireDefaults.zellijStatus
    @Published private(set) var zellijScreenPreview: String?
    @Published private(set) var isZellijScreenLoading = false
    @Published var selectedHandoffID: String?
    @Published private(set) var isHandoffSending = false
    @Published private(set) var agentTerminalConnected = false
    @Published private(set) var agentTerminalText = ""
    @Published private(set) var agentTerminalKind: String?
    @Published private(set) var agentTerminalPod: String?
    @Published private(set) var agentTerminalError: String?

    var agentTerminalSocket: AgentTerminalWebSocket?
    @Published private(set) var catalogWire: Truthful<ExecutiveCatalog> = WorkbenchWireDefaults.catalog
    @Published private(set) var workspaceWire: Truthful<GoWorkNowEnvelope> = WorkbenchWireDefaults.workspace
    @Published private(set) var clusterWire: Truthful<ClusterOpsSummary> = WorkbenchWireDefaults.cluster
    @Published private(set) var multimodelWire: Truthful<MultimodelTurnsResponse> = WorkbenchWireDefaults.multimodel
    @Published private(set) var presenceWire: Truthful<WorkbenchContextPresenceResponse> = WorkbenchWireDefaults.presence
    @Published private(set) var exocortexWire: Truthful<ExocortexProcessResponse> = WorkbenchWireDefaults.exocortex
    @Published private(set) var graphragWire: Truthful<GraphRAGQueryResponse> = WorkbenchWireDefaults.graphrag
    @Published private(set) var handoffsWire: Truthful<WorkbenchMessageBoardResponse> = WorkbenchWireDefaults.handoffs
    @Published private(set) var handoffCompileWire: Truthful<WorkbenchHandoffCompilePacket> = WorkbenchWireDefaults.handoffCompile
    @Published private(set) var isHandoffCompileLoading = false
    @Published private(set) var providersWire: Truthful<MultimodelProvidersResponse> = WorkbenchWireDefaults.providers
    @Published private(set) var isGraphRAGLoading = false
    @Published private(set) var multimodelSocketConnected = false
    @Published private(set) var multimodelSocketError: String?

    var multimodelSocket: MultimodelChatWebSocket?
    var streamingMessageKeys: [String: UUID] = [:]
    var activeStreamingTurnId: String?

    init() {
        let env = ProcessInfo.processInfo.environment["BEAGLE_COCKPIT_URL"]?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        cockpitEndpoint = (env?.isEmpty == false) ? env! : "http://127.0.0.1:4370"
    }

    var selectedProject: WorkbenchProject? { projects.first { $0.id == selectedProjectID } }
    var selectedLane: WorkbenchLane? { lanes.first { $0.id == selectedLaneID } }
    var selectedAgent: WorkbenchAgent? { agents.first { $0.id == selectedAgentID } }
    var selectedFile: WorkbenchFilePreview? { filePreviews.first { $0.id == selectedFileID } }
    var activeAgents: [WorkbenchAgent] { agents.filter { $0.status == .running || $0.status == .waiting } }
    var lastExocortexPhi: Double? { exocortexWire.value?.phi }

    var isStreamingMultimodel: Bool {
        activeStreamingTurnId != nil || messages.contains(where: \.isStreaming)
    }

    var availableProviderIds: [String] {
        multimodelProviders
            .filter { ($0.status ?? "").lowercased() == "available" }
            .map { $0.providerId ?? $0.rawId ?? $0.id }
    }

    var defaultProviderPreviewIds: [String] {
        let selected = providerIdForSelectedAgent()
        if availableProviderIds.contains(selected) { return [selected] }
        return Array(availableProviderIds.prefix(2))
    }

    var selectedHandoff: WorkbenchHandoffItem? {
        handoffItems.first { $0.messageId == selectedHandoffID }
    }

    var displayAgentTerminalText: String {
        AgentTerminalFormatting.stripANSI(agentTerminalText)
    }

    var isLive: Bool {
        catalogWire.mode == .observed || workspace.source == .live
    }

    var leaseSummary: String {
        guard let lane = selectedLane else { return "No lane selected." }
        switch lane.leaseState {
        case .clear: return "Workspace lane is open."
        case .owned: return "\(agentName(for: lane.ownerAgentID)) marked owner (declarative)."
        case .overlap: return "Overlap risk — confirm before patch/commit."
        case .blocked: return "Blocked until current work settles."
        }
    }

    func refreshAll() async {
        guard !isRefreshing else { return }
        isRefreshing = true
        lastError = nil
        defer { isRefreshing = false }

        await configureCockpitClient()
        await refreshCatalog()
        await refreshWorkspace(for: selectedProjectID)
        await refreshCluster()
        await refreshMultimodel()
        await refreshPresence()
        await refreshHandoffs()
        await refreshAgentSessions()
        await refreshZellijTransport()
        appendBootstrapMessageIfNeeded()
    }

    func refreshWorkspace(for slug: String) async {
        selectedProjectID = slug
        let wire = await CockpitClient.shared.goWorkNow(slug: slug)
        workspaceWire = wire

        if let envelope = wire.value {
            workspace = SounioWorkspaceSnapshot(envelope: envelope, slug: slug)
            applyWorkspaceBindings()
        } else {
            var stale = workspace.projectSlug == slug ? workspace : .disconnected
            stale.projectSlug = slug
            stale.source = workspace.source == .live ? .stale : .disconnected
            stale.error = wire.error ?? "go-work-now failed"
            stale.status = "unreachable"
            stale.summary = "Could not read go-work-now for \(slug)."
            workspace = stale
            lastError = wire.error
            applyWorkspaceBindings()
        }
    }

    func refreshCluster() async {
        clusterWire = await CockpitClient.shared.clusterOpsSummary()
    }

    func refreshMultimodel() async {
        let turns = await CockpitClient.shared.multimodelTurns(slug: chatProjectSlug)
        multimodelWire = turns
        let providers = await CockpitClient.shared.multimodelProviders(slug: chatProjectSlug)
        providersWire = providers
        multimodelProviders = providers.value?.providers ?? []
        if turns.value != nil, !multimodelSocketConnected {
            applyTurnsToMessages(turns.value)
        }
        await applyAgentPresence()
        connectMultimodelWebSocket()
    }

    func connectMultimodelWebSocket() {
        if multimodelSocket == nil {
            let socket = MultimodelChatWebSocket()
            socket.delegate = self
            multimodelSocket = socket
        }
        multimodelSocket?.connect(httpBase: cockpitEndpoint, slug: chatProjectSlug)
    }

    func disconnectMultimodelWebSocket() {
        multimodelSocket?.disconnect()
        multimodelSocketConnected = false
    }

    func refreshHandoffs() async {
        let board = await CockpitClient.shared.workbenchMessageBoard(slug: selectedProjectID)
        handoffsWire = board
        handoffItems = board.value?.nextActions ?? []
    }

    func refreshPresence() async {
        let recent = await CockpitClient.shared.workbenchRecent(slug: selectedProjectID)
        let presence = await CockpitClient.shared.workbenchPresence(slug: selectedProjectID)
        presenceWire = presence
        presenceClients = presence.value?.clients ?? []
        contextRecords = recent.value?.records ?? []

        if recent.error != nil && presence.error == nil {
            presenceWire = Truthful(
                value: presence.value,
                mode: presence.mode,
                observedAt: presence.observedAt,
                source: presence.source,
                error: recent.error
            )
        }
    }

    func runExocortex(query: String) async {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        isExocortexLoading = true
        defer { isExocortexLoading = false }

        let wire = await CockpitClient.shared.exocortexProcess(query: trimmed)
        exocortexWire = wire

        if let result = wire.value {
            messages.append(
                WorkbenchMessage(
                    role: .system,
                    agentKind: .beagle,
                    truth: TruthMode(rawValue: result.truthMode ?? "") ?? wire.mode,
                    title: "Exocortex",
                    content: """
                    Φ=\(result.phi.map { String(format: "%.4f", $0) } ?? "—") · \(result.awarenessLevel ?? "unknown")

                    \(result.response ?? wire.error ?? "No response body.")
                    """
                )
            )
        } else {
            messages.append(
                WorkbenchMessage(
                    role: .system,
                    truth: .stale,
                    title: "Exocortex unavailable",
                    content: wire.error ?? "Could not reach /api/exocortex/process via Cockpit proxy."
                )
            )
        }
    }

    func runGraphRAG(query: String, queryMode: String = "local") async {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        isGraphRAGLoading = true
        defer { isGraphRAGLoading = false }

        let wire = await CockpitClient.shared.workbenchGraphRAG(
            slug: selectedProjectID,
            query: trimmed,
            queryMode: queryMode
        )
        graphragWire = wire
    }

    func selectLane(_ lane: WorkbenchLane) {
        selectedLaneID = lane.id
        if let agent = agents.first(where: { $0.laneID == lane.id }) {
            selectedAgentID = agent.id
        }
    }

    func selectAgent(_ agent: WorkbenchAgent) {
        selectedAgentID = agent.id
        selectedLaneID = agent.laneID
    }

    func sendComposerMessage() {
        let trimmed = composerText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        if requiresLeaseConfirmation(trimmed), pendingLeaseGateText != trimmed {
            pendingLeaseGateText = trimmed
            messages.append(
                WorkbenchMessage(
                    role: .system,
                    truth: .declared,
                    title: "Lease guard",
                    content: "This message looks like a mutating action. Send the same text again to confirm."
                )
            )
            return
        }
        pendingLeaseGateText = nil

        if trimmed.lowercased().hasPrefix("/exocortex ") {
            let query = String(trimmed.dropFirst("/exocortex ".count))
            composerText = ""
            Task { await runExocortex(query: query) }
            return
        }

        if trimmed.lowercased().hasPrefix("/graphrag ") {
            let query = String(trimmed.dropFirst("/graphrag ".count))
            composerText = ""
            Task { await runGraphRAG(query: query) }
            return
        }

        if trimmed.lowercased().hasPrefix("/send ") {
            let payload = String(trimmed.dropFirst(6)).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !payload.isEmpty else { return }
            composerText = ""
            composerDelivery = .zellijTab
            messages.append(
                WorkbenchMessage(
                    role: .operatorRole,
                    truth: .observed,
                    title: "You → zellij",
                    content: payload
                )
            )
            Task { await submitZellijSend(payload) }
            return
        }

        if trimmed.lowercased() == "/whereami" {
            composerText = ""
            Task { await runWhereAmI() }
            return
        }

        if trimmed.lowercased() == "/stop" || trimmed.lowercased() == "/cancel" {
            composerText = ""
            stopActiveMultimodelTurn()
            return
        }

        if trimmed.lowercased().hasPrefix("/handoff ") {
            let payload = String(trimmed.dropFirst(9)).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !payload.isEmpty else { return }
            composerText = ""
            Task {
                await sendHandoff(
                    subject: "Workbench handoff",
                    toClient: "beagle-native",
                    content: payload
                )
            }
            return
        }

        if trimmed.lowercased() == "/handoff-compile" || trimmed.lowercased().hasPrefix("/handoff-compile ") {
            composerText = ""
            Task { await compileSelectedHandoff() }
            return
        }

        messages.append(
            WorkbenchMessage(
                role: .operatorRole,
                truth: .observed,
                title: resolvedDelivery() == .multimodel ? "You" : "You → zellij",
                content: trimmed
            )
        )
        composerText = ""

        let delivery = resolvedDelivery()
        Task {
            if delivery == .multimodel {
                await submitMultimodelTurn(trimmed)
            } else {
                await submitZellijSend(trimmed)
            }
        }
    }

    func useStarter(_ text: String) {
        if text == "/exocortex" {
            composerText = "/exocortex "
            return
        }
        if text == "/graphrag" {
            composerText = "/graphrag "
            return
        }
        composerText = text
    }

    func agentName(for id: String?) -> String {
        guard let id, let agent = agents.first(where: { $0.id == id }) else { return "No agent" }
        return agent.displayName
    }

    func cycleComposerDelivery() {
        let all = ComposerDelivery.allCases
        guard let index = all.firstIndex(of: composerDelivery) else {
            composerDelivery = .auto
            return
        }
        composerDelivery = all[(index + 1) % all.count]
    }

    func toggleProviderSelection(_ providerId: String) {
        if selectedProviderIds.contains(providerId) {
            selectedProviderIds.remove(providerId)
        } else {
            selectedProviderIds.insert(providerId)
        }
    }

    func stopActiveMultimodelTurn() {
        let turnId = activeStreamingTurnId
        multimodelSocket?.stop(turnId: turnId)
        activeStreamingTurnId = nil
        streamingMessageKeys.removeAll()
        messages = messages.map { message in
            guard message.isStreaming else { return message }
            return WorkbenchMessage(
                id: message.id,
                role: message.role,
                agentID: message.agentID,
                agentKind: message.agentKind,
                truth: .stale,
                timestamp: message.timestamp,
                title: message.title,
                content: message.content.isEmpty ? "(stopped)" : message.content,
                isStreaming: false
            )
        }
        messages.append(
            WorkbenchMessage(
                role: .system,
                truth: .observed,
                title: "Stop",
                content: turnId.map { "Requested stop for turn \($0)." } ?? "Requested stop for active multimodel stream."
            )
        )
        terminalLines.append(
            WorkbenchTerminalLine(source: "multimodel-ws", truth: .observed, text: "WS stop → \(chatProjectSlug)")
        )
    }

    func refreshAgentSessions() async {
        let wire = await CockpitClient.shared.agentSessions(slug: selectedProjectID)
        agentSessions = wire.value?.sessions ?? []
        applyAgentSessionsOverlay()
    }

    func refreshZellijTransport() async {
        zellijStatusWire = await CockpitClient.shared.workspaceZellijStatus(slug: selectedProjectID)
    }

    func peekZellijScreen(for tab: String? = nil) async {
        let targetTab = tab ?? selectedAgent?.zellijTabName
        guard let targetTab, !targetTab.isEmpty else { return }
        isZellijScreenLoading = true
        defer { isZellijScreenLoading = false }

        let request = WorkspaceZellijScreenRequest(tab: targetTab, confirmed: true)
        let wire = await CockpitClient.shared.workspaceZellijScreen(slug: selectedProjectID, request: request)
        if let screen = wire.value?.screen, !screen.isEmpty {
            zellijScreenPreview = screen
            terminalLines.append(
                WorkbenchTerminalLine(
                    source: "zellij-screen",
                    truth: wire.mode,
                    text: "screen dump → \(selectedProjectID)/\(targetTab) (\(screen.count) chars)"
                )
            )
        } else {
            zellijScreenPreview = nil
            messages.append(
                WorkbenchMessage(
                    role: .system,
                    truth: .stale,
                    title: "Zellij screen",
                    content: wire.error ?? wire.value?.error ?? "No screen captured for tab \(targetTab)."
                )
            )
        }
    }

    var resolvedDeliveryLabel: String {
        resolvedDelivery().label
    }

    private func resolvedDelivery() -> ComposerDelivery {
        switch composerDelivery {
        case .multimodel, .zellijTab:
            return composerDelivery
        case .auto:
            if let tab = selectedAgent?.zellijTabName,
               workspace.expectedTabs.contains(tab) {
                return .zellijTab
            }
            return .multimodel
        }
    }

    func runWhereAmI() async {
        await refreshWorkspace(for: selectedProjectID)
        await applyAgentPresence()
        await refreshAgentSessions()
        await refreshZellijTransport()
        let tab = selectedAgent?.zellijTabName ?? "none"
        let delivery = resolvedDelivery()
        messages.append(
            WorkbenchMessage(
                role: .system,
                truth: workspace.source.truth,
                title: "/whereami",
                content: """
                project=\(selectedProjectID) · workspace=\(workspace.status) · session=\(workspace.sessionName)
                tab=\(tab) · delivery=\(delivery.label) · multimodel=\(chatProjectSlug)
                zellij transport=\(zellijStatusWire.value?.transport ?? "unknown") · agent pods=\(agentSessions.filter { $0.status == "running" }.count)
                tabs=\(workspace.expectedTabs.count) · transport=\(multimodelSocketConnected ? "websocket" : "http")
                """
            )
        )
        terminalLines.append(
            WorkbenchTerminalLine(
                source: "whereami",
                truth: workspace.source.truth,
                text: "\(selectedProjectID)/\(tab) · \(workspace.status)"
            )
        )
    }

    private func agentSessionKind(for tab: String) -> String? {
        let lower = tab.lowercased()
        if lower.hasPrefix("claude") { return "claude-code" }
        if lower.hasPrefix("codex") { return "codex" }
        return nil
    }

    func agentSessionKindForSelectedTab() -> String? {
        guard let tab = selectedAgent?.zellijTabName else { return nil }
        return agentSessionKind(for: tab)
    }

    func ensureAgentTerminalForSelectedTab() {
        guard let kind = agentSessionKindForSelectedTab() else {
            disconnectAgentTerminal()
            return
        }
        let running = agentSessions.contains {
            $0.kind == kind && ($0.status ?? "").lowercased() == "running"
        }
        guard running else {
            disconnectAgentTerminal()
            return
        }
        if agentTerminalKind != kind || !agentTerminalConnected {
            connectAgentTerminalForSelectedTab(force: false)
        }
    }

    func connectAgentTerminalForSelectedTab(force: Bool = false) {
        guard let kind = agentSessionKindForSelectedTab() else { return }
        if !force, agentTerminalKind == kind, agentTerminalConnected { return }
        connectAgentTerminal(kind: kind)
    }

    func connectAgentTerminal(kind: String) {
        agentTerminalSocket?.disconnect()
        let socket = AgentTerminalWebSocket()
        socket.delegate = self
        agentTerminalSocket = socket
        agentTerminalKind = kind
        agentTerminalText = ""
        agentTerminalPod = nil
        agentTerminalError = nil
        socket.connect(httpBase: cockpitEndpoint, slug: selectedProjectID, kind: kind)
        terminalLines.append(
            WorkbenchTerminalLine(
                source: "agent-pty",
                truth: .observed,
                text: "WS connect → \(selectedProjectID)/agent/\(kind)"
            )
        )
    }

    func disconnectAgentTerminal() {
        agentTerminalSocket?.disconnect()
        agentTerminalSocket = nil
        agentTerminalConnected = false
        agentTerminalKind = nil
    }

    func sendAgentTerminalLine(_ text: String) {
        let payload = text.hasSuffix("\n") ? text : "\(text)\n"
        agentTerminalSocket?.sendInput(payload)
        terminalLines.append(
            WorkbenchTerminalLine(source: "agent-pty", truth: .observed, text: "input → \(text.prefix(60))")
        )
    }

    func defaultHandoffDraft() -> String {
        let tab = selectedAgent?.zellijTabName ?? "none"
        return """
        project=\(selectedProjectID) tab=\(tab) workspace=\(workspace.status)
        delivery=\(composerDelivery.label) multimodel=\(chatProjectSlug)
        Next agent: continue from current lane with lease guard respected.
        """
    }

    func sendHandoff(subject: String, toClient: String, content: String) async {
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        isHandoffSending = true
        defer { isHandoffSending = false }

        let request = WorkbenchHandoffSendRequest(
            toClient: toClient,
            subject: subject,
            content: trimmed,
            priority: "normal",
            requiresResponse: true
        )
        let wire = await CockpitClient.shared.workbenchHandoffSend(slug: selectedProjectID, request: request)
        if wire.error == nil, wire.value?.messageId != nil || wire.value?.status != nil {
            messages.append(
                WorkbenchMessage(
                    role: .system,
                    truth: wire.mode,
                    title: "Handoff sent",
                    content: "→ \(toClient): \(subject)"
                )
            )
            await refreshHandoffs()
        } else {
            messages.append(
                WorkbenchMessage(
                    role: .system,
                    truth: .stale,
                    title: "Handoff failed",
                    content: wire.error ?? wire.value?.error ?? "send failed"
                )
            )
        }
    }

    func replyHandoff(text: String) async {
        guard let messageId = selectedHandoffID else { return }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        isHandoffSending = true
        defer { isHandoffSending = false }

        let wire = await CockpitClient.shared.workbenchHandoffReply(
            slug: selectedProjectID,
            messageId: messageId,
            request: WorkbenchHandoffReplyRequest(text: trimmed)
        )
        if wire.error == nil {
            messages.append(
                WorkbenchMessage(
                    role: .system,
                    truth: wire.mode,
                    title: "Handoff reply",
                    content: trimmed
                )
            )
            await refreshHandoffs()
        }
    }

    func claimSelectedHandoff() async {
        guard let messageId = selectedHandoffID else { return }
        _ = await CockpitClient.shared.workbenchHandoffClaim(slug: selectedProjectID, messageId: messageId)
        await refreshHandoffs()
    }

    func completeSelectedHandoff() async {
        guard let messageId = selectedHandoffID else { return }
        _ = await CockpitClient.shared.workbenchHandoffComplete(slug: selectedProjectID, messageId: messageId)
        await refreshHandoffs()
    }

    func compileSelectedHandoff(query: String? = nil) async {
        guard let messageId = selectedHandoffID else {
            messages.append(
                WorkbenchMessage(
                    role: .system,
                    truth: .declared,
                    title: "Handoff compile",
                    content: "Select a handoff on the board first."
                )
            )
            return
        }
        isHandoffCompileLoading = true
        defer { isHandoffCompileLoading = false }

        let request = WorkbenchHandoffCompileRequest(
            query: query,
            queryMode: "handoff",
            maxItems: 8,
            taskProfile: "handoff"
        )
        let wire = await CockpitClient.shared.workbenchHandoffCompile(
            slug: selectedProjectID,
            messageId: messageId,
            request: request
        )
        handoffCompileWire = wire

        if wire.error == nil, wire.value?.handoff?.messageId != nil {
            terminalLines.append(
                WorkbenchTerminalLine(
                    source: "handoff-compile",
                    truth: wire.mode,
                    text: "compiled \(messageId.prefix(48)) · \(wire.value?.graph?.nodeCount ?? 0) nodes"
                )
            )
        } else {
            messages.append(
                WorkbenchMessage(
                    role: .system,
                    truth: .stale,
                    title: "Handoff compile failed",
                    content: wire.error ?? "compile failed"
                )
            )
        }
    }

    func submitZellijSend(_ text: String) async {
        guard let tab = selectedAgent?.zellijTabName, !tab.isEmpty else {
            appendZellijFailure("No zellij tab selected.")
            return
        }
        let slug = selectedProjectID

        if let kind = agentSessionKind(for: tab) {
            let sessions = await CockpitClient.shared.agentSessions(slug: slug)
            let running = sessions.value?.sessions?.contains {
                $0.kind == kind && ($0.status ?? "").lowercased() == "running"
            } ?? false
            if running {
                let input = AgentSessionInputRequest(text: text, enter: true, confirmed: true)
                let result = await CockpitClient.shared.postAgentSessionInput(
                    slug: slug,
                    kind: kind,
                    request: input
                )
                if result.error == nil, result.value != nil {
                    messages.append(
                        WorkbenchMessage(
                            role: .system,
                            truth: result.mode,
                            title: "Agent PTY",
                            content: "Wrote to \(kind) pod for tab \(tab)."
                        )
                    )
                    terminalLines.append(
                        WorkbenchTerminalLine(
                            source: "agent-input",
                            truth: result.mode,
                            text: "POST agent/session/\(kind)/input → \(tab)"
                        )
                    )
                    return
                }
                appendZellijFailure(result.error ?? "agent input failed; trying habitat zellij")
            }
        }

        guard workspace.isLive else {
            appendZellijFailure("Workspace is not live; cannot write to zellij tab \(tab).")
            return
        }

        let request = WorkspaceZellijSendRequest(tab: tab, text: text, confirmed: true, enter: true)
        let result = await CockpitClient.shared.workspaceZellijSend(slug: slug, request: request)
        if result.value?.ok == true {
            messages.append(
                WorkbenchMessage(
                    role: .system,
                    truth: result.mode,
                    title: "Zellij",
                    content: "Sent to tab \(tab) (\(result.value?.transport ?? "workspace")) in session \(result.value?.sessionName ?? workspace.sessionName)."
                )
            )
            terminalLines.append(
                WorkbenchTerminalLine(
                    source: "zellij",
                    truth: result.mode,
                    text: "POST workspace/zellij/send → \(slug)/\(tab)"
                )
            )
        } else {
            appendZellijFailure(result.error ?? result.value?.error ?? "workspace zellij send failed")
        }
    }

    private func appendZellijFailure(_ message: String) {
        messages.append(
            WorkbenchMessage(
                role: .system,
                truth: .stale,
                title: "Zellij send failed",
                content: message
            )
        )
        terminalLines.append(
            WorkbenchTerminalLine(source: "zellij", truth: .stale, text: message)
        )
    }

    private func submitMultimodelTurn(_ text: String) async {
        let providers = selectedMultimodelProviderIds()

        if multimodelSocketConnected {
            multimodelSocket?.sendChat(message: text, providers: providers)
            terminalLines.append(
                WorkbenchTerminalLine(
                    source: "multimodel-ws",
                    truth: .observed,
                    text: "WS chat → \(chatProjectSlug) [\(providers.joined(separator: ","))]: \(text.prefix(80))"
                )
            )
            return
        }

        let providerId = providers.first ?? providerIdForSelectedAgent()
        let request = AgentTerminalTurnRequest(
            message: text,
            status: "waiting",
            kind: "beagle-native",
            providerId: providerId,
            label: selectedAgent?.displayName ?? "beagle-native"
        )
        let result = await CockpitClient.shared.postAgentTerminalTurn(slug: chatProjectSlug, request: request)

        if let turn = result.value?.turn {
            messages.append(
                WorkbenchMessage(
                    role: .system,
                    agentKind: .beagle,
                    truth: .observed,
                    title: "Turn recorded",
                    content: "Persisted turn \(turn.turnId ?? "?") on \(chatProjectSlug) via agent-terminal."
                )
            )
        } else {
            messages.append(
                WorkbenchMessage(
                    role: .system,
                    truth: .stale,
                    title: "Send failed",
                    content: result.error ?? "agent-terminal POST failed"
                )
            )
        }

        terminalLines.append(
            WorkbenchTerminalLine(
                source: "multimodel",
                truth: result.mode,
                text: "POST agent-terminal → \(chatProjectSlug): \(text.prefix(80))"
            )
        )

        await refreshMultimodel()
    }

    private func selectedMultimodelProviderIds() -> [String] {
        let available = Set(availableProviderIds)
        if !selectedProviderIds.isEmpty {
            let picked = selectedProviderIds.filter { available.contains($0) }
            if !picked.isEmpty { return Array(picked) }
        }

        let selected = providerIdForSelectedAgent()
        if available.contains(selected) {
            return [selected]
        }
        let defaults = multimodelSocket?.defaultProviderIds.filter { available.contains($0) } ?? []
        if !defaults.isEmpty { return defaults }
        let fallback = multimodelProviders
            .filter { ($0.status ?? "").lowercased() == "available" }
            .prefix(3)
            .map { $0.providerId ?? $0.rawId ?? $0.id }
        if !fallback.isEmpty { return Array(fallback) }
        return [selected]
    }

    private func requiresLeaseConfirmation(_ text: String) -> Bool {
        let lower = text.lowercased()
        let risky = ["patch", "commit", "merge", "push", "deploy", "delete", "reset", "force push", "git push"]
        return risky.contains { lower.contains($0) }
    }

    private func providerIdForSelectedAgent() -> String {
        guard let agent = selectedAgent else { return "beagle-native" }
        if agent.kind == .codex { return "codex" }
        if agent.kind == .claude { return "claude" }
        if agent.kind == .kimi { return "kimi" }
        if agent.kind == .grok { return "grok" }
        return "beagle-native"
    }

    private func configureCockpitClient() async {
        let trimmed = cockpitEndpoint.trimmingCharacters(in: .whitespacesAndNewlines)
        let base = trimmed.hasSuffix("/") ? String(trimmed.dropLast()) : trimmed
        guard let url = URL(string: base) else { return }
        await CockpitClient.shared.configure(baseURLs: [url])
    }

    private func refreshCatalog() async {
        let catalog = await CockpitClient.shared.catalog()
        catalogWire = catalog
        catalogTruth = catalog.mode

        if let error = catalog.error, catalog.value == nil {
            lastError = error
            projects = []
            return
        }

        projects = (catalog.value?.projects ?? []).map(mapProject).sorted { $0.id < $1.id }
        if !projects.contains(where: { $0.id == selectedProjectID }), let first = projects.first {
            selectedProjectID = first.id
        }
    }

    private func applyWorkspaceBindings() {
        lanes = [
            WorkbenchLane(
                id: "workspace",
                title: "Workspace",
                purpose: workspace.summary,
                leaseState: .clear,
                ownerAgentID: nil,
                touchedFiles: []
            )
        ]
        selectedLaneID = "workspace"

        agents = workspace.expectedTabs.map { tab in
            WorkbenchAgent(
                id: "\(workspace.projectSlug)-\(tab)",
                kind: agentKind(for: tab),
                displayName: tab,
                laneID: "workspace",
                status: .idle,
                activity: 0,
                currentTask: "Tab from Cockpit.",
                zellijTabName: tab
            )
        }

        if selectedAgentID.isEmpty || !agents.contains(where: { $0.id == selectedAgentID }) {
            selectedAgentID = agents.first(where: { $0.zellijTabName == "repo" })?.id ?? agents.first?.id ?? ""
        }

        filePreviews = []
        selectedFileID = ""

        terminalLines = [
            WorkbenchTerminalLine(
                source: "cockpit",
                truth: workspace.source.truth,
                text: "GET /api/projects/\(workspace.projectSlug)/go-work-now"
            ),
            WorkbenchTerminalLine(
                source: "workspace",
                truth: workspace.source.truth,
                text: "status=\(workspace.status) session=\(workspace.sessionName) tabs=\(workspace.expectedTabs.count)"
            )
        ]
        if let error = workspace.error {
            terminalLines.append(WorkbenchTerminalLine(source: "error", truth: .stale, text: error))
        }
    }

    func applyAgentPresence() async {
        let active = await CockpitClient.shared.multimodelActiveTurns(slug: chatProjectSlug)
        let runningProviders = Set((active.value?.turns ?? []).flatMap { turn in
            (turn.responses ?? []).compactMap(\.provider)
        })

        agents = agents.map { agent in
            var copy = agent
            let tab = agent.zellijTabName.lowercased()
            if runningProviders.contains(where: { tab.contains($0.lowercased()) || $0.lowercased().contains(tab) }) {
                copy.status = .running
                copy.activity = 0.7
                copy.currentTask = "Active multimodel turn"
            } else if active.value?.turns?.isEmpty != false {
                copy.status = .idle
                copy.currentTask = "Tab from Cockpit."
            }
            return copy
        }
        applyAgentSessionsOverlay()
    }

    private func applyAgentSessionsOverlay() {
        let runningKinds = Set(
            agentSessions
                .filter { ($0.status ?? "").lowercased() == "running" }
                .compactMap(\.kind)
        )
        guard !runningKinds.isEmpty else { return }

        agents = agents.map { agent in
            var copy = agent
            guard let kind = agentSessionKind(for: agent.zellijTabName), runningKinds.contains(kind) else {
                return copy
            }
            copy.status = .running
            copy.activity = max(copy.activity, 0.85)
            copy.currentTask = "Agent pod live (\(kind))"
            return copy
        }
    }

    func applyTurnsToMessages(_ payload: MultimodelTurnsResponse?) {
        guard let payload else { return }
        let turns = payload.turns ?? []
        let mapped: [WorkbenchMessage] = turns.prefix(20).flatMap { turn -> [WorkbenchMessage] in
            var items: [WorkbenchMessage] = []
            if let message = turn.message, !message.isEmpty {
                items.append(
                    WorkbenchMessage(
                        role: .operatorRole,
                        truth: truthFrom(turn.truthMode),
                        title: "Turn",
                        content: message
                    )
                )
            }
            for response in turn.responses ?? [] {
                let text = response.text ?? response.error ?? ""
                guard !text.isEmpty else { continue }
                items.append(
                    WorkbenchMessage(
                        role: .agent,
                        agentKind: agentKind(for: response.provider ?? "beagle"),
                        truth: truthFrom(turn.truthMode),
                        title: response.label ?? response.provider ?? "agent",
                        content: text
                    )
                )
            }
            return items
        }
        if !mapped.isEmpty {
            messages = mapped
        }
    }

    private func truthFrom(_ raw: String?) -> TruthMode {
        TruthMode(rawValue: raw ?? "") ?? .observed
    }

    private func appendBootstrapMessageIfNeeded() {
        messages.removeAll { $0.title?.hasPrefix("Beagle reset") == true || $0.title == "Beagle live" }
        if let error = lastError, !isLive {
            messages.insert(
                WorkbenchMessage(
                    role: .system,
                    truth: .stale,
                    title: "Beagle live",
                    content: "Cockpit unreachable at \(cockpitEndpoint). \(error)"
                ),
                at: 0
            )
            return
        }
        messages.insert(
            WorkbenchMessage(
                role: .system,
                truth: catalogTruth,
                title: "Beagle live",
                content: """
                Projects: \(projects.count) · workspace \(workspace.projectSlug) (\(workspace.status))
                Multimodel chat slug: \(chatProjectSlug) · transport: \(multimodelSocketConnected ? "websocket" : "http") · turns: \(multimodelWire.value?.count ?? 0)
                """
            ),
            at: 0
        )
    }

    private func mapProject(_ project: Project) -> WorkbenchProject {
        WorkbenchProject(
            id: project.projectSlug,
            title: displayTitle(for: project.projectSlug),
            subtitle: project.workspaceRoot ?? project.repoUrl ?? "no workspace root declared",
            posture: project.posture,
            branch: project.branch ?? "branch unknown",
            workspaceCommand: "dev \(project.projectSlug)"
        )
    }

    private func displayTitle(for slug: String) -> String {
        switch slug {
        case "sounio": return "Sounio Language"
        case "darwin-mfc": return "Darwin-MFC"
        case "beagle": return "Beagle Platform"
        default:
            return slug.split(separator: "-").map { $0.prefix(1).uppercased() + $0.dropFirst() }.joined(separator: " ")
        }
    }

    func agentKind(for tab: String) -> WorkbenchAgentKind {
        let lower = tab.lowercased()
        if lower.hasPrefix("claude") { return .claude }
        if lower.hasPrefix("codex") { return .codex }
        if lower.hasPrefix("kimi") { return .kimi }
        if lower.hasPrefix("grok") { return .grok }
        if lower == "repo" || lower == "beagle" { return .beagle }
        return .beagle
    }
}

extension WorkbenchStore: MultimodelChatWebSocketDelegate {
    func multimodelChatWebSocket(_ socket: MultimodelChatWebSocket, connectionChanged connected: Bool, error: String?) {
        multimodelSocketConnected = connected
        multimodelSocketError = error
        if connected {
            terminalLines.append(
                WorkbenchTerminalLine(
                    source: "multimodel-ws",
                    truth: .observed,
                    text: "WS connected → \(chatProjectSlug)/multimodel-chat"
                )
            )
        } else if let error {
            terminalLines.append(
                WorkbenchTerminalLine(
                    source: "multimodel-ws",
                    truth: .stale,
                    text: "WS disconnected: \(error)"
                )
            )
        }
    }

    func multimodelChatWebSocket(_ socket: MultimodelChatWebSocket, didReceive event: MultimodelChatEvent) {
        switch event.type {
        case "ready":
            if let providers = event.providers, !providers.isEmpty {
                multimodelProviders = providers
            }

        case "turn_started", "turn_snapshot":
            if let turnId = event.turnId {
                activeStreamingTurnId = turnId
            }

        case "provider_started":
            upsertStreamingMessage(for: event, content: "", streaming: true)

        case "delta":
            appendStreamingDelta(for: event)

        case "provider_done":
            finalizeStreamingMessage(for: event, fallbackError: nil)

        case "provider_error", "provider_unavailable":
            finalizeStreamingMessage(
                for: event,
                fallbackError: event.error ?? event.reason ?? event.type
            )

        case "turn_done", "turn_stopped":
            activeStreamingTurnId = nil
            streamingMessageKeys.removeAll()
            Task { await refreshMultimodelHistoryOnly() }

        case "error":
            messages.append(
                WorkbenchMessage(
                    role: .system,
                    truth: .stale,
                    title: "Multimodel WS",
                    content: event.error ?? event.reason ?? "websocket error"
                )
            )

        default:
            break
        }
    }

    private func refreshMultimodelHistoryOnly() async {
        let turns = await CockpitClient.shared.multimodelTurns(slug: chatProjectSlug)
        multimodelWire = turns
        if turns.value != nil, !multimodelSocketConnected || streamingMessageKeys.isEmpty {
            applyTurnsToMessages(turns.value)
        }
        await applyAgentPresence()
    }

    private func upsertStreamingMessage(for event: MultimodelChatEvent, content: String, streaming: Bool) {
        let key = event.streamKey
        let providerName = event.label ?? event.provider ?? "agent"
        if let existingID = streamingMessageKeys[key],
           let index = messages.firstIndex(where: { $0.id == existingID }) {
            let existing = messages[index]
            messages[index] = WorkbenchMessage(
                id: existing.id,
                role: .agent,
                agentKind: agentKind(for: event.provider ?? providerName),
                truth: .observed,
                timestamp: existing.timestamp,
                title: providerName,
                content: content,
                isStreaming: streaming
            )
            return
        }

        let message = WorkbenchMessage(
            role: .agent,
            agentKind: agentKind(for: event.provider ?? providerName),
            truth: .observed,
            title: providerName,
            content: content,
            isStreaming: streaming
        )
        streamingMessageKeys[key] = message.id
        messages.append(message)
    }

    private func appendStreamingDelta(for event: MultimodelChatEvent) {
        guard let chunk = event.text, !chunk.isEmpty else { return }
        let key = event.streamKey
        if let existingID = streamingMessageKeys[key],
           let index = messages.firstIndex(where: { $0.id == existingID }) {
            let existing = messages[index]
            messages[index] = WorkbenchMessage(
                id: existing.id,
                role: existing.role,
                agentKind: existing.agentKind,
                truth: existing.truth,
                timestamp: existing.timestamp,
                title: existing.title,
                content: existing.content + chunk,
                isStreaming: true
            )
        } else {
            upsertStreamingMessage(for: event, content: chunk, streaming: true)
        }
    }

    private func finalizeStreamingMessage(for event: MultimodelChatEvent, fallbackError: String?) {
        let key = event.streamKey
        let providerName = event.label ?? event.provider ?? "agent"
        let finalText = event.text ?? fallbackError ?? ""
        guard !finalText.isEmpty else {
            if let existingID = streamingMessageKeys[key],
               let index = messages.firstIndex(where: { $0.id == existingID }) {
                let existing = messages[index]
                messages[index] = WorkbenchMessage(
                    id: existing.id,
                    role: existing.role,
                    agentKind: existing.agentKind,
                    truth: fallbackError == nil ? .observed : .stale,
                    timestamp: existing.timestamp,
                    title: existing.title,
                    content: existing.content.isEmpty ? (fallbackError ?? "done") : existing.content,
                    isStreaming: false
                )
            }
            streamingMessageKeys.removeValue(forKey: key)
            return
        }

        if let existingID = streamingMessageKeys[key],
           let index = messages.firstIndex(where: { $0.id == existingID }) {
            let existing = messages[index]
            let merged = existing.content.isEmpty ? finalText : existing.content
            messages[index] = WorkbenchMessage(
                id: existing.id,
                role: .agent,
                agentKind: agentKind(for: event.provider ?? providerName),
                truth: fallbackError == nil ? .observed : .stale,
                timestamp: existing.timestamp,
                title: providerName,
                content: merged,
                isStreaming: false
            )
        } else {
            upsertStreamingMessage(for: event, content: finalText, streaming: false)
        }
        streamingMessageKeys.removeValue(forKey: key)
    }
}

extension WorkbenchStore: AgentTerminalWebSocketDelegate {
    func agentTerminalWebSocket(_ socket: AgentTerminalWebSocket, connectionChanged connected: Bool, error: String?) {
        agentTerminalConnected = connected
        agentTerminalError = error
        if connected {
            socket.resize(cols: 120, rows: 36)
        } else if let error {
            terminalLines.append(
                WorkbenchTerminalLine(source: "agent-pty", truth: .stale, text: "WS disconnected: \(error)")
            )
        }
    }

    func agentTerminalWebSocket(_ socket: AgentTerminalWebSocket, receivedOutput chunk: String, snapshotReplace: Bool) {
        if snapshotReplace {
            agentTerminalText = AgentTerminalFormatting.cap(chunk)
        } else {
            agentTerminalText = AgentTerminalFormatting.cap(agentTerminalText + chunk)
        }
    }

    func agentTerminalWebSocket(_ socket: AgentTerminalWebSocket, ready info: AgentTerminalReadyInfo) {
        agentTerminalKind = info.kind
        agentTerminalPod = info.pod
    }
}

#if DEBUG
extension WorkbenchStore {
    static func preview() -> WorkbenchStore {
        let store = WorkbenchStore()
        store.projects = [
            WorkbenchProject(
                id: "sounio",
                title: "Sounio Language",
                subtitle: "Preview only",
                posture: .alwaysOn,
                branch: "integration/sounio-dev-ready-base",
                workspaceCommand: "dev sounio"
            )
        ]
        return store
    }
}
#endif
