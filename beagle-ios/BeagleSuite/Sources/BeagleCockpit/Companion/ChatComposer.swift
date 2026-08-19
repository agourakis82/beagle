//
//  ChatComposer.swift
//  BeagleCockpit — Companion chat
//
//  The floating input bar — the ONLY Liquid Glass element in the chat (chrome floats
//  above flat content). The "+" attaches a photo (PhotosPicker); a removable chip shows
//  the attachment. Sending the image to the model (iOS 27 Foundation Models multimodal)
//  is the next step. Mic = voice, arrow = send.
//

import SwiftUI
import PhotosUI
import BeagleCore
#if canImport(UIKit)
import UIKit
#endif

/// The companion's "gear": which voice (model) speaks the next turn, or Fundo = escalate to a full
/// Go-Deeper exploration. The chosen voice sets the personal-path `voiceModel` (the friend persona
/// is the constant — only the engine changes). Live switching so the user judges pt-BR for himself.
enum ChatDepth: String, CaseIterable, Identifiable {
    // .sonnet is the default voice — near-Opus quality (Anthropic, released 2026-06-30), far
    // cheaper, and the most agentic Sonnet yet. Opus stays one tap away for the absolute ceiling.
    case sonnet, opus, gpt, grok, glm, kimi, minimax, fundo, agente
    var id: String { rawValue }
    var label: String {
        switch self {
        case .sonnet: return "Sonnet 5"
        case .opus: return "Opus 4.8"
        case .gpt: return "GPT 5.5"
        case .grok: return "Grok 4.3"
        case .glm: return "GLM 5.2"
        case .kimi: return "Kimi 2.6"
        case .minimax: return "MiniMax M3"
        case .fundo: return "Fundo"
        case .agente: return "Agente"
        }
    }
    var subtitle: String {
        switch self {
        case .sonnet: return "padrão · pt-BR"
        case .opus: return "voz premium · pt-BR"
        case .gpt: return "voz premium · OpenAI"
        case .grok: return "rápido · xAI"
        case .glm: return "cluster"
        case .kimi: return "voz alternativa"
        case .minimax: return "voz alternativa"
        case .fundo: return "exploração profunda"
        case .agente: return "cluster + ferramentas (leitura)"
        }
    }
    var systemImage: String {
        switch self {
        case .sonnet: return "sparkles"
        case .opus: return "sparkles"
        case .gpt: return "sparkle"
        case .grok: return "bolt"
        case .glm, .kimi, .minimax: return "waveform"
        case .fundo: return "scope"
        case .agente: return "wrench.and.screwdriver"
        }
    }
    /// Personal-path voiceModel (router model_name); nil = server default. `.fundo` → Go-Deeper.
    var voiceModel: String? {
        switch self {
        case .sonnet: return "claude-sonnet-5"
        case .opus: return "claude-opus-4-8"
        case .gpt: return "gpt-5.5"
        case .grok: return "grok"
        case .glm: return "glm-5.2"
        case .kimi: return "kimi-k2.6"
        case .minimax: return "minimax-m3"
        case .fundo: return nil
        case .agente: return nil   // server default voice; deepThink flag (not voiceModel) selects the agentic path
        }
    }

    /// True only for `.agente` — the composer's signal to thread `deepThink: true` into the
    /// request body instead of the ChatDepth voiceModel override.
    var isDeepThink: Bool { self == .agente }
}

struct ChatComposer: View {
    @Binding var text: String
    @Binding var depth: ChatDepth
    var isStreaming: Bool
    var onSend: () -> Void
    /// The voice turn for this composer. Held by the screen so it survives composer redraws;
    /// the composer only drives the gesture and reads the state.
    var voice: VoiceTurnController
    /// A finished spoken turn. Same funnel as `onSend` on the screen side.
    var onVoiceCommit: (String) -> Void
    /// Dictation language (pt_BR/en_US) shown in the PT/EN chip + a handler to toggle it. The chip
    /// sits next to the mic (only when the field is empty) — the recognizer is single-locale, so
    /// the language is chosen before speaking.
    ///
    /// SOBREVIVEU À FUSÃO DE PROPÓSITO. O turno de voz novo entra no reconhecedor por
    /// `startRecording(profile:)`, que não tinha idioma; sem levar o `localeID` até lá o
    /// chip continuaria DESENHADO e não mudaria nada — botão morto. Ver VoiceTurnController.
    var dictationLocaleID: String = "pt_BR"
    var onToggleLocale: (() -> Void)? = nil
    /// Quando o estado aconteceu, se ele declarou. `nil` = não declarou, e é o padrão.
    ///
    /// A ausência é significativa e não pode virar um "agora" implícito: sob o pré-registro
    /// `direcao-v2`, instante DEDUZIDO da fala é inelegível ao confronto com a fisiologia. O
    /// relato só se torna elegível por um ato — inclusive o ato de tocar em "agora", que troca
    /// uma suposição do sistema por uma afirmação dele. Ver `InstanteDoEstado.swift`.
    @Binding var ancora: AncoraTemporal?

    @State private var pickedItem: PhotosPickerItem?
    @State private var attachedData: Data?
    @FocusState private var focused: Bool
    // SOTA-chat: monotonic trigger for the send haptic (fires .sensoryFeedback on change).
    @State private var sendHaptic = 0
    /// When the long-press last engaged. SwiftUI still delivers the Button's `action` on
    /// touch-up after a long hold, and the ordering against the gesture's `onEnded` is not
    /// guaranteed — so a hold must be able to veto the tap that follows it, or every
    /// push-to-talk turn would also toggle hands-free.
    @State private var holdEngagedAt: Date?
    @State private var mostrandoSeletor = false
    /// A folha de "quando foi isso?", aberta pelo próprio envio quando o texto é um relato.
    @State private var perguntandoInstante = false
    /// Texto falado esperando a declaração do instante. `nil` quando o gate veio do teclado.
    @State private var faladoPendente: String?
    @State private var horaEscolhida = Date()
    /// Accessibility: Reduce Transparency swaps the Liquid Glass for a solid material so the
    /// draft text never loses contrast over a busy aurora (iOS 27 contrast guidance).
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    private var trimmed: String { text.trimmingCharacters(in: .whitespacesAndNewlines) }
    /// Whether there's anything to send — independent of streaming state.
    private var hasContent: Bool { !trimmed.isEmpty || attachedData != nil }
    /// Whether tapping the button would actually send right now. While streaming this is
    /// false, but — see body — the button itself never disables its *identity*, only whether
    /// the tap does anything; the glyph swap (arrow ⇄ mic) and the streaming state are both
    /// just modifiers on ONE persistent Button, never a structural if/else. An if/else here
    /// was the real remaining "disappears" bug (beyond the streaming case fixed in 0c32ddd):
    /// it destroys and recreates the Button every time `hasContent` flips — which happens
    /// constantly (typing then deleting back to empty, or `text` clearing the instant Send is
    /// tapped) — and that structural swap, combined with per-branch `.animation`/`.opacity`
    /// modifiers, could race and land on a blank frame mid cross-fade. A single Button that
    /// only ever changes its icon/action in place cannot do that.
    private var canSend: Bool { hasContent && !isStreaming }

    /// A voz falhando precisa DIZER que falhou.
    ///
    /// O motivo já era gravado em `recognizer.error` e nenhuma superfície o
    /// mostrava: microfone negado, rota de áudio indisponível, tudo virava
    /// silêncio idêntico a "não apertei direito". Uma linha curta, apagada, que
    /// some sozinha quando a voz volta a funcionar.
    @ViewBuilder
    private var avisoDeVoz: some View {
        if voice.phase == .denied {
            Text("Microfone sem permissão — libere em Ajustes › Beagle › Microfone.")
                .font(BeagleFont.caption.font)
                .foregroundStyle(BeagleTheme.postureWarm)
                .padding(.horizontal, BeagleSpacing.xs)
        } else if let recusa = voice.motivoDaRecusa, !recusa.isEmpty {
            Text(recusa)
                .font(BeagleFont.caption.font)
                .foregroundStyle(BeagleTheme.postureWarm)
                .padding(.horizontal, BeagleSpacing.xs)
        } else if let erro = voice.erro, !erro.isEmpty {
            Text(erro)
                .font(BeagleFont.caption.font)
                .foregroundStyle(BeagleTheme.postureWarm)
                .padding(.horizontal, BeagleSpacing.xs)
        } else if let aviso = avisoTemporario, !aviso.isEmpty {
            // Recusa explicada, com prazo. Some sozinha para não virar ruído fixo.
            Text(aviso)
                .font(BeagleFont.caption.font)
                .foregroundStyle(BeagleTheme.textTertiary)
                .padding(.horizontal, BeagleSpacing.xs)
                .task(id: aviso) {
                    try? await Task.sleep(for: .seconds(3))
                    avisoTemporario = nil
                }
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: BeagleSpacing.xs) {
            avisoDeVoz
            if attachedData != nil { attachmentChip }
            if ancora != nil { ancoraChip }

            HStack(alignment: .bottom, spacing: BeagleSpacing.xs) {
                // Depth gear — Rápido / Pensar / Fundo. Lives in the composer edge (Kimi/MiniMax
                // style) so the user picks how hard the companion works before sending.
                depthGear

                inputField

                // CHIP PT/EN — sobreviveu da outra faixa. So aparece com o campo vazio,
                // ao lado do microfone: o reconhecedor e de um idioma so, entao a escolha
                // e ANTES de falar. Continua util porque o localeID agora atravessa o
                // turno de voz ate o reconhecedor (ver VoiceTurnController).
                if !hasContent, let onToggleLocale {
                    Button(action: onToggleLocale) {
                        Text(dictationLocaleID.hasPrefix("en") ? "EN" : "PT")
                            .font(BeagleFont.caption2.font.weight(.semibold))
                            .foregroundStyle(BeagleTheme.companionInk.opacity(0.6))
                            .frame(minWidth: 28, minHeight: 28)
                            .background(Capsule().fill(BeagleTheme.companionInk.opacity(0.08)))
                            .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(dictationLocaleID.hasPrefix("en") ? "Idioma da ditada: inglês, tocar para português" : "Idioma da ditada: português, tocar para inglês")
                }

                relogioDeEstado

                actionButton
            }
        }
        .padding(.vertical, BeagleSpacing.xs)
        .padding(.horizontal, BeagleSpacing.sm)
        .modifier(ComposerGlass(reduceTransparency: reduceTransparency))
        // `confirmationDialog` e não `sheet`: as opções aparecem na borda inferior, ao alcance do
        // polegar e sobre a conversa, sem cobrir o que ele acabou de escrever. Uma folha inteira
        // para uma pergunta de uma linha pareceria um formulário, e a diferença entre "um toque"
        // e "um formulário" é a diferença entre ele usar e não usar.
        .confirmationDialog("Quando esse estado aconteceu?",
                            isPresented: $perguntandoInstante, titleVisibility: .visible) {
            ForEach(AncoraTemporal.rapidas, id: \.chave) { op in
                Button(op.rotulo) { declararEEnviar(op) }
            }
            Button("Escolher hora…") { mostrandoSeletor = true }
            // Sem escapatória silenciosa: `cancel` volta ao texto, não envia sem instante. Um
            // botão "enviar assim mesmo" reabriria exatamente o buraco que isto fecha, e seria
            // o caminho de menor esforço em todo relato.
            Button("Voltar", role: .cancel) {
                // O falado volta para o campo em vez de sumir: ele acabou de DIZER aquilo, e
                // perder o texto por ter recuado da pergunta seria pior que a pergunta.
                if let falado = faladoPendente { text = falado; faladoPendente = nil }
            }
        } message: {
            Text("O confronto com o corpo usa esse instante — não o da mensagem.")
        }
        .sheet(isPresented: $mostrandoSeletor) {
            SeletorDeInstante(hora: $horaEscolhida) { escolhida in
                // Se o seletor foi aberto pelo gate do envio, declarar já envia — mesmo gesto.
                // Se foi aberto pelo relógio, só marca a âncora e devolve o controle.
                if perguntandoInstante {
                    perguntandoInstante = false
                    declararEEnviar(.horario(escolhida))
                } else {
                    ancora = .horario(escolhida)
                }
            }
        }
        // SOTA-chat: subtle light-impact haptic confirming the send, contained and non-decorative.
        .sensoryFeedback(.impact(weight: .light), trigger: sendHaptic)
        .onChange(of: pickedItem) { _, item in
            Task<Void, Never> { attachedData = try? await item?.loadTransferable(type: Data.self) }
        }
        .onAppear {
            // Routed through the composer, not straight to the screen, so a spoken turn goes
            // through the same cleanup as a typed one and can never leave an orphan attachment
            // stuck in the bar for the next message.
            voice.onCommit = { spoken in
                attachedData = nil
                pickedItem = nil
                // O turno FALADO passa pelo mesmo gate do digitado. Ele conversa por voz o
                // tempo todo; cobrir só o teclado deixaria a maior parte dos relatos sem
                // instante — o defeito de "ligar a guarda numa rota só", que nesta base já
                // apareceu mais de uma vez.
                //
                // O texto falado não está em `text`, então fica guardado até a declaração.
                if ancora == nil && RelatoDeEstado.pareceRelato(spoken) {
                    faladoPendente = spoken
                    perguntandoInstante = true
                    return
                }
                onVoiceCommit(spoken)
            }
        }
        .animation(.easeOut(duration: 0.18), value: voice.isListening)
    }

    // MARK: - Voice turn

    /// Voice may only arm when the bar is idle: not while editing text (a long press inside a
    /// TextField is the system's cursor/selection gesture), not while an attachment is pending
    /// (that turn belongs to the arrow), and not mid-stream.
    /// Recusa explicada. Um botão que não faz nada é pior que um que diz não.
    @State private var avisoTemporario: String?

    private var canArmVoice: Bool { !hasContent && !focused && !isStreaming }

    private var voiceAccessibilityLabel: String {
        if hasContent { return isStreaming ? "Enviando" : "Enviar" }
        switch voice.phase {
        case .cancelArmed: return "Solte para cancelar"
        case .listening, .latched: return "Ouvindo"
        case .arming: return "Abrindo o microfone"
        case .denied: return "Microfone sem permissão"
        case .idle: return "Voz"
        }
    }

    /// Short tap = latch hands-free for this turn (and tap again to force the commit). A tap
    /// that merely ends a hold is vetoed here.
    private func micTapped() {
        if let engaged = holdEngagedAt, Date().timeIntervalSince(engaged) < 3 {
            holdEngagedAt = nil
            return
        }
        // TOCAR NO MICROFONE COM O TECLADO ABERTO É INTENÇÃO CLARA: ele quer falar.
        //
        // Antes isto era `guard canArmVoice else { return }` — um RETURN SILENCIOSO.
        // E `canArmVoice` exige `!focused`, ou seja, teclado FECHADO. Como não
        // existia botão para recolher o teclado, o microfone ficava inalcançável
        // por construção: ele tocava e não acontecia nada, sem uma palavra na tela.
        // Os dois defeitos que ele relatou (o teclado que não abaixa e o microfone
        // que não responde) eram o MESMO defeito.
        //
        // Agora, em vez de recusar: fecha o teclado e abre o microfone. Recusar
        // algo que o usuário pediu sem explicar é a pior resposta possível.
        if focused && !voice.isListening {
            recolherTeclado()
            Task<Void, Never> {
                // Um respiro para o teclado sair e a sessão de áudio assentar —
                // abrir o microfone no mesmo instante disputa a rota de áudio.
                try? await Task.sleep(for: .milliseconds(250))
                await voice.toggleLatched()
            }
            return
        }
        guard canArmVoice || voice.isListening else {
            // Sobra um caso só: ele está respondendo. Dizer isso é melhor que
            // um botão morto.
            if isStreaming { avisoTemporario = "espera ele terminar de responder" }
            return
        }
        Task<Void, Never> { await voice.toggleLatched() }
    }

    /// Hold to talk; drag up past the threshold to cancel. The finger is the endpoint
    /// detector — the only one that works when the room is not quiet.
    ///
    /// The handlers are written out as methods with explicit types on purpose: inline
    /// closures over a SequenceGesture value blew up the type-checker in this file.
    private typealias VoiceGesture = SequenceGesture<LongPressGesture, DragGesture>

    private var voiceGesture: some Gesture {
        LongPressGesture(minimumDuration: 0.18)
            .sequenced(before: DragGesture(minimumDistance: 0, coordinateSpace: .local))
            .onChanged(handleVoiceGestureChange)
            .onEnded(handleVoiceGestureEnd)
    }

    private func handleVoiceGestureChange(_ value: VoiceGesture.Value) {
        switch value {
        case .first(true):
            guard canArmVoice else { return }
            holdEngagedAt = Date()
            Task<Void, Never> { await voice.beginHold() }
        case .second(true, let drag):
            guard let drag else { return }
            voice.updateHold(translation: drag.translation.height)
        default:
            break
        }
    }

    private func handleVoiceGestureEnd(_ value: VoiceGesture.Value) {
        voice.endHold()
    }

    /// What the text field becomes while he is speaking: the words as they land, plus a level
    /// bar that proves the microphone is actually hearing something.
    private var listeningField: some View {
        HStack(spacing: BeagleSpacing.xs) {
            levelMeter
            Text(listeningText)
                .font(BeagleFont.body.font)
                .foregroundStyle(voice.phase == .cancelArmed ? BeagleTheme.textSecondary : BeagleTheme.companionInk)
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 4)
        }
        .accessibilityElement(children: .combine)
    }

    private var listeningText: String {
        if voice.phase == .cancelArmed { return "solta para cancelar" }
        let t = voice.transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        if !t.isEmpty { return t }
        return voice.phase == .latched ? "ouvindo · toca para enviar" : "ouvindo…"
    }

    /// Three bars breathing with the input level. Deliberately tiny — it is a proof of life,
    /// not a visualization; the real feedback channel for this gesture is haptic.
    private var levelMeter: some View {
        let lvl = CGFloat(max(0.06, min(1, voice.level)))
        return HStack(spacing: 2) {
            ForEach(0..<3, id: \.self) { i in
                Capsule()
                    .fill(voice.phase == .cancelArmed ? BeagleTheme.textTertiary : BeagleTheme.truthObserved)
                    .frame(width: 2.5, height: 6 + lvl * (i == 1 ? 16 : 10))
            }
        }
        .frame(width: 14, height: 24)
        .animation(.easeOut(duration: 0.12), value: voice.level)
    }

    /// The text field, or — while he is speaking — the live transcript. Swapping the FIELD's
    /// content is safe; the forbidden swap is the Button's.
    @ViewBuilder
    private var inputField: some View {
        if voice.isListening {
            listeningField
        } else {
            TextField("Fala comigo…", text: $text, axis: .vertical)
                .font(BeagleFont.body.font)
                .foregroundStyle(BeagleTheme.companionInk)
                .tint(BeagleTheme.truthObserved)
                .lineLimit(1...6)
                .focused($focused)
                .padding(.vertical, 4)
                // BOTÃO DE RECOLHER, acima do teclado.
                //
                // Havia .scrollDismissesKeyboard(.interactively) e mais nada. Num
                // chat a lista já está no fim: arrastar para baixo ROLA o
                // conteúdo, não fecha o teclado. Na prática não existia saída — e
                // ele não conseguia LER a conversa, que é metade do uso.
                //
                // Uma barra acima do teclado é o lugar onde a Apple treinou todo
                // mundo a procurar, e funciona com o polegar da mão que segura o
                // telefone.
                .toolbar {
                    ToolbarItemGroup(placement: .keyboard) {
                        Spacer()
                        Button {
                            recolherTeclado()
                        } label: {
                            Label("recolher", systemImage: "keyboard.chevron.compact.down")
                                .font(BeagleFont.caption.font)
                        }
                        .tint(BeagleTheme.truthObserved)
                        .accessibilityLabel("Recolher o teclado")
                    }
                }
        }
    }

    /// ONE persistent Button — send-vs-mic is just which icon/action it wears right now, never
    /// a structural if/else. (See `canSend`'s doc comment: the old if/else identity-swap was
    /// the real remaining disappearing bug.) Streaming is shown as a quiet ring around the
    /// still full-opacity arrow, not a gray dim — the button is never hidden and never looks
    /// "broken". It lives in its own property purely so the type-checker can cope.
    /// Fecha o teclado. Também usado pelo toque na conversa.
    func recolherTeclado() {
        focused = false
        #if canImport(UIKit)
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder),
                                        to: nil, from: nil, for: nil)
        #endif
    }

    private var actionButton: some View {
        // The ternary is INSIDE the closure, not on the Button: two partially-applied method
        // references as a ternary is what the type-checker choked on, and swapping the Button
        // itself is forbidden (see canSend).
        Button(action: { hasContent ? send() : micTapped() }) {
            ZStack {
                if hasContent && isStreaming {
                    ProgressView()
                        .progressViewStyle(.circular)
                        .tint(BeagleTheme.truthObserved.opacity(0.7))
                        .scaleEffect(1.25)
                }
                Image(systemName: hasContent ? "arrow.up.circle.fill" : "mic.fill")
                    .font(.system(size: hasContent ? 28 : 20))
                    .foregroundStyle(micTint)
                    .contentTransition(.symbolEffect(.replace))
            }
            .frame(width: 44, height: 44)   // HIG minimum: 34 was unhittable without looking
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(hasContent && !canSend)
        .accessibilityLabel(voiceAccessibilityLabel)
        .accessibilityHint(hasContent ? "" : "Segure para falar, arraste para cima para cancelar")
        .scaleEffect(voice.isListening ? 1.12 : 1.0)
        // simultaneousGesture, never .gesture: .gesture would swallow the Button's own action
        // and trade the send tap for the hold. The Button's identity is untouched.
        .simultaneousGesture(voiceGesture)
        .animation(.snappy(duration: 0.2), value: hasContent)
        .animation(.snappy(duration: 0.2), value: isStreaming)
        .animation(.snappy(duration: 0.2), value: voice.isListening)
    }

    private var micTint: Color {
        if hasContent { return BeagleTheme.truthObserved }
        switch voice.phase {
        case .cancelArmed: return BeagleTheme.textTertiary
        case .listening, .latched, .arming: return BeagleTheme.truthObserved
        default: return BeagleTheme.textSecondary
        }
    }

    // The gear control: current mode icon → menu of the three depths.
    private var depthGear: some View {
        Menu {
            Picker("Profundidade", selection: $depth) {
                ForEach(ChatDepth.allCases) { d in
                    Label("\(d.label) · \(d.subtitle)", systemImage: d.systemImage).tag(d)
                }
            }
        } label: {
            Image(systemName: depth.systemImage)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(depth == .fundo ? BeagleTheme.truthObserved : BeagleTheme.companionInk.opacity(0.6))
                .frame(width: 32, height: 32)
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .accessibilityLabel("Profundidade: \(depth.label)")
    }

    /// Precisa perguntar QUANDO antes de enviar?
    ///
    /// Só quando o texto parece auto-relato de estado (ver `RelatoDeEstado`) e ele ainda não
    /// declarou. Exigir em toda mensagem transformaria cada "bom dia" numa pergunta sobre
    /// quando — e app que atrapalha deixa de ser usado, o que custaria o dado inteiro.
    private var precisaDeclararInstante: Bool {
        ancora == nil && RelatoDeEstado.pareceRelato(trimmed)
    }

    private func send() {
        // O gate. Sob a `direcao-v2` só o instante DECLARADO entra no confronto com a
        // fisiologia, e enquanto declarar era opcional simplesmente não acontecia: dos 10
        // auto-relatos que o funil contava como tendo hora, os 10 eram imputados da fala.
        //
        // Aqui o envio não é bloqueado com um aviso — ele ABRE a escolha. Tocar uma opção
        // declara e envia no mesmo gesto: um toque a mais, não dois, e nenhuma tela nova.
        if precisaDeclararInstante {
            perguntandoInstante = true
            return
        }
        sendHaptic &+= 1   // SOTA-chat: bump trigger before the send so the haptic fires with the action.
        onSend()
        attachedData = nil
        pickedItem = nil
        // A âncora vale por UM turno. Sem zerar aqui, o próximo relato herdaria em silêncio o
        // instante do anterior — e sob a v2 esse instante entraria como declarado.
        ancora = nil
    }

    /// Declara e envia no mesmo gesto.
    private func declararEEnviar(_ escolhida: AncoraTemporal) {
        ancora = escolhida
        sendHaptic &+= 1
        // Uma porta de saída para as duas rotas: falado tem o texto guardado, digitado está no
        // campo. Duplicar o caminho de envio faria a declaração valer numa e não na outra.
        if let falado = faladoPendente {
            faladoPendente = nil
            onVoiceCommit(falado)
        } else {
            onSend()
        }
        attachedData = nil
        pickedItem = nil
        ancora = nil
    }

    /// Abre as âncoras. Fica ao lado do enviar porque a pergunta que ele responde — "isto é
    /// sobre quando?" — só faz sentido com algo escrito, e some da vista o resto do tempo.
    @ViewBuilder
    private var relogioDeEstado: some View {
        if hasContent {
            Menu {
                ForEach(AncoraTemporal.rapidas, id: \.chave) { op in
                    Button(op.rotulo) { ancora = op }
                }
                Divider()
                Button("Escolher hora…") { mostrandoSeletor = true }
                if ancora != nil {
                    Divider()
                    Button("Não declarar", role: .destructive) { ancora = nil }
                }
            } label: {
                Image(systemName: ancora == nil ? "clock" : "clock.fill")
                    .font(.system(size: 17, weight: .regular))
                    .foregroundStyle(BeagleTheme.companionInk.opacity(ancora == nil ? 0.42 : 0.85))
                    .frame(minWidth: 34, minHeight: 34)
                    // Sem isto a área de toque é só o glifo — o mesmo defeito que já deixou um
                    // botão morto nesta tela antes.
                    .contentShape(Rectangle())
            }
            .accessibilityLabel(ancora == nil
                ? "Declarar quando o estado aconteceu"
                : "Estado declarado \(ancora?.rotulo ?? ""), tocar para mudar")
        }
    }

    /// O chip existe para que a declaração seja VISÍVEL antes de enviar. Uma âncora escolhida e
    /// esquecida mandaria um instante que ele não quis afirmar — e sob a `direcao-v2` seria
    /// justamente esse instante a entrar no confronto.
    private var ancoraChip: some View {
        HStack(spacing: BeagleSpacing.xs) {
            Image(systemName: "clock.fill")
                .font(.system(size: 12))
                .foregroundStyle(BeagleTheme.companionInk.opacity(0.55))
            Text("o estado foi \(ancora?.rotulo ?? "")")
                .font(BeagleFont.caption2.font)
                .foregroundStyle(BeagleTheme.companionInk.opacity(0.6))
            Spacer()
            Button {
                ancora = nil
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(BeagleTheme.companionInk.opacity(0.42))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Remover a declaração de quando")
        }
        .padding(.horizontal, BeagleSpacing.xs)
    }

    private var attachmentChip: some View {
        HStack(spacing: BeagleSpacing.xs) {
            thumbnail
            Text("foto anexada")
                .font(BeagleFont.caption2.font)
                .foregroundStyle(BeagleTheme.companionInk.opacity(0.6))
            Spacer()
            Button {
                attachedData = nil
                pickedItem = nil
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(BeagleTheme.companionInk.opacity(0.42))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, BeagleSpacing.xs)
    }

    @ViewBuilder
    private var thumbnail: some View {
        #if canImport(UIKit)
        if let data = attachedData, let img = UIImage(data: data) {
            Image(uiImage: img)
                .resizable()
                .scaledToFill()
                .frame(width: 36, height: 36)
                .clipShape(RoundedRectangle(cornerRadius: BeagleRadius.sm))
        } else {
            Image(systemName: "photo").foregroundStyle(BeagleTheme.companionInk.opacity(0.6))
        }
        #else
        Image(systemName: "photo").foregroundStyle(BeagleTheme.companionInk.opacity(0.6))
        #endif
    }
}

/// The composer's capsule background: true Liquid Glass normally; a solid material when the
/// user enables Reduce Transparency. Kept non-interactive on purpose — the capsule is mostly a
/// text field, and Apple reserves interactive glass for tappable surfaces.
private struct ComposerGlass: ViewModifier {
    let reduceTransparency: Bool
    func body(content: Content) -> some View {
        if reduceTransparency {
            content
                .background(.ultraThinMaterial, in: Capsule())
                .overlay(Capsule().strokeBorder(Color.white.opacity(0.10), lineWidth: 0.75))
        } else {
            content
                .glassEffect(.regular, in: Capsule())
                .overlay(Capsule().strokeBorder(Color.white.opacity(0.10), lineWidth: 0.75))
        }
    }
}
