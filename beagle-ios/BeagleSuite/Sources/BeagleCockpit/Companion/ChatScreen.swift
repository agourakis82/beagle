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
    @State private var draft = ""

    public init(store: ConversationStore) {
        self.store = store
    }

    public var body: some View {
        ZStack(alignment: .bottom) {
            conversation
            composer
        }
    }

    // MARK: - Conversation (flat content above the mesh)

    private var conversation: some View {
        ScrollViewReader { proxy in
            ScrollView {
                if store.messages.isEmpty {
                    greeting.padding(.top, BeagleSpacing.jumbo)
                }
                LazyVStack(spacing: BeagleSpacing.sm) {
                    ForEach(store.messages) { message in
                        MessageBubble(message: message)
                            .id(message.id)
                    }
                    // clearance so the floating composer never covers the last line
                    Color.clear.frame(height: 72).id(Self.bottomAnchor)
                }
                .padding(.horizontal, BeagleSpacing.md)
                .padding(.top, BeagleSpacing.md)
                .animation(.easeOut(duration: 0.25), value: store.messages.count)
            }
            .scrollDismissesKeyboard(.interactively)
            .onChange(of: store.messages.last?.content) { _, _ in
                withAnimation(.easeOut(duration: 0.18)) { proxy.scrollTo(Self.bottomAnchor, anchor: .bottom) }
            }
            .onChange(of: store.messages.count) { _, _ in
                proxy.scrollTo(Self.bottomAnchor, anchor: .bottom)
            }
        }
    }

    // MARK: - Composer (the only glass)

    private var composer: some View {
        ChatComposer(
            text: $draft,
            isStreaming: store.isStreaming,
            onSend: send,
            onAttach: {},   // TODO: multimodal image attach (iOS 27 Foundation Models)
            onVoice: {}     // TODO: voice capture
        )
        .padding(.horizontal, BeagleSpacing.md)
        .padding(.bottom, BeagleSpacing.xs)
    }

    // MARK: - Empty state (warm, zero-friction — no forms)

    private var greeting: some View {
        VStack(spacing: BeagleSpacing.sm) {
            Image(systemName: "sparkles")
                .font(.system(size: 32, weight: .light))
                .foregroundStyle(BeagleTheme.truthObserved)
            Text("Estou aqui.")
                .font(BeagleFont.title2.font)
                .foregroundStyle(BeagleTheme.companionInk)
            Text("Conta o que está passando — eu lembro de ti.")
                .font(BeagleFont.subheadline.font)
                .foregroundStyle(BeagleTheme.textSecondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, BeagleSpacing.xl)
    }

    // MARK: - Send

    private func send() {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        draft = ""
        Task { await store.sendMessage(text) }
    }

    private static let bottomAnchor = "companion.chat.bottom"
}
