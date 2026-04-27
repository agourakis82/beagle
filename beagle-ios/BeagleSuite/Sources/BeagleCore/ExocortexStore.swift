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
    public var home: Truthful<ExocortexHomeSnapshot> = .declared(.bootstrap, source: "bootstrap")
    public var projectionStatus: Truthful<MemoryProjectionStatus>?
    public var graphStatus: Truthful<MemoryGraphStatus>?
    public var bakeoffStatus: Truthful<MemoryGraphStatus>?
    public var recentGraph: Truthful<MemoryGraphRecentResponse>?
    public var recentWorlds: Truthful<MemoryWorldsRecentResponse>?
    public var lastGraphRagQuery: Truthful<GraphRagQueryResponse>?
    public var lastAssistedImport: Truthful<AssistedImportBatchResult>?
    public var mcpTools: Truthful<MCPToolListResult>?
    public var isLoading = false
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

    public func refreshRecentGraph(limit: Int = 12) async {
        recentGraph = await client.memoryGraphRecent(limit: limit)
    }

    public func refreshRecentWorlds(limit: Int = 12) async {
        recentWorlds = await client.memoryWorldsRecent(limit: limit)
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
