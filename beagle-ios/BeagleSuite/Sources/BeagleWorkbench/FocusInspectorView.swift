import SwiftUI
import BeagleCore

enum FocusInspectorTab: String, CaseIterable, Identifiable {
    case agent = "Agent"
    case zellij = "Zellij"
    case handoffs = "Handoffs"
    case connection = "Connection"
    case exocortex = "Exocortex"
    case graphrag = "GraphRAG"
    case memory = "Memory"

    var id: String { rawValue }
}

struct FocusInspector: View {
    @EnvironmentObject private var store: WorkbenchStore
    @Binding var selectedTab: FocusInspectorTab

    var body: some View {
        VStack(spacing: 0) {
            Picker("Inspector", selection: $selectedTab) {
                ForEach(FocusInspectorTab.allCases) { tab in
                    Text(tab.rawValue).tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 12)
            .padding(.top, 12)
            .padding(.bottom, 8)

            ScrollView {
                Group {
                    switch selectedTab {
                    case .agent:
                        agentForm
                    case .zellij:
                        ZellijDepthPanel()
                    case .handoffs:
                        HandoffsDepthPanel()
                    case .connection:
                        ConnectionHealthView()
                    case .exocortex:
                        ExocortexPanel()
                    case .graphrag:
                        GraphRAGPanel()
                    case .memory:
                        memoryForm
                    }
                }
            }
        }
    }

    private var agentForm: some View {
        Form {
            Section("Agent") {
                if let agent = store.selectedAgent {
                    LabeledContent("Name", value: agent.displayName)
                    LabeledContent("Tab", value: agent.zellijTabName)
                    LabeledContent("Status", value: agent.status.rawValue)
                    LabeledContent("Task", value: agent.currentTask)
                } else {
                    Text("No agent selected.")
                        .foregroundStyle(.secondary)
                }
            }

            Section("Chat slug") {
                Text(store.chatProjectSlug)
                    .font(.system(size: 12, design: .monospaced))
                Text("Multimodel turns use darwin-mfc; workspace default stays sounio.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }

            Section("Multimodel providers") {
                if store.multimodelProviders.isEmpty {
                    Text("No providers reported for \(store.chatProjectSlug).")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(store.multimodelProviders) { provider in
                        HStack {
                            Text(provider.label ?? provider.id)
                                .font(.system(size: 12, weight: .semibold))
                            Spacer()
                            Text(provider.status ?? "—")
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                TruthBadge(store.providersWire.mode, compact: true)
            }

            Section("Lease") {
                if let lane = store.selectedLane {
                    LabeledContent("Lane", value: lane.title)
                    LabeledContent("State", value: lane.leaseState.rawValue)
                    Text(store.leaseSummary)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
    }

    private var memoryForm: some View {
        Form {
            Section("Handoffs") {
                Text("Compose, reply, claim, and complete in the Handoffs inspector tab.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                if let summary = store.handoffsWire.value?.summary {
                    HStack {
                        Label("\(summary.waiting ?? 0) waiting", systemImage: "tray")
                        Label("\(summary.active ?? 0) active", systemImage: "bolt")
                    }
                    .font(.system(size: 11))
                }
                TruthBadge(store.handoffsWire.mode, compact: true)
            }

            Section("Presence") {
                if store.presenceClients.isEmpty {
                    Text("No MCP clients observed.")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(store.presenceClients) { client in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(client.clientId ?? "unknown")
                                .font(.system(size: 12, weight: .semibold))
                            Text("\(client.provider ?? "—") · \(client.status ?? "—")")
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                TruthBadge(store.presenceWire.mode, compact: true)
            }

            Section("Recent context") {
                if store.contextRecords.isEmpty {
                    Text("No recent workbench context records.")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(store.contextRecords.prefix(12)) { record in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(record.role ?? record.source ?? "record")
                                .font(.system(size: 11, weight: .semibold))
                            Text(record.content ?? "")
                                .font(.system(size: 11))
                                .lineLimit(4)
                        }
                    }
                }
            }
        }
        .formStyle(.grouped)
    }
}
