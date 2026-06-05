//
//  Models.swift
//  BeagleCore
//
//  Domain models matching the cockpit server API responses.
//  All Sendable for Swift 6 strict concurrency.
//

import Foundation

// MARK: - Project

public struct Project: Codable, Sendable, Identifiable, Hashable {
    public var id: String { projectSlug }
    public let projectSlug: String
    public let mode: String?
    public let namespace: String?
    public let branch: String?
    public let preferredPrBase: String?
    public let workspacePod: String?
    public let tmuxSession: String?
    public let workspaceRoot: String?
    public let playgroundClass: String?
    public let repoUrl: String?

    public var posture: ProjectPosture {
        ProjectPosture(from: mode)
    }

    public init(
        projectSlug: String,
        mode: String? = nil,
        namespace: String? = nil,
        branch: String? = nil,
        preferredPrBase: String? = nil,
        workspacePod: String? = nil,
        tmuxSession: String? = nil,
        workspaceRoot: String? = nil,
        playgroundClass: String? = nil,
        repoUrl: String? = nil
    ) {
        self.projectSlug = projectSlug
        self.mode = mode
        self.namespace = namespace
        self.branch = branch
        self.preferredPrBase = preferredPrBase
        self.workspacePod = workspacePod
        self.tmuxSession = tmuxSession
        self.workspaceRoot = workspaceRoot
        self.playgroundClass = playgroundClass
        self.repoUrl = repoUrl
    }
}

// MARK: - Posture Policy

public struct PostureDefinition: Codable, Sendable, Hashable {
    public let name: String
    public let summary: String
    public let operationalMeaning: String?
}

public struct PostureCounts: Codable, Sendable, Hashable {
    public let totalProjects: Int
    public let alwaysOn: Int
    public let warm: Int
    public let cold: Int

    public static let empty = PostureCounts(totalProjects: 0, alwaysOn: 0, warm: 0, cold: 0)
}

public struct PosturePolicy: Codable, Sendable {
    public let title: String?
    public let coreRule: String?
    public let postureDefinitions: [PostureDefinition]?
    public let counts: PostureCounts?
}

// MARK: - Catalog

public struct ExecutiveCatalog: Codable, Sendable {
    public let generatedAt: String?
    public let projects: [Project]?
    public let projectPosturePolicy: PosturePolicy?

    public init(
        generatedAt: String? = nil,
        projects: [Project]? = nil,
        projectPosturePolicy: PosturePolicy? = nil
    ) {
        self.generatedAt = generatedAt
        self.projects = projects
        self.projectPosturePolicy = projectPosturePolicy
    }
}

// MARK: - Mission Control

public struct MissionControl: Codable, Sendable {
    public let project: Project?
    public let packetCount: Int?
    public let generatedAt: String?
}

// MARK: - Inference Fabric

public struct InferenceModel: Codable, Sendable, Hashable, Identifiable {
    public var id: String { "\(provider ?? "")/\(idField ?? "unknown")" }
    public let idField: String?
    public let provider: String?
    public let family: String?

    enum CodingKeys: String, CodingKey {
        case idField = "id"
        case provider, family
    }
}

public struct InferenceComponent: Codable, Sendable {
    public let status: String?
    public let reachable: Bool?
}

public struct InferenceRuntime: Codable, Sendable {
    public let status: String?
    public let configured: Bool?
    public let reachable: Bool?
    public let truthMode: String?
    public let engine: InferenceComponent?
    public let controlPlane: InferenceComponent?
    public let models: [InferenceModel]?
    public let endpoint: String?

    public var displayTruthMode: TruthMode {
        TruthMode(rawValue: truthMode ?? "") ?? .declared
    }
}

public struct InferenceRuntimeResponse: Codable, Sendable {
    public let runtime: InferenceRuntime?
}

// MARK: - Cluster Truth

public struct ClusterNode: Codable, Sendable, Hashable, Identifiable {
    public var id: String { hostname ?? name ?? UUID().uuidString }
    public let name: String?
    public let hostname: String?
    public let role: String?
    public let healthy: Bool?
}

public struct ClusterLaneTruth: Codable, Sendable {
    public let project: Project?
    public let generatedAt: String?
}

// MARK: - Research Operations

public struct ResearchCampaign: Codable, Sendable {
    public let runId: String?
    public let jobId: String?
    public let status: String?
    public let nodelist: String?
    public let lastSubmitUnixtime: Double?

    enum CodingKeys: String, CodingKey {
        case runId = "run_id"
        case jobId = "job_id"
        case status, nodelist
        case lastSubmitUnixtime = "last_submit_unixtime"
    }
}

public struct ResearchOperations: Codable, Sendable {
    public let project: Project?
    public let generatedAt: String?
}

// MARK: - Viewer

public struct ViewerRenderer: Codable, Sendable {
    public let status: String?
    public let runtime: ViewerRendererRuntime?
}

public struct ViewerRendererRuntime: Codable, Sendable {
    public let api: String?
    public let backend: String?
}

public struct ViewerRuntimeResponse: Codable, Sendable {
    public let renderer: ViewerRenderer?
}
