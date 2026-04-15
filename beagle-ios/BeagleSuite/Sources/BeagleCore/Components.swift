//
//  Components.swift
//  BeagleCore
//
//  Command bridge component library — sovereign supercomputing aesthetic.
//  Liquid Glass, semantic depth, animated SF Symbols, shimmer loading.
//

import SwiftUI

// MARK: - TruthBadge

public struct TruthBadge: View {
    let mode: TruthMode
    let compact: Bool

    public init(_ mode: TruthMode, compact: Bool = false) {
        self.mode = mode
        self.compact = compact
    }

    public var body: some View {
        HStack(spacing: BeagleSpacing.xxs) {
            Image(systemName: symbolName)
                .font(.system(size: compact ? 8 : 10))
                .symbolEffect(.pulse, isActive: mode == .observed)
            if !compact {
                Text(mode.rawValue)
                    .font(BeagleFont.caption.font)
                    .fontWeight(.medium)
            }
        }
        .foregroundStyle(BeagleTheme.color(for: mode))
        .padding(.horizontal, compact ? BeagleSpacing.xxs : BeagleSpacing.xs)
        .padding(.vertical, 3)
        .background(
            Capsule()
                .fill(BeagleTheme.color(for: mode).opacity(0.10))
        )
        .accessibilityLabel("Truth: \(mode.rawValue)")
    }

    private var symbolName: String {
        switch mode {
        case .observed:   return "circle.fill"
        case .remembered: return "circle.lefthalf.filled"
        case .declared:   return "circle"
        case .stale:      return "circle.dashed"
        }
    }
}

// MARK: - PostureIndicator

public struct PostureIndicator: View {
    let posture: ProjectPosture
    let size: CGFloat
    let showLabel: Bool

    public init(_ posture: ProjectPosture, size: CGFloat = 13, showLabel: Bool = true) {
        self.posture = posture
        self.size = size
        self.showLabel = showLabel
    }

    public var body: some View {
        HStack(spacing: BeagleSpacing.xxs + 2) {
            Image(systemName: symbolName)
                .font(.system(size: size))
                .foregroundStyle(BeagleTheme.color(for: posture))
                .symbolEffect(.pulse, isActive: posture == .alwaysOn)
                .shadow(
                    color: posture == .alwaysOn ? BeagleTheme.postureOn.opacity(0.4) : .clear,
                    radius: 6
                )

            if showLabel {
                Text(posture.displayLabel)
                    .font(BeagleFont.footnote.font)
                    .foregroundStyle(BeagleTheme.color(for: posture))
            }
        }
        .accessibilityLabel("Posture: \(posture.displayLabel)")
    }

    private var symbolName: String {
        switch posture {
        case .alwaysOn: return "circle.fill"
        case .warm:     return "circle.lefthalf.filled"
        case .cold:     return "circle"
        case .unknown:  return "circle.dashed"
        }
    }
}

// MARK: - GlassPanel (3-level elevation + Liquid Glass)

public struct GlassPanel<Content: View>: View {
    let elevation: PanelElevation
    let truth: TruthMode?
    let content: Content

    public init(
        elevation: PanelElevation = .raised,
        elevated: Bool = false,
        truth: TruthMode? = nil,
        @ViewBuilder content: () -> Content
    ) {
        self.elevation = elevated ? .floating : elevation
        self.truth = truth
        self.content = content()
    }

    public var body: some View {
        content
            .padding(.horizontal, BeagleSpacing.lg)
            .padding(.vertical, BeagleSpacing.md)
            .background(
                RoundedRectangle(cornerRadius: BeagleRadius.lg)
                    .fill(.regularMaterial)
                    .opacity(materialOpacity)
            )
            #if os(iOS)
            .glassEffect(
                .regular.tint(glassTint),
                in: .rect(cornerRadius: BeagleRadius.lg)
            )
            #endif
            .overlay(
                RoundedRectangle(cornerRadius: BeagleRadius.lg)
                    .strokeBorder(borderColor, style: borderStyle)
            )
            .shadow(color: primaryShadow.0, radius: primaryShadow.1, y: primaryShadow.2)
            .shadow(color: ambientGlow.0, radius: ambientGlow.1, y: 0)
    }

    private var materialOpacity: Double {
        switch elevation {
        case .flush:    return 0.65
        case .raised:   return 0.78
        case .floating: return 0.90
        }
    }

    private var glassTint: Color {
        guard let truth else { return .clear }
        return BeagleTheme.color(for: truth).opacity(0.05)
    }

    private var borderColor: Color {
        if let truth {
            return BeagleTheme.color(for: truth)
        }
        return Color.white.opacity(elevation == .flush ? 0.04 : 0.08)
    }

    private var borderStyle: StrokeStyle {
        guard let truth else {
            return StrokeStyle(lineWidth: 1)
        }
        let dash: [CGFloat] = switch truth {
        case .observed:   []
        case .remembered: [4, 3]
        case .declared:   [1, 3]
        case .stale:      [1, 5]
        }
        return StrokeStyle(lineWidth: 1, dash: dash)
    }

    private var primaryShadow: (Color, CGFloat, CGFloat) {
        switch elevation {
        case .flush:    return (.clear, 0, 0)
        case .raised:   return (.black.opacity(0.2), 8, 4)
        case .floating: return (.black.opacity(0.35), 16, 8)
        }
    }

    private var ambientGlow: (Color, CGFloat) {
        guard elevation == .floating, let truth else { return (.clear, 0) }
        return (BeagleTheme.color(for: truth).opacity(0.1), 20)
    }
}

// MARK: - Lane (collapsible section with shimmer)

public struct Lane<Content: View>: View {
    let title: String
    let truth: TruthMode?
    @State private var expanded: Bool
    let content: Content

    public init(
        title: String,
        truth: TruthMode? = nil,
        defaultExpanded: Bool = true,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.truth = truth
        self._expanded = State(initialValue: defaultExpanded)
        self.content = content()
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            Button {
                withAnimation(BeagleMotion.snappy) { expanded.toggle() }
            } label: {
                HStack {
                    Text(title)
                        .font(BeagleFont.headline.font)
                        .foregroundStyle(BeagleTheme.textSecondary)

                    if let truth {
                        TruthBadge(truth, compact: true)
                    }

                    Spacer()

                    Image(systemName: "chevron.down")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(BeagleTheme.textTertiary)
                        .rotationEffect(.degrees(expanded ? 0 : -90))
                        .animation(BeagleMotion.snappy, value: expanded)
                }
                .padding(.horizontal, BeagleSpacing.md)
                .padding(.vertical, BeagleSpacing.sm)
            }
            .buttonStyle(.plain)
            .sensoryFeedback(.selection, trigger: expanded)

            if expanded {
                // Divider
                Rectangle()
                    .fill(Color.white.opacity(0.06))
                    .frame(height: 1)
                    .padding(.horizontal, BeagleSpacing.md)

                content
                    .padding(.horizontal, BeagleSpacing.lg)
                    .padding(.vertical, BeagleSpacing.md)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .background(
            RoundedRectangle(cornerRadius: BeagleRadius.lg)
                .fill(.regularMaterial)
                .opacity(0.55)
        )
        #if os(iOS)
        .glassEffect(.regular, in: .rect(cornerRadius: BeagleRadius.lg))
        #endif
        .truthBorder(truth ?? .declared)
    }
}

// MARK: - Shimmer Skeleton

public struct LaneSkeleton: View {
    @State private var phase: CGFloat = -0.3

    public init() {}

    public var body: some View {
        VStack(alignment: .leading, spacing: BeagleSpacing.xs) {
            shimmerBar(width: .infinity, height: 14)
            shimmerBar(width: 200, height: 14)
            shimmerBar(width: 140, height: 12)
        }
        .padding(.vertical, BeagleSpacing.xxs)
        .onAppear {
            withAnimation(.easeInOut(duration: 1.5).repeatForever(autoreverses: false)) {
                phase = 1.3
            }
        }
    }

    private func shimmerBar(width: CGFloat, height: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: BeagleRadius.sm)
            .fill(Color.white.opacity(0.05))
            .frame(maxWidth: width == .infinity ? .infinity : width, minHeight: height, maxHeight: height)
            .overlay(
                GeometryReader { geo in
                    LinearGradient(
                        colors: [.clear, Color.white.opacity(0.08), .clear],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                    .frame(width: geo.size.width * 0.4)
                    .offset(x: geo.size.width * phase)
                }
                .clipped()
            )
    }
}

// MARK: - Data Flash Modifier

public struct DataFlashModifier: ViewModifier {
    let truthMode: TruthMode
    @State private var flash = false

    public func body(content: Content) -> some View {
        content
            .overlay(
                RoundedRectangle(cornerRadius: BeagleRadius.lg)
                    .fill(BeagleTheme.color(for: truthMode).opacity(flash ? 0.08 : 0))
                    .allowsHitTesting(false)
            )
            .onChange(of: truthMode) { old, new in
                if new == .observed && old != .observed {
                    flash = true
                    withAnimation(BeagleMotion.slow) { flash = false }
                }
            }
    }
}

public extension View {
    func dataFlash(truth: TruthMode) -> some View {
        modifier(DataFlashModifier(truthMode: truth))
    }
}

// MARK: - Button Styles

public struct PrimaryButton: ButtonStyle {
    let color: Color

    public init(color: Color = BeagleTheme.truthObserved) {
        self.color = color
    }

    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(BeagleFont.footnote.font.weight(.medium))
            .foregroundStyle(.white)
            .padding(.horizontal, BeagleSpacing.lg)
            .padding(.vertical, BeagleSpacing.sm)
            .background(
                Capsule()
                    .fill(color)
                    .shadow(color: color.opacity(0.3), radius: 8, y: 4)
            )
            .scaleEffect(configuration.isPressed ? 0.96 : 1.0)
            .animation(BeagleMotion.fast, value: configuration.isPressed)
    }
}

public struct SecondaryButton: ButtonStyle {
    let color: Color

    public init(color: Color = BeagleTheme.truthObserved) {
        self.color = color
    }

    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(BeagleFont.footnote.font.weight(.medium))
            .foregroundStyle(color)
            .padding(.horizontal, BeagleSpacing.lg)
            .padding(.vertical, BeagleSpacing.sm)
            .background(
                Capsule()
                    .fill(color.opacity(0.08))
                    .overlay(Capsule().strokeBorder(color.opacity(0.2), lineWidth: 1))
            )
            .scaleEffect(configuration.isPressed ? 0.96 : 1.0)
            .animation(BeagleMotion.fast, value: configuration.isPressed)
    }
}

// MARK: - Lane Error State

public struct LaneErrorState: View {
    let error: String?
    let onRetry: () -> Void

    public init(error: String?, onRetry: @escaping () -> Void) {
        self.error = error
        self.onRetry = onRetry
    }

    public var body: some View {
        HStack(spacing: BeagleSpacing.sm) {
            VStack(alignment: .leading, spacing: BeagleSpacing.xxs) {
                TruthBadge(.stale, compact: true)
                if let error {
                    Text(error)
                        .font(BeagleFont.footnote.font)
                        .foregroundStyle(BeagleTheme.stateError)
                        .lineLimit(2)
                }
            }
            Spacer()
            Button("Retry", systemImage: "arrow.clockwise") {
                onRetry()
            }
            .buttonStyle(SecondaryButton(color: BeagleTheme.truthObserved))
            .controlSize(.small)
        }
    }
}

// MARK: - Pulsing Glow (for always-on)

struct PulsingGlow: ViewModifier {
    let enabled: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var on = false

    func body(content: Content) -> some View {
        content
            .shadow(
                color: enabled && !reduceMotion
                    ? BeagleTheme.truthObserved.opacity(on ? 0.6 : 0.15)
                    : .clear,
                radius: on ? 10 : 3
            )
            .onAppear {
                guard enabled, !reduceMotion else { return }
                withAnimation(.easeInOut(duration: 2).repeatForever(autoreverses: true)) {
                    on = true
                }
            }
    }
}

extension View {
    func pulsingGlow(enabled: Bool) -> some View {
        modifier(PulsingGlow(enabled: enabled))
    }
}

// MARK: - Staggered Appear (for lists and grids)

/// Applies a staggered fade+slide entrance animation to a view.
public struct StaggeredAppear: ViewModifier {
    let index: Int
    let baseDelay: Double
    @State private var appeared = false

    public init(index: Int, baseDelay: Double = 0.06) {
        self.index = index
        self.baseDelay = baseDelay
    }

    public func body(content: Content) -> some View {
        content
            .opacity(appeared ? 1 : 0)
            .offset(y: appeared ? 0 : 12)
            .scaleEffect(appeared ? 1 : 0.97)
            .animation(
                .spring(duration: 0.5, bounce: 0.15).delay(Double(index) * baseDelay),
                value: appeared
            )
            .onAppear { appeared = true }
    }
}

public extension View {
    func staggeredAppear(index: Int, delay: Double = 0.06) -> some View {
        modifier(StaggeredAppear(index: index, baseDelay: delay))
    }
}

// MARK: - Scale Press (subtle press feedback)

public struct ScalePress: ButtonStyle {
    public init() {}

    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
            .opacity(configuration.isPressed ? 0.85 : 1.0)
            .animation(BeagleMotion.fast, value: configuration.isPressed)
    }
}

// MARK: - Breathing Indicator

/// A gently pulsing dot that communicates "alive".
public struct BreathingDot: View {
    let color: Color
    let size: CGFloat
    @State private var phase = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(color: Color = BeagleTheme.truthObserved, size: CGFloat = 8) {
        self.color = color
        self.size = size
    }

    public var body: some View {
        Circle()
            .fill(color)
            .frame(width: size, height: size)
            .shadow(color: color.opacity(phase ? 0.5 : 0.15), radius: phase ? size : size/3)
            .scaleEffect(phase ? 1.15 : 1.0)
            .onAppear {
                guard !reduceMotion else { return }
                withAnimation(.easeInOut(duration: 2).repeatForever(autoreverses: true)) {
                    phase = true
                }
            }
    }
}

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
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { onDismiss() }
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
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
            UIImpactFeedbackGenerator(style: .medium).impactOccurred(intensity: 0.5)
        }
    }

    /// Milestone hit — three quick taps ascending in intensity.
    public static func milestone() {
        let timings: [(delay: Double, style: UIImpactFeedbackGenerator.FeedbackStyle, intensity: CGFloat)] = [
            (0,    .light,  0.4),
            (0.10, .medium, 0.7),
            (0.22, .heavy,  1.0),
        ]
        for t in timings {
            DispatchQueue.main.asyncAfter(deadline: .now() + t.delay) {
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
