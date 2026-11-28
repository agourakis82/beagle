//
//  SpatialWorkspaceTabs.swift
//  BeagleVisionOS
//
//  Capture, Go Deep, Work, and 5-lane Project detail views for the main visionOS window.
//

import SwiftUI
import BeagleCore

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
    @Environment(SpatialSpaceCoordinator.self) private var spaceCoordinator
    @Environment(\.openImmersiveSpace) private var openImmersiveSpace
    @Environment(\.dismissImmersiveSpace) private var dismissImmersiveSpace
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
                    Task {
                        await spaceCoordinator.toggle(
                            id: "go-deep",
                            open: openImmersiveSpace,
                            dismiss: dismissImmersiveSpace
                        )
                    }
                } label: {
                    Label(
                        spaceCoordinator.isOpen("go-deep") ? "Exit Spatial Mode" : "Spatial Mode",
                        systemImage: "cube.transparent"
                    )
                }
                .buttonStyle(.bordered)
                .disabled(spaceCoordinator.isTransitioning)

                Button {
                    Task {
                        await spaceCoordinator.toggle(
                            id: "triad-debate",
                            open: openImmersiveSpace,
                            dismiss: dismissImmersiveSpace
                        )
                    }
                } label: {
                    Label(
                        spaceCoordinator.isOpen("triad-debate") ? "Exit Triad Debate" : "Triad Debate",
                        systemImage: "scalemass"
                    )
                }
                .buttonStyle(.bordered)
                .disabled(spaceCoordinator.isTransitioning)
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
