//
//  DreamSynthesisEngine.swift
//  BeagleCore
//
//  Dream Synthesis Engine — thinks while you sleep.
//  Triggered by HealthKit sleep stage detection, recombines recent thoughts
//  using serendipity and quantum engines to produce overnight insights.
//
//  During REM (when the brain consolidates memories), the exocortex runs
//  its own "dream" — recombining ideas in novel ways.
//  Wake up to insights you didn't think of.
//

import Foundation
import Observation

@Observable
@MainActor
public final class DreamSynthesisEngine {
    public static let shared = DreamSynthesisEngine()

    public var overnightInsights: [DreamInsight] = []
    public var lastDreamSession: Date?
    public var isDreaming = false

    /// Whether there are unread morning insights
    public var hasUnreadInsights: Bool {
        overnightInsights.contains { !$0.isRead }
    }

    /// Number of unread insights
    public var unreadCount: Int {
        overnightInsights.filter { !$0.isRead }.count
    }

    private init() {}

    /// Run a dream synthesis session.
    /// Call from background processing when sleep is detected,
    /// or manually from the morning brief.
    public func synthesize(thoughts: [ThoughtCapture], cognitivePosture: CognitivePosture) async {
        guard !isDreaming else { return }
        guard thoughts.count >= 3 else { return }
        isDreaming = true
        defer { isDreaming = false }

        let recent = Array(thoughts.prefix(20))
        var insights: [DreamInsight] = []

        // 1. Random recombination — pick 2-3 thoughts from different time periods and find connections
        for _ in 0..<3 {
            let shuffled = recent.shuffled()
            guard shuffled.count >= 2 else { continue }
            let a = shuffled[0]
            let b = shuffled[1]
            let c = shuffled.count > 2 ? shuffled[2] : nil

            let textA = a.refinedText ?? a.rawText ?? ""
            let textB = b.refinedText ?? b.rawText ?? ""
            let textC = c.flatMap { $0.refinedText ?? $0.rawText }

            guard !textA.isEmpty && !textB.isEmpty else { continue }

            // Extract key concepts from each
            let conceptsA = extractConcepts(textA)
            let conceptsB = extractConcepts(textB)
            let conceptsC = textC.map { extractConcepts($0) }

            // Find unexpected bridges between them
            let bridge = findBridge(conceptsA, conceptsB, conceptsC)
            if let bridge {
                insights.append(DreamInsight(
                    text: bridge,
                    sourceThoughtIds: [a.id, b.id] + (c.map { [$0.id] } ?? []),
                    sleepStage: inferSleepStage(cognitivePosture),
                    hrvAtGeneration: cognitivePosture.hrv,
                    generatedAt: Date()
                ))
            }
        }

        // 2. Quantum recombination — superpose thought themes and interfere
        let themes = recent.prefix(5).compactMap { $0.refinedText ?? $0.rawText }
        if themes.count >= 2 {
            let combinedQuestion = "What connects: \(themes.joined(separator: " AND "))"
            let hypotheses = await QuantumHypothesisEngine.shared.superpose(question: combinedQuestion)
            let interference = QuantumHypothesisEngine.shared.interfere(hypotheses)

            for emergent in interference.novelEmergent {
                insights.append(DreamInsight(
                    text: emergent,
                    sourceThoughtIds: [],
                    sleepStage: "quantum-dream",
                    hrvAtGeneration: cognitivePosture.hrv,
                    generatedAt: Date()
                ))
            }
        }

        // 3. Serendipity cross-domain — inject from an unexpected field
        let provocation = SerendipityEngine.shared.generateProvocation()
        insights.append(DreamInsight(
            text: "From \(provocation.domain): \(provocation.text)",
            sourceThoughtIds: [],
            sleepStage: "serendipity-dream",
            hrvAtGeneration: cognitivePosture.hrv,
            generatedAt: Date()
        ))

        // Store results
        overnightInsights = insights + overnightInsights
        if overnightInsights.count > 50 { overnightInsights = Array(overnightInsights.prefix(50)) }
        lastDreamSession = Date()

        // Persist to UserDefaults for morning retrieval
        persistInsights()
    }

    /// Mark an insight as read
    public func markRead(_ id: UUID) {
        if let idx = overnightInsights.firstIndex(where: { $0.id == id }) {
            overnightInsights[idx].isRead = true
            persistInsights()
        }
    }

    /// Mark all as read
    public func markAllRead() {
        for i in overnightInsights.indices { overnightInsights[i].isRead = true }
        persistInsights()
    }

    /// Load persisted insights on app launch
    public func loadPersistedInsights() {
        guard let data = UserDefaults.standard.data(forKey: "dreamInsights"),
              let decoded = try? JSONDecoder().decode([DreamInsight].self, from: data) else { return }
        overnightInsights = decoded
        lastDreamSession = UserDefaults.standard.object(forKey: "lastDreamSession") as? Date
    }

    /// Whether enough time has passed since last dream to trigger a new one
    public var shouldDreamAgain: Bool {
        guard let last = lastDreamSession else { return true }
        return Date().timeIntervalSince(last) > 12 * 3600
    }

    private func persistInsights() {
        if let data = try? JSONEncoder().encode(overnightInsights) {
            UserDefaults.standard.set(data, forKey: "dreamInsights")
        }
        UserDefaults.standard.set(lastDreamSession, forKey: "lastDreamSession")
    }

    private func extractConcepts(_ text: String) -> [String] {
        text.lowercased()
            .split(separator: " ")
            .map(String.init)
            .filter { $0.count > 4 }
            .filter { !["about", "which", "where", "their", "would", "could", "should", "being", "these", "those", "there", "after", "before"].contains($0) }
    }

    private func findBridge(_ a: [String], _ b: [String], _ c: [String]?) -> String? {
        let shared = Set(a).intersection(Set(b))
        let unique_a = Set(a).subtracting(Set(b))
        let unique_b = Set(b).subtracting(Set(a))

        if shared.isEmpty && !unique_a.isEmpty && !unique_b.isEmpty {
            // No obvious connection — the most interesting case
            let bridgeA = unique_a.prefix(2).joined(separator: "/")
            let bridgeB = unique_b.prefix(2).joined(separator: "/")
            return "Unexpected bridge: what if \(bridgeA) and \(bridgeB) are the same phenomenon seen from different scales?"
        } else if !shared.isEmpty {
            let sharedConcept = shared.first!
            return "Recurring theme '\(sharedConcept)' appears across your recent thinking \u{2014} is this convergence intentional or a hidden attractor?"
        }
        return nil
    }

    private func inferSleepStage(_ posture: CognitivePosture) -> String {
        if let sleep = posture.sleepQuality {
            if sleep > 0.5 { return "deep-rem-phase" }
            if sleep > 0.3 { return "core-sleep" }
            return "light-sleep"
        }
        return "unknown"
    }
}

public struct DreamInsight: Identifiable, Codable, Sendable {
    public let id: UUID
    public let text: String
    public let sourceThoughtIds: [String]
    public let sleepStage: String
    public let hrvAtGeneration: Double?
    public let generatedAt: Date
    public var isRead: Bool

    public init(text: String, sourceThoughtIds: [String], sleepStage: String, hrvAtGeneration: Double?, generatedAt: Date, isRead: Bool = false) {
        self.id = UUID()
        self.text = text
        self.sourceThoughtIds = sourceThoughtIds
        self.sleepStage = sleepStage
        self.hrvAtGeneration = hrvAtGeneration
        self.generatedAt = generatedAt
        self.isRead = isRead
    }
}
