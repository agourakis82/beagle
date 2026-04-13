//
//  LiveActivityManager.swift
//  BeagleCockpit
//
//  Manages Live Activity lifecycle for agent sessions and research runs.
//  Shows persistent status on lock screen + Dynamic Island.
//

import Foundation
import BeagleCore

#if os(iOS)
import ActivityKit

@MainActor
public final class LiveActivityManager {
    public static let shared = LiveActivityManager()
    private init() {}

    private var agentActivity: Activity<AgentSessionAttributes>?
    private var researchActivity: Activity<ResearchRunAttributes>?

    // MARK: - Agent Session

    public func startAgentActivity(slug: String, kind: String, sessionId: String) {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }

        let attributes = AgentSessionAttributes(
            agentKind: kind,
            projectSlug: slug,
            sessionId: sessionId
        )
        let initialState = AgentSessionAttributes.ContentState(
            status: "running",
            tokensUsed: 0,
            lastOutputSnippet: "Session starting..."
        )

        do {
            agentActivity = try Activity.request(
                attributes: attributes,
                content: .init(state: initialState, staleDate: Date.now.addingTimeInterval(300))
            )
        } catch {
            print("[LiveActivity] agent start failed: \(error)")
        }
    }

    public func updateAgentActivity(status: String, tokens: Int, snippet: String) {
        guard let act = agentActivity else { return }
        let newState = AgentSessionAttributes.ContentState(
            status: status,
            tokensUsed: tokens,
            lastOutputSnippet: String(snippet.suffix(80))
        )
        let content = ActivityContent(state: newState, staleDate: Date.now.addingTimeInterval(300))
        nonisolated(unsafe) let unsafeAct = act
        Task { await unsafeAct.update(content) }
    }

    public func endAgentActivity(finalStatus: String) {
        guard let act = agentActivity else { return }
        let finalState = AgentSessionAttributes.ContentState(
            status: finalStatus,
            tokensUsed: 0,
            lastOutputSnippet: ""
        )
        let content = ActivityContent(state: finalState, staleDate: nil)
        nonisolated(unsafe) let unsafeAct = act
        Task { await unsafeAct.end(content, dismissalPolicy: .after(.now + 300)) }
        agentActivity = nil
    }

    // MARK: - Research Run

    public func startResearchActivity(runId: String, campaign: String, slug: String) {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }

        let attributes = ResearchRunAttributes(
            runId: runId,
            campaignName: campaign,
            projectSlug: slug
        )
        let initialState = ResearchRunAttributes.ContentState(
            stepCurrent: 0,
            stepTotal: 1,
            etaSeconds: 0
        )

        do {
            researchActivity = try Activity.request(
                attributes: attributes,
                content: .init(state: initialState, staleDate: Date.now.addingTimeInterval(600))
            )
        } catch {
            print("[LiveActivity] research start failed: \(error)")
        }
    }

    public func updateResearchActivity(step: Int, total: Int, eta: Int) {
        guard let act = researchActivity else { return }
        let newState = ResearchRunAttributes.ContentState(
            stepCurrent: step,
            stepTotal: total,
            etaSeconds: eta
        )
        let content = ActivityContent(state: newState, staleDate: Date.now.addingTimeInterval(600))
        nonisolated(unsafe) let unsafeAct = act
        Task { await unsafeAct.update(content) }
    }

    public func endResearchActivity() {
        guard let act = researchActivity else { return }
        let finalState = ResearchRunAttributes.ContentState(stepCurrent: 1, stepTotal: 1, etaSeconds: 0)
        let content = ActivityContent(state: finalState, staleDate: nil)
        nonisolated(unsafe) let unsafeAct = act
        Task { await unsafeAct.end(content, dismissalPolicy: .after(.now + 300)) }
        researchActivity = nil
    }
}

#else
@MainActor
public final class LiveActivityManager {
    public static let shared = LiveActivityManager()
    private init() {}
    public func startAgentActivity(slug: String, kind: String, sessionId: String) {}
    public func updateAgentActivity(status: String, tokens: Int, snippet: String) {}
    public func endAgentActivity(finalStatus: String) {}
}
#endif
