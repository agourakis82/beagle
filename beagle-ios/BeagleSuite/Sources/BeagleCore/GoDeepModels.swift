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

// MARK: - GoDeep Modality Enum

public enum GoDeepModality: String, CaseIterable, Sendable, Identifiable {
    case deepResearch    = "deep-research"
    case quantumReasoning = "quantum-reasoning"
    case swarmConsensus  = "swarm-consensus"
    case causalExtract   = "causal-extract"
    case temporal        = "temporal"
    case neurosymbolic   = "neurosymbolic"
    case adversarial     = "adversarial"
    case serendipity     = "serendipity"

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .deepResearch:    return "Deep Research"
        case .quantumReasoning: return "Quantum Reasoning"
        case .swarmConsensus:  return "Swarm Consensus"
        case .causalExtract:   return "Causal Graph"
        case .temporal:        return "Temporal"
        case .neurosymbolic:   return "Neurosymbolic"
        case .adversarial:     return "Adversarial"
        case .serendipity:     return "Serendipity"
        }
    }

    public var icon: String {
        switch self {
        case .deepResearch:    return "tree"
        case .quantumReasoning: return "atom"
        case .swarmConsensus:  return "ant.fill"
        case .causalExtract:   return "arrow.triangle.branch"
        case .temporal:        return "clock.arrow.2.circlepath"
        case .neurosymbolic:   return "brain.head.profile"
        case .adversarial:     return "shield.lefthalf.filled"
        case .serendipity:     return "sparkles"
        }
    }

    public var themeColor: Color {
        switch self {
        case .deepResearch:    return BeagleTheme.truthObserved      // teal
        case .quantumReasoning: return BeagleTheme.truthRemembered   // sky blue
        case .swarmConsensus:  return BeagleTheme.postureWarm        // gold
        case .causalExtract:   return BeagleTheme.truthDeclared      // slate-purple
        case .temporal:        return BeagleTheme.textData            // cool cyan
        case .neurosymbolic:   return BeagleTheme.stateStarting      // gold
        case .adversarial:     return BeagleTheme.stateError          // red
        case .serendipity:     return Color(hue: 300/360, saturation: 0.60, brightness: 0.90) // magenta
        }
    }
}

// MARK: - GoDeep Result (unified container)

public enum GoDeepResult: Sendable {
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
        case .deepResearch(let t):
            guard let v = t.value else { return t.error ?? "No result" }
            return v.bestHypothesis ?? "Tree: \(v.treeSize ?? 0) nodes, \(v.iterations ?? 0) iterations"
        case .quantum(let t):
            guard let v = t.value else { return t.error ?? "No result" }
            if let h = v.selectedHypothesis, let p = v.probability {
                return "\(h) (p=\(String(format: "%.2f", p)))"
            }
            return "\(v.rankedHypotheses?.count ?? 0) hypotheses ranked"
        case .swarm(let t):
            guard let v = t.value else { return t.error ?? "No result" }
            return "\(v.consensus?.count ?? 0) consensus points from \(v.nAgents ?? 0) agents"
        case .causal(let t):
            guard let v = t.value else { return t.error ?? "No result" }
            return "\(v.nodes?.count ?? 0) nodes, \(v.edges?.count ?? 0) edges"
        case .temporal(let t):
            return t.value?.summary ?? t.error ?? "No result"
        case .neurosymbolic(let t):
            return t.value?.summary ?? t.error ?? "No result"
        case .adversarial(let t):
            guard let v = t.value else { return t.error ?? "No result" }
            return v.winner ?? "\(v.rounds ?? 0) rounds"
        case .serendipity(let t):
            return t.value?.summary ?? t.error ?? "No result"
        }
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
}

public struct QuantumMetadata: Codable, Sendable {
    public let totalHypotheses: Int?
    public let interferenceApplied: Bool?
    public let decoherenceApplied: Bool?
    public let processingTimeMs: Int?

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

    enum CodingKeys: String, CodingKey {
        case consensus, iterations
        case nAgents = "n_agents"
    }
}

// MARK: - Causal (/dev/causal/extract, /dev/causal/intervention)

public struct CausalGraph: Codable, Sendable {
    public let nodes: [CausalNode]?
    public let edges: [CausalEdge]?
    public let summary: String?
}

public struct CausalNode: Codable, Sendable, Identifiable {
    public var id: String { nodeId ?? UUID().uuidString }
    public let nodeId: String?
    public let label: String?
    public let type: String?

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
}

// MARK: - Neurosymbolic (/dev/neurosymbolic)

public struct NeurosymbolicResult: Codable, Sendable {
    public let result: JSONValue?
    public let summary: String?
}

// MARK: - Adversarial (/dev/adversarial-compete)

public struct AdversarialResult: Codable, Sendable {
    public let winner: String?
    public let agents: [AdversarialAgent]?
    public let rounds: Int?
    public let summary: String?
}

public struct AdversarialAgent: Codable, Sendable, Identifiable {
    public var id: String { name ?? UUID().uuidString }
    public let name: String?
    public let score: Double?
    public let strategy: String?
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
}

public struct SerendipityConnection: Codable, Sendable, Identifiable {
    public var id: String { "\(from ?? "")-\(to ?? "")" }
    public let from: String?
    public let to: String?
    public let surprise: Double?
    public let explanation: String?
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
