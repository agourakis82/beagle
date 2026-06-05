import SwiftUI
import BeagleCore

struct ExocortexPanel: View {
    @EnvironmentObject private var store: WorkbenchStore
    @State private var query: String = "What is the current workspace state?"

    var body: some View {
        Form {
            Section("Query") {
                TextField("Ask the exocortex", text: $query, axis: .vertical)
                    .lineLimit(2...5)
                Button(store.isExocortexLoading ? "Processing…" : "Process") {
                    Task { await store.runExocortex(query: query) }
                }
                .disabled(store.isExocortexLoading || query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }

            if let result = store.exocortexWire.value {
                Section("Measurement") {
                    HStack {
                        Text("Φ")
                        Spacer()
                        Text(result.phi.map { String(format: "%.4f", $0) } ?? "—")
                            .font(.system(.body, design: .monospaced))
                    }
                    if let substrate = result.substrate, !substrate.isEmpty {
                        Text(substrate.joined(separator: ", "))
                            .font(.system(size: 11, design: .monospaced))
                    }
                    if let level = result.awarenessLevel {
                        Text("awareness: \(level)")
                            .font(.system(size: 12))
                    }
                    TruthBadge(exocortexTruth(result.truthMode), compact: true)
                    if let reason = result.declaredReason {
                        Text(reason)
                            .font(.system(size: 11))
                            .foregroundStyle(.orange)
                    }
                }

                if let response = result.response, !response.isEmpty {
                    Section("Response") {
                        Text(response)
                            .font(.system(size: 13))
                            .textSelection(.enabled)
                    }
                }
            }

            if let error = store.exocortexWire.error {
                Section("Error") {
                    Text(error)
                        .foregroundStyle(.orange)
                        .font(.system(size: 12))
                }
            }
        }
        .formStyle(.grouped)
    }

    private func exocortexTruth(_ raw: String?) -> TruthMode {
        TruthMode(rawValue: raw ?? "") ?? store.exocortexWire.mode
    }
}
