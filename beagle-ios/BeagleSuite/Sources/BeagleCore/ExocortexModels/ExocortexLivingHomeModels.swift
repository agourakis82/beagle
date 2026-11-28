//
//  ExocortexLivingHomeModels.swift
//  BeagleCore
//
//  Living Home continuity signals, next-move synthesis, and ExocortexHomeSnapshot.
//

import Foundation

public struct LivingHomeMode: RawRepresentable, Codable, Equatable, Hashable, Sendable {
    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }

    public static let live = LivingHomeMode(rawValue: "live")
    public static let remembered = LivingHomeMode(rawValue: "remembered")
    public static let offline = LivingHomeMode(rawValue: "offline")
    public static let attention = LivingHomeMode(rawValue: "attention")
    public static let review = LivingHomeMode(rawValue: "review")
    public static let capture = LivingHomeMode(rawValue: "capture")
}

public struct HomeContinuitySignal: Codable, Equatable, Sendable, Identifiable {
    public let id: String
    public let title: String
    public let detail: String
    public let kind: String
    public let sourceSurface: String?
    public let observedAt: String?
    public let truthMode: String
    public let provenanceRefs: [String]

    public init(
        id: String,
        title: String,
        detail: String,
        kind: String,
        sourceSurface: String? = nil,
        observedAt: String? = nil,
        truthMode: String = "declared",
        provenanceRefs: [String] = []
    ) {
        self.id = id
        self.title = title
        self.detail = detail
        self.kind = kind
        self.sourceSurface = sourceSurface
        self.observedAt = observedAt
        self.truthMode = truthMode
        self.provenanceRefs = provenanceRefs
    }

    enum CodingKeys: String, CodingKey {
        case id
        case title
        case detail
        case kind
        case sourceSurface = "source_surface"
        case observedAt = "observed_at"
        case truthMode = "truth_mode"
        case provenanceRefs = "provenance_refs"
    }
}

public struct HomeNextMove: Codable, Equatable, Sendable, Identifiable {
    public let id: String
    public let title: String
    public let detail: String
    public let action: String
    public let systemImage: String
    public let reason: String
    public let priority: Int
    public let target: String?

    public init(
        id: String,
        title: String,
        detail: String,
        action: String,
        systemImage: String,
        reason: String,
        priority: Int = 0,
        target: String? = nil
    ) {
        self.id = id
        self.title = title
        self.detail = detail
        self.action = action
        self.systemImage = systemImage
        self.reason = reason
        self.priority = priority
        self.target = target
    }

    enum CodingKeys: String, CodingKey {
        case id
        case title
        case detail
        case action
        case systemImage = "system_image"
        case reason
        case priority
        case target
    }
}

public struct HomeContinuityContext: Codable, Equatable, Sendable {
    public let generatedAt: String
    public let mode: LivingHomeMode
    public let changedSinceLastOpen: [HomeContinuitySignal]
    public let latestSurfaceWrite: HomeContinuitySignal?
    public let activeThread: String?
    public let primaryNextAction: HomeNextMove
    public let alternativeNextActions: [HomeNextMove]
    public let whyThisNow: String
    public let confidence: Double
    public let sourceMode: String

    public init(
        generatedAt: String,
        mode: LivingHomeMode,
        changedSinceLastOpen: [HomeContinuitySignal],
        latestSurfaceWrite: HomeContinuitySignal?,
        activeThread: String?,
        primaryNextAction: HomeNextMove,
        alternativeNextActions: [HomeNextMove] = [],
        whyThisNow: String,
        confidence: Double,
        sourceMode: String
    ) {
        self.generatedAt = generatedAt
        self.mode = mode
        self.changedSinceLastOpen = changedSinceLastOpen
        self.latestSurfaceWrite = latestSurfaceWrite
        self.activeThread = activeThread
        self.primaryNextAction = primaryNextAction
        self.alternativeNextActions = alternativeNextActions
        self.whyThisNow = whyThisNow
        self.confidence = confidence
        self.sourceMode = sourceMode
    }

    enum CodingKeys: String, CodingKey {
        case generatedAt = "generated_at"
        case mode
        case changedSinceLastOpen = "changed_since_last_open"
        case latestSurfaceWrite = "latest_surface_write"
        case activeThread = "active_thread"
        case primaryNextAction = "primary_next_action"
        case alternativeNextActions = "alternative_next_actions"
        case whyThisNow = "why_this_now"
        case confidence
        case sourceMode = "source_mode"
    }
}

public extension HomeContinuityContext {
    static func synthesized(
        home: ExocortexHomeSnapshot,
        truthMode: TruthMode,
        previousHome: ExocortexHomeSnapshot? = nil,
        recentGraph: MemoryGraphRecentResponse? = nil,
        projectionStatus: MemoryProjectionStatus? = nil,
        originLineage: OriginLineageSnapshot? = nil
    ) -> HomeContinuityContext {
        var signals: [HomeContinuitySignal] = []

        if truthMode == .stale {
            signals.append(HomeContinuitySignal(
                id: "home-offline-cache",
                title: "Offline cache",
                detail: "The last remembered Home is visible while cluster truth is unavailable.",
                kind: "cache",
                sourceSurface: "swiftdata-cache",
                observedAt: previousHome?.generatedAt,
                truthMode: truthMode.rawValue,
                provenanceRefs: ["swiftdata-cache"]
            ))
        } else if previousHome?.generatedAt != nil, previousHome?.generatedAt != home.generatedAt {
            signals.append(HomeContinuitySignal(
                id: "home-cluster-refresh",
                title: "Cluster refreshed",
                detail: "Live cluster truth replaced the last remembered Home.",
                kind: "cluster_refresh",
                sourceSurface: "beagle-core",
                observedAt: home.generatedAt,
                truthMode: truthMode.rawValue,
                provenanceRefs: ["home:\(home.generatedAt)"]
            ))
        }

        if let last = home.agentContext?.lastAgentWrite ?? home.trustContext?.latestAgentWrite, !last.isEmpty {
            signals.append(HomeContinuitySignal(
                id: "latest-agent-write-\(stableSignalSuffix(last))",
                title: "Agent wrote memory",
                detail: last,
                kind: "agent_write",
                sourceSurface: "mcp-agent",
                observedAt: home.trustContext?.auditFreshness,
                truthMode: "observed",
                provenanceRefs: home.trustContext?.lastAuditEventId.map { [$0] } ?? []
            ))
        }

        if let capture = home.trustContext?.appleCaptureFreshness ?? home.trustContext?.captureLoopStatus, !capture.isEmpty {
            signals.append(HomeContinuitySignal(
                id: "apple-capture-\(stableSignalSuffix(capture))",
                title: "Apple capture loop",
                detail: capture,
                kind: "apple_capture",
                sourceSurface: "beagle-apple",
                observedAt: home.generatedAt,
                truthMode: "observed",
                provenanceRefs: ["home.trust_context.capture"]
            ))
        }

        if let graphSignal = latestGraphSignal(from: recentGraph) {
            signals.append(graphSignal)
        }

        if let projectionStatus {
            let detail = "\(projectionStatus.episodeCount) episodes · \(projectionStatus.atomCount) atoms · \(projectionStatus.retrievalMode)"
            signals.append(HomeContinuitySignal(
                id: "memory-projection-\(projectionStatus.status)",
                title: "Memory projection",
                detail: detail,
                kind: "memory_projection",
                sourceSurface: "beagle-core",
                observedAt: projectionStatus.latestRun?.createdAt,
                truthMode: projectionStatus.status == "fresh" ? "observed" : "remembered",
                provenanceRefs: projectionStatus.latestRun.map { [$0.id] } ?? []
            ))
        }

        if let originLineage, !originLineage.nodes.isEmpty {
            signals.append(HomeContinuitySignal(
                id: "origin-lineage-\(originLineage.sourcePolicy)",
                title: "Origin lineage",
                detail: "RAG++ -> Darwin -> Beagle -> Sounio remains visible as sanitized memory archaeology.",
                kind: "origin_lineage",
                sourceSurface: originLineage.sourcePolicy.contains("cluster") ? "beagle-core" : "local-seed",
                observedAt: originLineage.generatedAt,
                truthMode: originLineage.sourcePolicy.contains("cluster") ? "observed" : "remembered",
                provenanceRefs: originLineage.evidenceRefs.map(\.id)
            ))
        }

        for signal in home.memorySignals.prefix(2) where !signal.localizedCaseInsensitiveContains("restricted") {
            signals.append(HomeContinuitySignal(
                id: "home-memory-signal-\(stableSignalSuffix(signal))",
                title: "Memory signal",
                detail: signal,
                kind: "memory_signal",
                sourceSurface: "exocortex-home",
                observedAt: home.generatedAt,
                truthMode: truthMode.rawValue,
                provenanceRefs: []
            ))
        }

        let uniqueSignals = unique(signals).prefix(6)
        let latestSurfaceWrite = uniqueSignals.first {
            ["agent_write", "apple_capture", "grok_import", "work_memory"].contains($0.kind)
        }
        let moves = nextMoves(
            home: home,
            truthMode: truthMode,
            latestSurfaceWrite: latestSurfaceWrite,
            signals: Array(uniqueSignals)
        )
        let mode = livingMode(home: home, truthMode: truthMode, latestSurfaceWrite: latestSurfaceWrite)

        return HomeContinuityContext(
            generatedAt: home.generatedAt,
            mode: mode,
            changedSinceLastOpen: Array(uniqueSignals),
            latestSurfaceWrite: latestSurfaceWrite,
            activeThread: home.activeProjectRef ?? home.temporalPhase,
            primaryNextAction: moves.primary,
            alternativeNextActions: moves.alternatives,
            whyThisNow: whyThisNow(
                home: home,
                truthMode: truthMode,
                primary: moves.primary,
                latestSurfaceWrite: latestSurfaceWrite
            ),
            confidence: confidence(truthMode: truthMode, signalCount: uniqueSignals.count),
            sourceMode: "local_synthesis"
        )
    }

    private static func latestGraphSignal(from graph: MemoryGraphRecentResponse?) -> HomeContinuitySignal? {
        guard let graph else { return nil }

        if let episode = graph.episodes.first(where: {
            $0.privacyClass != "restricted" && haystack(for: $0).contains("grok")
        }) {
            return HomeContinuitySignal(
                id: "grok-import-\(episode.id)",
                title: "Grok import signal",
                detail: episode.title ?? "Grok context is projected into GraphRAG++ memory.",
                kind: "grok_import",
                sourceSurface: episode.sourcePlatform ?? episode.source,
                observedAt: episode.occurredAt ?? episode.createdAt,
                truthMode: "observed",
                provenanceRefs: [episode.sourceRef]
            )
        }

        if let atom = graph.atoms.first(where: {
            $0.privacyClass != "restricted" && haystack(for: $0).contains("work-memory")
        }) {
            return HomeContinuitySignal(
                id: "work-memory-\(atom.id)",
                title: "Work memory",
                detail: "Codex or Claude Code work context is now recoverable.",
                kind: "work_memory",
                sourceSurface: "agent-work-memory",
                observedAt: atom.occurredAt ?? atom.createdAt,
                truthMode: "observed",
                provenanceRefs: atom.sourceRefs
            )
        }

        if let episode = graph.episodes.first(where: {
            $0.privacyClass != "restricted" && haystack(for: $0).contains("watch")
        }) {
            return HomeContinuitySignal(
                id: "watch-capture-\(episode.id)",
                title: "Watch capture",
                detail: "A wrist micro-intention reached cluster memory.",
                kind: "apple_capture",
                sourceSurface: episode.sourcePlatform ?? "watchos",
                observedAt: episode.occurredAt ?? episode.createdAt,
                truthMode: "observed",
                provenanceRefs: [episode.sourceRef]
            )
        }

        return nil
    }

    private static func nextMoves(
        home: ExocortexHomeSnapshot,
        truthMode: TruthMode,
        latestSurfaceWrite: HomeContinuitySignal?,
        signals: [HomeContinuitySignal]
    ) -> (primary: HomeNextMove, alternatives: [HomeNextMove]) {
        let inspectTrust = HomeNextMove(
            id: "inspect-trust",
            title: "Inspect trust",
            detail: home.trustContext?.mcpStatus ?? "Check cluster, MCP and audit state.",
            action: "inspect_trust",
            systemImage: "checkmark.shield",
            reason: "The Home is stale or needs trust context before action.",
            priority: 90
        )
        let reviewClaim = HomeNextMove(
            id: "review-claim",
            title: "Review claim",
            detail: home.trustContext?.sounioPendingApproval ?? "\(home.trustContext?.pendingTriads ?? 0) pending Triad items",
            action: "review_claim",
            systemImage: "checklist.checked",
            reason: "A pending claim or Triad item needs human judgment.",
            priority: 80
        )
        let openMemory = HomeNextMove(
            id: "open-memory-lens",
            title: "Open Memory Lens",
            detail: latestSurfaceWrite?.title ?? "\(signals.count) continuity signals",
            action: "open_memory_lens",
            systemImage: "point.3.connected.trianglepath.dotted",
            reason: "New memory is visible; inspect evidence and provenance.",
            priority: 70
        )
        let resumeProject = HomeNextMove(
            id: "resume-project",
            title: "Resume \(home.activeProjectRef ?? "project")",
            detail: home.recommendedNextAction,
            action: "resume_project",
            systemImage: "arrow.forward.circle.fill",
            reason: "The active project is the highest-continuity thread.",
            priority: 60,
            target: home.activeProjectRef
        )
        let captureThought = HomeNextMove(
            id: "capture-thought",
            title: "Capture thought",
            detail: "Record the next intention as Episode+Atom.",
            action: "capture_thought",
            systemImage: "mic.fill",
            reason: "No urgent review exists; preserve the next thought before it evaporates.",
            priority: 40
        )

        let primary: HomeNextMove
        if truthMode == .stale {
            primary = inspectTrust
        } else if home.trustContext?.sounioPendingApproval?.isEmpty == false || (home.trustContext?.pendingTriads ?? 0) > 0 {
            primary = reviewClaim
        } else if latestSurfaceWrite != nil || !signals.isEmpty {
            primary = openMemory
        } else if home.activeProjectRef != nil {
            primary = resumeProject
        } else {
            primary = captureThought
        }

        let alternatives = [reviewClaim, openMemory, resumeProject, captureThought, inspectTrust]
            .filter { $0.id != primary.id }
        return (primary, alternatives)
    }

    private static func livingMode(
        home: ExocortexHomeSnapshot,
        truthMode: TruthMode,
        latestSurfaceWrite: HomeContinuitySignal?
    ) -> LivingHomeMode {
        if truthMode == .stale { return .offline }
        if home.trustContext?.sounioPendingApproval?.isEmpty == false || (home.trustContext?.pendingTriads ?? 0) > 0 {
            return .review
        }
        if latestSurfaceWrite?.kind == "apple_capture" { return .capture }
        if latestSurfaceWrite != nil { return .live }
        if truthMode == .remembered { return .remembered }
        return .attention
    }

    private static func whyThisNow(
        home: ExocortexHomeSnapshot,
        truthMode: TruthMode,
        primary: HomeNextMove,
        latestSurfaceWrite: HomeContinuitySignal?
    ) -> String {
        if truthMode == .stale {
            return "Beagle is showing remembered state; trust inspection comes before deeper action."
        }
        if let latestSurfaceWrite {
            return "\(latestSurfaceWrite.title) is the freshest change, so the safest next move is to inspect its provenance."
        }
        if primary.action == "review_claim" {
            return "A claim or Triad item is waiting for human judgment before promotion."
        }
        if !home.recommendedNextAction.isEmpty {
            return home.recommendedNextAction
        }
        return "No urgent write or review is visible; capture the next intention."
    }

    private static func confidence(truthMode: TruthMode, signalCount: Int) -> Double {
        switch truthMode {
        case .observed:
            return signalCount > 0 ? 0.88 : 0.72
        case .remembered:
            return 0.66
        case .declared:
            return 0.52
        case .stale:
            return 0.40
        }
    }

    private static func unique(_ signals: [HomeContinuitySignal]) -> [HomeContinuitySignal] {
        var seen = Set<String>()
        return signals.filter { signal in
            guard !seen.contains(signal.id) else { return false }
            seen.insert(signal.id)
            return true
        }
    }

    private static func stableSignalSuffix(_ text: String) -> String {
        text
            .lowercased()
            .unicodeScalars
            .filter { CharacterSet.alphanumerics.contains($0) }
            .prefix(24)
            .map(String.init)
            .joined()
    }

    private static func haystack(for episode: MemoryEpisode) -> String {
        (episode.tags + [
            episode.source,
            episode.sourcePlatform ?? "",
            episode.title ?? "",
            episode.sourceRef
        ]).joined(separator: " ").lowercased()
    }

    private static func haystack(for atom: MemoryAtom) -> String {
        (atom.tags + [
            atom.atomType,
            atom.text,
            atom.normalizedText
        ]).joined(separator: " ").lowercased()
    }
}

public struct ExocortexHomeSnapshot: Codable, Equatable, Sendable {
    public let generatedAt: String
    public let todayBrief: String
    public let currentSelf: SelfVersion
    public let memorySignals: [String]
    public let openLoops: [String]
    public let activeProjectRef: String?
    public let bodyContext: String?
    public let recommendedNextAction: String
    public let clusterTruth: String
    public let omnimemoryStatus: String
    public let temporalPhase: String?
    public let agentContext: AgentContext?
    public let trustContext: TrustContext?
    public let originLineage: OriginLineageSnapshot?
    public let continuityContext: HomeContinuityContext?
    public let sounioWorkdayContext: SounioWorkdaySnapshot?

    enum CodingKeys: String, CodingKey {
        case generatedAt = "generated_at"
        case todayBrief = "today_brief"
        case currentSelf = "current_self"
        case memorySignals = "memory_signals"
        case openLoops = "open_loops"
        case activeProjectRef = "active_project_ref"
        case bodyContext = "body_context"
        case recommendedNextAction = "recommended_next_action"
        case clusterTruth = "cluster_truth"
        case omnimemoryStatus = "omnimemory_status"
        case temporalPhase = "temporal_phase"
        case agentContext = "agent_context"
        case trustContext = "trust_context"
        case originLineage = "origin_lineage"
        case continuityContext = "continuity_context"
        case sounioWorkdayContext = "sounio_workday_context"
    }

    public static let bootstrap = ExocortexHomeSnapshot(
        generatedAt: "",
        todayBrief: "O cluster ainda não enviou um snapshot vivo.",
        currentSelf: .bootstrap,
        memorySignals: [],
        openLoops: [],
        activeProjectRef: nil,
        bodyContext: nil,
        recommendedNextAction: "Conectar ao cluster e recuperar a Home Exocortex.",
        clusterTruth: "declared",
        omnimemoryStatus: "unknown",
        temporalPhase: nil,
        agentContext: nil,
        trustContext: nil,
        originLineage: nil,
        continuityContext: nil,
        sounioWorkdayContext: nil
    )
}
