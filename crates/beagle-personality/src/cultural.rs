use serde::{Deserialize, Serialize};
use std::collections::HashMap;
use std::sync::Arc;
use tokio::sync::RwLock;

/// Cultural adapter for personality expressions
pub struct CulturalAdapter {
    profiles: Arc<RwLock<HashMap<String, CulturalProfile>>>,
    active_culture: Arc<RwLock<String>>,
    config: CulturalConfig,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct CulturalProfile {
    pub name: String,
    pub communication_style: CommunicationStyle,
    pub value_system: HashMap<String, f32>,
    pub interaction_norms: Vec<InteractionNorm>,
    pub language_patterns: LanguagePatterns,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct CommunicationStyle {
    pub directness: f32,           // 0 = indirect, 1 = direct
    pub formality: f32,            // 0 = informal, 1 = formal
    pub emotional_expression: f32, // 0 = reserved, 1 = expressive
    pub context_sensitivity: f32,  // 0 = low context, 1 = high context
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct InteractionNorm {
    pub situation: String,
    pub appropriate_response: String,
    pub priority: f32,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct LanguagePatterns {
    pub greeting_styles: Vec<String>,
    pub politeness_markers: Vec<String>,
    pub disagreement_phrases: Vec<String>,
    pub appreciation_expressions: Vec<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct CulturalConfig {
    pub auto_detect: bool,
    pub blend_cultures: bool,
    pub adaptation_speed: f32,
}

impl Default for CulturalConfig {
    fn default() -> Self {
        Self {
            auto_detect: true,
            blend_cultures: false,
            adaptation_speed: 0.5,
        }
    }
}

impl CulturalAdapter {
    pub fn new(config: CulturalConfig) -> Self {
        let adapter = Self {
            profiles: Arc::new(RwLock::new(HashMap::new())),
            active_culture: Arc::new(RwLock::new("neutral".to_string())),
            config,
        };

        // Initialize with default profiles
        let profiles = adapter.profiles.clone();
        tokio::spawn(async move {
            let neutral = CulturalProfile {
                name: "neutral".to_string(),
                communication_style: CommunicationStyle {
                    directness: 0.5,
                    formality: 0.5,
                    emotional_expression: 0.5,
                    context_sensitivity: 0.5,
                },
                value_system: HashMap::from([
                    ("respect".to_string(), 0.8),
                    ("efficiency".to_string(), 0.7),
                    ("harmony".to_string(), 0.7),
                    ("innovation".to_string(), 0.6),
                ]),
                interaction_norms: vec![InteractionNorm {
                    situation: "greeting".to_string(),
                    appropriate_response: "Hello".to_string(),
                    priority: 1.0,
                }],
                language_patterns: LanguagePatterns {
                    greeting_styles: vec!["Hello".to_string(), "Hi".to_string()],
                    politeness_markers: vec!["please".to_string(), "thank you".to_string()],
                    disagreement_phrases: vec!["I understand, but".to_string()],
                    appreciation_expressions: vec!["Thank you".to_string()],
                },
            };

            let mut profs = profiles.write().await;
            profs.insert("neutral".to_string(), neutral);
        });

        adapter
    }

    async fn init_default_profiles(&mut self) {
        let neutral = CulturalProfile {
            name: "neutral".to_string(),
            communication_style: CommunicationStyle {
                directness: 0.5,
                formality: 0.5,
                emotional_expression: 0.5,
                context_sensitivity: 0.5,
            },
            value_system: HashMap::from([
                ("respect".to_string(), 0.8),
                ("efficiency".to_string(), 0.7),
                ("harmony".to_string(), 0.7),
                ("innovation".to_string(), 0.6),
            ]),
            interaction_norms: vec![InteractionNorm {
                situation: "greeting".to_string(),
                appropriate_response: "Hello".to_string(),
                priority: 1.0,
            }],
            language_patterns: LanguagePatterns {
                greeting_styles: vec!["Hello".to_string(), "Hi".to_string()],
                politeness_markers: vec!["please".to_string(), "thank you".to_string()],
                disagreement_phrases: vec!["I understand, but".to_string()],
                appreciation_expressions: vec!["Thank you".to_string()],
            },
        };

        let mut profiles = self.profiles.write().await;
        profiles.insert("neutral".to_string(), neutral);
    }

    pub async fn adapt_message(
        &self,
        message: &str,
        target_culture: Option<String>,
    ) -> Result<String, Box<dyn std::error::Error + Send + Sync>> {
        let culture_name = if let Some(culture) = target_culture {
            culture
        } else {
            self.active_culture.read().await.clone()
        };

        let profiles = self.profiles.read().await;
        let profile = profiles
            .get(&culture_name)
            .ok_or_else(|| format!("Cultural profile '{}' not found", culture_name))?;

        // Apply cultural adaptations
        let mut adapted = message.to_string();

        // Adjust formality
        if profile.communication_style.formality > 0.7 {
            adapted = self.add_formality_markers(&adapted);
        }

        // Adjust directness
        if profile.communication_style.directness < 0.3 {
            adapted = self.add_indirectness(&adapted);
        }

        // Add cultural markers
        for marker in &profile.language_patterns.politeness_markers {
            if !adapted.contains(marker) && rand::random::<f32>() < 0.3 {
                adapted = format!("{} {}", adapted, marker);
            }
        }

        Ok(adapted)
    }

    fn add_formality_markers(&self, text: &str) -> String {
        // Simple formality addition - in production, use NLP
        text.replace("Hi", "Greetings")
            .replace("Thanks", "Thank you")
            .replace("Yeah", "Yes")
    }

    fn add_indirectness(&self, text: &str) -> String {
        // Simple indirectness addition - in production, use NLP
        if text.starts_with("You should") {
            format!(
                "Perhaps you might consider to {}",
                text.trim_start_matches("You should")
            )
        } else if text.starts_with("Do") {
            format!("Would you mind if we {}", text.trim_start_matches("Do"))
        } else {
            text.to_string()
        }
    }

    pub async fn detect_culture(
        &self,
        context: &HashMap<String, String>,
    ) -> Result<String, Box<dyn std::error::Error + Send + Sync>> {
        // Simple culture detection based on context
        // In production, use more sophisticated methods

        if let Some(lang) = context.get("language") {
            // Map language to culture (simplified)
            match lang.as_str() {
                "en-US" => Ok("american".to_string()),
                "en-GB" => Ok("british".to_string()),
                "ja" => Ok("japanese".to_string()),
                "zh" => Ok("chinese".to_string()),
                _ => Ok("neutral".to_string()),
            }
        } else if let Some(region) = context.get("region") {
            Ok(region.to_lowercase())
        } else {
            Ok("neutral".to_string())
        }
    }

    pub async fn set_active_culture(
        &self,
        culture: String,
    ) -> Result<(), Box<dyn std::error::Error + Send + Sync>> {
        let profiles = self.profiles.read().await;
        if !profiles.contains_key(&culture) {
            return Err(format!("Cultural profile '{}' not found", culture).into());
        }

        let mut active = self.active_culture.write().await;
        *active = culture;
        Ok(())
    }

    pub async fn add_profile(
        &self,
        profile: CulturalProfile,
    ) -> Result<(), Box<dyn std::error::Error + Send + Sync>> {
        let mut profiles = self.profiles.write().await;
        profiles.insert(profile.name.clone(), profile);
        Ok(())
    }
}
