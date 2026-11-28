//
//  ExocortexMemoryGovernanceModels.swift
//  BeagleCore
//
//  Memory episodes, atoms, governance/quorum/contradictions, graph projection,
//  worlds, context packs, policy, and dream-cycle contracts.
//

import Foundation

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
