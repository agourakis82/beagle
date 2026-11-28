//
//  ExocortexCaptureAuditModels.swift
//  BeagleCore
//
//  Audit & memory events, multimodal capture sessions, visual evidence
//  artifacts/analysis, capture review, and assisted conversation imports.
//

import Foundation

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
