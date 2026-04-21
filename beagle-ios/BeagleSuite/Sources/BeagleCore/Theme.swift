//
//  Theme.swift
//  BeagleCore
//
//  Design tokens — Swift/SwiftUI port of the web cockpit's "Sovereign Dark"
//  semantic color system.
//
//  Color = meaning, never decoration.
//

import SwiftUI

public enum BeagleTheme {

    // MARK: - Truth colors

    public static let truthObserved    = Color(hue: 165/360, saturation: 0.60, brightness: 0.90)
    public static let truthRemembered  = Color(hue: 214/360, saturation: 0.70, brightness: 1.00)
    public static let truthDeclared    = Color(hue: 215/360, saturation: 0.25, brightness: 0.75)
    public static let truthStale       = Color(hue: 220/360, saturation: 0.10, brightness: 0.45)

    public static func color(for truth: TruthMode) -> Color {
        switch truth {
        case .observed:   return truthObserved
        case .remembered: return truthRemembered
        case .declared:   return truthDeclared
        case .stale:      return truthStale
        }
    }

    // MARK: - Posture colors

    public static let postureOn   = truthObserved
    public static let postureWarm = Color(hue: 42/360, saturation: 0.88, brightness: 1.00)
    public static let postureCold = truthDeclared

    public static func color(for posture: ProjectPosture) -> Color {
        switch posture {
        case .alwaysOn: return postureOn
        case .warm:     return postureWarm
        case .cold:     return postureCold
        case .unknown:  return truthStale
        }
    }

    // MARK: - Operational state

    public static let stateReady    = truthObserved
    public static let stateStarting = postureWarm
    public static let stateError    = Color(hue: 0, saturation: 0.84, brightness: 0.95)
    public static let statePlanned  = truthDeclared

    // MARK: - Surfaces

    public static let surface0 = Color(red: 5/255,  green: 10/255, blue: 18/255)
    public static let surface1 = Color(red: 10/255, green: 22/255, blue: 40/255)
    public static let surface2 = Color(red: 15/255, green: 31/255, blue: 56/255)
    public static let surface3 = Color(red: 22/255, green: 42/255, blue: 74/255)

    // MARK: - Text

    public static let textPrimary   = Color.white.opacity(0.94)
    public static let textSecondary = Color.white.opacity(0.58)
    public static let textTertiary  = Color.white.opacity(0.34)
    public static let textData      = Color(red: 200/255, green: 230/255, blue: 255/255).opacity(0.90)

    // MARK: - Typography

    /// Data font — monospaced, tabular numerals. For IDs, timestamps, paths, numbers.
    public static func dataFont(size: CGFloat = 13, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .monospaced)
    }

    /// UI font — default SF text. For labels, descriptions.
    public static func uiFont(size: CGFloat = 15, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .default)
    }

    /// Display font — tight tracking. For page titles, hero project names.
    public static func displayFont(size: CGFloat = 24, weight: Font.Weight = .semibold) -> Font {
        .system(size: size, weight: weight, design: .default)
    }
}

// MARK: - Style Modifiers

public struct TruthBorder: ViewModifier {
    let truth: TruthMode
    let lineWidth: CGFloat

    public init(truth: TruthMode, lineWidth: CGFloat = 1) {
        self.truth = truth
        self.lineWidth = lineWidth
    }

    public func body(content: Content) -> some View {
        content.overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(
                    BeagleTheme.color(for: truth),
                    style: StrokeStyle(
                        lineWidth: lineWidth,
                        dash: dashPattern
                    )
                )
        )
    }

    private var dashPattern: [CGFloat] {
        switch truth {
        case .observed:   return []           // solid
        case .remembered: return [4, 3]       // dashed
        case .declared:   return [1, 3]       // dotted
        case .stale:      return [1, 5]       // sparse dotted
        }
    }
}

public extension View {
    func truthBorder(_ truth: TruthMode, lineWidth: CGFloat = 1) -> some View {
        modifier(TruthBorder(truth: truth, lineWidth: lineWidth))
    }
}

// MARK: - Glass surface (uses iOS 26 Liquid Glass materials)

public extension View {
    /// Apply a glass container style (uses system material where available).
    func glassPanel(elevated: Bool = false) -> some View {
        self
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(.regularMaterial)
                    .opacity(elevated ? 0.95 : 0.75)
            )
    }
}
