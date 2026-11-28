//
//  ExocortexModels.swift
//  BeagleCore
//
//  Cluster-canonical Exocortex contracts shared by iPhone, iPad, macOS,
//  visionOS, Watch, and external MCP agents.
//
//  Domain models are decomposed under `ExocortexModels/`:
//  - ExocortexIdentityHomeModels.swift: Chronoself, OmniConversation, TemporalAnalysis, Agent/Trust, Living Home continuity
//  - ExocortexMemoryGovernanceModels.swift: Memory episodes/atoms, governance/quorum/contradictions, projection, worlds, policy, context packs
//  - ExocortexBenchmarkIndexModels.swift: Memory benchmarks, truthsets, promotion gates, hot-path modes, semantic index
//  - ExocortexGraphRAGModels.swift: GraphRAG query/trace/votes, evidence graph, Memory Lens & Proof Sheet
//  - ExocortexSpatialMindPalaceModels.swift: Spatial worlds, control room, Mind Palace, desk, conversation portals, focus coach
//  - ExocortexSounioPaperRunModels.swift: Sounio programs, PaperRun, Origin Lineage, epistemic claims & moments
//  - ExocortexCaptureAuditModels.swift: Audit/memory events, multimodal capture sessions, visual evidence, assisted imports
//

import Foundation

public enum ExocortexJSONValue: Codable, Equatable, Sendable {
    case string(String)
    case number(Double)
    case bool(Bool)
    case object([String: ExocortexJSONValue])
    case array([ExocortexJSONValue])
    case null

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Double.self) {
            self = .number(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode([String: ExocortexJSONValue].self) {
            self = .object(value)
        } else {
            self = .array(try container.decode([ExocortexJSONValue].self))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let value):
            try container.encode(value)
        case .number(let value):
            try container.encode(value)
        case .bool(let value):
            try container.encode(value)
        case .object(let value):
            try container.encode(value)
        case .array(let value):
            try container.encode(value)
        case .null:
            try container.encodeNil()
        }
    }
}
