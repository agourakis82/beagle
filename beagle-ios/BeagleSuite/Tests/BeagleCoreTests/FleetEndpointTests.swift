import XCTest
@testable import BeagleCore

/// The P0 `/pty/<agent>` gateway is dead (Rust, source lost). The live transport is the Loom
/// broker: ONE multiplexed socket, JSON frames, lane chosen by `subscribe` rather than by path.
final class FleetEndpointTests: XCTestCase {
    func testLoomURLIsASingleMultiplexedSocket() {
        let ep = FleetEndpoint(host: "sounio-cockpit.tail21cbc4.ts.net")
        XCTAssertEqual(ep.loomURL()?.absoluteString,
                       "ws://sounio-cockpit.tail21cbc4.ts.net/ws/loom")
    }

    func testORosterDeTerminaisNaoEOAllowlistDeAcao() {
        // Duas perguntas diferentes, duas listas. Enquanto foram uma só, `loom-1` — que não é
        // sessão tmux — entrou no roster que `FleetTerminalStore.agents` publica, e o app passou
        // a oferecer um terminal que só podia dar erro.
        XCTAssertEqual(FleetEndpoint.terminalAgents.count, 11)
        XCTAssertEqual(FleetEndpoint.terminalAgents.first, "claude-1")
        XCTAssertEqual(FleetEndpoint.terminalAgents.last, "repo")
        XCTAssertFalse(FleetEndpoint.terminalAgents.contains("loom-1"),
                       "lane do loomd não tem pty: não pode estar no roster de terminais")

        // O allowlist de AÇÃO é estritamente maior — e é essa folga que a lista única apagava.
        XCTAssertEqual(FleetEndpoint.actionableLanes.count, 12)
        XCTAssertTrue(FleetEndpoint.isKnownAgent("loom-1"),
                      "sem allowlist a lane do loomd é descartada em silêncio nas ações")
        XCTAssertFalse(FleetEndpoint.hasTerminal("loom-1"))
        XCTAssertTrue(FleetEndpoint.hasTerminal("claude-1"))

        // Um POST de tecla para a lane do loomd continua sendo MONTADO (o allowlist a conhece)…
        let ep = FleetEndpoint(host: "h", scheme: "wss", token: "t")
        XCTAssertNotNil(ep.laneKeyRequest(sid: "loom-1", key: .y))

        // The old roster was stale fiction (minimax/cursor/grok/kimi were never tmux sessions).
        for ghost in ["minimax", "cursor", "grok", "kimi"] {
            XCTAssertFalse(FleetEndpoint.isKnownAgent(ghost), "\(ghost) is not a real lane")
            XCTAssertFalse(FleetEndpoint.hasTerminal(ghost))
        }
        for real in ["claude-3", "codex-2", "kimi-cli1", "grok-cli2", "repo"] {
            XCTAssertTrue(FleetEndpoint.isKnownAgent(real))
            XCTAssertTrue(FleetEndpoint.hasTerminal(real))
        }
    }

    func testTokenIsSentAsAHeaderNotAQueryParameter() {
        let withToken = FleetEndpoint(host: "h", scheme: "wss", token: "s3cr3t")
        let req = withToken.loomRequest()
        XCTAssertEqual(req?.value(forHTTPHeaderField: "x-cockpit-token"), "s3cr3t")
        XCTAssertFalse(req?.url?.absoluteString.contains("s3cr3t") ?? true,
                       "a token in the URL leaks into logs")

        // NEVER assert on the AMBIENT token. `CockpitToken.resolve` falls back to Secrets.plist,
        // $BEAGLE_COCKPIT_TOKEN and ~/.beagle/cockpit-token, so this used to assert nil and then
        // FAIL on the operator's own Mac — printing the real cockpit token into the test log
        // (2026-08-09; that token is being rotated). A test must not depend on, or be able to
        // reveal, a secret that happens to exist on the machine running it.
        let ambient = FleetEndpoint(host: "h").loomRequest()?.value(forHTTPHeaderField: "x-cockpit-token")
        XCTAssertNotEqual(ambient, "", "an empty token must stay absent, not become an empty header")
        // Whatever the ambient token is, it belongs in the header and never in the URL.
        XCTAssertEqual(FleetEndpoint(host: "h").loomURL()?.absoluteString, "ws://h/ws/loom")
    }

    func testHTTPReadsUseHTTPSWhenTheSocketIsSecure() {
        XCTAssertEqual(FleetEndpoint(host: "h", scheme: "wss").oficinaRequest()?.url?.scheme, "https")
        XCTAssertEqual(FleetEndpoint(host: "h", scheme: "ws").oficinaRequest()?.url?.scheme, "http")
        XCTAssertEqual(FleetEndpoint(host: "h").coordRequest()?.url?.path, "/api/mobile/v1/coord")
        XCTAssertEqual(FleetEndpoint(host: "h").oficinaRequest()?.url?.path, "/api/mobile/v1/oficina")
    }

    func testFramesMatchTheBrokerProtocol() {
        XCTAssertEqual(FleetEndpoint.subscribeFrame(sid: "claude-1"),
                       #"{"sid":"claude-1","t":"subscribe"}"#)
        XCTAssertEqual(FleetEndpoint.resizeFrame(sid: "repo", cols: 120, rows: 40),
                       #"{"cols":120,"rows":40,"sid":"repo","t":"resize"}"#)
        XCTAssertEqual(FleetEndpoint.listFrame(), #"{"t":"list"}"#)
    }

    func testKeystrokesAreJSONEscapedSoTheyCannotCorruptTheFrame() {
        // A quote or newline typed into a terminal must not break out of the JSON string.
        let frame = FleetEndpoint.inputFrame(sid: "claude-1", data: "echo \"hi\"\n")
        let obj = try? JSONSerialization.jsonObject(with: Data(frame.utf8)) as? [String: Any]
        XCTAssertEqual(obj?["data"] as? String, "echo \"hi\"\n")
        XCTAssertEqual(obj?["t"] as? String, "input")
    }
    // ─── A Sessão: prompt e conversa ────────────────────────────────────────────────────────

    /// 🚨 A regressão que este teste guarda saiu na TELA como "erro 404 no canto superior".
    ///
    /// `laneTurnsRequest` montava `jsonRequest(path: "/…/turns?since=0")`, e
    /// `URLComponents.path` **percent-encoda o `?`**: a URL saía `/…/turns%3Fsince=0`, uma rota que
    /// não existe. Compilava, tipava, e o servidor devolvia 404. Nenhum teste de lógica pegaria —
    /// só um que olha a URL PRONTA.
    func testOsTurnosVaoComQueryDeVerdadeNaoComOPathEncodado() {
        let ep = FleetEndpoint(host: "cockpit.exemplo", token: "t")
        let url = ep.laneTurnsRequest(sid: "loom-1", since: 42)?.url
        XCTAssertEqual(url?.path, "/api/mobile/v1/lanes/loom-1/turns",
                       "o caminho não pode carregar a query")
        XCTAssertEqual(url?.query, "since=42", "a query tem que ser query")
        XCTAssertFalse(url?.absoluteString.contains("%3F") ?? true,
                       "um `?` encodado no caminho é exatamente o 404 que apareceu na tela")
        XCTAssertEqual(url?.absoluteString,
                       "http://cockpit.exemplo/api/mobile/v1/lanes/loom-1/turns?since=42")
    }

    func testOTokenViajaNoCabecalhoNuncaNaURL() {
        // Invariante que o repo já guardava para as outras rotas: segredo em URL vaza em log de
        // proxy e em histórico. As rotas novas entram sob a mesma regra.
        let ep = FleetEndpoint(host: "cockpit.exemplo", token: "segredo-do-cockpit")
        for req in [ep.laneTurnsRequest(sid: "loom-1", since: 0),
                    ep.lanePromptRequest(sid: "loom-1", text: "oi")] {
            XCTAssertEqual(req?.value(forHTTPHeaderField: "x-cockpit-token"), "segredo-do-cockpit")
            XCTAssertFalse(req?.url?.absoluteString.contains("segredo") ?? true)
        }
    }

    func testOPromptViajaNoCORPOSerializado() {
        // O texto nunca entra na URL nem é concatenado à mão — o servidor o repassa pelo stdin de
        // um exec, e um texto com metacaractere no lugar errado seria injeção de shell.
        let ep = FleetEndpoint(host: "cockpit.exemplo", token: "t")
        let veneno = "oi\"; rm -rf /workspace; echo $(whoami)"
        let req = ep.lanePromptRequest(sid: "loom-1", text: veneno)
        XCTAssertEqual(req?.httpMethod, "POST")
        XCTAssertFalse(req?.url?.absoluteString.contains("rm -rf") ?? true)
        let corpo = (try? JSONSerialization.jsonObject(with: req?.httpBody ?? Data())) as? [String: String]
        XCTAssertEqual(corpo?["text"], veneno, "o corpo é JSON serializado, com o texto intacto")
    }

    func testLaneComNomeHostilNaoViraRequest() {
        // O `sid` entra no CAMINHO da URL. A tranca de verdade é do servidor; esta evita construir
        // um request condenado — e evita que um nome com `/` produza uma rota inventada.
        let ep = FleetEndpoint(host: "cockpit.exemplo", token: "t")
        for ruim in ["", "../admin", "loom 1", "loom/1", String(repeating: "x", count: 65)] {
            XCTAssertNil(ep.laneTurnsRequest(sid: ruim, since: 0), "aceitou sid ruim: \(ruim)")
            XCTAssertNil(ep.lanePromptRequest(sid: ruim, text: "oi"), "aceitou sid ruim: \(ruim)")
        }
        XCTAssertNil(ep.laneTurnsRequest(sid: "loom-1", since: -1), "cursor negativo não é cursor")
    }

}
