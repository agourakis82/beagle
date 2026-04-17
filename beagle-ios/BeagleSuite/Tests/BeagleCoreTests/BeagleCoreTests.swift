import Testing
@testable import BeagleCore
import Foundation

@Test func truthModeValues() {
    #expect(TruthMode.observed.rawValue == "observed")
    #expect(TruthMode.remembered.rawValue == "remembered")
    #expect(TruthMode.declared.rawValue == "declared")
}

@Test func postureCountsInit() {
    let counts = PostureCounts(totalProjects: 5, alwaysOn: 1, warm: 2, cold: 2)
    #expect(counts.totalProjects == 5)
    #expect(counts.alwaysOn == 1)
    #expect(PostureCounts.empty.totalProjects == 0)
}

@Test func agentSessionPhaseMapping() {
    let running = AgentSession(
        kind: "claude-code",
        name: "sounio-claude-code",
        replicas: 1,
        readyReplicas: 1,
        createdAt: nil,
        pods: nil,
        status: "running",
        truthMode: "observed",
        action: nil
    )
    #expect(running.phase == .running)

    let paused = AgentSession(
        kind: "claude-code",
        name: "sounio-claude-code",
        replicas: 0,
        readyReplicas: 0,
        createdAt: nil,
        pods: nil,
        status: "paused",
        truthMode: "observed",
        action: nil
    )
    #expect(paused.phase == .paused)

    let pending = AgentSession(
        kind: "claude-code",
        name: "sounio-claude-code",
        replicas: 1,
        readyReplicas: 0,
        createdAt: nil,
        pods: [AgentPod(name: "pod-1", phase: "Pending", ready: false)],
        status: "creating",
        truthMode: "observed",
        action: "resume"
    )
    #expect(pending.phase == .pending)
}

@Test func beagleBackendErrorPayloadMessageIncludesStructuredFields() throws {
    let payload = BeagleBackendErrorPayload(
        error: "unauthorized",
        reason: "invalid or missing API token",
        truthMode: "stale",
        requestId: "req-123",
        caller: "ios",
        via: "auth-bridge",
        proxiedPath: "/api/auth/beagle-token"
    )

    let message = payload.message(statusCode: 401, fallback: "HTTP 401")

    #expect(message.contains("HTTP 401"))
    #expect(message.contains("unauthorized"))
    #expect(message.contains("invalid or missing API token"))
    #expect(message.contains("truth=stale"))
    #expect(message.contains("requestId=req-123"))
    #expect(message.contains("caller=ios"))
    #expect(message.contains("via=auth-bridge"))
    #expect(message.contains("path=/api/auth/beagle-token"))
}

@Test func cockpitBackendErrorPayloadMessageIncludesRequestId() {
    let payload = CockpitBackendErrorPayload(
        error: "session resume failed",
        reason: nil,
        truthMode: "stale",
        requestId: "resume-42"
    )

    let message = payload.message(statusCode: 503, fallback: "HTTP 503")

    #expect(message.contains("HTTP 503"))
    #expect(message.contains("session resume failed"))
    #expect(message.contains("truth=stale"))
    #expect(message.contains("requestId=resume-42"))
}
