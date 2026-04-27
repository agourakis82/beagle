//
//  WorkView.swift
//  BeagleCockpit
//
//  The Work tab. Terminal, agents, and operational access.
//  First-class terminal that connects to workspace tmux.
//  Quick access to Platform, ControlRoom, HPC, ScienceJobs.
//

import SwiftUI
import BeagleCore

struct WorkView: View {
    @Environment(CatalogStore.self) private var catalog
    @Environment(CognitiveStore.self) private var cognitive
    @Binding var bootError: String?

    @State private var terminal = TerminalStore()
    @State private var exocortex = ExocortexStore()
    @State private var terminalInputText = ""
    @State private var showAgentSession = false
    @State private var showPlatform = false
    @State private var workMemoryStatus = "Work memory idle"

    var body: some View {
        VStack(spacing: 0) {
            // Terminal — the main content
            TerminalContentView(
                terminal: terminal,
                onReconnect: { connectTerminal() },
                sessionIdentityText: activeSlug
            )

            // Terminal input bar
            BeagleInputBar(
                text: $terminalInputText,
                placeholder: "> command",
                mode: .terminal,
                isEnabled: terminal.connectionState.isConnected,
                onSubmit: { text in
                    terminal.sendInput(text + "\n")
                },
                onSpecialKey: { key in
                    terminal.sendInput(key.escapeSequence)
                }
            )

            HStack(spacing: BeagleSpacing.xs) {
                Image(systemName: "point.3.connected.trianglepath.dotted")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(BeagleTheme.truthObserved)
                Text(workMemoryStatus)
                    .font(BeagleFont.caption2.font)
                    .foregroundStyle(BeagleTheme.textTertiary)
                    .lineLimit(1)
                Spacer()
            }
            .padding(.horizontal, BeagleSpacing.md)
            .padding(.vertical, 4)
            .background(BeagleTheme.surface1.opacity(0.5))

            latestWorkMemoryStrip

            // Quick access strip
            quickAccessStrip
        }
        .background(Color(red: 0.02, green: 0.03, blue: 0.06))
        .navigationTitle("Work")
        #if !os(macOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            ToolbarItem(placement: toolbarPlacement) {
                Menu {
                    Button {
                        showAgentSession = true
                    } label: {
                        Label("Agent Sessions", systemImage: "bolt.fill")
                    }
                    Button {
                        showPlatform = true
                    } label: {
                        Label("Platform", systemImage: "server.rack")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .foregroundStyle(BeagleTheme.textSecondary)
                }
            }
        }
        .task {
            connectTerminal()
            await refreshWorkMemoryContext()
        }
        .sheet(isPresented: $showAgentSession) {
            NavigationStack {
                AgentSessionView(slug: activeSlug)
            }
        }
        .sheet(isPresented: $showPlatform) {
            NavigationStack {
                PlatformView()
                    .navigationDestination(for: Project.self) { project in
                        ControlRoomView(slug: project.projectSlug)
                    }
            }
        }
    }

    // MARK: - Quick access strip

    private var toolbarPlacement: ToolbarItemPlacement {
        #if os(macOS)
        return .automatic
        #else
        return .topBarTrailing
        #endif
    }

    private var quickAccessStrip: some View {
        HStack(spacing: 0) {
            quickButton("Agents", icon: runningAgentCount > 0 ? "bolt.fill" : "bolt", tint: runningAgentCount > 0 ? BeagleTheme.postureWarm : BeagleTheme.textTertiary) {
                showAgentSession = true
            }
            quickButton("Platform", icon: "server.rack", tint: BeagleTheme.textTertiary) {
                showPlatform = true
            }
            quickButton("Remember", icon: "externaldrive.connected.to.line.below", tint: BeagleTheme.truthObserved) {
                Task { await recordWorkMemory() }
            }
            quickButton("Reconnect", icon: "arrow.clockwise", tint: terminal.connectionState.isConnected ? BeagleTheme.truthObserved : BeagleTheme.stateError) {
                connectTerminal()
            }
        }
        .padding(.vertical, BeagleSpacing.xs)
        .background(.ultraThinMaterial)
    }

    private var latestWorkMemoryStrip: some View {
        HStack(alignment: .top, spacing: BeagleSpacing.xs) {
            Image(systemName: "hammer.circle")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(BeagleTheme.truthObserved)
                .frame(width: 16)
            VStack(alignment: .leading, spacing: 2) {
                Text("Latest work memory")
                    .font(BeagleFont.caption2.font)
                    .fontWeight(.semibold)
                    .foregroundStyle(BeagleTheme.textTertiary)
                Text(latestWorkMemoryLine)
                    .font(BeagleFont.caption2.font)
                    .foregroundStyle(BeagleTheme.textSecondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: BeagleSpacing.xs)
        }
        .padding(.horizontal, BeagleSpacing.md)
        .padding(.vertical, 5)
        .background(BeagleTheme.surface0.opacity(0.55))
    }

    private func quickButton(_ label: String, icon: String, tint: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 2) {
                Image(systemName: icon)
                    .font(.system(size: 13))
                Text(label)
                    .font(BeagleFont.caption2.font)
            }
            .foregroundStyle(tint)
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Terminal connection

    private func connectTerminal() {
        terminal.connectTerminal(slug: activeSlug)
    }

    private func recordWorkMemory() async {
        let project = catalog.projects.first(where: { $0.projectSlug == activeSlug })
        let snapshot = AgentWorkMemorySnapshot(
            projectSlug: activeSlug,
            repo: project?.repoUrl,
            branch: project?.branch ?? project?.preferredPrBase,
            sessionId: "beagle-work-\(activeSlug)-\(UUID().uuidString.lowercased())",
            agentKind: "beagle-apple-work",
            objective: "Continue work on \(activeSlug) from the Beagle app Work surface.",
            planSummary: "User opened Work surface with terminal and agent sessions available.",
            diffSummary: nil,
            testsSummary: nil,
            decisionSummary: "Record current Work context as GraphRAG++ operational memory.",
            createdAt: AssistedImportRequestFactory.isoTimestamp()
        )
        let request = AssistedImportRequestFactory.workMemory(snapshot)
        guard request.privacyClass != "restricted" else {
            workMemoryStatus = "Restricted work context held locally."
            return
        }
        let result = await BeagleClient.shared.assistedImportBatch(request)
        if let imported = result.value, imported.status == "imported" {
            let atoms = imported.projection?.atomsCreated ?? 0
            workMemoryStatus = "Work memory imported: \(atoms) atoms"
            await refreshWorkMemoryContext()
        } else {
            workMemoryStatus = result.error ?? result.value?.reason ?? "Work memory import failed"
        }
    }

    private func refreshWorkMemoryContext() async {
        async let home: Void = exocortex.refresh(activeProjectSlug: activeSlug, platform: "beagle-apple-work")
        async let graph: Void = exocortex.refreshRecentGraph(limit: 16)
        _ = await (home, graph)
    }

    // MARK: - Computed

    private var activeSlug: String {
        cognitive.activeProjectSlug ?? catalog.primaryProject?.projectSlug ?? "sounio"
    }

    private var runningAgentCount: Int {
        cognitive.state.value?.agentSessions?.filter { ($0.readyReplicas ?? 0) > 0 }.count ?? 0
    }

    private var latestWorkMemoryLine: String {
        if let latest = exocortex.home.value?.trustContext?.latestAgentWrite?.trimmingCharacters(in: .whitespacesAndNewlines),
           !latest.isEmpty {
            return latest
        }
        if let latest = exocortex.home.value?.agentContext?.lastAgentWrite?.trimmingCharacters(in: .whitespacesAndNewlines),
           !latest.isEmpty {
            return latest
        }
        if let atom = (exocortex.recentGraph?.value?.atoms ?? []).first(where: isWorkMemoryAtom) {
            let branch = atom.tags.first(where: { $0.hasPrefix("branch:") })?.replacingOccurrences(of: "branch:", with: "")
            let branchSuffix = branch.map { " · \($0)" } ?? ""
            return "\(atom.atomType)\(branchSuffix) · \(atom.text)"
        }
        return "No Codex or Claude Code work-memory atom observed yet."
    }

    private func isWorkMemoryAtom(_ atom: MemoryAtom) -> Bool {
        let haystack = (atom.tags + [atom.atomType, atom.text]).joined(separator: " ").lowercased()
        return haystack.contains("work-memory")
            || haystack.contains("codex")
            || haystack.contains("claude-code")
            || haystack.contains("agent:")
    }
}
