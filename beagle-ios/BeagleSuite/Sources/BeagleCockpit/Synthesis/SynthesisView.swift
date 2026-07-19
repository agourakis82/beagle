// SynthesisView.swift — the deliberate synthesis surface (a sheet opened from the drawer
// footer). Streams the 5-block markdown from /api/mobile/v1/synthesize. THE HARD WALL:
// the result lives ONLY in this view's @State — it is never appended to ConversationStore,
// never persisted, never shown in the chat. Dismiss = discard. No chat imports.
import SwiftUI
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

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    TextField("sobre o quê?  (vazio = os últimos dias)", text: $topic, axis: .vertical)
                        .textFieldStyle(.plain)
                        .padding(12)
                        .background(RoundedRectangle(cornerRadius: 12).fill(.quaternary.opacity(0.4)))
                        .disabled(phase == .streaming)

                    Button(action: start) {
                        Text(phase == .streaming ? "sintetizando…" : "Sintetizar")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(phase == .streaming)

                    if !markdown.isEmpty {
                        renderMarkdown(markdown)
                    }

                    if phase == .done || phase == .insufficient {
                        HStack {
                            Button("nova síntese") { reset() }
                            Spacer()
                            if phase == .done {
                                Button { copy() } label: { Label("copiar", systemImage: "doc.on.doc") }
                            }
                        }
                        .font(.footnote)
                        .padding(.top, 4)
                    }

                    if case .error(let msg) = phase {
                        Text(msg).foregroundStyle(.red).font(.footnote)
                        Button("tentar de novo", action: start).font(.footnote)
                    }
                }
                .padding()
            }
            .navigationTitle("Síntese")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button { work?.cancel(); dismiss() } label: { Image(systemName: "xmark") }
                }
            }
        }
        .onDisappear { work?.cancel() }
    }

    private func start() {
        work?.cancel()
        markdown = ""
        phase = .streaming
        let t = topic
        work = Task {
            do {
                for try await chunk in SynthesisClient().stream(topic: t) {
                    switch chunk {
                    case .token(let tok):
                        markdown += tok
                    case .done(let insufficient, let err):
                        if let err { phase = .error(err) }
                        else { phase = insufficient ? .insufficient : .done }
                    }
                }
                if phase == .streaming { phase = .done }
            } catch is CancellationError {
                // dismissed / cancelled — leave state
            } catch {
                phase = .error(error.localizedDescription)
            }
        }
    }

    private func reset() { work?.cancel(); markdown = ""; topic = ""; phase = .idle }

    private func copy() {
        #if canImport(UIKit)
        UIPasteboard.general.string = markdown
        #endif
    }

    // Small LOCAL markdown renderer — the 5 blocks are only `##` headings + paragraphs +
    // bullets. Deliberately does NOT import the chat's fileprivate renderer (keeps the chat
    // file untouched — the wall).
    @ViewBuilder
    private func renderMarkdown(_ text: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(text.split(separator: "\n", omittingEmptySubsequences: false).enumerated()), id: \.offset) { _, raw in
                let trimmed = String(raw).trimmingCharacters(in: .whitespaces)
                if trimmed.hasPrefix("## ") {
                    Text(String(trimmed.dropFirst(3))).font(.headline).padding(.top, 6)
                } else if trimmed.hasPrefix("# ") {
                    Text(String(trimmed.dropFirst(2))).font(.title3.bold()).padding(.top, 6)
                } else if trimmed.hasPrefix("- ") || trimmed.hasPrefix("* ") {
                    HStack(alignment: .top, spacing: 8) {
                        Text("•")
                        Text(inline(String(trimmed.dropFirst(2))))
                    }
                } else if trimmed.isEmpty {
                    Color.clear.frame(height: 2)
                } else {
                    Text(inline(trimmed))
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .textSelection(.enabled)
    }

    private func inline(_ s: String) -> AttributedString {
        (try? AttributedString(markdown: s)) ?? AttributedString(s)
    }
}
