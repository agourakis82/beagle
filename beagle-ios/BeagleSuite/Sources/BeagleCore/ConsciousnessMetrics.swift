//
//  ConsciousnessMetrics.swift
//  BeagleCore
//
//  Perturbational Complexity Index (PCI) proxy for the exocortex.
//  Measures the "consciousness quality" of a Triad interaction:
//  how integrated and differentiated the agents' responses are.
//
//  Background: IIT proposes Phi as a consciousness metric but it is
//  computationally intractable. PCI is the clinically validated proxy:
//  perturb the system, measure response complexity.
//
//  High PCI (>0.7): Rich, interdependent, non-redundant analysis
//  Medium PCI (0.4-0.7): Moderate integration, some redundancy
//  Low PCI (<0.4): Agents repeated each other or produced shallow output
//

import Foundation

/// Perturbational Complexity Index proxy computed over Triad agent interactions.
@MainActor
public final class ConsciousnessMetrics {
    public static let shared = ConsciousnessMetrics()
    private init() {}

    /// Compute PCI proxy from a Triad result.
    /// Based on: differentiation x integration x compression complexity.
    public func computePCI(from triad: TriadResult) -> ConsciousnessScore {
        let opinions = extractOpinionTexts(from: triad)
        guard opinions.count >= 2 else { return .empty }

        // 1. Differentiation: how different are the agents' responses?
        let differentiation = computeDifferentiation(opinions)

        // 2. Integration: how much do they reference each other's concepts?
        let integration = computeIntegration(opinions)

        // 3. Complexity: normalized compression ratio (Lempel-Ziv proxy)
        let complexity = computeComplexity(opinions)

        // 4. PCI = differentiation x integration x complexity
        let pci = differentiation * integration * complexity

        return ConsciousnessScore(
            pci: pci,
            differentiation: differentiation,
            integration: integration,
            complexity: complexity,
            agentCount: opinions.count,
            timestamp: Date()
        )
    }

    // MARK: - Differentiation (1 - average pairwise Jaccard similarity)

    private func computeDifferentiation(_ texts: [String]) -> Double {
        var totalSimilarity = 0.0
        var pairs = 0
        let wordSets = texts.map { text in
            Set(
                text.lowercased()
                    .split(separator: " ")
                    .map(String.init)
                    .filter { $0.count > 2 }  // skip trivial words
            )
        }
        for i in 0..<wordSets.count {
            for j in (i + 1)..<wordSets.count {
                let intersection = wordSets[i].intersection(wordSets[j]).count
                let union = wordSets[i].union(wordSets[j]).count
                totalSimilarity += union > 0 ? Double(intersection) / Double(union) : 0
                pairs += 1
            }
        }
        return pairs > 0 ? 1.0 - (totalSimilarity / Double(pairs)) : 0
    }

    // MARK: - Integration (cross-reference detection via shared key phrases)

    private func computeIntegration(_ texts: [String]) -> Double {
        let phrases = texts.map { extractKeyPhrases($0) }
        var crossRefs = 0
        var totalPhrases = 0
        for i in 0..<phrases.count {
            for phrase in phrases[i] {
                totalPhrases += 1
                for j in 0..<phrases.count where j != i {
                    if texts[j].lowercased().contains(phrase.lowercased()) {
                        crossRefs += 1
                        break
                    }
                }
            }
        }
        return totalPhrases > 0 ? min(Double(crossRefs) / Double(totalPhrases) * 2.0, 1.0) : 0
    }

    // MARK: - Complexity (normalized compression ratio)

    private func computeComplexity(_ texts: [String]) -> Double {
        let combined = texts.joined(separator: " ")
        let rawLength = Double(combined.utf8.count)
        guard rawLength > 0 else { return 0 }

        guard let data = combined.data(using: .utf8) else { return 0.5 }

        let compressed: Data
        do {
            compressed = try (data as NSData).compressed(using: .lzma) as Data
        } catch {
            return 0.5
        }

        let ratio = Double(compressed.count) / rawLength
        // Normalize: ratio near 1.0 = incompressible (high complexity), near 0 = redundant
        return min(ratio * 1.5, 1.0)
    }

    // MARK: - Key phrase extraction (3-word sliding window)

    private func extractKeyPhrases(_ text: String) -> [String] {
        let words = text.split(separator: " ").map(String.init)
        guard words.count >= 3 else { return [] }
        var phrases: [String] = []
        for i in 0..<(words.count - 2) {
            phrases.append(words[i..<(i + 3)].joined(separator: " "))
        }
        return phrases
    }

    // MARK: - Opinion text extraction from TriadResult

    private func extractOpinionTexts(from triad: TriadResult) -> [String] {
        let agents: [TriadAgentOpinion?] = [triad.athena, triad.hermes, triad.argos, triad.judge]
        var texts: [String] = []
        for agent in agents {
            if let text = agent?.opinion, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                texts.append(text)
            }
        }
        // Also fold in consensus if it adds substance
        if let consensus = triad.consensus,
           !consensus.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
           consensus.count > 20 {
            texts.append(consensus)
        }
        return texts
    }
}

// MARK: - ConsciousnessScore

public struct ConsciousnessScore: Sendable {
    public let pci: Double            // 0.0-1.0 overall consciousness proxy
    public let differentiation: Double // how different agents are
    public let integration: Double     // how much they cross-reference
    public let complexity: Double      // compression complexity
    public let agentCount: Int
    public let timestamp: Date

    public static let empty = ConsciousnessScore(
        pci: 0,
        differentiation: 0,
        integration: 0,
        complexity: 0,
        agentCount: 0,
        timestamp: .distantPast
    )

    public var level: String {
        if pci >= 0.7 { return "Deep" }
        if pci >= 0.4 { return "Moderate" }
        return "Surface"
    }

    public var description: String {
        "\u{03A6}\u{2248}\(String(format: "%.2f", pci)) (\(level))"
    }

    /// Short label for compact UI (e.g. gauge captions).
    public var shortLabel: String {
        String(format: "%.2f", pci)
    }
}
