//
//  ControlRoomView.swift
//  BeagleCockpit
//
//  Mission control — per-project control room with 5 operational lanes.
//  Data visualization via Swift Charts, animated node indicators, AI triage.
//

import SwiftUI
import BeagleCore
import Charts

struct ControlRoomView: View {
    let slug: String
    @State private var store: ProjectStore
    @State private var aiTriage: String?
    @State private var isTriaging = false
    @State private var gitStatus: GitStatusDetail?
    @State private var liveSessions: [AgentSession] = []
    @State private var goWorkActions: [GoWorkNowAction] = []
    @State private var showScienceJobs = false

    init(slug: String) {
        self.slug = slug
        self._store = State(initialValue: ProjectStore(slug: slug))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: BeagleSpacing.lg) {
                header
                missionLane
                clusterLane
                researchLane
                inferenceLane
                agentLane
                goWorkLane
                Spacer(minLength: BeagleSpacing.jumbo)
            }
            .padding(.horizontal, BeagleSpacing.lg)
            .padding(.top, BeagleSpacing.md)
        }
        .background { HealthPulseGradient(truth: store.mission.mode) }
        .navigationTitle(slug)
        .sensoryFeedback(.success, trigger: store.mission.mode == .observed)
        .task {
            await store.refresh()
            await refreshSideData()
        }
        .refreshable {
            await store.refresh()
            await refreshSideData()
        }
        .userActivity("dev.sounio.cockpit.viewProject") { activity in
            activity.title = "Viewing \(slug)"
            activity.userInfo = ["slug": slug]
            activity.isEligibleForHandoff = true
        }
        .sheet(isPresented: $showScienceJobs) {
            ScienceJobsView()
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: BeagleSpacing.sm) {
            HStack(alignment: .firstTextBaseline) {
                HStack(spacing: BeagleSpacing.sm) {
                    Text(slug)
                        .font(BeagleFont.title1.font)
                        .tracking(-0.3)
                        .foregroundStyle(BeagleTheme.textPrimary)
                    PostureIndicator(store.posture)
                }
                Spacer()
                HStack(spacing: BeagleSpacing.xs) {
                    if FoundationModelsAgent.shared.isAvailable {
                        Button {
                            Task { await runAITriage() }
                        } label: {
                            Image(systemName: "sparkles")
                                .font(.system(size: 16))
                                .foregroundStyle(BeagleTheme.truthObserved)
                                .symbolEffect(.variableColor.iterative, isActive: isTriaging)
                        }
                        .buttonStyle(.plain)
                        .disabled(isTriaging)
                    }
                    TruthBadge(store.mission.mode)
                    if store.mission.observedAt != nil {
                        Text(store.mission.ageLabel)
                            .font(BeagleFont.caption.font)
                            .foregroundStyle(BeagleTheme.textTertiary)
                    }
                }
            }

            // AI triage result
            if let triage = aiTriage {
                GlassPanel(elevation: .raised, truth: .observed) {
                    HStack(spacing: BeagleSpacing.xs) {
                        Image(systemName: "sparkles")
                            .font(.system(size: 12))
                            .foregroundStyle(BeagleTheme.truthObserved)
                        Text(triage)
                            .font(BeagleFont.footnote.font)
                            .foregroundStyle(BeagleTheme.textSecondary)
                        Spacer()
                        Button {
                            withAnimation(BeagleMotion.normal) { aiTriage = nil }
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(BeagleTheme.textTertiary)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .transition(.asymmetric(insertion: .push(from: .top), removal: .opacity))
            }
        }
    }

    private func runAITriage() async {
        isTriaging = true
        let nodes = store.clusterNodes
        let result = await FoundationModelsAgent.shared.triageLaneStatus(
            slug: slug,
            posture: store.posture.displayLabel,
            habitat: store.project?.workspacePod != nil ? "live" : "standby",
            clusterNodes: nodes.count,
            healthyNodes: nodes.filter { $0.healthy == true }.count,
            inferenceStatus: store.inference.value?.status,
            modelCount: store.inference.value?.models?.count ?? 0
        )
        withAnimation(BeagleMotion.slow) {
            aiTriage = result ?? "Foundation Models unavailable"
        }
        isTriaging = false
    }

    private func refreshSideData() async {
        async let gs = CockpitClient.shared.gitStatus(slug: slug)
        async let ss = CockpitClient.shared.agentSessions(slug: slug)
        async let gw = CockpitClient.shared.goWorkNow(slug: slug)
        let (gitResult, sessionsResult, gwResult) = await (gs, ss, gw)
        withAnimation(BeagleMotion.normal) {
            gitStatus = gitResult.value?.git
            liveSessions = sessionsResult.value?.sessions ?? []
            goWorkActions = (gwResult.value?.actions ?? []).filter { $0.ready == true }
        }
    }

    // MARK: - Lane 1: Mission Control

    private var missionLane: some View {
        Lane(title: "Mission Control", truth: store.mission.mode) {
            if let project = store.project {
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: BeagleSpacing.sm) {
                    StatItem(label: "habitat",
                             value: project.workspacePod != nil ? "live" : "standby",
                             color: store.posture == .alwaysOn ? BeagleTheme.truthObserved : BeagleTheme.postureWarm)
                    StatItem(label: "branch", value: project.preferredPrBase ?? project.branch ?? "—")
                    StatItem(label: "namespace", value: project.namespace ?? "—")
                    if let tmux = project.tmuxSession {
                        StatItem(label: "tmux", value: tmux)
                    }
                    if let pg = project.playgroundClass {
                        StatItem(label: "playground", value: pg)
                    }
                }
                if let count = store.mission.value?.packetCount {
                    HStack(spacing: BeagleSpacing.xxs) {
                        Text("execution packets")
                            .font(BeagleFont.caption.font)
                            .foregroundStyle(BeagleTheme.textTertiary)
                        Text("\(count)")
                            .font(BeagleFont.dataProminent.font)
                            .foregroundStyle(BeagleTheme.truthObserved)
                    }
                    .padding(.top, BeagleSpacing.xxs)
                }
                if let git = gitStatus {
                    HStack(spacing: BeagleSpacing.sm) {
                        Image(systemName: "arrow.triangle.branch")
                            .font(.system(size: 10))
                            .foregroundStyle(BeagleTheme.textTertiary)
                        Text(git.branch ?? "—")
                            .font(BeagleFont.data.font)
                            .foregroundStyle(BeagleTheme.textSecondary)
                        if let dirty = git.dirty, dirty, let count = git.dirtyCount, count > 0 {
                            Text("·")
                                .foregroundStyle(BeagleTheme.textTertiary)
                            HStack(spacing: BeagleSpacing.xxs) {
                                Image(systemName: "pencil.circle.fill")
                                    .font(.system(size: 9))
                                Text("\(count) changed")
                                    .font(BeagleFont.dataSmall.font)
                            }
                            .foregroundStyle(BeagleTheme.postureWarm)
                        }
                        if let ab = git.aheadBehind, !ab.isEmpty, ab != "0 0" {
                            Text("·")
                                .foregroundStyle(BeagleTheme.textTertiary)
                            Text(ab)
                                .font(BeagleFont.dataSmall.font)
                                .foregroundStyle(BeagleTheme.truthRemembered)
                        }
                    }
                    .padding(.top, BeagleSpacing.xxs)
                }
            } else if store.mission.mode == .stale {
                LaneErrorState(error: store.mission.error) {
                    Task { await store.refresh() }
                }
            } else {
                LaneSkeleton()
            }
        }
        .dataFlash(truth: store.mission.mode)
        .scrollTransition(.animated(BeagleMotion.normal)) { content, phase in
            content.opacity(phase.isIdentity ? 1 : 0.6).scaleEffect(phase.isIdentity ? 1 : 0.97)
        }
    }

    // MARK: - Lane 2: Cluster Truth

    private var clusterLane: some View {
        Lane(title: "Cluster Truth", truth: store.clusterTruth.mode) {
            if store.clusterTruth.value != nil {
                let nodes = store.clusterNodes
                if nodes.isEmpty {
                    Text("no nodes reported")
                        .font(BeagleFont.footnote.font)
                        .foregroundStyle(BeagleTheme.textTertiary)
                } else {
                    MetalClusterView(nodes: nodes)
                        .clipShape(RoundedRectangle(cornerRadius: BeagleRadius.lg))
                }
            } else if store.clusterTruth.mode == .stale {
                LaneErrorState(error: store.clusterTruth.error) {
                    Task { await store.refresh() }
                }
            } else {
                LaneSkeleton()
            }
        }
        .dataFlash(truth: store.clusterTruth.mode)
        .scrollTransition(.animated(BeagleMotion.normal)) { content, phase in
            content.opacity(phase.isIdentity ? 1 : 0.6).scaleEffect(phase.isIdentity ? 1 : 0.97)
        }
    }

    // MARK: - Lane 3: Research Operations

    private var researchLane: some View {
        Lane(title: "Research Operations", truth: store.research.mode) {
            if store.research.value != nil {
                VStack(alignment: .leading, spacing: BeagleSpacing.sm) {
                    HStack(spacing: BeagleSpacing.xs) {
                        Image(systemName: "flask.fill")
                            .foregroundStyle(BeagleTheme.truthObserved)
                        Text("Scientific Pipelines")
                            .font(BeagleFont.footnote.font)
                            .fontWeight(.medium)
                            .foregroundStyle(BeagleTheme.textPrimary)
                    }

                    // Pipeline launch shortcuts
                    HStack(spacing: BeagleSpacing.xs) {
                        Button { showScienceJobs = true } label: {
                            researchChip("PBPK", icon: "cross.vial.fill", color: BeagleTheme.stateError)
                        }
                        .buttonStyle(.plain)
                        Button { showScienceJobs = true } label: {
                            researchChip("Helio", icon: "sun.max.fill", color: BeagleTheme.postureWarm)
                        }
                        .buttonStyle(.plain)
                        Button { showScienceJobs = true } label: {
                            researchChip("KEC", icon: "brain.head.profile", color: BeagleTheme.truthRemembered)
                        }
                        .buttonStyle(.plain)
                    }

                    // Go Deeper on research topic
                    GoDeepButton(prompt: "What are the latest findings across my PBPK, heliobiology, and brain morphometry research?")
                }
            } else if store.research.mode == .stale {
                LaneErrorState(error: store.research.error) {
                    Task { await store.refresh() }
                }
            } else {
                LaneSkeleton()
            }
        }
        .scrollTransition(.animated(BeagleMotion.normal)) { content, phase in
            content.opacity(phase.isIdentity ? 1 : 0.6).scaleEffect(phase.isIdentity ? 1 : 0.97)
        }
    }

    // MARK: - Lane 4: Inference Fabric

    private var inferenceLane: some View {
        Lane(title: "Inference Fabric", truth: store.inference.mode) {
            if let runtime = store.inference.value {
                VStack(alignment: .leading, spacing: BeagleSpacing.sm) {
                    HStack(spacing: BeagleSpacing.lg) {
                        InferenceStatusRow(
                            name: "Dynamo",
                            status: runtime.controlPlane?.status ?? "—",
                            healthy: runtime.controlPlane?.status == "ready"
                        )
                        InferenceStatusRow(
                            name: "SGLang",
                            status: runtime.engine?.status ?? "—",
                            healthy: runtime.engine?.status?.contains("published") ?? false
                        )
                    }

                    // Swift Charts: model serving bar
                    if let models = runtime.models, !models.isEmpty {
                        Chart {
                            ForEach(models) { model in
                                BarMark(
                                    x: .value("Model", model.idField ?? "unknown"),
                                    y: .value("Active", 1)
                                )
                                .foregroundStyle(BeagleTheme.truthObserved.gradient)
                                .cornerRadius(BeagleRadius.sm)
                            }
                        }
                        .chartXAxis(.hidden)
                        .chartYAxis(.hidden)
                        .frame(height: 32)

                        Text("\(models.count) model\(models.count > 1 ? "s" : "") serving")
                            .font(BeagleFont.caption.font)
                            .foregroundStyle(BeagleTheme.textSecondary)
                    }
                }
            } else if store.inference.mode == .stale {
                LaneErrorState(error: store.inference.error) {
                    Task { await store.refresh() }
                }
            } else {
                LaneSkeleton()
            }
        }
        .dataFlash(truth: store.inference.mode)
        .scrollTransition(.animated(BeagleMotion.normal)) { content, phase in
            content.opacity(phase.isIdentity ? 1 : 0.6).scaleEffect(phase.isIdentity ? 1 : 0.97)
        }
    }

    // MARK: - Lane 5: Agent Session

    private var agentLane: some View {
        let runningSession = liveSessions.first(where: { ($0.readyReplicas ?? 0) > 0 })
        let lanetruth: TruthMode = runningSession != nil ? .observed : .declared
        return Lane(title: "Agent Session", truth: lanetruth, defaultExpanded: runningSession != nil) {
            VStack(alignment: .leading, spacing: BeagleSpacing.sm) {
                // Live session status rows
                if !liveSessions.isEmpty {
                    ForEach(liveSessions, id: \.kind) { session in
                        let isRunning = (session.readyReplicas ?? 0) > 0
                        HStack(spacing: BeagleSpacing.sm) {
                            Circle()
                                .fill(isRunning ? BeagleTheme.truthObserved : BeagleTheme.textTertiary)
                                .frame(width: 7, height: 7)
                                .shadow(color: isRunning ? BeagleTheme.truthObserved.opacity(0.4) : .clear, radius: 4)
                                .symbolEffect(.pulse, isActive: isRunning)
                            Text(session.kind?.replacingOccurrences(of: "-", with: " ").capitalized ?? "agent")
                                .font(BeagleFont.footnote.font)
                                .foregroundStyle(BeagleTheme.textPrimary)
                            Spacer()
                            Text(isRunning ? "live" : "stopped")
                                .font(BeagleFont.dataSmall.font)
                                .foregroundStyle(isRunning ? BeagleTheme.truthObserved : BeagleTheme.textTertiary)
                            if let pod = session.podName {
                                Text(pod)
                                    .font(BeagleFont.dataSmall.font)
                                    .foregroundStyle(BeagleTheme.textTertiary)
                                    .lineLimit(1)
                                    .frame(maxWidth: 120, alignment: .trailing)
                            }
                        }
                    }
                    Divider().opacity(0.2)
                } else {
                    Text("No sessions deployed yet.")
                        .font(BeagleFont.footnote.font)
                        .foregroundStyle(BeagleTheme.textTertiary)
                }

                NavigationLink(value: AgentSessionDestination(slug: slug)) {
                    HStack(spacing: BeagleSpacing.xs) {
                        Image(systemName: runningSession != nil ? "terminal.fill" : "sparkles")
                        Text(runningSession != nil ? "Join Running Session" : "Start Agent Session")
                            .font(BeagleFont.footnote.font)
                            .fontWeight(.medium)
                        Spacer()
                        Image(systemName: "arrow.right")
                            .font(.system(size: 12, weight: .medium))
                    }
                    .foregroundStyle(BeagleTheme.truthObserved)
                    .padding(.horizontal, BeagleSpacing.md)
                    .padding(.vertical, BeagleSpacing.sm)
                    .background(
                        RoundedRectangle(cornerRadius: BeagleRadius.md)
                            .fill(BeagleTheme.truthObserved.opacity(0.08))
                            .overlay(
                                RoundedRectangle(cornerRadius: BeagleRadius.md)
                                    .strokeBorder(BeagleTheme.truthObserved.opacity(0.15), lineWidth: 1)
                            )
                    )
                }
                .buttonStyle(.plain)
            }
        }
        .navigationDestination(for: AgentSessionDestination.self) { dest in
            AgentSessionView(slug: dest.slug)
        }
    }

    // MARK: - Lane 6: Go Work Now

    @ViewBuilder
    private var goWorkLane: some View {
        if !goWorkActions.isEmpty {
            Lane(title: "Go Work Now", truth: .observed) {
                VStack(alignment: .leading, spacing: BeagleSpacing.xs) {
                    ForEach(goWorkActions.prefix(4), id: \.id) { action in
                        Button {
                            Task { await CockpitClient.shared.executeAction(slug: slug, actionId: action.id ?? "") }
                        } label: {
                            HStack(spacing: BeagleSpacing.sm) {
                                Image(systemName: "bolt.fill")
                                    .font(.system(size: 11))
                                    .foregroundStyle(BeagleTheme.postureWarm)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(action.label ?? action.id ?? "action")
                                        .font(BeagleFont.footnote.font)
                                        .fontWeight(.medium)
                                        .foregroundStyle(BeagleTheme.textPrimary)
                                    if let desc = action.description, !desc.isEmpty {
                                        Text(desc)
                                            .font(BeagleFont.caption.font)
                                            .foregroundStyle(BeagleTheme.textSecondary)
                                            .lineLimit(1)
                                    }
                                }
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 10, weight: .medium))
                                    .foregroundStyle(BeagleTheme.textTertiary)
                            }
                            .padding(.horizontal, BeagleSpacing.sm)
                            .padding(.vertical, BeagleSpacing.xs)
                            .background(
                                RoundedRectangle(cornerRadius: BeagleRadius.sm)
                                    .fill(BeagleTheme.postureWarm.opacity(0.05))
                            )
                        }
                        .buttonStyle(ScalePress())
                    }
                }
            }
            .scrollTransition(.animated(BeagleMotion.normal)) { content, phase in
                content.opacity(phase.isIdentity ? 1 : 0.6).scaleEffect(phase.isIdentity ? 1 : 0.97)
            }
        }
    }
}

// MARK: - Node Card (cluster visualization)

struct NodeCard: View {
    let node: ClusterNode

    private var isHealthy: Bool { node.healthy ?? false }

    var body: some View {
        VStack(spacing: BeagleSpacing.xxs) {
            Circle()
                .fill(isHealthy ? BeagleTheme.truthObserved : BeagleTheme.stateError)
                .frame(width: 12, height: 12)
                .shadow(
                    color: (isHealthy ? BeagleTheme.truthObserved : BeagleTheme.stateError).opacity(0.4),
                    radius: 6
                )
                .symbolEffect(.pulse, isActive: isHealthy)

            Text(node.hostname ?? node.name ?? "?")
                .font(BeagleFont.dataSmall.font)
                .foregroundStyle(BeagleTheme.textData)

            if let role = node.role {
                Text(role)
                    .font(BeagleFont.dataSmall.font)
                    .foregroundStyle(BeagleTheme.textTertiary)
            }
        }
        .frame(minWidth: 56)
    }
}

// MARK: - Inference Status Row

struct InferenceStatusRow: View {
    let name: String
    let status: String
    let healthy: Bool

    var body: some View {
        HStack(spacing: BeagleSpacing.xs) {
            Circle()
                .fill(healthy ? BeagleTheme.truthObserved : BeagleTheme.truthStale)
                .frame(width: 8, height: 8)
                .shadow(color: healthy ? BeagleTheme.truthObserved.opacity(0.3) : .clear, radius: 4)
            Text(name)
                .font(BeagleFont.caption.font)
                .foregroundStyle(BeagleTheme.textSecondary)
            Text(status)
                .font(BeagleFont.data.font)
                .foregroundStyle(healthy ? BeagleTheme.truthObserved : BeagleTheme.textTertiary)
        }
    }
}

struct AgentSessionDestination: Hashable {
    let slug: String
}

// MARK: - Research Chip

extension ControlRoomView {
    func researchChip(_ label: String, icon: String, color: Color) -> some View {
        HStack(spacing: BeagleSpacing.xxs) {
            Image(systemName: icon)
                .font(.system(size: 10))
            Text(label)
                .font(BeagleFont.caption.font)
                .fontWeight(.medium)
        }
        .foregroundStyle(color)
        .padding(.horizontal, BeagleSpacing.sm)
        .padding(.vertical, BeagleSpacing.xs)
        .frame(minHeight: 36)
        .background(
            Capsule().fill(color.opacity(0.08))
                .overlay(Capsule().strokeBorder(color.opacity(0.12), lineWidth: 1))
        )
    }
}

// MARK: - StatItem (inline stat display)

private struct StatItem: View {
    let label: String
    let value: String
    let color: Color

    init(label: String, value: String, color: Color = BeagleTheme.textData) {
        self.label = label
        self.value = value
        self.color = color
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(BeagleFont.caption.font)
                .foregroundStyle(BeagleTheme.textTertiary)
            Text(value)
                .font(BeagleFont.data.font)
                .foregroundStyle(color)
        }
    }
}
