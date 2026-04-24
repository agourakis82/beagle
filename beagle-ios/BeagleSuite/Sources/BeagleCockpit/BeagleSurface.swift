//
//  BeagleSurface.swift
//  BeagleCockpit
//
//  The unified thinking surface. Not a dashboard. Not a chat app.
//  A single intelligent field where everything begins.
//
//  You type. The exocortex understands.
//  Results emerge below. The supercomputer is behind the glass.
//

import SwiftUI
import BeagleCore

// MARK: - Surface mode (what's showing below the input)

enum SurfaceMode: Equatable {
    case resting            // just the field + greeting
    case thinking           // HERMES refining a thought
    case conversation       // chat with the exocortex
    case deepExploration    // GoDeep multi-modal results
    case terminal           // live cluster terminal
    case results            // search results, agent output, etc.
    case readiness          // cognitive state / HRV / sleep
}

// MARK: - The surface

struct BeagleSurface: View {
    @Environment(CatalogStore.self) private var catalog
    @Environment(CognitiveStore.self) private var cognitive
    @Environment(PhysioStore.self) private var physio
    @State private var inputText = ""
    @State private var mode: SurfaceMode = .resting
    @State private var greeting = ""
    @State private var showProjectPicker = false
    @State private var showAgentPanel = false
    @State private var showReadiness = false
    @State private var terminal = TerminalStore()
    @State private var conversation = ConversationStore(preferLocal: false)
    @State private var deepStore = GoDeepStore()
    @State private var lastCapture: ThoughtCapture?
    @State private var searchResults: [(thought: ThoughtCapture, similarity: Double)] = []
    @FocusState private var inputFocused: Bool
    @Binding var bootError: String?

    var body: some View {
        ZStack {
            // Living background
            ShellPresenceGradient(
                presence: shellPresence,
                cognitivePosture: physio.cognitivePosture
            )

            VStack(spacing: 0) {
                // Spacer pushes content to center when resting
                if mode == .resting {
                    Spacer()
                }

                // Greeting — one warm line, not a card
                if mode == .resting {
                    greetingLine
                        .padding(.bottom, BeagleSpacing.xl)
                }

                // Dream insights float above the field
                if mode == .resting && DreamSynthesisEngine.shared.hasUnreadInsights {
                    dreamBadge
                        .padding(.bottom, BeagleSpacing.md)
                }

                // The field — always present, always centered when resting
                inputField
                    .padding(.horizontal, BeagleSpacing.lg)

                // Results grow below the field
                if mode != .resting {
                    resultArea
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }

                if mode == .resting {
                    Spacer()
                }

                // Context bar at the bottom — not tabs, just truth
                contextBar
            }

            // Error banner if backend unreachable
            if let error = bootError {
                VStack {
                    errorBanner(error)
                        .padding(.horizontal, BeagleSpacing.lg)
                        .padding(.top, BeagleSpacing.xl)
                    Spacer()
                }
            }
        }
        .sheet(isPresented: $showReadiness) {
            NavigationStack {
                CognitiveStateView()
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Done") { showReadiness = false }
                        }
                    }
            }
        }
        .sheet(isPresented: $showAgentPanel) {
            NavigationStack {
                AgentSessionView(slug: activeSlug)
            }
        }
        .sheet(isPresented: $showProjectPicker) {
            NavigationStack {
                PlatformView()
                    .navigationDestination(for: Project.self) { project in
                        ControlRoomView(slug: project.projectSlug)
                    }
            }
        }
        .task {
            greeting = buildGreeting()
        }
    }

    // MARK: - Greeting

    private var greetingLine: some View {
        Text(greeting)
            .font(BeagleFont.title2.font)
            .foregroundStyle(BeagleTheme.textSecondary)
            .multilineTextAlignment(.center)
            .padding(.horizontal, BeagleSpacing.xl)
    }

    // MARK: - Input field

    private var inputField: some View {
        HStack(spacing: BeagleSpacing.sm) {
            TextField("What's on your mind?", text: $inputText, axis: .vertical)
                .font(BeagleFont.body.font)
                .foregroundStyle(BeagleTheme.textPrimary)
                .lineLimit(1...6)
                .focused($inputFocused)
                .onSubmit { handleInput() }
                .submitLabel(.send)

            if !inputText.isEmpty {
                Button(action: handleInput) {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 28))
                        .foregroundStyle(BeagleTheme.truthObserved)
                }
                .transition(.scale.combined(with: .opacity))
            }
        }
        .padding(.horizontal, BeagleSpacing.md)
        .padding(.vertical, BeagleSpacing.sm + 2)
        .background(
            RoundedRectangle(cornerRadius: BeagleRadius.lg)
                .fill(.ultraThinMaterial)
        )
        .overlay(
            RoundedRectangle(cornerRadius: BeagleRadius.lg)
                .strokeBorder(
                    inputFocused ? BeagleTheme.truthObserved.opacity(0.3) : Color.white.opacity(0.08),
                    lineWidth: 1
                )
        )
        .animation(.easeOut(duration: 0.2), value: inputText.isEmpty)
    }

    // MARK: - Result area (grows below input based on mode)

    @ViewBuilder
    private var resultArea: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: BeagleSpacing.md) {
                switch mode {
                case .resting:
                    EmptyView()

                case .thinking:
                    thinkingView

                case .conversation:
                    ConversationView(conversation: conversation)

                case .deepExploration:
                    GoDeepView(store: deepStore, prompt: inputText)

                case .terminal:
                    TerminalContentView(
                        terminal: terminal,
                        onReconnect: nil
                    )
                    .frame(minHeight: 300)

                case .results:
                    resultsView

                case .readiness:
                    CognitiveStateView()
                }
            }
            .padding(.horizontal, BeagleSpacing.lg)
            .padding(.top, BeagleSpacing.md)
            .padding(.bottom, BeagleSpacing.jumbo)
        }
    }

    // MARK: - Thinking (HERMES refining)

    private var thinkingView: some View {
        VStack(alignment: .leading, spacing: BeagleSpacing.md) {
            if cognitive.isCapturing {
                HStack(spacing: BeagleSpacing.sm) {
                    ProgressView()
                        .tint(BeagleTheme.postureWarm)
                    Text("Refining...")
                        .font(BeagleFont.caption.font)
                        .foregroundStyle(BeagleTheme.textSecondary)
                }
            }

            if let capture = lastCapture {
                VStack(alignment: .leading, spacing: BeagleSpacing.xs) {
                    if let refined = capture.refinedText {
                        Text(refined)
                            .font(BeagleFont.body.font)
                            .foregroundStyle(BeagleTheme.textPrimary)
                    }
                    if let translated = capture.translatedText {
                        HStack(spacing: BeagleSpacing.xxs) {
                            Image(systemName: "globe")
                                .font(.system(size: 10))
                            Text(translated)
                                .font(BeagleFont.caption.font)
                                .italic()
                        }
                        .foregroundStyle(BeagleTheme.textTertiary)
                    }
                }
                .padding(BeagleSpacing.md)
                .background(
                    RoundedRectangle(cornerRadius: BeagleRadius.md)
                        .fill(.ultraThinMaterial)
                )
            }
        }
    }

    // MARK: - Results (search, agent output)

    private var resultsView: some View {
        VStack(alignment: .leading, spacing: BeagleSpacing.sm) {
            if !searchResults.isEmpty {
                ForEach(searchResults.prefix(5), id: \.thought.id) { match in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(match.thought.refinedText ?? match.thought.rawText ?? "")
                            .font(BeagleFont.body.font)
                            .foregroundStyle(BeagleTheme.textPrimary)
                            .lineLimit(3)
                        Text("\(Int(match.similarity * 100))% match")
                            .font(BeagleFont.caption2.font)
                            .foregroundStyle(BeagleTheme.textTertiary)
                    }
                    .padding(BeagleSpacing.sm)
                    .background(
                        RoundedRectangle(cornerRadius: BeagleRadius.md)
                            .fill(.ultraThinMaterial)
                    )
                }
            }
        }
    }

    // MARK: - Dream badge (compact, not a huge card)

    private var dreamBadge: some View {
        Button {
            // TODO: expand dream insights
        } label: {
            HStack(spacing: BeagleSpacing.xs) {
                Image(systemName: "moon.stars.fill")
                    .font(.system(size: 12))
                Text("\(DreamSynthesisEngine.shared.unreadCount) overnight insight\(DreamSynthesisEngine.shared.unreadCount == 1 ? "" : "s")")
                    .font(BeagleFont.caption.font)
                    .fontWeight(.medium)
            }
            .foregroundStyle(Color(hue: 270/360, saturation: 0.5, brightness: 0.9))
            .padding(.horizontal, BeagleSpacing.md)
            .padding(.vertical, BeagleSpacing.xs)
            .background(
                Capsule().fill(.ultraThinMaterial)
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Context bar (bottom — project, agents, physio)

    private var contextBar: some View {
        HStack(spacing: 0) {
            // Project
            Button { showProjectPicker = true } label: {
                VStack(spacing: 2) {
                    Image(systemName: "scope")
                        .font(.system(size: 14))
                    Text(activeSlug)
                        .font(BeagleFont.caption2.font)
                }
                .foregroundStyle(BeagleTheme.truthObserved)
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.plain)

            // Agents
            Button { showAgentPanel = true } label: {
                VStack(spacing: 2) {
                    Image(systemName: runningAgentCount > 0 ? "bolt.fill" : "bolt")
                        .font(.system(size: 14))
                    Text(runningAgentCount > 0 ? "\(runningAgentCount) mind\(runningAgentCount == 1 ? "" : "s")" : "agents")
                        .font(BeagleFont.caption2.font)
                }
                .foregroundStyle(runningAgentCount > 0 ? BeagleTheme.postureWarm : BeagleTheme.textTertiary)
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.plain)

            // Readiness
            Button { showReadiness = true } label: {
                VStack(spacing: 2) {
                    Image(systemName: "heart.fill")
                        .font(.system(size: 14))
                    Text(readinessLabel)
                        .font(BeagleFont.caption2.font)
                }
                .foregroundStyle(readinessColor)
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, BeagleSpacing.sm)
        .background(.ultraThinMaterial)
    }

    // MARK: - Error banner

    private func errorBanner(_ error: String) -> some View {
        HStack(spacing: BeagleSpacing.xs) {
            Image(systemName: "wifi.exclamationmark")
                .foregroundStyle(BeagleTheme.stateError)
            Text(error)
                .font(BeagleFont.caption.font)
                .foregroundStyle(BeagleTheme.textSecondary)
                .lineLimit(1)
            Spacer()
            Button {
                Task {
                    bootError = nil
                    await catalog.refresh()
                }
            } label: {
                Text("Retry")
                    .font(BeagleFont.caption.font)
                    .fontWeight(.medium)
            }
        }
        .padding(BeagleSpacing.sm)
        .background(
            RoundedRectangle(cornerRadius: BeagleRadius.md)
                .fill(.ultraThinMaterial)
        )
    }

    // MARK: - Input handling (the intelligence)

    private func handleInput() {
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }

        let intent = classifyIntent(text)
        inputText = ""
        inputFocused = false

        withAnimation(BeagleMotion.snappy) {
            switch intent {
            case .thought:
                mode = .thinking
                Task {
                    lastCapture = await cognitive.captureThought(text: text, source: "surface")
                    if !cognitive.isCapturing {
                        // Stay in thinking mode to show the result
                    }
                }

            case .goDeep:
                mode = .deepExploration
                deepStore = GoDeepStore()
                // GoDeepView handles the rest via its .task

            case .terminal:
                mode = .terminal
                terminal.connect(slug: activeSlug, kind: "claude-code")

            case .search:
                mode = .results
                let query = text.replacingOccurrences(of: "search ", with: "")
                    .replacingOccurrences(of: "find ", with: "")
                    .replacingOccurrences(of: "buscar ", with: "")
                searchResults = cognitive.semanticSearch(query: query)

            case .readiness:
                showReadiness = true

            case .chat:
                mode = .conversation
                conversation = ConversationStore(preferLocal: false)
                let slug = cognitive.activeProjectSlug ?? "sounio"
                conversation.projectSlug = slug
                Task { await conversation.sendMessage(text) }
            }
        }
    }

    // MARK: - Intent classification

    private enum InputIntent {
        case thought, goDeep, terminal, search, readiness, chat
    }

    private func classifyIntent(_ text: String) -> InputIntent {
        let lower = text.lowercased()

        // Explicit commands
        if lower.hasPrefix("go deep") || lower.hasPrefix("explore") || lower.hasPrefix("aprofundar") {
            return .goDeep
        }
        if lower.hasPrefix("terminal") || lower.hasPrefix("shell") || lower.hasPrefix("ssh") {
            return .terminal
        }
        if lower.hasPrefix("search") || lower.hasPrefix("find") || lower.hasPrefix("buscar") || lower.hasPrefix("o que pensei") {
            return .search
        }
        if lower.hasPrefix("how am i") || lower.hasPrefix("readiness") || lower.hasPrefix("como estou") || lower.hasPrefix("hrv") {
            return .readiness
        }

        // Questions → chat
        if lower.hasSuffix("?") || lower.hasPrefix("what") || lower.hasPrefix("why") || lower.hasPrefix("how") ||
           lower.hasPrefix("o que") || lower.hasPrefix("por que") || lower.hasPrefix("como") {
            return .chat
        }

        // Default: capture as thought
        return .thought
    }

    // MARK: - Computed

    private var activeSlug: String {
        cognitive.activeProjectSlug ?? catalog.primaryProject?.projectSlug ?? "sounio"
    }

    private var runningAgentCount: Int {
        cognitive.state.value?.agentSessions?.filter { ($0.readyReplicas ?? 0) > 0 }.count ?? 0
    }

    private var shellPresence: BeaglePresenceState {
        if bootError != nil { return .strained }
        if runningAgentCount > 0 || cognitive.runningJobCount > 0 { return .active }
        return .attentive
    }

    private var readinessLabel: String {
        if let r = physio.cognitivePosture.readiness {
            return "\(Int(r * 100))%"
        }
        return "—"
    }

    private var readinessColor: Color {
        guard let r = physio.cognitivePosture.readiness else { return BeagleTheme.textTertiary }
        if r >= 0.7 { return BeagleTheme.truthObserved }
        if r >= 0.4 { return BeagleTheme.postureWarm }
        return BeagleTheme.stateError
    }

    private func buildGreeting() -> String {
        let hour = Calendar.current.component(.hour, from: .now)
        let posture = physio.cognitivePosture

        if hour < 5 { return "The night holds its own wisdom." }
        if hour < 9 {
            if let sleep = posture.sleepQuality, sleep < 0.3 {
                return "Gentle morning. Be kind to yourself."
            }
            if let r = posture.readiness, r > 0.7 {
                return "Sharp morning. Your mind is ready."
            }
            return "Good morning."
        }
        if hour < 13 { return "What are you thinking about?" }
        if hour < 18 { return "The afternoon is yours." }
        if hour < 22 { return "Evening mind." }
        return "Late thoughts are the deepest."
    }
}

// MARK: - Simplified background (no more ShellPresenceBackground monster)

private struct ShellPresenceGradient: View {
    let presence: BeaglePresenceState
    let cognitivePosture: CognitivePosture

    var body: some View {
        MeshGradient(
            width: 3,
            height: 3,
            points: [
                SIMD2(0, 0), SIMD2(0.5, 0), SIMD2(1, 0),
                SIMD2(0, 0.5), SIMD2(0.5, 0.5), SIMD2(1, 0.5),
                SIMD2(0, 1), SIMD2(0.5, 1), SIMD2(1, 1)
            ],
            colors: gradientColors
        )
        .ignoresSafeArea()
        .overlay {
            Color.black.opacity(0.75)
                .ignoresSafeArea()
        }
    }

    private var gradientColors: [Color] {
        let glow = presence.glow
        let tint = presence.tint
        let base = Color(red: 0.02, green: 0.03, blue: 0.06)
        return [
            glow.opacity(0.15), tint.opacity(0.06), base,
            tint.opacity(0.08), base, glow.opacity(0.08),
            base, base, base
        ]
    }
}
