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

extension Notification.Name {
    fileprivate static let beagleNavigateSidebar = Notification.Name("beagle.navigate.sidebar")
}

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
        .defaultSize(width: 1200, height: 800)
        .windowResizability(.contentSize)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("Refresh Catalog") {
                    Task { await catalog.refresh() }
                }
                .keyboardShortcut("r", modifiers: .command)
            }
            CommandMenu("Go") {
                Button("Home") { NotificationCenter.default.post(name: .beagleNavigateSidebar, object: "Home") }
                    .keyboardShortcut("1", modifiers: .command)
                Button("Work") { NotificationCenter.default.post(name: .beagleNavigateSidebar, object: "Work") }
                    .keyboardShortcut("2", modifiers: .command)
                Button("Terminals") { NotificationCenter.default.post(name: .beagleNavigateSidebar, object: "Terminals") }
                    .keyboardShortcut("3", modifiers: .command)
                Button("Recall") { NotificationCenter.default.post(name: .beagleNavigateSidebar, object: "Recall") }
                    .keyboardShortcut("4", modifiers: .command)
            }
        }
        #endif

        #if os(macOS)
        MenuBarExtra("Beagle Cockpit", systemImage: "sparkle") {
            MenuBarContent()
                .environment(catalog)
        }
        .menuBarExtraStyle(.window)

        // ⌘, opens the model/settings surface as a proper macOS Settings window.
        Settings {
            NavigationStack { ModelSettingsView() }
                .frame(minWidth: 520, minHeight: 600)
                .preferredColorScheme(.dark)
                .tint(BeagleTheme.truthObserved)
        }
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
    @State private var showCompose = false
    @State private var showSettings = false
    @Environment(\.horizontalSizeClass) private var sizeClass
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        Group {
            #if os(macOS)
            macLayout
            #else
            // iPad regular width gets the persistent sidebar; iPhone / compact (Slide
            // Over, narrow Stage Manager) keep the tab bar.
            if sizeClass == .regular {
                macLayout
            } else {
                phoneLayout
            }
            #endif
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
        .sheet(isPresented: $showCompose) {
            NavigationStack {
                AgentSessionView(slug: cognitive.activeProjectSlug ?? "sounio")
                    .navigationTitle("Chat")
                    #if os(iOS)
                    .navigationBarTitleDisplayMode(.inline)
                    #endif
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Close") { showCompose = false }
                        }
                    }
            }
            #if os(macOS)
            .frame(minWidth: 640, minHeight: 720)
            #endif
        }
        .sheet(isPresented: $showSettings) {
            NavigationStack {
                ModelSettingsView()
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Done") { showSettings = false }
                        }
                    }
            }
            #if os(macOS)
            .frame(minWidth: 520, minHeight: 600)
            #endif
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

    // MARK: - Phone Layout (3 tabs + floating Compose)

    private var phoneLayout: some View {
        TabView(selection: $selectedTab) {
            Tab("Home", systemImage: "house", value: 0) {
                NavigationStack {
                    HomeView()
                        .toolbar { composeToolbarItem; settingsToolbarItem }
                }
            }
            Tab("Agents", systemImage: "terminal", value: 3) {
                NavigationStack {
                    AgentsHubView(bootError: $bootError)
                        .toolbar { composeToolbarItem; settingsToolbarItem }
                }
            }
            Tab("Recall", systemImage: "magnifyingglass", value: 4, role: .search) {
                NavigationStack {
                    CognitiveRecallView()
                        .toolbar { composeToolbarItem; settingsToolbarItem }
                }
            }
        }
        // Unify the app accent to teal (truthObserved). The amber brand accent
        // applied here colored ALL toolbar/nav chrome amber, clashing with the
        // teal used everywhere else — it read as random. Amber stays reserved
        // for semantic "warm/working" states, not chrome.
        .tint(BeagleTheme.truthObserved)
        // iPad (regular width) promotes the tab bar to a sidebar; iPhone keeps the
        // bottom tabs. Fixes the P0 where a 13" iPad rendered the iPhone tab layout.
        .tabViewStyle(.sidebarAdaptable)
    }

#if os(macOS) || os(iOS)
    // MARK: - Mac/iPad sidebar layout (shared NavigationSplitView)
    // Used on macOS always, and on iPad regular width (iPhone/compact use phoneLayout).

    enum SidebarItem: String, CaseIterable, Identifiable, Hashable {
        case home = "Home"
        case work = "Work"
        case terminals = "Terminals"
        case recall = "Recall"
        case platform = "Platform"
        case diagnostics = "Diagnostics"

        var id: Self { self }

        var icon: String {
            switch self {
            case .home:        return "house"
            case .work:        return "rectangle.3.group"
            case .terminals:   return "terminal"
            case .recall:      return "magnifyingglass"
            case .platform:    return "server.rack"
            case .diagnostics: return "stethoscope"
            }
        }

        var subtitle: String {
            switch self {
            case .home:
                return "Briefing and thinking surface"
            case .work:
                return "Agent lanes and artifacts"
            case .terminals:
                return "Fleet runtime access"
            case .recall:
                return "Search memory"
            case .platform:
                return "Projects and cluster state"
            case .diagnostics:
                return "Health checks"
            }
        }

        var legacyTabValue: Int {
            switch self {
            case .home:
                return 0
            case .work, .terminals, .platform, .diagnostics:
                return 3
            case .recall:
                return 4
            }
        }
    }

    enum SidebarSection: String, CaseIterable, Identifiable {
        case cockpit = "Cockpit"
        case memory = "Memory"
        case system = "System"

        var id: Self { self }

        var items: [SidebarItem] {
            switch self {
            case .cockpit:
                return [.home, .work, .terminals]
            case .memory:
                return [.recall]
            case .system:
                return [.platform, .diagnostics]
            }
        }
    }

    @State private var sidebarSelection: SidebarItem = .home
    @State private var columnVisibility: NavigationSplitViewVisibility = .all

    // iOS List single-selection needs an OPTIONAL binding (macOS allows non-optional).
    // This proxy keeps `sidebarSelection` non-optional everywhere else while satisfying
    // both platforms' `List(selection:)`.
    private var sidebarSelectionBinding: Binding<SidebarItem?> {
        Binding(get: { sidebarSelection }, set: { if let v = $0 { sidebarSelection = v } })
    }

    private var macLayout: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            List(selection: sidebarSelectionBinding) {
                ForEach(SidebarSection.allCases) { section in
                    Section(section.rawValue) {
                        ForEach(section.items) { item in
                            macSidebarRow(item)
                                .tag(item)
                        }
                    }
                }

                Section {
                    macSidebarStatus
                }
            }
            .navigationTitle("Beagle")
            .listStyle(.sidebar)
            .navigationSplitViewColumnWidth(min: 220, ideal: 260, max: 320)
        } detail: {
            NavigationStack(path: $path) {
                macDetail
                    .navigationDestination(for: Project.self) { project in
                        ControlRoomView(slug: project.projectSlug)
                    }
                    .toolbar { macToolbarContent }
            }
        }
        // Unify the app accent to teal (truthObserved). The amber brand accent
        // applied here colored ALL toolbar/nav chrome amber, clashing with the
        // teal used everywhere else — it read as random. Amber stays reserved
        // for semantic "warm/working" states, not chrome.
        .tint(BeagleTheme.truthObserved)
        .onChange(of: sidebarSelection) { _, newValue in
            selectedTab = newValue.legacyTabValue
        }
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
        .onReceive(NotificationCenter.default.publisher(for: .beagleNavigateSidebar)) { note in
            guard let raw = note.object as? String,
                  let item = SidebarItem(rawValue: raw) else { return }
            sidebarSelection = item
        }
    }

    private func macSidebarRow(_ item: SidebarItem) -> some View {
        Label {
            VStack(alignment: .leading, spacing: 2) {
                Text(item.rawValue)
                    .font(BeagleFont.subheadline.font)
                Text(item.subtitle)
                    .font(BeagleFont.caption2.font)
                    .foregroundStyle(BeagleTheme.textTertiary)
                    .lineLimit(1)
            }
        } icon: {
            Image(systemName: item.icon)
                .foregroundStyle(sidebarSelection == item ? BeagleTheme.accent : BeagleTheme.textSecondary)
        }
        .padding(.vertical, 3)
    }

    private var macSidebarStatus: some View {
        VStack(alignment: .leading, spacing: BeagleSpacing.sm) {
            HStack(spacing: BeagleSpacing.xs) {
                Image(systemName: shellPresence.icon)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(shellPresence.tint)
                Text(macStatusTitle)
                    .font(BeagleFont.caption.font)
                    .fontWeight(.semibold)
                    .foregroundStyle(BeagleTheme.textPrimary)
                Spacer()
            }

            Text(macStatusDetail)
                .font(BeagleFont.caption2.font)
                .foregroundStyle(BeagleTheme.textTertiary)
                .lineLimit(2)

            HStack(spacing: BeagleSpacing.xs) {
                PresencePill(label: currentLaneLabel, systemImage: "scope", tint: BeagleTheme.truthObserved)
                if runningAgentCount > 0 {
                    PresencePill(label: "\(runningAgentCount) live", systemImage: "sparkles", tint: BeagleTheme.truthRemembered)
                }
            }
        }
        .padding(.vertical, BeagleSpacing.xs)
    }

    private var macDetail: some View {
        VStack(spacing: 0) {
            macStatusStrip
            Divider().overlay(BeagleTheme.hairline)
            macSelectedContent
        }
        .background(ShellPresenceBackground(presence: shellPresence))
        .navigationTitle(sidebarSelection.rawValue)
    }

    private var macStatusStrip: some View {
        VStack(spacing: BeagleSpacing.xs) {
            ShellPresenceBanner(
                presence: shellPresence,
                selectedTabTitle: sidebarSelection.rawValue,
                runningAgentCount: runningAgentCount,
                runningJobCount: cognitive.runningJobCount,
                laneLabel: currentLaneLabel,
                mindLabel: currentMindLabel,
                objectiveLabel: currentObjectiveLabel,
                compact: true
            )
            .padding(.horizontal, BeagleSpacing.lg)
            .padding(.top, BeagleSpacing.md)
            .padding(.bottom, bootError == nil ? BeagleSpacing.md : 0)

            if let bootError {
                authErrorBanner(bootError)
                    .padding(.horizontal, BeagleSpacing.lg)
                    .padding(.bottom, BeagleSpacing.md)
            }
        }
        .background(.background.secondary)
    }

    @ViewBuilder
    private var macSelectedContent: some View {
        switch sidebarSelection {
        case .home:
            HomeView()
        case .work:
            WorkView(bootError: $bootError)
        case .terminals:
            FleetTerminalsView()
                .navigationTitle("Terminals")
        case .recall:
            CognitiveRecallView()
        case .platform:
            PlatformView()
        case .diagnostics:
            DiagnosticsView()
        }
    }

    @ToolbarContentBuilder
    private var macToolbarContent: some ToolbarContent {
        ToolbarItem(placement: .navigation) {
            Button {
                withAnimation(BeagleMotion.snappy) {
                    columnVisibility = columnVisibility == .detailOnly ? .all : .detailOnly
                }
            } label: {
                Label("Toggle Sidebar", systemImage: "sidebar.left")
            }
        }

        ToolbarItemGroup(placement: .primaryAction) {
            Button { showCompose = true } label: {
                Label("New chat", systemImage: "bubble.left.and.text.bubble.right")
            }
            // Teal (truthObserved) to match the rest of the toolbar — the amber
            // brand accent on a single icon read as random in the teal UI.
            .tint(BeagleTheme.truthObserved)

            Button { showCognitiveState = true } label: {
                Label("State", systemImage: "waveform.path.ecg")
            }

            Button { showSettings = true } label: {
                Label("Settings", systemImage: "gearshape")
            }
        }
    }

    private var macStatusTitle: String {
        switch shellPresence {
        case .active:
            return "Live work"
        case .attentive:
            return "Ready"
        case .dormant:
            return "Quiet"
        case .strained:
            return "Needs attention"
        }
    }

    private var macStatusDetail: String {
        if let bootError {
            return bootError
        }
        var parts: [String] = []
        if runningAgentCount > 0 {
            parts.append("\(runningAgentCount) agent\(runningAgentCount == 1 ? "" : "s")")
        }
        if cognitive.runningJobCount > 0 {
            parts.append("\(cognitive.runningJobCount) job\(cognitive.runningJobCount == 1 ? "" : "s")")
        }
        if parts.isEmpty {
            return "Lane \(currentLaneLabel) is available."
        }
        return parts.joined(separator: " · ")
    }

#endif

    @ToolbarContentBuilder
    private var composeToolbarItem: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            Button { showCompose = true } label: {
                Label("New chat", systemImage: "bubble.left.and.text.bubble.right")
            }
            // Teal (truthObserved) to match the rest of the toolbar — the amber
            // brand accent on a single icon read as random in the teal UI.
            .tint(BeagleTheme.truthObserved)
        }
    }

    @ToolbarContentBuilder
    private var settingsToolbarItem: some ToolbarContent {
        ToolbarItem(placement: .secondaryAction) {
            Button { showSettings = true } label: {
                Label("Settings", systemImage: "gearshape")
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
        case 3:  return "Work"
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

// CircadianPhase removed — no time-of-day tinting in the new visual direction.

private struct ShellPresenceBackground: View {
    let presence: BeaglePresenceState

    var body: some View {
        // Flat system background. No mesh, no circadian, no glow.
        #if os(iOS)
        Color(uiColor: .systemBackground).ignoresSafeArea()
        #elseif os(macOS)
        Color(nsColor: .windowBackgroundColor).ignoresSafeArea()
        #else
        Color.clear.ignoresSafeArea()
        #endif
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
