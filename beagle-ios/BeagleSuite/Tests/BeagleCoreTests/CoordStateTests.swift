import Foundation
import Testing
@testable import BeagleCore

/// Coordination. The hazard below is REAL: on 2026-08-08 all 10 live lanes shared one working
/// tree and branch, so an edit by any of them was clobberable by all.
@Suite
struct CoordStateTests {
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

    @Test func testSharedTreeHazardAndBothSidesOfAConflict() throws {
        let s = try #require(CoordState(envelope: envelope()))
        #expect(s.hazards.count == 1)
        #expect(s.lanesAtRisk == 10)
        #expect(s.conflicts.first?.lanes == ["claude-1", "kimi-cli1"])
        // Both agents' own words travel with the conflict, so he can judge who should yield.
        #expect(s.conflicts.first?.notes.count == 2)
        #expect(s.conflicts.first?.overlaps.first?.contains("∩") == true)
        #expect(s.claims.count == 2)
        #expect(s.claims[0].expiresAt != nil)
        #expect(s.claims[1].expiresAt == nil, "a missing expiry stays nil, not a fake date")
    }

    @Test func testOneLanePerWorktreeIsNeverAHazard() throws {
        let safe = try #require(CoordState(envelope: ["data": ["sharedTrees": [
            ["cwd": "/workspace/.wt/claude-1", "branch": "lane/claude-1/x", "lanes": ["claude-1"]],
            ["cwd": "/workspace/.wt/kimi-cli1", "branch": "lane/kimi-cli1/y", "lanes": ["kimi-cli1"]],
        ]]]))
        #expect(safe.hazards.isEmpty, "this is exactly what the worktree migration buys")
        #expect(safe.lanesAtRisk == 0)
    }

    @Test func testAMissedPollNeverReadsAsAllClear() throws {
        let thin = try #require(CoordState(envelope: ["data": [:]]))
        #expect(thin.hazards.isEmpty)
        #expect(thin.observedAt == nil)
        #expect(thin.isStale, "never observed must not look like all-clear")
        let errored = CoordState(claims: [], conflicts: [], sharedTrees: [],
                                 observedAt: Date(), error: "unreachable")
        #expect(errored.isStale)
        #expect(CoordState(envelope: ["meta": [:]]) == nil)
    }

    @Test func testJunkRowsAreDroppedNotInvented() throws {
        let junk = try #require(CoordState(envelope: ["data": [
            "sharedTrees": [["cwd": "/x"]],
            "conflicts": [["lanes": ["only-one"]]],
        ]]))
        #expect(junk.sharedTrees.isEmpty, "a tree with no lanes is not a tree")
        #expect(junk.conflicts.isEmpty, "a conflict needs exactly two parties")
    }
}
