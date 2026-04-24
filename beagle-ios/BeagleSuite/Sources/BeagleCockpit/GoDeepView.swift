//
//  GoDeepView.swift
//  BeagleCockpit
//
//  Go Deeper — multi-modal reasoning exploration.
//
//  Design principles:
//   - All modality slots visible from launch (skeleton → thinking → resolved)
//   - Per-modality thinking text that rotates ("Building research tree...")
//   - Dramatic background shift as results arrive
//   - Synthesis card at end integrates all findings
//   - Error cards have retry affordance
//   - Share/export for research results
//   - 44pt minimum tap targets everywhere
//   - Insight-focused rendering, not data dumps
//

import SwiftUI
import BeagleCore
import Charts

struct GoDeepView: View {
    @Bindable var store: GoDeepStore
    let prompt: String
    @State private var expandedModality: GoDeepModality?
    @State private var hasLaunched = false
    @State private var promptExpanded = false
    @State private var quickTake: String?
    @State private var savedToExocortex = false
    @Environment(\.dismiss) private var dismiss
    @Environment(CognitiveStore.self) private var cognitive

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: BeagleSpacing.lg) {
                    promptHeader
                        .padding(.top, BeagleSpacing.sm)

                    // Quick-take: on-device instant insight while cloud runs
                    if let quickTake, store.synthesis == nil {
                        quickTakeCard(quickTake)
                    }

                    modalityStream

                    if store.isSynthesizing || store.synthesis != nil {
                        synthesisCard
                    }
                }
                .padding(.horizontal, BeagleSpacing.lg)
                .padding(.bottom, BeagleSpacing.jumbo + 20)
            }
            .background { depthGradient }
            .navigationTitle("Go Deeper")
            .navigationBarTitleDisplayModeIfAvailable(.inline)
            .toolbar { toolbarContent }
            .task {
                guard !hasLaunched else { return }
                hasLaunched = true

                // Wire Live Activity callbacks
                store.onResearchStart = { runId, name, slug in
                    LiveActivityManager.shared.startResearchActivity(runId: runId, campaign: name, slug: slug)
                }
                store.onResearchUpdate = { step, total, eta in
                    LiveActivityManager.shared.updateResearchActivity(step: step, total: total, eta: eta)
                }
                store.onResearchEnd = { _ in
                    LiveActivityManager.shared.endResearchActivity()
                    #if os(iOS)
                    BeagleHaptics.goDeepComplete()
                    #endif
                }

                store.goDeeper(prompt: prompt)

                // Fire quick-take on-device (arrives in ~1s, before cloud)
                Task {
                    quickTake = await FoundationModelsAgent.shared.summarize(
                        "A researcher asks: \(prompt)\n\nGive a quick initial take in 2 sentences — what's the most interesting angle to explore here?",
                        instructions: "You are an intellectual companion. Give a brief, sharp initial reaction to a research question. Be specific, not generic."
                    )
                }
            }
        }
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: leadingToolbarPlacement) {
            Button { store.cancel(); dismiss() } label: {
                Text(store.isRunning ? "Cancel" : "Close")
                    .foregroundStyle(BeagleTheme.textSecondary)
            }
        }
        ToolbarItem(placement: trailingToolbarPlacement) {
            if !store.isRunning && store.hasAnyResult {
                ShareLink(
                    item: store.exportText,
                    subject: Text("Go Deeper: \(String(prompt.prefix(40)))"),
                    message: Text("Research exploration results")
                ) {
                    Image(systemName: "square.and.arrow.up")
                        .font(.system(size: 14))
                        .foregroundStyle(BeagleTheme.textSecondary)
                }
            }
        }
    }

    private var leadingToolbarPlacement: ToolbarItemPlacement {
        #if os(macOS)
        return .automatic
        #else
        return .topBarLeading
        #endif
    }

    private var trailingToolbarPlacement: ToolbarItemPlacement {
        #if os(macOS)
        return .automatic
        #else
        return .topBarTrailing
        #endif
    }

    // MARK: - Prompt Header

    private var promptHeader: some View {
        Button {
            withAnimation(BeagleMotion.snappy) { promptExpanded.toggle() }
        } label: {
            VStack(alignment: .leading, spacing: BeagleSpacing.xs) {
                HStack(spacing: BeagleSpacing.xs) {
                    Image(systemName: "scope")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(BeagleTheme.truthRemembered)
                    Text("Exploring")
                        .font(BeagleFont.caption.font)
                        .fontWeight(.medium)
                        .foregroundStyle(BeagleTheme.textTertiary)
                    Spacer()
                    if !promptExpanded {
                        Image(systemName: "chevron.down")
                            .font(.system(size: 9, weight: .medium))
                            .foregroundStyle(BeagleTheme.textTertiary)
                    }
                }
                Text(prompt)
                    .font(BeagleFont.body.font)
                    .foregroundStyle(BeagleTheme.textPrimary)
                    .lineLimit(promptExpanded ? nil : 3)
                    .multilineTextAlignment(.leading)
                    .animation(BeagleMotion.snappy, value: promptExpanded)
            }
            .padding(.horizontal, BeagleSpacing.lg)
            .padding(.vertical, BeagleSpacing.md)
            .background(
                RoundedRectangle(cornerRadius: BeagleRadius.lg)
                    .fill(BeagleTheme.surface1.opacity(0.6))
            )
            .overlay(
                RoundedRectangle(cornerRadius: BeagleRadius.lg)
                    .strokeBorder(BeagleTheme.truthRemembered.opacity(0.12), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Modality Stream (all slots always visible)

    /// When synthesis arrives, compress resolved modalities to compact rows
    /// unless the user has one expanded. The journey compresses; the destination expands.
    private var journeyCompressed: Bool {
        store.synthesis != nil && expandedModality == nil
    }

    private var modalityStream: some View {
        VStack(spacing: journeyCompressed ? BeagleSpacing.xs : BeagleSpacing.md) {
            ForEach(Array(store.modalityStates.enumerated()), id: \.element.id) { index, state in
                ModalitySlot(
                    state: state,
                    isExpanded: expandedModality == state.modality,
                    isCompact: journeyCompressed && state.isResolved,
                    onTap: {
                        withAnimation(BeagleMotion.snappy) {
                            expandedModality = expandedModality == state.modality ? nil : state.modality
                        }
                    },
                    onRetry: { store.retryModality(state.modality) }
                )
                .transition(.opacity.combined(with: .scale(scale: 0.97, anchor: .top)))
                .animation(
                    BeagleMotion.bouncy.delay(Double(index) * 0.06),
                    value: hasLaunched
                )
            }
        }
        .animation(BeagleMotion.slow, value: journeyCompressed)
    }

    // MARK: - Synthesis Card

    private var synthesisCard: some View {
        GlassPanel(elevation: .floating, truth: store.synthesis != nil ? .observed : nil) {
            VStack(alignment: .leading, spacing: BeagleSpacing.sm) {
                HStack(spacing: BeagleSpacing.xs) {
                    Image(systemName: "brain.head.profile.fill")
                        .font(.system(size: 16))
                        .foregroundStyle(
                            LinearGradient(
                                colors: [BeagleTheme.truthObserved, BeagleTheme.truthRemembered],
                                startPoint: .topLeading, endPoint: .bottomTrailing
                            )
                        )

                    Text("Synthesis")
                        .font(BeagleFont.headline.font)
                        .foregroundStyle(BeagleTheme.textPrimary)

                    Spacer()

                    if store.isSynthesizing {
                        ProgressView()
                            .controlSize(.small)
                            .tint(BeagleTheme.truthObserved)
                    } else {
                        TruthBadge(.observed, compact: true)
                    }
                }

                if store.isSynthesizing {
                    Text("Integrating insights across \(store.completedCount) modalities...")
                        .font(BeagleFont.footnote.font)
                        .foregroundStyle(BeagleTheme.textSecondary)
                        .italic()
                } else if let synthesis = store.synthesis {
                    Text(synthesis)
                        .font(BeagleFont.body.font)
                        .foregroundStyle(BeagleTheme.textPrimary)
                        .textSelection(.enabled)
                        .lineSpacing(3)

                    // Save to Exocortex
                    HStack(spacing: BeagleSpacing.sm) {
                        Button {
                            Task {
                                savedToExocortex = true
                                _ = await cognitive.captureThought(
                                    text: synthesis,
                                    source: "go-deeper"
                                )
                            }
                        } label: {
                            HStack(spacing: BeagleSpacing.xxs + 1) {
                                Image(systemName: savedToExocortex ? "checkmark.circle.fill" : "brain")
                                    .font(.system(size: 12))
                                Text(savedToExocortex ? "Saved" : "Save to Exocortex")
                                    .font(BeagleFont.caption.font)
                                    .fontWeight(.medium)
                            }
                            .foregroundStyle(savedToExocortex ? BeagleTheme.truthObserved : BeagleTheme.truthRemembered)
                            .padding(.horizontal, BeagleSpacing.sm + 2)
                            .padding(.vertical, BeagleSpacing.xs)
                            .background(
                                Capsule()
                                    .fill((savedToExocortex ? BeagleTheme.truthObserved : BeagleTheme.truthRemembered).opacity(0.08))
                            )
                        }
                        .buttonStyle(.plain)
                        .disabled(savedToExocortex)
                        .sensoryFeedback(.success, trigger: savedToExocortex)

                        Spacer()
                    }
                }
            }
        }
        .transition(.asymmetric(
            insertion: .push(from: .bottom).combined(with: .opacity),
            removal: .opacity
        ))
        .sensoryFeedback(.success, trigger: store.synthesis != nil)
    }

    // MARK: - Quick Take (on-device, instant)

    private func quickTakeCard(_ text: String) -> some View {
        HStack(alignment: .top, spacing: BeagleSpacing.sm) {
            Image(systemName: "brain")
                .font(.system(size: 13))
                .foregroundStyle(BeagleTheme.truthObserved.opacity(0.7))
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: BeagleSpacing.xxs) {
                Text("Quick Take")
                    .font(BeagleFont.caption.font)
                    .fontWeight(.medium)
                    .foregroundStyle(BeagleTheme.textTertiary)
                    .textCase(.uppercase)
                    .tracking(0.5)

                Text(text)
                    .font(BeagleFont.subheadline.font)
                    .foregroundStyle(BeagleTheme.textSecondary)
                    .lineSpacing(2)
                    .italic()
            }
        }
        .padding(.horizontal, BeagleSpacing.lg)
        .padding(.vertical, BeagleSpacing.md)
        .background(
            RoundedRectangle(cornerRadius: BeagleRadius.lg)
                .fill(BeagleTheme.truthObserved.opacity(0.03))
        )
        .overlay(
            RoundedRectangle(cornerRadius: BeagleRadius.lg)
                .strokeBorder(BeagleTheme.truthObserved.opacity(0.06), lineWidth: 1)
        )
        .transition(.opacity.combined(with: .move(edge: .top)))
    }

    // MARK: - Depth Gradient Background (living MeshGradient)

    private var depthGradient: some View {
        DepthMeshGradient(progress: store.progress, completedCount: store.completedCount)
    }
}

// MARK: - Depth Mesh Gradient

/// Living MeshGradient that breathes and shifts from deep indigo → teal
/// as reasoning results arrive. Same pattern as PostureGradientBackground.
private struct DepthMeshGradient: View {
    let progress: Double
    let completedCount: Int
    @State private var phase: CGFloat = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            MeshGradient(
                width: 3, height: 3,
                points: animatedPoints,
                colors: gradientColors
            )

            // Radial pulse when results arriving
            if progress > 0 && progress < 1 {
                RadialGradient(
                    colors: [
                        BeagleTheme.truthObserved.opacity(phase > 0.5 ? 0.08 : 0.02),
                        .clear
                    ],
                    center: .center,
                    startRadius: 60,
                    endRadius: 600
                )
            }
        }
        .ignoresSafeArea()
        .animation(.easeInOut(duration: 1.5), value: completedCount)
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 7).repeatForever(autoreverses: true)) {
                phase = 1
            }
        }
    }

    private var animatedPoints: [SIMD2<Float>] {
        let d: Float = reduceMotion ? 0 : Float(phase) * 0.07
        return [
            SIMD2(0,     0),     SIMD2(0.5,   0),       SIMD2(1,     0),
            SIMD2(0+d,   0.5-d), SIMD2(0.5+d, 0.5+d),   SIMD2(1-d,   0.5+d),
            SIMD2(0,     1),     SIMD2(0.5,   1),       SIMD2(1,     1)
        ]
    }

    private var gradientColors: [Color] {
        let p = progress
        // Shift from indigo void → teal glow as results arrive
        let tealIntensity = p * 0.30
        let warmIntensity = max(0, (p - 0.5) * 0.15)
        let base = Color(red: 0.02, green: 0.03, blue: 0.07)

        return [
            BeagleTheme.truthObserved.opacity(tealIntensity),
            BeagleTheme.truthRemembered.opacity(tealIntensity * 0.3),
            Color(white: 0.04),

            Color(white: 0.03),
            BeagleTheme.postureWarm.opacity(warmIntensity),
            Color(white: 0.03),

            base, base, Color(white: 0.02)
        ]
    }
}

// MARK: - Modality Slot

/// One slot in the stream — morphs from skeleton → thinking → resolved → failed.
private struct ModalitySlot: View {
    let state: ModalityState
    let isExpanded: Bool
    var isCompact: Bool = false
    let onTap: () -> Void
    let onRetry: () -> Void

    var body: some View {
        Group {
            switch state.phase {
            case .waiting:
                waitingSlot
            case .thinking(let message):
                thinkingSlot(message)
            case .resolved(let result):
                if isCompact && !isExpanded {
                    compactSlot(result)
                } else {
                    resolvedSlot(result)
                }
            case .failed(let message):
                failedSlot(message)
            }
        }
        .sensoryFeedback(.impact(weight: .medium), trigger: state.isResolved)
    }

    // MARK: - Compact (journey compressed)

    private func compactSlot(_ result: GoDeepResult) -> some View {
        HStack(spacing: BeagleSpacing.sm) {
            Image(systemName: state.modality.icon)
                .font(.system(size: 12))
                .foregroundStyle(state.modality.themeColor)
                .frame(width: 20)

            Text(state.modality.displayName)
                .font(BeagleFont.caption.font)
                .fontWeight(.medium)
                .foregroundStyle(BeagleTheme.textSecondary)

            Text("·")
                .foregroundStyle(BeagleTheme.textTertiary)

            Text(result.summary)
                .font(BeagleFont.caption.font)
                .foregroundStyle(BeagleTheme.textTertiary)
                .lineLimit(1)

            Spacer()

            if let ms = state.durationMs {
                Text("\(ms)ms")
                    .font(BeagleFont.caption2.font)
                    .foregroundStyle(BeagleTheme.textTertiary)
            }

            TruthBadge(result.truthMode, compact: true)
        }
        .padding(.horizontal, BeagleSpacing.md)
        .padding(.vertical, BeagleSpacing.xs + 2)
        .background(
            RoundedRectangle(cornerRadius: BeagleRadius.md)
                .fill(BeagleTheme.surface1.opacity(0.3))
        )
        .contentShape(Rectangle())
        .onTapGesture(perform: onTap)
    }

    // MARK: - Waiting (shimmer skeleton)

    private var waitingSlot: some View {
        HStack(spacing: BeagleSpacing.sm) {
            Image(systemName: state.modality.icon)
                .font(.system(size: 14))
                .foregroundStyle(state.modality.themeColor.opacity(0.3))
                .frame(width: 28)

            VStack(alignment: .leading, spacing: BeagleSpacing.xxs) {
                Text(state.modality.displayName)
                    .font(BeagleFont.footnote.font)
                    .fontWeight(.medium)
                    .foregroundStyle(BeagleTheme.textTertiary)

                ShimmerBar()
            }

            Spacer()
        }
        .padding(.horizontal, BeagleSpacing.lg)
        .padding(.vertical, BeagleSpacing.md)
        .background(
            RoundedRectangle(cornerRadius: BeagleRadius.lg)
                .fill(BeagleTheme.surface1.opacity(0.3))
        )
    }

    // MARK: - Thinking (animated status)

    private func thinkingSlot(_ message: String) -> some View {
        HStack(spacing: BeagleSpacing.sm) {
            Image(systemName: state.modality.icon)
                .font(.system(size: 14))
                .foregroundStyle(state.modality.themeColor)
                .symbolEffect(.pulse, isActive: true)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: BeagleSpacing.xxs) {
                Text(state.modality.displayName)
                    .font(BeagleFont.footnote.font)
                    .fontWeight(.medium)
                    .foregroundStyle(BeagleTheme.textPrimary)

                Text(message)
                    .font(BeagleFont.caption.font)
                    .foregroundStyle(state.modality.themeColor.opacity(0.8))
                    .contentTransition(.numericText())
                    .animation(BeagleMotion.normal, value: message)
            }

            Spacer()

            ProgressView()
                .controlSize(.small)
                .tint(state.modality.themeColor)
        }
        .padding(.horizontal, BeagleSpacing.lg)
        .padding(.vertical, BeagleSpacing.md)
        .background(
            RoundedRectangle(cornerRadius: BeagleRadius.lg)
                .fill(state.modality.themeColor.opacity(0.04))
        )
        .overlay(
            RoundedRectangle(cornerRadius: BeagleRadius.lg)
                .strokeBorder(state.modality.themeColor.opacity(0.1), lineWidth: 1)
        )
    }

    // MARK: - Resolved (full result card)

    private func resolvedSlot(_ result: GoDeepResult) -> some View {
        GlassPanel(
            elevation: isExpanded ? .floating : .raised,
            truth: result.truthMode
        ) {
            VStack(alignment: .leading, spacing: BeagleSpacing.sm) {
                // Header
                HStack(spacing: BeagleSpacing.xs) {
                    Image(systemName: state.modality.icon)
                        .font(.system(size: 16))
                        .foregroundStyle(state.modality.themeColor)

                    Text(state.modality.displayName)
                        .font(BeagleFont.headline.font)
                        .foregroundStyle(BeagleTheme.textPrimary)

                    Spacer()

                    if let ms = state.durationMs {
                        Text("\(ms)ms")
                            .font(BeagleFont.dataSmall.font)
                            .foregroundStyle(BeagleTheme.textTertiary)
                    }

                    TruthBadge(result.truthMode, compact: true)

                    Image(systemName: "chevron.down")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(BeagleTheme.textTertiary)
                        .rotationEffect(.degrees(isExpanded ? 0 : -90))
                        .animation(BeagleMotion.snappy, value: isExpanded)
                }

                // Summary — always visible
                Text(result.summary)
                    .font(BeagleFont.subheadline.font)
                    .foregroundStyle(BeagleTheme.textSecondary)
                    .lineLimit(isExpanded ? nil : 2)
                    .lineSpacing(2)

                // Expanded detail
                if isExpanded {
                    Rectangle()
                        .fill(Color.white.opacity(0.06))
                        .frame(height: 1)
                        .padding(.vertical, BeagleSpacing.xxs)

                    ExpandedDetail(result: result)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
        }
        .contentShape(Rectangle())
        .onTapGesture(perform: onTap)
        .sensoryFeedback(.selection, trigger: isExpanded)
    }

    // MARK: - Failed (error with retry)

    private func failedSlot(_ message: String) -> some View {
        HStack(spacing: BeagleSpacing.sm) {
            Image(systemName: state.modality.icon)
                .font(.system(size: 14))
                .foregroundStyle(BeagleTheme.stateError.opacity(0.6))
                .frame(width: 28)

            VStack(alignment: .leading, spacing: BeagleSpacing.xxs) {
                Text(state.modality.displayName)
                    .font(BeagleFont.footnote.font)
                    .fontWeight(.medium)
                    .foregroundStyle(BeagleTheme.textPrimary)

                Text(message)
                    .font(BeagleFont.caption.font)
                    .foregroundStyle(BeagleTheme.stateError)
                    .lineLimit(2)
            }

            Spacer()

            Button {
                onRetry()
            } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(BeagleTheme.truthObserved)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, BeagleSpacing.lg)
        .padding(.vertical, BeagleSpacing.sm)
        .background(
            RoundedRectangle(cornerRadius: BeagleRadius.lg)
                .fill(BeagleTheme.stateError.opacity(0.04))
        )
        .overlay(
            RoundedRectangle(cornerRadius: BeagleRadius.lg)
                .strokeBorder(BeagleTheme.stateError.opacity(0.12), lineWidth: 1)
        )
    }
}

// MARK: - Expanded Detail (per modality)

private struct ExpandedDetail: View {
    let result: GoDeepResult

    var body: some View {
        switch result {
        case .deepResearch(let t):  deepResearchView(t)
        case .quantum(let t):       quantumView(t)
        case .swarm(let t):         swarmView(t)
        case .causal(let t):        causalView(t)
        case .temporal(let t):      genericView(t.value?.summary, fallback: t.value?.result)
        case .neurosymbolic(let t): genericView(t.value?.summary, fallback: t.value?.result)
        case .adversarial(let t):   adversarialView(t)
        case .serendipity(let t):   serendipityView(t)
        }
    }

    // MARK: - Deep Research

    private func deepResearchView(_ t: Truthful<DeepResearchResult>) -> some View {
        VStack(alignment: .leading, spacing: BeagleSpacing.sm) {
            if let v = t.value {
                if let hyp = v.bestHypothesis {
                    sectionLabel("Best Hypothesis")
                    Text(hyp)
                        .font(BeagleFont.body.font)
                        .foregroundStyle(BeagleTheme.textPrimary)
                        .textSelection(.enabled)
                        .lineSpacing(2)
                }

                HStack(spacing: BeagleSpacing.lg) {
                    metric("Tree", "\(v.treeSize ?? 0) nodes")
                    metric("Iterations", "\(v.iterations ?? 0)")
                }
                .padding(.top, BeagleSpacing.xxs)
            }
        }
    }

    // MARK: - Quantum

    private func quantumView(_ t: Truthful<QuantumReasoningResult>) -> some View {
        VStack(alignment: .leading, spacing: BeagleSpacing.sm) {
            if let v = t.value, let ranked = v.rankedHypotheses, !ranked.isEmpty {
                sectionLabel("Ranked Hypotheses")

                ForEach(ranked.prefix(5)) { h in
                    HStack(spacing: BeagleSpacing.sm) {
                        // Probability bar
                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                Capsule()
                                    .fill(Color.white.opacity(0.04))
                                Capsule()
                                    .fill(BeagleTheme.truthRemembered.opacity(0.5))
                                    .frame(width: max(4, geo.size.width * (h.probability ?? 0)))
                            }
                        }
                        .frame(width: 60, height: 6)

                        Text(String(format: "%.0f%%", (h.probability ?? 0) * 100))
                            .font(BeagleFont.dataSmall.font)
                            .foregroundStyle(BeagleTheme.truthRemembered)
                            .frame(width: 36, alignment: .trailing)

                        Text(h.content ?? "—")
                            .font(BeagleFont.footnote.font)
                            .foregroundStyle(BeagleTheme.textPrimary)
                            .lineLimit(2)
                    }
                }

                if let meta = v.metadata, let ms = meta.processingTimeMs {
                    metric("Processing", "\(ms)ms")
                        .padding(.top, BeagleSpacing.xxs)
                }
            }
        }
    }

    // MARK: - Swarm

    private func swarmView(_ t: Truthful<SwarmResult>) -> some View {
        VStack(alignment: .leading, spacing: BeagleSpacing.sm) {
            if let v = t.value {
                HStack(spacing: BeagleSpacing.lg) {
                    metric("Agents", "\(v.nAgents ?? 0)")
                    metric("Rounds", "\(v.iterations ?? 0)")
                }

                if let consensus = v.consensus, !consensus.isEmpty {
                    sectionLabel("Consensus Points")
                    ForEach(Array(consensus.prefix(5).enumerated()), id: \.offset) { _, point in
                        HStack(alignment: .top, spacing: BeagleSpacing.xs) {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 10))
                                .foregroundStyle(BeagleTheme.postureWarm)
                                .padding(.top, 3)
                            Text(point)
                                .font(BeagleFont.footnote.font)
                                .foregroundStyle(BeagleTheme.textPrimary)
                                .lineSpacing(2)
                        }
                    }
                }
            }
        }
    }

    // MARK: - Causal

    private func causalView(_ t: Truthful<CausalGraph>) -> some View {
        VStack(alignment: .leading, spacing: BeagleSpacing.sm) {
            if let v = t.value {
                if let summary = v.summary {
                    Text(summary)
                        .font(BeagleFont.body.font)
                        .foregroundStyle(BeagleTheme.textPrimary)
                        .lineSpacing(2)
                }

                if let edges = v.edges, !edges.isEmpty {
                    sectionLabel("Causal Chains (\(edges.count))")
                    ForEach(edges.prefix(6)) { edge in
                        HStack(spacing: BeagleSpacing.xs) {
                            Text(edge.source ?? "?")
                                .font(BeagleFont.data.font)
                                .foregroundStyle(BeagleTheme.textData)
                            Image(systemName: "arrow.right")
                                .font(.system(size: 9, weight: .semibold))
                                .foregroundStyle(BeagleTheme.truthDeclared)
                            Text(edge.target ?? "?")
                                .font(BeagleFont.data.font)
                                .foregroundStyle(BeagleTheme.textData)
                            Spacer()
                            if let s = edge.strength {
                                Text(String(format: "%.0f%%", s * 100))
                                    .font(BeagleFont.dataSmall.font)
                                    .foregroundStyle(BeagleTheme.textTertiary)
                            }
                        }
                    }
                }
            }
        }
    }

    // MARK: - Adversarial

    private func adversarialView(_ t: Truthful<AdversarialResult>) -> some View {
        VStack(alignment: .leading, spacing: BeagleSpacing.sm) {
            if let v = t.value {
                if let winner = v.winner {
                    HStack(spacing: BeagleSpacing.xs) {
                        Image(systemName: "trophy.fill")
                            .font(.system(size: 12))
                            .foregroundStyle(BeagleTheme.postureWarm)
                        Text(winner)
                            .font(BeagleFont.headline.font)
                            .foregroundStyle(BeagleTheme.textPrimary)
                    }
                }

                HStack(spacing: BeagleSpacing.lg) {
                    metric("Rounds", "\(v.rounds ?? 0)")
                    metric("Agents", "\(v.agents?.count ?? 0)")
                }

                if let agents = v.agents, !agents.isEmpty {
                    sectionLabel("Scoreboard")
                    ForEach(agents.prefix(5)) { agent in
                        HStack {
                            Text(agent.name ?? "?")
                                .font(BeagleFont.data.font)
                                .foregroundStyle(BeagleTheme.textPrimary)
                            Spacer()
                            if let score = agent.score {
                                Text(String(format: "%.1f", score))
                                    .font(BeagleFont.dataProminent.font)
                                    .fontWeight(.bold)
                                    .foregroundStyle(BeagleTheme.stateError)
                            }
                        }
                    }
                }
            }
        }
    }

    // MARK: - Serendipity

    private func serendipityView(_ t: Truthful<SerendipityResult>) -> some View {
        VStack(alignment: .leading, spacing: BeagleSpacing.sm) {
            if let v = t.value {
                if let connections = v.connections, !connections.isEmpty {
                    ForEach(connections.prefix(5)) { conn in
                        VStack(alignment: .leading, spacing: BeagleSpacing.xxs) {
                            HStack(spacing: BeagleSpacing.xxs) {
                                Text(conn.from ?? "?")
                                    .font(BeagleFont.data.font)
                                    .foregroundStyle(BeagleTheme.textData)
                                Image(systemName: "sparkle")
                                    .font(.system(size: 10))
                                    .foregroundStyle(GoDeepModality.serendipity.themeColor)
                                Text(conn.to ?? "?")
                                    .font(BeagleFont.data.font)
                                    .foregroundStyle(BeagleTheme.textData)
                                Spacer()
                                if let surprise = conn.surprise {
                                    Text("\(Int(surprise * 100))% surprise")
                                        .font(BeagleFont.caption2.font)
                                        .foregroundStyle(GoDeepModality.serendipity.themeColor.opacity(0.7))
                                }
                            }
                            if let explanation = conn.explanation {
                                Text(explanation)
                                    .font(BeagleFont.caption.font)
                                    .foregroundStyle(BeagleTheme.textSecondary)
                                    .lineLimit(3)
                                    .lineSpacing(1)
                            }
                        }
                        .padding(.vertical, BeagleSpacing.xxs)
                    }
                } else {
                    genericView(v.summary, fallback: v.result)
                }
            }
        }
    }

    // MARK: - Generic (temporal, neurosymbolic, or unknown)

    private func genericView(_ summary: String?, fallback: JSONValue?) -> some View {
        VStack(alignment: .leading, spacing: BeagleSpacing.xs) {
            if let summary, !summary.isEmpty {
                Text(summary)
                    .font(BeagleFont.body.font)
                    .foregroundStyle(BeagleTheme.textPrimary)
                    .textSelection(.enabled)
                    .lineSpacing(2)
            } else if let fallback {
                Text(fallback.displayString)
                    .font(BeagleFont.data.font)
                    .foregroundStyle(BeagleTheme.textData)
                    .lineLimit(15)
            } else {
                Text("No structured data returned")
                    .font(BeagleFont.footnote.font)
                    .foregroundStyle(BeagleTheme.textTertiary)
                    .italic()
            }
        }
    }

    // MARK: - Helpers

    private func sectionLabel(_ text: String) -> some View {
        Text(text)
            .font(BeagleFont.caption.font)
            .fontWeight(.medium)
            .foregroundStyle(BeagleTheme.textTertiary)
            .textCase(.uppercase)
            .tracking(0.5)
    }

    private func metric(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(BeagleFont.caption2.font)
                .foregroundStyle(BeagleTheme.textTertiary)
                .textCase(.uppercase)
                .tracking(0.5)
            Text(value)
                .font(BeagleFont.dataProminent.font)
                .foregroundStyle(BeagleTheme.textData)
        }
    }
}

// MARK: - Shimmer Bar (inline skeleton)

private struct ShimmerBar: View {
    @State private var phase: CGFloat = -0.3

    var body: some View {
        RoundedRectangle(cornerRadius: 4)
            .fill(Color.white.opacity(0.04))
            .frame(height: 10)
            .overlay(
                GeometryReader { geo in
                    LinearGradient(
                        colors: [.clear, Color.white.opacity(0.06), .clear],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                    .frame(width: geo.size.width * 0.4)
                    .offset(x: geo.size.width * phase)
                }
                .clipped()
            )
            .clipShape(RoundedRectangle(cornerRadius: 4))
            .onAppear {
                withAnimation(.easeInOut(duration: 1.5).repeatForever(autoreverses: false)) {
                    phase = 1.3
                }
            }
    }
}
