//
//  BeagleVisionOSApp.swift
//  BeagleVisionOS
//
//  Spatial control room for Apple Vision Pro / visionOS 26.
//
//  Three coexisting scenes:
//  - Window: 2D control panels (glass morphing in space)
//  - Volume: 3D cluster topology (nodes floating, particle streams)
//  - Immersive Space: fully immersive dataset viewer for OME-Zarr
//

import SwiftUI
import RealityKit
import BeagleCore

@main
struct BeagleVisionOSApp: App {
    @State private var catalog = CatalogStore()

    var body: some SwiftUI.Scene {
        WindowGroup("Cockpit", id: "cockpit") {
            SpatialCockpitView()
                .environment(catalog)
                .task { await catalog.refresh() }
                .preferredColorScheme(.dark)
                .tint(BeagleTheme.truthObserved)
        }
        .defaultSize(width: 900, height: 640)

        WindowGroup("Cluster Volume", id: "cluster-volume") {
            ClusterVolumeView()
                .environment(catalog)
        }
        .windowStyle(.volumetric)
        .defaultSize(width: 1.2, height: 0.8, depth: 1.2, in: .meters)

        ImmersiveSpace(id: "dataset-immersive") {
            ImmersiveDatasetView()
                .environment(catalog)
        }
        .immersionStyle(selection: .constant(.progressive), in: .mixed, .progressive, .full)
    }
}

// MARK: - SpatialCockpitView (Window)

struct SpatialCockpitView: View {
    @Environment(CatalogStore.self) private var catalog
    @Environment(\.openWindow) private var openWindow
    @Environment(\.openImmersiveSpace) private var openImmersiveSpace

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                Text("Sovereign Surfaces")
                    .font(BeagleTheme.displayFont(size: 36, weight: .semibold))
                    .foregroundStyle(BeagleTheme.textPrimary)

                // Posture summary
                let counts = catalog.postureCounts
                HStack(spacing: 20) {
                    postureCard(count: counts.alwaysOn, label: "always-on", color: BeagleTheme.postureOn)
                    postureCard(count: counts.warm, label: "warm", color: BeagleTheme.postureWarm)
                    postureCard(count: counts.cold, label: "cold", color: BeagleTheme.postureCold)
                }

                // Always-on projects
                ScrollView {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 280))], spacing: 16) {
                        ForEach(catalog.alwaysOnProjects) { project in
                            NavigationLink(value: project) {
                                projectCard(project)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding()
                }
                .navigationDestination(for: Project.self) { project in
                    SpatialProjectView(slug: project.projectSlug)
                }

                // Spatial controls
                HStack(spacing: 16) {
                    Button {
                        openWindow(id: "cluster-volume")
                    } label: {
                        Label("Open Cluster Volume", systemImage: "cube.fill")
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(BeagleTheme.truthObserved)

                    Button {
                        Task { await openImmersiveSpace(id: "dataset-immersive") }
                    } label: {
                        Label("Immersive Dataset", systemImage: "cube.transparent")
                    }
                    .buttonStyle(.bordered)
                }
                .padding(.bottom)
            }
            .padding()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(.regularMaterial)
        }
    }

    private func postureCard(count: Int, label: String, color: Color) -> some View {
        VStack(spacing: 6) {
            Text("\(count)")
                .font(BeagleTheme.displayFont(size: 32, weight: .bold))
                .foregroundStyle(color)
            Text(label.uppercased())
                .font(BeagleTheme.uiFont(size: 10, weight: .semibold))
                .tracking(1.2)
                .foregroundStyle(BeagleTheme.textTertiary)
        }
        .frame(width: 120, height: 100)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(.regularMaterial)
        )
        .hoverEffect()
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
                Text(project.namespace ?? "—")
                    .font(BeagleTheme.dataFont(size: 11))
                    .foregroundStyle(BeagleTheme.textTertiary)
            }
        }
        .hoverEffect()
    }
}

// MARK: - SpatialProjectView

struct SpatialProjectView: View {
    let slug: String
    @State private var store: ProjectStore

    init(slug: String) {
        self.slug = slug
        self._store = State(initialValue: ProjectStore(slug: slug))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text(slug.uppercased())
                    .font(BeagleTheme.displayFont(size: 32, weight: .semibold))
                PostureIndicator(store.posture)
                Spacer()
                TruthBadge(store.mission.mode)
            }

            // 5 lanes in spatial glass
            ScrollView {
                VStack(spacing: 10) {
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
                            Text("\(runtime.status ?? "—")")
                                .font(BeagleTheme.dataFont(size: 12))
                                .foregroundStyle(BeagleTheme.textData)
                        }
                    }
                }
            }
        }
        .padding(24)
        .task { await store.refresh() }
    }
}

// MARK: - ClusterVolumeView (3D volumetric)

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
            // Fetch cluster nodes for the first always-on project
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

        // Interactive for gaze/pinch
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
        // Align cylinder with edge direction
        let dir = simd_normalize(end - start)
        let up = SIMD3<Float>(0, 1, 0)
        let rotation = simd_quatf(from: up, to: dir)
        entity.orientation = rotation
        return entity
    }
}

// MARK: - ImmersiveDatasetView (full space)

struct ImmersiveDatasetView: View {
    var body: some View {
        RealityView { content in
            // Placeholder: floating volume for OME-Zarr dataset
            let mesh = MeshResource.generateBox(size: 0.5)
            var material = PhysicallyBasedMaterial()
            material.emissiveColor = .init(color: .init(resolvableColor: BeagleTheme.truthObserved))
            material.emissiveIntensity = 0.2
            material.baseColor = .init(tint: .init(white: 0.1, alpha: 1))
            material.roughness = 0.8
            material.metallic = 0.1

            let entity = ModelEntity(mesh: mesh, materials: [material])
            entity.position = SIMD3<Float>(0, 1.4, -1.5)
            entity.components.set(InputTargetComponent())
            entity.components.set(CollisionComponent(shapes: [.generateBox(size: SIMD3<Float>(0.5, 0.5, 0.5))]))
            entity.components.set(HoverEffectComponent())
            content.add(entity)
        }
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
                        // Handle node tap — could drill into node detail
                        print("[vision] tapped node: \(value.entity.name)")
                    }
            )
    }
}
