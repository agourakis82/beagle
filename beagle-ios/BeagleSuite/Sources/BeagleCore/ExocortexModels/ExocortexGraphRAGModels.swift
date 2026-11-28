//
//  ExocortexGraphRAGModels.swift
//  BeagleCore
//
//  GraphRAG query evidence, evidence graph, retrieval traces, runtime votes,
//  and Memory Lens / Proof Sheet synthesis contracts.
//

import Foundation

fileprivate extension String {
    var nilIfEmpty: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

fileprivate extension Array {
    func stablePrefix(_ count: Int) -> [Element] {
        Array(prefix(count))
    }
}

public struct GraphRagEvidence: Codable, Equatable, Sendable {
    public let atomId: String
    public let episodeId: String
    public let atomType: String
    public let text: String
    public let score: Double
    public let sourceRefs: [String]
    public let provenance: ExocortexJSONValue?

    enum CodingKeys: String, CodingKey {
        case atomId = "atom_id"
        case episodeId = "episode_id"
        case atomType = "atom_type"
        case text
        case score
        case sourceRefs = "source_refs"
        case provenance
    }
}

public struct GraphRagTemporalContext: Codable, Equatable, Sendable {
    public let newestEvidenceAt: String?
    public let oldestEvidenceAt: String?
    public let matchedEpisodeCount: Int

    enum CodingKeys: String, CodingKey {
        case newestEvidenceAt = "newest_evidence_at"
        case oldestEvidenceAt = "oldest_evidence_at"
        case matchedEpisodeCount = "matched_episode_count"
    }
}

public struct EvidenceGraphNode: Codable, Equatable, Sendable, Identifiable {
    public let id: String
    public let label: String
    public let nodeType: String
    public let score: Double
    public let provenance: ExocortexJSONValue?

    enum CodingKeys: String, CodingKey {
        case id
        case label
        case nodeType = "node_type"
        case score
        case provenance
    }
}

public struct EvidenceGraphEdge: Codable, Equatable, Sendable, Identifiable {
    public var id: String { "\(source)-\(predicate)-\(target)" }
    public let source: String
    public let target: String
    public let predicate: String
    public let confidence: Double
    public let provenance: ExocortexJSONValue?
}

public struct EvidenceGraph: Codable, Equatable, Sendable {
    public let nodes: [EvidenceGraphNode]
    public let edges: [EvidenceGraphEdge]
    public let temporary: Bool
    public let merkleRoot: String

    enum CodingKeys: String, CodingKey {
        case nodes
        case edges
        case temporary
        case merkleRoot = "merkle_root"
    }
}

public struct GraphRagCommunityContext: Codable, Equatable, Sendable {
    public let strategy: String
    public let selectedCommunities: [MemoryCommunity]
    public let degradedReason: String?

    enum CodingKeys: String, CodingKey {
        case strategy
        case selectedCommunities = "selected_communities"
        case degradedReason = "degraded_reason"
    }
}

public struct RetrievalTraceStep: Codable, Equatable, Sendable, Identifiable {
    public var id: String { "\(stage)-\(backend)-\(items)" }
    public let stage: String
    public let backend: String
    public let status: String
    public let items: Int
    public let latencyMs: Double
    public let notes: [String]

    enum CodingKeys: String, CodingKey {
        case stage
        case backend
        case status
        case items
        case latencyMs = "latency_ms"
        case notes
    }
}

public struct RuntimeVote: Codable, Equatable, Sendable, Identifiable {
    public var id: String { "\(runtime)-\(role)" }
    public let runtime: String
    public let role: String
    public let status: String
    public let score: Double
    public let notes: [String]

    enum CodingKeys: String, CodingKey {
        case runtime
        case role
        case status
        case score
        case notes
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        runtime = try container.decode(String.self, forKey: .runtime)
        role = try container.decode(String.self, forKey: .role)
        status = try container.decode(String.self, forKey: .status)
        score = try container.decode(Double.self, forKey: .score)
        notes = try container.decodeIfPresent([String].self, forKey: .notes) ?? []
    }
}

public struct GraphRagQueryResponse: Codable, Equatable, Sendable {
    public let summary: String
    public let evidence: [GraphRagEvidence]
    public let atoms: [MemoryAtom]
    public let episodes: [MemoryEpisode]
    public let relations: [MemoryRelation]
    public let temporalContext: GraphRagTemporalContext
    public let provenance: ExocortexJSONValue?
    public let confidence: Double
    public let degradedReason: String?
    public let mode: String?
    public let graphRuntime: String?
    public let evidenceGraph: EvidenceGraph?
    public let communityContext: GraphRagCommunityContext?
    public let retrievalTrace: [RetrievalTraceStep]?
    public let meshTrace: [RetrievalTraceStep]
    public let runtimeVotes: [RuntimeVote]
    public let candidateRefs: [String]
    public let runtimeUsed: String?
    public let fallbackChain: [String]
    public let semanticTrace: [RetrievalTraceStep]
    public let maxsimScores: [ExocortexJSONValue]
    public let graphExpansion: ExocortexJSONValue?
    public let rerankerScores: [ExocortexJSONValue]
    public let truthsetGateStatus: PortfolioTruthGate?
    public let restrictedLeakCheck: ExocortexJSONValue?
    public let retrievalAgent: String?
    public let retrievalPlanId: String?
    public let strategyUsed: String?
    public let subqueries: [String]
    public let evidencePack: ExocortexJSONValue?
    public let contextFormat: String?
    public let plannerMode: String?
    public let budget: ExocortexJSONValue?
    public let runtimeTrace: [RetrievalTraceStep]
    public let contextPackId: String?
    public let policyVersion: String?
    public let policyGate: ExocortexJSONValue?
    public let dreamcycleStatus: String?

    enum CodingKeys: String, CodingKey {
        case summary
        case evidence
        case atoms
        case episodes
        case relations
        case temporalContext = "temporal_context"
        case provenance
        case confidence
        case degradedReason = "degraded_reason"
        case mode
        case graphRuntime = "graph_runtime"
        case evidenceGraph = "evidence_graph"
        case communityContext = "community_context"
        case retrievalTrace = "retrieval_trace"
        case meshTrace = "mesh_trace"
        case runtimeVotes = "runtime_votes"
        case candidateRefs = "candidate_refs"
        case runtimeUsed = "runtime_used"
        case fallbackChain = "fallback_chain"
        case semanticTrace = "semantic_trace"
        case maxsimScores = "maxsim_scores"
        case graphExpansion = "graph_expansion"
        case rerankerScores = "reranker_scores"
        case truthsetGateStatus = "truthset_gate_status"
        case restrictedLeakCheck = "restricted_leak_check"
        case retrievalAgent = "retrieval_agent"
        case retrievalPlanId = "retrieval_plan_id"
        case strategyUsed = "strategy_used"
        case subqueries
        case evidencePack = "evidence_pack"
        case contextFormat = "context_format"
        case plannerMode = "planner_mode"
        case budget
        case runtimeTrace = "runtime_trace"
        case contextPackId = "context_pack_id"
        case policyVersion = "policy_version"
        case policyGate = "policy_gate"
        case dreamcycleStatus = "dreamcycle_status"
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        summary = try container.decode(String.self, forKey: .summary)
        evidence = try container.decodeIfPresent([GraphRagEvidence].self, forKey: .evidence) ?? []
        atoms = try container.decodeIfPresent([MemoryAtom].self, forKey: .atoms) ?? []
        episodes = try container.decodeIfPresent([MemoryEpisode].self, forKey: .episodes) ?? []
        relations = try container.decodeIfPresent([MemoryRelation].self, forKey: .relations) ?? []
        temporalContext = try container.decode(GraphRagTemporalContext.self, forKey: .temporalContext)
        provenance = try container.decodeIfPresent(ExocortexJSONValue.self, forKey: .provenance)
        confidence = try container.decode(Double.self, forKey: .confidence)
        degradedReason = try container.decodeIfPresent(String.self, forKey: .degradedReason)
        mode = try container.decodeIfPresent(String.self, forKey: .mode)
        graphRuntime = try container.decodeIfPresent(String.self, forKey: .graphRuntime)
        evidenceGraph = try container.decodeIfPresent(EvidenceGraph.self, forKey: .evidenceGraph)
        communityContext = try container.decodeIfPresent(GraphRagCommunityContext.self, forKey: .communityContext)
        retrievalTrace = try container.decodeIfPresent([RetrievalTraceStep].self, forKey: .retrievalTrace)
        meshTrace = try container.decodeIfPresent([RetrievalTraceStep].self, forKey: .meshTrace) ?? []
        runtimeVotes = try container.decodeIfPresent([RuntimeVote].self, forKey: .runtimeVotes) ?? []
        candidateRefs = try container.decodeIfPresent([String].self, forKey: .candidateRefs) ?? []
        runtimeUsed = try container.decodeIfPresent(String.self, forKey: .runtimeUsed)
        fallbackChain = try container.decodeIfPresent([String].self, forKey: .fallbackChain) ?? []
        semanticTrace = try container.decodeIfPresent([RetrievalTraceStep].self, forKey: .semanticTrace) ?? []
        maxsimScores = try container.decodeIfPresent([ExocortexJSONValue].self, forKey: .maxsimScores) ?? []
        graphExpansion = try container.decodeIfPresent(ExocortexJSONValue.self, forKey: .graphExpansion)
        rerankerScores = try container.decodeIfPresent([ExocortexJSONValue].self, forKey: .rerankerScores) ?? []
        truthsetGateStatus = try container.decodeIfPresent(PortfolioTruthGate.self, forKey: .truthsetGateStatus)
        restrictedLeakCheck = try container.decodeIfPresent(ExocortexJSONValue.self, forKey: .restrictedLeakCheck)
        retrievalAgent = try container.decodeIfPresent(String.self, forKey: .retrievalAgent)
        retrievalPlanId = try container.decodeIfPresent(String.self, forKey: .retrievalPlanId)
        strategyUsed = try container.decodeIfPresent(String.self, forKey: .strategyUsed)
        subqueries = try container.decodeIfPresent([String].self, forKey: .subqueries) ?? []
        evidencePack = try container.decodeIfPresent(ExocortexJSONValue.self, forKey: .evidencePack)
        contextFormat = try container.decodeIfPresent(String.self, forKey: .contextFormat)
        plannerMode = try container.decodeIfPresent(String.self, forKey: .plannerMode)
        budget = try container.decodeIfPresent(ExocortexJSONValue.self, forKey: .budget)
        runtimeTrace = try container.decodeIfPresent([RetrievalTraceStep].self, forKey: .runtimeTrace) ?? []
        contextPackId = try container.decodeIfPresent(String.self, forKey: .contextPackId)
        policyVersion = try container.decodeIfPresent(String.self, forKey: .policyVersion)
        policyGate = try container.decodeIfPresent(ExocortexJSONValue.self, forKey: .policyGate)
        dreamcycleStatus = try container.decodeIfPresent(String.self, forKey: .dreamcycleStatus)
    }
}

public struct MemoryLensMode: RawRepresentable, Codable, Equatable, Hashable, Sendable {
    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }

    public static let report = MemoryLensMode(rawValue: "report")
    public static let evidence = MemoryLensMode(rawValue: "evidence")
    public static let proof = MemoryLensMode(rawValue: "proof")
    public static let deepDive = MemoryLensMode(rawValue: "deep_dive")
}

public struct MemoryLensPreset: Codable, Equatable, Sendable, Identifiable {
    public let id: String
    public let title: String
    public let query: String
    public let detail: String
    public let systemImage: String
    public let scopeHint: String?
    public let priority: Int

    enum CodingKeys: String, CodingKey {
        case id
        case title
        case query
        case detail
        case systemImage = "system_image"
        case scopeHint = "scope_hint"
        case priority
    }
}

public struct ProofSheetModel: Codable, Equatable, Sendable, Identifiable {
    public let id: String
    public let title: String
    public let summary: String
    public let sourceRefs: [String]
    public let provenanceLines: [String]
    public let traceLines: [String]
    public let runtime: String?
    public let confidence: Double
    public let restrictedLeakCheck: String

    enum CodingKeys: String, CodingKey {
        case id
        case title
        case summary
        case sourceRefs = "source_refs"
        case provenanceLines = "provenance_lines"
        case traceLines = "trace_lines"
        case runtime
        case confidence
        case restrictedLeakCheck = "restricted_leak_check"
    }
}

public struct EvidenceFrontierItem: Codable, Equatable, Sendable, Identifiable {
    public let id: String
    public let title: String
    public let detail: String
    public let kind: String
    public let score: Double
    public let sourceLabel: String
    public let sourceRefs: [String]
    public let truthMode: String
    public let privacyClass: String
    public let proof: ProofSheetModel

    enum CodingKeys: String, CodingKey {
        case id
        case title
        case detail
        case kind
        case score
        case sourceLabel = "source_label"
        case sourceRefs = "source_refs"
        case truthMode = "truth_mode"
        case privacyClass = "privacy_class"
        case proof
    }
}

public struct MemoryLensReport: Codable, Equatable, Sendable, Identifiable {
    public let id: String
    public let generatedAt: String
    public let mode: MemoryLensMode
    public let headline: String
    public let summary: String
    public let changedSignals: [String]
    public let evidenceFrontier: [EvidenceFrontierItem]
    public let presets: [MemoryLensPreset]
    public let sourceConfidenceBadges: [String]
    public let confidence: Double
    public let runtime: String
    public let degradedReason: String?
    public let restrictedContentFiltered: Bool
    public let proof: ProofSheetModel

    enum CodingKeys: String, CodingKey {
        case id
        case generatedAt = "generated_at"
        case mode
        case headline
        case summary
        case changedSignals = "changed_signals"
        case evidenceFrontier = "evidence_frontier"
        case presets
        case sourceConfidenceBadges = "source_confidence_badges"
        case confidence
        case runtime
        case degradedReason = "degraded_reason"
        case restrictedContentFiltered = "restricted_content_filtered"
        case proof
    }
}

public extension MemoryLensReport {
    static func synthesized(
        home: ExocortexHomeSnapshot? = nil,
        homeTruthMode: TruthMode = .declared,
        graphStatus: MemoryGraphStatus? = nil,
        recentGraph: MemoryGraphRecentResponse? = nil,
        benchmark: MemoryBenchmarkStatus? = nil,
        governance: MemoryGovernanceStatus? = nil,
        contradictions: MemoryContradictionListResponse? = nil,
        lastQuery: GraphRagQueryResponse? = nil,
        activeProjectSlug: String = "beagle"
    ) -> MemoryLensReport {
        let generatedAt = lastQuery?.temporalContext.newestEvidenceAt
            ?? recentGraph?.generatedAt
            ?? graphStatus?.generatedAt
            ?? home?.generatedAt
            ?? "local-memory-lens"
        let runtime = lastQuery?.runtimeUsed
            ?? lastQuery?.mode
            ?? graphStatus?.graphRuntime
            ?? home?.trustContext?.hotPathMode
            ?? home?.trustContext?.retrievalMode
            ?? recentGraph?.status.retrievalMode
            ?? "GraphRAG++"
        let degraded = lastQuery?.degradedReason
            ?? graphStatus?.degradedReason.nilIfEmpty
            ?? recentGraph?.status.degradedReason.nilIfEmpty
            ?? home?.trustContext?.graphDegradedReason?.nilIfEmpty

        var changedSignals: [String] = []
        if let write = home?.trustContext?.latestAgentWrite ?? home?.agentContext?.lastAgentWrite, !write.isEmpty {
            changedSignals.append("agent write: \(write)")
        }
        if let paper = home?.trustContext?.sounioPaperRunStatus, !paper.isEmpty {
            changedSignals.append("Sounio PaperRun: \(paper)")
        }
        if let pending = home?.trustContext?.sounioPendingApproval, !pending.isEmpty {
            changedSignals.append("approval pending: \(pending)")
        }
        if let grok = latestGrokSignal(home: home, graph: recentGraph) {
            changedSignals.append("Grok/LLM import: \(grok)")
        }
        if let contradictions, !contradictions.contradictions.isEmpty {
            changedSignals.append("tension: \(contradictions.contradictions.count) contradiction candidates")
        } else if let open = governance?.openContradictions, open > 0 {
            changedSignals.append("tension: \(open) open contradictions")
        }
        if let benchmark {
            let score = benchmark.latestScore.map { String(format: "%.2f", $0) } ?? "pending"
            changedSignals.append("bench \(benchmark.status): \(score)")
        }
        if changedSignals.isEmpty, let status = recentGraph?.status {
            changedSignals.append("\(status.episodeCount) episodes · \(status.atomCount) atoms projected")
        }
        if changedSignals.isEmpty {
            changedSignals.append("Memory Lens is ready from cached or declared state.")
        }

        let frontier = evidenceFrontier(from: lastQuery, recentGraph: recentGraph, truthMode: homeTruthMode)
        let restrictedFiltered = containsRestricted(recentGraph: recentGraph)
            || containsRestricted(query: lastQuery)
        let headline: String
        if lastQuery != nil {
            headline = "A lente montou uma resposta verificável."
        } else if frontier.isEmpty {
            headline = "A bancada de memória está pronta."
        } else {
            headline = "A memória viva tem \(frontier.count) evidências na fronteira."
        }

        let summary = lastQuery?.summary
            ?? synthesizedSummary(home: home, graph: recentGraph, governance: governance, degraded: degraded)
        let confidence = lastQuery?.confidence
            ?? min(0.98, max(0.35, frontier.map(\.score).max() ?? 0.62))
        let badges = sourceBadges(
            home: home,
            homeTruthMode: homeTruthMode,
            graphStatus: graphStatus,
            recentGraph: recentGraph,
            benchmark: benchmark,
            runtime: runtime,
            restrictedFiltered: restrictedFiltered
        )
        let proof = ProofSheetModel(
            id: "memory-lens-report-proof",
            title: "Prova da lente",
            summary: summary,
            sourceRefs: frontier.flatMap(\.sourceRefs).stablePrefix(8),
            provenanceLines: badges,
            traceLines: proofTraceLines(lastQuery: lastQuery, graphStatus: graphStatus, recentGraph: recentGraph),
            runtime: runtime,
            confidence: confidence,
            restrictedLeakCheck: restrictedFiltered ? "restricted filtered before display" : "no restricted surfaced"
        )

        return MemoryLensReport(
            id: "memory-lens-\(generatedAt)-\(runtime)",
            generatedAt: generatedAt,
            mode: lastQuery == nil ? .report : .evidence,
            headline: headline,
            summary: summary,
            changedSignals: changedSignals.stablePrefix(5),
            evidenceFrontier: frontier,
            presets: MemoryLensPreset.beagleNow(activeProjectSlug: activeProjectSlug),
            sourceConfidenceBadges: badges,
            confidence: confidence,
            runtime: runtime,
            degradedReason: degraded,
            restrictedContentFiltered: restrictedFiltered,
            proof: proof
        )
    }

    private static func evidenceFrontier(
        from query: GraphRagQueryResponse?,
        recentGraph: MemoryGraphRecentResponse?,
        truthMode: TruthMode
    ) -> [EvidenceFrontierItem] {
        if let query, !query.evidence.isEmpty {
            let trace = (query.retrievalTrace ?? []) + query.semanticTrace + query.runtimeTrace
            return query.evidence
                .filter { !isRestrictedText($0.text) && !$0.sourceRefs.contains(where: isRestrictedText) }
                .prefix(6)
                .map { evidence in
                    let proof = ProofSheetModel(
                        id: "proof-\(evidence.atomId)",
                        title: evidence.atomType.capitalized,
                        summary: evidence.text,
                        sourceRefs: evidence.sourceRefs,
                        provenanceLines: provenanceLines(from: evidence.provenance),
                        traceLines: trace.prefix(8).map(traceLine),
                        runtime: query.runtimeUsed ?? query.mode,
                        confidence: evidence.score,
                        restrictedLeakCheck: "no restricted surfaced"
                    )
                    return EvidenceFrontierItem(
                        id: evidence.atomId,
                        title: evidence.atomType.capitalized,
                        detail: evidence.text,
                        kind: "query_evidence",
                        score: evidence.score,
                        sourceLabel: evidence.episodeId,
                        sourceRefs: evidence.sourceRefs,
                        truthMode: TruthMode.observed.rawValue,
                        privacyClass: "sensitive",
                        proof: proof
                    )
                }
        }

        let atoms = recentGraph?.atoms ?? []
        return atoms
            .filter { !isRestricted($0) }
            .prefix(6)
            .map { atom in
                let proof = ProofSheetModel(
                    id: "proof-\(atom.id)",
                    title: atom.atomType.capitalized,
                    summary: atom.text,
                    sourceRefs: atom.sourceRefs,
                    provenanceLines: atom.tags.stablePrefix(6),
                    traceLines: [
                        "episode \(atom.episodeId)",
                        "created \(atom.createdAt)",
                        "truth \(truthMode.rawValue)"
                    ],
                    runtime: recentGraph?.status.retrievalMode,
                    confidence: atom.confidence,
                    restrictedLeakCheck: "no restricted surfaced"
                )
                return EvidenceFrontierItem(
                    id: atom.id,
                    title: atom.atomType.capitalized,
                    detail: atom.text,
                    kind: "projected_atom",
                    score: atom.confidence,
                    sourceLabel: atom.episodeId,
                    sourceRefs: atom.sourceRefs,
                    truthMode: truthMode.rawValue,
                    privacyClass: atom.privacyClass,
                    proof: proof
                )
            }
    }

    private static func synthesizedSummary(
        home: ExocortexHomeSnapshot?,
        graph: MemoryGraphRecentResponse?,
        governance: MemoryGovernanceStatus?,
        degraded: String?
    ) -> String {
        if let graph {
            let status = graph.status
            var parts = ["\(status.episodeCount) episodes and \(status.atomCount) atoms are projected into GraphRAG++."]
            if let governance {
                parts.append("\(governance.pendingTriads) Triad items pending and \(governance.openContradictions) open tensions.")
            }
            if let degraded, !degraded.isEmpty {
                parts.append("Retrieval is degraded: \(degraded)")
            }
            return parts.joined(separator: " ")
        }
        if let home {
            return home.todayBrief
        }
        return "The lens is waiting for cluster memory, but the local interface remains ready."
    }

    private static func latestGrokSignal(home: ExocortexHomeSnapshot?, graph: MemoryGraphRecentResponse?) -> String? {
        if let signal = home?.memorySignals.first(where: { $0.localizedCaseInsensitiveContains("grok") }) {
            return signal
        }
        if let episode = graph?.episodes.first(where: { !isRestricted($0) && isGrok($0) }) {
            return episode.title ?? episode.sourceRef
        }
        if let atom = graph?.atoms.first(where: { !isRestricted($0) && isGrok($0) }) {
            return atom.text
        }
        return nil
    }

    private static func sourceBadges(
        home: ExocortexHomeSnapshot?,
        homeTruthMode: TruthMode,
        graphStatus: MemoryGraphStatus?,
        recentGraph: MemoryGraphRecentResponse?,
        benchmark: MemoryBenchmarkStatus?,
        runtime: String,
        restrictedFiltered: Bool
    ) -> [String] {
        var badges = [
            "truth \(homeTruthMode.rawValue)",
            runtime,
            restrictedFiltered ? "restricted filtered" : "no restricted surfaced"
        ]
        if let mcp = home?.trustContext?.mcpStatus {
            badges.append("MCP \(mcp)")
        }
        if let graph = graphStatus?.runtimeStatus {
            badges.append("graph \(graph)")
        }
        if let freshness = recentGraph?.status.freshness {
            badges.append("freshness \(freshness)")
        }
        if let benchmark {
            badges.append("bench \(benchmark.status)")
        }
        return badges.stablePrefix(6)
    }

    private static func proofTraceLines(
        lastQuery: GraphRagQueryResponse?,
        graphStatus: MemoryGraphStatus?,
        recentGraph: MemoryGraphRecentResponse?
    ) -> [String] {
        if let lastQuery {
            let trace = (lastQuery.retrievalTrace ?? []) + lastQuery.semanticTrace + lastQuery.runtimeTrace
            let lines = trace.prefix(8).map(traceLine)
            if !lines.isEmpty { return lines }
            if let plan = lastQuery.retrievalPlanId { return ["retrieval plan \(plan)"] }
        }
        var lines: [String] = []
        if let graphStatus {
            lines.append("\(graphStatus.graphRuntime) · \(graphStatus.retrievalMode)")
        }
        if let recentGraph {
            lines.append("\(recentGraph.status.episodeCount) episodes · \(recentGraph.status.atomCount) atoms")
        }
        return lines.isEmpty ? ["local derived report; no backend mutation"] : lines
    }

    private static func traceLine(_ step: RetrievalTraceStep) -> String {
        "\(step.stage) · \(step.backend) · \(step.status) · \(step.items) items"
    }

    private static func provenanceLines(from value: ExocortexJSONValue?) -> [String] {
        guard let value else { return [] }
        return String(describing: value)
            .split(separator: "\n")
            .map(String.init)
            .stablePrefix(4)
    }

    private static func containsRestricted(recentGraph: MemoryGraphRecentResponse?) -> Bool {
        guard let recentGraph else { return false }
        return recentGraph.atoms.contains(where: isRestricted) || recentGraph.episodes.contains(where: isRestricted)
    }

    private static func containsRestricted(query: GraphRagQueryResponse?) -> Bool {
        guard let query else { return false }
        return query.evidence.contains { isRestrictedText($0.text) || $0.sourceRefs.contains(where: isRestrictedText) }
    }

    private static func isRestricted(_ atom: MemoryAtom) -> Bool {
        atom.privacyClass.lowercased() == "restricted" || isRestrictedText(atom.text)
    }

    private static func isRestricted(_ episode: MemoryEpisode) -> Bool {
        episode.privacyClass.lowercased() == "restricted"
            || isRestrictedText(episode.title ?? "")
            || isRestrictedText(episode.sourceRef)
    }

    private static func isRestrictedText(_ text: String) -> Bool {
        text.localizedCaseInsensitiveContains("restricted")
            || text.localizedCaseInsensitiveContains("client_secret")
            || text.localizedCaseInsensitiveContains("api_key")
    }

    private static func isGrok(_ episode: MemoryEpisode) -> Bool {
        ([episode.source, episode.sourcePlatform ?? "", episode.title ?? "", episode.sourceRef] + episode.tags)
            .joined(separator: " ")
            .localizedCaseInsensitiveContains("grok")
    }

    private static func isGrok(_ atom: MemoryAtom) -> Bool {
        ([atom.atomType, atom.text] + atom.tags)
            .joined(separator: " ")
            .localizedCaseInsensitiveContains("grok")
    }
}

public extension MemoryLensPreset {
    static func beagleNow(activeProjectSlug: String = "beagle") -> [MemoryLensPreset] {
        [
            MemoryLensPreset(
                id: "latest-beagle-decision",
                title: "Última decisão Beagle",
                query: "qual foi a última decisão relevante sobre o Beagle?",
                detail: "Retoma a decisão mais recente com evidência e próximo gesto.",
                systemImage: "checkmark.seal",
                scopeHint: activeProjectSlug,
                priority: 0
            ),
            MemoryLensPreset(
                id: "claude-codex-changes",
                title: "Claude/Codex mudou o quê?",
                query: "o que mudou desde as últimas escritas do Claude, Codex ou Claude Code?",
                detail: "Compara writes recentes de agentes e memória de trabalho.",
                systemImage: "point.3.connected.trianglepath.dotted",
                scopeHint: activeProjectSlug,
                priority: 1
            ),
            MemoryLensPreset(
                id: "sounio-paperrun-now",
                title: "Sounio/PaperRun agora",
                query: "qual é o estado atual do Sounio PaperRun e quais claims precisam atenção?",
                detail: "Mostra claims, aprovações e tensão epistêmica.",
                systemImage: "doc.richtext",
                scopeHint: activeProjectSlug,
                priority: 2
            ),
            MemoryLensPreset(
                id: "grok-claude-imports",
                title: "Imports Grok/Claude",
                query: "o que os imports do Grok e Claude adicionaram à memória do Beagle?",
                detail: "Procura sinais novos sem expor conteúdo restrito.",
                systemImage: "tray.and.arrow.down",
                scopeHint: activeProjectSlug,
                priority: 3
            ),
            MemoryLensPreset(
                id: "next-move",
                title: "Próximo gesto",
                query: "o que devo fazer agora no Beagle considerando memória, agentes, Sounio e app Apple?",
                detail: "Sintetiza ação situada a partir da memória viva.",
                systemImage: "arrow.forward.circle",
                scopeHint: activeProjectSlug,
                priority: 4
            )
        ]
    }
}
