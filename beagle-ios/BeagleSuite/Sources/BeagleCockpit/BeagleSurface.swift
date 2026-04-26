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
            async let bodyRefresh: Void = physio.refresh()
            _ = await (homeRefresh, bodyRefresh)
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
                            async let bodyRefresh: Void = physio.refresh()
                            _ = await (homeRefresh, bodyRefresh)
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
