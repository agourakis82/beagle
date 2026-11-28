//
//  WorkbenchTerminalModels.swift
//  BeagleCore
//
//  Workspace sessions, terminal panes, terminal blocks, approvals,
//  workbench authority/memory/bridge status, and WebSocket terminal events.
//

import Foundation

// MARK: - Workspace & Terminal Responses

public struct WorkspaceListResponse: Codable, Sendable {
    public let workspaces: [WorkspaceSummary]
    public let truthMode: String?

    public init(workspaces: [WorkspaceSummary] = [], truthMode: String? = nil) {
        self.workspaces = workspaces
        self.truthMode = truthMode
    }
}

public struct WorkspaceSummary: Codable, Identifiable, Sendable {
    public let slug: String
    public let title: String
    public let namespace: String
    public let workspaceRoot: String
    public let workspacePod: String
    public let workspaceContainer: String
    public let branch: String
    public let truthMode: String

    public var id: String { slug }

    public init(
        slug: String,
        title: String,
        namespace: String = "beagle",
        workspaceRoot: String = "",
        workspacePod: String = "",
        workspaceContainer: String = "",
        branch: String = "",
        truthMode: String = "declared"
    ) {
        self.slug = slug
        self.title = title
        self.namespace = namespace
        self.workspaceRoot = workspaceRoot
        self.workspacePod = workspacePod
        self.workspaceContainer = workspaceContainer
        self.branch = branch
        self.truthMode = truthMode
    }
}

public struct WorkspaceSessionListResponse: Codable, Sendable {
    public let projectSlug: String
    public let authority: WorkbenchAuthorityStatus?
    public let sessions: [WorkspaceSession]

    public init(projectSlug: String, sessions: [WorkspaceSession], authority: WorkbenchAuthorityStatus? = nil) {
        self.projectSlug = projectSlug
        self.authority = authority
        self.sessions = sessions
    }
}

public struct WorkspaceSessionResponse: Codable, Sendable {
    public let session: WorkspaceSession

    public init(session: WorkspaceSession) {
        self.session = session
    }
}

public struct WorkspacePaneResponse: Codable, Sendable {
    public let pane: TerminalPane
    public let session: WorkspaceSession

    public init(pane: TerminalPane, session: WorkspaceSession) {
        self.pane = pane
        self.session = session
    }
}

public struct WorkspaceBlocksResponse: Codable, Sendable {
    public let projectSlug: String
    public let sessionId: String
    public let authority: WorkbenchAuthorityStatus?
    public let blocks: [TerminalBlock]

    public init(projectSlug: String, sessionId: String, blocks: [TerminalBlock], authority: WorkbenchAuthorityStatus? = nil) {
        self.projectSlug = projectSlug
        self.sessionId = sessionId
        self.authority = authority
        self.blocks = blocks
    }
}

public struct WorkspaceRememberBlockResponse: Codable, Sendable {
    public let blockId: String
    public let memory: WorkbenchMemoryStatus

    public init(blockId: String, memory: WorkbenchMemoryStatus) {
        self.blockId = blockId
        self.memory = memory
    }
}

// MARK: - Sessions, Panes & Blocks

public struct WorkspaceSession: Codable, Identifiable, Sendable {
    public let id: String
    public let projectSlug: String
    public let title: String
    public let status: String
    public let layout: NotebookTerminalLayout
    public let createdAt: String
    public let updatedAt: String
    public let lastAttachedAt: String
    public let lastMemoryStatus: WorkbenchMemoryStatus?
    public let panes: [TerminalPane]
    public let sourceModel: String?
    public let bridgeVersion: String?
    public let sessionHash: String?
    public let rendererHint: String?
    public let authorityStatus: WorkbenchAuthorityStatus?

    public init(
        id: String,
        projectSlug: String,
        title: String,
        status: String = "active",
        layout: NotebookTerminalLayout = .notebook,
        createdAt: String = "",
        updatedAt: String = "",
        lastAttachedAt: String = "",
        lastMemoryStatus: WorkbenchMemoryStatus? = nil,
        panes: [TerminalPane] = [],
        sourceModel: String? = nil,
        bridgeVersion: String? = nil,
        sessionHash: String? = nil,
        rendererHint: String? = nil,
        authorityStatus: WorkbenchAuthorityStatus? = nil
    ) {
        self.id = id
        self.projectSlug = projectSlug
        self.title = title
        self.status = status
        self.layout = layout
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.lastAttachedAt = lastAttachedAt
        self.lastMemoryStatus = lastMemoryStatus
        self.panes = panes
        self.sourceModel = sourceModel
        self.bridgeVersion = bridgeVersion
        self.sessionHash = sessionHash
        self.rendererHint = rendererHint
        self.authorityStatus = authorityStatus
    }
}

public struct TerminalPane: Codable, Identifiable, Sendable {
    public let id: String
    public let title: String
    public let kind: String
    public let status: String
    public let createdAt: String
    public let lastAttachedAt: String
    public let cwd: String
    public let reconnectState: String?
    public let agentRole: String?
    public let providerSlot: String?
    public let modelId: String?
    public let routeReason: String?
    public let arousalMode: String?
    public let agent: AgentRunState?

    public init(
        id: String,
        title: String,
        kind: String = "human",
        status: String = "idle",
        createdAt: String = "",
        lastAttachedAt: String = "",
        cwd: String = "",
        reconnectState: String? = nil,
        agentRole: String? = nil,
        providerSlot: String? = nil,
        modelId: String? = nil,
        routeReason: String? = nil,
        arousalMode: String? = nil,
        agent: AgentRunState? = nil
    ) {
        self.id = id
        self.title = title
        self.kind = kind
        self.status = status
        self.createdAt = createdAt
        self.lastAttachedAt = lastAttachedAt
        self.cwd = cwd
        self.reconnectState = reconnectState
        self.agentRole = agentRole
        self.providerSlot = providerSlot
        self.modelId = modelId
        self.routeReason = routeReason
        self.arousalMode = arousalMode
        self.agent = agent
    }
}

public struct TerminalBlock: Codable, Identifiable, Sendable {
    public let id: String
    public let sessionId: String
    public let paneId: String
    public let kind: String
    public let title: String
    public let command: String
    public let outputPreview: String
    public let outputByteCount: Int
    public let startedAt: String
    public let finishedAt: String
    public let durationMs: Int?
    public let exitCode: Int?
    public let status: String
    public let privacyClass: String
    public let memoryStatus: String
    public let memoryEventId: String?
    public let auditEventId: String?
    public let memoryError: String?
    public let tags: [String]
    public let sourceModel: String?
    public let bridgeVersion: String?
    public let blockHash: String?
    public let sessionHash: String?
    public let rendererHint: String?

    public init(
        id: String,
        sessionId: String,
        paneId: String,
        kind: String = "command",
        title: String,
        command: String = "",
        outputPreview: String = "",
        outputByteCount: Int = 0,
        startedAt: String = "",
        finishedAt: String = "",
        durationMs: Int? = nil,
        exitCode: Int? = nil,
        status: String = "running",
        privacyClass: String = "sensitive",
        memoryStatus: String = "not_saved",
        memoryEventId: String? = nil,
        auditEventId: String? = nil,
        memoryError: String? = nil,
        tags: [String] = [],
        sourceModel: String? = nil,
        bridgeVersion: String? = nil,
        blockHash: String? = nil,
        sessionHash: String? = nil,
        rendererHint: String? = nil
    ) {
        self.id = id
        self.sessionId = sessionId
        self.paneId = paneId
        self.kind = kind
        self.title = title
        self.command = command
        self.outputPreview = outputPreview
        self.outputByteCount = outputByteCount
        self.startedAt = startedAt
        self.finishedAt = finishedAt
        self.durationMs = durationMs
        self.exitCode = exitCode
        self.status = status
        self.privacyClass = privacyClass
        self.memoryStatus = memoryStatus
        self.memoryEventId = memoryEventId
        self.auditEventId = auditEventId
        self.memoryError = memoryError
        self.tags = tags
        self.sourceModel = sourceModel
        self.bridgeVersion = bridgeVersion
        self.blockHash = blockHash
        self.sessionHash = sessionHash
        self.rendererHint = rendererHint
    }
}

public struct ApprovalRequest: Codable, Identifiable, Sendable {
    public let id: String
    public let title: String
    public let detail: String
    public let requestedBy: String
    public let status: String
    public let createdAt: String

    public init(
        id: String,
        title: String,
        detail: String = "",
        requestedBy: String = "",
        status: String = "pending",
        createdAt: String = ""
    ) {
        self.id = id
        self.title = title
        self.detail = detail
        self.requestedBy = requestedBy
        self.status = status
        self.createdAt = createdAt
    }
}

// MARK: - Workbench Status & Bridge

public struct WorkbenchMemoryStatus: Codable, Sendable {
    public let blockId: String?
    public let status: String
    public let privacyClass: String?
    public let reason: String?
    public let error: String?
    public let memoryEventId: String?
    public let auditEventId: String?
    public let updatedAt: String?
    public let sourceModel: String?
    public let bridgeVersion: String?

    public init(
        blockId: String? = nil,
        status: String,
        privacyClass: String? = nil,
        reason: String? = nil,
        error: String? = nil,
        memoryEventId: String? = nil,
        auditEventId: String? = nil,
        updatedAt: String? = nil,
        sourceModel: String? = nil,
        bridgeVersion: String? = nil
    ) {
        self.blockId = blockId
        self.status = status
        self.privacyClass = privacyClass
        self.reason = reason
        self.error = error
        self.memoryEventId = memoryEventId
        self.auditEventId = auditEventId
        self.updatedAt = updatedAt
        self.sourceModel = sourceModel
        self.bridgeVersion = bridgeVersion
    }
}

public struct WorkbenchAuthorityStatus: Codable, Sendable {
    public let authority: String
    public let fallback: String?
    public let persistence: String?
    public let workbenchDir: String?
    public let workspaceRoot: String?
    public let protocolName: String?
    public let bridgeVersion: String?
    public let supervisor: PtySupervisorStatus?
    public let updatedAt: String?

    enum CodingKeys: String, CodingKey {
        case authority
        case fallback
        case persistence
        case workbenchDir
        case workspaceRoot
        case protocolName = "protocol"
        case bridgeVersion
        case supervisor
        case updatedAt
    }

    public init(
        authority: String = "cockpit-local",
        fallback: String? = nil,
        persistence: String? = nil,
        workbenchDir: String? = nil,
        workspaceRoot: String? = nil,
        protocolName: String? = nil,
        bridgeVersion: String? = nil,
        supervisor: PtySupervisorStatus? = nil,
        updatedAt: String? = nil
    ) {
        self.authority = authority
        self.fallback = fallback
        self.persistence = persistence
        self.workbenchDir = workbenchDir
        self.workspaceRoot = workspaceRoot
        self.protocolName = protocolName
        self.bridgeVersion = bridgeVersion
        self.supervisor = supervisor
        self.updatedAt = updatedAt
    }
}

public struct PtySupervisorStatus: Codable, Sendable {
    public let status: String
    public let runtime: String?
    public let panes: Int?
    public let url: String?
    public let error: String?
    public let updatedAt: String?

    public init(
        status: String = "unknown",
        runtime: String? = nil,
        panes: Int? = nil,
        url: String? = nil,
        error: String? = nil,
        updatedAt: String? = nil
    ) {
        self.status = status
        self.runtime = runtime
        self.panes = panes
        self.url = url
        self.error = error
        self.updatedAt = updatedAt
    }
}

public struct WarpBridgeStatus: Codable, Sendable {
    public let sourceModel: String
    public let bridgeVersion: String
    public let rendererHint: String
    public let bridgeHash: String?
    public let vendorCommit: String?

    public init(
        sourceModel: String = "beagle",
        bridgeVersion: String = "beagle-warp-bridge-v0.2",
        rendererHint: String = "beagle-terminal-v1",
        bridgeHash: String? = nil,
        vendorCommit: String? = nil
    ) {
        self.sourceModel = sourceModel
        self.bridgeVersion = bridgeVersion
        self.rendererHint = rendererHint
        self.bridgeHash = bridgeHash
        self.vendorCommit = vendorCommit
    }
}

public enum NotebookTerminalLayout: String, Codable, Sendable {
    case notebook
    case raw
    case split
}

// MARK: - Live Events & Terminal Stream

public struct WorkbenchLiveEvent: Codable, Identifiable, Sendable {
    public let type: String
    public let sessionId: String?
    public let paneId: String?
    public let blockId: String?
    public let at: String?
    public let data: String?
    public let status: String?
    public let state: String?
    public let command: String?
    public let title: String?
    public let kind: String?
    public let privacyClass: String?
    public let memoryEventId: String?
    public let auditEventId: String?
    public let exitCode: Int?
    public let durationMs: Int?
    public let trigger: String?
    public let reason: String?
    public let error: String?
    public let authority: String?
    public let sourceModel: String?
    public let bridgeVersion: String?
    public let reconnectState: String?
    public let tags: [String]?
    public let blockHash: String?
    public let sessionHash: String?
    public let rendererHint: String?
    public let startedAt: String?
    public let finishedAt: String?
    public let event: String?
    public let agentRole: String?
    public let providerSlot: String?
    public let modelId: String?
    public let arousalMode: String?
    public let registryVersion: String?

    public var id: String {
        [
            type,
            sessionId ?? "session",
            paneId ?? "pane",
            blockId ?? "block",
            at ?? UUID().uuidString
        ].joined(separator: ":")
    }

    enum CodingKeys: String, CodingKey {
        case type
        case sessionId
        case paneId
        case blockId
        case at
        case data
        case status
        case state
        case command
        case title
        case kind
        case privacyClass
        case memoryEventId
        case auditEventId
        case exitCode
        case durationMs
        case trigger
        case reason
        case error
        case authority
        case sourceModel
        case bridgeVersion
        case reconnectState
        case tags
        case blockHash
        case sessionHash
        case rendererHint
        case startedAt
        case finishedAt
        case event
        case agentRole
        case providerSlot
        case modelId
        case arousalMode
        case registryVersion
    }

    public init(
        type: String,
        sessionId: String? = nil,
        paneId: String? = nil,
        blockId: String? = nil,
        at: String? = nil,
        data: String? = nil,
        status: String? = nil,
        state: String? = nil,
        command: String? = nil,
        title: String? = nil,
        kind: String? = nil,
        privacyClass: String? = nil,
        memoryEventId: String? = nil,
        auditEventId: String? = nil,
        exitCode: Int? = nil,
        durationMs: Int? = nil,
        trigger: String? = nil,
        reason: String? = nil,
        error: String? = nil,
        authority: String? = nil,
        sourceModel: String? = nil,
        bridgeVersion: String? = nil,
        reconnectState: String? = nil,
        tags: [String]? = nil,
        blockHash: String? = nil,
        sessionHash: String? = nil,
        rendererHint: String? = nil,
        startedAt: String? = nil,
        finishedAt: String? = nil,
        event: String? = nil,
        agentRole: String? = nil,
        providerSlot: String? = nil,
        modelId: String? = nil,
        arousalMode: String? = nil,
        registryVersion: String? = nil
    ) {
        self.type = type
        self.sessionId = sessionId
        self.paneId = paneId
        self.blockId = blockId
        self.at = at
        self.data = data
        self.status = status
        self.state = state
        self.command = command
        self.title = title
        self.kind = kind
        self.privacyClass = privacyClass
        self.memoryEventId = memoryEventId
        self.auditEventId = auditEventId
        self.exitCode = exitCode
        self.durationMs = durationMs
        self.trigger = trigger
        self.reason = reason
        self.error = error
        self.authority = authority
        self.sourceModel = sourceModel
        self.bridgeVersion = bridgeVersion
        self.reconnectState = reconnectState
        self.tags = tags
        self.blockHash = blockHash
        self.sessionHash = sessionHash
        self.rendererHint = rendererHint
        self.startedAt = startedAt
        self.finishedAt = finishedAt
        self.event = event
        self.agentRole = agentRole
        self.providerSlot = providerSlot
        self.modelId = modelId
        self.arousalMode = arousalMode
        self.registryVersion = registryVersion
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.type = try container.decode(String.self, forKey: .type)
        self.sessionId = try container.decodeIfPresent(String.self, forKey: .sessionId)
        self.paneId = try container.decodeIfPresent(String.self, forKey: .paneId)
        self.blockId = try container.decodeIfPresent(String.self, forKey: .blockId)
        self.at = try container.decodeIfPresent(String.self, forKey: .at)
        self.data = try? container.decode(String.self, forKey: .data)
        self.status = try container.decodeIfPresent(String.self, forKey: .status)
        self.state = try container.decodeIfPresent(String.self, forKey: .state)
        self.command = try container.decodeIfPresent(String.self, forKey: .command)
        self.title = try container.decodeIfPresent(String.self, forKey: .title)
        self.kind = try container.decodeIfPresent(String.self, forKey: .kind)
        self.privacyClass = try container.decodeIfPresent(String.self, forKey: .privacyClass)
        self.memoryEventId = try container.decodeIfPresent(String.self, forKey: .memoryEventId)
        self.auditEventId = try container.decodeIfPresent(String.self, forKey: .auditEventId)
        self.exitCode = try container.decodeIfPresent(Int.self, forKey: .exitCode)
        self.durationMs = try container.decodeIfPresent(Int.self, forKey: .durationMs)
        self.trigger = try container.decodeIfPresent(String.self, forKey: .trigger)
        self.reason = try container.decodeIfPresent(String.self, forKey: .reason)
        self.error = try container.decodeIfPresent(String.self, forKey: .error)
        self.authority = try container.decodeIfPresent(String.self, forKey: .authority)
        self.sourceModel = try container.decodeIfPresent(String.self, forKey: .sourceModel)
        self.bridgeVersion = try container.decodeIfPresent(String.self, forKey: .bridgeVersion)
        self.reconnectState = try container.decodeIfPresent(String.self, forKey: .reconnectState)
        self.tags = try container.decodeIfPresent([String].self, forKey: .tags)
        self.blockHash = try container.decodeIfPresent(String.self, forKey: .blockHash)
        self.sessionHash = try container.decodeIfPresent(String.self, forKey: .sessionHash)
        self.rendererHint = try container.decodeIfPresent(String.self, forKey: .rendererHint)
        self.startedAt = try container.decodeIfPresent(String.self, forKey: .startedAt)
        self.finishedAt = try container.decodeIfPresent(String.self, forKey: .finishedAt)
        self.event = try container.decodeIfPresent(String.self, forKey: .event)
        self.agentRole = try container.decodeIfPresent(String.self, forKey: .agentRole)
        self.providerSlot = try container.decodeIfPresent(String.self, forKey: .providerSlot)
        self.modelId = try container.decodeIfPresent(String.self, forKey: .modelId)
        self.arousalMode = try container.decodeIfPresent(String.self, forKey: .arousalMode)
        self.registryVersion = try container.decodeIfPresent(String.self, forKey: .registryVersion)
    }
}

public struct TerminalBlockLiveState: Identifiable, Sendable, Equatable {
    public let id: String
    public var sessionId: String?
    public var paneId: String?
    public var kind: String
    public var title: String
    public var command: String
    public var outputPreview: String
    public var status: String
    public var privacyClass: String
    public var memoryStatus: String
    public var memoryEventId: String?
    public var auditEventId: String?
    public var exitCode: Int?
    public var durationMs: Int?
    public var updatedAt: String?

    public init(
        id: String,
        sessionId: String? = nil,
        paneId: String? = nil,
        kind: String = "command",
        title: String = "Command",
        command: String = "",
        outputPreview: String = "",
        status: String = "running",
        privacyClass: String = "sensitive",
        memoryStatus: String = "not_saved",
        memoryEventId: String? = nil,
        auditEventId: String? = nil,
        exitCode: Int? = nil,
        durationMs: Int? = nil,
        updatedAt: String? = nil
    ) {
        self.id = id
        self.sessionId = sessionId
        self.paneId = paneId
        self.kind = kind
        self.title = title
        self.command = command
        self.outputPreview = outputPreview
        self.status = status
        self.privacyClass = privacyClass
        self.memoryStatus = memoryStatus
        self.memoryEventId = memoryEventId
        self.auditEventId = auditEventId
        self.exitCode = exitCode
        self.durationMs = durationMs
        self.updatedAt = updatedAt
    }
}

public struct WorkbenchActionDockState: Sendable, Equatable {
    public let canSendInput: Bool
    public let canInterrupt: Bool
    public let canApprove: Bool
    public let canRemember: Bool
    public let activeLaneKind: String?

    public init(
        canSendInput: Bool,
        canInterrupt: Bool,
        canApprove: Bool,
        canRemember: Bool,
        activeLaneKind: String? = nil
    ) {
        self.canSendInput = canSendInput
        self.canInterrupt = canInterrupt
        self.canApprove = canApprove
        self.canRemember = canRemember
        self.activeLaneKind = activeLaneKind
    }
}

public enum TerminalMessage: Sendable {
    case data(String)
    case stderr(String)
    case ready(projectSlug: String)
    case workbenchEvent(WorkbenchLiveEvent)
    case exit(code: Int, detail: String? = nil)
}

public enum WebSocketState: Sendable, Equatable {
    case disconnected
    case connecting
    case connected(source: String)
    case reconnecting(attempt: Int)
    case failed(String)
}

public struct TerminalLine: Identifiable, Sendable {
    public let id: UInt64
    public let text: String
    public let timestamp: Date
    public let isStderr: Bool

    public init(id: UInt64, text: String, timestamp: Date = .now, isStderr: Bool = false) {
        self.id = id
        self.text = text
        self.timestamp = timestamp
        self.isStderr = isStderr
    }
}
