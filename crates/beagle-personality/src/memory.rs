use serde::{Deserialize, Serialize};
use std::collections::{HashMap, VecDeque};
use std::sync::Arc;
use tokio::sync::RwLock;

/// Memory system for personality context
pub struct PersonalityMemory {
    interactions: Arc<RwLock<VecDeque<Interaction>>>,
    relationships: Arc<RwLock<HashMap<String, Relationship>>>,
    preferences: Arc<RwLock<HashMap<String, Preference>>>,
    config: MemoryConfig,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Interaction {
    pub id: String,
    pub timestamp: chrono::DateTime<chrono::Utc>,
    pub participant: String,
    pub content: String,
    pub emotional_context: HashMap<String, f32>,
    pub outcome: InteractionOutcome,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub enum InteractionOutcome {
    Positive,
    Negative,
    Neutral,
    Mixed,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Relationship {
    pub entity_id: String,
    pub trust_level: f32,
    pub familiarity: f32,
    pub interaction_count: usize,
    pub last_interaction: chrono::DateTime<chrono::Utc>,
    pub emotional_association: HashMap<String, f32>,
    pub notes: Vec<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Preference {
    pub category: String,
    pub value: String,
    pub strength: f32,
    pub learned_from: Vec<String>,
    pub last_updated: chrono::DateTime<chrono::Utc>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct MemoryConfig {
    pub max_interactions: usize,
    pub relationship_decay_rate: f32,
    pub preference_learning_rate: f32,
    pub consolidation_interval: std::time::Duration,
}

impl Default for MemoryConfig {
    fn default() -> Self {
        Self {
            max_interactions: 10000,
            relationship_decay_rate: 0.01,
            preference_learning_rate: 0.1,
            consolidation_interval: std::time::Duration::from_secs(3600),
        }
    }
}

impl PersonalityMemory {
    pub fn new(config: MemoryConfig) -> Self {
        Self {
            interactions: Arc::new(RwLock::new(VecDeque::new())),
            relationships: Arc::new(RwLock::new(HashMap::new())),
            preferences: Arc::new(RwLock::new(HashMap::new())),
            config,
        }
    }

    pub async fn record_interaction(
        &self,
        interaction: Interaction,
    ) -> Result<(), Box<dyn std::error::Error + Send + Sync>> {
        let mut interactions = self.interactions.write().await;

        // Add new interaction
        interactions.push_back(interaction.clone());

        // Limit size
        while interactions.len() > self.config.max_interactions {
            interactions.pop_front();
        }

        // Update relationship
        self.update_relationship(&interaction).await?;

        Ok(())
    }

    async fn update_relationship(
        &self,
        interaction: &Interaction,
    ) -> Result<(), Box<dyn std::error::Error + Send + Sync>> {
        let mut relationships = self.relationships.write().await;

        let relationship = relationships
            .entry(interaction.participant.clone())
            .or_insert_with(|| Relationship {
                entity_id: interaction.participant.clone(),
                trust_level: 0.5,
                familiarity: 0.0,
                interaction_count: 0,
                last_interaction: interaction.timestamp,
                emotional_association: HashMap::new(),
                notes: Vec::new(),
            });

        // Update relationship metrics
        relationship.interaction_count += 1;
        relationship.last_interaction = interaction.timestamp;
        relationship.familiarity = (relationship.familiarity + 0.1).min(1.0);

        // Update trust based on outcome
        match interaction.outcome {
            InteractionOutcome::Positive => {
                relationship.trust_level = (relationship.trust_level + 0.05).min(1.0);
            }
            InteractionOutcome::Negative => {
                relationship.trust_level = (relationship.trust_level - 0.1).max(0.0);
            }
            _ => {}
        }

        // Update emotional associations
        for (emotion, value) in &interaction.emotional_context {
            let current = relationship
                .emotional_association
                .entry(emotion.clone())
                .or_insert(0.0);
            *current = (*current * 0.9 + value * 0.1).clamp(-1.0, 1.0);
        }

        Ok(())
    }

    pub async fn learn_preference(
        &self,
        category: String,
        value: String,
        context: String,
    ) -> Result<(), Box<dyn std::error::Error + Send + Sync>> {
        let mut preferences = self.preferences.write().await;

        let key = format!("{}:{}", category, value);
        let preference = preferences
            .entry(key.clone())
            .or_insert_with(|| Preference {
                category: category.clone(),
                value: value.clone(),
                strength: 0.0,
                learned_from: Vec::new(),
                last_updated: chrono::Utc::now(),
            });

        // Update preference strength
        preference.strength = (preference.strength + self.config.preference_learning_rate).min(1.0);
        preference.learned_from.push(context);
        preference.last_updated = chrono::Utc::now();

        // Limit learned_from history
        if preference.learned_from.len() > 100 {
            preference
                .learned_from
                .drain(0..preference.learned_from.len() - 100);
        }

        Ok(())
    }

    pub async fn get_relationship(&self, entity_id: &str) -> Option<Relationship> {
        self.relationships.read().await.get(entity_id).cloned()
    }

    pub async fn get_preferences_for_category(&self, category: &str) -> Vec<Preference> {
        self.preferences
            .read()
            .await
            .values()
            .filter(|p| p.category == category)
            .cloned()
            .collect()
    }

    pub async fn get_recent_interactions(&self, limit: usize) -> Vec<Interaction> {
        let interactions = self.interactions.read().await;
        interactions.iter().rev().take(limit).cloned().collect()
    }

    pub async fn consolidate_memory(&self) -> Result<(), Box<dyn std::error::Error + Send + Sync>> {
        // Apply decay to relationships
        let mut relationships = self.relationships.write().await;
        let now = chrono::Utc::now();

        for relationship in relationships.values_mut() {
            let days_since = (now - relationship.last_interaction).num_days() as f32;
            let decay = self.config.relationship_decay_rate * days_since;

            relationship.familiarity = (relationship.familiarity - decay).max(0.0);
            relationship.trust_level = (relationship.trust_level - decay * 0.5).max(0.0);
        }

        // Remove very old or weak preferences
        let mut preferences = self.preferences.write().await;
        preferences.retain(|_, pref| {
            let days_old = (now - pref.last_updated).num_days();
            days_old < 365 && pref.strength > 0.1
        });

        Ok(())
    }

    pub async fn search_interactions(&self, query: &str) -> Vec<Interaction> {
        let interactions = self.interactions.read().await;
        interactions
            .iter()
            .filter(|i| i.content.contains(query) || i.participant.contains(query))
            .cloned()
            .collect()
    }
}
