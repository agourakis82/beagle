//
//  BeagleWatchApp.swift
//  BeagleWatch
//
//  watchOS 26 companion — your exocortex on the wrist.
//
//  Not a dashboard. A gentle tap when something matters.
//  A quick glance to know your platform is alive.
//  A voice capture that flows into your thinking.
//
//  Screens:
//   - Flow: HRV + cognitive state (the core)
//   - Pulse: cluster health at a glance
//   - Capture: quick voice thought into the exocortex
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
            FlowView()
                .tabItem { Label("Flow", systemImage: "heart.fill") }

            PulseView()
                .tabItem { Label("Pulse", systemImage: "waveform.path") }

            QuickCaptureView()
                .tabItem { Label("Capture", systemImage: "thought.bubble") }
        }
    }
}

// MARK: - Flow View (the emotional core)

/// Your cognitive state. How are you feeling? The watch knows.
struct FlowView: View {
    @Environment(HRVMonitor.self) private var hrv

    var body: some View {
        VStack(spacing: 12) {
            // Circadian-aware label
            Text(flowGreeting)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
                .tracking(0.5)

            // Hero HRV number
            Text(String(format: "%.0f", hrv.latestHRV))
                .font(.system(size: 44, weight: .bold, design: .rounded))
                .foregroundStyle(flowColor)

            Text("ms")
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
                .offset(y: -4)

            // Flow state badge
            Text(hrv.flowState.rawValue.uppercased())
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(flowColor)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(
                    Capsule()
                        .fill(flowColor.opacity(0.15))
                )

            // Gentle guidance
            Text(flowMessage)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 8)
        }
        .containerBackground(for: .tabView) {
            flowGradient
        }
    }

    private var flowColor: Color {
        switch hrv.flowState {
        case .flow:    return BeagleTheme.truthObserved
        case .normal:  return BeagleTheme.textData
        case .stress:  return BeagleTheme.postureWarm
        case .unknown: return BeagleTheme.textTertiary
        }
    }

    private var flowGreeting: String {
        let hour = Calendar.current.component(.hour, from: Date())
        switch hour {
        case 5..<10:  return "MORNING"
        case 10..<17: return "FOCUS"
        case 17..<22: return "EVENING"
        default:      return "REST"
        }
    }

    private var flowMessage: String {
        switch hrv.flowState {
        case .flow:    return "Deep flow. Protect this state."
        case .normal:  return "Steady. Good for thinking."
        case .stress:  return "Elevated stress. Take a breath."
        case .unknown: return "Measuring..."
        }
    }

    private var flowGradient: some View {
        LinearGradient(
            colors: [
                flowColor.opacity(0.15),
                Color(white: 0.05),
                Color(white: 0.03)
            ],
            startPoint: .top, endPoint: .bottom
        )
        .ignoresSafeArea()
    }
}

// MARK: - Pulse View (cluster glance)

/// Your platform's heartbeat. One glance tells you everything is OK.
struct PulseView: View {
    @Environment(CatalogStore.self) private var catalog

    var body: some View {
        VStack(spacing: 10) {
            // Truth indicator — the single most important signal
            TruthBadge(catalog.executive.mode)

            let counts = catalog.postureCounts

            // Posture counts with warm styling
            VStack(spacing: 6) {
                postureRow(count: counts.alwaysOn, label: "alive", color: BeagleTheme.postureOn, pulse: true)
                postureRow(count: counts.warm, label: "warm", color: BeagleTheme.postureWarm, pulse: false)
                postureRow(count: counts.cold, label: "resting", color: BeagleTheme.postureCold, pulse: false)
            }

            Text("\(counts.totalProjects) surfaces")
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)

            Button {
                Task { await catalog.refresh() }
            } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 12))
            }
            .buttonStyle(.bordered)
            .controlSize(.mini)
            .tint(BeagleTheme.truthObserved)
        }
        .containerBackground(for: .tabView) {
            LinearGradient(
                colors: [
                    BeagleTheme.truthObserved.opacity(catalog.executive.mode == .observed ? 0.1 : 0.02),
                    Color(white: 0.03)
                ],
                startPoint: .top, endPoint: .bottom
            )
            .ignoresSafeArea()
        }
    }

    private func postureRow(count: Int, label: String, color: Color, pulse: Bool) -> some View {
        HStack(spacing: 6) {
            Circle()
                .fill(color)
                .frame(width: 6, height: 6)
                .shadow(color: pulse ? color.opacity(0.4) : .clear, radius: 3)

            Text("\(count)")
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .foregroundStyle(color)

            Text(label)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)

            Spacer()
        }
    }
}

// MARK: - Quick Capture View

/// Capture a thought from your wrist. One tap, speak, done.
/// The thought flows into the exocortex — HERMES refines it later.
struct QuickCaptureView: View {
    @State private var capturedText: String?
    @State private var isCaptured = false

    var body: some View {
        VStack(spacing: 12) {
            if let text = capturedText {
                // Captured confirmation
                VStack(spacing: 8) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 28))
                        .foregroundStyle(BeagleTheme.truthObserved)

                    Text("Captured")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(BeagleTheme.truthObserved)

                    Text(text)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(3)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 8)

                    Text("HERMES will refine")
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                }
                .transition(.opacity.combined(with: .scale(scale: 0.9)))
            } else {
                // Ready to capture
                VStack(spacing: 10) {
                    Image(systemName: "thought.bubble")
                        .font(.system(size: 28))
                        .foregroundStyle(BeagleTheme.truthRemembered)

                    Text("Quick Thought")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.primary)

                    Text("Tap to dictate. Your thought flows into the exocortex.")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 8)

                    // Dictation button (system TextFieldLink for watchOS dictation)
                    Button {
                        // On watchOS 26, use system dictation
                        // The captured text would be sent to BeagleClient
                        capturedText = "Thought captured via Watch"
                        Task {
                            _ = await BeagleClient.shared.captureThought(
                                text: capturedText ?? "",
                                source: "apple-watch"
                            )
                        }
                    } label: {
                        Label("Speak", systemImage: "mic.fill")
                    }
                    .buttonStyle(.bordered)
                    .tint(BeagleTheme.truthRemembered)
                }
            }
        }
        .sensoryFeedback(.success, trigger: isCaptured)
        .containerBackground(for: .tabView) {
            LinearGradient(
                colors: [
                    (capturedText != nil ? BeagleTheme.truthObserved : BeagleTheme.truthRemembered).opacity(0.08),
                    Color(white: 0.03)
                ],
                startPoint: .top, endPoint: .bottom
            )
            .ignoresSafeArea()
        }
    }
}

// MARK: - HRV Monitor

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
