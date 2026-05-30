import SwiftUI
import BeagleCore

struct GraphRAGPanel: View {
    @EnvironmentObject private var store: WorkbenchStore
    @State private var query: String = "sounio workspace"
    @State private var queryMode: String = "local"

    private let queryModes = ["local", "handoff", "analysis"]

    var body: some View {
        Form {
            Section("Query") {
                TextField("Memory query", text: $query, axis: .vertical)
                    .lineLimit(2...4)
                Picker("Mode", selection: $queryMode) {
                    ForEach(queryModes, id: \.self) { mode in
                        Text(mode).tag(mode)
                    }
                }
                Button(store.isGraphRAGLoading ? "Querying…" : "Query GraphRAG") {
                    Task { await store.runGraphRAG(query: query, queryMode: queryMode) }
                }
                .disabled(store.isGraphRAGLoading || query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }

            if let result = store.graphragWire.value {
                if let datum = result.visDatum {
                    Section("Force graph") {
                        GraphRAGGraphView(datum: datum)
                    }
                }

                Section("Graph") {
                    LabeledContent("Nodes", value: "\(result.nodeCount ?? result.nodes?.count ?? 0)")
                    LabeledContent("Edges", value: "\(result.edgeCount ?? result.edges?.count ?? 0)")
                    if let mode = result.retrievalMode {
                        Text(mode)
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                    TruthBadge(graphTruth(result), compact: true)
                }

                if let highlights = result.highlights, !highlights.isEmpty {
                    Section("Highlights") {
                        ForEach(highlights.prefix(8)) { item in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(item.snippet ?? item.text ?? item.memoryId ?? "memory")
                                    .font(.system(size: 12))
                                    .lineLimit(4)
                                HStack {
                                    if let source = item.source {
                                        Text(source)
                                            .font(.system(size: 10, design: .monospaced))
                                            .foregroundStyle(.secondary)
                                    }
                                    if let relevance = item.relevance {
                                        Text(String(format: "%.2f", relevance))
                                            .font(.system(size: 10, design: .monospaced))
                                            .foregroundStyle(.tertiary)
                                    }
                                }
                            }
                        }
                    }
                } else {
                    Section("Highlights") {
                        Text("No memory highlights for this query (empty graph is honest).")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                    }
                }

                if let nodes = result.nodes, !nodes.isEmpty {
                    Section("Nodes") {
                        ForEach(nodes.prefix(12)) { node in
                            HStack {
                                Text(node.nodeType ?? "node")
                                    .font(.system(size: 10, weight: .semibold))
                                    .foregroundStyle(.secondary)
                                Text(node.displayName ?? node.nodeId ?? "—")
                                    .font(.system(size: 11))
                                    .lineLimit(1)
                            }
                        }
                    }
                }

                if let upstream = result.upstream {
                    Section("Upstream") {
                        if let memory = upstream.beagleMemory {
                            Text("beagle_memory: \(memory)")
                                .font(.system(size: 11, design: .monospaced))
                        }
                        if let error = upstream.error, !error.isEmpty {
                            Text(error)
                                .font(.system(size: 11))
                                .foregroundStyle(.orange)
                        }
                    }
                }
            }

            if let error = store.graphragWire.error {
                Section("Error") {
                    Text(error)
                        .foregroundStyle(.orange)
                        .font(.system(size: 12))
                }
            }
        }
        .formStyle(.grouped)
    }

    private func graphTruth(_ result: GraphRAGQueryResponse) -> TruthMode {
        TruthMode(rawValue: result.truthMode ?? "") ?? store.graphragWire.mode
    }
}
