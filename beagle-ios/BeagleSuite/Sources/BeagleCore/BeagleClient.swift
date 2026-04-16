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
        let result = await fetch([String: Bool].self, path: "/health")
        return result.mode == .observed
    }

    // MARK: - Core fetch (GET)

    public func fetch<T: Decodable & Sendable>(
        _ type: T.Type,
        path: String,
        timeout: TimeInterval = 15
    ) async -> Truthful<T> {
        var lastError = "beagle-server unreachable"
        let debugLabel = "[\(type)] GET \(path)"
        print("[BeagleClient] \(debugLabel) starting...")

        for base in baseURLs {
            guard let url = URL(string: path, relativeTo: base) else {
                print("[BeagleClient] \(debugLabel) failed to construct URL with base: \(base)")
                continue
            }
            do {
                var request = URLRequest(url: url)
                request.timeoutInterval = timeout
                applyAuth(&request)
                print("[BeagleClient] \(debugLabel) requesting: \(url)")
                let (data, response) = try await session.data(for: request)

                guard let http = response as? HTTPURLResponse,
                      (200..<300).contains(http.statusCode) else {
                    let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
                    lastError = "HTTP \(statusCode)"
                    print("[BeagleClient] \(debugLabel) ❌ HTTP \(statusCode)")
                    continue
                }

                let decoded = try decoder.decode(T.self, from: data)
                print("[BeagleClient] \(debugLabel) ✅ success")
                return .observed(decoded, source: url.host)
            } catch {
                lastError = error.localizedDescription
                print("[BeagleClient] \(debugLabel) ❌ error: \(error.localizedDescription)")
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
        timeout: TimeInterval = 120
    ) async -> Truthful<T> {
        var lastError = "beagle-server unreachable"
        let debugLabel = "[\(type)] POST \(path)"
        print("[BeagleClient] \(debugLabel) starting...")

        for base in baseURLs {
            guard let url = URL(string: path, relativeTo: base) else {
                print("[BeagleClient] \(debugLabel) failed to construct URL with base: \(base)")
                continue
            }
            do {
                var request = URLRequest(url: url)
                request.httpMethod = "POST"
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                request.timeoutInterval = timeout
                applyAuth(&request)
                request.httpBody = try JSONSerialization.data(withJSONObject: body)

                print("[BeagleClient] \(debugLabel) requesting: \(url)")
                let (data, response) = try await session.data(for: request)

                guard let http = response as? HTTPURLResponse,
                      (200..<300).contains(http.statusCode) else {
                    let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
                    lastError = "HTTP \(statusCode)"
                    print("[BeagleClient] \(debugLabel) ❌ HTTP \(statusCode)")
                    continue
                }

                let decoded = try decoder.decode(T.self, from: data)
                print("[BeagleClient] \(debugLabel) ✅ success")
                return .observed(decoded, source: url.host)
            } catch {
                lastError = error.localizedDescription
                print("[BeagleClient] \(debugLabel) ❌ error: \(error.localizedDescription)")
                continue
            }
        }
        print("[BeagleClient] \(debugLabel) all URLs failed: \(lastError)")
        return .staleError(lastError)
    }

    /// Fetch auth token from cockpit bridge (zero hardcode).
    public func ensureAuth() async {
        guard !tokenFetched else { return }
        print("[BeagleClient] ensureAuth starting...")
        // GET /api/auth/beagle-token from cockpit
        let cockpitURLs = [
            URL(string: "http://sounio-cockpit.tail21cbc4.ts.net")!  // Changed from HTTPS
        ]
        for base in cockpitURLs {
            guard let url = URL(string: "/api/auth/beagle-token", relativeTo: base) else {
                print("[BeagleClient] ensureAuth failed to construct URL")
                continue
            }
            do {
                print("[BeagleClient] ensureAuth requesting: \(url)")
                let (data, response) = try await session.data(for: URLRequest(url: url))
                guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                    let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
                    print("[BeagleClient] ensureAuth ❌ HTTP \(statusCode)")
                    continue
                }
                if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                    consumerToken = json["token"] as? String
                    consumerId = json["consumer"] as? String ?? "beagle-operator"
                    print("[BeagleClient] ensureAuth ✅ token acquired: \(consumerId ?? "unknown")")
                    // Update base URL if provided
                    if let urlStr = json["beagleServerUrl"] as? String, let serverUrl = URL(string: urlStr) {
                        print("[BeagleClient] ensureAuth updating base URL: \(serverUrl)")
                        baseURLs.insert(serverUrl, at: 0)
                    }
                    tokenFetched = true
                    return
                }
            } catch {
                print("[BeagleClient] ensureAuth ❌ error: \(error.localizedDescription)")
                continue
            }
        }
        // Fallback: try without auth (health endpoint works without it)
        print("[BeagleClient] ensureAuth falling back to unauthenticated mode")
        tokenFetched = true
    }

    private func applyAuth(_ request: inout URLRequest) {
        if let consumerId { request.setValue(consumerId, forHTTPHeaderField: "X-Beagle-Consumer") }
        if let consumerToken { request.setValue("Bearer \(consumerToken)", forHTTPHeaderField: "Authorization") }
    }

    // MARK: - Thought Capture

    /// Capture a thought via HERMES system prompt → beagle-server.
    public func captureThought(text: String, source: String = "ios") async -> Truthful<ChatResponse> {
        await post(ChatResponse.self, path: "/dev/chat", body: [
            "prompt": text,
            "system": "You are HERMES: receive a thought fragment, refine into a structured memory. Preserve the original insight. Output only the refined text.",
            "context": ["project": "sounio", "source": source] as [String: String]
        ])
    }

    // MARK: - Triad (adversarial review)

    /// Submit draft for ATHENA/HERMES/ARGOS/Judge review. Timeout 120s.
    public func runTriad(prompt: String) async -> Truthful<TriadResult> {
        await post(TriadResult.self, path: "/dev/debate", body: [
            "prompt": prompt
        ], timeout: 120)
    }

    // MARK: - Science Jobs

    public func startScienceJob(kind: String) async -> Truthful<ScienceJob> {
        await post(ScienceJob.self, path: "/api/jobs/science/start", body: [
            "kind": kind,
            "config": [String: String]() as [String: String]
        ])
    }

    public func scienceJobStatus(jobId: String) async -> Truthful<ScienceJob> {
        await fetch(ScienceJob.self, path: "/api/jobs/science/status/\(jobId)")
    }

    // MARK: - HPC Jobs (Darwin)

    public func submitHPCJob(kind: String, config: [String: String] = [:]) async -> Truthful<HPCJob> {
        await post(HPCJob.self, path: "/api/darwin/hpc/jobs/submit", body: [
            "kind": kind,
            "config": config
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

    public func llmComplete(prompt: String, system: String? = nil) async -> Truthful<ChatResponse> {
        var body: [String: any Sendable] = ["prompt": prompt]
        if let system { body["system"] = system }
        return await post(ChatResponse.self, path: "/api/llm/complete", body: body)
    }

    // MARK: - HRV

    public func postHRV(hrv: Double, state: String) async -> Truthful<HRVResponse> {
        await post(HRVResponse.self, path: "/api/observer/physio", body: [
            "hrv_ms": hrv,
            "state": state,
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
        await post(ChatResponse.self, path: "/api/cognitive/deep-think", body: ["prompt": prompt], timeout: 180)
    }

    // MARK: - Hypergraph

    public func queryHyperedges(nodeId: String? = nil) async -> Truthful<[Hyperedge]> {
        var path = "/api/v1/hyperedges"
        if let nodeId { path += "?node_id=\(nodeId)" }
        return await fetch([Hyperedge].self, path: path)
    }

    public func createHyperedge(label: String, nodeIds: [String]) async -> Truthful<Hyperedge> {
        await post(Hyperedge.self, path: "/api/v1/hyperedges", body: [
            "label": label,
            "node_ids": nodeIds,
            "directed": false
        ])
    }

    // MARK: - Feedback

    public func postFeedback(event: FeedbackEvent) async -> Truthful<FeedbackAck> {
        var body: [String: any Sendable] = [
            "run_id": event.runId,
            "kind": event.kind
        ]
        if let c = event.clarity { body["clarity"] = c }
        if let a = event.adequacy { body["adequacy"] = a }
        if let s = event.safety { body["safety"] = s }
        if let n = event.notes { body["notes"] = n }
        return await post(FeedbackAck.self, path: "/api/v1/feedback", body: body)
    }

    // MARK: - Chat (generic exocortex conversation)

    public func chat(prompt: String, system: String? = nil) async -> Truthful<ChatResponse> {
        var body: [String: any Sendable] = ["prompt": prompt]
        if let system { body["system"] = system }
        return await post(ChatResponse.self, path: "/api/llm/complete", body: body)
    }

    // MARK: - Novelty Endpoints (Void, Fractal, Phi)

    public func startVoidJourney(prompt: String, maxDepth: Int = 3) async -> Truthful<VoidJourney> {
        await post(VoidJourney.self, path: "/dev/void", body: [
            "prompt": prompt,
            "max_depth": maxDepth
        ] as [String: any Sendable])
    }

    public func startFractalTree(prompt: String, maxDepth: Int = 2, branching: Int = 2) async -> Truthful<FractalTree> {
        await post(FractalTree.self, path: "/api/fractal/recurse", body: [
            "prompt": prompt,
            "max_depth": maxDepth,
            "branching_factor": branching
        ] as [String: any Sendable])
    }

    public func measurePhi(prompt: String) async -> Truthful<PhiMeasurement> {
        await post(PhiMeasurement.self, path: "/api/exocortex/process", body: [
            "prompt": prompt
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
        ] as [String: any Sendable], timeout: 120)
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
            "graph_id": graphId,
            "intervention": intervention
        ] as [String: any Sendable], timeout: 60)
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
        await post(AdversarialResult.self, path: "/dev/adversarial-compete", body: ["query": query], timeout: 180)
    }

    public func research(query: String) async -> Truthful<ResearchResult> {
        // Backend field: research_goal (verified 2026-04-15)
        await post(ResearchResult.self, path: "/dev/research", body: ["research_goal": query], timeout: 120)
    }

    public func researchParallel(query: String) async -> Truthful<ParallelResearchResult> {
        await post(ParallelResearchResult.self, path: "/dev/research/parallel", body: ["query": query], timeout: 180)
    }

    public func reasoningPath(source: String, target: String) async -> Truthful<ReasoningPathResult> {
        // Backend expects start_concept / end_concept (verified 2026-04-15)
        await post(ReasoningPathResult.self, path: "/dev/reasoning", body: [
            "start_concept": source, "end_concept": target
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
        await post(WorldModelCounterfactual.self, path: "/worldmodel/counterfactual", body: ["query": query], timeout: 60)
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
        await post(SerendipityResult.self, path: "/api/serendipity/discover", body: [
            "query": query, "focus_project": "sounio"
        ] as [String: any Sendable], timeout: 60)
    }

    public func deepThink(prompt: String, depth: Int = 3) async -> Truthful<ChatResponse> {
        // Backend field: root_prompt (verified 2026-04-15)
        await post(ChatResponse.self, path: "/api/cognitive/deep-think", body: [
            "root_prompt": prompt, "depth": depth
        ] as [String: any Sendable], timeout: 180)
    }
}
