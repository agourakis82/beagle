//
//  CockpitWorkbenchAPI.swift
//  BeagleCore
//
//  Workbench-facing Cockpit payloads (go-work-now, cluster ops, multimodel).
//

import Foundation

public struct GoWorkNowEnvelope: Codable, Sendable {
    public let project: GoWorkNowProject?
    public let projectSlug: String?
    public let generatedAt: String?
    public let goWorkNow: GoWorkNowPayload?

    public init(
        project: GoWorkNowProject? = nil,
        projectSlug: String? = nil,
        generatedAt: String? = nil,
        goWorkNow: GoWorkNowPayload? = nil
    ) {
        self.project = project
        self.projectSlug = projectSlug
        self.generatedAt = generatedAt
        self.goWorkNow = goWorkNow
    }
}

public struct GoWorkNowProject: Codable, Sendable {
    public let projectSlug: String?
    public let branch: String?
    public let workspaceId: String?
    public let zellijSession: String?
    public let zellijTabs: [String]?
    public let workspaceRoot: String?
    public let workspacePod: String?
    public let workspacePublicUrl: String?
}

public struct GoWorkNowPayload: Codable, Sendable {
    public let summary: String?
    public let workspace: GoWorkNowWorkspaceEntry?
    public let workspaceState: GoWorkNowWorkspaceState?
    public let routes: GoWorkNowRoutes?
}

public struct GoWorkNowWorkspaceEntry: Codable, Sendable {
    public let pod: String?
    public let tmuxSession: String?
    public let root: String?
    public let publicUrl: String?
}

public struct GoWorkNowWorkspaceState: Codable, Sendable {
    public let status: String?
    public let summary: String?
    public let podName: String?
    public let nodeName: String?
    public let browserUrl: String?
    public let workspaceRoot: String?
    public let ready: Bool?
}

public struct GoWorkNowRoutes: Codable, Sendable {
    public let cockpit: String?
}

public struct ClusterOpsSummary: Codable, Sendable {
    public let status: String?
    public let generatedAt: String?
    public let truthMode: String?

    public init(status: String? = nil, generatedAt: String? = nil, truthMode: String? = nil) {
        self.status = status
        self.generatedAt = generatedAt
        self.truthMode = truthMode
    }
}

public struct MultimodelTurnsResponse: Codable, Sendable {
    public let projectSlug: String?
    public let turns: [MultimodelTurn]?
    public let activeTurns: [MultimodelTurn]?
    public let activeCount: Int?
    public let count: Int?
    public let generatedAt: String?
    public let truthMode: String?

    public init(
        projectSlug: String? = nil,
        turns: [MultimodelTurn]? = nil,
        activeTurns: [MultimodelTurn]? = nil,
        activeCount: Int? = nil,
        count: Int? = nil,
        generatedAt: String? = nil,
        truthMode: String? = nil
    ) {
        self.projectSlug = projectSlug
        self.turns = turns
        self.activeTurns = activeTurns
        self.activeCount = activeCount
        self.count = count
        self.generatedAt = generatedAt
        self.truthMode = truthMode
    }
}

public struct MultimodelTurn: Codable, Sendable, Identifiable {
    public var id: String { turnId ?? UUID().uuidString }
    public let turnId: String?
    public let status: String?
    public let message: String?
    public let prompt: String?
    public let createdAt: String?
    public let completedAt: String?
    public let truthMode: String?
    public let responses: [MultimodelTurnResponse]?
}

public struct MultimodelTurnResponse: Codable, Sendable {
    public let provider: String?
    public let label: String?
    public let status: String?
    public let text: String?
    public let error: String?
}

public struct MultimodelActiveTurnsResponse: Codable, Sendable {
    public let projectSlug: String?
    public let turns: [MultimodelTurn]?
    public let count: Int?
    public let truthMode: String?
}

public struct MultimodelProvidersResponse: Codable, Sendable {
    public let projectSlug: String?
    public let providers: [MultimodelProvider]?
    public let truthMode: String?

    public init(projectSlug: String? = nil, providers: [MultimodelProvider]? = nil, truthMode: String? = nil) {
        self.projectSlug = projectSlug
        self.providers = providers
        self.truthMode = truthMode
    }
}

public struct MultimodelProvider: Codable, Sendable, Identifiable {
    public var id: String { providerId ?? rawId ?? label ?? UUID().uuidString }
    public let rawId: String?
    public let providerId: String?
    public let label: String?
    public let status: String?
    public let transport: String?

    enum CodingKeys: String, CodingKey {
        case rawId = "id"
        case providerId
        case label
        case status
        case transport
    }
}

public struct WorkbenchContextPresenceResponse: Codable, Sendable {
    public let clients: [WorkbenchContextClient]?
    public let truthMode: String?

    public init(clients: [WorkbenchContextClient]? = nil, truthMode: String? = nil) {
        self.clients = clients
        self.truthMode = truthMode
    }
}

public struct WorkbenchContextClient: Codable, Sendable, Identifiable {
    public var id: String { clientId ?? UUID().uuidString }
    public let clientId: String?
    public let status: String?
    public let provider: String?
    public let lastSeen: String?
}

public struct WorkbenchContextRecentResponse: Codable, Sendable {
    public let records: [WorkbenchContextRecord]?
    public let count: Int?
    public let truthMode: String?
}

public struct WorkbenchContextRecord: Codable, Sendable, Identifiable {
    public var id: String { recordId ?? UUID().uuidString }
    public let recordId: String?
    public let role: String?
    public let content: String?
    public let source: String?
}

public struct ExocortexProcessRequest: Codable, Sendable {
    public let query: String
    public let substrateSize: Int?

    public init(query: String, substrateSize: Int? = nil) {
        self.query = query
        self.substrateSize = substrateSize
    }
}

public struct ExocortexProcessResponse: Codable, Sendable {
    public let phi: Double?
    public let substrate: [String]?
    public let awarenessLevel: String?
    public let response: String?
    public let truthMode: String?
    public let declaredReason: String?
    public let tpmSource: String?

    public init(
        phi: Double? = nil,
        substrate: [String]? = nil,
        awarenessLevel: String? = nil,
        response: String? = nil,
        truthMode: String? = nil,
        declaredReason: String? = nil,
        tpmSource: String? = nil
    ) {
        self.phi = phi
        self.substrate = substrate
        self.awarenessLevel = awarenessLevel
        self.response = response
        self.truthMode = truthMode
        self.declaredReason = declaredReason
        self.tpmSource = tpmSource
    }
}

public struct AgentTerminalTurnRequest: Codable, Sendable {
    public let message: String
    public let status: String
    public let kind: String
    public let providerId: String
    public let label: String

    public init(message: String, status: String = "waiting", kind: String = "beagle-native", providerId: String, label: String) {
        self.message = message
        self.status = status
        self.kind = kind
        self.providerId = providerId
        self.label = label
    }
}

public struct AgentTerminalTurnResponse: Codable, Sendable {
    public let status: String?
    public let turn: MultimodelTurn?
    public let persisted: Bool?
    public let truthMode: String?
}

// MARK: - Agent PTY + workspace zellij

public struct AgentSessionsResponse: Codable, Sendable {
    public let projectSlug: String?
    public let sessions: [AgentSessionRecord]?
    public let generatedAt: String?
    public let truthMode: String?
}

public struct AgentSessionRecord: Codable, Sendable {
    public let kind: String?
    public let name: String?
    public let status: String?
    public let readyReplicas: Int?
    public let replicas: Int?
}

public struct AgentSessionInputRequest: Codable, Sendable {
    public let text: String?
    public let data: String?
    public let enter: Bool?
    public let confirmed: Bool

    public init(text: String, enter: Bool = true, confirmed: Bool = true) {
        self.text = text
        self.data = nil
        self.enter = enter
        self.confirmed = confirmed
    }
}

public struct AgentSessionInputResponse: Codable, Sendable {
    public let action: String?
    public let ok: Bool?
    public let truthMode: String?
    public let error: String?
}

public struct WorkspaceZellijSendRequest: Codable, Sendable {
    public let tab: String
    public let text: String
    public let confirmed: Bool
    public let enter: Bool?

    public init(tab: String, text: String, confirmed: Bool = true, enter: Bool = true) {
        self.tab = tab
        self.text = text
        self.confirmed = confirmed
        self.enter = enter
    }
}

public struct WorkspaceZellijSendResponse: Codable, Sendable {
    public let ok: Bool?
    public let action: String?
    public let projectSlug: String?
    public let tab: String?
    public let sessionName: String?
    public let enter: Bool?
    public let transport: String?
    public let target: String?
    public let fallbackFrom: String?
    public let fallbackReason: String?
    public let sshCandidates: [String]?
    public let truthMode: String?
    public let error: String?
}

public struct WorkspaceZellijStatusResponse: Codable, Sendable {
    public let ok: Bool?
    public let projectSlug: String?
    public let sessionName: String?
    public let declaredTabs: [String]?
    public let transport: String?
    public let target: String?
    public let zellijPath: String?
    public let sessionsRaw: String?
    public let sshCandidates: [String]?
    public let probeError: String?
    public let truthMode: String?
    public let error: String?
}

public struct WorkspaceZellijScreenRequest: Codable, Sendable {
    public let tab: String
    public let confirmed: Bool

    public init(tab: String, confirmed: Bool = true) {
        self.tab = tab
        self.confirmed = confirmed
    }
}

public struct WorkspaceZellijScreenResponse: Codable, Sendable {
    public let ok: Bool?
    public let action: String?
    public let projectSlug: String?
    public let tab: String?
    public let sessionName: String?
    public let transport: String?
    public let target: String?
    public let screen: String?
    public let truthMode: String?
    public let error: String?
}

// MARK: - GraphRAG

public struct GraphRAGQueryRequest: Codable, Sendable {
    public let query: String
    public let queryMode: String?
    public let limit: Int?

    enum CodingKeys: String, CodingKey {
        case query
        case queryMode = "query_mode"
        case limit
    }

    public init(query: String, queryMode: String? = "local", limit: Int? = 8) {
        self.query = query
        self.queryMode = queryMode
        self.limit = limit
    }
}

public struct GraphRAGQueryResponse: Codable, Sendable {
    public let resultVersion: String?
    public let projectSlug: String?
    public let query: String?
    public let queryMode: String?
    public let retrievalMode: String?
    public let supportMemoryIds: [String]?
    public let nodeCount: Int?
    public let edgeCount: Int?
    public let nodes: [GraphRAGNode]?
    public let edges: [GraphRAGEdge]?
    public let highlights: [GraphRAGHighlight]?
    public let upstream: GraphRAGUpstream?
    public let note: String?
    public let truthMode: String?

    enum CodingKeys: String, CodingKey {
        case resultVersion = "result_version"
        case projectSlug
        case query
        case queryMode = "query_mode"
        case retrievalMode = "retrieval_mode"
        case supportMemoryIds = "support_memory_ids"
        case nodeCount = "node_count"
        case edgeCount = "edge_count"
        case nodes, edges, highlights, upstream, note, truthMode
    }

    public init(
        resultVersion: String? = nil,
        projectSlug: String? = nil,
        query: String? = nil,
        queryMode: String? = nil,
        retrievalMode: String? = nil,
        supportMemoryIds: [String]? = nil,
        nodeCount: Int? = nil,
        edgeCount: Int? = nil,
        nodes: [GraphRAGNode]? = nil,
        edges: [GraphRAGEdge]? = nil,
        highlights: [GraphRAGHighlight]? = nil,
        upstream: GraphRAGUpstream? = nil,
        note: String? = nil,
        truthMode: String? = nil
    ) {
        self.resultVersion = resultVersion
        self.projectSlug = projectSlug
        self.query = query
        self.queryMode = queryMode
        self.retrievalMode = retrievalMode
        self.supportMemoryIds = supportMemoryIds
        self.nodeCount = nodeCount
        self.edgeCount = edgeCount
        self.nodes = nodes
        self.edges = edges
        self.highlights = highlights
        self.upstream = upstream
        self.note = note
        self.truthMode = truthMode
    }
}

public struct GraphRAGNode: Codable, Sendable, Identifiable {
    public var id: String { nodeId ?? UUID().uuidString }
    public let nodeId: String?
    public let nodeType: String?
    public let displayName: String?
    public let supportMemoryIds: [String]?

    enum CodingKeys: String, CodingKey {
        case nodeId = "node_id"
        case nodeType = "node_type"
        case displayName = "display_name"
        case supportMemoryIds = "support_memory_ids"
    }
}

public struct GraphRAGEdge: Codable, Sendable, Identifiable {
    public var id: String { edgeId ?? UUID().uuidString }
    public let edgeId: String?
    public let fromNodeId: String?
    public let toNodeId: String?
    public let edgeType: String?

    enum CodingKeys: String, CodingKey {
        case edgeId = "edge_id"
        case fromNodeId = "from_node_id"
        case toNodeId = "to_node_id"
        case edgeType = "edge_type"
    }
}

public struct GraphRAGHighlight: Codable, Sendable, Identifiable {
    public var id: String { memoryId ?? UUID().uuidString }
    public let memoryId: String?
    public let snippet: String?
    public let text: String?
    public let source: String?
    public let provider: String?
    public let relevance: Double?
    public let tags: [String]?

    enum CodingKeys: String, CodingKey {
        case memoryId = "memory_id"
        case snippet, text, source, provider, relevance, tags
    }
}

public struct GraphRAGUpstream: Codable, Sendable {
    public let beagleMemory: String?
    public let beagleUrl: String?
    public let error: String?

    enum CodingKeys: String, CodingKey {
        case beagleMemory = "beagle_memory"
        case beagleUrl = "beagle_url"
        case error
    }
}

// MARK: - Handoffs board

public struct WorkbenchMessageBoardResponse: Codable, Sendable {
    public let schema: String?
    public let projectSlug: String?
    public let generatedAt: String?
    public let truthMode: String?
    public let summary: WorkbenchMessageBoardSummary?
    public let nextActions: [WorkbenchHandoffItem]?
    public let columns: WorkbenchMessageBoardColumns?
    public let count: Int?

    enum CodingKeys: String, CodingKey {
        case schema, projectSlug, generatedAt, truthMode, summary, columns, count
        case nextActions = "next_actions"
    }

    public init(
        schema: String? = nil,
        projectSlug: String? = nil,
        generatedAt: String? = nil,
        truthMode: String? = nil,
        summary: WorkbenchMessageBoardSummary? = nil,
        nextActions: [WorkbenchHandoffItem]? = nil,
        columns: WorkbenchMessageBoardColumns? = nil,
        count: Int? = nil
    ) {
        self.schema = schema
        self.projectSlug = projectSlug
        self.generatedAt = generatedAt
        self.truthMode = truthMode
        self.summary = summary
        self.nextActions = nextActions
        self.columns = columns
        self.count = count
    }
}

public struct WorkbenchMessageBoardSummary: Codable, Sendable {
    public let total: Int?
    public let waiting: Int?
    public let active: Int?
    public let done: Int?
    public let canceled: Int?
    public let stale: Int?
    public let urgent: Int?
}

public struct WorkbenchMessageBoardColumns: Codable, Sendable {
    public let waiting: [WorkbenchHandoffItem]?
    public let active: [WorkbenchHandoffItem]?
    public let done: [WorkbenchHandoffItem]?
    public let canceled: [WorkbenchHandoffItem]?
    public let stale: [WorkbenchHandoffItem]?
}

public struct WorkbenchHandoffItem: Codable, Sendable, Identifiable {
    public var id: String { messageId ?? UUID().uuidString }
    public let messageId: String?
    public let fromClient: String?
    public let toClient: String?
    public let subject: String?
    public let priority: String?
    public let status: String?
    public let sentAt: String?
    public let ageMinutes: Int?
    public let stale: Bool?
    public let claimedBy: String?
    public let snippet: String?

    enum CodingKeys: String, CodingKey {
        case messageId = "message_id"
        case fromClient = "from_client"
        case toClient = "to_client"
        case subject, priority, status
        case sentAt = "sent_at"
        case ageMinutes = "age_minutes"
        case stale
        case claimedBy = "claimed_by"
        case snippet
    }
}

public struct WorkbenchHandoffSendRequest: Codable, Sendable {
    public let fromClient: String
    public let toClient: String
    public let subject: String
    public let content: String
    public let priority: String?
    public let requiresResponse: Bool?

    enum CodingKeys: String, CodingKey {
        case fromClient = "from_client"
        case toClient = "to_client"
        case subject, content, priority
        case requiresResponse = "requires_response"
    }

    public init(
        fromClient: String = "beagle-native",
        toClient: String,
        subject: String,
        content: String,
        priority: String? = "normal",
        requiresResponse: Bool? = true
    ) {
        self.fromClient = fromClient
        self.toClient = toClient
        self.subject = subject
        self.content = content
        self.priority = priority
        self.requiresResponse = requiresResponse
    }
}

public struct WorkbenchHandoffReplyRequest: Codable, Sendable {
    public let text: String
    public let clientId: String?

    enum CodingKeys: String, CodingKey {
        case text
        case clientId = "client_id"
    }

    public init(text: String, clientId: String? = "beagle-native") {
        self.text = text
        self.clientId = clientId
    }
}

public struct WorkbenchHandoffLifecycleRequest: Codable, Sendable {
    public let clientId: String?
    public let note: String?

    enum CodingKeys: String, CodingKey {
        case clientId = "client_id"
        case note
    }

    public init(clientId: String? = "beagle-native", note: String? = nil) {
        self.clientId = clientId
        self.note = note
    }
}

public struct WorkbenchHandoffActionResponse: Codable, Sendable {
    public let messageId: String?
    public let status: String?
    public let truthMode: String?
    public let error: String?

    enum CodingKeys: String, CodingKey {
        case messageId = "message_id"
        case status, truthMode, error
    }
}

// MARK: - Handoff compile packet

public struct WorkbenchHandoffCompileRequest: Codable, Sendable {
    public let query: String?
    public let queryMode: String?
    public let maxItems: Int?
    public let taskProfile: String?

    enum CodingKeys: String, CodingKey {
        case query
        case queryMode = "query_mode"
        case maxItems = "max_items"
        case taskProfile = "task_profile"
    }

    public init(
        query: String? = nil,
        queryMode: String? = "handoff",
        maxItems: Int? = 8,
        taskProfile: String? = "handoff"
    ) {
        self.query = query
        self.queryMode = queryMode
        self.maxItems = maxItems
        self.taskProfile = taskProfile
    }
}

public struct GraphRAGGraphBundle: Codable, Sendable {
    public let nodes: [GraphRAGNode]?
    public let edges: [GraphRAGEdge]?
    public let nodeCount: Int?
    public let edgeCount: Int?

    enum CodingKeys: String, CodingKey {
        case nodes, edges
        case nodeCount = "node_count"
        case edgeCount = "edge_count"
    }

    public var asQueryResponse: GraphRAGQueryResponse {
        GraphRAGQueryResponse(
            nodeCount: nodeCount ?? nodes?.count,
            edgeCount: edgeCount ?? edges?.count,
            nodes: nodes,
            edges: edges
        )
    }
}

public struct WorkbenchHandoffCompilePacket: Codable, Sendable {
    public let schema: String?
    public let projectSlug: String?
    public let generatedAt: String?
    public let truthMode: String?
    public let taskProfile: String?
    public let handoff: WorkbenchHandoffPacketMeta?
    public let thread: [WorkbenchHandoffThreadTurn]?
    public let retrieval: WorkbenchHandoffRetrievalMeta?
    public let replyInstruction: String?
    public let compiledContextText: String?
    public let graph: GraphRAGGraphBundle?
    public let highlights: [GraphRAGHighlight]?
    public let upstream: GraphRAGUpstream?

    enum CodingKeys: String, CodingKey {
        case schema, projectSlug, generatedAt, truthMode, handoff, thread, retrieval, graph, highlights, upstream
        case taskProfile = "task_profile"
        case replyInstruction = "reply_instruction"
        case compiledContextText = "compiled_context_text"
    }
}

public struct WorkbenchHandoffPacketMeta: Codable, Sendable {
    public let messageId: String?
    public let fromClient: String?
    public let toClient: String?
    public let subject: String?
    public let priority: String?
    public let status: String?
    public let requiresResponse: Bool?
    public let threadId: String?
    public let replyTool: String?
    public let replyToolStdioProxy: String?
    public let replyEndpoint: String?
    public let sentAt: String?
    public let text: String?
    public let memoryId: String?
    public let claimedBy: String?
    public let completedBy: String?

    enum CodingKeys: String, CodingKey {
        case messageId = "message_id"
        case fromClient = "from_client"
        case toClient = "to_client"
        case subject, priority, status, text
        case requiresResponse = "requires_response"
        case threadId = "thread_id"
        case replyTool = "reply_tool"
        case replyToolStdioProxy = "reply_tool_stdio_proxy"
        case replyEndpoint = "reply_endpoint"
        case sentAt = "sent_at"
        case memoryId = "memory_id"
        case claimedBy = "claimed_by"
        case completedBy = "completed_by"
    }
}

public struct WorkbenchHandoffThreadTurn: Codable, Sendable, Identifiable {
    public var id: String { memoryId ?? UUID().uuidString }
    public let memoryId: String?
    public let source: String?
    public let clientId: String?
    public let role: String?
    public let createdAt: String?
    public let text: String?
    public let messageId: String?

    enum CodingKeys: String, CodingKey {
        case memoryId = "memory_id"
        case source
        case clientId = "client_id"
        case role
        case createdAt = "created_at"
        case text
        case messageId = "message_id"
    }
}

public struct WorkbenchHandoffRetrievalMeta: Codable, Sendable {
    public let query: String?
    public let summary: String?
    public let nodeCount: Int?
    public let edgeCount: Int?
    public let topMemoryIds: [String]?

    enum CodingKeys: String, CodingKey {
        case query, summary
        case nodeCount = "node_count"
        case edgeCount = "edge_count"
        case topMemoryIds = "top_memory_ids"
    }
}
