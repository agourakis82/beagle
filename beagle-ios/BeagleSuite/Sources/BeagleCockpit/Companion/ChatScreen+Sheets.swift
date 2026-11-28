//
//  ChatScreen+Sheets.swift
//  BeagleCockpit — Companion chat unified sheet routing & conversation history drawer
//

import SwiftUI
import BeagleCore
#if canImport(UIKit)
import UIKit
#endif

// MARK: - Sheet Routing

extension ChatScreen {
    @ViewBuilder
    func sheetContent(for sheet: ChatSheet) -> some View {
        switch sheet {
        case .history:
            ConversationDrawer(
                store: store,
                onOpenSettings: onOpenSettings.map { action in { pendingDrawerAction = action } },
                onOpenProject: onOpenProject.map { action in { pendingDrawerAction = action } },
                onOpenData: onOpenData.map { action in { pendingDrawerAction = action } },
                onOpenMemory: onOpenMemory.map { action in { pendingDrawerAction = action } },
                onOpenDreamInsights: onOpenDreamInsights.map { action in { pendingDrawerAction = action } },
                unreadDreamInsightCount: unreadDreamInsightCount,
                onOpenWork: onOpenWork.map { action in { pendingDrawerAction = action } },
                onOpenDailySynthesis: onOpenDailySynthesis.map { action in { pendingDrawerAction = action } },
                onOpenDeepExploration: onOpenDeepExploration.map { action in { pendingDrawerAction = action } }
            )
        case .goDeep(let prompt):
            GoDeepView(store: composerGoDeepStore, prompt: prompt)
        #if os(iOS)
        case .camera:
            CameraImagePicker { image in
                if let jpeg = image.jpegData(compressionQuality: 0.88) {
                    attachedImageData = jpeg
                    attachedDocument = nil
                }
            }
            .ignoresSafeArea()
        case .documentScanner:
            DocumentCameraScanner { image in
                if let jpeg = image.jpegData(compressionQuality: 0.90) {
                    attachedImageData = jpeg
                    attachedDocument = nil
                }
            }
            .ignoresSafeArea()
        #endif
        }
    }
}

// MARK: - Sheets

/// The single sheet the chat screen can present. One enum-driven sheet avoids the SwiftUI
/// multiple-`.sheet` conflict (which silently broke the history drawer).
enum ChatSheet: Identifiable {
    case history
    case goDeep(String)   // prompt to explore
    #if os(iOS)
    case camera
    case documentScanner
    #endif
    var id: String {
        switch self {
        case .history: return "history"
        case .goDeep: return "goDeep"
        #if os(iOS)
        case .camera: return "camera"
        case .documentScanner: return "documentScanner"
        #endif
        }
    }
}

// MARK: - Conversation history drawer (Fase 1 polishes: search, rename, pin UI)

/// The thread list — tap to switch, swipe to delete, + to start fresh. Best-in-class history
/// (Claude/ChatGPT) so the chat is many conversations, not one.
struct ConversationDrawer: View {
    let store: ConversationStore
    var onOpenSettings: (() -> Void)?
    var onOpenProject: (() -> Void)?
    var onOpenData: (() -> Void)?
    var onOpenMemory: (() -> Void)?
    var onOpenDreamInsights: (() -> Void)?
    var unreadDreamInsightCount: Int = 0
    var onOpenWork: (() -> Void)?
    var onOpenDailySynthesis: (() -> Void)?
    var onOpenDeepExploration: (() -> Void)?
    @Environment(\.dismiss) private var dismiss
    @State private var reloadToken = 0

    internal init(
        store: ConversationStore,
        onOpenSettings: (() -> Void)? = nil,
        onOpenProject: (() -> Void)? = nil,
        onOpenData: (() -> Void)? = nil,
        onOpenMemory: (() -> Void)? = nil,
        onOpenDreamInsights: (() -> Void)? = nil,
        unreadDreamInsightCount: Int = 0,
        onOpenWork: (() -> Void)? = nil,
        onOpenDailySynthesis: (() -> Void)? = nil,
        onOpenDeepExploration: (() -> Void)? = nil
    ) {
        self.store = store
        self.onOpenSettings = onOpenSettings
        self.onOpenProject = onOpenProject
        self.onOpenData = onOpenData
        self.onOpenMemory = onOpenMemory
        self.onOpenDreamInsights = onOpenDreamInsights
        self.unreadDreamInsightCount = unreadDreamInsightCount
        self.onOpenWork = onOpenWork
        self.onOpenDailySynthesis = onOpenDailySynthesis
        self.onOpenDeepExploration = onOpenDeepExploration
    }

    var body: some View {
        NavigationStack {
            List {
                let threads = store.conversations()
                if threads.isEmpty {
                    Text("Nenhuma conversa ainda.")
                        .font(BeagleFont.footnote.font)
                        .foregroundStyle(BeagleTheme.textSecondary)
                } else {
                    ForEach(threads, id: \.id) { conv in
                        Button {
                            store.switchTo(conversationId: conv.id)
                            dismiss()
                        } label: {
                            HStack(spacing: BeagleSpacing.sm) {
                                if conv.pinned {
                                    Image(systemName: "pin.fill")
                                        .font(.system(size: 10))
                                        .foregroundStyle(BeagleTheme.truthRemembered)
                                }
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(conv.displayTitle)
                                        .font(BeagleFont.body.font)
                                        .foregroundStyle(BeagleTheme.companionInk)
                                        .lineLimit(1)
                                    Text(conv.updatedAt, format: .relative(presentation: .named))
                                        .font(BeagleFont.caption2.font)
                                        .foregroundStyle(BeagleTheme.textSecondary)
                                }
                                Spacer()
                                if conv.id == store.currentConversationId {
                                    Image(systemName: "checkmark")
                                        .font(.system(size: 12, weight: .semibold))
                                        .foregroundStyle(BeagleTheme.truthObserved)
                                }
                            }
                        }
                        .swipeActions(edge: .trailing) {
                            Button(role: .destructive) {
                                store.deleteConversation(conv.id); reloadToken += 1
                            } label: { Label("Apagar", systemImage: "trash") }
                        }
                        .swipeActions(edge: .leading) {
                            Button {
                                store.togglePinned(conv.id); reloadToken += 1
                            } label: { Label("Fixar", systemImage: "pin") }
                            .tint(BeagleTheme.truthRemembered)
                        }
                    }
                }
                // Footer: memory + daily synthesis + deep exploration + data screen + settings + project.
                Section {
                    if onOpenDailySynthesis != nil {
                        Button { onOpenDailySynthesis?(); dismiss() } label: {
                            Label("Síntese matinal", systemImage: "sun.horizon.fill")
                        }
                        .foregroundStyle(BeagleTheme.companionInk.opacity(0.9))
                        .accessibilityIdentifier("chat.drawer.dailySynthesisButton")
                    }
                    if onOpenDeepExploration != nil {
                        Button { onOpenDeepExploration?(); dismiss() } label: {
                            Label("Modo Fundo", systemImage: "sparkle.magnifyingglass")
                        }
                        .foregroundStyle(BeagleTheme.companionInk.opacity(0.9))
                        .accessibilityIdentifier("chat.drawer.deepExplorationButton")
                    }
                    if onOpenMemory != nil {
                        Button { onOpenMemory?(); dismiss() } label: {
                            Label("O que eu lembro de ti", systemImage: "brain.head.profile")
                        }
                        .foregroundStyle(BeagleTheme.companionInk.opacity(0.9))
                        .accessibilityIdentifier("chat.drawer.memoryButton")
                    }
                    if onOpenDreamInsights != nil {
                        Button { onOpenDreamInsights?(); dismiss() } label: {
                            HStack {
                                Label("Insights da noite", systemImage: "moon.stars.fill")
                                if unreadDreamInsightCount > 0 {
                                    Spacer()
                                    Text("\(unreadDreamInsightCount)")
                                        .font(BeagleFont.caption2.font)
                                        .foregroundStyle(Color(hue: 270/360, saturation: 0.5, brightness: 0.9))
                                }
                            }
                        }
                        .foregroundStyle(BeagleTheme.companionInk.opacity(0.9))
                        .accessibilityIdentifier("chat.drawer.dreamInsightsButton")
                    }
                    if onOpenData != nil {
                        Button { onOpenData?(); dismiss() } label: {
                            Label("Dados", systemImage: "chart.xyaxis.line")
                        }
                        .foregroundStyle(BeagleTheme.companionInk.opacity(0.9))
                        .accessibilityIdentifier("chat.drawer.dataButton")
                    }
                    if onOpenWork != nil {
                        Button { onOpenWork?(); dismiss() } label: {
                            Label("Trabalho", systemImage: "bolt.fill")
                        }
                        .foregroundStyle(BeagleTheme.companionInk.opacity(0.9))
                        .accessibilityIdentifier("chat.drawer.workButton")
                    }
                    if onOpenProject != nil {
                        Button { onOpenProject?(); dismiss() } label: {
                            Label("Projeto", systemImage: "scope")
                        }
                        .foregroundStyle(BeagleTheme.companionInk.opacity(0.9))
                        .accessibilityIdentifier("chat.drawer.projectButton")
                    }
                    if onOpenSettings != nil {
                        Button { onOpenSettings?(); dismiss() } label: {
                            Label("Configurações", systemImage: "gearshape")
                        }
                        .foregroundStyle(BeagleTheme.companionInk.opacity(0.9))
                        .accessibilityIdentifier("chat.drawer.settingsButton")
                    }
                }
            }
            .id(reloadToken)
            .navigationTitle("Conversas")
            .navigationBarTitleDisplayMode(.inline)
            // Keep the native sheet material (the nice translucent glass) — just force dark so the
            // warm-white text reads. (Flattening to a solid canvas killed the material and the
            // tap targets; reverted.)
            .preferredColorScheme(.dark)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Fechar") { dismiss() }
                        .font(BeagleFont.caption.font)
                        .foregroundStyle(BeagleTheme.textSecondary)
                        .accessibilityIdentifier("chat.drawer.closeButton")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        store.newConversation(); dismiss()
                    } label: { Image(systemName: "square.and.pencil") }
                        .accessibilityLabel("Nova conversa")
                        .accessibilityIdentifier("chat.drawer.newChatButton")
                }
            }
        }
    }
}
