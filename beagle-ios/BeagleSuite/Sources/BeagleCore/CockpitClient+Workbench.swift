//
//  CockpitClient+Workbench.swift
//  BeagleCore
//

import Foundation

extension CockpitClient {

    public func goWorkNow(slug: String, depth: String = "deep") async -> Truthful<GoWorkNowEnvelope> {
        await fetchLegacy(
            GoWorkNowEnvelope.self,
            path: "/api/projects/\(slug)/go-work-now?depth=\(depth)",
            timeout: 12
        )
    }

    public func clusterOpsSummary() async -> Truthful<ClusterOpsSummary> {
        await fetchLegacy(ClusterOpsSummary.self, path: "/api/cluster/ops/summary", timeout: 12)
    }

    public func multimodelTurns(slug: String, limit: Int = 30) async -> Truthful<MultimodelTurnsResponse> {
        await fetchLegacy(
            MultimodelTurnsResponse.self,
            path: "/api/projects/\(slug)/multimodel/turns?limit=\(limit)&includeActive=1",
            timeout: 15
        )
    }

    public func multimodelActiveTurns(slug: String) async -> Truthful<MultimodelActiveTurnsResponse> {
        await fetchLegacy(
            MultimodelActiveTurnsResponse.self,
            path: "/api/projects/\(slug)/multimodel/active-turns",
            timeout: 12
        )
    }

    public func multimodelProviders(slug: String) async -> Truthful<MultimodelProvidersResponse> {
        await fetchLegacy(
            MultimodelProvidersResponse.self,
            path: "/api/projects/\(slug)/multimodel/providers",
            timeout: 12
        )
    }

    public func postAgentTerminalTurn(slug: String, request: AgentTerminalTurnRequest) async -> Truthful<AgentTerminalTurnResponse> {
        await postJSON(
            AgentTerminalTurnResponse.self,
            path: "/api/projects/\(slug)/multimodel/turns/agent-terminal",
            body: request,
            timeout: 20
        )
    }

    public func agentSessions(slug: String) async -> Truthful<AgentSessionsResponse> {
        await fetchLegacy(
            AgentSessionsResponse.self,
            path: "/api/projects/\(slug)/agent/sessions",
            timeout: 12
        )
    }

    public func postAgentSessionInput(
        slug: String,
        kind: String,
        request: AgentSessionInputRequest
    ) async -> Truthful<AgentSessionInputResponse> {
        await postJSON(
            AgentSessionInputResponse.self,
            path: "/api/projects/\(slug)/agent/session/\(kind)/input",
            body: request,
            timeout: 15
        )
    }

    public func workspaceZellijSend(
        slug: String,
        request: WorkspaceZellijSendRequest
    ) async -> Truthful<WorkspaceZellijSendResponse> {
        await postJSON(
            WorkspaceZellijSendResponse.self,
            path: "/api/projects/\(slug)/workspace/zellij/send",
            body: request,
            timeout: 20
        )
    }

    public func workspaceZellijStatus(slug: String) async -> Truthful<WorkspaceZellijStatusResponse> {
        await fetchLegacy(
            WorkspaceZellijStatusResponse.self,
            path: "/api/projects/\(slug)/workspace/zellij/status",
            timeout: 15
        )
    }

    public func workspaceZellijScreen(
        slug: String,
        request: WorkspaceZellijScreenRequest
    ) async -> Truthful<WorkspaceZellijScreenResponse> {
        await postJSON(
            WorkspaceZellijScreenResponse.self,
            path: "/api/projects/\(slug)/workspace/zellij/screen",
            body: request,
            timeout: 25
        )
    }

    public func workbenchPresence(slug: String) async -> Truthful<WorkbenchContextPresenceResponse> {
        await fetchLegacy(
            WorkbenchContextPresenceResponse.self,
            path: "/api/workbench/\(slug)/context/presence",
            timeout: 12
        )
    }

    public func workbenchRecent(slug: String, limit: Int = 20) async -> Truthful<WorkbenchContextRecentResponse> {
        await fetchLegacy(
            WorkbenchContextRecentResponse.self,
            path: "/api/workbench/\(slug)/context/recent?limit=\(limit)",
            timeout: 12
        )
    }

    /// Proxied through Cockpit to Beagle Core monorepo.
    public func exocortexProcess(query: String, substrateSize: Int? = nil) async -> Truthful<ExocortexProcessResponse> {
        let body = ExocortexProcessRequest(query: query, substrateSize: substrateSize)
        return await postJSON(
            ExocortexProcessResponse.self,
            path: "/api/beagle/api/exocortex/process",
            body: body,
            timeout: 120
        )
    }

    public func workbenchGraphRAG(slug: String, query: String, queryMode: String = "local", limit: Int = 8) async -> Truthful<GraphRAGQueryResponse> {
        let body = GraphRAGQueryRequest(query: query, queryMode: queryMode, limit: limit)
        return await postJSON(
            GraphRAGQueryResponse.self,
            path: "/api/workbench/\(slug)/context/graphrag/query",
            body: body,
            timeout: 20
        )
    }

    public func workbenchMessageBoard(slug: String, limit: Int = 24) async -> Truthful<WorkbenchMessageBoardResponse> {
        await fetchLegacy(
            WorkbenchMessageBoardResponse.self,
            path: "/api/workbench/\(slug)/context/messages/board?limit=\(limit)&include_completed=true",
            timeout: 12
        )
    }

    public func workbenchHandoffSend(
        slug: String,
        request: WorkbenchHandoffSendRequest
    ) async -> Truthful<WorkbenchHandoffActionResponse> {
        await postJSON(
            WorkbenchHandoffActionResponse.self,
            path: "/api/workbench/\(slug)/context/messages/send",
            body: request,
            timeout: 20
        )
    }

    public func workbenchHandoffReply(
        slug: String,
        messageId: String,
        request: WorkbenchHandoffReplyRequest
    ) async -> Truthful<WorkbenchHandoffActionResponse> {
        await postJSON(
            WorkbenchHandoffActionResponse.self,
            path: "/api/workbench/\(slug)/context/messages/\(encodedPathComponent(messageId))/reply",
            body: request,
            timeout: 20
        )
    }

    public func workbenchHandoffClaim(
        slug: String,
        messageId: String,
        request: WorkbenchHandoffLifecycleRequest = WorkbenchHandoffLifecycleRequest()
    ) async -> Truthful<WorkbenchHandoffActionResponse> {
        await postJSON(
            WorkbenchHandoffActionResponse.self,
            path: "/api/workbench/\(slug)/context/messages/\(encodedPathComponent(messageId))/claim",
            body: request,
            timeout: 15
        )
    }

    public func workbenchHandoffComplete(
        slug: String,
        messageId: String,
        request: WorkbenchHandoffLifecycleRequest = WorkbenchHandoffLifecycleRequest()
    ) async -> Truthful<WorkbenchHandoffActionResponse> {
        await postJSON(
            WorkbenchHandoffActionResponse.self,
            path: "/api/workbench/\(slug)/context/messages/\(encodedPathComponent(messageId))/complete",
            body: request,
            timeout: 15
        )
    }

    public func workbenchHandoffCompile(
        slug: String,
        messageId: String,
        request: WorkbenchHandoffCompileRequest = WorkbenchHandoffCompileRequest()
    ) async -> Truthful<WorkbenchHandoffCompilePacket> {
        await fetchLegacy(
            WorkbenchHandoffCompilePacket.self,
            path: "/api/workbench/\(slug)/context/messages/\(encodedPathComponent(messageId))/compile?max_items=\(request.maxItems ?? 8)&query_mode=\(request.queryMode ?? "handoff")",
            timeout: 20
        )
    }

    private func encodedPathComponent(_ value: String) -> String {
        value.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? value
    }
}
