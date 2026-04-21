//
//  CockpitClient.swift
//  BeagleCore
//
//  Truth-aware HTTP client for the cockpit API.
//  Prefers the public mobile gateway and falls back to private cockpit
//  origins when needed so iPhone, Watch, and VisionOS can work both
//  remotely and on the private plane.
//

import Foundation

public actor CockpitClient {

    public static let shared = CockpitClient()

    private let session: URLSession
    private let decoder: JSONDecoder

    /// URL resolution order — tried in sequence until one responds.
    /// Override via `configure(baseURLs:)` from the app.
    private var baseURLs: [URL] = [
        URL(string: "https://beagle.chiuratto.ai")!,                    // Public Cloudflare edge
        URL(string: "http://sounio-cockpit.tail21cbc4.ts.net")!,      // Tailnet public
        URL(string: "http://100.107.208.198")!,                        // Tailnet internal VIP
        URL(string: "http://project-cockpit.beagle.svc.cluster.local")! // In-cluster (dev only)
    ]

    private init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 8
        config.timeoutIntervalForResource = 15
        config.waitsForConnectivity = true
        config.httpAdditionalHeaders = [
            "Accept": "application/json",
            "User-Agent": "BeagleCockpit/1.0 (iOS/macOS native)"
        ]
        self.session = URLSession(configuration: config)
        self.decoder = JSONDecoder()
    }

    /// Configure the URL resolution order.
    public func configure(baseURLs: [URL]) {
        self.baseURLs = baseURLs
    }

    // MARK: - Core fetch

    /// Fetches a direct cockpit payload without the mobile envelope.
    private func fetchLegacy<T: Decodable & Sendable>(
        _ type: T.Type,
        path: String,
        timeout: TimeInterval = 8
    ) async -> Truthful<T> {
        var lastError: String = "no base URL reachable"

        for base in baseURLs {
            guard let url = URL(string: path, relativeTo: base) else { continue }
            do {
                var request = URLRequest(url: url)
                request.timeoutInterval = timeout
                let (data, response) = try await session.data(for: request)

                guard let httpResponse = response as? HTTPURLResponse else {
                    lastError = "invalid response"
                    continue
                }

                guard (200..<300).contains(httpResponse.statusCode) else {
                    lastError = "HTTP \(httpResponse.statusCode)"
                    continue
                }

                let decoded = try decoder.decode(T.self, from: data)
                return .observed(decoded, source: url.host)
            } catch {
                lastError = error.localizedDescription
                continue
            }
        }

        return .staleError(lastError)
    }

    /// Fetches a mobile API envelope and unwraps its `data` payload.
    private func fetchMobile<T: Decodable & Sendable>(
        _ type: T.Type,
        path: String,
        timeout: TimeInterval = 8
    ) async -> Truthful<T> {
        let wrapped = await fetchLegacy(MobileEnvelope<T>.self, path: path, timeout: timeout)

        guard let envelope = wrapped.value else {
            return .staleError(wrapped.error ?? "mobile route unavailable", source: wrapped.source)
        }

        let mode = envelope.meta?.truthMode.flatMap(TruthMode.init(rawValue:)) ?? wrapped.mode
        let message = envelope.error?.message ?? wrapped.error

        guard envelope.ok, let data = envelope.data else {
            return Truthful(
                value: nil,
                mode: mode,
                observedAt: wrapped.observedAt,
                source: wrapped.source,
                error: message ?? "mobile payload missing data"
            )
        }

        return Truthful(
            value: data,
            mode: mode,
            observedAt: wrapped.observedAt,
            source: wrapped.source,
            error: message
        )
    }

    // MARK: - High-level API

    public func catalog() async -> Truthful<ExecutiveCatalog> {
        let mobile = await fetchMobile(MobileCatalogData.self, path: "/api/mobile/v1/catalog")
        if let data = mobile.value {
            return Truthful(
                value: data.executiveCatalog,
                mode: mobile.mode,
                observedAt: mobile.observedAt,
                source: mobile.source,
                error: mobile.error
            )
        }
        return await fetchLegacy(ExecutiveCatalog.self, path: "/api/catalog/executive")
    }

    public func posturePolicy() async -> Truthful<PosturePolicy> {
        let mobile = await fetchMobile(MobileCatalogData.self, path: "/api/mobile/v1/catalog")
        if let policy = mobile.value?.projectPosturePolicy {
            return Truthful(
                value: policy,
                mode: mobile.mode,
                observedAt: mobile.observedAt,
                source: mobile.source,
                error: mobile.error
            )
        }
        return await fetchLegacy(PosturePolicy.self, path: "/api/catalog/project-posture-policy")
    }

    public func missionControl(slug: String) async -> Truthful<MissionControl> {
        let overview = await mobileOverview(slug: slug)
        if let data = overview.value {
            return Truthful(
                value: data.missionControl,
                mode: overview.mode,
                observedAt: overview.observedAt,
                source: overview.source,
                error: overview.error
            )
        }
        return await fetchLegacy(MissionControl.self, path: "/api/projects/\(slug)/mission-control")
    }

    public func clusterLaneTruth(slug: String) async -> Truthful<ClusterLaneTruth> {
        let overview = await mobileOverview(slug: slug)
        if let data = overview.value {
            return Truthful(
                value: data.clusterLaneTruth,
                mode: overview.mode,
                observedAt: overview.observedAt,
                source: overview.source,
                error: overview.error
            )
        }
        return await fetchLegacy(ClusterLaneTruth.self, path: "/api/projects/\(slug)/cluster/lane-truth")
    }

    public func researchOperations(slug: String) async -> Truthful<ResearchOperations> {
        let overview = await mobileOverview(slug: slug)
        if let data = overview.value {
            return Truthful(
                value: data.researchOperations,
                mode: overview.mode,
                observedAt: overview.observedAt,
                source: overview.source,
                error: overview.error
            )
        }
        return await fetchLegacy(ResearchOperations.self, path: "/api/projects/\(slug)/research/operations")
    }

    public func inferenceRuntime(slug: String) async -> Truthful<InferenceRuntime> {
        let overview = await mobileOverview(slug: slug)
        if let runtime = overview.value?.inferenceRuntime {
            return Truthful(
                value: runtime,
                mode: overview.mode,
                observedAt: overview.observedAt,
                source: overview.source,
                error: overview.error
            )
        }

        let wrapped = await fetchLegacy(InferenceRuntimeResponse.self, path: "/api/projects/\(slug)/inference/runtime")
        guard let runtime = wrapped.value?.runtime else {
            return .staleError(wrapped.error ?? "no runtime payload", source: wrapped.source)
        }
        return Truthful(value: runtime, mode: wrapped.mode, observedAt: wrapped.observedAt, source: wrapped.source, error: wrapped.error)
    }

    public func viewerRuntime(slug: String) async -> Truthful<ViewerRuntimeResponse> {
        let overview = await mobileOverview(slug: slug)
        if let runtime = overview.value?.viewerRuntime {
            return Truthful(
                value: runtime,
                mode: overview.mode,
                observedAt: overview.observedAt,
                source: overview.source,
                error: overview.error
            )
        }
        return await fetchLegacy(ViewerRuntimeResponse.self, path: "/api/projects/\(slug)/viewer/runtime")
    }

    func mobileOverview(slug: String) async -> Truthful<MobileOverviewData> {
        await fetchMobile(MobileOverviewData.self, path: "/api/mobile/v1/projects/\(slug)/overview")
    }
}

private struct MobileEnvelope<Data: Decodable & Sendable>: Decodable, Sendable {
    let ok: Bool
    let data: Data?
    let error: MobileEnvelopeError?
    let meta: MobileEnvelopeMeta?
}

private struct MobileEnvelopeError: Decodable, Sendable {
    let code: String?
    let message: String?
}

private struct MobileEnvelopeMeta: Decodable, Sendable {
    let truthMode: String?
    let observedAt: String?
    let generatedAt: String?
}

private struct MobileCatalogData: Decodable, Sendable {
    let generatedAt: String?
    let projectPosturePolicy: PosturePolicy?
    let projects: [MobileCatalogProject]

    var executiveCatalog: ExecutiveCatalog {
        ExecutiveCatalog(
            generatedAt: generatedAt,
            projects: projects.map(\.legacyProject),
            projectPosturePolicy: projectPosturePolicy
        )
    }
}

private struct MobileCatalogProject: Decodable, Sendable {
    let slug: String
    let posture: String
    let workspace: MobileCatalogWorkspace?

    var legacyProject: Project {
        Project(
            projectSlug: slug,
            mode: posture,
            branch: workspace?.liveBranch ?? workspace?.branchContract,
            preferredPrBase: workspace?.branchContract,
            workspacePod: workspace == nil ? nil : "live",
            workspaceRoot: workspace?.workspaceRoot,
            repoUrl: workspace?.repoUrl
        )
    }
}

private struct MobileCatalogWorkspace: Decodable, Sendable {
    let workspaceRoot: String?
    let repoUrl: String?
    let branchContract: String?
    let liveBranch: String?
}

struct MobileOverviewData: Decodable, Sendable {
    let project: MobileOverviewProject
    let workspaceState: MobileWorkspaceState?
    let inferenceRuntime: InferenceRuntime?
    let viewerRuntime: ViewerRuntimeResponse?
    let generatedAt: String?

    var missionControl: MissionControl {
        MissionControl(project: legacyProject, packetCount: nil, generatedAt: generatedAt)
    }

    var clusterLaneTruth: ClusterLaneTruth {
        ClusterLaneTruth(project: legacyProject, generatedAt: generatedAt)
    }

    var researchOperations: ResearchOperations {
        ResearchOperations(project: legacyProject, generatedAt: generatedAt)
    }

    var legacyProject: Project {
        Project(
            projectSlug: project.slug,
            mode: project.posture,
            namespace: project.namespace,
            branch: project.branch,
            preferredPrBase: project.workspaceBootstrapBranch ?? project.branch,
            workspacePod: workspaceLabel,
            workspaceRoot: workspaceState?.workspaceRoot ?? project.workspaceRoot
        )
    }

    private var workspaceLabel: String? {
        guard let state = nonEmpty(workspaceState?.status) else {
            return nil
        }

        switch state {
        case "live", "recovering":
            return state
        default:
            return workspaceState?.ready == true ? "live" : nil
        }
    }
}

struct MobileOverviewProject: Decodable, Sendable {
    let slug: String
    let posture: String
    let namespace: String?
    let branch: String?
    let workspaceBootstrapBranch: String?
    let workspaceRoot: String?
}

struct MobileWorkspaceState: Decodable, Sendable {
    let status: String?
    let workspaceRoot: String?
    let ready: Bool?
}

private func nonEmpty(_ value: String?) -> String? {
    guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else {
        return nil
    }
    return trimmed
}
