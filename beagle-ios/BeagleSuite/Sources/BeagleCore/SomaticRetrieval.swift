//
//  SomaticRetrieval.swift
//  BeagleCore
//
//  Somatic Retrieval — search by body state, not content.
//  Based on Damasio's somatic marker hypothesis: emotions and insights
//  are stored as body states. We tag thoughts with physiological context
//  and enable retrieval by "how you felt," not "what you said."
//

import Foundation

/// Somatic Retrieval — search by body state, not content.
@MainActor
public final class SomaticRetrieval {
    public static let shared = SomaticRetrieval()
    private init() {}

    /// A somatic query — describe a body state to search for
    public enum SomaticQuery: Sendable {
        case flow           // high HRV, high readiness, low stagnation
        case stress         // low HRV, low readiness
        case nightInsight   // captured during night hours
        case morningClarity // captured in early morning, high sleep quality
        case deepWork       // long sessions, multiple captures, high readiness
        case emotionalLow   // State of Mind < -0.3
        case custom(hrvRange: ClosedRange<Double>?, readinessRange: ClosedRange<Double>?,
                    timeRange: ClosedRange<Int>?, intensity: CognitivePosture.InterfaceIntensity?)
    }

    /// Search thoughts by somatic state
    public func search(
        query: SomaticQuery,
        thoughts: [ThoughtCapture],
        postures: [SomaticSnapshot] = []
    ) -> [SomaticMatch] {
        return thoughts.compactMap { thought in
            let score = matchScore(thought: thought, query: query, snapshots: postures)
            guard score > 0.3 else { return nil }
            return SomaticMatch(thought: thought, somaticScore: score, matchReason: describeMatch(query))
        }
        .sorted { $0.somaticScore > $1.somaticScore }
    }

    private func matchScore(thought: ThoughtCapture, query: SomaticQuery, snapshots: [SomaticSnapshot]) -> Double {
        let snapshot = findSnapshot(for: thought, in: snapshots)

        switch query {
        case .flow:
            guard let s = snapshot else { return 0 }
            let hrvScore = s.hrv.map { normalizeHRV($0) } ?? 0
            let readinessScore = s.readiness ?? 0
            return (hrvScore * 0.5 + readinessScore * 0.5)

        case .stress:
            guard let s = snapshot else { return 0 }
            let hrvScore = s.hrv.map { 1.0 - normalizeHRV($0) } ?? 0
            let readinessScore = 1.0 - (s.readiness ?? 0.5)
            return (hrvScore * 0.5 + readinessScore * 0.5)

        case .nightInsight:
            let hour = hourOfCapture(thought)
            return (hour >= 22 || hour < 5) ? 0.9 : 0.0

        case .morningClarity:
            let hour = hourOfCapture(thought)
            let sleepBonus = snapshot?.sleepQuality ?? 0
            return (hour >= 5 && hour < 9) ? (0.5 + sleepBonus * 0.5) : 0.0

        case .deepWork:
            guard let s = snapshot else { return 0 }
            return (s.readiness ?? 0) > 0.6 ? 0.8 : 0.2

        case .emotionalLow:
            guard let s = snapshot, let mood = s.stateOfMind else { return 0 }
            return mood < -0.3 ? (0.5 + abs(mood) * 0.5) : 0.0

        case .custom(let hrvRange, let readinessRange, let timeRange, let intensity):
            var score = 0.5  // base
            if let range = hrvRange, let hrv = snapshot?.hrv {
                score = range.contains(hrv) ? score + 0.2 : score - 0.3
            }
            if let range = readinessRange, let r = snapshot?.readiness {
                score = range.contains(r) ? score + 0.2 : score - 0.3
            }
            if let range = timeRange {
                let hour = hourOfCapture(thought)
                score = range.contains(hour) ? score + 0.1 : score - 0.2
            }
            if let targetIntensity = intensity, let s = snapshot {
                let posture = CognitivePosture(
                    hrv: s.hrv, respiratoryRate: nil, wristTemperature: nil,
                    sleepQuality: s.sleepQuality, stateOfMind: s.stateOfMind, observedAt: nil
                )
                score = posture.suggestedIntensity == targetIntensity ? score + 0.2 : score
            }
            return max(0, min(1, score))
        }
    }

    private func findSnapshot(for thought: ThoughtCapture, in snapshots: [SomaticSnapshot]) -> SomaticSnapshot? {
        guard let capturedStr = thought.createdAt,
              let captured = ISO8601DateFormatter().date(from: capturedStr) else {
            return snapshots.last
        }
        return snapshots.min(by: {
            abs($0.timestamp.timeIntervalSince(captured)) < abs($1.timestamp.timeIntervalSince(captured))
        })
    }

    private func hourOfCapture(_ thought: ThoughtCapture) -> Int {
        guard let str = thought.createdAt,
              let date = ISO8601DateFormatter().date(from: str) else {
            return Calendar.current.component(.hour, from: .now)
        }
        return Calendar.current.component(.hour, from: date)
    }

    private func normalizeHRV(_ ms: Double) -> Double {
        min(max((ms - 20) / 80, 0), 1)
    }

    private func describeMatch(_ query: SomaticQuery) -> String {
        switch query {
        case .flow: return "Captured during flow state"
        case .stress: return "Captured under stress"
        case .nightInsight: return "Late night insight"
        case .morningClarity: return "Morning clarity"
        case .deepWork: return "Deep work session"
        case .emotionalLow: return "Emotional processing"
        case .custom: return "Custom body state match"
        }
    }
}

// MARK: - Somatic Snapshot

/// A snapshot of somatic state at a point in time
public struct SomaticSnapshot: Codable, Sendable {
    public let timestamp: Date
    public let hrv: Double?
    public let readiness: Double?
    public let sleepQuality: Double?
    public let stateOfMind: Double?
    public let circadianPhase: String?

    public init(timestamp: Date = Date(), hrv: Double?, readiness: Double?, sleepQuality: Double?, stateOfMind: Double?, circadianPhase: String? = nil) {
        self.timestamp = timestamp
        self.hrv = hrv
        self.readiness = readiness
        self.sleepQuality = sleepQuality
        self.stateOfMind = stateOfMind
        self.circadianPhase = circadianPhase
    }

    public init(from posture: CognitivePosture, phase: String? = nil) {
        self.timestamp = Date()
        self.hrv = posture.hrv
        self.readiness = posture.readiness
        self.sleepQuality = posture.sleepQuality
        self.stateOfMind = posture.stateOfMind
        self.circadianPhase = phase
    }
}

// MARK: - Somatic Match

/// A thought matched by somatic state
public struct SomaticMatch: Identifiable, Sendable {
    public var id: String { thought.id }
    public let thought: ThoughtCapture
    public let somaticScore: Double  // 0-1
    public let matchReason: String
}
