//
//  GoDeepModels.swift
//  BeagleCore
//
//  Core GoDeep types (modality enum, unified result container, frontier research
//  payloads, session metadata, and flexible JSONValue).
//
//  Domain decomposition (under BeagleCore/GoDeep/):
//  - GoDeepReasoningResponses.swift : beagle-core reasoning & research response models
//  - GoDeepCockpitModels.swift      : cockpit endpoint & agent scratchpad models
//  - ScientificDossierExporter.swift: citation harvesting, BibTeX, Markdown & vector PDF export
//  - DailyBriefingBuilder.swift     : daily morning briefing context, cache & synthesis builder
//
//  Convention: all public, Codable, Sendable, optional fields,
//  CodingKeys for snake_case JSON mapping.
//

import Foundation
import SwiftUI

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
