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
}
