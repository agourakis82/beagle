//
//  ExocortexBenchmarkIndexModels.swift
//  BeagleCore
//
//  Memory benchmark runs, truthsets, promotion gates, hot-path modes, and
//  semantic index status/run contracts.
//

import Foundation

public struct MemoryBenchmarkMetricSet: Codable, Equatable, Sendable {
    public let topKHitRate: Double?
    public let exactSupport: Double?
    public let multiHopCorrectness: Double?
    public let temporalCorrectness: Double?
    public let provenanceCompleteness: Double?
    public let contradictionSafety: Double?
    public let implicitRecall: Double?
    public let restrictedLeakCount: Int?
    public let p95LatencyMs: Double?
    public let blindJudgeDepth: Double?

    enum CodingKeys: String, CodingKey {
        case topKHitRate = "top_k_hit_rate"
        case exactSupport = "exact_support"
        case multiHopCorrectness = "multi_hop_correctness"
        case temporalCorrectness = "temporal_correctness"
        case provenanceCompleteness = "provenance_completeness"
        case contradictionSafety = "contradiction_safety"
        case implicitRecall = "implicit_recall"
        case restrictedLeakCount = "restricted_leak_count"
        case p95LatencyMs = "p95_latency_ms"
        case blindJudgeDepth = "blind_judge_depth"
    }
}

public struct MemoryBenchmarkModeResult: Codable, Equatable, Sendable, Identifiable {
    public var id: String { mode }
    public let mode: String
    public let status: String
    public let score: Double
    public let metrics: MemoryBenchmarkMetricSet?
    public let notes: [String]

    enum CodingKeys: String, CodingKey {
        case mode
        case status
        case score
        case metrics
        case notes
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        mode = try container.decode(String.self, forKey: .mode)
        status = try container.decode(String.self, forKey: .status)
        score = try container.decodeIfPresent(Double.self, forKey: .score) ?? 0
        metrics = try container.decodeIfPresent(MemoryBenchmarkMetricSet.self, forKey: .metrics)
        notes = try container.decodeIfPresent([String].self, forKey: .notes) ?? []
    }
}

public struct MemoryPromotionGate: Codable, Equatable, Sendable {
    public let baselineMode: String
    public let candidateMode: String
    public let requiredMargin: Double
    public let baselineScore: Double?
    public let candidateScore: Double?
    public let consecutivePassingRuns: Int
    public let requiredConsecutiveRuns: Int
    public let hardGatesPassed: Bool
    public let eligible: Bool
    public let rationale: String

    enum CodingKeys: String, CodingKey {
        case baselineMode = "baseline_mode"
        case candidateMode = "candidate_mode"
        case requiredMargin = "required_margin"
        case baselineScore = "baseline_score"
        case candidateScore = "candidate_score"
        case consecutivePassingRuns = "consecutive_passing_runs"
        case requiredConsecutiveRuns = "required_consecutive_runs"
        case hardGatesPassed = "hard_gates_passed"
        case eligible
        case rationale
    }
}

public struct MemoryTruthJudgment: Codable, Equatable, Sendable, Identifiable {
    public var id: String { caseId }
    public let caseId: String
    public let domain: String
    public let query: String
    public let passed: Bool
    public let score: Double
    public let baselineSupport: Double
    public let candidateSupport: Double
    public let regression: Bool
    public let supportingRefs: [String]
    public let notes: [String]

    enum CodingKeys: String, CodingKey {
        case caseId = "case_id"
        case domain
        case query
        case passed
        case score
        case baselineSupport = "baseline_support"
        case candidateSupport = "candidate_support"
        case regression
        case supportingRefs = "supporting_refs"
        case notes
    }
}

public struct MemoryBenchmarkRun: Codable, Equatable, Sendable, Identifiable {
    public let id: String
    public let createdAt: String
    public let status: String
    public let schemaVersion: String
    public let truthsetId: String?
    public let queryCount: Int
    public let domains: [String]
    public let judgeMode: String?
    public let baselineMode: String?
    public let candidateModes: [String]
    public let hardGates: [String: Bool]
    public let modeResults: [MemoryBenchmarkModeResult]
    public let caseJudgments: [MemoryTruthJudgment]
    public let winningMode: String?
    public let regressionCount: Int
    public let promotionGate: MemoryPromotionGate?
    public let hotPathEligible: Bool
    public let artifactManifest: String?
    public let degradedReason: String?

    enum CodingKeys: String, CodingKey {
        case id
        case createdAt = "created_at"
        case status
        case schemaVersion = "schema_version"
        case truthsetId = "truthset_id"
        case queryCount = "query_count"
        case domains
        case judgeMode = "judge_mode"
        case baselineMode = "baseline_mode"
        case candidateModes = "candidate_modes"
        case hardGates = "hard_gates"
        case modeResults = "mode_results"
        case caseJudgments = "case_judgments"
        case winningMode = "winning_mode"
        case regressionCount = "regression_count"
        case promotionGate = "promotion_gate"
        case hotPathEligible = "hot_path_eligible"
        case artifactManifest = "artifact_manifest"
        case degradedReason = "degraded_reason"
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        createdAt = try container.decode(String.self, forKey: .createdAt)
        status = try container.decode(String.self, forKey: .status)
        schemaVersion = try container.decode(String.self, forKey: .schemaVersion)
        truthsetId = try container.decodeIfPresent(String.self, forKey: .truthsetId)
        queryCount = try container.decodeIfPresent(Int.self, forKey: .queryCount) ?? 0
        domains = try container.decodeIfPresent([String].self, forKey: .domains) ?? []
        judgeMode = try container.decodeIfPresent(String.self, forKey: .judgeMode)
        baselineMode = try container.decodeIfPresent(String.self, forKey: .baselineMode)
        candidateModes = try container.decodeIfPresent([String].self, forKey: .candidateModes) ?? []
        hardGates = try container.decodeIfPresent([String: Bool].self, forKey: .hardGates) ?? [:]
        modeResults = try container.decodeIfPresent([MemoryBenchmarkModeResult].self, forKey: .modeResults) ?? []
        caseJudgments = try container.decodeIfPresent([MemoryTruthJudgment].self, forKey: .caseJudgments) ?? []
        winningMode = try container.decodeIfPresent(String.self, forKey: .winningMode)
        regressionCount = try container.decodeIfPresent(Int.self, forKey: .regressionCount) ?? 0
        promotionGate = try container.decodeIfPresent(MemoryPromotionGate.self, forKey: .promotionGate)
        hotPathEligible = try container.decodeIfPresent(Bool.self, forKey: .hotPathEligible) ?? false
        artifactManifest = try container.decodeIfPresent(String.self, forKey: .artifactManifest)
        degradedReason = try container.decodeIfPresent(String.self, forKey: .degradedReason)
    }
}

public struct MemoryBenchmarkStatus: Codable, Equatable, Sendable {
    public let generatedAt: String
    public let schemaVersion: String
    public let status: String
    public let latestRunId: String?
    public let latestScore: Double?
    public let queryCount: Int
    public let hardGates: [String: Bool]
    public let evaluatedModes: [String]
    public let regressionCount: Int
    public let artifactManifest: String?
    public let degradedReason: String?
    public let latestRun: MemoryBenchmarkRun?
    public let truthsetId: String?
    public let promotionGate: MemoryPromotionGate?
    public let hotPathEligible: Bool
    public let provisionalHotPath: Bool
    public let hotPathMode: String?
    public let confirmedPassingRuns: Int
    public let portfolioTruthsetId: String?

    enum CodingKeys: String, CodingKey {
        case generatedAt = "generated_at"
        case schemaVersion = "schema_version"
        case status
        case latestRunId = "latest_run_id"
        case latestScore = "latest_score"
        case queryCount = "query_count"
        case hardGates = "hard_gates"
        case evaluatedModes = "evaluated_modes"
        case regressionCount = "regression_count"
        case artifactManifest = "artifact_manifest"
        case degradedReason = "degraded_reason"
        case latestRun = "latest_run"
        case truthsetId = "truthset_id"
        case promotionGate = "promotion_gate"
        case hotPathEligible = "hot_path_eligible"
        case provisionalHotPath = "provisional_hot_path"
        case hotPathMode = "hot_path_mode"
        case confirmedPassingRuns = "confirmed_passing_runs"
        case portfolioTruthsetId = "portfolio_truthset_id"
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        generatedAt = try container.decodeIfPresent(String.self, forKey: .generatedAt) ?? ""
        schemaVersion = try container.decodeIfPresent(String.self, forKey: .schemaVersion) ?? "beagle-memory-bench-hypermemory-v1.8"
        status = try container.decodeIfPresent(String.self, forKey: .status) ?? "empty"
        latestRunId = try container.decodeIfPresent(String.self, forKey: .latestRunId)
        latestScore = try container.decodeIfPresent(Double.self, forKey: .latestScore)
        queryCount = try container.decodeIfPresent(Int.self, forKey: .queryCount) ?? 0
        hardGates = try container.decodeIfPresent([String: Bool].self, forKey: .hardGates) ?? [:]
        evaluatedModes = try container.decodeIfPresent([String].self, forKey: .evaluatedModes) ?? []
        regressionCount = try container.decodeIfPresent(Int.self, forKey: .regressionCount) ?? 0
        artifactManifest = try container.decodeIfPresent(String.self, forKey: .artifactManifest)
        degradedReason = try container.decodeIfPresent(String.self, forKey: .degradedReason)
        latestRun = try container.decodeIfPresent(MemoryBenchmarkRun.self, forKey: .latestRun)
        truthsetId = try container.decodeIfPresent(String.self, forKey: .truthsetId)
        promotionGate = try container.decodeIfPresent(MemoryPromotionGate.self, forKey: .promotionGate)
        hotPathEligible = try container.decodeIfPresent(Bool.self, forKey: .hotPathEligible) ?? false
        provisionalHotPath = try container.decodeIfPresent(Bool.self, forKey: .provisionalHotPath) ?? false
        hotPathMode = try container.decodeIfPresent(String.self, forKey: .hotPathMode)
        confirmedPassingRuns = try container.decodeIfPresent(Int.self, forKey: .confirmedPassingRuns) ?? 0
        portfolioTruthsetId = try container.decodeIfPresent(String.self, forKey: .portfolioTruthsetId)
    }
}

public struct HotPathMode: Codable, Equatable, Sendable, RawRepresentable {
    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        rawValue = try container.decode(String.self)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

public struct PortfolioTruthGate: Codable, Equatable, Sendable {
    public let truthsetId: String?
    public let portfolioTruthsetId: String?
    public let hotPathMode: String?
    public let provisionalHotPath: Bool
    public let confirmedPassing: Bool
    public let requiredConfirmedRuns: Int?
    public let requiredMargin: Double?
    public let policy: String?

    enum CodingKeys: String, CodingKey {
        case truthsetId = "truthset_id"
        case portfolioTruthsetId = "portfolio_truthset_id"
        case hotPathMode = "hot_path_mode"
        case provisionalHotPath = "provisional_hot_path"
        case confirmedPassing = "confirmed_passing"
        case requiredConfirmedRuns = "required_confirmed_runs"
        case requiredMargin = "required_margin"
        case policy
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        truthsetId = try container.decodeIfPresent(String.self, forKey: .truthsetId)
        portfolioTruthsetId = try container.decodeIfPresent(String.self, forKey: .portfolioTruthsetId)
        hotPathMode = try container.decodeIfPresent(String.self, forKey: .hotPathMode)
        provisionalHotPath = try container.decodeIfPresent(Bool.self, forKey: .provisionalHotPath) ?? false
        confirmedPassing = try container.decodeIfPresent(Bool.self, forKey: .confirmedPassing) ?? false
        requiredConfirmedRuns = try container.decodeIfPresent(Int.self, forKey: .requiredConfirmedRuns)
        requiredMargin = try container.decodeIfPresent(Double.self, forKey: .requiredMargin)
        policy = try container.decodeIfPresent(String.self, forKey: .policy)
    }
}

public struct SemanticIndexRun: Codable, Equatable, Sendable, Identifiable {
    public let id: String
    public let createdAt: String
    public let status: String
    public let schemaVersion: String
    public let hotPathMode: String?
    public let runtime: String?
    public let model: String?
    public let fallbackModel: String?
    public let rerankerModel: String?
    public let sourceExportId: String?
    public let sourceMerkleRoot: String?
    public let episodeCount: Int
    public let atomCount: Int
    public let worldCount: Int
    public let truthsetId: String?
    public let artifactManifest: String?
    public let lancedbPath: String?
    public let tableName: String?
    public let rowCount: Int
    public let indexReady: Bool
    public let nativeLancedb: Bool
    public let maxsimReady: Bool
    public let embeddingBackend: String?
    public let vectorDim: Int?
    public let maxTokens: Int?
    public let workerStatus: String?
    public let restrictedLeakCount: Int
    public let workerLatencyMs: Double?
    public let degradedReason: String?

    enum CodingKeys: String, CodingKey {
        case id
        case createdAt = "created_at"
        case status
        case schemaVersion = "schema_version"
        case hotPathMode = "hot_path_mode"
        case runtime
        case model
        case fallbackModel = "fallback_model"
        case rerankerModel = "reranker_model"
        case sourceExportId = "source_export_id"
        case sourceMerkleRoot = "source_merkle_root"
        case episodeCount = "episode_count"
        case atomCount = "atom_count"
        case worldCount = "world_count"
        case truthsetId = "truthset_id"
        case artifactManifest = "artifact_manifest"
        case lancedbPath = "lancedb_path"
        case tableName = "table_name"
        case rowCount = "row_count"
        case indexReady = "index_ready"
        case nativeLancedb = "native_lancedb"
        case maxsimReady = "maxsim_ready"
        case embeddingBackend = "embedding_backend"
        case vectorDim = "vector_dim"
        case maxTokens = "max_tokens"
        case workerStatus = "worker_status"
        case restrictedLeakCount = "restricted_leak_count"
        case workerLatencyMs = "worker_latency_ms"
        case degradedReason = "degraded_reason"
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        createdAt = try container.decodeIfPresent(String.self, forKey: .createdAt) ?? ""
        status = try container.decodeIfPresent(String.self, forKey: .status) ?? "unknown"
        schemaVersion = try container.decodeIfPresent(String.self, forKey: .schemaVersion) ?? ""
        hotPathMode = try container.decodeIfPresent(String.self, forKey: .hotPathMode)
        runtime = try container.decodeIfPresent(String.self, forKey: .runtime)
        model = try container.decodeIfPresent(String.self, forKey: .model)
        fallbackModel = try container.decodeIfPresent(String.self, forKey: .fallbackModel)
        rerankerModel = try container.decodeIfPresent(String.self, forKey: .rerankerModel)
        sourceExportId = try container.decodeIfPresent(String.self, forKey: .sourceExportId)
        sourceMerkleRoot = try container.decodeIfPresent(String.self, forKey: .sourceMerkleRoot)
        episodeCount = try container.decodeIfPresent(Int.self, forKey: .episodeCount) ?? 0
        atomCount = try container.decodeIfPresent(Int.self, forKey: .atomCount) ?? 0
        worldCount = try container.decodeIfPresent(Int.self, forKey: .worldCount) ?? 0
        truthsetId = try container.decodeIfPresent(String.self, forKey: .truthsetId)
        artifactManifest = try container.decodeIfPresent(String.self, forKey: .artifactManifest)
        lancedbPath = try container.decodeIfPresent(String.self, forKey: .lancedbPath)
        tableName = try container.decodeIfPresent(String.self, forKey: .tableName)
        rowCount = try container.decodeIfPresent(Int.self, forKey: .rowCount) ?? atomCount
        indexReady = try container.decodeIfPresent(Bool.self, forKey: .indexReady) ?? false
        nativeLancedb = try container.decodeIfPresent(Bool.self, forKey: .nativeLancedb) ?? false
        maxsimReady = try container.decodeIfPresent(Bool.self, forKey: .maxsimReady) ?? false
        embeddingBackend = try container.decodeIfPresent(String.self, forKey: .embeddingBackend)
        vectorDim = try container.decodeIfPresent(Int.self, forKey: .vectorDim)
        maxTokens = try container.decodeIfPresent(Int.self, forKey: .maxTokens)
        workerStatus = try container.decodeIfPresent(String.self, forKey: .workerStatus)
        restrictedLeakCount = try container.decodeIfPresent(Int.self, forKey: .restrictedLeakCount) ?? 0
        workerLatencyMs = try container.decodeIfPresent(Double.self, forKey: .workerLatencyMs)
        degradedReason = try container.decodeIfPresent(String.self, forKey: .degradedReason)
    }
}

public struct SemanticIndexStatus: Codable, Equatable, Sendable {
    public let generatedAt: String
    public let schemaVersion: String
    public let status: String
    public let hotPathMode: String?
    public let runtime: String?
    public let model: String?
    public let fallbackModel: String?
    public let rerankerModel: String?
    public let lancedbPath: String?
    public let tableName: String?
    public let rowCount: Int
    public let indexReady: Bool
    public let nativeLancedb: Bool
    public let maxsimReady: Bool
    public let embeddingBackend: String?
    public let latestRun: SemanticIndexRun?
    public let freshness: String?
    public let degradedReason: String?

    enum CodingKeys: String, CodingKey {
        case generatedAt = "generated_at"
        case schemaVersion = "schema_version"
        case status
        case hotPathMode = "hot_path_mode"
        case runtime
        case model
        case fallbackModel = "fallback_model"
        case rerankerModel = "reranker_model"
        case lancedbPath = "lancedb_path"
        case tableName = "table_name"
        case rowCount = "row_count"
        case indexReady = "index_ready"
        case nativeLancedb = "native_lancedb"
        case maxsimReady = "maxsim_ready"
        case embeddingBackend = "embedding_backend"
        case latestRun = "latest_run"
        case freshness
        case degradedReason = "degraded_reason"
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        generatedAt = try container.decodeIfPresent(String.self, forKey: .generatedAt) ?? ""
        schemaVersion = try container.decodeIfPresent(String.self, forKey: .schemaVersion) ?? ""
        status = try container.decodeIfPresent(String.self, forKey: .status) ?? "unknown"
        hotPathMode = try container.decodeIfPresent(String.self, forKey: .hotPathMode)
        runtime = try container.decodeIfPresent(String.self, forKey: .runtime)
        model = try container.decodeIfPresent(String.self, forKey: .model)
        fallbackModel = try container.decodeIfPresent(String.self, forKey: .fallbackModel)
        rerankerModel = try container.decodeIfPresent(String.self, forKey: .rerankerModel)
        lancedbPath = try container.decodeIfPresent(String.self, forKey: .lancedbPath)
        tableName = try container.decodeIfPresent(String.self, forKey: .tableName)
        rowCount = try container.decodeIfPresent(Int.self, forKey: .rowCount) ?? 0
        indexReady = try container.decodeIfPresent(Bool.self, forKey: .indexReady) ?? false
        nativeLancedb = try container.decodeIfPresent(Bool.self, forKey: .nativeLancedb) ?? false
        maxsimReady = try container.decodeIfPresent(Bool.self, forKey: .maxsimReady) ?? false
        embeddingBackend = try container.decodeIfPresent(String.self, forKey: .embeddingBackend)
        latestRun = try container.decodeIfPresent(SemanticIndexRun.self, forKey: .latestRun)
        freshness = try container.decodeIfPresent(String.self, forKey: .freshness)
        degradedReason = try container.decodeIfPresent(String.self, forKey: .degradedReason)
    }
}

public struct MemoryTruthSetSummary: Codable, Equatable, Sendable, Identifiable {
    public let id: String
    public let status: String
    public let title: String
    public let description: String?
    public let domains: [String]
    public let caseCount: Int
    public let approvedCaseCount: Int
    public let artifactRoot: String?
    public let reviewer: String?
    public let rationale: String?

    enum CodingKeys: String, CodingKey {
        case id
        case status
        case title
        case description
        case domains
        case caseCount = "case_count"
        case approvedCaseCount = "approved_case_count"
        case artifactRoot = "artifact_root"
        case reviewer
        case rationale
    }
}

public struct MemoryTruthCaseSummary: Codable, Equatable, Sendable, Identifiable {
    public let id: String
    public let truthsetId: String
    public let status: String
    public let domain: String
    public let query: String
    public let privacyClass: String
    public let tags: [String]

    enum CodingKeys: String, CodingKey {
        case id
        case truthsetId = "truthset_id"
        case status
        case domain
        case query
        case privacyClass = "privacy_class"
        case tags
    }
}

public struct MemoryTruthSetStatus: Codable, Equatable, Sendable {
    public let truthset: MemoryTruthSetSummary
    public let cases: [MemoryTruthCaseSummary]
}

public struct MemoryPromotionGateStatus: Codable, Equatable, Sendable {
    public let truthsetId: String?
    public let promotionGate: MemoryPromotionGate?
    public let hotPathEligible: Bool
}
