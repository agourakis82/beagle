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
    private let encoder: JSONEncoder

    /// URL resolution order — tried in sequence until one responds.
    /// Override via `init(session:baseURLs:)` or `configure(baseURLs:)` from the app/tests.
    private var baseURLs: [URL] = BeagleEndpoints.cockpitURLs

    public init(session: URLSession? = nil, baseURLs: [URL]? = nil) {
        if let baseURLs {
            self.baseURLs = baseURLs
        }
        if let session {
            self.session = session
        } else {
            let config = URLSessionConfiguration.default
            config.timeoutIntervalForRequest = 12  // Leave room for edge or tailnet fallback
            config.timeoutIntervalForResource = 30
            config.waitsForConnectivity = true
            config.httpAdditionalHeaders = [
                "Accept": "application/json",
                "User-Agent": "BeagleCockpit/1.0 (iOS/macOS native)"
            ]
            self.session = URLSession(configuration: config)
        }
        self.decoder = JSONDecoder()
        self.encoder = JSONEncoder()
    }

    private static func seg(_ value: String) -> String {
        BeagleEndpoints.pathComponent(value)
    }

    /// Configure the URL resolution order.
    public func configure(baseURLs: [URL]) {
        self.baseURLs = baseURLs
    }

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
                BeagleEndpoints.applyCockpitAuth(to: &request)
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
                BeagleEndpoints.applyCockpitAuth(to: &request)
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
            path: "/api/mobile/v1/projects/\(Self.seg(slug))/overview?depth=\(Self.seg(depth))"
        )
    }

    public func posturePolicy() async -> Truthful<PosturePolicy> {
        await fetch(PosturePolicy.self, path: "/api/catalog/project-posture-policy")
    }

    public func missionControl(slug: String) async -> Truthful<MissionControl> {
        let s = Self.seg(slug)
        let overview = await fetchMobile(MobileProjectOverview.self, path: "/api/mobile/v1/projects/\(s)/overview")
        if let projected = overview.compactMap(\.missionControl) { return projected }
        return await fetch(MissionControl.self, path: "/api/projects/\(s)/mission-control")
    }

    public func clusterLaneTruth(slug: String) async -> Truthful<ClusterLaneTruth> {
        let s = Self.seg(slug)
        let overview = await fetchMobile(MobileProjectOverview.self, path: "/api/mobile/v1/projects/\(s)/overview")
        if let projected = overview.compactMap(\.clusterLaneTruth) { return projected }
        return await fetch(ClusterLaneTruth.self, path: "/api/projects/\(s)/cluster/lane-truth")
    }

    public func researchOperations(slug: String) async -> Truthful<ResearchOperations> {
        let s = Self.seg(slug)
        let overview = await fetchMobile(MobileProjectOverview.self, path: "/api/mobile/v1/projects/\(s)/overview")
        if let projected = overview.compactMap(\.researchOperations) { return projected }
        return await fetch(ResearchOperations.self, path: "/api/projects/\(s)/research/operations")
    }

    public func inferenceRuntime(slug: String) async -> Truthful<InferenceRuntime> {
        let s = Self.seg(slug)
        let overview = await fetchMobile(MobileProjectOverview.self, path: "/api/mobile/v1/projects/\(s)/overview")
        if let projected = overview.compactMap(\.inferenceRuntime) { return projected }
        let wrapped = await fetch(InferenceRuntimeResponse.self, path: "/api/projects/\(s)/inference/runtime")
        // Unwrap nested runtime object
        if let projected = wrapped.compactMap(\.runtime) { return projected }
        return .staleError(wrapped.error ?? "no runtime payload", source: wrapped.source)
    }

    public func viewerRuntime(slug: String) async -> Truthful<ViewerRuntimeResponse> {
        let s = Self.seg(slug)
        let overview = await fetchMobile(MobileProjectOverview.self, path: "/api/mobile/v1/projects/\(s)/overview")
        if let projected = overview.compactMap(\.viewerRuntime) { return projected }
        return await fetch(ViewerRuntimeResponse.self, path: "/api/projects/\(s)/viewer/runtime")
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
                BeagleEndpoints.applyCockpitAuth(to: &request)
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
                BeagleEndpoints.applyCockpitAuth(to: &request)
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

    public func postEncoded<T: Decodable & Sendable, Body: Encodable & Sendable>(
        _ type: T.Type,
        path: String,
        body: Body,
        timeout: TimeInterval = 15
    ) async -> Truthful<T> {
        let payload: Data
        do {
            payload = try encoder.encode(body)
        } catch {
            return .staleError("Failed to encode request: \(error.localizedDescription)")
        }

        var lastError = "no base URL reachable"
        for base in baseURLs {
            guard let url = URL(string: path, relativeTo: base) else { continue }
            do {
                var request = URLRequest(url: url)
                BeagleEndpoints.applyCockpitAuth(to: &request)
                request.httpMethod = "POST"
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                request.timeoutInterval = timeout
                request.httpBody = payload

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

    public func postMobileEncoded<T: Decodable & Sendable, Body: Encodable & Sendable>(
        _ type: T.Type,
        path: String,
        body: Body,
        timeout: TimeInterval = 15
    ) async -> Truthful<T> {
        let payload: Data
        do {
            payload = try encoder.encode(body)
        } catch {
            return .staleError("Failed to encode request: \(error.localizedDescription)")
        }

        var lastError = "no base URL reachable"
        for base in baseURLs {
            guard let url = URL(string: path, relativeTo: base) else { continue }
            do {
                var request = URLRequest(url: url)
                BeagleEndpoints.applyCockpitAuth(to: &request)
                request.httpMethod = "POST"
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                request.timeoutInterval = timeout
                request.httpBody = payload

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

                if let envelope = try? decoder.decode(MobileEnvelope<T>.self, from: data),
                   envelope.ok != false, let unwrapped = envelope.data {
                    let mode = TruthMode(rawValue: envelope.meta?.truthMode ?? "") ?? .observed
                    return Truthful(
                        value: unwrapped,
                        mode: mode,
                        observedAt: .now,
                        source: url.host,
                        error: nil
                    )
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
                BeagleEndpoints.applyCockpitAuth(to: &request)
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

    // MARK: - Habitat Actions

    public func executeAction(slug: String, actionId: String) async -> Truthful<ActionResponse> {
        let s = Self.seg(slug)
        let a = Self.seg(actionId)
        let mobile = await postMobile(ActionResponse.self, path: "/api/mobile/v1/projects/\(s)/actions/\(a)", body: [
            "confirmed": true
        ])
        if mobile.value != nil { return mobile }
        return await post(ActionResponse.self, path: "/api/projects/\(s)/go-work-now/actions/\(a)", body: [
            "confirm": true
        ])
    }

    // MARK: - Cluster & HPC

    public func clusterSummary(slug: String) async -> Truthful<ClusterSummary> {
        await fetch(ClusterSummary.self, path: "/api/projects/\(Self.seg(slug))/cluster/summary")
    }

    public func hpcJobQueue() async -> Truthful<HPCJobQueue> {
        await fetch(HPCJobQueue.self, path: "/api/jobs/queue")
    }

    public func goWorkNow(slug: String) async -> Truthful<GoWorkNow> {
        await fetch(GoWorkNow.self, path: "/api/projects/\(Self.seg(slug))/go-work-now")
    }

    // MARK: - Project Memory

    public func fastMemory(slug: String) async -> Truthful<ProjectMemory> {
        await fetch(ProjectMemory.self, path: "/api/projects/\(Self.seg(slug))/memory/fast")
    }

    public func deepMemory(slug: String) async -> Truthful<ProjectMemory> {
        await fetch(ProjectMemory.self, path: "/api/projects/\(Self.seg(slug))/memory/deep", timeout: 15)
    }

    // MARK: - Sovereign Surface

    public func sovereignSurface(slug: String) async -> Truthful<SovereignSurface> {
        await fetch(SovereignSurface.self, path: "/api/projects/\(Self.seg(slug))/sovereign-surface")
    }

    public func truthSummary(slug: String) async -> Truthful<ProjectTruthSummary> {
        await fetch(ProjectTruthSummary.self, path: "/api/projects/\(Self.seg(slug))/truth/summary")
    }

    // MARK: - Git Operations

    public func gitStatus(slug: String) async -> Truthful<GitStatusResponse> {
        await fetch(GitStatusResponse.self, path: "/api/projects/\(Self.seg(slug))/git/status")
    }

    public func gitDiff(slug: String) async -> Truthful<GitDiffResponse> {
        await fetch(GitDiffResponse.self, path: "/api/projects/\(Self.seg(slug))/git/diff")
    }

    // MARK: - Execution & Workflows

    public func executionPackets(slug: String) async -> Truthful<ExecutionPacketsResponse> {
        await fetch(ExecutionPacketsResponse.self, path: "/api/projects/\(Self.seg(slug))/execution/packets")
    }

    public func scientificWorkflows(slug: String) async -> Truthful<ScientificWorkflowsResponse> {
        await fetch(ScientificWorkflowsResponse.self, path: "/api/projects/\(Self.seg(slug))/workflows/scientific")
    }

    public func datasetCatalog(slug: String) async -> Truthful<DatasetCatalogResponse> {
        await fetch(DatasetCatalogResponse.self, path: "/api/projects/\(Self.seg(slug))/datasets/catalog")
    }

    // MARK: - Session

    public func sessionHeartbeat(
        slug: String,
        clientSessionId: String,
        projectFamily: ProjectFamily? = nil,
        publicationScope: PublicationScope? = nil
    ) async -> Truthful<SessionHeartbeatResponse> {
        let s = Self.seg(slug)
        let family = derivedProjectFamily(slug: slug, override: projectFamily)
        let scope = derivedPublicationScope(
            slug: slug,
            projectFamily: family,
            override: publicationScope
        )
        let mobile = await postMobile(SessionHeartbeatResponse.self, path: "/api/mobile/v1/projects/\(s)/heartbeat", body: [
            "clientSessionId": clientSessionId,
            "projectFamily": family.rawValue,
            "publicationScope": scope.rawValue,
            "confirmed": true
        ])
        if mobile.value != nil { return mobile }
        return await post(SessionHeartbeatResponse.self, path: "/api/projects/\(s)/session/heartbeat", body: [
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
            path: "/api/mobile/v1/projects/\(Self.seg(slug))/ideas",
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
            path: "/api/mobile/v1/projects/\(Self.seg(slug))/delegations",
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

    // MARK: - Mobile Companion & Telemetry Routes

    /// Recent sky + ambient + HRV series for the Agora detail screen's trends.
    public func agoraHistory(hours: Int = 48) async -> Truthful<AgoraHistory> {
        await fetch(AgoraHistory.self, path: "/api/mobile/v1/agora-history?hours=\(hours)", timeout: 20)
    }

    /// Body × sky × ambient correlations (Spearman + lag scan) proxied through the cockpit.
    public func correlations(days: Int = 30) async -> Truthful<PhysioCorrelations> {
        await fetch(PhysioCorrelations.self, path: "/api/mobile/v1/correlations?days=\(days)", timeout: 20)
    }

    /// Flush one queued offline companion turn to the cockpit's memory-spine ingest endpoint.
    public func ingestTurn(_ request: IngestTurnRequest) async -> Truthful<IngestTurnResult> {
        let mobile = await postMobileEncoded(
            IngestTurnResult.self,
            path: "/api/mobile/v1/ingest",
            body: request,
            timeout: 30
        )
        if mobile.value != nil { return mobile }
        return await postEncoded(
            IngestTurnResult.self,
            path: "/api/mobile/v1/ingest",
            body: request,
            timeout: 30
        )
    }

    // MARK: - Agent Scratchpad (inter-agent communication)

    public func agentScratchpad(slug: String) async -> Truthful<ScratchpadResponse> {
        await fetch(ScratchpadResponse.self, path: "/api/projects/\(Self.seg(slug))/agents/scratchpad")
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
        return await post(AgentMessageAck.self, path: "/api/projects/\(Self.seg(slug))/agents/scratchpad", body: body)
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
