//
//  AgentSessionView.swift
//  BeagleCockpit
//
//  Persistent agent session UI with live WebSocket terminal streaming.
//  Supports multiple agent types — Claude Code, Codex, local agents,
//  custom Beagle agents. All share the same pod/PVC/WebSocket pattern.
//
//  Session state survives app close + device switching — the actual
//  agent runs in a K8s pod with persistent volume.
//

import SwiftUI
import BeagleCore

/// Agent type — extensible registry of persistent agent kinds.
public enum AgentKind: String, CaseIterable, Identifiable, Sendable {
    case claudeCode = "claude-code"
    case codex
    case localSGLang = "local-sglang"
    case custom

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .claudeCode:  return "Claude Code"
        case .codex:       return "Codex"
        case .localSGLang: return "Local SGLang"
        case .custom:      return "Custom Agent"
        }
    }

    public var iconSystemName: String {
        switch self {
        case .claudeCode:  return "sparkles"
        case .codex:       return "curlybraces"
        case .localSGLang: return "cpu"
        case .custom:      return "gear"
        }
    }

    public var description: String {
        switch self {
        case .claudeCode:
            return "Anthropic Claude Code in a persistent pod. Full tool use + MCP."
        case .codex:
            return "OpenAI Codex agent in a persistent pod."
        case .localSGLang:
            return "Local model via SGLang. Fast, no external API cost."
        case .custom:
            return "Custom Beagle agent from beagle-agents crate."
        }
    }
}

struct AgentSessionView: View {
    @Environment(CatalogStore.self) private var catalog
    @Environment(CognitiveStore.self) private var cognitive
    private let initialSlug: String
    @AppStorage("lastAgentKind") private var lastAgentKindRaw: String = AgentKind.claudeCode.rawValue
    @AppStorage("lastAgentObjective") private var lastAgentObjective = ""
    @AppStorage("lastAgentObjectiveProjectSlug") private var lastAgentObjectiveProjectSlug = ""
    @AppStorage("pinnedLaneQuestionsJSON") private var pinnedLaneQuestionsJSON = "{}"
    @State private var selectedKind: AgentKind = .claudeCode
    @State private var sessionState: AgentSessionState = .idle
    @State private var terminal = TerminalStore()
    @State private var inputText: String = ""
    @FocusState private var inputFocused: Bool
    @State private var scratchpadEntries: [ScratchpadEntry] = []
    @State private var laneSessions: [AgentSession] = []
    @State private var laneOverview: Truthful<MobileProjectOverview>?
    @State private var currentSlug: String

    init(slug: String) {
        self.initialSlug = slug
        _currentSlug = State(initialValue: slug)
    }

    enum AgentSessionState: Equatable {
        case idle
        case pending(message: String)
        case running(podName: String)
        case paused
        case error(String)

        var isRunning: Bool {
            if case .running = self { return true }
            return false
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            projectPicker
            laneOverviewCard
            companionPresenceCard
            agentPicker
            if !scratchpadEntries.isEmpty {
                scratchpadStrip
            }
            sessionControls
            TerminalContentView(
                terminal: terminal,
                onReconnect: {
                    Task { await reconnectTerminal() }
                },
                diagnosticsText: terminalDiagnosticsText,
                sessionIdentityText: terminalSessionIdentityText
            )
            if sessionState.isRunning {
                inputBar
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .background { AgentSessionGradient(sessionState: sessionState, connectionState: terminal.connectionState) }
        .navigationTitle("Work \u{00B7} \(currentSlug)")
        .sensoryFeedback(.success, trigger: sessionState.isRunning)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                NavigationLink(value: catalog.projects.first(where: { $0.projectSlug == currentSlug }) ?? catalog.primaryProject) {
                    Label("Command", systemImage: "server.rack")
                        .font(.system(size: 14))
                        .foregroundStyle(BeagleTheme.textSecondary)
                }
            }
        }
        .onChange(of: sessionState) {
            if sessionState.isRunning {
                inputFocused = true
            }
        }
        .onChange(of: cognitive.activeProjectSlug) { _, newValue in
            guard let newValue, newValue != currentSlug else { return }
            switchProject(to: newValue)
        }
        .onAppear {
            terminal.onActivityUpdate = { status, tokens, snippet in
                LiveActivityManager.shared.updateAgentActivity(status: status, tokens: tokens, snippet: snippet)
            }
            // Restore last used agent kind
            if let kind = AgentKind(rawValue: lastAgentKindRaw) {
                selectedKind = kind
            }
            let preferredSlug = cognitive.activeProjectSlug ?? initialSlug
            if preferredSlug != currentSlug {
                currentSlug = preferredSlug
            }
        }
        .task(id: currentSlug) {
            laneOverview = await CockpitClient.shared.projectOverview(slug: currentSlug)
            // Restore visible state from the cluster on launch.
            if currentSlug == (cognitive.activeProjectSlug ?? currentSlug) || cognitive.activeProjectSlug == nil {
                cognitive.activeProjectSlug = currentSlug
            }
            if sessionState == .idle || !terminal.connectionState.isConnected {
                if let existing = await restoreExistingSession() {
                    if let kind = AgentKind(rawValue: existing.kind ?? "") {
                        selectedKind = kind
                        lastAgentKindRaw = kind.rawValue
                    }
                    applyRestoredSession(existing)
                }
            }
            // Load scratchpad
            await refreshScratchpad()
            await refreshLaneSessions()
            persistShellObjective()
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: BeagleSpacing.sm) {
            Image(systemName: selectedKind.iconSystemName)
                .font(.system(size: 20))
                .foregroundStyle(BeagleTheme.truthObserved)
                .symbolEffect(.pulse, isActive: terminal.connectionState.isConnected)

            VStack(alignment: .leading, spacing: 2) {
                Text(selectedKind.displayName)
                    .font(BeagleFont.title3.font)
                    .foregroundStyle(BeagleTheme.textPrimary)
                connectionStatus
            }

            Spacer()

            TruthBadge(terminal.truthMode)
        }
        .padding(.horizontal, BeagleSpacing.lg)
        .padding(.vertical, BeagleSpacing.md)
        .background(.ultraThinMaterial)
    }

    private var projectPicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: BeagleSpacing.xs) {
                ForEach(projectOptions) { project in
                    Button {
                        switchProject(to: project.projectSlug)
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            HStack(spacing: BeagleSpacing.xxs) {
                                Text(projectDisplayName(project.projectSlug))
                                    .font(BeagleFont.footnote.font)
                                    .fontWeight(.semibold)
                                    .foregroundStyle(project.projectSlug == currentSlug ? BeagleTheme.textPrimary : BeagleTheme.textSecondary)
                                if project.projectSlug == currentSlug {
                                    PresencePill(label: "active", systemImage: "scope", tint: BeagleTheme.truthObserved)
                                }
                            }

                            Text(project.branch ?? project.preferredPrBase ?? "branch not declared")
                                .font(BeagleFont.caption2.font)
                                .foregroundStyle(BeagleTheme.textTertiary)
                                .lineLimit(1)

                            HStack(spacing: BeagleSpacing.xxs) {
                                Image(systemName: project.workspacePod == nil ? "moon.zzz.fill" : "shippingbox.fill")
                                    .font(.system(size: 10))
                                Text(project.workspacePod ?? "habitat parked")
                                    .font(BeagleFont.caption2.font)
                                    .lineLimit(1)
                            }
                            .foregroundStyle(project.projectSlug == currentSlug ? BeagleTheme.truthObserved.opacity(0.9) : BeagleTheme.textTertiary)
                        }
                        .frame(width: 196, alignment: .leading)
                        .padding(.horizontal, BeagleSpacing.md)
                        .padding(.vertical, BeagleSpacing.sm)
                        .background(
                            RoundedRectangle(cornerRadius: BeagleRadius.lg)
                                .fill(project.projectSlug == currentSlug ? BeagleTheme.truthObserved.opacity(0.09) : BeagleTheme.surface1.opacity(0.62))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: BeagleRadius.lg)
                                .strokeBorder(project.projectSlug == currentSlug ? BeagleTheme.truthObserved.opacity(0.24) : Color.white.opacity(0.06), lineWidth: 1)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, BeagleSpacing.lg)
            .padding(.top, BeagleSpacing.sm)
        }
    }

    private var companionPresenceCard: some View {
        PresenceFieldCard(
            state: companionPresenceState,
            eyebrow: "Live Companion",
            title: companionHeadline,
            body: companionBody,
            detail: companionDetail,
            truth: companionTruth
        ) {
            HStack(spacing: BeagleSpacing.xs) {
                PresencePill(
                    label: selectedKind.displayName,
                    systemImage: selectedKind.iconSystemName,
                    tint: companionTint
                )
                if case .running(let podName) = sessionState {
                    PresencePill(
                        label: podName,
                        systemImage: "shippingbox",
                        tint: BeagleTheme.truthRemembered
                    )
                }
            }
        }
        .padding(.horizontal, BeagleSpacing.lg)
        .padding(.top, BeagleSpacing.sm)
        .padding(.bottom, BeagleSpacing.xs)
    }

    private var laneOverviewCard: some View {
        PresenceFieldCard(
            state: .attentive,
            eyebrow: "Project Lane",
            title: laneOverviewTitle,
            body: laneOverviewBody,
            detail: laneOverviewDetail,
            truth: laneOverviewTruth
        ) {
            VStack(alignment: .leading, spacing: BeagleSpacing.sm) {
                ForEach(laneAgentStatuses) { status in
                    Button {
                        guard sessionState == .idle else { return }
                        selectedKind = status.kind
                        lastAgentKindRaw = status.kind.rawValue
                    } label: {
                        HStack(alignment: .top, spacing: BeagleSpacing.sm) {
                            PresencePill(
                                label: status.kind.displayName,
                                systemImage: status.kind.iconSystemName,
                                tint: laneStatusTint(status)
                            )

                            VStack(alignment: .leading, spacing: 3) {
                                Text(laneStatusActivity(status))
                                    .font(BeagleFont.footnote.font)
                                    .foregroundStyle(BeagleTheme.textPrimary)
                                    .multilineTextAlignment(.leading)
                                    .lineLimit(2)

                                Text(laneStatusDetail(status))
                                    .font(BeagleFont.caption2.font)
                                    .foregroundStyle(BeagleTheme.textTertiary)
                                    .lineLimit(1)
                            }

                            Spacer(minLength: BeagleSpacing.sm)

                            PresencePill(
                                label: laneStatusSelectionLabel(status),
                                systemImage: laneStatusSelectionIcon(status),
                                tint: laneStatusSelectionTint(status)
                            )
                        }
                        .padding(.horizontal, BeagleSpacing.sm)
                        .padding(.vertical, BeagleSpacing.sm)
                        .background(
                            RoundedRectangle(cornerRadius: BeagleRadius.md)
                                .fill(selectedKind == status.kind ? BeagleTheme.truthObserved.opacity(0.08) : BeagleTheme.surface0.opacity(0.34))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: BeagleRadius.md)
                                .strokeBorder(selectedKind == status.kind ? BeagleTheme.truthObserved.opacity(0.22) : Color.white.opacity(0.05), lineWidth: 1)
                        )
                    }
                    .buttonStyle(.plain)
                    .disabled(sessionState != .idle)
                }
            }
        }
        .padding(.horizontal, BeagleSpacing.lg)
        .padding(.top, BeagleSpacing.sm)
        .padding(.bottom, BeagleSpacing.xs)
    }

    private var connectionStatus: some View {
        HStack(spacing: BeagleSpacing.xxs) {
            connectionIcon
            connectionText
        }
        .font(BeagleFont.data.font)
    }

    @ViewBuilder
    private var connectionIcon: some View {
        switch sessionState {
        case .idle:
            Image(systemName: "circle.dashed")
                .foregroundStyle(BeagleTheme.textTertiary)
        case .pending:
            Image(systemName: "circle.dotted")
                .foregroundStyle(BeagleTheme.postureWarm)
                .symbolEffect(.variableColor)
        case .running:
            switch terminal.connectionState {
            case .connected:
                Image(systemName: "circle.fill")
                    .foregroundStyle(BeagleTheme.truthObserved)
                    .symbolEffect(.pulse)
            case .connecting:
                Image(systemName: "circle.dotted")
                    .foregroundStyle(BeagleTheme.postureWarm)
                    .symbolEffect(.variableColor)
            case .reconnecting:
                Image(systemName: "arrow.clockwise")
                    .foregroundStyle(BeagleTheme.postureWarm)
            case .failed:
                Image(systemName: "xmark.circle")
                    .foregroundStyle(BeagleTheme.stateError)
            case .disconnected:
                Image(systemName: "circle")
                    .foregroundStyle(BeagleTheme.textTertiary)
            }
        case .paused:
            Image(systemName: "pause.circle")
                .foregroundStyle(BeagleTheme.postureWarm)
        case .error:
            Image(systemName: "xmark.circle")
                .foregroundStyle(BeagleTheme.stateError)
        }
    }

    @ViewBuilder
    private var connectionText: some View {
        switch sessionState {
        case .idle:
            Text("no active session").foregroundStyle(BeagleTheme.textTertiary)
        case .pending(let message):
            Text(message).foregroundStyle(BeagleTheme.postureWarm)
        case .running(let pod):
            switch terminal.connectionState {
            case .connected(let source):
                Text("live \u{00B7} \(pod) via \(source)").foregroundStyle(BeagleTheme.truthObserved)
            case .connecting:
                Text("connecting...").foregroundStyle(BeagleTheme.postureWarm)
            case .reconnecting(let n):
                Text("reconnecting (\(n))...").foregroundStyle(BeagleTheme.postureWarm)
            case .failed(let err):
                Text(err).foregroundStyle(BeagleTheme.stateError)
            case .disconnected:
                Text("running \u{00B7} \(pod)").foregroundStyle(BeagleTheme.textSecondary)
            }
        case .paused:
            Text("paused (state preserved)").foregroundStyle(BeagleTheme.postureWarm)
        case .error(let msg):
            Text(msg).foregroundStyle(BeagleTheme.stateError)
        }
    }

    // MARK: - Agent picker

    private var agentPicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: BeagleSpacing.xs) {
                ForEach(AgentKind.allCases) { kind in
                    Button {
                        guard sessionState == .idle else { return }
                        withAnimation(BeagleMotion.snappy) {
                            selectedKind = kind
                            lastAgentKindRaw = kind.rawValue
                        }
                    } label: {
                        Label(kind.displayName, systemImage: kind.iconSystemName)
                            .font(BeagleFont.footnote.font)
                            .padding(.horizontal, BeagleSpacing.md)
                            .padding(.vertical, BeagleSpacing.xs + 2)
                            .frame(minHeight: 44)
                            .foregroundStyle(
                                selectedKind == kind ? BeagleTheme.truthObserved : BeagleTheme.textSecondary
                            )
                            .background(
                                Capsule().fill(
                                    selectedKind == kind
                                    ? BeagleTheme.truthObserved.opacity(0.12)
                                    : Color.white.opacity(0.04)
                                )
                            )
                            .overlay(
                                Capsule().strokeBorder(
                                    selectedKind == kind
                                    ? BeagleTheme.truthObserved.opacity(0.25)
                                    : Color.white.opacity(0.08),
                                    lineWidth: 1
                                )
                            )
                    }
                    .buttonStyle(.plain)
                    .disabled(sessionState != .idle)
                    .sensoryFeedback(.selection, trigger: selectedKind)
                }
            }
            .padding(.horizontal, BeagleSpacing.lg)
            .padding(.vertical, BeagleSpacing.sm)
        }
    }

    // MARK: - Session controls

    private var sessionControls: some View {
        HStack(spacing: BeagleSpacing.sm) {
            switch sessionState {
            case .idle:
                Button {
                    Task { await spawnSession() }
                } label: {
                    Label("Connect", systemImage: "play.fill")
                }
                .buttonStyle(PrimaryButton())

            case .running:
                Button {
                    Task { await pauseSession() }
                } label: {
                    Label("Pause", systemImage: "pause.fill")
                }
                .buttonStyle(SecondaryButton(color: BeagleTheme.postureWarm))

                Button {
                    Task { await stopSession() }
                } label: {
                    Label("Stop", systemImage: "stop.fill")
                }
                .buttonStyle(SecondaryButton(color: BeagleTheme.stateError))

            case .paused:
                Button {
                    Task { await spawnSession() }
                } label: {
                    Label("Resume", systemImage: "play.fill")
                }
                .buttonStyle(PrimaryButton())

            case .pending(let message):
                SpawningIndicator(agentKind: selectedKind, messageOverride: message)

            case .error:
                Button {
                    Task { await spawnSession() }
                } label: {
                    Label("Retry", systemImage: "arrow.clockwise")
                }
                .buttonStyle(PrimaryButton(color: BeagleTheme.stateError))
            }

            Spacer()
        }
        .padding(.horizontal, BeagleSpacing.lg)
        .padding(.vertical, BeagleSpacing.sm)
    }

    // MARK: - Input bar

    private var inputBar: some View {
        BeagleInputBar(
            text: $inputText,
            placeholder: "command...",
            mode: .terminal,
            isEnabled: sessionState.isRunning,
            onSubmit: { cmd in
                terminal.sendInput(cmd + "\n")
            },
            onSpecialKey: { key in
                terminal.sendInput(key.escapeSequence)
            }
        )
    }

    // MARK: - Actions

    /// Connect to (or deploy) an agent session.
    ///
    /// Flow:
    ///  1. Fetch sessions list from cockpit
    ///  2a. Session running → connect WebSocket immediately
    ///  2b. Session exists but paused → resume it, then poll until ready
    ///  2c. No session → deploy via startAgentSession, then poll until ready
    ///  3. Error reaching cockpit → show actionable message
    private func spawnSession() async {
        sessionState = .pending(message: "Checking session state...")

        // Fetch real sessions from cockpit
        let result = await CockpitClient.shared.agentSessions(slug: currentSlug)

        guard result.mode == .observed, let sessions = result.value?.sessions else {
            let err = result.error ?? "no response"
            sessionState = .error("Cockpit unreachable: \(err). Check public gateway or Tailscale connectivity.")
            return
        }

        laneSessions = sessions

        let existing = sessions.first(where: { $0.kind == selectedKind.rawValue })

        if let existing {
            switch existing.phase {
            case .running:
                connectToSession(existing)
                return
            case .paused:
                sessionState = .pending(message: "Resuming \(selectedKind.displayName)...")
                let resumed = await CockpitClient.shared.resumeAgentSession(slug: currentSlug, kind: selectedKind.rawValue)
                if resumed.mode != .observed {
                    sessionState = .error("Could not resume session: \(resumed.error ?? "unknown")")
                    return
                }
            case .pending:
                sessionState = .pending(message: pendingMessage(for: existing, fallback: "Session pending..."))
            }
        } else {
            sessionState = .pending(message: "Starting \(selectedKind.displayName)...")
            let started = await CockpitClient.shared.startAgentSession(slug: currentSlug, kind: selectedKind.rawValue)
            if started.mode != .observed {
                sessionState = .error("Could not start session: \(started.error ?? "unknown")")
                return
            }
        }

        // Poll until the pod becomes ready (up to 120s)
        await pollUntilReady()
    }

    /// Poll `/api/projects/:slug/agent/session/:kind` until readyReplicas > 0 or timeout.
    private func pollUntilReady() async {
        let maxWait = 120  // seconds
        let pollInterval = 3  // seconds
        var elapsed = 0

        while elapsed < maxWait {
            try? await Task.sleep(for: .seconds(pollInterval))
            elapsed += pollInterval

            let detail = await CockpitClient.shared.agentSession(slug: currentSlug, kind: selectedKind.rawValue)
            guard let session = detail.value else {
                if let error = detail.error {
                    sessionState = .error(error)
                    return
                }
                continue
            }

            switch session.phase {
            case .running:
                connectToSession(session)
                return
            case .paused:
                terminal.disconnect()
                sessionState = .paused
                LiveActivityManager.shared.updateAgentActivity(status: "paused", tokens: 0, snippet: "session paused")
                return
            case .pending:
                let message = "\(pendingMessage(for: session, fallback: "Pod pending")) · \(elapsed)s elapsed"
                sessionState = .pending(message: message)
                terminal.appendDiagnosticLine("⏳ \(message)")
            }
        }

        sessionState = .error("Pod did not become ready in \(maxWait)s. Check cluster from workspace.")
    }

    private func pollUntilPaused() async {
        let maxWait = 30
        let pollInterval = 2
        var elapsed = 0

        while elapsed < maxWait {
            try? await Task.sleep(for: .seconds(pollInterval))
            elapsed += pollInterval

            let detail = await CockpitClient.shared.agentSession(slug: currentSlug, kind: selectedKind.rawValue)
            guard let session = detail.value else {
                if let error = detail.error {
                    sessionState = .error(error)
                    return
                }
                continue
            }

            switch session.phase {
            case .paused:
                terminal.disconnect()
                sessionState = .paused
                LiveActivityManager.shared.updateAgentActivity(status: "paused", tokens: 0, snippet: "session paused")
                return
            case .running, .pending:
                sessionState = .pending(message: "Pausing session... \(elapsed)s")
            }
        }

        sessionState = .error("Pause request did not settle within \(maxWait)s.")
    }

    private func connectToSession(_ session: AgentSession) {
        let podName = session.podName ?? session.name ?? "\(currentSlug)-\(selectedKind.rawValue)"
        sessionState = .running(podName: podName)
        terminal.connect(slug: currentSlug, kind: selectedKind.rawValue)
        LiveActivityManager.shared.startAgentActivity(slug: currentSlug, kind: selectedKind.rawValue, sessionId: podName)
        persistShellObjective(using: session)
    }

    private func restoreExistingSession() async -> AgentSession? {
        let listResult = await CockpitClient.shared.agentSessions(slug: currentSlug)
        if let sessions = listResult.value?.sessions,
           let existing = sessions.first(where: { $0.kind == selectedKind.rawValue }) ?? sessions.first {
            laneSessions = sessions
            return existing
        }

        let detailResult = await CockpitClient.shared.agentSession(slug: currentSlug, kind: selectedKind.rawValue)
        guard let session = detailResult.value else { return nil }

        // Ignore explicit idle/not-created responses, but trust any real phase immediately.
        if (session.status ?? "").lowercased() == "idle",
           (session.name == nil || session.name?.isEmpty == true),
           session.pods?.isEmpty != false,
           session.readyReplicas ?? 0 == 0,
           session.replicas ?? 0 == 0 {
            return nil
        }

        return session
    }

    private func applyRestoredSession(_ session: AgentSession) {
        switch session.phase {
        case .running:
            connectToSession(session)
        case .paused:
            terminal.disconnect()
            sessionState = .paused
            persistShellObjective(using: session)
        case .pending:
            sessionState = .pending(message: pendingMessage(for: session, fallback: "Session pending..."))
            persistShellObjective(using: session)
        }
    }

    private func reconnectTerminal() async {
        guard sessionState.isRunning else {
            await spawnSession()
            return
        }

        let detail = await CockpitClient.shared.agentSession(slug: currentSlug, kind: selectedKind.rawValue)
        guard let session = detail.value else {
            sessionState = .error(detail.error ?? "Could not refresh session before reconnect.")
            return
        }

        switch session.phase {
        case .running:
            connectToSession(session)
        case .paused:
            terminal.disconnect()
            sessionState = .paused
        case .pending:
            sessionState = .pending(message: pendingMessage(for: session, fallback: "Session pending..."))
            await pollUntilReady()
        }
    }

    private var terminalDiagnosticsText: String? {
        guard terminal.hasAbnormalExit else { return nil }
        let formatter = ISO8601DateFormatter()
        let sessionSummary: String = {
            switch sessionState {
            case .idle:
                return "idle"
            case .pending(let message):
                return "pending: \(message)"
            case .running(let podName):
                return "running: \(podName)"
            case .paused:
                return "paused"
            case .error(let message):
                return "error: \(message)"
            }
        }()
        let connectionSummary: String = {
            switch terminal.connectionState {
            case .disconnected:
                return "disconnected"
            case .connecting:
                return "connecting"
            case .connected(let source):
                return "connected via \(source)"
            case .reconnecting(let attempt):
                return "reconnecting attempt \(attempt)"
            case .failed(let message):
                return "failed: \(message)"
            }
        }()

        return [
            "Beagle terminal diagnostics",
            "timestamp: \(formatter.string(from: .now))",
            "project: \(currentSlug)",
            "agent: \(selectedKind.rawValue)",
            "session: \(sessionSummary)",
            "connection: \(connectionSummary)",
            "exit_code: \(terminal.lastExitCode ?? 0)",
            "exit_detail: \(terminal.lastExitDetail ?? "unknown")"
        ].joined(separator: "\n")
    }

    private var terminalSessionIdentityText: String? {
        guard case .running(let podName) = sessionState else { return nil }
        switch terminal.connectionState {
        case .connected(let source):
            return "\(podName) via \(source)"
        case .connecting:
            return "\(podName) connecting"
        case .reconnecting(let attempt):
            return "\(podName) reconnecting (\(attempt))"
        case .failed(let message):
            return "\(podName) failed: \(message)"
        case .disconnected:
            return "\(podName) detached"
        }
    }

    private func pendingMessage(for session: AgentSession, fallback: String) -> String {
        if let action = session.action, !action.isEmpty {
            return action.replacingOccurrences(of: "-", with: " ").capitalized
        }
        if let podPhase = session.pods?.first?.phase, !podPhase.isEmpty {
            return "Pod \(podPhase.lowercased())"
        }
        if let status = session.status, !status.isEmpty {
            return status.replacingOccurrences(of: "-", with: " ").capitalized
        }
        return fallback
    }

    /// Pause the remote session and detach the terminal.
    private func pauseSession() async {
        sessionState = .pending(message: "Pausing session...")
        let paused = await CockpitClient.shared.pauseAgentSession(slug: currentSlug, kind: selectedKind.rawValue)
        guard paused.mode == .observed else {
            sessionState = .error("Could not pause session: \(paused.error ?? "unknown")")
            return
        }
        if let session = paused.value, session.phase == .paused {
            terminal.disconnect()
            sessionState = .paused
            LiveActivityManager.shared.updateAgentActivity(status: "paused", tokens: 0, snippet: "session paused")
            return
        }
        await pollUntilPaused()
    }

    /// Stop the remote session and return to idle.
    private func stopSession() async {
        let stopped = await CockpitClient.shared.stopAgentSession(slug: currentSlug, kind: selectedKind.rawValue)
        guard stopped.mode == .observed else {
            sessionState = .error("Could not stop session: \(stopped.error ?? "unknown")")
            return
        }
        terminal.disconnect()
        sessionState = .idle
        LiveActivityManager.shared.endAgentActivity(finalStatus: "stopped")
    }

    /// Same as spawnSession — checks for running session and connects.
    private func resumeLastSession() async {
        await spawnSession()
    }

    // MARK: - Scratchpad (agent-to-agent communication)

    private var scratchpadStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: BeagleSpacing.xs) {
                ForEach(scratchpadEntries.prefix(5)) { entry in
                    HStack(spacing: BeagleSpacing.xs) {
                        Text(entry.agent ?? "agent")
                            .font(BeagleFont.dataSmall.font)
                            .fontWeight(.semibold)
                            .foregroundStyle(BeagleTheme.truthRemembered)
                        Text(entry.text ?? "")
                            .font(BeagleFont.dataSmall.font)
                            .foregroundStyle(BeagleTheme.textSecondary)
                            .lineLimit(1)
                    }
                    .padding(.horizontal, BeagleSpacing.sm)
                    .padding(.vertical, BeagleSpacing.xs)
                    .background(
                        RoundedRectangle(cornerRadius: BeagleRadius.sm)
                            .fill(BeagleTheme.surface1.opacity(0.5))
                            .overlay(
                                RoundedRectangle(cornerRadius: BeagleRadius.sm)
                                    .strokeBorder(BeagleTheme.truthRemembered.opacity(0.12), lineWidth: 1)
                            )
                    )
                }
            }
            .padding(.horizontal, BeagleSpacing.lg)
            .padding(.vertical, BeagleSpacing.xs)
        }
        .background(.ultraThinMaterial.opacity(0.5))
    }

    private func refreshScratchpad() async {
        let result = await CockpitClient.shared.agentScratchpad(slug: currentSlug)
        if let entries = result.value?.entries, !entries.isEmpty {
            withAnimation(BeagleMotion.normal) {
                scratchpadEntries = Array(entries.suffix(5))
            }
        }
    }

    private func refreshLaneSessions() async {
        let result = await CockpitClient.shared.agentSessions(slug: currentSlug)
        if let sessions = result.value?.sessions {
            laneSessions = sessions
            persistShellObjective()
        } else if result.mode != .observed {
            laneSessions = []
        }
    }

    private var companionHeadline: String {
        switch sessionState {
        case .idle:
            return "No live channel yet"
        case .pending:
            return "The companion is crossing into the cluster"
        case .running:
            if terminal.connectionState.isConnected {
                return "The channel is open"
            }
            return "The agent is present, but the line is unsettled"
        case .paused:
            return "The mind is resting in place"
        case .error:
            return "The channel broke, but the context remained"
        }
    }

    private var companionBody: String {
        switch sessionState {
        case .idle:
            return "Wake a pod when you want a second intelligence in the room for \(projectDisplayName(currentSlug)). The workspace will hold its place once the channel is live."
        case .pending(let message):
            return message
        case .running(let podName):
            if terminal.connectionState.isConnected {
                return "\(selectedKind.displayName) is inhabiting \(podName). Speak plainly; this is a live working channel, not just a deployment."
            }
            return "\(selectedKind.displayName) is still anchored to \(podName), but the terminal line needs recovery."
        case .paused:
            return "The pod is paused without losing continuity. Resume when you want the same thread of work back in front of you."
        case .error(let error):
            return error
        }
    }

    private var companionTint: Color {
        companionPresenceState.tint
    }

    private var companionPresenceState: BeaglePresenceState {
        switch sessionState {
        case .idle:
            return .dormant
        case .pending:
            return .attentive
        case .running:
            return terminal.connectionState.isConnected ? .active : .attentive
        case .paused:
            return .dormant
        case .error:
            return .strained
        }
    }

    private var companionDetail: String {
        switch terminal.connectionState {
        case .disconnected:
            return "no websocket attached right now, but the pod state may still be intact"
        case .connecting:
            return "opening the live shell and waiting for the channel to settle"
        case .connected(let source):
            return "source: \(source) · session continuity is preserved in the cluster"
        case .reconnecting(let attempt):
            return "reconnect attempt \(attempt) · context should survive the interruption"
        case .failed(let error):
            return error
        }
    }

    private var companionTruth: TruthMode {
        switch sessionState {
        case .idle:
            return .declared
        case .pending:
            return .remembered
        case .running:
            return terminal.connectionState.isConnected ? .observed : .remembered
        case .paused:
            return .remembered
        case .error:
            return .stale
        }
    }

    private func switchProject(to slug: String) {
        guard slug != currentSlug else { return }
        terminal.disconnect()
        LiveActivityManager.shared.endAgentActivity(finalStatus: "lane switched")
        scratchpadEntries = []
        laneSessions = []
        sessionState = .idle
        currentSlug = slug
        cognitive.activeProjectSlug = slug
        persistShellObjective()
    }

    private func projectDisplayName(_ slug: String) -> String {
        slug
            .split(separator: "-")
            .map { $0.capitalized }
            .joined(separator: " ")
    }

    private var projectOptions: [Project] {
        if !catalog.projects.isEmpty {
            return catalog.projects
        }

        return [
            Project(projectSlug: "sounio", preferredPrBase: "integration/sounio-dev-ready-base"),
            Project(projectSlug: "scratch"),
            Project(projectSlug: "hyperbolic-semantic-networks")
        ]
    }

    private var laneOverviewTitle: String {
        if let laneState, laneState.activeMindCount > 0 {
            return "Choose the mind you want to enter in \(laneState.displayName)"
        }
        if let laneState, laneState.pausedMindCount > 0 {
            return "\(laneState.displayName) is holding preserved threads"
        }
        return "\(projectDisplayName(currentSlug)) is ready for multiple minds"
    }

    private var laneOverviewBody: String {
        if let laneState, let livingQuestion = laneState.livingQuestion {
            return "This lane is carrying a real living question: “\(livingQuestion)”. Read the board before you enter a terminal, then choose the mind that should carry that question forward."
        }
        if let laneState, let resultSignal = laneState.resultSignal {
            return "This lane already has a result trail: \(resultSignal). Choose the mind that should interpret it or move it forward."
        }
        return "Read this board before you drop into one terminal. It tells you which agent is active, which one is waiting, and which one has not been invited into the lane yet."
    }

    private var laneOverviewDetail: String {
        if let laneState {
            return "\(laneState.countsLine) · \(laneState.nextRecommendedMove)"
        }
        return "\(laneSessions.filter { $0.isRunning }.count) live · \(laneSessions.filter { $0.phase == .paused }.count) paused · \(laneAgentStatuses.count) visible minds"
    }

    private var laneOverviewTruth: TruthMode {
        if laneOverview?.value?.laneResult != nil {
            return laneOverview?.mode ?? .observed
        }
        return laneSessions.isEmpty ? .declared : .observed
    }

    private var laneAgentStatuses: [LaneAgentStatus] {
        let knownKinds = AgentKind.allCases.filter { $0 != .custom }
        let known = knownKinds.map { kind in
            LaneAgentStatus(kind: kind, session: laneSessions.first(where: { $0.kind == kind.rawValue }))
        }

        let extra = laneSessions.compactMap { session -> LaneAgentStatus? in
            guard let kindRaw = session.kind,
                  AgentKind(rawValue: kindRaw) == nil else { return nil }
            return LaneAgentStatus(kind: .custom, session: session)
        }

        return known + extra
    }

    private var laneState: ProjectLaneState? {
        let project = projectOptions.first(where: { $0.projectSlug == currentSlug }) ?? catalog.primaryProject
        guard let project else { return nil }
        let carriedObjective =
            laneSessions.first(where: \.isRunning)?.presentedActivityLine
            ?? laneSessions.first(where: { $0.phase == .paused })?.presentedActivityLine
            ?? laneSessions.first?.presentedActivityLine
        return ProjectLaneState(
            project: project,
            sessions: laneSessions,
            scienceJobs: currentSlug == (cognitive.activeProjectSlug ?? currentSlug) ? cognitive.activeJobs : [],
            laneResult: laneOverview?.value?.laneResult,
            recentTrail: currentSlug == (cognitive.activeProjectSlug ?? currentSlug) ? CognitiveStore.recentTrailSnippets(from: cognitive.recentThoughts) : [],
            truth: laneOverviewTruth,
            isCurrent: currentSlug == (cognitive.activeProjectSlug ?? currentSlug),
            livingQuestion: pinnedLaneQuestions[project.projectSlug],
            carriedObjective: carriedObjective
        )
    }

    private var pinnedLaneQuestions: [String: String] {
        guard let data = pinnedLaneQuestionsJSON.data(using: .utf8),
              let decoded = try? JSONDecoder().decode([String: String].self, from: data) else {
            return [:]
        }
        return decoded
    }


    private func laneStatusActivity(_ status: LaneAgentStatus) -> String {
        guard let session = status.session else {
            return "Not started in this lane yet."
        }

        if let summary = session.activity?.summary?.trimmingCharacters(in: .whitespacesAndNewlines), !summary.isEmpty {
            return summary
        }

        if let excerpt = session.activity?.excerpt?.trimmingCharacters(in: .whitespacesAndNewlines), !excerpt.isEmpty {
            return excerpt
        }

        if let action = session.action?.trimmingCharacters(in: .whitespacesAndNewlines), !action.isEmpty {
            return action
                .replacingOccurrences(of: "-", with: " ")
                .replacingOccurrences(of: "_", with: " ")
                .capitalized
        }

        switch session.phase {
        case .running:
            return "Live and ready in the cluster."
        case .paused:
            return "Paused with context preserved."
        case .pending:
            return "Crossing into the cluster and not ready yet."
        }
    }

    private func laneStatusDetail(_ status: LaneAgentStatus) -> String {
        guard let session = status.session else {
            return "Select \(status.kind.displayName) to start a fresh thread here."
        }

        if let source = session.activity?.source, !source.isEmpty,
           let updatedAt = session.activity?.updatedAt, !updatedAt.isEmpty,
           let relative = relativeTime(from: updatedAt) {
            return "\(source) update · \(relative)"
        }

        switch session.phase {
        case .running:
            if let pod = session.podName {
                return "live in \(pod)"
            }
            return "live now"
        case .paused:
            return "paused but recoverable"
        case .pending:
            if let status = session.status, !status.isEmpty {
                return status.replacingOccurrences(of: "-", with: " ").lowercased()
            }
            return "waiting for readiness"
        }
    }

    private func laneStatusTint(_ status: LaneAgentStatus) -> Color {
        guard let session = status.session else {
            return BeagleTheme.textTertiary
        }

        switch session.phase {
        case .running:
            return BeagleTheme.truthObserved
        case .paused:
            return BeagleTheme.postureWarm
        case .pending:
            return BeagleTheme.truthRemembered
        }
    }

    private func sessionDisplayName(_ session: AgentSession) -> String {
        if let kind = session.kind, !kind.isEmpty {
            return kind
                .replacingOccurrences(of: "-", with: " ")
                .replacingOccurrences(of: "_", with: " ")
                .capitalized
        }

        if let name = session.name, !name.isEmpty {
            return name
        }

        return "Agent"
    }

    private func persistShellObjective(using session: AgentSession? = nil) {
        let candidate = session
            ?? laneSessions.first(where: { $0.kind == selectedKind.rawValue })
            ?? laneSessions.first(where: \.isRunning)
            ?? laneSessions.first

        let objective = candidate.flatMap(shellObjectiveText(for:)) ?? defaultShellObjective
        lastAgentObjective = objective
        lastAgentObjectiveProjectSlug = currentSlug
    }

    private func shellObjectiveText(for session: AgentSession) -> String? {
        if let summary = session.activity?.summary?.trimmingCharacters(in: .whitespacesAndNewlines), !summary.isEmpty {
            return summary
        }

        if let excerpt = session.activity?.excerpt?.trimmingCharacters(in: .whitespacesAndNewlines), !excerpt.isEmpty {
            return excerpt
        }

        if let action = session.action?.trimmingCharacters(in: .whitespacesAndNewlines), !action.isEmpty {
            return action
                .replacingOccurrences(of: "-", with: " ")
                .replacingOccurrences(of: "_", with: " ")
                .capitalized
        }

        switch session.phase {
        case .running:
            return "\(sessionDisplayName(session)) is live and ready in the lane."
        case .paused:
            return "\(sessionDisplayName(session)) is paused with context preserved."
        case .pending:
            return "\(sessionDisplayName(session)) is still crossing into the cluster."
        }
    }

    private var defaultShellObjective: String {
        "Choose a mind in \(projectDisplayName(currentSlug)) to pick up the next thread."
    }

    private func laneStatusSelectionLabel(_ status: LaneAgentStatus) -> String {
        if selectedKind == status.kind {
            return "entered"
        }
        if status.session == nil {
            return "dormant"
        }
        switch status.session?.phase {
        case .running:
            return "live"
        case .paused:
            return "paused"
        case .pending:
            return "waiting"
        case nil:
            return "dormant"
        }
    }

    private func laneStatusSelectionIcon(_ status: LaneAgentStatus) -> String {
        if selectedKind == status.kind {
            return "arrow.down.right.circle.fill"
        }
        if status.session == nil {
            return "moon.zzz.fill"
        }
        switch status.session?.phase {
        case .running:
            return "waveform.circle.fill"
        case .paused:
            return "pause.circle.fill"
        case .pending:
            return "hourglass.circle.fill"
        case nil:
            return "moon.zzz.fill"
        }
    }

    private func laneStatusSelectionTint(_ status: LaneAgentStatus) -> Color {
        if selectedKind == status.kind {
            return BeagleTheme.truthObserved
        }
        return laneStatusTint(status)
    }

    private func relativeTime(from isoString: String) -> String? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let fallback = ISO8601DateFormatter()
        if let date = formatter.date(from: isoString) ?? fallback.date(from: isoString) {
            return RelativeDateTimeFormatter().localizedString(for: date, relativeTo: .now)
        }
        return nil
    }
}

private struct LaneAgentStatus: Identifiable {
    let kind: AgentKind
    let session: AgentSession?

    var id: String {
        session?.kind ?? kind.rawValue
    }
}

// MARK: - Spawning Indicator (rotating messages)

private struct SpawningIndicator: View {
    let agentKind: AgentKind
    let messageOverride: String?
    @State private var message = ""
    @State private var index = 0

    private var messages: [String] {
        [
            "Requesting pod from cluster...",
            "Pulling container image...",
            "Mounting persistent volume...",
            "Starting \(agentKind.displayName)...",
        ]
    }

    var body: some View {
        HStack(spacing: BeagleSpacing.xs) {
            Image(systemName: agentKind.iconSystemName)
                .font(.system(size: 12))
                .foregroundStyle(BeagleTheme.postureWarm)
                .symbolEffect(.pulse, isActive: true)

            Text(message.isEmpty ? messages[0] : message)
                .font(BeagleFont.footnote.font)
                .foregroundStyle(BeagleTheme.postureWarm)
                .contentTransition(.numericText())
                .animation(BeagleMotion.normal, value: message)

            ProgressView()
                .controlSize(.small)
                .tint(BeagleTheme.postureWarm)
        }
        .task {
            while !Task.isCancelled {
                if let messageOverride, !messageOverride.isEmpty {
                    message = messageOverride
                    try? await Task.sleep(for: .seconds(1))
                    continue
                }
                message = messages[index % messages.count]
                index += 1
                try? await Task.sleep(for: .seconds(2))
            }
        }
    }
}

// MARK: - Agent Session Gradient

/// Living background that reacts to session state.
private struct AgentSessionGradient: View {
    let sessionState: AgentSessionView.AgentSessionState
    let connectionState: WebSocketState
    @State private var phase: CGFloat = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        MeshGradient(
            width: 3, height: 3,
            points: animatedPoints,
            colors: gradientColors
        )
        .ignoresSafeArea()
        .animation(.easeInOut(duration: 1.5), value: sessionState.isRunning)
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 8).repeatForever(autoreverses: true)) {
                phase = 1
            }
        }
    }

    private var animatedPoints: [SIMD2<Float>] {
        let d: Float = reduceMotion ? 0 : Float(phase) * 0.06
        return [
            SIMD2(0,     0),     SIMD2(0.5,   0),       SIMD2(1,     0),
            SIMD2(0+d,   0.5-d), SIMD2(0.5+d, 0.5+d),   SIMD2(1-d,   0.5+d),
            SIMD2(0,     1),     SIMD2(0.5,   1),       SIMD2(1,     1)
        ]
    }

    private var gradientColors: [Color] {
        let base = Color(red: 0.02, green: 0.03, blue: 0.07)
        let isLive = sessionState.isRunning && connectionState.isConnected

        return [
            BeagleTheme.truthObserved.opacity(isLive ? 0.25 : 0.0),
            Color(white: 0.04),
            Color(white: 0.03),

            BeagleTheme.postureWarm.opacity(isPending ? 0.15 : 0.0),
            base,
            Color(white: 0.03),

            base, base, Color(white: 0.02)
        ]
    }

    private var isPending: Bool {
        if case .pending = sessionState { return true }
        return false
    }
}

private extension WebSocketState {
    var isConnected: Bool {
        if case .connected = self { return true }
        return false
    }
}
