//
//  TerminalContentView.swift
//  BeagleCockpit
//
//  Rich terminal renderer using AttributedString.
//  Smart scroll: auto-scrolls only when at bottom, preserves position when reading history.
//  Floating "Jump to bottom" pill when scrolled up with new content.
//

import SwiftUI
import BeagleCore

struct TerminalContentView: View {
    @Bindable var terminal: TerminalStore

    // Smart scroll state
    @State private var isUserScrolledUp = false
    @State private var hasNewContent = false
    @State private var lastLineCount = 0

    var body: some View {
        ZStack(alignment: .bottom) {
            scrollContent
            if isUserScrolledUp && hasNewContent {
                jumpToBottomPill
            }
            reconnectingOverlay
            exitOverlay
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color(red: 0.04, green: 0.04, blue: 0.07))
    }

    // MARK: - Scroll content

    private var scrollContent: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 3) {
                    if terminal.isEmpty && terminal.connectionState == .disconnected {
                        emptyState
                    } else {
                        ForEach(terminal.attributedLines) { line in
                            terminalRow(line)
                                .id(line.id)
                        }
                    }

                    // Invisible anchor at the very bottom for scroll tracking
                    Color.clear
                        .frame(height: 1)
                        .id("bottom-anchor")
                        .onAppear { isUserScrolledUp = false; hasNewContent = false }
                        .onDisappear { isUserScrolledUp = true }
                }
                .padding(.horizontal, BeagleSpacing.xs)
            }
            .onChange(of: terminal.attributedLines.count) { oldCount, newCount in
                if newCount > oldCount {
                    if !isUserScrolledUp {
                        withAnimation(BeagleMotion.fast) {
                            proxy.scrollTo("bottom-anchor", anchor: .bottom)
                        }
                    } else {
                        hasNewContent = true
                    }
                }
                lastLineCount = newCount
            }
            .onChange(of: isUserScrolledUp) {
                if !isUserScrolledUp {
                    hasNewContent = false
                    withAnimation(BeagleMotion.fast) {
                        proxy.scrollTo("bottom-anchor", anchor: .bottom)
                    }
                }
            }
        }
    }

    // MARK: - Terminal row

    private func terminalRow(_ line: AttributedTerminalLine) -> some View {
        HStack(alignment: .top, spacing: 0) {
            // Stderr accent bar — subtle left edge
            if line.isStderr {
                Rectangle()
                    .fill(BeagleTheme.stateError.opacity(0.5))
                    .frame(width: 2)
                    .padding(.trailing, BeagleSpacing.xxs)
            }

            // Attributed content
            Text(line.content)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, BeagleSpacing.sm)
        .padding(.vertical, 2)
    }

    // MARK: - Empty state

    private var emptyState: some View {
        VStack(spacing: BeagleSpacing.lg) {
            Image(systemName: "apple.terminal")
                .font(.system(size: 36))
                .foregroundStyle(BeagleTheme.textTertiary.opacity(0.3))

            VStack(spacing: BeagleSpacing.xs) {
                Text("No active session")
                    .font(BeagleFont.subheadline.font)
                    .fontWeight(.medium)
                    .foregroundStyle(BeagleTheme.textSecondary)
                Text("Press Connect to deploy or resume an agent pod.\nSession survives app close — your work is never lost.")
                    .font(BeagleFont.footnote.font)
                    .foregroundStyle(BeagleTheme.textTertiary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(3)
            }

            VStack(alignment: .leading, spacing: BeagleSpacing.xs) {
                shortcutHint("Ctrl+C", "interrupt current process")
                shortcutHint("Tab", "complete command")
                shortcutHint("↑ ↓", "navigate command history")
            }
            .padding(BeagleSpacing.md)
            .background(
                RoundedRectangle(cornerRadius: BeagleRadius.md)
                    .fill(Color.white.opacity(0.03))
                    .overlay(
                        RoundedRectangle(cornerRadius: BeagleRadius.md)
                            .strokeBorder(Color.white.opacity(0.06), lineWidth: 1)
                    )
            )
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, BeagleSpacing.xxxl)
        .padding(.top, BeagleSpacing.jumbo)
    }

    private func shortcutHint(_ key: String, _ description: String) -> some View {
        HStack(spacing: BeagleSpacing.sm) {
            Text(key)
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundStyle(BeagleTheme.truthObserved.opacity(0.8))
                .padding(.horizontal, BeagleSpacing.xs)
                .padding(.vertical, 2)
                .background(
                    RoundedRectangle(cornerRadius: 4)
                        .fill(BeagleTheme.truthObserved.opacity(0.08))
                )
            Text(description)
                .font(BeagleFont.caption.font)
                .foregroundStyle(BeagleTheme.textTertiary)
        }
    }

    // MARK: - Jump to bottom pill

    private var jumpToBottomPill: some View {
        let newLines = max(0, terminal.attributedLines.count - lastLineCount)
        return Button {
            withAnimation(BeagleMotion.snappy) {
                isUserScrolledUp = false
            }
        } label: {
            HStack(spacing: BeagleSpacing.xxs) {
                Image(systemName: "arrow.down")
                    .font(.system(size: 11, weight: .bold))
                if newLines > 0 {
                    Text("+\(newLines) lines")
                        .font(BeagleFont.caption.font)
                        .fontWeight(.medium)
                } else {
                    Text("Jump to bottom")
                        .font(BeagleFont.caption.font)
                        .fontWeight(.medium)
                }
            }
            .foregroundStyle(.black)
            .padding(.horizontal, BeagleSpacing.md)
            .padding(.vertical, BeagleSpacing.xs + 1)
            .background(
                Capsule()
                    .fill(BeagleTheme.truthObserved)
                    .shadow(color: BeagleTheme.truthObserved.opacity(0.35), radius: 12, y: 4)
            )
        }
        .buttonStyle(.plain)
        .padding(.bottom, BeagleSpacing.sm)
        .transition(.scale(scale: 0.85).combined(with: .opacity))
    }

    // MARK: - Reconnecting overlay

    @ViewBuilder
    private var reconnectingOverlay: some View {
        if case .reconnecting(let attempt) = terminal.connectionState {
            VStack {
                HStack(spacing: BeagleSpacing.xs) {
                    Image(systemName: "arrow.clockwise")
                        .symbolEffect(.variableColor)
                    Text("Reconnecting (attempt \(attempt))...")
                        .font(BeagleFont.caption.font)
                        .fontWeight(.medium)
                }
                .foregroundStyle(BeagleTheme.postureWarm)
                .padding(.horizontal, BeagleSpacing.md)
                .padding(.vertical, BeagleSpacing.xs)
                .background(
                    Capsule()
                        .fill(BeagleTheme.surface2)
                )
                .overlay(
                    Capsule()
                        .strokeBorder(BeagleTheme.postureWarm.opacity(0.3), lineWidth: 1)
                )
                .padding(.top, BeagleSpacing.sm)

                Spacer()
            }
        }
    }

    @ViewBuilder
    private var exitOverlay: some View {
        if terminal.connectionState == .disconnected, terminal.hasAbnormalExit {
            VStack {
                HStack(alignment: .top, spacing: BeagleSpacing.sm) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(BeagleTheme.stateError)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Terminal session ended unexpectedly")
                            .font(BeagleFont.caption.font)
                            .fontWeight(.semibold)
                            .foregroundStyle(BeagleTheme.textPrimary)
                        if let detail = terminal.lastExitDetail {
                            Text(detail)
                                .font(BeagleFont.caption2.font)
                                .foregroundStyle(BeagleTheme.textSecondary)
                                .textSelection(.enabled)
                        }
                    }
                    Spacer()
                }
                .padding(.horizontal, BeagleSpacing.md)
                .padding(.vertical, BeagleSpacing.sm)
                .background(
                    RoundedRectangle(cornerRadius: BeagleRadius.md)
                        .fill(BeagleTheme.surface2)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: BeagleRadius.md)
                        .strokeBorder(BeagleTheme.stateError.opacity(0.35), lineWidth: 1)
                )
                .padding(.horizontal, BeagleSpacing.sm)
                .padding(.top, BeagleSpacing.sm)
                Spacer()
            }
        }
    }
}
