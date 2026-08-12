import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import Observation

/// The Frota board's data source: ONE Loom socket that only listens for roster/state frames
/// and never subscribes to a lane. Cheap by construction — it carries no terminal bytes, so the
/// board stays live on a phone without streaming 11 PTYs.
///
/// It publishes what the broker observed, including staleness. When the socket drops, lanes are
/// NOT cleared: they keep their last verdict and age visibly, because a board that blanks on a
/// blip is worse than one that admits its data is old.
@MainActor
@Observable
public final class FleetStateClient {
    public enum Link: Sendable, Equatable {
        case idle, connecting, live, reconnecting
        /// 🚨 Achado de review: muitas quedas seguidas, mas o cliente NÃO parou — o laço em
        /// `drop` roda para sempre, com o atraso saturado no teto (`proximoAtrasoMs`). Isto é só
        /// um AVISO para a UI ("está demorando"), nunca uma afirmação de que o motor desligou.
        /// Antes, esse aviso reaproveitava `.failed`, e a `FrotaView` desenhava um botão "Tentar
        /// de novo" como se a reconexão dependesse do operador clicar — exatamente a mentira que
        /// esta fatia existe para matar, e desta vez sobre o próprio transporte que ela conserta.
        case insistindo(motivo: String, tentativas: Int)
        /// Parou de vez. Só por erro de CONFIGURAÇÃO (endpoint inválido) — nada que uma
        /// retentativa resolveria sozinha, então aqui não há mentira em dizer "parei".
        case failed(String)
    }

    public private(set) var link: Link = .idle
    public private(set) var lanes: [LaneSnapshot] = []
    /// When the board last heard anything at all from the broker.
    public private(set) var lastFrameAt: Date?

    /// A saúde da fonte MEDIDA (loomd), do bloco `loomd:{…}` que todo frame `sessions` carrega.
    ///
    /// `nil` = o cockpit nunca falou sobre essa fonte (versão antiga do servidor). É diferente
    /// de `.unknown`, que é o servidor DIZENDO que não sabe — e a tela trata os dois diferente:
    /// sobre o que ninguém afirmou, ela fica calada.
    public private(set) var loomd: LoomdHealth?

    /// As lanes de protocolo, do SERVIDOR quando ele soube dizer; da semente antes disso.
    ///
    /// 🚨 A duplicação que isto mata: `FleetEndpoint.loomdLanes` era uma constante espelhando
    /// `SOUNIO_LOOMD_LANES` no launcher do pod. Editei os dois lados à mão ao adotar `codex-4`, o
    /// que é exatamente como duas listas divergem — e o allowlist é consultado antes de montar
    /// qualquer POST, então uma lane fora dele é descartada em silêncio.
    ///
    /// A semente permanece porque a primeira tela precisa existir antes do primeiro frame; e o
    /// roster do servidor só manda quando ele DISSE algo (`mode == .observed`). Um roster vazio numa
    /// queda do loomd significa "não sei", não "não há lane" — tratar os dois igual esvaziaria a
    /// lista justamente quando a fonte caiu.
    public var loomdRoster: [String] {
        guard let l = loomd, l.mode == .observed, !l.roster.isEmpty else {
            return FleetEndpoint.loomdLanes
        }
        return l.roster
    }

    /// O que a lane aceita, segundo o servidor. `nil` quando a lane não está no último quadro —
    /// e `nil` faz a tela NÃO oferecer gesto, que é o comportamento seguro.
    public func aceita(de sid: String) -> Aceita? {
        lanes.first { $0.sid == sid }?.aceita
    }

    /// Trava: a fonte já respondeu nesta sessão. É o que separa QUEDA de AUSÊNCIA, e portanto
    /// o que decide se a faixa aparece — sem ela, um deploy sem loomd nenhum ganharia banner
    /// permanente, que é como um aviso vira papel de parede.
    private var loomdEverObserved = false

    /// As lanes que sumiram junto com a fonte, acumuladas DESTE lado.
    ///
    /// Não basta repassar o `lost[]` do servidor: ele zera quando o cockpit reinicia, e a lane
    /// continua fora do board. O diff antes/depois feito aqui é o único que o outro lado não
    /// pode apagar. Só é limpo quando a fonte volta a ser observada.
    private var loomdLost: Set<String> = []

    private let endpoint: FleetEndpoint
    private let session: URLSession
    private var task: URLSessionWebSocketTask?
    private var loop: Task<Void, Never>?
    private var retries = 0
    /// NÃO é mais um limite de desistência — ver `drop`. Só decide quando `link` vira
    /// `.insistindo` (aviso de "está demorando"); a retentativa em si nunca para.
    private let maxRetries = 12

    public init(endpoint: FleetEndpoint = FleetEndpoint()) {
        self.endpoint = endpoint
        self.session = URLSession(configuration: .default)
    }

    /// Lanes blocked on the operator — the "PRECISA DE VOCÊ" shelf.
    public var shelf: [LaneSnapshot] { FrotaBoard.shelf(lanes) }
    /// Everything else, calm.
    public var rest: [LaneSnapshot] { FrotaBoard.rest(lanes) }
    /// What ⌘↩ would clear (nil when nothing can be honestly approved with one keystroke).
    public var nextApprovable: LaneSnapshot? { FrotaBoard.oldestApprovable(lanes) }

    /// Uma fonte PARADA: estado colado à mão, socket nenhum.
    ///
    /// Existe porque a Frota só podia ser vista com o cluster de pé E um agente parado no
    /// instante certo — ou seja, quase nunca. Uma tela que só se inspeciona ao vivo é uma tela
    /// que se projeta no escuro, e foi assim que ela chegou a três rodadas de "ainda tá ruim"
    /// sem ninguém conseguir apontar o quê.
    public static func fixture(
        lanes: [LaneSnapshot],
        loomd: LoomdHealth? = nil,
        link: Link = .live,
        lastFrameAt: Date? = Date()
    ) -> FleetStateClient {
        let c = FleetStateClient()
        c.lanes = lanes
        c.loomd = loomd
        c.link = link
        c.lastFrameAt = lastFrameAt
        c.isFixture = true
        return c
    }

    /// Trava dura: uma fonte parada NUNCA abre socket. Sem isto um snapshot dispararia rede de
    /// verdade e, pior, sobrescreveria as lanes coladas com o que o cluster respondesse.
    public private(set) var isFixture = false

    public func connect() {
        guard !isFixture else { return }
        guard link != .live && link != .connecting else { return }
        guard let request = endpoint.loomRequest() else { link = .failed("bad endpoint"); return }
        // 🚨 Achado de review: o guard acima NÃO bloqueia durante `.reconnecting` — de propósito,
        // é o que deixa um `connect()` externo (troca de aba) religar enquanto o cliente já está
        // tentando sozinho. Mas isso abre uma corrida: se uma tentativa interna já tem um socket
        // vivo (ainda não `.live`) quando o externo chega, `task` era apenas SOBRESCRITO — o
        // socket antigo nunca era cancelado, e ficava solto até o servidor fechá-lo sozinho.
        // Cancelar aqui é seguro porque o loop antigo se protege contra o erro que isto gera: ver
        // o guard de identidade em `startLoop`.
        task?.cancel(with: .goingAway, reason: nil)
        closedByCaller = false
        link = (retries == 0) ? .connecting : .reconnecting
        trace("connect -> \(request.url?.absoluteString ?? "?") token=\(endpoint.token == nil ? "nil" : "sim")")
        let t = session.webSocketTask(with: request)
        task = t
        t.resume()
        send(FleetEndpoint.listFrame())
        startLoop()
    }

    public func disconnect() {
        // Order matters: cancel the receive loop FIRST. Cancelling the task while the loop is
        // still awaiting `receive()` makes it throw, which used to run the drop path and
        // resurrect a client the caller had deliberately closed.
        loop?.cancel(); loop = nil
        closedByCaller = true
        task?.cancel(with: .goingAway, reason: nil); task = nil
        link = .idle; retries = 0
        trace("disconnect (pedido pelo chamador)")
    }

    /// Set by `disconnect()` so a late error from the socket cannot schedule a reconnect.
    private var closedByCaller = false

    /// What an action did, in words the card can show. An approval that did not land must never
    /// look like one that did — the old path sent a frame into `task?.send { _ in }` and threw
    /// the completion error away, so a half-open socket swallowed the keystroke in silence.
    public struct ActionResult: Sendable, Equatable {
        public let ok: Bool
        public let message: String
        public static let sent = ActionResult(ok: true, message: "")
    }

    /// Clear a waiting lane with ONE named key, over HTTP — no attach, so it never becomes a
    /// tmux client and never resizes his panes. The server re-reads the lane's screen inside the
    /// request and refuses with a reason if the key is wrong for what is on it.
    /// Por onde uma aprovação sai. PURA e separada do `approve` de propósito: enquanto a escolha
    /// morava dentro da função que faz rede, ela não tinha teste — e a mutação provou isso
    /// (trocar o ramo do RPC por `false` deixava a suíte INTEIRA verde). O servidor já separa a
    /// decisão do efeito em `decideKey`; aqui é a mesma disciplina.
    public enum ApproveTransport: Sendable, Equatable {
        /// Pedido TIPADO: o loomd responde por RPC. Não há tecla nenhuma para nomear.
        case rpc
        /// Lane de tela: uma tecla nomeada, entregue por `send-keys`.
        case key(FleetEndpoint.LaneKey)
        /// Pergunta aberta: precisa de frase digitada, e nenhum botão pode fingir que resolve.
        case answer
    }

    /// `nonisolated` porque é PURA: não toca estado do cliente, e uma decisão que só pode ser
    /// consultada de dentro do main actor não é testável como decisão.
    public nonisolated static func approveTransport(for lane: LaneSnapshot) -> ApproveTransport {
        if lane.pendingApproval { return .rpc }
        if let k = lane.approve.key { return .key(k) }
        return .answer
    }

    @discardableResult
    public func approve(_ lane: LaneSnapshot) async -> ActionResult {
        // Lane servida pelo loomd: não há tecla, há um pedido TIPADO a responder. Sem este ramo
        // o card exato caía no `guard` abaixo e abria a folha de "Responder" — cuja resposta
        // seguia pelo socket para uma sessão que o broker não tem, e sumia em silêncio.
        if Self.approveTransport(for: lane) == .rpc {
            guard let req = endpoint.laneApproveRequest(sid: lane.sid, allow: true) else {
                return ActionResult(ok: false, message: "lane fora do allowlist: \(lane.sid)")
            }
            let out = await post(req)
            if out.ok { refresh() }
            return out
        }
        guard let key = lane.approve.key else {
            return ActionResult(ok: false, message: "essa lane pede uma resposta digitada — abra o terminal")
        }
        return await press(lane, key)
    }

    /// Interrupt a lane. The only key that is also valid while it is working, and it confirms
    /// nothing — the CLIs advertise it themselves ("esc to interrupt").
    @discardableResult
    public func interrupt(_ lane: LaneSnapshot) async -> ActionResult { await press(lane, .esc) }

    /// Move a lane into its own git worktree, so two agents cannot clobber one tree.
    @discardableResult
    public func isolate(_ lane: LaneSnapshot) async -> ActionResult {
        guard let req = endpoint.laneIsolateRequest(sid: lane.sid) else {
            return ActionResult(ok: false, message: "lane fora do allowlist: \(lane.sid)")
        }
        return await post(req)
    }

    public func press(_ lane: LaneSnapshot, _ key: FleetEndpoint.LaneKey) async -> ActionResult {
        guard let req = endpoint.laneKeyRequest(sid: lane.sid, key: key) else {
            return ActionResult(ok: false, message: "lane fora do allowlist: \(lane.sid)")
        }
        let out = await post(req)
        if out.ok { refresh() }   // pull the roster so the card catches up with the sweep
        return out
    }

    /// One place where a lane action becomes an HTTP call, so every failure is legible. The
    /// server's own refusal text is surfaced verbatim: it is more specific than anything the
    /// client could guess ("a lane está running, não esperando por você").
    private func post(_ request: URLRequest) async -> ActionResult {
        do {
            let (data, response) = try await session.data(for: request)
            let code = (response as? HTTPURLResponse)?.statusCode ?? 0
            let body = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
            let serverError = (body?["error"] as? String) ?? ""
            if (200..<300).contains(code) { return .sent }
            if code == 401 { return ActionResult(ok: false, message: "Token do cockpit recusado (401).") }
            return ActionResult(ok: false, message: serverError.isEmpty ? "cockpit respondeu \(code)" : serverError)
        } catch {
            return ActionResult(ok: false, message: error.localizedDescription)
        }
    }

    /// Answer an open question with real text (the case one keystroke cannot cover). This one
    /// DOES need the socket: arbitrary text is not a named key, and it belongs on the path where
    /// he can see what he is answering.
    public func answer(_ lane: LaneSnapshot, text: String) {
        guard !text.isEmpty else { return }
        send(FleetEndpoint.inputFrame(sid: lane.sid, data: text + "\r"))
    }

    /// Ask the broker for a fresh roster (it also pushes on its own timer).
    public func refresh() { send(FleetEndpoint.listFrame()) }

    private func send(_ frame: String) { task?.send(.string(frame)) { _ in } }

    /// DEBUG-only breadcrumb on stderr. A board that silently fails to connect is the worst
    /// possible outcome — it looks like "the fleet is quiet" instead of "I am blind".
    private func trace(_ message: String) {
        #if DEBUG
        FileHandle.standardError.write(Data("[loom] \(message)\n".utf8))
        #endif
    }

    private func startLoop() {
        loop?.cancel()
        loop = Task { [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                guard let t = self.task else { break }
                do {
                    let msg = try await t.receive()
                    if self.link != .live { self.link = .live; self.retries = 0; self.trace("live") }
                    switch msg {
                    case .string(let s): self.handle(s)
                    case .data(let d): self.handle(String(decoding: d, as: UTF8.self))
                    @unknown default: break
                    }
                } catch {
                    // 🚨 Guarda de IDENTIDADE, não de estado: se `self.task` já não é o mesmo
                    // objeto que `t` (uma tentativa MAIS NOVA de `connect()` já assumiu o lugar),
                    // este erro é o socket ÓRFÃO sendo cancelado de propósito — não uma queda
                    // real. Tratá-lo como drop() pisaria no `retries`/`link` da tentativa nova
                    // que já está em andamento. `===` funciona porque `URLSessionWebSocketTask`
                    // é classe.
                    guard self.task === t else {
                        self.trace("erro em socket já substituído — ignorado")
                        break
                    }
                    self.drop(error)
                    break
                }
            }
        }
    }

    /// `internal` (não `private`) só para dar costura de teste via `@testable`: o caminho de
    /// patch de lane única é onde um campo novo some em silêncio, e não há como exercê-lo sem
    /// um socket real de outra forma.
    func handle(_ raw: String) {
        guard
            let data = raw.data(using: .utf8),
            let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let t = obj["t"] as? String
        else { return }
        lastFrameAt = Date()

        switch t {
        case "sessions":
            guard let arr = obj["sessions"] as? [[String: Any]] else { return }
            let antes = lanes
            lanes = arr.compactMap(LaneSnapshot.init(loom:))
            ingestLoomd(obj["loomd"] as? [String: Any], antes: antes)
            trace("sessions: \(lanes.count) lanes, \(shelf.count) na prateleira, fonte medida: \(loomd?.mode.rawValue ?? "não declarada")")
        case "state":
            // A single lane changed; patch it in place so the board does not reflow.
            guard let sid = obj["sid"] as? String,
                  let idx = lanes.firstIndex(where: { $0.sid == sid }) else { return }
            let old = lanes[idx]
            lanes[idx] = LaneSnapshot(
                sid: old.sid,
                title: old.title,
                state: LaneState(rawValue: (obj["state"] as? String) ?? "") ?? .unknown,
                detail: (obj["detail"] as? String) ?? old.detail,
                peek: (obj["peek"] as? [Any])?.compactMap { $0 as? String } ?? old.peek,
                // A patch that kept the OLD affordance could leave an approve button on a lane
                // that has moved on to a question needing a typed answer.
                approve: obj["approveKey"] == nil
                    ? old.approve
                    : ApproveAffordance(approveKey: obj["approveKey"] as? String),
                atShell: (obj["atShell"] as? Bool) ?? old.atShell,
                observedAt: (obj["observedAt"] as? Double).map { Date(timeIntervalSince1970: $0 / 1000) }
                    ?? old.observedAt,
                // Patch de lane única: `?? old.confidence`, NÃO `?? .inferred`. Um frame
                // `state` que omite o campo é silêncio sobre a procedência, não a afirmação
                // de que a lane passou a ser adivinhada — rebaixá-la apagaria o contraste
                // no primeiro evento depois do snapshot.
                confidence: (obj["confidence"] as? String).flatMap(Confidence.init(rawValue:))
                    ?? old.confidence,
                // Mesma disciplina de `confidence`: `?? old.aceita`, NÃO `?? nil`. Um frame
                // `state` que omite `aceita` é silêncio sobre a capacidade, não a revogação
                // dela — e foi exatamente este ponto que apagou `confidence` em silêncio antes
                // de o comentário acima existir. `aceita` não repete o erro.
                //
                // 🚨 Achado de review: CHAVE AUSENTE e VALOR ILEGÍVEL não podem cair no mesmo
                // `?? old.aceita`. `(obj["aceita"] as? String).flatMap(Aceita.init(rawValue:))`
                // devolve `nil` tanto para "a chave não veio" quanto para "a chave veio com um
                // valor que o vocabulário atual não reconhece" (ex.: o servidor renomeou
                // `redireciona` e este binário ainda não sabe) — e os dois `nil` acabavam no
                // MESMO `?? old.aceita`, preservando `GUIAR`/`ENFILEIRAR` numa lane que o
                // servidor pode ter acabado de tornar somente-leitura. O caminho de quadro
                // inteiro (`LaneState.init(loom:)`, linha ~275) já degrada valor ilegível para
                // `nil` — o lado seguro — e este patch de lane única tinha de concordar com ele
                // em vez de tratar "não sei ler isto" como "não mudou nada".
                aceita: obj["aceita"] == nil
                    ? old.aceita
                    : (obj["aceita"] as? String).flatMap(Aceita.init(rawValue:)),
                // Mesma disciplina de `confidence`/`aceita`: `?? old.usd`, NÃO `?? 0`. Um frame
                // `state` que omite `usd` é silêncio sobre o custo, não a afirmação de que ele
                // zerou. 🚨 A razão ORIGINALMENTE escrita aqui — "o servidor omite a chave por
                // padrão quando o valor não mudou desde o último `sessions`" — é FABRICADA: o
                // servidor manda `usd` explicitamente em todo patch, hoje. A defesa `?? old.usd`
                // continua certa (silêncio nunca pode virar zero, e um binário futuro pode voltar
                // a omitir a chave), só a JUSTIFICATIVA estava errada e enganaria o próximo
                // leitor a procurar um comportamento do servidor que não existe. A razão real:
                // é defensivo por cautela, não porque o servidor hoje se comporta assim.
                //
                // ⚠️ DÍVIDA: o chip de custo (`FrotaView` — ver o comentário ao lado de
                // `SessionStore.custoDoChip` na `LaneCard`) NÃO herda `isStale`/`confidence` da
                // lane. Como o servidor CONGELA o último custo conhecido quando perde a fonte
                // exata (é o que este `?? old.usd` faz do lado do cliente também), o valor pode
                // ficar stale POR CONSTRUÇÃO — dos dois lados — sem nenhum indicador visível de
                // expiração. Não implementado aqui de propósito: este item é só o comentário.
                usd: (obj["usd"] as? Double) ?? old.usd
            )
        default:
            break   // data/scrollback belong to PTYClient; the board ignores terminal bytes.
        }
    }

    /// Lê o bloco `loomd` de um frame `sessions` e mantém, deste lado, o que a queda levou.
    ///
    /// Bloco ausente = cockpit antigo, que nunca soube da fonte: deixamos `loomd` como estava
    /// (`nil` continua `nil`). Silêncio não é afirmação, e inventar `.unknown` aqui produziria
    /// uma faixa sobre uma fonte que ninguém mencionou.
    private func ingestLoomd(_ bloco: [String: Any]?, antes: [LaneSnapshot]) {
        guard let bloco else { return }
        let lida = LoomdHealth(loom: bloco)

        if lida.mode == .observed {
            loomdEverObserved = true
            loomdLost.removeAll()   // a fonte voltou: parar de acusar perda que já não existe
        } else {
            // As lanes que ERAM medidas e não vieram neste frame. Comparar por `confidence`
            // importa: uma lane raspada da tela some por outros motivos (tmux, pod), e pendurá-la
            // na queda do loomd seria acusar a fonte errada.
            let vivas = Set(lanes.map(\.sid))
            let sumidas = antes.filter { $0.confidence == .exact && !vivas.contains($0.sid) }
            loomdLost.formUnion(sumidas.map(\.sid))
            loomdLost.formUnion(lida.lost)
        }

        loomd = lida
            .remembering(everObserved: loomdEverObserved)
            .naming(lost: loomdLost.sorted())
    }

    private func drop(_ error: Error) {
        task = nil
        if closedByCaller { trace("socket fechou após disconnect — sem reconexão"); return }
        trace("drop: \(error.localizedDescription)")
        // Deliberately keep `lanes`: stale-but-labelled beats an empty board.
        //
        // 🚨 Achado de review pós-Task-4: o cliente desistia de vez depois de `maxRetries`, e
        // ficava parado em `.failed` até algo EXTERNO chamar `connect()` de novo. Antes desta
        // fatia isso "funcionava" porque `FrotaView.onAppear` religava incondicionalmente — mas
        // quem fica parado na Sessão, lendo, não tem esse gesto, e é justo essa pessoa a mais
        // prejudicada por um link morto que ninguém revive sozinho. Mesmo defeito que o
        // `PTYClient` já teve e já consertou (ver `PTYClient.proximoAtrasoMs` e
        // `PTYClientKeepaliveTests`): `.failed` continua aparecendo depois de `maxRetries`, mas
        // SÓ como aviso para a UI — o laço de retentativa abaixo roda de qualquer jeito, sempre,
        // com o atraso saturado no teto. O cliente não tem mais estado de desistência permanente.
        retries += 1
        // `.insistindo`, não `.failed`: o laço abaixo agenda a próxima tentativa de qualquer
        // jeito, então "parei" seria mentira depois de `maxRetries` tanto quanto antes.
        link = retries >= maxRetries
            ? .insistindo(motivo: error.localizedDescription, tentativas: retries)
            : .reconnecting
        let delayMs = Self.proximoAtrasoMs(retries: retries)
        Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(delayMs))
            self?.connect()
        }
    }

    /// Pura: backoff exponencial com teto de 10s, e SEM limite de `retries` — o laço em `drop`
    /// continua chamando esta função para sempre; ela só para de crescer o atraso ao bater no
    /// teto. Mesmo padrão de `PTYClient.proximoAtrasoMs`, que já resolveu este defeito exato
    /// (lane presa para sempre depois de uma queda) para o socket de terminal; o socket da Frota
    /// não pode regredir para o bug que aquele conserto existiu para matar.
    nonisolated static func proximoAtrasoMs(retries: Int) -> Int {
        // 🚨 A fórmula ORIGINAL (`min(retries, 5)`) nunca alcançava o teto declarado: com o
        // expoente travado em 5, `250 * 2^5 = 8_000`, sempre abaixo dos 10_000 que o `min` dizia
        // ser o limite — um teto que existia só no comentário. O expoente 6 é o menor que faz
        // `250 * 2^6 = 16_000` estourar o `min` de verdade e saturar em 10_000.
        min(10_000, 250 * (1 << min(max(retries, 1), 6)))
    }

    /// O texto explicativo para cada estado do link. PURA — extraída para ser testável sem UI,
    /// no mesmo padrão de `SessionStore.rotuloDeGuiar`/`semCaixa` desta mesma fatia.
    ///
    /// 🚨 `.insistindo` NUNCA pode devolver um texto que implique que o cliente parou: ele está
    /// retentando sozinho, em segundo plano, o tempo todo. Dizer o contrário manda o operador
    /// embora achando que perdeu a frota — pior notícia que a verdade, que já é boa ("caiu,
    /// mas eu mesmo estou tentando de novo").
    public nonisolated static func explicacaoDoLink(_ link: Link) -> String {
        switch link {
        case .failed(let why):
            return "O broker não respondeu: \(why). Tailnet ativa? Cockpit no ar?"
        case .insistindo(let motivo, let tentativas):
            return "O broker caiu — reconectando sozinho (tentativa \(tentativas)): \(motivo). Tailnet ativa? Cockpit no ar?"
        case .reconnecting:
            return "Reconectando ao broker…"
        case .connecting:
            return "Conectando ao broker…"
        case .live:
            return "Conectado, mas o broker ainda não observou nenhuma lane."
        case .idle:
            return "Sem conexão com o broker."
        }
    }
}
