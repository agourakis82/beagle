import Testing
@testable import BeagleCore
@testable import BeagleWorkbenchKit
import Foundation

@Test func workbenchBoundaryDeclaresAgplAndPrivateMemoryPolicy() {
    let boundary = BeagleWorkbenchBoundary()

    #expect(boundary.license == "AGPL-3.0-only")
    #expect(boundary.bridgeVersion == "beagle-warp-bridge-v0.2")
    #expect(boundary.canonicalMemory.contains("cluster"))
    #expect(boundary.privateDataPolicy.contains("no-private-memory"))
    #expect(BeagleWorkbenchBoundary.warpVendorCommit == "805b3e2a576e689a1e414f01ed3fc51e9e704d69")
}

@Test func workbenchBridgeEnvelopeWrapsCoreTerminalBlock() throws {
    let block = TerminalBlock(
        id: "block-1",
        sessionId: "session-1",
        paneId: "pane-main",
        kind: "command",
        title: "swift test",
        command: "swift test",
        outputPreview: "passed",
        status: "finished",
        memoryStatus: "remembered",
        sourceModel: "beagle",
        bridgeVersion: "beagle-warp-bridge-v0.2",
        blockHash: "sha256:test"
    )
    let envelope = WorkbenchBridgeEnvelope(
        sourceModel: .beagle,
        rendererHint: "beagle-terminal-v1",
        payload: block
    )

    let data = try JSONEncoder().encode(envelope)
    let decoded = try JSONDecoder().decode(WorkbenchBridgeEnvelope<TerminalBlock>.self, from: data)

    #expect(decoded.sourceModel == .beagle)
    #expect(decoded.payload.id == "block-1")
    #expect(decoded.payload.memoryStatus == "remembered")
    #expect(decoded.payload.blockHash == "sha256:test")
}

@Test func workbenchActionModelsTerminalFullControls() {
    let approve = WorkbenchAction(kind: .approve, paneId: "pane-main", payload: "y\n")
    let remember = WorkbenchAction(kind: .attachBlockToMemory, paneId: "pane-main", blockId: "block-1")

    #expect(approve.kind == .approve)
    #expect(approve.payload == "y\n")
    #expect(remember.kind.rawValue == "attach_block_to_memory")
    #expect(remember.blockId == "block-1")
}

@Test func rendererBakeOffSampleRedactsRestrictedBlocks() {
    let restricted = TerminalBlock(
        id: "block-secret",
        sessionId: "session-1",
        paneId: "pane-main",
        title: "Restricted command",
        command: "export API_KEY=secret",
        outputPreview: "token output",
        privacyClass: "restricted_local_only",
        memoryStatus: "blocked",
        blockHash: "sha256:secret"
    )

    let sample = WorkbenchBakeOffSample(block: restricted)

    #expect(sample.restrictedRedacted)
    #expect(sample.command == "[restricted command redacted]")
    #expect(sample.outputPreview == "[restricted output redacted]")
    #expect(sample.blockHash == "sha256:secret")
}

@Test func rendererHumanJudgmentClampsExploratoryScore() {
    let low = RendererHumanJudgment(
        sampleId: "sample-1",
        selectedCandidate: .warpDerived,
        score: -4
    )
    let high = RendererHumanJudgment(
        sampleId: "sample-1",
        selectedCandidate: .beagleTerminal,
        score: 10
    )

    #expect(low.score == 1)
    #expect(high.score == 5)
}

@Test func warpMetalProbeDecodesVtAndLatencyBudget() throws {
    let json = """
    {
      "schema_version": "beagle-warp-metal-probe-v0.1",
      "status": "unsupported_or_partial",
      "platform": "darwin",
      "arch": "arm64",
      "bridge": {
        "version": "beagle-warp-bridge-v0.2",
        "vendor_commit": "805b3e2a576e689a1e414f01ed3fc51e9e704d69"
      },
      "vt_fidelity": {
        "status": "pass",
        "mode": "terminalblock_to_warpblock_preview",
        "notes": ["CSI/OSC preserved"]
      },
      "latency_budget": {
        "status": "pass",
        "total_ms": 14.22,
        "threshold_ms": 50,
        "scope": "probe_conversion_only",
        "note": "Derived probe latency only"
      },
      "fidelity_notes": ["not promoted"]
    }
    """.data(using: .utf8)!

    let decoded = try JSONDecoder().decode(WarpMetalProbeResult.self, from: json)

    #expect(decoded.status == "unsupported_or_partial")
    #expect(decoded.vtFidelity?.status == "pass")
    #expect(decoded.vtFidelity?.mode == "terminalblock_to_warpblock_preview")
    #expect(decoded.latencyBudget?.status == "pass")
    #expect(decoded.latencyBudget?.totalMs == 14.22)
    #expect(decoded.latencyBudget?.scope == "probe_conversion_only")
}

@Test func appleDeviceGateRequiresHumanPassBeforePromotion() {
    let sample = WorkbenchBakeOffSample(
        id: "sample-1",
        sessionId: "session-1",
        paneId: "pane-main",
        blockId: "block-1",
        title: "swift test",
        command: "swift test",
        outputPreview: "passed",
        status: "finished",
        privacyClass: "sensitive",
        memoryStatus: "remembered",
        blockHash: "sha256:block"
    )
    let probe = WarpMetalProbeResult(
        status: "unsupported_or_partial",
        platform: "darwin",
        arch: "arm64",
        vtFidelity: RendererProbeVTFidelity(status: "pass", mode: "terminalblock_to_warpblock_preview"),
        latencyBudget: RendererProbeLatencyBudget(status: "pass", totalMs: 14.22, thresholdMs: 50, scope: "probe_conversion_only")
    )
    let preHuman = WorkbenchAppleDeviceGate.evaluate(
        sample: sample,
        probe: probe,
        viewportWidth: 1024
    )
    let judged = WorkbenchAppleDeviceGate.evaluate(
        sample: sample,
        probe: probe,
        judgments: [
            RendererHumanJudgment(sampleId: sample.id, selectedCandidate: .beagleTerminal, score: 4)
        ],
        viewportWidth: 1024
    )

    #expect(preHuman.status == "needs_human_device_pass")
    #expect(preHuman.promotionAllowed == false)
    #expect(preHuman.blockers.contains("human device judgment missing"))
    #expect(judged.status == "device_pass")
    #expect(judged.humanJudgmentScore == 4)
    #expect(judged.promotionAllowed == false)
}
