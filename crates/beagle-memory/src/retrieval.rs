use crate::engine::MemoryRecord;
use serde::{Deserialize, Serialize};

pub const RETRIEVAL_COLLECTION_VERSION: &str = "beagle-retrieval-collection-v1";
pub const MEMORY_POINT_VERSION: &str = "beagle-memory-point-v1";
pub const RETRIEVAL_QUERY_VERSION: &str = "beagle-retrieval-query-v1";
pub const RETRIEVAL_RESULT_VERSION: &str = "beagle-retrieval-result-v1";
pub const RETRIEVAL_BENCHMARK_VERSION: &str = "beagle-retrieval-benchmark-v1";
pub const EMBEDDING_BACKEND_MATRIX_VERSION: &str = "beagle-embedding-backend-matrix-v1";
pub const EMBEDDING_BACKEND_CONTRACT_VERSION: &str = "beagle-embedding-backend-contract-v1";
pub const RERANKING_PROFILE_VERSION: &str = "beagle-reranking-profile-v1";
pub const RERANKED_RESULT_VERSION: &str = "beagle-reranked-result-v1";
pub const RELEVANCE_FEEDBACK_VERSION: &str = "beagle-relevance-feedback-v1";
pub const RETRIEVAL_EVAL_REPORT_VERSION: &str = "beagle-retrieval-eval-report-v1";
pub const RETRIEVAL_POLICY_VERSION: &str = "beagle-retrieval-policy-v1";
pub const MEMORY_HIERARCHY_VERSION: &str = "beagle-memory-hierarchy-v1";
pub const GRAPHRAG_NODE_VERSION: &str = "beagle-graphrag-node-v1";
pub const GRAPHRAG_EDGE_VERSION: &str = "beagle-graphrag-edge-v1";
pub const GRAPHRAG_QUERY_VERSION: &str = "beagle-graphrag-query-v1";
pub const GRAPHRAG_RESULT_VERSION: &str = "beagle-graphrag-result-v1";
pub const CODE_RETRIEVAL_QUERY_VERSION: &str = "beagle-code-retrieval-query-v1";
pub const CODE_RETRIEVAL_RESULT_VERSION: &str = "beagle-code-retrieval-result-v1";
pub const SOVEREIGN_RETRIEVAL_QUERY_VERSION: &str = "beagle-sovereign-retrieval-query-v1";
pub const SOVEREIGN_RETRIEVAL_RESULT_VERSION: &str = "beagle-sovereign-retrieval-result-v1";
pub const RETRIEVAL_ROUTER_VERSION: &str = "beagle-retrieval-router-v1";
pub const QUERY_TYPE_VERSION: &str = "beagle-query-type-v1";
pub const ROUTED_RETRIEVAL_QUERY_VERSION: &str = "beagle-routed-retrieval-query-v1";
pub const RETRIEVAL_ROUTING_DECISION_VERSION: &str =
    "beagle-retrieval-routing-decision-v1";
pub const ROUTED_RETRIEVAL_RESULT_VERSION: &str = "beagle-routed-retrieval-result-v1";

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
pub struct RetrievalCollectionField {
    pub name: String,
    pub field_type: String,
    pub filterable: bool,
    pub indexed_hint: bool,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
pub struct RetrievalCollection {
    pub collection_version: String,
    pub collection_kind: String,
    pub collection_name: String,
    pub dense_backend: String,
    pub sparse_backend: String,
    pub dense_vector_name: Option<String>,
    pub supports_named_vectors: bool,
    pub supports_payload_filters: bool,
    pub supports_hybrid_query: bool,
    pub payload_fields: Vec<RetrievalCollectionField>,
    pub filter_fields: Vec<String>,
    pub note: String,
}

#[derive(Debug, Clone, Default, Serialize, Deserialize, PartialEq, Eq)]
pub struct RetrievalFilters {
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

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct RetrievalQuery {
    pub query_version: String,
    pub query_text: String,
    pub top_k: usize,
    pub dense_enabled: bool,
    pub sparse_enabled: bool,
    pub dense_weight: f32,
    pub sparse_weight: f32,
    pub filters: RetrievalFilters,
    #[serde(default)]
    pub rerank_hint: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct MemoryPoint {
    pub point_version: String,
    pub point_id: String,
    pub collection_name: String,
    #[serde(default)]
    pub dense_vector_name: Option<String>,
    pub payload: MemoryRecord,
    pub note: String,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct RetrievalHit {
    pub rank: usize,
    pub point: MemoryPoint,
    #[serde(default)]
    pub dense_score: Option<f32>,
    #[serde(default)]
    pub sparse_score: Option<f32>,
    pub hybrid_score: f32,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct RetrievalResult {
    pub result_version: String,
    pub retrieval_mode: String,
    pub collection_name: String,
    pub dense_backend: String,
    pub sparse_backend: String,
    pub top_k: usize,
    pub applied_filters: RetrievalFilters,
    pub dense_hit_count: usize,
    pub sparse_hit_count: usize,
    pub hits: Vec<RetrievalHit>,
    pub note: String,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
pub struct CodeRetrievalBackendProfile {
    pub profile_version: String,
    pub backend_id: String,
    pub provider: String,
    pub model: String,
    pub runtime_state: String,
    pub store_direction: String,
    pub note: String,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct CodeRetrievalQuery {
    pub query_version: String,
    pub query_text: String,
    pub top_k: usize,
    pub dense_enabled: bool,
    pub sparse_enabled: bool,
    pub dense_weight: f32,
    pub sparse_weight: f32,
    pub filters: RetrievalFilters,
    #[serde(default)]
    pub compare_against_general: bool,
    #[serde(default)]
    pub rerank_hint: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct CodeRetrievalComparison {
    pub general_dense_backend: String,
    pub code_dense_backend: String,
    pub general_top_memory_ids: Vec<String>,
    pub code_top_memory_ids: Vec<String>,
    pub overlap_memory_ids: Vec<String>,
    pub top_hit_changed: bool,
    pub note: String,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct CodeRetrievalResult {
    pub result_version: String,
    pub retrieval_mode: String,
    pub collection_name: String,
    pub code_dense_backend: String,
    pub general_dense_backend: String,
    pub sparse_backend: String,
    pub top_k: usize,
    pub applied_filters: RetrievalFilters,
    pub dense_hit_count: usize,
    pub sparse_hit_count: usize,
    pub hits: Vec<RetrievalHit>,
    pub backend_profile: CodeRetrievalBackendProfile,
    #[serde(default)]
    pub comparison: Option<CodeRetrievalComparison>,
    pub note: String,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
pub struct SovereignRetrievalBackendProfile {
    pub profile_version: String,
    pub backend_id: String,
    pub provider: String,
    pub model: String,
    pub runtime_state: String,
    pub endpoint_ref: Option<String>,
    pub store_direction: String,
    pub note: String,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct SovereignRetrievalQuery {
    pub query_version: String,
    pub query_text: String,
    pub top_k: usize,
    pub dense_enabled: bool,
    pub sparse_enabled: bool,
    pub dense_weight: f32,
    pub sparse_weight: f32,
    pub filters: RetrievalFilters,
    #[serde(default)]
    pub compare_against_general: bool,
    #[serde(default)]
    pub rerank_hint: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct SovereignRetrievalComparison {
    pub general_dense_backend: String,
    pub sovereign_dense_backend: String,
    pub general_top_memory_ids: Vec<String>,
    pub sovereign_top_memory_ids: Vec<String>,
    pub overlap_memory_ids: Vec<String>,
    pub top_hit_changed: bool,
    pub note: String,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct SovereignRetrievalResult {
    pub result_version: String,
    pub retrieval_mode: String,
    pub collection_name: String,
    pub sovereign_dense_backend: String,
    pub general_dense_backend: String,
    pub sparse_backend: String,
    pub top_k: usize,
    pub applied_filters: RetrievalFilters,
    pub dense_hit_count: usize,
    pub sparse_hit_count: usize,
    pub hits: Vec<RetrievalHit>,
    pub backend_profile: SovereignRetrievalBackendProfile,
    #[serde(default)]
    pub comparison: Option<SovereignRetrievalComparison>,
    pub note: String,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
pub struct RetrievalQueryType {
    pub query_type_version: String,
    pub router_version: String,
    pub query_text: String,
    #[serde(default)]
    pub requested_hint: Option<String>,
    pub selected_query_type: String,
    pub classifier_source: String,
    pub classifier_reason: String,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
pub struct RetrievalRoutingDecision {
    pub decision_version: String,
    pub router_version: String,
    pub query_type: String,
    pub selected_route: String,
    pub selected_dense_backend: String,
    pub sparse_backend: String,
    pub payload_filters_present: bool,
    pub compare_against_general: bool,
    pub routing_source: String,
    pub routing_reason: String,
    pub note: String,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct RoutedRetrievalQuery {
    pub query_version: String,
    pub query_text: String,
    pub top_k: usize,
    pub dense_enabled: bool,
    pub sparse_enabled: bool,
    pub dense_weight: f32,
    pub sparse_weight: f32,
    pub filters: RetrievalFilters,
    #[serde(default)]
    pub query_type_hint: Option<String>,
    #[serde(default)]
    pub compare_against_general: bool,
    #[serde(default)]
    pub rerank_hint: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct RoutedRetrievalResult {
    pub result_version: String,
    pub retrieval_mode: String,
    pub collection_name: String,
    pub query_type: String,
    pub routing_decision: RetrievalRoutingDecision,
    pub dense_backend: String,
    pub sparse_backend: String,
    pub top_k: usize,
    pub applied_filters: RetrievalFilters,
    pub dense_hit_count: usize,
    pub sparse_hit_count: usize,
    pub hits: Vec<RetrievalHit>,
    #[serde(default)]
    pub comparison_general_dense_backend: Option<String>,
    #[serde(default)]
    pub comparison_changed_top_hit: Option<bool>,
    pub note: String,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
pub struct EmbeddingBackendCandidate {
    pub backend_id: String,
    pub backend_kind: String,
    pub provider: String,
    pub model_family: String,
    pub serving_mode: String,
    pub self_hosted: bool,
    pub multilingual_ready: bool,
    pub code_retrieval_ready: bool,
    pub sovereign_fit: String,
    pub qdrant_fit: String,
    pub recommended_scope: String,
    pub note: String,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
pub struct EmbeddingBackendContract {
    pub contract_version: String,
    pub promoted_dense_backend: String,
    pub promoted_provider: String,
    pub promoted_model: String,
    pub active_dense_backend: String,
    pub runtime_state: String,
    pub authentication_mode: String,
    #[serde(default)]
    pub endpoint_ref: Option<String>,
    pub store_direction: String,
    pub sparse_backend: String,
    pub code_candidate_backend: String,
    pub sovereign_candidate_backend: String,
    pub note: String,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
pub struct EmbeddingBackendMatrix {
    pub matrix_version: String,
    pub current_dense_backend: String,
    pub current_sparse_backend: String,
    pub current_store: String,
    pub backends: Vec<EmbeddingBackendCandidate>,
    pub note: String,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
pub struct RerankingCandidate {
    pub candidate_id: String,
    pub provider: String,
    pub model: String,
    pub candidate_kind: String,
    pub route_scope: String,
    pub serving_mode: String,
    pub runtime_state: String,
    pub self_hosted: bool,
    pub multilingual_ready: bool,
    pub code_retrieval_ready: bool,
    pub latency_class: String,
    #[serde(default)]
    pub endpoint_ref: Option<String>,
    pub recommended_scope: String,
    pub note: String,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
pub struct RerankingProfile {
    pub profile_version: String,
    pub profile_id: String,
    pub current_state: String,
    pub current_mode: String,
    pub bounded_top_k: usize,
    pub general_candidate_id: String,
    pub sovereign_candidate_id: String,
    pub candidates: Vec<RerankingCandidate>,
    pub note: String,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct RerankingLatencyComparison {
    pub prerank_latency_ms: u64,
    pub rerank_latency_ms: u64,
    pub total_latency_ms: u64,
    pub latency_delta_ms: u64,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct RerankingRecommendation {
    pub query_type: String,
    pub reranker_backend: String,
    pub runtime_state: String,
    pub reranking_applied: bool,
    pub top_hit_changed: bool,
    pub relevance_proxy_before: f32,
    pub relevance_proxy_after: f32,
    pub latency_delta_ms: u64,
    pub recommendation: String,
    pub note: String,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct RerankedHit {
    pub rank: usize,
    pub prerank_rank: usize,
    pub point: MemoryPoint,
    #[serde(default)]
    pub dense_score: Option<f32>,
    #[serde(default)]
    pub sparse_score: Option<f32>,
    pub hybrid_score: f32,
    pub rerank_score: f32,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct RerankedResult {
    pub result_version: String,
    pub profile_id: String,
    pub query_type: String,
    pub routing_decision: RetrievalRoutingDecision,
    pub collection_name: String,
    pub prerank_retrieval_mode: String,
    pub postrank_retrieval_mode: String,
    pub dense_backend: String,
    pub sparse_backend: String,
    pub reranker_backend: String,
    pub reranker_kind: String,
    pub reranker_runtime_state: String,
    pub reranking_applied: bool,
    pub top_k: usize,
    pub candidate_count: usize,
    pub applied_filters: RetrievalFilters,
    pub prerank_hit_count: usize,
    pub postrank_hit_count: usize,
    pub prerank_top_memory_ids: Vec<String>,
    pub postrank_top_memory_ids: Vec<String>,
    pub relevance_proxy_before: f32,
    pub relevance_proxy_after: f32,
    pub latency: RerankingLatencyComparison,
    pub hits: Vec<RerankedHit>,
    pub recommendation: RerankingRecommendation,
    pub note: String,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct RetrievalBenchmarkCase {
    pub case_id: String,
    pub case_kind: String,
    #[serde(default)]
    pub description: Option<String>,
    pub query: RetrievalQuery,
    #[serde(default)]
    pub expected_memory_ids: Vec<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct RetrievalBenchmarkRequest {
    pub benchmark_version: String,
    pub cases: Vec<RetrievalBenchmarkCase>,
    #[serde(default)]
    pub top_k_stability_runs: usize,
    #[serde(default)]
    pub reranking_profile_id: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct RetrievalBenchmarkCaseReport {
    pub case_id: String,
    pub case_kind: String,
    #[serde(default)]
    pub description: Option<String>,
    pub retrieval_mode: String,
    pub latency_ms: u64,
    pub hit_count: usize,
    pub dense_hit_count: usize,
    pub sparse_hit_count: usize,
    pub payload_filter_correctness: f32,
    pub relevance_proxy_score: f32,
    pub top_k_stable: bool,
    pub context_packet_usable_hit_count: usize,
    #[serde(default)]
    pub top_hit_memory_id: Option<String>,
    #[serde(default)]
    pub top_hit_source: Option<String>,
    #[serde(default)]
    pub top_hit_workstream_id: Option<String>,
    #[serde(default)]
    pub top_hit_tags: Vec<String>,
    #[serde(default)]
    pub note: String,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct RetrievalRecommendation {
    pub keep_qdrant: bool,
    pub dense_backend_recommendation: String,
    pub reranking_recommendation: String,
    pub general_retrieval_path: String,
    pub code_retrieval_path: String,
    pub multilingual_retrieval_path: String,
    pub sovereign_retrieval_path: String,
    pub bounded_upgrade_path: Vec<String>,
    pub note: String,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct RetrievalBenchmarkSummary {
    pub benchmark_version: String,
    pub collection_name: String,
    pub dense_backend: String,
    pub sparse_backend: String,
    pub reranking_profile_id: String,
    pub case_count: usize,
    pub average_latency_ms: f32,
    pub average_filter_correctness: f32,
    pub average_relevance_proxy: f32,
    pub top_k_stability_pass_rate: f32,
    pub context_packet_usable_case_count: usize,
    pub note: String,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct RetrievalBenchmarkReport {
    pub benchmark_version: String,
    pub collection_name: String,
    pub dense_backend: String,
    pub sparse_backend: String,
    pub reranking_profile_id: String,
    pub cases: Vec<RetrievalBenchmarkCaseReport>,
    pub summary: RetrievalBenchmarkSummary,
    pub recommendation: RetrievalRecommendation,
    pub note: String,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct RetrievalEvalCase {
    pub case_id: String,
    pub query_type: String,
    #[serde(default)]
    pub description: Option<String>,
    pub query: RoutedRetrievalQuery,
    #[serde(default)]
    pub expected_memory_ids: Vec<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct RetrievalEvalRequest {
    pub report_version: String,
    pub cases: Vec<RetrievalEvalCase>,
    #[serde(default)]
    pub top_k_stability_runs: usize,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct RetrievalEvalCaseReport {
    pub case_id: String,
    pub query_type: String,
    #[serde(default)]
    pub description: Option<String>,
    pub selected_route: String,
    pub dense_backend: String,
    pub sparse_backend: String,
    pub reranker_backend: String,
    pub reranking_applied: bool,
    pub latency_ms: u64,
    pub relevance_proxy_score: f32,
    pub payload_filter_correctness: f32,
    pub top_k_stable: bool,
    pub route_appropriate: bool,
    pub context_packet_usable_hit_count: usize,
    #[serde(default)]
    pub top_hit_memory_id: Option<String>,
    #[serde(default)]
    pub expected_memory_ids: Vec<String>,
    pub note: String,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct RetrievalEvalLaneSummary {
    pub query_type: String,
    pub selected_route: String,
    pub dense_backend: String,
    pub sparse_backend: String,
    pub reranker_backend: String,
    pub case_count: usize,
    pub average_latency_ms: f32,
    pub average_relevance_proxy: f32,
    pub average_filter_correctness: f32,
    pub top_k_stability_pass_rate: f32,
    pub route_appropriateness_rate: f32,
    pub average_context_packet_usable_hits: f32,
    pub recommended_when: String,
    pub note: String,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct RetrievalEvalReport {
    pub report_version: String,
    pub collection_name: String,
    pub sparse_backend: String,
    pub reranking_profile_id: String,
    pub generated_at: String,
    pub cases: Vec<RetrievalEvalCaseReport>,
    pub lanes: Vec<RetrievalEvalLaneSummary>,
    pub note: String,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct RelevanceFeedbackJudgment {
    pub memory_id: String,
    pub signal: String,
    pub score: f32,
    #[serde(default)]
    pub rationale: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct RelevanceFeedbackInput {
    pub feedback_version: String,
    pub query: RoutedRetrievalQuery,
    pub feedback_round: usize,
    #[serde(default)]
    pub expected_memory_ids: Vec<String>,
    pub judgments: Vec<RelevanceFeedbackJudgment>,
    #[serde(default)]
    pub note: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct FeedbackLatencyComparison {
    pub prerank_latency_ms: u64,
    pub feedback_adjustment_latency_ms: u64,
    pub total_latency_ms: u64,
    pub latency_delta_ms: u64,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct FeedbackAdjustedHit {
    pub rank: usize,
    pub prerank_rank: usize,
    pub point: MemoryPoint,
    #[serde(default)]
    pub dense_score: Option<f32>,
    #[serde(default)]
    pub sparse_score: Option<f32>,
    pub hybrid_score: f32,
    pub rerank_score: f32,
    pub feedback_score: f32,
    pub adjusted_score: f32,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct FeedbackLoopResult {
    pub result_version: String,
    pub profile_id: String,
    pub feedback_version: String,
    pub query_type: String,
    pub routing_decision: RetrievalRoutingDecision,
    pub collection_name: String,
    pub dense_backend: String,
    pub sparse_backend: String,
    pub reranker_backend: String,
    pub reranking_applied: bool,
    pub feedback_strategy: String,
    pub feedback_applied: bool,
    pub feedback_round: usize,
    pub top_k: usize,
    pub candidate_count: usize,
    pub applied_filters: RetrievalFilters,
    pub prerank_hit_count: usize,
    pub postfeedback_hit_count: usize,
    pub prerank_top_memory_ids: Vec<String>,
    pub postfeedback_top_memory_ids: Vec<String>,
    pub relevance_proxy_before: f32,
    pub relevance_proxy_after: f32,
    pub top_hit_changed: bool,
    pub improvement_observed: bool,
    pub latency: FeedbackLatencyComparison,
    pub hits: Vec<FeedbackAdjustedHit>,
    pub note: String,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct RetrievalPolicyLane {
    pub query_type: String,
    pub selected_route: String,
    pub dense_backend: String,
    pub sparse_backend: String,
    pub reranker_backend: String,
    pub feedback_mode: String,
    pub current_state: String,
    pub evidence_basis: Vec<String>,
    pub last_eval_at: String,
    pub recommended_when: String,
    pub note: String,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct RetrievalPolicy {
    pub policy_version: String,
    pub policy_id: String,
    pub generated_at: String,
    pub lanes: Vec<RetrievalPolicyLane>,
    pub note: String,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct MemoryHierarchyBucket {
    pub memory_type: String,
    pub description: String,
    pub store_when: Vec<String>,
    pub count: usize,
    pub memory_ids: Vec<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct MemoryHierarchy {
    pub hierarchy_version: String,
    pub policy_id: String,
    pub collection_name: String,
    pub buckets: Vec<MemoryHierarchyBucket>,
    pub note: String,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct GraphRagQuery {
    pub query_version: String,
    pub query_text: String,
    pub top_k: usize,
    pub max_hops: usize,
    pub dense_enabled: bool,
    pub sparse_enabled: bool,
    pub dense_weight: f32,
    pub sparse_weight: f32,
    pub filters: RetrievalFilters,
    #[serde(default)]
    pub root_entity_type: Option<String>,
    #[serde(default)]
    pub root_entity_id: Option<String>,
    #[serde(default)]
    pub program_id: Option<String>,
    #[serde(default)]
    pub include_memory_hierarchy: bool,
    #[serde(default)]
    pub query_type_hint: Option<String>,
    #[serde(default)]
    pub query_mode_hint: Option<String>,
    #[serde(default)]
    pub rerank_hint: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct GraphRagNode {
    pub node_version: String,
    pub node_id: String,
    pub node_type: String,
    pub display_name: String,
    pub support_memory_ids: Vec<String>,
    pub properties: serde_json::Value,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct GraphRagEdge {
    pub edge_version: String,
    pub edge_id: String,
    pub from_node_id: String,
    pub to_node_id: String,
    pub edge_type: String,
    pub support_memory_ids: Vec<String>,
    pub properties: serde_json::Value,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct GraphRagResult {
    pub result_version: String,
    pub query_type: String,
    pub query_mode: String,
    pub query_mode_source: String,
    pub query_mode_reason: String,
    pub collection_name: String,
    pub retrieval_mode: String,
    pub routing_decision: RetrievalRoutingDecision,
    pub dense_backend: String,
    pub sparse_backend: String,
    pub reranker_backend: String,
    pub reranking_applied: bool,
    pub applied_filters: RetrievalFilters,
    pub promotion_policy_id: String,
    pub retention_policy_id: String,
    #[serde(default)]
    pub root_entity_type: Option<String>,
    #[serde(default)]
    pub root_entity_id: Option<String>,
    #[serde(default)]
    pub program_id: Option<String>,
    #[serde(default)]
    pub campaign_id: Option<String>,
    #[serde(default)]
    pub workstream_id: Option<String>,
    #[serde(default)]
    pub session_id: Option<String>,
    pub support_memory_ids: Vec<String>,
    pub node_count: usize,
    pub edge_count: usize,
    pub nodes: Vec<GraphRagNode>,
    pub edges: Vec<GraphRagEdge>,
    #[serde(default)]
    pub promoted_memories: Vec<crate::promotion::PromotedMemory>,
    #[serde(default)]
    pub memory_hierarchy: Option<MemoryHierarchy>,
    pub note: String,
}
