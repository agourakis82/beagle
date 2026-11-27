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
//   - CompanionVoiceLauncherWidget
//
//  Live Activities:
//   - CompanionVoiceSessionActivityConfiguration (Walkie-Talkie Hands-Free + Interactive Dynamic Island)
//   - CompanionTurnActivityConfiguration
//   - AgentSessionActivity (Claude Code / Codex running)
//   - ResearchRunActivity (ABIDE campaign progress)
//   - CognitiveActivityConfiguration
//

import AppIntents
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
        MorningBriefingWidget()
        ClusterHealthWidget()
        PostureOverviewWidget()
        LatestResearchWidget()
        FlowStateWidget()
        ThoughtCaptureWidget()
        CompanionVoiceLauncherWidget()

        // Control Center & Lock Screen Controls + Live Activities (iOS only)
        #if os(iOS)
        BeagleVoiceControlWidget()
        BeagleMorningControlWidget()
        BeagleModoFundoControlWidget()
        CompanionVoiceSessionActivityConfiguration()
        CompanionTurnActivityConfiguration()
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

struct FlowStateProvider: TimelineProvider {
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

// MARK: - Companion Voice Launcher Widget (Lock Screen Circular/Rectangular + Home Small)

struct CompanionVoiceLauncherWidget: Widget {
    let kind: String = "CompanionVoiceLauncherWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: CaptureWidgetProvider()) { entry in
            CompanionVoiceLauncherView(entry: entry)
                .containerBackground(BeagleTheme.surface0, for: .widget)
        }
        .configurationDisplayName("Beagle Voz Mãos-Livres")
        .description("Abre o Beagle em sessão contínua de voz mãos-livres (Walkie-Talkie + Dynamic Island).")
        .supportedFamilies([.accessoryCircular, .accessoryRectangular, .systemSmall])
    }
}

struct CompanionVoiceLauncherView: View {
    @Environment(\.widgetFamily) var family
    let entry: CaptureWidgetEntry

    var body: some View {
        switch family {
        case .accessoryCircular:
            ZStack {
                AccessoryWidgetBackground()
                Image(systemName: "waveform.circle.fill")
                    .font(.system(size: 24, weight: .semibold))
            }
            .widgetURL(URL(string: "beagle://voice"))

        case .accessoryRectangular:
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Image(systemName: "waveform.circle.fill")
                        .font(.system(size: 11, weight: .semibold))
                    Text("BEAGLE VOZ")
                        .font(.system(size: 9, weight: .semibold))
                        .tracking(0.5)
                }
                .foregroundStyle(.secondary)
                Text("Walkie-talkie mãos-livres")
                    .font(.system(size: 11, weight: .medium))
            }
            .widgetURL(URL(string: "beagle://voice"))

        default:
            Link(destination: URL(string: "beagle://voice")!) {
                VStack(spacing: 8) {
                    Image(systemName: "waveform.circle.fill")
                        .font(.system(size: 30))
                        .foregroundStyle(BeagleTheme.truthObserved)
                    Text("Voz Beagle")
                        .font(BeagleTheme.uiFont(size: 13, weight: .semibold))
                        .foregroundStyle(BeagleTheme.textPrimary)
                    Text("Contínua")
                        .font(BeagleTheme.dataFont(size: 10))
                        .foregroundStyle(BeagleTheme.textTertiary)
                }
                .padding(12)
            }
        }
    }
}

#if os(iOS)
struct BeagleVoiceControlWidget: ControlWidget {
    static let kind: String = "dev.sounio.cockpit.control.voice"

    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: Self.kind) {
            ControlWidgetButton(action: OpenURLIntent(URL(string: "beagle://voice")!)) {
                Label("Voz Beagle", systemImage: "waveform.circle.fill")
            }
        }
        .displayName("Falar com Beagle")
        .description("Abre o Beagle Cockpit em sessão contínua de voz mãos-livres.")
    }
}

struct BeagleMorningControlWidget: ControlWidget {
    static let kind: String = "dev.sounio.cockpit.control.morning"

    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: Self.kind) {
            ControlWidgetButton(action: OpenURLIntent(URL(string: "beagle://sintese")!)) {
                Label("Síntese Matinal", systemImage: "sun.horizon.fill")
            }
        }
        .displayName("Síntese Matinal Beagle")
        .description("Abre a Síntese Matinal diária (Fisioma × Clima Espacial × Agenda 48h).")
    }
}

struct BeagleModoFundoControlWidget: ControlWidget {
    static let kind: String = "dev.sounio.cockpit.control.fundo"

    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: Self.kind) {
            ControlWidgetButton(action: OpenURLIntent(URL(string: "beagle://fundo")!)) {
                Label("Modo Fundo", systemImage: "scope")
            }
        }
        .displayName("Modo Fundo Beagle")
        .description("Abre a exploração científica profunda (GPT-6.2 Astra xhigh + GPT-Rosalind).")
    }
}
#endif

// MARK: - Morning Briefing Widget (Lock Screen + Home Screen)

struct MorningBriefingWidget: Widget {
    let kind: String = "MorningBriefingWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: MorningBriefingProvider()) { entry in
            MorningBriefingWidgetView(entry: entry)
                .containerBackground(BeagleTheme.surface0, for: .widget)
        }
        .configurationDisplayName("Síntese Matinal")
        .description("Pulso autonômico (HRV/Sono), clima espacial (Kp) e síntese diária do Beagle.")
        .supportedFamilies([.accessoryCircular, .accessoryRectangular, .systemSmall, .systemMedium])
    }
}

struct MorningBriefingEntry: TimelineEntry {
    let date: Date
    let digest: DailyBriefingBuilder.WidgetBriefingDigest?
}

struct MorningBriefingProvider: TimelineProvider {
    typealias Entry = MorningBriefingEntry

    func placeholder(in context: Context) -> MorningBriefingEntry {
        MorningBriefingEntry(
            date: .now,
            digest: DailyBriefingBuilder.WidgetBriefingDigest(
                dateISO: ISO8601DateFormatter().string(from: .now),
                headline: "HRV estável, céu calmo — proteger foco profundo na manhã.",
                readinessLabel: "restored",
                hrvMs: 68,
                sleepHours: 7.4,
                kpIndex: 2.3,
                skyBandLabel: "Calmo",
                captureCount: 3
            )
        )
    }

    func getSnapshot(in context: Context, completion: @escaping (MorningBriefingEntry) -> Void) {
        let digest = DailyBriefingBuilder.cachedWidgetDigest()
        completion(MorningBriefingEntry(date: .now, digest: digest))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<MorningBriefingEntry>) -> Void) {
        let digest = DailyBriefingBuilder.cachedWidgetDigest()
        let entry = MorningBriefingEntry(date: .now, digest: digest)
        let next = Date.now.addingTimeInterval(1_800)
        completion(Timeline(entries: [entry], policy: .after(next)))
    }
}

struct MorningBriefingWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: MorningBriefingEntry

    private var hrvText: String? {
        entry.digest?.hrvMs.map { String(format: "%.0fms", $0) }
    }

    private var kpText: String? {
        entry.digest?.kpIndex.map { String(format: "Kp %.1f", $0) }
    }

    var body: some View {
        switch family {
        case .accessoryCircular:
            ZStack {
                AccessoryWidgetBackground()
                VStack(spacing: 1) {
                    Image(systemName: "sun.horizon.fill")
                        .font(.system(size: 13, weight: .semibold))
                    Text(hrvText ?? (entry.digest != nil ? "OK" : "Dia"))
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                }
            }
            .widgetURL(URL(string: "beagle://sintese"))

        case .accessoryRectangular:
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Image(systemName: "sun.horizon.fill")
                        .font(.system(size: 10, weight: .semibold))
                    Text("SÍNTESE MATINAL")
                        .font(.system(size: 9, weight: .semibold))
                        .tracking(0.4)
                }
                .foregroundStyle(.secondary)

                Text(entry.digest?.headline ?? "Toque para gerar seu briefing matinal")
                    .font(.system(size: 11, weight: .medium))
                    .lineLimit(2)
            }
            .widgetURL(URL(string: "beagle://sintese"))

        case .systemMedium:
            Link(destination: URL(string: "beagle://sintese")!) {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 6) {
                        Image(systemName: "sun.horizon.fill")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(BeagleTheme.postureWarm)
                        Text("Síntese Matinal · Astra")
                            .font(BeagleTheme.uiFont(size: 12, weight: .semibold))
                            .foregroundStyle(BeagleTheme.textPrimary)
                        Spacer()
                        if let hrvText {
                            Text(hrvText)
                                .font(BeagleTheme.dataFont(size: 10, weight: .semibold))
                                .foregroundStyle(BeagleTheme.truthObserved)
                        }
                        if let kpText {
                            Text(kpText)
                                .font(BeagleTheme.dataFont(size: 10))
                                .foregroundStyle(BeagleTheme.truthRemembered)
                        }
                    }

                    Text(entry.digest?.headline ?? "Toque para cruzar Fisioma (Apple Watch), Clima Espacial NOAA e Agenda das próximas 48h.")
                        .font(BeagleTheme.uiFont(size: 12))
                        .foregroundStyle(BeagleTheme.textSecondary)
                        .lineLimit(3)
                        .multilineTextAlignment(.leading)

                    Spacer(minLength: 0)
                }
                .padding(14)
            }

        default:
            Link(destination: URL(string: "beagle://sintese")!) {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Image(systemName: "sun.horizon.fill")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(BeagleTheme.postureWarm)
                        Spacer()
                        if let hrvText {
                            Text(hrvText)
                                .font(BeagleTheme.dataFont(size: 10, weight: .semibold))
                                .foregroundStyle(BeagleTheme.truthObserved)
                        }
                    }
                    Spacer(minLength: 0)
                    Text("Síntese")
                        .font(BeagleTheme.uiFont(size: 13, weight: .semibold))
                        .foregroundStyle(BeagleTheme.textPrimary)
                    Text(entry.digest?.headline ?? "Gerar resumo do dia")
                        .font(BeagleTheme.uiFont(size: 10))
                        .foregroundStyle(BeagleTheme.textSecondary)
                        .lineLimit(2)
                }
                .padding(12)
            }
        }
    }
}

// MARK: - Live Activity: Continuous Hands-Free Voice Session (Walkie-Talkie + Interactive Dynamic Island)

#if os(iOS)
struct CompanionVoiceSessionActivityConfiguration: Widget {
    private func accent(for phase: CompanionLiveVoicePhase) -> Color {
        switch phase {
        case .listening: return BeagleTheme.truthObserved
        case .thinking:  return BeagleTheme.truthRemembered
        case .speaking:  return BeagleTheme.postureWarm
        case .paused:    return BeagleTheme.textSecondary
        case .ended:     return BeagleTheme.textTertiary
        }
    }

    var body: some WidgetConfiguration {
        ActivityConfiguration(for: CompanionVoiceSessionAttributes.self) { context in
            let phase = context.state.phase
            let tint = accent(for: phase)

            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    Image(systemName: phase.symbolName)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(tint)
                    Text("Beagle · \(phase.titlePtBR)")
                        .font(BeagleTheme.uiFont(size: 13, weight: .semibold))
                        .foregroundStyle(BeagleTheme.textPrimary)
                    Spacer()
                    if context.state.turnCount > 0 {
                        Text("T\(context.state.turnCount)")
                            .font(BeagleTheme.dataFont(size: 10, weight: .semibold))
                            .foregroundStyle(BeagleTheme.textTertiary)
                    }
                    Text(context.state.voiceLabel)
                        .font(BeagleTheme.dataFont(size: 11, weight: .medium))
                        .foregroundStyle(tint)
                }

                Text(context.state.liveLine.isEmpty ? phase.defaultLinePtBR : context.state.liveLine)
                    .font(BeagleTheme.dataFont(size: 11))
                    .foregroundStyle(BeagleTheme.textSecondary)
                    .lineLimit(2)

                HStack(spacing: 8) {
                    if phase == .speaking {
                        Button(intent: InterruptSpeechLiveVoiceIntent()) {
                            Label("Falar agora", systemImage: "mic.fill")
                                .font(BeagleTheme.uiFont(size: 11, weight: .semibold))
                                .padding(.horizontal, 10)
                                .padding(.vertical, 5)
                                .background(BeagleTheme.truthObserved.opacity(0.22), in: Capsule())
                                .foregroundStyle(BeagleTheme.truthObserved)
                        }
                        .buttonStyle(.plain)
                    }

                    Button(intent: TogglePauseLiveVoiceIntent()) {
                        Label(
                            phase == .paused ? "Retomar" : "Pausar",
                            systemImage: phase == .paused ? "play.fill" : "pause.fill"
                        )
                        .font(BeagleTheme.uiFont(size: 11, weight: .semibold))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Color.white.opacity(0.10), in: Capsule())
                        .foregroundStyle(BeagleTheme.textPrimary)
                    }
                    .buttonStyle(.plain)

                    Spacer(minLength: 4)

                    Button(intent: EndLiveVoiceSessionIntent()) {
                        Label("Encerrar", systemImage: "xmark")
                            .font(BeagleTheme.uiFont(size: 11, weight: .semibold))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(BeagleTheme.stateError.opacity(0.20), in: Capsule())
                            .foregroundStyle(BeagleTheme.stateError)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(12)
            .activityBackgroundTint(BeagleTheme.surface1)
            .activitySystemActionForegroundColor(tint)
        } dynamicIsland: { context in
            let phase = context.state.phase
            let tint = accent(for: phase)

            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    HStack(spacing: 5) {
                        Image(systemName: phase.symbolName)
                            .foregroundStyle(tint)
                        Text(phase.titlePtBR)
                            .font(BeagleTheme.uiFont(size: 12, weight: .semibold))
                            .foregroundStyle(tint)
                    }
                }
                DynamicIslandExpandedRegion(.trailing) {
                    HStack(spacing: 4) {
                        if context.state.turnCount > 0 {
                            Text("T\(context.state.turnCount)")
                                .font(BeagleTheme.dataFont(size: 10))
                                .foregroundStyle(BeagleTheme.textTertiary)
                        }
                        Text(context.state.voiceLabel)
                            .font(BeagleTheme.dataFont(size: 11, weight: .medium))
                            .foregroundStyle(BeagleTheme.textSecondary)
                            .lineLimit(1)
                    }
                }
                DynamicIslandExpandedRegion(.center) {
                    Text(context.attributes.conversationTitle)
                        .font(BeagleTheme.dataFont(size: 12, weight: .medium))
                        .foregroundStyle(BeagleTheme.textPrimary)
                        .lineLimit(1)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(context.state.liveLine.isEmpty ? phase.defaultLinePtBR : context.state.liveLine)
                            .font(BeagleTheme.dataFont(size: 11))
                            .foregroundStyle(BeagleTheme.textSecondary)
                            .lineLimit(2)

                        HStack(spacing: 8) {
                            if phase == .speaking {
                                Button(intent: InterruptSpeechLiveVoiceIntent()) {
                                    Label("Cortar", systemImage: "mic.fill")
                                        .font(.system(size: 11, weight: .semibold))
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 5)
                                        .background(BeagleTheme.truthObserved.opacity(0.22), in: Capsule())
                                        .foregroundStyle(BeagleTheme.truthObserved)
                                }
                                .buttonStyle(.plain)
                            }

                            Button(intent: TogglePauseLiveVoiceIntent()) {
                                Label(
                                    phase == .paused ? "Retomar" : "Pausar",
                                    systemImage: phase == .paused ? "play.fill" : "pause.fill"
                                )
                                .font(.system(size: 11, weight: .semibold))
                                .padding(.horizontal, 10)
                                .padding(.vertical, 5)
                                .background(Color.white.opacity(0.12), in: Capsule())
                                .foregroundStyle(BeagleTheme.textPrimary)
                            }
                            .buttonStyle(.plain)

                            Spacer()

                            Button(intent: EndLiveVoiceSessionIntent()) {
                                Label("Encerrar", systemImage: "xmark")
                                    .font(.system(size: 11, weight: .semibold))
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 5)
                                    .background(BeagleTheme.stateError.opacity(0.22), in: Capsule())
                                    .foregroundStyle(BeagleTheme.stateError)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            } compactLeading: {
                Image(systemName: phase.symbolName)
                    .foregroundStyle(tint)
            } compactTrailing: {
                Text(phase.shortBadge)
                    .font(BeagleTheme.dataFont(size: 10, weight: .bold))
                    .foregroundStyle(tint)
            } minimal: {
                Image(systemName: phase.symbolName)
                    .foregroundStyle(tint)
            }
            .widgetURL(URL(string: "beagle://chat"))
        }
    }
}

// MARK: - Live Activity: Companion Turn

struct CompanionTurnActivityConfiguration: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: CompanionTurnAttributes.self) { context in
            // Lock screen / banner — warm, not technical (this IS the companion's voice, not an agent job).
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Image(systemName: context.state.status == "pensando" ? "sparkle" : "checkmark.circle.fill")
                        .foregroundStyle(BeagleTheme.truthObserved)
                    Text(context.attributes.conversationTitle)
                        .font(BeagleTheme.dataFont(size: 12, weight: .medium))
                        .foregroundStyle(BeagleTheme.textPrimary)
                        .lineLimit(1)
                    Spacer()
                    Text(context.state.voiceLabel)
                        .font(BeagleTheme.dataFont(size: 11))
                        .foregroundStyle(BeagleTheme.truthObserved)
                }
                Text(context.state.snippet.isEmpty ? "pensando…" : context.state.snippet)
                    .font(BeagleTheme.dataFont(size: 11))
                    .foregroundStyle(BeagleTheme.textSecondary)
                    .lineLimit(2)
            }
            .padding(12)
            .activityBackgroundTint(BeagleTheme.surface1)
            .activitySystemActionForegroundColor(BeagleTheme.truthObserved)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Image(systemName: context.state.status == "pensando" ? "sparkle" : "checkmark.circle.fill")
                        .foregroundStyle(BeagleTheme.truthObserved)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text(context.state.voiceLabel)
                        .font(BeagleTheme.dataFont(size: 11))
                        .foregroundStyle(BeagleTheme.truthObserved)
                }
                DynamicIslandExpandedRegion(.center) {
                    Text(context.attributes.conversationTitle)
                        .font(BeagleTheme.dataFont(size: 12, weight: .medium))
                        .lineLimit(1)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    Text(context.state.snippet.isEmpty ? "pensando…" : context.state.snippet)
                        .font(BeagleTheme.dataFont(size: 10))
                        .foregroundStyle(BeagleTheme.textSecondary)
                        .lineLimit(2)
                }
            } compactLeading: {
                Image(systemName: context.state.status == "pensando" ? "sparkle" : "checkmark.circle.fill")
            } compactTrailing: {
                Text(context.state.voiceLabel.prefix(4))
                    .font(BeagleTheme.dataFont(size: 10))
            } minimal: {
                Image(systemName: context.state.status == "pensando" ? "sparkle" : "checkmark.circle.fill")
                    .foregroundStyle(BeagleTheme.truthObserved)
            }
        }
    }
}

// MARK: - Live Activity: Agent Session

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
            let done = context.state.isCompleted == true
            let accent = done ? BeagleTheme.truthObserved : BeagleTheme.truthRemembered
            VStack(alignment: .leading, spacing: 7) {
                HStack(spacing: 6) {
                    Image(systemName: done ? "checkmark.seal.fill" : "sparkle.magnifyingglass")
                        .foregroundStyle(accent)
                    Text(context.attributes.campaignName)
                        .font(BeagleTheme.dataFont(size: 12, weight: .semibold))
                        .foregroundStyle(BeagleTheme.textPrimary)
                        .lineLimit(1)
                    Spacer()
                    if done {
                        Text("Concluído")
                            .font(BeagleTheme.dataFont(size: 10, weight: .semibold))
                            .foregroundStyle(BeagleTheme.truthObserved)
                    } else if let lens = context.state.activeLens, !lens.isEmpty {
                        Text(lens)
                            .font(BeagleTheme.dataFont(size: 10, weight: .medium))
                            .foregroundStyle(BeagleTheme.truthObserved)
                            .lineLimit(1)
                    } else {
                        Text("ETA \(max(1, context.state.etaSeconds / 60))m")
                            .font(BeagleTheme.dataFont(size: 10))
                            .foregroundStyle(BeagleTheme.truthObserved)
                    }
                }
                ProgressView(
                    value: Double(context.state.stepCurrent),
                    total: Double(max(1, context.state.stepTotal))
                )
                .tint(accent)

                if let snippet = context.state.summarySnippet, !snippet.isEmpty {
                    Text(snippet)
                        .font(BeagleTheme.dataFont(size: 11))
                        .foregroundStyle(BeagleTheme.textSecondary)
                        .lineLimit(2)
                }

                HStack {
                    Text("Etapa \(context.state.stepCurrent)/\(context.state.stepTotal)")
                        .font(BeagleTheme.dataFont(size: 10))
                        .foregroundStyle(BeagleTheme.textTertiary)
                    Spacer()
                    Text(done ? "Abrir síntese no Modo Fundo" : "Modo Fundo ao vivo")
                        .font(BeagleTheme.dataFont(size: 10))
                        .foregroundStyle(BeagleTheme.textTertiary)
                }
            }
            .padding(12)
            .activityBackgroundTint(BeagleTheme.surface1)
            .widgetURL(URL(string: "beagle://fundo"))
        } dynamicIsland: { context in
            let done = context.state.isCompleted == true
            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    HStack(spacing: 4) {
                        Image(systemName: done ? "checkmark.seal.fill" : "sparkle.magnifyingglass")
                            .foregroundStyle(BeagleTheme.truthObserved)
                        Text("Modo Fundo")
                            .font(BeagleTheme.dataFont(size: 11, weight: .semibold))
                    }
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text(done ? "Concluído" : (context.state.activeLens ?? "\(context.state.stepCurrent)/\(context.state.stepTotal)"))
                        .font(BeagleTheme.dataFont(size: 10, weight: .medium))
                        .foregroundStyle(BeagleTheme.truthObserved)
                        .lineLimit(1)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(alignment: .leading, spacing: 5) {
                        Text(context.attributes.campaignName)
                            .font(BeagleTheme.dataFont(size: 11, weight: .medium))
                            .lineLimit(1)
                        ProgressView(
                            value: Double(context.state.stepCurrent),
                            total: Double(max(1, context.state.stepTotal))
                        )
                        .tint(BeagleTheme.truthObserved)
                        if let snippet = context.state.summarySnippet, !snippet.isEmpty {
                            Text(snippet)
                                .font(BeagleTheme.dataFont(size: 10))
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                        }
                    }
                }
            } compactLeading: {
                Image(systemName: done ? "checkmark.seal.fill" : "sparkle.magnifyingglass")
                    .foregroundStyle(BeagleTheme.truthObserved)
            } compactTrailing: {
                Text(done ? "OK" : "\(context.state.stepCurrent)/\(context.state.stepTotal)")
                    .font(BeagleTheme.dataFont(size: 10, weight: .semibold))
                    .foregroundStyle(BeagleTheme.truthObserved)
            } minimal: {
                Image(systemName: done ? "checkmark.seal.fill" : "sparkle.magnifyingglass")
                    .foregroundStyle(BeagleTheme.truthObserved)
            }
            .widgetURL(URL(string: "beagle://fundo"))
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
