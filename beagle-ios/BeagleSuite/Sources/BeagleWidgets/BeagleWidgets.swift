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
        CognitiveActivityConfiguration()
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

// MARK: - Lock Screen: Flow State Widget

struct FlowStateWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "FlowStateWidget", provider: FlowStateProvider()) { entry in
            FlowStateWidgetView(entry: entry)
                .containerBackground(BeagleTheme.surface0, for: .widget)
        }
        .configurationDisplayName("Cluster Pulse")
        .description("Active agents and cluster health at a glance.")
        .supportedFamilies([.accessoryCircular, .accessoryRectangular, .systemSmall])
    }
}

struct FlowStateEntry: TimelineEntry {
    let date: Date
    let activeAgents: Int
    let activeSessions: Int
    let clusterHealth: String
}

struct FlowStateProvider: TimelineProvider {
    typealias Entry = FlowStateEntry

    func placeholder(in context: Context) -> FlowStateEntry {
        FlowStateEntry(date: .now, activeAgents: 2, activeSessions: 1, clusterHealth: "healthy")
    }

    func getSnapshot(in context: Context, completion: @escaping (FlowStateEntry) -> Void) {
        completion(FlowStateEntry(date: .now, activeAgents: 2, activeSessions: 1, clusterHealth: "healthy"))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<FlowStateEntry>) -> Void) {
        nonisolated(unsafe) let completion = completion
        Task {
            // cognitive/state was retired on beagle-core; cluster pulse now comes from the
            // mobile summary gateway (CockpitClient.fetchMobile), which is real and live.
            let summary = await CockpitClient.shared.mobileSummary()
            let agents = summary.value?.activeAgentsCount ?? 0
            let sessions = summary.value?.activeSessionsCount ?? 0
            let healthRaw = summary.value?.clusterHealth ?? ""
            let health = healthRaw.isEmpty ? "unknown" : healthRaw
            let entry = FlowStateEntry(date: .now, activeAgents: agents,
                                       activeSessions: sessions, clusterHealth: health)
            let next = Date.now.addingTimeInterval(600)
            completion(Timeline(entries: [entry], policy: .after(next)))
        }
    }
}

struct FlowStateWidgetView: View {
    @Environment(\.widgetFamily) var family
    let entry: FlowStateEntry

    private var healthColor: Color {
        switch entry.clusterHealth.lowercased() {
        case "healthy", "ok", "ready", "green":          return BeagleTheme.truthObserved
        case "unhealthy", "down", "error", "red", "critical": return BeagleTheme.stateError
        default:                                          return BeagleTheme.textData
        }
    }

    var body: some View {
        switch family {
        case .accessoryCircular:
            ZStack {
                AccessoryWidgetBackground()
                VStack(spacing: 1) {
                    Text("\(entry.activeAgents)")
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                    Text("agt")
                        .font(.system(size: 8))
                        .foregroundStyle(.secondary)
                }
            }
        case .accessoryRectangular:
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Image(systemName: "cpu.fill")
                        .font(.system(size: 10))
                    Text("CLUSTER")
                        .font(.system(size: 9, weight: .semibold))
                        .tracking(0.5)
                }
                .foregroundStyle(.secondary)
                HStack(alignment: .firstTextBaseline, spacing: 3) {
                    Text("\(entry.activeAgents)")
                        .font(.system(size: 22, weight: .bold, design: .rounded))
                    Text(entry.activeAgents == 1 ? "agent" : "agents")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
                Text("\(entry.clusterHealth.lowercased()) · \(entry.activeSessions) sessions")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)
            }
        default:
            // systemSmall
            VStack(spacing: 8) {
                Text("CLUSTER")
                    .font(BeagleTheme.uiFont(size: 9, weight: .semibold))
                    .tracking(1)
                    .foregroundStyle(BeagleTheme.textTertiary)
                Text("\(entry.activeAgents)")
                    .font(.system(size: 36, weight: .bold, design: .rounded))
                    .foregroundStyle(healthColor)
                Text("active · \(entry.clusterHealth.lowercased())")
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

struct CaptureWidgetProvider: TimelineProvider {
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

// MARK: - Live Activity: Cognitive State (HRV + Agent Posture)

struct CognitiveActivityConfiguration: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: CognitiveActivityAttributes.self) { context in
            // Lock screen / notification banner
            CognitiveLockScreenView(state: context.state)
                .activityBackgroundTint(BeagleTheme.surface1)
                .activitySystemActionForegroundColor(
                    BeagleTheme.color(forIntensity: context.state.intensity)
                )
        } dynamicIsland: { context in
            DynamicIsland {
                // Expanded: full cognitive dashboard
                DynamicIslandExpandedRegion(.leading) {
                    CognitiveReadinessGauge(
                        readiness: context.state.readiness,
                        intensity: context.state.intensity,
                        size: 44
                    )
                }
                DynamicIslandExpandedRegion(.trailing) {
                    VStack(alignment: .trailing, spacing: 4) {
                        if let hrv = context.state.hrvMs {
                            HStack(spacing: 3) {
                                Image(systemName: "heart.fill")
                                    .font(.system(size: 9))
                                    .foregroundStyle(BeagleTheme.color(forIntensity: context.state.intensity))
                                Text("\(Int(hrv)) ms")
                                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                            }
                        }
                        if context.state.agentCount > 0 {
                            HStack(spacing: 3) {
                                Image(systemName: "sparkles")
                                    .font(.system(size: 9))
                                Text("\(context.state.agentCount)")
                                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                            }
                            .foregroundStyle(BeagleTheme.truthObserved)
                        }
                    }
                }
                DynamicIslandExpandedRegion(.center) {
                    Text(context.state.intensityLabel)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(BeagleTheme.color(forIntensity: context.state.intensity))
                }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(alignment: .leading, spacing: 4) {
                        if context.state.activeJobCount > 0 {
                            HStack(spacing: 4) {
                                Image(systemName: "gearshape.2.fill")
                                    .font(.system(size: 9))
                                    .foregroundStyle(BeagleTheme.textTertiary)
                                Text("\(context.state.activeJobCount) active job\(context.state.activeJobCount == 1 ? "" : "s")")
                                    .font(.system(size: 11, weight: .regular))
                                    .foregroundStyle(BeagleTheme.textSecondary)
                            }
                        }
                        if let snippet = context.state.lastThoughtSnippet, !snippet.isEmpty {
                            Text(snippet)
                                .font(.system(size: 11))
                                .foregroundStyle(BeagleTheme.textSecondary)
                                .lineLimit(2)
                        }
                    }
                }
            } compactLeading: {
                // Readiness as a small circular gauge
                CognitiveReadinessGauge(
                    readiness: context.state.readiness,
                    intensity: context.state.intensity,
                    size: 24
                )
            } compactTrailing: {
                // Agent count when agents are active
                if context.state.agentCount > 0 {
                    HStack(spacing: 2) {
                        Image(systemName: "sparkles")
                            .font(.system(size: 9))
                        Text("\(context.state.agentCount)")
                            .font(.system(size: 12, weight: .semibold, design: .monospaced))
                    }
                    .foregroundStyle(BeagleTheme.truthObserved)
                } else {
                    Text(context.state.intensity.prefix(3).uppercased())
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundStyle(BeagleTheme.color(forIntensity: context.state.intensity))
                }
            } minimal: {
                CognitiveReadinessGauge(
                    readiness: context.state.readiness,
                    intensity: context.state.intensity,
                    size: 20
                )
            }
        }
    }
}

// MARK: - Cognitive Activity: Subviews

private struct CognitiveReadinessGauge: View {
    let readiness: Double?
    let intensity: String
    let size: CGFloat

    private var fraction: Double {
        readiness ?? 0
    }

    private var tint: Color {
        BeagleTheme.color(forIntensity: intensity)
    }

    var body: some View {
        ZStack {
            Circle()
                .stroke(tint.opacity(0.2), lineWidth: size > 30 ? 4 : 2.5)
            Circle()
                .trim(from: 0, to: fraction)
                .stroke(tint, style: StrokeStyle(
                    lineWidth: size > 30 ? 4 : 2.5,
                    lineCap: .round
                ))
                .rotationEffect(.degrees(-90))

            if size >= 40 {
                Text("\(Int((fraction * 100).rounded()))")
                    .font(.system(size: size * 0.3, weight: .bold, design: .rounded))
                    .foregroundStyle(tint)
            }
        }
        .frame(width: size, height: size)
    }
}

private struct CognitiveLockScreenView: View {
    let state: CognitiveActivityAttributes.ContentState

    private var tint: Color {
        BeagleTheme.color(forIntensity: state.intensity)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                CognitiveReadinessGauge(
                    readiness: state.readiness,
                    intensity: state.intensity,
                    size: 36
                )

                VStack(alignment: .leading, spacing: 2) {
                    Text(state.lockScreenLine)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(tint)

                    HStack(spacing: 8) {
                        if let hrv = state.hrvMs {
                            HStack(spacing: 3) {
                                Image(systemName: "heart.fill")
                                    .font(.system(size: 9))
                                Text("\(Int(hrv)) ms")
                                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                            }
                            .foregroundStyle(BeagleTheme.textData)
                        }
                        if state.activeJobCount > 0 {
                            HStack(spacing: 3) {
                                Image(systemName: "gearshape.2.fill")
                                    .font(.system(size: 9))
                                Text("\(state.activeJobCount) job\(state.activeJobCount == 1 ? "" : "s")")
                                    .font(.system(size: 11, weight: .regular))
                            }
                            .foregroundStyle(BeagleTheme.textSecondary)
                        }
                    }
                }

                Spacer()
            }

            if let snippet = state.lastThoughtSnippet, !snippet.isEmpty {
                Text(snippet)
                    .font(.system(size: 11))
                    .foregroundStyle(BeagleTheme.textSecondary)
                    .lineLimit(2)
            }
        }
        .padding(12)
    }
}
#endif
