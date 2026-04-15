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
