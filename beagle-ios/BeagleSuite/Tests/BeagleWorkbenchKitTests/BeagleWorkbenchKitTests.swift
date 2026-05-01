import Testing
@testable import BeagleCore
@testable import BeagleWorkbenchKit
import Foundation

@Test func workbenchBoundaryDeclaresAgplAndPrivateMemoryPolicy() {
    let boundary = BeagleWorkbenchBoundary()

    #expect(boundary.license == "AGPL-3.0-only")
    #expect(boundary.bridgeVersion == "beagle-warp-bridge-v0.1")
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
        bridgeVersion: "beagle-warp-bridge-v0.1",
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
