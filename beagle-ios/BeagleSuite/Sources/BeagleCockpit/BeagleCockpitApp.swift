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

@main
struct BeagleCockpitApp: App {
    @State private var catalog = CatalogStore()
    @State private var cognitive = CognitiveStore()
    @State private var hpc = HPCStore()
    @State private var navigationPath = NavigationPath()
    @State private var bootError: String?
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false

    var body: some Scene {
        WindowGroup {
            if hasCompletedOnboarding {
                RootView(path: $navigationPath, bootError: $bootError)
                .environment(catalog)
                .environment(cognitive)
                .environment(hpc)
                .modelContainer(for: [PersistedThought.self, PersistedMessage.self, PersistedDeepSession.self])
                .task {
                    await bootstrap()
                }
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

    @Environment(\.modelContext) private var modelContext

    private func bootstrap() async {
        // Wire persistence into stores
        cognitive.modelContext = modelContext
        cognitive.loadPersistedThoughts()

        // Auth bridge first — gets token from cockpit
        await BeagleClient.shared.ensureAuth()
        // Parallel refresh
        async let catalogTask: () = catalog.refresh()
        async let cognitiveTask: () = cognitive.refresh()
        async let warmTask: () = FoundationModelsAgent.shared.prewarm()
        _ = await (catalogTask, cognitiveTask, warmTask)
        // Check if data loaded — if not, show error
        if catalog.executive.mode == .stale {
            bootError = "Could not reach cockpit. Check Tailnet connectivity."
        }
    }

    private func navigateToProject(_ slug: String) {
        // Find or create the project to navigate to
        if let project = catalog.projects.first(where: { $0.projectSlug == slug }) {
            navigationPath = NavigationPath()
            navigationPath.append(project)
        }
    }
}

// MARK: - Root navigation shell

struct RootView: View {
    @Binding var path: NavigationPath
    @Binding var bootError: String?
    @Environment(CatalogStore.self) private var catalog
    @AppStorage("selectedTab") private var selectedTab = 0

    var body: some View {
        ZStack(alignment: .top) {
            if sizeClass == .regular {
                iPadLayout
            } else {
                tabContent
            }
            if let error = bootError {
                authErrorBanner(error)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
    }

    // MARK: - iPad Layout (sidebar + detail)

    enum SidebarItem: String, CaseIterable, Identifiable {
        case mind = "Mind"
        case deep = "Deep"
        case platform = "Platform"
        case terminal = "Terminal"
        case settings = "Settings"

        var id: String { rawValue }

        var icon: String {
            switch self {
            case .mind:     return "brain.head.profile"
            case .deep:     return "scope"
            case .platform: return "server.rack"
            case .terminal: return "terminal"
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
                        HomeView()
                    case .deep:
                        DeepExplorationView()
                    case .platform:
                        PlatformView()
                            .navigationDestination(for: Project.self) { project in
                                ControlRoomView(slug: project.projectSlug)
                            }
                    case .terminal:
                        AgentSessionView(slug: catalog.primaryProject?.projectSlug ?? "sounio")
                    case .settings:
                        ModelSettingsView()
                    case nil:
                        HomeView()
                    }
                }
            }
        }
        .tint(BeagleTheme.truthObserved)
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
        .padding(.horizontal, BeagleSpacing.lg)
        .padding(.top, BeagleSpacing.md)
    }

    @Environment(\.horizontalSizeClass) private var sizeClass

    private var tabContent: some View {
        TabView(selection: $selectedTab) {
            // Tab 0: Mind — think, capture, connect
            NavigationStack {
                HomeView()
            }
            .tabItem { Label("Mind", systemImage: "brain.head.profile") }
            .tag(0)

            // Tab 1: Deep — Go Deeper as first-class surface with history
            NavigationStack {
                DeepExplorationView()
            }
            .tabItem { Label("Deep", systemImage: "scope") }
            .tag(1)

            // Tab 2: Platform — cluster, projects, control rooms
            NavigationStack(path: $path) {
                PlatformView()
                    .navigationDestination(for: Project.self) { project in
                        ControlRoomView(slug: project.projectSlug)
                    }
            }
            .tabItem { Label("Platform", systemImage: "server.rack") }
            .tag(2)

            // Tab 3: Terminal — agent session
            NavigationStack {
                AgentSessionView(slug: catalog.primaryProject?.projectSlug ?? "sounio")
            }
            .tabItem { Label("Terminal", systemImage: "terminal") }
            .tag(3)
        }
        .tint(BeagleTheme.truthObserved)
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
