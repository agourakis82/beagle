//
//  CockpitClient+Workspaces.swift
//  BeagleCore
//
//  Agent sessions, notebook workspaces, panes, blocks, provider config, and routing routes.
//

import Foundation

extension CockpitClient {

    // MARK: - Agent Sessions

    public func agentSessions(slug: String) async -> Truthful<AgentSessionListResponse> {
        let s = Self.seg(slug)
        let mobile = await fetchMobile(AgentSessionListResponse.self, path: "/api/mobile/v1/projects/\(s)/agent-sessions")
        if mobile.value != nil { return mobile }
        return await fetch(AgentSessionListResponse.self, path: "/api/projects/\(s)/agent/sessions")
    }

    public func agentSession(slug: String, kind: String) async -> Truthful<AgentSession> {
        let s = Self.seg(slug)
        let k = Self.seg(kind)
        let mobile = await fetchMobile(AgentSessionDetailResponse.self, path: "/api/mobile/v1/projects/\(s)/agent-sessions/\(k)")
        if let session = mobile.compactMap(\.session) { return session }
        return await fetch(AgentSession.self, path: "/api/projects/\(s)/agent/session/\(k)")
    }

    public func startAgentSession(slug: String, kind: String = "claude-code") async -> Truthful<AgentSession> {
        let s = Self.seg(slug)
        let mobile = await postMobile(AgentSessionActionResponse.self, path: "/api/mobile/v1/projects/\(s)/agent-sessions", body: [
            "kind": kind,
            "confirmed": true
        ], timeout: 60)
        if let session = mobile.compactMap(\.session) { return session }
        return await post(AgentSession.self, path: "/api/projects/\(s)/agent/session/start", body: ["kind": kind], timeout: 60)
    }

    public func pauseAgentSession(slug: String, kind: String) async -> Truthful<AgentSession> {
        let s = Self.seg(slug)
        let k = Self.seg(kind)
        let mobile = await postMobile(AgentSessionActionResponse.self, path: "/api/mobile/v1/projects/\(s)/agent-sessions/\(k)/pause", body: [
            "confirmed": true
        ])
        if let session = mobile.compactMap(\.session) { return session }
        return await post(AgentSession.self, path: "/api/projects/\(s)/agent/session/\(k)/pause")
    }

    public func resumeAgentSession(slug: String, kind: String) async -> Truthful<AgentSession> {
        let s = Self.seg(slug)
        let k = Self.seg(kind)
        let mobile = await postMobile(AgentSessionActionResponse.self, path: "/api/mobile/v1/projects/\(s)/agent-sessions/\(k)/resume", body: [
            "confirmed": true
        ])
        if let session = mobile.compactMap(\.session) { return session }
        return await post(AgentSession.self, path: "/api/projects/\(s)/agent/session/\(k)/resume")
    }

    public func stopAgentSession(slug: String, kind: String) async -> Truthful<AgentSession> {
        let s = Self.seg(slug)
        let k = Self.seg(kind)
        let mobile = await deleteMobile(AgentSessionActionResponse.self, path: "/api/mobile/v1/projects/\(s)/agent-sessions/\(k)", body: [
            "confirmed": true
        ])
        if let session = mobile.compactMap(\.session) { return session }
        return await post(AgentSession.self, path: "/api/projects/\(s)/agent/session/\(k)/stop")
    }

    // MARK: - Workspace / Notebook Terminal

    public func workspaces() async -> Truthful<WorkspaceListResponse> {
        await fetch(WorkspaceListResponse.self, path: "/api/workspaces")
    }

    public func workspaceSessions(slug: String) async -> Truthful<WorkspaceSessionListResponse> {
        await fetch(
            WorkspaceSessionListResponse.self,
            path: "/api/workspaces/\(Self.seg(slug))/sessions"
        )
    }

    public func createWorkspaceSession(
        slug: String,
        title: String = "Sounio Workbench",
        layout: NotebookTerminalLayout = .notebook
    ) async -> Truthful<WorkspaceSessionResponse> {
        await post(
            WorkspaceSessionResponse.self,
            path: "/api/workspaces/\(Self.seg(slug))/sessions",
            body: [
                "title": title,
                "layout": layout.rawValue
            ]
        )
    }

    public func workspaceSession(slug: String, sessionId: String) async -> Truthful<WorkspaceSessionResponse> {
        await fetch(
            WorkspaceSessionResponse.self,
            path: "/api/workspaces/\(Self.seg(slug))/sessions/\(Self.seg(sessionId))"
        )
    }

    public func agentRegistry(slug: String) async -> Truthful<AgentRegistryResponse> {
        await fetch(
            AgentRegistryResponse.self,
            path: "/api/workspaces/\(Self.seg(slug))/agents/registry"
        )
    }

    public func agentRoute(
        slug: String,
        task: String,
        privacyClass: String = "sensitive"
    ) async -> Truthful<AgentRouteResponse> {
        await post(
            AgentRouteResponse.self,
            path: "/api/workspaces/\(Self.seg(slug))/agents/route",
            body: [
                "task": task,
                "privacy_class": privacyClass
            ]
        )
    }

    public func startAgentRole(
        slug: String,
        roleOrKind: String,
        sessionId: String? = nil,
        task: String = "",
        providerSlot: String? = nil
    ) async -> Truthful<AgentStartResponse> {
        var body: [String: any Sendable] = [
            "task": task
        ]
        if let sessionId, !sessionId.isEmpty {
            body["session_id"] = sessionId
        }
        if let providerSlot, !providerSlot.isEmpty {
            body["provider_slot"] = providerSlot
        }
        return await post(
            AgentStartResponse.self,
            path: "/api/workspaces/\(Self.seg(slug))/agents/\(Self.seg(roleOrKind))/start",
            body: body
        )
    }

    /// Persist a lane's provider credentials server-side so the readiness probe
    /// flips needs_setup -> ready and the agent launch can inject them. The API
    /// key is sent once over the zero-trust Tailnet path and is NEVER returned;
    /// the masked acknowledgement only reports `apiKeyConfigured`.
    public func setProviderConfig(
        slug: String,
        role: String,
        slot: String? = nil,
        baseURL: String,
        apiKey: String,
        model: String? = nil
    ) async -> Truthful<AgentProviderConfigResponse> {
        var body: [String: any Sendable] = [
            "base_url": baseURL,
            "api_key": apiKey
        ]
        if let slot, !slot.isEmpty {
            body["slot"] = slot
        }
        if let model, !model.isEmpty {
            body["model"] = model
        }
        return await post(
            AgentProviderConfigResponse.self,
            path: "/api/workspaces/\(Self.seg(slug))/agents/\(Self.seg(role))/provider-config",
            body: body,
            timeout: 30
        )
    }

    public func createWorkspacePane(
        slug: String,
        sessionId: String,
        kind: String = "human",
        title: String = "Shell"
    ) async -> Truthful<WorkspacePaneResponse> {
        await post(
            WorkspacePaneResponse.self,
            path: "/api/workspaces/\(Self.seg(slug))/sessions/\(Self.seg(sessionId))/panes",
            body: [
                "kind": kind,
                "title": title
            ]
        )
    }

    public func workspaceBlocks(slug: String, sessionId: String) async -> Truthful<WorkspaceBlocksResponse> {
        await fetch(
            WorkspaceBlocksResponse.self,
            path: "/api/workspaces/\(Self.seg(slug))/sessions/\(Self.seg(sessionId))/blocks"
        )
    }

    public func rememberWorkspaceBlock(
        slug: String,
        sessionId: String,
        blockId: String,
        summary: String = ""
    ) async -> Truthful<WorkspaceRememberBlockResponse> {
        var body: [String: any Sendable] = ["confirmed": true]
        if !summary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            body["summary"] = summary
        }
        return await post(
            WorkspaceRememberBlockResponse.self,
            path: "/api/workspaces/\(Self.seg(slug))/sessions/\(Self.seg(sessionId))/blocks/\(Self.seg(blockId))/remember",
            body: body,
            timeout: 30
        )
    }
}
