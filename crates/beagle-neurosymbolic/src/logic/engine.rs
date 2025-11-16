use super::{Formula, Predicate, Term, Result, LogicError};
use std::collections::{HashSet};
use tracing::{debug, info};

/// Knowledge Base (Facts + Rules)
#[derive(Debug, Clone)]
pub struct KnowledgeBase {
    /// Facts: Ground predicates
    pub facts: HashSet<Predicate>,
    /// Rules: Horn clauses (Head ← Body)
    pub rules: Vec<Rule>,
}

#[derive(Debug, Clone)]
pub struct Rule {
    pub head: Predicate,
    pub body: Vec<Predicate>,
}

impl KnowledgeBase {
    pub fn new() -> Self {
        Self {
            facts: HashSet::new(),
            rules: Vec::new(),
        }
    }

    pub fn add_fact(&mut self, fact: Predicate) {
        debug!("Adding fact: {}", fact);
        self.facts.insert(fact);
    }

    pub fn add_rule(&mut self, head: Predicate, body: Vec<Predicate>) {
        debug!("Adding rule: {} ← {:?}", head, body);
        self.rules.push(Rule { head, body });
    }

    /// Check if predicate is derivable (very simplified forward chaining)
    pub fn is_derivable(&self, query: &Predicate) -> bool {
        // Direct fact
        if self.facts.contains(query) {
            return true;
        }

        // Try rules (simple forward chaining without unification)
        for rule in &self.rules {
            if rule.head.name == query.name && rule.head.args.len() == query.args.len() {
                // Check if all body predicates are derivable as exact matches
                let all_derivable = rule.body.iter().all(|body_pred| self.facts.contains(body_pred));
                if all_derivable {
                    return true;
                }
            }
        }
        false
    }
}

/// Logic Engine (reasoning + proof)
pub struct LogicEngine {
    pub kb: KnowledgeBase,
}

impl LogicEngine {
    pub fn new() -> Self {
        Self {
            kb: KnowledgeBase::new(),
        }
    }

    pub fn with_kb(kb: KnowledgeBase) -> Self {
        Self { kb }
    }

    /// Prove formula using resolution (placeholder; supports only atomic facts/rules)
    pub fn prove(&self, formula: &Formula) -> Result<Proof> {
        info!("Attempting to prove: {}", formula);
        match formula {
            Formula::Atom(pred) => {
                if self.kb.is_derivable(pred) {
                    Ok(Proof {
                        formula: formula.clone(),
                        steps: vec![ProofStep::Fact(pred.clone())],
                        valid: true,
                    })
                } else {
                    Err(LogicError::ProofNotFound)
                }
            }
            _ => Err(LogicError::ProofNotFound),
        }
    }

    /// Validate formula against KB
    pub fn validate(&self, formula: &Formula) -> bool {
        self.prove(formula).is_ok()
    }
}

#[derive(Debug, Clone)]
pub struct Proof {
    pub formula: Formula,
    pub steps: Vec<ProofStep>,
    pub valid: bool,
}

#[derive(Debug, Clone)]
pub enum ProofStep {
    Fact(Predicate),
    Rule { head: Predicate, body: Vec<Predicate> },
    Resolution { left: Box<ProofStep>, right: Box<ProofStep> },
}

impl Proof {
    /// Generate human-readable explanation
    pub fn explain(&self) -> String {
        let mut explanation = format!("Proof of: {}\n", self.formula);
        for (i, step) in self.steps.iter().enumerate() {
            explanation.push_str(&format!("{}. {}\n", i + 1, Self::explain_step(step)));
        }
        explanation
    }

    fn explain_step(step: &ProofStep) -> String {
        match step {
            ProofStep::Fact(p) => format!("Given fact: {}", p),
            ProofStep::Rule { head, body } => {
                format!("Applied rule: {} ← {:?}", head, body)
            }
            ProofStep::Resolution { left, right } => {
                format!("Resolution: {} + {}", Self::explain_step(left), Self::explain_step(right))
            }
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_simple_fact() {
        let mut kb = KnowledgeBase::new();
        kb.add_fact(Predicate {
            name: "human".to_string(),
            args: vec![Term::Constant("socrates".to_string())],
        });
        let engine = LogicEngine::with_kb(kb);
        let query = Formula::atom("human", vec![Term::Constant("socrates".to_string())]);
        assert!(engine.validate(&query));
    }

    #[test]
    fn test_rule_currently_fails_without_unification() {
        let mut kb = KnowledgeBase::new();
        kb.add_fact(Predicate {
            name: "human".to_string(),
            args: vec![Term::Constant("socrates".to_string())],
        });
        kb.add_rule(
            Predicate {
                name: "mortal".to_string(),
                args: vec![Term::Variable("X".to_string())],
            },
            vec![Predicate {
                name: "human".to_string(),
                args: vec![Term::Variable("X".to_string())],
            }],
        );
        let engine = LogicEngine::with_kb(kb);
        let query = Formula::atom("mortal", vec![Term::Constant("socrates".to_string())]);
        assert!(!engine.validate(&query)); // Expected to fail without unification
    }
}


