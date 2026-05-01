//
//  MindPalaceSpatialDeskView.swift
//  BeagleVisionOS
//
//  visionOS shell for the v3.7 Spatial Desk Mind Palace.
//

#if os(visionOS)
import SwiftUI
import RealityKit
import BeagleCore

struct MindPalaceSpatialDeskView: View {
    @Environment(\.openImmersiveSpace) private var openImmersiveSpace
    @State private var exocortex = ExocortexStore()

    private var snapshot: MindPalaceSnapshot? { exocortex.mindPalace?.value }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header
                if let snapshot {
                    rooms(snapshot.rooms)
                    actionMenu(snapshot.actionMenu)
                    portals(snapshot.desk.portals)
                } else {
                    GlassPanel(truth: .declared) {
                        HStack(spacing: 12) {
                            ProgressView()
                            Text("Loading Mind Palace from cluster...")
                                .foregroundStyle(BeagleTheme.textSecondary)
                        }
                    }
                }
            }
            .padding(28)
        }
        .navigationTitle("Mind Palace")
        .background(.regularMaterial)
        .task { await exocortex.refreshMindPalace() }
        .refreshable { await exocortex.refreshMindPalace() }
        .ornament(attachmentAnchor: .scene(.bottom)) {
            Button {
                Task { await openImmersiveSpace(id: "beagle-mind-palace") }
            } label: {
                Label("Enter Spatial Desk", systemImage: "rectangle.3.group.bubble.left")
            }
            .buttonStyle(.borderedProminent)
            .tint(BeagleTheme.truthObserved)
            .padding(14)
            .glassBackgroundEffect()
        }
    }

    private var header: some View {
        GlassPanel(elevated: true, truth: exocortex.mindPalace?.mode ?? .declared) {
            VStack(alignment: .leading, spacing: 10) {
                Text("Spatial Desk Mind Palace")
                    .font(BeagleTheme.displayFont(size: 30, weight: .semibold))
                    .foregroundStyle(BeagleTheme.textPrimary)
                Text(snapshot?.nextBestPlace.reason ?? "A memory-derived spatial desk for parallel work, portals, proof, and focus.")
                    .font(BeagleTheme.uiFont(size: 15))
                    .foregroundStyle(BeagleTheme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 8) {
                    TruthBadge(exocortex.mindPalace?.mode ?? .declared, compact: true)
                    statusChip(snapshot?.nextBestPlace.title ?? "next place")
                    statusChip(snapshot?.focusCoach.mode ?? "focus coach")
                }
            }
        }
    }

    private func rooms(_ rooms: [MindPalaceRoom]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("ROOMS")
                .font(BeagleTheme.uiFont(size: 11, weight: .semibold))
                .tracking(1.2)
                .foregroundStyle(BeagleTheme.textTertiary)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 240))], spacing: 12) {
                ForEach(rooms.prefix(8)) { room in
                    GlassPanel(truth: room.truthMode == "observed" ? .observed : .declared) {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(room.title)
                                .font(BeagleTheme.uiFont(size: 15, weight: .semibold))
                                .foregroundStyle(BeagleTheme.textPrimary)
                            Text(room.tension)
                                .font(BeagleTheme.uiFont(size: 12))
                                .foregroundStyle(BeagleTheme.textSecondary)
                                .lineLimit(3)
                            statusChip(room.sourceFamily)
                        }
                    }
                }
            }
        }
    }

    private func actionMenu(_ menu: SpatialActionMenu) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("ACTION MENU")
                .font(BeagleTheme.uiFont(size: 11, weight: .semibold))
                .tracking(1.2)
                .foregroundStyle(BeagleTheme.textTertiary)
            ForEach(menu.actions.prefix(6)) { action in
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: action.enabled ? "circle.fill" : "circle")
                        .font(.system(size: 9))
                        .foregroundStyle(action.enabled ? BeagleTheme.truthObserved : BeagleTheme.textTertiary)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(action.title)
                            .font(BeagleTheme.uiFont(size: 14, weight: .semibold))
                            .foregroundStyle(BeagleTheme.textPrimary)
                        Text(action.reason)
                            .font(BeagleTheme.uiFont(size: 12))
                            .foregroundStyle(BeagleTheme.textSecondary)
                            .lineLimit(2)
                    }
                }
                .padding(10)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
            }
        }
    }

    private func portals(_ portals: [ConversationPortal]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("PORTALS")
                .font(BeagleTheme.uiFont(size: 11, weight: .semibold))
                .tracking(1.2)
                .foregroundStyle(BeagleTheme.textTertiary)
            if portals.isEmpty {
                Text("Claude/GPT portals appear here after explicit registration. Promotion remains manual.")
                    .font(BeagleTheme.uiFont(size: 13))
                    .foregroundStyle(BeagleTheme.textSecondary)
            } else {
                ForEach(portals.prefix(4)) { portal in
                    GlassPanel(truth: .remembered) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(portal.title)
                                .font(BeagleTheme.uiFont(size: 14, weight: .semibold))
                                .foregroundStyle(BeagleTheme.textPrimary)
                            Text("\(portal.provider) · \(portal.sourceMode)")
                                .font(BeagleTheme.dataFont(size: 11))
                                .foregroundStyle(BeagleTheme.textTertiary)
                        }
                    }
                }
            }
        }
    }

    private func statusChip(_ text: String) -> some View {
        Text(text)
            .font(BeagleTheme.dataFont(size: 11))
            .padding(.horizontal, 9)
            .padding(.vertical, 4)
            .background(.thinMaterial, in: Capsule())
            .foregroundStyle(BeagleTheme.textSecondary)
    }
}

struct MindPalaceImmersiveView: View {
    @State private var exocortex = ExocortexStore()

    var body: some View {
        RealityView { content in
            content.add(MindPalaceSpatialRenderer.makeScene(snapshot: exocortex.mindPalace?.value))
        } update: { content in
            content.entities.removeAll()
            content.add(MindPalaceSpatialRenderer.makeScene(snapshot: exocortex.mindPalace?.value))
        }
        .task { await exocortex.refreshMindPalace() }
        .ornament(attachmentAnchor: .scene(.bottom)) {
            VStack(spacing: 5) {
                Text("Beagle Mind Palace")
                    .font(BeagleTheme.uiFont(size: 15, weight: .semibold))
                Text(exocortex.mindPalace?.value?.nextBestPlace.title ?? "Memory-derived Spatial Desk")
                    .font(BeagleTheme.dataFont(size: 12))
                    .foregroundStyle(BeagleTheme.textTertiary)
            }
            .padding(14)
            .glassBackgroundEffect()
        }
    }
}

enum MindPalaceSpatialRenderer {
    static func makeScene(snapshot: MindPalaceSnapshot?) -> Entity {
        let root = Entity()
        root.name = "beagle-mind-palace-root"
        addDesk(to: root)
        addRooms(to: root, rooms: snapshot?.rooms ?? [])
        addAgents(to: root, lanes: snapshot?.desk.agentLanes ?? [])
        addPortals(to: root, portals: snapshot?.desk.portals ?? [])
        return root
    }

    private static func addDesk(to root: Entity) {
        let desk = ModelEntity(
            mesh: .generateBox(size: SIMD3<Float>(1.2, 0.04, 0.74)),
            materials: [material(UIColor(red: 0.25, green: 0.84, blue: 0.95, alpha: 0.48))]
        )
        desk.position = SIMD3<Float>(0, -0.45, -1.1)
        desk.name = "spatial-desk"
        root.addChild(desk)
    }

    private static func addRooms(to root: Entity, rooms: [MindPalaceRoom]) {
        for (index, room) in rooms.prefix(8).enumerated() {
            let angle = Float(index) / Float(max(rooms.prefix(8).count, 1)) * Float.pi * 2
            let roomEntity = ModelEntity(
                mesh: .generateBox(size: SIMD3<Float>(0.16, 0.12, 0.035)),
                materials: [material(room.truthMode == "observed"
                    ? UIColor(red: 0.42, green: 0.95, blue: 0.70, alpha: 0.62)
                    : UIColor(red: 0.65, green: 0.72, blue: 0.95, alpha: 0.45))]
            )
            roomEntity.position = SIMD3<Float>(cos(angle) * 0.95, -0.12, -1.1 + sin(angle) * 0.62)
            roomEntity.name = "room-\(room.id)"
            root.addChild(roomEntity)
        }
    }

    private static func addAgents(to root: Entity, lanes: [String]) {
        for (index, lane) in lanes.prefix(8).enumerated() {
            let agent = ModelEntity(
                mesh: .generateSphere(radius: 0.045),
                materials: [material(UIColor(red: 0.82, green: 0.66, blue: 1.0, alpha: 0.72))]
            )
            agent.position = SIMD3<Float>(0.9, -0.32 + Float(index) * 0.1, -1.35)
            agent.name = "instrument-\(lane)"
            root.addChild(agent)
        }
    }

    private static func addPortals(to root: Entity, portals: [ConversationPortal]) {
        for (index, portal) in portals.prefix(4).enumerated() {
            let portalEntity = ModelEntity(
                mesh: .generateBox(size: SIMD3<Float>(0.2, 0.14, 0.02)),
                materials: [material(UIColor(red: 0.95, green: 0.75, blue: 0.45, alpha: 0.58))]
            )
            portalEntity.position = SIMD3<Float>(-0.9, -0.25 + Float(index) * 0.16, -1.34)
            portalEntity.name = "portal-\(portal.id)"
            root.addChild(portalEntity)
        }
    }

    private static func material(_ color: UIColor) -> SimpleMaterial {
        var material = SimpleMaterial()
        material.color = .init(tint: color)
        material.roughness = 0.28
        material.metallic = 0.08
        return material
    }
}
#endif
