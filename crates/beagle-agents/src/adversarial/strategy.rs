use serde::{Deserialize, Serialize};
use std::collections::HashMap;

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Strategy {
    pub name: String,
    pub approach: ResearchApproach,
    pub parameters: HashMap<String, f64>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub enum ResearchApproach {
    Aggressive,   // Bold hypotheses, high risk
    Conservative, // Safe hypotheses, incremental
    Exploratory,  // Random search, novelty-seeking
    Exploitative, // Refine known good areas
}

impl Strategy {
    pub fn new_aggressive() -> Self {
        let mut params = HashMap::new();
        params.insert("boldness".to_string(), 0.9);
        params.insert("risk_tolerance".to_string(), 0.8);

        Self {
            name: "Aggressive".to_string(),
            approach: ResearchApproach::Aggressive,
            parameters: params,
        }
    }

    pub fn new_conservative() -> Self {
        let mut params = HashMap::new();
        params.insert("boldness".to_string(), 0.3);
        params.insert("risk_tolerance".to_string(), 0.2);

        Self {
            name: "Conservative".to_string(),
            approach: ResearchApproach::Conservative,
            parameters: params,
        }
    }

    pub fn new_exploratory() -> Self {
        let mut params = HashMap::new();
        params.insert("boldness".to_string(), 0.7);
        params.insert("novelty_seeking".to_string(), 0.9);
        params.insert("randomness".to_string(), 0.6);

        Self {
            name: "Exploratory".to_string(),
            approach: ResearchApproach::Exploratory,
            parameters: params,
        }
    }

    pub fn new_exploitative() -> Self {
        let mut params = HashMap::new();
        params.insert("boldness".to_string(), 0.5);
        params.insert("refinement".to_string(), 0.8);
        params.insert("consistency".to_string(), 0.9);

        Self {
            name: "Exploitative".to_string(),
            approach: ResearchApproach::Exploitative,
            parameters: params,
        }
    }

    /// Mutate strategy with random parameter adjustments
    pub fn mutate(&self) -> Self {
        let mut new_params = self.parameters.clone();

        // Randomly adjust parameters
        for value in new_params.values_mut() {
            let delta = (rand::random::<f64>() - 0.5) * 0.2;
            *value = (*value + delta).clamp(0.0, 1.0);
        }

        Self {
            name: format!("{}_m", self.name),
            approach: self.approach.clone(),
            parameters: new_params,
        }
    }

    /// Crossover two strategies to create offspring
    pub fn crossover(&self, other: &Strategy) -> Self {
        let mut new_params = HashMap::new();

        // Combine parameters from both parents
        for (key, &value1) in &self.parameters {
            if let Some(&value2) = other.parameters.get(key) {
                // Average or randomly pick from parents
                let combined = if rand::random::<bool>() {
                    value1
                } else {
                    value2
                };
                new_params.insert(key.clone(), combined);
            } else {
                new_params.insert(key.clone(), value1);
            }
        }

        // Add parameters from other parent not in self
        for (key, &value) in &other.parameters {
            if !new_params.contains_key(key) {
                new_params.insert(key.clone(), value);
            }
        }

        Self {
            name: format!("{}x{}", self.name, other.name),
            approach: if rand::random::<bool>() {
                self.approach.clone()
            } else {
                other.approach.clone()
            },
            parameters: new_params,
        }
    }

    /// Get fitness score based on performance
    pub fn fitness(&self, wins: usize, losses: usize) -> f64 {
        let total = wins + losses;
        if total == 0 {
            return 0.5;
        }
        wins as f64 / total as f64
    }
}
