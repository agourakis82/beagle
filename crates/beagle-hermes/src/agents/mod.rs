//! Multi-agent orchestration for advanced synthesis

pub mod argos;
pub mod athena;
pub mod hermes_agent;
pub mod integrated_pipeline;
pub mod orchestrator;

pub use argos::ArgosAgent;
// Tipos de validação devem ser importados diretamente de beagle_llm::validation
pub use athena::AthenaAgent;
pub use beagle_llm::validation::{Issue, IssueType, Severity, ValidationResult};
pub use hermes_agent::{Draft, GenerationContext, HermesAgent};
pub use integrated_pipeline::{EnhancedSynthesisOutput, IntegratedPipeline};
pub use orchestrator::MultiAgentOrchestrator;
