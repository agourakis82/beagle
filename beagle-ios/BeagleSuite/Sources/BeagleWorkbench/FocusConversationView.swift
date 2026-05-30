import SwiftUI
import BeagleCore

struct FocusConversationCanvas: View {
    @EnvironmentObject private var store: WorkbenchStore

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 18) {
                    ConversationStartingPoint()
                    ForEach(store.messages) { message in
                        FocusMessageRow(message: message)
                            .id(message.id)
                    }
                }
                .frame(maxWidth: 820, alignment: .leading)
                .padding(.top, 42)
                .padding(.horizontal, 32)
                .padding(.bottom, 128)
                .frame(maxWidth: .infinity)
            }
            .onChange(of: store.messages.count) { _, _ in
                if let last = store.messages.last {
                    withAnimation(.easeOut(duration: 0.15)) {
                        proxy.scrollTo(last.id, anchor: .bottom)
                    }
                }
            }
        }
    }
}

struct ConversationStartingPoint: View {
    @EnvironmentObject private var store: WorkbenchStore

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 5) {
                Text("Live Cockpit shell.")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(.primary)
                Text("Tabs on \(store.workspace.projectSlug) · composer \(store.composerDelivery.label) → \(store.resolvedDeliveryLabel). Multimodel chat: \(store.chatProjectSlug).")
                    .font(.system(size: 14, weight: .regular))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack(spacing: 10) {
                QuietAction(title: "Exocortex", icon: "brain.head.profile", prompt: "/exocortex What is the current workspace state?")
                QuietAction(title: "Make a plan", icon: "list.bullet.rectangle", prompt: "Turn this conversation into a concrete plan. No code yet.")
                QuietAction(title: "Give to Codex", icon: "hammer", prompt: "Prepare this as an implementation brief for Codex, including guardrails.")
            }
        }
        .padding(22)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(.quaternary, lineWidth: 1)
        }
    }
}

struct FocusMessageRow: View {
    let message: WorkbenchMessage

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Text(message.title ?? (message.role == .operatorRole ? "You" : "Agent"))
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                TruthBadge(message.truth, compact: true)
                Text(message.timestamp, style: .time)
                    .font(.system(size: 11, weight: .regular))
                    .foregroundStyle(.tertiary)
                if message.isStreaming {
                    ProgressView()
                        .controlSize(.mini)
                }
            }
            Text(message.content)
                .font(.system(size: 15, weight: .regular))
                .foregroundStyle(.primary)
                .lineSpacing(4)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.quaternary, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
    }
}

struct FocusInputBar: View {
    @EnvironmentObject private var store: WorkbenchStore
    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: 10) {
            TextField("Message, /send <text>, /exocortex, /graphrag, /whereami", text: $store.composerText, axis: .vertical)
                .font(.system(size: 15, weight: .regular))
                .lineLimit(1...4)
                .focused($focused)
                .textFieldStyle(.plain)
                .onSubmit {
                    store.sendComposerMessage()
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
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(.quaternary, lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.10), radius: 24, y: 12)
    }
}

struct QuietAction: View {
    @EnvironmentObject private var store: WorkbenchStore
    let title: String
    let icon: String
    let prompt: String

    var body: some View {
        Button {
            store.useStarter(prompt)
        } label: {
            Label(title, systemImage: icon)
                .font(.system(size: 13, weight: .regular))
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
        }
        .buttonStyle(.bordered)
    }
}
