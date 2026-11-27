//
//  ExocortexStore.swift
//  BeagleCore
//
//  Shared Apple store for the cluster-canonical Exocortex Home.
//  SwiftData is only a cache; the cluster remains the source of truth.
//

import Foundation
import Observation
import SwiftData

@Observable
@MainActor
public final class ExocortexStore {
    public private(set) var home: Truthful<ExocortexHomeSnapshot> = .declared(.bootstrap, source: "bootstrap")
    public private(set) var projectionStatus: Truthful<MemoryProjectionStatus>?
    public private(set) var graphStatus: Truthful<MemoryGraphStatus>?
    public private(set) var bakeoffStatus: Truthful<MemoryGraphStatus>?
    public private(set) var benchmarkStatus: Truthful<MemoryBenchmarkStatus>?
    public private(set) var truthSetStatus: Truthful<MemoryTruthSetStatus>?
    public private(set) var recentGraph: Truthful<MemoryGraphRecentResponse>?
    public private(set) var recentWorlds: Truthful<MemoryWorldsRecentResponse>?
    public private(set) var spatialControlRoom: Truthful<ControlRoomSnapshot>?
    public private(set) var mindPalace: Truthful<MindPalaceSnapshot>?
    public private(set) var spatialDesk: Truthful<SpatialDeskSnapshot>?
    public private(set) var focusCoach: Truthful<FocusCoachState>?
    public private(set) var memoryCandidates: Truthful<MemoryCandidateListResponse>?
    public private(set) var memoryGovernanceStatus: Truthful<MemoryGovernanceStatus>?
    public private(set) var memoryContradictions: Truthful<MemoryContradictionListResponse>?
    public private(set) var sounioWorkday: Truthful<SounioWorkdaySnapshot>?
    public private(set) var recentSounioMoments: Truthful<SounioMomentListResponse>?
    public private(set) var lastGraphRagQuery: Truthful<GraphRagQueryResponse>?
    public private(set) var lastAssistedImport: Truthful<AssistedImportBatchResult>?
    public private(set) var mcpTools: Truthful<MCPToolListResult>?
    public private(set) var cachedHomeSnapshot: ExocortexHomeSnapshot?
    public private(set) var isLoading = false
    public var modelContext: ModelContext?

    private let client: BeagleClient
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    public init(client: BeagleClient = .shared) {
        self.client = client
    }

    public func refresh(activeProjectSlug: String? = nil, platform: String = "apple") async {
        isLoading = true
        let result = await client.exocortexHome(
            activeProjectSlug: activeProjectSlug,
            platform: platform
        )
        home = result
        if let snapshot = result.value {
            cache(snapshot)
        }
        isLoading = false
    }

    public func refreshProjectionStatus() async {
        projectionStatus = await client.memoryProjectionStatus()
    }

    public func refreshGraphStatus() async {
        graphStatus = await client.memoryGraphStatus()
    }

    public func refreshBakeoffStatus() async {
        bakeoffStatus = await client.memoryGraphBakeoffStatus()
    }

    public func refreshBenchmarkStatus() async {
        benchmarkStatus = await client.memoryBenchmarkStatus()
    }

    public func refreshTruthSetStatus(id: String) async {
        truthSetStatus = await client.memoryTruthSetStatus(id: id)
    }

    public func refreshRecentGraph(limit: Int = 12) async {
        recentGraph = await client.memoryGraphRecent(limit: limit)
    }

    public func refreshRecentWorlds(limit: Int = 12) async {
        recentWorlds = await client.memoryWorldsRecent(limit: limit)
    }

    public func refreshSpatialControlRoom(projectSlug: String = "sounio") async {
        spatialControlRoom = await client.spatialControlRoom(projectSlug: projectSlug)
    }

    public func refreshMindPalace() async {
        mindPalace = await client.mindPalace()
        if let snapshot = mindPalace?.value {
            spatialDesk = .observed(snapshot.desk, source: "mind-palace")
            focusCoach = .observed(snapshot.focusCoach, source: "mind-palace")
        }
    }

    public func refreshSpatialDesk() async {
        spatialDesk = await client.spatialDesk()
    }

    public func refreshFocusCoach() async {
        focusCoach = await client.focusCoachStatus()
    }

    @discardableResult
    public func recordFocusCoachEvent(_ request: FocusCoachEventRequest) async -> Truthful<FocusCoachState> {
        let result = await client.recordFocusCoachEvent(request)
        focusCoach = result
        return result
    }

    public func refreshMemoryCandidates(limit: Int = 20) async {
        memoryCandidates = await client.memoryCandidates(limit: limit)
    }

    public func refreshMemoryGovernanceStatus() async {
        memoryGovernanceStatus = await client.memoryGovernanceStatus()
    }

    public func refreshMemoryContradictions(limit: Int = 20) async {
        memoryContradictions = await client.memoryContradictions(limit: limit)
    }

    public func refreshSounioWorkday(projectSlug: String = "sounio", limit: Int = 20) async {
        sounioWorkday = await client.sounioWorkdayStatus(projectSlug: projectSlug, limit: limit)
    }

    public func refreshRecentSounioMoments(projectSlug: String = "sounio", limit: Int = 20) async {
        recentSounioMoments = await client.recentSounioMoments(projectSlug: projectSlug, limit: limit)
    }

    @discardableResult
    public func reviewSounioMoment(
        _ moment: SounioMoment,
        decision: String,
        rationale: String? = nil
    ) async -> Truthful<SounioMoment> {
        let result = await client.reviewSounioMoment(
            momentId: moment.id,
            decision: decision,
            rationale: rationale,
            evidenceRefs: moment.evidenceRefs
        )
        if result.value != nil {
            await refreshSounioWorkday(projectSlug: moment.projectSlug)
            await refreshRecentSounioMoments(projectSlug: moment.projectSlug)
        }
        return result
    }

    @discardableResult
    public func queryGraphMemory(
        _ query: String,
        scope: String? = nil,
        maxItems: Int = 5,
        mode: String = "graphsearch-lite"
    ) async -> Truthful<GraphRagQueryResponse> {
        let result = await client.graphRagQuery(query: query, scope: scope, maxItems: maxItems, mode: mode)
        lastGraphRagQuery = result
        return result
    }

    @discardableResult
    public func assistedImport(_ request: AssistedImportBatchRequest) async -> Truthful<AssistedImportBatchResult> {
        let result = await client.assistedImportBatch(request)
        lastAssistedImport = result
        if result.value?.status == "imported" {
            await refresh(platform: request.sourceSurface)
        }
        return result
    }

    public func refreshMCPToolList(
        using mcpClient: BeagleMCPClient = .shared
    ) async {
        do {
            mcpTools = .observed(try await mcpClient.listTools(), source: mcpClient.endpointHost)
        } catch {
            mcpTools = .staleError(error.localizedDescription, source: mcpClient.endpointHost)
        }
    }

    public func loadCachedHome() {
        guard let modelContext else { return }
        var descriptor = FetchDescriptor<PersistedExocortexHomeSnapshot>(
            sortBy: [SortDescriptor(\.capturedAt, order: .reverse)]
        )
        descriptor.fetchLimit = 1
        guard
            let cached = try? modelContext.fetch(descriptor).first,
            let data = cached.payload.data(using: .utf8),
            let snapshot = try? decoder.decode(ExocortexHomeSnapshot.self, from: data)
        else {
            return
        }
        cachedHomeSnapshot = snapshot
        home = .remembered(snapshot, observedAt: cached.capturedAt, source: "swiftdata-cache")
    }

    private func cache(_ snapshot: ExocortexHomeSnapshot) {
        guard
            let modelContext,
            let data = try? encoder.encode(snapshot),
            let payload = String(data: data, encoding: .utf8)
        else {
            return
        }

        if let existing = try? modelContext.fetch(FetchDescriptor<PersistedExocortexHomeSnapshot>()) {
            for item in existing {
                modelContext.delete(item)
            }
        }
        modelContext.insert(PersistedExocortexHomeSnapshot(payload: payload, capturedAt: .now))
        try? modelContext.save()
    }
}
