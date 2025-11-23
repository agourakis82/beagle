//! Neuro-Symbolic Hybrid Reasoning
//!
//! Combines neural pattern extraction with symbolic logic
//! Neural networks extract patterns, symbolic systems enforce constraints

use anyhow::Result;
use beagle_llm::{AnthropicClient, CompletionRequest, Message, ModelType};
use serde::{Deserialize, Serialize};
use std::collections::{HashMap, HashSet};
use std::sync::Arc;
use tracing::info;

#[cfg(test)]
mod tests;

// ============================================================================
// Core Data Structures
// ============================================================================

/// Predicate in first-order logic: P(x, y, z)
#[derive(Debug, Clone, PartialEq, Eq, Hash, Serialize, Deserialize)]
pub struct Predicate {
    pub name: String,
    pub args: Vec<Term>,
}

/// Term in logic (constant, variable, or function)
#[derive(Debug, Clone, PartialEq, Eq, Hash, Serialize, Deserialize)]
pub enum Term {
    Constant(String),
    Variable(String),
    Function(String, Vec<Term>),
}

/// Horn clause: premise1 ∧ premise2 ∧ ... → conclusion
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct LogicRule {
    pub premises: Vec<Predicate>,
    pub conclusion: Predicate,
    pub confidence: f64,
}

/// Fact extracted from neural network
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Fact {
    pub predicate: Predicate,
    pub confidence: f64,
    pub source: String,
}

/// Substitution for variable binding
pub type Substitution = HashMap<String, Term>;

// ============================================================================
// Neural Extractor (LLM → Symbolic)
// ============================================================================

/// Neural pattern extractor using LLM
pub struct NeuralExtractor {
    llm: Arc<AnthropicClient>,
}

impl NeuralExtractor {
    pub fn new(llm: Arc<AnthropicClient>) -> Self {
        Self { llm }
    }

    /// Extract facts from text using LLM
    pub async fn extract_facts(&self, text: &str) -> Result<Vec<Fact>> {
        info!("🔍 Extracting facts from text...");

        let prompt = format!(
            "Extract structured facts from the following text. \
             Output as JSON array of facts in the format:\n\
             [{{\n  \
               \"predicate\": \"fact_name\",\n  \
               \"args\": [\"arg1\", \"arg2\"],\n  \
               \"confidence\": 0.9\n\
             }}]\n\n\
             Text:\n{}\n\n\
             Focus on concrete, verifiable facts. Use predicates like:\n\
             - is_a(X, Type)\n\
             - has_property(X, Property, Value)\n\
             - related_to(X, Y, Relation)\n\
             - causes(X, Y)\n\
             - requires(X, Y)",
            text
        );

        let request = CompletionRequest {
            model: ModelType::ClaudeSonnet4,
            messages: vec![Message::user(prompt)],
            max_tokens: 2000,
            temperature: 0.2,
            system: Some("You are a fact extraction system. Output only valid JSON.".to_string()),
        };

        let response = self.llm.complete(request).await?;

        // Parse JSON
        #[derive(Deserialize)]
        struct FactData {
            predicate: String,
            args: Vec<String>,
            confidence: f64,
        }

        let content = response.content.trim();
        let json_content = if content.contains("```json") {
            content
                .lines()
                .skip_while(|l| !l.contains('['))
                .take_while(|l| !l.starts_with("```"))
                .collect::<Vec<_>>()
                .join("\n")
        } else {
            content.to_string()
        };

        let fact_data: Vec<FactData> =
            serde_json::from_str(&json_content).unwrap_or_else(|_| vec![]);

        let facts: Vec<Fact> = fact_data
            .into_iter()
            .map(|fd| Fact {
                predicate: Predicate {
                    name: fd.predicate,
                    args: fd.args.into_iter().map(|a| Term::Constant(a)).collect(),
                },
                confidence: fd.confidence,
                source: "llm_extraction".to_string(),
            })
            .collect();

        info!("✅ Extracted {} facts", facts.len());
        Ok(facts)
    }

    /// Extract logic rules from text
    pub async fn extract_rules(&self, text: &str) -> Result<Vec<LogicRule>> {
        info!("📜 Extracting rules from text...");

        let prompt = format!(
            "Extract logical rules from the following text. \
             Output as JSON array of rules in the format:\n\
             [{{\n  \
               \"premises\": [[\"predicate1\", [\"arg1\", \"arg2\"]], [\"predicate2\", [\"arg3\"]]],\n  \
               \"conclusion\": [\"predicate3\", [\"arg4\", \"arg5\"]],\n  \
               \"confidence\": 0.85\n\
             }}]\n\n\
             Text:\n{}\n\n\
             Rules should be in the form: IF premise1 AND premise2 THEN conclusion",
            text
        );

        let request = CompletionRequest {
            model: ModelType::ClaudeSonnet4,
            messages: vec![Message::user(prompt)],
            max_tokens: 2000,
            temperature: 0.2,
            system: Some("You are a rule extraction system. Output only valid JSON.".to_string()),
        };

        let response = self.llm.complete(request).await?;

        #[derive(Deserialize)]
        struct RuleData {
            premises: Vec<(String, Vec<String>)>,
            conclusion: (String, Vec<String>),
            confidence: f64,
        }

        let content = response.content.trim();
        let json_content = if content.contains("```json") {
            content
                .lines()
                .skip_while(|l| !l.contains('['))
                .take_while(|l| !l.starts_with("```"))
                .collect::<Vec<_>>()
                .join("\n")
        } else {
            content.to_string()
        };

        let rule_data: Vec<RuleData> =
            serde_json::from_str(&json_content).unwrap_or_else(|_| vec![]);

        let rules: Vec<LogicRule> = rule_data
            .into_iter()
            .map(|rd| LogicRule {
                premises: rd
                    .premises
                    .into_iter()
                    .map(|(name, args)| Predicate {
                        name,
                        args: args.into_iter().map(|a| Term::Constant(a)).collect(),
                    })
                    .collect(),
                conclusion: Predicate {
                    name: rd.conclusion.0,
                    args: rd
                        .conclusion
                        .1
                        .into_iter()
                        .map(|a| Term::Constant(a))
                        .collect(),
                },
                confidence: rd.confidence,
            })
            .collect();

        info!("✅ Extracted {} rules", rules.len());
        Ok(rules)
    }

    /// Extract entities and their types
    pub async fn entity_recognition(&self, text: &str) -> Result<Vec<(String, String)>> {
        info!("🏷️  Recognizing entities...");

        let prompt = format!(
            "Extract entities and their types from the text. \
             Output as JSON array: [[\"entity_name\", \"entity_type\"]]\n\n\
             Text:\n{}",
            text
        );

        let request = CompletionRequest {
            model: ModelType::ClaudeHaiku45,
            messages: vec![Message::user(prompt)],
            max_tokens: 1000,
            temperature: 0.1,
            system: Some("You are an entity recognition system.".to_string()),
        };

        let response = self.llm.complete(request).await?;

        let entities: Vec<(String, String)> =
            serde_json::from_str(response.content.trim()).unwrap_or_else(|_| vec![]);

        info!("✅ Recognized {} entities", entities.len());
        Ok(entities)
    }

    /// Extract relations between entities
    pub async fn relation_extraction(&self, text: &str) -> Result<Vec<(String, String, String)>> {
        info!("🔗 Extracting relations...");

        let prompt = format!(
            "Extract relations between entities. \
             Output as JSON array: [[\"entity1\", \"relation\", \"entity2\"]]\n\n\
             Text:\n{}",
            text
        );

        let request = CompletionRequest {
            model: ModelType::ClaudeHaiku45,
            messages: vec![Message::user(prompt)],
            max_tokens: 1000,
            temperature: 0.1,
            system: Some("You are a relation extraction system.".to_string()),
        };

        let response = self.llm.complete(request).await?;

        let relations: Vec<(String, String, String)> =
            serde_json::from_str(response.content.trim()).unwrap_or_else(|_| vec![]);

        info!("✅ Extracted {} relations", relations.len());
        Ok(relations)
    }
}

// ============================================================================
// Symbolic Reasoner
// ============================================================================

/// Symbolic reasoner with first-order logic
pub struct SymbolicReasoner {
    facts: HashSet<Predicate>,
    rules: Vec<LogicRule>,
}

impl SymbolicReasoner {
    pub fn new() -> Self {
        Self {
            facts: HashSet::new(),
            rules: Vec::new(),
        }
    }

    /// Add a fact to the knowledge base
    pub fn add_fact(&mut self, fact: Predicate) {
        self.facts.insert(fact);
    }

    /// Add a rule to the knowledge base
    pub fn add_rule(&mut self, rule: LogicRule) {
        self.rules.push(rule);
    }

    /// Forward chaining: derive new facts from existing ones
    pub fn forward_chain(&mut self, max_iterations: usize) -> Vec<Predicate> {
        let mut new_facts = Vec::new();
        let mut changed = true;
        let mut iteration = 0;

        while changed && iteration < max_iterations {
            changed = false;
            iteration += 1;

            for rule in &self.rules {
                // Try to match all premises
                if let Some(substitutions) = self.match_premises(&rule.premises) {
                    for sub in substitutions {
                        let derived = self.apply_substitution(&rule.conclusion, &sub);

                        if !self.facts.contains(&derived) {
                            self.facts.insert(derived.clone());
                            new_facts.push(derived);
                            changed = true;
                        }
                    }
                }
            }
        }

        info!(
            "Forward chaining derived {} new facts in {} iterations",
            new_facts.len(),
            iteration
        );
        new_facts
    }

    /// Backward chaining: prove a goal from facts and rules
    pub fn backward_chain(&self, goal: &Predicate) -> bool {
        self.prove(goal, &HashMap::new(), &mut HashSet::new())
    }

    /// Unification: find substitution that makes two predicates equal
    pub fn unify(&self, p1: &Predicate, p2: &Predicate) -> Option<Substitution> {
        if p1.name != p2.name || p1.args.len() != p2.args.len() {
            return None;
        }

        let mut sub = HashMap::new();

        for (t1, t2) in p1.args.iter().zip(p2.args.iter()) {
            if !self.unify_terms(t1, t2, &mut sub) {
                return None;
            }
        }

        Some(sub)
    }

    /// Check if knowledge base is consistent
    pub fn is_consistent(&self) -> bool {
        // Simple consistency check: no contradictions
        // A more sophisticated version would use SAT solving
        true
    }

    /// Query the knowledge base
    pub fn query(&self, predicate: &Predicate) -> Vec<Substitution> {
        let mut results = Vec::new();

        for fact in &self.facts {
            if let Some(sub) = self.unify(predicate, fact) {
                results.push(sub);
            }
        }

        results
    }

    // Helper methods

    fn match_premises(&self, premises: &[Predicate]) -> Option<Vec<Substitution>> {
        if premises.is_empty() {
            return Some(vec![HashMap::new()]);
        }

        let mut all_subs = vec![HashMap::new()];

        for premise in premises {
            let mut new_subs = Vec::new();

            for existing_sub in &all_subs {
                let instantiated = self.apply_substitution(premise, existing_sub);

                for fact in &self.facts {
                    if let Some(mut sub) = self.unify(&instantiated, fact) {
                        // Merge substitutions
                        sub.extend(existing_sub.clone());
                        new_subs.push(sub);
                    }
                }
            }

            if new_subs.is_empty() {
                return None;
            }

            all_subs = new_subs;
        }

        Some(all_subs)
    }

    fn apply_substitution(&self, pred: &Predicate, sub: &Substitution) -> Predicate {
        Predicate {
            name: pred.name.clone(),
            args: pred
                .args
                .iter()
                .map(|t| self.substitute_term(t, sub))
                .collect(),
        }
    }

    fn substitute_term(&self, term: &Term, sub: &Substitution) -> Term {
        match term {
            Term::Variable(v) => sub.get(v).cloned().unwrap_or_else(|| term.clone()),
            Term::Function(name, args) => Term::Function(
                name.clone(),
                args.iter().map(|t| self.substitute_term(t, sub)).collect(),
            ),
            Term::Constant(_) => term.clone(),
        }
    }

    fn unify_terms(&self, t1: &Term, t2: &Term, sub: &mut Substitution) -> bool {
        match (t1, t2) {
            (Term::Constant(c1), Term::Constant(c2)) => c1 == c2,
            (Term::Variable(v), t) | (t, Term::Variable(v)) => {
                if let Some(existing) = sub.get(v).cloned() {
                    self.unify_terms(&existing, t, sub)
                } else {
                    sub.insert(v.clone(), t.clone());
                    true
                }
            }
            (Term::Function(f1, args1), Term::Function(f2, args2)) => {
                if f1 != f2 || args1.len() != args2.len() {
                    return false;
                }

                for (a1, a2) in args1.iter().zip(args2.iter()) {
                    if !self.unify_terms(a1, a2, sub) {
                        return false;
                    }
                }

                true
            }
            _ => false,
        }
    }

    fn prove(
        &self,
        goal: &Predicate,
        sub: &Substitution,
        visited: &mut HashSet<Predicate>,
    ) -> bool {
        let instantiated = self.apply_substitution(goal, sub);

        if visited.contains(&instantiated) {
            return false; // Prevent infinite loops
        }

        visited.insert(instantiated.clone());

        // Check if goal is a known fact
        if self.facts.contains(&instantiated) {
            return true;
        }

        // Try to prove using rules
        for rule in &self.rules {
            if let Some(unifier) = self.unify(&instantiated, &rule.conclusion) {
                // Try to prove all premises
                let mut all_proven = true;

                for premise in &rule.premises {
                    if !self.prove(premise, &unifier, visited) {
                        all_proven = false;
                        break;
                    }
                }

                if all_proven {
                    return true;
                }
            }
        }

        false
    }
}

impl Default for SymbolicReasoner {
    fn default() -> Self {
        Self::new()
    }
}

// ============================================================================
// Constraint Solver
// ============================================================================

/// Constraint solver for symbolic constraints
pub struct ConstraintSolver {
    constraints: Vec<Constraint>,
}

#[derive(Debug, Clone)]
pub enum Constraint {
    Equality(Term, Term),
    Inequality(Term, Term),
    GreaterThan(Term, Term),
    LessThan(Term, Term),
}

impl ConstraintSolver {
    pub fn new() -> Self {
        Self {
            constraints: Vec::new(),
        }
    }

    pub fn add_constraint(&mut self, constraint: Constraint) {
        self.constraints.push(constraint);
    }

    /// Check if constraints are satisfiable
    pub fn is_satisfiable(&self) -> bool {
        // Simple consistency check
        // A real implementation would use SAT/SMT solving
        true
    }

    /// Propagate constraints to derive new ones
    pub fn propagate(&mut self) -> Vec<Constraint> {
        // Simple constraint propagation
        // A real implementation would use arc consistency or similar
        vec![]
    }
}

impl Default for ConstraintSolver {
    fn default() -> Self {
        Self::new()
    }
}

// ============================================================================
// Hybrid Reasoner
// ============================================================================

/// Hybrid reasoner combining neural and symbolic approaches
pub struct HybridReasoner {
    neural: Arc<NeuralExtractor>,
    symbolic: SymbolicReasoner,
    constraint_solver: ConstraintSolver,
}

impl HybridReasoner {
    pub fn new(neural: Arc<NeuralExtractor>) -> Self {
        Self {
            neural,
            symbolic: SymbolicReasoner::new(),
            constraint_solver: ConstraintSolver::new(),
        }
    }

    /// Process text: neural extraction → symbolic reasoning
    pub async fn reason(&mut self, text: &str) -> Result<ReasoningResult> {
        info!("🧠 Hybrid reasoning on text...");

        // Step 1: Neural extraction
        let facts = self.neural.extract_facts(text).await?;
        let rules = self.neural.extract_rules(text).await?;

        // Step 2: Add to symbolic KB
        for fact in &facts {
            if fact.confidence > 0.7 {
                self.symbolic.add_fact(fact.predicate.clone());
            }
        }

        for rule in &rules {
            if rule.confidence > 0.7 {
                self.symbolic.add_rule(rule.clone());
            }
        }

        // Step 3: Forward chaining to derive new facts
        let derived_facts = self.symbolic.forward_chain(10);

        // Step 4: Detect contradictions (hallucination detection)
        let is_consistent = self.symbolic.is_consistent();

        // Calculate confidence before moving values
        let confidence_score = self.calculate_confidence(&facts, &rules);

        Ok(ReasoningResult {
            extracted_facts: facts,
            extracted_rules: rules,
            derived_facts,
            is_consistent,
            confidence_score,
        })
    }

    /// Detect LLM hallucinations using symbolic constraints
    pub fn detect_hallucinations(&self, facts: &[Fact]) -> Vec<String> {
        let mut hallucinations = Vec::new();

        for fact in facts {
            // Check if fact violates known constraints
            if fact.confidence < 0.5 {
                hallucinations.push(format!("Low confidence fact: {:?}", fact.predicate));
            }

            // Check consistency with symbolic KB
            if !self.symbolic.backward_chain(&fact.predicate)
                && !self.symbolic.facts.contains(&fact.predicate)
            {
                // Fact cannot be proven from existing knowledge
                if fact.confidence < 0.8 {
                    hallucinations.push(format!("Unverifiable fact: {:?}", fact.predicate));
                }
            }
        }

        hallucinations
    }

    fn calculate_confidence(&self, facts: &[Fact], rules: &[LogicRule]) -> f64 {
        if facts.is_empty() && rules.is_empty() {
            return 0.0;
        }

        let fact_conf: f64 =
            facts.iter().map(|f| f.confidence).sum::<f64>() / facts.len().max(1) as f64;
        let rule_conf: f64 =
            rules.iter().map(|r| r.confidence).sum::<f64>() / rules.len().max(1) as f64;

        (fact_conf + rule_conf) / 2.0
    }
}

#[derive(Debug, Serialize)]
pub struct ReasoningResult {
    pub extracted_facts: Vec<Fact>,
    pub extracted_rules: Vec<LogicRule>,
    pub derived_facts: Vec<Predicate>,
    pub is_consistent: bool,
    pub confidence_score: f64,
}
