//! Beagle Memory - Conversation context management via hypergraph
//!
//! Provides Context Bridge for storing and retrieving conversation history
//! with semantic search capabilities, plus graph knowledge storage.

pub mod bridge;
pub mod budgeting;
pub mod compiler;
pub mod engine;
pub mod graphrag_modes;
pub mod models;
pub mod promotion;
pub mod retention;
pub mod retrieval;
pub mod temporal;

// Graph knowledge storage
pub mod graph;
pub mod neo4j;

pub use bridge::ContextBridge;
pub use budgeting::{
    CONTEXT_BUDGET_PROFILE_VERSION, ContextBudgetAllocation, ContextBudgetProfile,
    compiler_policy_variants, context_budget_profile, normalize_task_profile,
    supported_task_profiles,
};
pub use compiler::{
    COMPILED_CONTEXT_PACKET_VERSION, COMPILER_EVAL_REPORT_VERSION,
    COMPILER_POLICY_VERSION, CONTEXT_EVAL_CASE_VERSION, CompilerEvalReport,
    CompilerEvalRequest, CompilerPolicy, CompilerPolicyProfile,
    CompilerPolicyVariantReport, CompilerTaskComparison,
    CompiledContextPacket, CompiledContextRequest, CompiledContextSourceSlice,
    ContextEvalCase, MEMORY_COMPILER_VERSION, MemoryCompilerContract, memory_compiler_contract,
};
pub use engine::{
    ChatSession, ChatTurn, ExperimentFlags, IngestStats, MemoryEngine, MemoryEngineConfig,
    MemoryQdrantHealth, MemoryQuery, MemoryRecord, MemoryResult, MemoryResultHighlight,
    PhysioSnapshot,
};
pub use models::{
    ConversationMetadata, ConversationSession, ConversationTurn, PerformanceMetrics,
    RetrievedContext, UserFeedback,
};
pub use retrieval::{
    CodeRetrievalBackendProfile, CodeRetrievalComparison, CodeRetrievalQuery,
    CodeRetrievalResult, EmbeddingBackendCandidate, EmbeddingBackendContract,
    EmbeddingBackendMatrix, GraphRagEdge, GraphRagNode, GraphRagQuery,
    GraphRagResult, MemoryHierarchy, MemoryHierarchyBucket, MemoryPoint, RetrievalBenchmarkCase,
    RetrievalBenchmarkCaseReport, RetrievalBenchmarkReport, RetrievalBenchmarkRequest,
    RetrievalBenchmarkSummary, RetrievalCollection, RetrievalCollectionField,
    RetrievalEvalCase, RetrievalEvalCaseReport, RetrievalEvalLaneSummary,
    RetrievalEvalReport, RetrievalEvalRequest, RetrievalFilters, RetrievalHit,
    RetrievalPolicy, RetrievalPolicyLane, RetrievalQuery, RetrievalQueryType,
    RetrievalRecommendation, RetrievalResult, RetrievalRoutingDecision,
    FeedbackAdjustedHit, FeedbackLatencyComparison, FeedbackLoopResult,
    RelevanceFeedbackInput, RelevanceFeedbackJudgment, RerankedHit, RerankedResult, RerankingCandidate,
    RerankingLatencyComparison, RerankingProfile,
    RerankingRecommendation, RoutedRetrievalQuery,
    RoutedRetrievalResult,
    SovereignRetrievalBackendProfile, SovereignRetrievalComparison,
    SovereignRetrievalQuery, SovereignRetrievalResult,
    CODE_RETRIEVAL_QUERY_VERSION, CODE_RETRIEVAL_RESULT_VERSION,
    EMBEDDING_BACKEND_CONTRACT_VERSION, EMBEDDING_BACKEND_MATRIX_VERSION,
    GRAPHRAG_EDGE_VERSION, GRAPHRAG_NODE_VERSION, GRAPHRAG_QUERY_VERSION,
    GRAPHRAG_RESULT_VERSION, MEMORY_HIERARCHY_VERSION, MEMORY_POINT_VERSION,
    QUERY_TYPE_VERSION, RELEVANCE_FEEDBACK_VERSION,
    RERANKED_RESULT_VERSION, RERANKING_PROFILE_VERSION,
    RETRIEVAL_BENCHMARK_VERSION, RETRIEVAL_COLLECTION_VERSION,
    RETRIEVAL_EVAL_REPORT_VERSION, RETRIEVAL_POLICY_VERSION,
    RETRIEVAL_QUERY_VERSION, RETRIEVAL_RESULT_VERSION,
    RETRIEVAL_ROUTER_VERSION, RETRIEVAL_ROUTING_DECISION_VERSION,
    ROUTED_RETRIEVAL_QUERY_VERSION, ROUTED_RETRIEVAL_RESULT_VERSION,
    SOVEREIGN_RETRIEVAL_QUERY_VERSION, SOVEREIGN_RETRIEVAL_RESULT_VERSION,
};
pub use graphrag_modes::{
    GraphRagQueryModeDecision, GRAPHRAG_QUERY_MODE_VERSION, apply_graphrag_query_mode,
    derive_graphrag_query_mode,
};
pub use promotion::{
    MemoryPromotionPolicy, MemoryPromotionRule, PromotedMemory,
    MEMORY_PROMOTION_POLICY_VERSION, PROMOTED_MEMORY_VERSION, classify_memory_type,
    derive_memory_promotion, memory_promotion_policy, promoted_target_memory_type,
};
pub use retention::{
    MemoryRetentionPolicy, MemoryRetentionRule, MEMORY_RETENTION_POLICY_VERSION,
    memory_retention_policy, retention_action_for_memory_type,
};
pub use temporal::{
    MemoryContradiction, TemporalMemorySchema, TemporalMemoryTrack, TemporalMemoryVersion,
    TemporalQuery, TemporalQueryResult, MEMORY_CONTRADICTION_VERSION,
    TEMPORAL_MEMORY_VERSION, TEMPORAL_QUERY_RESULT_VERSION, TEMPORAL_QUERY_VERSION,
    detect_temporal_contradiction, normalize_truth_view, temporal_entity_refs,
    temporal_memory_schema, temporal_truth_keys, temporal_version_from_record,
};

// Graph exports
pub use graph::{
    GraphError, GraphNode, GraphQueryResult, GraphRelationship, GraphStore, InMemoryGraphStore,
};
pub use neo4j::Neo4jGraphStore;
