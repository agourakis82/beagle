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
        voiceName: String? = nil
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
    /// Set true for one turn (ChatDepth.agente) to ask the server for the read-only agentic
    /// (tool-using) path instead of the plain one-shot voice call. Server: mobile-routes.mjs
    /// completeChatRequest reads `deepThink` at ~L718.
    public var deepThink: Bool = false

    /// Live Activity hooks (set by the view layer, since LiveActivityManager is in BeagleCockpit) —
    /// mirrors the GoDeepStore onResearch* pattern. Lets the user leave the app during the ~14-20s
    /// premium-voice wait (Opus/GPT) and see "pensando…" → the reply resolve on the lock screen.
    public var onCompanionTurnStart: ((String, String) -> Void)?
    public var onCompanionTurnEnd: ((String?) -> Void)?

    /// Friendly voice name for the Live Activity — mirrors ChatDepth's labels (BeagleCockpit layer,
    /// not importable from here) so the lock screen says "Sonnet 5" instead of "claude-sonnet-5".
    private func voiceLabel(for model: String?) -> String {
        switch model {
        case "claude-sonnet-5": return "Sonnet 5"
        case "claude-opus-4-8": return "Opus 4.8"
        case "gpt-5.5": return "GPT 5.5"
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
    public func sendMessage(_ text: String) async {
        // O tom vale para ESTE turno. `defer` roda depois de todos os awaits, então
        // o sinal chega às chamadas do cliente e some antes do turno seguinte —
        // senão a próxima mensagem digitada herdaria a fala anterior.
        defer { sinalDeVozDoTurno = nil }
        // Light, casual messages → instant on-device Apple Intelligence (when available).
        if isLight(text), fastAvailable, fastResponder != nil {
            await sendMessageFast(text)
            return
        }
        // Companion: cloud (rich, grounded, server-side memory ingest) when online; the on-device
        // MLX model when offline — and enqueue the offline turn so the memory spine receives it
        // once connectivity returns. `flowState` still travels in the cloud request body.
        if NetworkMonitor.shared.isOnline {
            await sendMessageCloud(text)
        } else {
            // Sem rede. O engine esquece o modelo a cada abertura do app, então
            // tentar restaurar AQUI é a diferença entre responder e não existir.
            // Só carrega o que já está no aparelho: nunca baixa GB no celular.
            var pronto = llm.isReady
            if !pronto { pronto = await llm.restaurarUltimoModelo() }
            if pronto {
                await sendMessageLocal(text)
                enqueueOffline(userText: text)
            } else {
                await sendMessageCloud(text)
            }
        }
        // Mantém o grounding offline fresco enquanto há rede. Fire-and-forget: nunca
        // atrasa a resposta, nunca derruba o turno.
        if NetworkMonitor.shared.isOnline {
            Task { @MainActor [weak self] in await self?.refreshGroundingIfStale() }
        }
    }

    /// Atualiza o cache de identidade quando está ausente ou com mais de 2h.
    public func refreshGroundingIfStale() async {
        if let at = groundingCachedAt, Date().timeIntervalSince(at) < 7200 { return }
        let result = await client.fetchCompanionGrounding()
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
            let result = await client.ingestTurn(IngestTurnRequest(
                session_id: item.sessionId, userText: item.userText, assistantText: item.assistantText,
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
        // SOTA-chat: optimistic UI — user bubble + empty streaming assistant bubble are appended
        // synchronously, before any network/model await, so send feels instant.
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
                    heartRate: physioSummary?.heartRate, stateOfMind: physioSummary?.stateOfMind, stateOfMindLabel: physioSummary?.stateOfMindLabel,
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

    private func offlineGroundedPrompt(_ text: String) -> String {
        // USUÁRIO: só o que muda no turno. O grounding e as regras vão no papel de
        // SISTEMA (instrucoesOffline) — misturar os dois foi o bug.
        let bula = BulaStore.shared.consulta(text)
        let pcdt = BulaStore.shared.consultaPCDT(text)
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

    // SOTA-chat: word-grouped stream buffering.
    /// Reveal up to the last completed word — i.e. everything through the final whitespace or
    /// newline — holding back the trailing in-progress word. Combined with the ~40ms repaint
    /// window in the stream loop, this makes the cloud reply land word-by-word (calm, natural)
    /// instead of char/token-jerky, while never altering the final text (the loop's post-pass
    /// commits the full `streamedText`). Returns "" until the first boundary exists.
    private func wordGroupedPrefix(_ s: String) -> String {
        guard let boundary = s.lastIndex(where: { $0.isWhitespace }) else { return "" }
        return String(s[...boundary])
    }
    private func stripReasoning(_ text: String) -> String { Self.semRaciocinio(text) }

    // MARK: - Send via on-device LLM

    /// Send using the on-device MLX model (streaming).
    public func sendMessageLocal(_ text: String) async {
        guard llm.isReady else {
            // Fallback to cloud
            await sendMessageCloud(text)
            return
        }

        // SOTA-chat: optimistic UI — user bubble + empty streaming assistant bubble appended
        // synchronously before the first model await, so the send registers instantly.
        let userMessage = ChatMessage(role: .user, content: text)
        messages.append(userMessage)
        persist(message: userMessage)
        // Papéis separados: quem ele é vai como SISTEMA, o turno vai como fala.
        // O texto é o MESMO todo turno, então aplicarInstrucoes vira no-op depois
        // da primeira vez — a sessão sobrevive e o prefill fica pago.
        llm.aplicarInstrucoes(instrucoesOffline() + llm.sufixoSemRaciocinio)
        let prompt = offlineGroundedPrompt(text)

        let assistantId = UUID()
        let modelName = llm.currentModel?.displayName ?? "local"
        let placeholder = ChatMessage(
            id: assistantId, role: .assistant, content: "",
            isStreaming: true, model: modelName, isLocal: true
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
            await autoImportExchange(
                user: userMessage,
                assistant: messages[idx],
                sourceSurface: "beagle-apple-local"
            )
        }
        isStreaming = false
    }

    // MARK: - Send via cloud (HERMES)

    /// Send using the cloud backend (beagle-core /api/v1/chat).
    public func sendMessageCloud(_ text: String) async {
        // Build history BEFORE appending new user message — pass as STRUCTURED
        // turn-based messages (role+content), NOT a "User: ... Assistant: ..."
        // concatenated string. Smart models (Grok) read concatenated transcripts
        // as text-to-continue and hallucinate the next user line.
        let history: [[String: String]] = messages
            .suffix(16)   // C: widen in-conversation memory (10→16) so long threads don't forget the opening turns
            .map { ["role": $0.role == .user ? "user" : "assistant", "content": $0.content] }
        let contextualPrompt = text

        // SOTA-chat: optimistic UI — the user bubble and the empty streaming assistant bubble
        // (isStreaming=true) are appended here, BEFORE any network await (chatStream below only
        // builds the async sequence; the first await is in the `for try await` loop). Send is
        // instant; no artificial delay is introduced.
        let userMessage = ChatMessage(role: .user, content: text)
        messages.append(userMessage)
        persist(message: userMessage)

        let assistantId = UUID()
        let placeholder = ChatMessage(id: assistantId, role: .assistant, content: "", isStreaming: true)
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
        // then stamp this exchange as the new "last contact" for the next turn. First send →
        // previousContact == nil → the server frames it as a first contact.
        let previousContact = lastContactAt
        lastContactAt = Date()

        // Presence is a signal about THIS turn; it must not survive it, on any exit path.
        defer { presenceNote = nil }

        // STREAM tokens live from /api/mobile/v1/chat/stream. The user sees the
        // companion typing as the model emits — no more 7-9s frozen wait.
        // Falls back to the buffered /chat endpoint on stream failure so the chat
        // never goes completely dark.
        let stream = client.chatStream(
            prompt: contextualPrompt,
            system: activeSystemInstruction,
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
            heartRate: physioSummary?.heartRate, stateOfMind: physioSummary?.stateOfMind, stateOfMindLabel: physioSummary?.stateOfMindLabel,
            kp: currentSky?.kp, dst: currentSky?.dst,
            solarWind: currentSky?.solarWindSpeed, bz: currentSky?.bz,
            voiceModel: voiceModel,
            deepThink: deepThink,
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
        // O publicador por PARÁGRAFO deste ramo saiu na fusão em favor do publicador por
        // PALAVRA do outro (ver a decisão dentro do laço). `publishedLen`/`lastPublish`
        // eram só dele e foram removidos junto — deixá-los seria código morto.
        var streamErr: Error? = nil
        // SOTA-chat: word-grouped repaint window. Raw SSE deltas accumulate in `streamedText`
        // (the source of truth) and are painted into the bubble at most once per ~40ms, aligned
        // to word boundaries — a calm, natural reveal, not char-jerky and not artificially slow.
        // Time-gated on the main actor (no extra Task/Timer) to stay @Observable/Sendable-safe.
        let flushWindow: Duration = .milliseconds(40)
        var lastFlushAt = ContinuousClock.now
        do {
            for try await token in stream {
                streamedText += token
                guard let idx = messages.firstIndex(where: { $0.id == assistantId }) else { continue }
                // DECISAO DE FUSAO: os dois ramos escreveram publicadores incrementais
                // diferentes — um por PARAGRAFO, outro por PALAVRA. Fica o por palavra
                // (mais liso) e fica a LINHA DE PRESENCA do outro ramo, porque elas
                // atuam em momentos distintos e nao competem: a presenca cobre a espera
                // ATE o primeiro token; a revelacao cobre o texto DEPOIS dele.
                //
                // First real token evicts the provisional on-device ack; clear it so the
                // word-buffer reveals the grounded reply cleanly rather than blending with it.
                if messages[idx].isProvisional {
                    messages[idx].isProvisional = false
                    messages[idx].content = ""
                }
                presenceNote = nil
                // SOTA-chat: flush only complete words, and only when the ~40ms window elapsed.
                let now = ContinuousClock.now
                if now - lastFlushAt >= flushWindow {
                    lastFlushAt = now
                    let reveal = wordGroupedPrefix(streamedText)
                    if !reveal.isEmpty {
                        messages[idx].content = stripReasoning(reveal)
                    }
                }
            }
        } catch {
            streamErr = error
        }

        if !streamedText.isEmpty {
            if let idx = messages.firstIndex(where: { $0.id == assistantId }) {
                // SOTA-chat: end-of-stream commit — a palavra final retida pela janela
                // sempre aterrissa aqui, com o texto preservado exatamente.
                //
                // E o PORTÃO DA ÚLTIMA MILHA por cima: o app fala com quatro gateways e
                // com o modelo local; nem todo caminho passa pelo portão do cockpit, e
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
                    await self?.autoImportExchange(
                        user: userMessage,
                        assistant: respondida,
                        sourceSurface: "beagle-apple-cloud"
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
            system: activeSystemInstruction,
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
            heartRate: physioSummary?.heartRate, stateOfMind: physioSummary?.stateOfMind, stateOfMindLabel: physioSummary?.stateOfMindLabel,
            kp: currentSky?.kp, dst: currentSky?.dst,
            solarWind: currentSky?.solarWindSpeed, bz: currentSky?.bz,
            voiceModel: voiceModel
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
                    await self?.autoImportExchange(
                        user: userMessage,
                        assistant: respondidaBuf,
                        sourceSurface: "beagle-apple-cloud"
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

        // Remove the assistant response(s) after the last user message
        if let lastAssistantIdx = messages.lastIndex(where: { $0.role == .assistant }) {
            messages.removeSubrange(lastAssistantIdx...)
        }
        // Remove the user message by id (not content) to avoid matching duplicates
        if let userIdx = messages.lastIndex(where: { $0.id == userId }) {
            messages.remove(at: userIdx)
        }

        await sendMessage(prompt)
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
    public func historyForContext(maxTurns: Int = 20) -> [String] {
        messages.suffix(maxTurns).map { msg in
            "\(msg.role == .user ? "User" : "Beagle"): \(msg.content)"
        }
    }

    // MARK: - Derived

    public var isEmpty: Bool { messages.isEmpty }
    public var lastMessage: ChatMessage? { messages.last }
    public var lastUserMessage: ChatMessage? { messages.last(where: { $0.role == .user }) }
    public var lastAssistantMessage: ChatMessage? { messages.last(where: { $0.role == .assistant }) }
    public var lastUpdatedAt: Date? { messages.last?.timestamp }

    public func loadPersistedConversation() {
        guard let modelContext else { return }
        let conversationId = persistenceConversationId
        let descriptor = FetchDescriptor<PersistedMessage>(
            predicate: #Predicate<PersistedMessage> { message in
                message.conversationId == conversationId
            },
            sortBy: [SortDescriptor(\PersistedMessage.sentAt, order: .forward)]
        )

        guard let persisted = try? modelContext.fetch(descriptor) else { return }
        messages = persisted.map { stored in
            ChatMessage(
                role: MessageRole(rawValue: stored.role) ?? .assistant,
                content: stored.content,
                timestamp: stored.sentAt,
                isStreaming: false,
                model: stored.model,
                tokensUsed: stored.tokensUsed,
                isLocal: stored.isLocal,
                source: stored.source,
                agentKind: stored.agentKind,
                sessionId: stored.sessionId,
                podName: stored.podName
            )
        }
        isStreaming = false
        // Backfill a thread record for legacy/un-recorded conversations so they show in the drawer.
        if !messages.isEmpty {
            touchConversationRecord(firstUserText: messages.first(where: { $0.role == .user })?.content)
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
        let persisted = PersistedMessage(
            role: message.role.rawValue,
            content: message.content,
            model: message.model,
            tokensUsed: message.tokensUsed,
            isLocal: message.isLocal,
            source: message.source,
            agentKind: message.agentKind,
            sessionId: message.sessionId,
            podName: message.podName,
            conversationId: persistenceConversationId,
            sentAt: message.timestamp
        )
        modelContext.insert(persisted)
        try? modelContext.save()
        // Keep the thread record fresh (updatedAt for ordering; title from the first user line).
        touchConversationRecord(firstUserText: message.role == .user ? message.content : nil)
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
        sqlite3_bind_int(st, 2, Int32(limite))
        while sqlite3_step(st) == SQLITE_ROW {
            out.append(PCDTTrecho(texto: Self.texto(st, 0), citacao: Self.texto(st, 1)))
        }
        return out
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
