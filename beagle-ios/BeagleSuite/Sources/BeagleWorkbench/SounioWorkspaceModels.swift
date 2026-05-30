import Foundation
import SwiftUI
import BeagleCore

struct SounioWorkspaceSnapshot {
    var generatedAt: Date
    var source: SounioWorkspaceSource
    var status: String
    var summary: String
    var projectSlug: String
    var branch: String
    var workspaceId: String
    var sessionName: String
    var podName: String
    var nodeName: String
    var workspaceRoot: String
    var publicURL: String
    var cockpitRoute: String
    var expectedTabs: [String]
    var error: String?

    var isLive: Bool {
        source == .live && status.localizedCaseInsensitiveContains("live")
    }

    static let disconnected = SounioWorkspaceSnapshot(
        generatedAt: .now,
        source: .disconnected,
        status: "disconnected",
        summary: "Start Cockpit bridge or set BEAGLE_COCKPIT_URL",
        projectSlug: "sounio",
        branch: "unknown",
        workspaceId: "",
        sessionName: "—",
        podName: "—",
        nodeName: "—",
        workspaceRoot: "—",
        publicURL: "",
        cockpitRoute: "",
        expectedTabs: [],
        error: nil
    )

    @available(*, deprecated, message: "Use disconnected — fake ritual data was removed in reset")
    static var fallback: SounioWorkspaceSnapshot { disconnected }
}

enum SounioWorkspaceSource: String {
    case live
    case disconnected
    case stale

    var truth: TruthMode {
        switch self {
        case .live: return .observed
        case .disconnected: return .declared
        case .stale: return .stale
        }
    }
}

struct SounioWorkspaceEnvelope: Decodable {
    let project: SounioWorkspaceProject?
    let projectSlug: String?
    let generatedAt: String?
    let goWorkNow: SounioGoWorkNow?
}

struct SounioWorkspaceProject: Decodable {
    let projectSlug: String?
    let branch: String?
    let workspaceId: String?
    let zellijSession: String?
    let zellijTabs: [String]?
    let workspaceRoot: String?
    let workspacePod: String?
    let workspacePublicUrl: String?
}

struct SounioGoWorkNow: Decodable {
    let summary: String?
    let primaryEntry: String?
    let workspace: SounioWorkspaceEntry?
    let workspaceState: SounioWorkspaceState?
    let routes: SounioWorkspaceRoutes?
}

struct SounioWorkspaceEntry: Decodable {
    let pod: String?
    let tmuxSession: String?
    let root: String?
    let publicUrl: String?
}

struct SounioWorkspaceState: Decodable {
    let status: String?
    let summary: String?
    let podName: String?
    let nodeName: String?
    let browserUrl: String?
    let workspaceRoot: String?
    let ready: Bool?
}

struct SounioWorkspaceRoutes: Decodable {
    let cockpit: String?
}

extension SounioWorkspaceSnapshot {
    init(envelope: SounioWorkspaceEnvelope) {
        let empty = SounioWorkspaceSnapshot.disconnected
        let date = envelope.generatedAt.flatMap { ISO8601DateFormatter().date(from: $0) } ?? .now
        let project = envelope.project
        let go = envelope.goWorkNow
        let workspace = go?.workspace
        let state = go?.workspaceState
        let status = state?.status ?? "unknown"

        self.generatedAt = date
        self.source = .live
        self.status = status
        self.summary = state?.summary ?? go?.summary ?? "Workspace reported by Cockpit."
        self.projectSlug = envelope.projectSlug ?? project?.projectSlug ?? empty.projectSlug
        self.branch = project?.branch ?? empty.branch
        self.workspaceId = project?.workspaceId ?? empty.workspaceId
        self.sessionName = project?.zellijSession ?? workspace?.tmuxSession ?? empty.sessionName
        self.podName = state?.podName ?? workspace?.pod ?? project?.workspacePod ?? empty.podName
        self.nodeName = state?.nodeName ?? empty.nodeName
        self.workspaceRoot = state?.workspaceRoot ?? workspace?.root ?? project?.workspaceRoot ?? empty.workspaceRoot
        self.publicURL = state?.browserUrl ?? workspace?.publicUrl ?? project?.workspacePublicUrl ?? empty.publicURL
        self.cockpitRoute = go?.routes?.cockpit ?? empty.cockpitRoute
        self.expectedTabs = project?.zellijTabs ?? []
        self.error = nil
    }

    init(envelope: GoWorkNowEnvelope, slug: String) {
        let empty = SounioWorkspaceSnapshot.disconnected
        let project = envelope.project
        let go = envelope.goWorkNow
        let workspace = go?.workspace
        let state = go?.workspaceState

        self.generatedAt = envelope.generatedAt.flatMap { ISO8601DateFormatter().date(from: $0) } ?? .now
        self.source = .live
        self.status = state?.status ?? "unknown"
        self.summary = state?.summary ?? go?.summary ?? "Workspace reported by Cockpit."
        self.projectSlug = envelope.projectSlug ?? project?.projectSlug ?? slug
        self.branch = project?.branch ?? empty.branch
        self.workspaceId = project?.workspaceId ?? empty.workspaceId
        self.sessionName = project?.zellijSession ?? workspace?.tmuxSession ?? empty.sessionName
        self.podName = state?.podName ?? workspace?.pod ?? project?.workspacePod ?? empty.podName
        self.nodeName = state?.nodeName ?? empty.nodeName
        self.workspaceRoot = state?.workspaceRoot ?? workspace?.root ?? project?.workspaceRoot ?? empty.workspaceRoot
        self.publicURL = state?.browserUrl ?? workspace?.publicUrl ?? project?.workspacePublicUrl ?? empty.publicURL
        self.cockpitRoute = go?.routes?.cockpit ?? empty.cockpitRoute
        self.expectedTabs = project?.zellijTabs ?? []
        self.error = nil
    }
}
