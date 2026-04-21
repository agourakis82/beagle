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
        let catalog = await CockpitClient.shared.catalog()
        executive = catalog

        if let policy = catalog.value?.projectPosturePolicy {
            posturePolicy = Truthful(
                value: policy,
                mode: catalog.mode,
                observedAt: catalog.observedAt,
                source: catalog.source,
                error: catalog.error
            )
        } else {
            posturePolicy = await CockpitClient.shared.posturePolicy()
        }

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
    public var research: Truthful<ResearchOperations>
    public var inference: Truthful<InferenceRuntime>

    public var isLoading: Bool = false

    public init(slug: String) {
        self.slug = slug
        self.mission = .declared(MissionControl(project: nil, packetCount: nil, generatedAt: nil))
        self.clusterTruth = .declared(ClusterLaneTruth(project: nil, generatedAt: nil))
        self.research = .declared(ResearchOperations(project: nil, generatedAt: nil))
        self.inference = .declared(InferenceRuntime(
            status: nil, configured: nil, reachable: nil, truthMode: nil,
            engine: nil, controlPlane: nil, models: nil, endpoint: nil
        ))
    }

    public func refresh() async {
        isLoading = true
        let overview = await CockpitClient.shared.mobileOverview(slug: slug)

        if let data = overview.value {
            mission = Truthful(
                value: data.missionControl,
                mode: overview.mode,
                observedAt: overview.observedAt,
                source: overview.source,
                error: overview.error
            )
            clusterTruth = Truthful(
                value: data.clusterLaneTruth,
                mode: overview.mode,
                observedAt: overview.observedAt,
                source: overview.source,
                error: overview.error
            )
            research = Truthful(
                value: data.researchOperations,
                mode: overview.mode,
                observedAt: overview.observedAt,
                source: overview.source,
                error: overview.error
            )

            if let runtime = data.inferenceRuntime {
                inference = Truthful(
                    value: runtime,
                    mode: overview.mode,
                    observedAt: overview.observedAt,
                    source: overview.source,
                    error: overview.error
                )
            } else {
                inference = await CockpitClient.shared.inferenceRuntime(slug: slug)
            }
        } else {
            async let missionTask = CockpitClient.shared.missionControl(slug: slug)
            async let clusterTask = CockpitClient.shared.clusterLaneTruth(slug: slug)
            async let researchTask = CockpitClient.shared.researchOperations(slug: slug)
            async let inferenceTask = CockpitClient.shared.inferenceRuntime(slug: slug)

            mission = await missionTask
            clusterTruth = await clusterTask
            research = await researchTask
            inference = await inferenceTask
        }

        isLoading = false
    }

    public var project: Project? {
        mission.value?.project
    }

    public var posture: ProjectPosture {
        project?.posture ?? .unknown
    }
}
