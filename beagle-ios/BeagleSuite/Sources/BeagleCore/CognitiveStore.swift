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
import SwiftData
#if canImport(CoreSpotlight)
import CoreSpotlight
#endif

@Observable
@MainActor
public final class CognitiveStore {

    private static let isoFormatter = ISO8601DateFormatter()
    private let assistedImportEncoder = JSONEncoder()

    public var state: Truthful<CognitiveState> = .declared(
        CognitiveState(hrv: nil, recentDrafts: nil, triadLatest: nil, agentSessions: nil, recentVoidJourneys: nil, recentFractalTrees: nil, recentPhiMeasurements: nil)
    )
    public var recentThoughts: [ThoughtCapture] = []
    public var activeJobs: [ScienceJob] = []
    public var lastTriad: Truthful<TriadResult>?

    /// Latest PCI consciousness score from a Triad review.
    public private(set) var lastConsciousnessScore: ConsciousnessScore?

    public var isLoading = false
    public var isCapturing = false
    public var isReviewingTriad = false

    /// Live, incrementally-streamed debate transcript (SSE). Cleared on each new review.
    public var triadStreamText = ""

    /// Whether beagle-server is reachable.
    public var serverReachable = false

    /// SwiftData context for persisting thoughts.
    public var modelContext: ModelContext?

    /// Total thoughts ever captured (persisted count).
    public var totalThoughtCount: Int = 0

    /// Somatic snapshots taken at thought capture time (body state context).
    public var somaticSnapshots: [SomaticSnapshot] = []

    /// The project that should receive idea writes on the mobile boundary.
    public var activeProjectSlug: String?

    /// Reference to the physio store for somatic snapshot capture.
    public weak var physioStore: PhysioStore?

    public init() {}

    /// Load persisted thoughts from SwiftData on launch.
    public func loadPersistedThoughts() {
        guard let context = modelContext else { return }
        let descriptor = FetchDescriptor<PersistedThought>(
            sortBy: [SortDescriptor(\.capturedAt, order: .reverse)]
        )
        if let persisted = try? context.fetch(descriptor) {
            totalThoughtCount = persisted.count
            // Convert to ThoughtCapture for display (most recent 50)
            let formatter = Self.isoFormatter
            recentThoughts = persisted.prefix(50).map { p in
                ThoughtCapture(
                    nodeId: p.nodeId,
                    refinedText: p.refinedText,
                    rawText: p.rawText,
                    source: p.source,
                    createdAt: formatter.string(from: p.capturedAt),
                    syncedToServer: p.syncedToServer,
                    syncState: p.syncedToServer ? .synced : .localOnly,
                    translatedText: p.translatedText,
                    originalLanguage: p.originalLanguage
                )
            }
            SemanticSearchEngine.shared.index(thoughts: recentThoughts)
        }
    }

    /// Drain the Share Extension's transient handoff queue into cluster memory.
    /// The queue is only a local bridge; successful captures are removed.
    public func drainSharedThoughtQueue(appGroupId: String = "group.dev.sounio.cockpit") async {
        guard let defaults = UserDefaults(suiteName: appGroupId) else { return }
        let pending = defaults.array(forKey: "pendingSharedThoughts") as? [[String: String]] ?? []
        guard !pending.isEmpty else { return }

        var retry: [[String: String]] = []
        for item in pending {
            let content = item["content"]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard !content.isEmpty else { continue }
            if await captureThought(text: content, source: item["source"] ?? "share-extension") == nil {
                retry.append(item)
            }
        }
        defaults.set(retry, forKey: "pendingSharedThoughts")
    }

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

    /// Capture a thought into cluster-canonical GraphRAG++ memory.
    /// SwiftData is only cache/outbox; canonical memory lives on the cluster.
    public func captureThought(text: String, source: String = "ios-keyboard") async -> ThoughtCapture? {
        isCapturing = true
        defer { isCapturing = false }

        let projectSlug = activeProjectSlug ?? "sounio"
        let bodySummary = physioStore?.summary.detailLine
        let request = AssistedImportRequestFactory.capture(
            text: text,
            source: source,
            projectRef: projectSlug,
            bodySummary: bodySummary,
            metadata: [
                "project_slug": .string(projectSlug)
            ]
        )
        var thought: ThoughtCapture
        let persisted = PersistedThought(rawText: text, source: source)

        if request.privacyClass == "restricted" {
            enqueueAssistedImportOutbox(request, reason: "restricted_privacy_guard")
            thought = ThoughtCapture(
                nodeId: nil,
                refinedText: "Restricted content held locally for explicit review.",
                rawText: text,
                source: "\(source)-restricted",
                createdAt: Self.isoFormatter.string(from: .now),
                syncedToServer: false,
                syncState: .queued
            )
            persisted.refinedText = thought.refinedText
            persisted.syncedToServer = false
        } else {
            let result = await BeagleClient.shared.assistedImportBatch(request)
            if let importResult = result.value, importResult.status == "imported" {
                let atoms = importResult.projection?.atomsCreated ?? 0
                let episodes = importResult.projection?.episodesCreated ?? 0
                // Real HERMES refinement of the thought (Wave 2); falls back to the
                // import-accounting line if the refine endpoint/provider is unavailable.
                // Detect the source language up-front and pass it as a preserve-language
                // hint so Portuguese thoughts stay in Portuguese after refinement.
                let sourceLanguageHint = TranslationEngine.shared.detectLanguage(text)
                let refined = await BeagleClient.shared.refineThought(
                    text: text,
                    projectSlug: projectSlug,
                    source: source,
                    languageHint: sourceLanguageHint
                ).value?.refinedText
                    ?? "Captured into cluster GraphRAG++ memory (\(episodes) episode, \(atoms) atoms)."
                let nodeId = importResult.omnimemory?.id
                    ?? importResult.memoryEvent?.id
                    ?? importResult.auditEvent?.id
                    ?? importResult.sessionId
                thought = ThoughtCapture(
                    nodeId: nodeId,
                    refinedText: refined,
                    rawText: text,
                    source: source,
                    createdAt: Self.isoFormatter.string(from: .now),
                    syncedToServer: true,
                    syncState: .synced
                )
                persisted.refinedText = refined
                persisted.nodeId = nodeId
                persisted.syncedToServer = true
            } else {
                enqueueAssistedImportOutbox(request, reason: result.error ?? result.value?.reason ?? "cluster_import_failed")
                thought = ThoughtCapture(
                    nodeId: nil,
                    refinedText: result.error ?? "Queued for cluster GraphRAG++ import.",
                    rawText: text,
                    source: "\(source)-queued",
                    createdAt: Self.isoFormatter.string(from: .now),
                    syncedToServer: false,
                    syncState: .queued
                )
                persisted.refinedText = thought.refinedText
                persisted.syncedToServer = false
            }
        }

        // Bilingual processing: detect language and enqueue translation if Portuguese
        let textToAnalyze = thought.refinedText ?? thought.rawText ?? text
        let detectedLang = TranslationEngine.shared.detectLanguage(textToAnalyze)
        thought.originalLanguage = detectedLang
        persisted.originalLanguage = detectedLang

        if TranslationEngine.isPortugueseCode(detectedLang) {
            TranslationEngine.shared.enqueueForTranslation(
                thoughtId: thought.id,
                text: textToAnalyze
            )
        }

        recentThoughts.insert(thought, at: 0)
        if recentThoughts.count > 50 { recentThoughts.removeLast() }
        totalThoughtCount += 1
        SemanticSearchEngine.shared.index(thoughts: recentThoughts)

        // Take somatic snapshot from PhysioStore at capture time
        if let physio = physioStore {
            let snapshot = SomaticSnapshot(from: physio.cognitivePosture)
            somaticSnapshots.append(snapshot)
            if somaticSnapshots.count > 200 { somaticSnapshots.removeFirst() }
        }

        // Persist to SwiftData as cache/outbox-visible local recall.
        modelContext?.insert(persisted)
        try? modelContext?.save()

        // Index to Spotlight for system-wide search
        indexToSpotlight(thought)

        return thought
    }

    /// Drain queued assisted-import requests back to the cluster when connectivity
    /// returns. Restricted-privacy items are held until explicit review. Successful
    /// imports are removed; failures stay queued with an incremented attempt count.
    /// Returns the number of queued items successfully imported.
    @discardableResult
    public func drainAssistedImportOutbox() async -> Int {
        guard let modelContext else { return 0 }
        let descriptor = FetchDescriptor<PersistedAssistedImportOutbox>(
            predicate: #Predicate<PersistedAssistedImportOutbox> { item in
                item.privacyClass != "restricted"
            },
            sortBy: [SortDescriptor(\.createdAt, order: .forward)]
        )
        guard let pending = try? modelContext.fetch(descriptor), !pending.isEmpty else { return 0 }

        let decoder = JSONDecoder()
        var drained = 0
        for item in pending {
            guard
                let data = item.payload.data(using: .utf8),
                let request = try? decoder.decode(AssistedImportBatchRequest.self, from: data)
            else {
                // Undecodable payload — drop it so it can't wedge the queue forever.
                modelContext.delete(item)
                continue
            }
            let result = await BeagleClient.shared.assistedImportBatch(request)
            if result.value?.status == "imported" {
                modelContext.delete(item)
                drained += 1
            } else {
                item.attemptCount += 1
                item.lastAttemptAt = .now
            }
        }
        try? modelContext.save()
        return drained
    }

    private func enqueueAssistedImportOutbox(_ request: AssistedImportBatchRequest, reason: String) {
        guard
            let modelContext,
            let data = try? assistedImportEncoder.encode(request),
            let payload = String(data: data, encoding: .utf8)
        else {
            return
        }
        modelContext.insert(PersistedAssistedImportOutbox(
            payload: payload,
            reason: reason,
            privacyClass: request.privacyClass,
            sourceSurface: request.sourceSurface
        ))
        try? modelContext.save()
    }

    // MARK: - Bilingual translation callback

    /// Called by the UI layer when a translation completes via TranslationSession.
    /// Updates the in-memory thought and persists the translation to SwiftData.
    public func applyTranslation(thoughtId: String, translatedText: String) {
        TranslationEngine.shared.recordTranslation(thoughtId: thoughtId, translatedText: translatedText)

        // Update in-memory thought
        if let idx = recentThoughts.firstIndex(where: { $0.id == thoughtId }) {
            recentThoughts[idx].translatedText = translatedText
        }

        // Persist to SwiftData
        if let context = modelContext {
            let descriptor = FetchDescriptor<PersistedThought>()
            if let all = try? context.fetch(descriptor),
               let persisted = all.first(where: { $0.nodeId == thoughtId }) {
                persisted.translatedText = translatedText
                try? context.save()
            }
        }
    }

    // MARK: - Triad review

    /// Submit draft for adversarial review. Long-running (up to 120s).
    public func submitForTriadReview(draft: String) async -> TriadResult? {
        isReviewingTriad = true
        defer { isReviewingTriad = false }

        let result = await BeagleClient.shared.runTriad(prompt: draft)
        lastTriad = result
        if let triadResult = result.value {
            lastConsciousnessScore = ConsciousnessMetrics.shared.computePCI(from: triadResult)
        }
        return result.value
    }

    /// Streaming adversarial review: renders the debate transcript incrementally
    /// via SSE, then returns the final consolidated TriadResult when it arrives.
    public func streamTriadReview(draft: String) async -> TriadResult? {
        isReviewingTriad = true
        triadStreamText = ""
        defer { isReviewingTriad = false }

        var finalResult: TriadResult?
        for await event in BeagleClient.shared.streamTriad(prompt: draft) {
            switch event {
            case .delta(let agent, let text):
                if let agent, !agent.isEmpty {
                    triadStreamText += "\n[\(agent)] \(text)"
                } else {
                    triadStreamText += text
                }
            case .final(let result):
                finalResult = result
            case .error(let message):
                if triadStreamText.isEmpty {
                    triadStreamText = message
                }
            }
        }

        if let finalResult {
            lastTriad = .observed(finalResult, source: "dev-debate-stream")
            lastConsciousnessScore = ConsciousnessMetrics.shared.computePCI(from: finalResult)
            return finalResult
        }
        // Stream produced text but no structured final frame — fall back to the
        // non-streaming endpoint so the scores/opinions UI still resolves.
        let result = await BeagleClient.shared.runTriad(prompt: draft)
        lastTriad = result
        if let triadResult = result.value {
            lastConsciousnessScore = ConsciousnessMetrics.shared.computePCI(from: triadResult)
        }
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

    // MARK: - Semantic search

    /// Search recent thoughts by semantic similarity using on-device NLEmbedding.
    /// Falls back to substring matching when the embedding model is unavailable.
    public func semanticSearch(query: String) -> [(thought: ThoughtCapture, similarity: Double)] {
        if SemanticSearchEngine.shared.isAvailable {
            return SemanticSearchEngine.shared.search(query: query)
        }
        // Fallback: substring match with synthetic similarity of 0.5
        return SemanticSearchEngine.substringSearch(query: query, in: recentThoughts)
            .map { (thought: $0, similarity: 0.5) }
    }

    // MARK: - Somatic search

    /// Search recent thoughts by somatic (body) state rather than content.
    public func somaticSearch(query: SomaticRetrieval.SomaticQuery) -> [SomaticMatch] {
        SomaticRetrieval.shared.search(
            query: query,
            thoughts: recentThoughts,
            postures: somaticSnapshots
        )
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

    // MARK: - Spotlight indexing

    #if canImport(CoreSpotlight)
    private func indexToSpotlight(_ thought: ThoughtCapture) {
        let title = thought.refinedText ?? thought.rawText ?? ""
        guard !title.isEmpty else { return }

        let attributes = CSSearchableItemAttributeSet(contentType: .text)
        attributes.title = String(title.prefix(120))
        attributes.contentDescription = thought.rawText
        attributes.keywords = extractKeywords(from: title)

        let item = CSSearchableItem(
            uniqueIdentifier: "thought-\(thought.id)",
            domainIdentifier: "dev.sounio.cockpit.thoughts",
            attributeSet: attributes
        )
        item.expirationDate = Calendar.current.date(byAdding: .year, value: 1, to: Date())

        CSSearchableIndex.default().indexSearchableItems([item]) { error in
            if let error { print("[Spotlight] indexing failed: \(error)") }
        }
    }
    #else
    private func indexToSpotlight(_ thought: ThoughtCapture) {}
    #endif

    private func extractKeywords(from text: String) -> [String] {
        let stopWords: Set<String> = ["the", "a", "an", "is", "are", "was", "were", "be", "been",
                                       "being", "have", "has", "had", "do", "does", "did", "will",
                                       "would", "could", "should", "may", "might", "can", "shall",
                                       "to", "of", "in", "for", "on", "with", "at", "by", "from",
                                       "as", "into", "through", "during", "before", "after",
                                       "de", "do", "da", "dos", "das", "em", "no", "na", "um", "uma",
                                       "que", "para", "com", "por", "se", "como", "mais", "ou", "mas"]
        return text.lowercased()
            .components(separatedBy: .alphanumerics.inverted)
            .filter { $0.count >= 4 && !stopWords.contains($0) }
    }

    // MARK: - Shared helpers

    public static func recentTrailSnippets(from thoughts: [ThoughtCapture], limit: Int = 3) -> [String] {
        thoughts.prefix(limit).compactMap { thought in
            let text = thought.refinedText ?? thought.rawText ?? ""
            guard !text.isEmpty else { return nil }
            return text.count > 96 ? String(text.prefix(96)) + "..." : text
        }
    }
}
