//! Beagle Memory - Conversation context management via hypergraph
//!
//! Provides Context Bridge for storing and retrieving conversation history
//! with semantic search capabilities.

pub mod bridge;
pub mod models;

pub use bridge::ContextBridge;
pub use models::{
    ConversationMetadata, ConversationSession, ConversationTurn, PerformanceMetrics,
    RetrievedContext, UserFeedback,
};
