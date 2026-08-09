import Foundation

/// What a lane is doing, as reported by the Loom broker's read-only screen peek.
/// `unknown` is a first-class case on purpose: the board must be able to say "I have not
/// observed this lane yet" instead of defaulting to a comfortable-looking `idle`.
public enum LaneState: String, Sendable, Codable, CaseIterable {
    case waiting, stuck, running, idle, exited, unknown

    /// Ranking for the Frota board: who needs you first. Lower sorts higher.
    /// waiting (a human is the blocker) → stuck (something broke) → running → idle → the rest.
    public var urgency: Int {
        switch self {
        case .waiting: return 0
        case .stuck:   return 1
        case .running: return 2
        case .idle:    return 3
        case .exited:  return 4
        case .unknown: return 5
        }
    }

    /// Does this lane belong on the "PRECISA DE VOCÊ" shelf?
    public var needsOperator: Bool { self == .waiting || self == .stuck }

    /// The glyph half of the triple encoding (light + elevation + glyph), so state survives
    /// for an operator who cannot rely on hue alone.
    public var glyph: String {
        switch self {
        case .waiting: return "◉"
        case .stuck:   return "▲"
        case .running: return "▮"
        case .idle:    return "▪"
        case .exited:  return "◌"
        case .unknown: return "·"
        }
    }

    public var label: String {
        switch self {
        case .waiting: return "precisa de você"
        case .stuck:   return "travado"
        case .running: return "trabalhando"
        case .idle:    return "ocioso"
        case .exited:  return "encerrado"
        case .unknown: return "não observado"
        }
    }
}

/// Which agent family a lane belongs to — the hue that carries identity.
public enum LaneFamily: String, Sendable, CaseIterable {
    case claude, codex, kimi, grok, glm, repo, other

    public static func of(_ sid: String) -> LaneFamily {
        if sid.hasPrefix("claude") { return .claude }
        if sid.hasPrefix("codex") { return .codex }
        if sid.hasPrefix("kimi") { return .kimi }
        if sid.hasPrefix("grok") { return .grok }
        if sid.hasPrefix("glm") { return .glm }
        if sid == "repo" { return .repo }
        return .other
    }
}

/// How the operator can clear a `waiting` lane in one gesture.
public enum ApproveAffordance: Sendable, Equatable {
    /// A permission dialog: Enter accepts the highlighted option.
    case enterKey
    /// A `(y/n)` gate: send `y`.
    case yKey
    /// An open question — it needs a real answer typed, not a keystroke. No 1-tap approve.
    case answerNeeded

    public init(approveKey: String?) {
        switch approveKey {
        case "enter": self = .enterKey
        case "y":     self = .yKey
        default:      self = .answerNeeded
        }
    }

    /// The bytes to inject into the lane. Nil when a real answer is required — the UI must
    /// NOT offer a one-tap button it cannot honestly fulfil.
    ///
    /// Kept for the terminal path (`/ws/loom` `input`). The Frota's one-tap button no longer
    /// uses it: it posts a NAMED key instead, so approving does not require attaching a tmux
    /// client — an attach resizes the pane for every other client on that session.
    public var injection: String? {
        switch self {
        case .enterKey: return "\r"
        case .yKey: return "y\n"
        case .answerNeeded: return nil
        }
    }

    /// The named key to press for a one-touch approval. Nil for `answerNeeded` — and the server
    /// refuses it too, so a client bug cannot press Enter at a question that wants a sentence.
    public var key: FleetEndpoint.LaneKey? {
        switch self {
        case .enterKey: return .enter
        case .yKey: return .y
        case .answerNeeded: return nil
        }
    }
}

/// De ONDE veio o estado desta lane. Não é decoração: separa o que foi medido no protocolo
/// do agente (JSON-RPC do codex app-server / hooks do Claude Code, via loomd) do que foi
/// adivinhado por regex em cima de `tmux capture-pane`.
///
/// A ausência do campo lê `inferred` — o lado seguro. Todo emissor que NÃO sabe a procedência
/// está, por definição, adivinhando; promover ausência a `exact` inventaria uma garantia.
public enum Confidence: String, Sendable, Codable, CaseIterable {
    /// Medido no protocolo: o agente disse, o loomd registrou. Nenhuma tela foi lida.
    case exact
    /// Lido da tela: classificação por regex do `capture-pane` (o LanePoller de hoje).
    case inferred

    /// O glifo da procedência. Reaproveita o vocabulário de `TruthMode` — ● observado,
    /// ○ declarado — porque é a mesma pergunta: isto foi visto ou foi suposto?
    public var glyph: String {
        switch self {
        case .exact:    return "\u{25CF}"   // ●
        case .inferred: return "\u{25CB}"   // ○
        }
    }

    public var label: String {
        switch self {
        case .exact:    return "medido no protocolo"
        case .inferred: return "lido da tela"
        }
    }
}

/// One lane as the Frota board sees it — decoded from a Loom `sessions` entry.
public struct LaneSnapshot: Sendable, Identifiable, Equatable {
    public let sid: String
    public let title: String
    public let state: LaneState
    /// The evidence for `state`: the quoted question, dialog line, or last output line.
    /// The card shows THIS rather than asserting a bare state.
    public let detail: String
    /// Up to 2 opaque terminal lines for the card's peek.
    public let peek: [String]
    public let approve: ApproveAffordance
    /// The lane is sitting at a SHELL, not at an agent's input box. Both read as `idle`, and the
    /// difference decides whether typed text is executed or handed to an agent as a request.
    public let atShell: Bool
    /// When the broker actually observed this lane. Nil = never observed (state is a guess).
    public let observedAt: Date?
    /// A procedência de `state`: medido no protocolo (loomd) ou lido da tela (LanePoller).
    /// Mesmo peso epistêmico de `observedAt` — QUANDO foi visto e COMO foi visto.
    public let confidence: Confidence
    /// A lane tem um pedido de aprovação TIPADO pendente (o loomd o recebeu por RPC).
    /// Diferente de `approve`, que descreve uma TECLA: aqui não há tecla nenhuma — há um pedido
    /// a responder. É este sinal que desenha o botão numa lane servida pelo loomd, e sem ele o
    /// card exato caía na folha de "Responder", cuja resposta era engolida em silêncio.
    public let pendingApproval: Bool

    public var id: String { sid }
    public var family: LaneFamily { LaneFamily.of(sid) }
    public var needsOperator: Bool { state.needsOperator }

    /// The lane does not exist in tmux at all — it was seeded in the roster but never created
    /// (measured 2026-08-09: grok-cli1, grok-cli2, codex-3). Different from "it ran and ended",
    /// and very different from `unknown`; the card must not offer actions on a lane that is
    /// not there. The server states this in `detail`, so the client never has to infer it.
    public var isAbsent: Bool {
        state == .exited && detail.localizedCaseInsensitiveContains("não existe no tmux")
    }

    /// What the card calls this lane's presence.
    public var presenceLabel: String { isAbsent ? "ausente" : state.label }

    /// Como o card NOMEIA a procedência — para leitor de tela e para quem não distingue as
    /// duas cores. Sem isto o campo existiria só em cor+glifo dentro de um card `.combine`.
    public var confidenceLabel: String { confidence.label }

    /// Existe uma sessão tmux por trás desta lane, ou seja: dá para ABRIR um terminal nela?
    ///
    /// Uma lane do loomd (`loom-1`) é supervisionada por JSON-RPC e não tem pty do outro lado.
    /// Oferecer "Abrir lane" ali é oferecer um erro — e foi o que aconteceu enquanto o roster de
    /// terminais e o allowlist de ação eram a mesma lista.
    public var hasTerminal: Bool { FleetEndpoint.hasTerminal(sid) }

    /// Por que este card não tem "Abrir lane". Um botão que some sem explicação vira suspeita
    /// de bug; a frase é curta e fica no lugar dele.
    public var noTerminalReason: String { "sem terminal — supervisionada por protocolo" }

    /// Moving a lane into its own worktree types a `cd`, so it needs TWO things: the lane at
    /// rest, and the lane at a **shell**. `idle` alone is not enough — a lane parked at its
    /// agent's input box is idle too, and there the same text is a REQUEST to the agent rather
    /// than a command. The server enforces both; this only avoids drawing a doomed button.
    public var isIsolatable: Bool { (state == .idle || state == .exited) && atShell && !isAbsent }

    public init(
        sid: String, title: String, state: LaneState, detail: String = "",
        peek: [String] = [], approve: ApproveAffordance = .answerNeeded,
        atShell: Bool = false, observedAt: Date? = nil,
        confidence: Confidence = .inferred,
        pendingApproval: Bool = false
    ) {
        self.sid = sid; self.title = title; self.state = state; self.detail = detail
        self.peek = peek; self.approve = approve; self.atShell = atShell
        self.observedAt = observedAt
        // Default `.inferred` pela mesma razão de `atShell: false`: quem constrói sem dizer
        // a procedência não a conhece.
        self.confidence = confidence
        self.pendingApproval = pendingApproval
    }

    /// True when the observation is too old to present as current. The card must then show it
    /// as stale rather than asserting a fresh truth (platform truth-mode invariant).
    public func isStale(now: Date = Date(), toleranceSeconds: TimeInterval = 45) -> Bool {
        guard let observedAt else { return true }
        return now.timeIntervalSince(observedAt) > toleranceSeconds
    }

    /// Decode one entry of a Loom `{t:"sessions"}` frame. Unknown/absent fields degrade
    /// honestly to `.unknown` + no evidence rather than to a confident default.
    public init?(loom obj: [String: Any]) {
        guard let sid = obj["sid"] as? String else { return nil }
        self.sid = sid
        self.title = (obj["title"] as? String) ?? sid
        self.state = LaneState(rawValue: (obj["state"] as? String) ?? "") ?? .unknown
        self.detail = (obj["detail"] as? String) ?? ""
        self.peek = (obj["peek"] as? [Any])?.compactMap { $0 as? String } ?? []
        self.approve = ApproveAffordance(approveKey: obj["approveKey"] as? String)
        // Absent field = not a shell. Guessing "shell" would draw a button the server refuses.
        self.atShell = (obj["atShell"] as? Bool) ?? false
        if let ms = obj["observedAt"] as? Double, ms > 0 {
            self.observedAt = Date(timeIntervalSince1970: ms / 1000)
        } else {
            self.observedAt = nil
        }
        // Campo ausente OU valor desconhecido = `inferred`. Um cockpit antigo, que ainda não
        // manda `confidence`, não pode fazer a Frota afirmar que raspagem de tela é medição.
        self.confidence = Confidence(rawValue: (obj["confidence"] as? String) ?? "") ?? .inferred
        // Ausente = não há pendência. Degradar para "tem pedido" desenharia um botão que não
        // tem o que responder — e o servidor recusaria com 409.
        self.pendingApproval = obj["pendingApproval"] != nil && !(obj["pendingApproval"] is NSNull)
    }
}

/// Board ordering + the shelf. Pure so it can be tested without a UI.
public enum FrotaBoard {
    /// The whole roster, most-urgent first; ties broken by lane name for a stable layout
    /// (an operator's spatial memory is worth more than novelty ordering).
    public static func ordered(_ lanes: [LaneSnapshot]) -> [LaneSnapshot] {
        lanes.sorted {
            $0.state.urgency != $1.state.urgency
                ? $0.state.urgency < $1.state.urgency
                : $0.sid.localizedStandardCompare($1.sid) == .orderedAscending
        }
    }

    /// The "PRECISA DE VOCÊ" shelf: only lanes actually blocked on the operator.
    public static func shelf(_ lanes: [LaneSnapshot]) -> [LaneSnapshot] {
        ordered(lanes.filter(\.needsOperator))
    }

    /// The lanes that are not asking for anything — the calm part of the board.
    public static func rest(_ lanes: [LaneSnapshot]) -> [LaneSnapshot] {
        ordered(lanes.filter { !$0.needsOperator })
    }

    /// The lane ⌘↩ should clear: the oldest observation among one-tap-approvable waiters.
    /// Lanes needing a typed answer are never auto-picked — there is nothing honest to send.
    public static func oldestApprovable(_ lanes: [LaneSnapshot]) -> LaneSnapshot? {
        lanes
            .filter { $0.state == .waiting && $0.approve.injection != nil }
            .min { ($0.observedAt ?? .distantFuture) < ($1.observedAt ?? .distantFuture) }
    }
}
