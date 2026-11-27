//
//  Stores.swift
//  BeagleCore
//
//  Observation-framework reactive stores.
//  Swift equivalent of SolidJS createResource/createTruthSignal.
//
//  Usage:
//    @State var catalog = CatalogStore()
//    Task { await catalog.refresh() }
//

import Foundation
import Observation

@Observable
@MainActor
public final class CatalogStore {
    public private(set) var executive: Truthful<ExecutiveCatalog> = .declared(ExecutiveCatalog(generatedAt: nil, projects: [], projectPosturePolicy: nil))
    public private(set) var posturePolicy: Truthful<PosturePolicy> = .declared(PosturePolicy(title: nil, coreRule: nil, postureDefinitions: nil, counts: nil))
    public private(set) var isLoading: Bool = false

    private let client: CockpitClient

    public init(client: CockpitClient = .shared) {
        self.client = client
    }

    public func refresh() async {
        isLoading = true
        defer { isLoading = false }
        async let catalogTask = client.catalog()
        async let policyTask = client.posturePolicy()
        executive = await catalogTask
        posturePolicy = await policyTask
    }

    public var projects: [Project] {
        executive.value?.projects ?? []
    }

    public var alwaysOnProjects: [Project] {
        projects.filter { $0.posture == .alwaysOn }
    }

    /// The primary project — first always-on, or first project overall.
    public var primaryProject: Project? {
        alwaysOnProjects.first ?? projects.first
    }

    public var warmProjects: [Project] {
        projects.filter { $0.posture == .warm }
    }

    public var coldProjects: [Project] {
        projects.filter { $0.posture == .cold }
    }

    public var postureCounts: PostureCounts {
        executive.value?.projectPosturePolicy?.counts
            ?? posturePolicy.value?.counts
            ?? .empty
    }
}

@Observable
@MainActor
public final class ProjectStore {
    public let slug: String

    public private(set) var mission: Truthful<MissionControl>
    public private(set) var clusterTruth: Truthful<ClusterLaneTruth>
    public private(set) var clusterSummary: Truthful<ClusterSummary>
    public private(set) var research: Truthful<ResearchOperations>
    public private(set) var inference: Truthful<InferenceRuntime>

    public private(set) var isLoading: Bool = false

    private let client: CockpitClient

    public init(slug: String, client: CockpitClient = .shared) {
        self.slug = slug
        self.client = client
        self.mission = .declared(MissionControl(project: nil, packetCount: nil, generatedAt: nil))
        self.clusterTruth = .declared(ClusterLaneTruth(project: nil, generatedAt: nil))
        self.clusterSummary = .declared(ClusterSummary(nodes: nil, project: nil, generatedAt: nil, truthMode: nil))
        self.research = .declared(ResearchOperations(project: nil, generatedAt: nil))
        self.inference = .declared(InferenceRuntime(
            status: nil, configured: nil, reachable: nil, truthMode: nil,
            engine: nil, controlPlane: nil, models: nil, endpoint: nil
        ))
    }

    /// Refreshes project state using a single `/overview` request (instead of 4 redundant
    /// calls) plus `/cluster/summary`, falling back per-field to direct endpoints only when
    /// a section is absent from the mobile overview payload.
    public func refresh() async {
        isLoading = true
        defer { isLoading = false }

        let client = self.client
        let slug = self.slug
        let encodedSlug = BeagleEndpoints.pathComponent(slug)

        async let overviewTask = client.projectOverview(slug: slug)
        async let clusterSumTask = client.clusterSummary(slug: slug)

        let overview = await overviewTask

        async let missionTask: Truthful<MissionControl> = {
            if let projected = overview.compactMap(\.missionControl) { return projected }
            return await client.fetch(MissionControl.self, path: "/api/projects/\(encodedSlug)/mission-control")
        }()
        async let clusterTask: Truthful<ClusterLaneTruth> = {
            if let projected = overview.compactMap(\.clusterLaneTruth) { return projected }
            return await client.fetch(ClusterLaneTruth.self, path: "/api/projects/\(encodedSlug)/cluster/lane-truth")
        }()
        async let researchTask: Truthful<ResearchOperations> = {
            if let projected = overview.compactMap(\.researchOperations) { return projected }
            return await client.fetch(ResearchOperations.self, path: "/api/projects/\(encodedSlug)/research/operations")
        }()
        async let inferenceTask: Truthful<InferenceRuntime> = {
            if let projected = overview.compactMap(\.inferenceRuntime) { return projected }
            let wrapped = await client.fetch(InferenceRuntimeResponse.self, path: "/api/projects/\(encodedSlug)/inference/runtime")
            if let projected = wrapped.compactMap(\.runtime) { return projected }
            return .staleError(wrapped.error ?? "no runtime payload", source: wrapped.source)
        }()

        mission = await missionTask
        clusterTruth = await clusterTask
        clusterSummary = await clusterSumTask
        research = await researchTask
        inference = await inferenceTask
    }

    public var clusterNodes: [ClusterNode] {
        clusterSummary.value?.nodes ?? []
    }

    public var project: Project? {
        mission.value?.project
    }

    public var posture: ProjectPosture {
        project?.posture ?? .unknown
    }
}
