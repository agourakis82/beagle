//
//  CognitiveChatModels.swift
//  BeagleCore
//
//  Triad review, Round Table debates, thought capture & idea sync,
//  discussion profiles, exocortex chat, HRV, cognitive state, novelty
//  endpoints (Void/Fractal/Phi), hypergraph edges, and human feedback.
//

import Foundation

// MARK: - Triad (ATHENA / HERMES / ARGOS / Judge)

public struct TriadResult: Codable, Sendable {
    public let runId: String?
    public let athena: TriadAgentOpinion?
    public let hermes: TriadAgentOpinion?
    public let argos: TriadAgentOpinion?
    public let judge: TriadAgentOpinion?
    public let consensus: String?
    public let scores: TriadScores?

    enum CodingKeys: String, CodingKey {
        case runId = "run_id"
        case athena, hermes, argos, judge, consensus, scores
    }
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

// MARK: - Round Table (exotic model debate)

public struct RoundTableResult: Codable, Sendable {
    public let voices: [RoundTableVoice]?
    public let interference: RoundTableInterference?
    public let pciScore: Double?
    public let synthesis: String?

    public init(
        voices: [RoundTableVoice]? = nil,
        interference: RoundTableInterference? = nil,
        pciScore: Double? = nil,
        synthesis: String? = nil
    ) {
        self.voices = voices
        self.interference = interference
        self.pciScore = pciScore
        self.synthesis = synthesis
    }

    enum CodingKeys: String, CodingKey {
        case voices, interference, synthesis
        case pciScore = "pci_score"
    }
}

public struct RoundTableVoice: Codable, Sendable, Identifiable {
    public var id: String { name }
    public let name: String
    public let perspective: String?
    public let content: String

    public init(name: String, perspective: String? = nil, content: String) {
        self.name = name
        self.perspective = perspective
        self.content = content
    }
}

public struct RoundTableInterference: Codable, Sendable {
    public let constructive: [String]?
    public let destructive: [String]?
    public let emergentInsights: [String]?

    public init(
        constructive: [String]? = nil,
        destructive: [String]? = nil,
        emergentInsights: [String]? = nil
    ) {
        self.constructive = constructive
        self.destructive = destructive
        self.emergentInsights = emergentInsights
    }
}

// MARK: - Thought Capture & Idea Sync

public struct ThoughtCapture: Codable, Sendable, Identifiable {
    private let stableId: String
    public var id: String { nodeId ?? stableId }
    public let nodeId: String?
    public let refinedText: String?
    public let rawText: String?
    public let source: String?
    public let createdAt: String?
    public let syncedToServer: Bool?
    public let syncState: IdeaSyncState?

    /// English translation if the original thought was in Portuguese.
    public var translatedText: String?
    /// Detected language code (BCP-47), e.g. "pt", "en", "es".
    public var originalLanguage: String?

    /// Whether this thought has a bilingual translation available.
    public var isBilingual: Bool { translatedText != nil }

    /// The best text for international display: translation if available, otherwise refined/raw.
    public var internationalText: String? {
        translatedText ?? refinedText ?? rawText
    }

    enum CodingKeys: String, CodingKey {
        case nodeId = "node_id"
        case refinedText = "refined_text"
        case rawText = "raw_text"
        case source
        case createdAt = "created_at"
        case syncedToServer = "synced_to_server"
        case syncState
        case syncStateSnake = "sync_state"
        case translatedText = "translated_text"
        case originalLanguage = "original_language"
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
        syncState: IdeaSyncState?,
        translatedText: String? = nil,
        originalLanguage: String? = nil
    ) {
        self.stableId = UUID().uuidString
        self.nodeId = nodeId
        self.refinedText = refinedText
        self.rawText = rawText
        self.source = source
        self.createdAt = createdAt
        self.syncedToServer = syncedToServer
        self.syncState = syncState
        self.translatedText = translatedText
        self.originalLanguage = originalLanguage
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.stableId = UUID().uuidString
        nodeId = try container.decodeIfPresent(String.self, forKey: .nodeId)
        refinedText = try container.decodeIfPresent(String.self, forKey: .refinedText)
        rawText = try container.decodeIfPresent(String.self, forKey: .rawText)
        source = try container.decodeIfPresent(String.self, forKey: .source)
        createdAt = try container.decodeIfPresent(String.self, forKey: .createdAt)
        syncedToServer = try container.decodeIfPresent(Bool.self, forKey: .syncedToServer)
        syncState =
            try container.decodeIfPresent(IdeaSyncState.self, forKey: .syncState)
            ?? container.decodeIfPresent(IdeaSyncState.self, forKey: .syncStateSnake)
        translatedText = try container.decodeIfPresent(String.self, forKey: .translatedText)
        originalLanguage = try container.decodeIfPresent(String.self, forKey: .originalLanguage)
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
        try container.encodeIfPresent(translatedText, forKey: .translatedText)
        try container.encodeIfPresent(originalLanguage, forKey: .originalLanguage)
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

// MARK: - Discussion Profile & Chat (exocortex conversation)

public enum DiscussionProfile: String, Codable, Sendable, CaseIterable, Identifiable {
    case cluster
    case qwen3b
    case yi6b
    case grok
    case kimi
    case claudeCode = "claude-code"
    case codex

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .cluster:
            return "Cluster"
        case .qwen3b:
            return "Qwen"
        case .yi6b:
            return "Yi"
        case .grok:
            return "Grok"
        case .kimi:
            return "Kimi"
        case .claudeCode:
            return "Claude Code"
        case .codex:
            return "Codex"
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
        case .grok:
            return "Fast / xAI"
        case .kimi:
            return "Moonshot / OpenRouter"
        case .claudeCode:
            return "Max / Pro subscription"
        case .codex:
            return "ChatGPT Pro subscription"
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
        case .grok:
            return "sparkles.rectangle.stack"
        case .kimi:
            return "moon.stars"
        case .claudeCode:
            return "person.crop.circle.badge.sparkles"
        case .codex:
            return "terminal"
        }
    }
}

public struct ChatResponse: Decodable, Sendable {
    public let response: String?
    public let tokensUsed: Int?
    public let model: String?
    public let source: String?
    public let agentKind: String?
    public let sessionId: String?
    public let podName: String?
    public let conversationMode: String?
    public let appliedDiscussionProfile: String?
    public let flowState: String?

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
        case conversationMode = "conversation_mode"
        case appliedDiscussionProfile = "applied_discussion_profile"
        case flowState = "flow_state"
        case agentKindSnake = "agent_kind"
        case sessionIdSnake = "session_id"
        case podNameSnake = "pod_name"
    }

    public init(
        response: String?,
        tokensUsed: Int? = nil,
        model: String? = nil,
        source: String? = nil,
        agentKind: String? = nil,
        sessionId: String? = nil,
        podName: String? = nil,
        conversationMode: String? = nil,
        appliedDiscussionProfile: String? = nil,
        flowState: String? = nil
    ) {
        self.response = response
        self.tokensUsed = tokensUsed
        self.model = model
        self.source = source
        self.agentKind = agentKind
        self.sessionId = sessionId
        self.podName = podName
        self.conversationMode = conversationMode
        self.appliedDiscussionProfile = appliedDiscussionProfile
        self.flowState = flowState
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
        conversationMode = try container.decodeIfPresent(String.self, forKey: .conversationMode)
        appliedDiscussionProfile = try container.decodeIfPresent(String.self, forKey: .appliedDiscussionProfile)
        flowState = try container.decodeIfPresent(String.self, forKey: .flowState)
    }
}

// MARK: - HRV & Cognitive State (aggregated)

public struct HRVResponse: Codable, Sendable {
    public let status: String?
    public let speedMultiplier: Double?

    enum CodingKeys: String, CodingKey {
        case status
        case speedMultiplier = "speed_multiplier"
    }
}

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
    private let stableId: String = UUID().uuidString
    public var id: String { journeyId ?? stableId }
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
    private let stableId: String = UUID().uuidString
    public var id: String { rootId ?? stableId }
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
    private let stableId: String = UUID().uuidString
    public var id: String { "\(measuredAt ?? stableId)" }
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
    private let stableId: String = UUID().uuidString
    public var id: String { draftId ?? stableId }
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
    private let stableId: String = UUID().uuidString
    public var id: String { edgeId ?? stableId }
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
