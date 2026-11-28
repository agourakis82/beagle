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
#if canImport(CoreSpotlight) && !os(watchOS)
import CoreSpotlight
#endif
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
    @State private var forceOnboardingInSession = ProcessInfo.processInfo.arguments.contains("--reset-onboarding")

    init() {
        let args = ProcessInfo.processInfo.arguments
        if args.contains("--reset-onboarding") {
            UserDefaults.standard.removeObject(forKey: "hasCompletedOnboarding")
        }
        #if os(iOS)
        if args.contains("--ui-testing") {
            UIView.setAnimationsEnabled(false)
        }
        Self.configureShellChrome()
        #endif
    }

    var body: some Scene {
        WindowGroup {
            if hasCompletedOnboarding && !forceOnboardingInSession {
                RootView(path: $navigationPath, bootError: $bootError, launchOverrides: launchOverrides)
                .environment(catalog)
                .environment(cognitive)
                .environment(physio)
                .environment(hpc)
                .modelContainer(for: [
                    PersistedThought.self,
                    PersistedMessage.self,
                    PersistedConversation.self,
                    PersistedDeepSession.self,
                    PersistedExocortexHomeSnapshot.self,
                    PersistedAssistedImportOutbox.self,
                ], inMemory: ProcessInfo.processInfo.arguments.contains("--ui-testing"))
                .sheet(isPresented: Binding(
                    get: { MemorySearchNavigation.shared.episodeID != nil },
                    set: { if !$0 { MemorySearchNavigation.shared.episodeID = nil } }
                )) {
                    if let id = MemorySearchNavigation.shared.episodeID {
                        MemorySearchDetailView(episodeID: id)
                    }
                }
                .sheet(isPresented: Binding(
                    get: { ResearchRunSearchNavigation.shared.runID != nil },
                    set: { if !$0 { ResearchRunSearchNavigation.shared.runID = nil } }
                )) {
                    if let runID = ResearchRunSearchNavigation.shared.runID {
                        ResearchRunSearchDetailView(runID: runID)
                    }
                }
                .task {
                    guard !ProcessInfo.processInfo.arguments.contains("--ui-testing") else { return }
                    await LiveActivityManager.shared.restoreClusterActivitiesAfterLaunch()
                    await MemorySearchIndex.refresh()
                }
                .onOpenURL { url in
                    handleDeepLink(url)
                }
                .onContinueUserActivity("dev.sounio.cockpit.viewProject") { activity in
                    if let slug = activity.userInfo?["slug"] as? String {
                        DeepLinkRouter.shared.requestProject(.init(slug: slug))
                    }
                }
                .onContinueUserActivity("dev.sounio.cockpit.viewAgent") { activity in
                    if let slug = activity.userInfo?["slug"] as? String {
                        let kind = (activity.userInfo?["agentKind"] as? String)
                            ?? (activity.userInfo?["kind"] as? String)
                        DeepLinkRouter.shared.requestProject(.init(slug: slug, agentKind: kind))
                    }
                }
                #if canImport(CoreSpotlight) && !os(watchOS)
                .onContinueUserActivity(CSSearchableItemActionType) { activity in
                    if let rawId = activity.userInfo?[CSSearchableItemActivityIdentifier] as? String,
                       let convId = ConversationSpotlightIndexer.conversationId(fromSpotlightIdentifier: rawId) {
                        navigationPath = NavigationPath()
                        DeepLinkRouter.shared.requestCompanionAction(
                            CompanionLaunchAction(conversationId: convId)
                        )
                    }
                }
                #endif
                .preferredColorScheme(.dark)
        .tint(BeagleTheme.truthObserved)
            } else {
                OnboardingView(isComplete: Binding(
                    get: { hasCompletedOnboarding && !forceOnboardingInSession },
                    set: { completed in
                        hasCompletedOnboarding = completed
                        if completed { forceOnboardingInSession = false }
                    }
                ))
                    .preferredColorScheme(.dark)
            }
        }
        #if os(iOS)
        .backgroundTask(.appRefresh(beagleDreamTaskIdentifier)) {
            await runDreamConsolidation()
            // Piggybacks on this task's ~8h cadence rather than registering a second
            // BGTaskSchedulerPermittedIdentifiers entry — comfortably inside the ~2-day
            // window CMSensorRecorder needs to not lose its rolling 3-day buffer.
            await ActigraphySyncEngine.shared.pullAndProcess(uploader: PhysiomeUploader.shared)
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
            cognitivePosture: physio.cognitivePosture,
            neuralSynthesizer: { candidateThoughts in
                await FoundationModelsAgent.shared.synthesizeDreamBridge(thoughts: candidateThoughts)
            }
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
        // Unified routing through DeepLinkRouter (handles companion actions, project targets
        // beagle://project/{slug}[/agent/{kind}], and top-level destinations across cold start
        // on both iPhone and iPad).
        _ = DeepLinkRouter.shared.open(url)
    }

    // bootstrap() moved to RootView where modelContext is properly available
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
