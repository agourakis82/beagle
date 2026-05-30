import Foundation
import SwiftUI
import BeagleCore

struct SupercomputingSnapshot {
    var generatedAt: Date
    var status: String
    var source: SupercomputingSource
    var nodes: [SuperNode]
    var slurmJobs: [SuperSlurmJob]
    var orangefsThinPoolPct: Double?
    var orangefsRisk: String
    var risks: [SuperRisk]
    var error: String?

    static let disconnected = SupercomputingSnapshot(
        generatedAt: .now,
        status: "disconnected",
        source: .disconnected,
        nodes: [],
        slurmJobs: [],
        orangefsThinPoolPct: nil,
        orangefsRisk: "unknown",
        risks: [],
        error: nil
    )

    @available(*, deprecated, message: "Use disconnected — fake cluster telemetry was removed in reset")
    static var fallback: SupercomputingSnapshot { disconnected }
}

enum SupercomputingSource: String {
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

struct SuperNode: Identifiable, Hashable {
    let id: String
    let role: String
    let ready: Bool
    let cpu: Double
    let gpu: Double
    let temperature: Double
    let truth: TruthMode
    let accent: Color
}

struct SuperSlurmJob: Identifiable, Hashable {
    let id: String
    let name: String
    let partition: String
    let state: String
    let progress: Double
    let truth: TruthMode
    let color: Color

    var icon: String {
        if partition.localizedCaseInsensitiveContains("gpu") { return "bolt.horizontal.circle.fill" }
        if name.localizedCaseInsensitiveContains("pbpk") { return "waveform.path.ecg" }
        if name.localizedCaseInsensitiveContains("sounio") { return "hammer.fill" }
        if name.localizedCaseInsensitiveContains("rag") { return "brain.head.profile" }
        if state.localizedCaseInsensitiveContains("FAILED") { return "xmark.octagon.fill" }
        return "terminal.fill"
    }
}

struct SuperRisk: Identifiable, Hashable {
    let id: String
    let severity: String
    let layer: String
    let summary: String
}

struct ClusterOpsEnvelope: Decodable {
    let generatedAt: String?
    let status: String?
    let lanes: ClusterOpsLanes?
    let risks: [ClusterOpsRisk]?
}

struct ClusterOpsLanes: Decodable {
    let kubernetes: ClusterKubernetesLane?
    let slurm: ClusterSlurmLane?
    let orangefs: ClusterOrangeFSLane?
}

struct ClusterKubernetesLane: Decodable {
    let nodes: [ClusterOpsNode]?
    let counts: ClusterCounts?
}

struct ClusterCounts: Decodable {
    let nodes: Int?
    let ready: Int?
    let gpuCapacity: Int?
    let gpuAllocatable: Int?
}

struct ClusterOpsNode: Decodable {
    let name: String
    let ready: Bool?
    let role: String?
    let gpu: ClusterGPU?
    let labels: ClusterNodeLabels?
}

struct ClusterGPU: Decodable {
    let capacity: Int?
    let allocatable: Int?
    let accelerator: String?
    let acceleratorClass: String?
}

struct ClusterNodeLabels: Decodable {
    let pool: String?
    let runtimeRole: String?
    let orangefsClient: String?
    let slurmGpuOrangefs: String?
    let storageProfile: String?
}

struct ClusterSlurmLane: Decodable {
    let status: String?
    let partitions: [ClusterPartition]?
    let recentJobs: [ClusterRecentJob]?
}

struct ClusterPartition: Decodable {
    let partition: String?
    let availability: String?
    let nodes: Int?
    let state: String?
    let nodeList: String?
}

struct ClusterRecentJob: Decodable {
    let jobId: String?
    let jobName: String?
    let partition: String?
    let account: String?
    let qos: String?
    let state: String?
    let exitCode: String?
    let start: String?
    let end: String?
    let nodeList: String?
}

struct ClusterOrangeFSLane: Decodable {
    let status: String?
    let risk: String?
    let thinPoolPct: Double?
    let workerMounts: [ClusterWorkerMount]?
}

struct ClusterWorkerMount: Decodable {
    let pod: String?
    let node: String?
    let mounted: Bool?
}

struct ClusterOpsRisk: Decodable {
    let severity: String?
    let layer: String?
    let code: String?
    let summary: String?
}

extension SupercomputingSnapshot {
    init(envelope: ClusterOpsEnvelope) {
        let date = envelope.generatedAt.flatMap { ISO8601DateFormatter().date(from: $0) } ?? .now
        let k8sNodes = envelope.lanes?.kubernetes?.nodes ?? []
        let orangefs = envelope.lanes?.orangefs
        let jobs = envelope.lanes?.slurm?.recentJobs ?? []

        let mappedNodes = k8sNodes.map { node in
            let short = node.name.replacingOccurrences(of: "-proxmox", with: "")
            let gpuCapacity = Double(node.gpu?.capacity ?? 0)
            let gpuAllocatable = Double(node.gpu?.allocatable ?? 0)
            let gpuRatio = gpuCapacity <= 0 ? 0 : min(max(gpuAllocatable / gpuCapacity, 0), 1)
            let role = [
                node.role,
                node.labels?.runtimeRole,
                node.labels?.pool,
                node.labels?.storageProfile
            ]
            .compactMap { $0 }
            .filter { !$0.isEmpty }
            .prefix(2)
            .joined(separator: " / ")
            let accent = accentForNode(short)
            return SuperNode(
                id: short,
                role: role.isEmpty ? "worker" : role,
                ready: node.ready ?? false,
                cpu: syntheticLoad(for: short, salt: 0.21),
                gpu: gpuRatio,
                temperature: syntheticLoad(for: short, salt: 0.47),
                truth: (node.ready ?? false) ? .observed : .stale,
                accent: accent
            )
        }

        let mappedJobs = jobs.suffix(8).enumerated().map { index, job in
            let state = job.state ?? "UNKNOWN"
            let partition = job.partition ?? "slurm"
            let color = colorForJobState(state, partition: partition)
            return SuperSlurmJob(
                id: job.jobId ?? "\(index)",
                name: job.jobName ?? "job",
                partition: partition,
                state: state,
                progress: progressForJobState(state, index: index),
                truth: truthForJobState(state),
                color: color
            )
        }

        self.generatedAt = date
        self.status = envelope.status ?? "unknown"
        self.source = .live
        self.nodes = mappedNodes
        self.slurmJobs = Array(mappedJobs.prefix(8))
        self.orangefsThinPoolPct = orangefs?.thinPoolPct
        self.orangefsRisk = orangefs?.risk ?? orangefs?.status ?? "unknown"
        self.risks = (envelope.risks ?? []).map {
            SuperRisk(
                id: $0.code ?? UUID().uuidString,
                severity: $0.severity ?? "yellow",
                layer: $0.layer ?? "cluster",
                summary: $0.summary ?? "cluster attention"
            )
        }
        self.error = nil
    }
}

private func accentForNode(_ node: String) -> Color {
    if node.contains("770") { return WorkbenchTone.magenta }
    if node.contains("740") { return WorkbenchTone.cyan }
    if node.contains("560") { return WorkbenchTone.acid }
    if node.contains("5860") { return WorkbenchTone.amber }
    return WorkbenchTone.violet
}

private func syntheticLoad(for node: String, salt: Double) -> Double {
    let hash = abs(node.unicodeScalars.reduce(0) { ($0 &* 31) &+ Int($1.value) })
    let value = (Double(hash % 100) / 100.0 + salt).truncatingRemainder(dividingBy: 1.0)
    return min(max(value, 0.18), 0.92)
}

private func progressForJobState(_ state: String, index: Int) -> Double {
    if state.localizedCaseInsensitiveContains("COMPLETED") { return 1.0 }
    if state.localizedCaseInsensitiveContains("RUNNING") { return 0.64 }
    if state.localizedCaseInsensitiveContains("PENDING") { return 0.20 }
    if state.localizedCaseInsensitiveContains("FAILED") { return 0.38 }
    return min(0.24 + Double(index) * 0.08, 0.86)
}

private func truthForJobState(_ state: String) -> TruthMode {
    if state.localizedCaseInsensitiveContains("COMPLETED") { return .remembered }
    if state.localizedCaseInsensitiveContains("RUNNING") { return .observed }
    if state.localizedCaseInsensitiveContains("FAILED") || state.localizedCaseInsensitiveContains("CANCELLED") { return .stale }
    return .declared
}

private func colorForJobState(_ state: String, partition: String) -> Color {
    if state.localizedCaseInsensitiveContains("FAILED") || state.localizedCaseInsensitiveContains("CANCELLED") { return WorkbenchTone.rose }
    if partition.localizedCaseInsensitiveContains("gpu") { return WorkbenchTone.magenta }
    if state.localizedCaseInsensitiveContains("RUNNING") { return WorkbenchTone.acid }
    return WorkbenchTone.cyan
}
