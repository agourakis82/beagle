//
//  CompanionLiveActivities.swift
//  BeagleWidgets
//
//  Live Activities for Companion continuous hands-free voice sessions
//  and Companion turns (iOS only).
//

#if os(iOS)
import ActivityKit
import AppIntents
import WidgetKit
import SwiftUI
import BeagleCore

// MARK: - Live Activity: Continuous Hands-Free Voice Session (Walkie-Talkie + Interactive Dynamic Island)

struct CompanionVoiceSessionActivityConfiguration: Widget {
    private func accent(for phase: CompanionLiveVoicePhase) -> Color {
        switch phase {
        case .listening: return BeagleTheme.truthObserved
        case .thinking:  return BeagleTheme.truthRemembered
        case .speaking:  return BeagleTheme.postureWarm
        case .paused:    return BeagleTheme.textSecondary
        case .ended:     return BeagleTheme.textTertiary
        }
    }

    var body: some WidgetConfiguration {
        ActivityConfiguration(for: CompanionVoiceSessionAttributes.self) { context in
            let phase = context.state.phase
            let tint = accent(for: phase)

            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    Image(systemName: phase.symbolName)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(tint)
                    Text("Beagle · \(phase.titlePtBR)")
                        .font(BeagleTheme.uiFont(size: 13, weight: .semibold))
                        .foregroundStyle(BeagleTheme.textPrimary)
                    Spacer()
                    if context.state.turnCount > 0 {
                        Text("T\(context.state.turnCount)")
                            .font(BeagleTheme.dataFont(size: 10, weight: .semibold))
                            .foregroundStyle(BeagleTheme.textTertiary)
                    }
                    Text(context.state.voiceLabel)
                        .font(BeagleTheme.dataFont(size: 11, weight: .medium))
                        .foregroundStyle(tint)
                }

                Text(context.state.liveLine.isEmpty ? phase.defaultLinePtBR : context.state.liveLine)
                    .font(BeagleTheme.dataFont(size: 11))
                    .foregroundStyle(BeagleTheme.textSecondary)
                    .lineLimit(2)

                HStack(spacing: 8) {
                    if phase == .speaking {
                        Button(intent: InterruptSpeechLiveVoiceIntent()) {
                            Label("Falar agora", systemImage: "mic.fill")
                                .font(BeagleTheme.uiFont(size: 11, weight: .semibold))
                                .padding(.horizontal, 10)
                                .padding(.vertical, 5)
                                .background(BeagleTheme.truthObserved.opacity(0.22), in: Capsule())
                                .foregroundStyle(BeagleTheme.truthObserved)
                        }
                        .buttonStyle(.plain)
                    }

                    Button(intent: TogglePauseLiveVoiceIntent()) {
                        Label(
                            phase == .paused ? "Retomar" : "Pausar",
                            systemImage: phase == .paused ? "play.fill" : "pause.fill"
                        )
                        .font(BeagleTheme.uiFont(size: 11, weight: .semibold))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Color.white.opacity(0.10), in: Capsule())
                        .foregroundStyle(BeagleTheme.textPrimary)
                    }
                    .buttonStyle(.plain)

                    Spacer(minLength: 4)

                    Button(intent: EndLiveVoiceSessionIntent()) {
                        Label("Encerrar", systemImage: "xmark")
                            .font(BeagleTheme.uiFont(size: 11, weight: .semibold))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(BeagleTheme.stateError.opacity(0.20), in: Capsule())
                            .foregroundStyle(BeagleTheme.stateError)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(12)
            .activityBackgroundTint(BeagleTheme.surface1)
            .activitySystemActionForegroundColor(tint)
        } dynamicIsland: { context in
            let phase = context.state.phase
            let tint = accent(for: phase)

            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    HStack(spacing: 5) {
                        Image(systemName: phase.symbolName)
                            .foregroundStyle(tint)
                        Text(phase.titlePtBR)
                            .font(BeagleTheme.uiFont(size: 12, weight: .semibold))
                            .foregroundStyle(tint)
                    }
                }
                DynamicIslandExpandedRegion(.trailing) {
                    HStack(spacing: 4) {
                        if context.state.turnCount > 0 {
                            Text("T\(context.state.turnCount)")
                                .font(BeagleTheme.dataFont(size: 10))
                                .foregroundStyle(BeagleTheme.textTertiary)
                        }
                        Text(context.state.voiceLabel)
                            .font(BeagleTheme.dataFont(size: 11, weight: .medium))
                            .foregroundStyle(BeagleTheme.textSecondary)
                            .lineLimit(1)
                    }
                }
                DynamicIslandExpandedRegion(.center) {
                    Text(context.attributes.conversationTitle)
                        .font(BeagleTheme.dataFont(size: 12, weight: .medium))
                        .foregroundStyle(BeagleTheme.textPrimary)
                        .lineLimit(1)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(context.state.liveLine.isEmpty ? phase.defaultLinePtBR : context.state.liveLine)
                            .font(BeagleTheme.dataFont(size: 11))
                            .foregroundStyle(BeagleTheme.textSecondary)
                            .lineLimit(2)

                        HStack(spacing: 8) {
                            if phase == .speaking {
                                Button(intent: InterruptSpeechLiveVoiceIntent()) {
                                    Label("Cortar", systemImage: "mic.fill")
                                        .font(.system(size: 11, weight: .semibold))
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 5)
                                        .background(BeagleTheme.truthObserved.opacity(0.22), in: Capsule())
                                        .foregroundStyle(BeagleTheme.truthObserved)
                                }
                                .buttonStyle(.plain)
                            }

                            Button(intent: TogglePauseLiveVoiceIntent()) {
                                Label(
                                    phase == .paused ? "Retomar" : "Pausar",
                                    systemImage: phase == .paused ? "play.fill" : "pause.fill"
                                )
                                .font(.system(size: 11, weight: .semibold))
                                .padding(.horizontal, 10)
                                .padding(.vertical, 5)
                                .background(Color.white.opacity(0.12), in: Capsule())
                                .foregroundStyle(BeagleTheme.textPrimary)
                            }
                            .buttonStyle(.plain)

                            Spacer()

                            Button(intent: EndLiveVoiceSessionIntent()) {
                                Label("Encerrar", systemImage: "xmark")
                                    .font(.system(size: 11, weight: .semibold))
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 5)
                                    .background(BeagleTheme.stateError.opacity(0.22), in: Capsule())
                                    .foregroundStyle(BeagleTheme.stateError)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            } compactLeading: {
                Image(systemName: phase.symbolName)
                    .foregroundStyle(tint)
            } compactTrailing: {
                Text(phase.shortBadge)
                    .font(BeagleTheme.dataFont(size: 10, weight: .bold))
                    .foregroundStyle(tint)
            } minimal: {
                Image(systemName: phase.symbolName)
                    .foregroundStyle(tint)
            }
            .widgetURL(URL(string: "beagle://chat"))
        }
    }
}

// MARK: - Live Activity: Companion Turn

struct CompanionTurnActivityConfiguration: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: CompanionTurnAttributes.self) { context in
            // Lock screen / banner — warm, not technical (this IS the companion's voice, not an agent job).
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Image(systemName: context.state.status == "pensando" ? "sparkle" : "checkmark.circle.fill")
                        .foregroundStyle(BeagleTheme.truthObserved)
                    Text(context.attributes.conversationTitle)
                        .font(BeagleTheme.dataFont(size: 12, weight: .medium))
                        .foregroundStyle(BeagleTheme.textPrimary)
                        .lineLimit(1)
                    Spacer()
                    Text(context.state.voiceLabel)
                        .font(BeagleTheme.dataFont(size: 11))
                        .foregroundStyle(BeagleTheme.truthObserved)
                }
                Text(context.state.snippet.isEmpty ? "pensando…" : context.state.snippet)
                    .font(BeagleTheme.dataFont(size: 11))
                    .foregroundStyle(BeagleTheme.textSecondary)
                    .lineLimit(2)
            }
            .padding(12)
            .activityBackgroundTint(BeagleTheme.surface1)
            .activitySystemActionForegroundColor(BeagleTheme.truthObserved)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Image(systemName: context.state.status == "pensando" ? "sparkle" : "checkmark.circle.fill")
                        .foregroundStyle(BeagleTheme.truthObserved)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text(context.state.voiceLabel)
                        .font(BeagleTheme.dataFont(size: 11))
                        .foregroundStyle(BeagleTheme.truthObserved)
                }
                DynamicIslandExpandedRegion(.center) {
                    Text(context.attributes.conversationTitle)
                        .font(BeagleTheme.dataFont(size: 12, weight: .medium))
                        .lineLimit(1)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    Text(context.state.snippet.isEmpty ? "pensando…" : context.state.snippet)
                        .font(BeagleTheme.dataFont(size: 10))
                        .foregroundStyle(BeagleTheme.textSecondary)
                        .lineLimit(2)
                }
            } compactLeading: {
                Image(systemName: context.state.status == "pensando" ? "sparkle" : "checkmark.circle.fill")
            } compactTrailing: {
                Text(context.state.voiceLabel.prefix(4))
                    .font(BeagleTheme.dataFont(size: 10))
            } minimal: {
                Image(systemName: context.state.status == "pensando" ? "sparkle" : "checkmark.circle.fill")
                    .foregroundStyle(BeagleTheme.truthObserved)
            }
        }
    }
}
#endif
