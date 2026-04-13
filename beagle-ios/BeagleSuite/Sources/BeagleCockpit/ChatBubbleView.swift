//
//  ChatBubbleView.swift
//  BeagleCockpit
//
//  Chat bubble renderer for conversation messages.
//  User messages right-aligned, assistant messages left-aligned.
//  Markdown rendering in assistant responses, streaming cursor animation.
//

import SwiftUI
import BeagleCore

struct ChatBubbleView: View {
    let message: ChatMessage
    var onRegenerate: (() -> Void)?

    @State private var cursorVisible = true

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            if message.role == .user {
                Spacer(minLength: 60)
            }

            bubbleContent
                .contextMenu { contextMenuItems }

            if message.role == .assistant {
                Spacer(minLength: 60)
            }
        }
        .padding(.horizontal, BeagleSpacing.md)
        .padding(.vertical, BeagleSpacing.xxs)
    }

    // MARK: - Bubble content

    private var bubbleContent: some View {
        VStack(alignment: message.role == .user ? .trailing : .leading, spacing: BeagleSpacing.xxs) {
            messageBody
            messageFooter
        }
    }

    private var messageBody: some View {
        Group {
            if message.role == .user {
                userBubble
            } else {
                assistantBubble
            }
        }
    }

    // MARK: - User bubble

    private var userBubble: some View {
        Text(message.content)
            .font(BeagleFont.body.font)
            .foregroundStyle(BeagleTheme.textPrimary)
            .padding(.horizontal, BeagleSpacing.md)
            .padding(.vertical, BeagleSpacing.sm)
            .background(
                RoundedRectangle(cornerRadius: BeagleRadius.lg)
                    .fill(BeagleTheme.truthObserved.opacity(0.15))
            )
            .overlay(
                RoundedRectangle(cornerRadius: BeagleRadius.lg)
                    .strokeBorder(BeagleTheme.truthObserved.opacity(0.1), lineWidth: 1)
            )
    }

    // MARK: - Assistant bubble

    private var assistantBubble: some View {
        VStack(alignment: .leading, spacing: 0) {
            if message.isStreaming && message.content.isEmpty {
                streamingPlaceholder
            } else {
                renderedContent
            }
        }
        .padding(.horizontal, BeagleSpacing.md)
        .padding(.vertical, BeagleSpacing.sm)
        .background(
            RoundedRectangle(cornerRadius: BeagleRadius.lg)
                .fill(BeagleTheme.surface2)
        )
        .overlay(
            RoundedRectangle(cornerRadius: BeagleRadius.lg)
                .strokeBorder(Color.white.opacity(0.06), lineWidth: 1)
        )
    }

    private var streamingPlaceholder: some View {
        HStack(spacing: BeagleSpacing.xs) {
            ProgressView()
                .controlSize(.small)
            Text("Thinking...")
                .font(BeagleFont.footnote.font)
                .foregroundStyle(BeagleTheme.textSecondary)
        }
    }

    @ViewBuilder
    private var renderedContent: some View {
        if let attributed = try? AttributedString(markdown: message.content, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)) {
            Text(attributed)
                .font(BeagleFont.body.font)
                .foregroundStyle(BeagleTheme.textPrimary)
                .textSelection(.enabled)
        } else {
            Text(message.content)
                .font(BeagleFont.body.font)
                .foregroundStyle(BeagleTheme.textPrimary)
                .textSelection(.enabled)
        }

        if message.isStreaming {
            streamingCursor
        }
    }

    private var streamingCursor: some View {
        Text("|")
            .font(BeagleFont.body.font)
            .fontWeight(.semibold)
            .foregroundStyle(BeagleTheme.truthObserved)
            .opacity(cursorVisible ? 1 : 0)
            .onAppear {
                withAnimation(.easeInOut(duration: 0.5).repeatForever(autoreverses: true)) {
                    cursorVisible = false
                }
            }
    }

    // MARK: - Footer (timestamp, model, tokens)

    @ViewBuilder
    private var messageFooter: some View {
        HStack(spacing: BeagleSpacing.xs) {
            Text(message.timestamp, style: .time)
                .font(BeagleFont.caption2.font)
                .foregroundStyle(BeagleTheme.textTertiary)

            if let model = message.model {
                HStack(spacing: 2) {
                    if message.isLocal {
                        Image(systemName: "iphone")
                            .font(.system(size: 8))
                    }
                    Text(model)
                }
                .font(BeagleFont.caption2.font)
                .foregroundStyle(message.isLocal ? BeagleTheme.truthObserved.opacity(0.6) : BeagleTheme.textTertiary)
            }

            if let tokens = message.tokensUsed, tokens > 0 {
                Text("\(tokens) tok")
                    .font(BeagleFont.caption2.font)
                    .foregroundStyle(BeagleTheme.textTertiary)
            }
        }
    }

    // MARK: - Context menu

    @ViewBuilder
    private var contextMenuItems: some View {
        Button {
            #if os(iOS)
            UIPasteboard.general.string = message.content
            #elseif os(macOS)
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(message.content, forType: .string)
            #endif
        } label: {
            Label("Copy", systemImage: "doc.on.doc")
        }

        if message.role == .assistant, let onRegenerate {
            Button {
                onRegenerate()
            } label: {
                Label("Regenerate", systemImage: "arrow.clockwise")
            }
        }
    }
}
