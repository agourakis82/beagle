//
//  BeagleSurface.swift
//  BeagleCockpit
//
//  The Mind tab. A real conversation with memory.
//
//  Foundation Models (on-device) is the primary responder.
//  When unavailable, falls back to cloud HERMES.
//  All responses go through ConversationStore — persistent, searchable, real.
//

import SwiftUI
import SwiftData
import BeagleCore
#if canImport(UIKit)
import UIKit
#endif

struct BeagleSurface: View {
    @Environment(CatalogStore.self) private var catalog
    @Environment(CognitiveStore.self) private var cognitive
    @Environment(PhysioStore.self) private var physio
    @Environment(\.modelContext) private var modelContext
    @Binding var bootError: String?

    @State private var conversation = ConversationStore(preferLocal: false)
    @State private var exocortex = ExocortexStore()
    @State private var activeSheet: SurfaceSheet?
    @State private var metacogNudge: MetacognitiveObservation?
    @State private var serendipityProvocation: SerendipityProvocation?

    private enum SurfaceSheet: String, Identifiable {
        case settings
        case cognitiveState
        case projectPicker
        case memoryLens
        case originObservatory
        case continuityExplanation
        case capture

        var id: String { rawValue }
    }

    var body: some View {
        surfaceRoot
            .task {
                await bootstrapSurface()
            }
            .onChange(of: conversation.messages.count) {
                runMetacognitiveCheck()
            }
            .sheet(item: $activeSheet) { sheet in
                surfaceSheet(sheet)
            }
            .onChange(of: exocortex.home.mode) { oldValue, newValue in
                markHomeTruthTransition(from: oldValue, to: newValue)
            }
            .onChange(of: latestSurfaceWriteHapticKey) { oldValue, newValue in
                markSurfaceWriteTransition(from: oldValue, to: newValue)
            }
    }

    private var surfaceRoot: some View {
        ZStack {
            livingBackground
            surfaceForeground
            bootErrorOverlay
        }
    }

    private var livingBackground: some View {
        ShellPresenceGradient(
            presence: shellPresence,
            cognitivePosture: physio.cognitivePosture
        )
    }

    private var surfaceForeground: some View {
        VStack(spacing: 0) {
            headerBar
            metacognitiveNudgeLayer
            serendipityLayer

            // Chat-first companion surface: the conversation is the hero, full-height
            // over the living mesh. (The exocortex home card is retired from this surface
            // — it can return as a collapsible header or a separate view later.)
            ChatScreen(store: conversation)
        }
    }

    @ViewBuilder
    private var metacognitiveNudgeLayer: some View {
        if let nudge = metacogNudge {
            metacogNudgeView(nudge)
                .transition(.move(edge: .top).combined(with: .opacity))
        }
    }

    @ViewBuilder
    private var serendipityLayer: some View {
        if let provocation = serendipityProvocation {
            serendipityChip(provocation)
                .transition(.move(edge: .top).combined(with: .opacity))
        }
    }

    @ViewBuilder
    private var bootErrorOverlay: some View {
        if let error = bootError {
            VStack {
                errorBanner(error)
                    .padding(.horizontal, BeagleSpacing.lg)
                    .padding(.top, 60)
                Spacer()
            }
        }
    }

    @ViewBuilder
    private func surfaceSheet(_ sheet: SurfaceSheet) -> some View {
        switch sheet {
        case .settings:
            settingsSheet
        case .cognitiveState:
            cognitiveStateSheet
        case .projectPicker:
            projectPickerSheet
        case .memoryLens:
            memoryLensSheet
        case .originObservatory:
            originObservatorySheet
        case .continuityExplanation:
            continuityExplanationSheet
        case .capture:
            captureSheet
        }
    }

    private var settingsSheet: some View {
        NavigationStack {
            ModelSettingsView()
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Done") { activeSheet = nil }
                    }
                }
        }
    }

    private var cognitiveStateSheet: some View {
        NavigationStack {
            CognitiveStateView()
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Done") { activeSheet = nil }
                    }
                }
        }
    }

    private var projectPickerSheet: some View {
        NavigationStack {
            PlatformView()
                .navigationDestination(for: Project.self) { project in
                    ControlRoomView(slug: project.projectSlug)
                }
        }
    }

    private var memoryLensSheet: some View {
        NavigationStack {
            MemoryLensSheet(exocortex: exocortex, activeProjectSlug: activeSlug)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Done") { activeSheet = nil }
                    }
                }
        }
    }

    private var originObservatorySheet: some View {
        NavigationStack {
            OriginObservatorySheet(lineage: originLineage)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Done") { activeSheet = nil }
                    }
                }
        }
    }

    private var continuityExplanationSheet: some View {
        NavigationStack {
            ContinuityExplanationSheet(
                context: continuityContext,
                home: home,
                truthMode: exocortex.home.mode
            )
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { activeSheet = nil }
                }
            }
        }
    }

    private var captureSheet: some View {
        NavigationStack {
            ThoughtCaptureView()
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Done") { activeSheet = nil }
                    }
                }
        }
    }

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

    private var home: ExocortexHomeSnapshot {
        exocortex.home.value ?? .bootstrap
    }

    private var continuityContext: HomeContinuityContext {
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

    private var latestSurfaceWriteHapticKey: String {
        continuityContext.latestSurfaceWrite?.id ?? ""
    }

    private func markHomeTruthTransition(from oldValue: TruthMode, to newValue: TruthMode) {
        guard oldValue == .stale, newValue == .observed else { return }
        #if canImport(UIKit)
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        #endif
    }

    private func markSurfaceWriteTransition(from oldValue: String, to newValue: String) {
        guard !oldValue.isEmpty, oldValue != newValue, !newValue.isEmpty else { return }
        #if canImport(UIKit)
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        #endif
    }

    private var originLineage: OriginLineageSnapshot {
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
    }

    private func bootstrapSurface() async {
        wireConversation()
        exocortex.modelContext = modelContext
        exocortex.loadCachedHome()
        await refreshLivingHome()
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

    // MARK: - Header bar (project + readiness + settings)

    private var headerBar: some View {
        HStack(spacing: BeagleSpacing.sm) {
            // Project context
            Button { activeSheet = .projectPicker } label: {
                HStack(spacing: BeagleSpacing.xxs) {
                    Image(systemName: "scope")
                        .font(.system(size: 12))
                    Text(activeSlug)
                        .font(BeagleFont.caption.font)
                        .fontWeight(.medium)
                }
                .foregroundStyle(BeagleTheme.truthObserved)
            }
            .buttonStyle(.plain)

            Spacer()

            // Dream insights badge
            if DreamSynthesisEngine.shared.hasUnreadInsights {
                dreamBadge
            }

            // Running agents indicator
            if runningAgentCount > 0 {
                HStack(spacing: BeagleSpacing.xxs) {
                    Image(systemName: "bolt.fill")
                        .font(.system(size: 10))
                    Text("\(runningAgentCount)")
                        .font(BeagleFont.caption2.font)
                }
                .foregroundStyle(BeagleTheme.postureWarm)
            }

            // Readiness
            Button { activeSheet = .cognitiveState } label: {
                HStack(spacing: BeagleSpacing.xxs) {
                    Image(systemName: "heart.fill")
                        .font(.system(size: 10))
                    Text(readinessLabel)
                        .font(BeagleFont.caption2.font)
                }
                .foregroundStyle(readinessColor)
            }
            .buttonStyle(.plain)

            // Settings
            Button { activeSheet = .settings } label: {
                Image(systemName: "gearshape")
                    .font(.system(size: 14))
                    .foregroundStyle(BeagleTheme.textTertiary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, BeagleSpacing.lg)
        .padding(.vertical, BeagleSpacing.sm)
    }

    // MARK: - Dream badge

    private var dreamBadge: some View {
        HStack(spacing: BeagleSpacing.xxs) {
            Image(systemName: "moon.stars.fill")
                .font(.system(size: 10))
            Text("\(DreamSynthesisEngine.shared.unreadCount)")
                .font(BeagleFont.caption2.font)
        }
        .foregroundStyle(Color(hue: 270/360, saturation: 0.5, brightness: 0.9))
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

    // MARK: - Wire conversation on appear

    private func wireConversation() {
        let slug = cognitive.activeProjectSlug ?? catalog.primaryProject?.projectSlug ?? "sounio"
        conversation.modelContext = modelContext
        conversation.projectSlug = slug
        conversation.projectFamily = ProjectFamily.fromProjectSlug(slug)
        conversation.publicationScope = PublicationScope.forProjectFamily(
            ProjectFamily.fromProjectSlug(slug)
        )
        // Derive flow state from readiness
        if let r = physio.cognitivePosture.readiness {
            if r >= 0.7 { conversation.flowState = "FLOW" }
            else if r < 0.3 { conversation.flowState = "STRESS" }
            else { conversation.flowState = "NORMAL" }
        }
        conversation.loadPersistedConversation()

        // Configure Foundation Models with stores
        #if canImport(FoundationModels)
        if #available(iOS 26, macOS 26, visionOS 26, *) {
            FoundationModelsAgent.shared.configure(cognitive: cognitive, physio: physio)
        }
        #endif
    }

    // MARK: - Metacognitive nudge view

    private func metacogNudgeView(_ nudge: MetacognitiveObservation) -> some View {
        HStack(spacing: BeagleSpacing.sm) {
            Image(systemName: nudge.severity == .celebration ? "sparkles" : "brain")
                .font(.system(size: 12))
                .foregroundStyle(nudge.severity == .celebration ? BeagleTheme.truthObserved : BeagleTheme.postureWarm)

            Text(nudge.message)
                .font(BeagleFont.caption.font)
                .foregroundStyle(BeagleTheme.textSecondary)
                .lineLimit(2)

            Spacer(minLength: 0)

            Button {
                withAnimation(BeagleMotion.snappy) {
                    metacogNudge = nil
                }
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 10))
                    .foregroundStyle(BeagleTheme.textTertiary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, BeagleSpacing.lg)
        .padding(.vertical, BeagleSpacing.xs)
        .background(.ultraThinMaterial)
    }

    // MARK: - Serendipity chip

    private func serendipityChip(_ provocation: SerendipityProvocation) -> some View {
        Button {
            // Send the provocation as a conversation prompt
            Task { await conversation.sendMessage(provocation.text) }
            withAnimation(BeagleMotion.snappy) {
                serendipityProvocation = nil
            }
        } label: {
            HStack(spacing: BeagleSpacing.xs) {
                Image(systemName: "wand.and.stars")
                    .font(.system(size: 11))
                VStack(alignment: .leading, spacing: 1) {
                    Text(provocation.domain)
                        .font(BeagleFont.caption2.font)
                        .fontWeight(.semibold)
                    Text(provocation.text)
                        .font(BeagleFont.caption.font)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
                Image(systemName: "arrow.up.right")
                    .font(.system(size: 9))
            }
            .foregroundStyle(Color(hue: 270/360, saturation: 0.4, brightness: 0.85))
            .padding(.horizontal, BeagleSpacing.lg)
            .padding(.vertical, BeagleSpacing.xs)
            .background(.ultraThinMaterial)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Metacognitive check

    private func runMetacognitiveCheck() {
        // Only check after assistant responses (every 2nd message)
        guard conversation.messages.count >= 2,
              conversation.messages.last?.role == .assistant else { return }

        let metacog = MetacognitiveDialogue.shared
        let stagnation = SerendipityEngine.shared.detectStagnation(
            thoughts: cognitive.recentThoughts
        )
        let timeSinceCapture: TimeInterval? = cognitive.recentThoughts.first.flatMap { thought in
            guard let dateStr = thought.createdAt,
                  let date = ISO8601DateFormatter().date(from: dateStr) else { return nil }
            return Date().timeIntervalSince(date)
        }

        metacog.observe(
            consciousnessScore: cognitive.lastConsciousnessScore,
            stagnation: stagnation,
            posture: physio.cognitivePosture,
            thoughtCount: cognitive.recentThoughts.count,
            timeSinceLastCapture: timeSinceCapture
        )

        // Show the most important observation as a nudge
        withAnimation(BeagleMotion.snappy) {
            metacogNudge = metacog.observations.first
        }

        // If stagnating, offer a serendipity provocation
        if metacog.currentState == .stagnating {
            let keywords = cognitive.recentThoughts.prefix(3).compactMap {
                $0.refinedText ?? $0.rawText
            }
            withAnimation(BeagleMotion.snappy) {
                serendipityProvocation = SerendipityEngine.shared.generateProvocation(
                    avoiding: keywords
                )
            }
        } else {
            withAnimation(BeagleMotion.snappy) {
                serendipityProvocation = nil
            }
        }
    }

    // MARK: - Computed

    private var activeSlug: String {
        cognitive.activeProjectSlug ?? catalog.primaryProject?.projectSlug ?? "sounio"
    }

    private var platformName: String {
        #if os(iOS)
        #if canImport(UIKit)
        return UIDevice.current.userInterfaceIdiom == .pad ? "iPad" : "iPhone"
        #else
        return "iOS"
        #endif
        #elseif os(macOS)
        return "macOS"
        #elseif os(visionOS)
        return "visionOS"
        #else
        return "Apple"
        #endif
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

    private var phoneSurfaceLabel: String {
        if home.bodyContext?.localizedCaseInsensitiveContains("iPhone 17 Pro Max") == true {
            return "iPhone 17 Pro Max"
        }
        return platformName
    }

    private var watchSurfaceLabel: String {
        if home.bodyContext?.localizedCaseInsensitiveContains("Apple Watch Ultra 2") == true {
            return "Watch Ultra 2"
        }
        return physio.isAvailable ? "HealthKit" : "Watch loop"
    }

    private var readinessStatusLabel: String {
        if readinessLabel != "—" {
            return readinessLabel
        }
        switch physio.summary.authorizationState {
        case .authorized:
            return physio.summary.readiness == .unavailable ? "waiting" : physio.summary.readiness.rawValue
        case .requesting:
            return "requesting"
        case .denied:
            return "denied"
        case .error:
            return "error"
        case .unavailable:
            return "unavailable"
        case .idle:
            return "ready"
        }
    }

    private var bodyContextLine: String? {
        if let clusterLine = home.bodyContext?.trimmingCharacters(in: .whitespacesAndNewlines),
           !clusterLine.isEmpty {
            return clusterLine
        }
        if physio.summary.isMeaningful || physio.summary.authorizationState != .idle {
            return physio.summary.bodyLine
        }
        return nil
    }

    private var trustContextLine: String? {
        guard let trust = home.trustContext else { return nil }
        let scopeCount = trust.activeScopes.count
        let hashLabel = trust.toolManifestHash.map { String($0.suffix(12)) } ?? "no hash"
        let mesh = trust.memoryEngineStatus.map { " · \($0)" } ?? ""
        let quorum = trust.latestQuorumStatus.map { " · quorum \($0)" } ?? ""
        let governor = trust.memoryGovernorStatus.map { " · governor \($0)" } ?? ""
        let pending = trust.pendingTriads.map { " · triad \($0)" } ?? ""
        let contradictions = trust.openContradictions.map { " · contradictions \($0)" } ?? ""
        let benchGate = trust.benchHotPathEligible.map { " · bench gate \($0 ? "eligible" : "shadow")" } ?? ""
        let semantic = trust.semanticBackboneStatus.map { " · \($0)" } ?? ""
        let hotPath = trust.hotPathMode.map { " · hot path \($0)" } ?? ""
        let provisional = trust.provisionalHotPath == true ? " · provisional" : ""
        let capture = trust.captureLoopStatus.map { " · capture \($0)" } ?? ""
        let compiler = trust.contextCompilerStatus.map { " · compiler \($0)" } ?? ""
        let policy = trust.memoryPolicyStatus.map { " · policy \($0)" } ?? ""
        let dream = trust.dreamcycleStatus.map { " · dream \($0)" } ?? ""
        let sounio = trust.sounioPaperRunStatus.map { " · Sounio \($0)" } ?? ""
        let temporal = trust.sounioTemporalStatus.map { " · Temporal \($0)" } ?? ""
        return "\(trust.mcpStatus) · \(scopeCount) scopes · \(hashLabel)\(semantic)\(hotPath)\(provisional)\(compiler)\(policy)\(dream)\(sounio)\(temporal)\(mesh)\(governor)\(pending)\(contradictions)\(quorum)\(benchGate)\(capture) · destructive locked"
    }

    private var memoryProjectionLine: String {
        let status = exocortex.recentGraph?.value?.status
            ?? exocortex.projectionStatus?.value
            ?? home.trustContext?.memoryProjectionStatus
        guard let status else {
            return "Projection not observed yet; tap to inspect cluster memory."
        }
        let runtime = home.trustContext?.semanticBackboneStatus ?? home.trustContext?.graphRuntime ?? exocortex.graphStatus?.value?.graphRuntime ?? "jsonl"
        let mode = home.trustContext?.hotPathMode ?? home.trustContext?.retrievalMode ?? exocortex.graphStatus?.value?.retrievalMode ?? status.retrievalMode
        let degrade = home.trustContext?.graphDegradedReason ?? exocortex.graphStatus?.value?.degradedReason ?? status.degradedReason
        let hash = home.trustContext?.lastWorldHash.map { " · \($0.prefix(18))" } ?? ""
        let candidate = home.trustContext?.latestCandidateRef.map { " · candidate \($0.prefix(12))" } ?? ""
        let bench = memoryBenchLine.map { " · \($0)" } ?? ""
        return "\(runtime) · \(mode) · \(status.episodeCount) episodes · \(status.atomCount) atoms · \(degrade)\(bench)\(hash)\(candidate)"
    }

    private var semanticBackboneDetail: String {
        guard let trust = home.trustContext else {
            return "awaiting cluster trust"
        }
        let backbone = trust.semanticBackboneStatus ?? "semantic-backbone-unknown"
        let hotPath = trust.hotPathMode ?? trust.retrievalMode ?? "unknown"
        let gate = trust.provisionalHotPath == true ? "provisional" : (trust.benchHotPathEligible == true ? "confirmed" : "shadow")
        return "\(backbone) · \(hotPath) · \(gate)"
    }

    private var memoryBenchLine: String? {
        if let trust = home.trustContext,
           let status = trust.memoryBenchStatus {
            let score = trust.latestBenchScore.map { " \(String(format: "%.2f", $0))" } ?? ""
            let regressions = trust.memoryRegressionCount.map { " · \($0) regressions" } ?? ""
            let gate = trust.benchHotPathEligible.map { " · \($0 ? "hot-path eligible" : "shadow gate")" } ?? ""
            let truthset = trust.truthsetId.map { " · truth \($0.prefix(12))" } ?? ""
            return "bench \(status)\(score)\(regressions)\(gate)\(truthset)"
        }
        if let bench = exocortex.benchmarkStatus?.value {
            let score = bench.latestScore.map { " \(String(format: "%.2f", $0))" } ?? ""
            let gate = bench.hotPathEligible ? " · hot-path eligible" : " · shadow gate"
            let truthset = bench.truthsetId.map { " · truth \($0.prefix(12))" } ?? ""
            return "bench \(bench.status)\(score) · \(bench.regressionCount) regressions\(gate)\(truthset)"
        }
        return nil
    }

    private var latestAgentWriteLine: String? {
        if let latest = home.trustContext?.latestAgentWrite?.trimmingCharacters(in: .whitespacesAndNewlines),
           !latest.isEmpty {
            return latest
        }
        if let latest = home.agentContext?.lastAgentWrite?.trimmingCharacters(in: .whitespacesAndNewlines),
           !latest.isEmpty {
            return latest
        }
        if let atom = exocortex.recentGraph?.value?.atoms.first(where: isWorkMemoryAtom) {
            return "\(atom.atomType) · \(atom.text)"
        }
        return nil
    }

    private var latestGrokImportLine: String? {
        if let signal = home.memorySignals.first(where: { $0.localizedCaseInsensitiveContains("grok") }) {
            return signal
        }
        if let episode = exocortex.recentGraph?.value?.episodes.first(where: isGrokEpisode) {
            let when = episode.occurredAt ?? episode.createdAt
            return "\(episode.title ?? episode.sourceRef) · \(when)"
        }
        if let atom = exocortex.recentGraph?.value?.atoms.first(where: isGrokAtom) {
            return "\(atom.atomType) · \(atom.text)"
        }
        return nil
    }

    private var autoImportTitle: String {
        switch conversation.autoImportState.status {
        case "imported":
            return "Auto-memory"
        case "importing":
            return "Importing"
        case "blocked":
            return "Privacy held"
        case "queued":
            return "Queued"
        default:
            return "Auto-memory"
        }
    }

    private var autoImportDetail: String {
        let state = conversation.autoImportState
        if let summary = state.lastSummary, state.status == "imported" {
            return "\(summary) · GraphRAG++"
        }
        if state.restrictedCount > 0 {
            return "\(state.restrictedCount) restricted · explicit review"
        }
        if state.queuedCount > 0 {
            return "\(state.queuedCount) queued · cluster retry"
        }
        return "Every completed exchange becomes Episode+Atom."
    }

    private var agentContextDetail: String {
        if let agent = home.agentContext {
            if let last = agent.lastAgentWrite, !last.isEmpty {
                return "\(agent.mcpStatus) · last \(last)"
            }
            return "\(agent.mcpStatus) · \(agent.activeSessions) sessions"
        }
        return home.clusterTruth
    }

    private func isWorkMemoryAtom(_ atom: MemoryAtom) -> Bool {
        guard atom.privacyClass != "restricted" else { return false }
        let haystack = (atom.tags + [atom.atomType, atom.text]).joined(separator: " ").lowercased()
        return haystack.contains("work-memory")
            || haystack.contains("codex")
            || haystack.contains("claude-code")
            || haystack.contains("agent:")
    }

    private func isGrokEpisode(_ episode: MemoryEpisode) -> Bool {
        guard episode.privacyClass != "restricted" else { return false }
        let haystack = (episode.tags + [
            episode.source,
            episode.sourcePlatform ?? "",
            episode.title ?? "",
            episode.sourceRef
        ]).joined(separator: " ").lowercased()
        return haystack.contains("grok")
    }

    private func isGrokAtom(_ atom: MemoryAtom) -> Bool {
        guard atom.privacyClass != "restricted" else { return false }
        let haystack = (atom.tags + [atom.atomType, atom.text]).joined(separator: " ").lowercased()
        return haystack.contains("grok")
    }

    private var bodyLoopTitle: String {
        if readinessLabel != "—" {
            return "Body \(readinessLabel)"
        }
        if physio.summary.authorizationState == .authorized {
            return physio.summary.readiness.title
        }
        return "Body loop"
    }

    private var bodyLoopDetail: String {
        if physio.summary.isMeaningful {
            return physio.summary.detailLine
        }
        return bodyContextLine ?? "Waiting for Ultra 2 and HealthKit samples."
    }
}

// MARK: - Living Home

private struct LivingHomeHeader: View {
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

private struct ContinuityDeltaBand: View {
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

private struct NextMoveDock: View {
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

private struct ContinuityExplanationSheet: View {
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

private struct OriginObservatorySheet: View {
    let lineage: OriginLineageSnapshot
    @State private var selectedTab: OriginTab = .timeline

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

// MARK: - Memory Lens

private struct MemoryLensSheet: View {
    let exocortex: ExocortexStore
    let activeProjectSlug: String
    @State private var query = ""
    @State private var isSearching = false
    @State private var selectedTab: LensTab = .evidence
    @State private var lensMode: MemoryLensMode = .report
    @State private var selectedProof: ProofSheetModel?

    private enum LensTab: String, CaseIterable, Identifiable {
        case evidence = "Evidence"
        case timeline = "Timeline"
        case sounioWorkday = "Sounio"
        case worlds = "Worlds"
        case work = "Work"
        case contradictions = "Contradictions"
        case candidates = "Candidates"
        case truth = "Truth"
        case bench = "Bench"
        case context = "Context"
        case agentTrace = "Agent"
        case semanticTrace = "Semantic"
        case runtimeTrace = "Runtime"

        var id: String { rawValue }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: BeagleSpacing.md) {
                livingReportLayer
                deepDiveToggle
                if lensMode == .deepDive {
                    deepDiveLayer
                }
            }
            .padding(BeagleSpacing.lg)
        }
        .navigationTitle("Memory Lens")
        .background(BeagleTheme.surface0.ignoresSafeArea())
        .sheet(item: $selectedProof) { proof in
            ProofSheet(model: proof)
        }
        .task {
            async let graphStatus: Void = exocortex.refreshGraphStatus()
            async let benchmark: Void = exocortex.refreshBenchmarkStatus()
            async let recentGraph: Void = exocortex.refreshRecentGraph(limit: 16)
            async let worlds: Void = exocortex.refreshRecentWorlds(limit: 16)
            async let candidates: Void = exocortex.refreshMemoryCandidates(limit: 20)
            async let governance: Void = exocortex.refreshMemoryGovernanceStatus()
            async let contradictions: Void = exocortex.refreshMemoryContradictions(limit: 20)
            async let sounioWorkday: Void = exocortex.refreshSounioWorkday(projectSlug: activeProjectSlug, limit: 25)
            async let sounioMoments: Void = exocortex.refreshRecentSounioMoments(projectSlug: activeProjectSlug, limit: 25)
            if let truthsetId = exocortex.home.value?.trustContext?.truthsetId {
                async let truthset: Void = exocortex.refreshTruthSetStatus(id: truthsetId)
                _ = await (graphStatus, benchmark, recentGraph, worlds, candidates, governance, contradictions, sounioWorkday, sounioMoments, truthset)
            } else {
                _ = await (graphStatus, benchmark, recentGraph, worlds, candidates, governance, contradictions, sounioWorkday, sounioMoments)
            }
        }
    }

    private var report: MemoryLensReport {
        MemoryLensReport.synthesized(
            home: exocortex.home.value,
            homeTruthMode: exocortex.home.mode,
            graphStatus: exocortex.graphStatus?.value,
            recentGraph: exocortex.recentGraph?.value,
            benchmark: exocortex.benchmarkStatus?.value,
            governance: exocortex.memoryGovernanceStatus?.value,
            contradictions: exocortex.memoryContradictions?.value,
            lastQuery: exocortex.lastGraphRagQuery?.value,
            activeProjectSlug: activeProjectSlug
        )
    }

    private var livingReportLayer: some View {
        let report = report
        return VStack(alignment: .leading, spacing: BeagleSpacing.md) {
            LivingMemoryReportHeader(report: report) {
                selectedProof = report.proof
            }
            SourceConfidenceStrip(report: report)
            MemoryQuestionDock(
                query: $query,
                isSearching: isSearching,
                onSubmit: {
                    Task { await runQuery() }
                }
            )
            LensPresetRail(presets: report.presets) { preset in
                Task { await runPreset(preset) }
            }
            EvidenceFrontier(report: report) { proof in
                selectedProof = proof
            }
        }
    }

    private var deepDiveToggle: some View {
        Button {
            withAnimation(.snappy(duration: 0.22)) {
                lensMode = lensMode == .deepDive ? .report : .deepDive
            }
        } label: {
            HStack {
                Label(lensMode == .deepDive ? "Hide lab bench" : "Open lab bench", systemImage: "slider.horizontal.3")
                    .font(BeagleFont.caption.font)
                    .fontWeight(.semibold)
                Spacer()
                Image(systemName: lensMode == .deepDive ? "chevron.up" : "chevron.down")
                    .font(.system(size: 12, weight: .semibold))
            }
            .foregroundStyle(BeagleTheme.textSecondary)
            .padding(.horizontal, BeagleSpacing.sm)
            .padding(.vertical, BeagleSpacing.xs)
            .background(
                Capsule()
                    .fill(BeagleTheme.surface1.opacity(0.72))
            )
        }
        .buttonStyle(.plain)
    }

    private var deepDiveLayer: some View {
        VStack(alignment: .leading, spacing: BeagleSpacing.md) {
            header
            lensPicker
            switch selectedTab {
            case .evidence:
                evidenceTab
            case .timeline:
                timelineTab
            case .sounioWorkday:
                sounioWorkdayTab
            case .worlds:
                worldsTab
            case .work:
                workTab
            case .contradictions:
                contradictionsTab
            case .candidates:
                candidatesTab
            case .truth:
                truthTab
            case .bench:
                benchTab
            case .context:
                contextTab
            case .agentTrace:
                agentTraceTab
            case .semanticTrace:
                semanticTraceTab
            case .runtimeTrace:
                runtimeTraceTab
            }
        }
        .transition(.opacity.combined(with: .move(edge: .top)))
    }

    private var header: some View {
        let graphStatus = exocortex.graphStatus?.value
        let status = graphStatus?.projectionStatus
            ?? exocortex.recentGraph?.value?.status
            ?? exocortex.projectionStatus?.value
        return GlassPanel(truth: exocortex.graphStatus?.mode ?? exocortex.recentGraph?.mode ?? exocortex.projectionStatus?.mode ?? .declared) {
            VStack(alignment: .leading, spacing: BeagleSpacing.xs) {
                Text((graphStatus?.graphRuntime ?? "GRAPHRAG++").uppercased())
                    .font(BeagleFont.caption2.font)
                    .fontWeight(.semibold)
                    .foregroundStyle(BeagleTheme.textTertiary)
                Text(statusLine(status))
                    .font(BeagleFont.callout.font)
                    .foregroundStyle(BeagleTheme.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                if let graphStatus {
                    Text("\(graphStatus.retrievalMode) · \(graphStatus.worldCount) worlds")
                        .font(BeagleFont.caption.font)
                        .foregroundStyle(BeagleTheme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if let trust = exocortex.home.value?.trustContext {
                    let mesh = trust.memoryEngineStatus ?? "mesh not observed"
                    let candidate = trust.latestCandidateRef.map { " · candidate \($0.prefix(12))" } ?? ""
                    let quorum = trust.latestQuorumStatus.map { " · quorum \($0)" } ?? ""
                    let governor = trust.memoryGovernorStatus.map { " · governor \($0)" } ?? ""
                    let triad = trust.pendingTriads.map { " · pending \($0)" } ?? ""
                    let contradictions = trust.openContradictions.map { " · contradictions \($0)" } ?? ""
                    let bench = trust.memoryBenchStatus.map { " · bench \($0)" } ?? ""
                    let score = trust.latestBenchScore.map { " \(String(format: "%.2f", $0))" } ?? ""
                    let gate = trust.benchHotPathEligible.map { " · gate \($0 ? "eligible" : "shadow")" } ?? ""
                    let capture = trust.captureLoopStatus.map { " · capture \($0)" } ?? ""
                    let retrieval = trust.retrievalAgentStatus.map { " · retrieval \($0)" } ?? ""
                    let arena = trust.memoryarenaGate.map { " · arena \($0)" } ?? ""
                    Text("\(mesh)\(retrieval)\(arena)\(governor)\(triad)\(contradictions)\(bench)\(score)\(gate)\(capture)\(candidate)\(quorum)")
                        .font(BeagleFont.caption.font)
                        .foregroundStyle(BeagleTheme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if let latestWorkMemoryLine {
                    lensContextLine("work memory · \(latestWorkMemoryLine)")
                }
                if let latestGrokImportLine {
                    lensContextLine("grok import · \(latestGrokImportLine)")
                }
                if let degraded = graphStatus?.degradedReason ?? status?.degradedReason, !degraded.isEmpty {
                    Text(degraded)
                        .font(BeagleFont.caption.font)
                        .foregroundStyle(BeagleTheme.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private var lensPicker: some View {
        Picker("Lens", selection: $selectedTab) {
            ForEach(LensTab.allCases) { tab in
                Text(tab.rawValue).tag(tab)
            }
        }
        .pickerStyle(.menu)
    }

    private var evidenceTab: some View {
        VStack(alignment: .leading, spacing: BeagleSpacing.md) {
            queryBar
            if let graph = exocortex.lastGraphRagQuery?.value {
                graphResult(graph)
            }
            recentGraph
        }
    }

    private var timelineTab: some View {
        VStack(alignment: .leading, spacing: BeagleSpacing.sm) {
            sectionTitle("RECENT EPISODES")
            let episodes = (exocortex.recentGraph?.value?.episodes ?? []).filter(isDisplayableEpisode)
            if episodes.isEmpty {
                emptyRow("No projected episodes yet.")
            } else {
                ForEach(episodes.prefix(16)) { episode in
                    GlassPanel(truth: .remembered) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(episode.title ?? episode.sourceRef)
                                .font(BeagleFont.caption.font)
                                .fontWeight(.semibold)
                                .foregroundStyle(BeagleTheme.textPrimary)
                                .lineLimit(2)
                            Text("\(episode.source) · \(episode.sourcePlatform ?? "unknown") · \(episode.occurredAt ?? episode.createdAt)")
                                .font(BeagleFont.caption2.font)
                                .foregroundStyle(BeagleTheme.textTertiary)
                                .lineLimit(1)
                            Text(episode.tags.prefix(5).joined(separator: " · "))
                                .font(BeagleFont.caption2.font)
                                .foregroundStyle(BeagleTheme.textTertiary)
                                .lineLimit(1)
                        }
                    }
                }
            }
        }
    }

    private var sounioWorkdaySnapshot: SounioWorkdaySnapshot? {
        exocortex.sounioWorkday?.value ?? exocortex.home.value?.sounioWorkdayContext
    }

    private var sounioWorkdayTab: some View {
        VStack(alignment: .leading, spacing: BeagleSpacing.md) {
            sectionTitle("SOUNIO WORKDAY")
            if let workday = sounioWorkdaySnapshot {
                GlassPanel(truth: exocortex.sounioWorkday?.mode ?? exocortex.home.mode) {
                    VStack(alignment: .leading, spacing: BeagleSpacing.xs) {
                        HStack {
                            Text(workday.status.uppercased())
                                .font(BeagleFont.caption2.font)
                                .fontWeight(.semibold)
                                .foregroundStyle(BeagleTheme.truthDeclared)
                            Spacer()
                            Text("\(workday.moments.count) moments")
                                .font(BeagleFont.caption2.font.monospaced())
                                .foregroundStyle(BeagleTheme.textTertiary)
                        }
                        Text(workday.nextAction)
                            .font(BeagleFont.caption.font)
                            .foregroundStyle(BeagleTheme.textPrimary)
                            .fixedSize(horizontal: false, vertical: true)
                        if !workday.tensions.isEmpty {
                            Text("tension · \(workday.tensions.prefix(2).joined(separator: " · "))")
                                .font(BeagleFont.caption2.font)
                                .foregroundStyle(BeagleTheme.textTertiary)
                                .lineLimit(3)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }

                if !workday.decisionSeeds.isEmpty {
                    sectionTitle("DECISIONS")
                    ForEach(Array(workday.decisionSeeds.prefix(6).enumerated()), id: \.offset) { _, decision in
                        lensTextRow("checkmark.circle", "Decision seed", decision, tint: BeagleTheme.truthObserved)
                    }
                }

                if !workday.claimSeeds.isEmpty {
                    sectionTitle("CLAIM<T> SEEDS")
                    ForEach(workday.claimSeeds.prefix(8)) { claim in
                        GlassPanel(truth: .declared) {
                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    Text(claim.epistemicStatus.uppercased())
                                        .font(BeagleFont.caption2.font)
                                        .fontWeight(.semibold)
                                        .foregroundStyle(claim.epistemicStatus == "contest" ? BeagleTheme.postureWarm : BeagleTheme.truthDeclared)
                                    Spacer()
                                    Text(claim.reviewState)
                                        .font(BeagleFont.caption2.font.monospaced())
                                        .foregroundStyle(BeagleTheme.textTertiary)
                                }
                                Text(claim.claimText)
                                    .font(BeagleFont.caption.font)
                                    .foregroundStyle(BeagleTheme.textPrimary)
                                    .fixedSize(horizontal: false, vertical: true)
                                Text(claim.evidenceRefs.prefix(2).joined(separator: " · "))
                                    .font(BeagleFont.caption2.font.monospaced())
                                    .foregroundStyle(BeagleTheme.textTertiary)
                                    .lineLimit(1)
                            }
                        }
                    }
                }

                sectionTitle("MOMENTS")
                if workday.moments.isEmpty {
                    emptyRow("No Sounio moments yet.")
                } else {
                    ForEach(workday.moments.prefix(16)) { moment in
                        sounioMomentRow(moment)
                    }
                }
            } else {
                emptyRow("Sounio Workday has not been observed yet.")
            }
        }
    }

    private var worldsTab: some View {
        VStack(alignment: .leading, spacing: BeagleSpacing.sm) {
            sectionTitle("MEMORY WORLDS")
            let worlds = exocortex.recentWorlds?.value?.worlds ?? exocortex.recentGraph?.value?.worlds ?? []
            if worlds.isEmpty {
                emptyRow("No content-addressed MemoryWorlds yet. Index the graph after the next import.")
            } else {
                ForEach(worlds.prefix(16)) { world in
                    GlassPanel(truth: .observed) {
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(world.worldType.uppercased())
                                    .font(BeagleFont.caption2.font)
                                    .fontWeight(.semibold)
                                    .foregroundStyle(BeagleTheme.truthObserved)
                                Spacer()
                                Text("\(world.nodeCount)n \(world.edgeCount)e")
                                    .font(BeagleFont.caption2.font)
                                    .foregroundStyle(BeagleTheme.textTertiary)
                            }
                            Text(world.title ?? world.sourceRef)
                                .font(BeagleFont.caption.font)
                                .foregroundStyle(BeagleTheme.textPrimary)
                                .lineLimit(2)
                            Text(world.merkleRoot)
                                .font(BeagleFont.caption2.font.monospaced())
                                .foregroundStyle(BeagleTheme.textTertiary)
                                .lineLimit(1)
                        }
                    }
                }
            }
        }
    }

    private var workTab: some View {
        VStack(alignment: .leading, spacing: BeagleSpacing.sm) {
            sectionTitle("WORK MEMORY")
            let workAtoms = (exocortex.recentGraph?.value?.atoms ?? []).filter { atom in
                let haystack = (atom.tags + [atom.atomType, atom.text]).joined(separator: " ").lowercased()
                return isDisplayableAtom(atom) && (haystack.contains("work-memory")
                    || haystack.contains("codex")
                    || haystack.contains("claude-code")
                    || haystack.contains("agent:"))
            }
            if let latest = exocortex.home.value?.trustContext?.latestAgentWrite {
                Text("latest agent write · \(latest)")
                    .font(BeagleFont.caption.font)
                    .foregroundStyle(BeagleTheme.textSecondary)
            }
            if let latestWorkMemoryLine {
                Text("latest work event · \(latestWorkMemoryLine)")
                    .font(BeagleFont.caption.font)
                    .foregroundStyle(BeagleTheme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let latestGrokImportLine {
                Text("grok corpus signal · \(latestGrokImportLine)")
                    .font(BeagleFont.caption.font)
                    .foregroundStyle(BeagleTheme.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if workAtoms.isEmpty {
                emptyRow("No Codex or Claude Code work-memory atoms observed yet.")
            } else {
                ForEach(workAtoms.prefix(12)) { atom in
                    memoryAtomRow(atom)
                }
            }
        }
    }

    private var contradictionsTab: some View {
        VStack(alignment: .leading, spacing: BeagleSpacing.sm) {
            sectionTitle("CONTRADICTIONS")
            let contradictions = exocortex.memoryContradictions?.value?.contradictions ?? []
            let relations = (exocortex.recentGraph?.value?.relations ?? []).filter {
                $0.predicate.lowercased().contains("contradict")
                    || $0.predicate.lowercased().contains("conflict")
                    || $0.predicate.lowercased().contains("tension")
            }
            if !contradictions.isEmpty {
                ForEach(contradictions.prefix(20)) { contradiction in
                    GlassPanel(truth: .declared) {
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text("CONTRADICTION")
                                    .font(BeagleFont.caption2.font)
                                    .fontWeight(.semibold)
                                    .foregroundStyle(BeagleTheme.truthDeclared)
                                Spacer()
                                Text("\(contradiction.severity) · \(contradiction.status)")
                                    .font(BeagleFont.caption2.font)
                                    .foregroundStyle(BeagleTheme.textTertiary)
                            }
                            Text(contradiction.description)
                                .font(BeagleFont.caption.font)
                                .foregroundStyle(BeagleTheme.textPrimary)
                                .fixedSize(horizontal: false, vertical: true)
                            Text("\(contradiction.subjectRef) ↔ \(contradiction.conflictingRef)")
                                .font(BeagleFont.caption2.font.monospaced())
                                .foregroundStyle(BeagleTheme.textTertiary)
                                .lineLimit(1)
                        }
                    }
                }
            } else if relations.isEmpty {
                emptyRow("No explicit contradiction relations observed in the recent graph.")
            } else {
                ForEach(relations.indices, id: \.self) { index in
                    relationRow(relations[index])
                }
            }
        }
    }

    private var candidatesTab: some View {
        VStack(alignment: .leading, spacing: BeagleSpacing.sm) {
            sectionTitle("TRIAD REVIEW")
            if let governance = exocortex.memoryGovernanceStatus?.value {
                GlassPanel(truth: .observed) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("\(governance.status) · \(governance.candidateCount) candidates")
                            .font(BeagleFont.caption.font)
                            .fontWeight(.semibold)
                            .foregroundStyle(BeagleTheme.textPrimary)
                        Text("\(governance.pendingTriads) pending · \(governance.promotedCount) promoted · \(governance.rejectedCount) rejected · \(governance.openContradictions) contradictions")
                            .font(BeagleFont.caption2.font)
                            .foregroundStyle(BeagleTheme.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                        if let decision = governance.latestPromotionDecision {
                            Text("latest \(decision.decision) · \(decision.rationale)")
                                .font(BeagleFont.caption2.font)
                                .foregroundStyle(BeagleTheme.textTertiary)
                                .lineLimit(2)
                        }
                    }
                }
            }
            let candidates = (exocortex.memoryCandidates?.value?.candidates ?? []).filter {
                $0.privacyClass.lowercased() != "restricted" && !containsRestrictedMarker($0.text)
            }
            if candidates.isEmpty {
                emptyRow("No candidate atoms or hyperedges awaiting Triad quorum.")
            } else {
                ForEach(candidates.prefix(20)) { candidate in
                    GlassPanel(truth: .declared) {
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(candidate.candidateType.uppercased())
                                    .font(BeagleFont.caption2.font)
                                    .fontWeight(.semibold)
                                    .foregroundStyle(BeagleTheme.truthDeclared)
                                Spacer()
                                Text(candidate.status)
                                    .font(BeagleFont.caption2.font)
                                    .foregroundStyle(BeagleTheme.textTertiary)
                            }
                            Text(candidate.text)
                                .font(BeagleFont.caption.font)
                                .foregroundStyle(BeagleTheme.textPrimary)
                                .fixedSize(horizontal: false, vertical: true)
                            Text("confidence \(String(format: "%.2f", candidate.confidence)) · \(candidate.privacyClass)")
                                .font(BeagleFont.caption2.font)
                                .foregroundStyle(BeagleTheme.textTertiary)
                            if let quorum = candidate.quorumRef {
                                Text("triad quorum · \(quorum)")
                                    .font(BeagleFont.caption2.font.monospaced())
                                    .foregroundStyle(BeagleTheme.textTertiary)
                                    .lineLimit(1)
                            }
                            if candidate.status == "triad_pending" {
                                Text("pending strict 3/3 promotion; Home/search stay promoted-only")
                                    .font(BeagleFont.caption2.font)
                                    .foregroundStyle(BeagleTheme.textTertiary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                }
            }
        }
    }

    private var benchTab: some View {
        VStack(alignment: .leading, spacing: BeagleSpacing.sm) {
            sectionTitle("MEMORY BENCH")
            if let bench = exocortex.benchmarkStatus?.value {
                GlassPanel(truth: bench.status == "passing" ? .observed : .declared) {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(bench.status.uppercased())
                                .font(BeagleFont.caption2.font)
                                .fontWeight(.semibold)
                                .foregroundStyle(bench.status == "passing" ? BeagleTheme.truthObserved : BeagleTheme.truthDeclared)
                            Spacer()
                            if let score = bench.latestScore {
                                Text(String(format: "%.2f", score))
                                    .font(BeagleFont.caption2.font.monospaced())
                                    .foregroundStyle(BeagleTheme.textTertiary)
                            }
                        }
                        Text("\(bench.queryCount) queries · \(bench.regressionCount) regressions")
                            .font(BeagleFont.caption.font)
                            .foregroundStyle(BeagleTheme.textSecondary)
                        if !bench.evaluatedModes.isEmpty {
                            Text(bench.evaluatedModes.joined(separator: " · "))
                                .font(BeagleFont.caption2.font)
                                .foregroundStyle(BeagleTheme.textTertiary)
                                .lineLimit(2)
                        }
                        if let reason = bench.degradedReason {
                            Text(reason)
                                .font(BeagleFont.caption2.font)
                                .foregroundStyle(BeagleTheme.textTertiary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                if let latest = bench.latestRun {
                    ForEach(latest.modeResults.prefix(6)) { result in
                        GlassPanel(truth: result.status.contains("pass") ? .observed : .declared) {
                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    Text(result.mode.uppercased())
                                        .font(BeagleFont.caption2.font)
                                        .fontWeight(.semibold)
                                        .foregroundStyle(BeagleTheme.truthObserved)
                                    Spacer()
                                    Text(String(format: "%.2f", result.score))
                                        .font(BeagleFont.caption2.font.monospaced())
                                        .foregroundStyle(BeagleTheme.textTertiary)
                                }
                                Text(result.status)
                                    .font(BeagleFont.caption.font)
                                    .foregroundStyle(BeagleTheme.textSecondary)
                                if let metrics = result.metrics {
                                    Text("top-k \(String(format: "%.2f", metrics.topKHitRate ?? 0)) · provenance \(String(format: "%.2f", metrics.provenanceCompleteness ?? 0)) · leaks \(metrics.restrictedLeakCount ?? 0)")
                                        .font(BeagleFont.caption2.font)
                                        .foregroundStyle(BeagleTheme.textTertiary)
                                }
                            }
                        }
                    }
                }
            } else if let trust = exocortex.home.value?.trustContext,
                      let status = trust.memoryBenchStatus {
                emptyRow("Bench \(status) observed in Home; open cluster status for detailed mode scores.")
            } else {
                emptyRow("No Memory Bench run observed yet.")
            }
        }
    }

    private var truthTab: some View {
        VStack(alignment: .leading, spacing: BeagleSpacing.sm) {
            sectionTitle("MEMORY TRUTH")
            if let bench = exocortex.benchmarkStatus?.value {
                GlassPanel(truth: bench.hotPathEligible ? .observed : .declared) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(bench.hotPathEligible ? "HOT PATH ELIGIBLE" : "SHADOW GATE")
                            .font(BeagleFont.caption2.font)
                            .fontWeight(.semibold)
                            .foregroundStyle(bench.hotPathEligible ? BeagleTheme.truthObserved : BeagleTheme.truthDeclared)
                        if let truthsetId = bench.truthsetId {
                            Text("truthset \(truthsetId)")
                                .font(BeagleFont.caption.font.monospaced())
                                .foregroundStyle(BeagleTheme.textSecondary)
                                .lineLimit(2)
                        }
                        if let gate = bench.promotionGate {
                            Text("\(gate.candidateMode) vs \(gate.baselineMode) · margin \(String(format: "%.2f", gate.requiredMargin)) · runs \(gate.consecutivePassingRuns)/\(gate.requiredConsecutiveRuns)")
                                .font(BeagleFont.caption.font)
                                .foregroundStyle(BeagleTheme.textSecondary)
                            Text(gate.rationale)
                                .font(BeagleFont.caption2.font)
                                .foregroundStyle(BeagleTheme.textTertiary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                if let latest = bench.latestRun, !latest.caseJudgments.isEmpty {
                    ForEach(latest.caseJudgments.prefix(8)) { judgment in
                        GlassPanel(truth: judgment.passed ? .observed : .declared) {
                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    Text(judgment.domain.uppercased())
                                        .font(BeagleFont.caption2.font)
                                        .fontWeight(.semibold)
                                        .foregroundStyle(judgment.passed ? BeagleTheme.truthObserved : BeagleTheme.postureWarm)
                                    Spacer()
                                    Text(String(format: "%.2f", judgment.score))
                                        .font(BeagleFont.caption2.font.monospaced())
                                        .foregroundStyle(BeagleTheme.textTertiary)
                                }
                                Text(judgment.query)
                                    .font(BeagleFont.caption.font)
                                    .foregroundStyle(BeagleTheme.textSecondary)
                                    .fixedSize(horizontal: false, vertical: true)
                                if !judgment.supportingRefs.isEmpty {
                                    Text(judgment.supportingRefs.prefix(4).joined(separator: " · "))
                                        .font(BeagleFont.caption2.font)
                                        .foregroundStyle(BeagleTheme.textTertiary)
                                        .lineLimit(2)
                                }
                            }
                        }
                    }
                }
            } else if let trust = exocortex.home.value?.trustContext {
                let gate = trust.benchHotPathEligible == true ? "eligible" : "shadow"
                emptyRow("Truth gate \(gate); truthset \(trust.truthsetId ?? "not observed").")
            } else {
                emptyRow("No truthset gate observed yet.")
            }

            sectionTitle("CAPTURE LOOP")
            if let trust = exocortex.home.value?.trustContext {
                let observer = trust.agentObserverStatus ?? "not-observed"
                let capture = trust.captureLoopStatus ?? "pending-first-capture"
                let apple = trust.appleCaptureFreshness ?? "no Apple capture"
                emptyRow("Agent observer \(observer) · \(capture) · Apple \(apple)")
            } else {
                emptyRow("Home trust context not loaded.")
            }
        }
    }

    private var agentTraceTab: some View {
        VStack(alignment: .leading, spacing: BeagleSpacing.sm) {
            sectionTitle("RETRIEVAL AGENT")
            if let graph = exocortex.lastGraphRagQuery?.value {
                GlassPanel(truth: graph.retrievalAgent == "default" ? .observed : .declared) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text((graph.strategyUsed ?? "strategy pending").uppercased())
                            .font(BeagleFont.caption2.font)
                            .fontWeight(.semibold)
                            .foregroundStyle(BeagleTheme.truthObserved)
                        Text("\(graph.retrievalAgent ?? "agent") · planner \(graph.plannerMode ?? "hybrid") · \(graph.contextFormat ?? "context pack pending")")
                            .font(BeagleFont.caption.font)
                            .foregroundStyle(BeagleTheme.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                        if let plan = graph.retrievalPlanId {
                            Text(plan)
                                .font(BeagleFont.caption2.font.monospaced())
                                .foregroundStyle(BeagleTheme.textTertiary)
                                .lineLimit(1)
                        }
                    }
                }
                if !graph.subqueries.isEmpty {
                    sectionTitle("SUBQUERIES")
                    ForEach(Array(graph.subqueries.prefix(6).enumerated()), id: \.offset) { _, item in
                        Text(item)
                            .font(BeagleFont.caption.font)
                            .foregroundStyle(BeagleTheme.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                if let pack = graph.evidencePack {
                    sectionTitle("EVIDENCE PACK")
                    Text(String(describing: pack))
                        .font(BeagleFont.caption2.font)
                        .foregroundStyle(BeagleTheme.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if !graph.runtimeTrace.isEmpty {
                    sectionTitle("AGENT TRACE")
                    ForEach(graph.runtimeTrace.prefix(10)) { step in
                        GlassPanel(truth: step.status.contains("fallback") ? .declared : .observed) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(step.stage.uppercased())
                                    .font(BeagleFont.caption2.font)
                                    .fontWeight(.semibold)
                                    .foregroundStyle(BeagleTheme.textTertiary)
                                Text("\(step.backend) · \(step.status) · \(step.items) items")
                                    .font(BeagleFont.caption.font)
                                    .foregroundStyle(BeagleTheme.textSecondary)
                                if !step.notes.isEmpty {
                                    Text(step.notes.prefix(3).joined(separator: " · "))
                                        .font(BeagleFont.caption2.font)
                                        .foregroundStyle(BeagleTheme.textTertiary)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                            }
                        }
                    }
                }
            } else if let trust = exocortex.home.value?.trustContext {
                emptyRow("Retrieval \(trust.retrievalAgentStatus ?? "not observed") · strategy \(trust.latestRetrievalStrategy ?? "pending") · arena \(trust.memoryarenaGate ?? "shadow")")
            } else {
                emptyRow("Run a Memory Lens query to see Retrieval Agent plan, evidence pack and runtime trace.")
            }
        }
    }

    private var runtimeTraceTab: some View {
        VStack(alignment: .leading, spacing: BeagleSpacing.sm) {
            sectionTitle("RUNTIME VOTES")
            if let graph = exocortex.lastGraphRagQuery?.value, !graph.runtimeVotes.isEmpty {
                ForEach(graph.runtimeVotes.prefix(12)) { vote in
                    GlassPanel(truth: vote.status == "available" ? .observed : .declared) {
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(vote.runtime.uppercased())
                                    .font(BeagleFont.caption2.font)
                                    .fontWeight(.semibold)
                                    .foregroundStyle(BeagleTheme.truthObserved)
                                Spacer()
                                Text(String(format: "%.2f", vote.score))
                                    .font(BeagleFont.caption2.font.monospaced())
                                    .foregroundStyle(BeagleTheme.textTertiary)
                            }
                            Text("\(vote.role) · \(vote.status)")
                                .font(BeagleFont.caption.font)
                                .foregroundStyle(BeagleTheme.textSecondary)
                            if !vote.notes.isEmpty {
                                Text(vote.notes.prefix(3).joined(separator: " · "))
                                    .font(BeagleFont.caption2.font)
                                    .foregroundStyle(BeagleTheme.textTertiary)
                                    .lineLimit(2)
                            }
                        }
                    }
                }
            } else {
                emptyRow("Run a Memory Lens query to see federated runtime votes.")
            }

            sectionTitle("MESH TRACE")
            let trace = exocortex.lastGraphRagQuery?.value?.meshTrace
                ?? exocortex.lastGraphRagQuery?.value?.retrievalTrace
                ?? []
            if trace.isEmpty {
                emptyRow("No retrieval trace observed yet.")
            } else {
                ForEach(trace.prefix(12)) { step in
                    Text("\(step.stage) · \(step.backend) · \(step.status) · \(step.items) items · \(String(format: "%.1f", step.latencyMs))ms")
                        .font(BeagleFont.caption2.font)
                        .foregroundStyle(BeagleTheme.textTertiary)
                        .lineLimit(2)
                }
            }
        }
    }

    private var contextTab: some View {
        VStack(alignment: .leading, spacing: BeagleSpacing.sm) {
            sectionTitle("ADAPTIVE CONTEXT")
            if let graph = exocortex.lastGraphRagQuery?.value {
                GlassPanel(truth: graph.contextPackId == nil ? .declared : .observed) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("CONTEXT PACK")
                            .font(BeagleFont.caption2.font)
                            .fontWeight(.semibold)
                            .foregroundStyle(BeagleTheme.truthObserved)
                        Text(graph.contextPackId ?? "context pack pending")
                            .font(BeagleFont.caption.font.monospaced())
                            .foregroundStyle(BeagleTheme.textSecondary)
                            .lineLimit(2)
                        Text("\(graph.policyVersion ?? "policy unknown") · \(graph.contextFormat ?? "format pending")")
                            .font(BeagleFont.caption2.font)
                            .foregroundStyle(BeagleTheme.textTertiary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                sectionTitle("WHY THIS MEMORY")
                if !graph.subqueries.isEmpty {
                    ForEach(Array(graph.subqueries.prefix(4).enumerated()), id: \.offset) { _, subquery in
                        Text(subquery)
                            .font(BeagleFont.caption.font)
                            .foregroundStyle(BeagleTheme.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                } else {
                    emptyRow("No subqueries recorded yet.")
                }

                sectionTitle("POLICY")
                Text("DreamCycle \(graph.dreamcycleStatus ?? "manual")")
                    .font(BeagleFont.caption.font)
                    .foregroundStyle(BeagleTheme.textSecondary)
                if let policyGate = graph.policyGate {
                    Text(String(describing: policyGate))
                        .font(BeagleFont.caption2.font)
                        .foregroundStyle(BeagleTheme.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if let leak = graph.restrictedLeakCheck {
                    Text(String(describing: leak))
                        .font(BeagleFont.caption2.font)
                        .foregroundStyle(BeagleTheme.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            } else if let trust = exocortex.home.value?.trustContext {
                emptyRow("Compiler \(trust.contextCompilerStatus ?? "shadow") · policy \(trust.memoryPolicyStatus ?? "observe") · DreamCycle \(trust.dreamcycleStatus ?? "manual-ready")")
                if let paper = trust.sounioPaperRunStatus {
                    emptyRow("Sounio PaperRun \(paper)")
                }
                if let pending = trust.sounioPendingApproval {
                    emptyRow("Approval pending · \(pending)")
                }
                if let pack = trust.latestContextPackId {
                    emptyRow("Latest ContextPack \(pack)")
                }
            } else {
                emptyRow("Run a Memory Lens query to see ContextPack, policy gate and DreamCycle status.")
            }
        }
    }

    private var semanticTraceTab: some View {
        VStack(alignment: .leading, spacing: BeagleSpacing.sm) {
            sectionTitle("SEMANTIC TRACE")
            if let graph = exocortex.lastGraphRagQuery?.value {
                GlassPanel(truth: graph.runtimeUsed?.contains("fallback") == true ? .declared : .observed) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text((graph.runtimeUsed ?? graph.mode ?? "unknown").uppercased())
                            .font(BeagleFont.caption2.font)
                            .fontWeight(.semibold)
                            .foregroundStyle(BeagleTheme.truthObserved)
                        if !graph.fallbackChain.isEmpty {
                            Text(graph.fallbackChain.joined(separator: " -> "))
                                .font(BeagleFont.caption.font)
                                .foregroundStyle(BeagleTheme.textSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        if let gate = graph.truthsetGateStatus {
                            let gateLabel = gate.confirmedPassing ? "confirmed" : (gate.provisionalHotPath ? "provisional" : "shadow")
                            Text("Portfolio gate \(gateLabel) · \(gate.portfolioTruthsetId ?? gate.truthsetId ?? "truthset pending")")
                                .font(BeagleFont.caption2.font)
                                .foregroundStyle(BeagleTheme.textTertiary)
                                .lineLimit(2)
                        }
                    }
                }
                ForEach(graph.semanticTrace.prefix(10)) { step in
                    GlassPanel(truth: step.status == "ready" || step.status == "ok" ? .observed : .declared) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(step.stage.uppercased())
                                .font(BeagleFont.caption2.font)
                                .fontWeight(.semibold)
                                .foregroundStyle(BeagleTheme.textTertiary)
                            Text("\(step.backend) · \(step.status) · \(step.items) items")
                                .font(BeagleFont.caption.font)
                                .foregroundStyle(BeagleTheme.textSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                            if !step.notes.isEmpty {
                                Text(step.notes.prefix(3).joined(separator: " · "))
                                    .font(BeagleFont.caption2.font)
                                    .foregroundStyle(BeagleTheme.textTertiary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                }
                if !graph.maxsimScores.isEmpty {
                    sectionTitle("MAXSIM")
                    ForEach(Array(graph.maxsimScores.prefix(5).enumerated()), id: \.offset) { _, score in
                        Text(String(describing: score))
                            .font(BeagleFont.caption2.font)
                            .foregroundStyle(BeagleTheme.textTertiary)
                            .lineLimit(3)
                    }
                }
                if !graph.rerankerScores.isEmpty {
                    sectionTitle("RERANK")
                    ForEach(Array(graph.rerankerScores.prefix(5).enumerated()), id: \.offset) { _, score in
                        Text(String(describing: score))
                            .font(BeagleFont.caption2.font)
                            .foregroundStyle(BeagleTheme.textTertiary)
                            .lineLimit(3)
                    }
                }
                if let expansion = graph.graphExpansion {
                    sectionTitle("GRAPH EXPANSION")
                    Text(String(describing: expansion))
                        .font(BeagleFont.caption2.font)
                        .foregroundStyle(BeagleTheme.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            } else {
                emptyRow("Run a Memory Lens query to see MaxSim/late-interaction, graph expansion, rerank, provenance, and fallback trace.")
            }
        }
    }

    private var queryBar: some View {
        HStack(spacing: BeagleSpacing.sm) {
            TextField("Search decisions, hypotheses, evidence...", text: $query)
                .textFieldStyle(.plain)
                .font(BeagleFont.callout.font)
                .padding(.horizontal, BeagleSpacing.sm)
                .padding(.vertical, BeagleSpacing.xs)
                .background(
                    RoundedRectangle(cornerRadius: BeagleRadius.sm)
                        .fill(BeagleTheme.surface1.opacity(0.72))
                )

            Button {
                Task { await runQuery() }
            } label: {
                Image(systemName: isSearching ? "hourglass" : "magnifyingglass")
                    .font(.system(size: 14, weight: .semibold))
            }
            .buttonStyle(.borderedProminent)
            .disabled(query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSearching)
        }
    }

    private var recentGraph: some View {
        VStack(alignment: .leading, spacing: BeagleSpacing.sm) {
            sectionTitle("RECENT PROJECTED ATOMS")

            let atoms = (exocortex.recentGraph?.value?.atoms ?? []).filter(isDisplayableAtom)
            if atoms.isEmpty {
                emptyRow("No projected atoms yet. Capture or import context to wake the graph.")
            } else {
                ForEach(atoms.prefix(12)) { atom in
                    memoryAtomRow(atom)
                }
            }
        }
    }

    private func graphResult(_ result: GraphRagQueryResponse) -> some View {
        VStack(alignment: .leading, spacing: BeagleSpacing.sm) {
            Text("QUERY RESULT")
                .font(BeagleFont.caption2.font)
                .fontWeight(.semibold)
                .foregroundStyle(BeagleTheme.textTertiary)
            Text(result.summary)
                .font(BeagleFont.callout.font)
                .foregroundStyle(BeagleTheme.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
            if let runtime = result.runtimeUsed ?? result.mode {
                Text("\(runtime) · \(result.fallbackChain.joined(separator: " -> "))")
                    .font(BeagleFont.caption2.font)
                    .foregroundStyle(BeagleTheme.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let pack = result.contextPackId {
                Text("context \(pack) · \(result.policyVersion ?? "policy unknown") · DreamCycle \(result.dreamcycleStatus ?? "manual")")
                    .font(BeagleFont.caption2.font.monospaced())
                    .foregroundStyle(BeagleTheme.textTertiary)
                    .lineLimit(2)
            }
            ForEach(result.evidence.filter(isDisplayableEvidence).prefix(6), id: \.atomId) { evidence in
                GlassPanel(truth: .observed) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(evidence.atomType.uppercased())
                            .font(BeagleFont.caption2.font)
                            .fontWeight(.semibold)
                            .foregroundStyle(BeagleTheme.truthObserved)
                        Text(evidence.text)
                            .font(BeagleFont.caption.font)
                            .foregroundStyle(BeagleTheme.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                        Text("score \(String(format: "%.2f", evidence.score)) · \(evidence.episodeId)")
                            .font(BeagleFont.caption2.font)
                            .foregroundStyle(BeagleTheme.textTertiary)
                    }
                }
            }
            if let graph = result.evidenceGraph {
                Text("evidence graph · \(graph.nodes.count) nodes · \(graph.edges.count) edges · \(graph.merkleRoot)")
                    .font(BeagleFont.caption2.font.monospaced())
                    .foregroundStyle(BeagleTheme.textTertiary)
                    .lineLimit(2)
            }
            if let trace = result.retrievalTrace, !trace.isEmpty {
                ForEach(trace.prefix(4)) { step in
                    Text("\(step.stage) · \(step.backend) · \(step.status) · \(step.items)")
                        .font(BeagleFont.caption2.font)
                        .foregroundStyle(BeagleTheme.textTertiary)
                        .lineLimit(1)
                }
            }
            if !result.semanticTrace.isEmpty {
                ForEach(result.semanticTrace.prefix(3)) { step in
                    Text("\(step.stage) · \(step.backend) · \(step.status)")
                        .font(BeagleFont.caption2.font)
                        .foregroundStyle(BeagleTheme.textTertiary)
                        .lineLimit(1)
                }
            }
            if !result.runtimeVotes.isEmpty {
                Text("runtime votes · \(result.runtimeVotes.prefix(4).map { "\($0.runtime):\($0.status)" }.joined(separator: " · "))")
                    .font(BeagleFont.caption2.font)
                    .foregroundStyle(BeagleTheme.textTertiary)
                    .lineLimit(2)
            }
            if !result.candidateRefs.isEmpty {
                Text("candidates · \(result.candidateRefs.prefix(4).joined(separator: " · "))")
                    .font(BeagleFont.caption2.font.monospaced())
                    .foregroundStyle(BeagleTheme.textTertiary)
                    .lineLimit(2)
            }
        }
    }

    private func memoryAtomRow(_ atom: MemoryAtom) -> some View {
        GlassPanel(truth: .remembered) {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(atom.atomType.uppercased())
                        .font(BeagleFont.caption2.font)
                        .fontWeight(.semibold)
                        .foregroundStyle(BeagleTheme.truthObserved)
                    Spacer()
                    Text(atom.privacyClass)
                        .font(BeagleFont.caption2.font)
                        .foregroundStyle(BeagleTheme.textTertiary)
                }
                Text(atom.text)
                    .font(BeagleFont.caption.font)
                    .foregroundStyle(BeagleTheme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                Text(atom.tags.prefix(4).joined(separator: " · "))
                    .font(BeagleFont.caption2.font)
                    .foregroundStyle(BeagleTheme.textTertiary)
                    .lineLimit(1)
            }
        }
    }

    private func sounioMomentRow(_ moment: SounioMoment) -> some View {
        GlassPanel(truth: moment.reviewState == "approved" ? .observed : .declared) {
            VStack(alignment: .leading, spacing: BeagleSpacing.xs) {
                HStack(alignment: .firstTextBaseline) {
                    Text(moment.momentType.uppercased())
                        .font(BeagleFont.caption2.font)
                        .fontWeight(.semibold)
                        .foregroundStyle(BeagleTheme.truthDeclared)
                    Spacer()
                    Text(moment.reviewState)
                        .font(BeagleFont.caption2.font.monospaced())
                        .foregroundStyle(BeagleTheme.textTertiary)
                }
                Text(moment.summary)
                    .font(BeagleFont.caption.font)
                    .foregroundStyle(BeagleTheme.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                Text("\(moment.sourcePlatform) · \(moment.sourceSurface) · \(moment.updatedAt)")
                    .font(BeagleFont.caption2.font)
                    .foregroundStyle(BeagleTheme.textTertiary)
                    .lineLimit(1)
                if let next = moment.nextAction, !next.isEmpty {
                    Text("next · \(next)")
                        .font(BeagleFont.caption2.font)
                        .foregroundStyle(BeagleTheme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if moment.reviewState != "approved" && moment.privacyClass.lowercased() != "restricted" {
                    HStack(spacing: BeagleSpacing.xs) {
                        Button {
                            Task {
                                await exocortex.reviewSounioMoment(
                                    moment,
                                    decision: "approved",
                                    rationale: "Approved from Apple Memory Lens Sounio Workday."
                                )
                            }
                        } label: {
                            Label("Approve", systemImage: "checkmark.circle")
                        }
                        Button {
                            Task {
                                await exocortex.reviewSounioMoment(
                                    moment,
                                    decision: "mark_contest",
                                    rationale: "Marked contest from Apple Memory Lens Sounio Workday."
                                )
                            }
                        } label: {
                            Label("Contest", systemImage: "exclamationmark.triangle")
                        }
                    }
                    .font(BeagleFont.caption2.font)
                    .buttonStyle(.borderless)
                    .foregroundStyle(BeagleTheme.textSecondary)
                }
            }
        }
    }

    private func lensTextRow(_ icon: String, _ title: String, _ text: String, tint: Color) -> some View {
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
                Text(text)
                    .font(BeagleFont.caption.font)
                    .foregroundStyle(BeagleTheme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.vertical, 2)
    }

    private func emptyRow(_ message: String) -> some View {
        Text(message)
            .font(BeagleFont.caption.font)
            .foregroundStyle(BeagleTheme.textTertiary)
            .padding(.vertical, BeagleSpacing.sm)
    }

    private func sectionTitle(_ text: String) -> some View {
        Text(text)
            .font(BeagleFont.caption2.font)
            .fontWeight(.semibold)
            .foregroundStyle(BeagleTheme.textTertiary)
    }

    private func relationRow(_ relation: MemoryRelation) -> some View {
        GlassPanel(truth: .remembered) {
            VStack(alignment: .leading, spacing: 4) {
                Text(relation.predicate.uppercased())
                    .font(BeagleFont.caption2.font)
                    .fontWeight(.semibold)
                    .foregroundStyle(BeagleTheme.truthDeclared)
                Text(relation.subject)
                    .font(BeagleFont.caption.font)
                    .foregroundStyle(BeagleTheme.textPrimary)
                    .lineLimit(2)
                Text(relation.object)
                    .font(BeagleFont.caption.font)
                    .foregroundStyle(BeagleTheme.textSecondary)
                    .lineLimit(2)
                Text("confidence \(String(format: "%.2f", relation.confidence))")
                    .font(BeagleFont.caption2.font)
                    .foregroundStyle(BeagleTheme.textTertiary)
            }
        }
    }

    private func statusLine(_ status: MemoryProjectionStatus?) -> String {
        guard let status else { return "Projection status unavailable." }
        return "\(status.status) · \(status.episodeCount) episodes · \(status.atomCount) atoms · \(status.retrievalMode)"
    }

    private var latestWorkMemoryLine: String? {
        if let latest = exocortex.home.value?.trustContext?.latestAgentWrite?.trimmingCharacters(in: .whitespacesAndNewlines),
           !latest.isEmpty {
            return latest
        }
        if let latest = exocortex.home.value?.agentContext?.lastAgentWrite?.trimmingCharacters(in: .whitespacesAndNewlines),
           !latest.isEmpty {
            return latest
        }
        if let atom = (exocortex.recentGraph?.value?.atoms ?? []).first(where: isWorkMemoryAtom) {
            return "\(atom.atomType) · \(atom.text)"
        }
        return nil
    }

    private var latestGrokImportLine: String? {
        if let signal = exocortex.home.value?.memorySignals.first(where: { $0.localizedCaseInsensitiveContains("grok") }) {
            return signal
        }
        if let episode = (exocortex.recentGraph?.value?.episodes ?? []).first(where: isGrokEpisode) {
            return "\(episode.title ?? episode.sourceRef) · \(episode.occurredAt ?? episode.createdAt)"
        }
        if let atom = (exocortex.recentGraph?.value?.atoms ?? []).first(where: isGrokAtom) {
            return "\(atom.atomType) · \(atom.text)"
        }
        return nil
    }

    private func lensContextLine(_ text: String) -> some View {
        Text(text)
            .font(BeagleFont.caption.font)
            .foregroundStyle(BeagleTheme.textSecondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func isWorkMemoryAtom(_ atom: MemoryAtom) -> Bool {
        guard isDisplayableAtom(atom) else { return false }
        let haystack = (atom.tags + [atom.atomType, atom.text]).joined(separator: " ").lowercased()
        return haystack.contains("work-memory")
            || haystack.contains("codex")
            || haystack.contains("claude-code")
            || haystack.contains("agent:")
    }

    private func isGrokEpisode(_ episode: MemoryEpisode) -> Bool {
        guard isDisplayableEpisode(episode) else { return false }
        let haystack = (episode.tags + [
            episode.source,
            episode.sourcePlatform ?? "",
            episode.title ?? "",
            episode.sourceRef
        ]).joined(separator: " ").lowercased()
        return haystack.contains("grok")
    }

    private func isGrokAtom(_ atom: MemoryAtom) -> Bool {
        guard isDisplayableAtom(atom) else { return false }
        let haystack = (atom.tags + [atom.atomType, atom.text]).joined(separator: " ").lowercased()
        return haystack.contains("grok")
    }

    private func isDisplayableAtom(_ atom: MemoryAtom) -> Bool {
        atom.privacyClass.lowercased() != "restricted"
            && !containsRestrictedMarker(atom.text)
            && !atom.sourceRefs.contains(where: containsRestrictedMarker)
    }

    private func isDisplayableEpisode(_ episode: MemoryEpisode) -> Bool {
        episode.privacyClass.lowercased() != "restricted"
            && !containsRestrictedMarker(episode.title ?? "")
            && !containsRestrictedMarker(episode.sourceRef)
    }

    private func isDisplayableEvidence(_ evidence: GraphRagEvidence) -> Bool {
        !containsRestrictedMarker(evidence.text)
            && !evidence.sourceRefs.contains(where: containsRestrictedMarker)
    }

    private func containsRestrictedMarker(_ text: String) -> Bool {
        text.localizedCaseInsensitiveContains("restricted")
            || text.localizedCaseInsensitiveContains("client_secret")
            || text.localizedCaseInsensitiveContains("api_key")
    }

    private func runPreset(_ preset: MemoryLensPreset) async {
        query = preset.query
        await runQuery(preset.query)
    }

    private func runQuery(_ override: String? = nil) async {
        let candidate = override ?? query
        let trimmed = candidate.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        isSearching = true
        _ = await exocortex.queryGraphMemory(trimmed, scope: activeProjectSlug, maxItems: 8, mode: "hypermemory_multivector")
        isSearching = false
    }
}

private struct LivingMemoryReportHeader: View {
    let report: MemoryLensReport
    let onProve: () -> Void

    private var truthMode: TruthMode {
        report.degradedReason == nil ? .observed : .declared
    }

    var body: some View {
        GlassPanel(truth: truthMode) {
            VStack(alignment: .leading, spacing: BeagleSpacing.sm) {
                HStack(alignment: .top, spacing: BeagleSpacing.sm) {
                    VStack(alignment: .leading, spacing: BeagleSpacing.xxs) {
                        Text("LIVING MEMORY REPORT")
                            .font(BeagleFont.caption2.font)
                            .fontWeight(.semibold)
                            .foregroundStyle(BeagleTheme.textTertiary)
                        Text(report.headline)
                            .font(BeagleFont.title3.font)
                            .fontWeight(.semibold)
                            .foregroundStyle(BeagleTheme.textPrimary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: BeagleSpacing.sm)
                    TruthBadge(truthMode, compact: true)
                }

                Text(report.summary)
                    .font(BeagleFont.callout.font)
                    .foregroundStyle(BeagleTheme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)

                if !report.changedSignals.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(report.changedSignals.prefix(3), id: \.self) { signal in
                            HStack(alignment: .top, spacing: BeagleSpacing.xs) {
                                Image(systemName: "sparkle.magnifyingglass")
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundStyle(BeagleTheme.truthObserved)
                                    .frame(width: 16)
                                Text(signal)
                                    .font(BeagleFont.caption.font)
                                    .foregroundStyle(BeagleTheme.textSecondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                }

                HStack(spacing: BeagleSpacing.sm) {
                    Button {
                        onProve()
                    } label: {
                        Label("Provar", systemImage: "checkmark.shield")
                            .font(BeagleFont.caption.font)
                            .fontWeight(.semibold)
                    }
                    .buttonStyle(.bordered)

                    Text("\(report.evidenceFrontier.count) evidências · confiança \(String(format: "%.2f", report.confidence))")
                        .font(BeagleFont.caption2.font)
                        .foregroundStyle(BeagleTheme.textTertiary)
                        .lineLimit(1)
                }
            }
        }
    }
}

private struct SourceConfidenceStrip: View {
    let report: MemoryLensReport

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: BeagleSpacing.xs) {
                ForEach(report.sourceConfidenceBadges, id: \.self) { badge in
                    Text(badge)
                        .font(BeagleFont.caption2.font)
                        .fontWeight(.medium)
                        .foregroundStyle(BeagleTheme.textSecondary)
                        .padding(.horizontal, BeagleSpacing.xs)
                        .padding(.vertical, 5)
                        .background(
                            Capsule()
                                .fill(BeagleTheme.surface1.opacity(0.72))
                        )
                }
            }
        }
        .accessibilityLabel("Source and confidence badges")
    }
}

private struct MemoryQuestionDock: View {
    @Binding var query: String
    let isSearching: Bool
    let onSubmit: () -> Void

    var body: some View {
        HStack(spacing: BeagleSpacing.sm) {
            Image(systemName: "text.magnifyingglass")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(BeagleTheme.textTertiary)

            TextField("Perguntar à memória viva...", text: $query)
                .textFieldStyle(.plain)
                .font(BeagleFont.callout.font)
                .submitLabel(.search)
                .onSubmit(onSubmit)

            Button(action: onSubmit) {
                Image(systemName: isSearching ? "hourglass" : "arrow.up.circle.fill")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? BeagleTheme.textTertiary : BeagleTheme.truthObserved)
            }
            .buttonStyle(.plain)
            .disabled(query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSearching)
        }
        .padding(.horizontal, BeagleSpacing.sm)
        .padding(.vertical, BeagleSpacing.xs)
        .background(
            RoundedRectangle(cornerRadius: BeagleRadius.md, style: .continuous)
                .fill(BeagleTheme.surface1.opacity(0.82))
                .overlay(
                    RoundedRectangle(cornerRadius: BeagleRadius.md, style: .continuous)
                        .stroke(BeagleTheme.truthObserved.opacity(0.18), lineWidth: 1)
                )
        )
        .accessibilityLabel("Memory Lens question")
    }
}

private struct LensPresetRail: View {
    let presets: [MemoryLensPreset]
    let onSelect: (MemoryLensPreset) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: BeagleSpacing.sm) {
                ForEach(presets) { preset in
                    Button {
                        onSelect(preset)
                    } label: {
                        VStack(alignment: .leading, spacing: 5) {
                            HStack(spacing: BeagleSpacing.xs) {
                                Image(systemName: preset.systemImage)
                                    .font(.system(size: 13, weight: .semibold))
                                Text(preset.title)
                                    .font(BeagleFont.caption.font)
                                    .fontWeight(.semibold)
                                    .lineLimit(1)
                            }
                            Text(preset.detail)
                                .font(BeagleFont.caption2.font)
                                .foregroundStyle(BeagleTheme.textTertiary)
                                .lineLimit(2)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .foregroundStyle(BeagleTheme.textSecondary)
                        .frame(width: 176, alignment: .leading)
                        .padding(BeagleSpacing.sm)
                        .background(
                            RoundedRectangle(cornerRadius: BeagleRadius.sm, style: .continuous)
                                .fill(BeagleTheme.surface1.opacity(0.68))
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .accessibilityLabel("Memory Lens presets")
    }
}

private struct EvidenceFrontier: View {
    let report: MemoryLensReport
    let onProve: (ProofSheetModel) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: BeagleSpacing.sm) {
            HStack {
                Text("FRONTEIRA DE EVIDÊNCIA")
                    .font(BeagleFont.caption2.font)
                    .fontWeight(.semibold)
                    .foregroundStyle(BeagleTheme.textTertiary)
                Spacer()
                if report.restrictedContentFiltered {
                    Label("restricted filtrado", systemImage: "lock.shield")
                        .font(BeagleFont.caption2.font)
                        .foregroundStyle(BeagleTheme.textTertiary)
                }
            }

            if report.evidenceFrontier.isEmpty {
                GlassPanel(truth: .declared) {
                    Text("Ainda não há evidência projetada para exibir. Use um preset ou capture uma nova intenção para acordar a lente.")
                        .font(BeagleFont.caption.font)
                        .foregroundStyle(BeagleTheme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            } else {
                ForEach(report.evidenceFrontier.prefix(4)) { item in
                    evidenceRow(item)
                }
            }
        }
    }

    private func evidenceRow(_ item: EvidenceFrontierItem) -> some View {
        let truth = TruthMode(rawValue: item.truthMode) ?? .remembered
        return GlassPanel(truth: truth) {
            VStack(alignment: .leading, spacing: BeagleSpacing.xs) {
                HStack(alignment: .firstTextBaseline) {
                    Text(item.title.uppercased())
                        .font(BeagleFont.caption2.font)
                        .fontWeight(.semibold)
                        .foregroundStyle(BeagleTheme.color(for: truth))
                    Spacer()
                    Text(String(format: "%.2f", item.score))
                        .font(BeagleFont.caption2.font.monospaced())
                        .foregroundStyle(BeagleTheme.textTertiary)
                }
                Text(item.detail)
                    .font(BeagleFont.caption.font)
                    .foregroundStyle(BeagleTheme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: BeagleSpacing.xs) {
                    Text(item.sourceLabel)
                        .font(BeagleFont.caption2.font.monospaced())
                        .foregroundStyle(BeagleTheme.textTertiary)
                        .lineLimit(1)
                    Spacer()
                    Button {
                        onProve(item.proof)
                    } label: {
                        Label("Provar", systemImage: "doc.text.magnifyingglass")
                            .font(BeagleFont.caption2.font)
                    }
                    .buttonStyle(.borderless)
                }
            }
        }
        .onLongPressGesture {
            onProve(item.proof)
        }
    }
}

private struct ProofSheet: View {
    let model: ProofSheetModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: BeagleSpacing.md) {
                    GlassPanel(truth: .observed) {
                        VStack(alignment: .leading, spacing: BeagleSpacing.xs) {
                            Text("PROOF PACK")
                                .font(BeagleFont.caption2.font)
                                .fontWeight(.semibold)
                                .foregroundStyle(BeagleTheme.textTertiary)
                            Text(model.title)
                                .font(BeagleFont.title3.font)
                                .fontWeight(.semibold)
                                .foregroundStyle(BeagleTheme.textPrimary)
                            Text(model.summary)
                                .font(BeagleFont.callout.font)
                                .foregroundStyle(BeagleTheme.textSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }

                    proofSection("SOURCE REFS", model.sourceRefs)
                    proofSection("PROVENANCE", model.provenanceLines)
                    proofSection("TRACE", model.traceLines)

                    Text("\(model.runtime ?? "runtime unknown") · confidence \(String(format: "%.2f", model.confidence)) · \(model.restrictedLeakCheck)")
                        .font(BeagleFont.caption2.font)
                        .foregroundStyle(BeagleTheme.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(BeagleSpacing.lg)
            }
            .background(BeagleTheme.surface0.ignoresSafeArea())
            .navigationTitle("Provar")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private func proofSection(_ title: String, _ lines: [String]) -> some View {
        VStack(alignment: .leading, spacing: BeagleSpacing.xs) {
            Text(title)
                .font(BeagleFont.caption2.font)
                .fontWeight(.semibold)
                .foregroundStyle(BeagleTheme.textTertiary)
            if lines.isEmpty {
                Text("No entries recorded.")
                    .font(BeagleFont.caption.font)
                    .foregroundStyle(BeagleTheme.textTertiary)
            } else {
                ForEach(lines, id: \.self) { line in
                    Text(line)
                        .font(BeagleFont.caption.font.monospaced())
                        .foregroundStyle(BeagleTheme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }
}

// MARK: - Simplified background

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
