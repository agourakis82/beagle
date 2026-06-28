//! Data-transfer objects for the exocortex HTTP surface.
//! Extracted verbatim from mod.rs (god-file split, plan #16) — 142 pure DTOs, zero logic.
//! Re-exported pub(crate) so handlers and external consumers keep referencing them unqualified.

use super::*;
use serde::{Deserialize, Serialize};
use std::collections::{BTreeMap, BTreeSet};

/// A hyperedge as the iOS cockpit's `Hyperedge` model expects it. Surfaced from
/// the REAL knowledge graph: every distinct `MemoryRelation` (subject→object) plus
/// any user-created edges in `HYPEREDGES_LOG`. Serializes to the exact client keys
/// (`id`/`label`/`node_ids`/`metadata`/`directed`/`created_at`).
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct HyperedgeRecord {
    pub id: String,
    pub label: String,
    pub node_ids: Vec<String>,
    #[serde(default)]
    pub metadata: BTreeMap<String, String>,
    #[serde(default)]
    pub directed: bool,
    pub created_at: String,
}

/// POST /api/hyperedges body (BeagleClient `createHyperedge`).
#[derive(Debug, Clone, Deserialize)]
pub struct CreateHyperedgeRequest {
    pub label: String,
    #[serde(default)]
    pub node_ids: Vec<String>,
    #[serde(default)]
    pub directed: bool,
    #[serde(default)]
    pub metadata: BTreeMap<String, String>,
}

/// GET /api/hyperedges optional `?node_id=` incidence filter.
#[derive(Debug, Clone, Deserialize)]
pub struct HyperedgeListQuery {
    #[serde(default)]
    pub node_id: Option<String>,
}

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

/// A single turn inside a durable conversation passage record.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ConversationPassageTurn {
    pub role: String,
    pub content: String,
}

/// Append-only durable record of an ingested conversation, preserving the raw
/// turn text so downstream workers can chunk it into semantic passages.
/// Shared contract shape across the assisted-import and /api/memory paths and
/// the Python projection worker.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ConversationPassageRecord {
    pub id: String,
    #[serde(default)]
    pub session_id: Option<String>,
    pub source_platform: String,
    pub occurred_at: String,
    pub privacy_class: String,
    pub turns: Vec<ConversationPassageTurn>,
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
    #[serde(default)]
    pub passages: Vec<ConversationPassageRecord>,
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
