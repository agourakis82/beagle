import SwiftUI
import BeagleCore

struct ZellijDepthPanel: View {
    @EnvironmentObject private var store: WorkbenchStore

    var body: some View {
        Form {
            Section("Transport") {
                if let status = store.zellijStatusWire.value {
                    LabeledContent("Mode", value: status.transport ?? "none")
                    if let target = status.target {
                        LabeledContent("Target", value: target)
                            .font(.system(size: 11, design: .monospaced))
                    }
                    if let path = status.zellijPath {
                        LabeledContent("zellij", value: path)
                            .font(.system(size: 11, design: .monospaced))
                    }
                    if let probe = status.probeError, !probe.isEmpty {
                        Text(probe)
                            .font(.system(size: 11))
                            .foregroundStyle(.orange)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    if let candidates = status.sshCandidates, !candidates.isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("SSH candidates")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(.secondary)
                            ForEach(candidates, id: \.self) { candidate in
                                Text(candidate)
                                    .font(.system(size: 10, design: .monospaced))
                            }
                        }
                    }
                } else {
                    Text("No zellij transport probe yet.")
                        .foregroundStyle(.secondary)
                }
                TruthBadge(store.zellijStatusWire.mode, compact: true)
                Button("Refresh transport") {
                    Task { await store.refreshZellijTransport() }
                }
            }

            Section("Selected tab") {
                if let agent = store.selectedAgent {
                    LabeledContent("Tab", value: agent.zellijTabName)
                    LabeledContent("Kind", value: agent.kind.displayName)
                    LabeledContent("Status", value: agent.status.rawValue)
                }
                Button(store.isZellijScreenLoading ? "Peeking…" : "Peek zellij screen") {
                    Task { await store.peekZellijScreen() }
                }
                .disabled(store.isZellijScreenLoading || store.selectedAgent == nil)
            }

            if let preview = store.zellijScreenPreview, !preview.isEmpty {
                Section("Screen dump") {
                    ScrollView {
                        Text(preview)
                            .font(.system(size: 10, design: .monospaced))
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(maxHeight: 260)
                }
            }

            Section("Agent pods") {
                if store.agentSessions.isEmpty {
                    Text("No agent StatefulSets reported for \(store.selectedProjectID).")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(Array(store.agentSessions.enumerated()), id: \.offset) { _, session in
                        HStack {
                            Text(session.kind ?? "agent")
                                .font(.system(size: 12, weight: .semibold))
                            Spacer()
                            Text(session.status ?? "—")
                                .font(.system(size: 11))
                                .foregroundStyle(session.status == "running" ? .green : .secondary)
                        }
                    }
                }
                Button("Refresh agent sessions") {
                    Task { await store.refreshAgentSessions() }
                }
            }

            Section("Composer routing") {
                LabeledContent("Mode", value: store.composerDelivery.label)
                LabeledContent("Resolved", value: store.resolvedDeliveryLabel)
                Text(store.composerDelivery.hint)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .formStyle(.grouped)
    }
}
