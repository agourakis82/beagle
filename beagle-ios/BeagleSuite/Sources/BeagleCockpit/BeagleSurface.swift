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
import BeagleWorkbenchKit
#if canImport(UIKit)
import UIKit
#endif

struct BeagleSurface: View {
    @Environment(CatalogStore.self) var catalog
    @Environment(CognitiveStore.self) private var cognitive
    @Environment(PhysioStore.self) var physio
    @Environment(\.modelContext) var modelContext
    @Binding var bootError: String?

    @State var conversation = ConversationStore(preferLocal: false)
    @State var exocortex = ExocortexStore()
    @State var spaceWeather = SpaceWeatherStore()
    @State var activeSheet: SurfaceSheet? = nil
    @State private var metacogNudge: MetacognitiveObservation? = nil
    @State private var serendipityProvocation: SerendipityProvocation? = nil

    /// A deep link parked by `onOpenURL` — the path a Live Activity or lock-screen tap takes
    /// to land straight on the Frota.
    private let deepLink = DeepLinkRouter.shared

    init(bootError: Binding<String?>) {
        self._bootError = bootError
    }

    enum SurfaceSheet: String, Identifiable {
        case settings
        case cognitiveState
        case projectPicker
        case memoryLens
        case originObservatory
        case continuityExplanation
        case capture
        case agora   // the dedicated data screen (Fase 4) — body × sky × ambient series
        case memory  // "o que eu lembro de ti" — warm biography read, NOT the memoryLens debug console
        case dreamInsights  // overnight Dream Synthesis reader — only surfaced consumer of DreamSynthesisEngine
        case work  // agent deck (WorkView) — was iPad-sidebar-only until this session's audit
        case dailySynthesis  // Síntese Matinal Diária (GPT-6.2 Astra × Fisioma × Céu × Agenda)
        case deepExploration // Modo Fundo (DeepExplorationView) — target for beagle://fundo Live Activity tap

        var id: String { rawValue }
    }

    var body: some View {
        surfaceRoot
            .onChange(of: deepLink.pending) { _, _ in
                // The Companion honours its own destinations (.work, .chat, .fundo, .sintese); Frota/Oficina belong
                // to the macOS Mission Control / iPad sidebar and are left parked for them.
                switch deepLink.pending {
                case .work:
                    _ = deepLink.consume()
                    activeSheet = .work
                case .capture:
                    _ = deepLink.consume()
                    activeSheet = .capture
                case .fundo:
                    _ = deepLink.consume()
                    activeSheet = .deepExploration
                case .sintese:
                    _ = deepLink.consume()
                    activeSheet = .dailySynthesis
                case .chat:
                    _ = deepLink.consume()
                    activeSheet = nil
                default:
                    break
                }
            }
            .task { deepLink.applyLaunchArgumentIfPresent() }
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
            .onChange(of: physio.summary.observedAt) { _, _ in
                syncConversationLiveContext()
            }
            .onChange(of: physio.cognitivePosture.observedAt) { _, _ in
                syncConversationLiveContext()
            }
            .onChange(of: spaceWeather.latest?.ts) { _, _ in
                syncConversationLiveContext()
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
        // Living mesh restored (dark-only — the light-mode legibility reason is gone).
        ShellPresenceGradient(
            presence: shellPresence,
            cognitivePosture: physio.cognitivePosture
        )
    }

    private var surfaceForeground: some View {
        VStack(spacing: 0) {
            // Top chrome retired from the chat (project/dream/agents/readiness/settings) — the
            // companion leads, Claude-grade. Settings + project moved into the drawer footer;
            // the dashboard strips move to the dedicated data screen (Fase 4). Nudge/serendipity
            // stay as transient event banners only.
            metacognitiveNudgeLayer
            serendipityLayer

            ChatScreen(
                store: conversation,
                // Os DOIS precisam existir: sem `observedAt` o dado não foi observado,
                // e uma leitura velha demais deixa de valer como agora.
                breath: PresenceBreath.from(
                    bpm: physio.cognitivePosture.respiratoryRate,
                    observedAt: physio.cognitivePosture.observedAt
                ).resolved(now: .now),
                weather: spaceWeather.latest,
                posture: physio.cognitivePosture,
                onOpenSettings: { activeSheet = .settings },
                onOpenProject: { activeSheet = .projectPicker },
                onOpenData: { activeSheet = .agora },
                onOpenMemory: { activeSheet = .memory },
                onOpenDreamInsights: { activeSheet = .dreamInsights },
                unreadDreamInsightCount: DreamSynthesisEngine.shared.unreadCount,
                onOpenWork: { activeSheet = .work },
                onOpenDailySynthesis: { activeSheet = .dailySynthesis },
                onOpenDeepExploration: { activeSheet = .deepExploration }
            )
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
        case .agora:
            AgoraDetailView(sky: spaceWeather.latest, summary: physio.summary) { prompt in
                Task { await conversation.sendMessage(prompt) }
            }
        case .memory:
            MemoryLensDetailView(store: conversation)
        case .dreamInsights:
            dreamInsightsSheet
        case .work:
            workSheet
        case .dailySynthesis:
            DailySynthesisView(
                captureLines: cognitive.todaysCaptureLines(),
                physioSummary: physio.summary,
                sky: spaceWeather.latest
            )
        case .deepExploration:
            deepExplorationSheet
        }
    }

    private var deepExplorationSheet: some View {
        NavigationStack {
            DeepExplorationView()
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Fechar") { activeSheet = nil }
                            .accessibilityIdentifier("surface.deepExploration.closeButton")
                    }
                }
        }
    }

    private var dreamInsightsSheet: some View {
        NavigationStack {
            DreamInsightsView()
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Done") { activeSheet = nil }
                            .accessibilityIdentifier("surface.dreamInsights.doneButton")
                    }
                }
        }
    }

    private var workSheet: some View {
        NavigationStack {
            WorkView(bootError: $bootError)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Fechar") { activeSheet = nil }
                            .accessibilityIdentifier("surface.work.closeButton")
                    }
                }
        }
    }

    private var settingsSheet: some View {
        NavigationStack {
            ModelSettingsView()
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Done") { activeSheet = nil }
                            .accessibilityIdentifier("surface.settings.doneButton")
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
            ThoughtCaptureView(sharedConversation: conversation)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Done") { activeSheet = nil }
                    }
                }
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
                .foregroundStyle(BeagleTheme.textTertiary)  // recede — the companion leads
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

    func syncConversationLiveContext() {
        if let r = physio.cognitivePosture.readiness {
            if r >= 0.7 { conversation.flowState = "FLOW" }
            else if r < 0.3 { conversation.flowState = "STRESS" }
            else { conversation.flowState = "NORMAL" }
        }
        conversation.sleepQuality01 = physio.cognitivePosture.sleepQuality
        conversation.physioSummary = physio.summary
        if physio.summary.isMeaningful {
            conversation.physioContext = physio.summary.detailLine
        }
        conversation.currentSky = spaceWeather.latest
    }

    func wireConversation() {
        let slug = cognitive.activeProjectSlug ?? catalog.primaryProject?.projectSlug ?? "sounio"
        conversation.modelContext = modelContext
        conversation.projectSlug = slug
        conversation.projectFamily = ProjectFamily.fromProjectSlug(slug)
        conversation.publicationScope = PublicationScope.forProjectFamily(
            ProjectFamily.fromProjectSlug(slug)
        )
        syncConversationLiveContext()
        conversation.loadPersistedConversation()
        if ProcessInfo.processInfo.arguments.contains("--demo-history") {
            conversation.seedPreviewConversation([
                ChatMessage(role: .user, content: "Acordei meio pra baixo hoje, não sei bem por quê."),
                ChatMessage(
                    role: .assistant,
                    content: "Faz sentido. Você dormiu leve e o coração andou tenso essa noite — às vezes o corpo sente antes da gente entender. Quer me contar como foi a noite?",
                    source: "physiome"
                ),
            ])
        } else if ProcessInfo.processInfo.arguments.contains("--demo-chat") {
            conversation.seedDemoConversation()
        }

        let physioStore = physio
        let skyStore = spaceWeather
        AppleDeviceToolsBridge.shared.registerLivePhysioProvider { shouldRefresh in
            await Task { @MainActor in
                if shouldRefresh || !physioStore.summary.isMeaningful {
                    await physioStore.refresh(requestAuthorization: false)
                }
                let s = physioStore.summary
                let p = physioStore.cognitivePosture
                var lines: [String] = ["## Fisioma ao Vivo (Apple Watch / HealthKit)"]
                lines.append("- Prontidão autonômica: \(s.readiness.rawValue) (\(s.detailLine))")
                if let hrv = s.hrvMs { lines.append(String(format: "- HRV (SDNN): %.1f ms", hrv)) }
                if let rhr = s.restingHeartRate { lines.append(String(format: "- FC de repouso: %.0f bpm", rhr)) }
                if let sleep = s.sleepHours { lines.append(String(format: "- Sono total: %.1f h", sleep)) }
                if let sq = p.sleepQuality { lines.append(String(format: "- Fração Sono Profundo + REM: %.0f%%", sq * 100)) }
                if let resp = p.respiratoryRate { lines.append(String(format: "- Frequência respiratória: %.1f irpm", resp)) }
                if let temp = p.wristTemperature { lines.append(String(format: "- Delta de temperatura noturna do punho: %+.2f °C", temp)) }
                if let som = p.stateOfMind { lines.append(String(format: "- Estado da Mente (valência -1..+1): %+.2f", som)) }
                if let r = p.readiness { lines.append(String(format: "- Índice composto de prontidão cognitiva (5 sinais): %.0f%%", r * 100)) }
                let mindful = Int((s.mindfulMinutes ?? 0).rounded())
                lines.append("- Treinos recentes: \(s.workoutCount) · Minutos de atenção plena: \(mindful)")
                if let sky = skyStore.latest {
                    var skyLine = String(format: "- Clima espacial / geomagnético: Kp %.1f (%@), F10.7 %.0f sfu", sky.kp, sky.band.rawValue, sky.f107)
                    if let dst = sky.dst { skyLine += String(format: ", Dst %.0f nT", dst) }
                    if let sw = sky.solarWindSpeed { skyLine += String(format: ", vento solar %.0f km/s", sw) }
                    if let bz = sky.bz { skyLine += String(format: ", Bz %+.1f nT", bz) }
                    lines.append(skyLine)
                }
                return lines.joined(separator: "\n")
            }.value
        }

        // Configure Foundation Models with stores
        #if canImport(FoundationModels)
        if #available(iOS 26, macOS 26, visionOS 26, *) {
            FoundationModelsAgent.shared.configure(cognitive: cognitive, physio: physio)
            // On-device Apple Intelligence (~3B) is too weak for the companion's voice —
            // the richness IS the companion. Route EVERYTHING to the cluster (GLM). The
            // ~14s latency is covered by the typing indicator. (Fast path kept for a future
            // faster-but-capable model.)
            conversation.fastAvailable = false
            conversation.fastResponder = { prompt, history in
                await FoundationModelsAgent.shared.respond(to: prompt, conversationHistory: history)
            }
            // B-routing: the on-device model doesn't ANSWER (too small for the companion's voice),
            // but it gives an instant warm pt-BR "presence" that bridges the cloud latency. The
            // grounded cluster reply replaces it the moment it streams.
            conversation.quickAck = { userText in
                await FoundationModelsAgent.shared.summarize(
                    userText,
                    instructions: """
                    Você é um amigo íntimo falando português do Brasil, natural e caloroso. O usuário \
                    acabou de te dizer algo. Responda com UMA frase curtíssima (até ~8 palavras) que \
                    apenas acolhe e sinaliza que você está pensando junto — NÃO responda o conteúdo, \
                    NÃO faça perguntas. Exemplos: "Boa, deixa eu pensar nisso contigo…", "Tô aqui, \
                    sentindo isso com você…". Devolva só a frase.
                    """
                )
            }
            Task { await FoundationModelsAgent.shared.prewarm() }
        }
        #endif

        // Live Activity for the companion's own voice turns — independent of on-device Foundation
        // Models, so it covers every reply (Sonnet/Opus/GPT/...), not just the B-routing ack path.
        conversation.onCompanionTurnStart = { title, voiceLabel in
            LiveActivityManager.shared.startCompanionTurn(conversationTitle: title, voiceLabel: voiceLabel)
        }
        conversation.onCompanionTurnEnd = { snippet in
            LiveActivityManager.shared.endCompanionTurn(finalSnippet: snippet)
        }
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

    var activeSlug: String {
        cognitive.activeProjectSlug ?? catalog.primaryProject?.projectSlug ?? "sounio"
    }

    var platformName: String {
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

    var shellPresence: BeaglePresenceState {
        if bootError != nil { return .strained }
        if runningAgentCount > 0 || cognitive.runningJobCount > 0 { return .active }
        return .attentive
    }

    var readinessLabel: String {
        if let r = physio.cognitivePosture.readiness {
            return "\(Int(r * 100))%"
        }
        return "—"
    }

    var readinessColor: Color {
        guard let r = physio.cognitivePosture.readiness else { return BeagleTheme.textTertiary }
        if r >= 0.7 { return BeagleTheme.truthObserved }
        if r >= 0.4 { return BeagleTheme.postureWarm }
        return BeagleTheme.stateError
    }
}

// MARK: - Living shell background

private struct ShellPresenceGradient: View {
    let presence: BeaglePresenceState
    let cognitivePosture: CognitivePosture
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
            guard !reduceMotion, !ProcessInfo.processInfo.arguments.contains("--ui-testing") else { return }
            withAnimation(.easeInOut(duration: 9).repeatForever(autoreverses: true)) {
                phase = 1
            }
        }
    }

    private var animatedPoints: [SIMD2<Float>] {
        let d: Float = reduceMotion ? 0 : Float(phase) * 0.07
        return [
            SIMD2(0,     0),       SIMD2(0.5,     0),        SIMD2(1,     0),
            SIMD2(0+d,   0.5-d),   SIMD2(0.5+d,   0.5+d),    SIMD2(1-d,   0.5+d),
            SIMD2(0,     1),       SIMD2(0.5,     1),        SIMD2(1,     1)
        ]
    }

    // Dark-only living shell: deep void base with a state-tinted glow at the top.
    // No black overlay (the old one muted it to death); `.glow` is now `.clear`
    // post-redesign, so the presence color comes from `.tint`.
    private var gradientColors: [Color] {
        let tint = presence.tint
        let deep = Color(red: 0.02, green: 0.03, blue: 0.07)
        return [
            tint.opacity(0.28), tint.opacity(0.10), Color(white: 0.045),
            tint.opacity(0.12), Color(white: 0.035), tint.opacity(0.14),
            deep,               deep,                Color(white: 0.03)
        ]
    }
}
