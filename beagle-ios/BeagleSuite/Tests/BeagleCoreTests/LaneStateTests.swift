import XCTest
@testable import BeagleCore

/// The Frota board's rules. Ported from checks run against the live broker on 2026-08-08.
final class LaneStateTests: XCTestCase {
    private let lanes = [
        LaneSnapshot(sid: "repo", title: "repo", state: .idle),
        LaneSnapshot(sid: "codex-1", title: "codex-1", state: .running),
        LaneSnapshot(sid: "kimi-cli1", title: "kimi-cli1", state: .waiting,
                     detail: "A pergunta: quer que eu rode o pré-registro?",
                     approve: .answerNeeded, observedAt: Date(timeIntervalSince1970: 100)),
        LaneSnapshot(sid: "claude-2", title: "claude-2", state: .stuck),
        LaneSnapshot(sid: "claude-1", title: "claude-1", state: .waiting,
                     detail: "Do you want to proceed?",
                     approve: .enterKey, observedAt: Date(timeIntervalSince1970: 50)),
        LaneSnapshot(sid: "grok-cli1", title: "grok-cli1", state: .unknown),
    ]

    func testShelfHoldsOnlyLanesBlockedOnTheOperator() {
        XCTAssertEqual(FrotaBoard.shelf(lanes).map(\.sid), ["claude-1", "kimi-cli1", "claude-2"])
        XCTAssertEqual(FrotaBoard.rest(lanes).map(\.sid), ["codex-1", "repo", "grok-cli1"])
        XCTAssertFalse(FrotaBoard.rest(lanes).contains { $0.needsOperator })
    }

    func testOneTapApprovalNeverAnswersAnOpenQuestion() {
        // ⌘↩ may clear a permission dialog; it must never "answer" a real question for him.
        XCTAssertEqual(FrotaBoard.oldestApprovable(lanes)?.sid, "claude-1")
        XCTAssertNil(FrotaBoard.oldestApprovable([lanes[2]]))
        XCTAssertNil(ApproveAffordance.answerNeeded.injection)
        XCTAssertEqual(ApproveAffordance.enterKey.injection, "\r")
        XCTAssertEqual(ApproveAffordance.yKey.injection, "y\n")
    }

    func testDecodesALoomSessionsEntry() {
        let s = LaneSnapshot(loom: [
            "sid": "kimi-cli1", "title": "kimi-cli1", "state": "waiting",
            "detail": "A pergunta: quer que eu baixe LEMON/MODMA?",
            "peek": ["• H2: σ_min correlaciona", "A pergunta: ..."],
            "approveKey": NSNull(), "observedAt": 1_700_000_000_000.0,
        ])
        XCTAssertEqual(s?.state, .waiting)
        XCTAssertEqual(s?.family, .kimi)
        XCTAssertEqual(s?.peek.count, 2)
        XCTAssertEqual(s?.approve, .answerNeeded)
        XCTAssertNotNil(s?.observedAt)
    }

    func testAnUnobservedLaneIsUnknownAndStaleNeverAComfortableIdle() {
        let thin = LaneSnapshot(loom: ["sid": "codex-3"])
        XCTAssertEqual(thin?.state, .unknown, "a board that guesses idle teaches distrust")
        XCTAssertNil(thin?.observedAt)
        XCTAssertTrue(thin?.isStale() ?? false)
        XCTAssertNil(LaneSnapshot(loom: ["state": "running"]), "no sid = not a lane")
        XCTAssertEqual(LaneSnapshot(loom: ["sid": "x", "state": "vibing"])?.state, .unknown)
    }

    func testStalenessWindow() {
        XCTAssertFalse(LaneSnapshot(sid: "a", title: "a", state: .running, observedAt: Date()).isStale())
        XCTAssertTrue(LaneSnapshot(sid: "b", title: "b", state: .running,
                                   observedAt: Date().addingTimeInterval(-120)).isStale())
    }
}
