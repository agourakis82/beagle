//
//  BeagleCockpitApp.swift
//  BeagleCockpit
//
//  App entry point for iOS 26, iPadOS 26, macOS 26.
//  Native Apple client for the sovereign supercomputing cockpit.
//
//  Deep links:  beagle://project/{slug}
//               beagle://project/{slug}/agent/{kind}
//  Handoff:     dev.sounio.cockpit.viewProject (slug in userInfo)
//

import SwiftUI
import SwiftData
import BeagleCore
import BeagleWorkbenchKit
#if os(iOS)
import UIKit
import BackgroundTasks
#endif

/// Identifier for the overnight dream-consolidation background task.
/// Must match the `BGTaskSchedulerPermittedIdentifiers` Info.plist entry.
let beagleDreamTaskIdentifier = "dev.sounio.cockpit.dream"

@main
struct BeagleCockpitApp: App {
    @State private var catalog = CatalogStore()
    @State private var cognitive = CognitiveStore()
    @State private var physio = PhysioStore()
    @State private var hpc = HPCStore()
    @State private var navigationPath = NavigationPath()
    @State private var bootError: String?
    @State private var launchOverrides = LaunchOverrides.current
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false

    init() {
        #if os(iOS)
        Self.configureShellChrome()
        #endif
    }

    var body: some Scene {
        WindowGroup {
            if hasCompletedOnboarding {
                RootView(path: $navigationPath, bootError: $bootError, launchOverrides: launchOverrides)
                .environment(catalog)
                .environment(cognitive)
                .environment(physio)
                .environment(hpc)
                .modelContainer(for: [
                    PersistedThought.self,
                    PersistedMessage.self,
                    PersistedDeepSession.self,
                    PersistedExocortexHomeSnapshot.self,
                    PersistedAssistedImportOutbox.self,
                ])
                .onOpenURL { url in
                    handleDeepLink(url)
                }
                .onContinueUserActivity("dev.sounio.cockpit.viewProject") { activity in
                    if let slug = activity.userInfo?["slug"] as? String {
                        navigateToProject(slug)
                    }
                }
                .onContinueUserActivity("dev.sounio.cockpit.viewAgent") { activity in
                    if let slug = activity.userInfo?["slug"] as? String {
                        navigateToProject(slug)
                    }
                }
                .preferredColorScheme(.dark)
                .tint(BeagleTheme.truthObserved)
            } else {
                OnboardingView(isComplete: $hasCompletedOnboarding)
                    .preferredColorScheme(.dark)
            }
        }
        #if os(iOS)
        .backgroundTask(.appRefresh(beagleDreamTaskIdentifier)) {
            await runDreamConsolidation()
            await scheduleDreamConsolidation()
        }
        #endif
        #if os(macOS)
        .windowStyle(.automatic)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("Refresh Catalog") {
                    Task { await catalog.refresh() }
                }
                .keyboardShortcut("r", modifiers: .command)
            }
        }
        #endif

        #if os(macOS)
        MenuBarExtra("Beagle Cockpit", systemImage: "sparkle") {
            MenuBarContent()
                .environment(catalog)
        }
        .menuBarExtraStyle(.window)
        #endif
    }

    // MARK: - Dream consolidation (BGTask)

    #if os(iOS)
    /// Run an overnight dream-synthesis pass from the background task.
    /// Reads the latest thoughts/posture from the app stores (MainActor) and
    /// recombines them via the DreamSynthesisEngine.
    @MainActor
    private func runDreamConsolidation() async {
        guard DreamSynthesisEngine.shared.shouldDreamAgain else { return }
        await cognitive.refresh()
        await physio.refresh()
        await DreamSynthesisEngine.shared.synthesize(
            thoughts: cognitive.recentThoughts,
            cognitivePosture: physio.cognitivePosture
        )
    }

    /// Submit the next dream-consolidation background refresh request.
    /// Earliest fire ~8h out so it lands during an overnight/idle window.
    private func scheduleDreamConsolidation() async {
        let request = BGAppRefreshTaskRequest(identifier: beagleDreamTaskIdentifier)
        request.earliestBeginDate = Date(timeIntervalSinceNow: 8 * 3600)
        do {
            try BGTaskScheduler.shared.submit(request)
        } catch {
            print("[BeagleCockpit] dream BGTask submit failed: \(error)")
        }
    }
    #endif

    // MARK: - Deep link handling

    private func handleDeepLink(_ url: URL) {
        // beagle://project/{slug}
        // beagle://project/{slug}/agent/{kind}
        guard url.scheme == "beagle" else { return }
        let components = url.pathComponents.filter { $0 != "/" }

        if components.count >= 2, components[0] == "project" {
            let slug = components[1]
            navigateToProject(slug)
        }
    }

    // bootstrap() moved to RootView where modelContext is properly available

    private func navigateToProject(_ slug: String) {
        // Find or create the project to navigate to
        if let project = catalog.projects.first(where: { $0.projectSlug == slug }) {
            navigationPath = NavigationPath()
            navigationPath.append(project)
        }
    }
}

#if os(iOS)
private extension BeagleCockpitApp {
    static func configureShellChrome() {
        let tabAppearance = UITabBarAppearance()
        tabAppearance.configureWithTransparentBackground()
        tabAppearance.backgroundEffect = UIBlurEffect(style: .systemUltraThinMaterialDark)
        tabAppearance.backgroundColor = UIColor(BeagleTheme.surface0.opacity(0.88))
        tabAppearance.shadowColor = UIColor(BeagleTheme.hairline)

        let selected = UIColor(BeagleTheme.truthObserved)
        let normal = UIColor(BeagleTheme.textSecondary)

        [tabAppearance.stackedLayoutAppearance,
         tabAppearance.inlineLayoutAppearance,
         tabAppearance.compactInlineLayoutAppearance].forEach { item in
            item.normal.iconColor = normal
            item.normal.titleTextAttributes = [.foregroundColor: normal]
            item.selected.iconColor = selected
            item.selected.titleTextAttributes = [.foregroundColor: selected]
        }

        UITabBar.appearance().standardAppearance = tabAppearance
        UITabBar.appearance().scrollEdgeAppearance = tabAppearance

        let navAppearance = UINavigationBarAppearance()
        navAppearance.configureWithTransparentBackground()
        navAppearance.backgroundColor = .clear
        navAppearance.largeTitleTextAttributes = [.foregroundColor: UIColor(BeagleTheme.textPrimary)]
        navAppearance.titleTextAttributes = [.foregroundColor: UIColor(BeagleTheme.textPrimary)]

        UINavigationBar.appearance().standardAppearance = navAppearance
        UINavigationBar.appearance().scrollEdgeAppearance = navAppearance
        UINavigationBar.appearance().compactAppearance = navAppearance
        UINavigationBar.appearance().tintColor = selected
    }
}
#endif

// MARK: - Root navigation shell

struct RootView: View {
    @Binding var path: NavigationPath
    @Binding var bootError: String?
    let launchOverrides: LaunchOverrides
    @Environment(CatalogStore.self) private var catalog
    @Environment(CognitiveStore.self) private var cognitive
    @Environment(PhysioStore.self) private var physio
    @AppStorage("selectedTab") private var persistedSelectedTab = 0
    @AppStorage("lastAgentKind") private var lastAgentKindRaw = "claude-code"
    @AppStorage("lastAgentObjective") private var lastAgentObjective = ""
    @AppStorage("lastAgentObjectiveProjectSlug") private var lastAgentObjectiveProjectSlug = ""
    @AppStorage("pinnedLaneQuestionsJSON") private var pinnedLaneQuestionsJSON = "{}"
    @AppStorage("cachedLaneResultsJSON") private var cachedLaneResultsJSON = "[]"
    @State private var selectedTab = 0
    @State private var hasInitializedTabSelection = false
    @State private var showCognitiveState = false
    @Environment(\.horizontalSizeClass) private var sizeClass
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        Group {
            if sizeClass == .regular {
                iPadLayout
            } else {
                iPhoneLayout
            }
        }
        .task {
            initializeTabSelectionIfNeeded()
            await bootstrap()
        }
        .onChange(of: selectedTab) { _, newValue in
            persistedSelectedTab = newValue
        }
        .onChange(of: scenePhase) { _, newPhase in
            switch newPhase {
            case .active:
                // Returning to foreground (connectivity likely restored):
                // re-fetch credentials and auto-drain any queued captures/messages.
                Task {
                    _ = await BeagleClient.shared.ensureAuth()
                    await cognitive.drainSharedThoughtQueue()
                    await cognitive.drainAssistedImportOutbox()
                }
            case .background:
                // Queue the overnight dream-consolidation background task.
                #if os(iOS)
                let request = BGAppRefreshTaskRequest(identifier: beagleDreamTaskIdentifier)
                request.earliestBeginDate = Date(timeIntervalSinceNow: 8 * 3600)
                try? BGTaskScheduler.shared.submit(request)
                #endif
            default:
                break
            }
        }
    }

    // MARK: - Tab selection (launch override > persisted > default)

    private func initializeTabSelectionIfNeeded() {
        guard !hasInitializedTabSelection else { return }
        hasInitializedTabSelection = true
        selectedTab = launchOverrides.selectedTab ?? persistedSelectedTab
    }

    // MARK: - Bootstrap (runs inside model container scope)

    private func bootstrap() async {
        cognitive.modelContext = modelContext
        cognitive.physioStore = physio
        #if canImport(WatchConnectivity)
        WatchExocortexBridge.shared.activate()
        #endif
        SemanticSearchEngine.shared.warmup()
        cognitive.loadPersistedThoughts()
        DreamSynthesisEngine.shared.loadPersistedInsights()
        cognitive.activeProjectSlug = launchOverrides.projectSlug ?? cognitive.activeProjectSlug ?? "sounio"

        let authReady = await BeagleClient.shared.ensureAuth()
        startPhysiomeRealtimeSync()
        async let catalogTask: () = catalog.refresh()
        async let cognitiveTask: () = cognitive.refresh()
        async let physioTask: () = physio.refresh()
        async let sharedQueueTask: () = cognitive.drainSharedThoughtQueue()
        async let outboxDrainTask: Int = cognitive.drainAssistedImportOutbox()
        async let warmTask: () = FoundationModelsAgent.shared.prewarm()
        _ = await (catalogTask, cognitiveTask, physioTask, sharedQueueTask, outboxDrainTask, warmTask)
        cognitive.activeProjectSlug =
            launchOverrides.projectSlug
            ?? cognitive.activeProjectSlug
            ?? catalog.primaryProject?.projectSlug
            ?? "sounio"
        if catalog.executive.mode == .stale {
            if !authReady {
                let authStatus = await BeagleClient.shared.authBootstrapStatus()
                bootError = authStatus.error ?? "Could not fetch beagle-core credentials."
            } else {
                bootError = "Could not reach cockpit over the public gateway or private fallback path."
            }
        }
    }

    // MARK: - Physiome real-time ingest

    /// Activate the sovereign real-time Physiome pipeline. Detached so HealthKit
    /// authorization + background-delivery registration never block the cockpit boot.
    ///  1. recover any samples queued (and persisted to disk) in a prior session,
    ///  2. authorize + register HKObserverQuery/background-delivery for every type,
    ///  3. catch up incrementally via persisted per-type anchors (no re-send, no loss),
    ///  4. start WeatherKit + barometric/location streaming (temp, pressure, …).
    /// Idempotent by HKObject.uuid — safe to run on every launch.
    private func startPhysiomeRealtimeSync() {
        // Demo/screenshot mode: never trigger the system HealthKit auth sheet — it would
        // cover the chat UI being previewed. Real launches authorize as normal.
        let args = ProcessInfo.processInfo.arguments
        if args.contains("--demo") || args.contains("--demo-chat") { return }
        Task.detached(priority: .utility) {
            let uploader = PhysiomeUploader.shared
            await uploader.recoverAndFlush()
            do {
                try await HealthSyncEngine.shared.requestAuthorization()
                await HealthSyncEngine.shared.enableBackgroundDelivery(uploader: uploader)
                await HealthSyncEngine.shared.catchUp(uploader: uploader)
            } catch {
                print("[physiome] health sync init failed: \(error)")
            }
            await WeatherSyncEngine.shared.start(uploader: uploader)
            #if os(iOS)
            // Device barometer → exact local atmospheric pressure (indoor, no network).
            await BaroSyncEngine.shared.start(uploader: uploader)
            #endif
        }
    }

    // MARK: - iPhone Layout (4 tabs)

    // 2026-06-28: simplified to companion-only per design doc IA
    // ("Companion-pure + Trabalho drawer"). The other tabs (Fleet/Capture/Deep/
    // Agents/Recall) were triggering an AttributeGraph cycle in their bodies —
    // even when offscreen — causing 12M cycles/22s and SIGKILL. The TabView
    // returns when one or more of those tabs' cycles are fixed and we
    // re-introduce them behind a proper drawer (per the IA design doc).
    private var iPhoneLayout: some View {
        BeagleSurface(bootError: $bootError)
    }

    // MARK: - iPad Layout (sidebar + detail)

    enum SidebarItem: String, CaseIterable, Identifiable {
        case mind     = "Mind"
        case fleet    = "Fleet"
        case capture  = "Capture"
        case deep     = "Go Deep"
        case work     = "Work"
        case recall   = "Recall"
        case settings = "Settings"

        var id: String { rawValue }

        var icon: String {
            switch self {
            case .mind:     return "brain.head.profile"
            case .capture:  return "mic.fill"
            case .deep:     return "sparkles"
            case .work:     return "apple.terminal"
            case .recall:   return "sparkle.magnifyingglass"
            case .fleet:    return "terminal"
            case .settings: return "gearshape"
            }
        }
    }

    @State private var sidebarSelection: SidebarItem? = .mind

    private var iPadLayout: some View {
        NavigationSplitView {
            List(SidebarItem.allCases, selection: $sidebarSelection) { item in
                Label(item.rawValue, systemImage: item.icon)
                    .foregroundStyle(BeagleTheme.textPrimary)
            }
            .navigationTitle("Beagle")
            .listStyle(.sidebar)
        } detail: {
            NavigationStack(path: $path) {
                Group {
                    switch sidebarSelection {
                    case .mind:
                        SpatialDeskMissionControlView()
                    case .capture:
                        ThoughtCaptureView()
                    case .deep:
                        DeepExplorationView()
                            .navigationDestination(for: String.self) { _ in
                                TriadReviewView()
                            }
                    case .work:
                        WorkView(bootError: $bootError)
                    case .recall:
                        CognitiveRecallView()
                    case .fleet:
                        FleetTerminalsView()
                    case .settings:
                        ModelSettingsView()
                    case nil:
                        SpatialDeskMissionControlView()
                    }
                }
            }
        }
        .tint(BeagleTheme.truthObserved)
        .sheet(isPresented: $showCognitiveState) {
            NavigationStack {
                CognitiveStateView()
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Done") { showCognitiveState = false }
                        }
                    }
            }
        }
    }

    private func authErrorBanner(_ error: String) -> some View {
        GlassPanel(elevation: .raised, truth: .stale) {
            HStack(spacing: BeagleSpacing.xs) {
                Image(systemName: "wifi.exclamationmark")
                    .font(.system(size: 14))
                    .foregroundStyle(BeagleTheme.stateError)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Cannot reach cockpit")
                        .font(BeagleFont.footnote.font)
                        .fontWeight(.medium)
                        .foregroundStyle(BeagleTheme.textPrimary)
                    Text(error)
                        .font(BeagleFont.caption.font)
                        .foregroundStyle(BeagleTheme.textSecondary)
                        .lineLimit(2)
                }
                Spacer()
                Button {
                    Task {
                        bootError = nil
                        await catalog.refresh()
                        if catalog.executive.mode == .stale {
                            bootError = error
                        }
                    }
                } label: {
                    Label("Retry", systemImage: "arrow.clockwise")
                }
                .buttonStyle(SecondaryButton(color: BeagleTheme.truthObserved))
                .controlSize(.small)

                Button {
                    withAnimation(BeagleMotion.snappy) { bootError = nil }
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(BeagleTheme.textTertiary)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var runningAgentCount: Int {
        cognitive.state.value?.agentSessions?.filter { ($0.readyReplicas ?? 0) > 0 }.count ?? 0
    }

    private var shellPresence: BeaglePresenceState {
        if bootError != nil {
            return .strained
        }
        if cognitive.runningJobCount > 0 || runningAgentCount > 0 {
            return .active
        }
        if selectedTab == 0 || selectedTab == 1 || selectedTab == 2 {
            return .attentive
        }
        return .dormant
    }

    private var selectedTabTitle: String {
        switch selectedTab {
        case 0:  return "Mind"
        case 1:  return "Capture"
        case 2:  return "Deep"
        case 3:  return "Agents"
        default: return "Mind"
        }
    }

    private var currentLaneLabel: String {
        let slug = preferredLaneSlug
        return slug
            .split(separator: "-")
            .map { $0.capitalized }
            .joined(separator: " ")
    }

    private var currentMindLabel: String {
        let runningKinds = cognitive.state.value?.agentSessions?
            .filter { ($0.readyReplicas ?? 0) > 0 }
            .compactMap(\.kind) ?? []

        if let first = runningKinds.first {
            return presentAgentKind(first)
        }

        return presentAgentKind(lastAgentKindRaw)
    }

    private func presentAgentKind(_ raw: String) -> String {
        raw
            .split(separator: "-")
            .map { $0.capitalized }
            .joined(separator: " ")
    }

    private var currentObjectiveLabel: String? {
        guard !lastAgentObjective.isEmpty else { return nil }
        guard lastAgentObjectiveProjectSlug.isEmpty || lastAgentObjectiveProjectSlug == preferredLaneSlug else {
            return nil
        }
        return lastAgentObjective
    }

    private var currentLaneResult: MobileLaneResultSummary? {
        let slug = preferredLaneSlug
        return cachedLaneResults.first(where: { $0.projectSlug == slug })
    }

    private var currentLaneState: ProjectLaneState? {
        let slug = preferredLaneSlug
        let project = catalog.projects.first(where: { $0.projectSlug == slug }) ?? catalog.primaryProject
        guard let project else { return nil }
        let sessions = cognitive.state.value?.agentSessions ?? []
        let carriedObjective =
            sessions.first(where: \.isRunning)?.presentedActivityLine
            ?? sessions.first(where: { $0.phase == .paused })?.presentedActivityLine
            ?? sessions.first?.presentedActivityLine
        return ProjectLaneState(
            project: project,
            sessions: sessions,
            scienceJobs: cognitive.activeJobs,
            laneResult: currentLaneResult,
            recentTrail: CognitiveStore.recentTrailSnippets(from: cognitive.recentThoughts),
            truth: shellPresenceTruth,
            isCurrent: true,
            livingQuestion: pinnedLaneQuestions[project.projectSlug],
            carriedObjective: carriedObjective ?? currentObjectiveLabel
        )
    }

    private var cachedLaneResults: [MobileLaneResultSummary] {
        guard let data = cachedLaneResultsJSON.data(using: .utf8),
              let decoded = try? JSONDecoder().decode([MobileLaneResultSummary].self, from: data) else {
            return []
        }
        return decoded
    }

    private var shellBannerIsCompact: Bool {
        bootError == nil
    }

    private var preferredLaneSlug: String {
        launchOverrides.projectSlug
        ?? cognitive.activeProjectSlug
        ?? catalog.primaryProject?.projectSlug
        ?? "sounio"
    }

    private var pinnedLaneQuestions: [String: String] {
        guard let data = pinnedLaneQuestionsJSON.data(using: .utf8),
              let decoded = try? JSONDecoder().decode([String: String].self, from: data) else {
            return [:]
        }
        return decoded
    }

    private var shellPresenceTruth: TruthMode {
        switch shellPresence {
        case .active:
            return .observed
        case .attentive:
            return .remembered
        case .dormant:
            return .declared
        case .strained:
            return .stale
        }
    }

}

/// Work (the agent deck) and Fleet (live sessions) share one phone tab — they are two
/// views of the same domain (the cluster agents). A segmented control swaps between them
/// so neither gets buried in a "More" overflow.
private struct AgentsTabView: View {
    @Binding var bootError: String?
    @State private var mode = 0   // 0 = Deck, 1 = Sessions

    var body: some View {
        VStack(spacing: 0) {
            Picker("Agents", selection: $mode) {
                Text("Deck").tag(0)
                Text("Sessions").tag(1)
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)
            .padding(.bottom, 8)

            if mode == 0 {
                WorkView(bootError: $bootError)
            } else {
                FleetTerminalsView()
            }
        }
    }
}

struct LaunchOverrides {
    let selectedTab: Int?
    let projectSlug: String?

    static var current: LaunchOverrides {
        let args = ProcessInfo.processInfo.arguments

        func value(after flag: String) -> String? {
            guard let index = args.firstIndex(of: flag), args.indices.contains(index + 1) else { return nil }
            return args[index + 1]
        }

        let selectedTab = value(after: "--beagle-selected-tab").flatMap(Int.init)
        let projectSlug = value(after: "--beagle-project-slug")

        return LaunchOverrides(selectedTab: selectedTab, projectSlug: projectSlug)
    }
}

// Cross-platform navigation title display mode
extension View {
    @ViewBuilder
    func navigationBarTitleDisplayModeIfAvailable(_ mode: TitleDisplayMode) -> some View {
        #if os(iOS) || os(visionOS)
        self.navigationBarTitleDisplayMode(mode == .large ? .large : .inline)
        #else
        self
        #endif
    }
}

enum TitleDisplayMode {
    case large, inline
}

private enum CircadianPhase: Sendable, Equatable {
    case dawn, morning, peak, afternoon, evening, night

    static var current: CircadianPhase {
        let hour = Calendar.current.component(.hour, from: .now)
        switch hour {
        case 5..<8: return .dawn
        case 8..<12: return .morning
        case 12..<16: return .peak
        case 16..<19: return .afternoon
        case 19..<22: return .evening
        default: return .night
        }
    }

    var tint: Color {
        switch self {
        case .dawn:      return Color(red: 0.95, green: 0.75, blue: 0.35) // warm amber
        case .morning:   return Color(red: 0.85, green: 0.88, blue: 0.95) // cool clarity
        case .peak:      return Color(red: 0.95, green: 0.92, blue: 0.85) // neutral warm
        case .afternoon: return Color(red: 0.90, green: 0.78, blue: 0.55) // copper
        case .evening:   return Color(red: 0.60, green: 0.50, blue: 0.75) // dusky violet
        case .night:     return Color(red: 0.15, green: 0.12, blue: 0.30) // deep indigo
        }
    }

    var tintIntensity: Double {
        switch self {
        case .dawn: return 0.12
        case .morning: return 0.06
        case .peak: return 0.05
        case .afternoon: return 0.08
        case .evening: return 0.14
        case .night: return 0.18
        }
    }

    var brightnessFactor: Double {
        switch self {
        case .dawn: return 0.70
        case .morning: return 0.95
        case .peak: return 1.05
        case .afternoon: return 0.85
        case .evening: return 0.60
        case .night: return 0.40
        }
    }

    var blueRetention: Double {
        switch self {
        case .dawn: return 0.65
        case .morning: return 1.0
        case .peak: return 0.95
        case .afternoon: return 0.80
        case .evening: return 0.55
        case .night: return 0.35
        }
    }

    var driftSpeed: Double {
        switch self {
        case .dawn: return 0.5
        case .morning: return 0.9
        case .peak: return 1.1
        case .afternoon: return 0.8
        case .evening: return 0.4
        case .night: return 0.15
        }
    }
}

private struct ShellPresenceBackground: View {
    let presence: BeaglePresenceState
    @State private var phase: CGFloat = 0
    @State private var circadianPhase: CircadianPhase = .current
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            MeshGradient(
                width: 3,
                height: 3,
                points: animatedPoints,
                colors: gradientColors
            )
            .ignoresSafeArea()

            LinearGradient(
                colors: [
                    .black.opacity(0.06),
                    .black.opacity(0.18),
                    Color(red: 0.01, green: 0.02, blue: 0.05).opacity(0.94)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()
        }
        .onAppear {
            guard !reduceMotion else { return }
            let animDuration = min(9.0 / circadianPhase.driftSpeed, 60.0)
            withAnimation(.easeInOut(duration: animDuration).repeatForever(autoreverses: true)) {
                phase = 1
            }
        }
        .task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(60))
                let newPhase = CircadianPhase.current
                if newPhase != circadianPhase {
                    withAnimation(.easeInOut(duration: 3.0)) {
                        circadianPhase = newPhase
                    }
                }
            }
        }
    }

    private var animatedPoints: [SIMD2<Float>] {
        let drift: Float = reduceMotion ? 0 : Float(phase) * 0.05 * Float(circadianPhase.driftSpeed)
        return [
            SIMD2(0, 0), SIMD2(0.5, 0), SIMD2(1, 0),
            SIMD2(0 + drift, 0.5 - drift), SIMD2(0.5, 0.5 + drift), SIMD2(1 - drift, 0.5 + drift),
            SIMD2(0, 1), SIMD2(0.5, 1), SIMD2(1, 1)
        ]
    }

    private var gradientColors: [Color] {
        let glow = presence.glow
        let tint = presence.tint
        let bf = circadianPhase.brightnessFactor
        let br = circadianPhase.blueRetention
        let ct = circadianPhase.tint
        let ci = circadianPhase.tintIntensity

        func dimBlue(_ color: Color, _ r: Double, _ g: Double, _ b: Double) -> Color {
            Color(red: r, green: g, blue: b * br)
        }

        return [
            glow.opacity(0.22 * bf), tint.opacity(0.08 * bf), dimBlue(.clear, 0.02, 0.03, 0.08),
            tint.opacity(0.10 * bf), ct.opacity(ci), glow.opacity(0.10 * bf),
            dimBlue(.clear, 0.01, 0.02, 0.05), dimBlue(.clear, 0.02, 0.03, 0.07), dimBlue(.clear, 0.01, 0.01, 0.03)
        ]
    }
}

private struct ShellPresenceBanner: View {
    let presence: BeaglePresenceState
    let selectedTabTitle: String
    let runningAgentCount: Int
    let runningJobCount: Int
    let laneLabel: String
    let mindLabel: String
    let objectiveLabel: String?
    let compact: Bool

    var body: some View {
        GlassPanel(elevation: .floating, truth: presenceTruth) {
            if compact {
                HStack(spacing: BeagleSpacing.xs) {
                    compactIcon
                    PresencePill(
                        label: laneLabel,
                        systemImage: "scope",
                        tint: BeagleTheme.truthObserved
                    )
                    if runningAgentCount > 0 {
                        PresencePill(
                            label: mindLabel,
                            systemImage: "sparkles",
                            tint: BeagleTheme.truthRemembered
                        )
                    }
                    if showsCompactStatus {
                        PresencePill(
                            label: statusLine,
                            systemImage: "waveform",
                            tint: presence.tint
                        )
                    }
                    Spacer(minLength: BeagleSpacing.xs)
                    if shouldShowCompactObjective, let objectiveLabel, !objectiveLabel.isEmpty {
                        Text(objectiveLabel)
                            .font(BeagleFont.caption2.font)
                            .foregroundStyle(BeagleTheme.truthRemembered)
                            .lineLimit(1)
                    }
                }
            } else {
                HStack(alignment: .top, spacing: BeagleSpacing.md) {
                    compactIcon

                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: BeagleSpacing.xs) {
                            Text(selectedTabTitle)
                                .font(BeagleFont.caption.font)
                                .fontWeight(.semibold)
                                .foregroundStyle(BeagleTheme.textTertiary)
                                .textCase(.uppercase)
                                .tracking(0.8)
                            PresencePill(
                                label: statusLine,
                                systemImage: "waveform",
                                tint: presence.tint
                            )
                        }

                        HStack(spacing: BeagleSpacing.xs) {
                            PresencePill(
                                label: laneLabel,
                                systemImage: "scope",
                                tint: BeagleTheme.truthObserved
                            )
                            PresencePill(
                                label: mindLabel,
                                systemImage: "sparkles",
                                tint: BeagleTheme.truthRemembered
                            )
                        }

                        Text(presence.title)
                            .font(BeagleFont.subheadline.font)
                            .fontWeight(.semibold)
                            .foregroundStyle(BeagleTheme.textPrimary)

                        Text(presence.subtitle)
                            .font(BeagleFont.caption.font)
                            .foregroundStyle(BeagleTheme.textSecondary)
                            .lineLimit(2)

                        if let objectiveLabel, !objectiveLabel.isEmpty {
                            Text(objectiveLabel)
                                .font(BeagleFont.caption2.font)
                                .foregroundStyle(BeagleTheme.truthRemembered)
                                .lineLimit(2)
                        }
                    }

                    Spacer()
                }
            }
        }
    }

    private var compactIcon: some View {
        ZStack {
            Circle()
                .fill(presence.tint.opacity(compact ? 0.10 : 0.14))
                .frame(width: compact ? 24 : 34, height: compact ? 24 : 34)
            Image(systemName: presence.icon)
                .font(.system(size: compact ? 11 : 14, weight: .semibold))
                .foregroundStyle(presence.tint)
        }
    }

    private var showsCompactStatus: Bool {
        runningAgentCount > 0 || runningJobCount > 0 || presence == .strained
    }

    private var shouldShowCompactObjective: Bool {
        runningAgentCount > 0 || runningJobCount > 0
    }

    private var statusLine: String {
        if runningAgentCount > 0 || runningJobCount > 0 {
            var parts: [String] = []
            if runningAgentCount > 0 {
                parts.append("\(runningAgentCount) agent\(runningAgentCount == 1 ? "" : "s")")
            }
            if runningJobCount > 0 {
                parts.append("\(runningJobCount) job\(runningJobCount == 1 ? "" : "s")")
            }
            return parts.joined(separator: " · ")
        }
        switch presence {
        case .dormant:
            return "quiet continuity"
        case .attentive:
            return "ambient attention"
        case .active:
            return "live cognition"
        case .strained:
            return "signal strain"
        }
    }

    private var presenceTruth: TruthMode {
        switch presence {
        case .active:
            return .observed
        case .attentive:
            return .remembered
        case .dormant:
            return .declared
        case .strained:
            return .stale
        }
    }
}

// MARK: - Menu bar content (macOS)

#if os(macOS)
struct MenuBarContent: View {
    @Environment(CatalogStore.self) private var catalog

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("COCKPIT")
                .font(BeagleTheme.uiFont(size: 10, weight: .semibold))
                .tracking(1.2)
                .foregroundStyle(BeagleTheme.textTertiary)

            let counts = catalog.postureCounts
            HStack(spacing: 12) {
                Label("\(counts.alwaysOn)", systemImage: "circle.fill")
                    .foregroundStyle(BeagleTheme.postureOn)
                Label("\(counts.warm)", systemImage: "circle.lefthalf.filled")
                    .foregroundStyle(BeagleTheme.postureWarm)
                Label("\(counts.cold)", systemImage: "circle")
                    .foregroundStyle(BeagleTheme.postureCold)
            }
            .font(BeagleTheme.dataFont(size: 12))

            Divider().padding(.vertical, 4)

            ForEach(catalog.alwaysOnProjects) { project in
                Button {
                    NSApp.activate(ignoringOtherApps: true)
                } label: {
                    HStack {
                        PostureIndicator(project.posture, size: 11, showLabel: false)
                        Text(project.projectSlug)
                            .font(BeagleTheme.dataFont(size: 12))
                    }
                }
                .buttonStyle(.plain)
            }

            Divider().padding(.vertical, 4)

            Button("Open Cockpit") {
                NSApp.activate(ignoringOtherApps: true)
            }
            Button("Refresh") {
                Task { await catalog.refresh() }
            }
            Button("Quit") {
                NSApp.terminate(nil)
            }
        }
        .padding(12)
        .frame(width: 240)
    }
}
#endif
