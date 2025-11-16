//! Meta-Cognitive Self-Improvement
//! 
//! System that:
//! 1. Monitors its own performance
//! 2. Identifies weaknesses and failure patterns
//! 3. Evolves architecture autonomously
//! 4. Creates specialized agents on-demand

pub mod monitor;
pub mod analyzer;
pub mod evolver;
pub mod specialized;

pub use monitor::PerformanceMonitor;
pub use analyzer::{WeaknessAnalyzer, FailurePattern};
pub use evolver::{ArchitectureEvolver, AgentSpecification, EvolutionResult};
pub use specialized::SpecializedAgentFactory;
