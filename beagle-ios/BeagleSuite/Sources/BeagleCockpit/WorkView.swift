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
    @State private var terminalInputText = ""
    @State private var showAgentSession = false
    @State private var showPlatform = false

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
            quickButton("Reconnect", icon: "arrow.clockwise", tint: terminal.connectionState.isConnected ? BeagleTheme.truthObserved : BeagleTheme.stateError) {
                connectTerminal()
            }
        }
        .padding(.vertical, BeagleSpacing.xs)
        .background(.ultraThinMaterial)
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

    // MARK: - Computed

    private var activeSlug: String {
        cognitive.activeProjectSlug ?? catalog.primaryProject?.projectSlug ?? "sounio"
    }

    private var runningAgentCount: Int {
        cognitive.state.value?.agentSessions?.filter { ($0.readyReplicas ?? 0) > 0 }.count ?? 0
    }
}
