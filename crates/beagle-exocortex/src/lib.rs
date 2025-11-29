//! Personal Exocortex - Unified Cognitive Orchestration Layer
//!
//! This crate provides the central integration point for BEAGLE's cognitive
//! architecture, unifying previously disconnected subsystems into a cohesive
//! personal assistant experience.
//!
//! # Architecture
//!
//! ```text
//!                    ┌─────────────────────────────────────┐
//!                    │       PersonalExocortex             │
//!                    │   "Your External Cognitive Layer"   │
//!                    └─────────────┬───────────────────────┘
//!                                  │
//!          ┌───────────┬───────────┼───────────┬───────────┐
//!          ▼           ▼           ▼           ▼           ▼
//!    ┌──────────┐ ┌──────────┐ ┌──────────┐ ┌──────────┐ ┌──────────┐
//!    │ Identity │ │  Brain   │ │ Context  │ │  Agent   │ │ Memory   │
//!    │  System  │ │Connector │ │ Manager  │ │  Mesh    │ │ Bridge   │
//!    │          │ │(IIT/GWT) │ │(WorldMdl)│ │ (Tasks)  │ │ (RAG)    │
//!    └──────────┘ └──────────┘ └──────────┘ └──────────┘ └──────────┘
//!        USER        CONSCIOUS    SITUATION    EXECUTION   RETRIEVAL
//!       PROFILE      SUBSTRATE     AWARENESS    LAYER       LAYER
//! ```
//!
//! # Core Concepts
//!
//! - **Identity System**: Persistent user profile, preferences, expertise levels
//! - **Brain Connector**: IIT consciousness substrate + Global Workspace attention
//! - **Context Manager**: World model integration for situational awareness
//! - **Agent Mesh**: Coordinated agent team with specialization learning
//! - **Memory Bridge**: Unified semantic + episodic memory with consciousness tagging
//!
//! # Usage
//!
//! ```rust,ignore
//! use beagle_exocortex::{PersonalExocortex, ExocortexConfig};
//!
//! let exocortex = PersonalExocortex::new(config).await?;
//!
//! // Process a request with full cognitive integration
//! let response = exocortex.process(
//!     "Help me understand quantum entanglement",
//!     Some(user_physio_state),
//! ).await?;
//!
//! // The response includes:
//! // - Consciousness confidence (Φ-based)
//! // - Personality-adapted language
//! // - Relevant memories surfaced
//! // - User expertise-aware explanations
//! ```

pub mod agents;
pub mod brain;
pub mod config;
pub mod context;
pub mod error;
pub mod identity;
pub mod memory;
pub mod orchestrator;
pub mod workflow;

pub use agents::{AgentCapability, AgentMesh, AgentMeshConfig, AgentTeam, TaskContext};
pub use brain::{AwarenessLevel, BrainConnector, BrainConnectorConfig, ConsciousnessState};
pub use config::ExocortexConfig;
pub use context::{ContextAdaptations, ContextManager, ContextManagerConfig, SituationalContext};
pub use error::{ExocortexError, ExocortexResult};
pub use identity::{ExpertiseLevel, IdentitySystem, PersistenceMode, UserPreferences, UserProfile};
pub use memory::{
    EmotionalValence, EpisodicMemory, MemoryBridge, MemoryBridgeConfig, MemoryStats, SemanticMemory,
};
pub use orchestrator::{
    ExocortexBuilder, ExocortexInput, ExocortexOutput, InputModality, PersonalExocortex,
    ProactiveSuggestion, SessionStats,
};
pub use workflow::{
    AgentDefinition, FlowDefinition, FlowStep, FlowType, ModelConfig, TeamDefinition,
    TerminationConfig, ToolDefinition, WorkflowDefinition,
};

/// Version of the exocortex system
pub const VERSION: &str = env!("CARGO_PKG_VERSION");

/// Initialize the personal exocortex with default configuration
pub async fn init() -> Result<PersonalExocortex, ExocortexError> {
    let config = ExocortexConfig::default();
    PersonalExocortex::new(config).await
}

/// Initialize with custom configuration
pub async fn init_with_config(
    config: ExocortexConfig,
) -> Result<PersonalExocortex, ExocortexError> {
    PersonalExocortex::new(config).await
}

#[cfg(test)]
mod tests {
    use super::*;

    #[tokio::test]
    async fn test_exocortex_init() {
        let config = ExocortexConfig::minimal();
        let exocortex = PersonalExocortex::new(config).await;
        assert!(exocortex.is_ok());
    }
}
