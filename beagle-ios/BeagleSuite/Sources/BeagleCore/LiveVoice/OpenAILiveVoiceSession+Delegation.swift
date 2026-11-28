//
//  OpenAILiveVoiceSession+Delegation.swift
//  BeagleCore — Client Delegation (`session.delegation.created`) e follow-ups assíncronos
//

import Foundation

extension OpenAILiveVoiceSession {
    // MARK: - Client Delegation (`session.delegation.created` → MoE / Bula / MCP / Apple Tools)

    func handleClientDelegationCreated(delegationId: String, offsetMs: Int) {
        guard let delegateHandler = onDelegateToBackend else { return }

        let window: [(role: String, text: String)] = transcriptTimeline.suffix(16).compactMap { seg in
            let clean = seg.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !clean.isEmpty else { return nil }
            return (role: seg.role == .user ? "user" : "assistant", text: clean)
        }
        let latestUser = transcriptTimeline.last(where: {
            $0.role == .user && !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        })?.text.trimmingCharacters(in: .whitespacesAndNewlines) ?? activeUserText.trimmingCharacters(in: .whitespacesAndNewlines)

        let context = OpenAILiveDelegationContext(
            delegationId: delegationId,
            offsetMs: offsetMs,
            transcriptWindow: window,
            latestUserUtterance: latestUser
        )

        adjustActiveDelegationCount(by: 1)
        emitPhaseUpdate(.thinking, line: "MoE · consultando exocórtex, Bula & ferramentas…")

        let task = Task { @MainActor [weak self] in
            guard let self else { return }
            defer {
                self.delegationTasks.removeValue(forKey: delegationId)
                self.adjustActiveDelegationCount(by: -1)
                if self.isActive && !self.isPaused && self.activeDelegationCount == 0 {
                    #if os(iOS) || os(visionOS) || os(macOS)
                    let speakingNow = self.scheduledOutputBuffers > 0
                    #else
                    let speakingNow = false
                    #endif
                    if !speakingNow {
                        self.emitPhaseUpdate(.listening, line: CompanionLiveVoicePhase.listening.defaultLinePtBR)
                    }
                }
            }

            if let progressPayload = OpenAILiveProtocol.buildContextAppendPayload(
                kind: .thinking,
                delegationId: delegationId,
                content: "Consultando o cérebro MoE do Beagle, memória GraphRAG++, Bula/PCDT e ferramentas nativas em segundo plano."
            ) {
                _ = await self.sendJSON(progressPayload)
            }

            let outcome = await delegateHandler(context)
            guard !Task.isCancelled, self.isActive else { return }

            if !outcome.executedTools.isEmpty {
                for tool in outcome.executedTools where !self.activeAssistantTools.contains(tool) {
                    self.activeAssistantTools.append(tool)
                }
                if let aid = self.activeAssistantBubbleId {
                    let display = self.activeAssistantText.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !display.isEmpty {
                        self.onTranscriptBubbleUpdate?(.assistant, aid, display, false, self.activeAssistantTools)
                    }
                }
            }

            if let facts = outcome.backgroundFacts, !facts.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
               let thinkingPayload = OpenAILiveProtocol.buildContextAppendPayload(
                   kind: .thinking,
                   delegationId: delegationId,
                   content: facts
               ) {
                _ = await self.sendJSON(thinkingPayload)
            }

            if let commentaryPayload = OpenAILiveProtocol.buildContextAppendPayload(
                kind: .commentary,
                delegationId: delegationId,
                content: outcome.spokenSummary
            ) {
                _ = await self.sendJSON(commentaryPayload)
            }
        }
        delegationTasks[delegationId] = task
    }

    /// Injeta assincronamente na sessão `gpt-live-1.1` o resultado de uma pesquisa profunda
    /// (`Modo Fundo`, `GPT-Rosalind` ou `Síntese Matinal`) iniciada em segundo plano durante a conversa por voz.
    public func pushAsyncFollowup(
        spokenSummary: String,
        backgroundFacts: String? = nil,
        executedTools: [String] = []
    ) async {
        guard isActive, isConnected else { return }

        if !executedTools.isEmpty {
            for tool in executedTools where !activeAssistantTools.contains(tool) {
                activeAssistantTools.append(tool)
            }
        }

        if let facts = backgroundFacts,
           !facts.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
           let thinkingPayload = OpenAILiveProtocol.buildContextAppendPayload(
               kind: .thinking,
               delegationId: nil,
               content: OpenAILiveProtocol.truncateForLiveAppend(facts, maxChars: 1_400)
           ) {
            _ = await sendJSON(thinkingPayload)
        }

        let cleanSpoken = OpenAILiveProtocol.truncateForLiveAppend(spokenSummary, maxChars: 1_200)
        guard !cleanSpoken.isEmpty else { return }
        if let commentaryPayload = OpenAILiveProtocol.buildContextAppendPayload(
            kind: .commentary,
            delegationId: nil,
            content: cleanSpoken
        ) {
            _ = await sendJSON(commentaryPayload)
        }
    }
}
