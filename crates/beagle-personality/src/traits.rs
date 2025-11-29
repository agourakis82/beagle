use serde::{Deserialize, Serialize};
use std::collections::HashMap;

/// Big Five personality traits
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct PersonalityTraits {
    // Core Big Five traits
    pub openness: f32,          // Openness to experience
    pub conscientiousness: f32, // Organization and dependability
    pub extraversion: f32,      // Sociability and assertiveness
    pub agreeableness: f32,     // Cooperation and trust
    pub neuroticism: f32,       // Emotional instability

    // Additional traits
    pub creativity: f32,
    pub curiosity: f32,
    pub empathy: f32,
    pub assertiveness: f32,
    pub humor: f32,

    // Meta-traits
    pub adaptability: f32,
    pub resilience: f32,
    pub authenticity: f32,
}

impl Default for PersonalityTraits {
    fn default() -> Self {
        Self {
            // Neutral/balanced personality
            openness: 0.6,
            conscientiousness: 0.7,
            extraversion: 0.5,
            agreeableness: 0.7,
            neuroticism: 0.3,

            creativity: 0.6,
            curiosity: 0.7,
            empathy: 0.7,
            assertiveness: 0.5,
            humor: 0.5,

            adaptability: 0.6,
            resilience: 0.6,
            authenticity: 0.8,
        }
    }
}

impl PersonalityTraits {
    /// Create a new personality with specific traits
    pub fn new(traits: HashMap<String, f32>) -> Self {
        let mut personality = Self::default();

        for (key, value) in traits {
            match key.as_str() {
                "openness" => personality.openness = value.clamp(0.0, 1.0),
                "conscientiousness" => personality.conscientiousness = value.clamp(0.0, 1.0),
                "extraversion" => personality.extraversion = value.clamp(0.0, 1.0),
                "agreeableness" => personality.agreeableness = value.clamp(0.0, 1.0),
                "neuroticism" => personality.neuroticism = value.clamp(0.0, 1.0),
                "creativity" => personality.creativity = value.clamp(0.0, 1.0),
                "curiosity" => personality.curiosity = value.clamp(0.0, 1.0),
                "empathy" => personality.empathy = value.clamp(0.0, 1.0),
                "assertiveness" => personality.assertiveness = value.clamp(0.0, 1.0),
                "humor" => personality.humor = value.clamp(0.0, 1.0),
                "adaptability" => personality.adaptability = value.clamp(0.0, 1.0),
                "resilience" => personality.resilience = value.clamp(0.0, 1.0),
                "authenticity" => personality.authenticity = value.clamp(0.0, 1.0),
                _ => {} // Ignore unknown traits
            }
        }

        personality
    }

    /// Get a trait value by name
    pub fn get_trait(&self, name: &str) -> Option<f32> {
        match name {
            "openness" => Some(self.openness),
            "conscientiousness" => Some(self.conscientiousness),
            "extraversion" => Some(self.extraversion),
            "agreeableness" => Some(self.agreeableness),
            "neuroticism" => Some(self.neuroticism),
            "creativity" => Some(self.creativity),
            "curiosity" => Some(self.curiosity),
            "empathy" => Some(self.empathy),
            "assertiveness" => Some(self.assertiveness),
            "humor" => Some(self.humor),
            "adaptability" => Some(self.adaptability),
            "resilience" => Some(self.resilience),
            "authenticity" => Some(self.authenticity),
            _ => None,
        }
    }

    /// Set a trait value by name
    pub fn set_trait(&mut self, name: &str, value: f32) -> bool {
        let clamped = value.clamp(0.0, 1.0);

        match name {
            "openness" => {
                self.openness = clamped;
                true
            }
            "conscientiousness" => {
                self.conscientiousness = clamped;
                true
            }
            "extraversion" => {
                self.extraversion = clamped;
                true
            }
            "agreeableness" => {
                self.agreeableness = clamped;
                true
            }
            "neuroticism" => {
                self.neuroticism = clamped;
                true
            }
            "creativity" => {
                self.creativity = clamped;
                true
            }
            "curiosity" => {
                self.curiosity = clamped;
                true
            }
            "empathy" => {
                self.empathy = clamped;
                true
            }
            "assertiveness" => {
                self.assertiveness = clamped;
                true
            }
            "humor" => {
                self.humor = clamped;
                true
            }
            "adaptability" => {
                self.adaptability = clamped;
                true
            }
            "resilience" => {
                self.resilience = clamped;
                true
            }
            "authenticity" => {
                self.authenticity = clamped;
                true
            }
            _ => false,
        }
    }

    /// Apply adjustments from adaptation
    pub fn apply_adjustments(&mut self, adjustments: &[(String, f32)]) {
        for (trait_name, delta) in adjustments {
            if let Some(current) = self.get_trait(trait_name) {
                self.set_trait(trait_name, current + delta);
            }
        }
    }

    /// Calculate personality distance from another
    pub fn distance(&self, other: &PersonalityTraits) -> f32 {
        let diffs = [
            (self.openness - other.openness).powi(2),
            (self.conscientiousness - other.conscientiousness).powi(2),
            (self.extraversion - other.extraversion).powi(2),
            (self.agreeableness - other.agreeableness).powi(2),
            (self.neuroticism - other.neuroticism).powi(2),
        ];

        diffs.iter().sum::<f32>().sqrt() / 5.0_f32.sqrt()
    }

    /// Get personality archetype
    pub fn get_archetype(&self) -> String {
        // Simplified archetype detection
        if self.openness > 0.7 && self.creativity > 0.7 {
            "Creative Explorer".to_string()
        } else if self.conscientiousness > 0.8 && self.agreeableness > 0.7 {
            "Reliable Helper".to_string()
        } else if self.extraversion > 0.8 && self.assertiveness > 0.7 {
            "Natural Leader".to_string()
        } else if self.agreeableness > 0.8 && self.empathy > 0.8 {
            "Empathetic Supporter".to_string()
        } else if self.neuroticism < 0.3 && self.resilience > 0.7 {
            "Steady Rock".to_string()
        } else if self.curiosity > 0.8 && self.openness > 0.7 {
            "Knowledge Seeker".to_string()
        } else {
            "Balanced Individual".to_string()
        }
    }

    /// Convert to HashMap for serialization
    pub fn to_map(&self) -> HashMap<String, f32> {
        HashMap::from([
            ("openness".to_string(), self.openness),
            ("conscientiousness".to_string(), self.conscientiousness),
            ("extraversion".to_string(), self.extraversion),
            ("agreeableness".to_string(), self.agreeableness),
            ("neuroticism".to_string(), self.neuroticism),
            ("creativity".to_string(), self.creativity),
            ("curiosity".to_string(), self.curiosity),
            ("empathy".to_string(), self.empathy),
            ("assertiveness".to_string(), self.assertiveness),
            ("humor".to_string(), self.humor),
            ("adaptability".to_string(), self.adaptability),
            ("resilience".to_string(), self.resilience),
            ("authenticity".to_string(), self.authenticity),
        ])
    }
}

/// Predefined personality profiles
pub struct PersonalityProfiles;

impl PersonalityProfiles {
    pub fn creative() -> PersonalityTraits {
        PersonalityTraits::new(HashMap::from([
            ("openness".to_string(), 0.9),
            ("creativity".to_string(), 0.95),
            ("curiosity".to_string(), 0.85),
            ("conscientiousness".to_string(), 0.5),
            ("extraversion".to_string(), 0.6),
        ]))
    }

    pub fn analytical() -> PersonalityTraits {
        PersonalityTraits::new(HashMap::from([
            ("conscientiousness".to_string(), 0.9),
            ("openness".to_string(), 0.7),
            ("curiosity".to_string(), 0.8),
            ("neuroticism".to_string(), 0.3),
            ("assertiveness".to_string(), 0.6),
        ]))
    }

    pub fn social() -> PersonalityTraits {
        PersonalityTraits::new(HashMap::from([
            ("extraversion".to_string(), 0.9),
            ("agreeableness".to_string(), 0.85),
            ("empathy".to_string(), 0.9),
            ("humor".to_string(), 0.8),
            ("assertiveness".to_string(), 0.7),
        ]))
    }

    pub fn leader() -> PersonalityTraits {
        PersonalityTraits::new(HashMap::from([
            ("assertiveness".to_string(), 0.9),
            ("conscientiousness".to_string(), 0.85),
            ("extraversion".to_string(), 0.8),
            ("resilience".to_string(), 0.9),
            ("adaptability".to_string(), 0.8),
        ]))
    }

    pub fn helper() -> PersonalityTraits {
        PersonalityTraits::new(HashMap::from([
            ("agreeableness".to_string(), 0.95),
            ("empathy".to_string(), 0.9),
            ("conscientiousness".to_string(), 0.8),
            ("neuroticism".to_string(), 0.4),
            ("authenticity".to_string(), 0.85),
        ]))
    }
}
