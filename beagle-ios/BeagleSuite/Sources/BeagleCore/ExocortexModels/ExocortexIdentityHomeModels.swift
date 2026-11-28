//
//  ExocortexIdentityHomeModels.swift
//  BeagleCore
//
//  Identity (Chronoself), Omni-Conversation, Temporal Analysis, and Trust/Agent context.
//

import Foundation

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
