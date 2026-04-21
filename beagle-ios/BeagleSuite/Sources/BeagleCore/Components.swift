//
//  Components.swift
//  BeagleCore
//
//  Shared SwiftUI primitives used across iOS, macOS, visionOS, watchOS.
//  Native equivalents of the web cockpit's component library.
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
        HStack(spacing: 4) {
            Text(mode.displaySymbol)
                .font(BeagleTheme.dataFont(size: compact ? 9 : 11))
            if !compact {
                Text(mode.rawValue.uppercased())
                    .font(BeagleTheme.dataFont(size: 10, weight: .medium))
                    .tracking(0.5)
            }
        }
        .foregroundStyle(BeagleTheme.color(for: mode))
        .padding(.horizontal, compact ? 4 : 8)
        .padding(.vertical, 2)
        .background(
            Capsule()
                .fill(BeagleTheme.color(for: mode).opacity(0.10))
        )
        .accessibilityLabel("Truth mode: \(mode.rawValue)")
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
        HStack(spacing: 6) {
            Text(posture.displaySymbol)
                .font(BeagleTheme.dataFont(size: size * 1.1, weight: .medium))
                .foregroundStyle(BeagleTheme.color(for: posture))
                .pulsingGlow(enabled: posture == .alwaysOn)

            if showLabel {
                Text(posture.displayLabel)
                    .font(BeagleTheme.dataFont(size: size, weight: .regular))
                    .foregroundStyle(BeagleTheme.color(for: posture))
                    .tracking(0.3)
            }
        }
        .accessibilityLabel("Posture: \(posture.displayLabel)")
    }
}

// MARK: - GlassPanel

public struct GlassPanel<Content: View>: View {
    let elevated: Bool
    let truth: TruthMode?
    let content: Content

    public init(elevated: Bool = false, truth: TruthMode? = nil, @ViewBuilder content: () -> Content) {
        self.elevated = elevated
        self.truth = truth
        self.content = content()
    }

    public var body: some View {
        content
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(.regularMaterial)
                    .opacity(elevated ? 0.95 : 0.78)
            )
            .overlay(
                Group {
                    if let truth {
                        RoundedRectangle(cornerRadius: 12)
                            .strokeBorder(
                                BeagleTheme.color(for: truth),
                                style: StrokeStyle(
                                    lineWidth: 1,
                                    dash: dashPattern(for: truth)
                                )
                            )
                    } else {
                        RoundedRectangle(cornerRadius: 12)
                            .strokeBorder(Color.white.opacity(0.06), lineWidth: 1)
                    }
                }
            )
            .shadow(color: .black.opacity(elevated ? 0.3 : 0), radius: 8, y: 4)
    }

    private func dashPattern(for truth: TruthMode) -> [CGFloat] {
        switch truth {
        case .observed:   return []
        case .remembered: return [4, 3]
        case .declared:   return [1, 3]
        case .stale:      return [1, 5]
        }
    }
}

// MARK: - Lane

/// Collapsible section with truth badge header.
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
            Button {
                withAnimation(.snappy) { expanded.toggle() }
            } label: {
                HStack {
                    Text(title.uppercased())
                        .font(BeagleTheme.uiFont(size: 11, weight: .semibold))
                        .tracking(0.08 * 11)
                        .foregroundStyle(BeagleTheme.textSecondary)

                    if let truth {
                        TruthBadge(truth, compact: true)
                    }

                    Spacer()

                    Image(systemName: "chevron.down")
                        .font(.system(size: 10))
                        .foregroundStyle(BeagleTheme.textTertiary)
                        .rotationEffect(.degrees(expanded ? 0 : -90))
                }
                .padding(12)
            }
            .buttonStyle(.plain)

            if expanded {
                content
                    .padding(.horizontal, 12)
                    .padding(.bottom, 12)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(.regularMaterial)
                .opacity(0.65)
        )
        .truthBorder(truth ?? .declared)
    }
}

// MARK: - PulsingGlow modifier (for always-on indicator)

struct PulsingGlow: ViewModifier {
    let enabled: Bool
    @State private var on = false

    func body(content: Content) -> some View {
        content
            .shadow(
                color: enabled ? BeagleTheme.truthObserved.opacity(on ? 0.5 : 0.2) : .clear,
                radius: on ? 8 : 4
            )
            .onAppear {
                guard enabled else { return }
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
