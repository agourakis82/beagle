//! Multi-agent orchestration for advanced synthesis

pub mod athena;
pub mod hermes_agent;
pub mod argos;
pub mod orchestrator;

pub use athena::AthenaAgent;
pub use hermes_agent::HermesAgent;
pub use argos::ArgosAgent;
pub use orchestrator::MultiAgentOrchestrator;

