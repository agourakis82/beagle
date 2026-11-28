//
//  ProjectModels.swift
//  BeagleCore
//
//  Project identity, posture policy, executive catalog, project lane state,
//  mobile home/overview summaries, mission control, and publication scopes.
//

import Foundation

// MARK: - Project

public struct Project: Codable, Sendable, Identifiable, Hashable {
    public var id: String { projectSlug }
    public let projectSlug: String
    public let mode: String?
    public let namespace: String?
    public let branch: String?
    public let preferredPrBase: String?
    public let workspacePod: String?
    public let tmuxSession: String?
    public let workspaceRoot: String?
    public let playgroundClass: String?
    public let repoUrl: String?

    public var posture: ProjectPosture {
        ProjectPosture(from: mode)
    }

    public init(
        projectSlug: String,
        mode: String? = nil,
        namespace: String? = nil,
        branch: String? = nil,
        preferredPrBase: String? = nil,
        workspacePod: String? = nil,
        tmuxSession: String? = nil,
        workspaceRoot: String? = nil,
        playgroundClass: String? = nil,
        repoUrl: String? = nil
    ) {
        self.projectSlug = projectSlug
        self.mode = mode
        self.namespace = namespace
        self.branch = branch
        self.preferredPrBase = preferredPrBase
        self.workspacePod = workspacePod
        self.tmuxSession = tmuxSession
        self.workspaceRoot = workspaceRoot
        self.playgroundClass = playgroundClass
        self.repoUrl = repoUrl
    }
}

public struct ProjectLaneState: Sendable, Identifiable {
    public let project: Project
    public let sessions: [AgentSession]
    public let scienceJobs: [ScienceJob]
    public let laneResult: MobileLaneResultSummary?
    public let recentTrail: [String]
    public let truth: TruthMode
    public let isCurrent: Bool
    public let livingQuestion: String?
    public let carriedObjective: String?

    public var id: String { project.projectSlug }

    public init(
        project: Project,
        sessions: [AgentSession] = [],
        scienceJobs: [ScienceJob] = [],
        laneResult: MobileLaneResultSummary? = nil,
        recentTrail: [String] = [],
        truth: TruthMode = .declared,
        isCurrent: Bool = false,
        livingQuestion: String? = nil,
        carriedObjective: String? = nil
    ) {
        self.project = project
        self.sessions = sessions
        self.scienceJobs = scienceJobs
        self.laneResult = laneResult
        self.recentTrail = recentTrail.filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        self.truth = truth
        self.isCurrent = isCurrent
        self.livingQuestion = livingQuestion?.nonBlankOrNil
        self.carriedObjective = carriedObjective?.nonBlankOrNil
    }

    public var displayName: String {
        project.projectSlug
            .split(separator: "-")
            .map { $0.capitalized }
            .joined(separator: " ")
    }

    public var branchLabel: String {
        project.branch ?? project.preferredPrBase ?? "branch not declared"
    }

    public var habitatLabel: String {
        project.workspacePod ?? "habitat parked"
    }

    public var runningSessions: [AgentSession] {
        sessions.filter(\.isRunning)
    }

    public var pausedSessions: [AgentSession] {
        sessions.filter { $0.phase == .paused }
    }

    public var visibleMindCount: Int {
        sessions.count
    }

    public var activeMindCount: Int {
        runningSessions.count
    }

    public var pausedMindCount: Int {
        pausedSessions.count
    }

    public var leadSession: AgentSession? {
        runningSessions.first ?? pausedSessions.first ?? sessions.first
    }

    public var leadMindLabel: String? {
        leadSession?.presentedMindLabel
    }

    public var leadMindActivity: String? {
        leadSession?.presentedActivityLine
    }

    public var currentFocus: String? {
        carriedObjective?.nonBlankOrNil
            ?? leadMindActivity?.nonBlankOrNil
            ?? livingQuestion?.nonBlankOrNil
    }

    public var countsLine: String {
        if sessions.isEmpty {
            return "0 minds visible"
        }
        return "\(activeMindCount) live · \(pausedMindCount) paused · \(visibleMindCount) visible"
    }

    public var runningJobs: [ScienceJob] {
        scienceJobs.filter(\.isRunning)
    }

    public var completedJobs: [ScienceJob] {
        scienceJobs.filter(\.isCompleted)
    }

    public var failedJobs: [ScienceJob] {
        scienceJobs.filter(\.isFailed)
    }

    public var jobLine: String? {
        guard !scienceJobs.isEmpty else { return nil }
        var parts: [String] = []
        if !runningJobs.isEmpty { parts.append("\(runningJobs.count) live jobs") }
        if !completedJobs.isEmpty { parts.append("\(completedJobs.count) results ready") }
        if !failedJobs.isEmpty { parts.append("\(failedJobs.count) failed") }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    public var resultSignal: String? {
        if let laneResult {
            return laneResult.signalLine
        }
        if let resultPath = completedJobs.compactMap(\.resultPath).first?.nonBlankOrNil {
            return "Latest result at \(resultPath)"
        }
        if let recentTrail = recentTrail.first?.nonBlankOrNil {
            return recentTrail
        }
        return nil
    }

    public var nextRecommendedMove: String {
        if let laneResult {
            return laneResult.recommendedAction?.nonBlankOrNil
                ?? "Open what came back from this lane and decide what deserves promotion."
        }
        if let runningJob = runningJobs.first?.kind {
            return "Watch \(runningJob) complete before changing lanes."
        }
        if let completedResult = completedJobs.first?.resultPath?.nonBlankOrNil {
            return "Inspect the latest result at \(completedResult)."
        }
        if let running = leadSession, running.isRunning {
            return "Re-enter \(running.presentedMindLabel) and keep the lane moving."
        }
        if !pausedSessions.isEmpty {
            return "Recover the paused mind in this lane before starting a new thread."
        }
        if project.workspacePod != nil {
            return "Wake the first mind inside the existing habitat."
        }
        return "Wake this lane in Agents, then let Command carry the heavier cluster work."
    }

    public var postureNarrative: String {
        if let laneResult {
            return (laneResult.resultReady ?? false)
                ? "This lane has already returned work. Beagle should help you interpret it, not make you hunt for it."
                : "This lane has a result thread forming, but it has not settled into a published return yet."
        }
        if let running = leadSession, running.isRunning {
            return "\(running.presentedMindLabel) is carrying the clearest live thread in this lane right now."
        }
        if !pausedSessions.isEmpty {
            return "This lane still has preserved context waiting for you to re-enter it."
        }
        if project.workspacePod != nil {
            return "Its habitat already exists, even if no mind is actively carrying it yet."
        }
        return "This lane is known, but it still needs a living mind and a concrete next move."
    }
}

// MARK: - Posture Policy

public struct PostureDefinition: Codable, Sendable, Hashable {
    public let name: String
    public let summary: String
    public let operationalMeaning: String?
}

public struct PostureCounts: Codable, Sendable, Hashable {
    public let totalProjects: Int
    public let alwaysOn: Int
    public let warm: Int
    public let cold: Int

    public init(totalProjects: Int, alwaysOn: Int, warm: Int, cold: Int) {
        self.totalProjects = totalProjects
        self.alwaysOn = alwaysOn
        self.warm = warm
        self.cold = cold
    }

    public static let empty = PostureCounts(totalProjects: 0, alwaysOn: 0, warm: 0, cold: 0)
}

public struct PosturePolicy: Codable, Sendable {
    public let title: String?
    public let coreRule: String?
    public let postureDefinitions: [PostureDefinition]?
    public let counts: PostureCounts?
}

// MARK: - Catalog & Mobile Summaries

public struct ExecutiveCatalog: Codable, Sendable {
    public let generatedAt: String?
    public let projects: [Project]?
    public let projectPosturePolicy: PosturePolicy?
}

public struct MobileProjectOverview: Decodable, Sendable {
    public let project: Project?
    public let missionControl: MissionControl?
    public let clusterLaneTruth: ClusterLaneTruth?
    public let clusterSummary: ClusterSummary?
    public let researchOperations: ResearchOperations?
    public let inferenceRuntime: InferenceRuntime?
    public let viewerRuntime: ViewerRuntimeResponse?
    public let laneResult: MobileLaneResultSummary?

    enum CodingKeys: String, CodingKey {
        case project
        case missionControl
        case mission
        case clusterLaneTruth
        case clusterTruth
        case clusterSummary
        case cluster
        case researchOperations
        case research
        case inferenceRuntime
        case inference
        case viewerRuntime
        case viewer
        case laneResult
        case laneResultSnake = "lane_result"
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        project = try container.decodeIfPresent(Project.self, forKey: .project)
        missionControl =
            try container.decodeIfPresent(MissionControl.self, forKey: .missionControl)
            ?? container.decodeIfPresent(MissionControl.self, forKey: .mission)
        clusterLaneTruth =
            try container.decodeIfPresent(ClusterLaneTruth.self, forKey: .clusterLaneTruth)
            ?? container.decodeIfPresent(ClusterLaneTruth.self, forKey: .clusterTruth)
        clusterSummary =
            try container.decodeIfPresent(ClusterSummary.self, forKey: .clusterSummary)
            ?? container.decodeIfPresent(ClusterSummary.self, forKey: .cluster)
        researchOperations =
            try container.decodeIfPresent(ResearchOperations.self, forKey: .researchOperations)
            ?? container.decodeIfPresent(ResearchOperations.self, forKey: .research)
        inferenceRuntime =
            try container.decodeIfPresent(InferenceRuntime.self, forKey: .inferenceRuntime)
            ?? container.decodeIfPresent(InferenceRuntime.self, forKey: .inference)
        viewerRuntime =
            try container.decodeIfPresent(ViewerRuntimeResponse.self, forKey: .viewerRuntime)
            ?? container.decodeIfPresent(ViewerRuntimeResponse.self, forKey: .viewer)
        laneResult =
            try container.decodeIfPresent(MobileLaneResultSummary.self, forKey: .laneResult)
            ?? container.decodeIfPresent(MobileLaneResultSummary.self, forKey: .laneResultSnake)
    }
}

public struct MobileHomeSummary: Decodable, Sendable {
    public let activeAgentsCount: Int?
    public let activeSessionsCount: Int?
    public let clusterHealth: String?
    public let lastMemorySyncTime: String?
    public let laneResults: [MobileLaneResultSummary]?

    enum CodingKeys: String, CodingKey {
        case activeAgentsCount
        case activeAgentsCountSnake = "active_agents_count"
        case activeSessionsCount
        case activeSessionsCountSnake = "active_sessions_count"
        case clusterHealth
        case clusterHealthSnake = "cluster_health"
        case lastMemorySyncTime
        case lastMemorySyncTimeSnake = "last_memory_sync_time"
        case laneResults
        case laneResultsSnake = "lane_results"
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        activeAgentsCount =
            try container.decodeIfPresent(Int.self, forKey: .activeAgentsCount)
            ?? container.decodeIfPresent(Int.self, forKey: .activeAgentsCountSnake)
        activeSessionsCount =
            try container.decodeIfPresent(Int.self, forKey: .activeSessionsCount)
            ?? container.decodeIfPresent(Int.self, forKey: .activeSessionsCountSnake)
        clusterHealth =
            try container.decodeIfPresent(String.self, forKey: .clusterHealth)
            ?? container.decodeIfPresent(String.self, forKey: .clusterHealthSnake)
        lastMemorySyncTime =
            try container.decodeIfPresent(String.self, forKey: .lastMemorySyncTime)
            ?? container.decodeIfPresent(String.self, forKey: .lastMemorySyncTimeSnake)
        laneResults =
            try container.decodeIfPresent([MobileLaneResultSummary].self, forKey: .laneResults)
            ?? container.decodeIfPresent([MobileLaneResultSummary].self, forKey: .laneResultsSnake)
    }
}

public struct MobileLaneResultSummary: Codable, Sendable, Identifiable, Hashable {
    public var id: String { projectSlug }

    public let projectSlug: String
    public let workstreamId: String?
    public let lookupJobId: String?
    public let submittedJobId: String?
    public let publishedResultJobId: String?
    public let profileId: String?
    public let requestedRunLabel: String?
    public let publishedResultRunLabel: String?
    public let publicationState: String?
    public let finalJobState: String?
    public let manifestKey: String?
    public let resultManifestObjectKey: String?
    public let resultLookupScope: String?
    public let latestResultAt: String?
    public let resultReady: Bool?
    public let signalLine: String?
    public let recommendedAction: String?
    public let resultRoute: String?
    public let manifestRoute: String?
    public let artifactRoute: String?
    public let stdoutRoute: String?
    public let via: String?

    public var effectiveRunLabel: String? {
        publishedResultRunLabel?.nonBlankOrNil ?? requestedRunLabel?.nonBlankOrNil
    }

    public var readyForOpen: Bool {
        resultReady == true || !(manifestKey?.isEmpty ?? true) || !(resultRoute?.isEmpty ?? true)
    }

    public var displayStateLabel: String {
        publicationState?.nonBlankOrNil
            ?? finalJobState?.nonBlankOrNil
            ?? (readyForOpen ? "RETURNED" : "IN FLIGHT")
    }

    public var displayHeadline: String {
        effectiveRunLabel ?? "Published work returned"
    }

    public var displayNodeLabel: String? {
        signalLine?
            .components(separatedBy: " · ")
            .first(where: { $0.contains("-") && !$0.lowercased().contains("latest returned work") })?
            .nonBlankOrNil
    }

    public var resultAgeLabel: String? {
        guard let latestResultAt = latestResultAt?.nonBlankOrNil else { return nil }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let fallback = ISO8601DateFormatter()
        guard let date = formatter.date(from: latestResultAt) ?? fallback.date(from: latestResultAt) else {
            return nil
        }
        let relative = RelativeDateTimeFormatter()
        relative.unitsStyle = .abbreviated
        return relative.localizedString(for: date, relativeTo: .now)
    }

    public var humanSummary: String {
        if let signalLine = signalLine?.nonBlankOrNil {
            return signalLine
        }
        if readyForOpen {
            return "This lane has returned work ready to inspect."
        }
        return "A result thread exists for this lane, but it still needs interpretation."
    }

    enum CodingKeys: String, CodingKey {
        case projectSlug
        case workstreamId
        case lookupJobId
        case submittedJobId
        case publishedResultJobId
        case profileId
        case requestedRunLabel
        case publishedResultRunLabel
        case publicationState
        case finalJobState
        case manifestKey
        case resultManifestObjectKey
        case resultLookupScope
        case latestResultAt
        case resultReady
        case signalLine
        case recommendedAction
        case resultRoute
        case manifestRoute
        case artifactRoute
        case stdoutRoute
        case via
        case projectSlugSnake = "project_slug"
        case workstreamIdSnake = "workstream_id"
        case lookupJobIdSnake = "lookup_job_id"
        case submittedJobIdSnake = "submitted_job_id"
        case publishedResultJobIdSnake = "published_result_job_id"
        case profileIdSnake = "profile_id"
        case requestedRunLabelSnake = "requested_run_label"
        case publishedResultRunLabelSnake = "published_result_run_label"
        case publicationStateSnake = "publication_state"
        case finalJobStateSnake = "final_job_state"
        case manifestKeySnake = "manifest_key"
        case resultManifestObjectKeySnake = "result_manifest_object_key"
        case resultLookupScopeSnake = "result_lookup_scope"
        case latestResultAtSnake = "latest_result_at"
        case resultReadySnake = "result_ready"
        case signalLineSnake = "signal_line"
        case recommendedActionSnake = "recommended_action"
        case resultRouteSnake = "result_route"
        case manifestRouteSnake = "manifest_route"
        case artifactRouteSnake = "artifact_route"
        case stdoutRouteSnake = "stdout_route"
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        projectSlug =
            try container.decodeIfPresent(String.self, forKey: .projectSlug)
            ?? container.decodeIfPresent(String.self, forKey: .projectSlugSnake)
            ?? "unknown"
        workstreamId =
            try container.decodeIfPresent(String.self, forKey: .workstreamId)
            ?? container.decodeIfPresent(String.self, forKey: .workstreamIdSnake)
        lookupJobId =
            try container.decodeIfPresent(String.self, forKey: .lookupJobId)
            ?? container.decodeIfPresent(String.self, forKey: .lookupJobIdSnake)
        submittedJobId =
            try container.decodeIfPresent(String.self, forKey: .submittedJobId)
            ?? container.decodeIfPresent(String.self, forKey: .submittedJobIdSnake)
        publishedResultJobId =
            try container.decodeIfPresent(String.self, forKey: .publishedResultJobId)
            ?? container.decodeIfPresent(String.self, forKey: .publishedResultJobIdSnake)
        profileId =
            try container.decodeIfPresent(String.self, forKey: .profileId)
            ?? container.decodeIfPresent(String.self, forKey: .profileIdSnake)
        requestedRunLabel =
            try container.decodeIfPresent(String.self, forKey: .requestedRunLabel)
            ?? container.decodeIfPresent(String.self, forKey: .requestedRunLabelSnake)
        publishedResultRunLabel =
            try container.decodeIfPresent(String.self, forKey: .publishedResultRunLabel)
            ?? container.decodeIfPresent(String.self, forKey: .publishedResultRunLabelSnake)
        publicationState =
            try container.decodeIfPresent(String.self, forKey: .publicationState)
            ?? container.decodeIfPresent(String.self, forKey: .publicationStateSnake)
        finalJobState =
            try container.decodeIfPresent(String.self, forKey: .finalJobState)
            ?? container.decodeIfPresent(String.self, forKey: .finalJobStateSnake)
        manifestKey =
            try container.decodeIfPresent(String.self, forKey: .manifestKey)
            ?? container.decodeIfPresent(String.self, forKey: .manifestKeySnake)
        resultManifestObjectKey =
            try container.decodeIfPresent(String.self, forKey: .resultManifestObjectKey)
            ?? container.decodeIfPresent(String.self, forKey: .resultManifestObjectKeySnake)
        resultLookupScope =
            try container.decodeIfPresent(String.self, forKey: .resultLookupScope)
            ?? container.decodeIfPresent(String.self, forKey: .resultLookupScopeSnake)
        latestResultAt =
            try container.decodeIfPresent(String.self, forKey: .latestResultAt)
            ?? container.decodeIfPresent(String.self, forKey: .latestResultAtSnake)
        resultReady =
            try container.decodeIfPresent(Bool.self, forKey: .resultReady)
            ?? container.decodeIfPresent(Bool.self, forKey: .resultReadySnake)
        signalLine =
            try container.decodeIfPresent(String.self, forKey: .signalLine)
            ?? container.decodeIfPresent(String.self, forKey: .signalLineSnake)
        recommendedAction =
            try container.decodeIfPresent(String.self, forKey: .recommendedAction)
            ?? container.decodeIfPresent(String.self, forKey: .recommendedActionSnake)
        resultRoute =
            try container.decodeIfPresent(String.self, forKey: .resultRoute)
            ?? container.decodeIfPresent(String.self, forKey: .resultRouteSnake)
        manifestRoute =
            try container.decodeIfPresent(String.self, forKey: .manifestRoute)
            ?? container.decodeIfPresent(String.self, forKey: .manifestRouteSnake)
        artifactRoute =
            try container.decodeIfPresent(String.self, forKey: .artifactRoute)
            ?? container.decodeIfPresent(String.self, forKey: .artifactRouteSnake)
        stdoutRoute =
            try container.decodeIfPresent(String.self, forKey: .stdoutRoute)
            ?? container.decodeIfPresent(String.self, forKey: .stdoutRouteSnake)
        via = try container.decodeIfPresent(String.self, forKey: .via)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(projectSlug, forKey: .projectSlug)
        try container.encodeIfPresent(workstreamId, forKey: .workstreamId)
        try container.encodeIfPresent(lookupJobId, forKey: .lookupJobId)
        try container.encodeIfPresent(submittedJobId, forKey: .submittedJobId)
        try container.encodeIfPresent(publishedResultJobId, forKey: .publishedResultJobId)
        try container.encodeIfPresent(profileId, forKey: .profileId)
        try container.encodeIfPresent(requestedRunLabel, forKey: .requestedRunLabel)
        try container.encodeIfPresent(publishedResultRunLabel, forKey: .publishedResultRunLabel)
        try container.encodeIfPresent(publicationState, forKey: .publicationState)
        try container.encodeIfPresent(finalJobState, forKey: .finalJobState)
        try container.encodeIfPresent(manifestKey, forKey: .manifestKey)
        try container.encodeIfPresent(resultManifestObjectKey, forKey: .resultManifestObjectKey)
        try container.encodeIfPresent(resultLookupScope, forKey: .resultLookupScope)
        try container.encodeIfPresent(latestResultAt, forKey: .latestResultAt)
        try container.encodeIfPresent(resultReady, forKey: .resultReady)
        try container.encodeIfPresent(signalLine, forKey: .signalLine)
        try container.encodeIfPresent(recommendedAction, forKey: .recommendedAction)
        try container.encodeIfPresent(resultRoute, forKey: .resultRoute)
        try container.encodeIfPresent(manifestRoute, forKey: .manifestRoute)
        try container.encodeIfPresent(artifactRoute, forKey: .artifactRoute)
        try container.encodeIfPresent(stdoutRoute, forKey: .stdoutRoute)
        try container.encodeIfPresent(via, forKey: .via)
    }
}

// MARK: - Mission Control

public struct MissionControl: Codable, Sendable {
    public let project: Project?
    public let packetCount: Int?
    public let generatedAt: String?
}

// MARK: - Go Work Now

public struct GoWorkNow: Codable, Sendable {
    public let project: Project?
    public let actions: [GoWorkNowAction]?
    public let generatedAt: String?
}

public struct GoWorkNowAction: Codable, Sendable {
    public let id: String?
    public let label: String?
    public let description: String?
    public let kind: String?
    public let ready: Bool?
}

// MARK: - Project Classification

public enum ProjectFamily: String, Codable, Sendable {
    case language
    case hsn
    case experimental
    case platform

    public static func fromProjectSlug(_ slug: String) -> ProjectFamily {
        switch slug.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "sounio":
            return .language
        case "hyperbolic-semantic-networks":
            return .hsn
        default:
            return .experimental
        }
    }
}

public enum PublicationScope: String, Codable, Sendable {
    case `public`
    case internalOnly = "internal"
    case conference
    case draft

    public static func forProjectFamily(_ family: ProjectFamily) -> PublicationScope {
        switch family {
        case .language:
            return .public
        case .hsn:
            return .conference
        case .experimental, .platform:
            return .internalOnly
        }
    }
}
