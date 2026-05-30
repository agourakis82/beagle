import SwiftUI
import BeagleCore

struct AgentTerminalCanvas: View {
    @EnvironmentObject private var store: WorkbenchStore
    @State private var ptyInput: String = ""
    @FocusState private var ptyFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            terminalHeader
            Divider()
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        if store.agentTerminalConnected || !store.agentTerminalText.isEmpty {
                            Text(store.displayAgentTerminalText)
                                .font(.system(size: 12, weight: .regular, design: .monospaced))
                                .foregroundStyle(Color(red: 0.78, green: 0.92, blue: 0.78))
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .id("pty-bottom")
                        } else if let preview = store.zellijScreenPreview, !preview.isEmpty {
                            zellijPreviewBlock(preview)
                        } else {
                            wireLogBlock
                        }
                    }
                    .padding(20)
                }
                .background(Color(red: 0.04, green: 0.05, blue: 0.07))
                .onChange(of: store.agentTerminalText) { _, _ in
                    withAnimation(.linear(duration: 0.08)) {
                        proxy.scrollTo("pty-bottom", anchor: .bottom)
                    }
                }
            }

            if store.agentTerminalKind != nil {
                ptyInputBar
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(store.agentTerminalConnected ? Color.green.opacity(0.35) : Color.white.opacity(0.08), lineWidth: 1)
        }
        .padding(.top, 40)
        .padding(.horizontal, 28)
        .padding(.bottom, 120)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear { store.ensureAgentTerminalForSelectedTab() }
        .onChange(of: store.selectedAgentID) { _, _ in
            store.ensureAgentTerminalForSelectedTab()
        }
        .onChange(of: store.selectedProjectID) { _, _ in
            store.ensureAgentTerminalForSelectedTab()
        }
    }

    private var terminalHeader: some View {
        HStack(spacing: 12) {
            Circle()
                .fill(store.agentTerminalConnected ? Color.green : Color.orange)
                .frame(width: 9, height: 9)
            VStack(alignment: .leading, spacing: 2) {
                Text(headerTitle)
                    .font(.system(size: 13, weight: .semibold))
                Text(headerSubtitle)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if store.agentSessionKindForSelectedTab() != nil {
                Button(store.agentTerminalConnected ? "Reconnect PTY" : "Connect PTY") {
                    store.connectAgentTerminalForSelectedTab(force: true)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
            Button {
                Task { await store.peekZellijScreen() }
            } label: {
                Label("Zellij", systemImage: "rectangle.split.3x1")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial)
    }

    private var headerTitle: String {
        if let kind = store.agentTerminalKind {
            return "Agent PTY · \(kind)"
        }
        return "Workspace terminal · \(store.workspace.sessionName)"
    }

    private var headerSubtitle: String {
        if let pod = store.agentTerminalPod {
            return "\(store.selectedProjectID) · \(pod)"
        }
        if let transport = store.zellijStatusWire.value?.transport {
            return "zellij \(transport) · tab \(store.selectedAgent?.zellijTabName ?? "—")"
        }
        return store.workspace.status
    }

    private var ptyInputBar: some View {
        HStack(spacing: 8) {
            TextField("Write to agent PTY…", text: $ptyInput)
                .font(.system(size: 12, design: .monospaced))
                .textFieldStyle(.plain)
                .focused($ptyFocused)
                .onSubmit { submitPTY() }
            Button("Send") { submitPTY() }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .disabled(ptyInput.isEmpty || !store.agentTerminalConnected)
        }
        .padding(12)
        .background(Color.black.opacity(0.35))
    }

    private func submitPTY() {
        let line = ptyInput
        guard !line.isEmpty else { return }
        ptyInput = ""
        store.sendAgentTerminalLine(line)
    }

    @ViewBuilder
    private func zellijPreviewBlock(_ preview: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Zellij screen · \(store.selectedAgent?.zellijTabName ?? "tab")", systemImage: "terminal")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
            Text(AgentTerminalFormatting.stripANSI(preview))
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(Color(red: 0.75, green: 0.85, blue: 1.0))
                .textSelection(.enabled)
        }
    }

    private var wireLogBlock: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(store.terminalLines.suffix(40)) { line in
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text(line.source)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .frame(width: 110, alignment: .leading)
                    Text(line.text)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.primary.opacity(0.85))
                }
            }
            if store.agentSessionKindForSelectedTab() == nil {
                Text("Select a claude* or codex* tab with a running agent pod, or peek zellij.")
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
                    .padding(.top, 8)
            }
        }
    }
}
