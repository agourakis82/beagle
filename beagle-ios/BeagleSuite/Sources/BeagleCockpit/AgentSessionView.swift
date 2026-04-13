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
        .background(
            LinearGradient(
                colors: [BeagleTheme.surface0, BeagleTheme.surface1.opacity(0.5)],
                startPoint: .top, endPoint: .bottom
            )
            .ignoresSafeArea()
        )
        .navigationTitle("Agent \u{00B7} \(slug)")
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
                            .padding(.vertical, BeagleSpacing.xs)
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
                    Label("Start Session", systemImage: "play.fill")
                }
                .buttonStyle(PrimaryButton())

                Button {
                    Task { await resumeLastSession() }
                } label: {
                    Label("Resume Last", systemImage: "arrow.clockwise")
                }
                .buttonStyle(SecondaryButton())

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

            case .spawning:
                ProgressView()
                    .controlSize(.small)
                Text("Starting...")
                    .font(BeagleFont.footnote.font)
                    .foregroundStyle(BeagleTheme.textSecondary)

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

    private func spawnSession() async {
        sessionState = .spawning
        let result = await CockpitClient.shared.startAgentSession(slug: slug, kind: selectedKind.rawValue)
        if let session = result.value, session.isRunning || session.action == "start" {
            let podName = session.podName ?? "\(slug)-\(selectedKind.rawValue)-0"
            sessionState = .running(podName: podName)
            terminal.connect(slug: slug, kind: selectedKind.rawValue)
            LiveActivityManager.shared.startAgentActivity(slug: slug, kind: selectedKind.rawValue, sessionId: podName)
        } else if let error = result.error {
            sessionState = .error(error)
        } else {
            sessionState = .running(podName: "\(slug)-\(selectedKind.rawValue)-0")
            terminal.connect(slug: slug, kind: selectedKind.rawValue)
            LiveActivityManager.shared.startAgentActivity(slug: slug, kind: selectedKind.rawValue, sessionId: "\(slug)-\(selectedKind.rawValue)-0")
        }
    }

    private func pauseSession() async {
        terminal.disconnect()
        let result = await CockpitClient.shared.pauseAgentSession(slug: slug, kind: selectedKind.rawValue)
        if let error = result.error {
            sessionState = .error(error)
        } else {
            sessionState = .paused
            LiveActivityManager.shared.updateAgentActivity(status: "paused", tokens: 0, snippet: "session paused")
        }
    }

    private func stopSession() async {
        terminal.disconnect()
        let result = await CockpitClient.shared.stopAgentSession(slug: slug, kind: selectedKind.rawValue)
        if let error = result.error {
            sessionState = .error(error)
        } else {
            sessionState = .idle
            LiveActivityManager.shared.endAgentActivity(finalStatus: "stopped")
        }
    }

    private func resumeLastSession() async {
        sessionState = .spawning
        let existing = await CockpitClient.shared.agentSession(slug: slug, kind: selectedKind.rawValue)
        if let session = existing.value, session.isRunning {
            let podName = session.podName ?? "\(slug)-\(selectedKind.rawValue)-0"
            sessionState = .running(podName: podName)
            terminal.connect(slug: slug, kind: selectedKind.rawValue)
            return
        }
        let result = await CockpitClient.shared.resumeAgentSession(slug: slug, kind: selectedKind.rawValue)
        if let session = result.value {
            let podName = session.podName ?? "\(slug)-\(selectedKind.rawValue)-0"
            sessionState = .running(podName: podName)
            terminal.connect(slug: slug, kind: selectedKind.rawValue)
        } else {
            sessionState = .error(result.error ?? "no session to resume")
        }
    }
}
