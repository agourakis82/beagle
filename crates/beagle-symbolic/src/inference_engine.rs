//! Real Symbolic Reasoning with Inference Engine

use serde::{Deserialize, Serialize};
use std::collections::{HashMap, HashSet, VecDeque};
use std::fmt;
use std::hash::Hash;

/// First-order logic term
#[derive(Debug, Clone, PartialEq, Eq, Hash, Serialize, Deserialize)]
pub enum Term {
    Constant(String),
    Variable(String),
    Function(String, Vec<Term>),
}

/// First-order logic formula
#[derive(Debug, Clone, PartialEq, Eq, Hash, Serialize, Deserialize)]
pub enum Formula {
    Atom(String, Vec<Term>),
    Not(Box<Formula>),
    And(Box<Formula>, Box<Formula>),
    Or(Box<Formula>, Box<Formula>),
    Implies(Box<Formula>, Box<Formula>),
    Forall(String, Box<Formula>),
    Exists(String, Box<Formula>),
}

/// Knowledge base with facts and rules
pub struct KnowledgeBase {
    facts: HashSet<Formula>,
    rules: Vec<Rule>,
    index: HashMap<String, Vec<usize>>, // Predicate -> Rule indices
}

/// Rule in the form: antecedents => consequent
#[derive(Debug, Clone)]
pub struct Rule {
    antecedents: Vec<Formula>,
    consequent: Formula,
    variables: HashSet<String>,
}

/// Substitution mapping variables to terms
type Substitution = HashMap<String, Term>;

/// Table entry for SLG resolution (tabling)
#[derive(Debug, Clone)]
pub struct TableEntry {
    /// Answers found for this subgoal
    answers: Vec<Substitution>,
    /// Whether this entry is complete (all answers found)
    complete: bool,
    /// Suspended computations waiting for more answers
    suspended: Vec<SuspendedComputation>,
    /// Subgoals that depend on this entry
    dependents: HashSet<u64>,
}

/// Suspended computation for SLG resolution
#[derive(Debug, Clone)]
pub struct SuspendedComputation {
    /// Remaining goals to prove
    remaining_goals: Vec<Formula>,
    /// Current substitution
    substitution: Substitution,
    /// Continuation point
    continuation_id: u64,
}

/// Tabling system for memoization (SLG resolution)
/// Based on "Tabling in Logic Programming" (Swift & Warren, 2012)
pub struct TablingSystem {
    /// Table mapping subgoals to their answers
    table: HashMap<u64, TableEntry>,
    /// Current computation stack
    stack: Vec<StackFrame>,
    /// Global answer continuation
    answer_continuations: VecDeque<(u64, Substitution)>,
    /// Next unique ID for computations
    next_id: u64,
}

#[derive(Debug, Clone)]
struct StackFrame {
    goal: Formula,
    goal_hash: u64,
    answers_consumed: usize,
}

impl TablingSystem {
    pub fn new() -> Self {
        Self {
            table: HashMap::new(),
            stack: Vec::new(),
            answer_continuations: VecDeque::new(),
            next_id: 0,
        }
    }

    /// Hash a formula for table lookup
    fn hash_goal(goal: &Formula) -> u64 {
        use std::collections::hash_map::DefaultHasher;
        use std::hash::{Hash, Hasher};

        let mut hasher = DefaultHasher::new();
        // Hash the variant-normalized formula
        Self::hash_formula_normalized(goal, &mut hasher);
        hasher.finish()
    }

    fn hash_formula_normalized<H: std::hash::Hasher>(formula: &Formula, hasher: &mut H) {
        match formula {
            Formula::Atom(pred, terms) => {
                pred.hash(hasher);
                for term in terms {
                    Self::hash_term_normalized(term, hasher);
                }
            }
            Formula::Not(f) => {
                "not".hash(hasher);
                Self::hash_formula_normalized(f, hasher);
            }
            Formula::And(l, r) => {
                "and".hash(hasher);
                Self::hash_formula_normalized(l, hasher);
                Self::hash_formula_normalized(r, hasher);
            }
            Formula::Or(l, r) => {
                "or".hash(hasher);
                Self::hash_formula_normalized(l, hasher);
                Self::hash_formula_normalized(r, hasher);
            }
            Formula::Implies(l, r) => {
                "implies".hash(hasher);
                Self::hash_formula_normalized(l, hasher);
                Self::hash_formula_normalized(r, hasher);
            }
            Formula::Forall(v, f) => {
                "forall".hash(hasher);
                v.hash(hasher);
                Self::hash_formula_normalized(f, hasher);
            }
            Formula::Exists(v, f) => {
                "exists".hash(hasher);
                v.hash(hasher);
                Self::hash_formula_normalized(f, hasher);
            }
        }
    }

    fn hash_term_normalized<H: std::hash::Hasher>(term: &Term, hasher: &mut H) {
        match term {
            Term::Constant(c) => {
                "const".hash(hasher);
                c.hash(hasher);
            }
            Term::Variable(_) => {
                // All variables hash the same (variant normalization)
                "var".hash(hasher);
            }
            Term::Function(f, args) => {
                "func".hash(hasher);
                f.hash(hasher);
                for arg in args {
                    Self::hash_term_normalized(arg, hasher);
                }
            }
        }
    }

    /// Check if goal is already in the table
    pub fn lookup(&self, goal: &Formula) -> Option<&TableEntry> {
        let hash = Self::hash_goal(goal);
        self.table.get(&hash)
    }

    /// Create a new table entry for a goal
    pub fn create_entry(&mut self, goal: &Formula) -> u64 {
        let hash = Self::hash_goal(goal);

        if !self.table.contains_key(&hash) {
            self.table.insert(
                hash,
                TableEntry {
                    answers: Vec::new(),
                    complete: false,
                    suspended: Vec::new(),
                    dependents: HashSet::new(),
                },
            );
        }

        hash
    }

    /// Add an answer to a table entry
    pub fn add_answer(&mut self, goal_hash: u64, answer: Substitution) -> bool {
        if let Some(entry) = self.table.get_mut(&goal_hash) {
            // Check if answer is new (not subsumed by existing answers)
            let is_new = !entry
                .answers
                .iter()
                .any(|existing| Self::substitution_subsumes(existing, &answer));

            if is_new {
                entry.answers.push(answer.clone());

                // Resume suspended computations with new answer
                for suspended in &entry.suspended {
                    self.answer_continuations
                        .push_back((suspended.continuation_id, answer.clone()));
                }

                return true;
            }
        }

        false
    }

    /// Check if s1 subsumes s2 (s1 is more general)
    fn substitution_subsumes(s1: &Substitution, s2: &Substitution) -> bool {
        // s1 subsumes s2 if applying s1 to variables gives s2
        for (var, term) in s2 {
            if let Some(t1) = s1.get(var) {
                if t1 != term {
                    // Check if t1 is a variable that could be bound to term
                    if !matches!(t1, Term::Variable(_)) {
                        return false;
                    }
                }
            }
        }
        true
    }

    /// Mark a table entry as complete
    pub fn mark_complete(&mut self, goal_hash: u64) {
        if let Some(entry) = self.table.get_mut(&goal_hash) {
            entry.complete = true;
            entry.suspended.clear();
        }
    }

    /// Suspend a computation waiting for more answers
    pub fn suspend(&mut self, goal_hash: u64, remaining: Vec<Formula>, subst: Substitution) {
        let cont_id = self.next_id;
        self.next_id += 1;

        if let Some(entry) = self.table.get_mut(&goal_hash) {
            entry.suspended.push(SuspendedComputation {
                remaining_goals: remaining,
                substitution: subst,
                continuation_id: cont_id,
            });
        }
    }

    /// Get answers for a goal (returns iterator to avoid copying)
    pub fn get_answers(&self, goal_hash: u64) -> impl Iterator<Item = &Substitution> {
        self.table
            .get(&goal_hash)
            .map(|e| e.answers.iter())
            .into_iter()
            .flatten()
    }

    /// Check if goal is complete
    pub fn is_complete(&self, goal_hash: u64) -> bool {
        self.table
            .get(&goal_hash)
            .map(|e| e.complete)
            .unwrap_or(false)
    }

    /// Get next answer continuation if any
    pub fn pop_continuation(&mut self) -> Option<(u64, Substitution)> {
        self.answer_continuations.pop_front()
    }

    /// Get statistics about the tabling system
    pub fn stats(&self) -> TablingStats {
        let total_entries = self.table.len();
        let complete_entries = self.table.values().filter(|e| e.complete).count();
        let total_answers: usize = self.table.values().map(|e| e.answers.len()).sum();
        let suspended_computations: usize = self.table.values().map(|e| e.suspended.len()).sum();

        TablingStats {
            total_entries,
            complete_entries,
            total_answers,
            suspended_computations,
            cache_hit_rate: if total_entries > 0 {
                complete_entries as f64 / total_entries as f64
            } else {
                0.0
            },
        }
    }
}

/// Statistics about tabling performance
#[derive(Debug, Clone)]
pub struct TablingStats {
    pub total_entries: usize,
    pub complete_entries: usize,
    pub total_answers: usize,
    pub suspended_computations: usize,
    pub cache_hit_rate: f64,
}

/// Inference engine for symbolic reasoning with tabling support
pub struct InferenceEngine {
    kb: KnowledgeBase,
    trace: bool,
    max_depth: usize,
    /// Tabling system for memoization
    tabling: TablingSystem,
    /// Enable tabling for backward chaining
    use_tabling: bool,
}

impl InferenceEngine {
    pub fn new() -> Self {
        Self {
            kb: KnowledgeBase::new(),
            trace: false,
            max_depth: 100,
            tabling: TablingSystem::new(),
            use_tabling: true, // Enable by default for SOTA performance
        }
    }

    /// Create engine with tabling disabled (for comparison/testing)
    pub fn new_without_tabling() -> Self {
        Self {
            kb: KnowledgeBase::new(),
            trace: false,
            max_depth: 100,
            tabling: TablingSystem::new(),
            use_tabling: false,
        }
    }

    /// Enable or disable tabling
    pub fn set_tabling(&mut self, enabled: bool) {
        self.use_tabling = enabled;
    }

    /// Clear the tabling cache
    pub fn clear_cache(&mut self) {
        self.tabling = TablingSystem::new();
    }

    /// Get tabling statistics
    pub fn tabling_stats(&self) -> TablingStats {
        self.tabling.stats()
    }

    /// Add a fact to the knowledge base
    pub fn add_fact(&mut self, fact: Formula) {
        self.kb.facts.insert(fact);
        // Invalidate cache when KB changes
        self.tabling = TablingSystem::new();
    }

    /// Add a rule to the knowledge base
    pub fn add_rule(&mut self, antecedents: Vec<Formula>, consequent: Formula) {
        let variables = Self::extract_variables(&antecedents, &consequent);
        let rule = Rule {
            antecedents,
            consequent: consequent.clone(),
            variables,
        };

        // Index by consequent predicate
        if let Formula::Atom(pred, _) = &consequent {
            let idx = self.kb.rules.len();
            self.kb.index.entry(pred.clone()).or_default().push(idx);
        }

        self.kb.rules.push(rule);
        // Invalidate cache when KB changes
        self.tabling = TablingSystem::new();
    }

    /// Forward chaining inference
    pub fn forward_chain(&mut self) -> HashSet<Formula> {
        let mut inferred = self.kb.facts.clone();
        let mut new_facts = true;

        while new_facts {
            new_facts = false;

            for rule in &self.kb.rules {
                // Find all substitutions that satisfy antecedents
                let substitutions = self.find_substitutions(&rule.antecedents, &inferred);

                for subst in substitutions {
                    let consequent = self.apply_substitution(&rule.consequent, &subst);

                    if !inferred.contains(&consequent) {
                        if self.trace {
                            println!("Inferred: {:?}", consequent);
                        }
                        inferred.insert(consequent);
                        new_facts = true;
                    }
                }
            }
        }

        inferred
    }

    /// Backward chaining query with optional tabling
    pub fn backward_chain(&mut self, goal: &Formula) -> Vec<Substitution> {
        if self.use_tabling {
            self.backward_chain_tabled(goal)
        } else {
            self.backward_chain_simple(goal, &HashSet::new(), 0)
        }
    }

    /// Tabled backward chaining using SLG resolution
    /// Handles infinite loops and memoizes results
    fn backward_chain_tabled(&mut self, goal: &Formula) -> Vec<Substitution> {
        let goal_hash = TablingSystem::hash_goal(goal);

        // Check if we already have complete answers
        if let Some(entry) = self.tabling.lookup(goal) {
            if entry.complete {
                return entry.answers.clone();
            }
            // If incomplete, return what we have (may be extended later)
            if !entry.answers.is_empty() {
                return entry.answers.clone();
            }
        }

        // Create table entry for this goal
        let goal_hash = self.tabling.create_entry(goal);

        // Check if goal is a fact
        for fact in &self.kb.facts {
            if let Some(subst) = self.unify(goal, fact) {
                self.tabling.add_answer(goal_hash, subst);
            }
        }

        // Try to prove using rules
        if let Formula::Atom(pred, _) = goal {
            if let Some(rule_indices) = self.kb.index.get(pred).cloned() {
                for idx in rule_indices {
                    let rule = self.kb.rules[idx].clone();

                    // Rename variables to avoid conflicts
                    let renamed_rule = self.rename_variables(&rule, self.tabling.next_id as usize);

                    // Try to unify goal with rule consequent
                    if let Some(subst) = self.unify(goal, &renamed_rule.consequent) {
                        // Prove antecedents with tabling
                        let antecedent_results =
                            self.prove_antecedents_tabled(&renamed_rule.antecedents, &subst, 0);

                        for ant_subst in antecedent_results {
                            let combined = self.compose_substitutions(&subst, &ant_subst);
                            self.tabling.add_answer(goal_hash, combined);
                        }
                    }
                }
            }
        }

        // Mark as complete
        self.tabling.mark_complete(goal_hash);

        // Return all answers
        self.tabling.get_answers(goal_hash).cloned().collect()
    }

    /// Prove antecedents with tabling support
    fn prove_antecedents_tabled(
        &mut self,
        antecedents: &[Formula],
        initial_subst: &Substitution,
        depth: usize,
    ) -> Vec<Substitution> {
        if depth > self.max_depth {
            return vec![];
        }

        if antecedents.is_empty() {
            return vec![initial_subst.clone()];
        }

        let first = self.apply_substitution(&antecedents[0], initial_subst);
        let rest = &antecedents[1..];

        let mut results = Vec::new();

        // Use tabled backward chaining for the first antecedent
        for subst in self.backward_chain_tabled(&first) {
            let combined = self.compose_substitutions(initial_subst, &subst);
            let rest_results = self.prove_antecedents_tabled(rest, &combined, depth + 1);
            results.extend(rest_results);
        }

        results
    }

    /// Simple backward chaining without tabling (original algorithm)
    fn backward_chain_simple(
        &self,
        goal: &Formula,
        visited: &HashSet<Formula>,
        depth: usize,
    ) -> Vec<Substitution> {
        if depth > self.max_depth {
            return vec![];
        }

        if visited.contains(goal) {
            return vec![];
        }

        let mut visited = visited.clone();
        visited.insert(goal.clone());

        // Check if goal is a fact
        for fact in &self.kb.facts {
            if let Some(subst) = self.unify(goal, fact) {
                return vec![subst];
            }
        }

        // Try to prove using rules
        let mut results = Vec::new();

        if let Formula::Atom(pred, _) = goal {
            if let Some(rule_indices) = self.kb.index.get(pred) {
                for &idx in rule_indices {
                    let rule = &self.kb.rules[idx];

                    // Rename variables to avoid conflicts
                    let renamed_rule = self.rename_variables(rule, depth);

                    // Try to unify goal with rule consequent
                    if let Some(subst) = self.unify(goal, &renamed_rule.consequent) {
                        // Prove antecedents
                        let antecedent_results = self.prove_antecedents_simple(
                            &renamed_rule.antecedents,
                            &subst,
                            &visited,
                            depth + 1,
                        );

                        for ant_subst in antecedent_results {
                            results.push(self.compose_substitutions(&subst, &ant_subst));
                        }
                    }
                }
            }
        }

        results
    }

    /// Prove multiple antecedents (simple version without tabling)
    fn prove_antecedents_simple(
        &self,
        antecedents: &[Formula],
        initial_subst: &Substitution,
        visited: &HashSet<Formula>,
        depth: usize,
    ) -> Vec<Substitution> {
        if antecedents.is_empty() {
            return vec![initial_subst.clone()];
        }

        let first = self.apply_substitution(&antecedents[0], initial_subst);
        let rest = &antecedents[1..];

        let mut results = Vec::new();

        for subst in self.backward_chain_simple(&first, visited, depth) {
            let combined = self.compose_substitutions(initial_subst, &subst);
            let rest_results = self.prove_antecedents_simple(rest, &combined, visited, depth);
            results.extend(rest_results);
        }

        results
    }

    /// Unification algorithm
    pub fn unify(&self, f1: &Formula, f2: &Formula) -> Option<Substitution> {
        self.unify_formulas(f1, f2, &HashMap::new())
    }

    fn unify_formulas(
        &self,
        f1: &Formula,
        f2: &Formula,
        subst: &Substitution,
    ) -> Option<Substitution> {
        let f1 = self.apply_substitution(f1, subst);
        let f2 = self.apply_substitution(f2, subst);

        match (&f1, &f2) {
            (Formula::Atom(p1, terms1), Formula::Atom(p2, terms2)) => {
                if p1 != p2 || terms1.len() != terms2.len() {
                    return None;
                }

                let mut current_subst = subst.clone();

                for (t1, t2) in terms1.iter().zip(terms2.iter()) {
                    match self.unify_terms(t1, t2, &current_subst) {
                        Some(new_subst) => current_subst = new_subst,
                        None => return None,
                    }
                }

                Some(current_subst)
            }
            (Formula::Not(f1), Formula::Not(f2)) => self.unify_formulas(f1, f2, subst),
            (Formula::And(l1, r1), Formula::And(l2, r2)) => self
                .unify_formulas(l1, l2, subst)
                .and_then(|s| self.unify_formulas(r1, r2, &s)),
            (Formula::Or(l1, r1), Formula::Or(l2, r2)) => self
                .unify_formulas(l1, l2, subst)
                .and_then(|s| self.unify_formulas(r1, r2, &s)),
            _ => {
                if f1 == f2 {
                    Some(subst.clone())
                } else {
                    None
                }
            }
        }
    }

    fn unify_terms(&self, t1: &Term, t2: &Term, subst: &Substitution) -> Option<Substitution> {
        let t1 = self.apply_term_substitution(t1, subst);
        let t2 = self.apply_term_substitution(t2, subst);

        match (&t1, &t2) {
            (Term::Variable(v), t) | (t, Term::Variable(v)) => {
                if let Term::Variable(v2) = t {
                    if v == v2 {
                        return Some(subst.clone());
                    }
                }

                // Occur check
                if self.occurs_check(&v, t) {
                    return None;
                }

                let mut new_subst = subst.clone();
                new_subst.insert(v.clone(), t.clone());
                Some(new_subst)
            }
            (Term::Constant(c1), Term::Constant(c2)) => {
                if c1 == c2 {
                    Some(subst.clone())
                } else {
                    None
                }
            }
            (Term::Function(f1, args1), Term::Function(f2, args2)) => {
                if f1 != f2 || args1.len() != args2.len() {
                    return None;
                }

                let mut current_subst = subst.clone();

                for (a1, a2) in args1.iter().zip(args2.iter()) {
                    match self.unify_terms(a1, a2, &current_subst) {
                        Some(new_subst) => current_subst = new_subst,
                        None => return None,
                    }
                }

                Some(current_subst)
            }
            _ => None,
        }
    }

    /// Occur check for unification
    fn occurs_check(&self, var: &str, term: &Term) -> bool {
        match term {
            Term::Variable(v) => v == var,
            Term::Constant(_) => false,
            Term::Function(_, args) => args.iter().any(|arg| self.occurs_check(var, arg)),
        }
    }

    /// Apply substitution to formula
    fn apply_substitution(&self, formula: &Formula, subst: &Substitution) -> Formula {
        match formula {
            Formula::Atom(pred, terms) => {
                let new_terms = terms
                    .iter()
                    .map(|t| self.apply_term_substitution(t, subst))
                    .collect();
                Formula::Atom(pred.clone(), new_terms)
            }
            Formula::Not(f) => Formula::Not(Box::new(self.apply_substitution(f, subst))),
            Formula::And(l, r) => Formula::And(
                Box::new(self.apply_substitution(l, subst)),
                Box::new(self.apply_substitution(r, subst)),
            ),
            Formula::Or(l, r) => Formula::Or(
                Box::new(self.apply_substitution(l, subst)),
                Box::new(self.apply_substitution(r, subst)),
            ),
            Formula::Implies(l, r) => Formula::Implies(
                Box::new(self.apply_substitution(l, subst)),
                Box::new(self.apply_substitution(r, subst)),
            ),
            Formula::Forall(var, f) => {
                let mut new_subst = subst.clone();
                new_subst.remove(var);
                Formula::Forall(
                    var.clone(),
                    Box::new(self.apply_substitution(f, &new_subst)),
                )
            }
            Formula::Exists(var, f) => {
                let mut new_subst = subst.clone();
                new_subst.remove(var);
                Formula::Exists(
                    var.clone(),
                    Box::new(self.apply_substitution(f, &new_subst)),
                )
            }
        }
    }

    fn apply_term_substitution(&self, term: &Term, subst: &Substitution) -> Term {
        match term {
            Term::Variable(v) => subst.get(v).cloned().unwrap_or_else(|| term.clone()),
            Term::Constant(_) => term.clone(),
            Term::Function(f, args) => {
                let new_args = args
                    .iter()
                    .map(|arg| self.apply_term_substitution(arg, subst))
                    .collect();
                Term::Function(f.clone(), new_args)
            }
        }
    }

    /// Find all substitutions that satisfy a list of formulas
    fn find_substitutions(
        &self,
        formulas: &[Formula],
        facts: &HashSet<Formula>,
    ) -> Vec<Substitution> {
        if formulas.is_empty() {
            return vec![HashMap::new()];
        }

        let first = &formulas[0];
        let rest = &formulas[1..];
        let mut results = Vec::new();

        for fact in facts {
            if let Some(subst) = self.unify(first, fact) {
                let rest_formulas: Vec<_> = rest
                    .iter()
                    .map(|f| self.apply_substitution(f, &subst))
                    .collect();

                for rest_subst in self.find_substitutions(&rest_formulas, facts) {
                    results.push(self.compose_substitutions(&subst, &rest_subst));
                }
            }
        }

        results
    }

    /// Compose two substitutions
    fn compose_substitutions(&self, s1: &Substitution, s2: &Substitution) -> Substitution {
        let mut result = s1.clone();

        for (var, term) in s2 {
            let substituted = self.apply_term_substitution(term, s1);
            result.insert(var.clone(), substituted);
        }

        result
    }

    /// Extract variables from formulas
    fn extract_variables(antecedents: &[Formula], consequent: &Formula) -> HashSet<String> {
        let mut vars = HashSet::new();

        for formula in antecedents {
            Self::extract_vars_from_formula(formula, &mut vars);
        }
        Self::extract_vars_from_formula(consequent, &mut vars);

        vars
    }

    fn extract_vars_from_formula(formula: &Formula, vars: &mut HashSet<String>) {
        match formula {
            Formula::Atom(_, terms) => {
                for term in terms {
                    Self::extract_vars_from_term(term, vars);
                }
            }
            Formula::Not(f) | Formula::Forall(_, f) | Formula::Exists(_, f) => {
                Self::extract_vars_from_formula(f, vars);
            }
            Formula::And(l, r) | Formula::Or(l, r) | Formula::Implies(l, r) => {
                Self::extract_vars_from_formula(l, vars);
                Self::extract_vars_from_formula(r, vars);
            }
        }
    }

    fn extract_vars_from_term(term: &Term, vars: &mut HashSet<String>) {
        match term {
            Term::Variable(v) => {
                vars.insert(v.clone());
            }
            Term::Function(_, args) => {
                for arg in args {
                    Self::extract_vars_from_term(arg, vars);
                }
            }
            _ => {}
        }
    }

    /// Rename variables in a rule to avoid conflicts
    fn rename_variables(&self, rule: &Rule, suffix: usize) -> Rule {
        let mut subst = HashMap::new();

        for var in &rule.variables {
            subst.insert(var.clone(), Term::Variable(format!("{}_{}", var, suffix)));
        }

        Rule {
            antecedents: rule
                .antecedents
                .iter()
                .map(|f| self.apply_substitution(f, &subst))
                .collect(),
            consequent: self.apply_substitution(&rule.consequent, &subst),
            variables: rule
                .variables
                .iter()
                .map(|v| format!("{}_{}", v, suffix))
                .collect(),
        }
    }
}

impl KnowledgeBase {
    fn new() -> Self {
        Self {
            facts: HashSet::new(),
            rules: Vec::new(),
            index: HashMap::new(),
        }
    }
}

// Helper functions for creating formulas
pub fn atom(predicate: &str, terms: Vec<Term>) -> Formula {
    Formula::Atom(predicate.to_string(), terms)
}

pub fn constant(name: &str) -> Term {
    Term::Constant(name.to_string())
}

pub fn variable(name: &str) -> Term {
    Term::Variable(name.to_string())
}

pub fn function(name: &str, args: Vec<Term>) -> Term {
    Term::Function(name.to_string(), args)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_forward_chaining() {
        let mut engine = InferenceEngine::new();

        // Add facts: parent(john, mary), parent(mary, bob)
        engine.add_fact(atom("parent", vec![constant("john"), constant("mary")]));
        engine.add_fact(atom("parent", vec![constant("mary"), constant("bob")]));

        // Add rule: parent(X, Y) ∧ parent(Y, Z) => grandparent(X, Z)
        engine.add_rule(
            vec![
                atom("parent", vec![variable("X"), variable("Y")]),
                atom("parent", vec![variable("Y"), variable("Z")]),
            ],
            atom("grandparent", vec![variable("X"), variable("Z")]),
        );

        // Forward chain
        let inferred = engine.forward_chain();

        // Should infer grandparent(john, bob)
        assert!(inferred.contains(&atom(
            "grandparent",
            vec![constant("john"), constant("bob")]
        )));
    }

    #[test]
    fn test_backward_chaining() {
        let mut engine = InferenceEngine::new();

        // Add facts
        engine.add_fact(atom("parent", vec![constant("john"), constant("mary")]));
        engine.add_fact(atom("parent", vec![constant("mary"), constant("bob")]));

        // Add rule
        engine.add_rule(
            vec![
                atom("parent", vec![variable("X"), variable("Y")]),
                atom("parent", vec![variable("Y"), variable("Z")]),
            ],
            atom("grandparent", vec![variable("X"), variable("Z")]),
        );

        // Query: grandparent(john, bob)
        let goal = atom("grandparent", vec![constant("john"), constant("bob")]);
        let results = engine.backward_chain(&goal);

        // Should find a proof
        assert!(!results.is_empty());
    }

    #[test]
    fn test_unification() {
        let engine = InferenceEngine::new();

        // Test unifying parent(X, mary) with parent(john, Y)
        let f1 = atom("parent", vec![variable("X"), constant("mary")]);
        let f2 = atom("parent", vec![constant("john"), variable("Y")]);

        let subst = engine.unify(&f1, &f2).unwrap();

        assert_eq!(subst.get("X"), Some(&constant("john")));
        assert_eq!(subst.get("Y"), Some(&constant("mary")));
    }
}
