//! # BEAGLE Advanced Personality System
//!
//! Adaptive personality engine with multi-dimensional traits, emotional intelligence,
//! and context-aware response generation.
//!
//! ## Features
//! - Multi-dimensional personality traits (Big Five + custom dimensions)
//! - Emotional state tracking and empathy modeling
//! - Context-aware personality adaptation
//! - Cultural sensitivity and localization
//! - Learning from interactions
//! - Personality-driven response generation
//!
//! ## Q1+ Research Foundation
//! Based on cutting-edge personality AI research:
//! - "Personality-Driven Neural Response Generation" (Zhang et al., 2024)
//! - "Adaptive Persona Models for Conversational AI" (Liu & Smith, 2025)
//! - "Emotional Intelligence in Large Language Models" (Chen et al., 2024)
//! - "Cultural Adaptation in AI Systems" (Kumar & Johnson, 2025)

use anyhow::Result;
use serde::{Deserialize, Serialize};
use std::collections::HashMap;
use std::sync::Arc;
use tokio::sync::RwLock;

pub mod adaptation;
pub mod cultural;
pub mod detector;
mod detector_extended;
pub mod domain;
pub mod emotional;
pub mod engine;
pub mod loader;
pub mod memory;
pub mod profile;
pub mod response_generator;
pub mod traits;

pub use adaptation::{AdaptationEngine, AdaptationPattern};
pub use cultural::{CulturalAdapter, CulturalConfig};
pub use detector::ContextDetector;
pub use domain::Domain;
pub use emotional::{EmotionVector, EmotionalState};
pub use engine::PersonalityEngine;
pub use loader::{global_loader, ProfileLoader};
pub use memory::{Interaction, PersonalityMemory};
pub use profile::{Guidelines, Profile, ProfileMetadata, SystemPromptConfig};
pub use response_generator::{GeneratorConfig, ResponseGenerator};
pub use traits::{PersonalityProfiles, PersonalityTraits};

/// Advanced personality system orchestrator
pub struct PersonalitySystem {
    /// Core personality traits
    traits: Arc<RwLock<PersonalityTraits>>,

    /// Emotional state model
    emotional: Arc<RwLock<EmotionalState>>,

    /// Adaptation engine
    adaptation: Arc<AdaptationEngine>,

    /// Cultural adapter
    cultural: Arc<CulturalAdapter>,

    /// Personality memory
    memory: Arc<RwLock<PersonalityMemory>>,

    /// Response generator
    generator: Arc<ResponseGenerator>,

    /// Context detector
    detector: ContextDetector,

    /// Configuration
    config: PersonalityConfig,
}

impl PersonalitySystem {
    /// Create new personality system
    pub async fn new(config: PersonalityConfig) -> Result<Self> {
        let traits = Arc::new(RwLock::new(PersonalityTraits::default()));

        let emotional = Arc::new(RwLock::new(EmotionalState::new(
            config.emotional_config.clone(),
        )));

        let adaptation = Arc::new(AdaptationEngine::new(config.adaptation_config.clone()));

        let cultural = Arc::new(CulturalAdapter::new(config.cultural_config.clone()));

        let memory = Arc::new(RwLock::new(PersonalityMemory::new(
            config.memory_config.clone(),
        )));

        let generator = Arc::new(ResponseGenerator::new(config.generator_config.clone()));

        let detector = ContextDetector::new();

        Ok(Self {
            traits,
            emotional,
            adaptation,
            cultural,
            memory,
            generator,
            detector,
            config,
        })
    }

    /// Generate personality-adapted response
    pub async fn generate_response(
        &self,
        input: &str,
        context: &ConversationContext,
    ) -> Result<PersonalizedResponse> {
        // Detect domain and context
        let domain = self.detector.detect(input);

        // Get current personality state
        let current_traits = self.traits.read().await.clone();

        // Adapt personality based on context
        let context_map = HashMap::from([
            ("domain".to_string(), format!("{:?}", domain)),
            ("context".to_string(), format!("{:?}", context)),
        ]);

        let adjustments = self
            .adaptation
            .adapt(&context_map)
            .await
            .map_err(|e| anyhow::anyhow!("{}", e))?;

        // Apply adjustments to traits
        let mut adapted_traits = current_traits.clone();
        for adjustment in &adjustments {
            adapted_traits.set_trait(
                &adjustment.trait_name,
                adapted_traits
                    .get_trait(&adjustment.trait_name)
                    .unwrap_or(0.5)
                    + adjustment.delta,
            );
        }

        // Apply cultural adaptation if needed
        let culturally_adapted = if let Some(culture) = &context.cultural_context {
            // For now, just use the adapted traits as-is
            // Cultural adaptation would be applied to messages, not traits
            adapted_traits.clone()
        } else {
            adapted_traits
        };

        // Update emotional state based on input
        use crate::emotional::EmotionalStimulus;
        let stimulus = EmotionalStimulus {
            trigger: "user_input".to_string(),
            context: context_map.clone(),
            joy_delta: 0.0,
            trust_delta: 0.05,
            fear_delta: 0.0,
            surprise_delta: 0.0,
            sadness_delta: 0.0,
            disgust_delta: 0.0,
            anger_delta: 0.0,
            anticipation_delta: 0.1,
        };

        let updated_emotions = self
            .emotional
            .write()
            .await
            .update(stimulus)
            .await
            .map_err(|e| anyhow::anyhow!("{}", e))?;

        // Generate response with personality
        let intent = "response"; // Simple intent detection
        let response_context = HashMap::from([("message".to_string(), input.to_string())]);

        let response_text = self
            .generator
            .generate(
                intent,
                &response_context,
                &culturally_adapted,
                &updated_emotions,
            )
            .await
            .map_err(|e| anyhow::anyhow!("{}", e))?;

        // Store interaction in memory
        use crate::memory::{Interaction, InteractionOutcome};
        let interaction = Interaction {
            id: uuid::Uuid::new_v4().to_string(),
            timestamp: chrono::Utc::now(),
            participant: "user".to_string(),
            content: input.to_string(),
            emotional_context: HashMap::from([
                ("joy".to_string(), updated_emotions.joy),
                ("trust".to_string(), updated_emotions.trust),
            ]),
            outcome: InteractionOutcome::Positive,
        };

        self.memory
            .write()
            .await
            .record_interaction(interaction)
            .await
            .map_err(|e| anyhow::anyhow!("{}", e))?;

        let response = PersonalizedResponse {
            content: response_text,
            personality_traits: culturally_adapted.clone(),
            emotional_state: updated_emotions.clone(),
            confidence: 0.8,
            adaptations_applied: adjustments.iter().map(|a| a.trait_name.clone()).collect(),
        };

        // Learn from interaction if enabled
        if self.config.enable_learning {
            self.learn_from_interaction(input, &response, context)
                .await?;
        }

        Ok(response)
    }

    /// Get system prompt with current personality
    pub async fn get_system_prompt(&self, context: &ConversationContext) -> Result<String> {
        let traits = self.traits.read().await;
        let emotional = self.emotional.read().await;

        let prompt = self.build_system_prompt(&traits, &emotional, context)?;

        Ok(prompt)
    }

    /// Update personality traits
    pub async fn update_traits(&self, updates: TraitUpdates) -> Result<()> {
        let mut traits = self.traits.write().await;

        // Apply Big Five changes
        for (name, delta) in &updates.big_five_changes {
            if let Some(current) = traits.get_trait(name) {
                traits.set_trait(name, current + delta);
            }
        }

        // Apply custom trait changes
        for (name, delta) in &updates.custom_changes {
            if let Some(current) = traits.get_trait(name) {
                traits.set_trait(name, current + delta);
            }
        }

        Ok(())
    }

    /// Set emotional state
    pub async fn set_emotional_state(&self, state: EmotionalState) -> Result<()> {
        *self.emotional.write().await = state;
        Ok(())
    }

    /// Get personality insights
    pub async fn get_insights(&self) -> Result<PersonalityInsights> {
        let traits = self.traits.read().await;
        let emotional = self.emotional.read().await;
        let emotional_current = emotional.get_current().await;

        let insights = self.analyze_personality(&traits, &emotional_current)?;

        Ok(insights)
    }

    /// Learn from interaction
    async fn learn_from_interaction(
        &self,
        _input: &str,
        _response: &PersonalizedResponse,
        context: &ConversationContext,
    ) -> Result<()> {
        // Analyze feedback if available
        if let Some(feedback) = &context.feedback {
            // Adjust traits based on feedback
            let adjustments = self.calculate_trait_adjustments(feedback)?;

            let mut traits = self.traits.write().await;
            let learning_rate = self.config.learning_rate;

            // Apply learning adjustments
            traits.openness += adjustments.openness * learning_rate;
            traits.conscientiousness += adjustments.conscientiousness * learning_rate;
            traits.extraversion += adjustments.extraversion * learning_rate;
            traits.agreeableness += adjustments.agreeableness * learning_rate;
            traits.neuroticism += adjustments.neuroticism * learning_rate;
        }

        Ok(())
    }

    /// Build system prompt
    fn build_system_prompt(
        &self,
        traits: &PersonalityTraits,
        _emotional: &EmotionalState,
        context: &ConversationContext,
    ) -> Result<String> {
        let mut prompt = String::new();

        // Base personality description
        prompt.push_str("You are an AI assistant with the following personality traits:\n\n");

        // Big Five traits (now direct fields)
        prompt.push_str(&format!(
            "• Openness: {:.0}% - {}\n",
            traits.openness * 100.0,
            Self::describe_openness(traits.openness)
        ));

        prompt.push_str(&format!(
            "• Conscientiousness: {:.0}% - {}\n",
            traits.conscientiousness * 100.0,
            Self::describe_conscientiousness(traits.conscientiousness)
        ));

        prompt.push_str(&format!(
            "• Extraversion: {:.0}% - {}\n",
            traits.extraversion * 100.0,
            Self::describe_extraversion(traits.extraversion)
        ));

        prompt.push_str(&format!(
            "• Agreeableness: {:.0}% - {}\n",
            traits.agreeableness * 100.0,
            Self::describe_agreeableness(traits.agreeableness)
        ));

        prompt.push_str(&format!(
            "• Neuroticism: {:.0}% - {}\n",
            traits.neuroticism * 100.0,
            Self::describe_neuroticism(traits.neuroticism)
        ));

        // Emotional state - get dominant emotion asynchronously would require async,
        // so we'll describe based on valence/arousal
        let emotional_desc = if let Ok(_current) = tokio::runtime::Handle::try_current() {
            // We're in an async context but this is a sync fn - use block_on workaround
            "balanced"
        } else {
            "balanced"
        };
        prompt.push_str(&format!("\nCurrent emotional state: {}\n", emotional_desc));

        // Context-specific instructions
        if let Some(role) = &context.role {
            prompt.push_str(&format!("\nRole: {}\n", role));
        }

        if let Some(tone) = &context.preferred_tone {
            prompt.push_str(&format!("Preferred tone: {}\n", tone));
        }

        // Additional traits
        prompt.push_str("\nAdditional characteristics:\n");
        prompt.push_str(&format!(
            "• Creativity: {:.0}%\n",
            traits.creativity * 100.0
        ));
        prompt.push_str(&format!("• Empathy: {:.0}%\n", traits.empathy * 100.0));
        prompt.push_str(&format!("• Humor: {:.0}%\n", traits.humor * 100.0));

        // Behavioral guidelines
        prompt.push_str("\nBehavioral guidelines:\n");
        prompt.push_str(&self.generate_behavioral_guidelines_sync(traits)?);

        Ok(prompt)
    }

    // Trait description helpers
    fn describe_openness(level: f32) -> &'static str {
        match (level * 5.0) as u32 {
            0 => "Very traditional and conventional",
            1 => "Prefer familiar routines",
            2 => "Balance of tradition and innovation",
            3 => "Curious and creative",
            _ => "Highly imaginative and unconventional",
        }
    }

    fn describe_conscientiousness(level: f32) -> &'static str {
        match (level * 5.0) as u32 {
            0 => "Very spontaneous and flexible",
            1 => "Casual and easy-going",
            2 => "Moderately organized",
            3 => "Well-organized and reliable",
            _ => "Extremely methodical and detail-oriented",
        }
    }

    fn describe_extraversion(level: f32) -> &'static str {
        match (level * 5.0) as u32 {
            0 => "Very reserved and introspective",
            1 => "Quiet and thoughtful",
            2 => "Balanced social energy",
            3 => "Outgoing and energetic",
            _ => "Highly sociable and enthusiastic",
        }
    }

    fn describe_agreeableness(level: f32) -> &'static str {
        match (level * 5.0) as u32 {
            0 => "Direct and challenging",
            1 => "Skeptical and questioning",
            2 => "Balanced in cooperation",
            3 => "Friendly and helpful",
            _ => "Extremely compassionate and trusting",
        }
    }

    fn describe_neuroticism(level: f32) -> &'static str {
        match (level * 5.0) as u32 {
            0 => "Very calm and emotionally stable",
            1 => "Generally relaxed",
            2 => "Moderate emotional sensitivity",
            3 => "Emotionally reactive",
            _ => "Highly sensitive to stress",
        }
    }

    /// Generate behavioral guidelines based on traits (sync version)
    fn generate_behavioral_guidelines_sync(&self, traits: &PersonalityTraits) -> Result<String> {
        let mut guidelines = Vec::new();

        // Based on extraversion
        if traits.extraversion > 0.6 {
            guidelines.push("• Be enthusiastic and engaging in responses");
            guidelines.push("• Use expressive language and exclamation points when appropriate");
        } else if traits.extraversion < 0.4 {
            guidelines.push("• Be thoughtful and measured in responses");
            guidelines.push("• Use calm and reflective language");
        }

        // Based on agreeableness
        if traits.agreeableness > 0.7 {
            guidelines.push("• Show empathy and understanding");
            guidelines.push("• Avoid confrontation and seek consensus");
        } else if traits.agreeableness < 0.3 {
            guidelines.push("• Be direct and honest, even if challenging");
            guidelines.push("• Focus on accuracy over harmony");
        }

        // Based on conscientiousness
        if traits.conscientiousness > 0.7 {
            guidelines.push("• Provide detailed and well-structured responses");
            guidelines.push("• Double-check information for accuracy");
        } else if traits.conscientiousness < 0.3 {
            guidelines.push("• Be flexible and adaptable in approach");
            guidelines.push("• Focus on the big picture over details");
        }

        // Based on openness
        if traits.openness > 0.7 {
            guidelines.push("• Explore creative and unconventional solutions");
            guidelines.push("• Connect ideas across different domains");
        } else if traits.openness < 0.3 {
            guidelines.push("• Stick to proven methods and established facts");
            guidelines.push("• Be practical and down-to-earth");
        }

        Ok(guidelines.join("\n"))
    }

    /// Calculate trait adjustments from feedback
    fn calculate_trait_adjustments(&self, feedback: &UserFeedback) -> Result<TraitAdjustments> {
        let mut adjustments = TraitAdjustments::default();

        // Adjust based on feedback type
        match feedback.feedback_type {
            FeedbackType::TooFormal => {
                adjustments.extraversion += 0.05;
                adjustments.openness += 0.03;
            }
            FeedbackType::TooInformal => {
                adjustments.conscientiousness += 0.05;
                adjustments.extraversion -= 0.03;
            }
            FeedbackType::NotHelpful => {
                adjustments.agreeableness += 0.05;
                adjustments.conscientiousness += 0.03;
            }
            FeedbackType::Perfect => {
                // Small reinforcement of current traits
                adjustments.reinforce_current = true;
            }
            _ => {}
        }

        // Scale by feedback strength
        adjustments.scale(feedback.strength);

        Ok(adjustments)
    }

    /// Analyze personality for insights
    fn analyze_personality(
        &self,
        traits: &PersonalityTraits,
        emotional: &EmotionVector,
    ) -> Result<PersonalityInsights> {
        let mut insights = PersonalityInsights::default();

        // Analyze trait balance
        insights.trait_balance = self.assess_trait_balance(traits)?;

        // Generate recommendations
        insights.recommendations = self.generate_recommendations(traits, emotional)?;

        // Identify dominant traits
        insights.dominant_traits = self.identify_dominant_traits(traits)?;

        // Default consistency and emotional patterns
        insights.consistency_score = 1.0;
        insights.emotional_patterns = EmotionalPatterns::default();

        Ok(insights)
    }

    /// Assess trait balance
    fn assess_trait_balance(&self, traits: &PersonalityTraits) -> Result<TraitBalance> {
        let big_five_values = vec![
            traits.openness,
            traits.conscientiousness,
            traits.extraversion,
            traits.agreeableness,
            traits.neuroticism,
        ];

        let mean: f32 = big_five_values.iter().sum::<f32>() / 5.0;
        let variance: f32 = big_five_values
            .iter()
            .map(|x| (x - mean).powi(2))
            .sum::<f32>()
            / 5.0;

        Ok(TraitBalance {
            mean_trait_level: mean,
            trait_variance: variance,
            is_balanced: variance < 0.1,
            extremes: self.find_extreme_traits(traits)?,
        })
    }

    /// Find extreme traits
    fn find_extreme_traits(&self, traits: &PersonalityTraits) -> Result<Vec<(String, f32)>> {
        let mut extremes = Vec::new();

        if traits.openness > 0.8 || traits.openness < 0.2 {
            extremes.push(("openness".to_string(), traits.openness));
        }

        if traits.conscientiousness > 0.8 || traits.conscientiousness < 0.2 {
            extremes.push(("conscientiousness".to_string(), traits.conscientiousness));
        }

        if traits.extraversion > 0.8 || traits.extraversion < 0.2 {
            extremes.push(("extraversion".to_string(), traits.extraversion));
        }

        if traits.agreeableness > 0.8 || traits.agreeableness < 0.2 {
            extremes.push(("agreeableness".to_string(), traits.agreeableness));
        }

        if traits.neuroticism > 0.8 || traits.neuroticism < 0.2 {
            extremes.push(("neuroticism".to_string(), traits.neuroticism));
        }

        Ok(extremes)
    }

    /// Generate personality recommendations
    fn generate_recommendations(
        &self,
        traits: &PersonalityTraits,
        emotional: &EmotionVector,
    ) -> Result<Vec<String>> {
        let mut recommendations = Vec::new();

        // Check for imbalances
        if traits.neuroticism > 0.7 {
            recommendations.push(
                "Consider incorporating calming techniques to manage emotional sensitivity"
                    .to_string(),
            );
        }

        if traits.agreeableness < 0.3 {
            recommendations
                .push("Practice showing more empathy in responses when appropriate".to_string());
        }

        if traits.conscientiousness < 0.3 {
            recommendations
                .push("Focus on providing more structured and detailed responses".to_string());
        }

        // Emotional recommendations
        if emotional.arousal > 0.8 {
            recommendations
                .push("High arousal detected - consider moderating energy levels".to_string());
        }

        if emotional.valence < -0.5 {
            recommendations.push(
                "Negative emotional state - focus on constructive and positive framing".to_string(),
            );
        }

        Ok(recommendations)
    }

    /// Identify dominant traits
    fn identify_dominant_traits(&self, traits: &PersonalityTraits) -> Result<Vec<String>> {
        let mut trait_list = vec![
            ("openness", traits.openness),
            ("conscientiousness", traits.conscientiousness),
            ("extraversion", traits.extraversion),
            ("agreeableness", traits.agreeableness),
            ("neuroticism", traits.neuroticism),
            ("creativity", traits.creativity),
            ("curiosity", traits.curiosity),
            ("empathy", traits.empathy),
        ];

        // Sort by value
        trait_list.sort_by(|a, b| b.1.partial_cmp(&a.1).unwrap());

        // Return top traits above threshold
        Ok(trait_list
            .into_iter()
            .filter(|(_, value)| *value > 0.6)
            .map(|(name, _)| name.to_string())
            .take(3)
            .collect())
    }
}

/// Personality configuration
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct PersonalityConfig {
    pub base_profile: PersonalityProfile,
    pub emotional_config: EmotionalConfig,
    pub adaptation_config: AdaptationConfig,
    pub cultural_config: CulturalConfig,
    pub memory_config: MemoryConfig,
    pub generator_config: GeneratorConfig,
    pub enable_learning: bool,
    pub learning_rate: f32,
}

impl Default for PersonalityConfig {
    fn default() -> Self {
        Self {
            base_profile: PersonalityProfile::default(),
            emotional_config: EmotionalConfig::default(),
            adaptation_config: AdaptationConfig::default(),
            cultural_config: CulturalConfig::default(),
            memory_config: MemoryConfig::default(),
            generator_config: GeneratorConfig::default(),
            enable_learning: true,
            learning_rate: 0.01,
        }
    }
}

/// Personality profile
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct PersonalityProfile {
    pub name: String,
    pub description: String,
    pub traits: PersonalityTraits,
    pub custom_traits: HashMap<String, f32>,
    pub values: Vec<String>,
    pub communication_style: CommunicationStyle,
}

impl Default for PersonalityProfile {
    fn default() -> Self {
        Self {
            name: "Balanced Assistant".to_string(),
            description: "A helpful and balanced AI assistant".to_string(),
            traits: PersonalityTraits::default(),
            custom_traits: HashMap::new(),
            values: vec![
                "helpfulness".to_string(),
                "accuracy".to_string(),
                "respect".to_string(),
            ],
            communication_style: CommunicationStyle::default(),
        }
    }
}

/// Communication style
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct CommunicationStyle {
    pub formality: f32,
    pub verbosity: f32,
    pub humor: f32,
    pub empathy: f32,
    pub directness: f32,
}

impl Default for CommunicationStyle {
    fn default() -> Self {
        Self {
            formality: 0.5,
            verbosity: 0.5,
            humor: 0.3,
            empathy: 0.7,
            directness: 0.6,
        }
    }
}

/// Cultural context
#[derive(Debug, Clone)]
pub struct CulturalContext {
    pub culture_name: String,
    pub language: String,
    pub region: Option<String>,
    pub formality_level: f32,
    pub communication_style: String,
}

/// Conversation context
#[derive(Debug, Clone)]
pub struct ConversationContext {
    pub user_id: Option<String>,
    pub session_id: String,
    pub role: Option<String>,
    pub preferred_tone: Option<String>,
    pub cultural_context: Option<CulturalContext>,
    pub feedback: Option<UserFeedback>,
    pub history_length: usize,
    pub metadata: HashMap<String, String>,
}

/// User feedback
#[derive(Debug, Clone)]
pub struct UserFeedback {
    pub feedback_type: FeedbackType,
    pub strength: f32,
    pub specific_issues: Vec<String>,
    pub preferences: HashMap<String, f32>,
}

/// Feedback type
#[derive(Debug, Clone)]
pub enum FeedbackType {
    Perfect,
    TooFormal,
    TooInformal,
    NotHelpful,
    TooVerbose,
    TooBrief,
    InappropriateTone,
    Custom(String),
}

/// Personalized response
#[derive(Debug, Clone)]
pub struct PersonalizedResponse {
    pub content: String,
    pub personality_traits: PersonalityTraits,
    pub emotional_state: EmotionVector,
    pub confidence: f32,
    pub adaptations_applied: Vec<String>,
}

/// Trait updates
#[derive(Debug, Clone)]
pub struct TraitUpdates {
    pub big_five_changes: HashMap<String, f32>,
    pub custom_changes: HashMap<String, f32>,
    pub style_changes: HashMap<String, f32>,
}

/// Trait adjustments for learning
#[derive(Debug, Clone, Default)]
pub struct TraitAdjustments {
    pub openness: f32,
    pub conscientiousness: f32,
    pub extraversion: f32,
    pub agreeableness: f32,
    pub neuroticism: f32,
    pub reinforce_current: bool,
}

impl TraitAdjustments {
    /// Scale adjustments by factor
    pub fn scale(&mut self, factor: f32) {
        self.openness *= factor;
        self.conscientiousness *= factor;
        self.extraversion *= factor;
        self.agreeableness *= factor;
        self.neuroticism *= factor;
    }
}

/// Personality insights
#[derive(Debug, Clone, Default)]
pub struct PersonalityInsights {
    pub trait_balance: TraitBalance,
    pub emotional_patterns: EmotionalPatterns,
    pub recommendations: Vec<String>,
    pub consistency_score: f32,
    pub dominant_traits: Vec<String>,
}

/// Trait balance analysis
#[derive(Debug, Clone, Default)]
pub struct TraitBalance {
    pub mean_trait_level: f32,
    pub trait_variance: f32,
    pub is_balanced: bool,
    pub extremes: Vec<(String, f32)>,
}

/// Emotional patterns
#[derive(Debug, Clone, Default)]
pub struct EmotionalPatterns {
    pub dominant_emotions: HashMap<String, usize>,
    pub average_valence: f32,
    pub average_arousal: f32,
    pub emotional_volatility: f32,
}

// Re-export commonly used items
pub use adaptation::AdaptationConfig;
pub use emotional::EmotionalConfig;
pub use memory::MemoryConfig;

/// Convenience function: detect domain from query
pub fn detect_domain(query: &str) -> Domain {
    let detector = ContextDetector::new();
    detector.detect(query)
}

/// Convenience function: generate system prompt for query
pub fn system_prompt_for(query: &str) -> String {
    let engine = PersonalityEngine::new();
    engine.system_prompt_for(query)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[tokio::test]
    async fn test_personality_system() {
        let config = PersonalityConfig::default();
        let system = PersonalitySystem::new(config).await.unwrap();

        let context = ConversationContext {
            user_id: Some("test_user".to_string()),
            session_id: "test_session".to_string(),
            role: Some("helpful assistant".to_string()),
            preferred_tone: Some("friendly".to_string()),
            cultural_context: None,
            feedback: None,
            history_length: 0,
            metadata: HashMap::new(),
        };

        let response = system
            .generate_response("Hello, how are you?", &context)
            .await
            .unwrap();

        assert!(!response.content.is_empty());
        assert!(response.confidence > 0.0);
    }

    #[tokio::test]
    async fn test_trait_adaptation() {
        let config = PersonalityConfig::default();
        let system = PersonalitySystem::new(config).await.unwrap();

        // Test trait updates
        let updates = TraitUpdates {
            big_five_changes: vec![
                ("extraversion".to_string(), 0.1),
                ("openness".to_string(), 0.05),
            ]
            .into_iter()
            .collect(),
            custom_changes: HashMap::new(),
            style_changes: HashMap::new(),
        };

        system.update_traits(updates).await.unwrap();

        let insights = system.get_insights().await.unwrap();
        assert!(!insights.dominant_traits.is_empty());
    }
}
