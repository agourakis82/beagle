//
//  GoDeepView+ModalityDetail.swift
//  BeagleCockpit
//
//  Per-modality slot rendering (skeleton → thinking → resolved → failed),
//  expanded per-modality result detail views, and shimmer placeholder.
//

import SwiftUI
import BeagleCore

// MARK: - Modality Slot

/// One slot in the stream — morphs from skeleton → thinking → resolved → failed.
struct ModalitySlot: View {
    let state: ModalityState
    let isExpanded: Bool
    var isCompact: Bool = false
    let onTap: () -> Void
    let onRetry: () -> Void

    internal init(
        state: ModalityState,
        isExpanded: Bool,
        isCompact: Bool = false,
        onTap: @escaping () -> Void,
        onRetry: @escaping () -> Void
    ) {
        self.state = state
        self.isExpanded = isExpanded
        self.isCompact = isCompact
        self.onTap = onTap
        self.onRetry = onRetry
    }

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
        HStack(alignment: .top, spacing: BeagleSpacing.sm) {
            Image(systemName: state.modality.icon)
                .font(.system(size: 12))
                .foregroundStyle(state.modality.themeColor)
                .frame(width: 20)
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: 2) {
                Text(state.modality.displayName)
                    .font(BeagleFont.caption.font)
                    .fontWeight(.medium)
                    .foregroundStyle(BeagleTheme.textSecondary)

                Text(result.summary)
                    .font(BeagleFont.footnote.font)
                    .foregroundStyle(BeagleTheme.textPrimary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
            }

            Spacer()

            TruthBadge(result.truthMode, compact: true)
                .padding(.top, 1)
        }
        .padding(.horizontal, BeagleSpacing.md)
        .padding(.vertical, BeagleSpacing.sm)
        .background(
            RoundedRectangle(cornerRadius: BeagleRadius.md)
                .fill(BeagleTheme.surface1.opacity(0.55))
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
                        .lineLimit(1)

                    Spacer()

                    if isExpanded, let ms = state.durationMs {
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
                    .fixedSize(horizontal: false, vertical: true)

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
        case .astraDeep(let t):     frontierView(t, accent: GoDeepModality.astraDeep.themeColor)
        case .rosalindBio(let t):   frontierView(t, accent: GoDeepModality.rosalindBio.themeColor)
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

    // MARK: - Frontier Research (GPT-6.2 Astra xhigh & GPT-Rosalind Bio/PBPK)

    private func frontierView(_ t: Truthful<FrontierResearchResult>, accent: Color) -> some View {
        VStack(alignment: .leading, spacing: BeagleSpacing.sm) {
            if let v = t.value {
                HStack(spacing: BeagleSpacing.md) {
                    metric("Modelo", v.model)
                    metric("Esforço", v.reasoningEffort.uppercased())
                    if !v.executedTools.isEmpty {
                        metric("Ferramentas", "\(v.executedTools.count)")
                    }
                }

                if !v.executedTools.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: BeagleSpacing.xs) {
                            ForEach(v.executedTools, id: \.self) { tool in
                                Text(tool)
                                    .font(BeagleFont.caption2.font)
                                    .foregroundStyle(accent)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 3)
                                    .background(Capsule().fill(accent.opacity(0.10)))
                            }
                        }
                    }
                }

                sectionLabel("Análise Completa")
                Text(LocalizedStringKey(v.analysisMarkdown))
                    .font(BeagleFont.body.font)
                    .foregroundStyle(BeagleTheme.textPrimary)
                    .tint(accent)
                    .textSelection(.enabled)
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)

                if !v.citations.isEmpty {
                    sectionLabel("Fontes Verificadas (\(v.citations.count))")
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(v.citations) { cite in
                            if let url = URL(string: cite.url) {
                                Link(destination: url) {
                                    HStack(spacing: 6) {
                                        Image(systemName: "arrow.up.right.square")
                                            .font(.system(size: 11))
                                            .foregroundStyle(accent)
                                        Text(cite.title)
                                            .font(BeagleFont.caption.font)
                                            .foregroundStyle(BeagleTheme.textPrimary)
                                            .lineLimit(1)
                                        Spacer()
                                    }
                                    .padding(.horizontal, BeagleSpacing.sm)
                                    .padding(.vertical, 6)
                                    .background(
                                        RoundedRectangle(cornerRadius: BeagleRadius.sm)
                                            .fill(accent.opacity(0.07))
                                    )
                                }
                            }
                        }
                    }
                }
            }
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
