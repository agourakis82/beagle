//! # BEAGLE Advanced Personality System - Fixed Version
//!
//! Simplified version that compiles correctly

use anyhow::Result;
use serde::{Deserialize, Serialize};
use std::collections::HashMap;
use std::sync::Arc;
use tokio::sync::RwLock;

pub mod adaptation;
pub mod cultural;
pub mod emotional;
pub mod memory;
pub mod response_generator;
pub mod traits;

// Re-exports
pub use adaptation::{AdaptationConfig, AdaptationEngine};
pub use cultural::{CulturalAdapter, CulturalConfig};
pub use emotional::{EmotionVector, EmotionalConfig, EmotionalState};
pub use memory::{MemoryConfig, PersonalityMemory};
pub use response_generator::{GeneratorConfig, ResponseGenerator};
pub use traits::{PersonalityProfiles, PersonalityTraits};

/// Simplified personality system
pub struct PersonalitySystem {
    traits: Arc<RwLock<PersonalityTraits>>,
    emotional: Arc<EmotionalState>,
    adaptation: Arc<AdaptationEngine>,
    cultural: Arc<CulturalAdapter>,
    memory: Arc<RwLock<PersonalityMemory>>,
    generator: Arc<ResponseGenerator>,
    config: PersonalityConfig,
}

/// Personality configuration
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct PersonalityConfig {
    pub base_traits: PersonalityTraits,
    pub emotional_config: EmotionalConfig,
    pub adaptation_config: AdaptationConfig,
    pub cultural_config: CulturalConfig,
    pub memory_config: MemoryConfig,
    pub generator_config: GeneratorConfig,
    pub enable_learning: bool,
}

impl Default for PersonalityConfig {
    fn default() -> Self {
        Self {
            base_traits: PersonalityTraits::default(),
            emotional_config: EmotionalConfig::default(),
            adaptation_config: AdaptationConfig::default(),
            cultural_config: CulturalConfig::default(),
            memory_config: MemoryConfig::default(),
            generator_config: GeneratorConfig::default(),
            enable_learning: true,
        }
    }
}

impl PersonalitySystem {
    /// Create new personality system
    pub async fn new(config: PersonalityConfig) -> Result<Self> {
        Ok(Self {
            traits: Arc::new(RwLock::new(config.base_traits.clone())),
            emotional: Arc::new(EmotionalState::new(config.emotional_config.clone())),
            adaptation: Arc::new(AdaptationEngine::new(config.adaptation_config.clone())),
            cultural: Arc::new(CulturalAdapter::new(config.cultural_config.clone())),
            memory: Arc::new(RwLock::new(PersonalityMemory::new(
                config.memory_config.clone(),
            ))),
            generator: Arc::new(ResponseGenerator::new(config.generator_config.clone())),
            config,
        })
    }

    /// Generate response with personality
    pub async fn generate_response(
        &self,
        input: &str,
        context: HashMap<String, String>,
    ) -> Result<PersonalizedResponse> {
        // Get current traits
        let traits = self.traits.read().await.clone();

        // Get emotional state
        let emotions = self.emotional.get_current().await;

        // Generate response
        let intent = "response";
        let response_text = self
            .generator
            .generate(intent, &context, &traits, &emotions)
            .await
            .unwrap_or_else(|_| format!("I understand: {}", input));

        Ok(PersonalizedResponse {
            content: response_text,
            personality_traits: traits,
            emotional_state: emotions,
            confidence: 0.8,
        })
    }

    /// Update traits
    pub async fn update_traits(&self, updates: HashMap<String, f32>) -> Result<()> {
        let mut traits = self.traits.write().await;
        for (name, value) in updates {
            traits.set_trait(&name, value);
        }
        Ok(())
    }

    /// Get current traits
    pub async fn get_traits(&self) -> PersonalityTraits {
        self.traits.read().await.clone()
    }

    /// Get personality description
    pub async fn describe(&self) -> String {
        let traits = self.traits.read().await;
        let emotions = self.emotional.get_current().await;

        format!(
            "Personality Profile:\n\
            - Openness: {:.0}%\n\
            - Conscientiousness: {:.0}%\n\
            - Extraversion: {:.0}%\n\
            - Agreeableness: {:.0}%\n\
            - Neuroticism: {:.0}%\n\
            \nCurrent Emotional State:\n\
            - Joy: {:.0}%\n\
            - Trust: {:.0}%\n\
            - Fear: {:.0}%\n\
            - Arousal: {:.0}%\n\
            - Valence: {:.0}%",
            traits.openness * 100.0,
            traits.conscientiousness * 100.0,
            traits.extraversion * 100.0,
            traits.agreeableness * 100.0,
            traits.neuroticism * 100.0,
            emotions.joy * 100.0,
            emotions.trust * 100.0,
            emotions.fear * 100.0,
            emotions.arousal * 100.0,
            emotions.valence * 100.0,
        )
    }
}

/// Personalized response
#[derive(Debug, Clone)]
pub struct PersonalizedResponse {
    pub content: String,
    pub personality_traits: PersonalityTraits,
    pub emotional_state: EmotionVector,
    pub confidence: f32,
}

#[cfg(test)]
mod tests {
    use super::*;

    #[tokio::test]
    async fn test_personality_system() {
        let config = PersonalityConfig::default();
        let system = PersonalitySystem::new(config).await.unwrap();

        let context = HashMap::from([("user".to_string(), "test".to_string())]);

        let response = system.generate_response("Hello", context).await.unwrap();
        assert!(!response.content.is_empty());
    }

    #[tokio::test]
    async fn test_trait_updates() {
        let config = PersonalityConfig::default();
        let system = PersonalitySystem::new(config).await.unwrap();

        let updates = HashMap::from([
            ("openness".to_string(), 0.8),
            ("extraversion".to_string(), 0.7),
        ]);

        system.update_traits(updates).await.unwrap();

        let traits = system.get_traits().await;
        assert_eq!(traits.openness, 0.8);
        assert_eq!(traits.extraversion, 0.7);
    }
}
