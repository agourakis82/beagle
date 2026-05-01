//
//  HPCStore.swift
//  BeagleCore
//
//  Observable store for HPC cluster state — GPU metrics, job queue, bandwidth.
//  The computational pulse of the sovereign supercomputing platform.
//

import Foundation
import Observation

@Observable
@MainActor
public final class HPCStore {

    public var gpuMetrics: [GPUNodeMetric] = []
    public var jobQueue: Truthful<HPCJobQueue> = .declared(HPCJobQueue(jobs: nil, totalGPUs: nil, allocatedGPUs: nil, generatedAt: nil))
    public var isLoading = false

    public init() {}

    // MARK: - Refresh

    public func refresh() async {
        isLoading = true
        async let queueTask = CockpitClient.shared.fetch(HPCJobQueue.self, path: "/api/jobs/queue")
        jobQueue = await queueTask
        isLoading = false
    }

    // MARK: - Job submission via beagle-server

    public func submitJob(kind: String) async -> HPCJob? {
        let result = await BeagleClient.shared.post(
            HPCJob.self,
            path: "/api/darwin/hpc/jobs/submit",
            body: ["kind": kind]
        )
        if let job = result.value {
            // Refresh queue to include new job
            await refresh()
            return job
        }
        return nil
    }

    /// Get stdout from a running/completed job.
    public func jobStdout(jobId: String) async -> String? {
        let result = await BeagleClient.shared.fetch(
            ChatResponse.self,  // reuse — has response field
            path: "/api/darwin/hpc/jobs/\(jobId)/stdout"
        )
        return result.value?.response
    }

    // MARK: - Derived

    public var jobs: [HPCJob] {
        jobQueue.value?.jobs ?? []
    }

    public var runningJobs: [HPCJob] {
        jobs.filter(\.isRunning)
    }

    public var completedJobs: [HPCJob] {
        jobs.filter(\.isCompleted)
    }

    public var totalGPUs: Int {
        jobQueue.value?.totalGPUs ?? 0
    }

    public var allocatedGPUs: Int {
        jobQueue.value?.allocatedGPUs ?? 0
    }

    public var gpuUtilizationPercent: Double {
        guard totalGPUs > 0 else { return 0 }
        return Double(allocatedGPUs) / Double(totalGPUs) * 100
    }
}
