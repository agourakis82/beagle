use serde::{Deserialize, Serialize};
use std::collections::HashMap;

pub use super::neural::Predicate;

/// Symbolic reasoner using logic rules
pub struct SymbolicReasoner {
    rules: Vec<LogicRule>,
    facts: Vec<Predicate>,
}

impl SymbolicReasoner {
    pub fn new() -> Self {
        Self {
            rules: Self::default_rules(),
            facts: Vec::new(),
        }
    }
    
    pub fn add_fact(&mut self, predicate: Predicate) {
        self.facts.push(predicate);
    }
    
    pub fn add_rule(&mut self, rule: LogicRule) {
        self.rules.push(rule);
    }
    
    /// Check logical consistency of facts
    pub fn check_consistency(&self) -> ConsistencyResult {
        let mut contradictions = Vec::new();
        
        // Check for direct contradictions
        for i in 0..self.facts.len() {
            for j in (i+1)..self.facts.len() {
                let fact1 = &self.facts[i];
                let fact2 = &self.facts[j];
                
                // Check if same subject-object but opposite predicates
                if fact1.subject == fact2.subject && fact1.object == fact2.object {
                    if Self::are_contradictory(&fact1.predicate, &fact2.predicate) {
                        contradictions.push((fact1.clone(), fact2.clone()));
                    }
                }
            }
        }
        
        ConsistencyResult {
            is_consistent: contradictions.is_empty(),
            contradictions,
        }
    }
    
    /// Apply inference rules to derive new facts
    pub fn infer(&self) -> Vec<Predicate> {
        let mut inferred = Vec::new();
        
        for rule in &self.rules {
            if let Some(new_fact) = rule.apply(&self.facts) {
                inferred.push(new_fact);
            }
        }
        
        inferred
    }
    
    /// Get the number of facts currently stored
    pub fn fact_count(&self) -> usize {
        self.facts.len()
    }
    
    /// Get all facts (for inspection)
    pub fn get_facts(&self) -> &[Predicate] {
        &self.facts
    }
    
    fn are_contradictory(pred1: &str, pred2: &str) -> bool {
        matches!(
            (pred1, pred2),
            ("increases", "decreases") |
            ("decreases", "increases") |
            ("causes", "prevents") |
            ("prevents", "causes") |
            ("enables", "blocks") |
            ("blocks", "enables")
        )
    }
    
    fn default_rules() -> Vec<LogicRule> {
        vec![
            // Transitivity: if A→B and B→C, then A→C
            LogicRule {
                name: "transitivity".to_string(),
                condition: "increases(X,Y) ∧ increases(Y,Z)".to_string(),
                conclusion: "increases(X,Z)".to_string(),
            },
            // Negation propagation
            LogicRule {
                name: "negation".to_string(),
                condition: "increases(X,Y) ∧ decreases(Y,Z)".to_string(),
                conclusion: "decreases(X,Z)".to_string(),
            },
        ]
    }
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct LogicRule {
    pub name: String,
    pub condition: String,
    pub conclusion: String,
}

impl LogicRule {
    pub fn apply(&self, facts: &[Predicate]) -> Option<Predicate> {
        // Simplified rule application
        // In real implementation, would use proper unification
        
        if self.name == "transitivity" {
            // Find chains: A→B, B→C
            for fact1 in facts {
                if fact1.predicate == "increases" {
                    for fact2 in facts {
                        if fact2.predicate == "increases" && fact1.object == fact2.subject {
                            // Found chain: fact1.subject → fact1.object → fact2.object
                            return Some(Predicate {
                                predicate: "increases".to_string(),
                                subject: fact1.subject.clone(),
                                object: fact2.object.clone(),
                                confidence: fact1.confidence * fact2.confidence * 0.9,
                            });
                        }
                    }
                }
            }
        }
        
        None
    }
}

#[derive(Debug, Clone)]
pub struct ConsistencyResult {
    pub is_consistent: bool,
    pub contradictions: Vec<(Predicate, Predicate)>,
}

