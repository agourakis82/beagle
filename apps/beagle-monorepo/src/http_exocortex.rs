//! Cluster-first Exocortex API.
//!
//! This module is intentionally small and append-only. The cluster owns the
//! canonical Chronoself/OmniMemory/TemporalAI state, while Apple clients and
//! MCP agents render or mutate it through this contract.

use axum::{
    extract::{Query, State},
    http::StatusCode,
    routing::{get, post},
    Json, Router,
};
use beagle_config::beagle_data_dir;
use chrono::Utc;
use serde::{Deserialize, Serialize};
use sha2::{Digest, Sha256};
use std::{
    fs::{self, File, OpenOptions},
    io::{BufRead, BufReader, Write},
    path::PathBuf,
};
use tracing::error;
use uuid::Uuid;

use crate::http::AppState;

const EXOCORTEX_DIR: &str = "exocortex";
const CHRONOSELF_LOG: &str = "chronoself_commits.jsonl";
const OMNIMEMORY_LOG: &str = "omni_conversations.jsonl";
const TEMPORAL_LOG: &str = "temporal_analyses.jsonl";
const AUDIT_LOG: &str = "audit_events.jsonl";
const MEMORY_EVENTS_LOG: &str = "memory_events.jsonl";
const MEMORY_EPISODES_LOG: &str = "memory_episodes.jsonl";
const MEMORY_ATOMS_LOG: &str = "memory_atoms.jsonl";
const MEMORY_PROJECTION_RUNS_LOG: &str = "memory_projection_runs.jsonl";
const AGENT_OBSERVATIONS_LOG: &str = "agent_observations.jsonl";
const PROJECT_STATES_LOG: &str = "project_states.jsonl";
const CAUSAL_HYPOTHESES_LOG: &str = "causal_hypotheses.jsonl";
const CURRENT_SELF_SNAPSHOT: &str = "current_self.json";
const HOME_SNAPSHOT: &str = "home_snapshot.json";
const MEMORY_PROJECTION_SCHEMA: &str = "beagle-memory-projection-v1.2";

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ContextSnapshot {
    #[serde(default)]
    pub health_ref: Option<String>,
    #[serde(default)]
    pub active_project_ids: Vec<String>,
    #[serde(default)]
    pub recent_decision_ids: Vec<String>,
    #[serde(default)]
    pub energy_level: Option<f64>,
    #[serde(default)]
    pub emotional_valence: Option<f64>,
    #[serde(default)]
    pub platform: Option<String>,
    #[serde(default)]
    pub target_hardware: Option<TargetHardware>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct TargetHardware {
    #[serde(default)]
    pub phone: Option<String>,
    #[serde(default)]
    pub watch: Option<String>,
    #[serde(default)]
    pub tablet: Option<String>,
    #[serde(default)]
    pub desktop: Option<String>,
    #[serde(default)]
    pub spatial: Option<String>,
    #[serde(default)]
    pub notes: Vec<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize, Default)]
pub struct IdentityDelta {
    #[serde(default)]
    pub beliefs_added: Vec<String>,
    #[serde(default)]
    pub beliefs_removed: Vec<String>,
    #[serde(default)]
    pub values_changed: Vec<ValueChange>,
    #[serde(default)]
    pub cognitive_style_shift: Option<String>,
    #[serde(default)]
    pub priority_reordering: Vec<String>,
    #[serde(default)]
    pub product_principles: Vec<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ValueChange {
    pub value: String,
    pub old_strength: f64,
    pub new_strength: f64,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ChronoselfCommit {
    pub id: String,
    pub created_at: String,
    pub self_version: String,
    #[serde(default)]
    pub parent_commit_ids: Vec<String>,
    pub user_id: String,
    pub context_snapshot: ContextSnapshot,
    pub identity_delta: IdentityDelta,
    pub trigger_type: String,
    pub hash: String,
    pub confidence: f64,
    #[serde(default)]
    pub source_refs: Vec<String>,
    #[serde(default)]
    pub summary: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SelfVersion {
    pub id: String,
    pub label: String,
    pub period_start: String,
    #[serde(default)]
    pub period_end: Option<String>,
    #[serde(default)]
    pub dominant_beliefs: Vec<String>,
    #[serde(default)]
    pub core_values: Vec<CoreValue>,
    pub cognitive_style: String,
    pub risk_tolerance: f64,
    #[serde(default)]
    pub source_commit_id: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct CoreValue {
    pub name: String,
    pub strength: f64,
}

#[derive(Debug, Clone, Serialize, Deserialize, Default)]
pub struct OmniExtraction {
    #[serde(default)]
    pub key_insights: Vec<String>,
    #[serde(default)]
    pub decisions: Vec<String>,
    #[serde(default)]
    pub hypotheses: Vec<String>,
    #[serde(default)]
    pub belief_changes: Vec<String>,
    #[serde(default)]
    pub emotional_state: Option<serde_json::Value>,
    #[serde(default)]
    pub identity_signals: Option<serde_json::Value>,
    #[serde(default)]
    pub projects_mentioned: Vec<String>,
    #[serde(default)]
    pub unresolved_questions: Vec<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct OmniConversation {
    pub id: String,
    pub source_platform: String,
    pub imported_at: String,
    #[serde(default)]
    pub session_id: Option<String>,
    #[serde(default)]
    pub original_date: Option<String>,
    pub raw_content_ref: String,
    pub extracted: OmniExtraction,
    #[serde(default)]
    pub linked_chronoself_commits: Vec<String>,
    #[serde(default)]
    pub linked_memory_events: Vec<String>,
    pub confidence_score: f64,
    #[serde(default)]
    pub title: Option<String>,
    #[serde(default = "default_sensitive_privacy_class")]
    pub privacy_class: String,
    #[serde(default)]
    pub tags: Vec<String>,
    #[serde(default)]
    pub metadata: serde_json::Value,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct MemoryRelation {
    pub subject: String,
    pub predicate: String,
    pub object: String,
    pub confidence: f64,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct MemoryEpisode {
    pub id: String,
    pub created_at: String,
    pub source: String,
    #[serde(default)]
    pub source_platform: Option<String>,
    #[serde(default)]
    pub session_id: Option<String>,
    pub source_ref: String,
    pub content_hash: String,
    pub privacy_class: String,
    #[serde(default)]
    pub provenance: serde_json::Value,
    #[serde(default)]
    pub tags: Vec<String>,
    #[serde(default)]
    pub title: Option<String>,
    #[serde(default)]
    pub linked_chronoself_commits: Vec<String>,
    #[serde(default)]
    pub occurred_at: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct MemoryAtom {
    pub id: String,
    pub created_at: String,
    pub episode_id: String,
    pub atom_type: String,
    pub text: String,
    pub normalized_text: String,
    #[serde(default)]
    pub source_refs: Vec<String>,
    #[serde(default)]
    pub relations: Vec<MemoryRelation>,
    #[serde(default)]
    pub tags: Vec<String>,
    pub confidence: f64,
    pub privacy_class: String,
    #[serde(default)]
    pub occurred_at: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct MemoryProjectionRun {
    pub id: String,
    pub created_at: String,
    pub schema_version: String,
    pub source_count: usize,
    pub episodes_created: usize,
    pub atoms_created: usize,
    pub duplicates: usize,
    #[serde(default)]
    pub errors: Vec<String>,
    pub projection_hash: String,
    pub status: String,
    pub degraded_reason: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct MemoryProjectionStatus {
    pub status: String,
    pub schema_version: String,
    pub episode_count: usize,
    pub atom_count: usize,
    #[serde(default)]
    pub latest_run: Option<MemoryProjectionRun>,
    pub freshness: String,
    pub retrieval_mode: String,
    pub degraded_reason: String,
}

#[derive(Debug, Clone, Deserialize)]
pub struct ProjectMemoryRequest {
    #[serde(default)]
    pub rebuild: bool,
    #[serde(default)]
    pub source_refs: Vec<String>,
}

#[derive(Debug, Clone, Deserialize)]
pub struct GraphRagQueryRequest {
    pub query: String,
    #[serde(default)]
    pub scope: Option<String>,
    #[serde(default)]
    pub max_items: Option<usize>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct GraphRagEvidence {
    pub atom_id: String,
    pub episode_id: String,
    pub atom_type: String,
    pub text: String,
    pub score: f64,
    #[serde(default)]
    pub source_refs: Vec<String>,
    #[serde(default)]
    pub provenance: serde_json::Value,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct GraphRagTemporalContext {
    pub newest_evidence_at: Option<String>,
    pub oldest_evidence_at: Option<String>,
    pub matched_episode_count: usize,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct GraphRagQueryResponse {
    pub summary: String,
    #[serde(default)]
    pub evidence: Vec<GraphRagEvidence>,
    #[serde(default)]
    pub atoms: Vec<MemoryAtom>,
    #[serde(default)]
    pub episodes: Vec<MemoryEpisode>,
    #[serde(default)]
    pub relations: Vec<MemoryRelation>,
    pub temporal_context: GraphRagTemporalContext,
    #[serde(default)]
    pub provenance: serde_json::Value,
    pub confidence: f64,
    #[serde(default)]
    pub degraded_reason: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct TemporalPhase {
    pub name: String,
    pub period_start: String,
    #[serde(default)]
    pub period_end: Option<String>,
    #[serde(default)]
    pub characteristics: Vec<String>,
    #[serde(default)]
    pub self_version_ref: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct TurningPoint {
    pub date: String,
    pub description: String,
    #[serde(default)]
    pub cause: Option<String>,
    #[serde(default)]
    pub self_version_before: Option<String>,
    #[serde(default)]
    pub self_version_after: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct RecurringPattern {
    pub description: String,
    #[serde(default)]
    pub frequency_days: Option<f64>,
    pub confidence: f64,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct TemporalAnalysis {
    pub id: String,
    pub created_at: String,
    pub topic: String,
    pub time_range_start: String,
    pub time_range_end: String,
    #[serde(default)]
    pub phases: Vec<TemporalPhase>,
    #[serde(default)]
    pub turning_points: Vec<TurningPoint>,
    #[serde(default)]
    pub recurring_pattern: Option<RecurringPattern>,
    #[serde(default)]
    pub causal_hypothesis: Option<String>,
    pub recommendation: String,
    #[serde(default)]
    pub llm_model_used: Option<String>,
    pub confidence_score: f64,
    #[serde(default)]
    pub source_refs: Vec<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct AuditEvent {
    pub id: String,
    pub created_at: String,
    pub client_id: String,
    pub action: String,
    #[serde(default)]
    pub tool_name: Option<String>,
    pub risk_level: String,
    #[serde(default)]
    pub required_scopes: Vec<String>,
    #[serde(default)]
    pub granted_scopes: Vec<String>,
    pub status: String,
    pub source: String,
    #[serde(default)]
    pub target_ref: Option<String>,
    #[serde(default)]
    pub summary: Option<String>,
    #[serde(default)]
    pub metadata: serde_json::Value,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct MemoryEvent {
    pub id: String,
    pub created_at: String,
    pub source: String,
    pub kind: String,
    #[serde(default)]
    pub content_ref: Option<String>,
    pub summary: String,
    #[serde(default)]
    pub tags: Vec<String>,
    #[serde(default)]
    pub metadata: serde_json::Value,
    #[serde(default)]
    pub linked_chronoself_commits: Vec<String>,
    pub confidence: f64,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct AgentObservation {
    pub id: String,
    pub created_at: String,
    pub agent_id: String,
    pub project_ref: String,
    pub observation: String,
    #[serde(default)]
    pub source_refs: Vec<String>,
    pub confidence: f64,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ProjectState {
    pub id: String,
    pub name: String,
    pub status: String,
    #[serde(default)]
    pub recent_events: Vec<String>,
    #[serde(default)]
    pub next_actions: Vec<String>,
    #[serde(default)]
    pub linked_memories: Vec<String>,
    #[serde(default)]
    pub last_interaction_at: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct CausalHypothesis {
    pub id: String,
    pub created_at: String,
    pub cause_candidate: String,
    pub effect_candidate: String,
    #[serde(default)]
    pub evidence: Vec<String>,
    pub confidence: f64,
    #[serde(default)]
    pub alternative_explanations: Vec<String>,
    pub last_updated: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct AgentContext {
    pub active_sessions: usize,
    #[serde(default)]
    pub recent_observations: Vec<String>,
    #[serde(default)]
    pub last_agent_write: Option<String>,
    pub mcp_status: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct TrustContext {
    pub mcp_status: String,
    #[serde(default)]
    pub active_scopes: Vec<String>,
    pub audit_freshness: String,
    pub destructive_actions: String,
    #[serde(default)]
    pub tool_manifest_hash: Option<String>,
    #[serde(default)]
    pub last_audit_event_id: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub memory_projection_status: Option<MemoryProjectionStatus>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ExocortexHomeSnapshot {
    pub generated_at: String,
    pub today_brief: String,
    pub current_self: SelfVersion,
    #[serde(default)]
    pub memory_signals: Vec<String>,
    #[serde(default)]
    pub open_loops: Vec<String>,
    #[serde(default)]
    pub active_project_ref: Option<String>,
    #[serde(default)]
    pub body_context: Option<String>,
    pub recommended_next_action: String,
    pub cluster_truth: String,
    pub omnimemory_status: String,
    #[serde(default)]
    pub temporal_phase: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub agent_context: Option<AgentContext>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub trust_context: Option<TrustContext>,
}

#[derive(Debug, Deserialize)]
pub struct HomeQuery {
    #[serde(default)]
    pub active_project_slug: Option<String>,
    #[serde(default)]
    pub platform: Option<String>,
}

#[derive(Debug, Deserialize)]
pub struct LimitQuery {
    #[serde(default)]
    pub limit: Option<usize>,
}

#[derive(Debug, Deserialize)]
pub struct CreateCommitRequest {
    #[serde(default)]
    pub user_id: Option<String>,
    #[serde(default)]
    pub self_version: Option<String>,
    #[serde(default)]
    pub parent_commit_ids: Vec<String>,
    #[serde(default)]
    pub context_snapshot: Option<ContextSnapshot>,
    #[serde(default)]
    pub identity_delta: IdentityDelta,
    #[serde(default)]
    pub trigger_type: Option<String>,
    #[serde(default)]
    pub confidence: Option<f64>,
    #[serde(default)]
    pub source_refs: Vec<String>,
    #[serde(default)]
    pub summary: Option<String>,
}

#[derive(Debug, Deserialize)]
pub struct ImportConversationRequest {
    pub source_platform: String,
    #[serde(default)]
    pub session_id: Option<String>,
    #[serde(default)]
    pub original_date: Option<String>,
    pub raw_content: String,
    #[serde(default)]
    pub title: Option<String>,
    #[serde(default)]
    pub tags: Vec<String>,
    #[serde(default)]
    pub extracted: Option<OmniExtraction>,
    #[serde(default)]
    pub confidence_score: Option<f64>,
    #[serde(default)]
    pub create_chronoself_commit: Option<bool>,
    #[serde(default)]
    pub privacy_class: Option<String>,
    #[serde(default)]
    pub metadata: Option<serde_json::Value>,
}

#[derive(Debug, Clone, Deserialize)]
pub struct AssistedImportTurn {
    pub role: String,
    pub content: String,
    #[serde(default)]
    pub timestamp: Option<String>,
    #[serde(default)]
    pub model: Option<String>,
}

#[derive(Debug, Clone, Deserialize)]
pub struct AssistedImportBatchRequest {
    pub source_platform: String,
    #[serde(default = "default_assisted_source_surface")]
    pub source_surface: String,
    #[serde(default = "default_assisted_import_scope")]
    pub import_scope: String,
    pub session_id: String,
    #[serde(default)]
    pub project_ref: Option<String>,
    #[serde(default = "default_one_u32")]
    pub batch_index: u32,
    #[serde(default = "default_one_u32")]
    pub batch_total: u32,
    #[serde(default)]
    pub turns: Vec<AssistedImportTurn>,
    #[serde(default)]
    pub tags: Vec<String>,
    #[serde(default)]
    pub metadata: serde_json::Value,
    #[serde(default)]
    pub coverage: serde_json::Value,
    #[serde(default)]
    pub extracted: Option<OmniExtraction>,
    #[serde(default)]
    pub privacy_class: Option<String>,
    #[serde(default)]
    pub title: Option<String>,
    #[serde(default)]
    pub original_date: Option<String>,
    #[serde(default)]
    pub confidence_score: Option<f64>,
    #[serde(default)]
    pub create_chronoself_commit: Option<bool>,
}

#[derive(Debug, Clone, Serialize)]
pub struct AssistedImportBatchResponse {
    pub status: String,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub reason: Option<String>,
    pub session_id: String,
    pub source_platform: String,
    pub source_surface: String,
    pub batch_index: u32,
    pub batch_total: u32,
    pub privacy_class: String,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub omnimemory: Option<OmniConversation>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub projection: Option<MemoryProjectionRun>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub memory_event: Option<MemoryEvent>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub audit_event: Option<AuditEvent>,
}

#[derive(Debug, Deserialize)]
pub struct TemporalAnalyzeRequest {
    pub topic: String,
    #[serde(default)]
    pub days_back: Option<u32>,
    #[serde(default)]
    pub time_range_start: Option<String>,
    #[serde(default)]
    pub time_range_end: Option<String>,
}

#[derive(Debug, Deserialize)]
pub struct CreateAuditEventRequest {
    #[serde(default)]
    pub client_id: Option<String>,
    #[serde(default)]
    pub action: Option<String>,
    #[serde(default)]
    pub tool_name: Option<String>,
    #[serde(default)]
    pub risk_level: Option<String>,
    #[serde(default)]
    pub required_scopes: Vec<String>,
    #[serde(default)]
    pub granted_scopes: Vec<String>,
    #[serde(default)]
    pub status: Option<String>,
    #[serde(default)]
    pub source: Option<String>,
    #[serde(default)]
    pub target_ref: Option<String>,
    #[serde(default)]
    pub summary: Option<String>,
    #[serde(default)]
    pub metadata: Option<serde_json::Value>,
}

#[derive(Debug, Deserialize)]
pub struct CreateMemoryEventRequest {
    #[serde(default)]
    pub source: Option<String>,
    #[serde(default)]
    pub kind: Option<String>,
    #[serde(default)]
    pub content_ref: Option<String>,
    #[serde(default)]
    pub summary: Option<String>,
    #[serde(default)]
    pub tags: Vec<String>,
    #[serde(default)]
    pub metadata: Option<serde_json::Value>,
    #[serde(default)]
    pub linked_chronoself_commits: Vec<String>,
    #[serde(default)]
    pub confidence: Option<f64>,
}

#[derive(Debug, Serialize)]
pub struct CommitListResponse {
    pub commits: Vec<ChronoselfCommit>,
}

#[derive(Debug, Serialize)]
pub struct AuditEventListResponse {
    pub events: Vec<AuditEvent>,
}

#[derive(Debug, Serialize)]
pub struct MemoryEventListResponse {
    pub events: Vec<MemoryEvent>,
}

#[derive(Debug, Serialize)]
pub struct ProjectStateListResponse {
    pub projects: Vec<ProjectState>,
}

pub fn exocortex_routes() -> Router<AppState> {
    Router::new()
        .route("/api/exocortex/v1/home", get(exocortex_home_handler))
        .route(
            "/api/exocortex/v1/chronoself/current",
            get(chronoself_current_handler),
        )
        .route(
            "/api/exocortex/v1/chronoself/commits",
            get(chronoself_commits_handler).post(chronoself_create_commit_handler),
        )
        .route(
            "/api/exocortex/v1/omnimemory/imports",
            post(omnimemory_import_handler),
        )
        .route(
            "/api/exocortex/v1/memory/assisted-import",
            post(memory_assisted_import_handler),
        )
        .route(
            "/api/exocortex/v1/temporal/analyze",
            post(temporal_analyze_handler),
        )
        .route(
            "/api/exocortex/v1/audit/events",
            get(audit_events_handler).post(audit_event_create_handler),
        )
        .route(
            "/api/exocortex/v1/memory/events",
            get(memory_events_handler).post(memory_event_create_handler),
        )
        .route(
            "/api/exocortex/v1/memory/project",
            post(memory_project_handler),
        )
        .route(
            "/api/exocortex/v1/memory/projection/status",
            get(memory_projection_status_handler),
        )
        .route(
            "/api/exocortex/v1/graphrag/query",
            post(graphrag_query_handler),
        )
        .route(
            "/api/exocortex/v1/projects/active",
            get(active_projects_handler),
        )
}

async fn exocortex_home_handler(
    State(_state): State<AppState>,
    Query(query): Query<HomeQuery>,
) -> Result<Json<ExocortexHomeSnapshot>, StatusCode> {
    let repo = ExocortexRepository::default();
    repo.ensure().map_err(internal_error)?;
    let snapshot = repo.build_home_snapshot(query).map_err(internal_error)?;
    Ok(Json(snapshot))
}

async fn chronoself_current_handler(
    State(_state): State<AppState>,
) -> Result<Json<SelfVersion>, StatusCode> {
    let repo = ExocortexRepository::default();
    repo.ensure().map_err(internal_error)?;
    let current = repo.current_self().map_err(internal_error)?;
    Ok(Json(current))
}

async fn chronoself_commits_handler(
    State(_state): State<AppState>,
    Query(query): Query<LimitQuery>,
) -> Result<Json<CommitListResponse>, StatusCode> {
    let repo = ExocortexRepository::default();
    repo.ensure().map_err(internal_error)?;
    let commits = repo
        .read_recent_jsonl::<ChronoselfCommit>(CHRONOSELF_LOG, query.limit.unwrap_or(50))
        .map_err(internal_error)?;
    Ok(Json(CommitListResponse { commits }))
}

async fn chronoself_create_commit_handler(
    State(_state): State<AppState>,
    Json(req): Json<CreateCommitRequest>,
) -> Result<Json<ChronoselfCommit>, StatusCode> {
    let repo = ExocortexRepository::default();
    repo.ensure().map_err(internal_error)?;
    let commit = repo.create_commit(req).map_err(internal_error)?;
    Ok(Json(commit))
}

async fn omnimemory_import_handler(
    State(_state): State<AppState>,
    Json(req): Json<ImportConversationRequest>,
) -> Result<Json<OmniConversation>, StatusCode> {
    let repo = ExocortexRepository::default();
    repo.ensure().map_err(internal_error)?;
    let imported = repo.import_conversation(req).map_err(internal_error)?;
    Ok(Json(imported))
}

async fn memory_assisted_import_handler(
    State(_state): State<AppState>,
    Json(req): Json<AssistedImportBatchRequest>,
) -> Result<Json<AssistedImportBatchResponse>, StatusCode> {
    let repo = ExocortexRepository::default();
    repo.ensure().map_err(internal_error)?;
    let result = repo.assisted_import_batch(req).map_err(internal_error)?;
    Ok(Json(result))
}

async fn temporal_analyze_handler(
    State(_state): State<AppState>,
    Json(req): Json<TemporalAnalyzeRequest>,
) -> Result<Json<TemporalAnalysis>, StatusCode> {
    let repo = ExocortexRepository::default();
    repo.ensure().map_err(internal_error)?;
    let analysis = repo.analyze_temporal(req).map_err(internal_error)?;
    Ok(Json(analysis))
}

async fn audit_events_handler(
    State(_state): State<AppState>,
    Query(query): Query<LimitQuery>,
) -> Result<Json<AuditEventListResponse>, StatusCode> {
    let repo = ExocortexRepository::default();
    repo.ensure().map_err(internal_error)?;
    let events = repo
        .read_recent_jsonl::<AuditEvent>(AUDIT_LOG, query.limit.unwrap_or(50))
        .map_err(internal_error)?;
    Ok(Json(AuditEventListResponse { events }))
}

async fn audit_event_create_handler(
    State(_state): State<AppState>,
    Json(req): Json<CreateAuditEventRequest>,
) -> Result<Json<AuditEvent>, StatusCode> {
    let repo = ExocortexRepository::default();
    repo.ensure().map_err(internal_error)?;
    let event = repo.create_audit_event(req).map_err(internal_error)?;
    Ok(Json(event))
}

async fn memory_events_handler(
    State(_state): State<AppState>,
    Query(query): Query<LimitQuery>,
) -> Result<Json<MemoryEventListResponse>, StatusCode> {
    let repo = ExocortexRepository::default();
    repo.ensure().map_err(internal_error)?;
    let events = repo
        .read_recent_jsonl::<MemoryEvent>(MEMORY_EVENTS_LOG, query.limit.unwrap_or(50))
        .map_err(internal_error)?;
    Ok(Json(MemoryEventListResponse { events }))
}

async fn memory_event_create_handler(
    State(_state): State<AppState>,
    Json(req): Json<CreateMemoryEventRequest>,
) -> Result<Json<MemoryEvent>, StatusCode> {
    let repo = ExocortexRepository::default();
    repo.ensure().map_err(internal_error)?;
    let event = repo.create_memory_event(req).map_err(internal_error)?;
    Ok(Json(event))
}

async fn memory_project_handler(
    State(_state): State<AppState>,
    Json(req): Json<ProjectMemoryRequest>,
) -> Result<Json<MemoryProjectionRun>, StatusCode> {
    let repo = ExocortexRepository::default();
    repo.ensure().map_err(internal_error)?;
    let run = repo.project_memory(req).map_err(internal_error)?;
    Ok(Json(run))
}

async fn memory_projection_status_handler(
    State(_state): State<AppState>,
) -> Result<Json<MemoryProjectionStatus>, StatusCode> {
    let repo = ExocortexRepository::default();
    repo.ensure().map_err(internal_error)?;
    let status = repo.memory_projection_status().map_err(internal_error)?;
    Ok(Json(status))
}

async fn graphrag_query_handler(
    State(_state): State<AppState>,
    Json(req): Json<GraphRagQueryRequest>,
) -> Result<Json<GraphRagQueryResponse>, StatusCode> {
    let repo = ExocortexRepository::default();
    repo.ensure().map_err(internal_error)?;
    let response = repo.graphrag_query(req).map_err(internal_error)?;
    Ok(Json(response))
}

async fn active_projects_handler(
    State(_state): State<AppState>,
) -> Result<Json<ProjectStateListResponse>, StatusCode> {
    let repo = ExocortexRepository::default();
    repo.ensure().map_err(internal_error)?;
    let projects = repo.active_projects().map_err(internal_error)?;
    Ok(Json(ProjectStateListResponse { projects }))
}

fn internal_error(error: anyhow::Error) -> StatusCode {
    error!("Exocortex API error: {:#}", error);
    StatusCode::INTERNAL_SERVER_ERROR
}

#[derive(Debug, Clone)]
struct ExocortexRepository {
    root: PathBuf,
}

impl Default for ExocortexRepository {
    fn default() -> Self {
        Self {
            root: beagle_data_dir().join(EXOCORTEX_DIR),
        }
    }
}

impl ExocortexRepository {
    #[cfg(test)]
    fn new(root: PathBuf) -> Self {
        Self { root }
    }

    fn ensure(&self) -> anyhow::Result<()> {
        fs::create_dir_all(&self.root)?;
        Ok(())
    }

    fn create_commit(&self, req: CreateCommitRequest) -> anyhow::Result<ChronoselfCommit> {
        self.ensure()?;
        let now = Utc::now();
        let last = self
            .read_recent_jsonl::<ChronoselfCommit>(CHRONOSELF_LOG, 1)?
            .into_iter()
            .next();
        let parent_commit_ids = if req.parent_commit_ids.is_empty() {
            last.as_ref()
                .map(|commit| vec![commit.id.clone()])
                .unwrap_or_default()
        } else {
            req.parent_commit_ids
        };
        let context_snapshot = req.context_snapshot.unwrap_or(ContextSnapshot {
            health_ref: None,
            active_project_ids: Vec::new(),
            recent_decision_ids: Vec::new(),
            energy_level: None,
            emotional_valence: None,
            platform: None,
            target_hardware: None,
        });
        let self_version = req
            .self_version
            .unwrap_or_else(|| format!("v{}", now.format("%Y.%m.%d.%H")));
        let user_id = req.user_id.unwrap_or_else(|| "beagle-operator".to_string());
        let trigger_type = req.trigger_type.unwrap_or_else(|| "manual".to_string());
        let confidence = req
            .confidence
            .unwrap_or_else(|| confidence_for_delta(&req.identity_delta));
        let hash = chronoself_hash(
            &self_version,
            &parent_commit_ids,
            &context_snapshot,
            &req.identity_delta,
            &trigger_type,
        )?;
        let commit = ChronoselfCommit {
            id: Uuid::new_v4().to_string(),
            created_at: now.to_rfc3339(),
            self_version,
            parent_commit_ids,
            user_id,
            context_snapshot,
            identity_delta: req.identity_delta,
            trigger_type,
            hash,
            confidence,
            source_refs: req.source_refs,
            summary: req.summary,
        };
        self.append_jsonl(CHRONOSELF_LOG, &commit)?;
        self.write_snapshot(CURRENT_SELF_SNAPSHOT, &self_version_from_commit(&commit))?;
        let home = self.build_home_snapshot(HomeQuery {
            active_project_slug: commit.context_snapshot.active_project_ids.first().cloned(),
            platform: commit.context_snapshot.platform.clone(),
        })?;
        self.write_snapshot(HOME_SNAPSHOT, &home)?;
        Ok(commit)
    }

    fn import_conversation(
        &self,
        req: ImportConversationRequest,
    ) -> anyhow::Result<OmniConversation> {
        self.ensure()?;
        let extracted = req
            .extracted
            .unwrap_or_else(|| extract_conversation_signals(&req.raw_content, &req.tags));
        let raw_hash = content_hash(req.raw_content.as_bytes());
        let raw_content_ref = format!("sha256:{}", raw_hash);
        let source_platform = normalize_source_platform(&req.source_platform);
        if let Some(existing) = self
            .read_recent_jsonl::<OmniConversation>(OMNIMEMORY_LOG, usize::MAX)?
            .into_iter()
            .find(|conversation| {
                conversation.raw_content_ref == raw_content_ref
                    && conversation.source_platform == source_platform
            })
        {
            return Ok(existing);
        }
        let imported_at = Utc::now().to_rfc3339();
        let mut linked_chronoself_commits = Vec::new();
        if req.create_chronoself_commit.unwrap_or(false)
            || !extracted.decisions.is_empty()
            || !extracted.belief_changes.is_empty()
        {
            let commit = self.create_commit(CreateCommitRequest {
                user_id: None,
                self_version: None,
                parent_commit_ids: Vec::new(),
                context_snapshot: Some(ContextSnapshot {
                    health_ref: None,
                    active_project_ids: extracted.projects_mentioned.clone(),
                    recent_decision_ids: Vec::new(),
                    energy_level: None,
                    emotional_valence: None,
                    platform: Some(req.source_platform.clone()),
                    target_hardware: None,
                }),
                identity_delta: IdentityDelta {
                    beliefs_added: extracted.belief_changes.clone(),
                    beliefs_removed: Vec::new(),
                    values_changed: Vec::new(),
                    cognitive_style_shift: extracted
                        .key_insights
                        .first()
                        .map(|insight| truncate_chars(insight, 180)),
                    priority_reordering: extracted.decisions.clone(),
                    product_principles: Vec::new(),
                },
                trigger_type: Some("explicit_decision".to_string()),
                confidence: Some(req.confidence_score.unwrap_or(0.72)),
                source_refs: vec![format!("omnimemory:{}", raw_hash)],
                summary: extracted.key_insights.first().cloned(),
            })?;
            linked_chronoself_commits.push(commit.id);
        }
        let imported = OmniConversation {
            id: Uuid::new_v4().to_string(),
            source_platform,
            imported_at,
            session_id: req.session_id,
            original_date: req.original_date,
            raw_content_ref,
            extracted,
            linked_chronoself_commits,
            linked_memory_events: Vec::new(),
            confidence_score: req.confidence_score.unwrap_or(0.68),
            title: req.title,
            privacy_class: normalize_privacy_class(req.privacy_class.as_deref()),
            tags: req.tags,
            metadata: req.metadata.unwrap_or(serde_json::Value::Null),
        };
        self.append_jsonl(OMNIMEMORY_LOG, &imported)?;
        let _ = self.project_memory(ProjectMemoryRequest {
            rebuild: false,
            source_refs: vec![format!("omnimemory:{}", imported.id)],
        })?;
        let home = self.build_home_snapshot(HomeQuery {
            active_project_slug: imported.extracted.projects_mentioned.first().cloned(),
            platform: Some(imported.source_platform.clone()),
        })?;
        self.write_snapshot(HOME_SNAPSHOT, &home)?;
        Ok(imported)
    }

    fn assisted_import_batch(
        &self,
        req: AssistedImportBatchRequest,
    ) -> anyhow::Result<AssistedImportBatchResponse> {
        self.ensure()?;
        anyhow::ensure!(
            !req.turns.is_empty(),
            "assisted import requires at least one visible turn"
        );

        let source_platform = normalize_source_platform(&req.source_platform);
        let source_surface = if req.source_surface.trim().is_empty() {
            default_assisted_source_surface()
        } else {
            req.source_surface.trim().to_lowercase()
        };
        let import_scope = if req.import_scope.trim().is_empty() {
            default_assisted_import_scope()
        } else {
            req.import_scope.trim().to_lowercase()
        };
        let privacy_class = normalize_privacy_class(req.privacy_class.as_deref());
        let base_metadata = ensure_object(req.metadata);
        let tool_manifest_hash = base_metadata
            .get("tool_manifest_hash")
            .and_then(|value| value.as_str())
            .map(str::to_string);
        let principal = base_metadata
            .get("principal")
            .and_then(|value| value.as_str())
            .unwrap_or(&source_surface)
            .to_string();
        let surface_observed = base_metadata
            .get("surface_observed")
            .and_then(|value| value.as_str())
            .unwrap_or("cluster-core")
            .to_string();

        if privacy_class == "restricted" {
            let audit = self.create_audit_event(CreateAuditEventRequest {
                client_id: Some(principal.clone()),
                action: Some("memory.assisted_import".to_string()),
                tool_name: Some("beagle_assisted_import_batch".to_string()),
                risk_level: Some("write".to_string()),
                required_scopes: vec!["memory:write".to_string()],
                granted_scopes: metadata_string_array(&base_metadata, "scopes"),
                status: Some("rejected".to_string()),
                source: Some(source_surface.clone()),
                target_ref: None,
                summary: Some(
                    "Rejected restricted assisted import before OmniMemory write.".to_string(),
                ),
                metadata: Some(serde_json::json!({
                    "source_platform": source_platform,
                    "source_surface": source_surface,
                    "surface_claimed": source_surface,
                    "surface_observed": surface_observed,
                    "principal": principal,
                    "session_id": req.session_id,
                    "batch_index": req.batch_index,
                    "batch_total": req.batch_total,
                    "privacy_class": privacy_class,
                    "tool_manifest_hash": tool_manifest_hash,
                    "restricted_default_policy": "reject_without_explicit_human_review",
                })),
            })?;
            return Ok(AssistedImportBatchResponse {
                status: "rejected".to_string(),
                reason: Some(
                    "restricted payloads require explicit human review before import".to_string(),
                ),
                session_id: req.session_id,
                source_platform,
                source_surface,
                batch_index: req.batch_index,
                batch_total: req.batch_total,
                privacy_class,
                omnimemory: None,
                projection: None,
                memory_event: None,
                audit_event: Some(audit),
            });
        }

        let raw_content = assisted_raw_content(&req.turns);
        let mut tags = req.tags.clone();
        merge_unique(
            &mut tags,
            vec![
                source_platform.clone(),
                source_surface.clone(),
                import_scope.clone(),
                "assisted-import".to_string(),
                "graphrag-projection".to_string(),
                format!("privacy:{}", privacy_class),
            ],
            32,
        );
        if let Some(project) = req
            .project_ref
            .as_deref()
            .filter(|value| !value.trim().is_empty())
        {
            let project_tag = format!("project:{}", project.trim());
            if !tags.contains(&project_tag) {
                tags.push(project_tag);
            }
        }
        let first_timestamp = req.turns.iter().find_map(|turn| turn.timestamp.clone());
        let mut metadata = base_metadata.clone();
        metadata.insert(
            "import_scope".to_string(),
            serde_json::Value::String(import_scope.clone()),
        );
        metadata.insert(
            "source_surface".to_string(),
            serde_json::Value::String(source_surface.clone()),
        );
        metadata.insert(
            "surface_claimed".to_string(),
            serde_json::Value::String(source_surface.clone()),
        );
        metadata.insert(
            "surface_observed".to_string(),
            serde_json::Value::String(surface_observed.clone()),
        );
        metadata.insert(
            "principal".to_string(),
            serde_json::Value::String(principal.clone()),
        );
        metadata.insert(
            "session_id".to_string(),
            serde_json::Value::String(req.session_id.clone()),
        );
        metadata.insert(
            "batch_index".to_string(),
            serde_json::json!(req.batch_index),
        );
        metadata.insert(
            "batch_total".to_string(),
            serde_json::json!(req.batch_total),
        );
        metadata.insert("coverage".to_string(), req.coverage.clone());
        metadata.insert(
            "explicit_import_only".to_string(),
            serde_json::Value::Bool(true),
        );
        metadata.insert(
            "privacy_class".to_string(),
            serde_json::Value::String(privacy_class.clone()),
        );
        if let Some(project_ref) = req.project_ref.clone() {
            metadata.insert(
                "project_ref".to_string(),
                serde_json::Value::String(project_ref),
            );
        }
        if let Some(hash) = tool_manifest_hash.clone() {
            metadata.insert(
                "tool_manifest_hash".to_string(),
                serde_json::Value::String(hash),
            );
        }

        let imported = self.import_conversation(ImportConversationRequest {
            source_platform: source_platform.clone(),
            session_id: Some(req.session_id.clone()),
            original_date: req.original_date.or(first_timestamp),
            raw_content,
            title: req.title.or_else(|| {
                Some(format!(
                    "{} {} {} batch {}/{}",
                    source_platform, import_scope, req.session_id, req.batch_index, req.batch_total
                ))
            }),
            tags: tags.clone(),
            extracted: req.extracted,
            confidence_score: Some(req.confidence_score.unwrap_or(0.76).clamp(0.0, 1.0)),
            create_chronoself_commit: req.create_chronoself_commit,
            privacy_class: Some(privacy_class.clone()),
            metadata: Some(serde_json::Value::Object(metadata.clone())),
        })?;
        let source_refs = vec![
            format!("omnimemory:{}", imported.id),
            imported.raw_content_ref.clone(),
        ];
        let projection = match self
            .read_recent_jsonl::<MemoryProjectionRun>(MEMORY_PROJECTION_RUNS_LOG, 1)?
            .into_iter()
            .next()
        {
            Some(run) => run,
            None => self.project_memory(ProjectMemoryRequest {
                rebuild: false,
                source_refs: source_refs.clone(),
            })?,
        };
        let summary = format!(
            "Assisted import batch {}/{} from {} via {}",
            req.batch_index, req.batch_total, source_platform, source_surface
        );
        let memory_event = self.create_memory_event(CreateMemoryEventRequest {
            source: Some(source_surface.clone()),
            kind: Some("assisted_import_batch".to_string()),
            content_ref: Some(format!("omnimemory:{}", imported.id)),
            summary: Some(summary.clone()),
            tags: tags.clone(),
            metadata: Some(serde_json::json!({
                "source_platform": source_platform,
                "source_surface": source_surface,
                "surface_claimed": source_surface,
                "surface_observed": surface_observed,
                "principal": principal,
                "import_scope": import_scope,
                "session_id": req.session_id,
                "project_ref": req.project_ref,
                "batch_index": req.batch_index,
                "batch_total": req.batch_total,
                "privacy_class": privacy_class,
                "coverage": req.coverage,
                "omnimemory_source_refs": source_refs,
                "projection": projection,
                "tool_manifest_hash": tool_manifest_hash,
            })),
            linked_chronoself_commits: imported.linked_chronoself_commits.clone(),
            confidence: Some(req.confidence_score.unwrap_or(0.76).clamp(0.0, 1.0)),
        })?;
        let audit = self.create_audit_event(CreateAuditEventRequest {
            client_id: Some(principal.clone()),
            action: Some("memory.assisted_import".to_string()),
            tool_name: Some("beagle_assisted_import_batch".to_string()),
            risk_level: Some("write".to_string()),
            required_scopes: vec!["memory:write".to_string()],
            granted_scopes: metadata_string_array(&base_metadata, "scopes"),
            status: Some("success".to_string()),
            source: Some(source_surface.clone()),
            target_ref: Some(format!("omnimemory:{}", imported.id)),
            summary: Some(summary),
            metadata: Some(serde_json::json!({
                "source_platform": source_platform,
                "source_surface": source_surface,
                "surface_claimed": source_surface,
                "surface_observed": surface_observed,
                "principal": principal,
                "session_id": req.session_id,
                "batch_index": req.batch_index,
                "batch_total": req.batch_total,
                "privacy_class": privacy_class,
                "tool_manifest_hash": tool_manifest_hash,
                "memory_event_id": memory_event.id,
                "projection_run_id": projection.id,
            })),
        })?;

        Ok(AssistedImportBatchResponse {
            status: "imported".to_string(),
            reason: None,
            session_id: req.session_id,
            source_platform,
            source_surface,
            batch_index: req.batch_index,
            batch_total: req.batch_total,
            privacy_class,
            omnimemory: Some(imported),
            projection: Some(projection),
            memory_event: Some(memory_event),
            audit_event: Some(audit),
        })
    }

    fn project_memory(&self, req: ProjectMemoryRequest) -> anyhow::Result<MemoryProjectionRun> {
        self.ensure()?;
        let source_filter = req.source_refs;
        let imports = self.read_recent_jsonl::<OmniConversation>(OMNIMEMORY_LOG, usize::MAX)?;
        let memory_events = self.read_recent_jsonl::<MemoryEvent>(MEMORY_EVENTS_LOG, usize::MAX)?;
        let before_episodes =
            self.read_recent_jsonl::<MemoryEpisode>(MEMORY_EPISODES_LOG, usize::MAX)?;
        let before_atoms = self.read_recent_jsonl::<MemoryAtom>(MEMORY_ATOMS_LOG, usize::MAX)?;
        let mut episodes_created = 0;
        let mut atoms_created = 0;
        let mut duplicates = 0;
        let mut source_count = 0;
        let mut errors = Vec::new();

        for import in &imports {
            let source_ref = format!("omnimemory:{}", import.id);
            if !source_filter.is_empty()
                && !source_filter.contains(&source_ref)
                && !source_filter.contains(&import.raw_content_ref)
            {
                continue;
            }
            source_count += 1;
            match self.project_import(import) {
                Ok(outcome) => {
                    episodes_created += outcome.episodes_created;
                    atoms_created += outcome.atoms_created;
                    duplicates += outcome.duplicates;
                }
                Err(error) => errors.push(format!("{}: {:#}", source_ref, error)),
            }
        }

        for event in &memory_events {
            let source_ref = format!("memory_event:{}", event.id);
            if !source_filter.is_empty()
                && !source_filter.contains(&source_ref)
                && event
                    .content_ref
                    .as_ref()
                    .map(|content_ref| !source_filter.contains(content_ref))
                    .unwrap_or(true)
            {
                continue;
            }
            source_count += 1;
            match self.project_memory_event(event) {
                Ok(outcome) => {
                    episodes_created += outcome.episodes_created;
                    atoms_created += outcome.atoms_created;
                    duplicates += outcome.duplicates;
                }
                Err(error) => errors.push(format!("{}: {:#}", source_ref, error)),
            }
        }

        let after_episodes =
            self.read_recent_jsonl::<MemoryEpisode>(MEMORY_EPISODES_LOG, usize::MAX)?;
        let after_atoms = self.read_recent_jsonl::<MemoryAtom>(MEMORY_ATOMS_LOG, usize::MAX)?;
        let projection_hash = projection_hash(&after_episodes, &after_atoms)?;
        let run = MemoryProjectionRun {
            id: Uuid::new_v4().to_string(),
            created_at: Utc::now().to_rfc3339(),
            schema_version: MEMORY_PROJECTION_SCHEMA.to_string(),
            source_count,
            episodes_created,
            atoms_created,
            duplicates,
            errors,
            projection_hash,
            status: if episodes_created > 0 || atoms_created > 0 || req.rebuild {
                "projected".to_string()
            } else {
                "unchanged".to_string()
            },
            degraded_reason: "lexical+graph+temporal retrieval active; real embedding backend not configured in GraphRAG++ projection v1.2".to_string(),
        };
        if before_episodes.len() != after_episodes.len()
            || before_atoms.len() != after_atoms.len()
            || req.rebuild
        {
            self.append_jsonl(MEMORY_PROJECTION_RUNS_LOG, &run)?;
        }
        let home = self.build_home_snapshot(HomeQuery {
            active_project_slug: None,
            platform: Some("graphrag++".to_string()),
        })?;
        self.write_snapshot(HOME_SNAPSHOT, &home)?;
        Ok(run)
    }

    fn project_import(&self, import: &OmniConversation) -> anyhow::Result<ProjectionOutcome> {
        if import.privacy_class == "restricted" {
            return Ok(ProjectionOutcome::default());
        }
        let source_ref = format!("omnimemory:{}", import.id);
        let existing_episode = self.find_episode_by_source_ref(&source_ref)?;
        if existing_episode.is_some() {
            return Ok(ProjectionOutcome {
                duplicates: 1,
                ..Default::default()
            });
        }
        let episode = MemoryEpisode {
            id: stable_id("episode", &[&source_ref, &import.raw_content_ref]),
            created_at: Utc::now().to_rfc3339(),
            source: "omnimemory".to_string(),
            source_platform: Some(import.source_platform.clone()),
            session_id: import.session_id.clone(),
            source_ref: source_ref.clone(),
            content_hash: import.raw_content_ref.clone(),
            privacy_class: import.privacy_class.clone(),
            provenance: serde_json::json!({
                "source": "omnimemory",
                "source_platform": import.source_platform,
                "raw_content_ref": import.raw_content_ref,
                "imported_at": import.imported_at,
                "metadata": import.metadata,
            }),
            tags: import.tags.clone(),
            title: import.title.clone(),
            linked_chronoself_commits: import.linked_chronoself_commits.clone(),
            occurred_at: import
                .original_date
                .clone()
                .or_else(|| Some(import.imported_at.clone())),
        };
        self.append_jsonl(MEMORY_EPISODES_LOG, &episode)?;
        let atoms = atoms_from_import(import, &episode);
        let mut atoms_created = 0;
        for atom in atoms {
            if self.find_atom_by_id(&atom.id)?.is_none() {
                self.append_jsonl(MEMORY_ATOMS_LOG, &atom)?;
                atoms_created += 1;
            }
        }
        Ok(ProjectionOutcome {
            episodes_created: 1,
            atoms_created,
            duplicates: 0,
        })
    }

    fn project_memory_event(&self, event: &MemoryEvent) -> anyhow::Result<ProjectionOutcome> {
        let privacy = normalize_privacy_class(
            event
                .metadata
                .get("privacy_class")
                .and_then(|value| value.as_str()),
        );
        if privacy == "restricted" {
            return Ok(ProjectionOutcome::default());
        }
        let source_ref = format!("memory_event:{}", event.id);
        if self.find_episode_by_source_ref(&source_ref)?.is_some() {
            return Ok(ProjectionOutcome {
                duplicates: 1,
                ..Default::default()
            });
        }
        let content_hash = event
            .content_ref
            .clone()
            .unwrap_or_else(|| format!("sha256:{}", content_hash(event.summary.as_bytes())));
        let episode = MemoryEpisode {
            id: stable_id("episode", &[&source_ref, &content_hash]),
            created_at: Utc::now().to_rfc3339(),
            source: event.source.clone(),
            source_platform: Some(event.source.clone()),
            session_id: metadata_string(&event.metadata, "session_id"),
            source_ref: source_ref.clone(),
            content_hash,
            privacy_class: privacy.clone(),
            provenance: serde_json::json!({
                "source": event.source,
                "kind": event.kind,
                "content_ref": event.content_ref,
                "metadata": event.metadata,
            }),
            tags: event.tags.clone(),
            title: Some(event.kind.clone()),
            linked_chronoself_commits: event.linked_chronoself_commits.clone(),
            occurred_at: Some(event.created_at.clone()),
        };
        self.append_jsonl(MEMORY_EPISODES_LOG, &episode)?;
        let atom = MemoryAtom {
            id: stable_id("atom", &[&episode.id, "memory_event", &event.summary]),
            created_at: Utc::now().to_rfc3339(),
            episode_id: episode.id.clone(),
            atom_type: "memory_event".to_string(),
            text: truncate_chars(&event.summary, 500),
            normalized_text: normalize_text(&event.summary),
            source_refs: vec![source_ref],
            relations: relations_for_tags(&event.tags, &episode.id),
            tags: event.tags.clone(),
            confidence: event.confidence,
            privacy_class: privacy,
            occurred_at: Some(event.created_at.clone()),
        };
        if self.find_atom_by_id(&atom.id)?.is_none() {
            self.append_jsonl(MEMORY_ATOMS_LOG, &atom)?;
            Ok(ProjectionOutcome {
                episodes_created: 1,
                atoms_created: 1,
                duplicates: 0,
            })
        } else {
            Ok(ProjectionOutcome {
                episodes_created: 1,
                atoms_created: 0,
                duplicates: 1,
            })
        }
    }

    fn memory_projection_status(&self) -> anyhow::Result<MemoryProjectionStatus> {
        self.ensure()?;
        let episodes = self.read_recent_jsonl::<MemoryEpisode>(MEMORY_EPISODES_LOG, usize::MAX)?;
        let atoms = self.read_recent_jsonl::<MemoryAtom>(MEMORY_ATOMS_LOG, usize::MAX)?;
        let latest_run = self
            .read_recent_jsonl::<MemoryProjectionRun>(MEMORY_PROJECTION_RUNS_LOG, 1)?
            .into_iter()
            .next();
        let freshness = latest_run
            .as_ref()
            .map(|run| run.created_at.clone())
            .unwrap_or_else(|| "never".to_string());
        Ok(MemoryProjectionStatus {
            status: if atoms.is_empty() {
                "empty".to_string()
            } else {
                "fresh".to_string()
            },
            schema_version: MEMORY_PROJECTION_SCHEMA.to_string(),
            episode_count: episodes.len(),
            atom_count: atoms.len(),
            latest_run,
            freshness,
            retrieval_mode: if atoms.is_empty() {
                "append-only fallback".to_string()
            } else {
                "hybrid lexical+graph+temporal".to_string()
            },
            degraded_reason: "real embedding backend not configured in GraphRAG++ projection v1.2"
                .to_string(),
        })
    }

    fn graphrag_query(&self, req: GraphRagQueryRequest) -> anyhow::Result<GraphRagQueryResponse> {
        self.ensure()?;
        let max_items = req.max_items.unwrap_or(5).clamp(1, 20);
        let atoms = self.read_recent_jsonl::<MemoryAtom>(MEMORY_ATOMS_LOG, usize::MAX)?;
        let episodes = self.read_recent_jsonl::<MemoryEpisode>(MEMORY_EPISODES_LOG, usize::MAX)?;
        if atoms.is_empty() {
            return Ok(GraphRagQueryResponse {
                summary: format!(
                    "No GraphRAG++ projected memory matches found for '{}'.",
                    req.query
                ),
                evidence: Vec::new(),
                atoms: Vec::new(),
                episodes: Vec::new(),
                relations: Vec::new(),
                temporal_context: GraphRagTemporalContext {
                    newest_evidence_at: None,
                    oldest_evidence_at: None,
                    matched_episode_count: 0,
                },
                provenance: serde_json::json!({
                    "schema_version": MEMORY_PROJECTION_SCHEMA,
                    "retrieval_mode": "append-only fallback"
                }),
                confidence: 0.0,
                degraded_reason: Some("no projected memory atoms available".to_string()),
            });
        }

        let query_tokens = tokenize(&req.query);
        let scope = req.scope.as_ref().map(|scope| scope.to_lowercase());
        let mut scored = atoms
            .iter()
            .filter(|atom| {
                scope
                    .as_ref()
                    .map(|scope| {
                        atom.tags
                            .iter()
                            .any(|tag| tag.to_lowercase().contains(scope))
                            || atom.atom_type.to_lowercase().contains(scope)
                    })
                    .unwrap_or(true)
            })
            .filter_map(|atom| {
                let score = atom_score(atom, &query_tokens);
                (score > 0.0).then_some((atom.clone(), score))
            })
            .collect::<Vec<_>>();
        scored.sort_by(|a, b| {
            b.1.partial_cmp(&a.1)
                .unwrap_or(std::cmp::Ordering::Equal)
                .then_with(|| b.0.occurred_at.cmp(&a.0.occurred_at))
        });
        scored.truncate(max_items);

        let mut matched_episodes = Vec::<MemoryEpisode>::new();
        let mut evidence = Vec::<GraphRagEvidence>::new();
        let mut relations = Vec::<MemoryRelation>::new();
        for (atom, score) in &scored {
            if let Some(episode) = episodes
                .iter()
                .find(|episode| episode.id == atom.episode_id)
            {
                if !matched_episodes.iter().any(|item| item.id == episode.id) {
                    matched_episodes.push(episode.clone());
                }
                evidence.push(GraphRagEvidence {
                    atom_id: atom.id.clone(),
                    episode_id: atom.episode_id.clone(),
                    atom_type: atom.atom_type.clone(),
                    text: atom.text.clone(),
                    score: *score,
                    source_refs: atom.source_refs.clone(),
                    provenance: episode.provenance.clone(),
                });
            }
            for relation in &atom.relations {
                if !relations.iter().any(|existing| {
                    existing.subject == relation.subject
                        && existing.predicate == relation.predicate
                        && existing.object == relation.object
                }) {
                    relations.push(relation.clone());
                }
            }
        }
        let newest = evidence
            .iter()
            .filter_map(|item| {
                matched_episodes
                    .iter()
                    .find(|episode| episode.id == item.episode_id)
                    .and_then(|episode| episode.occurred_at.clone())
            })
            .max();
        let oldest = evidence
            .iter()
            .filter_map(|item| {
                matched_episodes
                    .iter()
                    .find(|episode| episode.id == item.episode_id)
                    .and_then(|episode| episode.occurred_at.clone())
            })
            .min();
        let confidence = if evidence.is_empty() {
            0.0
        } else {
            (evidence.iter().map(|item| item.score).sum::<f64>() / evidence.len() as f64)
                .clamp(0.0, 1.0)
        };
        let summary = if evidence.is_empty() {
            format!(
                "No GraphRAG++ projected memory matches found for '{}'.",
                req.query
            )
        } else {
            format!(
                "Found {} GraphRAG++ projected memory match(es) across {} episode(s) for '{}'.",
                evidence.len(),
                matched_episodes.len(),
                req.query
            )
        };

        let matched_episode_count = matched_episodes.len();
        Ok(GraphRagQueryResponse {
            summary,
            evidence,
            atoms: scored.into_iter().map(|(atom, _)| atom).collect(),
            episodes: matched_episodes,
            relations,
            temporal_context: GraphRagTemporalContext {
                newest_evidence_at: newest,
                oldest_evidence_at: oldest,
                matched_episode_count,
            },
            provenance: serde_json::json!({
                "schema_version": MEMORY_PROJECTION_SCHEMA,
                "retrieval_mode": "hybrid lexical+graph+temporal",
                "embedding_backend": "not_configured",
            }),
            confidence,
            degraded_reason: Some(
                "real embedding backend not configured; using lexical+graph+temporal scoring"
                    .to_string(),
            ),
        })
    }

    fn find_episode_by_source_ref(
        &self,
        source_ref: &str,
    ) -> anyhow::Result<Option<MemoryEpisode>> {
        Ok(self
            .read_recent_jsonl::<MemoryEpisode>(MEMORY_EPISODES_LOG, usize::MAX)?
            .into_iter()
            .find(|episode| episode.source_ref == source_ref))
    }

    fn find_atom_by_id(&self, atom_id: &str) -> anyhow::Result<Option<MemoryAtom>> {
        Ok(self
            .read_recent_jsonl::<MemoryAtom>(MEMORY_ATOMS_LOG, usize::MAX)?
            .into_iter()
            .find(|atom| atom.id == atom_id))
    }

    fn analyze_temporal(&self, req: TemporalAnalyzeRequest) -> anyhow::Result<TemporalAnalysis> {
        self.ensure()?;
        let now = Utc::now();
        let commits = self.read_recent_jsonl::<ChronoselfCommit>(CHRONOSELF_LOG, 50)?;
        let imports = self.read_recent_jsonl::<OmniConversation>(OMNIMEMORY_LOG, 25)?;
        let days_back = req.days_back.unwrap_or(90);
        let start = req
            .time_range_start
            .unwrap_or_else(|| (now - chrono::Duration::days(days_back as i64)).to_rfc3339());
        let end = req.time_range_end.unwrap_or_else(|| now.to_rfc3339());
        let latest_self = commits
            .first()
            .map(self_version_from_commit)
            .unwrap_or_else(default_self_version);
        let topic_lc = req.topic.to_lowercase();
        let matching_commits: Vec<_> = commits
            .iter()
            .filter(|commit| commit_matches_topic(commit, &topic_lc))
            .collect();
        let matching_imports: Vec<_> = imports
            .iter()
            .filter(|import| import_matches_topic(import, &topic_lc))
            .collect();
        let signal_count = matching_commits.len() + matching_imports.len();
        let phase_name = if signal_count >= 3 {
            "Fase de Integração Ativa"
        } else if signal_count > 0 {
            "Fase de Consolidação"
        } else {
            "Fase de Busca de Sinal"
        };
        let recommendation = if signal_count > 0 {
            format!(
                "Retome '{}' a partir dos sinais recentes e converta a próxima decisão em commit Chronoself.",
                req.topic
            )
        } else {
            format!(
                "Crie um primeiro registro explícito sobre '{}' para dar material longitudinal ao TemporalAI.",
                req.topic
            )
        };
        let analysis = TemporalAnalysis {
            id: Uuid::new_v4().to_string(),
            created_at: now.to_rfc3339(),
            topic: req.topic,
            time_range_start: start,
            time_range_end: end,
            phases: vec![TemporalPhase {
                name: phase_name.to_string(),
                period_start: latest_self.period_start.clone(),
                period_end: None,
                characteristics: vec![
                    "Análise gerada por sinais cluster-first do Exocortex.".to_string(),
                    format!("{} sinais relevantes encontrados.", signal_count),
                ],
                self_version_ref: latest_self.source_commit_id.clone(),
            }],
            turning_points: matching_commits
                .iter()
                .take(3)
                .map(|commit| TurningPoint {
                    date: commit.created_at.clone(),
                    description: commit.summary.clone().unwrap_or_else(|| commit.trigger_type.clone()),
                    cause: commit.identity_delta.cognitive_style_shift.clone(),
                    self_version_before: commit.parent_commit_ids.first().cloned(),
                    self_version_after: Some(commit.id.clone()),
                })
                .collect(),
            recurring_pattern: (signal_count >= 2).then(|| RecurringPattern {
                description: "O tema reaparece em múltiplas superfícies de memória.".to_string(),
                frequency_days: None,
                confidence: 0.62,
            }),
            causal_hypothesis: Some(
                "Hipótese inicial: mudanças de foco aparecem quando decisões, importações e projetos ativos convergem no mesmo tema."
                    .to_string(),
            ),
            recommendation,
            llm_model_used: Some("deterministic-temporalai-mvp".to_string()),
            confidence_score: if signal_count > 0 { 0.66 } else { 0.42 },
            source_refs: matching_commits
                .iter()
                .map(|commit| format!("chronoself:{}", commit.id))
                .chain(
                    matching_imports
                        .iter()
                        .map(|import| format!("omnimemory:{}", import.id)),
                )
                .take(10)
                .collect(),
        };
        self.append_jsonl(TEMPORAL_LOG, &analysis)?;
        let home = self.build_home_snapshot(HomeQuery {
            active_project_slug: None,
            platform: None,
        })?;
        self.write_snapshot(HOME_SNAPSHOT, &home)?;
        Ok(analysis)
    }

    fn create_audit_event(&self, req: CreateAuditEventRequest) -> anyhow::Result<AuditEvent> {
        self.ensure()?;
        let event = AuditEvent {
            id: Uuid::new_v4().to_string(),
            created_at: Utc::now().to_rfc3339(),
            client_id: req.client_id.unwrap_or_else(|| "unknown-agent".to_string()),
            action: req.action.unwrap_or_else(|| "mcp.tool_call".to_string()),
            tool_name: req.tool_name,
            risk_level: req.risk_level.unwrap_or_else(|| "unknown".to_string()),
            required_scopes: req.required_scopes,
            granted_scopes: req.granted_scopes,
            status: req.status.unwrap_or_else(|| "success".to_string()),
            source: req.source.unwrap_or_else(|| "mcp".to_string()),
            target_ref: req.target_ref,
            summary: req.summary,
            metadata: req.metadata.unwrap_or(serde_json::Value::Null),
        };
        self.append_jsonl(AUDIT_LOG, &event)?;
        let home = self.build_home_snapshot(HomeQuery {
            active_project_slug: None,
            platform: Some("mcp".to_string()),
        })?;
        self.write_snapshot(HOME_SNAPSHOT, &home)?;
        Ok(event)
    }

    fn create_memory_event(&self, req: CreateMemoryEventRequest) -> anyhow::Result<MemoryEvent> {
        self.ensure()?;
        let event = MemoryEvent {
            id: Uuid::new_v4().to_string(),
            created_at: Utc::now().to_rfc3339(),
            source: req.source.unwrap_or_else(|| "mcp".to_string()),
            kind: req.kind.unwrap_or_else(|| "note".to_string()),
            content_ref: req.content_ref,
            summary: req
                .summary
                .unwrap_or_else(|| "Memory event recorded by Beagle MCP.".to_string()),
            tags: req.tags,
            metadata: req.metadata.unwrap_or(serde_json::Value::Null),
            linked_chronoself_commits: req.linked_chronoself_commits,
            confidence: req.confidence.unwrap_or(0.7).clamp(0.0, 1.0),
        };
        self.append_jsonl(MEMORY_EVENTS_LOG, &event)?;
        let home = self.build_home_snapshot(HomeQuery {
            active_project_slug: None,
            platform: Some(event.source.clone()),
        })?;
        self.write_snapshot(HOME_SNAPSHOT, &home)?;
        Ok(event)
    }

    fn active_projects(&self) -> anyhow::Result<Vec<ProjectState>> {
        self.ensure()?;
        let commits = self.read_recent_jsonl::<ChronoselfCommit>(CHRONOSELF_LOG, 50)?;
        let imports = self.read_recent_jsonl::<OmniConversation>(OMNIMEMORY_LOG, 25)?;
        let memory_events = self.read_recent_jsonl::<MemoryEvent>(MEMORY_EVENTS_LOG, 25)?;
        let explicit_states = self.read_recent_jsonl::<ProjectState>(PROJECT_STATES_LOG, 50)?;

        let mut projects = Vec::<ProjectState>::new();
        for state in explicit_states {
            upsert_project(&mut projects, state);
        }

        for commit in &commits {
            for project in &commit.context_snapshot.active_project_ids {
                upsert_project(
                    &mut projects,
                    ProjectState {
                        id: project_slug(project),
                        name: project.clone(),
                        status: "active".to_string(),
                        recent_events: commit
                            .summary
                            .clone()
                            .into_iter()
                            .chain(commit.identity_delta.priority_reordering.clone())
                            .take(3)
                            .collect(),
                        next_actions: commit.identity_delta.priority_reordering.clone(),
                        linked_memories: commit
                            .source_refs
                            .iter()
                            .map(|source| source.to_string())
                            .collect(),
                        last_interaction_at: Some(commit.created_at.clone()),
                    },
                );
            }
        }

        for import in &imports {
            for project in &import.extracted.projects_mentioned {
                upsert_project(
                    &mut projects,
                    ProjectState {
                        id: project_slug(project),
                        name: project.clone(),
                        status: "active".to_string(),
                        recent_events: import
                            .extracted
                            .key_insights
                            .iter()
                            .take(3)
                            .cloned()
                            .collect(),
                        next_actions: import
                            .extracted
                            .unresolved_questions
                            .iter()
                            .take(3)
                            .cloned()
                            .collect(),
                        linked_memories: vec![format!("omnimemory:{}", import.id)],
                        last_interaction_at: Some(import.imported_at.clone()),
                    },
                );
            }
        }

        for event in &memory_events {
            for project in event
                .tags
                .iter()
                .filter_map(|tag| tag.strip_prefix("project:").map(str::to_string))
            {
                upsert_project(
                    &mut projects,
                    ProjectState {
                        id: project_slug(&project),
                        name: project,
                        status: "active".to_string(),
                        recent_events: vec![event.summary.clone()],
                        next_actions: Vec::new(),
                        linked_memories: vec![format!("memory_event:{}", event.id)],
                        last_interaction_at: Some(event.created_at.clone()),
                    },
                );
            }
        }

        if projects.is_empty() {
            projects.push(ProjectState {
                id: "sounio".to_string(),
                name: "sounio".to_string(),
                status: "forming".to_string(),
                recent_events: vec!["Bootstrap project for the Beagle exocortex.".to_string()],
                next_actions: vec![
                    "Importar conversa, registrar decisão ou iniciar pesquisa.".to_string()
                ],
                linked_memories: Vec::new(),
                last_interaction_at: None,
            });
        }

        projects.sort_by(|a, b| b.last_interaction_at.cmp(&a.last_interaction_at));
        Ok(projects)
    }

    fn current_self(&self) -> anyhow::Result<SelfVersion> {
        if let Some(snapshot) = self.read_snapshot::<SelfVersion>(CURRENT_SELF_SNAPSHOT)? {
            return Ok(snapshot);
        }
        let latest = self
            .read_recent_jsonl::<ChronoselfCommit>(CHRONOSELF_LOG, 1)?
            .into_iter()
            .next()
            .map(|commit| self_version_from_commit(&commit))
            .unwrap_or_else(default_self_version);
        self.write_snapshot(CURRENT_SELF_SNAPSHOT, &latest)?;
        Ok(latest)
    }

    fn build_home_snapshot(&self, query: HomeQuery) -> anyhow::Result<ExocortexHomeSnapshot> {
        let current_self = self.current_self()?;
        let commits = self.read_recent_jsonl::<ChronoselfCommit>(CHRONOSELF_LOG, 5)?;
        let imports = self.read_recent_jsonl::<OmniConversation>(OMNIMEMORY_LOG, 5)?;
        let projected_atoms = self.read_recent_jsonl::<MemoryAtom>(MEMORY_ATOMS_LOG, 5)?;
        let analyses = self.read_recent_jsonl::<TemporalAnalysis>(TEMPORAL_LOG, 3)?;
        let audit_events = self.read_recent_jsonl::<AuditEvent>(AUDIT_LOG, 10)?;
        let memory_events = self.read_recent_jsonl::<MemoryEvent>(MEMORY_EVENTS_LOG, 5)?;
        let agent_observations =
            self.read_recent_jsonl::<AgentObservation>(AGENT_OBSERVATIONS_LOG, 5)?;
        let causal_hypotheses =
            self.read_recent_jsonl::<CausalHypothesis>(CAUSAL_HYPOTHESES_LOG, 3)?;
        let requested_platform = query.platform.clone();
        let target_hardware = commits
            .iter()
            .find_map(|commit| commit.context_snapshot.target_hardware.clone());
        let active_project = query
            .active_project_slug
            .or_else(|| {
                commits
                    .iter()
                    .find_map(|commit| commit.context_snapshot.active_project_ids.first().cloned())
            })
            .or_else(|| Some("sounio".to_string()));
        let memory_signals = projected_atoms
            .iter()
            .map(|atom| format!("{}: {}", atom.atom_type, atom.text))
            .chain(commits.iter().filter_map(|commit| {
                commit
                    .summary
                    .clone()
                    .or_else(|| commit.identity_delta.cognitive_style_shift.clone())
            }))
            .chain(
                imports
                    .iter()
                    .filter_map(|import| import.extracted.key_insights.first().cloned()),
            )
            .chain(memory_events.iter().map(|event| event.summary.clone()))
            .take(5)
            .collect::<Vec<_>>();
        let open_loops = imports
            .iter()
            .flat_map(|import| import.extracted.unresolved_questions.clone())
            .take(5)
            .collect::<Vec<_>>();
        let temporal_phase = analyses
            .first()
            .and_then(|analysis| analysis.phases.first())
            .map(|phase| phase.name.clone());
        let today_brief = if memory_signals.is_empty() {
            "O cluster está pronto para começar a formar continuidade: capture uma decisão, importe uma conversa ou retome um projeto ativo.".to_string()
        } else {
            format!(
                "O Exocortex tem {} sinais recentes e está ancorado em {}.",
                memory_signals.len(),
                current_self.label
            )
        };
        let recommended_next_action = open_loops.first().cloned().unwrap_or_else(|| {
            active_project
                .as_ref()
                .map(|project| {
                    format!(
                        "Retomar {} e registrar o próximo passo como memória.",
                        project
                    )
                })
                .unwrap_or_else(|| {
                    "Registrar uma intenção ou importar uma conversa importante.".to_string()
                })
        });
        let body_context = target_hardware
            .as_ref()
            .map(|hardware| format_target_hardware_context(hardware, requested_platform.as_deref()))
            .or_else(|| {
                requested_platform.map(|platform| {
                    format!(
                        "Superfície ativa: {}. HealthKit entra como contexto quando disponível.",
                        platform
                    )
                })
            });
        let latest_audit = audit_events.first();
        let recent_observations = agent_observations
            .iter()
            .map(|observation| observation.observation.clone())
            .chain(
                audit_events
                    .iter()
                    .filter_map(|event| event.summary.clone())
                    .take(3),
            )
            .take(5)
            .collect::<Vec<_>>();
        let agent_context = Some(AgentContext {
            active_sessions: audit_events
                .iter()
                .filter(|event| event.tool_name.as_deref() == Some("beagle_agent_session_start"))
                .filter(|event| event.status == "success")
                .count(),
            recent_observations,
            last_agent_write: latest_audit
                .and_then(|event| event.tool_name.clone())
                .or_else(|| memory_events.first().map(|event| event.kind.clone())),
            mcp_status: if audit_events.is_empty() {
                "waiting-for-first-agent-write".to_string()
            } else {
                "audited".to_string()
            },
        });
        let projection_status = self.memory_projection_status().ok();
        let trust_context = Some(TrustContext {
            mcp_status: if audit_events.is_empty() {
                "no-audit-events-yet".to_string()
            } else {
                "audit-log-observed".to_string()
            },
            active_scopes: latest_audit
                .map(|event| event.granted_scopes.clone())
                .filter(|scopes| !scopes.is_empty())
                .unwrap_or_else(default_mcp_scopes),
            audit_freshness: latest_audit
                .map(|event| event.created_at.clone())
                .unwrap_or_else(|| "no audit events yet".to_string()),
            destructive_actions:
                "locked: requires admin:destructive scope and explicit future endpoint".to_string(),
            tool_manifest_hash: latest_audit
                .and_then(|event| metadata_string(&event.metadata, "tool_manifest_hash")),
            last_audit_event_id: latest_audit.map(|event| event.id.clone()),
            memory_projection_status: projection_status.clone(),
        });
        let temporal_phase = temporal_phase.or_else(|| {
            causal_hypotheses
                .first()
                .map(|hypothesis| format!("Causal hypothesis: {}", hypothesis.effect_candidate))
        });
        let snapshot = ExocortexHomeSnapshot {
            generated_at: Utc::now().to_rfc3339(),
            today_brief,
            current_self,
            memory_signals,
            open_loops,
            active_project_ref: active_project,
            body_context,
            recommended_next_action,
            cluster_truth: "observed".to_string(),
            omnimemory_status: projection_status
                .as_ref()
                .map(|status| {
                    format!(
                        "{} imports, {} episodes, {} atoms projected",
                        imports.len(),
                        status.episode_count,
                        status.atom_count
                    )
                })
                .unwrap_or_else(|| format!("{} imports indexed", imports.len())),
            temporal_phase,
            agent_context,
            trust_context,
        };
        self.write_snapshot(HOME_SNAPSHOT, &snapshot)?;
        Ok(snapshot)
    }

    fn append_jsonl<T: Serialize>(&self, file_name: &str, value: &T) -> anyhow::Result<()> {
        self.ensure()?;
        let path = self.root.join(file_name);
        let mut file = OpenOptions::new().create(true).append(true).open(path)?;
        serde_json::to_writer(&mut file, value)?;
        file.write_all(b"\n")?;
        file.flush()?;
        Ok(())
    }

    fn read_recent_jsonl<T: for<'de> Deserialize<'de>>(
        &self,
        file_name: &str,
        limit: usize,
    ) -> anyhow::Result<Vec<T>> {
        let path = self.root.join(file_name);
        if !path.exists() {
            return Ok(Vec::new());
        }
        let file = File::open(path)?;
        let reader = BufReader::new(file);
        let mut values = Vec::new();
        for line in reader.lines() {
            let line = line?;
            if line.trim().is_empty() {
                continue;
            }
            values.push(serde_json::from_str::<T>(&line)?);
        }
        values.reverse();
        values.truncate(limit);
        Ok(values)
    }

    fn write_snapshot<T: Serialize>(&self, file_name: &str, value: &T) -> anyhow::Result<()> {
        self.ensure()?;
        let path = self.root.join(file_name);
        let tmp = path.with_extension("tmp");
        {
            let mut file = File::create(&tmp)?;
            serde_json::to_writer_pretty(&mut file, value)?;
            file.write_all(b"\n")?;
            file.flush()?;
        }
        fs::rename(tmp, path)?;
        Ok(())
    }

    fn read_snapshot<T: for<'de> Deserialize<'de>>(
        &self,
        file_name: &str,
    ) -> anyhow::Result<Option<T>> {
        let path = self.root.join(file_name);
        if !path.exists() {
            return Ok(None);
        }
        let data = fs::read_to_string(path)?;
        Ok(Some(serde_json::from_str(&data)?))
    }
}

fn chronoself_hash(
    self_version: &str,
    parent_commit_ids: &[String],
    context_snapshot: &ContextSnapshot,
    identity_delta: &IdentityDelta,
    trigger_type: &str,
) -> anyhow::Result<String> {
    let mut hasher = Sha256::new();
    hasher.update(self_version.as_bytes());
    hasher.update(serde_json::to_vec(parent_commit_ids)?);
    hasher.update(serde_json::to_vec(context_snapshot)?);
    hasher.update(serde_json::to_vec(identity_delta)?);
    hasher.update(trigger_type.as_bytes());
    Ok(hex_digest(hasher.finalize()))
}

fn content_hash(bytes: &[u8]) -> String {
    let mut hasher = Sha256::new();
    hasher.update(bytes);
    hex_digest(hasher.finalize())
}

fn hex_digest(bytes: impl AsRef<[u8]>) -> String {
    bytes
        .as_ref()
        .iter()
        .map(|byte| format!("{:02x}", byte))
        .collect()
}

fn confidence_for_delta(delta: &IdentityDelta) -> f64 {
    let change_count = delta.beliefs_added.len()
        + delta.beliefs_removed.len()
        + delta.values_changed.len()
        + delta.product_principles.len();
    (1.0 - (change_count as f64 * 0.05)).clamp(0.60, 0.95)
}

fn format_target_hardware_context(hardware: &TargetHardware, platform: Option<&str>) -> String {
    let phone = hardware.phone.as_deref().unwrap_or("iPhone");
    let watch = hardware.watch.as_deref().unwrap_or("Apple Watch");
    let mut context = format!(
        "Alvo Apple principal: {} como superfície íntima do Exocortex e {} como sensor corporal/microinterface.",
        phone, watch
    );
    if let Some(platform) = platform {
        context.push_str(&format!(" Superfície ativa: {}.", platform));
    }
    if let Some(note) = hardware.notes.first() {
        context.push_str(&format!(" {}", truncate_chars(note, 180)));
    }
    context
}

fn self_version_from_commit(commit: &ChronoselfCommit) -> SelfVersion {
    SelfVersion {
        id: commit.self_version.clone(),
        label: commit
            .summary
            .clone()
            .unwrap_or_else(|| "Current self".to_string()),
        period_start: commit.created_at.clone(),
        period_end: None,
        dominant_beliefs: commit.identity_delta.beliefs_added.clone(),
        core_values: commit
            .identity_delta
            .values_changed
            .iter()
            .map(|value| CoreValue {
                name: value.value.clone(),
                strength: value.new_strength,
            })
            .collect(),
        cognitive_style: commit
            .identity_delta
            .cognitive_style_shift
            .clone()
            .unwrap_or_else(|| "cluster-first continuity".to_string()),
        risk_tolerance: 0.5,
        source_commit_id: Some(commit.id.clone()),
    }
}

fn default_self_version() -> SelfVersion {
    let now = Utc::now().to_rfc3339();
    SelfVersion {
        id: "v0.bootstrap".to_string(),
        label: "Bootstrap Self".to_string(),
        period_start: now,
        period_end: None,
        dominant_beliefs: vec!["Beagle is a cluster-first exocortex.".to_string()],
        core_values: vec![CoreValue {
            name: "continuity".to_string(),
            strength: 1.0,
        }],
        cognitive_style: "forming continuity".to_string(),
        risk_tolerance: 0.5,
        source_commit_id: None,
    }
}

fn extract_conversation_signals(raw: &str, tags: &[String]) -> OmniExtraction {
    let mut lines = raw
        .lines()
        .map(str::trim)
        .filter(|line| !line.is_empty())
        .collect::<Vec<_>>();
    if lines.is_empty() && !raw.trim().is_empty() {
        lines.push(raw.trim());
    }
    let key_insights = lines
        .iter()
        .filter(|line| is_signal_line(line))
        .take(6)
        .map(|line| truncate_chars(line, 280))
        .collect::<Vec<_>>();
    let decisions = lines
        .iter()
        .filter(|line| {
            contains_any(
                line,
                &["decidi", "decisão", "decision", "vamos", "priorizar"],
            )
        })
        .take(6)
        .map(|line| truncate_chars(line, 240))
        .collect::<Vec<_>>();
    let hypotheses = lines
        .iter()
        .filter(|line| contains_any(line, &["hipótese", "hypothesis", "talvez", "maybe"]))
        .take(6)
        .map(|line| truncate_chars(line, 240))
        .collect::<Vec<_>>();
    let unresolved_questions = lines
        .iter()
        .filter(|line| line.ends_with('?'))
        .take(6)
        .map(|line| truncate_chars(line, 240))
        .collect::<Vec<_>>();
    OmniExtraction {
        key_insights,
        decisions,
        hypotheses,
        belief_changes: Vec::new(),
        emotional_state: None,
        identity_signals: None,
        projects_mentioned: tags
            .iter()
            .filter(|tag| tag.starts_with("project:"))
            .map(|tag| tag.trim_start_matches("project:").to_string())
            .collect(),
        unresolved_questions,
    }
}

fn contains_any(line: &str, needles: &[&str]) -> bool {
    let lower = line.to_lowercase();
    needles.iter().any(|needle| lower.contains(needle))
}

fn default_mcp_scopes() -> Vec<String> {
    [
        "exocortex:read",
        "memory:write",
        "chronoself:write",
        "research:run",
        "agent:start",
    ]
    .iter()
    .map(|scope| scope.to_string())
    .collect()
}

fn metadata_string(value: &serde_json::Value, key: &str) -> Option<String> {
    value
        .as_object()
        .and_then(|object| object.get(key))
        .and_then(|value| value.as_str())
        .map(|value| value.to_string())
}

fn metadata_string_array(
    metadata: &serde_json::Map<String, serde_json::Value>,
    key: &str,
) -> Vec<String> {
    match metadata.get(key) {
        Some(serde_json::Value::Array(values)) => values
            .iter()
            .filter_map(|value| value.as_str())
            .map(str::trim)
            .filter(|value| !value.is_empty())
            .map(ToOwned::to_owned)
            .collect(),
        Some(serde_json::Value::String(value)) if !value.trim().is_empty() => {
            value.split_whitespace().map(ToOwned::to_owned).collect()
        }
        _ => Vec::new(),
    }
}

fn ensure_object(value: serde_json::Value) -> serde_json::Map<String, serde_json::Value> {
    match value {
        serde_json::Value::Object(object) => object,
        serde_json::Value::Null => serde_json::Map::new(),
        other => {
            let mut object = serde_json::Map::new();
            object.insert("raw_metadata".to_string(), other);
            object
        }
    }
}

fn assisted_raw_content(turns: &[AssistedImportTurn]) -> String {
    turns
        .iter()
        .enumerate()
        .map(|(index, turn)| {
            let timestamp = turn
                .timestamp
                .as_deref()
                .map(|value| format!(" @ {}", value))
                .unwrap_or_default();
            let model = turn
                .model
                .as_deref()
                .map(|value| format!("/{}", value))
                .unwrap_or_default();
            format!(
                "[{}:{}{}{}]\n{}",
                index + 1,
                turn.role.trim(),
                model,
                timestamp,
                turn.content
            )
        })
        .collect::<Vec<_>>()
        .join("\n\n")
}

fn project_slug(value: &str) -> String {
    value
        .trim()
        .to_lowercase()
        .chars()
        .map(|ch| if ch.is_ascii_alphanumeric() { ch } else { '-' })
        .collect::<String>()
        .split('-')
        .filter(|part| !part.is_empty())
        .collect::<Vec<_>>()
        .join("-")
}

fn upsert_project(projects: &mut Vec<ProjectState>, incoming: ProjectState) {
    if let Some(existing) = projects
        .iter_mut()
        .find(|project| project.id == incoming.id)
    {
        existing.status = incoming.status;
        merge_unique(&mut existing.recent_events, incoming.recent_events, 6);
        merge_unique(&mut existing.next_actions, incoming.next_actions, 6);
        merge_unique(&mut existing.linked_memories, incoming.linked_memories, 10);
        if incoming.last_interaction_at.as_deref() > existing.last_interaction_at.as_deref() {
            existing.last_interaction_at = incoming.last_interaction_at;
        }
    } else {
        projects.push(incoming);
    }
}

fn merge_unique(target: &mut Vec<String>, incoming: Vec<String>, limit: usize) {
    for item in incoming {
        if !item.trim().is_empty() && !target.contains(&item) {
            target.push(item);
        }
    }
    target.truncate(limit);
}

fn is_signal_line(line: &str) -> bool {
    line.len() > 40
        && contains_any(
            line,
            &[
                "exocortex",
                "beagle",
                "memória",
                "memory",
                "chronoself",
                "temporal",
                "identidade",
                "identity",
                "decisão",
                "decision",
            ],
        )
}

fn normalize_source_platform(value: &str) -> String {
    match value.trim().to_lowercase().as_str() {
        "chatgpt" | "chat gpt" | "openai" => "chatgpt".to_string(),
        "claude" | "anthropic" => "claude".to_string(),
        "grok" | "xai" | "x.ai" => "grok".to_string(),
        "gemini" | "google" => "gemini".to_string(),
        other if !other.is_empty() => other.to_string(),
        _ => "other".to_string(),
    }
}

fn commit_matches_topic(commit: &ChronoselfCommit, topic_lc: &str) -> bool {
    let haystack = serde_json::to_string(commit)
        .unwrap_or_default()
        .to_lowercase();
    haystack.contains(topic_lc)
}

fn import_matches_topic(import: &OmniConversation, topic_lc: &str) -> bool {
    let haystack = serde_json::to_string(import)
        .unwrap_or_default()
        .to_lowercase();
    haystack.contains(topic_lc)
}

pub(crate) fn query_projected_memory_for_memory_api(
    query: beagle_memory::MemoryQuery,
) -> anyhow::Result<Option<beagle_memory::MemoryResult>> {
    let repo = ExocortexRepository::default();
    repo.ensure()?;
    let status = repo.memory_projection_status()?;
    if status.atom_count == 0 {
        return Ok(None);
    }
    let response = repo.graphrag_query(GraphRagQueryRequest {
        query: query.query,
        scope: query.scope,
        max_items: query.max_items,
    })?;
    Ok(Some(graphrag_to_memory_result(response)))
}

fn graphrag_to_memory_result(response: GraphRagQueryResponse) -> beagle_memory::MemoryResult {
    let highlights = response
        .evidence
        .iter()
        .map(|evidence| {
            let episode = response
                .episodes
                .iter()
                .find(|episode| episode.id == evidence.episode_id);
            beagle_memory::MemoryResultHighlight {
                source: episode
                    .map(|episode| episode.source.clone())
                    .unwrap_or_else(|| "graphrag++".to_string()),
                date: episode
                    .and_then(|episode| episode.occurred_at.as_deref())
                    .and_then(|date| chrono::DateTime::parse_from_rfc3339(date).ok())
                    .map(|date| date.with_timezone(&Utc)),
                snippet: evidence.text.clone(),
                run_id: None,
                session_id: episode.and_then(|episode| episode.session_id.clone()),
                relevance: evidence.score as f32,
            }
        })
        .collect();
    beagle_memory::MemoryResult {
        summary: response.summary,
        highlights,
        links: response
            .evidence
            .iter()
            .flat_map(|evidence| evidence.source_refs.clone())
            .map(serde_json::Value::String)
            .collect(),
    }
}

#[derive(Debug, Default)]
struct ProjectionOutcome {
    episodes_created: usize,
    atoms_created: usize,
    duplicates: usize,
}

fn default_sensitive_privacy_class() -> String {
    "sensitive".to_string()
}

fn default_assisted_source_surface() -> String {
    "mcp-visible-context".to_string()
}

fn default_assisted_import_scope() -> String {
    "current_conversation".to_string()
}

fn default_one_u32() -> u32 {
    1
}

fn normalize_privacy_class(value: Option<&str>) -> String {
    match value
        .unwrap_or("sensitive")
        .trim()
        .to_lowercase()
        .replace('-', "_")
        .as_str()
    {
        "public" => "public".to_string(),
        "restricted" | "secret" | "credential" => "restricted".to_string(),
        _ => "sensitive".to_string(),
    }
}

fn projection_hash(episodes: &[MemoryEpisode], atoms: &[MemoryAtom]) -> anyhow::Result<String> {
    let mut hasher = Sha256::new();
    hasher.update(MEMORY_PROJECTION_SCHEMA.as_bytes());
    hasher.update(serde_json::to_vec(episodes)?);
    hasher.update(serde_json::to_vec(atoms)?);
    Ok(format!("sha256:{}", hex_digest(hasher.finalize())))
}

fn stable_id(prefix: &str, parts: &[&str]) -> String {
    let mut hasher = Sha256::new();
    hasher.update(prefix.as_bytes());
    for part in parts {
        hasher.update(b"\0");
        hasher.update(part.as_bytes());
    }
    format!("{}:{}", prefix, hex_digest(hasher.finalize()))
}

fn atoms_from_import(import: &OmniConversation, episode: &MemoryEpisode) -> Vec<MemoryAtom> {
    let mut atoms = Vec::new();
    push_atoms(
        &mut atoms,
        "insight",
        &import.extracted.key_insights,
        import,
        episode,
    );
    push_atoms(
        &mut atoms,
        "decision",
        &import.extracted.decisions,
        import,
        episode,
    );
    push_atoms(
        &mut atoms,
        "hypothesis",
        &import.extracted.hypotheses,
        import,
        episode,
    );
    push_atoms(
        &mut atoms,
        "belief_change",
        &import.extracted.belief_changes,
        import,
        episode,
    );
    push_atoms(
        &mut atoms,
        "open_question",
        &import.extracted.unresolved_questions,
        import,
        episode,
    );
    push_atoms(
        &mut atoms,
        "project",
        &import.extracted.projects_mentioned,
        import,
        episode,
    );
    atoms
}

fn push_atoms(
    atoms: &mut Vec<MemoryAtom>,
    atom_type: &str,
    values: &[String],
    import: &OmniConversation,
    episode: &MemoryEpisode,
) {
    for value in values {
        let text = truncate_chars(value, 500);
        let atom = MemoryAtom {
            id: stable_id("atom", &[&episode.id, atom_type, &text]),
            created_at: Utc::now().to_rfc3339(),
            episode_id: episode.id.clone(),
            atom_type: atom_type.to_string(),
            normalized_text: normalize_text(&text),
            text,
            source_refs: vec![episode.source_ref.clone(), import.raw_content_ref.clone()],
            relations: relations_for_import(import, episode),
            tags: import.tags.clone(),
            confidence: import.confidence_score,
            privacy_class: import.privacy_class.clone(),
            occurred_at: episode.occurred_at.clone(),
        };
        atoms.push(atom);
    }
}

fn relations_for_import(import: &OmniConversation, episode: &MemoryEpisode) -> Vec<MemoryRelation> {
    let mut relations = relations_for_tags(&import.tags, &episode.id);
    for project in &import.extracted.projects_mentioned {
        relations.push(MemoryRelation {
            subject: project.clone(),
            predicate: "mentioned_in".to_string(),
            object: episode.id.clone(),
            confidence: 0.78,
        });
    }
    for decision in &import.extracted.decisions {
        for hypothesis in &import.extracted.hypotheses {
            relations.push(MemoryRelation {
                subject: truncate_chars(decision, 120),
                predicate: "informs_hypothesis".to_string(),
                object: truncate_chars(hypothesis, 120),
                confidence: 0.58,
            });
        }
    }
    relations
}

fn relations_for_tags(tags: &[String], episode_id: &str) -> Vec<MemoryRelation> {
    tags.iter()
        .filter_map(|tag| tag.strip_prefix("project:"))
        .map(|project| MemoryRelation {
            subject: project.to_string(),
            predicate: "has_episode".to_string(),
            object: episode_id.to_string(),
            confidence: 0.72,
        })
        .collect()
}

fn normalize_text(value: &str) -> String {
    value
        .to_lowercase()
        .split_whitespace()
        .collect::<Vec<_>>()
        .join(" ")
}

fn tokenize(value: &str) -> Vec<String> {
    value
        .to_lowercase()
        .split(|ch: char| !ch.is_alphanumeric())
        .filter(|token| token.len() > 2)
        .map(ToOwned::to_owned)
        .collect()
}

fn atom_score(atom: &MemoryAtom, query_tokens: &[String]) -> f64 {
    if query_tokens.is_empty() {
        return 0.0;
    }
    let text = atom.normalized_text.as_str();
    let token_hits = query_tokens
        .iter()
        .filter(|token| text.contains(token.as_str()))
        .count();
    if token_hits == 0 {
        return 0.0;
    }
    let lexical = token_hits as f64 / query_tokens.len() as f64;
    let type_boost = match atom.atom_type.as_str() {
        "decision" => 0.12,
        "hypothesis" => 0.10,
        "belief_change" => 0.09,
        "project" => 0.06,
        _ => 0.0,
    };
    let graph_boost = if atom.relations.is_empty() { 0.0 } else { 0.08 };
    let recency_boost = atom
        .occurred_at
        .as_deref()
        .and_then(|date| chrono::DateTime::parse_from_rfc3339(date).ok())
        .map(|date| {
            let age_days = (Utc::now() - date.with_timezone(&Utc)).num_days().max(0) as f64;
            (0.08 / (1.0 + age_days / 30.0)).clamp(0.0, 0.08)
        })
        .unwrap_or(0.0);
    (lexical * 0.72 + type_boost + graph_boost + recency_boost)
        .min(1.0)
        .max(0.0)
}

fn truncate_chars(value: &str, max_chars: usize) -> String {
    value.chars().take(max_chars).collect()
}

#[cfg(test)]
mod tests {
    use super::*;
    use tempfile::tempdir;

    #[test]
    fn repository_appends_commits_and_reads_newest_first() {
        let dir = tempdir().unwrap();
        let repo = ExocortexRepository::new(dir.path().join("exocortex"));
        let first = repo
            .create_commit(CreateCommitRequest {
                user_id: Some("test".to_string()),
                self_version: Some("v2026.04.25.01".to_string()),
                parent_commit_ids: Vec::new(),
                context_snapshot: None,
                identity_delta: IdentityDelta {
                    beliefs_added: vec!["continuity matters".to_string()],
                    ..Default::default()
                },
                trigger_type: Some("manual".to_string()),
                confidence: None,
                source_refs: Vec::new(),
                summary: Some("First".to_string()),
            })
            .unwrap();
        let second = repo
            .create_commit(CreateCommitRequest {
                user_id: Some("test".to_string()),
                self_version: Some("v2026.04.25.02".to_string()),
                parent_commit_ids: Vec::new(),
                context_snapshot: None,
                identity_delta: IdentityDelta::default(),
                trigger_type: Some("manual".to_string()),
                confidence: None,
                source_refs: Vec::new(),
                summary: Some("Second".to_string()),
            })
            .unwrap();
        assert_eq!(second.parent_commit_ids, vec![first.id]);
        let commits = repo
            .read_recent_jsonl::<ChronoselfCommit>(CHRONOSELF_LOG, 2)
            .unwrap();
        assert_eq!(commits[0].id, second.id);
        assert_eq!(commits[1].summary.as_deref(), Some("First"));
    }

    #[test]
    fn chronoself_hash_changes_when_delta_changes() {
        let ctx = ContextSnapshot {
            health_ref: None,
            active_project_ids: Vec::new(),
            recent_decision_ids: Vec::new(),
            energy_level: None,
            emotional_valence: None,
            platform: None,
            target_hardware: None,
        };
        let a = chronoself_hash(
            "v1",
            &[],
            &ctx,
            &IdentityDelta {
                beliefs_added: vec!["a".to_string()],
                ..Default::default()
            },
            "manual",
        )
        .unwrap();
        let b = chronoself_hash(
            "v1",
            &[],
            &ctx,
            &IdentityDelta {
                beliefs_added: vec!["b".to_string()],
                ..Default::default()
            },
            "manual",
        )
        .unwrap();
        assert_ne!(a, b);
        assert_eq!(a.len(), 64);
    }

    #[test]
    fn omnimemory_import_can_create_linked_commit() {
        let dir = tempdir().unwrap();
        let repo = ExocortexRepository::new(dir.path().join("exocortex"));
        let imported = repo
            .import_conversation(ImportConversationRequest {
                source_platform: "ChatGPT".to_string(),
                session_id: None,
                original_date: None,
                raw_content: "Decisão: Beagle precisa de MCP como sistema nervoso do exocortex."
                    .to_string(),
                title: Some("MCP decision".to_string()),
                tags: vec!["project:sounio".to_string()],
                extracted: None,
                confidence_score: Some(0.8),
                create_chronoself_commit: Some(true),
                privacy_class: None,
                metadata: None,
            })
            .unwrap();
        assert_eq!(imported.source_platform, "chatgpt");
        assert_eq!(imported.linked_chronoself_commits.len(), 1);
        let duplicate = repo
            .import_conversation(ImportConversationRequest {
                source_platform: "ChatGPT".to_string(),
                session_id: None,
                original_date: None,
                raw_content: "Decisão: Beagle precisa de MCP como sistema nervoso do exocortex."
                    .to_string(),
                title: Some("MCP decision duplicate".to_string()),
                tags: vec!["project:sounio".to_string()],
                extracted: None,
                confidence_score: Some(0.8),
                create_chronoself_commit: Some(true),
                privacy_class: None,
                metadata: None,
            })
            .unwrap();
        assert_eq!(duplicate.id, imported.id);
        let imports = repo
            .read_recent_jsonl::<OmniConversation>(OMNIMEMORY_LOG, 10)
            .unwrap();
        assert_eq!(imports.len(), 1);
    }

    #[test]
    fn audit_and_memory_events_are_append_only_and_feed_home_trust() {
        let dir = tempdir().unwrap();
        let repo = ExocortexRepository::new(dir.path().join("exocortex"));
        let audit = repo
            .create_audit_event(CreateAuditEventRequest {
                client_id: Some("claude-desktop".to_string()),
                action: Some("tools/call".to_string()),
                tool_name: Some("beagle_memory_ingest_chat".to_string()),
                risk_level: Some("write".to_string()),
                required_scopes: vec!["memory:write".to_string()],
                granted_scopes: vec!["exocortex:read".to_string(), "memory:write".to_string()],
                status: Some("success".to_string()),
                source: Some("mcp".to_string()),
                target_ref: None,
                summary: Some("Stored a conversation turn.".to_string()),
                metadata: Some(serde_json::json!({
                    "tool_manifest_hash": "sha256:test"
                })),
            })
            .unwrap();
        let memory = repo
            .create_memory_event(CreateMemoryEventRequest {
                source: Some("mcp".to_string()),
                kind: Some("agent_write".to_string()),
                content_ref: Some("memory:abc".to_string()),
                summary: Some("Beagle MCP is now audited.".to_string()),
                tags: vec!["project:sounio".to_string()],
                metadata: None,
                linked_chronoself_commits: Vec::new(),
                confidence: Some(0.8),
            })
            .unwrap();
        let audits = repo.read_recent_jsonl::<AuditEvent>(AUDIT_LOG, 5).unwrap();
        let memories = repo
            .read_recent_jsonl::<MemoryEvent>(MEMORY_EVENTS_LOG, 5)
            .unwrap();
        assert_eq!(audits[0].id, audit.id);
        assert_eq!(memories[0].id, memory.id);

        let home = repo
            .build_home_snapshot(HomeQuery {
                active_project_slug: None,
                platform: Some("mcp".to_string()),
            })
            .unwrap();
        let trust = home.trust_context.unwrap();
        assert_eq!(trust.mcp_status, "audit-log-observed");
        assert_eq!(trust.tool_manifest_hash.as_deref(), Some("sha256:test"));
        assert!(home
            .memory_signals
            .iter()
            .any(|signal| signal.contains("audited")));
    }

    #[test]
    fn active_projects_are_reconstructed_from_append_only_events() {
        let dir = tempdir().unwrap();
        let repo = ExocortexRepository::new(dir.path().join("exocortex"));
        repo.create_memory_event(CreateMemoryEventRequest {
            source: Some("mcp".to_string()),
            kind: Some("agent_write".to_string()),
            content_ref: None,
            summary: Some("Next action for iPhone Home.".to_string()),
            tags: vec!["project:Beagle Apple Suite".to_string()],
            metadata: None,
            linked_chronoself_commits: Vec::new(),
            confidence: Some(0.7),
        })
        .unwrap();
        let projects = repo.active_projects().unwrap();
        assert_eq!(projects[0].id, "beagle-apple-suite");
        assert!(projects[0]
            .recent_events
            .iter()
            .any(|event| event.contains("iPhone")));
    }

    #[test]
    fn omnimemory_import_creates_projected_episode_and_atoms() {
        let dir = tempdir().unwrap();
        let repo = ExocortexRepository::new(dir.path().join("exocortex"));
        let imported = repo
            .import_conversation(ImportConversationRequest {
                source_platform: "Claude".to_string(),
                session_id: Some("visible-project-1".to_string()),
                original_date: Some("2026-04-26T16:00:00Z".to_string()),
                raw_content: "Decisão: Beagle Memory v1.2 deve priorizar GraphRAG++ persistente.\nHipótese: Episode+Atom melhora recuperação temporal.".to_string(),
                title: Some("GraphRAG++ decision".to_string()),
                tags: vec!["project:beagle".to_string()],
                extracted: None,
                confidence_score: Some(0.86),
                create_chronoself_commit: None,
                privacy_class: None,
                metadata: Some(serde_json::json!({"import_scope": "visible_project"})),
            })
            .unwrap();

        let episodes = repo
            .read_recent_jsonl::<MemoryEpisode>(MEMORY_EPISODES_LOG, 10)
            .unwrap();
        let atoms = repo
            .read_recent_jsonl::<MemoryAtom>(MEMORY_ATOMS_LOG, 10)
            .unwrap();
        assert_eq!(episodes.len(), 1);
        assert_eq!(
            episodes[0].source_ref,
            format!("omnimemory:{}", imported.id)
        );
        assert!(atoms.iter().any(|atom| atom.atom_type == "decision"));
        assert!(atoms.iter().any(|atom| atom.atom_type == "hypothesis"));

        let duplicate_run = repo
            .project_memory(ProjectMemoryRequest {
                rebuild: false,
                source_refs: Vec::new(),
            })
            .unwrap();
        assert!(duplicate_run.duplicates >= 1);
        assert_eq!(
            repo.read_recent_jsonl::<MemoryEpisode>(MEMORY_EPISODES_LOG, 10)
                .unwrap()
                .len(),
            1
        );
    }

    #[test]
    fn graphrag_query_returns_projected_evidence_with_provenance() {
        let dir = tempdir().unwrap();
        let repo = ExocortexRepository::new(dir.path().join("exocortex"));
        repo.import_conversation(ImportConversationRequest {
            source_platform: "Claude".to_string(),
            session_id: Some("session-graphrag".to_string()),
            original_date: Some("2026-04-26T16:00:00Z".to_string()),
            raw_content: "Decisão: GraphRAG++ persistente deve ser o núcleo do exocortex Beagle."
                .to_string(),
            title: Some("Persistent memory".to_string()),
            tags: vec!["project:beagle".to_string()],
            extracted: Some(OmniExtraction {
                decisions: vec![
                    "GraphRAG++ persistente deve ser o núcleo do exocortex Beagle.".to_string(),
                ],
                projects_mentioned: vec!["beagle".to_string()],
                ..Default::default()
            }),
            confidence_score: Some(0.9),
            create_chronoself_commit: None,
            privacy_class: Some("sensitive".to_string()),
            metadata: None,
        })
        .unwrap();

        let result = repo
            .graphrag_query(GraphRagQueryRequest {
                query: "núcleo exocortex GraphRAG".to_string(),
                scope: None,
                max_items: Some(5),
            })
            .unwrap();
        assert_eq!(result.evidence.len(), 1);
        assert_eq!(result.evidence[0].atom_type, "decision");
        assert!(result
            .relations
            .iter()
            .any(|relation| relation.subject == "beagle"));
        assert!(result.degraded_reason.is_some());
    }

    #[test]
    fn restricted_import_is_not_projected() {
        let dir = tempdir().unwrap();
        let repo = ExocortexRepository::new(dir.path().join("exocortex"));
        repo.import_conversation(ImportConversationRequest {
            source_platform: "manual".to_string(),
            session_id: Some("restricted-session".to_string()),
            original_date: None,
            raw_content: "Decisão: este payload restrito não deve virar átomo.".to_string(),
            title: Some("Restricted pilot".to_string()),
            tags: vec!["project:beagle".to_string()],
            extracted: None,
            confidence_score: Some(0.8),
            create_chronoself_commit: None,
            privacy_class: Some("restricted".to_string()),
            metadata: None,
        })
        .unwrap();

        let status = repo.memory_projection_status().unwrap();
        assert_eq!(status.episode_count, 0);
        assert_eq!(status.atom_count, 0);
    }

    #[test]
    fn assisted_import_batch_creates_omnimemory_projection_memory_and_audit() {
        let dir = tempdir().unwrap();
        let repo = ExocortexRepository::new(dir.path().join("exocortex"));
        let result = repo
            .assisted_import_batch(AssistedImportBatchRequest {
                source_platform: "Claude".to_string(),
                source_surface: "claude-ios".to_string(),
                import_scope: "current_conversation".to_string(),
                session_id: "claude-ios-visible-1".to_string(),
                project_ref: Some("beagle".to_string()),
                batch_index: 1,
                batch_total: 1,
                turns: vec![
                    AssistedImportTurn {
                        role: "user".to_string(),
                        content: "Decisão: Beagle deve usar GraphRAG++ persistente como núcleo."
                            .to_string(),
                        timestamp: Some("2026-04-26T16:30:00Z".to_string()),
                        model: None,
                    },
                    AssistedImportTurn {
                        role: "assistant".to_string(),
                        content:
                            "Hipótese: Claude iOS deve importar contexto visível via MCP para Episode+Atom."
                                .to_string(),
                        timestamp: Some("2026-04-26T16:31:00Z".to_string()),
                        model: Some("claude-sonnet-4".to_string()),
                    },
                ],
                tags: vec!["surface:claude-ios".to_string()],
                metadata: serde_json::json!({
                    "principal": "claude-connector",
                    "surface_observed": "anthropic-cloud",
                    "scopes": ["exocortex:read", "memory:write"],
                    "tool_manifest_hash": "sha256:test"
                }),
                coverage: serde_json::json!({"visible_turns": 2}),
                extracted: Some(OmniExtraction {
                    decisions: vec![
                        "Beagle deve usar GraphRAG++ persistente como núcleo.".to_string(),
                    ],
                    hypotheses: vec![
                        "Claude iOS deve importar contexto visível via MCP para Episode+Atom."
                            .to_string(),
                    ],
                    projects_mentioned: vec!["beagle".to_string()],
                    ..Default::default()
                }),
                privacy_class: Some("sensitive".to_string()),
                title: Some("Claude iOS visible context".to_string()),
                original_date: None,
                confidence_score: Some(0.88),
                create_chronoself_commit: Some(false),
            })
            .unwrap();

        assert_eq!(result.status, "imported");
        assert_eq!(result.source_platform, "claude");
        assert_eq!(result.source_surface, "claude-ios");
        assert_eq!(result.privacy_class, "sensitive");
        assert!(result.omnimemory.is_some());
        assert!(result.projection.as_ref().unwrap().atoms_created >= 2);
        assert_eq!(
            result.memory_event.as_ref().unwrap().kind,
            "assisted_import_batch"
        );
        assert_eq!(result.audit_event.as_ref().unwrap().status, "success");

        let status = repo.memory_projection_status().unwrap();
        assert_eq!(status.episode_count, 1);
        assert!(status.atom_count >= 2);
        let query = repo
            .graphrag_query(GraphRagQueryRequest {
                query: "GraphRAG núcleo Claude iOS".to_string(),
                scope: None,
                max_items: Some(5),
            })
            .unwrap();
        assert!(!query.evidence.is_empty());
        assert!(query
            .evidence
            .iter()
            .any(|item| item.provenance["metadata"]["source_surface"] == "claude-ios"));
    }

    #[test]
    fn assisted_import_rejects_restricted_payload_before_omnimemory_write() {
        let dir = tempdir().unwrap();
        let repo = ExocortexRepository::new(dir.path().join("exocortex"));
        let result = repo
            .assisted_import_batch(AssistedImportBatchRequest {
                source_platform: "ChatGPT".to_string(),
                source_surface: "chatgpt-web".to_string(),
                import_scope: "current_conversation".to_string(),
                session_id: "restricted-visible-1".to_string(),
                project_ref: None,
                batch_index: 1,
                batch_total: 1,
                turns: vec![AssistedImportTurn {
                    role: "user".to_string(),
                    content: "Restricted payload".to_string(),
                    timestamp: None,
                    model: None,
                }],
                tags: Vec::new(),
                metadata: serde_json::json!({"principal": "chatgpt-connector"}),
                coverage: serde_json::Value::Null,
                extracted: None,
                privacy_class: Some("restricted".to_string()),
                title: None,
                original_date: None,
                confidence_score: None,
                create_chronoself_commit: None,
            })
            .unwrap();

        assert_eq!(result.status, "rejected");
        assert!(result.omnimemory.is_none());
        assert_eq!(result.audit_event.as_ref().unwrap().status, "rejected");
        assert_eq!(
            repo.read_recent_jsonl::<OmniConversation>(OMNIMEMORY_LOG, 10)
                .unwrap()
                .len(),
            0
        );
        assert_eq!(
            repo.read_recent_jsonl::<AuditEvent>(AUDIT_LOG, 10)
                .unwrap()
                .len(),
            1
        );
    }
}
