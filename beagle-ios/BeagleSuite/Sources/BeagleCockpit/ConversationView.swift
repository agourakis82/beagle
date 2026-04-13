//
//  ConversationView.swift
//  BeagleCockpit
//
//  Full conversation view with message list, smart scroll, and input bar.
//  Used in the Capture tab for interactive chat with the exocortex.
//

import SwiftUI
import BeagleCore

struct ConversationView: View {
    @Bindable var conversation: ConversationStore
    @State private var inputText = ""

    var body: some View {
        VStack(spacing: 0) {
            messageList
            BeagleInputBar(
                text: $inputText,
                placeholder: "Ask the exocortex...",
                mode: .chat,
                isEnabled: !conversation.isStreaming,
                onSubmit: { text in
                    Task { await conversation.sendMessage(text) }
                }
            )
        }
    }

    // MARK: - Message list

    private var messageList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: BeagleSpacing.xxs) {
                    if conversation.isEmpty {
                        emptyState
                    } else {
                        ForEach(conversation.messages) { message in
                            ChatBubbleView(
                                message: message,
                                onRegenerate: message.role == .assistant ? {
                                    Task { await conversation.regenerateLastResponse() }
                                } : nil
                            )
                            .id(message.id)
                        }
                    }
                }
                .padding(.vertical, BeagleSpacing.md)
            }
            .onChange(of: conversation.messages.count) {
                if let last = conversation.messages.last {
                    withAnimation(BeagleMotion.fast) {
                        proxy.scrollTo(last.id, anchor: .bottom)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Empty state

    private var emptyState: some View {
        VStack(spacing: BeagleSpacing.md) {
            Image(systemName: "sparkles")
                .font(.system(size: 32))
                .foregroundStyle(BeagleTheme.textTertiary.opacity(0.4))
            Text("Start a conversation")
                .font(BeagleFont.footnote.font)
                .foregroundStyle(BeagleTheme.textTertiary)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, BeagleSpacing.jumbo)
    }
}
