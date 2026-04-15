//
//  BeagleWidgets.swift
//  BeagleWidgets
//
//  WidgetKit + ActivityKit for home screen / lock screen / Dynamic Island.
//
//  Widgets:
//   - ClusterHealthWidget (small/medium/large)
//   - PostureOverviewWidget
//   - LatestResearchWidget
//
//  Live Activities:
//   - AgentSessionActivity (Claude Code / Codex running)
//   - ResearchRunActivity (ABIDE campaign progress)
//

import WidgetKit
import SwiftUI
#if os(iOS)
import ActivityKit
#endif
import BeagleCore

// MARK: - Widget Bundle entry

@main
struct BeagleWidgetsBundle: WidgetBundle {
    var body: some Widget {
        ClusterHealthWidget()
        PostureOverviewWidget()
        LatestResearchWidget()
        FlowStateWidget()
        ThoughtCaptureWidget()

        // Live Activities (iOS only)
        #if os(iOS)
        AgentSessionActivityConfiguration()
        ResearchRunActivityConfiguration()
        #endif
    }
}

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

struct ClusterHealthProvider: @preconcurrency TimelineProvider {
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

// MARK: - Lock Screen: Flow State Widget

struct FlowStateWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "FlowStateWidget", provider: FlowStateProvider()) { entry in
            FlowStateWidgetView(entry: entry)
                .containerBackground(BeagleTheme.surface0, for: .widget)
        }
        .configurationDisplayName("Flow State")
        .description("Your HRV and cognitive flow state on the lock screen.")
        .supportedFamilies([.accessoryCircular, .accessoryRectangular, .systemSmall])
    }
}

struct FlowStateEntry: TimelineEntry {
    let date: Date
    let hrvMs: Double
    let flowState: String
}

struct FlowStateProvider: @preconcurrency TimelineProvider {
    typealias Entry = FlowStateEntry

    func placeholder(in context: Context) -> FlowStateEntry {
        FlowStateEntry(date: .now, hrvMs: 72, flowState: "NORMAL")
    }

    func getSnapshot(in context: Context, completion: @escaping (FlowStateEntry) -> Void) {
        completion(FlowStateEntry(date: .now, hrvMs: 72, flowState: "NORMAL"))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<FlowStateEntry>) -> Void) {
        nonisolated(unsafe) let completion = completion
        Task {
            let state = await BeagleClient.shared.cognitiveState()
            let hrv = state.value?.hrv?.latestMs ?? 0
            let flow = state.value?.hrv?.displayFlowState ?? "UNKNOWN"
            let entry = FlowStateEntry(date: .now, hrvMs: hrv, flowState: flow)
            let next = Date.now.addingTimeInterval(600)
            completion(Timeline(entries: [entry], policy: .after(next)))
        }
    }
}

struct FlowStateWidgetView: View {
    @Environment(\.widgetFamily) var family
    let entry: FlowStateEntry

    private var flowColor: Color {
        switch entry.flowState {
        case "FLOW":   return BeagleTheme.truthObserved
        case "STRESS": return BeagleTheme.stateError
        default:       return BeagleTheme.textData
        }
    }

    var body: some View {
        switch family {
        case .accessoryCircular:
            ZStack {
                AccessoryWidgetBackground()
                VStack(spacing: 1) {
                    Text("\(Int(entry.hrvMs))")
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                    Text("ms")
                        .font(.system(size: 8))
                        .foregroundStyle(.secondary)
                }
            }
        case .accessoryRectangular:
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Image(systemName: "heart.fill")
                        .font(.system(size: 10))
                    Text("FLOW")
                        .font(.system(size: 9, weight: .semibold))
                        .tracking(0.5)
                }
                .foregroundStyle(.secondary)
                HStack(alignment: .firstTextBaseline, spacing: 3) {
                    Text("\(Int(entry.hrvMs))")
                        .font(.system(size: 22, weight: .bold, design: .rounded))
                    Text("ms")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
                Text(entry.flowState.lowercased())
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)
            }
        default:
            // systemSmall
            VStack(spacing: 8) {
                Text("FLOW")
                    .font(BeagleTheme.uiFont(size: 9, weight: .semibold))
                    .tracking(1)
                    .foregroundStyle(BeagleTheme.textTertiary)
                Text("\(Int(entry.hrvMs))")
                    .font(.system(size: 36, weight: .bold, design: .rounded))
                    .foregroundStyle(flowColor)
                Text("ms · \(entry.flowState)")
                    .font(BeagleTheme.dataFont(size: 11))
                    .foregroundStyle(BeagleTheme.textSecondary)
            }
            .padding(12)
        }
    }
}

// MARK: - Lock Screen: Quick Capture Widget

struct ThoughtCaptureWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "ThoughtCaptureWidget", provider: CaptureWidgetProvider()) { entry in
            CaptureWidgetView(entry: entry)
                .containerBackground(BeagleTheme.surface0, for: .widget)
        }
        .configurationDisplayName("Quick Capture")
        .description("Tap to capture a thought into your exocortex.")
        .supportedFamilies([.accessoryRectangular, .systemSmall])
    }
}

struct CaptureWidgetEntry: TimelineEntry {
    let date: Date
    let thoughtCount: Int
}

struct CaptureWidgetProvider: @preconcurrency TimelineProvider {
    typealias Entry = CaptureWidgetEntry

    func placeholder(in context: Context) -> CaptureWidgetEntry {
        CaptureWidgetEntry(date: .now, thoughtCount: 0)
    }

    func getSnapshot(in context: Context, completion: @escaping (CaptureWidgetEntry) -> Void) {
        completion(CaptureWidgetEntry(date: .now, thoughtCount: 0))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<CaptureWidgetEntry>) -> Void) {
        let entry = CaptureWidgetEntry(date: .now, thoughtCount: 0)
        let next = Date.now.addingTimeInterval(3600)
        completion(Timeline(entries: [entry], policy: .after(next)))
    }
}

struct CaptureWidgetView: View {
    @Environment(\.widgetFamily) var family
    let entry: CaptureWidgetEntry

    var body: some View {
        switch family {
        case .accessoryRectangular:
            Link(destination: URL(string: "beagle://capture")!) {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 4) {
                        Image(systemName: "thought.bubble")
                            .font(.system(size: 10))
                        Text("CAPTURE")
                            .font(.system(size: 9, weight: .semibold))
                            .tracking(0.5)
                    }
                    .foregroundStyle(.secondary)
                    Text("Tap to capture a thought")
                        .font(.system(size: 11))
                }
            }
        default:
            // systemSmall
            Link(destination: URL(string: "beagle://capture")!) {
                VStack(spacing: 8) {
                    Image(systemName: "thought.bubble")
                        .font(.system(size: 28))
                        .foregroundStyle(BeagleTheme.truthRemembered)
                    Text("Capture")
                        .font(BeagleTheme.uiFont(size: 13, weight: .semibold))
                        .foregroundStyle(BeagleTheme.textPrimary)
                    Text("Tap to think")
                        .font(BeagleTheme.dataFont(size: 10))
                        .foregroundStyle(BeagleTheme.textTertiary)
                }
                .padding(12)
            }
        }
    }
}

// MARK: - Live Activity: Agent Session

#if os(iOS)
struct AgentSessionActivityConfiguration: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: AgentSessionAttributes.self) { context in
            // Lock screen / banner UI
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Image(systemName: "sparkles")
                        .foregroundStyle(BeagleTheme.truthObserved)
                    Text("\(context.attributes.agentKind.uppercased()) · \(context.attributes.projectSlug)")
                        .font(BeagleTheme.dataFont(size: 12, weight: .medium))
                        .foregroundStyle(BeagleTheme.textPrimary)
                    Spacer()
                    Text(context.state.status)
                        .font(BeagleTheme.dataFont(size: 11))
                        .foregroundStyle(BeagleTheme.truthObserved)
                }
                if !context.state.lastOutputSnippet.isEmpty {
                    Text(context.state.lastOutputSnippet)
                        .font(BeagleTheme.dataFont(size: 11))
                        .foregroundStyle(BeagleTheme.textSecondary)
                        .lineLimit(2)
                }
                HStack {
                    Text("\(context.state.tokensUsed) tokens")
                        .font(BeagleTheme.dataFont(size: 10))
                        .foregroundStyle(BeagleTheme.textTertiary)
                    Spacer()
                }
            }
            .padding(12)
            .activityBackgroundTint(BeagleTheme.surface1)
            .activitySystemActionForegroundColor(BeagleTheme.truthObserved)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Image(systemName: "sparkles")
                        .foregroundStyle(BeagleTheme.truthObserved)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text(context.state.status)
                        .font(BeagleTheme.dataFont(size: 11))
                        .foregroundStyle(BeagleTheme.truthObserved)
                }
                DynamicIslandExpandedRegion(.center) {
                    Text("\(context.attributes.agentKind) · \(context.attributes.projectSlug)")
                        .font(BeagleTheme.dataFont(size: 12, weight: .medium))
                }
                DynamicIslandExpandedRegion(.bottom) {
                    Text(context.state.lastOutputSnippet)
                        .font(BeagleTheme.dataFont(size: 10))
                        .foregroundStyle(BeagleTheme.textSecondary)
                        .lineLimit(2)
                }
            } compactLeading: {
                Image(systemName: "sparkles")
            } compactTrailing: {
                Text(context.state.status.prefix(4))
                    .font(BeagleTheme.dataFont(size: 10))
            } minimal: {
                Image(systemName: "sparkles")
                    .foregroundStyle(BeagleTheme.truthObserved)
            }
        }
    }
}

// MARK: - Live Activity: Research Run

struct ResearchRunActivityConfiguration: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: ResearchRunAttributes.self) { context in
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Image(systemName: "flask.fill")
                        .foregroundStyle(BeagleTheme.truthObserved)
                    Text(context.attributes.campaignName)
                        .font(BeagleTheme.dataFont(size: 12, weight: .medium))
                    Spacer()
                    Text("ETA \(context.state.etaSeconds / 60)m")
                        .font(BeagleTheme.dataFont(size: 11))
                        .foregroundStyle(BeagleTheme.truthObserved)
                }
                ProgressView(value: Double(context.state.stepCurrent), total: Double(context.state.stepTotal))
                    .tint(BeagleTheme.truthObserved)
                Text("step \(context.state.stepCurrent) of \(context.state.stepTotal)")
                    .font(BeagleTheme.dataFont(size: 10))
                    .foregroundStyle(BeagleTheme.textTertiary)
            }
            .padding(12)
            .activityBackgroundTint(BeagleTheme.surface1)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Image(systemName: "flask.fill")
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text("ETA \(context.state.etaSeconds / 60)m")
                        .font(BeagleTheme.dataFont(size: 11))
                }
                DynamicIslandExpandedRegion(.bottom) {
                    ProgressView(value: Double(context.state.stepCurrent), total: Double(context.state.stepTotal))
                }
            } compactLeading: {
                Image(systemName: "flask.fill")
            } compactTrailing: {
                Text("\(context.state.stepCurrent)/\(context.state.stepTotal)")
                    .font(BeagleTheme.dataFont(size: 10))
            } minimal: {
                Image(systemName: "flask.fill")
            }
        }
    }
}
#endif
