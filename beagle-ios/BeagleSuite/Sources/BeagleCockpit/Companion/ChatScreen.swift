//
//  ChatScreen.swift
//  BeagleCockpit — Companion chat
//
//  The chat surface skeleton. Flat warm bubbles scroll above the app's living-mesh
//  background; a single floating Liquid Glass composer is the only chrome. Streaming is
//  driven by ConversationStore (@Observable) — content snapshots coalesce naturally
//  through SwiftUI Observation, and the scroll follows the latest snapshot.
//  See docs/design/2026-06-24-companion-design-system.md (§4, §7).
//

import SwiftUI
import BeagleCore
#if canImport(UIKit)
import UIKit
#endif

public struct ChatScreen: View {
    let store: ConversationStore   // @Observable — SwiftUI tracks property reads in body
    /// Ritmo declarado da respiração (PhysioStore/HealthKit). `.neutral` quando o
    /// Physiome está mudo — e aí a presença respira visivelmente mais raso, em vez
    /// de fingir um ritmo.
    let breath: PresenceBreath
    /// Live geomagnetic snapshot for AuroraPresence. nil → calm placeholder; the
    /// store keeps refreshing in the background so this updates naturally.
    let weather: SpaceWeatherStore.Snapshot?
    /// Live body snapshot (HRV, breath, wrist temp, sleep) for the body strip
    /// above the composer. nil → strip is hidden.
    let posture: CognitivePosture?
    /// Access to the surface's sheets, folded into the history drawer (Claude-style: settings
    /// at the bottom of the drawer) so the chat top stays clean — just history · title · new.
    var onOpenSettings: (() -> Void)?
    var onOpenProject: (() -> Void)?
    /// Opens the dedicated data screen (Agora/physiome series). Lives in the drawer footer.
    var onOpenData: (() -> Void)?
    /// Opens "o que eu lembro de ti" — the warm memory-browse screen. Drawer footer.
    var onOpenMemory: (() -> Void)?
    /// Opens the overnight Dream Synthesis reader. Drawer footer, badge shows unread count —
    /// this is the ONLY surfaced consumer of DreamSynthesisEngine; it silently had no home
    /// after the header-bar chrome was retired, so insights piled up invisibly.
    var onOpenDreamInsights: (() -> Void)?
    var unreadDreamInsightCount: Int = 0
    /// Opens WorkView (the agent deck) — was iPad-sidebar-only before this session's screen
    /// audit found it had zero entry point on iPhone despite being the richest single
    /// feature in the app. Drawer footer.
    var onOpenWork: (() -> Void)?
    var onOpenDailySynthesis: (() -> Void)?
    var onOpenDeepExploration: (() -> Void)?
    @State private var draft = ""
    @State private var attachedImageData: Data?
    @State private var attachedDocument: ChatDocumentPayload?
    /// Última vez que o usuário mexeu em alguma coisa. `nil` → ainda não mexeu nesta
    /// sessão, e nesse caso a presença NÃO adormece (abrir o app e ficar lendo não é
    /// abandono).
    @State private var lastInteraction: Date?
    /// Relógio grosso (30s) só para a ociosidade poder virar `adormecido` sem que nada
    /// mais na tela mude. Não é um timer de animação.
    @State private var idleTick = Date()
    /// The voice turn. Owned by the screen so a composer redraw never drops a live recording.
    @State private var voice = VoiceTurnController()
    @State private var appeared = false
    /// ONE sheet for the whole screen — multiple `.sheet(isPresented:)` on the same view conflict
    /// in SwiftUI (the second silently breaks the first, which is why the drawer stopped opening).
    @State private var activeSheet: ChatSheet?
    /// Action queued by `ConversationDrawer` to fire only after its UIKit dismissal completes,
    /// avoiding parent/child sheet presentation collisions.
    @State private var pendingDrawerAction: (() -> Void)?
    /// The companion's gear for the next message (voice model, or Fundo → Go-Deeper).
    /// Persisted in @AppStorage so his choice (MoE / GPT 5.5 / Local Sem Censura / Sonnet 5) survives app restarts.
    @AppStorage("beagle.chat.depth") private var depth: ChatDepth = .moe
    @State private var composerGoDeepStore = GoDeepStore()
    /// The top bar melts away while you read forward and returns when you scroll back up — the
    /// "chrome dissolves into the content" feel (Claude/Safari). Driven by scroll direction below.
    @State private var topBarHidden = false
    /// Accumulated scroll in the current direction — the bar only flips after a deliberate
    /// gesture (not a twitch), so it doesn't vanish on the slightest touch.
    @State private var scrollAccum: CGFloat = 0
    /// Accessibility: when the user turns on Reduce Transparency, glass falls back to a
    /// solid material so text/controls stay legible (iOS 27's contrast guidance).
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    /// A hold whose release event never arrives (incoming call, backgrounding) would leave the
    /// microphone open. Leaving the foreground closes the turn.
    @Environment(\.scenePhase) private var scenePhase

    public init(store: ConversationStore,
                breath: PresenceBreath = .neutral,
                weather: SpaceWeatherStore.Snapshot? = nil,
                posture: CognitivePosture? = nil,
                onOpenSettings: (() -> Void)? = nil,
                onOpenProject: (() -> Void)? = nil,
                onOpenData: (() -> Void)? = nil,
                onOpenMemory: (() -> Void)? = nil,
                onOpenDreamInsights: (() -> Void)? = nil,
                unreadDreamInsightCount: Int = 0,
                onOpenWork: (() -> Void)? = nil,
                onOpenDailySynthesis: (() -> Void)? = nil,
                onOpenDeepExploration: (() -> Void)? = nil) {
        self.store = store
        self.breath = breath
        self.weather = weather
        self.posture = posture
        self.onOpenSettings = onOpenSettings
        self.onOpenProject = onOpenProject
        self.onOpenData = onOpenData
        self.onOpenMemory = onOpenMemory
        self.onOpenDreamInsights = onOpenDreamInsights
        self.unreadDreamInsightCount = unreadDreamInsightCount
        self.onOpenWork = onOpenWork
        self.onOpenDailySynthesis = onOpenDailySynthesis
        self.onOpenDeepExploration = onOpenDeepExploration
    }

    /// Estado da presença. Toda a regra vive em `PresenceResolver` (puro, testado em
    /// BeagleCoreTests); aqui só se colhem as entradas.
    ///
    /// `composerFocused` é aproximado por "há rascunho digitado": o foco de teclado
    /// mora dentro do ChatComposer e não é exposto para cá. Vale mais errar para
    /// menos (não ficar em `ouvindo` com o composer vazio) do que instrumentar o
    /// composer inteiro neste corte.
    /// O céu só conta se foi MEDIDO e ainda vale.
    ///
    /// `SpaceWeatherStore.latest` é nil até a primeira leitura, então ausência é
    /// distinguível. Mas `SkyBand.from` devolve `.calm` com Kp e Dst nulos — passar
    /// a banda direto faria "não sei" virar "calmo", e a presença estaria afirmando
    /// algo sobre o céu sem ter olhado.
    ///
    /// O poller roda a cada 30min; 3h de folga cobre uma falha de rede sem deixar
    /// tempestade de ontem animando o bicho hoje.
    private var ceuMedido: SkyBand? {
        guard let w = weather else { return nil }
        guard idleTick.timeIntervalSince(w.ts) < 3 * 60 * 60 else { return nil }
        return w.band
    }

    /// O que ele deixou. Tipo PRÓPRIO, nunca `store.messages` — a parede da
    /// síntese é estrutural: não existe caminho de código que transforme isto em
    /// turno de conversa.
    @State private var chegada = ArrivalStore()
    @State private var voz = CompanionVoice()
    @State private var chegadaAberta = false
    /// O turno atual começou por FALA. É isto que decide se ele responde em voz.
    ///
    /// Se ele falou, quer ouvir — está andando, com a tela longe dos olhos, e foi
    /// essa a queixa que abriu o desenho. Se ele digitou, falar sozinho seria
    /// intromissão: quem digita está olhando.
    @State private var turnoVeioDeVoz = false
    @AppStorage(CompanionVoice.autoSpeakModeKey) private var autoSpeakRaw: String = CompanionAutoSpeakMode.whenSpoken.rawValue
    @AppStorage(CompanionLiveSessionTransportMode.storageKey) private var liveTransportRaw: String = CompanionLiveSessionTransportMode.auto.rawValue
    /// Sessão de Voz Contínua Mãos-Livres (GPT-Live 1.1 Full-Duplex ou Walkie-Talkie Offline)
    @State private var liveVoice = CompanionLiveVoiceSessionState()
    @State private var gptLive = OpenAILiveVoiceSession()
    @State private var usingGPTLiveFullDuplex = false
    @State private var liveVoiceLoopTask: Task<Void, Never>?
    @State private var lastForwardedTranscriptLength: Int = 0

    private var presenceState: PresenceState {
        PresenceResolver(
            isStreaming: store.isStreaming || gptLive.activeDelegationCount > 0,
            isVoiceListening: voice.isListening || (usingGPTLiveFullDuplex && liveVoice.isActive && liveVoice.phase == .listening),
            composerFocused: !draft.isEmpty || attachedImageData != nil || attachedDocument != nil,
            isActive: scenePhase == .active,
            lastInteraction: lastInteraction,
            ultimaFalaDele: store.messages.last(where: { $0.role == .user })?.content,
            hora: Calendar.current.component(.hour, from: idleTick),
            ceu: ceuMedido
        ).state(now: idleTick)
    }

    public var body: some View {
        ZStack(alignment: .bottom) {
            // Layer 1: hearth glow rising from bottom
            hearth
            // Layer 2: aurora orb sitting BEHIND the conversation (per user 2026-06-28:
            // "deixar o orb no mesmo plano que a conversa, ou atrás dela, pra ampliar
            // a visualização do chat"). Large + faint; the chat reads OVER it.
            presenceBackground
            // Layer 3: chat content fills the screen — empty state greeting OR conversation
            VStack(spacing: 0) {
                if store.messages.isEmpty {
                    Spacer(minLength: 0)
                    greeting
                    Spacer(minLength: 0)
                    Spacer(minLength: 0)
                } else {
                    conversation
                }
            }
            // Layer 4: minimal top bar — history · title · walkie-talkie · new. Floats over the aurora.
            topBar
            // Layer 5: floating live voice bar (when Walkie-Talkie is active) + composer pinned to bottom.
            VStack(spacing: BeagleSpacing.xs) {
                if liveVoice.isActive {
                    liveVoiceFloatingBar
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
                composer
            }
            .animation(.snappy(duration: 0.25), value: liveVoice.isActive)
        }
        // Entry ceremony — the space materializes with a breath instead of snapping in
        // (Gaggioli: ceremony over frictionless).
        .opacity(appeared ? 1 : 0)
        .scaleEffect(appeared ? 1 : 0.985, anchor: .bottom)
        .task {
            let isUITesting = ProcessInfo.processInfo.arguments.contains("--ui-testing")
            if ProcessInfo.processInfo.arguments.contains("--demo-chat") {
                store.seedDemoConversation()
            }
            bindVoiceCallbacks()
            CompanionLiveVoiceBus.shared.onCommand = { command in
                handleLiveVoiceCommand(command)
            }
            if let queuedCommand = CompanionLiveVoiceBus.shared.consumePendingCommand() {
                handleLiveVoiceCommand(queuedCommand)
            }
            guard !isUITesting else { return }
            // Warm the on-device speech assets now so the first hold doesn't eat the first
            // three words. Fire-and-forget and time-boxed inside the controller.
            voice.prewarm()
            await consumeSharedInboxIfNeeded()
            await consumeCompanionLaunchActionIfNeeded()

            // O que ele deixou. Em Task separada de propósito: a síntese leva
            // dezenas de segundos e NUNCA pode atrasar a tela abrir. Se falhar,
            // falha calada — a chegada é um presente, não um requisito.
            Task { await chegada.buscarSeForHora() }
        }
        .onChange(of: DeepLinkRouter.shared.pendingCompanionAction) { _, _ in
            Task { await consumeCompanionLaunchActionIfNeeded() }
        }
        .onChange(of: voice.transcript) { _, novoTexto in
            guard liveVoice.isActive, !usingGPTLiveFullDuplex, liveVoice.phase == .listening else { return }
            let trimmed = novoTexto.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return }
            if abs(trimmed.count - lastForwardedTranscriptLength) >= 12 || lastForwardedTranscriptLength == 0 {
                lastForwardedTranscriptLength = trimmed.count
                liveVoice.updatePartialTranscript(trimmed)
                LiveActivityManager.shared.updateVoiceSession(state: liveVoice)
            }
        }
        .onChange(of: store.presenceNote) { _, nota in
            guard liveVoice.isActive,
                  (liveVoice.phase == .thinking || gptLive.activeDelegationCount > 0),
                  let nota, !nota.isEmpty else { return }
            liveVoice.updateThinkingNote(nota)
            LiveActivityManager.shared.updateVoiceSession(state: liveVoice)
        }
        .onChange(of: store.isStreaming) { antes, agora in
            guard antes, !agora else { return }
            if liveVoice.isActive {
                guard !usingGPTLiveFullDuplex else { return }
                turnoVeioDeVoz = false
                liveVoiceLoopTask?.cancel()
                liveVoiceLoopTask = Task { @MainActor in
                    guard liveVoice.isActive,
                          liveVoice.phase != .paused,
                          liveVoice.phase != .ended else { return }

                    if let ultima = store.messages.last,
                       ultima.role == .assistant,
                       !ultima.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        liveVoice.voiceLabel = depth.label
                        liveVoice.onAssistantSpeaking(ultima.content)
                        LiveActivityManager.shared.updateVoiceSession(state: liveVoice)
                        await voz.falar(ultima.content, id: ultima.id.uuidString)
                    }

                    guard !Task.isCancelled,
                          liveVoice.isActive,
                          liveVoice.phase != .paused,
                          liveVoice.phase != .ended else { return }

                    // Compasso acústico de 320ms para dissipar reverberação do alto-falante antes de rearmar o STT
                    try? await Task.sleep(for: .milliseconds(320))

                    guard !Task.isCancelled,
                          liveVoice.isActive,
                          liveVoice.phase != .paused,
                          liveVoice.phase != .ended else { return }

                    if liveVoice.onSpeechFinishedRearm() {
                        lastForwardedTranscriptLength = 0
                        LiveActivityManager.shared.updateVoiceSession(state: liveVoice)
                        await armNextLiveVoiceTurn()
                    }
                }
                return
            }

            // Fim do turno avulso: se ele FALOU (modo padrão) ou ativou Mãos-livres ("always"), ouve de volta.
            let deveFalar = (autoSpeakRaw == CompanionAutoSpeakMode.always.rawValue)
                || (autoSpeakRaw == CompanionAutoSpeakMode.whenSpoken.rawValue && turnoVeioDeVoz)
            turnoVeioDeVoz = false
            guard deveFalar,
                  let ultima = store.messages.last,
                  ultima.role == .assistant,
                  !ultima.content.isEmpty else { return }
            Task { await voz.falar(ultima.content, id: ultima.id.uuidString) }
        }
        .onDisappear {
            // Sair da tela cala a boca apenas fora da sessão contínua mãos-livres.
            if !liveVoice.isActive {
                voz.parar()
            }
        }
        .onChange(of: scenePhase) { _, phase in
            // Na sessão contínua Walkie-Talkie, bloquear a tela no bolso/carro mantém a escuta e o áudio vivos.
            if phase != .active && !liveVoice.isActive {
                voice.handleResignActive()
            }
            if phase == .active {
                lastInteraction = .now
                idleTick = .now
                if let queuedCommand = CompanionLiveVoiceBus.shared.consumePendingCommand() {
                    handleLiveVoiceCommand(queuedCommand)
                }
                Task { await consumeSharedInboxIfNeeded() }
            }
        }
        .onChange(of: DeepLinkRouter.shared.pending) { _, pending in
            if pending == .chat {
                _ = DeepLinkRouter.shared.consume()
                activeSheet = nil
                Task { await consumeSharedInboxIfNeeded() }
            }
        }
        .onChange(of: draft) { _, _ in lastInteraction = .now }
        .onChange(of: store.messages.count) { _, _ in lastInteraction = .now }
        // 30s é grosso de propósito: só existe para a ociosidade poder virar
        // `adormecido`. Nada de animação depende disto.
        .onReceive(Timer.publish(every: 30, on: .main, in: .common).autoconnect()) { now in
            idleTick = now
        }
        .onAppear {
            withAnimation(.easeOut(duration: 0.55)) { appeared = true }
        }
        .sheet(item: $activeSheet, onDismiss: {
            if let action = pendingDrawerAction {
                pendingDrawerAction = nil
                action()
            }
        }) { sheet in
            switch sheet {
            case .history:
                ConversationDrawer(
                    store: store,
                    onOpenSettings: onOpenSettings.map { action in { pendingDrawerAction = action } },
                    onOpenProject: onOpenProject.map { action in { pendingDrawerAction = action } },
                    onOpenData: onOpenData.map { action in { pendingDrawerAction = action } },
                    onOpenMemory: onOpenMemory.map { action in { pendingDrawerAction = action } },
                    onOpenDreamInsights: onOpenDreamInsights.map { action in { pendingDrawerAction = action } },
                    unreadDreamInsightCount: unreadDreamInsightCount,
                    onOpenWork: onOpenWork.map { action in { pendingDrawerAction = action } },
                    onOpenDailySynthesis: onOpenDailySynthesis.map { action in { pendingDrawerAction = action } },
                    onOpenDeepExploration: onOpenDeepExploration.map { action in { pendingDrawerAction = action } }
                )
            case .goDeep(let prompt):
                GoDeepView(store: composerGoDeepStore, prompt: prompt)
            #if os(iOS)
            case .camera:
                CameraImagePicker { image in
                    if let jpeg = image.jpegData(compressionQuality: 0.88) {
                        attachedImageData = jpeg
                        attachedDocument = nil
                    }
                }
                .ignoresSafeArea()
            case .documentScanner:
                DocumentCameraScanner { image in
                    if let jpeg = image.jpegData(compressionQuality: 0.90) {
                        attachedImageData = jpeg
                        attachedDocument = nil
                    }
                }
                .ignoresSafeArea()
            #endif
            }
        }
    }

    // Minimal top bar: history (☰) · conversation title · new (＋). Liquid Glass buttons that
    // float over the aurora. NO GlassEffectContainer/glassEffectID — those try to MORPH the glass
    // when state changes (e.g. presenting the drawer), which made the buttons flicker / lose their
    // effect on tap. Plain per-button glass is stable.
    private var topBar: some View {
        VStack {
            HStack(spacing: BeagleSpacing.sm) {
                topBarButton(
                    "line.3.horizontal",
                    accessibilityLabel: "Histórico e menu",
                    accessibilityIdentifier: "chat.topBar.drawerButton"
                ) { activeSheet = .history }
                Spacer(minLength: BeagleSpacing.sm)
                VStack(spacing: 2) {
                    Text(store.currentConversationTitle)
                        .font(BeagleFont.subheadline.font.weight(.semibold))
                        .foregroundStyle(BeagleTheme.companionInk)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .accessibilityIdentifier("chat.topBar.title")
                        // Legibility over the variable aurora - a soft dark halo keeps the title
                        // readable whether it floats over bright green or deep night.
                        .shadow(color: .black.opacity(0.45), radius: 4, y: 0.5)
                    // The Agora block distilled to three words: day-part, hour, readiness (when
                    // HealthKit has a signal). Same vocabulary the server puts in the model
                    // own Agora block - never invents a state the model was not given.
                    Text(agoraStrip)
                        .font(BeagleFont.caption2.font)
                        .foregroundStyle(BeagleTheme.textSecondary)
                        .shadow(color: .black.opacity(0.45), radius: 4, y: 0.5)
                }
                Spacer(minLength: BeagleSpacing.sm)
                voiceTopBarControl
                topBarButton(
                    "square.and.pencil",
                    accessibilityLabel: "Nova conversa",
                    accessibilityIdentifier: "chat.topBar.newChatButton"
                ) {
                    voz.parar()
                    withAnimation(.easeOut(duration: 0.25)) { store.newConversation() }
                }
            }
            .padding(.horizontal, BeagleSpacing.md)
            .padding(.top, BeagleSpacing.sm)
            // Melt away while reading forward; glide back on scroll-up.
            .opacity(topBarHidden ? 0 : 1)
            .offset(y: topBarHidden ? -72 : 0)
            .blur(radius: topBarHidden ? 6 : 0)
            .allowsHitTesting(!topBarHidden)
            Spacer()
        }
    }

    @ViewBuilder
    private var voiceTopBarControl: some View {
        HStack(spacing: 6) {
            // Botão direto de 1 toque para Sessão de Voz Contínua (Walkie-Talkie Mãos-Livres + Dynamic Island)
            Button {
                #if canImport(UIKit)
                UIImpactFeedbackGenerator(style: .soft).impactOccurred()
                #endif
                Task {
                    if liveVoice.isActive {
                        endLiveVoiceSession()
                    } else {
                        await startLiveVoiceSession()
                    }
                }
            } label: {
                Image(systemName: liveVoice.isActive ? "dot.radiowaves.left.and.right" : "waveform.badge.mic")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(
                        liveVoice.isActive
                            ? liveVoiceAccent(for: liveVoice.phase)
                            : BeagleTheme.companionInk.opacity(0.88)
                    )
                    .frame(width: 40, height: 40)
                    .background(.ultraThinMaterial, in: Circle())
                    .overlay(
                        Circle().strokeBorder(
                            liveVoice.isActive
                                ? liveVoiceAccent(for: liveVoice.phase).opacity(0.55)
                                : Color.white.opacity(0.12),
                            lineWidth: liveVoice.isActive ? 1.0 : 0.5
                        )
                    )
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(liveVoice.isActive ? "Encerrar sessão de voz contínua" : "Iniciar sessão de voz contínua mãos-livres")

            if voz.estaAtivo && !liveVoice.isActive {
                Button {
                    #if canImport(UIKit)
                    UIImpactFeedbackGenerator(style: .soft).impactOccurred()
                    #endif
                    voz.parar()
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "stop.fill")
                            .font(.system(size: 11, weight: .bold))
                        Text(voz.buscando ? "voz…" : "parar")
                            .font(BeagleFont.caption2.font.weight(.semibold))
                    }
                    .foregroundStyle(MessageBubble.marcaAmbar)
                    .frame(height: 40)
                    .padding(.horizontal, 12)
                    .background(.ultraThinMaterial, in: Capsule())
                    .overlay(Capsule().strokeBorder(MessageBubble.marcaAmbar.opacity(0.45), lineWidth: 0.75))
                    .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Parar leitura em voz")
            } else if !liveVoice.isActive {
                Menu {
                    Button {
                        Task { await startLiveVoiceSession() }
                    } label: {
                        Label("Iniciar Conversa de Voz Contínua", systemImage: "dot.radiowaves.left.and.right")
                    }
                    Picker("Modo Mãos-Livres", selection: $liveTransportRaw) {
                        ForEach(CompanionLiveSessionTransportMode.allCases) { mode in
                            Text(mode.label).tag(mode.rawValue)
                        }
                    }
                    Divider()
                    Picker("Resposta em Voz", selection: $autoSpeakRaw) {
                        ForEach(CompanionAutoSpeakMode.allCases) { mode in
                            Label(
                                mode.label,
                                systemImage: mode == .always
                                    ? "waveform"
                                    : (mode == .whenSpoken ? "speaker.wave.2" : "speaker.slash")
                            )
                            .tag(mode.rawValue)
                        }
                    }
                } label: {
                    Image(
                        systemName: autoSpeakRaw == CompanionAutoSpeakMode.always.rawValue
                            ? "waveform"
                            : (autoSpeakRaw == CompanionAutoSpeakMode.manual.rawValue ? "speaker.slash" : "speaker.wave.2")
                    )
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(
                        autoSpeakRaw == CompanionAutoSpeakMode.always.rawValue
                            ? BeagleTheme.truthObserved
                            : BeagleTheme.companionInk.opacity(0.88)
                    )
                    .frame(width: 40, height: 40)
                    .background(.ultraThinMaterial, in: Circle())
                    .overlay(Circle().strokeBorder(Color.white.opacity(0.12), lineWidth: 0.5))
                    .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Modo de resposta em voz")
            }
        }
    }

    private func topBarButton(
        _ system: String,
        accessibilityLabel: String,
        accessibilityIdentifier: String,
        action: @escaping () -> Void
    ) -> some View {
        // NO `.glassEffect` on these buttons: on iOS 26/27 glass applied to a Button mismatches the
        // tap region (the glass shape ≠ the hittable area), so taps were silently lost — that's why
        // the ☰ "didn't open" the drawer while the composer Menu (not a glass button) worked. A
        // frosted-material circle + an explicit `.contentShape(Circle())` makes the WHOLE circle a
        // reliable tap target.
        Button {
            #if canImport(UIKit)
            UIImpactFeedbackGenerator(style: .soft).impactOccurred()
            #endif
            action()
        } label: {
            Image(systemName: system)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(BeagleTheme.companionInk.opacity(0.9))
                .frame(width: 40, height: 40)
                .background(.ultraThinMaterial, in: Circle())
                .overlay(Circle().strokeBorder(Color.white.opacity(0.12), lineWidth: 0.5))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityIdentifier(accessibilityIdentifier)
    }

    // Aurora CURTAIN sitting BEHIND the conversation. Spans the full width;
    // drifts horizontally, ripples vertically, hue cycles, brightens when the
    // companion is streaming. Empty state: brighter and fills upper half.
    // Chatting: dimmer and pulled to upper third so the conversation reads.
    private var presenceBackground: some View {
        let empty = store.messages.isEmpty
        // ATENÇÃO: cada camada tem a SUA opacidade. Antes havia um único
        // `.opacity(empty ? 0.9 : 0.28)` no retorno da propriedade; herdá-lo deixaria
        // o primordial a 28% justamente enquanto se lê — o efeito "fantasma".
        return ZStack {
            // Atrás: a aurora continua (foi construída de propósito e o usuário gosta
            // dela), mas rebaixada a cenário do cenário para não virar sopa visual.
            AuroraPresence(
                breath: breath,
                weather: weather,
                isStreaming: store.isStreaming,
                size: empty ? .greeter : .header
            )
            .opacity(empty ? 0.55 : 0.16)
            .animation(.easeOut(duration: 0.35), value: empty)

            // Na frente: o bicho. Máscara radial e curva própria de opacidade vivem
            // dentro de PrimordialPresence.
            PrimordialPresence(
                state: presenceState,
                breath: breath,
                sky: weather?.band ?? .calm
            )
            .opacity(empty ? 0.95 : 0.55)
            .animation(.easeOut(duration: 0.35), value: empty)
        }
        .allowsHitTesting(false)
    }

    // Top-right "novo" button — clears the conversation thread. Floats over the
    // chat so it doesn't steal layout space. Glass capsule + hairline.
    private var newConversationButton: some View {
        VStack {
            HStack {
                Spacer()
                Button {
                    #if canImport(UIKit)
                    UIImpactFeedbackGenerator(style: .soft).impactOccurred()
                    #endif
                    withAnimation(.easeOut(duration: 0.25)) { store.clear() }
                } label: {
                    Label("novo", systemImage: "square.and.pencil")
                        .font(BeagleFont.caption.font.weight(.medium))
                        .foregroundStyle(BeagleTheme.companionInk.opacity(0.85))
                        .padding(.horizontal, BeagleSpacing.sm)
                        .padding(.vertical, 6)
                }
                .buttonStyle(.plain)
                .glassEffect(.regular, in: Capsule())
                .overlay(Capsule().strokeBorder(Color.white.opacity(0.12), lineWidth: 0.75))
                .padding(.trailing, BeagleSpacing.md)
                .padding(.top, BeagleSpacing.sm)
            }
            Spacer()
        }
    }

    // Live body strip — HRV / breath / wrist temp / sleep — pulled from PhysioStore.
    // Renders only when at least one signal is available; chips collapse otherwise.
    @ViewBuilder
    private var bodyStrip: some View {
        if let p = posture, hasAnyBodySignal(p) {
            HStack(spacing: BeagleSpacing.sm) {
                if let h = p.hrv { bodyChip("\(Int(h)) ms", system: "waveform.path.ecg") }
                if let r = p.respiratoryRate { bodyChip("\(Int(r.rounded())) bpm", system: "wind") }
                if let s = p.sleepQuality { bodyChip("\(Int((s * 100).rounded()))% sono", system: "moon.zzz") }
                if let t = p.wristTemperature {
                    let sign = t >= 0 ? "+" : ""
                    bodyChip("\(sign)\(String(format: "%.1f", t))°", system: "thermometer.medium")
                }
            }
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.horizontal, BeagleSpacing.md)
        }
    }

    private func hasAnyBodySignal(_ p: CognitivePosture) -> Bool {
        p.hrv != nil || p.respiratoryRate != nil || p.sleepQuality != nil || p.wristTemperature != nil
    }

    private func bodyChip(_ text: String, system: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: system)
                .font(.system(size: 10, weight: .medium))
            Text(text)
                .font(BeagleFont.caption2.font.weight(.medium))
        }
        .foregroundStyle(BeagleTheme.companionInk.opacity(0.75))
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .glassEffect(.regular, in: Capsule())
        .overlay(Capsule().strokeBorder(Color.white.opacity(0.10), lineWidth: 0.5))
    }

    // Aurora glow rising from the composer — geomagnetic dawn.
    private var hearth: some View {
        let kp = weather?.kp ?? 1.0
        let stormBoost = min(0.25, max(0, (kp - 2) / 20))
        return RadialGradient(
            colors: [
                BeagleTheme.auroraGreen.opacity(0.18 + stormBoost),
                BeagleTheme.auroraTeal.opacity(0.14 + stormBoost),
                BeagleTheme.auroraViolet.opacity(0.10 + stormBoost),
                BeagleTheme.auroraNight.opacity(0.55),
                .clear
            ],
            center: UnitPoint(x: 0.5, y: 0.95),
            startRadius: 0,
            endRadius: 520
        )
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }

    // MARK: - Conversation (flat content above the mesh)

    /// A CHEGADA — item 7 do desenho: "quando há material, ao abrir o app ele já
    /// disse algo".
    ///
    /// Visualmente distinta da carta de propósito. A fala em resposta tem serifa e
    /// a marca âmbar no início do turno; isto é um bloco recuado, com filete e uma
    /// etiqueta que diz QUANDO foi dito. A diferença não é decorativa: sem ela,
    /// algo escrito antes dele chegar leria como resposta ao que ele acabou de
    /// dizer — e ele confiaria numa réplica que nunca houve.
    @ViewBuilder
    private var aChegada: some View {
        if chegada.temAlgoADizer {
            VStack(alignment: .leading, spacing: BeagleSpacing.xs) {
                HStack(spacing: BeagleSpacing.xxs) {
                    Text("ENQUANTO VOCÊ NÃO ESTAVA")
                        .font(.system(size: 9.5, weight: .semibold))
                        .tracking(1.3)
                        .foregroundStyle(MessageBubble.marcaAmbar.opacity(0.85))
                    Spacer(minLength: 0)
                    Button {
                        withAnimation(BeagleMotion.snappy) { chegada.dispensar() }
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(BeagleTheme.textTertiary)
                            .padding(6)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Dispensar")
                }
                MarkdownText(
                    text: chegadaAberta ? chegada.textoCompleto : chegada.texto,
                    inkColor: BeagleTheme.companionInk.opacity(0.92),
                    bodyFont: .system(.callout, design: .serif),
                    lineSpacingPt: 5.5
                )
                if chegada.temMais {
                    Button {
                        withAnimation(BeagleMotion.snappy) { chegadaAberta.toggle() }
                    } label: {
                        Text(chegadaAberta ? "menos" : "o resto")
                            .font(BeagleFont.caption2.font)
                            .foregroundStyle(MessageBubble.marcaAmbar.opacity(0.9))
                            .padding(.vertical, 4)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.leading, BeagleSpacing.sm)
            .padding(.trailing, BeagleSpacing.xs)
            .padding(.vertical, BeagleSpacing.sm)
            .overlay(alignment: .leading) {
                Capsule()
                    .fill(MessageBubble.marcaAmbar.opacity(0.5))
                    .frame(width: 2)
            }
            .frame(maxWidth: 620, alignment: .leading)
            .transition(.opacity.combined(with: .move(edge: .top)))
        }
    }

    private var conversation: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: BeagleSpacing.lg) {
                    aChegada
                    ForEach(store.messages) { message in
                        MessageBubble(
                            message: message,
                            isLast: message.id == store.messages.last?.id,
                            onRegenerate: { Task { await store.regenerateLastResponse() } },
                            voz: voz
                        )
                        .id(message.id)
                    }
                    // Presence LAYER — a murmur about the wait, not a line of his letter.
                    // Lives outside the message list so server-authored text never renders
                    // in serif as his voice (desenho 2026-08-02, item 5).
                    if (store.isStreaming || gptLive.activeDelegationCount > 0),
                       let note = store.presenceNote,
                       !note.isEmpty {
                        Text(note)
                            .font(BeagleFont.footnote.font.italic())
                            .foregroundStyle(BeagleTheme.textTertiary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.leading, BeagleSpacing.xs)
                            .transition(.opacity)
                    }
                    // clearance so the floating composer + live voice bar never cover the last line
                    Color.clear.frame(height: liveVoice.isActive ? 136 : 72).id(Self.bottomAnchor)
                }
                .padding(.horizontal, BeagleSpacing.md)
                .padding(.top, BeagleSpacing.md)
                .frame(maxWidth: .infinity, minHeight: 0, alignment: .bottom)
                .animation(.easeOut(duration: 0.25), value: store.messages.count)
            }
            .defaultScrollAnchor(.bottom)   // recent messages hug the composer; void goes up top
            .scrollDismissesKeyboard(.interactively)
            // Direction-based chrome melt: finger up (offset grows → reading forward) hides the
            // top bar; finger down (offset shrinks → going back) reveals it. Anchor-agnostic,
            // and never hides the bar when the transcript fits on screen or sits at the top.
            .onScrollGeometryChange(for: TopBarScrollMetrics.self) { geo in
                TopBarScrollMetrics(
                    offsetY: geo.contentOffset.y + geo.contentInsets.top,
                    containerHeight: geo.containerSize.height,
                    isScrollable: geo.contentSize.height > geo.containerSize.height + 24
                )
            } action: { oldMetrics, newMetrics in
                // Ignore programmatic offset jumps caused by keyboard appearance/dismissal
                // or orientation changes resizing the scroll container.
                if abs(newMetrics.containerHeight - oldMetrics.containerHeight) > 1 {
                    scrollAccum = 0
                    return
                }
                if !newMetrics.isScrollable || newMetrics.offsetY <= 12 {
                    if topBarHidden {
                        withAnimation(.easeOut(duration: 0.3)) { topBarHidden = false }
                    }
                    scrollAccum = 0
                    return
                }
                let delta = newMetrics.offsetY - oldMetrics.offsetY
                guard abs(delta) > 0.5 else { return }     // ignore noise
                // Reset the accumulator on a direction change so a deliberate gesture in one
                // direction is what counts — not net drift.
                if (delta > 0) != (scrollAccum > 0) { scrollAccum = 0 }
                scrollAccum += delta
                if scrollAccum > 60, !topBarHidden {
                    withAnimation(.easeOut(duration: 0.4)) { topBarHidden = true }
                    scrollAccum = 0
                } else if scrollAccum < -40, topBarHidden {
                    withAnimation(.easeOut(duration: 0.4)) { topBarHidden = false }
                    scrollAccum = 0
                }
            }
            .onChange(of: store.messages.last?.content) { _, _ in
                proxy.scrollTo(Self.bottomAnchor, anchor: .bottom)
            }
            .onChange(of: store.messages.count) { _, _ in
                withAnimation(.snappy(duration: 0.22)) {
                    proxy.scrollTo(Self.bottomAnchor, anchor: .bottom)
                }
                // A fresh turn brings the bar back so the title/controls are always reachable.
                if topBarHidden { withAnimation(.easeOut(duration: 0.28)) { topBarHidden = false } }
            }
        }
    }

    // MARK: - Barra Flutuante da Sessão Contínua Mãos-Livres (Walkie-Talkie)

    private func liveVoiceAccent(for phase: CompanionLiveVoicePhase) -> Color {
        switch phase {
        case .listening: return BeagleTheme.truthObserved
        case .thinking:  return BeagleTheme.truthRemembered
        case .speaking:  return MessageBubble.marcaAmbar
        case .paused:    return BeagleTheme.textSecondary
        case .ended:     return BeagleTheme.textTertiary
        }
    }

    private var liveVoiceDisplayedLine: String {
        if !usingGPTLiveFullDuplex && liveVoice.phase == .listening {
            let partial = voice.transcript.trimmingCharacters(in: .whitespacesAndNewlines)
            if !partial.isEmpty { return partial }
        } else if liveVoice.phase == .thinking || gptLive.activeDelegationCount > 0 {
            if let note = store.presenceNote, !note.isEmpty { return note }
        }
        return liveVoice.liveLine.isEmpty ? liveVoice.phase.defaultLinePtBR : liveVoice.liveLine
    }

    private var liveVoiceFloatingBar: some View {
        let tint = liveVoiceAccent(for: liveVoice.phase)
        return HStack(spacing: 10) {
            Image(systemName: liveVoice.phase.symbolName)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(tint)
                .symbolEffect(.pulse, isActive: liveVoice.phase == .listening || liveVoice.phase == .speaking)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text("\(usingGPTLiveFullDuplex ? "GPT-Live 1.1" : "Voz Contínua") · \(liveVoice.phase.titlePtBR)")
                        .font(BeagleFont.caption.font.weight(.semibold))
                        .foregroundStyle(BeagleTheme.companionInk)
                    if gptLive.activeDelegationCount > 0 {
                        Text("MoE")
                            .font(BeagleFont.caption2.font.monospaced())
                            .foregroundStyle(BeagleTheme.truthRemembered)
                    }
                    if liveVoice.turnCount > 0 {
                        Text("T\(liveVoice.turnCount)")
                            .font(BeagleFont.caption2.font.monospaced())
                            .foregroundStyle(tint)
                    }
                }
                Text(liveVoiceDisplayedLine)
                    .font(BeagleFont.caption2.font)
                    .foregroundStyle(BeagleTheme.textSecondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 4)

            if liveVoice.phase == .speaking {
                Button {
                    #if canImport(UIKit)
                    UIImpactFeedbackGenerator(style: .soft).impactOccurred()
                    #endif
                    handleLiveVoiceCommand(.interruptAndListen)
                } label: {
                    Image(systemName: "mic.fill")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(BeagleTheme.truthObserved)
                        .frame(width: 32, height: 32)
                        .background(BeagleTheme.truthObserved.opacity(0.18), in: Circle())
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Cortar resposta e falar agora")
            }

            Button {
                #if canImport(UIKit)
                UIImpactFeedbackGenerator(style: .soft).impactOccurred()
                #endif
                handleLiveVoiceCommand(.togglePause)
            } label: {
                Image(systemName: liveVoice.phase == .paused ? "play.fill" : "pause.fill")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(BeagleTheme.companionInk)
                    .frame(width: 32, height: 32)
                    .background(Color.white.opacity(0.12), in: Circle())
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(liveVoice.phase == .paused ? "Retomar voz contínua" : "Pausar voz contínua")

            Button {
                #if canImport(UIKit)
                UIImpactFeedbackGenerator(style: .soft).impactOccurred()
                #endif
                endLiveVoiceSession()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(BeagleTheme.stateError)
                    .frame(width: 32, height: 32)
                    .background(BeagleTheme.stateError.opacity(0.18), in: Circle())
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Encerrar voz contínua")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .background(.ultraThinMaterial, in: Capsule())
        .overlay(Capsule().strokeBorder(tint.opacity(0.42), lineWidth: 0.85))
        .padding(.horizontal, BeagleSpacing.md)
        .shadow(color: .black.opacity(0.28), radius: 12, y: 4)
    }

    // MARK: - Composer (the only glass)

    private var composer: some View {
        ChatComposer(
            text: $draft,
            depth: $depth,
            attachedImageData: $attachedImageData,
            attachedDocument: $attachedDocument,
            isStreaming: store.isStreaming,
            onSend: send,
            voice: voice,
            // Só o turno FALADO carrega tom. Digitado envia nil, e nil significa
            // "não falei" — não "falei normal".
            onVoiceCommit: { falado in
                handleVoiceCommittedUtterance(falado)
            },
            onWillArmVoice: {
                voz.parar()
            },
            onRequestCamera: {
                #if os(iOS)
                activeSheet = .camera
                #endif
            },
            onRequestScanner: {
                #if os(iOS)
                activeSheet = .documentScanner
                #endif
            }
        )
        .padding(.horizontal, BeagleSpacing.md)
        .padding(.bottom, BeagleSpacing.sm)
        .shadow(color: .black.opacity(0.35), radius: 18, y: 6)   // lift off the surface
    }

    // MARK: - Empty state (warm, zero-friction — no forms)

    private var greeting: some View {
        let story = BodyStory.opening(physioSnapshot, hour: Calendar.current.component(.hour, from: Date()))
        return VStack(spacing: BeagleSpacing.md) {
            VStack(spacing: BeagleSpacing.sm) {
                Text(story.line)
                    .font(BeagleFont.title2.font)
                    .fontWeight(.semibold)
                    .foregroundStyle(BeagleTheme.companionInk)
                    .multilineTextAlignment(.center)
                    .lineSpacing(2)
                Text(story.follow)
                    .font(BeagleFont.callout.font)
                    .foregroundStyle(BeagleTheme.textSecondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, BeagleSpacing.xl)

            quickLaunchCapsules
        }
        .frame(maxWidth: .infinity)
    }

    private var quickLaunchCapsules: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: BeagleSpacing.xs + 2) {
                if let onOpenDailySynthesis {
                    quickLaunchChip(
                        title: DailyBriefingBuilder.cachedTodaySynthesis() != nil ? "Síntese pronta" : "Síntese matinal",
                        systemImage: "sun.horizon.fill",
                        tint: BeagleTheme.postureWarm,
                        action: onOpenDailySynthesis
                    )
                }

                if let onOpenDeepExploration {
                    quickLaunchChip(
                        title: "Modo Fundo",
                        systemImage: "scope",
                        tint: BeagleTheme.truthRemembered,
                        action: onOpenDeepExploration
                    )
                }

                quickLaunchChip(
                    title: liveVoice.isActive ? "Voz ativa" : "Voz mãos-livres",
                    systemImage: "waveform.badge.mic",
                    tint: BeagleTheme.truthObserved
                ) {
                    Task {
                        if liveVoice.isActive {
                            endLiveVoiceSession()
                        } else {
                            await startLiveVoiceSession()
                        }
                    }
                }

                if let onOpenData {
                    let kpLabel: String = {
                        if let kp = weather?.kp {
                            return String(format: "Agora · Kp %.1f", kp)
                        }
                        return "Agora · Corpo & Céu"
                    }()
                    quickLaunchChip(
                        title: kpLabel,
                        systemImage: "sparkles",
                        tint: BeagleTheme.auroraTeal,
                        action: onOpenData
                    )
                }
            }
            .padding(.horizontal, BeagleSpacing.lg)
        }
    }

    private func quickLaunchChip(
        title: String,
        systemImage: String,
        tint: Color,
        action: @escaping () -> Void
    ) -> some View {
        Button {
            #if canImport(UIKit)
            UIImpactFeedbackGenerator(style: .soft).impactOccurred()
            #endif
            action()
        } label: {
            HStack(spacing: 6) {
                Image(systemName: systemImage)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(tint)
                Text(title)
                    .font(BeagleFont.caption.font.weight(.medium))
                    .foregroundStyle(BeagleTheme.companionInk.opacity(0.9))
            }
            .padding(.horizontal, 13)
            .padding(.vertical, 8)
            .background(.ultraThinMaterial, in: Capsule())
            .overlay(Capsule().strokeBorder(tint.opacity(0.28), lineWidth: 0.75))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Agora strip (top bar)

    /// Day-part word for the top bar. Same hour buckets as BodyStory.salutation so the
    /// greeting and the strip never disagree about what time of day it is.
    private var periodWord: String {
        switch Calendar.current.component(.hour, from: Date()) {
        case 5..<12:  return "manhã"
        case 12..<18: return "tarde"
        case 18..<24: return "noite"
        default:      return "madrugada"
        }
    }

    private var hourString: String {
        "\(Calendar.current.component(.hour, from: Date()))h"
    }

    /// Same readiness word the server puts in the model's ## Agora block
    /// (temporal-context.mjs readinessPtBR) — derived from store.physioSummary, NOT
    /// posture, so the strip never contradicts what the model was just told. nil when
    /// there's no HealthKit signal to derive it from (never invents a state).
    private var stateWord: String? {
        switch store.physioSummary?.readiness {
        case .restored: return "recuperado"
        case .steady: return "estável"
        case .strained: return "tenso"
        case .unavailable, .none: return nil
        }
    }

    private var agoraStrip: String {
        var parts = [periodWord, hourString]
        if let stateWord { parts.append(stateWord) }
        return parts.joined(separator: " · ")
    }

    /// Body-as-story snapshot. Reads the wired store (flow ← HRV); `--demo` injects a
    /// realistic body state so the attuned greeting renders without live HealthKit (sim).
    private var physioSnapshot: PhysioSnapshot {
        let args = ProcessInfo.processInfo.arguments
        if args.contains("--demo") || args.contains("--demo-chat") {
            return PhysioSnapshot(sleepQuality: "light", flow: "STRESS", restingHRElevated: true)
        }
        // Real sleep quality (deep+REM ratio) → narrative word, never a number.
        let sleep: String? = store.sleepQuality01.map { q in
            q < 0.35 ? "light" : (q > 0.65 ? "deep" : "ok")
        }.flatMap { $0 == "ok" ? nil : $0 }
        return PhysioSnapshot(sleepQuality: sleep, flow: store.flowState, restingHRElevated: false)
    }

    // MARK: - Shared Inbox (Share Sheet → Chat)

    private func consumeSharedInboxIfNeeded() async {
        guard let loaded = BeagleSharedInbox.dequeueNext() else { return }
        var textParts: [String] = []
        if !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            textParts.append(draft.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        if !loaded.item.text.isEmpty {
            textParts.append(loaded.item.text)
        }
        for url in loaded.item.urls where !textParts.joined(separator: "\n").contains(url) {
            textParts.append(url)
        }
        if !textParts.isEmpty {
            draft = textParts.joined(separator: "\n")
        }
        if let pdfData = loaded.pdfData, !pdfData.isEmpty {
            let fileName = loaded.item.originalPDFName ?? "documento_compartilhado.pdf"
            if let extracted = await ChatDocumentPayload.extract(from: pdfData, fileName: fileName) {
                attachedDocument = extracted
                attachedImageData = nil
            }
        } else if let imgData = loaded.imageData, !imgData.isEmpty {
            attachedImageData = imgData
            attachedDocument = nil
        }
        #if canImport(UIKit)
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        #endif
    }

    // MARK: - Action Button / Siri / Spotlight / Control Center Launch Actions

    private func bindVoiceCallbacks() {
        voice.onCommit = { falado in
            handleVoiceCommittedUtterance(falado)
        }
        voice.onEmptyFinish = {
            guard liveVoice.isActive, liveVoice.phase == .listening else { return }
            let shouldRearm = liveVoice.onEmptySilenceWindow(maxStrikes: 2)
            lastForwardedTranscriptLength = 0
            LiveActivityManager.shared.updateVoiceSession(state: liveVoice)
            guard shouldRearm else { return }
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(220))
                guard liveVoice.isActive, liveVoice.phase == .listening else { return }
                await armNextLiveVoiceTurn()
            }
        }
    }

    private func handleVoiceCommittedUtterance(_ falado: String) {
        store.sinalDeVozDoTurno = voice.sinalDoUltimoTurno
        turnoVeioDeVoz = true
        lastForwardedTranscriptLength = 0
        if liveVoice.isActive {
            liveVoice.voiceLabel = depth.label
            liveVoice.onUserUtteranceCommitted(falado)
            LiveActivityManager.shared.updateVoiceSession(state: liveVoice)
        }
        sendText(falado)
    }

    private func startLiveVoiceSession() async {
        liveVoiceLoopTask?.cancel()
        liveVoiceLoopTask = nil
        if usingGPTLiveFullDuplex || gptLive.isActive {
            await gptLive.stop()
        }
        usingGPTLiveFullDuplex = false
        voz.parar()
        voice.stopQuietly()
        bindVoiceCallbacks()

        lastForwardedTranscriptLength = 0

        let transportMode = CompanionLiveSessionTransportMode(rawValue: liveTransportRaw) ?? .auto
        let wantsGPTLive: Bool = {
            switch transportMode {
            case .gptLiveFullDuplex:
                return true
            case .auto:
                return DirectBrainCredentials.hasOpenAI && NetworkMonitor.shared.isOnline
            case .walkieTalkieTurns:
                return false
            }
        }()

        if wantsGPTLive {
            let rawTimbre = UserDefaults.standard.string(forKey: CompanionVoice.openAIVoiceKey) ?? "marin"
            let normalizedTimbre = CompanionVoice.normalizedLiveVoice(rawTimbre)
            let voiceBadge = "GPT-Live · \(normalizedTimbre.capitalized)"

            gptLive.onTranscriptBubbleUpdate = { role, bubbleId, text, isFinal, tools in
                store.upsertGPTLiveBubble(
                    id: bubbleId,
                    role: role,
                    text: text,
                    isFinal: isFinal,
                    executedTools: tools
                )
            }
            gptLive.onStateChanged = { phase, turns, line in
                guard liveVoice.isActive, usingGPTLiveFullDuplex else { return }
                liveVoice.phase = phase
                liveVoice.turnCount = max(liveVoice.turnCount, turns)
                liveVoice.liveLine = line
                LiveActivityManager.shared.updateVoiceSession(state: liveVoice)
            }
            gptLive.onDelegateToBackend = { delegationCtx in
                let useMoE = (depth == .moe || depth == .fundo)
                return await store.executeGPTLiveDelegation(delegationCtx, useMoE: useMoE)
            }
            store.onVoiceResearchStart = { runId, campaign, slug, totalSteps, activeLens in
                LiveActivityManager.shared.startResearchActivity(
                    runId: runId,
                    campaign: campaign,
                    slug: slug,
                    totalSteps: totalSteps,
                    activeLens: activeLens
                )
            }
            store.onVoiceResearchUpdate = { step, total, eta, activeLens, snippet, isCompleted in
                if isCompleted {
                    LiveActivityManager.shared.endResearchActivity(finalSummary: snippet)
                } else {
                    LiveActivityManager.shared.updateResearchActivity(
                        step: step,
                        total: total,
                        eta: eta,
                        activeLens: activeLens,
                        summarySnippet: snippet
                    )
                }
            }
            store.onTriggerAsyncVoiceFollowup = { spokenSummary, backgroundFacts, tools in
                await gptLive.pushAsyncFollowup(
                    spokenSummary: spokenSummary,
                    backgroundFacts: backgroundFacts,
                    executedTools: tools
                )
            }
            gptLive.onStartupFallbackNeeded = { _ in
                guard liveVoice.isActive, usingGPTLiveFullDuplex else { return }
                usingGPTLiveFullDuplex = false
                Task { @MainActor in
                    await gptLive.stop()
                    guard liveVoice.isActive else { return }
                    liveVoice.voiceLabel = depth.label
                    liveVoice.phase = .listening
                    liveVoice.liveLine = "Rede oscilou — retomando Walkie-Talkie local…"
                    LiveActivityManager.shared.updateVoiceSession(state: liveVoice)
                    await armNextLiveVoiceTurn()
                }
            }

            usingGPTLiveFullDuplex = true
            liveVoice.start(voiceLabel: voiceBadge)
            liveVoice.liveLine = "Conectando ao GPT-Live 1.1 (full-duplex)…"
            LiveActivityManager.shared.startVoiceSession(
                conversationTitle: store.currentConversationTitle,
                voiceLabel: voiceBadge
            )
            LiveActivityManager.shared.updateVoiceSession(state: liveVoice)

            let priorHistory = store.messages.suffix(12).map { (role: $0.role, content: $0.content) }
            let started = await gptLive.start(
                apiKey: DirectBrainCredentials.openAIKey,
                voice: normalizedTimbre,
                priorMessages: priorHistory,
                agoraDeveloperNote: store.buildGPTLiveAgoraNote(),
                greetOnOpen: store.messages.isEmpty
            )

            if started {
                return
            }

            usingGPTLiveFullDuplex = false
            if transportMode == .gptLiveFullDuplex {
                liveVoice.phase = .paused
                liveVoice.liveLine = gptLive.lastError ?? "GPT-Live 1.1 indisponível agora — verifique sua chave OpenAI ou conexão."
                LiveActivityManager.shared.updateVoiceSession(state: liveVoice)
                return
            }

            // Modo Automático: fallback contínuo e silencioso para Walkie-Talkie Offline/Híbrido no hospital
            liveVoice.voiceLabel = depth.label
            liveVoice.phase = .listening
            liveVoice.liveLine = "Modo Walkie-Talkie ativo — pode falar…"
            LiveActivityManager.shared.updateVoiceSession(state: liveVoice)
            await armNextLiveVoiceTurn()
            return
        }

        liveVoice.start(voiceLabel: depth.label)
        LiveActivityManager.shared.startVoiceSession(
            conversationTitle: store.currentConversationTitle,
            voiceLabel: depth.label
        )
        await armNextLiveVoiceTurn()
    }

    private func armNextLiveVoiceTurn() async {
        guard liveVoice.isActive, !usingGPTLiveFullDuplex, liveVoice.phase == .listening else { return }
        let started = await voice.startContinuousTurn()
        if !started && liveVoice.isActive {
            liveVoice.phase = .paused
            liveVoice.liveLine = voice.erro
                ?? voice.motivoDaRecusa
                ?? "Microfone indisponível agora — toque para retomar"
            LiveActivityManager.shared.updateVoiceSession(state: liveVoice)
        }
    }

    private func handleLiveVoiceCommand(_ command: CompanionLiveVoiceCommand) {
        switch command {
        case .togglePause:
            guard liveVoice.isActive else { return }
            if usingGPTLiveFullDuplex {
                let targetPaused = (liveVoice.phase != .paused)
                Task { @MainActor in
                    await gptLive.setPaused(targetPaused)
                }
                return
            }
            liveVoiceLoopTask?.cancel()
            liveVoiceLoopTask = nil
            liveVoice.apply(command: .togglePause)
            lastForwardedTranscriptLength = 0
            LiveActivityManager.shared.updateVoiceSession(state: liveVoice)
            if liveVoice.phase == .paused {
                voz.parar()
                voice.stopQuietly()
            } else if liveVoice.phase == .listening {
                voz.parar()
                Task { await armNextLiveVoiceTurn() }
            }

        case .interruptAndListen:
            guard liveVoice.isActive else { return }
            if usingGPTLiveFullDuplex {
                Task { @MainActor in
                    await gptLive.interruptOutputAndListen()
                }
                return
            }
            liveVoiceLoopTask?.cancel()
            liveVoiceLoopTask = nil
            voz.parar()
            voice.stopQuietly()
            liveVoice.apply(command: .interruptAndListen)
            lastForwardedTranscriptLength = 0
            LiveActivityManager.shared.updateVoiceSession(state: liveVoice)
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(180))
                guard liveVoice.isActive, !usingGPTLiveFullDuplex, liveVoice.phase == .listening else { return }
                await armNextLiveVoiceTurn()
            }

        case .endSession:
            endLiveVoiceSession()
        }
    }

    private func endLiveVoiceSession() {
        let finalTurns = liveVoice.turnCount
        let finalVoiceLabel = liveVoice.voiceLabel
        let wasGPTLive = usingGPTLiveFullDuplex || gptLive.isActive
        usingGPTLiveFullDuplex = false
        liveVoiceLoopTask?.cancel()
        liveVoiceLoopTask = nil
        if wasGPTLive {
            Task { @MainActor in
                await gptLive.stop()
            }
        }
        voz.parar()
        voice.stopQuietly()
        lastForwardedTranscriptLength = 0
        liveVoice.apply(command: .endSession)
        LiveActivityManager.shared.endVoiceSession(
            turnCount: finalTurns,
            voiceLabel: finalVoiceLabel
        )
    }

    private func consumeCompanionLaunchActionIfNeeded() async {
        guard let action = DeepLinkRouter.shared.consumeCompanionAction() else { return }
        activeSheet = nil
        voz.parar()
        bindVoiceCallbacks()

        if action.openNewConversation {
            store.newConversation()
        } else if let convId = action.conversationId, !convId.isEmpty {
            store.switchTo(conversationId: convId)
        }

        if let prompt = action.initialPrompt?.trimmingCharacters(in: .whitespacesAndNewlines),
           !prompt.isEmpty {
            if action.autoSendPrompt {
                sendText(prompt)
            } else {
                draft = prompt
            }
        }

        if action.continuousVoiceSession {
            turnoVeioDeVoz = true
            await startLiveVoiceSession()
        } else if action.startHandsFreeVoice {
            turnoVeioDeVoz = true
            await voice.startHandsFreeFromShortcut()
        }
    }

    // MARK: - Send

    private func send() { sendText(draft) }

    /// The single funnel for a turn, typed, spoken, visual, or PDF. Extracted so voice + attachment commits
    /// inherit the Fundo escalation and voiceModel routing cleanly.
    private func sendText(_ raw: String) {
        // Quem chegou aqui pelo teclado não quer ser interrompido por áudio.
        if !draft.isEmpty && !liveVoice.isActive { turnoVeioDeVoz = false }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let imageToSend = attachedImageData
        let docToSend = attachedDocument
        let hasMedia = (imageToSend != nil || docToSend != nil)
        guard !trimmed.isEmpty || hasMedia else { return }

        let defaultPrompt = docToSend != nil
            ? "Analisa este documento PDF comigo."
            : "Olha esta imagem comigo."
        let text = trimmed.isEmpty ? defaultPrompt : trimmed

        // Fundo = escalate to a full Go-Deeper exploration instead of a chat turn (when text-only and not in hands-free Walkie-Talkie).
        if depth == .fundo && !hasMedia && !liveVoice.isActive {
            draft = ""
            activeSheet = .goDeep(text)
            return
        }
        draft = ""
        attachedImageData = nil
        attachedDocument = nil
        store.voiceModel = (depth == .fundo && (hasMedia || liveVoice.isActive)) ? "moe" : depth.voiceModel
        Task { await store.sendMessage(text, imageData: imageToSend, document: docToSend) }
    }

    private static let bottomAnchor = "companion.chat.bottom"

    private struct TopBarScrollMetrics: Equatable {
        let offsetY: CGFloat
        let containerHeight: CGFloat
        let isScrollable: Bool
    }
}

// MARK: - Sheets

/// The single sheet the chat screen can present. One enum-driven sheet avoids the SwiftUI
/// multiple-`.sheet` conflict (which silently broke the history drawer).
enum ChatSheet: Identifiable {
    case history
    case goDeep(String)   // prompt to explore
    #if os(iOS)
    case camera
    case documentScanner
    #endif
    var id: String {
        switch self {
        case .history: return "history"
        case .goDeep: return "goDeep"
        #if os(iOS)
        case .camera: return "camera"
        case .documentScanner: return "documentScanner"
        #endif
        }
    }
}

// MARK: - Conversation history drawer (Fase 1 polishes: search, rename, pin UI)

/// The thread list — tap to switch, swipe to delete, + to start fresh. Best-in-class history
/// (Claude/ChatGPT) so the chat is many conversations, not one.
struct ConversationDrawer: View {
    let store: ConversationStore
    var onOpenSettings: (() -> Void)?
    var onOpenProject: (() -> Void)?
    var onOpenData: (() -> Void)?
    var onOpenMemory: (() -> Void)?
    var onOpenDreamInsights: (() -> Void)?
    var unreadDreamInsightCount: Int = 0
    var onOpenWork: (() -> Void)?
    var onOpenDailySynthesis: (() -> Void)?
    var onOpenDeepExploration: (() -> Void)?
    @Environment(\.dismiss) private var dismiss
    @State private var reloadToken = 0

    var body: some View {
        NavigationStack {
            List {
                let threads = store.conversations()
                if threads.isEmpty {
                    Text("Nenhuma conversa ainda.")
                        .font(BeagleFont.footnote.font)
                        .foregroundStyle(BeagleTheme.textSecondary)
                } else {
                    ForEach(threads, id: \.id) { conv in
                        Button {
                            store.switchTo(conversationId: conv.id)
                            dismiss()
                        } label: {
                            HStack(spacing: BeagleSpacing.sm) {
                                if conv.pinned {
                                    Image(systemName: "pin.fill")
                                        .font(.system(size: 10))
                                        .foregroundStyle(BeagleTheme.truthRemembered)
                                }
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(conv.displayTitle)
                                        .font(BeagleFont.body.font)
                                        .foregroundStyle(BeagleTheme.companionInk)
                                        .lineLimit(1)
                                    Text(conv.updatedAt, format: .relative(presentation: .named))
                                        .font(BeagleFont.caption2.font)
                                        .foregroundStyle(BeagleTheme.textSecondary)
                                }
                                Spacer()
                                if conv.id == store.currentConversationId {
                                    Image(systemName: "checkmark")
                                        .font(.system(size: 12, weight: .semibold))
                                        .foregroundStyle(BeagleTheme.truthObserved)
                                }
                            }
                        }
                        .swipeActions(edge: .trailing) {
                            Button(role: .destructive) {
                                store.deleteConversation(conv.id); reloadToken += 1
                            } label: { Label("Apagar", systemImage: "trash") }
                        }
                        .swipeActions(edge: .leading) {
                            Button {
                                store.togglePinned(conv.id); reloadToken += 1
                            } label: { Label("Fixar", systemImage: "pin") }
                            .tint(BeagleTheme.truthRemembered)
                        }
                    }
                }
                // Footer: memory + daily synthesis + deep exploration + data screen + settings + project.
                Section {
                    if onOpenDailySynthesis != nil {
                        Button { onOpenDailySynthesis?(); dismiss() } label: {
                            Label("Síntese matinal", systemImage: "sun.horizon.fill")
                        }
                        .foregroundStyle(BeagleTheme.companionInk.opacity(0.9))
                        .accessibilityIdentifier("chat.drawer.dailySynthesisButton")
                    }
                    if onOpenDeepExploration != nil {
                        Button { onOpenDeepExploration?(); dismiss() } label: {
                            Label("Modo Fundo", systemImage: "sparkle.magnifyingglass")
                        }
                        .foregroundStyle(BeagleTheme.companionInk.opacity(0.9))
                        .accessibilityIdentifier("chat.drawer.deepExplorationButton")
                    }
                    if onOpenMemory != nil {
                        Button { onOpenMemory?(); dismiss() } label: {
                            Label("O que eu lembro de ti", systemImage: "brain.head.profile")
                        }
                        .foregroundStyle(BeagleTheme.companionInk.opacity(0.9))
                        .accessibilityIdentifier("chat.drawer.memoryButton")
                    }
                    if onOpenDreamInsights != nil {
                        Button { onOpenDreamInsights?(); dismiss() } label: {
                            HStack {
                                Label("Insights da noite", systemImage: "moon.stars.fill")
                                if unreadDreamInsightCount > 0 {
                                    Spacer()
                                    Text("\(unreadDreamInsightCount)")
                                        .font(BeagleFont.caption2.font)
                                        .foregroundStyle(Color(hue: 270/360, saturation: 0.5, brightness: 0.9))
                                }
                            }
                        }
                        .foregroundStyle(BeagleTheme.companionInk.opacity(0.9))
                        .accessibilityIdentifier("chat.drawer.dreamInsightsButton")
                    }
                    if onOpenData != nil {
                        Button { onOpenData?(); dismiss() } label: {
                            Label("Dados", systemImage: "chart.xyaxis.line")
                        }
                        .foregroundStyle(BeagleTheme.companionInk.opacity(0.9))
                        .accessibilityIdentifier("chat.drawer.dataButton")
                    }
                    if onOpenWork != nil {
                        Button { onOpenWork?(); dismiss() } label: {
                            Label("Trabalho", systemImage: "bolt.fill")
                        }
                        .foregroundStyle(BeagleTheme.companionInk.opacity(0.9))
                        .accessibilityIdentifier("chat.drawer.workButton")
                    }
                    if onOpenProject != nil {
                        Button { onOpenProject?(); dismiss() } label: {
                            Label("Projeto", systemImage: "scope")
                        }
                        .foregroundStyle(BeagleTheme.companionInk.opacity(0.9))
                        .accessibilityIdentifier("chat.drawer.projectButton")
                    }
                    if onOpenSettings != nil {
                        Button { onOpenSettings?(); dismiss() } label: {
                            Label("Configurações", systemImage: "gearshape")
                        }
                        .foregroundStyle(BeagleTheme.companionInk.opacity(0.9))
                        .accessibilityIdentifier("chat.drawer.settingsButton")
                    }
                }
            }
            .id(reloadToken)
            .navigationTitle("Conversas")
            .navigationBarTitleDisplayMode(.inline)
            // Keep the native sheet material (the nice translucent glass) — just force dark so the
            // warm-white text reads. (Flattening to a solid canvas killed the material and the
            // tap targets; reverted.)
            .preferredColorScheme(.dark)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Fechar") { dismiss() }
                        .font(BeagleFont.caption.font)
                        .foregroundStyle(BeagleTheme.textSecondary)
                        .accessibilityIdentifier("chat.drawer.closeButton")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        store.newConversation(); dismiss()
                    } label: { Image(systemName: "square.and.pencil") }
                        .accessibilityLabel("Nova conversa")
                        .accessibilityIdentifier("chat.drawer.newChatButton")
                }
            }
        }
    }
}
