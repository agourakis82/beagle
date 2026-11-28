//
//  BeagleSurface+MemoryLensTabs.swift
//  BeagleCockpit
//
//  Deep-dive lab bench tab views for MemoryLensSheet.
//

import SwiftUI
import BeagleCore

extension MemoryLensSheet {
    var evidenceTab: some View {
        VStack(alignment: .leading, spacing: BeagleSpacing.md) {
            queryBar
            if let graph = exocortex.lastGraphRagQuery?.value {
                graphResult(graph)
            }
            recentGraph
        }
    }

    var timelineTab: some View {
        VStack(alignment: .leading, spacing: BeagleSpacing.sm) {
            sectionTitle("RECENT EPISODES")
            let episodes = (exocortex.recentGraph?.value?.episodes ?? []).filter(isDisplayableEpisode)
            if episodes.isEmpty {
                emptyRow("No projected episodes yet.")
            } else {
                ForEach(episodes.prefix(16)) { episode in
                    GlassPanel(truth: .remembered) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(episode.title ?? episode.sourceRef)
                                .font(BeagleFont.caption.font)
                                .fontWeight(.semibold)
                                .foregroundStyle(BeagleTheme.textPrimary)
                                .lineLimit(2)
                            Text("\(episode.source) · \(episode.sourcePlatform ?? "unknown") · \(episode.occurredAt ?? episode.createdAt)")
                                .font(BeagleFont.caption2.font)
                                .foregroundStyle(BeagleTheme.textTertiary)
                                .lineLimit(1)
                            Text(episode.tags.prefix(5).joined(separator: " · "))
                                .font(BeagleFont.caption2.font)
                                .foregroundStyle(BeagleTheme.textTertiary)
                                .lineLimit(1)
                        }
                    }
                }
            }
        }
    }

    private var sounioWorkdaySnapshot: SounioWorkdaySnapshot? {
        exocortex.sounioWorkday?.value ?? exocortex.home.value?.sounioWorkdayContext
    }

    var sounioWorkdayTab: some View {
        VStack(alignment: .leading, spacing: BeagleSpacing.md) {
            sectionTitle("SOUNIO WORKDAY")
            if let workday = sounioWorkdaySnapshot {
                GlassPanel(truth: exocortex.sounioWorkday?.mode ?? exocortex.home.mode) {
                    VStack(alignment: .leading, spacing: BeagleSpacing.xs) {
                        HStack {
                            Text(workday.status.uppercased())
                                .font(BeagleFont.caption2.font)
                                .fontWeight(.semibold)
                                .foregroundStyle(BeagleTheme.truthDeclared)
                            Spacer()
                            Text("\(workday.moments.count) moments")
                                .font(BeagleFont.caption2.font.monospaced())
                                .foregroundStyle(BeagleTheme.textTertiary)
                        }
                        Text(workday.nextAction)
                            .font(BeagleFont.caption.font)
                            .foregroundStyle(BeagleTheme.textPrimary)
                            .fixedSize(horizontal: false, vertical: true)
                        if !workday.tensions.isEmpty {
                            Text("tension · \(workday.tensions.prefix(2).joined(separator: " · "))")
                                .font(BeagleFont.caption2.font)
                                .foregroundStyle(BeagleTheme.textTertiary)
                                .lineLimit(3)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }

                if !workday.decisionSeeds.isEmpty {
                    sectionTitle("DECISIONS")
                    ForEach(Array(workday.decisionSeeds.prefix(6).enumerated()), id: \.offset) { _, decision in
                        lensTextRow("checkmark.circle", "Decision seed", decision, tint: BeagleTheme.truthObserved)
                    }
                }

                if !workday.claimSeeds.isEmpty {
                    sectionTitle("CLAIM<T> SEEDS")
                    ForEach(workday.claimSeeds.prefix(8)) { claim in
                        GlassPanel(truth: .declared) {
                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    Text(claim.epistemicStatus.uppercased())
                                        .font(BeagleFont.caption2.font)
                                        .fontWeight(.semibold)
                                        .foregroundStyle(claim.epistemicStatus == "contest" ? BeagleTheme.postureWarm : BeagleTheme.truthDeclared)
                                    Spacer()
                                    Text(claim.reviewState)
                                        .font(BeagleFont.caption2.font.monospaced())
                                        .foregroundStyle(BeagleTheme.textTertiary)
                                }
                                Text(claim.claimText)
                                    .font(BeagleFont.caption.font)
                                    .foregroundStyle(BeagleTheme.textPrimary)
                                    .fixedSize(horizontal: false, vertical: true)
                                Text(claim.evidenceRefs.prefix(2).joined(separator: " · "))
                                    .font(BeagleFont.caption2.font.monospaced())
                                    .foregroundStyle(BeagleTheme.textTertiary)
                                    .lineLimit(1)
                            }
                        }
                    }
                }

                sectionTitle("MOMENTS")
                if workday.moments.isEmpty {
                    emptyRow("No Sounio moments yet.")
                } else {
                    ForEach(workday.moments.prefix(16)) { moment in
                        sounioMomentRow(moment)
                    }
                }
            } else {
                emptyRow("Sounio Workday has not been observed yet.")
            }
        }
    }

    var worldsTab: some View {
        VStack(alignment: .leading, spacing: BeagleSpacing.sm) {
            sectionTitle("MEMORY WORLDS")
            let worlds = exocortex.recentWorlds?.value?.worlds ?? exocortex.recentGraph?.value?.worlds ?? []
            if worlds.isEmpty {
                emptyRow("No content-addressed MemoryWorlds yet. Index the graph after the next import.")
            } else {
                ForEach(worlds.prefix(16)) { world in
                    GlassPanel(truth: .observed) {
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(world.worldType.uppercased())
                                    .font(BeagleFont.caption2.font)
                                    .fontWeight(.semibold)
                                    .foregroundStyle(BeagleTheme.truthObserved)
                                Spacer()
                                Text("\(world.nodeCount)n \(world.edgeCount)e")
                                    .font(BeagleFont.caption2.font)
                                    .foregroundStyle(BeagleTheme.textTertiary)
                            }
                            Text(world.title ?? world.sourceRef)
                                .font(BeagleFont.caption.font)
                                .foregroundStyle(BeagleTheme.textPrimary)
                                .lineLimit(2)
                            Text(world.merkleRoot)
                                .font(BeagleFont.caption2.font.monospaced())
                                .foregroundStyle(BeagleTheme.textTertiary)
                                .lineLimit(1)
                        }
                    }
                }
            }
        }
    }

    var workTab: some View {
        VStack(alignment: .leading, spacing: BeagleSpacing.sm) {
            sectionTitle("WORK MEMORY")
            let workAtoms = (exocortex.recentGraph?.value?.atoms ?? []).filter { atom in
                let haystack = (atom.tags + [atom.atomType, atom.text]).joined(separator: " ").lowercased()
                return isDisplayableAtom(atom) && (haystack.contains("work-memory")
                    || haystack.contains("codex")
                    || haystack.contains("claude-code")
                    || haystack.contains("agent:"))
            }
            if let latest = exocortex.home.value?.trustContext?.latestAgentWrite {
                Text("latest agent write · \(latest)")
                    .font(BeagleFont.caption.font)
                    .foregroundStyle(BeagleTheme.textSecondary)
            }
            if let latestWorkMemoryLine {
                Text("latest work event · \(latestWorkMemoryLine)")
                    .font(BeagleFont.caption.font)
                    .foregroundStyle(BeagleTheme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let latestGrokImportLine {
                Text("grok corpus signal · \(latestGrokImportLine)")
                    .font(BeagleFont.caption.font)
                    .foregroundStyle(BeagleTheme.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if workAtoms.isEmpty {
                emptyRow("No Codex or Claude Code work-memory atoms observed yet.")
            } else {
                ForEach(workAtoms.prefix(12)) { atom in
                    memoryAtomRow(atom)
                }
            }
        }
    }

    var contradictionsTab: some View {
        VStack(alignment: .leading, spacing: BeagleSpacing.sm) {
            sectionTitle("CONTRADICTIONS")
            let contradictions = exocortex.memoryContradictions?.value?.contradictions ?? []
            let relations = (exocortex.recentGraph?.value?.relations ?? []).filter {
                $0.predicate.lowercased().contains("contradict")
                    || $0.predicate.lowercased().contains("conflict")
                    || $0.predicate.lowercased().contains("tension")
            }
            if !contradictions.isEmpty {
                ForEach(contradictions.prefix(20)) { contradiction in
                    GlassPanel(truth: .declared) {
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text("CONTRADICTION")
                                    .font(BeagleFont.caption2.font)
                                    .fontWeight(.semibold)
                                    .foregroundStyle(BeagleTheme.truthDeclared)
                                Spacer()
                                Text("\(contradiction.severity) · \(contradiction.status)")
                                    .font(BeagleFont.caption2.font)
                                    .foregroundStyle(BeagleTheme.textTertiary)
                            }
                            Text(contradiction.description)
                                .font(BeagleFont.caption.font)
                                .foregroundStyle(BeagleTheme.textPrimary)
                                .fixedSize(horizontal: false, vertical: true)
                            Text("\(contradiction.subjectRef) ↔ \(contradiction.conflictingRef)")
                                .font(BeagleFont.caption2.font.monospaced())
                                .foregroundStyle(BeagleTheme.textTertiary)
                                .lineLimit(1)
                        }
                    }
                }
            } else if relations.isEmpty {
                emptyRow("No explicit contradiction relations observed in the recent graph.")
            } else {
                ForEach(relations.indices, id: \.self) { index in
                    relationRow(relations[index])
                }
            }
        }
    }

    var candidatesTab: some View {
        VStack(alignment: .leading, spacing: BeagleSpacing.sm) {
            sectionTitle("TRIAD REVIEW")
            if let governance = exocortex.memoryGovernanceStatus?.value {
                GlassPanel(truth: .observed) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("\(governance.status) · \(governance.candidateCount) candidates")
                            .font(BeagleFont.caption.font)
                            .fontWeight(.semibold)
                            .foregroundStyle(BeagleTheme.textPrimary)
                        Text("\(governance.pendingTriads) pending · \(governance.promotedCount) promoted · \(governance.rejectedCount) rejected · \(governance.openContradictions) contradictions")
                            .font(BeagleFont.caption2.font)
                            .foregroundStyle(BeagleTheme.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                        if let decision = governance.latestPromotionDecision {
                            Text("latest \(decision.decision) · \(decision.rationale)")
                                .font(BeagleFont.caption2.font)
                                .foregroundStyle(BeagleTheme.textTertiary)
                                .lineLimit(2)
                        }
                    }
                }
            }
            let candidates = (exocortex.memoryCandidates?.value?.candidates ?? []).filter {
                $0.privacyClass.lowercased() != "restricted" && !containsRestrictedMarker($0.text)
            }
            if candidates.isEmpty {
                emptyRow("No candidate atoms or hyperedges awaiting Triad quorum.")
            } else {
                ForEach(candidates.prefix(20)) { candidate in
                    GlassPanel(truth: .declared) {
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(candidate.candidateType.uppercased())
                                    .font(BeagleFont.caption2.font)
                                    .fontWeight(.semibold)
                                    .foregroundStyle(BeagleTheme.truthDeclared)
                                Spacer()
                                Text(candidate.status)
                                    .font(BeagleFont.caption2.font)
                                    .foregroundStyle(BeagleTheme.textTertiary)
                            }
                            Text(candidate.text)
                                .font(BeagleFont.caption.font)
                                .foregroundStyle(BeagleTheme.textPrimary)
                                .fixedSize(horizontal: false, vertical: true)
                            Text("confidence \(String(format: "%.2f", candidate.confidence)) · \(candidate.privacyClass)")
                                .font(BeagleFont.caption2.font)
                                .foregroundStyle(BeagleTheme.textTertiary)
                            if let quorum = candidate.quorumRef {
                                Text("triad quorum · \(quorum)")
                                    .font(BeagleFont.caption2.font.monospaced())
                                    .foregroundStyle(BeagleTheme.textTertiary)
                                    .lineLimit(1)
                            }
                            if candidate.status == "triad_pending" {
                                Text("pending strict 3/3 promotion; Home/search stay promoted-only")
                                    .font(BeagleFont.caption2.font)
                                    .foregroundStyle(BeagleTheme.textTertiary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                }
            }
        }
    }

    var benchTab: some View {
        VStack(alignment: .leading, spacing: BeagleSpacing.sm) {
            sectionTitle("MEMORY BENCH")
            if let bench = exocortex.benchmarkStatus?.value {
                GlassPanel(truth: bench.status == "passing" ? .observed : .declared) {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(bench.status.uppercased())
                                .font(BeagleFont.caption2.font)
                                .fontWeight(.semibold)
                                .foregroundStyle(bench.status == "passing" ? BeagleTheme.truthObserved : BeagleTheme.truthDeclared)
                            Spacer()
                            if let score = bench.latestScore {
                                Text(String(format: "%.2f", score))
                                    .font(BeagleFont.caption2.font.monospaced())
                                    .foregroundStyle(BeagleTheme.textTertiary)
                            }
                        }
                        Text("\(bench.queryCount) queries · \(bench.regressionCount) regressions")
                            .font(BeagleFont.caption.font)
                            .foregroundStyle(BeagleTheme.textSecondary)
                        if !bench.evaluatedModes.isEmpty {
                            Text(bench.evaluatedModes.joined(separator: " · "))
                                .font(BeagleFont.caption2.font)
                                .foregroundStyle(BeagleTheme.textTertiary)
                                .lineLimit(2)
                        }
                        if let reason = bench.degradedReason {
                            Text(reason)
                                .font(BeagleFont.caption2.font)
                                .foregroundStyle(BeagleTheme.textTertiary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                if let latest = bench.latestRun {
                    ForEach(latest.modeResults.prefix(6)) { result in
                        GlassPanel(truth: result.status.contains("pass") ? .observed : .declared) {
                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    Text(result.mode.uppercased())
                                        .font(BeagleFont.caption2.font)
                                        .fontWeight(.semibold)
                                        .foregroundStyle(BeagleTheme.truthObserved)
                                    Spacer()
                                    Text(String(format: "%.2f", result.score))
                                        .font(BeagleFont.caption2.font.monospaced())
                                        .foregroundStyle(BeagleTheme.textTertiary)
                                }
                                Text(result.status)
                                    .font(BeagleFont.caption.font)
                                    .foregroundStyle(BeagleTheme.textSecondary)
                                if let metrics = result.metrics {
                                    Text("top-k \(String(format: "%.2f", metrics.topKHitRate ?? 0)) · provenance \(String(format: "%.2f", metrics.provenanceCompleteness ?? 0)) · leaks \(metrics.restrictedLeakCount ?? 0)")
                                        .font(BeagleFont.caption2.font)
                                        .foregroundStyle(BeagleTheme.textTertiary)
                                }
                            }
                        }
                    }
                }
            } else if let trust = exocortex.home.value?.trustContext,
                      let status = trust.memoryBenchStatus {
                emptyRow("Bench \(status) observed in Home; open cluster status for detailed mode scores.")
            } else {
                emptyRow("No Memory Bench run observed yet.")
            }
        }
    }

    var truthTab: some View {
        VStack(alignment: .leading, spacing: BeagleSpacing.sm) {
            sectionTitle("MEMORY TRUTH")
            if let bench = exocortex.benchmarkStatus?.value {
                GlassPanel(truth: bench.hotPathEligible ? .observed : .declared) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(bench.hotPathEligible ? "HOT PATH ELIGIBLE" : "SHADOW GATE")
                            .font(BeagleFont.caption2.font)
                            .fontWeight(.semibold)
                            .foregroundStyle(bench.hotPathEligible ? BeagleTheme.truthObserved : BeagleTheme.truthDeclared)
                        if let truthsetId = bench.truthsetId {
                            Text("truthset \(truthsetId)")
                                .font(BeagleFont.caption.font.monospaced())
                                .foregroundStyle(BeagleTheme.textSecondary)
                                .lineLimit(2)
                        }
                        if let gate = bench.promotionGate {
                            Text("\(gate.candidateMode) vs \(gate.baselineMode) · margin \(String(format: "%.2f", gate.requiredMargin)) · runs \(gate.consecutivePassingRuns)/\(gate.requiredConsecutiveRuns)")
                                .font(BeagleFont.caption.font)
                                .foregroundStyle(BeagleTheme.textSecondary)
                            Text(gate.rationale)
                                .font(BeagleFont.caption2.font)
                                .foregroundStyle(BeagleTheme.textTertiary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                if let latest = bench.latestRun, !latest.caseJudgments.isEmpty {
                    ForEach(latest.caseJudgments.prefix(8)) { judgment in
                        GlassPanel(truth: judgment.passed ? .observed : .declared) {
                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    Text(judgment.domain.uppercased())
                                        .font(BeagleFont.caption2.font)
                                        .fontWeight(.semibold)
                                        .foregroundStyle(judgment.passed ? BeagleTheme.truthObserved : BeagleTheme.postureWarm)
                                    Spacer()
                                    Text(String(format: "%.2f", judgment.score))
                                        .font(BeagleFont.caption2.font.monospaced())
                                        .foregroundStyle(BeagleTheme.textTertiary)
                                }
                                Text(judgment.query)
                                    .font(BeagleFont.caption.font)
                                    .foregroundStyle(BeagleTheme.textSecondary)
                                    .fixedSize(horizontal: false, vertical: true)
                                if !judgment.supportingRefs.isEmpty {
                                    Text(judgment.supportingRefs.prefix(4).joined(separator: " · "))
                                        .font(BeagleFont.caption2.font)
                                        .foregroundStyle(BeagleTheme.textTertiary)
                                        .lineLimit(2)
                                }
                            }
                        }
                    }
                }
            } else if let trust = exocortex.home.value?.trustContext {
                let gate = trust.benchHotPathEligible == true ? "eligible" : "shadow"
                emptyRow("Truth gate \(gate); truthset \(trust.truthsetId ?? "not observed").")
            } else {
                emptyRow("No truthset gate observed yet.")
            }

            sectionTitle("CAPTURE LOOP")
            if let trust = exocortex.home.value?.trustContext {
                let observer = trust.agentObserverStatus ?? "not-observed"
                let capture = trust.captureLoopStatus ?? "pending-first-capture"
                let apple = trust.appleCaptureFreshness ?? "no Apple capture"
                emptyRow("Agent observer \(observer) · \(capture) · Apple \(apple)")
            } else {
                emptyRow("Home trust context not loaded.")
            }
        }
    }

    var agentTraceTab: some View {
        VStack(alignment: .leading, spacing: BeagleSpacing.sm) {
            sectionTitle("RETRIEVAL AGENT")
            if let graph = exocortex.lastGraphRagQuery?.value {
                GlassPanel(truth: graph.retrievalAgent == "default" ? .observed : .declared) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text((graph.strategyUsed ?? "strategy pending").uppercased())
                            .font(BeagleFont.caption2.font)
                            .fontWeight(.semibold)
                            .foregroundStyle(BeagleTheme.truthObserved)
                        Text("\(graph.retrievalAgent ?? "agent") · planner \(graph.plannerMode ?? "hybrid") · \(graph.contextFormat ?? "context pack pending")")
                            .font(BeagleFont.caption.font)
                            .foregroundStyle(BeagleTheme.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                        if let plan = graph.retrievalPlanId {
                            Text(plan)
                                .font(BeagleFont.caption2.font.monospaced())
                                .foregroundStyle(BeagleTheme.textTertiary)
                                .lineLimit(1)
                        }
                    }
                }
                if !graph.subqueries.isEmpty {
                    sectionTitle("SUBQUERIES")
                    ForEach(Array(graph.subqueries.prefix(6).enumerated()), id: \.offset) { _, item in
                        Text(item)
                            .font(BeagleFont.caption.font)
                            .foregroundStyle(BeagleTheme.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                if let pack = graph.evidencePack {
                    sectionTitle("EVIDENCE PACK")
                    Text(String(describing: pack))
                        .font(BeagleFont.caption2.font)
                        .foregroundStyle(BeagleTheme.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if !graph.runtimeTrace.isEmpty {
                    sectionTitle("AGENT TRACE")
                    ForEach(graph.runtimeTrace.prefix(10)) { step in
                        GlassPanel(truth: step.status.contains("fallback") ? .declared : .observed) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(step.stage.uppercased())
                                    .font(BeagleFont.caption2.font)
                                    .fontWeight(.semibold)
                                    .foregroundStyle(BeagleTheme.textTertiary)
                                Text("\(step.backend) · \(step.status) · \(step.items) items")
                                    .font(BeagleFont.caption.font)
                                    .foregroundStyle(BeagleTheme.textSecondary)
                                if !step.notes.isEmpty {
                                    Text(step.notes.prefix(3).joined(separator: " · "))
                                        .font(BeagleFont.caption2.font)
                                        .foregroundStyle(BeagleTheme.textTertiary)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                            }
                        }
                    }
                }
            } else if let trust = exocortex.home.value?.trustContext {
                emptyRow("Retrieval \(trust.retrievalAgentStatus ?? "not observed") · strategy \(trust.latestRetrievalStrategy ?? "pending") · arena \(trust.memoryarenaGate ?? "shadow")")
            } else {
                emptyRow("Run a Memory Lens query to see Retrieval Agent plan, evidence pack and runtime trace.")
            }
        }
    }

    var runtimeTraceTab: some View {
        VStack(alignment: .leading, spacing: BeagleSpacing.sm) {
            sectionTitle("RUNTIME VOTES")
            if let graph = exocortex.lastGraphRagQuery?.value, !graph.runtimeVotes.isEmpty {
                ForEach(graph.runtimeVotes.prefix(12)) { vote in
                    GlassPanel(truth: vote.status == "available" ? .observed : .declared) {
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(vote.runtime.uppercased())
                                    .font(BeagleFont.caption2.font)
                                    .fontWeight(.semibold)
                                    .foregroundStyle(BeagleTheme.truthObserved)
                                Spacer()
                                Text(String(format: "%.2f", vote.score))
                                    .font(BeagleFont.caption2.font.monospaced())
                                    .foregroundStyle(BeagleTheme.textTertiary)
                            }
                            Text("\(vote.role) · \(vote.status)")
                                .font(BeagleFont.caption.font)
                                .foregroundStyle(BeagleTheme.textSecondary)
                            if !vote.notes.isEmpty {
                                Text(vote.notes.prefix(3).joined(separator: " · "))
                                    .font(BeagleFont.caption2.font)
                                    .foregroundStyle(BeagleTheme.textTertiary)
                                    .lineLimit(2)
                            }
                        }
                    }
                }
            } else {
                emptyRow("Run a Memory Lens query to see federated runtime votes.")
            }

            sectionTitle("MESH TRACE")
            let trace = exocortex.lastGraphRagQuery?.value?.meshTrace
                ?? exocortex.lastGraphRagQuery?.value?.retrievalTrace
                ?? []
            if trace.isEmpty {
                emptyRow("No retrieval trace observed yet.")
            } else {
                ForEach(trace.prefix(12)) { step in
                    Text("\(step.stage) · \(step.backend) · \(step.status) · \(step.items) items · \(String(format: "%.1f", step.latencyMs))ms")
                        .font(BeagleFont.caption2.font)
                        .foregroundStyle(BeagleTheme.textTertiary)
                        .lineLimit(2)
                }
            }
        }
    }

    var contextTab: some View {
        VStack(alignment: .leading, spacing: BeagleSpacing.sm) {
            sectionTitle("ADAPTIVE CONTEXT")
            if let graph = exocortex.lastGraphRagQuery?.value {
                GlassPanel(truth: graph.contextPackId == nil ? .declared : .observed) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("CONTEXT PACK")
                            .font(BeagleFont.caption2.font)
                            .fontWeight(.semibold)
                            .foregroundStyle(BeagleTheme.truthObserved)
                        Text(graph.contextPackId ?? "context pack pending")
                            .font(BeagleFont.caption.font.monospaced())
                            .foregroundStyle(BeagleTheme.textSecondary)
                            .lineLimit(2)
                        Text("\(graph.policyVersion ?? "policy unknown") · \(graph.contextFormat ?? "format pending")")
                            .font(BeagleFont.caption2.font)
                            .foregroundStyle(BeagleTheme.textTertiary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                sectionTitle("WHY THIS MEMORY")
                if !graph.subqueries.isEmpty {
                    ForEach(Array(graph.subqueries.prefix(4).enumerated()), id: \.offset) { _, subquery in
                        Text(subquery)
                            .font(BeagleFont.caption.font)
                            .foregroundStyle(BeagleTheme.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                } else {
                    emptyRow("No subqueries recorded yet.")
                }

                sectionTitle("POLICY")
                Text("DreamCycle \(graph.dreamcycleStatus ?? "manual")")
                    .font(BeagleFont.caption.font)
                    .foregroundStyle(BeagleTheme.textSecondary)
                if let policyGate = graph.policyGate {
                    Text(String(describing: policyGate))
                        .font(BeagleFont.caption2.font)
                        .foregroundStyle(BeagleTheme.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if let leak = graph.restrictedLeakCheck {
                    Text(String(describing: leak))
                        .font(BeagleFont.caption2.font)
                        .foregroundStyle(BeagleTheme.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            } else if let trust = exocortex.home.value?.trustContext {
                emptyRow("Compiler \(trust.contextCompilerStatus ?? "shadow") · policy \(trust.memoryPolicyStatus ?? "observe") · DreamCycle \(trust.dreamcycleStatus ?? "manual-ready")")
                if let paper = trust.sounioPaperRunStatus {
                    emptyRow("Sounio PaperRun \(paper)")
                }
                if let pending = trust.sounioPendingApproval {
                    emptyRow("Approval pending · \(pending)")
                }
                if let pack = trust.latestContextPackId {
                    emptyRow("Latest ContextPack \(pack)")
                }
            } else {
                emptyRow("Run a Memory Lens query to see ContextPack, policy gate and DreamCycle status.")
            }
        }
    }

    var semanticTraceTab: some View {
        VStack(alignment: .leading, spacing: BeagleSpacing.sm) {
            sectionTitle("SEMANTIC TRACE")
            if let graph = exocortex.lastGraphRagQuery?.value {
                GlassPanel(truth: graph.runtimeUsed?.contains("fallback") == true ? .declared : .observed) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text((graph.runtimeUsed ?? graph.mode ?? "unknown").uppercased())
                            .font(BeagleFont.caption2.font)
                            .fontWeight(.semibold)
                            .foregroundStyle(BeagleTheme.truthObserved)
                        if !graph.fallbackChain.isEmpty {
                            Text(graph.fallbackChain.joined(separator: " -> "))
                                .font(BeagleFont.caption.font)
                                .foregroundStyle(BeagleTheme.textSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        if let gate = graph.truthsetGateStatus {
                            let gateLabel = gate.confirmedPassing ? "confirmed" : (gate.provisionalHotPath ? "provisional" : "shadow")
                            Text("Portfolio gate \(gateLabel) · \(gate.portfolioTruthsetId ?? gate.truthsetId ?? "truthset pending")")
                                .font(BeagleFont.caption2.font)
                                .foregroundStyle(BeagleTheme.textTertiary)
                                .lineLimit(2)
                        }
                    }
                }
                ForEach(graph.semanticTrace.prefix(10)) { step in
                    GlassPanel(truth: step.status == "ready" || step.status == "ok" ? .observed : .declared) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(step.stage.uppercased())
                                .font(BeagleFont.caption2.font)
                                .fontWeight(.semibold)
                                .foregroundStyle(BeagleTheme.textTertiary)
                            Text("\(step.backend) · \(step.status) · \(step.items) items")
                                .font(BeagleFont.caption.font)
                                .foregroundStyle(BeagleTheme.textSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                            if !step.notes.isEmpty {
                                Text(step.notes.prefix(3).joined(separator: " · "))
                                    .font(BeagleFont.caption2.font)
                                    .foregroundStyle(BeagleTheme.textTertiary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                }
                if !graph.maxsimScores.isEmpty {
                    sectionTitle("MAXSIM")
                    ForEach(Array(graph.maxsimScores.prefix(5).enumerated()), id: \.offset) { _, score in
                        Text(String(describing: score))
                            .font(BeagleFont.caption2.font)
                            .foregroundStyle(BeagleTheme.textTertiary)
                            .lineLimit(3)
                    }
                }
                if !graph.rerankerScores.isEmpty {
                    sectionTitle("RERANK")
                    ForEach(Array(graph.rerankerScores.prefix(5).enumerated()), id: \.offset) { _, score in
                        Text(String(describing: score))
                            .font(BeagleFont.caption2.font)
                            .foregroundStyle(BeagleTheme.textTertiary)
                            .lineLimit(3)
                    }
                }
                if let expansion = graph.graphExpansion {
                    sectionTitle("GRAPH EXPANSION")
                    Text(String(describing: expansion))
                        .font(BeagleFont.caption2.font)
                        .foregroundStyle(BeagleTheme.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            } else {
                emptyRow("Run a Memory Lens query to see MaxSim/late-interaction, graph expansion, rerank, provenance, and fallback trace.")
            }
        }
    }
}
