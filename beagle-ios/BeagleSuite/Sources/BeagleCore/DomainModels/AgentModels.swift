//
//  AgentModels.swift
//  BeagleCore
//
//  Agent sessions, pods, activity, delegation, provider registry,
//  routing decisions, run state, and live agent console snapshots.
//

import Foundation

// MARK: - Agent Sessions

public struct AgentPod: Codable, Sendable {
    public let name: String?
    public let phase: String?
    public let ready: Bool?
}

public struct AgentSessionActivity: Codable, Sendable {
    public let summary: String?
    public let source: String?
    public let updatedAt: String?
    public let author: String?
    public let excerpt: String?

    enum CodingKeys: String, CodingKey {
        case summary
        case source
        case updatedAt
        case updatedAtSnake = "updated_at"
        case author
        case excerpt
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        summary = try container.decodeIfPresent(String.self, forKey: .summary)
        source = try container.decodeIfPresent(String.self, forKey: .source)
        updatedAt =
            try container.decodeIfPresent(String.self, forKey: .updatedAt)
            ?? container.decodeIfPresent(String.self, forKey: .updatedAtSnake)
        author = try container.decodeIfPresent(String.self, forKey: .author)
        excerpt = try container.decodeIfPresent(String.self, forKey: .excerpt)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(summary, forKey: .summary)
        try container.encodeIfPresent(source, forKey: .source)
        try container.encodeIfPresent(updatedAt, forKey: .updatedAt)
        try container.encodeIfPresent(author, forKey: .author)
        try container.encodeIfPresent(excerpt, forKey: .excerpt)
    }
}

public struct AgentSession: Codable, Sendable {
    public let kind: String?
    public let name: String?
    public let replicas: Int?
    public let readyReplicas: Int?
    public let createdAt: String?
    public let pods: [AgentPod]?
    public let status: String?
    public let truthMode: String?
    public let action: String?
    public let activity: AgentSessionActivity?

    public init(
        kind: String?,
        name: String?,
        replicas: Int?,
        readyReplicas: Int?,
        createdAt: String?,
        pods: [AgentPod]?,
        status: String?,
        truthMode: String?,
        action: String?,
        activity: AgentSessionActivity? = nil
    ) {
        self.kind = kind
        self.name = name
        self.replicas = replicas
        self.readyReplicas = readyReplicas
        self.createdAt = createdAt
        self.pods = pods
        self.status = status
        self.truthMode = truthMode
        self.action = action
        self.activity = activity
    }

    public var isRunning: Bool { (readyReplicas ?? 0) > 0 }
    public var podName: String? { pods?.first?.name }
    public var phase: AgentSessionPhase {
        if isRunning { return .running }
        if replicas == 0 { return .paused }
        return .pending
    }
}

public extension AgentSession {
    var presentedMindLabel: String {
        if let kind, !kind.isEmpty {
            return kind
                .replacingOccurrences(of: "-", with: " ")
                .capitalized
        }
        if let name, !name.isEmpty {
            return name
        }
        return "Agent"
    }

    var presentedActivityLine: String {
        if let summary = activity?.summary?.nonBlankOrNil {
            return summary
        }
        if let excerpt = activity?.excerpt?.nonBlankOrNil {
            return excerpt
        }
        if let action, !action.isEmpty {
            return action
        }
        switch phase {
        case .running:
            return "\(presentedMindLabel) is live in the habitat."
        case .paused:
            return "\(presentedMindLabel) is paused but recoverable."
        case .pending:
            return "\(presentedMindLabel) is waiting for readiness."
        }
    }
}

public enum AgentSessionPhase: String, Sendable {
    case pending
    case running
    case paused
}

public struct AgentSessionListResponse: Codable, Sendable {
    public let projectSlug: String?
    public let sessions: [AgentSession]?
    public let generatedAt: String?
    public let truthMode: String?
}

public struct AgentSessionDetailResponse: Codable, Sendable {
    public let projectSlug: String?
    public let session: AgentSession?
    public let generatedAt: String?
}

public struct AgentSessionActionResponse: Codable, Sendable {
    public let projectSlug: String?
    public let action: String?
    public let session: AgentSession?
    public let generatedAt: String?
}

// MARK: - Delegation

public struct DelegationResponse: Decodable, Sendable {
    public let agentKind: String?
    public let sessionId: String?
    public let podName: String?
    public let resultingState: String?
    public let projectFamily: String?
    public let publicationScope: String?

    enum CodingKeys: String, CodingKey {
        case agentKind
        case sessionId
        case podName
        case resultingState
        case projectFamily
        case publicationScope
        case agentKindSnake = "agent_kind"
        case sessionIdSnake = "session_id"
        case podNameSnake = "pod_name"
        case resultingStateSnake = "resulting_state"
        case projectFamilySnake = "project_family"
        case publicationScopeSnake = "publication_scope"
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        agentKind =
            try container.decodeIfPresent(String.self, forKey: .agentKind)
            ?? container.decodeIfPresent(String.self, forKey: .agentKindSnake)
        sessionId =
            try container.decodeIfPresent(String.self, forKey: .sessionId)
            ?? container.decodeIfPresent(String.self, forKey: .sessionIdSnake)
        podName =
            try container.decodeIfPresent(String.self, forKey: .podName)
            ?? container.decodeIfPresent(String.self, forKey: .podNameSnake)
        resultingState =
            try container.decodeIfPresent(String.self, forKey: .resultingState)
            ?? container.decodeIfPresent(String.self, forKey: .resultingStateSnake)
        projectFamily =
            try container.decodeIfPresent(String.self, forKey: .projectFamily)
            ?? container.decodeIfPresent(String.self, forKey: .projectFamilySnake)
        publicationScope =
            try container.decodeIfPresent(String.self, forKey: .publicationScope)
            ?? container.decodeIfPresent(String.self, forKey: .publicationScopeSnake)
    }
}

// MARK: - Agent Registry, Providers & Routing

public struct AgentProviderSlot: Codable, Identifiable, Sendable, Equatable {
    public let id: String
    public let title: String
    public let modelId: String
    public let baseUrl: String?
    public let command: String?
    public let runtime: String
    public let costTier: String
    public let latencyTier: String
    public let privacyTier: String
    public let licenseNote: String?
    public let enabled: Bool

    public init(
        id: String,
        title: String,
        modelId: String,
        baseUrl: String? = nil,
        command: String? = nil,
        runtime: String = "",
        costTier: String = "",
        latencyTier: String = "",
        privacyTier: String = "",
        licenseNote: String? = nil,
        enabled: Bool = true
    ) {
        self.id = id
        self.title = title
        self.modelId = modelId
        self.baseUrl = baseUrl
        self.command = command
        self.runtime = runtime
        self.costTier = costTier
        self.latencyTier = latencyTier
        self.privacyTier = privacyTier
        self.licenseNote = licenseNote
        self.enabled = enabled
    }
}

/// Masked acknowledgement returned by the cockpit after writing a lane's
/// provider configuration server-side. The raw API key is NEVER echoed; only
/// `apiKeyConfigured` reflects whether a secret is now stored on the workspace.
public struct AgentProviderConfigResponse: Codable, Sendable, Equatable {
    public let projectSlug: String?
    public let role: String?
    public let slot: String?
    public let status: String?
    public let readiness: AgentReadinessState?
    public let providerConfig: Masked?

    /// The masked view of the stored slot — safe to render in the UI.
    public struct Masked: Codable, Sendable, Equatable {
        public let slot: String?
        public let baseUrl: String?
        public let model: String?
        public let apiKeyConfigured: Bool?
        public let updatedAt: String?

        public init(
            slot: String? = nil,
            baseUrl: String? = nil,
            model: String? = nil,
            apiKeyConfigured: Bool? = nil,
            updatedAt: String? = nil
        ) {
            self.slot = slot
            self.baseUrl = baseUrl
            self.model = model
            self.apiKeyConfigured = apiKeyConfigured
            self.updatedAt = updatedAt
        }
    }

    public init(
        projectSlug: String? = nil,
        role: String? = nil,
        slot: String? = nil,
        status: String? = nil,
        readiness: AgentReadinessState? = nil,
        providerConfig: Masked? = nil
    ) {
        self.projectSlug = projectSlug
        self.role = role
        self.slot = slot
        self.status = status
        self.readiness = readiness
        self.providerConfig = providerConfig
    }
}

public struct AgentReadinessState: Codable, Sendable, Equatable {
    public let status: String
    public let reason: String?
    public let command: String?
    public let env: String?
    public let model: String?

    public init(
        status: String = "unknown",
        reason: String? = nil,
        command: String? = nil,
        env: String? = nil,
        model: String? = nil
    ) {
        self.status = status
        self.reason = reason
        self.command = command
        self.env = env
        self.model = model
    }
}

public struct AgentRole: Codable, Identifiable, Sendable, Equatable {
    public let role: String
    public let kind: String
    public let title: String
    public let subtitle: String?
    public let roleSummary: String?
    public let visible: Bool
    public let arousalRole: String?
    public let icon: String?
    public let accent: String?
    public let launchCommand: String?
    public let memoryPolicy: String?
    public let riskLevel: String?
    public let providerSlots: [AgentProviderSlot]
    public let readiness: AgentReadinessState?
    public let enabled: Bool

    public var id: String { role }

    public init(
        role: String,
        kind: String,
        title: String,
        subtitle: String? = nil,
        roleSummary: String? = nil,
        visible: Bool = true,
        arousalRole: String? = nil,
        icon: String? = nil,
        accent: String? = nil,
        launchCommand: String? = nil,
        memoryPolicy: String? = nil,
        riskLevel: String? = nil,
        providerSlots: [AgentProviderSlot] = [],
        readiness: AgentReadinessState? = nil,
        enabled: Bool = true
    ) {
        self.role = role
        self.kind = kind
        self.title = title
        self.subtitle = subtitle
        self.roleSummary = roleSummary
        self.visible = visible
        self.arousalRole = arousalRole
        self.icon = icon
        self.accent = accent
        self.launchCommand = launchCommand
        self.memoryPolicy = memoryPolicy
        self.riskLevel = riskLevel
        self.providerSlots = providerSlots
        self.readiness = readiness
        self.enabled = enabled
    }
}

public struct AgentRegistryResponse: Codable, Sendable {
    public let projectSlug: String
    public let registryVersion: String?
    public let arousalModel: String?
    public let authority: WorkbenchAuthorityStatus?
    public let roles: [AgentRole]
    public let visibleRoles: [String]
    public let scoutRoles: [String]
    public let updatedAt: String?
    public let error: String?

    public init(
        projectSlug: String,
        registryVersion: String? = nil,
        arousalModel: String? = nil,
        authority: WorkbenchAuthorityStatus? = nil,
        roles: [AgentRole] = [],
        visibleRoles: [String] = [],
        scoutRoles: [String] = [],
        updatedAt: String? = nil,
        error: String? = nil
    ) {
        self.projectSlug = projectSlug
        self.registryVersion = registryVersion
        self.arousalModel = arousalModel
        self.authority = authority
        self.roles = roles
        self.visibleRoles = visibleRoles
        self.scoutRoles = scoutRoles
        self.updatedAt = updatedAt
        self.error = error
    }
}

public struct AgentRouteSlot: Codable, Sendable, Equatable {
    public let role: String
    public let kind: String
    public let title: String
    public let providerSlots: [AgentProviderSlot]

    public init(role: String, kind: String, title: String, providerSlots: [AgentProviderSlot] = []) {
        self.role = role
        self.kind = kind
        self.title = title
        self.providerSlots = providerSlots
    }
}

public struct AgentRouteDecision: Codable, Identifiable, Sendable, Equatable {
    public let id: String
    public let createdAt: String?
    public let projectSlug: String?
    public let task: String?
    public let chosenRole: String
    public let chosenSlot: AgentRouteSlot
    public let fallbackSlots: [AgentRouteSlot]
    public let reason: String
    public let arousalMode: String
    public let privacyConstraints: [String]
    public let expectedArtifacts: [String]
    public let registryVersion: String?

    public init(
        id: String = UUID().uuidString,
        createdAt: String? = nil,
        projectSlug: String? = nil,
        task: String? = nil,
        chosenRole: String,
        chosenSlot: AgentRouteSlot,
        fallbackSlots: [AgentRouteSlot] = [],
        reason: String = "",
        arousalMode: String = "phasic_focus",
        privacyConstraints: [String] = [],
        expectedArtifacts: [String] = [],
        registryVersion: String? = nil
    ) {
        self.id = id
        self.createdAt = createdAt
        self.projectSlug = projectSlug
        self.task = task
        self.chosenRole = chosenRole
        self.chosenSlot = chosenSlot
        self.fallbackSlots = fallbackSlots
        self.reason = reason
        self.arousalMode = arousalMode
        self.privacyConstraints = privacyConstraints
        self.expectedArtifacts = expectedArtifacts
        self.registryVersion = registryVersion
    }
}

public struct AgentRouteResponse: Codable, Sendable {
    public let projectSlug: String
    public let decision: AgentRouteDecision
    public let authority: WorkbenchAuthorityStatus?

    public init(projectSlug: String, decision: AgentRouteDecision, authority: WorkbenchAuthorityStatus? = nil) {
        self.projectSlug = projectSlug
        self.decision = decision
        self.authority = authority
    }
}

public struct AgentStartResponse: Codable, Sendable {
    public let projectSlug: String
    public let pane: TerminalPane
    public let session: WorkspaceSession
    public let decision: AgentRouteDecision?
    public let readiness: AgentReadinessState?
    public let startCommand: String?
    public let providerSlot: AgentProviderSlot?

    public init(
        projectSlug: String,
        pane: TerminalPane,
        session: WorkspaceSession,
        decision: AgentRouteDecision? = nil,
        readiness: AgentReadinessState? = nil,
        startCommand: String? = nil,
        providerSlot: AgentProviderSlot? = nil
    ) {
        self.projectSlug = projectSlug
        self.pane = pane
        self.session = session
        self.decision = decision
        self.readiness = readiness
        self.startCommand = startCommand
        self.providerSlot = providerSlot
    }
}

// MARK: - Agent Run & Console State

public struct AgentRunState: Codable, Sendable {
    public let kind: String
    public let state: String
    public let summary: String
    public let branch: String
    public let commit: String
    public let changedFiles: [String]
    public let role: String?
    public let providerSlot: String?
    public let modelId: String?
    public let arousalMode: String?

    public init(
        kind: String,
        state: String = "idle",
        summary: String = "",
        branch: String = "",
        commit: String = "",
        changedFiles: [String] = [],
        role: String? = nil,
        providerSlot: String? = nil,
        modelId: String? = nil,
        arousalMode: String? = nil
    ) {
        self.kind = kind
        self.state = state
        self.summary = summary
        self.branch = branch
        self.commit = commit
        self.changedFiles = changedFiles
        self.role = role
        self.providerSlot = providerSlot
        self.modelId = modelId
        self.arousalMode = arousalMode
    }
}

public struct AgentLaneState: Identifiable, Sendable, Equatable {
    public let id: String
    public let title: String
    public let kind: String
    public let paneId: String?
    public let status: String
    public let detail: String
    public let lastBlockTitle: String?
    public let lastBlockStatus: String?
    public let memoryStatus: String?
    public let pendingApproval: Bool
    public let reconnectState: String?
    public let isActive: Bool
    public let role: String?
    public let subtitle: String?
    public let providerLabel: String?
    public let arousalMode: String?
    public let isScout: Bool
    public let readinessReason: String?

    public init(
        id: String,
        title: String,
        kind: String,
        paneId: String? = nil,
        status: String = "idle",
        detail: String = "",
        lastBlockTitle: String? = nil,
        lastBlockStatus: String? = nil,
        memoryStatus: String? = nil,
        pendingApproval: Bool = false,
        reconnectState: String? = nil,
        isActive: Bool = false,
        role: String? = nil,
        subtitle: String? = nil,
        providerLabel: String? = nil,
        arousalMode: String? = nil,
        isScout: Bool = false,
        readinessReason: String? = nil
    ) {
        self.id = id
        self.title = title
        self.kind = kind
        self.paneId = paneId
        self.status = status
        self.detail = detail
        self.lastBlockTitle = lastBlockTitle
        self.lastBlockStatus = lastBlockStatus
        self.memoryStatus = memoryStatus
        self.pendingApproval = pendingApproval
        self.reconnectState = reconnectState
        self.isActive = isActive
        self.role = role
        self.subtitle = subtitle
        self.providerLabel = providerLabel
        self.arousalMode = arousalMode
        self.isScout = isScout
        self.readinessReason = readinessReason
    }
}

public struct AgentConsoleSnapshot: Sendable, Equatable {
    public let projectSlug: String
    public let sessionId: String?
    public let lanes: [AgentLaneState]
    public let activeLaneKind: String?
    public let authority: String?
    public let updatedAt: String?

    public init(
        projectSlug: String,
        sessionId: String? = nil,
        lanes: [AgentLaneState] = [],
        activeLaneKind: String? = nil,
        authority: String? = nil,
        updatedAt: String? = nil
    ) {
        self.projectSlug = projectSlug
        self.sessionId = sessionId
        self.lanes = lanes
        self.activeLaneKind = activeLaneKind
        self.authority = authority
        self.updatedAt = updatedAt
    }
}
