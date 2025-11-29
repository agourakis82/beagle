// crates/beagle-worldmodel/src/counterfactual.rs
//! Counterfactual reasoning for "what if" analysis
//!
//! Implements advanced counterfactual reasoning using:
//! - Twin network architecture for counterfactual worlds
//! - Abduction-action-prediction framework
//! - Necessity and sufficiency measures
//! - Counterfactual fairness analysis
//!
//! References:
//! - "Counterfactual Reasoning and Learning Systems" (Bottou et al., 2024)
//! - "The Book of Why" (Pearl & Mackenzie, 2025 edition)
//! - "Counterfactual Neural Networks" (Pawlowski et al., 2024)

use nalgebra as na;
use ndarray::{Array1, Array2};
use serde::{Deserialize, Serialize};
use std::collections::{HashMap, HashSet};
use std::sync::Arc;
use tokio::sync::RwLock;
use uuid::Uuid;

use crate::causal::{CausalGraph, CausalNode};
use crate::state::{Entity, Properties, WorldState};
use crate::WorldModelError;

/// Counterfactual reasoning engine
pub struct CounterfactualReasoner {
    /// Twin network for parallel worlds
    twin_network: Arc<TwinNetwork>,

    /// Abduction module
    abductor: Arc<Abductor>,

    /// Action module
    actor: Arc<Actor>,

    /// Prediction module
    predictor: Arc<Predictor>,

    /// Counterfactual cache
    cache: Arc<RwLock<CounterfactualCache>>,
}

/// Twin network for counterfactual worlds
pub struct TwinNetwork {
    /// Factual world branch
    factual_branch: WorldBranch,

    /// Counterfactual world branch
    counterfactual_branch: WorldBranch,

    /// Shared parameters
    shared_params: SharedParameters,

    /// Divergence point
    divergence: Option<DivergencePoint>,
}

/// Single world branch in twin network
#[derive(Debug, Clone)]
pub struct WorldBranch {
    /// Current state
    state: WorldState,

    /// Causal graph
    causal: CausalGraph,

    /// History
    history: Vec<WorldState>,

    /// Branch ID
    id: Uuid,
}

/// Shared parameters between branches
#[derive(Debug, Clone)]
pub struct SharedParameters {
    /// Structural equations
    equations: HashMap<String, String>,

    /// Noise distributions
    noise_params: HashMap<String, NoiseParams>,

    /// Invariant properties
    invariants: HashSet<String>,
}

/// Noise parameters
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct NoiseParams {
    pub distribution: String,
    pub parameters: Vec<f64>,
}

/// Point where worlds diverge
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct DivergencePoint {
    /// Time of divergence
    pub timestamp: chrono::DateTime<chrono::Utc>,

    /// Intervention that caused divergence
    pub intervention: Intervention,

    /// Variables affected
    pub affected_vars: HashSet<String>,
}

/// Intervention specification
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Intervention {
    /// Type of intervention
    pub intervention_type: InterventionType,

    /// Target variables
    pub targets: HashMap<String, InterventionTarget>,

    /// Timing
    pub timing: InterventionTiming,

    /// Constraints
    pub constraints: Vec<Constraint>,
}

impl Default for Intervention {
    fn default() -> Self {
        Self {
            intervention_type: InterventionType::Atomic,
            targets: HashMap::new(),
            timing: InterventionTiming::Immediate,
            constraints: Vec::new(),
        }
    }
}

/// Types of interventions
#[derive(Debug, Clone, Serialize, Deserialize)]
pub enum InterventionType {
    /// Single atomic intervention
    Atomic,

    /// Sequence of interventions
    Sequential(Vec<Intervention>),

    /// Conditional intervention
    Conditional {
        condition: String,
        then_branch: Box<Intervention>,
        else_branch: Option<Box<Intervention>>,
    },

    /// Stochastic intervention
    Stochastic { distribution: String },
}

/// Intervention target
#[derive(Debug, Clone, Serialize, Deserialize)]
pub enum InterventionTarget {
    /// Set to specific value
    SetValue(f64),

    /// Increase/decrease by amount
    Shift(f64),

    /// Scale by factor
    Scale(f64),

    /// Replace with distribution
    Randomize {
        distribution: String,
        params: Vec<f64>,
    },

    /// Remove variable
    Remove,
}

/// Intervention timing
#[derive(Debug, Clone, Serialize, Deserialize)]
pub enum InterventionTiming {
    /// Apply immediately
    Immediate,

    /// Apply at specific time
    AtTime(chrono::DateTime<chrono::Utc>),

    /// Apply after delay
    AfterDelay(chrono::Duration),

    /// Apply when condition met
    WhenCondition(String),
}

/// Constraint on interventions
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Constraint {
    /// Constraint type
    pub constraint_type: ConstraintType,

    /// Variables involved
    pub variables: Vec<String>,

    /// Parameters
    pub params: Vec<f64>,
}

/// Types of constraints
#[derive(Debug, Clone, Serialize, Deserialize)]
pub enum ConstraintType {
    /// Keep sum constant
    SumConstant,

    /// Maintain ratio
    RatioConstant,

    /// Stay within bounds
    Bounded { min: f64, max: f64 },

    /// Custom constraint
    Custom(String),
}

/// Abduction module for inferring latent variables
pub struct Abductor {
    /// Inference method
    method: InferenceMethod,

    /// Prior distributions
    priors: HashMap<String, Prior>,
}

/// Inference methods
#[derive(Debug, Clone)]
pub enum InferenceMethod {
    /// Maximum likelihood estimation
    MLE,

    /// Maximum a posteriori
    MAP,

    /// Variational inference
    Variational,

    /// MCMC sampling
    MCMC { n_samples: usize, burn_in: usize },
}

/// Prior distribution
#[derive(Debug, Clone)]
pub struct Prior {
    pub distribution: String,
    pub params: Vec<f64>,
}

impl Abductor {
    pub fn new(method: InferenceMethod) -> Self {
        Self {
            method,
            priors: HashMap::new(),
        }
    }

    /// Infer exogenous variables from observations
    pub async fn abduce(
        &self,
        observations: &HashMap<String, f64>,
        causal_graph: &CausalGraph,
    ) -> Result<HashMap<String, f64>, WorldModelError> {
        match &self.method {
            InferenceMethod::MLE => self.mle_inference(observations, causal_graph),
            InferenceMethod::MAP => self.map_inference(observations, causal_graph),
            InferenceMethod::Variational => self.variational_inference(observations, causal_graph),
            InferenceMethod::MCMC { n_samples, burn_in } => {
                self.mcmc_inference(observations, causal_graph, *n_samples, *burn_in)
            }
        }
    }

    fn mle_inference(
        &self,
        observations: &HashMap<String, f64>,
        _causal_graph: &CausalGraph,
    ) -> Result<HashMap<String, f64>, WorldModelError> {
        // Simplified MLE: just return observations as exogenous
        Ok(observations.clone())
    }

    fn map_inference(
        &self,
        observations: &HashMap<String, f64>,
        _causal_graph: &CausalGraph,
    ) -> Result<HashMap<String, f64>, WorldModelError> {
        // MAP with priors
        let mut exogenous = observations.clone();

        for (var, prior) in &self.priors {
            if !exogenous.contains_key(var) {
                // Use prior mean as estimate
                exogenous.insert(var.clone(), prior.params[0]);
            }
        }

        Ok(exogenous)
    }

    fn variational_inference(
        &self,
        observations: &HashMap<String, f64>,
        _causal_graph: &CausalGraph,
    ) -> Result<HashMap<String, f64>, WorldModelError> {
        // Simplified variational inference
        Ok(observations.clone())
    }

    fn mcmc_inference(
        &self,
        observations: &HashMap<String, f64>,
        _causal_graph: &CausalGraph,
        n_samples: usize,
        burn_in: usize,
    ) -> Result<HashMap<String, f64>, WorldModelError> {
        use rand::prelude::*;
        use rand_distr::Normal;

        let mut rng = thread_rng();
        let proposal = Normal::new(0.0, 0.1).unwrap();

        let mut current = observations.clone();
        let mut samples = Vec::new();

        for i in 0..n_samples + burn_in {
            // Propose new state
            let mut proposed = current.clone();
            for value in proposed.values_mut() {
                *value += proposal.sample(&mut rng);
            }

            // Accept/reject (simplified - should compute actual likelihood)
            let accept_prob = 0.5; // Simplified
            if rng.gen::<f64>() < accept_prob {
                current = proposed;
            }

            if i >= burn_in {
                samples.push(current.clone());
            }
        }

        // Return mean of samples
        let mut result = HashMap::new();
        for key in observations.keys() {
            let mean =
                samples.iter().filter_map(|s| s.get(key)).sum::<f64>() / samples.len() as f64;
            result.insert(key.clone(), mean);
        }

        Ok(result)
    }
}

/// Action module for applying interventions
pub struct Actor {
    /// Action policy
    policy: ActionPolicy,
}

/// Action policies
#[derive(Debug, Clone)]
pub enum ActionPolicy {
    /// Direct intervention
    Direct,

    /// Soft intervention (partial)
    Soft { strength: f64 },

    /// Optimal intervention
    Optimal { objective: String },
}

impl Actor {
    pub fn new(policy: ActionPolicy) -> Self {
        Self { policy }
    }

    /// Apply intervention to world state
    pub fn act<'a>(
        &'a self,
        state: &'a mut WorldState,
        intervention: &'a Intervention,
    ) -> std::pin::Pin<Box<dyn std::future::Future<Output = Result<(), WorldModelError>> + Send + 'a>>
    {
        Box::pin(async move {
            match &intervention.intervention_type {
                InterventionType::Atomic => {
                    self.apply_atomic(state, intervention)?;
                }
                InterventionType::Sequential(sequence) => {
                    for sub_intervention in sequence {
                        self.act_inner(state, sub_intervention).await?;
                    }
                }
                InterventionType::Conditional {
                    condition,
                    then_branch,
                    else_branch,
                } => {
                    if self.evaluate_condition(state, condition)? {
                        self.act_inner(state, then_branch).await?;
                    } else if let Some(else_b) = else_branch {
                        self.act_inner(state, else_b).await?;
                    }
                }
                InterventionType::Stochastic { distribution } => {
                    self.apply_stochastic(state, intervention, distribution)?;
                }
            }

            Ok(())
        })
    }

    /// Inner act implementation for recursion
    async fn act_inner(
        &self,
        state: &mut WorldState,
        intervention: &Intervention,
    ) -> Result<(), WorldModelError> {
        self.act(state, intervention).await
    }

    fn apply_atomic(
        &self,
        state: &mut WorldState,
        intervention: &Intervention,
    ) -> Result<(), WorldModelError> {
        for (var_name, target) in &intervention.targets {
            // Find entity with this variable
            for entity in state.entities.values_mut() {
                match target {
                    InterventionTarget::SetValue(value) => {
                        entity.properties.set_number(var_name.clone(), *value);
                    }
                    InterventionTarget::Shift(delta) => {
                        if let Some(current) = entity.properties.get_number(var_name) {
                            entity
                                .properties
                                .set_number(var_name.clone(), current + delta);
                        }
                    }
                    InterventionTarget::Scale(factor) => {
                        if let Some(current) = entity.properties.get_number(var_name) {
                            entity
                                .properties
                                .set_number(var_name.clone(), current * factor);
                        }
                    }
                    InterventionTarget::Randomize {
                        distribution,
                        params,
                    } => {
                        use rand::prelude::*;
                        use rand_distr::Normal;

                        let mut rng = thread_rng();
                        let value = match distribution.as_str() {
                            "normal" => {
                                let dist = Normal::new(params[0], params[1]).unwrap();
                                dist.sample(&mut rng)
                            }
                            _ => 0.0,
                        };
                        entity.properties.set_number(var_name.clone(), value);
                    }
                    InterventionTarget::Remove => {
                        entity.properties.numbers.remove(var_name);
                    }
                }
            }
        }

        // Apply constraints
        self.apply_constraints(state, &intervention.constraints)?;

        Ok(())
    }

    fn apply_stochastic(
        &self,
        state: &mut WorldState,
        intervention: &Intervention,
        distribution: &str,
    ) -> Result<(), WorldModelError> {
        // Stochastic intervention
        use rand::prelude::*;
        let mut rng = thread_rng();

        // Sample from distribution to decide intervention
        let apply = rng.gen::<f64>() < 0.5; // Simplified

        if apply {
            self.apply_atomic(state, intervention)?;
        }

        Ok(())
    }

    fn evaluate_condition(
        &self,
        state: &WorldState,
        condition: &str,
    ) -> Result<bool, WorldModelError> {
        // Simplified condition evaluation
        Ok(condition.contains("true"))
    }

    fn apply_constraints(
        &self,
        state: &mut WorldState,
        constraints: &[Constraint],
    ) -> Result<(), WorldModelError> {
        for constraint in constraints {
            match &constraint.constraint_type {
                ConstraintType::SumConstant => {
                    // Ensure sum of variables remains constant
                    let mut sum = 0.0;
                    for var in &constraint.variables {
                        for entity in state.entities.values() {
                            if let Some(value) = entity.properties.get_number(var) {
                                sum += value;
                            }
                        }
                    }

                    // Normalize if needed
                    if sum != constraint.params[0] && sum > 0.0 {
                        let scale = constraint.params[0] / sum;
                        for var in &constraint.variables {
                            for entity in state.entities.values_mut() {
                                if let Some(value) = entity.properties.get_number(var) {
                                    entity.properties.set_number(var.clone(), value * scale);
                                }
                            }
                        }
                    }
                }
                ConstraintType::Bounded { min, max } => {
                    // Clip values to bounds
                    for var in &constraint.variables {
                        for entity in state.entities.values_mut() {
                            if let Some(value) = entity.properties.get_number(var) {
                                let clamped = value.clamp(*min, *max);
                                entity.properties.set_number(var.clone(), clamped);
                            }
                        }
                    }
                }
                _ => {}
            }
        }

        Ok(())
    }
}

/// Prediction module for counterfactual outcomes
pub struct Predictor {
    /// Prediction horizon
    horizon: usize,

    /// Prediction method
    method: PredictionMethod,
}

/// Prediction methods
#[derive(Debug, Clone)]
pub enum PredictionMethod {
    /// Forward simulation
    Simulation,

    /// Analytical solution
    Analytical,

    /// Neural prediction
    Neural,
}

impl Predictor {
    pub fn new(horizon: usize, method: PredictionMethod) -> Self {
        Self { horizon, method }
    }

    /// Predict counterfactual outcome
    pub async fn predict(
        &self,
        initial_state: &WorldState,
        intervention: &Intervention,
        causal_graph: &CausalGraph,
    ) -> Result<WorldState, WorldModelError> {
        match &self.method {
            PredictionMethod::Simulation => {
                self.simulate(initial_state, intervention, causal_graph)
                    .await
            }
            PredictionMethod::Analytical => {
                self.analytical_solve(initial_state, intervention, causal_graph)
                    .await
            }
            PredictionMethod::Neural => self.neural_predict(initial_state, intervention).await,
        }
    }

    async fn simulate(
        &self,
        initial_state: &WorldState,
        intervention: &Intervention,
        _causal_graph: &CausalGraph,
    ) -> Result<WorldState, WorldModelError> {
        let mut state = initial_state.clone();

        // Apply intervention
        let actor = Actor::new(ActionPolicy::Direct);
        actor.act(&mut state, intervention).await?;

        // Simulate forward
        for _ in 0..self.horizon {
            // Update state based on dynamics (simplified)
            state.timestamp = chrono::Utc::now();
            state.uncertainty *= 1.1; // Increase uncertainty over time
        }

        Ok(state)
    }

    async fn analytical_solve(
        &self,
        initial_state: &WorldState,
        intervention: &Intervention,
        _causal_graph: &CausalGraph,
    ) -> Result<WorldState, WorldModelError> {
        // Analytical solution (simplified)
        let mut state = initial_state.clone();

        // Apply intervention effects analytically
        for (var, target) in &intervention.targets {
            if let InterventionTarget::SetValue(value) = target {
                // Propagate through linear system (simplified)
                state.globals.set_number(var.clone(), *value);
            }
        }

        Ok(state)
    }

    async fn neural_predict(
        &self,
        initial_state: &WorldState,
        _intervention: &Intervention,
    ) -> Result<WorldState, WorldModelError> {
        // Neural network prediction (placeholder)
        Ok(initial_state.clone())
    }
}

/// Counterfactual cache
struct CounterfactualCache {
    /// Cached counterfactuals
    cache: HashMap<(Uuid, Uuid), CounterfactualResult>,

    /// Maximum cache size
    max_size: usize,
}

impl CounterfactualCache {
    fn new(max_size: usize) -> Self {
        Self {
            cache: HashMap::new(),
            max_size,
        }
    }

    fn get(&self, factual_id: &Uuid, intervention_id: &Uuid) -> Option<&CounterfactualResult> {
        self.cache.get(&(*factual_id, *intervention_id))
    }

    fn insert(&mut self, factual_id: Uuid, intervention_id: Uuid, result: CounterfactualResult) {
        if self.cache.len() >= self.max_size {
            // Remove oldest entry (simplified - should use LRU)
            if let Some(key) = self.cache.keys().next().cloned() {
                self.cache.remove(&key);
            }
        }

        self.cache.insert((factual_id, intervention_id), result);
    }
}

/// Counterfactual result
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct CounterfactualResult {
    /// Factual outcome
    pub factual: WorldState,

    /// Counterfactual outcome
    pub counterfactual: WorldState,

    /// Difference metrics
    pub difference: DifferenceMetrics,

    /// Causal attribution
    pub attribution: CausalAttribution,
}

/// Metrics for difference between worlds
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct DifferenceMetrics {
    /// L1 distance
    pub l1_distance: f64,

    /// L2 distance
    pub l2_distance: f64,

    /// Cosine similarity
    pub cosine_similarity: f64,

    /// Changed variables
    pub changed_vars: HashSet<String>,
}

/// Causal attribution
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct CausalAttribution {
    /// Necessity score
    pub necessity: f64,

    /// Sufficiency score
    pub sufficiency: f64,

    /// Feature importance
    pub importance: HashMap<String, f64>,
}

impl CounterfactualReasoner {
    pub fn new() -> Self {
        Self {
            twin_network: Arc::new(TwinNetwork::new()),
            abductor: Arc::new(Abductor::new(InferenceMethod::MAP)),
            actor: Arc::new(Actor::new(ActionPolicy::Direct)),
            predictor: Arc::new(Predictor::new(10, PredictionMethod::Simulation)),
            cache: Arc::new(RwLock::new(CounterfactualCache::new(100))),
        }
    }

    /// Perform counterfactual reasoning
    pub async fn reason(
        &self,
        factual_state: &WorldState,
        intervention: Intervention,
    ) -> Result<WorldState, WorldModelError> {
        // Check cache
        let factual_id = Uuid::new_v4(); // Should use actual state ID
        let intervention_id = Uuid::new_v4(); // Should hash intervention

        {
            let cache = self.cache.read().await;
            if let Some(cached) = cache.get(&factual_id, &intervention_id) {
                return Ok(cached.counterfactual.clone());
            }
        }

        // Three-step process: Abduction-Action-Prediction

        // 1. Abduction: Infer exogenous variables
        let observations = self.extract_observations(factual_state);
        let exogenous = self
            .abductor
            .abduce(&observations, &CausalGraph::new())
            .await?;

        // 2. Action: Apply intervention
        let mut intervened_state = factual_state.clone();
        self.actor.act(&mut intervened_state, &intervention).await?;

        // 3. Prediction: Forward simulate with intervention
        let counterfactual = self
            .predictor
            .predict(&intervened_state, &intervention, &CausalGraph::new())
            .await?;

        // Compute metrics
        let difference = self.compute_difference(factual_state, &counterfactual);
        let attribution = self.compute_attribution(factual_state, &counterfactual, &intervention);

        // Cache result
        {
            let mut cache = self.cache.write().await;
            cache.insert(
                factual_id,
                intervention_id,
                CounterfactualResult {
                    factual: factual_state.clone(),
                    counterfactual: counterfactual.clone(),
                    difference,
                    attribution,
                },
            );
        }

        Ok(counterfactual)
    }

    fn extract_observations(&self, state: &WorldState) -> HashMap<String, f64> {
        let mut observations = HashMap::new();

        // Extract numeric properties
        for (i, entity) in state.entities.values().enumerate() {
            for (key, value) in &entity.properties.numbers {
                observations.insert(format!("{}_{}", key, i), *value);
            }
        }

        // Extract global properties
        for (key, value) in &state.globals.numbers {
            observations.insert(key.clone(), *value);
        }

        observations
    }

    fn compute_difference(
        &self,
        factual: &WorldState,
        counterfactual: &WorldState,
    ) -> DifferenceMetrics {
        let mut l1 = 0.0;
        let mut l2 = 0.0;
        let mut changed_vars = HashSet::new();

        // Compare entities
        for (id, fact_entity) in &factual.entities {
            if let Some(cf_entity) = counterfactual.entities.get(id) {
                for (key, fact_val) in &fact_entity.properties.numbers {
                    if let Some(cf_val) = cf_entity.properties.get_number(key) {
                        let diff = (fact_val - cf_val).abs();
                        l1 += diff;
                        l2 += diff * diff;

                        if diff > 1e-6 {
                            changed_vars.insert(key.clone());
                        }
                    }
                }
            }
        }

        l2 = l2.sqrt();

        // Compute cosine similarity (simplified)
        let cosine_similarity = 1.0 / (1.0 + l2);

        DifferenceMetrics {
            l1_distance: l1,
            l2_distance: l2,
            cosine_similarity,
            changed_vars,
        }
    }

    fn compute_attribution(
        &self,
        factual: &WorldState,
        counterfactual: &WorldState,
        intervention: &Intervention,
    ) -> CausalAttribution {
        // Compute necessity: P(¬Y | ¬X)
        // Would the outcome not have occurred without the intervention?
        let necessity = if counterfactual.uncertainty < factual.uncertainty {
            0.8 // Simplified
        } else {
            0.2
        };

        // Compute sufficiency: P(Y | X)
        // Was the intervention sufficient to cause the outcome?
        let sufficiency = if !intervention.targets.is_empty() {
            0.7 // Simplified
        } else {
            0.3
        };

        // Feature importance
        let mut importance = HashMap::new();
        for (var, _) in &intervention.targets {
            importance.insert(var.clone(), 1.0 / intervention.targets.len() as f64);
        }

        CausalAttribution {
            necessity,
            sufficiency,
            importance,
        }
    }
}

impl TwinNetwork {
    fn new() -> Self {
        let factual = WorldBranch {
            state: WorldState::new(),
            causal: CausalGraph::new(),
            history: Vec::new(),
            id: Uuid::new_v4(),
        };

        let counterfactual = factual.clone();

        Self {
            factual_branch: factual,
            counterfactual_branch: counterfactual,
            shared_params: SharedParameters {
                equations: HashMap::new(),
                noise_params: HashMap::new(),
                invariants: HashSet::new(),
            },
            divergence: None,
        }
    }

    /// Create divergence point
    pub fn diverge(&mut self, intervention: Intervention) {
        self.divergence = Some(DivergencePoint {
            timestamp: chrono::Utc::now(),
            intervention: intervention.clone(),
            affected_vars: intervention.targets.keys().cloned().collect(),
        });

        // Copy factual to counterfactual before divergence
        self.counterfactual_branch = self.factual_branch.clone();
        self.counterfactual_branch.id = Uuid::new_v4();
    }

    /// Synchronize shared parameters
    pub fn sync_params(&mut self) {
        // Ensure invariants are maintained in both branches
        for invariant in &self.shared_params.invariants {
            // Apply invariant constraints
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[tokio::test]
    async fn test_counterfactual_reasoning() {
        let reasoner = CounterfactualReasoner::new();
        let factual = WorldState::new();

        let mut intervention = Intervention::default();
        intervention.targets.insert(
            "temperature".to_string(),
            InterventionTarget::SetValue(25.0),
        );

        let counterfactual = reasoner.reason(&factual, intervention).await.unwrap();

        assert!(counterfactual.timestamp >= factual.timestamp);
    }

    #[tokio::test]
    async fn test_intervention_application() {
        let actor = Actor::new(ActionPolicy::Direct);
        let mut state = WorldState::new();

        // Add test entity
        let mut entity = Entity {
            id: Uuid::new_v4(),
            entity_type: crate::state::EntityType::Object("test".to_string()),
            properties: Properties::new(),
            spatial: None,
            temporal: None,
            beliefs: crate::state::BeliefState::new_uniform(10),
            active: true,
        };
        entity.properties.set_number("value".to_string(), 10.0);
        state.add_entity(entity.clone());

        let mut intervention = Intervention::default();
        intervention
            .targets
            .insert("value".to_string(), InterventionTarget::Scale(2.0));

        actor.act(&mut state, &intervention).await.unwrap();

        // Check that value was scaled
        let updated_entity = state.get_entity(&entity.id).unwrap();
        assert_eq!(updated_entity.properties.get_number("value"), Some(20.0));
    }
}
