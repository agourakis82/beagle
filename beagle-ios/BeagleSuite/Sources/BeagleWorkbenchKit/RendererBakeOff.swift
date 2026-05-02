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

public struct RendererProbeVTFidelity: Codable, Sendable, Equatable {
    public let status: String
    public let mode: String
    public let notes: [String]

    enum CodingKeys: String, CodingKey {
        case status
        case mode
        case notes
    }

    public init(status: String = "not_measured", mode: String = "unknown", notes: [String] = []) {
        self.status = status
        self.mode = mode
        self.notes = notes
    }
}

public struct RendererProbeLatencyBudget: Codable, Sendable, Equatable {
    public let status: String
    public let totalMs: Double?
    public let thresholdMs: Double?
    public let scope: String
    public let note: String

    enum CodingKeys: String, CodingKey {
        case status
        case totalMs = "total_ms"
        case thresholdMs = "threshold_ms"
        case scope
        case note
    }

    public init(
        status: String = "not_measured",
        totalMs: Double? = nil,
        thresholdMs: Double? = nil,
        scope: String = "unknown",
        note: String = ""
    ) {
        self.status = status
        self.totalMs = totalMs
        self.thresholdMs = thresholdMs
        self.scope = scope
        self.note = note
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
    public let vtFidelity: RendererProbeVTFidelity?
    public let latencyBudget: RendererProbeLatencyBudget?

    enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case status
        case platform
        case arch
        case bridge
        case renderer
        case fidelityNotes = "fidelity_notes"
        case artifactPath = "artifact_path"
        case vtFidelity = "vt_fidelity"
        case latencyBudget = "latency_budget"
    }

    public init(
        schemaVersion: String = "beagle-warp-metal-probe-v0.1",
        status: String = "not_measured",
        platform: String = "",
        arch: String = "",
        bridgeVersion: String = BeagleWorkbenchBoundary.bridgeVersion,
        vendorCommit: String = BeagleWorkbenchBoundary.warpVendorCommit,
        reason: String? = nil,
        artifactPath: String? = nil,
        vtFidelity: RendererProbeVTFidelity? = nil,
        latencyBudget: RendererProbeLatencyBudget? = nil
    ) {
        self.schemaVersion = schemaVersion
        self.status = status
        self.platform = platform
        self.arch = arch
        self.bridgeVersion = bridgeVersion
        self.vendorCommit = vendorCommit
        self.reason = reason
        self.artifactPath = artifactPath
        self.vtFidelity = vtFidelity
        self.latencyBudget = latencyBudget
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
        self.vtFidelity = try container.decodeIfPresent(RendererProbeVTFidelity.self, forKey: .vtFidelity)
        self.latencyBudget = try container.decodeIfPresent(RendererProbeLatencyBudget.self, forKey: .latencyBudget)
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
        try container.encodeIfPresent(vtFidelity, forKey: .vtFidelity)
        try container.encodeIfPresent(latencyBudget, forKey: .latencyBudget)
    }
}

public enum WorkbenchAppleFormFactor: String, Codable, Sendable, Equatable {
    case compactPhone
    case regularPhone
    case ipadOrMac
    case vision

    public static func from(width: Double) -> WorkbenchAppleFormFactor {
        if width < 390 { return .compactPhone }
        if width < 760 { return .regularPhone }
        return .ipadOrMac
    }
}

public struct WorkbenchAppleDeviceGate: Codable, Sendable, Equatable {
    public let status: String
    public let formFactor: WorkbenchAppleFormFactor
    public let viewportWidth: Double
    public let touchTargetReady: Bool
    public let dynamicTypeReady: Bool
    public let restrictedLeakCheck: String
    public let vtFidelityStatus: String
    public let latencyStatus: String
    public let humanJudgmentScore: Int?
    public let promotionAllowed: Bool
    public let blockers: [String]

    public init(
        status: String,
        formFactor: WorkbenchAppleFormFactor,
        viewportWidth: Double,
        touchTargetReady: Bool,
        dynamicTypeReady: Bool,
        restrictedLeakCheck: String,
        vtFidelityStatus: String,
        latencyStatus: String,
        humanJudgmentScore: Int?,
        promotionAllowed: Bool,
        blockers: [String]
    ) {
        self.status = status
        self.formFactor = formFactor
        self.viewportWidth = viewportWidth
        self.touchTargetReady = touchTargetReady
        self.dynamicTypeReady = dynamicTypeReady
        self.restrictedLeakCheck = restrictedLeakCheck
        self.vtFidelityStatus = vtFidelityStatus
        self.latencyStatus = latencyStatus
        self.humanJudgmentScore = humanJudgmentScore
        self.promotionAllowed = promotionAllowed
        self.blockers = blockers
    }

    public static func evaluate(
        sample: WorkbenchBakeOffSample,
        probe: WarpMetalProbeResult? = nil,
        judgments: [RendererHumanJudgment] = [],
        viewportWidth: Double,
        dynamicTypeReady: Bool = true,
        touchTargetReady: Bool = true
    ) -> WorkbenchAppleDeviceGate {
        let formFactor = WorkbenchAppleFormFactor.from(width: viewportWidth)
        let restrictedSafe = !sample.restrictedRedacted || sample.outputPreview == "[restricted output redacted]"
        let leakCheck = restrictedSafe ? "passed:no_restricted_output" : "failed:restricted_output_visible"
        let sampleJudgments = judgments.filter { $0.sampleId == sample.id }
        let bestHumanScore = sampleJudgments.map(\.score).max()
        let vtStatus = probe?.vtFidelity?.status ?? "not_measured"
        let latencyStatus = probe?.latencyBudget?.status ?? "not_measured"

        var blockers: [String] = []
        if !restrictedSafe { blockers.append("restricted output visible") }
        if !touchTargetReady { blockers.append("touch targets below 44pt") }
        if !dynamicTypeReady { blockers.append("large Dynamic Type not verified") }
        if vtStatus != "pass" { blockers.append("VT fidelity not passed") }
        if latencyStatus != "pass" { blockers.append("latency budget not passed") }
        if bestHumanScore == nil { blockers.append("human device judgment missing") }
        if let bestHumanScore, bestHumanScore < 4 { blockers.append("human device score below 4") }

        let preflightReady = restrictedSafe && touchTargetReady && dynamicTypeReady
        let humanReady = (bestHumanScore ?? 0) >= 4
        let measuredReady = vtStatus == "pass" && latencyStatus == "pass"
        let status: String
        if preflightReady && measuredReady && humanReady {
            status = "device_pass"
        } else if preflightReady && measuredReady {
            status = "needs_human_device_pass"
        } else if preflightReady {
            status = "preflight_ready"
        } else {
            status = "blocked"
        }

        return WorkbenchAppleDeviceGate(
            status: status,
            formFactor: formFactor,
            viewportWidth: viewportWidth,
            touchTargetReady: touchTargetReady,
            dynamicTypeReady: dynamicTypeReady,
            restrictedLeakCheck: leakCheck,
            vtFidelityStatus: vtStatus,
            latencyStatus: latencyStatus,
            humanJudgmentScore: bestHumanScore,
            promotionAllowed: false,
            blockers: blockers
        )
    }
}

public struct AppleDevicePassEvidence: Codable, Sendable, Equatable {
    public let schemaVersion: String
    public let projectSlug: String
    public let sampleId: String
    public let sessionId: String
    public let blockId: String
    public let selectedCandidate: String
    public let device: [String: String]
    public let gateStatus: String
    public let viewportWidth: Double?
    public let dynamicTypeReady: Bool
    public let touchTargetReady: Bool
    public let inputToPaintMs: Double?
    public let humanScore: Int?
    public let restrictedLeakCheck: String
    public let vtFidelityStatus: String
    public let latencyStatus: String
    public let blockers: [String]
    public let notes: String
    public let promotionAllowed: Bool
    public let canonicalMemoryWritten: Bool
    public let createdAt: String

    enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case projectSlug = "project_slug"
        case sampleId = "sample_id"
        case sessionId = "session_id"
        case blockId = "block_id"
        case selectedCandidate = "selected_candidate"
        case device
        case gateStatus = "gate_status"
        case viewportWidth = "viewport_width"
        case dynamicTypeReady = "dynamic_type_ready"
        case touchTargetReady = "touch_target_ready"
        case inputToPaintMs = "input_to_paint_ms"
        case humanScore = "human_score"
        case restrictedLeakCheck = "restricted_leak_check"
        case vtFidelityStatus = "vt_fidelity_status"
        case latencyStatus = "latency_status"
        case blockers
        case notes
        case promotionAllowed = "promotion_allowed"
        case canonicalMemoryWritten = "canonical_memory_written"
        case createdAt = "created_at"
    }

    public init(
        projectSlug: String,
        sample: WorkbenchBakeOffSample,
        gate: WorkbenchAppleDeviceGate,
        selectedCandidate: WorkbenchRendererCandidate,
        inputToPaintMs: Double? = nil,
        notes: String = "",
        device: [String: String] = [:],
        createdAt: String = ISO8601DateFormatter().string(from: Date())
    ) {
        self.schemaVersion = "beagle-apple-device-pass-v0.1"
        self.projectSlug = projectSlug
        self.sampleId = sample.id
        self.sessionId = sample.sessionId
        self.blockId = sample.blockId
        self.selectedCandidate = selectedCandidate.rawValue
        self.device = device
        self.gateStatus = gate.status
        self.viewportWidth = gate.viewportWidth
        self.dynamicTypeReady = gate.dynamicTypeReady
        self.touchTargetReady = gate.touchTargetReady
        self.inputToPaintMs = inputToPaintMs
        self.humanScore = gate.humanJudgmentScore
        self.restrictedLeakCheck = gate.restrictedLeakCheck
        self.vtFidelityStatus = gate.vtFidelityStatus
        self.latencyStatus = gate.latencyStatus
        self.blockers = gate.blockers
        self.notes = notes
        self.promotionAllowed = false
        self.canonicalMemoryWritten = false
        self.createdAt = createdAt
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
