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
                            async let graphRefresh: Void = exocortex.refreshRecentGraph(limit: 12)
                            async let worldsRefresh: Void = exocortex.refreshRecentWorlds(limit: 12)
                            async let bodyRefresh: Void = physio.refresh()
                            _ = await (homeRefresh, projectionRefresh, graphStatusRefresh, graphRefresh, worldsRefresh, bodyRefresh)
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
                    Text("GraphRAG++ memory")
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
        return "\(trust.mcpStatus) · \(scopeCount) scopes · \(hashLabel) · destructive locked"
    }

    private var memoryProjectionLine: String {
        let status = exocortex.recentGraph?.value?.status
            ?? exocortex.projectionStatus?.value
            ?? home.trustContext?.memoryProjectionStatus
        guard let status else {
            return "Projection not observed yet; tap to inspect cluster memory."
        }
        let runtime = home.trustContext?.graphRuntime ?? exocortex.graphStatus?.value?.graphRuntime ?? "jsonl"
        let mode = home.trustContext?.retrievalMode ?? exocortex.graphStatus?.value?.retrievalMode ?? status.retrievalMode
        let degrade = home.trustContext?.graphDegradedReason ?? exocortex.graphStatus?.value?.degradedReason ?? status.degradedReason
        let hash = home.trustContext?.lastWorldHash.map { " · \($0.prefix(18))" } ?? ""
        return "\(runtime) · \(mode) · \(status.episodeCount) episodes · \(status.atomCount) atoms · \(degrade)\(hash)"
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
                }
            }
            .padding(BeagleSpacing.lg)
        }
        .navigationTitle("Memory Lens")
        .background(BeagleTheme.surface0.ignoresSafeArea())
        .task {
            async let graphStatus: Void = exocortex.refreshGraphStatus()
            async let recentGraph: Void = exocortex.refreshRecentGraph(limit: 16)
            async let worlds: Void = exocortex.refreshRecentWorlds(limit: 16)
            _ = await (graphStatus, recentGraph, worlds)
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
        .pickerStyle(.segmented)
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
            let relations = (exocortex.recentGraph?.value?.relations ?? []).filter {
                $0.predicate.lowercased().contains("contradict")
                    || $0.predicate.lowercased().contains("conflict")
                    || $0.predicate.lowercased().contains("tension")
            }
            if relations.isEmpty {
                emptyRow("No explicit contradiction relations observed in the recent graph.")
            } else {
                ForEach(relations.indices, id: \.self) { index in
                    relationRow(relations[index])
                }
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

    private func runQuery() async {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        isSearching = true
        _ = await exocortex.queryGraphMemory(trimmed, scope: activeProjectSlug, maxItems: 8, mode: "graphsearch-lite")
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
