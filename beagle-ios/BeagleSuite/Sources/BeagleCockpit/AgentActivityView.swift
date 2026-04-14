//
//  AgentActivityView.swift
//  BeagleCockpit
//
//  Live feed of inter-agent communication — what each agent surface
//  (remote Claude Code, ChatGPT, cockpit web, iOS) is doing.
//
//  This is the nervous system of the exocortex ensemble.
//  Enables session continuity: see what the remote agent deployed,
//  what ChatGPT discovered, what the iOS capture surface recorded.
//

import SwiftUI
import BeagleCore

struct AgentActivityView: View {
    @State private var store = AgentActivityStore()
    @State private var composeText = ""
    @State private var composeKind = "completed"

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: BeagleSpacing.sm) {
                    if store.isLoading && !store.hasMessages {
                        ForEach(0..<4, id: \.self) { _ in
                            LaneSkeleton()
                                .padding(.horizontal, BeagleSpacing.lg)
                        }
                    } else if !store.hasMessages {
                        emptyState
                    } else {
                        ForEach(store.recentMessages) { message in
                            AgentMessageCard(message: message)
                        }
                    }
                }
                .padding(.top, BeagleSpacing.md)
                .padding(.bottom, BeagleSpacing.jumbo)
            }

            composeBar
        }
        .background { AgentActivityGradient(hasActivity: store.hasMessages) }
        .navigationTitle("Agent Activity")
        .task { await store.refresh() }
        .refreshable { await store.refresh() }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: BeagleSpacing.md) {
            Image(systemName: "antenna.radiowaves.left.and.right")
                .font(.system(size: 32))
                .foregroundStyle(BeagleTheme.textTertiary)

            Text("No agent activity yet")
                .font(BeagleFont.subheadline.font)
                .foregroundStyle(BeagleTheme.textSecondary)

            Text("When agents post to the scratchpad, their messages appear here. All surfaces — Claude Code, ChatGPT, cockpit web — share this channel.")
                .font(BeagleFont.caption.font)
                .foregroundStyle(BeagleTheme.textTertiary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, BeagleSpacing.xxl)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, BeagleSpacing.xxxl)
    }

    // MARK: - Compose Bar

    private var composeBar: some View {
        HStack(spacing: BeagleSpacing.xs) {
            // Kind picker
            Menu {
                Button { composeKind = "completed" } label: { Label("Completed", systemImage: "checkmark.circle") }
                Button { composeKind = "deployed" } label: { Label("Deployed", systemImage: "arrow.up.circle") }
                Button { composeKind = "discovered" } label: { Label("Discovered", systemImage: "sparkle") }
                Button { composeKind = "needs" } label: { Label("Needs", systemImage: "exclamationmark.bubble") }
                Button { composeKind = "question" } label: { Label("Question", systemImage: "questionmark.circle") }
            } label: {
                Image(systemName: kindIcon(composeKind))
                    .font(.system(size: 14))
                    .foregroundStyle(kindColor(composeKind))
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }

            TextField("Post to scratchpad...", text: $composeText)
                .font(BeagleFont.body.font)
                .foregroundStyle(BeagleTheme.textPrimary)

            Button {
                let text = composeText.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !text.isEmpty else { return }
                composeText = ""
                Task { _ = await store.post(kind: composeKind, content: text) }
            } label: {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.system(size: 28))
                    .foregroundStyle(composeText.isEmpty ? BeagleTheme.textTertiary : BeagleTheme.truthObserved)
            }
            .buttonStyle(.plain)
            .disabled(composeText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            .sensoryFeedback(.impact(weight: .medium), trigger: composeText.isEmpty)
        }
        .padding(.horizontal, BeagleSpacing.md)
        .padding(.vertical, BeagleSpacing.sm)
        .background(.ultraThinMaterial)
    }

    // MARK: - Helpers

    private func kindIcon(_ kind: String) -> String {
        switch kind {
        case "deployed":   return "arrow.up.circle"
        case "completed":  return "checkmark.circle"
        case "discovered": return "sparkle"
        case "needs":      return "exclamationmark.bubble"
        case "question":   return "questionmark.circle"
        default:           return "circle"
        }
    }

    private func kindColor(_ kind: String) -> Color {
        switch kind {
        case "deployed":   return BeagleTheme.truthObserved
        case "completed":  return BeagleTheme.truthObserved
        case "discovered": return BeagleTheme.postureWarm
        case "needs":      return BeagleTheme.truthRemembered
        case "question":   return BeagleTheme.truthRemembered
        default:           return BeagleTheme.textSecondary
        }
    }
}

// MARK: - Agent Message Card

private struct AgentMessageCard: View {
    let message: AgentMessage

    var body: some View {
        HStack(alignment: .top, spacing: BeagleSpacing.sm) {
            // Agent avatar
            Image(systemName: agentIcon)
                .font(.system(size: 14))
                .foregroundStyle(agentColor)
                .frame(width: 28, height: 28)
                .background(
                    Circle()
                        .fill(agentColor.opacity(0.1))
                )

            VStack(alignment: .leading, spacing: BeagleSpacing.xxs) {
                // Agent name + kind badge
                HStack(spacing: BeagleSpacing.xs) {
                    Text(message.agent ?? "unknown")
                        .font(BeagleFont.footnote.font)
                        .fontWeight(.medium)
                        .foregroundStyle(BeagleTheme.textPrimary)

                    Text(message.kind ?? "message")
                        .font(BeagleFont.caption2.font)
                        .fontWeight(.medium)
                        .foregroundStyle(kindColor)
                        .padding(.horizontal, BeagleSpacing.xxs + 2)
                        .padding(.vertical, 2)
                        .background(
                            Capsule().fill(kindColor.opacity(0.1))
                        )

                    Spacer()

                    if let ts = message.createdAt {
                        Text(relativeTime(ts))
                            .font(BeagleFont.caption2.font)
                            .foregroundStyle(BeagleTheme.textTertiary)
                    }
                }

                // Content
                if let content = message.content {
                    Text(content)
                        .font(BeagleFont.subheadline.font)
                        .foregroundStyle(BeagleTheme.textSecondary)
                        .lineSpacing(2)
                        .textSelection(.enabled)
                }
            }
        }
        .padding(.horizontal, BeagleSpacing.lg)
        .padding(.vertical, BeagleSpacing.xs)
    }

    private var agentIcon: String {
        switch message.agent {
        case "claude-code-remote": return "sparkles"
        case "claude-code-ios":    return "iphone"
        case "chatgpt":            return "bubble.left.and.bubble.right"
        case "cockpit-web":        return "globe"
        case "codex":              return "curlybraces"
        default:                   return "person.circle"
        }
    }

    private var agentColor: Color {
        switch message.agent {
        case "claude-code-remote": return BeagleTheme.truthObserved
        case "claude-code-ios":    return BeagleTheme.truthRemembered
        case "chatgpt":            return BeagleTheme.postureWarm
        case "cockpit-web":        return BeagleTheme.textData
        case "codex":              return BeagleTheme.truthDeclared
        default:                   return BeagleTheme.textSecondary
        }
    }

    private var kindColor: Color {
        switch message.kind {
        case "deployed":   return BeagleTheme.truthObserved
        case "completed":  return BeagleTheme.truthObserved
        case "discovered": return BeagleTheme.postureWarm
        case "needs":      return BeagleTheme.truthRemembered
        case "question":   return BeagleTheme.truthRemembered
        default:           return BeagleTheme.textSecondary
        }
    }

    private func relativeTime(_ iso: String) -> String {
        let formatter = ISO8601DateFormatter()
        guard let date = formatter.date(from: iso) else { return iso }
        let seconds = Date.now.timeIntervalSince(date)
        if seconds < 60 { return "\(Int(seconds))s ago" }
        if seconds < 3600 { return "\(Int(seconds / 60))m ago" }
        if seconds < 86400 { return "\(Int(seconds / 3600))h ago" }
        return "\(Int(seconds / 86400))d ago"
    }
}

// MARK: - Agent Activity Gradient

private struct AgentActivityGradient: View {
    let hasActivity: Bool
    @State private var phase: CGFloat = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        MeshGradient(
            width: 3, height: 3,
            points: animatedPoints,
            colors: gradientColors
        )
        .ignoresSafeArea()
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 8).repeatForever(autoreverses: true)) {
                phase = 1
            }
        }
    }

    private var animatedPoints: [SIMD2<Float>] {
        let d: Float = reduceMotion ? 0 : Float(phase) * 0.06
        return [
            SIMD2(0,     0),     SIMD2(0.5,   0),       SIMD2(1,     0),
            SIMD2(0+d,   0.5-d), SIMD2(0.5+d, 0.5+d),   SIMD2(1-d,   0.5+d),
            SIMD2(0,     1),     SIMD2(0.5,   1),       SIMD2(1,     1)
        ]
    }

    private var gradientColors: [Color] {
        let base = Color(red: 0.02, green: 0.03, blue: 0.07)
        // Multiple colors = multiple agent surfaces active
        return [
            BeagleTheme.truthObserved.opacity(hasActivity ? 0.10 : 0.0),  // remote agent
            BeagleTheme.truthRemembered.opacity(hasActivity ? 0.06 : 0.0), // iOS
            Color(white: 0.03),

            BeagleTheme.postureWarm.opacity(hasActivity ? 0.05 : 0.0),    // ChatGPT
            base,
            Color(white: 0.03),

            base, base, Color(white: 0.02)
        ]
    }
}
