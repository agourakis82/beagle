//! Beagle Memory - Conversation context management via hypergraph
//!
//! Provides Context Bridge for storing and retrieving conversation history
//! with semantic search capabilities, plus graph knowledge storage.

pub mod bridge;
pub mod engine;
pub mod models;

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

// Graph exports
pub use graph::{
    GraphError, GraphNode, GraphQueryResult, GraphRelationship, GraphStore, InMemoryGraphStore,
};
pub use neo4j::Neo4jGraphStore;
