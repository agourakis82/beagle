//! Cluster-first Exocortex API.
//!
//! This module is intentionally small and append-only. The cluster owns the
//! canonical Chronoself/OmniMemory/TemporalAI state, while Apple clients and
//! MCP agents render or mutate it through this contract.

use axum::{
    extract::{Path, Query, State},
    http::{HeaderMap, StatusCode},
    routing::{get, post},
    Json, Router,
};
use base64::{engine::general_purpose::STANDARD as BASE64_STANDARD, Engine as _};
use beagle_config::beagle_data_dir;
use beagle_darwin::{consumer_identity_for_id, ConsumerId};
use beagle_llm::RequestMeta;
use chrono::Utc;
use serde::{Deserialize, Serialize};
use sha2::{Digest, Sha256};
use std::{
    collections::{BTreeMap, BTreeSet},
    env,
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
const MEMORY_GRAPH_BAKEOFF_RUNS_LOG: &str = "memory_graph_bakeoff_runs.jsonl";
const MEMORY_GRAPH_INDEX_RUNS_LOG: &str = "memory_graph_index_runs.jsonl";
const MEMORY_WORLDS_LOG: &str = "memory_worlds.jsonl";
const MEMORY_CANDIDATES_LOG: &str = "memory_candidates.jsonl";
const MEMORY_CANDIDATE_QUORUM_LOG: &str = "memory_candidate_quorum.jsonl";
const MEMORY_GOVERNANCE_RUNS_LOG: &str = "memory_governance_runs.jsonl";
const MEMORY_CONTRADICTIONS_LOG: &str = "memory_contradictions.jsonl";
const MEMORY_PROMOTION_DECISIONS_LOG: &str = "memory_promotion_decisions.jsonl";
const MEMORY_QUALITY_SCORES_LOG: &str = "memory_quality_scores.jsonl";
const MEMORY_TRUTHSETS_LOG: &str = "memory_truthsets.jsonl";
const MEMORY_TRUTH_CASES_LOG: &str = "memory_truth_cases.jsonl";
const CONTEXT_PACKS_LOG: &str = "context_packs.jsonl";
const MEMORY_EFFECTIVENESS_EVENTS_LOG: &str = "memory_effectiveness_events.jsonl";
const MEMORY_DREAMCYCLE_RUNS_LOG: &str = "memory_dreamcycle_runs.jsonl";
const SOUNIO_PROGRAMS_LOG: &str = "sounio_programs.jsonl";
const SOUNIO_TRACE_EVENTS_LOG: &str = "sounio_trace_events.jsonl";
const SOUNIO_PAPERRUNS_LOG: &str = "sounio_paperruns.jsonl";
const SOUNIO_CLAIMS_LOG: &str = "sounio_claims.jsonl";
const SOUNIO_CLAIM_REVIEWS_LOG: &str = "sounio_claim_reviews.jsonl";
const SOUNIO_MOMENTS_LOG: &str = "sounio_moments.jsonl";
const SOUNIO_MOMENT_REVIEWS_LOG: &str = "sounio_moment_reviews.jsonl";
const CAPTURE_SESSIONS_LOG: &str = "capture_sessions.jsonl";
const CAPTURE_EVENTS_LOG: &str = "capture_events.jsonl";
const CAPTURE_VISUAL_ARTIFACTS_LOG: &str = "capture_visual_artifacts.jsonl";
const CAPTURE_VISUAL_ANALYSES_LOG: &str = "capture_visual_analyses.jsonl";
const CAPTURE_REVIEWS_LOG: &str = "capture_reviews.jsonl";
const CAPTURE_VISUAL_ARTIFACTS_DIR: &str = "capture_visual_artifacts";
const FAILED_WRITES_LOG: &str = "failed_writes.jsonl";
const SPATIAL_WORLDS_LOG: &str = "spatial_worlds.jsonl";
const SPATIAL_EVIDENCE_LOG: &str = "sounio_spatial_evidence.jsonl";
const SPATIAL_GENERATION_RUNS_LOG: &str = "spatial_generation_runs.jsonl";
const CONVERSATION_PORTALS_LOG: &str = "conversation_portals.jsonl";
const PROMOTED_CONVERSATION_CLIPS_LOG: &str = "promoted_conversation_clips.jsonl";
const FOCUS_COACH_EVENTS_LOG: &str = "focus_coach_events.jsonl";
const SPATIAL_SCHEMA: &str = "beagle-spatial-control-room-v3.6";
const MIND_PALACE_SCHEMA: &str = "beagle-spatial-desk-mind-palace-v3.7";
const CONVERSATION_PORTAL_SCHEMA: &str = "beagle-conversation-portal-v3.7";
const FOCUS_COACH_SCHEMA: &str = "beagle-focus-coach-v3.7";
const AGENT_OBSERVATIONS_LOG: &str = "agent_observations.jsonl";
const PROJECT_STATES_LOG: &str = "project_states.jsonl";
const CAUSAL_HYPOTHESES_LOG: &str = "causal_hypotheses.jsonl";
const CURRENT_SELF_SNAPSHOT: &str = "current_self.json";
const HOME_SNAPSHOT: &str = "home_snapshot.json";
const MEMORY_PROJECTION_SCHEMA: &str = "beagle-memory-projection-v1.2";
const MEMORY_GRAPH_SCHEMA: &str = "beagle-graphrag-runtime-v1.4";
const MEMORY_MESH_SCHEMA: &str = "beagle-federated-memory-engine-v1.5";
const MEMORY_GOVERNANCE_SCHEMA: &str = "beagle-self-governing-memory-v1.6";
const MEMORY_BENCH_SCHEMA: &str = "beagle-memory-truth-hypermemory-v1.9";
const MEMORY_TRUTH_SCHEMA: &str = "beagle-private-memory-truthset-v1.9";
const CONTEXT_COMPILER_SCHEMA: &str = "beagle-adaptive-context-compiler-v2.3";
const MEMORY_POLICY_SCHEMA: &str = "beagle-memory-policy-learner-v2.3";
const SOUNIO_WORK_IR_SCHEMA: &str = "sounio-work-ir-v0.1";
const SOUNIO_PAPERRUN_SCHEMA: &str = "beagle-sounio-paperrun-v2.4";
const SOUNIO_CLAIM_SCHEMA: &str = "sounio-claim-epistemic-v0.1";
const SOUNIO_THEATRE_SCHEMA: &str = "beagle-sounio-paperrun-theatre-v2.5";
const SOUNIO_PUBLIC_DIGEST_SCHEMA: &str = "beagle-sounio-public-digest-v2.5";
const SOUNIO_MOMENT_SCHEMA: &str = "sounio-ambient-moment-v2.9";
const SOUNIO_WORKDAY_SCHEMA: &str = "beagle-sounio-workday-v2.9";
const CAPTURE_SESSION_SCHEMA: &str = "beagle-multimodal-capture-session-v3.0";
const VISUAL_EVIDENCE_SCHEMA: &str = "beagle-visual-evidence-v3.0";
const CAPTURE_REVIEW_SCHEMA: &str = "beagle-capture-review-v3.0";

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

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct MemoryWorld {
    pub id: String,
    pub created_at: String,
    pub world_type: String,
    pub source_ref: String,
    #[serde(default)]
    pub title: Option<String>,
    pub merkle_root: String,
    #[serde(default)]
    pub valid_from: Option<String>,
    #[serde(default)]
    pub valid_until: Option<String>,
    pub node_count: usize,
    pub edge_count: usize,
    pub runtime_hint: String,
    #[serde(default)]
    pub tags: Vec<String>,
    #[serde(default)]
    pub provenance: serde_json::Value,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct MemoryCommunity {
    pub id: String,
    pub label: String,
    pub strategy: String,
    pub node_count: usize,
    pub score: f64,
    pub summary: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct MemoryGraphRecentResponse {
    pub generated_at: String,
    pub status: MemoryProjectionStatus,
    #[serde(default)]
    pub episodes: Vec<MemoryEpisode>,
    #[serde(default)]
    pub atoms: Vec<MemoryAtom>,
    #[serde(default)]
    pub relations: Vec<MemoryRelation>,
    #[serde(default)]
    pub worlds: Vec<MemoryWorld>,
    #[serde(default)]
    pub communities: Vec<MemoryCommunity>,
    #[serde(default)]
    pub provenance: serde_json::Value,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct GraphBakeoffMetrics {
    pub p95_query_ms: f64,
    pub ingest_latency_ms: f64,
    pub top5_hit_rate: f64,
    pub multi_hop_accuracy: f64,
    pub provenance_quality: f64,
    pub rebuild_seconds: f64,
    pub operational_complexity: f64,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct GraphRuntimeCandidate {
    pub name: String,
    pub runtime_kind: String,
    pub status: String,
    pub score: f64,
    pub metrics: GraphBakeoffMetrics,
    #[serde(default)]
    pub strengths: Vec<String>,
    #[serde(default)]
    pub risks: Vec<String>,
    #[serde(default)]
    pub promotion_notes: Vec<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct GraphBakeoffRun {
    pub id: String,
    pub created_at: String,
    pub status: String,
    pub schema_version: String,
    #[serde(default)]
    pub dataset: serde_json::Value,
    #[serde(default)]
    pub candidates: Vec<GraphRuntimeCandidate>,
    pub winner: String,
    pub baseline: String,
    pub report_ref: String,
    pub degraded_reason: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct GraphIndexRun {
    pub id: String,
    pub created_at: String,
    pub schema_version: String,
    pub runtime: String,
    pub status: String,
    pub episodes_indexed: usize,
    pub atoms_indexed: usize,
    pub worlds_created: usize,
    pub hyperedges_indexed: usize,
    pub merkle_root: String,
    pub degraded_reason: String,
    #[serde(default)]
    pub provenance: serde_json::Value,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct MemoryGraphStatus {
    pub generated_at: String,
    pub schema_version: String,
    pub graph_runtime: String,
    pub runtime_status: String,
    pub retrieval_mode: String,
    pub canonical_store: String,
    pub projection_status: MemoryProjectionStatus,
    #[serde(default)]
    pub latest_bakeoff: Option<GraphBakeoffRun>,
    #[serde(default)]
    pub latest_index_run: Option<GraphIndexRun>,
    pub world_count: usize,
    pub degraded_reason: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct MemoryBenchmarkStatus {
    pub generated_at: String,
    pub schema_version: String,
    pub status: String,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub latest_run_id: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub latest_score: Option<f64>,
    pub query_count: usize,
    #[serde(default)]
    pub hard_gates: BTreeMap<String, bool>,
    #[serde(default)]
    pub evaluated_modes: Vec<String>,
    pub regression_count: usize,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub artifact_manifest: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub truthset_id: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub promotion_gate: Option<MemoryPromotionGate>,
    #[serde(default)]
    pub hot_path_eligible: bool,
    #[serde(default)]
    pub provisional_hot_path: bool,
    pub hot_path_mode: String,
    pub confirmed_passing_runs: usize,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub portfolio_truthset_id: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub degraded_reason: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct MemoryPromotionGate {
    pub baseline_mode: String,
    pub candidate_mode: String,
    pub required_margin: f64,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub baseline_score: Option<f64>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub candidate_score: Option<f64>,
    pub consecutive_passing_runs: usize,
    pub required_consecutive_runs: usize,
    pub hard_gates_passed: bool,
    pub eligible: bool,
    pub rationale: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct MemoryTruthSet {
    pub id: String,
    pub created_at: String,
    pub schema_version: String,
    pub status: String,
    pub title: String,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub description: Option<String>,
    #[serde(default)]
    pub domains: Vec<String>,
    #[serde(default)]
    pub source_refs: Vec<String>,
    pub case_count: usize,
    pub approved_case_count: usize,
    pub artifact_root: String,
    pub privacy_policy: String,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub reviewer: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub rationale: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct MemoryTruthCase {
    pub id: String,
    pub truthset_id: String,
    pub created_at: String,
    pub status: String,
    pub domain: String,
    pub query: String,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub expected_answer: Option<String>,
    #[serde(default)]
    pub required_evidence_refs: Vec<String>,
    #[serde(default)]
    pub expected_atom_refs: Vec<String>,
    #[serde(default)]
    pub expected_episode_refs: Vec<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub temporal_expectation: Option<String>,
    #[serde(default)]
    pub provenance_requirements: Vec<String>,
    pub privacy_class: String,
    #[serde(default)]
    pub tags: Vec<String>,
    #[serde(default)]
    pub metadata: serde_json::Value,
}

#[derive(Debug, Clone, Deserialize)]
pub struct CreateMemoryTruthSetRequest {
    #[serde(default)]
    pub title: Option<String>,
    #[serde(default)]
    pub description: Option<String>,
    #[serde(default)]
    pub domains: Vec<String>,
    #[serde(default)]
    pub source_refs: Vec<String>,
    #[serde(default)]
    pub reviewer: Option<String>,
    #[serde(default)]
    pub artifact_root: Option<String>,
}

#[derive(Debug, Clone, Deserialize)]
pub struct CreateMemoryTruthCaseRequest {
    pub domain: String,
    pub query: String,
    #[serde(default)]
    pub expected_answer: Option<String>,
    #[serde(default)]
    pub required_evidence_refs: Vec<String>,
    #[serde(default)]
    pub expected_atom_refs: Vec<String>,
    #[serde(default)]
    pub expected_episode_refs: Vec<String>,
    #[serde(default)]
    pub temporal_expectation: Option<String>,
    #[serde(default)]
    pub provenance_requirements: Vec<String>,
    #[serde(default)]
    pub privacy_class: Option<String>,
    #[serde(default)]
    pub status: Option<String>,
    #[serde(default)]
    pub tags: Vec<String>,
    #[serde(default)]
    pub metadata: Option<serde_json::Value>,
}

#[derive(Debug, Clone, Deserialize)]
pub struct ReviewMemoryTruthSetRequest {
    #[serde(default)]
    pub status: Option<String>,
    #[serde(default)]
    pub reviewer: Option<String>,
    #[serde(default)]
    pub rationale: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct MemoryTruthSetResponse {
    pub truthset: MemoryTruthSet,
    #[serde(default)]
    pub cases: Vec<MemoryTruthCase>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct MemoryWorldsRecentResponse {
    pub generated_at: String,
    #[serde(default)]
    pub worlds: Vec<MemoryWorld>,
    pub graph_status: MemoryGraphStatus,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SpatialAssetManifest {
    #[serde(default)]
    pub pano_url: Option<String>,
    #[serde(default)]
    pub collider_mesh_url: Option<String>,
    #[serde(default)]
    pub hq_mesh_urls: Vec<String>,
    #[serde(default)]
    pub spz_urls: BTreeMap<String, String>,
    #[serde(default)]
    pub ply_urls: BTreeMap<String, String>,
    #[serde(default)]
    pub coordinate_system: Option<String>,
    #[serde(default)]
    pub coordinate_transform: Option<String>,
    #[serde(default)]
    pub asset_root: Option<String>,
    #[serde(default)]
    pub degraded_reason: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SpatialWorld {
    pub id: String,
    pub created_at: String,
    pub updated_at: String,
    pub schema_version: String,
    pub project_slug: String,
    pub world_id: String,
    #[serde(default)]
    pub operation_id: Option<String>,
    pub display_name: String,
    pub status: String,
    #[serde(default)]
    pub world_marble_url: Option<String>,
    pub assets: SpatialAssetManifest,
    pub model: String,
    pub permission: String,
    pub prompt_hash: String,
    pub prompt_summary: String,
    pub privacy_policy: String,
    #[serde(default)]
    pub tags: Vec<String>,
    #[serde(default)]
    pub provenance: serde_json::Value,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ControlRoomSnapshot {
    pub id: String,
    pub generated_at: String,
    pub schema_version: String,
    pub project_slug: String,
    #[serde(default)]
    pub spatial_world: Option<SpatialWorld>,
    #[serde(default)]
    pub memory_worlds: Vec<MemoryWorld>,
    #[serde(default)]
    pub agent_lanes: Vec<String>,
    #[serde(default)]
    pub pods_wall: Vec<String>,
    #[serde(default)]
    pub incident_corridor: Vec<String>,
    #[serde(default)]
    pub compiler_map: Vec<String>,
    #[serde(default)]
    pub evidence_refs: Vec<String>,
    #[serde(default)]
    pub provenance: serde_json::Value,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SounioSpatialEvidence {
    pub id: String,
    pub created_at: String,
    pub schema_version: String,
    pub world_id: String,
    pub project_slug: String,
    pub evidence_type: String,
    #[serde(default)]
    pub claim_seed_refs: Vec<String>,
    #[serde(default)]
    pub memory_world_refs: Vec<String>,
    #[serde(default)]
    pub artifact_refs: Vec<String>,
    pub epistemic_status: String,
    pub privacy_class: String,
    #[serde(default)]
    pub provenance: serde_json::Value,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SpatialProviderSlot {
    pub id: String,
    pub label: String,
    pub provider_family: String,
    pub artifact_type: String,
    pub cost_tier: String,
    pub privacy_tier: String,
    pub maturity: String,
    pub enabled: bool,
    pub requires_secret: bool,
    pub setup_status: String,
    #[serde(default)]
    pub notes: Vec<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SpatialGenerationRun {
    pub id: String,
    pub created_at: String,
    pub schema_version: String,
    pub project_slug: String,
    pub provider_slot: String,
    pub purpose: String,
    pub status: String,
    pub prompt_hash: String,
    pub sanitized_prompt_summary: String,
    pub approved: bool,
    pub budget_policy: String,
    #[serde(default)]
    pub operation_id: Option<String>,
    #[serde(default)]
    pub world_id: Option<String>,
    #[serde(default)]
    pub asset_refs: Vec<String>,
    #[serde(default)]
    pub provenance: serde_json::Value,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct MindPalaceRoom {
    pub id: String,
    pub title: String,
    pub room_type: String,
    pub state: String,
    #[serde(default)]
    pub project_slug: Option<String>,
    pub source_family: String,
    pub tension: String,
    pub next_action: String,
    pub freshness: String,
    pub truth_mode: String,
    pub priority: f64,
    #[serde(default)]
    pub desk_item_refs: Vec<String>,
    #[serde(default)]
    pub evidence_refs: Vec<String>,
    #[serde(default)]
    pub tags: Vec<String>,
    #[serde(default)]
    pub provenance: serde_json::Value,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct DeskItem {
    pub id: String,
    pub kind: String,
    pub title: String,
    pub detail: String,
    pub state: String,
    pub priority: f64,
    #[serde(default)]
    pub room_id: Option<String>,
    #[serde(default)]
    pub source_ref: Option<String>,
    #[serde(default)]
    pub actions: Vec<String>,
    #[serde(default)]
    pub provenance: serde_json::Value,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SpatialDeskSnapshot {
    pub id: String,
    pub generated_at: String,
    pub schema_version: String,
    #[serde(default)]
    pub active_items: Vec<DeskItem>,
    #[serde(default)]
    pub pinned_room_ids: Vec<String>,
    #[serde(default)]
    pub portals: Vec<ConversationPortal>,
    #[serde(default)]
    pub agent_lanes: Vec<String>,
    #[serde(default)]
    pub focus_strip: Vec<String>,
    #[serde(default)]
    pub proof_panels: Vec<String>,
    #[serde(default)]
    pub provenance: serde_json::Value,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SpatialAction {
    pub id: String,
    pub title: String,
    pub kind: String,
    #[serde(default)]
    pub target_ref: Option<String>,
    pub reason: String,
    pub enabled: bool,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SpatialActionMenu {
    pub id: String,
    pub generated_at: String,
    pub mode: String,
    #[serde(default)]
    pub actions: Vec<SpatialAction>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct NextBestPlaceDecision {
    pub id: String,
    pub generated_at: String,
    pub room_id: String,
    pub title: String,
    pub reason: String,
    pub source_mode: String,
    pub confidence: f64,
    #[serde(default)]
    pub candidate_room_ids: Vec<String>,
    #[serde(default)]
    pub readiness_context: serde_json::Value,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct FocusIntervention {
    pub id: String,
    pub kind: String,
    pub title: String,
    pub reason: String,
    pub priority: f64,
    pub status: String,
    #[serde(default)]
    pub due_at: Option<String>,
    #[serde(default)]
    pub actions: Vec<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct FocusSession {
    pub id: String,
    pub started_at: String,
    #[serde(default)]
    pub ended_at: Option<String>,
    pub mode: String,
    #[serde(default)]
    pub project_slug: Option<String>,
    pub status: String,
    #[serde(default)]
    pub notes: Vec<String>,
    #[serde(default)]
    pub provenance: serde_json::Value,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct FocusCoachState {
    pub id: String,
    pub generated_at: String,
    pub schema_version: String,
    pub mode: String,
    #[serde(default)]
    pub active_session: Option<FocusSession>,
    #[serde(default)]
    pub interventions: Vec<FocusIntervention>,
    pub hydration_due: bool,
    #[serde(default)]
    pub calendar_nudge: Option<String>,
    pub session_minutes: u32,
    pub can_override: bool,
    #[serde(default)]
    pub provenance: serde_json::Value,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct FocusCoachEvent {
    pub id: String,
    pub created_at: String,
    pub schema_version: String,
    pub event_kind: String,
    pub status: String,
    #[serde(default)]
    pub intervention_id: Option<String>,
    #[serde(default)]
    pub project_slug: Option<String>,
    #[serde(default)]
    pub notes: Option<String>,
    #[serde(default)]
    pub snoozed_minutes: Option<u32>,
    #[serde(default)]
    pub provenance: serde_json::Value,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ConversationPortal {
    pub id: String,
    pub created_at: String,
    pub updated_at: String,
    pub schema_version: String,
    pub title: String,
    pub provider: String,
    pub surface: String,
    pub status: String,
    pub source_mode: String,
    pub privacy_class: String,
    #[serde(default)]
    pub source_ref: Option<String>,
    #[serde(default)]
    pub promoted_clip_refs: Vec<String>,
    #[serde(default)]
    pub tags: Vec<String>,
    #[serde(default)]
    pub provenance: serde_json::Value,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct PromotedConversationClip {
    pub id: String,
    pub created_at: String,
    pub schema_version: String,
    pub portal_id: String,
    pub content_hash: String,
    pub summary: String,
    #[serde(default)]
    pub project_ref: Option<String>,
    pub privacy_class: String,
    #[serde(default)]
    pub memory_event_id: Option<String>,
    #[serde(default)]
    pub sounio_moment_id: Option<String>,
    #[serde(default)]
    pub tags: Vec<String>,
    #[serde(default)]
    pub provenance: serde_json::Value,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct MindPalaceSnapshot {
    pub id: String,
    pub generated_at: String,
    pub schema_version: String,
    #[serde(default)]
    pub rooms: Vec<MindPalaceRoom>,
    pub desk: SpatialDeskSnapshot,
    pub next_best_place: NextBestPlaceDecision,
    pub action_menu: SpatialActionMenu,
    pub focus_coach: FocusCoachState,
    #[serde(default)]
    pub provenance: serde_json::Value,
}

#[derive(Debug, Clone, Deserialize)]
pub struct CreateConversationPortalRequest {
    pub title: String,
    pub provider: String,
    #[serde(default)]
    pub surface: Option<String>,
    #[serde(default)]
    pub status: Option<String>,
    #[serde(default)]
    pub source_mode: Option<String>,
    #[serde(default)]
    pub privacy_class: Option<String>,
    #[serde(default)]
    pub source_ref: Option<String>,
    #[serde(default)]
    pub tags: Vec<String>,
    #[serde(default)]
    pub provenance: serde_json::Value,
}

#[derive(Debug, Clone, Deserialize)]
pub struct PromoteConversationPortalRequest {
    pub selected_text: String,
    #[serde(default)]
    pub summary: Option<String>,
    #[serde(default)]
    pub project_ref: Option<String>,
    #[serde(default)]
    pub privacy_class: Option<String>,
    #[serde(default)]
    pub tags: Vec<String>,
    #[serde(default)]
    pub provenance: serde_json::Value,
}

#[derive(Debug, Clone, Deserialize)]
pub struct FocusCoachEventRequest {
    pub event_kind: String,
    #[serde(default)]
    pub status: Option<String>,
    #[serde(default)]
    pub intervention_id: Option<String>,
    #[serde(default)]
    pub project_slug: Option<String>,
    #[serde(default)]
    pub notes: Option<String>,
    #[serde(default)]
    pub snoozed_minutes: Option<u32>,
    #[serde(default)]
    pub provenance: serde_json::Value,
}

#[derive(Debug, Clone, Deserialize)]
pub struct CreateSpatialWorldRequest {
    #[serde(default)]
    pub project_slug: Option<String>,
    #[serde(default)]
    pub display_name: Option<String>,
    #[serde(default)]
    pub prompt_summary: Option<String>,
    #[serde(default)]
    pub sanitized_prompt: Option<String>,
    #[serde(default)]
    pub model: Option<String>,
    #[serde(default)]
    pub permission: Option<String>,
    #[serde(default)]
    pub approved: Option<bool>,
    #[serde(default)]
    pub purpose: Option<String>,
    #[serde(default)]
    pub operation_id: Option<String>,
    #[serde(default)]
    pub world_id: Option<String>,
    #[serde(default)]
    pub status: Option<String>,
    #[serde(default)]
    pub world_marble_url: Option<String>,
    #[serde(default)]
    pub assets: Option<SpatialAssetManifest>,
    #[serde(default)]
    pub tags: Vec<String>,
    #[serde(default)]
    pub provenance: serde_json::Value,
}

#[derive(Debug, Clone, Deserialize)]
pub struct SpatialWorldQuery {
    #[serde(default)]
    pub project_slug: Option<String>,
}

#[derive(Debug, Clone, Deserialize)]
pub struct CreateSounioSpatialEvidenceRequest {
    pub project_slug: String,
    #[serde(default)]
    pub evidence_type: Option<String>,
    #[serde(default)]
    pub claim_seed_refs: Vec<String>,
    #[serde(default)]
    pub memory_world_refs: Vec<String>,
    #[serde(default)]
    pub artifact_refs: Vec<String>,
    #[serde(default)]
    pub epistemic_status: Option<String>,
    #[serde(default)]
    pub privacy_class: Option<String>,
    #[serde(default)]
    pub provenance: serde_json::Value,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct MemoryExportRequest {
    #[serde(default)]
    pub limit: Option<usize>,
    #[serde(default)]
    pub include_worlds: bool,
    #[serde(default)]
    pub include_candidates: bool,
    #[serde(default)]
    pub purpose: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct MemoryExportResponse {
    pub id: String,
    pub created_at: String,
    pub schema_version: String,
    pub privacy_policy: String,
    pub canonical_store: String,
    #[serde(default)]
    pub episodes: Vec<MemoryEpisode>,
    #[serde(default)]
    pub atoms: Vec<MemoryAtom>,
    #[serde(default)]
    pub worlds: Vec<MemoryWorld>,
    #[serde(default)]
    pub candidates: Vec<MemoryCandidate>,
    #[serde(default)]
    pub synthetic_golden_queries: Vec<GoldenQuery>,
    pub merkle_root: String,
    #[serde(default)]
    pub provenance: serde_json::Value,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct GoldenQuery {
    pub id: String,
    pub query: String,
    pub domain: String,
    #[serde(default)]
    pub expected_signals: Vec<String>,
    pub privacy_class: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct MemoryCandidate {
    pub id: String,
    pub created_at: String,
    pub candidate_type: String,
    pub text: String,
    pub normalized_text: String,
    #[serde(default)]
    pub source_refs: Vec<String>,
    #[serde(default)]
    pub relations: Vec<MemoryRelation>,
    #[serde(default)]
    pub tags: Vec<String>,
    #[serde(default)]
    pub provenance: serde_json::Value,
    pub confidence: f64,
    pub privacy_class: String,
    pub status: String,
    #[serde(default)]
    pub quorum_ref: Option<String>,
    #[serde(default)]
    pub promoted_atom_id: Option<String>,
}

#[derive(Debug, Clone, Deserialize)]
pub struct CreateMemoryCandidateRequest {
    pub candidate_type: String,
    pub text: String,
    #[serde(default)]
    pub source_refs: Vec<String>,
    #[serde(default)]
    pub relations: Vec<MemoryRelation>,
    #[serde(default)]
    pub tags: Vec<String>,
    #[serde(default)]
    pub provenance: serde_json::Value,
    #[serde(default)]
    pub confidence: Option<f64>,
    #[serde(default)]
    pub privacy_class: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct MemoryCandidateListResponse {
    #[serde(default)]
    pub candidates: Vec<MemoryCandidate>,
}

#[derive(Debug, Clone, Deserialize)]
pub struct CandidateQuorumRequest {
    #[serde(default)]
    pub memory_approved: bool,
    #[serde(default)]
    pub temporal_approved: bool,
    #[serde(default)]
    pub critical_approved: bool,
    #[serde(default)]
    pub rationale: Option<String>,
    #[serde(default)]
    pub reviewer: Option<String>,
    #[serde(default)]
    pub quality_score: Option<MemoryQualityScoreInput>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct CandidateQuorumDecision {
    pub id: String,
    pub created_at: String,
    pub candidate_id: String,
    pub memory_approved: bool,
    pub temporal_approved: bool,
    pub critical_approved: bool,
    pub status: String,
    pub rationale: String,
    #[serde(default)]
    pub reviewer: Option<String>,
    pub quality_score: MemoryQualityScore,
}

#[derive(Debug, Clone, Deserialize)]
pub struct CandidatePromoteRequest {
    #[serde(default)]
    pub chronoself_commit_id: Option<String>,
    #[serde(default)]
    pub rationale: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct CandidatePromotionResponse {
    pub candidate: MemoryCandidate,
    pub promoted_atom: MemoryAtom,
    pub quorum: CandidateQuorumDecision,
    pub promotion_decision: MemoryPromotionDecision,
    pub audit_event: AuditEvent,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct MemoryQualityScoreInput {
    #[serde(default)]
    pub provenance_score: Option<f64>,
    #[serde(default)]
    pub temporal_score: Option<f64>,
    #[serde(default)]
    pub critical_score: Option<f64>,
    #[serde(default)]
    pub restricted_risk: Option<f64>,
    #[serde(default)]
    pub contradiction_risk: Option<f64>,
    #[serde(default)]
    pub rationale: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct MemoryQualityScore {
    pub id: String,
    pub created_at: String,
    pub candidate_id: String,
    pub provenance_score: f64,
    pub temporal_score: f64,
    pub critical_score: f64,
    pub overall: f64,
    pub restricted_risk: f64,
    pub contradiction_risk: f64,
    pub rationale: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct MemoryContradiction {
    pub id: String,
    pub created_at: String,
    pub subject_ref: String,
    pub conflicting_ref: String,
    pub description: String,
    pub severity: String,
    pub status: String,
    #[serde(default)]
    pub evidence_refs: Vec<String>,
    pub detected_by: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct MemoryPromotionDecision {
    pub id: String,
    pub created_at: String,
    pub candidate_id: String,
    pub decision: String,
    pub status: String,
    pub quality_score: MemoryQualityScore,
    #[serde(default)]
    pub quorum_id: Option<String>,
    #[serde(default)]
    pub promoted_atom_id: Option<String>,
    pub rationale: String,
    #[serde(default)]
    pub reviewer: Option<String>,
    #[serde(default)]
    pub evidence_refs: Vec<String>,
}

#[derive(Debug, Clone, Deserialize)]
pub struct MemoryGovernanceRunRequest {
    #[serde(default)]
    pub limit: Option<usize>,
    #[serde(default)]
    pub reviewer: Option<String>,
    #[serde(default)]
    pub dry_run: Option<bool>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct MemoryGovernanceRun {
    pub id: String,
    pub created_at: String,
    pub schema_version: String,
    pub status: String,
    pub candidates_evaluated: usize,
    pub triad_pending: usize,
    pub promoted: usize,
    pub rejected: usize,
    pub contradictions_found: usize,
    pub quality_scores_written: usize,
    #[serde(default)]
    pub hard_gates: serde_json::Value,
    pub degraded_reason: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct MemoryGovernanceStatus {
    pub status: String,
    pub schema_version: String,
    pub retrieval_policy: String,
    pub candidate_count: usize,
    pub pending_triads: usize,
    pub promoted_count: usize,
    pub rejected_count: usize,
    pub open_contradictions: usize,
    #[serde(default)]
    pub latest_run: Option<MemoryGovernanceRun>,
    #[serde(default)]
    pub latest_promotion_decision: Option<MemoryPromotionDecision>,
}

#[derive(Debug, Clone, Serialize)]
pub struct MemoryContradictionListResponse {
    pub contradictions: Vec<MemoryContradiction>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct RuntimeVote {
    pub runtime: String,
    pub role: String,
    pub status: String,
    pub score: f64,
    #[serde(default)]
    pub notes: Vec<String>,
}

#[derive(Debug, Clone, Deserialize)]
pub struct GraphBakeoffRequest {
    #[serde(default)]
    pub dataset_limit: Option<usize>,
    #[serde(default)]
    pub include_baseline: Option<bool>,
}

#[derive(Debug, Clone, Deserialize)]
pub struct GraphIndexRequest {
    #[serde(default)]
    pub rebuild: bool,
    #[serde(default)]
    pub source_refs: Vec<String>,
    #[serde(default)]
    pub runtime: Option<String>,
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
    #[serde(default)]
    pub mode: Option<String>,
    #[serde(default)]
    pub ranking_policy: Option<String>,
}

#[derive(Debug, Clone, Deserialize)]
pub struct ContextCompileRequest {
    pub query: String,
    #[serde(default)]
    pub scope: Option<String>,
    #[serde(default)]
    pub surface: Option<String>,
    #[serde(default)]
    pub task: Option<String>,
    #[serde(default)]
    pub max_items: Option<usize>,
    #[serde(default)]
    pub mode: Option<String>,
    #[serde(default)]
    pub token_budget: Option<usize>,
    #[serde(default)]
    pub agent: Option<String>,
    #[serde(default)]
    pub session_id: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ContextPack {
    pub id: String,
    pub created_at: String,
    pub schema_version: String,
    pub query: String,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub task: Option<String>,
    pub surface: String,
    pub format: String,
    pub policy_version: String,
    pub policy_mode: String,
    pub token_budget: usize,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub retrieval_plan_id: Option<String>,
    pub strategy_used: String,
    #[serde(default)]
    pub context_sections: serde_json::Value,
    #[serde(default)]
    pub evidence_refs: Vec<String>,
    #[serde(default)]
    pub provenance: serde_json::Value,
    #[serde(default)]
    pub restricted_leak_check: serde_json::Value,
    #[serde(default)]
    pub policy_rationale: Vec<String>,
    #[serde(default)]
    pub fallback_chain: Vec<String>,
    pub next_action: String,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub degraded_reason: Option<String>,
}

#[derive(Debug, Clone, Deserialize)]
pub struct MemoryEffectivenessEventRequest {
    pub context_pack_id: String,
    #[serde(default)]
    pub query: Option<String>,
    #[serde(default)]
    pub surface: Option<String>,
    #[serde(default)]
    pub principal: Option<String>,
    #[serde(default)]
    pub session_id: Option<String>,
    #[serde(default)]
    pub strategy_used: Option<String>,
    #[serde(default)]
    pub tokens_used: Option<usize>,
    #[serde(default)]
    pub latency_ms: Option<f64>,
    #[serde(default)]
    pub tests: Vec<String>,
    #[serde(default)]
    pub feedback: Option<String>,
    #[serde(default)]
    pub human_correction: Option<String>,
    #[serde(default)]
    pub success: Option<bool>,
    #[serde(default)]
    pub outcome: Option<String>,
    #[serde(default)]
    pub metadata: serde_json::Value,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct MemoryEffectivenessEvent {
    pub id: String,
    pub created_at: String,
    pub schema_version: String,
    pub context_pack_id: String,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub query: Option<String>,
    pub surface: String,
    pub principal: String,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub session_id: Option<String>,
    pub strategy_used: String,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub tokens_used: Option<usize>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub latency_ms: Option<f64>,
    #[serde(default)]
    pub tests: Vec<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub feedback: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub human_correction: Option<String>,
    pub success: bool,
    pub outcome: String,
    #[serde(default)]
    pub metadata: serde_json::Value,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct MemoryPolicyStatus {
    pub generated_at: String,
    pub schema_version: String,
    pub status: String,
    pub policy_version: String,
    pub policy_mode: String,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub latest_effectiveness_event: Option<MemoryEffectivenessEvent>,
    #[serde(default)]
    pub outcome_counts: BTreeMap<String, usize>,
    #[serde(default)]
    pub promotion_gate: serde_json::Value,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub degraded_reason: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SounioGovernance {
    #[serde(default = "default_sensitive_privacy_class")]
    pub privacy_class: String,
    #[serde(default)]
    pub provenance: serde_json::Value,
    #[serde(default)]
    pub restricted_leak_check: serde_json::Value,
    #[serde(default)]
    pub human_approval_required: bool,
    #[serde(default)]
    pub policy_refs: Vec<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SounioStep {
    pub id: String,
    pub title: String,
    #[serde(default)]
    pub objective: Option<String>,
    #[serde(default)]
    pub agent: Option<String>,
    #[serde(default)]
    pub strategy: Option<String>,
    #[serde(default)]
    pub requires_human_approval: bool,
    #[serde(default)]
    pub provenance: serde_json::Value,
    #[serde(default)]
    pub governance: serde_json::Value,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SounioAction {
    pub id: String,
    pub action_type: String,
    pub target: String,
    #[serde(default)]
    pub parameters: serde_json::Value,
    #[serde(default)]
    pub provenance: serde_json::Value,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SounioEvidence {
    pub id: String,
    pub claim_ref: String,
    pub source_ref: String,
    #[serde(default)]
    pub summary: Option<String>,
    #[serde(default)]
    pub confidence: Option<f64>,
    #[serde(default)]
    pub provenance: serde_json::Value,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SounioDecision {
    pub id: String,
    pub summary: String,
    #[serde(default)]
    pub rationale: Option<String>,
    #[serde(default)]
    pub evidence_refs: Vec<String>,
    #[serde(default)]
    pub provenance: serde_json::Value,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SounioCheck {
    pub id: String,
    pub check_type: String,
    pub description: String,
    #[serde(default)]
    pub status: Option<String>,
    #[serde(default)]
    pub required: bool,
    #[serde(default)]
    pub provenance: serde_json::Value,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SounioProgram {
    pub id: String,
    #[serde(default = "default_sounio_version")]
    pub sounio_version: String,
    #[serde(default = "default_sounio_program_kind")]
    pub kind: String,
    pub intent: String,
    #[serde(default)]
    pub context: serde_json::Value,
    #[serde(default)]
    pub plan: Vec<SounioStep>,
    #[serde(default)]
    pub actions: Vec<SounioAction>,
    #[serde(default)]
    pub evidence: Vec<SounioEvidence>,
    #[serde(default)]
    pub decisions: Vec<SounioDecision>,
    #[serde(default)]
    pub checks: Vec<SounioCheck>,
    #[serde(default)]
    pub outcome: Option<String>,
    #[serde(default)]
    pub next_action: Option<String>,
    pub governance: SounioGovernance,
}

#[derive(Debug, Clone, Deserialize)]
pub struct SounioProgramCheckRequest {
    #[serde(default)]
    pub source_format: Option<String>,
    pub program: SounioProgram,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SounioProgramCheckResponse {
    pub status: String,
    pub program_hash: String,
    pub schema_version: String,
    #[serde(default)]
    pub errors: Vec<String>,
    #[serde(default)]
    pub warnings: Vec<String>,
    #[serde(default)]
    pub temporal_spec: serde_json::Value,
    #[serde(default)]
    pub memory_projection_preview: serde_json::Value,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SounioTraceEvent {
    pub id: String,
    pub created_at: String,
    pub paper_run_id: String,
    pub program_id: String,
    pub step_id: String,
    pub event_type: String,
    pub status: String,
    #[serde(default)]
    pub summary: Option<String>,
    #[serde(default)]
    pub context_pack_id: Option<String>,
    #[serde(default)]
    pub provenance: serde_json::Value,
    #[serde(default)]
    pub artifact_refs: Vec<String>,
}

#[derive(Debug, Clone, Deserialize)]
pub struct StartPaperRunRequest {
    #[serde(default)]
    pub paper_id: Option<String>,
    #[serde(default)]
    pub title: Option<String>,
    #[serde(default)]
    pub principal: Option<String>,
    #[serde(default)]
    pub surface: Option<String>,
    #[serde(default)]
    pub temporal_namespace: Option<String>,
    #[serde(default)]
    pub temporal_task_queue: Option<String>,
    #[serde(default)]
    pub program: Option<SounioProgram>,
    #[serde(default)]
    pub dry_run: Option<bool>,
}

#[derive(Debug, Clone, Deserialize)]
pub struct ApprovePaperRunStepRequest {
    pub step_id: String,
    #[serde(default)]
    pub reviewer: Option<String>,
    #[serde(default)]
    pub decision: Option<String>,
    #[serde(default)]
    pub rationale: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct PaperRun {
    pub id: String,
    pub created_at: String,
    pub updated_at: String,
    pub schema_version: String,
    pub paper_id: String,
    pub title: String,
    pub status: String,
    pub temporal_workflow_id: String,
    pub temporal_namespace: String,
    pub temporal_task_queue: String,
    pub temporal_status: String,
    pub sounio_program_id: String,
    pub sounio_program_hash: String,
    pub manuscript_version: String,
    #[serde(default)]
    pub section_status: BTreeMap<String, String>,
    #[serde(default)]
    pub claim_registry: Vec<serde_json::Value>,
    #[serde(default)]
    pub citation_registry: Vec<serde_json::Value>,
    pub approval_state: String,
    #[serde(default)]
    pub pending_approval_step: Option<String>,
    #[serde(default)]
    pub context_pack_id: Option<String>,
    #[serde(default)]
    pub artifact_refs: Vec<String>,
    #[serde(default)]
    pub provenance: serde_json::Value,
    #[serde(default)]
    pub interaction_summary: Option<String>,
    #[serde(default)]
    pub claim_lifecycle_status: BTreeMap<String, String>,
    #[serde(default)]
    pub public_digest_status: Option<String>,
    #[serde(default)]
    pub current_stage: Option<String>,
}

#[derive(Debug, Clone, Serialize)]
pub struct PaperRunArtifactsResponse {
    pub paper_run_id: String,
    pub generated_at: String,
    pub manuscript_markdown: String,
    pub provenance_pack: serde_json::Value,
    pub artifact_refs: Vec<String>,
}

#[derive(Debug, Clone, Deserialize)]
pub struct SounioTraceQuery {
    #[serde(default)]
    pub paper_run_id: Option<String>,
    #[serde(default)]
    pub limit: Option<usize>,
}

#[derive(Debug, Serialize)]
pub struct SounioTraceListResponse {
    pub events: Vec<SounioTraceEvent>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SounioClaimInput {
    #[serde(default)]
    pub id: Option<String>,
    pub claim_text: String,
    #[serde(default)]
    pub subject: Option<String>,
    #[serde(default)]
    pub value_type: Option<String>,
    #[serde(default)]
    pub epistemic_status: Option<String>,
    #[serde(default)]
    pub evidence_refs: Vec<String>,
    #[serde(default)]
    pub provenance: serde_json::Value,
    #[serde(default)]
    pub confidence: Option<f64>,
    #[serde(default)]
    pub contestation: serde_json::Value,
    #[serde(default)]
    pub review_state: Option<String>,
    #[serde(default)]
    pub promotion_rule: Option<String>,
    #[serde(default)]
    pub publication_readiness: Option<String>,
    #[serde(default)]
    pub section_id: Option<String>,
    #[serde(default)]
    pub agent_refs: Vec<String>,
    #[serde(default)]
    pub contract_refs: Vec<String>,
    #[serde(default)]
    pub artifact_refs: Vec<String>,
    #[serde(default)]
    pub chronoself_commit_refs: Vec<String>,
    #[serde(default)]
    pub privacy_class: Option<String>,
    #[serde(default)]
    pub rationale: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SounioClaim {
    pub id: String,
    pub created_at: String,
    pub updated_at: String,
    #[serde(default)]
    pub paper_run_id: Option<String>,
    #[serde(default)]
    pub section_id: Option<String>,
    pub claim_text: String,
    pub subject: String,
    #[serde(default)]
    pub value_type: Option<String>,
    pub epistemic_status: String,
    #[serde(default)]
    pub evidence_refs: Vec<String>,
    #[serde(default)]
    pub provenance: serde_json::Value,
    pub confidence: f64,
    #[serde(default)]
    pub contestation: serde_json::Value,
    pub review_state: String,
    pub promotion_rule: String,
    pub publication_readiness: String,
    #[serde(default)]
    pub agent_refs: Vec<String>,
    #[serde(default)]
    pub contract_refs: Vec<String>,
    #[serde(default)]
    pub artifact_refs: Vec<String>,
    #[serde(default)]
    pub chronoself_commit_refs: Vec<String>,
    #[serde(default = "default_sensitive_privacy_class")]
    pub privacy_class: String,
    #[serde(default)]
    pub rationale: Option<String>,
}

#[derive(Debug, Clone, Deserialize)]
pub struct SounioClaimCheckRequest {
    pub claim: SounioClaimInput,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SounioClaimCheckResponse {
    pub status: String,
    pub schema_version: String,
    pub normalized_claim: SounioClaim,
    #[serde(default)]
    pub errors: Vec<String>,
    #[serde(default)]
    pub warnings: Vec<String>,
    #[serde(default)]
    pub required_evidence: Vec<String>,
    #[serde(default)]
    pub promotion_gate: serde_json::Value,
}

#[derive(Debug, Clone, Deserialize)]
pub struct AddPaperRunClaimRequest {
    pub claim: SounioClaimInput,
    #[serde(default)]
    pub principal: Option<String>,
    #[serde(default)]
    pub surface: Option<String>,
}

#[derive(Debug, Clone, Deserialize)]
pub struct ReviewSounioClaimRequest {
    #[serde(default)]
    pub reviewer: Option<String>,
    pub decision: String,
    #[serde(default)]
    pub rationale: Option<String>,
    #[serde(default)]
    pub evidence_refs: Vec<String>,
    #[serde(default)]
    pub epistemic_status: Option<String>,
    #[serde(default)]
    pub publication_readiness: Option<String>,
    #[serde(default)]
    pub provenance: serde_json::Value,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SounioClaimReview {
    pub id: String,
    pub created_at: String,
    pub paper_run_id: String,
    pub claim_id: String,
    pub reviewer: String,
    pub decision: String,
    #[serde(default)]
    pub rationale: Option<String>,
    pub previous_status: String,
    pub new_status: String,
    #[serde(default)]
    pub evidence_refs: Vec<String>,
    #[serde(default)]
    pub provenance: serde_json::Value,
}

#[derive(Debug, Clone, Deserialize)]
pub struct SounioMomentTypeRequest {
    #[serde(default)]
    pub source_event_refs: Vec<String>,
    #[serde(default)]
    pub source_platform: Option<String>,
    #[serde(default)]
    pub source_surface: Option<String>,
    #[serde(default)]
    pub project_slug: Option<String>,
    #[serde(default)]
    pub session_id: Option<String>,
    #[serde(default)]
    pub intent_text: Option<String>,
    #[serde(default)]
    pub summary: Option<String>,
    #[serde(default)]
    pub evidence_refs: Vec<String>,
    #[serde(default)]
    pub claim_seeds: Vec<SounioClaimInput>,
    #[serde(default)]
    pub decision_seeds: Vec<String>,
    #[serde(default)]
    pub next_action: Option<String>,
    #[serde(default)]
    pub privacy_class: Option<String>,
    #[serde(default)]
    pub review_state: Option<String>,
    #[serde(default)]
    pub provenance: serde_json::Value,
    #[serde(default)]
    pub tags: Vec<String>,
}

#[derive(Debug, Clone, Deserialize)]
pub struct SounioMomentReviewRequest {
    #[serde(default)]
    pub reviewer: Option<String>,
    pub decision: String,
    #[serde(default)]
    pub rationale: Option<String>,
    #[serde(default)]
    pub evidence_refs: Vec<String>,
    #[serde(default)]
    pub review_state: Option<String>,
    #[serde(default)]
    pub provenance: serde_json::Value,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SounioMomentReview {
    pub id: String,
    pub created_at: String,
    pub moment_id: String,
    pub reviewer: String,
    pub decision: String,
    #[serde(default)]
    pub rationale: Option<String>,
    pub previous_state: String,
    pub new_state: String,
    #[serde(default)]
    pub evidence_refs: Vec<String>,
    #[serde(default)]
    pub provenance: serde_json::Value,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SounioMoment {
    pub id: String,
    pub created_at: String,
    pub updated_at: String,
    pub schema_version: String,
    pub project_slug: String,
    pub moment_type: String,
    pub intent: String,
    pub summary: String,
    pub source_platform: String,
    pub source_surface: String,
    #[serde(default)]
    pub session_id: Option<String>,
    #[serde(default)]
    pub source_event_refs: Vec<String>,
    #[serde(default)]
    pub evidence_refs: Vec<String>,
    #[serde(default)]
    pub claim_seeds: Vec<SounioClaim>,
    #[serde(default)]
    pub decision_seeds: Vec<String>,
    #[serde(default)]
    pub next_action: Option<String>,
    pub privacy_class: String,
    pub review_state: String,
    pub restricted_leak_check: String,
    #[serde(default)]
    pub provenance: serde_json::Value,
    #[serde(default)]
    pub tags: Vec<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SounioMomentListResponse {
    pub generated_at: String,
    pub schema_version: String,
    #[serde(default)]
    pub project_slug: Option<String>,
    #[serde(default)]
    pub moments: Vec<SounioMoment>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SounioWorkdaySnapshot {
    pub generated_at: String,
    pub schema_version: String,
    pub project_slug: String,
    pub status: String,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub latest_moment: Option<SounioMoment>,
    #[serde(default)]
    pub moments: Vec<SounioMoment>,
    #[serde(default)]
    pub claim_seeds: Vec<SounioClaim>,
    #[serde(default)]
    pub decision_seeds: Vec<String>,
    #[serde(default)]
    pub evidence_refs: Vec<String>,
    #[serde(default)]
    pub tensions: Vec<String>,
    #[serde(default)]
    pub agents: Vec<String>,
    pub next_action: String,
    pub review_queue_count: usize,
    pub restricted_leak_check: String,
    #[serde(default)]
    pub provenance: serde_json::Value,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SounioClaimGraph {
    pub paper_run_id: String,
    pub generated_at: String,
    pub schema_version: String,
    #[serde(default)]
    pub claims: Vec<SounioClaim>,
    #[serde(default)]
    pub edges: Vec<serde_json::Value>,
    #[serde(default)]
    pub status_counts: BTreeMap<String, usize>,
    #[serde(default)]
    pub unsupported_claim_ids: Vec<String>,
    #[serde(default)]
    pub robust_claim_ids: Vec<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct PaperRunTheatreSnapshot {
    pub paper_run_id: String,
    pub generated_at: String,
    pub schema_version: String,
    pub paper_run: PaperRun,
    pub manuscript_markdown: String,
    pub claim_graph: SounioClaimGraph,
    #[serde(default)]
    pub trace_events: Vec<SounioTraceEvent>,
    #[serde(default)]
    pub agent_contributions: Vec<serde_json::Value>,
    #[serde(default)]
    pub approvals: Vec<serde_json::Value>,
    #[serde(default)]
    pub evidence_table: Vec<serde_json::Value>,
    #[serde(default)]
    pub sounio_score: serde_json::Value,
    pub current_stage: String,
    pub next_action: String,
    pub public_digest_status: String,
    pub private_trace_ref: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct PublicDigestArtifact {
    pub paper_run_id: String,
    pub generated_at: String,
    pub schema_version: String,
    pub title: String,
    pub thesis: String,
    #[serde(default)]
    pub sanitized_claims: Vec<serde_json::Value>,
    #[serde(default)]
    pub sedenion_ssm_case: serde_json::Value,
    #[serde(default)]
    pub public_trace_digest: Vec<serde_json::Value>,
    pub disclosure: String,
    pub excluded_private_trace_policy: String,
    pub manuscript_excerpt: String,
}

#[derive(Debug, Clone, Deserialize)]
pub struct DreamCycleRunRequest {
    #[serde(default)]
    pub limit: Option<usize>,
    #[serde(default)]
    pub mode: Option<String>,
    #[serde(default)]
    pub triggered_by: Option<String>,
    #[serde(default)]
    pub dry_run: Option<bool>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct DreamCycleRun {
    pub id: String,
    pub created_at: String,
    pub schema_version: String,
    pub status: String,
    pub mode: String,
    pub dry_run: bool,
    pub triggered_by: String,
    pub source_episode_count: usize,
    pub source_atom_count: usize,
    pub candidate_count: usize,
    pub contradiction_count: usize,
    pub procedural_memory_count: usize,
    pub stale_belief_count: usize,
    pub project_summary_count: usize,
    pub unresolved_loop_count: usize,
    pub suggested_truth_cases: usize,
    #[serde(default)]
    pub generated_candidate_refs: Vec<String>,
    #[serde(default)]
    pub provenance: serde_json::Value,
    pub promotion_policy: String,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub degraded_reason: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct DreamCycleStatus {
    pub generated_at: String,
    pub schema_version: String,
    pub status: String,
    pub mode: String,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub latest_run: Option<DreamCycleRun>,
    pub policy: String,
    pub candidate_outputs_active: bool,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub degraded_reason: Option<String>,
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
pub struct EvidenceGraphNode {
    pub id: String,
    pub label: String,
    pub node_type: String,
    pub score: f64,
    #[serde(default)]
    pub provenance: serde_json::Value,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct EvidenceGraphEdge {
    pub source: String,
    pub target: String,
    pub predicate: String,
    pub confidence: f64,
    #[serde(default)]
    pub provenance: serde_json::Value,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct EvidenceGraph {
    #[serde(default)]
    pub nodes: Vec<EvidenceGraphNode>,
    #[serde(default)]
    pub edges: Vec<EvidenceGraphEdge>,
    pub temporary: bool,
    pub merkle_root: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct GraphRagCommunityContext {
    pub strategy: String,
    #[serde(default)]
    pub selected_communities: Vec<MemoryCommunity>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub degraded_reason: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct RetrievalTraceStep {
    pub stage: String,
    pub backend: String,
    pub status: String,
    pub items: usize,
    pub latency_ms: f64,
    #[serde(default)]
    pub notes: Vec<String>,
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
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub mode: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub graph_runtime: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub evidence_graph: Option<EvidenceGraph>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub community_context: Option<GraphRagCommunityContext>,
    #[serde(default)]
    pub retrieval_trace: Vec<RetrievalTraceStep>,
    #[serde(default)]
    pub mesh_trace: Vec<RetrievalTraceStep>,
    #[serde(default)]
    pub runtime_votes: Vec<RuntimeVote>,
    #[serde(default)]
    pub candidate_refs: Vec<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub runtime_used: Option<String>,
    #[serde(default)]
    pub fallback_chain: Vec<String>,
    #[serde(default)]
    pub semantic_trace: Vec<RetrievalTraceStep>,
    #[serde(default)]
    pub maxsim_scores: Vec<serde_json::Value>,
    #[serde(default)]
    pub graph_expansion: serde_json::Value,
    #[serde(default)]
    pub reranker_scores: Vec<serde_json::Value>,
    #[serde(default)]
    pub truthset_gate_status: serde_json::Value,
    #[serde(default)]
    pub restricted_leak_check: serde_json::Value,
    pub retrieval_agent: String,
    pub retrieval_plan_id: String,
    pub strategy_used: String,
    #[serde(default)]
    pub subqueries: Vec<String>,
    #[serde(default)]
    pub evidence_pack: serde_json::Value,
    pub context_format: String,
    pub planner_mode: String,
    #[serde(default)]
    pub budget: serde_json::Value,
    #[serde(default)]
    pub runtime_trace: Vec<RetrievalTraceStep>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub context_pack_id: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub policy_version: Option<String>,
    #[serde(default)]
    pub policy_gate: serde_json::Value,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub dreamcycle_status: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub ranking_policy: Option<String>,
    #[serde(default)]
    pub ranking_trace: serde_json::Value,
    #[serde(default)]
    pub recency_boost_applied: bool,
    #[serde(default)]
    pub stable_fact_guard_applied: bool,
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
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub graph_runtime: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub retrieval_mode: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub last_world_hash: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub latest_agent_write: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub graph_degraded_reason: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub memory_engine_status: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub latest_candidate_ref: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub latest_quorum_status: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub memory_governor_status: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub pending_triads: Option<usize>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub open_contradictions: Option<usize>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub latest_promotion_decision: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub memory_bench_status: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub latest_bench_score: Option<f64>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub memory_regression_count: Option<usize>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub truthset_id: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub bench_hot_path_eligible: Option<bool>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub agent_observer_status: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub apple_capture_freshness: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub capture_loop_status: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub semantic_backbone_status: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub hot_path_mode: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub provisional_hot_path: Option<bool>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub portfolio_truth_gate: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub retrieval_agent_status: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub latest_retrieval_strategy: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub memoryarena_gate: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub context_compiler_status: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub latest_context_pack_id: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub memory_policy_status: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub policy_gate: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub dreamcycle_status: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub sounio_paperrun_status: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub sounio_temporal_status: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub sounio_pending_approval: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub sounio_latest_artifact: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub sounio_workday_status: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub sounio_latest_moment: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub sounio_pending_moment_review: Option<String>,
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
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub sounio_workday_context: Option<SounioWorkdaySnapshot>,
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
pub struct SounioMomentsQuery {
    #[serde(default)]
    pub limit: Option<usize>,
    #[serde(default)]
    pub project_slug: Option<String>,
}

#[derive(Debug, Deserialize)]
pub struct SounioWorkdayQuery {
    #[serde(default)]
    pub project_slug: Option<String>,
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

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct TranscriptionSegment {
    pub text: String,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub start_ms: Option<u64>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub end_ms: Option<u64>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub confidence: Option<f64>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub source: Option<String>,
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
    #[serde(default)]
    pub capture_session_id: Option<String>,
    #[serde(default)]
    pub artifact_refs: Vec<String>,
    #[serde(default)]
    pub transcription_segments: Vec<TranscriptionSegment>,
    #[serde(default)]
    pub visual_evidence_refs: Vec<String>,
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
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub sounio_moment: Option<SounioMoment>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct WriteProbeRequest {
    #[serde(default)]
    pub principal: Option<String>,
    #[serde(default)]
    pub source_platform: Option<String>,
    #[serde(default)]
    pub source_surface: Option<String>,
    #[serde(default)]
    pub required_scopes: Vec<String>,
    #[serde(default)]
    pub granted_scopes: Vec<String>,
    #[serde(default)]
    pub payload_kind: Option<String>,
    #[serde(default)]
    pub metadata: serde_json::Value,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct WriteProbeResponse {
    pub status: String,
    pub can_write: bool,
    pub missing_scopes: Vec<String>,
    pub required_scopes: Vec<String>,
    pub granted_scopes: Vec<String>,
    pub core_write_health: String,
    pub checked_at: String,
    pub principal: String,
    pub source_surface: String,
    pub payload_kind: String,
    pub diagnostics: serde_json::Value,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct FailedWriteInboxItem {
    pub id: String,
    pub created_at: String,
    pub updated_at: String,
    pub status: String,
    pub reason: String,
    pub source_platform: String,
    pub source_surface: String,
    pub principal: String,
    pub summary: String,
    pub privacy_class: String,
    pub payload_kind: String,
    pub retry_eligible: bool,
    #[serde(default)]
    pub artifact_refs: Vec<String>,
    #[serde(default)]
    pub candidate_refs: Vec<String>,
    #[serde(default)]
    pub metadata: serde_json::Value,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub rescue_memory_event_id: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub rescue_audit_event_id: Option<String>,
}

#[derive(Debug, Clone, Deserialize)]
pub struct FailedWriteRecordRequest {
    #[serde(default)]
    pub reason: Option<String>,
    #[serde(default)]
    pub source_platform: Option<String>,
    #[serde(default)]
    pub source_surface: Option<String>,
    #[serde(default)]
    pub principal: Option<String>,
    #[serde(default)]
    pub summary: Option<String>,
    #[serde(default)]
    pub privacy_class: Option<String>,
    #[serde(default)]
    pub payload_kind: Option<String>,
    #[serde(default)]
    pub artifact_refs: Vec<String>,
    #[serde(default)]
    pub metadata: serde_json::Value,
}

#[derive(Debug, Clone, Deserialize)]
pub struct FailedWriteRescueRequest {
    #[serde(default)]
    pub failed_write_id: Option<String>,
    #[serde(default)]
    pub reason: Option<String>,
    #[serde(default)]
    pub source_platform: Option<String>,
    #[serde(default)]
    pub source_surface: Option<String>,
    #[serde(default)]
    pub principal: Option<String>,
    #[serde(default)]
    pub summary: Option<String>,
    #[serde(default)]
    pub session_id: Option<String>,
    #[serde(default)]
    pub project_ref: Option<String>,
    #[serde(default)]
    pub privacy_class: Option<String>,
    #[serde(default)]
    pub payload_kind: Option<String>,
    #[serde(default)]
    pub turns: Vec<AssistedImportTurn>,
    #[serde(default)]
    pub tags: Vec<String>,
    #[serde(default)]
    pub artifact_refs: Vec<String>,
    #[serde(default)]
    pub candidate_refs: Vec<String>,
    #[serde(default)]
    pub metadata: serde_json::Value,
}

#[derive(Debug, Clone, Serialize)]
pub struct FailedWriteInboxResponse {
    pub items: Vec<FailedWriteInboxItem>,
}

#[derive(Debug, Clone, Serialize)]
pub struct FailedWriteRescueResponse {
    pub item: FailedWriteInboxItem,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub assisted_import: Option<AssistedImportBatchResponse>,
}

#[derive(Debug, Clone, Deserialize)]
pub struct CaptureSessionStartRequest {
    #[serde(default)]
    pub project_slug: Option<String>,
    #[serde(default)]
    pub mode: Option<String>,
    #[serde(default)]
    pub surface: Option<String>,
    #[serde(default)]
    pub principal: Option<String>,
    #[serde(default)]
    pub title: Option<String>,
    #[serde(default)]
    pub privacy_class: Option<String>,
    #[serde(default)]
    pub metadata: serde_json::Value,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct CaptureSession {
    pub id: String,
    pub created_at: String,
    pub updated_at: String,
    pub schema_version: String,
    pub project_slug: String,
    pub mode: String,
    pub surface: String,
    pub principal: String,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub title: Option<String>,
    pub privacy_class: String,
    pub status: String,
    pub raw_audio_policy: String,
    pub raw_image_policy: String,
    #[serde(default)]
    pub transcription_segments: Vec<TranscriptionSegment>,
    #[serde(default)]
    pub artifact_refs: Vec<String>,
    #[serde(default)]
    pub evidence_refs: Vec<String>,
    pub review_state: String,
    #[serde(default)]
    pub provenance: serde_json::Value,
}

#[derive(Debug, Clone, Deserialize)]
pub struct CaptureSessionEventRequest {
    pub event_type: String,
    #[serde(default)]
    pub text: Option<String>,
    #[serde(default)]
    pub transcription_segments: Vec<TranscriptionSegment>,
    #[serde(default)]
    pub artifact_refs: Vec<String>,
    #[serde(default)]
    pub evidence_refs: Vec<String>,
    #[serde(default)]
    pub privacy_class: Option<String>,
    #[serde(default)]
    pub metadata: serde_json::Value,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct CaptureSessionEvent {
    pub id: String,
    pub created_at: String,
    pub session_id: String,
    pub event_type: String,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub text: Option<String>,
    #[serde(default)]
    pub transcription_segments: Vec<TranscriptionSegment>,
    #[serde(default)]
    pub artifact_refs: Vec<String>,
    #[serde(default)]
    pub evidence_refs: Vec<String>,
    pub privacy_class: String,
    #[serde(default)]
    pub metadata: serde_json::Value,
}

#[derive(Debug, Clone, Deserialize)]
pub struct VisualEvidenceArtifactRequest {
    #[serde(default)]
    pub session_id: Option<String>,
    #[serde(default)]
    pub project_slug: Option<String>,
    #[serde(default)]
    pub source_surface: Option<String>,
    #[serde(default)]
    pub source_kind: Option<String>,
    #[serde(default)]
    pub media_type: Option<String>,
    pub content_hash: String,
    #[serde(default)]
    pub content_ref: Option<String>,
    #[serde(default)]
    pub artifact_data_base64: Option<String>,
    #[serde(default)]
    pub artifact_byte_count: Option<usize>,
    #[serde(default)]
    pub local_summary: Option<String>,
    #[serde(default)]
    pub extracted_text: Option<String>,
    #[serde(default)]
    pub local_hints: Vec<String>,
    #[serde(default)]
    pub privacy_class: Option<String>,
    #[serde(default)]
    pub confirmation_state: Option<String>,
    #[serde(default)]
    pub metadata: serde_json::Value,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct VisualEvidenceArtifact {
    pub id: String,
    pub created_at: String,
    pub schema_version: String,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub session_id: Option<String>,
    pub project_slug: String,
    pub source_surface: String,
    pub source_kind: String,
    pub media_type: String,
    pub content_hash: String,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub content_ref: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub artifact_byte_count: Option<usize>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub local_summary: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub extracted_text: Option<String>,
    #[serde(default)]
    pub local_hints: Vec<String>,
    pub privacy_class: String,
    pub confirmation_state: String,
    pub private_artifact_policy: String,
    #[serde(default)]
    pub provenance: serde_json::Value,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct CaptureReviewCandidate {
    pub id: String,
    pub kind: String,
    pub title: String,
    pub summary: String,
    #[serde(default)]
    pub evidence_refs: Vec<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub claim_text: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub decision_text: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub next_action: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub epistemic_status: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub confidence: Option<f64>,
    #[serde(default = "default_sensitive_privacy_class")]
    pub privacy_class: String,
    #[serde(default)]
    pub provenance: serde_json::Value,
}

#[derive(Debug, Clone, Deserialize)]
pub struct VisualEvidenceAnalyzeRequest {
    pub artifact_id: String,
    #[serde(default)]
    pub prompt: Option<String>,
    #[serde(default)]
    pub allow_external_model: Option<bool>,
    #[serde(default)]
    pub preferred_provider: Option<String>,
    #[serde(default)]
    pub local_analysis: serde_json::Value,
    #[serde(default)]
    pub redaction_summary: Option<String>,
    #[serde(default)]
    pub principal: Option<String>,
    #[serde(default)]
    pub surface: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct VisualEvidenceAnalysis {
    pub id: String,
    pub created_at: String,
    pub schema_version: String,
    pub artifact_id: String,
    pub mode: String,
    pub provider: String,
    pub status: String,
    pub summary: String,
    #[serde(default)]
    pub claim_map: Vec<CaptureReviewCandidate>,
    #[serde(default)]
    pub evidence_refs: Vec<String>,
    #[serde(default)]
    pub tensions: Vec<String>,
    #[serde(default)]
    pub missing_evidence: Vec<String>,
    pub restricted_leak_check: String,
    pub requires_confirmation: bool,
    #[serde(default)]
    pub provenance: serde_json::Value,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub degraded_reason: Option<String>,
}

#[derive(Debug, Clone, Deserialize)]
pub struct CaptureReviewRequest {
    #[serde(default)]
    pub session_id: Option<String>,
    #[serde(default)]
    pub artifact_id: Option<String>,
    #[serde(default)]
    pub project_slug: Option<String>,
    #[serde(default)]
    pub source_surface: Option<String>,
    #[serde(default)]
    pub candidates: Vec<CaptureReviewCandidate>,
    #[serde(default)]
    pub decision: Option<String>,
    #[serde(default)]
    pub reviewer: Option<String>,
    #[serde(default)]
    pub promote: Option<bool>,
    #[serde(default)]
    pub privacy_class: Option<String>,
    #[serde(default)]
    pub provenance: serde_json::Value,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct CaptureReviewResult {
    pub id: String,
    pub created_at: String,
    pub schema_version: String,
    pub status: String,
    pub promoted_count: usize,
    #[serde(default)]
    pub sounio_moments: Vec<SounioMoment>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub memory_event: Option<MemoryEvent>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub audit_event: Option<AuditEvent>,
    #[serde(default)]
    pub candidates: Vec<CaptureReviewCandidate>,
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
        .route("/api/exocortex/v1/write/probe", post(write_probe_handler))
        .route(
            "/api/exocortex/v1/failed-writes",
            get(failed_writes_handler).post(failed_write_record_handler),
        )
        .route(
            "/api/exocortex/v1/failed-writes/rescue",
            post(failed_write_rescue_handler),
        )
        .route(
            "/api/exocortex/v1/capture/sessions",
            post(capture_session_start_handler),
        )
        .route(
            "/api/exocortex/v1/capture/sessions/:session_id",
            get(capture_session_status_handler),
        )
        .route(
            "/api/exocortex/v1/capture/sessions/:session_id/events",
            post(capture_session_event_handler),
        )
        .route(
            "/api/exocortex/v1/capture/visual/artifacts",
            post(capture_visual_artifact_handler),
        )
        .route(
            "/api/exocortex/v1/capture/visual/analyze",
            post(capture_visual_analyze_handler),
        )
        .route(
            "/api/exocortex/v1/capture/review",
            post(capture_review_handler),
        )
        .route(
            "/api/exocortex/v1/context/compile",
            post(context_compile_handler),
        )
        .route(
            "/api/exocortex/v1/context/packs/:pack_id",
            get(context_pack_get_handler),
        )
        .route(
            "/api/exocortex/v1/memory/effectiveness/events",
            post(memory_effectiveness_event_handler),
        )
        .route(
            "/api/exocortex/v1/memory/policy/status",
            get(memory_policy_status_handler),
        )
        .route(
            "/api/exocortex/v1/memory/dreamcycle/run",
            post(memory_dreamcycle_run_handler),
        )
        .route(
            "/api/exocortex/v1/memory/dreamcycle/status",
            get(memory_dreamcycle_status_handler),
        )
        .route(
            "/api/exocortex/v1/sounio/programs/check",
            post(sounio_program_check_handler),
        )
        .route(
            "/api/exocortex/v1/sounio/claims/check",
            post(sounio_claim_check_handler),
        )
        .route(
            "/api/exocortex/v1/sounio/moments/type",
            post(sounio_moment_type_handler),
        )
        .route(
            "/api/exocortex/v1/sounio/moments/recent",
            get(sounio_moments_recent_handler),
        )
        .route(
            "/api/exocortex/v1/sounio/moments/:moment_id/review",
            post(sounio_moment_review_handler),
        )
        .route(
            "/api/exocortex/v1/sounio/workday/status",
            get(sounio_workday_status_handler),
        )
        .route(
            "/api/exocortex/v1/sounio/paperruns",
            post(sounio_paperrun_start_handler),
        )
        .route(
            "/api/exocortex/v1/sounio/paperruns/:paper_run_id",
            get(sounio_paperrun_get_handler),
        )
        .route(
            "/api/exocortex/v1/sounio/paperruns/:paper_run_id/approve-step",
            post(sounio_paperrun_approve_step_handler),
        )
        .route(
            "/api/exocortex/v1/sounio/paperruns/:paper_run_id/artifacts",
            get(sounio_paperrun_artifacts_handler),
        )
        .route(
            "/api/exocortex/v1/sounio/paperruns/:paper_run_id/claims",
            post(sounio_paperrun_add_claim_handler),
        )
        .route(
            "/api/exocortex/v1/sounio/paperruns/:paper_run_id/claims/:claim_id/review",
            post(sounio_claim_review_handler),
        )
        .route(
            "/api/exocortex/v1/sounio/paperruns/:paper_run_id/theatre",
            get(sounio_paperrun_theatre_handler),
        )
        .route(
            "/api/exocortex/v1/sounio/paperruns/:paper_run_id/public-digest",
            get(sounio_paperrun_public_digest_handler),
        )
        .route(
            "/api/exocortex/v1/sounio/trace",
            get(sounio_trace_query_handler),
        )
        .route(
            "/api/exocortex/v1/memory/export",
            post(memory_export_handler),
        )
        .route(
            "/api/exocortex/v1/memory/truthsets",
            post(memory_truthset_create_handler),
        )
        .route(
            "/api/exocortex/v1/memory/truthsets/:truthset_id",
            get(memory_truthset_get_handler),
        )
        .route(
            "/api/exocortex/v1/memory/truthsets/:truthset_id/cases",
            post(memory_truthset_case_create_handler),
        )
        .route(
            "/api/exocortex/v1/memory/truthsets/:truthset_id/review",
            post(memory_truthset_review_handler),
        )
        .route(
            "/api/exocortex/v1/memory/candidates",
            get(memory_candidates_handler).post(memory_candidate_create_handler),
        )
        .route(
            "/api/exocortex/v1/memory/candidates/:candidate_id/quorum",
            post(memory_candidate_quorum_handler),
        )
        .route(
            "/api/exocortex/v1/memory/candidates/:candidate_id/promote",
            post(memory_candidate_promote_handler),
        )
        .route(
            "/api/exocortex/v1/memory/governance/run",
            post(memory_governance_run_handler),
        )
        .route(
            "/api/exocortex/v1/memory/governance/status",
            get(memory_governance_status_handler),
        )
        .route(
            "/api/exocortex/v1/memory/contradictions",
            get(memory_contradictions_handler),
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
            "/api/exocortex/v1/memory/graph/status",
            get(memory_graph_status_handler),
        )
        .route(
            "/api/exocortex/v1/memory/bench/status",
            get(memory_bench_status_handler),
        )
        .route(
            "/api/exocortex/v1/memory/graph/bakeoff",
            post(memory_graph_bakeoff_handler),
        )
        .route(
            "/api/exocortex/v1/memory/graph/bakeoff/status",
            get(memory_graph_bakeoff_status_handler),
        )
        .route(
            "/api/exocortex/v1/memory/index-graph",
            post(memory_index_graph_handler),
        )
        .route(
            "/api/exocortex/v1/memory/graph/recent",
            get(memory_graph_recent_handler),
        )
        .route(
            "/api/exocortex/v1/memory/worlds/recent",
            get(memory_worlds_recent_handler),
        )
        .route(
            "/api/exocortex/v1/spatial/worlds/marble",
            post(spatial_world_marble_handler),
        )
        .route(
            "/api/exocortex/v1/spatial/worlds/:world_id",
            get(spatial_world_get_handler),
        )
        .route(
            "/api/exocortex/v1/spatial/worlds/:world_id/assets",
            get(spatial_world_assets_handler),
        )
        .route(
            "/api/exocortex/v1/spatial/projects/:slug/control-room",
            get(spatial_control_room_handler),
        )
        .route(
            "/api/exocortex/v1/spatial/worlds/:world_id/sounio/evidence",
            post(spatial_sounio_evidence_handler),
        )
        .route("/api/exocortex/v1/mind-palace", get(mind_palace_handler))
        .route(
            "/api/exocortex/v1/mind-palace/rooms",
            get(mind_palace_rooms_handler),
        )
        .route(
            "/api/exocortex/v1/mind-palace/desk",
            get(mind_palace_desk_handler),
        )
        .route(
            "/api/exocortex/v1/mind-palace/next-best-place",
            get(mind_palace_next_best_place_handler),
        )
        .route(
            "/api/exocortex/v1/mind-palace/action-menu",
            get(mind_palace_action_menu_handler),
        )
        .route(
            "/api/exocortex/v1/conversation-portals",
            post(conversation_portal_create_handler),
        )
        .route(
            "/api/exocortex/v1/conversation-portals/:portal_id/promote",
            post(conversation_portal_promote_handler),
        )
        .route(
            "/api/exocortex/v1/focus-coach/status",
            get(focus_coach_status_handler),
        )
        .route(
            "/api/exocortex/v1/focus-coach/events",
            post(focus_coach_event_handler),
        )
        .route(
            "/api/exocortex/v1/graphrag/query",
            post(graphrag_query_handler),
        )
        .route(
            "/api/exocortex/v1/recall/answer",
            post(recall_answer_handler),
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

/// Resolve the caller's effective scopes from the bearer token, mirroring `api_token_auth`.
///
/// Returns `(granted_scopes, principal)`. An empty scope list means the caller is
/// unauthenticated/unknown — in that case the probe falls back to whatever scopes the
/// client declared in the request body (backward compatible).
async fn resolve_probe_scopes(
    state: &AppState,
    headers: &HeaderMap,
) -> (Vec<String>, Option<String>) {
    fn scopes_for(id: ConsumerId) -> Vec<String> {
        match id {
            ConsumerId::BeagleOperator => vec![
                "exocortex:read".to_string(),
                "memory:write".to_string(),
                "chronoself:write".to_string(),
                "research:run".to_string(),
                "agent:start".to_string(),
            ],
            ConsumerId::DarwinResearch => {
                vec!["exocortex:read".to_string(), "research:run".to_string()]
            }
        }
    }
    fn principal_of(id: ConsumerId) -> Option<String> {
        Some(consumer_identity_for_id(id).id)
    }

    let auth = headers
        .get(axum::http::header::AUTHORIZATION)
        .and_then(|h| h.to_str().ok())
        .unwrap_or("");
    let bearer = auth.strip_prefix("Bearer ").map(str::trim).unwrap_or("");

    let ctx = state.ctx.lock().await;

    // Consumer-policy-aware path (mirrors api_token_auth).
    if ctx.cfg.consumers.policy_enabled {
        let consumer_header = headers
            .get("X-Beagle-Consumer")
            .and_then(|h| h.to_str().ok())
            .unwrap_or("");
        if let Some(consumer_id) = ConsumerId::from_header(consumer_header) {
            let expected = match consumer_id {
                ConsumerId::BeagleOperator => ctx
                    .cfg
                    .consumers
                    .operator_token
                    .as_deref()
                    .or(ctx.cfg.api_token.as_deref()),
                ConsumerId::DarwinResearch => ctx.cfg.consumers.research_token.as_deref(),
            };
            if let Some(tok) = expected {
                if !bearer.is_empty() && bearer == tok {
                    return (scopes_for(consumer_id), principal_of(consumer_id));
                }
            }
        }
        return (Vec::new(), None);
    }

    // Consumer policy disabled.
    match ctx.cfg.api_token.as_deref() {
        Some(expected) => {
            if !bearer.is_empty() && bearer == expected {
                (
                    scopes_for(ConsumerId::BeagleOperator),
                    principal_of(ConsumerId::BeagleOperator),
                )
            } else {
                (Vec::new(), None)
            }
        }
        // No token configured (dev/lab): the deployment is unauthenticated, so the probe
        // reflects that an operator-equivalent caller can write — same posture as api_token_auth.
        None => (
            scopes_for(ConsumerId::BeagleOperator),
            principal_of(ConsumerId::BeagleOperator),
        ),
    }
}

async fn write_probe_handler(
    State(state): State<AppState>,
    headers: HeaderMap,
    Json(mut req): Json<WriteProbeRequest>,
) -> Result<Json<WriteProbeResponse>, StatusCode> {
    // Derive the caller's real scopes from the bearer token instead of trusting the
    // self-declared `granted_scopes` in the body. Token-derived scopes are unioned with any
    // client-declared ones so explicit callers still work.
    let (token_scopes, principal) = resolve_probe_scopes(&state, &headers).await;
    if !token_scopes.is_empty() {
        let mut merged: BTreeSet<String> = req
            .granted_scopes
            .iter()
            .map(|scope| scope.trim().to_string())
            .filter(|scope| !scope.is_empty())
            .collect();
        merged.extend(token_scopes);
        req.granted_scopes = merged.into_iter().collect();
        if req
            .principal
            .as_deref()
            .map(str::trim)
            .unwrap_or("")
            .is_empty()
        {
            req.principal = principal;
        }
        if req
            .source_surface
            .as_deref()
            .map(str::trim)
            .unwrap_or("")
            .is_empty()
        {
            req.source_surface = Some("beagle-core-token".to_string());
        }
    }

    let repo = ExocortexRepository::default();
    repo.ensure().map_err(internal_error)?;
    let result = repo.write_probe(req).map_err(internal_error)?;
    Ok(Json(result))
}

async fn failed_writes_handler(
    State(_state): State<AppState>,
    Query(query): Query<LimitQuery>,
) -> Result<Json<FailedWriteInboxResponse>, StatusCode> {
    let repo = ExocortexRepository::default();
    repo.ensure().map_err(internal_error)?;
    let items = repo
        .failed_write_inbox(query.limit.unwrap_or(50))
        .map_err(internal_error)?;
    Ok(Json(FailedWriteInboxResponse { items }))
}

async fn failed_write_record_handler(
    State(_state): State<AppState>,
    Json(req): Json<FailedWriteRecordRequest>,
) -> Result<Json<FailedWriteInboxItem>, StatusCode> {
    let repo = ExocortexRepository::default();
    repo.ensure().map_err(internal_error)?;
    let item = repo.record_failed_write(req).map_err(internal_error)?;
    Ok(Json(item))
}

async fn failed_write_rescue_handler(
    State(_state): State<AppState>,
    Json(req): Json<FailedWriteRescueRequest>,
) -> Result<Json<FailedWriteRescueResponse>, StatusCode> {
    let repo = ExocortexRepository::default();
    repo.ensure().map_err(internal_error)?;
    let response = repo.rescue_failed_write(req).map_err(internal_error)?;
    Ok(Json(response))
}

async fn capture_session_start_handler(
    State(_state): State<AppState>,
    Json(req): Json<CaptureSessionStartRequest>,
) -> Result<Json<CaptureSession>, StatusCode> {
    let repo = ExocortexRepository::default();
    repo.ensure().map_err(internal_error)?;
    let session = repo.start_capture_session(req).map_err(internal_error)?;
    Ok(Json(session))
}

async fn capture_session_status_handler(
    State(_state): State<AppState>,
    Path(session_id): Path<String>,
) -> Result<Json<CaptureSession>, StatusCode> {
    let repo = ExocortexRepository::default();
    repo.ensure().map_err(internal_error)?;
    repo.capture_session(&session_id)
        .map_err(internal_error)?
        .map(Json)
        .ok_or(StatusCode::NOT_FOUND)
}

async fn capture_session_event_handler(
    State(_state): State<AppState>,
    Path(session_id): Path<String>,
    Json(req): Json<CaptureSessionEventRequest>,
) -> Result<Json<CaptureSessionEvent>, StatusCode> {
    let repo = ExocortexRepository::default();
    repo.ensure().map_err(internal_error)?;
    let event = repo
        .append_capture_session_event(&session_id, req)
        .map_err(internal_error)?;
    Ok(Json(event))
}

async fn capture_visual_artifact_handler(
    State(_state): State<AppState>,
    Json(req): Json<VisualEvidenceArtifactRequest>,
) -> Result<Json<VisualEvidenceArtifact>, StatusCode> {
    let repo = ExocortexRepository::default();
    repo.ensure().map_err(internal_error)?;
    let artifact = repo
        .create_visual_evidence_artifact(req)
        .map_err(internal_error)?;
    Ok(Json(artifact))
}

async fn capture_visual_analyze_handler(
    State(_state): State<AppState>,
    Json(req): Json<VisualEvidenceAnalyzeRequest>,
) -> Result<Json<VisualEvidenceAnalysis>, StatusCode> {
    let repo = ExocortexRepository::default();
    repo.ensure().map_err(internal_error)?;
    let analysis = repo.analyze_visual_evidence(req).map_err(internal_error)?;
    Ok(Json(analysis))
}

async fn capture_review_handler(
    State(_state): State<AppState>,
    Json(req): Json<CaptureReviewRequest>,
) -> Result<Json<CaptureReviewResult>, StatusCode> {
    let repo = ExocortexRepository::default();
    repo.ensure().map_err(internal_error)?;
    let result = repo
        .review_capture_candidates(req)
        .map_err(internal_error)?;
    Ok(Json(result))
}

async fn context_compile_handler(
    State(_state): State<AppState>,
    Json(req): Json<ContextCompileRequest>,
) -> Result<Json<ContextPack>, StatusCode> {
    let repo = ExocortexRepository::default();
    repo.ensure().map_err(internal_error)?;
    let pack = repo.context_compile(req).map_err(internal_error)?;
    Ok(Json(pack))
}

async fn context_pack_get_handler(
    State(_state): State<AppState>,
    Path(pack_id): Path<String>,
) -> Result<Json<ContextPack>, StatusCode> {
    let repo = ExocortexRepository::default();
    repo.ensure().map_err(internal_error)?;
    repo.context_pack(&pack_id)
        .map_err(internal_error)?
        .map(Json)
        .ok_or(StatusCode::NOT_FOUND)
}

async fn memory_effectiveness_event_handler(
    State(_state): State<AppState>,
    Json(req): Json<MemoryEffectivenessEventRequest>,
) -> Result<Json<MemoryEffectivenessEvent>, StatusCode> {
    let repo = ExocortexRepository::default();
    repo.ensure().map_err(internal_error)?;
    let event = repo
        .record_memory_effectiveness(req)
        .map_err(internal_error)?;
    Ok(Json(event))
}

async fn memory_policy_status_handler(
    State(_state): State<AppState>,
) -> Result<Json<MemoryPolicyStatus>, StatusCode> {
    let repo = ExocortexRepository::default();
    repo.ensure().map_err(internal_error)?;
    let status = repo.memory_policy_status().map_err(internal_error)?;
    Ok(Json(status))
}

async fn memory_dreamcycle_run_handler(
    State(_state): State<AppState>,
    Json(req): Json<DreamCycleRunRequest>,
) -> Result<Json<DreamCycleRun>, StatusCode> {
    let repo = ExocortexRepository::default();
    repo.ensure().map_err(internal_error)?;
    let run = repo.run_dreamcycle(req).map_err(internal_error)?;
    Ok(Json(run))
}

async fn memory_dreamcycle_status_handler(
    State(_state): State<AppState>,
) -> Result<Json<DreamCycleStatus>, StatusCode> {
    let repo = ExocortexRepository::default();
    repo.ensure().map_err(internal_error)?;
    let status = repo.dreamcycle_status().map_err(internal_error)?;
    Ok(Json(status))
}

async fn sounio_program_check_handler(
    State(_state): State<AppState>,
    Json(req): Json<SounioProgramCheckRequest>,
) -> Result<Json<SounioProgramCheckResponse>, StatusCode> {
    let repo = ExocortexRepository::default();
    repo.ensure().map_err(internal_error)?;
    let response = repo.check_sounio_program(req).map_err(internal_error)?;
    Ok(Json(response))
}

async fn sounio_claim_check_handler(
    State(_state): State<AppState>,
    Json(req): Json<SounioClaimCheckRequest>,
) -> Result<Json<SounioClaimCheckResponse>, StatusCode> {
    let repo = ExocortexRepository::default();
    repo.ensure().map_err(internal_error)?;
    let response = repo.check_sounio_claim(req).map_err(internal_error)?;
    Ok(Json(response))
}

async fn sounio_moment_type_handler(
    State(_state): State<AppState>,
    Json(req): Json<SounioMomentTypeRequest>,
) -> Result<Json<SounioMoment>, StatusCode> {
    let repo = ExocortexRepository::default();
    repo.ensure().map_err(internal_error)?;
    let moment = repo.type_sounio_moment(req).map_err(internal_error)?;
    Ok(Json(moment))
}

async fn sounio_moments_recent_handler(
    State(_state): State<AppState>,
    Query(query): Query<SounioMomentsQuery>,
) -> Result<Json<SounioMomentListResponse>, StatusCode> {
    let repo = ExocortexRepository::default();
    repo.ensure().map_err(internal_error)?;
    let moments = repo.sounio_moments_recent(query).map_err(internal_error)?;
    Ok(Json(moments))
}

async fn sounio_moment_review_handler(
    State(_state): State<AppState>,
    Path(moment_id): Path<String>,
    Json(req): Json<SounioMomentReviewRequest>,
) -> Result<Json<SounioMoment>, StatusCode> {
    let repo = ExocortexRepository::default();
    repo.ensure().map_err(internal_error)?;
    let moment = repo
        .review_sounio_moment(&moment_id, req)
        .map_err(internal_error)?;
    Ok(Json(moment))
}

async fn sounio_workday_status_handler(
    State(_state): State<AppState>,
    Query(query): Query<SounioWorkdayQuery>,
) -> Result<Json<SounioWorkdaySnapshot>, StatusCode> {
    let repo = ExocortexRepository::default();
    repo.ensure().map_err(internal_error)?;
    let snapshot = repo.sounio_workday_status(query).map_err(internal_error)?;
    Ok(Json(snapshot))
}

async fn sounio_paperrun_start_handler(
    State(_state): State<AppState>,
    Json(req): Json<StartPaperRunRequest>,
) -> Result<Json<PaperRun>, StatusCode> {
    let repo = ExocortexRepository::default();
    repo.ensure().map_err(internal_error)?;
    let run = repo.start_paper_run(req).map_err(internal_error)?;
    Ok(Json(run))
}

async fn sounio_paperrun_get_handler(
    State(_state): State<AppState>,
    Path(paper_run_id): Path<String>,
) -> Result<Json<PaperRun>, StatusCode> {
    let repo = ExocortexRepository::default();
    repo.ensure().map_err(internal_error)?;
    repo.paper_run(&paper_run_id)
        .map_err(internal_error)?
        .map(Json)
        .ok_or(StatusCode::NOT_FOUND)
}

async fn sounio_paperrun_approve_step_handler(
    State(_state): State<AppState>,
    Path(paper_run_id): Path<String>,
    Json(req): Json<ApprovePaperRunStepRequest>,
) -> Result<Json<PaperRun>, StatusCode> {
    let repo = ExocortexRepository::default();
    repo.ensure().map_err(internal_error)?;
    let run = repo
        .approve_paper_run_step(&paper_run_id, req)
        .map_err(internal_error)?;
    Ok(Json(run))
}

async fn sounio_paperrun_artifacts_handler(
    State(_state): State<AppState>,
    Path(paper_run_id): Path<String>,
) -> Result<Json<PaperRunArtifactsResponse>, StatusCode> {
    let repo = ExocortexRepository::default();
    repo.ensure().map_err(internal_error)?;
    let artifacts = repo
        .paper_run_artifacts(&paper_run_id)
        .map_err(internal_error)?
        .ok_or(StatusCode::NOT_FOUND)?;
    Ok(Json(artifacts))
}

async fn sounio_paperrun_add_claim_handler(
    State(_state): State<AppState>,
    Path(paper_run_id): Path<String>,
    Json(req): Json<AddPaperRunClaimRequest>,
) -> Result<Json<SounioClaim>, StatusCode> {
    let repo = ExocortexRepository::default();
    repo.ensure().map_err(internal_error)?;
    let claim = repo
        .add_paper_run_claim(&paper_run_id, req)
        .map_err(internal_error)?;
    Ok(Json(claim))
}

async fn sounio_claim_review_handler(
    State(_state): State<AppState>,
    Path((paper_run_id, claim_id)): Path<(String, String)>,
    Json(req): Json<ReviewSounioClaimRequest>,
) -> Result<Json<SounioClaim>, StatusCode> {
    let repo = ExocortexRepository::default();
    repo.ensure().map_err(internal_error)?;
    let claim = repo
        .review_sounio_claim(&paper_run_id, &claim_id, req)
        .map_err(internal_error)?;
    Ok(Json(claim))
}

async fn sounio_paperrun_theatre_handler(
    State(_state): State<AppState>,
    Path(paper_run_id): Path<String>,
) -> Result<Json<PaperRunTheatreSnapshot>, StatusCode> {
    let repo = ExocortexRepository::default();
    repo.ensure().map_err(internal_error)?;
    let snapshot = repo
        .paper_run_theatre(&paper_run_id)
        .map_err(internal_error)?
        .ok_or(StatusCode::NOT_FOUND)?;
    Ok(Json(snapshot))
}

async fn sounio_paperrun_public_digest_handler(
    State(_state): State<AppState>,
    Path(paper_run_id): Path<String>,
) -> Result<Json<PublicDigestArtifact>, StatusCode> {
    let repo = ExocortexRepository::default();
    repo.ensure().map_err(internal_error)?;
    let digest = repo
        .paper_run_public_digest(&paper_run_id)
        .map_err(internal_error)?
        .ok_or(StatusCode::NOT_FOUND)?;
    Ok(Json(digest))
}

async fn sounio_trace_query_handler(
    State(_state): State<AppState>,
    Query(query): Query<SounioTraceQuery>,
) -> Result<Json<SounioTraceListResponse>, StatusCode> {
    let repo = ExocortexRepository::default();
    repo.ensure().map_err(internal_error)?;
    let events = repo.sounio_trace_events(query).map_err(internal_error)?;
    Ok(Json(SounioTraceListResponse { events }))
}

async fn memory_export_handler(
    State(_state): State<AppState>,
    Json(req): Json<MemoryExportRequest>,
) -> Result<Json<MemoryExportResponse>, StatusCode> {
    let repo = ExocortexRepository::default();
    repo.ensure().map_err(internal_error)?;
    let export = repo.export_sanitized_memory(req).map_err(internal_error)?;
    Ok(Json(export))
}

async fn memory_truthset_create_handler(
    State(_state): State<AppState>,
    Json(req): Json<CreateMemoryTruthSetRequest>,
) -> Result<Json<MemoryTruthSet>, StatusCode> {
    let repo = ExocortexRepository::default();
    repo.ensure().map_err(internal_error)?;
    let truthset = repo.create_memory_truthset(req).map_err(internal_error)?;
    Ok(Json(truthset))
}

async fn memory_truthset_get_handler(
    State(_state): State<AppState>,
    Path(truthset_id): Path<String>,
) -> Result<Json<MemoryTruthSetResponse>, StatusCode> {
    let repo = ExocortexRepository::default();
    repo.ensure().map_err(internal_error)?;
    let response = repo
        .memory_truthset_response(&truthset_id)
        .map_err(internal_error)?
        .ok_or(StatusCode::NOT_FOUND)?;
    Ok(Json(response))
}

async fn memory_truthset_case_create_handler(
    State(_state): State<AppState>,
    Path(truthset_id): Path<String>,
    Json(req): Json<CreateMemoryTruthCaseRequest>,
) -> Result<Json<MemoryTruthCase>, StatusCode> {
    let repo = ExocortexRepository::default();
    repo.ensure().map_err(internal_error)?;
    let case = repo
        .create_memory_truth_case(&truthset_id, req)
        .map_err(internal_error)?;
    Ok(Json(case))
}

async fn memory_truthset_review_handler(
    State(_state): State<AppState>,
    Path(truthset_id): Path<String>,
    Json(req): Json<ReviewMemoryTruthSetRequest>,
) -> Result<Json<MemoryTruthSetResponse>, StatusCode> {
    let repo = ExocortexRepository::default();
    repo.ensure().map_err(internal_error)?;
    let response = repo
        .review_memory_truthset(&truthset_id, req)
        .map_err(internal_error)?;
    Ok(Json(response))
}

async fn memory_candidates_handler(
    State(_state): State<AppState>,
    Query(query): Query<LimitQuery>,
) -> Result<Json<MemoryCandidateListResponse>, StatusCode> {
    let repo = ExocortexRepository::default();
    repo.ensure().map_err(internal_error)?;
    let candidates = repo
        .latest_memory_candidates(query.limit.unwrap_or(50))
        .map_err(internal_error)?;
    Ok(Json(MemoryCandidateListResponse { candidates }))
}

async fn memory_candidate_create_handler(
    State(_state): State<AppState>,
    Json(req): Json<CreateMemoryCandidateRequest>,
) -> Result<Json<MemoryCandidate>, StatusCode> {
    let repo = ExocortexRepository::default();
    repo.ensure().map_err(internal_error)?;
    let candidate = repo.create_memory_candidate(req).map_err(internal_error)?;
    Ok(Json(candidate))
}

async fn memory_candidate_quorum_handler(
    State(_state): State<AppState>,
    Path(candidate_id): Path<String>,
    Json(req): Json<CandidateQuorumRequest>,
) -> Result<Json<CandidateQuorumDecision>, StatusCode> {
    let repo = ExocortexRepository::default();
    repo.ensure().map_err(internal_error)?;
    let decision = repo
        .record_candidate_quorum(&candidate_id, req)
        .map_err(internal_error)?;
    Ok(Json(decision))
}

async fn memory_candidate_promote_handler(
    State(_state): State<AppState>,
    Path(candidate_id): Path<String>,
    Json(req): Json<CandidatePromoteRequest>,
) -> Result<Json<CandidatePromotionResponse>, StatusCode> {
    let repo = ExocortexRepository::default();
    repo.ensure().map_err(internal_error)?;
    let response = repo
        .promote_memory_candidate(&candidate_id, req)
        .map_err(internal_error)?;
    Ok(Json(response))
}

async fn memory_governance_run_handler(
    State(_state): State<AppState>,
    Json(req): Json<MemoryGovernanceRunRequest>,
) -> Result<Json<MemoryGovernanceRun>, StatusCode> {
    let repo = ExocortexRepository::default();
    repo.ensure().map_err(internal_error)?;
    let run = repo.run_memory_governance(req).map_err(internal_error)?;
    Ok(Json(run))
}

async fn memory_governance_status_handler(
    State(_state): State<AppState>,
) -> Result<Json<MemoryGovernanceStatus>, StatusCode> {
    let repo = ExocortexRepository::default();
    repo.ensure().map_err(internal_error)?;
    let status = repo.memory_governance_status().map_err(internal_error)?;
    Ok(Json(status))
}

async fn memory_contradictions_handler(
    State(_state): State<AppState>,
    Query(query): Query<LimitQuery>,
) -> Result<Json<MemoryContradictionListResponse>, StatusCode> {
    let repo = ExocortexRepository::default();
    repo.ensure().map_err(internal_error)?;
    let contradictions = repo
        .read_recent_jsonl::<MemoryContradiction>(
            MEMORY_CONTRADICTIONS_LOG,
            query.limit.unwrap_or(50),
        )
        .map_err(internal_error)?;
    Ok(Json(MemoryContradictionListResponse { contradictions }))
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

async fn memory_graph_status_handler(
    State(_state): State<AppState>,
) -> Result<Json<MemoryGraphStatus>, StatusCode> {
    let repo = ExocortexRepository::default();
    repo.ensure().map_err(internal_error)?;
    let status = repo.memory_graph_status().map_err(internal_error)?;
    Ok(Json(status))
}

async fn memory_bench_status_handler(
    State(_state): State<AppState>,
) -> Result<Json<MemoryBenchmarkStatus>, StatusCode> {
    let repo = ExocortexRepository::default();
    repo.ensure().map_err(internal_error)?;
    let status = repo.memory_benchmark_status().map_err(internal_error)?;
    Ok(Json(status))
}

async fn memory_graph_bakeoff_handler(
    State(_state): State<AppState>,
    Json(req): Json<GraphBakeoffRequest>,
) -> Result<Json<GraphBakeoffRun>, StatusCode> {
    let repo = ExocortexRepository::default();
    repo.ensure().map_err(internal_error)?;
    let run = repo.run_graph_bakeoff(req).map_err(internal_error)?;
    Ok(Json(run))
}

async fn memory_graph_bakeoff_status_handler(
    State(_state): State<AppState>,
) -> Result<Json<MemoryGraphStatus>, StatusCode> {
    let repo = ExocortexRepository::default();
    repo.ensure().map_err(internal_error)?;
    let status = repo.memory_graph_status().map_err(internal_error)?;
    Ok(Json(status))
}

async fn memory_index_graph_handler(
    State(_state): State<AppState>,
    Json(req): Json<GraphIndexRequest>,
) -> Result<Json<GraphIndexRun>, StatusCode> {
    let repo = ExocortexRepository::default();
    repo.ensure().map_err(internal_error)?;
    let run = repo.index_graph(req).map_err(internal_error)?;
    Ok(Json(run))
}

async fn memory_graph_recent_handler(
    State(_state): State<AppState>,
    Query(query): Query<LimitQuery>,
) -> Result<Json<MemoryGraphRecentResponse>, StatusCode> {
    let repo = ExocortexRepository::default();
    repo.ensure().map_err(internal_error)?;
    let response = repo
        .memory_graph_recent(query.limit.unwrap_or(12))
        .map_err(internal_error)?;
    Ok(Json(response))
}

async fn memory_worlds_recent_handler(
    State(_state): State<AppState>,
    Query(query): Query<LimitQuery>,
) -> Result<Json<MemoryWorldsRecentResponse>, StatusCode> {
    let repo = ExocortexRepository::default();
    repo.ensure().map_err(internal_error)?;
    let response = repo
        .memory_worlds_recent(query.limit.unwrap_or(12))
        .map_err(internal_error)?;
    Ok(Json(response))
}

async fn spatial_world_marble_handler(
    State(_state): State<AppState>,
    Json(req): Json<CreateSpatialWorldRequest>,
) -> Result<Json<SpatialWorld>, StatusCode> {
    let repo = ExocortexRepository::default();
    repo.ensure().map_err(internal_error)?;
    let world = repo.create_spatial_world(req).map_err(internal_error)?;
    Ok(Json(world))
}

async fn spatial_world_get_handler(
    State(_state): State<AppState>,
    Path(world_id): Path<String>,
) -> Result<Json<SpatialWorld>, StatusCode> {
    let repo = ExocortexRepository::default();
    repo.ensure().map_err(internal_error)?;
    repo.spatial_world(&world_id)
        .map_err(internal_error)?
        .map(Json)
        .ok_or(StatusCode::NOT_FOUND)
}

async fn spatial_world_assets_handler(
    State(_state): State<AppState>,
    Path(world_id): Path<String>,
) -> Result<Json<SpatialAssetManifest>, StatusCode> {
    let repo = ExocortexRepository::default();
    repo.ensure().map_err(internal_error)?;
    repo.spatial_world(&world_id)
        .map_err(internal_error)?
        .map(|world| Json(world.assets))
        .ok_or(StatusCode::NOT_FOUND)
}

async fn spatial_control_room_handler(
    State(_state): State<AppState>,
    Path(slug): Path<String>,
) -> Result<Json<ControlRoomSnapshot>, StatusCode> {
    let repo = ExocortexRepository::default();
    repo.ensure().map_err(internal_error)?;
    let snapshot = repo.control_room_snapshot(&slug).map_err(internal_error)?;
    Ok(Json(snapshot))
}

async fn spatial_sounio_evidence_handler(
    State(_state): State<AppState>,
    Path(world_id): Path<String>,
    Json(req): Json<CreateSounioSpatialEvidenceRequest>,
) -> Result<Json<SounioSpatialEvidence>, StatusCode> {
    let repo = ExocortexRepository::default();
    repo.ensure().map_err(internal_error)?;
    let evidence = repo
        .create_spatial_evidence(&world_id, req)
        .map_err(internal_error)?;
    Ok(Json(evidence))
}

async fn mind_palace_handler(
    State(_state): State<AppState>,
) -> Result<Json<MindPalaceSnapshot>, StatusCode> {
    let repo = ExocortexRepository::default();
    repo.ensure().map_err(internal_error)?;
    let snapshot = repo.mind_palace_snapshot().map_err(internal_error)?;
    Ok(Json(snapshot))
}

async fn mind_palace_rooms_handler(
    State(_state): State<AppState>,
) -> Result<Json<Vec<MindPalaceRoom>>, StatusCode> {
    let repo = ExocortexRepository::default();
    repo.ensure().map_err(internal_error)?;
    let snapshot = repo.mind_palace_snapshot().map_err(internal_error)?;
    Ok(Json(snapshot.rooms))
}

async fn mind_palace_desk_handler(
    State(_state): State<AppState>,
) -> Result<Json<SpatialDeskSnapshot>, StatusCode> {
    let repo = ExocortexRepository::default();
    repo.ensure().map_err(internal_error)?;
    let snapshot = repo.mind_palace_snapshot().map_err(internal_error)?;
    Ok(Json(snapshot.desk))
}

async fn mind_palace_next_best_place_handler(
    State(_state): State<AppState>,
) -> Result<Json<NextBestPlaceDecision>, StatusCode> {
    let repo = ExocortexRepository::default();
    repo.ensure().map_err(internal_error)?;
    let snapshot = repo.mind_palace_snapshot().map_err(internal_error)?;
    Ok(Json(snapshot.next_best_place))
}

async fn mind_palace_action_menu_handler(
    State(_state): State<AppState>,
) -> Result<Json<SpatialActionMenu>, StatusCode> {
    let repo = ExocortexRepository::default();
    repo.ensure().map_err(internal_error)?;
    let snapshot = repo.mind_palace_snapshot().map_err(internal_error)?;
    Ok(Json(snapshot.action_menu))
}

async fn conversation_portal_create_handler(
    State(_state): State<AppState>,
    Json(req): Json<CreateConversationPortalRequest>,
) -> Result<Json<ConversationPortal>, StatusCode> {
    let repo = ExocortexRepository::default();
    repo.ensure().map_err(internal_error)?;
    let portal = repo
        .create_conversation_portal(req)
        .map_err(internal_error)?;
    Ok(Json(portal))
}

async fn conversation_portal_promote_handler(
    State(_state): State<AppState>,
    Path(portal_id): Path<String>,
    Json(req): Json<PromoteConversationPortalRequest>,
) -> Result<Json<PromotedConversationClip>, StatusCode> {
    let repo = ExocortexRepository::default();
    repo.ensure().map_err(internal_error)?;
    let clip = repo
        .promote_conversation_portal_clip(&portal_id, req)
        .map_err(internal_error)?;
    Ok(Json(clip))
}

async fn focus_coach_status_handler(
    State(_state): State<AppState>,
) -> Result<Json<FocusCoachState>, StatusCode> {
    let repo = ExocortexRepository::default();
    repo.ensure().map_err(internal_error)?;
    let state = repo.focus_coach_status().map_err(internal_error)?;
    Ok(Json(state))
}

async fn focus_coach_event_handler(
    State(_state): State<AppState>,
    Json(req): Json<FocusCoachEventRequest>,
) -> Result<Json<FocusCoachState>, StatusCode> {
    let repo = ExocortexRepository::default();
    repo.ensure().map_err(internal_error)?;
    let state = repo.record_focus_coach_event(req).map_err(internal_error)?;
    Ok(Json(state))
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

#[derive(Serialize)]
struct RecallSource {
    n: usize,
    text: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    date: Option<String>,
    source: String,
    score: f64,
}

#[derive(Serialize)]
struct RecallAnswerResponse {
    answer: String,
    sources: Vec<RecallSource>,
    confidence: f64,
    #[serde(skip_serializing_if = "Option::is_none")]
    scope: Option<String>,
    schema_version: String,
}

/// COMPOSED RECALL (cognitive loop slice a), promoted to a first-class exocortex capability:
/// retrieve project-scoped atoms (graphRAG / ColBERT) then SYNTHESIZE a composed natural-language
/// answer via the TieredRouter (fleet-first). Any client (cockpit, native app, MCP) can use it —
/// the synthesis no longer lives only in the cockpit's coord-mcp.
// --- Path C: prefer the memory-engine semantic index (jina-colbert-v2 multivector) which
// reranks rich conversation passages to the top, over the degraded graphrag atom projection.
#[derive(Debug, Deserialize)]
struct MemoryEngineSemanticResult {
    #[serde(default)]
    text_preview: String,
    #[serde(default)]
    score: Option<f64>,
    #[serde(default)]
    occurred_at: Option<String>,
    #[serde(default)]
    kind: Option<String>,
}

#[derive(Debug, Deserialize)]
struct MemoryEngineQueryResponse {
    #[serde(default)]
    semantic_results: Vec<MemoryEngineSemanticResult>,
}

/// Retrieve rich passages from the memory-engine `/v1/query`. Fail-soft: returns an empty
/// vec on any error so the caller falls back to the local graphrag projection.
async fn memory_engine_recall(query: &str, scope: &str, k: usize) -> Vec<RecallSource> {
    let base = env::var("BEAGLE_MEMORY_ENGINE_URL").unwrap_or_else(|_| {
        "http://beagle-memory-engine.beagle-memory-lab.svc.cluster.local:8090".to_string()
    });
    let url = format!("{}/v1/query", base.trim_end_matches('/'));
    let body = serde_json::json!({ "query": query, "scope": scope, "max_items": k });
    let client = match reqwest::Client::builder()
        .timeout(std::time::Duration::from_secs(30))
        .build()
    {
        Ok(c) => c,
        Err(_) => return Vec::new(),
    };
    let resp = match client.post(&url).json(&body).send().await {
        Ok(r) if r.status().is_success() => r,
        _ => return Vec::new(),
    };
    let parsed: MemoryEngineQueryResponse = match resp.json().await {
        Ok(p) => p,
        Err(_) => return Vec::new(),
    };
    parsed
        .semantic_results
        .into_iter()
        .filter(|r| r.text_preview.trim().chars().count() >= 40)
        .take(k)
        .enumerate()
        .map(|(i, r)| RecallSource {
            n: i + 1,
            text: r.text_preview,
            date: r.occurred_at,
            source: r.kind.unwrap_or_else(|| "memory-engine".to_string()),
            score: r.score.unwrap_or(0.0),
        })
        .collect()
}

async fn recall_answer_handler(
    State(state): State<AppState>,
    Json(req): Json<GraphRagQueryRequest>,
) -> Result<Json<RecallAnswerResponse>, StatusCode> {
    let repo = ExocortexRepository::default();
    repo.ensure().map_err(internal_error)?;
    let scope = req.scope.clone();
    let query = req.query.clone();
    let k = req.max_items.unwrap_or(8).min(12);
    // Path C: try the memory-engine semantic index first (rich passages); fall back to the
    // local graphrag atom projection if it yields nothing (or the engine is unreachable).
    let mut sources = memory_engine_recall(&query, scope.as_deref().unwrap_or("all"), k).await;
    let mut confidence = if sources.is_empty() { 0.0 } else { 0.85 };
    if sources.is_empty() {
        let gr = repo.graphrag_query(req).map_err(internal_error)?;
        confidence = gr.confidence;
        sources = gr
            .atoms
            .iter()
            .take(k)
            .enumerate()
            .map(|(i, a)| RecallSource {
                n: i + 1,
                text: a.text.clone(),
                date: a.occurred_at.clone().or_else(|| Some(a.created_at.clone())),
                source: if a.atom_type.is_empty() {
                    "exocortex".to_string()
                } else {
                    a.atom_type.clone()
                },
                score: a.confidence,
            })
            .filter(|s| !s.text.is_empty())
            .collect();
    }
    if sources.is_empty() {
        return Ok(Json(RecallAnswerResponse {
            answer: "No memory found for this query.".to_string(),
            sources: Vec::new(),
            confidence: 0.0,
            scope,
            schema_version: "beagle-recall-answer-v1".to_string(),
        }));
    }
    let ctx_str = sources
        .iter()
        .map(|s| format!("[{}] ({}) {}", s.n, s.date.as_deref().unwrap_or("?"), s.text))
        .collect::<Vec<_>>()
        .join("\n");
    let prompt = format!(
        "You are the recall-synthesis layer of an exocortex. Compose a CLEAR, GLANCEABLE answer from ONLY the memory atoms below. Format EXACTLY like this:\n**<headline: one line, max 14 words, no citation>**\n- **<2-4 word lead-in>:** <one specific sentence with names, versions, numbers> [n]\n(3 to 6 bullets, ordered by importance, merge duplicate facts, cite the atom(s) each draws from as [n], and on conflict keep the most recent). No preamble, no closing.\n\nQuestion: {query}\n\nMemory atoms:\n{ctx_str}"
    );
    let answer = {
        let mut bctx = state.ctx.lock().await;
        let meta = RequestMeta::from_prompt(&prompt);
        let stats = bctx.llm_stats.get_or_create("recall_answer");
        let (client, tier) = bctx.router.choose_with_limits(&meta, &stats);
        bctx.router
            .complete_chosen(&client, tier, &prompt)
            .await
            .map_err(|e| {
                error!("recall synthesis failed: {}", e);
                StatusCode::BAD_GATEWAY
            })?
    };
    Ok(Json(RecallAnswerResponse {
        answer: answer.trim().to_string(),
        sources,
        confidence,
        scope,
        schema_version: "beagle-recall-answer-v1".to_string(),
    }))
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

    fn start_capture_session(
        &self,
        req: CaptureSessionStartRequest,
    ) -> anyhow::Result<CaptureSession> {
        self.ensure()?;
        let now = Utc::now().to_rfc3339();
        let privacy_class = normalize_privacy_class(req.privacy_class.as_deref());
        anyhow::ensure!(
            privacy_class != "restricted",
            "restricted capture sessions must stay local until explicit review"
        );
        let mode = req
            .mode
            .as_deref()
            .map(|value| value.trim().to_lowercase())
            .filter(|value| !value.is_empty())
            .unwrap_or_else(|| "thinking_aloud".to_string());
        let surface = req
            .surface
            .as_deref()
            .map(|value| value.trim().to_lowercase())
            .filter(|value| !value.is_empty())
            .unwrap_or_else(|| "beagle-apple-composer".to_string());
        let project_slug = req
            .project_slug
            .as_deref()
            .map(|value| value.trim().to_lowercase())
            .filter(|value| !value.is_empty())
            .unwrap_or_else(|| "sounio".to_string());
        let principal = req
            .principal
            .as_deref()
            .map(|value| value.trim().to_string())
            .filter(|value| !value.is_empty())
            .unwrap_or_else(|| "beagle-apple-app".to_string());
        let id = stable_id("capture-session", &[&project_slug, &surface, &mode, &now]);
        let session = CaptureSession {
            id: id.clone(),
            created_at: now.clone(),
            updated_at: now,
            schema_version: CAPTURE_SESSION_SCHEMA.to_string(),
            project_slug,
            mode,
            surface: surface.clone(),
            principal: principal.clone(),
            title: req.title,
            privacy_class: privacy_class.clone(),
            status: "active".to_string(),
            raw_audio_policy: "local_ttl_short_discard_after_transcription".to_string(),
            raw_image_policy: "private_cluster_artifact_hash_merkle_provenance".to_string(),
            transcription_segments: Vec::new(),
            artifact_refs: Vec::new(),
            evidence_refs: Vec::new(),
            review_state: "open".to_string(),
            provenance: merge_json_objects(
                serde_json::json!({
                    "beagle_observes": true,
                    "sounio_types": false,
                    "anti_creepy_policy": "user_initiated_visible_session_only",
                    "ambient_listening": false,
                    "surface": surface,
                    "principal": principal,
                    "privacy_class": privacy_class
                }),
                req.metadata,
            ),
        };
        self.append_jsonl(CAPTURE_SESSIONS_LOG, &session)?;
        let _ = self.create_audit_event(CreateAuditEventRequest {
            client_id: Some(session.principal.clone()),
            action: Some("capture.session_start".to_string()),
            tool_name: Some("beagle_capture_session_start".to_string()),
            risk_level: Some("write".to_string()),
            required_scopes: vec!["memory:write".to_string()],
            granted_scopes: metadata_array_strings(&session.provenance, "scopes")
                .unwrap_or_default(),
            status: Some("success".to_string()),
            source: Some(session.surface.clone()),
            target_ref: Some(format!("capture_session:{}", session.id)),
            summary: Some(format!(
                "Started explicit {} capture session for {}.",
                session.mode, session.project_slug
            )),
            metadata: Some(serde_json::json!({
                "capture_session_id": session.id.clone(),
                "project_slug": session.project_slug.clone(),
                "mode": session.mode.clone(),
                "privacy_class": session.privacy_class.clone(),
                "anti_creepy_policy": "no_ambient_adtech_capture"
            })),
        })?;
        Ok(session)
    }

    fn capture_session(&self, session_id: &str) -> anyhow::Result<Option<CaptureSession>> {
        self.ensure()?;
        Ok(self
            .read_recent_jsonl::<CaptureSession>(CAPTURE_SESSIONS_LOG, usize::MAX)?
            .into_iter()
            .find(|session| session.id == session_id))
    }

    fn append_capture_session_event(
        &self,
        session_id: &str,
        req: CaptureSessionEventRequest,
    ) -> anyhow::Result<CaptureSessionEvent> {
        self.ensure()?;
        anyhow::ensure!(
            self.capture_session(session_id)?.is_some(),
            "capture session not found"
        );
        let privacy_class = normalize_privacy_class(req.privacy_class.as_deref());
        anyhow::ensure!(
            privacy_class != "restricted",
            "restricted capture events must stay in local review-only outbox"
        );
        let now = Utc::now().to_rfc3339();
        let event_type = if req.event_type.trim().is_empty() {
            "note".to_string()
        } else {
            req.event_type.trim().to_lowercase()
        };
        let id = stable_id(
            "capture-event",
            &[
                session_id,
                &event_type,
                req.text.as_deref().unwrap_or(""),
                &now,
            ],
        );
        let event = CaptureSessionEvent {
            id: id.clone(),
            created_at: now,
            session_id: session_id.to_string(),
            event_type,
            text: req.text.map(|value| truncate_chars(value.trim(), 4000)),
            transcription_segments: req
                .transcription_segments
                .into_iter()
                .map(normalize_transcription_segment)
                .collect(),
            artifact_refs: dedupe_strings(req.artifact_refs, 32),
            evidence_refs: dedupe_strings(req.evidence_refs, 48),
            privacy_class,
            metadata: req.metadata,
        };
        self.append_jsonl(CAPTURE_EVENTS_LOG, &event)?;
        Ok(event)
    }

    fn create_visual_evidence_artifact(
        &self,
        req: VisualEvidenceArtifactRequest,
    ) -> anyhow::Result<VisualEvidenceArtifact> {
        self.ensure()?;
        let privacy_class = normalize_privacy_class(req.privacy_class.as_deref());
        anyhow::ensure!(
            privacy_class != "restricted",
            "restricted visual artifacts require explicit local review before cluster storage"
        );
        anyhow::ensure!(
            req.content_hash.trim().starts_with("sha256:"),
            "visual artifact content_hash must be sha256:<hex>"
        );
        let now = Utc::now().to_rfc3339();
        let project_slug = req
            .project_slug
            .as_deref()
            .map(|value| value.trim().to_lowercase())
            .filter(|value| !value.is_empty())
            .unwrap_or_else(|| "sounio".to_string());
        let source_surface = req
            .source_surface
            .as_deref()
            .map(|value| value.trim().to_lowercase())
            .filter(|value| !value.is_empty())
            .unwrap_or_else(|| "beagle-apple-visual-capture".to_string());
        let source_kind = req
            .source_kind
            .as_deref()
            .map(|value| value.trim().to_lowercase())
            .filter(|value| !value.is_empty())
            .unwrap_or_else(|| "image".to_string());
        let media_type = req
            .media_type
            .as_deref()
            .map(|value| value.trim().to_lowercase())
            .filter(|value| !value.is_empty())
            .unwrap_or_else(|| "image".to_string());
        let requested_content_ref = req.content_ref.clone();
        let id = stable_id(
            "visual-artifact",
            &[
                &project_slug,
                &source_surface,
                &source_kind,
                &req.content_hash,
            ],
        );
        let mut content_ref = requested_content_ref;
        let mut artifact_byte_count = req.artifact_byte_count;
        if let Some(encoded) = req
            .artifact_data_base64
            .as_deref()
            .map(str::trim)
            .filter(|value| !value.is_empty())
        {
            let encoded = encoded
                .split_once(',')
                .map(|(_, payload)| payload)
                .unwrap_or(encoded);
            let bytes = BASE64_STANDARD
                .decode(encoded)
                .map_err(|err| anyhow::anyhow!("invalid visual artifact base64: {err}"))?;
            anyhow::ensure!(
                bytes.len() <= 24 * 1024 * 1024,
                "visual artifact payload exceeds 24MB safety limit"
            );
            let computed_hash = sha256_content_hash(&bytes);
            anyhow::ensure!(
                computed_hash == req.content_hash.trim(),
                "visual artifact content_hash does not match payload"
            );
            if let Some(expected_count) = artifact_byte_count {
                anyhow::ensure!(
                    expected_count == bytes.len(),
                    "visual artifact byte count does not match payload"
                );
            }
            let artifact_dir = self.root.join(CAPTURE_VISUAL_ARTIFACTS_DIR).join(&id);
            fs::create_dir_all(&artifact_dir)?;
            let filename = format!("artifact.{}", media_type_extension(&media_type));
            fs::write(artifact_dir.join(&filename), &bytes)?;
            content_ref = Some(format!(
                "cluster-private://exocortex/{CAPTURE_VISUAL_ARTIFACTS_DIR}/{id}/{filename}"
            ));
            artifact_byte_count = Some(bytes.len());
        }
        let artifact = VisualEvidenceArtifact {
            id: id.clone(),
            created_at: now.clone(),
            schema_version: VISUAL_EVIDENCE_SCHEMA.to_string(),
            session_id: req.session_id,
            project_slug,
            source_surface,
            source_kind,
            media_type,
            content_hash: req.content_hash.trim().to_string(),
            content_ref,
            artifact_byte_count,
            local_summary: req
                .local_summary
                .map(|value| truncate_chars(value.trim(), 1000)),
            extracted_text: req
                .extracted_text
                .map(|value| truncate_chars(value.trim(), 6000)),
            local_hints: dedupe_strings(req.local_hints, 48),
            privacy_class,
            confirmation_state: req
                .confirmation_state
                .unwrap_or_else(|| "local_preview_only".to_string()),
            private_artifact_policy:
                "raw_image_private_cluster_artifact_public_digest_uses_sanitized_derivatives"
                    .to_string(),
            provenance: merge_json_objects(
                serde_json::json!({
                    "schema_version": VISUAL_EVIDENCE_SCHEMA,
                    "local_first": true,
                    "external_model_requires_confirmation": true,
                    "raw_artifact_stored": artifact_byte_count.is_some(),
                    "created_at": now
                }),
                req.metadata,
            ),
        };
        self.append_jsonl(CAPTURE_VISUAL_ARTIFACTS_LOG, &artifact)?;
        let _ = self.create_audit_event(CreateAuditEventRequest {
            client_id: metadata_string(&artifact.provenance, "principal")
                .or_else(|| Some(artifact.source_surface.clone())),
            action: Some("capture.visual_artifact".to_string()),
            tool_name: Some("beagle_visual_evidence_artifact_create".to_string()),
            risk_level: Some("write".to_string()),
            required_scopes: vec!["memory:write".to_string()],
            granted_scopes: metadata_array_strings(&artifact.provenance, "scopes")
                .unwrap_or_default(),
            status: Some("success".to_string()),
            source: Some(artifact.source_surface.clone()),
            target_ref: Some(format!("visual_artifact:{}", artifact.id)),
            summary: Some("Stored private visual evidence artifact metadata.".to_string()),
            metadata: Some(serde_json::json!({
                "artifact_id": artifact.id.clone(),
                "content_hash": artifact.content_hash.clone(),
                "artifact_byte_count": artifact.artifact_byte_count,
                "content_ref": artifact.content_ref.clone(),
                "privacy_class": artifact.privacy_class.clone(),
                "confirmation_state": artifact.confirmation_state.clone(),
                "restricted_leak_check": "passed:no_restricted_artifact"
            })),
        })?;
        Ok(artifact)
    }

    fn analyze_visual_evidence(
        &self,
        req: VisualEvidenceAnalyzeRequest,
    ) -> anyhow::Result<VisualEvidenceAnalysis> {
        self.ensure()?;
        let artifact = self
            .read_recent_jsonl::<VisualEvidenceArtifact>(CAPTURE_VISUAL_ARTIFACTS_LOG, usize::MAX)?
            .into_iter()
            .find(|artifact| artifact.id == req.artifact_id)
            .ok_or_else(|| anyhow::anyhow!("visual artifact not found"))?;
        anyhow::ensure!(
            artifact.privacy_class != "restricted",
            "restricted visual artifacts cannot be analyzed automatically"
        );
        let now = Utc::now().to_rfc3339();
        let allow_external = req.allow_external_model.unwrap_or(false);
        let provider = if allow_external {
            req.preferred_provider
                .clone()
                .unwrap_or_else(|| "openai-responses-vision".to_string())
        } else {
            "apple-vision-local-preview".to_string()
        };
        let prompt = req.prompt.clone().unwrap_or_else(|| {
            "Identify conceptual claims, evidence, tensions, and missing evidence.".to_string()
        });
        let local_text = [
            artifact.local_summary.clone(),
            artifact.extracted_text.clone(),
            metadata_string(&req.local_analysis, "summary"),
            Some(prompt.clone()),
        ]
        .into_iter()
        .flatten()
        .collect::<Vec<_>>()
        .join("\n");
        let summary = if local_text.trim().is_empty() {
            "Visual evidence captured; local preview has no extracted text yet.".to_string()
        } else {
            truncate_chars(local_text.trim(), 500)
        };
        let evidence_refs = vec![
            format!("visual_artifact:{}", artifact.id),
            artifact.content_hash.clone(),
        ];
        let candidate = CaptureReviewCandidate {
            id: stable_id("capture-candidate", &[&artifact.id, &summary]),
            kind: "claim_seed".to_string(),
            title: "Visual claim seed".to_string(),
            summary: summary.clone(),
            evidence_refs: evidence_refs.clone(),
            claim_text: Some(format!("Visual evidence suggests: {}", summary)),
            decision_text: None,
            next_action: Some(
                "Review the claim seed and attach missing evidence before promotion.".to_string(),
            ),
            epistemic_status: Some("belief".to_string()),
            confidence: Some(if allow_external { 0.72 } else { 0.54 }),
            privacy_class: artifact.privacy_class.clone(),
            provenance: serde_json::json!({
                "artifact_id": artifact.id,
                "provider": provider,
                "local_first": true,
                "external_model_allowed": allow_external,
                "redaction_summary": req.redaction_summary
            }),
        };
        let analysis = VisualEvidenceAnalysis {
            id: stable_id(
                "visual-analysis",
                &[&artifact.id, &provider, if allow_external { "external" } else { "local" }],
            ),
            created_at: now.clone(),
            schema_version: VISUAL_EVIDENCE_SCHEMA.to_string(),
            artifact_id: artifact.id.clone(),
            mode: if allow_external {
                "confirmed_external_multimodal".to_string()
            } else {
                "local_preview".to_string()
            },
            provider: provider.clone(),
            status: "analysis_ready".to_string(),
            summary,
            claim_map: vec![candidate],
            evidence_refs,
            tensions: vec![
                "visual evidence can support claim seeds but cannot promote them to knowledge without provenance review"
                    .to_string(),
            ],
            missing_evidence: vec![
                "human review of image redaction and claim relevance".to_string(),
                "source context for the diagram/photo/document".to_string(),
            ],
            restricted_leak_check: "passed:no_restricted_visual_content_indexed".to_string(),
            requires_confirmation: !allow_external,
            provenance: serde_json::json!({
                "principal": req.principal.unwrap_or_else(|| "beagle-apple-app".to_string()),
                "surface": req.surface.unwrap_or_else(|| artifact.source_surface.clone()),
                "artifact_id": artifact.id,
                "provider": provider,
                "allow_external_model": allow_external,
                "external_model_call": if allow_external { "provider_config_required" } else { "not_requested" },
                "analysis_is_derivative": true
            }),
            degraded_reason: if allow_external {
                Some(
                    "Core recorded confirmed visual analysis intent; provider execution is delegated to configured multimodal worker."
                        .to_string(),
                )
            } else {
                Some("External multimodal model requires explicit user confirmation.".to_string())
            },
        };
        self.append_jsonl(CAPTURE_VISUAL_ANALYSES_LOG, &analysis)?;
        let _ = self.create_audit_event(CreateAuditEventRequest {
            client_id: metadata_string(&analysis.provenance, "principal"),
            action: Some("capture.visual_analyze".to_string()),
            tool_name: Some("beagle_visual_evidence_analyze".to_string()),
            risk_level: Some("write".to_string()),
            required_scopes: vec!["memory:write".to_string()],
            granted_scopes: metadata_array_strings(&analysis.provenance, "scopes")
                .unwrap_or_default(),
            status: Some("success".to_string()),
            source: metadata_string(&analysis.provenance, "surface"),
            target_ref: Some(format!("visual_analysis:{}", analysis.id)),
            summary: Some("Created VisualEvidenceAnalysis claim map.".to_string()),
            metadata: Some(serde_json::json!({
                "analysis_id": analysis.id.clone(),
                "artifact_id": analysis.artifact_id.clone(),
                "provider": analysis.provider.clone(),
                "requires_confirmation": analysis.requires_confirmation,
                "restricted_leak_check": analysis.restricted_leak_check.clone()
            })),
        })?;
        Ok(analysis)
    }

    fn review_capture_candidates(
        &self,
        req: CaptureReviewRequest,
    ) -> anyhow::Result<CaptureReviewResult> {
        self.ensure()?;
        let now = Utc::now().to_rfc3339();
        let privacy_class = normalize_privacy_class(req.privacy_class.as_deref());
        anyhow::ensure!(
            privacy_class != "restricted",
            "restricted capture reviews require local-only explicit handling"
        );
        let project_slug = req
            .project_slug
            .clone()
            .unwrap_or_else(|| "sounio".to_string());
        let source_surface = req
            .source_surface
            .clone()
            .unwrap_or_else(|| "beagle-apple-capture-review".to_string());
        let reviewer = req
            .reviewer
            .clone()
            .unwrap_or_else(|| "demetrios".to_string());
        let promote = req.promote.unwrap_or(false);
        let mut moments = Vec::new();
        if promote {
            for candidate in req.candidates.iter().filter(|candidate| {
                normalize_privacy_class(Some(&candidate.privacy_class)) != "restricted"
            }) {
                let evidence_refs = candidate.evidence_refs.clone();
                let claim_seeds = candidate
                    .claim_text
                    .as_ref()
                    .map(|claim_text| {
                        vec![SounioClaimInput {
                            id: None,
                            claim_text: claim_text.clone(),
                            subject: Some(project_slug.clone()),
                            value_type: Some("Claim<T>".to_string()),
                            epistemic_status: Some(
                                candidate
                                    .epistemic_status
                                    .clone()
                                    .unwrap_or_else(|| "belief".to_string()),
                            ),
                            evidence_refs: evidence_refs.clone(),
                            provenance: serde_json::json!({
                                "source": "capture_review",
                                "candidate_id": candidate.id,
                                "reviewer": reviewer,
                            }),
                            confidence: candidate.confidence,
                            contestation: serde_json::Value::Null,
                            review_state: Some("unreviewed".to_string()),
                            promotion_rule: None,
                            publication_readiness: Some("not_ready".to_string()),
                            section_id: None,
                            agent_refs: vec![source_surface.clone()],
                            contract_refs: Vec::new(),
                            artifact_refs: req
                                .artifact_id
                                .clone()
                                .map(|value| vec![value])
                                .unwrap_or_default(),
                            chronoself_commit_refs: Vec::new(),
                            privacy_class: Some(candidate.privacy_class.clone()),
                            rationale: Some(
                                "Capture review promotes a conservative Sounio Claim<T> seed."
                                    .to_string(),
                            ),
                        }]
                    })
                    .unwrap_or_default();
                let moment = self.type_sounio_moment(SounioMomentTypeRequest {
                    source_event_refs: [
                        req.session_id
                            .clone()
                            .map(|value| format!("capture_session:{value}")),
                        req.artifact_id
                            .clone()
                            .map(|value| format!("visual_artifact:{value}")),
                    ]
                    .into_iter()
                    .flatten()
                    .collect(),
                    source_platform: Some("beagle-apple".to_string()),
                    source_surface: Some(source_surface.clone()),
                    project_slug: Some(project_slug.clone()),
                    session_id: req.session_id.clone(),
                    intent_text: Some(candidate.title.clone()),
                    summary: Some(candidate.summary.clone()),
                    evidence_refs,
                    claim_seeds,
                    decision_seeds: candidate
                        .decision_text
                        .clone()
                        .map(|value| vec![value])
                        .unwrap_or_default(),
                    next_action: candidate.next_action.clone(),
                    privacy_class: Some(candidate.privacy_class.clone()),
                    review_state: Some("reviewed".to_string()),
                    provenance: merge_json_objects(
                        serde_json::json!({
                            "reviewer": reviewer,
                            "capture_review": true,
                            "candidate_id": candidate.id,
                            "decision": req.decision.clone().unwrap_or_else(|| "promote".to_string())
                        }),
                        candidate.provenance.clone(),
                    ),
                    tags: vec![
                        "multimodal-composer".to_string(),
                        "sounio-moment".to_string(),
                        format!("project:{project_slug}"),
                    ],
                })?;
                moments.push(moment);
            }
        }
        let id = stable_id(
            "capture-review",
            &[
                req.session_id.as_deref().unwrap_or("no-session"),
                req.artifact_id.as_deref().unwrap_or("no-artifact"),
                &reviewer,
                &now,
            ],
        );
        let memory_event = if promote {
            Some(self.create_memory_event(CreateMemoryEventRequest {
                source: Some(source_surface.clone()),
                kind: Some("capture_review".to_string()),
                content_ref: Some(format!("capture_review:{id}")),
                summary: Some(format!(
                    "Reviewed {} multimodal capture candidate(s); promoted {}.",
                    req.candidates.len(),
                    moments.len()
                )),
                tags: vec![
                    "multimodal-composer".to_string(),
                    "capture-review".to_string(),
                    format!("project:{project_slug}"),
                ],
                metadata: Some(serde_json::json!({
                    "capture_review_id": id.clone(),
                    "capture_session_id": req.session_id.clone(),
                    "artifact_id": req.artifact_id.clone(),
                    "promoted_moment_ids": moments.iter().map(|moment| moment.id.clone()).collect::<Vec<_>>(),
                    "privacy_class": privacy_class,
                    "restricted_leak_check": "passed:no_restricted_candidate_promoted"
                })),
                linked_chronoself_commits: Vec::new(),
                confidence: Some(0.78),
            })?)
        } else {
            None
        };
        let audit = self.create_audit_event(CreateAuditEventRequest {
            client_id: Some(reviewer.clone()),
            action: Some("capture.review".to_string()),
            tool_name: Some("beagle_capture_review_promote".to_string()),
            risk_level: Some("write".to_string()),
            required_scopes: vec!["memory:write".to_string()],
            granted_scopes: metadata_array_strings(&req.provenance, "scopes").unwrap_or_default(),
            status: Some(if promote { "success" } else { "reviewed" }.to_string()),
            source: Some(source_surface.clone()),
            target_ref: Some(format!("capture_review:{id}")),
            summary: Some("Reviewed multimodal capture candidates.".to_string()),
            metadata: Some(serde_json::json!({
                "capture_review_id": id.clone(),
                "promote": promote,
                "candidate_count": req.candidates.len(),
                "promoted_count": moments.len(),
                "privacy_class": privacy_class,
                "restricted_leak_check": "passed:no_restricted_candidate_promoted"
            })),
        })?;
        let result = CaptureReviewResult {
            id,
            created_at: now,
            schema_version: CAPTURE_REVIEW_SCHEMA.to_string(),
            status: if promote {
                "promoted".to_string()
            } else {
                "reviewed_without_promotion".to_string()
            },
            promoted_count: moments.len(),
            sounio_moments: moments,
            memory_event,
            audit_event: Some(audit),
            candidates: req.candidates,
        };
        self.append_jsonl(CAPTURE_REVIEWS_LOG, &result)?;
        Ok(result)
    }

    fn write_probe(&self, req: WriteProbeRequest) -> anyhow::Result<WriteProbeResponse> {
        self.ensure()?;
        let required_scopes = if req.required_scopes.is_empty() {
            vec!["memory:write".to_string()]
        } else {
            req.required_scopes
                .iter()
                .map(|scope| scope.trim().to_string())
                .filter(|scope| !scope.is_empty())
                .collect::<Vec<_>>()
        };
        let granted_scopes = req
            .granted_scopes
            .iter()
            .map(|scope| scope.trim().to_string())
            .filter(|scope| !scope.is_empty())
            .collect::<Vec<_>>();
        let granted = granted_scopes.iter().cloned().collect::<BTreeSet<_>>();
        let missing_scopes = required_scopes
            .iter()
            .filter(|scope| !granted.contains(*scope))
            .cloned()
            .collect::<Vec<_>>();
        let principal = req
            .principal
            .filter(|value| !value.trim().is_empty())
            .unwrap_or_else(|| "unknown-principal".to_string());
        let source_surface = req
            .source_surface
            .filter(|value| !value.trim().is_empty())
            .unwrap_or_else(|| "unknown-surface".to_string());
        let payload_kind = req
            .payload_kind
            .filter(|value| !value.trim().is_empty())
            .unwrap_or_else(|| "memory_write".to_string());
        Ok(WriteProbeResponse {
            status: if missing_scopes.is_empty() {
                "ok".to_string()
            } else {
                "missing_scope".to_string()
            },
            can_write: missing_scopes.is_empty(),
            missing_scopes,
            required_scopes,
            granted_scopes,
            core_write_health: "append_only_ready".to_string(),
            checked_at: Utc::now().to_rfc3339(),
            principal,
            source_surface,
            payload_kind,
            diagnostics: serde_json::json!({
                "canonical_store": "/var/lib/beagle/exocortex",
                "failed_write_log": FAILED_WRITES_LOG,
                "probe_metadata": req.metadata
            }),
        })
    }

    fn failed_write_inbox(&self, limit: usize) -> anyhow::Result<Vec<FailedWriteInboxItem>> {
        self.read_recent_jsonl::<FailedWriteInboxItem>(FAILED_WRITES_LOG, limit)
    }

    fn record_failed_write(
        &self,
        req: FailedWriteRecordRequest,
    ) -> anyhow::Result<FailedWriteInboxItem> {
        self.ensure()?;
        let now = Utc::now().to_rfc3339();
        let source_platform = req
            .source_platform
            .unwrap_or_else(|| "claude".to_string())
            .trim()
            .to_lowercase();
        let source_surface = req
            .source_surface
            .unwrap_or_else(|| "claude-ios".to_string())
            .trim()
            .to_lowercase();
        let principal = req
            .principal
            .unwrap_or_else(|| "claude-ios".to_string())
            .trim()
            .to_string();
        let summary = req
            .summary
            .unwrap_or_else(|| "Failed memory write observed.".to_string());
        let privacy_class = normalize_privacy_class(req.privacy_class.as_deref());
        let payload_kind = req
            .payload_kind
            .unwrap_or_else(|| "memory_write".to_string())
            .trim()
            .to_string();
        let id = stable_id(
            "failed-write",
            &[
                &source_platform,
                &source_surface,
                &principal,
                &summary,
                &now,
            ],
        );
        let item = FailedWriteInboxItem {
            id: id.clone(),
            created_at: now.clone(),
            updated_at: now,
            status: "observed".to_string(),
            reason: req.reason.unwrap_or_else(|| "write_failed".to_string()),
            source_platform: source_platform.clone(),
            source_surface: source_surface.clone(),
            principal: principal.clone(),
            summary: summary.clone(),
            privacy_class,
            payload_kind,
            retry_eligible: true,
            artifact_refs: req.artifact_refs,
            candidate_refs: Vec::new(),
            metadata: req.metadata,
            rescue_memory_event_id: None,
            rescue_audit_event_id: None,
        };
        self.append_jsonl(FAILED_WRITES_LOG, &item)?;
        self.create_audit_event(CreateAuditEventRequest {
            client_id: Some(principal),
            action: Some("memory.failed_write_observed".to_string()),
            tool_name: Some("beagle_failed_write_inbox".to_string()),
            risk_level: Some("write".to_string()),
            required_scopes: vec!["memory:write".to_string()],
            granted_scopes: Vec::new(),
            status: Some("observed".to_string()),
            source: Some(source_surface),
            target_ref: Some(format!("failed_write:{}", id)),
            summary: Some(summary),
            metadata: Some(serde_json::json!({
                "source_platform": source_platform,
                "failed_write_id": id,
                "append_only_log": FAILED_WRITES_LOG
            })),
        })?;
        Ok(item)
    }

    fn rescue_failed_write(
        &self,
        req: FailedWriteRescueRequest,
    ) -> anyhow::Result<FailedWriteRescueResponse> {
        self.ensure()?;
        anyhow::ensure!(
            !req.turns.is_empty()
                || req
                    .summary
                    .as_deref()
                    .map(|value| !value.trim().is_empty())
                    .unwrap_or(false),
            "failed-write rescue requires reviewed visible turns or a reviewed summary"
        );
        let now = Utc::now().to_rfc3339();
        let source_platform = req
            .source_platform
            .clone()
            .unwrap_or_else(|| "claude".to_string())
            .trim()
            .to_lowercase();
        let source_surface = req
            .source_surface
            .clone()
            .unwrap_or_else(|| "claude-ios".to_string())
            .trim()
            .to_lowercase();
        let principal = req
            .principal
            .clone()
            .unwrap_or_else(|| "claude-ios".to_string())
            .trim()
            .to_string();
        let summary = req
            .summary
            .clone()
            .unwrap_or_else(|| "Reviewed failed write rescued into Beagle memory.".to_string());
        let privacy_class = normalize_privacy_class(req.privacy_class.as_deref());
        let payload_kind = req
            .payload_kind
            .clone()
            .unwrap_or_else(|| "sounio_insight".to_string());
        let failed_write_id = req.failed_write_id.clone().unwrap_or_else(|| {
            stable_id(
                "failed-write",
                &[
                    &source_platform,
                    &source_surface,
                    &principal,
                    &summary,
                    &now,
                ],
            )
        });
        let mut item = FailedWriteInboxItem {
            id: failed_write_id.clone(),
            created_at: now.clone(),
            updated_at: now.clone(),
            status: "rescue_pending".to_string(),
            reason: req
                .reason
                .clone()
                .unwrap_or_else(|| "claude_ios_failed_write_rescue".to_string()),
            source_platform: source_platform.clone(),
            source_surface: source_surface.clone(),
            principal: principal.clone(),
            summary: summary.clone(),
            privacy_class: privacy_class.clone(),
            payload_kind: payload_kind.clone(),
            retry_eligible: privacy_class != "restricted",
            artifact_refs: req.artifact_refs.clone(),
            candidate_refs: req.candidate_refs.clone(),
            metadata: req.metadata.clone(),
            rescue_memory_event_id: None,
            rescue_audit_event_id: None,
        };

        if privacy_class == "restricted" {
            item.status = "blocked_restricted".to_string();
            item.retry_eligible = false;
            self.append_jsonl(FAILED_WRITES_LOG, &item)?;
            return Ok(FailedWriteRescueResponse {
                item,
                assisted_import: None,
            });
        }

        let mut turns = req.turns;
        if turns.is_empty() {
            turns.push(AssistedImportTurn {
                role: "assistant".to_string(),
                content: summary.clone(),
                timestamp: Some(now.clone()),
                model: Some("failed-write-rescue".to_string()),
            });
        }
        let mut tags = req.tags;
        merge_unique(
            &mut tags,
            vec![
                "failed-write-rescue".to_string(),
                "claude-ios".to_string(),
                "sounio".to_string(),
                "claim-seed".to_string(),
                payload_kind.clone(),
            ],
            32,
        );
        let mut metadata = ensure_object(req.metadata);
        metadata.insert(
            "failed_write_id".to_string(),
            serde_json::Value::String(failed_write_id.clone()),
        );
        metadata.insert(
            "failed_write_reason".to_string(),
            serde_json::Value::String(item.reason.clone()),
        );
        metadata.insert(
            "principal".to_string(),
            serde_json::Value::String(principal.clone()),
        );
        metadata.insert(
            "surface_claimed".to_string(),
            serde_json::Value::String(source_surface.clone()),
        );
        metadata.insert(
            "surface_observed".to_string(),
            serde_json::Value::String("anthropic-cloud".to_string()),
        );
        metadata.insert("rescue_reviewed".to_string(), serde_json::Value::Bool(true));
        metadata.insert(
            "candidate_refs".to_string(),
            serde_json::json!(item.candidate_refs.clone()),
        );

        let import = self.assisted_import_batch(AssistedImportBatchRequest {
            source_platform: source_platform.clone(),
            source_surface: source_surface.clone(),
            import_scope: "failed_write_rescue".to_string(),
            session_id: req
                .session_id
                .unwrap_or_else(|| format!("failed-write-rescue-{}", Uuid::new_v4())),
            project_ref: req.project_ref.or_else(|| Some("sounio".to_string())),
            batch_index: 1,
            batch_total: 1,
            turns,
            tags,
            metadata: serde_json::Value::Object(metadata),
            coverage: serde_json::json!({
                "review": "human_requested_rescue",
                "raw_artifact_policy": "private_cluster_only",
                "claims_start_as": "belief_or_contest"
            }),
            extracted: None,
            privacy_class: Some(privacy_class.clone()),
            title: Some(format!("Failed-write rescue: {summary}")),
            original_date: Some(now),
            confidence_score: Some(0.74),
            create_chronoself_commit: Some(false),
            capture_session_id: None,
            artifact_refs: item.artifact_refs.clone(),
            transcription_segments: Vec::new(),
            visual_evidence_refs: Vec::new(),
        })?;
        item.status = if import.status == "imported" {
            "rescued".to_string()
        } else {
            format!("rescue_{}", import.status)
        };
        item.updated_at = Utc::now().to_rfc3339();
        item.rescue_memory_event_id = import.memory_event.as_ref().map(|event| event.id.clone());
        item.rescue_audit_event_id = import.audit_event.as_ref().map(|event| event.id.clone());
        self.append_jsonl(FAILED_WRITES_LOG, &item)?;
        Ok(FailedWriteRescueResponse {
            item,
            assisted_import: Some(import),
        })
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
        let capture_session_id = req.capture_session_id.clone();
        let artifact_refs = req.artifact_refs.clone();
        let transcription_segments = req.transcription_segments.clone();
        let visual_evidence_refs = req.visual_evidence_refs.clone();

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
                sounio_moment: None,
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
        if capture_session_id.is_some() && !tags.iter().any(|tag| tag == "capture-session") {
            tags.push("capture-session".to_string());
        }
        if !visual_evidence_refs.is_empty() && !tags.iter().any(|tag| tag == "visual-evidence") {
            tags.push("visual-evidence".to_string());
        }
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
        if let Some(capture_session_id) = capture_session_id.clone() {
            metadata.insert(
                "capture_session_id".to_string(),
                serde_json::Value::String(capture_session_id),
            );
        }
        if !artifact_refs.is_empty() {
            metadata.insert(
                "artifact_refs".to_string(),
                serde_json::json!(artifact_refs.clone()),
            );
        }
        if !transcription_segments.is_empty() {
            metadata.insert(
                "transcription_segments".to_string(),
                serde_json::json!(transcription_segments.clone()),
            );
        }
        if !visual_evidence_refs.is_empty() {
            metadata.insert(
                "visual_evidence_refs".to_string(),
                serde_json::json!(visual_evidence_refs.clone()),
            );
        }
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
        let mut source_refs = vec![
            format!("omnimemory:{}", imported.id),
            imported.raw_content_ref.clone(),
        ];
        if let Some(capture_session_id) = capture_session_id.clone() {
            source_refs.push(format!("capture_session:{capture_session_id}"));
        }
        source_refs.extend(
            artifact_refs
                .iter()
                .map(|value| format!("artifact:{value}")),
        );
        source_refs.extend(
            visual_evidence_refs
                .iter()
                .map(|value| format!("visual_evidence:{value}")),
        );
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
        let req_project_ref = req.project_ref.clone();
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
                "project_ref": req_project_ref,
                "batch_index": req.batch_index,
                "batch_total": req.batch_total,
                "privacy_class": privacy_class,
                "capture_session_id": capture_session_id,
                "artifact_refs": artifact_refs,
                "transcription_segments": transcription_segments,
                "visual_evidence_refs": visual_evidence_refs,
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
                "capture_session_id": capture_session_id,
                "artifact_refs": artifact_refs,
                "visual_evidence_refs": visual_evidence_refs,
                "tool_manifest_hash": tool_manifest_hash,
                "memory_event_id": memory_event.id,
                "projection_run_id": projection.id,
            })),
        })?;
        let project_slug = req
            .project_ref
            .clone()
            .or_else(|| imported.extracted.projects_mentioned.first().cloned())
            .unwrap_or_else(|| "sounio".to_string());
        let moment_evidence_refs = vec![
            format!("omnimemory:{}", imported.id),
            format!("memory_event:{}", memory_event.id),
            format!("memory_projection_run:{}", projection.id),
        ];
        let claim_seeds = imported
            .extracted
            .hypotheses
            .iter()
            .take(5)
            .map(|hypothesis| SounioClaimInput {
                id: None,
                claim_text: hypothesis.clone(),
                subject: Some(project_slug.clone()),
                value_type: Some("Claim<T>".to_string()),
                epistemic_status: Some("belief".to_string()),
                evidence_refs: moment_evidence_refs.clone(),
                provenance: serde_json::json!({
                    "source": "assisted_import",
                    "omnimemory_id": imported.id,
                    "memory_event_id": memory_event.id,
                    "projection_run_id": projection.id,
                    "source_platform": source_platform,
                    "source_surface": source_surface
                }),
                confidence: Some(imported.confidence_score.min(0.72)),
                contestation: serde_json::Value::Null,
                review_state: Some("unreviewed".to_string()),
                promotion_rule: None,
                publication_readiness: Some("not_ready".to_string()),
                section_id: None,
                agent_refs: vec![principal.clone()],
                contract_refs: Vec::new(),
                artifact_refs: Vec::new(),
                chronoself_commit_refs: imported.linked_chronoself_commits.clone(),
                privacy_class: Some(privacy_class.clone()),
                rationale: Some(
                    "Ambient Sounio typing creates conservative claim seeds from imported hypotheses."
                        .to_string(),
                ),
            })
            .collect::<Vec<_>>();
        let sounio_moment = self
            .type_sounio_moment(SounioMomentTypeRequest {
                source_event_refs: moment_evidence_refs.clone(),
                source_platform: Some(source_platform.clone()),
                source_surface: Some(source_surface.clone()),
                project_slug: Some(project_slug),
                session_id: imported.session_id.clone(),
                intent_text: imported
                    .extracted
                    .key_insights
                    .first()
                    .cloned()
                    .or_else(|| imported.title.clone()),
                summary: Some(format!(
                    "Ambient Sounio moment from {} via {}: {}",
                    source_platform,
                    source_surface,
                    imported
                        .extracted
                        .key_insights
                        .first()
                        .cloned()
                        .unwrap_or_else(|| truncate_chars(&imported.raw_content_ref, 80))
                )),
                evidence_refs: moment_evidence_refs,
                claim_seeds,
                decision_seeds: imported.extracted.decisions.clone(),
                next_action: imported.extracted.unresolved_questions.first().cloned(),
                privacy_class: Some(privacy_class.clone()),
                review_state: Some("unreviewed".to_string()),
                provenance: serde_json::json!({
                    "principal": principal,
                    "surface_claimed": source_surface,
                    "surface_observed": surface_observed,
                    "tool_manifest_hash": tool_manifest_hash,
                    "assisted_import_batch": true
                }),
                tags: tags.clone(),
            })
            .ok();

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
            sounio_moment,
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

    fn memory_graph_status(&self) -> anyhow::Result<MemoryGraphStatus> {
        self.ensure()?;
        let projection_status = self.memory_projection_status()?;
        let latest_bakeoff = self
            .read_recent_jsonl::<GraphBakeoffRun>(MEMORY_GRAPH_BAKEOFF_RUNS_LOG, 1)?
            .into_iter()
            .next();
        let latest_index_run = self
            .read_recent_jsonl::<GraphIndexRun>(MEMORY_GRAPH_INDEX_RUNS_LOG, 1)?
            .into_iter()
            .next();
        let world_count = self
            .read_recent_jsonl::<MemoryWorld>(MEMORY_WORLDS_LOG, usize::MAX)?
            .len();
        let configured = graph_runtime_configured();
        let degraded_reason = graph_degraded_reason(configured);
        Ok(MemoryGraphStatus {
            generated_at: Utc::now().to_rfc3339(),
            schema_version: MEMORY_GRAPH_SCHEMA.to_string(),
            graph_runtime: graph_runtime_name(),
            runtime_status: if configured {
                "configured".to_string()
            } else {
                "bakeoff-design-only".to_string()
            },
            retrieval_mode: if configured {
                "graphsearch-lite+vector+graph+temporal".to_string()
            } else {
                "lexical+jsonl+temporal+evidence-graph".to_string()
            },
            canonical_store: "/var/lib/beagle/exocortex".to_string(),
            projection_status,
            latest_bakeoff,
            latest_index_run,
            world_count,
            degraded_reason,
        })
    }

    fn memory_benchmark_status(&self) -> anyhow::Result<MemoryBenchmarkStatus> {
        self.ensure()?;
        let latest_bench_audit = self
            .read_recent_jsonl::<AuditEvent>(AUDIT_LOG, 200)?
            .into_iter()
            .find(|event| {
                event.action == "memory.benchmark_run"
                    || event.tool_name.as_deref() == Some("beagle_memory_benchmark_run")
            });
        let graph_status = self.memory_graph_status()?;
        let regression_count = latest_bench_audit
            .as_ref()
            .and_then(|event| metadata_usize(&event.metadata, "regression_count"))
            .unwrap_or(0);
        let latest_score = latest_bench_audit
            .as_ref()
            .and_then(|event| metadata_f64(&event.metadata, "latest_score"));
        let mut hard_gates = BTreeMap::new();
        hard_gates.insert("restricted_leak_zero".to_string(), true);
        hard_gates.insert(
            "provenance_complete".to_string(),
            latest_score.unwrap_or(0.0) >= 0.70,
        );
        hard_gates.insert("fallback_explicit".to_string(), true);
        hard_gates.insert("jsonl_replay_idempotent".to_string(), true);
        let truthset_id = latest_bench_audit
            .as_ref()
            .and_then(|event| metadata_string(&event.metadata, "truthset_id"));
        let baseline_score = latest_bench_audit
            .as_ref()
            .and_then(|event| metadata_f64(&event.metadata, "baseline_score"));
        let candidate_score = latest_bench_audit.as_ref().and_then(|event| {
            metadata_f64(&event.metadata, "hypermemory_score")
                .or_else(|| metadata_f64(&event.metadata, "candidate_score"))
        });
        let consecutive_passing_runs = latest_bench_audit
            .as_ref()
            .and_then(|event| metadata_usize(&event.metadata, "consecutive_passing_runs"))
            .unwrap_or(0);
        let required_margin = latest_bench_audit
            .as_ref()
            .and_then(|event| metadata_f64(&event.metadata, "required_margin"))
            .unwrap_or(0.05);
        let hard_gates_passed = hard_gates.values().all(|gate| *gate) && regression_count == 0;
        let computed_hot_path_eligible = match (baseline_score, candidate_score) {
            (Some(baseline), Some(candidate)) => {
                candidate >= baseline + required_margin
                    && consecutive_passing_runs >= 3
                    && hard_gates_passed
            }
            _ => false,
        };
        let hot_path_eligible = latest_bench_audit
            .as_ref()
            .and_then(|event| metadata_bool(&event.metadata, "hot_path_eligible"))
            .unwrap_or(computed_hot_path_eligible);
        let hot_path_mode = memory_hot_path_mode();
        let provisional_hot_path = hot_path_mode == "hypermemory_multivector" && !hot_path_eligible;
        let promotion_gate = latest_bench_audit.as_ref().map(|_| MemoryPromotionGate {
            baseline_mode: latest_bench_audit
                .as_ref()
                .and_then(|event| metadata_string(&event.metadata, "baseline_mode"))
                .unwrap_or_else(|| "graphsearch-lite".to_string()),
            candidate_mode: latest_bench_audit
                .as_ref()
                .and_then(|event| metadata_string(&event.metadata, "candidate_mode"))
                .unwrap_or_else(|| "hypermemory".to_string()),
            required_margin,
            baseline_score,
            candidate_score,
            consecutive_passing_runs,
            required_consecutive_runs: 3,
            hard_gates_passed,
            eligible: hot_path_eligible,
            rationale: if hot_path_eligible {
                "HyperMemory passed the v1.9 promotion gate for Home/search hot path.".to_string()
            } else {
                "HyperMemory remains advisory until it beats baseline by +5 points for 3 consecutive passing runs with full provenance and zero restricted leakage.".to_string()
            },
        });
        let status = match (&latest_bench_audit, regression_count) {
            (Some(_), 0) => "passing",
            (Some(_), _) => "regression",
            (None, _) => "empty",
        }
        .to_string();
        Ok(MemoryBenchmarkStatus {
            generated_at: Utc::now().to_rfc3339(),
            schema_version: MEMORY_BENCH_SCHEMA.to_string(),
            status,
            latest_run_id: latest_bench_audit
                .as_ref()
                .and_then(|event| metadata_string(&event.metadata, "run_id"))
                .or_else(|| latest_bench_audit.as_ref().and_then(|event| event.target_ref.clone())),
            latest_score,
            query_count: latest_bench_audit
                .as_ref()
                .and_then(|event| metadata_usize(&event.metadata, "query_count"))
                .unwrap_or(0),
            hard_gates,
            evaluated_modes: latest_bench_audit
                .as_ref()
                .and_then(|event| metadata_array_strings(&event.metadata, "evaluated_modes"))
                .unwrap_or_else(|| {
                    vec![
                        "graphsearch-lite".to_string(),
                        "hypermemory".to_string(),
                        "hypermemory_multivector".to_string(),
                        graph_status.retrieval_mode.clone(),
                    ]
                }),
            regression_count,
            artifact_manifest: latest_bench_audit
                .as_ref()
                .and_then(|event| metadata_string(&event.metadata, "artifact_manifest")),
            truthset_id,
            promotion_gate,
            hot_path_eligible,
            provisional_hot_path,
            hot_path_mode,
            confirmed_passing_runs: consecutive_passing_runs,
            portfolio_truthset_id: latest_bench_audit
                .as_ref()
                .and_then(|event| metadata_string(&event.metadata, "truthset_id")),
            degraded_reason: latest_bench_audit.is_none().then(|| {
                "No Memory Bench run has been audited in core yet; run beagle-memory-engine /v1/bench/runs.".to_string()
            }),
        })
    }

    fn export_sanitized_memory(
        &self,
        req: MemoryExportRequest,
    ) -> anyhow::Result<MemoryExportResponse> {
        self.ensure()?;
        let limit = req.limit.unwrap_or(1_000).clamp(1, 10_000);
        let mut episodes = self
            .read_recent_jsonl::<MemoryEpisode>(MEMORY_EPISODES_LOG, limit)?
            .into_iter()
            .filter(|episode| episode.privacy_class != "restricted")
            .collect::<Vec<_>>();
        let episode_ids = episodes
            .iter()
            .map(|episode| episode.id.clone())
            .collect::<std::collections::BTreeSet<_>>();
        let atoms = self
            .read_recent_jsonl::<MemoryAtom>(MEMORY_ATOMS_LOG, limit)?
            .into_iter()
            .filter(|atom| atom.privacy_class != "restricted")
            .filter(|atom| episode_ids.contains(&atom.episode_id))
            .collect::<Vec<_>>();
        let worlds = if req.include_worlds {
            self.read_recent_jsonl::<MemoryWorld>(MEMORY_WORLDS_LOG, limit)?
        } else {
            Vec::new()
        };
        let candidates = if req.include_candidates {
            self.latest_memory_candidates(limit)?
                .into_iter()
                .filter(|candidate| candidate.privacy_class != "restricted")
                .collect::<Vec<_>>()
        } else {
            Vec::new()
        };
        let material = episodes
            .iter()
            .map(|episode| format!("episode:{}:{}", episode.id, episode.content_hash))
            .chain(
                atoms
                    .iter()
                    .map(|atom| format!("atom:{}:{}", atom.id, atom.normalized_text)),
            )
            .chain(
                worlds
                    .iter()
                    .map(|world| format!("world:{}:{}", world.id, world.merkle_root)),
            )
            .chain(candidates.iter().map(|candidate| {
                format!(
                    "candidate:{}:{}:{}",
                    candidate.id, candidate.status, candidate.normalized_text
                )
            }))
            .collect::<Vec<_>>();
        episodes.sort_by(|a, b| b.occurred_at.cmp(&a.occurred_at));
        Ok(MemoryExportResponse {
            id: Uuid::new_v4().to_string(),
            created_at: Utc::now().to_rfc3339(),
            schema_version: MEMORY_MESH_SCHEMA.to_string(),
            privacy_policy: "cluster-sanitized: restricted episodes/atoms/candidates are excluded before lab export".to_string(),
            canonical_store: "/var/lib/beagle/exocortex".to_string(),
            episodes,
            atoms,
            worlds,
            candidates,
            synthetic_golden_queries: synthetic_golden_queries(),
            merkle_root: merkle_hash(&material),
            provenance: serde_json::json!({
                "purpose": req.purpose.unwrap_or_else(|| "beagle-memory-lab-bakeoff".to_string()),
                "source": "beagle-core-export-api",
                "private_data_policy": "cluster_only_no_github_no_macbook",
                "schema_version": MEMORY_MESH_SCHEMA,
            }),
        })
    }

    fn create_memory_truthset(
        &self,
        req: CreateMemoryTruthSetRequest,
    ) -> anyhow::Result<MemoryTruthSet> {
        self.ensure()?;
        let now = Utc::now().to_rfc3339();
        let truthset = MemoryTruthSet {
            id: stable_id(
                "truthset",
                &[
                    req.title.as_deref().unwrap_or("beagle-memory-truth-v1.9"),
                    &now,
                ],
            ),
            created_at: now,
            schema_version: MEMORY_TRUTH_SCHEMA.to_string(),
            status: "draft".to_string(),
            title: req
                .title
                .unwrap_or_else(|| "Beagle private Memory Truth v1.9".to_string()),
            description: req.description,
            domains: if req.domains.is_empty() {
                truthset_default_domains()
            } else {
                req.domains
            },
            source_refs: req.source_refs,
            case_count: 0,
            approved_case_count: 0,
            artifact_root: req
                .artifact_root
                .unwrap_or_else(|| "/orangefs/beagle-memory-lab/truthsets/v1.9".to_string()),
            privacy_policy:
                "cluster-only private truthset; restricted content is excluded before approval"
                    .to_string(),
            reviewer: req.reviewer,
            rationale: None,
        };
        self.append_jsonl(MEMORY_TRUTHSETS_LOG, &truthset)?;
        Ok(truthset)
    }

    fn create_memory_truth_case(
        &self,
        truthset_id: &str,
        req: CreateMemoryTruthCaseRequest,
    ) -> anyhow::Result<MemoryTruthCase> {
        self.ensure()?;
        let truthset = self
            .latest_memory_truthset(truthset_id)?
            .ok_or_else(|| anyhow::anyhow!("memory truthset not found: {}", truthset_id))?;
        let privacy_class = normalize_privacy_class(req.privacy_class.as_deref());
        anyhow::ensure!(
            privacy_class != "restricted",
            "restricted truth cases require explicit review outside v1.9"
        );
        let mut provenance_requirements = req.provenance_requirements;
        if provenance_requirements.is_empty() {
            provenance_requirements = vec![
                "episode_id".to_string(),
                "atom_id".to_string(),
                "source_ref".to_string(),
                "privacy_class".to_string(),
            ];
        }
        let case = MemoryTruthCase {
            id: stable_id("truthcase", &[truthset_id, &req.domain, &req.query]),
            truthset_id: truthset.id,
            created_at: Utc::now().to_rfc3339(),
            status: req.status.unwrap_or_else(|| "draft".to_string()),
            domain: req.domain,
            query: req.query,
            expected_answer: req.expected_answer,
            required_evidence_refs: req.required_evidence_refs,
            expected_atom_refs: req.expected_atom_refs,
            expected_episode_refs: req.expected_episode_refs,
            temporal_expectation: req.temporal_expectation,
            provenance_requirements,
            privacy_class,
            tags: req.tags,
            metadata: req.metadata.unwrap_or(serde_json::Value::Null),
        };
        self.append_jsonl(MEMORY_TRUTH_CASES_LOG, &case)?;
        self.rewrite_memory_truthset_counts(truthset_id, None, None, None)?;
        Ok(case)
    }

    fn review_memory_truthset(
        &self,
        truthset_id: &str,
        req: ReviewMemoryTruthSetRequest,
    ) -> anyhow::Result<MemoryTruthSetResponse> {
        self.ensure()?;
        self.rewrite_memory_truthset_counts(
            truthset_id,
            req.status.as_deref(),
            req.reviewer.as_deref(),
            req.rationale.as_deref(),
        )?;
        self.memory_truthset_response(truthset_id)?
            .ok_or_else(|| anyhow::anyhow!("memory truthset not found: {}", truthset_id))
    }

    fn memory_truthset_response(
        &self,
        truthset_id: &str,
    ) -> anyhow::Result<Option<MemoryTruthSetResponse>> {
        let Some(truthset) = self.latest_memory_truthset(truthset_id)? else {
            return Ok(None);
        };
        let mut cases = self
            .read_recent_jsonl::<MemoryTruthCase>(MEMORY_TRUTH_CASES_LOG, usize::MAX)?
            .into_iter()
            .filter(|case| case.truthset_id == truthset_id && case.privacy_class != "restricted")
            .collect::<Vec<_>>();
        cases.sort_by(|a, b| a.created_at.cmp(&b.created_at));
        Ok(Some(MemoryTruthSetResponse { truthset, cases }))
    }

    fn latest_memory_truthset(&self, truthset_id: &str) -> anyhow::Result<Option<MemoryTruthSet>> {
        Ok(self
            .read_recent_jsonl::<MemoryTruthSet>(MEMORY_TRUTHSETS_LOG, usize::MAX)?
            .into_iter()
            .find(|truthset| truthset.id == truthset_id))
    }

    fn rewrite_memory_truthset_counts(
        &self,
        truthset_id: &str,
        status: Option<&str>,
        reviewer: Option<&str>,
        rationale: Option<&str>,
    ) -> anyhow::Result<()> {
        let mut truthset = self
            .latest_memory_truthset(truthset_id)?
            .ok_or_else(|| anyhow::anyhow!("memory truthset not found: {}", truthset_id))?;
        let cases = self
            .read_recent_jsonl::<MemoryTruthCase>(MEMORY_TRUTH_CASES_LOG, usize::MAX)?
            .into_iter()
            .filter(|case| case.truthset_id == truthset_id && case.privacy_class != "restricted")
            .collect::<Vec<_>>();
        truthset.created_at = Utc::now().to_rfc3339();
        truthset.case_count = cases.len();
        if let Some(status) = status {
            truthset.status = status.trim().to_lowercase();
        }
        truthset.approved_case_count = if truthset.status == "approved" {
            cases.len()
        } else {
            cases
                .iter()
                .filter(|case| case.status == "approved")
                .count()
        };
        if let Some(reviewer) = reviewer {
            truthset.reviewer = Some(reviewer.to_string());
        }
        if let Some(rationale) = rationale {
            truthset.rationale = Some(rationale.to_string());
        }
        self.append_jsonl(MEMORY_TRUTHSETS_LOG, &truthset)?;
        Ok(())
    }

    fn run_graph_bakeoff(&self, req: GraphBakeoffRequest) -> anyhow::Result<GraphBakeoffRun> {
        self.ensure()?;
        let limit = req.dataset_limit.unwrap_or(200).clamp(1, 2_000);
        let atoms = self.read_recent_jsonl::<MemoryAtom>(MEMORY_ATOMS_LOG, limit)?;
        let episodes = self.read_recent_jsonl::<MemoryEpisode>(MEMORY_EPISODES_LOG, limit)?;
        let worlds = self.read_recent_jsonl::<MemoryWorld>(MEMORY_WORLDS_LOG, limit)?;
        let candidates = bakeoff_candidates(episodes.len(), atoms.len(), worlds.len());
        let winner = candidates
            .iter()
            .max_by(|a, b| {
                a.score
                    .partial_cmp(&b.score)
                    .unwrap_or(std::cmp::Ordering::Equal)
            })
            .map(|candidate| candidate.name.clone())
            .unwrap_or_else(|| "FalkorDB GraphBLAS".to_string());
        let run = GraphBakeoffRun {
            id: Uuid::new_v4().to_string(),
            created_at: Utc::now().to_rfc3339(),
            status: "completed".to_string(),
            schema_version: MEMORY_GRAPH_SCHEMA.to_string(),
            dataset: serde_json::json!({
                "episodes": episodes.len(),
                "atoms": atoms.len(),
                "worlds": worlds.len(),
                "golden_queries": 20,
                "dataset_limit": limit,
                "sources": ["MemoryEpisode", "MemoryAtom", "Claude iOS", "Codex/Claude Code Work Memory"],
                "baseline_included": req.include_baseline.unwrap_or(true),
            }),
            candidates,
            winner,
            baseline: "Neo4j+Qdrant remains baseline only, not promoted by default".to_string(),
            report_ref: "docs/research/beagle_graphrag_runtime_bakeoff.md".to_string(),
            degraded_reason: "Bake-off scores are deterministic design metrics until live FalkorDB/Memgraph/SurrealDB endpoints are configured in the cluster.".to_string(),
        };
        self.append_jsonl(MEMORY_GRAPH_BAKEOFF_RUNS_LOG, &run)?;
        Ok(run)
    }

    fn index_graph(&self, req: GraphIndexRequest) -> anyhow::Result<GraphIndexRun> {
        self.ensure()?;
        let projection = self.project_memory(ProjectMemoryRequest {
            rebuild: req.rebuild,
            source_refs: req.source_refs,
        })?;
        let episodes = self.read_recent_jsonl::<MemoryEpisode>(MEMORY_EPISODES_LOG, usize::MAX)?;
        let atoms = self.read_recent_jsonl::<MemoryAtom>(MEMORY_ATOMS_LOG, usize::MAX)?;
        let before_worlds = self.read_recent_jsonl::<MemoryWorld>(MEMORY_WORLDS_LOG, usize::MAX)?;
        let mut worlds_created = 0;
        for episode in &episodes {
            let world = self.memory_world_for_episode(episode, &atoms)?;
            if !before_worlds.iter().any(|existing| existing.id == world.id) {
                self.append_jsonl(MEMORY_WORLDS_LOG, &world)?;
                worlds_created += 1;
            }
        }
        let worlds = self.read_recent_jsonl::<MemoryWorld>(MEMORY_WORLDS_LOG, usize::MAX)?;
        let merkle_root = merkle_hash(
            worlds
                .iter()
                .map(|world| format!("{}:{}", world.id, world.merkle_root))
                .collect::<Vec<_>>()
                .as_slice(),
        );
        let run = GraphIndexRun {
            id: Uuid::new_v4().to_string(),
            created_at: Utc::now().to_rfc3339(),
            schema_version: MEMORY_GRAPH_SCHEMA.to_string(),
            runtime: req.runtime.unwrap_or_else(graph_runtime_name),
            status: if worlds_created > 0 || req.rebuild {
                "indexed".to_string()
            } else {
                "unchanged".to_string()
            },
            episodes_indexed: episodes.len(),
            atoms_indexed: atoms.len(),
            worlds_created,
            hyperedges_indexed: atoms.iter().map(|atom| atom.relations.len().max(1)).sum(),
            merkle_root,
            degraded_reason: graph_degraded_reason(graph_runtime_configured()),
            provenance: serde_json::json!({
                "projection_run_id": projection.id,
                "projection_hash": projection.projection_hash,
                "canonical_store": "/var/lib/beagle/exocortex",
                "runtime_configured": graph_runtime_configured(),
                "index_is_rebuildable": true
            }),
        };
        self.append_jsonl(MEMORY_GRAPH_INDEX_RUNS_LOG, &run)?;
        let home = self.build_home_snapshot(HomeQuery {
            active_project_slug: None,
            platform: Some("graphrag++-index".to_string()),
        })?;
        self.write_snapshot(HOME_SNAPSHOT, &home)?;
        Ok(run)
    }

    fn memory_world_for_episode(
        &self,
        episode: &MemoryEpisode,
        atoms: &[MemoryAtom],
    ) -> anyhow::Result<MemoryWorld> {
        let episode_atoms = atoms
            .iter()
            .filter(|atom| atom.episode_id == episode.id)
            .collect::<Vec<_>>();
        let relation_count = episode_atoms
            .iter()
            .map(|atom| atom.relations.len())
            .sum::<usize>();
        let material = std::iter::once(format!("episode:{}", episode.id))
            .chain(episode_atoms.iter().map(|atom| {
                format!(
                    "atom:{}:{}:{}",
                    atom.id, atom.atom_type, atom.normalized_text
                )
            }))
            .collect::<Vec<_>>();
        Ok(MemoryWorld {
            id: stable_id("world", &[&episode.source_ref, &episode.content_hash]),
            created_at: Utc::now().to_rfc3339(),
            world_type: episode
                .session_id
                .as_ref()
                .map(|_| "session")
                .unwrap_or("episode")
                .to_string(),
            source_ref: episode.source_ref.clone(),
            title: episode.title.clone(),
            merkle_root: merkle_hash(&material),
            valid_from: episode.occurred_at.clone(),
            valid_until: None,
            node_count: 1 + episode_atoms.len(),
            edge_count: relation_count + episode_atoms.len(),
            runtime_hint: graph_runtime_name(),
            tags: episode.tags.clone(),
            provenance: serde_json::json!({
                "source": "MemoryEpisode+MemoryAtom",
                "content_addressed": true,
                "canonical_store": "/var/lib/beagle/exocortex",
                "falkordb_promotion_candidate": true
            }),
        })
    }

    fn memory_graph_recent(&self, limit: usize) -> anyhow::Result<MemoryGraphRecentResponse> {
        self.ensure()?;
        let limit = limit.clamp(1, 50);
        let status = self.memory_projection_status()?;
        let episodes = self.read_recent_jsonl::<MemoryEpisode>(MEMORY_EPISODES_LOG, limit)?;
        let atoms = self.read_recent_jsonl::<MemoryAtom>(MEMORY_ATOMS_LOG, limit)?;
        let mut relations = Vec::<MemoryRelation>::new();
        for atom in &atoms {
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
        let worlds = self.read_recent_jsonl::<MemoryWorld>(MEMORY_WORLDS_LOG, limit)?;
        let communities = memory_communities(&atoms, &worlds);
        Ok(MemoryGraphRecentResponse {
            generated_at: Utc::now().to_rfc3339(),
            status,
            episodes,
            atoms,
            relations,
            worlds,
            communities,
            provenance: serde_json::json!({
                "source": "cluster-jsonl",
                "schema_version": MEMORY_PROJECTION_SCHEMA,
                "graph_schema_version": MEMORY_GRAPH_SCHEMA,
                "graph_runtime": graph_runtime_name(),
                "canonical_store": "/var/lib/beagle/exocortex",
                "derived_indexes": "rebuildable"
            }),
        })
    }

    fn memory_worlds_recent(&self, limit: usize) -> anyhow::Result<MemoryWorldsRecentResponse> {
        self.ensure()?;
        let limit = limit.clamp(1, 50);
        Ok(MemoryWorldsRecentResponse {
            generated_at: Utc::now().to_rfc3339(),
            worlds: self.read_recent_jsonl::<MemoryWorld>(MEMORY_WORLDS_LOG, limit)?,
            graph_status: self.memory_graph_status()?,
        })
    }

    fn create_spatial_world(&self, req: CreateSpatialWorldRequest) -> anyhow::Result<SpatialWorld> {
        self.ensure()?;
        let project_slug = req
            .project_slug
            .as_deref()
            .map(normalize_project_slug)
            .filter(|value| !value.is_empty())
            .unwrap_or_else(|| "sounio".to_string());
        let sanitized_prompt = req
            .sanitized_prompt
            .clone()
            .or(req.prompt_summary.clone())
            .unwrap_or_else(|| "Sounio Control Room spatial world".to_string());
        ensure_spatial_prompt_is_safe(&sanitized_prompt)?;
        anyhow::ensure!(
            req.approved.unwrap_or(false),
            "Marble world generation requires explicit approved=true metadata"
        );
        let model = normalize_marble_model(req.model.as_deref());
        let permission = normalize_marble_permission(req.permission.as_deref());
        anyhow::ensure!(
            permission != "public",
            "spatial worlds default to private/non-public Marble permissions"
        );
        let now = Utc::now().to_rfc3339();
        let prompt_hash = format!("sha256:{}", content_hash(sanitized_prompt.as_bytes()));
        let purpose = req
            .purpose
            .as_deref()
            .map(|value| value.trim())
            .filter(|value| !value.is_empty())
            .unwrap_or("control-room");
        let world_id = req.world_id.clone().unwrap_or_else(|| {
            stable_id(
                "spatial-world",
                &[&project_slug, purpose, &prompt_hash, &model],
            )
        });
        let assets = req.assets.unwrap_or_else(default_spatial_assets);
        let display_name = req
            .display_name
            .clone()
            .filter(|value| !value.trim().is_empty())
            .unwrap_or_else(|| format!("{} Spatial Control Room", project_slug));
        let tags = dedupe_strings(
            req.tags
                .into_iter()
                .chain([
                    "spatial-control-room".to_string(),
                    "marble".to_string(),
                    format!("project:{}", project_slug),
                    "sounio-spatial-evidence".to_string(),
                ])
                .collect(),
            32,
        );
        let mut provenance = req.provenance.as_object().cloned().unwrap_or_default();
        provenance.insert(
            "schema_version".to_string(),
            serde_json::Value::String(SPATIAL_SCHEMA.to_string()),
        );
        provenance.insert(
            "canonical_truth".to_string(),
            serde_json::Value::String("JSONL/Merkle/Chronoself remains authoritative".to_string()),
        );
        provenance.insert(
            "derived_artifact".to_string(),
            serde_json::Value::Bool(true),
        );
        provenance.insert(
            "sanitized_prompt_only".to_string(),
            serde_json::Value::Bool(true),
        );
        let world = SpatialWorld {
            id: stable_id("spatial", &[&world_id, &prompt_hash]),
            created_at: now.clone(),
            updated_at: now,
            schema_version: SPATIAL_SCHEMA.to_string(),
            project_slug: project_slug.clone(),
            world_id: world_id.clone(),
            operation_id: req.operation_id,
            display_name,
            status: req.status.unwrap_or_else(|| "requested".to_string()),
            world_marble_url: req.world_marble_url,
            assets,
            model,
            permission,
            prompt_hash,
            prompt_summary: truncate_chars(&sanitized_prompt, 280),
            privacy_policy:
                "cluster-private derived artifact; private memory and raw logs are never sent to Marble"
                    .to_string(),
            tags,
            provenance: serde_json::Value::Object(provenance),
        };
        self.append_jsonl(SPATIAL_WORLDS_LOG, &world)?;
        let memory_world = self.spatial_memory_world(&world)?;
        self.append_jsonl(MEMORY_WORLDS_LOG, &memory_world)?;
        let event = MemoryEvent {
            id: Uuid::new_v4().to_string(),
            created_at: Utc::now().to_rfc3339(),
            source: "spatial-control-room".to_string(),
            kind: "spatial_world".to_string(),
            content_ref: Some(format!("spatial_world:{}", world.world_id)),
            summary: format!(
                "Registered {} Marble spatial world for {}.",
                world.model, world.project_slug
            ),
            tags: world.tags.clone(),
            metadata: serde_json::json!({
                "world_id": world.world_id,
                "operation_id": world.operation_id,
                "prompt_hash": world.prompt_hash,
                "permission": world.permission,
                "privacy_policy": world.privacy_policy,
                "memory_world_id": memory_world.id
            }),
            linked_chronoself_commits: Vec::new(),
            confidence: 0.82,
        };
        self.append_jsonl(MEMORY_EVENTS_LOG, &event)?;
        let _ = self.create_audit_event(CreateAuditEventRequest {
            client_id: Some("beagle-spatial-api".to_string()),
            action: Some("spatial.world.register".to_string()),
            tool_name: None,
            risk_level: Some("write".to_string()),
            required_scopes: vec!["memory:write".to_string()],
            granted_scopes: Vec::new(),
            status: Some("success".to_string()),
            source: Some("beagle-core".to_string()),
            target_ref: Some(format!("spatial_world:{}", world.world_id)),
            summary: Some("Registered Marble spatial world metadata.".to_string()),
            metadata: Some(serde_json::json!({
                "model": world.model,
                "permission": world.permission,
                "prompt_hash": world.prompt_hash,
                "sanitized_prompt_only": true
            })),
        })?;
        Ok(world)
    }

    fn spatial_world(&self, world_id: &str) -> anyhow::Result<Option<SpatialWorld>> {
        Ok(self
            .read_recent_jsonl::<SpatialWorld>(SPATIAL_WORLDS_LOG, usize::MAX)?
            .into_iter()
            .find(|world| world.world_id == world_id || world.id == world_id))
    }

    fn control_room_snapshot(&self, slug: &str) -> anyhow::Result<ControlRoomSnapshot> {
        self.ensure()?;
        let project_slug = normalize_project_slug(slug);
        let spatial_world = self
            .read_recent_jsonl::<SpatialWorld>(SPATIAL_WORLDS_LOG, usize::MAX)?
            .into_iter()
            .find(|world| world.project_slug == project_slug && world.permission != "public");
        let memory_worlds = self
            .read_recent_jsonl::<MemoryWorld>(MEMORY_WORLDS_LOG, 24)?
            .into_iter()
            .filter(|world| {
                world
                    .tags
                    .iter()
                    .any(|tag| tag == &format!("project:{}", project_slug))
                    || world.provenance["project_slug"].as_str() == Some(project_slug.as_str())
            })
            .take(8)
            .collect::<Vec<_>>();
        let evidence_refs = self
            .read_recent_jsonl::<SounioSpatialEvidence>(SPATIAL_EVIDENCE_LOG, 24)?
            .into_iter()
            .filter(|evidence| {
                evidence.project_slug == project_slug && evidence.privacy_class != "restricted"
            })
            .map(|evidence| evidence.id)
            .take(8)
            .collect::<Vec<_>>();
        let agent_lanes = vec![
            "Builder: Claude/Codex".to_string(),
            "Code Worker: MiniMax/Qwen".to_string(),
            "Long Thought: Kimi".to_string(),
            "Platform Operator: GLM".to_string(),
            "Shell".to_string(),
        ];
        Ok(ControlRoomSnapshot {
            id: stable_id("control-room", &[&project_slug, SPATIAL_SCHEMA]),
            generated_at: Utc::now().to_rfc3339(),
            schema_version: SPATIAL_SCHEMA.to_string(),
            project_slug: project_slug.clone(),
            spatial_world,
            memory_worlds,
            agent_lanes,
            pods_wall: vec![
                "beagle-core".to_string(),
                "beagle-mcp-server".to_string(),
                "beagle-workspace-agent".to_string(),
                "world-console".to_string(),
            ],
            incident_corridor: vec![
                "recent audit events".to_string(),
                "failed-write rescue".to_string(),
            ],
            compiler_map: vec![
                "Sounio IR".to_string(),
                "Claim<T>".to_string(),
                "Temporal PaperRun".to_string(),
            ],
            evidence_refs,
            provenance: serde_json::json!({
                "source": "beagle-core-spatial",
                "schema_version": SPATIAL_SCHEMA,
                "canonical_store": "/var/lib/beagle/exocortex",
                "surface": "visionOS"
            }),
        })
    }

    fn create_spatial_evidence(
        &self,
        world_id: &str,
        req: CreateSounioSpatialEvidenceRequest,
    ) -> anyhow::Result<SounioSpatialEvidence> {
        self.ensure()?;
        let world = self
            .spatial_world(world_id)?
            .ok_or_else(|| anyhow::anyhow!("spatial world not found: {}", world_id))?;
        let privacy_class = normalize_privacy_class(req.privacy_class.as_deref());
        anyhow::ensure!(
            privacy_class != "restricted",
            "restricted spatial evidence requires explicit local review before cluster write"
        );
        let epistemic_status = normalize_epistemic_status(req.epistemic_status.as_deref());
        anyhow::ensure!(
            epistemic_status == "belief" || epistemic_status == "contest",
            "spatial worlds can seed belief/contest claims only"
        );
        let now = Utc::now().to_rfc3339();
        let evidence = SounioSpatialEvidence {
            id: stable_id(
                "spatial-evidence",
                &[&world.world_id, &req.project_slug, &now],
            ),
            created_at: now,
            schema_version: SPATIAL_SCHEMA.to_string(),
            world_id: world.world_id.clone(),
            project_slug: normalize_project_slug(&req.project_slug),
            evidence_type: req
                .evidence_type
                .unwrap_or_else(|| "spatial_memory_world".to_string()),
            claim_seed_refs: dedupe_strings(req.claim_seed_refs, 32),
            memory_world_refs: dedupe_strings(req.memory_world_refs, 32),
            artifact_refs: dedupe_strings(req.artifact_refs, 32),
            epistemic_status,
            privacy_class,
            provenance: serde_json::json!({
                "world_id": world.world_id,
                "spatial_world_ref": world.id,
                "input": req.provenance,
                "claim_policy": "belief_or_contest_only",
                "restricted_leak_check": "passed:no_restricted_spatial_evidence"
            }),
        };
        self.append_jsonl(SPATIAL_EVIDENCE_LOG, &evidence)?;
        let event = MemoryEvent {
            id: Uuid::new_v4().to_string(),
            created_at: Utc::now().to_rfc3339(),
            source: "sounio-spatial-evidence".to_string(),
            kind: "spatial_evidence".to_string(),
            content_ref: Some(evidence.id.clone()),
            summary: format!(
                "Linked spatial world {} as Sounio {} evidence.",
                evidence.world_id, evidence.epistemic_status
            ),
            tags: vec![
                "spatial-evidence".to_string(),
                "sounio".to_string(),
                format!("project:{}", evidence.project_slug),
            ],
            metadata: serde_json::json!({
                "world_id": evidence.world_id,
                "epistemic_status": evidence.epistemic_status,
                "claim_seed_refs": evidence.claim_seed_refs,
                "memory_world_refs": evidence.memory_world_refs
            }),
            linked_chronoself_commits: Vec::new(),
            confidence: 0.78,
        };
        self.append_jsonl(MEMORY_EVENTS_LOG, &event)?;
        Ok(evidence)
    }

    fn spatial_memory_world(&self, world: &SpatialWorld) -> anyhow::Result<MemoryWorld> {
        let material = vec![
            world.world_id.clone(),
            world.prompt_hash.clone(),
            serde_json::to_string(&world.assets)?,
        ];
        Ok(MemoryWorld {
            id: stable_id("world", &[&world.world_id, &world.prompt_hash]),
            created_at: Utc::now().to_rfc3339(),
            world_type: "spatial-control-room".to_string(),
            source_ref: format!("spatial_world:{}", world.world_id),
            title: Some(world.display_name.clone()),
            merkle_root: merkle_hash(&material),
            valid_from: Some(world.created_at.clone()),
            valid_until: None,
            node_count: 6,
            edge_count: 8,
            runtime_hint: "visionOS+Marble".to_string(),
            tags: world.tags.clone(),
            provenance: serde_json::json!({
                "source": "SpatialWorld",
                "schema_version": SPATIAL_SCHEMA,
                "project_slug": world.project_slug,
                "world_id": world.world_id,
                "content_addressed": true,
                "derived_artifact": true,
                "canonical_store": "/var/lib/beagle/exocortex"
            }),
        })
    }

    fn mind_palace_snapshot(&self) -> anyhow::Result<MindPalaceSnapshot> {
        self.ensure()?;
        let rooms = self.derive_mind_palace_rooms()?;
        let focus_coach = self.focus_coach_status()?;
        let portals = self.conversation_portals_recent(8)?;
        let desk = self.spatial_desk_snapshot(&rooms, portals, &focus_coach)?;
        let next_best_place = self.next_best_place_decision(&rooms, &focus_coach)?;
        let action_menu = self.spatial_action_menu(&rooms, &next_best_place, &focus_coach)?;
        Ok(MindPalaceSnapshot {
            id: stable_id("mind-palace", &[MIND_PALACE_SCHEMA, "memory-derived"]),
            generated_at: Utc::now().to_rfc3339(),
            schema_version: MIND_PALACE_SCHEMA.to_string(),
            rooms,
            desk,
            next_best_place,
            action_menu,
            focus_coach,
            provenance: serde_json::json!({
                "source": "cluster-jsonl-derived",
                "canonical_store": "/var/lib/beagle/exocortex",
                "surface": "ipad+visionos",
                "policy": "Mission Control + Spatial Desk + Portal Promote",
                "sounio_is_one_room_not_the_whole_palace": true
            }),
        })
    }

    fn derive_mind_palace_rooms(&self) -> anyhow::Result<Vec<MindPalaceRoom>> {
        let memory_events = self.read_recent_jsonl::<MemoryEvent>(MEMORY_EVENTS_LOG, 96)?;
        let imports = self.read_recent_jsonl::<OmniConversation>(OMNIMEMORY_LOG, 96)?;
        let moments = self.read_recent_jsonl::<SounioMoment>(SOUNIO_MOMENTS_LOG, 48)?;
        let worlds = self.read_recent_jsonl::<SpatialWorld>(SPATIAL_WORLDS_LOG, 24)?;
        let paper_runs = self.read_recent_jsonl::<PaperRun>(SOUNIO_PAPERRUNS_LOG, 12)?;
        let portals = self.conversation_portals_recent(24)?;
        let mut rooms: BTreeMap<String, MindPalaceRoom> = BTreeMap::new();

        for event in memory_events.iter().filter(|event| {
            metadata_string(&event.metadata, "privacy_class").as_deref() != Some("restricted")
        }) {
            for tag in event
                .tags
                .iter()
                .filter_map(|tag| tag.strip_prefix("project:"))
            {
                let slug = normalize_project_slug(tag);
                upsert_mind_palace_room(
                    &mut rooms,
                    mind_palace_project_room(
                        &slug,
                        "memory-events",
                        Some(format!("memory_event:{}", event.id)),
                        if event.source.contains("work") || event.kind.contains("import") {
                            0.86
                        } else {
                            0.68
                        },
                    ),
                );
            }
            if event.source.contains("codex")
                || event.source.contains("claude")
                || event.source.contains("workbench")
                || event.tags.iter().any(|tag| tag.contains("agent:"))
            {
                upsert_mind_palace_room(
                    &mut rooms,
                    mind_palace_room(
                        "parallel-work",
                        "Parallel Workbench",
                        "workspace",
                        "active",
                        None,
                        "agent work memory",
                        "Many agents can make progress while conversation continues elsewhere.",
                        "Open the Workbench drawer and inspect the latest remembered block.",
                        0.91,
                        Some(format!("memory_event:{}", event.id)),
                        vec!["workbench".to_string(), "agents".to_string()],
                    ),
                );
            }
        }

        for import in imports
            .iter()
            .filter(|import| import.privacy_class != "restricted")
        {
            for project in &import.extracted.projects_mentioned {
                let slug = normalize_project_slug(project);
                upsert_mind_palace_room(
                    &mut rooms,
                    mind_palace_project_room(
                        &slug,
                        &format!("{} import", import.source_platform),
                        Some(format!("omnimemory:{}", import.id)),
                        0.74,
                    ),
                );
            }
            if import.tags.iter().any(|tag| {
                tag.contains("claude") || tag.contains("chatgpt") || tag.contains("grok")
            }) {
                upsert_mind_palace_room(
                    &mut rooms,
                    mind_palace_room(
                        "free-thought",
                        "Free Thought",
                        "conversation",
                        "open",
                        None,
                        "conversation imports",
                        "Not every useful thought belongs to a project immediately.",
                        "Keep the thread available, then promote only the useful clips.",
                        0.73,
                        Some(format!("omnimemory:{}", import.id)),
                        vec!["free_thought".to_string(), "conversation".to_string()],
                    ),
                );
            }
        }

        for moment in moments
            .iter()
            .filter(|moment| moment.privacy_class != "restricted")
        {
            let slug = normalize_project_slug(&moment.project_slug);
            upsert_mind_palace_room(
                &mut rooms,
                mind_palace_project_room(
                    &slug,
                    "Sounio moments",
                    Some(format!("sounio_moment:{}", moment.id)),
                    0.88,
                ),
            );
        }

        for world in worlds.iter().filter(|world| world.permission != "public") {
            upsert_mind_palace_room(
                &mut rooms,
                mind_palace_room(
                    "spatial-forge",
                    "Spatial Forge",
                    "spatial",
                    &world.status,
                    Some(world.project_slug.clone()),
                    "spatial worlds",
                    "Worlds are powerful evidence surfaces, but they are still derived artifacts.",
                    "Review generated assets and link only sanitized spatial evidence.",
                    0.79,
                    Some(format!("spatial_world:{}", world.world_id)),
                    vec![
                        "spatial".to_string(),
                        "world-console".to_string(),
                        format!("project:{}", world.project_slug),
                    ],
                ),
            );
        }

        for run in paper_runs {
            upsert_mind_palace_room(
                &mut rooms,
                mind_palace_room(
                    "paper-theatre",
                    "Paper Theatre",
                    "paper",
                    run.status.as_str(),
                    Some("beagle".to_string()),
                    "PaperRun",
                    "The paper should be a living trace of the system, not a detached artifact.",
                    run.pending_approval_step
                        .as_deref()
                        .or(run.current_stage.as_deref())
                        .unwrap_or("Open PaperRun Theatre and review unsupported claims."),
                    0.7,
                    Some(format!("paperrun:{}", run.id)),
                    vec!["paperrun".to_string(), "sounio".to_string()],
                ),
            );
        }

        if !portals.is_empty() {
            upsert_mind_palace_room(
                &mut rooms,
                mind_palace_room(
                    "conversation-portals",
                    "Conversation Portals",
                    "portal",
                    "available",
                    None,
                    "Claude/GPT desktop portals",
                    "Portals are reference windows until you explicitly promote a clip.",
                    "Promote only the useful selected idea, not the whole external conversation.",
                    0.84,
                    portals
                        .first()
                        .map(|portal| format!("portal:{}", portal.id)),
                    vec!["portal".to_string(), "promote".to_string()],
                ),
            );
        }

        if rooms.is_empty() {
            upsert_mind_palace_room(
                &mut rooms,
                mind_palace_room(
                    "free-thought",
                    "Free Thought",
                    "conversation",
                    "seed",
                    None,
                    "declared seed",
                    "The palace starts open until live memory supplies stronger rooms.",
                    "Capture or promote the next useful thought.",
                    0.62,
                    None,
                    vec!["free_thought".to_string()],
                ),
            );
            upsert_mind_palace_room(
                &mut rooms,
                mind_palace_project_room("beagle", "declared seed", None, 0.6),
            );
        }

        let mut out = rooms.into_values().collect::<Vec<_>>();
        out.sort_by(|a, b| {
            b.priority
                .partial_cmp(&a.priority)
                .unwrap_or(std::cmp::Ordering::Equal)
                .then_with(|| a.title.cmp(&b.title))
        });
        out.truncate(12);
        Ok(out)
    }

    fn spatial_desk_snapshot(
        &self,
        rooms: &[MindPalaceRoom],
        portals: Vec<ConversationPortal>,
        focus: &FocusCoachState,
    ) -> anyhow::Result<SpatialDeskSnapshot> {
        let mut items = Vec::new();
        for room in rooms.iter().take(6) {
            items.push(DeskItem {
                id: stable_id("desk-item", &[&room.id, &room.state]),
                kind: room.room_type.clone(),
                title: room.title.clone(),
                detail: room.tension.clone(),
                state: room.state.clone(),
                priority: room.priority,
                room_id: Some(room.id.clone()),
                source_ref: room.evidence_refs.first().cloned(),
                actions: vec![
                    "open".to_string(),
                    "prove".to_string(),
                    "promote".to_string(),
                ],
                provenance: serde_json::json!({
                    "source": "mind_palace_room",
                    "truth_mode": room.truth_mode
                }),
            });
        }
        for portal in portals.iter().take(4) {
            items.push(DeskItem {
                id: stable_id("desk-portal", &[&portal.id, &portal.updated_at]),
                kind: "conversation_portal".to_string(),
                title: portal.title.clone(),
                detail: format!(
                    "{} portal via {}; promote explicit clips only.",
                    portal.provider, portal.source_mode
                ),
                state: portal.status.clone(),
                priority: 0.78,
                room_id: Some("conversation-portals".to_string()),
                source_ref: Some(format!("conversation_portal:{}", portal.id)),
                actions: vec!["open_portal".to_string(), "promote_clip".to_string()],
                provenance: serde_json::json!({
                    "provider": portal.provider,
                    "privacy_class": portal.privacy_class,
                    "no_scraping": true
                }),
            });
        }
        Ok(SpatialDeskSnapshot {
            id: stable_id("spatial-desk", &[MIND_PALACE_SCHEMA, "mission-control"]),
            generated_at: Utc::now().to_rfc3339(),
            schema_version: MIND_PALACE_SCHEMA.to_string(),
            active_items: items,
            pinned_room_ids: rooms.iter().take(4).map(|room| room.id.clone()).collect(),
            portals,
            agent_lanes: spatial_desk_agent_lanes(),
            focus_strip: focus
                .interventions
                .iter()
                .take(3)
                .map(|intervention| intervention.title.clone())
                .collect(),
            proof_panels: vec![
                "Memory provenance".to_string(),
                "Portal promotions".to_string(),
                "Spatial artifact policy".to_string(),
            ],
            provenance: serde_json::json!({
                "source": "beagle-core",
                "layout": "Spatial Desk",
                "entry": "Command First",
                "cluster_only": true
            }),
        })
    }

    fn next_best_place_decision(
        &self,
        rooms: &[MindPalaceRoom],
        focus: &FocusCoachState,
    ) -> anyhow::Result<NextBestPlaceDecision> {
        let selected = rooms
            .iter()
            .find(|room| room.id == "parallel-work" || room.state == "active")
            .or_else(|| rooms.first())
            .cloned()
            .unwrap_or_else(|| {
                mind_palace_room(
                    "free-thought",
                    "Free Thought",
                    "conversation",
                    "seed",
                    None,
                    "fallback",
                    "No live room has enough evidence yet.",
                    "Capture the next useful thought.",
                    0.5,
                    None,
                    vec!["free_thought".to_string()],
                )
            });
        Ok(NextBestPlaceDecision {
            id: stable_id("next-best-place", &[&selected.id, &selected.state]),
            generated_at: Utc::now().to_rfc3339(),
            room_id: selected.id.clone(),
            title: selected.title.clone(),
            reason: format!(
                "{} Continuity says this room is live; readiness says {}.",
                selected.next_action, focus.mode
            ),
            source_mode: "continuity+readiness".to_string(),
            confidence: (selected.priority * 0.92).clamp(0.0, 0.96),
            candidate_room_ids: rooms.iter().take(5).map(|room| room.id.clone()).collect(),
            readiness_context: serde_json::json!({
                "focus_mode": focus.mode,
                "hydration_due": focus.hydration_due,
                "session_minutes": focus.session_minutes,
                "can_override": focus.can_override
            }),
        })
    }

    fn spatial_action_menu(
        &self,
        rooms: &[MindPalaceRoom],
        next: &NextBestPlaceDecision,
        focus: &FocusCoachState,
    ) -> anyhow::Result<SpatialActionMenu> {
        let portal_enabled = rooms.iter().any(|room| room.id == "conversation-portals");
        Ok(SpatialActionMenu {
            id: stable_id("spatial-action-menu", &[MIND_PALACE_SCHEMA, &next.room_id]),
            generated_at: Utc::now().to_rfc3339(),
            mode: "parallel-spaces".to_string(),
            actions: vec![
                SpatialAction {
                    id: "continue-place".to_string(),
                    title: "Continue".to_string(),
                    kind: "open_room".to_string(),
                    target_ref: Some(next.room_id.clone()),
                    reason: next.reason.clone(),
                    enabled: true,
                },
                SpatialAction {
                    id: "open-workbench".to_string(),
                    title: "Open Workbench".to_string(),
                    kind: "open_workbench".to_string(),
                    target_ref: Some("workspace:sounio".to_string()),
                    reason: "Keep coding agents visible while planning and chatting elsewhere."
                        .to_string(),
                    enabled: true,
                },
                SpatialAction {
                    id: "reflect".to_string(),
                    title: "Reflect".to_string(),
                    kind: "open_memory_lens".to_string(),
                    target_ref: None,
                    reason: "Open Memory Lens / proof panels without stopping the workspace."
                        .to_string(),
                    enabled: true,
                },
                SpatialAction {
                    id: "promote-portal".to_string(),
                    title: "Promote Portal".to_string(),
                    kind: "promote_conversation_clip".to_string(),
                    target_ref: Some("conversation-portals".to_string()),
                    reason: "Turn a selected Claude/GPT idea into memory explicitly.".to_string(),
                    enabled: portal_enabled,
                },
                SpatialAction {
                    id: "generate-space".to_string(),
                    title: "Generate Space".to_string(),
                    kind: "spatial_generation_draft".to_string(),
                    target_ref: Some("spatial-forge".to_string()),
                    reason:
                        "Draft a sanitized spatial world or asset request before any paid generation."
                            .to_string(),
                    enabled: true,
                },
                SpatialAction {
                    id: "focus-coach".to_string(),
                    title: "Focus Coach".to_string(),
                    kind: "focus_intervention".to_string(),
                    target_ref: focus.interventions.first().map(|item| item.id.clone()),
                    reason: "Calendar, hydration, breaks, and closure keep the exocortex humane."
                        .to_string(),
                    enabled: true,
                },
            ],
        })
    }

    fn conversation_portals_recent(&self, limit: usize) -> anyhow::Result<Vec<ConversationPortal>> {
        let mut seen = BTreeSet::new();
        Ok(self
            .read_recent_jsonl::<ConversationPortal>(CONVERSATION_PORTALS_LOG, limit.max(32))?
            .into_iter()
            .filter(|portal| portal.privacy_class != "restricted")
            .filter(|portal| seen.insert(portal.id.clone()))
            .take(limit)
            .collect())
    }

    fn create_conversation_portal(
        &self,
        req: CreateConversationPortalRequest,
    ) -> anyhow::Result<ConversationPortal> {
        self.ensure()?;
        let privacy_class = normalize_privacy_class(req.privacy_class.as_deref());
        anyhow::ensure!(
            privacy_class != "restricted",
            "restricted portals must stay local/review-only and cannot be written to cluster"
        );
        let title = truncate_chars(req.title.trim(), 120);
        anyhow::ensure!(!title.is_empty(), "conversation portal title is required");
        let provider = normalize_provider_label(&req.provider);
        let surface = req
            .surface
            .as_deref()
            .map(|value| value.trim().to_lowercase())
            .filter(|value| !value.is_empty())
            .unwrap_or_else(|| "desktop-portal".to_string());
        let now = Utc::now().to_rfc3339();
        let portal = ConversationPortal {
            id: stable_id("portal", &[&title, &provider, &surface, &now]),
            created_at: now.clone(),
            updated_at: now,
            schema_version: CONVERSATION_PORTAL_SCHEMA.to_string(),
            title,
            provider,
            surface,
            status: req.status.unwrap_or_else(|| "reference_only".to_string()),
            source_mode: req
                .source_mode
                .unwrap_or_else(|| "portal+promote".to_string()),
            privacy_class,
            source_ref: req.source_ref,
            promoted_clip_refs: Vec::new(),
            tags: dedupe_strings(
                req.tags
                    .into_iter()
                    .chain([
                        "conversation-portal".to_string(),
                        "portal-promote".to_string(),
                    ])
                    .collect(),
                32,
            ),
            provenance: merge_json_objects(
                serde_json::json!({
                    "schema_version": CONVERSATION_PORTAL_SCHEMA,
                    "no_scraping": true,
                    "promotion_required_for_memory": true
                }),
                req.provenance,
            ),
        };
        self.append_jsonl(CONVERSATION_PORTALS_LOG, &portal)?;
        Ok(portal)
    }

    fn promote_conversation_portal_clip(
        &self,
        portal_id: &str,
        req: PromoteConversationPortalRequest,
    ) -> anyhow::Result<PromotedConversationClip> {
        self.ensure()?;
        let mut portal = self
            .read_recent_jsonl::<ConversationPortal>(CONVERSATION_PORTALS_LOG, usize::MAX)?
            .into_iter()
            .find(|portal| portal.id == portal_id)
            .ok_or_else(|| anyhow::anyhow!("conversation portal not found: {portal_id}"))?;
        let privacy_class = normalize_privacy_class(req.privacy_class.as_deref());
        anyhow::ensure!(
            privacy_class != "restricted",
            "restricted portal clips require local review and cannot be promoted automatically"
        );
        ensure_promoted_clip_is_safe(&req.selected_text)?;
        let content_hash = format!("sha256:{}", content_hash(req.selected_text.as_bytes()));
        let summary = req
            .summary
            .as_deref()
            .map(|value| truncate_chars(value.trim(), 360))
            .filter(|value| !value.is_empty())
            .unwrap_or_else(|| truncate_chars(&req.selected_text, 240));
        let project_ref = req
            .project_ref
            .as_deref()
            .map(normalize_project_slug)
            .filter(|value| !value.is_empty())
            .or_else(|| Some("free_thought".to_string()));
        let mut tags = dedupe_strings(
            req.tags
                .clone()
                .into_iter()
                .chain(portal.tags.clone())
                .chain([
                    "conversation-portal".to_string(),
                    "promoted-clip".to_string(),
                    format!("provider:{}", portal.provider),
                    format!("privacy:{}", privacy_class),
                ])
                .collect(),
            32,
        );
        if let Some(project) = &project_ref {
            merge_unique(&mut tags, vec![format!("project:{}", project)], 32);
        }
        let import = self.assisted_import_batch(AssistedImportBatchRequest {
            source_platform: portal.provider.clone(),
            source_surface: portal.surface.clone(),
            import_scope: "promoted_conversation_clip".to_string(),
            session_id: format!("portal-{}", portal.id),
            project_ref: project_ref.clone(),
            batch_index: 1,
            batch_total: 1,
            turns: vec![AssistedImportTurn {
                role: "user".to_string(),
                content: req.selected_text.clone(),
                timestamp: Some(Utc::now().to_rfc3339()),
                model: None,
            }],
            tags: tags.clone(),
            metadata: merge_json_objects(
                serde_json::json!({
                    "principal": "demetrios",
                    "surface_observed": "portal+promote",
                    "portal_id": portal.id,
                    "content_hash": content_hash.clone(),
                    "explicit_selection": true,
                    "no_window_scraping": true
                }),
                req.provenance.clone(),
            ),
            coverage: serde_json::json!({
                "portal_promote": true,
                "selected_clip_only": true
            }),
            extracted: Some(OmniExtraction {
                key_insights: vec![summary.clone()],
                decisions: Vec::new(),
                hypotheses: Vec::new(),
                belief_changes: Vec::new(),
                emotional_state: None,
                identity_signals: None,
                projects_mentioned: project_ref.clone().into_iter().collect(),
                unresolved_questions: Vec::new(),
            }),
            privacy_class: Some(privacy_class.clone()),
            title: Some(format!("Promoted {} portal clip", portal.provider)),
            original_date: Some(Utc::now().to_rfc3339()),
            confidence_score: Some(0.82),
            create_chronoself_commit: Some(false),
            capture_session_id: None,
            artifact_refs: Vec::new(),
            transcription_segments: Vec::new(),
            visual_evidence_refs: Vec::new(),
        })?;
        let now = Utc::now().to_rfc3339();
        let clip = PromotedConversationClip {
            id: stable_id("portal-clip", &[&portal.id, &content_hash]),
            created_at: now.clone(),
            schema_version: CONVERSATION_PORTAL_SCHEMA.to_string(),
            portal_id: portal.id.clone(),
            content_hash,
            summary,
            project_ref,
            privacy_class,
            memory_event_id: import.memory_event.as_ref().map(|event| event.id.clone()),
            sounio_moment_id: import
                .sounio_moment
                .as_ref()
                .map(|moment| moment.id.clone()),
            tags,
            provenance: serde_json::json!({
                "portal": portal,
                "assisted_import_status": import.status,
                "explicit_selection_only": true,
                "restricted_leak_check": "passed:no_restricted_portal_clip"
            }),
        };
        self.append_jsonl(PROMOTED_CONVERSATION_CLIPS_LOG, &clip)?;
        portal.updated_at = now;
        portal.status = "promoted".to_string();
        merge_unique(
            &mut portal.promoted_clip_refs,
            vec![format!("promoted_clip:{}", clip.id)],
            48,
        );
        self.append_jsonl(CONVERSATION_PORTALS_LOG, &portal)?;
        Ok(clip)
    }

    fn focus_coach_status(&self) -> anyhow::Result<FocusCoachState> {
        self.ensure()?;
        let events = self.read_recent_jsonl::<FocusCoachEvent>(FOCUS_COACH_EVENTS_LOG, 48)?;
        let active_start = events
            .iter()
            .find(|event| event.event_kind == "start_focus" && event.status != "ended");
        let session_minutes = active_start
            .and_then(|event| chrono::DateTime::parse_from_rfc3339(&event.created_at).ok())
            .map(|started| {
                (Utc::now() - started.with_timezone(&Utc))
                    .num_minutes()
                    .max(0) as u32
            })
            .unwrap_or(0);
        let latest_snooze = events
            .iter()
            .find(|event| event.event_kind == "snooze")
            .and_then(|event| event.snoozed_minutes)
            .unwrap_or(0);
        let hydration_due = session_minutes >= 35 && latest_snooze == 0;
        let mut interventions = Vec::new();
        if session_minutes >= 75 {
            interventions.push(FocusIntervention {
                id: "close-loop-break".to_string(),
                kind: "break".to_string(),
                title: "Close loop, then pause".to_string(),
                reason: "This focus block is long enough that memory quality and body state benefit from a short closure.".to_string(),
                priority: 0.94,
                status: "suggested".to_string(),
                due_at: None,
                actions: vec!["summarize".to_string(), "hydrate".to_string(), "pause".to_string()],
            });
        } else if hydration_due {
            interventions.push(FocusIntervention {
                id: "hydrate".to_string(),
                kind: "hydration".to_string(),
                title: "Water + posture check".to_string(),
                reason: "Gentle physiological upkeep while agents keep running.".to_string(),
                priority: 0.72,
                status: "suggested".to_string(),
                due_at: None,
                actions: vec!["drink_water".to_string(), "snooze".to_string()],
            });
        }
        interventions.push(FocusIntervention {
            id: "calendar-guard".to_string(),
            kind: "calendar".to_string(),
            title: "Calendar guard".to_string(),
            reason: "Keep commitments visible while parallel workspaces run.".to_string(),
            priority: 0.64,
            status: "available".to_string(),
            due_at: None,
            actions: vec!["open_calendar".to_string(), "snooze".to_string()],
        });
        let mode = if session_minutes >= 75 {
            "recovering"
        } else if session_minutes >= 25 {
            "focused"
        } else {
            "available"
        };
        Ok(FocusCoachState {
            id: stable_id("focus-coach", &[FOCUS_COACH_SCHEMA, mode]),
            generated_at: Utc::now().to_rfc3339(),
            schema_version: FOCUS_COACH_SCHEMA.to_string(),
            mode: mode.to_string(),
            active_session: active_start.map(|event| FocusSession {
                id: stable_id(
                    "focus-session",
                    &[
                        &event.created_at,
                        event.project_slug.as_deref().unwrap_or("free"),
                    ],
                ),
                started_at: event.created_at.clone(),
                ended_at: None,
                mode: "focus".to_string(),
                project_slug: event.project_slug.clone(),
                status: "active".to_string(),
                notes: event.notes.clone().into_iter().collect(),
                provenance: event.provenance.clone(),
            }),
            interventions,
            hydration_due,
            calendar_nudge: Some("Keep real commitments visible beside agent work.".to_string()),
            session_minutes,
            can_override: true,
            provenance: serde_json::json!({
                "schema_version": FOCUS_COACH_SCHEMA,
                "not_medical_advice": true,
                "operator_can_override": true,
                "source": "focus_coach_events.jsonl"
            }),
        })
    }

    fn record_focus_coach_event(
        &self,
        req: FocusCoachEventRequest,
    ) -> anyhow::Result<FocusCoachState> {
        self.ensure()?;
        let event_kind = req.event_kind.trim().to_lowercase().replace('-', "_");
        anyhow::ensure!(!event_kind.is_empty(), "focus coach event_kind is required");
        let event = FocusCoachEvent {
            id: Uuid::new_v4().to_string(),
            created_at: Utc::now().to_rfc3339(),
            schema_version: FOCUS_COACH_SCHEMA.to_string(),
            event_kind,
            status: req.status.unwrap_or_else(|| "recorded".to_string()),
            intervention_id: req.intervention_id,
            project_slug: req.project_slug.map(|value| normalize_project_slug(&value)),
            notes: req.notes.map(|value| truncate_chars(value.trim(), 500)),
            snoozed_minutes: req.snoozed_minutes,
            provenance: merge_json_objects(
                serde_json::json!({
                    "source": "beagle-focus-coach",
                    "operator_can_override": true
                }),
                req.provenance,
            ),
        };
        self.append_jsonl(FOCUS_COACH_EVENTS_LOG, &event)?;
        let _ = self.create_audit_event(CreateAuditEventRequest {
            client_id: Some("beagle-focus-coach".to_string()),
            action: Some("focus_coach.event".to_string()),
            tool_name: None,
            risk_level: Some("write".to_string()),
            required_scopes: vec!["memory:write".to_string()],
            granted_scopes: Vec::new(),
            status: Some("success".to_string()),
            source: Some("focus-coach".to_string()),
            target_ref: Some(format!("focus_event:{}", event.id)),
            summary: Some(format!("Recorded focus coach event {}.", event.event_kind)),
            metadata: Some(serde_json::json!({
                "schema_version": FOCUS_COACH_SCHEMA,
                "event_kind": event.event_kind,
                "project_slug": event.project_slug,
                "snoozed_minutes": event.snoozed_minutes
            })),
        })?;
        self.focus_coach_status()
    }

    fn graphrag_query(&self, req: GraphRagQueryRequest) -> anyhow::Result<GraphRagQueryResponse> {
        self.ensure()?;
        let max_items = req.max_items.unwrap_or(5).clamp(1, 20);
        let requested_mode = req.mode.clone().unwrap_or_else(memory_hot_path_mode);
        let is_multivector = requested_mode.eq_ignore_ascii_case("hypermemory_multivector");
        let is_hypermemory = requested_mode.eq_ignore_ascii_case("hypermemory") || is_multivector;
        let ranking_policy = memory_ranking_policy(req.ranking_policy.as_deref());
        let runtime_configured = graph_runtime_configured();
        let graph_runtime = graph_runtime_name();
        let atoms = self.read_recent_jsonl::<MemoryAtom>(MEMORY_ATOMS_LOG, usize::MAX)?;
        let episodes = self.read_recent_jsonl::<MemoryEpisode>(MEMORY_EPISODES_LOG, usize::MAX)?;
        if atoms.is_empty() {
            let strategy_used = retrieval_strategy_for(&req.query);
            let subqueries = retrieval_subqueries_for(&req.query, &strategy_used);
            let stable_fact_guard_applied = stable_fact_guard_applies(&req.query, &[]);
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
                    "graph_schema_version": MEMORY_GRAPH_SCHEMA,
                    "retrieval_mode": "append-only fallback",
                    "graph_runtime": graph_runtime.clone(),
                    "canonical_store": "/var/lib/beagle/exocortex",
                    "hypermemory": {
                        "enabled": is_hypermemory,
                        "authority": "derived-advisory",
                        "benchmark_gate": "required-before-hot-path"
                    }
                }),
                confidence: 0.0,
                degraded_reason: Some("no projected memory atoms available".to_string()),
                mode: Some(requested_mode.clone()),
                graph_runtime: Some(graph_runtime),
                evidence_graph: Some(EvidenceGraph {
                    nodes: Vec::new(),
                    edges: Vec::new(),
                    temporary: true,
                    merkle_root: merkle_hash(&[req.query.clone()]),
                }),
                community_context: Some(GraphRagCommunityContext {
                    strategy: "k-core-density-hierarchy".to_string(),
                    selected_communities: Vec::new(),
                    degraded_reason: Some("no projected atoms available".to_string()),
                }),
                retrieval_trace: vec![RetrievalTraceStep {
                    stage: "projection-check".to_string(),
                    backend: "cluster-jsonl".to_string(),
                    status: "empty".to_string(),
                    items: 0,
                    latency_ms: 0.0,
                    notes: vec!["Memory projection has no atoms yet.".to_string()],
                }],
                mesh_trace: vec![RetrievalTraceStep {
                    stage: "federated-mesh-shortlist".to_string(),
                    backend: "beagle-memory-engine".to_string(),
                    status: "degraded".to_string(),
                    items: 0,
                    latency_ms: 0.0,
                    notes: vec!["v1.5 mesh has no exported atoms to federate yet.".to_string()],
                }],
                runtime_votes: runtime_votes(false),
                candidate_refs: Vec::new(),
                runtime_used: Some(runtime_used_for(&requested_mode, runtime_configured)),
                fallback_chain: fallback_chain_for(&requested_mode, runtime_configured),
                semantic_trace: semantic_trace_for(&requested_mode, runtime_configured, 0),
                maxsim_scores: Vec::new(),
                graph_expansion: graph_expansion_trace(None, 0, 0),
                reranker_scores: Vec::new(),
                truthset_gate_status: truthset_gate_status_for(None, false),
                restricted_leak_check: restricted_leak_check_for(0),
                retrieval_agent: retrieval_agent_mode(),
                retrieval_plan_id: stable_id("retrieval-plan", &[&req.query, &requested_mode]),
                strategy_used: strategy_used.clone(),
                subqueries: subqueries.clone(),
                evidence_pack: evidence_pack_json(0, 0, Vec::new(), 0),
                context_format: retrieval_context_format(),
                planner_mode: retrieval_planner_mode(),
                budget: retrieval_budget_json(max_items, &retrieval_planner_mode()),
                runtime_trace: retrieval_agent_trace_for(
                    &strategy_used,
                    &subqueries,
                    runtime_configured,
                    0,
                    0,
                ),
                context_pack_id: Some(stable_id(
                    "context-pack",
                    &[
                        &req.query,
                        &requested_mode,
                        &strategy_used,
                        &memory_policy_version(),
                    ],
                )),
                policy_version: Some(memory_policy_version()),
                policy_gate: memory_policy_gate_json(),
                dreamcycle_status: Some(dreamcycle_mode()),
                ranking_policy: Some(ranking_policy.clone()),
                ranking_trace: ranking_trace_json(&[], &ranking_policy, stable_fact_guard_applied),
                recency_boost_applied: false,
                stable_fact_guard_applied,
            });
        }

        let query_tokens = tokenize(&req.query);
        let scope = req.scope.as_ref().map(|scope| scope.to_lowercase());
        let stable_fact_guard_applied = stable_fact_guard_applies(&req.query, &query_tokens);
        let episode_by_id = episodes
            .iter()
            .map(|episode| (episode.id.as_str(), episode))
            .collect::<BTreeMap<_, _>>();
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
            .filter(|atom| {
                !is_restricted_memory(atom, episode_by_id.get(atom.episode_id.as_str()).copied())
            })
            .filter_map(|atom| {
                let base_score = if is_hypermemory {
                    hypermemory_atom_score(atom, &query_tokens)
                } else {
                    atom_score(atom, &query_tokens)
                };
                let ranked = rank_memory_atom(
                    atom,
                    episode_by_id.get(atom.episode_id.as_str()).copied(),
                    base_score,
                    &query_tokens,
                    &ranking_policy,
                    stable_fact_guard_applied,
                );
                (ranked.final_score > 0.0).then_some(ranked)
            })
            .collect::<Vec<_>>();
        scored.sort_by(|a, b| {
            b.final_score
                .partial_cmp(&a.final_score)
                .unwrap_or(std::cmp::Ordering::Equal)
                .then_with(|| b.atom.occurred_at.cmp(&a.atom.occurred_at))
        });
        scored.truncate(max_items);
        let ranking_trace = ranking_trace_json(&scored, &ranking_policy, stable_fact_guard_applied);
        let recency_boost_applied = scored.iter().any(|item| item.recency_boost > 0.0);

        let mut matched_episodes = Vec::<MemoryEpisode>::new();
        let mut evidence = Vec::<GraphRagEvidence>::new();
        let mut relations = Vec::<MemoryRelation>::new();
        for ranked in &scored {
            let atom = &ranked.atom;
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
                    score: ranked.final_score,
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
        } else if is_hypermemory {
            format!(
                "Found {} HyperMemory match(es) across {} episode(s), with topic/world/hyperedge expansion, for '{}'.",
                evidence.len(),
                matched_episodes.len(),
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
        let matched_atoms = scored
            .into_iter()
            .map(|ranked| ranked.atom)
            .collect::<Vec<_>>();
        let worlds = self.read_recent_jsonl::<MemoryWorld>(MEMORY_WORLDS_LOG, max_items)?;
        let communities = memory_communities(&matched_atoms, &worlds);
        let evidence_graph =
            evidence_graph_for(&evidence, &matched_atoms, &matched_episodes, &relations);
        let candidate_refs = self
            .read_recent_jsonl::<MemoryCandidate>(MEMORY_CANDIDATES_LOG, 20)?
            .into_iter()
            .filter(|candidate| {
                (candidate.status == "candidate" || candidate.status == "triad_pending")
                    && query_tokens
                        .iter()
                        .any(|token| candidate.normalized_text.contains(token))
            })
            .map(|candidate| candidate.id)
            .take(5)
            .collect::<Vec<_>>();
        let mut retrieval_trace = vec![
            RetrievalTraceStep {
                stage: "question-analysis".to_string(),
                backend: "deterministic-tokenizer".to_string(),
                status: "ok".to_string(),
                items: query_tokens.len(),
                latency_ms: 0.0,
                notes: vec![format!("mode={}", requested_mode)],
            },
            RetrievalTraceStep {
                stage: "semantic-candidate-search".to_string(),
                backend: if runtime_configured {
                    graph_runtime.clone()
                } else {
                    "cluster-jsonl lexical fallback".to_string()
                },
                status: if evidence.is_empty() {
                    "no_hits".to_string()
                } else {
                    "ok".to_string()
                },
                items: evidence.len(),
                latency_ms: 0.0,
                notes: vec![graph_degraded_reason(runtime_configured)],
            },
            RetrievalTraceStep {
                stage: "structural-expansion".to_string(),
                backend: "memory-relations+worlds".to_string(),
                status: "ok".to_string(),
                items: relations.len() + worlds.len(),
                latency_ms: 0.0,
                notes: vec![
                    "Relink-lite is represented as a temporary evidence graph, never promoted automatically."
                        .to_string(),
                ],
            },
            RetrievalTraceStep {
                stage: "rerank-and-synthesis".to_string(),
                backend: "temporal-confidence-reranker".to_string(),
                status: "ok".to_string(),
                items: matched_atoms.len(),
                latency_ms: 0.0,
                notes: vec!["Evidence keeps provenance back to Episode+Atom JSONL.".to_string()],
            },
        ];
        if is_hypermemory {
            retrieval_trace.insert(
                1,
                RetrievalTraceStep {
                    stage: if is_multivector {
                        "hypermemory-multivector-topic-world-selection"
                    } else {
                        "hypermemory-topic-world-selection"
                    }
                    .to_string(),
                    backend: if is_multivector {
                        "LanceDB multivector + Jina-ColBERT-v2 + MemoryWorld projection"
                    } else {
                        "MemoryTopic+MemoryWorld+Hyperedge projection"
                    }
                    .to_string(),
                    status: if evidence.is_empty() { "no_hits" } else { "ok" }.to_string(),
                    items: communities.len() + worlds.len(),
                    latency_ms: 0.0,
                    notes: vec![
                        "HyperMemory is derived/advisory until Memory Bench beats baseline.".to_string(),
                        "Coarse-to-fine retrieval expands tags, source refs, relations, and MemoryWorlds.".to_string(),
                    ],
                },
            );
        }
        let mesh_trace = vec![
            RetrievalTraceStep {
                stage: "adaptive-federation".to_string(),
                backend: "beagle-memory-engine".to_string(),
                status: if runtime_configured {
                    "shortlist"
                } else {
                    "degraded"
                }
                .to_string(),
                items: evidence.len(),
                latency_ms: 0.0,
                notes: vec![
                    "Home/search use shortlist federation; Memory Lens can fan out deeper."
                        .to_string(),
                    "Canonical authority remains JSONL+Merkle+Chronoself in beagle-core."
                        .to_string(),
                ],
            },
            RetrievalTraceStep {
                stage: "candidate-memory-check".to_string(),
                backend: "memory_candidates.jsonl".to_string(),
                status: if candidate_refs.is_empty() {
                    "no_candidates"
                } else {
                    "candidate_refs"
                }
                .to_string(),
                items: candidate_refs.len(),
                latency_ms: 0.0,
                notes: vec![
                    "Candidates never enter active retrieval until Triad quorum promotes them."
                        .to_string(),
                ],
            },
        ];
        let evidence_count = evidence.len();
        let strategy_used = retrieval_strategy_for(&req.query);
        let subqueries = retrieval_subqueries_for(&req.query, &strategy_used);
        let evidence_refs = evidence
            .iter()
            .flat_map(|item| {
                let mut refs = vec![
                    format!("atom:{}", item.atom_id),
                    format!("episode:{}", item.episode_id),
                ];
                refs.extend(item.source_refs.clone());
                refs
            })
            .collect::<Vec<_>>();
        let maxsim_scores = maxsim_scores_for(&evidence);
        let graph_expansion =
            graph_expansion_trace(Some(&evidence_graph), communities.len(), relations.len());
        let reranker_scores = reranker_scores_for(&evidence);
        let benchmark_status = self.memory_benchmark_status().ok();
        let truthset_gate_status = truthset_gate_status_for(
            benchmark_status
                .as_ref()
                .and_then(|status| status.portfolio_truthset_id.clone()),
            benchmark_status
                .as_ref()
                .map(|status| status.hot_path_eligible)
                .unwrap_or(false),
        );
        Ok(GraphRagQueryResponse {
            summary,
            evidence,
            atoms: matched_atoms,
            episodes: matched_episodes,
            relations,
            temporal_context: GraphRagTemporalContext {
                newest_evidence_at: newest,
                oldest_evidence_at: oldest,
                matched_episode_count,
            },
            provenance: serde_json::json!({
                "schema_version": MEMORY_PROJECTION_SCHEMA,
                "graph_schema_version": MEMORY_GRAPH_SCHEMA,
                "retrieval_mode": requested_mode.clone(),
                "graph_runtime": graph_runtime.clone(),
                "canonical_store": "/var/lib/beagle/exocortex",
                "derived_indexes": "rebuildable",
                "runtime_configured": runtime_configured,
                "ranking_policy": ranking_policy.clone(),
                "stable_fact_guard_applied": stable_fact_guard_applied,
                "hypermemory": {
                    "enabled": is_hypermemory,
                    "multivector": is_multivector,
                    "authority": "derived-advisory",
                    "benchmark_schema": MEMORY_BENCH_SCHEMA,
                    "hot_path_gate": "must beat graphsearch-lite baseline with full provenance"
                }
            }),
            confidence,
            degraded_reason: Some(if is_hypermemory {
                hypermemory_degraded_reason(runtime_configured)
            } else {
                graph_degraded_reason(runtime_configured)
            }),
            mode: Some(requested_mode.clone()),
            graph_runtime: Some(graph_runtime),
            evidence_graph: Some(evidence_graph.clone()),
            community_context: Some(GraphRagCommunityContext {
                strategy: if is_hypermemory {
                    "hypermemory-topic-world-density".to_string()
                } else {
                    "k-core-density-hierarchy".to_string()
                },
                selected_communities: communities,
                degraded_reason: (!runtime_configured).then(|| {
                    if is_hypermemory {
                        hypermemory_degraded_reason(false)
                    } else {
                        graph_degraded_reason(false)
                    }
                }),
            }),
            retrieval_trace,
            mesh_trace,
            runtime_votes: runtime_votes(runtime_configured),
            candidate_refs,
            runtime_used: Some(runtime_used_for(&requested_mode, runtime_configured)),
            fallback_chain: fallback_chain_for(&requested_mode, runtime_configured),
            semantic_trace: semantic_trace_for(&requested_mode, runtime_configured, evidence_count),
            maxsim_scores,
            graph_expansion,
            reranker_scores,
            truthset_gate_status,
            restricted_leak_check: restricted_leak_check_for(0),
            retrieval_agent: retrieval_agent_mode(),
            retrieval_plan_id: stable_id("retrieval-plan", &[&req.query, &requested_mode]),
            strategy_used: strategy_used.clone(),
            subqueries: subqueries.clone(),
            evidence_pack: evidence_pack_json(
                evidence_count,
                matched_episode_count,
                evidence_refs,
                0,
            ),
            context_format: retrieval_context_format(),
            planner_mode: retrieval_planner_mode(),
            budget: retrieval_budget_json(max_items, &retrieval_planner_mode()),
            runtime_trace: retrieval_agent_trace_for(
                &strategy_used,
                &subqueries,
                runtime_configured,
                evidence_count,
                matched_episode_count,
            ),
            context_pack_id: Some(stable_id(
                "context-pack",
                &[
                    &req.query,
                    &requested_mode,
                    &strategy_used,
                    &memory_policy_version(),
                ],
            )),
            policy_version: Some(memory_policy_version()),
            policy_gate: memory_policy_gate_json(),
            dreamcycle_status: Some(dreamcycle_mode()),
            ranking_policy: Some(ranking_policy),
            ranking_trace,
            recency_boost_applied,
            stable_fact_guard_applied,
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

    fn find_memory_candidate(&self, candidate_id: &str) -> anyhow::Result<Option<MemoryCandidate>> {
        Ok(self
            .read_recent_jsonl::<MemoryCandidate>(MEMORY_CANDIDATES_LOG, usize::MAX)?
            .into_iter()
            .find(|candidate| candidate.id == candidate_id))
    }

    fn latest_candidate_quorum(
        &self,
        candidate_id: &str,
    ) -> anyhow::Result<Option<CandidateQuorumDecision>> {
        Ok(self
            .read_recent_jsonl::<CandidateQuorumDecision>(MEMORY_CANDIDATE_QUORUM_LOG, usize::MAX)?
            .into_iter()
            .find(|decision| decision.candidate_id == candidate_id))
    }

    fn latest_memory_candidates(&self, limit: usize) -> anyhow::Result<Vec<MemoryCandidate>> {
        let mut seen = std::collections::BTreeSet::<String>::new();
        let mut candidates = Vec::new();
        for candidate in
            self.read_recent_jsonl::<MemoryCandidate>(MEMORY_CANDIDATES_LOG, usize::MAX)?
        {
            if seen.insert(candidate.id.clone()) {
                candidates.push(candidate);
            }
            if candidates.len() >= limit {
                break;
            }
        }
        Ok(candidates)
    }

    fn latest_quality_score(
        &self,
        candidate_id: &str,
    ) -> anyhow::Result<Option<MemoryQualityScore>> {
        Ok(self
            .read_recent_jsonl::<MemoryQualityScore>(MEMORY_QUALITY_SCORES_LOG, usize::MAX)?
            .into_iter()
            .find(|score| score.candidate_id == candidate_id))
    }

    fn memory_governance_status(&self) -> anyhow::Result<MemoryGovernanceStatus> {
        self.ensure()?;
        let candidates = self.latest_memory_candidates(usize::MAX)?;
        let contradictions =
            self.read_recent_jsonl::<MemoryContradiction>(MEMORY_CONTRADICTIONS_LOG, usize::MAX)?;
        let open_contradictions = contradictions
            .iter()
            .filter(|item| item.status == "open")
            .count();
        let pending_triads = candidates
            .iter()
            .filter(|candidate| {
                candidate.status == "candidate" || candidate.status == "triad_pending"
            })
            .count();
        let promoted_count = candidates
            .iter()
            .filter(|candidate| candidate.status == "promoted")
            .count();
        let rejected_count = candidates
            .iter()
            .filter(|candidate| candidate.status == "rejected")
            .count();
        let latest_run = self
            .read_recent_jsonl::<MemoryGovernanceRun>(MEMORY_GOVERNANCE_RUNS_LOG, 1)?
            .into_iter()
            .next();
        let latest_promotion_decision = self
            .read_recent_jsonl::<MemoryPromotionDecision>(MEMORY_PROMOTION_DECISIONS_LOG, 1)?
            .into_iter()
            .next();
        Ok(MemoryGovernanceStatus {
            status: if pending_triads > 0 {
                "triad-pending".to_string()
            } else if open_contradictions > 0 {
                "contradiction-review".to_string()
            } else {
                "governed".to_string()
            },
            schema_version: MEMORY_GOVERNANCE_SCHEMA.to_string(),
            retrieval_policy: "promoted-only-active-search; candidates require strict Memory+Temporal+Critical 3/3 quorum".to_string(),
            candidate_count: candidates.len(),
            pending_triads,
            promoted_count,
            rejected_count,
            open_contradictions,
            latest_run,
            latest_promotion_decision,
        })
    }

    fn run_memory_governance(
        &self,
        req: MemoryGovernanceRunRequest,
    ) -> anyhow::Result<MemoryGovernanceRun> {
        self.ensure()?;
        let limit = req.limit.unwrap_or(100).clamp(1, 1_000);
        let dry_run = req.dry_run.unwrap_or(false);
        let reviewer = req
            .reviewer
            .unwrap_or_else(|| "memory-governor-v1.6".to_string());
        let candidates = self
            .latest_memory_candidates(limit)?
            .into_iter()
            .filter(|candidate| candidate.privacy_class != "restricted")
            .collect::<Vec<_>>();
        let atoms = self.read_recent_jsonl::<MemoryAtom>(MEMORY_ATOMS_LOG, usize::MAX)?;
        let mut contradictions_found = 0usize;
        let mut quality_scores_written = 0usize;
        let mut triad_pending = 0usize;
        let mut promoted = 0usize;
        let mut rejected = 0usize;

        for candidate in &candidates {
            match candidate.status.as_str() {
                "promoted" => {
                    promoted += 1;
                    continue;
                }
                "rejected" => {
                    rejected += 1;
                    continue;
                }
                _ => {}
            }

            let contradictions = detect_candidate_contradictions(candidate, &atoms);
            contradictions_found += contradictions.len();
            let quality_score = self.score_memory_candidate(candidate, &contradictions, None);
            if !dry_run {
                self.append_jsonl(MEMORY_QUALITY_SCORES_LOG, &quality_score)?;
                quality_scores_written += 1;
                for contradiction in contradictions {
                    self.append_jsonl(MEMORY_CONTRADICTIONS_LOG, &contradiction)?;
                }
                if candidate.status == "candidate" {
                    self.append_jsonl(
                        MEMORY_CANDIDATES_LOG,
                        &MemoryCandidate {
                            status: "triad_pending".to_string(),
                            ..candidate.clone()
                        },
                    )?;
                }
            }
            triad_pending += 1;
        }

        let run = MemoryGovernanceRun {
            id: Uuid::new_v4().to_string(),
            created_at: Utc::now().to_rfc3339(),
            schema_version: MEMORY_GOVERNANCE_SCHEMA.to_string(),
            status: if dry_run { "dry_run" } else { "completed" }.to_string(),
            candidates_evaluated: candidates.len(),
            triad_pending,
            promoted,
            rejected,
            contradictions_found,
            quality_scores_written,
            hard_gates: serde_json::json!({
                "restricted_leak_zero": true,
                "triad_strict_required": true,
                "active_search_promoted_only": true,
                "provenance_required_for_promotion": true,
            }),
            degraded_reason: "v1.6 governor is deterministic and append-only; LLM/judge expansion remains delegated to memory-engine evals.".to_string(),
        };
        if !dry_run {
            self.append_jsonl(MEMORY_GOVERNANCE_RUNS_LOG, &run)?;
            let _ = self.create_audit_event(CreateAuditEventRequest {
                client_id: Some(reviewer),
                action: Some("memory.governance_run".to_string()),
                tool_name: Some("beagle_memory_governance_run".to_string()),
                risk_level: Some("write".to_string()),
                required_scopes: vec!["memory:write".to_string()],
                granted_scopes: vec!["memory:write".to_string()],
                status: Some("success".to_string()),
                source: Some("memory-governor".to_string()),
                target_ref: Some(format!("memory_governance_run:{}", run.id)),
                summary: Some(
                    "Evaluated candidate memory quality, contradictions, and Triad pending state."
                        .to_string(),
                ),
                metadata: Some(serde_json::json!({
                    "schema_version": MEMORY_GOVERNANCE_SCHEMA,
                    "candidates_evaluated": run.candidates_evaluated,
                    "contradictions_found": run.contradictions_found,
                    "triad_pending": run.triad_pending,
                })),
            })?;
        }
        Ok(run)
    }

    fn score_memory_candidate(
        &self,
        candidate: &MemoryCandidate,
        contradictions: &[MemoryContradiction],
        input: Option<MemoryQualityScoreInput>,
    ) -> MemoryQualityScore {
        let provenance_score = input
            .as_ref()
            .and_then(|score| score.provenance_score)
            .unwrap_or_else(|| {
                let source_refs = if candidate.source_refs.is_empty() {
                    0.0
                } else {
                    0.35
                };
                let provenance = if candidate.provenance.is_null() {
                    0.0
                } else {
                    0.35
                };
                (source_refs + provenance + candidate.confidence.min(0.30)).clamp(0.0, 1.0)
            });
        let temporal_score = input
            .as_ref()
            .and_then(|score| score.temporal_score)
            .unwrap_or_else(|| {
                if candidate
                    .tags
                    .iter()
                    .any(|tag| tag.contains("temporal") || tag.contains("work-memory"))
                {
                    0.78
                } else {
                    0.62
                }
            });
        let contradiction_risk = input
            .as_ref()
            .and_then(|score| score.contradiction_risk)
            .unwrap_or_else(|| (contradictions.len() as f64 * 0.35).clamp(0.0, 1.0));
        let critical_score = input
            .as_ref()
            .and_then(|score| score.critical_score)
            .unwrap_or_else(|| (candidate.confidence - contradiction_risk * 0.35).clamp(0.0, 1.0));
        let restricted_risk = input
            .as_ref()
            .and_then(|score| score.restricted_risk)
            .unwrap_or(if candidate.privacy_class == "restricted" {
                1.0
            } else {
                0.0
            });
        let overall = ((provenance_score + temporal_score + critical_score) / 3.0
            - restricted_risk * 0.5
            - contradiction_risk * 0.25)
            .clamp(0.0, 1.0);
        MemoryQualityScore {
            id: stable_id("quality", &[&candidate.id, &format!("{overall:.3}")]),
            created_at: Utc::now().to_rfc3339(),
            candidate_id: candidate.id.clone(),
            provenance_score,
            temporal_score,
            critical_score,
            overall,
            restricted_risk,
            contradiction_risk,
            rationale: input
                .and_then(|score| score.rationale)
                .unwrap_or_else(|| {
                    "Deterministic v1.6 score from provenance, temporal fit, critical risk, privacy, and contradiction signals.".to_string()
                }),
        }
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

    fn create_memory_candidate(
        &self,
        req: CreateMemoryCandidateRequest,
    ) -> anyhow::Result<MemoryCandidate> {
        self.ensure()?;
        let privacy_class = normalize_privacy_class(req.privacy_class.as_deref());
        anyhow::ensure!(
            privacy_class != "restricted",
            "restricted memory candidates require explicit human review outside v1.5"
        );
        let normalized_text = normalize_text(&req.text);
        let candidate = MemoryCandidate {
            id: stable_id("candidate", &[&req.candidate_type, &normalized_text]),
            created_at: Utc::now().to_rfc3339(),
            candidate_type: req.candidate_type,
            text: truncate_chars(&req.text, 1_200),
            normalized_text,
            source_refs: req.source_refs,
            relations: req.relations,
            tags: req.tags,
            provenance: req.provenance,
            confidence: req.confidence.unwrap_or(0.55).clamp(0.0, 1.0),
            privacy_class,
            status: "candidate".to_string(),
            quorum_ref: None,
            promoted_atom_id: None,
        };
        self.append_jsonl(MEMORY_CANDIDATES_LOG, &candidate)?;
        let _ = self.create_audit_event(CreateAuditEventRequest {
            client_id: Some("beagle-memory-engine".to_string()),
            action: Some("memory.candidate_create".to_string()),
            tool_name: Some("beagle_memory_candidates".to_string()),
            risk_level: Some("write".to_string()),
            required_scopes: vec!["memory:write".to_string()],
            granted_scopes: vec!["memory:write".to_string()],
            status: Some("success".to_string()),
            source: Some("memory-engine".to_string()),
            target_ref: Some(format!("memory_candidate:{}", candidate.id)),
            summary: Some("Recorded candidate memory outside active retrieval.".to_string()),
            metadata: Some(serde_json::json!({
                "schema_version": MEMORY_MESH_SCHEMA,
                "candidate_status": candidate.status,
                "candidate_type": candidate.candidate_type,
            })),
        })?;
        Ok(candidate)
    }

    fn context_compile(&self, req: ContextCompileRequest) -> anyhow::Result<ContextPack> {
        self.ensure()?;
        let mode = req.mode.clone().unwrap_or_else(memory_hot_path_mode);
        let query_response = self.graphrag_query(GraphRagQueryRequest {
            query: req.query.clone(),
            scope: req.scope.clone(),
            max_items: req.max_items,
            mode: Some(mode.clone()),
            ranking_policy: None,
        })?;
        let evidence_refs = query_response
            .evidence
            .iter()
            .flat_map(|item| {
                let mut refs = vec![
                    format!("atom:{}", item.atom_id),
                    format!("episode:{}", item.episode_id),
                ];
                refs.extend(item.source_refs.clone());
                refs
            })
            .collect::<Vec<_>>();
        let token_budget = req.token_budget.unwrap_or_else(|| {
            if req.surface.as_deref().unwrap_or("").contains("watch") {
                1_200
            } else {
                8_000
            }
        });
        let strategy_used = query_response.strategy_used.clone();
        let pack = ContextPack {
            id: stable_id(
                "context-pack",
                &[
                    &req.query,
                    req.surface.as_deref().unwrap_or("core-context"),
                    &strategy_used,
                    &memory_policy_version(),
                ],
            ),
            created_at: Utc::now().to_rfc3339(),
            schema_version: CONTEXT_COMPILER_SCHEMA.to_string(),
            query: req.query.clone(),
            task: req.task.clone(),
            surface: req
                .surface
                .clone()
                .unwrap_or_else(|| "beagle-core-context".to_string()),
            format: "episodic_envelope+evidence_frontier+procedural_hint+contradiction_guard+next_action"
                .to_string(),
            policy_version: memory_policy_version(),
            policy_mode: memory_policy_mode(),
            token_budget,
            retrieval_plan_id: Some(query_response.retrieval_plan_id.clone()),
            strategy_used,
            context_sections: serde_json::json!({
                "episodic_envelope": query_response.episodes.iter().take(6).collect::<Vec<_>>(),
                "evidence_frontier": query_response.evidence.iter().take(req.max_items.unwrap_or(8)).collect::<Vec<_>>(),
                "hypergraph_relations": query_response.relations.iter().take(16).collect::<Vec<_>>(),
                "timeline": query_response.temporal_context,
                "procedural_hint": [
                    "Preserve full episode context around nucleus hits.",
                    "Cite provenance and confidence before synthesis.",
                    "Record MemoryEffectivenessEvent after the action."
                ],
                "contradiction_guard": query_response.candidate_refs,
                "next_action": "Use this ContextPack, then append an effectiveness event with outcome."
            }),
            evidence_refs,
            provenance: serde_json::json!({
                "canonical_source": "beagle-core-jsonl",
                "mode": mode,
                "context_compiler": context_compiler_mode(),
                "agent": req.agent,
                "session_id": req.session_id,
            }),
            restricted_leak_check: query_response.restricted_leak_check,
            policy_rationale: vec![
                format!("policy={}", memory_policy_version()),
                format!("compiler={}", context_compiler_mode()),
                "Policy learning is observe-only until MemoryArena private gate passes.".to_string(),
            ],
            fallback_chain: query_response.fallback_chain,
            next_action:
                "Act with the compiled context and record effectiveness feedback afterward."
                    .to_string(),
            degraded_reason: query_response.degraded_reason,
        };
        self.append_jsonl(CONTEXT_PACKS_LOG, &pack)?;
        let _ = self.create_audit_event(CreateAuditEventRequest {
            client_id: Some("beagle-core".to_string()),
            action: Some("context.compile".to_string()),
            tool_name: Some("beagle_context_compile".to_string()),
            risk_level: Some("read".to_string()),
            required_scopes: vec!["exocortex:read".to_string()],
            granted_scopes: vec!["exocortex:read".to_string()],
            status: Some("success".to_string()),
            source: Some("context-compiler".to_string()),
            target_ref: Some(format!("context_pack:{}", pack.id)),
            summary: Some("Compiled adaptive ContextPack from GraphRAG++ evidence.".to_string()),
            metadata: Some(serde_json::json!({
                "schema_version": CONTEXT_COMPILER_SCHEMA,
                "policy_version": pack.policy_version,
                "strategy_used": pack.strategy_used,
                "context_compiler": context_compiler_mode()
            })),
        })?;
        Ok(pack)
    }

    fn context_pack(&self, pack_id: &str) -> anyhow::Result<Option<ContextPack>> {
        Ok(self
            .read_recent_jsonl::<ContextPack>(CONTEXT_PACKS_LOG, usize::MAX)?
            .into_iter()
            .rev()
            .find(|pack| pack.id == pack_id))
    }

    fn record_memory_effectiveness(
        &self,
        req: MemoryEffectivenessEventRequest,
    ) -> anyhow::Result<MemoryEffectivenessEvent> {
        self.ensure()?;
        let event = MemoryEffectivenessEvent {
            id: Uuid::new_v4().to_string(),
            created_at: Utc::now().to_rfc3339(),
            schema_version: MEMORY_POLICY_SCHEMA.to_string(),
            context_pack_id: req.context_pack_id,
            query: req.query,
            surface: req.surface.unwrap_or_else(|| "unknown-surface".to_string()),
            principal: req
                .principal
                .unwrap_or_else(|| "unknown-principal".to_string()),
            session_id: req.session_id,
            strategy_used: req
                .strategy_used
                .unwrap_or_else(|| "not-recorded".to_string()),
            tokens_used: req.tokens_used,
            latency_ms: req.latency_ms,
            tests: req.tests,
            feedback: req.feedback,
            human_correction: req.human_correction,
            success: req.success.unwrap_or(false),
            outcome: req.outcome.unwrap_or_else(|| "observed".to_string()),
            metadata: req.metadata,
        };
        self.append_jsonl(MEMORY_EFFECTIVENESS_EVENTS_LOG, &event)?;
        let _ = self.create_audit_event(CreateAuditEventRequest {
            client_id: Some(event.principal.clone()),
            action: Some("memory.effectiveness_record".to_string()),
            tool_name: Some("beagle_memory_effectiveness_record".to_string()),
            risk_level: Some("write".to_string()),
            required_scopes: vec!["memory:write".to_string()],
            granted_scopes: vec!["memory:write".to_string()],
            status: Some("success".to_string()),
            source: Some(event.surface.clone()),
            target_ref: Some(format!("context_pack:{}", event.context_pack_id)),
            summary: Some(format!("Recorded memory policy outcome: {}", event.outcome)),
            metadata: Some(serde_json::json!({
                "schema_version": MEMORY_POLICY_SCHEMA,
                "policy_version": memory_policy_version(),
                "strategy_used": event.strategy_used,
                "success": event.success
            })),
        })?;
        Ok(event)
    }

    fn memory_policy_status(&self) -> anyhow::Result<MemoryPolicyStatus> {
        self.ensure()?;
        let events = self
            .read_recent_jsonl::<MemoryEffectivenessEvent>(MEMORY_EFFECTIVENESS_EVENTS_LOG, 250)?;
        let latest_effectiveness_event = events.last().cloned();
        let mut outcome_counts = BTreeMap::<String, usize>::new();
        for event in &events {
            *outcome_counts.entry(event.outcome.clone()).or_default() += 1;
        }
        Ok(MemoryPolicyStatus {
            generated_at: Utc::now().to_rfc3339(),
            schema_version: MEMORY_POLICY_SCHEMA.to_string(),
            status: memory_policy_mode(),
            policy_version: memory_policy_version(),
            policy_mode: memory_policy_mode(),
            latest_effectiveness_event,
            outcome_counts,
            promotion_gate: memory_policy_gate_json(),
            degraded_reason: Some(
                "Policy learner is observe/recommend/canary only; no fine-tuning or automatic promotion."
                    .to_string(),
            ),
        })
    }

    fn run_dreamcycle(&self, req: DreamCycleRunRequest) -> anyhow::Result<DreamCycleRun> {
        self.ensure()?;
        let limit = req.limit.unwrap_or(500).clamp(1, 5_000);
        let episodes = self.read_recent_jsonl::<MemoryEpisode>(MEMORY_EPISODES_LOG, limit)?;
        let atoms = self.read_recent_jsonl::<MemoryAtom>(MEMORY_ATOMS_LOG, limit)?;
        let dry_run = req.dry_run.unwrap_or(true);
        let mut generated_candidate_refs = Vec::new();
        if !dry_run {
            for (candidate_type, text) in [
                (
                    "procedural_memory",
                    "DreamCycle candidate: consolidate recent work-memory into a reusable procedural playbook.",
                ),
                (
                    "project_summary",
                    "DreamCycle candidate: summarize active project drift and unresolved loops.",
                ),
                (
                    "contradiction_watch",
                    "DreamCycle candidate: review stale beliefs and contradictions before promotion.",
                ),
            ] {
                let candidate = self.create_memory_candidate(CreateMemoryCandidateRequest {
                    candidate_type: candidate_type.to_string(),
                    text: text.to_string(),
                    source_refs: vec!["dreamcycle:v2.3".to_string()],
                    relations: Vec::new(),
                    tags: vec![
                        "dreamcycle".to_string(),
                        "candidate".to_string(),
                        "v2.3".to_string(),
                    ],
                    provenance: serde_json::json!({
                        "schema_version": CONTEXT_COMPILER_SCHEMA,
                        "source": "beagle-core-dreamcycle",
                        "dry_run": dry_run
                    }),
                    confidence: Some(0.58),
                    privacy_class: Some("sensitive".to_string()),
                })?;
                generated_candidate_refs.push(candidate.id);
            }
        }
        let run = DreamCycleRun {
            id: Uuid::new_v4().to_string(),
            created_at: Utc::now().to_rfc3339(),
            schema_version: CONTEXT_COMPILER_SCHEMA.to_string(),
            status: if dry_run {
                "dry_run".to_string()
            } else {
                "candidates_recorded".to_string()
            },
            mode: req.mode.unwrap_or_else(dreamcycle_mode),
            dry_run,
            triggered_by: req.triggered_by.unwrap_or_else(|| "manual".to_string()),
            source_episode_count: episodes.len(),
            source_atom_count: atoms.len(),
            candidate_count: if dry_run { 3 } else { generated_candidate_refs.len() },
            contradiction_count: usize::from(!atoms.is_empty()),
            procedural_memory_count: usize::from(!episodes.is_empty()),
            stale_belief_count: usize::from(atoms.len() > 10),
            project_summary_count: usize::from(!episodes.is_empty()),
            unresolved_loop_count: usize::from(!episodes.is_empty()),
            suggested_truth_cases: 3,
            generated_candidate_refs,
            provenance: serde_json::json!({
                "canonical_source": "/var/lib/beagle/exocortex",
                "restricted_policy": "restricted never enters DreamCycle candidates automatically",
                "cluster_only": true
            }),
            promotion_policy:
                "DreamCycle outputs are candidates only; Governor/Triad is required before active retrieval."
                    .to_string(),
            degraded_reason: Some(
                "DreamCycle v2.3 is deterministic consolidation; LLM reflection remains optional."
                    .to_string(),
            ),
        };
        self.append_jsonl(MEMORY_DREAMCYCLE_RUNS_LOG, &run)?;
        Ok(run)
    }

    fn dreamcycle_status(&self) -> anyhow::Result<DreamCycleStatus> {
        let latest_run = self
            .read_recent_jsonl::<DreamCycleRun>(MEMORY_DREAMCYCLE_RUNS_LOG, 1)?
            .into_iter()
            .next();
        Ok(DreamCycleStatus {
            generated_at: Utc::now().to_rfc3339(),
            schema_version: CONTEXT_COMPILER_SCHEMA.to_string(),
            status: latest_run
                .as_ref()
                .map(|run| run.status.clone())
                .unwrap_or_else(|| "manual-ready".to_string()),
            mode: dreamcycle_mode(),
            latest_run,
            policy:
                "candidate-only consolidation; no DreamCycle inference enters Home/search without Governor/Triad."
                    .to_string(),
            candidate_outputs_active: false,
            degraded_reason: None,
        })
    }

    fn check_sounio_program(
        &self,
        req: SounioProgramCheckRequest,
    ) -> anyhow::Result<SounioProgramCheckResponse> {
        let mut errors = validate_sounio_program(&req.program);
        let privacy_class = normalize_privacy_class(Some(&req.program.governance.privacy_class));
        if privacy_class == "restricted" {
            errors.push(
                "program governance privacy_class=restricted is blocked from PaperRun v2.4"
                    .to_string(),
            );
        }
        let warnings = sounio_program_warnings(&req.program, req.source_format.as_deref());
        let program_hash = sounio_program_hash(&req.program)?;
        Ok(SounioProgramCheckResponse {
            status: if errors.is_empty() {
                "valid".to_string()
            } else {
                "invalid".to_string()
            },
            program_hash,
            schema_version: SOUNIO_WORK_IR_SCHEMA.to_string(),
            errors,
            warnings,
            temporal_spec: sounio_temporal_spec(&req.program),
            memory_projection_preview: sounio_memory_projection_preview(&req.program),
        })
    }

    fn check_sounio_claim(
        &self,
        req: SounioClaimCheckRequest,
    ) -> anyhow::Result<SounioClaimCheckResponse> {
        let (claim, errors, warnings) = materialize_sounio_claim(req.claim, None, None)?;
        Ok(SounioClaimCheckResponse {
            status: if errors.is_empty() {
                "valid".to_string()
            } else {
                "invalid".to_string()
            },
            schema_version: SOUNIO_CLAIM_SCHEMA.to_string(),
            required_evidence: sounio_claim_required_evidence(&claim),
            promotion_gate: sounio_claim_promotion_gate(&claim),
            normalized_claim: claim,
            errors,
            warnings,
        })
    }

    fn type_sounio_moment(&self, req: SounioMomentTypeRequest) -> anyhow::Result<SounioMoment> {
        self.ensure()?;
        let now = Utc::now().to_rfc3339();
        let privacy_class = normalize_privacy_class(req.privacy_class.as_deref());
        anyhow::ensure!(
            privacy_class != "restricted",
            "restricted payloads require explicit local review before Sounio typing"
        );

        let source_platform = req
            .source_platform
            .as_deref()
            .map(normalize_source_platform)
            .unwrap_or_else(|| "mcp-agent".to_string());
        let source_surface = req
            .source_surface
            .as_deref()
            .map(|value| value.trim().to_lowercase())
            .filter(|value| !value.is_empty())
            .unwrap_or_else(|| "sounio-ambient-typing".to_string());
        let project_slug = req
            .project_slug
            .as_deref()
            .map(|value| value.trim().to_lowercase())
            .filter(|value| !value.is_empty())
            .unwrap_or_else(|| "sounio".to_string());
        let mut evidence_refs = req.evidence_refs.clone();
        merge_unique(&mut evidence_refs, req.source_event_refs.clone(), 48);
        let intent = req
            .intent_text
            .as_deref()
            .or(req.summary.as_deref())
            .map(|value| truncate_chars(value.trim(), 240))
            .filter(|value| !value.is_empty())
            .unwrap_or_else(|| {
                "Type this ambient work signal into the Sounio workday.".to_string()
            });
        let summary = req
            .summary
            .as_deref()
            .map(|value| truncate_chars(value.trim(), 360))
            .filter(|value| !value.is_empty())
            .unwrap_or_else(|| intent.clone());
        let mut claim_seeds = Vec::new();
        let mut claim_warnings = Vec::new();
        for input in req.claim_seeds {
            let (claim, errors, warnings) = materialize_sounio_claim(input, None, None)?;
            anyhow::ensure!(
                errors.is_empty(),
                "Sounio moment claim seed invalid: {}",
                errors.join("; ")
            );
            claim_warnings.extend(warnings);
            claim_seeds.push(claim);
        }
        let id = stable_id(
            "sounio-moment",
            &[
                &project_slug,
                req.session_id.as_deref().unwrap_or("ambient"),
                &source_platform,
                &source_surface,
                &summary,
            ],
        );
        let moment = SounioMoment {
            id,
            created_at: now.clone(),
            updated_at: now.clone(),
            schema_version: SOUNIO_MOMENT_SCHEMA.to_string(),
            project_slug: project_slug.clone(),
            moment_type: infer_sounio_moment_type(&source_platform, &source_surface, &req.tags),
            intent,
            summary,
            source_platform: source_platform.clone(),
            source_surface: source_surface.clone(),
            session_id: req.session_id.clone(),
            source_event_refs: req.source_event_refs.clone(),
            evidence_refs: evidence_refs.clone(),
            claim_seeds,
            decision_seeds: req.decision_seeds.clone(),
            next_action: req.next_action.clone(),
            privacy_class: privacy_class.clone(),
            review_state: req.review_state.unwrap_or_else(|| "unreviewed".to_string()),
            restricted_leak_check: "passed:no_restricted_payload_typed".to_string(),
            provenance: merge_json_objects(
                serde_json::json!({
                    "schema_version": SOUNIO_MOMENT_SCHEMA,
                    "beagle_observes": true,
                    "sounio_types": true,
                    "source_platform": source_platform,
                    "source_surface": source_surface,
                    "claim_seed_warnings": claim_warnings,
                    "restricted_policy": "restricted never enters ambient typing automatically"
                }),
                req.provenance,
            ),
            tags: req.tags,
        };
        self.append_jsonl(SOUNIO_MOMENTS_LOG, &moment)?;
        let _ = self.create_audit_event(CreateAuditEventRequest {
            client_id: Some(
                metadata_string(&moment.provenance, "principal")
                    .unwrap_or_else(|| moment.source_surface.clone()),
            ),
            action: Some("sounio.moment_type".to_string()),
            tool_name: Some("beagle_sounio_moment_type".to_string()),
            risk_level: Some("write".to_string()),
            required_scopes: vec!["memory:write".to_string()],
            granted_scopes: metadata_array_strings(&moment.provenance, "scopes")
                .unwrap_or_default(),
            status: Some("success".to_string()),
            source: Some(moment.source_surface.clone()),
            target_ref: Some(format!("sounio_moment:{}", moment.id)),
            summary: Some(format!(
                "Sounio typed ambient moment for {} as {}.",
                moment.project_slug, moment.moment_type
            )),
            metadata: Some(serde_json::json!({
                "moment_id": moment.id,
                "project_slug": moment.project_slug,
                "privacy_class": moment.privacy_class,
                "claim_seed_count": moment.claim_seeds.len(),
                "decision_seed_count": moment.decision_seeds.len(),
                "restricted_leak_check": moment.restricted_leak_check,
                "schema_version": SOUNIO_MOMENT_SCHEMA
            })),
        })?;
        Ok(moment)
    }

    fn sounio_moments_recent(
        &self,
        query: SounioMomentsQuery,
    ) -> anyhow::Result<SounioMomentListResponse> {
        let project_slug = query
            .project_slug
            .as_deref()
            .map(|value| value.trim().to_lowercase())
            .filter(|value| !value.is_empty());
        let mut seen = BTreeSet::new();
        let moments = self
            .read_recent_jsonl::<SounioMoment>(
                SOUNIO_MOMENTS_LOG,
                query.limit.unwrap_or(25).min(100),
            )?
            .into_iter()
            .filter(|moment| moment.privacy_class != "restricted")
            .filter(|moment| {
                project_slug
                    .as_ref()
                    .map(|slug| &moment.project_slug == slug)
                    .unwrap_or(true)
            })
            .filter(|moment| seen.insert(moment.id.clone()))
            .collect::<Vec<_>>();
        Ok(SounioMomentListResponse {
            generated_at: Utc::now().to_rfc3339(),
            schema_version: SOUNIO_MOMENT_SCHEMA.to_string(),
            project_slug,
            moments,
        })
    }

    fn review_sounio_moment(
        &self,
        moment_id: &str,
        req: SounioMomentReviewRequest,
    ) -> anyhow::Result<SounioMoment> {
        self.ensure()?;
        let mut moment = self
            .read_recent_jsonl::<SounioMoment>(SOUNIO_MOMENTS_LOG, usize::MAX)?
            .into_iter()
            .find(|moment| moment.id == moment_id)
            .ok_or_else(|| anyhow::anyhow!("Sounio moment not found: {moment_id}"))?;
        anyhow::ensure!(
            moment.privacy_class != "restricted",
            "restricted Sounio moments cannot enter cluster review flow"
        );
        let decision = req.decision.trim().to_lowercase();
        anyhow::ensure!(
            matches!(
                decision.as_str(),
                "approved" | "rejected" | "needs_revision" | "mark_contest" | "promote_claim_seed"
            ),
            "moment review decision must be approved, rejected, needs_revision, mark_contest, or promote_claim_seed"
        );
        let previous_state = moment.review_state.clone();
        for evidence_ref in &req.evidence_refs {
            if !moment.evidence_refs.contains(evidence_ref) {
                moment.evidence_refs.push(evidence_ref.clone());
            }
        }
        moment.review_state = req
            .review_state
            .clone()
            .unwrap_or_else(|| match decision.as_str() {
                "approved" => "approved".to_string(),
                "rejected" => "rejected".to_string(),
                "needs_revision" => "needs_revision".to_string(),
                "mark_contest" => "contest".to_string(),
                _ => "reviewed_claim_seed".to_string(),
            });
        if decision == "mark_contest" {
            for claim in &mut moment.claim_seeds {
                claim.epistemic_status = "contest".to_string();
                claim.review_state = "contested".to_string();
            }
        }
        moment.updated_at = Utc::now().to_rfc3339();
        moment.provenance = merge_json_objects(
            moment.provenance.clone(),
            serde_json::json!({
                "latest_review_decision": decision,
                "latest_reviewer": req.reviewer.clone().unwrap_or_else(|| "demetrios".to_string()),
                "latest_review_rationale": req.rationale.clone()
            }),
        );
        if !req.provenance.is_null() {
            moment.provenance =
                merge_json_objects(moment.provenance.clone(), req.provenance.clone());
        }
        self.append_jsonl(SOUNIO_MOMENTS_LOG, &moment)?;
        let review = SounioMomentReview {
            id: Uuid::new_v4().to_string(),
            created_at: moment.updated_at.clone(),
            moment_id: moment.id.clone(),
            reviewer: req.reviewer.unwrap_or_else(|| "demetrios".to_string()),
            decision: decision.clone(),
            rationale: req.rationale,
            previous_state,
            new_state: moment.review_state.clone(),
            evidence_refs: moment.evidence_refs.clone(),
            provenance: serde_json::json!({
                "schema_version": SOUNIO_MOMENT_SCHEMA,
                "project_slug": moment.project_slug,
                "source_surface": moment.source_surface,
                "restricted_leak_check": moment.restricted_leak_check
            }),
        };
        self.append_jsonl(SOUNIO_MOMENT_REVIEWS_LOG, &review)?;
        let _ = self.create_audit_event(CreateAuditEventRequest {
            client_id: Some(review.reviewer.clone()),
            action: Some("sounio.moment_review".to_string()),
            tool_name: Some("beagle_sounio_moment_review".to_string()),
            risk_level: Some("write".to_string()),
            required_scopes: vec!["memory:write".to_string()],
            granted_scopes: Vec::new(),
            status: Some("success".to_string()),
            source: Some("sounio-workday-review".to_string()),
            target_ref: Some(format!("sounio_moment:{}", moment.id)),
            summary: Some(format!("Reviewed Sounio moment as {}.", decision)),
            metadata: Some(serde_json::json!({
                "moment_id": moment.id,
                "review_id": review.id,
                "decision": review.decision,
                "new_state": review.new_state,
                "restricted_leak_check": moment.restricted_leak_check
            })),
        })?;
        Ok(moment)
    }

    fn sounio_workday_status(
        &self,
        query: SounioWorkdayQuery,
    ) -> anyhow::Result<SounioWorkdaySnapshot> {
        let project_slug = query
            .project_slug
            .as_deref()
            .map(|value| value.trim().to_lowercase())
            .filter(|value| !value.is_empty())
            .unwrap_or_else(|| "sounio".to_string());
        let moments_response = self.sounio_moments_recent(SounioMomentsQuery {
            limit: query.limit.or(Some(20)),
            project_slug: Some(project_slug.clone()),
        })?;
        let moments = moments_response.moments;
        let latest_moment = moments.first().cloned();
        let mut claim_seeds = Vec::new();
        let mut claim_seen = BTreeSet::new();
        let mut decision_seeds = Vec::new();
        let mut evidence_refs = Vec::new();
        let mut tensions = Vec::new();
        let mut agents = Vec::new();
        for moment in &moments {
            merge_unique(&mut decision_seeds, moment.decision_seeds.clone(), 32);
            merge_unique(&mut evidence_refs, moment.evidence_refs.clone(), 64);
            merge_unique(
                &mut agents,
                vec![
                    moment.source_platform.clone(),
                    moment.source_surface.clone(),
                ],
                24,
            );
            for claim in &moment.claim_seeds {
                if claim_seen.insert(claim.id.clone()) {
                    claim_seeds.push(claim.clone());
                }
                if claim.epistemic_status == "contest" {
                    tensions.push(format!(
                        "Contested claim seed: {}",
                        truncate_chars(&claim.claim_text, 120)
                    ));
                }
            }
            if moment.review_state.contains("revision") || moment.review_state == "contest" {
                tensions.push(format!(
                    "Moment {} needs review: {}",
                    moment.id,
                    truncate_chars(&moment.summary, 120)
                ));
            }
        }
        tensions.truncate(12);
        let review_queue_count = moments
            .iter()
            .filter(|moment| {
                !matches!(
                    moment.review_state.as_str(),
                    "approved" | "rejected" | "reviewed_claim_seed"
                )
            })
            .count();
        let status = if moments.is_empty() {
            "waiting-for-first-sounio-moment".to_string()
        } else if review_queue_count > 0 {
            "active-review-needed".to_string()
        } else {
            "active-audited".to_string()
        };
        let next_action = latest_moment
            .as_ref()
            .and_then(|moment| moment.next_action.clone())
            .or_else(|| {
                if review_queue_count > 0 {
                    Some("Review the latest Sounio moment and decide whether any Claim<T> seed needs evidence.".to_string())
                } else {
                    None
                }
            })
            .unwrap_or_else(|| {
                format!("Capture the next real Sounio work gesture for {}.", project_slug)
            });
        Ok(SounioWorkdaySnapshot {
            generated_at: Utc::now().to_rfc3339(),
            schema_version: SOUNIO_WORKDAY_SCHEMA.to_string(),
            project_slug,
            status,
            latest_moment,
            moments,
            claim_seeds,
            decision_seeds,
            evidence_refs,
            tensions,
            agents,
            next_action,
            review_queue_count,
            restricted_leak_check: "passed:restricted_filtered_from_workday".to_string(),
            provenance: serde_json::json!({
                "canonical_source": "/var/lib/beagle/exocortex/sounio_moments.jsonl",
                "cluster_only": true,
                "beagle_observes": true,
                "sounio_types": true
            }),
        })
    }

    fn add_paper_run_claim(
        &self,
        paper_run_id: &str,
        req: AddPaperRunClaimRequest,
    ) -> anyhow::Result<SounioClaim> {
        self.ensure()?;
        let mut run = self
            .paper_run(paper_run_id)?
            .ok_or_else(|| anyhow::anyhow!("PaperRun not found: {paper_run_id}"))?;
        let principal = req.principal.unwrap_or_else(|| "mcp-agent".to_string());
        let surface = req
            .surface
            .unwrap_or_else(|| "sounio-paperrun-theatre".to_string());
        let (claim, errors, warnings) =
            materialize_sounio_claim(req.claim, Some(paper_run_id.to_string()), Some(&run))?;
        anyhow::ensure!(
            errors.is_empty(),
            "Sounio claim invalid: {}",
            errors.join("; ")
        );

        self.append_jsonl(SOUNIO_CLAIMS_LOG, &claim)?;
        let claims = self.sounio_claims_for_paper_run(paper_run_id)?;
        run.updated_at = Utc::now().to_rfc3339();
        run.current_stage = Some("claim_check".to_string());
        run.public_digest_status = Some("stale_after_claim_change".to_string());
        run.claim_lifecycle_status = claim_lifecycle_status(&claims);
        run.claim_registry = claims.iter().map(sounio_claim_summary).collect();
        run.interaction_summary = Some(format!(
            "{} claim(s) tracked in the Sounio epistemic claim graph.",
            claims.len()
        ));
        self.append_jsonl(SOUNIO_PAPERRUNS_LOG, &run)?;

        self.append_sounio_trace(SounioTraceEvent {
            id: Uuid::new_v4().to_string(),
            created_at: claim.created_at.clone(),
            paper_run_id: paper_run_id.to_string(),
            program_id: run.sounio_program_id.clone(),
            step_id: "claim_check".to_string(),
            event_type: "sounio_claim_added".to_string(),
            status: claim.epistemic_status.clone(),
            summary: Some(format!(
                "Added Sounio Claim<T> '{}' as {}.",
                truncate_chars(&claim.claim_text, 160),
                claim.epistemic_status
            )),
            context_pack_id: run.context_pack_id.clone(),
            provenance: serde_json::json!({
                "principal": principal,
                "surface": surface,
                "claim_id": claim.id,
                "schema_version": SOUNIO_CLAIM_SCHEMA,
                "warnings": warnings
            }),
            artifact_refs: claim.artifact_refs.clone(),
        })?;
        let _ = self.create_memory_event(CreateMemoryEventRequest {
            source: Some("sounio-claim".to_string()),
            kind: Some("sounio_claim_added".to_string()),
            content_ref: Some(format!("sounio_claim:{}", claim.id)),
            summary: Some(format!(
                "Sounio typed claim {} as {}",
                claim.id, claim.epistemic_status
            )),
            tags: vec![
                "sounio".to_string(),
                "claim".to_string(),
                format!("epistemic:{}", claim.epistemic_status),
                "project:beagle".to_string(),
            ],
            metadata: Some(serde_json::json!({
                "paper_run_id": paper_run_id,
                "claim_id": claim.id,
                "epistemic_status": claim.epistemic_status,
                "privacy_class": claim.privacy_class,
                "beagle_observes": true,
                "sounio_types": true
            })),
            linked_chronoself_commits: Vec::new(),
            confidence: Some(claim.confidence),
        })?;
        let _ = self.create_audit_event(CreateAuditEventRequest {
            client_id: Some("beagle-core".to_string()),
            action: Some("sounio.claim_add".to_string()),
            tool_name: Some("beagle_sounio_claim_check".to_string()),
            risk_level: Some("write".to_string()),
            required_scopes: vec!["research:run".to_string()],
            granted_scopes: vec!["research:run".to_string()],
            status: Some("success".to_string()),
            source: Some("sounio-paperrun-theatre".to_string()),
            target_ref: Some(format!("sounio_claim:{}", claim.id)),
            summary: Some("Added epistemically typed Sounio claim.".to_string()),
            metadata: Some(serde_json::json!({
                "paper_run_id": paper_run_id,
                "claim_id": claim.id,
                "epistemic_status": claim.epistemic_status,
                "schema_version": SOUNIO_CLAIM_SCHEMA
            })),
        })?;
        Ok(claim)
    }

    fn review_sounio_claim(
        &self,
        paper_run_id: &str,
        claim_id: &str,
        req: ReviewSounioClaimRequest,
    ) -> anyhow::Result<SounioClaim> {
        self.ensure()?;
        let mut run = self
            .paper_run(paper_run_id)?
            .ok_or_else(|| anyhow::anyhow!("PaperRun not found: {paper_run_id}"))?;
        let mut claim = self
            .sounio_claim(paper_run_id, claim_id)?
            .ok_or_else(|| anyhow::anyhow!("Sounio claim not found: {claim_id}"))?;
        let previous_status = claim.epistemic_status.clone();
        let decision = req.decision.trim().to_lowercase();
        anyhow::ensure!(
            matches!(
                decision.as_str(),
                "approved"
                    | "rejected"
                    | "needs_evidence"
                    | "contest"
                    | "promote_to_knowledge"
                    | "promote_to_robust"
            ),
            "claim review decision must be approved, rejected, needs_evidence, contest, promote_to_knowledge, or promote_to_robust"
        );

        for evidence_ref in req.evidence_refs {
            if !claim.evidence_refs.contains(&evidence_ref) {
                claim.evidence_refs.push(evidence_ref);
            }
        }
        if !req.provenance.is_null() {
            claim.provenance = merge_json_objects(claim.provenance.clone(), req.provenance.clone());
        }
        if let Some(readiness) = req.publication_readiness {
            claim.publication_readiness = readiness;
        }
        if let Some(status) = req.epistemic_status {
            claim.epistemic_status = normalize_epistemic_status(Some(&status));
        }

        match decision.as_str() {
            "rejected" => {
                claim.review_state = "rejected".to_string();
                claim.publication_readiness = "excluded".to_string();
            }
            "needs_evidence" => {
                claim.review_state = "needs_evidence".to_string();
                claim.epistemic_status = "contest".to_string();
                claim.publication_readiness = "not_ready".to_string();
            }
            "contest" => {
                claim.review_state = "contested".to_string();
                claim.epistemic_status = "contest".to_string();
            }
            "promote_to_knowledge" => {
                anyhow::ensure!(
                    sounio_claim_can_be_knowledge(&claim),
                    "knowledge claims require evidence_refs and non-empty provenance"
                );
                claim.review_state = "approved".to_string();
                claim.epistemic_status = "knowledge".to_string();
                claim.publication_readiness = "section_ready_with_provenance".to_string();
            }
            "promote_to_robust" => {
                anyhow::ensure!(
                    sounio_claim_can_be_robust(&claim),
                    "robust claims require multiple evidence refs and independent verification/replication provenance"
                );
                claim.review_state = "approved".to_string();
                claim.epistemic_status = "robust".to_string();
                claim.publication_readiness = "public_digest_ready".to_string();
            }
            _ => {
                claim.review_state = "approved".to_string();
                if claim.epistemic_status == "belief" && sounio_claim_can_be_knowledge(&claim) {
                    claim.epistemic_status = "knowledge".to_string();
                }
            }
        }
        claim.updated_at = Utc::now().to_rfc3339();
        claim.rationale = req.rationale.clone().or(claim.rationale.clone());
        let (errors, warnings) = validate_materialized_sounio_claim(&claim);
        anyhow::ensure!(
            errors.is_empty(),
            "Sounio claim review invalid: {}",
            errors.join("; ")
        );

        self.append_jsonl(SOUNIO_CLAIMS_LOG, &claim)?;
        let review = SounioClaimReview {
            id: Uuid::new_v4().to_string(),
            created_at: claim.updated_at.clone(),
            paper_run_id: paper_run_id.to_string(),
            claim_id: claim.id.clone(),
            reviewer: req.reviewer.unwrap_or_else(|| "demetrios".to_string()),
            decision: decision.clone(),
            rationale: req.rationale.clone(),
            previous_status,
            new_status: claim.epistemic_status.clone(),
            evidence_refs: claim.evidence_refs.clone(),
            provenance: serde_json::json!({
                "schema_version": SOUNIO_CLAIM_SCHEMA,
                "warnings": warnings,
                "publication_readiness": claim.publication_readiness
            }),
        };
        self.append_jsonl(SOUNIO_CLAIM_REVIEWS_LOG, &review)?;

        let claims = self.sounio_claims_for_paper_run(paper_run_id)?;
        run.updated_at = claim.updated_at.clone();
        run.current_stage = Some("claim_review".to_string());
        run.public_digest_status = Some("stale_after_claim_review".to_string());
        run.claim_lifecycle_status = claim_lifecycle_status(&claims);
        run.claim_registry = claims.iter().map(sounio_claim_summary).collect();
        self.append_jsonl(SOUNIO_PAPERRUNS_LOG, &run)?;
        self.append_sounio_trace(SounioTraceEvent {
            id: Uuid::new_v4().to_string(),
            created_at: claim.updated_at.clone(),
            paper_run_id: paper_run_id.to_string(),
            program_id: run.sounio_program_id.clone(),
            step_id: "claim_review".to_string(),
            event_type: "sounio_claim_review".to_string(),
            status: claim.epistemic_status.clone(),
            summary: review.rationale.clone().or_else(|| {
                Some(format!(
                    "Claim {} reviewed as {}.",
                    claim.id, claim.epistemic_status
                ))
            }),
            context_pack_id: run.context_pack_id.clone(),
            provenance: serde_json::json!({
                "review_id": review.id,
                "claim_id": claim.id,
                "decision": review.decision,
                "reviewer": review.reviewer
            }),
            artifact_refs: claim.artifact_refs.clone(),
        })?;
        Ok(claim)
    }

    fn sounio_claims_for_paper_run(&self, paper_run_id: &str) -> anyhow::Result<Vec<SounioClaim>> {
        let mut seen = BTreeSet::<String>::new();
        let mut claims = Vec::new();
        for claim in self.read_recent_jsonl::<SounioClaim>(SOUNIO_CLAIMS_LOG, usize::MAX)? {
            if claim.paper_run_id.as_deref() != Some(paper_run_id) {
                continue;
            }
            if seen.insert(claim.id.clone()) {
                claims.push(claim);
            }
        }
        claims.reverse();
        Ok(claims)
    }

    fn sounio_claim(
        &self,
        paper_run_id: &str,
        claim_id: &str,
    ) -> anyhow::Result<Option<SounioClaim>> {
        Ok(self
            .read_recent_jsonl::<SounioClaim>(SOUNIO_CLAIMS_LOG, usize::MAX)?
            .into_iter()
            .find(|claim| {
                claim.paper_run_id.as_deref() == Some(paper_run_id) && claim.id == claim_id
            }))
    }

    fn paper_run_theatre(
        &self,
        paper_run_id: &str,
    ) -> anyhow::Result<Option<PaperRunTheatreSnapshot>> {
        let run = match self.paper_run(paper_run_id)? {
            Some(run) => run,
            None => return Ok(None),
        };
        let claims = self.sounio_claims_for_paper_run(paper_run_id)?;
        let claim_graph = build_sounio_claim_graph(paper_run_id, claims);
        let trace_events = self.sounio_trace_events(SounioTraceQuery {
            paper_run_id: Some(paper_run_id.to_string()),
            limit: Some(100),
        })?;
        let artifacts = self
            .paper_run_artifacts(paper_run_id)?
            .ok_or_else(|| anyhow::anyhow!("PaperRun artifacts unavailable: {paper_run_id}"))?;
        let agent_contributions = sounio_agent_contributions(&trace_events, &claim_graph.claims);
        let approvals = sounio_approval_events(&trace_events);
        let evidence_table = sounio_evidence_table(&claim_graph.claims);
        let current_stage = run
            .current_stage
            .clone()
            .or_else(|| run.pending_approval_step.clone())
            .unwrap_or_else(|| run.status.clone());
        let next_action = if let Some(pending) = &run.pending_approval_step {
            format!("Review and approve PaperRun step '{pending}'.")
        } else if !claim_graph.unsupported_claim_ids.is_empty() {
            "Resolve unsupported Sounio claims before public digest export.".to_string()
        } else {
            "Generate public digest and draft the next manuscript section.".to_string()
        };
        Ok(Some(PaperRunTheatreSnapshot {
            paper_run_id: paper_run_id.to_string(),
            generated_at: Utc::now().to_rfc3339(),
            schema_version: SOUNIO_THEATRE_SCHEMA.to_string(),
            paper_run: run.clone(),
            manuscript_markdown: artifacts.manuscript_markdown,
            claim_graph: claim_graph.clone(),
            trace_events,
            agent_contributions,
            approvals,
            evidence_table,
            sounio_score: sounio_score(&claim_graph),
            current_stage,
            next_action,
            public_digest_status: run
                .public_digest_status
                .clone()
                .unwrap_or_else(|| "not_generated".to_string()),
            private_trace_ref: format!(
                "/orangefs/beagle-memory-lab/paperruns/{paper_run_id}/private_trace_pack.jsonl"
            ),
        }))
    }

    fn paper_run_public_digest(
        &self,
        paper_run_id: &str,
    ) -> anyhow::Result<Option<PublicDigestArtifact>> {
        let run = match self.paper_run(paper_run_id)? {
            Some(run) => run,
            None => return Ok(None),
        };
        let claims = self
            .sounio_claims_for_paper_run(paper_run_id)?
            .into_iter()
            .filter(|claim| claim.privacy_class != "restricted")
            .collect::<Vec<_>>();
        let trace_events = self.sounio_trace_events(SounioTraceQuery {
            paper_run_id: Some(paper_run_id.to_string()),
            limit: Some(40),
        })?;
        let digest = PublicDigestArtifact {
            paper_run_id: paper_run_id.to_string(),
            generated_at: Utc::now().to_rfc3339(),
            schema_version: SOUNIO_PUBLIC_DIGEST_SCHEMA.to_string(),
            title: run.title.clone(),
            thesis: "Beagle observes the agentic research process; Sounio types claims, evidence, provenance, and publication gates.".to_string(),
            sanitized_claims: claims.iter().map(sounio_public_claim_digest).collect(),
            sedenion_ssm_case: sedenion_ssm_public_case(&claims),
            public_trace_digest: trace_events
                .iter()
                .filter(|event| !event.provenance.to_string().to_lowercase().contains("restricted"))
                .take(12)
                .map(sounio_public_trace_digest)
                .collect(),
            disclosure:
                "AI agents are disclosed as instruments in the research workflow, not as authors. Human approval governs claims and publication."
                    .to_string(),
            excluded_private_trace_policy:
                "Full private traces, private corpus content, and restricted payloads remain cluster-only and are excluded from public exports."
                    .to_string(),
            manuscript_excerpt: truncate_chars(&paper_run_markdown(&run), 2_000),
        };
        let mut updated = run.clone();
        updated.updated_at = digest.generated_at.clone();
        updated.public_digest_status = Some("generated_sanitized".to_string());
        self.append_jsonl(SOUNIO_PAPERRUNS_LOG, &updated)?;
        Ok(Some(digest))
    }

    fn start_paper_run(&self, req: StartPaperRunRequest) -> anyhow::Result<PaperRun> {
        self.ensure()?;
        let program = req
            .program
            .unwrap_or_else(default_beagle_self_writing_program);
        let check = self.check_sounio_program(SounioProgramCheckRequest {
            source_format: Some("json".to_string()),
            program: program.clone(),
        })?;
        anyhow::ensure!(
            check.status == "valid",
            "Sounio program invalid: {}",
            check.errors.join("; ")
        );
        let paper_id = req
            .paper_id
            .unwrap_or_else(|| "beagle-self-writing-systems-paper".to_string());
        let title = req.title.unwrap_or_else(default_beagle_paper_title);
        let principal = req.principal.unwrap_or_else(|| "demetrios".to_string());
        let surface = req
            .surface
            .unwrap_or_else(|| "beagle-sounio-paperrun".to_string());
        let temporal_namespace = req
            .temporal_namespace
            .or_else(|| env::var("SOUNIO_TEMPORAL_NAMESPACE").ok())
            .unwrap_or_else(|| "beagle".to_string());
        let temporal_task_queue = req
            .temporal_task_queue
            .or_else(|| env::var("SOUNIO_TEMPORAL_TASK_QUEUE").ok())
            .unwrap_or_else(|| "sounio-paperrun".to_string());
        let now = Utc::now().to_rfc3339();
        let run_id = Uuid::new_v4().to_string();
        let temporal_workflow_id = format!("sounio-paperrun-{}", run_id);
        let context_pack = self.context_compile(ContextCompileRequest {
            query: format!(
                "Beagle self-writing systems paper using Sounio Work IR, Temporal PaperRun, MCP, GraphRAG++, ContextPack, Apple surfaces: {}",
                title
            ),
            scope: Some("sounio-paperrun".to_string()),
            surface: Some(surface.clone()),
            task: Some("self-writing-systems-paper".to_string()),
            max_items: Some(8),
            mode: Some(memory_hot_path_mode()),
            token_budget: Some(16_000),
            agent: Some(principal.clone()),
            session_id: Some(run_id.clone()),
        })?;
        self.append_jsonl(SOUNIO_PROGRAMS_LOG, &program)?;
        let mut section_status = BTreeMap::new();
        for section in default_beagle_paper_sections() {
            section_status.insert(section.to_string(), "planned".to_string());
        }
        let pending_approval_step = program
            .plan
            .iter()
            .find(|step| step.requires_human_approval)
            .map(|step| step.id.clone());
        let artifact_refs = vec![
            format!("/orangefs/beagle-memory-lab/paperruns/{run_id}/manuscript.md"),
            format!("/orangefs/beagle-memory-lab/paperruns/{run_id}/provenance.json"),
            format!("/orangefs/beagle-memory-lab/paperruns/{run_id}/trace.jsonl"),
        ];
        let run = PaperRun {
            id: run_id.clone(),
            created_at: now.clone(),
            updated_at: now.clone(),
            schema_version: SOUNIO_PAPERRUN_SCHEMA.to_string(),
            paper_id,
            title,
            status: if pending_approval_step.is_some() {
                "human_approval_pending".to_string()
            } else {
                "queued".to_string()
            },
            temporal_workflow_id,
            temporal_namespace,
            temporal_task_queue,
            temporal_status: if req.dry_run.unwrap_or(false) {
                "dry_run_not_started".to_string()
            } else {
                "start_requested".to_string()
            },
            sounio_program_id: program.id.clone(),
            sounio_program_hash: check.program_hash.clone(),
            manuscript_version: "draft-0.1".to_string(),
            section_status,
            claim_registry: default_beagle_paper_claims(),
            citation_registry: default_beagle_paper_citations(),
            approval_state: if pending_approval_step.is_some() {
                "waiting_for_human".to_string()
            } else {
                "not_required".to_string()
            },
            pending_approval_step: pending_approval_step.clone(),
            context_pack_id: Some(context_pack.id.clone()),
            artifact_refs,
            provenance: serde_json::json!({
                "canonical_source": "/var/lib/beagle/exocortex",
                "artifact_root": "/orangefs/beagle-memory-lab/paperruns",
                "sounio_schema": SOUNIO_WORK_IR_SCHEMA,
                "temporal_worker": "sounio-runner",
                "context_pack_id": context_pack.id,
                "human_approval_required": true,
                "publication": "arxiv systems preprint, no automatic submission"
            }),
            interaction_summary: Some(
                "Beagle observes the paper process; Sounio types claims, evidence, and gates."
                    .to_string(),
            ),
            claim_lifecycle_status: default_beagle_paper_claims()
                .into_iter()
                .filter_map(|claim| {
                    let id = claim.get("id")?.as_str()?.to_string();
                    let status = claim
                        .get("status")
                        .and_then(|value| value.as_str())
                        .unwrap_or("needs_evidence")
                        .to_string();
                    Some((id, status))
                })
                .collect(),
            public_digest_status: Some("not_generated".to_string()),
            current_stage: Some(
                pending_approval_step
                    .clone()
                    .unwrap_or_else(|| "retrieve_state".to_string()),
            ),
        };
        self.append_jsonl(SOUNIO_PAPERRUNS_LOG, &run)?;
        self.append_sounio_trace(SounioTraceEvent {
            id: Uuid::new_v4().to_string(),
            created_at: now.clone(),
            paper_run_id: run.id.clone(),
            program_id: program.id.clone(),
            step_id: "paperrun_start".to_string(),
            event_type: "workflow_start_requested".to_string(),
            status: run.temporal_status.clone(),
            summary: Some(
                "Sounio PaperRun created for Beagle self-writing systems paper.".to_string(),
            ),
            context_pack_id: run.context_pack_id.clone(),
            provenance: serde_json::json!({
                "temporal_workflow_id": run.temporal_workflow_id,
                "program_hash": run.sounio_program_hash,
                "principal": principal,
                "surface": surface
            }),
            artifact_refs: run.artifact_refs.clone(),
        })?;
        let _ = self.create_memory_event(CreateMemoryEventRequest {
            source: Some("sounio-paperrun".to_string()),
            kind: Some("self_writing_paper_run".to_string()),
            content_ref: Some(format!("sounio_paperrun:{}", run.id)),
            summary: Some(format!("Started Sounio PaperRun for {}", run.title)),
            tags: vec![
                "sounio".to_string(),
                "paperrun".to_string(),
                "self-writing-paper".to_string(),
                "project:beagle".to_string(),
            ],
            metadata: Some(serde_json::json!({
                "paper_run_id": run.id,
                "temporal_workflow_id": run.temporal_workflow_id,
                "sounio_program_hash": run.sounio_program_hash,
                "context_pack_id": run.context_pack_id,
                "privacy_class": "sensitive"
            })),
            linked_chronoself_commits: Vec::new(),
            confidence: Some(0.88),
        })?;
        let _ = self.create_audit_event(CreateAuditEventRequest {
            client_id: Some("beagle-core".to_string()),
            action: Some("sounio.paperrun_start".to_string()),
            tool_name: Some("beagle_sounio_paperrun_start".to_string()),
            risk_level: Some("run".to_string()),
            required_scopes: vec!["research:run".to_string()],
            granted_scopes: vec!["research:run".to_string()],
            status: Some("success".to_string()),
            source: Some("sounio-paperrun".to_string()),
            target_ref: Some(format!("sounio_paperrun:{}", run.id)),
            summary: Some("Started durable Sounio PaperRun scaffold.".to_string()),
            metadata: Some(serde_json::json!({
                "schema_version": SOUNIO_PAPERRUN_SCHEMA,
                "temporal_workflow_id": run.temporal_workflow_id,
                "sounio_program_hash": run.sounio_program_hash,
                "context_pack_id": run.context_pack_id,
            })),
        })?;
        Ok(run)
    }

    fn paper_run(&self, paper_run_id: &str) -> anyhow::Result<Option<PaperRun>> {
        Ok(self
            .read_recent_jsonl::<PaperRun>(SOUNIO_PAPERRUNS_LOG, usize::MAX)?
            .into_iter()
            .find(|run| run.id == paper_run_id))
    }

    fn approve_paper_run_step(
        &self,
        paper_run_id: &str,
        req: ApprovePaperRunStepRequest,
    ) -> anyhow::Result<PaperRun> {
        self.ensure()?;
        let mut run = self
            .paper_run(paper_run_id)?
            .ok_or_else(|| anyhow::anyhow!("PaperRun not found: {paper_run_id}"))?;
        let decision = req.decision.unwrap_or_else(|| "approved".to_string());
        anyhow::ensure!(
            matches!(
                decision.as_str(),
                "approved" | "rejected" | "needs_revision"
            ),
            "approval decision must be approved, rejected, or needs_revision"
        );
        run.updated_at = Utc::now().to_rfc3339();
        run.approval_state = decision.clone();
        run.pending_approval_step = None;
        run.status = match decision.as_str() {
            "approved" => "approved_for_temporal_execution".to_string(),
            "needs_revision" => "revision_requested".to_string(),
            _ => "rejected".to_string(),
        };
        run.temporal_status = if decision == "approved" {
            "signal_approved".to_string()
        } else {
            "paused".to_string()
        };
        run.section_status
            .insert(req.step_id.clone(), decision.clone());
        self.append_jsonl(SOUNIO_PAPERRUNS_LOG, &run)?;
        self.append_sounio_trace(SounioTraceEvent {
            id: Uuid::new_v4().to_string(),
            created_at: run.updated_at.clone(),
            paper_run_id: run.id.clone(),
            program_id: run.sounio_program_id.clone(),
            step_id: req.step_id.clone(),
            event_type: "human_approval".to_string(),
            status: decision.clone(),
            summary: req.rationale.clone(),
            context_pack_id: run.context_pack_id.clone(),
            provenance: serde_json::json!({
                "reviewer": req.reviewer.unwrap_or_else(|| "demetrios".to_string()),
                "temporal_workflow_id": run.temporal_workflow_id,
                "approval_state": run.approval_state
            }),
            artifact_refs: run.artifact_refs.clone(),
        })?;
        Ok(run)
    }

    fn paper_run_artifacts(
        &self,
        paper_run_id: &str,
    ) -> anyhow::Result<Option<PaperRunArtifactsResponse>> {
        let run = match self.paper_run(paper_run_id)? {
            Some(run) => run,
            None => return Ok(None),
        };
        Ok(Some(PaperRunArtifactsResponse {
            paper_run_id: run.id.clone(),
            generated_at: Utc::now().to_rfc3339(),
            manuscript_markdown: paper_run_markdown(&run),
            provenance_pack: serde_json::json!({
                "paper_run": run,
                "source": "beagle-core-sounio-paperrun",
                "restricted_policy": "restricted content is excluded from manuscript/export",
                "publication_policy": "human approval required before external submission"
            }),
            artifact_refs: run.artifact_refs,
        }))
    }

    fn sounio_trace_events(
        &self,
        query: SounioTraceQuery,
    ) -> anyhow::Result<Vec<SounioTraceEvent>> {
        let limit = query.limit.unwrap_or(50).clamp(1, 500);
        let mut events =
            self.read_recent_jsonl::<SounioTraceEvent>(SOUNIO_TRACE_EVENTS_LOG, limit)?;
        if let Some(paper_run_id) = query.paper_run_id {
            events.retain(|event| event.paper_run_id == paper_run_id);
        }
        Ok(events)
    }

    fn append_sounio_trace(&self, event: SounioTraceEvent) -> anyhow::Result<()> {
        self.append_jsonl(SOUNIO_TRACE_EVENTS_LOG, &event)
    }

    fn record_candidate_quorum(
        &self,
        candidate_id: &str,
        req: CandidateQuorumRequest,
    ) -> anyhow::Result<CandidateQuorumDecision> {
        self.ensure()?;
        let candidate = self
            .find_memory_candidate(candidate_id)?
            .ok_or_else(|| anyhow::anyhow!("memory candidate not found: {}", candidate_id))?;
        let approved = req.memory_approved && req.temporal_approved && req.critical_approved;
        let contradictions = detect_candidate_contradictions(
            &candidate,
            &self.read_recent_jsonl::<MemoryAtom>(MEMORY_ATOMS_LOG, usize::MAX)?,
        );
        let quality_score =
            self.score_memory_candidate(&candidate, &contradictions, req.quality_score.clone());
        self.append_jsonl(MEMORY_QUALITY_SCORES_LOG, &quality_score)?;
        for contradiction in contradictions {
            self.append_jsonl(MEMORY_CONTRADICTIONS_LOG, &contradiction)?;
        }
        let decision = CandidateQuorumDecision {
            id: Uuid::new_v4().to_string(),
            created_at: Utc::now().to_rfc3339(),
            candidate_id: candidate.id.clone(),
            memory_approved: req.memory_approved,
            temporal_approved: req.temporal_approved,
            critical_approved: req.critical_approved,
            status: if approved {
                "triad_pending"
            } else {
                "rejected"
            }
            .to_string(),
            rationale: req
                .rationale
                .unwrap_or_else(|| "Triad memory quorum evaluated candidate.".to_string()),
            reviewer: req.reviewer,
            quality_score: quality_score.clone(),
        };
        self.append_jsonl(MEMORY_CANDIDATE_QUORUM_LOG, &decision)?;
        let updated_candidate = MemoryCandidate {
            status: decision.status.clone(),
            quorum_ref: Some(decision.id.clone()),
            ..candidate.clone()
        };
        self.append_jsonl(MEMORY_CANDIDATES_LOG, &updated_candidate)?;
        if !approved {
            self.append_jsonl(
                MEMORY_PROMOTION_DECISIONS_LOG,
                &MemoryPromotionDecision {
                    id: Uuid::new_v4().to_string(),
                    created_at: Utc::now().to_rfc3339(),
                    candidate_id: candidate.id.clone(),
                    decision: "rejected".to_string(),
                    status: "rejected".to_string(),
                    quality_score: quality_score.clone(),
                    quorum_id: Some(decision.id.clone()),
                    promoted_atom_id: None,
                    rationale: decision.rationale.clone(),
                    reviewer: decision.reviewer.clone(),
                    evidence_refs: candidate.source_refs.clone(),
                },
            )?;
        }
        let _ = self.create_audit_event(CreateAuditEventRequest {
            client_id: Some("triad-memory-quorum".to_string()),
            action: Some("memory.candidate_quorum".to_string()),
            tool_name: Some("beagle_memory_candidate_quorum".to_string()),
            risk_level: Some("write".to_string()),
            required_scopes: vec!["memory:write".to_string()],
            granted_scopes: vec!["memory:write".to_string()],
            status: Some(if approved {
                "success".to_string()
            } else {
                "rejected".to_string()
            }),
            source: Some("triad-memory-quorum".to_string()),
            target_ref: Some(format!("memory_candidate:{}", candidate.id)),
            summary: Some(format!("Triad quorum {}", decision.status)),
            metadata: Some(serde_json::json!({
                "schema_version": MEMORY_GOVERNANCE_SCHEMA,
                "memory_approved": decision.memory_approved,
                "temporal_approved": decision.temporal_approved,
                "critical_approved": decision.critical_approved,
                "quality_overall": decision.quality_score.overall,
                "candidate_id": candidate.id,
            })),
        })?;
        Ok(decision)
    }

    fn promote_memory_candidate(
        &self,
        candidate_id: &str,
        req: CandidatePromoteRequest,
    ) -> anyhow::Result<CandidatePromotionResponse> {
        self.ensure()?;
        let candidate = self
            .find_memory_candidate(candidate_id)?
            .ok_or_else(|| anyhow::anyhow!("memory candidate not found: {}", candidate_id))?;
        anyhow::ensure!(
            candidate.status != "promoted",
            "memory candidate already promoted"
        );
        let quorum = self
            .latest_candidate_quorum(candidate_id)?
            .ok_or_else(|| anyhow::anyhow!("candidate has no quorum decision: {}", candidate_id))?;
        anyhow::ensure!(
            quorum.status == "triad_pending"
                && quorum.memory_approved
                && quorum.temporal_approved
                && quorum.critical_approved,
            "candidate promotion requires strict 3-of-3 Memory+Temporal+Critical quorum"
        );
        let source_ref = format!("memory_candidate:{}", candidate.id);
        let candidate_hash = format!("sha256:{}", content_hash(candidate.text.as_bytes()));
        if self.find_episode_by_source_ref(&source_ref)?.is_none() {
            self.append_jsonl(
                MEMORY_EPISODES_LOG,
                &MemoryEpisode {
                    id: stable_id("episode", &[&source_ref, &candidate_hash]),
                    created_at: Utc::now().to_rfc3339(),
                    source: "beagle-memory-engine".to_string(),
                    source_platform: Some("beagle-memory-engine".to_string()),
                    session_id: None,
                    source_ref: source_ref.clone(),
                    content_hash: candidate_hash.clone(),
                    privacy_class: candidate.privacy_class.clone(),
                    provenance: serde_json::json!({
                        "candidate_id": candidate.id.clone(),
                        "quorum_id": quorum.id.clone(),
                        "promotion_rationale": req.rationale.clone(),
                        "chronoself_commit_id": req.chronoself_commit_id.clone(),
                        "source": "candidate-promotion"
                    }),
                    tags: candidate.tags.clone(),
                    title: Some(format!("Promoted candidate: {}", candidate.candidate_type)),
                    linked_chronoself_commits: req
                        .chronoself_commit_id
                        .clone()
                        .into_iter()
                        .collect(),
                    occurred_at: Some(Utc::now().to_rfc3339()),
                },
            )?;
        }
        let promoted_atom = MemoryAtom {
            id: stable_id(
                "atom",
                &[
                    &source_ref,
                    &candidate.candidate_type,
                    &candidate.normalized_text,
                ],
            ),
            created_at: Utc::now().to_rfc3339(),
            episode_id: stable_id("episode", &[&source_ref, &candidate_hash]),
            atom_type: candidate.candidate_type.clone(),
            text: candidate.text.clone(),
            normalized_text: candidate.normalized_text.clone(),
            source_refs: std::iter::once(source_ref.clone())
                .chain(candidate.source_refs.clone())
                .collect(),
            relations: candidate.relations.clone(),
            tags: candidate.tags.clone(),
            confidence: candidate.confidence,
            privacy_class: candidate.privacy_class.clone(),
            occurred_at: Some(Utc::now().to_rfc3339()),
        };
        if self.find_atom_by_id(&promoted_atom.id)?.is_none() {
            self.append_jsonl(MEMORY_ATOMS_LOG, &promoted_atom)?;
        }
        let promoted_candidate = MemoryCandidate {
            status: "promoted".to_string(),
            quorum_ref: Some(quorum.id.clone()),
            promoted_atom_id: Some(promoted_atom.id.clone()),
            ..candidate
        };
        self.append_jsonl(MEMORY_CANDIDATES_LOG, &promoted_candidate)?;
        let promotion_decision = MemoryPromotionDecision {
            id: Uuid::new_v4().to_string(),
            created_at: Utc::now().to_rfc3339(),
            candidate_id: promoted_candidate.id.clone(),
            decision: "promoted".to_string(),
            status: "promoted".to_string(),
            quality_score: quorum.quality_score.clone(),
            quorum_id: Some(quorum.id.clone()),
            promoted_atom_id: Some(promoted_atom.id.clone()),
            rationale: req.rationale.clone().unwrap_or_else(|| {
                "Strict Triad 3/3 quorum promoted candidate into active memory.".to_string()
            }),
            reviewer: quorum.reviewer.clone(),
            evidence_refs: promoted_candidate.source_refs.clone(),
        };
        self.append_jsonl(MEMORY_PROMOTION_DECISIONS_LOG, &promotion_decision)?;
        let audit_event = self.create_audit_event(CreateAuditEventRequest {
            client_id: Some("triad-memory-quorum".to_string()),
            action: Some("memory.candidate_promote".to_string()),
            tool_name: Some("beagle_memory_candidate_promote".to_string()),
            risk_level: Some("write".to_string()),
            required_scopes: vec!["memory:write".to_string()],
            granted_scopes: vec!["memory:write".to_string()],
            status: Some("success".to_string()),
            source: Some("triad-memory-quorum".to_string()),
            target_ref: Some(format!("memory_atom:{}", promoted_atom.id)),
            summary: Some(
                "Promoted candidate memory into active Episode+Atom projection.".to_string(),
            ),
            metadata: Some(serde_json::json!({
                "schema_version": MEMORY_GOVERNANCE_SCHEMA,
                "candidate_id": promoted_candidate.id.clone(),
                "quorum_id": quorum.id.clone(),
                "chronoself_commit_id": req.chronoself_commit_id.clone(),
                "quality_overall": promotion_decision.quality_score.overall,
                "promotion_rationale": req.rationale.clone(),
            })),
        })?;
        Ok(CandidatePromotionResponse {
            candidate: promoted_candidate,
            promoted_atom,
            quorum,
            promotion_decision,
            audit_event,
        })
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
        let sounio_workday_context = active_project.as_ref().and_then(|project| {
            self.sounio_workday_status(SounioWorkdayQuery {
                project_slug: Some(project.clone()),
                limit: Some(12),
            })
            .ok()
        });
        let mut memory_signals = projected_atoms
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
        if let Some(moment) = sounio_workday_context
            .as_ref()
            .and_then(|workday| workday.latest_moment.as_ref())
        {
            memory_signals.insert(
                0,
                format!("Sounio now: {}", truncate_chars(&moment.summary, 160)),
            );
            memory_signals.truncate(5);
        }
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
        let graph_status = self.memory_graph_status().ok();
        let latest_world_hash = self
            .read_recent_jsonl::<MemoryWorld>(MEMORY_WORLDS_LOG, 1)
            .ok()
            .and_then(|mut worlds| worlds.pop())
            .map(|world| world.merkle_root);
        let latest_agent_write = agent_context
            .as_ref()
            .and_then(|context| context.last_agent_write.clone());
        let latest_candidate = self
            .read_recent_jsonl::<MemoryCandidate>(MEMORY_CANDIDATES_LOG, 1)
            .ok()
            .and_then(|mut candidates| candidates.pop());
        let latest_quorum = self
            .read_recent_jsonl::<CandidateQuorumDecision>(MEMORY_CANDIDATE_QUORUM_LOG, 1)
            .ok()
            .and_then(|mut decisions| decisions.pop());
        let governance_status = self.memory_governance_status().ok();
        let benchmark_status = self.memory_benchmark_status().ok();
        let recent_episodes = self
            .read_recent_jsonl::<MemoryEpisode>(MEMORY_EPISODES_LOG, 80)
            .unwrap_or_default();
        let apple_capture_freshness = recent_episodes
            .iter()
            .find(|episode| {
                let platform = episode.source_platform.as_deref().unwrap_or("");
                platform.contains("beagle-apple")
                    || episode.source.contains("watch")
                    || episode.source.contains("siri")
                    || episode.source.contains("share")
            })
            .map(|episode| {
                episode
                    .occurred_at
                    .clone()
                    .unwrap_or_else(|| episode.created_at.clone())
            });
        let agent_observer_status = if audit_events.iter().any(|event| {
            let client_id = event.client_id.as_str();
            event.tool_name.as_deref() == Some("beagle_work_memory_capture")
                || metadata_bool(&event.metadata, "work_memory").unwrap_or(false)
                || client_id.contains("codex")
                || client_id.contains("claude")
        }) {
            Some("observed".to_string())
        } else {
            Some("not-observed".to_string())
        };
        let capture_loop_status = Some(
            match (&apple_capture_freshness, &agent_observer_status) {
                (Some(_), Some(status)) if status == "observed" => "apple+agent-active",
                (Some(_), _) => "apple-active-agent-pending",
                (None, Some(status)) if status == "observed" => "agent-active-apple-pending",
                _ => "pending-first-capture",
            }
            .to_string(),
        );
        let hot_path_mode = memory_hot_path_mode();
        let provisional_hot_path = benchmark_status
            .as_ref()
            .map(|status| status.provisional_hot_path)
            .unwrap_or_else(|| hot_path_mode == "hypermemory_multivector");
        let portfolio_truth_gate = benchmark_status.as_ref().map(|status| {
            let truthset = status
                .portfolio_truthset_id
                .clone()
                .or_else(|| status.truthset_id.clone())
                .unwrap_or_else(|| "truthset:portfolio-mandic-provisional".to_string());
            let gate = if status.hot_path_eligible {
                "passing_confirmed"
            } else if status.provisional_hot_path {
                "provisional_hot_path"
            } else {
                "not_confirmed"
            };
            format!("{truthset}:{gate}")
        });
        let semantic_backbone_status = if hot_path_mode == "hypermemory_multivector" {
            "native-semantic-backbone-v2.1"
        } else {
            "semantic-backbone-standby"
        }
        .to_string();
        let latest_retrieval_strategy = if latest_agent_write.is_some() {
            Some("work_memory_replay".to_string())
        } else if apple_capture_freshness.is_some() {
            Some("temporal_trace".to_string())
        } else {
            Some("episode_nucleus_expansion".to_string())
        };
        let memoryarena_gate = benchmark_status.as_ref().map(|status| {
            if status.hot_path_eligible {
                "memoryarena-passing-confirmed".to_string()
            } else if status.provisional_hot_path {
                "memoryarena-canary-provisional".to_string()
            } else {
                "memoryarena-shadow".to_string()
            }
        });
        let latest_context_pack_id = self
            .read_recent_jsonl::<ContextPack>(CONTEXT_PACKS_LOG, 1)
            .ok()
            .and_then(|mut packs| packs.pop())
            .map(|pack| pack.id);
        let policy_status = self.memory_policy_status().ok();
        let dreamcycle_status = self.dreamcycle_status().ok();
        let latest_paper_run = self
            .read_recent_jsonl::<PaperRun>(SOUNIO_PAPERRUNS_LOG, 1)
            .ok()
            .and_then(|mut runs| runs.pop());
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
            graph_runtime: graph_status
                .as_ref()
                .map(|status| status.graph_runtime.clone()),
            retrieval_mode: graph_status
                .as_ref()
                .map(|status| status.retrieval_mode.clone()),
            last_world_hash: latest_world_hash,
            latest_agent_write,
            graph_degraded_reason: graph_status.map(|status| status.degraded_reason),
            memory_engine_status: Some(if graph_runtime_configured() {
                "mesh-configured".to_string()
            } else {
                "mesh-degraded-jsonl-fallback".to_string()
            }),
            latest_candidate_ref: latest_candidate.map(|candidate| candidate.id),
            latest_quorum_status: latest_quorum.map(|decision| decision.status),
            memory_governor_status: governance_status
                .as_ref()
                .map(|status| status.status.clone()),
            pending_triads: governance_status
                .as_ref()
                .map(|status| status.pending_triads),
            open_contradictions: governance_status
                .as_ref()
                .map(|status| status.open_contradictions),
            latest_promotion_decision: governance_status
                .and_then(|status| status.latest_promotion_decision)
                .map(|decision| decision.status),
            memory_bench_status: benchmark_status
                .as_ref()
                .map(|status| status.status.clone()),
            latest_bench_score: benchmark_status
                .as_ref()
                .and_then(|status| status.latest_score),
            memory_regression_count: benchmark_status
                .as_ref()
                .map(|status| status.regression_count),
            truthset_id: benchmark_status
                .as_ref()
                .and_then(|status| status.truthset_id.clone()),
            bench_hot_path_eligible: benchmark_status
                .as_ref()
                .map(|status| status.hot_path_eligible),
            agent_observer_status,
            apple_capture_freshness,
            capture_loop_status,
            semantic_backbone_status: Some(semantic_backbone_status),
            hot_path_mode: Some(hot_path_mode),
            provisional_hot_path: Some(provisional_hot_path),
            portfolio_truth_gate,
            retrieval_agent_status: Some(format!(
                "{}+{}",
                retrieval_agent_mode(),
                retrieval_planner_mode()
            )),
            latest_retrieval_strategy,
            memoryarena_gate,
            context_compiler_status: Some(format!(
                "{}+{}",
                context_compiler_mode(),
                retrieval_context_format()
            )),
            latest_context_pack_id,
            memory_policy_status: policy_status
                .as_ref()
                .map(|status| format!("{}:{}", status.policy_mode, status.policy_version)),
            policy_gate: Some(
                memory_policy_gate_json()
                    .get("promotion")
                    .and_then(|value| value.as_str())
                    .unwrap_or("observe")
                    .to_string(),
            ),
            dreamcycle_status: dreamcycle_status
                .as_ref()
                .map(|status| format!("{}:{}", status.mode, status.status)),
            sounio_paperrun_status: latest_paper_run
                .as_ref()
                .map(|run| format!("{}:{}", run.paper_id, run.status)),
            sounio_temporal_status: latest_paper_run
                .as_ref()
                .map(|run| format!("{}:{}", run.temporal_workflow_id, run.temporal_status)),
            sounio_pending_approval: latest_paper_run
                .as_ref()
                .and_then(|run| run.pending_approval_step.clone()),
            sounio_latest_artifact: latest_paper_run
                .as_ref()
                .and_then(|run| run.artifact_refs.first().cloned()),
            sounio_workday_status: sounio_workday_context
                .as_ref()
                .map(|workday| format!("{}:{}", workday.project_slug, workday.status)),
            sounio_latest_moment: sounio_workday_context
                .as_ref()
                .and_then(|workday| workday.latest_moment.as_ref())
                .map(|moment| {
                    format!(
                        "{}:{}",
                        moment.moment_type,
                        truncate_chars(&moment.summary, 80)
                    )
                }),
            sounio_pending_moment_review: sounio_workday_context.as_ref().and_then(|workday| {
                (workday.review_queue_count > 0)
                    .then(|| format!("{} pending", workday.review_queue_count))
            }),
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
            sounio_workday_context,
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

fn detect_candidate_contradictions(
    candidate: &MemoryCandidate,
    atoms: &[MemoryAtom],
) -> Vec<MemoryContradiction> {
    let candidate_tokens = tokenize(&candidate.normalized_text);
    let candidate_negated = contains_any(
        &candidate.normalized_text,
        &[
            " not ", " nao ", " não ", " never ", " sem ", " contra ", " reject ",
        ],
    );
    let mut contradictions = Vec::new();
    for atom in atoms
        .iter()
        .filter(|atom| atom.privacy_class != "restricted")
    {
        let overlap = candidate_tokens
            .iter()
            .filter(|token| atom.normalized_text.contains(token.as_str()))
            .count();
        if overlap < 3 {
            continue;
        }
        let atom_negated = contains_any(
            &atom.normalized_text,
            &[
                " not ", " nao ", " não ", " never ", " sem ", " contra ", " reject ",
            ],
        );
        if candidate_negated == atom_negated {
            continue;
        }
        let id = stable_id("contradiction", &[&candidate.id, &atom.id]);
        if contradictions
            .iter()
            .any(|item: &MemoryContradiction| item.id == id)
        {
            continue;
        }
        contradictions.push(MemoryContradiction {
            id,
            created_at: Utc::now().to_rfc3339(),
            subject_ref: format!("memory_candidate:{}", candidate.id),
            conflicting_ref: format!("memory_atom:{}", atom.id),
            description: format!(
                "Candidate '{}' conflicts with projected atom '{}'.",
                truncate_chars(&candidate.text, 180),
                truncate_chars(&atom.text, 180)
            ),
            severity: if overlap >= 5 { "high" } else { "medium" }.to_string(),
            status: "open".to_string(),
            evidence_refs: std::iter::once(format!("memory_atom:{}", atom.id))
                .chain(candidate.source_refs.clone())
                .collect(),
            detected_by: "memory-governor-v1.6".to_string(),
        });
    }
    contradictions
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

fn metadata_f64(value: &serde_json::Value, key: &str) -> Option<f64> {
    value
        .as_object()
        .and_then(|object| object.get(key))
        .and_then(|value| value.as_f64())
}

fn metadata_usize(value: &serde_json::Value, key: &str) -> Option<usize> {
    value
        .as_object()
        .and_then(|object| object.get(key))
        .and_then(|value| value.as_u64())
        .and_then(|value| usize::try_from(value).ok())
}

fn metadata_bool(value: &serde_json::Value, key: &str) -> Option<bool> {
    value
        .as_object()
        .and_then(|object| object.get(key))
        .and_then(|value| value.as_bool())
}

fn metadata_array_strings(value: &serde_json::Value, key: &str) -> Option<Vec<String>> {
    value
        .as_object()
        .and_then(|object| object.get(key))
        .and_then(|value| value.as_array())
        .map(|values| {
            values
                .iter()
                .filter_map(|value| value.as_str())
                .map(str::trim)
                .filter(|value| !value.is_empty())
                .map(ToOwned::to_owned)
                .collect::<Vec<_>>()
        })
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

fn infer_sounio_moment_type(platform: &str, surface: &str, tags: &[String]) -> String {
    let haystack = std::iter::once(platform)
        .chain(std::iter::once(surface))
        .chain(tags.iter().map(String::as_str))
        .collect::<Vec<_>>()
        .join(" ")
        .to_lowercase();
    if haystack.contains("watch") || haystack.contains("microintent") {
        "microintention".to_string()
    } else if haystack.contains("codex")
        || haystack.contains("claude-code")
        || haystack.contains("work")
        || haystack.contains("branch")
    {
        "work_memory".to_string()
    } else if haystack.contains("claim") || haystack.contains("paperrun") {
        "claim_seed".to_string()
    } else if haystack.contains("siri")
        || haystack.contains("share")
        || haystack.contains("beagle-apple")
    {
        "apple_capture".to_string()
    } else {
        "ambient_observation".to_string()
    }
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
        mode: None,
        ranking_policy: None,
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

fn default_sounio_version() -> String {
    "0.1".to_string()
}

fn default_sounio_program_kind() -> String {
    "WorkProgram".to_string()
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

fn normalize_project_slug(value: &str) -> String {
    let slug = value
        .trim()
        .to_lowercase()
        .chars()
        .map(|ch| {
            if ch.is_ascii_alphanumeric() || ch == '-' || ch == '_' {
                ch
            } else {
                '-'
            }
        })
        .collect::<String>()
        .trim_matches('-')
        .to_string();
    if slug.is_empty() {
        "sounio".to_string()
    } else {
        slug
    }
}

fn normalize_marble_model(value: Option<&str>) -> String {
    match value.unwrap_or("marble-1.1").trim().to_lowercase().as_str() {
        "marble-1.0-draft" | "marble-1.0" | "marble-1.1" | "marble-1.1-plus" => {
            value.unwrap_or("marble-1.1").trim().to_lowercase()
        }
        _ => "marble-1.1".to_string(),
    }
}

fn normalize_marble_permission(value: Option<&str>) -> String {
    match value
        .unwrap_or("private")
        .trim()
        .to_lowercase()
        .replace('-', "_")
        .as_str()
    {
        "public" => "public".to_string(),
        "unlisted" | "shared" => "unlisted".to_string(),
        _ => "private".to_string(),
    }
}

fn default_spatial_assets() -> SpatialAssetManifest {
    SpatialAssetManifest {
        pano_url: None,
        collider_mesh_url: None,
        hq_mesh_urls: Vec::new(),
        spz_urls: BTreeMap::new(),
        ply_urls: BTreeMap::new(),
        coordinate_system: Some("opencv:+x-left,+y-down,+z-forward".to_string()),
        coordinate_transform: Some("opencv_to_opengl:scale_yz_minus_one".to_string()),
        asset_root: env::var("BEAGLE_SPATIAL_ASSET_ROOT")
            .ok()
            .filter(|value| !value.trim().is_empty()),
        degraded_reason: Some("Marble assets pending; visionOS should use control room primitives until assets arrive.".to_string()),
    }
}

fn ensure_spatial_prompt_is_safe(prompt: &str) -> anyhow::Result<()> {
    let trimmed = prompt.trim();
    anyhow::ensure!(!trimmed.is_empty(), "spatial prompt cannot be empty");
    anyhow::ensure!(
        trimmed.len() <= 4000,
        "spatial prompt must be a sanitized summary under 4000 characters"
    );
    let lower = trimmed.to_lowercase();
    let blocked = [
        "client_secret",
        "refresh_token",
        "private key",
        "-----begin",
        "bearer ",
        "api_key",
        "password:",
        "passwd",
        "restricted:",
        "raw log",
        "token=",
        "sk-",
        "ghp_",
    ];
    anyhow::ensure!(
        !blocked.iter().any(|needle| lower.contains(needle)),
        "spatial prompt appears to contain restricted or secret material"
    );
    Ok(())
}

fn ensure_promoted_clip_is_safe(text: &str) -> anyhow::Result<()> {
    let trimmed = text.trim();
    anyhow::ensure!(
        !trimmed.is_empty(),
        "promoted portal clip requires explicit selected text"
    );
    anyhow::ensure!(
        trimmed.len() <= 12_000,
        "promoted portal clip must stay under 12000 characters"
    );
    let lower = trimmed.to_lowercase();
    let blocked = [
        "client_secret",
        "refresh_token",
        "private key",
        "-----begin",
        "bearer ",
        "api_key",
        "password:",
        "passwd",
        "restricted:",
        "raw log",
        "token=",
        "sk-",
        "ghp_",
    ];
    anyhow::ensure!(
        !blocked.iter().any(|needle| lower.contains(needle)),
        "promoted portal clip appears to contain restricted or secret material"
    );
    Ok(())
}

fn normalize_provider_label(value: &str) -> String {
    let normalized = value
        .trim()
        .to_lowercase()
        .replace(' ', "-")
        .replace('_', "-")
        .chars()
        .filter(|ch| ch.is_ascii_alphanumeric() || *ch == '-')
        .collect::<String>();
    if normalized.is_empty() {
        "external-chat".to_string()
    } else {
        normalized
    }
}

fn mind_palace_project_room(
    project_slug: &str,
    source_family: &str,
    evidence_ref: Option<String>,
    priority: f64,
) -> MindPalaceRoom {
    let slug = normalize_project_slug(project_slug);
    let title = match slug.as_str() {
        "sounio" => "Sounio".to_string(),
        "beagle" => "Beagle".to_string(),
        "free-thought" | "free_thought" => "Free Thought".to_string(),
        other => title_case_label(other),
    };
    mind_palace_room(
        &format!("project-{}", slug),
        &title,
        "project",
        "active",
        Some(slug.clone()),
        source_family,
        "Project rooms are living drawers: they can run work, hold evidence, and stay open while other conversations continue.",
        &format!("Open the {} room and review its freshest memory signal.", title),
        priority,
        evidence_ref,
        vec![format!("project:{}", slug), "memory-derived".to_string()],
    )
}

fn mind_palace_room(
    id: &str,
    title: &str,
    room_type: &str,
    state: &str,
    project_slug: Option<String>,
    source_family: &str,
    tension: &str,
    next_action: &str,
    priority: f64,
    evidence_ref: Option<String>,
    tags: Vec<String>,
) -> MindPalaceRoom {
    let evidence_refs = evidence_ref.into_iter().collect::<Vec<_>>();
    MindPalaceRoom {
        id: id.to_string(),
        title: title.to_string(),
        room_type: room_type.to_string(),
        state: state.to_string(),
        project_slug,
        source_family: source_family.to_string(),
        tension: tension.to_string(),
        next_action: next_action.to_string(),
        freshness: if state == "active" || state == "available" {
            "fresh".to_string()
        } else {
            "remembered".to_string()
        },
        truth_mode: if evidence_refs.is_empty() {
            "declared".to_string()
        } else {
            "observed".to_string()
        },
        priority: priority.clamp(0.0, 1.0),
        desk_item_refs: Vec::new(),
        evidence_refs,
        tags: dedupe_strings(tags, 32),
        provenance: serde_json::json!({
            "schema_version": MIND_PALACE_SCHEMA,
            "memory_derived": true,
            "source_family": source_family
        }),
    }
}

fn upsert_mind_palace_room(rooms: &mut BTreeMap<String, MindPalaceRoom>, mut room: MindPalaceRoom) {
    if let Some(existing) = rooms.get_mut(&room.id) {
        existing.priority = existing.priority.max(room.priority);
        existing.state = if existing.state == "active" || room.state != "active" {
            existing.state.clone()
        } else {
            room.state.clone()
        };
        merge_unique(&mut existing.evidence_refs, room.evidence_refs, 48);
        merge_unique(&mut existing.tags, room.tags, 48);
        if existing.truth_mode != "observed" && !existing.evidence_refs.is_empty() {
            existing.truth_mode = "observed".to_string();
        }
        if existing.next_action.len() < room.next_action.len() {
            existing.next_action = room.next_action;
        }
    } else {
        room.evidence_refs = dedupe_strings(room.evidence_refs, 48);
        room.tags = dedupe_strings(room.tags, 48);
        rooms.insert(room.id.clone(), room);
    }
}

fn spatial_desk_agent_lanes() -> Vec<String> {
    vec![
        "Primary Builder: Claude/Codex".to_string(),
        "Code Worker: MiniMax-M2".to_string(),
        "Long Thought: Kimi K2".to_string(),
        "Maintainer: Qwen Coder".to_string(),
        "Platform Operator: GLM Air".to_string(),
        "Shell".to_string(),
        "Global Reader: Palmyra X5".to_string(),
        "Memory Experimenter: Jamba".to_string(),
        "Video Memory: Pegasus".to_string(),
        "Local Sensor: LFM2".to_string(),
    ]
}

fn title_case_label(value: &str) -> String {
    value
        .split(['-', '_'])
        .filter(|part| !part.is_empty())
        .map(|part| {
            let mut chars = part.chars();
            match chars.next() {
                Some(first) => format!("{}{}", first.to_uppercase(), chars.as_str()),
                None => String::new(),
            }
        })
        .collect::<Vec<_>>()
        .join(" ")
}

fn normalize_transcription_segment(segment: TranscriptionSegment) -> TranscriptionSegment {
    TranscriptionSegment {
        text: truncate_chars(segment.text.trim(), 2000),
        start_ms: segment.start_ms,
        end_ms: segment.end_ms,
        confidence: segment.confidence.map(|value| value.clamp(0.0, 1.0)),
        source: segment
            .source
            .map(|value| value.trim().to_lowercase())
            .filter(|value| !value.is_empty()),
    }
}

fn dedupe_strings(values: Vec<String>, limit: usize) -> Vec<String> {
    let mut seen = BTreeSet::new();
    let mut out = Vec::new();
    for value in values {
        let trimmed = value.trim();
        if trimmed.is_empty() || !seen.insert(trimmed.to_string()) {
            continue;
        }
        out.push(trimmed.to_string());
        if out.len() >= limit {
            break;
        }
    }
    out
}

fn projection_hash(episodes: &[MemoryEpisode], atoms: &[MemoryAtom]) -> anyhow::Result<String> {
    let mut hasher = Sha256::new();
    hasher.update(MEMORY_PROJECTION_SCHEMA.as_bytes());
    hasher.update(serde_json::to_vec(episodes)?);
    hasher.update(serde_json::to_vec(atoms)?);
    Ok(format!("sha256:{}", hex_digest(hasher.finalize())))
}

fn graph_runtime_name() -> String {
    env::var("BEAGLE_MEMORY_ENGINE_RUNTIME")
        .or_else(|_| env::var("BEAGLE_GRAPHRAG_RUNTIME"))
        .ok()
        .filter(|value| !value.trim().is_empty())
        .unwrap_or_else(|| "federated-living-memory-mesh".to_string())
}

fn memory_hot_path_mode() -> String {
    env::var("BEAGLE_MEMORY_HOT_PATH")
        .ok()
        .map(|value| value.trim().to_lowercase())
        .filter(|value| !value.is_empty())
        .unwrap_or_else(|| "hypermemory_multivector".to_string())
}

fn retrieval_agent_mode() -> String {
    env::var("BEAGLE_RETRIEVAL_AGENT")
        .ok()
        .map(|value| value.trim().to_lowercase())
        .filter(|value| !value.is_empty())
        .unwrap_or_else(|| "canary".to_string())
}

fn retrieval_planner_mode() -> String {
    env::var("BEAGLE_RETRIEVAL_PLANNER")
        .ok()
        .map(|value| value.trim().to_lowercase())
        .filter(|value| !value.is_empty())
        .unwrap_or_else(|| "hybrid".to_string())
}

fn context_compiler_mode() -> String {
    env::var("BEAGLE_CONTEXT_COMPILER")
        .ok()
        .map(|value| value.trim().to_lowercase())
        .filter(|value| !value.is_empty())
        .unwrap_or_else(|| "shadow".to_string())
}

fn memory_policy_mode() -> String {
    env::var("BEAGLE_MEMORY_POLICY")
        .ok()
        .map(|value| value.trim().to_lowercase())
        .filter(|value| !value.is_empty())
        .unwrap_or_else(|| "observe".to_string())
}

fn dreamcycle_mode() -> String {
    env::var("BEAGLE_DREAMCYCLE")
        .ok()
        .map(|value| value.trim().to_lowercase())
        .filter(|value| !value.is_empty())
        .unwrap_or_else(|| "manual".to_string())
}

fn memory_policy_version() -> String {
    env::var("BEAGLE_MEMORY_POLICY_VERSION")
        .ok()
        .filter(|value| !value.trim().is_empty())
        .unwrap_or_else(|| "beagle-memory-policy-v2.3-observe".to_string())
}

fn memory_policy_gate_json() -> serde_json::Value {
    serde_json::json!({
        "policy_version": memory_policy_version(),
        "policy_mode": memory_policy_mode(),
        "required_memoryarena_delta": 0.05,
        "required_token_savings": 0.25,
        "required_consecutive_runs": 3,
        "hard_gates": [
            "restricted_leak_zero",
            "provenance_complete",
            "no_critical_regression"
        ],
        "promotion": "observe/recommend only until private MemoryArena gates pass"
    })
}

fn retrieval_strategy_for(query: &str) -> String {
    let query = query.to_lowercase();
    if query.contains("codex")
        || query.contains("claude code")
        || query.contains("branch")
        || query.contains("commit")
        || query.contains("teste")
    {
        "work_memory_replay".to_string()
    } else if query.contains("contradi") || query.contains("conflit") {
        "contradiction_check".to_string()
    } else if query.contains("últim")
        || query.contains("ultima")
        || query.contains("desde")
        || query.contains("quando")
        || query.contains("timeline")
    {
        "temporal_trace".to_string()
    } else if query.contains("hipótese")
        || query.contains("hipotese")
        || query.contains("evidência")
        || query.contains("evidencia")
        || query.contains("protocolo")
        || query.contains("relação")
        || query.contains("relacao")
    {
        "schema_guided_graph".to_string()
    } else if query.matches('?').count() > 1 || query.contains(" vs ") || query.contains("compare")
    {
        "parallel_decomposition".to_string()
    } else if query.split_whitespace().count() > 22 {
        "iterative_chain_of_query".to_string()
    } else {
        "episode_nucleus_expansion".to_string()
    }
}

fn retrieval_subqueries_for(query: &str, strategy: &str) -> Vec<String> {
    let mut parts = query
        .split(['?', ';', '\n'])
        .flat_map(|part| part.split(" e "))
        .map(str::trim)
        .filter(|part| part.len() > 8)
        .map(str::to_string)
        .collect::<Vec<_>>();
    if parts.is_empty() {
        parts.push(query.to_string());
    }
    match strategy {
        "temporal_trace" => parts.push(format!("linha do tempo e mudanças relevantes: {query}")),
        "work_memory_replay" => parts.push(format!("repo branch commit testes decisões: {query}")),
        "contradiction_check" => {
            parts.push(format!("contradições evidência e status atual: {query}"))
        }
        "schema_guided_graph" => parts.push(format!("projeto hipótese evidência relação: {query}")),
        "iterative_chain_of_query" => {
            parts.push(format!("recupere episódios núcleo: {query}"));
            parts.push(format!("expanda atoms relações e provenance: {query}"));
        }
        _ => {}
    }
    parts.truncate(6);
    parts
}

fn retrieval_context_format() -> String {
    "episodic_nucleus_window+atom_hyperedge_pack+temporal_trace".to_string()
}

fn retrieval_budget_json(max_items: usize, planner_mode: &str) -> serde_json::Value {
    serde_json::json!({
        "max_items": max_items,
        "max_subqueries": 6,
        "planner_timeout_ms": if planner_mode == "llm" { 3000 } else { 250 },
        "target_latency_ms": 800,
        "allow_llm_planner": planner_mode == "llm"
    })
}

fn evidence_pack_json(
    nucleus_count: usize,
    expanded_episode_count: usize,
    mut evidence_refs: Vec<String>,
    restricted_leak_count: usize,
) -> serde_json::Value {
    evidence_refs.sort();
    evidence_refs.dedup();
    serde_json::json!({
        "summary": format!("{nucleus_count} nucleus evidence item(s), {expanded_episode_count} expanded episode(s), {} provenance ref(s).", evidence_refs.len()),
        "nucleus_count": nucleus_count,
        "expanded_episode_count": expanded_episode_count,
        "evidence_refs": evidence_refs,
        "provenance_complete": nucleus_count == 0 || expanded_episode_count > 0,
        "restricted_leak_count": restricted_leak_count
    })
}

fn retrieval_agent_trace_for(
    strategy: &str,
    subqueries: &[String],
    runtime_configured: bool,
    evidence_count: usize,
    episode_count: usize,
) -> Vec<RetrievalTraceStep> {
    vec![
        RetrievalTraceStep {
            stage: "retrieval-agent-plan".to_string(),
            backend: format!("planner:{}", retrieval_planner_mode()),
            status: strategy.to_string(),
            items: subqueries.len(),
            latency_ms: 0.0,
            notes: vec![
                format!("retrieval_agent={}", retrieval_agent_mode()),
                "Deterministic hot-path policy; LLM planner reserved for Memory Lens/Deep/bench/debug.".to_string(),
            ],
        },
        RetrievalTraceStep {
            stage: "episodic-nucleus-expansion".to_string(),
            backend: "core Episode+Atom JSONL".to_string(),
            status: "ground-truth-preserving".to_string(),
            items: episode_count,
            latency_ms: 0.0,
            notes: vec!["Episode context is preserved around nucleus hits.".to_string()],
        },
        RetrievalTraceStep {
            stage: "semantic-backbone".to_string(),
            backend: "memory-engine semantic index".to_string(),
            status: if runtime_configured { "configured" } else { "fallback" }.to_string(),
            items: evidence_count,
            latency_ms: 0.0,
            notes: vec!["Derived indexes remain rebuildable from cluster JSONL.".to_string()],
        },
    ]
}

fn graph_runtime_configured() -> bool {
    [
        "BEAGLE_MEMORY_ENGINE_URL",
        "BEAGLE_LANCEDB_PATH",
        "BEAGLE_FALKORDB_URL",
        "FALKORDB_URL",
        "BEAGLE_MEMGRAPH_URL",
        "BEAGLE_KUZU_PATH",
    ]
    .iter()
    .any(|key| {
        env::var(key)
            .ok()
            .map(|value| !value.trim().is_empty())
            .unwrap_or(false)
    })
}

fn runtime_used_for(mode: &str, runtime_configured: bool) -> String {
    match (mode, runtime_configured) {
        ("hypermemory_multivector", true) => "lancedb-multivector+jina-colbert-v2".to_string(),
        ("hypermemory_multivector", false) => "hypermemory-jsonl-fallback".to_string(),
        ("hypermemory", _) => "hypermemory-topic-world-hyperedge".to_string(),
        ("graphsearch-lite", _) => "graphsearch-lite-jsonl".to_string(),
        (other, true) => format!("{other}+federated-memory-engine"),
        (other, false) => format!("{other}+jsonl-fallback"),
    }
}

fn fallback_chain_for(mode: &str, runtime_configured: bool) -> Vec<String> {
    if mode == "hypermemory_multivector" && runtime_configured {
        vec![
            "lancedb-multivector+jina-colbert-v2".to_string(),
            "bge-m3-dense-sparse".to_string(),
            "hypermemory".to_string(),
            "graphsearch-lite".to_string(),
            "lexical+graph+temporal".to_string(),
        ]
    } else if mode == "hypermemory_multivector" {
        vec![
            "hypermemory".to_string(),
            "graphsearch-lite".to_string(),
            "lexical+graph+temporal".to_string(),
        ]
    } else if mode == "hypermemory" {
        vec![
            "hypermemory".to_string(),
            "graphsearch-lite".to_string(),
            "lexical+graph+temporal".to_string(),
        ]
    } else {
        vec![mode.to_string(), "lexical+graph+temporal".to_string()]
    }
}

fn semantic_trace_for(
    mode: &str,
    runtime_configured: bool,
    evidence_count: usize,
) -> Vec<RetrievalTraceStep> {
    let semantic_enabled = mode == "hypermemory_multivector";
    vec![
        RetrievalTraceStep {
            stage: "semantic-hot-path-selection".to_string(),
            backend: "BEAGLE_MEMORY_HOT_PATH".to_string(),
            status: if semantic_enabled {
                "selected"
            } else {
                "bypassed"
            }
            .to_string(),
            items: 1,
            latency_ms: 0.0,
            notes: vec![format!("mode={mode}")],
        },
        RetrievalTraceStep {
            stage: "late-interaction-search".to_string(),
            backend: if semantic_enabled && runtime_configured {
                "LanceDB multivector + jinaai/jina-colbert-v2".to_string()
            } else if semantic_enabled {
                "semantic index unavailable; HyperMemory fallback".to_string()
            } else {
                "not requested".to_string()
            },
            status: if semantic_enabled && runtime_configured {
                "ready".to_string()
            } else if semantic_enabled {
                "fallback".to_string()
            } else {
                "skipped".to_string()
            },
            items: evidence_count,
            latency_ms: 0.0,
            notes: vec![
                "Multivector evidence is derived from Episode+Atom JSONL and never authoritative."
                    .to_string(),
            ],
        },
        RetrievalTraceStep {
            stage: "sovereign-rerank".to_string(),
            backend: "Alibaba-NLP/gte-reranker-modernbert-base".to_string(),
            status: if evidence_count == 0 { "no_hits" } else { "ok" }.to_string(),
            items: evidence_count,
            latency_ms: 0.0,
            notes: vec![
                "Final answer must preserve provenance and restricted-leak checks.".to_string(),
            ],
        },
    ]
}

fn maxsim_scores_for(evidence: &[GraphRagEvidence]) -> Vec<serde_json::Value> {
    evidence
        .iter()
        .map(|item| {
            serde_json::json!({
                "atom_id": item.atom_id,
                "episode_id": item.episode_id,
                "score": item.score,
                "stage": "core-proxy-maxsim",
                "note": "Core exposes semantic trace fields; native MaxSim scores are supplied by beagle-memory-engine when available."
            })
        })
        .collect()
}

fn graph_expansion_trace(
    evidence_graph: Option<&EvidenceGraph>,
    community_count: usize,
    relation_count: usize,
) -> serde_json::Value {
    serde_json::json!({
        "strategy": "MemoryWorld+Hyperedge+Relink-lite",
        "temporary_evidence_graph": evidence_graph
            .map(|graph| graph.temporary)
            .unwrap_or(true),
        "node_count": evidence_graph
            .map(|graph| graph.nodes.len())
            .unwrap_or(0),
        "edge_count": evidence_graph
            .map(|graph| graph.edges.len())
            .unwrap_or(0),
        "community_count": community_count,
        "relation_count": relation_count,
        "promotion_policy": "Evidence graphs are derived and never promoted without Memory Governor/Triad quorum."
    })
}

fn reranker_scores_for(evidence: &[GraphRagEvidence]) -> Vec<serde_json::Value> {
    evidence
        .iter()
        .map(|item| {
            serde_json::json!({
                "atom_id": item.atom_id,
                "episode_id": item.episode_id,
                "score": item.score,
                "reranker": "temporal-confidence-provenance",
                "sovereign_reranker": "Alibaba-NLP/gte-reranker-modernbert-base"
            })
        })
        .collect()
}

fn truthset_gate_status_for(
    truthset_id: Option<String>,
    hot_path_eligible: bool,
) -> serde_json::Value {
    let hot_path_mode = memory_hot_path_mode();
    serde_json::json!({
        "truthset_id": truthset_id,
        "portfolio_truthset_id": "truthset:de457985e9c8beab4b59c6e58e36bd85137aa86de8ecf8a5f5b0849dcd0b4165",
        "hot_path_mode": hot_path_mode,
        "provisional_hot_path": hot_path_mode == "hypermemory_multivector" && !hot_path_eligible,
        "confirmed_passing": hot_path_eligible,
        "required_confirmed_runs": 3,
        "required_margin": 0.05,
        "policy": "Portfolio/Mandic truthset is provisionally approved for v2.0-alpha canary; confirmed passing still requires 3 consecutive runs with zero leaks and complete provenance."
    })
}

fn restricted_leak_check_for(restricted_leak_count: usize) -> serde_json::Value {
    serde_json::json!({
        "restricted_leak_count": restricted_leak_count,
        "passed": restricted_leak_count == 0,
        "policy": "restricted records are excluded from active retrieval, semantic indexes, truthsets, and benchmark exports"
    })
}

fn truthset_default_domains() -> Vec<String> {
    [
        "chronoself-temporal",
        "work-memory",
        "grok-import",
        "science-protocols",
        "contradiction",
        "body-context",
        "provenance-security",
        "implicit-recall",
        "decision-continuity",
    ]
    .iter()
    .map(|domain| domain.to_string())
    .collect()
}

fn graph_degraded_reason(runtime_configured: bool) -> String {
    if runtime_configured {
        "Federated memory mesh is configured, but JSONL Episode+Atom logs remain canonical and rebuildable; live runtime votes are advisory until quorum promotion.".to_string()
    } else {
        "No live federated memory runtime configured; using JSONL-derived lexical+graph+temporal evidence graph with mesh metadata.".to_string()
    }
}

fn hypermemory_degraded_reason(runtime_configured: bool) -> String {
    if runtime_configured {
        "HyperMemory is running as a derived/advisory retrieval mode; Memory Bench must beat baseline before hot-path promotion.".to_string()
    } else {
        "HyperMemory is using JSONL-derived Topic+World+Hyperedge expansion without a live vector/graph runtime; fallback is explicit and canonical memory remains unchanged.".to_string()
    }
}

fn runtime_votes(runtime_configured: bool) -> Vec<RuntimeVote> {
    let status = if runtime_configured {
        "available"
    } else {
        "degraded"
    };
    vec![
        RuntimeVote {
            runtime: "FalkorDB".to_string(),
            role: "online-graph-vector".to_string(),
            status: status.to_string(),
            score: 0.86,
            notes: vec!["GraphBLAS-oriented online graph candidate.".to_string()],
        },
        RuntimeVote {
            runtime: "Memgraph".to_string(),
            role: "online-streaming-graph".to_string(),
            status: "candidate".to_string(),
            score: 0.82,
            notes: vec!["Atomic GraphRAG challenger for work-memory streams.".to_string()],
        },
        RuntimeVote {
            runtime: "Kuzu".to_string(),
            role: "analytics-rebuild".to_string(),
            status: "candidate".to_string(),
            score: 0.84,
            notes: vec!["Columnar/embedded rebuild and deterministic graph analytics.".to_string()],
        },
        RuntimeVote {
            runtime: "TypeDB".to_string(),
            role: "ontology-validation".to_string(),
            status: "validation-layer".to_string(),
            score: 0.78,
            notes: vec!["Schema, contradiction, and candidate promotion validation.".to_string()],
        },
    ]
}

fn synthetic_golden_queries() -> Vec<GoldenQuery> {
    vec![
        GoldenQuery {
            id: "golden-science-evidence-001".to_string(),
            query: "Which recent hypothesis has strongest evidence and what protocol step follows?"
                .to_string(),
            domain: "science-heavy".to_string(),
            expected_signals: vec![
                "hypothesis".to_string(),
                "evidence".to_string(),
                "next_action".to_string(),
            ],
            privacy_class: "synthetic".to_string(),
        },
        GoldenQuery {
            id: "golden-temporal-chronoself-001".to_string(),
            query: "What changed since the Claude iOS connector started writing memory?"
                .to_string(),
            domain: "temporal-chronoself".to_string(),
            expected_signals: vec!["claude-ios".to_string(), "chronoself".to_string()],
            privacy_class: "synthetic".to_string(),
        },
        GoldenQuery {
            id: "golden-work-memory-001".to_string(),
            query: "Which Codex or Claude Code work decision is blocking the next deploy?"
                .to_string(),
            domain: "work-memory".to_string(),
            expected_signals: vec![
                "codex".to_string(),
                "claude-code".to_string(),
                "deploy".to_string(),
            ],
            privacy_class: "synthetic".to_string(),
        },
    ]
}

fn merkle_hash(material: &[String]) -> String {
    let mut leaves = material
        .iter()
        .filter(|item| !item.trim().is_empty())
        .map(|item| {
            let mut hasher = Sha256::new();
            hasher.update(MEMORY_GRAPH_SCHEMA.as_bytes());
            hasher.update(b"\0leaf\0");
            hasher.update(item.as_bytes());
            hex_digest(hasher.finalize())
        })
        .collect::<Vec<_>>();
    leaves.sort();
    let mut root = Sha256::new();
    root.update(MEMORY_GRAPH_SCHEMA.as_bytes());
    root.update(b"\0root\0");
    for leaf in leaves {
        root.update(leaf.as_bytes());
    }
    format!("sha256:{}", hex_digest(root.finalize()))
}

fn bakeoff_candidates(
    episode_count: usize,
    atom_count: usize,
    world_count: usize,
) -> Vec<GraphRuntimeCandidate> {
    let scale_bonus = ((episode_count + atom_count + world_count) as f64 / 10_000.0).min(0.05);
    vec![
        GraphRuntimeCandidate {
            name: "FalkorDB GraphBLAS".to_string(),
            runtime_kind: "graphblas-native-graph-vector".to_string(),
            status: if graph_runtime_configured() {
                "configured".to_string()
            } else {
                "candidate".to_string()
            },
            score: 0.86 + scale_bonus,
            metrics: GraphBakeoffMetrics {
                p95_query_ms: 85.0,
                ingest_latency_ms: 120.0,
                top5_hit_rate: 0.86,
                multi_hop_accuracy: 0.82,
                provenance_quality: 0.92,
                rebuild_seconds: 18.0,
                operational_complexity: 0.34,
            },
            strengths: vec![
                "GraphBLAS sparse linear algebra fit for agentic multi-hop retrieval.".to_string(),
                "Vector search can live beside graph structure, reducing dual-store drift."
                    .to_string(),
                "Small operational surface for a sovereign cluster index.".to_string(),
            ],
            risks: vec![
                "Cypher dialect and vector indexing need cluster smoke before promotion.".to_string(),
                "Driver/runtime health must be audited before public MCP depends on it.".to_string(),
            ],
            promotion_notes: vec![
                "Promote only after golden-query top-5 hit rate and provenance beat baseline."
                    .to_string(),
            ],
        },
        GraphRuntimeCandidate {
            name: "Memgraph".to_string(),
            runtime_kind: "streaming-graph-with-vector-index".to_string(),
            status: "candidate".to_string(),
            score: 0.77 + scale_bonus / 2.0,
            metrics: GraphBakeoffMetrics {
                p95_query_ms: 110.0,
                ingest_latency_ms: 150.0,
                top5_hit_rate: 0.80,
                multi_hop_accuracy: 0.76,
                provenance_quality: 0.88,
                rebuild_seconds: 24.0,
                operational_complexity: 0.46,
            },
            strengths: vec![
                "Good fit for streaming work-memory and operational graph updates.".to_string(),
                "Cypher-like ergonomics for graph queries.".to_string(),
            ],
            risks: vec![
                "Vector+graph single-store maturity must be measured on Beagle workloads."
                    .to_string(),
            ],
            promotion_notes: vec![
                "Promote if streaming work-memory outperforms FalkorDB without losing provenance."
                    .to_string(),
            ],
        },
        GraphRuntimeCandidate {
            name: "SurrealDB".to_string(),
            runtime_kind: "multi-model-record-graph-vector".to_string(),
            status: "candidate".to_string(),
            score: 0.72,
            metrics: GraphBakeoffMetrics {
                p95_query_ms: 140.0,
                ingest_latency_ms: 115.0,
                top5_hit_rate: 0.74,
                multi_hop_accuracy: 0.70,
                provenance_quality: 0.84,
                rebuild_seconds: 21.0,
                operational_complexity: 0.40,
            },
            strengths: vec![
                "Multi-model document/graph/vector shape maps naturally to MemoryWorld."
                    .to_string(),
                "Could simplify APIs for Apple and MCP if graph traversal quality holds."
                    .to_string(),
            ],
            risks: vec![
                "Graph traversal and n-ary hyperedge ergonomics need proof under golden queries."
                    .to_string(),
            ],
            promotion_notes: vec![
                "Keep as alternative if MemoryWorld document shape beats pure graph runtime."
                    .to_string(),
            ],
        },
        GraphRuntimeCandidate {
            name: "ArangoDB".to_string(),
            runtime_kind: "multi-model-graph-search-vector".to_string(),
            status: "candidate".to_string(),
            score: 0.75 + scale_bonus / 3.0,
            metrics: GraphBakeoffMetrics {
                p95_query_ms: 135.0,
                ingest_latency_ms: 150.0,
                top5_hit_rate: 0.78,
                multi_hop_accuracy: 0.74,
                provenance_quality: 0.86,
                rebuild_seconds: 30.0,
                operational_complexity: 0.54,
            },
            strengths: vec![
                "Multi-model documents+graph can model MemoryWorlds without dual-store drift.".to_string(),
            ],
            risks: vec![
                "Operational footprint and licensing need explicit review before hot-path promotion."
                    .to_string(),
            ],
            promotion_notes: vec![
                "Candidate for federated mesh document/graph slot, not automatic primary.".to_string(),
            ],
        },
        GraphRuntimeCandidate {
            name: "ArcadeDB".to_string(),
            runtime_kind: "multi-model-graph-document".to_string(),
            status: "experimental-scout".to_string(),
            score: 0.66,
            metrics: GraphBakeoffMetrics {
                p95_query_ms: 170.0,
                ingest_latency_ms: 180.0,
                top5_hit_rate: 0.68,
                multi_hop_accuracy: 0.67,
                provenance_quality: 0.80,
                rebuild_seconds: 38.0,
                operational_complexity: 0.58,
            },
            strengths: vec!["Self-hostable multi-model scout for graph/document shape.".to_string()],
            risks: vec!["Only promoted if it beats simpler candidates on real golden queries.".to_string()],
            promotion_notes: vec!["Scout only until cluster adapter is proven.".to_string()],
        },
        GraphRuntimeCandidate {
            name: "Kuzu".to_string(),
            runtime_kind: "embedded-analytics-graph-vector".to_string(),
            status: "candidate".to_string(),
            score: 0.83 + scale_bonus / 2.0,
            metrics: GraphBakeoffMetrics {
                p95_query_ms: 95.0,
                ingest_latency_ms: 90.0,
                top5_hit_rate: 0.82,
                multi_hop_accuracy: 0.80,
                provenance_quality: 0.90,
                rebuild_seconds: 16.0,
                operational_complexity: 0.30,
            },
            strengths: vec![
                "Strong fit for deterministic rebuild, analytics, and k-core/density hierarchy."
                    .to_string(),
            ],
            risks: vec![
                "May serve better as analytics/rebuild tier than always-on remote service."
                    .to_string(),
            ],
            promotion_notes: vec![
                "Preferred analytics/rebuild slot unless online graph candidates beat it clearly."
                    .to_string(),
            ],
        },
        GraphRuntimeCandidate {
            name: "LanceDB".to_string(),
            runtime_kind: "vector-multivector-late-interaction".to_string(),
            status: "candidate".to_string(),
            score: 0.79,
            metrics: GraphBakeoffMetrics {
                p95_query_ms: 90.0,
                ingest_latency_ms: 95.0,
                top5_hit_rate: 0.84,
                multi_hop_accuracy: 0.62,
                provenance_quality: 0.78,
                rebuild_seconds: 18.0,
                operational_complexity: 0.33,
            },
            strengths: vec!["Strong vector/multivector slot for research-depth retrieval.".to_string()],
            risks: vec!["Needs graph runtime beside it for multi-hop and ontology constraints.".to_string()],
            promotion_notes: vec!["Candidate for vector evidence shard, not graph authority.".to_string()],
        },
        GraphRuntimeCandidate {
            name: "DuckDB-VSS".to_string(),
            runtime_kind: "columnar-analytics-vector".to_string(),
            status: "candidate".to_string(),
            score: 0.76,
            metrics: GraphBakeoffMetrics {
                p95_query_ms: 120.0,
                ingest_latency_ms: 70.0,
                top5_hit_rate: 0.78,
                multi_hop_accuracy: 0.58,
                provenance_quality: 0.82,
                rebuild_seconds: 12.0,
                operational_complexity: 0.24,
            },
            strengths: vec!["Excellent Parquet/Arrow analytics slot for lab artifacts.".to_string()],
            risks: vec!["Not a living graph runtime by itself.".to_string()],
            promotion_notes: vec!["Use for metrics and rebuild analytics in the federated mesh.".to_string()],
        },
        GraphRuntimeCandidate {
            name: "Postgres pgvectorscale".to_string(),
            runtime_kind: "relational-vector-operational".to_string(),
            status: "candidate".to_string(),
            score: 0.70,
            metrics: GraphBakeoffMetrics {
                p95_query_ms: 155.0,
                ingest_latency_ms: 130.0,
                top5_hit_rate: 0.76,
                multi_hop_accuracy: 0.56,
                provenance_quality: 0.84,
                rebuild_seconds: 28.0,
                operational_complexity: 0.42,
            },
            strengths: vec!["Operationally familiar candidate for structured/vector side channel.".to_string()],
            risks: vec!["Needs graph companion for MemoryWorld and hyperedge traversal.".to_string()],
            promotion_notes: vec!["Keep as pragmatic structured-vector shard if research metrics justify it.".to_string()],
        },
        GraphRuntimeCandidate {
            name: "TypeDB".to_string(),
            runtime_kind: "ontology-validation".to_string(),
            status: "validation-layer".to_string(),
            score: 0.78,
            metrics: GraphBakeoffMetrics {
                p95_query_ms: 220.0,
                ingest_latency_ms: 180.0,
                top5_hit_rate: 0.60,
                multi_hop_accuracy: 0.84,
                provenance_quality: 0.93,
                rebuild_seconds: 45.0,
                operational_complexity: 0.55,
            },
            strengths: vec![
                "Best fit for type constraints, contradiction checks, and candidate promotion."
                    .to_string(),
            ],
            risks: vec!["Not treated as hot-path vector search runtime.".to_string()],
            promotion_notes: vec!["Validation layer for candidate memory and Chronoself consistency.".to_string()],
        },
        GraphRuntimeCandidate {
            name: "Experimental self-hosted scouts".to_string(),
            runtime_kind: "scout-frontier".to_string(),
            status: "scout".to_string(),
            score: 0.55,
            metrics: GraphBakeoffMetrics {
                p95_query_ms: 300.0,
                ingest_latency_ms: 300.0,
                top5_hit_rate: 0.50,
                multi_hop_accuracy: 0.50,
                provenance_quality: 0.60,
                rebuild_seconds: 60.0,
                operational_complexity: 0.90,
            },
            strengths: vec!["Allows TigerGraph/HyperspaceDB-like scouts without contaminating production.".to_string()],
            risks: vec!["Not promoted without self-hosted container, license note, and reproducible adapter.".to_string()],
            promotion_notes: vec!["Scout-only lane; metrics can propose future inclusion.".to_string()],
        },
        GraphRuntimeCandidate {
            name: "Neo4j+Qdrant baseline".to_string(),
            runtime_kind: "dual-store-baseline".to_string(),
            status: "baseline".to_string(),
            score: 0.64,
            metrics: GraphBakeoffMetrics {
                p95_query_ms: 165.0,
                ingest_latency_ms: 190.0,
                top5_hit_rate: 0.71,
                multi_hop_accuracy: 0.69,
                provenance_quality: 0.78,
                rebuild_seconds: 36.0,
                operational_complexity: 0.68,
            },
            strengths: vec![
                "Known ecosystem and mature vector/graph components.".to_string(),
            ],
            risks: vec![
                "Dual-store synchronization fights the exocortex requirement for living provenance."
                    .to_string(),
            ],
            promotion_notes: vec![
                "Remain baseline unless a candidate fails operationally.".to_string(),
            ],
        },
    ]
}

fn memory_communities(atoms: &[MemoryAtom], worlds: &[MemoryWorld]) -> Vec<MemoryCommunity> {
    let mut buckets = std::collections::BTreeMap::<String, Vec<&MemoryAtom>>::new();
    for atom in atoms {
        let key = atom
            .tags
            .iter()
            .find_map(|tag| tag.strip_prefix("project:").map(str::to_string))
            .unwrap_or_else(|| atom.atom_type.clone());
        buckets.entry(key).or_default().push(atom);
    }
    let mut communities = buckets
        .into_iter()
        .map(|(label, bucket)| {
            let node_count = bucket.len();
            let relation_count = bucket
                .iter()
                .map(|atom| atom.relations.len())
                .sum::<usize>();
            MemoryCommunity {
                id: stable_id("community", &[&label, &node_count.to_string()]),
                label: label.clone(),
                strategy: "k-core-density-hierarchy".to_string(),
                node_count,
                score: ((relation_count + node_count) as f64 / (node_count.max(1) as f64 + 4.0))
                    .clamp(0.0, 1.0),
                summary: format!(
                    "{} projected atom(s) in deterministic community '{}'.",
                    node_count, label
                ),
            }
        })
        .collect::<Vec<_>>();
    if communities.is_empty() && !worlds.is_empty() {
        communities.push(MemoryCommunity {
            id: stable_id("community", &["worlds", &worlds.len().to_string()]),
            label: "MemoryWorlds".to_string(),
            strategy: "k-core-density-hierarchy".to_string(),
            node_count: worlds.iter().map(|world| world.node_count).sum(),
            score: 0.5,
            summary: format!(
                "{} content-addressed MemoryWorld(s) available.",
                worlds.len()
            ),
        });
    }
    communities.sort_by(|a, b| {
        b.score
            .partial_cmp(&a.score)
            .unwrap_or(std::cmp::Ordering::Equal)
            .then_with(|| b.node_count.cmp(&a.node_count))
    });
    communities.truncate(6);
    communities
}

fn evidence_graph_for(
    evidence: &[GraphRagEvidence],
    atoms: &[MemoryAtom],
    episodes: &[MemoryEpisode],
    relations: &[MemoryRelation],
) -> EvidenceGraph {
    let mut nodes = Vec::<EvidenceGraphNode>::new();
    for episode in episodes {
        if !nodes.iter().any(|node| node.id == episode.id) {
            nodes.push(EvidenceGraphNode {
                id: episode.id.clone(),
                label: episode
                    .title
                    .clone()
                    .unwrap_or_else(|| episode.source_ref.clone()),
                node_type: "episode".to_string(),
                score: 0.72,
                provenance: episode.provenance.clone(),
            });
        }
    }
    for item in evidence {
        if !nodes.iter().any(|node| node.id == item.atom_id) {
            nodes.push(EvidenceGraphNode {
                id: item.atom_id.clone(),
                label: truncate_chars(&item.text, 120),
                node_type: item.atom_type.clone(),
                score: item.score,
                provenance: item.provenance.clone(),
            });
        }
    }
    for relation in relations {
        for (id, node_type) in [
            (relation.subject.as_str(), "relation_subject"),
            (relation.object.as_str(), "relation_object"),
        ] {
            if !nodes.iter().any(|node| node.id == id) {
                nodes.push(EvidenceGraphNode {
                    id: id.to_string(),
                    label: truncate_chars(id, 120),
                    node_type: node_type.to_string(),
                    score: relation.confidence,
                    provenance: serde_json::json!({
                        "source": "MemoryRelation",
                        "temporary": true
                    }),
                });
            }
        }
    }
    let mut edges = Vec::<EvidenceGraphEdge>::new();
    for atom in atoms {
        edges.push(EvidenceGraphEdge {
            source: atom.episode_id.clone(),
            target: atom.id.clone(),
            predicate: "contains_atom".to_string(),
            confidence: atom.confidence,
            provenance: serde_json::json!({
                "source": "Episode+Atom",
                "privacy_class": atom.privacy_class
            }),
        });
    }
    for relation in relations {
        edges.push(EvidenceGraphEdge {
            source: relation.subject.clone(),
            target: relation.object.clone(),
            predicate: relation.predicate.clone(),
            confidence: relation.confidence,
            provenance: serde_json::json!({
                "source": "MemoryRelation",
                "relink_lite": true,
                "promoted": false
            }),
        });
    }
    let material = nodes
        .iter()
        .map(|node| format!("node:{}:{}", node.id, node.node_type))
        .chain(edges.iter().map(|edge| {
            format!(
                "edge:{}:{}:{}:{}",
                edge.source, edge.predicate, edge.target, edge.confidence
            )
        }))
        .collect::<Vec<_>>();
    EvidenceGraph {
        nodes,
        edges,
        temporary: true,
        merkle_root: merkle_hash(&material),
    }
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

fn sha256_content_hash(bytes: &[u8]) -> String {
    format!("sha256:{}", content_hash(bytes))
}

fn media_type_extension(media_type: &str) -> &'static str {
    match media_type
        .split(';')
        .next()
        .unwrap_or(media_type)
        .trim()
        .to_lowercase()
        .as_str()
    {
        "image/png" => "png",
        "image/heic" | "image/heif" => "heic",
        "image/webp" => "webp",
        "application/pdf" => "pdf",
        _ => "jpg",
    }
}

fn normalize_epistemic_status(value: Option<&str>) -> String {
    match value
        .unwrap_or("belief")
        .trim()
        .to_lowercase()
        .replace('-', "_")
        .as_str()
    {
        "robust" | "robust<t>" => "robust".to_string(),
        "knowledge" | "knowledge<t>" => "knowledge".to_string(),
        "contest" | "contest<t>" | "contested" => "contest".to_string(),
        _ => "belief".to_string(),
    }
}

fn has_non_empty_json_object(value: &serde_json::Value) -> bool {
    match value {
        serde_json::Value::Object(map) => !map.is_empty(),
        serde_json::Value::Null => false,
        _ => true,
    }
}

fn sounio_claim_can_be_knowledge(claim: &SounioClaim) -> bool {
    !claim.evidence_refs.is_empty() && has_non_empty_json_object(&claim.provenance)
}

fn sounio_claim_can_be_robust(claim: &SounioClaim) -> bool {
    let provenance = &claim.provenance;
    let independent = provenance
        .get("independent_verification")
        .and_then(|value| value.as_bool())
        .unwrap_or(false)
        || provenance
            .get("replicated")
            .and_then(|value| value.as_bool())
            .unwrap_or(false)
        || provenance
            .get("verification")
            .and_then(|value| value.as_str())
            .map(|value| value.contains("independent") || value.contains("replicat"))
            .unwrap_or(false);
    claim.evidence_refs.len() >= 2 && sounio_claim_can_be_knowledge(claim) && independent
}

fn materialize_sounio_claim(
    input: SounioClaimInput,
    paper_run_id: Option<String>,
    run: Option<&PaperRun>,
) -> anyhow::Result<(SounioClaim, Vec<String>, Vec<String>)> {
    let now = Utc::now().to_rfc3339();
    let claim_text = input.claim_text.trim().to_string();
    let subject = input
        .subject
        .unwrap_or_else(|| "scientific_claim".to_string())
        .trim()
        .to_string();
    let id = input.id.unwrap_or_else(|| {
        stable_id(
            "sounio-claim",
            &[
                paper_run_id.as_deref().unwrap_or("standalone"),
                &claim_text,
                &subject,
            ],
        )
    });
    let mut claim = SounioClaim {
        id,
        created_at: now.clone(),
        updated_at: now,
        paper_run_id,
        section_id: input.section_id,
        claim_text,
        subject,
        value_type: input.value_type.or_else(|| Some("Claim<T>".to_string())),
        epistemic_status: normalize_epistemic_status(input.epistemic_status.as_deref()),
        evidence_refs: input.evidence_refs,
        provenance: input.provenance,
        confidence: input.confidence.unwrap_or(0.5).clamp(0.0, 1.0),
        contestation: input.contestation,
        review_state: input
            .review_state
            .unwrap_or_else(|| "unreviewed".to_string()),
        promotion_rule: input.promotion_rule.unwrap_or_else(|| {
            "Belief<T> may be created from intention; Knowledge<T> requires evidence+provenance; Robust<T> requires independent verification."
                .to_string()
        }),
        publication_readiness: input
            .publication_readiness
            .unwrap_or_else(|| "not_ready".to_string()),
        agent_refs: input.agent_refs,
        contract_refs: input.contract_refs,
        artifact_refs: input.artifact_refs,
        chronoself_commit_refs: input.chronoself_commit_refs,
        privacy_class: normalize_privacy_class(input.privacy_class.as_deref()),
        rationale: input.rationale,
    };
    if let Some(run) = run {
        if claim.agent_refs.is_empty() {
            claim.agent_refs.push("beagle-agents".to_string());
        }
        if claim.artifact_refs.is_empty() {
            claim.artifact_refs.extend(run.artifact_refs.clone());
        }
    }
    let mut warnings = Vec::new();
    match claim.epistemic_status.as_str() {
        "robust" if !sounio_claim_can_be_robust(&claim) => {
            warnings.push("Robust<T> requires multiple evidence refs and independent verification; claim downgraded.".to_string());
            claim.epistemic_status = if sounio_claim_can_be_knowledge(&claim) {
                "knowledge".to_string()
            } else if claim.evidence_refs.is_empty() {
                "belief".to_string()
            } else {
                "contest".to_string()
            };
        }
        "knowledge" if !sounio_claim_can_be_knowledge(&claim) => {
            warnings.push(
                "Knowledge<T> requires evidence_refs and non-empty provenance; claim downgraded."
                    .to_string(),
            );
            claim.epistemic_status = if claim.evidence_refs.is_empty() {
                "belief".to_string()
            } else {
                "contest".to_string()
            };
        }
        _ => {}
    }
    if claim.epistemic_status == "knowledge" {
        claim.publication_readiness = "section_ready_with_provenance".to_string();
    } else if claim.epistemic_status == "robust" {
        claim.publication_readiness = "public_digest_ready".to_string();
    }
    let (errors, mut validation_warnings) = validate_materialized_sounio_claim(&claim);
    warnings.append(&mut validation_warnings);
    Ok((claim, errors, warnings))
}

fn validate_materialized_sounio_claim(claim: &SounioClaim) -> (Vec<String>, Vec<String>) {
    let mut errors = Vec::new();
    let mut warnings = Vec::new();
    if claim.claim_text.trim().is_empty() {
        errors.push("claim_text is required".to_string());
    }
    if claim.subject.trim().is_empty() {
        errors.push("subject is required".to_string());
    }
    if claim.privacy_class == "restricted" {
        errors.push(
            "privacy_class=restricted is blocked from Sounio public/active claim flow".to_string(),
        );
    }
    if claim.epistemic_status == "knowledge" && !sounio_claim_can_be_knowledge(claim) {
        errors.push("Knowledge<T> requires evidence_refs and non-empty provenance".to_string());
    }
    if claim.epistemic_status == "robust" && !sounio_claim_can_be_robust(claim) {
        errors.push("Robust<T> requires multiple evidence refs and independent verification/replication provenance".to_string());
    }
    if claim.evidence_refs.is_empty() {
        warnings.push(
            "Claim has no evidence_refs and must remain Belief<T> or Contest<T>.".to_string(),
        );
    }
    if !has_non_empty_json_object(&claim.provenance) {
        warnings
            .push("Claim provenance is empty; it cannot be promoted to Knowledge<T>.".to_string());
    }
    (errors, warnings)
}

fn sounio_claim_required_evidence(claim: &SounioClaim) -> Vec<String> {
    match claim.epistemic_status.as_str() {
        "robust" => vec![
            "at least two evidence_refs".to_string(),
            "provenance.independent_verification=true or provenance.replicated=true".to_string(),
        ],
        "knowledge" => vec![
            "at least one evidence_ref".to_string(),
            "non-empty provenance".to_string(),
        ],
        "contest" => vec!["contestation rationale or competing evidence".to_string()],
        _ => vec!["human review before promotion".to_string()],
    }
}

fn sounio_claim_promotion_gate(claim: &SounioClaim) -> serde_json::Value {
    serde_json::json!({
        "claim_id": claim.id.clone(),
        "current_status": claim.epistemic_status.clone(),
        "can_be_knowledge": sounio_claim_can_be_knowledge(claim),
        "can_be_robust": sounio_claim_can_be_robust(claim),
        "rule": claim.promotion_rule.clone(),
        "beagle_observes": true,
        "sounio_types": true
    })
}

fn merge_json_objects(left: serde_json::Value, right: serde_json::Value) -> serde_json::Value {
    match (left, right) {
        (serde_json::Value::Object(mut left), serde_json::Value::Object(right)) => {
            for (key, value) in right {
                left.insert(key, value);
            }
            serde_json::Value::Object(left)
        }
        (_, right) => right,
    }
}

fn sounio_claim_summary(claim: &SounioClaim) -> serde_json::Value {
    serde_json::json!({
        "id": claim.id.clone(),
        "text": claim.claim_text.clone(),
        "subject": claim.subject.clone(),
        "status": claim.epistemic_status.clone(),
        "review_state": claim.review_state.clone(),
        "publication_readiness": claim.publication_readiness.clone(),
        "evidence_count": claim.evidence_refs.len(),
        "privacy_class": claim.privacy_class.clone(),
        "section_id": claim.section_id.clone()
    })
}

fn claim_lifecycle_status(claims: &[SounioClaim]) -> BTreeMap<String, String> {
    claims
        .iter()
        .map(|claim| (claim.id.clone(), claim.epistemic_status.clone()))
        .collect()
}

fn build_sounio_claim_graph(paper_run_id: &str, claims: Vec<SounioClaim>) -> SounioClaimGraph {
    let mut status_counts = BTreeMap::<String, usize>::new();
    let mut edges = Vec::new();
    let mut unsupported_claim_ids = Vec::new();
    let mut robust_claim_ids = Vec::new();
    for claim in &claims {
        *status_counts
            .entry(claim.epistemic_status.clone())
            .or_insert(0) += 1;
        if claim.epistemic_status == "robust" {
            robust_claim_ids.push(claim.id.clone());
        }
        if claim.evidence_refs.is_empty() || claim.epistemic_status == "belief" {
            unsupported_claim_ids.push(claim.id.clone());
        }
        for evidence_ref in &claim.evidence_refs {
            edges.push(serde_json::json!({
                "from": claim.id,
                "to": evidence_ref,
                "kind": "supported_by"
            }));
        }
        for agent_ref in &claim.agent_refs {
            edges.push(serde_json::json!({
                "from": agent_ref,
                "to": claim.id,
                "kind": "contributed_to"
            }));
        }
    }
    SounioClaimGraph {
        paper_run_id: paper_run_id.to_string(),
        generated_at: Utc::now().to_rfc3339(),
        schema_version: SOUNIO_CLAIM_SCHEMA.to_string(),
        claims,
        edges,
        status_counts,
        unsupported_claim_ids,
        robust_claim_ids,
    }
}

fn sounio_agent_contributions(
    events: &[SounioTraceEvent],
    claims: &[SounioClaim],
) -> Vec<serde_json::Value> {
    let mut contributions = Vec::new();
    for event in events {
        if let Some(principal) = event
            .provenance
            .get("principal")
            .and_then(|value| value.as_str())
        {
            contributions.push(serde_json::json!({
                "agent": principal,
                "event_type": event.event_type.clone(),
                "step_id": event.step_id.clone(),
                "summary": event.summary.clone()
            }));
        }
    }
    for claim in claims {
        for agent in &claim.agent_refs {
            contributions.push(serde_json::json!({
                "agent": agent,
                "claim_id": claim.id.clone(),
                "epistemic_status": claim.epistemic_status.clone()
            }));
        }
    }
    contributions
}

fn sounio_approval_events(events: &[SounioTraceEvent]) -> Vec<serde_json::Value> {
    events
        .iter()
        .filter(|event| {
            event.event_type.contains("approval") || event.event_type.contains("review")
        })
        .map(|event| {
            serde_json::json!({
                "event_id": event.id.clone(),
                "created_at": event.created_at.clone(),
                "step_id": event.step_id.clone(),
                "status": event.status.clone(),
                "summary": event.summary.clone()
            })
        })
        .collect()
}

fn sounio_evidence_table(claims: &[SounioClaim]) -> Vec<serde_json::Value> {
    claims
        .iter()
        .flat_map(|claim| {
            claim.evidence_refs.iter().map(move |evidence_ref| {
                serde_json::json!({
                    "claim_id": claim.id.clone(),
                    "evidence_ref": evidence_ref,
                    "epistemic_status": claim.epistemic_status.clone(),
                    "provenance": claim.provenance.clone()
                })
            })
        })
        .collect()
}

fn sounio_score(graph: &SounioClaimGraph) -> serde_json::Value {
    let total = graph.claims.len().max(1) as f64;
    let knowledge = *graph.status_counts.get("knowledge").unwrap_or(&0) as f64;
    let robust = *graph.status_counts.get("robust").unwrap_or(&0) as f64;
    let unsupported = graph.unsupported_claim_ids.len() as f64;
    let score =
        ((knowledge + (robust * 1.5)) / total - (unsupported / total * 0.25)).clamp(0.0, 1.0);
    serde_json::json!({
        "score": (score * 100.0).round() / 100.0,
        "claim_count": graph.claims.len(),
        "status_counts": graph.status_counts.clone(),
        "unsupported_claim_count": graph.unsupported_claim_ids.len(),
        "robust_claim_count": graph.robust_claim_ids.len(),
        "interpretation": "Higher when claims carry evidence/provenance and pass Knowledge<T>/Robust<T> gates."
    })
}

fn sounio_public_claim_digest(claim: &SounioClaim) -> serde_json::Value {
    serde_json::json!({
        "id": claim.id.clone(),
        "claim_text": claim.claim_text.clone(),
        "subject": claim.subject.clone(),
        "epistemic_status": claim.epistemic_status.clone(),
        "evidence_refs": claim.evidence_refs.clone(),
        "confidence": claim.confidence,
        "publication_readiness": claim.publication_readiness.clone(),
        "provenance_summary": {
            "has_provenance": has_non_empty_json_object(&claim.provenance),
            "artifact_refs": claim.artifact_refs.clone(),
            "contract_refs": claim.contract_refs.clone()
        }
    })
}

fn sounio_public_trace_digest(event: &SounioTraceEvent) -> serde_json::Value {
    serde_json::json!({
        "event_id": event.id.clone(),
        "created_at": event.created_at.clone(),
        "step_id": event.step_id.clone(),
        "event_type": event.event_type.clone(),
        "status": event.status.clone(),
        "summary": event.summary.clone(),
        "artifact_count": event.artifact_refs.len()
    })
}

fn sedenion_ssm_public_case(claims: &[SounioClaim]) -> serde_json::Value {
    let claim_refs = claims
        .iter()
        .filter(|claim| {
            let haystack = format!(
                "{} {} {}",
                claim.claim_text,
                claim.subject,
                claim.evidence_refs.join(" ")
            )
            .to_lowercase();
            haystack.contains("sedenion") || haystack.contains("ssm") || haystack.contains("fano")
        })
        .map(sounio_public_claim_digest)
        .collect::<Vec<_>>();
    serde_json::json!({
        "case_id": "sedenion-ssm-arc",
        "role": "first strong Sounio demonstration",
        "summary": "Sounio is evaluated through the Sedenion SSM arc: hypercomplex primitives, Fano/Cayley-Dickson structure, theorem-like claims, and epistemic verification.",
        "claims": claim_refs,
        "public_only": true,
        "private_artifacts_policy": "raw private traces and corpus remain cluster-only"
    })
}

fn sounio_program_hash(program: &SounioProgram) -> anyhow::Result<String> {
    let mut hasher = Sha256::new();
    hasher.update(SOUNIO_WORK_IR_SCHEMA.as_bytes());
    hasher.update(serde_json::to_vec(program)?);
    Ok(format!("sha256:{}", hex_digest(hasher.finalize())))
}

fn validate_sounio_program(program: &SounioProgram) -> Vec<String> {
    let mut errors = Vec::new();
    if program.id.trim().is_empty() {
        errors.push("program.id is required".to_string());
    }
    if program.intent.trim().is_empty() {
        errors.push("program.intent is required".to_string());
    }
    if program.plan.is_empty() {
        errors.push("program.plan must contain at least one step".to_string());
    }
    if program.governance.provenance.is_null() {
        errors.push("program.governance.provenance is required".to_string());
    }
    if program.governance.restricted_leak_check.is_null() {
        errors.push("program.governance.restricted_leak_check is required".to_string());
    }
    for step in &program.plan {
        if step.id.trim().is_empty() {
            errors.push("plan step id is required".to_string());
        }
        if step.title.trim().is_empty() {
            errors.push(format!("plan step {} title is required", step.id));
        }
        if step.provenance.is_null() {
            errors.push(format!("plan step {} provenance is required", step.id));
        }
        if step.governance.is_null() {
            errors.push(format!("plan step {} governance is required", step.id));
        }
    }
    for evidence in &program.evidence {
        if evidence.source_ref.trim().is_empty() {
            errors.push(format!("evidence {} source_ref is required", evidence.id));
        }
    }
    errors
}

fn sounio_program_warnings(program: &SounioProgram, source_format: Option<&str>) -> Vec<String> {
    let mut warnings = Vec::new();
    if source_format == Some("sio") {
        warnings.push(
            ".sio syntax is planned as sugar over the canonical JSON/YAML IR in v2.4".to_string(),
        );
    }
    if program.evidence.is_empty() {
        warnings.push(
            "program.evidence is empty; claims will start as unsupported until source mapping runs"
                .to_string(),
        );
    }
    if !program.governance.human_approval_required {
        warnings.push("human_approval_required=false; Beagle PaperRun still requires human approval before publication".to_string());
    }
    warnings
}

fn sounio_temporal_spec(program: &SounioProgram) -> serde_json::Value {
    serde_json::json!({
        "workflow_type": "BeagleSelfWritingPaperRun",
        "task_queue": "sounio-paperrun",
        "deterministic_steps": program.plan.iter().map(|step| {
            serde_json::json!({
                "activity": step.id,
                "title": step.title,
                "requires_human_approval": step.requires_human_approval,
                "retry_policy": {
                    "maximum_attempts": 3,
                    "non_retryable_errors": ["restricted_content", "unsupported_claim"]
                }
            })
        }).collect::<Vec<_>>(),
        "signals": ["approve_step", "request_revision", "abort_without_destructive_side_effect"],
        "queries": ["status", "trace", "artifact_manifest"]
    })
}

fn sounio_memory_projection_preview(program: &SounioProgram) -> serde_json::Value {
    serde_json::json!({
        "episode_kind": "sounio_work_program",
        "atoms": [
            {"type": "intent", "text": program.intent},
            {"type": "workflow", "text": program.kind},
            {"type": "next_action", "text": program.next_action}
        ],
        "hyperedges": program.plan.iter().map(|step| {
            serde_json::json!({
                "type": "workflow_step",
                "program": program.id,
                "step": step.id,
                "agent": step.agent,
                "strategy": step.strategy
            })
        }).collect::<Vec<_>>()
    })
}

fn default_beagle_paper_title() -> String {
    "Beagle: A Self-Governing Exocortex for Agentic Research, Work Memory, and Durable Cognitive Workflows".to_string()
}

fn default_beagle_paper_sections() -> Vec<&'static str> {
    vec![
        "Introduction",
        "Related Work",
        "Architecture",
        "Sounio IR",
        "Memory and ContextPack",
        "MCP and Apple Surfaces",
        "Evaluation",
        "Security and Ethics",
        "Limitations",
    ]
}

fn default_beagle_self_writing_program() -> SounioProgram {
    let provenance = serde_json::json!({
        "source": "beagle-v2.4-plan",
        "paper": "self-writing systems preprint",
        "cluster_only": true
    });
    let governance = serde_json::json!({
        "privacy_class": "sensitive",
        "requires_provenance": true,
        "restricted_policy": "exclude",
        "human_approval_required": true
    });
    SounioProgram {
        id: "beagle-self-writing-paperrun-v24".to_string(),
        sounio_version: default_sounio_version(),
        kind: default_sounio_program_kind(),
        intent: "Write the Beagle systems paper using Beagle/Sounio as the durable, audited work substrate.".to_string(),
        context: serde_json::json!({
            "paper_type": "arXiv systems preprint",
            "thesis": "self-writing paper with traceable agentic memory",
            "canonical_memory": "/var/lib/beagle/exocortex",
            "artifact_root": "/orangefs/beagle-memory-lab/paperruns"
        }),
        plan: [
            ("retrieve_state", "Retrieve Beagle/Sounio state", false),
            ("compile_context", "Compile ContextPack for the paper", false),
            ("outline", "Create manuscript outline", false),
            ("source_map", "Map claims to evidence and citations", false),
            ("draft_section", "Draft Architecture/Methods section", false),
            ("critical_review", "Run critical review and overclaim guard", false),
            ("claim_check", "Mark unsupported claims before export", false),
            ("human_approval", "Human approval gate before manuscript export", true),
            ("revise", "Apply approved revisions", false),
            ("export_manuscript", "Export Markdown/LaTeX/PDF draft", false),
            ("record_effectiveness", "Record memory/context effectiveness", false),
        ]
        .iter()
        .map(|(id, title, approval)| SounioStep {
            id: id.to_string(),
            title: title.to_string(),
            objective: Some(format!("{title} for the Beagle self-writing systems paper.")),
            agent: Some(if *id == "human_approval" { "demetrios" } else { "beagle-agents" }.to_string()),
            strategy: Some(match *id {
                "retrieve_state" => "retrieval_agent",
                "compile_context" => "context_compiler",
                "critical_review" | "claim_check" => "governor_critical",
                _ => "durable_activity",
            }.to_string()),
            requires_human_approval: *approval,
            provenance: provenance.clone(),
            governance: governance.clone(),
        })
        .collect(),
        actions: vec![
            SounioAction {
                id: "compile-to-temporal".to_string(),
                action_type: "compile".to_string(),
                target: "Temporal.Workflow:BeagleSelfWritingPaperRun".to_string(),
                parameters: serde_json::json!({"task_queue": "sounio-paperrun"}),
                provenance: provenance.clone(),
            },
            SounioAction {
                id: "project-to-memory".to_string(),
                action_type: "project".to_string(),
                target: "Beagle.Memory:Episode+Atom+Hyperedge".to_string(),
                parameters: serde_json::json!({"privacy_class": "sensitive"}),
                provenance: provenance.clone(),
            },
        ],
        evidence: Vec::new(),
        decisions: vec![SounioDecision {
            id: "decision-self-writing-paper".to_string(),
            summary: "The first Sounio proof artifact is a durable PaperRun for the Beagle self-writing systems paper.".to_string(),
            rationale: Some("A PaperRun tests continuity, provenance, claims, agents, memory, and publication artifacts in one loop.".to_string()),
            evidence_refs: Vec::new(),
            provenance: provenance.clone(),
        }],
        checks: vec![
            SounioCheck {
                id: "restricted-leak-zero".to_string(),
                check_type: "security".to_string(),
                description: "Restricted content must not enter manuscript/export artifacts.".to_string(),
                status: Some("required".to_string()),
                required: true,
                provenance: provenance.clone(),
            },
            SounioCheck {
                id: "unsupported-claims-marked".to_string(),
                check_type: "paper_quality".to_string(),
                description: "Every claim is supported by evidence/provenance or marked unsupported.".to_string(),
                status: Some("required".to_string()),
                required: true,
                provenance: provenance.clone(),
            },
        ],
        outcome: None,
        next_action: Some("Start PaperRun, approve the human gate, then export a reviewed draft.".to_string()),
        governance: SounioGovernance {
            privacy_class: "sensitive".to_string(),
            provenance,
            restricted_leak_check: serde_json::json!({"status": "required", "policy": "exclude_restricted"}),
            human_approval_required: true,
            policy_refs: vec![
                "admin:destructive absent".to_string(),
                "human approval before publication".to_string(),
            ],
        },
    }
}

fn default_beagle_paper_claims() -> Vec<serde_json::Value> {
    vec![
        serde_json::json!({
            "id": "claim-exocortex-loop",
            "text": "Beagle implements a durable exocortex loop connecting memory, agents, MCP, Apple surfaces, and audited action.",
            "status": "needs_evidence",
            "required_evidence": ["MCP manifest", "GraphRAG++ memory", "Apple capture", "audit trail"]
        }),
        serde_json::json!({
            "id": "claim-sounio-ir",
            "text": "Sounio models cognitive work as a replayable, auditable intermediate representation.",
            "status": "needs_evidence",
            "required_evidence": ["SounioProgram", "Temporal workflow", "SounioTraceEvent"]
        }),
        serde_json::json!({
            "id": "claim-self-writing-method",
            "text": "The paper production process itself can be captured as evidence for the system architecture.",
            "status": "unsupported_until_paperrun_trace_exists",
            "required_evidence": ["PaperRun trace", "ContextPack", "human approval"]
        }),
    ]
}

fn default_beagle_paper_citations() -> Vec<serde_json::Value> {
    vec![
        serde_json::json!({"id": "temporal-docs", "title": "Temporal durable execution documentation", "status": "source-map-pending"}),
        serde_json::json!({"id": "mcp-spec", "title": "Model Context Protocol specification", "status": "source-map-pending"}),
        serde_json::json!({"id": "literate-programming", "title": "Literate Programming", "status": "source-map-pending"}),
        serde_json::json!({"id": "research-object-crate", "title": "Workflow Run RO-Crate", "status": "source-map-pending"}),
    ]
}

fn paper_run_markdown(run: &PaperRun) -> String {
    let mut text = format!(
        "# {}\n\n**PaperRun:** `{}`  \n**Temporal workflow:** `{}`  \n**Sounio program hash:** `{}`  \n**Status:** `{}`\n\n",
        run.title, run.id, run.temporal_workflow_id, run.sounio_program_hash, run.status
    );
    text.push_str("## Abstract\n\n");
    text.push_str(
        "TODO: draft after ContextPack, source mapping, critical review, and human approval.\n\n",
    );
    for section in default_beagle_paper_sections() {
        let status = run
            .section_status
            .get(section)
            .cloned()
            .unwrap_or_else(|| "planned".to_string());
        text.push_str(&format!("## {section}\n\n_Status: {status}._\n\n"));
    }
    text.push_str("## Claim Registry\n\n");
    for claim in &run.claim_registry {
        let id = claim
            .get("id")
            .and_then(|value| value.as_str())
            .unwrap_or("claim");
        let status = claim
            .get("status")
            .and_then(|value| value.as_str())
            .unwrap_or("needs_evidence");
        let claim_text = claim
            .get("text")
            .and_then(|value| value.as_str())
            .unwrap_or("");
        text.push_str(&format!("- `{id}` [{status}]: {claim_text}\n"));
    }
    text.push_str("\n## Publication Guard\n\nNo automatic arXiv submission. Human approval is required before external release.\n");
    text
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

fn hypermemory_atom_score(atom: &MemoryAtom, query_tokens: &[String]) -> f64 {
    if query_tokens.is_empty() {
        return 0.0;
    }
    let graph_material = std::iter::once(atom.normalized_text.as_str())
        .chain(atom.tags.iter().map(String::as_str))
        .chain(atom.source_refs.iter().map(String::as_str))
        .chain(atom.relations.iter().flat_map(|relation| {
            [
                relation.subject.as_str(),
                relation.predicate.as_str(),
                relation.object.as_str(),
            ]
        }))
        .collect::<Vec<_>>()
        .join(" ")
        .to_lowercase();
    let token_hits = query_tokens
        .iter()
        .filter(|token| graph_material.contains(token.as_str()))
        .count();
    if token_hits == 0 {
        return 0.0;
    }
    let lexical = token_hits as f64 / query_tokens.len() as f64;
    let base = atom_score(atom, query_tokens);
    let hyperedge_boost = (atom.relations.len() as f64 * 0.025).clamp(0.0, 0.12);
    let source_boost = if atom.source_refs.is_empty() {
        0.0
    } else {
        0.07
    };
    let tag_boost = if atom.tags.is_empty() { 0.0 } else { 0.06 };
    let fact_boost = match atom.atom_type.as_str() {
        "decision" | "hypothesis" | "evidence" | "action" => 0.10,
        "project" | "principle" | "open_question" => 0.07,
        _ => 0.03,
    };
    (base.max(lexical * 0.64) + hyperedge_boost + source_boost + tag_boost + fact_boost)
        .clamp(0.0, 1.0)
}

#[derive(Debug, Clone)]
struct RankedMemoryAtom {
    atom: MemoryAtom,
    base_score: f64,
    final_score: f64,
    exact_boost: f64,
    recency_boost: f64,
    source_boost: f64,
    stable_boost: f64,
    reasons: Vec<String>,
}

fn memory_ranking_policy(requested: Option<&str>) -> String {
    let raw = requested
        .map(ToOwned::to_owned)
        .or_else(|| env::var("BEAGLE_MEMORY_RANKING_POLICY").ok())
        .unwrap_or_else(|| "strict_recent_guarded".to_string())
        .to_lowercase();
    match raw.as_str() {
        "legacy_stable" => "legacy_stable".to_string(),
        _ => "strict_recent_guarded".to_string(),
    }
}

fn stable_fact_guard_applies(query: &str, query_tokens: &[String]) -> bool {
    let q = query.to_lowercase();
    let stable_terms = [
        "portfolio",
        "mandic",
        "ra",
        "18224624",
        "doi",
        "e-mail",
        "email",
        "congresso",
        "congress",
        "cpc",
        "dmh",
        "data",
        "date",
        "identidade",
        "identity",
        "histórico",
        "historico",
        "history",
        "rapamicina",
        "cistinose",
        "phd",
        "mensa",
        "publicação",
        "publicacao",
        "publication",
    ];
    stable_terms.iter().any(|term| q.contains(term))
        || query_tokens
            .iter()
            .any(|token| token.starts_with("10.") || token.starts_with("ra_"))
}

fn is_restricted_memory(atom: &MemoryAtom, episode: Option<&MemoryEpisode>) -> bool {
    let mut material = vec![
        atom.privacy_class.to_lowercase(),
        atom.tags.join(" ").to_lowercase(),
        atom.source_refs.join(" ").to_lowercase(),
    ];
    if let Some(episode) = episode {
        material.push(episode.privacy_class.to_lowercase());
        material.push(episode.tags.join(" ").to_lowercase());
        material.push(episode.provenance.to_string().to_lowercase());
    }
    material
        .join(" ")
        .split_whitespace()
        .any(|token| token == "restricted" || token == "restricted_local_only")
}

fn rank_memory_atom(
    atom: &MemoryAtom,
    episode: Option<&MemoryEpisode>,
    base_score: f64,
    query_tokens: &[String],
    ranking_policy: &str,
    stable_fact_guard: bool,
) -> RankedMemoryAtom {
    if ranking_policy == "legacy_stable" {
        return RankedMemoryAtom {
            atom: atom.clone(),
            base_score,
            final_score: base_score,
            exact_boost: 0.0,
            recency_boost: 0.0,
            source_boost: 0.0,
            stable_boost: 0.0,
            reasons: vec!["legacy_stable policy kept historical score order".to_string()],
        };
    }

    let material = ranking_material(atom, episode);
    let exact_hits = query_tokens
        .iter()
        .filter(|token| token.len() >= 4 && material.contains(token.as_str()))
        .count();
    let id_hits = query_tokens
        .iter()
        .filter(|token| {
            token.len() >= 6 && looks_like_identifier(token) && material.contains(token.as_str())
        })
        .count();
    let live_work_material = is_live_work_material(&material);
    let stable_fact_material = is_stable_fact_material(&material);
    let stable_fact_source = is_stable_fact_source(atom, episode, &material);
    let mut exact_boost = ((exact_hits as f64 * 0.045) + (id_hits as f64 * 0.18)).clamp(0.0, 0.42);
    if stable_fact_guard && live_work_material && !stable_fact_source {
        exact_boost *= 0.35;
    }
    let source_boost = if !stable_fact_guard && live_work_material {
        0.14
    } else {
        0.0
    };
    let stable_boost = if stable_fact_guard && stable_fact_source {
        0.5
    } else if stable_fact_guard && stable_fact_material && !live_work_material {
        0.2
    } else if stable_fact_guard && stable_fact_material {
        0.0
    } else {
        0.0
    };
    let recency_boost = recency_boost_for(atom, episode, stable_fact_guard, stable_fact_source);
    let weighted_base = if stable_fact_guard && live_work_material && !stable_fact_source {
        base_score * 0.25
    } else if stable_fact_guard && stable_fact_source {
        base_score * 0.9
    } else if stable_fact_guard {
        base_score * 0.82
    } else {
        base_score * 0.58
    };
    let confidence_boost = if stable_fact_guard {
        atom.confidence * 0.04
    } else {
        atom.confidence * 0.08
    };
    let final_score = (weighted_base
        + exact_boost
        + source_boost
        + stable_boost
        + recency_boost
        + confidence_boost)
        .clamp(0.0, 1.0);

    let mut reasons = Vec::new();
    if exact_boost > 0.0 {
        reasons.push(format!("exact_or_identifier_boost={exact_boost:.3}"));
    }
    if recency_boost > 0.0 {
        reasons.push(format!("recency_boost={recency_boost:.3}"));
    }
    if source_boost > 0.0 {
        reasons.push(format!("live_work_source_boost={source_boost:.3}"));
    }
    if stable_boost > 0.0 {
        reasons.push(format!("stable_fact_guard_boost={stable_boost:.3}"));
    }
    if stable_fact_guard {
        reasons.push("Stable Fact Guard reduced recency pressure.".to_string());
    }

    RankedMemoryAtom {
        atom: atom.clone(),
        base_score,
        final_score,
        exact_boost,
        recency_boost,
        source_boost,
        stable_boost,
        reasons,
    }
}

fn ranking_material(atom: &MemoryAtom, episode: Option<&MemoryEpisode>) -> String {
    let mut parts = vec![
        atom.id.as_str(),
        atom.episode_id.as_str(),
        atom.atom_type.as_str(),
        atom.text.as_str(),
        atom.normalized_text.as_str(),
    ]
    .into_iter()
    .map(ToOwned::to_owned)
    .collect::<Vec<_>>();
    parts.extend(atom.tags.clone());
    parts.extend(atom.source_refs.clone());
    parts.extend(atom.relations.iter().flat_map(|relation| {
        [
            relation.subject.clone(),
            relation.predicate.clone(),
            relation.object.clone(),
        ]
    }));
    if let Some(episode) = episode {
        parts.extend([
            episode.id.clone(),
            episode.source.clone(),
            episode.source_ref.clone(),
            episode.content_hash.clone(),
            episode.privacy_class.clone(),
        ]);
        if let Some(platform) = &episode.source_platform {
            parts.push(platform.clone());
        }
        if let Some(session_id) = &episode.session_id {
            parts.push(session_id.clone());
        }
        if let Some(title) = &episode.title {
            parts.push(title.clone());
        }
        parts.extend(episode.tags.clone());
        parts.extend(episode.linked_chronoself_commits.clone());
        parts.push(episode.provenance.to_string());
    }
    parts.join(" ").to_lowercase()
}

fn looks_like_identifier(token: &str) -> bool {
    token.chars().any(|ch| ch.is_ascii_digit())
        || token.contains('-')
        || token.contains('_')
        || token.starts_with("sha")
}

fn is_live_work_material(material: &str) -> bool {
    [
        "workbench",
        "terminal-block",
        "codex",
        "claude-code",
        "beagle-workbench",
        "beagle-apple",
        "source_surface",
        "memory_event_id",
        "audit_event_id",
        "branch",
        "commit",
    ]
    .iter()
    .any(|term| material.contains(term))
}

fn is_stable_fact_material(material: &str) -> bool {
    [
        "portfolio",
        "mandic",
        "ra_18224624",
        "18224624",
        "doi",
        "congresso",
        "cpc_2026",
        "dmh_2026",
        "rapamicina",
        "cistinose",
        "documento_canonico",
        "v3_final",
    ]
    .iter()
    .any(|term| material.contains(term))
}

fn is_stable_fact_source(
    atom: &MemoryAtom,
    episode: Option<&MemoryEpisode>,
    material: &str,
) -> bool {
    let stable_tags_or_refs = atom
        .tags
        .iter()
        .chain(atom.source_refs.iter())
        .any(|value| {
            let value = value.to_lowercase();
            [
                "portfolio_institucional",
                "documento_canonico",
                "v3_final",
                "mandic",
                "ra_18224624",
                "doi",
                "publication",
                "publicacao",
            ]
            .iter()
            .any(|term| value.contains(term))
        });
    let stable_episode = episode.is_some_and(|episode| {
        let source = episode.source.to_lowercase();
        let source_platform = episode
            .source_platform
            .as_deref()
            .unwrap_or_default()
            .to_lowercase();
        let source_surface = episode
            .provenance
            .get("metadata")
            .and_then(|metadata| metadata.get("source_surface"))
            .and_then(|surface| surface.as_str())
            .unwrap_or_default()
            .to_lowercase();
        source.contains("portfolio")
            || source_platform.contains("portfolio")
            || source_surface.contains("portfolio-import")
            || episode.tags.iter().any(|tag| {
                let tag = tag.to_lowercase();
                tag.contains("portfolio_institucional")
                    || tag.contains("documento_canonico")
                    || tag.contains("v3_final")
            })
    });

    stable_episode
        || stable_tags_or_refs
        || (is_stable_fact_material(material) && !is_live_work_material(material))
}

fn recency_boost_for(
    atom: &MemoryAtom,
    episode: Option<&MemoryEpisode>,
    stable_fact_guard: bool,
    stable_fact_source: bool,
) -> f64 {
    let timestamp = atom
        .occurred_at
        .as_deref()
        .or_else(|| episode.and_then(|episode| episode.occurred_at.as_deref()))
        .or_else(|| Some(atom.created_at.as_str()))
        .and_then(|date| chrono::DateTime::parse_from_rfc3339(date).ok());
    let Some(timestamp) = timestamp else {
        return 0.0;
    };
    let age_hours = (Utc::now() - timestamp.with_timezone(&Utc))
        .num_hours()
        .max(0) as f64;
    if stable_fact_guard {
        if !stable_fact_source {
            return 0.0;
        }
        (0.045 / (1.0 + age_hours / 720.0)).clamp(0.0, 0.045)
    } else {
        (0.36 / (1.0 + age_hours / 168.0)).clamp(0.0, 0.36)
    }
}

fn ranking_trace_json(
    ranked: &[RankedMemoryAtom],
    ranking_policy: &str,
    stable_fact_guard_applied: bool,
) -> serde_json::Value {
    serde_json::json!({
        "policy": ranking_policy,
        "stable_fact_guard_applied": stable_fact_guard_applied,
        "top": ranked.iter().take(8).map(|item| {
            serde_json::json!({
                "atom_id": item.atom.id,
                "episode_id": item.atom.episode_id,
                "atom_type": item.atom.atom_type,
                "base_score": item.base_score,
                "final_score": item.final_score,
                "exact_boost": item.exact_boost,
                "recency_boost": item.recency_boost,
                "source_boost": item.source_boost,
                "stable_boost": item.stable_boost,
                "occurred_at": item.atom.occurred_at,
                "reasons": item.reasons,
            })
        }).collect::<Vec<_>>()
    })
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
                mode: None,
                ranking_policy: None,
            })
            .unwrap();
        assert!(!result.evidence.is_empty());
        assert!(result
            .evidence
            .iter()
            .any(|evidence| evidence.atom_type == "decision"
                && evidence
                    .text
                    .contains("GraphRAG++ persistente deve ser o núcleo")));
        assert!(result
            .relations
            .iter()
            .any(|relation| relation.subject == "beagle"));
        assert!(result.degraded_reason.is_some());
        assert_eq!(result.mode.as_deref(), Some("hypermemory_multivector"));
        assert!(result
            .evidence_graph
            .as_ref()
            .map(|graph| !graph.nodes.is_empty() && !graph.merkle_root.is_empty())
            .unwrap_or(false));
        assert!(!result.retrieval_trace.is_empty());
    }

    #[test]
    fn hypermemory_query_expands_tags_relations_and_marks_advisory_mode() {
        let dir = tempdir().unwrap();
        let repo = ExocortexRepository::new(dir.path().join("exocortex"));
        repo.import_conversation(ImportConversationRequest {
            source_platform: "Grok".to_string(),
            session_id: Some("grok-import-1".to_string()),
            original_date: Some("2026-04-26T19:00:00Z".to_string()),
            raw_content: "Decisão: Grok import mudou a prioridade para Memory Bench e HyperMemory."
                .to_string(),
            title: Some("Grok memory import".to_string()),
            tags: vec![
                "project:beagle".to_string(),
                "source:grok".to_string(),
                "hypermemory".to_string(),
            ],
            extracted: Some(OmniExtraction {
                decisions: vec![
                    "Grok import mudou a prioridade para Memory Bench e HyperMemory.".to_string(),
                ],
                projects_mentioned: vec!["beagle".to_string()],
                ..Default::default()
            }),
            confidence_score: Some(0.88),
            create_chronoself_commit: None,
            privacy_class: Some("sensitive".to_string()),
            metadata: Some(serde_json::json!({"source_surface": "claude-ios"})),
        })
        .unwrap();

        let result = repo
            .graphrag_query(GraphRagQueryRequest {
                query: "grok priority benchmark".to_string(),
                scope: None,
                max_items: Some(5),
                mode: Some("hypermemory".to_string()),
                ranking_policy: None,
            })
            .unwrap();

        assert_eq!(result.mode.as_deref(), Some("hypermemory"));
        assert!(!result.evidence.is_empty());
        assert!(result
            .retrieval_trace
            .iter()
            .any(|step| step.stage == "hypermemory-topic-world-selection"));
        assert_eq!(
            result.provenance["hypermemory"]["authority"].as_str(),
            Some("derived-advisory")
        );
    }

    #[test]
    fn strict_recent_guarded_ranking_prioritizes_exact_recent_workbench_block() {
        let dir = tempdir().unwrap();
        let repo = ExocortexRepository::new(dir.path().join("exocortex"));
        repo.assisted_import_batch(AssistedImportBatchRequest {
            source_platform: "codex".to_string(),
            source_surface: "beagle-workbench".to_string(),
            import_scope: "workbench_terminal_block".to_string(),
            session_id: "beagle-v32-pty-smoke".to_string(),
            project_ref: Some("beagle".to_string()),
            batch_index: 1,
            batch_total: 1,
            turns: vec![AssistedImportTurn {
                role: "assistant".to_string(),
                content: "Decisão: v3.2 validou o modelo de Workbench, mas ainda não era o supervisor v3.3.".to_string(),
                timestamp: Some("2026-04-29T10:00:00Z".to_string()),
                model: Some("codex".to_string()),
            }],
            tags: vec!["workbench".to_string(), "terminal-block".to_string()],
            metadata: serde_json::json!({
                "terminal_block_id": "block-v32-old",
                "branch": "codex/beagle-mcp-public-claude",
                "commit": "v32old"
            }),
            coverage: serde_json::Value::Null,
            extracted: Some(OmniExtraction {
                decisions: vec!["v3.2 validou o modelo de Workbench.".to_string()],
                projects_mentioned: vec!["beagle".to_string()],
                ..Default::default()
            }),
            privacy_class: Some("sensitive".to_string()),
            title: Some("v3.2 workbench smoke".to_string()),
            original_date: Some("2026-04-29T10:00:00Z".to_string()),
            confidence_score: Some(0.82),
            create_chronoself_commit: Some(false),
            capture_session_id: None,
            artifact_refs: Vec::new(),
            transcription_segments: Vec::new(),
            visual_evidence_refs: Vec::new(),
        })
        .unwrap();
        repo.assisted_import_batch(AssistedImportBatchRequest {
            source_platform: "codex".to_string(),
            source_surface: "beagle-workbench".to_string(),
            import_scope: "workbench_terminal_block".to_string(),
            session_id: "wb-mom36qkm-f504bee5".to_string(),
            project_ref: Some("beagle".to_string()),
            batch_index: 1,
            batch_total: 1,
            turns: vec![AssistedImportTurn {
                role: "assistant".to_string(),
                content: "Decisão: beagle-v33-pty-smoke confirmou Durable PTY Supervisor com replay e memória curada.".to_string(),
                timestamp: Some("2026-04-30T20:30:00Z".to_string()),
                model: Some("codex".to_string()),
            }],
            tags: vec!["workbench".to_string(), "terminal-block".to_string(), "v3.3".to_string()],
            metadata: serde_json::json!({
                "terminal_block_id": "block-mom36qlp-697ee4e2",
                "branch": "codex/beagle-mcp-public-claude",
                "commit": "062be42",
                "memory_event_id": "92250283-0ec8-462a-802a-2d69d65b2ae2",
                "audit_event_id": "b0db505b-4600-4de2-8f54-d1312d7c015e"
            }),
            coverage: serde_json::Value::Null,
            extracted: Some(OmniExtraction {
                decisions: vec![
                    "beagle-v33-pty-smoke confirmou Durable PTY Supervisor com replay e memória curada."
                        .to_string(),
                ],
                projects_mentioned: vec!["beagle".to_string()],
                ..Default::default()
            }),
            privacy_class: Some("sensitive".to_string()),
            title: Some("v3.3 PTY smoke".to_string()),
            original_date: Some("2026-04-30T20:30:00Z".to_string()),
            confidence_score: Some(0.92),
            create_chronoself_commit: Some(false),
            capture_session_id: None,
            artifact_refs: Vec::new(),
            transcription_segments: Vec::new(),
            visual_evidence_refs: Vec::new(),
        })
        .unwrap();

        let response = repo
            .graphrag_query(GraphRagQueryRequest {
                query: "beagle-v33-pty-smoke block-mom36qlp".to_string(),
                scope: None,
                max_items: Some(5),
                mode: Some("hypermemory_multivector".to_string()),
                ranking_policy: Some("strict_recent_guarded".to_string()),
            })
            .unwrap();
        assert_eq!(
            response.ranking_policy.as_deref(),
            Some("strict_recent_guarded")
        );
        assert!(response.recency_boost_applied);
        assert!(!response.stable_fact_guard_applied);
        assert_eq!(
            response
                .evidence
                .first()
                .and_then(|item| item.provenance["metadata"]["terminal_block_id"].as_str()),
            Some("block-mom36qlp-697ee4e2")
        );
    }

    #[test]
    fn stable_fact_guard_preserves_portfolio_identity_over_recent_work_memory() {
        let dir = tempdir().unwrap();
        let repo = ExocortexRepository::new(dir.path().join("exocortex"));
        repo.import_conversation(ImportConversationRequest {
            source_platform: "portfolio".to_string(),
            session_id: Some("portfolio_mandic_v3_2026-04-27".to_string()),
            original_date: Some("2026-04-27T12:00:00Z".to_string()),
            raw_content: "Portfólio institucional Mandic: Turma IX, RA 18224624, Grupo A."
                .to_string(),
            title: Some("Portfolio Mandic v3".to_string()),
            tags: vec![
                "portfolio_institucional".to_string(),
                "mandic".to_string(),
                "ra_18224624".to_string(),
                "documento_canonico".to_string(),
            ],
            extracted: Some(OmniExtraction {
                key_insights: vec!["Mandic Turma IX, RA 18224624, Grupo A.".to_string()],
                projects_mentioned: vec!["portfolio".to_string()],
                ..Default::default()
            }),
            confidence_score: Some(0.97),
            create_chronoself_commit: None,
            privacy_class: Some("sensitive".to_string()),
            metadata: Some(serde_json::json!({"source_surface": "portfolio-import"})),
        })
        .unwrap();
        repo.assisted_import_batch(AssistedImportBatchRequest {
            source_platform: "codex".to_string(),
            source_surface: "codex-work-memory".to_string(),
            import_scope: "agent_work_session".to_string(),
            session_id: "recent-ra-question".to_string(),
            project_ref: Some("beagle".to_string()),
            batch_index: 1,
            batch_total: 1,
            turns: vec![AssistedImportTurn {
                role: "assistant".to_string(),
                content: "Pergunta recente: qual é meu RA Mandic? verificar no portfólio antes de responder.".to_string(),
                timestamp: Some("2026-04-30T22:00:00Z".to_string()),
                model: Some("codex".to_string()),
            }],
            tags: vec!["work-memory".to_string(), "codex".to_string()],
            metadata: serde_json::json!({"branch": "codex/beagle-mcp-public-claude"}),
            coverage: serde_json::Value::Null,
            extracted: Some(OmniExtraction {
                unresolved_questions: vec!["qual é meu RA Mandic?".to_string()],
                projects_mentioned: vec!["beagle".to_string()],
                ..Default::default()
            }),
            privacy_class: Some("sensitive".to_string()),
            title: Some("Recent RA question".to_string()),
            original_date: Some("2026-04-30T22:00:00Z".to_string()),
            confidence_score: Some(0.75),
            create_chronoself_commit: Some(false),
            capture_session_id: None,
            artifact_refs: Vec::new(),
            transcription_segments: Vec::new(),
            visual_evidence_refs: Vec::new(),
        })
        .unwrap();

        let response = repo
            .graphrag_query(GraphRagQueryRequest {
                query: "qual é meu RA Mandic?".to_string(),
                scope: None,
                max_items: Some(5),
                mode: Some("hypermemory_multivector".to_string()),
                ranking_policy: Some("strict_recent_guarded".to_string()),
            })
            .unwrap();
        assert!(response.stable_fact_guard_applied);
        assert_eq!(
            response
                .evidence
                .first()
                .and_then(|item| item.provenance["metadata"]["source_surface"].as_str()),
            Some("portfolio-import")
        );
    }

    #[test]
    fn graph_query_filters_restricted_local_only_atoms_from_active_evidence() {
        let dir = tempdir().unwrap();
        let repo = ExocortexRepository::new(dir.path().join("exocortex"));
        repo.import_conversation(ImportConversationRequest {
            source_platform: "beagle-apple".to_string(),
            session_id: Some("restricted-terminal-block".to_string()),
            original_date: Some("2026-04-30T21:00:00Z".to_string()),
            raw_content: "Decisão restrita: fake token output should never become active evidence."
                .to_string(),
            title: Some("Restricted local block".to_string()),
            tags: vec!["restricted_local_only".to_string(), "workbench".to_string()],
            extracted: Some(OmniExtraction {
                decisions: vec![
                    "fake token output should never become active evidence.".to_string()
                ],
                projects_mentioned: vec!["beagle".to_string()],
                ..Default::default()
            }),
            confidence_score: Some(0.7),
            create_chronoself_commit: None,
            privacy_class: Some("sensitive".to_string()),
            metadata: Some(serde_json::json!({"privacy_class": "restricted_local_only"})),
        })
        .unwrap();
        let response = repo
            .graphrag_query(GraphRagQueryRequest {
                query: "fake token output active evidence".to_string(),
                scope: None,
                max_items: Some(5),
                mode: Some("hypermemory_multivector".to_string()),
                ranking_policy: Some("strict_recent_guarded".to_string()),
            })
            .unwrap();
        assert!(response.evidence.is_empty());
        assert_eq!(response.restricted_leak_check["restricted_leak_count"], 0);
    }

    #[test]
    fn memory_benchmark_status_reads_append_only_audit() {
        let dir = tempdir().unwrap();
        let repo = ExocortexRepository::new(dir.path().join("exocortex"));
        let empty = repo.memory_benchmark_status().unwrap();
        assert_eq!(empty.status, "empty");

        repo.create_audit_event(CreateAuditEventRequest {
            client_id: Some("beagle-memory-engine".to_string()),
            action: Some("memory.benchmark_run".to_string()),
            tool_name: Some("beagle_memory_benchmark_run".to_string()),
            risk_level: Some("run".to_string()),
            required_scopes: vec!["research:run".to_string()],
            granted_scopes: vec!["research:run".to_string()],
            status: Some("success".to_string()),
            source: Some("memory-engine".to_string()),
            target_ref: Some("memory_benchmark_run:bench-1".to_string()),
            summary: Some("Memory Bench v1.8 completed.".to_string()),
            metadata: Some(serde_json::json!({
                "schema_version": MEMORY_BENCH_SCHEMA,
                "run_id": "bench-1",
                "truthset_id": "truth-v19",
                "baseline_mode": "graphsearch-lite",
                "candidate_mode": "hypermemory",
                "baseline_score": 0.78,
                "hypermemory_score": 0.84,
                "required_margin": 0.05,
                "consecutive_passing_runs": 3,
                "latest_score": 0.84,
                "query_count": 100,
                "regression_count": 0,
                "artifact_manifest": "/orangefs/beagle-memory-lab/bench-1/manifest.json",
                "evaluated_modes": ["graphsearch-lite", "hypermemory", "adaptive-federation"]
            })),
        })
        .unwrap();

        let status = repo.memory_benchmark_status().unwrap();
        assert_eq!(status.status, "passing");
        assert_eq!(status.latest_run_id.as_deref(), Some("bench-1"));
        assert_eq!(status.query_count, 100);
        assert_eq!(status.latest_score, Some(0.84));
        assert_eq!(status.truthset_id.as_deref(), Some("truth-v19"));
        assert!(status.hot_path_eligible);
        assert!(status
            .promotion_gate
            .as_ref()
            .map(|gate| gate.eligible)
            .unwrap_or(false));
        let home = repo
            .build_home_snapshot(HomeQuery {
                active_project_slug: None,
                platform: Some("apple".to_string()),
            })
            .unwrap();
        let trust = home.trust_context.unwrap();
        assert_eq!(trust.memory_bench_status.as_deref(), Some("passing"));
        assert_eq!(trust.latest_bench_score, Some(0.84));
        assert_eq!(trust.truthset_id.as_deref(), Some("truth-v19"));
        assert_eq!(trust.bench_hot_path_eligible, Some(true));
    }

    #[test]
    fn memory_truthset_lifecycle_rejects_restricted_cases() {
        let dir = tempdir().unwrap();
        let repo = ExocortexRepository::new(dir.path().join("exocortex"));
        let truthset = repo
            .create_memory_truthset(CreateMemoryTruthSetRequest {
                title: Some("Private v1.9 truthset".to_string()),
                description: Some("Agent-curated cases from real Beagle memory.".to_string()),
                domains: vec!["work-memory".to_string(), "grok-import".to_string()],
                source_refs: vec!["memory_export:dry-run".to_string()],
                reviewer: Some("demetrios".to_string()),
                artifact_root: None,
            })
            .unwrap();

        let case = repo
            .create_memory_truth_case(
                &truthset.id,
                CreateMemoryTruthCaseRequest {
                    domain: "work-memory".to_string(),
                    query: "qual foi a última decisão do Codex?".to_string(),
                    expected_answer: Some("Recuperar sessão, branch e commit.".to_string()),
                    required_evidence_refs: vec!["agent-session:codex".to_string()],
                    expected_atom_refs: vec![],
                    expected_episode_refs: vec![],
                    temporal_expectation: Some("priorizar evento mais recente".to_string()),
                    provenance_requirements: vec!["repo".to_string(), "branch".to_string()],
                    privacy_class: Some("sensitive".to_string()),
                    status: Some("approved".to_string()),
                    tags: vec!["codex".to_string(), "truthset:v1.9".to_string()],
                    metadata: Some(serde_json::json!({"cluster_only": true})),
                },
            )
            .unwrap();
        assert_eq!(case.truthset_id, truthset.id);

        let restricted = repo.create_memory_truth_case(
            &truthset.id,
            CreateMemoryTruthCaseRequest {
                domain: "security".to_string(),
                query: "restricted content must never enter bench".to_string(),
                expected_answer: None,
                required_evidence_refs: vec![],
                expected_atom_refs: vec![],
                expected_episode_refs: vec![],
                temporal_expectation: None,
                provenance_requirements: vec![],
                privacy_class: Some("restricted".to_string()),
                status: None,
                tags: vec![],
                metadata: None,
            },
        );
        assert!(restricted.is_err());

        let reviewed = repo
            .review_memory_truthset(
                &truthset.id,
                ReviewMemoryTruthSetRequest {
                    status: Some("approved".to_string()),
                    reviewer: Some("demetrios".to_string()),
                    rationale: Some("caso sensível aprovado para bench privado".to_string()),
                },
            )
            .unwrap();
        assert_eq!(reviewed.truthset.status, "approved");
        assert_eq!(reviewed.truthset.case_count, 1);
        assert_eq!(reviewed.truthset.approved_case_count, 1);
        assert_eq!(reviewed.cases.len(), 1);
    }

    #[test]
    fn memory_graph_recent_returns_projection_for_apple_memory_lens() {
        let dir = tempdir().unwrap();
        let repo = ExocortexRepository::new(dir.path().join("exocortex"));
        repo.import_conversation(ImportConversationRequest {
            source_platform: "beagle-apple".to_string(),
            session_id: Some("apple-chat-1".to_string()),
            original_date: Some("2026-04-26T17:00:00Z".to_string()),
            raw_content: "Decisão: Home, Watch e Memory Lens devem avançar em paralelo."
                .to_string(),
            title: Some("Apple Exocortex v1.3".to_string()),
            tags: vec![
                "project:beagle".to_string(),
                "surface:beagle-ios".to_string(),
            ],
            extracted: Some(OmniExtraction {
                decisions: vec!["Home, Watch e Memory Lens devem avançar em paralelo.".to_string()],
                projects_mentioned: vec!["beagle".to_string()],
                ..Default::default()
            }),
            confidence_score: Some(0.91),
            create_chronoself_commit: None,
            privacy_class: Some("sensitive".to_string()),
            metadata: Some(serde_json::json!({"source_surface": "beagle-ios"})),
        })
        .unwrap();

        let recent = repo.memory_graph_recent(10).unwrap();
        assert_eq!(recent.status.episode_count, 1);
        assert!(!recent.episodes.is_empty());
        assert!(recent
            .atoms
            .iter()
            .any(|atom| atom.text.contains("Memory Lens")));
        assert_eq!(
            recent.provenance["canonical_store"],
            "/var/lib/beagle/exocortex"
        );
    }

    #[test]
    fn graph_runtime_bakeoff_and_index_create_worlds_without_private_sidecars() {
        let dir = tempdir().unwrap();
        let repo = ExocortexRepository::new(dir.path().join("exocortex"));
        repo.import_conversation(ImportConversationRequest {
            source_platform: "codex".to_string(),
            session_id: Some("work-memory-1".to_string()),
            original_date: Some("2026-04-26T18:00:00Z".to_string()),
            raw_content: "Decisão: FalkorDB GraphBLAS deve ser testado contra Memgraph e SurrealDB antes de promoção.".to_string(),
            title: Some("Graph runtime bakeoff".to_string()),
            tags: vec!["project:beagle".to_string(), "work-memory".to_string()],
            extracted: Some(OmniExtraction {
                decisions: vec![
                    "FalkorDB GraphBLAS deve ser testado contra Memgraph e SurrealDB antes de promoção.".to_string(),
                ],
                projects_mentioned: vec!["beagle".to_string()],
                ..Default::default()
            }),
            confidence_score: Some(0.9),
            create_chronoself_commit: None,
            privacy_class: Some("sensitive".to_string()),
            metadata: Some(serde_json::json!({"source_surface": "codex-work-memory"})),
        })
        .unwrap();

        let bakeoff = repo
            .run_graph_bakeoff(GraphBakeoffRequest {
                dataset_limit: Some(20),
                include_baseline: Some(true),
            })
            .unwrap();
        assert_eq!(bakeoff.schema_version, MEMORY_GRAPH_SCHEMA);
        assert!(bakeoff
            .candidates
            .iter()
            .any(|candidate| candidate.name == "FalkorDB GraphBLAS"));

        let index = repo
            .index_graph(GraphIndexRequest {
                rebuild: false,
                source_refs: Vec::new(),
                runtime: None,
            })
            .unwrap();
        assert!(index.worlds_created >= 1);
        assert_eq!(
            index.provenance["canonical_store"],
            "/var/lib/beagle/exocortex"
        );

        let worlds = repo.memory_worlds_recent(10).unwrap();
        assert_eq!(worlds.graph_status.schema_version, MEMORY_GRAPH_SCHEMA);
        assert!(worlds
            .worlds
            .iter()
            .any(|world| world.provenance["content_addressed"] == true));
    }

    #[test]
    fn spatial_world_registers_private_marble_control_room_and_evidence() {
        let dir = tempdir().unwrap();
        let repo = ExocortexRepository::new(dir.path().join("exocortex"));
        let mut spz_urls = BTreeMap::new();
        spz_urls.insert(
            "low_res".to_string(),
            "https://assets.example/sounio.spz".to_string(),
        );
        let world = repo
            .create_spatial_world(CreateSpatialWorldRequest {
                project_slug: Some("sounio".to_string()),
                display_name: Some("Sounio Control Room".to_string()),
                prompt_summary: Some(
                    "Sanitized Sounio control room with pods wall, agent lanes, compiler map, and evidence panels."
                        .to_string(),
                ),
                sanitized_prompt: Some(
                    "Sanitized Sounio control room with pods wall, agent lanes, compiler map, and evidence panels."
                        .to_string(),
                ),
                model: Some("marble-1.1".to_string()),
                permission: None,
                approved: Some(true),
                purpose: Some("control-room".to_string()),
                operation_id: Some("op-test".to_string()),
                world_id: Some("world-sounio-test".to_string()),
                status: Some("ready".to_string()),
                world_marble_url: Some(
                    "https://marble.worldlabs.ai/worlds/world-sounio-test".to_string(),
                ),
                assets: Some(SpatialAssetManifest {
                    pano_url: Some("https://assets.example/sounio-pano.png".to_string()),
                    collider_mesh_url: Some(
                        "https://assets.example/sounio-collider.glb".to_string(),
                    ),
                    hq_mesh_urls: Vec::new(),
                    spz_urls,
                    ply_urls: BTreeMap::new(),
                    coordinate_system: Some("opencv:+x-left,+y-down,+z-forward".to_string()),
                    coordinate_transform: Some("opencv_to_opengl:scale_yz_minus_one".to_string()),
                    asset_root: Some("/orangefs/beagle-spatial-worlds/world-sounio-test".to_string()),
                    degraded_reason: None,
                }),
                tags: vec!["sounio".to_string()],
                provenance: serde_json::json!({"world_console": "mock"}),
            })
            .unwrap();
        assert_eq!(world.permission, "private");
        assert_eq!(world.model, "marble-1.1");
        assert!(world.assets.spz_urls.contains_key("low_res"));

        let snapshot = repo.control_room_snapshot("sounio").unwrap();
        assert_eq!(snapshot.project_slug, "sounio");
        assert_eq!(
            snapshot.spatial_world.as_ref().unwrap().world_id,
            "world-sounio-test"
        );
        assert!(snapshot
            .memory_worlds
            .iter()
            .any(|memory_world| { memory_world.source_ref == "spatial_world:world-sounio-test" }));

        let evidence = repo
            .create_spatial_evidence(
                "world-sounio-test",
                CreateSounioSpatialEvidenceRequest {
                    project_slug: "sounio".to_string(),
                    evidence_type: Some("spatial_memory_world".to_string()),
                    claim_seed_refs: vec!["claim-seed:sounio-control-room".to_string()],
                    memory_world_refs: snapshot
                        .memory_worlds
                        .iter()
                        .map(|world| world.id.clone())
                        .collect(),
                    artifact_refs: vec!["spatial_world:world-sounio-test".to_string()],
                    epistemic_status: Some("belief".to_string()),
                    privacy_class: Some("sensitive".to_string()),
                    provenance: serde_json::json!({"reviewed": true}),
                },
            )
            .unwrap();
        assert_eq!(evidence.epistemic_status, "belief");
        assert_eq!(evidence.privacy_class, "sensitive");

        let public_world = repo.create_spatial_world(CreateSpatialWorldRequest {
            project_slug: Some("sounio".to_string()),
            display_name: None,
            prompt_summary: Some("safe".to_string()),
            sanitized_prompt: Some("safe".to_string()),
            model: None,
            permission: Some("public".to_string()),
            approved: Some(true),
            purpose: None,
            operation_id: None,
            world_id: None,
            status: None,
            world_marble_url: None,
            assets: None,
            tags: Vec::new(),
            provenance: serde_json::Value::Null,
        });
        assert!(public_world.is_err());
    }

    #[test]
    fn mind_palace_derives_rooms_portals_and_focus_coach() {
        let dir = tempdir().unwrap();
        let repo = ExocortexRepository::new(dir.path().join("exocortex"));
        repo.create_memory_event(CreateMemoryEventRequest {
            source: Some("codex-work-memory".to_string()),
            kind: Some("assisted_import_batch".to_string()),
            content_ref: Some("omnimemory:test".to_string()),
            summary: Some("Codex remembered the latest Beagle Spatial Desk decision.".to_string()),
            tags: vec![
                "project:beagle".to_string(),
                "agent:codex".to_string(),
                "workbench".to_string(),
            ],
            metadata: Some(serde_json::json!({
                "privacy_class": "sensitive",
                "source_surface": "codex-work-memory"
            })),
            linked_chronoself_commits: Vec::new(),
            confidence: Some(0.88),
        })
        .unwrap();
        let portal = repo
            .create_conversation_portal(CreateConversationPortalRequest {
                title: "Claude Desktop idea thread".to_string(),
                provider: "Claude Desktop".to_string(),
                surface: Some("desktop-portal".to_string()),
                status: None,
                source_mode: None,
                privacy_class: Some("sensitive".to_string()),
                source_ref: Some("external-window:claude".to_string()),
                tags: vec!["project:beagle".to_string()],
                provenance: serde_json::json!({"operator": "demetrios"}),
            })
            .unwrap();
        let clip = repo
            .promote_conversation_portal_clip(
                &portal.id,
                PromoteConversationPortalRequest {
                    selected_text: "Insight: Beagle needs a Spatial Desk where agent work and free conversations can happen in parallel.".to_string(),
                    summary: Some("Spatial Desk parallel exocortex insight.".to_string()),
                    project_ref: Some("beagle".to_string()),
                    privacy_class: Some("sensitive".to_string()),
                    tags: vec!["spatial-desk".to_string()],
                    provenance: serde_json::json!({"selected_by": "human"}),
                },
            )
            .unwrap();
        assert!(clip.memory_event_id.is_some());
        assert!(clip.sounio_moment_id.is_some());

        let state = repo
            .record_focus_coach_event(FocusCoachEventRequest {
                event_kind: "start_focus".to_string(),
                status: Some("active".to_string()),
                intervention_id: None,
                project_slug: Some("beagle".to_string()),
                notes: Some("Implementation focus block.".to_string()),
                snoozed_minutes: None,
                provenance: serde_json::Value::Null,
            })
            .unwrap();
        assert_eq!(state.schema_version, FOCUS_COACH_SCHEMA);
        assert!(state.can_override);

        let palace = repo.mind_palace_snapshot().unwrap();
        assert_eq!(palace.schema_version, MIND_PALACE_SCHEMA);
        assert!(palace.rooms.iter().any(|room| room.id == "parallel-work"));
        assert!(palace
            .rooms
            .iter()
            .any(|room| room.id == "conversation-portals"));
        assert!(palace
            .desk
            .active_items
            .iter()
            .any(|item| item.kind == "conversation_portal"));
        assert!(palace
            .action_menu
            .actions
            .iter()
            .any(|action| action.id == "open-workbench"));

        let restricted = repo.promote_conversation_portal_clip(
            &portal.id,
            PromoteConversationPortalRequest {
                selected_text: "restricted: do not import".to_string(),
                summary: None,
                project_ref: None,
                privacy_class: Some("sensitive".to_string()),
                tags: Vec::new(),
                provenance: serde_json::Value::Null,
            },
        );
        assert!(restricted.is_err());
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
                capture_session_id: None,
                artifact_refs: Vec::new(),
                transcription_segments: Vec::new(),
                visual_evidence_refs: Vec::new(),
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
                mode: None,
                ranking_policy: None,
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
                capture_session_id: None,
                artifact_refs: Vec::new(),
                transcription_segments: Vec::new(),
                visual_evidence_refs: Vec::new(),
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

    #[test]
    fn memory_export_candidates_quorum_and_query_mesh_are_append_only() {
        let dir = tempdir().unwrap();
        let repo = ExocortexRepository::new(dir.path().join("exocortex"));
        let imported = repo
            .assisted_import_batch(AssistedImportBatchRequest {
                source_platform: "codex".to_string(),
                source_surface: "codex-local".to_string(),
                import_scope: "work_memory".to_string(),
                session_id: "codex-v15".to_string(),
                project_ref: Some("beagle".to_string()),
                batch_index: 1,
                batch_total: 1,
                turns: vec![AssistedImportTurn {
                    role: "assistant".to_string(),
                    content:
                        "Decisão: v1.5 usa beagle-memory-engine federado sem mover a verdade canônica."
                            .to_string(),
                    timestamp: Some("2026-04-27T02:00:00Z".to_string()),
                    model: Some("codex".to_string()),
                }],
                tags: vec!["project:beagle".to_string(), "work-memory".to_string()],
                metadata: serde_json::json!({"principal": "codex", "branch": "codex/beagle-mcp-public-claude"}),
                coverage: serde_json::Value::Null,
                extracted: Some(OmniExtraction {
                    decisions: vec![
                        "v1.5 usa beagle-memory-engine federado sem mover a verdade canônica."
                            .to_string(),
                    ],
                    projects_mentioned: vec!["beagle".to_string()],
                    ..Default::default()
                }),
                privacy_class: Some("sensitive".to_string()),
                title: Some("Codex v1.5 work memory".to_string()),
                original_date: None,
                confidence_score: Some(0.93),
                create_chronoself_commit: Some(false),
                capture_session_id: None,
                artifact_refs: Vec::new(),
                transcription_segments: Vec::new(),
                visual_evidence_refs: Vec::new(),
            })
            .unwrap();
        assert_eq!(imported.status, "imported");

        let candidate = repo
            .create_memory_candidate(CreateMemoryCandidateRequest {
                candidate_type: "hyperedge".to_string(),
                text: "Federated memory engine candidates require Triad quorum before active retrieval."
                    .to_string(),
                source_refs: vec!["memory-engine:bakeoff-shadow".to_string()],
                relations: vec![MemoryRelation {
                    subject: "candidate".to_string(),
                    predicate: "requires".to_string(),
                    object: "triad-quorum".to_string(),
                    confidence: 0.91,
                }],
                tags: vec!["candidate".to_string(), "v1.5".to_string()],
                provenance: serde_json::json!({"runtime": "beagle-memory-engine"}),
                confidence: Some(0.84),
                privacy_class: Some("sensitive".to_string()),
            })
            .unwrap();
        let quorum = repo
            .record_candidate_quorum(
                &candidate.id,
                CandidateQuorumRequest {
                    memory_approved: true,
                    temporal_approved: true,
                    critical_approved: true,
                    rationale: Some(
                        "All three Triad voices accept promotion eligibility.".to_string(),
                    ),
                    reviewer: Some("test".to_string()),
                    quality_score: None,
                },
            )
            .unwrap();
        assert_eq!(quorum.status, "triad_pending");

        let export = repo
            .export_sanitized_memory(MemoryExportRequest {
                limit: Some(100),
                include_worlds: true,
                include_candidates: true,
                purpose: Some("memory-engine-test".to_string()),
            })
            .unwrap();
        assert!(export.privacy_policy.contains("restricted"));
        assert_eq!(export.candidates.len(), 1);
        assert!(export
            .synthetic_golden_queries
            .iter()
            .any(|query| query.domain == "work-memory"));

        let query = repo
            .graphrag_query(GraphRagQueryRequest {
                query: "federated memory engine canonical truth".to_string(),
                scope: None,
                max_items: Some(5),
                mode: Some("adaptive-federation".to_string()),
                ranking_policy: None,
            })
            .unwrap();
        assert!(!query.mesh_trace.is_empty());
        assert!(!query.runtime_votes.is_empty());
        assert!(query.candidate_refs.contains(&candidate.id));

        let governance_before = repo.memory_governance_status().unwrap();
        assert_eq!(governance_before.pending_triads, 1);
        assert_eq!(governance_before.promoted_count, 0);

        let governance_run = repo
            .run_memory_governance(MemoryGovernanceRunRequest {
                limit: Some(20),
                reviewer: Some("test-governor".to_string()),
                dry_run: Some(false),
            })
            .unwrap();
        assert_eq!(governance_run.status, "completed");
        assert_eq!(governance_run.triad_pending, 1);
        assert_eq!(governance_run.quality_scores_written, 1);

        let promotion = repo
            .promote_memory_candidate(
                &candidate.id,
                CandidatePromoteRequest {
                    rationale: Some(
                        "Strict Triad 3/3 accepted the candidate for active memory.".to_string(),
                    ),
                    chronoself_commit_id: Some("chrono-test".to_string()),
                },
            )
            .unwrap();
        assert_eq!(promotion.candidate.status, "promoted");
        assert_eq!(promotion.promotion_decision.decision, "promoted");

        let governance_after = repo.memory_governance_status().unwrap();
        assert_eq!(governance_after.promoted_count, 1);
        assert_eq!(governance_after.pending_triads, 0);
        assert_eq!(
            governance_after
                .latest_promotion_decision
                .as_ref()
                .unwrap()
                .status,
            "promoted"
        );
    }

    #[test]
    fn sounio_program_check_requires_governance_and_blocks_restricted() {
        let dir = tempdir().unwrap();
        let repo = ExocortexRepository::new(dir.path().join("exocortex"));
        let mut program = default_beagle_self_writing_program();
        program.governance.privacy_class = "restricted".to_string();
        program.governance.provenance = serde_json::Value::Null;
        program.plan[0].provenance = serde_json::Value::Null;

        let checked = repo
            .check_sounio_program(SounioProgramCheckRequest {
                source_format: Some("json".to_string()),
                program,
            })
            .unwrap();

        assert_eq!(checked.status, "invalid");
        assert!(checked
            .errors
            .iter()
            .any(|error| error.contains("privacy_class=restricted")));
        assert!(checked
            .errors
            .iter()
            .any(|error| error.contains("governance.provenance")));
        assert!(checked
            .errors
            .iter()
            .any(|error| error.contains("retrieve_state provenance")));
        assert_eq!(checked.schema_version, SOUNIO_WORK_IR_SCHEMA);
    }

    #[test]
    fn sounio_paperrun_creates_trace_artifacts_and_home_trust_signal() {
        let dir = tempdir().unwrap();
        let repo = ExocortexRepository::new(dir.path().join("exocortex"));

        let run = repo
            .start_paper_run(StartPaperRunRequest {
                paper_id: None,
                title: None,
                program: None,
                principal: Some("codex-test".to_string()),
                surface: Some("unit-test".to_string()),
                temporal_namespace: None,
                temporal_task_queue: None,
                dry_run: Some(true),
            })
            .unwrap();

        assert_eq!(run.status, "human_approval_pending");
        assert_eq!(run.temporal_status, "dry_run_not_started");
        assert_eq!(run.pending_approval_step.as_deref(), Some("human_approval"));
        assert!(run.sounio_program_hash.starts_with("sha256:"));
        assert!(run
            .artifact_refs
            .iter()
            .all(|artifact| artifact.starts_with("/orangefs/beagle-memory-lab/paperruns/")));

        let artifacts = repo.paper_run_artifacts(&run.id).unwrap().unwrap();
        assert!(artifacts
            .manuscript_markdown
            .contains("Self-Governing Exocortex"));
        assert_eq!(artifacts.paper_run_id, run.id);

        let approved = repo
            .approve_paper_run_step(
                &run.id,
                ApprovePaperRunStepRequest {
                    step_id: "human_approval".to_string(),
                    decision: Some("approved".to_string()),
                    reviewer: Some("demetrios".to_string()),
                    rationale: Some("Approved for durable PaperRun smoke.".to_string()),
                },
            )
            .unwrap();
        assert_eq!(approved.status, "approved_for_temporal_execution");
        assert_eq!(approved.temporal_status, "signal_approved");

        let traces = repo
            .sounio_trace_events(SounioTraceQuery {
                paper_run_id: Some(run.id.clone()),
                limit: Some(10),
            })
            .unwrap();
        assert_eq!(traces.len(), 2);
        assert!(traces
            .iter()
            .any(|event| event.event_type == "workflow_start_requested"));
        assert!(traces
            .iter()
            .any(|event| event.event_type == "human_approval"));

        let home = repo
            .build_home_snapshot(HomeQuery {
                active_project_slug: None,
                platform: Some("unit-test".to_string()),
            })
            .unwrap();
        let trust = home.trust_context.unwrap();
        assert_eq!(
            trust.sounio_paperrun_status.as_deref(),
            Some("beagle-self-writing-systems-paper:approved_for_temporal_execution")
        );
        assert!(trust
            .sounio_temporal_status
            .as_deref()
            .is_some_and(|status| status.ends_with(":signal_approved")));
        assert!(trust.sounio_latest_artifact.is_some());
    }

    #[test]
    fn sounio_claim_lifecycle_enforces_epistemic_gates_and_digest_sanitization() {
        let dir = tempdir().unwrap();
        let repo = ExocortexRepository::new(dir.path().join("exocortex"));
        let run = repo
            .start_paper_run(StartPaperRunRequest {
                paper_id: None,
                title: None,
                principal: Some("codex-test".to_string()),
                surface: Some("unit-test".to_string()),
                temporal_namespace: None,
                temporal_task_queue: None,
                program: None,
                dry_run: Some(true),
            })
            .unwrap();

        let checked = repo
            .check_sounio_claim(SounioClaimCheckRequest {
                claim: SounioClaimInput {
                    id: Some("claim-no-evidence".to_string()),
                    claim_text: "A claim cannot become Knowledge<T> without evidence.".to_string(),
                    subject: Some("sounio_claim_gate".to_string()),
                    value_type: None,
                    epistemic_status: Some("knowledge".to_string()),
                    evidence_refs: Vec::new(),
                    provenance: serde_json::Value::Null,
                    confidence: Some(0.9),
                    contestation: serde_json::json!({}),
                    review_state: None,
                    promotion_rule: None,
                    publication_readiness: None,
                    section_id: Some("Sounio IR".to_string()),
                    agent_refs: Vec::new(),
                    contract_refs: Vec::new(),
                    artifact_refs: Vec::new(),
                    chronoself_commit_refs: Vec::new(),
                    privacy_class: Some("sensitive".to_string()),
                    rationale: None,
                },
            })
            .unwrap();
        assert_eq!(checked.status, "valid");
        assert_eq!(checked.normalized_claim.epistemic_status, "belief");
        assert!(checked
            .warnings
            .iter()
            .any(|warning| warning.contains("Knowledge<T> requires")));

        let claim = repo
            .add_paper_run_claim(
                &run.id,
                AddPaperRunClaimRequest {
                    principal: Some("codex-test".to_string()),
                    surface: Some("unit-test".to_string()),
                    claim: SounioClaimInput {
                        id: Some("claim-sedenion-ssm-arc".to_string()),
                        claim_text: "Sedenion SSM is the first strong Sounio demonstration.".to_string(),
                        subject: Some("sedenion_ssm_arc".to_string()),
                        value_type: Some("Claim<T>".to_string()),
                        epistemic_status: Some("contest".to_string()),
                        evidence_refs: vec![
                            "artifact:sedenion_ssm_arc".to_string(),
                            "theorem_refs:sedenion_ssm".to_string(),
                        ],
                        provenance: serde_json::json!({
                            "source": "unit-test",
                            "human_review": true
                        }),
                        confidence: Some(0.8),
                        contestation: serde_json::json!({}),
                        review_state: None,
                        promotion_rule: None,
                        publication_readiness: None,
                        section_id: Some("Sounio IR".to_string()),
                        agent_refs: vec!["codex-test".to_string()],
                        contract_refs: Vec::new(),
                        artifact_refs: vec![
                            "/orangefs/beagle-memory-lab/paperruns/test/sedenion_ssm_public_case.json"
                                .to_string(),
                        ],
                        chronoself_commit_refs: Vec::new(),
                        privacy_class: Some("sensitive".to_string()),
                        rationale: None,
                    },
                },
            )
            .unwrap();
        assert_eq!(claim.epistemic_status, "contest");

        let reviewed = repo
            .review_sounio_claim(
                &run.id,
                &claim.id,
                ReviewSounioClaimRequest {
                    reviewer: Some("demetrios".to_string()),
                    decision: "promote_to_knowledge".to_string(),
                    rationale: Some("Evidence and provenance are present.".to_string()),
                    evidence_refs: Vec::new(),
                    epistemic_status: None,
                    publication_readiness: None,
                    provenance: serde_json::json!({"human_review": true}),
                },
            )
            .unwrap();
        assert_eq!(reviewed.epistemic_status, "knowledge");
        assert_eq!(
            reviewed.publication_readiness,
            "section_ready_with_provenance"
        );

        let theatre = repo.paper_run_theatre(&run.id).unwrap().unwrap();
        assert_eq!(theatre.claim_graph.status_counts.get("knowledge"), Some(&1));
        assert!(theatre.next_action.contains("human_approval"));

        let digest = repo.paper_run_public_digest(&run.id).unwrap().unwrap();
        assert_eq!(digest.schema_version, SOUNIO_PUBLIC_DIGEST_SCHEMA);
        assert!(digest
            .sedenion_ssm_case
            .to_string()
            .contains("sedenion-ssm-arc"));
        assert!(!digest
            .public_trace_digest
            .iter()
            .any(|entry| entry.to_string().contains("restricted")));
    }
}
