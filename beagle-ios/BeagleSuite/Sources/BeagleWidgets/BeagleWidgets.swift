//
//  BeagleWidgets.swift
//  BeagleWidgets
//
//  WidgetKit + ActivityKit entry point for home screen / lock screen / Dynamic Island.
//
//  Widgets:
//   - MorningBriefingWidget (MorningBriefingWidget.swift)
//   - ClusterHealthWidget, PostureOverviewWidget, LatestResearchWidget (ClusterWidgets.swift)
//   - FlowStateWidget, ThoughtCaptureWidget, CompanionVoiceLauncherWidget (FlowAndQuickActionWidgets.swift)
//   - BeagleVoiceControlWidget, BeagleMorningControlWidget, BeagleModoFundoControlWidget (FlowAndQuickActionWidgets.swift)
//
//  Live Activities (iOS only):
//   - CompanionVoiceSessionActivityConfiguration, CompanionTurnActivityConfiguration (CompanionLiveActivities.swift)
//   - AgentSessionActivityConfiguration, ResearchRunActivityConfiguration, CognitiveActivityConfiguration (AgentAndCognitiveLiveActivities.swift)
//

import WidgetKit
import SwiftUI

// MARK: - Widget Bundle entry

@main
struct BeagleWidgetsBundle: WidgetBundle {
    var body: some Widget {
        MorningBriefingWidget()
        ClusterHealthWidget()
        PostureOverviewWidget()
        LatestResearchWidget()
        FlowStateWidget()
        ThoughtCaptureWidget()
        CompanionVoiceLauncherWidget()

        // Control Center & Lock Screen Controls + Live Activities (iOS only)
        #if os(iOS)
        BeagleVoiceControlWidget()
        BeagleMorningControlWidget()
        BeagleModoFundoControlWidget()
        CompanionVoiceSessionActivityConfiguration()
        CompanionTurnActivityConfiguration()
        AgentSessionActivityConfiguration()
        ResearchRunActivityConfiguration()
        CognitiveActivityConfiguration()
        #endif
    }
}
