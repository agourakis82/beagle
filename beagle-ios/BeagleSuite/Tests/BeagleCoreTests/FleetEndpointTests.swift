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

    func testRosterIsTheRealElevenLanes() {
        XCTAssertEqual(FleetEndpoint.agents.count, 11)
        XCTAssertEqual(FleetEndpoint.agents.first, "claude-1")
        XCTAssertEqual(FleetEndpoint.agents.last, "repo")
        // The old roster was stale fiction (minimax/cursor/grok/kimi were never tmux sessions).
        for ghost in ["minimax", "cursor", "grok", "kimi"] {
            XCTAssertFalse(FleetEndpoint.isKnownAgent(ghost), "\(ghost) is not a real lane")
        }
        for real in ["claude-3", "codex-2", "kimi-cli1", "grok-cli2", "repo"] {
            XCTAssertTrue(FleetEndpoint.isKnownAgent(real))
        }
    }

    func testTokenIsSentAsAHeaderNotAQueryParameter() {
        let withToken = FleetEndpoint(host: "h", scheme: "wss", token: "s3cr3t")
        let req = withToken.loomRequest()
        XCTAssertEqual(req?.value(forHTTPHeaderField: "x-cockpit-token"), "s3cr3t")
        XCTAssertFalse(req?.url?.absoluteString.contains("s3cr3t") ?? true,
                       "a token in the URL leaks into logs")
        // No token = rely on the tailnet gateway, same posture as the old pod-gated /pty.
        XCTAssertNil(FleetEndpoint(host: "h").loomRequest()?.value(forHTTPHeaderField: "x-cockpit-token"))
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
