//! Multi-agent orchestration for advanced synthesis

pub mod argos;
pub mod athena;
pub mod hermes_agent;
pub mod orchestrator;

pub use argos::{ArgosAgent, ValidationResult, Issue, IssueType, Severity};
pub use athena::AthenaAgent;
pub use hermes_agent::{HermesAgent, Draft, GenerationContext};
pub use orchestrator::MultiAgentOrchestrator;
