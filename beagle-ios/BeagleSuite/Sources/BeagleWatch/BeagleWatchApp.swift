//
//  BeagleWatchApp.swift
//  BeagleWatch
//
//  watchOS 26 companion — cluster glance from the wrist.
//
//  Screens:
//   - Cluster status (pulse of truth badge + posture counts)
//   - Project list (all sovereign surfaces)
//   - Project detail (mission + cluster + research)
//   - HRV flow state (preserved from BeagleHRV prototype)
//

import SwiftUI
import BeagleCore
import HealthKit

@main
struct BeagleWatchApp: App {
    @State private var catalog = CatalogStore()
    @State private var hrv = HRVMonitor()

    var body: some Scene {
        WindowGroup {
            WatchRootView()
                .environment(catalog)
                .environment(hrv)
                .task {
                    await catalog.refresh()
                    await hrv.start()
                }
        }
    }
}

// MARK: - Root

struct WatchRootView: View {
    @Environment(CatalogStore.self) private var catalog

    var body: some View {
        TabView {
            ClusterGlanceView()
                .tabItem { Label("Cluster", systemImage: "sparkle") }

            ProjectListView()
                .tabItem { Label("Projects", systemImage: "folder.fill") }

            HRVFlowView()
                .tabItem { Label("Flow", systemImage: "heart.fill") }
        }
    }
}

// MARK: - ClusterGlanceView

struct ClusterGlanceView: View {
    @Environment(CatalogStore.self) private var catalog

    var body: some View {
        let counts = catalog.postureCounts
        VStack(spacing: 10) {
            Text("COCKPIT")
                .font(BeagleTheme.uiFont(size: 9, weight: .semibold))
                .tracking(1)
                .foregroundStyle(BeagleTheme.textTertiary)

            TruthBadge(catalog.executive.mode)

            VStack(spacing: 4) {
                row(count: counts.alwaysOn, label: "on", color: BeagleTheme.postureOn)
                row(count: counts.warm, label: "warm", color: BeagleTheme.postureWarm)
                row(count: counts.cold, label: "cold", color: BeagleTheme.postureCold)
            }

            Button {
                Task { await catalog.refresh() }
            } label: {
                Label("Refresh", systemImage: "arrow.clockwise")
            }
            .buttonStyle(.bordered)
            .controlSize(.mini)
        }
        .padding(.horizontal, 8)
    }

    private func row(count: Int, label: String, color: Color) -> some View {
        HStack(spacing: 4) {
            Circle().fill(color).frame(width: 5, height: 5)
            Text("\(count)")
                .font(BeagleTheme.dataFont(size: 14, weight: .semibold))
                .foregroundStyle(color)
            Text(label)
                .font(BeagleTheme.dataFont(size: 11))
                .foregroundStyle(BeagleTheme.textSecondary)
            Spacer()
        }
    }
}

// MARK: - ProjectListView

struct ProjectListView: View {
    @Environment(CatalogStore.self) private var catalog

    var body: some View {
        List {
            ForEach(catalog.projects) { project in
                NavigationLink(value: project) {
                    HStack {
                        PostureIndicator(project.posture, size: 10, showLabel: false)
                        Text(project.projectSlug)
                            .font(BeagleTheme.dataFont(size: 12))
                        Spacer()
                    }
                }
            }
        }
        .navigationDestination(for: Project.self) { project in
            ProjectGlanceView(slug: project.projectSlug)
        }
    }
}

// MARK: - ProjectGlanceView

struct ProjectGlanceView: View {
    let slug: String
    @State private var store: ProjectStore

    init(slug: String) {
        self.slug = slug
        self._store = State(initialValue: ProjectStore(slug: slug))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(slug)
                    .font(BeagleTheme.dataFont(size: 14, weight: .medium))
                Spacer()
                PostureIndicator(store.posture, size: 10, showLabel: false)
            }
            TruthBadge(store.mission.mode, compact: true)

            if let project = store.project {
                Text(project.workspacePod != nil ? "● live" : "○ standby")
                    .font(BeagleTheme.dataFont(size: 11))
                    .foregroundStyle(project.workspacePod != nil ? BeagleTheme.truthObserved : BeagleTheme.textTertiary)
                if let branch = project.branch {
                    Text(branch)
                        .font(BeagleTheme.dataFont(size: 10))
                        .foregroundStyle(BeagleTheme.textTertiary)
                        .lineLimit(1)
                }
            }

            Spacer()
        }
        .padding(.horizontal, 4)
        .task { await store.refresh() }
    }
}

// MARK: - HRV Flow integration

@Observable
@MainActor
final class HRVMonitor {
    enum FlowState: String { case flow, normal, stress, unknown }

    private let healthStore = HKHealthStore()
    private let hrvType = HKQuantityType.quantityType(forIdentifier: .heartRateVariabilitySDNN)!

    var latestHRV: Double = 0
    var flowState: FlowState = .unknown

    func start() async {
        guard HKHealthStore.isHealthDataAvailable() else { return }
        do {
            try await healthStore.requestAuthorization(toShare: [], read: [hrvType])
            await fetchLatest()
        } catch {
            print("[HRV] auth failed: \(error)")
        }
    }

    func fetchLatest() async {
        let end = Date.now
        let start = end.addingTimeInterval(-3600 * 6)
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end)
        let sort = NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)

        let sample: HKQuantitySample? = await withCheckedContinuation { cont in
            let query = HKSampleQuery(
                sampleType: hrvType,
                predicate: predicate,
                limit: 1,
                sortDescriptors: [sort]
            ) { _, samples, _ in
                cont.resume(returning: samples?.first as? HKQuantitySample)
            }
            healthStore.execute(query)
        }

        guard let sample else { return }
        let unit = HKUnit(from: "ms")
        let value = sample.quantity.doubleValue(for: unit)
        latestHRV = value
        flowState = classify(hrv: value)
    }

    private func classify(hrv: Double) -> FlowState {
        if hrv > 80 { return .flow }
        if hrv < 50 { return .stress }
        return .normal
    }
}

struct HRVFlowView: View {
    @Environment(HRVMonitor.self) private var hrv

    var body: some View {
        VStack(spacing: 10) {
            Text("FLOW")
                .font(BeagleTheme.uiFont(size: 9, weight: .semibold))
                .tracking(1)
                .foregroundStyle(BeagleTheme.textTertiary)

            Text(String(format: "%.0f", hrv.latestHRV))
                .font(BeagleTheme.displayFont(size: 40, weight: .bold))
                .foregroundStyle(color(for: hrv.flowState))

            Text("ms · \(hrv.flowState.rawValue.uppercased())")
                .font(BeagleTheme.dataFont(size: 11))
                .foregroundStyle(BeagleTheme.textSecondary)

            Button {
                Task { await hrv.fetchLatest() }
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .buttonStyle(.bordered)
            .controlSize(.mini)
        }
    }

    private func color(for state: HRVMonitor.FlowState) -> Color {
        switch state {
        case .flow:    return BeagleTheme.truthObserved
        case .normal:  return BeagleTheme.textData
        case .stress:  return BeagleTheme.stateError
        case .unknown: return BeagleTheme.textTertiary
        }
    }
}
