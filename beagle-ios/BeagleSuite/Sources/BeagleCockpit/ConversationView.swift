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
    let onRefresh: (() async -> Void)?
    @State private var inputText = ""
    @State private var userScrolledUp = false
    @State private var showHarvestSheet = false

    private var profilePlaceholder: String {
        switch conversation.discussionProfile {
        case .cluster:    return "Talk to Beagle..."
        case .qwen3b:     return "Ask Qwen..."
        case .yi6b:       return "Ask Yi..."
        case .grok:       return "Ask Grok..."
        case .kimi:       return "Ask Kimi..."
        case .claudeCode: return "Ask Claude Code..."
        case .codex:      return "Ask Codex..."
        }
    }

    init(conversation: ConversationStore, onRefresh: (() async -> Void)? = nil) {
        self.conversation = conversation
        self.onRefresh = onRefresh
    }

    var body: some View {
        VStack(spacing: 0) {
            discussionProfileStrip
            messageList

            // "New messages" indicator when scrolled up during streaming
            if userScrolledUp && conversation.isStreaming {
                newMessagePill
            }

            if conversation.isStreaming {
                streamingContextBar
            }

            BeagleInputBar(
                text: $inputText,
                placeholder: "Talk to Beagle...",
                mode: .chat,
                isEnabled: !conversation.isStreaming,
                onSubmit: { text in
                    userScrolledUp = false
                    conversation.submitMessage(text)
                },
                onStop: {
                    conversation.stopStreaming()
                }
            )
        }
    }

    private var discussionProfileStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: BeagleSpacing.xs) {
                ForEach(DiscussionProfile.allCases) { profile in
                    discussionProfileButton(for: profile)
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, BeagleSpacing.lg)
            .padding(.top, BeagleSpacing.sm)
            .padding(.bottom, BeagleSpacing.xs)
        }
    }

    private func discussionProfileButton(for profile: DiscussionProfile) -> some View {
        let isSelected = conversation.discussionProfile == profile
        let hue = BeagleTheme.profileHue(for: profile)
        let foreground = isSelected ? hue : BeagleTheme.textSecondary
        let fill = isSelected ? hue.opacity(0.18) : BeagleTheme.surface1.opacity(0.45)
        let stroke = isSelected ? hue.opacity(0.40) : BeagleTheme.hairline

        return Button {
            #if os(iOS)
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            #endif
            withAnimation(.spring(response: 0.38, dampingFraction: 0.72)) {
                conversation.discussionProfile = profile
            }
        } label: {
            HStack(spacing: BeagleSpacing.xs) {
                Image(systemName: profile.iconName)
                    .font(.system(size: 12, weight: .semibold))
                VStack(alignment: .leading, spacing: 1) {
                    Text(profile.label)
                        .font(BeagleFont.caption.font)
                        .fontWeight(.semibold)
                    Text(profile.subtitle)
                        .font(BeagleFont.caption2.font)
                }
            }
            .foregroundStyle(foreground)
            .padding(.horizontal, BeagleSpacing.sm)
            .padding(.vertical, BeagleSpacing.xs)
            .background(Capsule().fill(fill))
            .overlay(Capsule().strokeBorder(stroke, lineWidth: 1))
        }
        .animation(.spring(response: 0.38, dampingFraction: 0.72), value: isSelected)
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
            .refreshable {
                if let onRefresh {
                    await onRefresh()
                }
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

    // MARK: - Streaming context bar

    private var streamingContextBar: some View {
        HStack(spacing: BeagleSpacing.xs) {
            Image(systemName: conversation.discussionProfile.iconName)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(BeagleTheme.truthObserved)
            Text(conversation.discussionProfile.label)
                .font(BeagleFont.caption2.font)
                .fontWeight(.semibold)
                .foregroundStyle(BeagleTheme.textSecondary)
            Text("·")
                .foregroundStyle(BeagleTheme.textTertiary)
                .font(BeagleFont.caption2.font)
            Text("responding")
                .font(BeagleFont.caption2.font)
                .foregroundStyle(BeagleTheme.textTertiary)
            Spacer()
        }
        .padding(.horizontal, BeagleSpacing.lg)
        .padding(.vertical, BeagleSpacing.xxs)
        .transition(.move(edge: .bottom).combined(with: .opacity))
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

                Text("Start with the mind in your hand. When the work needs more reach, Beagle can lean on the cluster.")
                    .font(BeagleFont.footnote.font)
                    .foregroundStyle(BeagleTheme.textTertiary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, BeagleSpacing.xxl)
            }

            CognitiveBridgeField(
                localWeight: 1.0,
                bridgeWeight: 0.66,
                clusterWeight: 0.52,
                emphasis: .talk
            )
            .padding(.horizontal, BeagleSpacing.lg)

            HStack(spacing: BeagleSpacing.xs) {
                PresencePill(label: "On Device", systemImage: "iphone", tint: BeagleTheme.truthObserved)
                PresencePill(label: "Cluster", systemImage: "server.rack", tint: BeagleTheme.truthRemembered)
            }

            // Thought starters
            VStack(spacing: BeagleSpacing.xs) {
                thoughtStarter(
                    "Help me think this through from the device first.",
                    icon: "link", color: BeagleTheme.truthObserved
                )
                thoughtStarter(
                    "What has the cluster been doing while I was away?",
                    icon: "sparkles", color: BeagleTheme.postureWarm
                )
                thoughtStarter(
                    "Which thread should we pursue next?",
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
            conversation.submitMessage(text)
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
