//
//  SemanticSearch.swift
//  BeagleCore
//
//  On-device semantic similarity search using Apple NLEmbedding.
//  Searches recent thoughts by meaning, not just keywords.
//  Available since iOS 17 — no model download required.
//

import Foundation
import NaturalLanguage

@MainActor
public final class SemanticSearchEngine {
    public static let shared = SemanticSearchEngine()

    private var embedding: NLEmbedding?
    private var thoughtVectors: [(text: String, thought: ThoughtCapture)] = []

    private init() {}

    /// Load the sentence embedding model. Call once at launch.
    public func warmup() {
        embedding = NLEmbedding.sentenceEmbedding(for: .english)
    }

    /// Whether the embedding model loaded successfully.
    public var isAvailable: Bool { embedding != nil }

    /// Re-index the thought corpus. Call after loading or capturing thoughts.
    public func index(thoughts: [ThoughtCapture]) {
        guard embedding != nil else { return }
        thoughtVectors = thoughts.compactMap { t in
            var text = t.refinedText ?? t.rawText ?? ""
            guard !text.isEmpty else { return nil }
            // Include English translation in the indexed text for bilingual search
            if let translated = t.translatedText {
                text += " " + translated
            }
            return (text: text, thought: t)
        }
    }

    /// Semantic search over indexed thoughts.
    /// Returns matches sorted by descending cosine similarity, above a 0.3 threshold.
    public func search(query: String, limit: Int = 5) -> [(thought: ThoughtCapture, similarity: Double)] {
        guard let embedding, !thoughtVectors.isEmpty else { return [] }

        return thoughtVectors.compactMap { (text, thought) in
            let distance = embedding.distance(between: query, and: text)
            // NLEmbedding.distance returns cosine distance: 0 = identical, 2 = opposite
            let similarity = 1.0 - distance
            return (thought: thought, similarity: similarity)
        }
        .filter { $0.similarity > 0.3 }
        .sorted { $0.similarity > $1.similarity }
        .prefix(limit)
        .map { $0 }
    }

    /// Substring fallback for when the embedding model is unavailable.
    public static func substringSearch(query: String, in thoughts: [ThoughtCapture], limit: Int = 5) -> [ThoughtCapture] {
        let q = query.lowercased()
        return thoughts.filter { t in
            let text = (t.refinedText ?? t.rawText ?? "").lowercased()
            let translated = (t.translatedText ?? "").lowercased()
            return text.contains(q) || translated.contains(q)
        }
        .prefix(limit)
        .map { $0 }
    }
}
