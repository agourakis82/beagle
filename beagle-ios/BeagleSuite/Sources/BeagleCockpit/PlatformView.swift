//
//  PlatformView.swift
//  BeagleCockpit
//
//  The operational tab — cluster health, project list, agent activity.
//  Oriented around: "Is my platform healthy? What's running?"
//

import SwiftUI
import BeagleCore

struct PlatformView: View {
    @Environment(CatalogStore.self) private var catalog
    @Environment(CognitiveStore.self) private var cognitive
    @AppStorage("selectedTab") private var selectedTab = 2
    @AppStorage("pinnedLaneQuestionsJSON") private var pinnedLaneQuestionsJSON = "{}"
    @AppStorage("cachedLaneResultsJSON") private var cachedLaneResultsJSON = "[]"
    @State private var currentLaneOverview: Truthful<MobileProjectOverview>?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: BeagleSpacing.xl) {
                currentLaneCard
                commandPresenceCard
                clusterSummary
                jobsSection
                projectsSection
                agentActivitySection
                hpcLink
            }
            .padding(.horizontal, BeagleSpacing.lg)
            .padding(.top, BeagleSpacing.md)
            .padding(.bottom, BeagleSpacing.jumbo)
        }
        .background { PostureGradientBackground(counts: catalog.postureCounts) }
        .navigationTitle("Command Room")
        .task(id: currentLaneSlug) {
            await refreshCurrentLaneOverview()
        }
        .refreshable {
            await catalog.refresh()
            await cognitive.refresh()
            await refreshCurrentLaneOverview()
        }
    }

    private var commandPresenceCard: some View {
        PresenceFieldCard(
            state: commandPresenceState,
            eyebrow: "Command Presence",
            title: "The cluster should answer back, not just report in",
            body: commandPresenceBody,
            detail: commandPresenceDetail,
            truth: commandPresenceTruth
        ) {
            HStack(spacing: BeagleSpacing.xs) {
                PresencePill(
                    label: commandPresenceLabel,
                    systemImage: "antenna.radiowaves.left.and.right",
                    tint: commandPresenceTint
                )
                PresencePill(
                    label: "\(catalog.postureCounts.totalProjects) sovereign surfaces",
                    systemImage: "square.stack.3d.up",
                    tint: BeagleTheme.truthDeclared
                )
            }
        }
    }

    // MARK: - Cluster Summary

    private var clusterSummary: some View {
        GlassPanel(elevation: .raised, truth: catalog.executive.mode) {
            VStack(alignment: .leading, spacing: BeagleSpacing.sm) {
                HStack(spacing: BeagleSpacing.xs) {
                    Image(systemName: "server.rack")
                        .font(.system(size: 14))
                        .foregroundStyle(BeagleTheme.truthObserved)
                    Text("Cluster Mind")
                        .font(BeagleFont.headline.font)
                        .foregroundStyle(BeagleTheme.textPrimary)
                    Spacer()
                    TruthBadge(catalog.executive.mode, compact: true)
                }

                let counts = catalog.postureCounts
                HStack(spacing: BeagleSpacing.lg) {
                    postureStat(count: counts.alwaysOn, label: "alive", color: BeagleTheme.postureOn)
                    postureStat(count: counts.warm, label: "warm", color: BeagleTheme.postureWarm)
                    postureStat(count: counts.cold, label: "resting", color: BeagleTheme.postureCold)
                }

                Text("\(counts.totalProjects) sovereign surfaces online")
                    .font(BeagleFont.caption.font)
                    .foregroundStyle(BeagleTheme.textTertiary)
            }
        }
    }

    @ViewBuilder
    private var currentLaneCard: some View {
        if let lane = currentLaneState {
            GlassPanel(elevation: .floating, truth: lane.truth) {
                VStack(alignment: .leading, spacing: BeagleSpacing.md) {
                    HStack(alignment: .firstTextBaseline) {
                        VStack(alignment: .leading, spacing: BeagleSpacing.xxs) {
                            Text("Current Lane")
                                .font(BeagleFont.caption.font)
                                .fontWeight(.semibold)
                                .foregroundStyle(BeagleTheme.truthObserved)
                                .textCase(.uppercase)
                                .tracking(0.8)
                            Text("\(lane.displayName) is the cluster thread in your hands")
                                .font(BeagleFont.title3.font)
                                .fontWeight(.semibold)
                                .foregroundStyle(BeagleTheme.textPrimary)
                        }
                        Spacer()
                        PresencePill(
                            label: postureLabel(for: lane.project),
                            systemImage: postureIcon(for: lane.project),
                            tint: postureTint(for: lane.project)
                        )
                    }

                    Text(lane.postureNarrative)
                        .font(BeagleFont.footnote.font)
                        .foregroundStyle(BeagleTheme.textSecondary)
                        .lineSpacing(2)

                    HStack(spacing: BeagleSpacing.xs) {
                        PresencePill(
                            label: lane.branchLabel,
                            systemImage: "arrow.triangle.branch",
                            tint: BeagleTheme.truthRemembered
                        )
                        PresencePill(
                            label: lane.habitatLabel,
                            systemImage: lane.project.workspacePod == nil ? "moon.zzz.fill" : "shippingbox.fill",
                            tint: lane.project.workspacePod == nil ? BeagleTheme.postureWarm : BeagleTheme.truthObserved
                        )
                        if let tmux = lane.project.tmuxSession, !tmux.isEmpty {
                            PresencePill(label: tmux, systemImage: "terminal", tint: BeagleTheme.textSecondary)
                        }
                        PresencePill(label: lane.countsLine, systemImage: "brain.head.profile", tint: BeagleTheme.truthObserved)
                    }

                    if let livingQuestion = lane.livingQuestion {
                        Text("Living question: \(livingQuestion)")
                            .font(BeagleFont.footnote.font)
                            .foregroundStyle(BeagleTheme.truthRemembered)
                            .lineLimit(3)
                    }

                    if let currentFocus = lane.currentFocus {
                        Text("Lead focus: \(currentFocus)")
                            .font(BeagleFont.caption.font)
                            .foregroundStyle(BeagleTheme.textSecondary)
                            .lineLimit(2)
                    }

                    if let jobLine = lane.jobLine {
                        Text("Work in motion: \(jobLine)")
                            .font(BeagleFont.caption.font)
                            .foregroundStyle(BeagleTheme.postureWarm)
                            .lineLimit(2)
                    }

                    if lane.laneResult != nil {
                        LaneResultCard(lane: lane)
                    } else if let resultSignal = lane.resultSignal {
                        Text("Result trail: \(resultSignal)")
                            .font(BeagleFont.caption.font)
                            .foregroundStyle(BeagleTheme.truthRemembered)
                            .lineLimit(2)
                    }

                    Text("Next move: \(lane.nextRecommendedMove)")
                        .font(BeagleFont.caption.font)
                        .foregroundStyle(BeagleTheme.textSecondary)
                        .lineLimit(2)

                    HStack(spacing: BeagleSpacing.sm) {
                        Button {
                            cognitive.activeProjectSlug = lane.project.projectSlug
                            selectedTab = 3
                        } label: {
                            Label("Open \(lane.displayName) Agents", systemImage: "apple.terminal")
                        }
                        .buttonStyle(PrimaryButton())

                        NavigationLink(value: lane.project) {
                            Label("Open Control Room", systemImage: "server.rack")
                        }
                        .buttonStyle(SecondaryButton(color: BeagleTheme.truthObserved))
                    }
                }
            }
        }
    }

    private func postureStat(count: Int, label: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("\(count)")
                .font(BeagleFont.title3.font)
                .fontWeight(.bold)
                .foregroundStyle(color)
            Text(label)
                .font(BeagleFont.caption2.font)
                .foregroundStyle(BeagleTheme.textTertiary)
        }
    }

    // MARK: - Projects

    private var projectsSection: some View {
        VStack(alignment: .leading, spacing: BeagleSpacing.sm) {
            sectionLabel("Projects")

            if catalog.projects.isEmpty {
                ForEach(fallbackProjects) { project in
                    projectRow(project)
                }
            } else {
                ForEach(catalog.alwaysOnProjects) { project in
                    NavigationLink(value: project) {
                        projectRow(project)
                    }
                    .buttonStyle(.plain)
                }

                ForEach(catalog.warmProjects) { project in
                    NavigationLink(value: project) {
                        projectRow(project)
                    }
                    .buttonStyle(.plain)
                }

                if !catalog.coldProjects.isEmpty {
                DisclosureGroup {
                    ForEach(catalog.coldProjects) { project in
                        NavigationLink(value: project) {
                            projectRow(project)
                        }
                        .buttonStyle(.plain)
                    }
                } label: {
                    Text("\(catalog.coldProjects.count) resting")
                        .font(BeagleFont.caption.font)
                        .foregroundStyle(BeagleTheme.textTertiary)
                }
                .tint(BeagleTheme.textTertiary)
                }
            }
        }
    }

    private func projectRow(_ project: Project) -> some View {
        let lane = laneState(for: project)
        return VStack(alignment: .leading, spacing: BeagleSpacing.sm) {
            HStack(spacing: BeagleSpacing.sm) {
                PostureIndicator(project.posture, size: 10, showLabel: false)

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: BeagleSpacing.xs) {
                        Text(displayName(for: project))
                            .font(BeagleFont.body.font)
                            .foregroundStyle(BeagleTheme.textPrimary)
                        if lane.isCurrent {
                            PresencePill(label: "current", systemImage: "scope", tint: BeagleTheme.truthObserved)
                        }
                    }

                    Text(project.projectSlug)
                        .font(BeagleFont.caption2.font)
                        .foregroundStyle(BeagleTheme.textTertiary)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(BeagleTheme.textTertiary)
            }

            HStack(spacing: BeagleSpacing.xs) {
                PresencePill(
                    label: lane.branchLabel,
                    systemImage: "arrow.triangle.branch",
                    tint: BeagleTheme.truthRemembered
                )
                PresencePill(
                    label: lane.habitatLabel,
                    systemImage: project.workspacePod == nil ? "moon.zzz.fill" : "shippingbox.fill",
                    tint: project.workspacePod == nil ? BeagleTheme.postureWarm : BeagleTheme.truthObserved
                )
            }

            Text(lane.livingQuestion.map { "Living question: \($0)" } ?? lane.nextRecommendedMove)
                .font(BeagleFont.footnote.font)
                .foregroundStyle(lane.livingQuestion == nil ? BeagleTheme.textSecondary : BeagleTheme.truthRemembered)
                .lineLimit(2)

            if lane.laneResult != nil {
                LaneResultCard(lane: lane, compact: true)
            }
        }
        .frame(minHeight: 44)
        .padding(.horizontal, BeagleSpacing.md)
        .padding(.vertical, BeagleSpacing.sm)
        .background(
            RoundedRectangle(cornerRadius: BeagleRadius.lg)
                .fill(BeagleTheme.surface1.opacity(0.4))
        )
    }

    // MARK: - HPC Dashboard Link

    private var hpcLink: some View {
        NavigationLink {
            HPCDashboardView()
        } label: {
            HStack(spacing: BeagleSpacing.sm) {
                Image(systemName: "cpu")
                    .font(.system(size: 14))
                    .foregroundStyle(BeagleTheme.postureWarm)
                Text("Cluster & HPC")
                    .font(BeagleFont.footnote.font)
                    .fontWeight(.medium)
                    .foregroundStyle(BeagleTheme.textPrimary)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(BeagleTheme.textTertiary)
            }
            .padding(BeagleSpacing.md)
            .background(
                RoundedRectangle(cornerRadius: BeagleRadius.lg)
                    .fill(BeagleTheme.surface1.opacity(0.4))
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Agent Activity

    private var agentActivitySection: some View {
        NavigationLink {
            AgentActivityView()
        } label: {
            HStack(spacing: BeagleSpacing.sm) {
                Image(systemName: "antenna.radiowaves.left.and.right")
                    .font(.system(size: 14))
                    .foregroundStyle(BeagleTheme.truthRemembered)
                Text("Agent Activity")
                    .font(BeagleFont.footnote.font)
                    .fontWeight(.medium)
                    .foregroundStyle(BeagleTheme.textPrimary)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(BeagleTheme.textTertiary)
            }
            .frame(minHeight: 44)
            .padding(.horizontal, BeagleSpacing.md)
            .padding(.vertical, BeagleSpacing.xs)
            .background(
                RoundedRectangle(cornerRadius: BeagleRadius.lg)
                    .fill(BeagleTheme.surface1.opacity(0.4))
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Jobs

    @ViewBuilder
    private var jobsSection: some View {
        let running = cognitive.activeJobs.filter(\.isRunning)
        if !running.isEmpty {
            VStack(alignment: .leading, spacing: BeagleSpacing.sm) {
                sectionLabel("Running Jobs")
                ForEach(running) { job in
                    HStack(spacing: BeagleSpacing.sm) {
                        Image(systemName: "circle.fill")
                            .font(.system(size: 6))
                            .foregroundStyle(BeagleTheme.postureWarm)
                            .symbolEffect(.pulse)
                        Text(job.kind ?? "unknown")
                            .font(BeagleFont.data.font)
                            .foregroundStyle(BeagleTheme.textPrimary)
                        Spacer()
                        Text(job.status ?? "running")
                            .font(BeagleFont.dataSmall.font)
                            .foregroundStyle(BeagleTheme.postureWarm)
                    }
                }
            }
        }
    }

    // MARK: - Helpers

    private func sectionLabel(_ text: String) -> some View {
        Text(text)
            .font(BeagleFont.caption.font)
            .fontWeight(.medium)
            .foregroundStyle(BeagleTheme.textTertiary)
            .textCase(.uppercase)
            .tracking(0.5)
    }

    private var commandPresenceLabel: String {
        if cognitive.runningJobCount > 0 {
            return "\(cognitive.runningJobCount) live jobs"
        }
        if (cognitive.state.value?.agentSessions?.contains { ($0.readyReplicas ?? 0) > 0 } ?? false) {
            return "agents awake"
        }
        return "quiet command"
    }

    private var commandPresenceTint: Color {
        if cognitive.runningJobCount > 0 {
            return BeagleTheme.truthObserved
        }
        if (cognitive.state.value?.agentSessions?.contains { ($0.readyReplicas ?? 0) > 0 } ?? false) {
            return BeagleTheme.truthRemembered
        }
        return BeagleTheme.truthDeclared
    }

    private var commandPresenceState: BeaglePresenceState {
        if cognitive.runningJobCount > 0 {
            return .active
        }
        if (cognitive.state.value?.agentSessions?.contains { ($0.readyReplicas ?? 0) > 0 } ?? false) {
            return .attentive
        }
        if catalog.executive.mode == .stale {
            return .strained
        }
        return .dormant
    }

    private var commandPresenceBody: String {
        if cognitive.runningJobCount > 0 {
            return "Live jobs are moving through the cluster right now. This room should feel operationally clear, but still carry the pulse of the larger mind."
        }
        if (cognitive.state.value?.agentSessions?.contains { ($0.readyReplicas ?? 0) > 0 } ?? false) {
            return "Agents are awake even if jobs are quiet. Command should feel like the lab listening, not a wall of metrics."
        }
        if catalog.executive.mode == .stale {
            return "Some cluster truth is stale. The shell should stay calm, but honest about where the signal has weakened."
        }
        return "When the lab is steady, Command should feel composed rather than empty. Quiet continuity is still part of the system’s presence."
    }

    private var commandPresenceDetail: String {
        let counts = catalog.postureCounts
        return "\(counts.alwaysOn) alive · \(counts.warm) warm · \(counts.cold) resting"
    }

    private var commandPresenceTruth: TruthMode {
        switch commandPresenceState {
        case .active:
            return .observed
        case .attentive:
            return .remembered
        case .dormant:
            return .declared
        case .strained:
            return .stale
        }
    }

    private var currentProject: Project? {
        if let slug = cognitive.activeProjectSlug,
           let matching = catalog.projects.first(where: { $0.projectSlug == slug }) {
            return matching
        }
        if let slug = cognitive.activeProjectSlug,
           let fallback = fallbackProjects.first(where: { $0.projectSlug == slug }) {
            return fallback
        }
        return catalog.primaryProject ?? fallbackProjects.first
    }

    private var currentLaneState: ProjectLaneState? {
        guard let project = currentProject else { return nil }
        return laneState(for: project)
    }

    private func displayName(for project: Project) -> String {
        project.projectSlug
            .split(separator: "-")
            .map { $0.capitalized }
            .joined(separator: " ")
    }

    private func laneTruth(for project: Project) -> TruthMode {
        if project.projectSlug == cognitive.activeProjectSlug {
            return .observed
        }
        if project.workspacePod != nil {
            return .remembered
        }
        return .declared
    }

    private func currentLaneNarrative(for project: Project) -> String {
        if cognitive.runningJobCount > 0 {
            return "Jobs are moving in the cluster now. This lane should be the fastest way to see what world you are operating in before you jump into control or agents."
        }
        if project.workspacePod != nil {
            return "The habitat for this lane already exists. Open the agents or the control room from here instead of hunting through the cluster."
        }
        return "This lane is known, but its habitat is parked. Wake an agent or open the control room to move it from theory into execution."
    }

    private func postureLabel(for project: Project) -> String {
        switch project.posture {
        case .alwaysOn:
            return "alive"
        case .warm:
            return "warm"
        case .cold:
            return "resting"
        case .unknown:
            return "unknown"
        }
    }

    private func postureIcon(for project: Project) -> String {
        switch project.posture {
        case .alwaysOn:
            return "waveform.path.ecg"
        case .warm:
            return "flame.fill"
        case .cold:
            return "moon.zzz.fill"
        case .unknown:
            return "questionmark.circle"
        }
    }

    private func postureTint(for project: Project) -> Color {
        switch project.posture {
        case .alwaysOn:
            return BeagleTheme.postureOn
        case .warm:
            return BeagleTheme.postureWarm
        case .cold:
            return BeagleTheme.postureCold
        case .unknown:
            return BeagleTheme.textTertiary
        }
    }

    private func projectRowNarrative(_ project: Project) -> String {
        if project.projectSlug == cognitive.activeProjectSlug {
            return "This is the lane you are currently carrying through the shell."
        }
        if project.workspacePod != nil {
            return "Its habitat already exists, so you can step into agents or control without waking anything first."
        }
        switch project.posture {
        case .alwaysOn:
            return "This lane is meant to stay alive, even if its current habitat is quiet."
        case .warm:
            return "This lane is nearby and recoverable without a full cold start."
        case .cold:
            return "This lane is resting until you intentionally pull it back into motion."
        case .unknown:
            return "This lane exists, but the platform truth around it is still thin."
        }
    }

    private var pinnedLaneQuestions: [String: String] {
        guard let data = pinnedLaneQuestionsJSON.data(using: .utf8),
              let decoded = try? JSONDecoder().decode([String: String].self, from: data) else {
            return [:]
        }
        return decoded
    }

    private func laneState(for project: Project) -> ProjectLaneState {
        let isCurrent = project.projectSlug == (cognitive.activeProjectSlug ?? catalog.primaryProject?.projectSlug)
        let sessions = isCurrent ? (cognitive.state.value?.agentSessions ?? []) : []
        let carriedObjective =
            sessions.first(where: \.isRunning)?.presentedActivityLine
            ?? sessions.first(where: { $0.phase == .paused })?.presentedActivityLine
            ?? sessions.first?.presentedActivityLine
        return ProjectLaneState(
            project: project,
            sessions: sessions,
            scienceJobs: isCurrent ? cognitive.activeJobs : [],
            laneResult: isCurrent ? (currentLaneOverview?.value?.laneResult ?? cachedLaneResult(for: project.projectSlug)) : cachedLaneResult(for: project.projectSlug),
            recentTrail: isCurrent ? CognitiveStore.recentTrailSnippets(from: cognitive.recentThoughts) : [],
            truth: laneTruth(for: project),
            isCurrent: isCurrent,
            livingQuestion: pinnedLaneQuestions[project.projectSlug],
            carriedObjective: isCurrent ? carriedObjective : nil
        )
    }

    private var currentLaneSlug: String? {
        cognitive.activeProjectSlug ?? catalog.primaryProject?.projectSlug ?? fallbackProjects.first?.projectSlug
    }

    private var fallbackProjects: [Project] {
        [
            Project(projectSlug: "sounio", preferredPrBase: "integration/sounio-dev-ready-base"),
            Project(projectSlug: "scratch"),
            Project(projectSlug: "hyperbolic-semantic-networks")
        ]
    }

    private func refreshCurrentLaneOverview() async {
        guard let currentLaneSlug else {
            currentLaneOverview = nil
            return
        }
        currentLaneOverview = await CockpitClient.shared.projectOverview(slug: currentLaneSlug)
        if let laneResult = currentLaneOverview?.value?.laneResult {
            persistLaneResults([laneResult])
        }
    }


    private var cachedLaneResults: [MobileLaneResultSummary] {
        guard let data = cachedLaneResultsJSON.data(using: .utf8),
              let decoded = try? JSONDecoder().decode([MobileLaneResultSummary].self, from: data) else {
            return []
        }
        return decoded
    }

    private func cachedLaneResult(for slug: String) -> MobileLaneResultSummary? {
        cachedLaneResults.first(where: { $0.projectSlug == slug })
    }

    private func persistLaneResults(_ incoming: [MobileLaneResultSummary]) {
        guard !incoming.isEmpty else { return }
        var merged = Dictionary(uniqueKeysWithValues: cachedLaneResults.map { ($0.projectSlug, $0) })
        for item in incoming {
            merged[item.projectSlug] = item
        }
        let ordered = merged.values.sorted { $0.projectSlug < $1.projectSlug }
        if let data = try? JSONEncoder().encode(ordered),
           let json = String(data: data, encoding: .utf8) {
            cachedLaneResultsJSON = json
        }
    }
}
