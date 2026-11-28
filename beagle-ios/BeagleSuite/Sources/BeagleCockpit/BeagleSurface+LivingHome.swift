//
//  BeagleSurface+LivingHome.swift
//  BeagleCockpit
//
//  Living Home views, continuity explanation sheet, and Origin Observatory sheet.
//

import SwiftUI
import BeagleCore

// MARK: - Living Home

struct LivingHomeHeader: View {
    let context: HomeContinuityContext
    let home: ExocortexHomeSnapshot
    let presence: BeaglePresenceState
    let truthMode: TruthMode
    let isLoading: Bool
    let onRefresh: () -> Void
    let onExplain: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: BeagleSpacing.sm) {
            HStack(alignment: .top, spacing: BeagleSpacing.sm) {
                ZStack {
                    Circle()
                        .fill(presence.tint.opacity(0.16))
                        .frame(width: 38, height: 38)
                    Image(systemName: presence.icon)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(presence.tint)
                        .symbolEffect(.pulse, isActive: context.mode == .live)
                }

                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: BeagleSpacing.xs) {
                        Text("LIVING HOME")
                            .font(BeagleFont.caption2.font)
                            .fontWeight(.semibold)
                            .foregroundStyle(BeagleTheme.textTertiary)
                        Text(context.mode.rawValue.uppercased())
                            .font(BeagleFont.caption2.font.monospaced())
                            .foregroundStyle(modeColor)
                    }
                    Text(home.currentSelf.label)
                        .font(BeagleFont.callout.font)
                        .fontWeight(.semibold)
                        .foregroundStyle(BeagleTheme.textPrimary)
                        .lineLimit(2)
                        .minimumScaleFactor(0.82)
                    Text(home.todayBrief)
                        .font(BeagleFont.caption.font)
                        .foregroundStyle(BeagleTheme.textSecondary)
                        .lineLimit(3)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: BeagleSpacing.xs)

                VStack(alignment: .trailing, spacing: BeagleSpacing.xs) {
                    TruthBadge(truthMode, compact: true)
                    Button(action: onRefresh) {
                        Image(systemName: isLoading ? "arrow.triangle.2.circlepath" : "arrow.clockwise")
                            .font(.system(size: 12, weight: .semibold))
                            .symbolEffect(.pulse, isActive: isLoading)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(BeagleTheme.textSecondary)
                    .help("Refresh Living Home")
                    .disabled(isLoading)
                }
            }

            Button(action: onExplain) {
                HStack(alignment: .firstTextBaseline, spacing: BeagleSpacing.xs) {
                    Image(systemName: "questionmark.circle")
                        .font(.system(size: 10, weight: .semibold))
                    Text(context.whyThisNow)
                        .font(BeagleFont.caption.font)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: BeagleSpacing.xs)
                    Text("\(Int(context.confidence * 100))%")
                        .font(BeagleFont.caption2.font.monospaced())
                }
                .foregroundStyle(BeagleTheme.textTertiary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Why this now")
        }
    }

    private var modeColor: Color {
        if context.mode == .live {
            return BeagleTheme.truthObserved
        }
        if context.mode == .remembered {
            return BeagleTheme.truthRemembered
        }
        if context.mode == .offline {
            return BeagleTheme.truthStale
        }
        if context.mode == .review {
            return BeagleTheme.postureWarm
        }
        if context.mode == .capture {
            return BeagleTheme.truthObserved
        }
        return BeagleTheme.textTertiary
    }
}

struct ContinuityDeltaBand: View {
    let context: HomeContinuityContext
    let onExplain: () -> Void

    var body: some View {
        Button(action: onExplain) {
            VStack(alignment: .leading, spacing: BeagleSpacing.xs) {
                HStack(spacing: BeagleSpacing.xs) {
                    Image(systemName: "clock.arrow.circlepath")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(BeagleTheme.truthRemembered)
                    Text("WHAT CHANGED")
                        .font(BeagleFont.caption2.font)
                        .fontWeight(.semibold)
                        .foregroundStyle(BeagleTheme.textTertiary)
                    Spacer(minLength: BeagleSpacing.xs)
                    Text(context.sourceMode)
                        .font(BeagleFont.caption2.font.monospaced())
                        .foregroundStyle(BeagleTheme.textTertiary)
                        .lineLimit(1)
                }

                if context.changedSinceLastOpen.isEmpty {
                    Text("No fresh write is visible yet; Beagle is holding the last known thread.")
                        .font(BeagleFont.caption.font)
                        .foregroundStyle(BeagleTheme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: BeagleSpacing.xs) {
                            ForEach(context.changedSinceLastOpen.prefix(5)) { signal in
                                continuityChip(signal)
                            }
                        }
                        .padding(.vertical, 1)
                    }
                }
            }
            .padding(BeagleSpacing.sm)
            .background(
                RoundedRectangle(cornerRadius: BeagleRadius.md, style: .continuous)
                    .fill(BeagleTheme.surface1.opacity(0.34))
            )
            .overlay(
                RoundedRectangle(cornerRadius: BeagleRadius.md, style: .continuous)
                    .strokeBorder(BeagleTheme.hairline.opacity(0.85), lineWidth: 0.7)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Open continuity explanation")
    }

    private func continuityChip(_ signal: HomeContinuitySignal) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(signal.title)
                .font(BeagleFont.caption.font)
                .fontWeight(.semibold)
                .foregroundStyle(signalColor(signal))
                .lineLimit(1)
                .minimumScaleFactor(0.78)
            Text(signal.detail)
                .font(BeagleFont.caption2.font)
                .foregroundStyle(BeagleTheme.textSecondary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(width: 148, alignment: .leading)
        .padding(.horizontal, BeagleSpacing.xs)
        .padding(.vertical, 7)
        .background(
            RoundedRectangle(cornerRadius: BeagleRadius.sm, style: .continuous)
                .fill(BeagleTheme.surface0.opacity(0.66))
        )
    }
}

struct NextMoveDock: View {
    let context: HomeContinuityContext
    let onSelect: (HomeNextMove) -> Void
    let onExplain: () -> Void

    var body: some View {
        let move = context.primaryNextAction
        HStack(alignment: .center, spacing: BeagleSpacing.sm) {
            Button {
                onSelect(move)
            } label: {
                HStack(spacing: BeagleSpacing.sm) {
                    ZStack {
                        Circle()
                            .fill(BeagleTheme.truthObserved.opacity(0.16))
                            .frame(width: 32, height: 32)
                        Image(systemName: move.systemImage)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(BeagleTheme.truthObserved)
                    }

                    VStack(alignment: .leading, spacing: 2) {
                        Text("NEXT MOVE")
                            .font(BeagleFont.caption2.font)
                            .fontWeight(.semibold)
                            .foregroundStyle(BeagleTheme.textTertiary)
                        Text(move.title)
                            .font(BeagleFont.footnote.font)
                            .fontWeight(.semibold)
                            .foregroundStyle(BeagleTheme.textPrimary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.82)
                        Text(move.detail)
                            .font(BeagleFont.caption2.font)
                            .foregroundStyle(BeagleTheme.textSecondary)
                            .lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Spacer(minLength: BeagleSpacing.xs)

                    Image(systemName: "arrow.up.right.circle.fill")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(BeagleTheme.truthObserved)
                }
                .padding(BeagleSpacing.sm)
                .background(
                    RoundedRectangle(cornerRadius: BeagleRadius.md, style: .continuous)
                        .fill(BeagleTheme.truthObserved.opacity(0.10))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: BeagleRadius.md, style: .continuous)
                        .strokeBorder(BeagleTheme.truthObserved.opacity(0.28), lineWidth: 0.8)
                )
            }
            .buttonStyle(.plain)
            .contextMenu {
                ForEach(context.alternativeNextActions) { alternative in
                    Button {
                        onSelect(alternative)
                    } label: {
                        Label(alternative.title, systemImage: alternative.systemImage)
                    }
                }
            }

            Button(action: onExplain) {
                Image(systemName: "info.circle")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(BeagleTheme.textTertiary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Explain next move")
        }
    }
}

struct ContinuityExplanationSheet: View {
    let context: HomeContinuityContext
    let home: ExocortexHomeSnapshot
    let truthMode: TruthMode

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: BeagleSpacing.md) {
                GlassPanel(elevation: .floating, truth: truthMode) {
                    VStack(alignment: .leading, spacing: BeagleSpacing.xs) {
                        Text("WHY THIS NOW")
                            .font(BeagleFont.caption2.font)
                            .fontWeight(.semibold)
                            .foregroundStyle(BeagleTheme.textTertiary)
                        Text(context.primaryNextAction.title)
                            .font(BeagleFont.title3.font)
                            .fontWeight(.semibold)
                            .foregroundStyle(BeagleTheme.textPrimary)
                        Text(context.whyThisNow)
                            .font(BeagleFont.footnote.font)
                            .foregroundStyle(BeagleTheme.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                        Text("\(context.sourceMode) · \(context.mode.rawValue) · \(Int(context.confidence * 100))% confidence")
                            .font(BeagleFont.caption2.font.monospaced())
                            .foregroundStyle(BeagleTheme.textTertiary)
                    }
                }

                explanationSection("CONTINUITY SIGNALS")
                if context.changedSinceLastOpen.isEmpty {
                    emptyExplanation("No fresh continuity signal is visible yet.")
                } else {
                    ForEach(context.changedSinceLastOpen) { signal in
                        signalRow(signal)
                    }
                }

                explanationSection("NEXT MOVE RATIONALE")
                GlassPanel(truth: .declared) {
                    VStack(alignment: .leading, spacing: BeagleSpacing.xs) {
                        Text(context.primaryNextAction.reason)
                            .font(BeagleFont.caption.font)
                            .foregroundStyle(BeagleTheme.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                        if !context.alternativeNextActions.isEmpty {
                            Text("Alternatives: \(context.alternativeNextActions.prefix(3).map(\.title).joined(separator: " · "))")
                                .font(BeagleFont.caption2.font)
                                .foregroundStyle(BeagleTheme.textTertiary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }

                explanationSection("PROVENANCE")
                GlassPanel(truth: .remembered) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Home \(home.generatedAt.isEmpty ? "bootstrap" : home.generatedAt)")
                            .font(BeagleFont.caption.font)
                            .foregroundStyle(BeagleTheme.textSecondary)
                        Text("Cluster truth \(home.clusterTruth) · OmniMemory \(home.omnimemoryStatus)")
                            .font(BeagleFont.caption.font)
                            .foregroundStyle(BeagleTheme.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                        Text("No raw private chat text is stored in this local explanation.")
                            .font(BeagleFont.caption2.font)
                            .foregroundStyle(BeagleTheme.textTertiary)
                    }
                }
            }
            .padding(BeagleSpacing.lg)
        }
        .navigationTitle("Living Home")
        .background(BeagleTheme.surface0.ignoresSafeArea())
    }

    private func signalRow(_ signal: HomeContinuitySignal) -> some View {
        GlassPanel(truth: truth(for: signal)) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: BeagleSpacing.xs) {
                    Text(signal.title)
                        .font(BeagleFont.caption.font)
                        .fontWeight(.semibold)
                        .foregroundStyle(BeagleTheme.textPrimary)
                    Spacer(minLength: BeagleSpacing.sm)
                    Text(signal.kind)
                        .font(BeagleFont.caption2.font.monospaced())
                        .foregroundStyle(BeagleTheme.textTertiary)
                        .lineLimit(1)
                }
                Text(signal.detail)
                    .font(BeagleFont.caption.font)
                    .foregroundStyle(BeagleTheme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                if !signal.provenanceRefs.isEmpty {
                    Text(signal.provenanceRefs.prefix(3).joined(separator: " · "))
                        .font(BeagleFont.caption2.font.monospaced())
                        .foregroundStyle(BeagleTheme.textTertiary)
                        .lineLimit(2)
                }
            }
        }
    }

    private func emptyExplanation(_ text: String) -> some View {
        Text(text)
            .font(BeagleFont.caption.font)
            .foregroundStyle(BeagleTheme.textSecondary)
            .padding(.vertical, BeagleSpacing.sm)
    }

    private func explanationSection(_ title: String) -> some View {
        Text(title)
            .font(BeagleFont.caption2.font)
            .fontWeight(.semibold)
            .foregroundStyle(BeagleTheme.textTertiary)
    }

    private func truth(for signal: HomeContinuitySignal) -> TruthMode {
        TruthMode(rawValue: signal.truthMode) ?? .declared
    }
}

private func signalColor(_ signal: HomeContinuitySignal) -> Color {
    switch signal.kind {
    case "agent_write", "work_memory", "apple_capture":
        return BeagleTheme.truthObserved
    case "grok_import", "origin_lineage":
        return BeagleTheme.truthRemembered
    case "cache":
        return BeagleTheme.truthStale
    default:
        return BeagleTheme.textPrimary
    }
}

// MARK: - Origin Observatory

struct OriginObservatorySheet: View {
    let lineage: OriginLineageSnapshot
    @State private var selectedTab: OriginTab = .timeline

    init(lineage: OriginLineageSnapshot) {
        self.lineage = lineage
    }

    private enum OriginTab: String, CaseIterable, Identifiable {
        case timeline = "Timeline"
        case evidence = "Evidence"
        case tensions = "Tensions"
        case claims = "Claims"

        var id: String { rawValue }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: BeagleSpacing.md) {
                header
                tabPicker

                switch selectedTab {
                case .timeline:
                    timelineTab
                case .evidence:
                    evidenceTab
                case .tensions:
                    tensionsTab
                case .claims:
                    claimsTab
                }
            }
            .padding(BeagleSpacing.lg)
        }
        .navigationTitle("Origin Observatory")
        .background(BeagleTheme.surface0.ignoresSafeArea())
    }

    private var lineageTruth: TruthMode {
        lineage.sourcePolicy.lowercased().contains("cluster") ? .observed : .remembered
    }

    private var header: some View {
        GlassPanel(elevation: .floating, truth: lineageTruth) {
            VStack(alignment: .leading, spacing: BeagleSpacing.xs) {
                HStack(spacing: BeagleSpacing.xs) {
                    Image(systemName: "point.topleft.down.curvedto.point.bottomright.up")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(BeagleTheme.truthRemembered)
                    Text("RAG++ -> Darwin -> Beagle -> Sounio")
                        .font(BeagleFont.callout.font)
                        .fontWeight(.semibold)
                        .foregroundStyle(BeagleTheme.textPrimary)
                    Spacer(minLength: BeagleSpacing.xs)
                    TruthBadge(lineageTruth, compact: true)
                }

                Text("A sanitized origin map. The local seed is display-only; cluster lineage overrides it when provenance is available.")
                    .font(BeagleFont.caption.font)
                    .foregroundStyle(BeagleTheme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)

                ViewThatFits(in: .horizontal) {
                    HStack(spacing: BeagleSpacing.sm) {
                        metricPill("\(lineage.nodes.count)", "nodes")
                        metricPill("\(lineage.evidenceRefs.count)", "evidence families")
                        metricPill("\(lineage.tensions.count)", "tensions")
                        metricPill("\(lineage.claimSeeds.count)", "claim seeds")
                    }

                    VStack(alignment: .leading, spacing: BeagleSpacing.xs) {
                        HStack(spacing: BeagleSpacing.sm) {
                            metricPill("\(lineage.nodes.count)", "nodes")
                            metricPill("\(lineage.evidenceRefs.count)", "evidence families")
                        }
                        HStack(spacing: BeagleSpacing.sm) {
                            metricPill("\(lineage.tensions.count)", "tensions")
                            metricPill("\(lineage.claimSeeds.count)", "claim seeds")
                        }
                    }
                }

                Text("\(lineage.sourcePolicy) · generated \(lineage.generatedAt)")
                    .font(BeagleFont.caption2.font.monospaced())
                    .foregroundStyle(BeagleTheme.textTertiary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var tabPicker: some View {
        Picker("Origin view", selection: $selectedTab) {
            ForEach(OriginTab.allCases) { tab in
                Text(tab.rawValue).tag(tab)
            }
        }
        .pickerStyle(.segmented)
    }

    private var timelineTab: some View {
        VStack(alignment: .leading, spacing: BeagleSpacing.sm) {
            sectionTitle("CONCEPTUAL EVOLUTION")
            ForEach(lineage.nodes) { node in
                originNodeCard(node)
                if let edge = lineage.edges.first(where: { $0.from == node.id }) {
                    HStack(spacing: BeagleSpacing.xs) {
                        Image(systemName: "arrow.down")
                            .font(.system(size: 10, weight: .semibold))
                        Text(edge.label)
                            .font(BeagleFont.caption2.font)
                            .fontWeight(.semibold)
                    }
                    .foregroundStyle(BeagleTheme.textTertiary)
                    .padding(.leading, BeagleSpacing.md)
                }
            }
        }
    }

    private var evidenceTab: some View {
        VStack(alignment: .leading, spacing: BeagleSpacing.sm) {
            sectionTitle("SOURCE FAMILIES")
            Text("The first build shows families and cluster refs only. Raw ChatGPT, Claude or Grok conversation text stays out of GitHub and out of local canonical memory.")
                .font(BeagleFont.caption.font)
                .foregroundStyle(BeagleTheme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            ForEach(lineage.evidenceRefs) { evidence in
                GlassPanel(truth: evidence.visibility == "sanitized_digest_ok" ? .observed : .remembered) {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(alignment: .top) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(evidence.label)
                                    .font(BeagleFont.caption.font)
                                    .fontWeight(.semibold)
                                    .foregroundStyle(BeagleTheme.textPrimary)
                                    .fixedSize(horizontal: false, vertical: true)
                                Text(evidence.sourceFamily)
                                    .font(BeagleFont.caption2.font)
                                    .foregroundStyle(BeagleTheme.textSecondary)
                            }
                            Spacer(minLength: BeagleSpacing.sm)
                            visibilityBadge(evidence.visibility)
                        }

                        if let firstObserved = evidence.firstObservedAt {
                            Text("first observed \(firstObserved)")
                                .font(BeagleFont.caption2.font.monospaced())
                                .foregroundStyle(BeagleTheme.textTertiary)
                        }
                        Text(evidence.id)
                            .font(BeagleFont.caption2.font.monospaced())
                            .foregroundStyle(BeagleTheme.textTertiary)
                            .lineLimit(1)
                    }
                }
            }
        }
    }

    private var tensionsTab: some View {
        VStack(alignment: .leading, spacing: BeagleSpacing.sm) {
            sectionTitle("DESIGN TENSIONS")
            ForEach(lineage.tensions) { tension in
                GlassPanel(truth: tension.status == "active" ? .observed : .declared) {
                    VStack(alignment: .leading, spacing: 5) {
                        HStack(spacing: BeagleSpacing.xs) {
                            Text(tension.title)
                                .font(BeagleFont.caption.font)
                                .fontWeight(.semibold)
                                .foregroundStyle(BeagleTheme.textPrimary)
                            Spacer(minLength: BeagleSpacing.sm)
                            Text(tension.status)
                                .font(BeagleFont.caption2.font.monospaced())
                                .foregroundStyle(BeagleTheme.textTertiary)
                        }
                        Text(tension.detail)
                            .font(BeagleFont.caption.font)
                            .foregroundStyle(BeagleTheme.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
    }

    private var claimsTab: some View {
        VStack(alignment: .leading, spacing: BeagleSpacing.sm) {
            sectionTitle("SOUNIO CLAIM SEEDS")
            Text("These are Claim<T> candidates, not promoted knowledge. A claim becomes stronger only after cluster evidence, private trace review and human approval.")
                .font(BeagleFont.caption.font)
                .foregroundStyle(BeagleTheme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            ForEach(Array(lineage.claimSeeds.enumerated()), id: \.offset) { _, claim in
                claimCard(claim)
            }
        }
    }

    private func originNodeCard(_ node: OriginLineageNode) -> some View {
        GlassPanel(truth: node.state.lowercased().contains("origin") ? .remembered : .observed) {
            VStack(alignment: .leading, spacing: BeagleSpacing.xs) {
                HStack(alignment: .top, spacing: BeagleSpacing.xs) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(node.title)
                            .font(BeagleFont.callout.font)
                            .fontWeight(.semibold)
                            .foregroundStyle(BeagleTheme.textPrimary)
                        Text(node.subtitle)
                            .font(BeagleFont.caption.font)
                            .foregroundStyle(BeagleTheme.textSecondary)
                    }
                    Spacer(minLength: BeagleSpacing.sm)
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(node.state)
                            .font(BeagleFont.caption2.font.monospaced())
                            .foregroundStyle(nodeStateColor(node.state))
                        Text(node.firstKnownAt)
                            .font(BeagleFont.caption2.font.monospaced())
                            .foregroundStyle(BeagleTheme.textTertiary)
                    }
                }

                originDetail("Source", node.sourceFamily)
                originDetail("Tension", node.tension)
                originDetail("Next", node.nextAction)

                if !node.evidenceRefs.isEmpty {
                    Text(node.evidenceRefs.joined(separator: " · "))
                        .font(BeagleFont.caption2.font.monospaced())
                        .foregroundStyle(BeagleTheme.textTertiary)
                        .lineLimit(2)
                }
            }
        }
    }

    private func claimCard(_ claim: SounioClaimInput) -> some View {
        GlassPanel(truth: claim.epistemicStatus == "knowledge" || claim.epistemicStatus == "robust" ? .observed : .declared) {
            VStack(alignment: .leading, spacing: BeagleSpacing.xs) {
                HStack(spacing: BeagleSpacing.xs) {
                    Text((claim.epistemicStatus ?? "belief").uppercased())
                        .font(BeagleFont.caption2.font.monospaced())
                        .fontWeight(.semibold)
                        .foregroundStyle(claimStatusColor(claim.epistemicStatus))
                    Spacer(minLength: BeagleSpacing.sm)
                    Text(claim.publicationReadiness ?? "not_ready")
                        .font(BeagleFont.caption2.font.monospaced())
                        .foregroundStyle(BeagleTheme.textTertiary)
                }

                Text(claim.claimText)
                    .font(BeagleFont.caption.font)
                    .foregroundStyle(BeagleTheme.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)

                if let rationale = claim.rationale {
                    Text(rationale)
                        .font(BeagleFont.caption2.font)
                        .foregroundStyle(BeagleTheme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if !claim.evidenceRefs.isEmpty {
                    Text("evidence: \(claim.evidenceRefs.joined(separator: " · "))")
                        .font(BeagleFont.caption2.font.monospaced())
                        .foregroundStyle(BeagleTheme.textTertiary)
                        .lineLimit(2)
                }

                Text("review \(claim.reviewState ?? "unreviewed") · \(claim.promotionRule ?? "no promotion rule")")
                    .font(BeagleFont.caption2.font)
                    .foregroundStyle(BeagleTheme.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func metricPill(_ value: String, _ label: String) -> some View {
        HStack(spacing: BeagleSpacing.xxs) {
            Text(value)
                .font(BeagleFont.caption.font.monospaced())
                .fontWeight(.semibold)
                .foregroundStyle(BeagleTheme.textPrimary)
            Text(label)
                .font(BeagleFont.caption2.font)
                .foregroundStyle(BeagleTheme.textTertiary)
        }
        .padding(.horizontal, BeagleSpacing.xs)
        .padding(.vertical, 5)
        .background(
            Capsule(style: .continuous)
                .fill(BeagleTheme.surface1.opacity(0.5))
        )
    }

    private func visibilityBadge(_ visibility: String) -> some View {
        Text(visibility)
            .font(BeagleFont.caption2.font.monospaced())
            .foregroundStyle(visibility == "sanitized_digest_ok" ? BeagleTheme.truthObserved : BeagleTheme.truthRemembered)
            .lineLimit(1)
            .minimumScaleFactor(0.75)
    }

    private func originDetail(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(title.uppercased())
                .font(BeagleFont.caption2.font)
                .fontWeight(.semibold)
                .foregroundStyle(BeagleTheme.textTertiary)
            Text(value)
                .font(BeagleFont.caption.font)
                .foregroundStyle(BeagleTheme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func sectionTitle(_ text: String) -> some View {
        Text(text)
            .font(BeagleFont.caption2.font)
            .fontWeight(.semibold)
            .foregroundStyle(BeagleTheme.textTertiary)
    }

    private func nodeStateColor(_ state: String) -> Color {
        let lower = state.lowercased()
        if lower.contains("origin") { return BeagleTheme.truthRemembered }
        if lower.contains("platform") { return BeagleTheme.truthObserved }
        if lower.contains("memory") { return BeagleTheme.postureWarm }
        if lower.contains("epistemic") { return BeagleTheme.truthDeclared }
        return BeagleTheme.textTertiary
    }

    private func claimStatusColor(_ status: String?) -> Color {
        switch status {
        case "robust", "knowledge":
            return BeagleTheme.truthObserved
        case "contest":
            return BeagleTheme.postureWarm
        case "belief":
            return BeagleTheme.truthDeclared
        default:
            return BeagleTheme.textTertiary
        }
    }
}
