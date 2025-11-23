//! Beagle Agents - Advanced AI Research System

//!

//! Revolutionary features:

//! - Deep Research (MCTS + PUCT)

//! - Swarm Intelligence

//! - Temporal Multi-Scale Reasoning

//! - Meta-Cognitive Self-Improvement

//! - Neuro-Symbolic Hybrid

//! - Quantum-Inspired Superposition

//! - Adversarial Self-Play Evolution

// Core agent infrastructure

pub mod agent_trait;

pub mod coordinator;

pub mod models;

pub mod researcher;

pub mod specialized_agents;

// Disruptive techniques (v1.0)

pub mod debate;

pub mod reasoning;

pub mod causal;

// Revolutionary techniques (v2.0)

pub mod deep_research;

pub mod swarm;

pub mod temporal;

pub mod metacognitive;

pub mod neurosymbolic;

pub mod quantum;

pub mod quantum_mcts;

pub mod adversarial;

// ============================================

// Core exports

// ============================================

pub use agent_trait::{Agent, AgentCapability, AgentHealth, AgentInput, AgentOutput};

pub use coordinator::CoordinatorAgent;

pub use models::{ResearchMetrics, ResearchResult, ResearchStep};

pub use researcher::ResearcherAgent;

pub use specialized_agents::{QualityAgent, RetrievalAgent, ValidationAgent};

// ============================================

// Debate exports

// ============================================

pub use debate::{DebateOrchestrator, DebateRound, DebateSynthesis, DebateTranscript};

// ============================================

// Reasoning exports

// ============================================

pub use reasoning::{HypergraphReasoner, PathNode, ReasoningPath, ReasoningType};

// ============================================

// Causal exports

// ============================================

pub use causal::{
    CausalEdge, CausalEdgeType, CausalGraph, CausalMetadata, CausalNode, CausalReasoner,
    CounterfactualResult, InterventionResult, NodeType,
};

// ============================================

// Deep Research exports (MCTS + PUCT)

// ============================================

pub use deep_research::{
    hypothesis::{Hypothesis, HypothesisNode, HypothesisTree},
    mcts::{DeepResearchResult, MCTSEngine},
    puct::PUCTSelector,
    simulation::{SimulationEngine, SimulationResult},
};

// ============================================

// Swarm Intelligence exports

// ============================================

pub use swarm::{EmergentBehavior, Pheromone, PheromoneField, SwarmAgent, SwarmOrchestrator};

// ============================================

// Temporal Multi-Scale exports

// ============================================

pub use temporal::{CrossScaleCausality, TemporalReasoner, TemporalScale, TimePoint, TimeRange};

// ============================================

// Meta-Cognitive exports

// ============================================

pub use metacognitive::{
    ArchitectureEvolver, FailurePattern, PerformanceMonitor, SpecializedAgentFactory,
    WeaknessAnalyzer,
};

// ============================================

// Neuro-Symbolic exports

// ============================================

pub use neurosymbolic::{
    ConstraintSolver, HybridReasoner, LogicRule, NeuralExtractor, Predicate, SymbolicReasoner,
};

// ============================================

// Quantum-Inspired exports

// ============================================

pub use quantum::{
    HypothesisMetadata, InterferenceEngine, InterferenceType, MeasurementOperator,
    MeasurementResult, QuantumHypothesis, SuperpositionState,
};

pub use quantum_mcts::{QuantumMCTS, QuantumResearchResult};

// ============================================

// Adversarial Self-Play exports

// ============================================

pub use adversarial::{CompetitionArena, ResearchPlayer, Strategy, StrategyEvolution};
