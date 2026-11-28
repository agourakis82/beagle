//
//  BeagleCockpitShellChrome.swift
//  BeagleCockpit
//
//  Launch overrides, cross-platform navigation title helpers, circadian
//  ambient shell presence views, and macOS MenuBarContent.
//

import SwiftUI
import BeagleCore
#if os(macOS)
import AppKit
#endif

struct LaunchOverrides {
    let selectedTab: Int?
    let projectSlug: String?

    static var current: LaunchOverrides {
        let args = ProcessInfo.processInfo.arguments

        func value(after flag: String) -> String? {
            guard let index = args.firstIndex(of: flag), args.indices.contains(index + 1) else { return nil }
            return args[index + 1]
        }

        let selectedTab = value(after: "--beagle-selected-tab").flatMap(Int.init)
        let projectSlug = value(after: "--beagle-project-slug")

        return LaunchOverrides(selectedTab: selectedTab, projectSlug: projectSlug)
    }
}

// Cross-platform navigation title display mode
extension View {
    @ViewBuilder
    func navigationBarTitleDisplayModeIfAvailable(_ mode: TitleDisplayMode) -> some View {
        #if os(iOS) || os(visionOS)
        self.navigationBarTitleDisplayMode(mode == .large ? .large : .inline)
        #else
        self
        #endif
    }
}

enum TitleDisplayMode {
    case large, inline
}

private enum CircadianPhase: Sendable, Equatable {
    case dawn, morning, peak, afternoon, evening, night

    static var current: CircadianPhase {
        let hour = Calendar.current.component(.hour, from: .now)
        switch hour {
        case 5..<8: return .dawn
        case 8..<12: return .morning
        case 12..<16: return .peak
        case 16..<19: return .afternoon
        case 19..<22: return .evening
        default: return .night
        }
    }

    var tint: Color {
        switch self {
        case .dawn:      return Color(red: 0.95, green: 0.75, blue: 0.35) // warm amber
        case .morning:   return Color(red: 0.85, green: 0.88, blue: 0.95) // cool clarity
        case .peak:      return Color(red: 0.95, green: 0.92, blue: 0.85) // neutral warm
        case .afternoon: return Color(red: 0.90, green: 0.78, blue: 0.55) // copper
        case .evening:   return Color(red: 0.60, green: 0.50, blue: 0.75) // dusky violet
        case .night:     return Color(red: 0.15, green: 0.12, blue: 0.30) // deep indigo
        }
    }

    var tintIntensity: Double {
        switch self {
        case .dawn: return 0.12
        case .morning: return 0.06
        case .peak: return 0.05
        case .afternoon: return 0.08
        case .evening: return 0.14
        case .night: return 0.18
        }
    }

    var brightnessFactor: Double {
        switch self {
        case .dawn: return 0.70
        case .morning: return 0.95
        case .peak: return 1.05
        case .afternoon: return 0.85
        case .evening: return 0.60
        case .night: return 0.40
        }
    }

    var blueRetention: Double {
        switch self {
        case .dawn: return 0.65
        case .morning: return 1.0
        case .peak: return 0.95
        case .afternoon: return 0.80
        case .evening: return 0.55
        case .night: return 0.35
        }
    }

    var driftSpeed: Double {
        switch self {
        case .dawn: return 0.5
        case .morning: return 0.9
        case .peak: return 1.1
        case .afternoon: return 0.8
        case .evening: return 0.4
        case .night: return 0.15
        }
    }
}

private struct ShellPresenceBackground: View {
    let presence: BeaglePresenceState
    @State private var phase: CGFloat = 0
    @State private var circadianPhase: CircadianPhase = .current
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            MeshGradient(
                width: 3,
                height: 3,
                points: animatedPoints,
                colors: gradientColors
            )
            .ignoresSafeArea()

            LinearGradient(
                colors: [
                    .black.opacity(0.06),
                    .black.opacity(0.18),
                    Color(red: 0.01, green: 0.02, blue: 0.05).opacity(0.94)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()
        }
        .onAppear {
            guard !reduceMotion else { return }
            let animDuration = min(9.0 / circadianPhase.driftSpeed, 60.0)
            withAnimation(.easeInOut(duration: animDuration).repeatForever(autoreverses: true)) {
                phase = 1
            }
        }
        .task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(60))
                let newPhase = CircadianPhase.current
                if newPhase != circadianPhase {
                    withAnimation(.easeInOut(duration: 3.0)) {
                        circadianPhase = newPhase
                    }
                }
            }
        }
    }

    private var animatedPoints: [SIMD2<Float>] {
        let drift: Float = reduceMotion ? 0 : Float(phase) * 0.05 * Float(circadianPhase.driftSpeed)
        return [
            SIMD2(0, 0), SIMD2(0.5, 0), SIMD2(1, 0),
            SIMD2(0 + drift, 0.5 - drift), SIMD2(0.5, 0.5 + drift), SIMD2(1 - drift, 0.5 + drift),
            SIMD2(0, 1), SIMD2(0.5, 1), SIMD2(1, 1)
        ]
    }

    private var gradientColors: [Color] {
        let glow = presence.glow
        let tint = presence.tint
        let bf = circadianPhase.brightnessFactor
        let br = circadianPhase.blueRetention
        let ct = circadianPhase.tint
        let ci = circadianPhase.tintIntensity

        func dimBlue(_ color: Color, _ r: Double, _ g: Double, _ b: Double) -> Color {
            Color(red: r, green: g, blue: b * br)
        }

        return [
            glow.opacity(0.22 * bf), tint.opacity(0.08 * bf), dimBlue(.clear, 0.02, 0.03, 0.08),
            tint.opacity(0.10 * bf), ct.opacity(ci), glow.opacity(0.10 * bf),
            dimBlue(.clear, 0.01, 0.02, 0.05), dimBlue(.clear, 0.02, 0.03, 0.07), dimBlue(.clear, 0.01, 0.01, 0.03)
        ]
    }
}

private struct ShellPresenceBanner: View {
    let presence: BeaglePresenceState
    let selectedTabTitle: String
    let runningAgentCount: Int
    let runningJobCount: Int
    let laneLabel: String
    let mindLabel: String
    let objectiveLabel: String?
    let compact: Bool

    var body: some View {
        GlassPanel(elevation: .floating, truth: presenceTruth) {
            if compact {
                HStack(spacing: BeagleSpacing.xs) {
                    compactIcon
                    PresencePill(
                        label: laneLabel,
                        systemImage: "scope",
                        tint: BeagleTheme.truthObserved
                    )
                    if runningAgentCount > 0 {
                        PresencePill(
                            label: mindLabel,
                            systemImage: "sparkles",
                            tint: BeagleTheme.truthRemembered
                        )
                    }
                    if showsCompactStatus {
                        PresencePill(
                            label: statusLine,
                            systemImage: "waveform",
                            tint: presence.tint
                        )
                    }
                    Spacer(minLength: BeagleSpacing.xs)
                    if shouldShowCompactObjective, let objectiveLabel, !objectiveLabel.isEmpty {
                        Text(objectiveLabel)
                            .font(BeagleFont.caption2.font)
                            .foregroundStyle(BeagleTheme.truthRemembered)
                            .lineLimit(1)
                    }
                }
            } else {
                HStack(alignment: .top, spacing: BeagleSpacing.md) {
                    compactIcon

                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: BeagleSpacing.xs) {
                            Text(selectedTabTitle)
                                .font(BeagleFont.caption.font)
                                .fontWeight(.semibold)
                                .foregroundStyle(BeagleTheme.textTertiary)
                                .textCase(.uppercase)
                                .tracking(0.8)
                            PresencePill(
                                label: statusLine,
                                systemImage: "waveform",
                                tint: presence.tint
                            )
                        }

                        HStack(spacing: BeagleSpacing.xs) {
                            PresencePill(
                                label: laneLabel,
                                systemImage: "scope",
                                tint: BeagleTheme.truthObserved
                            )
                            PresencePill(
                                label: mindLabel,
                                systemImage: "sparkles",
                                tint: BeagleTheme.truthRemembered
                            )
                        }

                        Text(presence.title)
                            .font(BeagleFont.subheadline.font)
                            .fontWeight(.semibold)
                            .foregroundStyle(BeagleTheme.textPrimary)

                        Text(presence.subtitle)
                            .font(BeagleFont.caption.font)
                            .foregroundStyle(BeagleTheme.textSecondary)
                            .lineLimit(2)

                        if let objectiveLabel, !objectiveLabel.isEmpty {
                            Text(objectiveLabel)
                                .font(BeagleFont.caption2.font)
                                .foregroundStyle(BeagleTheme.truthRemembered)
                                .lineLimit(2)
                        }
                    }

                    Spacer()
                }
            }
        }
    }

    private var compactIcon: some View {
        ZStack {
            Circle()
                .fill(presence.tint.opacity(compact ? 0.10 : 0.14))
                .frame(width: compact ? 24 : 34, height: compact ? 24 : 34)
            Image(systemName: presence.icon)
                .font(.system(size: compact ? 11 : 14, weight: .semibold))
                .foregroundStyle(presence.tint)
        }
    }

    private var showsCompactStatus: Bool {
        runningAgentCount > 0 || runningJobCount > 0 || presence == .strained
    }

    private var shouldShowCompactObjective: Bool {
        runningAgentCount > 0 || runningJobCount > 0
    }

    private var statusLine: String {
        if runningAgentCount > 0 || runningJobCount > 0 {
            var parts: [String] = []
            if runningAgentCount > 0 {
                parts.append("\(runningAgentCount) agent\(runningAgentCount == 1 ? "" : "s")")
            }
            if runningJobCount > 0 {
                parts.append("\(runningJobCount) job\(runningJobCount == 1 ? "" : "s")")
            }
            return parts.joined(separator: " · ")
        }
        switch presence {
        case .dormant:
            return "quiet continuity"
        case .attentive:
            return "ambient attention"
        case .active:
            return "live cognition"
        case .strained:
            return "signal strain"
        }
    }

    private var presenceTruth: TruthMode {
        switch presence {
        case .active:
            return .observed
        case .attentive:
            return .remembered
        case .dormant:
            return .declared
        case .strained:
            return .stale
        }
    }
}

// MARK: - Menu bar content (macOS)

#if os(macOS)
struct MenuBarContent: View {
    @Environment(CatalogStore.self) private var catalog

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("COCKPIT")
                .font(BeagleTheme.uiFont(size: 10, weight: .semibold))
                .tracking(1.2)
                .foregroundStyle(BeagleTheme.textTertiary)

            let counts = catalog.postureCounts
            HStack(spacing: 12) {
                Label("\(counts.alwaysOn)", systemImage: "circle.fill")
                    .foregroundStyle(BeagleTheme.postureOn)
                Label("\(counts.warm)", systemImage: "circle.lefthalf.filled")
                    .foregroundStyle(BeagleTheme.postureWarm)
                Label("\(counts.cold)", systemImage: "circle")
                    .foregroundStyle(BeagleTheme.postureCold)
            }
            .font(BeagleTheme.dataFont(size: 12))

            Divider().padding(.vertical, 4)

            ForEach(catalog.alwaysOnProjects) { project in
                Button {
                    NSApp.activate(ignoringOtherApps: true)
                } label: {
                    HStack {
                        PostureIndicator(project.posture, size: 11, showLabel: false)
                        Text(project.projectSlug)
                            .font(BeagleTheme.dataFont(size: 12))
                    }
                }
                .buttonStyle(.plain)
            }

            Divider().padding(.vertical, 4)

            Button("Open Cockpit") {
                NSApp.activate(ignoringOtherApps: true)
            }
            Button("Refresh") {
                Task { await catalog.refresh() }
            }
            Button("Quit") {
                NSApp.terminate(nil)
            }
        }
        .padding(12)
        .frame(width: 240)
    }
}
#endif
