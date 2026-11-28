//
//  ExocortexSpatialMindPalaceModels.swift
//  BeagleCore
//
//  Spatial Worlds, Control Room, Mind Palace, Desk, Conversation Portals,
//  Focus Coach, and Agent Work Memory contracts.
//

import Foundation

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
