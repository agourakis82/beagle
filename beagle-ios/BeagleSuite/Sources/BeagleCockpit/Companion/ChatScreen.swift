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
    /// Opens the Frota (Mission Control: who needs you). Same trap as Work — it existed only in
    /// the iPad sidebar, i.e. unreachable on the device he actually carries.
    var onOpenFrota: (() -> Void)?
    /// Opens the Oficina (is it green / what broke / where am I).
    var onOpenOficina: (() -> Void)?
    @State private var draft = ""
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
                onOpenFrota: (() -> Void)? = nil,
                onOpenOficina: (() -> Void)? = nil) {
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
        self.onOpenFrota = onOpenFrota
        self.onOpenOficina = onOpenOficina
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
            Task { await voz.falar(ultima.content, id: ultima.id.uuidString) }
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
        .onAppear {
            withAnimation(.easeOut(duration: 0.55)) { appeared = true }
        }
        .sheet(item: $activeSheet) { sheet in
            switch sheet {
            case .history:
                ConversationDrawer(store: store, onOpenSettings: onOpenSettings, onOpenProject: onOpenProject, onOpenData: onOpenData, onOpenMemory: onOpenMemory, onOpenDreamInsights: onOpenDreamInsights, unreadDreamInsightCount: unreadDreamInsightCount, onOpenWork: onOpenWork, onOpenFrota: onOpenFrota, onOpenOficina: onOpenOficina)
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
    private var presenceBackground: some View {
        let empty = store.messages.isEmpty
        // ATENÇÃO: cada camada tem a SUA opacidade. Antes havia um único
        // `.opacity(empty ? 0.9 : 0.28)` no retorno da propriedade; herdá-lo deixaria
        // o primordial a 28% justamente enquanto se lê — o efeito "fantasma".
        return ZStack {
            // O CHÃO DE LUZ. Vem primeiro porque é ambiente, não elemento: é a brasa
            // que o bicho espalha, ancorada onde fica o coração dele. Sem ela o bicho
            // flutua sobre um retângulo chapado.
            EmberField(breath: breath, intensity: empty ? 1.0 : 0.62)
                .animation(.easeOut(duration: 0.6), value: empty)

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
                    if store.isStreaming, let note = store.presenceNote, !note.isEmpty {
                        Text(note)
                            .font(BeagleFont.footnote.font.italic())
                            .foregroundStyle(BeagleTheme.textTertiary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.leading, BeagleSpacing.xs)
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
            // `.immediately` e não `.interactively`: o modo interativo faz o
            // teclado seguir o dedo, e num chat a lista já está no fim — o gesto
            // vira rolagem e o teclado nunca sai. Rolar tem que fechar, ponto.
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
            .onChange(of: store.messages.last?.content) { _, _ in
                withAnimation(.easeOut(duration: 0.18)) { proxy.scrollTo(Self.bottomAnchor, anchor: .bottom) }
            }
            .onChange(of: store.messages.count) { _, _ in
                proxy.scrollTo(Self.bottomAnchor, anchor: .bottom)
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
            }
        )
        .padding(.horizontal, BeagleSpacing.md)
        .padding(.bottom, BeagleSpacing.sm)
        .shadow(color: .black.opacity(0.35), radius: 18, y: 6)   // lift off the surface
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

    private func send() { sendText(draft) }

    /// The single funnel for a turn, typed or spoken. Extracted so the voice commit inherits
    /// the Fundo escalation and the voiceModel routing instead of quietly duplicating them.
    private func sendText(_ raw: String) {
        // Quem chegou aqui pelo teclado não quer ser interrompido por áudio.
        if !draft.isEmpty { turnoVeioDeVoz = false }
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        // Fundo = escalate to a full Go-Deeper exploration instead of a chat turn.
        if depth == .fundo {
            draft = ""
            activeSheet = .goDeep(text)
            return
        }
        draft = ""
        store.voiceModel = depth.voiceModel   // Rápido → default voice; Pensar → stronger model
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
    let store: ConversationStore
    var onOpenSettings: (() -> Void)?
    var onOpenProject: (() -> Void)?
    var onOpenData: (() -> Void)?
    var onOpenMemory: (() -> Void)?
    var onOpenDreamInsights: (() -> Void)?
    var unreadDreamInsightCount: Int = 0
    var onOpenWork: (() -> Void)?
    /// Opens the Frota (Mission Control: who needs you). Same trap as Work — it existed only in
    /// the iPad sidebar, i.e. unreachable on the device he actually carries.
    var onOpenFrota: (() -> Void)?
    /// Opens the Oficina (is it green / what broke / where am I).
    var onOpenOficina: (() -> Void)?
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
                // Footer: memory + data screen + settings + project live here now (off the chat top).
                Section {
                    if onOpenMemory != nil {
                        Button { dismiss(); onOpenMemory?() } label: {
                            Label("O que eu lembro de ti", systemImage: "brain.head.profile")
                        }
                        .foregroundStyle(BeagleTheme.companionInk.opacity(0.9))
                    }
                    if onOpenDreamInsights != nil {
                        Button { dismiss(); onOpenDreamInsights?() } label: {
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
                    }
                    if onOpenData != nil {
                        Button { dismiss(); onOpenData?() } label: {
                            Label("Dados", systemImage: "chart.xyaxis.line")
                        }
                        .foregroundStyle(BeagleTheme.companionInk.opacity(0.9))
                    }
                    if onOpenFrota != nil {
                        Button { dismiss(); onOpenFrota?() } label: {
                            Label("Frota", systemImage: "dot.radiowaves.left.and.right")
                        }
                        .foregroundStyle(BeagleTheme.companionInk.opacity(0.9))
                    }
                    if onOpenOficina != nil {
                        Button { dismiss(); onOpenOficina?() } label: {
                            Label("Oficina", systemImage: "wrench.and.screwdriver")
                        }
                        .foregroundStyle(BeagleTheme.companionInk.opacity(0.9))
                    }
                    if onOpenWork != nil {
                        Button { dismiss(); onOpenWork?() } label: {
                            Label("Trabalho", systemImage: "bolt.fill")
                        }
                        .foregroundStyle(BeagleTheme.companionInk.opacity(0.9))
                    }
                    if onOpenProject != nil {
                        Button { dismiss(); onOpenProject?() } label: {
                            Label("Projeto", systemImage: "scope")
                        }
                        .foregroundStyle(BeagleTheme.companionInk.opacity(0.9))
                    }
                    if onOpenSettings != nil {
                        Button { dismiss(); onOpenSettings?() } label: {
                            Label("Configurações", systemImage: "gearshape")
                        }
                        .foregroundStyle(BeagleTheme.companionInk.opacity(0.9))
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
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        store.newConversation(); dismiss()
                    } label: { Image(systemName: "square.and.pencil") }
                }
            }
        }
    }
}
