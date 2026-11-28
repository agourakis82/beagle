//
//  SpatialMindView.swift
//  BeagleVisionOS
//
//  Main cockpit NavigationSplitView window and central Mind dashboard.
//

import SwiftUI
import BeagleCore

// MARK: - SpatialMindView (Main Window)

/// NavigationSplitView with sidebar tabs matching the iOS 4-tab structure:
/// Mind, Capture, Deep, Work, plus structured spatial volume/workspace launchers
/// and a bottom ornament bar for exclusive ImmersiveSpace transitions.
struct SpatialMindView: View {
    @Environment(CatalogStore.self) private var catalog
    @Environment(CognitiveStore.self) private var cognitive
    @Environment(PhysioStore.self) private var physio
    @Environment(SpatialSpaceCoordinator.self) private var spaceCoordinator
    @Environment(\.openWindow) private var openWindow
    @Environment(\.openImmersiveSpace) private var openImmersiveSpace
    @Environment(\.dismissImmersiveSpace) private var dismissImmersiveSpace
    @State private var selectedSection: SpatialSection = .mind

    enum SpatialSection: String, CaseIterable, Identifiable {
        case mind     = "Mind"
        case capture  = "Capture"
        case deep     = "Go Deep"
        case work     = "Work"

        var id: String { rawValue }

        var icon: String {
            switch self {
            case .mind:    return "brain.head.profile"
            case .capture: return "mic.fill"
            case .deep:    return "sparkles"
            case .work:    return "apple.terminal"
            }
        }
    }

    var body: some View {
        NavigationSplitView {
            List {
                Section("Exocortex") {
                    ForEach(SpatialSection.allCases) { section in
                        Button {
                            selectedSection = section
                        } label: {
                            HStack {
                                Label(section.rawValue, systemImage: section.icon)
                                    .font(BeagleTheme.uiFont(size: 15, weight: selectedSection == section ? .semibold : .medium))
                                    .foregroundStyle(
                                        selectedSection == section
                                        ? BeagleTheme.truthObserved
                                        : BeagleTheme.textPrimary
                                    )
                                Spacer()
                                if selectedSection == section {
                                    Circle()
                                        .fill(BeagleTheme.truthObserved)
                                        .frame(width: 6, height: 6)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }

                Section("Spatial Volumes") {
                    sidebarWindowButton("Readiness Gauge", icon: "heart.circle.fill", windowID: "cognitive-gauge")
                    sidebarWindowButton("Cluster Volume", icon: "cube.fill", windowID: "cluster-volume")
                    sidebarWindowButton("Knowledge Graph", icon: "point.3.connected.trianglepath.dotted", windowID: "knowledge-graph")
                    sidebarWindowButton("Thought Stream", icon: "note.text", windowID: "thought-stream")
                }

                Section("Workspaces") {
                    sidebarWindowButton("Spatial Control Room", icon: "visionpro", windowID: "spatial-control-room")
                    sidebarWindowButton("Mind Palace", icon: "rectangle.3.group.bubble.left", windowID: "mind-palace")
                }
            }
            .navigationTitle("Beagle")
            .listStyle(.sidebar)
        } detail: {
            detailView
        }
        .ornament(attachmentAnchor: .scene(.bottom)) {
            HStack(spacing: 12) {
                immersiveToggleButton(
                    id: "go-deep",
                    title: "Immersive Deep",
                    icon: "cube.transparent"
                )
                immersiveToggleButton(
                    id: "triad-debate",
                    title: "Triad Debate",
                    icon: "scalemass"
                )
                immersiveToggleButton(
                    id: "beagle-control-room",
                    title: "Control Room",
                    icon: "visionpro"
                )
                immersiveToggleButton(
                    id: "beagle-mind-palace",
                    title: "Mind Palace",
                    icon: "rectangle.3.group.bubble.left"
                )
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 12)
            .glassBackgroundEffect()
        }
    }

    private func sidebarWindowButton(_ title: String, icon: String, windowID: String) -> some View {
        Button {
            openWindow(id: windowID)
        } label: {
            Label(title, systemImage: icon)
                .font(BeagleTheme.uiFont(size: 14, weight: .medium))
                .foregroundStyle(BeagleTheme.textSecondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func immersiveToggleButton(id: String, title: String, icon: String) -> some View {
        let active = spaceCoordinator.isOpen(id)
        if active {
            Button {
                Task {
                    await spaceCoordinator.toggle(
                        id: id,
                        open: openImmersiveSpace,
                        dismiss: dismissImmersiveSpace
                    )
                }
            } label: {
                Label("Exit \(title)", systemImage: "xmark.circle.fill")
            }
            .buttonStyle(.borderedProminent)
            .tint(BeagleTheme.truthObserved)
            .disabled(spaceCoordinator.isTransitioning)
        } else {
            Button {
                Task {
                    await spaceCoordinator.toggle(
                        id: id,
                        open: openImmersiveSpace,
                        dismiss: dismissImmersiveSpace
                    )
                }
            } label: {
                Label(title, systemImage: icon)
            }
            .buttonStyle(.bordered)
            .disabled(spaceCoordinator.isTransitioning)
        }
    }

    @ViewBuilder
    private var detailView: some View {
        switch selectedSection {
        case .mind:
            SpatialMindDashboard()
        case .capture:
            SpatialCaptureView()
        case .deep:
            SpatialDeepExploration()
        case .work:
            SpatialWorkView()
        }
    }
}

// MARK: - Mind Dashboard (detail)

/// The central mind view: cognitive posture, recent thoughts, active projects.
struct SpatialMindDashboard: View {
    @Environment(CatalogStore.self) private var catalog
    @Environment(CognitiveStore.self) private var cognitive
    @Environment(PhysioStore.self) private var physio
    @State private var exocortex = ExocortexStore()

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {

                // Cognitive posture header
                cognitiveHeader
                    .padding(.top)

                exocortexSpatialCard
                    .padding(.horizontal)

                // Always-on projects grid
                if !catalog.alwaysOnProjects.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("ALWAYS-ON SURFACES")
                            .font(BeagleTheme.uiFont(size: 11, weight: .semibold))
                            .tracking(1.2)
                            .foregroundStyle(BeagleTheme.textTertiary)

                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 280))], spacing: 16) {
                            ForEach(catalog.alwaysOnProjects) { project in
                                NavigationLink(value: project) {
                                    projectCard(project)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    .padding(.horizontal)
                }

                // Projected GraphRAG++ memory from the cluster canonical store
                if let atoms = exocortex.recentGraph?.value?.atoms, !atoms.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("PROJECTED MEMORY")
                            .font(BeagleTheme.uiFont(size: 11, weight: .semibold))
                            .tracking(1.2)
                            .foregroundStyle(BeagleTheme.textTertiary)

                        ForEach(atoms.prefix(5)) { atom in
                            GlassPanel(truth: .observed) {
                                VStack(alignment: .leading, spacing: 6) {
                                    Text(atom.text)
                                        .font(BeagleTheme.uiFont(size: 14))
                                        .foregroundStyle(BeagleTheme.textPrimary)
                                        .lineLimit(3)
                                    Text("\(atom.atomType) · \(atom.privacyClass)")
                                        .font(BeagleTheme.dataFont(size: 11))
                                        .foregroundStyle(BeagleTheme.textTertiary)
                                }
                            }
                        }
                    }
                    .padding(.horizontal)
                }

                // Active science jobs
                if !cognitive.activeJobs.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("ACTIVE JOBS")
                            .font(BeagleTheme.uiFont(size: 11, weight: .semibold))
                            .tracking(1.2)
                            .foregroundStyle(BeagleTheme.textTertiary)

                        ForEach(cognitive.activeJobs) { job in
                            GlassPanel(truth: .observed) {
                                HStack {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(job.kind ?? "job")
                                            .font(BeagleTheme.uiFont(size: 14, weight: .medium))
                                            .foregroundStyle(BeagleTheme.textPrimary)
                                        Text(job.status ?? "---")
                                            .font(BeagleTheme.dataFont(size: 12))
                                            .foregroundStyle(BeagleTheme.textData)
                                    }
                                    Spacer()
                                }
                            }
                        }
                    }
                    .padding(.horizontal)
                }
            }
            .padding(.bottom, 40)
        }
        .navigationTitle("Mind")
        .navigationDestination(for: Project.self) { project in
            SpatialProjectView(slug: project.projectSlug)
        }
        .background(.regularMaterial)
        .task {
            let activeSlug = catalog.primaryProject?.projectSlug ?? cognitive.activeProjectSlug
            async let homeRefresh: Void = exocortex.refresh(
                activeProjectSlug: activeSlug,
                platform: "visionOS"
            )
            async let graphRefresh: Void = exocortex.refreshRecentGraph(limit: 18)
            _ = await (homeRefresh, graphRefresh)
        }
    }

    private var exocortexSpatialCard: some View {
        let snapshot = exocortex.home.value ?? .bootstrap
        return GlassPanel(elevated: true, truth: exocortex.home.mode) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 10) {
                    Image(systemName: "brain.head.profile")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(BeagleTheme.color(for: exocortex.home.mode))
                    VStack(alignment: .leading, spacing: 2) {
                        Text("CHRONOSELF")
                            .font(BeagleTheme.uiFont(size: 11, weight: .semibold))
                            .foregroundStyle(BeagleTheme.textTertiary)
                        Text(snapshot.currentSelf.label)
                            .font(BeagleTheme.uiFont(size: 17, weight: .semibold))
                            .foregroundStyle(BeagleTheme.textPrimary)
                    }
                    Spacer()
                    TruthBadge(exocortex.home.mode, compact: true)
                }

                Text(snapshot.todayBrief)
                    .font(BeagleTheme.uiFont(size: 14))
                    .foregroundStyle(BeagleTheme.textSecondary)
                    .lineLimit(3)

                HStack(alignment: .top, spacing: 18) {
                    spatialHomeSignal("phase", snapshot.temporalPhase ?? snapshot.omnimemoryStatus)
                    spatialHomeSignal("trust", snapshot.trustContext?.mcpStatus ?? snapshot.clusterTruth)
                    spatialHomeSignal("next", snapshot.recommendedNextAction)
                }

                if let agent = snapshot.agentContext,
                   let last = agent.lastAgentWrite {
                    spatialHomeSignal("agent write", "\(agent.mcpStatus) · \(last)")
                }
            }
        }
    }

    private func spatialHomeSignal(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label.uppercased())
                .font(BeagleTheme.uiFont(size: 10, weight: .semibold))
                .foregroundStyle(BeagleTheme.textTertiary)
            Text(value)
                .font(BeagleTheme.uiFont(size: 13))
                .foregroundStyle(BeagleTheme.textSecondary)
                .lineLimit(2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var cognitiveHeader: some View {
        GlassPanel(elevated: true, truth: .observed) {
            HStack(spacing: 24) {
                // Readiness ring
                ZStack {
                    Circle()
                        .stroke(BeagleTheme.truthStale.opacity(0.3), lineWidth: 6)
                        .frame(width: 80, height: 80)

                    Circle()
                        .trim(from: 0, to: physio.cognitivePosture.readiness ?? 0)
                        .stroke(readinessColor, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                        .frame(width: 80, height: 80)

                    VStack(spacing: 2) {
                        Text("\(Int((physio.cognitivePosture.readiness ?? 0) * 100))")
                            .font(BeagleTheme.displayFont(size: 28, weight: .bold))
                            .foregroundStyle(readinessColor)
                        Text("%")
                            .font(BeagleTheme.dataFont(size: 12))
                            .foregroundStyle(BeagleTheme.textTertiary)
                    }
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("Cognitive Readiness")
                        .font(BeagleTheme.uiFont(size: 17, weight: .semibold))
                        .foregroundStyle(BeagleTheme.textPrimary)

                    Text("Intensity: \(physio.cognitivePosture.suggestedIntensity.rawValue.capitalized)")
                        .font(BeagleTheme.uiFont(size: 14))
                        .foregroundStyle(BeagleTheme.textSecondary)

                    if let hrv = physio.cognitivePosture.hrv {
                        Text("HRV: \(Int(hrv)) ms")
                            .font(BeagleTheme.dataFont(size: 12))
                            .foregroundStyle(BeagleTheme.textData)
                    }
                }

                Spacer()

                // Posture counts
                let counts = catalog.postureCounts
                HStack(spacing: 16) {
                    postureChip(count: counts.alwaysOn, label: "ON", color: BeagleTheme.postureOn)
                    postureChip(count: counts.warm, label: "WARM", color: BeagleTheme.postureWarm)
                    postureChip(count: counts.cold, label: "COLD", color: BeagleTheme.postureCold)
                }
            }
        }
        .padding(.horizontal)
    }

    private var readinessColor: Color {
        guard let r = physio.cognitivePosture.readiness else { return .gray }
        if r >= 0.7 { return .green }
        if r >= 0.4 { return .yellow }
        return .orange
    }

    private func postureChip(count: Int, label: String, color: Color) -> some View {
        VStack(spacing: 4) {
            Text("\(count)")
                .font(BeagleTheme.displayFont(size: 22, weight: .bold))
                .foregroundStyle(color)
            Text(label)
                .font(BeagleTheme.uiFont(size: 9, weight: .semibold))
                .tracking(0.8)
                .foregroundStyle(BeagleTheme.textTertiary)
        }
    }

    private func projectCard(_ project: Project) -> some View {
        GlassPanel(elevated: true, truth: .observed) {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text(project.projectSlug.uppercased())
                        .font(BeagleTheme.displayFont(size: 20, weight: .semibold))
                        .foregroundStyle(BeagleTheme.textPrimary)
                    Spacer()
                    PostureIndicator(project.posture)
                }
                Text(project.namespace ?? "---")
                    .font(BeagleTheme.dataFont(size: 11))
                    .foregroundStyle(BeagleTheme.textTertiary)
            }
        }
        .hoverEffect()
    }
}
