//
//  ExocortexSounioPaperRunModels.swift
//  BeagleCore
//
//  Sounio epistemic program checks, PaperRun workflows & trace events,
//  claim input seeds, and Origin Lineage archaeology snapshots.
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
