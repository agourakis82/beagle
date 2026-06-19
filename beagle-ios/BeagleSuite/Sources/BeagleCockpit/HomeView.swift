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
import SwiftData

struct HomeView: View {
    @Environment(CatalogStore.self) private var catalog
    @Environment(CognitiveStore.self) private var cognitive
    @Environment(PhysioStore.self) private var physio
    @Environment(\.modelContext) private var modelContext
    @AppStorage("selectedTab") private var selectedTab = 0
    @AppStorage("pinnedLaneQuestionsJSON") private var pinnedLaneQuestionsJSON = "{}"
    @AppStorage("cachedLaneResultsJSON") private var cachedLaneResultsJSON = "[]"
    @State private var conversation: ConversationStore
    @State private var inputText = ""
    @State private var provocations: [Provocation] = []
    @State private var greeting = ""
    @State private var hasAppeared = false
    @State private var serendipityInsight: String?
    @State private var chaosProvocation: SerendipityProvocation?
    @State private var morningBrief: String?
    @State private var searchText = ""
    @State private var milestoneToShow: Int?
    @State private var lastSeenThoughtCount = 0
    @State private var homeSummary: Truthful<MobileHomeSummary>?
    @State private var workLanes: [ProjectLaneState] = []
    @State private var inputFocusRequest = 0
    @State private var metacognitive = MetacognitiveDialogue.shared
    @State private var showModelManager = false
    #if os(iOS)
    @State private var speechRecognizer = SpeechRecognizer()
    #endif

    init() {
        _conversation = State(initialValue: ConversationStore(preferLocal: false))
    }

    var body: some View {
        VStack(spacing: 0) {
            // Clarity pass: Home IS the thinking/chat surface.
            // Empty conversation = a clean launchpad — the invitation sits just above the
            // input (no greeting hero, no void). Active conversation = the thread scrolls.
            if conversation.isEmpty {
                VStack(alignment: .leading, spacing: BeagleSpacing.lg) {
                    Spacer(minLength: BeagleSpacing.md)
                    if let summary = homeSummary?.value,
                       summary.activeAgentsCount != nil || !(summary.laneResults?.isEmpty ?? true) {
                        clusterBriefingCard(summary)
                    }
                    homeInvitation
                    Spacer(minLength: BeagleSpacing.md)
                }
                .frame(maxWidth: 820, alignment: .leading)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, BeagleSpacing.lg)
            } else {
                ScrollView {
                    conversationSection
                        .padding(.horizontal, BeagleSpacing.lg)
                        .padding(.top, BeagleSpacing.xl)
                        .padding(.bottom, BeagleSpacing.jumbo)
                        .scrollTargetLayout()
                        .frame(maxWidth: 820)
                        .frame(maxWidth: .infinity)
                }
            }

            // Single prominent input anchored at the bottom, route picker just above it.
            VStack(spacing: BeagleSpacing.xs) {
                discussionProfileStrip
                exocortexInput
            }
            .padding(.horizontal, BeagleSpacing.lg)
            .padding(.top, BeagleSpacing.sm)
            .padding(.bottom, BeagleSpacing.sm)
            .background(.background.secondary.opacity(0.6))
        }
        .background { HomeGradient(thoughtCount: cognitive.recentThoughts.count, hasJobs: !cognitive.activeJobs.isEmpty) }
        .navigationTitle("Beagle")
        .navigationBarTitleDisplayModeIfAvailable(.inline)
        .overlay {
            if let milestone = milestoneToShow {
                MilestoneCelebration(count: milestone) {
                    milestoneToShow = nil
                }
                .transition(.opacity)
                .zIndex(100)
            }
        }
        .toolbar {
            // Wordmark MOCK (Option B): branded inline lockup in place of the
            // plain large title — teal brain glyph + "Beagle".
            ToolbarItem(placement: .principal) {
                HStack(spacing: 6) {
                    Image(systemName: "brain")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(BeagleTheme.truthObserved)
                    Text("Beagle")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(BeagleTheme.textPrimary)
                        .tracking(0.4)
                }
            }

            ToolbarItem(placement: homeToolbarPlacement) {
                NavigationLink {
                    DeepExplorationView()
                } label: {
                    Label("Explore", systemImage: "scope")
                        .foregroundStyle(BeagleTheme.textSecondary)
                }
            }

            ToolbarItem(placement: homeToolbarPlacement) {
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
        .sheet(isPresented: $showModelManager) {
            NavigationStack {
                ModelSettingsView()
            }
        }
        .refreshable {
            async let c: () = catalog.refresh()
            async let g: () = cognitive.refresh()
            async let p: () = physio.refresh(requestAuthorization: true)
            async let s = CockpitClient.shared.mobileSummary()
            let summary = await s
            applyHomeSummary(summary)
            _ = await (c, g, p)
            await refreshWorkLanes()
            applyPhysioConversationContext()
            runMetacognitiveCheck()
            generateProvocations()
        }
        .onChange(of: cognitive.recentThoughts.count) { oldCount, newCount in
            checkMilestone(oldCount: oldCount, newCount: newCount)
        }
    }

    private var homeToolbarPlacement: ToolbarItemPlacement {
        #if os(macOS)
        return .automatic
        #else
        return .topBarTrailing
        #endif
    }

    private func checkMilestone(oldCount: Int, newCount: Int) {
        let milestones = [1, 10, 50, 100, 500]
        for m in milestones {
            if oldCount < m && newCount >= m {
                milestoneToShow = m
                #if os(iOS)
                BeagleHaptics.capture()
                #endif
                break
            }
        }
    }

    // MARK: - Greeting (recognition, not template)

    private var previewSignalCard: some View {
        GlassPanel(elevation: .floating, truth: .observed) {
            VStack(alignment: .leading, spacing: BeagleSpacing.md) {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: BeagleSpacing.xxs) {
                        Text(BuildInfo.previewLabel)
                            .font(BeagleFont.caption.font)
                            .fontWeight(.semibold)
                            .foregroundStyle(BeagleTheme.postureWarm)
                            .textCase(.uppercase)
                            .tracking(0.9)
                        Text("Device Mind + Cluster Mind")
                            .font(BeagleFont.title2.font)
                            .fontWeight(.semibold)
                            .foregroundStyle(BeagleTheme.textPrimary)
                    }
                    Spacer()
                    PresencePill(label: BuildInfo.detailedLabel, systemImage: "bolt.fill", tint: BeagleTheme.truthObserved)
                }

                Text("This build makes the bridge explicit: the private intelligence on your device is visible, the cluster is visible, and the handoff between them should finally feel alive.")
                    .font(BeagleFont.body.font)
                    .foregroundStyle(BeagleTheme.textPrimary)
                    .lineSpacing(3)

                CognitiveBridgeField(
                    localWeight: LocalLLMEngine.shared.isReady ? 1.0 : 0.55,
                    bridgeWeight: cognitive.serverReachable ? 1.0 : 0.62,
                    clusterWeight: cognitive.serverReachable ? 0.96 : 0.38,
                    emphasis: .balanced
                )

                HStack(spacing: BeagleSpacing.xs) {
                    PresencePill(label: "On Device visible", systemImage: "iphone.gen3.radiowaves.left.and.right", tint: BeagleTheme.truthDeclared)
                    PresencePill(label: "Cluster presence visible", systemImage: "server.rack", tint: BeagleTheme.truthObserved)
                }
            }
        }
        .opacity(hasAppeared ? 1 : 0)
        .offset(y: hasAppeared ? 0 : 10)
        .animation(.easeOut(duration: 0.5), value: hasAppeared)
    }

    private var shellPresenceCard: some View {
        PresenceFieldCard(
            state: shellPresenceState,
            eyebrow: "Living Shell",
            title: shellPresenceTitle,
            body: shellPresenceBody,
            detail: shellPresenceDetail,
            truth: shellPresenceTruth
        ) {
            HStack(spacing: BeagleSpacing.xs) {
                PresencePill(
                    label: LocalLLMEngine.shared.isReady ? "device mind awake" : "device mind quiet",
                    systemImage: "iphone.gen3.radiowaves.left.and.right",
                    tint: LocalLLMEngine.shared.isReady ? BeagleTheme.truthDeclared : BeagleTheme.truthStale
                )
                PresencePill(
                    label: cognitive.serverReachable ? "cluster within reach" : "cluster holding at distance",
                    systemImage: "server.rack",
                    tint: cognitive.serverReachable ? BeagleTheme.truthObserved : BeagleTheme.postureWarm
                )
            }
        }
    }

    private var greetingSection: some View {
        VStack(alignment: .leading, spacing: BeagleSpacing.sm) {
            TypewriterText(
                greeting,
                font: BeagleFont.largeTitle.font,
                foregroundStyle: AnyShapeStyle(BeagleTheme.accent),
                speed: 24
            )
            .opacity(hasAppeared ? 1 : 0)
            .offset(y: hasAppeared ? 0 : 10)
            .animation(.easeOut(duration: 0.5), value: hasAppeared)

            Text(contextLine)
                .font(BeagleFont.body.font)
                .foregroundStyle(Color.primary.opacity(0.72))
                .lineSpacing(3)
                .opacity(hasAppeared ? 1 : 0)
                .offset(y: hasAppeared ? 0 : 8)
                .animation(.easeOut(duration: 0.8).delay(0.2), value: hasAppeared)

            // Growth + safety
            HStack(spacing: BeagleSpacing.md) {
                if !cognitive.recentThoughts.isEmpty {
                    HStack(spacing: BeagleSpacing.xxs) {
                        Image(systemName: "leaf.fill")
                            .font(.system(size: 9))
                        Text("\(cognitive.recentThoughts.count) thoughts")
                            .font(BeagleFont.caption2.font)
                    }
                    .foregroundStyle(BeagleTheme.truthObserved.opacity(0.6))
                }

                if LocalLLMEngine.shared.isReady {
                    HStack(spacing: BeagleSpacing.xxs) {
                        Image(systemName: "lock.shield.fill")
                            .font(.system(size: 9))
                        Text("Device mind")
                            .font(BeagleFont.caption2.font)
                    }
                    .foregroundStyle(BeagleTheme.truthObserved.opacity(0.5))
                }

                intensityPill
            }
            .opacity(hasAppeared ? 1 : 0)
            .animation(.easeOut(duration: 0.6).delay(0.4), value: hasAppeared)
        }
    }

    private var livingBriefingCard: some View {
        let runningAgents = cognitive.state.value?.agentSessions?.filter { ($0.readyReplicas ?? 0) > 0 } ?? []
        let summary = homeSummary?.value
        let activeAgentCount = summary?.activeAgentsCount ?? runningAgents.count
        let activeSessionCount = summary?.activeSessionsCount ?? runningAgents.count
        let clusterThoughts = cognitive.recentThoughts.filter { $0.residency == .clusterMemory }.count
        let localThoughts = cognitive.recentThoughts.filter { $0.residency == .deviceOnly }.count
        let localWeight = LocalLLMEngine.shared.isReady ? 1.0 : 0.35
        let bridgeWeight = cognitive.serverReachable ? 0.95 : 0.45
        let clusterWeight = activeAgentCount == 0 ? min(1.0, 0.35 + Double(clusterThoughts) * 0.12) : 1.0

        return GlassPanel(elevation: .floating, truth: cognitive.serverReachable ? .observed : .declared) {
            VStack(alignment: .leading, spacing: BeagleSpacing.md) {
                HStack(spacing: BeagleSpacing.xs) {
                    Image(systemName: "sparkles.rectangle.stack")
                        .font(.system(size: 14))
                        .foregroundStyle(BeagleTheme.truthObserved)
                    Text("Living Briefing")
                        .font(BeagleFont.caption.font)
                        .fontWeight(.medium)
                        .foregroundStyle(BeagleTheme.textTertiary)
                        .textCase(.uppercase)
                        .tracking(0.5)
                    Spacer()
                    TruthBadge(cognitive.serverReachable ? .observed : .declared, compact: true)
                }

                Text("The mind in your hand is awake. The bridge is visible. The larger system is \(cognitive.serverReachable ? "within reach" : "quiet for now").")
                    .font(BeagleFont.subheadline.font)
                    .foregroundStyle(BeagleTheme.textPrimary)
                    .lineSpacing(2)

                CognitiveBridgeField(
                    localWeight: localWeight,
                    bridgeWeight: bridgeWeight,
                    clusterWeight: clusterWeight,
                    emphasis: .balanced
                )

                HStack(spacing: BeagleSpacing.sm) {
                    briefingNode(
                        title: "Device Mind",
                        subtitle: LocalLLMEngine.shared.isReady ? "\(localThoughts) private thread\(localThoughts == 1 ? "" : "s")" : "Local model offline",
                        systemImage: "iphone",
                        tint: BeagleTheme.truthDeclared
                    )
                    briefingNode(
                        title: "Bridge",
                        subtitle: cognitive.serverReachable
                            ? (summary?.lastMemorySyncTime.flatMap { relativeTime(from: $0) }.map { "Last sync \($0)" } ?? "Sync is live")
                            : "Holding local state",
                        systemImage: "arrow.left.and.right.circle",
                        tint: BeagleTheme.postureWarm
                    )
                    briefingNode(
                        title: "Cluster Mind",
                        subtitle: activeAgentCount == 0
                            ? "\(clusterThoughts) memory thread\(clusterThoughts == 1 ? "" : "s")"
                            : "\(activeAgentCount) agent\(activeAgentCount == 1 ? "" : "s") active · \(activeSessionCount) session\(activeSessionCount == 1 ? "" : "s")",
                        systemImage: "server.rack",
                        tint: BeagleTheme.truthObserved
                    )
                }

                if let clusterHealth = summary?.clusterHealth, !clusterHealth.isEmpty {
                    PresencePill(label: "Cluster \(clusterHealth.capitalized)", systemImage: "waveform.path.ecg", tint: BeagleTheme.truthObserved)
                }
            }
        }
        .opacity(hasAppeared ? 1 : 0)
        .offset(y: hasAppeared ? 0 : 12)
        .animation(.easeOut(duration: 0.55).delay(0.12), value: hasAppeared)
    }

    private func briefingNode(title: String, subtitle: String, systemImage: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: BeagleSpacing.xs) {
            PresencePill(label: title, systemImage: systemImage, tint: tint)
            Text(subtitle)
                .font(BeagleFont.caption.font)
                .foregroundStyle(BeagleTheme.textSecondary)
                .lineLimit(2)
                .lineSpacing(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(BeagleSpacing.sm)
        .background(
            RoundedRectangle(cornerRadius: BeagleRadius.md)
                .fill(tint.opacity(0.05))
        )
        .overlay(
            RoundedRectangle(cornerRadius: BeagleRadius.md)
                .strokeBorder(tint.opacity(0.08), lineWidth: 1)
        )
    }

    /// Circadian gradient: warm gold in morning, teal in afternoon, soft violet at night.
    private var circadianGradientColors: [Color] {
        let hour = Calendar.current.component(.hour, from: Date())
        switch hour {
        case 5..<10:  return [BeagleTheme.postureWarm, BeagleTheme.textPrimary]         // morning gold
        case 10..<17: return [BeagleTheme.textPrimary, BeagleTheme.truthObserved.opacity(0.7)]  // day teal
        case 17..<21: return [BeagleTheme.textPrimary, BeagleTheme.truthRemembered.opacity(0.6)] // evening sky
        default:      return [BeagleTheme.textPrimary, Color(hue: 270/360, saturation: 0.3, brightness: 0.7)] // night violet
        }
    }

    private var contextLine: String {
        let thoughts = cognitive.recentThoughts
        let jobs = cognitive.activeJobs

        // Recognition: acknowledge what the user has been working on
        if let latest = thoughts.first, let text = latest.refinedText ?? latest.rawText {
            let snippet = String(text.prefix(60))
            if jobs.isEmpty {
                return "Your last thread: \"\(snippet)\(text.count > 60 ? "..." : "")\" — want to continue from the device, or carry it into the cluster?"
            } else {
                return "\(jobs.count) job\(jobs.count > 1 ? "s" : "") running. Last thread: \"\(snippet)\(text.count > 60 ? "..." : "")\""
            }
        }

        // Returning user with no recent thoughts
        let hour = Calendar.current.component(.hour, from: Date())
        if hour >= 0 && hour < 5 {
            return "Late night thinking? Start privately on device, then decide what deserves the larger mind."
        }
        return "Start with a thought."
    }

    private var shellPresenceState: BeaglePresenceState {
        if !cognitive.serverReachable && !cognitive.activeJobs.isEmpty {
            return .strained
        }
        if !cognitive.activeJobs.isEmpty || !(cognitive.state.value?.agentSessions?.isEmpty ?? true) {
            return .active
        }
        if LocalLLMEngine.shared.isReady || cognitive.serverReachable {
            return .attentive
        }
        return .dormant
    }

    private var shellPresenceTitle: String {
        switch shellPresenceState {
        case .active:
            return "The whole shell feels awake now"
        case .attentive:
            return "Beagle is waiting in both directions"
        case .strained:
            return "The shell is holding shape through signal strain"
        case .dormant:
            return "Even quiet, the shell remembers your last thread"
        }
    }

    private var shellPresenceBody: String {
        if !cognitive.activeJobs.isEmpty {
            return "\(cognitive.activeJobs.count) cluster job\(cognitive.activeJobs.count == 1 ? "" : "s") are still moving. This surface should feel less like a dashboard and more like a living bridge between your hand and the lab."
        }
        if let summary = homeSummary?.value, let activeAgentsCount = summary.activeAgentsCount, activeAgentsCount > 0 {
            return "\(activeAgentsCount) agent\(activeAgentsCount == 1 ? "" : "s") are awake in the cluster. Start privately, or let the larger mind answer back."
        }
        if cognitive.serverReachable {
            return "Your private thoughts, the remote memory, and the command surfaces now belong to one room. You should feel hosted, not dropped into tooling."
        }
        return "The local mind is still here even when the bridge goes quiet. Capture the thread first; the larger system can rejoin when the signal returns."
    }

    private var shellPresenceDetail: String {
        let thoughtCount = cognitive.recentThoughts.count
        let jobCount = cognitive.runningJobCount
        let syncClause = cognitive.serverReachable ? "sync is live" : "sync is paused"
        return "\(thoughtCount) thought\(thoughtCount == 1 ? "" : "s") in memory · \(jobCount) live job\(jobCount == 1 ? "" : "s") · \(syncClause)"
    }

    private var shellPresenceTruth: TruthMode {
        switch shellPresenceState {
        case .active:
            return .observed
        case .attentive:
            return .remembered
        case .dormant:
            return .declared
        case .strained:
            return .stale
        }
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
                .buttonStyle(ScalePress())
                .staggeredAppear(index: index + 2, delay: 0.1)
            }
        }
    }

    private func provocationCard(_ p: Provocation) -> some View {
        HStack(spacing: BeagleSpacing.sm) {
            ZStack {
                Circle()
                    .fill(p.color.opacity(0.08))
                    .frame(width: 36, height: 36)
                Image(systemName: p.icon)
                    .font(.system(size: 15))
                    .foregroundStyle(p.color)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(p.title)
                    .font(BeagleFont.subheadline.font)
                    .fontWeight(.medium)
                    .foregroundStyle(BeagleTheme.textPrimary)
                    .lineLimit(1)
                Text(p.subtitle)
                    .font(BeagleFont.caption.font)
                    .foregroundStyle(BeagleTheme.textSecondary)
                    .lineLimit(2)
                    .lineSpacing(1)
            }

            Spacer()

            Image(systemName: "arrow.up.right")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(p.color.opacity(0.5))
        }
        .frame(minHeight: 56)
        .padding(.horizontal, BeagleSpacing.md)
        .padding(.vertical, BeagleSpacing.sm)
        .background(
            RoundedRectangle(cornerRadius: BeagleRadius.lg)
                .fill(.regularMaterial)
                .opacity(0.6)
        )
        #if os(iOS)
        .glassEffect(.regular.tint(p.color.opacity(0.03)), in: .rect(cornerRadius: BeagleRadius.lg))
        #endif
        .overlay(
            RoundedRectangle(cornerRadius: BeagleRadius.lg)
                .strokeBorder(p.color.opacity(0.08), lineWidth: 1)
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
                SoftSeparator()

                HStack(spacing: BeagleSpacing.xs) {
                    BreathingDot(color: BeagleTheme.truthRemembered, size: 6)
                    Text("LARGER MIND")
                        .font(BeagleFont.caption.font)
                        .fontWeight(.medium)
                        .foregroundStyle(BeagleTheme.textTertiary)
                        .tracking(0.5)
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
                SoftSeparator()

                Text("RECENT THOUGHTS")
                    .font(BeagleFont.caption.font)
                    .fontWeight(.medium)
                    .foregroundStyle(BeagleTheme.textTertiary)
                    .tracking(0.5)

                ForEach(Array(cognitive.recentThoughts.prefix(5).enumerated()), id: \.element.id) { index, thought in
                    let thoughtText = thought.refinedText ?? thought.rawText ?? ""
                    Button {
                        Task { await conversation.sendMessage("Expand on this thought: \(thoughtText)") }
                    } label: {
                        HStack(alignment: .top, spacing: BeagleSpacing.sm) {
                            if thought.residency == .clusterMemory {
                                BreathingDot(color: BeagleTheme.truthObserved, size: 6)
                                    .padding(.top, 7)
                            } else {
                                Circle()
                                    .fill(BeagleTheme.truthDeclared)
                                    .frame(width: 6, height: 6)
                                    .padding(.top, 7)
                            }

                            Text(thoughtText.isEmpty ? "—" : thoughtText)
                                .font(BeagleFont.footnote.font)
                                .foregroundStyle(BeagleTheme.textPrimary)
                                .lineLimit(2)
                                .multilineTextAlignment(.leading)
                                .lineSpacing(2)

                            PresencePill(
                                label: thought.effectiveSyncState.label,
                                systemImage: thought.effectiveSyncState.systemImage,
                                tint: tint(for: thought.effectiveSyncState)
                            )

                            Spacer()

                            if let age = thought.createdAt.flatMap({ relativeTime(from: $0) }) {
                                Text(age)
                                    .font(BeagleFont.caption2.font)
                                    .foregroundStyle(BeagleTheme.textTertiary)
                                    .padding(.top, 4)
                            }
                        }
                    }
                    .buttonStyle(ScalePress())
                    .staggeredAppear(index: index)
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

    /// Clean empty-state invitation — replaces the old prompt-card scaffolding.
    /// The input bar below is where you actually type; this is just the prompt.
    /// Starter prompts for the empty launchpad — tappable, mirroring Recall's "TRY"
    /// affordances so an empty Home offers a way in instead of a blank void.
    private var starterPrompts: [String] {
        [
            "Help me think through a hard decision",
            "Summarize what the cluster did today",
            "Draft a plan for my next work session"
        ]
    }

    private var homeInvitation: some View {
        VStack(alignment: .leading, spacing: BeagleSpacing.md) {
            // Brand mark: a teal-tinted badge (PresenceFieldCard idiom) instead
            // of a bare glyph — gives the empty state an identity anchor.
            ZStack {
                Circle()
                    .fill(BeagleTheme.truthObserved.opacity(0.16))
                    .overlay(Circle().strokeBorder(BeagleTheme.truthObserved.opacity(0.4), lineWidth: 1))
                    .frame(width: 56, height: 56)
                Image(systemName: "brain")
                    .font(.system(size: 26, weight: .medium))
                    .foregroundStyle(BeagleTheme.truthObserved)
            }

            VStack(alignment: .leading, spacing: BeagleSpacing.xxs) {
                Text("What are you working on?")
                    .font(BeagleFont.title2.font)
                    .fontWeight(.semibold)
                    .foregroundStyle(BeagleTheme.textPrimary)
                Text("Type a thought below — Beagle stays with it.")
                    .font(BeagleFont.subheadline.font)
                    .foregroundStyle(BeagleTheme.textSecondary)
            }

            VStack(alignment: .leading, spacing: BeagleSpacing.xs) {
                ForEach(starterPrompts, id: \.self) { prompt in
                    Button {
                        inputText = prompt
                        Task { await conversation.sendMessage(prompt) }
                    } label: {
                        HStack(spacing: BeagleSpacing.xs) {
                            Image(systemName: "arrow.up.right")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(BeagleTheme.textTertiary)
                            Text(prompt)
                                .font(BeagleFont.subheadline.font)
                                .foregroundStyle(BeagleTheme.textSecondary)
                                .multilineTextAlignment(.leading)
                            Spacer(minLength: 0)
                        }
                        .padding(.vertical, BeagleSpacing.xs)
                        .padding(.horizontal, BeagleSpacing.sm)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(
                            RoundedRectangle(cornerRadius: BeagleRadius.md)
                                .fill(BeagleTheme.surface1.opacity(0.5))
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.top, BeagleSpacing.xs)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, BeagleSpacing.md)
    }

    // MARK: - Living briefing (empty Home answers "what should I look at?")

    /// Cluster briefing sourced from the live /api/mobile/v1/summary. Every value carries a
    /// TruthChip so freshness is glanceable — the cluster header is live (just fetched), the
    /// returned-work item shows its real age (which is often days/months old).
    @ViewBuilder
    private func clusterBriefingCard(_ summary: MobileHomeSummary) -> some View {
        let lane = summary.laneResults?.first(where: { $0.readyForOpen }) ?? summary.laneResults?.first
        VStack(alignment: .leading, spacing: BeagleSpacing.sm) {
            HStack {
                Text("CLUSTER BRIEFING")
                    .font(BeagleFont.dataSmall.font)
                    .tracking(1)
                    .foregroundStyle(BeagleTheme.textTertiary)
                Spacer()
                if let t = homeSummary {
                    TruthBadge(t)
                }
            }

            HStack(spacing: BeagleSpacing.xs) {
                Circle()
                    .fill(briefingHealthColor(summary.clusterHealth))
                    .frame(width: 7, height: 7)
                Text(briefingClusterLine(summary))
                    .font(BeagleFont.subheadline.font)
                    .foregroundStyle(BeagleTheme.textPrimary)
            }

            if let lane {
                Divider().overlay(Color.white.opacity(0.06))
                VStack(alignment: .leading, spacing: BeagleSpacing.xxs) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(lane.displayHeadline)
                            .font(BeagleFont.subheadline.font.weight(.semibold))
                            .foregroundStyle(BeagleTheme.textPrimary)
                            .lineLimit(1)
                        Spacer(minLength: BeagleSpacing.xs)
                        let ts = lane.latestResultAt.iso8601Date
                        TruthBadge(.observed.aged(ts), observedAt: ts, compact: true)
                    }
                    Text("\(lane.projectSlug) · \(lane.displayStateLabel)")
                        .font(BeagleFont.dataSmall.font)
                        .foregroundStyle(BeagleTheme.textSecondary)

                    if let action = lane.recommendedAction, !action.isEmpty {
                        Button {
                            inputText = action
                            Task { await conversation.sendMessage("About \(lane.projectSlug): \(action)") }
                        } label: {
                            HStack(spacing: BeagleSpacing.xs) {
                                Image(systemName: "arrow.forward.circle.fill")
                                    .font(.system(size: 13))
                                    .foregroundStyle(BeagleTheme.truthObserved)
                                Text(action)
                                    .font(BeagleFont.subheadline.font)
                                    .foregroundStyle(BeagleTheme.textSecondary)
                                    .multilineTextAlignment(.leading)
                                Spacer(minLength: 0)
                            }
                        }
                        .buttonStyle(.plain)
                        .padding(.top, 2)
                    }
                }
            }
        }
        .padding(BeagleSpacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: BeagleRadius.lg)
                .fill(BeagleTheme.surface1.opacity(0.6))
        )
        .overlay(
            RoundedRectangle(cornerRadius: BeagleRadius.lg)
                .strokeBorder(Color.white.opacity(0.06), lineWidth: 1)
        )
    }

    private func briefingHealthColor(_ health: String?) -> Color {
        switch (health ?? "").lowercased() {
        case "healthy", "ok", "ready", "green":  return BeagleTheme.truthObserved
        case "unhealthy", "down", "critical", "red": return BeagleTheme.stateError
        default:                                  return BeagleTheme.truthRemembered
        }
    }

    private func briefingClusterLine(_ s: MobileHomeSummary) -> String {
        let health = s.clusterHealth?.isEmpty == false ? s.clusterHealth! : "unknown"
        let agents = s.activeAgentsCount ?? 0
        let sessions = s.activeSessionsCount ?? 0
        var parts = [health, "\(agents) agent\(agents == 1 ? "" : "s") active"]
        if sessions > 0 { parts.append("\(sessions) session\(sessions == 1 ? "" : "s")") }
        return parts.joined(separator: " · ")
    }

    private var discussionFieldCard: some View {
        GlassPanel(elevation: .floating, truth: discussionTruth) {
            VStack(alignment: .leading, spacing: BeagleSpacing.md) {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: BeagleSpacing.xxs) {
                        Text("Idea Field")
                            .font(BeagleFont.caption.font)
                            .fontWeight(.semibold)
                            .foregroundStyle(BeagleTheme.truthObserved)
                            .textCase(.uppercase)
                            .tracking(0.8)
                        Text(conversation.isEmpty ? "What are you working on?" : "Continue the thread")
                            .font(BeagleFont.title3.font)
                            .fontWeight(.semibold)
                            .foregroundStyle(BeagleTheme.textPrimary)
                    }
                    Spacer()
                    PresencePill(
                        label: discussionProfileLabel,
                        systemImage: conversation.discussionProfile.iconName,
                        tint: BeagleTheme.truthRemembered
                    )
                }

                Text(discussionNarrative)
                    .font(BeagleFont.footnote.font)
                    .foregroundStyle(BeagleTheme.textSecondary)
                    .lineSpacing(2)

                if let pinnedQuestion = pinnedQuestionForCurrentLane {
                    pinnedQuestionCard(pinnedQuestion)
                }

                if !conversation.isEmpty {
                    whereWeLeftOffCard
                }

                discussionProfileStrip

                if conversation.isEmpty {
                    emptyDiscussionState
                } else {
                    conversationSection
                }
            }
        }
    }

    private var conversationSection: some View {
        VStack(alignment: .leading, spacing: BeagleSpacing.xs) {
            ForEach(conversation.messages.suffix(6)) { message in
                ChatBubbleView(
                    message: message,
                    onRegenerate: message.role == .assistant ? {
                        Task { await conversation.regenerateLastResponse() }
                    } : nil
                )

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

    private var emptyDiscussionState: some View {
        VStack(alignment: .leading, spacing: BeagleSpacing.md) {
            HStack(spacing: BeagleSpacing.xs) {
                PresencePill(
                    label: focusedLane.map { projectDisplayName($0.project.projectSlug) } ?? "No lane selected",
                    systemImage: "scope",
                    tint: BeagleTheme.truthObserved
                )
                PresencePill(
                    label: LocalLLMEngine.shared.isReady ? "Device mind ready" : "Cluster route ready",
                    systemImage: LocalLLMEngine.shared.isReady ? "iphone" : "server.rack",
                    tint: LocalLLMEngine.shared.isReady ? BeagleTheme.truthObserved : BeagleTheme.truthRemembered
                )
            }

            Text("Or start with a prompt:")
                .font(BeagleFont.footnote.font)
                .foregroundStyle(BeagleTheme.textSecondary)

            VStack(spacing: BeagleSpacing.xs) {
                ForEach(discussionStarters, id: \.self) { starter in
                    Button {
                        prepareDraft(starter)
                    } label: {
                        HStack(spacing: BeagleSpacing.sm) {
                            Image(systemName: "arrow.up.right.circle")
                                .font(.system(size: 14))
                                .foregroundStyle(BeagleTheme.truthObserved)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(starter)
                                    .font(BeagleFont.footnote.font)
                                    .foregroundStyle(BeagleTheme.textPrimary)
                                    .multilineTextAlignment(.leading)
                                    .lineLimit(3)
                                Text("Load this into the composer")
                                    .font(BeagleFont.caption2.font)
                                    .foregroundStyle(BeagleTheme.textTertiary)
                            }
                            Spacer()
                        }
                        .padding(.horizontal, BeagleSpacing.md)
                        .padding(.vertical, BeagleSpacing.sm)
                        .background(
                            RoundedRectangle(cornerRadius: BeagleRadius.lg)
                                .fill(BeagleTheme.surface1.opacity(0.5))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: BeagleRadius.lg)
                                .strokeBorder(BeagleTheme.truthObserved.opacity(0.08), lineWidth: 1)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    /// The single "who answers" control. The leading pill reflects the *active engine*
    /// — an explicitly loaded on-device model takes precedence over the cloud route
    /// (matching `ConversationStore.sendMessage`). The menu unifies both: pick an
    /// on-device model (loads it → routes local) or a cloud/cluster route (unloads
    /// local → routes cloud).
    private var discussionProfileStrip: some View {
        HStack(spacing: BeagleSpacing.sm) {
            PresencePill(
                label: activeRoutePill.label,
                systemImage: activeRoutePill.icon,
                tint: activeRoutePill.tint
            )

            Menu {
                if LocalLLMEngine.shared.isAvailable {
                    Section("On device") {
                        ForEach(homeLocalModels) { model in
                            Button {
                                Task { await LocalLLMEngine.shared.load(model) }
                            } label: {
                                Label(homeLocalModelLabel(model), systemImage: localModelIsActive(model) ? "checkmark" : "brain")
                            }
                        }
                        Button {
                            showModelManager = true
                        } label: {
                            Label("Manage models…", systemImage: "slider.horizontal.3")
                        }
                    }
                }

                Section("Cloud / cluster") {
                    ForEach(DiscussionProfile.allCases) { profile in
                        Button {
                            selectCloudRoute(profile)
                        } label: {
                            Label("\(profile.label) · \(profile.subtitle)", systemImage: profile.iconName)
                        }
                    }
                }
            } label: {
                Label("Change Route", systemImage: "arrow.triangle.branch")
                    .font(BeagleFont.caption.font)
                    .foregroundStyle(BeagleTheme.textSecondary)
                    .padding(.horizontal, BeagleSpacing.sm)
                    .padding(.vertical, BeagleSpacing.xs)
                    .background(Capsule().fill(BeagleTheme.surface1))
                    .overlay(
                        Capsule()
                            .strokeBorder(BeagleTheme.hairline, lineWidth: 1)
                    )
            }
            Spacer()
        }
    }

    /// What the leading route pill should say, based on the live engine state.
    private var activeRoutePill: (label: String, icon: String, tint: Color) {
        let llm = LocalLLMEngine.shared
        switch llm.loadState {
        case .ready:
            return ("On-device · \(llm.currentModel?.displayName ?? "local")", "brain", BeagleTheme.truthObserved)
        case .downloading(let progress):
            return ("Downloading · \(Int(progress * 100))%", "arrow.down.circle", BeagleTheme.postureWarm)
        case .loading:
            return ("Waking device mind…", "hourglass", BeagleTheme.postureWarm)
        case .error, .idle:
            return ("\(conversation.discussionProfile.label) route", conversation.discussionProfile.iconName, BeagleTheme.truthRemembered)
        }
    }

    /// A short, curated set of on-device models for the Home menu: whatever is loaded,
    /// the recommended default, and the last one the user picked — deduped, fits-only,
    /// capped. The full catalog (download/manage) lives behind "Manage models…".
    private var homeLocalModels: [OnDeviceModel] {
        let llm = LocalLLMEngine.shared
        var picks: [OnDeviceModel] = []
        if let current = llm.currentModel { picks.append(current) }
        let recommended = OnDeviceModel.recommended
        if !picks.contains(recommended) { picks.append(recommended) }
        if let last = llm.lastSelectedModel, !picks.contains(last) { picks.append(last) }
        return Array(picks.filter { $0.fitsOnThisDevice }.prefix(3))
    }

    private func homeLocalModelLabel(_ model: OnDeviceModel) -> String {
        if localModelIsActive(model) { return "\(model.displayName) · loaded" }
        return "\(model.displayName) · \(model.sizeDescription)"
    }

    private func localModelIsActive(_ model: OnDeviceModel) -> Bool {
        LocalLLMEngine.shared.currentModel == model && LocalLLMEngine.shared.isReady
    }

    /// Selecting a cloud/cluster route is an explicit choice to leave the device mind:
    /// unload any local model so `sendMessage` routes to the cloud, then set the route.
    private func selectCloudRoute(_ profile: DiscussionProfile) {
        let llm = LocalLLMEngine.shared
        if llm.isReady || llm.loadState == .loading {
            llm.unload()
        }
        conversation.discussionProfile = profile
    }

    private var companionSignalStrip: some View {
        HStack(spacing: BeagleSpacing.xs) {
            PresencePill(
                label: "friend assistant",
                systemImage: "person.2.wave.2.fill",
                tint: BeagleTheme.truthObserved
            )
            PresencePill(
                label: "idea notes stay alive",
                systemImage: "note.text",
                tint: BeagleTheme.truthRemembered
            )
            PresencePill(
                label: physio.summary.readiness == .unavailable ? "body-state still quiet" : "body-state is shaping tone",
                systemImage: "waveform.path.ecg",
                tint: bodyPresenceState.tint
            )
            PresencePill(
                label: physio.summary.conversationPolicy.modeLabel,
                systemImage: "brain.head.profile",
                tint: BeagleTheme.truthRemembered
            )
        }
    }

    @ViewBuilder
    private var whereWeLeftOffCard: some View {
        if let lastUser = conversation.lastUserMessage {
            VStack(alignment: .leading, spacing: BeagleSpacing.sm) {
                HStack(spacing: BeagleSpacing.xs) {
                    PresencePill(label: "Where We Left Off", systemImage: "arrow.trianglehead.clockwise", tint: BeagleTheme.truthRemembered)
                    if let updated = conversation.lastUpdatedAt {
                        PresencePill(label: RelativeDateTimeFormatter().localizedString(for: updated, relativeTo: .now), systemImage: "clock", tint: BeagleTheme.textSecondary)
                    }
                }

                Text(lastUser.content)
                    .font(BeagleFont.body.font)
                    .foregroundStyle(BeagleTheme.textPrimary)
                    .lineLimit(3)

                if let lastAssistant = conversation.lastAssistantMessage, !lastAssistant.content.isEmpty {
                    Text(lastAssistant.content)
                        .font(BeagleFont.footnote.font)
                        .foregroundStyle(BeagleTheme.textSecondary)
                        .lineLimit(3)
                }

                HStack(spacing: BeagleSpacing.sm) {
                    Button {
                        prepareDraft("Continue from where we left off and push this idea one level deeper.")
                    } label: {
                        Label("Continue in Composer", systemImage: "text.bubble")
                    }
                    .buttonStyle(SecondaryButton(color: BeagleTheme.truthObserved))

                    Button {
                        pinQuestionForCurrentLane(lastUser.content)
                    } label: {
                        Label(pinnedQuestionForCurrentLane == lastUser.content ? "Pinned" : "Pin Question", systemImage: pinnedQuestionForCurrentLane == lastUser.content ? "pin.fill" : "pin")
                    }
                    .buttonStyle(SecondaryButton(color: BeagleTheme.truthRemembered))
                }
            }
            .padding(BeagleSpacing.md)
            .background(
                RoundedRectangle(cornerRadius: BeagleRadius.lg)
                    .fill(BeagleTheme.surface1.opacity(0.45))
            )
            .overlay(
                RoundedRectangle(cornerRadius: BeagleRadius.lg)
                    .strokeBorder(BeagleTheme.truthRemembered.opacity(0.08), lineWidth: 1)
            )
        }
    }

    private func pinnedQuestionCard(_ question: String) -> some View {
        VStack(alignment: .leading, spacing: BeagleSpacing.sm) {
            HStack(spacing: BeagleSpacing.xs) {
                PresencePill(label: "Pinned Question", systemImage: "pin.fill", tint: BeagleTheme.truthObserved)
                Spacer()
                Button {
                    clearPinnedQuestionForCurrentLane()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(BeagleTheme.textTertiary)
                }
                .buttonStyle(.plain)
            }

            Text(question)
                .font(BeagleFont.footnote.font)
                .foregroundStyle(BeagleTheme.textPrimary)
                .lineLimit(4)

            Button {
                prepareDraft("Return to this core question and help me work it forward: \(question)")
            } label: {
                Label("Re-enter in Composer", systemImage: "arrow.up.right")
            }
            .buttonStyle(SecondaryButton(color: BeagleTheme.truthObserved))
        }
        .padding(BeagleSpacing.md)
        .background(
            RoundedRectangle(cornerRadius: BeagleRadius.lg)
                .fill(BeagleTheme.truthObserved.opacity(0.07))
        )
        .overlay(
            RoundedRectangle(cornerRadius: BeagleRadius.lg)
                .strokeBorder(BeagleTheme.truthObserved.opacity(0.12), lineWidth: 1)
        )
    }

    private func discussionProfileButton(for profile: DiscussionProfile) -> some View {
        let isSelected = conversation.discussionProfile == profile
        let foreground = isSelected ? BeagleTheme.truthObserved : BeagleTheme.textSecondary
        let fill = isSelected
            ? BeagleTheme.truthObserved.opacity(0.12)
            : BeagleTheme.surface1.opacity(0.45)
        let stroke = isSelected
            ? BeagleTheme.truthObserved.opacity(0.18)
            : BeagleTheme.hairline

        return Button {
            conversation.discussionProfile = profile
        } label: {
            HStack(spacing: BeagleSpacing.xs) {
                Image(systemName: profile.iconName)
                    .font(.system(size: 12, weight: .semibold))
                VStack(alignment: .leading, spacing: 1) {
                    Text(profile.label)
                        .font(BeagleFont.caption.font)
                        .fontWeight(.semibold)
                    Text(profile.subtitle)
                        .font(BeagleFont.caption2.font)
                }
            }
            .foregroundStyle(foreground)
            .padding(.horizontal, BeagleSpacing.sm)
            .padding(.vertical, BeagleSpacing.xs)
            .background(Capsule().fill(fill))
            .overlay(Capsule().strokeBorder(stroke, lineWidth: 1))
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

    // MARK: - Talk input (always visible at bottom)

    private var exocortexInput: some View {
        BeagleInputBar(
            text: $inputText,
            placeholder: circadianPlaceholder,
            mode: .chat,
            isEnabled: !conversation.isStreaming,
            focusRequest: inputFocusRequest,
            onSubmit: { text in
                #if os(iOS)
                BeagleHaptics.capture()
                #endif
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
                Text("Ambient Ideas")
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

    // MARK: - Active Agents Strip (exocortex awareness)

    @ViewBuilder
    private var myWorkCard: some View {
        if !displayWorkLanes.isEmpty {
            GlassPanel(elevation: .floating, truth: .observed) {
                VStack(alignment: .leading, spacing: homeLeadsWithReturnedWork ? BeagleSpacing.sm : BeagleSpacing.md) {
                    HStack(alignment: .firstTextBaseline) {
                        VStack(alignment: .leading, spacing: BeagleSpacing.xxs) {
                            Text("My Work Right Now")
                                .font(BeagleFont.caption.font)
                                .fontWeight(.semibold)
                                .foregroundStyle(BeagleTheme.truthObserved)
                                .textCase(.uppercase)
                                .tracking(0.8)
                            Text(workLaneHeadline)
                                .font(BeagleFont.title3.font)
                                .fontWeight(.semibold)
                                .foregroundStyle(BeagleTheme.textPrimary)
                        }
                        Spacer()
                        if let focusedLane {
                            PresencePill(
                                label: "focus: \(projectDisplayName(focusedLane.project.projectSlug))",
                                systemImage: "scope",
                                tint: BeagleTheme.truthObserved
                            )
                        }
                    }

                    if !homeLeadsWithReturnedWork {
                        Text(workLaneSupportText)
                            .font(BeagleFont.footnote.font)
                            .foregroundStyle(BeagleTheme.textSecondary)
                            .lineSpacing(2)
                            .lineLimit(2)
                    }

                    if let focusedLane {
                        focusedLaneCompass(focusedLane)
                    }

                    VStack(spacing: BeagleSpacing.sm) {
                        ForEach(displayWorkLanes) { lane in
                            workLaneRow(lane)
                        }
                    }
                }
            }
            .opacity(hasAppeared ? 1 : 0)
            .offset(y: hasAppeared ? 0 : 8)
            .animation(.easeOut(duration: 0.5).delay(0.08), value: hasAppeared)
        }
    }

    @ViewBuilder
    private var activeAgentsStrip: some View {
        let running = cognitive.state.value?.agentSessions?.filter { ($0.readyReplicas ?? 0) > 0 } ?? []
        let activeAgentCount = homeSummary?.value?.activeAgentsCount ?? running.count
        if activeAgentCount > 0 {
            HStack(spacing: BeagleSpacing.sm) {
                BreathingDot(color: BeagleTheme.truthObserved, size: 7)
                VStack(alignment: .leading, spacing: 1) {
                    Text(activeAgentCount == 1
                         ? "\(running.first?.kind?.replacingOccurrences(of: "-", with: " ").capitalized ?? "Agent") is active"
                         : "\(activeAgentCount) agents active")
                        .font(BeagleFont.footnote.font)
                        .fontWeight(.medium)
                        .foregroundStyle(BeagleTheme.textPrimary)
                Text("Cluster mind is live · open Agents to join")
                    .font(BeagleFont.caption2.font)
                    .foregroundStyle(BeagleTheme.textTertiary)
                }
                Spacer()
                CognitiveBridgeField(
                    localWeight: 0.45,
                    bridgeWeight: 1.0,
                    clusterWeight: 1.0,
                    emphasis: .balanced
                )
                .frame(width: 138, height: 54)
                Image(systemName: "arrow.right")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(BeagleTheme.truthObserved.opacity(0.5))
            }
            .padding(.horizontal, BeagleSpacing.md)
            .padding(.vertical, BeagleSpacing.sm)
            .background(
                RoundedRectangle(cornerRadius: BeagleRadius.lg)
                    .fill(BeagleTheme.truthObserved.opacity(0.06))
                    .overlay(
                        RoundedRectangle(cornerRadius: BeagleRadius.lg)
                            .strokeBorder(BeagleTheme.truthObserved.opacity(0.15), lineWidth: 1)
                    )
            )
            .opacity(hasAppeared ? 1 : 0)
            .animation(.easeOut(duration: 0.5).delay(0.15), value: hasAppeared)
        }
    }

    // MARK: - Warmth Card (negative State of Mind)

    private var warmthCard: some View {
        HStack(alignment: .top, spacing: BeagleSpacing.sm) {
            Image(systemName: "heart.fill")
                .font(.system(size: 16))
                .foregroundStyle(BeagleTheme.postureWarm)
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: BeagleSpacing.xs) {
                Text("Your recent mood check suggests a harder day. The exocortex is here \u{2014} no pressure, just presence.")
                    .font(BeagleFont.subheadline.font)
                    .foregroundStyle(BeagleTheme.textPrimary)
                    .lineSpacing(3)
            }
        }
        .padding(.horizontal, BeagleSpacing.lg)
        .padding(.vertical, BeagleSpacing.md)
        .background(
            RoundedRectangle(cornerRadius: BeagleRadius.lg)
                .fill(BeagleTheme.postureWarm.opacity(0.04))
        )
        .overlay(
            RoundedRectangle(cornerRadius: BeagleRadius.lg)
                .strokeBorder(BeagleTheme.postureWarm.opacity(0.08), lineWidth: 1)
        )
        .opacity(hasAppeared ? 1 : 0)
        .offset(y: hasAppeared ? 0 : 12)
        .animation(.easeOut(duration: 0.6).delay(0.15), value: hasAppeared)
    }

    // MARK: - Morning Brief (synthesized from overnight agent activity)

    private func morningBriefCard(_ brief: String) -> some View {
        let displayBrief: String = {
            if morningBriefIntensity == .minimal {
                // Show only the first sentence for low-energy state
                let firstSentence = brief.components(separatedBy: ". ").first ?? brief
                return firstSentence.hasSuffix(".") ? firstSentence : firstSentence + "."
            }
            return brief
        }()

        return GlassPanel(elevation: .floating, truth: .observed) {
            VStack(alignment: .leading, spacing: BeagleSpacing.sm) {
                HStack(spacing: BeagleSpacing.xs) {
                    Image(systemName: "sunrise.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(BeagleTheme.postureWarm)
                    Text("Command Brief")
                        .font(BeagleFont.caption.font)
                        .fontWeight(.medium)
                        .foregroundStyle(BeagleTheme.postureWarm)
                        .textCase(.uppercase)
                        .tracking(0.5)
                    Spacer()
                    TruthBadge(.observed, compact: true)
                }

                Text(displayBrief)
                    .font(BeagleFont.subheadline.font)
                    .foregroundStyle(BeagleTheme.textPrimary)
                    .lineSpacing(3)

                if morningBriefIntensity != .minimal {
                    GoDeepButton(prompt: "Expand on this morning brief: \(brief)")
                }
            }
        }
        .opacity(hasAppeared ? 1 : 0)
        .offset(y: hasAppeared ? 0 : 12)
        .animation(.easeOut(duration: 0.6).delay(0.2), value: hasAppeared)
    }

    // MARK: - Overnight Insights (Dream Synthesis)

    private var overnightInsightsCard: some View {
        let engine = DreamSynthesisEngine.shared
        let unread = engine.overnightInsights.filter { !$0.isRead }
        let dreamTint = Color(red: 0.45, green: 0.35, blue: 0.75)

        return GlassPanel(elevation: .floating, truth: .remembered) {
            VStack(alignment: .leading, spacing: BeagleSpacing.md) {
                HStack(spacing: BeagleSpacing.xs) {
                    Image(systemName: "moon.stars.fill")
                        .font(.system(size: 15))
                        .foregroundStyle(
                            LinearGradient(
                                colors: [dreamTint, Color(red: 0.6, green: 0.5, blue: 0.85)],
                                startPoint: .topLeading, endPoint: .bottomTrailing
                            )
                        )
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Your exocortex dreamed last night")
                            .font(BeagleFont.caption.font)
                            .fontWeight(.medium)
                            .foregroundStyle(dreamTint)
                            .textCase(.uppercase)
                            .tracking(0.5)
                        if let last = engine.lastDreamSession {
                            Text(last, style: .relative)
                                .font(BeagleFont.caption2.font)
                                .foregroundStyle(BeagleTheme.textTertiary)
                        }
                    }
                    Spacer()
                    TruthBadge(.remembered, compact: true)
                }

                ForEach(unread.prefix(5)) { insight in
                    VStack(alignment: .leading, spacing: BeagleSpacing.xs) {
                        HStack(spacing: BeagleSpacing.xxs) {
                            sleepStageBadge(insight.sleepStage)
                            if let hrv = insight.hrvAtGeneration {
                                Text("HRV \(Int(hrv))")
                                    .font(BeagleFont.caption2.font)
                                    .foregroundStyle(BeagleTheme.textTertiary)
                            }
                        }

                        Text(insight.text)
                            .font(BeagleFont.footnote.font)
                            .foregroundStyle(BeagleTheme.textPrimary)
                            .lineSpacing(2)

                        HStack(spacing: BeagleSpacing.sm) {
                            Button {
                                Task {
                                    _ = await cognitive.captureThought(text: insight.text, source: "dream-synthesis")
                                    engine.markRead(insight.id)
                                    #if os(iOS)
                                    BeagleHaptics.capture()
                                    #endif
                                }
                            } label: {
                                HStack(spacing: BeagleSpacing.xxs) {
                                    Image(systemName: "arrow.down.doc")
                                        .font(.system(size: 11))
                                    Text("Capture")
                                        .font(BeagleFont.caption2.font)
                                }
                                .foregroundStyle(dreamTint)
                            }
                            .buttonStyle(.plain)

                            GoDeepButton(prompt: "Explore this overnight insight: \(insight.text)")

                            Spacer()

                            Button {
                                engine.markRead(insight.id)
                            } label: {
                                Image(systemName: "checkmark.circle")
                                    .font(.system(size: 13))
                                    .foregroundStyle(BeagleTheme.textTertiary)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.vertical, BeagleSpacing.xs)

                    if insight.id != unread.prefix(5).last?.id {
                        Divider().overlay(dreamTint.opacity(0.08))
                    }
                }

                if unread.count > 1 {
                    Button {
                        withAnimation(BeagleMotion.snappy) {
                            engine.markAllRead()
                        }
                    } label: {
                        HStack(spacing: BeagleSpacing.xxs) {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 12))
                            Text("Mark all read")
                                .font(BeagleFont.caption.font)
                        }
                        .foregroundStyle(BeagleTheme.textTertiary)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .opacity(hasAppeared ? 1 : 0)
        .offset(y: hasAppeared ? 0 : 12)
        .animation(.easeOut(duration: 0.6).delay(0.18), value: hasAppeared)
    }

    private func sleepStageBadge(_ stage: String) -> some View {
        let (label, icon): (String, String) = {
            switch stage {
            case "deep-rem-phase":
                return ("REM", "moon.zzz.fill")
            case "core-sleep":
                return ("Core", "moon.fill")
            case "light-sleep":
                return ("Light", "moon.haze.fill")
            case "quantum-dream":
                return ("Quantum", "atom")
            case "serendipity-dream":
                return ("Serendipity", "sparkle")
            default:
                return ("Dream", "moon.stars")
            }
        }()

        return HStack(spacing: 3) {
            Image(systemName: icon)
                .font(.system(size: 9))
            Text(label)
                .font(BeagleFont.caption2.font)
                .fontWeight(.medium)
        }
        .foregroundStyle(Color(red: 0.55, green: 0.45, blue: 0.8))
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(
            Capsule()
                .fill(Color(red: 0.45, green: 0.35, blue: 0.75).opacity(0.10))
        )
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

    // MARK: - Chaos Serendipity Card (Lorenz attractor thought-loop rescue)

    private func chaosSerendipityCard(_ provocation: SerendipityProvocation) -> some View {
        VStack(alignment: .leading, spacing: BeagleSpacing.sm) {
            HStack(spacing: BeagleSpacing.xs) {
                Image(systemName: "butterfly")
                    .font(.system(size: 14))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [Color.orange, Color(hue: 30/360, saturation: 0.8, brightness: 0.95)],
                            startPoint: .topLeading, endPoint: .bottomTrailing
                        )
                    )

                Text("Chaos Injection")
                    .font(BeagleFont.caption.font)
                    .fontWeight(.medium)
                    .foregroundStyle(BeagleTheme.textTertiary)
                    .textCase(.uppercase)
                    .tracking(0.5)

                Spacer()

                LorenzAttractorView(
                    stagnation: provocation.stagnationScore ?? 0.5,
                    tintColor: Color.orange
                )
                .frame(width: 80, height: 60)
                .opacity(0.7)

                Text(provocation.domain)
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(Color.orange.opacity(0.7))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(
                        Capsule().fill(Color.orange.opacity(0.08))
                    )
            }

            Text(provocation.text)
                .font(BeagleFont.footnote.font)
                .foregroundStyle(BeagleTheme.textSecondary)
                .lineSpacing(2)
                .italic()

            if let score = provocation.stagnationScore {
                Text("Stagnation: \(Int(score * 100))%")
                    .font(.system(size: 9, weight: .medium, design: .monospaced))
                    .foregroundStyle(BeagleTheme.textTertiary)
            }

            Button {
                Task {
                    _ = await cognitive.captureThought(text: provocation.text, source: "serendipity-engine")
                }
                withAnimation(BeagleMotion.slow) { chaosProvocation = nil }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 11))
                    Text("Capture this")
                        .font(BeagleFont.caption.font)
                        .fontWeight(.medium)
                }
                .foregroundStyle(Color.orange)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, BeagleSpacing.lg)
        .padding(.vertical, BeagleSpacing.md)
        .background(
            RoundedRectangle(cornerRadius: BeagleRadius.lg)
                .fill(Color.orange.opacity(0.03))
        )
        .overlay(
            RoundedRectangle(cornerRadius: BeagleRadius.lg)
                .strokeBorder(Color.orange.opacity(0.08), lineWidth: 1)
        )
        .opacity(hasAppeared ? 1 : 0)
        .offset(y: hasAppeared ? 0 : 12)
        .animation(.easeOut(duration: 0.6).delay(0.4), value: hasAppeared)
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
                #if os(iOS)
                BeagleHaptics.morningBrief()
                #endif
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

            // Lorenz attractor chaos injection -- detect thought loops and provoke
            if let provocation = SerendipityEngine.shared.checkAndProvoke(thoughts: cognitive.recentThoughts) {
                withAnimation(BeagleMotion.slow) { chaosProvocation = provocation }
            }
        }
    }

    // MARK: - Bootstrap

    private func bootstrap() async {
        greeting = timeGreeting()
        if !hasAppeared {
            withAnimation { hasAppeared = true }
        }
        #if os(iOS)
        await speechRecognizer.setup()
        #endif
        async let c: () = catalog.refresh()
        async let g: () = cognitive.refresh()
        async let p: () = physio.refresh()
        async let s = CockpitClient.shared.mobileSummary()
        let summary = await s
        applyHomeSummary(summary)
        _ = await (c, g, p)
        // Wire HRV flow state into conversation routing
        conversation.flowState = cognitive.flowState
        conversation.modelContext = modelContext
        let projectSlug = preferredLaneSlug
        let family = ProjectFamily.fromProjectSlug(projectSlug)
        conversation.restoreContext(
            projectSlug: projectSlug,
            projectFamily: family,
            publicationScope: PublicationScope.forProjectFamily(family)
        )
        applyPhysioConversationContext()
        seedDiscussionPreviewIfRequested()
        await refreshWorkLanes()

        generateProvocations()
        generateInspirationLayer()
        runMetacognitiveCheck()

        // Dream Synthesis — if the exocortex hasn't dreamed recently, run a synthesis pass
        if DreamSynthesisEngine.shared.shouldDreamAgain && cognitive.recentThoughts.count >= 3 {
            await DreamSynthesisEngine.shared.synthesize(
                thoughts: cognitive.recentThoughts,
                cognitivePosture: physio.cognitivePosture
            )
        }

        #if os(iOS)
        // Start ambient triage loop: periodically sends fragments to cluster for filtering
        startAmbientTriageLoop()
        #endif
    }

    private func seedDiscussionPreviewIfRequested() {
        let args = ProcessInfo.processInfo.arguments
        guard args.contains("--beagle-seed-home-thread"), conversation.isEmpty else { return }

        let now = Date()
        let laneName = focusedLane.map { projectDisplayName($0.project.projectSlug) } ?? projectDisplayName(conversation.projectSlug)
        let sampleMessages = [
            ChatMessage(
                role: .user,
                content: "I think the real question in \(laneName) is whether we are building a tool or an actual cognitive habitat. Help me figure out what that changes.",
                timestamp: now.addingTimeInterval(-420)
            ),
            ChatMessage(
                role: .assistant,
                content: "It changes the center of gravity. A tool helps you complete tasks; a cognitive habitat keeps the thread of thought alive between tasks. If \(laneName) is a habitat, the priority is continuity, memory, and visible active minds, not just feature coverage.",
                timestamp: now.addingTimeInterval(-360),
                model: "Hermes",
                source: "agent",
                agentKind: "claude-code"
            ),
            ChatMessage(
                role: .user,
                content: "Then the next move is probably to make the app remember the living question per lane, not just the latest UI state.",
                timestamp: now.addingTimeInterval(-210)
            )
        ]

        conversation.seedPreviewConversation(sampleMessages)
        pinQuestionForCurrentLane("How do we make \(laneName) feel like a cognitive habitat instead of a tool?")
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
                    let cloudResult = await BeagleClient.shared.chat(prompt: triagePrompt, system: "You are a cognitive filter for a device mind that syncs with a larger cluster mind. Extract only genuine intellectual insights from ambient speech. Be aggressive about filtering noise.")
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

    // MARK: - Search Results

    private var searchResults: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: BeagleSpacing.sm) {
                let query = searchText.lowercased()
                let matches = cognitive.recentThoughts.filter { thought in
                    let text = (thought.refinedText ?? thought.rawText ?? "").lowercased()
                    return text.contains(query)
                }

                if matches.isEmpty {
                    VStack(spacing: BeagleSpacing.md) {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 28))
                            .foregroundStyle(BeagleTheme.textTertiary)
                        Text("No thoughts matching \"\(searchText)\"")
                            .font(BeagleFont.footnote.font)
                            .foregroundStyle(BeagleTheme.textSecondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, BeagleSpacing.xxxl)
                } else {
                    Text("\(matches.count) thought\(matches.count == 1 ? "" : "s")")
                        .font(BeagleFont.caption.font)
                        .foregroundStyle(BeagleTheme.textTertiary)
                        .padding(.horizontal, BeagleSpacing.lg)

                    ForEach(matches) { thought in
                        let text = thought.refinedText ?? thought.rawText ?? ""
                        HStack(alignment: .top, spacing: BeagleSpacing.sm) {
                            Circle()
                                .fill(thought.residency == .clusterMemory ? BeagleTheme.truthObserved : BeagleTheme.truthDeclared)
                                .frame(width: 6, height: 6)
                                .padding(.top, 7)

                            VStack(alignment: .leading, spacing: 3) {
                                Text(text)
                                    .font(BeagleFont.subheadline.font)
                                    .foregroundStyle(BeagleTheme.textPrimary)
                                    .lineLimit(4)

                                PresencePill(
                                    label: thought.residency == .clusterMemory ? "Cluster memory" : "Device only",
                                    systemImage: thought.effectiveSyncState.systemImage,
                                    tint: tint(for: thought.effectiveSyncState)
                                )
                            }

                            Spacer()

                            GoDeepButton(prompt: text)
                        }
                        .frame(minHeight: 44)
                        .padding(.horizontal, BeagleSpacing.lg)
                    }
                }
            }
            .padding(.top, BeagleSpacing.md)
        }
        .background(BeagleTheme.surface0)
    }

    private var circadianPlaceholder: String {
        if physio.summary.readiness != .unavailable {
            return physio.summary.conversationPolicy.suggestedPlaceholder
        }
        let hour = Calendar.current.component(.hour, from: Date())
        switch hour {
        case 5..<9:    return "Talk to Beagle about this morning's thread..."
        case 9..<12:   return "What are you working through?"
        case 12..<14:  return "What should the larger mind help with?"
        case 14..<18:  return "What's taking shape?"
        case 18..<22:  return "Any idea worth carrying forward tonight?"
        default:       return "Can't sleep? Start with the device mind..."
        }
    }

    private func tint(for syncState: IdeaSyncState) -> Color {
        switch syncState {
        case .localOnly:
            return BeagleTheme.truthDeclared
        case .queued:
            return BeagleTheme.postureWarm
        case .synced:
            return BeagleTheme.truthObserved
        case .delegated:
            return BeagleTheme.truthRemembered
        }
    }

    private func timeGreeting() -> String {
        let hour = Calendar.current.component(.hour, from: Date())
        let posture = physio.cognitivePosture
        let thoughtCount = cognitive.recentThoughts.count

        // Late-night wisdom
        if hour < 5 {
            return "The night holds its own wisdom."
        }

        // Morning: adapt to sleep + readiness
        if hour < 9 {
            if let sleep = posture.sleepQuality, sleep < 0.3 {
                return "Rough night. Be gentle with yourself today."
            }
            if let readiness = posture.readiness, readiness > 0.7 {
                return "Well rested. Your mind is sharp this morning."
            }
            if let readiness = posture.readiness, readiness < 0.3 {
                return "Your body is still recovering. Easy start."
            }
            return thoughtCount > 0 ? "Early start." : "Fresh morning."
        }

        // Late morning
        if hour < 12 {
            if let readiness = posture.readiness, readiness > 0.7 {
                return "Good morning. Energy looks strong."
            }
            return thoughtCount > 10 ? "Your mind has been active." : "Good morning."
        }

        // Midday
        if hour < 14 {
            return "Midday."
        }

        // Afternoon
        if hour < 17 {
            if let readiness = posture.readiness, readiness < 0.3 {
                return "Afternoon lull. Pace yourself."
            }
            return thoughtCount > 5 ? "Deep afternoon." : "Good afternoon."
        }

        // Evening
        if hour < 20 {
            return "Winding down."
        }
        if hour < 23 {
            return thoughtCount > 0 ? "Evening reflections." : "Quiet evening."
        }
        return "Still here."
    }

    // MARK: - Morning Brief Adaptation

    /// Controls how much content the morning brief shows based on biosignals.
    private enum MorningBriefIntensity {
        case minimal   // Poor sleep + low HRV: just one key item
        case moderate  // Decent state: standard brief
        case full      // Good sleep + high HRV: full brief with provocations and GoDeep
    }

    private var morningBriefIntensity: MorningBriefIntensity {
        let posture = physio.cognitivePosture
        guard let readiness = posture.readiness else { return .moderate }
        if readiness < 0.3 { return .minimal }
        if readiness > 0.65 { return .full }
        return .moderate
    }

    /// Whether the user's recent State of Mind suggests a harder day.
    private var showWarmthCard: Bool {
        guard let valence = physio.cognitivePosture.stateOfMind else { return false }
        return valence < -0.3
    }

    private var focusedLane: ProjectLaneState? {
        let targetSlug = preferredLaneSlug
        return displayWorkLanes.first(where: { $0.project.projectSlug == targetSlug }) ?? displayWorkLanes.first
    }

    private var homeLeadsWithReturnedWork: Bool {
        focusedLane?.laneResult != nil
    }

    private var runningAgentsExist: Bool {
        cognitive.state.value?.agentSessions?.contains(where: { ($0.readyReplicas ?? 0) > 0 }) ?? false
    }

    // MARK: - HRV Cognitive Throttling

    private var currentIntensity: CognitivePosture.InterfaceIntensity {
        physio.cognitivePosture.suggestedIntensity
    }

    private var showProvocations: Bool {
        guard !provocations.isEmpty else { return false }
        switch currentIntensity {
        case .minimal:
            return false
        case .calm:
            return true // gentle provocations only — filtered at generation time
        case .normal, .engaged, .challenge:
            return true
        }
    }

    private var showTriadReadyCard: Bool {
        currentIntensity == .challenge
    }

    private var triadReadyCard: some View {
        GlassPanel(elevation: .floating, truth: .observed) {
            HStack(spacing: BeagleSpacing.sm) {
                ZStack {
                    Circle()
                        .fill(BeagleTheme.truthObserved.opacity(0.12))
                        .frame(width: 40, height: 40)
                    Image(systemName: "bolt.trianglebadge.exclamationmark.fill")
                        .font(.system(size: 17))
                        .foregroundStyle(BeagleTheme.truthObserved)
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text("Ready for Triad Review?")
                        .font(BeagleFont.subheadline.font)
                        .fontWeight(.semibold)
                        .foregroundStyle(BeagleTheme.textPrimary)
                    Text("Your cognitive readiness is high. A good time to stress-test an idea with adversarial debate.")
                        .font(BeagleFont.caption.font)
                        .foregroundStyle(BeagleTheme.textSecondary)
                        .lineSpacing(1)
                }
                Spacer()
            }
        }
    }

    @ViewBuilder
    private var intensityPill: some View {
        let intensity = currentIntensity
        let (label, icon, tint): (String, String, Color) = {
            switch intensity {
            case .minimal:
                return ("minimal", "moon.zzz.fill", BeagleTheme.textTertiary)
            case .calm:
                return ("calm", "leaf.fill", BeagleTheme.truthDeclared)
            case .normal:
                return ("normal", "circle.fill", BeagleTheme.textSecondary)
            case .engaged:
                return ("engaged", "flame.fill", BeagleTheme.postureWarm)
            case .challenge:
                return ("challenge", "bolt.fill", BeagleTheme.truthObserved)
            }
        }()
        if intensity != .normal {
            PresencePill(label: label, systemImage: icon, tint: tint)
        }
    }

    private var displayWorkLanes: [ProjectLaneState] {
        if !workLanes.isEmpty {
            return workLanes
        }
        return summarySeededLanes()
    }

    private var preferredLaneSlug: String {
        cognitive.activeProjectSlug ?? catalog.primaryProject?.projectSlug ?? "sounio"
    }

    private var laneProjectOptions: [Project] {
        var ordered: [Project] = catalog.projects
        var seen = Set(ordered.map(\.projectSlug))

        let summaryDrivenSlugs = (homeSummary?.value?.laneResults ?? []).map(\.projectSlug)
            + cachedLaneResults.map(\.projectSlug)
            + ["sounio", "scratch", "hyperbolic-semantic-networks"]

        for slug in summaryDrivenSlugs {
            guard !seen.contains(slug) else { continue }
            ordered.append(placeholderProject(for: slug))
            seen.insert(slug)
        }
        ordered.sort { lhs, rhs in
            let lhsFocused = lhs.projectSlug == preferredLaneSlug
            let rhsFocused = rhs.projectSlug == preferredLaneSlug
            if lhsFocused != rhsFocused { return lhsFocused }
            if lhs.projectSlug == "sounio" || rhs.projectSlug == "sounio" {
                return lhs.projectSlug == "sounio"
            }
            return lhs.projectSlug < rhs.projectSlug
        }
        return ordered
    }

    private var workLaneSupportText: String {
        if let focusedLane, focusedLane.laneResult != nil {
            return "Returned work is already here. See what came back before you wake the next mind."
        }
        if workLanes.isEmpty {
            return "These are the project lanes Beagle already knows about. Live habitat and agent intent will settle in underneath as the bridge wakes up."
        }
        return "Start here when you want one honest answer to three questions: what you are building, where it is running, and which mind is doing what."
    }

    @ViewBuilder
    private var bodyStateCard: some View {
        PresenceFieldCard(
            state: bodyPresenceState,
            eyebrow: "Body State",
            title: physio.summary.title,
            body: physio.summary.bodyLine,
            detail: physio.summary.detailLine,
            truth: physio.summary.truthMode
        ) {
            VStack(alignment: .leading, spacing: BeagleSpacing.sm) {
                HStack(spacing: BeagleSpacing.xs) {
                    if let hrv = physio.summary.hrvMs {
                        PresencePill(label: "HRV \(Int(hrv)) ms", systemImage: "waveform.path.ecg", tint: BeagleTheme.truthObserved)
                    }
                    if let sleepHours = physio.summary.sleepHours {
                        PresencePill(label: String(format: "sleep %.1f h", sleepHours), systemImage: "bed.double.fill", tint: BeagleTheme.truthRemembered)
                    }
                    if physio.summary.workoutCount > 0 {
                        PresencePill(label: "\(physio.summary.workoutCount) workout\(physio.summary.workoutCount == 1 ? "" : "s")", systemImage: "figure.run", tint: BeagleTheme.postureWarm)
                    }
                    PresencePill(
                        label: physio.summary.conversationPolicy.modeLabel,
                        systemImage: "brain.head.profile",
                        tint: bodyPresenceState.tint
                    )
                    PresencePill(
                        label: physio.summary.conversationPolicy.routeLabel,
                        systemImage: conversation.discussionProfile.iconName,
                        tint: BeagleTheme.truthRemembered
                    )
                }

                if physio.authorizationState == .idle {
                    Button {
                        Task { await physio.refresh(requestAuthorization: true) }
                    } label: {
                        Label("Connect Body State", systemImage: "heart.text.square")
                    }
                    .buttonStyle(SecondaryButton(color: BeagleTheme.truthObserved))
                }
            }
        }
    }

    private var bodyPresenceState: BeaglePresenceState {
        switch physio.summary.readiness {
        case .restored:
            return .active
        case .steady:
            return .attentive
        case .strained:
            return .strained
        case .unavailable:
            return .dormant
        }
    }

    private func applyPhysioConversationContext() {
        conversation.flowState = physio.summary.readiness == .unavailable
            ? cognitive.flowState
            : physio.summary.readiness.discussionFlowState
        conversation.discussionProfile = physio.summary.suggestedDiscussionProfile
        conversation.preferLocal = physio.summary.suggestedPreferLocal
        conversation.physioPolicy = physio.summary.conversationPolicy
        conversation.physioContext = physio.summary.promptContextLine
        conversation.companionContext = "Companion contract: act like Beagle, a trusted friend-assistant and exocortex companion. Help carry the living question, take notes of important ideas, preserve continuity between turns, and adapt your cognitive pressure to the user's current state instead of acting like a generic chatbot."
        conversation.behaviorContext = "Behavior policy: \(physio.summary.conversationPolicy.companionInstruction) \(physio.summary.conversationPolicy.pacingInstruction)"
        conversation.noteTakingContext = "Note policy: \(physio.summary.conversationPolicy.noteInstruction)"
    }

    private var workLaneHeadline: String {
        if let focusedLane, focusedLane.laneResult != nil {
            return "See what came back and what should happen next"
        }
        return "See the lane, the habitat, and the minds actually carrying the thread"
    }

    private func focusedLaneCompass(_ lane: ProjectLaneState) -> some View {
        VStack(alignment: .leading, spacing: BeagleSpacing.md) {
            HStack(alignment: .top, spacing: BeagleSpacing.sm) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Current lane")
                        .font(BeagleFont.caption.font)
                        .fontWeight(.medium)
                        .foregroundStyle(BeagleTheme.textTertiary)
                        .textCase(.uppercase)
                        .tracking(0.5)
                    Text("\(projectDisplayName(lane.project.projectSlug)) is the thread in your hands")
                        .font(BeagleFont.title3.font)
                        .fontWeight(.semibold)
                        .foregroundStyle(BeagleTheme.textPrimary)
                    Text(lane.postureNarrative)
                        .font(BeagleFont.footnote.font)
                        .foregroundStyle(BeagleTheme.textSecondary)
                        .lineSpacing(2)
                        .lineLimit(lane.laneResult == nil ? 3 : 2)
                }
                Spacer()
                TruthBadge(lane.truth, compact: true)
            }

            if lane.laneResult != nil {
                LaneResultCard(lane: lane)
            }

            HStack(spacing: BeagleSpacing.xs) {
                PresencePill(
                    label: lane.project.branch ?? lane.project.preferredPrBase ?? "branch not declared",
                    systemImage: "arrow.triangle.branch",
                    tint: BeagleTheme.truthRemembered
                )
                PresencePill(
                    label: lane.project.workspacePod ?? "habitat parked",
                    systemImage: lane.project.workspacePod == nil ? "moon.zzz.fill" : "shippingbox.fill",
                    tint: lane.project.workspacePod == nil ? BeagleTheme.postureWarm : BeagleTheme.truthObserved
                )
                PresencePill(
                    label: lane.countsLine,
                    systemImage: "brain.head.profile",
                    tint: BeagleTheme.truthObserved
                )
            }

            if let livingQuestion = lane.livingQuestion, lane.laneResult == nil {
                VStack(alignment: .leading, spacing: BeagleSpacing.xs) {
                    PresencePill(label: "Living Question", systemImage: "pin.fill", tint: BeagleTheme.truthObserved)
                    Text(livingQuestion)
                        .font(BeagleFont.footnote.font)
                        .foregroundStyle(BeagleTheme.textPrimary)
                        .lineLimit(3)
                }
                .padding(BeagleSpacing.sm)
                .background(
                    RoundedRectangle(cornerRadius: BeagleRadius.md)
                        .fill(BeagleTheme.truthObserved.opacity(0.06))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: BeagleRadius.md)
                        .strokeBorder(BeagleTheme.truthObserved.opacity(0.10), lineWidth: 1)
                )
            }

            VStack(alignment: .leading, spacing: BeagleSpacing.xs) {
                ForEach(Array(orderedSessions(for: lane).prefix(3)), id: \.name) { session in
                    laneAgentRow(session)
                }
                if lane.sessions.isEmpty {
                    Text(lane.laneResult == nil
                         ? "No agent has picked up this lane yet. Open Agents to wake the first mind in this project."
                         : "Returned work is already here. Wake an agent when you want help interpreting or extending it.")
                        .font(BeagleFont.footnote.font)
                        .foregroundStyle(BeagleTheme.textSecondary)
                }
            }

            if let jobLine = lane.jobLine {
                HStack(spacing: BeagleSpacing.xs) {
                    PresencePill(label: "Work in Motion", systemImage: "bolt.badge.clock", tint: BeagleTheme.postureWarm)
                    Text(jobLine)
                        .font(BeagleFont.footnote.font)
                        .foregroundStyle(BeagleTheme.textSecondary)
                        .lineLimit(2)
                }
            }

            if lane.laneResult == nil, let resultSignal = lane.resultSignal {
                HStack(spacing: BeagleSpacing.xs) {
                    PresencePill(label: "Result Trail", systemImage: "tray.full", tint: BeagleTheme.truthRemembered)
                    Text(resultSignal)
                        .font(BeagleFont.footnote.font)
                        .foregroundStyle(BeagleTheme.textSecondary)
                        .lineLimit(2)
                }
            }

            HStack(spacing: BeagleSpacing.xs) {
                PresencePill(label: "Next move", systemImage: "figure.walk.motion", tint: BeagleTheme.postureWarm)
                Text(lane.nextRecommendedMove)
                    .font(BeagleFont.footnote.font)
                    .foregroundStyle(BeagleTheme.textSecondary)
                    .lineSpacing(2)
            }

            HStack(spacing: BeagleSpacing.sm) {
                Button {
                    focusProjectLane(lane.project)
                    selectedTab = 3
                } label: {
                    Label("Open \(projectDisplayName(lane.project.projectSlug)) Agents", systemImage: "apple.terminal")
                }
                .buttonStyle(PrimaryButton())

                Button {
                    focusProjectLane(lane.project)
                    selectedTab = 2
                } label: {
                    Label("Open Command", systemImage: "server.rack")
                }
                .buttonStyle(SecondaryButton(color: BeagleTheme.truthObserved))
            }
        }
        .padding(BeagleSpacing.md)
        .background(
            RoundedRectangle(cornerRadius: BeagleRadius.lg)
                .fill(BeagleTheme.truthObserved.opacity(0.08))
        )
        .overlay(
            RoundedRectangle(cornerRadius: BeagleRadius.lg)
                .strokeBorder(BeagleTheme.truthObserved.opacity(0.16), lineWidth: 1)
        )
    }

    private func workLaneRow(_ lane: ProjectLaneState) -> some View {
        let isFocused = lane.project.projectSlug == preferredLaneSlug
        return VStack(alignment: .leading, spacing: BeagleSpacing.sm) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: BeagleSpacing.xs) {
                        Text(projectDisplayName(lane.project.projectSlug))
                            .font(BeagleFont.body.font)
                            .fontWeight(.semibold)
                            .foregroundStyle(BeagleTheme.textPrimary)
                        if isFocused {
                            PresencePill(label: "current lane", systemImage: "scope", tint: BeagleTheme.truthObserved)
                        }
                    }
                    Text(lane.project.projectSlug)
                        .font(BeagleFont.caption2.font)
                        .foregroundStyle(BeagleTheme.textTertiary)
                }
                Spacer()
                TruthBadge(lane.truth, compact: true)
            }

            HStack(spacing: BeagleSpacing.xs) {
                PresencePill(
                    label: lane.project.branch ?? lane.project.preferredPrBase ?? "branch not declared",
                    systemImage: "arrow.triangle.branch",
                    tint: BeagleTheme.truthRemembered
                )
                PresencePill(
                    label: lane.project.workspacePod ?? "habitat parked",
                    systemImage: lane.project.workspacePod == nil ? "moon.zzz.fill" : "shippingbox.fill",
                    tint: lane.project.workspacePod == nil ? BeagleTheme.postureWarm : BeagleTheme.truthObserved
                )
                if let tmux = lane.project.tmuxSession {
                    PresencePill(label: tmux, systemImage: "terminal", tint: BeagleTheme.textSecondary)
                }
            }

            if lane.sessions.isEmpty {
                Text(lane.truth == .observed ? "No live agents are carrying this lane right now." : "Waiting for live habitat and agent telemetry.")
                    .font(BeagleFont.footnote.font)
                    .foregroundStyle(BeagleTheme.textSecondary)
            } else {
                VStack(alignment: .leading, spacing: BeagleSpacing.xxs) {
                    Text(lane.sessions.count == 1 ? "Agent in this lane" : "Agents in this lane")
                        .font(BeagleFont.caption.font)
                        .foregroundStyle(BeagleTheme.textTertiary)
                    VStack(alignment: .leading, spacing: BeagleSpacing.xs) {
                        ForEach(orderedSessions(for: lane), id: \.name) { session in
                            laneAgentRow(session)
                        }
                    }
                }
            }

            if let livingQuestion = lane.livingQuestion {
                Text("Living question: \(livingQuestion)")
                    .font(BeagleFont.caption.font)
                    .foregroundStyle(BeagleTheme.truthRemembered)
                    .lineLimit(2)
            } else if lane.laneResult != nil {
                LaneResultCard(lane: lane, compact: true)
            } else if let jobLine = lane.jobLine {
                Text(jobLine)
                    .font(BeagleFont.caption.font)
                    .foregroundStyle(BeagleTheme.postureWarm)
                    .lineLimit(2)
            } else {
                Text(lane.nextRecommendedMove)
                    .font(BeagleFont.caption.font)
                    .foregroundStyle(BeagleTheme.textSecondary)
                    .lineLimit(2)
            }

            HStack(spacing: BeagleSpacing.sm) {
                Button {
                    focusProjectLane(lane.project)
                    selectedTab = 3
                } label: {
                    Label(lane.runningSessions.isEmpty ? "Open Agents" : "Join Agent", systemImage: "apple.terminal")
                }
                .buttonStyle(PrimaryButton())

                Button {
                    focusProjectLane(lane.project)
                    selectedTab = 2
                } label: {
                    Label("Open Command", systemImage: "server.rack")
                }
                .buttonStyle(SecondaryButton(color: BeagleTheme.truthObserved))
            }
        }
        .padding(BeagleSpacing.md)
        .background(
            RoundedRectangle(cornerRadius: BeagleRadius.lg)
                .fill(isFocused ? BeagleTheme.truthObserved.opacity(0.08) : BeagleTheme.surface1.opacity(0.56))
        )
        .overlay(
            RoundedRectangle(cornerRadius: BeagleRadius.lg)
                .strokeBorder(isFocused ? BeagleTheme.truthObserved.opacity(0.22) : Color.white.opacity(0.05), lineWidth: 1)
        )
    }

    private func refreshWorkLanes() async {
        let projects = catalog.projects
        guard !projects.isEmpty else {
            workLanes = summarySeededLanes()
            return
        }

        let activeSlug = preferredLaneSlug
        let pinnedQuestions = pinnedLaneQuestions
        let activeJobs = cognitive.activeJobs
        let activeTrail = CognitiveStore.recentTrailSnippets(from: cognitive.recentThoughts)
        let laneResultsBySlug = Dictionary(
            uniqueKeysWithValues: (homeSummary?.value?.laneResults ?? []).map { ($0.projectSlug, $0) }
        )

        var lanes: [ProjectLaneState] = []
        await withTaskGroup(of: ProjectLaneState.self) { group in
            for project in projects {
                let laneResult = laneResultsBySlug[project.projectSlug]
                group.addTask {
                    async let sessionsResult = CockpitClient.shared.agentSessions(slug: project.projectSlug)
                    async let overviewResult = CockpitClient.shared.projectOverview(slug: project.projectSlug)
                    let result = await sessionsResult
                    let overview = await overviewResult
                    let sessions = result.value?.sessions ?? []
                    let carriedObjective =
                        sessions.first(where: \.isRunning)?.presentedActivityLine
                        ?? sessions.first(where: { $0.phase == .paused })?.presentedActivityLine
                        ?? sessions.first?.presentedActivityLine
                    let laneTruth = overview.value?.laneResult != nil ? overview.mode : result.mode
                    return ProjectLaneState(
                        project: project,
                        sessions: sessions,
                        scienceJobs: project.projectSlug == activeSlug ? activeJobs : [],
                        laneResult: overview.value?.laneResult ?? laneResult,
                        recentTrail: project.projectSlug == activeSlug ? activeTrail : [],
                        truth: laneTruth,
                        isCurrent: project.projectSlug == activeSlug,
                        livingQuestion: pinnedQuestions[project.projectSlug],
                        carriedObjective: project.projectSlug == activeSlug ? carriedObjective : nil
                    )
                }
            }

            for await lane in group {
                lanes.append(lane)
            }
        }

        lanes.sort { lhs, rhs in
            let lhsFocused = lhs.project.projectSlug == preferredLaneSlug
            let rhsFocused = rhs.project.projectSlug == preferredLaneSlug
            if lhsFocused != rhsFocused { return lhsFocused }
            if lhs.runningSessions.count != rhs.runningSessions.count {
                return lhs.runningSessions.count > rhs.runningSessions.count
            }
            return lhs.project.projectSlug < rhs.project.projectSlug
        }

        persistLaneResults(lanes.compactMap(\.laneResult))
        workLanes = lanes
    }

    private func applyHomeSummary(_ summary: Truthful<MobileHomeSummary>) {
        homeSummary = summary
        persistLaneResults(summary.value?.laneResults ?? [])
        workLanes = summarySeededLanes(preserving: workLanes)
    }

    private func summarySeededLanes(preserving existing: [ProjectLaneState] = []) -> [ProjectLaneState] {
        let projects = laneProjectOptions
        guard !projects.isEmpty else { return [] }

        let activeSlug = preferredLaneSlug
        let pinnedQuestions = pinnedLaneQuestions
        let activeJobs = cognitive.activeJobs
        let activeTrail = CognitiveStore.recentTrailSnippets(from: cognitive.recentThoughts)
        let existingBySlug = Dictionary(uniqueKeysWithValues: existing.map { ($0.project.projectSlug, $0) })
        let observedResultSlugs = Set((homeSummary?.value?.laneResults ?? []).map(\.projectSlug))

        var lanes = projects.map { project in
            let existingLane = existingBySlug[project.projectSlug]
            let laneResult = laneResultSummary(for: project.projectSlug) ?? existingLane?.laneResult
            let truth: TruthMode
            if observedResultSlugs.contains(project.projectSlug) {
                truth = homeSummary?.mode ?? .observed
            } else if laneResult != nil {
                truth = .remembered
            } else {
                truth = existingLane?.truth ?? (catalog.projects.isEmpty ? .stale : .declared)
            }

            return ProjectLaneState(
                project: existingLane?.project ?? project,
                sessions: existingLane?.sessions ?? [],
                scienceJobs: project.projectSlug == activeSlug ? activeJobs : (existingLane?.scienceJobs ?? []),
                laneResult: laneResult,
                recentTrail: project.projectSlug == activeSlug ? activeTrail : (existingLane?.recentTrail ?? []),
                truth: truth,
                isCurrent: project.projectSlug == activeSlug,
                livingQuestion: pinnedQuestions[project.projectSlug],
                carriedObjective: project.projectSlug == activeSlug
                    ? (existingLane?.carriedObjective ?? lastMeaningfulLaneObjective(in: existingLane?.sessions ?? []))
                    : existingLane?.carriedObjective
            )
        }

        lanes.sort { lhs, rhs in
            let lhsFocused = lhs.project.projectSlug == activeSlug
            let rhsFocused = rhs.project.projectSlug == activeSlug
            if lhsFocused != rhsFocused { return lhsFocused }
            let lhsObservedResult = observedResultSlugs.contains(lhs.project.projectSlug)
            let rhsObservedResult = observedResultSlugs.contains(rhs.project.projectSlug)
            if lhsObservedResult != rhsObservedResult { return lhsObservedResult }
            let lhsAnyResult = lhs.laneResult != nil
            let rhsAnyResult = rhs.laneResult != nil
            if lhsAnyResult != rhsAnyResult { return lhsAnyResult }
            return lhs.project.projectSlug < rhs.project.projectSlug
        }

        return lanes
    }

    private func focusProjectLane(_ project: Project) {
        cognitive.activeProjectSlug = project.projectSlug
        let family = ProjectFamily.fromProjectSlug(project.projectSlug)
        conversation.restoreContext(
            projectSlug: project.projectSlug,
            projectFamily: family,
            publicationScope: PublicationScope.forProjectFamily(family)
        )
    }

    private func liveAgentLabel(_ session: AgentSession) -> String {
        if let kind = session.kind, !kind.isEmpty {
            return kind.replacingOccurrences(of: "-", with: " ").capitalized
        }
        if let name = session.name, !name.isEmpty {
            return name
        }
        return "Agent"
    }

    private func orderedSessions(for lane: ProjectLaneState) -> [AgentSession] {
        lane.sessions.sorted { lhs, rhs in
            if lhs.isRunning != rhs.isRunning {
                return lhs.isRunning && !rhs.isRunning
            }
            return liveAgentLabel(lhs) < liveAgentLabel(rhs)
        }
    }

    private func laneAgentRow(_ session: AgentSession) -> some View {
        HStack(alignment: .top, spacing: BeagleSpacing.sm) {
            PresencePill(
                label: liveAgentLabel(session),
                systemImage: sessionRoleIcon(session),
                tint: sessionRoleTint(session)
            )

            VStack(alignment: .leading, spacing: 2) {
                Text(sessionActivityLine(session))
                    .font(BeagleFont.footnote.font)
                    .foregroundStyle(BeagleTheme.textPrimary)
                    .lineLimit(2)
                Text(sessionStateLine(session))
                    .font(BeagleFont.caption2.font)
                    .foregroundStyle(BeagleTheme.textTertiary)
                    .lineLimit(1)
            }

            Spacer()
        }
    }

    private var discussionTruth: TruthMode {
        if !conversation.isEmpty {
            return .observed
        }
        if LocalLLMEngine.shared.isReady || cognitive.serverReachable {
            return .remembered
        }
        return .declared
    }

    private var discussionProfileLabel: String {
        "\(conversation.discussionProfile.label) · \(physio.summary.conversationPolicy.modeLabel)"
    }

    private var discussionNarrative: String {
        let laneName = focusedLane.map { projectDisplayName($0.project.projectSlug) } ?? "this lane"
        if let latestThought = cognitive.recentThoughts.first?.refinedText ?? cognitive.recentThoughts.first?.rawText,
           !latestThought.isEmpty,
           conversation.isEmpty {
            let snippet = latestThought.count > 88 ? String(latestThought.prefix(88)) + "..." : latestThought
            return "Last thread in \(laneName): “\(snippet)”"
        }

        if conversation.isEmpty {
            return "A place to think in \(laneName). Type a thought — Beagle stays with it."
        }

        return "Keep going — push the idea, challenge it, or ask for the next leap."
    }

    private var discussionStarters: [String] {
        let laneName = focusedLane.map { projectDisplayName($0.project.projectSlug) } ?? "this project"
        var starters: [String] = [
            "What should I focus on in \(laneName) right now?",
            "Help me think through \(laneName) from first principles. What is the real problem underneath it?",
            "What is the next concrete move for \(laneName), and why is it the right move now?",
            "Challenge my current direction in \(laneName). What am I probably missing?"
        ]

        if let latestThought = cognitive.recentThoughts.first?.refinedText ?? cognitive.recentThoughts.first?.rawText,
           !latestThought.isEmpty {
            let snippet = latestThought.count > 120 ? String(latestThought.prefix(120)) + "..." : latestThought
            starters.insert("Take this idea seriously and help me deepen it: \(snippet)", at: 0)
        }

        if physio.summary.readiness != .unavailable {
            starters.insert(physio.summary.recommendedPrompt, at: min(1, starters.count))
        }

        return Array(starters.prefix(4))
    }

    private var currentLaneQuestionKey: String {
        focusedLane?.project.projectSlug ?? preferredLaneSlug
    }

    private var pinnedQuestionForCurrentLane: String? {
        pinnedQuestion(for: currentLaneQuestionKey)
    }

    private var pinnedLaneQuestions: [String: String] {
        guard let data = pinnedLaneQuestionsJSON.data(using: .utf8),
              let decoded = try? JSONDecoder().decode([String: String].self, from: data) else {
            return [:]
        }
        return decoded
    }

    private func pinQuestionForCurrentLane(_ question: String) {
        var updated = pinnedLaneQuestions
        updated[currentLaneQuestionKey] = question
        if let data = try? JSONEncoder().encode(updated),
           let json = String(data: data, encoding: .utf8) {
            pinnedLaneQuestionsJSON = json
        }
    }

    private func clearPinnedQuestionForCurrentLane() {
        var updated = pinnedLaneQuestions
        updated.removeValue(forKey: currentLaneQuestionKey)
        if let data = try? JSONEncoder().encode(updated),
           let json = String(data: data, encoding: .utf8) {
            pinnedLaneQuestionsJSON = json
        }
    }

    private func pinnedQuestion(for slug: String) -> String? {
        pinnedLaneQuestions[slug]
    }

    private func makeLaneState(
        project: Project,
        sessions: [AgentSession],
        truth: TruthMode,
        laneResult: MobileLaneResultSummary? = nil
    ) -> ProjectLaneState {
        let isCurrent = project.projectSlug == preferredLaneSlug
        let carriedObjective = isCurrent ? lastMeaningfulLaneObjective(in: sessions) : nil
        return ProjectLaneState(
            project: project,
            sessions: sessions,
            scienceJobs: isCurrent ? cognitive.activeJobs : [],
            laneResult: laneResult,
            recentTrail: isCurrent ? CognitiveStore.recentTrailSnippets(from: cognitive.recentThoughts) : [],
            truth: truth,
            isCurrent: isCurrent,
            livingQuestion: pinnedQuestion(for: project.projectSlug),
            carriedObjective: carriedObjective
        )
    }

    private func laneResultSummary(for slug: String) -> MobileLaneResultSummary? {
        homeSummary?.value?.laneResults?.first(where: { $0.projectSlug == slug })
            ?? cachedLaneResults.first(where: { $0.projectSlug == slug })
    }

    private func placeholderProject(for slug: String) -> Project {
        switch slug {
        case "sounio":
            return Project(projectSlug: slug, preferredPrBase: "integration/sounio-dev-ready-base")
        default:
            return Project(projectSlug: slug)
        }
    }

    private func lastMeaningfulLaneObjective(in sessions: [AgentSession]) -> String? {
        sessions.first(where: \.isRunning)?.presentedActivityLine
            ?? sessions.first(where: { $0.phase == .paused })?.presentedActivityLine
            ?? sessions.first?.presentedActivityLine
    }


    private var cachedLaneResults: [MobileLaneResultSummary] {
        guard let data = cachedLaneResultsJSON.data(using: .utf8),
              let decoded = try? JSONDecoder().decode([MobileLaneResultSummary].self, from: data) else {
            return []
        }
        return decoded
    }

    private func persistLaneResults(_ incoming: [MobileLaneResultSummary]) {
        guard !incoming.isEmpty else { return }
        var merged = Dictionary(uniqueKeysWithValues: cachedLaneResults.map { ($0.projectSlug, $0) })
        for item in incoming {
            merged[item.projectSlug] = item
        }
        let ordered = merged.values.sorted { $0.projectSlug < $1.projectSlug }
        if let data = try? JSONEncoder().encode(ordered),
           let json = String(data: data, encoding: .utf8) {
            cachedLaneResultsJSON = json
        }
    }

    private func prepareDraft(_ text: String) {
        inputText = text
        inputFocusRequest += 1
    }

    private func sessionRoleIcon(_ session: AgentSession) -> String {
        switch session.kind {
        case "claude-code":
            return "sparkles"
        case "codex":
            return "curlybraces"
        case "local-sglang":
            return "cpu"
        default:
            return "brain.head.profile"
        }
    }

    private func sessionRoleTint(_ session: AgentSession) -> Color {
        switch session.phase {
        case .running:
            return BeagleTheme.truthObserved
        case .paused:
            return BeagleTheme.postureWarm
        case .pending:
            return BeagleTheme.truthRemembered
        }
    }

    private func sessionActivityLine(_ session: AgentSession) -> String {
        if let summary = session.activity?.summary?.trimmingCharacters(in: .whitespacesAndNewlines), !summary.isEmpty {
            return summary
        }

        if let action = session.action?.trimmingCharacters(in: .whitespacesAndNewlines), !action.isEmpty {
            return action
                .replacingOccurrences(of: "-", with: " ")
                .replacingOccurrences(of: "_", with: " ")
                .capitalized
        }

        switch session.phase {
        case .running:
            return "Holding the live thread and ready for input."
        case .paused:
            return "Paused with its context preserved."
        case .pending:
            return "Crossing into the cluster and not ready yet."
        }
    }

    private func sessionStateLine(_ session: AgentSession) -> String {
        if let source = session.activity?.source, !source.isEmpty,
           let updatedAt = session.activity?.updatedAt, !updatedAt.isEmpty,
           let relative = relativeTime(from: updatedAt)
        {
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

    private func projectDisplayName(_ slug: String) -> String {
        guard !slug.isEmpty else { return "Unassigned" }
        return slug
            .split(separator: "-")
            .map { $0.capitalized }
            .joined(separator: " ")
    }

    // MARK: - Helpers

    private func relativeTime(from isoString: String) -> String? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: isoString) ?? ISO8601DateFormatter().date(from: isoString) {
            let seconds = Int(Date.now.timeIntervalSince(date))
            if seconds < 60 { return "just now" }
            if seconds < 3600 { return "\(seconds / 60)m ago" }
            if seconds < 86400 { return "\(seconds / 3600)h ago" }
            if seconds < 172800 { return "yesterday" }
            return "\(seconds / 86400)d ago"
        }
        return nil
    }

    // MARK: - Provocation generation (on-device LLM)

    // MARK: - Metacognitive Dialogue

    @ViewBuilder
    private var metacognitiveStrip: some View {
        if !metacognitive.observations.isEmpty && currentIntensity != .minimal {
            VStack(alignment: .leading, spacing: BeagleSpacing.sm) {
                HStack(spacing: BeagleSpacing.xs) {
                    Image(systemName: "brain.head.profile")
                        .font(.system(size: 11))
                        .foregroundStyle(metacognitiveAccentColor)
                    Text("Metacognition")
                        .font(BeagleFont.caption.font)
                        .fontWeight(.medium)
                        .foregroundStyle(BeagleTheme.textTertiary)
                }

                ForEach(Array(metacognitive.observations.enumerated()), id: \.element.id) { index, observation in
                    metacognitiveCard(observation, index: index)
                }
            }
            .transition(.opacity.combined(with: .move(edge: .top)))
        }
    }

    private func metacognitiveCard(_ observation: MetacognitiveObservation, index: Int) -> some View {
        HStack(alignment: .top, spacing: BeagleSpacing.sm) {
            ZStack {
                Circle()
                    .fill(metacognitiveCardColor(observation.severity).opacity(0.1))
                    .frame(width: 34, height: 34)
                Image(systemName: metacognitiveIcon(observation.severity))
                    .font(.system(size: 14))
                    .foregroundStyle(metacognitiveCardColor(observation.severity))
            }

            VStack(alignment: .leading, spacing: BeagleSpacing.xs) {
                Text(observation.message)
                    .font(BeagleFont.subheadline.font)
                    .foregroundStyle(BeagleTheme.textPrimary)
                    .lineSpacing(2)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: BeagleSpacing.sm) {
                    if observation.action != .none {
                        Button {
                            handleMetacognitiveAction(observation.action)
                            metacognitive.dismiss(observation.id)
                        } label: {
                            Text(metacognitiveActionLabel(observation.action))
                                .font(BeagleFont.caption.font)
                                .fontWeight(.medium)
                                .foregroundStyle(metacognitiveCardColor(observation.severity))
                        }
                        .buttonStyle(ScalePress())
                    }

                    Spacer()

                    Button {
                        withAnimation(.easeOut(duration: 0.25)) {
                            metacognitive.dismiss(observation.id)
                        }
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(BeagleTheme.textTertiary)
                    }
                    .buttonStyle(ScalePress())
                }
            }
        }
        .padding(.horizontal, BeagleSpacing.md)
        .padding(.vertical, BeagleSpacing.sm)
        .background(
            RoundedRectangle(cornerRadius: BeagleRadius.lg, style: .continuous)
                .fill(metacognitiveCardColor(observation.severity).opacity(0.04))
                .overlay(
                    RoundedRectangle(cornerRadius: BeagleRadius.lg, style: .continuous)
                        .strokeBorder(metacognitiveCardColor(observation.severity).opacity(0.1), lineWidth: 0.5)
                )
        )
        .staggeredAppear(index: index, delay: 0.08)
    }

    private var metacognitiveAccentColor: Color {
        switch metacognitive.currentState {
        case .flow: return BeagleTheme.truthObserved
        case .nominal: return BeagleTheme.textSecondary
        case .surfaceThinking: return .orange
        case .stagnating: return .yellow
        case .fatigued: return BeagleTheme.truthStale
        }
    }

    private func metacognitiveIcon(_ severity: MetacognitiveObservation.Severity) -> String {
        switch severity {
        case .celebration: return "sparkles"
        case .suggestion: return "lightbulb.fill"
        case .nudge: return "arrow.right.circle.fill"
        case .gentle: return "heart.fill"
        }
    }

    private func metacognitiveCardColor(_ severity: MetacognitiveObservation.Severity) -> Color {
        switch severity {
        case .celebration: return BeagleTheme.truthObserved
        case .suggestion: return .orange
        case .nudge: return .yellow
        case .gentle: return BeagleTheme.truthRemembered
        }
    }

    private func metacognitiveActionLabel(_ action: MetacognitiveObservation.SuggestedAction) -> String {
        switch action {
        case .tryQuantumMode: return "Try Quantum Mode"
        case .injectSerendipity: return "Inject Chaos"
        case .reduceIntensity: return "Ease Off"
        case .promptCapture: return "Capture a Thought"
        case .suggestGoDeep: return "Go Deep"
        case .quickCapture: return "Quick Capture"
        case .none: return ""
        }
    }

    private func handleMetacognitiveAction(_ action: MetacognitiveObservation.SuggestedAction) {
        switch action {
        case .tryQuantumMode:
            // Navigate to deep exploration
            selectedTab = 2
        case .injectSerendipity:
            chaosProvocation = SerendipityEngine.shared.generateProvocation()
        case .reduceIntensity:
            // Gentle hint — no forced action, just acknowledged
            break
        case .promptCapture:
            inputFocusRequest += 1
        case .suggestGoDeep:
            selectedTab = 2
        case .quickCapture:
            inputFocusRequest += 1
        case .none:
            break
        }
    }

    private func runMetacognitiveCheck() {
        let thoughts = cognitive.recentThoughts
        let stagnation = SerendipityEngine.shared.detectStagnation(thoughts: thoughts)
        let posture = physio.cognitivePosture

        // Compute time since last thought capture
        let timeSinceLastCapture: TimeInterval? = {
            guard let latest = thoughts.first,
                  let dateString = latest.createdAt else { return nil }
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            guard let date = formatter.date(from: dateString) ?? ISO8601DateFormatter().date(from: dateString) else { return nil }
            return Date().timeIntervalSince(date)
        }()

        metacognitive.observe(
            consciousnessScore: cognitive.lastConsciousnessScore,
            stagnation: stagnation,
            posture: posture,
            thoughtCount: thoughts.count,
            timeSinceLastCapture: timeSinceLastCapture
        )
    }

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

// MARK: - Home Gradient (circadian, warm, alive)

/// The home screen breathes with a circadian rhythm.
/// Morning: warm amber glow. Afternoon: focused teal. Evening: soft violet.
/// Night: deep indigo with a gentle heartbeat. The more thoughts you have,
/// the more alive the mesh becomes — your intellectual presence warms the space.
private struct HomeGradient: View {
    let thoughtCount: Int
    let hasJobs: Bool
    @State private var phase: CGFloat = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        MeshGradient(
            width: 3, height: 3,
            points: animatedPoints,
            colors: gradientColors
        )
        .ignoresSafeArea()
        .onAppear {
            guard !reduceMotion, !ProcessInfo.processInfo.isLowPowerModeEnabled else { return }
            // One-shot settle drift instead of repeatForever: the mesh eases into its
            // resting position once and stops. A perpetual MeshGradient animation kept the
            // GPU/CPU redrawing an idle Home forever (part of the ~7-8% idle-CPU cost).
            withAnimation(.easeInOut(duration: 10)) {
                phase = 1
            }
        }
    }

    private var animatedPoints: [SIMD2<Float>] {
        // Slower breathing than other views — this is home, not a cockpit
        let d: Float = reduceMotion ? 0 : Float(phase) * 0.05
        return [
            SIMD2(0,       0),     SIMD2(0.5,     0),       SIMD2(1,       0),
            SIMD2(0+d,     0.5-d), SIMD2(0.5+d,   0.5+d),   SIMD2(1-d,     0.5+d),
            SIMD2(0,       1),     SIMD2(0.5,     1),       SIMD2(1,       1)
        ]
    }

    private var gradientColors: [Color] {
        let base = Color(red: 0.02, green: 0.03, blue: 0.06)
        let hour = Calendar.current.component(.hour, from: Date())

        // Intellectual presence: more thoughts = warmer mesh
        let presenceWarmth = min(Double(thoughtCount) * 0.015, 0.20)

        // Circadian accent
        let accent: Color
        let accentIntensity: Double

        switch hour {
        case 5..<10:
            // Morning: amber warmth, gentle
            accent = Color(hue: 35/360, saturation: 0.7, brightness: 0.9)
            accentIntensity = 0.12 + presenceWarmth
        case 10..<17:
            // Day: teal focus, productive
            accent = BeagleTheme.truthObserved
            accentIntensity = 0.10 + presenceWarmth
        case 17..<21:
            // Evening: violet-blue, reflective
            accent = Color(hue: 250/360, saturation: 0.4, brightness: 0.7)
            accentIntensity = 0.10 + presenceWarmth
        default:
            // Night: deep indigo, quiet, safe
            accent = Color(hue: 240/360, saturation: 0.3, brightness: 0.5)
            accentIntensity = 0.06 + presenceWarmth
        }

        let jobGlow = hasJobs ? BeagleTheme.postureWarm.opacity(0.08) : Color(white: 0.03)

        return [
            accent.opacity(accentIntensity),
            accent.opacity(accentIntensity * 0.3),
            Color(white: 0.03),

            jobGlow,
            base,
            Color(white: 0.03),

            base, base, Color(white: 0.02)
        ]
    }
}

struct LaneResultCard: View {
    let lane: ProjectLaneState
    var compact: Bool = false

    private var result: MobileLaneResultSummary? { lane.laneResult }

    var body: some View {
        if let result {
            VStack(alignment: .leading, spacing: compact ? BeagleSpacing.sm : BeagleSpacing.md) {
                HStack(alignment: .firstTextBaseline, spacing: BeagleSpacing.sm) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(compact ? "Returned Work" : "What Came Back")
                            .font(BeagleFont.caption.font)
                            .fontWeight(.semibold)
                            .foregroundStyle(BeagleTheme.truthRemembered)
                            .textCase(.uppercase)
                            .tracking(0.7)
                        Text(result.displayHeadline)
                            .font(compact ? BeagleFont.footnote.font : BeagleFont.body.font)
                            .fontWeight(.semibold)
                            .foregroundStyle(BeagleTheme.textPrimary)
                            .lineLimit(compact ? 2 : 3)
                    }
                    Spacer()
                    PresencePill(
                        label: result.displayStateLabel,
                        systemImage: result.readyForOpen ? "checkmark.seal.fill" : "clock.badge",
                        tint: result.readyForOpen ? BeagleTheme.truthObserved : BeagleTheme.postureWarm
                    )
                }

                HStack(spacing: BeagleSpacing.xs) {
                    if let node = result.displayNodeLabel {
                        PresencePill(label: node, systemImage: "server.rack", tint: BeagleTheme.truthObserved)
                    }
                    if let age = result.resultAgeLabel {
                        PresencePill(label: age, systemImage: "clock", tint: BeagleTheme.textSecondary)
                    }
                    if let profile = nonEmpty(result.profileId) {
                        PresencePill(label: profile, systemImage: "dial.high", tint: BeagleTheme.truthRemembered)
                    }
                }

                Text(result.humanSummary)
                    .font(compact ? BeagleFont.caption.font : BeagleFont.footnote.font)
                    .foregroundStyle(BeagleTheme.textSecondary)
                    .lineSpacing(2)
                    .lineLimit(compact ? 2 : 4)

                if !compact {
                    Text(result.readyForOpen
                         ? "This lane already returned something real. Stay with the idea, but anchor it to the artifact that came back."
                         : "A result thread exists here, but it still needs to settle into something you can open and interpret.")
                        .font(BeagleFont.caption.font)
                        .foregroundStyle(BeagleTheme.truthRemembered)
                        .lineSpacing(2)
                }
            }
            .padding(compact ? BeagleSpacing.sm : BeagleSpacing.md)
            .background(
                RoundedRectangle(cornerRadius: compact ? BeagleRadius.md : BeagleRadius.lg)
                    .fill(BeagleTheme.truthRemembered.opacity(compact ? 0.06 : 0.08))
            )
            .overlay(
                RoundedRectangle(cornerRadius: compact ? BeagleRadius.md : BeagleRadius.lg)
                    .strokeBorder(BeagleTheme.truthRemembered.opacity(compact ? 0.12 : 0.16), lineWidth: 1)
            )
        }
    }

    private func nonEmpty(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
