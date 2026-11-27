//
//  CockpitClient+Projects.swift
//  BeagleCore
//
//  Project catalog, overview, cluster/HPC, memory, git, execution workflows,
//  session heartbeats/ideas/delegations, vision, companion telemetry, and scratchpad routes.
//

import Foundation

extension CockpitClient {

    // MARK: - Catalog & Project Overview

    public func catalog() async -> Truthful<ExecutiveCatalog> {
        let mobile = await fetchMobile(ExecutiveCatalog.self, path: "/api/mobile/v1/catalog")
        if mobile.value != nil { return mobile }
        return await fetch(ExecutiveCatalog.self, path: "/api/catalog/executive")
    }

    public func mobileSummary() async -> Truthful<MobileHomeSummary> {
        await fetchMobile(MobileHomeSummary.self, path: "/api/mobile/v1/summary")
    }

    public func projectOverview(slug: String, depth: String = "fast") async -> Truthful<MobileProjectOverview> {
        await fetchMobile(
            MobileProjectOverview.self,
            path: "/api/mobile/v1/projects/\(Self.seg(slug))/overview?depth=\(Self.seg(depth))"
        )
    }

    public func posturePolicy() async -> Truthful<PosturePolicy> {
        await fetch(PosturePolicy.self, path: "/api/catalog/project-posture-policy")
    }

    public func missionControl(slug: String) async -> Truthful<MissionControl> {
        let s = Self.seg(slug)
        let overview = await fetchMobile(MobileProjectOverview.self, path: "/api/mobile/v1/projects/\(s)/overview")
        if let projected = overview.compactMap(\.missionControl) { return projected }
        return await fetch(MissionControl.self, path: "/api/projects/\(s)/mission-control")
    }

    public func clusterLaneTruth(slug: String) async -> Truthful<ClusterLaneTruth> {
        let s = Self.seg(slug)
        let overview = await fetchMobile(MobileProjectOverview.self, path: "/api/mobile/v1/projects/\(s)/overview")
        if let projected = overview.compactMap(\.clusterLaneTruth) { return projected }
        return await fetch(ClusterLaneTruth.self, path: "/api/projects/\(s)/cluster/lane-truth")
    }

    public func researchOperations(slug: String) async -> Truthful<ResearchOperations> {
        let s = Self.seg(slug)
        let overview = await fetchMobile(MobileProjectOverview.self, path: "/api/mobile/v1/projects/\(s)/overview")
        if let projected = overview.compactMap(\.researchOperations) { return projected }
        return await fetch(ResearchOperations.self, path: "/api/projects/\(s)/research/operations")
    }

    public func inferenceRuntime(slug: String) async -> Truthful<InferenceRuntime> {
        let s = Self.seg(slug)
        let overview = await fetchMobile(MobileProjectOverview.self, path: "/api/mobile/v1/projects/\(s)/overview")
        if let projected = overview.compactMap(\.inferenceRuntime) { return projected }
        let wrapped = await fetch(InferenceRuntimeResponse.self, path: "/api/projects/\(s)/inference/runtime")
        // Unwrap nested runtime object
        if let projected = wrapped.compactMap(\.runtime) { return projected }
        return .staleError(wrapped.error ?? "no runtime payload", source: wrapped.source)
    }

    public func viewerRuntime(slug: String) async -> Truthful<ViewerRuntimeResponse> {
        let s = Self.seg(slug)
        let overview = await fetchMobile(MobileProjectOverview.self, path: "/api/mobile/v1/projects/\(s)/overview")
        if let projected = overview.compactMap(\.viewerRuntime) { return projected }
        return await fetch(ViewerRuntimeResponse.self, path: "/api/projects/\(s)/viewer/runtime")
    }

    // MARK: - Habitat Actions

    public func executeAction(slug: String, actionId: String) async -> Truthful<ActionResponse> {
        let s = Self.seg(slug)
        let a = Self.seg(actionId)
        let mobile = await postMobile(ActionResponse.self, path: "/api/mobile/v1/projects/\(s)/actions/\(a)", body: [
            "confirmed": true
        ])
        if mobile.value != nil { return mobile }
        return await post(ActionResponse.self, path: "/api/projects/\(s)/go-work-now/actions/\(a)", body: [
            "confirm": true
        ])
    }

    // MARK: - Cluster & HPC

    public func clusterSummary(slug: String) async -> Truthful<ClusterSummary> {
        await fetch(ClusterSummary.self, path: "/api/projects/\(Self.seg(slug))/cluster/summary")
    }

    public func hpcJobQueue() async -> Truthful<HPCJobQueue> {
        await fetch(HPCJobQueue.self, path: "/api/jobs/queue")
    }

    public func goWorkNow(slug: String) async -> Truthful<GoWorkNow> {
        await fetch(GoWorkNow.self, path: "/api/projects/\(Self.seg(slug))/go-work-now")
    }

    // MARK: - Project Memory

    public func fastMemory(slug: String) async -> Truthful<ProjectMemory> {
        await fetch(ProjectMemory.self, path: "/api/projects/\(Self.seg(slug))/memory/fast")
    }

    public func deepMemory(slug: String) async -> Truthful<ProjectMemory> {
        await fetch(ProjectMemory.self, path: "/api/projects/\(Self.seg(slug))/memory/deep", timeout: 15)
    }

    // MARK: - Sovereign Surface

    public func sovereignSurface(slug: String) async -> Truthful<SovereignSurface> {
        await fetch(SovereignSurface.self, path: "/api/projects/\(Self.seg(slug))/sovereign-surface")
    }

    public func truthSummary(slug: String) async -> Truthful<ProjectTruthSummary> {
        await fetch(ProjectTruthSummary.self, path: "/api/projects/\(Self.seg(slug))/truth/summary")
    }

    // MARK: - Git Operations

    public func gitStatus(slug: String) async -> Truthful<GitStatusResponse> {
        await fetch(GitStatusResponse.self, path: "/api/projects/\(Self.seg(slug))/git/status")
    }

    public func gitDiff(slug: String) async -> Truthful<GitDiffResponse> {
        await fetch(GitDiffResponse.self, path: "/api/projects/\(Self.seg(slug))/git/diff")
    }

    // MARK: - Execution & Workflows

    public func executionPackets(slug: String) async -> Truthful<ExecutionPacketsResponse> {
        await fetch(ExecutionPacketsResponse.self, path: "/api/projects/\(Self.seg(slug))/execution/packets")
    }

    public func scientificWorkflows(slug: String) async -> Truthful<ScientificWorkflowsResponse> {
        await fetch(ScientificWorkflowsResponse.self, path: "/api/projects/\(Self.seg(slug))/workflows/scientific")
    }

    public func datasetCatalog(slug: String) async -> Truthful<DatasetCatalogResponse> {
        await fetch(DatasetCatalogResponse.self, path: "/api/projects/\(Self.seg(slug))/datasets/catalog")
    }

    // MARK: - Session

    public func sessionHeartbeat(
        slug: String,
        clientSessionId: String,
        projectFamily: ProjectFamily? = nil,
        publicationScope: PublicationScope? = nil
    ) async -> Truthful<SessionHeartbeatResponse> {
        let s = Self.seg(slug)
        let family = derivedProjectFamily(slug: slug, override: projectFamily)
        let scope = derivedPublicationScope(
            slug: slug,
            projectFamily: family,
            override: publicationScope
        )
        let mobile = await postMobile(SessionHeartbeatResponse.self, path: "/api/mobile/v1/projects/\(s)/heartbeat", body: [
            "clientSessionId": clientSessionId,
            "projectFamily": family.rawValue,
            "publicationScope": scope.rawValue,
            "confirmed": true
        ])
        if mobile.value != nil { return mobile }
        return await post(SessionHeartbeatResponse.self, path: "/api/projects/\(s)/session/heartbeat", body: [
            "clientSessionId": clientSessionId,
            "projectFamily": family.rawValue,
            "publicationScope": scope.rawValue
        ])
    }

    public func saveIdea(
        slug: String,
        text: String,
        source: String,
        refinedText: String? = nil,
        projectFamily: ProjectFamily? = nil,
        publicationScope: PublicationScope? = nil
    ) async -> Truthful<IdeaSaveResponse> {
        let family = derivedProjectFamily(slug: slug, override: projectFamily)
        let scope = derivedPublicationScope(
            slug: slug,
            projectFamily: family,
            override: publicationScope
        )
        var body: [String: any Sendable] = [
            "text": text,
            "rawText": text,
            "raw_text": text,
            "source": source,
            "projectFamily": family.rawValue,
            "publicationScope": scope.rawValue
        ]
        if let refinedText, !refinedText.isEmpty {
            body["refinedText"] = refinedText
            body["refined_text"] = refinedText
        }
        return await postMobile(
            IdeaSaveResponse.self,
            path: "/api/mobile/v1/projects/\(Self.seg(slug))/ideas",
            body: body
        )
    }

    public func delegate(
        slug: String,
        text: String,
        agentKind: String? = nil,
        source: String = "ios",
        projectFamily: ProjectFamily? = nil,
        publicationScope: PublicationScope? = nil
    ) async -> Truthful<DelegationResponse> {
        let family = derivedProjectFamily(slug: slug, override: projectFamily)
        let scope = derivedPublicationScope(
            slug: slug,
            projectFamily: family,
            override: publicationScope
        )
        var body: [String: any Sendable] = [
            "text": text,
            "prompt": text,
            "source": source,
            "projectFamily": family.rawValue,
            "publicationScope": scope.rawValue
        ]
        if let agentKind, !agentKind.isEmpty {
            body["agentKind"] = agentKind
            body["agent_kind"] = agentKind
        }
        return await postMobile(
            DelegationResponse.self,
            path: "/api/mobile/v1/projects/\(Self.seg(slug))/delegations",
            body: body
        )
    }

    // MARK: - Vision (public endpoints)

    public func appleBrief() async -> Truthful<AppleBriefResponse> {
        await fetch(AppleBriefResponse.self, path: "/api/public/vision/apple-brief")
    }

    public func controlRoomVision() async -> Truthful<ControlRoomVisionResponse> {
        await fetch(ControlRoomVisionResponse.self, path: "/api/public/vision/control-room")
    }

    // MARK: - Mobile Companion & Telemetry Routes

    /// Recent sky + ambient + HRV series for the Agora detail screen's trends.
    public func agoraHistory(hours: Int = 48) async -> Truthful<AgoraHistory> {
        await fetch(AgoraHistory.self, path: "/api/mobile/v1/agora-history?hours=\(hours)", timeout: 20)
    }

    /// Body × sky × ambient correlations (Spearman + lag scan) proxied through the cockpit.
    public func correlations(days: Int = 30) async -> Truthful<PhysioCorrelations> {
        await fetch(PhysioCorrelations.self, path: "/api/mobile/v1/correlations?days=\(days)", timeout: 20)
    }

    /// Flush one queued offline companion turn to the cockpit's memory-spine ingest endpoint.
    public func ingestTurn(_ request: IngestTurnRequest) async -> Truthful<IngestTurnResult> {
        let mobile = await postMobileEncoded(
            IngestTurnResult.self,
            path: "/api/mobile/v1/ingest",
            body: request,
            timeout: 30
        )
        if mobile.value != nil { return mobile }
        return await postEncoded(
            IngestTurnResult.self,
            path: "/api/mobile/v1/ingest",
            body: request,
            timeout: 30
        )
    }

    // MARK: - Agent Scratchpad (inter-agent communication)

    public func agentScratchpad(slug: String) async -> Truthful<ScratchpadResponse> {
        await fetch(ScratchpadResponse.self, path: "/api/projects/\(Self.seg(slug))/agents/scratchpad")
    }

    public func postAgentMessage(slug: String, agent: String, text: String, consciousnessState: ConsciousnessState? = nil) async -> Truthful<AgentMessageAck> {
        var body: [String: any Sendable] = [
            "author": agent,
            "text": text
        ]
        if let cs = consciousnessState {
            var csDict: [String: any Sendable] = [:]
            if let hrv = cs.hrvMs { csDict["hrv_ms"] = hrv }
            if let r = cs.readiness { csDict["readiness"] = r }
            if let i = cs.intensity { csDict["intensity"] = i }
            if let cp = cs.circadianPhase { csDict["circadian_phase"] = cp }
            body["consciousness_state"] = csDict
        }
        return await post(AgentMessageAck.self, path: "/api/projects/\(Self.seg(slug))/agents/scratchpad", body: body)
    }
}
