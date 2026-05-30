import SwiftUI
import BeagleCore

struct FocusSidebar: View {
    @EnvironmentObject private var store: WorkbenchStore

    var body: some View {
        List(selection: $store.selectedProjectID) {
            Section("Projects") {
                ForEach(store.projects) { project in
                    Label(project.title, systemImage: project.id == "sounio" ? "curlybraces" : "folder")
                        .tag(project.id)
                }
            }

            if store.projects.isEmpty {
                Section("Cockpit") {
                    Text(store.isRefreshing ? "Loading projects…" : "No projects from Cockpit.")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
            }

            Section("Tabs") {
                ForEach(store.agents) { agent in
                    Button {
                        store.selectAgent(agent)
                    } label: {
                        HStack {
                            Label(agent.displayName, systemImage: "terminal")
                            Spacer()
                            if agent.status == .running {
                                Circle()
                                    .fill(agent.kind.color)
                                    .frame(width: 8, height: 8)
                            }
                        }
                    }
                }
            }

            if store.agents.isEmpty {
                Section("Workspace") {
                    Text("No zellij tabs reported.")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
            }

            Section("Composer") {
                Button {
                    store.cycleComposerDelivery()
                } label: {
                    HStack {
                        Label(store.composerDelivery.label, systemImage: "arrow.triangle.branch")
                        Spacer()
                        Text(store.resolvedDeliveryLabel)
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                }
                .buttonStyle(.plain)
                Text(store.composerDelivery.hint)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Section("Multimodel") {
                HStack {
                    Text("Chat: \(store.chatProjectSlug)")
                        .font(.system(size: 11, design: .monospaced))
                    Spacer()
                    Circle()
                        .fill(store.multimodelSocketConnected ? Color.green : Color.orange)
                        .frame(width: 8, height: 8)
                    Text(store.multimodelSocketConnected ? "WS live" : "HTTP fallback")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
                TruthBadge(store.multimodelWire.mode, compact: true)
            }
        }
        .listStyle(.sidebar)
    }
}
