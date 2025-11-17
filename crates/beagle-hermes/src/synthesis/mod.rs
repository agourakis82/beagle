//! Autonomous paper synthesis engine

mod scheduler;
mod engine;
mod citation_validator;
mod voice_similarity;
mod refinement;

pub use scheduler::{SynthesisScheduler, SchedulerConfig};
pub use engine::{SynthesisEngine, SynthesisResult};
pub use citation_validator::{CitationValidator, CitationValidationResult};
pub use voice_similarity::VoiceSimilarityAnalyzer;
pub use refinement::RefinementEngine;

use crate::knowledge::ConceptCluster;
use serde::{Serialize, Deserialize};
use uuid::Uuid;

/// Synthesis request
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SynthesisRequest {
    pub cluster: ConceptCluster,
    pub section_type: crate::SectionType,
    pub target_words: usize,
    pub voice_profile: VoiceProfile,
}

/// Voice profile for LoRA adapter
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct VoiceProfile {
    pub adapter_path: String,
    pub similarity_target: f64, // e.g., 0.95
}

impl Default for VoiceProfile {
    fn default() -> Self {
        Self {
            adapter_path: "models/beagle-hermes-voice-v1.safetensors".to_string(),
            similarity_target: 0.95,
        }
    }
}

