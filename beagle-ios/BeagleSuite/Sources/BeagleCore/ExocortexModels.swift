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

public struct MemoryCandidate: Codable, Equatable, Sendable, Identifiable {
    public let id: String
    public let createdAt: String
    public let candidateType: String
    public let text: String
    public let normalizedText: String
    public let sourceRefs: [String]
    public let relations: [MemoryRelation]
    public let tags: [String]
    public let provenance: ExocortexJSONValue?
    public let confidence: Double
    public let privacyClass: String
    public let status: String
    public let quorumRef: String?
    public let promotedAtomId: String?

    enum CodingKeys: String, CodingKey {
        case id
        case createdAt = "created_at"
        case candidateType = "candidate_type"
        case text
        case normalizedText = "normalized_text"
        case sourceRefs = "source_refs"
        case relations
        case tags
        case provenance
        case confidence
        case privacyClass = "privacy_class"
        case status
        case quorumRef = "quorum_ref"
        case promotedAtomId = "promoted_atom_id"
    }
}

public struct MemoryCandidateListResponse: Codable, Equatable, Sendable {
    public let candidates: [MemoryCandidate]
}

public struct CandidateQuorumDecision: Codable, Equatable, Sendable, Identifiable {
    public let id: String
    public let createdAt: String
    public let candidateId: String
    public let memoryApproved: Bool
    public let temporalApproved: Bool
    public let criticalApproved: Bool
    public let status: String
    public let rationale: String
    public let reviewer: String?
    public let qualityScore: MemoryQualityScore?

    enum CodingKeys: String, CodingKey {
        case id
        case createdAt = "created_at"
        case candidateId = "candidate_id"
        case memoryApproved = "memory_approved"
        case temporalApproved = "temporal_approved"
        case criticalApproved = "critical_approved"
        case status
        case rationale
        case reviewer
        case qualityScore = "quality_score"
    }
}

public struct MemoryQualityScore: Codable, Equatable, Sendable, Identifiable {
    public let id: String
    public let createdAt: String
    public let candidateId: String
    public let provenanceScore: Double
    public let temporalScore: Double
    public let criticalScore: Double
    public let restrictedRisk: Double
    public let contradictionRisk: Double
    public let overall: Double
    public let rationale: String
    public var contradictionPenalty: Double { contradictionRisk }

    enum CodingKeys: String, CodingKey {
        case id
        case createdAt = "created_at"
        case candidateId = "candidate_id"
        case provenanceScore = "provenance_score"
        case temporalScore = "temporal_score"
        case criticalScore = "critical_score"
        case restrictedRisk = "restricted_risk"
        case contradictionRisk = "contradiction_risk"
        case overall
        case rationale
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        createdAt = try container.decode(String.self, forKey: .createdAt)
        candidateId = try container.decode(String.self, forKey: .candidateId)
        provenanceScore = try container.decode(Double.self, forKey: .provenanceScore)
        temporalScore = try container.decode(Double.self, forKey: .temporalScore)
        criticalScore = try container.decode(Double.self, forKey: .criticalScore)
        restrictedRisk = try container.decode(Double.self, forKey: .restrictedRisk)
        contradictionRisk = try container.decode(Double.self, forKey: .contradictionRisk)
        overall = try container.decode(Double.self, forKey: .overall)
        rationale = try container.decode(String.self, forKey: .rationale)
    }
}

public struct MemoryContradiction: Codable, Equatable, Sendable, Identifiable {
    public let id: String
    public let createdAt: String
    public let subjectRef: String
    public let conflictingRef: String
    public let description: String
    public let severity: String
    public let evidenceRefs: [String]
    public let status: String
    public let detectedBy: String

    enum CodingKeys: String, CodingKey {
        case id
        case createdAt = "created_at"
        case subjectRef = "subject_ref"
        case conflictingRef = "conflicting_ref"
        case description
        case severity
        case evidenceRefs = "evidence_refs"
        case status
        case detectedBy = "detected_by"
    }
}

public struct MemoryContradictionListResponse: Codable, Equatable, Sendable {
    public let contradictions: [MemoryContradiction]
}

public struct MemoryPromotionDecision: Codable, Equatable, Sendable, Identifiable {
    public let id: String
    public let createdAt: String
    public let candidateId: String
    public let quorumId: String?
    public let decision: String
    public let status: String
    public let promotedAtomId: String?
    public let qualityScore: MemoryQualityScore?
    public let rationale: String
    public let reviewer: String?
    public let evidenceRefs: [String]

    enum CodingKeys: String, CodingKey {
        case id
        case createdAt = "created_at"
        case candidateId = "candidate_id"
        case quorumId = "quorum_id"
        case decision
        case status
        case promotedAtomId = "promoted_atom_id"
        case qualityScore = "quality_score"
        case rationale
        case reviewer
        case evidenceRefs = "evidence_refs"
    }
}

public struct MemoryGovernanceRun: Codable, Equatable, Sendable, Identifiable {
    public let id: String
    public let createdAt: String
    public let schemaVersion: String
    public let status: String
    public let candidatesEvaluated: Int
    public let triadPending: Int
    public let promoted: Int
    public let rejected: Int
    public let contradictionsFound: Int
    public let qualityScoresWritten: Int
    public let hardGates: ExocortexJSONValue?
    public let degradedReason: String

    enum CodingKeys: String, CodingKey {
        case id
        case createdAt = "created_at"
        case schemaVersion = "schema_version"
        case status
        case candidatesEvaluated = "candidates_evaluated"
        case triadPending = "triad_pending"
        case promoted
        case rejected
        case contradictionsFound = "contradictions_found"
        case qualityScoresWritten = "quality_scores_written"
        case hardGates = "hard_gates"
        case degradedReason = "degraded_reason"
    }
}

public struct MemoryGovernanceStatus: Codable, Equatable, Sendable {
    public let schemaVersion: String
    public let status: String
    public let retrievalPolicy: String?
    public let latestRun: MemoryGovernanceRun?
    public let candidateCount: Int
    public let pendingTriads: Int
    public let promotedCount: Int
    public let rejectedCount: Int
    public let openContradictions: Int
    public let latestPromotionDecision: MemoryPromotionDecision?

    enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case status
        case retrievalPolicy = "retrieval_policy"
        case latestRun = "latest_run"
        case candidateCount = "candidate_count"
        case pendingTriads = "pending_triads"
        case promotedCount = "promoted_count"
        case rejectedCount = "rejected_count"
        case openContradictions = "open_contradictions"
        case latestPromotionDecision = "latest_promotion_decision"
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

public struct MemoryBenchmarkMetricSet: Codable, Equatable, Sendable {
    public let topKHitRate: Double?
    public let exactSupport: Double?
    public let multiHopCorrectness: Double?
    public let temporalCorrectness: Double?
    public let provenanceCompleteness: Double?
    public let contradictionSafety: Double?
    public let implicitRecall: Double?
    public let restrictedLeakCount: Int?
    public let p95LatencyMs: Double?
    public let blindJudgeDepth: Double?

    enum CodingKeys: String, CodingKey {
        case topKHitRate = "top_k_hit_rate"
        case exactSupport = "exact_support"
        case multiHopCorrectness = "multi_hop_correctness"
        case temporalCorrectness = "temporal_correctness"
        case provenanceCompleteness = "provenance_completeness"
        case contradictionSafety = "contradiction_safety"
        case implicitRecall = "implicit_recall"
        case restrictedLeakCount = "restricted_leak_count"
        case p95LatencyMs = "p95_latency_ms"
        case blindJudgeDepth = "blind_judge_depth"
    }
}

public struct MemoryBenchmarkModeResult: Codable, Equatable, Sendable, Identifiable {
    public var id: String { mode }
    public let mode: String
    public let status: String
    public let score: Double
    public let metrics: MemoryBenchmarkMetricSet?
    public let notes: [String]

    enum CodingKeys: String, CodingKey {
        case mode
        case status
        case score
        case metrics
        case notes
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        mode = try container.decode(String.self, forKey: .mode)
        status = try container.decode(String.self, forKey: .status)
        score = try container.decodeIfPresent(Double.self, forKey: .score) ?? 0
        metrics = try container.decodeIfPresent(MemoryBenchmarkMetricSet.self, forKey: .metrics)
        notes = try container.decodeIfPresent([String].self, forKey: .notes) ?? []
    }
}

public struct MemoryPromotionGate: Codable, Equatable, Sendable {
    public let baselineMode: String
    public let candidateMode: String
    public let requiredMargin: Double
    public let baselineScore: Double?
    public let candidateScore: Double?
    public let consecutivePassingRuns: Int
    public let requiredConsecutiveRuns: Int
    public let hardGatesPassed: Bool
    public let eligible: Bool
    public let rationale: String

    enum CodingKeys: String, CodingKey {
        case baselineMode = "baseline_mode"
        case candidateMode = "candidate_mode"
        case requiredMargin = "required_margin"
        case baselineScore = "baseline_score"
        case candidateScore = "candidate_score"
        case consecutivePassingRuns = "consecutive_passing_runs"
        case requiredConsecutiveRuns = "required_consecutive_runs"
        case hardGatesPassed = "hard_gates_passed"
        case eligible
        case rationale
    }
}

public struct MemoryTruthJudgment: Codable, Equatable, Sendable, Identifiable {
    public var id: String { caseId }
    public let caseId: String
    public let domain: String
    public let query: String
    public let passed: Bool
    public let score: Double
    public let baselineSupport: Double
    public let candidateSupport: Double
    public let regression: Bool
    public let supportingRefs: [String]
    public let notes: [String]

    enum CodingKeys: String, CodingKey {
        case caseId = "case_id"
        case domain
        case query
        case passed
        case score
        case baselineSupport = "baseline_support"
        case candidateSupport = "candidate_support"
        case regression
        case supportingRefs = "supporting_refs"
        case notes
    }
}

public struct MemoryBenchmarkRun: Codable, Equatable, Sendable, Identifiable {
    public let id: String
    public let createdAt: String
    public let status: String
    public let schemaVersion: String
    public let truthsetId: String?
    public let queryCount: Int
    public let domains: [String]
    public let judgeMode: String?
    public let baselineMode: String?
    public let candidateModes: [String]
    public let hardGates: [String: Bool]
    public let modeResults: [MemoryBenchmarkModeResult]
    public let caseJudgments: [MemoryTruthJudgment]
    public let winningMode: String?
    public let regressionCount: Int
    public let promotionGate: MemoryPromotionGate?
    public let hotPathEligible: Bool
    public let artifactManifest: String?
    public let degradedReason: String?

    enum CodingKeys: String, CodingKey {
        case id
        case createdAt = "created_at"
        case status
        case schemaVersion = "schema_version"
        case truthsetId = "truthset_id"
        case queryCount = "query_count"
        case domains
        case judgeMode = "judge_mode"
        case baselineMode = "baseline_mode"
        case candidateModes = "candidate_modes"
        case hardGates = "hard_gates"
        case modeResults = "mode_results"
        case caseJudgments = "case_judgments"
        case winningMode = "winning_mode"
        case regressionCount = "regression_count"
        case promotionGate = "promotion_gate"
        case hotPathEligible = "hot_path_eligible"
        case artifactManifest = "artifact_manifest"
        case degradedReason = "degraded_reason"
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        createdAt = try container.decode(String.self, forKey: .createdAt)
        status = try container.decode(String.self, forKey: .status)
        schemaVersion = try container.decode(String.self, forKey: .schemaVersion)
        truthsetId = try container.decodeIfPresent(String.self, forKey: .truthsetId)
        queryCount = try container.decodeIfPresent(Int.self, forKey: .queryCount) ?? 0
        domains = try container.decodeIfPresent([String].self, forKey: .domains) ?? []
        judgeMode = try container.decodeIfPresent(String.self, forKey: .judgeMode)
        baselineMode = try container.decodeIfPresent(String.self, forKey: .baselineMode)
        candidateModes = try container.decodeIfPresent([String].self, forKey: .candidateModes) ?? []
        hardGates = try container.decodeIfPresent([String: Bool].self, forKey: .hardGates) ?? [:]
        modeResults = try container.decodeIfPresent([MemoryBenchmarkModeResult].self, forKey: .modeResults) ?? []
        caseJudgments = try container.decodeIfPresent([MemoryTruthJudgment].self, forKey: .caseJudgments) ?? []
        winningMode = try container.decodeIfPresent(String.self, forKey: .winningMode)
        regressionCount = try container.decodeIfPresent(Int.self, forKey: .regressionCount) ?? 0
        promotionGate = try container.decodeIfPresent(MemoryPromotionGate.self, forKey: .promotionGate)
        hotPathEligible = try container.decodeIfPresent(Bool.self, forKey: .hotPathEligible) ?? false
        artifactManifest = try container.decodeIfPresent(String.self, forKey: .artifactManifest)
        degradedReason = try container.decodeIfPresent(String.self, forKey: .degradedReason)
    }
}

public struct MemoryBenchmarkStatus: Codable, Equatable, Sendable {
    public let generatedAt: String
    public let schemaVersion: String
    public let status: String
    public let latestRunId: String?
    public let latestScore: Double?
    public let queryCount: Int
    public let hardGates: [String: Bool]
    public let evaluatedModes: [String]
    public let regressionCount: Int
    public let artifactManifest: String?
    public let degradedReason: String?
    public let latestRun: MemoryBenchmarkRun?
    public let truthsetId: String?
    public let promotionGate: MemoryPromotionGate?
    public let hotPathEligible: Bool
    public let provisionalHotPath: Bool
    public let hotPathMode: String?
    public let confirmedPassingRuns: Int
    public let portfolioTruthsetId: String?

    enum CodingKeys: String, CodingKey {
        case generatedAt = "generated_at"
        case schemaVersion = "schema_version"
        case status
        case latestRunId = "latest_run_id"
        case latestScore = "latest_score"
        case queryCount = "query_count"
        case hardGates = "hard_gates"
        case evaluatedModes = "evaluated_modes"
        case regressionCount = "regression_count"
        case artifactManifest = "artifact_manifest"
        case degradedReason = "degraded_reason"
        case latestRun = "latest_run"
        case truthsetId = "truthset_id"
        case promotionGate = "promotion_gate"
        case hotPathEligible = "hot_path_eligible"
        case provisionalHotPath = "provisional_hot_path"
        case hotPathMode = "hot_path_mode"
        case confirmedPassingRuns = "confirmed_passing_runs"
        case portfolioTruthsetId = "portfolio_truthset_id"
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        generatedAt = try container.decodeIfPresent(String.self, forKey: .generatedAt) ?? ""
        schemaVersion = try container.decodeIfPresent(String.self, forKey: .schemaVersion) ?? "beagle-memory-bench-hypermemory-v1.8"
        status = try container.decodeIfPresent(String.self, forKey: .status) ?? "empty"
        latestRunId = try container.decodeIfPresent(String.self, forKey: .latestRunId)
        latestScore = try container.decodeIfPresent(Double.self, forKey: .latestScore)
        queryCount = try container.decodeIfPresent(Int.self, forKey: .queryCount) ?? 0
        hardGates = try container.decodeIfPresent([String: Bool].self, forKey: .hardGates) ?? [:]
        evaluatedModes = try container.decodeIfPresent([String].self, forKey: .evaluatedModes) ?? []
        regressionCount = try container.decodeIfPresent(Int.self, forKey: .regressionCount) ?? 0
        artifactManifest = try container.decodeIfPresent(String.self, forKey: .artifactManifest)
        degradedReason = try container.decodeIfPresent(String.self, forKey: .degradedReason)
        latestRun = try container.decodeIfPresent(MemoryBenchmarkRun.self, forKey: .latestRun)
        truthsetId = try container.decodeIfPresent(String.self, forKey: .truthsetId)
        promotionGate = try container.decodeIfPresent(MemoryPromotionGate.self, forKey: .promotionGate)
        hotPathEligible = try container.decodeIfPresent(Bool.self, forKey: .hotPathEligible) ?? false
        provisionalHotPath = try container.decodeIfPresent(Bool.self, forKey: .provisionalHotPath) ?? false
        hotPathMode = try container.decodeIfPresent(String.self, forKey: .hotPathMode)
        confirmedPassingRuns = try container.decodeIfPresent(Int.self, forKey: .confirmedPassingRuns) ?? 0
        portfolioTruthsetId = try container.decodeIfPresent(String.self, forKey: .portfolioTruthsetId)
    }
}

public struct HotPathMode: Codable, Equatable, Sendable, RawRepresentable {
    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        rawValue = try container.decode(String.self)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

public struct PortfolioTruthGate: Codable, Equatable, Sendable {
    public let truthsetId: String?
    public let portfolioTruthsetId: String?
    public let hotPathMode: String?
    public let provisionalHotPath: Bool
    public let confirmedPassing: Bool
    public let requiredConfirmedRuns: Int?
    public let requiredMargin: Double?
    public let policy: String?

    enum CodingKeys: String, CodingKey {
        case truthsetId = "truthset_id"
        case portfolioTruthsetId = "portfolio_truthset_id"
        case hotPathMode = "hot_path_mode"
        case provisionalHotPath = "provisional_hot_path"
        case confirmedPassing = "confirmed_passing"
        case requiredConfirmedRuns = "required_confirmed_runs"
        case requiredMargin = "required_margin"
        case policy
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        truthsetId = try container.decodeIfPresent(String.self, forKey: .truthsetId)
        portfolioTruthsetId = try container.decodeIfPresent(String.self, forKey: .portfolioTruthsetId)
        hotPathMode = try container.decodeIfPresent(String.self, forKey: .hotPathMode)
        provisionalHotPath = try container.decodeIfPresent(Bool.self, forKey: .provisionalHotPath) ?? false
        confirmedPassing = try container.decodeIfPresent(Bool.self, forKey: .confirmedPassing) ?? false
        requiredConfirmedRuns = try container.decodeIfPresent(Int.self, forKey: .requiredConfirmedRuns)
        requiredMargin = try container.decodeIfPresent(Double.self, forKey: .requiredMargin)
        policy = try container.decodeIfPresent(String.self, forKey: .policy)
    }
}

public struct SemanticIndexRun: Codable, Equatable, Sendable, Identifiable {
    public let id: String
    public let createdAt: String
    public let status: String
    public let schemaVersion: String
    public let hotPathMode: String?
    public let runtime: String?
    public let model: String?
    public let fallbackModel: String?
    public let rerankerModel: String?
    public let sourceExportId: String?
    public let sourceMerkleRoot: String?
    public let episodeCount: Int
    public let atomCount: Int
    public let worldCount: Int
    public let truthsetId: String?
    public let artifactManifest: String?
    public let lancedbPath: String?
    public let tableName: String?
    public let rowCount: Int
    public let indexReady: Bool
    public let nativeLancedb: Bool
    public let maxsimReady: Bool
    public let embeddingBackend: String?
    public let vectorDim: Int?
    public let maxTokens: Int?
    public let workerStatus: String?
    public let restrictedLeakCount: Int
    public let workerLatencyMs: Double?
    public let degradedReason: String?

    enum CodingKeys: String, CodingKey {
        case id
        case createdAt = "created_at"
        case status
        case schemaVersion = "schema_version"
        case hotPathMode = "hot_path_mode"
        case runtime
        case model
        case fallbackModel = "fallback_model"
        case rerankerModel = "reranker_model"
        case sourceExportId = "source_export_id"
        case sourceMerkleRoot = "source_merkle_root"
        case episodeCount = "episode_count"
        case atomCount = "atom_count"
        case worldCount = "world_count"
        case truthsetId = "truthset_id"
        case artifactManifest = "artifact_manifest"
        case lancedbPath = "lancedb_path"
        case tableName = "table_name"
        case rowCount = "row_count"
        case indexReady = "index_ready"
        case nativeLancedb = "native_lancedb"
        case maxsimReady = "maxsim_ready"
        case embeddingBackend = "embedding_backend"
        case vectorDim = "vector_dim"
        case maxTokens = "max_tokens"
        case workerStatus = "worker_status"
        case restrictedLeakCount = "restricted_leak_count"
        case workerLatencyMs = "worker_latency_ms"
        case degradedReason = "degraded_reason"
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        createdAt = try container.decodeIfPresent(String.self, forKey: .createdAt) ?? ""
        status = try container.decodeIfPresent(String.self, forKey: .status) ?? "unknown"
        schemaVersion = try container.decodeIfPresent(String.self, forKey: .schemaVersion) ?? ""
        hotPathMode = try container.decodeIfPresent(String.self, forKey: .hotPathMode)
        runtime = try container.decodeIfPresent(String.self, forKey: .runtime)
        model = try container.decodeIfPresent(String.self, forKey: .model)
        fallbackModel = try container.decodeIfPresent(String.self, forKey: .fallbackModel)
        rerankerModel = try container.decodeIfPresent(String.self, forKey: .rerankerModel)
        sourceExportId = try container.decodeIfPresent(String.self, forKey: .sourceExportId)
        sourceMerkleRoot = try container.decodeIfPresent(String.self, forKey: .sourceMerkleRoot)
        episodeCount = try container.decodeIfPresent(Int.self, forKey: .episodeCount) ?? 0
        atomCount = try container.decodeIfPresent(Int.self, forKey: .atomCount) ?? 0
        worldCount = try container.decodeIfPresent(Int.self, forKey: .worldCount) ?? 0
        truthsetId = try container.decodeIfPresent(String.self, forKey: .truthsetId)
        artifactManifest = try container.decodeIfPresent(String.self, forKey: .artifactManifest)
        lancedbPath = try container.decodeIfPresent(String.self, forKey: .lancedbPath)
        tableName = try container.decodeIfPresent(String.self, forKey: .tableName)
        rowCount = try container.decodeIfPresent(Int.self, forKey: .rowCount) ?? atomCount
        indexReady = try container.decodeIfPresent(Bool.self, forKey: .indexReady) ?? false
        nativeLancedb = try container.decodeIfPresent(Bool.self, forKey: .nativeLancedb) ?? false
        maxsimReady = try container.decodeIfPresent(Bool.self, forKey: .maxsimReady) ?? false
        embeddingBackend = try container.decodeIfPresent(String.self, forKey: .embeddingBackend)
        vectorDim = try container.decodeIfPresent(Int.self, forKey: .vectorDim)
        maxTokens = try container.decodeIfPresent(Int.self, forKey: .maxTokens)
        workerStatus = try container.decodeIfPresent(String.self, forKey: .workerStatus)
        restrictedLeakCount = try container.decodeIfPresent(Int.self, forKey: .restrictedLeakCount) ?? 0
        workerLatencyMs = try container.decodeIfPresent(Double.self, forKey: .workerLatencyMs)
        degradedReason = try container.decodeIfPresent(String.self, forKey: .degradedReason)
    }
}

public struct SemanticIndexStatus: Codable, Equatable, Sendable {
    public let generatedAt: String
    public let schemaVersion: String
    public let status: String
    public let hotPathMode: String?
    public let runtime: String?
    public let model: String?
    public let fallbackModel: String?
    public let rerankerModel: String?
    public let lancedbPath: String?
    public let tableName: String?
    public let rowCount: Int
    public let indexReady: Bool
    public let nativeLancedb: Bool
    public let maxsimReady: Bool
    public let embeddingBackend: String?
    public let latestRun: SemanticIndexRun?
    public let freshness: String?
    public let degradedReason: String?

    enum CodingKeys: String, CodingKey {
        case generatedAt = "generated_at"
        case schemaVersion = "schema_version"
        case status
        case hotPathMode = "hot_path_mode"
        case runtime
        case model
        case fallbackModel = "fallback_model"
        case rerankerModel = "reranker_model"
        case lancedbPath = "lancedb_path"
        case tableName = "table_name"
        case rowCount = "row_count"
        case indexReady = "index_ready"
        case nativeLancedb = "native_lancedb"
        case maxsimReady = "maxsim_ready"
        case embeddingBackend = "embedding_backend"
        case latestRun = "latest_run"
        case freshness
        case degradedReason = "degraded_reason"
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        generatedAt = try container.decodeIfPresent(String.self, forKey: .generatedAt) ?? ""
        schemaVersion = try container.decodeIfPresent(String.self, forKey: .schemaVersion) ?? ""
        status = try container.decodeIfPresent(String.self, forKey: .status) ?? "unknown"
        hotPathMode = try container.decodeIfPresent(String.self, forKey: .hotPathMode)
        runtime = try container.decodeIfPresent(String.self, forKey: .runtime)
        model = try container.decodeIfPresent(String.self, forKey: .model)
        fallbackModel = try container.decodeIfPresent(String.self, forKey: .fallbackModel)
        rerankerModel = try container.decodeIfPresent(String.self, forKey: .rerankerModel)
        lancedbPath = try container.decodeIfPresent(String.self, forKey: .lancedbPath)
        tableName = try container.decodeIfPresent(String.self, forKey: .tableName)
        rowCount = try container.decodeIfPresent(Int.self, forKey: .rowCount) ?? 0
        indexReady = try container.decodeIfPresent(Bool.self, forKey: .indexReady) ?? false
        nativeLancedb = try container.decodeIfPresent(Bool.self, forKey: .nativeLancedb) ?? false
        maxsimReady = try container.decodeIfPresent(Bool.self, forKey: .maxsimReady) ?? false
        embeddingBackend = try container.decodeIfPresent(String.self, forKey: .embeddingBackend)
        latestRun = try container.decodeIfPresent(SemanticIndexRun.self, forKey: .latestRun)
        freshness = try container.decodeIfPresent(String.self, forKey: .freshness)
        degradedReason = try container.decodeIfPresent(String.self, forKey: .degradedReason)
    }
}

public struct MemoryTruthSetSummary: Codable, Equatable, Sendable, Identifiable {
    public let id: String
    public let status: String
    public let title: String
    public let description: String?
    public let domains: [String]
    public let caseCount: Int
    public let approvedCaseCount: Int
    public let artifactRoot: String?
    public let reviewer: String?
    public let rationale: String?

    enum CodingKeys: String, CodingKey {
        case id
        case status
        case title
        case description
        case domains
        case caseCount = "case_count"
        case approvedCaseCount = "approved_case_count"
        case artifactRoot = "artifact_root"
        case reviewer
        case rationale
    }
}

public struct MemoryTruthCaseSummary: Codable, Equatable, Sendable, Identifiable {
    public let id: String
    public let truthsetId: String
    public let status: String
    public let domain: String
    public let query: String
    public let privacyClass: String
    public let tags: [String]

    enum CodingKeys: String, CodingKey {
        case id
        case truthsetId = "truthset_id"
        case status
        case domain
        case query
        case privacyClass = "privacy_class"
        case tags
    }
}

public struct MemoryTruthSetStatus: Codable, Equatable, Sendable {
    public let truthset: MemoryTruthSetSummary
    public let cases: [MemoryTruthCaseSummary]
}

public struct MemoryPromotionGateStatus: Codable, Equatable, Sendable {
    public let truthsetId: String?
    public let promotionGate: MemoryPromotionGate?
    public let hotPathEligible: Bool
}

public struct AgentObserverStatus: Codable, Equatable, Sendable {
    public let status: String
    public let latestAgentWrite: String?
    public let captureLoopStatus: String?
    public let updatedAt: String?
}

public struct AppleCaptureFreshness: Codable, Equatable, Sendable {
    public let status: String
    public let latestCaptureAt: String?
    public let sourceSurface: String?
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

public struct RuntimeVote: Codable, Equatable, Sendable, Identifiable {
    public var id: String { "\(runtime)-\(role)" }
    public let runtime: String
    public let role: String
    public let status: String
    public let score: Double
    public let notes: [String]

    enum CodingKeys: String, CodingKey {
        case runtime
        case role
        case status
        case score
        case notes
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        runtime = try container.decode(String.self, forKey: .runtime)
        role = try container.decode(String.self, forKey: .role)
        status = try container.decode(String.self, forKey: .status)
        score = try container.decode(Double.self, forKey: .score)
        notes = try container.decodeIfPresent([String].self, forKey: .notes) ?? []
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
    public let meshTrace: [RetrievalTraceStep]
    public let runtimeVotes: [RuntimeVote]
    public let candidateRefs: [String]
    public let runtimeUsed: String?
    public let fallbackChain: [String]
    public let semanticTrace: [RetrievalTraceStep]
    public let maxsimScores: [ExocortexJSONValue]
    public let graphExpansion: ExocortexJSONValue?
    public let rerankerScores: [ExocortexJSONValue]
    public let truthsetGateStatus: PortfolioTruthGate?
    public let restrictedLeakCheck: ExocortexJSONValue?

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
        case meshTrace = "mesh_trace"
        case runtimeVotes = "runtime_votes"
        case candidateRefs = "candidate_refs"
        case runtimeUsed = "runtime_used"
        case fallbackChain = "fallback_chain"
        case semanticTrace = "semantic_trace"
        case maxsimScores = "maxsim_scores"
        case graphExpansion = "graph_expansion"
        case rerankerScores = "reranker_scores"
        case truthsetGateStatus = "truthset_gate_status"
        case restrictedLeakCheck = "restricted_leak_check"
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        summary = try container.decode(String.self, forKey: .summary)
        evidence = try container.decodeIfPresent([GraphRagEvidence].self, forKey: .evidence) ?? []
        atoms = try container.decodeIfPresent([MemoryAtom].self, forKey: .atoms) ?? []
        episodes = try container.decodeIfPresent([MemoryEpisode].self, forKey: .episodes) ?? []
        relations = try container.decodeIfPresent([MemoryRelation].self, forKey: .relations) ?? []
        temporalContext = try container.decode(GraphRagTemporalContext.self, forKey: .temporalContext)
        provenance = try container.decodeIfPresent(ExocortexJSONValue.self, forKey: .provenance)
        confidence = try container.decode(Double.self, forKey: .confidence)
        degradedReason = try container.decodeIfPresent(String.self, forKey: .degradedReason)
        mode = try container.decodeIfPresent(String.self, forKey: .mode)
        graphRuntime = try container.decodeIfPresent(String.self, forKey: .graphRuntime)
        evidenceGraph = try container.decodeIfPresent(EvidenceGraph.self, forKey: .evidenceGraph)
        communityContext = try container.decodeIfPresent(GraphRagCommunityContext.self, forKey: .communityContext)
        retrievalTrace = try container.decodeIfPresent([RetrievalTraceStep].self, forKey: .retrievalTrace)
        meshTrace = try container.decodeIfPresent([RetrievalTraceStep].self, forKey: .meshTrace) ?? []
        runtimeVotes = try container.decodeIfPresent([RuntimeVote].self, forKey: .runtimeVotes) ?? []
        candidateRefs = try container.decodeIfPresent([String].self, forKey: .candidateRefs) ?? []
        runtimeUsed = try container.decodeIfPresent(String.self, forKey: .runtimeUsed)
        fallbackChain = try container.decodeIfPresent([String].self, forKey: .fallbackChain) ?? []
        semanticTrace = try container.decodeIfPresent([RetrievalTraceStep].self, forKey: .semanticTrace) ?? []
        maxsimScores = try container.decodeIfPresent([ExocortexJSONValue].self, forKey: .maxsimScores) ?? []
        graphExpansion = try container.decodeIfPresent(ExocortexJSONValue.self, forKey: .graphExpansion)
        rerankerScores = try container.decodeIfPresent([ExocortexJSONValue].self, forKey: .rerankerScores) ?? []
        truthsetGateStatus = try container.decodeIfPresent(PortfolioTruthGate.self, forKey: .truthsetGateStatus)
        restrictedLeakCheck = try container.decodeIfPresent(ExocortexJSONValue.self, forKey: .restrictedLeakCheck)
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
    public let memoryEngineStatus: String?
    public let latestCandidateRef: String?
    public let latestQuorumStatus: String?
    public let memoryGovernorStatus: String?
    public let pendingTriads: Int?
    public let openContradictions: Int?
    public let latestPromotionDecision: String?
    public let memoryBenchStatus: String?
    public let latestBenchScore: Double?
    public let memoryRegressionCount: Int?
    public let truthsetId: String?
    public let benchHotPathEligible: Bool?
    public let agentObserverStatus: String?
    public let appleCaptureFreshness: String?
    public let captureLoopStatus: String?
    public let semanticBackboneStatus: String?
    public let hotPathMode: String?
    public let provisionalHotPath: Bool?
    public let portfolioTruthGate: String?

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
        case memoryEngineStatus = "memory_engine_status"
        case latestCandidateRef = "latest_candidate_ref"
        case latestQuorumStatus = "latest_quorum_status"
        case memoryGovernorStatus = "memory_governor_status"
        case pendingTriads = "pending_triads"
        case openContradictions = "open_contradictions"
        case latestPromotionDecision = "latest_promotion_decision"
        case memoryBenchStatus = "memory_bench_status"
        case latestBenchScore = "latest_bench_score"
        case memoryRegressionCount = "memory_regression_count"
        case truthsetId = "truthset_id"
        case benchHotPathEligible = "bench_hot_path_eligible"
        case agentObserverStatus = "agent_observer_status"
        case appleCaptureFreshness = "apple_capture_freshness"
        case captureLoopStatus = "capture_loop_status"
        case semanticBackboneStatus = "semantic_backbone_status"
        case hotPathMode = "hot_path_mode"
        case provisionalHotPath = "provisional_hot_path"
        case portfolioTruthGate = "portfolio_truth_gate"
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
