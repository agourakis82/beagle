//
//  LiveActivityManager.swift
//  BeagleCockpit
//
//  Manages Live Activity lifecycle for agent sessions, research runs,
//  cognitive posture, and continuous companion voice sessions.
//
//  Cluster-driven delivery (`agent` & `research`):
//    - Requests ActivityKit update tokens (`pushType: .token`) with graceful
//      local fallback (`pushType: nil`) on Simulator or unprovisioned builds.
//    - Observes initial `pushToken`, `pushTokenUpdates`, and `activityStateUpdates`.
//    - Restores active `Activity<...>.activities` associations across app relaunch
//      and revokes ended/dismissed activities idempotently.
//    - Yields foreground local writes once `remoteDeliveryActive == true` is
//      acknowledged by `project-cockpit` to avoid competing writers.
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
    private var voiceSessionActivity: Activity<CompanionVoiceSessionAttributes>?

    private var clusterObserverTasks: [String: [Task<Void, Never>]] = [:]
    private var hasRestoredClusterActivities = false

    public var isVoiceSessionActive: Bool {
        voiceSessionActivity != nil
    }

    // MARK: - Relaunch Restoration & Cluster Token Observation

    /// Re-bind `Activity<AgentSessionAttributes>.activities` and
    /// `Activity<ResearchRunAttributes>.activities` after launch so token rotations,
    /// dismissals, and remote writer handoffs survive app termination.
    public func restoreClusterActivitiesAfterLaunch() async {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        hasRestoredClusterActivities = true

        var survivingIds = Set<String>()

        for act in Activity<AgentSessionAttributes>.activities {
            let state = act.activityState
            if state == .ended || state == .dismissed {
                cancelObserverTasks(for: act.id)
                await LiveActivityClusterCoordinator.shared.revoke(
                    activityId: act.id,
                    reason: state == .dismissed ? "dismissed" : "ended"
                )
                continue
            }
            survivingIds.insert(act.id)
            if agentActivity == nil {
                agentActivity = act
            }
            observeClusterActivity(
                act,
                kind: .agent,
                canonicalId: act.attributes.sessionId,
                agentKind: act.attributes.agentKind,
                projectSlug: act.attributes.projectSlug
            )
        }

        for act in Activity<ResearchRunAttributes>.activities {
            let state = act.activityState
            if state == .ended || state == .dismissed {
                cancelObserverTasks(for: act.id)
                await LiveActivityClusterCoordinator.shared.revoke(
                    activityId: act.id,
                    reason: state == .dismissed ? "dismissed" : "ended"
                )
                continue
            }
            survivingIds.insert(act.id)
            if researchActivity == nil {
                researchActivity = act
            }
            observeClusterActivity(
                act,
                kind: .research,
                canonicalId: act.attributes.runId,
                agentKind: nil,
                projectSlug: act.attributes.projectSlug
            )
        }

        await LiveActivityClusterCoordinator.shared.reconcileSurvivingActivities(activeIds: survivingIds)
    }

    private func cancelObserverTasks(for activityId: String) {
        if let tasks = clusterObserverTasks.removeValue(forKey: activityId) {
            for task in tasks {
                task.cancel()
            }
        }
    }

    private func observeClusterActivity<Attributes: ActivityAttributes>(
        _ act: Activity<Attributes>,
        kind: LiveActivityClusterKind,
        canonicalId: String,
        agentKind: String?,
        projectSlug: String
    ) {
        let activityId = act.id
        cancelObserverTasks(for: activityId)

        LiveActivityClusterCoordinator.shared.trackActivity(
            activityId: activityId,
            kind: kind,
            canonicalId: canonicalId,
            agentKind: agentKind,
            projectSlug: projectSlug
        )

        var tasks: [Task<Void, Never>] = []

        if let initialToken = act.pushToken {
            let initialTask = Task { @MainActor in
                _ = await LiveActivityClusterCoordinator.shared.submitPushTokenData(
                    initialToken,
                    activityId: activityId,
                    kind: kind,
                    canonicalId: canonicalId,
                    agentKind: agentKind,
                    projectSlug: projectSlug
                )
            }
            tasks.append(initialTask)
        }

        nonisolated(unsafe) let unsafeAct = act

        let tokenUpdatesTask = Task.detached {
            for await tokenData in unsafeAct.pushTokenUpdates {
                if Task.isCancelled { break }
                await MainActor.run {
                    Task { @MainActor in
                        _ = await LiveActivityClusterCoordinator.shared.submitPushTokenData(
                            tokenData,
                            activityId: activityId,
                            kind: kind,
                            canonicalId: canonicalId,
                            agentKind: agentKind,
                            projectSlug: projectSlug
                        )
                    }
                }
            }
        }
        tasks.append(tokenUpdatesTask)

        let stateUpdatesTask = Task.detached { [weak self] in
            for await state in unsafeAct.activityStateUpdates {
                if Task.isCancelled { break }
                if state == .ended || state == .dismissed {
                    let reason = state == .dismissed ? "dismissed" : "ended"
                    await MainActor.run {
                        guard let self else { return }
                        if self.agentActivity?.id == activityId {
                            self.agentActivity = nil
                        }
                        if self.researchActivity?.id == activityId {
                            self.researchActivity = nil
                        }
                        self.cancelObserverTasks(for: activityId)
                        Task { @MainActor in
                            await LiveActivityClusterCoordinator.shared.revoke(
                                activityId: activityId,
                                reason: reason
                            )
                        }
                    }
                    break
                }
            }
        }
        tasks.append(stateUpdatesTask)

        clusterObserverTasks[activityId] = tasks
    }

    // MARK: - Sessão de Voz Contínua Mãos-Livres (Walkie-Talkie + Dynamic Island)

    public func startVoiceSession(conversationTitle: String, voiceLabel: String) {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        if companionActivity != nil { endCompanionTurn(finalSnippet: nil) }

        // Limpa sessões órfãs anteriores para nunca disputar a Dynamic Island
        for orphan in Activity<CompanionVoiceSessionAttributes>.activities {
            let endedState = CompanionVoiceSessionAttributes.ContentState(
                phase: .ended,
                voiceLabel: orphan.content.state.voiceLabel,
                turnCount: orphan.content.state.turnCount,
                liveLine: CompanionLiveVoicePhase.ended.defaultLinePtBR
            )
            let content = ActivityContent(state: endedState, staleDate: nil)
            nonisolated(unsafe) let unsafeOrphan = orphan
            Task { await unsafeOrphan.end(content, dismissalPolicy: .immediate) }
        }
        voiceSessionActivity = nil

        let attributes = CompanionVoiceSessionAttributes(
            conversationTitle: conversationTitle,
            startedAt: .now
        )
        let initialState = CompanionVoiceSessionAttributes.ContentState(
            phase: .listening,
            voiceLabel: voiceLabel,
            turnCount: 0,
            liveLine: CompanionLiveVoicePhase.listening.defaultLinePtBR
        )

        do {
            voiceSessionActivity = try Activity.request(
                attributes: attributes,
                content: .init(state: initialState, staleDate: Date.now.addingTimeInterval(900)),
                pushType: nil
            )
        } catch {
            print("[LiveActivity] continuous voice session start failed: \(error)")
        }
    }

    public func updateVoiceSession(state: CompanionLiveVoiceSessionState) {
        guard let act = voiceSessionActivity else { return }
        let newState = CompanionVoiceSessionAttributes.ContentState(
            phase: state.phase,
            voiceLabel: state.voiceLabel,
            turnCount: state.turnCount,
            liveLine: state.liveLine
        )
        let content = ActivityContent(state: newState, staleDate: Date.now.addingTimeInterval(900))
        nonisolated(unsafe) let unsafeAct = act
        Task { await unsafeAct.update(content) }
    }

    public func endVoiceSession(turnCount: Int = 0, voiceLabel: String = "MoE") {
        let activeList = Activity<CompanionVoiceSessionAttributes>.activities
        if let act = voiceSessionActivity {
            let finalState = CompanionVoiceSessionAttributes.ContentState(
                phase: .ended,
                voiceLabel: act.content.state.voiceLabel,
                turnCount: max(turnCount, act.content.state.turnCount),
                liveLine: CompanionLiveVoicePhase.ended.defaultLinePtBR
            )
            let content = ActivityContent(state: finalState, staleDate: nil)
            nonisolated(unsafe) let unsafeAct = act
            Task { await unsafeAct.end(content, dismissalPolicy: .immediate) }
            voiceSessionActivity = nil
        } else {
            for orphan in activeList {
                let finalState = CompanionVoiceSessionAttributes.ContentState(
                    phase: .ended,
                    voiceLabel: voiceLabel,
                    turnCount: turnCount,
                    liveLine: CompanionLiveVoicePhase.ended.defaultLinePtBR
                )
                let content = ActivityContent(state: finalState, staleDate: nil)
                nonisolated(unsafe) let unsafeOrphan = orphan
                Task { await unsafeOrphan.end(content, dismissalPolicy: .immediate) }
            }
        }
    }

    // MARK: - Companion Turn (chat "pensando" → "respondeu")

    public func startCompanionTurn(conversationTitle: String, voiceLabel: String) {
        // Quando a sessão contínua Walkie-Talkie está ativa, ela é dona única da Dynamic Island.
        guard voiceSessionActivity == nil else { return }
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        // One turn at a time — a fresh message ends any activity still lingering from a prior turn.
        if companionActivity != nil { endCompanionTurn(finalSnippet: nil) }

        let attributes = CompanionTurnAttributes(conversationTitle: conversationTitle)
        let initialState = CompanionTurnAttributes.ContentState(status: "pensando", voiceLabel: voiceLabel)
        do {
            companionActivity = try Activity.request(
                attributes: attributes,
                content: .init(state: initialState, staleDate: Date.now.addingTimeInterval(120)),
                pushType: nil
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

    // MARK: - Agent Session (Cluster-Driven APNs + Foreground Fallback)

    public func startAgentActivity(slug: String, kind: String, sessionId: String) {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }

        if let existing = agentActivity {
            if existing.attributes.sessionId == sessionId && existing.activityState == .active {
                observeClusterActivity(
                    existing,
                    kind: .agent,
                    canonicalId: sessionId,
                    agentKind: kind,
                    projectSlug: slug
                )
                return
            }
            endAgentActivity(finalStatus: "stopped")
        }

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
        let initialContent = ActivityContent(
            state: initialState,
            staleDate: Date.now.addingTimeInterval(300)
        )

        do {
            let requested: Activity<AgentSessionAttributes>
            do {
                requested = try Activity.request(
                    attributes: attributes,
                    content: initialContent,
                    pushType: .token
                )
            } catch {
                requested = try Activity.request(
                    attributes: attributes,
                    content: initialContent,
                    pushType: nil
                )
            }
            agentActivity = requested
            observeClusterActivity(
                requested,
                kind: .agent,
                canonicalId: sessionId,
                agentKind: kind,
                projectSlug: slug
            )
        } catch {
            print("[LiveActivity] agent start failed: \(error)")
        }
    }

    public func updateAgentActivity(status: String, tokens: Int, snippet: String) {
        guard let act = agentActivity else { return }
        guard LiveActivityClusterCoordinator.shared.shouldWriteLocally(activityId: act.id) else {
            return
        }
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
        let activityId = act.id
        cancelObserverTasks(for: activityId)
        let finalState = AgentSessionAttributes.ContentState(
            status: finalStatus,
            tokensUsed: act.content.state.tokensUsed,
            lastOutputSnippet: ""
        )
        let content = ActivityContent(state: finalState, staleDate: nil)
        nonisolated(unsafe) let unsafeAct = act
        Task {
            await unsafeAct.end(content, dismissalPolicy: .after(.now + 300))
            await LiveActivityClusterCoordinator.shared.revoke(activityId: activityId, reason: "ended")
        }
        agentActivity = nil
    }

    // MARK: - Research Run (Cluster-Driven APNs + Foreground Fallback)

    public func startResearchActivity(
        runId: String,
        campaign: String,
        slug: String,
        totalSteps: Int = 1,
        activeLens: String? = nil
    ) {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }

        if let existing = researchActivity {
            if existing.attributes.runId == runId && existing.activityState == .active {
                observeClusterActivity(
                    existing,
                    kind: .research,
                    canonicalId: runId,
                    agentKind: nil,
                    projectSlug: slug
                )
                return
            }
            endResearchActivity()
        }

        let attributes = ResearchRunAttributes(
            runId: runId,
            campaignName: campaign,
            projectSlug: slug
        )
        let initialState = ResearchRunAttributes.ContentState(
            stepCurrent: 0,
            stepTotal: max(1, totalSteps),
            etaSeconds: max(15, totalSteps * 15),
            activeLens: activeLens,
            summarySnippet: nil,
            isCompleted: false
        )
        let initialContent = ActivityContent(
            state: initialState,
            staleDate: Date.now.addingTimeInterval(600)
        )

        do {
            let requested: Activity<ResearchRunAttributes>
            do {
                requested = try Activity.request(
                    attributes: attributes,
                    content: initialContent,
                    pushType: .token
                )
            } catch {
                requested = try Activity.request(
                    attributes: attributes,
                    content: initialContent,
                    pushType: nil
                )
            }
            researchActivity = requested
            observeClusterActivity(
                requested,
                kind: .research,
                canonicalId: runId,
                agentKind: nil,
                projectSlug: slug
            )
            Task {
                await ResearchRunSearchIndex.donate(
                    runId: runId,
                    campaignName: campaign,
                    projectSlug: slug,
                    status: "running"
                )
            }
        } catch {
            print("[LiveActivity] research start failed: \(error)")
        }
    }

    public func updateResearchActivity(
        step: Int,
        total: Int,
        eta: Int,
        activeLens: String? = nil,
        summarySnippet: String? = nil
    ) {
        guard let act = researchActivity else { return }
        guard LiveActivityClusterCoordinator.shared.shouldWriteLocally(activityId: act.id) else {
            return
        }
        let newState = ResearchRunAttributes.ContentState(
            stepCurrent: step,
            stepTotal: max(1, total),
            etaSeconds: eta,
            activeLens: activeLens ?? act.content.state.activeLens,
            summarySnippet: summarySnippet.map { String($0.prefix(160)) } ?? act.content.state.summarySnippet,
            isCompleted: false
        )
        let content = ActivityContent(state: newState, staleDate: Date.now.addingTimeInterval(600))
        nonisolated(unsafe) let unsafeAct = act
        Task { await unsafeAct.update(content) }
    }

    public func endResearchActivity(finalSummary: String? = nil) {
        guard let act = researchActivity else { return }
        let activityId = act.id
        cancelObserverTasks(for: activityId)
        let finalTotal = max(1, act.content.state.stepTotal)
        let snippet = finalSummary.map { String($0.prefix(160)) } ?? act.content.state.summarySnippet
        let finalState = ResearchRunAttributes.ContentState(
            stepCurrent: finalTotal,
            stepTotal: finalTotal,
            etaSeconds: 0,
            activeLens: "Concluído",
            summarySnippet: snippet,
            isCompleted: true
        )
        let content = ActivityContent(state: finalState, staleDate: nil)
        nonisolated(unsafe) let unsafeAct = act
        Task {
            await unsafeAct.end(content, dismissalPolicy: .after(.now + 300))
            await LiveActivityClusterCoordinator.shared.revoke(activityId: activityId, reason: "ended")
        }
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
                content: .init(state: initialState, staleDate: Date.now.addingTimeInterval(600)),
                pushType: nil
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
    public func restoreClusterActivitiesAfterLaunch() async {}
    public func startAgentActivity(slug: String, kind: String, sessionId: String) {}
    public func updateAgentActivity(status: String, tokens: Int, snippet: String) {}
    public func endAgentActivity(finalStatus: String) {}
    public func startResearchActivity(runId: String, campaign: String, slug: String, totalSteps: Int = 1, activeLens: String? = nil) {}
    public func updateResearchActivity(step: Int, total: Int, eta: Int, activeLens: String? = nil, summarySnippet: String? = nil) {}
    public func endResearchActivity(finalSummary: String? = nil) {}
    public func startCognitiveActivity(posture: CognitivePosture, agentCount: Int, jobCount: Int) {}
    public func updateCognitiveActivity(posture: CognitivePosture, agentCount: Int, jobCount: Int, lastThought: String? = nil) {}
    public func endCognitiveActivity() {}
    public var isCognitiveActivityRunning: Bool { false }
    public var isVoiceSessionActive: Bool { false }
    public func startVoiceSession(conversationTitle: String, voiceLabel: String) {}
    public func updateVoiceSession(state: CompanionLiveVoiceSessionState) {}
    public func endVoiceSession(turnCount: Int = 0, voiceLabel: String = "MoE") {}
    public func startCompanionTurn(conversationTitle: String, voiceLabel: String) {}
    public func endCompanionTurn(finalSnippet: String?) {}
}
#endif
