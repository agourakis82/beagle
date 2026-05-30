//
//  WorkbenchWireDefaults.swift
//  BeagleCore
//

import Foundation

public enum WorkbenchWireDefaults {
    public static let catalog: Truthful<ExecutiveCatalog> = .declared(
        ExecutiveCatalog(generatedAt: nil, projects: [], projectPosturePolicy: nil)
    )

    public static let workspace: Truthful<GoWorkNowEnvelope> = .declared(
        GoWorkNowEnvelope(project: nil, projectSlug: nil, generatedAt: nil, goWorkNow: nil)
    )

    public static let cluster: Truthful<ClusterOpsSummary> = .declared(
        ClusterOpsSummary(status: nil, generatedAt: nil, truthMode: nil)
    )

    public static let multimodel: Truthful<MultimodelTurnsResponse> = .declared(
        MultimodelTurnsResponse(
            projectSlug: nil,
            turns: [],
            activeTurns: [],
            activeCount: 0,
            count: 0,
            generatedAt: nil,
            truthMode: nil
        )
    )

    public static let presence: Truthful<WorkbenchContextPresenceResponse> = .declared(
        WorkbenchContextPresenceResponse(clients: [], truthMode: nil)
    )

    public static let exocortex: Truthful<ExocortexProcessResponse> = .declared(
        ExocortexProcessResponse(
            phi: nil,
            substrate: nil,
            awarenessLevel: nil,
            response: nil,
            truthMode: nil,
            declaredReason: nil,
            tpmSource: nil
        )
    )

    public static let graphrag: Truthful<GraphRAGQueryResponse> = .declared(
        GraphRAGQueryResponse(
            nodeCount: 0,
            edgeCount: 0,
            nodes: [],
            edges: [],
            highlights: []
        )
    )

    public static let handoffs: Truthful<WorkbenchMessageBoardResponse> = .declared(
        WorkbenchMessageBoardResponse(
            summary: WorkbenchMessageBoardSummary(total: 0, waiting: 0, active: 0, done: 0, canceled: 0, stale: 0, urgent: 0),
            nextActions: [],
            count: 0
        )
    )

    public static let providers: Truthful<MultimodelProvidersResponse> = .declared(
        MultimodelProvidersResponse(projectSlug: nil, providers: [], truthMode: nil)
    )

    public static let zellijStatus: Truthful<WorkspaceZellijStatusResponse> = .declared(
        WorkspaceZellijStatusResponse(
            ok: false,
            projectSlug: nil,
            sessionName: nil,
            declaredTabs: [],
            transport: "none",
            target: nil,
            zellijPath: nil,
            sessionsRaw: nil,
            sshCandidates: [],
            probeError: nil,
            truthMode: "declared",
            error: nil
        )
    )

    public static let handoffCompile: Truthful<WorkbenchHandoffCompilePacket> = .declared(
        WorkbenchHandoffCompilePacket(
            schema: nil,
            projectSlug: nil,
            generatedAt: nil,
            truthMode: nil,
            taskProfile: nil,
            handoff: nil,
            thread: nil,
            retrieval: nil,
            replyInstruction: nil,
            compiledContextText: nil,
            graph: nil,
            highlights: nil,
            upstream: nil
        )
    )
}
