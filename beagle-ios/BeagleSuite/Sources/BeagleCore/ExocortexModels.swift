//
//  ExocortexModels.swift
//  BeagleCore
//
//  Cluster-canonical Exocortex contracts shared by iPhone, iPad, macOS,
//  visionOS, Watch, and external MCP agents.
//

import Foundation

fileprivate extension String {
    var nilIfEmpty: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

fileprivate extension Array {
    func stablePrefix(_ count: Int) -> [Element] {
        Array(prefix(count))
    }
}

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

public struct SpatialAssetManifest: Codable, Equatable, Sendable {
    public let panoUrl: String?
    public let colliderMeshUrl: String?
    public let hqMeshUrls: [String]
    public let spzUrls: [String: String]
    public let plyUrls: [String: String]
    public let coordinateSystem: String?
    public let coordinateTransform: String?
    public let assetRoot: String?
    public let degradedReason: String?

    enum CodingKeys: String, CodingKey {
        case panoUrl = "pano_url"
        case colliderMeshUrl = "collider_mesh_url"
        case hqMeshUrls = "hq_mesh_urls"
        case spzUrls = "spz_urls"
        case plyUrls = "ply_urls"
        case coordinateSystem = "coordinate_system"
        case coordinateTransform = "coordinate_transform"
        case assetRoot = "asset_root"
        case degradedReason = "degraded_reason"
    }
}

public struct SpatialWorld: Codable, Equatable, Sendable, Identifiable {
    public let id: String
    public let createdAt: String
    public let updatedAt: String
    public let schemaVersion: String
    public let projectSlug: String
    public let worldId: String
    public let operationId: String?
    public let displayName: String
    public let status: String
    public let worldMarbleUrl: String?
    public let assets: SpatialAssetManifest
    public let model: String
    public let permission: String
    public let promptHash: String
    public let promptSummary: String
    public let privacyPolicy: String
    public let tags: [String]
    public let provenance: ExocortexJSONValue?

    enum CodingKeys: String, CodingKey {
        case id
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case schemaVersion = "schema_version"
        case projectSlug = "project_slug"
        case worldId = "world_id"
        case operationId = "operation_id"
        case displayName = "display_name"
        case status
        case worldMarbleUrl = "world_marble_url"
        case assets
        case model
        case permission
        case promptHash = "prompt_hash"
        case promptSummary = "prompt_summary"
        case privacyPolicy = "privacy_policy"
        case tags
        case provenance
    }
}

public struct ControlRoomSnapshot: Codable, Equatable, Sendable, Identifiable {
    public let id: String
    public let generatedAt: String
    public let schemaVersion: String
    public let projectSlug: String
    public let spatialWorld: SpatialWorld?
    public let memoryWorlds: [MemoryWorld]
    public let agentLanes: [String]
    public let podsWall: [String]
    public let incidentCorridor: [String]
    public let compilerMap: [String]
    public let evidenceRefs: [String]
    public let provenance: ExocortexJSONValue?

    enum CodingKeys: String, CodingKey {
        case id
        case generatedAt = "generated_at"
        case schemaVersion = "schema_version"
        case projectSlug = "project_slug"
        case spatialWorld = "spatial_world"
        case memoryWorlds = "memory_worlds"
        case agentLanes = "agent_lanes"
        case podsWall = "pods_wall"
        case incidentCorridor = "incident_corridor"
        case compilerMap = "compiler_map"
        case evidenceRefs = "evidence_refs"
        case provenance
    }
}

public struct SounioSpatialEvidence: Codable, Equatable, Sendable, Identifiable {
    public let id: String
    public let createdAt: String
    public let schemaVersion: String
    public let worldId: String
    public let projectSlug: String
    public let evidenceType: String
    public let claimSeedRefs: [String]
    public let memoryWorldRefs: [String]
    public let artifactRefs: [String]
    public let epistemicStatus: String
    public let privacyClass: String
    public let provenance: ExocortexJSONValue?

    enum CodingKeys: String, CodingKey {
        case id
        case createdAt = "created_at"
        case schemaVersion = "schema_version"
        case worldId = "world_id"
        case projectSlug = "project_slug"
        case evidenceType = "evidence_type"
        case claimSeedRefs = "claim_seed_refs"
        case memoryWorldRefs = "memory_world_refs"
        case artifactRefs = "artifact_refs"
        case epistemicStatus = "epistemic_status"
        case privacyClass = "privacy_class"
        case provenance
    }
}

public struct SpatialProviderSlot: Codable, Equatable, Sendable, Identifiable {
    public let id: String
    public let label: String
    public let providerFamily: String
    public let artifactType: String
    public let costTier: String
    public let privacyTier: String
    public let maturity: String
    public let enabled: Bool
    public let requiresSecret: Bool
    public let setupStatus: String
    public let notes: [String]

    enum CodingKeys: String, CodingKey {
        case id, label, maturity, enabled, notes
        case providerFamily = "provider_family"
        case artifactType = "artifact_type"
        case costTier = "cost_tier"
        case privacyTier = "privacy_tier"
        case requiresSecret = "requires_secret"
        case setupStatus = "setup_status"
    }
}

public struct MindPalaceRoom: Codable, Equatable, Sendable, Identifiable {
    public let id: String
    public let title: String
    public let roomType: String
    public let state: String
    public let projectSlug: String?
    public let sourceFamily: String
    public let tension: String
    public let nextAction: String
    public let freshness: String
    public let truthMode: String
    public let priority: Double
    public let deskItemRefs: [String]
    public let evidenceRefs: [String]
    public let tags: [String]
    public let provenance: ExocortexJSONValue?

    enum CodingKeys: String, CodingKey {
        case id, title, state, tension, freshness, priority, tags, provenance
        case roomType = "room_type"
        case projectSlug = "project_slug"
        case sourceFamily = "source_family"
        case nextAction = "next_action"
        case truthMode = "truth_mode"
        case deskItemRefs = "desk_item_refs"
        case evidenceRefs = "evidence_refs"
    }
}

public struct DeskItem: Codable, Equatable, Sendable, Identifiable {
    public let id: String
    public let kind: String
    public let title: String
    public let detail: String
    public let state: String
    public let priority: Double
    public let roomId: String?
    public let sourceRef: String?
    public let actions: [String]
    public let provenance: ExocortexJSONValue?

    enum CodingKeys: String, CodingKey {
        case id, kind, title, detail, state, priority, actions, provenance
        case roomId = "room_id"
        case sourceRef = "source_ref"
    }
}

public struct ConversationPortal: Codable, Equatable, Sendable, Identifiable {
    public let id: String
    public let createdAt: String
    public let updatedAt: String
    public let schemaVersion: String
    public let title: String
    public let provider: String
    public let surface: String
    public let status: String
    public let sourceMode: String
    public let privacyClass: String
    public let sourceRef: String?
    public let promotedClipRefs: [String]
    public let tags: [String]
    public let provenance: ExocortexJSONValue?

    enum CodingKeys: String, CodingKey {
        case id, title, provider, surface, status, tags, provenance
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case schemaVersion = "schema_version"
        case sourceMode = "source_mode"
        case privacyClass = "privacy_class"
        case sourceRef = "source_ref"
        case promotedClipRefs = "promoted_clip_refs"
    }
}

public struct PromotedConversationClip: Codable, Equatable, Sendable, Identifiable {
    public let id: String
    public let createdAt: String
    public let schemaVersion: String
    public let portalId: String
    public let contentHash: String
    public let summary: String
    public let projectRef: String?
    public let privacyClass: String
    public let memoryEventId: String?
    public let sounioMomentId: String?
    public let tags: [String]
    public let provenance: ExocortexJSONValue?

    enum CodingKeys: String, CodingKey {
        case id, summary, tags, provenance
        case createdAt = "created_at"
        case schemaVersion = "schema_version"
        case portalId = "portal_id"
        case contentHash = "content_hash"
        case projectRef = "project_ref"
        case privacyClass = "privacy_class"
        case memoryEventId = "memory_event_id"
        case sounioMomentId = "sounio_moment_id"
    }
}

public struct SpatialDeskSnapshot: Codable, Equatable, Sendable, Identifiable {
    public let id: String
    public let generatedAt: String
    public let schemaVersion: String
    public let activeItems: [DeskItem]
    public let pinnedRoomIds: [String]
    public let portals: [ConversationPortal]
    public let agentLanes: [String]
    public let focusStrip: [String]
    public let proofPanels: [String]
    public let provenance: ExocortexJSONValue?

    enum CodingKeys: String, CodingKey {
        case id, portals, provenance
        case generatedAt = "generated_at"
        case schemaVersion = "schema_version"
        case activeItems = "active_items"
        case pinnedRoomIds = "pinned_room_ids"
        case agentLanes = "agent_lanes"
        case focusStrip = "focus_strip"
        case proofPanels = "proof_panels"
    }
}

public struct SpatialAction: Codable, Equatable, Sendable, Identifiable {
    public let id: String
    public let title: String
    public let kind: String
    public let targetRef: String?
    public let reason: String
    public let enabled: Bool

    enum CodingKeys: String, CodingKey {
        case id, title, kind, reason, enabled
        case targetRef = "target_ref"
    }
}

public struct SpatialActionMenu: Codable, Equatable, Sendable, Identifiable {
    public let id: String
    public let generatedAt: String
    public let mode: String
    public let actions: [SpatialAction]

    enum CodingKeys: String, CodingKey {
        case id, mode, actions
        case generatedAt = "generated_at"
    }
}

public struct NextBestPlaceDecision: Codable, Equatable, Sendable, Identifiable {
    public let id: String
    public let generatedAt: String
    public let roomId: String
    public let title: String
    public let reason: String
    public let sourceMode: String
    public let confidence: Double
    public let candidateRoomIds: [String]
    public let readinessContext: ExocortexJSONValue?

    enum CodingKeys: String, CodingKey {
        case id, title, reason, confidence
        case generatedAt = "generated_at"
        case roomId = "room_id"
        case sourceMode = "source_mode"
        case candidateRoomIds = "candidate_room_ids"
        case readinessContext = "readiness_context"
    }
}

public struct FocusIntervention: Codable, Equatable, Sendable, Identifiable {
    public let id: String
    public let kind: String
    public let title: String
    public let reason: String
    public let priority: Double
    public let status: String
    public let dueAt: String?
    public let actions: [String]

    enum CodingKeys: String, CodingKey {
        case id, kind, title, reason, priority, status, actions
        case dueAt = "due_at"
    }
}

public struct FocusSession: Codable, Equatable, Sendable, Identifiable {
    public let id: String
    public let startedAt: String
    public let endedAt: String?
    public let mode: String
    public let projectSlug: String?
    public let status: String
    public let notes: [String]
    public let provenance: ExocortexJSONValue?

    enum CodingKeys: String, CodingKey {
        case id, mode, status, notes, provenance
        case startedAt = "started_at"
        case endedAt = "ended_at"
        case projectSlug = "project_slug"
    }
}

public struct FocusCoachState: Codable, Equatable, Sendable, Identifiable {
    public let id: String
    public let generatedAt: String
    public let schemaVersion: String
    public let mode: String
    public let activeSession: FocusSession?
    public let interventions: [FocusIntervention]
    public let hydrationDue: Bool
    public let calendarNudge: String?
    public let sessionMinutes: Int
    public let canOverride: Bool
    public let provenance: ExocortexJSONValue?

    enum CodingKeys: String, CodingKey {
        case id, mode, interventions, provenance
        case generatedAt = "generated_at"
        case schemaVersion = "schema_version"
        case activeSession = "active_session"
        case hydrationDue = "hydration_due"
        case calendarNudge = "calendar_nudge"
        case sessionMinutes = "session_minutes"
        case canOverride = "can_override"
    }
}

public struct MindPalaceSnapshot: Codable, Equatable, Sendable, Identifiable {
    public let id: String
    public let generatedAt: String
    public let schemaVersion: String
    public let rooms: [MindPalaceRoom]
    public let desk: SpatialDeskSnapshot
    public let nextBestPlace: NextBestPlaceDecision
    public let actionMenu: SpatialActionMenu
    public let focusCoach: FocusCoachState
    public let provenance: ExocortexJSONValue?

    enum CodingKeys: String, CodingKey {
        case id, rooms, desk, provenance
        case generatedAt = "generated_at"
        case schemaVersion = "schema_version"
        case nextBestPlace = "next_best_place"
        case actionMenu = "action_menu"
        case focusCoach = "focus_coach"
    }
}

public struct CreateConversationPortalRequest: Codable, Equatable, Sendable {
    public let title: String
    public let provider: String
    public let surface: String?
    public let status: String?
    public let sourceMode: String?
    public let privacyClass: String?
    public let sourceRef: String?
    public let tags: [String]
    public let provenance: ExocortexJSONValue?

    public init(
        title: String,
        provider: String,
        surface: String? = "desktop-portal",
        status: String? = "reference_only",
        sourceMode: String? = "portal+promote",
        privacyClass: String? = "sensitive",
        sourceRef: String? = nil,
        tags: [String] = [],
        provenance: ExocortexJSONValue? = nil
    ) {
        self.title = title
        self.provider = provider
        self.surface = surface
        self.status = status
        self.sourceMode = sourceMode
        self.privacyClass = privacyClass
        self.sourceRef = sourceRef
        self.tags = tags
        self.provenance = provenance
    }

    enum CodingKeys: String, CodingKey {
        case title, provider, surface, status, tags, provenance
        case sourceMode = "source_mode"
        case privacyClass = "privacy_class"
        case sourceRef = "source_ref"
    }
}

public struct PromoteConversationPortalRequest: Codable, Equatable, Sendable {
    public let selectedText: String
    public let summary: String?
    public let projectRef: String?
    public let privacyClass: String?
    public let tags: [String]
    public let provenance: ExocortexJSONValue?

    public init(
        selectedText: String,
        summary: String? = nil,
        projectRef: String? = nil,
        privacyClass: String? = "sensitive",
        tags: [String] = [],
        provenance: ExocortexJSONValue? = nil
    ) {
        self.selectedText = selectedText
        self.summary = summary
        self.projectRef = projectRef
        self.privacyClass = privacyClass
        self.tags = tags
        self.provenance = provenance
    }

    enum CodingKeys: String, CodingKey {
        case summary, tags, provenance
        case selectedText = "selected_text"
        case projectRef = "project_ref"
        case privacyClass = "privacy_class"
    }
}

public struct FocusCoachEventRequest: Codable, Equatable, Sendable {
    public let eventKind: String
    public let status: String?
    public let interventionId: String?
    public let projectSlug: String?
    public let notes: String?
    public let snoozedMinutes: Int?
    public let provenance: ExocortexJSONValue?

    public init(
        eventKind: String,
        status: String? = "recorded",
        interventionId: String? = nil,
        projectSlug: String? = nil,
        notes: String? = nil,
        snoozedMinutes: Int? = nil,
        provenance: ExocortexJSONValue? = nil
    ) {
        self.eventKind = eventKind
        self.status = status
        self.interventionId = interventionId
        self.projectSlug = projectSlug
        self.notes = notes
        self.snoozedMinutes = snoozedMinutes
        self.provenance = provenance
    }

    enum CodingKeys: String, CodingKey {
        case status, notes, provenance
        case eventKind = "event_kind"
        case interventionId = "intervention_id"
        case projectSlug = "project_slug"
        case snoozedMinutes = "snoozed_minutes"
    }
}

public struct CreateSpatialWorldRequest: Codable, Equatable, Sendable {
    public let projectSlug: String
    public let displayName: String?
    public let promptSummary: String
    public let sanitizedPrompt: String
    public let model: String?
    public let permission: String?
    public let approved: Bool
    public let purpose: String
    public let operationId: String?
    public let worldId: String?
    public let status: String?
    public let worldMarbleUrl: String?
    public let assets: SpatialAssetManifest?
    public let tags: [String]
    public let provenance: ExocortexJSONValue?

    public init(
        projectSlug: String = "sounio",
        displayName: String? = nil,
        promptSummary: String,
        sanitizedPrompt: String,
        model: String? = "marble-1.1",
        permission: String? = "private",
        approved: Bool,
        purpose: String = "control-room",
        operationId: String? = nil,
        worldId: String? = nil,
        status: String? = nil,
        worldMarbleUrl: String? = nil,
        assets: SpatialAssetManifest? = nil,
        tags: [String] = [],
        provenance: ExocortexJSONValue? = nil
    ) {
        self.projectSlug = projectSlug
        self.displayName = displayName
        self.promptSummary = promptSummary
        self.sanitizedPrompt = sanitizedPrompt
        self.model = model
        self.permission = permission
        self.approved = approved
        self.purpose = purpose
        self.operationId = operationId
        self.worldId = worldId
        self.status = status
        self.worldMarbleUrl = worldMarbleUrl
        self.assets = assets
        self.tags = tags
        self.provenance = provenance
    }

    enum CodingKeys: String, CodingKey {
        case projectSlug = "project_slug"
        case displayName = "display_name"
        case promptSummary = "prompt_summary"
        case sanitizedPrompt = "sanitized_prompt"
        case model
        case permission
        case approved
        case purpose
        case operationId = "operation_id"
        case worldId = "world_id"
        case status
        case worldMarbleUrl = "world_marble_url"
        case assets
        case tags
        case provenance
    }
}

public struct CreateSounioSpatialEvidenceRequest: Codable, Equatable, Sendable {
    public let projectSlug: String
    public let evidenceType: String?
    public let claimSeedRefs: [String]
    public let memoryWorldRefs: [String]
    public let artifactRefs: [String]
    public let epistemicStatus: String?
    public let privacyClass: String?
    public let provenance: ExocortexJSONValue?

    public init(
        projectSlug: String,
        evidenceType: String? = "spatial_memory_world",
        claimSeedRefs: [String] = [],
        memoryWorldRefs: [String] = [],
        artifactRefs: [String] = [],
        epistemicStatus: String? = "belief",
        privacyClass: String? = "sensitive",
        provenance: ExocortexJSONValue? = nil
    ) {
        self.projectSlug = projectSlug
        self.evidenceType = evidenceType
        self.claimSeedRefs = claimSeedRefs
        self.memoryWorldRefs = memoryWorldRefs
        self.artifactRefs = artifactRefs
        self.epistemicStatus = epistemicStatus
        self.privacyClass = privacyClass
        self.provenance = provenance
    }

    enum CodingKeys: String, CodingKey {
        case projectSlug = "project_slug"
        case evidenceType = "evidence_type"
        case claimSeedRefs = "claim_seed_refs"
        case memoryWorldRefs = "memory_world_refs"
        case artifactRefs = "artifact_refs"
        case epistemicStatus = "epistemic_status"
        case privacyClass = "privacy_class"
        case provenance
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
    public let retrievalAgent: String?
    public let retrievalPlanId: String?
    public let strategyUsed: String?
    public let subqueries: [String]
    public let evidencePack: ExocortexJSONValue?
    public let contextFormat: String?
    public let plannerMode: String?
    public let budget: ExocortexJSONValue?
    public let runtimeTrace: [RetrievalTraceStep]
    public let contextPackId: String?
    public let policyVersion: String?
    public let policyGate: ExocortexJSONValue?
    public let dreamcycleStatus: String?

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
        case retrievalAgent = "retrieval_agent"
        case retrievalPlanId = "retrieval_plan_id"
        case strategyUsed = "strategy_used"
        case subqueries
        case evidencePack = "evidence_pack"
        case contextFormat = "context_format"
        case plannerMode = "planner_mode"
        case budget
        case runtimeTrace = "runtime_trace"
        case contextPackId = "context_pack_id"
        case policyVersion = "policy_version"
        case policyGate = "policy_gate"
        case dreamcycleStatus = "dreamcycle_status"
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
        retrievalAgent = try container.decodeIfPresent(String.self, forKey: .retrievalAgent)
        retrievalPlanId = try container.decodeIfPresent(String.self, forKey: .retrievalPlanId)
        strategyUsed = try container.decodeIfPresent(String.self, forKey: .strategyUsed)
        subqueries = try container.decodeIfPresent([String].self, forKey: .subqueries) ?? []
        evidencePack = try container.decodeIfPresent(ExocortexJSONValue.self, forKey: .evidencePack)
        contextFormat = try container.decodeIfPresent(String.self, forKey: .contextFormat)
        plannerMode = try container.decodeIfPresent(String.self, forKey: .plannerMode)
        budget = try container.decodeIfPresent(ExocortexJSONValue.self, forKey: .budget)
        runtimeTrace = try container.decodeIfPresent([RetrievalTraceStep].self, forKey: .runtimeTrace) ?? []
        contextPackId = try container.decodeIfPresent(String.self, forKey: .contextPackId)
        policyVersion = try container.decodeIfPresent(String.self, forKey: .policyVersion)
        policyGate = try container.decodeIfPresent(ExocortexJSONValue.self, forKey: .policyGate)
        dreamcycleStatus = try container.decodeIfPresent(String.self, forKey: .dreamcycleStatus)
    }
}

public struct MemoryLensMode: RawRepresentable, Codable, Equatable, Hashable, Sendable {
    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }

    public static let report = MemoryLensMode(rawValue: "report")
    public static let evidence = MemoryLensMode(rawValue: "evidence")
    public static let proof = MemoryLensMode(rawValue: "proof")
    public static let deepDive = MemoryLensMode(rawValue: "deep_dive")
}

public struct MemoryLensPreset: Codable, Equatable, Sendable, Identifiable {
    public let id: String
    public let title: String
    public let query: String
    public let detail: String
    public let systemImage: String
    public let scopeHint: String?
    public let priority: Int

    enum CodingKeys: String, CodingKey {
        case id
        case title
        case query
        case detail
        case systemImage = "system_image"
        case scopeHint = "scope_hint"
        case priority
    }
}

public struct ProofSheetModel: Codable, Equatable, Sendable, Identifiable {
    public let id: String
    public let title: String
    public let summary: String
    public let sourceRefs: [String]
    public let provenanceLines: [String]
    public let traceLines: [String]
    public let runtime: String?
    public let confidence: Double
    public let restrictedLeakCheck: String

    enum CodingKeys: String, CodingKey {
        case id
        case title
        case summary
        case sourceRefs = "source_refs"
        case provenanceLines = "provenance_lines"
        case traceLines = "trace_lines"
        case runtime
        case confidence
        case restrictedLeakCheck = "restricted_leak_check"
    }
}

public struct EvidenceFrontierItem: Codable, Equatable, Sendable, Identifiable {
    public let id: String
    public let title: String
    public let detail: String
    public let kind: String
    public let score: Double
    public let sourceLabel: String
    public let sourceRefs: [String]
    public let truthMode: String
    public let privacyClass: String
    public let proof: ProofSheetModel

    enum CodingKeys: String, CodingKey {
        case id
        case title
        case detail
        case kind
        case score
        case sourceLabel = "source_label"
        case sourceRefs = "source_refs"
        case truthMode = "truth_mode"
        case privacyClass = "privacy_class"
        case proof
    }
}

public struct MemoryLensReport: Codable, Equatable, Sendable, Identifiable {
    public let id: String
    public let generatedAt: String
    public let mode: MemoryLensMode
    public let headline: String
    public let summary: String
    public let changedSignals: [String]
    public let evidenceFrontier: [EvidenceFrontierItem]
    public let presets: [MemoryLensPreset]
    public let sourceConfidenceBadges: [String]
    public let confidence: Double
    public let runtime: String
    public let degradedReason: String?
    public let restrictedContentFiltered: Bool
    public let proof: ProofSheetModel

    enum CodingKeys: String, CodingKey {
        case id
        case generatedAt = "generated_at"
        case mode
        case headline
        case summary
        case changedSignals = "changed_signals"
        case evidenceFrontier = "evidence_frontier"
        case presets
        case sourceConfidenceBadges = "source_confidence_badges"
        case confidence
        case runtime
        case degradedReason = "degraded_reason"
        case restrictedContentFiltered = "restricted_content_filtered"
        case proof
    }
}

public extension MemoryLensReport {
    static func synthesized(
        home: ExocortexHomeSnapshot? = nil,
        homeTruthMode: TruthMode = .declared,
        graphStatus: MemoryGraphStatus? = nil,
        recentGraph: MemoryGraphRecentResponse? = nil,
        benchmark: MemoryBenchmarkStatus? = nil,
        governance: MemoryGovernanceStatus? = nil,
        contradictions: MemoryContradictionListResponse? = nil,
        lastQuery: GraphRagQueryResponse? = nil,
        activeProjectSlug: String = "beagle"
    ) -> MemoryLensReport {
        let generatedAt = lastQuery?.temporalContext.newestEvidenceAt
            ?? recentGraph?.generatedAt
            ?? graphStatus?.generatedAt
            ?? home?.generatedAt
            ?? "local-memory-lens"
        let runtime = lastQuery?.runtimeUsed
            ?? lastQuery?.mode
            ?? graphStatus?.graphRuntime
            ?? home?.trustContext?.hotPathMode
            ?? home?.trustContext?.retrievalMode
            ?? recentGraph?.status.retrievalMode
            ?? "GraphRAG++"
        let degraded = lastQuery?.degradedReason
            ?? graphStatus?.degradedReason.nilIfEmpty
            ?? recentGraph?.status.degradedReason.nilIfEmpty
            ?? home?.trustContext?.graphDegradedReason?.nilIfEmpty

        var changedSignals: [String] = []
        if let write = home?.trustContext?.latestAgentWrite ?? home?.agentContext?.lastAgentWrite, !write.isEmpty {
            changedSignals.append("agent write: \(write)")
        }
        if let paper = home?.trustContext?.sounioPaperRunStatus, !paper.isEmpty {
            changedSignals.append("Sounio PaperRun: \(paper)")
        }
        if let pending = home?.trustContext?.sounioPendingApproval, !pending.isEmpty {
            changedSignals.append("approval pending: \(pending)")
        }
        if let grok = latestGrokSignal(home: home, graph: recentGraph) {
            changedSignals.append("Grok/LLM import: \(grok)")
        }
        if let contradictions, !contradictions.contradictions.isEmpty {
            changedSignals.append("tension: \(contradictions.contradictions.count) contradiction candidates")
        } else if let open = governance?.openContradictions, open > 0 {
            changedSignals.append("tension: \(open) open contradictions")
        }
        if let benchmark {
            let score = benchmark.latestScore.map { String(format: "%.2f", $0) } ?? "pending"
            changedSignals.append("bench \(benchmark.status): \(score)")
        }
        if changedSignals.isEmpty, let status = recentGraph?.status {
            changedSignals.append("\(status.episodeCount) episodes · \(status.atomCount) atoms projected")
        }
        if changedSignals.isEmpty {
            changedSignals.append("Memory Lens is ready from cached or declared state.")
        }

        let frontier = evidenceFrontier(from: lastQuery, recentGraph: recentGraph, truthMode: homeTruthMode)
        let restrictedFiltered = containsRestricted(recentGraph: recentGraph)
            || containsRestricted(query: lastQuery)
        let headline: String
        if lastQuery != nil {
            headline = "A lente montou uma resposta verificável."
        } else if frontier.isEmpty {
            headline = "A bancada de memória está pronta."
        } else {
            headline = "A memória viva tem \(frontier.count) evidências na fronteira."
        }

        let summary = lastQuery?.summary
            ?? synthesizedSummary(home: home, graph: recentGraph, governance: governance, degraded: degraded)
        let confidence = lastQuery?.confidence
            ?? min(0.98, max(0.35, frontier.map(\.score).max() ?? 0.62))
        let badges = sourceBadges(
            home: home,
            homeTruthMode: homeTruthMode,
            graphStatus: graphStatus,
            recentGraph: recentGraph,
            benchmark: benchmark,
            runtime: runtime,
            restrictedFiltered: restrictedFiltered
        )
        let proof = ProofSheetModel(
            id: "memory-lens-report-proof",
            title: "Prova da lente",
            summary: summary,
            sourceRefs: frontier.flatMap(\.sourceRefs).stablePrefix(8),
            provenanceLines: badges,
            traceLines: proofTraceLines(lastQuery: lastQuery, graphStatus: graphStatus, recentGraph: recentGraph),
            runtime: runtime,
            confidence: confidence,
            restrictedLeakCheck: restrictedFiltered ? "restricted filtered before display" : "no restricted surfaced"
        )

        return MemoryLensReport(
            id: "memory-lens-\(generatedAt)-\(runtime)",
            generatedAt: generatedAt,
            mode: lastQuery == nil ? .report : .evidence,
            headline: headline,
            summary: summary,
            changedSignals: changedSignals.stablePrefix(5),
            evidenceFrontier: frontier,
            presets: MemoryLensPreset.beagleNow(activeProjectSlug: activeProjectSlug),
            sourceConfidenceBadges: badges,
            confidence: confidence,
            runtime: runtime,
            degradedReason: degraded,
            restrictedContentFiltered: restrictedFiltered,
            proof: proof
        )
    }

    private static func evidenceFrontier(
        from query: GraphRagQueryResponse?,
        recentGraph: MemoryGraphRecentResponse?,
        truthMode: TruthMode
    ) -> [EvidenceFrontierItem] {
        if let query, !query.evidence.isEmpty {
            let trace = (query.retrievalTrace ?? []) + query.semanticTrace + query.runtimeTrace
            return query.evidence
                .filter { !isRestrictedText($0.text) && !$0.sourceRefs.contains(where: isRestrictedText) }
                .prefix(6)
                .map { evidence in
                    let proof = ProofSheetModel(
                        id: "proof-\(evidence.atomId)",
                        title: evidence.atomType.capitalized,
                        summary: evidence.text,
                        sourceRefs: evidence.sourceRefs,
                        provenanceLines: provenanceLines(from: evidence.provenance),
                        traceLines: trace.prefix(8).map(traceLine),
                        runtime: query.runtimeUsed ?? query.mode,
                        confidence: evidence.score,
                        restrictedLeakCheck: "no restricted surfaced"
                    )
                    return EvidenceFrontierItem(
                        id: evidence.atomId,
                        title: evidence.atomType.capitalized,
                        detail: evidence.text,
                        kind: "query_evidence",
                        score: evidence.score,
                        sourceLabel: evidence.episodeId,
                        sourceRefs: evidence.sourceRefs,
                        truthMode: TruthMode.observed.rawValue,
                        privacyClass: "sensitive",
                        proof: proof
                    )
                }
        }

        let atoms = recentGraph?.atoms ?? []
        return atoms
            .filter { !isRestricted($0) }
            .prefix(6)
            .map { atom in
                let proof = ProofSheetModel(
                    id: "proof-\(atom.id)",
                    title: atom.atomType.capitalized,
                    summary: atom.text,
                    sourceRefs: atom.sourceRefs,
                    provenanceLines: atom.tags.stablePrefix(6),
                    traceLines: [
                        "episode \(atom.episodeId)",
                        "created \(atom.createdAt)",
                        "truth \(truthMode.rawValue)"
                    ],
                    runtime: recentGraph?.status.retrievalMode,
                    confidence: atom.confidence,
                    restrictedLeakCheck: "no restricted surfaced"
                )
                return EvidenceFrontierItem(
                    id: atom.id,
                    title: atom.atomType.capitalized,
                    detail: atom.text,
                    kind: "projected_atom",
                    score: atom.confidence,
                    sourceLabel: atom.episodeId,
                    sourceRefs: atom.sourceRefs,
                    truthMode: truthMode.rawValue,
                    privacyClass: atom.privacyClass,
                    proof: proof
                )
            }
    }

    private static func synthesizedSummary(
        home: ExocortexHomeSnapshot?,
        graph: MemoryGraphRecentResponse?,
        governance: MemoryGovernanceStatus?,
        degraded: String?
    ) -> String {
        if let graph {
            let status = graph.status
            var parts = ["\(status.episodeCount) episodes and \(status.atomCount) atoms are projected into GraphRAG++."]
            if let governance {
                parts.append("\(governance.pendingTriads) Triad items pending and \(governance.openContradictions) open tensions.")
            }
            if let degraded, !degraded.isEmpty {
                parts.append("Retrieval is degraded: \(degraded)")
            }
            return parts.joined(separator: " ")
        }
        if let home {
            return home.todayBrief
        }
        return "The lens is waiting for cluster memory, but the local interface remains ready."
    }

    private static func latestGrokSignal(home: ExocortexHomeSnapshot?, graph: MemoryGraphRecentResponse?) -> String? {
        if let signal = home?.memorySignals.first(where: { $0.localizedCaseInsensitiveContains("grok") }) {
            return signal
        }
        if let episode = graph?.episodes.first(where: { !isRestricted($0) && isGrok($0) }) {
            return episode.title ?? episode.sourceRef
        }
        if let atom = graph?.atoms.first(where: { !isRestricted($0) && isGrok($0) }) {
            return atom.text
        }
        return nil
    }

    private static func sourceBadges(
        home: ExocortexHomeSnapshot?,
        homeTruthMode: TruthMode,
        graphStatus: MemoryGraphStatus?,
        recentGraph: MemoryGraphRecentResponse?,
        benchmark: MemoryBenchmarkStatus?,
        runtime: String,
        restrictedFiltered: Bool
    ) -> [String] {
        var badges = [
            "truth \(homeTruthMode.rawValue)",
            runtime,
            restrictedFiltered ? "restricted filtered" : "no restricted surfaced"
        ]
        if let mcp = home?.trustContext?.mcpStatus {
            badges.append("MCP \(mcp)")
        }
        if let graph = graphStatus?.runtimeStatus {
            badges.append("graph \(graph)")
        }
        if let freshness = recentGraph?.status.freshness {
            badges.append("freshness \(freshness)")
        }
        if let benchmark {
            badges.append("bench \(benchmark.status)")
        }
        return badges.stablePrefix(6)
    }

    private static func proofTraceLines(
        lastQuery: GraphRagQueryResponse?,
        graphStatus: MemoryGraphStatus?,
        recentGraph: MemoryGraphRecentResponse?
    ) -> [String] {
        if let lastQuery {
            let trace = (lastQuery.retrievalTrace ?? []) + lastQuery.semanticTrace + lastQuery.runtimeTrace
            let lines = trace.prefix(8).map(traceLine)
            if !lines.isEmpty { return lines }
            if let plan = lastQuery.retrievalPlanId { return ["retrieval plan \(plan)"] }
        }
        var lines: [String] = []
        if let graphStatus {
            lines.append("\(graphStatus.graphRuntime) · \(graphStatus.retrievalMode)")
        }
        if let recentGraph {
            lines.append("\(recentGraph.status.episodeCount) episodes · \(recentGraph.status.atomCount) atoms")
        }
        return lines.isEmpty ? ["local derived report; no backend mutation"] : lines
    }

    private static func traceLine(_ step: RetrievalTraceStep) -> String {
        "\(step.stage) · \(step.backend) · \(step.status) · \(step.items) items"
    }

    private static func provenanceLines(from value: ExocortexJSONValue?) -> [String] {
        guard let value else { return [] }
        return String(describing: value)
            .split(separator: "\n")
            .map(String.init)
            .stablePrefix(4)
    }

    private static func containsRestricted(recentGraph: MemoryGraphRecentResponse?) -> Bool {
        guard let recentGraph else { return false }
        return recentGraph.atoms.contains(where: isRestricted) || recentGraph.episodes.contains(where: isRestricted)
    }

    private static func containsRestricted(query: GraphRagQueryResponse?) -> Bool {
        guard let query else { return false }
        return query.evidence.contains { isRestrictedText($0.text) || $0.sourceRefs.contains(where: isRestrictedText) }
    }

    private static func isRestricted(_ atom: MemoryAtom) -> Bool {
        atom.privacyClass.lowercased() == "restricted" || isRestrictedText(atom.text)
    }

    private static func isRestricted(_ episode: MemoryEpisode) -> Bool {
        episode.privacyClass.lowercased() == "restricted"
            || isRestrictedText(episode.title ?? "")
            || isRestrictedText(episode.sourceRef)
    }

    private static func isRestrictedText(_ text: String) -> Bool {
        text.localizedCaseInsensitiveContains("restricted")
            || text.localizedCaseInsensitiveContains("client_secret")
            || text.localizedCaseInsensitiveContains("api_key")
    }

    private static func isGrok(_ episode: MemoryEpisode) -> Bool {
        ([episode.source, episode.sourcePlatform ?? "", episode.title ?? "", episode.sourceRef] + episode.tags)
            .joined(separator: " ")
            .localizedCaseInsensitiveContains("grok")
    }

    private static func isGrok(_ atom: MemoryAtom) -> Bool {
        ([atom.atomType, atom.text] + atom.tags)
            .joined(separator: " ")
            .localizedCaseInsensitiveContains("grok")
    }
}

public extension MemoryLensPreset {
    static func beagleNow(activeProjectSlug: String = "beagle") -> [MemoryLensPreset] {
        [
            MemoryLensPreset(
                id: "latest-beagle-decision",
                title: "Última decisão Beagle",
                query: "qual foi a última decisão relevante sobre o Beagle?",
                detail: "Retoma a decisão mais recente com evidência e próximo gesto.",
                systemImage: "checkmark.seal",
                scopeHint: activeProjectSlug,
                priority: 0
            ),
            MemoryLensPreset(
                id: "claude-codex-changes",
                title: "Claude/Codex mudou o quê?",
                query: "o que mudou desde as últimas escritas do Claude, Codex ou Claude Code?",
                detail: "Compara writes recentes de agentes e memória de trabalho.",
                systemImage: "point.3.connected.trianglepath.dotted",
                scopeHint: activeProjectSlug,
                priority: 1
            ),
            MemoryLensPreset(
                id: "sounio-paperrun-now",
                title: "Sounio/PaperRun agora",
                query: "qual é o estado atual do Sounio PaperRun e quais claims precisam atenção?",
                detail: "Mostra claims, aprovações e tensão epistêmica.",
                systemImage: "doc.richtext",
                scopeHint: activeProjectSlug,
                priority: 2
            ),
            MemoryLensPreset(
                id: "grok-claude-imports",
                title: "Imports Grok/Claude",
                query: "o que os imports do Grok e Claude adicionaram à memória do Beagle?",
                detail: "Procura sinais novos sem expor conteúdo restrito.",
                systemImage: "tray.and.arrow.down",
                scopeHint: activeProjectSlug,
                priority: 3
            ),
            MemoryLensPreset(
                id: "next-move",
                title: "Próximo gesto",
                query: "o que devo fazer agora no Beagle considerando memória, agentes, Sounio e app Apple?",
                detail: "Sintetiza ação situada a partir da memória viva.",
                systemImage: "arrow.forward.circle",
                scopeHint: activeProjectSlug,
                priority: 4
            )
        ]
    }
}

public struct ContextPack: Codable, Equatable, Sendable, Identifiable {
    public let id: String
    public let createdAt: String
    public let schemaVersion: String
    public let query: String
    public let task: String?
    public let surface: String
    public let format: String
    public let policyVersion: String
    public let policyMode: String
    public let tokenBudget: Int
    public let retrievalPlanId: String?
    public let strategyUsed: String
    public let contextSections: ExocortexJSONValue?
    public let evidenceRefs: [String]
    public let provenance: ExocortexJSONValue?
    public let restrictedLeakCheck: ExocortexJSONValue?
    public let policyRationale: [String]
    public let fallbackChain: [String]
    public let nextAction: String
    public let degradedReason: String?

    enum CodingKeys: String, CodingKey {
        case id
        case createdAt = "created_at"
        case schemaVersion = "schema_version"
        case query
        case task
        case surface
        case format
        case policyVersion = "policy_version"
        case policyMode = "policy_mode"
        case tokenBudget = "token_budget"
        case retrievalPlanId = "retrieval_plan_id"
        case strategyUsed = "strategy_used"
        case contextSections = "context_sections"
        case evidenceRefs = "evidence_refs"
        case provenance
        case restrictedLeakCheck = "restricted_leak_check"
        case policyRationale = "policy_rationale"
        case fallbackChain = "fallback_chain"
        case nextAction = "next_action"
        case degradedReason = "degraded_reason"
    }
}

public struct MemoryPolicyStatus: Codable, Equatable, Sendable {
    public let generatedAt: String
    public let schemaVersion: String
    public let status: String
    public let policyVersion: String
    public let policyMode: String
    public let promotionGate: ExocortexJSONValue?
    public let degradedReason: String?

    enum CodingKeys: String, CodingKey {
        case generatedAt = "generated_at"
        case schemaVersion = "schema_version"
        case status
        case policyVersion = "policy_version"
        case policyMode = "policy_mode"
        case promotionGate = "promotion_gate"
        case degradedReason = "degraded_reason"
    }
}

public struct DreamCycleStatus: Codable, Equatable, Sendable {
    public let generatedAt: String
    public let schemaVersion: String
    public let status: String
    public let mode: String
    public let policy: String
    public let candidateOutputsActive: Bool
    public let degradedReason: String?

    enum CodingKeys: String, CodingKey {
        case generatedAt = "generated_at"
        case schemaVersion = "schema_version"
        case status
        case mode
        case policy
        case candidateOutputsActive = "candidate_outputs_active"
        case degradedReason = "degraded_reason"
    }
}

public struct MemoryEffectivenessEvent: Codable, Equatable, Sendable, Identifiable {
    public let id: String
    public let createdAt: String
    public let schemaVersion: String
    public let contextPackId: String
    public let surface: String
    public let principal: String
    public let strategyUsed: String
    public let success: Bool
    public let outcome: String

    enum CodingKeys: String, CodingKey {
        case id
        case createdAt = "created_at"
        case schemaVersion = "schema_version"
        case contextPackId = "context_pack_id"
        case surface
        case principal
        case strategyUsed = "strategy_used"
        case success
        case outcome
    }
}

public struct IntentCapsule: Codable, Equatable, Sendable {
    public let sourceSurface: String
    public let intent: String
    public let bodySummary: String?
    public let redactionState: String
    public let privacyClass: String

    enum CodingKeys: String, CodingKey {
        case sourceSurface = "source_surface"
        case intent
        case bodySummary = "body_summary"
        case redactionState = "redaction_state"
        case privacyClass = "privacy_class"
    }
}

public struct SounioProgramCheckResponse: Codable, Equatable, Sendable {
    public let status: String
    public let programHash: String
    public let schemaVersion: String
    public let errors: [String]
    public let warnings: [String]
    public let temporalSpec: ExocortexJSONValue?
    public let memoryProjectionPreview: ExocortexJSONValue?

    enum CodingKeys: String, CodingKey {
        case status
        case programHash = "program_hash"
        case schemaVersion = "schema_version"
        case errors
        case warnings
        case temporalSpec = "temporal_spec"
        case memoryProjectionPreview = "memory_projection_preview"
    }
}

public struct PaperRun: Codable, Equatable, Sendable, Identifiable {
    public let id: String
    public let createdAt: String
    public let updatedAt: String
    public let schemaVersion: String
    public let paperId: String
    public let title: String
    public let status: String
    public let temporalWorkflowId: String
    public let temporalNamespace: String
    public let temporalTaskQueue: String
    public let temporalStatus: String
    public let sounioProgramId: String
    public let sounioProgramHash: String
    public let manuscriptVersion: String
    public let sectionStatus: [String: String]
    public let claimRegistry: [ExocortexJSONValue]
    public let citationRegistry: [ExocortexJSONValue]
    public let approvalState: String
    public let pendingApprovalStep: String?
    public let contextPackId: String?
    public let artifactRefs: [String]
    public let provenance: ExocortexJSONValue?
    public let interactionSummary: String?
    public let claimLifecycleStatus: [String: String]?
    public let publicDigestStatus: String?
    public let currentStage: String?

    enum CodingKeys: String, CodingKey {
        case id
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case schemaVersion = "schema_version"
        case paperId = "paper_id"
        case title
        case status
        case temporalWorkflowId = "temporal_workflow_id"
        case temporalNamespace = "temporal_namespace"
        case temporalTaskQueue = "temporal_task_queue"
        case temporalStatus = "temporal_status"
        case sounioProgramId = "sounio_program_id"
        case sounioProgramHash = "sounio_program_hash"
        case manuscriptVersion = "manuscript_version"
        case sectionStatus = "section_status"
        case claimRegistry = "claim_registry"
        case citationRegistry = "citation_registry"
        case approvalState = "approval_state"
        case pendingApprovalStep = "pending_approval_step"
        case contextPackId = "context_pack_id"
        case artifactRefs = "artifact_refs"
        case provenance
        case interactionSummary = "interaction_summary"
        case claimLifecycleStatus = "claim_lifecycle_status"
        case publicDigestStatus = "public_digest_status"
        case currentStage = "current_stage"
    }
}

public struct SounioTraceEvent: Codable, Equatable, Sendable, Identifiable {
    public let id: String
    public let createdAt: String
    public let paperRunId: String
    public let programId: String
    public let stepId: String
    public let eventType: String
    public let status: String
    public let summary: String?
    public let contextPackId: String?
    public let provenance: ExocortexJSONValue?
    public let artifactRefs: [String]

    enum CodingKeys: String, CodingKey {
        case id
        case createdAt = "created_at"
        case paperRunId = "paper_run_id"
        case programId = "program_id"
        case stepId = "step_id"
        case eventType = "event_type"
        case status
        case summary
        case contextPackId = "context_pack_id"
        case provenance
        case artifactRefs = "artifact_refs"
    }
}

public struct SounioTraceListResponse: Codable, Equatable, Sendable {
    public let events: [SounioTraceEvent]
}

public struct PaperRunArtifactsResponse: Codable, Equatable, Sendable {
    public let paperRunId: String
    public let generatedAt: String
    public let manuscriptMarkdown: String
    public let provenancePack: ExocortexJSONValue?
    public let artifactRefs: [String]

    enum CodingKeys: String, CodingKey {
        case paperRunId = "paper_run_id"
        case generatedAt = "generated_at"
        case manuscriptMarkdown = "manuscript_markdown"
        case provenancePack = "provenance_pack"
        case artifactRefs = "artifact_refs"
    }
}

public struct SounioClaimInput: Codable, Equatable, Sendable {
    public let id: String?
    public let claimText: String
    public let subject: String?
    public let valueType: String?
    public let epistemicStatus: String?
    public let evidenceRefs: [String]
    public let provenance: ExocortexJSONValue?
    public let confidence: Double?
    public let contestation: ExocortexJSONValue?
    public let reviewState: String?
    public let promotionRule: String?
    public let publicationReadiness: String?
    public let sectionId: String?
    public let agentRefs: [String]
    public let contractRefs: [String]
    public let artifactRefs: [String]
    public let chronoselfCommitRefs: [String]
    public let privacyClass: String?
    public let rationale: String?

    public init(
        id: String? = nil,
        claimText: String,
        subject: String? = nil,
        valueType: String? = "Claim<T>",
        epistemicStatus: String? = "belief",
        evidenceRefs: [String] = [],
        provenance: ExocortexJSONValue? = nil,
        confidence: Double? = nil,
        contestation: ExocortexJSONValue? = nil,
        reviewState: String? = "unreviewed",
        promotionRule: String? = nil,
        publicationReadiness: String? = "not_ready",
        sectionId: String? = nil,
        agentRefs: [String] = [],
        contractRefs: [String] = [],
        artifactRefs: [String] = [],
        chronoselfCommitRefs: [String] = [],
        privacyClass: String? = "sensitive",
        rationale: String? = nil
    ) {
        self.id = id
        self.claimText = claimText
        self.subject = subject
        self.valueType = valueType
        self.epistemicStatus = epistemicStatus
        self.evidenceRefs = evidenceRefs
        self.provenance = provenance
        self.confidence = confidence
        self.contestation = contestation
        self.reviewState = reviewState
        self.promotionRule = promotionRule
        self.publicationReadiness = publicationReadiness
        self.sectionId = sectionId
        self.agentRefs = agentRefs
        self.contractRefs = contractRefs
        self.artifactRefs = artifactRefs
        self.chronoselfCommitRefs = chronoselfCommitRefs
        self.privacyClass = privacyClass
        self.rationale = rationale
    }

    enum CodingKeys: String, CodingKey {
        case id
        case claimText = "claim_text"
        case subject
        case valueType = "value_type"
        case epistemicStatus = "epistemic_status"
        case evidenceRefs = "evidence_refs"
        case provenance
        case confidence
        case contestation
        case reviewState = "review_state"
        case promotionRule = "promotion_rule"
        case publicationReadiness = "publication_readiness"
        case sectionId = "section_id"
        case agentRefs = "agent_refs"
        case contractRefs = "contract_refs"
        case artifactRefs = "artifact_refs"
        case chronoselfCommitRefs = "chronoself_commit_refs"
        case privacyClass = "privacy_class"
        case rationale
    }
}

public struct OriginLineageSnapshot: Codable, Equatable, Sendable {
    public let generatedAt: String
    public let sourcePolicy: String
    public let nodes: [OriginLineageNode]
    public let edges: [OriginLineageEdge]
    public let evidenceRefs: [OriginEvidenceRef]
    public let tensions: [OriginTension]
    public let claimSeeds: [SounioClaimInput]

    enum CodingKeys: String, CodingKey {
        case generatedAt = "generated_at"
        case sourcePolicy = "source_policy"
        case nodes
        case edges
        case evidenceRefs = "evidence_refs"
        case tensions
        case claimSeeds = "claim_seeds"
    }

    public static let localSeed = OriginLineageSnapshot(
        generatedAt: "2026-04-28T00:00:00Z",
        sourcePolicy: "sanitized_local_seed_until_cluster_origin_lineage_is_available",
        nodes: [
            OriginLineageNode(
                id: "ragpp-mestrado",
                title: "RAG++",
                subtitle: "Mestrado",
                state: "origin",
                firstKnownAt: "2025-08-30",
                sourceFamily: "ChatGPT export archaeology",
                tension: "literature retrieval had to become auditable research memory",
                nextAction: "Preserve active-reading artifacts as projected evidence",
                evidenceRefs: ["origin:chatgpt:ragpp-2025-08-30"],
                claimSeedId: "claim-origin-ragpp"
            ),
            OriginLineageNode(
                id: "darwin-app-rag",
                title: "Darwin",
                subtitle: "App RAG",
                state: "platform",
                firstKnownAt: "2025-09-16",
                sourceFamily: "PCS-HELIO and Darwin release traces",
                tension: "RAG app needed imports, connectors, health checks and agentic evolution",
                nextAction: "Map Darwin failures and desires into Beagle product principles",
                evidenceRefs: ["origin:chatgpt:darwin-v5-2025-09-16"],
                claimSeedId: "claim-origin-darwin"
            ),
            OriginLineageNode(
                id: "beagle-exocortex",
                title: "Beagle",
                subtitle: "Exocortex",
                state: "living memory",
                firstKnownAt: "2026-04-25",
                sourceFamily: "Beagle design docs and MCP memory",
                tension: "dashboard and chatbot patterns were too shallow for continuity",
                nextAction: "Make Home feel like return to a remembered mind",
                evidenceRefs: ["origin:beagle:vision-2026-04-25"],
                claimSeedId: "claim-origin-beagle"
            ),
            OriginLineageNode(
                id: "sounio-claim",
                title: "Sounio",
                subtitle: "Claim<T>",
                state: "epistemic typing",
                firstKnownAt: "2026-04-28",
                sourceFamily: "Sounio specs and PaperRun design",
                tension: "observed process still needed typed epistemic claims",
                nextAction: "Seed PaperRun claims from the lineage without auto-promotion",
                evidenceRefs: ["origin:sounio:claimt-2026-04-28"],
                claimSeedId: "claim-origin-sounio"
            )
        ],
        edges: [
            OriginLineageEdge(
                id: "ragpp-to-darwin",
                from: "ragpp-mestrado",
                to: "darwin-app-rag",
                label: "became platform"
            ),
            OriginLineageEdge(
                id: "darwin-to-beagle",
                from: "darwin-app-rag",
                to: "beagle-exocortex",
                label: "gained continuity"
            ),
            OriginLineageEdge(
                id: "beagle-to-sounio",
                from: "beagle-exocortex",
                to: "sounio-claim",
                label: "typed claims"
            )
        ],
        evidenceRefs: [
            OriginEvidenceRef(
                id: "origin:chatgpt:ragpp-2025-08-30",
                label: "RAG++ for thesis and active reading",
                sourceFamily: "ChatGPT export",
                visibility: "private_trace_only",
                firstObservedAt: "2025-08-30"
            ),
            OriginEvidenceRef(
                id: "origin:chatgpt:darwin-v5-2025-09-16",
                label: "Darwin as PCS-HELIO RAG application",
                sourceFamily: "ChatGPT export",
                visibility: "private_trace_only",
                firstObservedAt: "2025-09-16"
            ),
            OriginEvidenceRef(
                id: "origin:beagle:vision-2026-04-25",
                label: "Beagle as cluster-first exocortex",
                sourceFamily: "Beagle design documents",
                visibility: "sanitized_digest_ok",
                firstObservedAt: "2026-04-25"
            ),
            OriginEvidenceRef(
                id: "origin:sounio:claimt-2026-04-28",
                label: "Sounio Claim<T> as epistemic core",
                sourceFamily: "Sounio/PaperRun design",
                visibility: "sanitized_digest_ok",
                firstObservedAt: "2026-04-28"
            )
        ],
        tensions: [
            OriginTension(
                id: "tension-rag-exocortex",
                title: "RAG vs exocortex",
                detail: "Retrieval solved access to documents, but not continuity of identity, projects and decisions.",
                status: "active"
            ),
            OriginTension(
                id: "tension-import-capture",
                title: "Import vs capture",
                detail: "Historical exports recover the past; live MCP, Apple and work-memory capture preserve the process as it happens.",
                status: "active"
            ),
            OriginTension(
                id: "tension-dashboard-memory",
                title: "Dashboard vs living memory",
                detail: "The interface must show origin, evidence and next action instead of isolated status cards.",
                status: "design_gate"
            ),
            OriginTension(
                id: "tension-claim-process",
                title: "Process vs claim",
                detail: "Beagle observes how ideas evolve; Sounio types what those ideas are allowed to claim.",
                status: "paper_seed"
            )
        ],
        claimSeeds: [
            SounioClaimInput(
                id: "claim-origin-ragpp",
                claimText: "The Beagle lineage begins with RAG++ as an auditable research-memory workflow for thesis-scale literature work.",
                subject: "Beagle origin",
                epistemicStatus: "belief",
                evidenceRefs: ["origin:chatgpt:ragpp-2025-08-30"],
                confidence: 0.62,
                reviewState: "seeded",
                promotionRule: "requires_private_trace_review_and_sanitized_digest",
                publicationReadiness: "not_ready",
                sectionId: "methods-origin",
                privacyClass: "sensitive",
                rationale: "Seeded from local sanitized archaeology; not promoted until cluster provenance is reviewed."
            ),
            SounioClaimInput(
                id: "claim-origin-darwin",
                claimText: "Darwin was the intermediate RAG application that exposed the need for connectors, memory import, health checks and agentic evolution.",
                subject: "Darwin to Beagle",
                epistemicStatus: "belief",
                evidenceRefs: ["origin:chatgpt:darwin-v5-2025-09-16"],
                confidence: 0.66,
                reviewState: "seeded",
                promotionRule: "requires_private_trace_review_and_sanitized_digest",
                publicationReadiness: "not_ready",
                sectionId: "architecture-genealogy",
                privacyClass: "sensitive",
                rationale: "Seeded from title-level and user-intent archaeology; raw chat remains private."
            ),
            SounioClaimInput(
                id: "claim-origin-beagle",
                claimText: "Beagle extends Darwin by turning retrieval into persistent cross-platform memory, agentic work capture and Apple-native continuity.",
                subject: "Beagle exocortex",
                epistemicStatus: "contest",
                evidenceRefs: ["origin:beagle:vision-2026-04-25"],
                confidence: 0.58,
                reviewState: "seeded",
                promotionRule: "requires_architecture_evidence_and_human_review",
                publicationReadiness: "not_ready",
                sectionId: "system-overview",
                privacyClass: "sensitive",
                rationale: "This is the central paper thesis and must stay contestable until implementation evidence is attached."
            ),
            SounioClaimInput(
                id: "claim-origin-sounio",
                claimText: "Sounio complements Beagle by typing the epistemic status of claims produced during human-agent scientific work.",
                subject: "Sounio Claim<T>",
                epistemicStatus: "belief",
                evidenceRefs: ["origin:sounio:claimt-2026-04-28"],
                confidence: 0.6,
                reviewState: "seeded",
                promotionRule: "requires_claim_graph_and_paperrun_artifact",
                publicationReadiness: "not_ready",
                sectionId: "sounio-ir",
                privacyClass: "sensitive",
                rationale: "Seeded as a paper claim candidate, not an active knowledge claim."
            )
        ]
    )
}

public struct OriginLineageNode: Codable, Equatable, Sendable, Identifiable {
    public let id: String
    public let title: String
    public let subtitle: String
    public let state: String
    public let firstKnownAt: String
    public let sourceFamily: String
    public let tension: String
    public let nextAction: String
    public let evidenceRefs: [String]
    public let claimSeedId: String?

    enum CodingKeys: String, CodingKey {
        case id
        case title
        case subtitle
        case state
        case firstKnownAt = "first_known_at"
        case sourceFamily = "source_family"
        case tension
        case nextAction = "next_action"
        case evidenceRefs = "evidence_refs"
        case claimSeedId = "claim_seed_id"
    }
}

public struct OriginLineageEdge: Codable, Equatable, Sendable, Identifiable {
    public let id: String
    public let from: String
    public let to: String
    public let label: String
}

public struct OriginEvidenceRef: Codable, Equatable, Sendable, Identifiable {
    public let id: String
    public let label: String
    public let sourceFamily: String
    public let visibility: String
    public let firstObservedAt: String?

    enum CodingKeys: String, CodingKey {
        case id
        case label
        case sourceFamily = "source_family"
        case visibility
        case firstObservedAt = "first_observed_at"
    }
}

public struct OriginTension: Codable, Equatable, Sendable, Identifiable {
    public let id: String
    public let title: String
    public let detail: String
    public let status: String
}

public struct SounioClaimCheckRequest: Codable, Equatable, Sendable {
    public let claim: SounioClaimInput
}

public struct AddSounioClaimRequest: Codable, Equatable, Sendable {
    public let claim: SounioClaimInput
    public let principal: String?
    public let surface: String?
}

public struct ReviewSounioClaimRequest: Codable, Equatable, Sendable {
    public let reviewer: String?
    public let decision: String
    public let rationale: String?
    public let evidenceRefs: [String]
    public let epistemicStatus: String?
    public let publicationReadiness: String?
    public let provenance: ExocortexJSONValue?

    enum CodingKeys: String, CodingKey {
        case reviewer
        case decision
        case rationale
        case evidenceRefs = "evidence_refs"
        case epistemicStatus = "epistemic_status"
        case publicationReadiness = "publication_readiness"
        case provenance
    }
}

public struct SounioClaim: Codable, Equatable, Sendable, Identifiable {
    public let id: String
    public let createdAt: String
    public let updatedAt: String
    public let paperRunId: String?
    public let sectionId: String?
    public let claimText: String
    public let subject: String
    public let valueType: String?
    public let epistemicStatus: String
    public let evidenceRefs: [String]
    public let provenance: ExocortexJSONValue?
    public let confidence: Double
    public let contestation: ExocortexJSONValue?
    public let reviewState: String
    public let promotionRule: String
    public let publicationReadiness: String
    public let agentRefs: [String]
    public let contractRefs: [String]
    public let artifactRefs: [String]
    public let chronoselfCommitRefs: [String]
    public let privacyClass: String
    public let rationale: String?

    enum CodingKeys: String, CodingKey {
        case id
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case paperRunId = "paper_run_id"
        case sectionId = "section_id"
        case claimText = "claim_text"
        case subject
        case valueType = "value_type"
        case epistemicStatus = "epistemic_status"
        case evidenceRefs = "evidence_refs"
        case provenance
        case confidence
        case contestation
        case reviewState = "review_state"
        case promotionRule = "promotion_rule"
        case publicationReadiness = "publication_readiness"
        case agentRefs = "agent_refs"
        case contractRefs = "contract_refs"
        case artifactRefs = "artifact_refs"
        case chronoselfCommitRefs = "chronoself_commit_refs"
        case privacyClass = "privacy_class"
        case rationale
    }
}

public struct SounioClaimCheckResponse: Codable, Equatable, Sendable {
    public let status: String
    public let schemaVersion: String
    public let normalizedClaim: SounioClaim
    public let errors: [String]
    public let warnings: [String]
    public let requiredEvidence: [String]
    public let promotionGate: ExocortexJSONValue?

    enum CodingKeys: String, CodingKey {
        case status
        case schemaVersion = "schema_version"
        case normalizedClaim = "normalized_claim"
        case errors
        case warnings
        case requiredEvidence = "required_evidence"
        case promotionGate = "promotion_gate"
    }
}

public struct SounioClaimReview: Codable, Equatable, Sendable, Identifiable {
    public let id: String
    public let createdAt: String
    public let paperRunId: String
    public let claimId: String
    public let reviewer: String
    public let decision: String
    public let rationale: String?
    public let previousStatus: String
    public let newStatus: String
    public let evidenceRefs: [String]
    public let provenance: ExocortexJSONValue?

    enum CodingKeys: String, CodingKey {
        case id
        case createdAt = "created_at"
        case paperRunId = "paper_run_id"
        case claimId = "claim_id"
        case reviewer
        case decision
        case rationale
        case previousStatus = "previous_status"
        case newStatus = "new_status"
        case evidenceRefs = "evidence_refs"
        case provenance
    }
}

public struct SounioMomentTypeRequest: Codable, Equatable, Sendable {
    public let sourceEventRefs: [String]
    public let sourcePlatform: String?
    public let sourceSurface: String?
    public let projectSlug: String?
    public let sessionId: String?
    public let intentText: String?
    public let summary: String?
    public let evidenceRefs: [String]
    public let claimSeeds: [SounioClaimInput]
    public let decisionSeeds: [String]
    public let nextAction: String?
    public let privacyClass: String?
    public let reviewState: String?
    public let provenance: ExocortexJSONValue?
    public let tags: [String]

    public init(
        sourceEventRefs: [String] = [],
        sourcePlatform: String? = "beagle-apple",
        sourceSurface: String? = "beagle-apple-sounio",
        projectSlug: String? = "sounio",
        sessionId: String? = nil,
        intentText: String? = nil,
        summary: String? = nil,
        evidenceRefs: [String] = [],
        claimSeeds: [SounioClaimInput] = [],
        decisionSeeds: [String] = [],
        nextAction: String? = nil,
        privacyClass: String? = "sensitive",
        reviewState: String? = "unreviewed",
        provenance: ExocortexJSONValue? = .object(["source": .string("beagle-apple")]),
        tags: [String] = ["sounio", "ambient-typing"]
    ) {
        self.sourceEventRefs = sourceEventRefs
        self.sourcePlatform = sourcePlatform
        self.sourceSurface = sourceSurface
        self.projectSlug = projectSlug
        self.sessionId = sessionId
        self.intentText = intentText
        self.summary = summary
        self.evidenceRefs = evidenceRefs
        self.claimSeeds = claimSeeds
        self.decisionSeeds = decisionSeeds
        self.nextAction = nextAction
        self.privacyClass = privacyClass
        self.reviewState = reviewState
        self.provenance = provenance
        self.tags = tags
    }

    enum CodingKeys: String, CodingKey {
        case sourceEventRefs = "source_event_refs"
        case sourcePlatform = "source_platform"
        case sourceSurface = "source_surface"
        case projectSlug = "project_slug"
        case sessionId = "session_id"
        case intentText = "intent_text"
        case summary
        case evidenceRefs = "evidence_refs"
        case claimSeeds = "claim_seeds"
        case decisionSeeds = "decision_seeds"
        case nextAction = "next_action"
        case privacyClass = "privacy_class"
        case reviewState = "review_state"
        case provenance
        case tags
    }
}

public struct SounioMomentReviewRequest: Codable, Equatable, Sendable {
    public let reviewer: String?
    public let decision: String
    public let rationale: String?
    public let evidenceRefs: [String]
    public let reviewState: String?
    public let provenance: ExocortexJSONValue?

    public init(
        reviewer: String? = "demetrios",
        decision: String,
        rationale: String? = nil,
        evidenceRefs: [String] = [],
        reviewState: String? = nil,
        provenance: ExocortexJSONValue? = .object(["source": .string("beagle-apple")])
    ) {
        self.reviewer = reviewer
        self.decision = decision
        self.rationale = rationale
        self.evidenceRefs = evidenceRefs
        self.reviewState = reviewState
        self.provenance = provenance
    }

    enum CodingKeys: String, CodingKey {
        case reviewer
        case decision
        case rationale
        case evidenceRefs = "evidence_refs"
        case reviewState = "review_state"
        case provenance
    }
}

public struct SounioMomentReview: Codable, Equatable, Sendable, Identifiable {
    public let id: String
    public let createdAt: String
    public let momentId: String
    public let reviewer: String
    public let decision: String
    public let rationale: String?
    public let previousState: String
    public let newState: String
    public let evidenceRefs: [String]
    public let provenance: ExocortexJSONValue?

    enum CodingKeys: String, CodingKey {
        case id
        case createdAt = "created_at"
        case momentId = "moment_id"
        case reviewer
        case decision
        case rationale
        case previousState = "previous_state"
        case newState = "new_state"
        case evidenceRefs = "evidence_refs"
        case provenance
    }
}

public struct SounioMoment: Codable, Equatable, Sendable, Identifiable {
    public let id: String
    public let createdAt: String
    public let updatedAt: String
    public let schemaVersion: String
    public let projectSlug: String
    public let momentType: String
    public let intent: String
    public let summary: String
    public let sourcePlatform: String
    public let sourceSurface: String
    public let sessionId: String?
    public let sourceEventRefs: [String]
    public let evidenceRefs: [String]
    public let claimSeeds: [SounioClaim]
    public let decisionSeeds: [String]
    public let nextAction: String?
    public let privacyClass: String
    public let reviewState: String
    public let restrictedLeakCheck: String
    public let provenance: ExocortexJSONValue?
    public let tags: [String]

    enum CodingKeys: String, CodingKey {
        case id
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case schemaVersion = "schema_version"
        case projectSlug = "project_slug"
        case momentType = "moment_type"
        case intent
        case summary
        case sourcePlatform = "source_platform"
        case sourceSurface = "source_surface"
        case sessionId = "session_id"
        case sourceEventRefs = "source_event_refs"
        case evidenceRefs = "evidence_refs"
        case claimSeeds = "claim_seeds"
        case decisionSeeds = "decision_seeds"
        case nextAction = "next_action"
        case privacyClass = "privacy_class"
        case reviewState = "review_state"
        case restrictedLeakCheck = "restricted_leak_check"
        case provenance
        case tags
    }
}

public struct SounioMomentListResponse: Codable, Equatable, Sendable {
    public let generatedAt: String
    public let schemaVersion: String
    public let projectSlug: String?
    public let moments: [SounioMoment]

    enum CodingKeys: String, CodingKey {
        case generatedAt = "generated_at"
        case schemaVersion = "schema_version"
        case projectSlug = "project_slug"
        case moments
    }
}

public struct SounioWorkdaySnapshot: Codable, Equatable, Sendable {
    public let generatedAt: String
    public let schemaVersion: String
    public let projectSlug: String
    public let status: String
    public let latestMoment: SounioMoment?
    public let moments: [SounioMoment]
    public let claimSeeds: [SounioClaim]
    public let decisionSeeds: [String]
    public let evidenceRefs: [String]
    public let tensions: [String]
    public let agents: [String]
    public let nextAction: String
    public let reviewQueueCount: Int
    public let restrictedLeakCheck: String
    public let provenance: ExocortexJSONValue?

    enum CodingKeys: String, CodingKey {
        case generatedAt = "generated_at"
        case schemaVersion = "schema_version"
        case projectSlug = "project_slug"
        case status
        case latestMoment = "latest_moment"
        case moments
        case claimSeeds = "claim_seeds"
        case decisionSeeds = "decision_seeds"
        case evidenceRefs = "evidence_refs"
        case tensions
        case agents
        case nextAction = "next_action"
        case reviewQueueCount = "review_queue_count"
        case restrictedLeakCheck = "restricted_leak_check"
        case provenance
    }
}

public struct SounioNowContext: Codable, Equatable, Sendable {
    public let status: String
    public let momentLine: String
    public let decisionLine: String?
    public let claimLine: String?
    public let agentLine: String?
    public let nextGesture: String
    public let truthMode: String
    public let reviewQueueCount: Int

    public static func synthesized(from home: ExocortexHomeSnapshot?) -> SounioNowContext {
        synthesized(home: home, workday: home?.sounioWorkdayContext)
    }

    public static func synthesized(home: ExocortexHomeSnapshot?, workday: SounioWorkdaySnapshot?) -> SounioNowContext {
        let latest = workday?.latestMoment
        let claim = workday?.claimSeeds.first ?? latest?.claimSeeds.first
        return SounioNowContext(
            status: workday?.status ?? home?.trustContext?.sounioWorkdayStatus ?? "waiting-for-sounio-signal",
            momentLine: latest?.summary ?? home?.trustContext?.sounioLatestMoment ?? "Capture a real Sounio work gesture.",
            decisionLine: workday?.decisionSeeds.first,
            claimLine: claim.map { "\($0.epistemicStatus): \($0.claimText)" },
            agentLine: workday?.agents.first ?? home?.trustContext?.latestAgentWrite,
            nextGesture: workday?.nextAction ?? home?.recommendedNextAction ?? "Open Memory Lens and ask what changed today.",
            truthMode: home?.clusterTruth ?? "remembered",
            reviewQueueCount: workday?.reviewQueueCount ?? 0
        )
    }
}

public struct SounioClaimGraph: Codable, Equatable, Sendable {
    public let paperRunId: String
    public let generatedAt: String
    public let schemaVersion: String
    public let claims: [SounioClaim]
    public let edges: [ExocortexJSONValue]
    public let statusCounts: [String: Int]
    public let unsupportedClaimIds: [String]
    public let robustClaimIds: [String]

    enum CodingKeys: String, CodingKey {
        case paperRunId = "paper_run_id"
        case generatedAt = "generated_at"
        case schemaVersion = "schema_version"
        case claims
        case edges
        case statusCounts = "status_counts"
        case unsupportedClaimIds = "unsupported_claim_ids"
        case robustClaimIds = "robust_claim_ids"
    }
}

public struct PaperRunTheatreSnapshot: Codable, Equatable, Sendable {
    public let paperRunId: String
    public let generatedAt: String
    public let schemaVersion: String
    public let paperRun: PaperRun
    public let manuscriptMarkdown: String
    public let claimGraph: SounioClaimGraph
    public let traceEvents: [SounioTraceEvent]
    public let agentContributions: [ExocortexJSONValue]
    public let approvals: [ExocortexJSONValue]
    public let evidenceTable: [ExocortexJSONValue]
    public let sounioScore: ExocortexJSONValue?
    public let currentStage: String
    public let nextAction: String
    public let publicDigestStatus: String
    public let privateTraceRef: String

    enum CodingKeys: String, CodingKey {
        case paperRunId = "paper_run_id"
        case generatedAt = "generated_at"
        case schemaVersion = "schema_version"
        case paperRun = "paper_run"
        case manuscriptMarkdown = "manuscript_markdown"
        case claimGraph = "claim_graph"
        case traceEvents = "trace_events"
        case agentContributions = "agent_contributions"
        case approvals
        case evidenceTable = "evidence_table"
        case sounioScore = "sounio_score"
        case currentStage = "current_stage"
        case nextAction = "next_action"
        case publicDigestStatus = "public_digest_status"
        case privateTraceRef = "private_trace_ref"
    }
}

public struct PublicDigestArtifact: Codable, Equatable, Sendable {
    public let paperRunId: String
    public let generatedAt: String
    public let schemaVersion: String
    public let title: String
    public let thesis: String
    public let sanitizedClaims: [ExocortexJSONValue]
    public let sedenionSSMCase: ExocortexJSONValue?
    public let publicTraceDigest: [ExocortexJSONValue]
    public let disclosure: String
    public let excludedPrivateTracePolicy: String
    public let manuscriptExcerpt: String

    enum CodingKeys: String, CodingKey {
        case paperRunId = "paper_run_id"
        case generatedAt = "generated_at"
        case schemaVersion = "schema_version"
        case title
        case thesis
        case sanitizedClaims = "sanitized_claims"
        case sedenionSSMCase = "sedenion_ssm_case"
        case publicTraceDigest = "public_trace_digest"
        case disclosure
        case excludedPrivateTracePolicy = "excluded_private_trace_policy"
        case manuscriptExcerpt = "manuscript_excerpt"
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

public struct TranscriptionSegment: Codable, Equatable, Sendable, Identifiable {
    public var id: String { "\(startMs ?? 0)-\(endMs ?? 0)-\(text.hashValue)" }
    public let text: String
    public let startMs: Int?
    public let endMs: Int?
    public let confidence: Double?
    public let source: String?

    public init(
        text: String,
        startMs: Int? = nil,
        endMs: Int? = nil,
        confidence: Double? = nil,
        source: String? = nil
    ) {
        self.text = text
        self.startMs = startMs
        self.endMs = endMs
        self.confidence = confidence
        self.source = source
    }

    enum CodingKeys: String, CodingKey {
        case text
        case startMs = "start_ms"
        case endMs = "end_ms"
        case confidence
        case source
    }
}

public enum MultimodalComposerState: String, Codable, Equatable, Sendable, CaseIterable {
    case text
    case voice
    case image
}

public struct CaptureSessionStartRequest: Codable, Equatable, Sendable {
    public let projectSlug: String?
    public let mode: String?
    public let surface: String?
    public let principal: String?
    public let title: String?
    public let privacyClass: String?
    public let metadata: ExocortexJSONValue?

    public init(
        projectSlug: String? = "sounio",
        mode: String? = "thinking_aloud",
        surface: String? = "beagle-apple-composer",
        principal: String? = "beagle-apple-app",
        title: String? = nil,
        privacyClass: String? = "sensitive",
        metadata: ExocortexJSONValue? = nil
    ) {
        self.projectSlug = projectSlug
        self.mode = mode
        self.surface = surface
        self.principal = principal
        self.title = title
        self.privacyClass = privacyClass
        self.metadata = metadata
    }

    enum CodingKeys: String, CodingKey {
        case projectSlug = "project_slug"
        case mode
        case surface
        case principal
        case title
        case privacyClass = "privacy_class"
        case metadata
    }
}

public struct CaptureSession: Codable, Equatable, Sendable, Identifiable {
    public let id: String
    public let createdAt: String
    public let updatedAt: String
    public let schemaVersion: String
    public let projectSlug: String
    public let mode: String
    public let surface: String
    public let principal: String
    public let title: String?
    public let privacyClass: String
    public let status: String
    public let rawAudioPolicy: String
    public let rawImagePolicy: String
    public let transcriptionSegments: [TranscriptionSegment]
    public let artifactRefs: [String]
    public let evidenceRefs: [String]
    public let reviewState: String
    public let provenance: ExocortexJSONValue?

    enum CodingKeys: String, CodingKey {
        case id
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case schemaVersion = "schema_version"
        case projectSlug = "project_slug"
        case mode
        case surface
        case principal
        case title
        case privacyClass = "privacy_class"
        case status
        case rawAudioPolicy = "raw_audio_policy"
        case rawImagePolicy = "raw_image_policy"
        case transcriptionSegments = "transcription_segments"
        case artifactRefs = "artifact_refs"
        case evidenceRefs = "evidence_refs"
        case reviewState = "review_state"
        case provenance
    }
}

public struct CaptureSessionEventRequest: Codable, Equatable, Sendable {
    public let eventType: String
    public let text: String?
    public let transcriptionSegments: [TranscriptionSegment]
    public let artifactRefs: [String]
    public let evidenceRefs: [String]
    public let privacyClass: String?
    public let metadata: ExocortexJSONValue?

    public init(
        eventType: String,
        text: String? = nil,
        transcriptionSegments: [TranscriptionSegment] = [],
        artifactRefs: [String] = [],
        evidenceRefs: [String] = [],
        privacyClass: String? = "sensitive",
        metadata: ExocortexJSONValue? = nil
    ) {
        self.eventType = eventType
        self.text = text
        self.transcriptionSegments = transcriptionSegments
        self.artifactRefs = artifactRefs
        self.evidenceRefs = evidenceRefs
        self.privacyClass = privacyClass
        self.metadata = metadata
    }

    enum CodingKeys: String, CodingKey {
        case eventType = "event_type"
        case text
        case transcriptionSegments = "transcription_segments"
        case artifactRefs = "artifact_refs"
        case evidenceRefs = "evidence_refs"
        case privacyClass = "privacy_class"
        case metadata
    }
}

public struct CaptureSessionEvent: Codable, Equatable, Sendable, Identifiable {
    public let id: String
    public let createdAt: String
    public let sessionId: String
    public let eventType: String
    public let text: String?
    public let transcriptionSegments: [TranscriptionSegment]
    public let artifactRefs: [String]
    public let evidenceRefs: [String]
    public let privacyClass: String
    public let metadata: ExocortexJSONValue?

    enum CodingKeys: String, CodingKey {
        case id
        case createdAt = "created_at"
        case sessionId = "session_id"
        case eventType = "event_type"
        case text
        case transcriptionSegments = "transcription_segments"
        case artifactRefs = "artifact_refs"
        case evidenceRefs = "evidence_refs"
        case privacyClass = "privacy_class"
        case metadata
    }
}

public struct VisualEvidenceArtifactRequest: Codable, Equatable, Sendable {
    public let sessionId: String?
    public let projectSlug: String?
    public let sourceSurface: String?
    public let sourceKind: String?
    public let mediaType: String?
    public let contentHash: String
    public let contentRef: String?
    public let artifactDataBase64: String?
    public let artifactByteCount: Int?
    public let localSummary: String?
    public let extractedText: String?
    public let localHints: [String]
    public let privacyClass: String?
    public let confirmationState: String?
    public let metadata: ExocortexJSONValue?

    public init(
        sessionId: String? = nil,
        projectSlug: String? = "sounio",
        sourceSurface: String? = "beagle-apple-visual-capture",
        sourceKind: String? = "image",
        mediaType: String? = "image",
        contentHash: String,
        contentRef: String? = nil,
        artifactDataBase64: String? = nil,
        artifactByteCount: Int? = nil,
        localSummary: String? = nil,
        extractedText: String? = nil,
        localHints: [String] = [],
        privacyClass: String? = "sensitive",
        confirmationState: String? = "local_preview_only",
        metadata: ExocortexJSONValue? = nil
    ) {
        self.sessionId = sessionId
        self.projectSlug = projectSlug
        self.sourceSurface = sourceSurface
        self.sourceKind = sourceKind
        self.mediaType = mediaType
        self.contentHash = contentHash
        self.contentRef = contentRef
        self.artifactDataBase64 = artifactDataBase64
        self.artifactByteCount = artifactByteCount
        self.localSummary = localSummary
        self.extractedText = extractedText
        self.localHints = localHints
        self.privacyClass = privacyClass
        self.confirmationState = confirmationState
        self.metadata = metadata
    }

    enum CodingKeys: String, CodingKey {
        case sessionId = "session_id"
        case projectSlug = "project_slug"
        case sourceSurface = "source_surface"
        case sourceKind = "source_kind"
        case mediaType = "media_type"
        case contentHash = "content_hash"
        case contentRef = "content_ref"
        case artifactDataBase64 = "artifact_data_base64"
        case artifactByteCount = "artifact_byte_count"
        case localSummary = "local_summary"
        case extractedText = "extracted_text"
        case localHints = "local_hints"
        case privacyClass = "privacy_class"
        case confirmationState = "confirmation_state"
        case metadata
    }
}

public struct VisualEvidenceArtifact: Codable, Equatable, Sendable, Identifiable {
    public let id: String
    public let createdAt: String
    public let schemaVersion: String
    public let sessionId: String?
    public let projectSlug: String
    public let sourceSurface: String
    public let sourceKind: String
    public let mediaType: String
    public let contentHash: String
    public let contentRef: String?
    public let artifactByteCount: Int?
    public let localSummary: String?
    public let extractedText: String?
    public let localHints: [String]
    public let privacyClass: String
    public let confirmationState: String
    public let privateArtifactPolicy: String
    public let provenance: ExocortexJSONValue?

    enum CodingKeys: String, CodingKey {
        case id
        case createdAt = "created_at"
        case schemaVersion = "schema_version"
        case sessionId = "session_id"
        case projectSlug = "project_slug"
        case sourceSurface = "source_surface"
        case sourceKind = "source_kind"
        case mediaType = "media_type"
        case contentHash = "content_hash"
        case contentRef = "content_ref"
        case artifactByteCount = "artifact_byte_count"
        case localSummary = "local_summary"
        case extractedText = "extracted_text"
        case localHints = "local_hints"
        case privacyClass = "privacy_class"
        case confirmationState = "confirmation_state"
        case privateArtifactPolicy = "private_artifact_policy"
        case provenance
    }
}

public struct CaptureReviewCandidate: Codable, Equatable, Sendable, Identifiable {
    public let id: String
    public let kind: String
    public let title: String
    public let summary: String
    public let evidenceRefs: [String]
    public let claimText: String?
    public let decisionText: String?
    public let nextAction: String?
    public let epistemicStatus: String?
    public let confidence: Double?
    public let privacyClass: String
    public let provenance: ExocortexJSONValue?

    public init(
        id: String = UUID().uuidString,
        kind: String,
        title: String,
        summary: String,
        evidenceRefs: [String] = [],
        claimText: String? = nil,
        decisionText: String? = nil,
        nextAction: String? = nil,
        epistemicStatus: String? = "belief",
        confidence: Double? = nil,
        privacyClass: String = "sensitive",
        provenance: ExocortexJSONValue? = nil
    ) {
        self.id = id
        self.kind = kind
        self.title = title
        self.summary = summary
        self.evidenceRefs = evidenceRefs
        self.claimText = claimText
        self.decisionText = decisionText
        self.nextAction = nextAction
        self.epistemicStatus = epistemicStatus
        self.confidence = confidence
        self.privacyClass = privacyClass
        self.provenance = provenance
    }

    enum CodingKeys: String, CodingKey {
        case id
        case kind
        case title
        case summary
        case evidenceRefs = "evidence_refs"
        case claimText = "claim_text"
        case decisionText = "decision_text"
        case nextAction = "next_action"
        case epistemicStatus = "epistemic_status"
        case confidence
        case privacyClass = "privacy_class"
        case provenance
    }
}

public struct VisualEvidenceAnalyzeRequest: Codable, Equatable, Sendable {
    public let artifactId: String
    public let prompt: String?
    public let allowExternalModel: Bool
    public let preferredProvider: String?
    public let localAnalysis: ExocortexJSONValue?
    public let redactionSummary: String?
    public let principal: String?
    public let surface: String?

    public init(
        artifactId: String,
        prompt: String? = nil,
        allowExternalModel: Bool = false,
        preferredProvider: String? = nil,
        localAnalysis: ExocortexJSONValue? = nil,
        redactionSummary: String? = nil,
        principal: String? = "beagle-apple-app",
        surface: String? = "beagle-apple-visual-capture"
    ) {
        self.artifactId = artifactId
        self.prompt = prompt
        self.allowExternalModel = allowExternalModel
        self.preferredProvider = preferredProvider
        self.localAnalysis = localAnalysis
        self.redactionSummary = redactionSummary
        self.principal = principal
        self.surface = surface
    }

    enum CodingKeys: String, CodingKey {
        case artifactId = "artifact_id"
        case prompt
        case allowExternalModel = "allow_external_model"
        case preferredProvider = "preferred_provider"
        case localAnalysis = "local_analysis"
        case redactionSummary = "redaction_summary"
        case principal
        case surface
    }
}

public struct VisualEvidenceAnalysis: Codable, Equatable, Sendable, Identifiable {
    public let id: String
    public let createdAt: String
    public let schemaVersion: String
    public let artifactId: String
    public let mode: String
    public let provider: String
    public let status: String
    public let summary: String
    public let claimMap: [CaptureReviewCandidate]
    public let evidenceRefs: [String]
    public let tensions: [String]
    public let missingEvidence: [String]
    public let restrictedLeakCheck: String
    public let requiresConfirmation: Bool
    public let provenance: ExocortexJSONValue?
    public let degradedReason: String?

    enum CodingKeys: String, CodingKey {
        case id
        case createdAt = "created_at"
        case schemaVersion = "schema_version"
        case artifactId = "artifact_id"
        case mode
        case provider
        case status
        case summary
        case claimMap = "claim_map"
        case evidenceRefs = "evidence_refs"
        case tensions
        case missingEvidence = "missing_evidence"
        case restrictedLeakCheck = "restricted_leak_check"
        case requiresConfirmation = "requires_confirmation"
        case provenance
        case degradedReason = "degraded_reason"
    }
}

public struct CaptureReviewRequest: Codable, Equatable, Sendable {
    public let sessionId: String?
    public let artifactId: String?
    public let projectSlug: String?
    public let sourceSurface: String?
    public let candidates: [CaptureReviewCandidate]
    public let decision: String?
    public let reviewer: String?
    public let promote: Bool
    public let privacyClass: String?
    public let provenance: ExocortexJSONValue?

    public init(
        sessionId: String? = nil,
        artifactId: String? = nil,
        projectSlug: String? = "sounio",
        sourceSurface: String? = "beagle-apple-capture-review",
        candidates: [CaptureReviewCandidate],
        decision: String? = "promote",
        reviewer: String? = "demetrios",
        promote: Bool = true,
        privacyClass: String? = "sensitive",
        provenance: ExocortexJSONValue? = nil
    ) {
        self.sessionId = sessionId
        self.artifactId = artifactId
        self.projectSlug = projectSlug
        self.sourceSurface = sourceSurface
        self.candidates = candidates
        self.decision = decision
        self.reviewer = reviewer
        self.promote = promote
        self.privacyClass = privacyClass
        self.provenance = provenance
    }

    enum CodingKeys: String, CodingKey {
        case sessionId = "session_id"
        case artifactId = "artifact_id"
        case projectSlug = "project_slug"
        case sourceSurface = "source_surface"
        case candidates
        case decision
        case reviewer
        case promote
        case privacyClass = "privacy_class"
        case provenance
    }
}

public struct AuditEvent: Codable, Equatable, Sendable, Identifiable {
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

public struct MemoryEvent: Codable, Equatable, Sendable, Identifiable {
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

public struct CaptureReviewResult: Codable, Equatable, Sendable, Identifiable {
    public let id: String
    public let createdAt: String
    public let schemaVersion: String
    public let status: String
    public let promotedCount: Int
    public let sounioMoments: [SounioMoment]
    public let memoryEvent: MemoryEvent?
    public let auditEvent: AuditEvent?
    public let candidates: [CaptureReviewCandidate]

    enum CodingKeys: String, CodingKey {
        case id
        case createdAt = "created_at"
        case schemaVersion = "schema_version"
        case status
        case promotedCount = "promoted_count"
        case sounioMoments = "sounio_moments"
        case memoryEvent = "memory_event"
        case auditEvent = "audit_event"
        case candidates
    }
}

public struct ChatMemoryTimelineEvent: Codable, Equatable, Sendable, Identifiable {
    public let id: String
    public let label: String
    public let status: String
    public let timestamp: Date
    public let truthMode: TruthMode

    public init(
        id: String = UUID().uuidString,
        label: String,
        status: String,
        timestamp: Date = .now,
        truthMode: TruthMode = .declared
    ) {
        self.id = id
        self.label = label
        self.status = status
        self.timestamp = timestamp
        self.truthMode = truthMode
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
    public let captureSessionId: String?
    public let artifactRefs: [String]
    public let transcriptionSegments: [TranscriptionSegment]
    public let visualEvidenceRefs: [String]

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
        createChronoselfCommit: Bool? = false,
        captureSessionId: String? = nil,
        artifactRefs: [String] = [],
        transcriptionSegments: [TranscriptionSegment] = [],
        visualEvidenceRefs: [String] = []
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
        self.captureSessionId = captureSessionId
        self.artifactRefs = artifactRefs
        self.transcriptionSegments = transcriptionSegments
        self.visualEvidenceRefs = visualEvidenceRefs
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
        case captureSessionId = "capture_session_id"
        case artifactRefs = "artifact_refs"
        case transcriptionSegments = "transcription_segments"
        case visualEvidenceRefs = "visual_evidence_refs"
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
    public let retrievalAgentStatus: String?
    public let latestRetrievalStrategy: String?
    public let memoryarenaGate: String?
    public let contextCompilerStatus: String?
    public let latestContextPackId: String?
    public let memoryPolicyStatus: String?
    public let policyGate: String?
    public let dreamcycleStatus: String?
    public let sounioPaperRunStatus: String?
    public let sounioTemporalStatus: String?
    public let sounioPendingApproval: String?
    public let sounioLatestArtifact: String?
    public let sounioWorkdayStatus: String?
    public let sounioLatestMoment: String?
    public let sounioPendingMomentReview: String?

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
        case retrievalAgentStatus = "retrieval_agent_status"
        case latestRetrievalStrategy = "latest_retrieval_strategy"
        case memoryarenaGate = "memoryarena_gate"
        case contextCompilerStatus = "context_compiler_status"
        case latestContextPackId = "latest_context_pack_id"
        case memoryPolicyStatus = "memory_policy_status"
        case policyGate = "policy_gate"
        case dreamcycleStatus = "dreamcycle_status"
        case sounioPaperRunStatus = "sounio_paperrun_status"
        case sounioTemporalStatus = "sounio_temporal_status"
        case sounioPendingApproval = "sounio_pending_approval"
        case sounioLatestArtifact = "sounio_latest_artifact"
        case sounioWorkdayStatus = "sounio_workday_status"
        case sounioLatestMoment = "sounio_latest_moment"
        case sounioPendingMomentReview = "sounio_pending_moment_review"
    }
}

public struct LivingHomeMode: RawRepresentable, Codable, Equatable, Hashable, Sendable {
    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }

    public static let live = LivingHomeMode(rawValue: "live")
    public static let remembered = LivingHomeMode(rawValue: "remembered")
    public static let offline = LivingHomeMode(rawValue: "offline")
    public static let attention = LivingHomeMode(rawValue: "attention")
    public static let review = LivingHomeMode(rawValue: "review")
    public static let capture = LivingHomeMode(rawValue: "capture")
}

public struct HomeContinuitySignal: Codable, Equatable, Sendable, Identifiable {
    public let id: String
    public let title: String
    public let detail: String
    public let kind: String
    public let sourceSurface: String?
    public let observedAt: String?
    public let truthMode: String
    public let provenanceRefs: [String]

    public init(
        id: String,
        title: String,
        detail: String,
        kind: String,
        sourceSurface: String? = nil,
        observedAt: String? = nil,
        truthMode: String = "declared",
        provenanceRefs: [String] = []
    ) {
        self.id = id
        self.title = title
        self.detail = detail
        self.kind = kind
        self.sourceSurface = sourceSurface
        self.observedAt = observedAt
        self.truthMode = truthMode
        self.provenanceRefs = provenanceRefs
    }

    enum CodingKeys: String, CodingKey {
        case id
        case title
        case detail
        case kind
        case sourceSurface = "source_surface"
        case observedAt = "observed_at"
        case truthMode = "truth_mode"
        case provenanceRefs = "provenance_refs"
    }
}

public struct HomeNextMove: Codable, Equatable, Sendable, Identifiable {
    public let id: String
    public let title: String
    public let detail: String
    public let action: String
    public let systemImage: String
    public let reason: String
    public let priority: Int
    public let target: String?

    public init(
        id: String,
        title: String,
        detail: String,
        action: String,
        systemImage: String,
        reason: String,
        priority: Int = 0,
        target: String? = nil
    ) {
        self.id = id
        self.title = title
        self.detail = detail
        self.action = action
        self.systemImage = systemImage
        self.reason = reason
        self.priority = priority
        self.target = target
    }

    enum CodingKeys: String, CodingKey {
        case id
        case title
        case detail
        case action
        case systemImage = "system_image"
        case reason
        case priority
        case target
    }
}

public struct HomeContinuityContext: Codable, Equatable, Sendable {
    public let generatedAt: String
    public let mode: LivingHomeMode
    public let changedSinceLastOpen: [HomeContinuitySignal]
    public let latestSurfaceWrite: HomeContinuitySignal?
    public let activeThread: String?
    public let primaryNextAction: HomeNextMove
    public let alternativeNextActions: [HomeNextMove]
    public let whyThisNow: String
    public let confidence: Double
    public let sourceMode: String

    public init(
        generatedAt: String,
        mode: LivingHomeMode,
        changedSinceLastOpen: [HomeContinuitySignal],
        latestSurfaceWrite: HomeContinuitySignal?,
        activeThread: String?,
        primaryNextAction: HomeNextMove,
        alternativeNextActions: [HomeNextMove] = [],
        whyThisNow: String,
        confidence: Double,
        sourceMode: String
    ) {
        self.generatedAt = generatedAt
        self.mode = mode
        self.changedSinceLastOpen = changedSinceLastOpen
        self.latestSurfaceWrite = latestSurfaceWrite
        self.activeThread = activeThread
        self.primaryNextAction = primaryNextAction
        self.alternativeNextActions = alternativeNextActions
        self.whyThisNow = whyThisNow
        self.confidence = confidence
        self.sourceMode = sourceMode
    }

    enum CodingKeys: String, CodingKey {
        case generatedAt = "generated_at"
        case mode
        case changedSinceLastOpen = "changed_since_last_open"
        case latestSurfaceWrite = "latest_surface_write"
        case activeThread = "active_thread"
        case primaryNextAction = "primary_next_action"
        case alternativeNextActions = "alternative_next_actions"
        case whyThisNow = "why_this_now"
        case confidence
        case sourceMode = "source_mode"
    }
}

public extension HomeContinuityContext {
    static func synthesized(
        home: ExocortexHomeSnapshot,
        truthMode: TruthMode,
        previousHome: ExocortexHomeSnapshot? = nil,
        recentGraph: MemoryGraphRecentResponse? = nil,
        projectionStatus: MemoryProjectionStatus? = nil,
        originLineage: OriginLineageSnapshot? = nil
    ) -> HomeContinuityContext {
        var signals: [HomeContinuitySignal] = []

        if truthMode == .stale {
            signals.append(HomeContinuitySignal(
                id: "home-offline-cache",
                title: "Offline cache",
                detail: "The last remembered Home is visible while cluster truth is unavailable.",
                kind: "cache",
                sourceSurface: "swiftdata-cache",
                observedAt: previousHome?.generatedAt,
                truthMode: truthMode.rawValue,
                provenanceRefs: ["swiftdata-cache"]
            ))
        } else if previousHome?.generatedAt != nil, previousHome?.generatedAt != home.generatedAt {
            signals.append(HomeContinuitySignal(
                id: "home-cluster-refresh",
                title: "Cluster refreshed",
                detail: "Live cluster truth replaced the last remembered Home.",
                kind: "cluster_refresh",
                sourceSurface: "beagle-core",
                observedAt: home.generatedAt,
                truthMode: truthMode.rawValue,
                provenanceRefs: ["home:\(home.generatedAt)"]
            ))
        }

        if let last = home.agentContext?.lastAgentWrite ?? home.trustContext?.latestAgentWrite, !last.isEmpty {
            signals.append(HomeContinuitySignal(
                id: "latest-agent-write-\(stableSignalSuffix(last))",
                title: "Agent wrote memory",
                detail: last,
                kind: "agent_write",
                sourceSurface: "mcp-agent",
                observedAt: home.trustContext?.auditFreshness,
                truthMode: "observed",
                provenanceRefs: home.trustContext?.lastAuditEventId.map { [$0] } ?? []
            ))
        }

        if let capture = home.trustContext?.appleCaptureFreshness ?? home.trustContext?.captureLoopStatus, !capture.isEmpty {
            signals.append(HomeContinuitySignal(
                id: "apple-capture-\(stableSignalSuffix(capture))",
                title: "Apple capture loop",
                detail: capture,
                kind: "apple_capture",
                sourceSurface: "beagle-apple",
                observedAt: home.generatedAt,
                truthMode: "observed",
                provenanceRefs: ["home.trust_context.capture"]
            ))
        }

        if let graphSignal = latestGraphSignal(from: recentGraph) {
            signals.append(graphSignal)
        }

        if let projectionStatus {
            let detail = "\(projectionStatus.episodeCount) episodes · \(projectionStatus.atomCount) atoms · \(projectionStatus.retrievalMode)"
            signals.append(HomeContinuitySignal(
                id: "memory-projection-\(projectionStatus.status)",
                title: "Memory projection",
                detail: detail,
                kind: "memory_projection",
                sourceSurface: "beagle-core",
                observedAt: projectionStatus.latestRun?.createdAt,
                truthMode: projectionStatus.status == "fresh" ? "observed" : "remembered",
                provenanceRefs: projectionStatus.latestRun.map { [$0.id] } ?? []
            ))
        }

        if let originLineage, !originLineage.nodes.isEmpty {
            signals.append(HomeContinuitySignal(
                id: "origin-lineage-\(originLineage.sourcePolicy)",
                title: "Origin lineage",
                detail: "RAG++ -> Darwin -> Beagle -> Sounio remains visible as sanitized memory archaeology.",
                kind: "origin_lineage",
                sourceSurface: originLineage.sourcePolicy.contains("cluster") ? "beagle-core" : "local-seed",
                observedAt: originLineage.generatedAt,
                truthMode: originLineage.sourcePolicy.contains("cluster") ? "observed" : "remembered",
                provenanceRefs: originLineage.evidenceRefs.map(\.id)
            ))
        }

        for signal in home.memorySignals.prefix(2) where !signal.localizedCaseInsensitiveContains("restricted") {
            signals.append(HomeContinuitySignal(
                id: "home-memory-signal-\(stableSignalSuffix(signal))",
                title: "Memory signal",
                detail: signal,
                kind: "memory_signal",
                sourceSurface: "exocortex-home",
                observedAt: home.generatedAt,
                truthMode: truthMode.rawValue,
                provenanceRefs: []
            ))
        }

        let uniqueSignals = unique(signals).prefix(6)
        let latestSurfaceWrite = uniqueSignals.first {
            ["agent_write", "apple_capture", "grok_import", "work_memory"].contains($0.kind)
        }
        let moves = nextMoves(
            home: home,
            truthMode: truthMode,
            latestSurfaceWrite: latestSurfaceWrite,
            signals: Array(uniqueSignals)
        )
        let mode = livingMode(home: home, truthMode: truthMode, latestSurfaceWrite: latestSurfaceWrite)

        return HomeContinuityContext(
            generatedAt: home.generatedAt,
            mode: mode,
            changedSinceLastOpen: Array(uniqueSignals),
            latestSurfaceWrite: latestSurfaceWrite,
            activeThread: home.activeProjectRef ?? home.temporalPhase,
            primaryNextAction: moves.primary,
            alternativeNextActions: moves.alternatives,
            whyThisNow: whyThisNow(
                home: home,
                truthMode: truthMode,
                primary: moves.primary,
                latestSurfaceWrite: latestSurfaceWrite
            ),
            confidence: confidence(truthMode: truthMode, signalCount: uniqueSignals.count),
            sourceMode: "local_synthesis"
        )
    }

    private static func latestGraphSignal(from graph: MemoryGraphRecentResponse?) -> HomeContinuitySignal? {
        guard let graph else { return nil }

        if let episode = graph.episodes.first(where: {
            $0.privacyClass != "restricted" && haystack(for: $0).contains("grok")
        }) {
            return HomeContinuitySignal(
                id: "grok-import-\(episode.id)",
                title: "Grok import signal",
                detail: episode.title ?? "Grok context is projected into GraphRAG++ memory.",
                kind: "grok_import",
                sourceSurface: episode.sourcePlatform ?? episode.source,
                observedAt: episode.occurredAt ?? episode.createdAt,
                truthMode: "observed",
                provenanceRefs: [episode.sourceRef]
            )
        }

        if let atom = graph.atoms.first(where: {
            $0.privacyClass != "restricted" && haystack(for: $0).contains("work-memory")
        }) {
            return HomeContinuitySignal(
                id: "work-memory-\(atom.id)",
                title: "Work memory",
                detail: "Codex or Claude Code work context is now recoverable.",
                kind: "work_memory",
                sourceSurface: "agent-work-memory",
                observedAt: atom.occurredAt ?? atom.createdAt,
                truthMode: "observed",
                provenanceRefs: atom.sourceRefs
            )
        }

        if let episode = graph.episodes.first(where: {
            $0.privacyClass != "restricted" && haystack(for: $0).contains("watch")
        }) {
            return HomeContinuitySignal(
                id: "watch-capture-\(episode.id)",
                title: "Watch capture",
                detail: "A wrist micro-intention reached cluster memory.",
                kind: "apple_capture",
                sourceSurface: episode.sourcePlatform ?? "watchos",
                observedAt: episode.occurredAt ?? episode.createdAt,
                truthMode: "observed",
                provenanceRefs: [episode.sourceRef]
            )
        }

        return nil
    }

    private static func nextMoves(
        home: ExocortexHomeSnapshot,
        truthMode: TruthMode,
        latestSurfaceWrite: HomeContinuitySignal?,
        signals: [HomeContinuitySignal]
    ) -> (primary: HomeNextMove, alternatives: [HomeNextMove]) {
        let inspectTrust = HomeNextMove(
            id: "inspect-trust",
            title: "Inspect trust",
            detail: home.trustContext?.mcpStatus ?? "Check cluster, MCP and audit state.",
            action: "inspect_trust",
            systemImage: "checkmark.shield",
            reason: "The Home is stale or needs trust context before action.",
            priority: 90
        )
        let reviewClaim = HomeNextMove(
            id: "review-claim",
            title: "Review claim",
            detail: home.trustContext?.sounioPendingApproval ?? "\(home.trustContext?.pendingTriads ?? 0) pending Triad items",
            action: "review_claim",
            systemImage: "checklist.checked",
            reason: "A pending claim or Triad item needs human judgment.",
            priority: 80
        )
        let openMemory = HomeNextMove(
            id: "open-memory-lens",
            title: "Open Memory Lens",
            detail: latestSurfaceWrite?.title ?? "\(signals.count) continuity signals",
            action: "open_memory_lens",
            systemImage: "point.3.connected.trianglepath.dotted",
            reason: "New memory is visible; inspect evidence and provenance.",
            priority: 70
        )
        let resumeProject = HomeNextMove(
            id: "resume-project",
            title: "Resume \(home.activeProjectRef ?? "project")",
            detail: home.recommendedNextAction,
            action: "resume_project",
            systemImage: "arrow.forward.circle.fill",
            reason: "The active project is the highest-continuity thread.",
            priority: 60,
            target: home.activeProjectRef
        )
        let captureThought = HomeNextMove(
            id: "capture-thought",
            title: "Capture thought",
            detail: "Record the next intention as Episode+Atom.",
            action: "capture_thought",
            systemImage: "mic.fill",
            reason: "No urgent review exists; preserve the next thought before it evaporates.",
            priority: 40
        )

        let primary: HomeNextMove
        if truthMode == .stale {
            primary = inspectTrust
        } else if home.trustContext?.sounioPendingApproval?.isEmpty == false || (home.trustContext?.pendingTriads ?? 0) > 0 {
            primary = reviewClaim
        } else if latestSurfaceWrite != nil || !signals.isEmpty {
            primary = openMemory
        } else if home.activeProjectRef != nil {
            primary = resumeProject
        } else {
            primary = captureThought
        }

        let alternatives = [reviewClaim, openMemory, resumeProject, captureThought, inspectTrust]
            .filter { $0.id != primary.id }
        return (primary, alternatives)
    }

    private static func livingMode(
        home: ExocortexHomeSnapshot,
        truthMode: TruthMode,
        latestSurfaceWrite: HomeContinuitySignal?
    ) -> LivingHomeMode {
        if truthMode == .stale { return .offline }
        if home.trustContext?.sounioPendingApproval?.isEmpty == false || (home.trustContext?.pendingTriads ?? 0) > 0 {
            return .review
        }
        if latestSurfaceWrite?.kind == "apple_capture" { return .capture }
        if latestSurfaceWrite != nil { return .live }
        if truthMode == .remembered { return .remembered }
        return .attention
    }

    private static func whyThisNow(
        home: ExocortexHomeSnapshot,
        truthMode: TruthMode,
        primary: HomeNextMove,
        latestSurfaceWrite: HomeContinuitySignal?
    ) -> String {
        if truthMode == .stale {
            return "Beagle is showing remembered state; trust inspection comes before deeper action."
        }
        if let latestSurfaceWrite {
            return "\(latestSurfaceWrite.title) is the freshest change, so the safest next move is to inspect its provenance."
        }
        if primary.action == "review_claim" {
            return "A claim or Triad item is waiting for human judgment before promotion."
        }
        if !home.recommendedNextAction.isEmpty {
            return home.recommendedNextAction
        }
        return "No urgent write or review is visible; capture the next intention."
    }

    private static func confidence(truthMode: TruthMode, signalCount: Int) -> Double {
        switch truthMode {
        case .observed:
            return signalCount > 0 ? 0.88 : 0.72
        case .remembered:
            return 0.66
        case .declared:
            return 0.52
        case .stale:
            return 0.40
        }
    }

    private static func unique(_ signals: [HomeContinuitySignal]) -> [HomeContinuitySignal] {
        var seen = Set<String>()
        return signals.filter { signal in
            guard !seen.contains(signal.id) else { return false }
            seen.insert(signal.id)
            return true
        }
    }

    private static func stableSignalSuffix(_ text: String) -> String {
        text
            .lowercased()
            .unicodeScalars
            .filter { CharacterSet.alphanumerics.contains($0) }
            .prefix(24)
            .map(String.init)
            .joined()
    }

    private static func haystack(for episode: MemoryEpisode) -> String {
        (episode.tags + [
            episode.source,
            episode.sourcePlatform ?? "",
            episode.title ?? "",
            episode.sourceRef
        ]).joined(separator: " ").lowercased()
    }

    private static func haystack(for atom: MemoryAtom) -> String {
        (atom.tags + [
            atom.atomType,
            atom.text,
            atom.normalizedText
        ]).joined(separator: " ").lowercased()
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
    public let originLineage: OriginLineageSnapshot?
    public let continuityContext: HomeContinuityContext?
    public let sounioWorkdayContext: SounioWorkdaySnapshot?

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
        case originLineage = "origin_lineage"
        case continuityContext = "continuity_context"
        case sounioWorkdayContext = "sounio_workday_context"
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
        trustContext: nil,
        originLineage: nil,
        continuityContext: nil,
        sounioWorkdayContext: nil
    )
}
