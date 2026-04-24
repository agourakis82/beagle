//
//  Theme.swift
//  BeagleCore
//
//  Sovereign Dark design system — command bridge aesthetic.
//  Ported from the web cockpit's design tokens with native Apple idioms.
//
//  Principles:
//   - Color = meaning, never decoration
//   - Monospace for data only, SF Pro for everything else
//   - 8px spacing grid
//   - Semantic elevation (flush → raised → floating)
//   - Physics-based motion tokens
//

import SwiftUI

// MARK: - BeagleTheme (colors + legacy aliases)

public enum BeagleTheme {

    // MARK: - Truth colors (semantic: data freshness)

    public static let truthObserved    = Color(hue: 165/360, saturation: 0.60, brightness: 0.90) // teal — live
    public static let truthRemembered  = Color(hue: 214/360, saturation: 0.70, brightness: 1.00) // sky — cached
    public static let truthDeclared    = Color(hue: 215/360, saturation: 0.25, brightness: 0.75) // slate — policy
    public static let truthStale       = Color(hue: 220/360, saturation: 0.10, brightness: 0.45) // gray — expired

    public static func color(for truth: TruthMode) -> Color {
        switch truth {
        case .observed:   return truthObserved
        case .remembered: return truthRemembered
        case .declared:   return truthDeclared
        case .stale:      return truthStale
        }
    }

    // MARK: - Posture colors (semantic: operational state)

    public static let postureOn   = truthObserved
    public static let postureWarm = Color(hue: 42/360, saturation: 0.88, brightness: 1.00) // gold
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

    // MARK: - Intensity colors (semantic: cognitive load / HRV-derived)

    public static let intensityMinimal   = Color(hue: 230/360, saturation: 0.25, brightness: 0.55) // muted indigo
    public static let intensityCalm      = Color(hue: 190/360, saturation: 0.50, brightness: 0.80) // cool cyan
    public static let intensityNormal    = truthObserved                                           // teal
    public static let intensityEngaged   = postureWarm                                             // gold
    public static let intensityChallenge = Color(hue: 18/360,  saturation: 0.85, brightness: 0.95) // warm orange

    public static func color(forIntensity intensity: String) -> Color {
        switch intensity {
        case "minimal":   return intensityMinimal
        case "calm":      return intensityCalm
        case "normal":    return intensityNormal
        case "engaged":   return intensityEngaged
        case "challenge": return intensityChallenge
        default:          return intensityNormal
        }
    }

    // MARK: - Surfaces (4-level depth)

    public static let surface0 = Color(red: 5/255,  green: 10/255, blue: 18/255)  // deepest
    public static let surface1 = Color(red: 10/255, green: 22/255, blue: 40/255)
    public static let surface2 = Color(red: 15/255, green: 31/255, blue: 56/255)
    public static let surface3 = Color(red: 22/255, green: 42/255, blue: 74/255)  // highest

    // MARK: - Text hierarchy

    public static let textPrimary   = Color.white.opacity(0.94)
    public static let textSecondary = Color.white.opacity(0.58)
    public static let textTertiary  = Color.white.opacity(0.34)
    public static let textData      = Color(red: 200/255, green: 230/255, blue: 255/255).opacity(0.90) // cool cyan tint
    public static let hairline      = Color.white.opacity(0.08)

    // MARK: - Legacy font aliases (deprecated — use BeagleFont instead)

    public static func dataFont(size: CGFloat = 13, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .monospaced)
    }

    public static func uiFont(size: CGFloat = 15, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .default)
    }

    public static func displayFont(size: CGFloat = 24, weight: Font.Weight = .semibold) -> Font {
        .system(size: size, weight: weight, design: .default)
    }
}

// MARK: - Presence System

public enum BeaglePresenceState: String, Sendable {
    case dormant
    case attentive
    case active
    case strained

    public var title: String {
        switch self {
        case .dormant:
            return "Beagle is resting lightly"
        case .attentive:
            return "Beagle is paying attention"
        case .active:
            return "Beagle is fully present"
        case .strained:
            return "Beagle is holding through interference"
        }
    }

    public var subtitle: String {
        switch self {
        case .dormant:
            return "The shell is quiet, but the system still remembers where you were."
        case .attentive:
            return "Device and cluster are listening for the next move."
        case .active:
            return "Agents, jobs, and memory are all in the room with you."
        case .strained:
            return "Truth is still visible, even when the channel is under pressure."
        }
    }

    public var icon: String {
        switch self {
        case .dormant:
            return "moon.stars.fill"
        case .attentive:
            return "eye.fill"
        case .active:
            return "sparkles"
        case .strained:
            return "waveform.path.ecg"
        }
    }

    public var tint: Color {
        switch self {
        case .dormant:
            return BeagleTheme.truthDeclared
        case .attentive:
            return BeagleTheme.truthRemembered
        case .active:
            return BeagleTheme.truthObserved
        case .strained:
            return BeagleTheme.postureWarm
        }
    }

    public var glow: Color {
        switch self {
        case .dormant:
            return Color(hue: 230/360, saturation: 0.24, brightness: 0.45)
        case .attentive:
            return Color(hue: 192/360, saturation: 0.48, brightness: 0.84)
        case .active:
            return Color(hue: 166/360, saturation: 0.66, brightness: 0.92)
        case .strained:
            return Color(hue: 28/360, saturation: 0.75, brightness: 0.95)
        }
    }
}

public struct PresenceFieldCard<Accessory: View>: View {
    private let state: BeaglePresenceState
    private let eyebrow: String
    private let title: String
    private let message: String
    private let detail: String?
    private let truth: TruthMode
    private let accessory: Accessory

    public init(
        state: BeaglePresenceState,
        eyebrow: String,
        title: String,
        body message: String,
        detail: String? = nil,
        truth: TruthMode,
        @ViewBuilder accessory: () -> Accessory
    ) {
        self.state = state
        self.eyebrow = eyebrow
        self.title = title
        self.message = message
        self.detail = detail
        self.truth = truth
        self.accessory = accessory()
    }

    public var body: some View {
        GlassPanel(elevation: .floating, truth: truth) {
            VStack(alignment: .leading, spacing: BeagleSpacing.md) {
                HStack(alignment: .top, spacing: BeagleSpacing.md) {
                    ZStack {
                        Circle()
                            .fill(state.tint.opacity(0.14))
                            .frame(width: 38, height: 38)
                        Image(systemName: state.icon)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(state.tint)
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        Text(eyebrow)
                            .font(BeagleFont.caption.font)
                            .fontWeight(.semibold)
                            .foregroundStyle(BeagleTheme.textTertiary)
                            .textCase(.uppercase)
                            .tracking(0.8)
                        Text(title)
                            .font(BeagleFont.title3.font)
                            .fontWeight(.semibold)
                            .foregroundStyle(BeagleTheme.textPrimary)
                        Text(message)
                            .font(BeagleFont.footnote.font)
                            .foregroundStyle(BeagleTheme.textSecondary)
                            .lineSpacing(2)
                    }

                    Spacer(minLength: BeagleSpacing.sm)
                }

                PresenceConstellation(state: state)

                if let detail, !detail.isEmpty {
                    Text(detail)
                        .font(BeagleFont.caption.font)
                        .foregroundStyle(BeagleTheme.textTertiary)
                        .lineSpacing(2)
                }

                accessory
            }
        }
    }
}

private struct PresenceConstellation: View {
    let state: BeaglePresenceState

    var body: some View {
        HStack(spacing: BeagleSpacing.sm) {
            presenceNode(size: 11, opacity: 0.95)
            capsule(width: 44, opacity: 0.35)
            presenceNode(size: 8, opacity: 0.65)
            capsule(width: 28, opacity: 0.20)
            presenceNode(size: 6, opacity: 0.40)
            Spacer()
            Text(state.subtitle)
                .font(BeagleFont.caption2.font)
                .foregroundStyle(BeagleTheme.textTertiary)
                .lineLimit(2)
        }
    }

    private func presenceNode(size: CGFloat, opacity: Double) -> some View {
        Circle()
            .fill(state.tint.opacity(opacity))
            .frame(width: size, height: size)
            .shadow(color: state.glow.opacity(opacity * 0.5), radius: size, y: 0)
    }

    private func capsule(width: CGFloat, opacity: Double) -> some View {
        Capsule()
            .fill(
                LinearGradient(
                    colors: [state.tint.opacity(opacity), state.glow.opacity(opacity * 0.65)],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
            .frame(width: width, height: 4)
    }
}

// MARK: - Semantic Typography

public enum BeagleFont {
    // iOS system typography scale (Apple HIG compliant)
    case caption2          // 11pt regular  — smallest labels
    case caption           // 12pt regular  — timestamps, tertiary
    case footnote          // 13pt regular  — descriptions, secondary
    case subheadline       // 15pt regular  — supporting text
    case callout           // 16pt regular  — callout text
    case body              // 17pt regular  — primary reading text (iOS standard)
    case headline          // 17pt semibold — section titles
    case title3            // 20pt regular  — card titles
    case title2            // 22pt bold     — section titles
    case title1            // 28pt bold     — page titles
    case largeTitle        // 34pt bold     — large navigation title
    case hero              // 48pt bold     — hero numbers, display

    // Data — SF Mono (monospaced, tabular numerals)
    case dataSmall         // 11pt regular  — line numbers, IDs
    case data              // 13pt regular  — terminal, paths, values
    case dataProminent     // 15pt medium   — highlighted data

    public var font: Font {
        switch self {
        case .caption2:      return .system(size: 11, weight: .regular, design: .default)
        case .caption:       return .system(size: 12, weight: .regular, design: .default)
        case .footnote:      return .system(size: 13, weight: .regular, design: .default)
        case .subheadline:   return .system(size: 15, weight: .regular, design: .default)
        case .callout:       return .system(size: 16, weight: .regular, design: .default)
        case .body:          return .system(size: 17, weight: .regular, design: .default)
        case .headline:      return .system(size: 17, weight: .semibold, design: .default)
        case .title3:        return .system(size: 20, weight: .regular, design: .default)
        case .title2:        return .system(size: 22, weight: .bold, design: .default)
        case .title1:        return .system(size: 28, weight: .bold, design: .default)
        case .largeTitle:    return .system(size: 34, weight: .bold, design: .default)
        case .hero:          return .system(size: 48, weight: .bold, design: .default)
        case .dataSmall:     return .system(size: 11, weight: .regular, design: .monospaced)
        case .data:          return .system(size: 13, weight: .regular, design: .monospaced)
        case .dataProminent: return .system(size: 15, weight: .medium, design: .monospaced)
        }
    }
}

// MARK: - Spacing Scale (8px base)

public enum BeagleSpacing {
    public static let xxs:  CGFloat = 4
    public static let xs:   CGFloat = 8
    public static let sm:   CGFloat = 12
    public static let md:   CGFloat = 16
    public static let lg:   CGFloat = 20
    public static let xl:   CGFloat = 24
    public static let xxl:  CGFloat = 32
    public static let xxxl: CGFloat = 40
    public static let jumbo: CGFloat = 48
}

// MARK: - Corner Radius Scale

public enum BeagleRadius {
    public static let sm:   CGFloat = 6    // chips, badges
    public static let md:   CGFloat = 10   // inputs, small cards
    public static let lg:   CGFloat = 14   // standard cards, lanes
    public static let xl:   CGFloat = 20   // hero panels
    public static let pill: CGFloat = 999  // capsule shapes
}

// MARK: - Elevation System

public enum PanelElevation {
    case flush      // surface-level: no shadow, faint border
    case raised     // standard cards: light shadow
    case floating   // hero cards: strong shadow + ambient glow
}

// MARK: - Animation Tokens

public enum BeagleMotion {
    public static let fast      = Animation.easeOut(duration: 0.12)
    public static let normal    = Animation.easeInOut(duration: 0.2)
    public static let slow      = Animation.easeInOut(duration: 0.4)
    public static let dramatic  = Animation.easeInOut(duration: 0.8)
    public static let snappy    = Animation.spring(duration: 0.3, bounce: 0.15)
    public static let bouncy    = Animation.spring(duration: 0.5, bounce: 0.25)
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
            RoundedRectangle(cornerRadius: BeagleRadius.lg)
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
        case .observed:   return []           // solid — live data
        case .remembered: return [4, 3]       // dashed — cached
        case .declared:   return [1, 3]       // dotted — policy
        case .stale:      return [1, 5]       // sparse — expired
        }
    }
}

public extension View {
    func truthBorder(_ truth: TruthMode, lineWidth: CGFloat = 1) -> some View {
        modifier(TruthBorder(truth: truth, lineWidth: lineWidth))
    }
}
