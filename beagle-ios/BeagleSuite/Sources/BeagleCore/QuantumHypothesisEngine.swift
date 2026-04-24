//
//  QuantumHypothesisEngine.swift
//  BeagleCore
//
//  Quantum-inspired hypothesis exploration engine.
//  Maintains N hypotheses in "superposition" — each explored in parallel,
//  then "interfered" (compared), and "collapsed" to the strongest.
//
//  Not quantum computing — uses quantum mechanics as a metaphor for
//  parallel exploration with interference and measurement.
//

import Foundation

@MainActor
public final class QuantumHypothesisEngine {
    public static let shared = QuantumHypothesisEngine()
    private init() {}

    // MARK: - Types

    /// A hypothesis in superposition — has amplitude (confidence) and phase (perspective).
    public struct Hypothesis: Identifiable, Sendable {
        public let id: UUID
        public let text: String
        public let perspective: String   // which angle it came from
        public var amplitude: Double     // 0.0-1.0, like quantum amplitude squared = probability
        public var phase: Double         // 0-2pi, represents the "angle" of approach
        public var isCollapsed: Bool

        /// Probability of this hypothesis being "measured" as the answer.
        public var probability: Double { amplitude * amplitude }

        public init(
            id: UUID = UUID(),
            text: String,
            perspective: String,
            amplitude: Double,
            phase: Double,
            isCollapsed: Bool = false
        ) {
            self.id = id
            self.text = text
            self.perspective = perspective
            self.amplitude = amplitude
            self.phase = phase
            self.isCollapsed = isCollapsed
        }
    }

    /// Result of interference between hypotheses.
    public struct InterferenceResult: Sendable {
        public let constructive: [(Hypothesis, Hypothesis)]  // hypotheses that reinforce each other
        public let destructive: [(Hypothesis, Hypothesis)]   // hypotheses that contradict each other
        public let novelEmergent: [String]                    // new ideas from interference

        public init(
            constructive: [(Hypothesis, Hypothesis)],
            destructive: [(Hypothesis, Hypothesis)],
            novelEmergent: [String]
        ) {
            self.constructive = constructive
            self.destructive = destructive
            self.novelEmergent = novelEmergent
        }
    }

    // MARK: - Default Perspectives

    private let defaultPerspectives = [
        "First principles",
        "Historical analogy",
        "Adversarial critique",
        "Cross-domain transfer",
        "Reductio ad absurdum"
    ]

    // MARK: - Superpose

    /// Generate N hypotheses from different perspectives for a given question.
    /// Each starts with equal amplitude in a uniform superposition.
    public func superpose(question: String, perspectives: [String]? = nil) async -> [Hypothesis] {
        let angles = perspectives ?? defaultPerspectives

        // Each perspective gets equal initial amplitude (normalized so sum of probabilities = 1)
        let initialAmplitude = 1.0 / sqrt(Double(angles.count))

        return angles.enumerated().map { index, perspective in
            let phase = (2.0 * .pi * Double(index)) / Double(angles.count)
            return Hypothesis(
                text: "\(perspective): [awaiting exploration of '\(question)']",
                perspective: perspective,
                amplitude: initialAmplitude,
                phase: phase
            )
        }
    }

    // MARK: - Interfere

    /// Interfere hypotheses — find constructive and destructive patterns.
    /// Constructive: similar content + similar phase reinforce each other.
    /// Destructive: similar topic + opposing phase create tension and emergent insights.
    public func interfere(_ hypotheses: [Hypothesis]) -> InterferenceResult {
        var constructive: [(Hypothesis, Hypothesis)] = []
        var destructive: [(Hypothesis, Hypothesis)] = []
        var emergent: [String] = []

        for i in 0..<hypotheses.count {
            for j in (i + 1)..<hypotheses.count {
                let similarity = textSimilarity(hypotheses[i].text, hypotheses[j].text)
                let phaseDiff = abs(hypotheses[i].phase - hypotheses[j].phase)

                // Constructive: similar content, similar phase
                if similarity > 0.3 && phaseDiff < .pi / 2 {
                    constructive.append((hypotheses[i], hypotheses[j]))
                }
                // Destructive: similar topic but opposing conclusions
                else if similarity > 0.2 && phaseDiff > .pi / 2 {
                    destructive.append((hypotheses[i], hypotheses[j]))
                    // Destructive interference generates emergent insights
                    emergent.append(
                        "Tension between \(hypotheses[i].perspective) and \(hypotheses[j].perspective)"
                    )
                }
            }
        }

        return InterferenceResult(
            constructive: constructive,
            destructive: destructive,
            novelEmergent: emergent
        )
    }

    // MARK: - Collapse

    /// Collapse superposition — amplify the strongest, attenuate the weakest.
    /// If `boostIndex` is provided, collapse deterministically to that hypothesis.
    /// Otherwise, natural collapse via constructive interference reinforcement.
    public func collapse(_ hypotheses: inout [Hypothesis], boostIndex: Int? = nil) {
        // Normalize amplitudes
        let totalProb = hypotheses.reduce(0.0) { $0 + $1.probability }
        guard totalProb > 0 else { return }

        // If a specific hypothesis is selected (measured), collapse to it
        if let boost = boostIndex, boost < hypotheses.count {
            for i in 0..<hypotheses.count {
                hypotheses[i].amplitude = (i == boost) ? 1.0 : 0.05
                hypotheses[i].isCollapsed = true
            }
            return
        }

        // Otherwise, natural collapse: amplify those reinforced by constructive interference
        let interference = interfere(hypotheses)
        let reinforcedIds = Set(interference.constructive.flatMap { [$0.0.id, $0.1.id] })

        for i in 0..<hypotheses.count {
            if reinforcedIds.contains(hypotheses[i].id) {
                hypotheses[i].amplitude = min(hypotheses[i].amplitude * 1.4, 1.0)
            } else {
                hypotheses[i].amplitude *= 0.7
            }
            hypotheses[i].isCollapsed = true
        }
    }

    // MARK: - Update Hypothesis Text

    /// Replace placeholder text with actual explored content, preserving amplitude and phase.
    public func evolve(
        _ hypotheses: inout [Hypothesis],
        at index: Int,
        withText text: String
    ) {
        guard index < hypotheses.count else { return }
        let old = hypotheses[index]
        hypotheses[index] = Hypothesis(
            id: old.id,
            text: text,
            perspective: old.perspective,
            amplitude: old.amplitude,
            phase: old.phase,
            isCollapsed: old.isCollapsed
        )
    }

    // MARK: - Text Similarity (Jaccard)

    private func textSimilarity(_ a: String, _ b: String) -> Double {
        let wordsA = Set(a.lowercased().split(separator: " ").map(String.init))
        let wordsB = Set(b.lowercased().split(separator: " ").map(String.init))
        let intersection = wordsA.intersection(wordsB).count
        let union = wordsA.union(wordsB).count
        return union > 0 ? Double(intersection) / Double(union) : 0
    }
}
