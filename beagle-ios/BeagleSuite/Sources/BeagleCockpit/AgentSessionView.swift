//
//  AgentSessionView.swift
//  BeagleCockpit
//
//  Persistent agent session UI.
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
    @State private var output: String = ""

    enum AgentSessionState: Equatable {
        case idle
        case spawning
        case running(podName: String)
        case paused
        case error(String)
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            agentPicker
            sessionControls
            outputView
        }
        .background(BeagleTheme.surface0.ignoresSafeArea())
        .navigationTitle("Agent · \(slug)")
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            Image(systemName: selectedKind.iconSystemName)
                .font(.title3)
                .foregroundStyle(BeagleTheme.truthObserved)

            VStack(alignment: .leading, spacing: 2) {
                Text(selectedKind.displayName)
                    .font(BeagleTheme.displayFont(size: 18, weight: .semibold))
                    .foregroundStyle(BeagleTheme.textPrimary)
                statusLabel
            }

            Spacer()

            TruthBadge(truthForState)
        }
        .padding()
        .background(.regularMaterial)
    }

    private var statusLabel: some View {
        switch sessionState {
        case .idle:
            return Text("no active session").font(BeagleTheme.dataFont(size: 11)).foregroundStyle(BeagleTheme.textTertiary)
        case .spawning:
            return Text("spawning agent pod...").font(BeagleTheme.dataFont(size: 11)).foregroundStyle(BeagleTheme.postureWarm)
        case .running(let pod):
            return Text("● running · \(pod)").font(BeagleTheme.dataFont(size: 11)).foregroundStyle(BeagleTheme.truthObserved)
        case .paused:
            return Text("paused (state preserved)").font(BeagleTheme.dataFont(size: 11)).foregroundStyle(BeagleTheme.postureWarm)
        case .error(let msg):
            return Text("error: \(msg)").font(BeagleTheme.dataFont(size: 11)).foregroundStyle(BeagleTheme.stateError)
        }
    }

    private var truthForState: TruthMode {
        switch sessionState {
        case .running: return .observed
        case .paused:  return .remembered
        case .spawning: return .declared
        case .idle: return .declared
        case .error: return .stale
        }
    }

    // MARK: - Agent picker

    private var agentPicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(AgentKind.allCases) { kind in
                    Button {
                        guard sessionState == .idle else { return }
                        selectedKind = kind
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: kind.iconSystemName)
                            Text(kind.displayName)
                        }
                        .font(BeagleTheme.dataFont(size: 12))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(
                            Capsule().fill(
                                selectedKind == kind
                                ? BeagleTheme.truthObserved.opacity(0.15)
                                : Color.white.opacity(0.04)
                            )
                        )
                        .overlay(
                            Capsule().strokeBorder(
                                selectedKind == kind
                                ? BeagleTheme.truthObserved.opacity(0.3)
                                : Color.white.opacity(0.06),
                                lineWidth: 1
                            )
                        )
                        .foregroundStyle(
                            selectedKind == kind ? BeagleTheme.truthObserved : BeagleTheme.textSecondary
                        )
                    }
                    .buttonStyle(.plain)
                    .disabled(sessionState != .idle)
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 10)
        }
    }

    // MARK: - Session controls

    private var sessionControls: some View {
        HStack(spacing: 10) {
            switch sessionState {
            case .idle:
                Button {
                    Task { await spawnSession() }
                } label: {
                    Label("Start Session", systemImage: "play.fill")
                }
                .primaryActionStyle()

                Button {
                    Task { await resumeLastSession() }
                } label: {
                    Label("Resume Last", systemImage: "arrow.clockwise")
                }
                .secondaryActionStyle()

            case .running:
                Button {
                    Task { await pauseSession() }
                } label: {
                    Label("Pause", systemImage: "pause.fill")
                }
                .secondaryActionStyle()

                Button(role: .destructive) {
                    Task { await stopSession() }
                } label: {
                    Label("Stop", systemImage: "stop.fill")
                }
                .secondaryActionStyle()

            case .paused:
                Button {
                    Task { await spawnSession() }
                } label: {
                    Label("Resume", systemImage: "play.fill")
                }
                .primaryActionStyle()

            case .spawning:
                ProgressView()
                    .controlSize(.small)
                Text("Starting...")
                    .font(BeagleTheme.dataFont(size: 12))
                    .foregroundStyle(BeagleTheme.textSecondary)

            case .error:
                Button {
                    Task { await spawnSession() }
                } label: {
                    Label("Retry", systemImage: "arrow.clockwise")
                }
                .primaryActionStyle()
            }

            Spacer()
        }
        .padding()
    }

    // MARK: - Output view

    private var outputView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 4) {
                if output.isEmpty {
                    Text("No output yet. Start a session to attach.")
                        .font(BeagleTheme.dataFont(size: 12))
                        .foregroundStyle(BeagleTheme.textTertiary)
                        .padding()
                } else {
                    Text(output)
                        .font(BeagleTheme.dataFont(size: 12))
                        .foregroundStyle(BeagleTheme.textData)
                        .textSelection(.enabled)
                        .padding()
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(BeagleTheme.surface1)
    }

    // MARK: - Actions (stubs — wire to /api/projects/:slug/agent/* later)

    private func spawnSession() async {
        sessionState = .spawning
        // TODO: POST /api/projects/{slug}/agent/session/start with kind
        try? await Task.sleep(for: .seconds(1))
        sessionState = .running(podName: "\(slug)-agent-\(selectedKind.rawValue)-0")
        output = "● connected to \(selectedKind.displayName) pod\n"
    }

    private func pauseSession() async {
        // TODO: POST /api/projects/{slug}/agent/session/pause
        sessionState = .paused
    }

    private func stopSession() async {
        // TODO: POST /api/projects/{slug}/agent/session/stop
        sessionState = .idle
        output = ""
    }

    private func resumeLastSession() async {
        sessionState = .spawning
        // TODO: GET /api/projects/{slug}/agent/session — if any, attach
        try? await Task.sleep(for: .seconds(1))
        sessionState = .running(podName: "\(slug)-agent-claude-code-0")
        output = "◒ resumed previous session\n"
    }
}

// MARK: - Button styles

extension Button {
    fileprivate func primaryActionStyle() -> some View {
        self
            .buttonStyle(.borderedProminent)
            .tint(BeagleTheme.truthObserved)
            .controlSize(.regular)
    }

    fileprivate func secondaryActionStyle() -> some View {
        self
            .buttonStyle(.bordered)
            .controlSize(.regular)
    }
}
