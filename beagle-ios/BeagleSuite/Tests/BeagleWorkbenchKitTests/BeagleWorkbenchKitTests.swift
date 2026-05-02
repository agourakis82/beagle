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

@Test func appleDevicePassEvidenceEncodesSanitizedClusterPayload() throws {
    let sample = WorkbenchBakeOffSample(
        id: "sample-session-block",
        sessionId: "session-1",
        paneId: "pane-main",
        blockId: "block-1",
        title: "swift test",
        command: "swift test",
        outputPreview: "very long terminal output that should not be exported",
        status: "finished",
        privacyClass: "sensitive",
        memoryStatus: "remembered",
        blockHash: "sha256:block"
    )
    let gate = WorkbenchAppleDeviceGate(
        status: "needs_human_device_pass",
        formFactor: .ipadOrMac,
        viewportWidth: 1180,
        touchTargetReady: true,
        dynamicTypeReady: true,
        restrictedLeakCheck: "passed:no_restricted_output",
        vtFidelityStatus: "pass",
        latencyStatus: "pass",
        humanJudgmentScore: 3,
        promotionAllowed: false,
        blockers: ["physical iPad/iPhone input-to-paint pass not recorded"]
    )
    let evidence = AppleDevicePassEvidence(
        projectSlug: "sounio",
        sample: sample,
        gate: gate,
        selectedCandidate: .beagleTerminal,
        inputToPaintMs: 14.22,
        notes: "Sanitized preflight evidence only.",
        device: [
            "platform": "macOS",
            "form_factor": "mac",
            "os_version": "local-preflight",
            "build": "codex-sprint"
        ],
        createdAt: "2026-05-02T12:00:00Z"
    )

    let data = try JSONEncoder().encode(evidence)
    let object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
    let decoded = try JSONDecoder().decode(AppleDevicePassEvidence.self, from: data)

    #expect(object["schema_version"] as? String == "beagle-apple-device-pass-v0.1")
    #expect(object["project_slug"] as? String == "sounio")
    #expect(object["selected_candidate"] as? String == "beagle-terminal-v1")
    #expect(object["canonical_memory_written"] as? Bool == false)
    #expect(object["promotion_allowed"] as? Bool == false)
    #expect(object["command"] == nil)
    #expect(object["output_preview"] == nil)
    #expect(decoded.blockId == "block-1")
    #expect(decoded.gateStatus == "needs_human_device_pass")
    #expect(decoded.inputToPaintMs == 14.22)
    #expect(decoded.canonicalMemoryWritten == false)
}

@Test func visualWorkbenchArtifactsRedactRestrictedBlocks() {
    let block = TerminalBlock(
        id: "block-secret",
        sessionId: "session-1",
        paneId: "pane-main",
        title: "export token",
        command: "export OPENAI_API_KEY=secret-value",
        outputPreview: "secret-value leaked in terminal",
        privacyClass: "restricted_local_only",
        memoryStatus: "blocked",
        blockHash: "sha256:secret"
    )

    let artifact = VisualWorkArtifact(block: block)

    #expect(artifact.restrictedRedacted)
    #expect(artifact.title == "[restricted command redacted]")
    #expect(artifact.summary == "[restricted output redacted]")
    #expect(!artifact.title.contains("secret-value"))
    #expect(!artifact.summary.contains("secret-value"))
    #expect(artifact.memoryStatus == "blocked")
    #expect(artifact.provenanceRefs.contains("sha256:secret"))
    #expect(artifact.touchedFiles.isEmpty)
    #expect(artifact.evidenceBadges.contains("restricted redacted"))
}

@Test func visualWorkbenchCanvasIsDeterministicAndClassifiesArtifacts() {
    let session = WorkspaceSession(id: "session-1", projectSlug: "sounio", title: "Sounio Workday")
    let testBlock = TerminalBlock(
        id: "block-test",
        sessionId: "session-1",
        paneId: "pane-main",
        title: "swift test",
        command: "swift test",
        outputPreview: "Test Suite passed",
        status: "finished",
        memoryStatus: "remembered",
        blockHash: "sha256:test"
    )
    let diffBlock = TerminalBlock(
        id: "block-diff",
        sessionId: "session-1",
        paneId: "pane-main",
        title: "git diff --stat",
        command: "git diff --stat",
        outputPreview: "Sources/Sounio/Compiler.swift | 12 +++---\nTests/SounioTests/CompilerTests.swift | 4 ++\n2 files changed",
        status: "finished",
        blockHash: "sha256:diff"
    )
    let lane = AgentLaneState(
        id: "shell",
        title: "Shell",
        kind: "human",
        paneId: "pane-main",
        status: "live",
        detail: "Attached to workspace",
        memoryStatus: "remembered",
        isActive: true
    )

    let first = VisualWorkCanvasState.synthesized(
        projectSlug: "sounio",
        session: session,
        lanes: [lane],
        blocks: [testBlock, diffBlock],
        selectedBlockId: "block-test",
        workMemoryLine: "latest memory",
        workMemoryStatus: "remembered"
    )
    let second = VisualWorkCanvasState.synthesized(
        projectSlug: "sounio",
        session: session,
        lanes: [lane],
        blocks: [testBlock, diffBlock],
        selectedBlockId: "block-test",
        workMemoryLine: "latest memory",
        workMemoryStatus: "remembered"
    )

    #expect(first == second)
    #expect(first.selectedArtifact?.kind == .test)
    #expect(first.recentArtifacts.map(\.kind).contains(.diff))
    #expect(first.recentArtifacts.first(where: { $0.kind == .diff })?.touchedFiles == [
        "Sources/Sounio/Compiler.swift",
        "Tests/SounioTests/CompilerTests.swift"
    ])
    #expect(first.restrictedLeakCheck == "passed:no_restricted_visual_payload")
    #expect(first.lanes.first?.runtimeAvailable == true)
}

@Test func visualWorkbenchCanvasUsesLiveBlocksBeforeReplayRefresh() {
    let session = WorkspaceSession(id: "session-1", projectSlug: "sounio", title: "Sounio Workday")
    let replayBlock = TerminalBlock(
        id: "block-live",
        sessionId: "session-1",
        paneId: "pane-main",
        title: "swift test",
        command: "swift test",
        outputPreview: "old replay output",
        status: "finished",
        memoryStatus: "not_saved",
        blockHash: "sha256:old"
    )
    let liveBlock = TerminalBlockLiveState(
        id: "block-live",
        sessionId: "session-1",
        paneId: "pane-main",
        title: "swift test",
        command: "swift test",
        outputPreview: "fresh live pass",
        status: "finished",
        memoryStatus: "remembered",
        memoryEventId: "memory-live"
    )
    let lane = AgentLaneState(
        id: "shell",
        title: "Shell",
        kind: "human",
        paneId: "pane-main",
        status: "live",
        detail: "Attached to workspace",
        isActive: true
    )

    let state = VisualWorkCanvasState.synthesized(
        projectSlug: "sounio",
        session: session,
        lanes: [lane],
        blocks: [replayBlock],
        liveBlocks: [liveBlock],
        selectedBlockId: "block-live",
        workMemoryLine: "latest memory",
        workMemoryStatus: "remembered"
    )

    #expect(state.selectedArtifact?.summary == "fresh live pass")
    #expect(state.selectedArtifact?.memoryStatus == "remembered")
    #expect(state.selectedArtifact?.provenanceRefs == ["memory-live"])
    #expect(state.selectedArtifact?.evidenceBadges.contains("live") == true)
    #expect(state.recentArtifacts.count == 1)
    #expect(state.lanes.first?.currentArtifact?.summary == "fresh live pass")
}

@Test func visualWorkbenchLiveBlocksRedactRestrictedOutput() {
    let liveBlock = TerminalBlockLiveState(
        id: "block-secret-live",
        sessionId: "session-1",
        paneId: "pane-main",
        title: "export token",
        command: "export OPENAI_API_KEY=secret-value",
        outputPreview: "secret-value leaked in terminal",
        status: "finished",
        privacyClass: "restricted_local_only",
        memoryStatus: "blocked",
        auditEventId: "audit-redacted"
    )

    let artifact = VisualWorkArtifact(liveBlock: liveBlock)

    #expect(artifact.restrictedRedacted)
    #expect(artifact.title == "[restricted command redacted]")
    #expect(artifact.summary == "[restricted output redacted]")
    #expect(!artifact.title.contains("secret-value"))
    #expect(!artifact.summary.contains("secret-value"))
    #expect(artifact.memoryStatus == "blocked")
    #expect(artifact.provenanceRefs == ["audit-redacted"])
    #expect(artifact.evidenceBadges.contains("restricted redacted"))
    #expect(artifact.evidenceBadges.contains("live"))
}

@Test func visualWorkbenchExtractsTouchedFilesAndRuntimeSheetIdentity() {
    let output = "\u{001B}[32mSources/App/WorkView.swift\u{001B}[0m | 20 +++++\nREADME.md | 2 +\n2 files changed"
    let files = VisualWorkArtifact.extractTouchedFiles(from: output)
    let runtime = RuntimeLogPresentationState(
        title: "Shell",
        sessionId: "session-1",
        paneId: "pane-main",
        isRuntimePrimary: false
    )

    #expect(files == ["Sources/App/WorkView.swift", "README.md"])
    #expect(runtime.id.contains("Shell"))
    #expect(runtime.id.contains("session-1"))
    #expect(runtime.id.contains("pane-main"))
}

@Test func visualAgentLaneSnapshotReflectsNeedsSetupAndRuntime() {
    let needsSetup = AgentLaneState(
        id: "primary_builder",
        title: "Claude / Codex",
        kind: "codex",
        status: "needs_setup",
        detail: "Codex is not on PATH",
        readinessReason: "codex is not on PATH"
    )
    let setupSnapshot = VisualAgentLaneSnapshot(lane: needsSetup)

    #expect(setupSnapshot.readiness == "needs_setup")
    #expect(setupSnapshot.setupGap == "codex is not on PATH")
    #expect(setupSnapshot.runtimeAvailable == false)

    let block = TerminalBlock(
        id: "block-1",
        sessionId: "session-1",
        paneId: "pane-main",
        title: "codex",
        command: "codex",
        outputPreview: "bash: codex: command not found",
        status: "finished",
        memoryStatus: "failed",
        blockHash: "sha256:block"
    )
    let readyLane = AgentLaneState(
        id: "primary_builder",
        title: "Claude / Codex",
        kind: "codex",
        paneId: "pane-main",
        status: "idle",
        detail: "Ready",
        isActive: true
    )
    let readySnapshot = VisualAgentLaneSnapshot(lane: readyLane, blocks: [block])

    #expect(readySnapshot.readiness == "ready")
    #expect(readySnapshot.runtimeAvailable)
    #expect(readySnapshot.currentArtifact?.kind == .agent)
    #expect(readySnapshot.memoryStatus == "failed")
}

@Test func spatialAgentDeckFallbackUsesVisualLanes() {
    let deck = SpatialAgentDeckSnapshot.fallback(
        projectSlug: "sounio",
        laneTitles: ["Claude/Codex", "MiniMax", "Kimi", "Shell"]
    )

    #expect(deck.projectSlug == "sounio")
    #expect(deck.lanes.count == 4)
    #expect(deck.lanes.last?.kind == "human")
    #expect(deck.activeTask.contains("Sounio"))
    #expect(deck.proofLine.contains("cluster"))
}
