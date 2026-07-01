//
//  MemoryLensDetailView.swift
//  BeagleCockpit — "O que eu lembro de ti"
//
//  The differentiator neither Kimi nor MiniMax has: a screen showing what the companion actually
//  knows about the user, in its own warm voice — not a raw memory dump. Asks the SAME personal-voice
//  companion pipeline (BeagleClient.chat, space:"personal" → biography/`## Agora` grounding) already
//  proven live, so the answer is a narrative, not a snippet list; renders via the MarkdownText
//  renderer built for chat replies. A follow-up composer lets the user drill in ("o que você sabe
//  sobre o Sounio?"). (`/api/memory/query` — raw ranked snippets — isn't publicly proxied; only
//  reachable over the tailnet, so it's not used here.)
//

import SwiftUI
import BeagleCore

struct MemoryLensDetailView: View {
    /// Read-only: gives the opening/follow-up questions a real `lastContactAt`, so the server
    /// knows this ISN'T the first conversation — without it the model frames itself as meeting
    /// the user for the first time and hedges hard ("isso eu ainda não tenho, primeira vez que
    /// conversamos"), which reads as shallow even though the biography grounding is rich.
    let store: ConversationStore
    @Environment(\.dismiss) private var dismiss
    @State private var entries: [MemoryLensEntry] = []
    @State private var draft = ""
    @State private var loading = true
    @FocusState private var focused: Bool

    private static let openingQuery =
        "O que você sabe sobre mim? Resuma o que lembra de mim de forma organizada — quem sou, " +
        "o que faço, meus projetos, meu jeito — em tópicos curtos e claros, em português."

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: BeagleSpacing.lg) {
                        ForEach(entries) { entry in
                            entryView(entry).id(entry.id)
                        }
                        if loading {
                            HStack(spacing: BeagleSpacing.sm) {
                                ProgressView().tint(BeagleTheme.textTertiary)
                                Text("Vasculhando o que lembro…")
                                    .font(BeagleFont.footnote.font)
                                    .foregroundStyle(BeagleTheme.textTertiary)
                            }
                            .padding(.top, BeagleSpacing.sm)
                        }
                        Color.clear.frame(height: 8).id("bottom")
                    }
                    .padding(BeagleSpacing.md)
                }
                .onChange(of: entries.count) { _, _ in
                    withAnimation(.easeOut(duration: 0.2)) { proxy.scrollTo("bottom", anchor: .bottom) }
                }
            }
            .background(BeagleTheme.surface0.ignoresSafeArea())
            .safeAreaInset(edge: .bottom) { followUpComposer }
            .navigationTitle("O que eu lembro de ti")
            .navigationBarTitleDisplayModeIfAvailable(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Fechar") { dismiss() }
                        .font(BeagleFont.caption.font)
                        .foregroundStyle(BeagleTheme.textSecondary)
                }
            }
        }
        .task {
            guard entries.isEmpty else { return }
            await ask(Self.openingQuery, showAsUserTurn: false)
        }
    }

    @ViewBuilder
    private func entryView(_ entry: MemoryLensEntry) -> some View {
        if let question = entry.question {
            Text(question)
                .font(BeagleFont.footnote.font.weight(.semibold))
                .foregroundStyle(BeagleTheme.textSecondary)
        }
        MarkdownText(text: entry.answer, inkColor: BeagleTheme.textPrimary)
            .frame(maxWidth: .infinity, alignment: .leading)
        Divider().overlay(BeagleTheme.textTertiary.opacity(0.15))
    }

    private var followUpComposer: some View {
        HStack(spacing: BeagleSpacing.xs) {
            TextField("Pergunta o que eu lembro…", text: $draft, axis: .vertical)
                .font(BeagleFont.body.font)
                .lineLimit(1...4)
                .focused($focused)
                .padding(.horizontal, BeagleSpacing.sm)
                .padding(.vertical, BeagleSpacing.xs)
            Button {
                let q = draft.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !q.isEmpty else { return }
                draft = ""
                Task { await ask(q, showAsUserTurn: true) }
            } label: {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.system(size: 26))
                    .foregroundStyle(BeagleTheme.truthObserved)
            }
            .buttonStyle(.plain)
        }
        .padding(BeagleSpacing.sm)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: BeagleRadius.lg))
        .overlay(RoundedRectangle(cornerRadius: BeagleRadius.lg).strokeBorder(Color.white.opacity(0.10), lineWidth: 0.5))
        .padding(.horizontal, BeagleSpacing.md)
        .padding(.bottom, BeagleSpacing.sm)
    }

    private func ask(_ question: String, showAsUserTurn: Bool) async {
        loading = true
        // `/api/memory/query` returns raw ranked snippets (not prose) and isn't publicly proxied —
        // it only works over the tailnet. `chat()` rides the SAME companion pipeline already proven
        // live (space: "personal" → biography/`## Agora` grounding, public-reachable, authenticated),
        // so it gives a warm narrative answer instead of a snippet dump.
        let lastContact = store.conversations().map(\.updatedAt).max()
        let result = await BeagleClient.shared.chat(prompt: question, lastContactAt: lastContact)
        loading = false
        let answer = result.value?.response?.trimmingCharacters(in: .whitespacesAndNewlines)
        entries.append(MemoryLensEntry(
            question: showAsUserTurn ? question : nil,
            answer: (answer?.isEmpty == false ? answer! : nil) ?? "Não consegui buscar a memória agora — tenta de novo em instantes."
        ))
    }
}

private struct MemoryLensEntry: Identifiable {
    let id = UUID()
    let question: String?
    let answer: String
}
