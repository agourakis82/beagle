//
//  Models.swift
//  BeagleCore
//
//  Domain models matching the cockpit server API responses.
//  All Sendable for Swift 6 strict concurrency.
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
        self.livingQuestion = livingQuestion?.nilIfBlank
        self.carriedObjective = carriedObjective?.nilIfBlank
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
        carriedObjective?.nilIfBlank
            ?? leadMindActivity?.nilIfBlank
            ?? livingQuestion?.nilIfBlank
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
        if let resultPath = completedJobs.compactMap(\.resultPath).first?.nilIfBlank {
            return "Latest result at \(resultPath)"
        }
        if let recentTrail = recentTrail.first?.nilIfBlank {
            return recentTrail
        }
        return nil
    }

    public var nextRecommendedMove: String {
        if let laneResult {
            return laneResult.recommendedAction?.nilIfBlank
                ?? "Open what came back from this lane and decide what deserves promotion."
        }
        if let runningJob = runningJobs.first?.kind {
            return "Watch \(runningJob) complete before changing lanes."
        }
        if let completedResult = completedJobs.first?.resultPath?.nilIfBlank {
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

public extension AgentSession {
    var presentedMindLabel: String {
        if let kind, !kind.isEmpty {
            return kind
                .replacingOccurrences(of: "-", with: " ")
                .capitalized
        }
        if let name, !name.isEmpty {
            return name
        }
        return "Agent"
    }

    var presentedActivityLine: String {
        if let summary = activity?.summary?.nilIfBlank {
            return summary
        }
        if let excerpt = activity?.excerpt?.nilIfBlank {
            return excerpt
        }
        if let action, !action.isEmpty {
            return action
        }
        switch phase {
        case .running:
            return "\(presentedMindLabel) is live in the habitat."
        case .paused:
            return "\(presentedMindLabel) is paused but recoverable."
        case .pending:
            return "\(presentedMindLabel) is waiting for readiness."
        }
    }
}

private extension String {
    var nilIfBlank: String? {
        trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : self
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

// MARK: - Catalog

public struct ExecutiveCatalog: Codable, Sendable {
    public let generatedAt: String?
    public let projects: [Project]?
    public let projectPosturePolicy: PosturePolicy?
}

public struct MobileMeta: Decodable, Sendable {
    public let truthMode: String?
    public let generatedAt: String?
    public let requestId: String?

    enum CodingKeys: String, CodingKey {
        case truthMode
        case truthModeSnake = "truth_mode"
        case generatedAt
        case generatedAtSnake = "generated_at"
        case requestId
        case requestIdSnake = "request_id"
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        truthMode =
            try container.decodeIfPresent(String.self, forKey: .truthMode)
            ?? container.decodeIfPresent(String.self, forKey: .truthModeSnake)
        generatedAt =
            try container.decodeIfPresent(String.self, forKey: .generatedAt)
            ?? container.decodeIfPresent(String.self, forKey: .generatedAtSnake)
        requestId =
            try container.decodeIfPresent(String.self, forKey: .requestId)
            ?? container.decodeIfPresent(String.self, forKey: .requestIdSnake)
    }
}

public struct MobileEnvelopeError: Decodable, Sendable {
    public let message: String?
    public let reason: String?
    public let code: String?

    public init(from decoder: Decoder) throws {
        if let singleValue = try? decoder.singleValueContainer(),
           let stringValue = try? singleValue.decode(String.self)
        {
            message = stringValue
            reason = nil
            code = nil
            return
        }

        let container = try decoder.container(keyedBy: CodingKeys.self)
        message =
            try container.decodeIfPresent(String.self, forKey: .message)
            ?? container.decodeIfPresent(String.self, forKey: .error)
        reason = try container.decodeIfPresent(String.self, forKey: .reason)
        code = try container.decodeIfPresent(String.self, forKey: .code)
    }

    enum CodingKeys: String, CodingKey {
        case message
        case error
        case reason
        case code
    }
}

public struct MobileEnvelope<T: Decodable & Sendable>: Decodable, Sendable {
    public let ok: Bool?
    public let data: T?
    public let error: MobileEnvelopeError?
    public let meta: MobileMeta?
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
        publishedResultRunLabel?.nilIfBlank ?? requestedRunLabel?.nilIfBlank
    }

    public var readyForOpen: Bool {
        resultReady == true || !(manifestKey?.isEmpty ?? true) || !(resultRoute?.isEmpty ?? true)
    }

    public var displayStateLabel: String {
        publicationState?.nilIfBlank
            ?? finalJobState?.nilIfBlank
            ?? (readyForOpen ? "RETURNED" : "IN FLIGHT")
    }

    public var displayHeadline: String {
        effectiveRunLabel ?? "Published work returned"
    }

    public var displayNodeLabel: String? {
        signalLine?
            .components(separatedBy: " · ")
            .first(where: { $0.contains("-") && !$0.lowercased().contains("latest returned work") })?
            .nilIfBlank
    }

    public var resultAgeLabel: String? {
        guard let latestResultAt = latestResultAt?.nilIfBlank else { return nil }
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
        if let signalLine = signalLine?.nilIfBlank {
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

public struct IdeaSaveResponse: Decodable, Sendable {
    public let nodeId: String?
    public let syncState: IdeaSyncState?
    public let projectFamily: String?
    public let publicationScope: String?

    enum CodingKeys: String, CodingKey {
        case nodeId
        case nodeIdSnake = "node_id"
        case syncState
        case syncStateSnake = "sync_state"
        case projectFamily
        case publicationScope
        case projectFamilySnake = "project_family"
        case publicationScopeSnake = "publication_scope"
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        nodeId =
            try container.decodeIfPresent(String.self, forKey: .nodeId)
            ?? container.decodeIfPresent(String.self, forKey: .nodeIdSnake)
        syncState =
            try container.decodeIfPresent(IdeaSyncState.self, forKey: .syncState)
            ?? container.decodeIfPresent(IdeaSyncState.self, forKey: .syncStateSnake)
        projectFamily =
            try container.decodeIfPresent(String.self, forKey: .projectFamily)
            ?? container.decodeIfPresent(String.self, forKey: .projectFamilySnake)
        publicationScope =
            try container.decodeIfPresent(String.self, forKey: .publicationScope)
            ?? container.decodeIfPresent(String.self, forKey: .publicationScopeSnake)
    }
}

public struct DelegationResponse: Decodable, Sendable {
    public let agentKind: String?
    public let sessionId: String?
    public let podName: String?
    public let resultingState: String?
    public let projectFamily: String?
    public let publicationScope: String?

    enum CodingKeys: String, CodingKey {
        case agentKind
        case sessionId
        case podName
        case resultingState
        case projectFamily
        case publicationScope
        case agentKindSnake = "agent_kind"
        case sessionIdSnake = "session_id"
        case podNameSnake = "pod_name"
        case resultingStateSnake = "resulting_state"
        case projectFamilySnake = "project_family"
        case publicationScopeSnake = "publication_scope"
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        agentKind =
            try container.decodeIfPresent(String.self, forKey: .agentKind)
            ?? container.decodeIfPresent(String.self, forKey: .agentKindSnake)
        sessionId =
            try container.decodeIfPresent(String.self, forKey: .sessionId)
            ?? container.decodeIfPresent(String.self, forKey: .sessionIdSnake)
        podName =
            try container.decodeIfPresent(String.self, forKey: .podName)
            ?? container.decodeIfPresent(String.self, forKey: .podNameSnake)
        resultingState =
            try container.decodeIfPresent(String.self, forKey: .resultingState)
            ?? container.decodeIfPresent(String.self, forKey: .resultingStateSnake)
        projectFamily =
            try container.decodeIfPresent(String.self, forKey: .projectFamily)
            ?? container.decodeIfPresent(String.self, forKey: .projectFamilySnake)
        publicationScope =
            try container.decodeIfPresent(String.self, forKey: .publicationScope)
            ?? container.decodeIfPresent(String.self, forKey: .publicationScopeSnake)
    }
}

// MARK: - Mission Control

public struct MissionControl: Codable, Sendable {
    public let project: Project?
    public let packetCount: Int?
    public let generatedAt: String?
}

// MARK: - Inference Fabric

public struct InferenceModel: Codable, Sendable, Hashable, Identifiable {
    public var id: String { "\(provider ?? "")/\(idField ?? "unknown")" }
    public let idField: String?
    public let provider: String?
    public let family: String?

    enum CodingKeys: String, CodingKey {
        case idField = "id"
        case provider, family
    }
}

public struct InferenceComponent: Codable, Sendable {
    public let status: String?
    public let reachable: Bool?
}

public struct InferenceRuntime: Codable, Sendable {
    public let status: String?
    public let configured: Bool?
    public let reachable: Bool?
    public let truthMode: String?
    public let engine: InferenceComponent?
    public let controlPlane: InferenceComponent?
    public let models: [InferenceModel]?
    public let endpoint: String?

    public var displayTruthMode: TruthMode {
        TruthMode(rawValue: truthMode ?? "") ?? .declared
    }
}

public struct InferenceRuntimeResponse: Codable, Sendable {
    public let runtime: InferenceRuntime?
}

// MARK: - Cluster Truth

public struct ClusterNode: Codable, Sendable, Hashable, Identifiable {
    public let stableId: String
    public var id: String { hostname ?? name ?? stableId }
    public let name: String?
    public let hostname: String?
    public let role: String?
    public let healthy: Bool?

    enum CodingKeys: String, CodingKey {
        case name, hostname, role, healthy
    }

    public init(name: String?, hostname: String?, role: String?, healthy: Bool?) {
        self.stableId = UUID().uuidString
        self.name = name
        self.hostname = hostname
        self.role = role
        self.healthy = healthy
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.stableId = UUID().uuidString
        self.name = try container.decodeIfPresent(String.self, forKey: .name)
        self.hostname = try container.decodeIfPresent(String.self, forKey: .hostname)
        self.role = try container.decodeIfPresent(String.self, forKey: .role)
        self.healthy = try container.decodeIfPresent(Bool.self, forKey: .healthy)
    }

    public static func == (lhs: ClusterNode, rhs: ClusterNode) -> Bool {
        lhs.name == rhs.name && lhs.hostname == rhs.hostname && lhs.role == rhs.role && lhs.healthy == rhs.healthy
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(name)
        hasher.combine(hostname)
        hasher.combine(role)
        hasher.combine(healthy)
    }
}

public struct ClusterLaneTruth: Codable, Sendable {
    public let project: Project?
    public let generatedAt: String?
}

// MARK: - Research Operations

public struct ResearchCampaign: Codable, Sendable {
    public let runId: String?
    public let jobId: String?
    public let status: String?
    public let nodelist: String?
    public let lastSubmitUnixtime: Double?

    enum CodingKeys: String, CodingKey {
        case runId = "run_id"
        case jobId = "job_id"
        case status, nodelist
        case lastSubmitUnixtime = "last_submit_unixtime"
    }
}

public struct ResearchOperations: Codable, Sendable {
    public let project: Project?
    public let generatedAt: String?
}

// MARK: - Viewer

public struct ViewerRenderer: Codable, Sendable {
    public let status: String?
    public let runtime: ViewerRendererRuntime?
}

public struct ViewerRendererRuntime: Codable, Sendable {
    public let api: String?
    public let backend: String?
}

public struct ViewerRuntimeResponse: Codable, Sendable {
    public let renderer: ViewerRenderer?
}

// MARK: - Agent Sessions

public struct AgentPod: Codable, Sendable {
    public let name: String?
    public let phase: String?
    public let ready: Bool?
}

public struct AgentSessionActivity: Codable, Sendable {
    public let summary: String?
    public let source: String?
    public let updatedAt: String?
    public let author: String?
    public let excerpt: String?

    enum CodingKeys: String, CodingKey {
        case summary
        case source
        case updatedAt
        case updatedAtSnake = "updated_at"
        case author
        case excerpt
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        summary = try container.decodeIfPresent(String.self, forKey: .summary)
        source = try container.decodeIfPresent(String.self, forKey: .source)
        updatedAt =
            try container.decodeIfPresent(String.self, forKey: .updatedAt)
            ?? container.decodeIfPresent(String.self, forKey: .updatedAtSnake)
        author = try container.decodeIfPresent(String.self, forKey: .author)
        excerpt = try container.decodeIfPresent(String.self, forKey: .excerpt)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(summary, forKey: .summary)
        try container.encodeIfPresent(source, forKey: .source)
        try container.encodeIfPresent(updatedAt, forKey: .updatedAt)
        try container.encodeIfPresent(author, forKey: .author)
        try container.encodeIfPresent(excerpt, forKey: .excerpt)
    }
}

public struct AgentSession: Codable, Sendable {
    public let kind: String?
    public let name: String?
    public let replicas: Int?
    public let readyReplicas: Int?
    public let createdAt: String?
    public let pods: [AgentPod]?
    public let status: String?
    public let truthMode: String?
    public let action: String?
    public let activity: AgentSessionActivity?

    public init(
        kind: String?,
        name: String?,
        replicas: Int?,
        readyReplicas: Int?,
        createdAt: String?,
        pods: [AgentPod]?,
        status: String?,
        truthMode: String?,
        action: String?,
        activity: AgentSessionActivity? = nil
    ) {
        self.kind = kind
        self.name = name
        self.replicas = replicas
        self.readyReplicas = readyReplicas
        self.createdAt = createdAt
        self.pods = pods
        self.status = status
        self.truthMode = truthMode
        self.action = action
        self.activity = activity
    }

    public var isRunning: Bool { (readyReplicas ?? 0) > 0 }
    public var podName: String? { pods?.first?.name }
    public var phase: AgentSessionPhase {
        if isRunning { return .running }
        if replicas == 0 { return .paused }
        return .pending
    }
}

public enum AgentSessionPhase: String, Sendable {
    case pending
    case running
    case paused
}

public struct AgentSessionListResponse: Codable, Sendable {
    public let projectSlug: String?
    public let sessions: [AgentSession]?
    public let generatedAt: String?
    public let truthMode: String?
}

public struct AgentSessionDetailResponse: Codable, Sendable {
    public let projectSlug: String?
    public let session: AgentSession?
    public let generatedAt: String?
}

public struct AgentSessionActionResponse: Codable, Sendable {
    public let projectSlug: String?
    public let action: String?
    public let session: AgentSession?
    public let generatedAt: String?
}

// MARK: - Action Response

public struct ActionResponse: Codable, Sendable {
    public let ok: Bool?
    public let actionId: String?
    public let output: String?
    public let truthMode: String?
}

// MARK: - Cluster Summary

public struct ClusterSummary: Codable, Sendable {
    public let nodes: [ClusterNode]?
    public let project: Project?
    public let generatedAt: String?
    public let truthMode: String?
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

// MARK: - Live Activity Attributes

#if os(iOS)
import ActivityKit

public struct AgentSessionAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable, Sendable {
        public var status: String
        public var tokensUsed: Int
        public var lastOutputSnippet: String

        public init(status: String, tokensUsed: Int, lastOutputSnippet: String) {
            self.status = status
            self.tokensUsed = tokensUsed
            self.lastOutputSnippet = lastOutputSnippet
        }
    }

    public var agentKind: String
    public var projectSlug: String
    public var sessionId: String

    public init(agentKind: String, projectSlug: String, sessionId: String) {
        self.agentKind = agentKind
        self.projectSlug = projectSlug
        self.sessionId = sessionId
    }
}

public struct ResearchRunAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable, Sendable {
        public var stepCurrent: Int
        public var stepTotal: Int
        public var etaSeconds: Int

        public init(stepCurrent: Int, stepTotal: Int, etaSeconds: Int) {
            self.stepCurrent = stepCurrent
            self.stepTotal = stepTotal
            self.etaSeconds = etaSeconds
        }
    }

    public var runId: String
    public var campaignName: String
    public var projectSlug: String

    public init(runId: String, campaignName: String, projectSlug: String) {
        self.runId = runId
        self.campaignName = campaignName
        self.projectSlug = projectSlug
    }
}

public struct CognitiveActivityAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable, Sendable {
        public var readiness: Double?
        public var intensity: String
        public var hrvMs: Double?
        public var agentCount: Int
        public var activeJobCount: Int
        public var lastThoughtSnippet: String?

        public init(
            readiness: Double? = nil,
            intensity: String = "normal",
            hrvMs: Double? = nil,
            agentCount: Int = 0,
            activeJobCount: Int = 0,
            lastThoughtSnippet: String? = nil
        ) {
            self.readiness = readiness
            self.intensity = intensity
            self.hrvMs = hrvMs
            self.agentCount = agentCount
            self.activeJobCount = activeJobCount
            self.lastThoughtSnippet = lastThoughtSnippet
        }

        public var readinessPercent: Int {
            guard let r = readiness else { return 0 }
            return Int((r * 100).rounded())
        }

        public var intensityLabel: String {
            switch intensity {
            case "minimal":   return "Minimal"
            case "calm":      return "Calm"
            case "normal":    return "Normal"
            case "engaged":   return "Engaged"
            case "challenge": return "Challenge"
            default:          return intensity.capitalized
            }
        }

        public var lockScreenLine: String {
            var parts: [String] = []
            parts.append(intensityLabel)
            if let readiness {
                parts.append("\(Int((readiness * 100).rounded()))%")
            }
            if agentCount > 0 {
                parts.append("\(agentCount) agent\(agentCount == 1 ? "" : "s")")
            }
            return parts.joined(separator: " · ")
        }
    }

    public init() {}
}
#endif

// MARK: - WebSocket / Terminal

public struct WorkspaceListResponse: Codable, Sendable {
    public let workspaces: [WorkspaceSummary]
    public let truthMode: String?

    public init(workspaces: [WorkspaceSummary] = [], truthMode: String? = nil) {
        self.workspaces = workspaces
        self.truthMode = truthMode
    }
}

public struct WorkspaceSummary: Codable, Identifiable, Sendable {
    public let slug: String
    public let title: String
    public let namespace: String
    public let workspaceRoot: String
    public let workspacePod: String
    public let workspaceContainer: String
    public let branch: String
    public let truthMode: String

    public var id: String { slug }

    public init(
        slug: String,
        title: String,
        namespace: String = "beagle",
        workspaceRoot: String = "",
        workspacePod: String = "",
        workspaceContainer: String = "",
        branch: String = "",
        truthMode: String = "declared"
    ) {
        self.slug = slug
        self.title = title
        self.namespace = namespace
        self.workspaceRoot = workspaceRoot
        self.workspacePod = workspacePod
        self.workspaceContainer = workspaceContainer
        self.branch = branch
        self.truthMode = truthMode
    }
}

public struct WorkspaceSessionListResponse: Codable, Sendable {
    public let projectSlug: String
    public let authority: WorkbenchAuthorityStatus?
    public let sessions: [WorkspaceSession]

    public init(projectSlug: String, sessions: [WorkspaceSession], authority: WorkbenchAuthorityStatus? = nil) {
        self.projectSlug = projectSlug
        self.authority = authority
        self.sessions = sessions
    }
}

public struct WorkspaceSessionResponse: Codable, Sendable {
    public let session: WorkspaceSession

    public init(session: WorkspaceSession) {
        self.session = session
    }
}

public struct WorkspacePaneResponse: Codable, Sendable {
    public let pane: TerminalPane
    public let session: WorkspaceSession

    public init(pane: TerminalPane, session: WorkspaceSession) {
        self.pane = pane
        self.session = session
    }
}

public struct WorkspaceBlocksResponse: Codable, Sendable {
    public let projectSlug: String
    public let sessionId: String
    public let authority: WorkbenchAuthorityStatus?
    public let blocks: [TerminalBlock]

    public init(projectSlug: String, sessionId: String, blocks: [TerminalBlock], authority: WorkbenchAuthorityStatus? = nil) {
        self.projectSlug = projectSlug
        self.sessionId = sessionId
        self.authority = authority
        self.blocks = blocks
    }
}

public struct WorkspaceRememberBlockResponse: Codable, Sendable {
    public let blockId: String
    public let memory: WorkbenchMemoryStatus

    public init(blockId: String, memory: WorkbenchMemoryStatus) {
        self.blockId = blockId
        self.memory = memory
    }
}

public struct AgentProviderSlot: Codable, Identifiable, Sendable, Equatable {
    public let id: String
    public let title: String
    public let modelId: String
    public let baseUrl: String?
    public let command: String?
    public let runtime: String
    public let costTier: String
    public let latencyTier: String
    public let privacyTier: String
    public let licenseNote: String?
    public let enabled: Bool

    public init(
        id: String,
        title: String,
        modelId: String,
        baseUrl: String? = nil,
        command: String? = nil,
        runtime: String = "",
        costTier: String = "",
        latencyTier: String = "",
        privacyTier: String = "",
        licenseNote: String? = nil,
        enabled: Bool = true
    ) {
        self.id = id
        self.title = title
        self.modelId = modelId
        self.baseUrl = baseUrl
        self.command = command
        self.runtime = runtime
        self.costTier = costTier
        self.latencyTier = latencyTier
        self.privacyTier = privacyTier
        self.licenseNote = licenseNote
        self.enabled = enabled
    }
}

/// Masked acknowledgement returned by the cockpit after writing a lane's
/// provider configuration server-side. The raw API key is NEVER echoed; only
/// `apiKeyConfigured` reflects whether a secret is now stored on the workspace.
public struct AgentProviderConfigResponse: Codable, Sendable, Equatable {
    public let projectSlug: String?
    public let role: String?
    public let slot: String?
    public let status: String?
    public let readiness: AgentReadinessState?
    public let providerConfig: Masked?

    /// The masked view of the stored slot — safe to render in the UI.
    public struct Masked: Codable, Sendable, Equatable {
        public let slot: String?
        public let baseUrl: String?
        public let model: String?
        public let apiKeyConfigured: Bool?
        public let updatedAt: String?

        public init(
            slot: String? = nil,
            baseUrl: String? = nil,
            model: String? = nil,
            apiKeyConfigured: Bool? = nil,
            updatedAt: String? = nil
        ) {
            self.slot = slot
            self.baseUrl = baseUrl
            self.model = model
            self.apiKeyConfigured = apiKeyConfigured
            self.updatedAt = updatedAt
        }
    }

    public init(
        projectSlug: String? = nil,
        role: String? = nil,
        slot: String? = nil,
        status: String? = nil,
        readiness: AgentReadinessState? = nil,
        providerConfig: Masked? = nil
    ) {
        self.projectSlug = projectSlug
        self.role = role
        self.slot = slot
        self.status = status
        self.readiness = readiness
        self.providerConfig = providerConfig
    }
}

public struct AgentReadinessState: Codable, Sendable, Equatable {
    public let status: String
    public let reason: String?
    public let command: String?
    public let env: String?
    public let model: String?

    public init(
        status: String = "unknown",
        reason: String? = nil,
        command: String? = nil,
        env: String? = nil,
        model: String? = nil
    ) {
        self.status = status
        self.reason = reason
        self.command = command
        self.env = env
        self.model = model
    }
}

public struct AgentRole: Codable, Identifiable, Sendable, Equatable {
    public let role: String
    public let kind: String
    public let title: String
    public let subtitle: String?
    public let roleSummary: String?
    public let visible: Bool
    public let arousalRole: String?
    public let icon: String?
    public let accent: String?
    public let launchCommand: String?
    public let memoryPolicy: String?
    public let riskLevel: String?
    public let providerSlots: [AgentProviderSlot]
    public let readiness: AgentReadinessState?
    public let enabled: Bool

    public var id: String { role }

    public init(
        role: String,
        kind: String,
        title: String,
        subtitle: String? = nil,
        roleSummary: String? = nil,
        visible: Bool = true,
        arousalRole: String? = nil,
        icon: String? = nil,
        accent: String? = nil,
        launchCommand: String? = nil,
        memoryPolicy: String? = nil,
        riskLevel: String? = nil,
        providerSlots: [AgentProviderSlot] = [],
        readiness: AgentReadinessState? = nil,
        enabled: Bool = true
    ) {
        self.role = role
        self.kind = kind
        self.title = title
        self.subtitle = subtitle
        self.roleSummary = roleSummary
        self.visible = visible
        self.arousalRole = arousalRole
        self.icon = icon
        self.accent = accent
        self.launchCommand = launchCommand
        self.memoryPolicy = memoryPolicy
        self.riskLevel = riskLevel
        self.providerSlots = providerSlots
        self.readiness = readiness
        self.enabled = enabled
    }
}

public struct AgentRegistryResponse: Codable, Sendable {
    public let projectSlug: String
    public let registryVersion: String?
    public let arousalModel: String?
    public let authority: WorkbenchAuthorityStatus?
    public let roles: [AgentRole]
    public let visibleRoles: [String]
    public let scoutRoles: [String]
    public let updatedAt: String?
    public let error: String?

    public init(
        projectSlug: String,
        registryVersion: String? = nil,
        arousalModel: String? = nil,
        authority: WorkbenchAuthorityStatus? = nil,
        roles: [AgentRole] = [],
        visibleRoles: [String] = [],
        scoutRoles: [String] = [],
        updatedAt: String? = nil,
        error: String? = nil
    ) {
        self.projectSlug = projectSlug
        self.registryVersion = registryVersion
        self.arousalModel = arousalModel
        self.authority = authority
        self.roles = roles
        self.visibleRoles = visibleRoles
        self.scoutRoles = scoutRoles
        self.updatedAt = updatedAt
        self.error = error
    }
}

public struct AgentRouteSlot: Codable, Sendable, Equatable {
    public let role: String
    public let kind: String
    public let title: String
    public let providerSlots: [AgentProviderSlot]

    public init(role: String, kind: String, title: String, providerSlots: [AgentProviderSlot] = []) {
        self.role = role
        self.kind = kind
        self.title = title
        self.providerSlots = providerSlots
    }
}

public struct AgentRouteDecision: Codable, Identifiable, Sendable, Equatable {
    public let id: String
    public let createdAt: String?
    public let projectSlug: String?
    public let task: String?
    public let chosenRole: String
    public let chosenSlot: AgentRouteSlot
    public let fallbackSlots: [AgentRouteSlot]
    public let reason: String
    public let arousalMode: String
    public let privacyConstraints: [String]
    public let expectedArtifacts: [String]
    public let registryVersion: String?

    public init(
        id: String = UUID().uuidString,
        createdAt: String? = nil,
        projectSlug: String? = nil,
        task: String? = nil,
        chosenRole: String,
        chosenSlot: AgentRouteSlot,
        fallbackSlots: [AgentRouteSlot] = [],
        reason: String = "",
        arousalMode: String = "phasic_focus",
        privacyConstraints: [String] = [],
        expectedArtifacts: [String] = [],
        registryVersion: String? = nil
    ) {
        self.id = id
        self.createdAt = createdAt
        self.projectSlug = projectSlug
        self.task = task
        self.chosenRole = chosenRole
        self.chosenSlot = chosenSlot
        self.fallbackSlots = fallbackSlots
        self.reason = reason
        self.arousalMode = arousalMode
        self.privacyConstraints = privacyConstraints
        self.expectedArtifacts = expectedArtifacts
        self.registryVersion = registryVersion
    }
}

public struct AgentRouteResponse: Codable, Sendable {
    public let projectSlug: String
    public let decision: AgentRouteDecision
    public let authority: WorkbenchAuthorityStatus?

    public init(projectSlug: String, decision: AgentRouteDecision, authority: WorkbenchAuthorityStatus? = nil) {
        self.projectSlug = projectSlug
        self.decision = decision
        self.authority = authority
    }
}

public struct AgentStartResponse: Codable, Sendable {
    public let projectSlug: String
    public let pane: TerminalPane
    public let session: WorkspaceSession
    public let decision: AgentRouteDecision?
    public let readiness: AgentReadinessState?
    public let startCommand: String?
    public let providerSlot: AgentProviderSlot?

    public init(
        projectSlug: String,
        pane: TerminalPane,
        session: WorkspaceSession,
        decision: AgentRouteDecision? = nil,
        readiness: AgentReadinessState? = nil,
        startCommand: String? = nil,
        providerSlot: AgentProviderSlot? = nil
    ) {
        self.projectSlug = projectSlug
        self.pane = pane
        self.session = session
        self.decision = decision
        self.readiness = readiness
        self.startCommand = startCommand
        self.providerSlot = providerSlot
    }
}

public struct WorkspaceSession: Codable, Identifiable, Sendable {
    public let id: String
    public let projectSlug: String
    public let title: String
    public let status: String
    public let layout: NotebookTerminalLayout
    public let createdAt: String
    public let updatedAt: String
    public let lastAttachedAt: String
    public let lastMemoryStatus: WorkbenchMemoryStatus?
    public let panes: [TerminalPane]
    public let sourceModel: String?
    public let bridgeVersion: String?
    public let sessionHash: String?
    public let rendererHint: String?
    public let authorityStatus: WorkbenchAuthorityStatus?

    public init(
        id: String,
        projectSlug: String,
        title: String,
        status: String = "active",
        layout: NotebookTerminalLayout = .notebook,
        createdAt: String = "",
        updatedAt: String = "",
        lastAttachedAt: String = "",
        lastMemoryStatus: WorkbenchMemoryStatus? = nil,
        panes: [TerminalPane] = [],
        sourceModel: String? = nil,
        bridgeVersion: String? = nil,
        sessionHash: String? = nil,
        rendererHint: String? = nil,
        authorityStatus: WorkbenchAuthorityStatus? = nil
    ) {
        self.id = id
        self.projectSlug = projectSlug
        self.title = title
        self.status = status
        self.layout = layout
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.lastAttachedAt = lastAttachedAt
        self.lastMemoryStatus = lastMemoryStatus
        self.panes = panes
        self.sourceModel = sourceModel
        self.bridgeVersion = bridgeVersion
        self.sessionHash = sessionHash
        self.rendererHint = rendererHint
        self.authorityStatus = authorityStatus
    }
}

public struct TerminalPane: Codable, Identifiable, Sendable {
    public let id: String
    public let title: String
    public let kind: String
    public let status: String
    public let createdAt: String
    public let lastAttachedAt: String
    public let cwd: String
    public let reconnectState: String?
    public let agentRole: String?
    public let providerSlot: String?
    public let modelId: String?
    public let routeReason: String?
    public let arousalMode: String?
    public let agent: AgentRunState?

    public init(
        id: String,
        title: String,
        kind: String = "human",
        status: String = "idle",
        createdAt: String = "",
        lastAttachedAt: String = "",
        cwd: String = "",
        reconnectState: String? = nil,
        agentRole: String? = nil,
        providerSlot: String? = nil,
        modelId: String? = nil,
        routeReason: String? = nil,
        arousalMode: String? = nil,
        agent: AgentRunState? = nil
    ) {
        self.id = id
        self.title = title
        self.kind = kind
        self.status = status
        self.createdAt = createdAt
        self.lastAttachedAt = lastAttachedAt
        self.cwd = cwd
        self.reconnectState = reconnectState
        self.agentRole = agentRole
        self.providerSlot = providerSlot
        self.modelId = modelId
        self.routeReason = routeReason
        self.arousalMode = arousalMode
        self.agent = agent
    }
}

public struct TerminalBlock: Codable, Identifiable, Sendable {
    public let id: String
    public let sessionId: String
    public let paneId: String
    public let kind: String
    public let title: String
    public let command: String
    public let outputPreview: String
    public let outputByteCount: Int
    public let startedAt: String
    public let finishedAt: String
    public let durationMs: Int?
    public let exitCode: Int?
    public let status: String
    public let privacyClass: String
    public let memoryStatus: String
    public let memoryEventId: String?
    public let auditEventId: String?
    public let memoryError: String?
    public let tags: [String]
    public let sourceModel: String?
    public let bridgeVersion: String?
    public let blockHash: String?
    public let sessionHash: String?
    public let rendererHint: String?

    public init(
        id: String,
        sessionId: String,
        paneId: String,
        kind: String = "command",
        title: String,
        command: String = "",
        outputPreview: String = "",
        outputByteCount: Int = 0,
        startedAt: String = "",
        finishedAt: String = "",
        durationMs: Int? = nil,
        exitCode: Int? = nil,
        status: String = "running",
        privacyClass: String = "sensitive",
        memoryStatus: String = "not_saved",
        memoryEventId: String? = nil,
        auditEventId: String? = nil,
        memoryError: String? = nil,
        tags: [String] = [],
        sourceModel: String? = nil,
        bridgeVersion: String? = nil,
        blockHash: String? = nil,
        sessionHash: String? = nil,
        rendererHint: String? = nil
    ) {
        self.id = id
        self.sessionId = sessionId
        self.paneId = paneId
        self.kind = kind
        self.title = title
        self.command = command
        self.outputPreview = outputPreview
        self.outputByteCount = outputByteCount
        self.startedAt = startedAt
        self.finishedAt = finishedAt
        self.durationMs = durationMs
        self.exitCode = exitCode
        self.status = status
        self.privacyClass = privacyClass
        self.memoryStatus = memoryStatus
        self.memoryEventId = memoryEventId
        self.auditEventId = auditEventId
        self.memoryError = memoryError
        self.tags = tags
        self.sourceModel = sourceModel
        self.bridgeVersion = bridgeVersion
        self.blockHash = blockHash
        self.sessionHash = sessionHash
        self.rendererHint = rendererHint
    }
}

public struct AgentRunState: Codable, Sendable {
    public let kind: String
    public let state: String
    public let summary: String
    public let branch: String
    public let commit: String
    public let changedFiles: [String]
    public let role: String?
    public let providerSlot: String?
    public let modelId: String?
    public let arousalMode: String?

    public init(
        kind: String,
        state: String = "idle",
        summary: String = "",
        branch: String = "",
        commit: String = "",
        changedFiles: [String] = [],
        role: String? = nil,
        providerSlot: String? = nil,
        modelId: String? = nil,
        arousalMode: String? = nil
    ) {
        self.kind = kind
        self.state = state
        self.summary = summary
        self.branch = branch
        self.commit = commit
        self.changedFiles = changedFiles
        self.role = role
        self.providerSlot = providerSlot
        self.modelId = modelId
        self.arousalMode = arousalMode
    }
}

public struct ApprovalRequest: Codable, Identifiable, Sendable {
    public let id: String
    public let title: String
    public let detail: String
    public let requestedBy: String
    public let status: String
    public let createdAt: String

    public init(
        id: String,
        title: String,
        detail: String = "",
        requestedBy: String = "",
        status: String = "pending",
        createdAt: String = ""
    ) {
        self.id = id
        self.title = title
        self.detail = detail
        self.requestedBy = requestedBy
        self.status = status
        self.createdAt = createdAt
    }
}

public struct WorkbenchMemoryStatus: Codable, Sendable {
    public let blockId: String?
    public let status: String
    public let privacyClass: String?
    public let reason: String?
    public let error: String?
    public let memoryEventId: String?
    public let auditEventId: String?
    public let updatedAt: String?
    public let sourceModel: String?
    public let bridgeVersion: String?

    public init(
        blockId: String? = nil,
        status: String,
        privacyClass: String? = nil,
        reason: String? = nil,
        error: String? = nil,
        memoryEventId: String? = nil,
        auditEventId: String? = nil,
        updatedAt: String? = nil,
        sourceModel: String? = nil,
        bridgeVersion: String? = nil
    ) {
        self.blockId = blockId
        self.status = status
        self.privacyClass = privacyClass
        self.reason = reason
        self.error = error
        self.memoryEventId = memoryEventId
        self.auditEventId = auditEventId
        self.updatedAt = updatedAt
        self.sourceModel = sourceModel
        self.bridgeVersion = bridgeVersion
    }
}

public struct WorkbenchAuthorityStatus: Codable, Sendable {
    public let authority: String
    public let fallback: String?
    public let persistence: String?
    public let workbenchDir: String?
    public let workspaceRoot: String?
    public let protocolName: String?
    public let bridgeVersion: String?
    public let supervisor: PtySupervisorStatus?
    public let updatedAt: String?

    enum CodingKeys: String, CodingKey {
        case authority
        case fallback
        case persistence
        case workbenchDir
        case workspaceRoot
        case protocolName = "protocol"
        case bridgeVersion
        case supervisor
        case updatedAt
    }

    public init(
        authority: String = "cockpit-local",
        fallback: String? = nil,
        persistence: String? = nil,
        workbenchDir: String? = nil,
        workspaceRoot: String? = nil,
        protocolName: String? = nil,
        bridgeVersion: String? = nil,
        supervisor: PtySupervisorStatus? = nil,
        updatedAt: String? = nil
    ) {
        self.authority = authority
        self.fallback = fallback
        self.persistence = persistence
        self.workbenchDir = workbenchDir
        self.workspaceRoot = workspaceRoot
        self.protocolName = protocolName
        self.bridgeVersion = bridgeVersion
        self.supervisor = supervisor
        self.updatedAt = updatedAt
    }
}

public struct PtySupervisorStatus: Codable, Sendable {
    public let status: String
    public let runtime: String?
    public let panes: Int?
    public let url: String?
    public let error: String?
    public let updatedAt: String?

    public init(
        status: String = "unknown",
        runtime: String? = nil,
        panes: Int? = nil,
        url: String? = nil,
        error: String? = nil,
        updatedAt: String? = nil
    ) {
        self.status = status
        self.runtime = runtime
        self.panes = panes
        self.url = url
        self.error = error
        self.updatedAt = updatedAt
    }
}

public struct WarpBridgeStatus: Codable, Sendable {
    public let sourceModel: String
    public let bridgeVersion: String
    public let rendererHint: String
    public let bridgeHash: String?
    public let vendorCommit: String?

    public init(
        sourceModel: String = "beagle",
        bridgeVersion: String = "beagle-warp-bridge-v0.2",
        rendererHint: String = "beagle-terminal-v1",
        bridgeHash: String? = nil,
        vendorCommit: String? = nil
    ) {
        self.sourceModel = sourceModel
        self.bridgeVersion = bridgeVersion
        self.rendererHint = rendererHint
        self.bridgeHash = bridgeHash
        self.vendorCommit = vendorCommit
    }
}

public enum NotebookTerminalLayout: String, Codable, Sendable {
    case notebook
    case raw
    case split
}

public struct WorkbenchLiveEvent: Codable, Identifiable, Sendable {
    public let type: String
    public let sessionId: String?
    public let paneId: String?
    public let blockId: String?
    public let at: String?
    public let data: String?
    public let status: String?
    public let state: String?
    public let command: String?
    public let title: String?
    public let kind: String?
    public let privacyClass: String?
    public let memoryEventId: String?
    public let auditEventId: String?
    public let exitCode: Int?
    public let durationMs: Int?
    public let trigger: String?
    public let reason: String?
    public let error: String?
    public let authority: String?
    public let sourceModel: String?
    public let bridgeVersion: String?
    public let reconnectState: String?
    public let tags: [String]?
    public let blockHash: String?
    public let sessionHash: String?
    public let rendererHint: String?
    public let startedAt: String?
    public let finishedAt: String?
    public let event: String?
    public let agentRole: String?
    public let providerSlot: String?
    public let modelId: String?
    public let arousalMode: String?
    public let registryVersion: String?

    public var id: String {
        [
            type,
            sessionId ?? "session",
            paneId ?? "pane",
            blockId ?? "block",
            at ?? UUID().uuidString
        ].joined(separator: ":")
    }

    enum CodingKeys: String, CodingKey {
        case type
        case sessionId
        case paneId
        case blockId
        case at
        case data
        case status
        case state
        case command
        case title
        case kind
        case privacyClass
        case memoryEventId
        case auditEventId
        case exitCode
        case durationMs
        case trigger
        case reason
        case error
        case authority
        case sourceModel
        case bridgeVersion
        case reconnectState
        case tags
        case blockHash
        case sessionHash
        case rendererHint
        case startedAt
        case finishedAt
        case event
        case agentRole
        case providerSlot
        case modelId
        case arousalMode
        case registryVersion
    }

    public init(
        type: String,
        sessionId: String? = nil,
        paneId: String? = nil,
        blockId: String? = nil,
        at: String? = nil,
        data: String? = nil,
        status: String? = nil,
        state: String? = nil,
        command: String? = nil,
        title: String? = nil,
        kind: String? = nil,
        privacyClass: String? = nil,
        memoryEventId: String? = nil,
        auditEventId: String? = nil,
        exitCode: Int? = nil,
        durationMs: Int? = nil,
        trigger: String? = nil,
        reason: String? = nil,
        error: String? = nil,
        authority: String? = nil,
        sourceModel: String? = nil,
        bridgeVersion: String? = nil,
        reconnectState: String? = nil,
        tags: [String]? = nil,
        blockHash: String? = nil,
        sessionHash: String? = nil,
        rendererHint: String? = nil,
        startedAt: String? = nil,
        finishedAt: String? = nil,
        event: String? = nil,
        agentRole: String? = nil,
        providerSlot: String? = nil,
        modelId: String? = nil,
        arousalMode: String? = nil,
        registryVersion: String? = nil
    ) {
        self.type = type
        self.sessionId = sessionId
        self.paneId = paneId
        self.blockId = blockId
        self.at = at
        self.data = data
        self.status = status
        self.state = state
        self.command = command
        self.title = title
        self.kind = kind
        self.privacyClass = privacyClass
        self.memoryEventId = memoryEventId
        self.auditEventId = auditEventId
        self.exitCode = exitCode
        self.durationMs = durationMs
        self.trigger = trigger
        self.reason = reason
        self.error = error
        self.authority = authority
        self.sourceModel = sourceModel
        self.bridgeVersion = bridgeVersion
        self.reconnectState = reconnectState
        self.tags = tags
        self.blockHash = blockHash
        self.sessionHash = sessionHash
        self.rendererHint = rendererHint
        self.startedAt = startedAt
        self.finishedAt = finishedAt
        self.event = event
        self.agentRole = agentRole
        self.providerSlot = providerSlot
        self.modelId = modelId
        self.arousalMode = arousalMode
        self.registryVersion = registryVersion
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.type = try container.decode(String.self, forKey: .type)
        self.sessionId = try container.decodeIfPresent(String.self, forKey: .sessionId)
        self.paneId = try container.decodeIfPresent(String.self, forKey: .paneId)
        self.blockId = try container.decodeIfPresent(String.self, forKey: .blockId)
        self.at = try container.decodeIfPresent(String.self, forKey: .at)
        self.data = try? container.decode(String.self, forKey: .data)
        self.status = try container.decodeIfPresent(String.self, forKey: .status)
        self.state = try container.decodeIfPresent(String.self, forKey: .state)
        self.command = try container.decodeIfPresent(String.self, forKey: .command)
        self.title = try container.decodeIfPresent(String.self, forKey: .title)
        self.kind = try container.decodeIfPresent(String.self, forKey: .kind)
        self.privacyClass = try container.decodeIfPresent(String.self, forKey: .privacyClass)
        self.memoryEventId = try container.decodeIfPresent(String.self, forKey: .memoryEventId)
        self.auditEventId = try container.decodeIfPresent(String.self, forKey: .auditEventId)
        self.exitCode = try container.decodeIfPresent(Int.self, forKey: .exitCode)
        self.durationMs = try container.decodeIfPresent(Int.self, forKey: .durationMs)
        self.trigger = try container.decodeIfPresent(String.self, forKey: .trigger)
        self.reason = try container.decodeIfPresent(String.self, forKey: .reason)
        self.error = try container.decodeIfPresent(String.self, forKey: .error)
        self.authority = try container.decodeIfPresent(String.self, forKey: .authority)
        self.sourceModel = try container.decodeIfPresent(String.self, forKey: .sourceModel)
        self.bridgeVersion = try container.decodeIfPresent(String.self, forKey: .bridgeVersion)
        self.reconnectState = try container.decodeIfPresent(String.self, forKey: .reconnectState)
        self.tags = try container.decodeIfPresent([String].self, forKey: .tags)
        self.blockHash = try container.decodeIfPresent(String.self, forKey: .blockHash)
        self.sessionHash = try container.decodeIfPresent(String.self, forKey: .sessionHash)
        self.rendererHint = try container.decodeIfPresent(String.self, forKey: .rendererHint)
        self.startedAt = try container.decodeIfPresent(String.self, forKey: .startedAt)
        self.finishedAt = try container.decodeIfPresent(String.self, forKey: .finishedAt)
        self.event = try container.decodeIfPresent(String.self, forKey: .event)
        self.agentRole = try container.decodeIfPresent(String.self, forKey: .agentRole)
        self.providerSlot = try container.decodeIfPresent(String.self, forKey: .providerSlot)
        self.modelId = try container.decodeIfPresent(String.self, forKey: .modelId)
        self.arousalMode = try container.decodeIfPresent(String.self, forKey: .arousalMode)
        self.registryVersion = try container.decodeIfPresent(String.self, forKey: .registryVersion)
    }
}

public struct TerminalBlockLiveState: Identifiable, Sendable, Equatable {
    public let id: String
    public var sessionId: String?
    public var paneId: String?
    public var kind: String
    public var title: String
    public var command: String
    public var outputPreview: String
    public var status: String
    public var privacyClass: String
    public var memoryStatus: String
    public var memoryEventId: String?
    public var auditEventId: String?
    public var exitCode: Int?
    public var durationMs: Int?
    public var updatedAt: String?

    public init(
        id: String,
        sessionId: String? = nil,
        paneId: String? = nil,
        kind: String = "command",
        title: String = "Command",
        command: String = "",
        outputPreview: String = "",
        status: String = "running",
        privacyClass: String = "sensitive",
        memoryStatus: String = "not_saved",
        memoryEventId: String? = nil,
        auditEventId: String? = nil,
        exitCode: Int? = nil,
        durationMs: Int? = nil,
        updatedAt: String? = nil
    ) {
        self.id = id
        self.sessionId = sessionId
        self.paneId = paneId
        self.kind = kind
        self.title = title
        self.command = command
        self.outputPreview = outputPreview
        self.status = status
        self.privacyClass = privacyClass
        self.memoryStatus = memoryStatus
        self.memoryEventId = memoryEventId
        self.auditEventId = auditEventId
        self.exitCode = exitCode
        self.durationMs = durationMs
        self.updatedAt = updatedAt
    }
}

public struct AgentLaneState: Identifiable, Sendable, Equatable {
    public let id: String
    public let title: String
    public let kind: String
    public let paneId: String?
    public let status: String
    public let detail: String
    public let lastBlockTitle: String?
    public let lastBlockStatus: String?
    public let memoryStatus: String?
    public let pendingApproval: Bool
    public let reconnectState: String?
    public let isActive: Bool
    public let role: String?
    public let subtitle: String?
    public let providerLabel: String?
    public let arousalMode: String?
    public let isScout: Bool
    public let readinessReason: String?

    public init(
        id: String,
        title: String,
        kind: String,
        paneId: String? = nil,
        status: String = "idle",
        detail: String = "",
        lastBlockTitle: String? = nil,
        lastBlockStatus: String? = nil,
        memoryStatus: String? = nil,
        pendingApproval: Bool = false,
        reconnectState: String? = nil,
        isActive: Bool = false,
        role: String? = nil,
        subtitle: String? = nil,
        providerLabel: String? = nil,
        arousalMode: String? = nil,
        isScout: Bool = false,
        readinessReason: String? = nil
    ) {
        self.id = id
        self.title = title
        self.kind = kind
        self.paneId = paneId
        self.status = status
        self.detail = detail
        self.lastBlockTitle = lastBlockTitle
        self.lastBlockStatus = lastBlockStatus
        self.memoryStatus = memoryStatus
        self.pendingApproval = pendingApproval
        self.reconnectState = reconnectState
        self.isActive = isActive
        self.role = role
        self.subtitle = subtitle
        self.providerLabel = providerLabel
        self.arousalMode = arousalMode
        self.isScout = isScout
        self.readinessReason = readinessReason
    }
}

public struct AgentConsoleSnapshot: Sendable, Equatable {
    public let projectSlug: String
    public let sessionId: String?
    public let lanes: [AgentLaneState]
    public let activeLaneKind: String?
    public let authority: String?
    public let updatedAt: String?

    public init(
        projectSlug: String,
        sessionId: String? = nil,
        lanes: [AgentLaneState] = [],
        activeLaneKind: String? = nil,
        authority: String? = nil,
        updatedAt: String? = nil
    ) {
        self.projectSlug = projectSlug
        self.sessionId = sessionId
        self.lanes = lanes
        self.activeLaneKind = activeLaneKind
        self.authority = authority
        self.updatedAt = updatedAt
    }
}

public struct WorkbenchActionDockState: Sendable, Equatable {
    public let canSendInput: Bool
    public let canInterrupt: Bool
    public let canApprove: Bool
    public let canRemember: Bool
    public let activeLaneKind: String?

    public init(
        canSendInput: Bool,
        canInterrupt: Bool,
        canApprove: Bool,
        canRemember: Bool,
        activeLaneKind: String? = nil
    ) {
        self.canSendInput = canSendInput
        self.canInterrupt = canInterrupt
        self.canApprove = canApprove
        self.canRemember = canRemember
        self.activeLaneKind = activeLaneKind
    }
}

public enum TerminalMessage: Sendable {
    case data(String)
    case stderr(String)
    case ready(projectSlug: String)
    case workbenchEvent(WorkbenchLiveEvent)
    case exit(code: Int, detail: String? = nil)
}

public enum WebSocketState: Sendable, Equatable {
    case disconnected
    case connecting
    case connected(source: String)
    case reconnecting(attempt: Int)
    case failed(String)
}

public struct TerminalLine: Identifiable, Sendable {
    public let id: UInt64
    public let text: String
    public let timestamp: Date
    public let isStderr: Bool

    public init(id: UInt64, text: String, timestamp: Date = .now, isStderr: Bool = false) {
        self.id = id
        self.text = text
        self.timestamp = timestamp
        self.isStderr = isStderr
    }
}

// MARK: - Science Jobs

public struct ScienceJob: Codable, Sendable, Identifiable {
    private let stableId: String = UUID().uuidString
    public var id: String { jobId ?? stableId }
    public let jobId: String?
    public let kind: String?
    public let status: String?
    public let createdAt: String?
    public let updatedAt: String?
    public let error: String?
    public let resultPath: String?

    enum CodingKeys: String, CodingKey {
        case jobId = "job_id"
        case kind, status
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case error
        case resultPath = "result_path"
    }

    public var isRunning: Bool { status == "running" || status == "pending" }
    public var isCompleted: Bool { status == "completed" || status == "done" }
    public var isFailed: Bool { status == "failed" || status == "error" }
}

// MARK: - Triad (ATHENA / HERMES / ARGOS / Judge)

public struct TriadResult: Codable, Sendable {
    public let athena: TriadAgentOpinion?
    public let hermes: TriadAgentOpinion?
    public let argos: TriadAgentOpinion?
    public let judge: TriadAgentOpinion?
    public let consensus: String?
    public let scores: TriadScores?
}

public struct TriadAgentOpinion: Codable, Sendable {
    public let agent: String?
    public let opinion: String?
    public let confidence: Double?
    public let citations: [String]?
}

public struct TriadScores: Codable, Sendable {
    public let athena: Double?
    public let hermes: Double?
    public let argos: Double?
    public let judge: Double?
}

// MARK: - Round Table (exotic model debate)

public struct RoundTableResult: Codable, Sendable {
    public let voices: [RoundTableVoice]?
    public let interference: RoundTableInterference?
    public let pciScore: Double?
    public let synthesis: String?

    enum CodingKeys: String, CodingKey {
        case voices, interference, synthesis
        case pciScore = "pci_score"
    }
}

public struct RoundTableVoice: Codable, Sendable, Identifiable {
    public var id: String { name }
    public let name: String
    public let perspective: String?
    public let content: String
}

public struct RoundTableInterference: Codable, Sendable {
    public let constructive: [String]?
    public let destructive: [String]?
    public let emergentInsights: [String]?
}

// MARK: - Thought Capture

public struct ThoughtCapture: Codable, Sendable, Identifiable {
    private let stableId: String
    public var id: String { nodeId ?? stableId }
    public let nodeId: String?
    public let refinedText: String?
    public let rawText: String?
    public let source: String?
    public let createdAt: String?
    public let syncedToServer: Bool?
    public let syncState: IdeaSyncState?

    /// English translation if the original thought was in Portuguese.
    public var translatedText: String?
    /// Detected language code (BCP-47), e.g. "pt", "en", "es".
    public var originalLanguage: String?

    /// Whether this thought has a bilingual translation available.
    public var isBilingual: Bool { translatedText != nil }

    /// The best text for international display: translation if available, otherwise refined/raw.
    public var internationalText: String? {
        translatedText ?? refinedText ?? rawText
    }

    enum CodingKeys: String, CodingKey {
        case nodeId = "node_id"
        case refinedText = "refined_text"
        case rawText = "raw_text"
        case source
        case createdAt = "created_at"
        case syncedToServer = "synced_to_server"
        case syncState
        case syncStateSnake = "sync_state"
        case translatedText = "translated_text"
        case originalLanguage = "original_language"
    }

    public var residency: ThoughtResidency {
        if effectiveSyncState.isClusterResident { return .clusterMemory }
        return .deviceOnly
    }

    public var effectiveSyncState: IdeaSyncState {
        if let syncState { return syncState }
        if syncedToServer == true { return .synced }
        return .localOnly
    }

    public init(
        nodeId: String?,
        refinedText: String?,
        rawText: String?,
        source: String?,
        createdAt: String?,
        syncedToServer: Bool?,
        syncState: IdeaSyncState?,
        translatedText: String? = nil,
        originalLanguage: String? = nil
    ) {
        self.stableId = UUID().uuidString
        self.nodeId = nodeId
        self.refinedText = refinedText
        self.rawText = rawText
        self.source = source
        self.createdAt = createdAt
        self.syncedToServer = syncedToServer
        self.syncState = syncState
        self.translatedText = translatedText
        self.originalLanguage = originalLanguage
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.stableId = UUID().uuidString
        nodeId = try container.decodeIfPresent(String.self, forKey: .nodeId)
        refinedText = try container.decodeIfPresent(String.self, forKey: .refinedText)
        rawText = try container.decodeIfPresent(String.self, forKey: .rawText)
        source = try container.decodeIfPresent(String.self, forKey: .source)
        createdAt = try container.decodeIfPresent(String.self, forKey: .createdAt)
        syncedToServer = try container.decodeIfPresent(Bool.self, forKey: .syncedToServer)
        syncState =
            try container.decodeIfPresent(IdeaSyncState.self, forKey: .syncState)
            ?? container.decodeIfPresent(IdeaSyncState.self, forKey: .syncStateSnake)
        translatedText = try container.decodeIfPresent(String.self, forKey: .translatedText)
        originalLanguage = try container.decodeIfPresent(String.self, forKey: .originalLanguage)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(nodeId, forKey: .nodeId)
        try container.encodeIfPresent(refinedText, forKey: .refinedText)
        try container.encodeIfPresent(rawText, forKey: .rawText)
        try container.encodeIfPresent(source, forKey: .source)
        try container.encodeIfPresent(createdAt, forKey: .createdAt)
        try container.encodeIfPresent(syncedToServer, forKey: .syncedToServer)
        try container.encodeIfPresent(syncState, forKey: .syncState)
        try container.encodeIfPresent(translatedText, forKey: .translatedText)
        try container.encodeIfPresent(originalLanguage, forKey: .originalLanguage)
    }
}

public enum ThoughtResidency: String, Codable, Sendable {
    case deviceOnly
    case clusterMemory

    public var label: String {
        switch self {
        case .deviceOnly:
            return "Device only"
        case .clusterMemory:
            return "Cluster memory"
        }
    }
}

public enum IdeaSyncState: String, Codable, Sendable {
    case localOnly = "local_only"
    case queued
    case synced
    case delegated

    public var label: String {
        switch self {
        case .localOnly:
            return "Device only"
        case .queued:
            return "Queued"
        case .synced:
            return "Cluster memory"
        case .delegated:
            return "Delegated"
        }
    }

    public var systemImage: String {
        switch self {
        case .localOnly:
            return "iphone"
        case .queued:
            return "clock.arrow.circlepath"
        case .synced:
            return "server.rack"
        case .delegated:
            return "bolt.horizontal.circle"
        }
    }

    public var isClusterResident: Bool {
        switch self {
        case .localOnly, .queued:
            return false
        case .synced, .delegated:
            return true
        }
    }
}

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

public enum DiscussionProfile: String, Codable, Sendable, CaseIterable, Identifiable {
    case cluster
    case qwen3b
    case yi6b
    case grok
    case kimi
    case claudeCode = "claude-code"
    case codex

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .cluster:
            return "Cluster"
        case .qwen3b:
            return "Qwen"
        case .yi6b:
            return "Yi"
        case .grok:
            return "Grok"
        case .kimi:
            return "Kimi"
        case .claudeCode:
            return "Claude Code"
        case .codex:
            return "Codex"
        }
    }

    public var subtitle: String {
        switch self {
        case .cluster:
            return "Default route"
        case .qwen3b:
            return "Daily / Cheap"
        case .yi6b:
            return "Bilingual / Creative"
        case .grok:
            return "Fast / xAI"
        case .kimi:
            return "Moonshot / OpenRouter"
        case .claudeCode:
            return "Max / Pro subscription"
        case .codex:
            return "ChatGPT Pro subscription"
        }
    }

    public var iconName: String {
        switch self {
        case .cluster:
            return "server.rack"
        case .qwen3b:
            return "bolt.horizontal.circle"
        case .yi6b:
            return "globe.asia.australia"
        case .grok:
            return "sparkles.rectangle.stack"
        case .kimi:
            return "moon.stars"
        case .claudeCode:
            return "person.crop.circle.badge.sparkles"
        case .codex:
            return "terminal"
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

// MARK: - HRV Response

public struct HRVResponse: Codable, Sendable {
    public let status: String?
    public let speedMultiplier: Double?

    enum CodingKeys: String, CodingKey {
        case status
        case speedMultiplier = "speed_multiplier"
    }
}

// MARK: - Cognitive State (aggregated)

public struct CognitiveState: Codable, Sendable {
    public let hrv: CognitiveHRV?
    public let recentDrafts: [CognitiveDraft]?
    public let triadLatest: CognitiveTriad?
    public let agentSessions: [AgentSession]?
    public let recentVoidJourneys: [VoidJourney]?
    public let recentFractalTrees: [FractalTree]?
    public let recentPhiMeasurements: [PhiMeasurement]?

    enum CodingKeys: String, CodingKey {
        case hrv
        case recentDrafts = "recent_drafts"
        case triadLatest = "triad_latest"
        case agentSessions = "agent_sessions"
        case recentVoidJourneys = "recent_void_journeys"
        case recentFractalTrees = "recent_fractal_trees"
        case recentPhiMeasurements = "recent_phi_measurements"
    }
}

// MARK: - Novelty Endpoints (Void, Fractal, Phi)

public struct VoidJourney: Codable, Sendable, Identifiable {
    private let stableId: String = UUID().uuidString
    public var id: String { journeyId ?? stableId }
    public let journeyId: String?
    public let status: String?
    public let maxDepthReached: Double?
    public let durationMs: Int?
    public let insights: [String]?
    public let truthMode: String?

    enum CodingKeys: String, CodingKey {
        case journeyId = "journey_id"
        case status
        case maxDepthReached = "max_depth_reached"
        case durationMs = "duration_ms"
        case insights
        case truthMode = "truth_mode"
    }
}

public struct FractalTree: Codable, Sendable, Identifiable {
    private let stableId: String = UUID().uuidString
    public var id: String { rootId ?? stableId }
    public let rootId: String?
    public let rootPrompt: String?
    public let maxDepth: Int?
    public let branching: Int?
    public let nodeCount: Int?
    public let generatedAt: String?
    public let durationMs: Int?
    public let truthMode: String?

    enum CodingKeys: String, CodingKey {
        case rootId = "root_id"
        case rootPrompt = "root_prompt"
        case maxDepth = "max_depth"
        case branching
        case nodeCount = "node_count"
        case generatedAt = "generated_at"
        case durationMs = "duration_ms"
        case truthMode = "truth_mode"
    }
}

public struct PhiMeasurement: Codable, Sendable, Identifiable {
    private let stableId: String = UUID().uuidString
    public var id: String { "\(measuredAt ?? stableId)" }
    public let querySnippet: String?
    public let phi: Double?
    public let substrateSize: Int?
    public let mipPartition: [[String]]?
    public let awarenessLevel: String?
    public let routerTier: String?
    public let measuredAt: String?
    public let durationMs: Int?
    public let truthMode: String?

    enum CodingKeys: String, CodingKey {
        case querySnippet = "query_snippet"
        case phi
        case substrateSize = "substrate_size"
        case mipPartition = "mip_partition"
        case awarenessLevel = "awareness_level"
        case routerTier = "router_tier"
        case measuredAt = "measured_at"
        case durationMs = "duration_ms"
        case truthMode = "truth_mode"
    }
}

public struct CognitiveHRV: Codable, Sendable {
    public let latestMs: Double?
    public let flowState: String?
    public let observedAt: String?
    public let truthMode: String?

    enum CodingKeys: String, CodingKey {
        case latestMs = "latest_ms"
        case flowState = "flow_state"
        case observedAt = "observed_at"
        case truthMode = "truth_mode"
    }

    public var displayFlowState: String {
        flowState?.uppercased() ?? "UNKNOWN"
    }
}

public struct CognitiveDraft: Codable, Sendable, Identifiable {
    private let stableId: String = UUID().uuidString
    public var id: String { draftId ?? stableId }
    public let draftId: String?
    public let kind: String?
    public let summary: String?
    public let createdAt: String?

    enum CodingKeys: String, CodingKey {
        case draftId = "id"
        case kind, summary
        case createdAt = "created_at"
    }
}

public struct CognitiveTriad: Codable, Sendable {
    public let runId: String?
    public let scores: TriadScores?
    public let verdict: String?

    enum CodingKeys: String, CodingKey {
        case runId = "run_id"
        case scores, verdict
    }
}

// MARK: - Hypergraph

public struct Hyperedge: Codable, Sendable, Identifiable {
    private let stableId: String = UUID().uuidString
    public var id: String { edgeId ?? stableId }
    public let edgeId: String?
    public let label: String?
    public let nodeIds: [String]?
    public let metadata: [String: String]?
    public let directed: Bool?
    public let createdAt: String?

    enum CodingKeys: String, CodingKey {
        case edgeId = "id"
        case label
        case nodeIds = "node_ids"
        case metadata, directed
        case createdAt = "created_at"
    }
}

// MARK: - Feedback

public struct FeedbackEvent: Codable, Sendable {
    public let runId: String
    public let kind: String        // "human_feedback" | "pipeline_run" | "triad_completed"
    public let clarity: Int?       // 0-10
    public let adequacy: Int?      // 0-10
    public let safety: Int?        // 0-10
    public let notes: String?

    public init(runId: String, kind: String, clarity: Int? = nil, adequacy: Int? = nil, safety: Int? = nil, notes: String? = nil) {
        self.runId = runId
        self.kind = kind
        self.clarity = clarity
        self.adequacy = adequacy
        self.safety = safety
        self.notes = notes
    }

    enum CodingKeys: String, CodingKey {
        case runId = "run_id"
        case kind, clarity, adequacy, safety, notes
    }
}

public struct FeedbackAck: Codable, Sendable {
    public let ok: Bool?
    public let eventId: String?
    public let status: String?

    enum CodingKeys: String, CodingKey {
        case ok
        case eventId = "event_id"
        case status
    }
}

// MARK: - Chat (exocortex conversation)

public struct ChatResponse: Decodable, Sendable {
    public let response: String?
    public let tokensUsed: Int?
    public let model: String?
    public let source: String?
    public let agentKind: String?
    public let sessionId: String?
    public let podName: String?
    public let conversationMode: String?
    public let appliedDiscussionProfile: String?
    public let flowState: String?

    enum CodingKeys: String, CodingKey {
        case response
        case text
        case tokensUsed = "tokens_used"
        case model
        case provider
        case tier
        case source
        case agentKind
        case sessionId
        case podName
        case conversationMode = "conversation_mode"
        case appliedDiscussionProfile = "applied_discussion_profile"
        case flowState = "flow_state"
        case agentKindSnake = "agent_kind"
        case sessionIdSnake = "session_id"
        case podNameSnake = "pod_name"
    }

    public init(
        response: String?,
        tokensUsed: Int? = nil,
        model: String? = nil,
        source: String? = nil,
        agentKind: String? = nil,
        sessionId: String? = nil,
        podName: String? = nil,
        conversationMode: String? = nil,
        appliedDiscussionProfile: String? = nil,
        flowState: String? = nil
    ) {
        self.response = response
        self.tokensUsed = tokensUsed
        self.model = model
        self.source = source
        self.agentKind = agentKind
        self.sessionId = sessionId
        self.podName = podName
        self.conversationMode = conversationMode
        self.appliedDiscussionProfile = appliedDiscussionProfile
        self.flowState = flowState
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        response =
            try container.decodeIfPresent(String.self, forKey: .response)
            ?? container.decodeIfPresent(String.self, forKey: .text)
        tokensUsed = try container.decodeIfPresent(Int.self, forKey: .tokensUsed)
        model =
            try container.decodeIfPresent(String.self, forKey: .model)
            ?? container.decodeIfPresent(String.self, forKey: .provider)
            ?? container.decodeIfPresent(String.self, forKey: .tier)
        source = try container.decodeIfPresent(String.self, forKey: .source)
        agentKind =
            try container.decodeIfPresent(String.self, forKey: .agentKind)
            ?? container.decodeIfPresent(String.self, forKey: .agentKindSnake)
        sessionId =
            try container.decodeIfPresent(String.self, forKey: .sessionId)
            ?? container.decodeIfPresent(String.self, forKey: .sessionIdSnake)
        podName =
            try container.decodeIfPresent(String.self, forKey: .podName)
            ?? container.decodeIfPresent(String.self, forKey: .podNameSnake)
        conversationMode = try container.decodeIfPresent(String.self, forKey: .conversationMode)
        appliedDiscussionProfile = try container.decodeIfPresent(String.self, forKey: .appliedDiscussionProfile)
        flowState = try container.decodeIfPresent(String.self, forKey: .flowState)
    }
}

// MARK: - HPC GPU Metrics

public struct GPUNodeMetric: Codable, Sendable, Identifiable {
    public var id: String { "\(node ?? "")-\(gpuId ?? 0)" }
    public let node: String?
    public let gpuId: Int?
    public let utilization: Double?    // 0-100
    public let memoryUsedMB: Double?
    public let temperatureC: Double?
    public let powerW: Double?

    enum CodingKeys: String, CodingKey {
        case node
        case gpuId = "gpu_id"
        case utilization
        case memoryUsedMB = "memory_used_mb"
        case temperatureC = "temperature_c"
        case powerW = "power_w"
    }
}

public struct HPCJob: Codable, Sendable, Identifiable {
    private let stableId: String = UUID().uuidString
    public var id: String { jobId ?? stableId }
    public let jobId: String?
    public let kind: String?
    public let status: String?
    public let nodeList: String?
    public let gpuCount: Int?
    public let submitTime: String?
    public let startTime: String?
    public let endTime: String?
    public let stdout: String?

    enum CodingKeys: String, CodingKey {
        case jobId = "job_id"
        case kind, status
        case nodeList = "node_list"
        case gpuCount = "gpu_count"
        case submitTime = "submit_time"
        case startTime = "start_time"
        case endTime = "end_time"
        case stdout
    }

    public var isRunning: Bool { status == "running" || status == "pending" }
    public var isCompleted: Bool { status == "completed" || status == "done" }
}

public struct HPCJobQueue: Codable, Sendable {
    public let jobs: [HPCJob]?
    public let totalGPUs: Int?
    public let allocatedGPUs: Int?
    public let generatedAt: String?

    enum CodingKeys: String, CodingKey {
        case jobs
        case totalGPUs = "total_gpus"
        case allocatedGPUs = "allocated_gpus"
        case generatedAt = "generated_at"
    }
}

public struct JobArtifact: Codable, Sendable, Identifiable {
    private let stableId: String = UUID().uuidString
    public var id: String { path ?? stableId }
    public let path: String?
    public let type: String?    // "csv", "image", "json", "surface3d"
    public let sizeBytes: Int?
    public let url: String?

    enum CodingKeys: String, CodingKey {
        case path, type
        case sizeBytes = "size_bytes"
        case url
    }
}

public struct BandwidthSample: Codable, Sendable {
    public let from: String?
    public let to: String?
    public let mbps: Double?
    public let timestamp: String?
}
