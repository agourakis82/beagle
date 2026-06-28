//
//  SpatialControlRoomView.swift
//  BeagleVisionOS
//
//  Native visionOS Control Room for Beagle Spatial Worlds.
//  Marble/World Labs generates the world; Beagle stores provenance and
//  visionOS renders the derived environment.
//

#if os(visionOS)
import SwiftUI
import RealityKit
import BeagleCore
import BeagleWorkbenchKit

struct SpatialControlRoomView: View {
    @Environment(\.openImmersiveSpace) private var openImmersiveSpace
    @State private var exocortex = ExocortexStore()
    @State private var projectSlug = "sounio"

    private var snapshot: ControlRoomSnapshot? {
        exocortex.spatialControlRoom?.value
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                header
                worldPanel
                lanesPanel
                topologyPanel
            }
            .padding(28)
        }
        .navigationTitle("Spatial Control Room")
        .background(.regularMaterial)
        .task { await refresh() }
        .refreshable { await refresh() }
        .ornament(attachmentAnchor: .scene(.bottom)) {
            HStack(spacing: 12) {
                Button {
                    Task { await refresh() }
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
                .buttonStyle(.bordered)

                Button {
                    Task { await openImmersiveSpace(id: "beagle-control-room") }
                } label: {
                    Label("Enter Room", systemImage: "visionpro")
                }
                .buttonStyle(.borderedProminent)
                .tint(BeagleTheme.truthObserved)
            }
            .padding(16)
            .glassBackgroundEffect()
        }
    }

    private var header: some View {
        GlassPanel(elevated: true, truth: exocortex.spatialControlRoom?.mode ?? .remembered) {
            HStack(alignment: .top, spacing: 18) {
                Image(systemName: "cube.transparent")
                    .font(.system(size: 34, weight: .semibold))
                    .foregroundStyle(BeagleTheme.truthObserved)
                VStack(alignment: .leading, spacing: 8) {
                    Text("Sounio Control Room")
                        .font(BeagleTheme.displayFont(size: 30, weight: .semibold))
                        .foregroundStyle(BeagleTheme.textPrimary)
                    Text(snapshot?.spatialWorld?.promptSummary ?? "Persistent spatial project world backed by Beagle and Marble.")
                        .font(BeagleTheme.uiFont(size: 15))
                        .foregroundStyle(BeagleTheme.textSecondary)
                        .lineLimit(3)
                    HStack(spacing: 10) {
                        TruthBadge(exocortex.spatialControlRoom?.mode ?? .remembered, compact: true)
                        statusChip(snapshot?.spatialWorld?.model ?? "marble pending")
                        statusChip(snapshot?.spatialWorld?.permission ?? "private")
                        statusChip(snapshot?.spatialWorld?.assets.coordinateTransform ?? "opencv->opengl")
                    }
                }
                Spacer()
            }
        }
    }

    private var worldPanel: some View {
        GlassPanel(elevated: true, truth: snapshot?.spatialWorld == nil ? .declared : .observed) {
            VStack(alignment: .leading, spacing: 12) {
                Text("MARBLE WORLD")
                    .font(BeagleTheme.uiFont(size: 11, weight: .semibold))
                    .tracking(1.1)
                    .foregroundStyle(BeagleTheme.textTertiary)

                if let world = snapshot?.spatialWorld {
                    LabeledContent("World", value: world.worldId)
                    LabeledContent("Status", value: world.status)
                    LabeledContent("SPZ", value: "\(world.assets.spzUrls.count) stream(s)")
                    if let pano = world.assets.panoUrl {
                        LabeledContent("Fallback pano", value: pano)
                    }
                    if let degraded = world.assets.degradedReason {
                        Text(degraded)
                            .font(BeagleTheme.uiFont(size: 13))
                            .foregroundStyle(BeagleTheme.truthDeclared)
                    }
                } else {
                    Text("No Marble world is registered yet. The immersive room will render Beagle-native topology primitives until world assets arrive.")
                        .font(BeagleTheme.uiFont(size: 14))
                        .foregroundStyle(BeagleTheme.textSecondary)
                }
            }
        }
    }

    private var lanesPanel: some View {
        let deck = SpatialAgentDeckSnapshot.fallback(
            projectSlug: projectSlug,
            laneTitles: snapshot?.agentLanes ?? defaultLanes
        )
        return GlassPanel(truth: .observed) {
            VStack(alignment: .leading, spacing: 12) {
                Text("SPATIAL AGENT DECK")
                    .font(BeagleTheme.uiFont(size: 11, weight: .semibold))
                    .tracking(1.1)
                    .foregroundStyle(BeagleTheme.textTertiary)
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: "slider.horizontal.3")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(BeagleTheme.truthObserved)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(deck.activeTask)
                            .font(BeagleTheme.uiFont(size: 15, weight: .semibold))
                            .foregroundStyle(BeagleTheme.textPrimary)
                        Text(deck.memoryLine)
                            .font(BeagleTheme.uiFont(size: 12))
                            .foregroundStyle(BeagleTheme.textSecondary)
                            .lineLimit(2)
                        Text(deck.proofLine)
                            .font(BeagleTheme.dataFont(size: 11))
                            .foregroundStyle(BeagleTheme.textTertiary)
                    }
                    Spacer()
                }
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 210))], spacing: 10) {
                    ForEach(deck.lanes) { lane in
                        HStack(spacing: 8) {
                            Image(systemName: lane.kind == "human" ? "terminal" : "rectangle.3.group")
                                .foregroundStyle(lane.readiness == "needs_setup" ? BeagleTheme.truthDeclared : BeagleTheme.truthObserved)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(lane.title)
                                    .font(BeagleTheme.uiFont(size: 13, weight: .semibold))
                                    .foregroundStyle(BeagleTheme.textPrimary)
                                    .lineLimit(1)
                                Text(lane.status)
                                    .font(BeagleTheme.dataFont(size: 11))
                                    .foregroundStyle(BeagleTheme.textTertiary)
                                    .lineLimit(1)
                            }
                            Spacer()
                        }
                        .padding(10)
                        .glassBackgroundEffect()
                    }
                }
            }
        }
    }

    private var topologyPanel: some View {
        GlassPanel(truth: .observed) {
            VStack(alignment: .leading, spacing: 12) {
                Text("ROOM TOPOLOGY")
                    .font(BeagleTheme.uiFont(size: 11, weight: .semibold))
                    .tracking(1.1)
                    .foregroundStyle(BeagleTheme.textTertiary)
                HStack(alignment: .top, spacing: 16) {
                    topologyColumn("Pods wall", snapshot?.podsWall ?? ["beagle-core", "mcp", "workspace"])
                    topologyColumn("Incident corridor", snapshot?.incidentCorridor ?? ["audit", "failed writes"])
                    topologyColumn("Compiler map", snapshot?.compilerMap ?? ["Sounio IR", "Claim<T>"])
                }
            }
        }
    }

    private func topologyColumn(_ title: String, _ values: [String]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(BeagleTheme.uiFont(size: 12, weight: .semibold))
                .foregroundStyle(BeagleTheme.textSecondary)
            ForEach(values.prefix(6), id: \.self) { value in
                Text(value)
                    .font(BeagleTheme.dataFont(size: 12))
                    .foregroundStyle(BeagleTheme.textData)
                    .lineLimit(2)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func statusChip(_ value: String) -> some View {
        Text(value)
            .font(BeagleTheme.dataFont(size: 11))
            .foregroundStyle(BeagleTheme.textData)
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .glassBackgroundEffect()
    }

    private var defaultLanes: [String] {
        ["Builder: Claude/Codex", "Code Worker: MiniMax/Qwen", "Long Thought: Kimi", "Platform: GLM", "Shell"]
    }

    private func refresh() async {
        await exocortex.refreshSpatialControlRoom(projectSlug: projectSlug)
    }
}

struct SpatialControlRoomImmersiveView: View {
    @State private var exocortex = ExocortexStore()

    var body: some View {
        RealityView { content in
            let root = MarbleSplatRenderer.makeScene(snapshot: exocortex.spatialControlRoom?.value)
            content.add(root)
        }
        .id(exocortex.spatialControlRoom?.value?.id ?? "beagle-control-room-pending")
        .task {
            await exocortex.refreshSpatialControlRoom(projectSlug: "sounio")
        }
        .ornament(attachmentAnchor: .scene(.bottom)) {
            VStack(spacing: 6) {
                Text("Beagle Spatial Control Room")
                    .font(BeagleTheme.uiFont(size: 15, weight: .semibold))
                Text(exocortex.spatialControlRoom?.value?.spatialWorld?.displayName ?? "Native Beagle topology fallback")
                    .font(BeagleTheme.dataFont(size: 12))
                    .foregroundStyle(BeagleTheme.textTertiary)
            }
            .padding(14)
            .glassBackgroundEffect()
        }
    }
}

enum MarbleSplatRenderer {
    static func makeScene(snapshot: ControlRoomSnapshot?) -> Entity {
        let root = Entity()
        root.name = "beagle-control-room-root"
        addFloor(to: root)
        addSounioTable(to: root)
        addPodsWall(to: root, labels: snapshot?.podsWall ?? ["beagle-core", "mcp", "workspace", "world-console"])
        addAgentLanes(to: root, lanes: snapshot?.agentLanes ?? ["Claude/Codex", "MiniMax/Qwen", "Kimi", "GLM", "Shell"])

        if let world = snapshot?.spatialWorld, !world.assets.spzUrls.isEmpty {
            addSplatProxy(to: root, world: world)
        } else {
            addFallbackPanoDome(to: root)
        }
        return root
    }

    private static func addFloor(to root: Entity) {
        let mesh = MeshResource.generatePlane(width: 4.0, depth: 3.0)
        var material = SimpleMaterial()
        material.color = .init(tint: UIColor(red: 0.05, green: 0.07, blue: 0.09, alpha: 0.55))
        let floor = ModelEntity(mesh: mesh, materials: [material])
        floor.position = SIMD3<Float>(0, -0.7, -1.2)
        floor.name = "control-room-floor"
        root.addChild(floor)
    }

    private static func addSounioTable(to root: Entity) {
        let table = ModelEntity(
            mesh: .generateBox(size: SIMD3<Float>(0.95, 0.05, 0.58)),
            materials: [glassMaterial(UIColor(red: 0.2, green: 0.8, blue: 0.95, alpha: 0.45))]
        )
        table.position = SIMD3<Float>(0, -0.42, -1.0)
        table.name = "sounio-table"
        root.addChild(table)
    }

    private static func addPodsWall(to root: Entity, labels: [String]) {
        for (index, _) in labels.prefix(6).enumerated() {
            let node = ModelEntity(
                mesh: .generateBox(size: SIMD3<Float>(0.18, 0.12, 0.025)),
                materials: [glassMaterial(UIColor(red: 0.35, green: 0.95, blue: 0.72, alpha: 0.55))]
            )
            node.position = SIMD3<Float>(-1.35 + Float(index % 3) * 0.28, 0.05 - Float(index / 3) * 0.18, -1.65)
            node.name = "pod-wall-\(index)"
            root.addChild(node)
        }
    }

    private static func addAgentLanes(to root: Entity, lanes: [String]) {
        let deck = lanes.isEmpty ? ["Claude-Codex", "MiniMax", "Kimi", "Qwen", "GLM", "Shell"] : lanes
        for (index, lane) in deck.prefix(6).enumerated() {
            let instrument = Entity()
            instrument.name = "spatial-agent-deck-\(safeEntityName(lane))"
            instrument.position = SIMD3<Float>(0.84, -0.23 + Float(index) * 0.13, -1.36)

            let body = ModelEntity(
                mesh: .generateBox(size: SIMD3<Float>(0.22, 0.052, 0.038)),
                materials: [glassMaterial(UIColor(red: 0.74, green: 0.74, blue: 1.0, alpha: 0.68))]
            )
            body.name = "\(instrument.name)-instrument"
            let status = ModelEntity(
                mesh: .generateSphere(radius: 0.018),
                materials: [glassMaterial(UIColor(red: 0.42, green: 0.96, blue: 0.74, alpha: 0.88))]
            )
            status.position = SIMD3<Float>(-0.09, 0.038, 0)
            status.name = "\(instrument.name)-status"

            instrument.addChild(body)
            instrument.addChild(status)
            root.addChild(instrument)
        }
    }

    private static func addSplatProxy(to root: Entity, world: SpatialWorld) {
        let count = world.assets.spzUrls["low_res"] == nil ? 48 : 96
        for index in 0..<count {
            let t = Float(index) / Float(max(count - 1, 1))
            let angle = t * Float.pi * 2.0 * 3.0
            let radius: Float = 0.45 + 0.18 * sin(t * Float.pi * 4)
            let point = ModelEntity(
                mesh: .generateSphere(radius: 0.008),
                materials: [glassMaterial(UIColor(red: 0.5, green: 0.85, blue: 1.0, alpha: 0.8))]
            )
            point.position = SIMD3<Float>(
                cos(angle) * radius,
                -0.12 + sin(t * Float.pi * 2) * 0.18,
                -1.1 + sin(angle) * radius
            )
            point.name = "marble-splat-proxy-\(index)"
            root.addChild(point)
        }
    }

    private static func addFallbackPanoDome(to root: Entity) {
        let dome = ModelEntity(
            mesh: .generateSphere(radius: 1.65),
            materials: [glassMaterial(UIColor(red: 0.08, green: 0.12, blue: 0.18, alpha: 0.22))]
        )
        dome.position = SIMD3<Float>(0, 0, -1.05)
        dome.name = "fallback-pano-dome"
        root.addChild(dome)
    }

    private static func glassMaterial(_ color: UIColor) -> SimpleMaterial {
        var material = SimpleMaterial()
        material.color = .init(tint: color)
        material.roughness = 0.25
        material.metallic = 0.1
        return material
    }

    private static func safeEntityName(_ value: String) -> String {
        value
            .lowercased()
            .map { character in
                character.isLetter || character.isNumber ? character : "-"
            }
            .reduce(into: "") { partial, character in
                partial.append(character)
            }
    }
}
#endif
