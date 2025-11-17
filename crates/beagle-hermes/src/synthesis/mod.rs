//! Autonomous paper synthesis engine

mod citation_validator;
mod engine;
mod refinement;
mod voice_similarity;

pub use citation_validator::{CitationValidationResult, CitationValidator};
pub use engine::{SynthesisEngine, SynthesisResult};
pub use refinement::RefinementEngine;
pub use voice_similarity::VoiceSimilarityAnalyzer;

use crate::knowledge::ConceptCluster;
use serde::{Deserialize, Serialize};

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
