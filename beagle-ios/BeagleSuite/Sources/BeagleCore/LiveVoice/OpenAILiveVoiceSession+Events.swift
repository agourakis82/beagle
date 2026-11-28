//
//  OpenAILiveVoiceSession+Events.swift
//  BeagleCore — Loop WebSocket, tratamento de eventos e agrupamento de transcrições full-duplex
//

import Foundation

extension OpenAILiveVoiceSession {
    // MARK: - WebSocket Loop & Tratamento de Eventos

    func startReceiveLoop(for socket: URLSessionWebSocketTask) {
        receiveTask?.cancel()
        receiveTask = Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                while !Task.isCancelled {
                    let message = try await socket.receive()
                    let rawData: Data
                    switch message {
                    case .string(let text):
                        guard let d = text.data(using: .utf8) else { continue }
                        rawData = d
                    case .data(let d):
                        rawData = d
                    @unknown default:
                        continue
                    }

                    guard let parsed = OpenAILiveProtocol.parseServerEvent(rawData) else {
                        continue
                    }
                    self.handleServerEvent(parsed)
                    if parsed == .sessionClosed {
                        break
                    }
                }
            } catch {
                if self.isActive {
                    let msg = error.localizedDescription
                    self.setLastError(msg)
                    if !self.isConnected {
                        if let cont = self.sessionReadyContinuation {
                            self.sessionReadyContinuation = nil
                            cont.resume(returning: false)
                        }
                    } else {
                        self.onStartupFallbackNeeded?(msg)
                    }
                }
            }
        }
    }

    func handleServerEvent(_ event: OpenAILiveServerEvent) {
        switch event {
        case .sessionStarted(let id):
            markSessionStarted(id: id)
            if let cont = sessionReadyContinuation {
                sessionReadyContinuation = nil
                cont.resume(returning: true)
            }

        case .outputAudioDelta(let pcm16Data):
            guard isActive, !isPaused else { return }
            scheduleOutputPCM16(pcm16Data)

        case .inputTranscriptDelta(let delta, let startMs, let endMs):
            guard isActive, !delta.isEmpty else { return }
            handleUserTranscriptDelta(delta, startMs: startMs, endMs: endMs)

        case .outputTranscriptDelta(let delta, let startMs, let endMs):
            guard isActive, !delta.isEmpty else { return }
            handleAssistantTranscriptDelta(delta, startMs: startMs, endMs: endMs)

        case .delegationCreated(let delegationId, _, let offsetMs):
            guard isActive else { return }
            handleClientDelegationCreated(delegationId: delegationId, offsetMs: offsetMs)

        case .sessionClosed:
            if let cont = sessionClosedContinuation {
                sessionClosedContinuation = nil
                cont.resume()
            }

        case .error(let code, let message):
            // Erros não-fatais de validação/append mantêm a sessão viva; erros antes de conectar liberam o start.
            if code != "responses_validation_failed" && !isConnected {
                setLastError(message)
                if let cont = sessionReadyContinuation {
                    sessionReadyContinuation = nil
                    cont.resume(returning: false)
                }
            } else {
                setLastError(message)
            }

        case .inputAudioMuted, .inputAudioUnmuted, .contextAppended, .ignored:
            break
        }
    }

    // MARK: - Transcrições Full-Duplex & Agrupamento em Bolhas

    private func handleUserTranscriptDelta(_ delta: String, startMs: Int, endMs: Int) {
        let shouldOpenNewUserBubble = activeUserBubbleId == nil
            || (!activeAssistantText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && startMs >= max(0, lastAssistantEndMs - 300) && (startMs - lastUserEndMs) > 1_400)

        if shouldOpenNewUserBubble {
            if let prevId = activeUserBubbleId, !activeUserText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                onTranscriptBubbleUpdate?(.user, prevId, activeUserText.trimmingCharacters(in: .whitespacesAndNewlines), true, [])
            }
            activeUserBubbleId = UUID()
            activeUserText = ""
            turnCount += 1
        }

        activeUserText += delta
        lastUserEndMs = max(lastUserEndMs, endMs)
        hasNewUserSpeechSinceAssistantDelta = true
        appendToTimeline(role: .user, delta: delta, startMs: startMs, endMs: endMs)

        // Barge-in acústico natural: se o assistente tinha longa fila de áudio bufferizada e o usuário começou
        // uma fala substantiva nova (> 3 caracteres úteis), esvazia o buffer residual do alto-falante local.
        let trimmedDelta = delta.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedDelta.count >= 3,
           activeAssistantText.count >= 24,
           Date().timeIntervalSince(lastUserAudioInterruptAt) > 1.0 {
            #if os(iOS) || os(visionOS) || os(macOS)
            if scheduledOutputBuffers > 1 {
                lastUserAudioInterruptAt = .now
                flushLocalPlayback()
            }
            #endif
        }

        if let uid = activeUserBubbleId {
            let display = activeUserText.trimmingCharacters(in: .whitespacesAndNewlines)
            if !display.isEmpty {
                onTranscriptBubbleUpdate?(.user, uid, display, false, [])
                if activeDelegationCount == 0 {
                    emitPhaseUpdate(.listening, line: String(display.suffix(120)))
                }
            }
        }
    }

    private func handleAssistantTranscriptDelta(_ delta: String, startMs: Int, endMs: Int) {
        if activeAssistantBubbleId == nil || (hasNewUserSpeechSinceAssistantDelta && activeAssistantText.trimmingCharacters(in: .whitespacesAndNewlines).count >= 10) {
            if let prevUserId = activeUserBubbleId, !activeUserText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                onTranscriptBubbleUpdate?(.user, prevUserId, activeUserText.trimmingCharacters(in: .whitespacesAndNewlines), true, [])
                activeUserBubbleId = nil
                activeUserText = ""
            }
            if let prevAssistantId = activeAssistantBubbleId, !activeAssistantText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                onTranscriptBubbleUpdate?(.assistant, prevAssistantId, activeAssistantText.trimmingCharacters(in: .whitespacesAndNewlines), true, activeAssistantTools)
            }
            activeAssistantBubbleId = UUID()
            activeAssistantText = ""
            activeAssistantTools = []
        }

        hasNewUserSpeechSinceAssistantDelta = false
        activeAssistantText += delta
        lastAssistantEndMs = max(lastAssistantEndMs, endMs)
        appendToTimeline(role: .assistant, delta: delta, startMs: startMs, endMs: endMs)

        if let aid = activeAssistantBubbleId {
            let display = activeAssistantText.trimmingCharacters(in: .whitespacesAndNewlines)
            if !display.isEmpty {
                onTranscriptBubbleUpdate?(.assistant, aid, display, false, activeAssistantTools)
                if !isPaused {
                    emitPhaseUpdate(.speaking, line: String(display.suffix(120)))
                }
            }
        }
    }

    private func appendToTimeline(role: MessageRole, delta: String, startMs: Int, endMs: Int) {
        if let lastIdx = transcriptTimeline.indices.last,
           transcriptTimeline[lastIdx].role == role,
           (startMs - transcriptTimeline[lastIdx].endMs) < 2_500 {
            transcriptTimeline[lastIdx].text += delta
            transcriptTimeline[lastIdx].endMs = max(transcriptTimeline[lastIdx].endMs, endMs)
        } else {
            transcriptTimeline.append(
                OpenAILiveTranscriptSegment(role: role, text: delta, startMs: startMs, endMs: endMs)
            )
            if transcriptTimeline.count > 40 {
                transcriptTimeline.removeFirst(transcriptTimeline.count - 40)
            }
        }
    }

    func finalizeOpenBubblesIfNeeded() {
        if let uid = activeUserBubbleId {
            let trimmed = activeUserText.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                onTranscriptBubbleUpdate?(.user, uid, trimmed, true, [])
            }
        }
        if let aid = activeAssistantBubbleId {
            let trimmed = activeAssistantText.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                onTranscriptBubbleUpdate?(.assistant, aid, trimmed, true, activeAssistantTools)
            }
        }
        resetBubbleTrackers()
    }

    func resetBubbleTrackers() {
        activeUserBubbleId = nil
        activeUserText = ""
        lastUserEndMs = 0
        activeAssistantBubbleId = nil
        activeAssistantText = ""
        activeAssistantTools = []
        lastAssistantEndMs = 0
        hasNewUserSpeechSinceAssistantDelta = false
    }
}
