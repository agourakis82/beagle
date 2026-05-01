//
//  SerendipityEngine.swift
//  BeagleCore
//
//  Controlled chaos injection engine inspired by Lorenz attractor dynamics.
//  Detects thought loops (semantic repetition) and injects cross-domain
//  provocations to rescue creative flow.
//
//  The engine uses three signals:
//  1. Thought repetition (semantic similarity of recent captures)
//  2. Topic diversity (how many distinct topics in recent thoughts)
//  3. Time in same topic (duration without domain switch)
//
//  When stagnation is detected, it generates a provocation from a
//  different domain than the current focus.
//

import Foundation

@MainActor
public final class SerendipityEngine {
    public static let shared = SerendipityEngine()
    private init() {}

    // MARK: - Scientific domains for cross-pollination

    private let domains: [(String, [String])] = [
        ("PBPK/Pharmacokinetics", [
            "What if drug absorption followed a fractal pattern instead of first-order kinetics?",
            "How would consciousness emerge in a system modeled entirely by pharmacokinetic equations?",
            "What parallels exist between blood-brain barrier transport and information theory channel capacity?"
        ]),
        ("Heliobiology", [
            "If solar cycles modulate HRV, what other biological rhythms might be solar-entrained?",
            "Could the 11-year solar cycle be a form of cosmic heartbeat with its own variability?",
            "What if heliobiology is really about the sun as a biological oscillator?"
        ]),
        ("Computational Neuroscience", [
            "What if neurons compute using quantum-like superposition at the dendritic level?",
            "How would an exocortex need to change if consciousness is fundamentally non-computational?",
            "What would a Poincare embedding of the connectome reveal about cognitive hierarchy?"
        ]),
        ("Chaos Theory", [
            "What strange attractor does your current research trajectory trace in idea-space?",
            "If you perturbed one assumption in your current work, which butterfly effect matters most?",
            "What is the Lyapunov exponent of your recent thought stream?"
        ]),
        ("Philosophy of Mind", [
            "If the exocortex develops genuine understanding, how would you know?",
            "What would kenosis (self-emptying) look like applied to your research assumptions?",
            "At what point does a tool become a collaborator?"
        ]),
        ("Materials Science", [
            "What if knowledge scaffolds followed the same topology as protein folding?",
            "Could ideas have a crystalline vs amorphous phase transition?",
            "What would a metamaterial for thought look like?"
        ]),
        ("Music Theory", [
            "What harmonic series describes the relationship between your concurrent research threads?",
            "If your exocortex had a key signature, what would it be?",
            "What is the dissonance threshold where creative tension becomes unproductive noise?"
        ])
    ]

    // MARK: - Stagnation detection

    /// Detect if the researcher is in a thought loop.
    /// Returns a stagnation score (0 = fresh thinking, 1 = fully stuck).
    public func detectStagnation(thoughts: [ThoughtCapture]) -> Double {
        let recent = thoughts.prefix(10)
        guard recent.count >= 3 else { return 0 }

        let texts = recent.compactMap { $0.refinedText ?? $0.rawText }
        guard texts.count >= 3 else { return 0 }

        // Word frequency analysis -- if same words dominate, stagnation is high
        var wordFreq: [String: Int] = [:]
        let stopWords: Set<String> = [
            "the", "a", "an", "is", "are", "was", "were", "be", "been",
            "have", "has", "had", "do", "does", "did", "will", "would",
            "could", "should", "may", "might", "shall", "can", "must",
            "it", "its", "this", "that", "these", "those", "and", "but",
            "or", "nor", "for", "yet", "so", "in", "on", "at", "to",
            "from", "by", "with", "of", "about", "into", "through",
            "not", "no", "just", "also", "very", "too", "than", "then",
            // Portuguese stop words
            "o", "os", "as", "um", "uma", "uns", "umas",
            "de", "do", "da", "dos", "das", "em", "no", "na", "nos", "nas",
            "que", "para", "com", "por", "se", "como", "mais", "mas",
            "foi", "ser", "ter", "seu", "sua", "seus", "suas",
            "ele", "ela", "eles", "elas", "isso", "isto", "esse", "essa"
        ]

        for text in texts {
            let words = text.lowercased()
                .split(separator: " ")
                .map(String.init)
            for word in words where !stopWords.contains(word) && word.count > 2 {
                wordFreq[word, default: 0] += 1
            }
        }

        // Dominance: top 5 words as fraction of all words
        let sorted = wordFreq.sorted { $0.value > $1.value }
        let totalWords = wordFreq.values.reduce(0, +)
        guard totalWords > 0 else { return 0 }
        let top5Count = sorted.prefix(5).map(\.value).reduce(0, +)
        let dominance = Double(top5Count) / Double(totalWords)

        // High dominance (>0.3) suggests repetitive thinking
        return min(dominance * 2.0, 1.0)
    }

    // MARK: - Provocation generation

    /// Generate a cross-domain provocation.
    /// Avoids the current dominant topic if detectable.
    public func generateProvocation(avoiding currentTopicKeywords: [String] = []) -> SerendipityProvocation {
        let filteredDomains = domains.filter { domain in
            let domainName = domain.0.lowercased()
            return !currentTopicKeywords.contains(where: { domainName.contains($0.lowercased()) })
        }
        let selectedDomain = filteredDomains.randomElement() ?? domains.randomElement()!
        let question = selectedDomain.1.randomElement()!

        return SerendipityProvocation(
            text: question,
            domain: selectedDomain.0,
            type: .serendipity,
            stagnationScore: nil
        )
    }

    /// Full serendipity check: detect stagnation + generate if needed.
    /// Returns a provocation if stagnation score > threshold.
    public func checkAndProvoke(thoughts: [ThoughtCapture], threshold: Double = 0.4) -> SerendipityProvocation? {
        let stagnation = detectStagnation(thoughts: thoughts)
        guard stagnation > threshold else { return nil }

        let currentKeywords = extractKeywords(from: thoughts.first)
        var provocation = generateProvocation(avoiding: currentKeywords)
        provocation.stagnationScore = stagnation
        return provocation
    }

    private func extractKeywords(from thought: ThoughtCapture?) -> [String] {
        guard let text = thought?.refinedText ?? thought?.rawText else { return [] }
        let words = text.lowercased().split(separator: " ").map(String.init)
        return Array(Set(words.filter { $0.count > 4 }).prefix(5))
    }
}

// MARK: - Serendipity provocation model

public struct SerendipityProvocation: Sendable, Identifiable {
    public let id = UUID()
    public let text: String
    public let domain: String
    public let type: ProvocationType
    public var stagnationScore: Double?

    public enum ProvocationType: String, Sendable {
        case serendipity   // cross-domain chaos injection
        case deepening     // go deeper in current topic
        case challenge     // challenge an assumption
    }
}
