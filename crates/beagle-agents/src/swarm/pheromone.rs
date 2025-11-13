use serde::{Deserialize, Serialize};
use std::collections::HashMap;
use uuid::Uuid;

/// Pheromone trail left by agents (stigmergy)
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Pheromone {
    pub id: Uuid,
    pub agent_id: Uuid,
    pub concept: String,
    pub strength: f64,
    pub timestamp: chrono::DateTime<chrono::Utc>,
    pub metadata: HashMap<String, String>,
}

impl Pheromone {
    pub fn new(agent_id: Uuid, concept: String, strength: f64) -> Self {
        Self {
            id: Uuid::new_v4(),
            agent_id,
            concept,
            strength,
            timestamp: chrono::Utc::now(),
            metadata: HashMap::new(),
        }
    }

    /// Evaporation over time
    pub fn evaporate(&mut self, rate: f64) {
        self.strength *= 1.0 - rate;
    }

    pub fn is_expired(&self) -> bool {
        self.strength < 0.01
    }
}

/// Field of pheromones (shared environment)
#[derive(Debug, Clone)]
pub struct PheromoneField {
    pub pheromones: Vec<Pheromone>,
    evaporation_rate: f64,
}

impl PheromoneField {
    pub fn new(evaporation_rate: f64) -> Self {
        Self {
            pheromones: Vec::new(),
            evaporation_rate,
        }
    }

    pub fn deposit(&mut self, pheromone: Pheromone) {
        self.pheromones.push(pheromone);
    }

    pub fn evaporate_all(&mut self) {
        for pheromone in &mut self.pheromones {
            pheromone.evaporate(self.evaporation_rate);
        }

        // Remove expired pheromones
        self.pheromones.retain(|p| !p.is_expired());
    }

    pub fn get_strongest_trail(&self, concept: &str) -> Option<&Pheromone> {
        self.pheromones
            .iter()
            .filter(|p| p.concept.contains(concept))
            .max_by(|a, b| a.strength.partial_cmp(&b.strength).unwrap())
    }

    pub fn get_all_for_concept(&self, concept: &str) -> Vec<&Pheromone> {
        self.pheromones
            .iter()
            .filter(|p| p.concept.contains(concept))
            .collect()
    }

    pub fn total_strength_for_concept(&self, concept: &str) -> f64 {
        self.pheromones
            .iter()
            .filter(|p| p.concept.contains(concept))
            .map(|p| p.strength)
            .sum()
    }
}
