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

    enum CodingKeys: String, CodingKey {
        case nodeId = "node_id"
        case refinedText = "refined_text"
        case rawText = "raw_text"
        case source
        case createdAt = "created_at"
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

    enum CodingKeys: String, CodingKey {
        case response
        case text
        case tokensUsed = "tokens_used"
        case model
        case provider
        case tier
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
