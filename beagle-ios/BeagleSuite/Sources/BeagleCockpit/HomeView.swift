//
//  HomeView.swift
//  BeagleCockpit
//
//  The exocortex surface. Not a dashboard — a thinking companion.
//  Opens with provocations, suggestions, and an inviting input.
//  Makes you want to engage, not just monitor.
//

import SwiftUI
import BeagleCore

struct HomeView: View {
    @Environment(CatalogStore.self) private var catalog
    @Environment(CognitiveStore.self) private var cognitive
    @State private var conversation = ConversationStore()
    @State private var inputText = ""
    @State private var provocations: [Provocation] = []
    @State private var greeting = ""
    @State private var hasAppeared = false
    @State private var serendipityInsight: String?
    @State private var morningBrief: String?
    #if os(iOS)
    @State private var speechRecognizer = SpeechRecognizer()
    #endif

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: BeagleSpacing.xl) {
                    greetingSection
                    #if os(iOS)
                    ambientCaptureToggle
                    #endif
                    if !provocations.isEmpty {
                        provocationsSection
                    }
                    if let brief = morningBrief {
                        morningBriefCard(brief)
                    }
                    if let insight = serendipityInsight {
                        serendipityCard(insight)
                    }
                    noveltySection
                    recentThoughtsSection
                    if !conversation.isEmpty {
                        conversationSection
                    }
                    agentActivityLink
                    statusGlance
                }
                .padding(.horizontal, BeagleSpacing.lg)
                .padding(.top, BeagleSpacing.xl)
                .padding(.bottom, BeagleSpacing.jumbo)
            }

            exocortexInput
        }
        .background(
            LinearGradient(
                colors: [
                    BeagleTheme.surface0,
                    Color(red: 8/255, green: 15/255, blue: 28/255),
                    Color(red: 5/255, green: 12/255, blue: 24/255)
                ],
                startPoint: .top, endPoint: .bottom
            )
            .ignoresSafeArea()
        )
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                NavigationLink {
                    ModelSettingsView()
                } label: {
                    HStack(spacing: BeagleSpacing.xxs) {
                        if LocalLLMEngine.shared.isReady {
                            Image(systemName: "brain")
                                .font(.system(size: 12))
                                .foregroundStyle(BeagleTheme.truthObserved)
                        }
                        Image(systemName: "gearshape")
                            .foregroundStyle(BeagleTheme.textSecondary)
                    }
                }
            }
        }
        .task {
            await bootstrap()
        }
        .refreshable {
            async let c: () = catalog.refresh()
            async let g: () = cognitive.refresh()
            _ = await (c, g)
            generateProvocations()
        }
    }

    // MARK: - Greeting

    private var greetingSection: some View {
        VStack(alignment: .leading, spacing: BeagleSpacing.sm) {
            Text(greeting)
                .font(BeagleFont.largeTitle.font)
                .foregroundStyle(
                    LinearGradient(
                        colors: [BeagleTheme.textPrimary, BeagleTheme.truthObserved.opacity(0.7)],
                        startPoint: .leading, endPoint: .trailing
                    )
                )
                .opacity(hasAppeared ? 1 : 0)
                .offset(y: hasAppeared ? 0 : 10)
                .animation(.easeOut(duration: 0.6), value: hasAppeared)

            Text(contextLine)
                .font(BeagleFont.body.font)
                .foregroundStyle(BeagleTheme.textSecondary)
                .opacity(hasAppeared ? 1 : 0)
                .offset(y: hasAppeared ? 0 : 8)
                .animation(.easeOut(duration: 0.6).delay(0.15), value: hasAppeared)

            if LocalLLMEngine.shared.isReady, let model = LocalLLMEngine.shared.currentModel {
                HStack(spacing: BeagleSpacing.xxs) {
                    Image(systemName: "brain")
                        .font(.system(size: 10))
                    Text("\(model.displayName) on-device")
                        .font(BeagleFont.caption2.font)
                }
                .foregroundStyle(BeagleTheme.truthObserved.opacity(0.7))
                .opacity(hasAppeared ? 1 : 0)
                .animation(.easeOut(duration: 0.4).delay(0.25), value: hasAppeared)
            }
        }
    }

    private var contextLine: String {
        let jobCount = cognitive.activeJobs.count
        let projectCount = catalog.postureCounts.totalProjects
        if jobCount > 0 {
            return "\(jobCount) job\(jobCount > 1 ? "s" : "") running across \(projectCount) surfaces."
        }
        return "\(projectCount) sovereign surfaces. What are you thinking about?"
    }

    // MARK: - Provocations (like ChatGPT Pulse)

    private var provocationsSection: some View {
        VStack(alignment: .leading, spacing: BeagleSpacing.sm) {
            HStack(spacing: BeagleSpacing.xs) {
                Image(systemName: "sparkles")
                    .font(.system(size: 12))
                    .foregroundStyle(BeagleTheme.truthObserved)
                Text("Explore")
                    .font(BeagleFont.caption.font)
                    .fontWeight(.medium)
                    .foregroundStyle(BeagleTheme.textTertiary)
            }
            .opacity(hasAppeared ? 1 : 0)
            .animation(.easeOut(duration: 0.4).delay(0.3), value: hasAppeared)

            ForEach(Array(provocations.enumerated()), id: \.element.id) { index, provocation in
                Button {
                    inputText = provocation.prompt
                    Task { await conversation.sendMessage(provocation.prompt) }
                } label: {
                    provocationCard(provocation)
                }
                .buttonStyle(.plain)
                .opacity(hasAppeared ? 1 : 0)
                .offset(y: hasAppeared ? 0 : 12)
                .animation(.easeOut(duration: 0.5).delay(0.35 + Double(index) * 0.1), value: hasAppeared)
            }
        }
    }

    private func provocationCard(_ p: Provocation) -> some View {
        HStack(spacing: BeagleSpacing.sm) {
            Image(systemName: p.icon)
                .font(.system(size: 16))
                .foregroundStyle(p.color)
                .frame(width: 32)

            VStack(alignment: .leading, spacing: 2) {
                Text(p.title)
                    .font(BeagleFont.footnote.font)
                    .fontWeight(.medium)
                    .foregroundStyle(BeagleTheme.textPrimary)
                    .lineLimit(1)
                Text(p.subtitle)
                    .font(BeagleFont.caption.font)
                    .foregroundStyle(BeagleTheme.textSecondary)
                    .lineLimit(2)
            }

            Spacer()

            Image(systemName: "arrow.up.right")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(BeagleTheme.textTertiary)
        }
        .padding(BeagleSpacing.md)
        .background(
            RoundedRectangle(cornerRadius: BeagleRadius.lg)
                .fill(BeagleTheme.surface1.opacity(0.7))
        )
        .overlay(
            RoundedRectangle(cornerRadius: BeagleRadius.lg)
                .strokeBorder(p.color.opacity(0.1), lineWidth: 1)
        )
    }

    // MARK: - Novelty (Void, Fractal, Phi)

    @ViewBuilder
    private var noveltySection: some View {
        let fractals = cognitive.state.value?.recentFractalTrees ?? []
        let phis = cognitive.state.value?.recentPhiMeasurements ?? []
        let voids = cognitive.state.value?.recentVoidJourneys ?? []

        if !fractals.isEmpty || !phis.isEmpty || !voids.isEmpty {
            VStack(alignment: .leading, spacing: BeagleSpacing.sm) {
                HStack(spacing: BeagleSpacing.xs) {
                    Image(systemName: "atom")
                        .font(.system(size: 12))
                        .foregroundStyle(BeagleTheme.truthRemembered)
                    Text("Exocortex")
                        .font(BeagleFont.caption.font)
                        .fontWeight(.medium)
                        .foregroundStyle(BeagleTheme.textTertiary)
                }

                // Latest fractal tree
                if let fractal = fractals.first {
                    Button {
                        let prompt = fractal.rootPrompt ?? "fractal tree"
                        Task { await conversation.sendMessage("Explain this fractal exploration: \(prompt) — it produced \(fractal.nodeCount ?? 0) nodes at depth \(fractal.maxDepth ?? 0) in \(fractal.durationMs ?? 0)ms") }
                    } label: {
                        noveltyCard(
                            icon: "tree",
                            color: BeagleTheme.truthObserved,
                            title: "Fractal: \(fractal.nodeCount ?? 0) nodes",
                            subtitle: fractal.rootPrompt ?? "",
                            detail: "depth \(fractal.maxDepth ?? 0) \u{00B7} \(fractal.durationMs ?? 0)ms",
                            truthMode: fractal.truthMode
                        )
                    }
                    .buttonStyle(.plain)
                }

                // Latest phi measurement
                if let phi = phis.first {
                    Button {
                        Task { await conversation.sendMessage("Analyze this IIT measurement: \u{03A6} = \(phi.phi ?? 0) for query '\(phi.querySnippet ?? "")'. Awareness: \(phi.awarenessLevel ?? "unknown"). What does this mean?") }
                    } label: {
                        noveltyCard(
                            icon: "waveform.path.ecg",
                            color: BeagleTheme.truthRemembered,
                            title: "\u{03A6} = \(String(format: "%.4f", phi.phi ?? 0))",
                            subtitle: phi.querySnippet ?? "",
                            detail: "\(phi.awarenessLevel ?? "") \u{00B7} \(phi.substrateSize ?? 0) substrates",
                            truthMode: phi.truthMode
                        )
                    }
                    .buttonStyle(.plain)
                }

                // Void journeys count
                if !voids.isEmpty {
                    noveltyCard(
                        icon: "circle.dotted",
                        color: BeagleTheme.postureWarm,
                        title: "\(voids.count) void journey\(voids.count > 1 ? "s" : "")",
                        subtitle: "\(voids.first?.insights?.count ?? 0) insights from latest",
                        detail: "depth \(String(format: "%.1f", voids.first?.maxDepthReached ?? 0))",
                        truthMode: voids.first?.truthMode
                    )
                }
            }
        }
    }

    private func noveltyCard(icon: String, color: Color, title: String, subtitle: String, detail: String, truthMode: String?) -> some View {
        HStack(spacing: BeagleSpacing.sm) {
            Image(systemName: icon)
                .font(.system(size: 14))
                .foregroundStyle(color)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(BeagleFont.footnote.font)
                    .fontWeight(.medium)
                    .foregroundStyle(BeagleTheme.textPrimary)
                Text(subtitle)
                    .font(BeagleFont.caption.font)
                    .foregroundStyle(BeagleTheme.textSecondary)
                    .lineLimit(1)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                Text(detail)
                    .font(BeagleFont.dataSmall.font)
                    .foregroundStyle(BeagleTheme.textTertiary)
                if let mode = truthMode {
                    TruthBadge(TruthMode(rawValue: mode) ?? .declared, compact: true)
                }
            }
        }
        .padding(BeagleSpacing.sm)
        .background(
            RoundedRectangle(cornerRadius: BeagleRadius.md)
                .fill(BeagleTheme.surface1.opacity(0.5))
        )
    }

    // MARK: - Recent thoughts

    @ViewBuilder
    private var recentThoughtsSection: some View {
        if !cognitive.recentThoughts.isEmpty {
            VStack(alignment: .leading, spacing: BeagleSpacing.sm) {
                Text("Recent thoughts")
                    .font(BeagleFont.caption.font)
                    .fontWeight(.medium)
                    .foregroundStyle(BeagleTheme.textTertiary)

                ForEach(cognitive.recentThoughts.prefix(3)) { thought in
                    let thoughtText = thought.refinedText ?? thought.rawText ?? ""
                    Button {
                        Task { await conversation.sendMessage("Expand on this thought: \(thoughtText)") }
                    } label: {
                        HStack(alignment: .top, spacing: BeagleSpacing.sm) {
                            Circle()
                                .fill(BeagleTheme.truthObserved.opacity(0.5))
                                .frame(width: 6, height: 6)
                                .padding(.top, 6)

                            Text(thoughtText.isEmpty ? "—" : thoughtText)
                                .font(BeagleFont.footnote.font)
                                .foregroundStyle(BeagleTheme.textPrimary)
                                .lineLimit(2)
                                .multilineTextAlignment(.leading)

                            Spacer()
                        }
                    }
                    .buttonStyle(.plain)
                    .contextMenu {
                        Button {
                            Task { await conversation.sendMessage("Expand on this thought: \(thoughtText)") }
                        } label: {
                            Label("Expand", systemImage: "text.bubble")
                        }
                        if !thoughtText.isEmpty {
                            GoDeepContextAction(prompt: thoughtText)
                        }
                    }
                }
            }
        }
    }

    // MARK: - Conversation (inline, not separate tab)

    @ViewBuilder
    private var conversationSection: some View {
        VStack(spacing: BeagleSpacing.xs) {
            ForEach(conversation.messages) { message in
                ChatBubbleView(
                    message: message,
                    onRegenerate: message.role == .assistant ? {
                        Task { await conversation.regenerateLastResponse() }
                    } : nil
                )

                // Go Deeper button on assistant responses
                if message.role == .assistant && !message.isStreaming {
                    HStack {
                        GoDeepButton(prompt: message.content)
                        Spacer()
                    }
                    .padding(.leading, BeagleSpacing.md)
                }
            }
        }
    }

    // MARK: - Agent Activity Link

    private var agentActivityLink: some View {
        NavigationLink {
            AgentActivityView()
        } label: {
            HStack(spacing: BeagleSpacing.sm) {
                Image(systemName: "antenna.radiowaves.left.and.right")
                    .font(.system(size: 14))
                    .foregroundStyle(BeagleTheme.truthRemembered)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Agent Activity")
                        .font(BeagleFont.footnote.font)
                        .fontWeight(.medium)
                        .foregroundStyle(BeagleTheme.textPrimary)
                    Text("See what all agents are doing")
                        .font(BeagleFont.caption.font)
                        .foregroundStyle(BeagleTheme.textTertiary)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(BeagleTheme.textTertiary)
            }
            .padding(BeagleSpacing.md)
            .background(
                RoundedRectangle(cornerRadius: BeagleRadius.lg)
                    .fill(BeagleTheme.surface1.opacity(0.5))
            )
            .overlay(
                RoundedRectangle(cornerRadius: BeagleRadius.lg)
                    .strokeBorder(BeagleTheme.truthRemembered.opacity(0.08), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Status glance (minimal, at the bottom)

    @ViewBuilder
    private var statusGlance: some View {
        let running = cognitive.activeJobs.filter(\.isRunning)
        let errors = cognitive.activeJobs.filter { $0.status == "error" }

        if !running.isEmpty || !errors.isEmpty {
            VStack(alignment: .leading, spacing: BeagleSpacing.xs) {
                Text("Status")
                    .font(BeagleFont.caption.font)
                    .fontWeight(.medium)
                    .foregroundStyle(BeagleTheme.textTertiary)

                ForEach(running) { job in
                    statusRow(job.kind ?? "job", status: "running", color: BeagleTheme.postureWarm, pulse: true)
                }
                ForEach(errors.prefix(2)) { job in
                    statusRow(job.kind ?? "job", status: "error", color: BeagleTheme.stateError, pulse: false)
                }
            }
        }
    }

    private func statusRow(_ name: String, status: String, color: Color, pulse: Bool) -> some View {
        HStack(spacing: BeagleSpacing.sm) {
            Circle()
                .fill(color)
                .frame(width: 6, height: 6)
                .symbolEffect(.pulse, isActive: pulse)
            Text(name)
                .font(BeagleFont.data.font)
                .foregroundStyle(BeagleTheme.textSecondary)
            Spacer()
            Text(status)
                .font(BeagleFont.dataSmall.font)
                .foregroundStyle(color)
        }
    }

    // MARK: - Exocortex input (always visible at bottom)

    private var exocortexInput: some View {
        BeagleInputBar(
            text: $inputText,
            placeholder: "Ask the exocortex...",
            mode: .chat,
            isEnabled: !conversation.isStreaming,
            onSubmit: { text in
                Task { await conversation.sendMessage(text) }
            }
        )
    }

    // MARK: - Ambient capture toggle

    #if os(iOS)
    private var ambientCaptureToggle: some View {
        HStack(spacing: BeagleSpacing.sm) {
            Image(systemName: speechRecognizer.isAmbientActive ? "waveform.badge.microphone" : "mic.badge.plus")
                .font(.system(size: 16))
                .foregroundStyle(speechRecognizer.isAmbientActive ? BeagleTheme.truthObserved : BeagleTheme.textTertiary)
                .symbolEffect(.variableColor, isActive: speechRecognizer.isAmbientActive)

            VStack(alignment: .leading, spacing: 1) {
                Text("Ambient Capture")
                    .font(BeagleFont.footnote.font)
                    .fontWeight(.medium)
                    .foregroundStyle(BeagleTheme.textPrimary)
                Text(speechRecognizer.isAmbientActive ? "Whisper listening on-device" : "Off — tap to start")
                    .font(BeagleFont.caption2.font)
                    .foregroundStyle(speechRecognizer.isAmbientActive ? BeagleTheme.truthObserved.opacity(0.7) : BeagleTheme.textTertiary)
            }

            Spacer()

            Toggle("", isOn: Binding(
                get: { speechRecognizer.isAmbientActive },
                set: { _ in Task { await speechRecognizer.toggleAmbient() } }
            ))
            .tint(BeagleTheme.truthObserved)
            .labelsHidden()
        }
        .padding(BeagleSpacing.md)
        .background(
            RoundedRectangle(cornerRadius: BeagleRadius.lg)
                .fill(speechRecognizer.isAmbientActive ? BeagleTheme.truthObserved.opacity(0.06) : BeagleTheme.surface1.opacity(0.7))
        )
        .overlay(
            RoundedRectangle(cornerRadius: BeagleRadius.lg)
                .strokeBorder(
                    speechRecognizer.isAmbientActive ? BeagleTheme.truthObserved.opacity(0.2) : Color.white.opacity(0.06),
                    lineWidth: 1
                )
        )
        .opacity(hasAppeared ? 1 : 0)
        .animation(.easeOut(duration: 0.4).delay(0.2), value: hasAppeared)
    }
    #endif

    // MARK: - Morning Brief (synthesized from overnight agent activity)

    private func morningBriefCard(_ brief: String) -> some View {
        GlassPanel(elevation: .floating, truth: .observed) {
            VStack(alignment: .leading, spacing: BeagleSpacing.sm) {
                HStack(spacing: BeagleSpacing.xs) {
                    Image(systemName: "sunrise.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(BeagleTheme.postureWarm)
                    Text("Morning Brief")
                        .font(BeagleFont.caption.font)
                        .fontWeight(.medium)
                        .foregroundStyle(BeagleTheme.postureWarm)
                        .textCase(.uppercase)
                        .tracking(0.5)
                    Spacer()
                    TruthBadge(.observed, compact: true)
                }

                Text(brief)
                    .font(BeagleFont.subheadline.font)
                    .foregroundStyle(BeagleTheme.textPrimary)
                    .lineSpacing(3)

                GoDeepButton(prompt: "Expand on this morning brief: \(brief)")
            }
        }
        .opacity(hasAppeared ? 1 : 0)
        .offset(y: hasAppeared ? 0 : 12)
        .animation(.easeOut(duration: 0.6).delay(0.2), value: hasAppeared)
    }

    // MARK: - Serendipity Card (unexpected connections)

    private func serendipityCard(_ insight: String) -> some View {
        HStack(alignment: .top, spacing: BeagleSpacing.sm) {
            Image(systemName: "sparkle")
                .font(.system(size: 16))
                .foregroundStyle(
                    LinearGradient(
                        colors: [Color(hue: 300/360, saturation: 0.6, brightness: 0.9), BeagleTheme.truthRemembered],
                        startPoint: .topLeading, endPoint: .bottomTrailing
                    )
                )
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: BeagleSpacing.xs) {
                Text("Serendipity")
                    .font(BeagleFont.caption.font)
                    .fontWeight(.medium)
                    .foregroundStyle(BeagleTheme.textTertiary)
                    .textCase(.uppercase)
                    .tracking(0.5)

                Text(insight)
                    .font(BeagleFont.footnote.font)
                    .foregroundStyle(BeagleTheme.textSecondary)
                    .lineSpacing(2)
                    .italic()

                GoDeepButton(prompt: insight)
            }
        }
        .padding(.horizontal, BeagleSpacing.lg)
        .padding(.vertical, BeagleSpacing.md)
        .background(
            RoundedRectangle(cornerRadius: BeagleRadius.lg)
                .fill(Color(hue: 300/360, saturation: 0.6, brightness: 0.9).opacity(0.03))
        )
        .overlay(
            RoundedRectangle(cornerRadius: BeagleRadius.lg)
                .strokeBorder(Color(hue: 300/360, saturation: 0.6, brightness: 0.9).opacity(0.06), lineWidth: 1)
        )
        .opacity(hasAppeared ? 1 : 0)
        .offset(y: hasAppeared ? 0 : 12)
        .animation(.easeOut(duration: 0.6).delay(0.35), value: hasAppeared)
    }

    // MARK: - Generate Morning Brief + Serendipity

    private func generateInspirationLayer() {
        let thoughts = cognitive.recentThoughts.prefix(5).compactMap { $0.refinedText ?? $0.rawText }
        let projects = catalog.projects.map(\.projectSlug)
        let jobs = cognitive.activeJobs

        Task {
            // Morning brief — what happened overnight, synthesized
            let briefPrompt = """
            My sovereign computing platform has \(projects.count) projects: \(projects.joined(separator: ", ")).
            \(jobs.isEmpty ? "No jobs running." : "\(jobs.count) jobs active.")
            \(thoughts.isEmpty ? "" : "Recent thoughts: \(thoughts.joined(separator: "; "))")

            Give me a 2-sentence morning brief: what's the most interesting state of my platform right now, and one thing I should explore today. Be specific to my context, not generic.
            """

            let brief = await FoundationModelsAgent.shared.summarize(
                briefPrompt,
                instructions: "You are a sovereign computing platform operator's morning brief. Be concise, specific, and inspiring. One insight, one suggestion."
            )
            if let brief, !brief.isEmpty {
                withAnimation(BeagleMotion.slow) { morningBrief = brief }
            }

            // Serendipity — find an unexpected connection
            guard thoughts.count >= 2 else { return }
            let serendipityPrompt = """
            These are recent thoughts from a researcher:
            \(thoughts.enumerated().map { "\($0 + 1). \($1)" }.joined(separator: "\n"))

            Find one surprising, non-obvious connection between any two of these thoughts. The connection should make the researcher stop and think "I hadn't considered that." Be specific.
            """

            let insight = await FoundationModelsAgent.shared.summarize(
                serendipityPrompt,
                instructions: "You are a serendipity engine. Find unexpected cross-domain connections between ideas. Be specific and surprising, not vague."
            )
            if let insight, !insight.isEmpty {
                withAnimation(BeagleMotion.slow) { serendipityInsight = insight }
            }
        }
    }

    // MARK: - Bootstrap

    private func bootstrap() async {
        greeting = timeGreeting()
        #if os(iOS)
        await speechRecognizer.setup()
        #endif
        async let c: () = catalog.refresh()
        async let g: () = cognitive.refresh()
        _ = await (c, g)
        // Wire HRV flow state into conversation routing
        conversation.flowState = cognitive.flowState

        generateProvocations()
        generateInspirationLayer()
        withAnimation { hasAppeared = true }

        #if os(iOS)
        // Start ambient triage loop: periodically sends fragments to cluster for filtering
        startAmbientTriageLoop()
        #endif
    }

    #if os(iOS)
    private func startAmbientTriageLoop() {
        Task {
            while true {
                try? await Task.sleep(for: .seconds(60))  // Every 60s
                guard speechRecognizer.isAmbientActive else { continue }

                let fragments = speechRecognizer.consumeFragments()
                guard !fragments.isEmpty else { continue }

                // Batch all fragments into one triage request
                let batch = fragments.map { "[\($0.timestamp.formatted(.dateTime.hour().minute().second()))]: \($0.text)" }.joined(separator: "\n")

                let triagePrompt = """
                These are ambient speech fragments captured from my environment. \
                Analyze each and classify as INSIGHT (worth capturing as a thought) \
                or NOISE (casual conversation, filler, irrelevant). \
                For each INSIGHT, extract the core idea in one refined sentence.

                Fragments:
                \(batch)

                Respond with only the insights, one per line. If nothing is useful, respond with "NO_INSIGHTS".
                """

                // Try local LLM first, then cloud
                let llm = LocalLLMEngine.shared
                var triageResult: String?

                if llm.isReady {
                    triageResult = try? await llm.respond(to: triagePrompt)
                }

                if triageResult == nil || triageResult?.isEmpty == true {
                    let cloudResult = await BeagleClient.shared.chat(prompt: triagePrompt, system: "You are a cognitive filter for an exocortex. Extract only genuine intellectual insights from ambient speech. Be aggressive about filtering noise.")
                    triageResult = cloudResult.value?.response
                }

                // Process triage results
                if let result = triageResult, result != "NO_INSIGHTS" && !result.isEmpty {
                    let insights = result.components(separatedBy: "\n").filter { !$0.isEmpty && !$0.contains("NO_INSIGHTS") }
                    for insight in insights {
                        _ = await cognitive.captureThought(text: insight, source: "ambient-whisper")
                    }
                }
            }
        }
    }
    #endif

    private func timeGreeting() -> String {
        let hour = Calendar.current.component(.hour, from: Date())
        switch hour {
        case 5..<12:  return "Good morning."
        case 12..<17: return "Good afternoon."
        case 17..<22: return "Good evening."
        default:      return "Still thinking?"
        }
    }

    // MARK: - Provocation generation (on-device LLM)

    @State private var isGeneratingProvocations = false

    private func generateProvocations() {
        guard !isGeneratingProvocations else { return }
        isGeneratingProvocations = true

        Task {
            let projects = catalog.projects.map(\.projectSlug)
            let thoughts = cognitive.recentThoughts.prefix(3).compactMap { $0.refinedText ?? $0.rawText }
            let jobs = cognitive.activeJobs.prefix(5).map { (kind: $0.kind ?? "unknown", status: $0.status ?? "unknown") }
            let counts = (on: catalog.postureCounts.alwaysOn, warm: catalog.postureCounts.warm, cold: catalog.postureCounts.cold)

            if let raw = await FoundationModelsAgent.shared.generateProvocations(
                projects: projects,
                recentThoughts: Array(thoughts),
                recentJobs: jobs,
                postureCounts: counts
            ) {
                let parsed = parseProvocations(raw)
                if !parsed.isEmpty {
                    withAnimation(BeagleMotion.slow) {
                        provocations = parsed
                    }
                } else {
                    // LLM returned something but parsing failed — use fallback
                    withAnimation(BeagleMotion.slow) {
                        provocations = fallbackProvocations()
                    }
                }
            } else {
                // LLM unavailable — use fallback
                withAnimation(BeagleMotion.slow) {
                    provocations = fallbackProvocations()
                }
            }

            isGeneratingProvocations = false
        }
    }

    private func parseProvocations(_ raw: String) -> [Provocation] {
        let icons = ["brain.head.profile", "sparkles", "lightbulb.max"]
        let colors = [BeagleTheme.truthRemembered, BeagleTheme.truthObserved, BeagleTheme.postureWarm]

        return raw
            .components(separatedBy: "\n")
            .filter { $0.contains("|") }
            .prefix(3)
            .enumerated()
            .map { index, line in
                let parts = line.components(separatedBy: "|").map { $0.trimmingCharacters(in: .whitespaces) }
                return Provocation(
                    title: parts.count > 0 ? parts[0] : "Explore",
                    subtitle: parts.count > 1 ? parts[1] : "",
                    icon: icons[index % icons.count],
                    color: colors[index % colors.count],
                    prompt: parts.count > 2 ? parts[2] : parts.first ?? ""
                )
            }
    }

    private func fallbackProvocations() -> [Provocation] {
        var result: [Provocation] = []

        // Job errors are always relevant
        if let lastError = cognitive.activeJobs.first(where: { $0.status == "error" }) {
            result.append(Provocation(
                title: "\(lastError.kind ?? "Job") failed",
                subtitle: "Want to investigate what went wrong?",
                icon: "exclamationmark.triangle",
                color: BeagleTheme.stateError,
                prompt: "My \(lastError.kind ?? "pipeline") job failed. Help me debug it."
            ))
        }

        // Continue last thought
        if let thought = cognitive.recentThoughts.first, let text = thought.refinedText ?? thought.rawText {
            result.append(Provocation(
                title: "Continue your last thought",
                subtitle: String(text.prefix(60)) + (text.count > 60 ? "..." : ""),
                icon: "text.bubble",
                color: BeagleTheme.truthObserved,
                prompt: "Continue developing this thought: \(text). What are the implications and next steps?"
            ))
        }

        // Generic research spark
        result.append(Provocation(
            title: "Cross-domain connections",
            subtitle: "What unexpected links exist in your research?",
            icon: "brain.head.profile",
            color: BeagleTheme.truthRemembered,
            prompt: "Look at my active projects and find unexpected cross-domain connections that could lead to novel insights."
        ))

        return Array(result.prefix(3))
    }
}

// MARK: - Provocation model

struct Provocation: Identifiable {
    let id = UUID()
    let title: String
    let subtitle: String
    let icon: String
    let color: Color
    let prompt: String
}
