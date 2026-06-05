import SwiftUI
import BeagleCore
#if os(macOS)
import AppKit
#endif

struct HandoffsDepthPanel: View {
    @EnvironmentObject private var store: WorkbenchStore
    @State private var sendSubject: String = "Workbench handoff"
    @State private var sendTo: String = "beagle-native"
    @State private var sendBody: String = ""
    @State private var replyText: String = ""
    @State private var compileQuery: String = ""
    @State private var copyStatus: String?

    var body: some View {
        Form {
            Section("Compose handoff") {
                TextField("To client", text: $sendTo)
                    .font(.system(size: 12, design: .monospaced))
                TextField("Subject", text: $sendSubject)
                TextField("Message", text: $sendBody, axis: .vertical)
                    .lineLimit(3...8)
                Button(store.isHandoffSending ? "Sending…" : "Send handoff") {
                    Task { await store.sendHandoff(subject: sendSubject, toClient: sendTo, content: sendBody) }
                }
                .disabled(store.isHandoffSending || sendBody.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }

            Section("Board") {
                if let summary = store.handoffsWire.value?.summary {
                    HStack {
                        boardChip("wait", summary.waiting ?? 0)
                        boardChip("active", summary.active ?? 0)
                        boardChip("stale", summary.stale ?? 0)
                        boardChip("done", summary.done ?? 0)
                    }
                    .font(.system(size: 10, design: .monospaced))
                }

                if store.handoffItems.isEmpty {
                    Text("No open handoffs on \(store.selectedProjectID).")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(store.handoffItems) { item in
                        handoffRow(item)
                    }
                }
                TruthBadge(store.handoffsWire.mode, compact: true)
                Button("Refresh board") {
                    Task { await store.refreshHandoffs() }
                }
            }

            if let selected = store.selectedHandoff {
                Section("Reply · \(selected.subject ?? selected.messageId ?? "handoff")") {
                    TextField("Reply text", text: $replyText, axis: .vertical)
                        .lineLimit(2...6)
                    HStack {
                        Button("Reply") {
                            Task { await store.replyHandoff(text: replyText) }
                        }
                        .disabled(replyText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        Button("Claim") {
                            Task { await store.claimSelectedHandoff() }
                        }
                        Button("Complete") {
                            Task { await store.completeSelectedHandoff() }
                        }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }

                handoffCompileSection(for: selected)
            }
        }
        .formStyle(.grouped)
        .onAppear {
            if sendBody.isEmpty {
                sendBody = store.defaultHandoffDraft()
            }
        }
    }

    @ViewBuilder
    private func handoffCompileSection(for selected: WorkbenchHandoffItem) -> some View {
        Section("Compile packet") {
            TextField("Optional RAG query override", text: $compileQuery, axis: .vertical)
                .lineLimit(1...3)
                .font(.system(size: 12, design: .monospaced))

            HStack {
                Button(store.isHandoffCompileLoading ? "Compiling…" : "Compile handoff") {
                    let query = compileQuery.trimmingCharacters(in: .whitespacesAndNewlines)
                    Task {
                        await store.compileSelectedHandoff(query: query.isEmpty ? nil : query)
                    }
                }
                .disabled(store.isHandoffCompileLoading)

                if let packet = store.handoffCompileWire.value, packet.handoff?.messageId == selected.messageId {
                    Button("Copy packet") {
                        copyHandoffPacket(packet)
                    }
                }
            }

            if let status = copyStatus {
                Text(status)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }

            if let packet = store.handoffCompileWire.value, packet.handoff?.messageId == selected.messageId {
                compilePacketBody(packet)
            } else if store.isHandoffCompileLoading {
                ProgressView("Building RAG++ packet…")
            } else {
                Text("Compile prepares thread, GraphRAG, highlights, and MCP reply instructions for \(selected.toClient ?? "target agent").")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private func compilePacketBody(_ packet: WorkbenchHandoffCompilePacket) -> some View {
        if let graph = packet.graph, let datum = graph.asQueryResponse.visDatum {
            GraphRAGGraphView(datum: datum)
                .frame(minHeight: 220)
        }

        if let retrieval = packet.retrieval {
            LabeledContent("Retrieval", value: retrieval.summary ?? "—")
            if let query = retrieval.query {
                Text(query)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            LabeledContent("Graph", value: "\(retrieval.nodeCount ?? 0) nodes · \(retrieval.edgeCount ?? 0) edges")
        }

        TruthBadge(handoffCompileTruth(packet), compact: true)

        if let instruction = packet.replyInstruction {
            Text(instruction)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }

        if let endpoint = packet.handoff?.replyEndpoint {
            Text(endpoint)
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(.tertiary)
                .textSelection(.enabled)
        }

        if let highlights = packet.highlights, !highlights.isEmpty {
            ForEach(highlights.prefix(6)) { item in
                VStack(alignment: .leading, spacing: 4) {
                    Text(item.snippet ?? item.text ?? item.memoryId ?? "memory")
                        .font(.system(size: 11))
                        .lineLimit(3)
                    if let source = item.source {
                        Text(source)
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }

        if let thread = packet.thread, !thread.isEmpty {
            DisclosureGroup("Thread (\(thread.count) turns)") {
                ForEach(thread.suffix(8)) { turn in
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(turn.role ?? "?") · \(turn.clientId ?? turn.source ?? "?")")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(.secondary)
                        Text(turn.text ?? "")
                            .font(.system(size: 11))
                            .lineLimit(4)
                    }
                }
            }
        }

        if let compiled = packet.compiledContextText, !compiled.isEmpty {
            ScrollView {
                Text(compiled)
                    .font(.system(size: 11, design: .monospaced))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
            }
            .frame(maxHeight: 180)
        }
    }

    @ViewBuilder
    private func handoffRow(_ item: WorkbenchHandoffItem) -> some View {
        Button {
            store.selectedHandoffID = item.messageId
            replyText = ""
            copyStatus = nil
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(item.subject ?? item.messageId ?? "handoff")
                        .font(.system(size: 12, weight: .semibold))
                    Spacer()
                    Text(item.status ?? "—")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(item.stale == true ? .orange : .secondary)
                }
                Text("\(item.fromClient ?? "?") → \(item.toClient ?? "?") · \(item.priority ?? "normal")")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.secondary)
                if let snippet = item.snippet, !snippet.isEmpty {
                    Text(snippet)
                        .font(.system(size: 11))
                        .foregroundStyle(.primary.opacity(0.85))
                        .lineLimit(3)
                }
            }
        }
        .buttonStyle(.plain)
        .padding(.vertical, 4)
        .background(
            store.selectedHandoffID == item.messageId ? Color.accentColor.opacity(0.08) : Color.clear,
            in: RoundedRectangle(cornerRadius: 8)
        )
    }

    private func boardChip(_ label: String, _ count: Int) -> some View {
        Text("\(label):\(count)")
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(.quaternary, in: Capsule())
    }

    private func handoffCompileTruth(_ packet: WorkbenchHandoffCompilePacket) -> TruthMode {
        packet.truthMode.flatMap(TruthMode.init(rawValue:)) ?? store.handoffCompileWire.mode
    }

    private func copyHandoffPacket(_ packet: WorkbenchHandoffCompilePacket) {
        let lines = [
            packet.compiledContextText ?? "",
            "",
            packet.replyInstruction ?? "",
            packet.handoff?.replyEndpoint.map { "REST: \($0)" } ?? ""
        ].filter { !$0.isEmpty }
        let text = lines.joined(separator: "\n")
        guard !text.isEmpty else { return }
        #if os(macOS)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        copyStatus = "Packet copied to clipboard."
        #else
        copyStatus = "Copy available on macOS."
        #endif
    }
}
