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

    public init(totalProjects: Int, alwaysOn: Int, warm: Int, cold: Int) {
        self.totalProjects = totalProjects
        self.alwaysOn = alwaysOn
        self.warm = warm
        self.cold = cold
    }

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
}

public struct MobileMeta: Decodable, Sendable {
    public let truthMode: String?
    public let generatedAt: String?
    public let requestId: String?

    enum CodingKeys: String, CodingKey {
        case truthMode
        case truthModeSnake = "truth_mode"
        case generatedAt
        case generatedAtSnake = "generated_at"
        case requestId
        case requestIdSnake = "request_id"
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        truthMode =
            try container.decodeIfPresent(String.self, forKey: .truthMode)
            ?? container.decodeIfPresent(String.self, forKey: .truthModeSnake)
        generatedAt =
            try container.decodeIfPresent(String.self, forKey: .generatedAt)
            ?? container.decodeIfPresent(String.self, forKey: .generatedAtSnake)
        requestId =
            try container.decodeIfPresent(String.self, forKey: .requestId)
            ?? container.decodeIfPresent(String.self, forKey: .requestIdSnake)
    }
}

public struct MobileEnvelopeError: Decodable, Sendable {
    public let message: String?
    public let reason: String?
    public let code: String?

    public init(from decoder: Decoder) throws {
        if let singleValue = try? decoder.singleValueContainer(),
           let stringValue = try? singleValue.decode(String.self)
        {
            message = stringValue
            reason = nil
            code = nil
            return
        }

        let container = try decoder.container(keyedBy: CodingKeys.self)
        message =
            try container.decodeIfPresent(String.self, forKey: .message)
            ?? container.decodeIfPresent(String.self, forKey: .error)
        reason = try container.decodeIfPresent(String.self, forKey: .reason)
        code = try container.decodeIfPresent(String.self, forKey: .code)
    }

    enum CodingKeys: String, CodingKey {
        case message
        case error
        case reason
        case code
    }
}

public struct MobileEnvelope<T: Decodable & Sendable>: Decodable, Sendable {
    public let ok: Bool?
    public let data: T?
    public let error: MobileEnvelopeError?
    public let meta: MobileMeta?
}

public struct MobileProjectOverview: Decodable, Sendable {
    public let project: Project?
    public let missionControl: MissionControl?
    public let clusterLaneTruth: ClusterLaneTruth?
    public let clusterSummary: ClusterSummary?
    public let researchOperations: ResearchOperations?
    public let inferenceRuntime: InferenceRuntime?
    public let viewerRuntime: ViewerRuntimeResponse?

    enum CodingKeys: String, CodingKey {
        case project
        case missionControl
        case mission
        case clusterLaneTruth
        case clusterTruth
        case clusterSummary
        case cluster
        case researchOperations
        case research
        case inferenceRuntime
        case inference
        case viewerRuntime
        case viewer
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        project = try container.decodeIfPresent(Project.self, forKey: .project)
        missionControl =
            try container.decodeIfPresent(MissionControl.self, forKey: .missionControl)
            ?? container.decodeIfPresent(MissionControl.self, forKey: .mission)
        clusterLaneTruth =
            try container.decodeIfPresent(ClusterLaneTruth.self, forKey: .clusterLaneTruth)
            ?? container.decodeIfPresent(ClusterLaneTruth.self, forKey: .clusterTruth)
        clusterSummary =
            try container.decodeIfPresent(ClusterSummary.self, forKey: .clusterSummary)
            ?? container.decodeIfPresent(ClusterSummary.self, forKey: .cluster)
        researchOperations =
            try container.decodeIfPresent(ResearchOperations.self, forKey: .researchOperations)
            ?? container.decodeIfPresent(ResearchOperations.self, forKey: .research)
        inferenceRuntime =
            try container.decodeIfPresent(InferenceRuntime.self, forKey: .inferenceRuntime)
            ?? container.decodeIfPresent(InferenceRuntime.self, forKey: .inference)
        viewerRuntime =
            try container.decodeIfPresent(ViewerRuntimeResponse.self, forKey: .viewerRuntime)
            ?? container.decodeIfPresent(ViewerRuntimeResponse.self, forKey: .viewer)
    }
}

public struct MobileHomeSummary: Decodable, Sendable {
    public let activeAgentsCount: Int?
    public let activeSessionsCount: Int?
    public let clusterHealth: String?
    public let lastMemorySyncTime: String?

    enum CodingKeys: String, CodingKey {
        case activeAgentsCount
        case activeAgentsCountSnake = "active_agents_count"
        case activeSessionsCount
        case activeSessionsCountSnake = "active_sessions_count"
        case clusterHealth
        case clusterHealthSnake = "cluster_health"
        case lastMemorySyncTime
        case lastMemorySyncTimeSnake = "last_memory_sync_time"
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        activeAgentsCount =
            try container.decodeIfPresent(Int.self, forKey: .activeAgentsCount)
            ?? container.decodeIfPresent(Int.self, forKey: .activeAgentsCountSnake)
        activeSessionsCount =
            try container.decodeIfPresent(Int.self, forKey: .activeSessionsCount)
            ?? container.decodeIfPresent(Int.self, forKey: .activeSessionsCountSnake)
        clusterHealth =
            try container.decodeIfPresent(String.self, forKey: .clusterHealth)
            ?? container.decodeIfPresent(String.self, forKey: .clusterHealthSnake)
        lastMemorySyncTime =
            try container.decodeIfPresent(String.self, forKey: .lastMemorySyncTime)
            ?? container.decodeIfPresent(String.self, forKey: .lastMemorySyncTimeSnake)
    }
}

public struct IdeaSaveResponse: Decodable, Sendable {
    public let nodeId: String?
    public let syncState: IdeaSyncState?
    public let projectFamily: String?
    public let publicationScope: String?

    enum CodingKeys: String, CodingKey {
        case nodeId
        case nodeIdSnake = "node_id"
        case syncState
        case syncStateSnake = "sync_state"
        case projectFamily
        case publicationScope
        case projectFamilySnake = "project_family"
        case publicationScopeSnake = "publication_scope"
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        nodeId =
            try container.decodeIfPresent(String.self, forKey: .nodeId)
            ?? container.decodeIfPresent(String.self, forKey: .nodeIdSnake)
        syncState =
            try container.decodeIfPresent(IdeaSyncState.self, forKey: .syncState)
            ?? container.decodeIfPresent(IdeaSyncState.self, forKey: .syncStateSnake)
        projectFamily =
            try container.decodeIfPresent(String.self, forKey: .projectFamily)
            ?? container.decodeIfPresent(String.self, forKey: .projectFamilySnake)
        publicationScope =
            try container.decodeIfPresent(String.self, forKey: .publicationScope)
            ?? container.decodeIfPresent(String.self, forKey: .publicationScopeSnake)
    }
}

public struct DelegationResponse: Decodable, Sendable {
    public let agentKind: String?
    public let sessionId: String?
    public let podName: String?
    public let resultingState: String?
    public let projectFamily: String?
    public let publicationScope: String?

    enum CodingKeys: String, CodingKey {
        case agentKind
        case sessionId
        case podName
        case resultingState
        case projectFamily
        case publicationScope
        case agentKindSnake = "agent_kind"
        case sessionIdSnake = "session_id"
        case podNameSnake = "pod_name"
        case resultingStateSnake = "resulting_state"
        case projectFamilySnake = "project_family"
        case publicationScopeSnake = "publication_scope"
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        agentKind =
            try container.decodeIfPresent(String.self, forKey: .agentKind)
            ?? container.decodeIfPresent(String.self, forKey: .agentKindSnake)
        sessionId =
            try container.decodeIfPresent(String.self, forKey: .sessionId)
            ?? container.decodeIfPresent(String.self, forKey: .sessionIdSnake)
        podName =
            try container.decodeIfPresent(String.self, forKey: .podName)
            ?? container.decodeIfPresent(String.self, forKey: .podNameSnake)
        resultingState =
            try container.decodeIfPresent(String.self, forKey: .resultingState)
            ?? container.decodeIfPresent(String.self, forKey: .resultingStateSnake)
        projectFamily =
            try container.decodeIfPresent(String.self, forKey: .projectFamily)
            ?? container.decodeIfPresent(String.self, forKey: .projectFamilySnake)
        publicationScope =
            try container.decodeIfPresent(String.self, forKey: .publicationScope)
            ?? container.decodeIfPresent(String.self, forKey: .publicationScopeSnake)
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

    public init(name: String?, hostname: String?, role: String?, healthy: Bool?) {
        self.name = name
        self.hostname = hostname
        self.role = role
        self.healthy = healthy
    }
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

// MARK: - Agent Sessions

public struct AgentPod: Codable, Sendable {
    public let name: String?
    public let phase: String?
    public let ready: Bool?
}

public struct AgentSession: Codable, Sendable {
    public let kind: String?
    public let name: String?
    public let replicas: Int?
    public let readyReplicas: Int?
    public let createdAt: String?
    public let pods: [AgentPod]?
    public let status: String?
    public let truthMode: String?
    public let action: String?

    public var isRunning: Bool { (readyReplicas ?? 0) > 0 }
    public var podName: String? { pods?.first?.name }
    public var phase: AgentSessionPhase {
        if isRunning { return .running }
        if replicas == 0 { return .paused }
        return .pending
    }
}

public enum AgentSessionPhase: String, Sendable {
    case pending
    case running
    case paused
}

public struct AgentSessionListResponse: Codable, Sendable {
    public let projectSlug: String?
    public let sessions: [AgentSession]?
    public let generatedAt: String?
    public let truthMode: String?
}

// MARK: - Action Response

public struct ActionResponse: Codable, Sendable {
    public let ok: Bool?
    public let actionId: String?
    public let output: String?
    public let truthMode: String?
}

// MARK: - Cluster Summary

public struct ClusterSummary: Codable, Sendable {
    public let nodes: [ClusterNode]?
    public let project: Project?
    public let generatedAt: String?
    public let truthMode: String?
}

// MARK: - Go Work Now

public struct GoWorkNow: Codable, Sendable {
    public let project: Project?
    public let actions: [GoWorkNowAction]?
    public let generatedAt: String?
}

public struct GoWorkNowAction: Codable, Sendable {
    public let id: String?
    public let label: String?
    public let description: String?
    public let kind: String?
    public let ready: Bool?
}

// MARK: - Live Activity Attributes

#if os(iOS)
import ActivityKit

public struct AgentSessionAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable, Sendable {
        public var status: String
        public var tokensUsed: Int
        public var lastOutputSnippet: String

        public init(status: String, tokensUsed: Int, lastOutputSnippet: String) {
            self.status = status
            self.tokensUsed = tokensUsed
            self.lastOutputSnippet = lastOutputSnippet
        }
    }

    public var agentKind: String
    public var projectSlug: String
    public var sessionId: String

    public init(agentKind: String, projectSlug: String, sessionId: String) {
        self.agentKind = agentKind
        self.projectSlug = projectSlug
        self.sessionId = sessionId
    }
}

public struct ResearchRunAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable, Sendable {
        public var stepCurrent: Int
        public var stepTotal: Int
        public var etaSeconds: Int

        public init(stepCurrent: Int, stepTotal: Int, etaSeconds: Int) {
            self.stepCurrent = stepCurrent
            self.stepTotal = stepTotal
            self.etaSeconds = etaSeconds
        }
    }

    public var runId: String
    public var campaignName: String
    public var projectSlug: String

    public init(runId: String, campaignName: String, projectSlug: String) {
        self.runId = runId
        self.campaignName = campaignName
        self.projectSlug = projectSlug
    }
}
#endif

// MARK: - WebSocket / Terminal

public enum TerminalMessage: Sendable {
    case data(String)
    case stderr(String)
    case ready(projectSlug: String)
    case exit(code: Int)
}

public enum WebSocketState: Sendable, Equatable {
    case disconnected
    case connecting
    case connected(source: String)
    case reconnecting(attempt: Int)
    case failed(String)
}

public struct TerminalLine: Identifiable, Sendable {
    public let id: UInt64
    public let text: String
    public let timestamp: Date
    public let isStderr: Bool

    public init(id: UInt64, text: String, timestamp: Date = .now, isStderr: Bool = false) {
        self.id = id
        self.text = text
        self.timestamp = timestamp
        self.isStderr = isStderr
    }
}

// MARK: - Science Jobs

public struct ScienceJob: Codable, Sendable, Identifiable {
    public var id: String { jobId ?? UUID().uuidString }
    public let jobId: String?
    public let kind: String?
    public let status: String?
    public let createdAt: String?
    public let updatedAt: String?
    public let error: String?
    public let resultPath: String?

    enum CodingKeys: String, CodingKey {
        case jobId = "job_id"
        case kind, status
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case error
        case resultPath = "result_path"
    }

    public var isRunning: Bool { status == "running" || status == "pending" }
    public var isCompleted: Bool { status == "completed" || status == "done" }
    public var isFailed: Bool { status == "failed" || status == "error" }
}

// MARK: - Triad (ATHENA / HERMES / ARGOS / Judge)

public struct TriadResult: Codable, Sendable {
    public let athena: TriadAgentOpinion?
    public let hermes: TriadAgentOpinion?
    public let argos: TriadAgentOpinion?
    public let judge: TriadAgentOpinion?
    public let consensus: String?
    public let scores: TriadScores?
}

public struct TriadAgentOpinion: Codable, Sendable {
    public let agent: String?
    public let opinion: String?
    public let confidence: Double?
    public let citations: [String]?
}

public struct TriadScores: Codable, Sendable {
    public let athena: Double?
    public let hermes: Double?
    public let argos: Double?
    public let judge: Double?
}

// MARK: - Thought Capture

public struct ThoughtCapture: Codable, Sendable, Identifiable {
    public var id: String { nodeId ?? UUID().uuidString }
    public let nodeId: String?
    public let refinedText: String?
    public let rawText: String?
    public let source: String?
    public let createdAt: String?
    public let syncedToServer: Bool?
    public let syncState: IdeaSyncState?

    enum CodingKeys: String, CodingKey {
        case nodeId = "node_id"
        case refinedText = "refined_text"
        case rawText = "raw_text"
        case source
        case createdAt = "created_at"
        case syncedToServer = "synced_to_server"
        case syncState
        case syncStateSnake = "sync_state"
    }

    public var residency: ThoughtResidency {
        if effectiveSyncState.isClusterResident { return .clusterMemory }
        return .deviceOnly
    }

    public var effectiveSyncState: IdeaSyncState {
        if let syncState { return syncState }
        if syncedToServer == true { return .synced }
        return .localOnly
    }

    public init(
        nodeId: String?,
        refinedText: String?,
        rawText: String?,
        source: String?,
        createdAt: String?,
        syncedToServer: Bool?,
        syncState: IdeaSyncState?
    ) {
        self.nodeId = nodeId
        self.refinedText = refinedText
        self.rawText = rawText
        self.source = source
        self.createdAt = createdAt
        self.syncedToServer = syncedToServer
        self.syncState = syncState
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        nodeId = try container.decodeIfPresent(String.self, forKey: .nodeId)
        refinedText = try container.decodeIfPresent(String.self, forKey: .refinedText)
        rawText = try container.decodeIfPresent(String.self, forKey: .rawText)
        source = try container.decodeIfPresent(String.self, forKey: .source)
        createdAt = try container.decodeIfPresent(String.self, forKey: .createdAt)
        syncedToServer = try container.decodeIfPresent(Bool.self, forKey: .syncedToServer)
        syncState =
            try container.decodeIfPresent(IdeaSyncState.self, forKey: .syncState)
            ?? container.decodeIfPresent(IdeaSyncState.self, forKey: .syncStateSnake)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(nodeId, forKey: .nodeId)
        try container.encodeIfPresent(refinedText, forKey: .refinedText)
        try container.encodeIfPresent(rawText, forKey: .rawText)
        try container.encodeIfPresent(source, forKey: .source)
        try container.encodeIfPresent(createdAt, forKey: .createdAt)
        try container.encodeIfPresent(syncedToServer, forKey: .syncedToServer)
        try container.encodeIfPresent(syncState, forKey: .syncState)
    }
}

public enum ThoughtResidency: String, Codable, Sendable {
    case deviceOnly
    case clusterMemory

    public var label: String {
        switch self {
        case .deviceOnly:
            return "Device only"
        case .clusterMemory:
            return "Cluster memory"
        }
    }
}

public enum IdeaSyncState: String, Codable, Sendable {
    case localOnly = "local_only"
    case queued
    case synced
    case delegated

    public var label: String {
        switch self {
        case .localOnly:
            return "Device only"
        case .queued:
            return "Queued"
        case .synced:
            return "Cluster memory"
        case .delegated:
            return "Delegated"
        }
    }

    public var systemImage: String {
        switch self {
        case .localOnly:
            return "iphone"
        case .queued:
            return "clock.arrow.circlepath"
        case .synced:
            return "server.rack"
        case .delegated:
            return "bolt.horizontal.circle"
        }
    }

    public var isClusterResident: Bool {
        switch self {
        case .localOnly, .queued:
            return false
        case .synced, .delegated:
            return true
        }
    }
}

public enum ProjectFamily: String, Codable, Sendable {
    case language
    case hsn
    case experimental
    case platform

    public static func fromProjectSlug(_ slug: String) -> ProjectFamily {
        switch slug.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "sounio":
            return .language
        case "hyperbolic-semantic-networks":
            return .hsn
        default:
            return .experimental
        }
    }
}

public enum DiscussionProfile: String, Codable, Sendable, CaseIterable, Identifiable {
    case cluster
    case qwen3b
    case yi6b

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .cluster:
            return "Cluster"
        case .qwen3b:
            return "Qwen"
        case .yi6b:
            return "Yi"
        }
    }

    public var subtitle: String {
        switch self {
        case .cluster:
            return "Default route"
        case .qwen3b:
            return "Daily / Cheap"
        case .yi6b:
            return "Bilingual / Creative"
        }
    }

    public var iconName: String {
        switch self {
        case .cluster:
            return "server.rack"
        case .qwen3b:
            return "bolt.horizontal.circle"
        case .yi6b:
            return "globe.asia.australia"
        }
    }
}

public enum PublicationScope: String, Codable, Sendable {
    case `public`
    case internalOnly = "internal"
    case conference
    case draft

    public static func forProjectFamily(_ family: ProjectFamily) -> PublicationScope {
        switch family {
        case .language:
            return .public
        case .hsn:
            return .conference
        case .experimental, .platform:
            return .internalOnly
        }
    }
}

// MARK: - HRV Response

public struct HRVResponse: Codable, Sendable {
    public let status: String?
    public let speedMultiplier: Double?

    enum CodingKeys: String, CodingKey {
        case status
        case speedMultiplier = "speed_multiplier"
    }
}

// MARK: - Cognitive State (aggregated)

public struct CognitiveState: Codable, Sendable {
    public let hrv: CognitiveHRV?
    public let recentDrafts: [CognitiveDraft]?
    public let triadLatest: CognitiveTriad?
    public let agentSessions: [AgentSession]?
    public let recentVoidJourneys: [VoidJourney]?
    public let recentFractalTrees: [FractalTree]?
    public let recentPhiMeasurements: [PhiMeasurement]?

    enum CodingKeys: String, CodingKey {
        case hrv
        case recentDrafts = "recent_drafts"
        case triadLatest = "triad_latest"
        case agentSessions = "agent_sessions"
        case recentVoidJourneys = "recent_void_journeys"
        case recentFractalTrees = "recent_fractal_trees"
        case recentPhiMeasurements = "recent_phi_measurements"
    }
}

// MARK: - Novelty Endpoints (Void, Fractal, Phi)

public struct VoidJourney: Codable, Sendable, Identifiable {
    public var id: String { journeyId ?? UUID().uuidString }
    public let journeyId: String?
    public let status: String?
    public let maxDepthReached: Double?
    public let durationMs: Int?
    public let insights: [String]?
    public let truthMode: String?

    enum CodingKeys: String, CodingKey {
        case journeyId = "journey_id"
        case status
        case maxDepthReached = "max_depth_reached"
        case durationMs = "duration_ms"
        case insights
        case truthMode = "truth_mode"
    }
}

public struct FractalTree: Codable, Sendable, Identifiable {
    public var id: String { rootId ?? UUID().uuidString }
    public let rootId: String?
    public let rootPrompt: String?
    public let maxDepth: Int?
    public let branching: Int?
    public let nodeCount: Int?
    public let generatedAt: String?
    public let durationMs: Int?
    public let truthMode: String?

    enum CodingKeys: String, CodingKey {
        case rootId = "root_id"
        case rootPrompt = "root_prompt"
        case maxDepth = "max_depth"
        case branching
        case nodeCount = "node_count"
        case generatedAt = "generated_at"
        case durationMs = "duration_ms"
        case truthMode = "truth_mode"
    }
}

public struct PhiMeasurement: Codable, Sendable, Identifiable {
    public var id: String { "\(measuredAt ?? UUID().uuidString)" }
    public let querySnippet: String?
    public let phi: Double?
    public let substrateSize: Int?
    public let mipPartition: [[String]]?
    public let awarenessLevel: String?
    public let routerTier: String?
    public let measuredAt: String?
    public let durationMs: Int?
    public let truthMode: String?

    enum CodingKeys: String, CodingKey {
        case querySnippet = "query_snippet"
        case phi
        case substrateSize = "substrate_size"
        case mipPartition = "mip_partition"
        case awarenessLevel = "awareness_level"
        case routerTier = "router_tier"
        case measuredAt = "measured_at"
        case durationMs = "duration_ms"
        case truthMode = "truth_mode"
    }
}

public struct CognitiveHRV: Codable, Sendable {
    public let latestMs: Double?
    public let flowState: String?
    public let observedAt: String?
    public let truthMode: String?

    enum CodingKeys: String, CodingKey {
        case latestMs = "latest_ms"
        case flowState = "flow_state"
        case observedAt = "observed_at"
        case truthMode = "truth_mode"
    }

    public var displayFlowState: String {
        flowState?.uppercased() ?? "UNKNOWN"
    }
}

public struct CognitiveDraft: Codable, Sendable, Identifiable {
    public var id: String { draftId ?? UUID().uuidString }
    public let draftId: String?
    public let kind: String?
    public let summary: String?
    public let createdAt: String?

    enum CodingKeys: String, CodingKey {
        case draftId = "id"
        case kind, summary
        case createdAt = "created_at"
    }
}

public struct CognitiveTriad: Codable, Sendable {
    public let runId: String?
    public let scores: TriadScores?
    public let verdict: String?

    enum CodingKeys: String, CodingKey {
        case runId = "run_id"
        case scores, verdict
    }
}

// MARK: - Hypergraph

public struct Hyperedge: Codable, Sendable, Identifiable {
    public var id: String { edgeId ?? UUID().uuidString }
    public let edgeId: String?
    public let label: String?
    public let nodeIds: [String]?
    public let metadata: [String: String]?
    public let directed: Bool?
    public let createdAt: String?

    enum CodingKeys: String, CodingKey {
        case edgeId = "id"
        case label
        case nodeIds = "node_ids"
        case metadata, directed
        case createdAt = "created_at"
    }
}

// MARK: - Feedback

public struct FeedbackEvent: Codable, Sendable {
    public let runId: String
    public let kind: String        // "human_feedback" | "pipeline_run" | "triad_completed"
    public let clarity: Int?       // 0-10
    public let adequacy: Int?      // 0-10
    public let safety: Int?        // 0-10
    public let notes: String?

    public init(runId: String, kind: String, clarity: Int? = nil, adequacy: Int? = nil, safety: Int? = nil, notes: String? = nil) {
        self.runId = runId
        self.kind = kind
        self.clarity = clarity
        self.adequacy = adequacy
        self.safety = safety
        self.notes = notes
    }

    enum CodingKeys: String, CodingKey {
        case runId = "run_id"
        case kind, clarity, adequacy, safety, notes
    }
}

public struct FeedbackAck: Codable, Sendable {
    public let ok: Bool?
    public let eventId: String?
    public let status: String?

    enum CodingKeys: String, CodingKey {
        case ok
        case eventId = "event_id"
        case status
    }
}

// MARK: - Chat (exocortex conversation)

public struct ChatResponse: Decodable, Sendable {
    public let response: String?
    public let tokensUsed: Int?
    public let model: String?
    public let source: String?
    public let agentKind: String?
    public let sessionId: String?
    public let podName: String?

    enum CodingKeys: String, CodingKey {
        case response
        case text
        case tokensUsed = "tokens_used"
        case model
        case provider
        case tier
        case source
        case agentKind
        case sessionId
        case podName
        case agentKindSnake = "agent_kind"
        case sessionIdSnake = "session_id"
        case podNameSnake = "pod_name"
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        response =
            try container.decodeIfPresent(String.self, forKey: .response)
            ?? container.decodeIfPresent(String.self, forKey: .text)
        tokensUsed = try container.decodeIfPresent(Int.self, forKey: .tokensUsed)
        model =
            try container.decodeIfPresent(String.self, forKey: .model)
            ?? container.decodeIfPresent(String.self, forKey: .provider)
            ?? container.decodeIfPresent(String.self, forKey: .tier)
        source = try container.decodeIfPresent(String.self, forKey: .source)
        agentKind =
            try container.decodeIfPresent(String.self, forKey: .agentKind)
            ?? container.decodeIfPresent(String.self, forKey: .agentKindSnake)
        sessionId =
            try container.decodeIfPresent(String.self, forKey: .sessionId)
            ?? container.decodeIfPresent(String.self, forKey: .sessionIdSnake)
        podName =
            try container.decodeIfPresent(String.self, forKey: .podName)
            ?? container.decodeIfPresent(String.self, forKey: .podNameSnake)
    }
}

// MARK: - HPC GPU Metrics

public struct GPUNodeMetric: Codable, Sendable, Identifiable {
    public var id: String { "\(node ?? "")-\(gpuId ?? 0)" }
    public let node: String?
    public let gpuId: Int?
    public let utilization: Double?    // 0-100
    public let memoryUsedMB: Double?
    public let temperatureC: Double?
    public let powerW: Double?

    enum CodingKeys: String, CodingKey {
        case node
        case gpuId = "gpu_id"
        case utilization
        case memoryUsedMB = "memory_used_mb"
        case temperatureC = "temperature_c"
        case powerW = "power_w"
    }
}

public struct HPCJob: Codable, Sendable, Identifiable {
    public var id: String { jobId ?? UUID().uuidString }
    public let jobId: String?
    public let kind: String?
    public let status: String?
    public let nodeList: String?
    public let gpuCount: Int?
    public let submitTime: String?
    public let startTime: String?
    public let endTime: String?
    public let stdout: String?

    enum CodingKeys: String, CodingKey {
        case jobId = "job_id"
        case kind, status
        case nodeList = "node_list"
        case gpuCount = "gpu_count"
        case submitTime = "submit_time"
        case startTime = "start_time"
        case endTime = "end_time"
        case stdout
    }

    public var isRunning: Bool { status == "running" || status == "pending" }
    public var isCompleted: Bool { status == "completed" || status == "done" }
}

public struct HPCJobQueue: Codable, Sendable {
    public let jobs: [HPCJob]?
    public let totalGPUs: Int?
    public let allocatedGPUs: Int?
    public let generatedAt: String?

    enum CodingKeys: String, CodingKey {
        case jobs
        case totalGPUs = "total_gpus"
        case allocatedGPUs = "allocated_gpus"
        case generatedAt = "generated_at"
    }
}

public struct JobArtifact: Codable, Sendable, Identifiable {
    public var id: String { path ?? UUID().uuidString }
    public let path: String?
    public let type: String?    // "csv", "image", "json", "surface3d"
    public let sizeBytes: Int?
    public let url: String?

    enum CodingKeys: String, CodingKey {
        case path, type
        case sizeBytes = "size_bytes"
        case url
    }
}

public struct BandwidthSample: Codable, Sendable {
    public let from: String?
    public let to: String?
    public let mbps: Double?
    public let timestamp: String?
}
