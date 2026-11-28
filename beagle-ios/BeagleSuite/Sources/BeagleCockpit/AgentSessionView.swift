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
    case openAIAgent = "openai-agents"
    case claudeCode = "claude-code"
    case codex
    case localSGLang = "local-sglang"
    case custom

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .openAIAgent: return "OpenAI Astra Agent"
        case .claudeCode:  return "Claude Code"
        case .codex:       return "Codex"
        case .localSGLang: return "Local SGLang"
        case .custom:      return "Custom Agent"
        }
    }

    public var iconSystemName: String {
        switch self {
        case .openAIAgent: return "brain.head.profile"
        case .claudeCode:  return "sparkles"
        case .codex:       return "curlybraces"
        case .localSGLang: return "cpu"
        case .custom:      return "gear"
        }
    }

    public var description: String {
        switch self {
        case .openAIAgent:
            return "OpenAI Agents API (v1/agents/sessions) com sandbox hospedado, GPT-6.2 Astra/Sol, SSE e steering ao vivo."
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
    @Environment(CatalogStore.self) var catalog
    @Environment(CognitiveStore.self) var cognitive
    private let initialSlug: String
    @AppStorage("lastAgentKind") var lastAgentKindRaw: String = AgentKind.claudeCode.rawValue
    @AppStorage("lastAgentObjective") var lastAgentObjective = ""
    @AppStorage("lastAgentObjectiveProjectSlug") var lastAgentObjectiveProjectSlug = ""
    @AppStorage("pinnedLaneQuestionsJSON") var pinnedLaneQuestionsJSON = "{}"
    @State var selectedKind: AgentKind = .claudeCode
    @State var sessionState: AgentSessionState = .idle
    @State var terminal = TerminalStore()
    @State var inputText: String = ""
    @FocusState private var inputFocused: Bool
    @State var scratchpadEntries: [ScratchpadEntry] = []
    @State var laneSessions: [AgentSession] = []
    @State var laneOverview: Truthful<MobileProjectOverview>?
    @State var currentSlug: String

    internal init(slug: String) {
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
}
