//
//  ConversationView.swift
//  BeagleCockpit
//
//  Full conversation view with message list, smart scroll, and input bar.
//  Used in the Capture tab for interactive chat with the exocortex.
//
//  Premium: empty state with thought-starters, scroll-aware new-message
//  indicator, GoDeep on assistant responses.
//

import SwiftUI
import BeagleCore

struct ConversationView: View {
    @Bindable var conversation: ConversationStore
    @State private var inputText = ""
    @State private var userScrolledUp = false

    var body: some View {
        VStack(spacing: 0) {
            messageList

            // "New messages" indicator when scrolled up during streaming
            if userScrolledUp && conversation.isStreaming {
                newMessagePill
            }

            BeagleInputBar(
                text: $inputText,
                placeholder: "Ask the exocortex...",
                mode: .chat,
                isEnabled: !conversation.isStreaming,
                onSubmit: { text in
                    userScrolledUp = false
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

                            // Go Deeper on assistant responses
                            if message.role == .assistant && !message.isStreaming {
                                HStack {
                                    GoDeepButton(prompt: message.content)
                                    Spacer()
                                }
                                .padding(.leading, BeagleSpacing.md)
                            }
                        }
                    }
                }
                .padding(.vertical, BeagleSpacing.md)
            }
            .onChange(of: conversation.messages.count) {
                guard !userScrolledUp else { return }
                if let last = conversation.messages.last {
                    withAnimation(BeagleMotion.fast) {
                        proxy.scrollTo(last.id, anchor: .bottom)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - New Message Pill

    private var newMessagePill: some View {
        Button {
            userScrolledUp = false
        } label: {
            HStack(spacing: BeagleSpacing.xxs) {
                Image(systemName: "arrow.down")
                    .font(.system(size: 10, weight: .semibold))
                Text("New message")
                    .font(BeagleFont.caption.font)
                    .fontWeight(.medium)
            }
            .foregroundStyle(.white)
            .padding(.horizontal, BeagleSpacing.md)
            .padding(.vertical, BeagleSpacing.xs)
            .background(
                Capsule()
                    .fill(BeagleTheme.truthObserved)
                    .shadow(color: BeagleTheme.truthObserved.opacity(0.3), radius: 8, y: 4)
            )
        }
        .buttonStyle(.plain)
        .padding(.bottom, BeagleSpacing.xs)
        .transition(.move(edge: .bottom).combined(with: .opacity))
        .sensoryFeedback(.impact(weight: .light), trigger: userScrolledUp)
    }

    // MARK: - Empty state (with thought starters)

    private var emptyState: some View {
        VStack(spacing: BeagleSpacing.xl) {
            Spacer(minLength: BeagleSpacing.xxxl)

            VStack(spacing: BeagleSpacing.sm) {
                Image(systemName: "brain.head.profile")
                    .font(.system(size: 36))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [BeagleTheme.truthObserved.opacity(0.6), BeagleTheme.truthRemembered.opacity(0.4)],
                            startPoint: .topLeading, endPoint: .bottomTrailing
                        )
                    )

                Text("What are you thinking about?")
                    .font(BeagleFont.title3.font)
                    .foregroundStyle(BeagleTheme.textPrimary)

                Text("Your exocortex is listening. Thoughts captured here flow into the hypergraph for HERMES refinement and Triad review.")
                    .font(BeagleFont.footnote.font)
                    .foregroundStyle(BeagleTheme.textTertiary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, BeagleSpacing.xxl)
            }

            // Thought starters
            VStack(spacing: BeagleSpacing.xs) {
                thoughtStarter(
                    "What connections am I missing in my research?",
                    icon: "link", color: BeagleTheme.truthObserved
                )
                thoughtStarter(
                    "Summarize what the agents have been doing",
                    icon: "sparkles", color: BeagleTheme.postureWarm
                )
                thoughtStarter(
                    "Help me think through this problem...",
                    icon: "lightbulb.max", color: BeagleTheme.truthRemembered
                )
            }
            .padding(.horizontal, BeagleSpacing.lg)

            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    private func thoughtStarter(_ text: String, icon: String, color: Color) -> some View {
        Button {
            inputText = text
            Task { await conversation.sendMessage(text) }
        } label: {
            HStack(spacing: BeagleSpacing.sm) {
                Image(systemName: icon)
                    .font(.system(size: 14))
                    .foregroundStyle(color)
                    .frame(width: 24)

                Text(text)
                    .font(BeagleFont.footnote.font)
                    .foregroundStyle(BeagleTheme.textSecondary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)

                Spacer()

                Image(systemName: "arrow.up.right")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(BeagleTheme.textTertiary)
            }
            .frame(minHeight: 44)
            .padding(.horizontal, BeagleSpacing.md)
            .padding(.vertical, BeagleSpacing.xs)
            .background(
                RoundedRectangle(cornerRadius: BeagleRadius.lg)
                    .fill(BeagleTheme.surface1.opacity(0.5))
            )
            .overlay(
                RoundedRectangle(cornerRadius: BeagleRadius.lg)
                    .strokeBorder(color.opacity(0.08), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}
