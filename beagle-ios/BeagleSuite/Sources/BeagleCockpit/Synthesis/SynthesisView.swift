// SynthesisView.swift — the deliberate synthesis surface (a sheet from the drawer footer).
// Streams the 5-block markdown from /api/mobile/v1/synthesize. THE HARD WALL: the result
// lives ONLY in this view's @State — never appended to ConversationStore, never persisted,
// never shown in the chat. Dismiss = discard. No chat imports.
//
// Typography breathes like the chat: companionInk on the deep-night companionSurface, the
// BeagleFont scale, chat-matching block treatment (title3-bold headings, ink-dimmed bullets,
// streaming-tolerant inline markdown). It matches the chat's READING feel without importing
// the chat's fileprivate renderer — a separate room in the same night.
import SwiftUI
import BeagleCore
#if canImport(UIKit)
import UIKit
#endif

struct SynthesisView: View {
    @Environment(\.dismiss) private var dismiss

    private enum Phase: Equatable { case idle, streaming, done, insufficient, error(String) }

    @State private var topic = ""
    @State private var markdown = ""
    @State private var phase: Phase = .idle
    @State private var work: Task<Void, Never>?

    private var ink: Color { BeagleTheme.companionInk }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: BeagleSpacing.md) {
                    field
                    synthButton
                    if !markdown.isEmpty { renderMarkdown(markdown) }
                    footer
                }
                .padding(BeagleSpacing.lg)
            }
            .scrollContentBackground(.hidden)
            .background(BeagleTheme.companionSurface)
            .navigationTitle("Síntese")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button { work?.cancel(); dismiss() } label: {
                        Image(systemName: "xmark").foregroundStyle(ink.opacity(0.7))
                    }
                }
            }
        }
        .presentationBackground(BeagleTheme.companionSurface)
        .tint(BeagleTheme.auroraGreen)
        .onDisappear { work?.cancel() }
    }

    private var field: some View {
        TextField("", text: $topic, prompt: Text("sobre o quê?  (vazio = os últimos dias)")
                    .foregroundColor(ink.opacity(0.4)), axis: .vertical)
            .font(BeagleFont.body.font)
            .foregroundStyle(ink)
            .tint(BeagleTheme.auroraGreen)
            .padding(BeagleSpacing.sm)
            .background(
                RoundedRectangle(cornerRadius: BeagleRadius.md, style: .continuous)
                    .fill(ink.opacity(0.06))
                    .overlay(RoundedRectangle(cornerRadius: BeagleRadius.md, style: .continuous)
                        .stroke(BeagleTheme.companionHairline, lineWidth: 1))
            )
            .disabled(phase == .streaming)
    }

    private var synthButton: some View {
        Button(action: start) {
            Text(phase == .streaming ? "sintetizando…" : "Sintetizar")
                .font(BeagleFont.headline.font)
                .foregroundStyle(BeagleTheme.companionSurface)
                .frame(maxWidth: .infinity)
                .padding(.vertical, BeagleSpacing.sm)
                .background(
                    Capsule().fill(phase == .streaming ? BeagleTheme.auroraGreen.opacity(0.5)
                                                        : BeagleTheme.auroraGreen)
                )
        }
        .disabled(phase == .streaming)
    }

    @ViewBuilder private var footer: some View {
        if phase == .done || phase == .insufficient {
            HStack {
                Button("nova síntese") { reset() }
                Spacer()
                if phase == .done {
                    Button { copy() } label: { Label("copiar", systemImage: "doc.on.doc") }
                }
            }
            .font(BeagleFont.footnote.font)
            .foregroundStyle(ink.opacity(0.7))
            .padding(.top, BeagleSpacing.xs)
        }
        if case .error(let msg) = phase {
            Text(msg).font(BeagleFont.footnote.font).foregroundStyle(BeagleTheme.auroraGreen)
            Button("tentar de novo", action: start).font(BeagleFont.footnote.font)
        }
    }

    // MARK: - actions

    private func start() {
        work?.cancel(); markdown = ""; phase = .streaming
        let t = topic
        work = Task {
            do {
                for try await chunk in SynthesisClient().stream(topic: t) {
                    switch chunk {
                    case .token(let tok): markdown += tok
                    case .done(let insufficient, let err):
                        if let err { phase = .error(err) } else { phase = insufficient ? .insufficient : .done }
                    }
                }
                if phase == .streaming { phase = .done }
            } catch is CancellationError {
            } catch { phase = .error(error.localizedDescription) }
        }
    }

    private func reset() { work?.cancel(); markdown = ""; topic = ""; phase = .idle }

    private func copy() {
        #if canImport(UIKit)
        UIPasteboard.general.string = markdown
        #endif
    }

    // MARK: - local markdown render (matches the chat's reading typography; no chat import)

    @ViewBuilder
    private func renderMarkdown(_ text: String) -> some View {
        VStack(alignment: .leading, spacing: BeagleSpacing.xs) {
            ForEach(Array(text.split(separator: "\n", omittingEmptySubsequences: false).enumerated()), id: \.offset) { _, raw in
                let trimmed = String(raw).trimmingCharacters(in: .whitespaces)
                if trimmed.hasPrefix("## ") {
                    Text(inline(String(trimmed.dropFirst(3))))
                        .font(BeagleFont.title3.font).fontWeight(.bold)
                        .foregroundStyle(ink)
                        .padding(.top, BeagleSpacing.sm)
                } else if trimmed.hasPrefix("# ") {
                    Text(inline(String(trimmed.dropFirst(2))))
                        .font(BeagleFont.title2.font).foregroundStyle(ink)
                        .padding(.top, BeagleSpacing.sm)
                } else if trimmed.hasPrefix("- ") || trimmed.hasPrefix("* ") {
                    HStack(alignment: .firstTextBaseline, spacing: BeagleSpacing.xs) {
                        Text("•").foregroundStyle(ink.opacity(0.55))
                        Text(inline(String(trimmed.dropFirst(2))))
                            .foregroundStyle(ink)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .font(BeagleFont.body.font)
                } else if trimmed.isEmpty {
                    Color.clear.frame(height: 1)
                } else {
                    Text(inline(trimmed))
                        .font(BeagleFont.body.font).foregroundStyle(ink)
                        .lineSpacing(3)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .textSelection(.enabled)
    }

    // streaming-tolerant inline emphasis, like the chat's mdInline.
    private func inline(_ s: String) -> AttributedString {
        (try? AttributedString(markdown: s,
            options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)))
            ?? AttributedString(s)
    }
}
