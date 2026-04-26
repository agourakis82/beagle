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
    public let originalDate: String?
    public let rawContentRef: String
    public let extracted: OmniExtraction
    public let linkedChronoselfCommits: [String]
    public let linkedMemoryEvents: [String]
    public let confidenceScore: Double
    public let title: String?

    enum CodingKeys: String, CodingKey {
        case id
        case sourcePlatform = "source_platform"
        case importedAt = "imported_at"
        case originalDate = "original_date"
        case rawContentRef = "raw_content_ref"
        case extracted
        case linkedChronoselfCommits = "linked_chronoself_commits"
        case linkedMemoryEvents = "linked_memory_events"
        case confidenceScore = "confidence_score"
        case title
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

    enum CodingKeys: String, CodingKey {
        case mcpStatus = "mcp_status"
        case activeScopes = "active_scopes"
        case auditFreshness = "audit_freshness"
        case destructiveActions = "destructive_actions"
        case toolManifestHash = "tool_manifest_hash"
        case lastAuditEventId = "last_audit_event_id"
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
