//
//  CognitiveStore.swift
//  BeagleCore
//
//  Observable store for the researcher's cognitive state.
//  Aggregates: HRV, recent thoughts, Triad scores, active science jobs.
//  The central nervous system of the iOS exocortex.
//

import Foundation
import Observation

@Observable
@MainActor
public final class CognitiveStore {

    public var state: Truthful<CognitiveState> = .declared(
        CognitiveState(hrv: nil, recentDrafts: nil, triadLatest: nil, agentSessions: nil)
    )
    public var recentThoughts: [ThoughtCapture] = []
    public var activeJobs: [ScienceJob] = []
    public var lastTriad: Truthful<TriadResult>?

    public var isLoading = false
    public var isCapturing = false
    public var isReviewingTriad = false

    /// Whether beagle-server is reachable.
    public var serverReachable = false

    public init() {}

    // MARK: - Refresh cognitive state

    public func refresh() async {
        isLoading = true
        serverReachable = await BeagleClient.shared.isReachable()

        if serverReachable {
            state = await BeagleClient.shared.cognitiveState()
        }
        isLoading = false
    }

    // MARK: - Thought capture

    /// Capture a thought → HERMES refinement → returns refined text.
    /// Falls back to Foundation Models on-device if server unreachable.
    public func captureThought(text: String, source: String = "ios-keyboard") async -> ThoughtCapture? {
        isCapturing = true
        defer { isCapturing = false }

        let result = await BeagleClient.shared.captureThought(text: text, source: source)

        if let response = result.value, let refined = response.response {
            let thought = ThoughtCapture(
                nodeId: nil,
                refinedText: refined,
                rawText: text,
                source: source,
                createdAt: ISO8601DateFormatter().string(from: .now)
            )
            recentThoughts.insert(thought, at: 0)
            if recentThoughts.count > 50 { recentThoughts.removeLast() }
            return thought
        }

        // Fallback: store raw thought locally
        let fallback = ThoughtCapture(
            nodeId: nil,
            refinedText: nil,
            rawText: text,
            source: "\(source)-offline",
            createdAt: ISO8601DateFormatter().string(from: .now)
        )
        recentThoughts.insert(fallback, at: 0)
        return fallback
    }

    // MARK: - Triad review

    /// Submit draft for adversarial review. Long-running (up to 120s).
    public func submitForTriadReview(draft: String) async -> TriadResult? {
        isReviewingTriad = true
        defer { isReviewingTriad = false }

        let result = await BeagleClient.shared.runTriad(prompt: draft)
        lastTriad = result
        return result.value
    }

    // MARK: - Science jobs

    public func launchJob(kind: String) async -> ScienceJob? {
        let result = await BeagleClient.shared.startScienceJob(kind: kind)
        if let job = result.value {
            activeJobs.insert(job, at: 0)
            return job
        }
        return nil
    }

    public func refreshJobStatus(jobId: String) async {
        let result = await BeagleClient.shared.scienceJobStatus(jobId: jobId)
        if let updated = result.value, let idx = activeJobs.firstIndex(where: { $0.jobId == updated.jobId }) {
            activeJobs[idx] = updated
        }
    }

    /// Poll all running jobs.
    public func pollActiveJobs() async {
        for job in activeJobs where job.isRunning {
            if let id = job.jobId {
                await refreshJobStatus(jobId: id)
            }
        }
    }

    // MARK: - Feedback

    public func submitFeedback(runId: String, clarity: Int, adequacy: Int, notes: String?) async -> Bool {
        let event = FeedbackEvent(
            runId: runId,
            kind: "human_feedback",
            clarity: clarity,
            adequacy: adequacy,
            notes: notes
        )
        let result = await BeagleClient.shared.postFeedback(event: event)
        return result.value?.ok == true
    }

    // MARK: - Derived

    public var flowState: String {
        state.value?.hrv?.displayFlowState ?? "UNKNOWN"
    }

    public var hrvValue: Double {
        state.value?.hrv?.latestMs ?? 0
    }

    public var triadVerdict: String? {
        state.value?.triadLatest?.verdict ?? lastTriad?.value?.consensus
    }

    public var runningJobCount: Int {
        activeJobs.filter(\.isRunning).count
    }
}
