use chrono::Timelike;
use serde::{Deserialize, Serialize};
use std::collections::{HashMap, VecDeque};
use std::sync::Arc;
use tokio::sync::RwLock;

/// Adaptation engine for personality adjustments
pub struct AdaptationEngine {
    patterns: Arc<RwLock<HashMap<String, AdaptationPattern>>>,
    history: Arc<RwLock<VecDeque<AdaptationEvent>>>,
    config: AdaptationConfig,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct AdaptationPattern {
    pub name: String,
    pub trigger: TriggerCondition,
    pub adjustments: Vec<TraitAdjustment>,
    pub duration: Option<std::time::Duration>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub enum TriggerCondition {
    EmotionalState(String),
    ContextualCue(String),
    InteractionPattern(String),
    TimeOfDay(u8, u8), // hour, minute
    StressLevel(f32),
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct TraitAdjustment {
    pub trait_name: String,
    pub delta: f32,
    pub reason: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct AdaptationEvent {
    pub timestamp: chrono::DateTime<chrono::Utc>,
    pub pattern: String,
    pub adjustments: Vec<TraitAdjustment>,
    pub context: HashMap<String, String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct AdaptationConfig {
    pub max_adjustment_rate: f32,
    pub learning_rate: f32,
    pub history_limit: usize,
    pub enable_auto_adaptation: bool,
}

impl Default for AdaptationConfig {
    fn default() -> Self {
        Self {
            max_adjustment_rate: 0.1,
            learning_rate: 0.01,
            history_limit: 1000,
            enable_auto_adaptation: true,
        }
    }
}

impl AdaptationEngine {
    pub fn new(config: AdaptationConfig) -> Self {
        Self {
            patterns: Arc::new(RwLock::new(HashMap::new())),
            history: Arc::new(RwLock::new(VecDeque::new())),
            config,
        }
    }

    pub async fn adapt(
        &self,
        context: &HashMap<String, String>,
    ) -> Result<Vec<TraitAdjustment>, Box<dyn std::error::Error + Send + Sync>> {
        let patterns = self.patterns.read().await;
        let mut adjustments = Vec::new();

        for pattern in patterns.values() {
            if self.check_trigger(&pattern.trigger, context).await? {
                adjustments.extend(pattern.adjustments.clone());
            }
        }

        // Apply learning rate
        for adj in &mut adjustments {
            adj.delta *= self.config.learning_rate;
            adj.delta = adj.delta.clamp(
                -self.config.max_adjustment_rate,
                self.config.max_adjustment_rate,
            );
        }

        // Record event
        if !adjustments.is_empty() {
            let event = AdaptationEvent {
                timestamp: chrono::Utc::now(),
                pattern: "adaptive".to_string(),
                adjustments: adjustments.clone(),
                context: context.clone(),
            };

            let mut history = self.history.write().await;
            history.push_back(event);

            // Limit history size
            while history.len() > self.config.history_limit {
                history.pop_front();
            }
        }

        Ok(adjustments)
    }

    async fn check_trigger(
        &self,
        trigger: &TriggerCondition,
        context: &HashMap<String, String>,
    ) -> Result<bool, Box<dyn std::error::Error + Send + Sync>> {
        match trigger {
            TriggerCondition::EmotionalState(state) => {
                Ok(context.get("emotional_state").map_or(false, |s| s == state))
            }
            TriggerCondition::ContextualCue(cue) => {
                Ok(context.get("context").map_or(false, |c| c.contains(cue)))
            }
            TriggerCondition::InteractionPattern(pattern) => {
                Ok(context.get("interaction").map_or(false, |i| i == pattern))
            }
            TriggerCondition::TimeOfDay(hour, _minute) => {
                let now = chrono::Local::now();
                Ok(now.hour() as u8 == *hour)
            }
            TriggerCondition::StressLevel(threshold) => Ok(context
                .get("stress_level")
                .and_then(|s| s.parse::<f32>().ok())
                .map_or(false, |level| level > *threshold)),
        }
    }

    pub async fn add_pattern(
        &self,
        pattern: AdaptationPattern,
    ) -> Result<(), Box<dyn std::error::Error + Send + Sync>> {
        let mut patterns = self.patterns.write().await;
        patterns.insert(pattern.name.clone(), pattern);
        Ok(())
    }

    pub async fn get_history(&self) -> Vec<AdaptationEvent> {
        self.history.read().await.iter().cloned().collect()
    }
}
