//
//  FlowAndQuickActionWidgets.swift
//  BeagleWidgets
//
//  Lock Screen & Home Screen widgets for Flow State, Quick Capture,
//  Companion Voice Launcher, and iOS Control Center / Lock Screen Controls.
//

import AppIntents
import WidgetKit
import SwiftUI
import BeagleCore

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

// MARK: - Control Center & Lock Screen Controls (iOS only)

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
