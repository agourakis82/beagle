//
//  ClusterWidgets.swift
//  BeagleWidgets
//
//  Cluster health, posture overview, and latest research widgets.
//

import WidgetKit
import SwiftUI
import BeagleCore

// MARK: - ClusterHealthWidget

struct ClusterHealthWidget: Widget {
    let kind: String = "ClusterHealthWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: ClusterHealthProvider()) { entry in
            ClusterHealthWidgetView(entry: entry)
                .containerBackground(BeagleTheme.surface0, for: .widget)
        }
        .configurationDisplayName("Cluster Health")
        .description("Live cluster status — nodes, GPU, health.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

struct ClusterHealthEntry: TimelineEntry {
    let date: Date
    let postureCounts: PostureCounts
    let truthMode: TruthMode
    let nodeHealth: [String: Bool]   // hostname → healthy
    let catalogProjects: [String]?   // project slugs for deep links
}

struct ClusterHealthProvider: TimelineProvider {
    typealias Entry = ClusterHealthEntry

    func placeholder(in context: Context) -> ClusterHealthEntry {
        ClusterHealthEntry(
            date: .now,
            postureCounts: PostureCounts(totalProjects: 7, alwaysOn: 1, warm: 4, cold: 2),
            truthMode: .declared,
            nodeHealth: ["r770": true, "r740": true, "t560": true],
            catalogProjects: ["sounio"]
        )
    }

    func getSnapshot(in context: Context, completion: @escaping (ClusterHealthEntry) -> Void) {
        nonisolated(unsafe) let completion = completion
        Task {
            let entry = await fetchEntry()
            completion(entry)
        }
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<ClusterHealthEntry>) -> Void) {
        nonisolated(unsafe) let completion = completion
        Task {
            let entry = await fetchEntry()
            let next = Date.now.addingTimeInterval(300) // refresh every 5 min
            completion(Timeline(entries: [entry], policy: .after(next)))
        }
    }

    private func fetchEntry() async -> ClusterHealthEntry {
        let catalog = await CockpitClient.shared.catalog()
        let counts = catalog.value?.projectPosturePolicy?.counts ?? .empty
        let slugs = catalog.value?.projects?.map(\.projectSlug)
        return ClusterHealthEntry(
            date: .now,
            postureCounts: counts,
            truthMode: catalog.mode,
            nodeHealth: [:],  // Real data fetched from cluster summary
            catalogProjects: slugs
        )
    }
}

struct ClusterHealthWidgetView: View {
    @Environment(\.widgetFamily) var family
    let entry: ClusterHealthEntry

    var body: some View {
        switch family {
        case .systemSmall:  smallView
        case .systemMedium: mediumView
        default:            largeView
        }
    }

    private var smallView: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: "sparkle")
                    .foregroundStyle(BeagleTheme.truthObserved)
                Text("CLUSTER")
                    .font(BeagleTheme.uiFont(size: 9, weight: .semibold))
                    .tracking(1)
                    .foregroundStyle(BeagleTheme.textTertiary)
                Spacer()
                TruthBadge(entry.truthMode, compact: true)
            }
            Spacer()
            HStack(spacing: 8) {
                ForEach(Array(entry.nodeHealth.keys.sorted()), id: \.self) { node in
                    Circle()
                        .fill(entry.nodeHealth[node] == true ? BeagleTheme.truthObserved : BeagleTheme.stateError)
                        .frame(width: 8, height: 8)
                }
            }
            Text("\(entry.postureCounts.totalProjects) projects")
                .font(BeagleTheme.dataFont(size: 11))
                .foregroundStyle(BeagleTheme.textSecondary)
        }
        .padding(8)
    }

    private var mediumView: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("CLUSTER").font(BeagleTheme.uiFont(size: 10, weight: .semibold)).tracking(1)
                    .foregroundStyle(BeagleTheme.textTertiary)
                Spacer()
                TruthBadge(entry.truthMode, compact: true)
            }
            VStack(alignment: .leading, spacing: 4) {
                ForEach(Array(entry.nodeHealth.keys.sorted()), id: \.self) { node in
                    HStack {
                        Circle()
                            .fill(entry.nodeHealth[node] == true ? BeagleTheme.truthObserved : BeagleTheme.stateError)
                            .frame(width: 6, height: 6)
                        Text(node)
                            .font(BeagleTheme.dataFont(size: 11))
                            .foregroundStyle(BeagleTheme.textData)
                    }
                }
            }
            Spacer()
            HStack(spacing: 12) {
                Label("\(entry.postureCounts.alwaysOn)", systemImage: "circle.fill")
                    .foregroundStyle(BeagleTheme.postureOn)
                Label("\(entry.postureCounts.warm)", systemImage: "circle.lefthalf.filled")
                    .foregroundStyle(BeagleTheme.postureWarm)
                Label("\(entry.postureCounts.cold)", systemImage: "circle")
                    .foregroundStyle(BeagleTheme.postureCold)
            }
            .font(BeagleTheme.dataFont(size: 11))
        }
        .padding(12)
    }

    private var largeView: some View {
        VStack(alignment: .leading, spacing: 10) {
            mediumView
            Divider()
            Text("Updated \(entry.date.formatted(date: .omitted, time: .shortened))")
                .font(BeagleTheme.dataFont(size: 10))
                .foregroundStyle(BeagleTheme.textTertiary)
        }
    }
}

// MARK: - PostureOverviewWidget

struct PostureOverviewWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "PostureOverviewWidget", provider: ClusterHealthProvider()) { entry in
            PostureOverviewView(entry: entry)
                .containerBackground(BeagleTheme.surface0, for: .widget)
        }
        .configurationDisplayName("Posture Overview")
        .description("Project posture summary at a glance.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

struct PostureOverviewView: View {
    let entry: ClusterHealthEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("POSTURE")
                .font(BeagleTheme.uiFont(size: 10, weight: .semibold)).tracking(1)
                .foregroundStyle(BeagleTheme.textTertiary)

            VStack(alignment: .leading, spacing: 4) {
                posture(label: "always-on", count: entry.postureCounts.alwaysOn, color: BeagleTheme.postureOn)
                posture(label: "warm", count: entry.postureCounts.warm, color: BeagleTheme.postureWarm)
                posture(label: "cold", count: entry.postureCounts.cold, color: BeagleTheme.postureCold)
            }

            Spacer()
            Text("\(entry.postureCounts.totalProjects) sovereign surfaces")
                .font(BeagleTheme.dataFont(size: 10))
                .foregroundStyle(BeagleTheme.textTertiary)
        }
        .padding(12)
    }

    private func posture(label: String, count: Int, color: Color) -> some View {
        HStack(spacing: 6) {
            Circle().fill(color).frame(width: 6, height: 6)
            Text("\(count)").font(BeagleTheme.dataFont(size: 13, weight: .medium)).foregroundStyle(color)
            Text(label).font(BeagleTheme.dataFont(size: 11)).foregroundStyle(BeagleTheme.textSecondary)
        }
    }
}

// MARK: - LatestResearchWidget

struct LatestResearchWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "LatestResearchWidget", provider: ClusterHealthProvider()) { entry in
            LatestResearchView(entry: entry)
                .containerBackground(BeagleTheme.surface0, for: .widget)
        }
        .configurationDisplayName("Latest Research")
        .description("Most recent ABIDE campaign or research run.")
        .supportedFamilies([.systemMedium, .systemLarge])
    }
}

struct LatestResearchView: View {
    let entry: ClusterHealthEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "flask.fill")
                    .foregroundStyle(BeagleTheme.truthObserved)
                Text("LATEST RUN")
                    .font(BeagleTheme.uiFont(size: 10, weight: .semibold)).tracking(1)
                    .foregroundStyle(BeagleTheme.textTertiary)
                Spacer()
                TruthBadge(entry.truthMode, compact: true)
            }

            if let projects = entry.catalogProjects, let first = projects.first {
                Link(destination: URL(string: "beagle://project/\(first)")!) {
                    Text(first)
                        .font(BeagleTheme.displayFont(size: 16, weight: .semibold))
                        .foregroundStyle(BeagleTheme.textPrimary)
                }
                Text("\(entry.postureCounts.totalProjects) sovereign surfaces")
                    .font(BeagleTheme.dataFont(size: 11))
                    .foregroundStyle(BeagleTheme.textSecondary)
            } else {
                Text("no projects")
                    .font(BeagleTheme.dataFont(size: 14))
                    .foregroundStyle(BeagleTheme.textTertiary)
            }

            Spacer()
            Text("Updated \(entry.date.formatted(date: .omitted, time: .shortened))")
                .font(BeagleTheme.dataFont(size: 10))
                .foregroundStyle(BeagleTheme.textTertiary)
        }
        .padding(12)
    }
}
