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
    public var executive: Truthful<ExecutiveCatalog> = .declared(ExecutiveCatalog(generatedAt: nil, projects: [], projectPosturePolicy: nil))
    public var posturePolicy: Truthful<PosturePolicy> = .declared(PosturePolicy(title: nil, coreRule: nil, postureDefinitions: nil, counts: nil))
    public var isLoading: Bool = false

    public init() {}

    public func refresh() async {
        isLoading = true
        async let catalogTask = CockpitClient.shared.catalog()
        async let policyTask = CockpitClient.shared.posturePolicy()
        executive = await catalogTask
        posturePolicy = await policyTask
        isLoading = false
    }

    public var projects: [Project] {
        executive.value?.projects ?? []
    }

    public var alwaysOnProjects: [Project] {
        projects.filter { $0.posture == .alwaysOn }
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

    public var mission: Truthful<MissionControl>
    public var clusterTruth: Truthful<ClusterLaneTruth>
    public var clusterSummary: Truthful<ClusterSummary>
    public var research: Truthful<ResearchOperations>
    public var inference: Truthful<InferenceRuntime>

    public var isLoading: Bool = false

    public init(slug: String) {
        self.slug = slug
        self.mission = .declared(MissionControl(project: nil, packetCount: nil, generatedAt: nil))
        self.clusterTruth = .declared(ClusterLaneTruth(project: nil, generatedAt: nil))
        self.clusterSummary = .declared(ClusterSummary(nodes: nil, project: nil, generatedAt: nil, truthMode: nil))
        self.research = .declared(ResearchOperations(project: nil, generatedAt: nil))
        self.inference = .declared(InferenceRuntime(
            status: nil, configured: nil, reachable: nil, truthMode: nil,
            engine: nil, controlPlane: nil, models: nil, endpoint: nil
        ))
    }

    public func refresh() async {
        isLoading = true
        async let missionTask = CockpitClient.shared.missionControl(slug: slug)
        async let clusterTask = CockpitClient.shared.clusterLaneTruth(slug: slug)
        async let clusterSumTask = CockpitClient.shared.clusterSummary(slug: slug)
        async let researchTask = CockpitClient.shared.researchOperations(slug: slug)
        async let inferenceTask = CockpitClient.shared.inferenceRuntime(slug: slug)

        mission = await missionTask
        clusterTruth = await clusterTask
        clusterSummary = await clusterSumTask
        research = await researchTask
        inference = await inferenceTask
        isLoading = false
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
