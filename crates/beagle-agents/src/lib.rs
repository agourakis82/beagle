//! Beagle Agents - Autonomous research agents with Self-RAG
//!
//! Provides:
//! - ResearcherAgent: Sequential Self-RAG research
//! - CoordinatorAgent: Parallel multi-agent orchestration
//! - DebateOrchestrator: Adversarial debate system
//! - HypergraphReasoner: Path-based reasoning
//! - CausalReasoner: Causal discovery and intervention
//! - Specialized agents: Retrieval, Validation, Quality

pub mod agent_trait;
pub mod coordinator;
pub mod models;
pub mod researcher;
pub mod specialized_agents;

// Disruptive techniques modules
pub mod debate;
pub mod reasoning;
pub mod causal;

// Re-export core types
pub use agent_trait::{Agent, AgentCapability, AgentHealth, AgentInput, AgentOutput};
pub use coordinator::CoordinatorAgent;
pub use models::{ResearchMetrics, ResearchResult, ResearchStep};
pub use researcher::ResearcherAgent;
pub use specialized_agents::{QualityAgent, RetrievalAgent, ValidationAgent};

// Re-export debate types
pub use debate::{
    DebateOrchestrator,
    DebateTranscript,
    DebateRound,
    DebateSynthesis,
};

// Re-export reasoning types
pub use reasoning::{
    HypergraphReasoner,
    ReasoningPath,
    ReasoningType,
    PathNode,
};

// Re-export causal types
pub use causal::{
    CausalReasoner,
    CausalGraph,
    CausalNode,
    CausalEdge,
    NodeType,
    CausalEdgeType,
    InterventionResult,
    CounterfactualResult,
    CausalMetadata,
};
