//
//  MessageBubble.swift
//  BeagleCockpit — Companion chat
//
//  A FLAT, opaque, directional message bubble (Messages-style). Per the design system:
//  glass is chrome only — bubbles never use glass. The companion's voice is warm
//  (`companionSurface`/`companionInk`); the user is cool (`userSurface`). Streaming shows
//  a breathing presence dot, not a spinner. Memory grounding shows a provenance chip.
//  See docs/design/2026-06-24-companion-design-system.md (§4 Components).
//

import SwiftUI
import BeagleCore

struct MessageBubble: View {
    let message: ChatMessage

    private var isUser: Bool { message.role == .user }

    var body: some View {
        HStack(spacing: 0) {
            if isUser { Spacer(minLength: BeagleSpacing.xxl) }

            VStack(alignment: isUser ? .trailing : .leading, spacing: BeagleSpacing.xxs) {
                bubble
                if !isUser, let provenance = groundingLabel {
                    MemoryProvenanceChip(label: provenance)
                }
            }

            if !isUser { Spacer(minLength: BeagleSpacing.xxl) }
        }
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }

    // MARK: - Bubble

    private var bubble: some View {
        Text(displayText)
            .font(BeagleFont.body.font)
            .foregroundStyle(isUser ? BeagleTheme.textPrimary : BeagleTheme.companionInk)
            .textSelection(.enabled)
            .padding(.vertical, BeagleSpacing.sm)
            .padding(.horizontal, BeagleSpacing.md)
            .background(isUser ? BeagleTheme.userSurface : BeagleTheme.companionSurface, in: bubbleShape)
            .overlay(alignment: .bottomTrailing) {
                if message.isStreaming { StreamingDot().padding(BeagleSpacing.xs) }
            }
            .frame(maxWidth: 540, alignment: isUser ? .trailing : .leading)
    }

    /// While streaming with no text yet, keep the bubble from collapsing.
    private var displayText: String {
        if message.content.isEmpty && message.isStreaming { return "…" }
        return message.content
    }

    private var bubbleShape: UnevenRoundedRectangle {
        let r = BeagleRadius.lg
        let tail: CGFloat = 4
        return UnevenRoundedRectangle(
            topLeadingRadius: r,
            bottomLeadingRadius: isUser ? r : tail,
            bottomTrailingRadius: isUser ? tail : r,
            topTrailingRadius: r
        )
    }

    /// Quiet provenance when the companion grounded on memory/physiome (finding 7).
    private var groundingLabel: String? {
        guard let source = message.source, !source.isEmpty else { return nil }
        switch source {
        case "physiome", "physiome-digest": return "do teu corpo"
        case "exocortex", "memory", "recall": return "do que lembro de ti"
        default: return nil
        }
    }
}

// MARK: - Streaming presence (breathing dot, not a spinner)

private struct StreamingDot: View {
    @State private var on = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Circle()
            .fill(BeagleTheme.truthObserved)
            .frame(width: 7, height: 7)
            .opacity(on ? 1.0 : 0.35)
            .onAppear {
                guard !reduceMotion else { on = true; return }
                withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) { on = true }
            }
            .accessibilityLabel("respondendo")
    }
}

// MARK: - Memory provenance chip

private struct MemoryProvenanceChip: View {
    let label: String

    var body: some View {
        HStack(spacing: BeagleSpacing.xxs) {
            Image(systemName: "sparkle")
                .font(.system(size: 9, weight: .semibold))
            Text(label)
                .font(BeagleFont.caption2.font)
        }
        .foregroundStyle(BeagleTheme.memoryGrounded)
        .padding(.horizontal, BeagleSpacing.xs)
        .padding(.vertical, 2)
        .background(BeagleTheme.memoryGrounded.opacity(0.12), in: Capsule())
        .padding(.leading, BeagleSpacing.xs)
    }
}
