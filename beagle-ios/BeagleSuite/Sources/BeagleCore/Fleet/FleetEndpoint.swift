import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking   // URLRequest/URLSession live here on non-Apple platforms
#endif

/// Connection details for the fleet's **Loom** transport (`/ws/loom`) — the live broker that
/// multiplexes every agent session over ONE WebSocket (server/loom/protocol.mjs). This replaces
/// the dead P0 `/pty/<agent>` gateway (Rust, source lost).
///
/// Auth: the Loom upgrade accepts a `tailscale-user-login` header (injected by the tailnet
/// gateway when the device is on the tailnet) OR an `x-cockpit-token`. So with `token == nil`
/// and a tailnet `host`, no secret is needed — same posture as the old pod-gated `/pty`.
public struct FleetEndpoint: Sendable {
    /// The real workspace agent lanes — tmux session ids on `sounio-workspace-control-0`,
    /// allowlisted in `platform-bridge.mjs` and seeded into the Loom broker.
    ///
    /// Esta lista é o roster de TERMINAIS: cada nome aqui tem uma sessão tmux atrás, e é a ela
    /// que `FleetTerminalStore` abre um PTY. Não é o allowlist de ação — ver `actionableLanes`.
    public static let terminalAgents: [String] = [
        "claude-1", "claude-2", "claude-3",
        "codex-1", "codex-2", "codex-3",
        "kimi-cli1", "kimi-cli2",
        "grok-cli1", "grok-cli2",
        "repo",
    ]

    /// Lanes servidas pelo **loomd** (supervisor por protocolo, JSON-RPC dentro do pod). Elas
    /// aparecem no board e aceitam ação, mas NÃO têm sessão tmux: abrir terminal para uma delas
    /// só pode dar erro.
    ///
    /// Medido hoje: `loom-1` tinha sido posto na lista acima, que é literalmente o que
    /// `FleetTerminalStore.agents` publica na aba Terminais — o app oferecia um terminal
    /// impossível. Duas perguntas diferentes ("posso AGIR nesta lane?" e "posso ABRIR esta
    /// lane?") não podem compartilhar uma lista só.
    public static let loomdLanes: [String] = ["loom-1"]

    /// Tudo em que o board pode agir: terminais + lanes do loomd. É o allowlist consultado
    /// antes de montar um POST de tecla/isolamento — sem estar aqui, a lane chega no frame e é
    /// descartada em silêncio, sem erro e sem log.
    public static let actionableLanes: [String] = terminalAgents + loomdLanes

    public let host: String
    public let scheme: String
    /// Optional cockpit token → sent as `x-cockpit-token` on the WS upgrade. Nil = rely on the
    /// tailnet gateway (`tailscale-user-login`). Set it to reach the public HTTPS gateway.
    public let token: String?

    public init(
        host: String = "sounio-cockpit.tail21cbc4.ts.net",
        scheme: String = "ws",
        token: String? = nil
    ) {
        self.host = host
        self.scheme = scheme
        // Default to the app's canonical cockpit token (Secrets.plist, gitignored — same source
        // every other cockpit call uses). A token is now REQUIRED for the Loom socket: it carries
        // keystrokes into live sessions, so the cockpit stopped accepting the forgeable
        // `tailscale-user-login` header alone on write paths. Empty stays empty, so a missing
        // Secrets.plist fails loudly with 401 instead of looking like a network problem.
        // Resolved across every source a client might have: explicit → the iOS bundle's
        // Secrets.plist → BEAGLE_COCKPIT_TOKEN → ~/.beagle/cockpit-token. The macOS app is a
        // package executable with no bundle, so without the last two it would 401 forever and
        // look like a network fault. Nil stays nil so the UI can say WHY.
        self.token = CockpitToken.resolve(explicit: token)
    }

    /// Pode-se AGIR nesta lane? (tecla, isolamento) — inclui as lanes do loomd.
    public static func isKnownAgent(_ agent: String) -> Bool {
        actionableLanes.contains(agent)
    }

    /// Existe um terminal para ABRIR? Só as sessões tmux. Estritamente mais restrito que
    /// `isKnownAgent`, e é essa folga entre os dois conjuntos que o roster único apagava.
    public static func hasTerminal(_ agent: String) -> Bool {
        terminalAgents.contains(agent)
    }

    /// The single multiplexed Loom socket: `ws(s)://<host>/ws/loom`. Every lane shares it;
    /// the agent is selected per-connection via a `subscribe` frame, not via the path.
    public func loomURL() -> URL? {
        var c = URLComponents()
        c.scheme = scheme
        c.host = host
        c.path = "/ws/loom"
        return c.url
    }

    /// A `URLRequest` for the WS upgrade, carrying the optional `x-cockpit-token` header.
    public func loomRequest() -> URLRequest? {
        guard let url = loomURL() else { return nil }
        var req = URLRequest(url: url)
        if let token, !token.isEmpty {
            req.setValue(token, forHTTPHeaderField: "x-cockpit-token")
        }
        return req
    }

    /// The Oficina reading: `http(s)://<host>/api/mobile/v1/oficina`, same auth posture as the
    /// Loom socket (tailnet header, or the cockpit token via the public gateway).
    public func oficinaRequest() -> URLRequest? {
        var c = URLComponents()
        c.scheme = (scheme == "wss") ? "https" : "http"
        c.host = host
        c.path = "/api/mobile/v1/oficina"
        guard let url = c.url else { return nil }
        var req = URLRequest(url: url)
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        if let token, !token.isEmpty { req.setValue(token, forHTTPHeaderField: "x-cockpit-token") }
        return req
    }

    /// The coordination reading: shared-tree hazards, live claims, and their conflicts.
    public func coordRequest() -> URLRequest? { jsonRequest(path: "/api/mobile/v1/coord") }

    // MARK: - Acting on a lane (HTTP one-shot, never an attach)

    /// The only keystrokes the cockpit will deliver, by name. Mirrors `LANE_KEYS` in
    /// `platform-bridge.mjs`; the server refuses anything else, so this is a convenience, not
    /// the guard. `esc` interrupts and confirms nothing — it is the one key valid on a busy lane.
    public enum LaneKey: String, Sendable, CaseIterable {
        case enter, y, esc
    }

    /// Press ONE named key in a lane, via `tmux send-keys` — no attach, so it never becomes a
    /// tmux client and never resizes his panes (tmux sizes a window to its smallest client).
    ///
    /// The server decides whether the key is allowed, from a screen it re-reads inside the
    /// request. A lane whose question needs a typed sentence is refused with a reason; the UI
    /// must open the terminal instead of pretending a keystroke answered it.
    public func laneKeyRequest(sid: String, key: LaneKey) -> URLRequest? {
        guard Self.isKnownAgent(sid) else { return nil }
        guard var req = jsonRequest(path: "/api/mobile/v1/lanes/\(sid)/key") else { return nil }
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = Self.encode(["key": key.rawValue]).data(using: .utf8)
        return req
    }

    /// Move a lane into its own git worktree. Only sound for a lane at rest — the server enforces
    /// that, because moving restarts the agent there and its context is lost.
    /// Responder ao pedido que a lane está fazendo. Irmã de `laneKeyRequest`, não substituta:
    /// `/key` diz "entregue ESTA tecla" e só faz sentido onde existe um pane; `/approve` diz
    /// "responda ao pedido" e deixa o SERVIDOR escolher o mecanismo a partir de quem serve a
    /// lane. Numa lane do loomd não há tecla nenhuma para nomear.
    ///
    /// O `sid` vem do frame do próprio servidor, não de digitação — mas passa por um teste de
    /// charset assim mesmo, porque ele entra num caminho de URL.
    public func laneApproveRequest(sid: String, allow: Bool = true) -> URLRequest? {
        guard !sid.isEmpty, sid.count <= 64,
              sid.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" }) else { return nil }
        guard var req = jsonRequest(path: "/api/mobile/v1/lanes/\(sid)/approve") else { return nil }
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = Self.encode(["allow": allow]).data(using: .utf8)
        return req
    }

    /// Um pedido em TEXTO LIVRE para uma lane de protocolo.
    ///
    /// O texto vai no CORPO, e a única razão de isto ser dizível em uma linha é que o servidor
    /// nunca o interpola num shell: ele o repassa pelo stdin do exec. A checagem de charset aqui
    /// é do `sid` — que entra no caminho da URL — nunca do texto, que é livre por definição.
    ///
    /// O 202 do servidor significa ACEITO, não concluído: quem conta o resto é a trama.
    public func lanePromptRequest(sid: String, text: String) -> URLRequest? {
        guard Self.isLaneName(sid) else { return nil }
        guard var req = jsonRequest(path: "/api/mobile/v1/lanes/\(sid)/prompt") else { return nil }
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try? JSONSerialization.data(withJSONObject: ["text": text])
        return req
    }

    /// A conversa a partir de um cursor. `since` é o maior `seq` já visto — o servidor devolve o
    /// próximo cursor pronto, então o cliente nunca o deriva do último elemento (que é `nil`
    /// quando o poll não trouxe novidade, o caso comum).
    public func laneTurnsRequest(sid: String, since: Int) -> URLRequest? {
        guard Self.isLaneName(sid), since >= 0 else { return nil }
        return jsonRequest(path: "/api/mobile/v1/lanes/\(sid)/turns?since=\(since)")
    }

    /// Charset de nome de lane que pode entrar num caminho de URL. Espelha `SAFE_LOOMD_LANE` do
    /// servidor — que é a tranca de verdade; esta evita construir um request condenado.
    static func isLaneName(_ sid: String) -> Bool {
        !sid.isEmpty && sid.count <= 64
            && sid.allSatisfy { $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" }
    }

    public func laneIsolateRequest(sid: String) -> URLRequest? {
        guard Self.isKnownAgent(sid) else { return nil }
        guard var req = jsonRequest(path: "/api/mobile/v1/lanes/\(sid)/isolate") else { return nil }
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = Data("{}".utf8)
        return req
    }

    private func jsonRequest(path: String) -> URLRequest? {
        var c = URLComponents()
        c.scheme = (scheme == "wss") ? "https" : "http"
        c.host = host
        c.path = path
        guard let url = c.url else { return nil }
        var req = URLRequest(url: url)
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        if let token, !token.isEmpty { req.setValue(token, forHTTPHeaderField: "x-cockpit-token") }
        return req
    }

    // MARK: - Loom client frames (see server/loom/protocol.mjs CLIENT_TYPES)

    /// Attach to a lane: server replies `{t:"scrollback"}` then streams `{t:"data"}`.
    public static func subscribeFrame(sid: String) -> String {
        encode(["t": "subscribe", "sid": sid])
    }

    /// Detach without killing the lane (broker dematerializes on last subscriber).
    public static func unsubscribeFrame(sid: String) -> String {
        encode(["t": "unsubscribe", "sid": sid])
    }

    /// Keyboard/stdin → lane. `data` is JSON-string-escaped by JSONSerialization.
    public static func inputFrame(sid: String, data: String) -> String {
        encode(["t": "input", "sid": sid, "data": data])
    }

    /// Tell the lane's pty its viewport (tmux only repaints once it knows the client size).
    public static func resizeFrame(sid: String, cols: Int, rows: Int) -> String {
        encode(["t": "resize", "sid": sid, "cols": cols, "rows": rows])
    }

    /// Ask for the current session roster (also sent unprompted on connect).
    public static func listFrame() -> String {
        encode(["t": "list"])
    }

    /// Robust JSON encoding via JSONSerialization (correct escaping for input payloads).
    static func encode(_ obj: [String: Any]) -> String {
        guard
            let d = try? JSONSerialization.data(withJSONObject: obj, options: [.sortedKeys]),
            let s = String(data: d, encoding: .utf8)
        else { return "{}" }
        return s
    }
}
