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

    /// Shared secret gating the project-cockpit's `/api/mobile/v1/*` surface — that API is
    /// reachable on the public internet (beagle.chiuratto.ai), so every request must prove
    /// physical possession of this build. Personal single-user app: a compiled-in constant
    /// matches this app's existing trust model (device possession = access), same as the
    /// other hardcoded endpoints/UAs already in this file. Rotate by regenerating + rebuilding.
    // internal (module-visible), not fileprivate: PhysiomeUploader (same BeagleCore module)
    // also needs it — its own token-bridge + ingest requests were missed in the original
    // cockpit-auth pass (a duplicate refreshPhysiomeToken() implementation, not routed
    // through this actor).
    // public, not just internal: BeagleCockpit-module screens (e.g. CognitiveRecall.swift)
    // also need it — BeagleCore and BeagleCockpit are separate modules, so `internal` isn't
    // enough.
    public static let cockpitMobileToken = "63e6190ef59507df275fb3550398bf7012afabc6a8075bb70f3869c8cb9e2f7e"

    public static let shared = BeagleClient()

    private let session: URLSession
    private let decoder: JSONDecoder
    private let encoder: JSONEncoder

    /// beagle-server URLs — tried in sequence.
    private var baseURLs: [URL] = [
        URL(string: "https://beagle.chiuratto.ai")!,                      // Public gateway (works from any device)
        URL(string: "http://beagle-core.tail21cbc4.ts.net")!,             // Tailnet (when on VPN)
        URL(string: "http://beagle-core.beagle.svc.cluster.local:8080")!  // In-cluster pod network
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
        self.encoder = JSONEncoder()
    }

    public func configure(baseURLs: [URL], consumerId: String? = nil, token: String? = nil) {
        self.baseURLs = baseURLs
        if let consumerId { self.consumerId = consumerId }
        if let token { self.consumerToken = token }
    }

    private static func pathComponent(_ value: String) -> String {
        value.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? value
    }

    /// Whether beagle-server is reachable (quick health check).
    /// Minimal decode of GET /health. The server returns a MIXED-type object
    /// ({"status":"ok","safe_mode":true,...}); decoding it as [String: Bool] (the old
    /// shape) always failed on the string fields, so isReachable() returned false — which
    /// silently gated every CognitiveStore.refresh(), so a triggered fractal/Φ (or any
    /// cognitive refresh) never surfaced in the UI. A permissive struct just confirms the
    /// server answered with parseable JSON.
    private struct HealthProbe: Decodable { let status: String? }

    public func isReachable() async -> Bool {
        let result = await fetch(HealthProbe.self, path: "/health", requiresAuth: false)
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

    public func postEncoded<T: Decodable & Sendable, Body: Encodable & Sendable>(
        _ type: T.Type,
        path: String,
        body: Body,
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

        let payload: Data
        do {
            payload = try encoder.encode(body)
        } catch {
            return .staleError("Failed to encode request: \(error.localizedDescription)")
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
                request.httpBody = payload

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
    /// Re-fetches when token is older than 4 minutes (server TTL is 5min).
    private var tokenFetchedAt: Date?
    private let tokenRefreshInterval: TimeInterval = 4 * 60 // 4 minutes

    public func ensureAuth() async -> Bool {
        if tokenFetched,
           let fetchedAt = tokenFetchedAt,
           Date().timeIntervalSince(fetchedAt) < tokenRefreshInterval {
            return true
        }
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
                var request = URLRequest(url: url)
                request.setValue(Self.cockpitMobileToken, forHTTPHeaderField: "x-cockpit-token")
                print("[BeagleClient] ensureAuth requesting: \(url)")
                let (data, response) = try await session.data(for: request)
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
                    if let urlStr = beagleURLString, let serverUrl = URL(string: urlStr),
                       !baseURLs.contains(serverUrl) {
                        print("[BeagleClient] ensureAuth updating base URL: \(serverUrl)")
                        baseURLs.insert(serverUrl, at: 0)
                    }
                    tokenFetched = true
                    tokenFetchedAt = Date()
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

    /// Returns the current bearer token after ensuring auth, for use by first-party
    /// WebSocket clients (e.g. MoshiSessionManager) that cannot use applyAuth directly.
    /// Falls back to empty string if auth is unavailable.
    public func resolvedBearerToken() async -> String {
        if !tokenFetched { _ = await ensureAuth() }
        return consumerToken ?? ""
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

    /// Capture a thought as cluster-canonical GraphRAG++ memory.
    public func captureThought(text: String, source: String = "ios") async -> Truthful<ChatResponse> {
        let request = AssistedImportRequestFactory.capture(
            text: text,
            source: source
        )
        if request.privacyClass == "restricted" {
            return .declared(
                ChatResponse(
                    response: "Restricted content was not uploaded. It must stay in the local outbox until you explicitly review it.",
                    model: "beagle-local-privacy-guard",
                    source: request.sourceSurface,
                    sessionId: request.sessionId,
                    conversationMode: "restricted_local_only"
                ),
                source: request.sourceSurface
            )
        }

        let result = await assistedImportBatch(request)
        guard let importResult = result.value else {
            return .staleError(result.error ?? "Assisted import failed", source: result.source)
        }
        let atoms = importResult.projection?.atomsCreated ?? 0
        let episodes = importResult.projection?.episodesCreated ?? 0
        let response = importResult.status == "imported"
            ? "Captured into cluster GraphRAG++ memory (\(episodes) episode, \(atoms) atoms)."
            : (importResult.reason ?? "Capture was not imported.")
        return Truthful(
            value: ChatResponse(
                response: response,
                model: "beagle-graphrag++",
                source: importResult.sourceSurface,
                sessionId: importResult.sessionId,
                conversationMode: "assisted_import"
            ),
            mode: result.mode,
            observedAt: result.observedAt,
            source: result.source,
            error: result.error
        )
    }

    // MARK: - Triad (adversarial review)

    /// Submit draft for ATHENA/HERMES/ARGOS/Judge review. Timeout 120s.
    public func runTriad(prompt: String) async -> Truthful<TriadResult> {
        await post(TriadResult.self, path: "/dev/debate", body: [
            "topic": prompt
        ], timeout: 120)
    }

    /// Streaming debate: consumes the SSE endpoint and yields incremental events
    /// (text deltas as agents speak, then a final consolidated TriadResult).
    /// Falls back through the same multi-URL chain as the non-streaming path.
    nonisolated public func streamTriad(prompt: String) -> AsyncStream<TriadStreamEvent> {
        AsyncStream { continuation in
            let task = Task { [weak self] in
                guard let self else { continuation.finish(); return }

                let authReady = await self.ensureAuth()
                guard authReady else {
                    continuation.yield(.error(await self.authBootstrapError ?? "Auth bootstrap failed"))
                    continuation.finish()
                    return
                }

                // Snapshot actor-isolated state up front so the streaming loop runs
                // off-actor with Sendable values only. The actor's decoder is a plain
                // JSONDecoder(); a local one is equivalent and avoids crossing a
                // non-Sendable JSONDecoder across the actor boundary per frame.
                let bases = await self.baseURLs
                let session = await self.session
                let decoder = JSONDecoder()

                for base in bases {
                    if Task.isCancelled { break }
                    // applyAuth mutates an inout request, so build it on the actor.
                    guard let request = await self.makeDebateStreamRequest(base: base, prompt: prompt) else { continue }

                    do {
                        let (bytes, response) = try await session.bytes(for: request)
                        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                            continue // try the next base URL
                        }
                        for try await line in bytes.lines {
                            if Task.isCancelled { break }
                            // SSE frames look like "data: <payload>"; ignore comments/blanks.
                            guard line.hasPrefix("data:") else { continue }
                            let payload = String(line.dropFirst(5)).trimmingCharacters(in: .whitespaces)
                            if payload.isEmpty || payload == "[DONE]" { continue }
                            guard let data = payload.data(using: .utf8) else { continue }
                            // A full TriadResult frame ends the stream; otherwise it's a delta.
                            if let final = try? decoder.decode(TriadResult.self, from: data),
                               final.consensus != nil || final.scores != nil {
                                continuation.yield(.final(final))
                            } else if let delta = try? decoder.decode(TriadStreamDelta.self, from: data) {
                                continuation.yield(.delta(agent: delta.agent, text: delta.text ?? delta.content ?? ""))
                            } else {
                                continuation.yield(.delta(agent: nil, text: payload))
                            }
                        }
                        continuation.finish()
                        return
                    } catch {
                        continue // network/parse error → next base URL
                    }
                }
                if !Task.isCancelled {
                    continuation.yield(.error("Debate stream unreachable on all endpoints."))
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    /// Actor-isolated builder so `applyAuth` (which mutates an inout request) runs
    /// on the actor; returns a Sendable URLRequest for the off-actor stream loop.
    private func makeDebateStreamRequest(base: URL, prompt: String) -> URLRequest? {
        guard let url = URL(string: "/dev/debate", relativeTo: base) else { return nil }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 180
        applyAuth(&request)
        request.httpBody = try? JSONSerialization.data(withJSONObject: ["topic": prompt, "stream": true])
        return request
    }

    // MARK: - Round Table (exotic model debate)

    /// Orchestrate exotic reasoning crates to debate a topic.
    /// Each voice runs in parallel on the backend; results include interference + PCI.
    public func roundTable(prompt: String, voices: [String]) async -> Truthful<RoundTableResult> {
        await post(RoundTableResult.self, path: "/api/v1/round-table", body: [
            "prompt": prompt,
            "voices": voices
        ], timeout: 180)
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

    // MARK: - Exocortex v1

    public func exocortexHome(
        activeProjectSlug: String? = nil,
        platform: String = "apple"
    ) async -> Truthful<ExocortexHomeSnapshot> {
        var queryItems: [String] = []
        if let activeProjectSlug,
           let encoded = activeProjectSlug.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) {
            queryItems.append("active_project_slug=\(encoded)")
        }
        if let encoded = platform.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) {
            queryItems.append("platform=\(encoded)")
        }
        let suffix = queryItems.isEmpty ? "" : "?\(queryItems.joined(separator: "&"))"
        return await fetch(
            ExocortexHomeSnapshot.self,
            path: "/api/exocortex/v1/home\(suffix)",
            timeout: 20
        )
    }

    public func memoryProjectionStatus() async -> Truthful<MemoryProjectionStatus> {
        await fetch(
            MemoryProjectionStatus.self,
            path: "/api/exocortex/v1/memory/projection/status",
            timeout: 20
        )
    }

    public func memoryGraphStatus() async -> Truthful<MemoryGraphStatus> {
        await fetch(
            MemoryGraphStatus.self,
            path: "/api/exocortex/v1/memory/graph/status",
            timeout: 20
        )
    }

    public func memoryGraphBakeoffStatus() async -> Truthful<MemoryGraphStatus> {
        await fetch(
            MemoryGraphStatus.self,
            path: "/api/exocortex/v1/memory/graph/bakeoff/status",
            timeout: 20
        )
    }

    public func memoryBenchmarkStatus() async -> Truthful<MemoryBenchmarkStatus> {
        await fetch(
            MemoryBenchmarkStatus.self,
            path: "/api/exocortex/v1/memory/bench/status",
            timeout: 20
        )
    }

    public func memoryTruthSetStatus(id: String) async -> Truthful<MemoryTruthSetStatus> {
        await fetch(
            MemoryTruthSetStatus.self,
            path: "/api/exocortex/v1/memory/truthsets/\(id)",
            timeout: 20
        )
    }

    public func runMemoryGraphBakeoff(datasetLimit: Int = 200) async -> Truthful<GraphBakeoffRun> {
        await post(
            GraphBakeoffRun.self,
            path: "/api/exocortex/v1/memory/graph/bakeoff",
            body: [
                "dataset_limit": max(1, min(datasetLimit, 2000)),
                "include_baseline": true
            ],
            timeout: 120
        )
    }

    public func indexMemoryGraph(rebuild: Bool = false, runtime: String? = nil) async -> Truthful<GraphIndexRun> {
        var body: [String: any Sendable] = [
            "rebuild": rebuild,
            "source_refs": [String]()
        ]
        if let runtime, !runtime.isEmpty {
            body["runtime"] = runtime
        }
        return await post(
            GraphIndexRun.self,
            path: "/api/exocortex/v1/memory/index-graph",
            body: body,
            timeout: 120
        )
    }

    public func memoryGraphRecent(limit: Int = 12) async -> Truthful<MemoryGraphRecentResponse> {
        await fetch(
            MemoryGraphRecentResponse.self,
            path: "/api/exocortex/v1/memory/graph/recent?limit=\(max(1, min(limit, 50)))",
            timeout: 20
        )
    }

    public func memoryWorldsRecent(limit: Int = 12) async -> Truthful<MemoryWorldsRecentResponse> {
        await fetch(
            MemoryWorldsRecentResponse.self,
            path: "/api/exocortex/v1/memory/worlds/recent?limit=\(max(1, min(limit, 50)))",
            timeout: 20
        )
    }

    public func registerSpatialWorld(_ request: CreateSpatialWorldRequest) async -> Truthful<SpatialWorld> {
        await postEncoded(
            SpatialWorld.self,
            path: "/api/exocortex/v1/spatial/worlds/marble",
            body: request,
            timeout: 60
        )
    }

    public func spatialWorld(_ worldId: String) async -> Truthful<SpatialWorld> {
        await fetch(
            SpatialWorld.self,
            path: "/api/exocortex/v1/spatial/worlds/\(Self.pathComponent(worldId))",
            timeout: 20
        )
    }

    public func spatialWorldAssets(_ worldId: String) async -> Truthful<SpatialAssetManifest> {
        await fetch(
            SpatialAssetManifest.self,
            path: "/api/exocortex/v1/spatial/worlds/\(Self.pathComponent(worldId))/assets",
            timeout: 20
        )
    }

    public func spatialControlRoom(projectSlug: String = "sounio") async -> Truthful<ControlRoomSnapshot> {
        await fetch(
            ControlRoomSnapshot.self,
            path: "/api/exocortex/v1/spatial/projects/\(Self.pathComponent(projectSlug))/control-room",
            timeout: 20
        )
    }

    public func createSounioSpatialEvidence(
        worldId: String,
        request: CreateSounioSpatialEvidenceRequest
    ) async -> Truthful<SounioSpatialEvidence> {
        await postEncoded(
            SounioSpatialEvidence.self,
            path: "/api/exocortex/v1/spatial/worlds/\(Self.pathComponent(worldId))/sounio/evidence",
            body: request,
            timeout: 60
        )
    }

    public func mindPalace() async -> Truthful<MindPalaceSnapshot> {
        await fetch(
            MindPalaceSnapshot.self,
            path: "/api/exocortex/v1/mind-palace",
            timeout: 20
        )
    }

    public func mindPalaceRooms() async -> Truthful<[MindPalaceRoom]> {
        await fetch(
            [MindPalaceRoom].self,
            path: "/api/exocortex/v1/mind-palace/rooms",
            timeout: 20
        )
    }

    public func spatialDesk() async -> Truthful<SpatialDeskSnapshot> {
        await fetch(
            SpatialDeskSnapshot.self,
            path: "/api/exocortex/v1/mind-palace/desk",
            timeout: 20
        )
    }

    public func nextBestPlace() async -> Truthful<NextBestPlaceDecision> {
        await fetch(
            NextBestPlaceDecision.self,
            path: "/api/exocortex/v1/mind-palace/next-best-place",
            timeout: 20
        )
    }

    public func spatialActionMenu() async -> Truthful<SpatialActionMenu> {
        await fetch(
            SpatialActionMenu.self,
            path: "/api/exocortex/v1/mind-palace/action-menu",
            timeout: 20
        )
    }

    public func createConversationPortal(_ request: CreateConversationPortalRequest) async -> Truthful<ConversationPortal> {
        await postEncoded(
            ConversationPortal.self,
            path: "/api/exocortex/v1/conversation-portals",
            body: request,
            timeout: 20
        )
    }

    public func promoteConversationPortal(
        portalId: String,
        request: PromoteConversationPortalRequest
    ) async -> Truthful<PromotedConversationClip> {
        await postEncoded(
            PromotedConversationClip.self,
            path: "/api/exocortex/v1/conversation-portals/\(Self.pathComponent(portalId))/promote",
            body: request,
            timeout: 60
        )
    }

    public func focusCoachStatus() async -> Truthful<FocusCoachState> {
        await fetch(
            FocusCoachState.self,
            path: "/api/exocortex/v1/focus-coach/status",
            timeout: 20
        )
    }

    public func recordFocusCoachEvent(_ request: FocusCoachEventRequest) async -> Truthful<FocusCoachState> {
        await postEncoded(
            FocusCoachState.self,
            path: "/api/exocortex/v1/focus-coach/events",
            body: request,
            timeout: 20
        )
    }

    public func memoryCandidates(limit: Int = 20) async -> Truthful<MemoryCandidateListResponse> {
        await fetch(
            MemoryCandidateListResponse.self,
            path: "/api/exocortex/v1/memory/candidates?limit=\(max(1, min(limit, 100)))",
            timeout: 20
        )
    }

    public func memoryGovernanceStatus() async -> Truthful<MemoryGovernanceStatus> {
        await fetch(
            MemoryGovernanceStatus.self,
            path: "/api/exocortex/v1/memory/governance/status",
            timeout: 20
        )
    }

    public func memoryContradictions(limit: Int = 20) async -> Truthful<MemoryContradictionListResponse> {
        await fetch(
            MemoryContradictionListResponse.self,
            path: "/api/exocortex/v1/memory/contradictions?limit=\(max(1, min(limit, 100)))",
            timeout: 20
        )
    }

    public func graphRagQuery(
        query: String,
        scope: String? = nil,
        maxItems: Int = 5,
        mode: String = "hypermemory_multivector"
    ) async -> Truthful<GraphRagQueryResponse> {
        var body: [String: any Sendable] = [
            "query": query,
            "max_items": maxItems,
            "mode": mode
        ]
        if let scope, !scope.isEmpty {
            body["scope"] = scope
        }
        return await post(
            GraphRagQueryResponse.self,
            path: "/api/exocortex/v1/graphrag/query",
            body: body,
            timeout: 60
        )
    }

    public func assistedImportBatch(
        _ request: AssistedImportBatchRequest
    ) async -> Truthful<AssistedImportBatchResult> {
        await postEncoded(
            AssistedImportBatchResult.self,
            // O Cloudflare libera /api/mobile/* e bloqueia /api/exocortex/* (401 de corpo
            // vazio, antes de chegar ao servidor). Como o gateway público é o primeiro
            // que o app tenta, a importação nunca chegava — e cada falha ia para o
            // outbox. O cockpit serve o MESMO handler nos dois caminhos.
            path: "/api/mobile/v1/memory/assisted-import",
            body: request,
            timeout: 120
        )
    }

    /// Flush one queued offline companion turn to the cockpit's memory-spine ingest endpoint.
    /// Mirrors assistedImportBatch — postEncoded handles base URLs + auth + the {data} envelope.
    public func ingestTurn(
        _ request: IngestTurnRequest
    ) async -> Truthful<IngestTurnResult> {
        await postEncoded(
            IngestTurnResult.self,
            path: "/api/mobile/v1/ingest",
            body: request,
            timeout: 30
        )
    }

    public func captureSessionStart(
        _ request: CaptureSessionStartRequest
    ) async -> Truthful<CaptureSession> {
        await postEncoded(
            CaptureSession.self,
            path: "/api/exocortex/v1/capture/sessions",
            body: request,
            timeout: 30
        )
    }

    public func captureSessionStatus(
        sessionId: String
    ) async -> Truthful<CaptureSession> {
        await fetch(
            CaptureSession.self,
            path: "/api/exocortex/v1/capture/sessions/\(sessionId)",
            timeout: 20
        )
    }

    public func captureSessionEvent(
        sessionId: String,
        request: CaptureSessionEventRequest
    ) async -> Truthful<CaptureSessionEvent> {
        await postEncoded(
            CaptureSessionEvent.self,
            path: "/api/exocortex/v1/capture/sessions/\(sessionId)/events",
            body: request,
            timeout: 30
        )
    }

    public func visualEvidenceArtifact(
        _ request: VisualEvidenceArtifactRequest
    ) async -> Truthful<VisualEvidenceArtifact> {
        await postEncoded(
            VisualEvidenceArtifact.self,
            path: "/api/exocortex/v1/capture/visual/artifacts",
            body: request,
            timeout: 60
        )
    }

    public func visualEvidenceAnalyze(
        _ request: VisualEvidenceAnalyzeRequest
    ) async -> Truthful<VisualEvidenceAnalysis> {
        await postEncoded(
            VisualEvidenceAnalysis.self,
            path: "/api/exocortex/v1/capture/visual/analyze",
            body: request,
            timeout: 90
        )
    }

    public func captureReview(
        _ request: CaptureReviewRequest
    ) async -> Truthful<CaptureReviewResult> {
        await postEncoded(
            CaptureReviewResult.self,
            path: "/api/exocortex/v1/capture/review",
            body: request,
            timeout: 60
        )
    }

    public func startSounioPaperRun(
        paperId: String? = nil,
        title: String? = nil,
        dryRun: Bool = false
    ) async -> Truthful<PaperRun> {
        var body: [String: any Sendable] = [
            "surface": "beagle-apple",
            "principal": "beagle-app",
            "dry_run": dryRun
        ]
        if let paperId, !paperId.isEmpty {
            body["paper_id"] = paperId
        }
        if let title, !title.isEmpty {
            body["title"] = title
        }
        return await post(
            PaperRun.self,
            path: "/api/exocortex/v1/sounio/paperruns",
            body: body,
            timeout: 120
        )
    }

    public func checkSounioClaim(_ claim: SounioClaimInput) async -> Truthful<SounioClaimCheckResponse> {
        await postEncoded(
            SounioClaimCheckResponse.self,
            path: "/api/exocortex/v1/sounio/claims/check",
            body: SounioClaimCheckRequest(claim: claim),
            timeout: 30
        )
    }

    public func typeSounioMoment(_ request: SounioMomentTypeRequest) async -> Truthful<SounioMoment> {
        await postEncoded(
            SounioMoment.self,
            path: "/api/exocortex/v1/sounio/moments/type",
            body: request,
            timeout: 30
        )
    }

    public func recentSounioMoments(projectSlug: String = "sounio", limit: Int = 20) async -> Truthful<SounioMomentListResponse> {
        let slug = projectSlug.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? projectSlug
        return await fetch(
            SounioMomentListResponse.self,
            path: "/api/exocortex/v1/sounio/moments/recent?project_slug=\(slug)&limit=\(limit)",
            timeout: 30
        )
    }

    public func reviewSounioMoment(
        momentId: String,
        decision: String,
        rationale: String? = nil,
        evidenceRefs: [String] = [],
        reviewState: String? = nil,
        provenance: ExocortexJSONValue? = .object(["source": .string("beagle-apple")])
    ) async -> Truthful<SounioMoment> {
        let body = SounioMomentReviewRequest(
            reviewer: "demetrios",
            decision: decision,
            rationale: rationale,
            evidenceRefs: evidenceRefs,
            reviewState: reviewState,
            provenance: provenance
        )
        let encodedId = momentId.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? momentId
        return await postEncoded(
            SounioMoment.self,
            path: "/api/exocortex/v1/sounio/moments/\(encodedId)/review",
            body: body,
            timeout: 30
        )
    }

    public func sounioWorkdayStatus(projectSlug: String = "sounio", limit: Int = 20) async -> Truthful<SounioWorkdaySnapshot> {
        let slug = projectSlug.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? projectSlug
        return await fetch(
            SounioWorkdaySnapshot.self,
            path: "/api/exocortex/v1/sounio/workday/status?project_slug=\(slug)&limit=\(limit)",
            timeout: 30
        )
    }

    public func sounioPaperRunStatus(_ paperRunId: String) async -> Truthful<PaperRun> {
        await fetch(
            PaperRun.self,
            path: "/api/exocortex/v1/sounio/paperruns/\(paperRunId)",
            timeout: 30
        )
    }

    public func approveSounioPaperRunStep(
        paperRunId: String,
        stepId: String,
        decision: String = "approved",
        rationale: String? = nil
    ) async -> Truthful<PaperRun> {
        var body: [String: any Sendable] = [
            "step_id": stepId,
            "decision": decision,
            "reviewer": "demetrios"
        ]
        if let rationale, !rationale.isEmpty {
            body["rationale"] = rationale
        }
        return await post(
            PaperRun.self,
            path: "/api/exocortex/v1/sounio/paperruns/\(paperRunId)/approve-step",
            body: body,
            timeout: 30
        )
    }

    public func addSounioClaim(
        paperRunId: String,
        claim: SounioClaimInput,
        principal: String = "beagle-app",
        surface: String = "beagle-apple-paper-workbench"
    ) async -> Truthful<SounioClaim> {
        let body = AddSounioClaimRequest(
            claim: claim,
            principal: principal,
            surface: surface
        )
        return await postEncoded(
            SounioClaim.self,
            path: "/api/exocortex/v1/sounio/paperruns/\(paperRunId)/claims",
            body: body,
            timeout: 30
        )
    }

    public func reviewSounioClaim(
        paperRunId: String,
        claimId: String,
        decision: String,
        rationale: String? = nil,
        evidenceRefs: [String] = [],
        epistemicStatus: String? = nil,
        publicationReadiness: String? = nil,
        provenance: ExocortexJSONValue? = .object(["source": .string("beagle-apple")])
    ) async -> Truthful<SounioClaim> {
        let body = ReviewSounioClaimRequest(
            reviewer: "demetrios",
            decision: decision,
            rationale: rationale,
            evidenceRefs: evidenceRefs,
            epistemicStatus: epistemicStatus,
            publicationReadiness: publicationReadiness,
            provenance: provenance
        )
        return await postEncoded(
            SounioClaim.self,
            path: "/api/exocortex/v1/sounio/paperruns/\(paperRunId)/claims/\(claimId)/review",
            body: body,
            timeout: 30
        )
    }

    public func sounioPaperRunTheatre(_ paperRunId: String) async -> Truthful<PaperRunTheatreSnapshot> {
        await fetch(
            PaperRunTheatreSnapshot.self,
            path: "/api/exocortex/v1/sounio/paperruns/\(paperRunId)/theatre",
            timeout: 30
        )
    }

    public func sounioPaperRunPublicDigest(_ paperRunId: String) async -> Truthful<PublicDigestArtifact> {
        await fetch(
            PublicDigestArtifact.self,
            path: "/api/exocortex/v1/sounio/paperruns/\(paperRunId)/public-digest",
            timeout: 30
        )
    }

    public func sounioPaperRunArtifacts(_ paperRunId: String) async -> Truthful<PaperRunArtifactsResponse> {
        await fetch(
            PaperRunArtifactsResponse.self,
            path: "/api/exocortex/v1/sounio/paperruns/\(paperRunId)/artifacts",
            timeout: 30
        )
    }

    public func sounioTrace(paperRunId: String? = nil, limit: Int = 25) async -> Truthful<SounioTraceListResponse> {
        var path = "/api/exocortex/v1/sounio/trace?limit=\(limit)"
        if let paperRunId, !paperRunId.isEmpty {
            path += "&paper_run_id=\(paperRunId)"
        }
        return await fetch(SounioTraceListResponse.self, path: path, timeout: 30)
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
        discussionProfile: DiscussionProfile = .cluster,
        flowState: String? = nil,
        physioPolicy: PhysioConversationPolicy? = nil,
        lastContactAt: Date? = nil,
        history: [[String: String]] = [],
        // Live body + sky for the server's `## Agora` block — the exact values the strip/aura
        // show. All optional → backward compatible (older server just ignores them).
        hrvMs: Double? = nil,
        voiceWpm: Double? = nil,
        voicePausa: Double? = nil,
        readiness: String? = nil,
        sleepHours: Double? = nil,
        kp: Double? = nil,
        dst: Double? = nil,
        solarWind: Double? = nil,
        bz: Double? = nil,
        voiceModel: String? = nil
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
        var body: [String: any Sendable] = [
            "prompt": effectivePrompt,
            "projectSlug": projectSlug,
            "projectFamily": family.rawValue,
            "publicationScope": scope.rawValue,
            "discussionProfile": discussionProfile.rawValue,
            // The companion's voice = the personal Muse+Voice dyadic ensemble, grounded in
            // the user's living biography + physiome (the "acoplamento diádico").
            "space": "personal",
            // Real-time awareness: the companion's "now" is the user's device clock + zone,
            // so it knows it's late *for him* and (with lastContactAt) how long since they talked.
            "clientTime": ISO8601DateFormatter().string(from: Date()),
            "timezone": TimeZone.current.identifier
        ]
        if let lastContactAt {
            body["lastContactAt"] = ISO8601DateFormatter().string(from: lastContactAt)
        }
        if let flowState, !flowState.isEmpty {
            body["flow_state"] = flowState
        }
        if let physioPolicy {
            body["physio_policy"] = physioPolicy.requestBody
        }
        if !history.isEmpty {
            body["history"] = history
        }
        if let voiceModel, !voiceModel.isEmpty {
            body["voiceModel"] = voiceModel
        }
        Self.addLiveContext(&body, hrvMs: hrvMs, readiness: readiness, sleepHours: sleepHours,
                            kp: kp, dst: dst, solarWind: solarWind, bz: bz,
                            voiceWpm: voiceWpm, voicePausa: voicePausa)

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
            "flow_state": state,
            "source": "apple-watch"
        ])
    }

    // MARK: - Cognitive State

    public func cognitiveState() async -> Truthful<CognitiveState> {
        await fetch(CognitiveState.self, path: "/api/v1/cognitive/state")
    }

    /// Real HERMES-style LLM refinement of a captured thought (Wave 2 capture/refine).
    /// `languageHint` (BCP-47, e.g. "pt-BR") instructs the refiner to keep the
    /// thought in the user's language instead of translating it to English.
    public func refineThought(
        text: String,
        projectSlug: String?,
        source: String,
        languageHint: String? = Locale.current.identifier(.bcp47)
    ) async -> Truthful<ThoughtRefineResponse> {
        await postEncoded(
            ThoughtRefineResponse.self,
            path: "/api/exocortex/v1/capture/refine",
            body: ThoughtRefineRequest(
                rawText: text,
                projectSlug: projectSlug,
                sourceSurface: source,
                languageHint: languageHint,
                preserveLanguage: true
            ),
            timeout: 60
        )
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
        let q = nodeId.map { "?node_id=\($0)" } ?? ""
        return await fetch([Hyperedge].self, path: "/api/hyperedges\(q)")
    }

    public func createHyperedge(label: String, nodeIds: [String]) async -> Truthful<Hyperedge> {
        await post(Hyperedge.self, path: "/api/hyperedges",
                   body: ["label": label, "node_ids": nodeIds, "directed": false])
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
        discussionProfile: DiscussionProfile = .cluster,
        flowState: String? = nil,
        physioPolicy: PhysioConversationPolicy? = nil,
        lastContactAt: Date? = nil,
        history: [[String: String]] = [],
        hrvMs: Double? = nil,
        voiceWpm: Double? = nil,
        voicePausa: Double? = nil,
        readiness: String? = nil,
        sleepHours: Double? = nil,
        kp: Double? = nil,
        dst: Double? = nil,
        solarWind: Double? = nil,
        bz: Double? = nil,
        voiceModel: String? = nil
    ) async -> Truthful<ChatResponse> {
        await llmComplete(
            prompt: prompt,
            system: system,
            projectSlug: projectSlug,
            projectFamily: projectFamily,
            publicationScope: publicationScope,
            discussionProfile: discussionProfile,
            flowState: flowState,
            physioPolicy: physioPolicy,
            lastContactAt: lastContactAt,
            history: history,
            hrvMs: hrvMs, voiceWpm: voiceWpm, voicePausa: voicePausa,
            readiness: readiness, sleepHours: sleepHours,
            kp: kp, dst: dst, solarWind: solarWind, bz: bz,
            voiceModel: voiceModel
        )
    }

    /// Inject the live body + sky fields into a chat request body (shared by llmComplete +
    /// the streaming path). Only present values are sent — the server's `## Agora` fills in
    /// the rest from its own fetch.
    /// Sinal de TOM (`voiceWpm`/`voicePausa`): derivado no aparelho quando ele falou
    /// em vez de digitar. São dois números; o áudio é descartado no iPhone e nunca
    /// sai. Ausentes quando ele digitou — ausência aqui significa "não falei", não
    /// "falei normal".
    static func addLiveContext(_ body: inout [String: any Sendable], hrvMs: Double?, readiness: String?,
                               sleepHours: Double?, kp: Double?, dst: Double?, solarWind: Double?, bz: Double?,
                               voiceWpm: Double? = nil, voicePausa: Double? = nil) {
        if let hrvMs { body["hrv_ms"] = hrvMs }
        if let readiness, !readiness.isEmpty { body["readiness"] = readiness }
        if let sleepHours { body["sleep_hours"] = sleepHours }
        if let kp { body["kp"] = kp }
        if let dst { body["dst"] = dst }
        if let solarWind { body["solar_wind"] = solarWind }
        if let bz { body["bz"] = bz }
        if let voiceWpm { body["voice_speech_rate_wpm"] = voiceWpm }
        if let voicePausa { body["voice_pause_ratio"] = voicePausa }
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
                request.setValue(Self.cockpitMobileToken, forHTTPHeaderField: "x-cockpit-token")
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

    // MARK: - Companion grounding (cache offline)

    /// O pacote de identidade dele, montado pelo cluster: persona, biografia viva,
    /// Sounio, continuidade. ~18 KB de texto.
    public struct CompanionGrounding: Decodable, Sendable {
        public let system: String
        public let bytes: Int?
    }

    /// Busca o grounding para o app guardar em disco. Existe por um motivo concreto:
    /// dentro do hospital a rede cai, e sem isto o modelo no aparelho responde como um
    /// estranho educado usando o nome dele — justamente quando ele está mais sozinho.
    public func fetchCompanionGrounding() async -> Truthful<CompanionGrounding> {
        let cockpitURLs = [
            URL(string: "https://beagle.chiuratto.ai")!,
            URL(string: "http://sounio-cockpit.tail21cbc4.ts.net")!,
            URL(string: "http://100.107.208.198")!,
            URL(string: "http://project-cockpit.beagle.svc.cluster.local")!
        ]
        let body: [String: any Sendable] = ["space": "personal", "prompt": "grounding"]
        var lastError = "grounding gateway unreachable"
        let debugLabel = "[CompanionGrounding] POST /api/mobile/v1/companion/grounding"

        for base in cockpitURLs {
            guard let url = URL(string: "/api/mobile/v1/companion/grounding", relativeTo: base) else { continue }
            do {
                var request = URLRequest(url: url)
                request.httpMethod = "POST"
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                request.setValue(Self.cockpitMobileToken, forHTTPHeaderField: "x-cockpit-token")
                request.timeoutInterval = 60
                request.httpBody = try JSONSerialization.data(withJSONObject: body)

                let (data, response) = try await session.data(for: request)
                guard let http = response as? HTTPURLResponse,
                      (200..<300).contains(http.statusCode) else {
                    let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
                    lastError = "HTTP \(statusCode)"
                    print("[BeagleClient] \(debugLabel) HTTP \(statusCode)")
                    continue
                }
                let envelope = try decoder.decode(MobileEnvelope<CompanionGrounding>.self, from: data)
                guard envelope.ok != false, let payload = envelope.data else {
                    lastError = envelope.error?.message ?? "grounding returned no data"
                    continue
                }
                print("[BeagleClient] \(debugLabel) ok — \(payload.bytes ?? payload.system.count) bytes")
                return Truthful(value: payload, mode: .observed, observedAt: .now, source: url.host, error: nil)
            } catch {
                lastError = error.localizedDescription
                continue
            }
        }
        print("[BeagleClient] \(debugLabel) all URLs failed: \(lastError)")
        return .staleError(lastError, source: "cockpit-mobile-gateway")
    }

    // MARK: - Streaming chat (SSE: /api/mobile/v1/chat/stream)
    //
    // Streams tokens from the cockpit's SSE endpoint as they arrive — the user sees
    // the companion typing live instead of a frozen 7-9s wait. Server writes
    // `data: {"token":"..."}\n\n` per token and a final `data: {"done":true,...}` event.
    // The returned AsyncThrowingStream yields one String per token.
    public nonisolated func chatStream(
        prompt: String,
        system: String? = nil,
        projectSlug: String = "sounio",
        projectFamily: ProjectFamily? = nil,
        publicationScope: PublicationScope? = nil,
        discussionProfile: DiscussionProfile = .cluster,
        flowState: String? = nil,
        physioPolicy: PhysioConversationPolicy? = nil,
        lastContactAt: Date? = nil,
        history: [[String: String]] = [],
        hrvMs: Double? = nil,
        voiceWpm: Double? = nil,
        voicePausa: Double? = nil,
        readiness: String? = nil,
        sleepHours: Double? = nil,
        kp: Double? = nil,
        dst: Double? = nil,
        solarWind: Double? = nil,
        bz: Double? = nil,
        voiceModel: String? = nil,
        deepThink: Bool = false,
        // Presence channel (2026-08-02-companion-presence-design.md §5): the server writes
        // {"event":"presence"|"phase", ...} at t≈0 and while it waits. Optional callback
        // instead of widening the stream element type, so the other call-site
        // (DailySynthesisView) keeps compiling untouched. Invoked off the main actor.
        onPhase: (@Sendable (String, String) -> Void)? = nil
    ) -> AsyncThrowingStream<String, Error> {
        let effectivePrompt: String
        if let system, !system.isEmpty {
            effectivePrompt = "System instruction:\n\(system)\n\nUser prompt:\n\(prompt)"
        } else {
            effectivePrompt = prompt
        }
        let family = projectFamily ?? .fromProjectSlug(projectSlug)
        let scope = publicationScope ?? .forProjectFamily(family)
        var body: [String: any Sendable] = [
            "prompt": effectivePrompt,
            "projectSlug": projectSlug,
            "projectFamily": family.rawValue,
            "publicationScope": scope.rawValue,
            "discussionProfile": discussionProfile.rawValue,
            "space": "personal",
            "clientTime": ISO8601DateFormatter().string(from: Date()),
            "timezone": TimeZone.current.identifier
        ]
        if let lastContactAt {
            body["lastContactAt"] = ISO8601DateFormatter().string(from: lastContactAt)
        }
        if let flowState, !flowState.isEmpty {
            body["flow_state"] = flowState
        }
        if let physioPolicy {
            body["physio_policy"] = physioPolicy.requestBody
        }
        if !history.isEmpty {
            body["history"] = history
        }
        // Depth gear: a non-default voiceModel asks the personal-voice path for a stronger model
        // (e.g. "Pensar" → glm-5.2). nil → server default voice ("Rápido").
        if let voiceModel, !voiceModel.isEmpty {
            body["voiceModel"] = voiceModel
        }
        // Deep-think gear: asks the server to route this turn through the grounded/agentic
        // path (web + cluster + fs tools) instead of the fast conversational default.
        if deepThink {
            body["deepThink"] = true
        }
        Self.addLiveContext(&body, hrvMs: hrvMs, readiness: readiness, sleepHours: sleepHours,
                            kp: kp, dst: dst, solarWind: solarWind, bz: bz,
                            voiceWpm: voiceWpm, voicePausa: voicePausa)

        let cockpitURLs: [URL] = [
            URL(string: "https://beagle.chiuratto.ai")!,
            URL(string: "http://sounio-cockpit.tail21cbc4.ts.net")!,
            URL(string: "http://100.107.208.198")!,
            URL(string: "http://project-cockpit.beagle.svc.cluster.local")!
        ]

        // Use an ephemeral session for the stream (long-lived, SSE) — avoids needing
        // to reach into actor-isolated self.session from this nonisolated method.
        let cfg = URLSessionConfiguration.ephemeral
        cfg.timeoutIntervalForRequest = 120
        cfg.timeoutIntervalForResource = 600
        cfg.httpAdditionalHeaders = ["User-Agent": "BeagleCockpit/1.0 (iOS exocortex stream)"]
        let session = URLSession(configuration: cfg)
        let payload = (try? JSONSerialization.data(withJSONObject: body)) ?? Data()

        return AsyncThrowingStream { continuation in
            let task = Task {
                var lastError: Error? = nil
                for base in cockpitURLs {
                    guard let url = URL(string: "/api/mobile/v1/chat/stream", relativeTo: base) else { continue }
                    var request = URLRequest(url: url)
                    request.httpMethod = "POST"
                    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                    request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
                    request.setValue(Self.cockpitMobileToken, forHTTPHeaderField: "x-cockpit-token")
                    request.timeoutInterval = 120
                    request.httpBody = payload
                    do {
                        let (bytes, response) = try await session.bytes(for: request)
                        guard let http = response as? HTTPURLResponse,
                              (200..<300).contains(http.statusCode) else {
                            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
                            lastError = NSError(domain: "BeagleChatStream", code: status,
                                userInfo: [NSLocalizedDescriptionKey: "HTTP \(status)"])
                            continue
                        }
                        // Parse SSE: lines starting with "data: <json>", events split by blank line.
                        for try await line in bytes.lines {
                            if Task.isCancelled { break }
                            guard line.hasPrefix("data:") else { continue }
                            let json = line.dropFirst(5).trimmingCharacters(in: .whitespaces)
                            guard let data = json.data(using: .utf8),
                                  let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                                continue
                            }
                            // ORDER IS CONTRACT: done → error → event → token. `done` carries a
                            // `presence` field of its own (the FLOOR layer) — checking presence
                            // first would swallow every degraded `done` and hang the stream.
                            if obj["done"] as? Bool == true {
                                if let err = obj["error"] as? String {
                                    continuation.finish(throwing: NSError(domain: "BeagleChatStream", code: -1,
                                        userInfo: [NSLocalizedDescriptionKey: err]))
                                    return
                                }
                                continuation.finish()
                                return
                            } else if let err = obj["error"] as? String {
                                continuation.finish(throwing: NSError(domain: "BeagleChatStream", code: -1,
                                    userInfo: [NSLocalizedDescriptionKey: err]))
                                return
                            } else if let event = obj["event"] as? String,
                                      event == "presence" || event == "phase" {
                                let phase = obj["phase"] as? String ?? event
                                let text = obj["text"] as? String ?? ""
                                onPhase?(phase, text)
                            } else if let token = obj["token"] as? String, !token.isEmpty {
                                continuation.yield(token)
                            }
                        }
                        continuation.finish()
                        return
                    } catch {
                        lastError = error
                        continue
                    }
                }
                continuation.finish(throwing: lastError ?? NSError(domain: "BeagleChatStream", code: -1,
                    userInfo: [NSLocalizedDescriptionKey: "all cockpit URLs failed"]))
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    // MARK: - Space weather (Kp/F10.7/solar wind for AuroraPresence)

    /// Fetch the latest geomagnetic snapshot from physiome (NOAA SWPC poller writes
    /// it every 2h). Returns nil on any failure — caller falls back to a calm default
    /// so the aurora keeps breathing even when offline.
    public func fetchLatestSpaceWeather() async -> SpaceWeatherStore.Snapshot? {
        let bases: [URL] = [
            URL(string: "https://beagle.chiuratto.ai")!,
            URL(string: "http://physiome-ingest.beagle.svc.cluster.local:8080")!
        ]
        print("[SpaceWeather/Client] ensureAuth…")
        let authed = await ensureAuth()
        print("[SpaceWeather/Client] auth=\(authed) trying \(bases.count) bases")
        var request = URLRequest(url: bases[0])
        for base in bases {
            guard let url = URL(string: "/api/physiome/space-weather/latest", relativeTo: base) else { continue }
            request = URLRequest(url: url)
            request.httpMethod = "GET"
            request.timeoutInterval = 15
            request.setValue("application/json", forHTTPHeaderField: "Accept")
            applyAuth(&request)
            do {
                let (data, response) = try await session.data(for: request)
                let code = (response as? HTTPURLResponse)?.statusCode ?? 0
                print("[SpaceWeather/Client] \(base.host ?? "?") → HTTP \(code) (\(data.count)B)")
                guard (200..<300).contains(code) else { continue }
                struct Resp: Decodable { let ok: Bool; let latest: Latest? ; struct Latest: Decodable { let ts: String; let kp: Double; let dst: Double?; let f107: Double; let solar_wind_speed: Double?; let bz: Double?; let hp30: Double?; let ap30: Double?; let hp60: Double?; let cosmic_ray_oulu: Double?; let schumann_f1: Double?; let schumann_f2: Double?; let schumann_f3: Double?; let xray_flux: Double?; let proton_flux: Double?; let aurora_power: Double?; let sym_h: Double?; let ae_index: Double?; let source: String } }
                let resp = try decoder.decode(Resp.self, from: data)
                guard let l = resp.latest else { return nil }
                let f = ISO8601DateFormatter(); f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
                let ts = f.date(from: l.ts) ?? ISO8601DateFormatter().date(from: l.ts) ?? Date()
                return SpaceWeatherStore.Snapshot(ts: ts, kp: l.kp, dst: l.dst, f107: l.f107, solarWindSpeed: l.solar_wind_speed, bz: l.bz, hp30: l.hp30, ap30: l.ap30, hp60: l.hp60, cosmicRayOulu: l.cosmic_ray_oulu, schumannF1: l.schumann_f1, schumannF2: l.schumann_f2, schumannF3: l.schumann_f3, xrayFlux: l.xray_flux, protonFlux: l.proton_flux, auroraPower: l.aurora_power, symH: l.sym_h, aeIndex: l.ae_index, source: l.source)
            } catch {
                print("[SpaceWeather/Client] \(base.host ?? "?") error: \(error.localizedDescription)")
                continue
            }
        }
        return nil
    }

    /// Recent sky + ambient + HRV series for the Agora detail screen's trends. Cockpit route
    /// (/api/mobile/v1/agora-history). Best-effort → nil on any failure.
    public func agoraHistory(hours: Int = 48) async -> AgoraHistory? {
        let cockpitURLs = [
            URL(string: "https://beagle.chiuratto.ai")!,
            URL(string: "http://sounio-cockpit.tail21cbc4.ts.net")!,
            URL(string: "http://100.107.208.198")!,
            URL(string: "http://project-cockpit.beagle.svc.cluster.local")!
        ]
        for base in cockpitURLs {
            guard let url = URL(string: "/api/mobile/v1/agora-history?hours=\(hours)", relativeTo: base) else { continue }
            do {
                var request = URLRequest(url: url)
                request.timeoutInterval = 20
                request.setValue("application/json", forHTTPHeaderField: "Accept")
                request.setValue(Self.cockpitMobileToken, forHTTPHeaderField: "x-cockpit-token")
                let (data, response) = try await session.data(for: request)
                guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else { continue }
                return try decoder.decode(AgoraHistory.self, from: data)
            } catch {
                print("[AgoraHistory] \(base.host ?? "?") error: \(error.localizedDescription)")
                continue
            }
        }
        return nil
    }

    /// Forecast (the forward half of the Agora charts): hourly temp/UV/AQI + the NOAA
    /// planetary-K 3-day forecast. The server defaults to the last uploaded location, so no
    /// lat/lon is needed. Public endpoint (no auth). Best-effort → nil.
    public func agoraForecast() async -> AgoraForecast? {
        let bases = [
            URL(string: "https://beagle.chiuratto.ai")!,
            URL(string: "http://physiome-ingest.beagle.svc.cluster.local:8080")!
        ]
        for base in bases {
            guard let url = URL(string: "/api/physiome/forecast", relativeTo: base) else { continue }
            do {
                var request = URLRequest(url: url)
                request.timeoutInterval = 20
                request.setValue("application/json", forHTTPHeaderField: "Accept")
                let (data, response) = try await session.data(for: request)
                guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else { continue }
                return try decoder.decode(AgoraForecast.self, from: data)
            } catch {
                print("[AgoraForecast] \(base.host ?? "?") error: \(error.localizedDescription)")
                continue
            }
        }
        return nil
    }

    /// Body×sky×ambient correlations (Spearman + lag scan) for the data screen. Reads through the
    /// cockpit (the phone can't reach physiome's ClusterIP / hold its token). Best-effort → nil.
    public func correlations(days: Int = 30) async -> PhysioCorrelations? {
        let cockpitURLs = [
            URL(string: "https://beagle.chiuratto.ai")!,
            URL(string: "http://sounio-cockpit.tail21cbc4.ts.net")!,
            URL(string: "http://100.107.208.198")!,
            URL(string: "http://project-cockpit.beagle.svc.cluster.local")!
        ]
        for base in cockpitURLs {
            guard let url = URL(string: "/api/mobile/v1/correlations?days=\(days)", relativeTo: base) else { continue }
            do {
                var request = URLRequest(url: url)
                request.timeoutInterval = 20
                request.setValue("application/json", forHTTPHeaderField: "Accept")
                request.setValue(Self.cockpitMobileToken, forHTTPHeaderField: "x-cockpit-token")
                let (data, response) = try await session.data(for: request)
                guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else { continue }
                return try decoder.decode(PhysioCorrelations.self, from: data)
            } catch {
                print("[Correlations] \(base.host ?? "?") error: \(error.localizedDescription)")
                continue
            }
        }
        return nil
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
        await post(QuantumReasoningResult.self, path: "/dev/quantum-reasoning", body: [
            "hypotheses": hypotheses,
            "threshold": threshold,
            "interference_strength": interferenceStrength,
            "probabilistic": probabilistic,
            "apply_decoherence": applyDecoherence
        ] as [String: any Sendable], timeout: 90)
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
        await post(CausalIntervention.self, path: "/dev/causal/intervention", body: [
            "graph_id": graphId, "intervention": intervention
        ] as [String: any Sendable], timeout: 90)
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
        await post(AdversarialResult.self, path: "/dev/adversarial-compete",
                   body: ["query": query], timeout: 180)
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
        await post(WorldModelCounterfactual.self, path: "/api/worldmodel/counterfactual",
                   body: ["query": query], timeout: 90)
    }

    // MARK: - Extended (Fractal, PCS, Serendipity)

    public func fractalGrow(seed: String) async -> Truthful<FractalGrowResult> {
        // Backend field: root_prompt (verified 2026-04-15)
        await post(FractalGrowResult.self, path: "/api/fractal/recurse", body: ["root_prompt": seed], timeout: 90)
    }

    public func pcsReason(query: String) async -> Truthful<PCSReasonResult> {
        await post(PCSReasonResult.self, path: "/api/pcs/reason", body: ["symptoms": [query]], timeout: 60)
    }

    public func serendipityDiscover(
        query: String,
        recallContext: String? = nil
    ) async -> Truthful<SerendipityResult> {
        // Real beagle-serendipity engine (Wave 1/3). Slow (LLM-backed) — generous timeout.
        // When `recallContext` is supplied the engine reuses the caller's already-loaded
        // recall context instead of re-running its own retrieval pass.
        var body: [String: any Sendable] = ["focus_project": query]
        if let recallContext, !recallContext.isEmpty {
            body["recall_context"] = recallContext
            body["reuse_context"] = true
        }
        return await post(SerendipityResult.self, path: "/api/serendipity/discover",
                          body: body, timeout: 120)
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

// MARK: - Triad streaming (SSE)

/// One event from the streaming debate endpoint.
public enum TriadStreamEvent: Sendable {
    /// Incremental text from an agent (agent name when the frame identifies one).
    case delta(agent: String?, text: String)
    /// Final consolidated review; the stream ends after this.
    case final(TriadResult)
    /// Stream-level failure (auth/network/unreachable).
    case error(String)
}

/// A single SSE delta frame from `/dev/debate?stream=true`.
struct TriadStreamDelta: Decodable, Sendable {
    let agent: String?
    let text: String?
    let content: String?
}

// MARK: - Wave 2: capture/refine (real LLM thought refinement)

public struct ThoughtRefineResponse: Codable, Sendable {
    public let refinedText: String
    public let model: String?
    public let tier: String?
    enum CodingKeys: String, CodingKey {
        case refinedText = "refined_text"
        case model
        case tier
    }
}

struct ThoughtRefineRequest: Encodable, Sendable {
    let rawText: String
    let projectSlug: String?
    let sourceSurface: String?
    /// BCP-47 hint (e.g. "pt-BR") so refinement keeps the user's language.
    let languageHint: String?
    /// Explicit flag instructing the backend never to translate the refined text.
    let preserveLanguage: Bool
    enum CodingKeys: String, CodingKey {
        case rawText = "raw_text"
        case projectSlug = "project_slug"
        case sourceSurface = "source_surface"
        case languageHint = "language_hint"
        case preserveLanguage = "preserve_language"
    }
}
