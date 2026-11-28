//
//  MorningBriefingWidget.swift
//  BeagleWidgets
//
//  Morning briefing widget for Lock Screen and Home Screen.
//

import WidgetKit
import SwiftUI
import BeagleCore

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
