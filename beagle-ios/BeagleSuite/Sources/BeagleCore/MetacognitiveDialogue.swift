//
//  MetacognitiveDialogue.swift
//  BeagleCore
//
//  The metacognitive layer — the system that observes the observer.
//  Monitors consciousness quality, stagnation, readiness decline,
//  and proactively generates suggestions to improve cognitive performance.
//
//  This is genuine functional metacognition: the exocortex reflects
//  on its own processing quality and the researcher's cognitive state,
//  then acts on that reflection.
//

import Foundation
import Observation

@Observable
@MainActor
public final class MetacognitiveDialogue {
    public static let shared = MetacognitiveDialogue()

    /// Active metacognitive observations
    public var observations: [MetacognitiveObservation] = []

    /// The current metacognitive state summary
    public var currentState: MetacognitiveState = .nominal

    /// Journal of cognitive transitions over time
    public var journal: [MetacognitiveJournalEntry] = []

    private var lastCheckedAt: Date?
    private var readinessHistory: [(date: Date, readiness: Double)] = []

    private init() {}

    /// Run a metacognitive check — call periodically (every 5-10 min) or after significant events
    public func observe(
        consciousnessScore: ConsciousnessScore?,
        stagnation: Double,
        posture: CognitivePosture,
        thoughtCount: Int,
        timeSinceLastCapture: TimeInterval?
    ) {
        var newObservations: [MetacognitiveObservation] = []

        // Track readiness over time
        if let r = posture.readiness {
            readinessHistory.append((date: Date(), readiness: r))
            if readinessHistory.count > 100 { readinessHistory.removeFirst() }
        }

        // 1. Low consciousness quality after Triad review
        if let score = consciousnessScore, score.pci < 0.4 {
            newObservations.append(.init(
                type: .lowConsciousness,
                message: "Your last Triad review showed surface-level engagement (\u{03A6}\u{2248}\(String(format: "%.2f", score.pci))). Try quantum mode for deeper exploration, or switch to a different model personality.",
                severity: .suggestion,
                action: .tryQuantumMode
            ))
        }

        // 2. Thought stagnation
        if stagnation > 0.6 {
            let days = estimateStagnationDuration()
            newObservations.append(.init(
                type: .stagnation,
                message: "You've been circling the same topic\(days > 1 ? " for \(days) days" : ""). Should I inject chaos from a different domain?",
                severity: .nudge,
                action: .injectSerendipity
            ))
        }

        // 3. Readiness decline over the day
        if let decline = readinessDecline(), decline > 0.3 {
            newObservations.append(.init(
                type: .readinessDrop,
                message: "Your cognitive readiness dropped \(Int(decline * 100))% since this morning. Consider saving complex thinking for tomorrow.",
                severity: .gentle,
                action: .reduceIntensity
            ))
        }

        // 4. Long silence — an INVITATION, never a demand. Raised 2h→8h so it stops nagging;
        //    an intimate companion doesn't police productivity. pt-BR, warm, no guilt.
        if let silence = timeSinceLastCapture, silence > 3600 * 8 {  // 8+ hours
            let hours = Int(silence / 3600)
            newObservations.append(.init(
                type: .silence,
                message: "Faz \(hours)h que nada passa por aqui. Se tiver algo pra soltar, o espaço é seu — sem pressa.",
                severity: .gentle,
                action: .promptCapture
            ))
        }

        // 5. Exceptional flow state
        if let r = posture.readiness, r > 0.8 && stagnation < 0.2 {
            newObservations.append(.init(
                type: .flow,
                message: "You're in deep flow \u{2014} high readiness, fresh thinking. This is your peak window for GoDeep.",
                severity: .celebration,
                action: .suggestGoDeep
            ))
        }

        // 6. Circadian mismatch — deep work at wrong time
        let hour = Calendar.current.component(.hour, from: .now)
        if hour >= 22 && posture.suggestedIntensity == .challenge {
            newObservations.append(.init(
                type: .circadianMismatch,
                message: "It's late but your body says go. Capture the spark now, refine tomorrow.",
                severity: .gentle,
                action: .quickCapture
            ))
        }

        // Update state
        observations = newObservations
        currentState = deriveState(from: newObservations)
        lastCheckedAt = Date()

        // Journal significant transitions
        if !newObservations.isEmpty {
            journal.append(MetacognitiveJournalEntry(
                observations: newObservations.map { $0.type },
                state: currentState,
                readiness: posture.readiness,
                stagnation: stagnation,
                pci: consciousnessScore?.pci
            ))
            if journal.count > 200 { journal.removeFirst() }
        }
    }

    /// Dismiss an observation
    public func dismiss(_ id: UUID) {
        observations.removeAll { $0.id == id }
    }

    private func readinessDecline() -> Double? {
        let today = readinessHistory.filter {
            Calendar.current.isDateInToday($0.date)
        }
        guard let morning = today.first, let now = today.last, today.count >= 2 else { return nil }
        return morning.readiness - now.readiness
    }

    private func estimateStagnationDuration() -> Int {
        // Rough estimate based on journal entries showing stagnation
        let stagnationEntries = journal.suffix(20).filter {
            $0.observations.contains(.stagnation) && $0.stagnation ?? 0 > 0.5
        }
        guard let first = stagnationEntries.first else { return 0 }
        return max(1, Calendar.current.dateComponents([.day], from: first.timestamp, to: Date()).day ?? 0)
    }

    private func deriveState(from observations: [MetacognitiveObservation]) -> MetacognitiveState {
        if observations.contains(where: { $0.type == .flow }) { return .flow }
        if observations.contains(where: { $0.type == .lowConsciousness }) { return .surfaceThinking }
        if observations.contains(where: { $0.type == .stagnation }) { return .stagnating }
        if observations.contains(where: { $0.type == .readinessDrop }) { return .fatigued }
        return .nominal
    }
}

// MARK: - MetacognitiveObservation

public struct MetacognitiveObservation: Identifiable, Sendable {
    public let id = UUID()
    public let type: ObservationType
    public let message: String
    public let severity: Severity
    public let action: SuggestedAction

    public enum ObservationType: String, Codable, Sendable {
        case lowConsciousness, stagnation, readinessDrop, silence, flow, circadianMismatch
    }

    public enum Severity: String, Sendable {
        case celebration  // positive — flow state, breakthrough
        case suggestion   // neutral — try something different
        case nudge        // gentle push
        case gentle       // soft observation, no pressure
    }

    public enum SuggestedAction: String, Sendable {
        case tryQuantumMode, injectSerendipity, reduceIntensity
        case promptCapture, suggestGoDeep, quickCapture, none
    }
}

// MARK: - MetacognitiveState

public enum MetacognitiveState: String, Codable, Sendable {
    case flow            // optimal — high readiness, fresh ideas
    case nominal         // normal operation
    case surfaceThinking // low PCI — shallow engagement
    case stagnating      // repeating same topics
    case fatigued        // readiness declining
}

// MARK: - MetacognitiveJournalEntry

public struct MetacognitiveJournalEntry: Codable, Sendable {
    public let timestamp: Date
    public let observations: [MetacognitiveObservation.ObservationType]
    public let state: MetacognitiveState
    public let readiness: Double?
    public let stagnation: Double?
    public let pci: Double?

    public init(
        observations: [MetacognitiveObservation.ObservationType],
        state: MetacognitiveState,
        readiness: Double?,
        stagnation: Double?,
        pci: Double?
    ) {
        self.timestamp = Date()
        self.observations = observations
        self.state = state
        self.readiness = readiness
        self.stagnation = stagnation
        self.pci = pci
    }
}
