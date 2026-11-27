import Foundation
import Testing
@testable import BeagleCore

/// The P0 `/pty/<agent>` gateway is dead (Rust, source lost). The live transport is the Loom
/// broker: ONE multiplexed socket, JSON frames, lane chosen by `subscribe` rather than by path.
@Suite
struct FleetEndpointTests {
    @Test func testLoomURLIsASingleMultiplexedSocket() {
        let ep = FleetEndpoint(host: "sounio-cockpit.tail21cbc4.ts.net")
        #expect(ep.loomURL()?.absoluteString == "ws://sounio-cockpit.tail21cbc4.ts.net/ws/loom")
    }

    @Test func testORosterDeTerminaisNaoEOAllowlistDeAcao() {
        // Duas perguntas diferentes, duas listas. Enquanto foram uma só, `loom-1` — que não é
        // sessão tmux — entrou no roster que `FleetTerminalStore.agents` publica, e o app passou
        // a oferecer um terminal que só podia dar erro.
        #expect(FleetEndpoint.terminalAgents.count == 11)
        #expect(FleetEndpoint.terminalAgents.first == "claude-1")
        #expect(FleetEndpoint.terminalAgents.last == "repo")
        #expect(!FleetEndpoint.terminalAgents.contains("loom-1"),
                "lane do loomd não tem pty: não pode estar no roster de terminais")

        // O allowlist de AÇÃO é estritamente maior — e é essa folga que a lista única apagava.
        //
        // A RELAÇÃO, não o número: `count == 12` quebrou ao adotar `codex-4` e me obrigaria a
        // trocar um número mágico por outro a cada lane nova. A invariante que importa é que o
        // allowlist contenha o roster e o exceda exatamente pelas lanes de protocolo.
        #expect(FleetEndpoint.actionableLanes.count ==
                FleetEndpoint.terminalAgents.count + FleetEndpoint.loomdLanes.count)
        for t in FleetEndpoint.terminalAgents {
            #expect(FleetEndpoint.isKnownAgent(t), "quem tem terminal também é acionável: \(t)")
        }
        for l in FleetEndpoint.loomdLanes {
            #expect(FleetEndpoint.isKnownAgent(l),
                    "sem allowlist a lane do loomd é descartada em silêncio nas ações: \(l)")
            #expect(!FleetEndpoint.hasTerminal(l), "lane de protocolo não tem pty: \(l)")
        }
        #expect(FleetEndpoint.hasTerminal("claude-1"))

        // Um POST de tecla para a lane do loomd continua sendo MONTADO (o allowlist a conhece)…
        let ep = FleetEndpoint(host: "h", scheme: "wss", token: "t")
        #expect(ep.laneKeyRequest(sid: "loom-1", key: .y) != nil)

        // The old roster was stale fiction (minimax/cursor/grok/kimi were never tmux sessions).
        for ghost in ["minimax", "cursor", "grok", "kimi"] {
            #expect(!FleetEndpoint.isKnownAgent(ghost), "\(ghost) is not a real lane")
            #expect(!FleetEndpoint.hasTerminal(ghost))
        }
        for real in ["claude-3", "codex-2", "kimi-cli1", "grok-cli2", "repo"] {
            #expect(FleetEndpoint.isKnownAgent(real))
            #expect(FleetEndpoint.hasTerminal(real))
        }
    }

    @Test func testTokenIsSentAsAHeaderNotAQueryParameter() {
        let withToken = FleetEndpoint(host: "h", scheme: "wss", token: "s3cr3t")
        let req = withToken.loomRequest()
        #expect(req?.value(forHTTPHeaderField: "x-cockpit-token") == "s3cr3t")
        #expect(!(req?.url?.absoluteString.contains("s3cr3t") ?? true),
                "a token in the URL leaks into logs")

        // NEVER assert on the AMBIENT token. `CockpitToken.resolve` falls back to Secrets.plist,
        // $BEAGLE_COCKPIT_TOKEN and ~/.beagle/cockpit-token, so this used to assert nil and then
        // FAIL on the operator's own Mac — printing the real cockpit token into the test log
        // (2026-08-09; that token is being rotated). A test must not depend on, or be able to
        // reveal, a secret that happens to exist on the machine running it.
        let ambient = FleetEndpoint(host: "h").loomRequest()?.value(forHTTPHeaderField: "x-cockpit-token")
        #expect(ambient != "", "an empty token must stay absent, not become an empty header")
        // Whatever the ambient token is, it belongs in the header and never in the URL.
        #expect(FleetEndpoint(host: "h").loomURL()?.absoluteString == "ws://h/ws/loom")
    }

    @Test func testHTTPReadsUseHTTPSWhenTheSocketIsSecure() {
        #expect(FleetEndpoint(host: "h", scheme: "wss").oficinaRequest()?.url?.scheme == "https")
        #expect(FleetEndpoint(host: "h", scheme: "ws").oficinaRequest()?.url?.scheme == "http")
        #expect(FleetEndpoint(host: "h").coordRequest()?.url?.path == "/api/mobile/v1/coord")
        #expect(FleetEndpoint(host: "h").oficinaRequest()?.url?.path == "/api/mobile/v1/oficina")
    }

    @Test func testFramesMatchTheBrokerProtocol() {
        #expect(FleetEndpoint.subscribeFrame(sid: "claude-1") ==
                #"{"sid":"claude-1","t":"subscribe"}"#)
        #expect(FleetEndpoint.resizeFrame(sid: "repo", cols: 120, rows: 40) ==
                #"{"cols":120,"rows":40,"sid":"repo","t":"resize"}"#)
        #expect(FleetEndpoint.listFrame() == #"{"t":"list"}"#)
    }

    @Test func testKeystrokesAreJSONEscapedSoTheyCannotCorruptTheFrame() {
        // A quote or newline typed into a terminal must not break out of the JSON string.
        let frame = FleetEndpoint.inputFrame(sid: "claude-1", data: "echo \"hi\"\n")
        let obj = try? JSONSerialization.jsonObject(with: Data(frame.utf8)) as? [String: Any]
        #expect(obj?["data"] as? String == "echo \"hi\"\n")
        #expect(obj?["t"] as? String == "input")
    }

    // ─── A Sessão: prompt e conversa ──────────────────────────────────────────────────────

    /// 🚨 A regressão que este teste guarda saiu na TELA como "erro 404 no canto superior".
    ///
    /// `laneTurnsRequest` montava `jsonRequest(path: "/…/turns?since=0")`, e
    /// `URLComponents.path` **percent-encoda o `?`**: a URL saía `/…/turns%3Fsince=0`, uma rota que
    /// não existe. Compilava, tipava, e o servidor devolvia 404. Nenhum teste de lógica pegaria —
    /// só um que olha a URL PRONTA.
    @Test func testOsTurnosVaoComQueryDeVerdadeNaoComOPathEncodado() {
        let ep = FleetEndpoint(host: "cockpit.exemplo", token: "t")
        let url = ep.laneTurnsRequest(sid: "loom-1", since: 42)?.url
        #expect(url?.path == "/api/mobile/v1/lanes/loom-1/turns",
                "o caminho não pode carregar a query")
        #expect(url?.query == "since=42", "a query tem que ser query")
        #expect(!(url?.absoluteString.contains("%3F") ?? true),
                "um `?` encodado no caminho é exatamente o 404 que apareceu na tela")
        #expect(url?.absoluteString ==
                "http://cockpit.exemplo/api/mobile/v1/lanes/loom-1/turns?since=42")
    }

    @Test func testOTokenViajaNoCabecalhoNuncaNaURL() {
        // Invariante que o repo já guardava para as outras rotas: segredo em URL vaza em log de
        // proxy e em histórico. As rotas novas entram sob a mesma regra.
        let ep = FleetEndpoint(host: "cockpit.exemplo", token: "segredo-do-cockpit")
        for req in [ep.laneTurnsRequest(sid: "loom-1", since: 0),
                    ep.lanePromptRequest(sid: "loom-1", text: "oi")] {
            #expect(req?.value(forHTTPHeaderField: "x-cockpit-token") == "segredo-do-cockpit")
            #expect(!(req?.url?.absoluteString.contains("segredo") ?? true))
        }
    }

    @Test func testOPromptViajaNoCORPOSerializado() {
        // O texto nunca entra na URL nem é concatenado à mão — o servidor o repassa pelo stdin de
        // um exec, e um texto com metacaractere no lugar errado seria injeção de shell.
        let ep = FleetEndpoint(host: "cockpit.exemplo", token: "t")
        let veneno = "oi\"; rm -rf /workspace; echo $(whoami)"
        let req = ep.lanePromptRequest(sid: "loom-1", text: veneno)
        #expect(req?.httpMethod == "POST")
        #expect(!(req?.url?.absoluteString.contains("rm -rf") ?? true))
        let corpo = (try? JSONSerialization.jsonObject(with: req?.httpBody ?? Data())) as? [String: String]
        #expect(corpo?["text"] == veneno, "o corpo é JSON serializado, com o texto intacto")
    }

    @Test func testLaneComNomeHostilNaoViraRequest() {
        // O `sid` entra no CAMINHO da URL. A tranca de verdade é do servidor; esta evita construir
        // um request condenado — e evita que um nome com `/` produza uma rota inventada.
        let ep = FleetEndpoint(host: "cockpit.exemplo", token: "t")
        for ruim in ["", "../admin", "loom 1", "loom/1", String(repeating: "x", count: 65)] {
            #expect(ep.laneTurnsRequest(sid: ruim, since: 0) == nil, "aceitou sid ruim: \(ruim)")
            #expect(ep.lanePromptRequest(sid: ruim, text: "oi") == nil, "aceitou sid ruim: \(ruim)")
        }
        #expect(ep.laneTurnsRequest(sid: "loom-1", since: -1) == nil, "cursor negativo não é cursor")
    }
}
