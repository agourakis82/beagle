use super::pheromone::{Pheromone, PheromoneField};
use serde::{Deserialize, Serialize};
use std::collections::HashMap;
use uuid::Uuid;

/// Simple swarm agent with local state
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SwarmAgent {
    pub id: Uuid,
    pub beliefs: HashMap<String, f64>,
    pub energy: f64,
    pub position: (f64, f64), // Conceptual space position
}

impl SwarmAgent {
    pub fn new() -> Self {
        Self {
            id: Uuid::new_v4(),
            beliefs: HashMap::new(),
            energy: 1.0,
            position: (rand::random(), rand::random()),
        }
    }

    /// Agent explores based on pheromone trails
    pub fn explore(&mut self, field: &PheromoneField) -> Option<String> {
        // Follow strongest pheromone trail with some randomness
        if rand::random::<f64>() > 0.3 {
            // Exploitation: follow strongest trail
            if let Some(pheromone) = field
                .pheromones
                .iter()
                .max_by(|a, b| a.strength.partial_cmp(&b.strength).unwrap())
            {
                return Some(pheromone.concept.clone());
            }
        }

        // Exploration: random concept
        None
    }

    /// Update belief based on local information
    pub fn update_belief(&mut self, concept: &str, evidence: f64) {
        let current = self.beliefs.get(concept).unwrap_or(&0.5);
        let new_belief = current + (evidence - current) * 0.3;
        self.beliefs
            .insert(concept.to_string(), new_belief.clamp(0.0, 1.0));
    }

    /// Decide whether to deposit pheromone
    pub fn should_deposit(&self, concept: &str) -> bool {
        if let Some(&belief) = self.beliefs.get(concept) {
            belief > 0.6 && self.energy > 0.2
        } else {
            false
        }
    }

    /// Create pheromone trail
    pub fn deposit_pheromone(&mut self, concept: String) -> Pheromone {
        let strength = self.beliefs.get(&concept).unwrap_or(&0.5);
        self.energy -= 0.1;

        Pheromone::new(self.id, concept, *strength)
    }

    /// Consume energy
    pub fn consume_energy(&mut self, amount: f64) {
        self.energy = (self.energy - amount).max(0.0);
    }

    /// Restore energy
    pub fn restore_energy(&mut self, amount: f64) {
        self.energy = (self.energy + amount).min(1.0);
    }
}


