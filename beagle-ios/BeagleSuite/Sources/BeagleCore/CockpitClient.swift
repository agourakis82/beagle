//
//  CockpitClient.swift
//  BeagleCore
//
//  Truth-aware HTTP client for the cockpit API.
//  Uses URLSession with Swift 6 async/await.
//  Returns Truthful<T> wrappers preserving epistemic metadata.
//
//  Resolves multiple URLs in preference order
//  (public HTTPS edge → tailnet → internal VIP → cluster service DNS)
//  so the same app works on the public mobile gateway first, while still
//  preserving the old private fallbacks during transition.
//

import Foundation

public actor CockpitClient {

    public static let shared = CockpitClient()

    private func derivedProjectFamily(slug: String, override: ProjectFamily?) -> ProjectFamily {
        override ?? .fromProjectSlug(slug)
    }

    private func derivedPublicationScope(
        slug: String,
        projectFamily: ProjectFamily?,
        override: PublicationScope?
    ) -> PublicationScope {
        if let override { return override }
        return .forProjectFamily(derivedProjectFamily(slug: slug, override: projectFamily))
    }

    private let session: URLSession
    private let decoder: JSONDecoder

    /// URL resolution order — tried in sequence until one responds.
    /// Override via `configure(baseURLs:)` from the app.
    private var baseURLs: [URL] = [
        URL(string: "https://beagle.chiuratto.ai")!,                     // Public HTTPS mobile gateway
        URL(string: "http://sounio-cockpit.tail21cbc4.ts.net")!,         // Tailnet FQDN
        URL(string: "http://100.107.208.198")!,                          // Tailnet direct IP (DNS fallback)
        URL(string: "http://project-cockpit.beagle.svc.cluster.local")!  // In-cluster (pod network only)
    ]

    private init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 12  // Leave room for edge or tailnet fallback
        config.timeoutIntervalForResource = 30
        config.waitsForConnectivity = true
        config.httpAdditionalHeaders = [
            "Accept": "application/json",
            "User-Agent": "BeagleCockpit/1.0 (iOS/macOS native)"
        ]
        self.session = URLSession(configuration: config)
        self.decoder = JSONDecoder()
    }

    /// Configure the URL resolution order.
    public func configure(baseURLs: [URL]) {
        self.baseURLs = baseURLs
    }

    /// Read-only base URLs (resolution order) for the synthesis streaming client.
    public var mobileBaseURLs: [URL] { baseURLs }

    // MARK: - Core fetch

    /// Fetch a typed response with truth-aware error handling.
    /// Tries each base URL in order; returns the first success.
    public func fetch<T: Decodable & Sendable>(
        _ type: T.Type,
        path: String,
        timeout: TimeInterval = 12
    ) async -> Truthful<T> {
        var lastError: String = "no base URL reachable"

        for base in baseURLs {
            guard let url = URL(string: path, relativeTo: base) else { continue }
            do {
                var request = URLRequest(url: url)
                request.setValue(BeagleClient.cockpitMobileToken, forHTTPHeaderField: "x-cockpit-token")
                request.timeoutInterval = timeout
                let (data, response) = try await session.data(for: request)

                guard let httpResponse = response as? HTTPURLResponse else {
                    lastError = "invalid response"
                    continue
                }

                guard (200..<300).contains(httpResponse.statusCode) else {
                    lastError = formatError(
                        statusCode: httpResponse.statusCode,
                        data: data,
                        fallback: "HTTP \(httpResponse.statusCode)"
                    )
                    continue
                }

                let decoded = try decoder.decode(T.self, from: data)
                return .observed(decoded, source: url.host)
            } catch {
                lastError = error.localizedDescription
                continue
            }
        }

        return .staleError(lastError)
    }

    public func fetchMobile<T: Decodable & Sendable>(
        _ type: T.Type,
        path: String,
        timeout: TimeInterval = 12
    ) async -> Truthful<T> {
        var lastError: String = "no base URL reachable"

        for base in baseURLs {
            guard let url = URL(string: path, relativeTo: base) else { continue }
            do {
                var request = URLRequest(url: url)
                request.setValue(BeagleClient.cockpitMobileToken, forHTTPHeaderField: "x-cockpit-token")
                request.timeoutInterval = timeout
                let (data, response) = try await session.data(for: request)

                guard let httpResponse = response as? HTTPURLResponse else {
                    lastError = "invalid response"
                    continue
                }

                guard (200..<300).contains(httpResponse.statusCode) else {
                    lastError = formatError(
                        statusCode: httpResponse.statusCode,
                        data: data,
                        fallback: "HTTP \(httpResponse.statusCode)"
                    )
                    continue
                }

                let envelope = try decoder.decode(MobileEnvelope<T>.self, from: data)
                guard envelope.ok != false else {
                    lastError = envelope.error?.message ?? "mobile gateway returned ok=false"
                    continue
                }
                guard let payload = envelope.data else {
                    lastError = envelope.error?.message ?? "mobile gateway returned no data"
                    continue
                }

                let mode = TruthMode(rawValue: envelope.meta?.truthMode ?? "") ?? .observed
                return Truthful(
                    value: payload,
                    mode: mode,
                    observedAt: .now,
                    source: url.host,
                    error: nil
                )
            } catch {
                lastError = error.localizedDescription
                continue
            }
        }

        return .staleError(lastError)
    }

    // MARK: - High-level API

    public func catalog() async -> Truthful<ExecutiveCatalog> {
        let mobile = await fetchMobile(ExecutiveCatalog.self, path: "/api/mobile/v1/catalog")
        if mobile.value != nil { return mobile }
        return await fetch(ExecutiveCatalog.self, path: "/api/catalog/executive")
    }

    public func mobileSummary() async -> Truthful<MobileHomeSummary> {
        await fetchMobile(MobileHomeSummary.self, path: "/api/mobile/v1/summary")
    }

    public func projectOverview(slug: String, depth: String = "fast") async -> Truthful<MobileProjectOverview> {
        await fetchMobile(
            MobileProjectOverview.self,
            path: "/api/mobile/v1/projects/\(slug)/overview?depth=\(depth)"
        )
    }

    public func posturePolicy() async -> Truthful<PosturePolicy> {
        await fetch(PosturePolicy.self, path: "/api/catalog/project-posture-policy")
    }

    public func missionControl(slug: String) async -> Truthful<MissionControl> {
        let overview = await fetchMobile(MobileProjectOverview.self, path: "/api/mobile/v1/projects/\(slug)/overview")
        if let payload = overview.value?.missionControl {
            return Truthful(
                value: payload,
                mode: overview.mode,
                observedAt: overview.observedAt,
                source: overview.source,
                error: overview.error
            )
        }
        return await fetch(MissionControl.self, path: "/api/projects/\(slug)/mission-control")
    }

    public func clusterLaneTruth(slug: String) async -> Truthful<ClusterLaneTruth> {
        let overview = await fetchMobile(MobileProjectOverview.self, path: "/api/mobile/v1/projects/\(slug)/overview")
        if let payload = overview.value?.clusterLaneTruth {
            return Truthful(
                value: payload,
                mode: overview.mode,
                observedAt: overview.observedAt,
                source: overview.source,
                error: overview.error
            )
        }
        return await fetch(ClusterLaneTruth.self, path: "/api/projects/\(slug)/cluster/lane-truth")
    }

    public func researchOperations(slug: String) async -> Truthful<ResearchOperations> {
        let overview = await fetchMobile(MobileProjectOverview.self, path: "/api/mobile/v1/projects/\(slug)/overview")
        if let payload = overview.value?.researchOperations {
            return Truthful(
                value: payload,
                mode: overview.mode,
                observedAt: overview.observedAt,
                source: overview.source,
                error: overview.error
            )
        }
        return await fetch(ResearchOperations.self, path: "/api/projects/\(slug)/research/operations")
    }

    public func inferenceRuntime(slug: String) async -> Truthful<InferenceRuntime> {
        let overview = await fetchMobile(MobileProjectOverview.self, path: "/api/mobile/v1/projects/\(slug)/overview")
        if let payload = overview.value?.inferenceRuntime {
            return Truthful(
                value: payload,
                mode: overview.mode,
                observedAt: overview.observedAt,
                source: overview.source,
                error: overview.error
            )
        }
        let wrapped = await fetch(InferenceRuntimeResponse.self, path: "/api/projects/\(slug)/inference/runtime")
        // Unwrap nested runtime object
        guard let runtime = wrapped.value?.runtime else {
            return .staleError(wrapped.error ?? "no runtime payload", source: wrapped.source)
        }
        return Truthful(
            value: runtime,
            mode: wrapped.mode,
            observedAt: wrapped.observedAt,
            source: wrapped.source,
            error: wrapped.error
        )
    }

    public func viewerRuntime(slug: String) async -> Truthful<ViewerRuntimeResponse> {
        let overview = await fetchMobile(MobileProjectOverview.self, path: "/api/mobile/v1/projects/\(slug)/overview")
        if let payload = overview.value?.viewerRuntime {
            return Truthful(
                value: payload,
                mode: overview.mode,
                observedAt: overview.observedAt,
                source: overview.source,
                error: overview.error
            )
        }
        return await fetch(ViewerRuntimeResponse.self, path: "/api/projects/\(slug)/viewer/runtime")
    }

    // MARK: - POST helper

    public func post<T: Decodable & Sendable>(
        _ type: T.Type,
        path: String,
        body: [String: any Sendable] = [:],
        timeout: TimeInterval = 15
    ) async -> Truthful<T> {
        var lastError = "no base URL reachable"

        for base in baseURLs {
            guard let url = URL(string: path, relativeTo: base) else { continue }
            do {
                var request = URLRequest(url: url)
                request.setValue(BeagleClient.cockpitMobileToken, forHTTPHeaderField: "x-cockpit-token")
                request.httpMethod = "POST"
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                request.timeoutInterval = timeout

                request.httpBody = try JSONSerialization.data(withJSONObject: body)

                let (data, response) = try await session.data(for: request)

                guard let httpResponse = response as? HTTPURLResponse,
                      (200..<300).contains(httpResponse.statusCode) else {
                    let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
                    lastError = formatError(
                        statusCode: statusCode,
                        data: data,
                        fallback: "HTTP \(statusCode)"
                    )
                    continue
                }

                let decoded = try decoder.decode(T.self, from: data)
                return .observed(decoded, source: url.host)
            } catch {
                lastError = error.localizedDescription
                continue
            }
        }
        return .staleError(lastError)
    }

    public func postMobile<T: Decodable & Sendable>(
        _ type: T.Type,
        path: String,
        body: [String: any Sendable] = [:],
        timeout: TimeInterval = 15
    ) async -> Truthful<T> {
        var lastError = "no base URL reachable"

        for base in baseURLs {
            guard let url = URL(string: path, relativeTo: base) else { continue }
            do {
                var request = URLRequest(url: url)
                request.setValue(BeagleClient.cockpitMobileToken, forHTTPHeaderField: "x-cockpit-token")
                request.httpMethod = "POST"
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                request.timeoutInterval = timeout
                request.httpBody = try JSONSerialization.data(withJSONObject: body)

                let (data, response) = try await session.data(for: request)

                guard let httpResponse = response as? HTTPURLResponse,
                      (200..<300).contains(httpResponse.statusCode) else {
                    let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
                    lastError = formatError(
                        statusCode: statusCode,
                        data: data,
                        fallback: "HTTP \(statusCode)"
                    )
                    continue
                }

                let envelope = try decoder.decode(MobileEnvelope<T>.self, from: data)
                guard envelope.ok != false else {
                    lastError = envelope.error?.message ?? "mobile gateway returned ok=false"
                    continue
                }
                guard let payload = envelope.data else {
                    lastError = envelope.error?.message ?? "mobile gateway returned no data"
                    continue
                }

                let mode = TruthMode(rawValue: envelope.meta?.truthMode ?? "") ?? .observed
                return Truthful(
                    value: payload,
                    mode: mode,
                    observedAt: .now,
                    source: url.host,
                    error: nil
                )
            } catch {
                lastError = error.localizedDescription
                continue
            }
        }
        return .staleError(lastError)
    }

    public func deleteMobile<T: Decodable & Sendable>(
        _ type: T.Type,
        path: String,
        body: [String: any Sendable] = [:]
    ) async -> Truthful<T> {
        var lastError = "no base URL reachable"

        for base in baseURLs {
            guard let url = URL(string: path, relativeTo: base) else { continue }
            do {
                var request = URLRequest(url: url)
                request.setValue(BeagleClient.cockpitMobileToken, forHTTPHeaderField: "x-cockpit-token")
                request.httpMethod = "DELETE"
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                request.timeoutInterval = 15
                if !body.isEmpty {
                    request.httpBody = try JSONSerialization.data(withJSONObject: body)
                }

                let (data, response) = try await session.data(for: request)

                guard let httpResponse = response as? HTTPURLResponse,
                      (200..<300).contains(httpResponse.statusCode) else {
                    let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
                    lastError = formatError(
                        statusCode: statusCode,
                        data: data,
                        fallback: "HTTP \(statusCode)"
                    )
                    continue
                }

                let envelope = try decoder.decode(MobileEnvelope<T>.self, from: data)
                guard envelope.ok != false else {
                    lastError = envelope.error?.message ?? "mobile gateway returned ok=false"
                    continue
                }
                guard let payload = envelope.data else {
                    lastError = envelope.error?.message ?? "mobile gateway returned no data"
                    continue
                }

                let mode = TruthMode(rawValue: envelope.meta?.truthMode ?? "") ?? .observed
                return Truthful(
                    value: payload,
                    mode: mode,
                    observedAt: .now,
                    source: url.host,
                    error: nil
                )
            } catch {
                lastError = error.localizedDescription
                continue
            }
        }
        return .staleError(lastError)
    }

    private func formatError(statusCode: Int, data: Data, fallback: String) -> String {
        if let payload = try? decoder.decode(MobileEnvelope<EmptyMobilePayload>.self, from: data) {
            var parts = ["HTTP \(statusCode)"]
            parts.append(payload.error?.message ?? fallback)
            if let reason = payload.error?.reason, !reason.isEmpty {
                parts.append(reason)
            }
            if let code = payload.error?.code, !code.isEmpty {
                parts.append("code=\(code)")
            }
            if let truthMode = payload.meta?.truthMode, !truthMode.isEmpty {
                parts.append("truth=\(truthMode)")
            }
            if let requestId = payload.meta?.requestId, !requestId.isEmpty {
                parts.append("requestId=\(requestId)")
            }
            return parts.joined(separator: " · ")
        }

        if let payload = try? decoder.decode(CockpitBackendErrorPayload.self, from: data) {
            return payload.message(statusCode: statusCode, fallback: fallback)
        }

        let bodyText = String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if let bodyText, !bodyText.isEmpty {
            return "HTTP \(statusCode) · \(bodyText)"
        }

        return fallback
    }

    // MARK: - Agent Sessions

    public func agentSessions(slug: String) async -> Truthful<AgentSessionListResponse> {
        let mobile = await fetchMobile(AgentSessionListResponse.self, path: "/api/mobile/v1/projects/\(slug)/agent-sessions")
        if mobile.value != nil { return mobile }
        return await fetch(AgentSessionListResponse.self, path: "/api/projects/\(slug)/agent/sessions")
    }

    public func agentSession(slug: String, kind: String) async -> Truthful<AgentSession> {
        let mobile = await fetchMobile(AgentSessionDetailResponse.self, path: "/api/mobile/v1/projects/\(slug)/agent-sessions/\(kind)")
        if let session = mobile.value?.session {
            return Truthful(
                value: session,
                mode: mobile.mode,
                observedAt: mobile.observedAt,
                source: mobile.source,
                error: mobile.error
            )
        }
        return await fetch(AgentSession.self, path: "/api/projects/\(slug)/agent/session/\(kind)")
    }

    public func startAgentSession(slug: String, kind: String = "claude-code") async -> Truthful<AgentSession> {
        let mobile = await postMobile(AgentSessionActionResponse.self, path: "/api/mobile/v1/projects/\(slug)/agent-sessions", body: [
            "kind": kind,
            "confirmed": true
        ], timeout: 60)
        if let session = mobile.value?.session {
            return Truthful(
                value: session,
                mode: mobile.mode,
                observedAt: mobile.observedAt,
                source: mobile.source,
                error: mobile.error
            )
        }
        return await post(AgentSession.self, path: "/api/projects/\(slug)/agent/session/start", body: ["kind": kind], timeout: 60)
    }

    public func pauseAgentSession(slug: String, kind: String) async -> Truthful<AgentSession> {
        let mobile = await postMobile(AgentSessionActionResponse.self, path: "/api/mobile/v1/projects/\(slug)/agent-sessions/\(kind)/pause", body: [
            "confirmed": true
        ])
        if let session = mobile.value?.session {
            return Truthful(
                value: session,
                mode: mobile.mode,
                observedAt: mobile.observedAt,
                source: mobile.source,
                error: mobile.error
            )
        }
        return await post(AgentSession.self, path: "/api/projects/\(slug)/agent/session/\(kind)/pause")
    }

    public func resumeAgentSession(slug: String, kind: String) async -> Truthful<AgentSession> {
        let mobile = await postMobile(AgentSessionActionResponse.self, path: "/api/mobile/v1/projects/\(slug)/agent-sessions/\(kind)/resume", body: [
            "confirmed": true
        ])
        if let session = mobile.value?.session {
            return Truthful(
                value: session,
                mode: mobile.mode,
                observedAt: mobile.observedAt,
                source: mobile.source,
                error: mobile.error
            )
        }
        return await post(AgentSession.self, path: "/api/projects/\(slug)/agent/session/\(kind)/resume")
    }

    public func stopAgentSession(slug: String, kind: String) async -> Truthful<AgentSession> {
        let mobile = await deleteMobile(AgentSessionActionResponse.self, path: "/api/mobile/v1/projects/\(slug)/agent-sessions/\(kind)", body: [
            "confirmed": true
        ])
        if let session = mobile.value?.session {
            return Truthful(
                value: session,
                mode: mobile.mode,
                observedAt: mobile.observedAt,
                source: mobile.source,
                error: mobile.error
            )
        }
        return await post(AgentSession.self, path: "/api/projects/\(slug)/agent/session/\(kind)/stop")
    }

    // MARK: - Workspace / Notebook Terminal

    public func workspaces() async -> Truthful<WorkspaceListResponse> {
        await fetch(WorkspaceListResponse.self, path: "/api/workspaces")
    }

    public func workspaceSessions(slug: String) async -> Truthful<WorkspaceSessionListResponse> {
        await fetch(
            WorkspaceSessionListResponse.self,
            path: "/api/workspaces/\(slug)/sessions"
        )
    }

    public func createWorkspaceSession(
        slug: String,
        title: String = "Sounio Workbench",
        layout: NotebookTerminalLayout = .notebook
    ) async -> Truthful<WorkspaceSessionResponse> {
        await post(
            WorkspaceSessionResponse.self,
            path: "/api/workspaces/\(slug)/sessions",
            body: [
                "title": title,
                "layout": layout.rawValue
            ]
        )
    }

    public func workspaceSession(slug: String, sessionId: String) async -> Truthful<WorkspaceSessionResponse> {
        await fetch(
            WorkspaceSessionResponse.self,
            path: "/api/workspaces/\(slug)/sessions/\(sessionId)"
        )
    }

    public func agentRegistry(slug: String) async -> Truthful<AgentRegistryResponse> {
        await fetch(
            AgentRegistryResponse.self,
            path: "/api/workspaces/\(slug)/agents/registry"
        )
    }

    public func agentRoute(
        slug: String,
        task: String,
        privacyClass: String = "sensitive"
    ) async -> Truthful<AgentRouteResponse> {
        await post(
            AgentRouteResponse.self,
            path: "/api/workspaces/\(slug)/agents/route",
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
            path: "/api/workspaces/\(slug)/agents/\(roleOrKind)/start",
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
            path: "/api/workspaces/\(slug)/agents/\(role)/provider-config",
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
            path: "/api/workspaces/\(slug)/sessions/\(sessionId)/panes",
            body: [
                "kind": kind,
                "title": title
            ]
        )
    }

    public func workspaceBlocks(slug: String, sessionId: String) async -> Truthful<WorkspaceBlocksResponse> {
        await fetch(
            WorkspaceBlocksResponse.self,
            path: "/api/workspaces/\(slug)/sessions/\(sessionId)/blocks"
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
            path: "/api/workspaces/\(slug)/sessions/\(sessionId)/blocks/\(blockId)/remember",
            body: body,
            timeout: 30
        )
    }

    // MARK: - Habitat Actions

    public func executeAction(slug: String, actionId: String) async -> Truthful<ActionResponse> {
        let mobile = await postMobile(ActionResponse.self, path: "/api/mobile/v1/projects/\(slug)/actions/\(actionId)", body: [
            "confirmed": true
        ])
        if mobile.value != nil { return mobile }
        return await post(ActionResponse.self, path: "/api/projects/\(slug)/go-work-now/actions/\(actionId)", body: [
            "confirm": true
        ])
    }

    // MARK: - Cluster

    public func clusterSummary(slug: String) async -> Truthful<ClusterSummary> {
        await fetch(ClusterSummary.self, path: "/api/projects/\(slug)/cluster/summary")
    }

    public func goWorkNow(slug: String) async -> Truthful<GoWorkNow> {
        await fetch(GoWorkNow.self, path: "/api/projects/\(slug)/go-work-now")
    }

    // MARK: - Project Memory

    public func fastMemory(slug: String) async -> Truthful<ProjectMemory> {
        await fetch(ProjectMemory.self, path: "/api/projects/\(slug)/memory/fast")
    }

    public func deepMemory(slug: String) async -> Truthful<ProjectMemory> {
        await fetch(ProjectMemory.self, path: "/api/projects/\(slug)/memory/deep", timeout: 15)
    }

    // MARK: - Sovereign Surface

    public func sovereignSurface(slug: String) async -> Truthful<SovereignSurface> {
        await fetch(SovereignSurface.self, path: "/api/projects/\(slug)/sovereign-surface")
    }

    public func truthSummary(slug: String) async -> Truthful<ProjectTruthSummary> {
        await fetch(ProjectTruthSummary.self, path: "/api/projects/\(slug)/truth/summary")
    }

    // MARK: - Git Operations

    public func gitStatus(slug: String) async -> Truthful<GitStatusResponse> {
        await fetch(GitStatusResponse.self, path: "/api/projects/\(slug)/git/status")
    }

    public func gitDiff(slug: String) async -> Truthful<GitDiffResponse> {
        await fetch(GitDiffResponse.self, path: "/api/projects/\(slug)/git/diff")
    }

    // MARK: - Execution & Workflows

    public func executionPackets(slug: String) async -> Truthful<ExecutionPacketsResponse> {
        await fetch(ExecutionPacketsResponse.self, path: "/api/projects/\(slug)/execution/packets")
    }

    public func scientificWorkflows(slug: String) async -> Truthful<ScientificWorkflowsResponse> {
        await fetch(ScientificWorkflowsResponse.self, path: "/api/projects/\(slug)/workflows/scientific")
    }

    public func datasetCatalog(slug: String) async -> Truthful<DatasetCatalogResponse> {
        await fetch(DatasetCatalogResponse.self, path: "/api/projects/\(slug)/datasets/catalog")
    }

    // MARK: - Session

    public func sessionHeartbeat(
        slug: String,
        clientSessionId: String,
        projectFamily: ProjectFamily? = nil,
        publicationScope: PublicationScope? = nil
    ) async -> Truthful<SessionHeartbeatResponse> {
        let family = derivedProjectFamily(slug: slug, override: projectFamily)
        let scope = derivedPublicationScope(
            slug: slug,
            projectFamily: family,
            override: publicationScope
        )
        let mobile = await postMobile(SessionHeartbeatResponse.self, path: "/api/mobile/v1/projects/\(slug)/heartbeat", body: [
            "clientSessionId": clientSessionId,
            "projectFamily": family.rawValue,
            "publicationScope": scope.rawValue,
            "confirmed": true
        ])
        if mobile.value != nil { return mobile }
        return await post(SessionHeartbeatResponse.self, path: "/api/projects/\(slug)/session/heartbeat", body: [
            "clientSessionId": clientSessionId,
            "projectFamily": family.rawValue,
            "publicationScope": scope.rawValue
        ])
    }

    public func saveIdea(
        slug: String,
        text: String,
        source: String,
        refinedText: String? = nil,
        projectFamily: ProjectFamily? = nil,
        publicationScope: PublicationScope? = nil
    ) async -> Truthful<IdeaSaveResponse> {
        let family = derivedProjectFamily(slug: slug, override: projectFamily)
        let scope = derivedPublicationScope(
            slug: slug,
            projectFamily: family,
            override: publicationScope
        )
        var body: [String: any Sendable] = [
            "text": text,
            "rawText": text,
            "raw_text": text,
            "source": source,
            "projectFamily": family.rawValue,
            "publicationScope": scope.rawValue
        ]
        if let refinedText, !refinedText.isEmpty {
            body["refinedText"] = refinedText
            body["refined_text"] = refinedText
        }
        return await postMobile(
            IdeaSaveResponse.self,
            path: "/api/mobile/v1/projects/\(slug)/ideas",
            body: body
        )
    }

    public func delegate(
        slug: String,
        text: String,
        agentKind: String? = nil,
        source: String = "ios",
        projectFamily: ProjectFamily? = nil,
        publicationScope: PublicationScope? = nil
    ) async -> Truthful<DelegationResponse> {
        let family = derivedProjectFamily(slug: slug, override: projectFamily)
        let scope = derivedPublicationScope(
            slug: slug,
            projectFamily: family,
            override: publicationScope
        )
        var body: [String: any Sendable] = [
            "text": text,
            "prompt": text,
            "source": source,
            "projectFamily": family.rawValue,
            "publicationScope": scope.rawValue
        ]
        if let agentKind, !agentKind.isEmpty {
            body["agentKind"] = agentKind
            body["agent_kind"] = agentKind
        }
        return await postMobile(
            DelegationResponse.self,
            path: "/api/mobile/v1/projects/\(slug)/delegations",
            body: body
        )
    }

    // MARK: - Vision (public endpoints)

    public func appleBrief() async -> Truthful<AppleBriefResponse> {
        await fetch(AppleBriefResponse.self, path: "/api/public/vision/apple-brief")
    }

    public func controlRoomVision() async -> Truthful<ControlRoomVisionResponse> {
        await fetch(ControlRoomVisionResponse.self, path: "/api/public/vision/control-room")
    }

    // MARK: - Agent Scratchpad (inter-agent communication)

    public func agentScratchpad(slug: String) async -> Truthful<ScratchpadResponse> {
        await fetch(ScratchpadResponse.self, path: "/api/projects/\(slug)/agents/scratchpad")
    }

    public func postAgentMessage(slug: String, agent: String, text: String, consciousnessState: ConsciousnessState? = nil) async -> Truthful<AgentMessageAck> {
        var body: [String: any Sendable] = [
            "author": agent,
            "text": text
        ]
        if let cs = consciousnessState {
            var csDict: [String: any Sendable] = [:]
            if let hrv = cs.hrvMs { csDict["hrv_ms"] = hrv }
            if let r = cs.readiness { csDict["readiness"] = r }
            if let i = cs.intensity { csDict["intensity"] = i }
            if let cp = cs.circadianPhase { csDict["circadian_phase"] = cp }
            body["consciousness_state"] = csDict
        }
        return await post(AgentMessageAck.self, path: "/api/projects/\(slug)/agents/scratchpad", body: body)
    }
}

struct CockpitBackendErrorPayload: Decodable {
    let error: String?
    let reason: String?
    let truthMode: String?
    let requestId: String?

    enum CodingKeys: String, CodingKey {
        case error
        case reason
        case truthMode
        case requestId
    }

    func message(statusCode: Int, fallback: String) -> String {
        var parts = ["HTTP \(statusCode)"]

        if let error, !error.isEmpty {
            parts.append(error)
        } else {
            parts.append(fallback)
        }
        if let reason, !reason.isEmpty {
            parts.append(reason)
        }
        if let truthMode, !truthMode.isEmpty {
            parts.append("truth=\(truthMode)")
        }
        if let requestId, !requestId.isEmpty {
            parts.append("requestId=\(requestId)")
        }

        return parts.joined(separator: " · ")
    }
}

private struct EmptyMobilePayload: Decodable, Sendable {}
