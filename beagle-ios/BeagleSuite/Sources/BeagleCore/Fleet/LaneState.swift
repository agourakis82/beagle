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

/// O que a lane aceita, dito pelo servidor.
///
/// 🚨 NÃO derivar de `sid` nem de `LaneFamily`: `claude-1` (tail) e `claude-4` (ACP) têm o mesmo
/// prefixo e comportamentos opostos. Capacidade é declarada, nunca inferida.
public enum Aceita: String, Sendable, Codable, Equatable {
    case redireciona
    case enfileira
    case somenteLeitura = "somente_leitura"
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
    /// O que esta lane aceita. `nil` = o servidor não declarou; a tela então não oferece gesto.
    public let aceita: Aceita?
    /// O custo acumulado da lane, em USD — SOMADO NO SERVIDOR (loomd), a partir dos `Turno.uso`
    /// de cada turno. O Swift NÃO recalcula: o `LaneCard` só tem este snapshot, sem acesso aos
    /// eventos por turno que o custo exigiria somar corretamente (último `usd` não-zero por
    /// turno, nunca a soma bruta — ver `Turno.uso`). Duas fontes calculando o mesmo número
    /// divergem, e nenhuma fica confiável.
    ///
    /// Valor padrão `0` no `init` explícito: zero é o valor HONESTO aqui, porque o servidor
    /// OMITE a chave `usd` do JSON quando não houve cobrança (`serde skip_serializing_if`) — a
    /// ausência da chave não é "desconhecido", é "zero".
    public let usd: Double
    /// O unified diff da mudança que esta lane está pedindo para aplicar. `nil` = não há mudança
    /// proposta (ou o servidor não a mandou); string vazia NUNCA chega aqui — vazio é um texto
    /// ("propôs um diff em branco") e ausente é outra coisa, então o parser degrada vazio a `nil`.
    ///
    /// 🚨 Este campo existe porque o dado ATRAVESSAVA Rust e Node e morria aqui. O loomd emite
    /// `last_diff` (`Option<String>`), o cockpit repassa `diff` (`loomd.mjs`), e o `LaneSnapshot`
    /// não tinha onde guardá-lo — então o card que PEDE DECISÃO mostrava o cromo cru do agente
    /// ("Press enter to confirm or esc to cancel") e dois cards de lanes diferentes ficavam
    /// idênticos. Não é que ninguém desenhou o card: ele não tinha o que mostrar.
    public let diff: String?
    /// O QUE está sendo aprovado — comando ou patch —, dito pelo servidor (`pending_kind` no
    /// loomd, `approvalKind` no cockpit). `nil` = o servidor não declarou; a tela então não
    /// afirma natureza nenhuma, em vez de chutar "patch" e prometer reversibilidade por git a
    /// um `rm -rf`.
    ///
    /// Reaproveita `SessionStep.ApprovalKind` (mesmo vocabulário, mesmos rótulos, mesma regra de
    /// reversibilidade) em vez de um enum paralelo: dois tipos para o mesmo fato divergem.
    public let approvalKind: SessionStep.ApprovalKind?
    /// O ÚLTIMO evento do protocolo nesta lane, como o loomd o nomeia (`agent_message`,
    /// `tool_call`, `awaiting_approval`, `session_started`…). `nil` = o servidor não declarou.
    ///
    /// Existe por uma razão só: escolher a VOZ da linha de evidência. `detail` carrega o texto,
    /// e só o kind diz que TIPO de coisa aquele texto é — algo que o agente DISSE, ou cromo de
    /// máquina. Sem ele a tela decidia pelo ESTADO da lane, que é o eixo errado: um agente
    /// falando enquanto trabalha e um agente falando enquanto espera dizem a mesma espécie de
    /// coisa, e saíam em faces diferentes.
    public let loomdKind: String?

    public var id: String { sid }
    public var family: LaneFamily { LaneFamily.of(sid) }
    public var needsOperator: Bool { state.needsOperator }

    /// The lane does not exist in tmux at all — it was seeded in the roster but never created
    /// (measured 2026-08-09: grok-cli1, grok-cli2, codex-3). Different from "it ran and ended",
    /// and very different from `unknown`; the card must not offer actions on a lane that is
    /// not there. The server states this in `detail`, so the client never has to infer it.
    // ⚠️ DÍVIDA: capacidade deduzida de prosa. A frase vem do LanePoller do project-cockpit (Node),
    // não do loomd — consertar exige tocar naquele serviço. Ver o spec desta fatia, §1.
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
        pendingApproval: Bool = false,
        aceita: Aceita? = nil,
        usd: Double = 0,
        diff: String? = nil,
        approvalKind: SessionStep.ApprovalKind? = nil,
        loomdKind: String? = nil
    ) {
        self.sid = sid; self.title = title; self.state = state; self.detail = detail
        self.peek = peek; self.approve = approve; self.atShell = atShell
        self.observedAt = observedAt
        // Default `.inferred` pela mesma razão de `atShell: false`: quem constrói sem dizer
        // a procedência não a conhece.
        self.confidence = confidence
        self.pendingApproval = pendingApproval
        self.aceita = aceita
        // Default `0` pela mesma razão de `aceita: nil`: quem constrói sem dizer o custo não o
        // conhece, e o servidor trata "não sei" e "zero" como a mesma coisa (chave omitida).
        self.usd = usd
        // Defaults `nil` pela mesma razão de `aceita: nil`: quem constrói sem dizer o que está
        // sendo aprovado não sabe — e a tela cala em vez de inventar.
        self.diff = diff
        self.approvalKind = approvalKind
        self.loomdKind = loomdKind
    }

    /// True when the observation is too old to present as current. The card must then show it
    /// as stale rather than asserting a fresh truth (platform truth-mode invariant).
    public func isStale(now: Date = Date(), toleranceSeconds: TimeInterval = 45) -> Bool {
        guard let observedAt else { return true }
        return now.timeIntervalSince(observedAt) > toleranceSeconds
    }

    /// Decode one entry of a Loom `{t:"sessions"}` frame. Unknown/absent fields degrade
    /// honestly to `.unknown` + no evidence rather than to a confident default.
    /// Decodifica uma lane do fio — e é o **ÚNICO** caminho de decodificação que existe.
    ///
    /// 🚨 Antes havia DOIS: este, para o quadro cheio `{t:"sessions"}`, e uma reconstrução
    /// campo-a-campo dentro de `FleetStateClient` para o patch `{t:"state"}`. Os dois divergiam, e
    /// divergiram **seis vezes** — `confidence`, `aceita`, `usd`, o congelamento do `usd`,
    /// `diff`/`approvalKind`, `loomdKind` — sempre do mesmo jeito: o campo novo entrava aqui e
    /// ninguém lembrava do outro lado. Nenhum formato de fio detecta isso: esquecer de LER um campo
    /// é propriedade do código, não do encoding. A cura é não ter dois lugares para esquecer.
    ///
    /// `mesclandoCom` é o que unifica os dois casos, em vez de escondê-los:
    ///   • `nil` (quadro cheio) — chave ausente cai no default HONESTO do campo;
    ///   • uma lane (patch) — chave ausente é SILÊNCIO e preserva o valor antigo.
    ///
    /// E em todo campo com vocabulário fechado, CHAVE AUSENTE e VALOR ILEGÍVEL são casos
    /// diferentes: ausente preserva, ilegível degrada para o lado seguro. Somar os dois no mesmo
    /// `?? antigo` foi o defeito que manteve `GUIAR` numa lane que o servidor tornou
    /// somente-leitura.
    public init?(loom obj: [String: Any], mesclandoCom antigo: LaneSnapshot? = nil) {
        guard let sid = obj["sid"] as? String else { return nil }
        self.sid = sid
        self.title = (obj["title"] as? String) ?? antigo?.title ?? sid
        // Estado ilegível degrada para `.unknown` nos DOIS casos: aqui o lado seguro é admitir
        // ignorância, não preservar um estado que pode ter mudado.
        self.state = LaneState(rawValue: (obj["state"] as? String) ?? "") ?? .unknown
        self.detail = (obj["detail"] as? String) ?? antigo?.detail ?? ""
        self.peek = (obj["peek"] as? [Any])?.compactMap { $0 as? String } ?? antigo?.peek ?? []
        // Um patch que mantivesse a affordance ANTIGA deixaria um botão de aprovar numa lane que
        // já passou para uma pergunta que precisa de resposta digitada.
        self.approve = obj["approveKey"] == nil
            ? (antigo?.approve ?? ApproveAffordance(approveKey: nil))
            : ApproveAffordance(approveKey: obj["approveKey"] as? String)
        // Chave ausente = não é shell. Chutar "shell" desenharia um botão que o servidor recusa.
        self.atShell = (obj["atShell"] as? Bool) ?? antigo?.atShell ?? false
        // `ms <= 0` é o vocabulário de "nunca observado" do servidor — vira `nil`, não uma data de
        // 1970. O caminho de patch antes aceitava qualquer número e fabricava essa data.
        self.observedAt = (obj["observedAt"] as? Double)
            .flatMap { $0 > 0 ? Date(timeIntervalSince1970: $0 / 1000) : nil }
            ?? antigo?.observedAt
        // Um cockpit antigo, que ainda não manda `confidence`, não pode fazer a Frota afirmar que
        // raspagem de tela é medição — daí o piso `.inferred` quando não há valor antigo.
        //
        // 🚨 ASSIMETRIA DELIBERADA com `aceita`, logo abaixo, e ela tem teste próprio
        // (`testAStatePatchThatDeclaresConfidenceWins`): aqui valor ILEGÍVEL **preserva**, ali
        // ilegível **degrada**. Não é descuido — os riscos têm formas opostas. Rebaixar uma lane
        // medida a `inferred` por causa de um token que este binário ainda não conhece é uma FALSA
        // DEMOÇÃO: apaga o contraste que a Frota existe para mostrar, sem que nada tenha mudado.
        // Já preservar `aceita` OFERECE UM GESTO que o servidor pode ter acabado de revogar, e o
        // botão falha na mão do operador. Quando errar de um lado custa contraste e do outro custa
        // uma ação quebrada, os dois campos não podem ter a mesma regra.
        self.confidence = Confidence(rawValue: (obj["confidence"] as? String) ?? "")
            ?? antigo?.confidence ?? .inferred
        // Ausente = não há pendência. Degradar para "tem pedido" desenharia um botão sem o que
        // responder — e o servidor recusaria com 409.
        self.pendingApproval = obj["pendingApproval"] == nil
            ? (antigo?.pendingApproval ?? false)
            : !(obj["pendingApproval"] is NSNull)
        // Afirmação sobre CAPACIDADE ATUAL: ilegível vira `nil` (a tela não oferece gesto nenhum)
        // em vez de preservar um `GUIAR` que o servidor pode ter acabado de revogar.
        self.aceita = obj["aceita"] == nil
            ? antigo?.aceita
            : (obj["aceita"] as? String).flatMap(Aceita.init(rawValue:))
        // FATO DO PASSADO: silêncio nunca pode virar zero — um gasto já ocorrido não desaparece
        // porque o servidor calou. E ausência de chave no quadro cheio É zero, porque o servidor
        // omite `usd` quando não houve cobrança (`serde skip_serializing_if`).
        self.usd = (obj["usd"] as? Double) ?? antigo?.usd ?? 0
        // Vazio degrada a `nil` de propósito: o cockpit já normaliza isso do lado dele, e concordar
        // com ele evita a tela desenhar um bloco de diff sem uma linha dentro.
        self.diff = obj["diff"] == nil
            ? antigo?.diff
            : (obj["diff"] as? String).flatMap { $0.isEmpty ? nil : $0 }
        // Vocabulário desconhecido = `nil`: um binário que ainda não sabe ler um tipo novo de
        // aprovação fica CALADO sobre a natureza dela, em vez de rebaixá-la a `.other` e prometer
        // reversibilidade por git a um `rm -rf`.
        self.approvalKind = obj["approvalKind"] == nil
            ? antigo?.approvalKind
            : (obj["approvalKind"] as? String).flatMap(SessionStep.ApprovalKind.init(rawValue:))
        // `null` explícito é o servidor admitindo que perdeu a fonte exata — a evidência volta a
        // ser lida como leitura de máquina. Não pode virar `?? antigo`.
        self.loomdKind = obj["loomdKind"] == nil
            ? antigo?.loomdKind
            : (obj["loomdKind"] as? String)
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
