//
//  CockpitClient.swift
//  BeagleCore
//
//  Truth-aware HTTP client for the cockpit API.
//  Uses URLSession with Swift 6 async/await.
//  Returns Truthful<T> wrappers preserving epistemic metadata.
//
//  Tailscale addressing: resolves multiple URLs in preference order
//  (public tailnet → internal VIP → cluster service DNS) so the same app
//  works whether on tailnet, LAN, or remote.
//

import Foundation

public actor CockpitClient {

    public static let shared = CockpitClient()

    private let session: URLSession
    private let decoder: JSONDecoder

    /// URL resolution order — tried in sequence until one responds.
    /// Override via `configure(baseURLs:)` from the app.
    private var baseURLs: [URL] = [
        URL(string: "https://sounio-cockpit.tail21cbc4.ts.net")!,       // Tailnet (TLS)
        URL(string: "http://project-cockpit.beagle.svc.cluster.local")! // In-cluster (pod network only)
    ]

    private init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 8
        config.timeoutIntervalForResource = 15
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

    // MARK: - Core fetch

    /// Fetch a typed response with truth-aware error handling.
    /// Tries each base URL in order; returns the first success.
    public func fetch<T: Decodable & Sendable>(
        _ type: T.Type,
        path: String,
        timeout: TimeInterval = 8
    ) async -> Truthful<T> {
        var lastError: String = "no base URL reachable"

        for base in baseURLs {
            guard let url = URL(string: path, relativeTo: base) else { continue }
            do {
                var request = URLRequest(url: url)
                request.timeoutInterval = timeout
                let (data, response) = try await session.data(for: request)

                guard let httpResponse = response as? HTTPURLResponse else {
                    lastError = "invalid response"
                    continue
                }

                guard (200..<300).contains(httpResponse.statusCode) else {
                    lastError = "HTTP \(httpResponse.statusCode)"
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

    // MARK: - High-level API

    public func catalog() async -> Truthful<ExecutiveCatalog> {
        await fetch(ExecutiveCatalog.self, path: "/api/catalog/executive")
    }

    public func posturePolicy() async -> Truthful<PosturePolicy> {
        await fetch(PosturePolicy.self, path: "/api/catalog/project-posture-policy")
    }

    public func missionControl(slug: String) async -> Truthful<MissionControl> {
        await fetch(MissionControl.self, path: "/api/projects/\(slug)/mission-control")
    }

    public func clusterLaneTruth(slug: String) async -> Truthful<ClusterLaneTruth> {
        await fetch(ClusterLaneTruth.self, path: "/api/projects/\(slug)/cluster/lane-truth")
    }

    public func researchOperations(slug: String) async -> Truthful<ResearchOperations> {
        await fetch(ResearchOperations.self, path: "/api/projects/\(slug)/research/operations")
    }

    public func inferenceRuntime(slug: String) async -> Truthful<InferenceRuntime> {
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
        await fetch(ViewerRuntimeResponse.self, path: "/api/projects/\(slug)/viewer/runtime")
    }

    // MARK: - POST helper

    public func post<T: Decodable & Sendable>(
        _ type: T.Type,
        path: String,
        body: [String: any Sendable] = [:]
    ) async -> Truthful<T> {
        var lastError = "no base URL reachable"

        for base in baseURLs {
            guard let url = URL(string: path, relativeTo: base) else { continue }
            do {
                var request = URLRequest(url: url)
                request.httpMethod = "POST"
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                request.timeoutInterval = 15

                // Encode confirmed: true by default
                var payload = body
                if payload["confirmed"] == nil { payload["confirmed"] = true }
                request.httpBody = try JSONSerialization.data(withJSONObject: payload)

                let (data, response) = try await session.data(for: request)

                guard let httpResponse = response as? HTTPURLResponse,
                      (200..<300).contains(httpResponse.statusCode) else {
                    lastError = "HTTP \((response as? HTTPURLResponse)?.statusCode ?? 0)"
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

    // MARK: - Agent Sessions

    public func agentSessions(slug: String) async -> Truthful<AgentSessionListResponse> {
        await fetch(AgentSessionListResponse.self, path: "/api/projects/\(slug)/agent/sessions")
    }

    public func agentSession(slug: String, kind: String) async -> Truthful<AgentSession> {
        await fetch(AgentSession.self, path: "/api/projects/\(slug)/agent/session/\(kind)")
    }

    public func startAgentSession(slug: String, kind: String = "claude-code") async -> Truthful<AgentSession> {
        await post(AgentSession.self, path: "/api/projects/\(slug)/agent/session/start", body: ["kind": kind])
    }

    public func pauseAgentSession(slug: String, kind: String) async -> Truthful<AgentSession> {
        await post(AgentSession.self, path: "/api/projects/\(slug)/agent/session/\(kind)/pause")
    }

    public func resumeAgentSession(slug: String, kind: String) async -> Truthful<AgentSession> {
        await post(AgentSession.self, path: "/api/projects/\(slug)/agent/session/\(kind)/resume")
    }

    public func stopAgentSession(slug: String, kind: String) async -> Truthful<AgentSession> {
        await post(AgentSession.self, path: "/api/projects/\(slug)/agent/session/\(kind)/stop")
    }

    // MARK: - Habitat Actions

    public func executeAction(slug: String, actionId: String) async -> Truthful<ActionResponse> {
        await post(ActionResponse.self, path: "/api/projects/\(slug)/go-work-now/actions/\(actionId)")
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

    public func sessionHeartbeat(slug: String, clientSessionId: String) async -> Truthful<SessionHeartbeatResponse> {
        await post(SessionHeartbeatResponse.self, path: "/api/projects/\(slug)/session/heartbeat", body: [
            "clientSessionId": clientSessionId
        ])
    }

    // MARK: - Vision (public endpoints)

    public func appleBrief() async -> Truthful<AppleBriefResponse> {
        await fetch(AppleBriefResponse.self, path: "/api/public/vision/apple-brief")
    }

    public func controlRoomVision() async -> Truthful<ControlRoomVisionResponse> {
        await fetch(ControlRoomVisionResponse.self, path: "/api/public/vision/control-room")
    }

    // MARK: - Agent Scratchpad (inter-agent communication)

    public func agentScratchpad(slug: String) async -> Truthful<AgentScratchpad> {
        await fetch(AgentScratchpad.self, path: "/api/projects/\(slug)/agents/scratchpad")
    }

    public func postAgentMessage(slug: String, agent: String, kind: String, content: String) async -> Truthful<AgentMessageAck> {
        await post(AgentMessageAck.self, path: "/api/projects/\(slug)/agents/scratchpad", body: [
            "agent": agent,
            "surface": "ios",
            "kind": kind,
            "content": content
        ])
    }
}
