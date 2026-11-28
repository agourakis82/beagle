//
//  BeagleSurface+ExocortexHome.swift
//  BeagleCockpit
//
//  Exocortex Home card, Sounio Now strip, haptics, surface bootstrap, and home metrics.
//

import SwiftUI
import SwiftData
import BeagleCore
import BeagleWorkbenchKit
#if canImport(UIKit)
import UIKit
#endif

extension BeagleSurface {
    // MARK: - Exocortex Home

    private var exocortexHomeCard: some View {
        GlassPanel(elevation: .floating, truth: exocortex.home.mode) {
            VStack(alignment: .leading, spacing: BeagleSpacing.sm) {
                LivingHomeHeader(
                    context: continuityContext,
                    home: home,
                    presence: shellPresence,
                    truthMode: exocortex.home.mode,
                    isLoading: exocortex.isLoading,
                    onRefresh: {
                        Task { await refreshLivingHome() }
                    },
                    onExplain: {
                        activeSheet = .continuityExplanation
                    }
                )

                ContinuityDeltaBand(
                    context: continuityContext,
                    onExplain: {
                        activeSheet = .continuityExplanation
                    }
                )

                originRibbon

                SounioNowStrip(context: sounioNowContext) {
                    activeSheet = .memoryLens
                }

                HStack(alignment: .top, spacing: BeagleSpacing.sm) {
                    hardwareStrip
                    Spacer(minLength: 0)
                }

                if let bodyLine = bodyContextLine {
                    bodyContextRow(bodyLine)
                }

                if let trustLine = trustContextLine {
                    trustContextRow(trustLine)
                }

                memoryProjectionStrip

                if let agentLine = latestAgentWriteLine {
                    memoryContextRow(
                        icon: "hammer",
                        title: "Latest work memory",
                        line: agentLine,
                        tint: BeagleTheme.truthObserved
                    )
                }

                if let grokLine = latestGrokImportLine {
                    memoryContextRow(
                        icon: "tray.and.arrow.down",
                        title: "Latest Grok signal",
                        line: grokLine,
                        tint: BeagleTheme.truthRemembered
                    )
                }

                NextMoveDock(
                    context: continuityContext,
                    onSelect: performNextMove,
                    onExplain: {
                        activeSheet = .continuityExplanation
                    }
                )

                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .top, spacing: BeagleSpacing.md) {
                        homeSignal(
                            icon: "scope",
                            title: home.activeProjectRef ?? activeSlug,
                            detail: home.temporalPhase ?? home.omnimemoryStatus
                        )
                        homeSignal(
                            icon: "point.3.connected.trianglepath.dotted",
                            title: "\(home.memorySignals.count) memory signals",
                            detail: agentContextDetail
                        )
                        homeSignal(
                            icon: "sparkles",
                            title: "Semantic Backbone",
                            detail: semanticBackboneDetail
                        )
                        homeSignal(
                            icon: "externaldrive.connected.to.line.below",
                            title: autoImportTitle,
                            detail: autoImportDetail
                        )
                        homeSignal(
                            icon: "applewatch",
                            title: bodyLoopTitle,
                            detail: bodyLoopDetail
                        )
                        homeSignal(
                            icon: "arrow.forward.circle.fill",
                            title: "Next",
                            detail: home.recommendedNextAction
                        )
                    }

                    VStack(alignment: .leading, spacing: BeagleSpacing.sm) {
                        homeSignal(
                            icon: "scope",
                            title: home.activeProjectRef ?? activeSlug,
                            detail: home.temporalPhase ?? home.omnimemoryStatus
                        )
                        homeSignal(
                            icon: "point.3.connected.trianglepath.dotted",
                            title: "\(home.memorySignals.count) memory signals",
                            detail: agentContextDetail
                        )
                        homeSignal(
                            icon: "externaldrive.connected.to.line.below",
                            title: autoImportTitle,
                            detail: autoImportDetail
                        )
                        homeSignal(
                            icon: "applewatch",
                            title: bodyLoopTitle,
                            detail: bodyLoopDetail
                        )
                        homeSignal(
                            icon: "arrow.forward.circle.fill",
                            title: "Next",
                            detail: home.recommendedNextAction
                        )
                    }
                }
            }
        }
    }

    private var memoryProjectionStrip: some View {
        Button {
            activeSheet = .memoryLens
        } label: {
            HStack(spacing: BeagleSpacing.xs) {
                Image(systemName: "point.3.connected.trianglepath.dotted")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(BeagleTheme.truthObserved)
                    .frame(width: 16)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Semantic GraphRAG++ memory")
                        .font(BeagleFont.caption2.font)
                        .fontWeight(.semibold)
                        .foregroundStyle(BeagleTheme.textTertiary)
                    Text(memoryProjectionLine)
                        .font(BeagleFont.caption.font)
                        .foregroundStyle(BeagleTheme.textSecondary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: BeagleSpacing.sm)

                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(BeagleTheme.textTertiary)
            }
            .padding(.vertical, 2)
        }
        .buttonStyle(.plain)
    }

    private var originRibbon: some View {
        Button {
            activeSheet = .originObservatory
        } label: {
            VStack(alignment: .leading, spacing: BeagleSpacing.xs) {
                HStack(spacing: BeagleSpacing.xs) {
                    Image(systemName: "point.topleft.down.curvedto.point.bottomright.up")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(BeagleTheme.truthRemembered)
                    Text("ORIGIN RIBBON")
                        .font(BeagleFont.caption2.font)
                        .fontWeight(.semibold)
                        .foregroundStyle(BeagleTheme.textTertiary)
                    Spacer(minLength: BeagleSpacing.xs)
                    Text(originLineage.sourcePolicy.contains("cluster") ? "cluster" : "seed")
                        .font(BeagleFont.caption2.font.monospaced())
                        .foregroundStyle(BeagleTheme.textTertiary)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(BeagleTheme.textTertiary)
                }

                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .top, spacing: BeagleSpacing.xs) {
                        originRibbonNodes
                    }

                    VStack(alignment: .leading, spacing: BeagleSpacing.xs) {
                        originRibbonNodes
                    }
                }

                if let centralTension = originLineage.tensions.first {
                    Text(centralTension.detail)
                        .font(BeagleFont.caption2.font)
                        .foregroundStyle(BeagleTheme.textTertiary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(BeagleSpacing.sm)
            .background(
                RoundedRectangle(cornerRadius: BeagleRadius.md, style: .continuous)
                    .fill(BeagleTheme.surface1.opacity(0.48))
            )
            .overlay(
                RoundedRectangle(cornerRadius: BeagleRadius.md, style: .continuous)
                    .strokeBorder(BeagleTheme.truthRemembered.opacity(0.35), lineWidth: 0.8)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Open Origin Observatory")
    }

    @ViewBuilder
    private var originRibbonNodes: some View {
        ForEach(Array(originLineage.nodes.enumerated()), id: \.element.id) { index, node in
            if index > 0 {
                Image(systemName: "chevron.right")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(BeagleTheme.textTertiary)
                    .padding(.top, 11)
            }
            originRibbonNode(node)
        }
    }

    private func originRibbonNode(_ node: OriginLineageNode) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(node.title)
                .font(BeagleFont.caption.font)
                .fontWeight(.semibold)
                .foregroundStyle(BeagleTheme.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.78)
            Text(node.subtitle)
                .font(BeagleFont.caption2.font)
                .foregroundStyle(BeagleTheme.textSecondary)
                .lineLimit(1)
                .minimumScaleFactor(0.78)
            Text(node.state)
                .font(BeagleFont.caption2.font)
                .foregroundStyle(originStateColor(node.state))
                .lineLimit(1)
                .minimumScaleFactor(0.78)
        }
        .padding(.horizontal, BeagleSpacing.xs)
        .padding(.vertical, 6)
        .frame(minWidth: 72, maxWidth: 116, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: BeagleRadius.sm, style: .continuous)
                .fill(BeagleTheme.surface0.opacity(0.72))
        )
    }

    private var hardwareStrip: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: BeagleSpacing.xs) {
                hardwarePill(
                    icon: "iphone.gen3",
                    title: phoneSurfaceLabel,
                    detail: "capture"
                )
                hardwarePill(
                    icon: "applewatch",
                    title: watchSurfaceLabel,
                    detail: readinessStatusLabel
                )
                hardwarePill(
                    icon: "server.rack",
                    title: "cluster truth",
                    detail: home.clusterTruth
                )
            }

            VStack(alignment: .leading, spacing: BeagleSpacing.xs) {
                HStack(spacing: BeagleSpacing.xs) {
                    hardwarePill(
                        icon: "iphone.gen3",
                        title: phoneSurfaceLabel,
                        detail: "capture"
                    )
                    hardwarePill(
                        icon: "applewatch",
                        title: watchSurfaceLabel,
                        detail: readinessStatusLabel
                    )
                }
                hardwarePill(
                    icon: "server.rack",
                    title: "cluster truth",
                    detail: home.clusterTruth
                )
            }
        }
    }

    private func hardwarePill(icon: String, title: String, detail: String) -> some View {
        HStack(spacing: BeagleSpacing.xxs) {
            Image(systemName: icon)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(BeagleTheme.truthObserved)
            Text(title)
                .font(BeagleFont.caption2.font)
                .fontWeight(.semibold)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Text(detail)
                .font(BeagleFont.caption2.font)
                .foregroundStyle(BeagleTheme.textTertiary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .foregroundStyle(BeagleTheme.textSecondary)
        .padding(.horizontal, BeagleSpacing.xs)
        .padding(.vertical, 5)
        .background(
            Capsule(style: .continuous)
                .fill(BeagleTheme.surface1.opacity(0.48))
        )
        .overlay(
            Capsule(style: .continuous)
                .strokeBorder(BeagleTheme.hairline.opacity(0.65), lineWidth: 0.6)
        )
    }

    private func bodyContextRow(_ line: String) -> some View {
        HStack(alignment: .top, spacing: BeagleSpacing.xs) {
            Image(systemName: "waveform.path.ecg")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(readinessColor)
                .frame(width: 16)

            VStack(alignment: .leading, spacing: 2) {
                Text("Body context")
                    .font(BeagleFont.caption2.font)
                    .fontWeight(.semibold)
                    .foregroundStyle(BeagleTheme.textTertiary)
                Text(line)
                    .font(BeagleFont.caption.font)
                    .foregroundStyle(BeagleTheme.textSecondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.vertical, 2)
    }

    private func trustContextRow(_ line: String) -> some View {
        HStack(alignment: .top, spacing: BeagleSpacing.xs) {
            Image(systemName: "checkmark.shield")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(BeagleTheme.truthObserved)
                .frame(width: 16)

            VStack(alignment: .leading, spacing: 2) {
                Text("MCP trust")
                    .font(BeagleFont.caption2.font)
                    .fontWeight(.semibold)
                    .foregroundStyle(BeagleTheme.textTertiary)
                Text(line)
                    .font(BeagleFont.caption.font)
                    .foregroundStyle(BeagleTheme.textSecondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.vertical, 2)
    }

    private func memoryContextRow(icon: String, title: String, line: String, tint: Color) -> some View {
        HStack(alignment: .top, spacing: BeagleSpacing.xs) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 16)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(BeagleFont.caption2.font)
                    .fontWeight(.semibold)
                    .foregroundStyle(BeagleTheme.textTertiary)
                Text(line)
                    .font(BeagleFont.caption.font)
                    .foregroundStyle(BeagleTheme.textSecondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.vertical, 2)
    }

    private struct SounioNowStrip: View {
        let context: SounioNowContext
        let onOpen: () -> Void

        var body: some View {
            Button(action: onOpen) {
                VStack(alignment: .leading, spacing: BeagleSpacing.xs) {
                    HStack(spacing: BeagleSpacing.xs) {
                        Image(systemName: "text.badge.checkmark")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(BeagleTheme.truthDeclared)
                            .frame(width: 16)
                        Text("SOUNIO NOW")
                            .font(BeagleFont.caption2.font)
                            .fontWeight(.semibold)
                            .foregroundStyle(BeagleTheme.textTertiary)
                        Spacer(minLength: BeagleSpacing.xs)
                        if context.reviewQueueCount > 0 {
                            Text("\(context.reviewQueueCount) review")
                                .font(BeagleFont.caption2.font.monospaced())
                                .foregroundStyle(BeagleTheme.postureWarm)
                        } else {
                            Text(context.status)
                                .font(BeagleFont.caption2.font.monospaced())
                                .foregroundStyle(BeagleTheme.textTertiary)
                                .lineLimit(1)
                        }
                        Image(systemName: "chevron.right")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(BeagleTheme.textTertiary)
                    }

                    Text(context.momentLine)
                        .font(BeagleFont.caption.font)
                        .foregroundStyle(BeagleTheme.textPrimary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)

                    ViewThatFits(in: .horizontal) {
                        HStack(spacing: BeagleSpacing.sm) {
                            if let decision = context.decisionLine {
                                chip("decision", decision, tint: BeagleTheme.truthObserved)
                            }
                            if let claim = context.claimLine {
                                chip("claim", claim, tint: BeagleTheme.truthDeclared)
                            }
                            if let agent = context.agentLine {
                                chip("agent", agent, tint: BeagleTheme.truthRemembered)
                            }
                        }
                        VStack(alignment: .leading, spacing: BeagleSpacing.xs) {
                            if let decision = context.decisionLine {
                                chip("decision", decision, tint: BeagleTheme.truthObserved)
                            }
                            if let claim = context.claimLine {
                                chip("claim", claim, tint: BeagleTheme.truthDeclared)
                            }
                            if let agent = context.agentLine {
                                chip("agent", agent, tint: BeagleTheme.truthRemembered)
                            }
                        }
                    }

                    Text(context.nextGesture)
                        .font(BeagleFont.caption2.font)
                        .foregroundStyle(BeagleTheme.textTertiary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(BeagleSpacing.sm)
                .background(
                    RoundedRectangle(cornerRadius: BeagleRadius.md, style: .continuous)
                        .fill(BeagleTheme.surface1.opacity(0.54))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: BeagleRadius.md, style: .continuous)
                        .strokeBorder(BeagleTheme.truthDeclared.opacity(0.34), lineWidth: 0.8)
                )
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Open Sounio Workday")
        }

        private func chip(_ title: String, _ value: String, tint: Color) -> some View {
            HStack(spacing: 4) {
                Text(title.uppercased())
                    .font(BeagleFont.caption2.font)
                    .fontWeight(.semibold)
                    .foregroundStyle(tint)
                Text(value)
                    .font(BeagleFont.caption2.font)
                    .foregroundStyle(BeagleTheme.textSecondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.76)
            }
            .padding(.horizontal, BeagleSpacing.xs)
            .padding(.vertical, 4)
            .background(
                Capsule(style: .continuous)
                    .fill(BeagleTheme.surface0.opacity(0.68))
            )
        }
    }

    var home: ExocortexHomeSnapshot {
        exocortex.home.value ?? .bootstrap
    }

    var continuityContext: HomeContinuityContext {
        if let clusterContext = home.continuityContext {
            return clusterContext
        }
        return HomeContinuityContext.synthesized(
            home: home,
            truthMode: exocortex.home.mode,
            previousHome: exocortex.cachedHomeSnapshot,
            recentGraph: exocortex.recentGraph?.value,
            projectionStatus: exocortex.graphStatus?.value?.projectionStatus
                ?? exocortex.projectionStatus?.value
                ?? home.trustContext?.memoryProjectionStatus,
            originLineage: originLineage
        )
    }

    var latestSurfaceWriteHapticKey: String {
        continuityContext.latestSurfaceWrite?.id ?? ""
    }

    func markHomeTruthTransition(from oldValue: TruthMode, to newValue: TruthMode) {
        guard oldValue == .stale, newValue == .observed else { return }
        #if canImport(UIKit)
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        #endif
    }

    func markSurfaceWriteTransition(from oldValue: String, to newValue: String) {
        guard !oldValue.isEmpty, oldValue != newValue, !newValue.isEmpty else { return }
        #if canImport(UIKit)
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        #endif
    }

    var originLineage: OriginLineageSnapshot {
        home.originLineage ?? .localSeed
    }

    private var sounioNowContext: SounioNowContext {
        SounioNowContext.synthesized(
            home: home,
            workday: exocortex.sounioWorkday?.value ?? home.sounioWorkdayContext
        )
    }

    private func originStateColor(_ state: String) -> Color {
        let lower = state.lowercased()
        if lower.contains("origin") { return BeagleTheme.truthRemembered }
        if lower.contains("platform") { return BeagleTheme.truthObserved }
        if lower.contains("memory") { return BeagleTheme.postureWarm }
        if lower.contains("epistemic") { return BeagleTheme.truthDeclared }
        return BeagleTheme.textTertiary
    }

    private func homeSignal(icon: String, title: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: BeagleSpacing.xxs) {
                Image(systemName: icon)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(BeagleTheme.truthObserved)
                Text(title)
                    .font(BeagleFont.caption.font)
                    .fontWeight(.semibold)
                    .foregroundStyle(BeagleTheme.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            Text(detail)
                .font(BeagleFont.caption2.font)
                .foregroundStyle(BeagleTheme.textTertiary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func refreshLivingHome() async {
        async let homeRefresh: Void = exocortex.refresh(activeProjectSlug: activeSlug, platform: platformName)
        async let projectionRefresh: Void = exocortex.refreshProjectionStatus()
        async let graphStatusRefresh: Void = exocortex.refreshGraphStatus()
        async let benchmarkRefresh: Void = exocortex.refreshBenchmarkStatus()
        async let graphRefresh: Void = exocortex.refreshRecentGraph(limit: 12)
        async let worldsRefresh: Void = exocortex.refreshRecentWorlds(limit: 12)
        async let sounioWorkdayRefresh: Void = exocortex.refreshSounioWorkday(projectSlug: activeSlug, limit: 20)
        async let sounioMomentsRefresh: Void = exocortex.refreshRecentSounioMoments(projectSlug: activeSlug, limit: 20)
        async let bodyRefresh: Void = physio.refresh()
        // Boot the geomagnetic poller once; idempotent.
        spaceWeather.start()
        _ = await (
            homeRefresh,
            projectionRefresh,
            graphStatusRefresh,
            benchmarkRefresh,
            graphRefresh,
            worldsRefresh,
            sounioWorkdayRefresh,
            sounioMomentsRefresh,
            bodyRefresh
        )
        syncConversationLiveContext()
    }

    func bootstrapSurface() async {
        wireConversation()
        exocortex.modelContext = modelContext
        exocortex.loadCachedHome()
        if ProcessInfo.processInfo.arguments.contains("--ui-testing") {
            syncConversationLiveContext()
            return
        }
        // Cold-start: refresh the project catalog + companion grounding + Beagle MCP tools + flush any offline outbox
        async let catalogTask: () = catalog.refresh()
        async let groundingTask: () = conversation.refreshGroundingIfStale()
        async let outboxTask: () = conversation.flushOutbox()
        Task {
            _ = await BeagleMCPClient.shared.availableTools()
        }
        await refreshLivingHome()
        _ = await (catalogTask, groundingTask, outboxTask)
        syncConversationLiveContext()
    }

    private func performNextMove(_ move: HomeNextMove) {
        switch move.action {
        case "open_memory_lens", "review_claim":
            activeSheet = .memoryLens
        case "capture_thought":
            activeSheet = .capture
        case "inspect_trust":
            activeSheet = .continuityExplanation
        case "resume_project":
            activeSheet = .projectPicker
        default:
            activeSheet = .continuityExplanation
        }
    }

}
