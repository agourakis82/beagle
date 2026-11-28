//
//  ExocortexQuery.swift
//  BeagleCockpit
//
//  Single client-side entry point for "ask the exocortex something." Before this, three
//  screens independently reimplemented similar-but-different network paths for the same
//  underlying question — CognitiveRecallView used CognitiveAPI.recall() (cited hypergraph
//  synthesis), MemoryLensDetailView used BeagleClient.chat() (warm personal narrative), and
//  SpatialDeskMissionControlView used ExocortexStore.queryGraphMemory() for what turned out
//  to be the SAME concept as CognitiveAPI.recall() — a real bug found in this session's
//  screen-by-screen audit (it discarded the citation/confidence/source-timeline UI that
//  RecallPane already built, see SpatialDeskMissionControlView.swift's fix).
//
//  New screens should reach for ExocortexQuery.ask(...) instead of picking a client ad hoc —
//  that's the whole point of this file existing.
//

import Foundation
import BeagleCore

enum ExocortexQueryMode: Sendable {
    /// Cited synthesis over the GraphRAG++ hypergraph — citations, confidence, source
    /// timeline. Use for "what does the exocortex know about X" work/project questions.
    /// Backed by CognitiveAPI.recall() (POST /api/recall/answer).
    case citedRecall(scope: String)
    /// Warm first-person narrative over the companion's biography grounding — no
    /// citations. Use for "what do you remember about me" personal questions.
    /// Backed by BeagleClient.chat(). `lastContactAt` lets the companion know how long
    /// it's been since you last talked (continuity grounding) — pass it when known.
    case personalNarrative(projectSlug: String = "sounio", lastContactAt: Date? = nil)
}

struct ExocortexQueryResult: Sendable {
    let text: String
    /// Non-nil only for `.citedRecall` — `.personalNarrative` has no citation concept.
    let citations: [RecallSource]?
    let confidence: Double?
    let failed: Bool
}

enum ExocortexQuery {
    /// `baseURL` mirrors CognitiveAPI's `preferred` param — pass the caller's own
    /// `@AppStorage("cognitiveBaseURL")` value if it has one, else the default fallback
    /// chain (beagle.chiuratto.ai → tailnet → IP → in-cluster) is used unchanged.
    static func ask(
        _ prompt: String,
        mode: ExocortexQueryMode,
        baseURL: String = "https://beagle.chiuratto.ai"
    ) async -> ExocortexQueryResult {
        switch mode {
        case .citedRecall(let scope):
            do {
                let answer = try await CognitiveAPI(preferred: baseURL).recall(query: prompt, scope: scope)
                return ExocortexQueryResult(
                    text: answer.answer, citations: answer.sources,
                    confidence: answer.confidence, failed: false
                )
            } catch {
                return ExocortexQueryResult(
                    text: "Recall failed: \(error.localizedDescription)",
                    citations: nil, confidence: nil, failed: true
                )
            }
        case .personalNarrative(let projectSlug, let lastContactAt):
            let result = await BeagleClient.shared.chat(
                prompt: prompt, projectSlug: projectSlug, lastContactAt: lastContactAt
            )
            if let response = result.value?.response {
                return ExocortexQueryResult(text: response, citations: nil, confidence: nil, failed: false)
            }
            return ExocortexQueryResult(
                text: result.error ?? "No response from the exocortex.",
                citations: nil, confidence: nil, failed: true
            )
        }
    }
}
