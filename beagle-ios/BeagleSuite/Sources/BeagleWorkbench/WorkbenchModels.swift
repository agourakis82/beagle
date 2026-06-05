import Foundation
import SwiftUI
import BeagleCore

enum WorkbenchAgentKind: String, CaseIterable, Identifiable, Sendable {
    case claude
    case codex
    case kimi
    case grok
    case beagle

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .claude: return "Claude Code"
        case .codex: return "Codex"
        case .kimi: return "Kimi"
        case .grok: return "Grok"
        case .beagle: return "Beagle"
        }
    }

    var shortName: String {
        switch self {
        case .claude: return "CL"
        case .codex: return "CX"
        case .kimi: return "KM"
        case .grok: return "GK"
        case .beagle: return "BG"
        }
    }

    var color: Color {
        WorkbenchTone.agentColor(self)
    }
}

enum WorkbenchAgentStatus: String, Sendable {
    case running
    case idle
    case waiting
    case blocked
    case done

    var truth: TruthMode {
        switch self {
        case .running: return .observed
        case .idle, .waiting: return .declared
        case .blocked: return .stale
        case .done: return .remembered
        }
    }

    var label: String { rawValue }
}

enum ComposerDelivery: String, CaseIterable, Sendable {
    case auto
    case multimodel
    case zellijTab

    var label: String {
        switch self {
        case .auto: return "Auto"
        case .multimodel: return "Multimodel"
        case .zellijTab: return "Zellij tab"
        }
    }

    var hint: String {
        switch self {
        case .auto:
            return "Agent pod when running, else habitat zellij on the selected tab."
        case .multimodel:
            return "WebSocket or agent-terminal on the multimodel chat slug."
        case .zellijTab:
            return "Write into the selected workspace tab via Cockpit."
        }
    }
}

enum LeaseState: String, Sendable {
    case clear
    case owned
    case overlap
    case blocked

    var truth: TruthMode {
        switch self {
        case .clear: return .observed
        case .owned: return .remembered
        case .overlap: return .declared
        case .blocked: return .stale
        }
    }
}

enum WorkbenchMessageRole: String, Sendable {
    case operatorRole
    case assistant
    case agent
    case system
}

struct WorkbenchProject: Identifiable, Hashable, Sendable {
    let id: String
    let title: String
    let subtitle: String
    let posture: ProjectPosture
    let branch: String
    let workspaceCommand: String
}

struct WorkbenchLane: Identifiable, Hashable, Sendable {
    let id: String
    let title: String
    let purpose: String
    let leaseState: LeaseState
    let ownerAgentID: String?
    let touchedFiles: [String]
}

struct WorkbenchAgent: Identifiable, Hashable, Sendable {
    let id: String
    let kind: WorkbenchAgentKind
    let displayName: String
    let laneID: String
    var status: WorkbenchAgentStatus
    var activity: Double
    var currentTask: String
    var zellijTabName: String
}

struct WorkbenchMessage: Identifiable, Hashable, Sendable {
    let id: UUID
    let role: WorkbenchMessageRole
    let agentID: String?
    let agentKind: WorkbenchAgentKind?
    let truth: TruthMode
    let timestamp: Date
    let title: String?
    let content: String
    let isStreaming: Bool

    init(
        id: UUID = UUID(),
        role: WorkbenchMessageRole,
        agentID: String? = nil,
        agentKind: WorkbenchAgentKind? = nil,
        truth: TruthMode = .declared,
        timestamp: Date = .now,
        title: String? = nil,
        content: String,
        isStreaming: Bool = false
    ) {
        self.id = id
        self.role = role
        self.agentID = agentID
        self.agentKind = agentKind
        self.truth = truth
        self.timestamp = timestamp
        self.title = title
        self.content = content
        self.isStreaming = isStreaming
    }
}

struct WorkbenchFilePreview: Identifiable, Hashable, Sendable {
    let id: String
    let path: String
    let language: String
    let ownerAgentID: String
    let truth: TruthMode
    let body: String
}

struct WorkbenchTerminalLine: Identifiable, Hashable, Sendable {
    let id = UUID()
    let source: String
    let truth: TruthMode
    let text: String
}
