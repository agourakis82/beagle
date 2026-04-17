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
    let slug: String
    @AppStorage("lastAgentKind") private var lastAgentKindRaw: String = AgentKind.claudeCode.rawValue
    @State private var selectedKind: AgentKind = .claudeCode
    @State private var sessionState: AgentSessionState = .idle
    @State private var terminal = TerminalStore()
    @State private var inputText: String = ""
    @FocusState private var inputFocused: Bool
    @State private var scratchpadEntries: [ScratchpadEntry] = []

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
            agentPicker
            if !scratchpadEntries.isEmpty {
                scratchpadStrip
            }
            sessionControls
            TerminalContentView(terminal: terminal)
            if sessionState.isRunning {
                inputBar
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .background { AgentSessionGradient(sessionState: sessionState, connectionState: terminal.connectionState) }
        .navigationTitle("Agent \u{00B7} \(slug)")
        .sensoryFeedback(.success, trigger: sessionState.isRunning)
        .onChange(of: sessionState) {
            if sessionState.isRunning {
                inputFocused = true
            }
        }
        .onAppear {
            terminal.onActivityUpdate = { status, tokens, snippet in
                LiveActivityManager.shared.updateAgentActivity(status: status, tokens: tokens, snippet: snippet)
            }
            // Restore last used agent kind
            if let kind = AgentKind(rawValue: lastAgentKindRaw) {
                selectedKind = kind
            }
        }
        .task {
            // Restore visible state from the cluster on launch.
            if sessionState == .idle {
                let result = await CockpitClient.shared.agentSessions(slug: slug)
                if let sessions = result.value?.sessions,
                   let existing = sessions.first(where: { $0.kind == selectedKind.rawValue })
                    ?? sessions.first {
                    if let kind = AgentKind(rawValue: existing.kind ?? "") {
                        selectedKind = kind
                        lastAgentKindRaw = kind.rawValue
                    }
                    switch existing.phase {
                    case .running:
                        connectToSession(existing)
                    case .paused:
                        sessionState = .paused
                    case .pending:
                        sessionState = .pending(message: pendingMessage(for: existing, fallback: "Session pending..."))
                    }
                }
            }
            // Load scratchpad
            await refreshScratchpad()
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
        let result = await CockpitClient.shared.agentSessions(slug: slug)

        guard result.mode == .observed, let sessions = result.value?.sessions else {
            let err = result.error ?? "no response"
            sessionState = .error("Cockpit unreachable: \(err). Check Tailscale on iPhone.")
            return
        }

        let existing = sessions.first(where: { $0.kind == selectedKind.rawValue })

        if let existing {
            switch existing.phase {
            case .running:
                connectToSession(existing)
                return
            case .paused:
                sessionState = .pending(message: "Resuming \(selectedKind.displayName)...")
                let resumed = await CockpitClient.shared.resumeAgentSession(slug: slug, kind: selectedKind.rawValue)
                if resumed.mode != .observed {
                    sessionState = .error("Could not resume session: \(resumed.error ?? "unknown")")
                    return
                }
            case .pending:
                sessionState = .pending(message: pendingMessage(for: existing, fallback: "Session pending..."))
            }
        } else {
            sessionState = .pending(message: "Starting \(selectedKind.displayName)...")
            let started = await CockpitClient.shared.startAgentSession(slug: slug, kind: selectedKind.rawValue)
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

            let detail = await CockpitClient.shared.agentSession(slug: slug, kind: selectedKind.rawValue)
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

            let detail = await CockpitClient.shared.agentSession(slug: slug, kind: selectedKind.rawValue)
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
        let podName = session.podName ?? session.name ?? "\(slug)-\(selectedKind.rawValue)"
        sessionState = .running(podName: podName)
        terminal.connect(slug: slug, kind: selectedKind.rawValue)
        LiveActivityManager.shared.startAgentActivity(slug: slug, kind: selectedKind.rawValue, sessionId: podName)
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
        let paused = await CockpitClient.shared.pauseAgentSession(slug: slug, kind: selectedKind.rawValue)
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
        let stopped = await CockpitClient.shared.stopAgentSession(slug: slug, kind: selectedKind.rawValue)
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
        let result = await CockpitClient.shared.agentScratchpad(slug: slug)
        if let entries = result.value?.entries, !entries.isEmpty {
            withAnimation(BeagleMotion.normal) {
                scratchpadEntries = Array(entries.suffix(5))
            }
        }
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
