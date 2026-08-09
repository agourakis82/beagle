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
        case idle, connecting, live, reconnecting, failed(String)
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
                    ?? old.confidence
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
        guard retries < maxRetries else { link = .failed(error.localizedDescription); return }
        retries += 1
        link = .reconnecting
        let delayMs = min(10_000, 250 * (1 << min(retries, 5)))
        Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(delayMs))
            self?.connect()
        }
    }
}
