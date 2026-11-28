//
//  AgentAndCognitiveLiveActivities.swift
//  BeagleWidgets
//
//  Live Activities for Agent Sessions, Research Runs, and Cognitive State (iOS only).
//

#if os(iOS)
import ActivityKit
import WidgetKit
import SwiftUI
import BeagleCore

// MARK: - Live Activity: Agent Session

struct AgentSessionActivityConfiguration: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: AgentSessionAttributes.self) { context in
            // Lock screen / banner UI
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Image(systemName: "sparkles")
                        .foregroundStyle(BeagleTheme.truthObserved)
                    Text("\(context.attributes.agentKind.uppercased()) · \(context.attributes.projectSlug)")
                        .font(BeagleTheme.dataFont(size: 12, weight: .medium))
                        .foregroundStyle(BeagleTheme.textPrimary)
                    Spacer()
                    Text(context.state.status)
                        .font(BeagleTheme.dataFont(size: 11))
                        .foregroundStyle(BeagleTheme.truthObserved)
                }
                if !context.state.lastOutputSnippet.isEmpty {
                    Text(context.state.lastOutputSnippet)
                        .font(BeagleTheme.dataFont(size: 11))
                        .foregroundStyle(BeagleTheme.textSecondary)
                        .lineLimit(2)
                }
                HStack {
                    Text("\(context.state.tokensUsed) tokens")
                        .font(BeagleTheme.dataFont(size: 10))
                        .foregroundStyle(BeagleTheme.textTertiary)
                    Spacer()
                }
            }
            .padding(12)
            .activityBackgroundTint(BeagleTheme.surface1)
            .activitySystemActionForegroundColor(BeagleTheme.truthObserved)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Image(systemName: "sparkles")
                        .foregroundStyle(BeagleTheme.truthObserved)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text(context.state.status)
                        .font(BeagleTheme.dataFont(size: 11))
                        .foregroundStyle(BeagleTheme.truthObserved)
                }
                DynamicIslandExpandedRegion(.center) {
                    Text("\(context.attributes.agentKind) · \(context.attributes.projectSlug)")
                        .font(BeagleTheme.dataFont(size: 12, weight: .medium))
                }
                DynamicIslandExpandedRegion(.bottom) {
                    Text(context.state.lastOutputSnippet)
                        .font(BeagleTheme.dataFont(size: 10))
                        .foregroundStyle(BeagleTheme.textSecondary)
                        .lineLimit(2)
                }
            } compactLeading: {
                Image(systemName: "sparkles")
            } compactTrailing: {
                Text(context.state.status.prefix(4))
                    .font(BeagleTheme.dataFont(size: 10))
            } minimal: {
                Image(systemName: "sparkles")
                    .foregroundStyle(BeagleTheme.truthObserved)
            }
        }
    }
}

// MARK: - Live Activity: Research Run

struct ResearchRunActivityConfiguration: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: ResearchRunAttributes.self) { context in
            let done = context.state.isCompleted == true
            let accent = done ? BeagleTheme.truthObserved : BeagleTheme.truthRemembered
            VStack(alignment: .leading, spacing: 7) {
                HStack(spacing: 6) {
                    Image(systemName: done ? "checkmark.seal.fill" : "sparkle.magnifyingglass")
                        .foregroundStyle(accent)
                    Text(context.attributes.campaignName)
                        .font(BeagleTheme.dataFont(size: 12, weight: .semibold))
                        .foregroundStyle(BeagleTheme.textPrimary)
                        .lineLimit(1)
                    Spacer()
                    if done {
                        Text("Concluído")
                            .font(BeagleTheme.dataFont(size: 10, weight: .semibold))
                            .foregroundStyle(BeagleTheme.truthObserved)
                    } else if let lens = context.state.activeLens, !lens.isEmpty {
                        Text(lens)
                            .font(BeagleTheme.dataFont(size: 10, weight: .medium))
                            .foregroundStyle(BeagleTheme.truthObserved)
                            .lineLimit(1)
                    } else {
                        Text("ETA \(max(1, context.state.etaSeconds / 60))m")
                            .font(BeagleTheme.dataFont(size: 10))
                            .foregroundStyle(BeagleTheme.truthObserved)
                    }
                }
                ProgressView(
                    value: Double(context.state.stepCurrent),
                    total: Double(max(1, context.state.stepTotal))
                )
                .tint(accent)

                if let snippet = context.state.summarySnippet, !snippet.isEmpty {
                    Text(snippet)
                        .font(BeagleTheme.dataFont(size: 11))
                        .foregroundStyle(BeagleTheme.textSecondary)
                        .lineLimit(2)
                }

                HStack {
                    Text("Etapa \(context.state.stepCurrent)/\(context.state.stepTotal)")
                        .font(BeagleTheme.dataFont(size: 10))
                        .foregroundStyle(BeagleTheme.textTertiary)
                    Spacer()
                    Text(done ? "Abrir síntese no Modo Fundo" : "Modo Fundo ao vivo")
                        .font(BeagleTheme.dataFont(size: 10))
                        .foregroundStyle(BeagleTheme.textTertiary)
                }
            }
            .padding(12)
            .activityBackgroundTint(BeagleTheme.surface1)
            .widgetURL(URL(string: "beagle://fundo"))
        } dynamicIsland: { context in
            let done = context.state.isCompleted == true
            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    HStack(spacing: 4) {
                        Image(systemName: done ? "checkmark.seal.fill" : "sparkle.magnifyingglass")
                            .foregroundStyle(BeagleTheme.truthObserved)
                        Text("Modo Fundo")
                            .font(BeagleTheme.dataFont(size: 11, weight: .semibold))
                    }
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text(done ? "Concluído" : (context.state.activeLens ?? "\(context.state.stepCurrent)/\(context.state.stepTotal)"))
                        .font(BeagleTheme.dataFont(size: 10, weight: .medium))
                        .foregroundStyle(BeagleTheme.truthObserved)
                        .lineLimit(1)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(alignment: .leading, spacing: 5) {
                        Text(context.attributes.campaignName)
                            .font(BeagleTheme.dataFont(size: 11, weight: .medium))
                            .lineLimit(1)
                        ProgressView(
                            value: Double(context.state.stepCurrent),
                            total: Double(max(1, context.state.stepTotal))
                        )
                        .tint(BeagleTheme.truthObserved)
                        if let snippet = context.state.summarySnippet, !snippet.isEmpty {
                            Text(snippet)
                                .font(BeagleTheme.dataFont(size: 10))
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                        }
                    }
                }
            } compactLeading: {
                Image(systemName: done ? "checkmark.seal.fill" : "sparkle.magnifyingglass")
                    .foregroundStyle(BeagleTheme.truthObserved)
            } compactTrailing: {
                Text(done ? "OK" : "\(context.state.stepCurrent)/\(context.state.stepTotal)")
                    .font(BeagleTheme.dataFont(size: 10, weight: .semibold))
                    .foregroundStyle(BeagleTheme.truthObserved)
            } minimal: {
                Image(systemName: done ? "checkmark.seal.fill" : "sparkle.magnifyingglass")
                    .foregroundStyle(BeagleTheme.truthObserved)
            }
            .widgetURL(URL(string: "beagle://fundo"))
        }
    }
}

// MARK: - Live Activity: Cognitive State (HRV + Agent Posture)

struct CognitiveActivityConfiguration: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: CognitiveActivityAttributes.self) { context in
            // Lock screen / notification banner
            CognitiveLockScreenView(state: context.state)
                .activityBackgroundTint(BeagleTheme.surface1)
                .activitySystemActionForegroundColor(
                    BeagleTheme.color(forIntensity: context.state.intensity)
                )
        } dynamicIsland: { context in
            DynamicIsland {
                // Expanded: full cognitive dashboard
                DynamicIslandExpandedRegion(.leading) {
                    CognitiveReadinessGauge(
                        readiness: context.state.readiness,
                        intensity: context.state.intensity,
                        size: 44
                    )
                }
                DynamicIslandExpandedRegion(.trailing) {
                    VStack(alignment: .trailing, spacing: 4) {
                        if let hrv = context.state.hrvMs {
                            HStack(spacing: 3) {
                                Image(systemName: "heart.fill")
                                    .font(.system(size: 9))
                                    .foregroundStyle(BeagleTheme.color(forIntensity: context.state.intensity))
                                Text("\(Int(hrv)) ms")
                                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                            }
                        }
                        if context.state.agentCount > 0 {
                            HStack(spacing: 3) {
                                Image(systemName: "sparkles")
                                    .font(.system(size: 9))
                                Text("\(context.state.agentCount)")
                                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                            }
                            .foregroundStyle(BeagleTheme.truthObserved)
                        }
                    }
                }
                DynamicIslandExpandedRegion(.center) {
                    Text(context.state.intensityLabel)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(BeagleTheme.color(forIntensity: context.state.intensity))
                }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(alignment: .leading, spacing: 4) {
                        if context.state.activeJobCount > 0 {
                            HStack(spacing: 4) {
                                Image(systemName: "gearshape.2.fill")
                                    .font(.system(size: 9))
                                    .foregroundStyle(BeagleTheme.textTertiary)
                                Text("\(context.state.activeJobCount) active job\(context.state.activeJobCount == 1 ? "" : "s")")
                                    .font(.system(size: 11, weight: .regular))
                                    .foregroundStyle(BeagleTheme.textSecondary)
                            }
                        }
                        if let snippet = context.state.lastThoughtSnippet, !snippet.isEmpty {
                            Text(snippet)
                                .font(.system(size: 11))
                                .foregroundStyle(BeagleTheme.textSecondary)
                                .lineLimit(2)
                        }
                    }
                }
            } compactLeading: {
                // Readiness as a small circular gauge
                CognitiveReadinessGauge(
                    readiness: context.state.readiness,
                    intensity: context.state.intensity,
                    size: 24
                )
            } compactTrailing: {
                // Agent count when agents are active
                if context.state.agentCount > 0 {
                    HStack(spacing: 2) {
                        Image(systemName: "sparkles")
                            .font(.system(size: 9))
                        Text("\(context.state.agentCount)")
                            .font(.system(size: 12, weight: .semibold, design: .monospaced))
                    }
                    .foregroundStyle(BeagleTheme.truthObserved)
                } else {
                    Text(context.state.intensity.prefix(3).uppercased())
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundStyle(BeagleTheme.color(forIntensity: context.state.intensity))
                }
            } minimal: {
                CognitiveReadinessGauge(
                    readiness: context.state.readiness,
                    intensity: context.state.intensity,
                    size: 20
                )
            }
        }
    }
}

// MARK: - Cognitive Activity: Subviews

private struct CognitiveReadinessGauge: View {
    let readiness: Double?
    let intensity: String
    let size: CGFloat

    private var fraction: Double {
        readiness ?? 0
    }

    private var tint: Color {
        BeagleTheme.color(forIntensity: intensity)
    }

    var body: some View {
        ZStack {
            Circle()
                .stroke(tint.opacity(0.2), lineWidth: size > 30 ? 4 : 2.5)
            Circle()
                .trim(from: 0, to: fraction)
                .stroke(tint, style: StrokeStyle(
                    lineWidth: size > 30 ? 4 : 2.5,
                    lineCap: .round
                ))
                .rotationEffect(.degrees(-90))

            if size >= 40 {
                Text("\(Int((fraction * 100).rounded()))")
                    .font(.system(size: size * 0.3, weight: .bold, design: .rounded))
                    .foregroundStyle(tint)
            }
        }
        .frame(width: size, height: size)
    }
}

private struct CognitiveLockScreenView: View {
    let state: CognitiveActivityAttributes.ContentState

    private var tint: Color {
        BeagleTheme.color(forIntensity: state.intensity)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                CognitiveReadinessGauge(
                    readiness: state.readiness,
                    intensity: state.intensity,
                    size: 36
                )

                VStack(alignment: .leading, spacing: 2) {
                    Text(state.lockScreenLine)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(tint)

                    HStack(spacing: 8) {
                        if let hrv = state.hrvMs {
                            HStack(spacing: 3) {
                                Image(systemName: "heart.fill")
                                    .font(.system(size: 9))
                                Text("\(Int(hrv)) ms")
                                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                            }
                            .foregroundStyle(BeagleTheme.textData)
                        }
                        if state.activeJobCount > 0 {
                            HStack(spacing: 3) {
                                Image(systemName: "gearshape.2.fill")
                                    .font(.system(size: 9))
                                Text("\(state.activeJobCount) job\(state.activeJobCount == 1 ? "" : "s")")
                                    .font(.system(size: 11, weight: .regular))
                            }
                            .foregroundStyle(BeagleTheme.textSecondary)
                        }
                    }
                }

                Spacer()
            }

            if let snippet = state.lastThoughtSnippet, !snippet.isEmpty {
                Text(snippet)
                    .font(.system(size: 11))
                    .foregroundStyle(BeagleTheme.textSecondary)
                    .lineLimit(2)
            }
        }
        .padding(12)
    }
}
#endif
