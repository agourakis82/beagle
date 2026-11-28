//
//  BeagleCockpitRootView.swift
//  BeagleCockpit
//
//  Root navigation shell, bootstrap lifecycle, Physiome real-time sync,
//  and iPhone / iPad adaptive layouts.
//

import SwiftUI
import SwiftData
import BeagleCore
import BeagleWorkbenchKit
#if os(iOS)
import BackgroundTasks
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
                guard !ProcessInfo.processInfo.arguments.contains("--ui-testing") else { break }
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
        let isUITesting = ProcessInfo.processInfo.arguments.contains("--ui-testing")
        if !isUITesting {
            SemanticSearchEngine.shared.warmup()
        }
        cognitive.loadPersistedThoughts()
        DreamSynthesisEngine.shared.loadPersistedInsights()
        cognitive.activeProjectSlug = launchOverrides.projectSlug ?? cognitive.activeProjectSlug ?? "sounio"
        if isUITesting {
            return
        }

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
        if args.contains("--demo") || args.contains("--demo-chat") || args.contains("--beagle-skip-physio-auth") { return }
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
            // Driving-time proxy (CarPlay/Waze integration confirmed infeasible — see
            // DrivingSyncEngine's header comment for why).
            await DrivingSyncEngine.shared.start(uploader: uploader)
            // Opportunistic pull — also runs from the dream BGTask (see .backgroundTask
            // above), this is the foreground half of the same ~2-day-max cadence. Own
            // detached Task (not awaited here): bucketing 2 days of 50Hz accelerometer +
            // DFA/sample-entropy is real CPU work that shouldn't delay AQI/other engines
            // starting right behind it.
            Task.detached(priority: .utility) {
                await ActigraphySyncEngine.shared.pullAndProcess(uploader: uploader)
            }
            #endif
            // AQI — WeatherKit doesn't provide it; direct API fallback chain instead.
            await AQISyncEngine.shared.start(uploader: uploader)
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
        case frota    = "Frota"
        case oficina  = "Oficina"
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
            case .frota:    return "dot.radiowaves.left.and.right"
            case .oficina:  return "wrench.and.screwdriver"
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
    /// Set when the Frota hands a lane to the Terminals screen ("open this one").
    @State private var openLane: String?
    /// A deep link parked by `onOpenURL` (Live Activity, Shortcut, notification tap).
    private let deepLink = DeepLinkRouter.shared

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
                    case .frota:
                        FrotaView(onOpenLane: { lane in
                            openLane = lane
                            sidebarSelection = .fleet
                        })
                    case .oficina:
                        OficinaView()
                    case .fleet:
                        FleetTerminalsView(initialAgent: openLane)
                    case .settings:
                        ModelSettingsView()
                    case nil:
                        SpatialDeskMissionControlView()
                    }
                }
                .navigationDestination(for: DeepLinkRouter.ProjectLaunchTarget.self) { target in
                    ControlRoomView(slug: target.slug)
                }
                .navigationDestination(for: Project.self) { project in
                    ControlRoomView(slug: project.projectSlug)
                }
            }
        }
        .task {
            consumePendingProjectOnIPad()
        }
        .onChange(of: deepLink.pendingProject) { _, _ in
            consumePendingProjectOnIPad()
        }
        .onChange(of: deepLink.pending) { _, _ in
            if deepLink.pending == .capture {
                sidebarSelection = .mind
                return
            }
            guard let d = deepLink.consume() else { return }
            switch d {
            case .chat, .capture, .sintese: sidebarSelection = .mind
            case .fundo:                    sidebarSelection = .deep
            case .frota:                    sidebarSelection = .frota
            case .oficina:                  sidebarSelection = .oficina
            case .work:                     sidebarSelection = .work
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

    private func consumePendingProjectOnIPad() {
        guard let target = deepLink.consumeProject() else { return }
        path = NavigationPath()
        path.append(target)
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

