//
//  BeagleSurface+MemoryLens.swift
//  BeagleCockpit
//
//  MemoryLensSheet core shell, living report layer, query bar, graph results, and shared helpers.
//

import SwiftUI
import BeagleCore

// MARK: - Memory Lens

struct MemoryLensSheet: View {
    let exocortex: ExocortexStore
    let activeProjectSlug: String
    @State var query = ""
    @State private var isSearching = false
    @State private var selectedTab: LensTab = .evidence
    @State private var lensMode: MemoryLensMode = .report
    @State private var selectedProof: ProofSheetModel? = nil

    init(exocortex: ExocortexStore, activeProjectSlug: String) {
        self.exocortex = exocortex
        self.activeProjectSlug = activeProjectSlug
    }

    private enum LensTab: String, CaseIterable, Identifiable {
        case evidence = "Evidence"
        case timeline = "Timeline"
        case sounioWorkday = "Sounio"
        case worlds = "Worlds"
        case work = "Work"
        case contradictions = "Contradictions"
        case candidates = "Candidates"
        case truth = "Truth"
        case bench = "Bench"
        case context = "Context"
        case agentTrace = "Agent"
        case semanticTrace = "Semantic"
        case runtimeTrace = "Runtime"

        var id: String { rawValue }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: BeagleSpacing.md) {
                livingReportLayer
                deepDiveToggle
                if lensMode == .deepDive {
                    deepDiveLayer
                }
            }
            .padding(BeagleSpacing.lg)
        }
        .navigationTitle("Memory Lens")
        .background(BeagleTheme.surface0.ignoresSafeArea())
        .sheet(item: $selectedProof) { proof in
            ProofSheet(model: proof)
        }
        .task {
            async let graphStatus: Void = exocortex.refreshGraphStatus()
            async let benchmark: Void = exocortex.refreshBenchmarkStatus()
            async let recentGraph: Void = exocortex.refreshRecentGraph(limit: 16)
            async let worlds: Void = exocortex.refreshRecentWorlds(limit: 16)
            async let candidates: Void = exocortex.refreshMemoryCandidates(limit: 20)
            async let governance: Void = exocortex.refreshMemoryGovernanceStatus()
            async let contradictions: Void = exocortex.refreshMemoryContradictions(limit: 20)
            async let sounioWorkday: Void = exocortex.refreshSounioWorkday(projectSlug: activeProjectSlug, limit: 25)
            async let sounioMoments: Void = exocortex.refreshRecentSounioMoments(projectSlug: activeProjectSlug, limit: 25)
            if let truthsetId = exocortex.home.value?.trustContext?.truthsetId {
                async let truthset: Void = exocortex.refreshTruthSetStatus(id: truthsetId)
                _ = await (graphStatus, benchmark, recentGraph, worlds, candidates, governance, contradictions, sounioWorkday, sounioMoments, truthset)
            } else {
                _ = await (graphStatus, benchmark, recentGraph, worlds, candidates, governance, contradictions, sounioWorkday, sounioMoments)
            }
        }
    }

    private var report: MemoryLensReport {
        MemoryLensReport.synthesized(
            home: exocortex.home.value,
            homeTruthMode: exocortex.home.mode,
            graphStatus: exocortex.graphStatus?.value,
            recentGraph: exocortex.recentGraph?.value,
            benchmark: exocortex.benchmarkStatus?.value,
            governance: exocortex.memoryGovernanceStatus?.value,
            contradictions: exocortex.memoryContradictions?.value,
            lastQuery: exocortex.lastGraphRagQuery?.value,
            activeProjectSlug: activeProjectSlug
        )
    }

    private var livingReportLayer: some View {
        let report = report
        return VStack(alignment: .leading, spacing: BeagleSpacing.md) {
            LivingMemoryReportHeader(report: report) {
                selectedProof = report.proof
            }
            SourceConfidenceStrip(report: report)
            MemoryQuestionDock(
                query: $query,
                isSearching: isSearching,
                onSubmit: {
                    Task { await runQuery() }
                }
            )
            LensPresetRail(presets: report.presets) { preset in
                Task { await runPreset(preset) }
            }
            EvidenceFrontier(report: report) { proof in
                selectedProof = proof
            }
        }
    }

    private var deepDiveToggle: some View {
        Button {
            withAnimation(.snappy(duration: 0.22)) {
                lensMode = lensMode == .deepDive ? .report : .deepDive
            }
        } label: {
            HStack {
                Label(lensMode == .deepDive ? "Hide lab bench" : "Open lab bench", systemImage: "slider.horizontal.3")
                    .font(BeagleFont.caption.font)
                    .fontWeight(.semibold)
                Spacer()
                Image(systemName: lensMode == .deepDive ? "chevron.up" : "chevron.down")
                    .font(.system(size: 12, weight: .semibold))
            }
            .foregroundStyle(BeagleTheme.textSecondary)
            .padding(.horizontal, BeagleSpacing.sm)
            .padding(.vertical, BeagleSpacing.xs)
            .background(
                Capsule()
                    .fill(BeagleTheme.surface1.opacity(0.72))
            )
        }
        .buttonStyle(.plain)
    }

    private var deepDiveLayer: some View {
        VStack(alignment: .leading, spacing: BeagleSpacing.md) {
            header
            lensPicker
            switch selectedTab {
            case .evidence:
                evidenceTab
            case .timeline:
                timelineTab
            case .sounioWorkday:
                sounioWorkdayTab
            case .worlds:
                worldsTab
            case .work:
                workTab
            case .contradictions:
                contradictionsTab
            case .candidates:
                candidatesTab
            case .truth:
                truthTab
            case .bench:
                benchTab
            case .context:
                contextTab
            case .agentTrace:
                agentTraceTab
            case .semanticTrace:
                semanticTraceTab
            case .runtimeTrace:
                runtimeTraceTab
            }
        }
        .transition(.opacity.combined(with: .move(edge: .top)))
    }

    private var header: some View {
        let graphStatus = exocortex.graphStatus?.value
        let status = graphStatus?.projectionStatus
            ?? exocortex.recentGraph?.value?.status
            ?? exocortex.projectionStatus?.value
        return GlassPanel(truth: exocortex.graphStatus?.mode ?? exocortex.recentGraph?.mode ?? exocortex.projectionStatus?.mode ?? .declared) {
            VStack(alignment: .leading, spacing: BeagleSpacing.xs) {
                Text((graphStatus?.graphRuntime ?? "GRAPHRAG++").uppercased())
                    .font(BeagleFont.caption2.font)
                    .fontWeight(.semibold)
                    .foregroundStyle(BeagleTheme.textTertiary)
                Text(statusLine(status))
                    .font(BeagleFont.callout.font)
                    .foregroundStyle(BeagleTheme.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                if let graphStatus {
                    Text("\(graphStatus.retrievalMode) · \(graphStatus.worldCount) worlds")
                        .font(BeagleFont.caption.font)
                        .foregroundStyle(BeagleTheme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if let trust = exocortex.home.value?.trustContext {
                    let mesh = trust.memoryEngineStatus ?? "mesh not observed"
                    let candidate = trust.latestCandidateRef.map { " · candidate \($0.prefix(12))" } ?? ""
                    let quorum = trust.latestQuorumStatus.map { " · quorum \($0)" } ?? ""
                    let governor = trust.memoryGovernorStatus.map { " · governor \($0)" } ?? ""
                    let triad = trust.pendingTriads.map { " · pending \($0)" } ?? ""
                    let contradictions = trust.openContradictions.map { " · contradictions \($0)" } ?? ""
                    let bench = trust.memoryBenchStatus.map { " · bench \($0)" } ?? ""
                    let score = trust.latestBenchScore.map { " \(String(format: "%.2f", $0))" } ?? ""
                    let gate = trust.benchHotPathEligible.map { " · gate \($0 ? "eligible" : "shadow")" } ?? ""
                    let capture = trust.captureLoopStatus.map { " · capture \($0)" } ?? ""
                    let retrieval = trust.retrievalAgentStatus.map { " · retrieval \($0)" } ?? ""
                    let arena = trust.memoryarenaGate.map { " · arena \($0)" } ?? ""
                    Text("\(mesh)\(retrieval)\(arena)\(governor)\(triad)\(contradictions)\(bench)\(score)\(gate)\(capture)\(candidate)\(quorum)")
                        .font(BeagleFont.caption.font)
                        .foregroundStyle(BeagleTheme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if let latestWorkMemoryLine {
                    lensContextLine("work memory · \(latestWorkMemoryLine)")
                }
                if let latestGrokImportLine {
                    lensContextLine("grok import · \(latestGrokImportLine)")
                }
                if let degraded = graphStatus?.degradedReason ?? status?.degradedReason, !degraded.isEmpty {
                    Text(degraded)
                        .font(BeagleFont.caption.font)
                        .foregroundStyle(BeagleTheme.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private var lensPicker: some View {
        Picker("Lens", selection: $selectedTab) {
            ForEach(LensTab.allCases) { tab in
                Text(tab.rawValue).tag(tab)
            }
        }
        .pickerStyle(.menu)
    }

    var queryBar: some View {
        HStack(spacing: BeagleSpacing.sm) {
            TextField("Search decisions, hypotheses, evidence...", text: $query)
                .textFieldStyle(.plain)
                .font(BeagleFont.callout.font)
                .padding(.horizontal, BeagleSpacing.sm)
                .padding(.vertical, BeagleSpacing.xs)
                .background(
                    RoundedRectangle(cornerRadius: BeagleRadius.sm)
                        .fill(BeagleTheme.surface1.opacity(0.72))
                )

            Button {
                Task { await runQuery() }
            } label: {
                Image(systemName: isSearching ? "hourglass" : "magnifyingglass")
                    .font(.system(size: 14, weight: .semibold))
            }
            .buttonStyle(.borderedProminent)
            .disabled(query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSearching)
        }
    }

    var recentGraph: some View {
        VStack(alignment: .leading, spacing: BeagleSpacing.sm) {
            sectionTitle("RECENT PROJECTED ATOMS")

            let atoms = (exocortex.recentGraph?.value?.atoms ?? []).filter(isDisplayableAtom)
            if atoms.isEmpty {
                emptyRow("No projected atoms yet. Capture or import context to wake the graph.")
            } else {
                ForEach(atoms.prefix(12)) { atom in
                    memoryAtomRow(atom)
                }
            }
        }
    }

    func graphResult(_ result: GraphRagQueryResponse) -> some View {
        VStack(alignment: .leading, spacing: BeagleSpacing.sm) {
            Text("QUERY RESULT")
                .font(BeagleFont.caption2.font)
                .fontWeight(.semibold)
                .foregroundStyle(BeagleTheme.textTertiary)
            Text(result.summary)
                .font(BeagleFont.callout.font)
                .foregroundStyle(BeagleTheme.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
            if let runtime = result.runtimeUsed ?? result.mode {
                Text("\(runtime) · \(result.fallbackChain.joined(separator: " -> "))")
                    .font(BeagleFont.caption2.font)
                    .foregroundStyle(BeagleTheme.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let pack = result.contextPackId {
                Text("context \(pack) · \(result.policyVersion ?? "policy unknown") · DreamCycle \(result.dreamcycleStatus ?? "manual")")
                    .font(BeagleFont.caption2.font.monospaced())
                    .foregroundStyle(BeagleTheme.textTertiary)
                    .lineLimit(2)
            }
            ForEach(result.evidence.filter(isDisplayableEvidence).prefix(6), id: \.atomId) { evidence in
                GlassPanel(truth: .observed) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(evidence.atomType.uppercased())
                            .font(BeagleFont.caption2.font)
                            .fontWeight(.semibold)
                            .foregroundStyle(BeagleTheme.truthObserved)
                        Text(evidence.text)
                            .font(BeagleFont.caption.font)
                            .foregroundStyle(BeagleTheme.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                        Text("score \(String(format: "%.2f", evidence.score)) · \(evidence.episodeId)")
                            .font(BeagleFont.caption2.font)
                            .foregroundStyle(BeagleTheme.textTertiary)
                    }
                }
            }
            if let graph = result.evidenceGraph {
                Text("evidence graph · \(graph.nodes.count) nodes · \(graph.edges.count) edges · \(graph.merkleRoot)")
                    .font(BeagleFont.caption2.font.monospaced())
                    .foregroundStyle(BeagleTheme.textTertiary)
                    .lineLimit(2)
            }
            if let trace = result.retrievalTrace, !trace.isEmpty {
                ForEach(trace.prefix(4)) { step in
                    Text("\(step.stage) · \(step.backend) · \(step.status) · \(step.items)")
                        .font(BeagleFont.caption2.font)
                        .foregroundStyle(BeagleTheme.textTertiary)
                        .lineLimit(1)
                }
            }
            if !result.semanticTrace.isEmpty {
                ForEach(result.semanticTrace.prefix(3)) { step in
                    Text("\(step.stage) · \(step.backend) · \(step.status)")
                        .font(BeagleFont.caption2.font)
                        .foregroundStyle(BeagleTheme.textTertiary)
                        .lineLimit(1)
                }
            }
            if !result.runtimeVotes.isEmpty {
                Text("runtime votes · \(result.runtimeVotes.prefix(4).map { "\($0.runtime):\($0.status)" }.joined(separator: " · "))")
                    .font(BeagleFont.caption2.font)
                    .foregroundStyle(BeagleTheme.textTertiary)
                    .lineLimit(2)
            }
            if !result.candidateRefs.isEmpty {
                Text("candidates · \(result.candidateRefs.prefix(4).joined(separator: " · "))")
                    .font(BeagleFont.caption2.font.monospaced())
                    .foregroundStyle(BeagleTheme.textTertiary)
                    .lineLimit(2)
            }
        }
    }

    func memoryAtomRow(_ atom: MemoryAtom) -> some View {
        GlassPanel(truth: .remembered) {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(atom.atomType.uppercased())
                        .font(BeagleFont.caption2.font)
                        .fontWeight(.semibold)
                        .foregroundStyle(BeagleTheme.truthObserved)
                    Spacer()
                    Text(atom.privacyClass)
                        .font(BeagleFont.caption2.font)
                        .foregroundStyle(BeagleTheme.textTertiary)
                }
                Text(atom.text)
                    .font(BeagleFont.caption.font)
                    .foregroundStyle(BeagleTheme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                Text(atom.tags.prefix(4).joined(separator: " · "))
                    .font(BeagleFont.caption2.font)
                    .foregroundStyle(BeagleTheme.textTertiary)
                    .lineLimit(1)
            }
        }
    }

    func sounioMomentRow(_ moment: SounioMoment) -> some View {
        GlassPanel(truth: moment.reviewState == "approved" ? .observed : .declared) {
            VStack(alignment: .leading, spacing: BeagleSpacing.xs) {
                HStack(alignment: .firstTextBaseline) {
                    Text(moment.momentType.uppercased())
                        .font(BeagleFont.caption2.font)
                        .fontWeight(.semibold)
                        .foregroundStyle(BeagleTheme.truthDeclared)
                    Spacer()
                    Text(moment.reviewState)
                        .font(BeagleFont.caption2.font.monospaced())
                        .foregroundStyle(BeagleTheme.textTertiary)
                }
                Text(moment.summary)
                    .font(BeagleFont.caption.font)
                    .foregroundStyle(BeagleTheme.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                Text("\(moment.sourcePlatform) · \(moment.sourceSurface) · \(moment.updatedAt)")
                    .font(BeagleFont.caption2.font)
                    .foregroundStyle(BeagleTheme.textTertiary)
                    .lineLimit(1)
                if let next = moment.nextAction, !next.isEmpty {
                    Text("next · \(next)")
                        .font(BeagleFont.caption2.font)
                        .foregroundStyle(BeagleTheme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if moment.reviewState != "approved" && moment.privacyClass.lowercased() != "restricted" {
                    HStack(spacing: BeagleSpacing.xs) {
                        Button {
                            Task {
                                await exocortex.reviewSounioMoment(
                                    moment,
                                    decision: "approved",
                                    rationale: "Approved from Apple Memory Lens Sounio Workday."
                                )
                            }
                        } label: {
                            Label("Approve", systemImage: "checkmark.circle")
                        }
                        Button {
                            Task {
                                await exocortex.reviewSounioMoment(
                                    moment,
                                    decision: "mark_contest",
                                    rationale: "Marked contest from Apple Memory Lens Sounio Workday."
                                )
                            }
                        } label: {
                            Label("Contest", systemImage: "exclamationmark.triangle")
                        }
                    }
                    .font(BeagleFont.caption2.font)
                    .buttonStyle(.borderless)
                    .foregroundStyle(BeagleTheme.textSecondary)
                }
            }
        }
    }

    func lensTextRow(_ icon: String, _ title: String, _ text: String, tint: Color) -> some View {
        HStack(alignment: .top, spacing: BeagleSpacing.xs) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 16)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(BeagleFont.caption2.font)
                    .fontWeight(.semibold)
                    .foregroundStyle(BeagleTheme.textTertiary)
                Text(text)
                    .font(BeagleFont.caption.font)
                    .foregroundStyle(BeagleTheme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.vertical, 2)
    }

    func emptyRow(_ message: String) -> some View {
        Text(message)
            .font(BeagleFont.caption.font)
            .foregroundStyle(BeagleTheme.textTertiary)
            .padding(.vertical, BeagleSpacing.sm)
    }

    func sectionTitle(_ text: String) -> some View {
        Text(text)
            .font(BeagleFont.caption2.font)
            .fontWeight(.semibold)
            .foregroundStyle(BeagleTheme.textTertiary)
    }

    func relationRow(_ relation: MemoryRelation) -> some View {
        GlassPanel(truth: .remembered) {
            VStack(alignment: .leading, spacing: 4) {
                Text(relation.predicate.uppercased())
                    .font(BeagleFont.caption2.font)
                    .fontWeight(.semibold)
                    .foregroundStyle(BeagleTheme.truthDeclared)
                Text(relation.subject)
                    .font(BeagleFont.caption.font)
                    .foregroundStyle(BeagleTheme.textPrimary)
                    .lineLimit(2)
                Text(relation.object)
                    .font(BeagleFont.caption.font)
                    .foregroundStyle(BeagleTheme.textSecondary)
                    .lineLimit(2)
                Text("confidence \(String(format: "%.2f", relation.confidence))")
                    .font(BeagleFont.caption2.font)
                    .foregroundStyle(BeagleTheme.textTertiary)
            }
        }
    }

    private func statusLine(_ status: MemoryProjectionStatus?) -> String {
        guard let status else { return "Projection status unavailable." }
        return "\(status.status) · \(status.episodeCount) episodes · \(status.atomCount) atoms · \(status.retrievalMode)"
    }

    var latestWorkMemoryLine: String? {
        if let latest = exocortex.home.value?.trustContext?.latestAgentWrite?.trimmingCharacters(in: .whitespacesAndNewlines),
           !latest.isEmpty {
            return latest
        }
        if let latest = exocortex.home.value?.agentContext?.lastAgentWrite?.trimmingCharacters(in: .whitespacesAndNewlines),
           !latest.isEmpty {
            return latest
        }
        if let atom = (exocortex.recentGraph?.value?.atoms ?? []).first(where: isWorkMemoryAtom) {
            return "\(atom.atomType) · \(atom.text)"
        }
        return nil
    }

    var latestGrokImportLine: String? {
        if let signal = exocortex.home.value?.memorySignals.first(where: { $0.localizedCaseInsensitiveContains("grok") }) {
            return signal
        }
        if let episode = (exocortex.recentGraph?.value?.episodes ?? []).first(where: isGrokEpisode) {
            return "\(episode.title ?? episode.sourceRef) · \(episode.occurredAt ?? episode.createdAt)"
        }
        if let atom = (exocortex.recentGraph?.value?.atoms ?? []).first(where: isGrokAtom) {
            return "\(atom.atomType) · \(atom.text)"
        }
        return nil
    }

    private func lensContextLine(_ text: String) -> some View {
        Text(text)
            .font(BeagleFont.caption.font)
            .foregroundStyle(BeagleTheme.textSecondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func isWorkMemoryAtom(_ atom: MemoryAtom) -> Bool {
        guard isDisplayableAtom(atom) else { return false }
        let haystack = (atom.tags + [atom.atomType, atom.text]).joined(separator: " ").lowercased()
        return haystack.contains("work-memory")
            || haystack.contains("codex")
            || haystack.contains("claude-code")
            || haystack.contains("agent:")
    }

    private func isGrokEpisode(_ episode: MemoryEpisode) -> Bool {
        guard isDisplayableEpisode(episode) else { return false }
        let haystack = (episode.tags + [
            episode.source,
            episode.sourcePlatform ?? "",
            episode.title ?? "",
            episode.sourceRef
        ]).joined(separator: " ").lowercased()
        return haystack.contains("grok")
    }

    private func isGrokAtom(_ atom: MemoryAtom) -> Bool {
        guard isDisplayableAtom(atom) else { return false }
        let haystack = (atom.tags + [atom.atomType, atom.text]).joined(separator: " ").lowercased()
        return haystack.contains("grok")
    }

    func isDisplayableAtom(_ atom: MemoryAtom) -> Bool {
        atom.privacyClass.lowercased() != "restricted"
            && !containsRestrictedMarker(atom.text)
            && !atom.sourceRefs.contains(where: containsRestrictedMarker)
    }

    func isDisplayableEpisode(_ episode: MemoryEpisode) -> Bool {
        episode.privacyClass.lowercased() != "restricted"
            && !containsRestrictedMarker(episode.title ?? "")
            && !containsRestrictedMarker(episode.sourceRef)
    }

    private func isDisplayableEvidence(_ evidence: GraphRagEvidence) -> Bool {
        !containsRestrictedMarker(evidence.text)
            && !evidence.sourceRefs.contains(where: containsRestrictedMarker)
    }

    func containsRestrictedMarker(_ text: String) -> Bool {
        text.localizedCaseInsensitiveContains("restricted")
            || text.localizedCaseInsensitiveContains("client_secret")
            || text.localizedCaseInsensitiveContains("api_key")
    }

    private func runPreset(_ preset: MemoryLensPreset) async {
        query = preset.query
        await runQuery(preset.query)
    }

    private func runQuery(_ override: String? = nil) async {
        let candidate = override ?? query
        let trimmed = candidate.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        isSearching = true
        _ = await exocortex.queryGraphMemory(trimmed, scope: activeProjectSlug, maxItems: 8, mode: "hypermemory_multivector")
        isSearching = false
    }
}
