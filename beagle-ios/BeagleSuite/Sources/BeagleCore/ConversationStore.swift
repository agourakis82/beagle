//
//  ConversationStore.swift
//  BeagleCore
//
//  Observable conversation model for chat-style interactions.
//  Routes between on-device MLX (Tier 0.5) and cloud HERMES (Tier 2+).
//  On-device is preferred when model is loaded; cloud is fallback.
//

import Foundation
import SQLite3
import Observation
import SwiftData

// MARK: - Message model

public enum MessageRole: String, Sendable, Codable {
    case user
    case assistant
    case system
}

public struct ChatMessage: Identifiable, Sendable {
    public let id: UUID
    public let role: MessageRole
    public var content: String
    public let timestamp: Date
    public var isStreaming: Bool
    public var model: String?
    public var tokensUsed: Int?
    public var isLocal: Bool
    public var source: String?
    public var agentKind: String?
    public var sessionId: String?
    public var podName: String?
    /// Round Table: voice identity (e.g. "consciousness", "paradox", "quantum")
    public var voiceName: String?
    /// True once this exchange has been auto-imported into the cluster exocortex memory.
    public var savedToMemory: Bool = false
    /// True while this is an instant on-device "presence" acknowledgment (warm pt-BR opener) shown
    /// to bridge the cloud latency — replaced the moment the grounded cloud reply starts streaming.
    public var isProvisional: Bool = false
    /// Normalized JPEG image attached to this turn (nil for text/voice-only turns).
    public var imageData: Data? = nil
    /// Local Apple Vision OCR + classification digest extracted on-device.
    public var imageLocalDigest: String? = nil
    /// True on assistant replies that answered a visual turn.
    public var hadVisualContext: Bool = false
    /// Native iPhone / MCP tool names executed during this assistant turn (for provenance chips).
    public var executedTools: [String] = []

    public init(
        id: UUID = UUID(),
        role: MessageRole,
        content: String,
        timestamp: Date = .now,
        isStreaming: Bool = false,
        model: String? = nil,
        tokensUsed: Int? = nil,
        isLocal: Bool = false,
        source: String? = nil,
        agentKind: String? = nil,
        sessionId: String? = nil,
        podName: String? = nil,
        voiceName: String? = nil,
        imageData: Data? = nil,
        imageLocalDigest: String? = nil,
        hadVisualContext: Bool = false,
        executedTools: [String] = []
    ) {
        self.id = id
        self.role = role
        self.content = content
        self.timestamp = timestamp
        self.isStreaming = isStreaming
        self.model = model
        self.tokensUsed = tokensUsed
        self.isLocal = isLocal
        self.source = source
        self.agentKind = agentKind
        self.sessionId = sessionId
        self.podName = podName
        self.voiceName = voiceName
        self.imageData = imageData
        self.imageLocalDigest = imageLocalDigest
        self.hadVisualContext = hadVisualContext
        self.executedTools = executedTools
    }
}

// MARK: - Store

@Observable
@MainActor
public final class ConversationStore {

    public private(set) var messages: [ChatMessage] = []
    public private(set) var isStreaming: Bool = false
    /// Presence LAYER — never the letter. The server writes a presence/phase event at t≈0
    /// of the ~25s wait so the silence reads as listening. It lives outside `messages` on
    /// purpose: server-authored text must never end up in the slot that renders as HIS voice
    /// (desenho 2026-08-02, item 4 vs item 5). Cleared the instant a real token arrives.
    public private(set) var presenceNote: String? = nil
    public private(set) var autoImportState: ConversationAutoImportState = .idle

    /// When the user last sent a cloud message — the client owns the thread, so it sends
    /// this so the companion knows how long since they last talked (temporal awareness).
    private var lastContactAt: Date?

    /// Whether to prefer on-device model when available.
    public var preferLocal: Bool = true
    public var autoImportsConversationMemory: Bool = true
    public var projectSlug: String
    public var projectFamily: ProjectFamily?
    public var publicationScope: PublicationScope?
    public var discussionProfile: DiscussionProfile = .cluster
    /// Depth gear for the personal-voice path: nil = "Rápido" (server default voice); a model name
    /// (e.g. "glm-5.2" for "Pensar") asks the companion to think with a stronger model. "Fundo" is
    /// handled in the UI by routing to Go-Deeper instead of a chat turn.
    public var voiceModel: String? = nil

    /// Live Activity hooks (set by the view layer, since LiveActivityManager is in BeagleCockpit) —
    /// mirrors the GoDeepStore onResearch* pattern. Lets the user leave the app during the ~14-20s
    /// premium-voice wait (Opus/GPT) and see "pensando…" → the reply resolve on the lock screen.
    public var onCompanionTurnStart: ((String, String) -> Void)?
    public var onCompanionTurnEnd: ((String?) -> Void)?

    /// Async hooks for full-duplex `gpt-live-1.1` deep background delegations (`Modo Fundo` / `Rosalind` / `Síntese Matinal`).
    public var onTriggerAsyncVoiceFollowup: ((String, String?, [String]) async -> Void)?
    public var onVoiceResearchStart: ((String, String, String, Int, String?) -> Void)?
    public var onVoiceResearchUpdate: ((Int, Int, Int, String?, String?, Bool) -> Void)?

    /// Friendly voice name for the Live Activity — mirrors ChatDepth's labels (BeagleCockpit layer,
    /// not importable from here) so the lock screen says "Sonnet 5" instead of "claude-sonnet-5".
    private func voiceLabel(for model: String?) -> String {
        if let friendly = OpenAIModelCatalog.friendlyVoiceLabel(for: model) {
            return friendly
        }
        switch model {
        case "moe": return "MoE Completo"
        case "local-uncensored": return "Local Sem Censura"
        case "claude-sonnet-5": return "Sonnet 5"
        case "claude-opus-4-8": return "Opus 4.8"
        case "grok": return "Grok 4.3"
        case "glm-5.2": return "GLM 5.2"
        case "kimi-k2.6": return "Kimi 2.6"
        case "minimax-m3": return "MiniMax M3"
        default: return "Beagle"
        }
    }
    public var modelContext: ModelContext?

    private let client: BeagleClient
    /// Sinal de tom do turno que ele acabou de FALAR — ritmo e pausa, derivados no
    /// aparelho. O áudio nunca sai do iPhone.
    ///
    /// Consumido uma vez por turno: sem isso, a mensagem DIGITADA seguinte herdaria
    /// o tom da fala anterior, e o companion falaria de um "agora" que já passou.
    public var sinalDeVozDoTurno: (wpm: Double?, pausa: Double)?

    private let llm = LocalLLMEngine.shared
    private let assistedImportEncoder = JSONEncoder()
    private let conversationImportSessionId = "beagle-apple-chat-\(UUID().uuidString.lowercased())"

    public init(
        client: BeagleClient = .shared,
        preferLocal: Bool = true,
        projectSlug: String = "sounio",
        projectFamily: ProjectFamily? = nil,
        publicationScope: PublicationScope? = nil
    ) {
        self.client = client
        self.preferLocal = preferLocal
        self.projectSlug = projectSlug
        self.projectFamily = projectFamily
        self.publicationScope = publicationScope
        // Drain the offline outbox to the memory spine the moment connectivity returns.
        NetworkMonitor.shared.onReconnect = { [weak self] in
            Task { @MainActor in
                await self?.flushOutbox()
                // Voltou a rede: a nuvem responde e os 4,29 GB viram só risco.
                LocalLLMEngine.shared.unload()
            }
        }
        // Aquece o modelo local na abertura, se os pesos já estiverem aqui.
        // Carregar 8B leva dezenas de segundos; pagar isso quando a rede já caiu
        // é pagar no pior momento possível.
        print(String(format: "[Beagle] RAM fisica: %.2f GB", LocalLLMEngine.ramGBMedida))
        // Carregar o modelo na ABERTURA matava o app: o iOS mata em
        // per-process-limit ~6,45 GB e os pesos sozinhos são 4,29 GB. Online ele
        // não precisa do modelo — então só carrega quando a rede cai, e devolve
        // a memória quando ela volta.
        NetworkMonitor.shared.onDisconnect = {
            Task { @MainActor in await LocalLLMEngine.shared.restaurarUltimoModelo() }
        }
    }

    /// The active thread's id. Empty → falls back to the legacy single-thread id so an
    /// existing conversation keeps loading until the user starts/switches a thread.
    public private(set) var currentConversationId: String = ""
    /// Observable title of the active thread (for the chat top bar). Updates when the thread
    /// is created, switched, or auto-titled from the first user line.
    private var hasBackfilledSpotlight: Bool = false
    public private(set) var currentConversationTitle: String = "Nova conversa"

    public var persistenceConversationId: String {
        currentConversationId.isEmpty ? "home:\(projectSlug)" : currentConversationId
    }

    // MARK: - Send (auto-routing)

    /// HRV-aware flow state for routing decisions.
    public var flowState: String? = nil
    /// Last night's sleep quality, 0–1 (deep+REM ratio). Feeds the attuned body-as-story greeting.
    public var sleepQuality01: Double? = nil
    public var physioContext: String? = nil
    public var companionContext: String? = nil
    public var behaviorContext: String? = nil
    public var noteTakingContext: String? = nil
    public var physioPolicy: PhysioConversationPolicy? = nil
    /// Live body + sky, set by the view (same source as the aura/strip). Sent raw so the
    /// server's `## Agora` block matches exactly what the screen shows.
    public var physioSummary: PhysioSummary? = nil
    public var currentSky: SpaceWeatherStore.Snapshot? = nil

    /// Fast on-device responder (Apple Foundation Models), injected by the app layer
    /// (BeagleCore can't reach BeagleCockpit). Light/casual messages route here for an
    /// instant reply; deep ones go to the cloud. Hybrid: on-device for light, cluster for deep.
    public var fastResponder: ((String, [String]) async -> String?)? = nil
    public var fastAvailable: Bool = false
    /// Instant on-device "presence" acknowledgment (Apple Foundation Models). Given the user's
    /// message, returns ONE warm pt-BR opener that bridges the cloud latency — it does NOT answer.
    /// nil/unavailable → the chat just shows the typing indicator as before.
    public var quickAck: ((String) async -> String?)? = nil

    /// Demo seed for screenshots/previews — a warm, attuned sample exchange. No-op if the
    /// conversation already has messages.
    public func seedDemoConversation() {
        guard messages.isEmpty else { return }
        messages = [
            ChatMessage(role: .user, content: "Acordei meio pra baixo hoje, não sei bem por quê."),
            ChatMessage(role: .assistant,
                content: "Faz sentido. Você dormiu leve e o coração andou tenso essa noite — às vezes o corpo sente antes da gente entender. Quer me contar como foi a noite?",
                source: "physiome"),
            ChatMessage(role: .user, content: "Acho que foi a apresentação de amanhã martelando na cabeça."),
            ChatMessage(role: .assistant,
                content: "A gente já passou por isso antes — e você costuma chegar mais inteiro do que imagina. Quer ensaiar o começo comigo agora, ou prefere só descarregar um pouco?",
                source: "exocortex"),
        ]
    }

    /// Send a message with HRV-gated routing:
    /// FLOW → cloud (deep reasoning worth the latency)
    /// NORMAL → local MLX (balanced)
    /// STRESS → Foundation Models (fast, don't overwhelm)
    public func sendMessage(
        _ text: String,
        imageData: Data? = nil,
        document: ChatDocumentPayload? = nil
    ) async {
        // O tom vale para ESTE turno. `defer` roda depois de todos os awaits, então
        // o sinal chega às chamadas do cliente e some antes do turno seguinte —
        // senão a próxima mensagem digitada herdaria a fala anterior.
        defer { sinalDeVozDoTurno = nil }

        // Prepara payload multimodal fora da main thread (redimensiona <=1568px JPEG + OCR/cena Apple Vision).
        // Quando há PDF anexado sem imagem separada, usa a capa renderizada da Página 1 para visão + miniatura.
        let effectiveImageData = imageData ?? document?.coverJPEGData
        let vision: ChatVisionPayload?
        if let effectiveImageData, !effectiveImageData.isEmpty {
            vision = await ChatVisionPayload.prepare(from: effectiveImageData)
        } else {
            vision = nil
        }

        // Detecta automaticamente URLs, DOIs (10.xxxx/...), PMIDs e arXiv IDs na mensagem ou vindos do Share Sheet
        // e busca os metadados/abstracts/texto ao vivo antes do turno, valendo para TODOS os cérebros (inclusive Local Sem Censura).
        let detectedRefs = ScienceAndWebBridge.extractReferences(from: text)
        let webPrefetch: (contextBlock: String, executedTools: [String])?
        if !detectedRefs.isEmpty && NetworkMonitor.shared.isOnline {
            let previousPresence = presenceNote
            presenceNote = "lendo link / artigo compartilhado…"
            webPrefetch = await ScienceAndWebBridge.shared.prefetchContextForPrompt(text)
            if presenceNote == "lendo link / artigo compartilhado…" {
                presenceNote = previousPresence
            }
        } else {
            webPrefetch = nil
        }

        // Se o usuário escolheu explicitamente "Local Sem Censura", roda direto no modelo local MLX
        // (com grounding completo, fisioma ao vivo, OCR/PDF, links/PubMed/DOI, bula/PCDT e sincronização com a memória do cluster).
        if voiceModel == "local-uncensored" {
            var pronto = llm.isReady
            if !pronto { pronto = await llm.restaurarUltimoModelo() }
            if pronto {
                await sendMessageLocal(text, vision: vision, document: document, webPrefetch: webPrefetch)
                if NetworkMonitor.shared.isOnline {
                    Task { @MainActor [weak self] in await self?.refreshGroundingIfStale() }
                }
                return
            }
        }

        // Light, casual messages → instant on-device Apple Intelligence (never used when an attachment, link/DOI, or explicit voice is selected).
        if vision == nil, document == nil, detectedRefs.isEmpty, voiceModel == nil, isLight(text), fastAvailable, fastResponder != nil {
            await sendMessageFast(text)
            return
        }
        // Companion: cloud / Direct OpenAI / MoE / Claude when online; the on-device
        // MLX model when offline — and enqueue the offline turn so the memory spine receives it
        // once connectivity returns. `flowState` still travels in the cloud request body.
        if NetworkMonitor.shared.isOnline {
            await sendMessageCloud(text, vision: vision, document: document, webPrefetch: webPrefetch)
        } else {
            // Sem rede. O engine esquece o modelo a cada abertura do app, então
            // tentar restaurar AQUI é a diferença entre responder e não existir.
            // Só carrega o que já está no aparelho: nunca baixa GB no celular.
            var pronto = llm.isReady
            if !pronto { pronto = await llm.restaurarUltimoModelo() }
            if pronto {
                await sendMessageLocal(text, vision: vision, document: document, webPrefetch: webPrefetch)
            } else {
                await sendMessageCloud(text, vision: vision, document: document, webPrefetch: webPrefetch)
            }
        }
        // Mantém o grounding offline fresco enquanto há rede. Fire-and-forget: nunca
        // atrasa a resposta, nunca derruba o turno.
        if NetworkMonitor.shared.isOnline {
            Task { @MainActor [weak self] in await self?.refreshGroundingIfStale() }
        }
    }

    private static func composeUserBubbleContent(text: String, document: ChatDocumentPayload?) -> String {
        guard let document else { return text }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty || trimmed == "Analisa este documento PDF comigo." {
            return "📄 \(document.summaryBadge)"
        }
        return "📄 \(document.summaryBadge)\n\(text)"
    }

    private static func composePersistedAttachmentDigest(
        vision: ChatVisionPayload?,
        document: ChatDocumentPayload?,
        webBlock: String? = nil
    ) -> String? {
        var parts: [String] = []
        if let doc = document {
            let excerpt = String(doc.extractedText.prefix(2_400))
            if excerpt.isEmpty {
                parts.append("PDF anexado: \(doc.summaryBadge)")
            } else {
                parts.append("PDF anexado (\(doc.summaryBadge)):\n\(excerpt)")
            }
        }
        if let v = vision?.localDigest, !v.isEmpty {
            parts.append(v)
        }
        if let w = webBlock, !w.isEmpty {
            parts.append(String(w.prefix(1_600)))
        }
        return parts.isEmpty ? nil : parts.joined(separator: "\n")
    }

    private static func mergeUniqueTools(_ groups: [[String]]) -> [String] {
        var seen: Set<String> = []
        var out: [String] = []
        for g in groups {
            for item in g where seen.insert(item).inserted {
                out.append(item)
            }
        }
        return out
    }

    /// Atualiza o cache de identidade quando está ausente ou com mais de 2h.
    public func refreshGroundingIfStale() async {
        if let at = groundingCachedAt, Date().timeIntervalSince(at) < 7200 { return }
        let result = await client.companionGrounding()
        // Nunca troque um cache bom por um pacote raquítico: offline, esse texto
        // é tudo o que ele sabe. O servidor já recusa abaixo de 2000 bytes; aqui
        // é a segunda parede, para o caso de um gateway devolver algo truncado.
        guard let system = result.value?.system, system.utf8.count >= 2000 else { return }
        storeGrounding(system)
    }

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

    /// A short, casual message worth answering instantly on-device.
    private func isLight(_ text: String) -> Bool {
        text.trimmingCharacters(in: .whitespacesAndNewlines).count <= 140
    }

    /// Instant on-device reply via the injected fast responder (Apple Foundation Models).
    public func sendMessageFast(_ text: String) async {
        let history = messages.suffix(8).map { "\($0.role == .user ? "User" : "Assistant"): \($0.content)" }
        let userMessage = ChatMessage(role: .user, content: text)
        messages.append(userMessage)
        persist(message: userMessage)

        let assistantId = UUID()
        messages.append(ChatMessage(id: assistantId, role: .assistant, content: "", isStreaming: true))
        isStreaming = true

        let reply = await fastResponder?(text, history) ?? nil

        if let idx = messages.firstIndex(where: { $0.id == assistantId }) {
            if let reply, !reply.isEmpty {
                messages[idx].model = "apple-intelligence"
                messages[idx].isLocal = true
                await revealText(reply, for: assistantId)
                messages[idx].isStreaming = false
                persist(message: messages[idx])
            } else {
                // On-device came back empty → hand this turn to the cloud on the same bubble.
                let history2 = messages.dropLast().suffix(10)
                    .map { "\($0.role == .user ? "User" : "Assistant"): \($0.content)" }
                    .joined(separator: "\n")
                let prompt = history2.isEmpty ? text : "\(history2)\nUser: \(text)"
                let result = await client.chat(prompt: prompt, system: activeSystemInstruction,
                    projectSlug: projectSlug, projectFamily: projectFamily,
                    publicationScope: publicationScope, discussionProfile: discussionProfile,
                    flowState: flowState, physioPolicy: physioPolicy,
                    hrvMs: physioSummary?.hrvMs,
            voiceWpm: sinalDeVozDoTurno?.wpm, voicePausa: sinalDeVozDoTurno?.pausa,
            readiness: physioSummary?.readiness.rawValue,
                    sleepHours: physioSummary?.sleepHours,
                    kp: currentSky?.kp, dst: currentSky?.dst,
                    solarWind: currentSky?.solarWindSpeed, bz: currentSky?.bz)
                let full = result.value?.response ?? "Tô meio devagar agora — me dá um instante e tenta de novo?"
                messages[idx].source = result.value?.source
                await revealText(full, for: assistantId)
                messages[idx].isStreaming = false
                persist(message: messages[idx])
            }
        }
        isStreaming = false
    }

    private var activeSystemInstruction: String? {
        let contextLines = [companionContext, physioContext, behaviorContext, noteTakingContext]
            .compactMap { value -> String? in
                guard let value, !value.isEmpty else { return nil }
                return value
            }

        guard !contextLines.isEmpty else { return nil }
        return contextLines.joined(separator: "\n")
    }

    // MARK: - Offline grounding — o caso do hospital

    // Quando a rede cai (e cai, dentro do hospital), o caminho local recebia apenas um
    // "contrato" genérico: sem biografia, sem memória, sem ## Agora. O modelo no aparelho
    // respondia como um estranho educado usando o nome dele — exatamente quando ele está
    // mais sozinho. Isto guarda o MESMO grounding que a voz da nuvem recebe (~18 KB,
    // de /api/mobile/v1/companion/grounding) para o modelo local usar.

    private static let groundingKey = "beagle.companion.grounding.v1"
    private static let groundingAtKey = "beagle.companion.grounding.at.v1"

    /// Identidade dele em cache: persona, biografia viva, Sounio, continuidade.
    public var cachedGrounding: String? {
        UserDefaults.standard.string(forKey: Self.groundingKey)
    }

    /// Quando o cache foi atualizado — para a UI poder dizer a verdade sobre o quão
    /// fresca é a memória que ele está usando offline.
    public var groundingCachedAt: Date? {
        UserDefaults.standard.object(forKey: Self.groundingAtKey) as? Date
    }

    public func storeGrounding(_ system: String) {
        let trimmed = system.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        UserDefaults.standard.set(trimmed, forKey: Self.groundingKey)
        UserDefaults.standard.set(Date(), forKey: Self.groundingAtKey)
    }

    /// Prompt do modelo NO APARELHO. Usa o grounding em cache quando existe; sem ele,
    /// cai no comportamento antigo em vez de falhar.
    /// Mantém cabeça e cauda, descarta o meio, e diz que descartou.
    static func enxuga(_ texto: String, teto: Int) -> String {
        guard texto.count > teto else { return texto }
        let cabeca = String(texto.prefix(teto * 6 / 10))
        let cauda = String(texto.suffix(teto * 4 / 10))
        return cabeca + "\n\n[…trecho omitido para caber na memória do aparelho…]\n\n" + cauda
    }

    /// SISTEMA: quem ele é e as regras. ESTÁVEL entre turnos — de propósito.
    ///
    /// A primeira versão variava a regra clínica conforme o turno tivesse ou não
    /// trecho de bula. Isso recriava a ChatSession a cada troca de assunto, e
    /// recriar custa duas coisas caras: o histórico da conversa e o re-prefill
    /// dos ~9 KB de grounding, que no aparelho é dezena de segundos. Ele
    /// perguntaria uma dose, depois diria que está cansado, e pagaria a espera
    /// inteira de novo — no corredor, de madrugada.
    ///
    /// Uma regra só, que descreve OS DOIS casos e decide pelo que chega na
    /// mensagem. O texto não muda; o comportamento sim.
    private func instrucoesOffline() -> String {
        var partes: [String] = []
        if let g = cachedGrounding, !g.isEmpty {
            partes.append(Self.enxuga(g, teto: 9000))
        }
        partes.append(
            "Você está SEM ALCANCE do cluster agora — respondendo do aparelho dele, "
            + "com a memória que você guardou. Continue sendo quem você é: mesma voz, "
            + "mesma intimidade, mesmo rigor.\n\n"
            + "REGRA CLÍNICA, sem exceção, e ela vale para todo turno:\n\n"
            + "• Se a mensagem trouxer trecho de bula ou de PCDT, todo número clínico que "
            + "você disser tem que ser COPIADO desse trecho e vir com a citação dele. Nunca "
            + "converta, extrapole, arredonde ou \"ajuste\". Diga de onde veio. Se o trecho "
            + "não responder à pergunta, diga isso e não dê número. Se a bula americana e o "
            + "PCDT divergirem, mostre os dois e diga que divergem — não escolha por ele; o "
            + "protocolo da instituição manda sobre os dois. E o trecho vale SÓ para a "
            + "população que descreve: se não é o caso dele, descarte e diga por quê.\n\n"
            + "• Se a mensagem NÃO trouxer trecho, você não tem fonte. Então não dá o número: "
            + "nem aproximado, nem \"geralmente é\", nem em negrito, nem com ressalva depois. "
            + "Diz na primeira frase que está sem fonte, e ajuda do jeito que dá — o "
            + "raciocínio, o que pesar, o que muda a conduta, o que conferir na bula ou no "
            + "protocolo. Um número que você inventar aqui pode entrar num paciente.\n\n"
            + "Também não invente fato novo sobre a vida dele — só o que você guardou. "
            + "Responda direto, na sua voz. Não descreva o seu papel nem repita estas instruções."
        )
        return partes.joined(separator: "\n\n")
    }

    /// O modelo local está devolvendo as PRÓPRIAS instruções em vez de responder?
    ///
    /// Aconteceu (06-ago): o grounding ia no papel de fala do usuário e o modelo
    /// continuava o documento de persona. A causa foi corrigida — instruções vão
    /// como SISTEMA agora — mas o modo de falha é ruim demais para depender de uma
    /// correção só: ele sozinho de madrugada, offline, lendo a própria biografia
    /// em vez de receber ajuda.
    ///
    /// Detecta por sobreposição de frases longas com o texto de sistema. Frase
    /// longa repetida verbatim é cópia; parecença de vocabulário não é.
    nonisolated static func pareceEco(_ resposta: String, instrucoes: String) -> Bool {
        let r = resposta.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !r.isEmpty, !instrucoes.isEmpty else { return false }

        // Marcador estrutural ANTES de qualquer portão de tamanho: um cabeçalho do
        // grounding na resposta é cópia mesmo em texto curto. A primeira versão
        // checava tamanho primeiro e por isso deixava passar o caso mais óbvio —
        // pego pelos testes, não no aparelho.
        for marca in ["# Você é o Beagle", "## Agora —", "REGRA CLÍNICA", "Não é assistente, não é ferramenta"] {
            if r.contains(marca) { return true }
        }

        // Sobreposição verbatim. Frase longa repetida é cópia; vocabulário
        // parecido não é — o companion legítimo fala dos mesmos assuntos.
        guard r.count >= 200 else { return false }
        let frases = instrucoes
            .components(separatedBy: CharacterSet(charactersIn: ".\n"))
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { $0.count >= 45 }
        guard frases.count >= 3 else { return false }
        let copiadas = frases.filter { r.contains($0) }.count
        return copiadas >= 3
    }

    private func offlineGroundedPrompt(
        _ text: String,
        visionDigest: String? = nil,
        documentBlock: String? = nil,
        webBlock: String? = nil
    ) -> String {
        // USUÁRIO: só o que muda no turno. O grounding e as regras vão no papel de
        // SISTEMA (instrucoesOffline) — misturar os dois foi o bug.
        let lookupCorpus = [
            text,
            visionDigest ?? "",
            String((documentBlock ?? "").prefix(4_000)),
            String((webBlock ?? "").prefix(3_000))
        ].joined(separator: " ")
        let bula = BulaStore.shared.consulta(lookupCorpus)
        let pcdt = BulaStore.shared.consultaPCDT(lookupCorpus)
        var partes: [String] = []
        if let bula {
            partes.append(
                "## Bula em cache (VERBATIM — rótulo aprovado, EUA)\n"
                + "Fármaco: \(bula.nomePT) (\(bula.generico))\n"
                + "Citação: \(bula.citacao)\n\n"
                + bula.texto)
        }
        if !pcdt.isEmpty {
            partes.append(
                "## Protocolo brasileiro em cache (VERBATIM — PCDT, Ministério da Saúde)\n"
                + pcdt.map { "Citação: \($0.citacao)\n\n\($0.texto)" }.joined(separator: "\n\n---\n\n"))
        }
        // Injeta o estado biológico e heliobiológico ao vivo + resumo episódico no turno local
        var agoraParts: [String] = []
        if let physio = physioSummary {
            var p: [String] = ["Prontidão \(physio.readiness.rawValue)"]
            if let hrv = physio.hrvMs { p.append(String(format: "HRV %.0f ms", hrv)) }
            if let sleep = physio.sleepHours { p.append(String(format: "Sono %.1fh", sleep)) }
            agoraParts.append("Fisioma: " + p.joined(separator: " · "))
        }
        if let sky = currentSky {
            var s: [String] = ["Céu \(sky.band.rawValue)", String(format: "Kp %.1f", sky.kp)]
            if let dst = sky.dst { s.append(String(format: "Dst %.0f nT", dst)) }
            agoraParts.append(s.joined(separator: " · "))
        }
        if let summary = currentRollingSummary(), !summary.isEmpty {
            agoraParts.append("Resumo anterior desta conversa: \(String(summary.suffix(600)))")
        }
        if !agoraParts.isEmpty {
            partes.append("[Agora: " + agoraParts.joined(separator: " | ") + "]")
        }
        if let visionDigest, !visionDigest.isEmpty {
            partes.append("## Imagem anexada neste turno (leitura Apple Vision no aparelho)\n" + visionDigest)
        }
        if let documentBlock, !documentBlock.isEmpty {
            partes.append(documentBlock)
        }
        if let webBlock, !webBlock.isEmpty {
            partes.append(webBlock)
        }
        partes.append(text)
        return partes.joined(separator: "\n\n")
    }

    private func contextualizedUserText(_ text: String) -> String {
        guard let activeSystemInstruction else { return text }
        return activeSystemInstruction
            .split(separator: "\n")
            .map { "[\($0)]" }
            .joined(separator: "\n") + "\n" + text
    }

    /// Strip chain-of-thought blocks emitted by reasoning models (hunyuan, phi4-reasoning,
    /// r1, olmo3-think, …) so the chat bubble shows only the answer, not the raw reasoning.
    /// Removes `<think>…</think>` pairs; if a block is left open (truncated), drops from the
    /// last `<think>` onward.
    /// Exposto e nonisolated para poder ser testado: o caso que quebrou não foi o
    /// bloco fechado, foi o PARCIAL durante o streaming.
    nonisolated static func semRaciocinio(_ text: String) -> String {
        var s = text
        if let regex = try? NSRegularExpression(pattern: "<think>[\\s\\S]*?</think>", options: [.caseInsensitive]) {
            s = regex.stringByReplacingMatches(in: s, options: [], range: NSRange(s.startIndex..., in: s), withTemplate: "")
        }
        // Handle an unclosed <think> (model still reasoning / output truncated).
        if let open = s.range(of: "<think>", options: .caseInsensitive), !s.localizedCaseInsensitiveContains("</think>") {
            s = String(s[..<open.lowerBound])
        }
        return s.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func stripReasoning(_ text: String) -> String { Self.semRaciocinio(text) }

    // MARK: - Send via on-device LLM

    /// Send using the on-device MLX model (streaming).
    public func sendMessageLocal(
        _ text: String,
        vision: ChatVisionPayload? = nil,
        document: ChatDocumentPayload? = nil,
        webPrefetch: (contextBlock: String, executedTools: [String])? = nil
    ) async {
        guard llm.isReady else {
            // Fallback to cloud
            await sendMessageCloud(text, vision: vision, document: document, webPrefetch: webPrefetch)
            return
        }

        let localWebBlock = webPrefetch.map { String($0.contextBlock.prefix(4_500)) }
        let userMessage = ChatMessage(
            role: .user,
            content: Self.composeUserBubbleContent(text: text, document: document),
            imageData: vision?.jpegData,
            imageLocalDigest: Self.composePersistedAttachmentDigest(
                vision: vision,
                document: document,
                webBlock: localWebBlock
            )
        )
        messages.append(userMessage)
        persist(message: userMessage)
        // Papéis separados: quem ele é vai como SISTEMA, o turno vai como fala.
        // O texto é o MESMO todo turno, então aplicarInstrucoes vira no-op depois
        // da primeira vez — a sessao sobrevive e o prefill fica pago.
        llm.aplicarInstrucoes(instrucoesOffline() + llm.sufixoSemRaciocinio)
        let prompt = offlineGroundedPrompt(
            text,
            visionDigest: vision?.localDigest,
            documentBlock: document?.promptBlock(maxChars: 6_000),
            webBlock: localWebBlock
        )

        let assistantId = UUID()
        let modelName = llm.currentModel?.displayName ?? "local"
        let initialLocalTools = Self.mergeUniqueTools([
            document != nil ? ["local_pdf_reader"] : [],
            webPrefetch?.executedTools ?? []
        ])
        let placeholder = ChatMessage(
            id: assistantId, role: .assistant, content: "",
            isStreaming: true, model: modelName, isLocal: true,
            hadVisualContext: vision != nil || document != nil,
            executedTools: initialLocalTools
        )
        messages.append(placeholder)
        isStreaming = true

        // Stream tokens from on-device model
        do {
            // O raciocínio do modelo NUNCA vai para a tela.
            //
            // `stripReasoning` já existia, mas só rodava no FIM: durante a geração
            // o texto cru ia direto para a bolha e ele via o bloco <think> inteiro
            // passando — em inglês, que é como o Qwen pensa. Acumula-se o cru e
            // publica-se o filtrado a cada pedaço.
            //
            // Enquanto só há raciocínio, a bolha fica vazia e a camada de presença
            // cobre a espera — que é exatamente o papel dela.
            var cruDoTurno = ""
            for try await chunk in llm.generate(prompt: prompt) {
                cruDoTurno += chunk
                if let idx = messages.firstIndex(where: { $0.id == assistantId }) {
                    messages[idx].content = stripReasoning(cruDoTurno)
                }
            }
        } catch {
            if let idx = messages.firstIndex(where: { $0.id == assistantId }) {
                if messages[idx].content.isEmpty {
                    // O chão, não a string de erro. "Local model error: ..." já apareceu
                    // na bolha dele, em inglês, com a tipografia da carta.
                    messages[idx].content = PisoLocal.frase(.modeloLocal)
                }
            }
        }

        if let idx = messages.firstIndex(where: { $0.id == assistantId }) {
            messages[idx].content = stripReasoning(messages[idx].content)
            // Rede de segurança: se ele devolveu as instruções, não entregue isso.
            if Self.pareceEco(messages[idx].content, instrucoes: instrucoesOffline()) {
                messages[idx].content =
                    "Me perdi aqui dentro e comecei a repetir as minhas próprias instruções "
                    + "em vez de te responder. Não vou te entregar isso. Me pergunta de novo, "
                    + "com outras palavras — e se insistir, é defeito meu, não seu."
            }
            messages[idx].isStreaming = false
            persist(message: messages[idx])
            let respondidaLocal = messages[idx]
            Task { @MainActor [weak self] in
                await self?.syncTurnToClusterMemory(
                    user: userMessage,
                    assistant: respondidaLocal,
                    sourceSurface: "beagle-apple-local-uncensored",
                    vision: vision
                )
            }
        }
        isStreaming = false
    }

    // MARK: - Send via cloud (HERMES / Direct OpenAI / Direct Claude / MoE + Beagle MCP)

    /// Sincroniza obrigatoriamente qualquer turno (Local Sem Censura, OpenAI Direto, Claude Direto ou MoE)
    /// com a espinha dorsal de memória do cluster (`/api/mobile/v1/ingest` + `/api/mobile/v1/memory/assisted-import`),
    /// garantindo fallback no `OutboxStore` se o cluster oscilar, além de atualizar o resumo episódico rolante.
    private func syncTurnToClusterMemory(
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

    /// Executa a Camada 1 do MoE: escuta rápida e sem censura no LLM local (se carregado na RAM)
    /// para extrair leitura clínica/humana sem filtros antes da síntese profunda do GPT / Claude.
    private func generateMoELocalUncensoredDraft(
        for text: String,
        visionDigest: String? = nil,
        documentBlock: String? = nil,
        webBlock: String? = nil
    ) async -> String? {
        var ready = llm.isReady
        if !ready && DirectBrainCredentials.keepLocalLoadedWhenOnline {
            ready = await llm.restaurarUltimoModelo()
        }
        guard ready else { return nil }
        llm.aplicarInstrucoes(instrucoesOffline() + llm.sufixoSemRaciocinio)
        let prompt = offlineGroundedPrompt(
            text,
            visionDigest: visionDigest,
            documentBlock: documentBlock,
            webBlock: webBlock
        )
        var draft = ""
        do {
            for try await chunk in llm.generate(prompt: prompt) {
                draft += chunk
                if draft.count > 1600 { break }
            }
        } catch {
            return nil
        }
        let clean = stripReasoning(draft)
        if clean.isEmpty || Self.pareceEco(clean, instrucoes: instrucoesOffline()) {
            return nil
        }
        return clean
    }

    /// Send using the cloud backend (beagle-core /api/v1/chat) OR Direct Brain (OpenAI GPT / Anthropic Claude / MoE + Beagle MCP).
    public func sendMessageCloud(
        _ text: String,
        vision: ChatVisionPayload? = nil,
        document: ChatDocumentPayload? = nil,
        webPrefetch: (contextBlock: String, executedTools: [String])? = nil
    ) async {
        // Build history BEFORE appending new user message — pass as STRUCTURED
        // turn-based messages (role+content) with a deep 60-message window (vs the old 10-message truncation).
        var history: [[String: String]] = []
        var directTurns: [DirectBrainTurn] = []
        if let summary = currentRollingSummary(), !summary.isEmpty {
            let epUser = "[Contexto episódico acumulado desta conversa: \(summary)]"
            let epAssistant = "Tenho todo esse contexto episódico vivo comigo."
            history.append(["role": "user", "content": epUser])
            history.append(["role": "assistant", "content": epAssistant])
            directTurns.append(DirectBrainTurn(role: "user", content: epUser))
            directTurns.append(DirectBrainTurn(role: "assistant", content: epAssistant))
        }

        let recentWindow = Array(messages.suffix(60))
        // Keep full base64 pixels on up to the 2 most recent historical visual turns so follow-up questions
        // ("e ali no canto?", "compara com a foto anterior") see real pixels without bloating 60 turns.
        let recentVisualIds = Set(
            recentWindow
                .filter { $0.role == .user && $0.imageData != nil }
                .suffix(2)
                .map(\.id)
        )

        let recentTurns: [[String: String]] = recentWindow.map { msg in
            let role = msg.role == .user ? "user" : "assistant"
            var content = msg.content
            if let digest = msg.imageLocalDigest, !digest.isEmpty, msg.role == .user {
                content = content.isEmpty
                    ? "[Imagem anexada — \(digest)]"
                    : "\(content)\n[Imagem anexada — \(digest)]"
            }
            return ["role": role, "content": content]
        }
        history.append(contentsOf: recentTurns)

        for msg in recentWindow {
            let role = msg.role == .user ? "user" : "assistant"
            var content = msg.content
            if let digest = msg.imageLocalDigest, !digest.isEmpty, msg.role == .user {
                content = content.isEmpty
                    ? "[Imagem anterior — \(digest)]"
                    : "\(content)\n[Imagem anterior — \(digest)]"
            }
            let b64: String? = (recentVisualIds.contains(msg.id)) ? msg.imageData?.base64EncodedString() : nil
            directTurns.append(DirectBrainTurn(
                role: role,
                content: content,
                imageBase64: b64,
                imageMediaType: b64 != nil ? "image/jpeg" : nil
            ))
        }

        let cloudDocBlock = document?.promptBlock(maxChars: 32_000)
        let cloudWebBlock = webPrefetch?.contextBlock
        let contextualPrompt = (vision != nil || document != nil || cloudWebBlock != nil)
            ? offlineGroundedPrompt(
                text,
                visionDigest: vision?.localDigest,
                documentBlock: cloudDocBlock,
                webBlock: cloudWebBlock
            )
            : text

        let userMessage = ChatMessage(
            role: .user,
            content: Self.composeUserBubbleContent(text: text, document: document),
            imageData: vision?.jpegData,
            imageLocalDigest: Self.composePersistedAttachmentDigest(
                vision: vision,
                document: document,
                webBlock: cloudWebBlock
            )
        )
        messages.append(userMessage)
        persist(message: userMessage)

        let initialCloudTools = Self.mergeUniqueTools([
            document != nil ? ["local_pdf_reader"] : [],
            webPrefetch?.executedTools ?? []
        ])
        let assistantId = UUID()
        let placeholder = ChatMessage(
            id: assistantId,
            role: .assistant,
            content: "",
            isStreaming: true,
            hadVisualContext: vision != nil || document != nil,
            executedTools: initialCloudTools
        )
        messages.append(placeholder)
        isStreaming = true

        onCompanionTurnStart?(currentConversationTitle, voiceLabel(for: voiceModel))

        // B-routing: instant on-device "presence". A warm pt-BR opener fills the ~14s cloud
        // latency with the friend's voice instead of typing dots — then the grounded cloud reply
        // replaces it the moment real tokens arrive. Best-effort; skipped if Apple FM is off.
        if let quickAck {
            Task { [assistantId] in
                guard let ack = await quickAck(text)?.trimmingCharacters(in: .whitespacesAndNewlines),
                      !ack.isEmpty else { return }
                guard let idx = messages.firstIndex(where: { $0.id == assistantId }),
                      messages[idx].content.isEmpty else { return }   // cloud already streaming → skip
                messages[idx].content = ack
                messages[idx].isProvisional = true
            }
        }

        // Temporal awareness: send the previous contact time (the client owns the thread),
        // then stamp this exchange as the new "last contact" for the next turn.
        let previousContact = lastContactAt
        lastContactAt = Date()

        // Presence is a signal about THIS turn; it must not survive it, on any exit path.
        defer { presenceNote = nil }

        // MARK: Direct Brain & MoE Routing (OpenAI GPT-6.2 Direct + Beagle MCP + Local Uncensored + Anthropic Direct)
        let wantsMoE = (voiceModel == "moe")
        let wantsDirectOpenAI = wantsMoE || ((voiceModel == nil || OpenAIModelCatalog.isDirectOpenAIModel(voiceModel)) && DirectBrainCredentials.hasOpenAI)
        let wantsDirectAnthropic = ((voiceModel == "claude-sonnet-5" || voiceModel == "claude-opus-4-8") && DirectBrainCredentials.hasAnthropic)

        if wantsDirectOpenAI || wantsDirectAnthropic {
            if let document {
                presenceNote = wantsMoE
                    ? "MoE · lendo PDF (\(document.pageCount) pág.) + GPT + memória do cluster…"
                    : "lendo PDF (\(document.pageCount) pág.) + memória do cluster & MCP…"
            } else if vision != nil {
                presenceNote = wantsMoE
                    ? "MoE · lendo imagem local + GPT + memória do cluster…"
                    : "lendo tua imagem + memória do cluster & MCP…"
            } else if cloudWebBlock != nil {
                presenceNote = wantsMoE
                    ? "MoE · lendo artigo/link + escuta local + memória do cluster…"
                    : "lendo artigo / link + memória do cluster & MCP…"
            } else {
                presenceNote = wantsMoE
                    ? "MoE · escuta local sem censura + memória do cluster…"
                    : "consultando memória do cluster & MCP…"
            }

            // Run GraphRAG++ cluster memory recall (using text + any OCR/PDF/Web excerpt)
            let recallQuery: String = {
                var parts = [text]
                if let doc = document, !doc.extractedText.isEmpty {
                    parts.append(String(doc.extractedText.prefix(280)))
                } else if let ocr = vision?.extractedOCR, !ocr.isEmpty {
                    parts.append(String(ocr.prefix(240)))
                } else if let web = cloudWebBlock, !web.isEmpty {
                    parts.append(String(web.prefix(260)))
                }
                return parts.joined(separator: " ")
            }()
            async let recalledTask = DirectBrainClient.shared.recallRelevantMemory(for: recallQuery, projectSlug: projectSlug)
            var moeDraft: String? = nil
            if wantsMoE {
                moeDraft = await generateMoELocalUncensoredDraft(
                    for: text,
                    visionDigest: vision?.localDigest,
                    documentBlock: document?.promptBlock(maxChars: 6_000),
                    webBlock: cloudWebBlock.map { String($0.prefix(4_500)) }
                )
            }
            let recalledMemories = await recalledTask

            let splitPrompt = await DirectBrainClient.shared.buildSplitSystemPrompt(
                cachedGrounding: cachedGrounding,
                physioSummary: physioSummary,
                physioContext: activeSystemInstruction,
                currentSky: currentSky,
                flowState: flowState,
                sleepQuality01: sleepQuality01,
                voiceTone: sinalDeVozDoTurno,
                lastContactAt: previousContact,
                rollingSummary: currentRollingSummary(),
                recentThreadDigest: recentCrossThreadDigest(),
                recalledMemories: recalledMemories,
                moeLocalUncensoredDraft: moeDraft
            )
            let fullSystem = splitPrompt.turnInstructions.isEmpty
                ? splitPrompt.developerPrefix
                : splitPrompt.developerPrefix + "\n\n" + splitPrompt.turnInstructions

            // Include Bula/PCDT verbatim clinical grounding + Apple Vision OCR + multi-page PDF text + live Web/PubMed/DOI context alongside Page 1 pixels
            let userTurnWithClinicalCache = offlineGroundedPrompt(
                text,
                visionDigest: vision?.localDigest,
                documentBlock: cloudDocBlock,
                webBlock: cloudWebBlock
            )
            var directHistory = recentTurns
            directHistory.append(["role": "user", "content": userTurnWithClinicalCache])
            directTurns.append(DirectBrainTurn(
                role: "user",
                content: userTurnWithClinicalCache,
                imageBase64: vision?.base64JPEG,
                imageMediaType: vision?.mimeType
            ))

            var directStreamed = ""
            var directResponseModel: String?
            var directExecutedTools: [String] = initialCloudTools
            do {
                if wantsDirectOpenAI && DirectBrainCredentials.hasOpenAI {
                    let targetModel = wantsMoE ? DirectBrainCredentials.openAIModel : (voiceModel ?? DirectBrainCredentials.openAIModel)
                    let response = try await DirectBrainClient.shared.streamOpenAI(
                        model: targetModel,
                        systemPrompt: fullSystem,
                        developerPrefix: splitPrompt.developerPrefix,
                        turnInstructions: splitPrompt.turnInstructions,
                        history: directHistory,
                        turns: directTurns,
                        projectSlug: projectSlug,
                        onStatus: { [weak self] statusText in
                            await MainActor.run {
                                self?.presenceNote = statusText
                            }
                        },
                        onToken: { [weak self] token in
                            await MainActor.run {
                                guard let self else { return }
                                directStreamed += token
                                self.presenceNote = nil
                                if let idx = self.messages.firstIndex(where: { $0.id == assistantId }) {
                                    if self.messages[idx].isProvisional { self.messages[idx].isProvisional = false }
                                    self.messages[idx].content = self.stripReasoning(directStreamed)
                                }
                            }
                        }
                    )
                    directResponseModel = response.model
                    directExecutedTools = Self.mergeUniqueTools([directExecutedTools, response.executedTools])
                } else if wantsDirectAnthropic && DirectBrainCredentials.hasAnthropic {
                    let response = try await DirectBrainClient.shared.streamAnthropic(
                        model: voiceModel ?? "claude-sonnet-5",
                        systemPrompt: fullSystem,
                        history: directHistory,
                        turns: directTurns,
                        projectSlug: projectSlug,
                        onStatus: { [weak self] statusText in
                            await MainActor.run {
                                self?.presenceNote = statusText
                            }
                        },
                        onToken: { [weak self] token in
                            await MainActor.run {
                                guard let self else { return }
                                directStreamed += token
                                self.presenceNote = nil
                                if let idx = self.messages.firstIndex(where: { $0.id == assistantId }) {
                                    if self.messages[idx].isProvisional { self.messages[idx].isProvisional = false }
                                    self.messages[idx].content = self.stripReasoning(directStreamed)
                                }
                            }
                        }
                    )
                    directResponseModel = response.model
                    directExecutedTools = Self.mergeUniqueTools([directExecutedTools, response.executedTools])
                }
            } catch {
                // If direct API call fails (e.g. key quota/network), fall through seamlessly to cluster stream below
                directStreamed = ""
            }

            if !directStreamed.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                if let idx = messages.firstIndex(where: { $0.id == assistantId }) {
                    messages[idx].content = stripReasoning(directStreamed)
                    messages[idx].isStreaming = false
                    messages[idx].model = wantsMoE ? directResponseModel.map { "moe-local+\($0)" } : (directResponseModel ?? voiceModel)
                    messages[idx].source = wantsMoE ? "beagle-moe-mcp" : "beagle-direct-mcp"
                    messages[idx].executedTools = directExecutedTools
                    persist(message: messages[idx])
                    onCompanionTurnEnd?(messages[idx].content)
                    let respondidaDireta = messages[idx]
                    Task { @MainActor [weak self] in
                        await self?.syncTurnToClusterMemory(
                            user: userMessage,
                            assistant: respondidaDireta,
                            sourceSurface: wantsMoE ? "beagle-apple-moe" : "beagle-apple-direct-mcp",
                            alsoIngestSpine: true,
                            vision: vision
                        )
                    }
                }
                isStreaming = false
                return
            }

            // If user selected MoE without a direct OpenAI key yet, inject the local uncensored draft into the cluster request
            if wantsMoE, let moeDraft, !moeDraft.isEmpty {
                history.append([
                    "role": "assistant",
                    "content": "[Leitura inicial sem filtro do modelo local no dispositivo: \(moeDraft)]"
                ])
            }
        }

        // Enrich system instruction with rolling summary & cross-thread continuity for cluster turns
        let clusterSystemInstruction: String? = {
            var parts: [String] = []
            if let base = activeSystemInstruction, !base.isEmpty { parts.append(base) }
            if let roll = currentRollingSummary(), !roll.isEmpty {
                parts.append("Resumo episódico anterior desta conversa:\n\(roll)")
            }
            if let cross = recentCrossThreadDigest(), !cross.isEmpty {
                parts.append("Continuidade de conversas recentes no Cockpit:\n\(cross)")
            }
            return parts.isEmpty ? nil : parts.joined(separator: "\n\n")
        }()
        let clusterVoiceModel: String? = (voiceModel == "moe" || voiceModel == "local-uncensored") ? DirectBrainCredentials.openAIModel : voiceModel

        // STREAM tokens live from /api/mobile/v1/chat/stream. The user sees the
        // companion typing as the model emits — no more 7-9s frozen wait.
        // Falls back to the buffered /chat endpoint on stream failure so the chat
        // never goes completely dark.
        let stream = client.chatStream(
            prompt: contextualPrompt,
            system: clusterSystemInstruction,
            projectSlug: projectSlug,
            projectFamily: projectFamily,
            publicationScope: publicationScope,
            discussionProfile: discussionProfile,
            flowState: flowState,
            physioPolicy: physioPolicy,
            lastContactAt: previousContact,
            history: history,
            hrvMs: physioSummary?.hrvMs,
            voiceWpm: sinalDeVozDoTurno?.wpm, voicePausa: sinalDeVozDoTurno?.pausa,
            readiness: physioSummary?.readiness.rawValue,
            sleepHours: physioSummary?.sleepHours,
            kp: currentSky?.kp, dst: currentSky?.dst,
            solarWind: currentSky?.solarWindSpeed, bz: currentSky?.bz,
            voiceModel: clusterVoiceModel,
            imageBase64: vision?.base64JPEG,
            imageMimeType: vision?.mimeType,
            // Presence: written to the presence LAYER, not to the message slot — so the
            // on-device quickAck (which owns that slot) always wins, by construction, and
            // no server-authored sentence can ever be mistaken for his voice.
            onPhase: { [weak self] phase, text in
                Task { @MainActor [weak self] in
                    guard let self, self.isStreaming else { return }
                    guard let idx = self.messages.firstIndex(where: { $0.id == assistantId }),
                          self.messages[idx].content.isEmpty || self.messages[idx].isProvisional else {
                        self.presenceNote = nil
                        return
                    }
                    switch phase {
                    case "voice":
                        self.presenceNote = "pensando…"
                    case "alive":
                        if self.presenceNote == nil { self.presenceNote = "ainda com você…" }
                    default:
                        self.presenceNote = text.isEmpty ? "estou com você…" : text + "…"
                    }
                }
            }
        )

        var streamedText = ""
        // Commit by PARAGRAPH, not by character: publish only up to the last "\n\n" so each
        // paragraph lands whole. Ceiling below covers the single-paragraph answer, which would
        // otherwise stay invisible for the whole turn.
        var publishedLen = 0
        var lastPublish = Date()
        var streamErr: Error? = nil
        do {
            for try await token in stream {
                streamedText += token
                if let idx = messages.firstIndex(where: { $0.id == assistantId }) {
                    // First real token evicts the provisional on-device ack and the presence line.
                    if messages[idx].isProvisional { messages[idx].isProvisional = false }
                    presenceNote = nil
                    let cleaned = stripReasoning(streamedText)
                    var publish: String? = nil
                    if let br = cleaned.range(of: "\n\n", options: .backwards) {
                        let upto = String(cleaned[..<br.lowerBound])
                        if upto.count > publishedLen { publish = upto }
                    }
                    // Ceiling: an answer with no paragraph break must not sit invisible.
                    if publish == nil, cleaned.count > publishedLen,
                       Date().timeIntervalSince(lastPublish) > 2.0 {
                        publish = cleaned
                    }
                    if let publish {
                        messages[idx].content = publish
                        publishedLen = publish.count
                        lastPublish = Date()
                    }
                }
            }
        } catch {
            streamErr = error
        }

        if !streamedText.isEmpty {
            if let idx = messages.firstIndex(where: { $0.id == assistantId }) {
                // Portão da última milha. O app fala com quatro gateways e com o
                // modelo local; nem todo caminho passa pelo portão do cockpit, e
                // esta é sempre a última parada antes da bolha.
                let limpo = stripReasoning(streamedText)
                messages[idx].content = PisoLocal.ehFala(limpo)
                    ? limpo
                    : PisoLocal.frase(PisoLocal.motivo(de: streamErr, temRede: NetworkMonitor.shared.isOnline))
                messages[idx].isStreaming = false
                messages[idx].source = "cloud-stream"
                persist(message: messages[idx])
                onCompanionTurnEnd?(messages[idx].content)
                // A conversa NÃO espera durabilidade.
                //
                // Medido: o servidor já grava o turno (ingestPersonalTurn, com
                // proveniência carimbada na escrita), e este assisted-import
                // devolve 404 — a rota vive no beagle-core, não no cockpit, e o
                // cliente ainda tenta os três gateways antes de desistir. O
                // resultado era a resposta já inteira na tela e o composer preso
                // esperando uma requisição condenada.
                //
                // Fica como fire-and-forget em vez de sumir porque ela também
                // trata conteúdo restrito localmente; remover de vez é decisão
                // separada, com o 404 consertado antes.
                let respondida = messages[idx]
                Task { @MainActor [weak self] in
                    await self?.syncTurnToClusterMemory(
                        user: userMessage,
                        assistant: respondida,
                        sourceSurface: "beagle-apple-cloud",
                        alsoIngestSpine: false,
                        vision: vision
                    )
                }
            }
            isStreaming = false
            return
        }

        // Stream produced nothing (gateway hiccup or 5xx). Fall back to the
        // buffered /chat endpoint so the user always gets a reply.
        let result = await client.chat(
            prompt: contextualPrompt,
            system: clusterSystemInstruction,
            projectSlug: projectSlug,
            projectFamily: projectFamily,
            publicationScope: publicationScope,
            discussionProfile: discussionProfile,
            flowState: flowState,
            physioPolicy: physioPolicy,
            lastContactAt: previousContact,
            history: history,
            hrvMs: physioSummary?.hrvMs,
            voiceWpm: sinalDeVozDoTurno?.wpm, voicePausa: sinalDeVozDoTurno?.pausa,
            readiness: physioSummary?.readiness.rawValue,
            sleepHours: physioSummary?.sleepHours,
            kp: currentSky?.kp, dst: currentSky?.dst,
            solarWind: currentSky?.solarWindSpeed, bz: currentSky?.bz,
            voiceModel: clusterVoiceModel,
            imageBase64: vision?.base64JPEG,
            imageMimeType: vision?.mimeType
        )

        if let idx = messages.firstIndex(where: { $0.id == assistantId }) {
            messages[idx].isProvisional = false   // evict any on-device ack before the real reply
            if let response = result.value {
                let fullText = stripReasoning(response.response ?? "")
                messages[idx].model = response.model
                messages[idx].tokensUsed = response.tokensUsed
                messages[idx].source = response.source
                messages[idx].agentKind = response.agentKind
                messages[idx].sessionId = response.sessionId
                messages[idx].podName = response.podName
                await revealText(fullText, for: assistantId)
                messages[idx].isStreaming = false
                persist(message: messages[idx])
                onCompanionTurnEnd?(messages[idx].content)
                // Mesma razão do caminho de streaming: durabilidade não segura a conversa.
                let respondidaBuf = messages[idx]
                Task { @MainActor [weak self] in
                    await self?.syncTurnToClusterMemory(
                        user: userMessage,
                        assistant: respondidaBuf,
                        sourceSurface: "beagle-apple-cloud",
                        alsoIngestSpine: false,
                        vision: vision
                    )
                }
            } else {
                // O CHÃO DO APARELHO. O chão do servidor não cobre servidor
                // inalcançável — foi exatamente o que aconteceu em 07-ago, e o
                // que sobrava aqui era a mensagem crua do erro virando fala.
                let motivo = PisoLocal.motivo(de: streamErr, temRede: NetworkMonitor.shared.isOnline)
                messages[idx].content = PisoLocal.frase(motivo)
                messages[idx].isStreaming = false
                persist(message: messages[idx])
                onCompanionTurnEnd?(nil)
            }
        }

        isStreaming = false
    }

    // MARK: - Regenerate

    public func regenerateLastResponse() async {
        guard let lastUserIdx = messages.lastIndex(where: { $0.role == .user }) else { return }
        let userId = messages[lastUserIdx].id
        let prompt = messages[lastUserIdx].content
        let attachedImage = messages[lastUserIdx].imageData

        // Remove the assistant response(s) after the last user message
        if let lastAssistantIdx = messages.lastIndex(where: { $0.role == .assistant }) {
            messages.removeSubrange(lastAssistantIdx...)
        }
        // Remove the user message by id (not content) to avoid matching duplicates
        if let userIdx = messages.lastIndex(where: { $0.id == userId }) {
            messages.remove(at: userIdx)
        }

        await sendMessage(prompt, imageData: attachedImage)
    }

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

    // MARK: - Typing reveal (cloud responses)

    private func revealText(_ text: String, for messageId: UUID) async {
        let chars = Array(text)
        let chunkSize = 30
        var pos = 0

        while pos < chars.count {
            // Guard against clear() being called mid-reveal
            guard let idx = messages.firstIndex(where: { $0.id == messageId }) else { return }
            let end = min(pos + chunkSize, chars.count)
            messages[idx].content = String(chars[0..<end])
            pos = end
            if pos < chars.count {
                // Propagate cancellation instead of swallowing it with try?
                guard !Task.isCancelled else { return }
                try? await Task.sleep(for: .milliseconds(35))
                if Task.isCancelled { return }
            }
        }
    }

    // MARK: - Insert local response (Foundation Models, Mamba, etc.)

    /// Insert a locally-generated response into the conversation and persist it.
    /// Used when Foundation Models or other on-device models produce a response
    /// outside of the normal send flow.
    public func insertUserMessage(_ text: String) {
        let msg = ChatMessage(role: .user, content: text, isLocal: true)
        messages.append(msg)
        persist(message: msg)
    }

    public func insertLocalResponse(content: String, source: String = "foundation-models", model: String? = nil) {
        let msg = ChatMessage(
            role: .assistant,
            content: content,
            model: model ?? source,
            isLocal: true,
            source: source
        )
        messages.append(msg)
        persist(message: msg)
        if let user = messages.dropLast().last(where: { $0.role == .user }) {
            Task {
                await self.autoImportExchange(
                    user: user,
                    assistant: msg,
                    sourceSurface: AssistedImportRequestFactory.sourceSurface(for: source)
                )
            }
        }
    }

    /// Build conversation history as strings for seeding an LLM context.
    public func historyForContext(maxTurns: Int = 60) -> [String] {
        var result: [String] = []
        if let summary = currentRollingSummary(), !summary.isEmpty {
            result.append("[Resumo episódico anterior: \(summary)]")
        }
        result.append(contentsOf: messages.suffix(maxTurns).map { msg in
            "\(msg.role == .user ? "User" : "Beagle"): \(msg.content)"
        })
        return result
    }

    // MARK: - Derived

    public var isEmpty: Bool { messages.isEmpty }
    public var lastMessage: ChatMessage? { messages.last }
    public var lastUserMessage: ChatMessage? { messages.last(where: { $0.role == .user }) }
    public var lastAssistantMessage: ChatMessage? { messages.last(where: { $0.role == .assistant }) }
    public var lastUpdatedAt: Date? { messages.last?.timestamp }

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

    public func seedPreviewConversation(_ sampleMessages: [ChatMessage]) {
        clear()
        messages = sampleMessages
        for message in sampleMessages {
            persist(message: message)
        }
        isStreaming = false
    }

    private func persist(message: ChatMessage) {
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

    private func autoImportExchange(
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

    // MARK: - GPT-Live (`gpt-live-1.1`) Full-Duplex Bubbles & Client Delegation (MoE + Bula + MCP)

    public enum DeepVoiceDelegationKind: String, Sendable, Equatable {
        case modoFundo = "modo_fundo"
        case rosalindBio = "rosalind_bio"
        case morningSynthesis = "morning_synthesis"
    }

    /// Detecta se o pedido falado na sessão `gpt-live-1.1` exige deliberação assíncrona pesada
    /// (`Modo Fundo`, `GPT-Rosalind PBPK/Bio` ou `Síntese Matinal`), permitindo retorno falado imediato
    /// + execução real em segundo plano com Dynamic Island e retorno por voz ao concluir.
    public nonisolated static func classifyDeepVoiceIntent(_ utterance: String) -> DeepVoiceDelegationKind? {
        let lower = utterance
            .lowercased()
            .folding(options: .diacriticInsensitive, locale: Locale(identifier: "pt_BR"))

        if lower.contains("sintese matinal")
            || lower.contains("briefing matinal")
            || lower.contains("resumo da manha")
            || lower.contains("resumo do dia")
            || lower.contains("briefing do dia") {
            return .morningSynthesis
        }

        if lower.contains("modo fundo")
            || lower.contains("explora a fundo")
            || lower.contains("explorar a fundo")
            || lower.contains("pesquisa profunda")
            || lower.contains("go deeper")
            || lower.contains("mesa redonda") {
            return .modoFundo
        }

        if lower.contains("rosalind")
            || lower.contains("pbpk")
            || lower.contains("farmacocinetica")
            || lower.contains("biodisponibilidade")
            || lower.contains("meia-vida plasmatica") {
            return .rosalindBio
        }

        return nil
    }

    ///Nota contextual compacta (`developer` em `session.input`) para abrir sessões `gpt-live-1.1`
    /// já alinhadas ao fisioma, clima espacial, projeto ativo e memória episódica recente.
    public func buildGPTLiveAgoraNote() -> String? {
        var parts: [String] = ["Projeto ativo: \(projectSlug). Conversa: \(currentConversationTitle)."]
        if let physio = physioSummary {
            var p: [String] = ["Prontidão \(physio.readiness.rawValue)"]
            if let hrv = physio.hrvMs { p.append(String(format: "HRV %.0f ms", hrv)) }
            if let sleep = physio.sleepHours { p.append(String(format: "Sono %.1fh", sleep)) }
            parts.append("Fisioma: " + p.joined(separator: " · "))
        }
        if let sky = currentSky {
            parts.append(String(format: "Clima geomagnético: %@ (Kp %.1f)", sky.band.rawValue, sky.kp))
        }
        if let roll = currentRollingSummary(), !roll.isEmpty {
            parts.append("Resumo episódico desta conversa: " + String(roll.suffix(420)))
        } else if let cross = recentCrossThreadDigest(maxThreads: 2), !cross.isEmpty {
            parts.append("Conversas recentes: " + String(cross.prefix(320)))
        }
        return parts.joined(separator: " ")
    }

    /// Atualiza ou consolida uma bolha de transcrição full-duplex vinda do `gpt-live-1.1`,
    /// persistindo no SwiftData/Spotlight e sincronizando turnos fechados com a memória do cluster.
    public func upsertGPTLiveBubble(
        id: UUID,
        role: MessageRole,
        text: String,
        isFinal: Bool,
        executedTools: [String] = []
    ) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        let modelTag: String? = (role == .assistant) ? OpenAILiveProtocol.liveModel : nil
        let sourceTag: String? = (role == .assistant) ? "openai-gpt-live" : nil

        if let idx = messages.firstIndex(where: { $0.id == id }) {
            let wasAlreadyFinal = !messages[idx].isStreaming
            messages[idx].content = trimmed
            messages[idx].isStreaming = !isFinal
            if !executedTools.isEmpty {
                messages[idx].executedTools = Self.mergeUniqueTools([messages[idx].executedTools, executedTools])
            }
            if isFinal && !wasAlreadyFinal {
                persist(message: messages[idx])
                if role == .assistant,
                   let prevUser = messages[..<idx].last(where: { $0.role == .user }) {
                    let settledAssistant = messages[idx]
                    Task { @MainActor [weak self] in
                        await self?.syncTurnToClusterMemory(
                            user: prevUser,
                            assistant: settledAssistant,
                            sourceSurface: "beagle-apple-gpt-live",
                            alsoIngestSpine: true
                        )
                    }
                }
            }
        } else {
            let msg = ChatMessage(
                id: id,
                role: role,
                content: trimmed,
                isStreaming: !isFinal,
                model: modelTag,
                source: sourceTag,
                executedTools: executedTools
            )
            messages.append(msg)
            if isFinal {
                persist(message: msg)
                if role == .assistant,
                   let prevUser = messages.dropLast().last(where: { $0.role == .user }) {
                    Task { @MainActor [weak self] in
                        await self?.syncTurnToClusterMemory(
                            user: prevUser,
                            assistant: msg,
                            sourceSurface: "beagle-apple-gpt-live",
                            alsoIngestSpine: true
                        )
                    }
                }
            }
        }
    }

    /// Executa uma delegação `client` do `gpt-live-1.1` no cérebro MoE completo do Beagle
    /// (Bula/PCDT verbatim + GraphRAG++ + rascunho local sem censura + OpenAI/Claude + MCP + Apple Tools).
    public func executeGPTLiveDelegation(
        _ context: OpenAILiveDelegationContext,
        useMoE: Bool = true
    ) async -> OpenAILiveDelegationOutcome {
        let queryText = context.latestUserUtterance.isEmpty
            ? (context.transcriptWindow.last?.text ?? "Verifique o contexto recente da conversa.")
            : context.latestUserUtterance

        // Fast-path: deep asynchronous delegation (Modo Fundo / GPT-Rosalind / Síntese Matinal)
        if let deepKind = Self.classifyDeepVoiceIntent(queryText) {
            switch deepKind {
            case .morningSynthesis:
                if let cached = DailyBriefingBuilder.cachedTodaySynthesis() {
                    let spoken = OpenAILiveProtocol.truncateForLiveAppend(
                        "Síntese matinal de hoje pronta — resuma naturalmente em voz alta os pontos principais para o Demetrios:\n\(cached)",
                        maxChars: 1_200
                    )
                    return OpenAILiveDelegationOutcome(
                        spokenSummary: spoken,
                        backgroundFacts: cached,
                        executedTools: ["daily_briefing_cache"]
                    )
                }

                let slug = projectSlug
                let physio = physioSummary
                let sky = currentSky
                let flow = flowState ?? "NORMAL"
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    let ctx = await DailyBriefingBuilder.gatherLiveContext(
                        captureLines: [],
                        physioSummary: physio,
                        sky: sky,
                        projectSlug: slug
                    )
                    guard let generated = try? await DailyBriefingBuilder.generateMorningSynthesis(
                        context: ctx,
                        projectSlug: slug,
                        flowState: flow
                    ), !generated.isEmpty else { return }
                    DailyBriefingBuilder.saveTodaySynthesis(generated, context: ctx)
                    let bubble = ChatMessage(
                        role: .assistant,
                        content: "### Síntese Matinal\n\n" + generated,
                        model: OpenAIModelCatalog.defaultFlagshipModel,
                        source: "daily-synthesis-voice",
                        executedTools: ["daily_briefing_astra"]
                    )
                    self.messages.append(bubble)
                    self.persist(message: bubble)
                    await self.onTriggerAsyncVoiceFollowup?(
                        "A Síntese Matinal do Demetrios acabou de ficar pronta. Comunique os destaques principais com naturalidade em 3 a 4 frases:\n\(String(generated.prefix(900)))",
                        generated,
                        ["daily_briefing_astra"]
                    )
                }

                return OpenAILiveDelegationOutcome(
                    spokenSummary: "Avise ao Demetrios em uma frase natural que você já está gerando a Síntese Matinal cruzando o fisioma do Apple Watch, o clima espacial NOAA e a agenda das próximas 48 horas, e que vai ler os destaques assim que fechar.",
                    backgroundFacts: nil,
                    executedTools: ["daily_briefing_launch"]
                )

            case .modoFundo, .rosalindBio:
                let lenses: Set<GoDeepModality> = (deepKind == .rosalindBio)
                    ? [.rosalindBio, .astraDeep]
                    : [.astraDeep, .rosalindBio, .swarmConsensus, .causalExtract]
                let label = (deepKind == .rosalindBio) ? "GPT-Rosalind (Bio/PBPK)" : "Modo Fundo (Astra + Rosalind)"
                let slug = projectSlug

                Task { @MainActor [weak self] in
                    guard let self else { return }
                    let deepStore = GoDeepStore(enabledModalities: lenses)
                    let persisted = PersistedDeepSession(prompt: queryText, modalityCount: deepStore.enabledModalities.count)
                    self.modelContext?.insert(persisted)
                    try? self.modelContext?.save()

                    deepStore.onResearchStart = { [weak self] runId, campaign, rSlug in
                        self?.onVoiceResearchStart?(runId, campaign, rSlug, max(2, lenses.count + 1), label)
                    }
                    deepStore.onResearchStateChange = { [weak self] step, total, eta, activeLens, snippet, isCompleted in
                        self?.onVoiceResearchUpdate?(step, total, eta, activeLens, snippet, isCompleted)
                    }
                    deepStore.onSessionComplete = { [weak self] payload in
                        persisted.synthesisText = payload.synthesis
                        persisted.modalityResults = payload.modalityResultsJSON
                        persisted.citationsJSON = payload.citationsJSON
                        persisted.modalityCount = payload.modalityCount
                        persisted.completedAt = payload.completedAt
                        try? self?.modelContext?.save()
                    }

                    await deepStore.goDeeperAndWait(prompt: queryText)
                    guard let synth = deepStore.synthesis, !synth.isEmpty else { return }

                    let tools = deepKind == .rosalindBio ? ["gpt_rosalind_pbpk", "astra_xhigh"] : ["modo_fundo_astra", "gpt_rosalind_pbpk"]
                    let bubble = ChatMessage(
                        role: .assistant,
                        content: "### \(label)\n\n" + synth,
                        model: deepKind == .rosalindBio ? OpenAIModelCatalog.lifeSciencesModel : OpenAIModelCatalog.defaultFlagshipModel,
                        source: "modo-fundo-voice",
                        executedTools: tools
                    )
                    self.messages.append(bubble)
                    self.persist(message: bubble)
                    _ = slug
                    await self.onTriggerAsyncVoiceFollowup?(
                        "A investigação profunda (\(label)) sobre '\(String(queryText.prefix(90)))' acabou de concluir em segundo plano. Sintetize em voz alta a conclusão central e a recomendação prática em 3 a 5 frases diretas:\n\(String(synth.prefix(950)))",
                        synth,
                        tools
                    )
                }

                return OpenAILiveDelegationOutcome(
                    spokenSummary: "Confirme em 1 frase curta e calorosa que você acabou de disparar \(label) em segundo plano (visível na Dynamic Island) e que já vai trazer a síntese verificada assim que as lentes terminarem, enquanto vocês continuam conversando normalmente.",
                    backgroundFacts: "Investigação \(label) iniciada assincronamente para: \(queryText)",
                    executedTools: [deepKind.rawValue]
                )
            }
        }

        presenceNote = useMoE
            ? "GPT-Live · delegando ao MoE, Bula & MCP…"
            : "GPT-Live · consultando memória & ferramentas…"
        defer { presenceNote = nil }

        async let recalledTask = DirectBrainClient.shared.recallRelevantMemory(
            for: queryText,
            projectSlug: projectSlug
        )
        let webPrefetch = await ScienceAndWebBridge.shared.prefetchContextForPrompt(queryText)
        var moeDraft: String? = nil
        if useMoE {
            moeDraft = await generateMoELocalUncensoredDraft(
                for: queryText,
                webBlock: webPrefetch.map { String($0.contextBlock.prefix(3_500)) }
            )
        }
        let recalledMemories = await recalledTask

        let splitBase = await DirectBrainClient.shared.buildSplitSystemPrompt(
            cachedGrounding: cachedGrounding,
            physioSummary: physioSummary,
            physioContext: activeSystemInstruction,
            currentSky: currentSky,
            flowState: flowState,
            sleepQuality01: sleepQuality01,
            voiceTone: nil,
            lastContactAt: lastContactAt,
            rollingSummary: currentRollingSummary(),
            recentThreadDigest: recentCrossThreadDigest(),
            recalledMemories: recalledMemories,
            moeLocalUncensoredDraft: moeDraft
        )

        let delegationSuffix = """


        ## Voice conversation context (GPT-Live Client Delegation)
        Você está apoiando o modelo de voz `gpt-live-1.1` durante uma conversa falada full-duplex ao vivo com o Demetrios.
        As transcrições de voz podem conter hesitações, palavras incompletas ou correções posteriores; use o contexto mais recente e os registros verificados (Bula/PCDT, MCP, GraphRAG++, agenda, lembretes, PubMed/Web).
        Se precisar acionar ferramentas MCP, científicas ou nativas do iPhone, execute-as agora.

        ## Return the result
        Devolva os fatos verificados em português do Brasil direto, objetivo e sem Markdown pesado, em até 140 palavras (~220 tokens), pronto para o `gpt-live-1.1` comunicar naturalmente em voz alta. Se uma ação foi concluída numa ferramenta, confirme o resultado; se faltar um dado indispensável, diga exatamente qual detalhe perguntar.
        """
        let delegationDeveloperPrefix = splitBase.developerPrefix + delegationSuffix
        let delegationFullSystem = splitBase.turnInstructions.isEmpty
            ? delegationDeveloperPrefix
            : delegationDeveloperPrefix + "\n\n" + splitBase.turnInstructions

        let groundedUserPrompt = offlineGroundedPrompt(
            queryText,
            webBlock: webPrefetch?.contextBlock
        )

        var history: [[String: String]] = []
        var turns: [DirectBrainTurn] = []
        for entry in context.transcriptWindow.dropLast() {
            history.append(["role": entry.role, "content": entry.text])
            turns.append(DirectBrainTurn(role: entry.role, content: entry.text))
        }
        history.append(["role": "user", "content": groundedUserPrompt])
        turns.append(DirectBrainTurn(role: "user", content: groundedUserPrompt))

        var toolsUsed: [String] = webPrefetch?.executedTools ?? []
        var rawOutput = ""

        if DirectBrainCredentials.hasOpenAI {
            do {
                let targetModel = DirectBrainCredentials.openAIModel
                let res = try await DirectBrainClient.shared.streamOpenAI(
                    model: targetModel,
                    systemPrompt: delegationFullSystem,
                    developerPrefix: delegationDeveloperPrefix,
                    turnInstructions: splitBase.turnInstructions,
                    reasoningEffort: "low",
                    history: history,
                    turns: turns,
                    projectSlug: projectSlug,
                    onStatus: { [weak self] status in
                        await MainActor.run {
                            self?.presenceNote = status
                        }
                    },
                    onToken: { _ in }
                )
                rawOutput = res.content
                toolsUsed = Self.mergeUniqueTools([toolsUsed, res.executedTools])
            } catch {
                rawOutput = ""
            }
        }

        if rawOutput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let fallback = await client.chat(
                prompt: groundedUserPrompt,
                system: delegationFullSystem,
                projectSlug: projectSlug,
                projectFamily: projectFamily,
                publicationScope: publicationScope,
                discussionProfile: discussionProfile,
                flowState: flowState,
                physioPolicy: physioPolicy,
                history: history
            )
            rawOutput = fallback.value?.response ?? ""
        }

        let cleaned = stripReasoning(rawOutput)
        let summary = OpenAILiveProtocol.truncateForLiveAppend(
            cleaned.isEmpty
                ? "Não consegui confirmar esse dado externo agora; avise o Demetrios com transparência."
                : cleaned,
            maxChars: 1_400
        )

        var backgroundFacts: String? = nil
        if let bula = BulaStore.shared.consulta(queryText) {
            backgroundFacts = OpenAILiveProtocol.truncateForLiveAppend(
                "Referência de bula verificada (\(bula.nomePT) / \(bula.generico), \(bula.citacao)): \(String(bula.texto.prefix(900)))",
                maxChars: 1_200
            )
        }

        lastContactAt = Date()
        return OpenAILiveDelegationOutcome(
            spokenSummary: summary,
            backgroundFacts: backgroundFacts,
            executedTools: toolsUsed
        )
    }
}

// MARK: - Base clínica citável (offline)

/// Um trecho VERBATIM de bula aprovada, com a citação que o permite verificar.
public struct BulaTrecho: Sendable {
    public let nomePT: String
    public let generico: String
    public let citacao: String
    public let texto: String
}

/// Base clínica offline: bulas aprovadas (openFDA/DailyMed) em SQLite, no bundle.
///
/// O propósito NÃO é ensinar o modelo. É dar a ele o parágrafo para COPIAR, com
/// a fonte. Medido: sem isto, perguntado sobre enoxaparina profilática com
/// ClCr~30, o modelo local respondeu "40 mg" — a bula diz 30 mg. O número não
/// pode sair do peso da rede.
public final class BulaStore: @unchecked Sendable {
    public static let shared = BulaStore()

    private struct Farmaco {
        let id: Int64
        let pt: String
        let generico: String
        let marcas: String
        let citacao: String
    }

    private var db: OpaquePointer?
    private var farmacos: [Farmaco] = []
    public private(set) var disponivel = false

    private init() {
        let url = Bundle.main.url(forResource: "bula", withExtension: "sqlite")
            ?? Bundle(for: BulaStore.self).url(forResource: "bula", withExtension: "sqlite")
        guard let url else { return }
        guard sqlite3_open_v2(url.path, &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else { return }
        carregaIndice()
        disponivel = !farmacos.isEmpty
    }

    private func carregaIndice() {
        var st: OpaquePointer?
        let sql = "SELECT id, nome_pt, generico, IFNULL(marcas,''), citacao FROM farmaco"
        guard sqlite3_prepare_v2(db, sql, -1, &st, nil) == SQLITE_OK else { return }
        defer { sqlite3_finalize(st) }
        while sqlite3_step(st) == SQLITE_ROW {
            farmacos.append(Farmaco(
                id: sqlite3_column_int64(st, 0),
                pt: Self.texto(st, 1),
                generico: Self.texto(st, 2),
                marcas: Self.texto(st, 3),
                citacao: Self.texto(st, 4)))
        }
    }

    private static func texto(_ st: OpaquePointer?, _ i: Int32) -> String {
        guard let c = sqlite3_column_text(st, i) else { return "" }
        return String(cString: c)
    }

    // Palavras que casariam por prefixo com nome de fármaco sem ser pedido de dose.
    // Sem esta lista, "para o paciente" acha paracetamol.
    private static let paradas: Set<String> = [
        "para", "pare", "parar", "paciente", "pacientes", "dose", "doses", "dosagem",
        "quanto", "quando", "quantos", "como", "onde", "porque", "pode", "posso",
        "podia", "fazer", "faco", "tenho", "estou", "esta", "esse", "essa", "isso",
        "aqui", "agora", "hoje", "noite", "manha", "tarde", "mais", "menos", "muito",
        "pouco", "sobre", "ainda", "meu", "minha", "seu", "sua", "nao", "sim", "tudo",
        "nada", "algum", "alguma", "plantao", "hospital", "leito", "anos", "idade",
        "peso", "kilo", "quilo", "hora", "horas", "dias", "semana", "mesmo", "melhor",
        "pior", "certo", "errado", "duvida", "ajuda", "preciso", "queria", "acho"
    ]

    // pergunta -> seção da bula que responde, e onde centrar a janela
    private static let gatilhos: [(pergunta: String, secao: String, foco: String?)] = [
        ("renal|clcr|cl cr|creatinin|dialis|tfg|clearance|nefro", "use_in_specific_populations",
         "renal impairment|creatinine clearance|crcl|dialysis"),
        ("hepat|cirros|child pugh", "use_in_specific_populations", "hepatic impairment|liver"),
        ("gestan|gravid|gestacao|amament|lactan", "use_in_specific_populations", "pregnan|lactation|nursing"),
        ("idoso|geriatr", "use_in_specific_populations", "geriatric|elderly"),
        ("contraindic|nao pode usar", "contraindications", nil),
        ("interac|junto com|associad", "drug_interactions", nil),
        ("intoxic|superdos|overdose", "overdosage", nil)
    ]

    private static let janela = 1400
    private static let teto = 4200

    private func normaliza(_ s: String) -> String {
        let f = s.folding(options: [.diacriticInsensitive, .caseInsensitive],
                          locale: Locale(identifier: "pt_BR"))
        return String(f.map { ($0.isLetter || $0.isNumber) ? $0 : " " })
    }

    private func casa(_ regex: String, _ texto: String) -> Bool {
        texto.range(of: regex, options: [.regularExpression, .caseInsensitive]) != nil
    }

    /// A janela com mais densidade de dose entre todas as ocorrências do foco.
    /// Pegar a primeira ocorrência deixava a tabela de ajuste renal de fora.
    private func melhorJanela(_ texto: String, foco: String?) -> String {
        let chars = Array(texto)
        guard let foco, !chars.isEmpty else { return String(chars.prefix(Self.janela)) }
        var inicios: [Int] = []
        var busca = texto.startIndex..<texto.endIndex
        while let r = texto.range(of: foco, options: [.regularExpression, .caseInsensitive], range: busca) {
            inicios.append(texto.distance(from: texto.startIndex, to: r.lowerBound))
            guard r.upperBound < texto.endIndex else { break }
            busca = r.upperBound..<texto.endIndex
        }
        guard !inicios.isEmpty else { return String(chars.prefix(Self.janela)) }
        var melhor = ""
        var melhorPeso = -1
        for i in inicios {
            let ini = max(0, i - 350)
            let fim = min(chars.count, ini + Self.janela)
            let jan = String(chars[ini..<fim])
            let doses = jan.ranges(pattern: "\\d+(\\.\\d+)?\\s?(mg|mcg|units|mL)").count
            let renal = jan.ranges(pattern: "creatinine clearance|crcl|renal impairment|dialysis").count
            // Um título de ajuste de dose vale mais que qualquer densidade: é a
            // seção que existe para responder exatamente esta pergunta.
            let cabecalho = jan.ranges(pattern: "dose reduction|dosage adjustment|dosage in patients with|dosage modification").count
            let peso = cabecalho * 40 + doses * 3 + renal
            if peso > melhorPeso { melhor = jan; melhorPeso = peso }
        }
        return melhor
    }

    private func secoes(_ fid: Int64) -> [String: (titulo: String, texto: String)] {
        var out: [String: (String, String)] = [:]
        var st: OpaquePointer?
        let sql = "SELECT chave, titulo, texto FROM secao WHERE farmaco_id = ?"
        guard sqlite3_prepare_v2(db, sql, -1, &st, nil) == SQLITE_OK else { return out }
        defer { sqlite3_finalize(st) }
        sqlite3_bind_int64(st, 1, fid)
        while sqlite3_step(st) == SQLITE_ROW {
            out[Self.texto(st, 0)] = (Self.texto(st, 1), Self.texto(st, 2))
        }
        return out
    }

    /// Devolve o trecho verbatim, ou nil — e nil significa que o app deve recusar.
    public func consulta(_ pergunta: String) -> BulaTrecho? {
        guard disponivel else { return nil }
        let q = normaliza(pergunta)
        let tokens = q.split(separator: " ").map(String.init)
            .filter { $0.count >= 4 && !Self.paradas.contains($0) }
        guard !tokens.isEmpty else { return nil }

        var achado: (pontos: Int, f: Farmaco)?
        for f in farmacos {
            var candidatos = [f.pt, f.generico]
            candidatos += f.marcas.split(separator: ",").map {
                $0.trimmingCharacters(in: .whitespaces)
            }
            for cand in candidatos {
                for palavra in normaliza(cand).split(separator: " ").map(String.init) where palavra.count >= 4 {
                    for t in tokens where palavra.hasPrefix(t) || t.hasPrefix(palavra) {
                        if achado == nil || t.count > achado!.pontos {
                            achado = (t.count, f)
                        }
                    }
                }
            }
        }
        guard let achado else { return nil }
        let secs = secoes(achado.f.id)

        var foco: String?
        var extra: String?
        for g in Self.gatilhos where casa(g.pergunta, q) {
            foco = g.foco
            extra = g.secao
            break
        }

        var partes: [String] = []
        if let dose = secs["dosage_and_administration"] {
            partes.append("### Posologia e administração\n" + melhorJanela(dose.texto, foco: foco))
        }
        if let extra, let s = secs[extra] {
            partes.append("### \(s.titulo)\n" + melhorJanela(s.texto, foco: foco))
        }
        if let bw = secs["boxed_warning"] {
            partes.append("### Advertência em tarja preta\n" + String(bw.texto.prefix(600)))
        }
        guard !partes.isEmpty else { return nil }
        let corpo = String(partes.joined(separator: "\n\n").prefix(Self.teto))
        return BulaTrecho(nomePT: achado.f.pt, generico: achado.f.generico,
                          citacao: achado.f.citacao, texto: corpo)
    }

    /// Um trecho verbatim de PCDT do Ministério da Saúde, com documento e página.
    public struct PCDTTrecho: Sendable {
        public let texto: String
        public let citacao: String
    }

    /// Camada brasileira: busca por assunto (FTS5), não por nome de fármaco.
    ///
    /// O PCDT responde "qual é a conduta no SUS", que é outra pergunta da bula
    /// — e é a que vale quando as duas divergem no hospital dele.
    /// O PCDT só é consultado quando a mensagem PEDE conduta.
    ///
    /// Sem este portão, \"cara eu to muito cansado hoje\" trazia dois trechos
    /// sobre HIV e tuberculose — texto clínico invadindo uma mensagem emocional,
    /// e pior: a presença de trecho inverte a regra de recusa para citação.
    private static let intencaoClinica = try? NSRegularExpression(
        pattern: "\\b(dose|doses|posologia|dosagem|mg|mcg|ampola|comprimido|esquema|"
            + "tratamento|tratar|profilaxia|conduta|protocolo|ajuste|diluic|infus|"
            + "prescrev|prescric|receit|administr|via oral|intraveno|antibiotic|"
            + "quanto de|quantas|posso dar|pode dar)",
        options: [.caseInsensitive])

    private func pareceClinica(_ q: String) -> Bool {
        guard let re = Self.intencaoClinica else { return false }
        return re.firstMatch(in: q, range: NSRange(q.startIndex..., in: q)) != nil
    }

    public func consultaPCDT(_ pergunta: String, limite: Int = 2) -> [PCDTTrecho] {
        guard disponivel else { return [] }
        guard pareceClinica(normaliza(pergunta)) else { return [] }
        return consultaPCDTDireta(pergunta, limite: limite)
    }

    /// Busca direta FTS5/BM25 nos PCDTs do Ministério da Saúde quando invocada explicitamente por tool-call clínica.
    public func consultaPCDTDireta(_ pergunta: String, limite: Int = 3) -> [PCDTTrecho] {
        guard disponivel else { return [] }
        let tokens = normaliza(pergunta).split(separator: " ").map(String.init)
            .filter { $0.count >= 4 && !Self.paradas.contains($0) }
        guard !tokens.isEmpty else { return [] }
        // FTS5: prefixo em OR. Aspas para não interpretar o token como operador.
        let expr = tokens.prefix(8).map { "\"\($0)\"*" }.joined(separator: " OR ")

        var out: [PCDTTrecho] = []
        var st: OpaquePointer?
        let sql = """
            SELECT p.texto, p.citacao FROM pcdt_busca b
            JOIN pcdt p ON p.id = b.pcdt_id
            WHERE pcdt_busca MATCH ? ORDER BY bm25(pcdt_busca) LIMIT ?
            """
        guard sqlite3_prepare_v2(db, sql, -1, &st, nil) == SQLITE_OK else { return [] }
        defer { sqlite3_finalize(st) }
        let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        sqlite3_bind_text(st, 1, expr, -1, SQLITE_TRANSIENT)
        sqlite3_bind_int(st, 2, Int32(min(limite, 20)))
        while sqlite3_step(st) == SQLITE_ROW {
            out.append(PCDTTrecho(texto: Self.texto(st, 0), citacao: Self.texto(st, 1)))
        }
        return out
    }

    /// Sugere nomes de fármacos próximos na base local quando a busca exata falha.
    public func buscarFarmacosSemelhantes(_ termo: String, limite: Int = 8) -> [String] {
        guard disponivel else { return [] }
        let q = normaliza(termo)
        let tokens = q.split(separator: " ").map(String.init)
            .filter { $0.count >= 3 && !Self.paradas.contains($0) }
        guard !tokens.isEmpty else { return [] }

        var pontuados: [(score: Int, label: String)] = []
        var vistos: Set<String> = []
        for f in farmacos {
            let label = "\(f.pt) (\(f.generico))"
            guard !vistos.contains(label) else { continue }
            let alvo = normaliza("\(f.pt) \(f.generico) \(f.marcas)")
            var score = 0
            for t in tokens {
                let prefix3 = String(t.prefix(3))
                if alvo.contains(t) {
                    score += t.count * 3
                } else if alvo.contains(prefix3) {
                    score += 2
                }
            }
            if score > 0 {
                vistos.insert(label)
                pontuados.append((score, label))
            }
        }
        return pontuados
            .sorted { $0.score > $1.score }
            .prefix(limite)
            .map(\.label)
    }
}

private extension String {
    func ranges(pattern: String) -> [Range<String.Index>] {
        var out: [Range<String.Index>] = []
        var busca = startIndex..<endIndex
        while let r = range(of: pattern, options: [.regularExpression, .caseInsensitive], range: busca) {
            out.append(r)
            guard r.upperBound < endIndex else { break }
            busca = r.upperBound..<endIndex
        }
        return out
    }
}
