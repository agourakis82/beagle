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
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(BeagleTheme.surface0.opacity(0.8))
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
            // Line number gutter
            Text(String(format: "%4d", line.lineNumber))
                .font(BeagleFont.dataSmall.font)
                .foregroundStyle(BeagleTheme.textTertiary.opacity(0.35))
                .frame(width: 36, alignment: .trailing)
                .padding(.trailing, BeagleSpacing.xs)

            // Gutter separator
            Rectangle()
                .fill(Color.white.opacity(0.06))
                .frame(width: 1)

            // Stderr indicator bar
            if line.isStderr {
                Rectangle()
                    .fill(BeagleTheme.stateError.opacity(0.6))
                    .frame(width: 2)
                    .padding(.leading, BeagleSpacing.xxs)
            }

            // Attributed content
            Text(line.content)
                .textSelection(.enabled)
                .padding(.leading, BeagleSpacing.xs)
        }
        .padding(.vertical, 1.5)
    }

    // MARK: - Empty state

    private var emptyState: some View {
        VStack(spacing: BeagleSpacing.md) {
            Image(systemName: "terminal")
                .font(.system(size: 32))
                .foregroundStyle(BeagleTheme.textTertiary.opacity(0.4))
            Text("Start a session to attach")
                .font(BeagleFont.footnote.font)
                .foregroundStyle(BeagleTheme.textTertiary)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, BeagleSpacing.jumbo)
    }

    // MARK: - Jump to bottom pill

    private var jumpToBottomPill: some View {
        Button {
            withAnimation(BeagleMotion.snappy) {
                isUserScrolledUp = false
            }
        } label: {
            HStack(spacing: BeagleSpacing.xxs) {
                Image(systemName: "arrow.down")
                    .font(.system(size: 11, weight: .semibold))
                Text("New output")
                    .font(BeagleFont.caption.font)
                    .fontWeight(.medium)
            }
            .foregroundStyle(BeagleTheme.truthObserved)
            .padding(.horizontal, BeagleSpacing.sm)
            .padding(.vertical, BeagleSpacing.xs)
            .background(
                Capsule()
                    .fill(BeagleTheme.surface2)
                    .shadow(color: BeagleTheme.truthObserved.opacity(0.2), radius: 8)
            )
            .overlay(
                Capsule()
                    .strokeBorder(BeagleTheme.truthObserved.opacity(0.25), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .padding(.bottom, BeagleSpacing.sm)
        .transition(.move(edge: .bottom).combined(with: .opacity))
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
}
