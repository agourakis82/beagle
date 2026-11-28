//
//  SpatialVolumesAndSpaces.swift
//  BeagleVisionOS
//
//  Volumetric RealityKit scenes (CognitiveGaugeVolume, ClusterVolumeView),
//  mixed-immersion GoDeepSpatialView, and shared RealityKit helpers.
//

import SwiftUI
import RealityKit
import BeagleCore

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
    @Environment(SpatialSpaceCoordinator.self) private var spaceCoordinator
    @Environment(\.dismissImmersiveSpace) private var dismissImmersiveSpace
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

            HStack(spacing: 12) {
                Button {
                    guard !prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
                    Task { goDeepStore.goDeeper(prompt: prompt) }
                } label: {
                    Label("Go Deep", systemImage: "sparkles")
                }
                .buttonStyle(.borderedProminent)
                .tint(BeagleTheme.truthObserved)
                .disabled(prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                Button {
                    Task { await spaceCoordinator.dismissActive(using: dismissImmersiveSpace) }
                } label: {
                    Label("Exit Space", systemImage: "xmark.circle")
                }
                .buttonStyle(.bordered)
            }
        }
        .padding(40)
        .glassBackgroundEffect()
        .onDisappear {
            spaceCoordinator.noteDismissed(id: "go-deep")
        }
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
            populateCluster(content: content)
        } update: { content in
            content.entities.removeAll()
            populateCluster(content: content)
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

    private func populateCluster(content: RealityViewContent) {
        let renderNodes = nodes.isEmpty ? defaultNodes : nodes
        let positions = layoutPositions(count: max(renderNodes.count, 3))

        for (i, node) in renderNodes.prefix(positions.count).enumerated() {
            let color = node.healthy == true ? BeagleTheme.truthObserved : BeagleTheme.truthDeclared
            let entity = makeNode(name: node.hostname ?? node.name ?? "node-\(i)", color: color, position: positions[i])
            content.add(entity)
        }

        for i in 0..<min(renderNodes.count, positions.count) {
            for j in (i + 1)..<min(renderNodes.count, positions.count) {
                content.add(makeEdge(from: positions[i], to: positions[j]))
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
