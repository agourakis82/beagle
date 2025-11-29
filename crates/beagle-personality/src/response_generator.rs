use serde::{Deserialize, Serialize};
use std::collections::HashMap;
use std::sync::Arc;
use tokio::sync::RwLock;

use crate::emotional::EmotionVector;
use crate::traits::PersonalityTraits;

/// Response generator for personality-driven outputs
pub struct ResponseGenerator {
    templates: Arc<RwLock<HashMap<String, ResponseTemplate>>>,
    style_modifiers: Arc<RwLock<Vec<StyleModifier>>>,
    config: GeneratorConfig,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ResponseTemplate {
    pub name: String,
    pub pattern: String,
    pub variations: Vec<String>,
    pub emotion_requirements: HashMap<String, f32>,
    pub trait_requirements: HashMap<String, f32>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct StyleModifier {
    pub name: String,
    pub condition: ModifierCondition,
    pub transformations: Vec<Transformation>,
    pub priority: i32,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub enum ModifierCondition {
    EmotionAbove(String, f32),
    EmotionBelow(String, f32),
    TraitAbove(String, f32),
    TraitBelow(String, f32),
    Always,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub enum Transformation {
    AddPrefix(String),
    AddSuffix(String),
    ReplacePattern { from: String, to: String },
    AdjustTone(ToneAdjustment),
    AddEmphasis(String),
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub enum ToneAdjustment {
    MoreFormal,
    LessFormal,
    MoreEnthusiastic,
    MoreReserved,
    MoreAssertive,
    MoreTentative,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct GeneratorConfig {
    pub creativity_level: f32,
    pub consistency_weight: f32,
    pub emotion_influence: f32,
    pub trait_influence: f32,
}

impl Default for GeneratorConfig {
    fn default() -> Self {
        Self {
            creativity_level: 0.5,
            consistency_weight: 0.7,
            emotion_influence: 0.6,
            trait_influence: 0.8,
        }
    }
}

impl ResponseGenerator {
    pub fn new(config: GeneratorConfig) -> Self {
        let generator = Self {
            templates: Arc::new(RwLock::new(HashMap::new())),
            style_modifiers: Arc::new(RwLock::new(Vec::new())),
            config,
        };

        // Initialize default templates
        let templates = generator.templates.clone();
        tokio::spawn(async move {
            let default_templates = vec![
                ResponseTemplate {
                    name: "greeting".to_string(),
                    pattern: "Hello {name}".to_string(),
                    variations: vec![
                        "Hi {name}!".to_string(),
                        "Hey {name}".to_string(),
                        "Greetings, {name}".to_string(),
                    ],
                    emotion_requirements: HashMap::from([("joy".to_string(), 0.3)]),
                    trait_requirements: HashMap::from([("extraversion".to_string(), 0.4)]),
                },
                ResponseTemplate {
                    name: "agreement".to_string(),
                    pattern: "I agree".to_string(),
                    variations: vec![
                        "Absolutely!".to_string(),
                        "I think so too".to_string(),
                        "That makes sense".to_string(),
                        "You're right".to_string(),
                    ],
                    emotion_requirements: HashMap::new(),
                    trait_requirements: HashMap::from([("agreeableness".to_string(), 0.5)]),
                },
                ResponseTemplate {
                    name: "disagreement".to_string(),
                    pattern: "I see it differently".to_string(),
                    variations: vec![
                        "I'm not so sure about that".to_string(),
                        "Actually, I think...".to_string(),
                        "I have a different perspective".to_string(),
                    ],
                    emotion_requirements: HashMap::new(),
                    trait_requirements: HashMap::from([("openness".to_string(), 0.6)]),
                },
            ];

            let mut stored_templates = templates.write().await;
            for template in default_templates {
                stored_templates.insert(template.name.clone(), template);
            }
        });

        generator
    }

    pub async fn generate(
        &self,
        intent: &str,
        context: &HashMap<String, String>,
        traits: &PersonalityTraits,
        emotions: &EmotionVector,
    ) -> Result<String, Box<dyn std::error::Error + Send + Sync>> {
        // Select appropriate template
        let template = self.select_template(intent, traits, emotions).await?;

        // Generate base response
        let mut response = self.apply_template(&template, context).await;

        // Apply style modifiers
        response = self.apply_modifiers(response, traits, emotions).await?;

        // Apply personality-specific adjustments
        response = self
            .apply_personality_style(response, traits, emotions)
            .await;

        Ok(response)
    }

    async fn select_template(
        &self,
        intent: &str,
        traits: &PersonalityTraits,
        emotions: &EmotionVector,
    ) -> Result<ResponseTemplate, Box<dyn std::error::Error + Send + Sync>> {
        let templates = self.templates.read().await;

        // Find matching template
        if let Some(template) = templates.get(intent) {
            // Check if personality matches requirements
            if self.matches_requirements(template, traits, emotions) {
                return Ok(template.clone());
            }
        }

        // Fallback to default template
        Ok(ResponseTemplate {
            name: "default".to_string(),
            pattern: "{message}".to_string(),
            variations: vec![],
            emotion_requirements: HashMap::new(),
            trait_requirements: HashMap::new(),
        })
    }

    fn matches_requirements(
        &self,
        template: &ResponseTemplate,
        traits: &PersonalityTraits,
        emotions: &EmotionVector,
    ) -> bool {
        // Check emotion requirements
        for (emotion, threshold) in &template.emotion_requirements {
            let value = match emotion.as_str() {
                "joy" => emotions.joy,
                "fear" => emotions.fear,
                "anger" => emotions.anger,
                "sadness" => emotions.sadness,
                _ => 0.0,
            };

            if value < *threshold {
                return false;
            }
        }

        // Check trait requirements
        for (trait_name, threshold) in &template.trait_requirements {
            let value = match trait_name.as_str() {
                "openness" => traits.openness,
                "conscientiousness" => traits.conscientiousness,
                "extraversion" => traits.extraversion,
                "agreeableness" => traits.agreeableness,
                "neuroticism" => traits.neuroticism,
                _ => 0.0,
            };

            if value < *threshold {
                return false;
            }
        }

        true
    }

    async fn apply_template(
        &self,
        template: &ResponseTemplate,
        context: &HashMap<String, String>,
    ) -> String {
        // Select variation based on creativity level
        let text = if !template.variations.is_empty()
            && rand::random::<f32>() < self.config.creativity_level
        {
            let idx = (rand::random::<f32>() * template.variations.len() as f32) as usize;
            &template.variations[idx.min(template.variations.len() - 1)]
        } else {
            &template.pattern
        };

        // Replace placeholders
        let mut result = text.clone();
        for (key, value) in context {
            result = result.replace(&format!("{{{}}}", key), value);
        }

        result
    }

    async fn apply_modifiers(
        &self,
        mut response: String,
        traits: &PersonalityTraits,
        emotions: &EmotionVector,
    ) -> Result<String, Box<dyn std::error::Error + Send + Sync>> {
        let modifiers = self.style_modifiers.read().await;

        // Sort by priority
        let mut applicable_modifiers: Vec<_> = modifiers
            .iter()
            .filter(|m| self.check_modifier_condition(&m.condition, traits, emotions))
            .collect();

        applicable_modifiers.sort_by_key(|m| -m.priority);

        // Apply transformations
        for modifier in applicable_modifiers {
            for transformation in &modifier.transformations {
                response = self.apply_transformation(response, transformation).await;
            }
        }

        Ok(response)
    }

    fn check_modifier_condition(
        &self,
        condition: &ModifierCondition,
        traits: &PersonalityTraits,
        emotions: &EmotionVector,
    ) -> bool {
        match condition {
            ModifierCondition::EmotionAbove(emotion, threshold) => {
                let value = match emotion.as_str() {
                    "joy" => emotions.joy,
                    "fear" => emotions.fear,
                    "anger" => emotions.anger,
                    _ => 0.0,
                };
                value > *threshold
            }
            ModifierCondition::EmotionBelow(emotion, threshold) => {
                let value = match emotion.as_str() {
                    "joy" => emotions.joy,
                    "fear" => emotions.fear,
                    "anger" => emotions.anger,
                    _ => 0.0,
                };
                value < *threshold
            }
            ModifierCondition::TraitAbove(trait_name, threshold) => {
                let value = match trait_name.as_str() {
                    "openness" => traits.openness,
                    "conscientiousness" => traits.conscientiousness,
                    "extraversion" => traits.extraversion,
                    "agreeableness" => traits.agreeableness,
                    "neuroticism" => traits.neuroticism,
                    _ => 0.0,
                };
                value > *threshold
            }
            ModifierCondition::TraitBelow(trait_name, threshold) => {
                let value = match trait_name.as_str() {
                    "openness" => traits.openness,
                    "conscientiousness" => traits.conscientiousness,
                    "extraversion" => traits.extraversion,
                    "agreeableness" => traits.agreeableness,
                    "neuroticism" => traits.neuroticism,
                    _ => 0.0,
                };
                value < *threshold
            }
            ModifierCondition::Always => true,
        }
    }

    async fn apply_transformation(&self, text: String, transformation: &Transformation) -> String {
        match transformation {
            Transformation::AddPrefix(prefix) => format!("{} {}", prefix, text),
            Transformation::AddSuffix(suffix) => format!("{} {}", text, suffix),
            Transformation::ReplacePattern { from, to } => text.replace(from, to),
            Transformation::AdjustTone(adjustment) => self.adjust_tone(text, adjustment),
            Transformation::AddEmphasis(word) => text.replace(word, &format!("**{}**", word)),
        }
    }

    fn adjust_tone(&self, text: String, adjustment: &ToneAdjustment) -> String {
        match adjustment {
            ToneAdjustment::MoreFormal => text
                .replace("Hi", "Hello")
                .replace("Thanks", "Thank you")
                .replace("Yeah", "Yes"),
            ToneAdjustment::LessFormal => text
                .replace("Hello", "Hi")
                .replace("Thank you", "Thanks")
                .replace("Yes", "Yeah"),
            ToneAdjustment::MoreEnthusiastic => format!("{}!", text.trim_end_matches('!')),
            ToneAdjustment::MoreReserved => text.replace("!", "."),
            ToneAdjustment::MoreAssertive => text
                .replace("I think", "I know")
                .replace("maybe", "definitely"),
            ToneAdjustment::MoreTentative => text
                .replace("I know", "I think")
                .replace("definitely", "perhaps"),
        }
    }

    async fn apply_personality_style(
        &self,
        mut response: String,
        traits: &PersonalityTraits,
        emotions: &EmotionVector,
    ) -> String {
        // Apply trait-based modifications
        if traits.extraversion > 0.7 {
            response = format!("{} 😊", response);
        }

        if traits.conscientiousness > 0.8 {
            response = response.replace("probably", "certainly");
        }

        if traits.neuroticism > 0.6 && emotions.fear > 0.4 {
            response = format!("{}, but I'm a bit concerned...", response);
        }

        if traits.agreeableness > 0.8 {
            if !response.contains("please") && rand::random::<f32>() < 0.3 {
                response = format!("Please, {}", response.to_lowercase());
            }
        }

        response
    }
}
