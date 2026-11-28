//
//  ClusterComputeModels.swift
//  BeagleCore
//
//  Inference fabric, cluster nodes/truth/summary, research operations,
//  viewer runtime, science jobs, and HPC GPU metrics.
//

import Foundation

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

// MARK: - Cluster Truth & Summary

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

public struct ClusterSummary: Codable, Sendable {
    public let nodes: [ClusterNode]?
    public let project: Project?
    public let generatedAt: String?
    public let truthMode: String?
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
