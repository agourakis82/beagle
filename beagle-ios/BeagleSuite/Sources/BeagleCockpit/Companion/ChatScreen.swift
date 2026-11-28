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
    @State var draft = ""
    @State var attachedImageData: Data?
    @State var attachedDocument: ChatDocumentPayload?
    /// Última vez que o usuário mexeu em alguma coisa. `nil` → ainda não mexeu nesta
    /// sessão, e nesse caso a presença NÃO adormece (abrir o app e ficar lendo não é
    /// abandono).
    @State private var lastInteraction: Date?
    /// Relógio grosso (30s) só para a ociosidade poder virar `adormecido` sem que nada
    /// mais na tela mude. Não é um timer de animação.
    @State private var idleTick = Date()
    /// The voice turn. Owned by the screen so a composer redraw never drops a live recording.
    @State var voice = VoiceTurnController()
    @State private var appeared = false
    /// ONE sheet for the whole screen — multiple `.sheet(isPresented:)` on the same view conflict
    /// in SwiftUI (the second silently breaks the first, which is why the drawer stopped opening).
    @State var activeSheet: ChatSheet?
    /// Action queued by `ConversationDrawer` to fire only after its UIKit dismissal completes,
    /// avoiding parent/child sheet presentation collisions.
    @State var pendingDrawerAction: (() -> Void)?
    /// The companion's gear for the next message (voice model, or Fundo → Go-Deeper).
    /// Persisted in @AppStorage so his choice (MoE / GPT 5.5 / Local Sem Censura / Sonnet 5) survives app restarts.
    @AppStorage("beagle.chat.depth") var depth: ChatDepth = .moe
    @State var composerGoDeepStore = GoDeepStore()
    /// The top bar melts away while you read forward and returns when you scroll back up — the
    /// "chrome dissolves into the content" feel (Claude/Safari). Driven by scroll direction below.
    @State var topBarHidden = false
    /// Accumulated scroll in the current direction — the bar only flips after a deliberate
    /// gesture (not a twitch), so it doesn't vanish on the slightest touch.
    @State var scrollAccum: CGFloat = 0
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
    @State var chegada = ArrivalStore()
    @State var voz = CompanionVoice()
    @State var chegadaAberta = false
    /// O turno atual começou por FALA. É isto que decide se ele responde em voz.
    ///
    /// Se ele falou, quer ouvir — está andando, com a tela longe dos olhos, e foi
    /// essa a queixa que abriu o desenho. Se ele digitou, falar sozinho seria
    /// intromissão: quem digita está olhando.
    @State var turnoVeioDeVoz = false
    @AppStorage(CompanionVoice.autoSpeakModeKey) var autoSpeakRaw: String = CompanionAutoSpeakMode.whenSpoken.rawValue
    @AppStorage(CompanionLiveSessionTransportMode.storageKey) var liveTransportRaw: String = CompanionLiveSessionTransportMode.auto.rawValue
    /// Sessão de Voz Contínua Mãos-Livres (GPT-Live 1.1 Full-Duplex ou Walkie-Talkie Offline)
    @State var liveVoice = CompanionLiveVoiceSessionState()
    @State var gptLive = OpenAILiveVoiceSession()
    @State var usingGPTLiveFullDuplex = false
    @State var liveVoiceLoopTask: Task<Void, Never>?
    @State var lastForwardedTranscriptLength: Int = 0

    var presenceState: PresenceState {
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
            handleStreamingFinished()
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
            sheetContent(for: sheet)
        }
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

    func send() { sendText(draft) }

    /// The single funnel for a turn, typed, spoken, visual, or PDF. Extracted so voice + attachment commits
    /// inherit the Fundo escalation and voiceModel routing cleanly.
    func sendText(_ raw: String) {
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
}
