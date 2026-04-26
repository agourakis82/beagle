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
const AGENT_OBSERVATIONS_LOG: &str = "agent_observations.jsonl";
const PROJECT_STATES_LOG: &str = "project_states.jsonl";
const CAUSAL_HYPOTHESES_LOG: &str = "causal_hypotheses.jsonl";
const CURRENT_SELF_SNAPSHOT: &str = "current_self.json";
const HOME_SNAPSHOT: &str = "home_snapshot.json";

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

#[derive(Debug, Clone, Serialize, Deserialize)]
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
            original_date: req.original_date,
            raw_content_ref,
            extracted,
            linked_chronoself_commits,
            linked_memory_events: Vec::new(),
            confidence_score: req.confidence_score.unwrap_or(0.68),
            title: req.title,
        };
        self.append_jsonl(OMNIMEMORY_LOG, &imported)?;
        let home = self.build_home_snapshot(HomeQuery {
            active_project_slug: imported.extracted.projects_mentioned.first().cloned(),
            platform: Some(imported.source_platform.clone()),
        })?;
        self.write_snapshot(HOME_SNAPSHOT, &home)?;
        Ok(imported)
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
        let memory_signals = commits
            .iter()
            .filter_map(|commit| {
                commit
                    .summary
                    .clone()
                    .or_else(|| commit.identity_delta.cognitive_style_shift.clone())
            })
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
            omnimemory_status: format!("{} imports indexed", imports.len()),
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
                original_date: None,
                raw_content: "Decisão: Beagle precisa de MCP como sistema nervoso do exocortex."
                    .to_string(),
                title: Some("MCP decision".to_string()),
                tags: vec!["project:sounio".to_string()],
                extracted: None,
                confidence_score: Some(0.8),
                create_chronoself_commit: Some(true),
            })
            .unwrap();
        assert_eq!(imported.source_platform, "chatgpt");
        assert_eq!(imported.linked_chronoself_commits.len(), 1);
        let duplicate = repo
            .import_conversation(ImportConversationRequest {
                source_platform: "ChatGPT".to_string(),
                original_date: None,
                raw_content: "Decisão: Beagle precisa de MCP como sistema nervoso do exocortex."
                    .to_string(),
                title: Some("MCP decision duplicate".to_string()),
                tags: vec!["project:sounio".to_string()],
                extracted: None,
                confidence_score: Some(0.8),
                create_chronoself_commit: Some(true),
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
}
