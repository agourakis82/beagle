import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import Observation

// SESSÃO — a conversa de uma lane, montada dos eventos do protocolo.
//
// Por que um modelo próprio, e não `ChatMessage`: uma sessão de agente não é uma conversa. Ela
// tem chamada de ferramenta, diff proposto e pedido de aprovação — três coisas que uma bolha de
// chat não sabe carregar, e que são exatamente o que o operador precisa ver para decidir.
// Reaproveitar a bolha faria diff e aprovação virarem anexo dentro de um balão, que é a forma de
// "nem uma coisa nem outra" que motivou esta rodada.
//
// O transporte é polling com cursor, não socket. A escolha é medida, não preguiça: `seq` é
// monotônico e ATRAVESSA reinício do loomd, então um poll perdido se recupera sozinho na próxima
// volta. Um socket dá latência menor e devolve o problema de reconexão, deduplicação e cursor —
// que é justamente o que o `seq` já resolve. Se a latência incomodar, o teto é SSE no loomd; não
// é remendar aqui.

/// O que o agente fez num passo. `Kind` do loomd, traduzido para o que a tela desenha.
public enum SessionStep: Sendable, Equatable, Identifiable {
    /// O que o operador pediu.
    case prompt(id: Int, text: String, at: Date)
    // `turno` é lido de fora por `Turno.agrupar`: sem ele a trilha é uma sopa em que não se vê
    // onde um pedido acaba e o próximo começa.
    /// O que o agente respondeu, inteiro.
    case message(id: Int, text: String, at: Date)
    /// Ferramenta executada — nome e alvo, uma linha. Não é texto para ler, é rastro para varrer.
    case tool(id: Int, name: String, detail: String, at: Date)
    /// Mudança proposta, em unified diff.
    case diff(id: Int, patch: String, at: Date)
    /// O agente parou e está esperando. `kind` decide o rótulo: patch se desfaz por git, comando não.
    case approval(id: Int, kind: ApprovalKind, detail: String, at: Date)
    /// Algo quebrou. Erro é conteúdo de primeira classe: escondê-lo faz a tela mentir por omissão.
    case failure(id: Int, text: String, at: Date)

    public enum ApprovalKind: String, Sendable, Codable {
        case command, patch, other

        public var label: String {
            switch self {
            case .command: return "rodar um comando"
            case .patch: return "aplicar uma mudança"
            case .other: return "seguir"
            }
        }
        /// Comando não se desfaz; patch sim. A tela diz isso ANTES do toque, não depois.
        public var reversible: Bool { self == .patch }
    }

    public var id: Int {
        switch self {
        case .prompt(let i, _, _), .message(let i, _, _), .tool(let i, _, _, _),
             .diff(let i, _, _), .approval(let i, _, _, _), .failure(let i, _, _):
            return i
        }
    }
    public var at: Date {
        switch self {
        case .prompt(_, _, let t), .message(_, _, let t), .diff(_, _, let t),
             .failure(_, _, let t):
            return t
        case .tool(_, _, _, let t), .approval(_, _, _, let t):
            return t
        }
    }

    /// Quem falou. A tela alinha e colore por isto — e é a pergunta que o olho faz primeiro.
    public var isOperator: Bool { if case .prompt = self { return true }; return false }
}

/// Um TURNO: o pedido, e tudo que o agente fez por causa dele.
///
/// 🚨 Por que agrupar. No primeiro retrato a trilha corria reta — prompt, mensagem, ferramenta,
/// diff, prompt, mensagem — e não havia como ver onde um pedido acabava e o próximo começava. Uma
/// sessão de trabalho de verdade tem dez turnos, e sem fronteira a tela deixa de ser legível
/// exatamente quando fica útil.
public struct Turno: Identifiable, Sendable {
    /// O `seq` do primeiro passo — estável e monotônico, então a lista não se reordena sozinha.
    public let id: Int
    public let passos: [SessionStep]

    public var pedido: String? {
        for p in passos { if case .prompt(_, let t, _) = p { return t } }
        return nil
    }
    public var comecouEm: Date { passos.first?.at ?? Date() }
    public var terminouEm: Date { passos.last?.at ?? Date() }
    /// Quanto durou. `nil` enquanto é o último turno e pode ainda estar correndo — afirmar duração
    /// de algo em curso seria dizer que acabou.
    public func duracao(concluido: Bool) -> TimeInterval? {
        concluido ? terminouEm.timeIntervalSince(comecouEm) : nil
    }
    public var temDiff: Bool { passos.contains { if case .diff = $0 { return true }; return false } }
    public var pedePermissao: Bool {
        passos.contains { if case .approval = $0 { return true }; return false }
    }

    /// Quebra a trilha em turnos. Um turno começa em cada `prompt` do operador.
    ///
    /// O que vem ANTES do primeiro prompt (uma sessão retomada, cujo pedido está fora da janela do
    /// diário) forma um turno sem pedido — e a tela diz isso, em vez de fingir que aquilo pertence
    /// ao próximo pedido, que seria atribuir trabalho ao pedido errado.
    public static func agrupar(_ passos: [SessionStep]) -> [Turno] {
        var fora: [Turno] = []
        var atual: [SessionStep] = []
        for p in passos {
            if p.isOperator, !atual.isEmpty {
                fora.append(Turno(id: atual[0].id, passos: atual))
                atual = []
            }
            atual.append(p)
        }
        if !atual.isEmpty { fora.append(Turno(id: atual[0].id, passos: atual)) }
        return fora
    }
}

/// Um evento cru da trama, como o cockpit o devolve em `/turns`.
public struct TramaEvent: Decodable, Sendable {
    public let seq: Int
    public let tsMs: Double
    public let lane: String
    public let kind: String
    public let text: String?
    public let detail: String?
    public let diff: String?
    public let tool: String?
    public let approvalKind: SessionStep.ApprovalKind?

    enum CodingKeys: String, CodingKey {
        case seq, lane, kind, text, detail, diff, tool
        case tsMs = "ts_ms"
        case approvalKind = "approval_kind"
    }

    public var at: Date { Date(timeIntervalSince1970: tsMs / 1000) }
}

@MainActor
@Observable
public final class SessionStore {
    public enum Link: Sendable, Equatable { case idle, live, failed(String) }

    public private(set) var lane: String
    public private(set) var steps: [SessionStep] = []
    /// A trilha agrupada. Derivada, nunca guardada em paralelo — dois lugares com a mesma verdade
    /// divergem, e a lição já foi paga no `detail`/`text`.
    public var turnos: [Turno] { Turno.agrupar(steps) }
    /// A mensagem SENDO ESCRITA agora — os deltas coalescidos do outro lado. Não é um passo:
    /// vira um quando fecha, e mostrá-la como passo faria a lista piscar a cada volta do poll.
    public private(set) var streaming: String?
    public private(set) var link: Link = .idle
    public private(set) var sending = false
    /// A recusa do servidor, nas palavras dele. Ele sabe o motivo; nós inventaríamos um pior.
    public private(set) var note: String?
    public private(set) var lastPollAt: Date?

    /// O maior `seq` já visto. LEGÍVEL de propósito: era `private`, e por isso o teste que dizia
    /// guardar a monotonicidade do cursor ficava VERDE com a regressão aplicada — `apply` guarda o
    /// cursor mas não o observa, então a consequência (o próximo poll pedir do lugar errado) não
    /// era alcançável por nenhuma asserção. Estado que decide a próxima requisição precisa ser
    /// observável, senão o teste sobre ele é teatro.
    public private(set) var cursor = 0
    private let endpoint: FleetEndpoint
    private let session: URLSession
    private var loop: Task<Void, Never>?
    /// Intervalo do poll. 900ms porque é o teto em que texto chegando ainda LÊ como chegando;
    /// mais rápido gasta exec no cluster sem o olho perceber a diferença.
    private let intervalo: Duration = .milliseconds(900)

    public init(lane: String, endpoint: FleetEndpoint = FleetEndpoint(), session: URLSession = .shared) {
        self.lane = lane
        self.endpoint = endpoint
        self.session = session
    }

    /// Fonte PARADA, para retrato e teste — sem rede, como a da Frota. Uma tela que só se
    /// inspeciona ao vivo é uma tela que se desenha no escuro.
    public static func fixture(lane: String, steps: [SessionStep], streaming: String? = nil,
                               link: Link = .live, note: String? = nil) -> SessionStore {
        let s = SessionStore(lane: lane)
        s.steps = steps
        s.streaming = streaming
        s.link = link
        s.note = note
        s.lastPollAt = Date()
        s.parada = true
        return s
    }
    private var parada = false

    public func start() {
        guard !parada, loop == nil else { return }
        loop = Task { [weak self] in
            while !Task.isCancelled {
                await self?.poll()
                try? await Task.sleep(for: self?.intervalo ?? .milliseconds(900))
            }
        }
    }

    public func stop() {
        loop?.cancel()
        loop = nil
    }

    public func poll() async {
        guard let req = endpoint.laneTurnsRequest(sid: lane, since: cursor) else {
            link = .failed("lane inválida: \(lane)")
            return
        }
        do {
            let (data, resp) = try await session.data(for: req)
            let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
            guard (200..<300).contains(code) else {
                link = .failed(Self.motivo(data) ?? "HTTP \(code)")
                return
            }
            let env = try JSONDecoder().decode(Envelope.self, from: data)
            apply(env.data)
            link = .live
            lastPollAt = Date()
        } catch {
            link = .failed(error.localizedDescription)
        }
    }

    /// Aplica uma resposta de poll. Separado da rede de propósito: é aqui que mora a decisão de
    /// como um evento vira passo, e decisão que só se alcança abrindo socket não é testável.
    public func apply(_ page: Page) {
        // O cursor vem PRONTO do servidor. Derivar do último elemento devolve nil num poll sem
        // novidade — e o cliente voltaria ao começo do diário a cada volta silenciosa.
        cursor = max(cursor, page.cursor)
        streaming = page.streaming
        turnoEmCurso = page.turnoEmCurso ?? (page.streaming != nil)
        for e in page.events {
            guard let passo = Self.passo(de: e) else { continue }
            // A trama é append-only e o cursor é monotônico, então repetição só acontece se um
            // poll for reaplicado. Guardar por `seq` é barato e evita a lista duplicar na tela.
            if steps.contains(where: { $0.id == passo.id }) { continue }
            steps.append(passo)
        }
    }

    /// A tradução. `Delta` nunca chega aqui — ele é coalescido no loomd e vem em `streaming`.
    public static func passo(de e: TramaEvent) -> SessionStep? {
        let corpo = e.text ?? e.detail ?? ""
        switch e.kind {
        case "user_prompt":
            return .prompt(id: e.seq, text: corpo, at: e.at)
        case "agent_message":
            return .message(id: e.seq, text: corpo, at: e.at)
        case "diff_proposed":
            guard let d = e.diff, !d.isEmpty else { return nil }
            return .diff(id: e.seq, patch: d, at: e.at)
        case "awaiting_approval":
            return .approval(id: e.seq, kind: e.approvalKind ?? .other, detail: corpo, at: e.at)
        case "error":
            return .failure(id: e.seq, text: corpo.isEmpty ? "erro sem descrição" : corpo, at: e.at)
        case "tool_call", "tool_result":
            return .tool(id: e.seq, name: e.tool ?? "ferramenta", detail: corpo, at: e.at)
        // Ruído de ciclo de vida: existe na trama porque é verdade, e não vira linha na tela
        // porque não é decisão nem conteúdo. Um turno que começa não é notícia.
        case "turn_started", "turn_ended", "session_started", "session_ended",
             "idle", "approval_answered", "unknown", "delta":
            return nil
        default:
            return nil
        }
    }

    // MARK: - Escrever

    /// Manda um pedido. Falha VISÍVEL: um prompt que não chegou não pode parecer que chegou.
    @discardableResult
    public func send(_ text: String) async -> Bool {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty, !sending else { return false }
        guard let req = endpoint.lanePromptRequest(sid: lane, text: t) else {
            note = "lane inválida: \(lane)"
            return false
        }
        sending = true
        note = nil
        defer { sending = false }
        do {
            let (data, resp) = try await session.data(for: req)
            let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
            guard (200..<300).contains(code) else {
                note = Self.motivo(data) ?? "o cockpit recusou (HTTP \(code))"
                return false
            }
            await poll()
            return true
        } catch {
            note = error.localizedDescription
            return false
        }
    }

    /// Há um turno correndo? É o que decide se a tela oferece parar/guiar — e a resposta vem do
    /// servidor (a trama), nunca de um palpite do cliente sobre o último passo visto.
    public private(set) var turnoEmCurso = false

    /// Parar o turno, ou guiá-lo. `texto` vazio = interromper.
    @discardableResult
    public func turno(interromper: Bool, texto: String = "") async -> Bool {
        guard let req = endpoint.laneTurnRequest(sid: lane, interromper: interromper, text: texto) else { return false }
        sending = true
        note = nil
        defer { sending = false }
        do {
            let (data, resp) = try await session.data(for: req)
            let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
            guard (200..<300).contains(code) else {
                // 409 aqui costuma ser "nenhum turno em curso" — recusa do chamador, com motivo.
                note = Self.motivo(data) ?? "o cockpit recusou (HTTP \(code))"
                return false
            }
            await poll()
            return true
        } catch {
            note = error.localizedDescription
            return false
        }
    }

    /// Responde ao pedido de aprovação pendente.
    @discardableResult
    public func approve(_ allow: Bool) async -> Bool {
        guard let req = endpoint.laneApproveRequest(sid: lane, allow: allow) else { return false }
        sending = true
        note = nil
        defer { sending = false }
        do {
            let (data, resp) = try await session.data(for: req)
            let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
            guard (200..<300).contains(code) else {
                note = Self.motivo(data) ?? "o cockpit recusou (HTTP \(code))"
                return false
            }
            await poll()
            return true
        } catch {
            note = error.localizedDescription
            return false
        }
    }

    /// O motivo que o SERVIDOR deu. Ele sabe se a lane é de tela, se a fonte caiu ou se o texto
    /// passou do teto; qualquer frase nossa aqui seria menos específica.
    static func motivo(_ data: Data) -> String? {
        guard let o = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        return (o["error"] as? String).flatMap { $0.isEmpty ? nil : $0 }
    }

    // MARK: - Fio

    public struct Page: Decodable, Sendable {
        public let lane: String
        public let since: Int
        public let cursor: Int
        public let events: [TramaEvent]
        public let streaming: String?
        /// O servidor diz se há turno. Enquanto não disser, um parcial em voo é a melhor pista —
        /// mas ela é PISTA, e o campo explícito manda quando existe.
        public let turnoEmCurso: Bool?

        enum CodingKeys: String, CodingKey {
            case lane, since, cursor, events, streaming
            case turnoEmCurso = "turnRunning"
        }
    }
    struct Envelope: Decodable { let ok: Bool; let data: Page }
}
