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

        let projectSlug = activeProjectSlug ?? "sounio"
        let projectFamily = ProjectFamily.fromProjectSlug(projectSlug)
        let publicationScope = PublicationScope.forProjectFamily(projectFamily)
        var thought: ThoughtCapture
        let persisted = PersistedThought(rawText: text, source: source)

        if let response = result.value, let refined = response.response {
            let saveResult = await CockpitClient.shared.saveIdea(
                slug: projectSlug,
                text: text,
                source: source,
                refinedText: refined,
                projectFamily: projectFamily,
                publicationScope: publicationScope
            )
            let syncState =
                saveResult.value?.syncState
                ?? (saveResult.error == nil ? .synced : .localOnly)
            thought = ThoughtCapture(
                nodeId: saveResult.value?.nodeId,
                refinedText: refined,
                rawText: text,
                source: source,
                createdAt: Self.isoFormatter.string(from: .now),
                syncedToServer: syncState.isClusterResident,
                syncState: syncState
            )
            persisted.refinedText = refined
            persisted.nodeId = saveResult.value?.nodeId
            persisted.syncedToServer = syncState.isClusterResident
        } else {
            // Fallback: store raw thought locally
            thought = ThoughtCapture(
                nodeId: nil,
                refinedText: nil,
                rawText: text,
                source: "\(source)-offline",
                createdAt: Self.isoFormatter.string(from: .now),
                syncedToServer: false,
                syncState: .localOnly
            )
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
            // Keep snapshots bounded
            if somaticSnapshots.count > 200 { somaticSnapshots.removeFirst() }
        }

        // Persist to SwiftData
        modelContext?.insert(persisted)
        try? modelContext?.save()

        // Index to Spotlight for system-wide search
        indexToSpotlight(thought)

        return thought
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
