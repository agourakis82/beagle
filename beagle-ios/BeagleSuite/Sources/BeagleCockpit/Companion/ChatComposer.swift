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
    case sonnet, opus, gpt, grok, glm, kimi, minimax, fundo
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
        }
    }
}

struct ChatComposer: View {
    @Binding var text: String
    @Binding var depth: ChatDepth
    var isStreaming: Bool
    var onSend: () -> Void
    var onVoice: () -> Void

    @State private var pickedItem: PhotosPickerItem?
    @State private var attachedData: Data?
    @FocusState private var focused: Bool
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

    var body: some View {
        VStack(alignment: .leading, spacing: BeagleSpacing.xs) {
            if attachedData != nil { attachmentChip }

            HStack(alignment: .bottom, spacing: BeagleSpacing.xs) {
                // Depth gear — Rápido / Pensar / Fundo. Lives in the composer edge (Kimi/MiniMax
                // style) so the user picks how hard the companion works before sending.
                depthGear

                TextField("Fala comigo…", text: $text, axis: .vertical)
                    .font(BeagleFont.body.font)
                    .foregroundStyle(BeagleTheme.companionInk)
                    .tint(BeagleTheme.truthObserved)
                    .lineLimit(1...6)
                    .focused($focused)
                    .padding(.vertical, 4)

                // ONE persistent Button — send-vs-mic is just which icon/action it wears right
                // now, never a structural if/else. (See `canSend`'s doc comment: the old
                // if/else identity-swap was the real remaining disappearing bug.) Streaming is
                // shown as a quiet ring around the still full-opacity arrow, not a gray dim —
                // the button is never hidden and never looks "broken".
                Button(action: hasContent ? send : onVoice) {
                    ZStack {
                        if hasContent && isStreaming {
                            ProgressView()
                                .progressViewStyle(.circular)
                                .tint(BeagleTheme.truthObserved.opacity(0.7))
                                .scaleEffect(1.25)
                        }
                        Image(systemName: hasContent ? "arrow.up.circle.fill" : "mic.fill")
                            .font(.system(size: hasContent ? 28 : 20))
                            .foregroundStyle(hasContent ? BeagleTheme.truthObserved : BeagleTheme.textSecondary)
                            .contentTransition(.symbolEffect(.replace))
                    }
                    .frame(width: 34, height: 34)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(hasContent && !canSend)
                .accessibilityLabel(hasContent ? (isStreaming ? "Enviando" : "Enviar") : "Voz")
                .animation(.snappy(duration: 0.2), value: hasContent)
                .animation(.snappy(duration: 0.2), value: isStreaming)
            }
        }
        .padding(.vertical, BeagleSpacing.xs)
        .padding(.horizontal, BeagleSpacing.sm)
        .modifier(ComposerGlass(reduceTransparency: reduceTransparency))
        .onChange(of: pickedItem) { _, item in
            Task { attachedData = try? await item?.loadTransferable(type: Data.self) }
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
                .foregroundStyle(depth == .fundo ? BeagleTheme.truthObserved : BeagleTheme.textSecondary)
                .frame(width: 32, height: 32)
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .accessibilityLabel("Profundidade: \(depth.label)")
    }

    private func send() {
        onSend()
        attachedData = nil
        pickedItem = nil
    }

    private var attachmentChip: some View {
        HStack(spacing: BeagleSpacing.xs) {
            thumbnail
            Text("foto anexada")
                .font(BeagleFont.caption2.font)
                .foregroundStyle(BeagleTheme.textSecondary)
            Spacer()
            Button {
                attachedData = nil
                pickedItem = nil
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(BeagleTheme.textTertiary)
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
            Image(systemName: "photo").foregroundStyle(BeagleTheme.textSecondary)
        }
        #else
        Image(systemName: "photo").foregroundStyle(BeagleTheme.textSecondary)
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
