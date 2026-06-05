import SwiftUI
import BeagleCore

struct ConnectionHealthView: View {
    @EnvironmentObject private var store: WorkbenchStore

    var body: some View {
        Form {
            Section("Endpoint") {
                TextField("Cockpit URL", text: $store.cockpitEndpoint)
                    .textFieldStyle(.roundedBorder)
                Button("Apply and refresh") {
                    Task { await store.refreshAll() }
                }
            }

            wireRow(
                title: "Catalog",
                wire: store.catalogWire,
                detail: "\(store.projects.count) project(s)"
            )
            wireRow(
                title: "Workspace",
                wire: store.workspaceWire,
                detail: "\(store.workspace.projectSlug) · \(store.workspace.status)"
            )
            wireRow(
                title: "Cluster ops",
                wire: store.clusterWire,
                detail: store.clusterWire.value?.status ?? "—"
            )
            wireRow(
                title: "Multimodel turns",
                wire: store.multimodelWire,
                detail: store.multimodelSocketConnected ? "\(store.chatProjectSlug) · WS" : store.chatProjectSlug
            )
            wireRow(
                title: "Workbench presence",
                wire: store.presenceWire,
                detail: "\(store.presenceClients.count) client(s)"
            )
            wireRow(
                title: "Exocortex",
                wire: store.exocortexWire,
                detail: store.lastExocortexPhi.map { String(format: "Φ=%.3f", $0) } ?? "not queried"
            )
            wireRow(
                title: "GraphRAG",
                wire: store.graphragWire,
                detail: "\(store.graphragWire.value?.nodeCount ?? 0) nodes"
            )
            wireRow(
                title: "Handoffs",
                wire: store.handoffsWire,
                detail: "\(store.handoffItems.count) open"
            )
            wireRow(
                title: "Providers",
                wire: store.providersWire,
                detail: store.chatProjectSlug
            )
            wireRow(
                title: "Zellij transport",
                wire: store.zellijStatusWire,
                detail: store.zellijStatusWire.value?.transport ?? "none"
            )
        }
        .formStyle(.grouped)
    }

    private func wireRow<T>(title: String, wire: Truthful<T>, detail: String) -> some View {
        Section(title) {
            HStack {
                TruthBadge(wire.mode, compact: true)
                Text(detail)
                    .font(.system(size: 12))
                Spacer()
                Text(wire.ageLabel)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            if let error = wire.error {
                Text(error)
                    .font(.system(size: 11))
                    .foregroundStyle(.orange)
            }
            if let source = wire.source {
                Text(source)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
        }
    }
}

struct WorkbenchConnectionBanner: View {
    @EnvironmentObject private var store: WorkbenchStore

    var body: some View {
        if !store.isLive {
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                Text(store.lastError ?? "Cockpit unreachable at \(store.cockpitEndpoint)")
                    .font(.system(size: 12))
                    .lineLimit(2)
                Spacer()
                Button("Retry") {
                    Task { await store.refreshAll() }
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(.orange.opacity(0.12))
        }
    }
}
