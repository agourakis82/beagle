//
//  Components+CelebrationsAndHaptics.swift
//  BeagleCore
//
//  Thought pulse, parallax header, soft separator, typewriter text,
//  milestone celebration particles, and Beagle emotional haptics.
//

import SwiftUI

// MARK: - Thought Pulse (radiating rings when a thought is captured)

public struct ThoughtPulse: View {
    let color: Color
    @State private var animate = false

    public init(color: Color = BeagleTheme.truthObserved) {
        self.color = color
    }

    public var body: some View {
        ZStack {
            ForEach(0..<3, id: \.self) { i in
                Circle()
                    .strokeBorder(color.opacity(animate ? 0 : 0.3), lineWidth: 1.5)
                    .scaleEffect(animate ? 2.5 : 1)
                    .animation(
                        .easeOut(duration: 1.5)
                        .repeatCount(1)
                        .delay(Double(i) * 0.3),
                        value: animate
                    )
            }
        }
        .frame(width: 20, height: 20)
        .onAppear { animate = true }
    }
}

// MARK: - Parallax Header

/// A header that moves slower than the scroll for depth.
public struct ParallaxHeader<Content: View>: View {
    let height: CGFloat
    let content: Content

    public init(height: CGFloat = 200, @ViewBuilder content: () -> Content) {
        self.height = height
        self.content = content()
    }

    public var body: some View {
        GeometryReader { geo in
            let minY = geo.frame(in: .scrollView).minY
            let parallax = minY > 0 ? -minY * 0.3 : 0

            content
                .frame(width: geo.size.width, height: height + (minY > 0 ? minY : 0))
                .offset(y: parallax)
                .clipped()
        }
        .frame(height: height)
    }
}

// MARK: - Separator Line

public struct SoftSeparator: View {
    public init() {}

    public var body: some View {
        Rectangle()
            .fill(
                LinearGradient(
                    colors: [.clear, Color.white.opacity(0.06), .clear],
                    startPoint: .leading, endPoint: .trailing
                )
            )
            .frame(height: 1)
            .padding(.vertical, BeagleSpacing.sm)
    }
}

// MARK: - Typewriter Text

/// Animates text appearing character by character — personal, not instant.
@MainActor
public struct TypewriterText: View {
    let text: String
    let font: Font
    let foregroundStyle: AnyShapeStyle
    let speed: Double  // characters per second

    @State private var displayedCount = 0
    @State private var typeTask: Task<Void, Never>?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(
        _ text: String,
        font: Font = BeagleFont.largeTitle.font,
        foregroundStyle: AnyShapeStyle = AnyShapeStyle(BeagleTheme.textPrimary),
        speed: Double = 28
    ) {
        self.text = text
        self.font = font
        self.foregroundStyle = foregroundStyle
        self.speed = speed
    }

    private var displayed: String {
        reduceMotion ? text : String(text.prefix(displayedCount))
    }

    public var body: some View {
        Text(displayed)
            .font(font)
            .foregroundStyle(foregroundStyle)
            .onAppear { start() }
            .onChange(of: text) { start() }
            .onDisappear { typeTask?.cancel() }
    }

    private func start() {
        typeTask?.cancel()
        if reduceMotion { displayedCount = text.count; return }
        displayedCount = 0
        let target = text.count
        let interval = UInt64(1_000_000_000 / speed)
        typeTask = Task { @MainActor in
            for i in 1...max(1, target) {
                guard !Task.isCancelled else { return }
                try? await Task.sleep(nanoseconds: interval)
                displayedCount = i
                if i >= target { return }
            }
        }
    }
}

// MARK: - Milestone Celebration

/// Full-screen overlay that celebrates a thought milestone with bursting stars.
public struct MilestoneCelebration: View {
    let count: Int
    let onDismiss: () -> Void

    @State private var show = false
    @State private var particles: [MilestoneParticle] = []

    public init(count: Int, onDismiss: @escaping () -> Void) {
        self.count = count
        self.onDismiss = onDismiss
    }

    private var headline: String {
        switch count {
        case 1:   return "First thought captured."
        case 10:  return "10 thoughts."
        case 50:  return "50 thoughts in your exocortex."
        case 100: return "100 thoughts. Your mind is alive."
        case 500: return "500 thoughts. This is rare."
        default:  return "\(count) thoughts."
        }
    }

    private var subtitle: String {
        switch count {
        case 1:   return "Every great system begins with one idea."
        case 10:  return "A pattern is forming."
        case 50:  return "You've built a knowledge base worth exploring."
        case 100: return "Most people never get this far. Keep going."
        case 500: return "You're building something extraordinary."
        default:  return "Keep capturing."
        }
    }

    private var accentColor: Color {
        switch count {
        case 1:   return BeagleTheme.truthObserved
        case 10:  return BeagleTheme.truthRemembered
        case 50:  return BeagleTheme.postureWarm
        case 100: return Color(hue: 50/360, saturation: 0.8, brightness: 1.0) // gold
        case 500: return Color(hue: 300/360, saturation: 0.7, brightness: 1.0) // magenta
        default:  return BeagleTheme.truthObserved
        }
    }

    public var body: some View {
        GeometryReader { geo in
            let center = CGPoint(x: geo.size.width / 2, y: geo.size.height / 2)
            ZStack {
                Color.black.opacity(show ? 0.55 : 0)
                    .ignoresSafeArea()
                    .onTapGesture { dismiss() }

                // Particles
                ForEach(particles) { p in
                    Circle()
                        .fill(p.color)
                        .frame(width: p.size, height: p.size)
                        .position(
                            x: center.x + p.offset.width,
                            y: center.y + p.offset.height
                        )
                        .opacity(show ? 0 : 0.8)
                        .animation(
                            .easeOut(duration: p.duration).delay(p.delay),
                            value: show
                        )
                }

                // Card
                VStack(spacing: BeagleSpacing.md) {
                    ZStack {
                        Circle()
                            .fill(accentColor.opacity(0.15))
                            .frame(width: 72, height: 72)
                        Image(systemName: count >= 100 ? "star.fill" : count >= 50 ? "sparkles" : "checkmark.seal.fill")
                            .font(.system(size: 30, weight: .medium))
                            .foregroundStyle(accentColor)
                            .symbolEffect(.bounce, value: show)
                    }

                    VStack(spacing: BeagleSpacing.xs) {
                        Text(headline)
                            .font(BeagleFont.title2.font)
                            .fontWeight(.semibold)
                            .foregroundStyle(BeagleTheme.textPrimary)
                            .multilineTextAlignment(.center)

                        Text(subtitle)
                            .font(BeagleFont.subheadline.font)
                            .foregroundStyle(BeagleTheme.textSecondary)
                            .multilineTextAlignment(.center)
                            .lineSpacing(2)
                    }

                    Button("Continue") { dismiss() }
                        .buttonStyle(PrimaryButton())
                        .controlSize(.regular)
                        .padding(.top, BeagleSpacing.xs)
                }
                .padding(BeagleSpacing.xxl)
                .background(
                    RoundedRectangle(cornerRadius: BeagleRadius.xl)
                        .fill(.ultraThinMaterial)
                        .overlay(
                            RoundedRectangle(cornerRadius: BeagleRadius.xl)
                                .strokeBorder(accentColor.opacity(0.18), lineWidth: 1)
                        )
                )
                .padding(.horizontal, BeagleSpacing.xxl)
                .scaleEffect(show ? 1 : 0.85)
                .opacity(show ? 1 : 0)
                .animation(.spring(duration: 0.5, bounce: 0.3), value: show)
            }
        }
        .ignoresSafeArea()
        .onAppear {
            spawnParticles()
            withAnimation { show = true }
            #if os(iOS)
            BeagleHaptics.milestone()
            #endif
        }
    }

    private func dismiss() {
        withAnimation(.easeIn(duration: 0.2)) { show = false }
        let finish = onDismiss
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(250))
            finish()
        }
    }

    private func spawnParticles() {
        let colors: [Color] = [accentColor, accentColor.opacity(0.7), BeagleTheme.truthObserved, .white.opacity(0.8)]
        particles = (0..<24).map { i in
            let angle = Double(i) / 24.0 * 2 * .pi
            let radius = Double.random(in: 80...200)
            return MilestoneParticle(
                id: i,
                offset: CGSize(width: cos(angle) * radius, height: sin(angle) * radius),
                color: colors[i % colors.count],
                size: CGFloat.random(in: 4...10),
                duration: Double.random(in: 0.6...1.1),
                delay: Double(i) * 0.025
            )
        }
    }
}

private struct MilestoneParticle: Identifiable {
    let id: Int
    var offset: CGSize
    var color: Color
    var size: CGFloat
    var duration: Double
    var delay: Double
}

// MARK: - Haptics (Beagle emotional signatures)

#if os(iOS)
import UIKit

/// Signature haptic patterns that give Beagle an emotional identity.
@MainActor
public enum BeagleHaptics {

    /// Single thought captured — a small, satisfying click.
    public static func capture() {
        let generator = UIImpactFeedbackGenerator(style: .light)
        generator.impactOccurred()
    }

    /// Go Deeper complete — double tap, feels like arrival.
    public static func goDeepComplete() {
        let gen = UINotificationFeedbackGenerator()
        gen.notificationOccurred(.success)
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(120))
            UIImpactFeedbackGenerator(style: .medium).impactOccurred(intensity: 0.5)
        }
    }

    /// Milestone hit — three quick taps ascending in intensity.
    public static func milestone() {
        let timings: [(delayMs: Int, style: UIImpactFeedbackGenerator.FeedbackStyle, intensity: CGFloat)] = [
            (0,   .light,  0.4),
            (100, .medium, 0.7),
            (220, .heavy,  1.0),
        ]
        for t in timings {
            Task { @MainActor in
                if t.delayMs > 0 {
                    try? await Task.sleep(for: .milliseconds(t.delayMs))
                }
                let gen = UIImpactFeedbackGenerator(style: t.style)
                gen.impactOccurred(intensity: t.intensity)
            }
        }
    }

    /// Morning brief arrived — one soft tap, like a quiet hello.
    public static func morningBrief() {
        UIImpactFeedbackGenerator(style: .soft).impactOccurred(intensity: 0.6)
    }

    /// Error / warning — rigid double-thump.
    public static func warning() {
        let gen = UINotificationFeedbackGenerator()
        gen.notificationOccurred(.warning)
    }
}
#endif
