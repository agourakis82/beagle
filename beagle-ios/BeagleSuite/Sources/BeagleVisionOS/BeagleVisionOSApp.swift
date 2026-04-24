//
//  BeagleVisionOSApp.swift
//  BeagleVisionOS
//
//  Spatial exocortex for Apple Vision Pro / visionOS 26.
//
//  Three coexisting scenes:
//  - WindowGroup "cockpit": 2D Mind view with NavigationSplitView
//  - WindowGroup "cognitive-gauge": volumetric cognitive readiness gauge
//  - ImmersiveSpace "go-deep": mixed-immersion GoDeep spatial exploration
//
//  The cluster topology volume is retained as a secondary spatial window.
//

import SwiftUI
import RealityKit
import BeagleCore

@main
struct BeagleVisionOSApp: App {
    @State private var catalog = CatalogStore()
    @State private var cognitive = CognitiveStore()
    @State private var physio = PhysioStore()
    @State private var hpc = HPCStore()

    var body: some SwiftUI.Scene {

        // MARK: - Main Window — Spatial Mind

        WindowGroup("Cockpit", id: "cockpit") {
            SpatialMindView()
                .environment(catalog)
                .environment(cognitive)
                .environment(physio)
                .environment(hpc)
                .task { await catalog.refresh() }
                .task { await physio.refresh(requestAuthorization: true) }
                .preferredColorScheme(.dark)
                .tint(BeagleTheme.truthObserved)
        }
        .defaultSize(width: 1000, height: 700)

        // MARK: - Cognitive Gauge Volume — floating readiness indicator

        WindowGroup("Cognitive Gauge", id: "cognitive-gauge") {
            CognitiveGaugeVolume()
                .environment(physio)
        }
        .windowStyle(.volumetric)
        .defaultSize(width: 0.3, height: 0.3, depth: 0.3, in: .meters)

        // MARK: - GoDeep Immersive Space

        ImmersiveSpace(id: "go-deep") {
            GoDeepSpatialView()
                .environment(cognitive)
        }
        .immersionStyle(selection: .constant(.mixed), in: .mixed)

        // MARK: - Cluster Volume (retained from v1)

        WindowGroup("Cluster Volume", id: "cluster-volume") {
            ClusterVolumeView()
                .environment(catalog)
        }
        .windowStyle(.volumetric)
        .defaultSize(width: 1.2, height: 0.8, depth: 1.2, in: .meters)
    }
}

// MARK: - SpatialMindView (Main Window)

/// NavigationSplitView with sidebar tabs matching the iOS 4-tab structure:
/// Mind, Capture, Deep, Work. Adapted for spatial glass panels.
struct SpatialMindView: View {
    @Environment(CatalogStore.self) private var catalog
    @Environment(CognitiveStore.self) private var cognitive
    @Environment(PhysioStore.self) private var physio
    @Environment(\.openWindow) private var openWindow
    @Environment(\.openImmersiveSpace) private var openImmersiveSpace
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
            List(SpatialSection.allCases, selection: $selectedSection) { section in
                Label(section.rawValue, systemImage: section.icon)
                    .font(BeagleTheme.uiFont(size: 15, weight: .medium))
                    .foregroundStyle(BeagleTheme.textPrimary)
            }
            .navigationTitle("Beagle")
            .listStyle(.sidebar)

            // Spatial controls at bottom of sidebar
            VStack(spacing: 12) {
                Divider()

                Button {
                    openWindow(id: "cognitive-gauge")
                } label: {
                    Label("Readiness Gauge", systemImage: "heart.circle.fill")
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.bordered)

                Button {
                    openWindow(id: "cluster-volume")
                } label: {
                    Label("Cluster Volume", systemImage: "cube.fill")
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.bordered)

                Button {
                    Task { await openImmersiveSpace(id: "go-deep") }
                } label: {
                    Label("Immersive Deep", systemImage: "cube.transparent")
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.bordered)
            }
            .padding(.horizontal)
            .padding(.bottom)
        } detail: {
            detailView
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

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {

                // Cognitive posture header
                cognitiveHeader
                    .padding(.top)

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

                // Recent thoughts
                if !cognitive.recentThoughts.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("RECENT THOUGHTS")
                            .font(BeagleTheme.uiFont(size: 11, weight: .semibold))
                            .tracking(1.2)
                            .foregroundStyle(BeagleTheme.textTertiary)

                        ForEach(cognitive.recentThoughts.prefix(5)) { thought in
                            GlassPanel(truth: .observed) {
                                VStack(alignment: .leading, spacing: 6) {
                                    Text(thought.refinedText ?? thought.rawText ?? "")
                                        .font(BeagleTheme.uiFont(size: 14))
                                        .foregroundStyle(BeagleTheme.textPrimary)
                                        .lineLimit(3)
                                    if let ts = thought.createdAt {
                                        Text(ts)
                                            .font(BeagleTheme.dataFont(size: 11))
                                            .foregroundStyle(BeagleTheme.textTertiary)
                                    }
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

// MARK: - Spatial Capture View

struct SpatialCaptureView: View {
    @Environment(CognitiveStore.self) private var cognitive
    @State private var inputText = ""

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "mic.fill")
                .font(.system(size: 48))
                .foregroundStyle(BeagleTheme.truthObserved)
                .symbolEffect(.pulse, isActive: cognitive.isCapturing)

            Text("Capture a Thought")
                .font(BeagleTheme.displayFont(size: 28, weight: .semibold))
                .foregroundStyle(BeagleTheme.textPrimary)

            Text("Raw insight before it evaporates")
                .font(BeagleTheme.uiFont(size: 15))
                .foregroundStyle(BeagleTheme.textSecondary)

            TextField("What are you thinking?", text: $inputText, axis: .vertical)
                .textFieldStyle(.roundedBorder)
                .lineLimit(3...8)
                .frame(maxWidth: 600)

            Button {
                guard !inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
                Task {
                    _ = await cognitive.captureThought(text: inputText)
                    inputText = ""
                }
            } label: {
                Label("Capture", systemImage: "arrow.up.circle.fill")
                    .font(BeagleTheme.uiFont(size: 16, weight: .semibold))
            }
            .buttonStyle(.borderedProminent)
            .tint(BeagleTheme.truthObserved)
            .disabled(inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

            Spacer()

            // Recent captures
            if !cognitive.recentThoughts.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("RECENT")
                        .font(BeagleTheme.uiFont(size: 11, weight: .semibold))
                        .tracking(1.2)
                        .foregroundStyle(BeagleTheme.textTertiary)

                    ForEach(cognitive.recentThoughts.prefix(3)) { thought in
                        HStack {
                            Text(thought.refinedText ?? thought.rawText ?? "")
                                .font(BeagleTheme.uiFont(size: 13))
                                .foregroundStyle(BeagleTheme.textSecondary)
                                .lineLimit(1)
                            Spacer()
                            if let ts = thought.createdAt {
                                Text(ts)
                                    .font(BeagleTheme.dataFont(size: 11))
                                    .foregroundStyle(BeagleTheme.textTertiary)
                            }
                        }
                    }
                }
                .padding(.horizontal, 40)
                .frame(maxWidth: 600)
            }

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.regularMaterial)
        .navigationTitle("Capture")
    }
}

// MARK: - Spatial Deep Exploration

struct SpatialDeepExploration: View {
    @Environment(CognitiveStore.self) private var cognitive
    @Environment(\.openImmersiveSpace) private var openImmersiveSpace
    @State private var goDeepStore = GoDeepStore()
    @State private var prompt = ""

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "sparkles")
                .font(.system(size: 48))
                .foregroundStyle(BeagleTheme.truthObserved)

            Text("Go Deep")
                .font(BeagleTheme.displayFont(size: 32, weight: .semibold))
                .foregroundStyle(BeagleTheme.textPrimary)

            Text("Multi-modal reasoning across research, logic, and intuition")
                .font(BeagleTheme.uiFont(size: 15))
                .foregroundStyle(BeagleTheme.textSecondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 500)

            TextField("What should we explore?", text: $prompt, axis: .vertical)
                .textFieldStyle(.roundedBorder)
                .lineLimit(2...6)
                .frame(maxWidth: 600)

            HStack(spacing: 16) {
                Button {
                    guard !prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
                    Task {
                        goDeepStore.goDeeper(prompt: prompt)
                    }
                } label: {
                    Label("Go Deep", systemImage: "sparkles")
                        .font(BeagleTheme.uiFont(size: 16, weight: .semibold))
                }
                .buttonStyle(.borderedProminent)
                .tint(BeagleTheme.truthObserved)
                .disabled(prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                Button {
                    Task { await openImmersiveSpace(id: "go-deep") }
                } label: {
                    Label("Spatial Mode", systemImage: "cube.transparent")
                }
                .buttonStyle(.bordered)
            }

            // Active session results
            if let synthesis = goDeepStore.synthesis {
                GlassPanel(elevated: true, truth: .observed) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Synthesis")
                            .font(BeagleTheme.uiFont(size: 15, weight: .semibold))
                            .foregroundStyle(BeagleTheme.textPrimary)
                        Text(synthesis)
                            .font(BeagleTheme.uiFont(size: 14))
                            .foregroundStyle(BeagleTheme.textSecondary)
                    }
                }
                .padding(.horizontal, 40)
            }

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.regularMaterial)
        .navigationTitle("Go Deep")
    }
}

// MARK: - Spatial Work View

struct SpatialWorkView: View {
    @Environment(CatalogStore.self) private var catalog
    @Environment(CognitiveStore.self) private var cognitive

    var body: some View {
        VStack(spacing: 24) {
            if catalog.alwaysOnProjects.isEmpty {
                ContentUnavailableView(
                    "No Active Projects",
                    systemImage: "apple.terminal",
                    description: Text("Projects will appear once the cockpit server is reachable.")
                )
            } else {
                ScrollView {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 300))], spacing: 16) {
                        ForEach(catalog.alwaysOnProjects) { project in
                            NavigationLink(value: project) {
                                GlassPanel(elevated: true, truth: .observed) {
                                    VStack(alignment: .leading, spacing: 10) {
                                        HStack {
                                            Text(project.projectSlug.uppercased())
                                                .font(BeagleTheme.displayFont(size: 20, weight: .semibold))
                                                .foregroundStyle(BeagleTheme.textPrimary)
                                            Spacer()
                                            PostureIndicator(project.posture)
                                        }
                                        if let pod = project.workspacePod {
                                            HStack(spacing: 4) {
                                                Circle()
                                                    .fill(BeagleTheme.truthObserved)
                                                    .frame(width: 6, height: 6)
                                                Text(pod)
                                                    .font(BeagleTheme.dataFont(size: 12))
                                                    .foregroundStyle(BeagleTheme.textData)
                                            }
                                        }
                                        Text(project.namespace ?? "---")
                                            .font(BeagleTheme.dataFont(size: 11))
                                            .foregroundStyle(BeagleTheme.textTertiary)
                                    }
                                }
                                .hoverEffect()
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding()
                }
            }
        }
        .navigationTitle("Work")
        .navigationDestination(for: Project.self) { project in
            SpatialProjectView(slug: project.projectSlug)
        }
        .background(.regularMaterial)
    }
}

// MARK: - SpatialProjectView (5-lane detail)

struct SpatialProjectView: View {
    let slug: String
    @State private var store: ProjectStore

    init(slug: String) {
        self.slug = slug
        self._store = State(initialValue: ProjectStore(slug: slug))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Text(slug.uppercased())
                        .font(BeagleTheme.displayFont(size: 32, weight: .semibold))
                        .foregroundStyle(BeagleTheme.textPrimary)
                    PostureIndicator(store.posture)
                    Spacer()
                    TruthBadge(store.mission.mode)
                }

                // 5 lanes in spatial glass
                Lane(title: "Mission", truth: store.mission.mode) {
                    if let p = store.project {
                        Text("habitat: \(p.workspacePod ?? "standby")")
                            .font(BeagleTheme.dataFont(size: 12))
                            .foregroundStyle(BeagleTheme.textData)
                    }
                }
                Lane(title: "Cluster", truth: store.clusterTruth.mode) {
                    let nodes = store.clusterNodes
                    if nodes.isEmpty {
                        Text("loading nodes...")
                            .font(BeagleTheme.dataFont(size: 12))
                            .foregroundStyle(BeagleTheme.textTertiary)
                    } else {
                        HStack(spacing: 10) {
                            ForEach(nodes) { node in
                                HStack(spacing: 3) {
                                    Circle()
                                        .fill(node.healthy == true ? BeagleTheme.truthObserved : BeagleTheme.truthStale)
                                        .frame(width: 5, height: 5)
                                    Text(node.hostname ?? node.name ?? "?")
                                        .font(BeagleTheme.dataFont(size: 12))
                                        .foregroundStyle(BeagleTheme.textData)
                                }
                            }
                        }
                    }
                }
                Lane(title: "Research", truth: store.research.mode) {
                    Text("ABIDE campaigns")
                        .font(BeagleTheme.dataFont(size: 12))
                        .foregroundStyle(BeagleTheme.textData)
                }
                Lane(title: "Inference", truth: store.inference.mode) {
                    if let runtime = store.inference.value {
                        Text("\(runtime.status ?? "---")")
                            .font(BeagleTheme.dataFont(size: 12))
                            .foregroundStyle(BeagleTheme.textData)
                    }
                }
            }
            .padding(24)
        }
        .background(.regularMaterial)
        .navigationTitle(slug)
        .task { await store.refresh() }
    }
}

// MARK: - CognitiveGaugeVolume (3D floating readiness)

/// A volumetric window showing a glowing readiness orb.
/// The orb color shifts green/yellow/orange based on cognitive posture.
struct CognitiveGaugeVolume: View {
    @Environment(PhysioStore.self) private var physio

    var body: some View {
        RealityView { content in
            // Glowing readiness sphere
            let mesh = MeshResource.generateSphere(radius: 0.08)
            var material = PhysicallyBasedMaterial()
            let tint = UIColor(resolvableColor: gaugeColor)
            material.emissiveColor = .init(color: tint)
            material.emissiveIntensity = 0.6
            material.baseColor = .init(tint: tint)
            material.metallic = 0.3
            material.roughness = 0.5

            let sphere = ModelEntity(mesh: mesh, materials: [material])
            sphere.position = SIMD3<Float>(0, 0, 0)
            sphere.name = "readiness-orb"

            // Interactive
            sphere.components.set(InputTargetComponent())
            sphere.components.set(CollisionComponent(shapes: [.generateSphere(radius: 0.1)]))
            sphere.components.set(HoverEffectComponent())

            content.add(sphere)

            // Outer ring (subtle)
            let ring = MeshResource.generateCylinder(height: 0.003, radius: 0.12)
            var ringMat = UnlitMaterial()
            ringMat.color = .init(tint: .init(white: 1, alpha: 0.15))
            let ringEntity = ModelEntity(mesh: ring, materials: [ringMat])
            ringEntity.position = SIMD3<Float>(0, 0, 0)
            content.add(ringEntity)

        } update: { content in
            // Update orb color on readiness changes
            if let orb = content.entities.first(where: { $0.name == "readiness-orb" }),
               let model = orb as? ModelEntity {
                var material = PhysicallyBasedMaterial()
                let tint = UIColor(resolvableColor: gaugeColor)
                material.emissiveColor = .init(color: tint)
                material.emissiveIntensity = 0.6
                material.baseColor = .init(tint: tint)
                material.metallic = 0.3
                material.roughness = 0.5
                model.model?.materials = [material]
            }
        }
        .overlay(alignment: .bottom) {
            VStack(spacing: 4) {
                Text("\(Int((physio.cognitivePosture.readiness ?? 0) * 100))%")
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                    .foregroundStyle(gaugeColor)
                Text(physio.cognitivePosture.suggestedIntensity.rawValue.capitalized)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            .padding(.bottom, 8)
        }
    }

    private var gaugeColor: Color {
        guard let r = physio.cognitivePosture.readiness else { return .gray }
        if r >= 0.7 { return .green }
        if r >= 0.4 { return .yellow }
        return .orange
    }
}

// MARK: - GoDeepSpatialView (Immersive Space)

/// Mixed-immersion ornament view for spatial deep exploration.
/// Floating glass panels around the user showing modality results.
struct GoDeepSpatialView: View {
    @Environment(CognitiveStore.self) private var cognitive
    @State private var goDeepStore = GoDeepStore()
    @State private var prompt = ""

    var body: some View {
        // Central glass panel floating in mixed reality
        VStack(spacing: 20) {
            Text("Deep Exploration")
                .font(BeagleTheme.displayFont(size: 28, weight: .semibold))
                .foregroundStyle(BeagleTheme.textPrimary)

            Text("Multi-modal reasoning in spatial context")
                .font(BeagleTheme.uiFont(size: 15))
                .foregroundStyle(BeagleTheme.textSecondary)

            Divider()

            // Modality status indicators
            HStack(spacing: 24) {
                ForEach(goDeepStore.modalityStates) { state in
                    modalityOrb(
                        name: state.modality.rawValue.localizedCapitalized,
                        icon: state.modality.icon,
                        active: state.isActive,
                        resolved: state.isResolved
                    )
                }
            }

            if let synthesis = goDeepStore.synthesis {
                VStack(alignment: .leading, spacing: 8) {
                    Text("SYNTHESIS")
                        .font(BeagleTheme.uiFont(size: 11, weight: .semibold))
                        .tracking(1.2)
                        .foregroundStyle(BeagleTheme.textTertiary)
                    Text(synthesis)
                        .font(BeagleTheme.uiFont(size: 14))
                        .foregroundStyle(BeagleTheme.textPrimary)
                        .frame(maxWidth: 500)
                }
                .padding()
            }

            // Prompt input for spatial exploration
            TextField("Explore...", text: $prompt, axis: .vertical)
                .textFieldStyle(.roundedBorder)
                .lineLimit(2...4)
                .frame(maxWidth: 400)

            Button {
                guard !prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
                Task { goDeepStore.goDeeper(prompt: prompt) }
            } label: {
                Label("Go Deep", systemImage: "sparkles")
            }
            .buttonStyle(.borderedProminent)
            .tint(BeagleTheme.truthObserved)
            .disabled(prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .padding(40)
        .glassBackgroundEffect()
    }

    private func modalityOrb(name: String, icon: String, active: Bool, resolved: Bool = false) -> some View {
        VStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 24))
                .foregroundStyle(resolved ? .green : (active ? BeagleTheme.truthObserved : BeagleTheme.textTertiary))
                .symbolEffect(.pulse, isActive: active)
            Text(name)
                .font(BeagleTheme.uiFont(size: 11, weight: .medium))
                .foregroundStyle(active || resolved ? BeagleTheme.textPrimary : BeagleTheme.textTertiary)
        }
        .frame(width: 80)
    }
}

// MARK: - ClusterVolumeView (3D volumetric — retained)

struct ClusterVolumeView: View {
    @Environment(CatalogStore.self) private var catalog
    @State private var nodes: [ClusterNode] = []

    var body: some View {
        RealityView { content in
            let positions = layoutPositions(count: max(nodes.count, 3))
            let renderNodes = nodes.isEmpty
                ? defaultNodes
                : nodes

            for (i, node) in renderNodes.prefix(positions.count).enumerated() {
                let color = node.healthy == true ? BeagleTheme.truthObserved : BeagleTheme.truthDeclared
                let entity = makeNode(name: node.hostname ?? node.name ?? "node-\(i)", color: color, position: positions[i])
                content.add(entity)
            }

            // Edges: connect all pairs
            for i in 0..<min(renderNodes.count, positions.count) {
                for j in (i + 1)..<min(renderNodes.count, positions.count) {
                    content.add(makeEdge(from: positions[i], to: positions[j]))
                }
            }
        }
        .installGestures()
        .task {
            if let slug = catalog.alwaysOnProjects.first?.projectSlug {
                let result = await CockpitClient.shared.clusterSummary(slug: slug)
                if let fetched = result.value?.nodes, !fetched.isEmpty {
                    nodes = fetched
                }
            }
        }
    }

    private var defaultNodes: [ClusterNode] {
        [
            ClusterNode(name: "r770", hostname: "r770", role: nil, healthy: true),
            ClusterNode(name: "r740", hostname: "r740", role: nil, healthy: true),
            ClusterNode(name: "t560", hostname: "t560", role: "ctrl", healthy: true)
        ]
    }

    private func layoutPositions(count: Int) -> [SIMD3<Float>] {
        guard count > 0 else { return [] }
        let radius: Float = 0.4
        return (0..<count).map { i in
            let angle = Float(i) * (2 * .pi / Float(count)) - .pi / 2
            return SIMD3<Float>(cos(angle) * radius, sin(angle) * radius, 0)
        }
    }

    private func makeNode(name: String, color: Color, position: SIMD3<Float>) -> Entity {
        let mesh = MeshResource.generateSphere(radius: 0.06)
        var material = PhysicallyBasedMaterial()
        material.emissiveColor = .init(color: .init(resolvableColor: color))
        material.emissiveIntensity = 0.4
        material.baseColor = .init(tint: .init(resolvableColor: color))
        material.metallic = 0.6
        material.roughness = 0.4

        let entity = ModelEntity(mesh: mesh, materials: [material])
        entity.position = position
        entity.name = name

        entity.components.set(InputTargetComponent())
        entity.components.set(CollisionComponent(shapes: [.generateSphere(radius: 0.08)]))
        entity.components.set(HoverEffectComponent())

        return entity
    }

    private func makeEdge(from start: SIMD3<Float>, to end: SIMD3<Float>) -> Entity {
        let midpoint = (start + end) / 2
        let length = simd_distance(start, end)
        let mesh = MeshResource.generateCylinder(height: length, radius: 0.002)
        var material = UnlitMaterial()
        material.color = .init(tint: .init(white: 1, alpha: 0.15))
        let entity = ModelEntity(mesh: mesh, materials: [material])
        entity.position = midpoint
        let dir = simd_normalize(end - start)
        let up = SIMD3<Float>(0, 1, 0)
        let rotation = simd_quatf(from: up, to: dir)
        entity.orientation = rotation
        return entity
    }
}

// MARK: - Helpers

extension UIColor {
    convenience init(resolvableColor: Color) {
        #if canImport(UIKit)
        self.init(resolvableColor)
        #else
        self.init(red: 0.32, green: 0.84, blue: 0.74, alpha: 1)
        #endif
    }
}

extension RealityView {
    fileprivate func installGestures() -> some View {
        self
            .gesture(
                SpatialTapGesture()
                    .targetedToAnyEntity()
                    .onEnded { value in
                        print("[vision] tapped entity: \(value.entity.name)")
                    }
            )
    }
}
