//
//  BeagleClient+Cognition.swift
//  BeagleCore
//
//  Thought capture, Triad/Debate SSE, Science/HPC jobs, Literature, Cognitive State, Go Deeper.
//

import Foundation

extension BeagleClient {

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
                let session = self.session
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
        voiceModel: String? = nil,
        imageBase64: String? = nil,
        imageMimeType: String? = nil
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
        if let imageBase64, !imageBase64.isEmpty {
            body["imageBase64"] = imageBase64
            body["imageMimeType"] = imageMimeType ?? "image/jpeg"
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
