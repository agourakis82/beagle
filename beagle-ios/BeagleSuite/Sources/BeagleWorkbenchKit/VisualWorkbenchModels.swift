//
//  VisualWorkbenchModels.swift
//  BeagleWorkbenchKit
//
//  Visual-first derived models for the Beagle Workbench. These structs never
//  become canonical memory; they package existing workspace/session/block state
//  into an Apple-native agent work surface.
//

import Foundation
import BeagleCore

public enum VisualWorkArtifactKind: String, Codable, Sendable, Equatable {
    case agent
    case diff
    case test
    case deploy
    case memory
    case runtime
    case approval
    case unknown
}

public struct VisualWorkArtifact: Codable, Identifiable, Sendable, Equatable {
    public let id: String
    public let kind: VisualWorkArtifactKind
    public let title: String
    public let summary: String
    public let status: String
    public let memoryStatus: String?
    public let sourceBlockId: String?
    public let paneId: String?
    public let restrictedRedacted: Bool
    public let provenanceRefs: [String]
    public let touchedFiles: [String]
    public let evidenceBadges: [String]

    public init(
        id: String,
        kind: VisualWorkArtifactKind,
        title: String,
        summary: String,
        status: String = "observed",
        memoryStatus: String? = nil,
        sourceBlockId: String? = nil,
        paneId: String? = nil,
        restrictedRedacted: Bool = false,
        provenanceRefs: [String] = [],
        touchedFiles: [String] = [],
        evidenceBadges: [String] = []
    ) {
        self.id = id
        self.kind = kind
        self.title = title
        self.summary = summary
        self.status = status
        self.memoryStatus = memoryStatus
        self.sourceBlockId = sourceBlockId
        self.paneId = paneId
        self.restrictedRedacted = restrictedRedacted
        self.provenanceRefs = provenanceRefs
        self.touchedFiles = touchedFiles
        self.evidenceBadges = evidenceBadges
    }

    public init(block: TerminalBlock) {
        let restricted = Self.isRestricted(block.privacyClass)
        let kind = Self.kind(for: block)
        let displayCommand = restricted ? "[restricted command redacted]" : block.command
        let displayOutput = restricted ? "[restricted output redacted]" : block.outputPreview
        let fallbackTitle = displayCommand.isEmpty ? block.title : displayCommand
        let touchedFiles = restricted ? [] : Self.extractTouchedFiles(from: displayOutput)
        let summary = Self.summary(
            kind: kind,
            command: displayCommand,
            output: displayOutput,
            status: block.status,
            exitCode: block.exitCode
        )
        self.init(
            id: "artifact:\(block.id)",
            kind: kind,
            title: fallbackTitle.isEmpty ? block.kind.capitalized : fallbackTitle,
            summary: summary,
            status: block.status,
            memoryStatus: block.memoryStatus,
            sourceBlockId: block.id,
            paneId: block.paneId,
            restrictedRedacted: restricted,
            provenanceRefs: [block.blockHash, block.memoryEventId, block.auditEventId].compactMap { $0 },
            touchedFiles: touchedFiles,
            evidenceBadges: Self.evidenceBadges(
                kind: kind,
                block: block,
                touchedFiles: touchedFiles,
                restricted: restricted
            )
        )
    }

    public init(liveBlock: TerminalBlockLiveState) {
        let restricted = Self.isRestricted(liveBlock.privacyClass)
        let kind = Self.kind(
            kind: liveBlock.kind,
            title: liveBlock.title,
            command: liveBlock.command,
            tags: []
        )
        let displayCommand = restricted ? "[restricted command redacted]" : liveBlock.command
        let displayOutput = restricted ? "[restricted output redacted]" : liveBlock.outputPreview
        let fallbackTitle = displayCommand.isEmpty ? liveBlock.title : displayCommand
        let touchedFiles = restricted ? [] : Self.extractTouchedFiles(from: displayOutput)
        let summary = Self.summary(
            kind: kind,
            command: displayCommand,
            output: displayOutput,
            status: liveBlock.status,
            exitCode: liveBlock.exitCode
        )
        self.init(
            id: "artifact:\(liveBlock.id)",
            kind: kind,
            title: fallbackTitle.isEmpty ? liveBlock.kind.capitalized : fallbackTitle,
            summary: summary,
            status: liveBlock.status,
            memoryStatus: liveBlock.memoryStatus,
            sourceBlockId: liveBlock.id,
            paneId: liveBlock.paneId,
            restrictedRedacted: restricted,
            provenanceRefs: [liveBlock.memoryEventId, liveBlock.auditEventId].compactMap { $0 },
            touchedFiles: touchedFiles,
            evidenceBadges: Self.evidenceBadges(
                kind: kind,
                status: liveBlock.status,
                memoryStatus: liveBlock.memoryStatus,
                outputPreview: liveBlock.outputPreview,
                touchedFiles: touchedFiles,
                restricted: restricted,
                isLive: true
            )
        )
    }

    public static func kind(for block: TerminalBlock) -> VisualWorkArtifactKind {
        kind(kind: block.kind, title: block.title, command: block.command, tags: block.tags)
    }

    private static func kind(
        kind: String,
        title: String,
        command: String,
        tags: [String]
    ) -> VisualWorkArtifactKind {
        let haystack = [kind, title, command, tags.joined(separator: " ")]
            .joined(separator: " ")
            .lowercased()
        if haystack.contains("approval") { return .approval }
        if haystack.contains("remember") || haystack.contains("memory") { return .memory }
        if haystack.contains("git diff") || haystack.contains(" diff") || haystack.contains("patch") { return .diff }
        if haystack.contains("swift test")
            || haystack.contains("npm test")
            || haystack.contains("npm run test")
            || haystack.contains("cargo test")
            || haystack.contains("pytest")
            || haystack.contains("xcodebuild test") {
            return .test
        }
        if haystack.contains("kubectl") || haystack.contains("rollout") || haystack.contains("deploy") {
            return .deploy
        }
        if haystack.contains("codex") || haystack.contains("claude") || haystack.contains("kimi") {
            return .agent
        }
        if kind == "command" { return .runtime }
        return .unknown
    }

    public static func isRestricted(_ privacyClass: String) -> Bool {
        privacyClass == "restricted" || privacyClass == "restricted_local_only"
    }

    public static func extractTouchedFiles(from output: String) -> [String] {
        let cleaned = stripANSI(output)
        let candidates = cleaned
            .split(whereSeparator: \.isNewline)
            .compactMap { line -> String? in
                let value = line.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !value.isEmpty else { return nil }
                if value.localizedCaseInsensitiveContains("files changed")
                    || value.localizedCaseInsensitiveContains("file changed") {
                    return nil
                }
                if let pipeIndex = value.firstIndex(of: "|") {
                    let file = value[..<pipeIndex].trimmingCharacters(in: .whitespaces)
                    return file.isEmpty ? nil : file
                }
                if let arrowRange = value.range(of: " -> ") {
                    let prefix = value[..<arrowRange.lowerBound]
                    let suffix = value[arrowRange.upperBound...]
                    let joined = "\(prefix)\(suffix)".trimmingCharacters(in: .whitespaces)
                    return joined.isEmpty ? nil : joined
                }
                let first = value.split(separator: " ").first.map(String.init) ?? ""
                if first.contains("/")
                    || first.hasSuffix(".swift")
                    || first.hasSuffix(".ts")
                    || first.hasSuffix(".tsx")
                    || first.hasSuffix(".js")
                    || first.hasSuffix(".py")
                    || first.hasSuffix(".rs")
                    || first.hasSuffix(".sio")
                    || first.hasSuffix(".md") {
                    return first.trimmingCharacters(in: CharacterSet(charactersIn: ":"))
                }
                return nil
            }
        var seen = Set<String>()
        let unique = candidates.filter { file in
            guard !seen.contains(file) else { return false }
            seen.insert(file)
            return true
        }
        return Array(unique.prefix(8))
    }

    private static func evidenceBadges(
        kind: VisualWorkArtifactKind,
        block: TerminalBlock,
        touchedFiles: [String],
        restricted: Bool
    ) -> [String] {
        evidenceBadges(
            kind: kind,
            status: block.status,
            memoryStatus: block.memoryStatus,
            outputPreview: block.outputPreview,
            touchedFiles: touchedFiles,
            restricted: restricted,
            isLive: false
        )
    }

    private static func evidenceBadges(
        kind: VisualWorkArtifactKind,
        status: String,
        memoryStatus: String,
        outputPreview: String,
        touchedFiles: [String],
        restricted: Bool,
        isLive: Bool
    ) -> [String] {
        var badges = [kind.rawValue, status]
        if !memoryStatus.isEmpty {
            badges.append(memoryStatus)
        }
        if isLive {
            badges.append("live")
        }
        if !touchedFiles.isEmpty {
            badges.append("files:\(touchedFiles.count)")
        }
        let output = outputPreview.lowercased()
        if output.contains("passed") || output.contains("success") {
            badges.append("pass")
        } else if output.contains("failed") || output.contains("error") {
            badges.append("attention")
        }
        if restricted {
            badges.append("restricted redacted")
        }
        var seen = Set<String>()
        return badges.filter { badge in
            guard !badge.isEmpty, !seen.contains(badge) else { return false }
            seen.insert(badge)
            return true
        }
    }

    private static func stripANSI(_ value: String) -> String {
        value.replacingOccurrences(
            of: "\u{001B}\\[[0-9;?]*[ -/]*[@-~]",
            with: "",
            options: .regularExpression
        )
    }

    private static func summary(
        kind: VisualWorkArtifactKind,
        command: String,
        output: String,
        status: String,
        exitCode: Int?
    ) -> String {
        let exit = exitCode.map { "exit \($0)" } ?? status
        let text = output.trimmingCharacters(in: .whitespacesAndNewlines)
        if !text.isEmpty {
            return String(text.prefix(220))
        }
        if !command.isEmpty {
            switch kind {
            case .test: return "Test command observed: \(command) · \(exit)"
            case .diff: return "Diff command observed: \(command) · \(exit)"
            case .deploy: return "Platform command observed: \(command) · \(exit)"
            case .agent: return "Agent runtime observed: \(command) · \(exit)"
            default: return "Runtime command observed: \(command) · \(exit)"
            }
        }
        return "No output captured yet · \(exit)"
    }
}

public struct VisualAgentLaneSnapshot: Codable, Identifiable, Sendable, Equatable {
    public let id: String
    public let title: String
    public let role: String?
    public let kind: String
    public let providerLabel: String?
    public let status: String
    public let taskSummary: String
    public let readiness: String
    public let setupGap: String?
    public let memoryStatus: String?
    public let pendingApproval: Bool
    public let isActive: Bool
    public let isScout: Bool
    public let runtimeAvailable: Bool
    public let currentArtifact: VisualWorkArtifact?
    public let artifacts: [VisualWorkArtifact]

    public init(
        id: String,
        title: String,
        role: String? = nil,
        kind: String,
        providerLabel: String? = nil,
        status: String,
        taskSummary: String,
        readiness: String,
        setupGap: String? = nil,
        memoryStatus: String? = nil,
        pendingApproval: Bool = false,
        isActive: Bool = false,
        isScout: Bool = false,
        runtimeAvailable: Bool = false,
        currentArtifact: VisualWorkArtifact? = nil,
        artifacts: [VisualWorkArtifact] = []
    ) {
        self.id = id
        self.title = title
        self.role = role
        self.kind = kind
        self.providerLabel = providerLabel
        self.status = status
        self.taskSummary = taskSummary
        self.readiness = readiness
        self.setupGap = setupGap
        self.memoryStatus = memoryStatus
        self.pendingApproval = pendingApproval
        self.isActive = isActive
        self.isScout = isScout
        self.runtimeAvailable = runtimeAvailable
        self.currentArtifact = currentArtifact
        self.artifacts = artifacts
    }

    public init(
        lane: AgentLaneState,
        blocks: [TerminalBlock] = [],
        liveBlocks: [TerminalBlockLiveState] = []
    ) {
        let laneLiveArtifacts = liveBlocks
            .filter { block in
                guard let paneId = lane.paneId else { return false }
                return block.paneId == paneId
            }
            .map(VisualWorkArtifact.init(liveBlock:))
        let laneReplayArtifacts = blocks
            .filter { block in
                guard let paneId = lane.paneId else { return false }
                return block.paneId == paneId
            }
            .map(VisualWorkArtifact.init(block:))
            .filter { artifact in
                !laneLiveArtifacts.contains(where: { $0.sourceBlockId == artifact.sourceBlockId })
            }
        let laneArtifacts = laneLiveArtifacts + laneReplayArtifacts
        let current = laneArtifacts.first
        let readiness = lane.status == "needs_setup" ? "needs_setup" : (lane.paneId == nil ? "not_started" : "ready")
        self.init(
            id: lane.id,
            title: lane.title,
            role: lane.role,
            kind: lane.kind,
            providerLabel: lane.providerLabel,
            status: lane.status,
            taskSummary: current?.summary ?? lane.detail,
            readiness: readiness,
            setupGap: lane.status == "needs_setup" ? lane.readinessReason : nil,
            memoryStatus: lane.memoryStatus ?? current?.memoryStatus,
            pendingApproval: lane.pendingApproval,
            isActive: lane.isActive,
            isScout: lane.isScout,
            runtimeAvailable: lane.paneId != nil,
            currentArtifact: current,
            artifacts: Array(laneArtifacts.prefix(4))
        )
    }
}

public struct VisualWorkCanvasState: Codable, Sendable, Equatable {
    public let projectSlug: String
    public let sessionId: String?
    public let activeLaneId: String?
    public let headline: String
    public let primaryAction: String
    public let selectedArtifact: VisualWorkArtifact?
    public let recentArtifacts: [VisualWorkArtifact]
    public let lanes: [VisualAgentLaneSnapshot]
    public let workMemoryLine: String
    public let workMemoryStatus: String
    public let restrictedLeakCheck: String

    public init(
        projectSlug: String,
        sessionId: String? = nil,
        activeLaneId: String? = nil,
        headline: String,
        primaryAction: String,
        selectedArtifact: VisualWorkArtifact? = nil,
        recentArtifacts: [VisualWorkArtifact] = [],
        lanes: [VisualAgentLaneSnapshot] = [],
        workMemoryLine: String = "",
        workMemoryStatus: String = "",
        restrictedLeakCheck: String = "passed:no_restricted_visual_payload"
    ) {
        self.projectSlug = projectSlug
        self.sessionId = sessionId
        self.activeLaneId = activeLaneId
        self.headline = headline
        self.primaryAction = primaryAction
        self.selectedArtifact = selectedArtifact
        self.recentArtifacts = recentArtifacts
        self.lanes = lanes
        self.workMemoryLine = workMemoryLine
        self.workMemoryStatus = workMemoryStatus
        self.restrictedLeakCheck = restrictedLeakCheck
    }

    public static func synthesized(
        projectSlug: String,
        session: WorkspaceSession?,
        lanes: [AgentLaneState],
        blocks: [TerminalBlock],
        liveBlocks: [TerminalBlockLiveState] = [],
        selectedBlockId: String?,
        workMemoryLine: String,
        workMemoryStatus: String
    ) -> VisualWorkCanvasState {
        let liveArtifacts = liveBlocks.map(VisualWorkArtifact.init(liveBlock:))
        let replayArtifacts = blocks
            .map(VisualWorkArtifact.init(block:))
            .filter { artifact in
                !liveArtifacts.contains(where: { $0.sourceBlockId == artifact.sourceBlockId })
            }
        let artifacts = liveArtifacts + replayArtifacts
        let visualLanes = lanes.map {
            VisualAgentLaneSnapshot(lane: $0, blocks: blocks, liveBlocks: liveBlocks)
        }
        let selected = selectedBlockId
            .flatMap { id in artifacts.first(where: { $0.sourceBlockId == id }) }
            ?? artifacts.first
            ?? visualLanes.first(where: { $0.isActive })?.currentArtifact
        let active = visualLanes.first(where: { $0.isActive }) ?? visualLanes.first
        let headline = selected?.title
            ?? active.map { "\($0.title) is ready" }
            ?? "Visual Workbench ready"
        let primaryAction = selected?.restrictedRedacted == true
            ? "Inspect provenance without exposing restricted output"
            : selected.map { "Review \($0.kind.rawValue) artifact and decide whether to remember it" }
            ?? "Start a visual agent lane"
        let leakCheck = artifacts.contains(where: { $0.restrictedRedacted })
            ? "passed:restricted_artifacts_redacted"
            : "passed:no_restricted_visual_payload"
        return VisualWorkCanvasState(
            projectSlug: projectSlug,
            sessionId: session?.id,
            activeLaneId: active?.id,
            headline: headline,
            primaryAction: primaryAction,
            selectedArtifact: selected,
            recentArtifacts: Array(artifacts.prefix(8)),
            lanes: visualLanes,
            workMemoryLine: workMemoryLine,
            workMemoryStatus: workMemoryStatus,
            restrictedLeakCheck: leakCheck
        )
    }
}

public struct RuntimeLogPresentationState: Codable, Identifiable, Sendable, Equatable {
    public let title: String
    public let sessionId: String?
    public let paneId: String?
    public let isRuntimePrimary: Bool

    public var id: String {
        [title, sessionId, paneId, String(isRuntimePrimary)].compactMap { $0 }.joined(separator: ":")
    }

    public init(
        title: String = "Runtime Log",
        sessionId: String? = nil,
        paneId: String? = nil,
        isRuntimePrimary: Bool = false
    ) {
        self.title = title
        self.sessionId = sessionId
        self.paneId = paneId
        self.isRuntimePrimary = isRuntimePrimary
    }
}

public struct SpatialAgentDeckSnapshot: Codable, Sendable, Equatable {
    public let projectSlug: String
    public let lanes: [VisualAgentLaneSnapshot]
    public let activeTask: String
    public let memoryLine: String
    public let proofLine: String

    public init(
        projectSlug: String,
        lanes: [VisualAgentLaneSnapshot],
        activeTask: String,
        memoryLine: String = "",
        proofLine: String = "cluster-only memory provenance"
    ) {
        self.projectSlug = projectSlug
        self.lanes = lanes
        self.activeTask = activeTask
        self.memoryLine = memoryLine
        self.proofLine = proofLine
    }

    public static func fallback(projectSlug: String = "sounio", laneTitles: [String]) -> SpatialAgentDeckSnapshot {
        let lanes = laneTitles.enumerated().map { index, title in
            VisualAgentLaneSnapshot(
                id: "spatial-lane-\(index)",
                title: title,
                kind: title.lowercased().contains("shell") ? "human" : "agent",
                providerLabel: nil,
                status: "observed",
                taskSummary: "Spatial instrument linked to Beagle Workbench state.",
                readiness: "ready",
                runtimeAvailable: true
            )
        }
        return SpatialAgentDeckSnapshot(
            projectSlug: projectSlug,
            lanes: lanes,
            activeTask: "Sounio Workday parallel agent deck",
            memoryLine: "Memory and proof remain cluster-canonical."
        )
    }
}
