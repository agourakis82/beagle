import XCTest
@testable import BeagleCore

/// Coordination. The hazard below is REAL: on 2026-08-08 all 10 live lanes shared one working
/// tree and branch, so an edit by any of them was clobberable by all.
final class CoordStateTests: XCTestCase {
    private func envelope() -> [String: Any] {
        [
            "data": [
                "sharedTrees": [[
                    "cwd": "/workspace/sounio",
                    "branch": "research/zd-fiber-antisymmetry-lemma-20260731",
                    "lanes": ["claude-1", "claude-2", "claude-3", "codex-1", "codex-2",
                              "grok-cli1", "grok-cli2", "kimi-cli1", "kimi-cli2", "repo"],
                ]],
                "conflicts": [[
                    "lanes": ["claude-1", "kimi-cli1"],
                    "overlaps": [["a": "self-hosted/check/**", "b": "self-hosted/check/effects.sio"]],
                    "notes": ["efeitos: fix do auto-deref", "prova espectral"],
                ]],
                "claims": [
                    ["lane": "claude-1", "globs": ["self-hosted/check/**"], "note": "efeitos",
                     "expiresAt": 1_786_300_000_000.0],
                    ["lane": "codex-1", "globs": ["stdlib/linalg/**"], "note": "blas"],
                ],
                "observedAt": 1_786_212_000_000.0,
            ],
            "meta": ["truthMode": "observed", "error": NSNull()],
        ]
    }

    func testSharedTreeHazardAndBothSidesOfAConflict() throws {
        let s = try XCTUnwrap(CoordState(envelope: envelope()))
        XCTAssertEqual(s.hazards.count, 1)
        XCTAssertEqual(s.lanesAtRisk, 10)
        XCTAssertEqual(s.conflicts.first?.lanes, ["claude-1", "kimi-cli1"])
        // Both agents' own words travel with the conflict, so he can judge who should yield.
        XCTAssertEqual(s.conflicts.first?.notes.count, 2)
        XCTAssertTrue(s.conflicts.first?.overlaps.first?.contains("∩") ?? false)
        XCTAssertEqual(s.claims.count, 2)
        XCTAssertNotNil(s.claims[0].expiresAt)
        XCTAssertNil(s.claims[1].expiresAt, "a missing expiry stays nil, not a fake date")
    }

    func testOneLanePerWorktreeIsNeverAHazard() throws {
        let safe = try XCTUnwrap(CoordState(envelope: ["data": ["sharedTrees": [
            ["cwd": "/workspace/.wt/claude-1", "branch": "lane/claude-1/x", "lanes": ["claude-1"]],
            ["cwd": "/workspace/.wt/kimi-cli1", "branch": "lane/kimi-cli1/y", "lanes": ["kimi-cli1"]],
        ]]]))
        XCTAssertTrue(safe.hazards.isEmpty, "this is exactly what the worktree migration buys")
        XCTAssertEqual(safe.lanesAtRisk, 0)
    }

    func testAMissedPollNeverReadsAsAllClear() throws {
        let thin = try XCTUnwrap(CoordState(envelope: ["data": [:]]))
        XCTAssertTrue(thin.hazards.isEmpty)
        XCTAssertNil(thin.observedAt)
        XCTAssertTrue(thin.isStale, "never observed must not look like all-clear")
        let errored = CoordState(claims: [], conflicts: [], sharedTrees: [],
                                 observedAt: Date(), error: "unreachable")
        XCTAssertTrue(errored.isStale)
        XCTAssertNil(CoordState(envelope: ["meta": [:]]))
    }

    func testJunkRowsAreDroppedNotInvented() throws {
        let junk = try XCTUnwrap(CoordState(envelope: ["data": [
            "sharedTrees": [["cwd": "/x"]],
            "conflicts": [["lanes": ["only-one"]]],
        ]]))
        XCTAssertTrue(junk.sharedTrees.isEmpty, "a tree with no lanes is not a tree")
        XCTAssertTrue(junk.conflicts.isEmpty, "a conflict needs exactly two parties")
    }
}
