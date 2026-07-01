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
    private var cognitiveActivity: Activity<CognitiveActivityAttributes>?
    private var companionActivity: Activity<CompanionTurnAttributes>?

    // MARK: - Companion Turn (chat "pensando" → "respondeu")

    public func startCompanionTurn(conversationTitle: String, voiceLabel: String) {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        // One turn at a time — a fresh message ends any activity still lingering from a prior turn.
        if companionActivity != nil { endCompanionTurn(finalSnippet: nil) }

        let attributes = CompanionTurnAttributes(conversationTitle: conversationTitle)
        let initialState = CompanionTurnAttributes.ContentState(status: "pensando", voiceLabel: voiceLabel)
        do {
            companionActivity = try Activity.request(
                attributes: attributes,
                content: .init(state: initialState, staleDate: Date.now.addingTimeInterval(120))
            )
        } catch {
            print("[LiveActivity] companion turn start failed: \(error)")
        }
    }

    public func endCompanionTurn(finalSnippet: String?) {
        guard let act = companionActivity else { return }
        let finalState = CompanionTurnAttributes.ContentState(
            status: finalSnippet != nil ? "respondeu" : "sem resposta",
            voiceLabel: act.content.state.voiceLabel,
            snippet: finalSnippet.map { String($0.prefix(120)) } ?? ""
        )
        let content = ActivityContent(state: finalState, staleDate: nil)
        nonisolated(unsafe) let unsafeAct = act
        Task { await unsafeAct.end(content, dismissalPolicy: .after(.now + 20)) }
        companionActivity = nil
    }

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

    // MARK: - Cognitive State (HRV + Agent Posture)

    public func startCognitiveActivity(
        posture: CognitivePosture,
        agentCount: Int,
        jobCount: Int
    ) {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }

        // End any existing cognitive activity before starting a new one
        if cognitiveActivity != nil {
            endCognitiveActivity()
        }

        let attributes = CognitiveActivityAttributes()
        let initialState = CognitiveActivityAttributes.ContentState(
            readiness: posture.readiness,
            intensity: posture.suggestedIntensity.rawValue,
            hrvMs: posture.hrv,
            agentCount: agentCount,
            activeJobCount: jobCount,
            lastThoughtSnippet: nil
        )

        do {
            cognitiveActivity = try Activity.request(
                attributes: attributes,
                content: .init(state: initialState, staleDate: Date.now.addingTimeInterval(600))
            )
        } catch {
            print("[LiveActivity] cognitive start failed: \(error)")
        }
    }

    public func updateCognitiveActivity(
        posture: CognitivePosture,
        agentCount: Int,
        jobCount: Int,
        lastThought: String? = nil
    ) {
        guard let act = cognitiveActivity else { return }
        let newState = CognitiveActivityAttributes.ContentState(
            readiness: posture.readiness,
            intensity: posture.suggestedIntensity.rawValue,
            hrvMs: posture.hrv,
            agentCount: agentCount,
            activeJobCount: jobCount,
            lastThoughtSnippet: lastThought.map { String($0.suffix(100)) }
        )
        let content = ActivityContent(state: newState, staleDate: Date.now.addingTimeInterval(600))
        nonisolated(unsafe) let unsafeAct = act
        Task { await unsafeAct.update(content) }
    }

    public func endCognitiveActivity() {
        guard let act = cognitiveActivity else { return }
        let finalState = CognitiveActivityAttributes.ContentState(
            readiness: nil,
            intensity: "normal",
            hrvMs: nil,
            agentCount: 0,
            activeJobCount: 0,
            lastThoughtSnippet: nil
        )
        let content = ActivityContent(state: finalState, staleDate: nil)
        nonisolated(unsafe) let unsafeAct = act
        Task { await unsafeAct.end(content, dismissalPolicy: .after(.now + 120)) }
        cognitiveActivity = nil
    }

    public var isCognitiveActivityRunning: Bool {
        cognitiveActivity != nil
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
    public func startResearchActivity(runId: String, campaign: String, slug: String) {}
    public func updateResearchActivity(step: Int, total: Int, eta: Int) {}
    public func endResearchActivity() {}
    public func startCognitiveActivity(posture: CognitivePosture, agentCount: Int, jobCount: Int) {}
    public func updateCognitiveActivity(posture: CognitivePosture, agentCount: Int, jobCount: Int, lastThought: String? = nil) {}
    public func endCognitiveActivity() {}
    public var isCognitiveActivityRunning: Bool { false }
    public func startCompanionTurn(conversationTitle: String, voiceLabel: String) {}
    public func endCompanionTurn(finalSnippet: String?) {}
}
#endif
