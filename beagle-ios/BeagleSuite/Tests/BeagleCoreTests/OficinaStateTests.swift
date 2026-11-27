import Foundation
import Testing
@testable import BeagleCore

/// The Oficina's reading. Fixtures mirror the live endpoint's shape (real Sounio PRs).
@Suite
struct OficinaStateTests {
    private func envelope() -> [String: Any] {
        [
            "ok": true,
            "data": [
                "prs": [
                    ["number": 1681, "title": "fix(ir): hoist aggregate array elements",
                     "branch": "fix/ir-hoist", "url": "https://gh/1681", "draft": false,
                     "verdict": "red", "checksTotal": 15, "checksGreen": 8,
                     "updatedAt": "2026-08-08T16:20:00Z",
                     "failing": [["name": "Contracts", "workflow": "CI", "url": "https://gh/c"],
                                 ["name": "CI Decision", "workflow": "CI", "url": "https://gh/d"]]],
                    ["number": 1684, "title": "ci: resync the Madaros prebuilt receipt",
                     "branch": "fix/madaros", "url": "https://gh/1684", "draft": false,
                     "verdict": "green", "checksTotal": 15, "checksGreen": 12, "failing": []],
                    ["number": 1672, "title": "Madaros: cross-module DCE", "branch": "fix/dce",
                     "url": "https://gh/1672", "draft": true, "verdict": "green",
                     "checksTotal": 4, "checksGreen": 1, "failing": []],
                ],
                "main": ["verdict": "red", "runs": []],
                "head": ["branch": "research/zd-fiber-antisymmetry-lemma-20260731",
                         "sha": "5c4e950f11", "subject": "feat(zd): Tier 94",
                         "committedAt": "2026-08-08T05:39:06Z", "dirtyFiles": 52],
                "observedAt": 1_786_205_946_000.0,
            ],
            "meta": ["truthMode": "observed", "error": NSNull()],
        ]
    }

    @Test func testRedSortsFirstAndFailingChecksAreNamed() throws {
        let s = try #require(OficinaState(envelope: envelope()))
        #expect(s.ordered.map(\.number) == [1681, 1684, 1672])
        #expect(s.red.count == 1)
        #expect(s.prs[0].failing.map(\.name) == ["Contracts", "CI Decision"])
        #expect(s.mainVerdict == .red)
    }

    @Test func testChecksSummaryExposesHowMuchActuallyRan() throws {
        let s = try #require(OficinaState(envelope: envelope()))
        // Green over 1/4 checks means something very different from green over 12/15.
        #expect(s.prs[0].checksSummary == "8/15")
        #expect(s.prs[2].checksSummary == "1/4")
    }

    @Test func testHeadDecodes() throws {
        let s = try #require(OficinaState(envelope: envelope()))
        #expect(s.head?.dirtyFiles == 52)
        #expect(s.head?.branch.hasPrefix("research/zd-fiber") == true)
        #expect(s.head?.committedAt != nil)
    }

    @Test func testDegradesToUnknownNeverToAConfidentGreen() throws {
        let thin = try #require(OficinaState(envelope: ["data": [:]]))
        #expect(thin.mainVerdict == .unknown)
        #expect(thin.prs.isEmpty)
        #expect(thin.isStale())
        #expect(OficinaState(envelope: ["meta": [:]]) == nil)
        let bogus = try #require(OficinaState(envelope: ["data": ["prs": [["number": 9, "verdict": "sparkling"]]]]))
        #expect(bogus.prs.first?.verdict == .unknown)
        let ghost = try #require(OficinaState(envelope: ["data": ["prs": [["title": "no number"]]]]))
        #expect(ghost.prs.isEmpty)
    }

    @Test func testAnErroredSweepIsStaleEvenWithAFreshTimestamp() {
        let failed = OficinaState(prs: [], mainVerdict: .green, head: nil,
                                  observedAt: Date(), error: "workspace unreachable")
        #expect(failed.isStale())
        #expect(!OficinaState(prs: [], mainVerdict: .green, head: nil,
                              observedAt: Date(), error: nil).isStale())
    }
}
