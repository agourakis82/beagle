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
    var profileHue: Color = BeagleTheme.truthObserved
    var verificationResult: VerificationResult? = nil
    var onCheckSources: (() -> Void)? = nil

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
            if message.role == .assistant, let result = verificationResult {
                VerificationStrip(result: result, profileHue: profileHue)
            }
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
            .lineSpacing(3)
            .foregroundStyle(BeagleTheme.textPrimary)
            .padding(.horizontal, BeagleSpacing.md)
            .padding(.vertical, BeagleSpacing.sm)
            .background(
                RoundedRectangle(cornerRadius: BeagleRadius.lg)
                    .fill(Color.white.opacity(0.07))
                    .overlay(
                        LinearGradient(
                            colors: [.black.opacity(0.08), .clear],
                            startPoint: .top, endPoint: .bottom
                        )
                        .clipShape(RoundedRectangle(cornerRadius: BeagleRadius.lg))
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: BeagleRadius.lg)
                    .strokeBorder(Color.white.opacity(0.12), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.3), radius: 4, x: 0, y: 2)
    }

    // MARK: - Assistant bubble

    private var assistantBubble: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Voice header for Round Table messages
            if let voiceName = message.voiceName {
                voiceHeader(voiceName)
            }

            if message.isStreaming && message.content.isEmpty {
                streamingPlaceholder
                    .transition(.opacity)
            } else {
                renderedContent
                    .transition(.opacity)
            }
        }
        .animation(BeagleMotion.fast, value: message.isStreaming && message.content.isEmpty)
        .padding(.horizontal, BeagleSpacing.md)
        .padding(.vertical, BeagleSpacing.sm)
        .background(.ultraThinMaterial)
        .overlay(alignment: .leading) {
            Rectangle()
                .fill(message.voiceName != nil ? voiceTint : profileHue)
                .frame(width: 3)
                .clipShape(UnevenRoundedRectangle(
                    topLeadingRadius: BeagleRadius.lg,
                    bottomLeadingRadius: BeagleRadius.lg,
                    bottomTrailingRadius: 0,
                    topTrailingRadius: 0
                ))
        }
        .clipShape(RoundedRectangle(cornerRadius: BeagleRadius.lg))
        .overlay(
            RoundedRectangle(cornerRadius: BeagleRadius.lg)
                .strokeBorder(
                    message.voiceName != nil ? voiceTint.opacity(0.2) : Color.white.opacity(0.06),
                    lineWidth: 1
                )
        )
        .shadow(
            color: (message.voiceName != nil ? voiceTint : profileHue).opacity(0.18),
            radius: 12, x: 0, y: 4
        )
    }

    // MARK: - Voice header (Round Table)

    private func voiceHeader(_ name: String) -> some View {
        HStack(spacing: BeagleSpacing.xs) {
            Image(systemName: voiceIcon(for: name))
                .font(.system(size: 10, weight: .semibold))
            Text(name.capitalized)
                .font(BeagleFont.caption.font)
                .fontWeight(.semibold)
        }
        .foregroundStyle(voiceTint)
        .padding(.bottom, BeagleSpacing.xs)
    }

    private var voiceTint: Color {
        guard let name = message.voiceName?.lowercased() else { return BeagleTheme.textSecondary }
        switch name {
        case "consciousness": return Color(hue: 0.55, saturation: 0.6, brightness: 0.9) // teal
        case "mirror":        return Color(hue: 0.6, saturation: 0.5, brightness: 0.85)  // blue
        case "paradox":       return Color(hue: 0.8, saturation: 0.5, brightness: 0.9)   // purple
        case "void":          return Color(hue: 0.0, saturation: 0.0, brightness: 0.65)   // gray
        case "reality":       return Color(hue: 0.1, saturation: 0.7, brightness: 0.9)    // amber
        case "noetic":        return Color(hue: 0.35, saturation: 0.5, brightness: 0.85)  // green
        case "quantum":       return Color(hue: 0.7, saturation: 0.6, brightness: 0.9)    // indigo
        case "fractal":       return Color(hue: 0.3, saturation: 0.6, brightness: 0.8)    // lime
        case "cosmo":         return Color(hue: 0.15, saturation: 0.5, brightness: 0.9)   // gold
        default:
            return name.lowercased().contains("synthesis")
                ? BeagleTheme.truthObserved
                : BeagleTheme.textSecondary
        }
    }

    private var voiceFill: Color {
        voiceTint.opacity(0.06)
    }

    private func voiceIcon(for name: String) -> String {
        switch name.lowercased() {
        case "consciousness": return "brain"
        case "mirror":        return "eye"
        case "paradox":       return "infinity"
        case "void":          return "circle.dotted"
        case "reality":       return "cube.transparent"
        case "noetic":        return "network"
        case "quantum":       return "waveform"
        case "fractal":       return "leaf"
        case "cosmo":         return "globe"
        default:
            return name.lowercased().contains("synthesis") ? "sparkles" : "circle"
        }
    }

    private var streamingPlaceholder: some View {
        ThinkingIndicator()
    }

    @ViewBuilder
    private var renderedContent: some View {
        MarkdownMessage(content: message.content)

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

            if message.role == .assistant {
                PresencePill(
                    label: provenanceLabel,
                    systemImage: provenanceSystemImage,
                    tint: provenanceTint
                )
                if let agentKind = message.agentKind, !agentKind.isEmpty {
                    PresencePill(
                        label: agentKindDisplayName(agentKind),
                        systemImage: "sparkles.rectangle.stack",
                        tint: BeagleTheme.truthRemembered
                    )
                }
            }

            if let model = message.model {
                Text(model)
                    .font(BeagleFont.caption2.font)
                    .foregroundStyle(message.isLocal ? BeagleTheme.truthObserved.opacity(0.6) : BeagleTheme.textTertiary)
            }

            if let tokens = message.tokensUsed, tokens > 0 {
                Text("\(tokens) tok")
                    .font(BeagleFont.caption2.font)
                    .foregroundStyle(BeagleTheme.textTertiary)
            }

            if message.role == .assistant && message.savedToMemory {
                PresencePill(
                    label: "Memory",
                    systemImage: "checkmark.circle.fill",
                    tint: BeagleTheme.truthObserved
                )
            }
        }
    }

    private var provenanceLabel: String {
        switch normalizedSource {
        case "device":
            return "On Device"
        case "agent":
            return "Agent"
        case "hybrid":
            return "Hybrid"
        default:
            return message.isLocal ? "On Device" : "Cluster"
        }
    }

    private var provenanceSystemImage: String {
        switch normalizedSource {
        case "device":
            return "iphone"
        case "agent":
            return "sparkles.rectangle.stack"
        case "hybrid":
            return "point.3.connected.trianglepath.dotted"
        default:
            return message.isLocal ? "iphone" : "server.rack"
        }
    }

    private var provenanceTint: Color {
        switch normalizedSource {
        case "device":
            return BeagleTheme.truthObserved
        case "agent":
            return BeagleTheme.truthRemembered
        case "hybrid":
            return BeagleTheme.truthObserved.opacity(0.9)
        default:
            return message.isLocal ? BeagleTheme.truthObserved : BeagleTheme.truthRemembered
        }
    }

    private var normalizedSource: String {
        message.source?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased() ?? ""
    }

    private func agentKindDisplayName(_ agentKind: String) -> String {
        agentKind
            .split(separator: "-", omittingEmptySubsequences: true)
            .map { segment in
                segment.prefix(1).uppercased() + segment.dropFirst().lowercased()
            }
            .joined(separator: " ")
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

            Divider()

            GoDeepContextAction(prompt: message.content)

            if let onCheckSources {
                Button {
                    onCheckSources()
                } label: {
                    Label("Check sources", systemImage: "checkmark.shield")
                }
            }
        }
    }
}

// MARK: - Thinking Indicator (rotating messages instead of spinner)

private struct ThinkingIndicator: View {
    @State private var message = ""
    @State private var index = 0

    private static let messages = [
        "Beagle is thinking...",
        "Following the thread...",
        "Reaching for the cluster...",
        "Consulting the exocortex...",
        "Shaping a response...",
        "Processing through the bridge...",
        "Composing from memory...",
    ]

    var body: some View {
        HStack(spacing: BeagleSpacing.xs) {
            Image(systemName: "brain")
                .font(.system(size: 11))
                .foregroundStyle(BeagleTheme.truthObserved)
                .symbolEffect(.pulse, isActive: true)

            Text(message.isEmpty ? Self.messages[0] : message)
                .font(BeagleFont.footnote.font)
                .foregroundStyle(BeagleTheme.textSecondary)
                .contentTransition(.numericText())
                .animation(BeagleMotion.normal, value: message)
        }
        .task {
            while !Task.isCancelled {
                message = Self.messages[index % Self.messages.count]
                index += 1
                try? await Task.sleep(for: .seconds(2))
            }
        }
    }
}

// MARK: - Markdown message renderer

/// Renders LLM markdown block-aware: fenced ``` code blocks become monospace
/// cards (so code stops collapsing into a wall of text), prose uses full
/// markdown (lists, headers, emphasis) instead of inline-only.
private struct MarkdownMessage: View {
    let content: String

    var body: some View {
        VStack(alignment: .leading, spacing: BeagleSpacing.sm) {
            ForEach(Array(segments.enumerated()), id: \.offset) { _, seg in
                switch seg {
                case .prose(let s):
                    Text(prose(s))
                        .font(BeagleFont.body.font)
                        .lineSpacing(4)
                        .foregroundStyle(BeagleTheme.textPrimary)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                case .code(let lang, let code):
                    codeCard(lang: lang, code: code)
                }
            }
        }
    }

    private func prose(_ s: String) -> AttributedString {
        (try? AttributedString(
            markdown: s,
            options: .init(
                interpretedSyntax: .full,
                failurePolicy: .returnPartiallyParsedIfPossible
            )
        )) ?? AttributedString(s)
    }

    private func codeCard(lang: String?, code: String) -> some View {
        VStack(alignment: .leading, spacing: BeagleSpacing.xxs) {
            if let lang, !lang.isEmpty {
                Text(lang)
                    .font(BeagleFont.caption2.font)
                    .foregroundStyle(BeagleTheme.textTertiary)
                    .textCase(.uppercase)
                    .tracking(0.6)
            }
            ScrollView(.horizontal, showsIndicators: false) {
                Text(code)
                    .font(BeagleFont.data.font)
                    .foregroundStyle(BeagleTheme.textPrimary)
                    .textSelection(.enabled)
            }
        }
        .padding(BeagleSpacing.sm)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: BeagleRadius.md).fill(BeagleTheme.surface0))
        .overlay(
            RoundedRectangle(cornerRadius: BeagleRadius.md)
                .strokeBorder(BeagleTheme.hairline, lineWidth: 1)
        )
    }

    private enum Segment {
        case prose(String)
        case code(String?, String)
    }

    /// Split on ``` fences into prose and code segments.
    private var segments: [Segment] {
        var result: [Segment] = []
        var inCode = false
        var lang: String?
        var buf: [String] = []

        func flush(asCode: Bool) {
            let joined = buf.joined(separator: "\n")
            if asCode {
                result.append(.code(lang, joined))
            } else if !joined.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                result.append(.prose(joined))
            }
            buf = []
        }

        for line in content.components(separatedBy: "\n") {
            if line.trimmingCharacters(in: .whitespaces).hasPrefix("```") {
                if inCode {
                    flush(asCode: true)
                    inCode = false
                    lang = nil
                } else {
                    flush(asCode: false)
                    inCode = true
                    let fence = line.trimmingCharacters(in: .whitespaces)
                    let l = String(fence.dropFirst(3)).trimmingCharacters(in: .whitespaces)
                    lang = l.isEmpty ? nil : l
                }
            } else {
                buf.append(line)
            }
        }
        flush(asCode: inCode)
        return result
    }
}
