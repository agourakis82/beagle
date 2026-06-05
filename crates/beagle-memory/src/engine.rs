//! Memory Engine - Unified interface for ingesting and querying memory
//!
//! Provides a high-level API for:
//! - Ingesting chat sessions (ChatGPT, Claude, Grok, local)
//! - Querying memory with semantic search
//! - Integration with GraphRAG and vector stores

use crate::bridge::ContextBridge;
use crate::budgeting::{
    ContextBudgetProfile, compiler_policy_variants, context_budget_profile,
    normalize_task_profile,
};
use crate::compiler::{
    COMPILER_EVAL_REPORT_VERSION, COMPILER_POLICY_VERSION, CompiledContextPacket,
    CompiledContextRequest, CompiledContextSourceSlice, CompilerEvalReport,
    CompilerEvalRequest, CompilerPolicy, CompilerPolicyProfile,
    CompilerPolicyVariantReport, CompilerTaskComparison, ContextEvalCase,
    MemoryCompilerContract, memory_compiler_contract,
};
use crate::graphrag_modes::{
    GraphRagQueryModeDecision, apply_graphrag_query_mode, derive_graphrag_query_mode,
};
use crate::models::ConversationTurn;
use crate::promotion::{
    MemoryPromotionPolicy, PromotedMemory, classify_memory_type, derive_memory_promotion,
    memory_promotion_policy, promoted_target_memory_type,
};
use crate::retention::{
    MemoryRetentionPolicy, memory_retention_policy, retention_action_for_memory_type,
};
use crate::retrieval::{
    CodeRetrievalBackendProfile, CodeRetrievalComparison, CodeRetrievalQuery,
    CodeRetrievalResult, EmbeddingBackendCandidate, EmbeddingBackendContract,
    EmbeddingBackendMatrix, GraphRagEdge, GraphRagNode, GraphRagQuery,
    GraphRagResult, MemoryHierarchy, MemoryHierarchyBucket, MemoryPoint, RetrievalBenchmarkCase,
    RetrievalBenchmarkCaseReport, RetrievalBenchmarkReport, RetrievalBenchmarkRequest,
    RetrievalBenchmarkSummary, RetrievalCollection, RetrievalCollectionField,
    RetrievalEvalCaseReport, RetrievalEvalLaneSummary,
    RetrievalEvalReport, RetrievalEvalRequest, RetrievalFilters, RetrievalHit,
    RetrievalPolicy, RetrievalPolicyLane, RetrievalQuery, RetrievalQueryType,
    RetrievalRecommendation, RetrievalResult, RetrievalRoutingDecision,
    FeedbackAdjustedHit, FeedbackLatencyComparison, FeedbackLoopResult,
    RelevanceFeedbackInput, RelevanceFeedbackJudgment, RerankedHit, RerankedResult, RerankingCandidate,
    RerankingLatencyComparison, RerankingProfile,
    RerankingRecommendation, RoutedRetrievalQuery, RoutedRetrievalResult,
    SovereignRetrievalBackendProfile, SovereignRetrievalComparison,
    SovereignRetrievalQuery, SovereignRetrievalResult,
    CODE_RETRIEVAL_RESULT_VERSION, EMBEDDING_BACKEND_CONTRACT_VERSION,
    EMBEDDING_BACKEND_MATRIX_VERSION, GRAPHRAG_EDGE_VERSION,
    GRAPHRAG_NODE_VERSION, GRAPHRAG_RESULT_VERSION,
    MEMORY_HIERARCHY_VERSION, MEMORY_POINT_VERSION, QUERY_TYPE_VERSION,
    RELEVANCE_FEEDBACK_VERSION, RERANKED_RESULT_VERSION,
    RERANKING_PROFILE_VERSION,
    RETRIEVAL_BENCHMARK_VERSION,
    RETRIEVAL_COLLECTION_VERSION, RETRIEVAL_EVAL_REPORT_VERSION,
    RETRIEVAL_POLICY_VERSION, RETRIEVAL_RESULT_VERSION,
    RETRIEVAL_ROUTER_VERSION, RETRIEVAL_ROUTING_DECISION_VERSION,
    ROUTED_RETRIEVAL_RESULT_VERSION,
    SOVEREIGN_RETRIEVAL_RESULT_VERSION,
};
use crate::temporal::{
    MemoryContradiction, TemporalMemorySchema, TemporalMemoryTrack, TemporalQuery,
    TemporalQueryResult, TEMPORAL_QUERY_RESULT_VERSION,
    TEMPORAL_QUERY_VERSION, detect_temporal_contradiction, normalize_truth_view,
    temporal_entity_refs, temporal_memory_schema, temporal_truth_keys, temporal_version_from_record,
};
use anyhow::{Context, Result};
use beagle_llm::embedding::EmbeddingClient;
use chrono::{DateTime, Utc};
use reqwest::Client;
use serde::{Deserialize, Serialize};
use serde_json::json;
use std::collections::{HashMap, HashSet};
use std::fs::{self, File};
use std::io::{BufRead, BufReader, Write};
use std::path::PathBuf;
use std::sync::Arc;
use std::time::{Duration, Instant};
use tokio::sync::RwLock;
use tracing::{debug, info, warn};
use uuid::Uuid;

/// Simplified chat turn for ingestion
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ChatTurn {
    pub role: String, // "user" | "assistant"
    pub content: String,
    pub timestamp: Option<DateTime<Utc>>,
    pub model: Option<String>,
    #[serde(default)]
    pub turn_index: Option<usize>,
}

/// Chat session for ingestion
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ChatSession {
    pub source: String, // "chatgpt" | "claude" | "grok" | "local"
    pub session_id: String,
    pub turns: Vec<ChatTurn>,
    pub tags: Vec<String>,
    pub metadata: serde_json::Value,
}

/// Memory query
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct MemoryQuery {
    pub query: String,
    pub scope: Option<String>, // "general" | "scientific" | "pcs" | "pbpk" | "fractal"
    pub max_items: Option<usize>,
    #[serde(default)]
    pub domain: Option<String>,
    #[serde(default)]
    pub tags: Vec<String>,
    #[serde(default)]
    pub include_recent_physio: bool,
}

#[derive(Debug, Clone, Default, Serialize, Deserialize, PartialEq)]
pub struct PhysioSnapshot {
    pub hr: Option<f64>,
    pub hrv_level: Option<String>,
    pub spo2: Option<f64>,
    pub timestamp: Option<DateTime<Utc>>,
    pub source: Option<String>,
}

#[derive(Debug, Clone, Default, Serialize, Deserialize, PartialEq)]
pub struct ExperimentFlags {
    pub hrv_aware: Option<bool>,
    pub serendipity_enabled: Option<bool>,
    pub triad_enabled: Option<bool>,
    pub provider: Option<String>,
    pub model: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct MemoryRecord {
    pub memory_id: String,
    pub source: String,
    pub conversation_id: String,
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
    pub turn_index: usize,
    pub role: String,
    pub text: String,
    pub tags: Vec<String>,
    pub domain: Option<String>,
    #[serde(default)]
    pub repo_path: Option<String>,
    #[serde(default)]
    pub file_type: Option<String>,
    pub timestamp: DateTime<Utc>,
    pub physio_snapshot: Option<PhysioSnapshot>,
    pub experiment_flags: Option<ExperimentFlags>,
    #[serde(default)]
    pub physio_snapshot_ref: Option<String>,
    #[serde(default)]
    pub result_refs: Vec<String>,
    #[serde(default)]
    pub claim_refs: Vec<String>,
    #[serde(default)]
    pub provider: Option<String>,
    #[serde(default)]
    pub model: Option<String>,
    #[serde(default)]
    pub score: Option<f32>,
}

/// Highlight from memory query
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct MemoryResultHighlight {
    pub memory_id: Option<String>,
    pub source: String,
    pub date: Option<DateTime<Utc>>,
    pub snippet: String,
    pub run_id: Option<String>,
    pub session_id: Option<String>,
    pub relevance: f32,
    #[serde(default)]
    pub conversation_id: Option<String>,
    #[serde(default)]
    pub turn_index: Option<usize>,
    #[serde(default)]
    pub role: Option<String>,
    #[serde(default)]
    pub tags: Vec<String>,
    #[serde(default)]
    pub domain: Option<String>,
    #[serde(default)]
    pub physio_snapshot: Option<PhysioSnapshot>,
    #[serde(default)]
    pub experiment_flags: Option<ExperimentFlags>,
    #[serde(default)]
    pub workstream_id: Option<String>,
    #[serde(default)]
    pub campaign_id: Option<String>,
    #[serde(default)]
    pub program_id: Option<String>,
    #[serde(default)]
    pub workspace_id: Option<String>,
    #[serde(default)]
    pub beagle_session_id: Option<String>,
    #[serde(default)]
    pub result_refs: Vec<String>,
    #[serde(default)]
    pub claim_refs: Vec<String>,
}

/// Memory query result
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct MemoryResult {
    pub summary: String,
    pub highlights: Vec<MemoryResultHighlight>,
    pub links: Vec<serde_json::Value>,
    #[serde(default)]
    pub results: Vec<MemoryRecord>,
    #[serde(default)]
    pub recent_physio: Option<PhysioSnapshot>,
}

/// Ingest statistics
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct IngestStats {
    pub num_turns: usize,
    pub num_chunks: usize,
    pub session_id: String,
    pub stored: bool,
    pub memory_id: Option<String>,
    pub searchable: bool,
    pub physio_attached: bool,
    pub experiment_flags_attached: bool,
}

#[derive(Debug, Clone, Default)]
pub struct MemoryEngineConfig {
    pub qdrant_url: Option<String>,
    pub embedding_url: Option<String>,
    pub embedding_model: String,
    pub dense_backend_id: String,
    pub dense_backend_provider: String,
    pub dense_backend_api_key: Option<String>,
    pub code_backend_id: String,
    pub sovereign_backend_id: String,
    pub sovereign_embedding_url: Option<String>,
    pub sovereign_embedding_model: String,
    pub sovereign_embedding_api_key: Option<String>,
    pub reranking_url: Option<String>,
    pub reranking_model: String,
    pub reranking_api_key: Option<String>,
    pub sovereign_reranking_url: Option<String>,
    pub sovereign_reranking_model: String,
    pub sovereign_reranking_api_key: Option<String>,
    pub qdrant_collection: String,
    pub local_index_path: PathBuf,
}

impl MemoryEngineConfig {
    pub fn from_runtime(
        qdrant_url: Option<String>,
        embedding_url: Option<String>,
        data_dir: Option<PathBuf>,
    ) -> Self {
        let data_dir = data_dir
            .or_else(|| std::env::var("BEAGLE_DATA_DIR").ok().map(PathBuf::from))
            .unwrap_or_else(|| PathBuf::from("/tmp/beagle-data"));
        Self {
            qdrant_url,
            embedding_url: embedding_url.clone(),
            embedding_model: std::env::var("BEAGLE_MEMORY_EMBEDDING_MODEL")
                .unwrap_or_else(|_| "voyage-4-large".to_string()),
            dense_backend_id: std::env::var("BEAGLE_MEMORY_DENSE_BACKEND_ID")
                .unwrap_or_else(|_| "voyage-4-large".to_string()),
            dense_backend_provider: std::env::var("BEAGLE_MEMORY_DENSE_BACKEND_PROVIDER")
                .unwrap_or_else(|_| "voyage".to_string()),
            dense_backend_api_key: std::env::var("BEAGLE_MEMORY_EMBEDDING_API_KEY")
                .ok()
                .or_else(|| std::env::var("VOYAGE_API_KEY").ok()),
            code_backend_id: std::env::var("BEAGLE_MEMORY_CODE_BACKEND_ID")
                .unwrap_or_else(|_| "voyage-code-3".to_string()),
            sovereign_backend_id: std::env::var("BEAGLE_MEMORY_SOVEREIGN_BACKEND_ID")
                .unwrap_or_else(|_| "bge-m3".to_string()),
            sovereign_embedding_url: std::env::var("BEAGLE_MEMORY_SOVEREIGN_EMBEDDING_URL")
                .ok()
                .filter(|value| !value.trim().is_empty()),
            sovereign_embedding_model: std::env::var("BEAGLE_MEMORY_SOVEREIGN_EMBEDDING_MODEL")
                .unwrap_or_else(|_| "BAAI/bge-m3".to_string()),
            sovereign_embedding_api_key: std::env::var("BEAGLE_MEMORY_SOVEREIGN_EMBEDDING_API_KEY")
                .ok()
                .filter(|value| !value.trim().is_empty()),
            reranking_url: std::env::var("BEAGLE_MEMORY_RERANKING_URL")
                .ok()
                .filter(|value| !value.trim().is_empty())
                .or_else(|| embedding_url.clone()),
            reranking_model: std::env::var("BEAGLE_MEMORY_RERANKING_MODEL")
                .unwrap_or_else(|_| "rerank-2.5".to_string()),
            reranking_api_key: std::env::var("BEAGLE_MEMORY_RERANKING_API_KEY")
                .ok()
                .filter(|value| !value.trim().is_empty())
                .or_else(|| std::env::var("VOYAGE_API_KEY").ok()),
            sovereign_reranking_url: std::env::var("BEAGLE_MEMORY_SOVEREIGN_RERANKING_URL")
                .ok()
                .filter(|value| !value.trim().is_empty()),
            sovereign_reranking_model: std::env::var("BEAGLE_MEMORY_SOVEREIGN_RERANKING_MODEL")
                .unwrap_or_else(|_| "BAAI/bge-reranker-v2-m3".to_string()),
            sovereign_reranking_api_key: std::env::var(
                "BEAGLE_MEMORY_SOVEREIGN_RERANKING_API_KEY",
            )
            .ok()
            .filter(|value| !value.trim().is_empty()),
            qdrant_collection: std::env::var("BEAGLE_MEMORY_QDRANT_COLLECTION")
                .unwrap_or_else(|_| "beagle_memory_chat".to_string()),
            local_index_path: data_dir.join("memory").join("chat-memory.jsonl"),
        }
    }
}

/// Qdrant connectivity snapshot for operators (no vector payloads).
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct MemoryQdrantHealth {
    pub configured: bool,
    /// e.g. `up`, `collection_missing`, `qdrant_error`, `unreachable`, `not_configured`
    pub status: String,
    pub http_status: Option<u16>,
    pub collection: String,
    pub base_url: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub error: Option<String>,
}

/// Memory Engine - Main interface for memory operations
pub struct MemoryEngine {
    bridge: Option<Arc<ContextBridge>>,
    index: Option<Arc<MemoryVectorIndex>>,
    local_index: Arc<LocalMemoryIndex>,
    dense_backend: DenseBackendRuntime,
    local_dense_index: Option<Arc<LocalDenseVectorIndex>>,
    code_dense_index: Option<Arc<LocalDenseVectorIndex>>,
    sovereign_dense_index: Option<Arc<LocalDenseVectorIndex>>,
    reranking_runtime: RerankingRuntime,
    general_reranker: Option<Arc<RerankerClient>>,
    sovereign_reranker: Option<Arc<RerankerClient>>,
    qdrant_telemetry_url: Option<String>,
    qdrant_telemetry_collection: String,
}

#[derive(Debug, Clone)]
struct DenseBackendRuntime {
    promoted_backend_id: String,
    promoted_provider: String,
    promoted_model: String,
    code_backend_id: String,
    sovereign_backend_id: String,
    endpoint_ref: Option<String>,
    api_key_present: bool,
    sovereign_endpoint_ref: Option<String>,
    sovereign_model: String,
}

#[derive(Debug, Clone)]
struct RerankingRuntime {
    general_backend_id: String,
    general_model: String,
    general_endpoint_ref: Option<String>,
    general_api_key_present: bool,
    sovereign_backend_id: String,
    sovereign_model: String,
    sovereign_endpoint_ref: Option<String>,
    sovereign_api_key_present: bool,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
enum RerankerKind {
    Voyage,
    Tei,
}

#[derive(Debug, Clone)]
struct RerankerClient {
    client: Client,
    base_url: String,
    model: String,
    api_key: Option<String>,
    kind: RerankerKind,
}

#[derive(Debug, Clone, PartialEq)]
struct RerankScore {
    index: usize,
    score: f32,
}

impl DenseBackendRuntime {
    fn semantic_path_enabled(&self) -> bool {
        self.endpoint_ref
            .as_deref()
            .map(|value| !value.trim().is_empty())
            .unwrap_or(false)
            && self.api_key_present
    }

    fn runtime_state(&self) -> &'static str {
        if self.semantic_path_enabled() {
            "promoted-active"
        } else if self
            .endpoint_ref
            .as_deref()
            .map(|value| !value.trim().is_empty())
            .unwrap_or(false)
        {
            "auth-blocked-fallback"
        } else {
            "endpoint-missing-fallback"
        }
    }
}

impl RerankingRuntime {
    fn general_runtime_state(&self) -> &'static str {
        if self
            .general_endpoint_ref
            .as_deref()
            .map(|value| !value.trim().is_empty())
            .unwrap_or(false)
            && self.general_api_key_present
        {
            "pilot-active"
        } else if self
            .general_endpoint_ref
            .as_deref()
            .map(|value| !value.trim().is_empty())
            .unwrap_or(false)
        {
            "auth-blocked-fallback"
        } else {
            "endpoint-missing-fallback"
        }
    }

    fn sovereign_runtime_state(&self) -> &'static str {
        if self
            .sovereign_endpoint_ref
            .as_deref()
            .map(|value| !value.trim().is_empty())
            .unwrap_or(false)
        {
            if self.sovereign_api_key_present {
                "pilot-active"
            } else {
                "pilot-active"
            }
        } else {
            "endpoint-missing-fallback"
        }
    }
}

impl RerankerClient {
    fn new(
        base_url: impl Into<String>,
        model: impl Into<String>,
        api_key: Option<String>,
        kind: RerankerKind,
    ) -> Self {
        Self {
            client: Client::new(),
            base_url: base_url.into(),
            model: model.into(),
            api_key: api_key
                .map(|value| value.trim().to_string())
                .filter(|value| !value.is_empty()),
            kind,
        }
    }

    async fn rerank(
        &self,
        query: &str,
        documents: &[String],
        top_k: usize,
    ) -> Result<Vec<RerankScore>> {
        match self.kind {
            RerankerKind::Voyage => self.rerank_voyage(query, documents, top_k).await,
            RerankerKind::Tei => self.rerank_tei(query, documents, top_k).await,
        }
    }

    async fn rerank_voyage(
        &self,
        query: &str,
        documents: &[String],
        top_k: usize,
    ) -> Result<Vec<RerankScore>> {
        let url = format!("{}/rerank", self.base_url.trim_end_matches('/'));
        let mut builder = self.client.post(&url).json(&json!({
            "model": self.model,
            "query": query,
            "documents": documents,
            "top_k": top_k,
            "truncation": true
        }));
        if let Some(api_key) = &self.api_key {
            builder = builder.bearer_auth(api_key);
        }
        let response = builder
            .send()
            .await
            .context("failed to send Voyage rerank request")?;
        let status = response.status();
        let body = response.text().await.unwrap_or_default();
        if !status.is_success() {
            anyhow::bail!("Voyage rerank request failed with {}: {}", status, body);
        }
        parse_rerank_scores(&body)
    }

    async fn rerank_tei(
        &self,
        query: &str,
        documents: &[String],
        top_k: usize,
    ) -> Result<Vec<RerankScore>> {
        let url = format!("{}/rerank", self.base_url.trim_end_matches('/'));
        let mut builder = self.client.post(&url).json(&json!({
            "query": query,
            "texts": documents,
            "top_n": top_k,
            "raw_scores": false,
            "truncate": true
        }));
        if let Some(api_key) = &self.api_key {
            builder = builder.bearer_auth(api_key);
        }
        let response = builder
            .send()
            .await
            .context("failed to send sovereign TEI rerank request")?;
        let status = response.status();
        let body = response.text().await.unwrap_or_default();
        if !status.is_success() {
            anyhow::bail!("sovereign rerank request failed with {}: {}", status, body);
        }
        parse_rerank_scores(&body)
    }
}

impl MemoryEngine {
    /// Create new MemoryEngine
    pub fn new(bridge: Option<Arc<ContextBridge>>, config: MemoryEngineConfig) -> Self {
        let dense_backend = DenseBackendRuntime {
            promoted_backend_id: config.dense_backend_id.clone(),
            promoted_provider: config.dense_backend_provider.clone(),
            promoted_model: config.embedding_model.clone(),
            code_backend_id: config.code_backend_id.clone(),
            sovereign_backend_id: config.sovereign_backend_id.clone(),
            endpoint_ref: config.embedding_url.clone(),
            api_key_present: config
                .dense_backend_api_key
                .as_deref()
                .map(|value| !value.trim().is_empty())
                .unwrap_or(false),
            sovereign_endpoint_ref: config.sovereign_embedding_url.clone(),
            sovereign_model: config.sovereign_embedding_model.clone(),
        };
        let index = config
            .qdrant_url
            .clone()
            .map(|qdrant_url| {
                Arc::new(MemoryVectorIndex::new(
                    qdrant_url,
                    config.qdrant_collection.clone(),
                    config.embedding_url.clone(),
                    config.embedding_model.clone(),
                    config.dense_backend_api_key.clone(),
                ))
            });
        let local_index = Arc::new(LocalMemoryIndex::new(config.local_index_path));
        let local_dense_index = if dense_backend.semantic_path_enabled() {
            dense_backend
                .endpoint_ref
                .clone()
                .map(|endpoint| {
                    Arc::new(LocalDenseVectorIndex::new(
                        endpoint,
                        dense_backend.promoted_model.clone(),
                        config.dense_backend_api_key.clone(),
                    ))
                })
        } else {
            None
        };
        let code_dense_index = if dense_backend.semantic_path_enabled() {
            dense_backend.endpoint_ref.clone().map(|endpoint| {
                Arc::new(LocalDenseVectorIndex::new(
                    endpoint,
                    dense_backend.code_backend_id.clone(),
                    config.dense_backend_api_key.clone(),
                ))
            })
        } else {
            None
        };
        let sovereign_dense_index = dense_backend
            .sovereign_endpoint_ref
            .clone()
            .map(|endpoint| {
                Arc::new(LocalDenseVectorIndex::new(
                    endpoint,
                    dense_backend.sovereign_model.clone(),
                    config.sovereign_embedding_api_key.clone(),
                ))
            });
        let reranking_runtime = RerankingRuntime {
            general_backend_id: "voyage-rerank-2.5".to_string(),
            general_model: config.reranking_model.clone(),
            general_endpoint_ref: config.reranking_url.clone(),
            general_api_key_present: config
                .reranking_api_key
                .as_deref()
                .map(|value| !value.trim().is_empty())
                .unwrap_or(false),
            sovereign_backend_id: "bge-reranker-v2-m3".to_string(),
            sovereign_model: config.sovereign_reranking_model.clone(),
            sovereign_endpoint_ref: config.sovereign_reranking_url.clone(),
            sovereign_api_key_present: config
                .sovereign_reranking_api_key
                .as_deref()
                .map(|value| !value.trim().is_empty())
                .unwrap_or(false),
        };
        let general_reranker = config.reranking_url.clone().map(|endpoint| {
            Arc::new(RerankerClient::new(
                endpoint,
                config.reranking_model.clone(),
                config.reranking_api_key.clone(),
                RerankerKind::Voyage,
            ))
        });
        let sovereign_reranker = config
            .sovereign_reranking_url
            .clone()
            .map(|endpoint| {
                Arc::new(RerankerClient::new(
                    endpoint,
                    config.sovereign_reranking_model.clone(),
                    config.sovereign_reranking_api_key.clone(),
                    RerankerKind::Tei,
                ))
            });

        Self {
            bridge,
            index,
            local_index,
            dense_backend,
            local_dense_index,
            code_dense_index,
            sovereign_dense_index,
            reranking_runtime,
            general_reranker,
            sovereign_reranker,
            qdrant_telemetry_url: config.qdrant_url.clone(),
            qdrant_telemetry_collection: config.qdrant_collection.clone(),
        }
    }

    /// Best-effort Qdrant reachability for the memory vector index (no writes).
    pub async fn qdrant_health(&self) -> MemoryQdrantHealth {
        let collection = self.qdrant_telemetry_collection.clone();
        let base_url = self.qdrant_telemetry_url.clone();
        let Some(ref index) = self.index else {
            return MemoryQdrantHealth {
                configured: false,
                status: "not_configured".to_string(),
                http_status: None,
                collection,
                base_url,
                error: None,
            };
        };
        match index.health_probe().await {
            Ok(MemoryIndexProbe::Up) => MemoryQdrantHealth {
                configured: true,
                status: "up".to_string(),
                http_status: Some(200),
                collection,
                base_url,
                error: None,
            },
            Ok(MemoryIndexProbe::CollectionMissing(code)) => MemoryQdrantHealth {
                configured: true,
                status: "collection_missing".to_string(),
                http_status: Some(code),
                collection,
                base_url,
                error: None,
            },
            Ok(MemoryIndexProbe::HttpError(code, body)) => MemoryQdrantHealth {
                configured: true,
                status: "qdrant_error".to_string(),
                http_status: Some(code),
                collection,
                base_url,
                error: Some(truncate_health_detail(&body)),
            },
            Err(e) => MemoryQdrantHealth {
                configured: true,
                status: "unreachable".to_string(),
                http_status: None,
                collection,
                base_url,
                error: Some(e.to_string()),
            },
        }
    }

    pub fn embedding_backend_contract(&self) -> EmbeddingBackendContract {
        EmbeddingBackendContract {
            contract_version: EMBEDDING_BACKEND_CONTRACT_VERSION.to_string(),
            promoted_dense_backend: self.dense_backend.promoted_backend_id.clone(),
            promoted_provider: self.dense_backend.promoted_provider.clone(),
            promoted_model: self.dense_backend.promoted_model.clone(),
            active_dense_backend: self.active_dense_backend_id(),
            runtime_state: self.dense_backend.runtime_state().to_string(),
            authentication_mode: if self.dense_backend.api_key_present {
                "bearer-configured".to_string()
            } else if self.dense_backend.promoted_provider.eq_ignore_ascii_case("voyage") {
                "bearer-required-missing".to_string()
            } else {
                "none".to_string()
            },
            endpoint_ref: self.dense_backend.endpoint_ref.clone(),
            store_direction: self.store_direction(),
            sparse_backend: "local-lexical".to_string(),
            code_candidate_backend: self.dense_backend.code_backend_id.clone(),
            sovereign_candidate_backend: self.dense_backend.sovereign_backend_id.clone(),
            note: "B22.3 promotes a stronger dense backend contract without changing the canonical Qdrant-compatible hybrid retrieval spine or the sparse lexical path.".to_string(),
        }
    }

    fn active_dense_backend_id(&self) -> String {
        if self.dense_backend.semantic_path_enabled() {
            self.dense_backend.promoted_backend_id.clone()
        } else {
            "local-fallback-dense".to_string()
        }
    }

    fn active_code_dense_backend_id(&self) -> String {
        if self.code_dense_index.is_some() {
            self.dense_backend.code_backend_id.clone()
        } else {
            "local-fallback-dense".to_string()
        }
    }

    fn active_sovereign_dense_backend_id(&self) -> String {
        if self.sovereign_dense_index.is_some() {
            self.dense_backend.sovereign_backend_id.clone()
        } else {
            "local-fallback-dense".to_string()
        }
    }

    fn active_general_reranker_backend_id(&self) -> String {
        if self.general_reranker.is_some()
            && self.reranking_runtime.general_runtime_state() == "pilot-active"
        {
            self.reranking_runtime.general_backend_id.clone()
        } else {
            "rerank-disabled".to_string()
        }
    }

    fn active_sovereign_reranker_backend_id(&self) -> String {
        if self.sovereign_reranker.is_some()
            && self.reranking_runtime.sovereign_runtime_state() == "pilot-active"
        {
            self.reranking_runtime.sovereign_backend_id.clone()
        } else {
            "rerank-disabled".to_string()
        }
    }

    fn store_direction(&self) -> String {
        if self.index.is_some() {
            "qdrant".to_string()
        } else {
            "local-memory-index".to_string()
        }
    }

    pub fn retrieval_collection(&self) -> RetrievalCollection {
        RetrievalCollection {
            collection_version: RETRIEVAL_COLLECTION_VERSION.to_string(),
            collection_kind: "hybrid-memory-retrieval-collection".to_string(),
            collection_name: self
                .index
                .as_ref()
                .map(|index| index.collection.clone())
                .unwrap_or_else(|| "beagle_memory_local".to_string()),
            dense_backend: self.active_dense_backend_id(),
            sparse_backend: "local-lexical".to_string(),
            dense_vector_name: Some("dense".to_string()),
            supports_named_vectors: false,
            supports_payload_filters: true,
            supports_hybrid_query: true,
            payload_fields: retrieval_collection_payload_fields(),
            filter_fields: vec![
                "workstream_id".to_string(),
                "campaign_id".to_string(),
                "session_id".to_string(),
                "source".to_string(),
                "role".to_string(),
                "domain".to_string(),
                "repo_path".to_string(),
                "file_type".to_string(),
                "tags".to_string(),
            ],
            note: format!(
                "Hybrid retrieval combines dense semantic search via {} with sparse lexical search and payload-aware filtering over Beagle memory points.",
                self.embedding_backend_contract().promoted_dense_backend
            ),
        }
    }

    pub fn embedding_backend_matrix(&self) -> EmbeddingBackendMatrix {
        let collection = self.retrieval_collection();
        EmbeddingBackendMatrix {
            matrix_version: EMBEDDING_BACKEND_MATRIX_VERSION.to_string(),
            current_dense_backend: self.active_dense_backend_id(),
            current_sparse_backend: collection.sparse_backend.clone(),
            current_store: self.store_direction(),
            backends: vec![
                EmbeddingBackendCandidate {
                    backend_id: "beagle-local-fallback-dense".to_string(),
                    backend_kind: "current-baseline".to_string(),
                    provider: "beagle-local".to_string(),
                    model_family: "lexical-dense-proxy".to_string(),
                    serving_mode: if self.active_dense_backend_id() == "local-fallback-dense" {
                        "active".to_string()
                    } else {
                        "fallback".to_string()
                    },
                    self_hosted: true,
                    multilingual_ready: false,
                    code_retrieval_ready: false,
                    sovereign_fit: "high".to_string(),
                    qdrant_fit: "medium".to_string(),
                    recommended_scope: "bounded fallback only".to_string(),
                    note: "Useful as a sovereign fallback and smoke path, but not strong enough as the long-term dense backbone.".to_string(),
                },
                EmbeddingBackendCandidate {
                    backend_id: self.dense_backend.promoted_backend_id.clone(),
                    backend_kind: "api-general-purpose".to_string(),
                    provider: self.dense_backend.promoted_provider.clone(),
                    model_family: self.dense_backend.promoted_model.clone(),
                    serving_mode: if self.dense_backend.semantic_path_enabled() {
                        "active".to_string()
                    } else {
                        "promoted-auth-blocked".to_string()
                    },
                    self_hosted: false,
                    multilingual_ready: true,
                    code_retrieval_ready: true,
                    sovereign_fit: "medium".to_string(),
                    qdrant_fit: "high".to_string(),
                    recommended_scope: "general retrieval default".to_string(),
                    note: "Promoted general-purpose dense backend for the canonical retrieval spine when provider access is available.".to_string(),
                },
                EmbeddingBackendCandidate {
                    backend_id: self.dense_backend.code_backend_id.clone(),
                    backend_kind: "api-code-oriented".to_string(),
                    provider: "voyage".to_string(),
                    model_family: "voyage-code".to_string(),
                    serving_mode: "candidate".to_string(),
                    self_hosted: false,
                    multilingual_ready: false,
                    code_retrieval_ready: true,
                    sovereign_fit: "medium".to_string(),
                    qdrant_fit: "high".to_string(),
                    recommended_scope: "code retrieval lane".to_string(),
                    note: "Best kept as a specialized candidate for code-heavy workstream and repository retrieval.".to_string(),
                },
                EmbeddingBackendCandidate {
                    backend_id: self.dense_backend.sovereign_backend_id.clone(),
                    backend_kind: "self-hosted-multilingual".to_string(),
                    provider: "bge".to_string(),
                    model_family: "bge-m3".to_string(),
                    serving_mode: "candidate".to_string(),
                    self_hosted: true,
                    multilingual_ready: true,
                    code_retrieval_ready: false,
                    sovereign_fit: "high".to_string(),
                    qdrant_fit: "high".to_string(),
                    recommended_scope: "multilingual and sovereign retrieval".to_string(),
                    note: "Most attractive self-hosted option when sovereignty and multilingual recall matter more than turnkey managed APIs.".to_string(),
                },
            ],
            note: "The current hybrid retrieval spine keeps Qdrant as the preferred store direction while separating dense backend choice from storage.".to_string(),
        }
    }

    pub fn reranking_profile(&self) -> RerankingProfile {
        RerankingProfile {
            profile_version: RERANKING_PROFILE_VERSION.to_string(),
            profile_id: "b228-bounded-reranking-pilot".to_string(),
            current_state: "pilot-live-bounded".to_string(),
            current_mode: "top-k-reranking-pilot".to_string(),
            bounded_top_k: 5,
            general_candidate_id: self.reranking_runtime.general_backend_id.clone(),
            sovereign_candidate_id: self.reranking_runtime.sovereign_backend_id.clone(),
            candidates: vec![
                RerankingCandidate {
                    candidate_id: self.reranking_runtime.general_backend_id.clone(),
                    provider: "voyage".to_string(),
                    model: self.reranking_runtime.general_model.clone(),
                    candidate_kind: "cross-encoder".to_string(),
                    route_scope: "general".to_string(),
                    serving_mode: "pilot".to_string(),
                    runtime_state: self.reranking_runtime.general_runtime_state().to_string(),
                    self_hosted: false,
                    multilingual_ready: true,
                    code_retrieval_ready: true,
                    latency_class: "medium".to_string(),
                    endpoint_ref: self.reranking_runtime.general_endpoint_ref.clone(),
                    recommended_scope: "manuscript, review bundle, and short-list refinement".to_string(),
                    note: "B22.8 promotes Voyage rerank-2.5 as the bounded general reranking pilot on top of the canonical general retrieval lane.".to_string(),
                },
                RerankingCandidate {
                    candidate_id: "voyage-rerank-2.5-lite".to_string(),
                    provider: "voyage".to_string(),
                    model: "rerank-2.5-lite".to_string(),
                    candidate_kind: "cross-encoder".to_string(),
                    route_scope: "general-latency-fallback".to_string(),
                    serving_mode: "candidate".to_string(),
                    runtime_state: "not-selected".to_string(),
                    self_hosted: false,
                    multilingual_ready: true,
                    code_retrieval_ready: true,
                    latency_class: "lower".to_string(),
                    endpoint_ref: self.reranking_runtime.general_endpoint_ref.clone(),
                    recommended_scope: "general retrieval when rerank-2.5 latency is materially worse".to_string(),
                    note: "Kept as a bounded fallback candidate; B22.8 does not promote the lite model unless latency evidence clearly justifies it.".to_string(),
                },
                RerankingCandidate {
                    candidate_id: self.reranking_runtime.sovereign_backend_id.clone(),
                    provider: "bge".to_string(),
                    model: self.reranking_runtime.sovereign_model.clone(),
                    candidate_kind: "cross-encoder".to_string(),
                    route_scope: "sovereign".to_string(),
                    serving_mode: "pilot".to_string(),
                    runtime_state: self.reranking_runtime.sovereign_runtime_state().to_string(),
                    self_hosted: true,
                    multilingual_ready: true,
                    code_retrieval_ready: false,
                    latency_class: "medium-high".to_string(),
                    endpoint_ref: self.reranking_runtime.sovereign_endpoint_ref.clone(),
                    recommended_scope: "multilingual, sovereign, privacy-sensitive, or offline-capable short-list refinement".to_string(),
                    note: "B22.8 promotes a self-hosted BGE reranker lane without changing the canonical Qdrant-backed retrieval architecture.".to_string(),
                },
            ],
            note: "B22.8 keeps reranking bounded to top-k pilot lanes and does not make late interaction a global canonical retrieval stage.".to_string(),
        }
    }

    pub fn code_retrieval_backend_profile(&self) -> CodeRetrievalBackendProfile {
        CodeRetrievalBackendProfile {
            profile_version: CODE_RETRIEVAL_RESULT_VERSION.to_string(),
            backend_id: self.active_code_dense_backend_id(),
            provider: "voyage".to_string(),
            model: self.dense_backend.code_backend_id.clone(),
            runtime_state: if self.code_dense_index.is_some() {
                "pilot-active".to_string()
            } else if self.dense_backend.endpoint_ref.is_some() {
                "pilot-auth-blocked-fallback".to_string()
            } else {
                "pilot-endpoint-missing-fallback".to_string()
            },
            store_direction: "canonical-payload-local-dense-pilot".to_string(),
            note: "B22.5 keeps the canonical payload model intact while evaluating voyage-code-3 over local candidate records to avoid reindexing the general dense collection.".to_string(),
        }
    }

    pub fn sovereign_retrieval_backend_profile(&self) -> SovereignRetrievalBackendProfile {
        SovereignRetrievalBackendProfile {
            profile_version: SOVEREIGN_RETRIEVAL_RESULT_VERSION.to_string(),
            backend_id: self.active_sovereign_dense_backend_id(),
            provider: "bge".to_string(),
            model: self.dense_backend.sovereign_model.clone(),
            runtime_state: if self.sovereign_dense_index.is_some() {
                "sovereign-active".to_string()
            } else if self.dense_backend.sovereign_endpoint_ref.is_some() {
                "sovereign-endpoint-configured-fallback".to_string()
            } else {
                "sovereign-endpoint-missing-fallback".to_string()
            },
            endpoint_ref: self.dense_backend.sovereign_endpoint_ref.clone(),
            store_direction: "canonical-payload-self-hosted-sovereign-track".to_string(),
            note: "B22.6 keeps the canonical payload model intact while evaluating self-hosted BGE-M3 over local candidate records for multilingual and sovereign retrieval.".to_string(),
        }
    }

    pub fn classify_retrieval_query(&self, q: &RoutedRetrievalQuery) -> RetrievalQueryType {
        let requested_hint = q
            .query_type_hint
            .as_ref()
            .map(|value| normalize_router_selector(value));

        let (selected_query_type, classifier_source, classifier_reason) =
            if let Some(normalized_hint) = requested_hint.as_deref() {
                if let Some(mapped_hint) = normalize_query_type_hint(normalized_hint) {
                    (
                        mapped_hint.to_string(),
                        "explicit-hint".to_string(),
                        format!("query_type_hint={} requested an explicit router lane", mapped_hint),
                    )
                } else {
                    (
                        "general".to_string(),
                        "invalid-hint-fallback".to_string(),
                        format!(
                            "query_type_hint={} is not a supported router class; falling back to general",
                            normalized_hint
                        ),
                    )
                }
            } else if filters_signal_code(&q.filters) {
                (
                    "code".to_string(),
                    "payload-filter".to_string(),
                    "repo_path or file_type filter requested a repo-native code retrieval lane"
                        .to_string(),
                )
            } else if query_text_signals_code(&q.query_text) {
                (
                    "code".to_string(),
                    "content-heuristic".to_string(),
                    "query text contains code/path/config/script signals".to_string(),
                )
            } else if query_text_signals_sovereign(&q.query_text) {
                (
                    "sovereign".to_string(),
                    "content-heuristic".to_string(),
                    "query text contains multilingual, sovereign, privacy-sensitive, or offline-capable signals".to_string(),
                )
            } else {
                (
                    "general".to_string(),
                    "default-general".to_string(),
                    "no stronger code or sovereign signal was present, so the canonical general dense lane remains selected".to_string(),
                )
            };

        RetrievalQueryType {
            query_type_version: QUERY_TYPE_VERSION.to_string(),
            router_version: RETRIEVAL_ROUTER_VERSION.to_string(),
            query_text: q.query_text.clone(),
            requested_hint,
            selected_query_type,
            classifier_source,
            classifier_reason,
        }
    }

    pub fn retrieval_routing_decision(
        &self,
        q: &RoutedRetrievalQuery,
    ) -> RetrievalRoutingDecision {
        let query_type = self.classify_retrieval_query(q);
        let (selected_route, selected_dense_backend, note) =
            match query_type.selected_query_type.as_str() {
                "code" => (
                    "code".to_string(),
                    self.active_code_dense_backend_id(),
                    "B22.7 routes repo-native code/config/script questions into the dedicated voyage-code-3 pilot while preserving sparse lexical search.".to_string(),
                ),
                "sovereign" => (
                    "sovereign".to_string(),
                    self.active_sovereign_dense_backend_id(),
                    "B22.7 routes multilingual, sovereign, privacy-sensitive, or offline-capable queries into the BGE-M3 self-hosted lane while preserving sparse lexical search.".to_string(),
                ),
                _ => (
                    "general".to_string(),
                    self.active_dense_backend_id(),
                    "B22.7 keeps the canonical voyage-4-large lane as the default path for general workstream, campaign, and memory retrieval.".to_string(),
                ),
            };

        RetrievalRoutingDecision {
            decision_version: RETRIEVAL_ROUTING_DECISION_VERSION.to_string(),
            router_version: RETRIEVAL_ROUTER_VERSION.to_string(),
            query_type: query_type.selected_query_type.clone(),
            selected_route,
            selected_dense_backend,
            sparse_backend: "local-lexical".to_string(),
            payload_filters_present: retrieval_filters_present(&q.filters),
            compare_against_general: q.compare_against_general,
            routing_source: query_type.classifier_source.clone(),
            routing_reason: query_type.classifier_reason.clone(),
            note,
        }
    }

    pub async fn routed_retrieve(&self, q: RoutedRetrievalQuery) -> Result<RoutedRetrievalResult> {
        let decision = self.retrieval_routing_decision(&q);

        match decision.selected_route.as_str() {
            "code" => {
                let result = self
                    .code_retrieve(CodeRetrievalQuery {
                        query_version: crate::retrieval::CODE_RETRIEVAL_QUERY_VERSION.to_string(),
                        query_text: q.query_text.clone(),
                        top_k: q.top_k,
                        dense_enabled: q.dense_enabled,
                        sparse_enabled: q.sparse_enabled,
                        dense_weight: q.dense_weight,
                        sparse_weight: q.sparse_weight,
                        filters: q.filters.clone(),
                        compare_against_general: q.compare_against_general,
                        rerank_hint: q.rerank_hint.clone(),
                    })
                    .await?;

                Ok(RoutedRetrievalResult {
                    result_version: ROUTED_RETRIEVAL_RESULT_VERSION.to_string(),
                    retrieval_mode: result.retrieval_mode,
                    collection_name: result.collection_name,
                    query_type: decision.query_type.clone(),
                    routing_decision: decision,
                    dense_backend: result.code_dense_backend,
                    sparse_backend: result.sparse_backend,
                    top_k: result.top_k,
                    applied_filters: result.applied_filters,
                    dense_hit_count: result.dense_hit_count,
                    sparse_hit_count: result.sparse_hit_count,
                    hits: result.hits,
                    comparison_general_dense_backend: result
                        .comparison
                        .as_ref()
                        .map(|comparison| comparison.general_dense_backend.clone()),
                    comparison_changed_top_hit: result
                        .comparison
                        .as_ref()
                        .map(|comparison| comparison.top_hit_changed),
                    note: "B22.7 router selected the bounded code retrieval lane while preserving payload-aware filters and sparse lexical support.".to_string(),
                })
            }
            "sovereign" => {
                let result = self
                    .sovereign_retrieve(SovereignRetrievalQuery {
                        query_version: crate::retrieval::SOVEREIGN_RETRIEVAL_QUERY_VERSION
                            .to_string(),
                        query_text: q.query_text.clone(),
                        top_k: q.top_k,
                        dense_enabled: q.dense_enabled,
                        sparse_enabled: q.sparse_enabled,
                        dense_weight: q.dense_weight,
                        sparse_weight: q.sparse_weight,
                        filters: q.filters.clone(),
                        compare_against_general: q.compare_against_general,
                        rerank_hint: q.rerank_hint.clone(),
                    })
                    .await?;

                Ok(RoutedRetrievalResult {
                    result_version: ROUTED_RETRIEVAL_RESULT_VERSION.to_string(),
                    retrieval_mode: result.retrieval_mode,
                    collection_name: result.collection_name,
                    query_type: decision.query_type.clone(),
                    routing_decision: decision,
                    dense_backend: result.sovereign_dense_backend,
                    sparse_backend: result.sparse_backend,
                    top_k: result.top_k,
                    applied_filters: result.applied_filters,
                    dense_hit_count: result.dense_hit_count,
                    sparse_hit_count: result.sparse_hit_count,
                    hits: result.hits,
                    comparison_general_dense_backend: result
                        .comparison
                        .as_ref()
                        .map(|comparison| comparison.general_dense_backend.clone()),
                    comparison_changed_top_hit: result
                        .comparison
                        .as_ref()
                        .map(|comparison| comparison.top_hit_changed),
                    note: "B22.7 router selected the sovereign multilingual lane while preserving payload-aware filters and sparse lexical support.".to_string(),
                })
            }
            _ => {
                let result = self
                    .hybrid_retrieve(RetrievalQuery {
                        query_version: crate::retrieval::RETRIEVAL_QUERY_VERSION.to_string(),
                        query_text: q.query_text.clone(),
                        top_k: q.top_k,
                        dense_enabled: q.dense_enabled,
                        sparse_enabled: q.sparse_enabled,
                        dense_weight: q.dense_weight,
                        sparse_weight: q.sparse_weight,
                        filters: q.filters.clone(),
                        rerank_hint: q.rerank_hint.clone(),
                    })
                    .await?;

                Ok(RoutedRetrievalResult {
                    result_version: ROUTED_RETRIEVAL_RESULT_VERSION.to_string(),
                    retrieval_mode: result.retrieval_mode,
                    collection_name: result.collection_name,
                    query_type: decision.query_type.clone(),
                    routing_decision: decision,
                    dense_backend: result.dense_backend,
                    sparse_backend: result.sparse_backend,
                    top_k: result.top_k,
                    applied_filters: result.applied_filters,
                    dense_hit_count: result.dense_hit_count,
                    sparse_hit_count: result.sparse_hit_count,
                    hits: result.hits,
                    comparison_general_dense_backend: None,
                    comparison_changed_top_hit: None,
                    note: "B22.7 router selected the canonical general dense lane while preserving payload-aware filters and sparse lexical support.".to_string(),
                })
            }
        }
    }

    pub async fn reranked_routed_retrieve(
        &self,
        q: RoutedRetrievalQuery,
    ) -> Result<RerankedResult> {
        let profile = self.reranking_profile();
        let prerank_started_at = Instant::now();
        let prerank = self.routed_retrieve(q.clone()).await?;
        let prerank_latency_ms = prerank_started_at.elapsed().as_millis() as u64;
        let prerank_top_memory_ids = prerank
            .hits
            .iter()
            .map(|hit| hit.point.payload.memory_id.clone())
            .collect::<Vec<_>>();
        let relevance_proxy_before =
            relevance_proxy_for_hits(&prerank.hits, &q.query_text, &[]);
        let rerank_started_at = Instant::now();
        let rerank_outcome = self.rerank_hits_for_lane(&q, &prerank).await;
        let rerank_latency_ms = rerank_started_at.elapsed().as_millis() as u64;
        let total_latency_ms = prerank_latency_ms.saturating_add(rerank_latency_ms);

        match rerank_outcome {
            Ok(Some((reranker_backend, reranker_kind, reranker_runtime_state, reranked_hits))) => {
                let postrank_top_memory_ids = reranked_hits
                    .iter()
                    .map(|hit| hit.point.payload.memory_id.clone())
                    .collect::<Vec<_>>();
                let relevance_proxy_after =
                    relevance_proxy_for_reranked_hits(&reranked_hits, &q.query_text);
                let top_hit_changed =
                    prerank_top_memory_ids.first() != postrank_top_memory_ids.first();
                let recommendation = reranking_recommendation_for_lane(
                    &prerank.routing_decision.query_type,
                    &reranker_backend,
                    &reranker_runtime_state,
                    true,
                    top_hit_changed,
                    relevance_proxy_before,
                    relevance_proxy_after,
                    rerank_latency_ms,
                );

                Ok(RerankedResult {
                    result_version: RERANKED_RESULT_VERSION.to_string(),
                    profile_id: profile.profile_id,
                    query_type: prerank.query_type.clone(),
                    routing_decision: prerank.routing_decision.clone(),
                    collection_name: prerank.collection_name.clone(),
                    prerank_retrieval_mode: prerank.retrieval_mode.clone(),
                    postrank_retrieval_mode: format!("{}+rerank", prerank.retrieval_mode),
                    dense_backend: prerank.dense_backend.clone(),
                    sparse_backend: prerank.sparse_backend.clone(),
                    reranker_backend,
                    reranker_kind,
                    reranker_runtime_state,
                    reranking_applied: true,
                    top_k: prerank.top_k,
                    candidate_count: prerank.hits.len(),
                    applied_filters: prerank.applied_filters.clone(),
                    prerank_hit_count: prerank.hits.len(),
                    postrank_hit_count: reranked_hits.len(),
                    prerank_top_memory_ids,
                    postrank_top_memory_ids,
                    relevance_proxy_before,
                    relevance_proxy_after,
                    latency: RerankingLatencyComparison {
                        prerank_latency_ms,
                        rerank_latency_ms,
                        total_latency_ms,
                        latency_delta_ms: rerank_latency_ms,
                    },
                    hits: reranked_hits,
                    recommendation,
                    note: "B22.8 applies bounded top-k reranking on top of the routed retrieval lane without replacing the canonical dense backends, sparse path, or payload-aware filters.".to_string(),
                })
            }
            Ok(None) => {
                let fallback_hits = prerank
                    .hits
                    .iter()
                    .enumerate()
                    .map(|(index, hit)| RerankedHit {
                        rank: index + 1,
                        prerank_rank: hit.rank,
                        point: hit.point.clone(),
                        dense_score: hit.dense_score,
                        sparse_score: hit.sparse_score,
                        hybrid_score: hit.hybrid_score,
                        rerank_score: hit.hybrid_score,
                    })
                    .collect::<Vec<_>>();
                let recommendation = reranking_recommendation_for_lane(
                    &prerank.routing_decision.query_type,
                    "rerank-disabled",
                    "not-enabled-for-route",
                    false,
                    false,
                    relevance_proxy_before,
                    relevance_proxy_before,
                    rerank_latency_ms,
                );

                Ok(RerankedResult {
                    result_version: RERANKED_RESULT_VERSION.to_string(),
                    profile_id: profile.profile_id,
                    query_type: prerank.query_type.clone(),
                    routing_decision: prerank.routing_decision.clone(),
                    collection_name: prerank.collection_name.clone(),
                    prerank_retrieval_mode: prerank.retrieval_mode.clone(),
                    postrank_retrieval_mode: prerank.retrieval_mode.clone(),
                    dense_backend: prerank.dense_backend.clone(),
                    sparse_backend: prerank.sparse_backend.clone(),
                    reranker_backend: "rerank-disabled".to_string(),
                    reranker_kind: "disabled".to_string(),
                    reranker_runtime_state: "not-enabled-for-route".to_string(),
                    reranking_applied: false,
                    top_k: prerank.top_k,
                    candidate_count: prerank.hits.len(),
                    applied_filters: prerank.applied_filters.clone(),
                    prerank_hit_count: prerank.hits.len(),
                    postrank_hit_count: fallback_hits.len(),
                    prerank_top_memory_ids: prerank_top_memory_ids.clone(),
                    postrank_top_memory_ids: prerank_top_memory_ids,
                    relevance_proxy_before,
                    relevance_proxy_after: relevance_proxy_before,
                    latency: RerankingLatencyComparison {
                        prerank_latency_ms,
                        rerank_latency_ms,
                        total_latency_ms,
                        latency_delta_ms: rerank_latency_ms,
                    },
                    hits: fallback_hits,
                    recommendation,
                    note: "B22.8 keeps code retrieval on the routed baseline while the reranking pilot stays bounded to general and sovereign lanes.".to_string(),
                })
            }
            Err(error) => {
                warn!(%error, "Reranking pilot failed; returning bounded prerank ordering");
                let fallback_hits = prerank
                    .hits
                    .iter()
                    .enumerate()
                    .map(|(index, hit)| RerankedHit {
                        rank: index + 1,
                        prerank_rank: hit.rank,
                        point: hit.point.clone(),
                        dense_score: hit.dense_score,
                        sparse_score: hit.sparse_score,
                        hybrid_score: hit.hybrid_score,
                        rerank_score: hit.hybrid_score,
                    })
                    .collect::<Vec<_>>();
                let recommendation = reranking_recommendation_for_lane(
                    &prerank.routing_decision.query_type,
                    "rerank-fallback",
                    "pilot-error-fallback",
                    false,
                    false,
                    relevance_proxy_before,
                    relevance_proxy_before,
                    rerank_latency_ms,
                );

                Ok(RerankedResult {
                    result_version: RERANKED_RESULT_VERSION.to_string(),
                    profile_id: profile.profile_id,
                    query_type: prerank.query_type.clone(),
                    routing_decision: prerank.routing_decision.clone(),
                    collection_name: prerank.collection_name.clone(),
                    prerank_retrieval_mode: prerank.retrieval_mode.clone(),
                    postrank_retrieval_mode: prerank.retrieval_mode.clone(),
                    dense_backend: prerank.dense_backend.clone(),
                    sparse_backend: prerank.sparse_backend.clone(),
                    reranker_backend: "rerank-fallback".to_string(),
                    reranker_kind: "fallback".to_string(),
                    reranker_runtime_state: "pilot-error-fallback".to_string(),
                    reranking_applied: false,
                    top_k: prerank.top_k,
                    candidate_count: prerank.hits.len(),
                    applied_filters: prerank.applied_filters.clone(),
                    prerank_hit_count: prerank.hits.len(),
                    postrank_hit_count: fallback_hits.len(),
                    prerank_top_memory_ids: prerank_top_memory_ids.clone(),
                    postrank_top_memory_ids: prerank_top_memory_ids,
                    relevance_proxy_before,
                    relevance_proxy_after: relevance_proxy_before,
                    latency: RerankingLatencyComparison {
                        prerank_latency_ms,
                        rerank_latency_ms,
                        total_latency_ms,
                        latency_delta_ms: rerank_latency_ms,
                    },
                    hits: fallback_hits,
                    recommendation,
                    note: format!(
                        "B22.8 pilot reranking failed and fell back to prerank ordering: {}",
                        error
                    ),
                })
            }
        }
    }

    pub async fn benchmark_retrieval(
        &self,
        request: RetrievalBenchmarkRequest,
    ) -> Result<RetrievalBenchmarkReport> {
        let RetrievalBenchmarkRequest {
            benchmark_version: _,
            cases: request_cases,
            top_k_stability_runs,
            reranking_profile_id,
        } = request;
        let collection = self.retrieval_collection();
        let reranking_profile = self.reranking_profile();
        let stability_runs = top_k_stability_runs.clamp(1, 5).max(2);
        let mut cases = Vec::new();

        for case in request_cases.into_iter() {
            let start = Instant::now();
            let result = self.hybrid_retrieve(case.query.clone()).await?;
            let latency_ms = start.elapsed().as_millis() as u64;
            let baseline_ids = result
                .hits
                .iter()
                .map(|hit| hit.point.payload.memory_id.clone())
                .collect::<Vec<_>>();
            let mut stable = true;
            for _ in 1..stability_runs {
                let rerun = self.hybrid_retrieve(case.query.clone()).await?;
                let rerun_ids = rerun
                    .hits
                    .iter()
                    .map(|hit| hit.point.payload.memory_id.clone())
                    .collect::<Vec<_>>();
                if rerun_ids != baseline_ids {
                    stable = false;
                    break;
                }
            }

            let hit_count = result.hits.len();
            let filter_correctness = filter_correctness_for_hits(&result.hits, &case.query.filters);
            let relevance_proxy_score =
                relevance_proxy_for_hits(&result.hits, &case.query.query_text, &case.expected_memory_ids);
            let context_packet_usable_hit_count = result
                .hits
                .iter()
                .filter(|hit| retrieval_hit_is_context_usable(hit))
                .count();
            let top_hit = result.hits.first();
            let note = benchmark_case_note(&collection.dense_backend, &case, &result);

            cases.push(RetrievalBenchmarkCaseReport {
                case_id: case.case_id,
                case_kind: case.case_kind,
                description: case.description.clone(),
                retrieval_mode: result.retrieval_mode.clone(),
                latency_ms,
                hit_count,
                dense_hit_count: result.dense_hit_count,
                sparse_hit_count: result.sparse_hit_count,
                payload_filter_correctness: filter_correctness,
                relevance_proxy_score,
                top_k_stable: stable,
                context_packet_usable_hit_count,
                top_hit_memory_id: top_hit.map(|hit| hit.point.payload.memory_id.clone()),
                top_hit_source: top_hit.map(|hit| hit.point.payload.source.clone()),
                top_hit_workstream_id: top_hit.and_then(|hit| hit.point.payload.workstream_id.clone()),
                top_hit_tags: top_hit
                    .map(|hit| hit.point.payload.tags.clone())
                    .unwrap_or_default(),
                note,
            });
        }

        let case_count = cases.len();
        let average_latency_ms = average_f32(cases.iter().map(|case| case.latency_ms as f32));
        let average_filter_correctness =
            average_f32(cases.iter().map(|case| case.payload_filter_correctness));
        let average_relevance_proxy =
            average_f32(cases.iter().map(|case| case.relevance_proxy_score));
        let top_k_stability_pass_rate = average_f32(
            cases
                .iter()
                .map(|case| if case.top_k_stable { 1.0 } else { 0.0 }),
        );
        let context_packet_usable_case_count = cases
            .iter()
            .filter(|case| case.context_packet_usable_hit_count > 0)
            .count();
        let recommendation = retrieval_recommendation_for(
            &collection,
            &self.embedding_backend_matrix(),
            &reranking_profile,
            &cases,
        );
        let reranking_profile_id = reranking_profile_id
            .unwrap_or_else(|| reranking_profile.profile_id.clone());

        Ok(RetrievalBenchmarkReport {
            benchmark_version: RETRIEVAL_BENCHMARK_VERSION.to_string(),
            collection_name: collection.collection_name.clone(),
            dense_backend: collection.dense_backend.clone(),
            sparse_backend: collection.sparse_backend.clone(),
            reranking_profile_id: reranking_profile_id.clone(),
            summary: RetrievalBenchmarkSummary {
                benchmark_version: RETRIEVAL_BENCHMARK_VERSION.to_string(),
                collection_name: collection.collection_name.clone(),
                dense_backend: collection.dense_backend.clone(),
                sparse_backend: collection.sparse_backend.clone(),
                reranking_profile_id,
                case_count,
                average_latency_ms,
                average_filter_correctness,
                average_relevance_proxy,
                top_k_stability_pass_rate,
                context_packet_usable_case_count,
                note: "Benchmark summary over the canonical B22.1 retrieval spine with baseline, filtered, and role-specific cases.".to_string(),
            },
            recommendation,
            cases,
            note: "B22.2 benchmark report compares the current hybrid retrieval baseline against explicit upgrade candidates without replatforming the retrieval spine.".to_string(),
        })
    }

    pub async fn evaluate_retrieval(
        &self,
        request: RetrievalEvalRequest,
    ) -> Result<RetrievalEvalReport> {
        let RetrievalEvalRequest {
            report_version: _,
            cases: request_cases,
            top_k_stability_runs,
        } = request;
        let collection = self.retrieval_collection();
        let reranking_profile = self.reranking_profile();
        let generated_at = Utc::now().to_rfc3339();
        let stability_runs = top_k_stability_runs.clamp(1, 3);
        let mut cases = Vec::new();

        for case in request_cases.into_iter() {
            let start = Instant::now();
            let result = self.reranked_routed_retrieve(case.query.clone()).await?;
            let latency_ms = start.elapsed().as_millis() as u64;
            let baseline_ids = result.postrank_top_memory_ids.clone();
            let mut stable = true;

            for _ in 1..stability_runs {
                let rerun = self.reranked_routed_retrieve(case.query.clone()).await?;
                if rerun.postrank_top_memory_ids != baseline_ids {
                    stable = false;
                    break;
                }
            }

            let filter_correctness =
                filter_correctness_for_reranked_hits(&result.hits, &case.query.filters);
            let relevance_proxy_score = relevance_proxy_for_feedback_hits(
                &result.hits,
                &case.query.query_text,
                &case.expected_memory_ids,
            );
            let context_packet_usable_hit_count = result
                .hits
                .iter()
                .filter(|hit| reranked_hit_is_context_usable(hit))
                .count();
            let route_appropriate = result
                .routing_decision
                .selected_route
                .eq_ignore_ascii_case(&case.query_type);
            let top_hit_memory_id = result
                .hits
                .first()
                .map(|hit| hit.point.payload.memory_id.clone());

            cases.push(RetrievalEvalCaseReport {
                case_id: case.case_id,
                query_type: case.query_type.clone(),
                description: case.description.clone(),
                selected_route: result.routing_decision.selected_route.clone(),
                dense_backend: result.dense_backend.clone(),
                sparse_backend: result.sparse_backend.clone(),
                reranker_backend: result.reranker_backend.clone(),
                reranking_applied: result.reranking_applied,
                latency_ms,
                relevance_proxy_score,
                payload_filter_correctness: filter_correctness,
                top_k_stable: stable,
                route_appropriate,
                context_packet_usable_hit_count,
                top_hit_memory_id,
                expected_memory_ids: case.expected_memory_ids.clone(),
                note: eval_case_note(&case.query_type, &case.query.query_text, &result),
            });
        }

        let lane_order = ["general", "code", "sovereign"];
        let lanes = lane_order
            .iter()
            .filter_map(|query_type| {
                let lane_cases = cases
                    .iter()
                    .filter(|case| case.query_type == *query_type)
                    .collect::<Vec<_>>();
                if lane_cases.is_empty() {
                    return None;
                }

                let first = lane_cases[0];
                Some(RetrievalEvalLaneSummary {
                    query_type: (*query_type).to_string(),
                    selected_route: first.selected_route.clone(),
                    dense_backend: first.dense_backend.clone(),
                    sparse_backend: first.sparse_backend.clone(),
                    reranker_backend: first.reranker_backend.clone(),
                    case_count: lane_cases.len(),
                    average_latency_ms: average_f32(
                        lane_cases.iter().map(|case| case.latency_ms as f32),
                    ),
                    average_relevance_proxy: average_f32(
                        lane_cases.iter().map(|case| case.relevance_proxy_score),
                    ),
                    average_filter_correctness: average_f32(
                        lane_cases
                            .iter()
                            .map(|case| case.payload_filter_correctness),
                    ),
                    top_k_stability_pass_rate: average_f32(
                        lane_cases.iter().map(|case| {
                            if case.top_k_stable {
                                1.0
                            } else {
                                0.0
                            }
                        }),
                    ),
                    route_appropriateness_rate: average_f32(
                        lane_cases.iter().map(|case| {
                            if case.route_appropriate {
                                1.0
                            } else {
                                0.0
                            }
                        }),
                    ),
                    average_context_packet_usable_hits: average_f32(
                        lane_cases
                            .iter()
                            .map(|case| case.context_packet_usable_hit_count as f32),
                    ),
                    recommended_when: recommended_when_for_query_type(query_type),
                    note: eval_lane_note(query_type, &lane_cases),
                })
            })
            .collect::<Vec<_>>();

        Ok(RetrievalEvalReport {
            report_version: RETRIEVAL_EVAL_REPORT_VERSION.to_string(),
            collection_name: collection.collection_name,
            sparse_backend: collection.sparse_backend,
            reranking_profile_id: reranking_profile.profile_id,
            generated_at,
            cases,
            lanes,
            note: "B22.9 evaluates the live routed retrieval lanes and keeps routing policy evidence-backed instead of heuristic-only.".to_string(),
        })
    }

    pub async fn feedback_adjusted_routed_retrieve(
        &self,
        input: RelevanceFeedbackInput,
    ) -> Result<FeedbackLoopResult> {
        let profile = self.reranking_profile();
        let prerank_started_at = Instant::now();
        let prerank = self.reranked_routed_retrieve(input.query.clone()).await?;
        let prerank_latency_ms = prerank_started_at.elapsed().as_millis() as u64;
        let relevance_proxy_before = relevance_proxy_for_feedback_hits(
            &prerank.hits,
            &input.query.query_text,
            &input.expected_memory_ids,
        );
        let prerank_top_memory_ids = prerank.postrank_top_memory_ids.clone();

        let feedback_started_at = Instant::now();
        let feedback_hits = apply_feedback_judgments_to_hits(&prerank.hits, &input.judgments);
        let feedback_adjustment_latency_ms =
            feedback_started_at.elapsed().as_millis() as u64;
        let total_latency_ms = prerank_latency_ms.saturating_add(feedback_adjustment_latency_ms);
        let postfeedback_top_memory_ids = feedback_hits
            .iter()
            .map(|hit| hit.point.payload.memory_id.clone())
            .collect::<Vec<_>>();
        let relevance_proxy_after = relevance_proxy_for_feedback_adjusted_hits(
            &feedback_hits,
            &input.query.query_text,
            &input.expected_memory_ids,
        );
        let top_hit_changed = prerank_top_memory_ids.first() != postfeedback_top_memory_ids.first();
        let improvement_observed = relevance_proxy_after > relevance_proxy_before || top_hit_changed;
        let feedback_applied = input
            .judgments
            .iter()
            .any(|judgment| feedback_signal_score(judgment) != 0.0);

        Ok(FeedbackLoopResult {
            result_version: RELEVANCE_FEEDBACK_VERSION.to_string(),
            profile_id: profile.profile_id,
            feedback_version: RELEVANCE_FEEDBACK_VERSION.to_string(),
            query_type: prerank.query_type.clone(),
            routing_decision: prerank.routing_decision.clone(),
            collection_name: prerank.collection_name.clone(),
            dense_backend: prerank.dense_backend.clone(),
            sparse_backend: prerank.sparse_backend.clone(),
            reranker_backend: prerank.reranker_backend.clone(),
            reranking_applied: prerank.reranking_applied,
            feedback_strategy: "top-k-score-adjustment".to_string(),
            feedback_applied,
            feedback_round: input.feedback_round,
            top_k: prerank.top_k,
            candidate_count: prerank.hits.len(),
            applied_filters: prerank.applied_filters.clone(),
            prerank_hit_count: prerank.hits.len(),
            postfeedback_hit_count: feedback_hits.len(),
            prerank_top_memory_ids,
            postfeedback_top_memory_ids,
            relevance_proxy_before,
            relevance_proxy_after,
            top_hit_changed,
            improvement_observed,
            latency: FeedbackLatencyComparison {
                prerank_latency_ms,
                feedback_adjustment_latency_ms,
                total_latency_ms,
                latency_delta_ms: feedback_adjustment_latency_ms,
            },
            hits: feedback_hits,
            note: input.note.unwrap_or_else(|| {
                "B22.9 applies bounded relevance feedback on top of the routed and optionally reranked retrieval result without changing the canonical backends or store.".to_string()
            }),
        })
    }

    pub fn derive_retrieval_policy(&self, report: &RetrievalEvalReport) -> RetrievalPolicy {
        let lanes = report
            .lanes
            .iter()
            .map(|lane| RetrievalPolicyLane {
                query_type: lane.query_type.clone(),
                selected_route: lane.selected_route.clone(),
                dense_backend: lane.dense_backend.clone(),
                sparse_backend: lane.sparse_backend.clone(),
                reranker_backend: lane.reranker_backend.clone(),
                feedback_mode: feedback_mode_for_lane(lane),
                current_state: "evidence-backed-live".to_string(),
                evidence_basis: vec![
                    format!("case_count={}", lane.case_count),
                    format!("average_relevance_proxy={:.3}", lane.average_relevance_proxy),
                    format!(
                        "average_filter_correctness={:.3}",
                        lane.average_filter_correctness
                    ),
                    format!(
                        "top_k_stability_pass_rate={:.3}",
                        lane.top_k_stability_pass_rate
                    ),
                    format!(
                        "route_appropriateness_rate={:.3}",
                        lane.route_appropriateness_rate
                    ),
                    format!(
                        "average_context_packet_usable_hits={:.3}",
                        lane.average_context_packet_usable_hits
                    ),
                ],
                last_eval_at: report.generated_at.clone(),
                recommended_when: lane.recommended_when.clone(),
                note: format!(
                    "B22.9 policy lane is evidence-backed by live eval metrics for the {} route.",
                    lane.query_type
                ),
            })
            .collect::<Vec<_>>();

        RetrievalPolicy {
            policy_version: RETRIEVAL_POLICY_VERSION.to_string(),
            policy_id: "b229-evidence-backed-retrieval-policy".to_string(),
            generated_at: report.generated_at.clone(),
            lanes,
            note: "B22.9 promotes an evidence-backed retrieval policy derived from live routed evaluation and bounded feedback, not from heuristics alone.".to_string(),
        }
    }

    pub fn memory_promotion_policy(&self) -> MemoryPromotionPolicy {
        memory_promotion_policy()
    }

    pub fn memory_retention_policy(&self) -> MemoryRetentionPolicy {
        memory_retention_policy()
    }

    pub fn temporal_memory_schema(&self) -> TemporalMemorySchema {
        temporal_memory_schema()
    }

    pub fn graph_rag_query_mode(&self, query: &GraphRagQuery) -> GraphRagQueryModeDecision {
        derive_graphrag_query_mode(query)
    }

    pub fn memory_compiler_contract(&self) -> MemoryCompilerContract {
        memory_compiler_contract()
    }

    pub fn context_budget_profile(&self, task_profile: &str) -> Result<ContextBudgetProfile> {
        context_budget_profile(task_profile).with_context(|| {
            format!(
                "unsupported task profile {}; expected one of implementation, analysis, interactive-editing, manuscript",
                task_profile
            )
        })
    }

    pub async fn evaluate_memory_promotion(
        &self,
        memory_id: &str,
    ) -> Result<Option<PromotedMemory>> {
        let record = self.local_index.record_by_id(memory_id).await;
        Ok(record.and_then(|record| {
            let target_memory_type = promoted_target_memory_type(&record)?;
            derive_memory_promotion(
                &record,
                Utc::now(),
                &retention_action_for_memory_type(&target_memory_type),
            )
        }))
    }

    pub async fn compile_context(
        &self,
        request: CompiledContextRequest,
    ) -> Result<CompiledContextPacket> {
        let profile = self.context_budget_profile(&request.task_profile)?;
        self.compile_context_with_profile(request, profile).await
    }

    async fn compile_context_with_profile(
        &self,
        request: CompiledContextRequest,
        profile: ContextBudgetProfile,
    ) -> Result<CompiledContextPacket> {
        let filters = RetrievalFilters {
            workstream_id: request.workstream_id.clone(),
            campaign_id: request.campaign_id.clone(),
            session_id: request.session_id.clone(),
            source: None,
            role: None,
            domain: None,
            repo_path: request.repo_path.clone(),
            file_type: request.file_type.clone(),
            tags: request.tags.clone(),
        };
        let (dense_weight, sparse_weight) = retrieval_weights_for_task_profile(&profile);
        let routed_query = RoutedRetrievalQuery {
            query_version: crate::retrieval::ROUTED_RETRIEVAL_QUERY_VERSION.to_string(),
            query_text: request.query_text.clone(),
            top_k: profile.max_context_items.max(4),
            dense_enabled: true,
            sparse_enabled: true,
            dense_weight,
            sparse_weight,
            filters: filters.clone(),
            query_type_hint: Some(profile.retrieval_query_type.clone()),
            compare_against_general: false,
            rerank_hint: request
                .rerank_hint
                .clone()
                .or_else(|| Some(format!("compiled-context-{}", profile.task_profile))),
        };
        let reranked = self.reranked_routed_retrieve(routed_query).await?;
        let graph_query = GraphRagQuery {
            query_version: crate::retrieval::GRAPHRAG_QUERY_VERSION.to_string(),
            query_text: request.query_text.clone(),
            top_k: profile.max_context_items.max(4),
            max_hops: if profile.graphrag_query_mode_hint == "local" { 2 } else { 3 },
            dense_enabled: true,
            sparse_enabled: true,
            dense_weight,
            sparse_weight,
            filters,
            root_entity_type: request.root_entity_type.clone(),
            root_entity_id: request.root_entity_id.clone(),
            program_id: request.program_id.clone(),
            include_memory_hierarchy: true,
            query_type_hint: Some(profile.retrieval_query_type.clone()),
            query_mode_hint: Some(profile.graphrag_query_mode_hint.clone()),
            rerank_hint: request
                .rerank_hint
                .clone()
                .or_else(|| Some(format!("compiled-context-graphrag-{}", profile.task_profile))),
        };
        let graphrag = self.graph_rag_query(graph_query).await?;
        let temporal_query = TemporalQuery {
            query_version: TEMPORAL_QUERY_VERSION.to_string(),
            query_text: request.query_text.clone(),
            truth_view: profile.temporal_truth_view.clone(),
            top_k: profile.max_context_items.max(4),
            dense_enabled: true,
            sparse_enabled: true,
            dense_weight,
            sparse_weight,
            filters: reranked.applied_filters.clone(),
            root_entity_type: request.root_entity_type.clone(),
            root_entity_id: request.root_entity_id.clone(),
            subject_refs: Vec::new(),
            include_contradictions: profile.include_temporal_contradictions,
            query_type_hint: Some(profile.retrieval_query_type.clone()),
            query_mode_hint: Some(profile.graphrag_query_mode_hint.clone()),
            rerank_hint: request
                .rerank_hint
                .clone()
                .or_else(|| Some(format!("compiled-context-temporal-{}", profile.task_profile))),
        };
        let temporal = self.temporal_query(temporal_query).await?;

        Ok(compiled_context_from_runtime(
            &request,
            &profile,
            &reranked,
            &graphrag,
            &temporal,
        ))
    }

    pub async fn evaluate_compiler_policies(
        &self,
        request: CompilerEvalRequest,
    ) -> Result<CompilerEvalReport> {
        let generated_at = Utc::now().to_rfc3339();
        let stability_runs = request.top_k_stability_runs.clamp(1, 3);
        let mut comparisons = Vec::new();

        for case in request.cases.into_iter() {
            let variants = compiler_policy_variants(&case.task_profile).with_context(|| {
                format!("unsupported compiler eval task profile {}", case.task_profile)
            })?;
            let mut variant_reports = Vec::new();

            for variant in variants.into_iter() {
                let request = compiler_eval_request_with_task_profile(&case, &variant.task_profile);
                let started_at = Instant::now();
                let compiled = self
                    .compile_context_with_profile(request.clone(), variant.clone())
                    .await?;
                let latency_ms = started_at.elapsed().as_millis() as u64;
                let baseline_ids = compiled.top_memory_ids.clone();
                let mut stable = true;

                for _ in 1..stability_runs {
                    let rerun = self
                        .compile_context_with_profile(request.clone(), variant.clone())
                        .await?;
                    if rerun.top_memory_ids != baseline_ids {
                        stable = false;
                        break;
                    }
                }

                let truth_view_appropriate = normalize_truth_view(&case.preferred_truth_view)
                    == compiled.temporal_truth_view;
                let graphrag_mode_appropriate = normalize_graphrag_query_mode_hint(
                    &case.preferred_graphrag_mode,
                ) == compiled.graphrag_query_mode;
                let expected_query_type = case
                    .expected_retrieval_query_type
                    .clone()
                    .unwrap_or_else(|| expected_query_type_for_task_profile(&case.task_profile));
                let route_appropriate = compiled
                    .retrieval_query_type
                    .eq_ignore_ascii_case(&expected_query_type);
                let relevance_proxy_score =
                    compiled_context_relevance_proxy(&compiled, &case.expected_memory_ids);
                let task_fit_score = compiled_context_task_fit_score(
                    &compiled,
                    &case,
                    truth_view_appropriate,
                    graphrag_mode_appropriate,
                    route_appropriate,
                );
                let context_usefulness_score =
                    compiled_context_usefulness_score(&compiled, relevance_proxy_score, stable);
                let budget_efficiency_score =
                    compiled_context_budget_efficiency_score(&compiled, &variant);
                let overall_score = compiled_context_overall_score(
                    relevance_proxy_score,
                    task_fit_score,
                    context_usefulness_score,
                    budget_efficiency_score,
                );

                variant_reports.push(CompilerPolicyVariantReport {
                    variant_id: variant.profile_id.clone(),
                    budget_profile_id: variant.profile_id.clone(),
                    task_profile: variant.task_profile.clone(),
                    retrieval_query_type: compiled.retrieval_query_type.clone(),
                    dense_backend: compiled.dense_backend.clone(),
                    sparse_backend: compiled.sparse_backend.clone(),
                    graphrag_query_mode: compiled.graphrag_query_mode.clone(),
                    temporal_truth_view: compiled.temporal_truth_view.clone(),
                    selected_memory_tiers: compiled.selected_memory_tiers.clone(),
                    top_memory_ids: compiled.top_memory_ids.clone(),
                    relevance_proxy_score,
                    task_fit_score,
                    context_usefulness_score,
                    budget_efficiency_score,
                    top_k_stable: stable,
                    truth_view_appropriate,
                    graphrag_mode_appropriate,
                    route_appropriate,
                    overall_score,
                    latency_ms,
                    note: compiler_eval_variant_note(
                        &case,
                        &compiled,
                        truth_view_appropriate,
                        graphrag_mode_appropriate,
                        route_appropriate,
                    ),
                });
            }

            variant_reports.sort_by(|left, right| {
                right
                    .overall_score
                    .partial_cmp(&left.overall_score)
                    .unwrap_or(std::cmp::Ordering::Equal)
            });
            let winner = variant_reports
                .first()
                .cloned()
                .context("compiler eval produced no variants")?;

            comparisons.push(CompilerTaskComparison {
                case_id: case.case_id.clone(),
                task_profile: case.task_profile.clone(),
                description: case.description.clone(),
                selected_variant_id: winner.variant_id.clone(),
                selected_budget_profile_id: winner.budget_profile_id.clone(),
                recommendation: compiler_eval_recommendation_for(&case.task_profile, &winner),
                variants: variant_reports,
                note: format!(
                    "B23.6 compared bounded compiler variants for {} and selected {} from evidence instead of preserving a hand-authored policy by default.",
                    case.task_profile, winner.variant_id
                ),
            });
        }

        Ok(CompilerEvalReport {
            report_version: COMPILER_EVAL_REPORT_VERSION.to_string(),
            compiler_id: memory_compiler_contract().compiler_id,
            generated_at,
            comparisons,
            note: "B23.6 evaluates bounded compiler policy variants over the live Beagle memory compiler so context policy can be evidence-backed instead of hand-authored only.".to_string(),
        })
    }

    pub fn derive_compiler_policy(&self, report: &CompilerEvalReport) -> CompilerPolicy {
        let profiles = report
            .comparisons
            .iter()
            .filter_map(|comparison| {
                let winner = comparison
                    .variants
                    .iter()
                    .find(|variant| variant.variant_id == comparison.selected_variant_id)?;
                Some(CompilerPolicyProfile {
                    task_profile: comparison.task_profile.clone(),
                    budget_profile_id: winner.budget_profile_id.clone(),
                    retrieval_query_type: winner.retrieval_query_type.clone(),
                    graphrag_query_mode: winner.graphrag_query_mode.clone(),
                    temporal_truth_view: winner.temporal_truth_view.clone(),
                    selected_memory_tiers: winner.selected_memory_tiers.clone(),
                    current_state: "evidence-backed-live".to_string(),
                    evidence_basis: vec![
                        format!("selected_variant_id={}", winner.variant_id),
                        format!("overall_score={:.3}", winner.overall_score),
                        format!("relevance_proxy_score={:.3}", winner.relevance_proxy_score),
                        format!("task_fit_score={:.3}", winner.task_fit_score),
                        format!(
                            "context_usefulness_score={:.3}",
                            winner.context_usefulness_score
                        ),
                        format!(
                            "budget_efficiency_score={:.3}",
                            winner.budget_efficiency_score
                        ),
                        format!("truth_view_appropriate={}", winner.truth_view_appropriate),
                        format!(
                            "graphrag_mode_appropriate={}",
                            winner.graphrag_mode_appropriate
                        ),
                        format!("route_appropriate={}", winner.route_appropriate),
                    ],
                    last_eval_at: report.generated_at.clone(),
                    recommended_when: compiler_policy_recommended_when(
                        &comparison.task_profile,
                        winner,
                    ),
                    note: format!(
                        "B23.6 compiler policy for {} is now evidence-backed by bounded context-quality evals.",
                        comparison.task_profile
                    ),
                })
            })
            .collect::<Vec<_>>();

        CompilerPolicy {
            policy_version: COMPILER_POLICY_VERSION.to_string(),
            policy_id: "b236-evidence-backed-compiler-policy".to_string(),
            generated_at: report.generated_at.clone(),
            profiles,
            note: "B23.6 derives compiler policy from bounded live evals across implementation, analysis, and manuscript context compilation variants.".to_string(),
        }
    }

    pub async fn temporal_query(
        &self,
        query: TemporalQuery,
    ) -> Result<TemporalQueryResult> {
        let truth_view = normalize_truth_view(&query.truth_view).to_string();
        let routed_query = RoutedRetrievalQuery {
            query_version: crate::retrieval::ROUTED_RETRIEVAL_QUERY_VERSION.to_string(),
            query_text: query.query_text.clone(),
            top_k: query.top_k.clamp(1, 8).max(2),
            dense_enabled: query.dense_enabled,
            sparse_enabled: query.sparse_enabled,
            dense_weight: query.dense_weight,
            sparse_weight: query.sparse_weight,
            filters: query.filters.clone(),
            query_type_hint: query.query_type_hint.clone(),
            compare_against_general: false,
            rerank_hint: query
                .rerank_hint
                .clone()
                .or_else(|| Some(format!("temporal-query-{}", truth_view))),
        };
        let reranked = self.reranked_routed_retrieve(routed_query).await?;
        let records = self.local_index.records_snapshot().await;

        Ok(temporal_query_from_runtime(
            &query,
            &truth_view,
            &self.retrieval_collection(),
            &reranked,
            &records,
        ))
    }

    pub async fn graph_rag_query(&self, query: GraphRagQuery) -> Result<GraphRagResult> {
        let query_mode = self.graph_rag_query_mode(&query);
        let effective_query = apply_graphrag_query_mode(&query, &query_mode);
        let routed_query = RoutedRetrievalQuery {
            query_version: crate::retrieval::ROUTED_RETRIEVAL_QUERY_VERSION.to_string(),
            query_text: effective_query.query_text.clone(),
            top_k: effective_query.top_k,
            dense_enabled: effective_query.dense_enabled,
            sparse_enabled: effective_query.sparse_enabled,
            dense_weight: effective_query.dense_weight,
            sparse_weight: effective_query.sparse_weight,
            filters: effective_query.filters.clone(),
            query_type_hint: effective_query.query_type_hint.clone(),
            compare_against_general: false,
            rerank_hint: effective_query.rerank_hint.clone(),
        };
        let reranked = self.reranked_routed_retrieve(routed_query).await?;
        Ok(self.graph_rag_from_reranked_result(
            &effective_query,
            &reranked,
            &query_mode,
        ))
    }

    pub fn graph_rag_from_reranked_result(
        &self,
        query: &GraphRagQuery,
        reranked: &RerankedResult,
        query_mode: &GraphRagQueryModeDecision,
    ) -> GraphRagResult {
        let collection = self.retrieval_collection();
        let program_id = query
            .program_id
            .clone()
            .or_else(|| first_non_empty(reranked.hits.iter().filter_map(|hit| hit.point.payload.program_id.clone())));
        let campaign_id = query
            .filters
            .campaign_id
            .clone()
            .or_else(|| first_non_empty(reranked.hits.iter().filter_map(|hit| hit.point.payload.campaign_id.clone())));
        let workstream_id = query
            .filters
            .workstream_id
            .clone()
            .or_else(|| first_non_empty(reranked.hits.iter().filter_map(|hit| hit.point.payload.workstream_id.clone())));
        let session_id = query
            .filters
            .session_id
            .clone()
            .or_else(|| first_non_empty(reranked.hits.iter().filter_map(|hit| hit.point.payload.session_id.clone())));
        let (root_entity_type, root_entity_id) =
            resolve_graph_root_entity(query, program_id.as_deref(), campaign_id.as_deref(), workstream_id.as_deref(), session_id.as_deref());

        let memory_hierarchy = if query.include_memory_hierarchy {
            Some(memory_hierarchy_from_records(
                &collection.collection_name,
                &reranked
                    .hits
                    .iter()
                    .map(|hit| hit.point.payload.clone())
                    .collect::<Vec<_>>(),
            ))
        } else {
            None
        };

        let mut node_map = std::collections::BTreeMap::<String, GraphRagNode>::new();
        let mut edge_map = std::collections::BTreeMap::<String, GraphRagEdge>::new();
        let mut support_memory_ids = Vec::new();

        if let (Some(node_type), Some(node_id)) = (root_entity_type.as_deref(), root_entity_id.as_deref()) {
            upsert_graph_node(
                &mut node_map,
                graph_node_key(node_type, node_id),
                canonical_graph_node_type(node_type).to_string(),
                node_id.to_string(),
                None,
                serde_json::json!({
                    "root": true,
                    "entity_id": node_id,
                    "max_hops": query.max_hops
                }),
            );
        }

        let program_node_id = program_id.as_ref().map(|value| {
            let key = graph_node_key("program", value);
            upsert_graph_node(
                &mut node_map,
                key.clone(),
                "Program".to_string(),
                value.clone(),
                None,
                serde_json::json!({ "program_id": value }),
            );
            key
        });
        let campaign_node_id = campaign_id.as_ref().map(|value| {
            let key = graph_node_key("campaign", value);
            upsert_graph_node(
                &mut node_map,
                key.clone(),
                "Campaign".to_string(),
                value.clone(),
                None,
                serde_json::json!({ "campaign_id": value }),
            );
            key
        });
        let workstream_node_id = workstream_id.as_ref().map(|value| {
            let key = graph_node_key("workstream", value);
            upsert_graph_node(
                &mut node_map,
                key.clone(),
                "Workstream".to_string(),
                value.clone(),
                None,
                serde_json::json!({ "workstream_id": value }),
            );
            key
        });
        let session_node_id = session_id.as_ref().map(|value| {
            let key = graph_node_key("session", value);
            upsert_graph_node(
                &mut node_map,
                key.clone(),
                "Session".to_string(),
                value.clone(),
                None,
                serde_json::json!({ "session_id": value }),
            );
            key
        });

        if let (Some(program_node_id), Some(campaign_node_id)) =
            (program_node_id.as_ref(), campaign_node_id.as_ref())
        {
            upsert_graph_edge(
                &mut edge_map,
                program_node_id.clone(),
                campaign_node_id.clone(),
                "contains".to_string(),
                None,
                serde_json::json!({ "source": "b231-graphrag-pilot" }),
            );
        }
        if let (Some(campaign_node_id), Some(workstream_node_id)) =
            (campaign_node_id.as_ref(), workstream_node_id.as_ref())
        {
            upsert_graph_edge(
                &mut edge_map,
                campaign_node_id.clone(),
                workstream_node_id.clone(),
                "uses".to_string(),
                None,
                serde_json::json!({ "source": "b231-graphrag-pilot" }),
            );
        }
        if let (Some(session_node_id), Some(workstream_node_id)) =
            (session_node_id.as_ref(), workstream_node_id.as_ref())
        {
            upsert_graph_edge(
                &mut edge_map,
                session_node_id.clone(),
                workstream_node_id.clone(),
                "belongs_to".to_string(),
                None,
                serde_json::json!({ "source": "b231-graphrag-pilot" }),
            );
        }

        let manuscript_node_id = campaign_id.as_ref().map(|value| {
            let key = graph_node_key("manuscript", value);
            upsert_graph_node(
                &mut node_map,
                key.clone(),
                "Manuscript".to_string(),
                format!("campaign manuscript {}", value),
                None,
                serde_json::json!({
                    "campaign_id": value,
                    "manuscript_id": format!("manuscript:{}", value)
                }),
            );
            key
        });

        for hit in &reranked.hits {
            let record = &hit.point.payload;
            support_memory_ids.push(record.memory_id.clone());

            if let Some(program_id) = record.program_id.as_deref() {
                let key = graph_node_key("program", program_id);
                upsert_graph_node(
                    &mut node_map,
                    key,
                    "Program".to_string(),
                    program_id.to_string(),
                    Some(record.memory_id.clone()),
                    serde_json::json!({ "program_id": program_id }),
                );
            }
            if let Some(campaign_id) = record.campaign_id.as_deref() {
                let key = graph_node_key("campaign", campaign_id);
                upsert_graph_node(
                    &mut node_map,
                    key,
                    "Campaign".to_string(),
                    campaign_id.to_string(),
                    Some(record.memory_id.clone()),
                    serde_json::json!({ "campaign_id": campaign_id }),
                );
            }
            if let Some(workstream_id) = record.workstream_id.as_deref() {
                let key = graph_node_key("workstream", workstream_id);
                upsert_graph_node(
                    &mut node_map,
                    key,
                    "Workstream".to_string(),
                    workstream_id.to_string(),
                    Some(record.memory_id.clone()),
                    serde_json::json!({ "workstream_id": workstream_id }),
                );
            }
            if let Some(session_id) = record.session_id.as_deref() {
                let key = graph_node_key("session", session_id);
                upsert_graph_node(
                    &mut node_map,
                    key,
                    "Session".to_string(),
                    session_id.to_string(),
                    Some(record.memory_id.clone()),
                    serde_json::json!({ "session_id": session_id }),
                );
            }

            let experiment_node_ids = record
                .result_refs
                .iter()
                .filter_map(|result_ref| derive_experiment_id_from_result_ref(result_ref))
                .map(|experiment_id| {
                    let key = graph_node_key("experiment", &experiment_id);
                    upsert_graph_node(
                        &mut node_map,
                        key.clone(),
                        "Experiment".to_string(),
                        experiment_id.clone(),
                        Some(record.memory_id.clone()),
                        serde_json::json!({ "experiment_id": experiment_id }),
                    );
                    key
                })
                .collect::<Vec<_>>();

            for experiment_node_id in &experiment_node_ids {
                if let Some(workstream_node_id) = workstream_node_id.as_ref() {
                    upsert_graph_edge(
                        &mut edge_map,
                        workstream_node_id.clone(),
                        experiment_node_id.clone(),
                        "runs".to_string(),
                        Some(record.memory_id.clone()),
                        serde_json::json!({ "source_memory_id": record.memory_id }),
                    );
                }
            }

            let mut result_node_ids = Vec::new();
            for result_ref in &record.result_refs {
                let key = graph_node_key("result", result_ref);
                upsert_graph_node(
                    &mut node_map,
                    key.clone(),
                    "Result".to_string(),
                    result_ref.clone(),
                    Some(record.memory_id.clone()),
                    serde_json::json!({ "result_ref": result_ref }),
                );
                for experiment_node_id in &experiment_node_ids {
                    upsert_graph_edge(
                        &mut edge_map,
                        experiment_node_id.clone(),
                        key.clone(),
                        "yields".to_string(),
                        Some(record.memory_id.clone()),
                        serde_json::json!({ "source_memory_id": record.memory_id }),
                    );
                }
                result_node_ids.push(key);
            }

            for claim_ref in &record.claim_refs {
                let claim_node_id = graph_node_key("claim", claim_ref);
                upsert_graph_node(
                    &mut node_map,
                    claim_node_id.clone(),
                    "Claim".to_string(),
                    claim_ref.clone(),
                    Some(record.memory_id.clone()),
                    serde_json::json!({ "claim_ref": claim_ref }),
                );
                for result_node_id in &result_node_ids {
                    upsert_graph_edge(
                        &mut edge_map,
                        result_node_id.clone(),
                        claim_node_id.clone(),
                        "supports".to_string(),
                        Some(record.memory_id.clone()),
                        serde_json::json!({ "source_memory_id": record.memory_id }),
                    );
                }
                if let Some(manuscript_node_id) = manuscript_node_id.as_ref() {
                    upsert_graph_edge(
                        &mut edge_map,
                        claim_node_id.clone(),
                        manuscript_node_id.clone(),
                        "appears_in".to_string(),
                        Some(record.memory_id.clone()),
                        serde_json::json!({ "source_memory_id": record.memory_id }),
                    );
                }
            }
        }

        let support_memory_ids = unique_strings(support_memory_ids, usize::MAX);
        let nodes = node_map.into_values().collect::<Vec<_>>();
        let edges = edge_map.into_values().collect::<Vec<_>>();
        let promotion_policy = self.memory_promotion_policy();
        let retention_policy = self.memory_retention_policy();
        let promoted_memories = derive_promoted_memories(&reranked.hits);

        GraphRagResult {
            result_version: GRAPHRAG_RESULT_VERSION.to_string(),
            query_type: reranked.query_type.clone(),
            query_mode: query_mode.query_mode.clone(),
            query_mode_source: query_mode.classifier_source.clone(),
            query_mode_reason: query_mode.classifier_reason.clone(),
            collection_name: reranked.collection_name.clone(),
            retrieval_mode: format!("{}+graphrag-pilot", reranked.postrank_retrieval_mode),
            routing_decision: reranked.routing_decision.clone(),
            dense_backend: reranked.dense_backend.clone(),
            sparse_backend: reranked.sparse_backend.clone(),
            reranker_backend: reranked.reranker_backend.clone(),
            reranking_applied: reranked.reranking_applied,
            applied_filters: query.filters.clone(),
            promotion_policy_id: promotion_policy.policy_id,
            retention_policy_id: retention_policy.policy_id,
            root_entity_type,
            root_entity_id,
            program_id,
            campaign_id,
            workstream_id,
            session_id,
            support_memory_ids,
            node_count: nodes.len(),
            edge_count: edges.len(),
            nodes,
            edges,
            promoted_memories,
            memory_hierarchy,
            note: "B23.2 keeps the bounded GraphRAG pilot from B23.1, but now adds explicit query-mode routing plus promotion/retention policy hooks over the same canonical Beagle memory spine.".to_string(),
        }
    }

    async fn rerank_hits_for_lane(
        &self,
        q: &RoutedRetrievalQuery,
        prerank: &RoutedRetrievalResult,
    ) -> Result<Option<(String, String, String, Vec<RerankedHit>)>> {
        if prerank.hits.is_empty() {
            return Ok(Some((
                "rerank-empty".to_string(),
                "empty".to_string(),
                "pilot-active".to_string(),
                Vec::new(),
            )));
        }

        let (backend_id, reranker_kind, runtime_state, client) =
            match prerank.routing_decision.selected_route.as_str() {
                "sovereign" => (
                    self.active_sovereign_reranker_backend_id(),
                    "cross-encoder-self-hosted".to_string(),
                    self.reranking_runtime.sovereign_runtime_state().to_string(),
                    self.sovereign_reranker.as_ref(),
                ),
                "general" => (
                    self.active_general_reranker_backend_id(),
                    "cross-encoder-api".to_string(),
                    self.reranking_runtime.general_runtime_state().to_string(),
                    self.general_reranker.as_ref(),
                ),
                _ => return Ok(None),
            };

        if runtime_state != "pilot-active" {
            return Ok(None);
        }

        let client = client.context("reranker client missing despite active runtime state")?;
        let documents = prerank
            .hits
            .iter()
            .map(rerank_document_text)
            .collect::<Vec<_>>();
        let scores = client
            .rerank(&q.query_text, &documents, prerank.hits.len())
            .await?;
        let reranked_hits = apply_rerank_scores_to_hits(&prerank.hits, &scores);

        Ok(Some((backend_id, reranker_kind, runtime_state, reranked_hits)))
    }

    /// Ingest a chat session into memory
    pub async fn ingest_chat(&self, session: ChatSession) -> Result<IngestStats> {
        info!(
            source = %session.source,
            session_id = %session.session_id,
            turns = session.turns.len(),
            "Ingesting chat session"
        );

        // Convert ChatSession to ConversationSession + ConversationTurns
        let session_uuid = Uuid::parse_str(&session.session_id).unwrap_or_else(|_| Uuid::new_v4());

        if let Some(bridge) = &self.bridge {
            bridge
                .create_session(None)
                .await
                .context("Failed to create conversation session")?;
        }

        let physio_snapshot = metadata_physio(&session.metadata);
        let experiment_flags = metadata_experiment_flags(&session.metadata);
        let domain_label = metadata_string(&session.metadata, "domain");
        let workstream_id = metadata_string(&session.metadata, "workstream_id");
        let campaign_id = metadata_string(&session.metadata, "campaign_id");
        let program_id = metadata_string(&session.metadata, "program_id");
        let workspace_id = metadata_string(&session.metadata, "workspace_id");
        let beagle_session_id = metadata_string(&session.metadata, "session_id");
        let physio_snapshot_ref = metadata_string(&session.metadata, "physio_snapshot_ref");
        let result_refs = metadata_string_list(&session.metadata, "result_refs");
        let claim_refs = metadata_string_list(&session.metadata, "claim_refs");
        let repo_path = metadata_string(&session.metadata, "repo_path");
        let file_type = metadata_string(&session.metadata, "file_type");
        let provider = metadata_string(&session.metadata, "provider");
        let model_override = metadata_string(&session.metadata, "model");
        let mut num_chunks = 0;
        let mut last_memory_id = None;

        // Ingest each turn
        for (idx, turn) in session.turns.iter().enumerate() {
            let timestamp = turn.timestamp.unwrap_or_else(Utc::now);
            let turn_index = turn.turn_index.unwrap_or(idx);
            let memory_id = stable_memory_id(&session.source, &session.session_id, turn_index, &turn.role);
            let role = canonical_role(&turn.role);
            let text = turn.content.trim().to_string();
            if text.is_empty() {
                warn!(turn_index, "Skipping empty chat turn during ingest");
                continue;
            }
            let domain = domain_from_label(domain_label.as_deref());
            let model = turn
                .model
                .clone()
                .or_else(|| model_override.clone())
                .unwrap_or_else(|| "unknown".to_string());

            let record = MemoryRecord {
                memory_id: memory_id.clone(),
                source: session.source.clone(),
                conversation_id: session.session_id.clone(),
                workstream_id: workstream_id.clone(),
                campaign_id: campaign_id.clone(),
                program_id: program_id.clone(),
                workspace_id: workspace_id.clone(),
                session_id: beagle_session_id.clone(),
                turn_index,
                role: role.clone(),
                text: text.clone(),
                tags: session.tags.clone(),
                domain: domain_label.clone(),
                repo_path: repo_path.clone(),
                file_type: file_type.clone(),
                timestamp,
                physio_snapshot: physio_snapshot.clone(),
                experiment_flags: experiment_flags.clone(),
                physio_snapshot_ref: physio_snapshot_ref.clone(),
                result_refs: result_refs.clone(),
                claim_refs: claim_refs.clone(),
                provider: provider.clone(),
                model: Some(model.clone()),
                score: None,
            };

            // Convert ChatTurn to ConversationTurn
            let mut conv_turn = ConversationTurn::new(
                session_uuid,
                if role == "user" { text.clone() } else { String::new() },
                if role == "assistant" || role == "system" || role == "tool" {
                    text.clone()
                } else {
                    String::new()
                },
                domain,
                model,
            );
            conv_turn.timestamp = timestamp;
            conv_turn.metadata.tags = session.tags.clone();
            conv_turn.metadata.source = Some(session.source.clone());
            conv_turn.metadata.conversation_id = Some(session.session_id.clone());
            conv_turn.metadata.turn_index = Some(turn_index);
            conv_turn.metadata.role = Some(role.clone());
            conv_turn.metadata.domain_label = domain_label.clone();
            conv_turn.metadata.physio_snapshot = physio_snapshot.clone();
            conv_turn.metadata.experiment_flags = experiment_flags.clone();

            let mut stored = false;
            if let Some(bridge) = &self.bridge {
                match bridge.store_turn(conv_turn).await {
                    Ok(_) => {
                        stored = true;
                    }
                    Err(e) => {
                        warn!(
                            turn_index = idx,
                            error = %e,
                            "Failed to store turn in hypergraph bridge"
                        );
                    }
                }
            }

            match self.local_index.upsert_record(&record).await {
                Ok(()) => {
                    stored = true;
                }
                Err(error) => {
                    warn!(
                        turn_index = idx,
                        %error,
                        "Failed to persist local memory record"
                    );
                }
            }

            if let Some(index) = &self.index {
                if let Err(error) = index.upsert_record(&record).await {
                    warn!(
                        memory_id = %record.memory_id,
                        %error,
                        "Failed to index memory record in Qdrant; keeping local memory path active"
                    );
                }
            }

            if stored {
                num_chunks += 1;
                last_memory_id = Some(memory_id);
            }
        }

        Ok(IngestStats {
            num_turns: session.turns.len(),
            num_chunks,
            session_id: session.session_id,
            stored: num_chunks > 0,
            memory_id: last_memory_id,
            searchable: num_chunks > 0,
            physio_attached: physio_snapshot.is_some(),
            experiment_flags_attached: experiment_flags.is_some(),
        })
    }

    pub async fn hybrid_retrieve(&self, q: RetrievalQuery) -> Result<RetrievalResult> {
        let collection = self.retrieval_collection();
        let top_k = q.top_k.clamp(1, 10);
        let dense_limit = top_k.saturating_mul(4).max(top_k);
        let sparse_limit = top_k.saturating_mul(4).max(top_k);

        let dense_records = if q.dense_enabled {
            if let Some(index) = &self.index {
                match index
                    .search_records_filtered(&q.query_text, &q.filters, dense_limit)
                    .await
                {
                    Ok(records) => records,
                    Err(error) => {
                        warn!(%error, "Dense retrieval failed; falling back to local dense path");
                        if let Some(local_dense_index) = &self.local_dense_index {
                            match local_dense_index
                                .search_records_filtered(
                                    &self.local_index,
                                    &q.query_text,
                                    &q.filters,
                                    dense_limit,
                                )
                                .await
                            {
                                Ok(records) => records,
                                Err(local_error) => {
                                    warn!(
                                        %local_error,
                                        "Promoted local dense path failed; falling back to lexical dense proxy"
                                    );
                                    self.local_index
                                        .search_records_filtered(&q.query_text, &q.filters, dense_limit)
                                        .await?
                                }
                            }
                        } else {
                            self.local_index
                                .search_records_filtered(&q.query_text, &q.filters, dense_limit)
                                .await?
                        }
                    }
                }
            } else if let Some(local_dense_index) = &self.local_dense_index {
                match local_dense_index
                    .search_records_filtered(&self.local_index, &q.query_text, &q.filters, dense_limit)
                    .await
                {
                    Ok(records) => records,
                    Err(error) => {
                        warn!(
                            %error,
                            "Promoted local dense path failed; falling back to lexical dense proxy"
                        );
                        self.local_index
                            .search_records_filtered(&q.query_text, &q.filters, dense_limit)
                            .await?
                    }
                }
            } else {
                self.local_index
                    .search_records_filtered(&q.query_text, &q.filters, dense_limit)
                    .await?
            }
        } else {
            Vec::new()
        };

        let sparse_records = if q.sparse_enabled {
            self.local_index
                .search_records_filtered(&q.query_text, &q.filters, sparse_limit)
                .await?
        } else {
            Vec::new()
        };

        let hits = hybrid_merge_records(
            &collection.collection_name,
            collection.dense_vector_name.clone(),
            dense_records,
            sparse_records,
            top_k,
            q.dense_weight,
            q.sparse_weight,
        );
        let dense_hit_count = hits.iter().filter(|hit| hit.dense_score.is_some()).count();
        let sparse_hit_count = hits.iter().filter(|hit| hit.sparse_score.is_some()).count();

        Ok(RetrievalResult {
            result_version: RETRIEVAL_RESULT_VERSION.to_string(),
            retrieval_mode: "dense+sparse-hybrid".to_string(),
            collection_name: collection.collection_name,
            dense_backend: collection.dense_backend,
            sparse_backend: collection.sparse_backend,
            top_k,
            applied_filters: q.filters,
            dense_hit_count,
            sparse_hit_count,
            hits,
            note: "Hybrid retrieval fuses dense and sparse signals with payload-aware filtering over canonical memory points.".to_string(),
        })
    }

    pub async fn code_retrieve(&self, q: CodeRetrievalQuery) -> Result<CodeRetrievalResult> {
        let collection = self.retrieval_collection();
        let backend_profile = self.code_retrieval_backend_profile();
        let top_k = q.top_k.clamp(1, 10);
        let dense_limit = top_k.saturating_mul(4).max(top_k);
        let sparse_limit = top_k.saturating_mul(4).max(top_k);

        let dense_records = if q.dense_enabled {
            if let Some(code_dense_index) = &self.code_dense_index {
                code_dense_index
                    .search_records_filtered(&self.local_index, &q.query_text, &q.filters, dense_limit)
                    .await?
            } else {
                self.local_index
                    .search_records_filtered(&q.query_text, &q.filters, dense_limit)
                    .await?
            }
        } else {
            Vec::new()
        };

        let sparse_records = if q.sparse_enabled {
            self.local_index
                .search_records_filtered(&q.query_text, &q.filters, sparse_limit)
                .await?
        } else {
            Vec::new()
        };

        let hits = hybrid_merge_records(
            &collection.collection_name,
            collection.dense_vector_name.clone(),
            dense_records,
            sparse_records,
            top_k,
            q.dense_weight,
            q.sparse_weight,
        );
        let dense_hit_count = hits.iter().filter(|hit| hit.dense_score.is_some()).count();
        let sparse_hit_count = hits.iter().filter(|hit| hit.sparse_score.is_some()).count();

        let comparison = if q.compare_against_general {
            let general = self
                .hybrid_retrieve(RetrievalQuery {
                    query_version: crate::retrieval::RETRIEVAL_QUERY_VERSION.to_string(),
                    query_text: q.query_text.clone(),
                    top_k,
                    dense_enabled: q.dense_enabled,
                    sparse_enabled: q.sparse_enabled,
                    dense_weight: q.dense_weight,
                    sparse_weight: q.sparse_weight,
                    filters: q.filters.clone(),
                    rerank_hint: q.rerank_hint.clone(),
                })
                .await?;
            let general_top_memory_ids = general
                .hits
                .iter()
                .map(|hit| hit.point.payload.memory_id.clone())
                .collect::<Vec<_>>();
            let code_top_memory_ids = hits
                .iter()
                .map(|hit| hit.point.payload.memory_id.clone())
                .collect::<Vec<_>>();
            let code_top_memory_id_set = code_top_memory_ids
                .iter()
                .cloned()
                .collect::<HashSet<_>>();
            Some(CodeRetrievalComparison {
                general_dense_backend: general.dense_backend,
                code_dense_backend: backend_profile.backend_id.clone(),
                overlap_memory_ids: general_top_memory_ids
                    .iter()
                    .filter(|memory_id| code_top_memory_id_set.contains(memory_id.as_str()))
                    .cloned()
                    .collect(),
                top_hit_changed: general_top_memory_ids.first() != code_top_memory_ids.first(),
                general_top_memory_ids,
                code_top_memory_ids,
                note: "B22.5 compares the canonical general dense lane against the bounded voyage-code-3 pilot over the same payload model.".to_string(),
            })
        } else {
            None
        };

        Ok(CodeRetrievalResult {
            result_version: CODE_RETRIEVAL_RESULT_VERSION.to_string(),
            retrieval_mode: "code-dense+sparse-hybrid".to_string(),
            collection_name: collection.collection_name,
            code_dense_backend: backend_profile.backend_id.clone(),
            general_dense_backend: self.active_dense_backend_id(),
            sparse_backend: collection.sparse_backend,
            top_k,
            applied_filters: q.filters,
            dense_hit_count,
            sparse_hit_count,
            hits,
            backend_profile,
            comparison,
            note: "B22.5 keeps the canonical retrieval collection and payload model intact while piloting voyage-code-3 for repo-native code/config/script retrieval.".to_string(),
        })
    }

    pub async fn sovereign_retrieve(
        &self,
        q: SovereignRetrievalQuery,
    ) -> Result<SovereignRetrievalResult> {
        let collection = self.retrieval_collection();
        let backend_profile = self.sovereign_retrieval_backend_profile();
        let top_k = q.top_k.clamp(1, 10);
        let dense_limit = top_k.saturating_mul(4).max(top_k);
        let sparse_limit = top_k.saturating_mul(4).max(top_k);

        let dense_records = if q.dense_enabled {
            if let Some(sovereign_dense_index) = &self.sovereign_dense_index {
                match sovereign_dense_index
                    .search_records_filtered(&self.local_index, &q.query_text, &q.filters, dense_limit)
                    .await
                {
                    Ok(records) => records,
                    Err(error) => {
                        warn!(
                            %error,
                            "Sovereign dense path failed; falling back to lexical dense proxy"
                        );
                        self.local_index
                            .search_records_filtered(&q.query_text, &q.filters, dense_limit)
                            .await?
                    }
                }
            } else {
                self.local_index
                    .search_records_filtered(&q.query_text, &q.filters, dense_limit)
                    .await?
            }
        } else {
            Vec::new()
        };

        let sparse_records = if q.sparse_enabled {
            self.local_index
                .search_records_filtered(&q.query_text, &q.filters, sparse_limit)
                .await?
        } else {
            Vec::new()
        };

        let hits = hybrid_merge_records(
            &collection.collection_name,
            collection.dense_vector_name.clone(),
            dense_records,
            sparse_records,
            top_k,
            q.dense_weight,
            q.sparse_weight,
        );
        let dense_hit_count = hits.iter().filter(|hit| hit.dense_score.is_some()).count();
        let sparse_hit_count = hits.iter().filter(|hit| hit.sparse_score.is_some()).count();

        let comparison = if q.compare_against_general {
            let general = self
                .hybrid_retrieve(RetrievalQuery {
                    query_version: crate::retrieval::RETRIEVAL_QUERY_VERSION.to_string(),
                    query_text: q.query_text.clone(),
                    top_k,
                    dense_enabled: q.dense_enabled,
                    sparse_enabled: q.sparse_enabled,
                    dense_weight: q.dense_weight,
                    sparse_weight: q.sparse_weight,
                    filters: q.filters.clone(),
                    rerank_hint: q.rerank_hint.clone(),
                })
                .await?;
            let general_top_memory_ids = general
                .hits
                .iter()
                .map(|hit| hit.point.payload.memory_id.clone())
                .collect::<Vec<_>>();
            let sovereign_top_memory_ids = hits
                .iter()
                .map(|hit| hit.point.payload.memory_id.clone())
                .collect::<Vec<_>>();
            let sovereign_top_memory_id_set = sovereign_top_memory_ids
                .iter()
                .cloned()
                .collect::<HashSet<_>>();
            Some(SovereignRetrievalComparison {
                general_dense_backend: general.dense_backend,
                sovereign_dense_backend: backend_profile.backend_id.clone(),
                overlap_memory_ids: general_top_memory_ids
                    .iter()
                    .filter(|memory_id| sovereign_top_memory_id_set.contains(memory_id.as_str()))
                    .cloned()
                    .collect(),
                top_hit_changed: general_top_memory_ids.first() != sovereign_top_memory_ids.first(),
                general_top_memory_ids,
                sovereign_top_memory_ids,
                note: "B22.6 compares the canonical voyage-4-large lane against the bounded self-hosted BGE-M3 sovereign track over the same payload model.".to_string(),
            })
        } else {
            None
        };

        Ok(SovereignRetrievalResult {
            result_version: SOVEREIGN_RETRIEVAL_RESULT_VERSION.to_string(),
            retrieval_mode: "sovereign-dense+sparse-hybrid".to_string(),
            collection_name: collection.collection_name,
            sovereign_dense_backend: backend_profile.backend_id.clone(),
            general_dense_backend: self.active_dense_backend_id(),
            sparse_backend: collection.sparse_backend,
            top_k,
            applied_filters: q.filters,
            dense_hit_count,
            sparse_hit_count,
            hits,
            backend_profile,
            comparison,
            note: "B22.6 keeps the canonical retrieval collection and payload model intact while piloting self-hosted BGE-M3 for sovereign multilingual retrieval.".to_string(),
        })
    }

    /// Query memory with semantic search
    pub async fn query(&self, q: MemoryQuery) -> Result<MemoryResult> {
        info!(
            query_preview = %q.query.chars().take(50).collect::<String>(),
            scope = ?q.scope,
            max_items = q.max_items.unwrap_or(5),
            "Querying memory"
        );

        let max_items = q.max_items.unwrap_or(5).clamp(1, 10);
        let retrieval = self
            .hybrid_retrieve(RetrievalQuery {
                query_version: crate::retrieval::RETRIEVAL_QUERY_VERSION.to_string(),
                query_text: q.query.clone(),
                top_k: max_items,
                dense_enabled: true,
                sparse_enabled: true,
                dense_weight: 0.65,
                sparse_weight: 0.35,
                filters: RetrievalFilters {
                    domain: q.domain.clone(),
                    tags: q.tags.clone(),
                    ..RetrievalFilters::default()
                },
                rerank_hint: None,
            })
            .await?;

        let records: Vec<MemoryRecord> = retrieval
            .hits
            .iter()
            .map(|hit| {
                let mut payload = hit.point.payload.clone();
                payload.score = Some(hit.hybrid_score);
                payload
            })
            .collect();

        let highlights: Vec<MemoryResultHighlight> = if !retrieval.hits.is_empty() {
            retrieval
                .hits
                .iter()
                .map(memory_highlight_from_retrieval_hit)
                .collect()
        } else if let Some(bridge) = &self.bridge {
            let retrieved = bridge
                .retrieve_similar_context(&q.query, max_items, 0.3)
                .await
                .context("Failed to retrieve context")?;

            retrieved
                .turns
                .iter()
                .zip(retrieved.relevance_scores.iter())
                .map(|(turn, score)| {
                    let snippet = if !turn.query.is_empty() && !turn.response.is_empty() {
                        format!(
                            "Q: {}\nA: {}",
                            turn.query.chars().take(100).collect::<String>(),
                            turn.response.chars().take(200).collect::<String>()
                        )
                    } else if !turn.query.is_empty() {
                        turn.query.chars().take(200).collect::<String>()
                    } else {
                        turn.response.chars().take(200).collect::<String>()
                    };

                    MemoryResultHighlight {
                        memory_id: None,
                        source: turn
                            .metadata
                            .source
                            .clone()
                            .unwrap_or_else(|| format!("conversation_{}", turn.session_id)),
                        date: Some(turn.timestamp),
                        snippet,
                        run_id: None,
                        session_id: Some(turn.session_id.to_string()),
                        relevance: *score,
                        conversation_id: turn.metadata.conversation_id.clone(),
                        turn_index: turn.metadata.turn_index,
                        role: turn.metadata.role.clone(),
                        tags: turn.metadata.tags.clone(),
                        domain: turn.metadata.domain_label.clone(),
                        physio_snapshot: turn.metadata.physio_snapshot.clone(),
                        experiment_flags: turn.metadata.experiment_flags.clone(),
                        workstream_id: None,
                        campaign_id: None,
                        program_id: None,
                        workspace_id: None,
                        beagle_session_id: None,
                        result_refs: Vec::new(),
                        claim_refs: Vec::new(),
                    }
                })
                .collect()
        } else {
            Vec::new()
        };

        // Generate summary (simple version: join highlights)
        // TODO: Use LLM to generate better summary
        let summary = if highlights.is_empty() {
            "No relevant context found.".to_string()
        } else {
            format!(
                "Found {} relevant context items:\n{}",
                highlights.len(),
                highlights
                    .iter()
                    .take(3)
                    .map(|h| format!("- {}", h.snippet.chars().take(100).collect::<String>()))
                    .collect::<Vec<_>>()
                    .join("\n")
            )
        };

        // Create links
        let links: Vec<serde_json::Value> = highlights
            .iter()
            .filter_map(|h| {
                h.conversation_id.as_ref().or(h.session_id.as_ref()).map(|sid| {
                    serde_json::json!({
                        "type": "session",
                        "id": sid,
                        "label": format!("Session {}", sid)
                    })
                })
            })
            .collect();

        Ok(MemoryResult {
            summary,
            highlights,
            links,
            results: records,
            recent_physio: None,
        })
    }
}

struct MemoryVectorIndex {
    base_url: String,
    collection: String,
    client: reqwest::Client,
    embedding_client: EmbeddingClient,
    collection_ready: Arc<RwLock<bool>>,
}

struct LocalDenseVectorIndex {
    embedding_client: EmbeddingClient,
    cache: Arc<RwLock<HashMap<String, Vec<f64>>>>,
}

struct LocalMemoryIndex {
    path: PathBuf,
    records: Arc<RwLock<Vec<MemoryRecord>>>,
}

impl LocalMemoryIndex {
    fn new(path: PathBuf) -> Self {
        let records = load_local_records(&path);
        Self {
            path,
            records: Arc::new(RwLock::new(records)),
        }
    }

    async fn upsert_record(&self, record: &MemoryRecord) -> Result<()> {
        let mut records = self.records.write().await;
        if let Some(existing) = records
            .iter_mut()
            .find(|candidate| candidate.memory_id == record.memory_id)
        {
            *existing = record.clone();
        } else {
            records.push(record.clone());
        }
        persist_local_records(&self.path, &records)
    }

    async fn record_by_id(&self, memory_id: &str) -> Option<MemoryRecord> {
        let records = self.records.read().await;
        records
            .iter()
            .find(|record| record.memory_id == memory_id)
            .cloned()
    }

    async fn search_records(&self, query: &str, limit: usize) -> Result<Vec<MemoryRecord>> {
        self.search_records_filtered(query, &RetrievalFilters::default(), limit)
            .await
    }

    async fn search_records_filtered(
        &self,
        query: &str,
        filters: &RetrievalFilters,
        limit: usize,
    ) -> Result<Vec<MemoryRecord>> {
        let records = self.records.read().await;
        let mut ranked: Vec<MemoryRecord> = records
            .iter()
            .filter_map(|record| {
                if !record_matches_filters(record, filters) {
                    return None;
                }
                let score = lexical_score(query, record);
                if score > 0.0 {
                    let mut copy = record.clone();
                    copy.score = Some(score);
                    Some(copy)
                } else {
                    None
                }
            })
            .collect();
        ranked.sort_by(|left, right| {
            right
                .score
                .partial_cmp(&left.score)
                .unwrap_or(std::cmp::Ordering::Equal)
                .then_with(|| right.timestamp.cmp(&left.timestamp))
        });
        ranked.truncate(limit);
        Ok(ranked)
    }

    async fn records_snapshot(&self) -> Vec<MemoryRecord> {
        self.records.read().await.clone()
    }
}

impl LocalDenseVectorIndex {
    fn new(base_url: String, model: String, api_key: Option<String>) -> Self {
        Self {
            embedding_client: EmbeddingClient::new_with_options(base_url, Some(model), api_key),
            cache: Arc::new(RwLock::new(HashMap::new())),
        }
    }

    async fn search_records_filtered(
        &self,
        local_index: &LocalMemoryIndex,
        query: &str,
        filters: &RetrievalFilters,
        limit: usize,
    ) -> Result<Vec<MemoryRecord>> {
        let records = local_index.records_snapshot().await;
        let mut missing_texts = Vec::new();
        let mut missing_keys = Vec::new();

        {
            let cache = self.cache.read().await;
            if !cache.contains_key(query) {
                missing_texts.push(query.to_string());
                missing_keys.push(query.to_string());
            }
            for record in &records {
                if record_matches_filters(record, filters) && !cache.contains_key(&record.text) {
                    missing_texts.push(record.text.clone());
                    missing_keys.push(record.text.clone());
                }
            }
        }

        if !missing_texts.is_empty() {
            let missing_refs = missing_texts.iter().map(String::as_str).collect::<Vec<_>>();
            let embeddings = self.embedding_client.embed_batch(&missing_refs).await?;
            let mut cache = self.cache.write().await;
            for (key, embedding) in missing_keys.into_iter().zip(embeddings.into_iter()) {
                cache.insert(key, embedding);
            }
        }

        let query_embedding = self.embedding_for(query).await?;
        let mut ranked = Vec::new();

        for record in records.into_iter() {
            if !record_matches_filters(&record, filters) {
                continue;
            }
            let embedding = self.embedding_for(&record.text).await?;
            let score =
                EmbeddingClient::cosine_similarity(&query_embedding, &embedding).clamp(0.0, 1.0) as f32;
            if score > 0.0 {
                let mut copy = record;
                copy.score = Some(score);
                ranked.push(copy);
            }
        }

        ranked.sort_by(|left, right| {
            right
                .score
                .partial_cmp(&left.score)
                .unwrap_or(std::cmp::Ordering::Equal)
                .then_with(|| right.timestamp.cmp(&left.timestamp))
        });
        ranked.truncate(limit);
        Ok(ranked)
    }

    async fn embedding_for(&self, text: &str) -> Result<Vec<f64>> {
        {
            let cache = self.cache.read().await;
            if let Some(cached) = cache.get(text) {
                return Ok(cached.clone());
            }
        }

        let embedding = self.embedding_client.embed(text).await?;
        let mut cache = self.cache.write().await;
        cache.insert(text.to_string(), embedding.clone());
        Ok(embedding)
    }
}

enum MemoryIndexProbe {
    Up,
    CollectionMissing(u16),
    HttpError(u16, String),
}

fn truncate_health_detail(body: &str) -> String {
    let t = body.trim();
    let mut out = String::new();
    for ch in t.chars().take(256) {
        out.push(ch);
    }
    if t.chars().count() > 256 {
        out.push('…');
    }
    out
}

/// Retries for transient Qdrant network failures only (not HTTP 4xx/5xx).
const QDRANT_TRANSPORT_RETRIES: u32 = 3;

impl MemoryVectorIndex {
    fn new(
        qdrant_url: String,
        collection: String,
        embedding_url: Option<String>,
        embedding_model: String,
        embedding_api_key: Option<String>,
    ) -> Self {
        let embedding_url = embedding_url.unwrap_or_else(|| {
            std::env::var("BEAGLE_MEMORY_EMBEDDING_URL")
                .unwrap_or_else(|_| "http://t560.local:8001/v1".to_string())
        });
        Self {
            base_url: qdrant_url.trim_end_matches('/').to_string(),
            collection,
            client: reqwest::Client::new(),
            embedding_client: EmbeddingClient::new_with_options(
                embedding_url,
                Some(embedding_model),
                embedding_api_key,
            ),
            collection_ready: Arc::new(RwLock::new(false)),
        }
    }

    async fn qdrant_get_transport_retry(
        &self,
        url: &str,
        op: &'static str,
    ) -> Result<reqwest::Response, reqwest::Error> {
        let mut backoff_ms = 100u64;
        for attempt in 0..QDRANT_TRANSPORT_RETRIES {
            match self.client.get(url).send().await {
                Ok(resp) => return Ok(resp),
                Err(e) => {
                    let retryable = attempt + 1 < QDRANT_TRANSPORT_RETRIES
                        && (e.is_connect() || e.is_timeout());
                    if retryable {
                        warn!(
                            attempt,
                            op,
                            url = %url,
                            error = %e,
                            "Qdrant GET transport error; backing off"
                        );
                        tokio::time::sleep(Duration::from_millis(backoff_ms)).await;
                        backoff_ms = (backoff_ms * 2).min(1500);
                    } else {
                        return Err(e);
                    }
                }
            }
        }
        unreachable!()
    }

    async fn qdrant_put_json_transport_retry(
        &self,
        url: &str,
        body: &serde_json::Value,
        op: &'static str,
    ) -> Result<reqwest::Response, reqwest::Error> {
        let mut backoff_ms = 100u64;
        for attempt in 0..QDRANT_TRANSPORT_RETRIES {
            match self.client.put(url).json(body).send().await {
                Ok(resp) => return Ok(resp),
                Err(e) => {
                    let retryable = attempt + 1 < QDRANT_TRANSPORT_RETRIES
                        && (e.is_connect() || e.is_timeout());
                    if retryable {
                        warn!(
                            attempt,
                            op,
                            url = %url,
                            error = %e,
                            "Qdrant PUT transport error; backing off"
                        );
                        tokio::time::sleep(Duration::from_millis(backoff_ms)).await;
                        backoff_ms = (backoff_ms * 2).min(1500);
                    } else {
                        return Err(e);
                    }
                }
            }
        }
        unreachable!()
    }

    async fn health_probe(&self) -> Result<MemoryIndexProbe, reqwest::Error> {
        let url = format!("{}/collections/{}", self.base_url, self.collection);
        let describe = self.qdrant_get_transport_retry(&url, "health_probe").await?;
        let status = describe.status();
        let code = status.as_u16();
        if status.is_success() {
            return Ok(MemoryIndexProbe::Up);
        }
        let body = describe.text().await.unwrap_or_default();
        if status == reqwest::StatusCode::NOT_FOUND {
            return Ok(MemoryIndexProbe::CollectionMissing(code));
        }
        Ok(MemoryIndexProbe::HttpError(code, body))
    }

    async fn upsert_record(&self, record: &MemoryRecord) -> Result<()> {
        let embedding = self.embedding_client.embed(&record.text).await?;
        self.ensure_collection(embedding.len()).await?;
        let vector: Vec<f32> = embedding.iter().map(|value| *value as f32).collect();
        let response = self
            .client
            .put(format!(
                "{}/collections/{}/points?wait=true",
                self.base_url, self.collection
            ))
            .json(&json!({
                "points": [{
                    "id": record.memory_id,
                    "vector": vector,
                    "payload": record,
                }]
            }))
            .send()
            .await
            .context("Failed to send Qdrant upsert request")?;

        if !response.status().is_success() {
            let error = response.text().await.unwrap_or_default();
            anyhow::bail!("Qdrant upsert failed: {}", error);
        }

        Ok(())
    }

    async fn search_records(&self, query: &str, limit: usize) -> Result<Vec<MemoryRecord>> {
        self.search_records_filtered(query, &RetrievalFilters::default(), limit)
            .await
    }

    async fn search_records_filtered(
        &self,
        query: &str,
        filters: &RetrievalFilters,
        limit: usize,
    ) -> Result<Vec<MemoryRecord>> {
        let embedding = self.embedding_client.embed(query).await?;
        self.ensure_collection(embedding.len()).await?;
        let vector: Vec<f32> = embedding.iter().map(|value| *value as f32).collect();
        // #8 hybrid retrieval: over-fetch the dense candidate pool so it can be re-fused with a
        // lexical ranking (RRF) before truncating to `limit`. No sparse vectors required in the
        // index — the fusion is client-side over the candidates' text. Toggle: BEAGLE_MEMORY_HYBRID.
        let hybrid = std::env::var("BEAGLE_MEMORY_HYBRID")
            .map(|v| !matches!(v.to_lowercase().as_str(), "0" | "false" | "off"))
            .unwrap_or(true);
        let fetch_limit = if hybrid {
            limit.saturating_mul(4).clamp(limit, 64)
        } else {
            limit
        };
        let mut body = json!({
            "vector": vector,
            "limit": fetch_limit,
            "with_payload": true,
            "with_vector": false
        });
        if let Some(filter) = qdrant_filter_for(filters) {
            if let Some(map) = body.as_object_mut() {
                map.insert("filter".to_string(), filter);
            }
        }
        let response = self
            .client
            .post(format!(
                "{}/collections/{}/points/search",
                self.base_url, self.collection
            ))
            .json(&body)
            .send()
            .await
            .context("Failed to send Qdrant search request")?;

        if !response.status().is_success() {
            let error = response.text().await.unwrap_or_default();
            anyhow::bail!("Qdrant search failed: {}", error);
        }

        let payload: serde_json::Value = response
            .json()
            .await
            .context("Failed to decode Qdrant search response")?;
        let mut records = Vec::new();
        if let Some(results) = payload.get("result").and_then(|value| value.as_array()) {
            for item in results {
                let score = item
                    .get("score")
                    .and_then(|value| value.as_f64())
                    .map(|value| value as f32);
                let Some(raw_payload) = item.get("payload").cloned() else {
                    continue;
                };
                match serde_json::from_value::<MemoryRecord>(raw_payload) {
                    Ok(mut record) => {
                        if !record_matches_filters(&record, filters) {
                            continue;
                        }
                        record.score = score;
                        records.push(record);
                    }
                    Err(error) => {
                        warn!(%error, "Failed to parse Qdrant memory payload");
                    }
                }
            }
        }
        // #8 hybrid fusion: re-rank the dense candidate pool by RRF(dense, lexical) over the query
        // text, then truncate to the requested limit. Degrades to dense order when hybrid is off or
        // there is no lexical signal among the candidates.
        if hybrid && records.len() > 1 {
            let texts: Vec<&str> = records.iter().map(|r| r.text.as_str()).collect();
            let order = crate::hybrid::fuse_dense_lexical(query, &texts, 60.0);
            let mut reordered: Vec<MemoryRecord> = Vec::with_capacity(records.len());
            for idx in order {
                reordered.push(records[idx].clone());
            }
            records = reordered;
        }
        records.truncate(limit);
        debug!(count = records.len(), "Qdrant memory search completed");
        Ok(records)
    }

    async fn ensure_collection(&self, embedding_size: usize) -> Result<()> {
        {
            let ready = self.collection_ready.read().await;
            if *ready {
                return Ok(());
            }
        }

        let url = format!("{}/collections/{}", self.base_url, self.collection);
        let describe = self
            .qdrant_get_transport_retry(&url, "describe_collection")
            .await
            .context("Failed to describe Qdrant collection")?;

        if describe.status().is_success() {
            let mut ready = self.collection_ready.write().await;
            *ready = true;
            return Ok(());
        }

        if describe.status() != reqwest::StatusCode::NOT_FOUND {
            let error = describe.text().await.unwrap_or_default();
            anyhow::bail!("Qdrant collection describe failed: {}", error);
        }

        let create_body = json!({
            "vectors": {
                "size": embedding_size,
                "distance": "Cosine"
            }
        });
        let create = self
            .qdrant_put_json_transport_retry(&url, &create_body, "create_collection")
            .await
            .context("Failed to create Qdrant collection")?;

        if !create.status().is_success() {
            let error = create.text().await.unwrap_or_default();
            anyhow::bail!("Qdrant collection creation failed: {}", error);
        }

        let mut ready = self.collection_ready.write().await;
        *ready = true;
        Ok(())
    }
}

fn metadata_string(metadata: &serde_json::Value, key: &str) -> Option<String> {
    metadata
        .get(key)
        .and_then(|value| value.as_str())
        .map(|value| value.trim().to_string())
        .filter(|value| !value.is_empty())
}

fn metadata_string_list(metadata: &serde_json::Value, key: &str) -> Vec<String> {
    metadata
        .get(key)
        .and_then(|value| value.as_array())
        .map(|items| {
            items
                .iter()
                .filter_map(|item| item.as_str())
                .map(|item| item.trim().to_string())
                .filter(|item| !item.is_empty())
                .collect::<Vec<_>>()
        })
        .unwrap_or_default()
}

fn metadata_physio(metadata: &serde_json::Value) -> Option<PhysioSnapshot> {
    metadata
        .get("physio_snapshot")
        .cloned()
        .and_then(|value| serde_json::from_value(value).ok())
}

fn metadata_experiment_flags(metadata: &serde_json::Value) -> Option<ExperimentFlags> {
    metadata
        .get("experiment_flags")
        .cloned()
        .and_then(|value| serde_json::from_value(value).ok())
}

fn stable_memory_id(source: &str, conversation_id: &str, turn_index: usize, role: &str) -> String {
    let seed = format!("{source}:{conversation_id}:{turn_index}:{role}");
    Uuid::new_v5(&Uuid::NAMESPACE_URL, seed.as_bytes()).to_string()
}

fn canonical_role(role: &str) -> String {
    match role.trim().to_ascii_lowercase().as_str() {
        "assistant" => "assistant".to_string(),
        "system" => "system".to_string(),
        "tool" => "tool".to_string(),
        _ => "user".to_string(),
    }
}

fn domain_from_label(label: Option<&str>) -> beagle_personality::Domain {
    match label.unwrap_or("").trim().to_ascii_lowercase().as_str() {
        "pbpk" => beagle_personality::Domain::PBPK,
        "clinicalmedicine" | "clinical-medicine" | "clinical_medicine" => {
            beagle_personality::Domain::ClinicalMedicine
        }
        "psychiatry" => beagle_personality::Domain::Psychiatry,
        "neuroscience" => beagle_personality::Domain::Neuroscience,
        "physics" => beagle_personality::Domain::Physics,
        "quantum" => beagle_personality::Domain::Quantum,
        "chemistry" => beagle_personality::Domain::Chemistry,
        "biomaterials" => beagle_personality::Domain::Biomaterials,
        "heliobiology" => beagle_personality::Domain::Heliobiology,
        "complexsystems" | "complex-systems" | "complex_systems" => {
            beagle_personality::Domain::ComplexSystems
        }
        "philosophy" => beagle_personality::Domain::Philosophy,
        "q1scholar" | "q1-scholar" | "q1_scholar" => beagle_personality::Domain::Q1Scholar,
        "metadiscovery" | "meta-discovery" | "meta_discovery" => {
            beagle_personality::Domain::MetaDiscovery
        }
        "discovery" => beagle_personality::Domain::Discovery,
        "beagleengine" | "beagle-engine" | "beagle_engine" | "beagle" => {
            beagle_personality::Domain::BeagleEngine
        }
        "chemicalengineering" | "chemical-engineering" | "chemical_engineering" => {
            beagle_personality::Domain::ChemicalEngineering
        }
        "medicallaw" | "medical-law" | "medical_law" => beagle_personality::Domain::MedicalLaw,
        "music" => beagle_personality::Domain::Music,
        _ => beagle_personality::Domain::General,
    }
}

fn record_matches(record: &MemoryRecord, domain: Option<&str>, tags: &[String]) -> bool {
    record_matches_filters(
        record,
        &RetrievalFilters {
            domain: domain.map(|value| value.to_string()),
            tags: tags.to_vec(),
            ..RetrievalFilters::default()
        },
    )
}

fn snippet_for_text(text: &str) -> String {
    text.chars().take(240).collect()
}

fn load_local_records(path: &PathBuf) -> Vec<MemoryRecord> {
    let file = match File::open(path) {
        Ok(file) => file,
        Err(_) => return Vec::new(),
        };

    BufReader::new(file)
        .lines()
        .map_while(|line| line.ok())
        .filter_map(|line| serde_json::from_str::<MemoryRecord>(&line).ok())
        .collect()
}

fn persist_local_records(path: &PathBuf, records: &[MemoryRecord]) -> Result<()> {
    if let Some(parent) = path.parent() {
        fs::create_dir_all(parent)
            .with_context(|| format!("Failed to create local memory directory {}", parent.display()))?;
    }
    let tmp_path = path.with_extension("jsonl.tmp");
    let mut file = File::create(&tmp_path)
        .with_context(|| format!("Failed to create local memory file {}", tmp_path.display()))?;
    for record in records {
        writeln!(file, "{}", serde_json::to_string(record)?)
            .with_context(|| format!("Failed to write local memory record {}", record.memory_id))?;
    }
    file.flush()
        .with_context(|| format!("Failed to flush local memory file {}", tmp_path.display()))?;
    fs::rename(&tmp_path, path).with_context(|| {
        format!(
            "Failed to replace local memory file {} with {}",
            path.display(),
            tmp_path.display()
        )
    })?;
    Ok(())
}

fn lexical_score(query: &str, record: &MemoryRecord) -> f32 {
    let normalized_query = query.trim().to_ascii_lowercase();
    if normalized_query.is_empty() {
        return 0.0;
    }

    let haystack = format!(
        "{} {} {} {} {} {} {} {} {} {} {} {} {}",
        record.text,
        record.domain.as_deref().unwrap_or_default(),
        record.repo_path.as_deref().unwrap_or_default(),
        record.file_type.as_deref().unwrap_or_default(),
        record.tags.join(" "),
        record.source,
        record.workstream_id.as_deref().unwrap_or_default(),
        record.campaign_id.as_deref().unwrap_or_default(),
        record.program_id.as_deref().unwrap_or_default(),
        record.workspace_id.as_deref().unwrap_or_default(),
        record.session_id.as_deref().unwrap_or_default(),
        record.result_refs.join(" "),
        record.claim_refs.join(" ")
    )
    .to_ascii_lowercase();

    let query_terms: Vec<&str> = normalized_query
        .split_whitespace()
        .filter(|term| !term.is_empty())
        .collect();
    if query_terms.is_empty() {
        return 0.0;
    }

    let matched_terms = query_terms
        .iter()
        .filter(|term| haystack.contains(**term))
        .count() as f32;
    let term_ratio = matched_terms / query_terms.len() as f32;
    let exact_bonus = if haystack.contains(&normalized_query) { 0.5 } else { 0.0 };
    let role_bonus = if record.role == "assistant" { 0.05 } else { 0.0 };

    (term_ratio + exact_bonus + role_bonus).min(1.0)
}

fn retrieval_collection_payload_fields() -> Vec<RetrievalCollectionField> {
    vec![
        retrieval_field("memory_id", "string", false, true),
        retrieval_field("workstream_id", "string", true, true),
        retrieval_field("campaign_id", "string", true, true),
        retrieval_field("program_id", "string", false, true),
        retrieval_field("workspace_id", "string", false, true),
        retrieval_field("session_id", "string", true, true),
        retrieval_field("source", "string", true, true),
        retrieval_field("conversation_id", "string", false, true),
        retrieval_field("turn_index", "integer", false, false),
        retrieval_field("role", "string", true, true),
        retrieval_field("domain", "string", true, true),
        retrieval_field("repo_path", "string", true, true),
        retrieval_field("file_type", "string", true, true),
        retrieval_field("tags", "string[]", true, true),
        retrieval_field("physio_snapshot_ref", "string", false, false),
        retrieval_field("physio_snapshot", "object", false, false),
        retrieval_field("experiment_flags", "object", false, false),
        retrieval_field("result_refs", "string[]", false, true),
        retrieval_field("claim_refs", "string[]", false, true),
        retrieval_field("timestamp", "date-time", false, true),
    ]
}

fn retrieval_field(
    name: &str,
    field_type: &str,
    filterable: bool,
    indexed_hint: bool,
) -> RetrievalCollectionField {
    RetrievalCollectionField {
        name: name.to_string(),
        field_type: field_type.to_string(),
        filterable,
        indexed_hint,
    }
}

fn record_matches_filters(record: &MemoryRecord, filters: &RetrievalFilters) -> bool {
    let workstream_ok = filters
        .workstream_id
        .as_deref()
        .map(|expected| {
            record
                .workstream_id
                .as_deref()
                .map(|value| value.eq_ignore_ascii_case(expected))
                .unwrap_or(false)
        })
        .unwrap_or(true);
    let campaign_ok = filters
        .campaign_id
        .as_deref()
        .map(|expected| {
            record
                .campaign_id
                .as_deref()
                .map(|value| value.eq_ignore_ascii_case(expected))
                .unwrap_or(false)
        })
        .unwrap_or(true);
    let session_ok = filters
        .session_id
        .as_deref()
        .map(|expected| {
            record
                .session_id
                .as_deref()
                .map(|value| value.eq_ignore_ascii_case(expected))
                .or_else(|| {
                    Some(
                        record
                            .conversation_id
                            .eq_ignore_ascii_case(expected),
                    )
                })
                .unwrap_or(false)
        })
        .unwrap_or(true);
    let source_ok = filters
        .source
        .as_deref()
        .map(|expected| record.source.eq_ignore_ascii_case(expected))
        .unwrap_or(true);
    let role_ok = filters
        .role
        .as_deref()
        .map(|expected| record.role.eq_ignore_ascii_case(expected))
        .unwrap_or(true);
    let domain_ok = filters
        .domain
        .as_deref()
        .map(|expected| {
            record
                .domain
                .as_deref()
                .map(|value| value.eq_ignore_ascii_case(expected))
                .unwrap_or(false)
        })
        .unwrap_or(true);
    let repo_path_ok = filters
        .repo_path
        .as_deref()
        .map(|expected| {
            record
                .repo_path
                .as_deref()
                .map(|value| value.eq_ignore_ascii_case(expected))
                .unwrap_or(false)
        })
        .unwrap_or(true);
    let file_type_ok = filters
        .file_type
        .as_deref()
        .map(|expected| {
            record
                .file_type
                .as_deref()
                .map(|value| value.eq_ignore_ascii_case(expected))
                .unwrap_or(false)
        })
        .unwrap_or(true);
    let tags_ok = filters.tags.iter().all(|tag| {
        record
            .tags
            .iter()
            .any(|candidate| candidate.eq_ignore_ascii_case(tag))
    });

    workstream_ok
        && campaign_ok
        && session_ok
        && source_ok
        && role_ok
        && domain_ok
        && repo_path_ok
        && file_type_ok
        && tags_ok
}

fn qdrant_filter_for(filters: &RetrievalFilters) -> Option<serde_json::Value> {
    let mut must = Vec::new();

    push_scalar_filter(&mut must, "workstream_id", filters.workstream_id.as_deref());
    push_scalar_filter(&mut must, "campaign_id", filters.campaign_id.as_deref());
    push_scalar_filter(&mut must, "session_id", filters.session_id.as_deref());
    push_scalar_filter(&mut must, "source", filters.source.as_deref());
    push_scalar_filter(&mut must, "role", filters.role.as_deref());
    push_scalar_filter(&mut must, "domain", filters.domain.as_deref());
    push_scalar_filter(&mut must, "repo_path", filters.repo_path.as_deref());
    push_scalar_filter(&mut must, "file_type", filters.file_type.as_deref());
    if !filters.tags.is_empty() {
        must.push(json!({
            "key": "tags",
            "match": {
                "any": filters.tags
            }
        }));
    }

    if must.is_empty() {
        None
    } else {
        Some(json!({ "must": must }))
    }
}

fn push_scalar_filter(target: &mut Vec<serde_json::Value>, key: &str, value: Option<&str>) {
    let Some(value) = value.map(str::trim).filter(|value| !value.is_empty()) else {
        return;
    };
    target.push(json!({
        "key": key,
        "match": {
            "value": value
        }
    }));
}

fn retrieval_hit_is_context_usable(hit: &RetrievalHit) -> bool {
    let payload = &hit.point.payload;
    !payload.memory_id.is_empty()
        && !payload.source.is_empty()
        && payload.workstream_id.is_some()
        && !payload.tags.is_empty()
}

fn average_f32(values: impl Iterator<Item = f32>) -> f32 {
    let mut count = 0usize;
    let mut total = 0.0f32;
    for value in values {
        total += value;
        count += 1;
    }
    if count == 0 {
        0.0
    } else {
        total / count as f32
    }
}

fn normalize_router_selector(value: &str) -> String {
    value.trim().to_ascii_lowercase().replace('_', "-")
}

fn normalize_query_type_hint(value: &str) -> Option<&'static str> {
    match value {
        "general" | "memory" | "campaign" | "program" => Some("general"),
        "code" | "repo" | "config" | "script" => Some("code"),
        "sovereign" | "multilingual" | "privacy-sensitive" | "privacy" | "private"
        | "self-hosted" | "offline" => Some("sovereign"),
        _ => None,
    }
}

fn retrieval_filters_present(filters: &RetrievalFilters) -> bool {
    filters.workstream_id.is_some()
        || filters.campaign_id.is_some()
        || filters.session_id.is_some()
        || filters.source.is_some()
        || filters.role.is_some()
        || filters.domain.is_some()
        || filters.repo_path.is_some()
        || filters.file_type.is_some()
        || !filters.tags.is_empty()
}

fn filters_signal_code(filters: &RetrievalFilters) -> bool {
    filters
        .repo_path
        .as_deref()
        .map(str::trim)
        .filter(|value| !value.is_empty())
        .is_some()
        || filters
            .file_type
            .as_deref()
            .map(str::trim)
            .filter(|value| !value.is_empty())
            .is_some()
}

fn query_text_signals_code(query_text: &str) -> bool {
    let normalized = query_text.to_ascii_lowercase();
    [
        ".rs",
        ".py",
        ".sh",
        ".yaml",
        ".yml",
        ".toml",
        ".json",
        "fn ",
        "struct ",
        "impl ",
        "class ",
        "cargo ",
        "kubectl ",
        "configmap",
        "deployment",
        "script",
        "crate::",
        "repo path",
        "workspace_attach",
    ]
    .iter()
    .any(|signal| normalized.contains(signal))
}

fn query_text_signals_sovereign(query_text: &str) -> bool {
    let normalized = query_text.to_ascii_lowercase();
    query_text.chars().any(|character| !character.is_ascii())
        || [
            "multilingual",
            "multilingue",
            "multilingu",
            "privacy",
            "privacidade",
            "private",
            "sovereign",
            "soberano",
            "self-hosted",
            "offline",
            "portuguese",
            "portugues",
            "espanol",
            "spanish",
        ]
        .iter()
        .any(|signal| normalized.contains(signal))
}

fn rerank_document_text(hit: &RetrievalHit) -> String {
    let payload = &hit.point.payload;
    let mut lines = Vec::new();
    if let Some(repo_path) = payload.repo_path.as_deref() {
        lines.push(format!("repo_path: {}", repo_path));
    }
    if let Some(file_type) = payload.file_type.as_deref() {
        lines.push(format!("file_type: {}", file_type));
    }
    if let Some(domain) = payload.domain.as_deref() {
        lines.push(format!("domain: {}", domain));
    }
    if !payload.tags.is_empty() {
        lines.push(format!("tags: {}", payload.tags.join(", ")));
    }
    if !payload.result_refs.is_empty() {
        lines.push(format!("result_refs: {}", payload.result_refs.join(", ")));
    }
    if !payload.claim_refs.is_empty() {
        lines.push(format!("claim_refs: {}", payload.claim_refs.join(", ")));
    }
    lines.push(payload.text.clone());
    lines.join("\n")
}

fn parse_rerank_scores(body: &str) -> Result<Vec<RerankScore>> {
    let value: serde_json::Value =
        serde_json::from_str(body).context("failed to decode rerank response JSON")?;
    let entries = if let Some(results) = value.get("results").and_then(|items| items.as_array()) {
        results.clone()
    } else if let Some(data) = value.get("data").and_then(|items| items.as_array()) {
        data.clone()
    } else if let Some(items) = value.as_array() {
        items.clone()
    } else {
        anyhow::bail!("rerank response did not contain a results array");
    };

    let mut scores = entries
        .into_iter()
        .filter_map(|entry| {
            let index = entry
                .get("index")
                .and_then(|value| value.as_u64())
                .map(|value| value as usize)?;
            let score = entry
                .get("relevance_score")
                .or_else(|| entry.get("score"))
                .and_then(|value| value.as_f64())
                .map(|value| value as f32)?;
            Some(RerankScore { index, score })
        })
        .collect::<Vec<_>>();
    scores.sort_by(|left, right| {
        right
            .score
            .partial_cmp(&left.score)
            .unwrap_or(std::cmp::Ordering::Equal)
    });
    Ok(scores)
}

fn apply_rerank_scores_to_hits(
    prerank_hits: &[RetrievalHit],
    rerank_scores: &[RerankScore],
) -> Vec<RerankedHit> {
    let mut emitted = HashSet::new();
    let mut hits = Vec::new();

    for (new_rank, score) in rerank_scores.iter().enumerate() {
        if let Some(hit) = prerank_hits.get(score.index) {
            emitted.insert(score.index);
            hits.push(RerankedHit {
                rank: new_rank + 1,
                prerank_rank: hit.rank,
                point: hit.point.clone(),
                dense_score: hit.dense_score,
                sparse_score: hit.sparse_score,
                hybrid_score: hit.hybrid_score,
                rerank_score: score.score,
            });
        }
    }

    for (index, hit) in prerank_hits.iter().enumerate() {
        if emitted.contains(&index) {
            continue;
        }
        hits.push(RerankedHit {
            rank: hits.len() + 1,
            prerank_rank: hit.rank,
            point: hit.point.clone(),
            dense_score: hit.dense_score,
            sparse_score: hit.sparse_score,
            hybrid_score: hit.hybrid_score,
            rerank_score: hit.hybrid_score,
        });
    }

    hits
}

fn apply_feedback_judgments_to_hits(
    prerank_hits: &[RerankedHit],
    judgments: &[RelevanceFeedbackJudgment],
) -> Vec<FeedbackAdjustedHit> {
    let mut feedback_scores = HashMap::new();
    for judgment in judgments {
        feedback_scores.insert(judgment.memory_id.clone(), feedback_signal_score(judgment));
    }

    let mut hits = prerank_hits
        .iter()
        .map(|hit| {
            let base_score = if hit.rerank_score > 0.0 {
                hit.rerank_score
            } else {
                hit.hybrid_score
            };
            let feedback_score = feedback_scores
                .get(&hit.point.payload.memory_id)
                .copied()
                .unwrap_or(0.0);
            FeedbackAdjustedHit {
                rank: hit.rank,
                prerank_rank: hit.prerank_rank,
                point: hit.point.clone(),
                dense_score: hit.dense_score,
                sparse_score: hit.sparse_score,
                hybrid_score: hit.hybrid_score,
                rerank_score: hit.rerank_score,
                feedback_score,
                adjusted_score: base_score + feedback_score,
            }
        })
        .collect::<Vec<_>>();

    hits.sort_by(|left, right| {
        right
            .adjusted_score
            .partial_cmp(&left.adjusted_score)
            .unwrap_or(std::cmp::Ordering::Equal)
            .then_with(|| left.prerank_rank.cmp(&right.prerank_rank))
    });

    for (index, hit) in hits.iter_mut().enumerate() {
        hit.rank = index + 1;
    }

    hits
}

fn relevance_proxy_for_reranked_hits(hits: &[RerankedHit], query_text: &str) -> f32 {
    if hits.is_empty() {
        return 0.0;
    }
    average_f32(hits.iter().map(|hit| lexical_overlap_ratio(query_text, &hit.point.payload)))
}

fn relevance_proxy_for_feedback_hits(
    hits: &[RerankedHit],
    query_text: &str,
    expected_memory_ids: &[String],
) -> f32 {
    if !expected_memory_ids.is_empty() {
        let expected: HashSet<&str> = expected_memory_ids.iter().map(String::as_str).collect();
        let matching = hits
            .iter()
            .filter(|hit| expected.contains(hit.point.payload.memory_id.as_str()))
            .count();
        return matching as f32 / expected_memory_ids.len().max(1) as f32;
    }

    relevance_proxy_for_reranked_hits(hits, query_text)
}

fn relevance_proxy_for_feedback_adjusted_hits(
    hits: &[FeedbackAdjustedHit],
    query_text: &str,
    expected_memory_ids: &[String],
) -> f32 {
    if !expected_memory_ids.is_empty() {
        let expected: HashSet<&str> = expected_memory_ids.iter().map(String::as_str).collect();
        let matching = hits
            .iter()
            .filter(|hit| expected.contains(hit.point.payload.memory_id.as_str()))
            .count();
        return matching as f32 / expected_memory_ids.len().max(1) as f32;
    }

    if hits.is_empty() {
        return 0.0;
    }

    average_f32(hits.iter().map(|hit| lexical_overlap_ratio(query_text, &hit.point.payload)))
}

fn reranking_recommendation_for_lane(
    query_type: &str,
    reranker_backend: &str,
    runtime_state: &str,
    reranking_applied: bool,
    top_hit_changed: bool,
    relevance_proxy_before: f32,
    relevance_proxy_after: f32,
    latency_delta_ms: u64,
) -> RerankingRecommendation {
    let recommendation = if reranking_applied && top_hit_changed && relevance_proxy_after >= relevance_proxy_before
    {
        "keep-bounded-reranking-pilot-enabled".to_string()
    } else if reranking_applied {
        "keep-pilot-bounded-and-measure-more".to_string()
    } else {
        "fallback-to-prerank-and-fix-runtime".to_string()
    };

    RerankingRecommendation {
        query_type: query_type.to_string(),
        reranker_backend: reranker_backend.to_string(),
        runtime_state: runtime_state.to_string(),
        reranking_applied,
        top_hit_changed,
        relevance_proxy_before,
        relevance_proxy_after,
        latency_delta_ms,
        recommendation,
        note: format!(
            "B22.8 keeps reranking bounded for the {} lane while tracking pre/post ranking and latency deltas explicitly.",
            query_type
        ),
    }
}

fn filter_correctness_for_hits(hits: &[RetrievalHit], filters: &RetrievalFilters) -> f32 {
    if hits.is_empty() {
        return 0.0;
    }
    let matching = hits
        .iter()
        .filter(|hit| record_matches_filters(&hit.point.payload, filters))
        .count();
    matching as f32 / hits.len() as f32
}

fn filter_correctness_for_reranked_hits(
    hits: &[RerankedHit],
    filters: &RetrievalFilters,
) -> f32 {
    if hits.is_empty() {
        return 0.0;
    }
    let matching = hits
        .iter()
        .filter(|hit| record_matches_filters(&hit.point.payload, filters))
        .count();
    matching as f32 / hits.len() as f32
}

fn relevance_proxy_for_hits(
    hits: &[RetrievalHit],
    query_text: &str,
    expected_memory_ids: &[String],
) -> f32 {
    if !expected_memory_ids.is_empty() {
        let expected: HashSet<&str> = expected_memory_ids.iter().map(String::as_str).collect();
        let matching = hits
            .iter()
            .filter(|hit| expected.contains(hit.point.payload.memory_id.as_str()))
            .count();
        return matching as f32 / expected_memory_ids.len().max(1) as f32;
    }

    if hits.is_empty() {
        return 0.0;
    }

    average_f32(hits.iter().map(|hit| lexical_overlap_ratio(query_text, &hit.point.payload)))
}

fn benchmark_case_note(
    dense_backend: &str,
    case: &RetrievalBenchmarkCase,
    result: &RetrievalResult,
) -> String {
    let filter_note = if result.applied_filters == RetrievalFilters::default() {
        "unfiltered"
    } else {
        "payload-filtered"
    };
    format!(
        "{} case on {} over {} retrieval returned {} hit(s).",
        case.case_kind,
        dense_backend,
        filter_note,
        result.hits.len()
    )
}

fn eval_case_note(query_type: &str, query_text: &str, result: &RerankedResult) -> String {
    format!(
        "{} evaluation case used route {} with dense backend {} and returned {} hit(s) for query {:?}.",
        query_type,
        result.routing_decision.selected_route,
        result.dense_backend,
        result.hits.len(),
        query_text
    )
}

fn eval_lane_note(query_type: &str, lane_cases: &[&RetrievalEvalCaseReport]) -> String {
    let avg_relevance = average_f32(
        lane_cases
            .iter()
            .map(|case| case.relevance_proxy_score),
    );
    let avg_filters = average_f32(
        lane_cases
            .iter()
            .map(|case| case.payload_filter_correctness),
    );
    format!(
        "B22.9 keeps the {} lane evidence-backed with average relevance {:.2} and filter correctness {:.2}.",
        query_type,
        avg_relevance,
        avg_filters
    )
}

fn recommended_when_for_query_type(query_type: &str) -> String {
    match query_type {
        "code" => "Use this lane when repo paths, file types, scripts, or configuration intent dominate the query.".to_string(),
        "sovereign" => "Use this lane when multilingual, privacy-sensitive, self-hosted, or offline-capable retrieval matters most.".to_string(),
        _ => "Use this lane for general campaign, workstream, memory, and tool-context retrieval.".to_string(),
    }
}

fn feedback_mode_for_lane(lane: &RetrievalEvalLaneSummary) -> String {
    if lane.average_relevance_proxy < 0.95 || lane.route_appropriateness_rate < 1.0 {
        "enable-bounded-feedback-loop".to_string()
    } else {
        "keep-feedback-available-on-demand".to_string()
    }
}

fn feedback_signal_score(judgment: &RelevanceFeedbackJudgment) -> f32 {
    let magnitude = judgment.score.abs().clamp(0.0, 1.0);
    match judgment.signal.trim().to_ascii_lowercase().as_str() {
        "positive" | "promote" | "upvote" => magnitude,
        "negative" | "demote" | "downvote" => -magnitude,
        _ => 0.0,
    }
}

fn memory_hierarchy_from_records(
    collection_name: &str,
    records: &[MemoryRecord],
) -> MemoryHierarchy {
    let mut episodic_memory_ids = Vec::new();
    let mut semantic_memory_ids = Vec::new();
    let mut procedural_memory_ids = Vec::new();

    for record in records {
        match classify_memory_type(record) {
            "procedural" => procedural_memory_ids.push(record.memory_id.clone()),
            "semantic" => semantic_memory_ids.push(record.memory_id.clone()),
            _ => episodic_memory_ids.push(record.memory_id.clone()),
        }
    }

    MemoryHierarchy {
        hierarchy_version: MEMORY_HIERARCHY_VERSION.to_string(),
        policy_id: "b231-memory-hierarchy-policy".to_string(),
        collection_name: collection_name.to_string(),
        buckets: vec![
            MemoryHierarchyBucket {
                memory_type: "episodic".to_string(),
                description: "Session-bound turns, operator events, and observer moments that preserve temporal continuity.".to_string(),
                store_when: vec![
                    "store conversation/session turns with temporal context".to_string(),
                    "prefer this bucket for observer snapshots and handoff chronology".to_string(),
                ],
                count: episodic_memory_ids.len(),
                memory_ids: episodic_memory_ids,
            },
            MemoryHierarchyBucket {
                memory_type: "semantic".to_string(),
                description: "Claims, results, evidence-bearing facts, and distilled program/campaign knowledge.".to_string(),
                store_when: vec![
                    "store result_refs and claim_refs here".to_string(),
                    "prefer this bucket for evidence, claim, and manuscript support".to_string(),
                ],
                count: semantic_memory_ids.len(),
                memory_ids: semantic_memory_ids,
            },
            MemoryHierarchyBucket {
                memory_type: "procedural".to_string(),
                description: "Repo-native procedures, configs, scripts, and code execution know-how.".to_string(),
                store_when: vec![
                    "store repo_path/file_type backed records here".to_string(),
                    "prefer this bucket for code, config, attach, launch, and operator procedures".to_string(),
                ],
                count: procedural_memory_ids.len(),
                memory_ids: procedural_memory_ids,
            },
        ],
        note: "B23.1 keeps memory hierarchy explicit without changing the canonical retrieval spine or introducing a separate memory system.".to_string(),
    }
}

fn first_non_empty<I>(values: I) -> Option<String>
where
    I: IntoIterator<Item = String>,
{
    values
        .into_iter()
        .map(|value| value.trim().to_string())
        .find(|value| !value.is_empty())
}

fn resolve_graph_root_entity(
    query: &GraphRagQuery,
    program_id: Option<&str>,
    campaign_id: Option<&str>,
    workstream_id: Option<&str>,
    session_id: Option<&str>,
) -> (Option<String>, Option<String>) {
    if let (Some(root_type), Some(root_id)) = (
        query.root_entity_type.as_deref(),
        query.root_entity_id.as_deref(),
    ) {
        return (
            Some(normalize_graph_entity_type(root_type).to_string()),
            Some(root_id.to_string()),
        );
    }
    if let Some(workstream_id) = workstream_id {
        return (Some("workstream".to_string()), Some(workstream_id.to_string()));
    }
    if let Some(campaign_id) = campaign_id {
        return (Some("campaign".to_string()), Some(campaign_id.to_string()));
    }
    if let Some(program_id) = program_id {
        return (Some("program".to_string()), Some(program_id.to_string()));
    }
    if let Some(session_id) = session_id {
        return (Some("session".to_string()), Some(session_id.to_string()));
    }
    (None, None)
}

fn normalize_graph_entity_type(value: &str) -> &'static str {
    match value.trim().to_ascii_lowercase().as_str() {
        "program" => "program",
        "campaign" => "campaign",
        "session" => "session",
        "experiment" => "experiment",
        "result" => "result",
        "claim" => "claim",
        "manuscript" => "manuscript",
        _ => "workstream",
    }
}

fn canonical_graph_node_type(value: &str) -> &'static str {
    match normalize_graph_entity_type(value) {
        "program" => "Program",
        "campaign" => "Campaign",
        "session" => "Session",
        "experiment" => "Experiment",
        "result" => "Result",
        "claim" => "Claim",
        "manuscript" => "Manuscript",
        _ => "Workstream",
    }
}

fn graph_node_key(entity_type: &str, entity_id: &str) -> String {
    format!(
        "{}:{}",
        normalize_graph_entity_type(entity_type),
        entity_id.trim()
    )
}

fn derive_experiment_id_from_result_ref(result_ref: &str) -> Option<String> {
    let trimmed = result_ref.trim();
    if trimmed.is_empty() {
        return None;
    }
    if let Some((experiment_id, _)) = trimmed.split_once('/') {
        let experiment_id = experiment_id.trim();
        if !experiment_id.is_empty() {
            return Some(experiment_id.to_string());
        }
    }
    if let Some((experiment_id, _)) = trimmed.split_once("::") {
        let experiment_id = experiment_id.trim();
        if !experiment_id.is_empty() {
            return Some(experiment_id.to_string());
        }
    }
    None
}

fn upsert_graph_node(
    nodes: &mut std::collections::BTreeMap<String, GraphRagNode>,
    node_id: String,
    node_type: String,
    display_name: String,
    support_memory_id: Option<String>,
    properties: serde_json::Value,
) {
    let entry = nodes.entry(node_id.clone()).or_insert_with(|| GraphRagNode {
        node_version: GRAPHRAG_NODE_VERSION.to_string(),
        node_id: node_id.clone(),
        node_type,
        display_name,
        support_memory_ids: Vec::new(),
        properties,
    });
    if let Some(memory_id) = support_memory_id {
        if !entry.support_memory_ids.iter().any(|existing| existing == &memory_id) {
            entry.support_memory_ids.push(memory_id);
        }
    }
}

fn upsert_graph_edge(
    edges: &mut std::collections::BTreeMap<String, GraphRagEdge>,
    from_node_id: String,
    to_node_id: String,
    edge_type: String,
    support_memory_id: Option<String>,
    properties: serde_json::Value,
) {
    let edge_id = format!("{}:{}->{}", edge_type, from_node_id, to_node_id);
    let entry = edges.entry(edge_id.clone()).or_insert_with(|| GraphRagEdge {
        edge_version: GRAPHRAG_EDGE_VERSION.to_string(),
        edge_id,
        from_node_id: from_node_id.clone(),
        to_node_id: to_node_id.clone(),
        edge_type,
        support_memory_ids: Vec::new(),
        properties,
    });
    if let Some(memory_id) = support_memory_id {
        if !entry.support_memory_ids.iter().any(|existing| existing == &memory_id) {
            entry.support_memory_ids.push(memory_id);
        }
    }
}

fn unique_strings<I>(values: I, limit: usize) -> Vec<String>
where
    I: IntoIterator<Item = String>,
{
    let mut seen = HashSet::new();
    let mut unique = Vec::new();
    for value in values {
        let normalized = value.trim();
        if normalized.is_empty() || !seen.insert(normalized.to_string()) {
            continue;
        }
        unique.push(normalized.to_string());
        if unique.len() >= limit {
            break;
        }
    }
    unique
}

fn derive_promoted_memories(hits: &[RerankedHit]) -> Vec<PromotedMemory> {
    let mut promoted = Vec::new();
    let mut seen = HashSet::new();

    for hit in hits {
        let record = &hit.point.payload;
        let Some(target_memory_type) = promoted_target_memory_type(record) else {
            continue;
        };

        if let Some(event) = derive_memory_promotion(
            record,
            Utc::now(),
            &retention_action_for_memory_type(&target_memory_type),
        ) {
            if seen.insert(event.source_memory_id.clone()) {
                promoted.push(event);
            }
        }

        if promoted.len() >= 3 {
            break;
        }
    }

    promoted
}

fn temporal_query_from_runtime(
    query: &TemporalQuery,
    truth_view: &str,
    collection: &RetrievalCollection,
    reranked: &RerankedResult,
    records: &[MemoryRecord],
) -> TemporalQueryResult {
    let candidate_limit = query.top_k.clamp(1, 8).saturating_mul(2).max(2);
    let requested_subject_refs = unique_strings(
        query
            .subject_refs
            .iter()
            .map(|value| value.trim().to_string())
            .filter(|value| !value.is_empty()),
        candidate_limit,
    );
    let mut candidate_truth_keys = if requested_subject_refs.is_empty() {
        let mut keys = unique_strings(
            reranked
                .hits
                .iter()
                .flat_map(|hit| temporal_truth_keys(&hit.point.payload)),
            candidate_limit,
        );
        let mut root_scoped_records = records
            .iter()
            .filter(|record| record_matches_filters(record, &query.filters))
            .filter(|record| {
                record_matches_temporal_root(
                    record,
                    query.root_entity_type.as_deref(),
                    query.root_entity_id.as_deref(),
                )
            })
            .cloned()
            .collect::<Vec<_>>();
        root_scoped_records.sort_by(|left, right| {
            right
                .timestamp
                .cmp(&left.timestamp)
                .then_with(|| right.turn_index.cmp(&left.turn_index))
                .then_with(|| right.memory_id.cmp(&left.memory_id))
        });
        extend_unique_memory_ids(
            &mut keys,
            root_scoped_records
                .iter()
                .flat_map(temporal_truth_keys)
                .take(candidate_limit.saturating_mul(2)),
            candidate_limit,
        );
        keys
    } else {
        requested_subject_refs.clone()
    };
    if candidate_truth_keys.is_empty() {
        candidate_truth_keys = unique_strings(
            reranked
                .hits
                .iter()
                .map(|hit| format!("memory:{}", hit.point.payload.memory_id)),
            query.top_k.clamp(1, 8).max(2),
        );
    }
    let candidate_truth_key_set = candidate_truth_keys
        .iter()
        .cloned()
        .collect::<HashSet<_>>();

    let mut grouped_records: HashMap<String, Vec<MemoryRecord>> = HashMap::new();
    for record in records {
        if !record_matches_filters(record, &query.filters) {
            continue;
        }
        if !record_matches_temporal_root(
            record,
            query.root_entity_type.as_deref(),
            query.root_entity_id.as_deref(),
        ) {
            continue;
        }
        for truth_key in temporal_truth_keys(record) {
            if candidate_truth_key_set.contains(&truth_key) {
                grouped_records
                    .entry(truth_key)
                    .or_default()
                    .push(record.clone());
            }
        }
    }

    if grouped_records.is_empty() {
        for hit in reranked.hits.iter().take(query.top_k.clamp(1, 8).max(1)) {
            grouped_records.insert(
                format!("memory:{}", hit.point.payload.memory_id),
                vec![hit.point.payload.clone()],
            );
        }
    }

    let mut built_tracks = Vec::new();
    for (truth_key, mut group) in grouped_records {
        group.sort_by(|left, right| {
            left.timestamp
                .cmp(&right.timestamp)
                .then_with(|| left.turn_index.cmp(&right.turn_index))
                .then_with(|| left.memory_id.cmp(&right.memory_id))
        });
        let Some(current) = group.last().cloned() else {
            continue;
        };
        let historical = group
            .iter()
            .take(group.len().saturating_sub(1))
            .cloned()
            .collect::<Vec<_>>();
        let historical_memory_ids = historical
            .iter()
            .map(|record| record.memory_id.clone())
            .collect::<Vec<_>>();
        let entity_refs = unique_strings(
            group
                .iter()
                .flat_map(temporal_entity_refs)
                .collect::<Vec<_>>()
                .into_iter(),
            10,
        );
        let version_window_start = group.len().saturating_sub(4);
        let versions = group[version_window_start..]
            .iter()
            .enumerate()
            .map(|(offset, record)| {
                let absolute_index = version_window_start + offset + 1;
                let valid_until = group
                    .get(version_window_start + offset + 1)
                    .map(|next| next.timestamp.to_rfc3339());
                let truth_status = if absolute_index == group.len() {
                    "current"
                } else {
                    "historical"
                };
                temporal_version_from_record(record, truth_status, absolute_index, valid_until)
            })
            .collect::<Vec<_>>();
        let contradictions = if query.include_contradictions {
            historical
                .iter()
                .rev()
                .filter_map(|prior| {
                    let (contradiction_kind, reason) =
                        detect_temporal_contradiction(&current, prior)?;
                    Some(MemoryContradiction {
                        contradiction_version: crate::temporal::MEMORY_CONTRADICTION_VERSION
                            .to_string(),
                        contradiction_id: Uuid::new_v5(
                            &Uuid::NAMESPACE_URL,
                            format!(
                                "{}:{}:{}",
                                truth_key, current.memory_id, prior.memory_id
                            )
                            .as_bytes(),
                        )
                        .to_string(),
                        truth_key: truth_key.clone(),
                        contradiction_kind,
                        contradiction_status: "current-vs-historical".to_string(),
                        current_memory_id: current.memory_id.clone(),
                        contradicted_memory_id: prior.memory_id.clone(),
                        entity_refs: entity_refs.clone(),
                        current_observed_at: current.timestamp.to_rfc3339(),
                        contradicted_observed_at: prior.timestamp.to_rfc3339(),
                        reason,
                        current_snippet: snippet_for_text(&current.text),
                        contradicted_snippet: snippet_for_text(&prior.text),
                    })
                })
                .take(2)
                .collect::<Vec<_>>()
        } else {
            Vec::new()
        };

        built_tracks.push((
            TemporalMemoryTrack {
                temporal_version: crate::temporal::TEMPORAL_MEMORY_VERSION.to_string(),
                truth_key: truth_key.clone(),
                entity_refs,
                current_memory_id: current.memory_id.clone(),
                historical_memory_ids,
                version_count: group.len(),
                contradiction_count: contradictions.len(),
                current_memory_type: classify_memory_type(&current).to_string(),
                latest_observed_at: Some(current.timestamp.to_rfc3339()),
                versions,
                note: "B23.4 keeps the newest version as current truth while preserving prior versions as historical truth on the same canonical subject.".to_string(),
            },
            contradictions,
        ));
    }

    built_tracks.sort_by(|(left_track, left_contradictions), (right_track, right_contradictions)| {
        right_track
            .latest_observed_at
            .cmp(&left_track.latest_observed_at)
            .then_with(|| right_contradictions.len().cmp(&left_contradictions.len()))
            .then_with(|| left_track.truth_key.cmp(&right_track.truth_key))
    });
    built_tracks.truncate(query.top_k.clamp(1, 8).max(1));

    let tracks = built_tracks
        .iter()
        .map(|(track, _)| track.clone())
        .collect::<Vec<_>>();
    let contradictions = if query.include_contradictions {
        built_tracks
            .iter()
            .flat_map(|(_, contradictions)| contradictions.clone())
            .take(query.top_k.clamp(1, 8).saturating_mul(2).max(2))
            .collect::<Vec<_>>()
    } else {
        Vec::new()
    };

    let top_current_memory_ids = if truth_view == "historical" {
        Vec::new()
    } else {
        tracks
            .iter()
            .map(|track| track.current_memory_id.clone())
            .take(query.top_k.clamp(1, 8))
            .collect::<Vec<_>>()
    };
    let top_historical_memory_ids = if truth_view == "current" {
        Vec::new()
    } else {
        let mut ids = Vec::new();
        for track in &tracks {
            extend_unique_memory_ids(
                &mut ids,
                track.historical_memory_ids.iter().cloned(),
                query.top_k.clamp(1, 8),
            );
        }
        ids
    };

    TemporalQueryResult {
        result_version: TEMPORAL_QUERY_RESULT_VERSION.to_string(),
        schema_version: crate::temporal::TEMPORAL_MEMORY_VERSION.to_string(),
        truth_view: truth_view.to_string(),
        collection_name: collection.collection_name.clone(),
        query_type: reranked.query_type.clone(),
        retrieval_mode: reranked.postrank_retrieval_mode.clone(),
        dense_backend: reranked.dense_backend.clone(),
        sparse_backend: reranked.sparse_backend.clone(),
        reranker_backend: reranked.reranker_backend.clone(),
        reranking_applied: reranked.reranking_applied,
        applied_filters: query.filters.clone(),
        temporal_root_entity_type: query.root_entity_type.clone(),
        temporal_root_entity_id: query.root_entity_id.clone(),
        subject_refs: candidate_truth_keys,
        track_count: tracks.len(),
        current_truth_count: top_current_memory_ids.len(),
        historical_truth_count: top_historical_memory_ids.len(),
        contradiction_count: contradictions.len(),
        top_current_memory_ids,
        top_historical_memory_ids,
        tracks,
        contradictions,
        note: "B23.4 temporal retrieval stays bounded: current truth, historical truth, and contradictions are explicit without deleting prior memory versions or creating a separate graph runtime.".to_string(),
    }
}

fn record_matches_temporal_root(
    record: &MemoryRecord,
    root_entity_type: Option<&str>,
    root_entity_id: Option<&str>,
) -> bool {
    let Some(root_entity_id) = root_entity_id.map(str::trim).filter(|value| !value.is_empty()) else {
        return true;
    };
    let Some(root_entity_type) = root_entity_type.map(str::trim).filter(|value| !value.is_empty()) else {
        return true;
    };

    match normalize_graph_entity_type(root_entity_type) {
        "program" => record
            .program_id
            .as_deref()
            .map(|value| value.eq_ignore_ascii_case(root_entity_id))
            .unwrap_or(false),
        "campaign" => record
            .campaign_id
            .as_deref()
            .map(|value| value.eq_ignore_ascii_case(root_entity_id))
            .unwrap_or(false),
        "session" => record
            .session_id
            .as_deref()
            .map(|value| value.eq_ignore_ascii_case(root_entity_id))
            .unwrap_or(false)
            || record.conversation_id.eq_ignore_ascii_case(root_entity_id),
        "experiment" | "result" => record
            .result_refs
            .iter()
            .any(|value| temporal_ref_matches("result", value, root_entity_id)),
        "claim" => record
            .claim_refs
            .iter()
            .any(|value| temporal_ref_matches("claim", value, root_entity_id)),
        "manuscript" => record
            .tags
            .iter()
            .any(|tag| tag.eq_ignore_ascii_case("manuscript"))
            || record.text.to_ascii_lowercase().contains(&root_entity_id.to_ascii_lowercase()),
        _ => record
            .workstream_id
            .as_deref()
            .map(|value| value.eq_ignore_ascii_case(root_entity_id))
            .unwrap_or(false),
    }
}

fn temporal_ref_matches(prefix: &str, record_ref: &str, expected: &str) -> bool {
    let normalized_record_ref = record_ref.trim();
    let normalized_expected = expected.trim();
    if normalized_record_ref.eq_ignore_ascii_case(normalized_expected) {
        return true;
    }
    normalized_record_ref
        .to_ascii_lowercase()
        .starts_with(&format!("{}:", prefix))
        && normalized_record_ref
            .rsplit(':')
            .next()
            .map(|value| value.eq_ignore_ascii_case(normalized_expected))
            .unwrap_or(false)
}

fn retrieval_recommendation_for(
    collection: &RetrievalCollection,
    matrix: &EmbeddingBackendMatrix,
    reranking_profile: &RerankingProfile,
    cases: &[RetrievalBenchmarkCaseReport],
) -> RetrievalRecommendation {
    let average_relevance = average_f32(cases.iter().map(|case| case.relevance_proxy_score));
    let average_filter_correctness =
        average_f32(cases.iter().map(|case| case.payload_filter_correctness));
    let code_case_present = cases.iter().any(|case| case.case_kind.contains("code"));
    let multilingual_case_present = cases.iter().any(|case| case.case_kind.contains("multilingual"));
    let dense_backend_recommendation = if collection.dense_backend == "local-fallback-dense" {
        "promote-stronger-dense-backend".to_string()
    } else {
        "keep-current-dense-backend".to_string()
    };
    let reranking_recommendation = if average_relevance < 0.85 && code_case_present {
        "defer-but-pilot-reranking-for-code-and-manuscript-shortlists".to_string()
    } else {
        "keep-reranking-hook-disabled-for-now".to_string()
    };
    let general_backend = matrix
        .backends
        .iter()
        .find(|backend| backend.backend_kind == "api-general-purpose")
        .map(|backend| backend.backend_id.clone())
        .unwrap_or_else(|| "api-general-purpose-embedding".to_string());
    let code_backend = matrix
        .backends
        .iter()
        .find(|backend| backend.backend_kind == "api-code-oriented")
        .map(|backend| backend.backend_id.clone())
        .unwrap_or_else(|| "code-oriented-embedding".to_string());
    let sovereign_backend = matrix
        .backends
        .iter()
        .find(|backend| backend.backend_kind == "self-hosted-multilingual")
        .map(|backend| backend.backend_id.clone())
        .unwrap_or_else(|| "self-hosted-multilingual-embedding".to_string());

    RetrievalRecommendation {
        keep_qdrant: true,
        dense_backend_recommendation,
        reranking_recommendation,
        general_retrieval_path: format!(
            "Keep Qdrant as the canonical store and promote {} as the first stronger dense backend.",
            general_backend
        ),
        code_retrieval_path: format!(
            "Keep the same retrieval spine and pilot {} only for code-heavy subagent lanes.",
            code_backend
        ),
        multilingual_retrieval_path: if multilingual_case_present {
            format!(
                "Prepare {} as the bounded multilingual/self-hosted upgrade path once multilingual recall becomes first-class.",
                sovereign_backend
            )
        } else {
            format!(
                "Stage {} as the multilingual/self-hosted candidate even before multilingual queries become canonical.",
                sovereign_backend
            )
        },
        sovereign_retrieval_path: format!(
            "Prefer {} when sovereignty matters more than turnkey API convenience.",
            sovereign_backend
        ),
        bounded_upgrade_path: vec![
            "Keep Qdrant as the baseline vector store and preserve payload-aware hybrid retrieval.".to_string(),
            format!("Promote {} behind the existing dense backend seam.", general_backend),
            if code_case_present {
                format!(
                    "Pilot {} on code retrieval cases before widening it to general cognition.",
                    code_backend
                )
            } else {
                "Keep code-oriented embeddings as a later bounded pilot rather than the first promotion.".to_string()
            },
            format!(
                "Keep reranking at {} until dense quality, latency, and filter correctness are already stable.",
                reranking_profile.current_state
            ),
        ],
        note: format!(
            "Average relevance proxy {:.2} and filter correctness {:.2} justify keeping Qdrant while promoting a stronger dense backend before making reranking canonical.",
            average_relevance,
            average_filter_correctness
        ),
    }
}

fn lexical_overlap_ratio(query: &str, record: &MemoryRecord) -> f32 {
    let query_terms = token_set(query);
    if query_terms.is_empty() {
        return 0.0;
    }
    let haystack = format!(
        "{} {} {} {} {} {} {} {} {} {} {}",
        record.text,
        record.repo_path.as_deref().unwrap_or_default(),
        record.file_type.as_deref().unwrap_or_default(),
        record.tags.join(" "),
        record.workstream_id.as_deref().unwrap_or_default(),
        record.campaign_id.as_deref().unwrap_or_default(),
        record.program_id.as_deref().unwrap_or_default(),
        record.workspace_id.as_deref().unwrap_or_default(),
        record.session_id.as_deref().unwrap_or_default(),
        record.result_refs.join(" "),
        record.claim_refs.join(" ")
    );
    let haystack_terms = token_set(&haystack);
    let overlap = query_terms
        .iter()
        .filter(|term| haystack_terms.contains(term.as_str()))
        .count();
    overlap as f32 / query_terms.len() as f32
}

fn reranked_hit_is_context_usable(hit: &RerankedHit) -> bool {
    retrieval_hit_is_context_usable(&RetrievalHit {
        rank: hit.rank,
        point: hit.point.clone(),
        dense_score: hit.dense_score,
        sparse_score: hit.sparse_score,
        hybrid_score: hit.hybrid_score,
    })
}

fn token_set(text: &str) -> HashSet<String> {
    text.split(|ch: char| !ch.is_alphanumeric() && ch != '_' && ch != '-')
        .map(|token| token.trim().to_ascii_lowercase())
        .filter(|token| token.len() > 2)
        .collect()
}

fn hybrid_merge_records(
    collection_name: &str,
    dense_vector_name: Option<String>,
    dense_records: Vec<MemoryRecord>,
    sparse_records: Vec<MemoryRecord>,
    top_k: usize,
    dense_weight: f32,
    sparse_weight: f32,
) -> Vec<RetrievalHit> {
    #[derive(Clone)]
    struct Accumulator {
        payload: MemoryRecord,
        dense_score: Option<f32>,
        sparse_score: Option<f32>,
        hybrid_score: f32,
    }

    let mut merged: HashMap<String, Accumulator> = HashMap::new();
    for (rank, record) in dense_records.into_iter().enumerate() {
        let key = record.memory_id.clone();
        let dense_score = record.score.unwrap_or_default();
        let reciprocal = dense_weight / (60.0 + rank as f32 + 1.0);
        let entry = merged.entry(key).or_insert_with(|| Accumulator {
            payload: record.clone(),
            dense_score: None,
            sparse_score: None,
            hybrid_score: 0.0,
        });
        entry.payload = record;
        entry.dense_score = Some(dense_score);
        entry.hybrid_score += reciprocal;
    }

    for (rank, record) in sparse_records.into_iter().enumerate() {
        let key = record.memory_id.clone();
        let sparse_score = record.score.unwrap_or_default();
        let reciprocal = sparse_weight / (60.0 + rank as f32 + 1.0);
        let entry = merged.entry(key).or_insert_with(|| Accumulator {
            payload: record.clone(),
            dense_score: None,
            sparse_score: None,
            hybrid_score: 0.0,
        });
        if entry.payload.text.is_empty() {
            entry.payload = record.clone();
        }
        entry.sparse_score = Some(sparse_score);
        entry.hybrid_score += reciprocal;
    }

    let mut ranked = merged
        .into_values()
        .collect::<Vec<_>>();
    ranked.sort_by(|left, right| {
        right
            .hybrid_score
            .partial_cmp(&left.hybrid_score)
            .unwrap_or(std::cmp::Ordering::Equal)
            .then_with(|| right.payload.timestamp.cmp(&left.payload.timestamp))
    });
    ranked.truncate(top_k);

    ranked
        .into_iter()
        .enumerate()
        .map(|(rank, item)| RetrievalHit {
            rank: rank + 1,
            point: MemoryPoint {
                point_version: MEMORY_POINT_VERSION.to_string(),
                point_id: item.payload.memory_id.clone(),
                collection_name: collection_name.to_string(),
                dense_vector_name: dense_vector_name.clone(),
                payload: item.payload,
                note: "Retrieval hit materialized as a canonical memory point with explicit payload.".to_string(),
            },
            dense_score: item.dense_score,
            sparse_score: item.sparse_score,
            hybrid_score: item.hybrid_score,
        })
        .collect()
}

fn memory_highlight_from_retrieval_hit(hit: &RetrievalHit) -> MemoryResultHighlight {
    let record = &hit.point.payload;
    MemoryResultHighlight {
        memory_id: Some(record.memory_id.clone()),
        source: record.source.clone(),
        date: Some(record.timestamp),
        snippet: snippet_for_text(&record.text),
        run_id: None,
        session_id: record
            .session_id
            .clone()
            .or_else(|| Some(record.conversation_id.clone())),
        relevance: hit.hybrid_score,
        conversation_id: Some(record.conversation_id.clone()),
        turn_index: Some(record.turn_index),
        role: Some(record.role.clone()),
        tags: record.tags.clone(),
        domain: record.domain.clone(),
        physio_snapshot: record.physio_snapshot.clone(),
        experiment_flags: record.experiment_flags.clone(),
        workstream_id: record.workstream_id.clone(),
        campaign_id: record.campaign_id.clone(),
        program_id: record.program_id.clone(),
        workspace_id: record.workspace_id.clone(),
        beagle_session_id: record.session_id.clone(),
        result_refs: record.result_refs.clone(),
        claim_refs: record.claim_refs.clone(),
    }
}

fn retrieval_weights_for_task_profile(profile: &ContextBudgetProfile) -> (f32, f32) {
    match profile.retrieval_query_type.as_str() {
        "code" => (0.75, 0.25),
        "sovereign" => (0.70, 0.30),
        _ => (0.65, 0.35),
    }
}

fn compiled_context_from_runtime(
    request: &CompiledContextRequest,
    profile: &ContextBudgetProfile,
    reranked: &RerankedResult,
    graphrag: &GraphRagResult,
    temporal: &TemporalQueryResult,
) -> CompiledContextPacket {
    let classified_hits = reranked
        .hits
        .iter()
        .map(|hit| (classify_memory_type(&hit.point.payload), hit))
        .collect::<Vec<_>>();
    let mut top_memory_ids = Vec::new();
    let mut source_slices = Vec::new();

    for allocation in &profile.allocations {
        if allocation.source_kind == "graphrag" {
            let support_ids = graphrag
                .support_memory_ids
                .iter()
                .take(allocation.max_items)
                .cloned()
                .collect::<Vec<_>>();
            extend_unique_memory_ids(&mut top_memory_ids, support_ids.iter().cloned(), profile.max_context_items);
            source_slices.push(CompiledContextSourceSlice {
                source_kind: allocation.source_kind.clone(),
                budgeted_items: allocation.max_items,
                selected_count: support_ids.len(),
                support_ids,
                summary: format!(
                    "graph scope={} nodes={} edges={} types={}",
                    graphrag.query_mode,
                    graphrag.node_count,
                    graphrag.edge_count,
                    graphrag
                        .nodes
                        .iter()
                        .map(|node| node.node_type.clone())
                        .take(4)
                        .collect::<Vec<_>>()
                        .join(", ")
                ),
            });
            continue;
        }
        if allocation.source_kind == "temporal" {
            let support_ids = temporal_support_memory_ids(temporal)
                .into_iter()
                .take(allocation.max_items)
                .collect::<Vec<_>>();
            extend_unique_memory_ids(
                &mut top_memory_ids,
                support_ids.iter().cloned(),
                profile.max_context_items,
            );
            source_slices.push(CompiledContextSourceSlice {
                source_kind: allocation.source_kind.clone(),
                budgeted_items: allocation.max_items,
                selected_count: support_ids.len(),
                support_ids,
                summary: format!(
                    "temporal truth_view={} tracks={} contradictions={} current={} historical={}",
                    temporal.truth_view,
                    temporal.track_count,
                    temporal.contradiction_count,
                    temporal.current_truth_count,
                    temporal.historical_truth_count
                ),
            });
            continue;
        }

        let selected_hits = classified_hits
            .iter()
            .filter(|(memory_type, _)| memory_type == &allocation.source_kind)
            .map(|(_, hit)| *hit)
            .take(allocation.max_items)
            .collect::<Vec<_>>();
        let support_ids = selected_hits
            .iter()
            .map(|hit| hit.point.payload.memory_id.clone())
            .collect::<Vec<_>>();
        extend_unique_memory_ids(&mut top_memory_ids, support_ids.iter().cloned(), profile.max_context_items);
        source_slices.push(CompiledContextSourceSlice {
            source_kind: allocation.source_kind.clone(),
            budgeted_items: allocation.max_items,
            selected_count: selected_hits.len(),
            support_ids,
            summary: selected_hits
                .iter()
                .map(|hit| {
                    format!(
                        "{}:{}",
                        hit.point.payload.memory_id,
                        snippet_for_text(&hit.point.payload.text)
                    )
                })
                .collect::<Vec<_>>()
                .join(" | "),
        });
    }

    CompiledContextPacket {
        packet_version: crate::compiler::COMPILED_CONTEXT_PACKET_VERSION.to_string(),
        compiler_id: crate::compiler::memory_compiler_contract().compiler_id,
        task_profile: normalize_task_profile(&request.task_profile),
        tool_id: request.tool_id.clone(),
        budget_profile: profile.clone(),
        retrieval_query_type: reranked.query_type.clone(),
        dense_backend: reranked.dense_backend.clone(),
        sparse_backend: reranked.sparse_backend.clone(),
        graphrag_query_mode: graphrag.query_mode.clone(),
        graphrag_query_mode_reason: graphrag.query_mode_reason.clone(),
        workstream_id: request
            .workstream_id
            .clone()
            .or_else(|| graphrag.workstream_id.clone()),
        campaign_id: request
            .campaign_id
            .clone()
            .or_else(|| graphrag.campaign_id.clone()),
        program_id: request
            .program_id
            .clone()
            .or_else(|| graphrag.program_id.clone()),
        workspace_id: request.workspace_id.clone(),
        session_id: request
            .session_id
            .clone()
            .or_else(|| graphrag.session_id.clone()),
        applied_filters: reranked.applied_filters.clone(),
        selected_memory_tiers: profile.selected_memory_tiers.clone(),
        temporal_truth_view: temporal.truth_view.clone(),
        temporal_subject_refs: temporal.subject_refs.clone(),
        temporal_current_memory_ids: temporal.top_current_memory_ids.clone(),
        temporal_historical_memory_ids: temporal.top_historical_memory_ids.clone(),
        temporal_track_count: temporal.track_count,
        temporal_contradiction_count: temporal.contradiction_count,
        temporal_preview: format!(
            "truth_view={} tracks={} contradictions={} current={} historical={}",
            temporal.truth_view,
            temporal.track_count,
            temporal.contradiction_count,
            temporal.current_truth_count,
            temporal.historical_truth_count
        ),
        top_memory_ids,
        compiled_context_text: render_compiled_context_text(profile, reranked, graphrag, &source_slices),
        source_slices,
        note: format!(
            "B23.5 compiled a bounded {} context packet from reranked retrieval, temporal truth, and GraphRAG without adding a parallel runtime.",
            profile.task_profile
        ),
    }
}

fn render_compiled_context_text(
    profile: &ContextBudgetProfile,
    reranked: &RerankedResult,
    graphrag: &GraphRagResult,
    source_slices: &[CompiledContextSourceSlice],
) -> String {
    let mut lines = vec![
        format!("task_profile: {}", profile.task_profile),
        format!("retrieval_query_type: {}", reranked.query_type),
        format!("dense_backend: {}", reranked.dense_backend),
        format!("sparse_backend: {}", reranked.sparse_backend),
        format!("graphrag_query_mode: {}", graphrag.query_mode),
        format!("temporal_truth_view: {}", profile.temporal_truth_view),
        format!("selected_memory_tiers: {}", profile.selected_memory_tiers.join(", ")),
    ];

    for slice in source_slices {
        lines.push(format!(
            "[{}] selected={}/{} {}",
            slice.source_kind,
            slice.selected_count,
            slice.budgeted_items,
            slice.summary
        ));
    }

    lines.join("\n")
}

fn temporal_support_memory_ids(temporal: &TemporalQueryResult) -> Vec<String> {
    let mut ids = Vec::new();
    extend_unique_memory_ids(&mut ids, temporal.top_current_memory_ids.clone(), usize::MAX);
    if temporal.truth_view != "current" {
        extend_unique_memory_ids(
            &mut ids,
            temporal.top_historical_memory_ids.clone(),
            usize::MAX,
        );
    }
    ids
}

fn compiler_eval_request_with_task_profile(
    case: &ContextEvalCase,
    task_profile: &str,
) -> CompiledContextRequest {
    let mut request = case.request.clone();
    request.task_profile = task_profile.to_string();
    request
}

fn normalize_graphrag_query_mode_hint(mode: &str) -> String {
    match mode.trim().to_ascii_lowercase().as_str() {
        "local" => "local".to_string(),
        "drift" => "drift".to_string(),
        _ => "global".to_string(),
    }
}

fn expected_query_type_for_task_profile(task_profile: &str) -> String {
    match normalize_task_profile(task_profile).as_str() {
        "implementation" | "interactive-editing" => "code".to_string(),
        "sovereign" => "sovereign".to_string(),
        _ => "general".to_string(),
    }
}

fn compiled_context_relevance_proxy(
    compiled: &CompiledContextPacket,
    expected_memory_ids: &[String],
) -> f32 {
    if expected_memory_ids.is_empty() {
        return if compiled.top_memory_ids.is_empty() { 0.0 } else { 1.0 };
    }

    let mut score = 0.0_f32;
    for (index, memory_id) in compiled.top_memory_ids.iter().enumerate() {
        if expected_memory_ids.iter().any(|expected| expected == memory_id) {
            score += 1.0 / (index as f32 + 1.0);
        }
    }

    score.min(1.0)
}

fn compiled_context_task_fit_score(
    compiled: &CompiledContextPacket,
    case: &ContextEvalCase,
    truth_view_appropriate: bool,
    graphrag_mode_appropriate: bool,
    route_appropriate: bool,
) -> f32 {
    let preferred_tiers = if case.preferred_memory_tiers.is_empty() {
        compiled.selected_memory_tiers.clone()
    } else {
        case.preferred_memory_tiers.clone()
    };
    let tier_overlap = tier_overlap_score(&compiled.selected_memory_tiers, &preferred_tiers);

    average_f32(
        [
            bool_score(route_appropriate),
            bool_score(truth_view_appropriate),
            bool_score(graphrag_mode_appropriate),
            tier_overlap,
        ]
        .into_iter(),
    )
}

fn compiled_context_usefulness_score(
    compiled: &CompiledContextPacket,
    relevance_proxy_score: f32,
    top_k_stable: bool,
) -> f32 {
    let source_fill_score = average_f32(compiled.source_slices.iter().map(|slice| {
        if slice.budgeted_items == 0 {
            0.0
        } else {
            (slice.selected_count as f32 / slice.budgeted_items as f32).min(1.0)
        }
    }));
    let source_diversity_score = if compiled.source_slices.is_empty() {
        0.0
    } else {
        compiled
            .source_slices
            .iter()
            .filter(|slice| slice.selected_count > 0)
            .count() as f32
            / compiled.source_slices.len() as f32
    };

    average_f32(
        [
            relevance_proxy_score,
            source_fill_score,
            source_diversity_score,
            bool_score(top_k_stable),
        ]
        .into_iter(),
    )
}

fn compiled_context_budget_efficiency_score(
    compiled: &CompiledContextPacket,
    profile: &ContextBudgetProfile,
) -> f32 {
    if profile.max_context_items == 0 {
        0.0
    } else {
        (compiled.top_memory_ids.len() as f32 / profile.max_context_items as f32).min(1.0)
    }
}

fn compiled_context_overall_score(
    relevance_proxy_score: f32,
    task_fit_score: f32,
    context_usefulness_score: f32,
    budget_efficiency_score: f32,
) -> f32 {
    (relevance_proxy_score * 0.35)
        + (task_fit_score * 0.30)
        + (context_usefulness_score * 0.20)
        + (budget_efficiency_score * 0.15)
}

fn compiler_eval_variant_note(
    case: &ContextEvalCase,
    compiled: &CompiledContextPacket,
    truth_view_appropriate: bool,
    graphrag_mode_appropriate: bool,
    route_appropriate: bool,
) -> String {
    format!(
        "task={} route={} truth_match={} graphrag_match={} dense={} top_memory_ids={}",
        case.task_profile,
        route_appropriate,
        truth_view_appropriate,
        graphrag_mode_appropriate,
        compiled.dense_backend,
        compiled.top_memory_ids.join(",")
    )
}

fn compiler_eval_recommendation_for(
    task_profile: &str,
    winner: &CompilerPolicyVariantReport,
) -> String {
    format!(
        "Prefer {} for {} because it produced the best bounded overall score with {} truth and {} GraphRAG.",
        winner.budget_profile_id,
        normalize_task_profile(task_profile),
        winner.temporal_truth_view,
        winner.graphrag_query_mode
    )
}

fn compiler_policy_recommended_when(
    task_profile: &str,
    winner: &CompilerPolicyVariantReport,
) -> String {
    format!(
        "Use {} for {} tasks when retrieval={}, graphrag={}, and truth_view={} fit the current work mode best.",
        winner.budget_profile_id,
        normalize_task_profile(task_profile),
        winner.retrieval_query_type,
        winner.graphrag_query_mode,
        winner.temporal_truth_view
    )
}

fn tier_overlap_score(selected: &[String], preferred: &[String]) -> f32 {
    if preferred.is_empty() {
        return 1.0;
    }

    let hits = preferred
        .iter()
        .filter(|tier| selected.iter().any(|selected_tier| selected_tier == *tier))
        .count();
    hits as f32 / preferred.len() as f32
}

fn bool_score(value: bool) -> f32 {
    if value {
        1.0
    } else {
        0.0
    }
}

fn extend_unique_memory_ids<I>(target: &mut Vec<String>, values: I, limit: usize)
where
    I: IntoIterator<Item = String>,
{
    for value in values {
        let normalized = value.trim();
        if normalized.is_empty() || target.iter().any(|existing| existing == normalized) {
            continue;
        }
        target.push(normalized.to_string());
        if target.len() >= limit {
            break;
        }
    }
}

/// Mock MemoryEngine for testing
#[cfg(test)]
pub struct MockMemoryEngine {
    pub ingested_sessions: Vec<ChatSession>,
    pub query_results: Vec<MemoryResult>,
}

#[cfg(test)]
impl MockMemoryEngine {
    pub fn new() -> Self {
        Self {
            ingested_sessions: Vec::new(),
            query_results: Vec::new(),
        }
    }

    pub async fn ingest_chat(&mut self, session: ChatSession) -> Result<IngestStats> {
        self.ingested_sessions.push(session.clone());
        Ok(IngestStats {
            num_turns: session.turns.len(),
            num_chunks: session.turns.len(),
            session_id: session.session_id,
            stored: !session.turns.is_empty(),
            memory_id: Some("mock-memory-id".to_string()),
            searchable: true,
            physio_attached: false,
            experiment_flags_attached: false,
        })
    }

    pub async fn query(&self, _q: MemoryQuery) -> Result<MemoryResult> {
        // Return first mock result or empty
        self.query_results
            .first()
            .cloned()
            .ok_or_else(|| anyhow::anyhow!("No mock results configured"))
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::env;
    use std::path::Path;

    fn local_test_config(root: &Path) -> MemoryEngineConfig {
        MemoryEngineConfig {
            qdrant_url: None,
            embedding_url: None,
            embedding_model: "voyage-4-large".to_string(),
            dense_backend_id: "voyage-4-large".to_string(),
            dense_backend_provider: "voyage".to_string(),
            dense_backend_api_key: None,
            code_backend_id: "voyage-code-3".to_string(),
            sovereign_backend_id: "bge-m3".to_string(),
            sovereign_embedding_url: None,
            sovereign_embedding_model: "BAAI/bge-m3".to_string(),
            sovereign_embedding_api_key: None,
            reranking_url: None,
            reranking_model: "rerank-2.5".to_string(),
            reranking_api_key: None,
            sovereign_reranking_url: None,
            sovereign_reranking_model: "BAAI/bge-reranker-v2-m3".to_string(),
            sovereign_reranking_api_key: None,
            qdrant_collection: "beagle_memory_chat".to_string(),
            local_index_path: root.join("memory").join("chat-memory.jsonl"),
        }
    }

    fn promoted_test_config(root: &Path) -> MemoryEngineConfig {
        MemoryEngineConfig {
            qdrant_url: None,
            embedding_url: Some("https://api.voyageai.com/v1".to_string()),
            embedding_model: "voyage-4-large".to_string(),
            dense_backend_id: "voyage-4-large".to_string(),
            dense_backend_provider: "voyage".to_string(),
            dense_backend_api_key: Some("test-key".to_string()),
            code_backend_id: "voyage-code-3".to_string(),
            sovereign_backend_id: "bge-m3".to_string(),
            sovereign_embedding_url: Some("http://sovereign.local/v1".to_string()),
            sovereign_embedding_model: "BAAI/bge-m3".to_string(),
            sovereign_embedding_api_key: None,
            reranking_url: Some("https://api.voyageai.com/v1".to_string()),
            reranking_model: "rerank-2.5".to_string(),
            reranking_api_key: Some("test-key".to_string()),
            sovereign_reranking_url: Some("http://sovereign-reranker.local".to_string()),
            sovereign_reranking_model: "BAAI/bge-reranker-v2-m3".to_string(),
            sovereign_reranking_api_key: None,
            qdrant_collection: "beagle_memory_chat".to_string(),
            local_index_path: root.join("memory").join("chat-memory.jsonl"),
        }
    }

    #[test]
    fn stable_memory_id_is_deterministic() {
        let left = stable_memory_id("chatgpt", "conv-1", 3, "assistant");
        let right = stable_memory_id("chatgpt", "conv-1", 3, "assistant");
        assert_eq!(left, right);
    }

    #[tokio::test]
    #[ignore = "set BEAGLE_MEMORY_TEST_QDRANT_URL to a running Qdrant HTTP base URL"]
    async fn qdrant_health_probe_integration() {
        let url = std::env::var("BEAGLE_MEMORY_TEST_QDRANT_URL")
            .expect("BEAGLE_MEMORY_TEST_QDRANT_URL must be set for this test");
        let root = std::env::temp_dir().join("beagle-memory-qdrant-health-test");
        let mut cfg = local_test_config(&root);
        cfg.qdrant_url = Some(url);
        let engine = MemoryEngine::new(None, cfg);
        let h = engine.qdrant_health().await;
        assert!(h.configured);
        assert!(
            matches!(
                h.status.as_str(),
                "up" | "collection_missing" | "qdrant_error" | "unreachable"
            ),
            "unexpected status: {}",
            h.status
        );
    }

    #[test]
    fn record_matches_domain_and_tags() {
        let record = MemoryRecord {
            memory_id: "m1".to_string(),
            source: "chatgpt".to_string(),
            conversation_id: "conv".to_string(),
            workstream_id: Some("beagle-darwin-hpc-governance".to_string()),
            campaign_id: Some("expedition-002-hrv-aware".to_string()),
            program_id: Some("beagle-physio-symbolic-exocortex".to_string()),
            workspace_id: Some("beagle-cluster-pilot".to_string()),
            session_id: Some("ws-cluster-workspace-habitat".to_string()),
            turn_index: 0,
            role: "user".to_string(),
            text: "hello".to_string(),
            tags: vec!["darwin".to_string(), "memory".to_string()],
            domain: Some("beagle-engine".to_string()),
            repo_path: Some("beagle/crates/beagle-memory/src/engine.rs".to_string()),
            file_type: Some("rust".to_string()),
            timestamp: Utc::now(),
            physio_snapshot: None,
            experiment_flags: None,
            physio_snapshot_ref: Some("physio:latest".to_string()),
            result_refs: vec!["result:1".to_string()],
            claim_refs: vec!["claim:1".to_string()],
            provider: None,
            model: None,
            score: None,
        };

        assert!(record_matches(&record, Some("beagle-engine"), &["memory".to_string()]));
        assert!(!record_matches(&record, Some("pbpk"), &["memory".to_string()]));
        assert!(!record_matches(&record, Some("beagle-engine"), &["missing".to_string()]));
    }

    #[tokio::test]
    async fn local_index_persists_and_finds_record() {
        let root = env::temp_dir().join(format!("beagle-memory-test-{}", Uuid::new_v4()));
        let path = root.join("memory").join("chat-memory.jsonl");
        let index = LocalMemoryIndex::new(path.clone());
        let record = MemoryRecord {
            memory_id: "m1".to_string(),
            source: "chatgpt".to_string(),
            conversation_id: "conv-1".to_string(),
            workstream_id: Some("beagle-darwin-hpc-governance".to_string()),
            campaign_id: Some("expedition-002-hrv-aware".to_string()),
            program_id: Some("beagle-physio-symbolic-exocortex".to_string()),
            workspace_id: Some("beagle-cluster-pilot".to_string()),
            session_id: Some("ws-cluster-workspace-habitat".to_string()),
            turn_index: 0,
            role: "assistant".to_string(),
            text: "repo native memory spine".to_string(),
            tags: vec!["memory-spine".to_string()],
            domain: Some("beagle-engine".to_string()),
            repo_path: Some("beagle/crates/beagle-memory/src/lib.rs".to_string()),
            file_type: Some("rust".to_string()),
            timestamp: Utc::now(),
            physio_snapshot: Some(PhysioSnapshot {
                hr: Some(63.0),
                hrv_level: Some("balanced".to_string()),
                spo2: Some(98.0),
                timestamp: Some(Utc::now()),
                source: Some("observer_context".to_string()),
            }),
            experiment_flags: Some(ExperimentFlags {
                hrv_aware: Some(true),
                serendipity_enabled: Some(false),
                triad_enabled: Some(true),
                provider: Some("chatgpt".to_string()),
                model: Some("gpt-5".to_string()),
            }),
            physio_snapshot_ref: Some("physio:observer".to_string()),
            result_refs: vec!["result:memory-spine".to_string()],
            claim_refs: vec!["claim:memory-spine".to_string()],
            provider: Some("chatgpt".to_string()),
            model: Some("gpt-5".to_string()),
            score: None,
        };

        index.upsert_record(&record).await.unwrap();
        let reloaded = LocalMemoryIndex::new(path);
        let results = reloaded.search_records("repo native memory", 5).await.unwrap();

        assert_eq!(results.len(), 1);
        assert_eq!(results[0].memory_id, "m1");
        assert_eq!(results[0].domain.as_deref(), Some("beagle-engine"));
        assert_eq!(results[0].physio_snapshot.as_ref().and_then(|p| p.hr), Some(63.0));

        let _ = fs::remove_dir_all(root);
    }

    #[tokio::test]
    async fn hybrid_retrieval_respects_payload_filters_and_keeps_payload() {
        let root = env::temp_dir().join(format!("beagle-memory-hybrid-{}", Uuid::new_v4()));
        let config = local_test_config(root.as_path());
        let engine = MemoryEngine::new(None, config);

        engine
            .ingest_chat(ChatSession {
                source: "codex".to_string(),
                session_id: "conv-hybrid-1".to_string(),
                turns: vec![ChatTurn {
                    role: "assistant".to_string(),
                    content: "B221 hybrid retrieval beagle-darwin-hpc-governance agourakis82/beagle main experiment context".to_string(),
                    timestamp: Some(Utc::now()),
                    model: Some("gpt-5.4".to_string()),
                    turn_index: Some(0),
                }],
                tags: vec!["hybrid-retrieval-smoke".to_string()],
                metadata: json!({
                    "domain": "beagle-engine",
                    "repo_path": "agourakis82/beagle/crates/beagle-memory/src/engine.rs",
                    "file_type": "rust",
                    "workstream_id": "beagle-darwin-hpc-governance",
                    "campaign_id": "expedition-002-hrv-aware",
                    "program_id": "beagle-physio-symbolic-exocortex",
                    "workspace_id": "beagle-cluster-pilot",
                    "session_id": "ws-cluster-workspace-habitat",
                    "result_refs": ["result:b221-core"],
                    "claim_refs": ["claim:b221-memory"],
                    "physio_snapshot_ref": "physio:b221",
                }),
            })
            .await
            .unwrap();

        engine
            .ingest_chat(ChatSession {
                source: "cursor".to_string(),
                session_id: "conv-hybrid-2".to_string(),
                turns: vec![ChatTurn {
                    role: "assistant".to_string(),
                    content: "B221 hybrid retrieval unrelated other-workstream experiment context".to_string(),
                    timestamp: Some(Utc::now()),
                    model: Some("gpt-5.4".to_string()),
                    turn_index: Some(0),
                }],
                tags: vec!["hybrid-retrieval-smoke".to_string()],
                metadata: json!({
                    "domain": "beagle-engine",
                    "repo_path": "agourakis82/beagle/scripts/other.sh",
                    "file_type": "shell",
                    "workstream_id": "other-workstream",
                    "campaign_id": "other-campaign",
                    "program_id": "other-program",
                    "workspace_id": "other-workspace",
                    "session_id": "other-session",
                }),
            })
            .await
            .unwrap();

        let result = engine
            .hybrid_retrieve(RetrievalQuery {
                query_version: crate::retrieval::RETRIEVAL_QUERY_VERSION.to_string(),
                query_text: "B221 hybrid retrieval beagle-darwin-hpc-governance agourakis82/beagle main".to_string(),
                top_k: 3,
                dense_enabled: true,
                sparse_enabled: true,
                dense_weight: 0.65,
                sparse_weight: 0.35,
                filters: RetrievalFilters {
                    workstream_id: Some("beagle-darwin-hpc-governance".to_string()),
                    tags: vec!["hybrid-retrieval-smoke".to_string()],
                    ..RetrievalFilters::default()
                },
                rerank_hint: None,
            })
            .await
            .unwrap();

        assert_eq!(result.hits.len(), 1);
        assert!(result.dense_hit_count >= 1);
        assert!(result.sparse_hit_count >= 1);
        assert_eq!(
            result.hits[0].point.payload.workstream_id.as_deref(),
            Some("beagle-darwin-hpc-governance")
        );
        assert_eq!(
            result.hits[0].point.payload.campaign_id.as_deref(),
            Some("expedition-002-hrv-aware")
        );
        assert_eq!(
            result.hits[0].point.payload.result_refs,
            vec!["result:b221-core".to_string()]
        );
        assert_eq!(
            result.hits[0].point.payload.claim_refs,
            vec!["claim:b221-memory".to_string()]
        );

        let _ = fs::remove_dir_all(root);
    }

    #[test]
    fn embedding_backend_matrix_exposes_current_and_candidate_backends() {
        let root = env::temp_dir().join(format!("beagle-memory-matrix-{}", Uuid::new_v4()));
        let config = local_test_config(root.as_path());
        let engine = MemoryEngine::new(None, config);
        let matrix = engine.embedding_backend_matrix();
        let reranking = engine.reranking_profile();
        let contract = engine.embedding_backend_contract();

        assert_eq!(matrix.current_dense_backend, "local-fallback-dense");
        assert!(matrix.backends.iter().any(|item| item.backend_id == "voyage-4-large"));
        assert!(matrix.backends.iter().any(|item| item.backend_id == "voyage-code-3"));
        assert!(matrix.backends.iter().any(|item| item.backend_id == "bge-m3"));
        assert_eq!(reranking.current_state, "pilot-live-bounded");
        assert_eq!(reranking.current_mode, "top-k-reranking-pilot");
        assert_eq!(reranking.bounded_top_k, 5);
        assert_eq!(contract.promoted_dense_backend, "voyage-4-large");
        assert_eq!(contract.runtime_state, "endpoint-missing-fallback");
    }

    #[test]
    fn embedding_backend_contract_promotes_voyage_dense_backend() {
        let root = env::temp_dir().join(format!("beagle-memory-contract-{}", Uuid::new_v4()));
        let config = promoted_test_config(root.as_path());
        let engine = MemoryEngine::new(None, config);
        let contract = engine.embedding_backend_contract();
        let collection = engine.retrieval_collection();

        assert_eq!(contract.promoted_dense_backend, "voyage-4-large");
        assert_eq!(contract.active_dense_backend, "voyage-4-large");
        assert_eq!(contract.runtime_state, "promoted-active");
        assert_eq!(collection.dense_backend, "voyage-4-large");
    }

    #[tokio::test]
    async fn retrieval_benchmark_produces_bounded_upgrade_recommendation() {
        let root = env::temp_dir().join(format!("beagle-memory-benchmark-{}", Uuid::new_v4()));
        let config = local_test_config(root.as_path());
        let engine = MemoryEngine::new(None, config);

        let baseline = engine
            .ingest_chat(ChatSession {
                source: "codex".to_string(),
                session_id: "conv-benchmark-1".to_string(),
                turns: vec![ChatTurn {
                    role: "assistant".to_string(),
                    content: "B222 retrieval benchmark harness canonical prose memory point for beagle-darwin-hpc-governance.".to_string(),
                    timestamp: Some(Utc::now()),
                    model: Some("gpt-5.4".to_string()),
                    turn_index: Some(0),
                }],
                tags: vec!["retrieval-benchmark".to_string(), "b222".to_string()],
                metadata: json!({
                    "domain": "beagle-engine",
                    "repo_path": "agourakis82/beagle/docs/b222.md",
                    "file_type": "markdown",
                    "workstream_id": "beagle-darwin-hpc-governance",
                    "campaign_id": "expedition-002-hrv-aware",
                    "program_id": "beagle-physio-symbolic-exocortex",
                    "workspace_id": "beagle-cluster-pilot",
                    "session_id": "ws-cluster-workspace-habitat",
                    "result_refs": ["result:b222-prose"],
                    "claim_refs": ["claim:b222-prose"],
                }),
            })
            .await
            .unwrap();

        let code = engine
            .ingest_chat(ChatSession {
                source: "codex".to_string(),
                session_id: "conv-benchmark-2".to_string(),
                turns: vec![ChatTurn {
                    role: "assistant".to_string(),
                    content: "fn benchmark_retrieval(query: RetrievalQuery) -> RetrievalBenchmarkReport { hybrid_retrieve(query) }".to_string(),
                    timestamp: Some(Utc::now()),
                    model: Some("gpt-5.4".to_string()),
                    turn_index: Some(0),
                }],
                tags: vec!["retrieval-benchmark".to_string(), "b222".to_string(), "code".to_string()],
                metadata: json!({
                    "domain": "beagle-engine",
                    "repo_path": "agourakis82/beagle/crates/beagle-memory/src/engine.rs",
                    "file_type": "rust",
                    "workstream_id": "beagle-darwin-hpc-governance",
                    "campaign_id": "expedition-002-hrv-aware",
                    "program_id": "beagle-physio-symbolic-exocortex",
                    "workspace_id": "beagle-cluster-pilot",
                    "session_id": "ws-cluster-workspace-habitat",
                    "result_refs": ["result:b222-code"],
                    "claim_refs": ["claim:b222-code"],
                }),
            })
            .await
            .unwrap();

        let report = engine
            .benchmark_retrieval(RetrievalBenchmarkRequest {
                benchmark_version: RETRIEVAL_BENCHMARK_VERSION.to_string(),
                top_k_stability_runs: 2,
                reranking_profile_id: None,
                cases: vec![
                    RetrievalBenchmarkCase {
                        case_id: "baseline-prose".to_string(),
                        case_kind: "prose".to_string(),
                        description: Some("Baseline prose retrieval".to_string()),
                        query: RetrievalQuery {
                            query_version: crate::retrieval::RETRIEVAL_QUERY_VERSION.to_string(),
                            query_text: "B222 retrieval benchmark canonical prose beagle".to_string(),
                            top_k: 3,
                            dense_enabled: true,
                            sparse_enabled: true,
                            dense_weight: 0.65,
                            sparse_weight: 0.35,
                            filters: RetrievalFilters {
                                domain: Some("beagle-engine".to_string()),
                                tags: vec!["retrieval-benchmark".to_string(), "b222".to_string()],
                                ..RetrievalFilters::default()
                            },
                            rerank_hint: None,
                        },
                        expected_memory_ids: vec![baseline.memory_id.unwrap()],
                    },
                    RetrievalBenchmarkCase {
                        case_id: "code-lane".to_string(),
                        case_kind: "code".to_string(),
                        description: Some("Code retrieval behavior".to_string()),
                        query: RetrievalQuery {
                            query_version: crate::retrieval::RETRIEVAL_QUERY_VERSION.to_string(),
                            query_text: "fn benchmark_retrieval hybrid_retrieve RetrievalBenchmarkReport".to_string(),
                            top_k: 3,
                            dense_enabled: true,
                            sparse_enabled: true,
                            dense_weight: 0.65,
                            sparse_weight: 0.35,
                            filters: RetrievalFilters {
                                domain: Some("beagle-engine".to_string()),
                                tags: vec!["retrieval-benchmark".to_string(), "b222".to_string(), "code".to_string()],
                                ..RetrievalFilters::default()
                            },
                            rerank_hint: Some("code-benchmark".to_string()),
                        },
                        expected_memory_ids: vec![code.memory_id.unwrap()],
                    },
                ],
            })
            .await
            .unwrap();

        assert_eq!(report.summary.case_count, 2);
        assert!(report.recommendation.keep_qdrant);
        assert_eq!(
            report.recommendation.dense_backend_recommendation,
            "promote-stronger-dense-backend"
        );
        assert!(report
            .recommendation
            .general_retrieval_path
            .contains("voyage-4-large"));
        assert!(report
            .recommendation
            .bounded_upgrade_path
            .iter()
            .any(|step| step.contains("Qdrant")));

        let _ = fs::remove_dir_all(root);
    }

    #[test]
    fn code_retrieval_backend_profile_promotes_voyage_code_candidate() {
        let root = env::temp_dir().join(format!("beagle-memory-code-{}", Uuid::new_v4()));
        let config = promoted_test_config(root.as_path());
        let engine = MemoryEngine::new(None, config);
        let profile = engine.code_retrieval_backend_profile();

        assert_eq!(profile.backend_id, "voyage-code-3");
        assert_eq!(profile.model, "voyage-code-3");
        assert_eq!(profile.runtime_state, "pilot-active");
        assert_eq!(engine.active_code_dense_backend_id(), "voyage-code-3");
    }

    #[test]
    fn sovereign_retrieval_backend_profile_promotes_bge_m3_candidate() {
        let root = env::temp_dir().join(format!("beagle-memory-sovereign-{}", Uuid::new_v4()));
        let config = promoted_test_config(root.as_path());
        let engine = MemoryEngine::new(None, config);
        let profile = engine.sovereign_retrieval_backend_profile();

        assert_eq!(profile.backend_id, "bge-m3");
        assert_eq!(profile.model, "BAAI/bge-m3");
        assert_eq!(profile.runtime_state, "sovereign-active");
        assert_eq!(engine.active_sovereign_dense_backend_id(), "bge-m3");
    }

    #[test]
    fn retrieval_router_classifies_general_code_and_sovereign_queries() {
        let root = env::temp_dir().join(format!("beagle-memory-router-{}", Uuid::new_v4()));
        let config = local_test_config(root.as_path());
        let engine = MemoryEngine::new(None, config);

        let general = engine.classify_retrieval_query(&RoutedRetrievalQuery {
            query_version: crate::retrieval::ROUTED_RETRIEVAL_QUERY_VERSION.to_string(),
            query_text: "retrieve workstream memory for the active campaign".to_string(),
            top_k: 3,
            dense_enabled: true,
            sparse_enabled: true,
            dense_weight: 0.65,
            sparse_weight: 0.35,
            filters: RetrievalFilters::default(),
            query_type_hint: None,
            compare_against_general: false,
            rerank_hint: None,
        });
        assert_eq!(general.selected_query_type, "general");

        let code = engine.classify_retrieval_query(&RoutedRetrievalQuery {
            query_version: crate::retrieval::ROUTED_RETRIEVAL_QUERY_VERSION.to_string(),
            query_text: "find workspace_attach config in the repo".to_string(),
            top_k: 3,
            dense_enabled: true,
            sparse_enabled: true,
            dense_weight: 0.75,
            sparse_weight: 0.25,
            filters: RetrievalFilters {
                repo_path: Some("beagle/crates/beagle-darwin/src/workspace_attach.rs".to_string()),
                file_type: Some("rust".to_string()),
                ..RetrievalFilters::default()
            },
            query_type_hint: None,
            compare_against_general: false,
            rerank_hint: None,
        });
        assert_eq!(code.selected_query_type, "code");

        let sovereign = engine.classify_retrieval_query(&RoutedRetrievalQuery {
            query_version: crate::retrieval::ROUTED_RETRIEVAL_QUERY_VERSION.to_string(),
            query_text: "consulta multilingue sobre privacidade e memoria soberana".to_string(),
            top_k: 3,
            dense_enabled: true,
            sparse_enabled: true,
            dense_weight: 0.7,
            sparse_weight: 0.3,
            filters: RetrievalFilters::default(),
            query_type_hint: None,
            compare_against_general: false,
            rerank_hint: None,
        });
        assert_eq!(sovereign.selected_query_type, "sovereign");
    }

    #[tokio::test]
    async fn routed_retrieval_uses_selected_backend_and_preserves_filters() {
        let root = env::temp_dir().join(format!("beagle-memory-routed-{}", Uuid::new_v4()));
        let config = local_test_config(root.as_path());
        let engine = MemoryEngine::new(None, config);

        engine
            .ingest_chat(ChatSession {
                source: "codex".to_string(),
                session_id: "conv-router-1".to_string(),
                turns: vec![ChatTurn {
                    role: "assistant".to_string(),
                    content: "fn workspace_attach_router() { println!(\"router\"); }".to_string(),
                    timestamp: Some(Utc::now()),
                    model: Some("gpt-5.4".to_string()),
                    turn_index: Some(0),
                }],
                tags: vec!["b227".to_string(), "router".to_string(), "code".to_string()],
                metadata: json!({
                    "domain": "beagle-engine",
                    "repo_path": "beagle/crates/beagle-darwin/src/workspace_attach.rs",
                    "file_type": "rust",
                    "workstream_id": "beagle-darwin-hpc-governance",
                    "campaign_id": "expedition-002-hrv-aware",
                    "program_id": "beagle-physio-symbolic-exocortex",
                    "workspace_id": "beagle-cluster-pilot",
                    "session_id": "ws-cluster-workspace-habitat",
                }),
            })
            .await
            .unwrap();

        let result = engine
            .routed_retrieve(RoutedRetrievalQuery {
                query_version: crate::retrieval::ROUTED_RETRIEVAL_QUERY_VERSION.to_string(),
                query_text: "find workspace_attach router implementation".to_string(),
                top_k: 3,
                dense_enabled: true,
                sparse_enabled: true,
                dense_weight: 0.75,
                sparse_weight: 0.25,
                filters: RetrievalFilters {
                    workstream_id: Some("beagle-darwin-hpc-governance".to_string()),
                    campaign_id: Some("expedition-002-hrv-aware".to_string()),
                    session_id: Some("ws-cluster-workspace-habitat".to_string()),
                    repo_path: Some("beagle/crates/beagle-darwin/src/workspace_attach.rs".to_string()),
                    file_type: Some("rust".to_string()),
                    tags: vec!["b227".to_string(), "router".to_string()],
                    ..RetrievalFilters::default()
                },
                query_type_hint: None,
                compare_against_general: true,
                rerank_hint: Some("code-router".to_string()),
            })
            .await
            .unwrap();

        assert_eq!(result.query_type, "code");
        assert_eq!(result.routing_decision.selected_route, "code");
        assert_eq!(result.sparse_backend, "local-lexical");
        assert!(!result.hits.is_empty());
        assert_eq!(
            result.hits[0].point.payload.repo_path.as_deref(),
            Some("beagle/crates/beagle-darwin/src/workspace_attach.rs")
        );
        assert_eq!(result.hits[0].point.payload.file_type.as_deref(), Some("rust"));
        assert_eq!(
            result.hits[0].point.payload.workstream_id.as_deref(),
            Some("beagle-darwin-hpc-governance")
        );
        assert_eq!(
            result.hits[0].point.payload.campaign_id.as_deref(),
            Some("expedition-002-hrv-aware")
        );
        assert_eq!(
            result.hits[0].point.payload.session_id.as_deref(),
            Some("ws-cluster-workspace-habitat")
        );

        let _ = fs::remove_dir_all(root);
    }

    #[tokio::test]
    async fn code_retrieval_uses_repo_filters_and_comparison_shape() {
        let root = env::temp_dir().join(format!("beagle-memory-code-{}", Uuid::new_v4()));
        let config = local_test_config(root.as_path());
        let engine = MemoryEngine::new(None, config);

        engine
            .ingest_chat(ChatSession {
                source: "codex".to_string(),
                session_id: "conv-code-1".to_string(),
                turns: vec![ChatTurn {
                    role: "assistant".to_string(),
                    content: "fn load_workspace_attach() { managed_attach_state(); }".to_string(),
                    timestamp: Some(Utc::now()),
                    model: Some("gpt-5.4".to_string()),
                    turn_index: Some(0),
                }],
                tags: vec!["b225".to_string(), "code".to_string()],
                metadata: json!({
                    "domain": "beagle-engine",
                    "repo_path": "beagle/crates/beagle-darwin/src/workspace_attach.rs",
                    "file_type": "rust",
                    "workstream_id": "beagle-darwin-hpc-governance",
                    "campaign_id": "expedition-002-hrv-aware",
                    "program_id": "beagle-physio-symbolic-exocortex",
                    "workspace_id": "beagle-cluster-pilot",
                    "session_id": "ws-cluster-workspace-habitat",
                }),
            })
            .await
            .unwrap();

        engine
            .ingest_chat(ChatSession {
                source: "codex".to_string(),
                session_id: "conv-code-2".to_string(),
                turns: vec![ChatTurn {
                    role: "assistant".to_string(),
                    content: "#!/usr/bin/env bash\necho managed attach".to_string(),
                    timestamp: Some(Utc::now()),
                    model: Some("gpt-5.4".to_string()),
                    turn_index: Some(0),
                }],
                tags: vec!["b225".to_string(), "code".to_string()],
                metadata: json!({
                    "domain": "darwin-hpc",
                    "repo_path": "beagle/scripts/infrastructure/darwin-hpc/launch_workspace_attach.sh",
                    "file_type": "shell",
                    "workstream_id": "beagle-darwin-hpc-governance",
                    "campaign_id": "expedition-002-hrv-aware",
                    "program_id": "beagle-physio-symbolic-exocortex",
                    "workspace_id": "beagle-cluster-pilot",
                    "session_id": "ws-cluster-workspace-habitat",
                }),
            })
            .await
            .unwrap();

        let result = engine
            .code_retrieve(CodeRetrievalQuery {
                query_version: crate::retrieval::CODE_RETRIEVAL_QUERY_VERSION.to_string(),
                query_text: "managed attach workspace_attach rust".to_string(),
                top_k: 3,
                dense_enabled: true,
                sparse_enabled: true,
                dense_weight: 0.75,
                sparse_weight: 0.25,
                filters: RetrievalFilters {
                    workstream_id: Some("beagle-darwin-hpc-governance".to_string()),
                    repo_path: Some("beagle/crates/beagle-darwin/src/workspace_attach.rs".to_string()),
                    file_type: Some("rust".to_string()),
                    tags: vec!["b225".to_string()],
                    ..RetrievalFilters::default()
                },
                compare_against_general: true,
                rerank_hint: Some("code-pilot".to_string()),
            })
            .await
            .unwrap();

        assert_eq!(result.code_dense_backend, "local-fallback-dense");
        assert_eq!(result.general_dense_backend, "local-fallback-dense");
        assert_eq!(result.backend_profile.model, "voyage-code-3");
        assert!(!result.hits.is_empty());
        assert!(result
            .hits
            .iter()
            .all(|hit| hit.point.payload.file_type.as_deref() == Some("rust")));
        assert!(result.hits.iter().all(|hit| {
            hit.point.payload.repo_path.as_deref()
                == Some("beagle/crates/beagle-darwin/src/workspace_attach.rs")
        }));
        assert!(result.comparison.is_some());

        let _ = fs::remove_dir_all(root);
    }

    #[tokio::test]
    async fn sovereign_retrieval_uses_filters_and_comparison_shape() {
        let root = env::temp_dir().join(format!("beagle-memory-sovereign-{}", Uuid::new_v4()));
        let config = local_test_config(root.as_path());
        let engine = MemoryEngine::new(None, config);

        engine
            .ingest_chat(ChatSession {
                source: "codex".to_string(),
                session_id: "conv-sovereign-1".to_string(),
                turns: vec![ChatTurn {
                    role: "assistant".to_string(),
                    content: "Alias estavel do workspace managed attach com contexto de memoria soberana.".to_string(),
                    timestamp: Some(Utc::now()),
                    model: Some("gpt-5.4".to_string()),
                    turn_index: Some(0),
                }],
                tags: vec!["b226".to_string(), "sovereign".to_string(), "pt".to_string()],
                metadata: json!({
                    "domain": "beagle-engine",
                    "repo_path": "beagle/crates/beagle-darwin/src/workspace_attach.rs",
                    "file_type": "rust",
                    "workstream_id": "beagle-darwin-hpc-governance",
                    "campaign_id": "expedition-002-hrv-aware",
                    "program_id": "beagle-physio-symbolic-exocortex",
                    "workspace_id": "beagle-cluster-pilot",
                    "session_id": "ws-cluster-workspace-habitat",
                }),
            })
            .await
            .unwrap();

        engine
            .ingest_chat(ChatSession {
                source: "codex".to_string(),
                session_id: "conv-sovereign-2".to_string(),
                turns: vec![ChatTurn {
                    role: "assistant".to_string(),
                    content: "#!/usr/bin/env bash\nkubectl rollout restart deployment/beagle-core".to_string(),
                    timestamp: Some(Utc::now()),
                    model: Some("gpt-5.4".to_string()),
                    turn_index: Some(0),
                }],
                tags: vec!["b226".to_string(), "sovereign".to_string(), "ops".to_string()],
                metadata: json!({
                    "domain": "darwin-hpc",
                    "repo_path": "beagle/scripts/infrastructure/darwin-hpc/run_dense_backend_promotion_smoke.sh",
                    "file_type": "shell",
                    "workstream_id": "beagle-darwin-hpc-governance",
                    "campaign_id": "expedition-002-hrv-aware",
                    "program_id": "beagle-physio-symbolic-exocortex",
                    "workspace_id": "beagle-cluster-pilot",
                    "session_id": "ws-cluster-workspace-habitat",
                }),
            })
            .await
            .unwrap();

        let result = engine
            .sovereign_retrieve(SovereignRetrievalQuery {
                query_version: crate::retrieval::SOVEREIGN_RETRIEVAL_QUERY_VERSION.to_string(),
                query_text: "alias estavel workspace attach".to_string(),
                top_k: 3,
                dense_enabled: true,
                sparse_enabled: true,
                dense_weight: 0.7,
                sparse_weight: 0.3,
                filters: RetrievalFilters {
                    workstream_id: Some("beagle-darwin-hpc-governance".to_string()),
                    campaign_id: Some("expedition-002-hrv-aware".to_string()),
                    session_id: Some("ws-cluster-workspace-habitat".to_string()),
                    source: Some("codex".to_string()),
                    role: None,
                    domain: None,
                    repo_path: Some("beagle/crates/beagle-darwin/src/workspace_attach.rs".to_string()),
                    file_type: Some("rust".to_string()),
                    tags: vec!["b226".to_string(), "sovereign".to_string()],
                },
                compare_against_general: true,
                rerank_hint: Some("sovereign-multilingual".to_string()),
            })
            .await
            .unwrap();

        assert_eq!(result.sovereign_dense_backend, "local-fallback-dense");
        assert_eq!(result.general_dense_backend, "local-fallback-dense");
        assert_eq!(result.sparse_backend, "local-lexical");
        assert_eq!(result.backend_profile.backend_id, "local-fallback-dense");
        assert_eq!(result.hits.len(), 1);
        assert_eq!(
            result.hits[0].point.payload.repo_path.as_deref(),
            Some("beagle/crates/beagle-darwin/src/workspace_attach.rs")
        );
        assert_eq!(
            result.hits[0].point.payload.file_type.as_deref(),
            Some("rust")
        );
        assert!(result.comparison.is_some());

        let _ = fs::remove_dir_all(root);
    }

    #[test]
    fn reranking_profile_exposes_bounded_general_and_sovereign_candidates() {
        let root = env::temp_dir().join(format!("beagle-memory-reranking-profile-{}", Uuid::new_v4()));
        let engine = MemoryEngine::new(None, promoted_test_config(root.as_path()));
        let profile = engine.reranking_profile();

        assert_eq!(profile.profile_id, "b228-bounded-reranking-pilot");
        assert_eq!(profile.current_state, "pilot-live-bounded");
        assert_eq!(profile.current_mode, "top-k-reranking-pilot");
        assert_eq!(profile.bounded_top_k, 5);
        assert_eq!(profile.general_candidate_id, "voyage-rerank-2.5");
        assert_eq!(profile.sovereign_candidate_id, "bge-reranker-v2-m3");
        assert!(profile.candidates.iter().any(|candidate| {
            candidate.candidate_id == "voyage-rerank-2.5"
                && candidate.runtime_state == "pilot-active"
                && candidate.route_scope == "general"
        }));
        assert!(profile.candidates.iter().any(|candidate| {
            candidate.candidate_id == "bge-reranker-v2-m3"
                && candidate.runtime_state == "pilot-active"
                && candidate.route_scope == "sovereign"
        }));
    }

    #[test]
    fn parse_rerank_scores_accepts_voyage_and_tei_shapes() {
        let voyage = r#"{"data":[{"index":1,"relevance_score":0.91},{"index":0,"relevance_score":0.73}]}"#;
        let tei = r#"[{"index":0,"score":0.88},{"index":2,"score":0.67}]"#;

        let voyage_scores = parse_rerank_scores(voyage).unwrap();
        let tei_scores = parse_rerank_scores(tei).unwrap();

        assert_eq!(voyage_scores[0].index, 1);
        assert_eq!(voyage_scores[0].score, 0.91);
        assert_eq!(tei_scores[0].index, 0);
        assert_eq!(tei_scores[0].score, 0.88);
    }

    #[test]
    fn apply_rerank_scores_reorders_and_preserves_tail() {
        let prerank_hits = vec![
            RetrievalHit {
                rank: 1,
                point: MemoryPoint {
                    point_version: crate::retrieval::MEMORY_POINT_VERSION.to_string(),
                    point_id: "m1".to_string(),
                    collection_name: "beagle_memory_local".to_string(),
                    dense_vector_name: Some("beagle-memory-dense".to_string()),
                    payload: MemoryRecord {
                        memory_id: "m1".to_string(),
                        source: "codex".to_string(),
                        conversation_id: "conv-1".to_string(),
                        workstream_id: None,
                        campaign_id: None,
                        program_id: None,
                        workspace_id: None,
                        session_id: None,
                        turn_index: 0,
                        role: "assistant".to_string(),
                        text: "first".to_string(),
                        tags: vec![],
                        domain: None,
                        repo_path: None,
                        file_type: None,
                        timestamp: Utc::now(),
                        physio_snapshot: None,
                        experiment_flags: None,
                        physio_snapshot_ref: None,
                        result_refs: vec![],
                        claim_refs: vec![],
                        provider: None,
                        model: None,
                        score: None,
                    },
                    note: "test point".to_string(),
                },
                dense_score: Some(0.9),
                sparse_score: Some(0.2),
                hybrid_score: 0.86,
            },
            RetrievalHit {
                rank: 2,
                point: MemoryPoint {
                    point_version: crate::retrieval::MEMORY_POINT_VERSION.to_string(),
                    point_id: "m2".to_string(),
                    collection_name: "beagle_memory_local".to_string(),
                    dense_vector_name: Some("beagle-memory-dense".to_string()),
                    payload: MemoryRecord {
                        memory_id: "m2".to_string(),
                        source: "codex".to_string(),
                        conversation_id: "conv-2".to_string(),
                        workstream_id: None,
                        campaign_id: None,
                        program_id: None,
                        workspace_id: None,
                        session_id: None,
                        turn_index: 0,
                        role: "assistant".to_string(),
                        text: "second".to_string(),
                        tags: vec![],
                        domain: None,
                        repo_path: None,
                        file_type: None,
                        timestamp: Utc::now(),
                        physio_snapshot: None,
                        experiment_flags: None,
                        physio_snapshot_ref: None,
                        result_refs: vec![],
                        claim_refs: vec![],
                        provider: None,
                        model: None,
                        score: None,
                    },
                    note: "test point".to_string(),
                },
                dense_score: Some(0.7),
                sparse_score: Some(0.3),
                hybrid_score: 0.74,
            },
        ];

        let reranked = apply_rerank_scores_to_hits(
            &prerank_hits,
            &[RerankScore {
                index: 1,
                score: 0.97,
            }],
        );

        assert_eq!(reranked.len(), 2);
        assert_eq!(reranked[0].point.payload.memory_id, "m2");
        assert_eq!(reranked[0].prerank_rank, 2);
        assert_eq!(reranked[0].rank, 1);
        assert_eq!(reranked[1].point.payload.memory_id, "m1");
        assert_eq!(reranked[1].prerank_rank, 1);
        assert_eq!(reranked[1].rank, 2);
    }

    #[test]
    fn apply_feedback_judgments_reorders_hits() {
        let prerank_hits = vec![
            RerankedHit {
                rank: 1,
                prerank_rank: 1,
                point: MemoryPoint {
                    point_version: crate::retrieval::MEMORY_POINT_VERSION.to_string(),
                    point_id: "m1".to_string(),
                    collection_name: "beagle_memory_local".to_string(),
                    dense_vector_name: Some("dense".to_string()),
                    payload: MemoryRecord {
                        memory_id: "m1".to_string(),
                        source: "codex".to_string(),
                        conversation_id: "conv-1".to_string(),
                        workstream_id: Some("beagle-darwin-hpc-governance".to_string()),
                        campaign_id: Some("expedition-002-hrv-aware".to_string()),
                        program_id: None,
                        workspace_id: None,
                        session_id: Some("ws-cluster-workspace-habitat".to_string()),
                        turn_index: 0,
                        role: "assistant".to_string(),
                        text: "workspace_exec_proxy helper".to_string(),
                        tags: vec!["b229-feedback".to_string(), "code".to_string()],
                        domain: Some("darwin-hpc".to_string()),
                        repo_path: Some(
                            "beagle/scripts/infrastructure/darwin-hpc/workspace_exec_proxy.sh"
                                .to_string(),
                        ),
                        file_type: Some("shell".to_string()),
                        timestamp: Utc::now(),
                        physio_snapshot: None,
                        experiment_flags: None,
                        physio_snapshot_ref: None,
                        result_refs: vec![],
                        claim_refs: vec![],
                        provider: None,
                        model: None,
                        score: None,
                    },
                    note: "test point".to_string(),
                },
                dense_score: Some(0.8),
                sparse_score: Some(0.4),
                hybrid_score: 0.82,
                rerank_score: 0.82,
            },
            RerankedHit {
                rank: 2,
                prerank_rank: 2,
                point: MemoryPoint {
                    point_version: crate::retrieval::MEMORY_POINT_VERSION.to_string(),
                    point_id: "m2".to_string(),
                    collection_name: "beagle_memory_local".to_string(),
                    dense_vector_name: Some("dense".to_string()),
                    payload: MemoryRecord {
                        memory_id: "m2".to_string(),
                        source: "codex".to_string(),
                        conversation_id: "conv-2".to_string(),
                        workstream_id: Some("beagle-darwin-hpc-governance".to_string()),
                        campaign_id: Some("expedition-002-hrv-aware".to_string()),
                        program_id: None,
                        workspace_id: None,
                        session_id: Some("ws-cluster-workspace-habitat".to_string()),
                        turn_index: 1,
                        role: "assistant".to_string(),
                        text: "http_memory feedback policy derive route".to_string(),
                        tags: vec!["b229-feedback".to_string(), "code".to_string()],
                        domain: Some("darwin-hpc".to_string()),
                        repo_path: Some(
                            "beagle/apps/beagle-monorepo/src/http_memory.rs".to_string(),
                        ),
                        file_type: Some("rust".to_string()),
                        timestamp: Utc::now(),
                        physio_snapshot: None,
                        experiment_flags: None,
                        physio_snapshot_ref: None,
                        result_refs: vec![],
                        claim_refs: vec![],
                        provider: None,
                        model: None,
                        score: None,
                    },
                    note: "test point".to_string(),
                },
                dense_score: Some(0.6),
                sparse_score: Some(0.3),
                hybrid_score: 0.61,
                rerank_score: 0.61,
            },
        ];

        let feedback_hits = apply_feedback_judgments_to_hits(
            &prerank_hits,
            &[
                RelevanceFeedbackJudgment {
                    memory_id: "m1".to_string(),
                    signal: "negative".to_string(),
                    score: 0.7,
                    rationale: None,
                },
                RelevanceFeedbackJudgment {
                    memory_id: "m2".to_string(),
                    signal: "positive".to_string(),
                    score: 0.9,
                    rationale: None,
                },
            ],
        );

        assert_eq!(feedback_hits.len(), 2);
        assert_eq!(feedback_hits[0].point.payload.memory_id, "m2");
        assert_eq!(feedback_hits[0].rank, 1);
        assert!(feedback_hits[0].adjusted_score > feedback_hits[1].adjusted_score);
    }

    #[test]
    fn derive_retrieval_policy_records_evidence_basis() {
        let root = env::temp_dir().join(format!("beagle-memory-policy-{}", Uuid::new_v4()));
        let engine = MemoryEngine::new(None, local_test_config(root.as_path()));
        let report = RetrievalEvalReport {
            report_version: crate::retrieval::RETRIEVAL_EVAL_REPORT_VERSION.to_string(),
            collection_name: "beagle_memory_local".to_string(),
            sparse_backend: "local-lexical".to_string(),
            reranking_profile_id: "b228-bounded-reranking-pilot".to_string(),
            generated_at: "2026-03-27T09:00:00Z".to_string(),
            cases: vec![],
            lanes: vec![
                RetrievalEvalLaneSummary {
                    query_type: "general".to_string(),
                    selected_route: "general".to_string(),
                    dense_backend: "voyage-4-large".to_string(),
                    sparse_backend: "local-lexical".to_string(),
                    reranker_backend: "voyage-rerank-2.5".to_string(),
                    case_count: 1,
                    average_latency_ms: 123.0,
                    average_relevance_proxy: 0.88,
                    average_filter_correctness: 1.0,
                    top_k_stability_pass_rate: 1.0,
                    route_appropriateness_rate: 1.0,
                    average_context_packet_usable_hits: 2.0,
                    recommended_when:
                        "Use this lane for general campaign, workstream, memory, and tool-context retrieval."
                            .to_string(),
                    note: "general lane".to_string(),
                },
                RetrievalEvalLaneSummary {
                    query_type: "code".to_string(),
                    selected_route: "code".to_string(),
                    dense_backend: "voyage-code-3".to_string(),
                    sparse_backend: "local-lexical".to_string(),
                    reranker_backend: "rerank-disabled".to_string(),
                    case_count: 1,
                    average_latency_ms: 98.0,
                    average_relevance_proxy: 0.72,
                    average_filter_correctness: 1.0,
                    top_k_stability_pass_rate: 1.0,
                    route_appropriateness_rate: 1.0,
                    average_context_packet_usable_hits: 2.0,
                    recommended_when:
                        "Use this lane when repo paths, file types, scripts, or configuration intent dominate the query."
                            .to_string(),
                    note: "code lane".to_string(),
                },
            ],
            note: "report".to_string(),
        };

        let policy = engine.derive_retrieval_policy(&report);

        assert_eq!(policy.policy_id, "b229-evidence-backed-retrieval-policy");
        assert_eq!(policy.lanes.len(), 2);
        assert!(policy.lanes[0]
            .evidence_basis
            .iter()
            .any(|entry| entry.starts_with("average_relevance_proxy=")));
        assert_eq!(policy.lanes[0].last_eval_at, "2026-03-27T09:00:00Z");
        assert_eq!(policy.lanes[1].feedback_mode, "enable-bounded-feedback-loop");
    }

    #[test]
    fn graph_rag_from_reranked_result_builds_hierarchy_and_canonical_edges() {
        let root = env::temp_dir().join(format!("beagle-memory-graphrag-{}", Uuid::new_v4()));
        let engine = MemoryEngine::new(None, local_test_config(root.as_path()));
        let query = GraphRagQuery {
            query_version: crate::retrieval::GRAPHRAG_QUERY_VERSION.to_string(),
            query_text: "connect experiment results to claims and manuscript".to_string(),
            top_k: 3,
            max_hops: 2,
            dense_enabled: true,
            sparse_enabled: true,
            dense_weight: 0.65,
            sparse_weight: 0.35,
            filters: RetrievalFilters {
                workstream_id: Some("beagle-darwin-hpc-governance".to_string()),
                campaign_id: Some("expedition-002-hrv-aware".to_string()),
                session_id: Some("ws-cluster-workspace-habitat".to_string()),
                source: Some("codex".to_string()),
                role: Some("assistant".to_string()),
                domain: Some("darwin-hpc".to_string()),
                repo_path: None,
                file_type: None,
                tags: vec!["b231-graphrag".to_string()],
            },
            root_entity_type: Some("workstream".to_string()),
            root_entity_id: Some("beagle-darwin-hpc-governance".to_string()),
            program_id: Some("beagle-physio-symbolic-exocortex".to_string()),
            include_memory_hierarchy: true,
            query_type_hint: Some("general".to_string()),
            query_mode_hint: None,
            rerank_hint: Some("b231-graphrag-test".to_string()),
        };

        let reranked = RerankedResult {
            result_version: crate::retrieval::RERANKED_RESULT_VERSION.to_string(),
            profile_id: "b228-bounded-reranking-pilot".to_string(),
            query_type: "general".to_string(),
            routing_decision: RetrievalRoutingDecision {
                decision_version: crate::retrieval::RETRIEVAL_ROUTING_DECISION_VERSION.to_string(),
                router_version: crate::retrieval::RETRIEVAL_ROUTER_VERSION.to_string(),
                query_type: "general".to_string(),
                selected_route: "general".to_string(),
                selected_dense_backend: "voyage-4-large".to_string(),
                sparse_backend: "local-lexical".to_string(),
                payload_filters_present: true,
                compare_against_general: false,
                routing_source: "heuristic+payload".to_string(),
                routing_reason: "campaign/workstream retrieval".to_string(),
                note: "test".to_string(),
            },
            collection_name: "beagle_memory_local".to_string(),
            prerank_retrieval_mode: "general-dense+sparse-hybrid".to_string(),
            postrank_retrieval_mode: "general-dense+sparse-hybrid+rerank".to_string(),
            dense_backend: "voyage-4-large".to_string(),
            sparse_backend: "local-lexical".to_string(),
            reranker_backend: "voyage-rerank-2.5".to_string(),
            reranker_kind: "cross-encoder-api".to_string(),
            reranker_runtime_state: "pilot-active".to_string(),
            reranking_applied: true,
            top_k: 3,
            candidate_count: 2,
            applied_filters: query.filters.clone(),
            prerank_hit_count: 2,
            postrank_hit_count: 2,
            prerank_top_memory_ids: vec!["memory-semantic".to_string(), "memory-procedural".to_string()],
            postrank_top_memory_ids: vec!["memory-semantic".to_string(), "memory-procedural".to_string()],
            relevance_proxy_before: 0.6,
            relevance_proxy_after: 0.8,
            latency: RerankingLatencyComparison {
                prerank_latency_ms: 12,
                rerank_latency_ms: 7,
                total_latency_ms: 19,
                latency_delta_ms: 7,
            },
            hits: vec![
                RerankedHit {
                    rank: 1,
                    prerank_rank: 1,
                    point: MemoryPoint {
                        point_version: crate::retrieval::MEMORY_POINT_VERSION.to_string(),
                        point_id: "point-semantic".to_string(),
                        collection_name: "beagle_memory_local".to_string(),
                        dense_vector_name: Some("beagle-memory-dense".to_string()),
                        payload: MemoryRecord {
                            memory_id: "memory-semantic".to_string(),
                            source: "codex".to_string(),
                            conversation_id: "conv-semantic".to_string(),
                            workstream_id: Some("beagle-darwin-hpc-governance".to_string()),
                            campaign_id: Some("expedition-002-hrv-aware".to_string()),
                            program_id: Some("beagle-physio-symbolic-exocortex".to_string()),
                            workspace_id: Some("beagle-cluster-pilot".to_string()),
                            session_id: Some("ws-cluster-workspace-habitat".to_string()),
                            turn_index: 0,
                            role: "assistant".to_string(),
                            text: "Experiment batch A result supports the HRV-aware claim in the manuscript draft.".to_string(),
                            tags: vec!["b231-graphrag".to_string(), "claim".to_string(), "evidence".to_string()],
                            domain: Some("darwin-hpc".to_string()),
                            repo_path: None,
                            file_type: None,
                            timestamp: Utc::now(),
                            physio_snapshot: None,
                            experiment_flags: None,
                            physio_snapshot_ref: None,
                            result_refs: vec!["experiment-expedition-002-batch-a/result-hrv-aware".to_string()],
                            claim_refs: vec!["claim-hrv-aware-improves-latency".to_string()],
                            provider: None,
                            model: None,
                            score: None,
                        },
                        note: "semantic".to_string(),
                    },
                    dense_score: Some(0.92),
                    sparse_score: Some(0.41),
                    hybrid_score: 0.88,
                    rerank_score: 0.93,
                },
                RerankedHit {
                    rank: 2,
                    prerank_rank: 2,
                    point: MemoryPoint {
                        point_version: crate::retrieval::MEMORY_POINT_VERSION.to_string(),
                        point_id: "point-procedural".to_string(),
                        collection_name: "beagle_memory_local".to_string(),
                        dense_vector_name: Some("beagle-memory-dense".to_string()),
                        payload: MemoryRecord {
                            memory_id: "memory-procedural".to_string(),
                            source: "codex".to_string(),
                            conversation_id: "conv-procedural".to_string(),
                            workstream_id: Some("beagle-darwin-hpc-governance".to_string()),
                            campaign_id: Some("expedition-002-hrv-aware".to_string()),
                            program_id: Some("beagle-physio-symbolic-exocortex".to_string()),
                            workspace_id: Some("beagle-cluster-pilot".to_string()),
                            session_id: Some("ws-cluster-workspace-habitat".to_string()),
                            turn_index: 1,
                            role: "assistant".to_string(),
                            text: "Update the GraphRAG smoke script and HTTP memory route for the pilot.".to_string(),
                            tags: vec!["b231-graphrag".to_string(), "code".to_string()],
                            domain: Some("darwin-hpc".to_string()),
                            repo_path: Some("beagle/apps/beagle-monorepo/src/http_memory.rs".to_string()),
                            file_type: Some("rust".to_string()),
                            timestamp: Utc::now(),
                            physio_snapshot: None,
                            experiment_flags: None,
                            physio_snapshot_ref: None,
                            result_refs: vec![],
                            claim_refs: vec![],
                            provider: None,
                            model: None,
                            score: None,
                        },
                        note: "procedural".to_string(),
                    },
                    dense_score: Some(0.71),
                    sparse_score: Some(0.22),
                    hybrid_score: 0.63,
                    rerank_score: 0.61,
                },
            ],
            recommendation: RerankingRecommendation {
                query_type: "general".to_string(),
                reranker_backend: "voyage-rerank-2.5".to_string(),
                runtime_state: "pilot-active".to_string(),
                reranking_applied: true,
                top_hit_changed: false,
                relevance_proxy_before: 0.6,
                relevance_proxy_after: 0.8,
                latency_delta_ms: 7,
                recommendation: "keep-bounded-reranking-pilot-enabled".to_string(),
                note: "test".to_string(),
            },
            note: "test".to_string(),
        };

        let mode = engine.graph_rag_query_mode(&query);
        let graphrag = engine.graph_rag_from_reranked_result(&query, &reranked, &mode);

        assert_eq!(graphrag.result_version, GRAPHRAG_RESULT_VERSION);
        assert_eq!(graphrag.query_mode, "local");
        assert_eq!(graphrag.root_entity_type.as_deref(), Some("workstream"));
        assert_eq!(graphrag.root_entity_id.as_deref(), Some("beagle-darwin-hpc-governance"));
        assert_eq!(graphrag.promotion_policy_id, "b232-memory-promotion-policy");
        assert_eq!(graphrag.retention_policy_id, "b232-memory-retention-policy");
        assert!(graphrag
            .nodes
            .iter()
            .any(|node| node.node_type == "Workstream"));
        assert!(graphrag
            .nodes
            .iter()
            .any(|node| node.node_type == "Program"));
        assert!(graphrag
            .nodes
            .iter()
            .any(|node| node.node_type == "Session"));
        assert!(graphrag
            .nodes
            .iter()
            .any(|node| node.node_type == "Campaign"));
        assert!(graphrag
            .nodes
            .iter()
            .any(|node| node.node_type == "Experiment"));
        assert!(graphrag
            .nodes
            .iter()
            .any(|node| node.node_type == "Result"));
        assert!(graphrag
            .nodes
            .iter()
            .any(|node| node.node_type == "Claim"));
        assert!(graphrag
            .nodes
            .iter()
            .any(|node| node.node_type == "Manuscript"));
        assert!(graphrag
            .edges
            .iter()
            .any(|edge| edge.edge_type == "contains"));
        assert!(graphrag.edges.iter().any(|edge| edge.edge_type == "uses"));
        assert!(graphrag.edges.iter().any(|edge| edge.edge_type == "runs"));
        assert!(graphrag.edges.iter().any(|edge| edge.edge_type == "yields"));
        assert!(graphrag
            .edges
            .iter()
            .any(|edge| edge.edge_type == "supports"));
        assert!(graphrag
            .edges
            .iter()
            .any(|edge| edge.edge_type == "appears_in"));
        assert!(graphrag
            .edges
            .iter()
            .any(|edge| edge.edge_type == "belongs_to"));
        assert!(graphrag.promoted_memories.is_empty());

        let hierarchy = graphrag.memory_hierarchy.expect("memory hierarchy");
        assert_eq!(hierarchy.policy_id, "b231-memory-hierarchy-policy");
        assert_eq!(hierarchy.buckets.len(), 3);
        assert_eq!(
            hierarchy
                .buckets
                .iter()
                .find(|bucket| bucket.memory_type == "semantic")
                .map(|bucket| bucket.count),
            Some(1)
        );
        assert_eq!(
            hierarchy
                .buckets
                .iter()
                .find(|bucket| bucket.memory_type == "procedural")
                .map(|bucket| bucket.count),
            Some(1)
        );
    }

    #[test]
    fn memory_hierarchy_from_records_classifies_episodic_semantic_and_procedural() {
        let now = Utc::now();
        let hierarchy = memory_hierarchy_from_records(
            "beagle_memory_local",
            &[
                MemoryRecord {
                    memory_id: "memory-episodic".to_string(),
                    source: "codex".to_string(),
                    conversation_id: "conv-episodic".to_string(),
                    workstream_id: Some("beagle-darwin-hpc-governance".to_string()),
                    campaign_id: Some("expedition-002-hrv-aware".to_string()),
                    program_id: Some("beagle-physio-symbolic-exocortex".to_string()),
                    workspace_id: Some("beagle-cluster-pilot".to_string()),
                    session_id: Some("ws-cluster-workspace-habitat".to_string()),
                    turn_index: 0,
                    role: "assistant".to_string(),
                    text: "Session handoff resumed after cluster restart.".to_string(),
                    tags: vec!["handoff".to_string(), "session".to_string()],
                    domain: Some("darwin-hpc".to_string()),
                    repo_path: None,
                    file_type: None,
                    timestamp: now,
                    physio_snapshot: None,
                    experiment_flags: None,
                    physio_snapshot_ref: None,
                    result_refs: Vec::new(),
                    claim_refs: Vec::new(),
                    provider: None,
                    model: None,
                    score: None,
                },
                MemoryRecord {
                    memory_id: "memory-semantic".to_string(),
                    source: "codex".to_string(),
                    conversation_id: "conv-semantic".to_string(),
                    workstream_id: Some("beagle-darwin-hpc-governance".to_string()),
                    campaign_id: Some("expedition-002-hrv-aware".to_string()),
                    program_id: Some("beagle-physio-symbolic-exocortex".to_string()),
                    workspace_id: Some("beagle-cluster-pilot".to_string()),
                    session_id: Some("ws-cluster-workspace-habitat".to_string()),
                    turn_index: 1,
                    role: "assistant".to_string(),
                    text: "Result support stays linked to the manuscript claim.".to_string(),
                    tags: vec!["claim".to_string(), "evidence".to_string()],
                    domain: Some("darwin-hpc".to_string()),
                    repo_path: None,
                    file_type: None,
                    timestamp: now,
                    physio_snapshot: None,
                    experiment_flags: None,
                    physio_snapshot_ref: None,
                    result_refs: vec!["experiment-expedition-002-batch-a/result-hrv-aware".to_string()],
                    claim_refs: vec!["claim-hrv-aware-improves-latency".to_string()],
                    provider: None,
                    model: None,
                    score: None,
                },
                MemoryRecord {
                    memory_id: "memory-procedural".to_string(),
                    source: "codex".to_string(),
                    conversation_id: "conv-procedural".to_string(),
                    workstream_id: Some("beagle-darwin-hpc-governance".to_string()),
                    campaign_id: Some("expedition-002-hrv-aware".to_string()),
                    program_id: Some("beagle-physio-symbolic-exocortex".to_string()),
                    workspace_id: Some("beagle-cluster-pilot".to_string()),
                    session_id: Some("ws-cluster-workspace-habitat".to_string()),
                    turn_index: 2,
                    role: "assistant".to_string(),
                    text: "Update the GraphRAG smoke script and route wiring.".to_string(),
                    tags: vec!["code".to_string(), "runbook".to_string()],
                    domain: Some("darwin-hpc".to_string()),
                    repo_path: Some("beagle/scripts/infrastructure/darwin-hpc/run_memory_hierarchy_graphrag_smoke.sh".to_string()),
                    file_type: Some("shell".to_string()),
                    timestamp: now,
                    physio_snapshot: None,
                    experiment_flags: None,
                    physio_snapshot_ref: None,
                    result_refs: Vec::new(),
                    claim_refs: Vec::new(),
                    provider: None,
                    model: None,
                    score: None,
                },
            ],
        );

        assert_eq!(hierarchy.hierarchy_version, MEMORY_HIERARCHY_VERSION);
        assert_eq!(hierarchy.policy_id, "b231-memory-hierarchy-policy");
        assert_eq!(hierarchy.buckets.len(), 3);
        assert_eq!(
            hierarchy
                .buckets
                .iter()
                .find(|bucket| bucket.memory_type == "episodic")
                .map(|bucket| bucket.memory_ids.clone()),
            Some(vec!["memory-episodic".to_string()])
        );
        assert_eq!(
            hierarchy
                .buckets
                .iter()
                .find(|bucket| bucket.memory_type == "semantic")
                .map(|bucket| bucket.memory_ids.clone()),
            Some(vec!["memory-semantic".to_string()])
        );
        assert_eq!(
            hierarchy
                .buckets
                .iter()
                .find(|bucket| bucket.memory_type == "procedural")
                .map(|bucket| bucket.memory_ids.clone()),
            Some(vec!["memory-procedural".to_string()])
        );
    }

    #[test]
    fn derive_memory_promotion_promotes_episodic_record_into_procedural_memory() {
        let record = MemoryRecord {
            memory_id: "memory-episodic-promotion".to_string(),
            source: "codex".to_string(),
            conversation_id: "conv-promotion".to_string(),
            workstream_id: Some("beagle-darwin-hpc-governance".to_string()),
            campaign_id: Some("expedition-002-hrv-aware".to_string()),
            program_id: Some("beagle-physio-symbolic-exocortex".to_string()),
            workspace_id: Some("beagle-cluster-pilot".to_string()),
            session_id: Some("ws-cluster-workspace-habitat".to_string()),
            turn_index: 4,
            role: "assistant".to_string(),
            text: "Operator note: attach, launch, and resume the same workspace through ssh and kubectl before continuing the workflow.".to_string(),
            tags: vec!["session".to_string(), "handoff".to_string()],
            domain: Some("darwin-hpc".to_string()),
            repo_path: None,
            file_type: None,
            timestamp: Utc::now(),
            physio_snapshot: None,
            experiment_flags: None,
            physio_snapshot_ref: None,
            result_refs: Vec::new(),
            claim_refs: Vec::new(),
            provider: None,
            model: None,
            score: None,
        };

        let promoted = derive_memory_promotion(
            &record,
            Utc::now(),
            &retention_action_for_memory_type("procedural"),
        )
        .expect("promotion event");

        assert_eq!(classify_memory_type(&record), "episodic");
        assert_eq!(promoted.target_memory_type, "procedural");
        assert_eq!(promoted.policy_id, "b232-memory-promotion-policy");
        assert_eq!(promoted.retention_action, "retain-until-superseded");
    }

    #[test]
    fn derive_graphrag_query_mode_routes_local_global_and_drift() {
        let local = derive_graphrag_query_mode(&GraphRagQuery {
            query_version: "beagle-graphrag-query-v1".to_string(),
            query_text: "resume the current workstream neighborhood".to_string(),
            top_k: 3,
            max_hops: 2,
            dense_enabled: true,
            sparse_enabled: true,
            dense_weight: 0.65,
            sparse_weight: 0.35,
            filters: RetrievalFilters {
                workstream_id: Some("beagle-darwin-hpc-governance".to_string()),
                campaign_id: None,
                session_id: Some("ws-cluster-workspace-habitat".to_string()),
                source: None,
                role: None,
                domain: None,
                repo_path: None,
                file_type: None,
                tags: vec![],
            },
            root_entity_type: Some("workstream".to_string()),
            root_entity_id: Some("beagle-darwin-hpc-governance".to_string()),
            program_id: None,
            include_memory_hierarchy: true,
            query_type_hint: Some("general".to_string()),
            query_mode_hint: None,
            rerank_hint: None,
        });
        let global = derive_graphrag_query_mode(&GraphRagQuery {
            query_version: "beagle-graphrag-query-v1".to_string(),
            query_text: "give me the program overview and campaign landscape".to_string(),
            top_k: 3,
            max_hops: 2,
            dense_enabled: true,
            sparse_enabled: true,
            dense_weight: 0.65,
            sparse_weight: 0.35,
            filters: RetrievalFilters::default(),
            root_entity_type: None,
            root_entity_id: None,
            program_id: Some("beagle-physio-symbolic-exocortex".to_string()),
            include_memory_hierarchy: true,
            query_type_hint: Some("general".to_string()),
            query_mode_hint: None,
            rerank_hint: None,
        });
        let drift = derive_graphrag_query_mode(&GraphRagQuery {
            query_version: "beagle-graphrag-query-v1".to_string(),
            query_text: "what changed across sessions and where is the drift in manuscript support".to_string(),
            top_k: 3,
            max_hops: 2,
            dense_enabled: true,
            sparse_enabled: true,
            dense_weight: 0.65,
            sparse_weight: 0.35,
            filters: RetrievalFilters {
                workstream_id: Some("beagle-darwin-hpc-governance".to_string()),
                campaign_id: Some("expedition-002-hrv-aware".to_string()),
                session_id: Some("ws-cluster-workspace-habitat".to_string()),
                source: None,
                role: None,
                domain: None,
                repo_path: None,
                file_type: None,
                tags: vec![],
            },
            root_entity_type: None,
            root_entity_id: None,
            program_id: Some("beagle-physio-symbolic-exocortex".to_string()),
            include_memory_hierarchy: true,
            query_type_hint: Some("general".to_string()),
            query_mode_hint: None,
            rerank_hint: None,
        });

        assert_eq!(local.query_mode, "local");
        assert_eq!(global.query_mode, "global");
        assert_eq!(drift.query_mode, "drift");
        assert_eq!(drift.classifier_source, "content-heuristic");
    }

    #[test]
    fn context_budget_profiles_differ_by_task() {
        let implementation = context_budget_profile("implementation").expect("implementation");
        let analysis = context_budget_profile("analysis").expect("analysis");
        let manuscript = context_budget_profile("manuscript").expect("manuscript");

        assert_eq!(implementation.retrieval_query_type, "code");
        assert_eq!(implementation.graphrag_query_mode_hint, "local");
        assert_eq!(implementation.temporal_truth_view, "current");
        assert_eq!(analysis.retrieval_query_type, "general");
        assert_eq!(analysis.graphrag_query_mode_hint, "global");
        assert_eq!(analysis.temporal_truth_view, "both");
        assert_eq!(manuscript.retrieval_query_type, "general");
        assert_eq!(manuscript.profile_id, "b235-budget-manuscript");
        assert!(implementation
            .allocations
            .iter()
            .any(|allocation| allocation.source_kind == "temporal"));
        assert_ne!(implementation.profile_id, analysis.profile_id);
        assert_ne!(analysis.profile_id, manuscript.profile_id);
    }

    #[test]
    fn compiler_policy_variants_include_canonical_and_alternates() {
        let implementation = compiler_policy_variants("implementation").expect("implementation");
        let analysis = compiler_policy_variants("analysis").expect("analysis");
        let manuscript = compiler_policy_variants("manuscript").expect("manuscript");

        assert!(implementation.len() >= 2);
        assert_eq!(implementation[0].profile_id, "b235-budget-implementation");
        assert_eq!(implementation[0].temporal_truth_view, "current");
        assert!(implementation
            .iter()
            .any(|profile| profile.graphrag_query_mode_hint == "global"));

        assert!(analysis.len() >= 3);
        assert!(analysis
            .iter()
            .any(|profile| profile.graphrag_query_mode_hint == "drift"));
        assert!(analysis
            .iter()
            .any(|profile| profile.temporal_truth_view == "both"));

        assert!(manuscript.len() >= 2);
        assert_eq!(manuscript[0].profile_id, "b235-budget-manuscript");
        assert!(manuscript
            .iter()
            .any(|profile| profile.temporal_truth_view == "current"));
    }

    #[test]
    fn derive_compiler_policy_records_evidence_basis() {
        let root = env::temp_dir().join(format!("beagle-memory-compiler-policy-{}", Uuid::new_v4()));
        let engine = MemoryEngine::new(None, local_test_config(root.as_path()));
        let report = CompilerEvalReport {
            report_version: COMPILER_EVAL_REPORT_VERSION.to_string(),
            compiler_id: "b235-query-adaptive-memory-compiler".to_string(),
            generated_at: "2026-03-27T12:00:00Z".to_string(),
            comparisons: vec![
                CompilerTaskComparison {
                    case_id: "case-implementation".to_string(),
                    task_profile: "implementation".to_string(),
                    description: Some("implementation case".to_string()),
                    selected_variant_id: "b235-budget-implementation".to_string(),
                    selected_budget_profile_id: "b235-budget-implementation".to_string(),
                    recommendation: "Prefer canonical implementation policy.".to_string(),
                    variants: vec![
                        CompilerPolicyVariantReport {
                            variant_id: "b235-budget-implementation".to_string(),
                            budget_profile_id: "b235-budget-implementation".to_string(),
                            task_profile: "implementation".to_string(),
                            retrieval_query_type: "code".to_string(),
                            dense_backend: "voyage-code-3".to_string(),
                            sparse_backend: "local-lexical".to_string(),
                            graphrag_query_mode: "local".to_string(),
                            temporal_truth_view: "current".to_string(),
                            selected_memory_tiers: vec![
                                "procedural".to_string(),
                                "semantic".to_string(),
                                "episodic".to_string(),
                            ],
                            top_memory_ids: vec!["m1".to_string()],
                            relevance_proxy_score: 0.91,
                            task_fit_score: 0.95,
                            context_usefulness_score: 0.88,
                            budget_efficiency_score: 0.75,
                            top_k_stable: true,
                            truth_view_appropriate: true,
                            graphrag_mode_appropriate: true,
                            route_appropriate: true,
                            overall_score: 0.89,
                            latency_ms: 42,
                            note: "winner".to_string(),
                        },
                    ],
                    note: "comparison".to_string(),
                },
            ],
            note: "report".to_string(),
        };

        let policy = engine.derive_compiler_policy(&report);

        assert_eq!(policy.policy_id, "b236-evidence-backed-compiler-policy");
        assert_eq!(policy.profiles.len(), 1);
        assert_eq!(policy.profiles[0].task_profile, "implementation");
        assert!(policy.profiles[0]
            .evidence_basis
            .iter()
            .any(|entry| entry.starts_with("overall_score=")));
        assert_eq!(policy.profiles[0].last_eval_at, "2026-03-27T12:00:00Z");
    }

    #[test]
    fn compiled_context_from_runtime_prioritizes_profile_specific_memory_slices() {
        let now = Utc::now();
        let procedural = MemoryRecord {
            memory_id: "memory-procedural".to_string(),
            source: "codex".to_string(),
            conversation_id: "conv-procedural".to_string(),
            workstream_id: Some("beagle-darwin-hpc-governance".to_string()),
            campaign_id: Some("expedition-002-hrv-aware".to_string()),
            program_id: Some("beagle-physio-symbolic-exocortex".to_string()),
            workspace_id: Some("beagle-cluster-pilot".to_string()),
            session_id: Some("ws-cluster-workspace-habitat".to_string()),
            turn_index: 0,
            role: "assistant".to_string(),
            text: "Update the workflow script and config path for the attach compiler.".to_string(),
            tags: vec!["code".to_string(), "workflow".to_string()],
            domain: Some("darwin-hpc".to_string()),
            repo_path: Some("beagle/crates/beagle-memory/src/compiler.rs".to_string()),
            file_type: Some("rust".to_string()),
            timestamp: now,
            physio_snapshot: None,
            experiment_flags: None,
            physio_snapshot_ref: None,
            result_refs: Vec::new(),
            claim_refs: Vec::new(),
            provider: None,
            model: None,
            score: None,
        };
        let semantic = MemoryRecord {
            memory_id: "memory-semantic".to_string(),
            source: "claude-code".to_string(),
            conversation_id: "conv-semantic".to_string(),
            workstream_id: Some("beagle-darwin-hpc-governance".to_string()),
            campaign_id: Some("expedition-002-hrv-aware".to_string()),
            program_id: Some("beagle-physio-symbolic-exocortex".to_string()),
            workspace_id: Some("beagle-cluster-pilot".to_string()),
            session_id: Some("ws-cluster-workspace-habitat".to_string()),
            turn_index: 1,
            role: "assistant".to_string(),
            text: "The result support remains linked to the campaign claim and manuscript evidence.".to_string(),
            tags: vec!["claim".to_string(), "evidence".to_string()],
            domain: Some("darwin-hpc".to_string()),
            repo_path: None,
            file_type: None,
            timestamp: now,
            physio_snapshot: None,
            experiment_flags: None,
            physio_snapshot_ref: None,
            result_refs: vec!["result-1".to_string()],
            claim_refs: vec!["claim-1".to_string()],
            provider: None,
            model: None,
            score: None,
        };
        let episodic = MemoryRecord {
            memory_id: "memory-episodic".to_string(),
            source: "cursor".to_string(),
            conversation_id: "conv-episodic".to_string(),
            workstream_id: Some("beagle-darwin-hpc-governance".to_string()),
            campaign_id: Some("expedition-002-hrv-aware".to_string()),
            program_id: Some("beagle-physio-symbolic-exocortex".to_string()),
            workspace_id: Some("beagle-cluster-pilot".to_string()),
            session_id: Some("ws-cluster-workspace-habitat".to_string()),
            turn_index: 2,
            role: "assistant".to_string(),
            text: "Session note after restart and handoff recovery in the current workspace.".to_string(),
            tags: vec!["session".to_string(), "handoff".to_string()],
            domain: Some("darwin-hpc".to_string()),
            repo_path: None,
            file_type: None,
            timestamp: now,
            physio_snapshot: None,
            experiment_flags: None,
            physio_snapshot_ref: None,
            result_refs: Vec::new(),
            claim_refs: Vec::new(),
            provider: None,
            model: None,
            score: None,
        };

        let reranked = RerankedResult {
            result_version: RERANKED_RESULT_VERSION.to_string(),
            profile_id: "b228-bounded-reranking-pilot".to_string(),
            query_type: "code".to_string(),
            routing_decision: RetrievalRoutingDecision {
                decision_version: RETRIEVAL_ROUTING_DECISION_VERSION.to_string(),
                router_version: RETRIEVAL_ROUTER_VERSION.to_string(),
                query_type: "code".to_string(),
                selected_route: "code".to_string(),
                selected_dense_backend: "voyage-code-3".to_string(),
                sparse_backend: "local-lexical".to_string(),
                payload_filters_present: true,
                compare_against_general: false,
                routing_source: "explicit-hint".to_string(),
                routing_reason: "task profile requested code".to_string(),
                note: "test".to_string(),
            },
            collection_name: "beagle_memory_local".to_string(),
            prerank_retrieval_mode: "code-dense+sparse-hybrid".to_string(),
            postrank_retrieval_mode: "code-dense+sparse-hybrid+rerank".to_string(),
            dense_backend: "voyage-code-3".to_string(),
            sparse_backend: "local-lexical".to_string(),
            reranker_backend: "voyage-rerank-2.5".to_string(),
            reranker_kind: "cross-encoder-api".to_string(),
            reranker_runtime_state: "pilot-active".to_string(),
            reranking_applied: true,
            top_k: 3,
            candidate_count: 3,
            applied_filters: RetrievalFilters {
                workstream_id: Some("beagle-darwin-hpc-governance".to_string()),
                campaign_id: Some("expedition-002-hrv-aware".to_string()),
                session_id: Some("ws-cluster-workspace-habitat".to_string()),
                source: None,
                role: None,
                domain: None,
                repo_path: None,
                file_type: None,
                tags: vec!["beagle-darwin-hpc-governance".to_string()],
            },
            prerank_hit_count: 3,
            postrank_hit_count: 3,
            prerank_top_memory_ids: vec![
                "memory-procedural".to_string(),
                "memory-semantic".to_string(),
                "memory-episodic".to_string(),
            ],
            postrank_top_memory_ids: vec![
                "memory-procedural".to_string(),
                "memory-semantic".to_string(),
                "memory-episodic".to_string(),
            ],
            relevance_proxy_before: 0.8,
            relevance_proxy_after: 0.9,
            latency: RerankingLatencyComparison {
                prerank_latency_ms: 10,
                rerank_latency_ms: 5,
                total_latency_ms: 15,
                latency_delta_ms: 5,
            },
            hits: vec![
                RerankedHit {
                    rank: 1,
                    prerank_rank: 1,
                    point: MemoryPoint {
                        point_version: crate::retrieval::MEMORY_POINT_VERSION.to_string(),
                        point_id: "point-procedural".to_string(),
                        collection_name: "beagle_memory_local".to_string(),
                        dense_vector_name: Some("beagle-memory-dense".to_string()),
                        payload: procedural.clone(),
                        note: "procedural".to_string(),
                    },
                    dense_score: Some(0.91),
                    sparse_score: Some(0.44),
                    hybrid_score: 0.86,
                    rerank_score: 0.94,
                },
                RerankedHit {
                    rank: 2,
                    prerank_rank: 2,
                    point: MemoryPoint {
                        point_version: crate::retrieval::MEMORY_POINT_VERSION.to_string(),
                        point_id: "point-semantic".to_string(),
                        collection_name: "beagle_memory_local".to_string(),
                        dense_vector_name: Some("beagle-memory-dense".to_string()),
                        payload: semantic.clone(),
                        note: "semantic".to_string(),
                    },
                    dense_score: Some(0.83),
                    sparse_score: Some(0.32),
                    hybrid_score: 0.75,
                    rerank_score: 0.82,
                },
                RerankedHit {
                    rank: 3,
                    prerank_rank: 3,
                    point: MemoryPoint {
                        point_version: crate::retrieval::MEMORY_POINT_VERSION.to_string(),
                        point_id: "point-episodic".to_string(),
                        collection_name: "beagle_memory_local".to_string(),
                        dense_vector_name: Some("beagle-memory-dense".to_string()),
                        payload: episodic.clone(),
                        note: "episodic".to_string(),
                    },
                    dense_score: Some(0.61),
                    sparse_score: Some(0.21),
                    hybrid_score: 0.55,
                    rerank_score: 0.53,
                },
            ],
            recommendation: RerankingRecommendation {
                query_type: "code".to_string(),
                reranker_backend: "voyage-rerank-2.5".to_string(),
                runtime_state: "pilot-active".to_string(),
                reranking_applied: true,
                top_hit_changed: false,
                relevance_proxy_before: 0.8,
                relevance_proxy_after: 0.9,
                latency_delta_ms: 5,
                recommendation: "keep-bounded-reranking-pilot-enabled".to_string(),
                note: "test".to_string(),
            },
            note: "test".to_string(),
        };

        let implementation_profile = context_budget_profile("implementation").expect("profile");
        let implementation_graphrag = GraphRagResult {
            result_version: GRAPHRAG_RESULT_VERSION.to_string(),
            query_type: "code".to_string(),
            query_mode: "local".to_string(),
            query_mode_source: "explicit-hint".to_string(),
            query_mode_reason: "implementation requested local".to_string(),
            collection_name: "beagle_memory_local".to_string(),
            retrieval_mode: "code-dense+sparse-hybrid+rerank".to_string(),
            routing_decision: reranked.routing_decision.clone(),
            dense_backend: "voyage-code-3".to_string(),
            sparse_backend: "local-lexical".to_string(),
            reranker_backend: "voyage-rerank-2.5".to_string(),
            reranking_applied: true,
            applied_filters: reranked.applied_filters.clone(),
            promotion_policy_id: "b232-memory-promotion-policy".to_string(),
            retention_policy_id: "b232-memory-retention-policy".to_string(),
            root_entity_type: Some("workstream".to_string()),
            root_entity_id: Some("beagle-darwin-hpc-governance".to_string()),
            program_id: Some("beagle-physio-symbolic-exocortex".to_string()),
            campaign_id: Some("expedition-002-hrv-aware".to_string()),
            workstream_id: Some("beagle-darwin-hpc-governance".to_string()),
            session_id: Some("ws-cluster-workspace-habitat".to_string()),
            support_memory_ids: vec!["memory-procedural".to_string(), "memory-semantic".to_string()],
            node_count: 4,
            edge_count: 3,
            nodes: Vec::new(),
            edges: Vec::new(),
            promoted_memories: Vec::new(),
            memory_hierarchy: None,
            note: "test".to_string(),
        };
        let implementation_temporal = TemporalQueryResult {
            result_version: TEMPORAL_QUERY_RESULT_VERSION.to_string(),
            schema_version: crate::temporal::TEMPORAL_MEMORY_VERSION.to_string(),
            truth_view: "current".to_string(),
            collection_name: "beagle_memory_local".to_string(),
            query_type: "code".to_string(),
            retrieval_mode: "code-dense+sparse-hybrid+rerank".to_string(),
            dense_backend: "voyage-code-3".to_string(),
            sparse_backend: "local-lexical".to_string(),
            reranker_backend: "voyage-rerank-2.5".to_string(),
            reranking_applied: true,
            applied_filters: reranked.applied_filters.clone(),
            temporal_root_entity_type: Some("workstream".to_string()),
            temporal_root_entity_id: Some("beagle-darwin-hpc-governance".to_string()),
            subject_refs: vec!["procedure:repo:beagle/crates/beagle-memory/src/compiler.rs".to_string()],
            track_count: 1,
            current_truth_count: 1,
            historical_truth_count: 1,
            contradiction_count: 1,
            top_current_memory_ids: vec!["memory-procedural".to_string()],
            top_historical_memory_ids: vec!["memory-semantic".to_string()],
            tracks: Vec::new(),
            contradictions: Vec::new(),
            note: "test".to_string(),
        };
        let manuscript_profile = context_budget_profile("manuscript").expect("profile");
        let manuscript_reranked = RerankedResult {
            query_type: "general".to_string(),
            routing_decision: RetrievalRoutingDecision {
                query_type: "general".to_string(),
                selected_route: "general".to_string(),
                selected_dense_backend: "voyage-4-large".to_string(),
                routing_reason: "task profile requested general".to_string(),
                ..reranked.routing_decision.clone()
            },
            prerank_retrieval_mode: "general-dense+sparse-hybrid".to_string(),
            postrank_retrieval_mode: "general-dense+sparse-hybrid+rerank".to_string(),
            dense_backend: "voyage-4-large".to_string(),
            recommendation: RerankingRecommendation {
                query_type: "general".to_string(),
                ..reranked.recommendation.clone()
            },
            ..reranked.clone()
        };
        let manuscript_graphrag = GraphRagResult {
            query_mode: "global".to_string(),
            query_mode_reason: "manuscript requested global".to_string(),
            ..implementation_graphrag.clone()
        };
        let manuscript_temporal = TemporalQueryResult {
            result_version: TEMPORAL_QUERY_RESULT_VERSION.to_string(),
            schema_version: crate::temporal::TEMPORAL_MEMORY_VERSION.to_string(),
            truth_view: "both".to_string(),
            query_type: "general".to_string(),
            dense_backend: "voyage-4-large".to_string(),
            retrieval_mode: "general-dense+sparse-hybrid+rerank".to_string(),
            ..implementation_temporal.clone()
        };

        let implementation = compiled_context_from_runtime(
            &crate::compiler::CompiledContextRequest {
                task_profile: "implementation".to_string(),
                tool_id: Some("codex".to_string()),
                query_text: "update compiler workflow and config path".to_string(),
                workstream_id: Some("beagle-darwin-hpc-governance".to_string()),
                campaign_id: Some("expedition-002-hrv-aware".to_string()),
                program_id: Some("beagle-physio-symbolic-exocortex".to_string()),
                workspace_id: Some("beagle-cluster-pilot".to_string()),
                session_id: Some("ws-cluster-workspace-habitat".to_string()),
                root_entity_type: Some("workstream".to_string()),
                root_entity_id: Some("beagle-darwin-hpc-governance".to_string()),
                repo_path: None,
                file_type: None,
                tags: vec!["beagle-darwin-hpc-governance".to_string()],
                rerank_hint: None,
            },
            &implementation_profile,
            &reranked,
            &implementation_graphrag,
            &implementation_temporal,
        );
        let manuscript = compiled_context_from_runtime(
            &crate::compiler::CompiledContextRequest {
                task_profile: "manuscript".to_string(),
                tool_id: Some("claude-code".to_string()),
                query_text: "assemble manuscript claim evidence context".to_string(),
                workstream_id: Some("beagle-darwin-hpc-governance".to_string()),
                campaign_id: Some("expedition-002-hrv-aware".to_string()),
                program_id: Some("beagle-physio-symbolic-exocortex".to_string()),
                workspace_id: Some("beagle-cluster-pilot".to_string()),
                session_id: Some("ws-cluster-workspace-habitat".to_string()),
                root_entity_type: Some("workstream".to_string()),
                root_entity_id: Some("beagle-darwin-hpc-governance".to_string()),
                repo_path: None,
                file_type: None,
                tags: vec!["beagle-darwin-hpc-governance".to_string()],
                rerank_hint: None,
            },
            &manuscript_profile,
            &manuscript_reranked,
            &manuscript_graphrag,
            &manuscript_temporal,
        );

        assert_eq!(implementation.task_profile, "implementation");
        assert_eq!(implementation.retrieval_query_type, "code");
        assert_eq!(implementation.graphrag_query_mode, "local");
        assert_eq!(implementation.temporal_truth_view, "current");
        assert_eq!(
            implementation.source_slices.first().map(|slice| slice.source_kind.as_str()),
            Some("procedural")
        );
        assert!(implementation.top_memory_ids.contains(&"memory-procedural".to_string()));
        assert!(implementation
            .source_slices
            .iter()
            .any(|slice| slice.source_kind == "temporal"));

        assert_eq!(manuscript.task_profile, "manuscript");
        assert_eq!(manuscript.retrieval_query_type, "general");
        assert_eq!(manuscript.graphrag_query_mode, "global");
        assert_eq!(manuscript.temporal_truth_view, "both");
        assert_eq!(
            manuscript.source_slices.first().map(|slice| slice.source_kind.as_str()),
            Some("semantic")
        );
        assert!(manuscript.top_memory_ids.contains(&"memory-semantic".to_string()));
        assert_ne!(
            implementation.budget_profile.profile_id,
            manuscript.budget_profile.profile_id
        );
    }

    #[test]
    fn temporal_query_from_runtime_preserves_current_and_historical_truth() {
        let root = env::temp_dir().join(format!("beagle-memory-temporal-{}", Uuid::new_v4()));
        let engine = MemoryEngine::new(None, local_test_config(root.as_path()));
        let earlier = Utc::now() - chrono::Duration::minutes(5);
        let later = Utc::now();
        let historical = MemoryRecord {
            memory_id: "memory-qa-historical".to_string(),
            source: "claude-code".to_string(),
            conversation_id: "conv-qa-historical".to_string(),
            workstream_id: Some("beagle-darwin-hpc-governance".to_string()),
            campaign_id: Some("expedition-002-hrv-aware".to_string()),
            program_id: Some("beagle-physio-symbolic-exocortex".to_string()),
            workspace_id: Some("beagle-cluster-pilot".to_string()),
            session_id: Some("ws-cluster-workspace-habitat".to_string()),
            turn_index: 0,
            role: "assistant".to_string(),
            text: "Claim expedition-002 QA state stayed blocked and not ready before validator alignment.".to_string(),
            tags: vec!["claim".to_string(), "temporal".to_string()],
            domain: Some("darwin-hpc".to_string()),
            repo_path: None,
            file_type: None,
            timestamp: earlier,
            physio_snapshot: None,
            experiment_flags: None,
            physio_snapshot_ref: None,
            result_refs: Vec::new(),
            claim_refs: vec!["claim:expedition-002-qa-state".to_string()],
            provider: None,
            model: None,
            score: None,
        };
        let current = MemoryRecord {
            memory_id: "memory-qa-current".to_string(),
            conversation_id: "conv-qa-current".to_string(),
            turn_index: 1,
            text: "Claim expedition-002 QA state is now green and ready after validator alignment.".to_string(),
            timestamp: later,
            ..historical.clone()
        };
        let reranked = RerankedResult {
            result_version: RERANKED_RESULT_VERSION.to_string(),
            profile_id: "b228-bounded-reranking-pilot".to_string(),
            query_type: "general".to_string(),
            routing_decision: RetrievalRoutingDecision {
                decision_version: RETRIEVAL_ROUTING_DECISION_VERSION.to_string(),
                router_version: RETRIEVAL_ROUTER_VERSION.to_string(),
                query_type: "general".to_string(),
                selected_route: "general".to_string(),
                selected_dense_backend: "voyage-4-large".to_string(),
                sparse_backend: "local-lexical".to_string(),
                payload_filters_present: true,
                compare_against_general: false,
                routing_source: "explicit-hint".to_string(),
                routing_reason: "test temporal route".to_string(),
                note: "test".to_string(),
            },
            collection_name: "beagle_memory_local".to_string(),
            prerank_retrieval_mode: "general-dense+sparse-hybrid".to_string(),
            postrank_retrieval_mode: "general-dense+sparse-hybrid+rerank".to_string(),
            dense_backend: "voyage-4-large".to_string(),
            sparse_backend: "local-lexical".to_string(),
            reranker_backend: "voyage-rerank-2.5".to_string(),
            reranker_kind: "cross-encoder-api".to_string(),
            reranker_runtime_state: "pilot-active".to_string(),
            reranking_applied: true,
            top_k: 3,
            candidate_count: 1,
            applied_filters: RetrievalFilters {
                workstream_id: Some("beagle-darwin-hpc-governance".to_string()),
                campaign_id: Some("expedition-002-hrv-aware".to_string()),
                session_id: None,
                source: None,
                role: None,
                domain: None,
                repo_path: None,
                file_type: None,
                tags: vec!["beagle-darwin-hpc-governance".to_string()],
            },
            prerank_hit_count: 1,
            postrank_hit_count: 1,
            prerank_top_memory_ids: vec!["memory-qa-current".to_string()],
            postrank_top_memory_ids: vec!["memory-qa-current".to_string()],
            relevance_proxy_before: 0.7,
            relevance_proxy_after: 0.8,
            latency: RerankingLatencyComparison {
                prerank_latency_ms: 12,
                rerank_latency_ms: 7,
                total_latency_ms: 19,
                latency_delta_ms: 7,
            },
            hits: vec![RerankedHit {
                rank: 1,
                prerank_rank: 1,
                point: MemoryPoint {
                    point_version: crate::retrieval::MEMORY_POINT_VERSION.to_string(),
                    point_id: "point-qa-current".to_string(),
                    collection_name: "beagle_memory_local".to_string(),
                    dense_vector_name: Some("beagle-memory-dense".to_string()),
                    payload: current.clone(),
                    note: "current".to_string(),
                },
                dense_score: Some(0.92),
                sparse_score: Some(0.33),
                hybrid_score: 0.88,
                rerank_score: 0.94,
            }],
            recommendation: RerankingRecommendation {
                query_type: "general".to_string(),
                reranker_backend: "voyage-rerank-2.5".to_string(),
                runtime_state: "pilot-active".to_string(),
                reranking_applied: true,
                top_hit_changed: false,
                relevance_proxy_before: 0.7,
                relevance_proxy_after: 0.8,
                latency_delta_ms: 7,
                recommendation: "keep-bounded-reranking-pilot-enabled".to_string(),
                note: "test".to_string(),
            },
            note: "test".to_string(),
        };
        let result = temporal_query_from_runtime(
            &crate::temporal::TemporalQuery {
                query_version: crate::temporal::TEMPORAL_QUERY_VERSION.to_string(),
                query_text: "qa state across time".to_string(),
                truth_view: "both".to_string(),
                top_k: 3,
                dense_enabled: true,
                sparse_enabled: true,
                dense_weight: 0.65,
                sparse_weight: 0.35,
                filters: RetrievalFilters {
                    workstream_id: Some("beagle-darwin-hpc-governance".to_string()),
                    campaign_id: Some("expedition-002-hrv-aware".to_string()),
                    session_id: None,
                    source: None,
                    role: None,
                    domain: None,
                    repo_path: None,
                    file_type: None,
                    tags: vec![],
                },
                root_entity_type: Some("workstream".to_string()),
                root_entity_id: Some("beagle-darwin-hpc-governance".to_string()),
                subject_refs: vec!["claim:expedition-002-qa-state".to_string()],
                include_contradictions: true,
                query_type_hint: Some("general".to_string()),
                query_mode_hint: None,
                rerank_hint: None,
            },
            "both",
            &engine.retrieval_collection(),
            &reranked,
            &[historical.clone(), current.clone()],
        );

        assert_eq!(result.truth_view, "both");
        assert_eq!(result.current_truth_count, 1);
        assert_eq!(result.historical_truth_count, 1);
        assert_eq!(result.contradiction_count, 1);
        assert_eq!(result.top_current_memory_ids, vec!["memory-qa-current".to_string()]);
        assert_eq!(
            result.top_historical_memory_ids,
            vec!["memory-qa-historical".to_string()]
        );
        assert_eq!(result.tracks.len(), 1);
        assert_eq!(result.tracks[0].version_count, 2);
        assert_eq!(result.tracks[0].current_memory_id, "memory-qa-current");
    }

    #[test]
    fn temporal_query_from_runtime_marks_explicit_contradiction() {
        let now = Utc::now();
        let current = MemoryRecord {
            memory_id: "memory-current".to_string(),
            source: "claude-code".to_string(),
            conversation_id: "conv-current".to_string(),
            workstream_id: Some("beagle-darwin-hpc-governance".to_string()),
            campaign_id: Some("expedition-002-hrv-aware".to_string()),
            program_id: Some("beagle-physio-symbolic-exocortex".to_string()),
            workspace_id: Some("beagle-cluster-pilot".to_string()),
            session_id: Some("ws-cluster-workspace-habitat".to_string()),
            turn_index: 1,
            role: "assistant".to_string(),
            text: "Claim QA state is green and ready.".to_string(),
            tags: vec!["claim".to_string(), "temporal".to_string()],
            domain: Some("darwin-hpc".to_string()),
            repo_path: None,
            file_type: None,
            timestamp: now,
            physio_snapshot: None,
            experiment_flags: None,
            physio_snapshot_ref: None,
            result_refs: Vec::new(),
            claim_refs: vec!["claim:expedition-002-qa-state".to_string()],
            provider: None,
            model: None,
            score: None,
        };
        let prior = MemoryRecord {
            memory_id: "memory-prior".to_string(),
            conversation_id: "conv-prior".to_string(),
            turn_index: 0,
            text: "Claim QA state was blocked and not ready.".to_string(),
            timestamp: now - chrono::Duration::minutes(10),
            ..current.clone()
        };

        let contradiction = detect_temporal_contradiction(&current, &prior)
            .expect("contradiction should be detected");
        assert_eq!(contradiction.0, "explicit-state-flip");
        assert!(contradiction.1.contains("blocked"));
        assert!(contradiction.1.contains("ready"));
    }

    #[test]
    fn temporal_query_from_runtime_uses_root_scoped_records_when_hits_miss_subject() {
        let root = env::temp_dir().join(format!(
            "beagle-memory-temporal-root-scope-{}",
            Uuid::new_v4()
        ));
        let engine = MemoryEngine::new(None, local_test_config(root.as_path()));
        let earlier = Utc::now() - chrono::Duration::minutes(10);
        let later = Utc::now();
        let historical = MemoryRecord {
            memory_id: "memory-root-historical".to_string(),
            source: "claude-code".to_string(),
            conversation_id: "conv-root-historical".to_string(),
            workstream_id: Some("beagle-darwin-hpc-governance".to_string()),
            campaign_id: Some("expedition-002-hrv-aware".to_string()),
            program_id: Some("beagle-physio-symbolic-exocortex".to_string()),
            workspace_id: Some("beagle-cluster-pilot".to_string()),
            session_id: Some("ws-cluster-workspace-habitat".to_string()),
            turn_index: 0,
            role: "assistant".to_string(),
            text: "Claim expedition-002 QA state stayed blocked and not ready before validator alignment.".to_string(),
            tags: vec!["claim".to_string(), "temporal".to_string()],
            domain: Some("darwin-hpc".to_string()),
            repo_path: None,
            file_type: None,
            timestamp: earlier,
            physio_snapshot: None,
            experiment_flags: None,
            physio_snapshot_ref: None,
            result_refs: Vec::new(),
            claim_refs: vec!["claim:expedition-002-qa-state".to_string()],
            provider: None,
            model: None,
            score: None,
        };
        let current = MemoryRecord {
            memory_id: "memory-root-current".to_string(),
            conversation_id: "conv-root-current".to_string(),
            turn_index: 1,
            text: "Claim expedition-002 QA state is now green and ready after validator alignment.".to_string(),
            timestamp: later,
            ..historical.clone()
        };
        let unrelated = MemoryRecord {
            memory_id: "memory-unrelated".to_string(),
            conversation_id: "conv-unrelated".to_string(),
            turn_index: 3,
            text: "Manuscript support context should lean editorial and review artifacts.".to_string(),
            tags: vec!["manuscript".to_string(), "editorial".to_string()],
            claim_refs: vec!["claim:b224-retrieval-aware-tool-context".to_string()],
            timestamp: later + chrono::Duration::seconds(5),
            ..historical.clone()
        };
        let reranked = RerankedResult {
            result_version: RERANKED_RESULT_VERSION.to_string(),
            profile_id: "b228-bounded-reranking-pilot".to_string(),
            query_type: "general".to_string(),
            routing_decision: RetrievalRoutingDecision {
                decision_version: RETRIEVAL_ROUTING_DECISION_VERSION.to_string(),
                router_version: RETRIEVAL_ROUTER_VERSION.to_string(),
                query_type: "general".to_string(),
                selected_route: "general".to_string(),
                selected_dense_backend: "voyage-4-large".to_string(),
                sparse_backend: "local-lexical".to_string(),
                payload_filters_present: true,
                compare_against_general: false,
                routing_source: "explicit-hint".to_string(),
                routing_reason: "test temporal root scope".to_string(),
                note: "test".to_string(),
            },
            collection_name: "beagle_memory_local".to_string(),
            prerank_retrieval_mode: "general-dense+sparse-hybrid".to_string(),
            postrank_retrieval_mode: "general-dense+sparse-hybrid+rerank".to_string(),
            dense_backend: "voyage-4-large".to_string(),
            sparse_backend: "local-lexical".to_string(),
            reranker_backend: "voyage-rerank-2.5".to_string(),
            reranker_kind: "cross-encoder-api".to_string(),
            reranker_runtime_state: "pilot-active".to_string(),
            reranking_applied: true,
            top_k: 3,
            candidate_count: 1,
            applied_filters: RetrievalFilters {
                workstream_id: Some("beagle-darwin-hpc-governance".to_string()),
                campaign_id: Some("expedition-002-hrv-aware".to_string()),
                session_id: None,
                source: None,
                role: None,
                domain: None,
                repo_path: None,
                file_type: None,
                tags: vec!["beagle-darwin-hpc-governance".to_string()],
            },
            prerank_hit_count: 1,
            postrank_hit_count: 1,
            prerank_top_memory_ids: vec!["memory-unrelated".to_string()],
            postrank_top_memory_ids: vec!["memory-unrelated".to_string()],
            relevance_proxy_before: 0.4,
            relevance_proxy_after: 0.5,
            latency: RerankingLatencyComparison {
                prerank_latency_ms: 12,
                rerank_latency_ms: 7,
                total_latency_ms: 19,
                latency_delta_ms: 7,
            },
            hits: vec![RerankedHit {
                rank: 1,
                prerank_rank: 1,
                point: MemoryPoint {
                    point_version: crate::retrieval::MEMORY_POINT_VERSION.to_string(),
                    point_id: "point-unrelated".to_string(),
                    collection_name: "beagle_memory_local".to_string(),
                    dense_vector_name: Some("beagle-memory-dense".to_string()),
                    payload: unrelated.clone(),
                    note: "unrelated".to_string(),
                },
                dense_score: Some(0.91),
                sparse_score: Some(0.22),
                hybrid_score: 0.83,
                rerank_score: 0.88,
            }],
            recommendation: RerankingRecommendation {
                query_type: "general".to_string(),
                reranker_backend: "voyage-rerank-2.5".to_string(),
                runtime_state: "pilot-active".to_string(),
                reranking_applied: true,
                top_hit_changed: false,
                relevance_proxy_before: 0.4,
                relevance_proxy_after: 0.5,
                latency_delta_ms: 7,
                recommendation: "keep-bounded-reranking-pilot-enabled".to_string(),
                note: "test".to_string(),
            },
            note: "test".to_string(),
        };

        let result = temporal_query_from_runtime(
            &crate::temporal::TemporalQuery {
                query_version: crate::temporal::TEMPORAL_QUERY_VERSION.to_string(),
                query_text: "workstream context temporal summary".to_string(),
                truth_view: "both".to_string(),
                top_k: 3,
                dense_enabled: true,
                sparse_enabled: true,
                dense_weight: 0.65,
                sparse_weight: 0.35,
                filters: RetrievalFilters {
                    workstream_id: Some("beagle-darwin-hpc-governance".to_string()),
                    campaign_id: Some("expedition-002-hrv-aware".to_string()),
                    session_id: None,
                    source: None,
                    role: None,
                    domain: None,
                    repo_path: None,
                    file_type: None,
                    tags: vec![],
                },
                root_entity_type: Some("workstream".to_string()),
                root_entity_id: Some("beagle-darwin-hpc-governance".to_string()),
                subject_refs: Vec::new(),
                include_contradictions: true,
                query_type_hint: Some("general".to_string()),
                query_mode_hint: None,
                rerank_hint: None,
            },
            "both",
            &engine.retrieval_collection(),
            &reranked,
            &[historical.clone(), current.clone(), unrelated.clone()],
        );

        assert_eq!(result.truth_view, "both");
        assert!(result.subject_refs.contains(&"claim:expedition-002-qa-state".to_string()));
        assert_eq!(result.current_truth_count, 2);
        assert_eq!(result.historical_truth_count, 1);
        assert_eq!(result.contradiction_count, 1);
        assert!(result.top_current_memory_ids.contains(&"memory-root-current".to_string()));
        assert!(result.top_historical_memory_ids.contains(&"memory-root-historical".to_string()));
    }
}
