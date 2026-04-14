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
    @State private var selectedKind: AgentKind = .claudeCode
    @State private var sessionState: AgentSessionState = .idle
    @State private var terminal = TerminalStore()
    @State private var inputText: String = ""
    @FocusState private var inputFocused: Bool

    enum AgentSessionState: Equatable {
        case idle
        case spawning
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
        case .spawning:
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
        case .spawning:
            Text("spawning pod...").foregroundStyle(BeagleTheme.postureWarm)
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
                        withAnimation(BeagleMotion.snappy) { selectedKind = kind }
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
                    Label("Detach", systemImage: "pause.fill")
                }
                .buttonStyle(SecondaryButton(color: BeagleTheme.postureWarm))

                Button {
                    Task { await stopSession() }
                } label: {
                    Label("Disconnect", systemImage: "stop.fill")
                }
                .buttonStyle(SecondaryButton(color: BeagleTheme.stateError))

            case .paused:
                Button {
                    Task { await spawnSession() }
                } label: {
                    Label("Resume", systemImage: "play.fill")
                }
                .buttonStyle(PrimaryButton())

            case .spawning:
                SpawningIndicator(agentKind: selectedKind)

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

    /// Connect to a running agent session.
    /// Fetches sessions list from cockpit, finds the matching kind, connects WebSocket.
    private func spawnSession() async {
        sessionState = .spawning

        // Fetch real sessions from cockpit
        let result = await CockpitClient.shared.agentSessions(slug: slug)

        if let response = result.value, let sessions = response.sessions {
            // Find a running session matching selected kind
            if let session = sessions.first(where: {
                $0.kind == selectedKind.rawValue && $0.isRunning
            }) {
                let podName = session.podName ?? session.name ?? "\(slug)-\(selectedKind.rawValue)"
                sessionState = .running(podName: podName)
                terminal.connect(slug: slug, kind: selectedKind.rawValue)
                LiveActivityManager.shared.startAgentActivity(slug: slug, kind: selectedKind.rawValue, sessionId: podName)
            } else if let session = sessions.first(where: { $0.kind == selectedKind.rawValue }) {
                // Session exists but not running
                sessionState = .error("\(selectedKind.displayName) exists but is not running (status: \(session.status ?? "unknown")). Scale it up from the cluster.")
            } else {
                // No session of this kind at all
                sessionState = .error("No \(selectedKind.displayName) session found for \(slug). Deploy it from the workspace first.")
            }
        } else if let error = result.error {
            sessionState = .error("Could not reach cockpit: \(error)")
        } else {
            sessionState = .error("Could not fetch agent sessions. Check Tailnet.")
        }
    }

    /// Disconnect from the terminal (session keeps running in K8s).
    private func pauseSession() async {
        terminal.disconnect()
        sessionState = .paused
        LiveActivityManager.shared.updateAgentActivity(status: "detached", tokens: 0, snippet: "detached from terminal")
    }

    /// Disconnect and return to idle.
    private func stopSession() async {
        terminal.disconnect()
        sessionState = .idle
        LiveActivityManager.shared.endAgentActivity(finalStatus: "detached")
    }

    /// Same as spawnSession — checks for running session and connects.
    private func resumeLastSession() async {
        await spawnSession()
    }
}

// MARK: - Spawning Indicator (rotating messages)

private struct SpawningIndicator: View {
    let agentKind: AgentKind
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

            BeagleTheme.postureWarm.opacity(sessionState == .spawning ? 0.15 : 0.0),
            base,
            Color(white: 0.03),

            base, base, Color(white: 0.02)
        ]
    }
}

private extension WebSocketState {
    var isConnected: Bool {
        if case .connected = self { return true }
        return false
    }
}
