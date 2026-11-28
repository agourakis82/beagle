//
//  ExocortexSounioClaimsAndMomentsModels.swift
//  BeagleCore
//
//  Sounio epistemic claims, reviews, ambient moments, workday snapshots,
//  and PaperRun theatre / public digest models.
//

import Foundation

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
