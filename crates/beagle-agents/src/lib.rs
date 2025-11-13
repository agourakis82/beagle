
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

pub mod adversarial;



// ============================================

// Core exports

// ============================================

pub use agent_trait::{Agent, AgentCapability, AgentHealth, AgentInput, AgentOutput};

pub use coordinator::CoordinatorAgent;

pub use models::{

    ResearchMetrics, ResearchResult, ResearchStep,

};

pub use researcher::ResearcherAgent;

pub use specialized_agents::{QualityAgent, RetrievalAgent, ValidationAgent};



// ============================================

// Debate exports

// ============================================

pub use debate::{

    DebateOrchestrator, 

    DebateTranscript, 

    DebateRound, 

    DebateSynthesis,

};



// ============================================

// Reasoning exports

// ============================================

pub use reasoning::{

    HypergraphReasoner,

    ReasoningPath,

    ReasoningType,

    PathNode,

};



// ============================================

// Causal exports

// ============================================

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



// ============================================

// Deep Research exports (MCTS + PUCT)

// ============================================

pub use deep_research::{

    mcts::{MCTSEngine, DeepResearchResult},

    hypothesis::{Hypothesis, HypothesisNode, HypothesisTree},

    simulation::{SimulationEngine, SimulationResult},

    puct::PUCTSelector,

};



// ============================================

// Swarm Intelligence exports

// ============================================

pub use swarm::{

    SwarmAgent,

    Pheromone,

    PheromoneField,

    SwarmOrchestrator,

    EmergentBehavior,

};



// ============================================

// Temporal Multi-Scale exports

// ============================================

pub use temporal::{

    TemporalScale,

    TimePoint,

    TimeRange,

    TemporalReasoner,

    CrossScaleCausality,

};



// ============================================

// Meta-Cognitive exports

// ============================================

pub use metacognitive::{

    PerformanceMonitor,

    WeaknessAnalyzer,

    FailurePattern,

    ArchitectureEvolver,

    SpecializedAgentFactory,

};



// ============================================

// Neuro-Symbolic exports

// ============================================

pub use neurosymbolic::{

    NeuralExtractor,

    SymbolicReasoner,

    LogicRule,

    Predicate,

    ConstraintSolver,

    HybridReasoner,

};



// ============================================

// Quantum-Inspired exports

// ============================================

pub use quantum::{

    QuantumHypothesis,

    SuperpositionState,

    MeasurementOperator,

    InterferenceEngine,

};



// ============================================

// Adversarial Self-Play exports

// ============================================

pub use adversarial::{

    ResearchPlayer,

    CompetitionArena,

    Strategy,

    StrategyEvolution,

};

