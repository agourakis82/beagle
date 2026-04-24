//
//  ExocortexTools.swift
//  BeagleCockpit
//
//  Foundation Models tool calling for the personal exocortex.
//  Tools give the on-device 3B model access to memory, physiology, and capture.
//

#if canImport(FoundationModels)
import FoundationModels
import BeagleCore

@MainActor
final class ExocortexToolContext {
    static let shared = ExocortexToolContext()
    var cognitive: CognitiveStore?
    var physio: PhysioStore?
    private init() {}
}

@available(iOS 26, macOS 26, *)
struct SearchMemoryTool: Tool {
    let name = "searchMemory"
    let description = "Search the researcher's recent thoughts and captured ideas for relevant context."

    @Generable
    struct Arguments {
        @Guide(description: "Keywords or topic to search for")
        var query: String
    }

    func call(arguments: Arguments) async throws -> String {
        let results = await MainActor.run {
            SemanticSearchEngine.shared.search(query: arguments.query, limit: 5)
        }

        // Semantic search available and returned results
        if !results.isEmpty {
            let formatted = results.enumerated().map { i, r in
                let pct = Int((r.similarity * 100).rounded())
                return "[\(i + 1)] (\(pct)% match) \(r.thought.refinedText ?? r.thought.rawText ?? "")"
            }.joined(separator: "\n")
            return "Found \(results.count) semantically relevant thoughts:\n\(formatted)"
        }

        // Fallback: substring search when embedding unavailable or no semantic matches
        let thoughts = await MainActor.run {
            ExocortexToolContext.shared.cognitive?.recentThoughts ?? []
        }
        let query = arguments.query.lowercased()
        let matches = thoughts.filter { t in
            let text = (t.refinedText ?? t.rawText ?? "").lowercased()
            return text.contains(query)
        }.prefix(5)
        if matches.isEmpty { return "No matching thoughts found for '\(arguments.query)'." }
        let formatted = matches.enumerated().map { i, t in
            "[\(i + 1)] \(t.refinedText ?? t.rawText ?? "")"
        }.joined(separator: "\n")
        return "Found \(matches.count) relevant thoughts:\n\(formatted)"
    }
}

@available(iOS 26, macOS 26, *)
struct CaptureThoughtTool: Tool {
    let name = "captureThought"
    let description = "Save an important insight to the exocortex memory. Use when the conversation produces a novel idea worth preserving."

    @Generable
    struct Arguments {
        @Guide(description: "The insight or idea to capture")
        var thought: String
    }

    func call(arguments: Arguments) async throws -> String {
        let cognitive = await MainActor.run {
            ExocortexToolContext.shared.cognitive
        }
        guard let cognitive else {
            return "Exocortex not available."
        }
        let captured = await cognitive.captureThought(text: arguments.thought, source: "foundation-models")
        if let refined = captured?.refinedText {
            return "Thought captured and refined: \(refined)"
        }
        return "Thought captured: \(arguments.thought)"
    }
}

@available(iOS 26, macOS 26, *)
struct QueryPhysioTool: Tool {
    let name = "queryPhysio"
    let description = "Check the researcher's physiological state including HRV, sleep quality, and cognitive readiness."

    @Generable
    struct Arguments {
        @Guide(description: "What aspect to check: readiness, hrv, sleep, or all")
        var aspect: String
    }

    func call(arguments: Arguments) async throws -> String {
        let summary = await MainActor.run {
            ExocortexToolContext.shared.physio?.summary
        }
        guard let s = summary else { return "Physiological data not available." }
        return "Physiological state: \(s.detailLine)"
    }
}

@available(iOS 26, macOS 26, *)
struct SuggestExplorationTool: Tool {
    let name = "suggestExploration"
    let description = "Suggest a topic for deep multi-modal exploration when an idea is worth investigating further."

    @Generable
    struct Arguments {
        @Guide(description: "The question or topic to explore")
        var topic: String
    }

    func call(arguments: Arguments) async throws -> String {
        "Exploration suggested: \"\(arguments.topic)\" — the researcher can open Go Deeper to explore this with multiple reasoning modalities."
    }
}
#endif
