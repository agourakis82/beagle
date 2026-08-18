//
//  VoiceModeView.swift
//  BeagleCockpit
//
//  Full-screen Moshi voice mode.
//  Layout: waveform (top ~60%) + Inner Monologue scroll (bottom ~40%).
//
//  Presented via .fullScreenCover (iOS) / .sheet (macOS) from ConversationView.
//

import SwiftUI
import BeagleCore

struct VoiceModeView: View {

    @Bindable var moshi: MoshiSessionManager
    let profileColor: Color
    @Environment(\.dismiss) private var dismiss

    // MARK: - Body

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 0) {
                topBar
                waveformSection
                    .frame(maxWidth: .infinity)
                    .layoutPriority(3)
                monologueSection
                    .frame(maxWidth: .infinity)
                    .layoutPriority(2)
            }
        }
        .preferredColorScheme(.dark)
        .onDisappear { moshi.disconnect() }
    }

    // MARK: - Top bar

    private var topBar: some View {
        HStack {
            statusPill
            Spacer()
            dismissButton
        }
        .padding(.horizontal, BeagleSpacing.lg)
        .padding(.top, BeagleSpacing.md)
        .padding(.bottom, BeagleSpacing.sm)
    }

    private var statusPill: some View {
        HStack(spacing: BeagleSpacing.xxs) {
            Circle()
                .fill(statusColor)
                .frame(width: 7, height: 7)
                .overlay(
                    Group {
                        if moshi.connectionState == .active {
                            Circle()
                                .fill(statusColor.opacity(0.35))
                                .frame(width: 14, height: 14)
                        }
                    }
                )
            Text(statusLabel)
                .font(BeagleFont.caption.font)
                .fontWeight(.medium)
                .foregroundStyle(BeagleTheme.textSecondary)
        }
        .padding(.horizontal, BeagleSpacing.sm)
        .padding(.vertical, BeagleSpacing.xxs)
        .background(
            Capsule().fill(BeagleTheme.surface1.opacity(0.45))
        )
        .overlay(
            Capsule().strokeBorder(BeagleTheme.hairline, lineWidth: 0.5)
        )
    }

    private var dismissButton: some View {
        Button {
            moshi.disconnect()
            dismiss()
        } label: {
            Image(systemName: "xmark")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(BeagleTheme.textSecondary)
                .frame(width: 32, height: 32)
                .background(Circle().fill(BeagleTheme.surface1.opacity(0.5)))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Waveform (top 60%)

    private var waveformSection: some View {
        GeometryReader { geo in
            TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { timeline in
                Canvas { context, size in
                    let bars = 48
                    let totalSpacing = size.width * 0.02
                    let barWidth = (size.width - totalSpacing) / CGFloat(bars * 2)
                    let gap = barWidth
                    let t = timeline.date.timeIntervalSinceReferenceDate
                    let level = CGFloat(moshi.inputLevel)

                    for i in 0..<bars {
                        let phase = Double(i) * 0.38 + t * 3.5
                        let wave = CGFloat((sin(phase) * 0.5 + 0.5))
                        let minH = size.height * 0.06
                        let maxH = size.height * 0.82
                        let dynamicH = minH + (maxH - minH) * (level * wave + 0.05)
                        let x = CGFloat(i) * (barWidth + gap) + barWidth / 2 + totalSpacing / 2

                        let rect = CGRect(
                            x: x - barWidth / 2,
                            y: (size.height - dynamicH) / 2,
                            width: barWidth,
                            height: dynamicH
                        )
                        let path = Path(roundedRect: rect, cornerRadius: barWidth / 2)
                        let alpha = 0.35 + 0.65 * (level * wave + 0.1)
                        context.fill(path, with: .color(profileColor.opacity(Double(alpha))))
                    }
                }
                .frame(width: geo.size.width, height: geo.size.height)
            }
        }
        .frame(maxWidth: .infinity)
        .frame(maxHeight: .infinity)
    }

    // MARK: - Inner Monologue scroll (bottom 40%)

    private var monologueSection: some View {
        VStack(spacing: BeagleSpacing.xs) {
            HStack {
                Text("Inner Monologue")
                    .font(BeagleFont.caption2.font)
                    .fontWeight(.medium)
                    .foregroundStyle(BeagleTheme.textTertiary)
                    .textCase(.uppercase)
                    .tracking(0.8)
                Spacer()
                if !moshi.innerMonologueText.isEmpty {
                    Button {
                        moshi.clearMonologue()
                    } label: {
                        Image(systemName: "eraser")
                            .font(.system(size: 11))
                            .foregroundStyle(BeagleTheme.textTertiary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, BeagleSpacing.lg)

            ScrollViewReader { proxy in
                ScrollView {
                    Text(moshi.innerMonologueText.isEmpty
                         ? "Waiting for inner monologue..."
                         : moshi.innerMonologueText)
                        .font(BeagleFont.body.font)
                        .foregroundStyle(moshi.innerMonologueText.isEmpty
                                        ? BeagleTheme.textTertiary
                                        : BeagleTheme.textPrimary)
                        .lineSpacing(4)
                        .padding(.horizontal, BeagleSpacing.lg)
                        .padding(.bottom, BeagleSpacing.md)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .id("bottom")
                }
                .onChange(of: moshi.innerMonologueText) {
                    withAnimation(.easeOut(duration: 0.2)) {
                        proxy.scrollTo("bottom", anchor: .bottom)
                    }
                }
            }
        }
        .padding(.top, BeagleSpacing.sm)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            RoundedRectangle(cornerRadius: BeagleRadius.lg)
                .fill(BeagleTheme.surface0.opacity(0.6))
                .ignoresSafeArea(edges: .bottom)
        )
    }

    // MARK: - State helpers

    private var statusLabel: String {
        switch moshi.connectionState {
        case .idle:          return "Idle"
        case .connecting:    return "Connecting..."
        case .active:        return "Live"
        case .disconnected:  return "Disconnected"
        case .failed(let e): return "Error: \(e)"
        }
    }

    private var statusColor: Color {
        switch moshi.connectionState {
        case .active:     return .green
        case .connecting: return BeagleTheme.postureWarm
        case .failed:     return .red
        default:          return BeagleTheme.textTertiary
        }
    }
}

// MARK: - DiscussionProfile → Color helper

extension DiscussionProfile {
    var moshiWaveformColor: Color {
        switch self {
        case .cluster:   return BeagleTheme.truthObserved
        case .grok:      return Color(hue: 0.58, saturation: 0.7, brightness: 0.95)
        case .kimi:      return Color(hue: 0.72, saturation: 0.6, brightness: 0.9)
        case .claudeCode: return Color(hue: 0.12, saturation: 0.75, brightness: 1.0)
        case .codex:     return Color(hue: 0.45, saturation: 0.6, brightness: 0.9)
        case .qwen3b:    return Color(hue: 0.03, saturation: 0.7, brightness: 1.0)
        case .yi6b:      return Color(hue: 0.33, saturation: 0.6, brightness: 0.85)
        }
    }
}
