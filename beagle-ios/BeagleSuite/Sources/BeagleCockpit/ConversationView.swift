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
    @State private var showVoiceMode = false
    @State private var moshi = MoshiSessionManager()

    init(conversation: ConversationStore, onRefresh: (() async -> Void)? = nil) {
        self.conversation = conversation
        self.onRefresh = onRefresh
    }

    init(conversation: ConversationStore, onRefresh: (() async -> Void)? = nil) {
        self.conversation = conversation
        self.onRefresh = onRefresh
    }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            VStack(spacing: 0) {
                discussionProfileStrip
                messageList

                // "New messages" indicator when scrolled up during streaming
                if userScrolledUp && conversation.isStreaming {
                    newMessagePill
                }

                BeagleInputBar(
                    text: ,
                    placeholder: "Talk to Beagle...",
                    mode: .chat,
                    isEnabled: !conversation.isStreaming,
                    onSubmit: { text in
                        userScrolledUp = false
                        Task { await conversation.sendMessage(text) }
                    }
                )
            }
            micButton
        }
#if os(iOS)
        .fullScreenCover(isPresented: $showVoiceMode) {
            VoiceModeView(
                moshi: moshi,
                profileColor: conversation.discussionProfile.moshiWaveformColor
            )
        }
#else
        .sheet(isPresented: $showVoiceMode) {
            VoiceModeView(
                moshi: moshi,
                profileColor: conversation.discussionProfile.moshiWaveformColor
            )
            .frame(minWidth: 480, minHeight: 640)
        }
#endif
        .onDisappear { moshi.disconnect() }
    }

    // MARK: - Mic button

    private var micButton: some View {
        Button {
            Task {
                let wsURL = URL(string: "wss://beagle.chiuratto.ai/api/moshi/v1/session")!
                let token = await BeagleClient.shared.resolvedBearerToken()
                await moshi.connect(serverURL: wsURL, bearerToken: token)
                showVoiceMode = true
            }
        } label: {
            Image(systemName: "waveform.and.mic")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(
                    moshi.connectionState == .active
                    ? conversation.discussionProfile.moshiWaveformColor
                    : BeagleTheme.textSecondary
                )
                .frame(width: 36, height: 36)
                .background(Circle().fill(BeagleTheme.surface1.opacity(0.6)))
                .overlay(
                    Circle().strokeBorder(
                        moshi.connectionState == .active
                        ? conversation.discussionProfile.moshiWaveformColor.opacity(0.3)
                        : BeagleTheme.hairline,
                        lineWidth: 1
                    )
                )
        }
        .buttonStyle(.plain)
        .padding(.top, BeagleSpacing.sm)
        .padding(.trailing, BeagleSpacing.lg)
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
        let foreground = isSelected ? BeagleTheme.truthObserved : BeagleTheme.textSecondary
        let fill = isSelected
            ? BeagleTheme.truthObserved.opacity(0.12)
            : BeagleTheme.surface1.opacity(0.45)
        let stroke = isSelected
            ? BeagleTheme.truthObserved.opacity(0.18)
            : BeagleTheme.hairline

        return Button {
            conversation.discussionProfile = profile
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
