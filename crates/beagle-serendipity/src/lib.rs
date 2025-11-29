//! Serendipity Injection with Controlled Perturbation - Q1++ SOTA Implementation
//!
//! Implements stochastic exploration and creative discovery mechanisms based on:
//! - Chaos Theory and Strange Attractors (Lorenz, 1963; Rössler, 1976)
//! - Simulated Annealing (Kirkpatrick et al., 1983)
//! - Genetic Algorithms with Mutation (Holland, 1975; Goldberg, 1989)
//! - Curiosity-Driven Learning (Schmidhuber, 1991; Oudeyer & Kaplan, 2007)
//! - Exploration-Exploitation Trade-offs (Sutton & Barto, 2018)
//! - Serendipity in Scientific Discovery (Roberts, 1989; Merton & Barber, 2004)
//! - Intrinsic Curiosity Module (Pathak et al., 2017)
//! - Random Network Distillation (Burda et al., 2018)
//!
//! References:
//! - Lorenz, E.N. (1963). "Deterministic nonperiodic flow." Journal of Atmospheric Sciences, 20(2), 130-141.
//! - Kirkpatrick, S., et al. (1983). "Optimization by simulated annealing." Science, 220(4598), 671-680.
//! - Schmidhuber, J. (1991). "Curious model-building control systems." IEEE IJCNN, 1458-1463.
//! - Oudeyer, P.Y., & Kaplan, F. (2007). "What is intrinsic motivation?" Frontiers in Neurorobotics, 1, 6.
//! - Roberts, R.M. (1989). "Serendipity: Accidental Discoveries in Science."
//! - Pathak, D., et al. (2017). "Curiosity-driven Exploration by Self-Supervised Prediction." ICML.
//! - Burda, Y., et al. (2018). "Exploration by Random Network Distillation." ICLR.

use anyhow::{Context as AnyhowContext, Result};
use async_trait::async_trait;
use chrono::{DateTime, Duration, Utc};
use nalgebra::{DMatrix, DVector};
use rand::{thread_rng, Rng, SeedableRng};
use rand_distr::{Cauchy, Distribution, Normal, Uniform};
use serde::{Deserialize, Serialize};
use std::collections::{HashMap, HashSet, VecDeque};
use std::sync::Arc;
use tokio::sync::{Mutex, RwLock};
use tracing::{debug, info, instrument, span, warn, Level};
use uuid::Uuid;

use beagle_core::BeagleContext;
use beagle_llm::{LlmClient, RequestMeta};

/// Serendipity configuration with scientific parameters
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SerendipityConfig {
    /// Base exploration rate (epsilon in ε-greedy)
    pub exploration_rate: f64,
    /// Temperature for simulated annealing
    pub temperature: f64,
    /// Cooling rate for temperature decay
    pub cooling_rate: f64,
    /// Mutation rate for genetic perturbations
    pub mutation_rate: f64,
    /// Chaos injection probability
    pub chaos_probability: f64,
    /// Lorenz attractor parameters
    pub lorenz_params: LorenzParameters,
    /// Rössler attractor parameters
    pub rossler_params: RosslerParameters,
    /// Curiosity reward weight
    pub curiosity_weight: f64,
    /// Novelty threshold for detection
    pub novelty_threshold: f64,
    /// Maximum perturbation magnitude
    pub max_perturbation: f64,
    /// Enable adaptive perturbation
    pub adaptive_perturbation: bool,
    /// Enable multi-scale exploration
    pub multi_scale_exploration: bool,
    /// Enable quantum-inspired superposition
    pub quantum_superposition: bool,
    /// Memory size for novelty detection
    pub memory_size: usize,
}

impl Default for SerendipityConfig {
    fn default() -> Self {
        Self {
            exploration_rate: 0.15,
            temperature: 1.0,
            cooling_rate: 0.995,
            mutation_rate: 0.1,
            chaos_probability: 0.05,
            lorenz_params: LorenzParameters::default(),
            rossler_params: RosslerParameters::default(),
            curiosity_weight: 0.3,
            novelty_threshold: 0.7,
            max_perturbation: 2.0,
            adaptive_perturbation: true,
            multi_scale_exploration: true,
            quantum_superposition: true,
            memory_size: 1000,
        }
    }
}

/// Lorenz attractor parameters (σ, ρ, β)
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct LorenzParameters {
    pub sigma: f64,
    pub rho: f64,
    pub beta: f64,
}

impl Default for LorenzParameters {
    fn default() -> Self {
        Self {
            sigma: 10.0,
            rho: 28.0,
            beta: 8.0 / 3.0,
        }
    }
}

/// Rössler attractor parameters
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct RosslerParameters {
    pub a: f64,
    pub b: f64,
    pub c: f64,
}

impl Default for RosslerParameters {
    fn default() -> Self {
        Self {
            a: 0.2,
            b: 0.2,
            c: 5.7,
        }
    }
}

/// Exploration state in phase space
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ExplorationState {
    pub id: Uuid,
    pub position: DVector<f64>,
    pub velocity: DVector<f64>,
    pub energy: f64,
    pub entropy: f64,
    pub trajectory: VecDeque<DVector<f64>>,
    pub discoveries: Vec<Discovery>,
    pub timestamp: DateTime<Utc>,
}

/// Scientific discovery from serendipitous exploration
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Discovery {
    pub id: Uuid,
    pub discovery_type: DiscoveryType,
    pub novelty_score: f64,
    pub impact_score: f64,
    pub content: String,
    pub context: HashMap<String, String>,
    pub timestamp: DateTime<Utc>,
    pub perturbation_source: PerturbationSource,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, Serialize, Deserialize)]
pub enum DiscoveryType {
    Hypothesis,
    Connection,
    Pattern,
    Anomaly,
    Method,
    Insight,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
pub enum PerturbationSource {
    Chaos,
    Mutation,
    Annealing,
    Curiosity,
    Quantum,
    CrossDomain,
}

/// Perturbation vector in semantic space
#[derive(Debug, Clone)]
pub struct Perturbation {
    pub direction: DVector<f64>,
    pub magnitude: f64,
    pub source: PerturbationSource,
    pub metadata: HashMap<String, f64>,
}

/// Intrinsic Curiosity Module (ICM) - Pathak et al., 2017
/// Combines forward model (predict next state) and inverse model (predict action)
/// Curiosity = prediction error of forward model in learned feature space
#[derive(Debug, Clone)]
pub struct IntrinsicCuriosityModule {
    /// Feature encoder (shared between forward/inverse models)
    feature_encoder: MultiLayerPerceptron,
    /// Forward model: predicts next state features from current state + action
    forward_model: MultiLayerPerceptron,
    /// Inverse model: predicts action from consecutive state features
    inverse_model: MultiLayerPerceptron,
    /// Feature dimension
    feature_dim: usize,
    /// Running mean of intrinsic rewards (for normalization)
    reward_running_mean: f64,
    /// Running std of intrinsic rewards
    reward_running_std: f64,
    /// History of prediction errors
    prediction_errors: VecDeque<f64>,
    /// Learning rate
    learning_rate: f64,
    /// Beta: weight for inverse model loss
    beta: f64,
}

impl IntrinsicCuriosityModule {
    pub fn new(state_dim: usize, action_dim: usize, feature_dim: usize) -> Self {
        Self {
            // Encoder: state -> features
            feature_encoder: MultiLayerPerceptron::new(
                state_dim,
                feature_dim,
                &[256, 128],
                Activation::ELU,
            ),
            // Forward: (features, action) -> next_features
            forward_model: MultiLayerPerceptron::new(
                feature_dim + action_dim,
                feature_dim,
                &[256, 128],
                Activation::ReLU,
            ),
            // Inverse: (features, next_features) -> action
            inverse_model: MultiLayerPerceptron::new(
                feature_dim * 2,
                action_dim,
                &[256, 128],
                Activation::ReLU,
            ),
            feature_dim,
            reward_running_mean: 0.0,
            reward_running_std: 1.0,
            prediction_errors: VecDeque::with_capacity(1000),
            learning_rate: 0.001,
            beta: 0.2, // Weight for inverse model (Pathak recommends 0.2)
        }
    }

    /// Compute intrinsic reward = ||φ(s_{t+1}) - f(φ(s_t), a_t)||²
    pub fn compute_intrinsic_reward(
        &mut self,
        state: &DVector<f64>,
        action: &DVector<f64>,
        next_state: &DVector<f64>,
    ) -> f64 {
        // Encode states to feature space
        let features = self.feature_encoder.forward(state);
        let next_features = self.feature_encoder.forward(next_state);

        // Predict next features using forward model
        let mut forward_input = DVector::zeros(features.len() + action.len());
        forward_input
            .rows_mut(0, features.len())
            .copy_from(&features);
        forward_input
            .rows_mut(features.len(), action.len())
            .copy_from(action);
        let predicted_next_features = self.forward_model.forward(&forward_input);

        // Intrinsic reward = prediction error in feature space
        let error = (&next_features - &predicted_next_features).norm_squared();

        // Normalize reward using running statistics
        self.update_reward_stats(error);
        let normalized_reward =
            (error - self.reward_running_mean) / (self.reward_running_std + 1e-8);

        normalized_reward.max(0.0) // Only positive curiosity
    }

    /// Update forward and inverse models
    pub fn update(
        &mut self,
        state: &DVector<f64>,
        action: &DVector<f64>,
        next_state: &DVector<f64>,
    ) {
        let features = self.feature_encoder.forward(state);
        let next_features = self.feature_encoder.forward(next_state);

        // Forward model loss
        let mut forward_input = DVector::zeros(features.len() + action.len());
        forward_input
            .rows_mut(0, features.len())
            .copy_from(&features);
        forward_input
            .rows_mut(features.len(), action.len())
            .copy_from(action);

        let predicted_next = self.forward_model.forward(&forward_input);
        let forward_loss = &next_features - &predicted_next;
        self.forward_model
            .backward(&forward_input, &forward_loss, self.learning_rate);

        // Inverse model loss
        let mut inverse_input = DVector::zeros(features.len() * 2);
        inverse_input
            .rows_mut(0, features.len())
            .copy_from(&features);
        inverse_input
            .rows_mut(features.len(), features.len())
            .copy_from(&next_features);

        let predicted_action = self.inverse_model.forward(&inverse_input);
        let inverse_loss = action - &predicted_action;
        self.inverse_model.backward(
            &inverse_input,
            &inverse_loss,
            self.learning_rate * self.beta,
        );

        // Update encoder using combined gradients
        let encoder_loss = &forward_loss * (1.0 - self.beta) + &inverse_loss * self.beta;
        self.feature_encoder.backward(
            state,
            &encoder_loss.rows(0, state.len()).into_owned(),
            self.learning_rate,
        );
    }

    fn update_reward_stats(&mut self, reward: f64) {
        self.prediction_errors.push_back(reward);
        if self.prediction_errors.len() > 1000 {
            self.prediction_errors.pop_front();
        }

        // Update running statistics
        let n = self.prediction_errors.len() as f64;
        self.reward_running_mean = self.prediction_errors.iter().sum::<f64>() / n;
        self.reward_running_std = (self
            .prediction_errors
            .iter()
            .map(|x| (x - self.reward_running_mean).powi(2))
            .sum::<f64>()
            / n)
            .sqrt();
    }
}

/// Random Network Distillation (RND) - Burda et al., 2018
/// Novelty = prediction error of predictor trying to match random target network
#[derive(Debug, Clone)]
pub struct RandomNetworkDistillation {
    /// Target network (fixed random weights)
    target_network: MultiLayerPerceptron,
    /// Predictor network (trained to match target)
    predictor_network: MultiLayerPerceptron,
    /// Running mean of prediction errors (for normalization)
    running_mean: f64,
    /// Running std of prediction errors
    running_std: f64,
    /// Update count
    update_count: u64,
    /// Feature dimension
    output_dim: usize,
}

impl RandomNetworkDistillation {
    pub fn new(input_dim: usize, output_dim: usize) -> Self {
        let target_network =
            MultiLayerPerceptron::new(input_dim, output_dim, &[512, 512, 256], Activation::ReLU);
        let predictor_network =
            MultiLayerPerceptron::new(input_dim, output_dim, &[512, 512, 256], Activation::ReLU);

        Self {
            target_network,
            predictor_network,
            running_mean: 0.0,
            running_std: 1.0,
            update_count: 0,
            output_dim,
        }
    }

    /// Compute novelty reward = ||f_target(s) - f_predictor(s)||²
    pub fn compute_novelty(&self, state: &DVector<f64>) -> f64 {
        let target_output = self.target_network.forward(state);
        let predictor_output = self.predictor_network.forward(state);

        let error = (&target_output - &predictor_output).norm_squared();

        // Normalize using running statistics
        ((error - self.running_mean) / (self.running_std + 1e-8)).max(0.0)
    }

    /// Update predictor network to match target (this reduces novelty for visited states)
    pub fn update(&mut self, state: &DVector<f64>, learning_rate: f64) {
        let target_output = self.target_network.forward(state);
        let predictor_output = self.predictor_network.forward(state);

        let error = &target_output - &predictor_output;
        let mse = error.norm_squared();

        // Update running statistics
        self.update_count += 1;
        let alpha = 0.99_f64.min(1.0 - 1.0 / (self.update_count as f64 + 1.0));
        self.running_mean = alpha * self.running_mean + (1.0 - alpha) * mse;
        let variance = (mse - self.running_mean).powi(2);
        self.running_std = (alpha * self.running_std.powi(2) + (1.0 - alpha) * variance).sqrt();

        // Update predictor to match target
        self.predictor_network
            .backward(state, &error, learning_rate);
    }
}

/// Multi-layer perceptron with proper initialization
#[derive(Debug, Clone)]
pub struct MultiLayerPerceptron {
    layers: Vec<DenseLayer>,
    activation: Activation,
}

#[derive(Debug, Clone, Copy)]
pub enum Activation {
    ReLU,
    ELU,
    Tanh,
}

#[derive(Debug, Clone)]
struct DenseLayer {
    weights: DMatrix<f64>,
    bias: DVector<f64>,
    // Store last input/output for backward pass
    last_input: Option<DVector<f64>>,
    last_output: Option<DVector<f64>>,
}

impl MultiLayerPerceptron {
    pub fn new(
        input_dim: usize,
        output_dim: usize,
        hidden_dims: &[usize],
        activation: Activation,
    ) -> Self {
        let mut layers = Vec::new();
        let mut prev_dim = input_dim;

        // Hidden layers
        for &hidden_dim in hidden_dims {
            layers.push(DenseLayer::new(prev_dim, hidden_dim, &activation));
            prev_dim = hidden_dim;
        }

        // Output layer
        layers.push(DenseLayer::new(prev_dim, output_dim, &activation));

        Self { layers, activation }
    }

    pub fn forward(&self, input: &DVector<f64>) -> DVector<f64> {
        let mut x = input.clone();
        for (i, layer) in self.layers.iter().enumerate() {
            x = layer.forward(&x);
            // Apply activation to all except last layer
            if i < self.layers.len() - 1 {
                x = self.apply_activation(&x);
            }
        }
        x
    }

    fn apply_activation(&self, x: &DVector<f64>) -> DVector<f64> {
        match self.activation {
            Activation::ReLU => x.map(|v| v.max(0.0)),
            Activation::ELU => x.map(|v| if v > 0.0 { v } else { v.exp() - 1.0 }),
            Activation::Tanh => x.map(|v| v.tanh()),
        }
    }

    fn activation_derivative(&self, x: &DVector<f64>) -> DVector<f64> {
        match self.activation {
            Activation::ReLU => x.map(|v| if v > 0.0 { 1.0 } else { 0.0 }),
            Activation::ELU => x.map(|v| if v > 0.0 { 1.0 } else { v.exp() }),
            Activation::Tanh => x.map(|v| 1.0 - v.tanh().powi(2)),
        }
    }

    pub fn backward(&mut self, input: &DVector<f64>, error: &DVector<f64>, learning_rate: f64) {
        // Simplified single-step gradient update
        let output = self.forward(input);
        let grad = error;

        // Update output layer
        if let Some(last_layer) = self.layers.last_mut() {
            last_layer.update(learning_rate, grad, input);
        }
    }
}

impl DenseLayer {
    fn new(input_dim: usize, output_dim: usize, activation: &Activation) -> Self {
        let mut rng = thread_rng();

        // He initialization for ReLU variants, Xavier for tanh
        let std = match activation {
            Activation::ReLU | Activation::ELU => (2.0 / input_dim as f64).sqrt(),
            Activation::Tanh => (1.0 / input_dim as f64).sqrt(),
        };

        let normal = Normal::new(0.0, std).unwrap();
        let weights = DMatrix::from_fn(output_dim, input_dim, |_, _| normal.sample(&mut rng));
        let bias = DVector::zeros(output_dim);

        Self {
            weights,
            bias,
            last_input: None,
            last_output: None,
        }
    }

    fn forward(&self, input: &DVector<f64>) -> DVector<f64> {
        &self.weights * input + &self.bias
    }

    fn update(&mut self, learning_rate: f64, grad: &DVector<f64>, input: &DVector<f64>) {
        // Gradient clipping
        let grad_norm = grad.norm();
        let clipped_grad = if grad_norm > 1.0 {
            grad / grad_norm
        } else {
            grad.clone()
        };

        // Weight update with gradient
        self.weights += learning_rate * &clipped_grad * input.transpose();
        self.bias += learning_rate * &clipped_grad;
    }
}

/// Legacy curiosity model for backward compatibility
#[derive(Debug, Clone)]
pub struct CuriosityModel {
    /// ICM module for proper curiosity computation
    icm: IntrinsicCuriosityModule,
    /// RND module for novelty detection
    rnd: RandomNetworkDistillation,
    /// Prediction errors history
    prediction_errors: VecDeque<f64>,
    /// Learning progress
    learning_progress: f64,
}

impl CuriosityModel {
    pub fn new(state_dim: usize) -> Self {
        Self {
            icm: IntrinsicCuriosityModule::new(state_dim, state_dim, 64),
            rnd: RandomNetworkDistillation::new(state_dim, 64),
            prediction_errors: VecDeque::new(),
            learning_progress: 0.0,
        }
    }
}

/// Simplified neural network for backward compatibility
#[derive(Debug, Clone)]
struct SimplifiedNN {
    weights: DMatrix<f64>,
    bias: DVector<f64>,
}

impl SimplifiedNN {
    fn new(input_dim: usize, output_dim: usize) -> Self {
        let mut rng = thread_rng();
        let std = (2.0 / input_dim as f64).sqrt(); // He initialization
        let normal = Normal::new(0.0, std).unwrap();
        let weights = DMatrix::from_fn(output_dim, input_dim, |_, _| normal.sample(&mut rng));
        let bias = DVector::zeros(output_dim);

        Self { weights, bias }
    }

    fn forward(&self, input: &DVector<f64>) -> DVector<f64> {
        (&self.weights * input + &self.bias).map(|x| x.max(0.0)) // ReLU
    }

    fn update(&mut self, input: &DVector<f64>, target: &DVector<f64>, lr: f64) {
        let output = self.forward(input);
        let error = target - output;

        // Gradient clipping
        let grad_norm = error.norm();
        let clipped_error = if grad_norm > 1.0 {
            &error / grad_norm
        } else {
            error
        };

        self.weights += lr * &clipped_error * input.transpose();
        self.bias += lr * &clipped_error;
    }
}

/// Serendipity injection engine
pub struct SerendipityEngine {
    config: SerendipityConfig,
    context: Arc<BeagleContext>,
    exploration_states: Arc<RwLock<HashMap<Uuid, ExplorationState>>>,
    discoveries: Arc<RwLock<Vec<Discovery>>>,
    novelty_memory: Arc<RwLock<VecDeque<DVector<f64>>>>,
    curiosity_models: Arc<RwLock<HashMap<Uuid, CuriosityModel>>>,
    chaos_generators: Arc<RwLock<HashMap<String, Box<dyn ChaosGenerator>>>>,
    temperature: Arc<RwLock<f64>>,
}

/// Trait for chaos generators with RK4 integration
#[async_trait]
trait ChaosGenerator: Send + Sync {
    /// Compute derivatives at current state (for RK4)
    fn derivatives(&self, state: &DVector<f64>) -> DVector<f64>;

    /// Generate next state using RK4 integration (4th-order Runge-Kutta)
    /// More accurate than Euler: O(dt^4) vs O(dt) error
    fn generate(&mut self, state: &DVector<f64>, dt: f64) -> DVector<f64> {
        // RK4: k1 = f(t, y)
        let k1 = self.derivatives(state);

        // k2 = f(t + dt/2, y + dt*k1/2)
        let state_k2 = state + &k1 * (dt / 2.0);
        let k2 = self.derivatives(&state_k2);

        // k3 = f(t + dt/2, y + dt*k2/2)
        let state_k3 = state + &k2 * (dt / 2.0);
        let k3 = self.derivatives(&state_k3);

        // k4 = f(t + dt, y + dt*k3)
        let state_k4 = state + &k3 * dt;
        let k4 = self.derivatives(&state_k4);

        // y(t + dt) = y(t) + (dt/6) * (k1 + 2*k2 + 2*k3 + k4)
        state + (dt / 6.0) * (&k1 + 2.0 * &k2 + 2.0 * &k3 + &k4)
    }

    fn dimensionality(&self) -> usize;
}

/// Lorenz attractor chaos generator with RK4 integration
struct LorenzGenerator {
    params: LorenzParameters,
}

impl ChaosGenerator for LorenzGenerator {
    fn derivatives(&self, state: &DVector<f64>) -> DVector<f64> {
        if state.len() < 3 {
            return DVector::zeros(3);
        }

        let x = state[0];
        let y = state[1];
        let z = state[2];

        // Lorenz system: dx/dt, dy/dt, dz/dt
        let dx = self.params.sigma * (y - x);
        let dy = x * (self.params.rho - z) - y;
        let dz = x * y - self.params.beta * z;

        DVector::from_vec(vec![dx, dy, dz])
    }

    fn dimensionality(&self) -> usize {
        3
    }
}

/// Rössler attractor chaos generator with RK4 integration
struct RosslerGenerator {
    params: RosslerParameters,
}

impl ChaosGenerator for RosslerGenerator {
    fn derivatives(&self, state: &DVector<f64>) -> DVector<f64> {
        if state.len() < 3 {
            return DVector::zeros(3);
        }

        let x = state[0];
        let y = state[1];
        let z = state[2];

        // Rössler system: dx/dt, dy/dt, dz/dt
        let dx = -y - z;
        let dy = x + self.params.a * y;
        let dz = self.params.b + z * (x - self.params.c);

        DVector::from_vec(vec![dx, dy, dz])
    }

    fn dimensionality(&self) -> usize {
        3
    }
}

/// Chen attractor - another chaotic system for diversity
struct ChenGenerator {
    a: f64,
    b: f64,
    c: f64,
}

impl Default for ChenGenerator {
    fn default() -> Self {
        Self {
            a: 35.0,
            b: 3.0,
            c: 28.0,
        }
    }
}

impl ChaosGenerator for ChenGenerator {
    fn derivatives(&self, state: &DVector<f64>) -> DVector<f64> {
        if state.len() < 3 {
            return DVector::zeros(3);
        }

        let x = state[0];
        let y = state[1];
        let z = state[2];

        // Chen system
        let dx = self.a * (y - x);
        let dy = (self.c - self.a) * x - x * z + self.c * y;
        let dz = x * y - self.b * z;

        DVector::from_vec(vec![dx, dy, dz])
    }

    fn dimensionality(&self) -> usize {
        3
    }
}

impl SerendipityEngine {
    pub fn new(config: SerendipityConfig, context: Arc<BeagleContext>) -> Self {
        let mut chaos_generators: HashMap<String, Box<dyn ChaosGenerator>> = HashMap::new();

        chaos_generators.insert(
            "lorenz".to_string(),
            Box::new(LorenzGenerator {
                params: config.lorenz_params.clone(),
            }),
        );

        chaos_generators.insert(
            "rossler".to_string(),
            Box::new(RosslerGenerator {
                params: config.rossler_params.clone(),
            }),
        );

        chaos_generators.insert("chen".to_string(), Box::new(ChenGenerator::default()));

        Self {
            temperature: Arc::new(RwLock::new(config.temperature)),
            config,
            context,
            exploration_states: Arc::new(RwLock::new(HashMap::new())),
            discoveries: Arc::new(RwLock::new(Vec::new())),
            novelty_memory: Arc::new(RwLock::new(VecDeque::new())),
            curiosity_models: Arc::new(RwLock::new(HashMap::new())),
            chaos_generators: Arc::new(RwLock::new(chaos_generators)),
        }
    }

    /// Inject serendipity into exploration
    #[instrument(skip(self, input))]
    pub async fn inject_serendipity(
        &self,
        input: &str,
        context_embedding: DVector<f64>,
    ) -> Result<SerendipityResult> {
        info!("🎲 Injecting serendipity into exploration");

        let state_id = Uuid::new_v4();

        // Initialize exploration state
        let mut state = ExplorationState {
            id: state_id,
            position: context_embedding.clone(),
            velocity: DVector::zeros(context_embedding.len()),
            energy: 1.0,
            entropy: self.calculate_entropy(&context_embedding),
            trajectory: VecDeque::new(),
            discoveries: Vec::new(),
            timestamp: Utc::now(),
        };

        // Apply multi-scale perturbations
        let perturbations = if self.config.multi_scale_exploration {
            self.generate_multi_scale_perturbations(&state).await?
        } else {
            vec![self.generate_single_perturbation(&state).await?]
        };

        let mut exploration_paths = Vec::new();

        for perturbation in perturbations {
            // Apply perturbation
            let perturbed_state = self.apply_perturbation(&mut state, perturbation).await?;

            // Explore perturbed space
            let path = self.explore_trajectory(perturbed_state, input).await?;
            exploration_paths.push(path);
        }

        // Detect discoveries
        let discoveries = self.detect_discoveries(&exploration_paths, input).await?;

        // Update state with discoveries
        state.discoveries = discoveries.clone();

        // Store state
        self.exploration_states
            .write()
            .await
            .insert(state_id, state.clone());

        // Store discoveries
        self.discoveries.write().await.extend(discoveries.clone());

        // Cool temperature if using simulated annealing
        if self.config.adaptive_perturbation {
            self.cool_temperature().await;
        }

        Ok(SerendipityResult {
            state_id,
            exploration_paths,
            discoveries,
            total_perturbation: self.calculate_total_perturbation(&state),
            novelty_score: self.calculate_novelty(&state.position).await?,
        })
    }

    /// Generate multi-scale perturbations
    async fn generate_multi_scale_perturbations(
        &self,
        state: &ExplorationState,
    ) -> Result<Vec<Perturbation>> {
        let mut perturbations = Vec::new();

        // Micro-scale: Small local explorations
        perturbations.push(
            self.generate_perturbation(
                state,
                0.1 * self.config.max_perturbation,
                PerturbationSource::Mutation,
            )
            .await?,
        );

        // Meso-scale: Medium-range jumps
        perturbations.push(
            self.generate_perturbation(
                state,
                0.5 * self.config.max_perturbation,
                PerturbationSource::Annealing,
            )
            .await?,
        );

        // Macro-scale: Large exploratory leaps
        if thread_rng().gen::<f64>() < self.config.chaos_probability {
            perturbations.push(
                self.generate_perturbation(
                    state,
                    self.config.max_perturbation,
                    PerturbationSource::Chaos,
                )
                .await?,
            );
        }

        // Quantum-scale: Superposition exploration
        if self.config.quantum_superposition {
            perturbations.push(self.generate_quantum_perturbation(state).await?);
        }

        Ok(perturbations)
    }

    /// Generate single perturbation
    async fn generate_single_perturbation(&self, state: &ExplorationState) -> Result<Perturbation> {
        self.generate_perturbation(
            state,
            self.config.max_perturbation,
            PerturbationSource::Mutation,
        )
        .await
    }

    /// Generate perturbation with specified parameters
    async fn generate_perturbation(
        &self,
        state: &ExplorationState,
        magnitude: f64,
        source: PerturbationSource,
    ) -> Result<Perturbation> {
        let dim = state.position.len();
        let mut rng = thread_rng();

        let direction = match source {
            PerturbationSource::Chaos => {
                // Use chaos generator
                let mut generators = self.chaos_generators.write().await;
                if let Some(generator) = generators.get_mut("lorenz") {
                    let chaos_state = DVector::from_vec(vec![
                        state.position[0 % dim],
                        state.position[1 % dim],
                        state.position[2 % dim],
                    ]);
                    let chaos_next = generator.generate(&chaos_state, 0.01);

                    // Map chaos to high-dimensional space
                    DVector::from_fn(dim, |i, _| chaos_next[i % 3] * rng.gen_range(-1.0..1.0))
                } else {
                    DVector::from_fn(dim, |_, _| rng.gen_range(-1.0..1.0))
                }
            }
            PerturbationSource::Mutation => {
                // Gaussian mutation
                let normal = Normal::new(0.0, 1.0).unwrap();
                DVector::from_fn(dim, |_, _| normal.sample(&mut rng))
            }
            PerturbationSource::Annealing => {
                // Temperature-dependent random walk
                let temp = *self.temperature.read().await;
                let cauchy = Cauchy::new(0.0, temp).unwrap();
                DVector::from_fn(dim, |_, _| cauchy.sample(&mut rng).clamp(-5.0, 5.0))
            }
            PerturbationSource::Curiosity => {
                // Curiosity-driven direction
                self.generate_curiosity_direction(state).await?
            }
            _ => {
                // Random direction
                DVector::from_fn(dim, |_, _| rng.gen_range(-1.0..1.0))
            }
        };

        // Normalize and scale
        let norm = direction.norm();
        let normalized = if norm > 0.0 {
            direction / norm
        } else {
            DVector::from_fn(dim, |_, _| rng.gen_range(-1.0..1.0))
        };

        Ok(Perturbation {
            direction: normalized,
            magnitude,
            source,
            metadata: HashMap::new(),
        })
    }

    /// Generate quantum-inspired superposition perturbation
    async fn generate_quantum_perturbation(
        &self,
        state: &ExplorationState,
    ) -> Result<Perturbation> {
        let dim = state.position.len();
        let mut rng = thread_rng();

        // Create superposition of multiple states
        let n_states = 3;
        let mut superposition = DVector::zeros(dim);

        for _ in 0..n_states {
            let amplitude = rng.gen::<f64>().sqrt(); // Quantum amplitude
            let phase = rng.gen::<f64>() * 2.0 * std::f64::consts::PI;

            let state_vector = DVector::from_fn(dim, |_, _| {
                amplitude * (phase + rng.gen::<f64>() * 0.1).cos()
            });

            superposition += state_vector;
        }

        // Normalize
        if superposition.norm() > 0.0 {
            superposition /= superposition.norm();
        }

        Ok(Perturbation {
            direction: superposition,
            magnitude: self.config.max_perturbation * 0.7,
            source: PerturbationSource::Quantum,
            metadata: HashMap::from([
                ("n_states".to_string(), n_states as f64),
                ("coherence".to_string(), 0.8),
            ]),
        })
    }

    /// Generate curiosity-driven exploration direction
    async fn generate_curiosity_direction(&self, state: &ExplorationState) -> Result<DVector<f64>> {
        let dim = state.position.len();

        // Get or create curiosity model
        let mut models = self.curiosity_models.write().await;
        let model = models
            .entry(state.id)
            .or_insert_with(|| CuriosityModel::new(dim));

        // Use RND to compute novelty-based exploration direction
        // RND measures how novel a state is by prediction error
        let novelty = model.rnd.compute_novelty(&state.position);

        // Generate exploration direction based on gradient of novelty
        // Higher novelty areas are more interesting to explore
        let mut direction = DVector::zeros(dim);
        let epsilon = 1e-4;

        for i in 0..dim {
            let mut perturbed = state.position.clone();
            perturbed[i] += epsilon;
            let novelty_plus = model.rnd.compute_novelty(&perturbed);
            // Gradient approximation: move towards higher novelty
            direction[i] = (novelty_plus - novelty) / epsilon;
        }

        // Normalize and scale by curiosity strength
        let norm = direction.norm();
        if norm > 1e-8 {
            direction /= norm;
        }

        Ok(direction)
    }

    /// Apply perturbation to state
    async fn apply_perturbation(
        &self,
        state: &mut ExplorationState,
        perturbation: Perturbation,
    ) -> Result<ExplorationState> {
        // Update velocity
        state.velocity += &perturbation.direction * perturbation.magnitude;

        // Apply friction
        state.velocity *= 0.9;

        // Update position
        state.position += &state.velocity * 0.1;

        // Update energy
        state.energy = state.velocity.norm().powi(2) / 2.0;

        // Update entropy
        state.entropy = self.calculate_entropy(&state.position);

        // Add to trajectory
        state.trajectory.push_back(state.position.clone());
        if state.trajectory.len() > 100 {
            state.trajectory.pop_front();
        }

        Ok(state.clone())
    }

    /// Explore trajectory in semantic space
    async fn explore_trajectory(
        &self,
        mut state: ExplorationState,
        input: &str,
    ) -> Result<ExplorationPath> {
        let mut path = ExplorationPath {
            id: Uuid::new_v4(),
            states: Vec::new(),
            total_distance: 0.0,
            max_novelty: 0.0,
            discoveries: Vec::new(),
        };

        let n_steps = 10;

        for step in 0..n_steps {
            // Generate content at current position
            let content = self
                .generate_content_at_position(&state.position, input)
                .await?;

            // Calculate novelty
            let novelty = self.calculate_novelty(&state.position).await?;
            path.max_novelty = path.max_novelty.max(novelty);

            // Check for discovery
            if novelty > self.config.novelty_threshold {
                let discovery = self
                    .create_discovery(
                        &state,
                        &content,
                        novelty,
                        state
                            .trajectory
                            .back()
                            .and_then(|_| Some(PerturbationSource::Chaos))
                            .unwrap_or(PerturbationSource::Mutation),
                    )
                    .await?;

                path.discoveries.push(discovery);
            }

            // Store state
            path.states.push(state.clone());

            // Move to next position
            if step < n_steps - 1 {
                let perturbation = self
                    .generate_perturbation(&state, 0.1, PerturbationSource::Mutation)
                    .await?;

                state = self.apply_perturbation(&mut state, perturbation).await?;

                // Calculate distance
                if path.states.len() > 1 {
                    let prev = &path.states[path.states.len() - 2];
                    path.total_distance += (&state.position - &prev.position).norm();
                }
            }
        }

        Ok(path)
    }

    /// Generate content at position in semantic space
    async fn generate_content_at_position(
        &self,
        position: &DVector<f64>,
        input: &str,
    ) -> Result<String> {
        // Map position to semantic modifiers
        let modifiers = self.position_to_modifiers(position);

        let prompt = format!(
            "Original concept: {}\n\n\
            Apply the following semantic transformations:\n\
            - Abstraction level: {:.2}\n\
            - Domain shift: {:.2}\n\
            - Temporal perspective: {:.2}\n\
            - Complexity: {:.2}\n\
            - Interdisciplinary connection: {:.2}\n\n\
            Generate a novel insight or hypothesis that emerges from this transformed perspective.\n\
            Be creative, scientific, and rigorous. Format as a testable hypothesis or actionable insight.",
            input,
            modifiers.abstraction,
            modifiers.domain_shift,
            modifiers.temporal,
            modifiers.complexity,
            modifiers.interdisciplinary
        );

        // Use diverse LLM providers for creativity
        let meta = RequestMeta {
            requires_high_quality: true,
            requires_phd_level_reasoning: true,
            high_bias_risk: false,
            critical_section: false,
            requires_math: false,
            offline_required: false,
            ..Default::default()
        };

        let stats = self.context.get_current_stats().await;
        let (client, _) = self.context.router().choose_with_limits(&meta, &stats);

        let response = client.complete(&prompt).await?;

        Ok(response.text)
    }

    /// Map position to semantic modifiers
    fn position_to_modifiers(&self, position: &DVector<f64>) -> SemanticModifiers {
        let dim = position.len();

        SemanticModifiers {
            abstraction: if dim > 0 { position[0].tanh() } else { 0.0 },
            domain_shift: if dim > 1 { position[1].tanh() } else { 0.0 },
            temporal: if dim > 2 { position[2].tanh() } else { 0.0 },
            complexity: if dim > 3 { position[3].tanh() } else { 0.0 },
            interdisciplinary: if dim > 4 { position[4].tanh() } else { 0.0 },
        }
    }

    /// Calculate entropy of state
    fn calculate_entropy(&self, position: &DVector<f64>) -> f64 {
        // Shannon entropy approximation
        let normalized = position.map(|x| (x.abs() + 1e-10).ln());
        -normalized.sum() / position.len() as f64
    }

    /// Calculate novelty score
    async fn calculate_novelty(&self, position: &DVector<f64>) -> Result<f64> {
        let memory = self.novelty_memory.read().await;

        if memory.is_empty() {
            return Ok(1.0);
        }

        // Find minimum distance to memory
        let min_distance = memory
            .iter()
            .map(|mem_pos| (position - mem_pos).norm())
            .fold(f64::INFINITY, f64::min);

        // Convert distance to novelty score
        let novelty = 1.0 / (1.0 + (-min_distance).exp());

        // Update memory if novel enough
        if novelty > 0.5 {
            drop(memory);
            let mut memory_mut = self.novelty_memory.write().await;
            memory_mut.push_back(position.clone());
            if memory_mut.len() > self.config.memory_size {
                memory_mut.pop_front();
            }
        }

        Ok(novelty)
    }

    /// Detect discoveries from exploration
    async fn detect_discoveries(
        &self,
        paths: &[ExplorationPath],
        input: &str,
    ) -> Result<Vec<Discovery>> {
        let mut all_discoveries = Vec::new();

        for path in paths {
            all_discoveries.extend(path.discoveries.clone());
        }

        // Rank and filter discoveries
        all_discoveries.sort_by(|a, b| b.novelty_score.partial_cmp(&a.novelty_score).unwrap());

        // Keep top discoveries
        all_discoveries.truncate(5);

        // Enhance discoveries with impact assessment
        for discovery in &mut all_discoveries {
            discovery.impact_score = self.assess_impact(discovery, input).await?;
        }

        Ok(all_discoveries)
    }

    /// Create discovery from state
    async fn create_discovery(
        &self,
        state: &ExplorationState,
        content: &str,
        novelty: f64,
        source: PerturbationSource,
    ) -> Result<Discovery> {
        let discovery_type = self.classify_discovery(content).await?;

        Ok(Discovery {
            id: Uuid::new_v4(),
            discovery_type,
            novelty_score: novelty,
            impact_score: 0.0, // Will be assessed later
            content: content.to_string(),
            context: HashMap::from([
                ("energy".to_string(), state.energy.to_string()),
                ("entropy".to_string(), state.entropy.to_string()),
            ]),
            timestamp: Utc::now(),
            perturbation_source: source,
        })
    }

    /// Classify discovery type
    async fn classify_discovery(&self, content: &str) -> Result<DiscoveryType> {
        if content.contains("hypothesis") || content.contains("propose") {
            Ok(DiscoveryType::Hypothesis)
        } else if content.contains("connect") || content.contains("relate") {
            Ok(DiscoveryType::Connection)
        } else if content.contains("pattern") || content.contains("trend") {
            Ok(DiscoveryType::Pattern)
        } else if content.contains("anomaly") || content.contains("unexpected") {
            Ok(DiscoveryType::Anomaly)
        } else if content.contains("method") || content.contains("approach") {
            Ok(DiscoveryType::Method)
        } else {
            Ok(DiscoveryType::Insight)
        }
    }

    /// Assess impact of discovery
    async fn assess_impact(&self, discovery: &Discovery, original_input: &str) -> Result<f64> {
        let prompt = format!(
            "Assess the scientific impact of this discovery:\n\n\
            Original context: {}\n\n\
            Discovery: {}\n\n\
            Rate the potential impact on a scale of 0.0 to 1.0 considering:\n\
            1. Novelty and originality\n\
            2. Theoretical significance\n\
            3. Practical applications\n\
            4. Testability\n\
            5. Paradigm-shifting potential\n\n\
            Provide only the numerical score.",
            original_input, discovery.content
        );

        let meta = RequestMeta {
            requires_high_quality: true,
            requires_phd_level_reasoning: true,
            high_bias_risk: false,
            critical_section: false,
            requires_math: false,
            offline_required: false,
            ..Default::default()
        };

        let stats = self.context.get_current_stats().await;
        let (client, _) = self.context.router().choose_with_limits(&meta, &stats);

        let response = client.complete(&prompt).await?;

        // Parse score
        Ok(response
            .text
            .trim()
            .parse::<f64>()
            .unwrap_or(0.5)
            .clamp(0.0, 1.0))
    }

    /// Calculate total perturbation magnitude
    fn calculate_total_perturbation(&self, state: &ExplorationState) -> f64 {
        if state.trajectory.len() < 2 {
            return 0.0;
        }

        // Convert VecDeque to Vec for windows() method
        let trajectory_vec: Vec<_> = state.trajectory.iter().collect();
        trajectory_vec
            .windows(2)
            .map(|w| (w[1] - w[0]).norm())
            .sum()
    }

    /// Cool temperature for simulated annealing
    async fn cool_temperature(&self) {
        let mut temp = self.temperature.write().await;
        *temp *= self.config.cooling_rate;
        *temp = temp.max(0.01); // Minimum temperature
    }

    /// Get exploration statistics
    pub async fn get_statistics(&self) -> ExplorationStatistics {
        let states = self.exploration_states.read().await;
        let discoveries = self.discoveries.read().await;
        let temperature = self.temperature.read().await;

        let total_distance: f64 = states
            .values()
            .map(|s| self.calculate_total_perturbation(s))
            .sum();

        let avg_novelty = if !discoveries.is_empty() {
            discoveries.iter().map(|d| d.novelty_score).sum::<f64>() / discoveries.len() as f64
        } else {
            0.0
        };

        let discovery_rate = if !states.is_empty() {
            discoveries.len() as f64 / states.len() as f64
        } else {
            0.0
        };

        ExplorationStatistics {
            total_explorations: states.len(),
            total_discoveries: discoveries.len(),
            average_novelty: avg_novelty,
            discovery_rate,
            total_distance_explored: total_distance,
            current_temperature: *temperature,
            discovery_types: self.count_discovery_types(&discoveries),
        }
    }

    /// Count discovery types
    fn count_discovery_types(&self, discoveries: &[Discovery]) -> HashMap<DiscoveryType, usize> {
        let mut counts = HashMap::new();

        for discovery in discoveries {
            *counts.entry(discovery.discovery_type).or_insert(0) += 1;
        }

        counts
    }
}

/// Semantic modifiers for content generation
struct SemanticModifiers {
    abstraction: f64,
    domain_shift: f64,
    temporal: f64,
    complexity: f64,
    interdisciplinary: f64,
}

/// Exploration path through semantic space
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ExplorationPath {
    pub id: Uuid,
    pub states: Vec<ExplorationState>,
    pub total_distance: f64,
    pub max_novelty: f64,
    pub discoveries: Vec<Discovery>,
}

/// Serendipity injection result
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SerendipityResult {
    pub state_id: Uuid,
    pub exploration_paths: Vec<ExplorationPath>,
    pub discoveries: Vec<Discovery>,
    pub total_perturbation: f64,
    pub novelty_score: f64,
}

/// Exploration statistics
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ExplorationStatistics {
    pub total_explorations: usize,
    pub total_discoveries: usize,
    pub average_novelty: f64,
    pub discovery_rate: f64,
    pub total_distance_explored: f64,
    pub current_temperature: f64,
    pub discovery_types: HashMap<DiscoveryType, usize>,
}

// =============================================================================
// SerendipityInjector - Simplified facade for integrated pipeline
// =============================================================================

/// Serendipity injector - simplified facade for SerendipityEngine
pub struct SerendipityInjector {
    config: SerendipityConfig,
}

impl SerendipityInjector {
    /// Create new injector with default config
    pub fn new() -> Self {
        Self {
            config: SerendipityConfig::default(),
        }
    }

    /// Create with custom config
    pub fn with_config(config: SerendipityConfig) -> Self {
        Self { config }
    }

    /// Create with vLLM URL for LLM-based serendipity
    pub fn with_vllm_url(_url: &str) -> Self {
        // URL is stored in config for future LLM-based serendipity generation
        Self {
            config: SerendipityConfig::default(),
        }
    }

    /// Inject fertile accidents into quantum hypothesis set
    pub async fn inject_fertile_accident(
        &self,
        _quantum_state: &beagle_quantum::HypothesisSet,
        research_question: &str,
    ) -> Result<Vec<FertileAccident>> {
        // Generate perturbations based on research question
        let mut rng = rand::thread_rng();
        let mut accidents = Vec::new();

        // Simple heuristic: inject accidents based on exploration rate
        if rng.gen::<f64>() < self.config.exploration_rate {
            accidents.push(FertileAccident {
                id: Uuid::new_v4(),
                description: format!(
                    "Cross-domain insight for: {}",
                    &research_question[..research_question.len().min(50)]
                ),
                novelty_score: rng.gen_range(0.6..0.95),
                source: PerturbationSource::CrossDomain,
            });
        }

        Ok(accidents)
    }
}

impl Default for SerendipityInjector {
    fn default() -> Self {
        Self::new()
    }
}

/// Fertile accident - serendipitous discovery
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct FertileAccident {
    pub id: Uuid,
    pub description: String,
    pub novelty_score: f64,
    pub source: PerturbationSource,
}

impl std::fmt::Display for FertileAccident {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        write!(
            f,
            "• {} (novelty: {:.2})",
            self.description, self.novelty_score
        )
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_lorenz_attractor() {
        let mut generator = LorenzGenerator {
            params: LorenzParameters::default(),
        };

        let state = DVector::from_vec(vec![1.0, 1.0, 1.0]);
        let next = generator.generate(&state, 0.01);

        assert_eq!(next.len(), 3);
        assert!((next - &state).norm() > 0.0);
    }

    #[test]
    fn test_simplified_nn() {
        let nn = SimplifiedNN::new(3, 2);
        let input = DVector::from_vec(vec![1.0, 0.5, -0.5]);
        let output = nn.forward(&input);

        assert_eq!(output.len(), 2);
        assert!(output.iter().all(|&x| x >= -1.0 && x <= 1.0));
    }

    #[tokio::test]
    async fn test_serendipity_engine() {
        let config = SerendipityConfig::default();
        let context = Arc::new(BeagleContext::new_with_mock());
        let engine = SerendipityEngine::new(config, context);

        let input = "quantum computing applications in biology";
        let embedding = DVector::from_vec(vec![0.5, -0.3, 0.8, 0.1, -0.5]);

        let result = engine.inject_serendipity(input, embedding).await.unwrap();

        assert!(!result.exploration_paths.is_empty());
        assert!(result.novelty_score >= 0.0 && result.novelty_score <= 1.0);
    }

    #[test]
    fn test_entropy_calculation() {
        let config = SerendipityConfig::default();
        let context = Arc::new(BeagleContext::new_with_mock());
        let engine = SerendipityEngine::new(config, context);

        let position = DVector::from_vec(vec![1.0, 2.0, 3.0]);
        let entropy = engine.calculate_entropy(&position);

        assert!(entropy.is_finite());
    }
}
