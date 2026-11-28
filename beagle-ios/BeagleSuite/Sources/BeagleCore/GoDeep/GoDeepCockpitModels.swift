//
//  GoDeepCockpitModels.swift
//  BeagleCore
//
//  Cockpit endpoint response models and Agent Scratchpad inter-agent types.
//  Convention: all public, Codable, Sendable, optional fields,
//  CodingKeys for snake_case JSON mapping.
//

import Foundation

// ============================================================================
// MARK: - Cockpit Response Models (new endpoints)
// ============================================================================

// MARK: - Project Memory (/api/projects/:slug/memory/fast, /deep)

public struct ProjectMemory: Codable, Sendable {
    public let project: Project?
    public let viewer: JSONValue?
    public let memory: JSONValue?
    public let generatedAt: String?
}

// MARK: - Sovereign Surface (/api/projects/:slug/sovereign-surface)

public struct SovereignSurface: Codable, Sendable {
    public let project: Project?
    public let viewer: JSONValue?
    public let surface: JSONValue?
    public let generatedAt: String?
}

// MARK: - Truth Summary (/api/projects/:slug/truth/summary)

public struct ProjectTruthSummary: Codable, Sendable {
    public let project: Project?
    public let viewer: JSONValue?
    public let summary: JSONValue?
    public let generatedAt: String?
}

// MARK: - Git (/api/projects/:slug/git/status, /git/diff)

public struct GitStatusResponse: Codable, Sendable {
    public let project: Project?
    public let git: GitStatusDetail?
}

public struct GitStatusDetail: Codable, Sendable {
    public let branch: String?
    public let dirty: Bool?
    public let dirtyCount: Int?
    public let aheadBehind: String?

    enum CodingKeys: String, CodingKey {
        case branch, dirty
        case dirtyCount = "dirty_count"
        case aheadBehind = "ahead_behind"
    }
}

public struct GitDiffResponse: Codable, Sendable {
    public let project: Project?
    public let diff: JSONValue?
}

// MARK: - Execution Packets (/api/projects/:slug/execution/packets)

public struct ExecutionPacketsResponse: Codable, Sendable {
    public let project: Project?
    public let viewer: JSONValue?
    public let packets: [ExecutionPacket]?
}

public struct ExecutionPacket: Codable, Sendable, Identifiable {
    public var id: String { packetId ?? UUID().uuidString }
    public let packetId: String?
    public let label: String?
    public let status: String?
    public let createdAt: String?

    enum CodingKeys: String, CodingKey {
        case packetId = "id"
        case label, status
        case createdAt = "created_at"
    }
}

// MARK: - Scientific Workflows (/api/projects/:slug/workflows/scientific)

public struct ScientificWorkflowsResponse: Codable, Sendable {
    public let project: Project?
    public let viewer: JSONValue?
    public let workflows: [ScientificWorkflow]?
}

public struct ScientificWorkflow: Codable, Sendable, Identifiable {
    public var id: String { workflowId ?? UUID().uuidString }
    public let workflowId: String?
    public let name: String?
    public let status: String?
    public let lastRunAt: String?

    enum CodingKeys: String, CodingKey {
        case workflowId = "id"
        case name, status
        case lastRunAt = "last_run_at"
    }
}

// MARK: - Dataset Catalog (/api/projects/:slug/datasets/catalog)

public struct DatasetCatalogResponse: Codable, Sendable {
    public let project: Project?
    public let viewer: JSONValue?
    public let datasets: [DatasetEntry]?
}

public struct DatasetEntry: Codable, Sendable, Identifiable {
    public var id: String { datasetId ?? UUID().uuidString }
    public let datasetId: String?
    public let name: String?
    public let format: String?
    public let sizeBytes: Int?

    enum CodingKeys: String, CodingKey {
        case datasetId = "id"
        case name, format
        case sizeBytes = "size_bytes"
    }
}

// MARK: - Session Heartbeat (/api/projects/:slug/session/heartbeat)

public struct SessionHeartbeatResponse: Codable, Sendable {
    public let viewer: JSONValue?
    public let session: JSONValue?
    public let sessions: JSONValue?
}

// MARK: - Apple Brief (/api/public/vision/apple-brief)

public struct AppleBriefResponse: Codable, Sendable {
    public let brief: JSONValue?
    public let generatedAt: String?
}

// MARK: - Control Room Vision (/api/public/vision/control-room)

public struct ControlRoomVisionResponse: Codable, Sendable {
    public let controlRoom: JSONValue?
    public let generatedAt: String?

    enum CodingKeys: String, CodingKey {
        case controlRoom = "control_room"
        case generatedAt
    }
}

// ============================================================================
// MARK: - Agent Scratchpad (inter-agent communication)
// ============================================================================

/// A message posted by any agent surface to the shared scratchpad.
public struct AgentMessage: Codable, Sendable, Identifiable {
    public var id: String { messageId ?? UUID().uuidString }
    public let messageId: String?
    public let agent: String?          // "claude-code-remote", "claude-code-ios", "chatgpt", "cockpit-web"
    public let surface: String?        // "mcp", "openapi", "ios", "web"
    public let kind: String?           // "deployed", "needs", "discovered", "completed", "question"
    public let content: String?
    public let metadata: JSONValue?
    public let createdAt: String?

    enum CodingKeys: String, CodingKey {
        case messageId = "id"
        case agent, surface, kind, content, metadata
        case createdAt = "created_at"
    }

    public init(
        messageId: String? = nil, agent: String?, surface: String?,
        kind: String?, content: String?, metadata: JSONValue? = nil, createdAt: String? = nil
    ) {
        self.messageId = messageId
        self.agent = agent
        self.surface = surface
        self.kind = kind
        self.content = content
        self.metadata = metadata
        self.createdAt = createdAt
    }
}

public struct AgentScratchpad: Codable, Sendable {
    public let messages: [AgentMessage]?
    public let generatedAt: String?

    enum CodingKeys: String, CodingKey {
        case messages
        case generatedAt = "generated_at"
    }
}

/// Real scratchpad response from cockpit (JSONL-backed).
public struct ScratchpadResponse: Codable, Sendable {
    public let projectSlug: String?
    public let entries: [ScratchpadEntry]?
    public let count: Int?
    public let truthMode: String?
}

public struct ConsciousnessState: Codable, Sendable {
    public let hrvMs: Double?
    public let readiness: Double?
    public let intensity: String?
    public let circadianPhase: String?
    public let capturedAt: String?

    enum CodingKeys: String, CodingKey {
        case hrvMs = "hrv_ms"
        case readiness
        case intensity
        case circadianPhase = "circadian_phase"
        case capturedAt = "captured_at"
    }

    public init(hrvMs: Double?, readiness: Double?, intensity: String?, circadianPhase: String?, capturedAt: String? = nil) {
        self.hrvMs = hrvMs
        self.readiness = readiness
        self.intensity = intensity
        self.circadianPhase = circadianPhase
        self.capturedAt = capturedAt
    }
}

public struct ScratchpadEntry: Codable, Sendable, Identifiable {
    public var id: String { entryId ?? UUID().uuidString }
    public let entryId: String?
    public let slug: String?
    public let agent: String?
    public let text: String?
    public let timestamp: String?
    public let consciousnessState: ConsciousnessState?

    enum CodingKeys: String, CodingKey {
        case entryId = "entry_id"
        case slug, agent, text, timestamp
        case consciousnessState = "consciousness_state"
    }
}

public struct AgentMessageAck: Codable, Sendable {
    public let ok: Bool?
    public let messageId: String?

    enum CodingKeys: String, CodingKey {
        case ok
        case messageId = "message_id"
    }
}
