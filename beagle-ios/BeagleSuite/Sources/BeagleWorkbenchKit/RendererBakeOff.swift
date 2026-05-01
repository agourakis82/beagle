// SPDX-License-Identifier: AGPL-3.0-only
//
// Derived renderer bake-off models for the Apple Workbench boundary.
// These are local/UI artifacts only; canonical memory remains cluster-owned.

import BeagleCore
import Foundation

public enum WorkbenchRendererCandidate: String, Codable, Sendable, CaseIterable {
    case beagleTerminal = "beagle-terminal-v1"
    case warpDerived = "warp-derived-spike"
    case warpMetalProbe = "warp-metal-probe"
    case ipadMicroMetal = "ipad-micro-metal"

    public var title: String {
        switch self {
        case .beagleTerminal: "Beagle Terminal"
        case .warpDerived: "WarpBlock Preview"
        case .warpMetalProbe: "Warp Metal Probe"
        case .ipadMicroMetal: "iPad Micro Metal"
        }
    }
}

public struct WorkbenchBakeOffSample: Codable, Identifiable, Sendable, Equatable {
    public let id: String
    public let sessionId: String
    public let paneId: String
    public let blockId: String
    public let title: String
    public let command: String
    public let outputPreview: String
    public let status: String
    public let privacyClass: String
    public let memoryStatus: String
    public let blockHash: String?
    public let bridgeVersion: String
    public let restrictedRedacted: Bool

    public init(
        id: String,
        sessionId: String,
        paneId: String,
        blockId: String,
        title: String,
        command: String,
        outputPreview: String,
        status: String,
        privacyClass: String,
        memoryStatus: String,
        blockHash: String? = nil,
        bridgeVersion: String = BeagleWorkbenchBoundary.bridgeVersion,
        restrictedRedacted: Bool = false
    ) {
        self.id = id
        self.sessionId = sessionId
        self.paneId = paneId
        self.blockId = blockId
        self.title = title
        self.command = command
        self.outputPreview = outputPreview
        self.status = status
        self.privacyClass = privacyClass
        self.memoryStatus = memoryStatus
        self.blockHash = blockHash
        self.bridgeVersion = bridgeVersion
        self.restrictedRedacted = restrictedRedacted
    }

    public init(block: TerminalBlock) {
        let restricted = block.privacyClass == "restricted" || block.privacyClass == "restricted_local_only"
        self.init(
            id: "sample:\(block.sessionId):\(block.id)",
            sessionId: block.sessionId,
            paneId: block.paneId,
            blockId: block.id,
            title: block.title.isEmpty ? block.kind.capitalized : block.title,
            command: restricted ? "[restricted command redacted]" : block.command,
            outputPreview: restricted ? "[restricted output redacted]" : block.outputPreview,
            status: block.status,
            privacyClass: block.privacyClass,
            memoryStatus: block.memoryStatus,
            blockHash: block.blockHash,
            bridgeVersion: block.bridgeVersion ?? BeagleWorkbenchBoundary.bridgeVersion,
            restrictedRedacted: restricted
        )
    }
}

public struct WorkbenchRendererScore: Codable, Identifiable, Sendable, Equatable {
    public let id: String
    public let candidate: WorkbenchRendererCandidate
    public let status: String
    public let roughLatencyMs: Double?
    public let fidelityNote: String
    public let restrictedLeakCheck: String
    public let provenancePreserved: Bool

    public init(
        id: String = UUID().uuidString,
        candidate: WorkbenchRendererCandidate,
        status: String,
        roughLatencyMs: Double? = nil,
        fidelityNote: String,
        restrictedLeakCheck: String = "passed:no_restricted_output",
        provenancePreserved: Bool = true
    ) {
        self.id = id
        self.candidate = candidate
        self.status = status
        self.roughLatencyMs = roughLatencyMs
        self.fidelityNote = fidelityNote
        self.restrictedLeakCheck = restrictedLeakCheck
        self.provenancePreserved = provenancePreserved
    }
}

public struct WarpMetalProbeResult: Codable, Sendable, Equatable {
    public let schemaVersion: String
    public let status: String
    public let platform: String
    public let arch: String
    public let bridgeVersion: String
    public let vendorCommit: String
    public let reason: String?
    public let artifactPath: String?

    enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case status
        case platform
        case arch
        case bridge
        case renderer
        case fidelityNotes = "fidelity_notes"
        case artifactPath = "artifact_path"
    }

    public init(
        schemaVersion: String = "beagle-warp-metal-probe-v0.1",
        status: String = "not_measured",
        platform: String = "",
        arch: String = "",
        bridgeVersion: String = BeagleWorkbenchBoundary.bridgeVersion,
        vendorCommit: String = BeagleWorkbenchBoundary.warpVendorCommit,
        reason: String? = nil,
        artifactPath: String? = nil
    ) {
        self.schemaVersion = schemaVersion
        self.status = status
        self.platform = platform
        self.arch = arch
        self.bridgeVersion = bridgeVersion
        self.vendorCommit = vendorCommit
        self.reason = reason
        self.artifactPath = artifactPath
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.schemaVersion = try container.decodeIfPresent(String.self, forKey: .schemaVersion) ?? "beagle-warp-metal-probe-v0.1"
        self.status = try container.decodeIfPresent(String.self, forKey: .status) ?? "not_measured"
        self.platform = try container.decodeIfPresent(String.self, forKey: .platform) ?? ""
        self.arch = try container.decodeIfPresent(String.self, forKey: .arch) ?? ""
        let bridge = try container.decodeIfPresent([String: String].self, forKey: .bridge) ?? [:]
        self.bridgeVersion = bridge["version"] ?? BeagleWorkbenchBoundary.bridgeVersion
        self.vendorCommit = bridge["vendor_commit"] ?? BeagleWorkbenchBoundary.warpVendorCommit
        let notes = try container.decodeIfPresent([String].self, forKey: .fidelityNotes)
        self.reason = notes?.last
        self.artifactPath = try container.decodeIfPresent(String.self, forKey: .artifactPath)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(schemaVersion, forKey: .schemaVersion)
        try container.encode(status, forKey: .status)
        try container.encode(platform, forKey: .platform)
        try container.encode(arch, forKey: .arch)
        try container.encode([
            "version": bridgeVersion,
            "vendor_commit": vendorCommit,
        ], forKey: .bridge)
        if let reason {
            try container.encode([reason], forKey: .fidelityNotes)
        }
        try container.encodeIfPresent(artifactPath, forKey: .artifactPath)
    }
}

public struct RendererHumanJudgment: Codable, Identifiable, Sendable, Equatable {
    public let id: String
    public let sampleId: String
    public let selectedCandidate: WorkbenchRendererCandidate
    public let score: Int
    public let notes: String
    public let createdAt: String

    public init(
        id: String = UUID().uuidString,
        sampleId: String,
        selectedCandidate: WorkbenchRendererCandidate,
        score: Int,
        notes: String = "",
        createdAt: String = ISO8601DateFormatter().string(from: Date())
    ) {
        self.id = id
        self.sampleId = sampleId
        self.selectedCandidate = selectedCandidate
        self.score = max(1, min(5, score))
        self.notes = notes
        self.createdAt = createdAt
    }
}
