// SPDX-License-Identifier: AGPL-3.0-only
//
// BeagleWorkbenchKit is the Apple AGPL boundary for terminal/workbench UX.
// It intentionally depends on BeagleCore models by protocol, while canonical
// memory remains cluster-owned through assisted-import.

import BeagleCore
import Foundation

public typealias WorkbenchSession = WorkspaceSession
public typealias WorkbenchPane = TerminalPane
public typealias WorkbenchBlock = TerminalBlock
public typealias WorkbenchAgentState = AgentRunState
public typealias WorkbenchApprovalRequest = ApprovalRequest

public enum WorkbenchSourceModel: String, Codable, Sendable {
    case beagle
    case warp
}

public enum WorkbenchMemoryImportState: String, Codable, Sendable {
    case remembered
    case blocked
    case queued
    case failed
    case manual
    case notSaved = "not_saved"
}

public struct BeagleWorkbenchBoundary: Codable, Sendable {
    public static let bridgeVersion = "beagle-warp-bridge-v0.1"
    public static let warpVendorCommit = "805b3e2a576e689a1e414f01ed3fc51e9e704d69"

    public let license: String
    public let bridgeVersion: String
    public let canonicalMemory: String
    public let privateDataPolicy: String

    public init(
        license: String = "AGPL-3.0-only",
        bridgeVersion: String = BeagleWorkbenchBoundary.bridgeVersion,
        canonicalMemory: String = "cluster-jsonl-merkle-chronoself",
        privateDataPolicy: String = "no-private-memory-in-github-or-local-canonical-store"
    ) {
        self.license = license
        self.bridgeVersion = bridgeVersion
        self.canonicalMemory = canonicalMemory
        self.privateDataPolicy = privateDataPolicy
    }
}

public struct WorkbenchBridgeEnvelope<Payload: Codable & Sendable>: Codable, Sendable {
    public let sourceModel: WorkbenchSourceModel
    public let bridgeVersion: String
    public let rendererHint: String
    public let payload: Payload

    public init(
        sourceModel: WorkbenchSourceModel,
        bridgeVersion: String = BeagleWorkbenchBoundary.bridgeVersion,
        rendererHint: String,
        payload: Payload
    ) {
        self.sourceModel = sourceModel
        self.bridgeVersion = bridgeVersion
        self.rendererHint = rendererHint
        self.payload = payload
    }
}

public struct WorkbenchAction: Codable, Identifiable, Sendable {
    public enum Kind: String, Codable, Sendable {
        case input
        case resize
        case signal
        case paste
        case focus
        case startProcess = "start_process"
        case stopProcess = "stop_process"
        case markBlock = "mark_block"
        case approve
        case attachBlockToMemory = "attach_block_to_memory"
    }

    public let id: String
    public let kind: Kind
    public let paneId: String
    public let blockId: String?
    public let payload: String?

    public init(
        id: String = UUID().uuidString,
        kind: Kind,
        paneId: String,
        blockId: String? = nil,
        payload: String? = nil
    ) {
        self.id = id
        self.kind = kind
        self.paneId = paneId
        self.blockId = blockId
        self.payload = payload
    }
}
