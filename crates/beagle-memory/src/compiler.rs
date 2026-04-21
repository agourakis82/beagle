use crate::budgeting::ContextBudgetProfile;
use crate::retrieval::RetrievalFilters;
use serde::{Deserialize, Serialize};

pub const MEMORY_COMPILER_VERSION: &str = "beagle-memory-compiler-v1";
pub const COMPILED_CONTEXT_PACKET_VERSION: &str = "beagle-compiled-context-packet-v1";
pub const CONTEXT_EVAL_CASE_VERSION: &str = "beagle-context-eval-case-v1";
pub const COMPILER_EVAL_REPORT_VERSION: &str = "beagle-compiler-eval-report-v1";
pub const COMPILER_POLICY_VERSION: &str = "beagle-compiler-policy-v1";

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
pub struct MemoryCompilerContract {
    pub compiler_version: String,
    pub compiler_id: String,
    pub supported_task_profiles: Vec<String>,
    pub supported_memory_tiers: Vec<String>,
    pub supported_graphrag_modes: Vec<String>,
    pub supported_temporal_truth_views: Vec<String>,
    pub supported_source_kinds: Vec<String>,
    pub note: String,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct CompiledContextRequest {
    pub task_profile: String,
    #[serde(default)]
    pub tool_id: Option<String>,
    #[serde(default)]
    pub query_text: String,
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
    pub root_entity_type: Option<String>,
    #[serde(default)]
    pub root_entity_id: Option<String>,
    #[serde(default)]
    pub repo_path: Option<String>,
    #[serde(default)]
    pub file_type: Option<String>,
    #[serde(default)]
    pub tags: Vec<String>,
    #[serde(default)]
    pub rerank_hint: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct CompiledContextSourceSlice {
    pub source_kind: String,
    pub budgeted_items: usize,
    pub selected_count: usize,
    pub support_ids: Vec<String>,
    pub summary: String,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct CompiledContextPacket {
    pub packet_version: String,
    pub compiler_id: String,
    pub task_profile: String,
    #[serde(default)]
    pub tool_id: Option<String>,
    pub budget_profile: ContextBudgetProfile,
    pub retrieval_query_type: String,
    pub dense_backend: String,
    pub sparse_backend: String,
    pub graphrag_query_mode: String,
    pub graphrag_query_mode_reason: String,
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
    pub applied_filters: RetrievalFilters,
    pub selected_memory_tiers: Vec<String>,
    pub temporal_truth_view: String,
    #[serde(default)]
    pub temporal_subject_refs: Vec<String>,
    #[serde(default)]
    pub temporal_current_memory_ids: Vec<String>,
    #[serde(default)]
    pub temporal_historical_memory_ids: Vec<String>,
    pub temporal_track_count: usize,
    pub temporal_contradiction_count: usize,
    pub temporal_preview: String,
    pub top_memory_ids: Vec<String>,
    pub source_slices: Vec<CompiledContextSourceSlice>,
    pub compiled_context_text: String,
    pub note: String,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct ContextEvalCase {
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

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct CompilerEvalRequest {
    pub report_version: String,
    pub cases: Vec<ContextEvalCase>,
    #[serde(default)]
    pub top_k_stability_runs: usize,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct CompilerPolicyVariantReport {
    pub variant_id: String,
    pub budget_profile_id: String,
    pub task_profile: String,
    pub retrieval_query_type: String,
    pub dense_backend: String,
    pub sparse_backend: String,
    pub graphrag_query_mode: String,
    pub temporal_truth_view: String,
    pub selected_memory_tiers: Vec<String>,
    pub top_memory_ids: Vec<String>,
    pub relevance_proxy_score: f32,
    pub task_fit_score: f32,
    pub context_usefulness_score: f32,
    pub budget_efficiency_score: f32,
    pub top_k_stable: bool,
    pub truth_view_appropriate: bool,
    pub graphrag_mode_appropriate: bool,
    pub route_appropriate: bool,
    pub overall_score: f32,
    pub latency_ms: u64,
    pub note: String,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct CompilerTaskComparison {
    pub case_id: String,
    pub task_profile: String,
    #[serde(default)]
    pub description: Option<String>,
    pub selected_variant_id: String,
    pub selected_budget_profile_id: String,
    pub recommendation: String,
    pub variants: Vec<CompilerPolicyVariantReport>,
    pub note: String,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct CompilerEvalReport {
    pub report_version: String,
    pub compiler_id: String,
    pub generated_at: String,
    pub comparisons: Vec<CompilerTaskComparison>,
    pub note: String,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct CompilerPolicyProfile {
    pub task_profile: String,
    pub budget_profile_id: String,
    pub retrieval_query_type: String,
    pub graphrag_query_mode: String,
    pub temporal_truth_view: String,
    pub selected_memory_tiers: Vec<String>,
    pub current_state: String,
    pub evidence_basis: Vec<String>,
    pub last_eval_at: String,
    pub recommended_when: String,
    pub note: String,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct CompilerPolicy {
    pub policy_version: String,
    pub policy_id: String,
    pub generated_at: String,
    pub profiles: Vec<CompilerPolicyProfile>,
    pub note: String,
}

pub fn memory_compiler_contract() -> MemoryCompilerContract {
    MemoryCompilerContract {
        compiler_version: MEMORY_COMPILER_VERSION.to_string(),
        compiler_id: "b235-query-adaptive-memory-compiler".to_string(),
        supported_task_profiles: vec![
            "implementation".to_string(),
            "analysis".to_string(),
            "interactive-editing".to_string(),
            "manuscript".to_string(),
        ],
        supported_memory_tiers: vec![
            "episodic".to_string(),
            "semantic".to_string(),
            "procedural".to_string(),
        ],
        supported_graphrag_modes: vec![
            "local".to_string(),
            "global".to_string(),
            "drift".to_string(),
        ],
        supported_temporal_truth_views: vec![
            "current".to_string(),
            "historical".to_string(),
            "both".to_string(),
        ],
        supported_source_kinds: vec![
            "procedural".to_string(),
            "semantic".to_string(),
            "episodic".to_string(),
            "temporal".to_string(),
            "graphrag".to_string(),
        ],
        note: "B23.5 compiles bounded, task-aware context slices from the existing retrieval, GraphRAG, temporal memory, and memory hierarchy layers instead of creating a parallel memory runtime.".to_string(),
    }
}
