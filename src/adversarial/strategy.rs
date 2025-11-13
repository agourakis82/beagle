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
    Aggressive,  // Bold hypotheses, high risk
    Conservative, // Safe hypotheses, incremental
    Exploratory, // Random search, novelty-seeking
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

    pub fn mutate(&self) -> Self {
        let mut new_params = self.parameters.clone();

        // Randomly adjust parameters
        for value in new_params.values_mut() {
            let delta = (rand::random::<f64>() - 0.5) * 0.2;
            *value = (*value + delta).clamp(0.0, 1.0);
        }

        Self {
            name: format!("{}_mutated", self.name),
            approach: self.approach.clone(),
            parameters: new_params,
        }
    }
}



