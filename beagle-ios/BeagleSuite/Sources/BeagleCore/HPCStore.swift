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

    public private(set) var gpuMetrics: [GPUNodeMetric] = []
    public private(set) var jobQueue: Truthful<HPCJobQueue> = .declared(HPCJobQueue(jobs: nil, totalGPUs: nil, allocatedGPUs: nil, generatedAt: nil))
    public private(set) var isLoading = false
    public private(set) var lastSubmissionError: String?

    private let cockpitClient: CockpitClient
    private let beagleClient: BeagleClient

    public init(
        cockpitClient: CockpitClient = .shared,
        beagleClient: BeagleClient = .shared
    ) {
        self.cockpitClient = cockpitClient
        self.beagleClient = beagleClient
    }

    // MARK: - Refresh

    public func refresh() async {
        isLoading = true
        defer { isLoading = false }
        jobQueue = await cockpitClient.hpcJobQueue()
    }

    // MARK: - Job submission via beagle-server

    /// Submits an HPC job and preserves full epistemic provenance / error details.
    public func submitJobResult(kind: String) async -> Truthful<HPCJob> {
        let result = await beagleClient.post(
            HPCJob.self,
            path: "/api/darwin/hpc/jobs/submit",
            body: ["kind": kind]
        )
        if result.value != nil {
            lastSubmissionError = nil
            await refresh()
        } else {
            lastSubmissionError = result.error ?? "Job submission failed"
        }
        return result
    }

    public func submitJob(kind: String) async -> HPCJob? {
        await submitJobResult(kind: kind).value
    }

    /// Get stdout from a running/completed job.
    public func jobStdout(jobId: String) async -> String? {
        let encodedId = BeagleEndpoints.pathComponent(jobId)
        let result = await beagleClient.fetch(
            ChatResponse.self,  // reuse — has response field
            path: "/api/darwin/hpc/jobs/\(encodedId)/stdout"
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
