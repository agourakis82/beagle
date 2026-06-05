import SwiftUI
import BeagleCore

struct ComposerCommandDeck: View {
    @EnvironmentObject private var store: WorkbenchStore
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ComposerRoutingStrip()
            if store.resolvedDeliveryLabel == "Multimodel", !store.availableProviderIds.isEmpty {
                ComposerProviderStrip()
            }
            HStack(spacing: 10) {
                TextField(composerPlaceholder, text: $store.composerText, axis: .vertical)
                    .font(.system(size: 15, weight: .regular))
                    .lineLimit(1...5)
                    .focused($focused)
                    .textFieldStyle(.plain)
                    .onSubmit { store.sendComposerMessage() }

                if store.isStreamingMultimodel {
                    Button {
                        store.stopActiveMultimodelTurn()
                    } label: {
                        Image(systemName: "stop.circle.fill")
                            .font(.system(size: 26))
                            .symbolRenderingMode(.palette)
                            .foregroundStyle(.white, .orange)
                    }
                    .buttonStyle(.plain)
                    .help("Stop active multimodel turn")
                }

                Button {
                    store.sendComposerMessage()
                } label: {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 26, weight: .regular))
                }
                .buttonStyle(.plain)
                .disabled(store.composerText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(
                    store.isStreamingMultimodel ? Color.orange.opacity(0.35) : Color.primary.opacity(0.08),
                    lineWidth: 1
                )
        }
        .shadow(color: .black.opacity(0.12), radius: 28, y: 14)
    }

    private var composerPlaceholder: String {
        switch store.resolvedDeliveryLabel {
        case "Multimodel":
            return "Multimodel on \(store.chatProjectSlug) · /stop to cancel stream"
        case "Zellij tab":
            return "Send to tab \(store.selectedAgent?.zellijTabName ?? "…") · /send or Enter"
        default:
            return "Message · /send /whereami /exocortex /graphrag /stop"
        }
    }
}

struct ComposerRoutingStrip: View {
    @EnvironmentObject private var store: WorkbenchStore

    var body: some View {
        HStack(spacing: 8) {
            ForEach(ComposerDelivery.allCases, id: \.self) { mode in
                Button {
                    store.composerDelivery = mode
                } label: {
                    Text(mode.label)
                        .font(.system(size: 11, weight: store.composerDelivery == mode ? .semibold : .regular))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(
                            store.composerDelivery == mode ? Color.accentColor.opacity(0.18) : Color.primary.opacity(0.05),
                            in: Capsule()
                        )
                }
                .buttonStyle(.plain)
            }

            Spacer(minLength: 8)

            if store.resolvedDeliveryLabel == "Zellij tab" {
                Label(store.selectedAgent?.zellijTabName ?? "tab", systemImage: "terminal")
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.secondary)
            } else if store.resolvedDeliveryLabel == "Multimodel" {
                HStack(spacing: 4) {
                    Circle()
                        .fill(store.multimodelSocketConnected ? Color.green : Color.orange)
                        .frame(width: 7, height: 7)
                    Text(store.chatProjectSlug)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
            }

            if let transport = store.zellijStatusWire.value?.transport, transport != "none" {
                Text(transport)
                    .font(.system(size: 9, weight: .medium, design: .monospaced))
                    .foregroundStyle(.tertiary)
            }
        }
    }
}

struct ComposerProviderStrip: View {
    @EnvironmentObject private var store: WorkbenchStore

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(store.multimodelProviders.filter { store.availableProviderIds.contains($0.providerId ?? $0.rawId ?? $0.id) }) { provider in
                    let providerId = provider.providerId ?? provider.rawId ?? provider.id
                    let selected = store.selectedProviderIds.isEmpty
                        ? store.defaultProviderPreviewIds.contains(providerId)
                        : store.selectedProviderIds.contains(providerId)
                    Button {
                        store.toggleProviderSelection(providerId)
                    } label: {
                        Text(provider.label ?? providerId)
                            .font(.system(size: 11, weight: selected ? .semibold : .regular))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(
                                selected ? WorkbenchTone.agentColor(store.agentKind(for: providerId)).opacity(0.22) : Color.primary.opacity(0.05),
                                in: Capsule()
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}
