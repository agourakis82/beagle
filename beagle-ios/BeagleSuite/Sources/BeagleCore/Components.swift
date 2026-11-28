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
                    .fill(.background.secondary)
            )
            .overlay(
                RoundedRectangle(cornerRadius: BeagleRadius.lg)
                    .strokeBorder(borderColor, lineWidth: 0.5)
            )
            .shadow(color: shadowColor, radius: shadowRadius, y: shadowY)
    }

    private var borderColor: Color {
        // Always hairline — colour belongs to badges/icons, never the card frame.
        BeagleTheme.hairline
    }

    private var shadowColor: Color {
        switch elevation {
        case .flush:    return .clear
        case .raised:   return .black.opacity(0.06)
        case .floating: return .black.opacity(0.10)
        }
    }

    private var shadowRadius: CGFloat {
        switch elevation {
        case .flush:    return 0
        case .raised:   return 4
        case .floating: return 10
        }
    }

    private var shadowY: CGFloat {
        switch elevation {
        case .flush:    return 0
        case .raised:   return 1
        case .floating: return 4
        }
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
                Rectangle()
                    .fill(BeagleTheme.hairline)
                    .frame(height: 0.5)
                    .padding(.horizontal, BeagleSpacing.md)

                content
                    .padding(.horizontal, BeagleSpacing.lg)
                    .padding(.vertical, BeagleSpacing.md)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .background(
            RoundedRectangle(cornerRadius: BeagleRadius.lg)
                .fill(.background.secondary)
        )
        .overlay(
            RoundedRectangle(cornerRadius: BeagleRadius.lg)
                .strokeBorder(BeagleTheme.hairline, lineWidth: 0.5)
        )
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
