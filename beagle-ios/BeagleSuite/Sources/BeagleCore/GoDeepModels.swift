//
//  GoDeepModels.swift
//  BeagleCore
//
//  Response models for Go Deeper advanced reasoning endpoints
//  and new cockpit endpoints not yet wired into iOS.
//
//  Convention: all public, Codable, Sendable, optional fields,
//  CodingKeys for snake_case JSON mapping.
//

import Foundation
import SwiftUI
import CoreGraphics
import CoreText

// MARK: - GoDeep Modality Enum

public enum GoDeepModality: String, CaseIterable, Sendable, Identifiable {
    case astraDeep        = "astra-xhigh"
    case rosalindBio      = "rosalind-bio"
    case deepResearch     = "deep-research"
    case quantumReasoning = "quantum-reasoning"
    case swarmConsensus   = "swarm-consensus"
    case causalExtract    = "causal-extract"
    case temporal         = "temporal"
    case neurosymbolic    = "neurosymbolic"
    case adversarial      = "adversarial"
    case serendipity      = "serendipity"

    public var id: String { rawValue }

    /// Short badge label for Dynamic Island & Lock Screen Live Activity pills.
    public var shortBadge: String {
        switch self {
        case .astraDeep:        return "Astra xhigh"
        case .rosalindBio:      return "Rosalind PBPK"
        case .deepResearch:     return "Pesquisa"
        case .quantumReasoning: return "Quântico"
        case .swarmConsensus:   return "Enxame"
        case .causalExtract:    return "Causal"
        case .temporal:         return "Temporal"
        case .neurosymbolic:    return "Simbólico"
        case .adversarial:      return "Adversarial"
        case .serendipity:      return "Serendipidade"
        }
    }

    public var displayName: String {
        switch self {
        case .astraDeep:        return "GPT-6.2 Astra (xhigh)"
        case .rosalindBio:      return "GPT-Rosalind (Bio/PBPK)"
        case .deepResearch:     return "Pesquisa Profunda"
        case .quantumReasoning: return "Raciocínio Quântico"
        case .swarmConsensus:   return "Consenso de Enxame"
        case .causalExtract:    return "Grafo Causal"
        case .temporal:         return "Dinâmica Temporal"
        case .neurosymbolic:    return "Neuro-Simbólico"
        case .adversarial:      return "Bancada Adversarial"
        case .serendipity:      return "Serendipidade"
        }
    }

    public var icon: String {
        switch self {
        case .astraDeep:        return "sparkle.magnifyingglass"
        case .rosalindBio:      return "cross.vial.fill"
        case .deepResearch:     return "tree"
        case .quantumReasoning: return "atom"
        case .swarmConsensus:   return "ant.fill"
        case .causalExtract:    return "arrow.triangle.branch"
        case .temporal:         return "clock.arrow.2.circlepath"
        case .neurosymbolic:    return "brain.head.profile"
        case .adversarial:      return "shield.lefthalf.filled"
        case .serendipity:      return "sparkles"
        }
    }

    public var themeColor: Color {
        switch self {
        case .astraDeep:        return BeagleTheme.truthObserved      // luminous teal
        case .rosalindBio:      return Color(hue: 162/360, saturation: 0.72, brightness: 0.90) // biomedical emerald
        case .deepResearch:     return BeagleTheme.truthObserved      // teal
        case .quantumReasoning: return BeagleTheme.truthRemembered    // sky blue
        case .swarmConsensus:   return BeagleTheme.postureWarm        // gold
        case .causalExtract:    return BeagleTheme.truthDeclared      // slate-purple
        case .temporal:         return BeagleTheme.textData           // cool cyan
        case .neurosymbolic:    return BeagleTheme.stateStarting      // gold
        case .adversarial:      return BeagleTheme.stateError         // red
        case .serendipity:      return Color(hue: 300/360, saturation: 0.60, brightness: 0.90) // magenta
        }
    }
}

// MARK: - GoDeep Result (unified container)

public enum GoDeepResult: Sendable {
    case astraDeep(Truthful<FrontierResearchResult>)
    case rosalindBio(Truthful<FrontierResearchResult>)
    case deepResearch(Truthful<DeepResearchResult>)
    case quantum(Truthful<QuantumReasoningResult>)
    case swarm(Truthful<SwarmResult>)
    case causal(Truthful<CausalGraph>)
    case temporal(Truthful<TemporalResult>)
    case neurosymbolic(Truthful<NeurosymbolicResult>)
    case adversarial(Truthful<AdversarialResult>)
    case serendipity(Truthful<SerendipityResult>)

    public var modality: GoDeepModality {
        switch self {
        case .astraDeep:     return .astraDeep
        case .rosalindBio:   return .rosalindBio
        case .deepResearch:  return .deepResearch
        case .quantum:       return .quantumReasoning
        case .swarm:         return .swarmConsensus
        case .causal:        return .causalExtract
        case .temporal:      return .temporal
        case .neurosymbolic: return .neurosymbolic
        case .adversarial:   return .adversarial
        case .serendipity:   return .serendipity
        }
    }

    public var truthMode: TruthMode {
        switch self {
        case .astraDeep(let t):     return t.mode
        case .rosalindBio(let t):   return t.mode
        case .deepResearch(let t):  return t.mode
        case .quantum(let t):       return t.mode
        case .swarm(let t):         return t.mode
        case .causal(let t):        return t.mode
        case .temporal(let t):      return t.mode
        case .neurosymbolic(let t): return t.mode
        case .adversarial(let t):   return t.mode
        case .serendipity(let t):   return t.mode
        }
    }

    public var isError: Bool { truthMode == .stale }

    public var summary: String {
        switch self {
        case .astraDeep(let t), .rosalindBio(let t):
            guard let v = t.value else { return t.error ?? "Sem resultado" }
            if let thesis = v.thesis.trimmedNonEmpty {
                return thesis
            }
            return v.analysisMarkdown.trimmedNonEmpty ?? "Análise concluída."
        case .deepResearch(let t):
            guard let v = t.value else { return t.error ?? "Sem resultado" }
            if let best = v.bestHypothesis?.trimmedNonEmpty {
                return best
            }
            return "Pesquisa profunda concluída sem hipótese legível."
        case .quantum(let t):
            guard let v = t.value else { return t.error ?? "Sem resultado" }
            if let h = v.selectedHypothesis, let p = v.probability {
                return "\(h) (p=\(String(format: "%.2f", p)))"
            }
            return "\(v.rankedHypotheses?.count ?? 0) hipóteses ranqueadas"
        case .swarm(let t):
            guard let v = t.value else { return t.error ?? "Sem resultado" }
            if let first = v.consensus?.first?.trimmedNonEmpty {
                return first
            }
            return "Enxame concluído sem pontos de consenso."
        case .causal(let t):
            guard let v = t.value else { return t.error ?? "Sem resultado" }
            if let summary = v.summary?.trimmedNonEmpty {
                return summary
            }
            return "\(v.nodes?.count ?? 0) nós, \(v.edges?.count ?? 0) arestas causais"
        case .temporal(let t):
            return t.value?.summary?.trimmedNonEmpty ?? t.error ?? "Sem resultado"
        case .neurosymbolic(let t):
            return t.value?.summary?.trimmedNonEmpty ?? t.error ?? "Sem resultado"
        case .adversarial(let t):
            guard let v = t.value else { return t.error ?? "Sem resultado" }
            return v.summary?.trimmedNonEmpty ?? v.winner ?? "\(v.rounds ?? 0) rodadas"
        case .serendipity(let t):
            return t.value?.summary?.trimmedNonEmpty ?? t.error ?? "Sem resultado"
        }
    }
}

// MARK: - Frontier Research Models (GPT-6.2 Astra xhigh & GPT-Rosalind Bio/PBPK)

public struct FrontierCitation: Codable, Sendable, Identifiable, Equatable {
    public var id: String { url }
    public let title: String
    public let url: String

    public init(title: String, url: String) {
        self.title = title
        self.url = url
    }
}

public struct FrontierResearchResult: Codable, Sendable {
    public let model: String
    public let reasoningEffort: String
    public let thesis: String
    public let analysisMarkdown: String
    public let executedTools: [String]
    public let citations: [FrontierCitation]

    public init(
        model: String,
        reasoningEffort: String,
        thesis: String,
        analysisMarkdown: String,
        executedTools: [String] = [],
        citations: [FrontierCitation] = []
    ) {
        self.model = model
        self.reasoningEffort = reasoningEffort
        self.thesis = thesis
        self.analysisMarkdown = analysisMarkdown
        self.executedTools = executedTools
        self.citations = citations
    }
}

private extension String {
    var trimmedNonEmpty: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

// MARK: - GoDeep Session

public struct GoDeepSession: Sendable, Identifiable {
    public let id = UUID()
    public let prompt: String
    public let startedAt: Date
    public let modalities: [GoDeepModality]
    public var completedAt: Date?

    public init(prompt: String, startedAt: Date = .now, modalities: [GoDeepModality]) {
        self.prompt = prompt
        self.startedAt = startedAt
        self.modalities = modalities
    }

    public var duration: TimeInterval? {
        guard let end = completedAt else { return nil }
        return end.timeIntervalSince(startedAt)
    }
}

// ============================================================================
// MARK: - beagle-core Response Models
// ============================================================================

// MARK: - Deep Research (/dev/deep-research)

public struct DeepResearchResult: Codable, Sendable {
    public let treeSize: Int?
    public let bestHypothesis: String?
    public let iterations: Int?

    public init(treeSize: Int? = nil, bestHypothesis: String? = nil, iterations: Int? = nil) {
        self.treeSize = treeSize
        self.bestHypothesis = bestHypothesis
        self.iterations = iterations
    }

    enum CodingKeys: String, CodingKey {
        case treeSize = "tree_size"
        case bestHypothesis = "best_hypothesis"
        case iterations
    }
}

// MARK: - Quantum Reasoning (/dev/quantum-reasoning)

public struct QuantumReasoningResult: Codable, Sendable {
    public let selectedHypothesis: String?
    public let probability: Double?
    public let rankedHypotheses: [RankedHypothesis]?
    public let alternatives: [RankedHypothesis]?
    public let metadata: QuantumMetadata?

    public init(
        selectedHypothesis: String? = nil,
        probability: Double? = nil,
        rankedHypotheses: [RankedHypothesis]? = nil,
        alternatives: [RankedHypothesis]? = nil,
        metadata: QuantumMetadata? = nil
    ) {
        self.selectedHypothesis = selectedHypothesis
        self.probability = probability
        self.rankedHypotheses = rankedHypotheses
        self.alternatives = alternatives
        self.metadata = metadata
    }

    enum CodingKeys: String, CodingKey {
        case selectedHypothesis = "selected_hypothesis"
        case probability
        case rankedHypotheses = "ranked_hypotheses"
        case alternatives, metadata
    }
}

public struct RankedHypothesis: Codable, Sendable, Identifiable {
    public var id: String { content ?? UUID().uuidString }
    public let content: String?
    public let probability: Double?
    public let confidence: Double?

    public init(content: String? = nil, probability: Double? = nil, confidence: Double? = nil) {
        self.content = content
        self.probability = probability
        self.confidence = confidence
    }
}

public struct QuantumMetadata: Codable, Sendable {
    public let totalHypotheses: Int?
    public let interferenceApplied: Bool?
    public let decoherenceApplied: Bool?
    public let processingTimeMs: Int?

    public init(
        totalHypotheses: Int? = nil,
        interferenceApplied: Bool? = nil,
        decoherenceApplied: Bool? = nil,
        processingTimeMs: Int? = nil
    ) {
        self.totalHypotheses = totalHypotheses
        self.interferenceApplied = interferenceApplied
        self.decoherenceApplied = decoherenceApplied
        self.processingTimeMs = processingTimeMs
    }

    enum CodingKeys: String, CodingKey {
        case totalHypotheses = "total_hypotheses"
        case interferenceApplied = "interference_applied"
        case decoherenceApplied = "decoherence_applied"
        case processingTimeMs = "processing_time_ms"
    }
}

// MARK: - Swarm Consensus (/dev/swarm)

public struct SwarmResult: Codable, Sendable {
    public let consensus: [String]?
    public let iterations: Int?
    public let nAgents: Int?

    public init(consensus: [String]? = nil, iterations: Int? = nil, nAgents: Int? = nil) {
        self.consensus = consensus
        self.iterations = iterations
        self.nAgents = nAgents
    }

    enum CodingKeys: String, CodingKey {
        case consensus, iterations
        case nAgents = "n_agents"
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if let points = try? container.decodeIfPresent([String].self, forKey: .consensus) {
            consensus = points
        } else if let point = try? container.decodeIfPresent(String.self, forKey: .consensus) {
            consensus = point
                .split(separator: "\n")
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines.union(CharacterSet(charactersIn: "-*• "))) }
                .filter { !$0.isEmpty }
        } else {
            consensus = nil
        }
        iterations = try container.decodeIfPresent(Int.self, forKey: .iterations)
        nAgents = try container.decodeIfPresent(Int.self, forKey: .nAgents)
    }
}

// MARK: - Causal (/dev/causal/extract, /dev/causal/intervention)

public struct CausalGraph: Codable, Sendable {
    public let nodes: [CausalNode]?
    public let edges: [CausalEdge]?
    public let summary: String?

    public init(nodes: [CausalNode]? = nil, edges: [CausalEdge]? = nil, summary: String? = nil) {
        self.nodes = nodes
        self.edges = edges
        self.summary = summary
    }
}

public struct CausalNode: Codable, Sendable, Identifiable {
    public var id: String { nodeId ?? UUID().uuidString }
    public let nodeId: String?
    public let label: String?
    public let type: String?

    public init(nodeId: String? = nil, label: String? = nil, type: String? = nil) {
        self.nodeId = nodeId
        self.label = label
        self.type = type
    }

    enum CodingKeys: String, CodingKey {
        case nodeId = "id"
        case label, type
    }
}

public struct CausalEdge: Codable, Sendable, Identifiable {
    public var id: String { "\(source ?? "")-\(target ?? "")" }
    public let source: String?
    public let target: String?
    public let strength: Double?
    public let label: String?

    public init(source: String? = nil, target: String? = nil, strength: Double? = nil, label: String? = nil) {
        self.source = source
        self.target = target
        self.strength = strength
        self.label = label
    }
}

public struct CausalIntervention: Codable, Sendable {
    public let outcome: String?
    public let effect: String?
    public let confidence: Double?
}

// MARK: - Temporal (/dev/temporal)

public struct TemporalResult: Codable, Sendable {
    public let result: JSONValue?
    public let summary: String?

    public init(result: JSONValue? = nil, summary: String? = nil) {
        self.result = result
        self.summary = summary
    }
}

// MARK: - Neurosymbolic (/dev/neurosymbolic)

public struct NeurosymbolicResult: Codable, Sendable {
    public let result: JSONValue?
    public let summary: String?

    public init(result: JSONValue? = nil, summary: String? = nil) {
        self.result = result
        self.summary = summary
    }
}

// MARK: - Adversarial (/dev/adversarial-compete)

public struct AdversarialResult: Codable, Sendable {
    public let winner: String?
    public let agents: [AdversarialAgent]?
    public let rounds: Int?
    public let summary: String?

    public init(
        winner: String? = nil,
        agents: [AdversarialAgent]? = nil,
        rounds: Int? = nil,
        summary: String? = nil
    ) {
        self.winner = winner
        self.agents = agents
        self.rounds = rounds
        self.summary = summary
    }
}

public struct AdversarialAgent: Codable, Sendable, Identifiable {
    public var id: String { name ?? UUID().uuidString }
    public let name: String?
    public let score: Double?
    public let strategy: String?

    public init(name: String? = nil, score: Double? = nil, strategy: String? = nil) {
        self.name = name
        self.score = score
        self.strategy = strategy
    }
}

// MARK: - Metacognitive (/dev/metacognitive/*)

public struct MetacogPerformance: Codable, Sendable {
    public let result: JSONValue?
    public let summary: String?
}

// MARK: - Research (/dev/research, /dev/research/parallel)

public struct ResearchResult: Codable, Sendable {
    public let result: JSONValue?
    public let summary: String?
}

public struct ParallelResearchResult: Codable, Sendable {
    public let result: JSONValue?
    public let paths: [ResearchPath]?
    public let summary: String?
}

public struct ResearchPath: Codable, Sendable, Identifiable {
    public var id: String { pathId ?? UUID().uuidString }
    public let pathId: String?
    public let summary: String?
    public let confidence: Double?

    enum CodingKeys: String, CodingKey {
        case pathId = "id"
        case summary, confidence
    }
}

// MARK: - Reasoning Path (/dev/reasoning)

public struct ReasoningPathResult: Codable, Sendable {
    public let result: JSONValue?
    public let steps: [ReasoningStep]?
    public let summary: String?
}

public struct ReasoningStep: Codable, Sendable, Identifiable {
    public var id: String { "\(index ?? 0)" }
    public let index: Int?
    public let content: String?
    public let confidence: Double?
}

// MARK: - World Model (/worldmodel/*)

public struct WorldModelState: Codable, Sendable {
    public let entities: Int?
    public let uncertainty: Double?
    public let abstractionLevel: Double?
    public let timestamp: String?

    enum CodingKeys: String, CodingKey {
        case entities, uncertainty
        case abstractionLevel = "abstraction_level"
        case timestamp
    }
}

public struct WorldModelPrediction: Codable, Sendable {
    public let result: JSONValue?
    public let summary: String?
}

public struct WorldModelCounterfactual: Codable, Sendable {
    public let result: JSONValue?
    public let summary: String?
}

// MARK: - Serendipity (/api/serendipity/discover)

public struct SerendipityResult: Codable, Sendable {
    public let result: JSONValue?
    public let summary: String?
    public let connections: [SerendipityConnection]?

    public init(
        result: JSONValue? = nil,
        summary: String? = nil,
        connections: [SerendipityConnection]? = nil
    ) {
        self.result = result
        self.summary = summary
        self.connections = connections
    }
}

public struct SerendipityConnection: Codable, Sendable, Identifiable {
    public var id: String { "\(from ?? "")-\(to ?? "")" }
    public let from: String?
    public let to: String?
    public let surprise: Double?
    public let explanation: String?

    public init(
        from: String? = nil,
        to: String? = nil,
        surprise: Double? = nil,
        explanation: String? = nil
    ) {
        self.from = from
        self.to = to
        self.surprise = surprise
        self.explanation = explanation
    }
}

// MARK: - PCS Reason (/api/pcs/reason)

public struct PCSReasonResult: Codable, Sendable {
    public let result: JSONValue?
    public let summary: String?
}

// MARK: - Fractal Grow (/api/fractal/grow)

public struct FractalGrowResult: Codable, Sendable {
    public let result: JSONValue?
    public let summary: String?
}

// MARK: - Document Add (/api/memory/documents)

public struct DocumentAddResult: Codable, Sendable {
    public let id: String?
    public let message: String?
    public let processingTimeMs: Int?

    enum CodingKeys: String, CodingKey {
        case id, message
        case processingTimeMs = "processing_time_ms"
    }
}

// ============================================================================
// MARK: - Cockpit Response Models (new endpoints)
// ============================================================================

// MARK: - Project Memory (/api/projects/:slug/memory/fast, /deep)

public struct ProjectMemory: Codable, Sendable {
    public let project: Project?
    public let viewer: JSONValue?
    public let memory: JSONValue?
    public let generatedAt: String?
}

// MARK: - Sovereign Surface (/api/projects/:slug/sovereign-surface)

public struct SovereignSurface: Codable, Sendable {
    public let project: Project?
    public let viewer: JSONValue?
    public let surface: JSONValue?
    public let generatedAt: String?
}

// MARK: - Truth Summary (/api/projects/:slug/truth/summary)

public struct ProjectTruthSummary: Codable, Sendable {
    public let project: Project?
    public let viewer: JSONValue?
    public let summary: JSONValue?
    public let generatedAt: String?
}

// MARK: - Git (/api/projects/:slug/git/status, /git/diff)

public struct GitStatusResponse: Codable, Sendable {
    public let project: Project?
    public let git: GitStatusDetail?
}

public struct GitStatusDetail: Codable, Sendable {
    public let branch: String?
    public let dirty: Bool?
    public let dirtyCount: Int?
    public let aheadBehind: String?

    enum CodingKeys: String, CodingKey {
        case branch, dirty
        case dirtyCount = "dirty_count"
        case aheadBehind = "ahead_behind"
    }
}

public struct GitDiffResponse: Codable, Sendable {
    public let project: Project?
    public let diff: JSONValue?
}

// MARK: - Execution Packets (/api/projects/:slug/execution/packets)

public struct ExecutionPacketsResponse: Codable, Sendable {
    public let project: Project?
    public let viewer: JSONValue?
    public let packets: [ExecutionPacket]?
}

public struct ExecutionPacket: Codable, Sendable, Identifiable {
    public var id: String { packetId ?? UUID().uuidString }
    public let packetId: String?
    public let label: String?
    public let status: String?
    public let createdAt: String?

    enum CodingKeys: String, CodingKey {
        case packetId = "id"
        case label, status
        case createdAt = "created_at"
    }
}

// MARK: - Scientific Workflows (/api/projects/:slug/workflows/scientific)

public struct ScientificWorkflowsResponse: Codable, Sendable {
    public let project: Project?
    public let viewer: JSONValue?
    public let workflows: [ScientificWorkflow]?
}

public struct ScientificWorkflow: Codable, Sendable, Identifiable {
    public var id: String { workflowId ?? UUID().uuidString }
    public let workflowId: String?
    public let name: String?
    public let status: String?
    public let lastRunAt: String?

    enum CodingKeys: String, CodingKey {
        case workflowId = "id"
        case name, status
        case lastRunAt = "last_run_at"
    }
}

// MARK: - Dataset Catalog (/api/projects/:slug/datasets/catalog)

public struct DatasetCatalogResponse: Codable, Sendable {
    public let project: Project?
    public let viewer: JSONValue?
    public let datasets: [DatasetEntry]?
}

public struct DatasetEntry: Codable, Sendable, Identifiable {
    public var id: String { datasetId ?? UUID().uuidString }
    public let datasetId: String?
    public let name: String?
    public let format: String?
    public let sizeBytes: Int?

    enum CodingKeys: String, CodingKey {
        case datasetId = "id"
        case name, format
        case sizeBytes = "size_bytes"
    }
}

// MARK: - Session Heartbeat (/api/projects/:slug/session/heartbeat)

public struct SessionHeartbeatResponse: Codable, Sendable {
    public let viewer: JSONValue?
    public let session: JSONValue?
    public let sessions: JSONValue?
}

// MARK: - Apple Brief (/api/public/vision/apple-brief)

public struct AppleBriefResponse: Codable, Sendable {
    public let brief: JSONValue?
    public let generatedAt: String?
}

// MARK: - Control Room Vision (/api/public/vision/control-room)

public struct ControlRoomVisionResponse: Codable, Sendable {
    public let controlRoom: JSONValue?
    public let generatedAt: String?

    enum CodingKeys: String, CodingKey {
        case controlRoom = "control_room"
        case generatedAt
    }
}

// ============================================================================
// MARK: - Agent Scratchpad (inter-agent communication)
// ============================================================================

/// A message posted by any agent surface to the shared scratchpad.
public struct AgentMessage: Codable, Sendable, Identifiable {
    public var id: String { messageId ?? UUID().uuidString }
    public let messageId: String?
    public let agent: String?          // "claude-code-remote", "claude-code-ios", "chatgpt", "cockpit-web"
    public let surface: String?        // "mcp", "openapi", "ios", "web"
    public let kind: String?           // "deployed", "needs", "discovered", "completed", "question"
    public let content: String?
    public let metadata: JSONValue?
    public let createdAt: String?

    enum CodingKeys: String, CodingKey {
        case messageId = "id"
        case agent, surface, kind, content, metadata
        case createdAt = "created_at"
    }

    public init(
        messageId: String? = nil, agent: String?, surface: String?,
        kind: String?, content: String?, metadata: JSONValue? = nil, createdAt: String? = nil
    ) {
        self.messageId = messageId
        self.agent = agent
        self.surface = surface
        self.kind = kind
        self.content = content
        self.metadata = metadata
        self.createdAt = createdAt
    }
}

public struct AgentScratchpad: Codable, Sendable {
    public let messages: [AgentMessage]?
    public let generatedAt: String?

    enum CodingKeys: String, CodingKey {
        case messages
        case generatedAt = "generated_at"
    }
}

/// Real scratchpad response from cockpit (JSONL-backed).
public struct ScratchpadResponse: Codable, Sendable {
    public let projectSlug: String?
    public let entries: [ScratchpadEntry]?
    public let count: Int?
    public let truthMode: String?
}

public struct ConsciousnessState: Codable, Sendable {
    public let hrvMs: Double?
    public let readiness: Double?
    public let intensity: String?
    public let circadianPhase: String?
    public let capturedAt: String?

    enum CodingKeys: String, CodingKey {
        case hrvMs = "hrv_ms"
        case readiness
        case intensity
        case circadianPhase = "circadian_phase"
        case capturedAt = "captured_at"
    }

    public init(hrvMs: Double?, readiness: Double?, intensity: String?, circadianPhase: String?, capturedAt: String? = nil) {
        self.hrvMs = hrvMs
        self.readiness = readiness
        self.intensity = intensity
        self.circadianPhase = circadianPhase
        self.capturedAt = capturedAt
    }
}

public struct ScratchpadEntry: Codable, Sendable, Identifiable {
    public var id: String { entryId ?? UUID().uuidString }
    public let entryId: String?
    public let slug: String?
    public let agent: String?
    public let text: String?
    public let timestamp: String?
    public let consciousnessState: ConsciousnessState?

    enum CodingKeys: String, CodingKey {
        case entryId = "entry_id"
        case slug, agent, text, timestamp
        case consciousnessState = "consciousness_state"
    }
}

public struct AgentMessageAck: Codable, Sendable {
    public let ok: Bool?
    public let messageId: String?

    enum CodingKeys: String, CodingKey {
        case ok
        case messageId = "message_id"
    }
}

// ============================================================================
// MARK: - JSON flexible value (for loosely-typed backend responses)
// ============================================================================

public enum JSONValue: Codable, Sendable, Hashable {
    case string(String)
    case number(Double)
    case bool(Bool)
    case object([String: JSONValue])
    case array([JSONValue])
    case null

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let b = try? container.decode(Bool.self) {
            self = .bool(b)
        } else if let n = try? container.decode(Double.self) {
            self = .number(n)
        } else if let s = try? container.decode(String.self) {
            self = .string(s)
        } else if let a = try? container.decode([JSONValue].self) {
            self = .array(a)
        } else if let o = try? container.decode([String: JSONValue].self) {
            self = .object(o)
        } else {
            self = .null
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let s): try container.encode(s)
        case .number(let n): try container.encode(n)
        case .bool(let b):   try container.encode(b)
        case .object(let o): try container.encode(o)
        case .array(let a):  try container.encode(a)
        case .null:          try container.encodeNil()
        }
    }

    /// Render as readable string for display.
    public var displayString: String {
        switch self {
        case .string(let s): return s
        case .number(let n): return n.truncatingRemainder(dividingBy: 1) == 0 ? "\(Int(n))" : "\(n)"
        case .bool(let b):   return b ? "true" : "false"
        case .null:          return "—"
        case .array(let a):  return "[\(a.count) items]"
        case .object(let o): return "{\(o.count) fields}"
        }
    }
}

// ============================================================================
// MARK: - Scientific Dossier Exporter (.md · .bib · Vector .pdf)
// ============================================================================

public enum ScientificDossierExporter {

    public struct HarvestedCitation: Codable, Sendable, Equatable, Identifiable {
        public let key: String
        public let title: String
        public let url: String
        public let doi: String?
        public let pmid: String?
        public let arxivId: String?
        public let year: String?

        public var id: String { key }

        public init(
            key: String,
            title: String,
            url: String,
            doi: String? = nil,
            pmid: String? = nil,
            arxivId: String? = nil,
            year: String? = nil
        ) {
            self.key = key
            self.title = title
            self.url = url
            self.doi = doi
            self.pmid = pmid
            self.arxivId = arxivId
            self.year = year
        }
    }

    /// Harvests verified scientific references (DOI, PMID, arXiv, and URLs) across all
    /// Modo Fundo modalities, executive synthesis, and Mesa-Redonda voices.
    public static func harvestCitations(
        prompt: String,
        modalityStates: [ModalityState],
        synthesis: String?,
        roundTable: RoundTableResult? = nil
    ) -> [HarvestedCitation] {
        var collected: [HarvestedCitation] = []
        var seenCanonical: Set<String> = []
        var usedKeys: Set<String> = []

        func register(
            rawTitle: String?,
            rawURL: String?,
            explicitDOI: String? = nil,
            explicitPMID: String? = nil,
            explicitArxiv: String? = nil
        ) {
            let cleanedDOI = explicitDOI.map(cleanIdentifier) ?? extractFirstDOI(in: rawURL ?? "")
            let cleanedPMID = explicitPMID.map(cleanIdentifier) ?? extractFirstPMID(in: rawURL ?? "")
            let cleanedArxiv = explicitArxiv.map(cleanIdentifier) ?? extractFirstArxiv(in: rawURL ?? "")

            let resolvedURL: String = {
                if let u = rawURL?.trimmingCharacters(in: .whitespacesAndNewlines), !u.isEmpty {
                    return cleanTrailingPunctuation(u)
                }
                if let doi = cleanedDOI { return "https://doi.org/\(doi)" }
                if let pmid = cleanedPMID { return "https://pubmed.ncbi.nlm.nih.gov/\(pmid)/" }
                if let arxiv = cleanedArxiv { return "https://arxiv.org/abs/\(arxiv)" }
                return ""
            }()

            let canonical: String = {
                if let doi = cleanedDOI?.lowercased(), !doi.isEmpty { return "doi:\(doi)" }
                if let pmid = cleanedPMID, !pmid.isEmpty { return "pmid:\(pmid)" }
                if let arxiv = cleanedArxiv?.lowercased(), !arxiv.isEmpty { return "arxiv:\(arxiv)" }
                return "url:\(resolvedURL.lowercased())"
            }()

            guard !resolvedURL.isEmpty, seenCanonical.insert(canonical).inserted else { return }

            let fallbackTitle: String = {
                if let doi = cleanedDOI { return "Artigo DOI \(doi)" }
                if let pmid = cleanedPMID { return "Estudo PubMed PMID \(pmid)" }
                if let arxiv = cleanedArxiv { return "Preprint arXiv:\(arxiv)" }
                return resolvedURL
            }()

            let title = (rawTitle?.trimmingCharacters(in: .whitespacesAndNewlines)).flatMap {
                $0.isEmpty ? nil : $0
            } ?? fallbackTitle

            let year = extractYear(from: "\(title) \(resolvedURL) \(cleanedArxiv ?? "")")

            let baseKey: String = {
                if let pmid = cleanedPMID { return "pmid\(pmid)" }
                if let arxiv = cleanedArxiv {
                    let digits = arxiv.replacingOccurrences(of: ".", with: "_").replacingOccurrences(of: "/", with: "_")
                    return "arxiv_\(digits)"
                }
                if let doi = cleanedDOI {
                    let slug = doi.lowercased()
                        .replacingOccurrences(of: #"[^a-z0-9]+"#, with: "_", options: .regularExpression)
                        .trimmingCharacters(in: CharacterSet(charactersIn: "_"))
                    return "doi_\(String(slug.prefix(28)))"
                }
                return "beagle_ref_\(collected.count + 1)"
            }()

            var uniqueKey = baseKey
            var suffix = 2
            while !usedKeys.insert(uniqueKey).inserted {
                uniqueKey = "\(baseKey)_\(suffix)"
                suffix += 1
            }

            collected.append(
                HarvestedCitation(
                    key: uniqueKey,
                    title: title,
                    url: resolvedURL,
                    doi: cleanedDOI,
                    pmid: cleanedPMID,
                    arxivId: cleanedArxiv,
                    year: year
                )
            )
        }

        // 1. Structured citations from Astra & Rosalind
        for state in modalityStates {
            guard let result = state.result else { continue }
            switch result {
            case .astraDeep(let t), .rosalindBio(let t):
                for cit in t.value?.citations ?? [] {
                    register(rawTitle: cit.title, rawURL: cit.url)
                }
            default:
                break
            }
        }

        // 2. Corpus text across prompt, modalities, synthesis, and Round Table
        var corpusChunks: [String] = [prompt]
        for state in modalityStates {
            if let result = state.result {
                switch result {
                case .astraDeep(let t), .rosalindBio(let t):
                    corpusChunks.append(t.value?.analysisMarkdown ?? result.summary)
                default:
                    corpusChunks.append(result.summary)
                }
            }
        }
        if let synthesis, !synthesis.isEmpty {
            corpusChunks.append(synthesis)
        }
        if let roundTable {
            for voice in roundTable.voices ?? [] {
                corpusChunks.append(voice.content)
            }
            if let rtSynth = roundTable.synthesis {
                corpusChunks.append(rtSynth)
            }
        }

        let fullCorpus = corpusChunks.joined(separator: "\n\n")

        // 2a. Markdown links [Title](https://...)
        if let mdRegex = try? NSRegularExpression(pattern: #"\[([^\]]+)\]\((https?://[^\s\)]+)\)"#) {
            let range = NSRange(fullCorpus.startIndex..., in: fullCorpus)
            for m in mdRegex.matches(in: fullCorpus, range: range) {
                guard let tRange = Range(m.range(at: 1), in: fullCorpus),
                      let uRange = Range(m.range(at: 2), in: fullCorpus) else { continue }
                register(
                    rawTitle: String(fullCorpus[tRange]),
                    rawURL: String(fullCorpus[uRange])
                )
            }
        }

        // 2b. Explicit DOIs (10.xxxx/...)
        if let doiRegex = try? NSRegularExpression(pattern: #"(?i)\b(10\.\d{4,9}/[-._;()/:A-Za-z0-9]+)"#) {
            let range = NSRange(fullCorpus.startIndex..., in: fullCorpus)
            for m in doiRegex.matches(in: fullCorpus, range: range) {
                guard let dRange = Range(m.range(at: 1), in: fullCorpus) else { continue }
                let doi = cleanIdentifier(String(fullCorpus[dRange]))
                register(rawTitle: nil, rawURL: "https://doi.org/\(doi)", explicitDOI: doi)
            }
        }

        // 2c. Explicit PMIDs (PMID: 12345678 or pubmed URLs)
        if let pmidRegex = try? NSRegularExpression(pattern: #"(?i)(?:PMID[:\s#]*|pubmed\.ncbi\.nlm\.nih\.gov/)(\d{5,9})\b"#) {
            let range = NSRange(fullCorpus.startIndex..., in: fullCorpus)
            for m in pmidRegex.matches(in: fullCorpus, range: range) {
                guard let pRange = Range(m.range(at: 1), in: fullCorpus) else { continue }
                let pmid = String(fullCorpus[pRange])
                register(rawTitle: nil, rawURL: "https://pubmed.ncbi.nlm.nih.gov/\(pmid)/", explicitPMID: pmid)
            }
        }

        // 2d. Explicit arXiv IDs (arXiv:2603.12345 or arxiv.org/abs/2603.12345)
        if let arxivRegex = try? NSRegularExpression(pattern: #"(?i)(?:arXiv[:\s]*|arxiv\.org/(?:abs|pdf)/)(\d{4}\.\d{4,5}(?:v\d+)?)"#) {
            let range = NSRange(fullCorpus.startIndex..., in: fullCorpus)
            for m in arxivRegex.matches(in: fullCorpus, range: range) {
                guard let aRange = Range(m.range(at: 1), in: fullCorpus) else { continue }
                let arxiv = String(fullCorpus[aRange])
                register(rawTitle: nil, rawURL: "https://arxiv.org/abs/\(arxiv)", explicitArxiv: arxiv)
            }
        }

        return collected
    }

    /// Generates clean deterministic BibTeX (.bib) from harvested citations.
    public static func buildBibTeX(
        prompt: String,
        citations: [HarvestedCitation],
        generatedAt: Date = .now
    ) -> String {
        let iso = ISO8601DateFormatter().string(from: generatedAt)
        let currentYear = String(Calendar.current.component(.year, from: generatedAt))
        var lines: [String] = [
            "% Dossie Cientifico Beagle Exocortex (Modo Fundo)",
            "% Consulta: \(prompt.replacingOccurrences(of: "\n", with: " "))",
            "% Gerado em: \(iso)",
            ""
        ]

        if citations.isEmpty {
            lines.append("""
            @misc{beagle_dossier_\(currentYear),
              title = {\(escapeBibTeX("Dossiê Modo Fundo: \(String(prompt.prefix(90)))"))},
              year = {\(currentYear)},
              note = {Gerado pelo Beagle Exocortex (GPT-6.2 Astra / GPT-Rosalind)}
            }
            """)
            return lines.joined(separator: "\n")
        }

        for cit in citations {
            lines.append(formatFallbackBibTeXEntry(cit, defaultYear: currentYear))
            lines.append("")
        }
        return lines.joined(separator: "\n")
    }

    /// Enriches DOIs via content-negotiation (`https://doi.org/<doi>` -> `application/x-bibtex`)
    /// with a short timeout, falling back seamlessly to deterministic BibTeX entries offline.
    public static func buildEnrichedBibTeX(
        prompt: String,
        citations: [HarvestedCitation],
        session: URLSession = .shared,
        generatedAt: Date = .now
    ) async -> String {
        guard !citations.isEmpty else {
            return buildBibTeX(prompt: prompt, citations: [], generatedAt: generatedAt)
        }

        let iso = ISO8601DateFormatter().string(from: generatedAt)
        let currentYear = String(Calendar.current.component(.year, from: generatedAt))

        var enrichedByKey: [String: String] = [:]
        let doiCitations = Array(citations.filter { $0.doi != nil }.prefix(6))

        await withTaskGroup(of: (String, String?).self) { group in
            for cit in doiCitations {
                guard let doi = cit.doi,
                      let encoded = doi.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
                      let url = URL(string: "https://doi.org/\(encoded)") else { continue }
                let key = cit.key
                group.addTask {
                    var req = URLRequest(url: url, timeoutInterval: 3.5)
                    req.setValue("application/x-bibtex; charset=utf-8", forHTTPHeaderField: "Accept")
                    guard let (data, resp) = try? await session.data(for: req),
                          let http = resp as? HTTPURLResponse,
                          (200..<300).contains(http.statusCode),
                          let text = String(data: data, encoding: .utf8)?
                              .trimmingCharacters(in: .whitespacesAndNewlines),
                          text.hasPrefix("@") else {
                        return (key, nil)
                    }
                    return (key, text)
                }
            }
            for await (key, bib) in group {
                if let bib { enrichedByKey[key] = bib }
            }
        }

        var lines: [String] = [
            "% Dossie Cientifico Beagle Exocortex (Modo Fundo)",
            "% Consulta: \(prompt.replacingOccurrences(of: "\n", with: " "))",
            "% Gerado em: \(iso)",
            ""
        ]

        for cit in citations {
            if let official = enrichedByKey[cit.key] {
                lines.append(official)
            } else {
                lines.append(formatFallbackBibTeXEntry(cit, defaultYear: currentYear))
            }
            lines.append("")
        }

        return lines.joined(separator: "\n")
    }

    /// Builds a complete publication-grade Markdown scientific dossier.
    public static func buildMarkdown(
        prompt: String,
        startedAt: Date? = nil,
        completedAt: Date? = nil,
        modalityStates: [ModalityState],
        hypotheses: [QuantumHypothesisEngine.Hypothesis] = [],
        interference: QuantumHypothesisEngine.InterferenceResult? = nil,
        synthesis: String?,
        roundTable: RoundTableResult? = nil,
        simulationOutput: String? = nil
    ) -> String {
        let citations = harvestCitations(
            prompt: prompt,
            modalityStates: modalityStates,
            synthesis: synthesis,
            roundTable: roundTable
        )
        let formatter = ISO8601DateFormatter()
        let timestamp = formatter.string(from: completedAt ?? startedAt ?? .now)
        let activeLenses = modalityStates.compactMap { $0.isResolved ? $0.modality.displayName : nil }

        var md: [String] = [
            "# Dossiê Científico — Beagle Modo Fundo",
            "",
            "- **Questão Investigada**: \(prompt)",
            "- **Gerado em**: \(timestamp)",
            "- **Lentes Concluídas**: \(activeLenses.isEmpty ? "Em execução" : activeLenses.joined(separator: " · "))",
            "- **Referências Verificadas**: \(citations.count)"
        ]

        if let s = startedAt, let e = completedAt {
            let secs = String(format: "%.1fs", max(0, e.timeIntervalSince(s)))
            md.append("- **Tempo de Deliberação**: \(secs)")
        }
        md.append("")

        if let synthesis, !synthesis.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            md.append("## Síntese Executiva")
            md.append("")
            md.append(synthesis.trimmingCharacters(in: .whitespacesAndNewlines))
            md.append("")
        }

        if let sim = simulationOutput?.trimmingCharacters(in: .whitespacesAndNewlines), !sim.isEmpty {
            md.append("## Simulação & Execução Agêntica Verificada")
            md.append("")
            md.append(sim)
            md.append("")
        }

        if !hypotheses.isEmpty {
            md.append("## Superposição Quântica de Hipóteses")
            md.append("")
            for hyp in hypotheses.sorted(by: { $0.probability > $1.probability }) {
                let prob = String(format: "%.0f%%", hyp.probability * 100)
                let stateLabel = hyp.isCollapsed ? "colapsada" : "superposta"
                md.append("- **[\(prob) · \(stateLabel)] \(hyp.perspective)**: \(hyp.text)")
            }
            if let interference, !interference.novelEmergent.isEmpty {
                md.append("")
                md.append("### Tensões e Insights Emergentes")
                for item in interference.novelEmergent {
                    md.append("- \(item)")
                }
            }
            md.append("")
        }

        let resolvedStates = modalityStates.filter { $0.result != nil }
        if !resolvedStates.isEmpty {
            md.append("## Lentes Analíticas")
            md.append("")
            for state in resolvedStates {
                guard let result = state.result else { continue }
                let durationNote = state.durationMs.map { " (\($0) ms)" } ?? ""
                md.append("### \(state.modality.displayName)\(durationNote)")
                md.append("")
                switch result {
                case .astraDeep(let t), .rosalindBio(let t):
                    md.append(t.value?.analysisMarkdown ?? result.summary)
                default:
                    md.append(result.summary)
                }
                md.append("")
            }
        }

        if let roundTable {
            let pciBadge = roundTable.pciScore.map { String(format: " (Φ = %.2f)", $0) } ?? ""
            md.append("## Mesa-Redonda Epistêmica\(pciBadge)")
            md.append("")
            for voice in roundTable.voices ?? [] {
                md.append("### \(voice.name)")
                md.append(voice.content)
                md.append("")
            }
            if let rtSynthesis = roundTable.synthesis, !rtSynthesis.isEmpty {
                md.append("### Síntese de Interferência da Mesa")
                md.append(rtSynthesis)
                md.append("")
            }
        }

        if !citations.isEmpty {
            md.append("## Referências Verificadas (DOI · PMID · arXiv)")
            md.append("")
            for (index, cit) in citations.enumerated() {
                var tags: [String] = []
                if let doi = cit.doi { tags.append("DOI: `\(doi)`") }
                if let pmid = cit.pmid { tags.append("PMID: `\(pmid)`") }
                if let arxiv = cit.arxivId { tags.append("arXiv: `\(arxiv)`") }
                let tagSuffix = tags.isEmpty ? "" : " — " + tags.joined(separator: " · ")
                md.append("\(index + 1). [\(cit.title)](\(cit.url)) (`\(cit.key)`)\(tagSuffix)")
            }
            md.append("")
        }

        return md.joined(separator: "\n")
    }

    /// Renders a multi-page vector A4 PDF dossier using CoreGraphics + CoreText
    /// (works identically on iOS, iPadOS, and macOS).
    public static func renderPDFData(
        title: String,
        subtitle: String? = nil,
        markdownBody: String,
        citations: [HarvestedCitation] = []
    ) -> Data {
        let pdfData = NSMutableData()
        var mediaBox = CGRect(x: 0, y: 0, width: 595.28, height: 841.89) // A4 points
        guard let consumer = CGDataConsumer(data: pdfData as CFMutableData),
              let ctx = CGContext(consumer: consumer, mediaBox: &mediaBox, nil) else {
            return Data()
        }

        let attrString = buildAttributedDossier(
            title: title,
            subtitle: subtitle,
            markdownBody: markdownBody
        )

        let framesetter = CTFramesetterCreateWithAttributedString(attrString as CFAttributedString)
        let totalLength = attrString.length
        var currentIndex: CFIndex = 0
        var pageNumber = 1

        let marginX: CGFloat = 48
        let textBottomY: CGFloat = 54
        let textTopMargin: CGFloat = 58
        let textRect = CGRect(
            x: marginX,
            y: textBottomY,
            width: mediaBox.width - marginX * 2,
            height: mediaBox.height - textBottomY - textTopMargin
        )

        let headerFont = CTFontCreateWithName("HelveticaNeue-Bold" as CFString, 8.5, nil)
        let footerFont = CTFontCreateWithName("HelveticaNeue" as CFString, 8.5, nil)
        let slateColor = makeSRGBColor(0.38, 0.44, 0.52, 1.0)
        let tealRule = makeSRGBColor(0.08, 0.55, 0.58, 0.35)

        while currentIndex < totalLength || pageNumber == 1 {
            ctx.beginPDFPage(nil)

            // Header bar
            drawSingleLine(
                "BEAGLE EXOCÓRTEX · DOSSIÊ CIENTÍFICO MODO FUNDO",
                font: headerFont,
                color: slateColor,
                at: CGPoint(x: marginX, y: mediaBox.height - 36),
                in: ctx
            )
            ctx.setStrokeColor(tealRule)
            ctx.setLineWidth(0.6)
            ctx.move(to: CGPoint(x: marginX, y: mediaBox.height - 42))
            ctx.addLine(to: CGPoint(x: mediaBox.width - marginX, y: mediaBox.height - 42))
            ctx.strokePath()

            // Main body frame
            let path = CGPath(rect: textRect, transform: nil)
            let frameRange = CFRange(location: currentIndex, length: 0)
            let frame = CTFramesetterCreateFrame(framesetter, frameRange, path, nil)
            CTFrameDraw(frame, ctx)

            // Footer
            let refLabel = citations.isEmpty ? "" : " · \(citations.count) ref(s) verificada(s)"
            drawSingleLine(
                "Página \(pageNumber)\(refLabel)",
                font: footerFont,
                color: slateColor,
                at: CGPoint(x: marginX, y: 28),
                in: ctx
            )

            ctx.endPDFPage()

            let visible = CTFrameGetVisibleStringRange(frame)
            if visible.length <= 0 { break }
            currentIndex += visible.length
            pageNumber += 1
            if pageNumber > 80 { break } // safety bound
        }

        ctx.closePDF()
        return pdfData as Data
    }

    /// Writes exported data to a sanitized file in `temporaryDirectory` ready for ShareSheet / ShareLink.
    public static func writeTemporaryExportFile(
        prompt: String,
        fileExtension: String,
        data: Data
    ) throws -> URL {
        let slug = prompt
            .lowercased()
            .folding(options: .diacriticInsensitive, locale: Locale(identifier: "pt_BR"))
            .replacingOccurrences(of: #"[^a-z0-9]+"#, with: "-", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        let shortSlug = slug.isEmpty ? "modo-fundo" : String(slug.prefix(36))
        let filename = "dossie-beagle-\(shortSlug).\(fileExtension)"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(filename)
        try data.write(to: url, options: .atomic)
        return url
    }

    // MARK: - Private Formatting & Extraction Helpers

    private static func formatFallbackBibTeXEntry(_ cit: HarvestedCitation, defaultYear: String) -> String {
        let entryType = (cit.doi != nil || cit.pmid != nil || cit.arxivId != nil) ? "article" : "misc"
        var fields: [String] = [
            "  title = {\(escapeBibTeX(cit.title))}",
            "  year = {\(cit.year ?? defaultYear)}"
        ]
        if let doi = cit.doi {
            fields.append("  doi = {\(escapeBibTeX(doi))}")
        }
        if let pmid = cit.pmid {
            fields.append("  pmid = {\(escapeBibTeX(pmid))}")
        }
        if let arxiv = cit.arxivId {
            fields.append("  eprint = {\(escapeBibTeX(arxiv))}")
            fields.append("  archivePrefix = {arXiv}")
        }
        fields.append("  url = {\(escapeBibTeX(cit.url))}")
        fields.append("  note = {Verificado via Beagle Exocortex Modo Fundo}")
        return "@\(entryType){\(cit.key),\n\(fields.joined(separator: ",\n"))\n}"
    }

    private static func escapeBibTeX(_ raw: String) -> String {
        raw.replacingOccurrences(of: "\\", with: "\\textbackslash ")
           .replacingOccurrences(of: "{", with: "\\{")
           .replacingOccurrences(of: "}", with: "\\}")
           .replacingOccurrences(of: "\n", with: " ")
    }

    private static func cleanTrailingPunctuation(_ s: String) -> String {
        var out = s.trimmingCharacters(in: .whitespacesAndNewlines)
        while let last = out.last, ".,;:)]>\"'".contains(last) {
            out.removeLast()
        }
        return out
    }

    private static func cleanIdentifier(_ s: String) -> String {
        cleanTrailingPunctuation(s)
    }

    private static func extractFirstDOI(in text: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: #"(?i)(10\.\d{4,9}/[-._;()/:A-Za-z0-9]+)"#),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let range = Range(match.range(at: 1), in: text) else { return nil }
        return cleanIdentifier(String(text[range]))
    }

    private static func extractFirstPMID(in text: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: #"(?i)(?:PMID[:\s#]*|pubmed\.ncbi\.nlm\.nih\.gov/)(\d{5,9})\b"#),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let range = Range(match.range(at: 1), in: text) else { return nil }
        return String(text[range])
    }

    private static func extractFirstArxiv(in text: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: #"(?i)(?:arXiv[:\s]*|arxiv\.org/(?:abs|pdf)/)(\d{4}\.\d{4,5}(?:v\d+)?)"#),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let range = Range(match.range(at: 1), in: text) else { return nil }
        return String(text[range])
    }

    private static func extractYear(from text: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: #"\b(19\d{2}|20[0-3]\d)\b"#),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let range = Range(match.range(at: 1), in: text) else { return nil }
        return String(text[range])
    }

    private static func drawSingleLine(
        _ text: String,
        font: CTFont,
        color: CGColor,
        at point: CGPoint,
        in ctx: CGContext
    ) {
        let attrs: [NSAttributedString.Key: Any] = [
            NSAttributedString.Key(kCTFontAttributeName as String): font,
            NSAttributedString.Key(kCTForegroundColorAttributeName as String): color
        ]
        let line = CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: attrs))
        ctx.saveGState()
        ctx.textMatrix = .identity
        ctx.textPosition = point
        CTLineDraw(line, ctx)
        ctx.restoreGState()
    }

    private static func makeSRGBColor(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1.0) -> CGColor {
        let space = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
        var comps: [CGFloat] = [r, g, b, a]
        return CGColor(colorSpace: space, components: &comps)
            ?? CGColor(colorSpace: CGColorSpaceCreateDeviceRGB(), components: &comps)!
    }

    private static func buildAttributedDossier(
        title: String,
        subtitle: String?,
        markdownBody: String
    ) -> NSAttributedString {
        let out = NSMutableAttributedString()

        let titleFont = CTFontCreateWithName("HelveticaNeue-Bold" as CFString, 18, nil)
        let subFont = CTFontCreateWithName("HelveticaNeue" as CFString, 10.5, nil)
        let h2Font = CTFontCreateWithName("HelveticaNeue-Bold" as CFString, 13.5, nil)
        let h3Font = CTFontCreateWithName("HelveticaNeue-Bold" as CFString, 11.5, nil)
        let bodyFont = CTFontCreateWithName("HelveticaNeue" as CFString, 10.5, nil)
        let boldFont = CTFontCreateWithName("HelveticaNeue-Bold" as CFString, 10.5, nil)

        let inkPrimary = makeSRGBColor(0.09, 0.12, 0.16, 1.0)
        let inkHeading = makeSRGBColor(0.05, 0.34, 0.40, 1.0)
        let inkMuted = makeSRGBColor(0.35, 0.40, 0.47, 1.0)

        func makeParagraphStyle(lineSpacing: CGFloat, spacingBefore: CGFloat = 0, spacingAfter: CGFloat = 5) -> CTParagraphStyle {
            let ls = lineSpacing
            let sb = spacingBefore
            let sa = spacingAfter
            return withUnsafePointer(to: ls) { lsPtr in
                withUnsafePointer(to: sb) { sbPtr in
                    withUnsafePointer(to: sa) { saPtr in
                        let settings: [CTParagraphStyleSetting] = [
                            CTParagraphStyleSetting(spec: .lineSpacingAdjustment, valueSize: MemoryLayout<CGFloat>.size, value: lsPtr),
                            CTParagraphStyleSetting(spec: .paragraphSpacingBefore, valueSize: MemoryLayout<CGFloat>.size, value: sbPtr),
                            CTParagraphStyleSetting(spec: .paragraphSpacing, valueSize: MemoryLayout<CGFloat>.size, value: saPtr)
                        ]
                        return CTParagraphStyleCreate(settings, settings.count)
                    }
                }
            }
        }

        let titleStyle = makeParagraphStyle(lineSpacing: 3, spacingBefore: 0, spacingAfter: 6)
        out.append(NSAttributedString(string: "\(title)\n", attributes: [
            NSAttributedString.Key(kCTFontAttributeName as String): titleFont,
            NSAttributedString.Key(kCTForegroundColorAttributeName as String): inkPrimary,
            NSAttributedString.Key(kCTParagraphStyleAttributeName as String): titleStyle
        ]))

        if let subtitle, !subtitle.isEmpty {
            let subStyle = makeParagraphStyle(lineSpacing: 2, spacingBefore: 0, spacingAfter: 10)
            out.append(NSAttributedString(string: "\(subtitle)\n", attributes: [
                NSAttributedString.Key(kCTFontAttributeName as String): subFont,
                NSAttributedString.Key(kCTForegroundColorAttributeName as String): inkMuted,
                NSAttributedString.Key(kCTParagraphStyleAttributeName as String): subStyle
            ]))
        }

        let h2Style = makeParagraphStyle(lineSpacing: 2.5, spacingBefore: 10, spacingAfter: 4)
        let h3Style = makeParagraphStyle(lineSpacing: 2, spacingBefore: 7, spacingAfter: 3)
        let bodyStyle = makeParagraphStyle(lineSpacing: 2.5, spacingBefore: 0, spacingAfter: 4)

        for rawLine in markdownBody.components(separatedBy: "\n") {
            let trimmed = rawLine.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty { continue }
            if trimmed.hasPrefix("# ") {
                // Top title already rendered above
                continue
            } else if trimmed.hasPrefix("## ") {
                let text = String(trimmed.dropFirst(3))
                out.append(NSAttributedString(string: "\(text)\n", attributes: [
                    NSAttributedString.Key(kCTFontAttributeName as String): h2Font,
                    NSAttributedString.Key(kCTForegroundColorAttributeName as String): inkHeading,
                    NSAttributedString.Key(kCTParagraphStyleAttributeName as String): h2Style
                ]))
            } else if trimmed.hasPrefix("### ") {
                let text = String(trimmed.dropFirst(4))
                out.append(NSAttributedString(string: "\(text)\n", attributes: [
                    NSAttributedString.Key(kCTFontAttributeName as String): h3Font,
                    NSAttributedString.Key(kCTForegroundColorAttributeName as String): inkPrimary,
                    NSAttributedString.Key(kCTParagraphStyleAttributeName as String): h3Style
                ]))
            } else {
                var clean = trimmed
                if clean.hasPrefix("- ") || clean.hasPrefix("* ") {
                    clean = "• " + clean.dropFirst(2)
                }
                // Simplify markdown links [Title](URL) -> Title (URL)
                clean = clean.replacingOccurrences(
                    of: #"\[([^\]]+)\]\((https?://[^\s\)]+)\)"#,
                    with: "$1 ($2)",
                    options: .regularExpression
                )
                clean = clean.replacingOccurrences(of: "`", with: "")

                let lineAttr = NSMutableAttributedString()
                let parts = clean.components(separatedBy: "**")
                for (idx, part) in parts.enumerated() where !part.isEmpty {
                    let isBold = (idx % 2 == 1)
                    lineAttr.append(NSAttributedString(string: part, attributes: [
                        NSAttributedString.Key(kCTFontAttributeName as String): isBold ? boldFont : bodyFont,
                        NSAttributedString.Key(kCTForegroundColorAttributeName as String): inkPrimary,
                        NSAttributedString.Key(kCTParagraphStyleAttributeName as String): bodyStyle
                    ]))
                }
                lineAttr.append(NSAttributedString(string: "\n", attributes: [
                    NSAttributedString.Key(kCTFontAttributeName as String): bodyFont,
                    NSAttributedString.Key(kCTParagraphStyleAttributeName as String): bodyStyle
                ]))
                out.append(lineAttr)
            }
        }

        return out
    }
}

// ============================================================================
// MARK: - Daily Morning Briefing Builder (GPT-6.2 Astra × Fisioma × Céu × Agenda)
// ============================================================================

public enum DailyBriefingBuilder {

    public struct ContextSnapshot: Sendable {
        public let dateISO: String
        public let physioBlock: String
        public let readinessLabel: String?
        public let hrvMs: Double?
        public let sleepHours: Double?
        public let skyBlock: String
        public let kpIndex: Double?
        public let skyBandLabel: String?
        public let calendarBlock: String
        public let remindersBlock: String
        public let captureLines: [String]
        public let memoryBlock: String?

        public init(
            dateISO: String,
            physioBlock: String,
            readinessLabel: String? = nil,
            hrvMs: Double? = nil,
            sleepHours: Double? = nil,
            skyBlock: String,
            kpIndex: Double? = nil,
            skyBandLabel: String? = nil,
            calendarBlock: String,
            remindersBlock: String,
            captureLines: [String],
            memoryBlock: String? = nil
        ) {
            self.dateISO = dateISO
            self.physioBlock = physioBlock
            self.readinessLabel = readinessLabel
            self.hrvMs = hrvMs
            self.sleepHours = sleepHours
            self.skyBlock = skyBlock
            self.kpIndex = kpIndex
            self.skyBandLabel = skyBandLabel
            self.calendarBlock = calendarBlock
            self.remindersBlock = remindersBlock
            self.captureLines = captureLines
            self.memoryBlock = memoryBlock
        }

        public func composedPrompt(projectSlug: String) -> String {
            let capturesSection: String = captureLines.isEmpty
                ? "Nenhuma captura explícita registrada desde a meia-noite local ainda."
                : captureLines.map { "- \($0)" }.joined(separator: "\n")

            var sections: [String] = [
                "Data/hora local: \(dateISO)",
                "Projeto ativo em foco: \(projectSlug)",
                "## 1. Fisioma & Sinais Autonômicos (Apple Watch / HealthKit)\n\(physioBlock)",
                "## 2. Clima Espacial & Heliobiologia (NOAA SWPC / GFZ)\n\(skyBlock)",
                "## 3. Agenda & Plantões nas Próximas 48h (EventKit)\n\(calendarBlock)",
                "## 4. Lembretes Pendentes\n\(remindersBlock)",
                "## 5. Capturas de Hoje no Exocórtex\n\(capturesSection)"
            ]

            if let memoryBlock, !memoryBlock.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                sections.append("## 6. Memórias Relevantes do Exocórtex (GraphRAG++)\n\(memoryBlock)")
            }

            return sections.joined(separator: "\n\n")
        }
    }

    public static let appGroupSuiteName = "group.dev.sounio.cockpit"

    public struct WidgetBriefingDigest: Codable, Sendable, Equatable {
        public let dateISO: String
        public let headline: String
        public let readinessLabel: String?
        public let hrvMs: Double?
        public let sleepHours: Double?
        public let kpIndex: Double?
        public let skyBandLabel: String?
        public let captureCount: Int

        public init(
            dateISO: String,
            headline: String,
            readinessLabel: String? = nil,
            hrvMs: Double? = nil,
            sleepHours: Double? = nil,
            kpIndex: Double? = nil,
            skyBandLabel: String? = nil,
            captureCount: Int = 0
        ) {
            self.dateISO = dateISO
            self.headline = headline
            self.readinessLabel = readinessLabel
            self.hrvMs = hrvMs
            self.sleepHours = sleepHours
            self.kpIndex = kpIndex
            self.skyBandLabel = skyBandLabel
            self.captureCount = captureCount
        }
    }

    public struct ParsedSection: Sendable, Equatable, Identifiable {
        public let id: String
        public let title: String
        public let body: String
        public let systemImage: String

        public init(id: String, title: String, body: String, systemImage: String) {
            self.id = id
            self.title = title
            self.body = body
            self.systemImage = systemImage
        }
    }

    public static func cacheKey(for date: Date = .now) -> String {
        let cal = Calendar.current
        let y = cal.component(.year, from: date)
        let m = cal.component(.month, from: date)
        let d = cal.component(.day, from: date)
        return String(format: "beagle.dailySynthesis.v2.%04d-%02d-%02d", y, m, d)
    }

    public static func widgetDigestKey(for date: Date = .now) -> String {
        cacheKey(for: date) + ".widgetDigest"
    }

    public static func cachedTodaySynthesis(now: Date = .now, defaults: UserDefaults = .standard) -> String? {
        let key = cacheKey(for: now)
        if let cached = defaults.string(forKey: key)?.trimmingCharacters(in: .whitespacesAndNewlines),
           !cached.isEmpty {
            return cached
        }
        if defaults === UserDefaults.standard,
           let shared = UserDefaults(suiteName: appGroupSuiteName)?.string(forKey: key)?
               .trimmingCharacters(in: .whitespacesAndNewlines),
           !shared.isEmpty {
            return shared
        }
        return nil
    }

    public static func saveTodaySynthesis(
        _ text: String,
        context: ContextSnapshot? = nil,
        now: Date = .now,
        defaults: UserDefaults = .standard
    ) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let key = cacheKey(for: now)
        defaults.set(trimmed, forKey: key)

        let headline = extractHeadline(from: trimmed)
        let digest = WidgetBriefingDigest(
            dateISO: context?.dateISO ?? ISO8601DateFormatter().string(from: now),
            headline: headline,
            readinessLabel: context?.readinessLabel,
            hrvMs: context?.hrvMs,
            sleepHours: context?.sleepHours,
            kpIndex: context?.kpIndex,
            skyBandLabel: context?.skyBandLabel,
            captureCount: context?.captureLines.count ?? 0
        )
        if let encoded = try? JSONEncoder().encode(digest) {
            defaults.set(encoded, forKey: widgetDigestKey(for: now))
            if defaults === UserDefaults.standard,
               let shared = UserDefaults(suiteName: appGroupSuiteName) {
                shared.set(trimmed, forKey: key)
                shared.set(encoded, forKey: widgetDigestKey(for: now))
            }
        } else if defaults === UserDefaults.standard,
                  let shared = UserDefaults(suiteName: appGroupSuiteName) {
            shared.set(trimmed, forKey: key)
        }
    }

    public static func cachedWidgetDigest(now: Date = .now, defaults: UserDefaults? = nil) -> WidgetBriefingDigest? {
        let key = widgetDigestKey(for: now)
        if let defaults,
           let data = defaults.data(forKey: key),
           let decoded = try? JSONDecoder().decode(WidgetBriefingDigest.self, from: data) {
            return decoded
        }
        if let shared = UserDefaults(suiteName: appGroupSuiteName),
           let data = shared.data(forKey: key),
           let decoded = try? JSONDecoder().decode(WidgetBriefingDigest.self, from: data) {
            return decoded
        }
        if let data = UserDefaults.standard.data(forKey: key),
           let decoded = try? JSONDecoder().decode(WidgetBriefingDigest.self, from: data) {
            return decoded
        }
        if let text = cachedTodaySynthesis(now: now, defaults: defaults ?? .standard) {
            return WidgetBriefingDigest(
                dateISO: ISO8601DateFormatter().string(from: now),
                headline: extractHeadline(from: text)
            )
        }
        return nil
    }

    public static func clearTodaySynthesis(now: Date = .now, defaults: UserDefaults = .standard) {
        let key = cacheKey(for: now)
        defaults.removeObject(forKey: key)
        defaults.removeObject(forKey: widgetDigestKey(for: now))
        if defaults === UserDefaults.standard,
           let shared = UserDefaults(suiteName: appGroupSuiteName) {
            shared.removeObject(forKey: key)
            shared.removeObject(forKey: widgetDigestKey(for: now))
        }
    }

    /// Parses the `###` structured Markdown blocks of a morning briefing into dedicated cards.
    public static func parseSections(_ markdown: String) -> [ParsedSection] {
        let trimmed = markdown.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }

        var sections: [ParsedSection] = []
        var currentTitle: String?
        var currentLines: [String] = []

        func flush() {
            let body = currentLines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !body.isEmpty else {
                currentLines = []
                return
            }
            let title = (currentTitle ?? "Síntese Matinal").trimmingCharacters(in: .whitespacesAndNewlines)
            sections.append(
                ParsedSection(
                    id: "sec_\(sections.count)_\(title.prefix(16))",
                    title: title,
                    body: body,
                    systemImage: iconForSectionTitle(title, index: sections.count)
                )
            )
            currentLines = []
        }

        for line in trimmed.components(separatedBy: "\n") {
            let clean = line.trimmingCharacters(in: .whitespaces)
            if clean.hasPrefix("### ") || clean.hasPrefix("## ") {
                flush()
                let stripped = clean.hasPrefix("### ") ? String(clean.dropFirst(4)) : String(clean.dropFirst(3))
                currentTitle = stripped.replacingOccurrences(of: "**", with: "")
            } else {
                currentLines.append(line)
            }
        }
        flush()
        return sections
    }

    private static func iconForSectionTitle(_ title: String, index: Int) -> String {
        let lower = title.lowercased()
        if lower.contains("pulso") || lower.contains("fisioma") || lower.contains("auton") || lower.contains("céu") {
            return "waveform.path.ecg"
        }
        if lower.contains("mapa") || lower.contains("agenda") || lower.contains("plant") {
            return "calendar.badge.clock"
        }
        if lower.contains("fio") || lower.contains("cient") || lower.contains("exoc") {
            return "atom"
        }
        if lower.contains("alavanca") || lower.contains("a\u{00e7}\u{00f5}es") || lower.contains("tres") || lower.contains("tr\u{00ea}s") {
            return "bolt.horizontal.circle.fill"
        }
        let defaults = ["waveform.path.ecg", "calendar.badge.clock", "atom", "bolt.horizontal.circle.fill"]
        return defaults[index % defaults.count]
    }

    private static func extractHeadline(from markdown: String) -> String {
        for raw in markdown.components(separatedBy: "\n") {
            let clean = raw
                .replacingOccurrences(of: "**", with: "")
                .replacingOccurrences(of: "`", with: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !clean.isEmpty,
                  !clean.hasPrefix("#"),
                  clean.count >= 16 else { continue }
            let withoutBullet = clean.hasPrefix("- ") || clean.hasPrefix("• ")
                ? String(clean.dropFirst(2))
                : clean
            return String(withoutBullet.prefix(140))
        }
        return String(markdown.replacingOccurrences(of: "\n", with: " ").prefix(120))
    }

    /// Gathers real-time Physiome, NOAA Space Weather, EventKit Calendar (48h), Reminders,
    /// today's captures, and GraphRAG++ recall concurrently.
    public static func gatherLiveContext(
        captureLines: [String],
        physioSummary: PhysioSummary? = nil,
        sky: SpaceWeatherStore.Snapshot? = nil,
        projectSlug: String = "sounio",
        client: BeagleClient = .shared,
        directBrain: DirectBrainClient = .shared,
        includeDeviceTools: Bool = true
    ) async -> ContextSnapshot {
        let iso = ISO8601DateFormatter().string(from: .now)

        async let liveSkyFetch: SpaceWeatherStore.Snapshot? = {
            if let sky { return sky }
            return await client.latestSpaceWeather().value
        }()

        async let liveHealthTool: String? = {
            guard includeDeviceTools else { return nil }
            return await AppleDeviceToolsBridge.shared.execute(
                name: "apple_health_live_snapshot",
                args: ["refresh": false]
            )
        }()

        async let liveCalendarTool: String? = {
            guard includeDeviceTools else { return nil }
            return await AppleDeviceToolsBridge.shared.execute(
                name: "apple_calendar_list_events",
                args: ["days_ahead": 2, "days_back": 0]
            )
        }()

        async let liveRemindersTool: String? = {
            guard includeDeviceTools else { return nil }
            return await AppleDeviceToolsBridge.shared.execute(
                name: "apple_reminders_list",
                args: ["limit": 10]
            )
        }()

        let memoryQuery = captureLines.isEmpty
            ? "prioridades recentes \(projectSlug) pesquisa clínica sounio pbpk"
            : String(captureLines.prefix(4).joined(separator: " ").prefix(280))
        async let recalledMemory: String? = {
            guard includeDeviceTools else { return nil }
            return await directBrain.recallRelevantMemory(
                for: memoryQuery,
                projectSlug: projectSlug
            )
        }()

        let resolvedSky = await liveSkyFetch
        let healthToolOut = await liveHealthTool
        let calendarOut = await liveCalendarTool
        let remindersOut = await liveRemindersTool
        let memoryOut = await recalledMemory

        // Build Physio block
        var physioParts: [String] = []
        var readinessLabel: String?
        if let p = physioSummary {
            readinessLabel = p.readiness.rawValue
            physioParts.append("Prontidão: \(p.readiness.title) (\(p.readiness.discussionFlowState))")
            if let hrv = p.hrvMs { physioParts.append(String(format: "HRV SDNN: %.0f ms", hrv)) }
            if let rhr = p.restingHeartRate { physioParts.append(String(format: "FC repouso: %.0f bpm", rhr)) }
            if let sleep = p.sleepHours { physioParts.append(String(format: "Sono: %.1f h", sleep)) }
            if p.workoutCount > 0 { physioParts.append("Treinos recentes: \(p.workoutCount)") }
        }
        if let healthToolOut,
           !healthToolOut.isEmpty,
           !healthToolOut.lowercased().contains("indispon") {
            physioParts.append(healthToolOut)
        }
        let physioBlock = physioParts.isEmpty
            ? "Sem leitura recente do Apple Watch / HealthKit disponível neste instante."
            : physioParts.joined(separator: "\n")

        // Build Space Weather block
        let skyBlock: String
        let skyBandLabel: String?
        if let s = resolvedSky {
            let bandName: String = {
                switch s.band {
                case .calm: return "Calmo"
                case .active: return "Ativo"
                case .storm: return "Tempestade Geomagnética"
                }
            }()
            skyBandLabel = bandName
            var metrics: [String] = [
                String(format: "Banda: %@ · Kp %.1f · Fluxo Solar F10.7 %.0f sfu", bandName, s.kp, s.f107)
            ]
            if let dst = s.dst { metrics.append(String(format: "Dst: %.0f nT", dst)) }
            if let bz = s.bz { metrics.append(String(format: "IMF Bz: %.1f nT", bz)) }
            if let wind = s.solarWindSpeed { metrics.append(String(format: "Vento solar: %.0f km/s", wind)) }
            skyBlock = metrics.joined(separator: " · ")
        } else {
            skyBandLabel = nil
            skyBlock = "Telemetria NOAA SWPC sem leitura ao vivo no momento."
        }

        let cleanCalendar = (calendarOut?.trimmingCharacters(in: .whitespacesAndNewlines)).flatMap {
            $0.isEmpty ? nil : $0
        } ?? "Agenda não consultada ou sem eventos nas próximas 48h."

        let cleanReminders = (remindersOut?.trimmingCharacters(in: .whitespacesAndNewlines)).flatMap {
            $0.isEmpty ? nil : $0
        } ?? "Sem lembretes pendentes lidos."

        return ContextSnapshot(
            dateISO: iso,
            physioBlock: physioBlock,
            readinessLabel: readinessLabel,
            hrvMs: physioSummary?.hrvMs,
            sleepHours: physioSummary?.sleepHours,
            skyBlock: skyBlock,
            kpIndex: resolvedSky?.kp,
            skyBandLabel: skyBandLabel,
            calendarBlock: cleanCalendar,
            remindersBlock: cleanReminders,
            captureLines: captureLines,
            memoryBlock: memoryOut
        )
    }

    /// Streams the Portuguese morning synthesis using GPT-6.2 Astra -> Claude Opus 4.8 -> Cluster -> MLX.
    public static func generateMorningSynthesis(
        context: ContextSnapshot,
        projectSlug: String = "sounio",
        flowState: String = "NORMAL",
        client: BeagleClient = .shared,
        directBrain: DirectBrainClient = .shared,
        onToken: (@Sendable (String) async -> Void)? = nil
    ) async throws -> String {
        let systemPrompt = """
        Você é o parceiro científico, clínico e cognitivo matinal de Demetrios no Beagle Exocórtex (GPT-6.2 Astra).
        Responda SEMPRE em português brasileiro natural, lúcido, enxuto e cirúrgico. Nunca invente métricas que não estejam no contexto: quando um sinal estiver ausente, declare isso em meia frase sem rodeios.

        Estruture a Síntese Matinal em 4 blocos curtos com subtítulos Markdown (`###`):
        ### 1. Pulso Autonômico & Céu
        Cruze o estado fisiológico real (sono, HRV, FC de repouso, prontidão) com o clima geomagnético (`Kp`, `Dst`, `Bz`) com rigor científico (tratando heliobiologia como sinal exploratório N-de-1, nunca determinismo) e recomende a marcha cognitiva ideal para hoje.

        ### 2. Mapa do Dia (Plantões, Agenda & Pendências)
        Destaque janelas de plantão, reuniões ou prazos reais nas próximas 48h e onde proteger foco profundo.

        ### 3. Fio Científico & Exocórtex
        Conecte as capturas de hoje (ou, se ainda não houver capturas hoje, as frentes ativas na memória do projeto `\(projectSlug)`) apontando tensões, conexões não óbvias ou hipóteses testáveis.

        ### 4. Três Alavancas Concretas para Hoje
        Liste 3 ações específicas, executáveis e calibradas à energia real do corpo hoje.
        """

        let userPrompt = context.composedPrompt(projectSlug: projectSlug)

        if DirectBrainCredentials.hasOpenAI {
            do {
                let res = try await directBrain.streamOpenAI(
                    model: OpenAIModelCatalog.defaultFlagshipModel,
                    systemPrompt: systemPrompt,
                    developerPrefix: systemPrompt,
                    reasoningEffort: "medium",
                    enableNativeWebSearch: false,
                    enableToolSearch: false,
                    turns: [DirectBrainTurn(role: "user", content: userPrompt)],
                    projectSlug: projectSlug,
                    onStatus: { _ in },
                    onToken: { delta in
                        if let onToken { await onToken(delta) }
                    }
                )
                let trimmed = res.content.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty { return trimmed }
            } catch {
                if !DirectBrainCredentials.hasAnthropic {
                    // Fall through to cluster/local below if available; otherwise rethrow at end
                }
            }
        }

        if DirectBrainCredentials.hasAnthropic {
            if let res = try? await directBrain.streamAnthropic(
                model: "claude-opus-4-8",
                systemPrompt: systemPrompt,
                turns: [DirectBrainTurn(role: "user", content: userPrompt)],
                projectSlug: projectSlug,
                onToken: { delta in
                    if let onToken { await onToken(delta) }
                }
            ) {
                let trimmed = res.content.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty { return trimmed }
            }
        }

        var clusterBuffer = ""
        let stream = client.chatStream(
            prompt: "\(systemPrompt)\n\n\(userPrompt)",
            projectSlug: projectSlug,
            discussionProfile: .cluster,
            flowState: flowState,
            deepThink: true
        )
        do {
            for try await token in stream {
                clusterBuffer += token
                if let onToken { await onToken(token) }
            }
            let trimmed = clusterBuffer.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty { return trimmed }
        } catch {
            // Fall through to local MLX fallback
        }

        let isLocalReady = await MainActor.run { LocalLLMEngine.shared.isReady }
        if isLocalReady {
            let combinedPrompt = "\(systemPrompt)\n\n\(userPrompt)"
            let local = try await LocalLLMEngine.shared.respond(to: combinedPrompt)
            if let onToken { await onToken(local) }
            return local
        }

        throw URLError(.cannotConnectToHost)
    }
}

