//
//  GoDeepStore.swift
//  BeagleCore
//
//  Orchestration store for Go Deeper — fires multiple reasoning
//  modalities concurrently, tracks per-modality thinking status,
//  collects results progressively, generates synthesis.
//
//  Pattern: @Observable @MainActor, same as CognitiveStore.
//  Uses TaskGroup for concurrent modality execution.
//

import Foundation
import Observation

// MARK: - Per-Modality State

public enum ModalityPhase: Sendable {
    case waiting                       // queued but not started
    case thinking(String)              // in-flight, status message
    case resolved(GoDeepResult)        // completed with result
    case failed(String)                // error with message

    public var label: String {
        switch self {
        case .waiting:           return "waiting"
        case .thinking(let msg): return "thinking:\(msg)"
        case .resolved:          return "resolved"
        case .failed(let msg):   return "failed:\(msg)"
        }
    }
}

public struct ModalityState: Sendable, Identifiable {
    public let modality: GoDeepModality
    public var phase: ModalityPhase
    public var startedAt: Date?
    public var completedAt: Date?

    public var id: String { modality.id }
    public var isResolved: Bool {
        if case .resolved = phase { return true }
        return false
    }
    public var isFailed: Bool {
        if case .failed = phase { return true }
        return false
    }
    public var isActive: Bool {
        if case .thinking = phase { return true }
        return false
    }
    public var durationMs: Int? {
        guard let start = startedAt, let end = completedAt else { return nil }
        return Int(end.timeIntervalSince(start) * 1000)
    }
    public var result: GoDeepResult? {
        if case .resolved(let r) = phase { return r }
        return nil
    }
    public var errorMessage: String? {
        if case .failed(let msg) = phase { return msg }
        return nil
    }

    public init(modality: GoDeepModality) {
        self.modality = modality
        self.phase = .waiting
    }
}

// MARK: - Store

@Observable
@MainActor
public final class GoDeepStore {

    // MARK: - Session State

    public var activeSession: GoDeepSession?
    public var isRunning = false
    public var completedCount = 0
    public var totalCount = 0

    /// Per-modality state — always contains one entry per enabled modality.
    /// UI shows ALL of these: waiting as skeleton, thinking as animated, resolved as card.
    public var modalityStates: [ModalityState] = []

    /// Synthesis generated after all modalities complete.
    public var synthesis: String?
    public var isSynthesizing = false

    // MARK: - Configuration

    public var enabledModalities: Set<GoDeepModality> = [
        .deepResearch, .quantumReasoning, .swarmConsensus,
        .causalExtract, .neurosymbolic, .serendipity
    ]

    // MARK: - History

    public var recentSessions: [GoDeepSession] = []

    private let client = BeagleClient.shared
    private var runTask: Task<Void, Never>?

    /// Callbacks for Live Activity (set by view layer, since LiveActivityManager is in BeagleCockpit).
    public var onResearchStart: ((String, String, String) -> Void)?   // (runId, name, slug)
    public var onResearchUpdate: ((Int, Int, Int) -> Void)?           // (step, total, eta)
    public var onResearchEnd: ((String) -> Void)?                     // (finalStatus)

    public init() {}

    // MARK: - Thinking Status Messages

    private static let thinkingMessages: [GoDeepModality: [String]] = [
        .deepResearch:     ["Building research tree...", "Expanding hypotheses...", "Pruning branches..."],
        .quantumReasoning: ["Preparing superposition...", "Applying interference...", "Collapsing wavefunctions..."],
        .swarmConsensus:   ["Spawning agents...", "Agents deliberating...", "Converging on consensus..."],
        .causalExtract:    ["Parsing causal structure...", "Identifying interventions...", "Mapping dependencies..."],
        .temporal:         ["Analyzing timescales...", "Tracing temporal patterns...", "Projecting trajectories..."],
        .neurosymbolic:    ["Encoding symbolic rules...", "Neural inference running...", "Merging representations..."],
        .adversarial:      ["Assembling competitors...", "Tournament in progress...", "Scoring final round..."],
        .serendipity:      ["Scanning lateral connections...", "Measuring surprise...", "Crystallizing insights..."],
    ]

    // MARK: - Run Go Deeper

    public func goDeeper(prompt: String) {
        runTask?.cancel()
        clearState()

        let modalities = Array(enabledModalities).sorted { $0.rawValue < $1.rawValue }
        let session = GoDeepSession(prompt: prompt, modalities: modalities)
        activeSession = session
        totalCount = modalities.count
        completedCount = 0
        isRunning = true
        synthesis = nil
        isSynthesizing = false

        // Initialize all modality states as waiting
        modalityStates = modalities.map { ModalityState(modality: $0) }

        // Start Live Activity on Dynamic Island
        onResearchStart?(session.id.uuidString, "Go Deeper", "exocortex")

        runTask = Task { [client] in
            // Start thinking status animation for all modalities
            let thinkingTask = Task { await self.animateThinkingStatuses() }

            await withTaskGroup(of: (GoDeepModality, GoDeepResult)?.self) { group in
                for modality in modalities {
                    group.addTask { [client] in
                        let result = await Self.executeModality(modality, prompt: prompt, client: client)
                        return (modality, result)
                    }
                }

                for await pair in group {
                    guard !Task.isCancelled else { return }
                    if let (modality, result) = pair {
                        self.resolveModality(modality, result: result)
                        self.completedCount += 1
                    }
                }
            }

            thinkingTask.cancel()

            guard !Task.isCancelled else { return }

            // Generate synthesis
            self.isSynthesizing = true
            let synthText = await self.generateSynthesis(prompt: prompt)
            guard !Task.isCancelled else { return }
            self.synthesis = synthText
            self.isSynthesizing = false

            // End Live Activity
            self.onResearchEnd?(synthText != nil ? "complete" : "no synthesis")

            self.isRunning = false
            if var session = self.activeSession {
                session.completedAt = .now
                self.activeSession = session
                self.recentSessions.insert(session, at: 0)
                if self.recentSessions.count > 10 { self.recentSessions.removeLast() }
            }
        }
    }

    // MARK: - Execute Single Modality

    private static func executeModality(
        _ modality: GoDeepModality,
        prompt: String,
        client: BeagleClient
    ) async -> GoDeepResult {
        switch modality {
        case .deepResearch:
            return .deepResearch(await client.deepResearch(query: prompt))
        case .quantumReasoning:
            let hypotheses: [[String: any Sendable]] = [
                ["content": prompt, "initial_probability": 0.5, "confidence": 0.5, "source": "ios-user"]
            ]
            return .quantum(await client.quantumReasoning(hypotheses: hypotheses))
        case .swarmConsensus:
            return .swarm(await client.swarmConsensus(query: prompt))
        case .causalExtract:
            return .causal(await client.causalExtract(text: prompt))
        case .temporal:
            return .temporal(await client.temporalReasoning(query: prompt))
        case .neurosymbolic:
            return .neurosymbolic(await client.neurosymbolicReasoning(query: prompt))
        case .adversarial:
            return .adversarial(await client.adversarialCompete(query: prompt))
        case .serendipity:
            return .serendipity(await client.serendipityDiscover(query: prompt))
        }
    }

    // MARK: - Resolve Modality

    private func resolveModality(_ modality: GoDeepModality, result: GoDeepResult) {
        guard let idx = modalityStates.firstIndex(where: { $0.modality == modality }) else { return }
        modalityStates[idx].completedAt = .now
        if result.isError {
            modalityStates[idx].phase = .failed(result.summary)
        } else {
            modalityStates[idx].phase = .resolved(result)
        }

        // Update Live Activity progress
        onResearchUpdate?(completedCount + 1, totalCount, max(0, (totalCount - completedCount - 1) * 15))
    }

    // MARK: - Animate Thinking Statuses

    private func animateThinkingStatuses() async {
        var messageIndex = 0
        while !Task.isCancelled {
            for i in modalityStates.indices {
                guard case .waiting = modalityStates[i].phase else { continue }
                let messages = Self.thinkingMessages[modalityStates[i].modality] ?? ["Processing..."]
                modalityStates[i].phase = .thinking(messages[messageIndex % messages.count])
                modalityStates[i].startedAt = modalityStates[i].startedAt ?? .now
            }
            // Also advance thinking messages for already-active modalities
            for i in modalityStates.indices {
                guard case .thinking = modalityStates[i].phase else { continue }
                let messages = Self.thinkingMessages[modalityStates[i].modality] ?? ["Processing..."]
                modalityStates[i].phase = .thinking(messages[messageIndex % messages.count])
            }
            messageIndex += 1
            try? await Task.sleep(for: .seconds(2.5))
        }
    }

    // MARK: - Synthesis

    private func generateSynthesis(prompt: String) async -> String? {
        let summaries = modalityStates.compactMap { state -> String? in
            guard let result = state.result else { return nil }
            return "[\(state.modality.displayName)]: \(result.summary)"
        }
        guard !summaries.isEmpty else { return nil }

        let synthesisPrompt = """
        The following are results from \(summaries.count) reasoning modalities analyzing: "\(prompt)"

        \(summaries.joined(separator: "\n"))

        Synthesize these into a single concise paragraph (3-4 sentences) that integrates the key insights across all modalities. \
        Highlight agreements, contradictions, and unexpected connections. Be direct.
        """

        // Try on-device LLM first
        let llm = LocalLLMEngine.shared
        if llm.isReady {
            if let result = try? await llm.respond(to: synthesisPrompt) {
                return result
            }
        }

        // Fall back to cloud
        let cloudResult = await client.chat(prompt: synthesisPrompt, system: "You are a research synthesis agent. Integrate multi-modal reasoning results into concise insights.")
        return cloudResult.value?.response
    }

    // MARK: - Retry Failed Modality

    public func retryModality(_ modality: GoDeepModality) {
        guard let idx = modalityStates.firstIndex(where: { $0.modality == modality }),
              modalityStates[idx].isFailed,
              let prompt = activeSession?.prompt else { return }

        modalityStates[idx].phase = .waiting
        modalityStates[idx].startedAt = nil
        modalityStates[idx].completedAt = nil

        Task { [client] in
            // Start thinking animation for this one
            let messages = Self.thinkingMessages[modality] ?? ["Retrying..."]
            self.modalityStates[idx].phase = .thinking(messages[0])
            self.modalityStates[idx].startedAt = .now

            let result = await Self.executeModality(modality, prompt: prompt, client: client)
            self.resolveModality(modality, result: result)
        }
    }

    // MARK: - Cancel

    public func cancel() {
        runTask?.cancel()
        isRunning = false
        isSynthesizing = false
    }

    // MARK: - Clear

    private func clearState() {
        modalityStates = []
        synthesis = nil
        completedCount = 0
        totalCount = 0
    }

    // MARK: - Derived

    public var progress: Double {
        guard totalCount > 0 else { return 0 }
        return Double(completedCount) / Double(totalCount)
    }

    public var allResults: [GoDeepResult] {
        modalityStates.compactMap(\.result)
    }

    public var hasAnyResult: Bool { completedCount > 0 }
    public var hasErrors: Bool { modalityStates.contains(where: \.isFailed) }
    public var allComplete: Bool { completedCount == totalCount && totalCount > 0 }

    /// Full text for sharing / export.
    public var exportText: String {
        guard let session = activeSession else { return "" }
        var lines: [String] = ["# Go Deeper: \(session.prompt)", ""]
        for state in modalityStates {
            if let result = state.result {
                lines.append("## \(state.modality.displayName)")
                lines.append(result.summary)
                if let ms = state.durationMs { lines.append("(\(ms)ms)") }
                lines.append("")
            }
        }
        if let synthesis {
            lines.append("## Synthesis")
            lines.append(synthesis)
        }
        return lines.joined(separator: "\n")
    }
}
