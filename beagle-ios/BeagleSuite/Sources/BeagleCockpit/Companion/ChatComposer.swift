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
import UniformTypeIdentifiers
import BeagleCore
#if canImport(UIKit)
import UIKit
#endif
#if canImport(VisionKit)
import VisionKit
#endif

/// The companion's "gear": which voice (model) speaks the next turn, or Fundo = escalate to a full
/// Go-Deeper exploration. The chosen voice sets the personal-path `voiceModel` (the friend persona
/// is the constant — only the engine changes). Live switching so the user judges pt-BR for himself.
enum ChatDepth: String, CaseIterable, Identifiable {
    // .moe combines the uncensored on-device model (Layer 1 raw listening) with OpenAI GPT-6.2 + Beagle MCP + Cluster Memory.
    case moe, gpt, gptSol, sonnet, opus, localUncensored, grok, glm, kimi, minimax, fundo
    var id: String { rawValue }
    var label: String {
        switch self {
        case .moe: return "MoE · Local + GPT"
        case .gpt: return "GPT 6.2 Astra"
        case .gptSol: return "GPT 6.2 Sol"
        case .sonnet: return "Sonnet 5"
        case .opus: return "Opus 4.8"
        case .localUncensored: return "Local Sem Censura"
        case .grok: return "Grok 4.3"
        case .glm: return "GLM 5.2"
        case .kimi: return "Kimi 2.6"
        case .minimax: return "MiniMax M3"
        case .fundo: return "Fundo"
        }
    }
    var subtitle: String {
        switch self {
        case .moe: return "sem censura local + GPT-6.2 + MCP"
        case .gpt: return "flagship 1M ctx · OpenAI + Tool Search"
        case .gptSol: return "agentes & código · OpenAI + MCP"
        case .sonnet: return "padrão · pt-BR"
        case .opus: return "voz premium · pt-BR"
        case .localUncensored: return "on-device abliterated · 100% local"
        case .grok: return "rápido · xAI"
        case .glm: return "cluster"
        case .kimi: return "voz alternativa"
        case .minimax: return "voz alternativa"
        case .fundo: return "exploração profunda"
        }
    }
    var systemImage: String {
        switch self {
        case .moe: return "brain.head.profile"
        case .gpt, .gptSol: return "sparkle"
        case .sonnet: return "sparkles"
        case .opus: return "sparkles"
        case .localUncensored: return "cpu.fill"
        case .grok: return "bolt"
        case .glm, .kimi, .minimax: return "waveform"
        case .fundo: return "scope"
        }
    }
    /// Personal-path voiceModel (router model_name); nil = server default. `.fundo` → Go-Deeper.
    var voiceModel: String? {
        switch self {
        case .moe: return "moe"
        case .gpt: return OpenAIModelCatalog.defaultFlagshipModel
        case .gptSol: return OpenAIModelCatalog.defaultDailyAgentModel
        case .sonnet: return "claude-sonnet-5"
        case .opus: return "claude-opus-4-8"
        case .localUncensored: return "local-uncensored"
        case .grok: return "grok"
        case .glm: return "glm-5.2"
        case .kimi: return "kimi-k2.6"
        case .minimax: return "minimax-m3"
        case .fundo: return nil
        }
    }
}

struct ChatComposer: View {
    @Binding var text: String
    @Binding var depth: ChatDepth
    @Binding var attachedImageData: Data?
    @Binding var attachedDocument: ChatDocumentPayload?
    var isStreaming: Bool
    var onSend: () -> Void
    /// The voice turn for this composer. Held by the screen so it survives composer redraws;
    /// the composer only drives the gesture and reads the state.
    var voice: VoiceTurnController
    /// A finished spoken turn. Same funnel as `onSend` on the screen side.
    var onVoiceCommit: (String) -> Void
    /// Invoked immediately before arming the microphone so active TTS playback yields the audio session (barge-in).
    var onWillArmVoice: (() -> Void)? = nil
    /// Multimodal capture triggers (presented by ChatScreen's unified sheet).
    var onRequestCamera: (() -> Void)? = nil
    var onRequestScanner: (() -> Void)? = nil

    @State private var pickedItem: PhotosPickerItem?
    @State private var showPhotosPicker = false
    @State private var showPDFImporter = false
    @State private var isExtractingPDF = false
    @State private var pdfImportError: String?
    @FocusState private var focused: Bool
    /// When the long-press last engaged. SwiftUI still delivers the Button's `action` on
    /// touch-up after a long hold, and the ordering against the gesture's `onEnded` is not
    /// guaranteed — so a hold must be able to veto the tap that follows it, or every
    /// push-to-talk turn would also toggle hands-free.
    @State private var holdEngagedAt: Date?
    /// Accessibility: Reduce Transparency swaps the Liquid Glass for a solid material so the
    /// draft text never loses contrast over a busy aurora (iOS 27 contrast guidance).
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    private var trimmed: String { text.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var hasAttachment: Bool { attachedImageData != nil || attachedDocument != nil }
    /// Whether there's anything to send — independent of streaming state.
    private var hasContent: Bool { !trimmed.isEmpty || hasAttachment }
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
    private var canSend: Bool { hasContent && !isStreaming && !isExtractingPDF }

    /// A voz falhando precisa DIZER que falhou.
    ///
    /// O motivo já era gravado em `recognizer.error` e nenhuma superfície o
    /// mostrava: microfone negado, rota de áudio indisponível, tudo virava
    /// silêncio idêntico a "não apertei direito". Uma linha curta, apagada, que
    /// some sozinha quando a voz volta a funcionar.
    @ViewBuilder
    private var avisoDeVoz: some View {
        if let pdfImportError, !pdfImportError.isEmpty {
            Text(pdfImportError)
                .font(BeagleFont.caption.font)
                .foregroundStyle(BeagleTheme.postureWarm)
                .padding(.horizontal, BeagleSpacing.xs)
        } else if voice.phase == .denied {
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
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: BeagleSpacing.xs) {
            avisoDeVoz
            if hasAttachment || isExtractingPDF { attachmentChip }

            HStack(alignment: .bottom, spacing: 4) {
                attachMenu

                // Depth gear — MoE / GPT 5.5 / Sonnet 5 / Opus 4.8 / Local Sem Censura / Fundo.
                depthGear

                inputField

                actionButton
            }
        }
        .padding(.vertical, BeagleSpacing.xs)
        .padding(.horizontal, BeagleSpacing.sm)
        .modifier(ComposerGlass(reduceTransparency: reduceTransparency))
        .photosPicker(isPresented: $showPhotosPicker, selection: $pickedItem, matching: .images)
        .fileImporter(
            isPresented: $showPDFImporter,
            allowedContentTypes: [.pdf],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                guard let url = urls.first else { return }
                pdfImportError = nil
                isExtractingPDF = true
                Task<Void, Never> {
                    let extracted = await ChatDocumentPayload.extract(from: url)
                    await MainActor.run {
                        isExtractingPDF = false
                        if let extracted {
                            attachedDocument = extracted
                            attachedImageData = nil
                        } else {
                            pdfImportError = "Não consegui ler este PDF — verifique se o arquivo não está protegido por senha."
                        }
                    }
                }
            case .failure:
                isExtractingPDF = false
            }
        }
        .onChange(of: pickedItem) { _, item in
            guard let item else { return }
            Task<Void, Never> {
                if let data = try? await item.loadTransferable(type: Data.self), !data.isEmpty {
                    await MainActor.run {
                        attachedImageData = data
                        attachedDocument = nil
                        pdfImportError = nil
                        pickedItem = nil
                    }
                }
            }
        }
        .onAppear {
            // Routed through the composer so a spoken turn flows through the same send funnel
            // (and if an image or PDF was attached first, sends spoken voice + attachment together).
            voice.onCommit = { spoken in
                pickedItem = nil
                onVoiceCommit(spoken)
            }
        }
        .animation(.easeOut(duration: 0.18), value: voice.isListening)
        .animation(.snappy(duration: 0.2), value: hasAttachment)
        .animation(.snappy(duration: 0.2), value: isExtractingPDF)
    }

    // MARK: - Voice turn

    /// Voice may only arm when the bar is idle: not while editing text (a long press inside a
    /// TextField is the system's cursor/selection gesture), not while an attachment is pending
    /// (that turn belongs to the arrow), and not mid-stream.
    private var canArmVoice: Bool { !hasContent && !focused && !isStreaming }

    private var voiceAccessibilityLabel: String {
        if hasContent { return isStreaming ? String(localized: "Enviando") : String(localized: "Enviar") }
        switch voice.phase {
        case .cancelArmed: return String(localized: "Solte para cancelar")
        case .listening, .latched: return String(localized: "Ouvindo")
        case .arming: return String(localized: "Abrindo o microfone")
        case .denied: return String(localized: "Microfone sem permissão")
        case .idle: return String(localized: "Voz")
        }
    }

    /// Short tap = latch hands-free for this turn (and tap again to force the commit). A tap
    /// that merely ends a hold is vetoed here.
    private func micTapped() {
        if let engaged = holdEngagedAt, Date().timeIntervalSince(engaged) < 3 {
            holdEngagedAt = nil
            return
        }
        guard canArmVoice || voice.isListening else { return }
        if !voice.isListening { onWillArmVoice?() }
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
            onWillArmVoice?()
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
        if voice.phase == .cancelArmed { return String(localized: "solta para cancelar") }
        let t = voice.transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        if !t.isEmpty { return t }
        return voice.phase == .latched ? String(localized: "ouvindo · toca para enviar") : String(localized: "ouvindo…")
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
            TextField(
                inputPlaceholder,
                text: $text,
                axis: .vertical
            )
            .font(BeagleFont.body.font)
            .foregroundStyle(BeagleTheme.companionInk)
            .tint(BeagleTheme.truthObserved)
            .lineLimit(1...6)
            .focused($focused)
            .padding(.vertical, 4)
            .accessibilityIdentifier("chat.composer.inputField")
        }
    }

    private var inputPlaceholder: String {
        if attachedDocument != nil { return String(localized: "Pergunte sobre o PDF…") }
        if attachedImageData != nil { return String(localized: "Pergunte sobre a imagem…") }
        return String(localized: "Fala comigo…")
    }

    /// ONE persistent Button — send-vs-mic is just which icon/action it wears right now, never
    /// a structural if/else. (See `canSend`'s doc comment: the old if/else identity-swap was
    /// the real remaining disappearing bug.) Streaming is shown as a quiet ring around the
    /// still full-opacity arrow, not a gray dim — the button is never hidden and never looks
    /// "broken". It lives in its own property purely so the type-checker can cope.
    private var actionButton: some View {
        // The ternary is INSIDE the closure, not on the Button: two partially-applied method
        // references as a ternary is what the type-checker choked on, and swapping the Button
        // itself is forbidden (see canSend).
        Button(action: { hasContent ? send() : micTapped() }) {
            ZStack {
                if hasContent && (isStreaming || isExtractingPDF) {
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
        .accessibilityIdentifier("chat.composer.actionButton")
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

    // The gear control: current mode icon + compact voice badge → menu of depths.
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
                .foregroundStyle(depthTint)
                .frame(width: 34, height: 34)
                .contentShape(Circle())
                .contentTransition(.symbolEffect(.replace))
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .sensoryFeedback(.selection, trigger: depth)
        .accessibilityIdentifier("chat.composer.depthMenu")
        .accessibilityLabel("Voz ativa: \(depth.label)")
    }

    private var depthTint: Color {
        switch depth {
        case .moe, .fundo: return BeagleTheme.truthObserved
        case .localUncensored: return MessageBubble.marcaAmbar
        case .gpt: return BeagleTheme.truthRemembered
        default: return BeagleTheme.textSecondary
        }
    }

    // Multimodal "+" menu: PDF/Articles, Photos library, Camera, Document/Prescription Scanner, Pasteboard.
    private var attachMenu: some View {
        Menu {
            Button {
                showPDFImporter = true
            } label: {
                Label("Importar PDF / Artigo", systemImage: "doc.richtext")
            }
            Button {
                showPhotosPicker = true
            } label: {
                Label("Fototeca", systemImage: "photo.on.rectangle")
            }
            #if os(iOS)
            if let onRequestCamera {
                Button {
                    onRequestCamera()
                } label: {
                    Label("Câmera", systemImage: "camera")
                }
            }
            if let onRequestScanner, VNDocumentCameraViewController.isSupported {
                Button {
                    onRequestScanner()
                } label: {
                    Label("Escanear Documento", systemImage: "doc.viewfinder")
                }
            }
            if UIPasteboard.general.hasImages {
                Button {
                    if let img = UIPasteboard.general.image,
                       let jpeg = img.jpegData(compressionQuality: 0.88) {
                        attachedImageData = jpeg
                        attachedDocument = nil
                    }
                } label: {
                    Label("Colar Imagem", systemImage: "doc.on.clipboard")
                }
            }
            if UIPasteboard.general.hasURLs || UIPasteboard.general.hasStrings {
                Button {
                    if let url = UIPasteboard.general.url {
                        let s = url.absoluteString
                        text = text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? s : "\(text)\n\(s)"
                    } else if let str = UIPasteboard.general.string?.trimmingCharacters(in: .whitespacesAndNewlines),
                              !str.isEmpty {
                        text = text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? str : "\(text)\n\(str)"
                    }
                } label: {
                    Label("Colar Link / DOI", systemImage: "link.badge.plus")
                }
            }
            #endif
            if hasAttachment {
                Divider()
                Button(role: .destructive) {
                    attachedImageData = nil
                    attachedDocument = nil
                    pdfImportError = nil
                    pickedItem = nil
                } label: {
                    Label(attachedDocument != nil ? "Remover PDF" : "Remover Imagem", systemImage: "trash")
                }
            }
        } label: {
            Image(systemName: attachIconName)
                .font(.system(size: 19, weight: .medium))
                .foregroundStyle(hasAttachment ? BeagleTheme.truthObserved : BeagleTheme.textSecondary)
                .frame(width: 34, height: 34)
                .contentShape(Circle())
                .contentTransition(.symbolEffect(.replace))
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .accessibilityIdentifier("chat.composer.attachMenu")
        .accessibilityLabel(hasAttachment ? "Anexo pronto" : "Anexar PDF, foto ou câmera")
    }

    private var attachIconName: String {
        if attachedDocument != nil { return "doc.richtext.fill" }
        if attachedImageData != nil { return "photo.badge.checkmark" }
        return "plus.circle.fill"
    }

    private func send() {
        onSend()
        pickedItem = nil
    }

    private var attachmentChip: some View {
        HStack(spacing: BeagleSpacing.sm) {
            thumbnail
            VStack(alignment: .leading, spacing: 2) {
                Text(attachmentChipTitle)
                    .font(BeagleFont.caption.font.weight(.medium))
                    .foregroundStyle(BeagleTheme.companionInk)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(attachmentChipSubtitle)
                    .font(BeagleFont.caption2.font)
                    .foregroundStyle(BeagleTheme.truthObserved)
                    .lineLimit(1)
            }
            Spacer()
            if !isExtractingPDF {
                Button {
                    attachedImageData = nil
                    attachedDocument = nil
                    pdfImportError = nil
                    pickedItem = nil
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 18))
                        .foregroundStyle(BeagleTheme.textTertiary)
                        .frame(width: 32, height: 32)
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Remover anexo")
            }
        }
        .padding(.horizontal, BeagleSpacing.xs)
        .padding(.top, 4)
    }

    private var attachmentChipTitle: String {
        if isExtractingPDF { return String(localized: "Lendo documento PDF…") }
        if let doc = attachedDocument { return doc.fileName }
        return String(localized: "Imagem pronta para análise")
    }

    private var attachmentChipSubtitle: String {
        let activeLabel = depth == .fundo ? ChatDepth.moe.label : depth.label
        if isExtractingPDF { return String(localized: "extraindo páginas + OCR no aparelho…") }
        if let doc = attachedDocument {
            let ocrTag = doc.ocrUsedPages > 0 ? " · OCR em \(doc.ocrUsedPages) pág." : ""
            return "\(doc.pageCount) pág.\(ocrTag) · \(activeLabel)"
        }
        return "visão ativa · \(activeLabel)"
    }

    @ViewBuilder
    private var thumbnail: some View {
        if isExtractingPDF {
            ProgressView()
                .progressViewStyle(.circular)
                .tint(BeagleTheme.truthObserved)
                .frame(width: 44, height: 44)
        } else {
            #if canImport(UIKit)
            if let data = attachedImageData ?? attachedDocument?.coverJPEGData,
               let img = UIImage(data: data) {
                Image(uiImage: img)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 44, height: 44)
                    .clipShape(RoundedRectangle(cornerRadius: BeagleRadius.sm, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: BeagleRadius.sm, style: .continuous)
                            .strokeBorder(Color.white.opacity(0.18), lineWidth: 0.75)
                    )
            } else {
                Image(systemName: attachedDocument != nil ? "doc.richtext.fill" : "photo")
                    .font(.system(size: 20))
                    .foregroundStyle(BeagleTheme.truthObserved)
                    .frame(width: 44, height: 44)
            }
            #else
            Image(systemName: attachedDocument != nil ? "doc.richtext.fill" : "photo")
                .foregroundStyle(BeagleTheme.textSecondary)
                .frame(width: 44, height: 44)
            #endif
        }
    }
}

/// The composer's rounded background: true Liquid Glass normally; a solid material when the
/// user enables Reduce Transparency. Continuous 24pt corner radius matches a Capsule at 1-line
/// height while expanding cleanly when a photo preview chip or multi-line draft is visible.
private struct ComposerGlass: ViewModifier {
    let reduceTransparency: Bool
    private let shape = RoundedRectangle(cornerRadius: 24, style: .continuous)
    func body(content: Content) -> some View {
        if reduceTransparency {
            content
                .background(.ultraThinMaterial, in: shape)
                .overlay(shape.strokeBorder(Color.white.opacity(0.10), lineWidth: 0.75))
        } else {
            content
                .glassEffect(.regular, in: shape)
                .overlay(shape.strokeBorder(Color.white.opacity(0.10), lineWidth: 0.75))
        }
    }
}
