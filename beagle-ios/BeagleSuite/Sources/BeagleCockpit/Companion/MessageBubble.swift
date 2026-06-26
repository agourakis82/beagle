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

    @State private var showThinking = false

    private var isUser: Bool { message.role == .user }

    var body: some View {
        HStack(spacing: 0) {
            if isUser { Spacer(minLength: BeagleSpacing.xxl) }

            VStack(alignment: isUser ? .trailing : .leading, spacing: BeagleSpacing.xxs) {
                bubble
                if !isUser, let thinking = parsed.thinking {
                    thinkingDisclosure(thinking)
                }
                if !isUser, let provenance = groundingLabel {
                    MemoryProvenanceChip(label: provenance)
                }
            }

            if !isUser { Spacer(minLength: BeagleSpacing.xxl) }
        }
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }

    /// Split the companion's internal note (presence framing + "Nota rápida" reasoning)
    /// from the warm message it actually says. The model puts the note above a `---` rule.
    private var parsed: (message: String, thinking: String?) {
        let c = message.content
        guard let r = c.range(of: "\n---\n") ?? c.range(of: "\n---") else { return (c, nil) }
        let before = c[..<r.lowerBound].trimmingCharacters(in: .whitespacesAndNewlines)
        let after = c[r.upperBound...].trimmingCharacters(in: .whitespacesAndNewlines)
        let looksLikeNote = ["nota", "pergunta viva", "interpretação", "próximo movimento", "abana"]
            .contains { before.range(of: $0, options: .caseInsensitive) != nil }
        return (after.isEmpty || !looksLikeNote) ? (c, nil) : (after, before)
    }

    @ViewBuilder
    private func thinkingDisclosure(_ thinking: String) -> some View {
        VStack(alignment: .leading, spacing: BeagleSpacing.xs) {
            Button {
                withAnimation(.snappy(duration: 0.25)) { showThinking.toggle() }
            } label: {
                HStack(spacing: BeagleSpacing.xxs) {
                    Image(systemName: showThinking ? "chevron.down" : "chevron.right")
                        .font(.system(size: 9, weight: .semibold))
                    Text(showThinking ? "esconder o que penso" : "ver o que penso")
                        .font(BeagleFont.caption2.font)
                }
                .foregroundStyle(BeagleTheme.textTertiary)
            }
            .buttonStyle(.plain)

            if showThinking {
                Text(thinking)
                    .font(BeagleFont.footnote.font)
                    .foregroundStyle(BeagleTheme.textSecondary)
                    .padding(BeagleSpacing.sm)
                    .background(BeagleTheme.companionSurface.opacity(0.5), in: RoundedRectangle(cornerRadius: BeagleRadius.md))
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(.leading, BeagleSpacing.xs)
    }

    // MARK: - Bubble

    /// Companion is thinking — request in flight, no text yet.
    private var isThinking: Bool { !isUser && message.isStreaming && message.content.isEmpty }

    private var bubble: some View {
        Group {
            if isThinking {
                TypingIndicator()
                    .padding(.vertical, 14)
                    .padding(.horizontal, BeagleSpacing.md)
            } else {
                Text(isUser ? message.content : parsed.message)
                    .font(BeagleFont.body.font)
                    .foregroundStyle(isUser ? BeagleTheme.textPrimary : BeagleTheme.companionInk)
                    .textSelection(.enabled)
                    .padding(.vertical, BeagleSpacing.sm)
                    .padding(.horizontal, BeagleSpacing.md)
            }
        }
        .background(isUser ? BeagleTheme.userSurface : BeagleTheme.companionSurface, in: bubbleShape)
        .frame(maxWidth: 540, alignment: isUser ? .trailing : .leading)
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

private struct TypingIndicator: View {
    @State private var animate = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 5) {
            ForEach(0..<3, id: \.self) { i in
                Circle()
                    .fill(BeagleTheme.companionInk.opacity(0.75))
                    .frame(width: 7, height: 7)
                    .scaleEffect(animate ? 1.0 : 0.5)
                    .opacity(animate ? 1.0 : 0.4)
                    .animation(
                        reduceMotion ? nil :
                            .easeInOut(duration: 0.6).repeatForever().delay(Double(i) * 0.18),
                        value: animate)
            }
        }
        .onAppear { animate = true }
        .accessibilityLabel("pensando")
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
