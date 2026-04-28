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
    @State private var showSettings = false
    @State private var showCognitiveState = false
    @State private var showProjectPicker = false
    @State private var showMemoryLens = false
    @State private var metacogNudge: MetacognitiveObservation?
    @State private var serendipityProvocation: SerendipityProvocation?

    var body: some View {
        ZStack {
            // Living background
            ShellPresenceGradient(
                presence: shellPresence,
                cognitivePosture: physio.cognitivePosture
            )

            VStack(spacing: 0) {
                // Header bar: project context + settings
                headerBar

                // Metacognitive nudge (stagnation, flow, fatigue)
                if let nudge = metacogNudge {
                    metacogNudgeView(nudge)
                        .transition(.move(edge: .top).combined(with: .opacity))
                }

                // Serendipity provocation
                if let provocation = serendipityProvocation {
                    serendipityChip(provocation)
                        .transition(.move(edge: .top).combined(with: .opacity))
                }

                exocortexHomeCard
                    .padding(.horizontal, BeagleSpacing.lg)
                    .padding(.bottom, BeagleSpacing.sm)

                // The conversation — this is the whole point
                ConversationView(conversation: conversation)
            }

            // Error banner if backend unreachable
            if let error = bootError {
                VStack {
                    errorBanner(error)
                        .padding(.horizontal, BeagleSpacing.lg)
                        .padding(.top, 60) // below header
                    Spacer()
                }
            }
        }
        .task {
            wireConversation()
            exocortex.modelContext = modelContext
            exocortex.loadCachedHome()
            async let homeRefresh: Void = exocortex.refresh(activeProjectSlug: activeSlug, platform: platformName)
            async let projectionRefresh: Void = exocortex.refreshProjectionStatus()
            async let graphStatusRefresh: Void = exocortex.refreshGraphStatus()
            async let graphRefresh: Void = exocortex.refreshRecentGraph(limit: 12)
            async let worldsRefresh: Void = exocortex.refreshRecentWorlds(limit: 12)
            async let bodyRefresh: Void = physio.refresh()
            _ = await (homeRefresh, projectionRefresh, graphStatusRefresh, graphRefresh, worldsRefresh, bodyRefresh)
        }
        .onChange(of: conversation.messages.count) {
            runMetacognitiveCheck()
        }
        .sheet(isPresented: $showSettings) {
            NavigationStack {
                ModelSettingsView()
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Done") { showSettings = false }
                        }
                    }
            }
        }
        .sheet(isPresented: $showCognitiveState) {
            NavigationStack {
                CognitiveStateView()
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Done") { showCognitiveState = false }
                        }
                    }
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
        .sheet(isPresented: $showMemoryLens) {
            NavigationStack {
                MemoryLensSheet(exocortex: exocortex, activeProjectSlug: activeSlug)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Done") { showMemoryLens = false }
                        }
                    }
            }
        }
    }

    // MARK: - Exocortex Home

    private var exocortexHomeCard: some View {
        GlassPanel(elevation: .floating, truth: exocortex.home.mode) {
            VStack(alignment: .leading, spacing: BeagleSpacing.sm) {
                HStack(alignment: .center, spacing: BeagleSpacing.sm) {
                    Image(systemName: "brain.head.profile")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(BeagleTheme.color(for: exocortex.home.mode))

                    VStack(alignment: .leading, spacing: 2) {
                        Text("EXOCORTEX HOME")
                            .font(BeagleFont.caption2.font)
                            .fontWeight(.semibold)
                            .foregroundStyle(BeagleTheme.textTertiary)
                        Text(home.currentSelf.label)
                            .font(BeagleFont.footnote.font)
                            .fontWeight(.semibold)
                            .foregroundStyle(BeagleTheme.textPrimary)
                            .lineLimit(1)
                    }

                    Spacer(minLength: BeagleSpacing.sm)

                    TruthBadge(exocortex.home.mode, compact: true)

                    Button {
                        Task {
                            async let homeRefresh: Void = exocortex.refresh(activeProjectSlug: activeSlug, platform: platformName)
                            async let projectionRefresh: Void = exocortex.refreshProjectionStatus()
                            async let graphStatusRefresh: Void = exocortex.refreshGraphStatus()
                            async let benchmarkRefresh: Void = exocortex.refreshBenchmarkStatus()
                            async let graphRefresh: Void = exocortex.refreshRecentGraph(limit: 12)
                            async let worldsRefresh: Void = exocortex.refreshRecentWorlds(limit: 12)
                            async let bodyRefresh: Void = physio.refresh()
                            _ = await (homeRefresh, projectionRefresh, graphStatusRefresh, benchmarkRefresh, graphRefresh, worldsRefresh, bodyRefresh)
                        }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 12, weight: .semibold))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(BeagleTheme.textSecondary)
                    .help("Refresh Exocortex Home")
                    .disabled(exocortex.isLoading)
                }

                hardwareStrip

                Text(home.todayBrief)
                    .font(BeagleFont.footnote.font)
                    .foregroundStyle(BeagleTheme.textSecondary)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)

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
            showMemoryLens = true
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

    private var home: ExocortexHomeSnapshot {
        exocortex.home.value ?? .bootstrap
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

    // MARK: - Header bar (project + readiness + settings)

    private var headerBar: some View {
        HStack(spacing: BeagleSpacing.sm) {
            // Project context
            Button { showProjectPicker = true } label: {
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
            Button { showCognitiveState = true } label: {
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
            Button { showSettings = true } label: {
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
        return "\(trust.mcpStatus) · \(scopeCount) scopes · \(hashLabel)\(semantic)\(hotPath)\(provisional)\(mesh)\(governor)\(pending)\(contradictions)\(quorum)\(benchGate)\(capture) · destructive locked"
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
        let haystack = (atom.tags + [atom.atomType, atom.text]).joined(separator: " ").lowercased()
        return haystack.contains("work-memory")
            || haystack.contains("codex")
            || haystack.contains("claude-code")
            || haystack.contains("agent:")
    }

    private func isGrokEpisode(_ episode: MemoryEpisode) -> Bool {
        let haystack = (episode.tags + [
            episode.source,
            episode.sourcePlatform ?? "",
            episode.title ?? "",
            episode.sourceRef
        ]).joined(separator: " ").lowercased()
        return haystack.contains("grok")
    }

    private func isGrokAtom(_ atom: MemoryAtom) -> Bool {
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

// MARK: - Memory Lens

private struct MemoryLensSheet: View {
    let exocortex: ExocortexStore
    let activeProjectSlug: String
    @State private var query = ""
    @State private var isSearching = false
    @State private var selectedTab: LensTab = .evidence

    private enum LensTab: String, CaseIterable, Identifiable {
        case evidence = "Evidence"
        case timeline = "Timeline"
        case worlds = "Worlds"
        case work = "Work"
        case contradictions = "Contradictions"
        case candidates = "Candidates"
        case truth = "Truth"
        case bench = "Bench"
        case semanticTrace = "Semantic"
        case runtimeTrace = "Runtime"

        var id: String { rawValue }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: BeagleSpacing.md) {
                header
                lensPicker
                switch selectedTab {
                case .evidence:
                    evidenceTab
                case .timeline:
                    timelineTab
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
                case .semanticTrace:
                    semanticTraceTab
                case .runtimeTrace:
                    runtimeTraceTab
                }
            }
            .padding(BeagleSpacing.lg)
        }
        .navigationTitle("Memory Lens")
        .background(BeagleTheme.surface0.ignoresSafeArea())
        .task {
            async let graphStatus: Void = exocortex.refreshGraphStatus()
            async let benchmark: Void = exocortex.refreshBenchmarkStatus()
            async let recentGraph: Void = exocortex.refreshRecentGraph(limit: 16)
            async let worlds: Void = exocortex.refreshRecentWorlds(limit: 16)
            async let candidates: Void = exocortex.refreshMemoryCandidates(limit: 20)
            async let governance: Void = exocortex.refreshMemoryGovernanceStatus()
            async let contradictions: Void = exocortex.refreshMemoryContradictions(limit: 20)
            if let truthsetId = exocortex.home.value?.trustContext?.truthsetId {
                async let truthset: Void = exocortex.refreshTruthSetStatus(id: truthsetId)
                _ = await (graphStatus, benchmark, recentGraph, worlds, candidates, governance, contradictions, truthset)
            } else {
                _ = await (graphStatus, benchmark, recentGraph, worlds, candidates, governance, contradictions)
            }
        }
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
                    Text("\(mesh)\(governor)\(triad)\(contradictions)\(bench)\(score)\(gate)\(capture)\(candidate)\(quorum)")
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
            let episodes = exocortex.recentGraph?.value?.episodes ?? []
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
                return haystack.contains("work-memory")
                    || haystack.contains("codex")
                    || haystack.contains("claude-code")
                    || haystack.contains("agent:")
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
            let candidates = exocortex.memoryCandidates?.value?.candidates ?? []
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

            let atoms = exocortex.recentGraph?.value?.atoms ?? []
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
            ForEach(result.evidence.prefix(6), id: \.atomId) { evidence in
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
        let haystack = (atom.tags + [atom.atomType, atom.text]).joined(separator: " ").lowercased()
        return haystack.contains("work-memory")
            || haystack.contains("codex")
            || haystack.contains("claude-code")
            || haystack.contains("agent:")
    }

    private func isGrokEpisode(_ episode: MemoryEpisode) -> Bool {
        let haystack = (episode.tags + [
            episode.source,
            episode.sourcePlatform ?? "",
            episode.title ?? "",
            episode.sourceRef
        ]).joined(separator: " ").lowercased()
        return haystack.contains("grok")
    }

    private func isGrokAtom(_ atom: MemoryAtom) -> Bool {
        let haystack = (atom.tags + [atom.atomType, atom.text]).joined(separator: " ").lowercased()
        return haystack.contains("grok")
    }

    private func runQuery() async {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        isSearching = true
        _ = await exocortex.queryGraphMemory(trimmed, scope: activeProjectSlug, maxItems: 8, mode: "hypermemory")
        isSearching = false
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
