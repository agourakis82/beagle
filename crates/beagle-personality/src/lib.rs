//! Beagle Personality Engine
//!
//! Sistema de adaptação contextual que detecta domínio de conhecimento
//! e ajusta system prompts, tom e profundidade das respostas.

pub mod detector;
mod detector_extended;
pub mod domain;
pub mod engine;
pub mod loader;
pub mod profile;

pub use detector::ContextDetector;
pub use domain::Domain;
pub use engine::PersonalityEngine;
pub use loader::{global_loader, ProfileLoader};
pub use profile::{Guidelines, Profile, ProfileMetadata, SystemPromptConfig};

/// Função de conveniência: detecta domínio a partir de uma query
pub fn detect_domain(query: &str) -> Domain {
    let detector = ContextDetector::new();
    detector.detect(query)
}

/// Função de conveniência: gera system prompt adaptado à query
pub fn system_prompt_for(query: &str) -> String {
    let engine = PersonalityEngine::new();
    engine.system_prompt_for(query)
}
