//! Memory endpoints for BEAGLE HTTP API

use crate::http::AppState;
use axum::http::StatusCode;
use axum::{extract::{Path, State}, routing::{get, post}, Json, Router};
use beagle_memory::{
    ChatSession, ChatTurn, CodeRetrievalQuery, CodeRetrievalResult,
    COMPILER_EVAL_REPORT_VERSION, COMPILER_POLICY_VERSION, CONTEXT_EVAL_CASE_VERSION,
    CompiledContextPacket, CompiledContextRequest, CompilerEvalReport, CompilerEvalRequest,
    CompilerPolicy, ContextEvalCase,
    ContextBudgetProfile,
    EmbeddingBackendContract, EmbeddingBackendMatrix, ExperimentFlags as MemoryExperimentFlags,
    FeedbackLoopResult, GraphRagQuery, GraphRagQueryModeDecision, GraphRagResult,
    MemoryPromotionPolicy, MemoryQuery, MemoryRetentionPolicy, PhysioSnapshot,
    MemoryCompilerContract, PromotedMemory, RelevanceFeedbackInput, RelevanceFeedbackJudgment,
    RetrievalBenchmarkCase, RetrievalBenchmarkReport,
    RetrievalBenchmarkRequest, RetrievalCollection, RetrievalEvalCase,
    RetrievalEvalReport, RetrievalEvalRequest, RetrievalFilters, RetrievalPolicy,
    RetrievalQuery, RetrievalQueryType, RetrievalResult, RetrievalRoutingDecision,
    RerankedResult, RerankingProfile, RoutedRetrievalQuery,
    RoutedRetrievalResult,
    TemporalMemorySchema, TemporalQuery, TemporalQueryResult,
    SovereignRetrievalBackendProfile, SovereignRetrievalQuery,
    SovereignRetrievalResult, CODE_RETRIEVAL_QUERY_VERSION,
    GRAPHRAG_QUERY_VERSION, RELEVANCE_FEEDBACK_VERSION, RETRIEVAL_BENCHMARK_VERSION,
    RETRIEVAL_EVAL_REPORT_VERSION,
    RETRIEVAL_QUERY_VERSION, ROUTED_RETRIEVAL_QUERY_VERSION,
    SOVEREIGN_RETRIEVAL_QUERY_VERSION,
    TEMPORAL_QUERY_VERSION,
};
use beagle_metrics::{record_memory_query, set_qdrant_health};
use beagle_observer::PhysioSnapshot as ObserverPhysioSnapshot;
use chrono::Utc;
use serde::{Deserialize, Serialize};
use serde_json::json;
use std::time::Instant;
use tracing::error;
#[cfg(not(feature = "memory"))]
use tracing::warn;

#[derive(Debug, Clone, Deserialize, Serialize, Default)]
pub struct MemoryIngestExperimentFlagsInput {
    #[serde(default)]
    pub hrv_aware: Option<bool>,
    #[serde(default)]
    pub serendipity_enabled: Option<bool>,
    #[serde(default)]
    pub triad_enabled: Option<bool>,
}

#[derive(Deserialize)]
pub struct MemoryIngestChatRequest {
    pub source: String,
    pub conversation_id: String,
    pub turn_index: usize,
    pub role: String,
    pub text: String,
    #[serde(default)]
    pub tags: Vec<String>,
    #[serde(default)]
    pub domain: Option<String>,
    #[serde(default)]
    pub provider: Option<String>,
    #[serde(default)]
    pub model: Option<String>,
    #[serde(default)]
    pub experiment_flags: Option<MemoryIngestExperimentFlagsInput>,
    #[serde(default)]
    pub workstream_id: Option<String>,
    #[serde(default)]
    pub campaign_id: Option<String>,
    #[serde(default)]
    pub program_id: Option<String>,
    #[serde(default)]
    pub workspace_id: Option<String>,
    #[serde(default)]
    pub session_id: Option<String>,
    #[serde(default)]
    pub repo_path: Option<String>,
    #[serde(default)]
    pub file_type: Option<String>,
    #[serde(default)]
    pub physio_snapshot_ref: Option<String>,
    #[serde(default)]
    pub result_refs: Vec<String>,
    #[serde(default)]
    pub claim_refs: Vec<String>,
}

#[derive(Serialize)]
pub struct MemoryIngestChatResponse {
    pub status: String,
    pub memory_id: Option<String>,
    pub conversation_id: String,
    pub turn_index: usize,
    pub role: String,
    pub searchable: bool,
    pub physio_attached: bool,
    pub experiment_flags_attached: bool,
}

#[derive(Deserialize)]
pub struct MemoryQueryRequest {
    pub query: String,
    #[serde(default)]
    pub limit: Option<usize>,
    #[serde(default)]
    pub top_k: Option<usize>,
    #[serde(default)]
    pub max_items: Option<usize>,
    #[serde(default)]
    pub domain: Option<String>,
    #[serde(default)]
    pub tags: Vec<String>,
    #[serde(default)]
    pub include_recent_physio: bool,
    #[serde(default)]
    pub scope: Option<String>,
}

#[derive(Debug, Clone, Deserialize, Serialize, Default)]
pub struct RetrievalFiltersRequest {
    #[serde(default)]
    pub workstream_id: Option<String>,
    #[serde(default)]
    pub campaign_id: Option<String>,
    #[serde(default)]
    pub session_id: Option<String>,
    #[serde(default)]
    pub source: Option<String>,
    #[serde(default)]
    pub role: Option<String>,
    #[serde(default)]
    pub domain: Option<String>,
    #[serde(default)]
    pub repo_path: Option<String>,
    #[serde(default)]
    pub file_type: Option<String>,
    #[serde(default)]
    pub tags: Vec<String>,
}

#[derive(Debug, Clone, Deserialize, Serialize)]
pub struct RetrievalQueryRequest {
    #[serde(default)]
    pub query_version: Option<String>,
    #[serde(alias = "query")]
    pub query_text: String,
    #[serde(default)]
    pub top_k: Option<usize>,
    #[serde(default)]
    pub limit: Option<usize>,
    #[serde(default = "default_retrieval_dense_enabled")]
    pub dense_enabled: bool,
    #[serde(default = "default_retrieval_sparse_enabled")]
    pub sparse_enabled: bool,
    #[serde(default = "default_retrieval_dense_weight")]
    pub dense_weight: f32,
    #[serde(default = "default_retrieval_sparse_weight")]
    pub sparse_weight: f32,
    #[serde(default)]
    pub filters: RetrievalFiltersRequest,
    #[serde(default)]
    pub rerank_hint: Option<String>,
}

#[derive(Debug, Clone, Deserialize, Serialize)]
pub struct CodeRetrievalQueryRequest {
    #[serde(default)]
    pub query_version: Option<String>,
    #[serde(alias = "query")]
    pub query_text: String,
    #[serde(default)]
    pub top_k: Option<usize>,
    #[serde(default)]
    pub limit: Option<usize>,
    #[serde(default = "default_retrieval_dense_enabled")]
    pub dense_enabled: bool,
    #[serde(default = "default_retrieval_sparse_enabled")]
    pub sparse_enabled: bool,
    #[serde(default = "default_code_retrieval_dense_weight")]
    pub dense_weight: f32,
    #[serde(default = "default_code_retrieval_sparse_weight")]
    pub sparse_weight: f32,
    #[serde(default)]
    pub filters: RetrievalFiltersRequest,
    #[serde(default)]
    pub compare_against_general: bool,
    #[serde(default)]
    pub rerank_hint: Option<String>,
}

#[derive(Debug, Clone, Deserialize, Serialize)]
pub struct SovereignRetrievalQueryRequest {
    #[serde(default)]
    pub query_version: Option<String>,
    #[serde(alias = "query")]
    pub query_text: String,
    #[serde(default)]
    pub top_k: Option<usize>,
    #[serde(default)]
    pub limit: Option<usize>,
    #[serde(default = "default_retrieval_dense_enabled")]
    pub dense_enabled: bool,
    #[serde(default = "default_retrieval_sparse_enabled")]
    pub sparse_enabled: bool,
    #[serde(default = "default_sovereign_retrieval_dense_weight")]
    pub dense_weight: f32,
    #[serde(default = "default_sovereign_retrieval_sparse_weight")]
    pub sparse_weight: f32,
    #[serde(default)]
    pub filters: RetrievalFiltersRequest,
    #[serde(default)]
    pub compare_against_general: bool,
    #[serde(default)]
    pub rerank_hint: Option<String>,
}

#[derive(Debug, Clone, Deserialize, Serialize)]
pub struct RoutedRetrievalQueryRequest {
    #[serde(default)]
    pub query_version: Option<String>,
    #[serde(alias = "query")]
    pub query_text: String,
    #[serde(default)]
    pub top_k: Option<usize>,
    #[serde(default)]
    pub limit: Option<usize>,
    #[serde(default = "default_retrieval_dense_enabled")]
    pub dense_enabled: bool,
    #[serde(default = "default_retrieval_sparse_enabled")]
    pub sparse_enabled: bool,
    #[serde(default = "default_retrieval_dense_weight")]
    pub dense_weight: f32,
    #[serde(default = "default_retrieval_sparse_weight")]
    pub sparse_weight: f32,
    #[serde(default)]
    pub filters: RetrievalFiltersRequest,
    #[serde(default)]
    pub query_type_hint: Option<String>,
    #[serde(default)]
    pub compare_against_general: bool,
    #[serde(default)]
    pub rerank_hint: Option<String>,
}

#[derive(Debug, Clone, Deserialize, Serialize)]
pub struct RetrievalBenchmarkCaseRequest {
    pub case_id: String,
    pub case_kind: String,
    #[serde(default)]
    pub description: Option<String>,
    #[serde(flatten)]
    pub query: RetrievalQueryRequest,
    #[serde(default)]
    pub expected_memory_ids: Vec<String>,
}

#[derive(Debug, Clone, Deserialize, Serialize)]
pub struct RetrievalBenchmarkRequestBody {
    #[serde(default)]
    pub benchmark_version: Option<String>,
    #[serde(default)]
    pub top_k_stability_runs: Option<usize>,
    #[serde(default)]
    pub reranking_profile_id: Option<String>,
    #[serde(default)]
    pub cases: Vec<RetrievalBenchmarkCaseRequest>,
}

#[derive(Debug, Clone, Deserialize, Serialize)]
pub struct RetrievalEvalCaseRequest {
    pub case_id: String,
    pub query_type: String,
    #[serde(default)]
    pub description: Option<String>,
    #[serde(flatten)]
    pub query: RoutedRetrievalQueryRequest,
    #[serde(default)]
    pub expected_memory_ids: Vec<String>,
}

#[derive(Debug, Clone, Deserialize, Serialize)]
pub struct RetrievalEvalRequestBody {
    #[serde(default)]
    pub report_version: Option<String>,
    #[serde(default)]
    pub top_k_stability_runs: Option<usize>,
    #[serde(default)]
    pub cases: Vec<RetrievalEvalCaseRequest>,
}

#[derive(Debug, Clone, Deserialize, Serialize)]
pub struct ContextEvalCaseRequest {
    pub case_id: String,
    pub task_profile: String,
    #[serde(default)]
    pub description: Option<String>,
    pub request: CompiledContextRequest,
    #[serde(default)]
    pub expected_memory_ids: Vec<String>,
    pub preferred_truth_view: String,
    pub preferred_graphrag_mode: String,
    #[serde(default)]
    pub preferred_memory_tiers: Vec<String>,
    #[serde(default)]
    pub expected_retrieval_query_type: Option<String>,
}

#[derive(Debug, Clone, Deserialize, Serialize)]
pub struct CompilerEvalRequestBody {
    #[serde(default)]
    pub report_version: Option<String>,
    #[serde(default)]
    pub top_k_stability_runs: Option<usize>,
    #[serde(default)]
    pub cases: Vec<ContextEvalCaseRequest>,
}

#[derive(Debug, Clone, Deserialize, Serialize)]
pub struct RelevanceFeedbackJudgmentRequest {
    pub memory_id: String,
    pub signal: String,
    #[serde(default = "default_feedback_score")]
    pub score: f32,
    #[serde(default)]
    pub rationale: Option<String>,
}

#[derive(Debug, Clone, Deserialize, Serialize)]
pub struct RelevanceFeedbackInputRequest {
    #[serde(default)]
    pub feedback_version: Option<String>,
    #[serde(default)]
    pub feedback_round: Option<usize>,
    #[serde(flatten)]
    pub query: RoutedRetrievalQueryRequest,
    #[serde(default)]
    pub expected_memory_ids: Vec<String>,
    #[serde(default)]
    pub judgments: Vec<RelevanceFeedbackJudgmentRequest>,
    #[serde(default)]
    pub note: Option<String>,
}

#[derive(Debug, Clone, Deserialize, Serialize)]
pub struct GraphRagQueryRequest {
    #[serde(default)]
    pub query_version: Option<String>,
    #[serde(alias = "query")]
    pub query_text: String,
    #[serde(default)]
    pub top_k: Option<usize>,
    #[serde(default)]
    pub limit: Option<usize>,
    #[serde(default)]
    pub max_hops: Option<usize>,
    #[serde(default = "default_retrieval_dense_enabled")]
    pub dense_enabled: bool,
    #[serde(default = "default_retrieval_sparse_enabled")]
    pub sparse_enabled: bool,
    #[serde(default = "default_retrieval_dense_weight")]
    pub dense_weight: f32,
    #[serde(default = "default_retrieval_sparse_weight")]
    pub sparse_weight: f32,
    #[serde(default)]
    pub filters: RetrievalFiltersRequest,
    #[serde(default)]
    pub root_entity_type: Option<String>,
    #[serde(default)]
    pub root_entity_id: Option<String>,
    #[serde(default)]
    pub program_id: Option<String>,
    #[serde(default = "default_true")]
    pub include_memory_hierarchy: bool,
    #[serde(default)]
    pub query_type_hint: Option<String>,
    #[serde(default)]
    pub query_mode_hint: Option<String>,
    #[serde(default)]
    pub rerank_hint: Option<String>,
}

#[derive(Debug, Clone, Deserialize, Serialize)]
pub struct MemoryPromotionEvaluateRequest {
    pub memory_id: String,
}

#[derive(Debug, Clone, Deserialize, Serialize)]
pub struct TemporalQueryRequest {
    #[serde(default)]
    pub query_version: Option<String>,
    #[serde(alias = "query")]
    pub query_text: String,
    #[serde(default)]
    pub truth_view: Option<String>,
    #[serde(default)]
    pub top_k: Option<usize>,
    #[serde(default)]
    pub limit: Option<usize>,
    #[serde(default = "default_retrieval_dense_enabled")]
    pub dense_enabled: bool,
    #[serde(default = "default_retrieval_sparse_enabled")]
    pub sparse_enabled: bool,
    #[serde(default = "default_retrieval_dense_weight")]
    pub dense_weight: f32,
    #[serde(default = "default_retrieval_sparse_weight")]
    pub sparse_weight: f32,
    #[serde(default)]
    pub filters: RetrievalFiltersRequest,
    #[serde(default)]
    pub root_entity_type: Option<String>,
    #[serde(default)]
    pub root_entity_id: Option<String>,
    #[serde(default)]
    pub subject_refs: Vec<String>,
    #[serde(default = "default_true")]
    pub include_contradictions: bool,
    #[serde(default)]
    pub query_type_hint: Option<String>,
    #[serde(default)]
    pub query_mode_hint: Option<String>,
    #[serde(default)]
    pub rerank_hint: Option<String>,
}

pub async fn memory_compiler_contract_handler(
    State(state): State<AppState>,
) -> Result<Json<MemoryCompilerContract>, StatusCode> {
    let ctx = state.ctx.lock().await;

    #[cfg(feature = "memory")]
    {
        match ctx.memory_compiler_contract() {
            Ok(contract) => Ok(Json(contract)),
            Err(error) => {
                error!("Failed to load memory compiler contract: {}", error);
                Err(StatusCode::INTERNAL_SERVER_ERROR)
            }
        }
    }

    #[cfg(not(feature = "memory"))]
    {
        warn!("Memory feature not enabled");
        Err(StatusCode::NOT_IMPLEMENTED)
    }
}

pub async fn memory_context_budget_profile_handler(
    State(state): State<AppState>,
    Path(task_profile): Path<String>,
) -> Result<Json<ContextBudgetProfile>, StatusCode> {
    let ctx = state.ctx.lock().await;

    #[cfg(feature = "memory")]
    {
        match ctx.memory_context_budget_profile(&task_profile) {
            Ok(profile) => Ok(Json(profile)),
            Err(error) => {
                error!(
                    "Failed to load context budget profile {}: {}",
                    task_profile, error
                );
                Err(StatusCode::BAD_REQUEST)
            }
        }
    }

    #[cfg(not(feature = "memory"))]
    {
        warn!("Memory feature not enabled");
        Err(StatusCode::NOT_IMPLEMENTED)
    }
}

pub async fn memory_compile_context_handler(
    State(state): State<AppState>,
    Json(req): Json<CompiledContextRequest>,
) -> Result<Json<CompiledContextPacket>, StatusCode> {
    let ctx = state.ctx.lock().await;
    let task_profile = trim_required(&req.task_profile)?;
    let query_text = trim_required(&req.query_text)?;
    let request = CompiledContextRequest {
        task_profile,
        tool_id: req.tool_id,
        query_text,
        workstream_id: req.workstream_id,
        campaign_id: req.campaign_id,
        program_id: req.program_id,
        workspace_id: req.workspace_id,
        session_id: req.session_id,
        root_entity_type: req.root_entity_type,
        root_entity_id: req.root_entity_id,
        repo_path: req.repo_path,
        file_type: req.file_type,
        tags: req.tags,
        rerank_hint: req.rerank_hint,
    };

    #[cfg(feature = "memory")]
    {
        match ctx.memory_compile_context(request).await {
            Ok(result) => Ok(Json(result)),
            Err(error) => {
                error!("Failed to compile task-aware memory context: {}", error);
                Err(StatusCode::INTERNAL_SERVER_ERROR)
            }
        }
    }

    #[cfg(not(feature = "memory"))]
    {
        warn!("Memory feature not enabled");
        Err(StatusCode::NOT_IMPLEMENTED)
    }
}

pub async fn memory_ingest_chat_handler(
    State(state): State<AppState>,
    Json(req): Json<MemoryIngestChatRequest>,
) -> Result<Json<MemoryIngestChatResponse>, StatusCode> {
    let source = normalize_source(&req.source)?;
    let role = normalize_role(&req.role)?;
    let conversation_id = trim_required(&req.conversation_id)?;
    let text = trim_required(&req.text)?;
    let physio_snapshot = latest_physio_snapshot(&state).await;
    let ctx = state.ctx.lock().await;
    let experiment_flags = build_experiment_flags(
        &ctx.cfg,
        req.experiment_flags.as_ref(),
        req.provider.clone(),
        req.model.clone(),
    );

    let session = ChatSession {
        source: source.clone(),
        session_id: conversation_id.clone(),
        turns: vec![ChatTurn {
            role: role.clone(),
            content: text,
            timestamp: Some(Utc::now()),
            model: req.model.clone(),
            turn_index: Some(req.turn_index),
        }],
        tags: req.tags,
        metadata: json!({
            "domain": req.domain,
            "provider": req.provider,
            "model": req.model,
            "physio_snapshot": physio_snapshot,
            "experiment_flags": experiment_flags,
            "workstream_id": req.workstream_id,
            "campaign_id": req.campaign_id,
            "program_id": req.program_id,
            "workspace_id": req.workspace_id,
            "session_id": req.session_id,
            "repo_path": req.repo_path,
            "file_type": req.file_type,
            "physio_snapshot_ref": req.physio_snapshot_ref,
            "result_refs": req.result_refs,
            "claim_refs": req.claim_refs,
        }),
    };

    #[cfg(feature = "memory")]
    {
        match ctx.memory_ingest_session(session).await {
            Ok(stats) => Ok(Json(MemoryIngestChatResponse {
                status: "ok".to_string(),
                memory_id: stats.memory_id,
                conversation_id,
                turn_index: req.turn_index,
                role,
                searchable: stats.searchable,
                physio_attached: stats.physio_attached,
                experiment_flags_attached: stats.experiment_flags_attached,
            })),
            Err(e) => {
                error!("Failed to ingest chat: {}", e);
                Err(StatusCode::INTERNAL_SERVER_ERROR)
            }
        }
    }

    #[cfg(not(feature = "memory"))]
    {
        warn!("Memory feature not enabled");
        Err(StatusCode::NOT_IMPLEMENTED)
    }
}

pub async fn memory_query_handler(
    State(state): State<AppState>,
    Json(req): Json<MemoryQueryRequest>,
) -> Result<Json<beagle_memory::MemoryResult>, StatusCode> {
    let start = Instant::now();
    let query_text = trim_required(&req.query)?;
    let limit = normalize_limit(&req);
    let ctx = state.ctx.lock().await;

    let query = MemoryQuery {
        query: query_text,
        scope: req.scope.or_else(|| req.domain.clone()),
        max_items: Some(limit),
        domain: req.domain,
        tags: req.tags,
        include_recent_physio: req.include_recent_physio,
    };

    #[cfg(feature = "memory")]
    {
        match ctx.memory_query(query).await {
            Ok(mut result) => {
                let duration = start.elapsed();
                // Record metrics for successful memory query
                // Determine source based on the query execution path
                record_memory_query("qdrant", "success", duration);

                if req.include_recent_physio {
                    result.recent_physio = latest_physio_snapshot(&state).await;
                }
                Ok(Json(result))
            }
            Err(e) => {
                let duration = start.elapsed();
                error!("Failed to query memory: {}", e);
                // Record metrics for failed memory query
                record_memory_query("qdrant", "error", duration);
                Err(StatusCode::INTERNAL_SERVER_ERROR)
            }
        }
    }

    #[cfg(not(feature = "memory"))]
    {
        let duration = start.elapsed();
        warn!("Memory feature not enabled");
        record_memory_query("qdrant", "not_implemented", duration);
        Err(StatusCode::NOT_IMPLEMENTED)
    }
}

pub async fn memory_qdrant_health_handler(
    State(state): State<AppState>,
) -> Result<Json<beagle_memory::MemoryQdrantHealth>, StatusCode> {
    let ctx = state.ctx.lock().await;
    #[cfg(feature = "memory")]
    {
        let health = ctx.memory_qdrant_health().await;
        // Update Qdrant health status metric (1=healthy, 0=unhealthy)
        let is_healthy = health.status == "healthy" || health.status == "ok";
        set_qdrant_health(is_healthy);
        Ok(Json(health))
    }
    #[cfg(not(feature = "memory"))]
    {
        warn!("Memory feature not enabled");
        set_qdrant_health(false);
        Err(StatusCode::NOT_IMPLEMENTED)
    }
}

pub async fn memory_compiler_eval_handler(
    State(state): State<AppState>,
    Json(req): Json<CompilerEvalRequestBody>,
) -> Result<Json<CompilerEvalReport>, StatusCode> {
    let ctx = state.ctx.lock().await;
    let request = CompilerEvalRequest {
        report_version: req
            .report_version
            .unwrap_or_else(|| COMPILER_EVAL_REPORT_VERSION.to_string()),
        top_k_stability_runs: req.top_k_stability_runs.unwrap_or(1),
        cases: req
            .cases
            .into_iter()
            .map(context_eval_case_from_request)
            .collect::<Result<Vec<_>, _>>()?,
    };

    #[cfg(feature = "memory")]
    {
        match ctx.memory_evaluate_compiler_policies(request).await {
            Ok(report) => Ok(Json(report)),
            Err(error) => {
                error!("Failed to run compiler context quality evals: {}", error);
                Err(StatusCode::INTERNAL_SERVER_ERROR)
            }
        }
    }

    #[cfg(not(feature = "memory"))]
    {
        warn!("Memory feature not enabled");
        Err(StatusCode::NOT_IMPLEMENTED)
    }
}

pub async fn memory_compiler_policy_handler(
    State(state): State<AppState>,
    Json(report): Json<CompilerEvalReport>,
) -> Result<Json<CompilerPolicy>, StatusCode> {
    let ctx = state.ctx.lock().await;

    #[cfg(feature = "memory")]
    {
        match ctx.memory_derive_compiler_policy(&report) {
            Ok(policy) => Ok(Json(policy)),
            Err(error) => {
                error!("Failed to derive compiler policy from eval report: {}", error);
                Err(StatusCode::INTERNAL_SERVER_ERROR)
            }
        }
    }

    #[cfg(not(feature = "memory"))]
    {
        warn!("Memory feature not enabled");
        Err(StatusCode::NOT_IMPLEMENTED)
    }
}

pub async fn memory_retrieval_collection_handler(
    State(state): State<AppState>,
) -> Result<Json<RetrievalCollection>, StatusCode> {
    let ctx = state.ctx.lock().await;

    #[cfg(feature = "memory")]
    {
        match ctx.memory_retrieval_collection() {
            Ok(collection) => Ok(Json(collection)),
            Err(error) => {
                error!("Failed to describe retrieval collection: {}", error);
                Err(StatusCode::INTERNAL_SERVER_ERROR)
            }
        }
    }

    #[cfg(not(feature = "memory"))]
    {
        warn!("Memory feature not enabled");
        Err(StatusCode::NOT_IMPLEMENTED)
    }
}

pub async fn memory_retrieval_query_handler(
    State(state): State<AppState>,
    Json(req): Json<RetrievalQueryRequest>,
) -> Result<Json<RetrievalResult>, StatusCode> {
    let query_text = trim_required(&req.query_text)?;
    let top_k = req.limit.or(req.top_k).unwrap_or(5).clamp(1, 10);
    let ctx = state.ctx.lock().await;
    let query = RetrievalQuery {
        query_version: req
            .query_version
            .unwrap_or_else(|| RETRIEVAL_QUERY_VERSION.to_string()),
        query_text,
        top_k,
        dense_enabled: req.dense_enabled,
        sparse_enabled: req.sparse_enabled,
        dense_weight: req.dense_weight,
        sparse_weight: req.sparse_weight,
        filters: RetrievalFilters {
            workstream_id: req.filters.workstream_id,
            campaign_id: req.filters.campaign_id,
            session_id: req.filters.session_id,
            source: req.filters.source,
            role: req.filters.role,
            domain: req.filters.domain,
            repo_path: req.filters.repo_path,
            file_type: req.filters.file_type,
            tags: req.filters.tags,
        },
        rerank_hint: req.rerank_hint,
    };

    #[cfg(feature = "memory")]
    {
        match ctx.memory_hybrid_retrieve(query).await {
            Ok(result) => Ok(Json(result)),
            Err(error) => {
                error!("Failed to run hybrid retrieval query: {}", error);
                Err(StatusCode::INTERNAL_SERVER_ERROR)
            }
        }
    }

    #[cfg(not(feature = "memory"))]
    {
        warn!("Memory feature not enabled");
        Err(StatusCode::NOT_IMPLEMENTED)
    }
}

pub async fn memory_code_retrieval_query_handler(
    State(state): State<AppState>,
    Json(req): Json<CodeRetrievalQueryRequest>,
) -> Result<Json<CodeRetrievalResult>, StatusCode> {
    let query_text = trim_required(&req.query_text)?;
    let top_k = req.limit.or(req.top_k).unwrap_or(5).clamp(1, 10);
    let ctx = state.ctx.lock().await;
    let query = CodeRetrievalQuery {
        query_version: req
            .query_version
            .unwrap_or_else(|| CODE_RETRIEVAL_QUERY_VERSION.to_string()),
        query_text,
        top_k,
        dense_enabled: req.dense_enabled,
        sparse_enabled: req.sparse_enabled,
        dense_weight: req.dense_weight,
        sparse_weight: req.sparse_weight,
        filters: RetrievalFilters {
            workstream_id: req.filters.workstream_id,
            campaign_id: req.filters.campaign_id,
            session_id: req.filters.session_id,
            source: req.filters.source,
            role: req.filters.role,
            domain: req.filters.domain,
            repo_path: req.filters.repo_path,
            file_type: req.filters.file_type,
            tags: req.filters.tags,
        },
        compare_against_general: req.compare_against_general,
        rerank_hint: req.rerank_hint,
    };

    #[cfg(feature = "memory")]
    {
        match ctx.memory_code_retrieve(query).await {
            Ok(result) => Ok(Json(result)),
            Err(error) => {
                error!("Failed to run code retrieval query: {}", error);
                Err(StatusCode::INTERNAL_SERVER_ERROR)
            }
        }
    }

    #[cfg(not(feature = "memory"))]
    {
        warn!("Memory feature not enabled");
        Err(StatusCode::NOT_IMPLEMENTED)
    }
}

pub async fn memory_sovereign_retrieval_backend_handler(
    State(state): State<AppState>,
) -> Result<Json<SovereignRetrievalBackendProfile>, StatusCode> {
    let ctx = state.ctx.lock().await;

    #[cfg(feature = "memory")]
    {
        match ctx.memory_sovereign_retrieval_backend_profile() {
            Ok(profile) => Ok(Json(profile)),
            Err(error) => {
                error!("Failed to describe sovereign retrieval backend: {}", error);
                Err(StatusCode::INTERNAL_SERVER_ERROR)
            }
        }
    }

    #[cfg(not(feature = "memory"))]
    {
        warn!("Memory feature not enabled");
        Err(StatusCode::NOT_IMPLEMENTED)
    }
}

pub async fn memory_sovereign_retrieval_query_handler(
    State(state): State<AppState>,
    Json(req): Json<SovereignRetrievalQueryRequest>,
) -> Result<Json<SovereignRetrievalResult>, StatusCode> {
    let query_text = trim_required(&req.query_text)?;
    let top_k = req.limit.or(req.top_k).unwrap_or(5).clamp(1, 10);
    let ctx = state.ctx.lock().await;
    let query = SovereignRetrievalQuery {
        query_version: req
            .query_version
            .unwrap_or_else(|| SOVEREIGN_RETRIEVAL_QUERY_VERSION.to_string()),
        query_text,
        top_k,
        dense_enabled: req.dense_enabled,
        sparse_enabled: req.sparse_enabled,
        dense_weight: req.dense_weight,
        sparse_weight: req.sparse_weight,
        filters: RetrievalFilters {
            workstream_id: req.filters.workstream_id,
            campaign_id: req.filters.campaign_id,
            session_id: req.filters.session_id,
            source: req.filters.source,
            role: req.filters.role,
            domain: req.filters.domain,
            repo_path: req.filters.repo_path,
            file_type: req.filters.file_type,
            tags: req.filters.tags,
        },
        compare_against_general: req.compare_against_general,
        rerank_hint: req.rerank_hint,
    };

    #[cfg(feature = "memory")]
    {
        match ctx.memory_sovereign_retrieve(query).await {
            Ok(result) => Ok(Json(result)),
            Err(error) => {
                error!("Failed to run sovereign retrieval query: {}", error);
                Err(StatusCode::INTERNAL_SERVER_ERROR)
            }
        }
    }

    #[cfg(not(feature = "memory"))]
    {
        warn!("Memory feature not enabled");
        Err(StatusCode::NOT_IMPLEMENTED)
    }
}

pub async fn memory_retrieval_query_type_handler(
    State(state): State<AppState>,
    Json(req): Json<RoutedRetrievalQueryRequest>,
) -> Result<Json<RetrievalQueryType>, StatusCode> {
    let ctx = state.ctx.lock().await;
    let query = routed_retrieval_query_from_request(req)?;

    #[cfg(feature = "memory")]
    {
        match ctx.memory_classify_retrieval_query(&query) {
            Ok(result) => Ok(Json(result)),
            Err(error) => {
                error!("Failed to classify routed retrieval query: {}", error);
                Err(StatusCode::INTERNAL_SERVER_ERROR)
            }
        }
    }

    #[cfg(not(feature = "memory"))]
    {
        warn!("Memory feature not enabled");
        Err(StatusCode::NOT_IMPLEMENTED)
    }
}

pub async fn memory_retrieval_routing_decision_handler(
    State(state): State<AppState>,
    Json(req): Json<RoutedRetrievalQueryRequest>,
) -> Result<Json<RetrievalRoutingDecision>, StatusCode> {
    let ctx = state.ctx.lock().await;
    let query = routed_retrieval_query_from_request(req)?;

    #[cfg(feature = "memory")]
    {
        match ctx.memory_retrieval_routing_decision(&query) {
            Ok(result) => Ok(Json(result)),
            Err(error) => {
                error!("Failed to resolve retrieval routing decision: {}", error);
                Err(StatusCode::INTERNAL_SERVER_ERROR)
            }
        }
    }

    #[cfg(not(feature = "memory"))]
    {
        warn!("Memory feature not enabled");
        Err(StatusCode::NOT_IMPLEMENTED)
    }
}

pub async fn memory_routed_retrieval_query_handler(
    State(state): State<AppState>,
    Json(req): Json<RoutedRetrievalQueryRequest>,
) -> Result<Json<RoutedRetrievalResult>, StatusCode> {
    let ctx = state.ctx.lock().await;
    let query = routed_retrieval_query_from_request(req)?;

    #[cfg(feature = "memory")]
    {
        match ctx.memory_routed_retrieve(query).await {
            Ok(result) => Ok(Json(result)),
            Err(error) => {
                error!("Failed to run routed retrieval query: {}", error);
                Err(StatusCode::INTERNAL_SERVER_ERROR)
            }
        }
    }

    #[cfg(not(feature = "memory"))]
    {
        warn!("Memory feature not enabled");
        Err(StatusCode::NOT_IMPLEMENTED)
    }
}

pub async fn memory_retrieval_backend_matrix_handler(
    State(state): State<AppState>,
) -> Result<Json<EmbeddingBackendMatrix>, StatusCode> {
    let ctx = state.ctx.lock().await;

    #[cfg(feature = "memory")]
    {
        match ctx.memory_embedding_backend_matrix() {
            Ok(matrix) => Ok(Json(matrix)),
            Err(error) => {
                error!("Failed to describe retrieval backend matrix: {}", error);
                Err(StatusCode::INTERNAL_SERVER_ERROR)
            }
        }
    }

    #[cfg(not(feature = "memory"))]
    {
        warn!("Memory feature not enabled");
        Err(StatusCode::NOT_IMPLEMENTED)
    }
}

pub async fn memory_retrieval_dense_backend_handler(
    State(state): State<AppState>,
) -> Result<Json<EmbeddingBackendContract>, StatusCode> {
    let ctx = state.ctx.lock().await;

    #[cfg(feature = "memory")]
    {
        match ctx.memory_embedding_backend_contract() {
            Ok(contract) => Ok(Json(contract)),
            Err(error) => {
                error!("Failed to describe dense backend contract: {}", error);
                Err(StatusCode::INTERNAL_SERVER_ERROR)
            }
        }
    }

    #[cfg(not(feature = "memory"))]
    {
        warn!("Memory feature not enabled");
        Err(StatusCode::NOT_IMPLEMENTED)
    }
}

pub async fn memory_retrieval_reranking_profile_handler(
    State(state): State<AppState>,
) -> Result<Json<RerankingProfile>, StatusCode> {
    let ctx = state.ctx.lock().await;

    #[cfg(feature = "memory")]
    {
        match ctx.memory_reranking_profile() {
            Ok(profile) => Ok(Json(profile)),
            Err(error) => {
                error!("Failed to describe retrieval reranking profile: {}", error);
                Err(StatusCode::INTERNAL_SERVER_ERROR)
            }
        }
    }

    #[cfg(not(feature = "memory"))]
    {
        warn!("Memory feature not enabled");
        Err(StatusCode::NOT_IMPLEMENTED)
    }
}

pub async fn memory_reranked_retrieval_query_handler(
    State(state): State<AppState>,
    Json(req): Json<RoutedRetrievalQueryRequest>,
) -> Result<Json<RerankedResult>, StatusCode> {
    let ctx = state.ctx.lock().await;
    let query = routed_retrieval_query_from_request(req)?;

    #[cfg(feature = "memory")]
    {
        match ctx.memory_reranked_routed_retrieve(query).await {
            Ok(result) => Ok(Json(result)),
            Err(error) => {
                error!("Failed to execute bounded reranking pilot: {}", error);
                Err(StatusCode::INTERNAL_SERVER_ERROR)
            }
        }
    }

    #[cfg(not(feature = "memory"))]
    {
        warn!("Memory feature not enabled");
        Err(StatusCode::NOT_IMPLEMENTED)
    }
}

pub async fn memory_retrieval_benchmark_handler(
    State(state): State<AppState>,
    Json(req): Json<RetrievalBenchmarkRequestBody>,
) -> Result<Json<RetrievalBenchmarkReport>, StatusCode> {
    let ctx = state.ctx.lock().await;
    let request = RetrievalBenchmarkRequest {
        benchmark_version: req
            .benchmark_version
            .unwrap_or_else(|| RETRIEVAL_BENCHMARK_VERSION.to_string()),
        top_k_stability_runs: req.top_k_stability_runs.unwrap_or(2),
        reranking_profile_id: req.reranking_profile_id,
        cases: req
            .cases
            .into_iter()
            .map(retrieval_benchmark_case_from_request)
            .collect::<Result<Vec<_>, _>>()?,
    };

    #[cfg(feature = "memory")]
    {
        match ctx.memory_retrieval_benchmark(request).await {
            Ok(report) => Ok(Json(report)),
            Err(error) => {
                error!("Failed to run retrieval benchmark harness: {}", error);
                Err(StatusCode::INTERNAL_SERVER_ERROR)
            }
        }
    }

    #[cfg(not(feature = "memory"))]
    {
        warn!("Memory feature not enabled");
        Err(StatusCode::NOT_IMPLEMENTED)
    }
}

pub async fn memory_retrieval_eval_handler(
    State(state): State<AppState>,
    Json(req): Json<RetrievalEvalRequestBody>,
) -> Result<Json<RetrievalEvalReport>, StatusCode> {
    let ctx = state.ctx.lock().await;
    let request = RetrievalEvalRequest {
        report_version: req
            .report_version
            .unwrap_or_else(|| RETRIEVAL_EVAL_REPORT_VERSION.to_string()),
        top_k_stability_runs: req.top_k_stability_runs.unwrap_or(1),
        cases: req
            .cases
            .into_iter()
            .map(retrieval_eval_case_from_request)
            .collect::<Result<Vec<_>, _>>()?,
    };

    #[cfg(feature = "memory")]
    {
        match ctx.memory_retrieval_evaluate(request).await {
            Ok(report) => Ok(Json(report)),
            Err(error) => {
                error!("Failed to run retrieval evaluation loop: {}", error);
                Err(StatusCode::INTERNAL_SERVER_ERROR)
            }
        }
    }

    #[cfg(not(feature = "memory"))]
    {
        warn!("Memory feature not enabled");
        Err(StatusCode::NOT_IMPLEMENTED)
    }
}

pub async fn memory_relevance_feedback_handler(
    State(state): State<AppState>,
    Json(req): Json<RelevanceFeedbackInputRequest>,
) -> Result<Json<FeedbackLoopResult>, StatusCode> {
    let ctx = state.ctx.lock().await;
    let request = relevance_feedback_input_from_request(req)?;

    #[cfg(feature = "memory")]
    {
        match ctx.memory_feedback_adjusted_routed_retrieve(request).await {
            Ok(result) => Ok(Json(result)),
            Err(error) => {
                error!("Failed to execute retrieval relevance feedback loop: {}", error);
                Err(StatusCode::INTERNAL_SERVER_ERROR)
            }
        }
    }

    #[cfg(not(feature = "memory"))]
    {
        warn!("Memory feature not enabled");
        Err(StatusCode::NOT_IMPLEMENTED)
    }
}

pub async fn memory_retrieval_policy_handler(
    State(state): State<AppState>,
    Json(report): Json<RetrievalEvalReport>,
) -> Result<Json<RetrievalPolicy>, StatusCode> {
    let ctx = state.ctx.lock().await;

    #[cfg(feature = "memory")]
    {
        match ctx.memory_derive_retrieval_policy(&report) {
            Ok(policy) => Ok(Json(policy)),
            Err(error) => {
                error!("Failed to derive evidence-backed retrieval policy: {}", error);
                Err(StatusCode::INTERNAL_SERVER_ERROR)
            }
        }
    }

    #[cfg(not(feature = "memory"))]
    {
        warn!("Memory feature not enabled");
        Err(StatusCode::NOT_IMPLEMENTED)
    }
}

pub async fn memory_promotion_policy_handler(
    State(state): State<AppState>,
) -> Result<Json<MemoryPromotionPolicy>, StatusCode> {
    let ctx = state.ctx.lock().await;

    #[cfg(feature = "memory")]
    {
        match ctx.memory_promotion_policy() {
            Ok(policy) => Ok(Json(policy)),
            Err(error) => {
                error!("Failed to load memory promotion policy: {}", error);
                Err(StatusCode::INTERNAL_SERVER_ERROR)
            }
        }
    }

    #[cfg(not(feature = "memory"))]
    {
        warn!("Memory feature not enabled");
        Err(StatusCode::NOT_IMPLEMENTED)
    }
}

pub async fn memory_retention_policy_handler(
    State(state): State<AppState>,
) -> Result<Json<MemoryRetentionPolicy>, StatusCode> {
    let ctx = state.ctx.lock().await;

    #[cfg(feature = "memory")]
    {
        match ctx.memory_retention_policy() {
            Ok(policy) => Ok(Json(policy)),
            Err(error) => {
                error!("Failed to load memory retention policy: {}", error);
                Err(StatusCode::INTERNAL_SERVER_ERROR)
            }
        }
    }

    #[cfg(not(feature = "memory"))]
    {
        warn!("Memory feature not enabled");
        Err(StatusCode::NOT_IMPLEMENTED)
    }
}

pub async fn memory_temporal_schema_handler(
    State(state): State<AppState>,
) -> Result<Json<TemporalMemorySchema>, StatusCode> {
    let ctx = state.ctx.lock().await;

    #[cfg(feature = "memory")]
    {
        match ctx.memory_temporal_schema() {
            Ok(schema) => Ok(Json(schema)),
            Err(error) => {
                error!("Failed to load temporal memory schema: {}", error);
                Err(StatusCode::INTERNAL_SERVER_ERROR)
            }
        }
    }

    #[cfg(not(feature = "memory"))]
    {
        warn!("Memory feature not enabled");
        Err(StatusCode::NOT_IMPLEMENTED)
    }
}

pub async fn memory_temporal_query_handler(
    State(state): State<AppState>,
    Json(req): Json<TemporalQueryRequest>,
) -> Result<Json<TemporalQueryResult>, StatusCode> {
    let query_text = trim_required(&req.query_text)?;
    let top_k = req.limit.or(req.top_k).unwrap_or(4).clamp(1, 8);
    let ctx = state.ctx.lock().await;
    let truth_view = req
        .truth_view
        .unwrap_or_else(|| "both".to_string())
        .trim()
        .to_string();
    let subject_refs = req
        .subject_refs
        .into_iter()
        .map(|value| value.trim().to_string())
        .filter(|value| !value.is_empty())
        .collect::<Vec<_>>();
    let query = TemporalQuery {
        query_version: req
            .query_version
            .unwrap_or_else(|| TEMPORAL_QUERY_VERSION.to_string()),
        query_text,
        truth_view,
        top_k,
        dense_enabled: req.dense_enabled,
        sparse_enabled: req.sparse_enabled,
        dense_weight: req.dense_weight,
        sparse_weight: req.sparse_weight,
        filters: RetrievalFilters {
            workstream_id: req.filters.workstream_id,
            campaign_id: req.filters.campaign_id,
            session_id: req.filters.session_id,
            source: req.filters.source,
            role: req.filters.role,
            domain: req.filters.domain,
            repo_path: req.filters.repo_path,
            file_type: req.filters.file_type,
            tags: req.filters.tags,
        },
        root_entity_type: req.root_entity_type,
        root_entity_id: req.root_entity_id,
        subject_refs,
        include_contradictions: req.include_contradictions,
        query_type_hint: req.query_type_hint,
        query_mode_hint: req.query_mode_hint,
        rerank_hint: req.rerank_hint,
    };

    #[cfg(feature = "memory")]
    {
        match ctx.memory_temporal_query(query).await {
            Ok(result) => Ok(Json(result)),
            Err(error) => {
                error!("Failed to run temporal memory query: {}", error);
                Err(StatusCode::INTERNAL_SERVER_ERROR)
            }
        }
    }

    #[cfg(not(feature = "memory"))]
    {
        warn!("Memory feature not enabled");
        Err(StatusCode::NOT_IMPLEMENTED)
    }
}

pub async fn memory_graphrag_query_mode_handler(
    State(state): State<AppState>,
    Json(req): Json<GraphRagQueryRequest>,
) -> Result<Json<GraphRagQueryModeDecision>, StatusCode> {
    let ctx = state.ctx.lock().await;
    let query = graphrag_query_from_request(req)?;

    #[cfg(feature = "memory")]
    {
        match ctx.memory_graph_rag_query_mode(&query) {
            Ok(decision) => Ok(Json(decision)),
            Err(error) => {
                error!("Failed to derive GraphRAG query mode: {}", error);
                Err(StatusCode::INTERNAL_SERVER_ERROR)
            }
        }
    }

    #[cfg(not(feature = "memory"))]
    {
        warn!("Memory feature not enabled");
        Err(StatusCode::NOT_IMPLEMENTED)
    }
}

pub async fn memory_promotion_evaluate_handler(
    State(state): State<AppState>,
    Json(req): Json<MemoryPromotionEvaluateRequest>,
) -> Result<Json<PromotedMemory>, StatusCode> {
    let ctx = state.ctx.lock().await;
    let memory_id = trim_required(&req.memory_id)?;

    #[cfg(feature = "memory")]
    {
        match ctx.memory_evaluate_promotion(&memory_id).await {
            Ok(Some(promotion)) => Ok(Json(promotion)),
            Ok(None) => Err(StatusCode::NOT_FOUND),
            Err(error) => {
                error!("Failed to evaluate memory promotion for {}: {}", memory_id, error);
                Err(StatusCode::INTERNAL_SERVER_ERROR)
            }
        }
    }

    #[cfg(not(feature = "memory"))]
    {
        warn!("Memory feature not enabled");
        Err(StatusCode::NOT_IMPLEMENTED)
    }
}

pub async fn memory_graphrag_query_handler(
    State(state): State<AppState>,
    Json(req): Json<GraphRagQueryRequest>,
) -> Result<Json<GraphRagResult>, StatusCode> {
    let ctx = state.ctx.lock().await;
    let query = graphrag_query_from_request(req)?;

    #[cfg(feature = "memory")]
    {
        match ctx.memory_graph_rag_query(query).await {
            Ok(result) => Ok(Json(result)),
            Err(error) => {
                error!("Failed to execute bounded graphrag query: {}", error);
                Err(StatusCode::INTERNAL_SERVER_ERROR)
            }
        }
    }

    #[cfg(not(feature = "memory"))]
    {
        warn!("Memory feature not enabled");
        Err(StatusCode::NOT_IMPLEMENTED)
    }
}

pub fn memory_routes() -> Router<AppState> {
    Router::new()
        .route("/api/memory/ingest_chat", post(memory_ingest_chat_handler))
        .route("/api/memory/query", post(memory_query_handler))
        .route(
            "/api/memory/qdrant/health",
            get(memory_qdrant_health_handler),
        )
        .route(
            "/api/memory/compiler",
            get(memory_compiler_contract_handler),
        )
        .route(
            "/api/memory/compiler/budget-profile/:task_profile",
            get(memory_context_budget_profile_handler),
        )
        .route(
            "/api/memory/compiler/compile",
            post(memory_compile_context_handler),
        )
        .route(
            "/api/memory/compiler/eval",
            post(memory_compiler_eval_handler),
        )
        .route(
            "/api/memory/compiler/policy",
            post(memory_compiler_policy_handler),
        )
        .route(
            "/api/memory/retrieval/collection",
            get(memory_retrieval_collection_handler),
        )
        .route(
            "/api/memory/retrieval/query",
            post(memory_retrieval_query_handler),
        )
        .route(
            "/api/memory/retrieval/code/query",
            post(memory_code_retrieval_query_handler),
        )
        .route(
            "/api/memory/retrieval/sovereign/backend",
            get(memory_sovereign_retrieval_backend_handler),
        )
        .route(
            "/api/memory/retrieval/sovereign/query",
            post(memory_sovereign_retrieval_query_handler),
        )
        .route(
            "/api/memory/retrieval/router/query-type",
            post(memory_retrieval_query_type_handler),
        )
        .route(
            "/api/memory/retrieval/router/decision",
            post(memory_retrieval_routing_decision_handler),
        )
        .route(
            "/api/memory/retrieval/router/query",
            post(memory_routed_retrieval_query_handler),
        )
        .route(
            "/api/memory/retrieval/backend-matrix",
            get(memory_retrieval_backend_matrix_handler),
        )
        .route(
            "/api/memory/retrieval/dense-backend",
            get(memory_retrieval_dense_backend_handler),
        )
        .route(
            "/api/memory/retrieval/reranking-profile",
            get(memory_retrieval_reranking_profile_handler),
        )
        .route(
            "/api/memory/retrieval/rerank/pilot",
            post(memory_reranked_retrieval_query_handler),
        )
        .route(
            "/api/memory/retrieval/evaluate",
            post(memory_retrieval_eval_handler),
        )
        .route(
            "/api/memory/retrieval/feedback",
            post(memory_relevance_feedback_handler),
        )
        .route(
            "/api/memory/promotion-policy",
            get(memory_promotion_policy_handler),
        )
        .route(
            "/api/memory/retention-policy",
            get(memory_retention_policy_handler),
        )
        .route(
            "/api/memory/temporal",
            get(memory_temporal_schema_handler),
        )
        .route(
            "/api/memory/temporal/query",
            post(memory_temporal_query_handler),
        )
        .route(
            "/api/memory/graphrag/query-mode",
            post(memory_graphrag_query_mode_handler),
        )
        .route(
            "/api/memory/promotion/evaluate",
            post(memory_promotion_evaluate_handler),
        )
        .route(
            "/api/memory/graphrag/query",
            post(memory_graphrag_query_handler),
        )
        .route(
            "/api/memory/retrieval/policy/derive",
            post(memory_retrieval_policy_handler),
        )
        .route(
            "/api/memory/retrieval/benchmark",
            post(memory_retrieval_benchmark_handler),
        )
}

fn trim_required(value: &str) -> Result<String, StatusCode> {
    let trimmed = value.trim();
    if trimmed.is_empty() {
        Err(StatusCode::BAD_REQUEST)
    } else {
        Ok(trimmed.to_string())
    }
}

fn normalize_source(source: &str) -> Result<String, StatusCode> {
    let normalized = source.trim().to_ascii_lowercase();
    if normalized.is_empty() {
        return Err(StatusCode::BAD_REQUEST);
    }
    Ok(match normalized.as_str() {
        "chatgpt" | "claude" | "claude-code" | "codex" | "cursor" | "other" => normalized,
        _ => "other".to_string(),
    })
}

fn normalize_role(role: &str) -> Result<String, StatusCode> {
    let normalized = role.trim().to_ascii_lowercase();
    match normalized.as_str() {
        "user" | "assistant" | "system" | "tool" => Ok(normalized),
        _ => Err(StatusCode::BAD_REQUEST),
    }
}

fn normalize_limit(req: &MemoryQueryRequest) -> usize {
    req.limit
        .or(req.top_k)
        .or(req.max_items)
        .unwrap_or(5)
        .clamp(1, 10)
}

fn default_retrieval_dense_enabled() -> bool {
    true
}

fn default_retrieval_sparse_enabled() -> bool {
    true
}

fn default_retrieval_dense_weight() -> f32 {
    0.65
}

fn default_retrieval_sparse_weight() -> f32 {
    0.35
}

fn default_code_retrieval_dense_weight() -> f32 {
    0.75
}

fn default_code_retrieval_sparse_weight() -> f32 {
    0.25
}

fn default_sovereign_retrieval_dense_weight() -> f32 {
    0.7
}

fn default_sovereign_retrieval_sparse_weight() -> f32 {
    0.3
}

fn default_feedback_score() -> f32 {
    1.0
}

fn default_true() -> bool {
    true
}

fn retrieval_filters_from_request(req: RetrievalFiltersRequest) -> RetrievalFilters {
    RetrievalFilters {
        workstream_id: req.workstream_id,
        campaign_id: req.campaign_id,
        session_id: req.session_id,
        source: req.source,
        role: req.role,
        domain: req.domain,
        repo_path: req.repo_path,
        file_type: req.file_type,
        tags: req.tags,
    }
}

fn routed_retrieval_query_from_request(
    req: RoutedRetrievalQueryRequest,
) -> Result<RoutedRetrievalQuery, StatusCode> {
    let query_text = trim_required(&req.query_text)?;
    let top_k = req.limit.or(req.top_k).unwrap_or(5).clamp(1, 10);
    Ok(RoutedRetrievalQuery {
        query_version: req
            .query_version
            .unwrap_or_else(|| ROUTED_RETRIEVAL_QUERY_VERSION.to_string()),
        query_text,
        top_k,
        dense_enabled: req.dense_enabled,
        sparse_enabled: req.sparse_enabled,
        dense_weight: req.dense_weight,
        sparse_weight: req.sparse_weight,
        filters: retrieval_filters_from_request(req.filters),
        query_type_hint: req.query_type_hint,
        compare_against_general: req.compare_against_general,
        rerank_hint: req.rerank_hint,
    })
}

fn retrieval_eval_case_from_request(
    req: RetrievalEvalCaseRequest,
) -> Result<RetrievalEvalCase, StatusCode> {
    Ok(RetrievalEvalCase {
        case_id: trim_required(&req.case_id)?,
        query_type: trim_required(&req.query_type)?.to_ascii_lowercase(),
        description: req.description,
        query: routed_retrieval_query_from_request(req.query)?,
        expected_memory_ids: req.expected_memory_ids,
    })
}

fn context_eval_case_from_request(req: ContextEvalCaseRequest) -> Result<ContextEvalCase, StatusCode> {
    let task_profile = trim_required(&req.task_profile)?.to_ascii_lowercase();
    let request = CompiledContextRequest {
        task_profile: task_profile.clone(),
        tool_id: req.request.tool_id,
        query_text: trim_required(&req.request.query_text)?,
        workstream_id: req.request.workstream_id,
        campaign_id: req.request.campaign_id,
        program_id: req.request.program_id,
        workspace_id: req.request.workspace_id,
        session_id: req.request.session_id,
        root_entity_type: req.request.root_entity_type,
        root_entity_id: req.request.root_entity_id,
        repo_path: req.request.repo_path,
        file_type: req.request.file_type,
        tags: req.request.tags,
        rerank_hint: req.request.rerank_hint,
    };

    Ok(ContextEvalCase {
        case_id: trim_required(&req.case_id)?,
        task_profile,
        description: req.description,
        request,
        expected_memory_ids: req.expected_memory_ids,
        preferred_truth_view: trim_required(&req.preferred_truth_view)?.to_ascii_lowercase(),
        preferred_graphrag_mode: trim_required(&req.preferred_graphrag_mode)?.to_ascii_lowercase(),
        preferred_memory_tiers: req
            .preferred_memory_tiers
            .into_iter()
            .map(|tier| tier.trim().to_ascii_lowercase())
            .filter(|tier| !tier.is_empty())
            .collect(),
        expected_retrieval_query_type: req
            .expected_retrieval_query_type
            .map(|query_type| query_type.trim().to_ascii_lowercase())
            .filter(|query_type| !query_type.is_empty()),
    })
}

fn relevance_feedback_input_from_request(
    req: RelevanceFeedbackInputRequest,
) -> Result<RelevanceFeedbackInput, StatusCode> {
    let judgments = req
        .judgments
        .into_iter()
        .map(|judgment| {
            Ok(RelevanceFeedbackJudgment {
                memory_id: trim_required(&judgment.memory_id)?,
                signal: trim_required(&judgment.signal)?.to_ascii_lowercase(),
                score: judgment.score,
                rationale: judgment.rationale,
            })
        })
        .collect::<Result<Vec<_>, StatusCode>>()?;

    Ok(RelevanceFeedbackInput {
        feedback_version: req
            .feedback_version
            .unwrap_or_else(|| RELEVANCE_FEEDBACK_VERSION.to_string()),
        query: routed_retrieval_query_from_request(req.query)?,
        feedback_round: req.feedback_round.unwrap_or(1),
        expected_memory_ids: req.expected_memory_ids,
        judgments,
        note: req.note,
    })
}

fn graphrag_query_from_request(req: GraphRagQueryRequest) -> Result<GraphRagQuery, StatusCode> {
    let query_text = trim_required(&req.query_text)?;
    let top_k = req.limit.or(req.top_k).unwrap_or(5).clamp(1, 10);
    Ok(GraphRagQuery {
        query_version: req
            .query_version
            .unwrap_or_else(|| GRAPHRAG_QUERY_VERSION.to_string()),
        query_text,
        top_k,
        max_hops: req.max_hops.unwrap_or(2).clamp(1, 3),
        dense_enabled: req.dense_enabled,
        sparse_enabled: req.sparse_enabled,
        dense_weight: req.dense_weight,
        sparse_weight: req.sparse_weight,
        filters: retrieval_filters_from_request(req.filters),
        root_entity_type: req.root_entity_type,
        root_entity_id: req.root_entity_id,
        program_id: req.program_id,
        include_memory_hierarchy: req.include_memory_hierarchy,
        query_type_hint: req.query_type_hint,
        query_mode_hint: req.query_mode_hint,
        rerank_hint: req.rerank_hint,
    })
}

fn retrieval_benchmark_case_from_request(
    req: RetrievalBenchmarkCaseRequest,
) -> Result<RetrievalBenchmarkCase, StatusCode> {
    let query_text = trim_required(&req.query.query_text)?;
    let top_k = req.query.limit.or(req.query.top_k).unwrap_or(5).clamp(1, 10);
    Ok(RetrievalBenchmarkCase {
        case_id: trim_required(&req.case_id)?,
        case_kind: trim_required(&req.case_kind)?,
        description: req.description,
        query: RetrievalQuery {
            query_version: req
                .query
                .query_version
                .unwrap_or_else(|| RETRIEVAL_QUERY_VERSION.to_string()),
            query_text,
            top_k,
            dense_enabled: req.query.dense_enabled,
            sparse_enabled: req.query.sparse_enabled,
            dense_weight: req.query.dense_weight,
            sparse_weight: req.query.sparse_weight,
            filters: RetrievalFilters {
                workstream_id: req.query.filters.workstream_id,
                campaign_id: req.query.filters.campaign_id,
                session_id: req.query.filters.session_id,
                source: req.query.filters.source,
                role: req.query.filters.role,
                domain: req.query.filters.domain,
                repo_path: req.query.filters.repo_path,
                file_type: req.query.filters.file_type,
                tags: req.query.filters.tags,
            },
            rerank_hint: req.query.rerank_hint,
        },
        expected_memory_ids: req.expected_memory_ids,
    })
}

pub(crate) async fn latest_physio_snapshot(state: &AppState) -> Option<PhysioSnapshot> {
    if let Some(snapshot) = state.observer.latest_physio_snapshot().await {
        return Some(canonical_memory_snapshot(snapshot));
    }

    let user_context = state.observer.current_user_context().await;
    let physio = user_context.physio;
    if physio.heart_rate_bpm.is_none()
        && physio.hrv_level.is_none()
        && physio.spo2_percent.is_none()
        && user_context.current_state.last_updated.is_none()
    {
        return None;
    }

    Some(PhysioSnapshot {
        hr: physio.heart_rate_bpm,
        hrv_level: physio.hrv_level,
        spo2: physio.spo2_percent,
        timestamp: user_context.current_state.last_updated,
        source: Some("observer_context".to_string()),
    })
}

fn canonical_memory_snapshot(snapshot: ObserverPhysioSnapshot) -> PhysioSnapshot {
    PhysioSnapshot {
        hr: snapshot.hr,
        hrv_level: snapshot.hrv_level,
        spo2: snapshot.spo2,
        timestamp: Some(snapshot.timestamp),
        source: Some(snapshot.source),
    }
}

fn build_experiment_flags(
    cfg: &beagle_config::BeagleConfig,
    request_flags: Option<&MemoryIngestExperimentFlagsInput>,
    provider: Option<String>,
    model: Option<String>,
) -> Option<MemoryExperimentFlags> {
    let flags = request_flags.cloned().unwrap_or_default();
    let result = MemoryExperimentFlags {
        hrv_aware: Some(flags.hrv_aware.unwrap_or(true)),
        serendipity_enabled: Some(
            flags
                .serendipity_enabled
                .unwrap_or_else(|| cfg.serendipity_enabled()),
        ),
        triad_enabled: Some(flags.triad_enabled.unwrap_or(true)),
        provider,
        model,
    };

    Some(result)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn limit_prefers_new_limit_field() {
        let req = MemoryQueryRequest {
            query: "memory".to_string(),
            limit: Some(7),
            top_k: Some(3),
            max_items: Some(2),
            domain: None,
            tags: vec![],
            include_recent_physio: false,
            scope: None,
        };
        assert_eq!(normalize_limit(&req), 7);
    }

    #[test]
    fn invalid_role_is_rejected() {
        assert!(normalize_role("narrator").is_err());
        assert_eq!(normalize_role("assistant").unwrap(), "assistant");
    }

    #[test]
    fn retrieval_memory_preserves_claude_code_source() {
        assert_eq!(normalize_source("claude-code").unwrap(), "claude-code");
        assert_eq!(normalize_source("CLAUDE-CODE").unwrap(), "claude-code");
    }
}
