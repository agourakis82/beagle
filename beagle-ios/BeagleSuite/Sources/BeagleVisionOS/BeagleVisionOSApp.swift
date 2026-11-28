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
import Observation

// MARK: - SpatialSpaceCoordinator

/// Coordinates exclusive transitions across visionOS ImmersiveSpaces so opening one space
/// while another is active cleanly dismisses the previous space first instead of failing.
@MainActor
@Observable
final class SpatialSpaceCoordinator {
    private(set) var activeImmersiveSpaceID: String?
    private(set) var isTransitioning = false

    func isOpen(_ id: String) -> Bool {
        activeImmersiveSpaceID == id
    }

    func noteDismissed(id: String) {
        if activeImmersiveSpaceID == id {
            activeImmersiveSpaceID = nil
        }
    }

    func dismissActive(using dismiss: DismissImmersiveSpaceAction) async {
        guard !isTransitioning, activeImmersiveSpaceID != nil else { return }
        isTransitioning = true
        defer { isTransitioning = false }
        await dismiss()
        activeImmersiveSpaceID = nil
    }

    func toggle(
        id: String,
        open: OpenImmersiveSpaceAction,
        dismiss: DismissImmersiveSpaceAction
    ) async {
        guard !isTransitioning else { return }
        isTransitioning = true
        defer { isTransitioning = false }

        if activeImmersiveSpaceID == id {
            await dismiss()
            activeImmersiveSpaceID = nil
            return
        }

        if activeImmersiveSpaceID != nil {
            await dismiss()
            activeImmersiveSpaceID = nil
        }

        switch await open(id: id) {
        case .opened:
            activeImmersiveSpaceID = id
        case .userCancelled, .error:
            activeImmersiveSpaceID = nil
        @unknown default:
            activeImmersiveSpaceID = nil
        }
    }
}

@main
struct BeagleVisionOSApp: App {
    @State private var catalog = CatalogStore()
    @State private var cognitive = CognitiveStore()
    @State private var physio = PhysioStore()
    @State private var hpc = HPCStore()
    @State private var spaceCoordinator = SpatialSpaceCoordinator()

    var body: some SwiftUI.Scene {

        // MARK: - Main Window — Spatial Mind

        WindowGroup("Cockpit", id: "cockpit") {
            SpatialMindView()
                .environment(catalog)
                .environment(cognitive)
                .environment(physio)
                .environment(hpc)
                .environment(spaceCoordinator)
                .task { await catalog.refresh() }
                .task { await physio.refresh(requestAuthorization: true) }
                .preferredColorScheme(.dark)
                .tint(BeagleTheme.truthObserved)
        }
        .defaultSize(width: 1060, height: 740)

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
                .environment(catalog)
                .environment(cognitive)
                .environment(physio)
                .environment(hpc)
                .environment(spaceCoordinator)
        }
        .immersionStyle(selection: .constant(.mixed), in: .mixed)

        // MARK: - Triad Spatial Debate

        ImmersiveSpace(id: "triad-debate") {
            SpatialTriadView()
                .environment(catalog)
                .environment(cognitive)
                .environment(physio)
                .environment(hpc)
                .environment(spaceCoordinator)
        }
        .immersionStyle(selection: .constant(.mixed), in: .mixed)

        // MARK: - Beagle Spatial Control Room

        WindowGroup("Spatial Control Room", id: "spatial-control-room") {
            NavigationStack {
                SpatialControlRoomView()
            }
            .environment(catalog)
            .environment(cognitive)
            .environment(physio)
            .environment(hpc)
            .environment(spaceCoordinator)
            .preferredColorScheme(.dark)
            .tint(BeagleTheme.truthObserved)
        }
        .defaultSize(width: 1100, height: 760)

        ImmersiveSpace(id: "beagle-control-room") {
            SpatialControlRoomImmersiveView()
                .environment(catalog)
                .environment(cognitive)
                .environment(physio)
                .environment(hpc)
                .environment(spaceCoordinator)
        }
        .immersionStyle(selection: .constant(.mixed), in: .mixed)

        // MARK: - Beagle Mind Palace / Spatial Desk

        WindowGroup("Mind Palace", id: "mind-palace") {
            NavigationStack {
                MindPalaceSpatialDeskView()
            }
            .environment(catalog)
            .environment(cognitive)
            .environment(physio)
            .environment(hpc)
            .environment(spaceCoordinator)
            .preferredColorScheme(.dark)
            .tint(BeagleTheme.truthObserved)
        }
        .defaultSize(width: 1180, height: 800)

        ImmersiveSpace(id: "beagle-mind-palace") {
            MindPalaceImmersiveView()
                .environment(catalog)
                .environment(cognitive)
                .environment(physio)
                .environment(hpc)
                .environment(spaceCoordinator)
        }
        .immersionStyle(selection: .constant(.mixed), in: .mixed)

        // MARK: - Cluster Volume (retained from v1)

        WindowGroup("Cluster Volume", id: "cluster-volume") {
            ClusterVolumeView()
                .environment(catalog)
        }
        .windowStyle(.volumetric)
        .defaultSize(width: 1.2, height: 0.8, depth: 1.2, in: .meters)

        // MARK: - Knowledge Graph Volume — Poincare disk in 3D

        WindowGroup("Knowledge Graph", id: "knowledge-graph") {
            HyperbolicGraphView(thoughts: cognitive.recentThoughts)
                .environment(cognitive)
        }
        .windowStyle(.volumetric)
        .defaultSize(width: 1.4, height: 0.8, depth: 1.4, in: .meters)

        // MARK: - Thought Stream — glass post-its floating in space

        WindowGroup("Thought Stream", id: "thought-stream") {
            SpatialThoughtsView(thoughts: cognitive.recentThoughts)
                .environment(cognitive)
        }
        .windowStyle(.volumetric)
        .defaultSize(width: 1.2, height: 0.6, depth: 0.8, in: .meters)
    }
}
