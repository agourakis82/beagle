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
    /// Opens the proactive Synthesis sheet — a deliberate surface, separate from the chat.
    var onOpenSynthesize: (() -> Void)?
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
    /// Opens ThoughtCaptureView (voice→text + Sounio typing) — SAME story as Work: it lived only
    /// in the iPad sidebar, so the iPhone had NO way to capture a thought at all, which is why the
    /// night synthesis stayed starved and the user couldn't dictate. Drawer footer.
    var onOpenCapture: (() -> Void)?
    /// Opens SleepView — last night's HealthKit sleep data (the real "análise do sono").
    var onOpenSleep: (() -> Void)?
    /// Opens the Frota (Mission Control: who needs you). Same trap as Work — it existed only in
    /// the iPad sidebar, i.e. unreachable on the device he actually carries.
    var onOpenFrota: (() -> Void)?
    /// Opens the Oficina (is it green / what broke / where am I).
    var onOpenOficina: (() -> Void)?
    /// Muda quando alguém pede para FALAR de fora (widget, Atalho, botão de Ação).
    /// UUID e não Bool: dois pedidos seguidos precisam disparar duas vezes.
    var pedidoDeVoz: UUID?
    @State private var draft = ""
    /// Quando o estado aconteceu, se ele declarou. Mora AQUI e não no compositor porque
    /// precisa sobreviver aos redesenhos do compositor e ser lida no envio — um estado de
    /// view interno seria zerado no meio do caminho e o turno sairia sem a declaração,
    /// que é o mesmo que não ter o controle.
    @State private var ancoraDoEstado: AncoraTemporal?
    /// Dictation language, toggled by the composer's PT/EN chip. Persisted; pt_BR default.
    @AppStorage("dictationLocaleID") private var dictationLocaleID = "pt_BR"
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
    /// Live dictation for the composer mic (was a dead `onVoice: {}` stub). @Observable +
    /// @MainActor; the transcript streams into `draft` while recording. Set up once via .task.
    @State private var speech = SpeechRecognizer()
    // SOTA-chat #5: send haptic trigger — bumped in send() so .sensoryFeedback fires a
    // discrete light impact on every send, independent of the message store's timing.
    @State private var sendTick = 0
    /// ONE sheet for the whole screen — multiple `.sheet(isPresented:)` on the same view conflict
    /// in SwiftUI (the second silently breaks the first, which is why the drawer stopped opening).
    @State private var activeSheet: ChatSheet?
    /// The companion's gear for the next message (voice model, or Fundo → Go-Deeper).
    @State private var depth: ChatDepth = .sonnet
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
                onOpenCapture: (() -> Void)? = nil,
                onOpenSleep: (() -> Void)? = nil,
                onOpenSynthesize: (() -> Void)? = nil,
                onOpenFrota: (() -> Void)? = nil,
                onOpenOficina: (() -> Void)? = nil,
                pedidoDeVoz: UUID? = nil) {
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
        self.onOpenCapture = onOpenCapture
        self.onOpenSleep = onOpenSleep
        self.onOpenSynthesize = onOpenSynthesize
        self.onOpenFrota = onOpenFrota
        self.onOpenOficina = onOpenOficina
        self.pedidoDeVoz = pedidoDeVoz
    }

    /// A emoção MEDIDA agora — valência que ele registrou, ativação do corpo.
    /// `nil` quando falta eixo: o servidor cai na direção neutra, e ninguém encena
    /// um estado que não foi medido.
    private var vetorDeEmocao: VetorDeEmocao? {
        VetorDeEmocao.de(valencia: posture?.stateOfMind,
                         readiness: posture?.readiness,
                         medidoEm: posture?.observedAt)
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

    private var presenceState: PresenceState {
        PresenceResolver(
            isStreaming: store.isStreaming,
            isVoiceListening: voice.isListening,
            composerFocused: !draft.isEmpty,
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
            // Layer 4: minimal top bar — history · title · new. Floats over the aurora.
            topBar
            // Layer 5: composer pinned to the bottom. No body strip — body/sky/ambient data
            // lives on its own screen now; the chat is just conversation.
            composer
        }
        // Entry ceremony — the space materializes with a breath instead of snapping in
        // (Gaggioli: ceremony over frictionless).
        .opacity(appeared ? 1 : 0)
        .scaleEffect(appeared ? 1 : 0.985, anchor: .bottom)
        .task {
            if ProcessInfo.processInfo.arguments.contains("--demo-chat") {
                store.seedDemoConversation()
            }
            // Warm the on-device speech assets now so the first hold doesn't eat the first
            // three words. Fire-and-forget and time-boxed inside the controller.
            voice.prewarm()

            // O que ele deixou. Em Task separada de propósito: a síntese leva
            // dezenas de segundos e NUNCA pode atrasar a tela abrir. Se falhar,
            // falha calada — a chegada é um presente, não um requisito.
            Task { await chegada.buscarSeForHora() }
        }
        .onChange(of: store.isStreaming) { antes, agora in
            // Fim do turno: se ele FALOU, ele ouve de volta.
            guard antes, !agora, turnoVeioDeVoz else { return }
            turnoVeioDeVoz = false
            guard let ultima = store.messages.last,
                  ultima.role == .assistant,
                  !ultima.content.isEmpty else { return }
            Task { await voz.falar(ultima.content, id: ultima.id.uuidString, vetor: vetorDeEmocao) }
        }
        .onDisappear {
            // Sair da tela cala a boca. Áudio tocando numa tela que ele fechou é
            // o app falando sozinho.
            voz.parar()
        }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { voice.handleResignActive() }
            if phase == .active { lastInteraction = .now; idleTick = .now }
        }
        .onChange(of: draft) { _, _ in lastInteraction = .now }
        .onChange(of: store.messages.count) { _, _ in lastInteraction = .now }
        // 30s é grosso de propósito: só existe para a ociosidade poder virar
        // `adormecido`. Nada de animação depende disto.
        .onReceive(Timer.publish(every: 30, on: .main, in: .common).autoconnect()) { now in
            idleTick = now
        }
        // PEDIDO DE VOZ VINDO DE FORA. O widget não grava áudio — o iOS não
        // deixa. O mais perto possível é o app abrir JÁ OUVINDO, e é isto: o
        // toque no widget vira um turno de voz sem passar por tela nenhuma.
        .onChange(of: pedidoDeVoz) { _, novo in
            guard novo != nil else { return }
            Task { await voice.toggleLatched() }
        }
        .onAppear {
            withAnimation(.easeOut(duration: 0.55)) { appeared = true }
            #if DEBUG
            semearParaInspecao()
            #endif
        }
        // SOTA-chat #5: subtle haptics via iOS 17 .sensoryFeedback (state-triggered, no
        // generators to manage). Light impact on send; a discrete success at the moment the
        // stream finishes (isStreaming true → false). Adult register — never festive.
        .sensoryFeedback(.impact(weight: .light), trigger: sendTick)
        .sensoryFeedback(trigger: store.isStreaming) { wasStreaming, isStreaming in
            (wasStreaming && !isStreaming) ? .success : nil
        }
        .sheet(item: $activeSheet) { sheet in
            switch sheet {
            case .history:
                ConversationDrawer(buscaInicial: argumentoDepois("-buscaDemo"), store: store, onOpenSettings: onOpenSettings, onOpenProject: onOpenProject, onOpenData: onOpenData, onOpenMemory: onOpenMemory, onOpenDreamInsights: onOpenDreamInsights, unreadDreamInsightCount: unreadDreamInsightCount, onOpenWork: onOpenWork, onOpenCapture: onOpenCapture, onOpenSleep: onOpenSleep, onOpenSynthesize: onOpenSynthesize, onOpenFrota: onOpenFrota, onOpenOficina: onOpenOficina)
            case .goDeep(let prompt):
                GoDeepView(store: composerGoDeepStore, prompt: prompt)
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
                topBarButton("line.3.horizontal") { activeSheet = .history }
                Spacer(minLength: BeagleSpacing.sm)
                VStack(spacing: 2) {
                    Text(store.currentConversationTitle)
                        .font(BeagleFont.subheadline.font.weight(.semibold))
                        .foregroundStyle(BeagleTheme.companionInk)
                        .lineLimit(1)
                        .truncationMode(.tail)
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
                topBarButton("square.and.pencil") {
                    withAnimation(.easeOut(duration: 0.25)) { store.newConversation() }
                }
            }
            .padding(.horizontal, BeagleSpacing.md)
            .padding(.top, BeagleSpacing.sm)
            // Melt away while reading forward; glide back on scroll-up.
            .opacity(topBarHidden ? 0 : 1)
            .offset(y: topBarHidden ? -72 : 0)
            .blur(radius: topBarHidden ? 6 : 0)

            // Tempo · corpo · céu. Fica logo abaixo da barra e some junto com ela
            // quando você lê para a frente — as duas são cromo, e cromo se dissolve
            // no conteúdo.
            //
            // Isto NÃO é a antiga tira de corpo que foi retirada daqui: aquela era
            // permanente acima do compositor. Esta nasce recolhida — em repouso é só
            // um traço — e só se abre para quem a procura. É a regra do contrato:
            // "a faixa é porta", e o estado se revela por gesto.
            FaixaDeEstado(breath: breath, sky: weather?.band)
                .opacity(topBarHidden ? 0 : 1)
                .offset(y: topBarHidden ? -72 : 0)
                .animation(.easeOut(duration: 0.22), value: topBarHidden)

            Spacer()
        }
    }

    private func topBarButton(_ system: String, action: @escaping () -> Void) -> some View {
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
    }

    // Aurora CURTAIN sitting BEHIND the conversation. Spans the full width;
    // drifts horizontally, ripples vertically, hue cycles, brightens when the
    // companion is streaming. Empty state: brighter and fills upper half.
    // Chatting: dimmer and pulled to upper third so the conversation reads.
    /// O estado do bicho. Entradas que este ramo não tem (ocioso, hora, céu medido)
    /// ficam no padrão do resolvedor — ele degrada para um estado calmo em vez de
    /// exigir tudo. Ligar o que existe hoje e crescer depois é melhor que não ligar.
    private var presenceBackground: some View {
        let empty = store.messages.isEmpty
        // CADA CAMADA TEM A SUA OPACIDADE.
        //
        // Havia um `.opacity(empty ? 0.9 : 0.28)` único no retorno da propriedade.
        // Herdá-lo deixaria o BICHO a 28% justamente enquanto se lê — o efeito
        // fantasma. A aurora pode ser cenário; ele não.
        return ZStack {
            // O CHÃO DE LUZ. Vem antes de tudo porque é o ambiente, não um elemento:
            // é a brasa que o bicho espalha, ancorada onde fica o coração dele.
            // Sem ela o bicho flutua sobre um retângulo chapado — foi exatamente o
            // que fez a primeira versão do desenho parecer pobre.
            EmberField(breath: breath, intensity: empty ? 1.0 : 0.22)
                .animation(.easeOut(duration: 0.6), value: empty)

            // Atrás: a aurora continua (foi construída de propósito e ele gosta dela),
            // mas rebaixada a cenário do cenário para não virar sopa visual.
            AuroraPresence(
                breath: breath,
                weather: weather,
                isStreaming: store.isStreaming,
                size: empty ? .greeter : .header
            )
            .opacity(empty ? 0.55 : 0.08)
            .animation(.easeOut(duration: 0.35), value: empty)

            // Na frente: o bicho. Máscara radial e curva própria de opacidade vivem
            // dentro de PrimordialPresence.
            PrimordialPresence(
                state: presenceState,
                breath: breath,
                sky: weather?.band ?? .calm
            )
            .opacity(empty ? 0.95 : 0.13)
            .animation(.easeOut(duration: 0.35), value: empty)
        }
        // VISTO no simulador, com a conversa dentro: o texto ficava escrito por cima da CARA do
        // cão — pelagem clara sob texto claro, sem nada separando. As opacidades de antes
        // (bicho 0.55, brasas 0.62) foram pensadas como "recuo", mas 0.55 de uma imagem com
        // esse contraste ainda é uma imagem no meio da leitura.
        //
        // Decisão dele: o cão FICA durante a conversa, mas como presença, não como concorrente.
        // Por isso três coisas juntas, e nenhuma sozinha bastaria:
        //   - opacidade muito menor (0.13 / 0.22 / 0.08);
        //   - desfoque, que mata a competição de DETALHE — é a borda nítida do olho e do focinho
        //     que puxa o olhar, não o brilho;
        //   - um véu escuro por cima, que garante contraste mínimo onde a pelagem é clara.
        //
        // Na tela VAZIA nada disso se aplica: ali ele aparece inteiro e nítido, que é onde ele
        // é bonito e não atrapalha ninguém.
        .blur(radius: store.messages.isEmpty ? 0 : 9)
        .animation(.easeOut(duration: 0.4), value: store.messages.isEmpty)
        .overlay {
            Color.black
                .opacity(store.messages.isEmpty ? 0 : 0.34)
                .animation(.easeOut(duration: 0.4), value: store.messages.isEmpty)
                .allowsHitTesting(false)
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
                    if store.isStreaming, let note = store.presenceNote, !note.isEmpty {
                        // VISTO no simulador: a nota flutuava lá embaixo, colada no
                        // compositor e a um `lg` inteiro de distância das bolinhas — duas
                        // coisas sem relação aparente, quando são a MESMA coisa (ele está
                        // aqui, e isto é o que está fazendo). O recuo passa a ser o mesmo do
                        // texto da resposta, e o topo negativo cancela o `spacing: lg` da
                        // pilha só para este item, encostando a nota na espera.
                        Text(note)
                            .font(BeagleFont.footnote.font.italic())
                            .foregroundStyle(BeagleTheme.textTertiary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.leading, BeagleSpacing.md + 3)
                            .padding(.top, -(BeagleSpacing.lg - BeagleSpacing.xxs))
                            .transition(.opacity)
                    }
                    // clearance so the floating composer never covers the last line
                    Color.clear.frame(height: 72).id(Self.bottomAnchor)
                }
                .padding(.horizontal, BeagleSpacing.md)
                .padding(.top, BeagleSpacing.md)
                .frame(maxWidth: .infinity, minHeight: 0, alignment: .bottom)
                .animation(.easeOut(duration: 0.25), value: store.messages.count)
            }
            .defaultScrollAnchor(.bottom)   // recent messages hug the composer; void goes up top
            // `.immediately` e não `.interactively`: o modo interativo faz o teclado
            // seguir o dedo, e num chat a lista já está no fim — o gesto vira rolagem
            // e o teclado nunca sai. Rolar tem que fechar, ponto. Ele relatou que não
            // conseguia LER a conversa, que é metade do uso.
            .scrollDismissesKeyboard(.immediately)
            // Direction-based chrome melt: finger up (offset grows → reading forward) hides the
            // top bar; finger down (offset shrinks → going back) reveals it. Anchor-agnostic.
            .onScrollGeometryChange(for: CGFloat.self) { geo in
                geo.contentOffset.y
            } action: { oldY, newY in
                let delta = newY - oldY
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
            // SOTA-chat #1: the instant a send starts, isStreaming flips true with an empty
            // assistant snapshot (the "pensando" indicator). Scroll it into view immediately so
            // the thinking state is visible at the moment of send, before the first token.
            .onChange(of: store.isStreaming) { _, isStreaming in
                if isStreaming {
                    withAnimation(.smooth) { proxy.scrollTo(Self.bottomAnchor, anchor: .bottom) }
                }
            }
            // SOTA-chat #3: springs (.smooth, bounce 0) instead of .easeOut so an in-flight
            // scroll FUSES with the next token or a user drag — the animation carries velocity
            // and blends rather than restarting/stuttering on every snapshot.
            .onChange(of: store.messages.last?.content) { _, _ in
                withAnimation(.smooth) { proxy.scrollTo(Self.bottomAnchor, anchor: .bottom) }
            }
            .onChange(of: store.messages.count) { _, _ in
                // SOTA-chat #3: interruptible spring for the new-message jump too.
                withAnimation(.smooth) { proxy.scrollTo(Self.bottomAnchor, anchor: .bottom) }
                // A fresh turn brings the bar back so the title/controls are always reachable.
                if topBarHidden { withAnimation(.easeOut(duration: 0.28)) { topBarHidden = false } }
            }
        }
    }

    // MARK: - Composer (the only glass)

    private var composer: some View {
        ChatComposer(
            text: $draft,
            depth: $depth,
            isStreaming: store.isStreaming,
            onSend: send,
            voice: voice,
            // Só o turno FALADO carrega tom. Digitado envia nil, e nil significa
            // "não falei" — não "falei normal".
            onVoiceCommit: { falado in
                store.sinalDeVozDoTurno = voice.sinalDoUltimoTurno
                turnoVeioDeVoz = true
                sendText(falado)
            },
            // O chip PT/EN sobreviveu à fusão: o localeID atravessa VoiceTurnController →
            // startRecording(localeID:) até o reconhecedor. Sem isso o botão ficaria
            // desenhado e mudo. A ordem aqui segue a da DECLARAÇÃO em ChatComposer —
            // Swift exige, e foi o último erro que o build pegou.
            dictationLocaleID: dictationLocaleID,
            onToggleLocale: { dictationLocaleID = dictationLocaleID.hasPrefix("en") ? "pt_BR" : "en_US" },
            ancora: $ancoraDoEstado
        )
        .padding(.horizontal, BeagleSpacing.md)
        .padding(.bottom, BeagleSpacing.sm)
        .shadow(color: .black.opacity(0.35), radius: 18, y: 6)   // lift off the surface
        .task { await speech.setup() }
        // Voice→text: stream the live transcript into the field while dictating. The mic only
        // appears when the field is empty, so this never clobbers typed text.
        .onChange(of: speech.transcript) { _, newValue in
            if speech.isRecording { draft = newValue }
        }
    }

    /// Toggle dictation: tap the mic to start (transcript streams into `draft`), tap Stop to end;
    /// the text then stays in the field to edit or send. Reuses the same SpeechRecognizer as capture.
    private func toggleVoice() {
        if speech.isRecording {
            speech.stopRecording()
        } else {
            Task { await speech.startRecording(localeID: dictationLocaleID) }
        }
    }

    // MARK: - Empty state (warm, zero-friction — no forms)

    private var greeting: some View {
        let story = BodyStory.opening(physioSnapshot, hour: Calendar.current.component(.hour, from: Date()))
        return VStack(spacing: BeagleSpacing.sm) {
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
        .frame(maxWidth: .infinity)
        .padding(.horizontal, BeagleSpacing.xl)
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

    // MARK: - Send

    /// Lê o valor que vem depois de uma chave nos argumentos de lançamento. Fora de DEBUG
    /// nenhum chamador passa essas chaves, então devolve nil.
    private func argumentoDepois(_ chave: String) -> String? {
        #if DEBUG
        let args = ProcessInfo.processInfo.arguments
        guard let i = args.firstIndex(of: chave), i + 1 < args.count else { return nil }
        return args[i + 1]
        #else
        return nil
        #endif
    }

    #if DEBUG
    /// Semeia a tela para INSPEÇÃO VISUAL no simulador. Só existe em DEBUG.
    ///
    /// Existe porque entreguei três builds sem nunca ter visto a interface — e cada defeito
    /// custou um ciclo dele: instalar, testar, relatar. O `simctl` não digita e clicar por
    /// coordenada é frágil; sem este gancho não há como capturar a tela num estado realista.
    ///
    /// Não toca a rede: as mensagens são montadas em memória. Isso é deliberado — mandar uma
    /// frase de teste pelo caminho real gravaria no corpus dele um "auto-relato" que ele nunca
    /// fez, e a Fase 2 mede exatamente isso.
    ///
    ///   -rascunhoInicial "dormi mal essa noite"   → põe o texto no campo
    ///   -conversaDemo                             → popula um fio de exemplo
    private func semearParaInspecao() {
        let args = ProcessInfo.processInfo.arguments
        if let i = args.firstIndex(of: "-rascunhoInicial"), i + 1 < args.count {
            draft = args[i + 1]
        }
        if args.contains("-conversaDemo"), store.messages.isEmpty {
            store.semearConversaDeInspecao()
        }
        // `-esperaDemo` congela a tela no instante em que ele mais reclama: depois de enviar,
        // antes do primeiro token. `-comPresenca` acrescenta a nota de presença.
        if args.contains("-historicoDemo") {
            store.semearHistoricoDeInspecao()
            activeSheet = .history
        }
        if args.contains("-esperaDemo"), store.messages.isEmpty {
            store.semearEsperaDeInspecao(comPresenca: args.contains("-comPresenca"))
        }
    }
    #endif

    private func send() { sendText(draft) }

    /// The single funnel for a turn, typed or spoken. Extracted so the voice commit inherits
    /// the Fundo escalation and the voiceModel routing instead of quietly duplicating them.
    private func sendText(_ raw: String) {
        // Quem chegou aqui pelo teclado não quer ser interrompido por áudio.
        if !draft.isEmpty { turnoVeioDeVoz = false }
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        // SOTA-chat #5: fire the light send haptic for any committed send (chat turn or Fundo).
        sendTick &+= 1
        // Fundo = escalate to a full Go-Deeper exploration instead of a chat turn.
        if depth == .fundo {
            draft = ""
            activeSheet = .goDeep(text)
            return
        }
        draft = ""
        // O instante é resolvido AGORA, no envio, e não quando ele tocou a âncora: entre uma
        // coisa e outra pode passar tempo redigindo, e "há 1h" congelado no toque gravaria a
        // hora de uma decisão de interface. Ver InstanteDoEstado.swift.
        store.instanteDeclarado = InstanteDeclarado(ancora: ancoraDoEstado)
        // Zera com o rascunho, pela mesma razão: âncora que sobrevive ao envio declararia o
        // instante do turno anterior no próximo, em silêncio.
        ancoraDoEstado = nil
        store.voiceModel = depth.voiceModel   // Rápido → default voice; Pensar → stronger model
        store.deepThink = depth.isDeepThink    // Agente → agentic read-only tool path (server side)
        Task { await store.sendMessage(text) }
    }

    private static let bottomAnchor = "companion.chat.bottom"
}

// MARK: - Sheets

/// The single sheet the chat screen can present. One enum-driven sheet avoids the SwiftUI
/// multiple-`.sheet` conflict (which silently broke the history drawer).
enum ChatSheet: Identifiable {
    case history
    case goDeep(String)   // prompt to explore
    var id: String {
        switch self {
        case .history: return "history"
        case .goDeep: return "goDeep"
        }
    }
}

// MARK: - Conversation history drawer (Fase 1 polishes: search, rename, pin UI)

/// The thread list — tap to switch, swipe to delete, + to start fresh. Best-in-class history
/// (Claude/ChatGPT) so the chat is many conversations, not one.
struct ConversationDrawer: View {
    /// Termo de busca inicial, para capturar a busca FUNCIONANDO no simulador.
    ///
    /// Existe porque a alternativa — clicar por coordenada e digitar com AppleScript — errou o
    /// alvo, caiu no compositor e ENVIOU UMA MENSAGEM REAL pelo caminho de produção. Não chegou
    /// ao corpus, mas podia ter chegado. Argumento de lançamento é determinístico e não toca a
    /// rede; clique cego num app ligado ao servidor real, não é.
    var buscaInicial: String?
    let store: ConversationStore
    var onOpenSettings: (() -> Void)?
    var onOpenProject: (() -> Void)?
    var onOpenData: (() -> Void)?
    var onOpenMemory: (() -> Void)?
    var onOpenDreamInsights: (() -> Void)?
    var unreadDreamInsightCount: Int = 0
    var onOpenWork: (() -> Void)?
    var onOpenCapture: (() -> Void)?
    var onOpenSleep: (() -> Void)?
    var onOpenSynthesize: (() -> Void)?
    /// Opens the Frota (Mission Control: who needs you). Same trap as Work — it existed only in
    /// the iPad sidebar, i.e. unreachable on the device he actually carries.
    var onOpenFrota: (() -> Void)?
    /// Opens the Oficina (is it green / what broke / where am I).
    var onOpenOficina: (() -> Void)?
    @Environment(\.dismiss) private var dismiss

    /// A lista lida da última recarga. Era `store.conversations()` chamado dentro do `body` mais
    /// um `.id(reloadToken)` na `List`, que reconstrói a lista INTEIRA a cada fixar/apagar —
    /// perdendo a posição de rolagem e, agora que existe busca, derrubando o teclado e o termo
    /// digitado. Estado explícito com recarga explícita não tem esse efeito.
    @State private var fios: [PersistedConversation] = []
    @State private var busca = ""

    @State private var renomeando: PersistedConversation?
    @State private var nomeNovo = ""

    var body: some View {
        NavigationStack {
            List {
                // A NAVEGAÇÃO VEM ANTES DOS FIOS. Ela tem contagem fixa (onze destinos); os fios
                // crescem sem limite. Embaixo, como estava, "Sono" e "Dados" afundavam um pouco
                // mais a cada conversa — VISTO no simulador: com sete fios a seção já saía da
                // tela, e ele conversa todo dia.
                destinos

                if visiveis.isEmpty {
                    Text(busca.isEmpty ? "Nenhuma conversa ainda." : "Nada encontrado.")
                        .font(BeagleFont.footnote.font)
                        .foregroundStyle(BeagleTheme.textSecondary)
                } else {
                    ForEach(grupos, id: \.titulo) { grupo in
                        Section(grupo.titulo) {
                            ForEach(grupo.fios, id: \.id) { conv in linha(conv) }
                        }
                    }
                }
            }
            .searchable(text: $busca, prompt: "Buscar nas conversas")
            .onAppear {
                recarregar()
                if let s = buscaInicial, busca.isEmpty { busca = s }
            }
            .alert("Renomear conversa", isPresented: Binding(
                get: { renomeando != nil },
                set: { if !$0 { renomeando = nil } }
            )) {
                TextField("Título", text: $nomeNovo)
                Button("Cancelar", role: .cancel) { renomeando = nil }
                Button("Salvar") {
                    // `renameConversation` existia no store e NÃO TINHA UM ÚNICO CHAMADOR —
                    // mecanismo completo cobrindo nada, o mesmo padrão do `requeueFromDlq`.
                    // Este botão é o chamador.
                    let limpo = nomeNovo.trimmingCharacters(in: .whitespacesAndNewlines)
                    if let c = renomeando, !limpo.isEmpty { store.renameConversation(c.id, title: limpo) }
                    renomeando = nil
                    recarregar()
                }
            }
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
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        store.newConversation(); dismiss()
                    } label: { Image(systemName: "square.and.pencil") }
                }
            }
        }
    }

    private func recarregar() { fios = store.conversations() }

    /// Fios vazios não entram: cada toque no ＋ que não virou conversa deixava uma linha
    /// "Nova conversa" no histórico para sempre. O fio CORRENTE é a exceção — ele pode estar
    /// vazio porque ele acabou de abrir e ainda vai falar.
    private var visiveis: [PersistedConversation] {
        let vivos = fios.filter { !($0.title ?? "").isEmpty || $0.id == store.currentConversationId }
        let termo = busca.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !termo.isEmpty else { return vivos }
        // Busca pelo TÍTULO, que é a primeira linha dele (48 caracteres, gravada por
        // `touchConversationRecord`). NÃO varre o corpo das mensagens: isso exigiria um fetch
        // por fio e o store não expõe essa consulta. Limite conhecido, não descuido.
        return vivos.filter { $0.displayTitle.localizedCaseInsensitiveContains(termo) }
    }

    private struct Grupo: Identifiable {
        let titulo: String
        let fios: [PersistedConversation]
        var id: String { titulo }
    }

    /// Fixadas primeiro; o resto em faixas de tempo. Uma data relativa por linha não substitui
    /// cabeçalho — é o cabeçalho que torna a rolagem orientável quando os fios passam de dezenas.
    private var grupos: [Grupo] {
        let cal = Calendar.current
        let agora = Date()
        var fixadas: [PersistedConversation] = []
        var hoje: [PersistedConversation] = []
        var ontem: [PersistedConversation] = []
        var semana: [PersistedConversation] = []
        var mes: [PersistedConversation] = []
        var antes: [PersistedConversation] = []
        for c in visiveis {
            if c.pinned { fixadas.append(c); continue }
            if cal.isDateInToday(c.updatedAt) { hoje.append(c) }
            else if cal.isDateInYesterday(c.updatedAt) { ontem.append(c) }
            else {
                let dias = cal.dateComponents([.day], from: c.updatedAt, to: agora).day ?? 0
                if dias < 7 { semana.append(c) }
                else if dias < 30 { mes.append(c) }
                else { antes.append(c) }
            }
        }
        return [
            Grupo(titulo: "Fixadas", fios: fixadas),
            Grupo(titulo: "Hoje", fios: hoje),
            Grupo(titulo: "Ontem", fios: ontem),
            Grupo(titulo: "Últimos 7 dias", fios: semana),
            Grupo(titulo: "Últimos 30 dias", fios: mes),
            Grupo(titulo: "Antes", fios: antes)
        ].filter { !$0.fios.isEmpty }
    }

    @ViewBuilder
    private func linha(_ conv: PersistedConversation) -> some View {
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
                store.deleteConversation(conv.id); recarregar()
            } label: { Label("Apagar", systemImage: "trash") }
        }
        .swipeActions(edge: .leading) {
            Button {
                store.togglePinned(conv.id); recarregar()
            } label: { Label(conv.pinned ? "Soltar" : "Fixar", systemImage: "pin") }
            .tint(BeagleTheme.truthRemembered)
            Button {
                nomeNovo = conv.displayTitle
                renomeando = conv
            } label: { Label("Renomear", systemImage: "pencil") }
            .tint(BeagleTheme.companionInk.opacity(0.55))
        }
    }

    private struct Destino: Identifiable {
        let rotulo: String
        let icone: String
        let selo: Int
        let acao: () -> Void
        var id: String { rotulo }
    }

    private var listaDeDestinos: [Destino] {
        var d: [Destino] = []
        func mais(_ rotulo: String, _ icone: String, _ selo: Int = 0, _ f: (() -> Void)?) {
            guard let f else { return }
            d.append(Destino(rotulo: rotulo, icone: icone, selo: selo, acao: { dismiss(); f() }))
        }
        mais("Capturar", "mic.fill", 0, onOpenCapture)
        mais("Sintetizar", "sparkles", 0, onOpenSynthesize)
        mais("Sono", "bed.double.fill", 0, onOpenSleep)
        mais("Memória", "brain.head.profile", 0, onOpenMemory)
        mais("Noite", "moon.stars.fill", unreadDreamInsightCount, onOpenDreamInsights)
        mais("Dados", "chart.xyaxis.line", 0, onOpenData)
        mais("Frota", "dot.radiowaves.left.and.right", 0, onOpenFrota)
        mais("Oficina", "wrench.and.screwdriver", 0, onOpenOficina)
        mais("Trabalho", "bolt.fill", 0, onOpenWork)
        mais("Projeto", "scope", 0, onOpenProject)
        mais("Ajustes", "gearshape", 0, onOpenSettings)
        return d
    }

    /// Os onze destinos do app, em UMA LINHA rolável.
    ///
    /// Eram onze linhas de `List`. Embaixo dos fios, afundavam um pouco mais a cada conversa
    /// ("Sono" e "Dados" já saíam da tela com sete fios). Movidos para cima, VISTO no simulador,
    /// fizeram o contrário e pior: ocupavam a tela inteira e empurravam TODAS as conversas para
    /// fora da dobra — a gaveta de conversas deixava de mostrar conversas.
    ///
    /// O erro nos dois casos era tratar contagem fixa como custo fixo. Onze destinos empilhados
    /// custam onze alturas de linha; em faixa horizontal custam uma. Assim os fios — que são o
    /// motivo da tela existir — começam logo abaixo do topo, e nenhum destino fica inalcançável.
    @ViewBuilder
    private var destinos: some View {
        Section {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: BeagleSpacing.md) {
                    ForEach(listaDeDestinos) { d in
                        Button(action: d.acao) {
                            VStack(spacing: 5) {
                                ZStack(alignment: .topTrailing) {
                                    Image(systemName: d.icone)
                                        .font(.system(size: 17, weight: .regular))
                                        .frame(width: 44, height: 44)
                                        .background(
                                            Circle().fill(BeagleTheme.companionInk.opacity(0.10)))
                                    if d.selo > 0 {
                                        Text("\(d.selo)")
                                            .font(.system(size: 10, weight: .semibold))
                                            .foregroundStyle(.black)
                                            .padding(4)
                                            .background(Circle().fill(
                                                Color(hue: 270/360, saturation: 0.5, brightness: 0.9)))
                                            .offset(x: 3, y: -3)
                                    }
                                }
                                Text(d.rotulo)
                                    .font(BeagleFont.caption2.font)
                                    .lineLimit(1)
                            }
                            .foregroundStyle(BeagleTheme.companionInk.opacity(0.9))
                            // Sem isto a área de toque é só o glifo — o defeito que já deixou um
                            // botão morto na tela de chat.
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, BeagleSpacing.md)
                .padding(.vertical, BeagleSpacing.xs)
            }
            .listRowInsets(EdgeInsets())
            .listRowBackground(Color.clear)
        }
    }
}
