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
                    #if canImport(WatchConnectivity)
                    WatchExocortexBridge.shared.activate()
                    #endif
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
            // PRIMEIRA aba de propósito: levantar o pulso tem que cair em falar
            // com ele, não em saúde de nó de cluster. O relógio estava no pulso
            // dele durante o plantão inteiro sabendo só falar de máquina.
            FalarView()
                .tabItem { Label("Falar", systemImage: "bubble.left.fill") }

            FlowView()
                .tabItem { Label("Flow", systemImage: "heart.fill") }

            PulseView()
                .tabItem { Label("Pulse", systemImage: "waveform.path") }

            ClusterHealthView()
                .tabItem { Label("Cluster", systemImage: "server.rack") }

            WatchDashboardView()
                .tabItem { Label("Dashboard", systemImage: "gauge.medium") }

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
/// The thought flows into cluster-canonical GraphRAG++ memory.
struct QuickCaptureView: View {
    @Environment(HRVMonitor.self) private var hrv
    @State private var draftText = ""
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

                    Text("Cluster memory queued")
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

                    TextField("Dictate thought", text: $draftText)
                        .font(.system(size: 12))
                        .textInputAutocapitalization(.sentences)

                    Button {
                        submitCapture()
                    } label: {
                        Label("Speak", systemImage: "mic.fill")
                    }
                    .buttonStyle(.bordered)
                    .tint(BeagleTheme.truthRemembered)
                    .disabled(draftText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
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

    private func submitCapture() {
        let text = draftText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        capturedText = text
        isCaptured.toggle()
        draftText = ""
        let bodySummary = "watch_hrv=\(Int(hrv.latestHRV.rounded()))ms flow_state=\(hrv.flowState.rawValue)"
        Task {
            #if canImport(WatchConnectivity)
            let sentToPhone = await WatchExocortexBridge.shared.sendCapture(
                WatchExocortexCapture(text: text, bodySummary: bodySummary)
            )
            if !sentToPhone {
                _ = await BeagleClient.shared.captureThought(text: "\(text)\n\n[\(bodySummary)]", source: "apple-watch")
            }
            #else
            _ = await BeagleClient.shared.captureThought(text: "\(text)\n\n[\(bodySummary)]", source: "apple-watch")
            #endif
        }
    }
}

// MARK: - Cluster Health View

/// Per-node cluster health. Each node is a colored dot — green is healthy.
/// One glance tells you if the sovereign infrastructure is intact.
struct ClusterHealthView: View {
    @Environment(CatalogStore.self) private var catalog
    @State private var store: ProjectStore?
    @State private var nodes: [ClusterNode] = []

    var body: some View {
        ScrollView {
            VStack(spacing: 10) {
                Text("CLUSTER")
                    .font(.system(size: 9, weight: .semibold))
                    .tracking(1)
                    .foregroundStyle(.tertiary)

                if nodes.isEmpty {
                    VStack(spacing: 6) {
                        Image(systemName: "server.rack")
                            .font(.system(size: 24))
                            .foregroundStyle(.tertiary)
                        Text("Loading...")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                    .padding(.top, 8)
                } else {
                    // Summary line
                    let healthy = nodes.filter { $0.healthy == true }.count
                    HStack(spacing: 4) {
                        Text("\(healthy)/\(nodes.count)")
                            .font(.system(size: 22, weight: .bold, design: .rounded))
                            .foregroundStyle(healthy == nodes.count ? BeagleTheme.truthObserved : BeagleTheme.postureWarm)
                        Text("healthy")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }

                    // Node grid
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 38))], spacing: 8) {
                        ForEach(nodes) { node in
                            VStack(spacing: 3) {
                                Circle()
                                    .fill(node.healthy == true ? BeagleTheme.truthObserved : BeagleTheme.stateError)
                                    .frame(width: 12, height: 12)
                                    .shadow(
                                        color: (node.healthy == true ? BeagleTheme.truthObserved : BeagleTheme.stateError).opacity(0.4),
                                        radius: 4
                                    )

                                Text(node.hostname ?? node.name ?? "?")
                                    .font(.system(size: 8))
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                        }
                    }
                    .padding(.horizontal, 4)

                    // Role breakdown
                    let roles = Dictionary(grouping: nodes, by: { $0.role ?? "unknown" })
                    ForEach(Array(roles.keys.sorted()), id: \.self) { role in
                        let count = roles[role]?.count ?? 0
                        let healthyInRole = roles[role]?.filter { $0.healthy == true }.count ?? 0
                        HStack(spacing: 4) {
                            Text(role)
                                .font(.system(size: 10, weight: .medium))
                                .foregroundStyle(.secondary)
                            Spacer()
                            Text("\(healthyInRole)/\(count)")
                                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                                .foregroundStyle(healthyInRole == count ? BeagleTheme.truthObserved : BeagleTheme.postureWarm)
                        }
                        .padding(.horizontal, 8)
                    }
                }
            }
        }
        .containerBackground(for: .tabView) {
            let allHealthy = !nodes.isEmpty && nodes.allSatisfy { $0.healthy == true }
            LinearGradient(
                colors: [
                    (allHealthy ? BeagleTheme.truthObserved : BeagleTheme.postureWarm).opacity(nodes.isEmpty ? 0.02 : 0.08),
                    Color(white: 0.03)
                ],
                startPoint: .top, endPoint: .bottom
            )
            .ignoresSafeArea()
        }
        .task {
            let slug = catalog.primaryProject?.projectSlug ?? "sounio"
            let projectStore = ProjectStore(slug: slug)
            store = projectStore
            await projectStore.refresh()
            nodes = projectStore.clusterSummary.value?.nodes ?? []
        }
    }
}

// MARK: - Watch Dashboard View

/// Mini operational dashboard — jobs, inference, agent sessions.
/// Everything you need to know at a glance while away from the desk.
struct WatchDashboardView: View {
    @Environment(CatalogStore.self) private var catalog
    @State private var store: ProjectStore?
    @State private var cognitive = CognitiveStore()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                Text("DASHBOARD")
                    .font(.system(size: 9, weight: .semibold))
                    .tracking(1)
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity)

                // Active jobs
                dashboardRow(
                    icon: "flask.fill",
                    label: "Jobs",
                    value: "\(cognitive.activeJobs.filter(\.isRunning).count) running",
                    color: cognitive.activeJobs.contains(where: \.isRunning) ? BeagleTheme.postureWarm : BeagleTheme.textTertiary
                )

                // Inference
                if let runtime = store?.inference.value {
                    dashboardRow(
                        icon: "cpu",
                        label: "Inference",
                        value: runtime.reachable == true ? "\(runtime.models?.count ?? 0) models" : "offline",
                        color: runtime.reachable == true ? BeagleTheme.truthObserved : BeagleTheme.textTertiary
                    )
                }

                // Thoughts today
                dashboardRow(
                    icon: "leaf.fill",
                    label: "Thoughts",
                    value: "\(cognitive.recentThoughts.count) captured",
                    color: cognitive.recentThoughts.isEmpty ? BeagleTheme.textTertiary : BeagleTheme.truthObserved
                )

                // Agent sessions
                if let sessions = cognitive.state.value?.agentSessions {
                    let running = sessions.filter(\.isRunning)
                    dashboardRow(
                        icon: "sparkles",
                        label: "Agents",
                        value: running.isEmpty ? "none active" : "\(running.count) live",
                        color: running.isEmpty ? BeagleTheme.textTertiary : BeagleTheme.truthObserved
                    )
                }

                // Primary project branch
                if let project = catalog.primaryProject, let branch = project.branch {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Branch")
                            .font(.system(size: 9, weight: .medium))
                            .foregroundStyle(.tertiary)
                        Text(branch)
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    .padding(.horizontal, 4)
                    .padding(.top, 4)
                }
            }
            .padding(.horizontal, 4)
        }
        .containerBackground(for: .tabView) {
            LinearGradient(
                colors: [
                    BeagleTheme.truthRemembered.opacity(0.06),
                    Color(white: 0.03)
                ],
                startPoint: .top, endPoint: .bottom
            )
            .ignoresSafeArea()
        }
        .task {
            let slug = catalog.primaryProject?.projectSlug ?? "sounio"
            let projectStore = ProjectStore(slug: slug)
            store = projectStore
            async let p: () = projectStore.refresh()
            async let c: () = cognitive.refresh()
            _ = await (p, c)
        }
    }

    private func dashboardRow(icon: String, label: String, value: String, color: Color) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 11))
                .foregroundStyle(color)
                .frame(width: 16)

            Text(label)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)

            Spacer()

            Text(value)
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundStyle(color)
        }
        .padding(.horizontal, 4)
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
