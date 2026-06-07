//! Beagle Memory - Conversation context management via hypergraph
//!
//! Provides Context Bridge for storing and retrieving conversation history
//! with semantic search capabilities, plus graph knowledge storage.

pub mod bridge;
pub mod engine;
pub mod error;
pub mod models;
pub mod rag_engine;

// Graph knowledge storage
pub mod graph;
pub mod neo4j;

pub use bridge::ContextBridge;
pub use engine::{
    ChatSession, ChatTurn, IngestStats, MemoryEngine, MemoryQuery, MemoryResult,
    MemoryResultHighlight,
};
pub use models::{
    ConversationMetadata, ConversationSession, ConversationTurn, PerformanceMetrics,
    RetrievedContext, UserFeedback,
};

// RAG engine (hybrid dense+sparse retrieval with Reciprocal Rank Fusion)
pub use error::MemoryError;
pub use rag_engine::{
    reciprocal_rank_fusion, Chunk, Document, FusedResult, RAGEngine,
    RetrievedContext as RagRetrievedContext, ANN_BATCH_CAP, RRF_K, SPARSE_WEIGHT,
};

// Graph exports
pub use graph::{
    GraphError, GraphNode, GraphQueryResult, GraphRelationship, GraphStore, InMemoryGraphStore,
};
pub use neo4j::Neo4jGraphStore;
