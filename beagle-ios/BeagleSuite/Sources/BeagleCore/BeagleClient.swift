//
//  BeagleClient.swift
//  BeagleCore
//
//  HTTP client for the beagle-server (Rust/Axum) scientific endpoints.
//  Mirrors CockpitClient pattern: multi-URL fallback, Truthful<T> responses.
//
//  Endpoints:
//   - /dev/chat, /dev/debate — exocortex conversation + Triad
//   - /api/jobs/science/* — Julia scientific pipelines
//   - /api/hrv — Apple Watch HRV ingest
//   - /api/v1/cognitive/state — aggregated cognitive dashboard
//   - /api/v1/hyperedges — knowledge graph
//   - /api/v1/feedback — learning loop
//

import Foundation

public actor BeagleClient {

    public static let shared = BeagleClient()

    private let session: URLSession
    private let decoder: JSONDecoder

    /// beagle-server URLs — tried in sequence.
    private var baseURLs: [URL] = [
        URL(string: "http://beagle-core.tail21cbc4.ts.net")!,            // Tailnet (HTTP, verified)
        URL(string: "http://beagle-core.beagle.svc.cluster.local:8080")! // In-cluster pod network
    ]

    /// Auth token for beagle-core consumer API.
    /// Obtained via cockpit auth bridge: GET /api/auth/beagle-token
    private var consumerToken: String?
    private var consumerId: String?
    private var tokenFetched = false
    private var authBootstrapError: String?

    private init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 15
        config.timeoutIntervalForResource = 120 // Triad can be slow
        config.waitsForConnectivity = true
        config.httpAdditionalHeaders = [
            "Accept": "application/json",
            "User-Agent": "BeagleCockpit/1.0 (iOS exocortex)"
        ]
        self.session = URLSession(configuration: config)
        self.decoder = JSONDecoder()
    }

    public func configure(baseURLs: [URL], consumerId: String? = nil, token: String? = nil) {
        self.baseURLs = baseURLs
        if let consumerId { self.consumerId = consumerId }
        if let token { self.consumerToken = token }
    }

    /// Whether beagle-server is reachable (quick health check).
    public func isReachable() async -> Bool {
        let result = await fetch([String: Bool].self, path: "/health", requiresAuth: false)
        return result.mode == .observed
    }

    // MARK: - Core fetch (GET)

    public func fetch<T: Decodable & Sendable>(
        _ type: T.Type,
        path: String,
        timeout: TimeInterval = 15,
        requiresAuth: Bool = true
    ) async -> Truthful<T> {
        if requiresAuth {
            let authReady = await ensureAuth()
            guard authReady else {
                let authError = authBootstrapError ?? "Auth bootstrap failed"
                print("[BeagleClient] [\(type)] GET \(path) auth blocked: \(authError)")
                return .staleError(authError)
            }
        }
        var lastError = "beagle-server unreachable"
        let debugLabel = "[\(type)] GET \(path)"
        print("[BeagleClient] \(debugLabel) starting...")

        for base in baseURLs {
            guard let url = URL(string: path, relativeTo: base) else {
                print("[BeagleClient] \(debugLabel) failed to construct URL with base: \(base)")
                continue
            }
            var responseData: Data?
            do {
                var request = URLRequest(url: url)
                request.timeoutInterval = timeout
                applyAuth(&request)
                print("[BeagleClient] \(debugLabel) requesting: \(url)")
                let (data, response) = try await session.data(for: request)
                responseData = data

                guard let http = response as? HTTPURLResponse,
                      (200..<300).contains(http.statusCode) else {
                    let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
                    let bodyText = String(data: data, encoding: .utf8) ?? "<binary>"
                    lastError = formatError(statusCode: statusCode, data: data, fallback: "HTTP \(statusCode)")
                    print("[BeagleClient] \(debugLabel) ❌ HTTP \(statusCode)")
                    print("[BeagleClient] Response body: \(bodyText.prefix(300))")
                    continue
                }

                let decoded = try decoder.decode(T.self, from: data)
                print("[BeagleClient] \(debugLabel) ✅ success")
                return .observed(decoded, source: url.host)
            } catch {
                lastError = error.localizedDescription
                let bodyText: String
                if let data = responseData {
                    bodyText = String(data: data, encoding: .utf8) ?? "<binary>"
                } else {
                    bodyText = "<no response data>"
                }
                print("[BeagleClient] \(debugLabel) ❌ error: \(error.localizedDescription)")
                print("[BeagleClient] Response body: \(bodyText.prefix(300))")
                continue
            }
        }
        print("[BeagleClient] \(debugLabel) all URLs failed: \(lastError)")
        return .staleError(lastError)
    }

    // MARK: - Core POST

    public func post<T: Decodable & Sendable>(
        _ type: T.Type,
        path: String,
        body: [String: any Sendable] = [:],
        timeout: TimeInterval = 120,
        requiresAuth: Bool = true
    ) async -> Truthful<T> {
        if requiresAuth {
            let authReady = await ensureAuth()
            guard authReady else {
                let authError = authBootstrapError ?? "Auth bootstrap failed"
                print("[BeagleClient] [\(type)] POST \(path) auth blocked: \(authError)")
                return .staleError(authError)
            }
        }
        var lastError = "beagle-server unreachable"
        let debugLabel = "[\(type)] POST \(path)"
        print("[BeagleClient] \(debugLabel) starting...")

        for base in baseURLs {
            guard let url = URL(string: path, relativeTo: base) else {
                print("[BeagleClient] \(debugLabel) failed to construct URL with base: \(base)")
                continue
            }
            var responseData: Data?
            do {
                var request = URLRequest(url: url)
                request.httpMethod = "POST"
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                request.timeoutInterval = timeout
                applyAuth(&request)
                request.httpBody = try JSONSerialization.data(withJSONObject: body)

                print("[BeagleClient] \(debugLabel) requesting: \(url)")
                let (data, response) = try await session.data(for: request)
                responseData = data

                guard let http = response as? HTTPURLResponse,
                      (200..<300).contains(http.statusCode) else {
                    let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
                    let bodyText = String(data: data, encoding: .utf8) ?? "<binary>"
                    lastError = formatError(statusCode: statusCode, data: data, fallback: "HTTP \(statusCode)")
                    print("[BeagleClient] \(debugLabel) ❌ HTTP \(statusCode)")
                    print("[BeagleClient] Response body: \(bodyText.prefix(300))")
                    continue
                }

                let decoded = try decoder.decode(T.self, from: data)
                print("[BeagleClient] \(debugLabel) ✅ success")
                return .observed(decoded, source: url.host)
            } catch {
                lastError = error.localizedDescription
                let bodyText: String
                if let data = responseData {
                    bodyText = String(data: data, encoding: .utf8) ?? "<binary>"
                } else {
                    bodyText = "<no response data>"
                }
                print("[BeagleClient] \(debugLabel) ❌ error: \(error.localizedDescription)")
                print("[BeagleClient] Response body: \(bodyText.prefix(300))")
                continue
            }
        }
        print("[BeagleClient] \(debugLabel) all URLs failed: \(lastError)")
        return .staleError(lastError)
    }

    /// Fetch auth token from cockpit bridge (zero hardcode).
    public func ensureAuth() async -> Bool {
        if tokenFetched { return true }
        print("[BeagleClient] ensureAuth starting...")
        // GET /api/auth/beagle-token from the public Cockpit boundary first,
        // with older private paths left as fallback during transition.
        let cockpitURLs = [
            URL(string: "https://beagle.chiuratto.ai")!,
            URL(string: "http://sounio-cockpit.tail21cbc4.ts.net")!,
            URL(string: "http://100.107.208.198")!,
            URL(string: "http://project-cockpit.beagle.svc.cluster.local")!
        ]
        var lastFailure = "Auth bridge unreachable"
        for base in cockpitURLs {
            guard let url = URL(string: "/api/auth/beagle-token", relativeTo: base) else {
                print("[BeagleClient] ensureAuth failed to construct URL")
                lastFailure = "Auth bridge URL construction failed"
                continue
            }
            do {
                print("[BeagleClient] ensureAuth requesting: \(url)")
                let (data, response) = try await session.data(for: URLRequest(url: url))
                guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                    let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
                    lastFailure = formatError(
                        statusCode: statusCode,
                        data: data,
                        fallback: "Auth bridge HTTP \(statusCode)"
                    )
                    print("[BeagleClient] ensureAuth ❌ HTTP \(statusCode)")
                    continue
                }
                if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                    let rawToken = json["token"] as? String
                    let authHeaderValue = json["auth_header_value"] as? String
                    let consumerHeaderName = json["consumer_header_name"] as? String
                    let consumerHeaderValue = json["consumer_header_value"] as? String

                    if let rawToken, !rawToken.isEmpty {
                        consumerToken = rawToken
                    } else if
                        let authHeaderValue,
                        authHeaderValue.hasPrefix("Bearer "),
                        authHeaderValue.count > "Bearer ".count
                    {
                        consumerToken = String(authHeaderValue.dropFirst("Bearer ".count))
                    } else {
                        consumerToken = nil
                    }

                    if consumerHeaderName == "X-Beagle-Consumer", let consumerHeaderValue, !consumerHeaderValue.isEmpty {
                        consumerId = consumerHeaderValue
                    } else {
                        consumerId = json["consumer"] as? String ?? "beagle-operator"
                    }
                    guard
                        let consumerToken,
                        !consumerToken.isEmpty,
                        let consumerId,
                        !consumerId.isEmpty
                    else {
                        lastFailure = "Auth bridge returned incomplete credentials"
                        print("[BeagleClient] ensureAuth ❌ incomplete credentials")
                        continue
                    }
                    print("[BeagleClient] ensureAuth ✅ token acquired: \(consumerId)")
                    // Update base URL if provided
                    let beagleURLString = (json["beagle_url"] as? String) ?? (json["beagleServerUrl"] as? String)
                    if let urlStr = beagleURLString, let serverUrl = URL(string: urlStr) {
                        print("[BeagleClient] ensureAuth updating base URL: \(serverUrl)")
                        baseURLs.insert(serverUrl, at: 0)
                    }
                    tokenFetched = true
                    authBootstrapError = nil
                    return true
                }
                lastFailure = "Auth bridge returned malformed JSON"
            } catch {
                lastFailure = error.localizedDescription
                print("[BeagleClient] ensureAuth ❌ error: \(error.localizedDescription)")
                continue
            }
        }
        authBootstrapError = lastFailure
        print("[BeagleClient] ensureAuth failed: \(lastFailure)")
        return false
    }

    public func authBootstrapStatus() -> Truthful<String> {
        if tokenFetched {
            return .observed(consumerId ?? "token ready", source: "cockpit-auth-bridge")
        }
        if let authBootstrapError {
            return .staleError(authBootstrapError, source: "cockpit-auth-bridge")
        }
        return .declared("auth not attempted", source: "cockpit-auth-bridge")
    }

    private func applyAuth(_ request: inout URLRequest) {
        if let consumerId {
            request.setValue(consumerId, forHTTPHeaderField: "X-Beagle-Consumer")
            print("[BeagleClient] applyAuth: X-Beagle-Consumer = \(consumerId)")
        } else {
            print("[BeagleClient] applyAuth: ⚠️  consumerId is nil")
        }
        if let consumerToken {
            request.setValue("Bearer \(consumerToken)", forHTTPHeaderField: "Authorization")
            print("[BeagleClient] applyAuth: Authorization header set (redacted)")
        } else {
            print("[BeagleClient] applyAuth: ⚠️  consumerToken is nil")
        }
    }

    private func formatError(statusCode: Int, data: Data, fallback: String) -> String {
        if let payload = try? decoder.decode(BeagleBackendErrorPayload.self, from: data) {
            return payload.message(statusCode: statusCode, fallback: fallback)
        }

        let bodyText = String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if let bodyText, !bodyText.isEmpty {
            return "HTTP \(statusCode) · \(bodyText)"
        }

        return fallback
    }

    private func formatMobileError(statusCode: Int, data: Data, fallback: String) -> String {
        if let payload = try? decoder.decode(MobileEnvelope<ChatResponse>.self, from: data) {
            var parts = ["HTTP \(statusCode)"]
            if let message = payload.error?.message, !message.isEmpty {
                parts.append(message)
            } else {
                parts.append(fallback)
            }
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

        let bodyText = String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if let bodyText, !bodyText.isEmpty {
            return "HTTP \(statusCode) · \(bodyText)"
        }

        return fallback
    }

    // MARK: - Thought Capture

    /// Capture a thought via HERMES system prompt → beagle-server.
    public func captureThought(text: String, source: String = "ios") async -> Truthful<ChatResponse> {
        let hermesPrompt = """
        You are HERMES. Refine the following thought fragment into a structured memory while preserving the original insight. Output only the refined text.

        Source: \(source)
        Thought: \(text)
        """
        return await llmComplete(prompt: hermesPrompt)
    }

    // MARK: - Triad (adversarial review)

    /// Submit draft for ATHENA/HERMES/ARGOS/Judge review. Timeout 120s.
    public func runTriad(prompt: String) async -> Truthful<TriadResult> {
        await post(TriadResult.self, path: "/dev/debate", body: [
            "topic": prompt
        ], timeout: 120)
    }

    // MARK: - Science Jobs

    public func startScienceJob(kind: String) async -> Truthful<ScienceJob> {
        await post(ScienceJob.self, path: "/api/jobs/science/start", body: [
            "kind": kind,
            "params": [String: String]() as [String: String]
        ])
    }

    public func scienceJobStatus(jobId: String) async -> Truthful<ScienceJob> {
        await fetch(ScienceJob.self, path: "/api/jobs/science/status/\(jobId)")
    }

    // MARK: - HPC Jobs (Darwin)

    public func submitHPCJob(kind: String, config: [String: String] = [:]) async -> Truthful<HPCJob> {
        await post(HPCJob.self, path: "/api/darwin/hpc/jobs/submit", body: [
            "profile_id": kind,
            "parameters": config
        ])
    }

    public func hpcJobStdout(jobId: String) async -> Truthful<ChatResponse> {
        await fetch(ChatResponse.self, path: "/api/darwin/hpc/jobs/\(jobId)/stdout")
    }

    public func hpcJobStderr(jobId: String) async -> Truthful<ChatResponse> {
        await fetch(ChatResponse.self, path: "/api/darwin/hpc/jobs/\(jobId)/stderr")
    }

    public func hpcProfiles() async -> Truthful<[String: String]> {
        await fetch([String: String].self, path: "/api/darwin/hpc/profiles")
    }

    // MARK: - Pipeline (full: fetch → draft → triad → feedback)

    public func startPipeline(question: String) async -> Truthful<ScienceJob> {
        await post(ScienceJob.self, path: "/api/pipeline/start", body: [
            "question": question
        ])
    }

    public func pipelineStatus(runId: String) async -> Truthful<ScienceJob> {
        await fetch(ScienceJob.self, path: "/api/pipeline/status/\(runId)")
    }

    public func recentRuns() async -> Truthful<[ScienceJob]> {
        await fetch([ScienceJob].self, path: "/api/runs/recent")
    }

    // MARK: - Memory (episodic/semantic)

    public func queryMemory(query: String) async -> Truthful<ChatResponse> {
        await post(ChatResponse.self, path: "/api/memory/query", body: ["query": query])
    }

    // MARK: - Literature Search

    public func searchPubMed(query: String) async -> Truthful<ChatResponse> {
        await post(ChatResponse.self, path: "/api/search/pubmed", body: ["query": query])
    }

    public func searchArxiv(query: String) async -> Truthful<ChatResponse> {
        await post(ChatResponse.self, path: "/api/search/arxiv", body: ["query": query])
    }

    // MARK: - LLM Passthrough

    public func llmComplete(
        prompt: String,
        system: String? = nil,
        projectSlug: String = "sounio",
        projectFamily: ProjectFamily? = nil,
        publicationScope: PublicationScope? = nil,
        discussionProfile: DiscussionProfile = .cluster
    ) async -> Truthful<ChatResponse> {
        let effectivePrompt: String
        if let system, !system.isEmpty {
            effectivePrompt = """
            System instruction:
            \(system)

            User prompt:
            \(prompt)
            """
        } else {
            effectivePrompt = prompt
        }
        let family = projectFamily ?? .fromProjectSlug(projectSlug)
        let scope = publicationScope ?? .forProjectFamily(family)
        let body: [String: any Sendable] = [
            "prompt": effectivePrompt,
            "projectSlug": projectSlug,
            "projectFamily": family.rawValue,
            "publicationScope": scope.rawValue,
            "discussionProfile": discussionProfile.rawValue
        ]

        let mobileResult = await postPublicMobileChat(body: body)
        if mobileResult.value != nil {
            return mobileResult
        }
        if discussionProfile != .cluster {
            return mobileResult
        }

        return await post(ChatResponse.self, path: "/api/llm/complete", body: body)
    }

    // MARK: - HRV

    public func postHRV(hrv: Double, state: String) async -> Truthful<HRVResponse> {
        await post(HRVResponse.self, path: "/api/observer/physio", body: [
            "hrv_ms": hrv,
            "source": "apple-watch"
        ])
    }

    // MARK: - Cognitive State

    public func cognitiveState() async -> Truthful<CognitiveState> {
        await fetch(CognitiveState.self, path: "/api/v1/cognitive/state")
    }

    /// Per-caller Φ rhythm (tool usage patterns).
    public func toolRhythmPhi() async -> Truthful<ChatResponse> {
        await fetch(ChatResponse.self, path: "/api/v1/cognitive/tool_rhythm_phi?caller=ios&split=true")
    }

    /// Joint semantic + behavioral Φ.
    public func jointPhi(hops: Int = 2) async -> Truthful<ChatResponse> {
        await fetch(ChatResponse.self, path: "/api/v1/cognitive/joint_phi?hops=\(hops)")
    }

    /// Recursive Φ (phi of phi).
    public func phiOfPhi() async -> Truthful<ChatResponse> {
        await fetch(ChatResponse.self, path: "/api/v1/cognitive/phi_of_phi")
    }

    /// Meta Φ (phi over recent events).
    public func metaPhi() async -> Truthful<ChatResponse> {
        await fetch(ChatResponse.self, path: "/api/v1/cognitive/meta_phi")
    }

    /// Chained deep-think: fractal + void + phi in sequence.
    public func deepThink(prompt: String) async -> Truthful<ChatResponse> {
        await deepThink(prompt: prompt, depth: 3)
    }

    // MARK: - Hypergraph

    public func queryHyperedges(nodeId: String? = nil) async -> Truthful<[Hyperedge]> {
        let detail = nodeId.map { " for node \($0)" } ?? ""
        return .staleError("Hyperedge route retired on current beagle-core backend\(detail)")
    }

    public func createHyperedge(label: String, nodeIds: [String]) async -> Truthful<Hyperedge> {
        .staleError("Hyperedge creation route retired on current beagle-core backend")
    }

    // MARK: - Feedback

    public func postFeedback(event: FeedbackEvent) async -> Truthful<FeedbackAck> {
        var body: [String: any Sendable] = [
            "run_id": event.runId,
            "event_type": event.kind
        ]
        let ratings = [event.clarity, event.adequacy, event.safety].compactMap { $0 }
        if !ratings.isEmpty {
            let average = Int((Double(ratings.reduce(0, +)) / Double(ratings.count)).rounded())
            body["rating_0_10"] = average
        }
        if let n = event.notes { body["notes"] = n }
        return await post(FeedbackAck.self, path: "/api/v1/feedback", body: body)
    }

    // MARK: - Chat (generic exocortex conversation)

    public func chat(
        prompt: String,
        system: String? = nil,
        projectSlug: String = "sounio",
        projectFamily: ProjectFamily? = nil,
        publicationScope: PublicationScope? = nil,
        discussionProfile: DiscussionProfile = .cluster
    ) async -> Truthful<ChatResponse> {
        await llmComplete(
            prompt: prompt,
            system: system,
            projectSlug: projectSlug,
            projectFamily: projectFamily,
            publicationScope: publicationScope,
            discussionProfile: discussionProfile
        )
    }

    private func postPublicMobileChat(body: [String: any Sendable]) async -> Truthful<ChatResponse> {
        let cockpitURLs = [
            URL(string: "https://beagle.chiuratto.ai")!,
            URL(string: "http://sounio-cockpit.tail21cbc4.ts.net")!,
            URL(string: "http://100.107.208.198")!,
            URL(string: "http://project-cockpit.beagle.svc.cluster.local")!
        ]

        var lastError = "mobile chat gateway unreachable"
        let debugLabel = "[\(ChatResponse.self)] POST /api/mobile/v1/chat"
        print("[BeagleClient] \(debugLabel) starting...")

        for base in cockpitURLs {
            guard let url = URL(string: "/api/mobile/v1/chat", relativeTo: base) else { continue }
            do {
                var request = URLRequest(url: url)
                request.httpMethod = "POST"
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                request.timeoutInterval = 60
                request.httpBody = try JSONSerialization.data(withJSONObject: body)

                print("[BeagleClient] \(debugLabel) requesting: \(url)")
                let (data, response) = try await session.data(for: request)

                guard let http = response as? HTTPURLResponse,
                      (200..<300).contains(http.statusCode) else {
                    let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
                    lastError = formatMobileError(
                        statusCode: statusCode,
                        data: data,
                        fallback: "HTTP \(statusCode)"
                    )
                    print("[BeagleClient] \(debugLabel) ❌ HTTP \(statusCode)")
                    continue
                }

                let envelope = try decoder.decode(MobileEnvelope<ChatResponse>.self, from: data)
                guard envelope.ok != false else {
                    lastError = envelope.error?.message ?? "mobile chat returned ok=false"
                    print("[BeagleClient] \(debugLabel) ❌ envelope ok=false")
                    continue
                }
                guard let payload = envelope.data else {
                    lastError = envelope.error?.message ?? "mobile chat returned no data"
                    print("[BeagleClient] \(debugLabel) ❌ envelope missing data")
                    continue
                }

                let mode = TruthMode(rawValue: envelope.meta?.truthMode ?? "") ?? .observed
                print("[BeagleClient] \(debugLabel) ✅ success")
                return Truthful(
                    value: payload,
                    mode: mode,
                    observedAt: .now,
                    source: url.host,
                    error: nil
                )
            } catch {
                lastError = error.localizedDescription
                print("[BeagleClient] \(debugLabel) ❌ error: \(error.localizedDescription)")
                continue
            }
        }

        print("[BeagleClient] \(debugLabel) all URLs failed: \(lastError)")
        return .staleError(lastError, source: "cockpit-mobile-gateway")
    }

    // MARK: - Novelty Endpoints (Void, Fractal, Phi)

    public func startVoidJourney(prompt: String, maxDepth: Int = 3) async -> Truthful<VoidJourney> {
        await post(VoidJourney.self, path: "/dev/void", body: [
            "focus": prompt,
            "target_depth": maxDepth,
            "deep": true
        ] as [String: any Sendable])
    }

    public func startFractalTree(prompt: String, maxDepth: Int = 2, branching: Int = 2) async -> Truthful<FractalTree> {
        await post(FractalTree.self, path: "/api/fractal/recurse", body: [
            "root_prompt": prompt,
            "max_depth": maxDepth,
            "branching_factor": branching
        ] as [String: any Sendable])
    }

    public func measurePhi(prompt: String) async -> Truthful<PhiMeasurement> {
        await post(PhiMeasurement.self, path: "/api/exocortex/process", body: [
            "query": prompt
        ] as [String: any Sendable])
    }

    // MARK: - Go Deeper (advanced reasoning)

    public func deepResearch(query: String) async -> Truthful<DeepResearchResult> {
        // Backend field: research_question (verified 2026-04-15)
        await post(DeepResearchResult.self, path: "/dev/deep-research", body: ["research_question": query], timeout: 180)
    }

    public func quantumReasoning(
        hypotheses: [[String: any Sendable]],
        threshold: Double = 0.15,
        interferenceStrength: Double = 1.0,
        probabilistic: Bool = true,
        applyDecoherence: Bool = true
    ) async -> Truthful<QuantumReasoningResult> {
        .staleError("Quantum reasoning route is retired on the current beagle-core backend")
    }

    public func swarmConsensus(query: String) async -> Truthful<SwarmResult> {
        // Backend field: exploration_query (verified 2026-04-15)
        await post(SwarmResult.self, path: "/dev/swarm", body: ["exploration_query": query], timeout: 120)
    }

    public func causalExtract(text: String) async -> Truthful<CausalGraph> {
        // Backend field: query (verified 2026-04-15)
        await post(CausalGraph.self, path: "/dev/causal", body: ["query": text], timeout: 60)
    }

    public func causalIntervention(
        graphId: String,
        intervention: String
    ) async -> Truthful<CausalIntervention> {
        .staleError("Causal intervention route is retired on the current beagle-core backend")
    }

    public func temporalReasoning(query: String) async -> Truthful<TemporalResult> {
        // Backend field: events (array) (verified 2026-04-15)
        await post(TemporalResult.self, path: "/dev/temporal", body: ["events": [query]], timeout: 90)
    }

    public func neurosymbolicReasoning(query: String) async -> Truthful<NeurosymbolicResult> {
        // Backend field: problem (verified 2026-04-15)
        await post(NeurosymbolicResult.self, path: "/dev/neurosymbolic", body: ["problem": query], timeout: 90)
    }

    public func adversarialCompete(query: String) async -> Truthful<AdversarialResult> {
        .staleError("Adversarial compete route is retired on the current beagle-core backend")
    }

    public func research(query: String) async -> Truthful<ResearchResult> {
        // Backend field: research_goal (verified 2026-04-15)
        await post(ResearchResult.self, path: "/dev/research", body: ["research_goal": query], timeout: 120)
    }

    public func researchParallel(query: String) async -> Truthful<ParallelResearchResult> {
        await post(ParallelResearchResult.self, path: "/dev/parallel", body: [
            "queries": [query]
        ], timeout: 180)
    }

    public func reasoningPath(source: String, target: String) async -> Truthful<ReasoningPathResult> {
        // Backend expects start_concept / end_concept (verified 2026-04-15)
        await post(ReasoningPathResult.self, path: "/dev/reasoning", body: [
            "start_concept": source, "target_concept": target
        ] as [String: any Sendable], timeout: 90)
    }

    // MARK: - World Model

    public func worldModelState() async -> Truthful<WorldModelState> {
        // /api/worldmodel/predict requires POST with context field (verified 2026-04-15)
        await post(WorldModelState.self, path: "/api/worldmodel/predict", body: ["context": "current"], timeout: 30)
    }

    public func worldModelPredict(query: String) async -> Truthful<WorldModelPrediction> {
        await post(WorldModelPrediction.self, path: "/api/worldmodel/predict", body: ["context": query], timeout: 60)
    }

    public func worldModelCounterfactual(query: String) async -> Truthful<WorldModelCounterfactual> {
        .staleError("World model counterfactual route is retired on the current beagle-core backend")
    }

    // MARK: - Extended (Fractal, PCS, Serendipity)

    public func fractalGrow(seed: String) async -> Truthful<FractalGrowResult> {
        // Backend field: root_prompt (verified 2026-04-15)
        await post(FractalGrowResult.self, path: "/api/fractal/recurse", body: ["root_prompt": seed], timeout: 90)
    }

    public func pcsReason(query: String) async -> Truthful<PCSReasonResult> {
        await post(PCSReasonResult.self, path: "/api/pcs/reason", body: ["symptoms": [query]], timeout: 60)
    }

    public func serendipityDiscover(query: String) async -> Truthful<SerendipityResult> {
        .staleError("Serendipity route no longer accepts free-text query input on the current beagle-core backend")
    }

    public func deepThink(prompt: String, depth: Int = 3) async -> Truthful<ChatResponse> {
        // Backend field: root_prompt (verified 2026-04-15)
        await post(ChatResponse.self, path: "/api/cognitive/deep-think", body: [
            "root_prompt": prompt, "max_depth": depth
        ] as [String: any Sendable], timeout: 180)
    }
}

struct BeagleBackendErrorPayload: Decodable {
    let error: String?
    let reason: String?
    let truthMode: String?
    let requestId: String?
    let caller: String?
    let via: String?
    let proxiedPath: String?

    enum CodingKeys: String, CodingKey {
        case error
        case reason
        case truthMode
        case requestId
        case caller
        case via
        case proxiedPath = "proxied_path"
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
        if let caller, !caller.isEmpty {
            parts.append("caller=\(caller)")
        }
        if let via, !via.isEmpty {
            parts.append("via=\(via)")
        }
        if let proxiedPath, !proxiedPath.isEmpty {
            parts.append("path=\(proxiedPath)")
        }

        return parts.joined(separator: " · ")
    }
}
