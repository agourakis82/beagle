import XCTest
@testable import BeagleCore

final class FleetEndpointTests: XCTestCase {
    func testPTYURLForAgent() {
        let ep = FleetEndpoint(host: "cockpit-1.tail21cbc4.ts.net")
        XCTAssertEqual(ep.ptyURL(agent: "claude-1")?.absoluteString,
                       "ws://cockpit-1.tail21cbc4.ts.net/pty/claude-1")
    }

    func testRejectsUnknownAgent() {
        let ep = FleetEndpoint(host: "h")
        XCTAssertNil(ep.ptyURL(agent: "bogus"))
        XCTAssertNil(ep.ptyURL(agent: "../x"))
    }

    func testResizeFrameJSON() {
        XCTAssertEqual(FleetEndpoint.resizeFrame(cols: 120, rows: 40),
                       #"{"resize":[120,40]}"#)
    }

    func testAgentRoster() {
        XCTAssertEqual(FleetEndpoint.agents.count, 10)
        XCTAssertEqual(FleetEndpoint.agents.first, "claude-1")
        XCTAssertEqual(FleetEndpoint.agents.last, "grok")
    }
}
