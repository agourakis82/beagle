//
//  BeagleClient+Exocortex.swift
//  BeagleCore
//
//  Exocortex v1 snapshot, capture, graph, and Sounio trace routes.
//

import Foundation

extension BeagleClient {

    // MARK: - Exocortex v1

    public func exocortexHome(
        activeProjectSlug: String? = nil,
        platform: String = "apple"
    ) async -> Truthful<ExocortexHomeSnapshot> {
        var queryItems: [String] = []
        if let activeProjectSlug,
           let encoded = activeProjectSlug.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) {
            queryItems.append("active_project_slug=\(encoded)")
        }
        if let encoded = platform.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) {
            queryItems.append("platform=\(encoded)")
        }
        let suffix = queryItems.isEmpty ? "" : "?\(queryItems.joined(separator: "&"))"
        return await fetch(
            ExocortexHomeSnapshot.self,
            path: "/api/exocortex/v1/home\(suffix)",
            timeout: 20
        )
    }

    public func memoryProjectionStatus() async -> Truthful<MemoryProjectionStatus> {
        await fetch(
            MemoryProjectionStatus.self,
            path: "/api/exocortex/v1/memory/projection/status",
            timeout: 20
        )
    }

    public func memoryGraphStatus() async -> Truthful<MemoryGraphStatus> {
        await fetch(
            MemoryGraphStatus.self,
            path: "/api/exocortex/v1/memory/graph/status",
            timeout: 20
        )
    }

    public func memoryGraphBakeoffStatus() async -> Truthful<MemoryGraphStatus> {
        await fetch(
            MemoryGraphStatus.self,
            path: "/api/exocortex/v1/memory/graph/bakeoff/status",
            timeout: 20
        )
    }

    public func memoryBenchmarkStatus() async -> Truthful<MemoryBenchmarkStatus> {
        await fetch(
            MemoryBenchmarkStatus.self,
            path: "/api/exocortex/v1/memory/bench/status",
            timeout: 20
        )
    }

    public func memoryTruthSetStatus(id: String) async -> Truthful<MemoryTruthSetStatus> {
        await fetch(
            MemoryTruthSetStatus.self,
            path: "/api/exocortex/v1/memory/truthsets/\(id)",
            timeout: 20
        )
    }

    public func runMemoryGraphBakeoff(datasetLimit: Int = 200) async -> Truthful<GraphBakeoffRun> {
        await post(
            GraphBakeoffRun.self,
            path: "/api/exocortex/v1/memory/graph/bakeoff",
            body: [
                "dataset_limit": max(1, min(datasetLimit, 2000)),
                "include_baseline": true
            ],
            timeout: 120
        )
    }

    public func indexMemoryGraph(rebuild: Bool = false, runtime: String? = nil) async -> Truthful<GraphIndexRun> {
        var body: [String: any Sendable] = [
            "rebuild": rebuild,
            "source_refs": [String]()
        ]
        if let runtime, !runtime.isEmpty {
            body["runtime"] = runtime
        }
        return await post(
            GraphIndexRun.self,
            path: "/api/exocortex/v1/memory/index-graph",
            body: body,
            timeout: 120
        )
    }

    public func memoryGraphRecent(limit: Int = 12) async -> Truthful<MemoryGraphRecentResponse> {
        await fetch(
            MemoryGraphRecentResponse.self,
            path: "/api/exocortex/v1/memory/graph/recent?limit=\(max(1, min(limit, 50)))",
            timeout: 20
        )
    }

    public func memoryWorldsRecent(limit: Int = 12) async -> Truthful<MemoryWorldsRecentResponse> {
        await fetch(
            MemoryWorldsRecentResponse.self,
            path: "/api/exocortex/v1/memory/worlds/recent?limit=\(max(1, min(limit, 50)))",
            timeout: 20
        )
    }

    public func registerSpatialWorld(_ request: CreateSpatialWorldRequest) async -> Truthful<SpatialWorld> {
        await postEncoded(
            SpatialWorld.self,
            path: "/api/exocortex/v1/spatial/worlds/marble",
            body: request,
            timeout: 60
        )
    }

    public func spatialWorld(_ worldId: String) async -> Truthful<SpatialWorld> {
        await fetch(
            SpatialWorld.self,
            path: "/api/exocortex/v1/spatial/worlds/\(Self.pathComponent(worldId))",
            timeout: 20
        )
    }

    public func spatialWorldAssets(_ worldId: String) async -> Truthful<SpatialAssetManifest> {
        await fetch(
            SpatialAssetManifest.self,
            path: "/api/exocortex/v1/spatial/worlds/\(Self.pathComponent(worldId))/assets",
            timeout: 20
        )
    }

    public func spatialControlRoom(projectSlug: String = "sounio") async -> Truthful<ControlRoomSnapshot> {
        await fetch(
            ControlRoomSnapshot.self,
            path: "/api/exocortex/v1/spatial/projects/\(Self.pathComponent(projectSlug))/control-room",
            timeout: 20
        )
    }

    public func createSounioSpatialEvidence(
        worldId: String,
        request: CreateSounioSpatialEvidenceRequest
    ) async -> Truthful<SounioSpatialEvidence> {
        await postEncoded(
            SounioSpatialEvidence.self,
            path: "/api/exocortex/v1/spatial/worlds/\(Self.pathComponent(worldId))/sounio/evidence",
            body: request,
            timeout: 60
        )
    }

    public func mindPalace() async -> Truthful<MindPalaceSnapshot> {
        await fetch(
            MindPalaceSnapshot.self,
            path: "/api/exocortex/v1/mind-palace",
            timeout: 20
        )
    }

    public func mindPalaceRooms() async -> Truthful<[MindPalaceRoom]> {
        await fetch(
            [MindPalaceRoom].self,
            path: "/api/exocortex/v1/mind-palace/rooms",
            timeout: 20
        )
    }

    public func spatialDesk() async -> Truthful<SpatialDeskSnapshot> {
        await fetch(
            SpatialDeskSnapshot.self,
            path: "/api/exocortex/v1/mind-palace/desk",
            timeout: 20
        )
    }

    public func nextBestPlace() async -> Truthful<NextBestPlaceDecision> {
        await fetch(
            NextBestPlaceDecision.self,
            path: "/api/exocortex/v1/mind-palace/next-best-place",
            timeout: 20
        )
    }

    public func spatialActionMenu() async -> Truthful<SpatialActionMenu> {
        await fetch(
            SpatialActionMenu.self,
            path: "/api/exocortex/v1/mind-palace/action-menu",
            timeout: 20
        )
    }

    public func createConversationPortal(_ request: CreateConversationPortalRequest) async -> Truthful<ConversationPortal> {
        await postEncoded(
            ConversationPortal.self,
            path: "/api/exocortex/v1/conversation-portals",
            body: request,
            timeout: 20
        )
    }

    public func promoteConversationPortal(
        portalId: String,
        request: PromoteConversationPortalRequest
    ) async -> Truthful<PromotedConversationClip> {
        await postEncoded(
            PromotedConversationClip.self,
            path: "/api/exocortex/v1/conversation-portals/\(Self.pathComponent(portalId))/promote",
            body: request,
            timeout: 60
        )
    }

    public func focusCoachStatus() async -> Truthful<FocusCoachState> {
        await fetch(
            FocusCoachState.self,
            path: "/api/exocortex/v1/focus-coach/status",
            timeout: 20
        )
    }

    public func recordFocusCoachEvent(_ request: FocusCoachEventRequest) async -> Truthful<FocusCoachState> {
        await postEncoded(
            FocusCoachState.self,
            path: "/api/exocortex/v1/focus-coach/events",
            body: request,
            timeout: 20
        )
    }

    public func memoryCandidates(limit: Int = 20) async -> Truthful<MemoryCandidateListResponse> {
        await fetch(
            MemoryCandidateListResponse.self,
            path: "/api/exocortex/v1/memory/candidates?limit=\(max(1, min(limit, 100)))",
            timeout: 20
        )
    }

    public func memoryGovernanceStatus() async -> Truthful<MemoryGovernanceStatus> {
        await fetch(
            MemoryGovernanceStatus.self,
            path: "/api/exocortex/v1/memory/governance/status",
            timeout: 20
        )
    }

    public func memoryContradictions(limit: Int = 20) async -> Truthful<MemoryContradictionListResponse> {
        await fetch(
            MemoryContradictionListResponse.self,
            path: "/api/exocortex/v1/memory/contradictions?limit=\(max(1, min(limit, 100)))",
            timeout: 20
        )
    }

    public func graphRagQuery(
        query: String,
        scope: String? = nil,
        maxItems: Int = 5,
        mode: String = "hypermemory_multivector"
    ) async -> Truthful<GraphRagQueryResponse> {
        var body: [String: any Sendable] = [
            "query": query,
            "max_items": maxItems,
            "mode": mode
        ]
        if let scope, !scope.isEmpty {
            body["scope"] = scope
        }
        return await post(
            GraphRagQueryResponse.self,
            path: "/api/exocortex/v1/graphrag/query",
            body: body,
            timeout: 60
        )
    }

    public func assistedImportBatch(
        _ request: AssistedImportBatchRequest
    ) async -> Truthful<AssistedImportBatchResult> {
        await postEncoded(
            AssistedImportBatchResult.self,
            // O Cloudflare libera /api/mobile/* e bloqueia /api/exocortex/* (401 de corpo
            // vazio, antes de chegar ao servidor). Como o gateway público é o primeiro
            // que o app tenta, a importação nunca chegava — e cada falha ia para o
            // outbox. O cockpit serve o MESMO handler nos dois caminhos.
            path: "/api/mobile/v1/memory/assisted-import",
            body: request,
            timeout: 120
        )
    }

    public func captureSessionStart(
        _ request: CaptureSessionStartRequest
    ) async -> Truthful<CaptureSession> {
        await postEncoded(
            CaptureSession.self,
            path: "/api/exocortex/v1/capture/sessions",
            body: request,
            timeout: 30
        )
    }

    public func captureSessionStatus(
        sessionId: String
    ) async -> Truthful<CaptureSession> {
        await fetch(
            CaptureSession.self,
            path: "/api/exocortex/v1/capture/sessions/\(sessionId)",
            timeout: 20
        )
    }

    public func captureSessionEvent(
        sessionId: String,
        request: CaptureSessionEventRequest
    ) async -> Truthful<CaptureSessionEvent> {
        await postEncoded(
            CaptureSessionEvent.self,
            path: "/api/exocortex/v1/capture/sessions/\(sessionId)/events",
            body: request,
            timeout: 30
        )
    }

    public func visualEvidenceArtifact(
        _ request: VisualEvidenceArtifactRequest
    ) async -> Truthful<VisualEvidenceArtifact> {
        await postEncoded(
            VisualEvidenceArtifact.self,
            path: "/api/exocortex/v1/capture/visual/artifacts",
            body: request,
            timeout: 60
        )
    }

    public func visualEvidenceAnalyze(
        _ request: VisualEvidenceAnalyzeRequest
    ) async -> Truthful<VisualEvidenceAnalysis> {
        await postEncoded(
            VisualEvidenceAnalysis.self,
            path: "/api/exocortex/v1/capture/visual/analyze",
            body: request,
            timeout: 90
        )
    }

    public func captureReview(
        _ request: CaptureReviewRequest
    ) async -> Truthful<CaptureReviewResult> {
        await postEncoded(
            CaptureReviewResult.self,
            path: "/api/exocortex/v1/capture/review",
            body: request,
            timeout: 60
        )
    }

    public func startSounioPaperRun(
        paperId: String? = nil,
        title: String? = nil,
        dryRun: Bool = false
    ) async -> Truthful<PaperRun> {
        var body: [String: any Sendable] = [
            "surface": "beagle-apple",
            "principal": "beagle-app",
            "dry_run": dryRun
        ]
        if let paperId, !paperId.isEmpty {
            body["paper_id"] = paperId
        }
        if let title, !title.isEmpty {
            body["title"] = title
        }
        return await post(
            PaperRun.self,
            path: "/api/exocortex/v1/sounio/paperruns",
            body: body,
            timeout: 120
        )
    }

    public func checkSounioClaim(_ claim: SounioClaimInput) async -> Truthful<SounioClaimCheckResponse> {
        await postEncoded(
            SounioClaimCheckResponse.self,
            path: "/api/exocortex/v1/sounio/claims/check",
            body: SounioClaimCheckRequest(claim: claim),
            timeout: 30
        )
    }

    public func typeSounioMoment(_ request: SounioMomentTypeRequest) async -> Truthful<SounioMoment> {
        await postEncoded(
            SounioMoment.self,
            path: "/api/exocortex/v1/sounio/moments/type",
            body: request,
            timeout: 30
        )
    }

    public func recentSounioMoments(projectSlug: String = "sounio", limit: Int = 20) async -> Truthful<SounioMomentListResponse> {
        let slug = projectSlug.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? projectSlug
        return await fetch(
            SounioMomentListResponse.self,
            path: "/api/exocortex/v1/sounio/moments/recent?project_slug=\(slug)&limit=\(limit)",
            timeout: 30
        )
    }

    public func reviewSounioMoment(
        momentId: String,
        decision: String,
        rationale: String? = nil,
        evidenceRefs: [String] = [],
        reviewState: String? = nil,
        provenance: ExocortexJSONValue? = .object(["source": .string("beagle-apple")])
    ) async -> Truthful<SounioMoment> {
        let body = SounioMomentReviewRequest(
            reviewer: "demetrios",
            decision: decision,
            rationale: rationale,
            evidenceRefs: evidenceRefs,
            reviewState: reviewState,
            provenance: provenance
        )
        let encodedId = momentId.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? momentId
        return await postEncoded(
            SounioMoment.self,
            path: "/api/exocortex/v1/sounio/moments/\(encodedId)/review",
            body: body,
            timeout: 30
        )
    }

    public func sounioWorkdayStatus(projectSlug: String = "sounio", limit: Int = 20) async -> Truthful<SounioWorkdaySnapshot> {
        let slug = projectSlug.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? projectSlug
        return await fetch(
            SounioWorkdaySnapshot.self,
            path: "/api/exocortex/v1/sounio/workday/status?project_slug=\(slug)&limit=\(limit)",
            timeout: 30
        )
    }

    public func sounioPaperRunStatus(_ paperRunId: String) async -> Truthful<PaperRun> {
        await fetch(
            PaperRun.self,
            path: "/api/exocortex/v1/sounio/paperruns/\(paperRunId)",
            timeout: 30
        )
    }

    public func approveSounioPaperRunStep(
        paperRunId: String,
        stepId: String,
        decision: String = "approved",
        rationale: String? = nil
    ) async -> Truthful<PaperRun> {
        var body: [String: any Sendable] = [
            "step_id": stepId,
            "decision": decision,
            "reviewer": "demetrios"
        ]
        if let rationale, !rationale.isEmpty {
            body["rationale"] = rationale
        }
        return await post(
            PaperRun.self,
            path: "/api/exocortex/v1/sounio/paperruns/\(paperRunId)/approve-step",
            body: body,
            timeout: 30
        )
    }

    public func addSounioClaim(
        paperRunId: String,
        claim: SounioClaimInput,
        principal: String = "beagle-app",
        surface: String = "beagle-apple-paper-workbench"
    ) async -> Truthful<SounioClaim> {
        let body = AddSounioClaimRequest(
            claim: claim,
            principal: principal,
            surface: surface
        )
        return await postEncoded(
            SounioClaim.self,
            path: "/api/exocortex/v1/sounio/paperruns/\(paperRunId)/claims",
            body: body,
            timeout: 30
        )
    }

    public func reviewSounioClaim(
        paperRunId: String,
        claimId: String,
        decision: String,
        rationale: String? = nil,
        evidenceRefs: [String] = [],
        epistemicStatus: String? = nil,
        publicationReadiness: String? = nil,
        provenance: ExocortexJSONValue? = .object(["source": .string("beagle-apple")])
    ) async -> Truthful<SounioClaim> {
        let body = ReviewSounioClaimRequest(
            reviewer: "demetrios",
            decision: decision,
            rationale: rationale,
            evidenceRefs: evidenceRefs,
            epistemicStatus: epistemicStatus,
            publicationReadiness: publicationReadiness,
            provenance: provenance
        )
        return await postEncoded(
            SounioClaim.self,
            path: "/api/exocortex/v1/sounio/paperruns/\(paperRunId)/claims/\(claimId)/review",
            body: body,
            timeout: 30
        )
    }

    public func sounioPaperRunTheatre(_ paperRunId: String) async -> Truthful<PaperRunTheatreSnapshot> {
        await fetch(
            PaperRunTheatreSnapshot.self,
            path: "/api/exocortex/v1/sounio/paperruns/\(paperRunId)/theatre",
            timeout: 30
        )
    }

    public func sounioPaperRunPublicDigest(_ paperRunId: String) async -> Truthful<PublicDigestArtifact> {
        await fetch(
            PublicDigestArtifact.self,
            path: "/api/exocortex/v1/sounio/paperruns/\(paperRunId)/public-digest",
            timeout: 30
        )
    }

    public func sounioPaperRunArtifacts(_ paperRunId: String) async -> Truthful<PaperRunArtifactsResponse> {
        await fetch(
            PaperRunArtifactsResponse.self,
            path: "/api/exocortex/v1/sounio/paperruns/\(paperRunId)/artifacts",
            timeout: 30
        )
    }

    public func sounioTrace(paperRunId: String? = nil, limit: Int = 25) async -> Truthful<SounioTraceListResponse> {
        var path = "/api/exocortex/v1/sounio/trace?limit=\(limit)"
        if let paperRunId, !paperRunId.isEmpty {
            path += "&paper_run_id=\(paperRunId)"
        }
        return await fetch(SounioTraceListResponse.self, path: path, timeout: 30)
    }

}
