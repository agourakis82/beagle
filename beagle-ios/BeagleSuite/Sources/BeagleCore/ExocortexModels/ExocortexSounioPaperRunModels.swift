//
//  ExocortexSounioPaperRunModels.swift
//  BeagleCore
//
//  Sounio epistemic program checks, PaperRun workflows & theatre snapshots,
//  Origin Lineage, Sounio claims/reviews, and ambient Sounio Moments/Workday.
//

import Foundation

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
