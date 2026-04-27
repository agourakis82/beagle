//
//  ExocortexModels.swift
//  BeagleCore
//
//  Cluster-canonical Exocortex contracts shared by iPhone, iPad, macOS,
//  visionOS, Watch, and external MCP agents.
//

import Foundation

public enum ExocortexJSONValue: Codable, Equatable, Sendable {
    case string(String)
    case number(Double)
    case bool(Bool)
    case object([String: ExocortexJSONValue])
    case array([ExocortexJSONValue])
    case null

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Double.self) {
            self = .number(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode([String: ExocortexJSONValue].self) {
            self = .object(value)
        } else {
            self = .array(try container.decode([ExocortexJSONValue].self))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let value):
            try container.encode(value)
        case .number(let value):
            try container.encode(value)
        case .bool(let value):
            try container.encode(value)
        case .object(let value):
            try container.encode(value)
        case .array(let value):
            try container.encode(value)
        case .null:
            try container.encodeNil()
        }
    }
}

public struct ContextSnapshot: Codable, Equatable, Sendable {
    public let healthRef: String?
    public let activeProjectIds: [String]
    public let recentDecisionIds: [String]
    public let energyLevel: Double?
    public let emotionalValence: Double?
    public let platform: String?
    public let targetHardware: TargetHardware?

    enum CodingKeys: String, CodingKey {
        case healthRef = "health_ref"
        case activeProjectIds = "active_project_ids"
        case recentDecisionIds = "recent_decision_ids"
        case energyLevel = "energy_level"
        case emotionalValence = "emotional_valence"
        case platform
        case targetHardware = "target_hardware"
    }
}

public struct TargetHardware: Codable, Equatable, Sendable {
    public let phone: String?
    public let watch: String?
    public let tablet: String?
    public let desktop: String?
    public let spatial: String?
    public let notes: [String]
}

public struct ValueChange: Codable, Equatable, Sendable {
    public let value: String
    public let oldStrength: Double
    public let newStrength: Double

    enum CodingKeys: String, CodingKey {
        case value
        case oldStrength = "old_strength"
        case newStrength = "new_strength"
    }
}

public struct IdentityDelta: Codable, Equatable, Sendable {
    public let beliefsAdded: [String]
    public let beliefsRemoved: [String]
    public let valuesChanged: [ValueChange]
    public let cognitiveStyleShift: String?
    public let priorityReordering: [String]
    public let productPrinciples: [String]?

    enum CodingKeys: String, CodingKey {
        case beliefsAdded = "beliefs_added"
        case beliefsRemoved = "beliefs_removed"
        case valuesChanged = "values_changed"
        case cognitiveStyleShift = "cognitive_style_shift"
        case priorityReordering = "priority_reordering"
        case productPrinciples = "product_principles"
    }
}

public struct ChronoselfCommit: Codable, Equatable, Sendable, Identifiable {
    public let id: String
    public let createdAt: String
    public let selfVersion: String
    public let parentCommitIds: [String]
    public let userId: String
    public let contextSnapshot: ContextSnapshot
    public let identityDelta: IdentityDelta
    public let triggerType: String
    public let hash: String
    public let confidence: Double
    public let sourceRefs: [String]
    public let summary: String?

    enum CodingKeys: String, CodingKey {
        case id
        case createdAt = "created_at"
        case selfVersion = "self_version"
        case parentCommitIds = "parent_commit_ids"
        case userId = "user_id"
        case contextSnapshot = "context_snapshot"
        case identityDelta = "identity_delta"
        case triggerType = "trigger_type"
        case hash
        case confidence
        case sourceRefs = "source_refs"
        case summary
    }
}

public struct CoreValue: Codable, Equatable, Sendable {
    public let name: String
    public let strength: Double
}

public struct SelfVersion: Codable, Equatable, Sendable, Identifiable {
    public let id: String
    public let label: String
    public let periodStart: String
    public let periodEnd: String?
    public let dominantBeliefs: [String]
    public let coreValues: [CoreValue]
    public let cognitiveStyle: String
    public let riskTolerance: Double
    public let sourceCommitId: String?

    enum CodingKeys: String, CodingKey {
        case id
        case label
        case periodStart = "period_start"
        case periodEnd = "period_end"
        case dominantBeliefs = "dominant_beliefs"
        case coreValues = "core_values"
        case cognitiveStyle = "cognitive_style"
        case riskTolerance = "risk_tolerance"
        case sourceCommitId = "source_commit_id"
    }

    public static let bootstrap = SelfVersion(
        id: "v0.bootstrap",
        label: "Bootstrap Self",
        periodStart: "",
        periodEnd: nil,
        dominantBeliefs: ["Beagle is a cluster-first exocortex."],
        coreValues: [CoreValue(name: "continuity", strength: 1.0)],
        cognitiveStyle: "forming continuity",
        riskTolerance: 0.5,
        sourceCommitId: nil
    )
}

public struct OmniExtraction: Codable, Equatable, Sendable {
    public let keyInsights: [String]
    public let decisions: [String]
    public let hypotheses: [String]
    public let beliefChanges: [String]
    public let emotionalState: ExocortexJSONValue?
    public let identitySignals: ExocortexJSONValue?
    public let projectsMentioned: [String]
    public let unresolvedQuestions: [String]

    enum CodingKeys: String, CodingKey {
        case keyInsights = "key_insights"
        case decisions
        case hypotheses
        case beliefChanges = "belief_changes"
        case emotionalState = "emotional_state"
        case identitySignals = "identity_signals"
        case projectsMentioned = "projects_mentioned"
        case unresolvedQuestions = "unresolved_questions"
    }
}

public struct OmniConversation: Codable, Equatable, Sendable, Identifiable {
    public let id: String
    public let sourcePlatform: String
    public let importedAt: String
    public let sessionId: String?
    public let originalDate: String?
    public let rawContentRef: String
    public let extracted: OmniExtraction
    public let linkedChronoselfCommits: [String]
    public let linkedMemoryEvents: [String]
    public let confidenceScore: Double
    public let title: String?
    public let privacyClass: String?
    public let tags: [String]?
    public let metadata: ExocortexJSONValue?

    enum CodingKeys: String, CodingKey {
        case id
        case sourcePlatform = "source_platform"
        case importedAt = "imported_at"
        case sessionId = "session_id"
        case originalDate = "original_date"
        case rawContentRef = "raw_content_ref"
        case extracted
        case linkedChronoselfCommits = "linked_chronoself_commits"
        case linkedMemoryEvents = "linked_memory_events"
        case confidenceScore = "confidence_score"
        case title
        case privacyClass = "privacy_class"
        case tags
        case metadata
    }
}

public struct MemoryRelation: Codable, Equatable, Sendable {
    public let subject: String
    public let predicate: String
    public let object: String
    public let confidence: Double
}

public struct MemoryEpisode: Codable, Equatable, Sendable, Identifiable {
    public let id: String
    public let createdAt: String
    public let source: String
    public let sourcePlatform: String?
    public let sessionId: String?
    public let sourceRef: String
    public let contentHash: String
    public let privacyClass: String
    public let provenance: ExocortexJSONValue?
    public let tags: [String]
    public let title: String?
    public let linkedChronoselfCommits: [String]
    public let occurredAt: String?

    enum CodingKeys: String, CodingKey {
        case id
        case createdAt = "created_at"
        case source
        case sourcePlatform = "source_platform"
        case sessionId = "session_id"
        case sourceRef = "source_ref"
        case contentHash = "content_hash"
        case privacyClass = "privacy_class"
        case provenance
        case tags
        case title
        case linkedChronoselfCommits = "linked_chronoself_commits"
        case occurredAt = "occurred_at"
    }
}

public struct MemoryAtom: Codable, Equatable, Sendable, Identifiable {
    public let id: String
    public let createdAt: String
    public let episodeId: String
    public let atomType: String
    public let text: String
    public let normalizedText: String
    public let sourceRefs: [String]
    public let relations: [MemoryRelation]
    public let tags: [String]
    public let confidence: Double
    public let privacyClass: String
    public let occurredAt: String?

    enum CodingKeys: String, CodingKey {
        case id
        case createdAt = "created_at"
        case episodeId = "episode_id"
        case atomType = "atom_type"
        case text
        case normalizedText = "normalized_text"
        case sourceRefs = "source_refs"
        case relations
        case tags
        case confidence
        case privacyClass = "privacy_class"
        case occurredAt = "occurred_at"
    }
}

public struct MemoryProjectionRun: Codable, Equatable, Sendable, Identifiable {
    public let id: String
    public let createdAt: String
    public let schemaVersion: String
    public let sourceCount: Int
    public let episodesCreated: Int
    public let atomsCreated: Int
    public let duplicates: Int
    public let errors: [String]
    public let projectionHash: String
    public let status: String
    public let degradedReason: String

    enum CodingKeys: String, CodingKey {
        case id
        case createdAt = "created_at"
        case schemaVersion = "schema_version"
        case sourceCount = "source_count"
        case episodesCreated = "episodes_created"
        case atomsCreated = "atoms_created"
        case duplicates
        case errors
        case projectionHash = "projection_hash"
        case status
        case degradedReason = "degraded_reason"
    }
}

public struct MemoryProjectionStatus: Codable, Equatable, Sendable {
    public let status: String
    public let schemaVersion: String
    public let episodeCount: Int
    public let atomCount: Int
    public let latestRun: MemoryProjectionRun?
    public let freshness: String
    public let retrievalMode: String
    public let degradedReason: String

    enum CodingKeys: String, CodingKey {
        case status
        case schemaVersion = "schema_version"
        case episodeCount = "episode_count"
        case atomCount = "atom_count"
        case latestRun = "latest_run"
        case freshness
        case retrievalMode = "retrieval_mode"
        case degradedReason = "degraded_reason"
    }
}

public struct MemoryWorld: Codable, Equatable, Sendable, Identifiable {
    public let id: String
    public let createdAt: String
    public let worldType: String
    public let sourceRef: String
    public let title: String?
    public let merkleRoot: String
    public let validFrom: String?
    public let validUntil: String?
    public let nodeCount: Int
    public let edgeCount: Int
    public let runtimeHint: String
    public let tags: [String]
    public let provenance: ExocortexJSONValue?

    enum CodingKeys: String, CodingKey {
        case id
        case createdAt = "created_at"
        case worldType = "world_type"
        case sourceRef = "source_ref"
        case title
        case merkleRoot = "merkle_root"
        case validFrom = "valid_from"
        case validUntil = "valid_until"
        case nodeCount = "node_count"
        case edgeCount = "edge_count"
        case runtimeHint = "runtime_hint"
        case tags
        case provenance
    }
}

public struct MemoryCommunity: Codable, Equatable, Sendable, Identifiable {
    public let id: String
    public let label: String
    public let strategy: String
    public let nodeCount: Int
    public let score: Double
    public let summary: String

    enum CodingKeys: String, CodingKey {
        case id
        case label
        case strategy
        case nodeCount = "node_count"
        case score
        case summary
    }
}

public struct MemoryGraphRecentResponse: Codable, Equatable, Sendable {
    public let generatedAt: String
    public let status: MemoryProjectionStatus
    public let episodes: [MemoryEpisode]
    public let atoms: [MemoryAtom]
    public let relations: [MemoryRelation]
    public let worlds: [MemoryWorld]?
    public let communities: [MemoryCommunity]?
    public let provenance: ExocortexJSONValue?

    enum CodingKeys: String, CodingKey {
        case generatedAt = "generated_at"
        case status
        case episodes
        case atoms
        case relations
        case worlds
        case communities
        case provenance
    }
}

public struct GraphBakeoffMetrics: Codable, Equatable, Sendable {
    public let p95QueryMs: Double
    public let ingestLatencyMs: Double
    public let top5HitRate: Double
    public let multiHopAccuracy: Double
    public let provenanceQuality: Double
    public let rebuildSeconds: Double
    public let operationalComplexity: Double

    enum CodingKeys: String, CodingKey {
        case p95QueryMs = "p95_query_ms"
        case ingestLatencyMs = "ingest_latency_ms"
        case top5HitRate = "top5_hit_rate"
        case multiHopAccuracy = "multi_hop_accuracy"
        case provenanceQuality = "provenance_quality"
        case rebuildSeconds = "rebuild_seconds"
        case operationalComplexity = "operational_complexity"
    }
}

public struct GraphRuntimeCandidate: Codable, Equatable, Sendable, Identifiable {
    public var id: String { name }
    public let name: String
    public let runtimeKind: String
    public let status: String
    public let score: Double
    public let metrics: GraphBakeoffMetrics
    public let strengths: [String]
    public let risks: [String]
    public let promotionNotes: [String]

    enum CodingKeys: String, CodingKey {
        case name
        case runtimeKind = "runtime_kind"
        case status
        case score
        case metrics
        case strengths
        case risks
        case promotionNotes = "promotion_notes"
    }
}

public struct GraphBakeoffRun: Codable, Equatable, Sendable, Identifiable {
    public let id: String
    public let createdAt: String
    public let status: String
    public let schemaVersion: String
    public let dataset: ExocortexJSONValue?
    public let candidates: [GraphRuntimeCandidate]
    public let winner: String
    public let baseline: String
    public let reportRef: String
    public let degradedReason: String

    enum CodingKeys: String, CodingKey {
        case id
        case createdAt = "created_at"
        case status
        case schemaVersion = "schema_version"
        case dataset
        case candidates
        case winner
        case baseline
        case reportRef = "report_ref"
        case degradedReason = "degraded_reason"
    }
}

public struct GraphIndexRun: Codable, Equatable, Sendable, Identifiable {
    public let id: String
    public let createdAt: String
    public let schemaVersion: String
    public let runtime: String
    public let status: String
    public let episodesIndexed: Int
    public let atomsIndexed: Int
    public let worldsCreated: Int
    public let hyperedgesIndexed: Int
    public let merkleRoot: String
    public let degradedReason: String
    public let provenance: ExocortexJSONValue?

    enum CodingKeys: String, CodingKey {
        case id
        case createdAt = "created_at"
        case schemaVersion = "schema_version"
        case runtime
        case status
        case episodesIndexed = "episodes_indexed"
        case atomsIndexed = "atoms_indexed"
        case worldsCreated = "worlds_created"
        case hyperedgesIndexed = "hyperedges_indexed"
        case merkleRoot = "merkle_root"
        case degradedReason = "degraded_reason"
        case provenance
    }
}

public struct MemoryGraphStatus: Codable, Equatable, Sendable {
    public let generatedAt: String
    public let schemaVersion: String
    public let graphRuntime: String
    public let runtimeStatus: String
    public let retrievalMode: String
    public let canonicalStore: String
    public let projectionStatus: MemoryProjectionStatus
    public let latestBakeoff: GraphBakeoffRun?
    public let latestIndexRun: GraphIndexRun?
    public let worldCount: Int
    public let degradedReason: String

    enum CodingKeys: String, CodingKey {
        case generatedAt = "generated_at"
        case schemaVersion = "schema_version"
        case graphRuntime = "graph_runtime"
        case runtimeStatus = "runtime_status"
        case retrievalMode = "retrieval_mode"
        case canonicalStore = "canonical_store"
        case projectionStatus = "projection_status"
        case latestBakeoff = "latest_bakeoff"
        case latestIndexRun = "latest_index_run"
        case worldCount = "world_count"
        case degradedReason = "degraded_reason"
    }
}

public struct MemoryWorldsRecentResponse: Codable, Equatable, Sendable {
    public let generatedAt: String
    public let worlds: [MemoryWorld]
    public let graphStatus: MemoryGraphStatus

    enum CodingKeys: String, CodingKey {
        case generatedAt = "generated_at"
        case worlds
        case graphStatus = "graph_status"
    }
}

public struct ConversationAutoImportState: Codable, Equatable, Sendable {
    public let status: String
    public let sessionId: String?
    public let lastImportedAt: String?
    public let lastSummary: String?
    public let queuedCount: Int
    public let restrictedCount: Int
    public let lastError: String?

    public init(
        status: String,
        sessionId: String? = nil,
        lastImportedAt: String? = nil,
        lastSummary: String? = nil,
        queuedCount: Int = 0,
        restrictedCount: Int = 0,
        lastError: String? = nil
    ) {
        self.status = status
        self.sessionId = sessionId
        self.lastImportedAt = lastImportedAt
        self.lastSummary = lastSummary
        self.queuedCount = queuedCount
        self.restrictedCount = restrictedCount
        self.lastError = lastError
    }

    public static let idle = ConversationAutoImportState(status: "idle")

    enum CodingKeys: String, CodingKey {
        case status
        case sessionId = "session_id"
        case lastImportedAt = "last_imported_at"
        case lastSummary = "last_summary"
        case queuedCount = "queued_count"
        case restrictedCount = "restricted_count"
        case lastError = "last_error"
    }
}

public struct AgentWorkMemorySnapshot: Codable, Equatable, Sendable {
    public let projectSlug: String
    public let repo: String?
    public let branch: String?
    public let sessionId: String
    public let agentKind: String
    public let objective: String?
    public let planSummary: String?
    public let diffSummary: String?
    public let testsSummary: String?
    public let decisionSummary: String?
    public let createdAt: String

    public init(
        projectSlug: String,
        repo: String? = nil,
        branch: String? = nil,
        sessionId: String,
        agentKind: String,
        objective: String? = nil,
        planSummary: String? = nil,
        diffSummary: String? = nil,
        testsSummary: String? = nil,
        decisionSummary: String? = nil,
        createdAt: String
    ) {
        self.projectSlug = projectSlug
        self.repo = repo
        self.branch = branch
        self.sessionId = sessionId
        self.agentKind = agentKind
        self.objective = objective
        self.planSummary = planSummary
        self.diffSummary = diffSummary
        self.testsSummary = testsSummary
        self.decisionSummary = decisionSummary
        self.createdAt = createdAt
    }

    enum CodingKeys: String, CodingKey {
        case projectSlug = "project_slug"
        case repo
        case branch
        case sessionId = "session_id"
        case agentKind = "agent_kind"
        case objective
        case planSummary = "plan_summary"
        case diffSummary = "diff_summary"
        case testsSummary = "tests_summary"
        case decisionSummary = "decision_summary"
        case createdAt = "created_at"
    }
}

public struct GraphRagEvidence: Codable, Equatable, Sendable {
    public let atomId: String
    public let episodeId: String
    public let atomType: String
    public let text: String
    public let score: Double
    public let sourceRefs: [String]
    public let provenance: ExocortexJSONValue?

    enum CodingKeys: String, CodingKey {
        case atomId = "atom_id"
        case episodeId = "episode_id"
        case atomType = "atom_type"
        case text
        case score
        case sourceRefs = "source_refs"
        case provenance
    }
}

public struct GraphRagTemporalContext: Codable, Equatable, Sendable {
    public let newestEvidenceAt: String?
    public let oldestEvidenceAt: String?
    public let matchedEpisodeCount: Int

    enum CodingKeys: String, CodingKey {
        case newestEvidenceAt = "newest_evidence_at"
        case oldestEvidenceAt = "oldest_evidence_at"
        case matchedEpisodeCount = "matched_episode_count"
    }
}

public struct EvidenceGraphNode: Codable, Equatable, Sendable, Identifiable {
    public let id: String
    public let label: String
    public let nodeType: String
    public let score: Double
    public let provenance: ExocortexJSONValue?

    enum CodingKeys: String, CodingKey {
        case id
        case label
        case nodeType = "node_type"
        case score
        case provenance
    }
}

public struct EvidenceGraphEdge: Codable, Equatable, Sendable, Identifiable {
    public var id: String { "\(source)-\(predicate)-\(target)" }
    public let source: String
    public let target: String
    public let predicate: String
    public let confidence: Double
    public let provenance: ExocortexJSONValue?
}

public struct EvidenceGraph: Codable, Equatable, Sendable {
    public let nodes: [EvidenceGraphNode]
    public let edges: [EvidenceGraphEdge]
    public let temporary: Bool
    public let merkleRoot: String

    enum CodingKeys: String, CodingKey {
        case nodes
        case edges
        case temporary
        case merkleRoot = "merkle_root"
    }
}

public struct GraphRagCommunityContext: Codable, Equatable, Sendable {
    public let strategy: String
    public let selectedCommunities: [MemoryCommunity]
    public let degradedReason: String?

    enum CodingKeys: String, CodingKey {
        case strategy
        case selectedCommunities = "selected_communities"
        case degradedReason = "degraded_reason"
    }
}

public struct RetrievalTraceStep: Codable, Equatable, Sendable, Identifiable {
    public var id: String { "\(stage)-\(backend)-\(items)" }
    public let stage: String
    public let backend: String
    public let status: String
    public let items: Int
    public let latencyMs: Double
    public let notes: [String]

    enum CodingKeys: String, CodingKey {
        case stage
        case backend
        case status
        case items
        case latencyMs = "latency_ms"
        case notes
    }
}

public struct GraphRagQueryResponse: Codable, Equatable, Sendable {
    public let summary: String
    public let evidence: [GraphRagEvidence]
    public let atoms: [MemoryAtom]
    public let episodes: [MemoryEpisode]
    public let relations: [MemoryRelation]
    public let temporalContext: GraphRagTemporalContext
    public let provenance: ExocortexJSONValue?
    public let confidence: Double
    public let degradedReason: String?
    public let mode: String?
    public let graphRuntime: String?
    public let evidenceGraph: EvidenceGraph?
    public let communityContext: GraphRagCommunityContext?
    public let retrievalTrace: [RetrievalTraceStep]?

    enum CodingKeys: String, CodingKey {
        case summary
        case evidence
        case atoms
        case episodes
        case relations
        case temporalContext = "temporal_context"
        case provenance
        case confidence
        case degradedReason = "degraded_reason"
        case mode
        case graphRuntime = "graph_runtime"
        case evidenceGraph = "evidence_graph"
        case communityContext = "community_context"
        case retrievalTrace = "retrieval_trace"
    }
}

public struct ExocortexAuditEvent: Codable, Equatable, Sendable, Identifiable {
    public let id: String
    public let createdAt: String
    public let clientId: String
    public let action: String
    public let toolName: String?
    public let riskLevel: String
    public let requiredScopes: [String]
    public let grantedScopes: [String]
    public let status: String
    public let source: String
    public let targetRef: String?
    public let summary: String?
    public let metadata: ExocortexJSONValue?

    enum CodingKeys: String, CodingKey {
        case id
        case createdAt = "created_at"
        case clientId = "client_id"
        case action
        case toolName = "tool_name"
        case riskLevel = "risk_level"
        case requiredScopes = "required_scopes"
        case grantedScopes = "granted_scopes"
        case status
        case source
        case targetRef = "target_ref"
        case summary
        case metadata
    }
}

public struct ExocortexMemoryEvent: Codable, Equatable, Sendable, Identifiable {
    public let id: String
    public let createdAt: String
    public let source: String
    public let kind: String
    public let contentRef: String?
    public let summary: String
    public let tags: [String]
    public let metadata: ExocortexJSONValue?
    public let linkedChronoselfCommits: [String]
    public let confidence: Double

    enum CodingKeys: String, CodingKey {
        case id
        case createdAt = "created_at"
        case source
        case kind
        case contentRef = "content_ref"
        case summary
        case tags
        case metadata
        case linkedChronoselfCommits = "linked_chronoself_commits"
        case confidence
    }
}

public struct AssistedImportTurn: Codable, Equatable, Sendable {
    public let role: String
    public let content: String
    public let timestamp: String?
    public let model: String?

    public init(role: String, content: String, timestamp: String? = nil, model: String? = nil) {
        self.role = role
        self.content = content
        self.timestamp = timestamp
        self.model = model
    }
}

public struct AssistedImportBatchRequest: Codable, Equatable, Sendable {
    public let sourcePlatform: String
    public let sourceSurface: String
    public let importScope: String
    public let sessionId: String
    public let projectRef: String?
    public let batchIndex: Int
    public let batchTotal: Int
    public let turns: [AssistedImportTurn]
    public let tags: [String]
    public let metadata: ExocortexJSONValue?
    public let coverage: ExocortexJSONValue?
    public let extracted: OmniExtraction?
    public let privacyClass: String
    public let title: String?
    public let originalDate: String?
    public let confidenceScore: Double?
    public let createChronoselfCommit: Bool?

    public init(
        sourcePlatform: String,
        sourceSurface: String = "beagle-apple-app",
        importScope: String = "current_conversation",
        sessionId: String,
        projectRef: String? = nil,
        batchIndex: Int = 1,
        batchTotal: Int = 1,
        turns: [AssistedImportTurn],
        tags: [String] = [],
        metadata: ExocortexJSONValue? = nil,
        coverage: ExocortexJSONValue? = nil,
        extracted: OmniExtraction? = nil,
        privacyClass: String = "sensitive",
        title: String? = nil,
        originalDate: String? = nil,
        confidenceScore: Double? = nil,
        createChronoselfCommit: Bool? = false
    ) {
        self.sourcePlatform = sourcePlatform
        self.sourceSurface = sourceSurface
        self.importScope = importScope
        self.sessionId = sessionId
        self.projectRef = projectRef
        self.batchIndex = batchIndex
        self.batchTotal = batchTotal
        self.turns = turns
        self.tags = tags
        self.metadata = metadata
        self.coverage = coverage
        self.extracted = extracted
        self.privacyClass = privacyClass
        self.title = title
        self.originalDate = originalDate
        self.confidenceScore = confidenceScore
        self.createChronoselfCommit = createChronoselfCommit
    }

    enum CodingKeys: String, CodingKey {
        case sourcePlatform = "source_platform"
        case sourceSurface = "source_surface"
        case importScope = "import_scope"
        case sessionId = "session_id"
        case projectRef = "project_ref"
        case batchIndex = "batch_index"
        case batchTotal = "batch_total"
        case turns
        case tags
        case metadata
        case coverage
        case extracted
        case privacyClass = "privacy_class"
        case title
        case originalDate = "original_date"
        case confidenceScore = "confidence_score"
        case createChronoselfCommit = "create_chronoself_commit"
    }
}

public struct AssistedImportBatchResult: Codable, Equatable, Sendable {
    public let status: String
    public let reason: String?
    public let sessionId: String
    public let sourcePlatform: String
    public let sourceSurface: String
    public let batchIndex: Int
    public let batchTotal: Int
    public let privacyClass: String
    public let omnimemory: OmniConversation?
    public let projection: MemoryProjectionRun?
    public let memoryEvent: ExocortexMemoryEvent?
    public let auditEvent: ExocortexAuditEvent?

    enum CodingKeys: String, CodingKey {
        case status
        case reason
        case sessionId = "session_id"
        case sourcePlatform = "source_platform"
        case sourceSurface = "source_surface"
        case batchIndex = "batch_index"
        case batchTotal = "batch_total"
        case privacyClass = "privacy_class"
        case omnimemory
        case projection
        case memoryEvent = "memory_event"
        case auditEvent = "audit_event"
    }
}

public struct TemporalPhase: Codable, Equatable, Sendable {
    public let name: String
    public let periodStart: String
    public let periodEnd: String?
    public let characteristics: [String]
    public let selfVersionRef: String?

    enum CodingKeys: String, CodingKey {
        case name
        case periodStart = "period_start"
        case periodEnd = "period_end"
        case characteristics
        case selfVersionRef = "self_version_ref"
    }
}

public struct TurningPoint: Codable, Equatable, Sendable {
    public let date: String
    public let description: String
    public let cause: String?
    public let selfVersionBefore: String?
    public let selfVersionAfter: String?

    enum CodingKeys: String, CodingKey {
        case date
        case description
        case cause
        case selfVersionBefore = "self_version_before"
        case selfVersionAfter = "self_version_after"
    }
}

public struct RecurringPattern: Codable, Equatable, Sendable {
    public let description: String
    public let frequencyDays: Double?
    public let confidence: Double

    enum CodingKeys: String, CodingKey {
        case description
        case frequencyDays = "frequency_days"
        case confidence
    }
}

public struct TemporalAnalysis: Codable, Equatable, Sendable, Identifiable {
    public let id: String
    public let createdAt: String
    public let topic: String
    public let timeRangeStart: String
    public let timeRangeEnd: String
    public let phases: [TemporalPhase]
    public let turningPoints: [TurningPoint]
    public let recurringPattern: RecurringPattern?
    public let causalHypothesis: String?
    public let recommendation: String
    public let llmModelUsed: String?
    public let confidenceScore: Double
    public let sourceRefs: [String]

    enum CodingKeys: String, CodingKey {
        case id
        case createdAt = "created_at"
        case topic
        case timeRangeStart = "time_range_start"
        case timeRangeEnd = "time_range_end"
        case phases
        case turningPoints = "turning_points"
        case recurringPattern = "recurring_pattern"
        case causalHypothesis = "causal_hypothesis"
        case recommendation
        case llmModelUsed = "llm_model_used"
        case confidenceScore = "confidence_score"
        case sourceRefs = "source_refs"
    }
}

public struct AgentContext: Codable, Equatable, Sendable {
    public let activeSessions: Int
    public let recentObservations: [String]
    public let lastAgentWrite: String?
    public let mcpStatus: String

    enum CodingKeys: String, CodingKey {
        case activeSessions = "active_sessions"
        case recentObservations = "recent_observations"
        case lastAgentWrite = "last_agent_write"
        case mcpStatus = "mcp_status"
    }
}

public struct TrustContext: Codable, Equatable, Sendable {
    public let mcpStatus: String
    public let activeScopes: [String]
    public let auditFreshness: String
    public let destructiveActions: String
    public let toolManifestHash: String?
    public let lastAuditEventId: String?
    public let memoryProjectionStatus: MemoryProjectionStatus?
    public let graphRuntime: String?
    public let retrievalMode: String?
    public let lastWorldHash: String?
    public let latestAgentWrite: String?
    public let graphDegradedReason: String?

    enum CodingKeys: String, CodingKey {
        case mcpStatus = "mcp_status"
        case activeScopes = "active_scopes"
        case auditFreshness = "audit_freshness"
        case destructiveActions = "destructive_actions"
        case toolManifestHash = "tool_manifest_hash"
        case lastAuditEventId = "last_audit_event_id"
        case memoryProjectionStatus = "memory_projection_status"
        case graphRuntime = "graph_runtime"
        case retrievalMode = "retrieval_mode"
        case lastWorldHash = "last_world_hash"
        case latestAgentWrite = "latest_agent_write"
        case graphDegradedReason = "graph_degraded_reason"
    }
}

public struct ExocortexHomeSnapshot: Codable, Equatable, Sendable {
    public let generatedAt: String
    public let todayBrief: String
    public let currentSelf: SelfVersion
    public let memorySignals: [String]
    public let openLoops: [String]
    public let activeProjectRef: String?
    public let bodyContext: String?
    public let recommendedNextAction: String
    public let clusterTruth: String
    public let omnimemoryStatus: String
    public let temporalPhase: String?
    public let agentContext: AgentContext?
    public let trustContext: TrustContext?

    enum CodingKeys: String, CodingKey {
        case generatedAt = "generated_at"
        case todayBrief = "today_brief"
        case currentSelf = "current_self"
        case memorySignals = "memory_signals"
        case openLoops = "open_loops"
        case activeProjectRef = "active_project_ref"
        case bodyContext = "body_context"
        case recommendedNextAction = "recommended_next_action"
        case clusterTruth = "cluster_truth"
        case omnimemoryStatus = "omnimemory_status"
        case temporalPhase = "temporal_phase"
        case agentContext = "agent_context"
        case trustContext = "trust_context"
    }

    public static let bootstrap = ExocortexHomeSnapshot(
        generatedAt: "",
        todayBrief: "O cluster ainda não enviou um snapshot vivo.",
        currentSelf: .bootstrap,
        memorySignals: [],
        openLoops: [],
        activeProjectRef: nil,
        bodyContext: nil,
        recommendedNextAction: "Conectar ao cluster e recuperar a Home Exocortex.",
        clusterTruth: "declared",
        omnimemoryStatus: "unknown",
        temporalPhase: nil,
        agentContext: nil,
        trustContext: nil
    )
}
