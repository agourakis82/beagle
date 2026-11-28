//
//  ConversationStore+Persistence.swift
//  BeagleCore
//
//  SwiftData persistence, multi-thread management, rolling episodic summaries,
//  CoreSpotlight indexing, offline outbox, and cluster memory synchronization.
//

import Foundation
import SwiftData

@MainActor
extension ConversationStore {

    // MARK: - Clear & Load

    /// Clear all messages.
    public func clear() {
        messages.removeAll()
        isStreaming = false
        guard let modelContext else { return }
        let conversationId = persistenceConversationId
        let descriptor = FetchDescriptor<PersistedMessage>(
            predicate: #Predicate<PersistedMessage> { message in
                message.conversationId == conversationId
            }
        )
        if let persisted = try? modelContext.fetch(descriptor) {
            for message in persisted {
                modelContext.delete(message)
            }
            try? modelContext.save()
        }
        Task.detached {
            await ConversationSpotlightIndexer.shared.removeConversation(id: conversationId)
        }
    }

    public func loadPersistedConversation() {
        guard let modelContext else { return }
        // Se nenhuma thread foi selecionada ainda na abertura do app, retoma automaticamente
        // a conversa mais recente com mensagens para não perder a continuidade entre sessões.
        if currentConversationId.isEmpty {
            if let mostRecent = conversations().first {
                currentConversationId = mostRecent.id
            }
        }
        let conversationId = persistenceConversationId
        let descriptor = FetchDescriptor<PersistedMessage>(
            predicate: #Predicate<PersistedMessage> { message in
                message.conversationId == conversationId
            },
            sortBy: [SortDescriptor(\PersistedMessage.sentAt, order: .forward)]
        )

        guard let persisted = try? modelContext.fetch(descriptor) else { return }
        var loaded: [ChatMessage] = []
        var pendingVisualTurn = false
        for stored in persisted {
            let role = MessageRole(rawValue: stored.role) ?? .assistant
            if role == .user {
                pendingVisualTurn = (stored.imageData != nil)
            }
            let parsedAgentKind: String?
            let parsedTools: [String]
            if let ak = stored.agentKind, ak.hasPrefix("tools:") {
                parsedAgentKind = nil
                parsedTools = ak.dropFirst("tools:".count).split(separator: ",").map(String.init)
            } else {
                parsedAgentKind = stored.agentKind
                parsedTools = []
            }
            loaded.append(ChatMessage(
                role: role,
                content: stored.content,
                timestamp: stored.sentAt,
                isStreaming: false,
                model: stored.model,
                tokensUsed: stored.tokensUsed,
                isLocal: stored.isLocal,
                source: stored.source,
                agentKind: parsedAgentKind,
                sessionId: stored.sessionId,
                podName: stored.podName,
                imageData: stored.imageData,
                imageLocalDigest: stored.imageExtractedText,
                hadVisualContext: role == .assistant ? pendingVisualTurn : false,
                executedTools: parsedTools
            ))
            if role == .assistant {
                pendingVisualTurn = false
            }
        }
        messages = loaded
        isStreaming = false
        refreshCurrentTitle()
        lastContactAt = messages.last(where: { $0.role == .user })?.timestamp
            ?? conversations().first?.updatedAt
        // Backfill a thread record for legacy/un-recorded conversations so they show in the drawer.
        if !messages.isEmpty {
            touchConversationRecord(firstUserText: messages.first(where: { $0.role == .user })?.content)
        }
        backfillRecentConversationsToSpotlightIfNeeded()
    }

    // MARK: - Rolling Episodic Summary & Cross-Thread Continuity

    public func currentRollingSummary() -> String? {
        guard let ctx = modelContext else { return nil }
        let id = persistenceConversationId
        let d = FetchDescriptor<PersistedConversation>(predicate: #Predicate<PersistedConversation> { $0.id == id })
        return (try? ctx.fetch(d).first)?.rollingSummary
    }

    public func recentCrossThreadDigest(maxThreads: Int = 3) -> String? {
        guard let ctx = modelContext else { return nil }
        let activeId = persistenceConversationId
        let others = conversations().filter { $0.id != activeId }.prefix(maxThreads)
        guard !others.isEmpty else { return nil }
        var lines: [String] = []
        for conv in others {
            if let roll = conv.rollingSummary, !roll.isEmpty {
                lines.append("• [\(conv.displayTitle)]: \(String(roll.prefix(240)))")
            } else {
                let cid = conv.id
                let md = FetchDescriptor<PersistedMessage>(
                    predicate: #Predicate<PersistedMessage> { $0.conversationId == cid },
                    sortBy: [SortDescriptor(\PersistedMessage.sentAt, order: .reverse)]
                )
                if let recentMsgs = try? ctx.fetch(md).prefix(2), !recentMsgs.isEmpty {
                    let snippet = recentMsgs.reversed().map { "\($0.role == "user" ? "D" : "B"): \(String($0.content.prefix(110)))" }.joined(separator: " / ")
                    lines.append("• [\(conv.displayTitle)]: \(snippet)")
                }
            }
        }
        return lines.isEmpty ? nil : lines.joined(separator: "\n")
    }

    private func maybeCompactRollingSummary() async {
        guard let ctx = modelContext else { return }
        let id = persistenceConversationId
        let d = FetchDescriptor<PersistedConversation>(predicate: #Predicate<PersistedConversation> { $0.id == id })
        guard let conv = try? ctx.fetch(d).first else { return }

        let total = messages.count
        let unsummarized = total - conv.summarizedMessageCount
        // Compacta quando acumulam >= 16 mensagens novas além da janela ativa
        guard total >= 20, unsummarized >= 12 else { return }

        let cutoff = max(0, total - 12)
        guard cutoff > conv.summarizedMessageCount else { return }
        let slice = messages[conv.summarizedMessageCount..<cutoff].map {
            (role: $0.role == .user ? "user" : "assistant", content: $0.content)
        }
        if let updated = await DirectBrainClient.shared.compactRollingSummary(
            existingSummary: conv.rollingSummary,
            newMessages: Array(slice)
        ) {
            conv.rollingSummary = updated
            conv.summarizedMessageCount = cutoff
            try? ctx.save()
        }
    }

    // MARK: - Threads (multi-conversation)

    /// All threads for the current project, pinned first then most-recently-updated.
    public func conversations() -> [PersistedConversation] {
        guard let ctx = modelContext else { return [] }
        let slug = projectSlug
        let d = FetchDescriptor<PersistedConversation>(
            predicate: #Predicate<PersistedConversation> { $0.projectSlug == slug },
            sortBy: [SortDescriptor(\.updatedAt, order: .reverse)]
        )
        let all = (try? ctx.fetch(d)) ?? []
        // Bool isn't Comparable for SortDescriptor — partition pinned-first, stable within each group.
        return all.filter { $0.pinned } + all.filter { !$0.pinned }
    }

    /// Start a fresh thread and switch to it (empty in-memory transcript).
    public func newConversation() {
        let id = "conv:\(UUID().uuidString.lowercased())"
        if let ctx = modelContext {
            ctx.insert(PersistedConversation(id: id, projectSlug: projectSlug, lastModel: discussionProfile.rawValue))
            try? ctx.save()
        }
        currentConversationId = id
        currentConversationTitle = "Nova conversa"
        messages = []
        isStreaming = false
        lastContactAt = nil
    }

    /// Switch to an existing thread and load its transcript.
    public func switchTo(conversationId id: String) {
        guard id != persistenceConversationId || messages.isEmpty else { return }
        currentConversationId = id
        loadPersistedConversation()
        refreshCurrentTitle()
        lastContactAt = messages.last(where: { $0.role == .user })?.timestamp
    }

    private func refreshCurrentTitle() {
        guard let ctx = modelContext else { return }
        let id = persistenceConversationId
        let d = FetchDescriptor<PersistedConversation>(predicate: #Predicate<PersistedConversation> { $0.id == id })
        currentConversationTitle = (try? ctx.fetch(d).first)?.displayTitle ?? "Nova conversa"
    }

    public func renameConversation(_ id: String, title: String) {
        guard let ctx = modelContext else { return }
        let d = FetchDescriptor<PersistedConversation>(predicate: #Predicate<PersistedConversation> { $0.id == id })
        if let conv = try? ctx.fetch(d).first {
            conv.title = title.trimmingCharacters(in: .whitespacesAndNewlines)
            conv.updatedAt = .now
            try? ctx.save()
            if id == persistenceConversationId { refreshCurrentTitle() }
            scheduleSpotlightIndex(for: id)
        }
    }

    public func togglePinned(_ id: String) {
        guard let ctx = modelContext else { return }
        let d = FetchDescriptor<PersistedConversation>(predicate: #Predicate<PersistedConversation> { $0.id == id })
        if let conv = try? ctx.fetch(d).first {
            conv.pinned.toggle()
            try? ctx.save()
        }
    }

    /// Delete a thread + its messages; if it was current, fall to the most-recent remaining (or a fresh one).
    public func deleteConversation(_ id: String) {
        guard let ctx = modelContext else { return }
        let md = FetchDescriptor<PersistedMessage>(predicate: #Predicate<PersistedMessage> { $0.conversationId == id })
        if let msgs = try? ctx.fetch(md) { for m in msgs { ctx.delete(m) } }
        let cd = FetchDescriptor<PersistedConversation>(predicate: #Predicate<PersistedConversation> { $0.id == id })
        if let convs = try? ctx.fetch(cd) { for c in convs { ctx.delete(c) } }
        try? ctx.save()
        Task.detached {
            await ConversationSpotlightIndexer.shared.removeConversation(id: id)
        }
        if persistenceConversationId == id {
            if let next = conversations().first {
                switchTo(conversationId: next.id)
            } else {
                newConversation()
            }
        }
    }

    /// Upsert the thread record (createdif missing, bump updatedAt, set title from the first user
    /// line if still untitled). Auto-title later upgrades to an LLM-generated title.
    private func touchConversationRecord(firstUserText: String?) {
        guard let ctx = modelContext else { return }
        let id = persistenceConversationId
        let slug = projectSlug
        let d = FetchDescriptor<PersistedConversation>(predicate: #Predicate<PersistedConversation> { $0.id == id })
        if let conv = try? ctx.fetch(d).first {
            conv.updatedAt = .now
            if (conv.title ?? "").isEmpty, let t = firstUserText { conv.title = Self.titleFrom(t) }
            conv.lastModel = discussionProfile.rawValue
        } else {
            let conv = PersistedConversation(id: id, projectSlug: slug, lastModel: discussionProfile.rawValue)
            if let t = firstUserText { conv.title = Self.titleFrom(t) }
            ctx.insert(conv)
        }
        try? ctx.save()
        refreshCurrentTitle()
    }

    private static func titleFrom(_ text: String) -> String {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "\n", with: " ")
        return String(t.prefix(48))
    }

    public func restoreContext(
        projectSlug: String,
        projectFamily: ProjectFamily?,
        publicationScope: PublicationScope?
    ) {
        self.projectSlug = projectSlug
        self.projectFamily = projectFamily
        self.publicationScope = publicationScope
        loadPersistedConversation()
    }

    func persist(message: ChatMessage) {
        guard let modelContext else { return }
        let encodedAgentKind: String? = {
            if let existing = message.agentKind, !existing.isEmpty { return existing }
            guard !message.executedTools.isEmpty else { return nil }
            return "tools:" + message.executedTools.joined(separator: ",")
        }()
        let persisted = PersistedMessage(
            role: message.role.rawValue,
            content: message.content,
            model: message.model,
            tokensUsed: message.tokensUsed,
            isLocal: message.isLocal,
            source: message.source,
            agentKind: encodedAgentKind,
            sessionId: message.sessionId,
            podName: message.podName,
            conversationId: persistenceConversationId,
            sentAt: message.timestamp,
            imageData: message.imageData,
            imageExtractedText: message.imageLocalDigest
        )
        modelContext.insert(persisted)
        try? modelContext.save()
        // Keep the thread record fresh (updatedAt for ordering; title from the first user line).
        let titleSeed: String? = {
            guard message.role == .user else { return nil }
            let trimmed = message.content.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty { return trimmed }
            if message.imageData != nil { return "Imagem compartilhada" }
            return nil
        }()
        touchConversationRecord(firstUserText: titleSeed)
        scheduleSpotlightIndex(for: persistenceConversationId)
    }

    // MARK: - CoreSpotlight Conversation Indexing

    public func spotlightSnapshot(for conversationId: String) -> SpotlightConversationSnapshot? {
        guard let ctx = modelContext else { return nil }
        let convDesc = FetchDescriptor<PersistedConversation>(
            predicate: #Predicate<PersistedConversation> { $0.id == conversationId }
        )
        let conv = try? ctx.fetch(convDesc).first
        let msgDesc = FetchDescriptor<PersistedMessage>(
            predicate: #Predicate<PersistedMessage> { $0.conversationId == conversationId },
            sortBy: [SortDescriptor(\.sentAt, order: .forward)]
        )
        let storedMsgs = (try? ctx.fetch(msgDesc)) ?? []
        guard !storedMsgs.isEmpty || !(conv?.rollingSummary ?? "").isEmpty else { return nil }

        let turns: [SpotlightMessageTurn] = storedMsgs.suffix(40).map { m in
            SpotlightMessageTurn(
                role: m.role,
                content: m.content,
                attachmentDigest: m.imageExtractedText,
                hasImage: m.imageData != nil
            )
        }
        return SpotlightConversationSnapshot(
            conversationId: conversationId,
            title: conv?.displayTitle ?? "Conversa no Beagle",
            projectSlug: conv?.projectSlug ?? projectSlug,
            updatedAt: conv?.updatedAt ?? storedMsgs.last?.sentAt ?? .now,
            rollingSummary: conv?.rollingSummary,
            turns: turns
        )
    }

    private func scheduleSpotlightIndex(for conversationId: String) {
        guard let snapshot = spotlightSnapshot(for: conversationId) else { return }
        Task.detached(priority: .utility) {
            await ConversationSpotlightIndexer.shared.index(snapshot)
        }
    }

    private func backfillRecentConversationsToSpotlightIfNeeded() {
        guard !hasBackfilledSpotlight, let ctx = modelContext else { return }
        hasBackfilledSpotlight = true
        let desc = FetchDescriptor<PersistedConversation>(
            sortBy: [SortDescriptor(\.updatedAt, order: .reverse)]
        )
        guard let recentConvs = try? ctx.fetch(desc).prefix(40), !recentConvs.isEmpty else { return }
        let snapshots = recentConvs.compactMap { spotlightSnapshot(for: $0.id) }
        guard !snapshots.isEmpty else { return }
        Task.detached(priority: .background) {
            await ConversationSpotlightIndexer.shared.indexBatch(snapshots)
        }
    }

    // MARK: - Offline Outbox & Cluster Memory Sync

    /// Queue an offline personal turn for later sync to the memory spine (online turns are
    /// ingested server-side during the chat, so only offline ones land here).
    private func enqueueOffline(userText: String) {
        guard let ctx = modelContext else { return }
        let assistant = messages.last(where: { $0.role == .assistant })?.content ?? ""
        OutboxStore(context: ctx).enqueue(
            sessionId: persistenceConversationId,
            userText: userText,
            assistantText: assistant,
            clientTime: ISO8601DateFormatter().string(from: Date()),
            timezone: TimeZone.current.identifier
        )
    }

    /// Drain the offline outbox to the cockpit. Idempotent server-side (content_hash), so a
    /// failed item simply stays queued for the next attempt.
    public func flushOutbox() async {
        guard let ctx = modelContext else { return }
        let store = OutboxStore(context: ctx)
        for item in store.pending() {
            let result = await CockpitClient.shared.ingestTurn(IngestTurnRequest(
                sessionId: item.sessionId, userText: item.userText, assistantText: item.assistantText,
                clientTime: item.clientTime, timezone: item.timezone))
            if result.value != nil { store.delete(item) }
        }
    }

    /// Sincroniza obrigatoriamente qualquer turno (Local Sem Censura, OpenAI Direto, Claude Direto ou MoE)
    /// com a espinha dorsal de memória do cluster (`/api/mobile/v1/ingest` + `/api/mobile/v1/memory/assisted-import`),
    /// garantindo fallback no `OutboxStore` se o cluster oscilar, além de atualizar o resumo episódico rolante.
    func syncTurnToClusterMemory(
        user: ChatMessage,
        assistant: ChatMessage,
        sourceSurface: String,
        alsoIngestSpine: Bool = true,
        vision: ChatVisionPayload? = nil
    ) async {
        let baseUserText = user.content.trimmingCharacters(in: .whitespacesAndNewlines)
        let userText: String = {
            if let digest = user.imageLocalDigest, !digest.isEmpty {
                return baseUserText.isEmpty
                    ? "[Imagem anexada — \(digest)]"
                    : "\(baseUserText)\n[Imagem anexada — \(digest)]"
            }
            return baseUserText
        }()
        let assistantText = assistant.content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !userText.isEmpty, !assistantText.isEmpty else { return }

        // Arquiva também o artefato visual privado no exocórtex do cluster quando online
        if let vision, NetworkMonitor.shared.isOnline {
            var hints = ["chat-multimodal", "vision-on-device"]
            if !vision.extractedOCR.isEmpty { hints.append("ocr") }
            if !vision.barcodes.isEmpty { hints.append("barcode") }
            let artifactReq = VisualEvidenceArtifactRequest(
                sessionId: persistenceConversationId,
                projectSlug: projectSlug,
                sourceSurface: sourceSurface,
                sourceKind: "chat_image",
                mediaType: vision.mimeType,
                contentHash: vision.sha256Hex,
                artifactDataBase64: vision.base64JPEG,
                artifactByteCount: vision.jpegData.count,
                localSummary: String(userText.prefix(360)),
                extractedText: vision.extractedOCR.isEmpty ? nil : vision.extractedOCR,
                localHints: hints,
                privacyClass: "sensitive",
                confirmationState: "private_cluster_artifact_only"
            )
            _ = await client.visualEvidenceArtifact(artifactReq)
        }

        if alsoIngestSpine {
            let nowISO = ISO8601DateFormatter().string(from: Date())
            let tz = TimeZone.current.identifier
            if NetworkMonitor.shared.isOnline {
                let res = await CockpitClient.shared.ingestTurn(IngestTurnRequest(
                    sessionId: persistenceConversationId,
                    userText: userText,
                    assistantText: assistantText,
                    clientTime: nowISO,
                    timezone: tz
                ))
                if res.value != nil {
                    if let i = messages.firstIndex(where: { $0.id == assistant.id }) {
                        messages[i].savedToMemory = true
                    }
                } else if let ctx = modelContext {
                    OutboxStore(context: ctx).enqueue(
                        sessionId: persistenceConversationId,
                        userText: userText,
                        assistantText: assistantText,
                        clientTime: nowISO,
                        timezone: tz
                    )
                }
            } else if let ctx = modelContext {
                OutboxStore(context: ctx).enqueue(
                    sessionId: persistenceConversationId,
                    userText: userText,
                    assistantText: assistantText,
                    clientTime: nowISO,
                    timezone: tz
                )
            }
        }

        var memoryUser = user
        memoryUser.content = userText
        await autoImportExchange(
            user: memoryUser,
            assistant: assistant,
            sourceSurface: sourceSurface
        )
        await maybeCompactRollingSummary()
    }

    func autoImportExchange(
        user: ChatMessage,
        assistant: ChatMessage,
        sourceSurface: String
    ) async {
        guard autoImportsConversationMemory else { return }
        let assistantText = assistant.content.trimmingCharacters(in: .whitespacesAndNewlines)
        let userText = user.content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !userText.isEmpty, !assistantText.isEmpty else { return }

        let request = AssistedImportRequestFactory.conversationExchange(
            userText: userText,
            assistantText: assistantText,
            sourceSurface: sourceSurface,
            sessionId: conversationImportSessionId,
            projectRef: projectSlug,
            model: assistant.model,
            flowState: flowState,
            bodySummary: physioContext,
            agentKind: assistant.agentKind,
            podName: assistant.podName
        )

        if request.privacyClass == "restricted" {
            enqueueAssistedImportOutbox(request, reason: "restricted_privacy_guard")
            autoImportState = ConversationAutoImportState(
                status: "blocked",
                sessionId: request.sessionId,
                queuedCount: queuedOutboxCount(),
                restrictedCount: restrictedOutboxCount(),
                lastError: "Restricted content held locally for explicit review."
            )
            return
        }

        autoImportState = ConversationAutoImportState(
            status: "importing",
            sessionId: request.sessionId,
            queuedCount: queuedOutboxCount(),
            restrictedCount: restrictedOutboxCount()
        )
        let result = await client.assistedImportBatch(request)
        guard let importResult = result.value, importResult.status == "imported" else {
            enqueueAssistedImportOutbox(request, reason: result.error ?? result.value?.reason ?? "auto_import_failed")
            autoImportState = ConversationAutoImportState(
                status: "queued",
                sessionId: request.sessionId,
                queuedCount: queuedOutboxCount(),
                restrictedCount: restrictedOutboxCount(),
                lastError: result.error ?? result.value?.reason
            )
            return
        }
        let atoms = importResult.projection?.atomsCreated ?? 0
        let episodes = importResult.projection?.episodesCreated ?? 0
        // Mark the assistant bubble so the UI can show "✓ Memory" — the idea is now recallable.
        if let i = messages.firstIndex(where: { $0.id == assistant.id }) {
            messages[i].savedToMemory = true
        }
        autoImportState = ConversationAutoImportState(
            status: "imported",
            sessionId: importResult.sessionId,
            lastImportedAt: AssistedImportRequestFactory.isoTimestamp(),
            lastSummary: "\(episodes) episode, \(atoms) atoms",
            queuedCount: queuedOutboxCount(),
            restrictedCount: restrictedOutboxCount()
        )
    }

    private func enqueueAssistedImportOutbox(_ request: AssistedImportBatchRequest, reason: String) {
        guard
            let modelContext,
            let data = try? assistedImportEncoder.encode(request),
            let payload = String(data: data, encoding: .utf8)
        else {
            return
        }
        modelContext.insert(PersistedAssistedImportOutbox(
            payload: payload,
            reason: reason,
            privacyClass: request.privacyClass,
            sourceSurface: request.sourceSurface
        ))
        try? modelContext.save()
    }

    private func queuedOutboxCount() -> Int {
        guard let modelContext else { return 0 }
        let descriptor = FetchDescriptor<PersistedAssistedImportOutbox>()
        return (try? modelContext.fetchCount(descriptor)) ?? 0
    }

    private func restrictedOutboxCount() -> Int {
        guard let modelContext else { return 0 }
        let descriptor = FetchDescriptor<PersistedAssistedImportOutbox>(
            predicate: #Predicate<PersistedAssistedImportOutbox> { item in
                item.privacyClass == "restricted"
            }
        )
        return (try? modelContext.fetchCount(descriptor)) ?? 0
    }
}
