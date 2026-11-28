//
//  GoDeepReasoningResponses.swift
//  BeagleCore
//
//  Response models for beagle-core advanced reasoning and research endpoints.
//  Convention: all public, Codable, Sendable, optional fields,
//  CodingKeys for snake_case JSON mapping.
//

import Foundation

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
