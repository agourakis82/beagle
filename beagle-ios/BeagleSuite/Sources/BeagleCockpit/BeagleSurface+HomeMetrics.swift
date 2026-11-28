//
//  BeagleSurface+HomeMetrics.swift
//  BeagleCockpit
//
//  Computed telemetry, trust, memory-projection, Grok/work-memory, and body-loop
//  summary lines for BeagleSurface's Exocortex Home card.
//

import SwiftUI
import BeagleCore

extension BeagleSurface {
    // MARK: - Home Metrics

    var phoneSurfaceLabel: String {
        if home.bodyContext?.localizedCaseInsensitiveContains("iPhone 17 Pro Max") == true {
            return "iPhone 17 Pro Max"
        }
        return platformName
    }

    var watchSurfaceLabel: String {
        if home.bodyContext?.localizedCaseInsensitiveContains("Apple Watch Ultra 2") == true {
            return "Watch Ultra 2"
        }
        return physio.isAvailable ? "HealthKit" : "Watch loop"
    }

    var readinessStatusLabel: String {
        if readinessLabel != "—" {
            return readinessLabel
        }
        switch physio.summary.authorizationState {
        case .authorized:
            return physio.summary.readiness == .unavailable ? "waiting" : physio.summary.readiness.rawValue
        case .requesting:
            return "requesting"
        case .denied:
            return "denied"
        case .error:
            return "error"
        case .unavailable:
            return "unavailable"
        case .idle:
            return "ready"
        }
    }

    var bodyContextLine: String? {
        if let clusterLine = home.bodyContext?.trimmingCharacters(in: .whitespacesAndNewlines),
           !clusterLine.isEmpty {
            return clusterLine
        }
        if physio.summary.isMeaningful || physio.summary.authorizationState != .idle {
            return physio.summary.bodyLine
        }
        return nil
    }

    var trustContextLine: String? {
        guard let trust = home.trustContext else { return nil }
        let scopeCount = trust.activeScopes.count
        let hashLabel = trust.toolManifestHash.map { String($0.suffix(12)) } ?? "no hash"
        let mesh = trust.memoryEngineStatus.map { " · \($0)" } ?? ""
        let quorum = trust.latestQuorumStatus.map { " · quorum \($0)" } ?? ""
        let governor = trust.memoryGovernorStatus.map { " · governor \($0)" } ?? ""
        let pending = trust.pendingTriads.map { " · triad \($0)" } ?? ""
        let contradictions = trust.openContradictions.map { " · contradictions \($0)" } ?? ""
        let benchGate = trust.benchHotPathEligible.map { " · bench gate \($0 ? "eligible" : "shadow")" } ?? ""
        let semantic = trust.semanticBackboneStatus.map { " · \($0)" } ?? ""
        let hotPath = trust.hotPathMode.map { " · hot path \($0)" } ?? ""
        let provisional = trust.provisionalHotPath == true ? " · provisional" : ""
        let capture = trust.captureLoopStatus.map { " · capture \($0)" } ?? ""
        let compiler = trust.contextCompilerStatus.map { " · compiler \($0)" } ?? ""
        let policy = trust.memoryPolicyStatus.map { " · policy \($0)" } ?? ""
        let dream = trust.dreamcycleStatus.map { " · dream \($0)" } ?? ""
        let sounio = trust.sounioPaperRunStatus.map { " · Sounio \($0)" } ?? ""
        let temporal = trust.sounioTemporalStatus.map { " · Temporal \($0)" } ?? ""
        return "\(trust.mcpStatus) · \(scopeCount) scopes · \(hashLabel)\(semantic)\(hotPath)\(provisional)\(compiler)\(policy)\(dream)\(sounio)\(temporal)\(mesh)\(governor)\(pending)\(contradictions)\(quorum)\(benchGate)\(capture) · destructive locked"
    }

    var memoryProjectionLine: String {
        let status = exocortex.recentGraph?.value?.status
            ?? exocortex.projectionStatus?.value
            ?? home.trustContext?.memoryProjectionStatus
        guard let status else {
            return "Projection not observed yet; tap to inspect cluster memory."
        }
        let runtime = home.trustContext?.semanticBackboneStatus ?? home.trustContext?.graphRuntime ?? exocortex.graphStatus?.value?.graphRuntime ?? "jsonl"
        let mode = home.trustContext?.hotPathMode ?? home.trustContext?.retrievalMode ?? exocortex.graphStatus?.value?.retrievalMode ?? status.retrievalMode
        let degrade = home.trustContext?.graphDegradedReason ?? exocortex.graphStatus?.value?.degradedReason ?? status.degradedReason
        let hash = home.trustContext?.lastWorldHash.map { " · \($0.prefix(18))" } ?? ""
        let candidate = home.trustContext?.latestCandidateRef.map { " · candidate \($0.prefix(12))" } ?? ""
        let bench = memoryBenchLine.map { " · \($0)" } ?? ""
        return "\(runtime) · \(mode) · \(status.episodeCount) episodes · \(status.atomCount) atoms · \(degrade)\(bench)\(hash)\(candidate)"
    }

    var semanticBackboneDetail: String {
        guard let trust = home.trustContext else {
            return "awaiting cluster trust"
        }
        let backbone = trust.semanticBackboneStatus ?? "semantic-backbone-unknown"
        let hotPath = trust.hotPathMode ?? trust.retrievalMode ?? "unknown"
        let gate = trust.provisionalHotPath == true ? "provisional" : (trust.benchHotPathEligible == true ? "confirmed" : "shadow")
        return "\(backbone) · \(hotPath) · \(gate)"
    }

    private var memoryBenchLine: String? {
        if let trust = home.trustContext,
           let status = trust.memoryBenchStatus {
            let score = trust.latestBenchScore.map { " \(String(format: "%.2f", $0))" } ?? ""
            let regressions = trust.memoryRegressionCount.map { " · \($0) regressions" } ?? ""
            let gate = trust.benchHotPathEligible.map { " · \($0 ? "hot-path eligible" : "shadow gate")" } ?? ""
            let truthset = trust.truthsetId.map { " · truth \($0.prefix(12))" } ?? ""
            return "bench \(status)\(score)\(regressions)\(gate)\(truthset)"
        }
        if let bench = exocortex.benchmarkStatus?.value {
            let score = bench.latestScore.map { " \(String(format: "%.2f", $0))" } ?? ""
            let gate = bench.hotPathEligible ? " · hot-path eligible" : " · shadow gate"
            let truthset = bench.truthsetId.map { " · truth \($0.prefix(12))" } ?? ""
            return "bench \(bench.status)\(score) · \(bench.regressionCount) regressions\(gate)\(truthset)"
        }
        return nil
    }

    var latestAgentWriteLine: String? {
        if let latest = home.trustContext?.latestAgentWrite?.trimmingCharacters(in: .whitespacesAndNewlines),
           !latest.isEmpty {
            return latest
        }
        if let latest = home.agentContext?.lastAgentWrite?.trimmingCharacters(in: .whitespacesAndNewlines),
           !latest.isEmpty {
            return latest
        }
        if let atom = exocortex.recentGraph?.value?.atoms.first(where: isWorkMemoryAtom) {
            return "\(atom.atomType) · \(atom.text)"
        }
        return nil
    }

    var latestGrokImportLine: String? {
        if let signal = home.memorySignals.first(where: { $0.localizedCaseInsensitiveContains("grok") }) {
            return signal
        }
        if let episode = exocortex.recentGraph?.value?.episodes.first(where: isGrokEpisode) {
            let when = episode.occurredAt ?? episode.createdAt
            return "\(episode.title ?? episode.sourceRef) · \(when)"
        }
        if let atom = exocortex.recentGraph?.value?.atoms.first(where: isGrokAtom) {
            return "\(atom.atomType) · \(atom.text)"
        }
        return nil
    }

    var autoImportTitle: String {
        switch conversation.autoImportState.status {
        case "imported":
            return "Auto-memory"
        case "importing":
            return "Importing"
        case "blocked":
            return "Privacy held"
        case "queued":
            return "Queued"
        default:
            return "Auto-memory"
        }
    }

    var autoImportDetail: String {
        let state = conversation.autoImportState
        if let summary = state.lastSummary, state.status == "imported" {
            return "\(summary) · GraphRAG++"
        }
        if state.restrictedCount > 0 {
            return "\(state.restrictedCount) restricted · explicit review"
        }
        if state.queuedCount > 0 {
            return "\(state.queuedCount) queued · cluster retry"
        }
        return "Every completed exchange becomes Episode+Atom."
    }

    var agentContextDetail: String {
        if let agent = home.agentContext {
            if let last = agent.lastAgentWrite, !last.isEmpty {
                return "\(agent.mcpStatus) · last \(last)"
            }
            return "\(agent.mcpStatus) · \(agent.activeSessions) sessions"
        }
        return home.clusterTruth
    }

    private func isWorkMemoryAtom(_ atom: MemoryAtom) -> Bool {
        guard atom.privacyClass != "restricted" else { return false }
        let haystack = (atom.tags + [atom.atomType, atom.text]).joined(separator: " ").lowercased()
        return haystack.contains("work-memory")
            || haystack.contains("codex")
            || haystack.contains("claude-code")
            || haystack.contains("agent:")
    }

    private func isGrokEpisode(_ episode: MemoryEpisode) -> Bool {
        guard episode.privacyClass != "restricted" else { return false }
        let haystack = (episode.tags + [
            episode.source,
            episode.sourcePlatform ?? "",
            episode.title ?? "",
            episode.sourceRef
        ]).joined(separator: " ").lowercased()
        return haystack.contains("grok")
    }

    private func isGrokAtom(_ atom: MemoryAtom) -> Bool {
        guard atom.privacyClass != "restricted" else { return false }
        let haystack = (atom.tags + [atom.atomType, atom.text]).joined(separator: " ").lowercased()
        return haystack.contains("grok")
    }

    var bodyLoopTitle: String {
        if readinessLabel != "—" {
            return "Body \(readinessLabel)"
        }
        if physio.summary.authorizationState == .authorized {
            return physio.summary.readiness.title
        }
        return "Body loop"
    }

    var bodyLoopDetail: String {
        if physio.summary.isMeaningful {
            return physio.summary.detailLine
        }
        return bodyContextLine ?? "Waiting for Ultra 2 and HealthKit samples."
    }
}
