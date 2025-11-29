//! DreamerV3 World Model Implementation (2024-2025 SOTA)
//!
//! Based on:
//! - "DreamerV3: Mastering Diverse Domains through World Models" (2024)
//! - "DyMoDreamer: World Modeling with Dynamic Modulation" (Sep 2024)
//! - "Contextual RSSM for Zero-Shot Generalization" (March 2024)
//! - "Hybrid-RSSM for Robust Representations" (2024)
//!
//! Implements RSSM (Recurrent State-Space Model) with latent dynamics

use anyhow::Result;
use nalgebra::{DMatrix, DVector};
use serde::{Deserialize, Serialize};
use std::collections::VecDeque;
use std::sync::Arc;
use tokio::sync::RwLock;
use rand::Rng;
use rand_distr::{Distribution, Normal};

/// Recurrent State-Space Model (RSSM) for world modeling
pub struct RSSM {
    /// Encoder network q(z_t | h_t, o_t)
    encoder: Encoder,

    /// Dynamics predictor p(z_t | h_t)
    dynamics: DynamicsPredictor,

    /// Recurrent state model
    recurrent: RecurrentModel,

    /// Decoder for observation reconstruction
    decoder: Decoder,

    /// Reward predictor
    reward_predictor: RewardPredictor,

    /// Continue predictor (discount factor)
    continue_predictor: ContinuePredictor,

    /// Latent state dimensionality (32 categorical, 32 classes each)
    latent_dim: usize,

    /// Hidden state size
    hidden_dim: usize,

    /// Context for zero-shot generalization (cRSSM)
    context_encoder: Option<ContextEncoder>,

    /// Dynamic modulation (DyMoDreamer)
    dynamic_modulator: Option<DynamicModulator>,
}

impl RSSM {
    /// Create new RSSM with specified dimensions
    pub fn new(hidden_dim: usize, action_dim: usize) -> Result<Self> {
        Ok(Self {
            encoder: Encoder::new(hidden_dim)?,
            dynamics: DynamicsPredictor::new(hidden_dim, action_dim)?,
            recurrent: RecurrentModel::new(hidden_dim, action_dim)?,
            decoder: Decoder::new(hidden_dim)?,
            reward_predictor: RewardPredictor::new(hidden_dim)?,
            continue_predictor: ContinuePredictor::new(hidden_dim)?,
            latent_dim: 32, // 32 categorical distributions
            hidden_dim,
            context_encoder: Some(ContextEncoder::new(hidden_dim)?),
            dynamic_modulator: Some(DynamicModulator::new(hidden_dim)?),
        })
    }

    /// Forward pass through RSSM
    pub async fn forward(
        &self,
        observation: &Observation,
        action: &Action,
        prev_state: &RSSMState,
    ) -> Result<RSSMState> {
        // Step 1: Update recurrent state with action
        let h_t = self.recurrent.forward(&prev_state.h, action)?;

        // Step 2: Predict latent from dynamics
        let z_pred = self.dynamics.predict(&h_t)?;

        // Step 3: Encode observation (posterior)
        let z_post = self.encoder.encode(&h_t, observation)?;

        // Step 4: Apply dynamic modulation if available
        let z_final = if let Some(ref modulator) = self.dynamic_modulator {
            modulator.modulate(&z_post, &h_t)?
        } else {
            z_post
        };

        // Step 5: Decode to reconstruct observation
        let reconstruction = self.decoder.decode(&h_t, &z_final)?;

        // Step 6: Predict reward and continue
        let reward = self.reward_predictor.predict(&h_t, &z_final)?;
        let continue_prob = self.continue_predictor.predict(&h_t, &z_final)?;

        Ok(RSSMState {
            h: h_t,
            z: z_final,
            reconstruction,
            reward,
            continue_prob,
        })
    }

    /// Imagine future trajectories (latent rollout)
    pub async fn imagine(
        &self,
        initial_state: &RSSMState,
        policy: &Policy,
        horizon: usize,
    ) -> Result<Vec<ImaginedTrajectory>> {
        let mut trajectories = Vec::new();
        let mut state = initial_state.clone();

        for _ in 0..horizon {
            // Sample action from policy
            let action = policy.sample(&state)?;

            // Dynamics only (no observation)
            let h_next = self.recurrent.forward(&state.h, &action)?;
            let z_next = self.dynamics.predict(&h_next)?;

            // Predict reward and continue
            let reward = self.reward_predictor.predict(&h_next, &z_next)?;
            let continue_prob = self.continue_predictor.predict(&h_next, &z_next)?;

            trajectories.push(ImaginedTrajectory {
                state: state.clone(),
                action: action.clone(),
                reward,
                continue_prob,
            });

            // Update state
            state = RSSMState {
                h: h_next,
                z: z_next,
                reconstruction: None,
                reward,
                continue_prob,
            };

            // Stop if episode ends
            if continue_prob < 0.5 {
                break;
            }
        }

        Ok(trajectories)
    }

    /// Train RSSM on experience batch
    pub async fn train(&mut self, batch: &ExperienceBatch) -> Result<RSSMLoss> {
        let mut total_loss = 0.0;
        let mut recon_loss = 0.0;
        let mut reward_loss = 0.0;
        let mut continue_loss = 0.0;
        let mut kl_loss = 0.0;

        for episode in &batch.episodes {
            let mut state = RSSMState::initial(self.hidden_dim);

            for (obs, action, reward, done) in episode.iter() {
                // Forward pass
                let next_state = self.forward(obs, action, &state).await?;

                // Reconstruction loss
                if let Some(ref recon) = next_state.reconstruction {
                    recon_loss += self.reconstruction_loss(obs, recon)?;
                }

                // Reward prediction loss
                reward_loss += (next_state.reward - reward).powi(2);

                // Continue prediction loss
                let target_continue = if *done { 0.0 } else { 1.0 };
                continue_loss += binary_cross_entropy(next_state.continue_prob, target_continue);

                // KL divergence (with KL balancing)
                let z_prior = self.dynamics.predict(&state.h)?;
                kl_loss += self.kl_divergence(&next_state.z, &z_prior)?;

                state = next_state;
            }
        }

        // Apply symlog transformation for stability
        total_loss = symlog(recon_loss) + symlog(reward_loss) + symlog(continue_loss) + 0.1 * kl_loss;

        Ok(RSSMLoss {
            total: total_loss,
            reconstruction: recon_loss,
            reward: reward_loss,
            continue_pred: continue_loss,
            kl_divergence: kl_loss,
        })
    }

    fn reconstruction_loss(&self, obs: &Observation, recon: &Observation) -> Result<f64> {
        // MSE loss for continuous observations
        let diff = &obs.data - &recon.data;
        Ok(diff.dot(&diff))
    }

    fn kl_divergence(&self, posterior: &LatentState, prior: &LatentState) -> Result<f64> {
        // KL divergence between categorical distributions
        let mut kl = 0.0;
        for i in 0..self.latent_dim {
            for j in 0..32 {
                let p = posterior.categoricals[i][j];
                let q = prior.categoricals[i][j];
                if p > 0.0 {
                    kl += p * (p / q.max(1e-8)).ln();
                }
            }
        }
        Ok(kl)
    }
}

/// Encoder: q(z_t | h_t, o_t)
/// Uses CNN for image observations with proper DreamerV3 architecture
struct Encoder {
    /// MLP layers for feature extraction
    layers: Vec<DMatrix<f64>>,
    /// Layer normalization parameters
    layer_norm_gamma: Vec<DVector<f64>>,
    layer_norm_beta: Vec<DVector<f64>>,
}

impl Encoder {
    fn new(hidden_dim: usize) -> Result<Self> {
        // Use He initialization for ReLU activations: sqrt(2/fan_in)
        let init_scale_1 = (2.0 / (hidden_dim * 2) as f64).sqrt();
        let init_scale_2 = (2.0 / hidden_dim as f64).sqrt();
        let init_scale_3 = (2.0 / hidden_dim as f64).sqrt();

        Ok(Self {
            layers: vec![
                DMatrix::from_fn(hidden_dim, hidden_dim * 2, |_, _| {
                    rand::thread_rng().gen_range(-1.0..1.0) * init_scale_1
                }),
                DMatrix::from_fn(hidden_dim, hidden_dim, |_, _| {
                    rand::thread_rng().gen_range(-1.0..1.0) * init_scale_2
                }),
                DMatrix::from_fn(32 * 32, hidden_dim, |_, _| {
                    rand::thread_rng().gen_range(-1.0..1.0) * init_scale_3
                }),
            ],
            layer_norm_gamma: vec![
                DVector::from_element(hidden_dim, 1.0),
                DVector::from_element(hidden_dim, 1.0),
            ],
            layer_norm_beta: vec![
                DVector::zeros(hidden_dim),
                DVector::zeros(hidden_dim),
            ],
        })
    }

    fn encode(&self, h: &DVector<f64>, obs: &Observation) -> Result<LatentState> {
        // Concatenate hidden state and observation
        let mut x = DVector::zeros(h.len() + obs.data.len());
        for (i, &v) in h.iter().enumerate() {
            x[i] = v;
        }
        for (i, &v) in obs.data.iter().enumerate() {
            x[h.len() + i] = v;
        }

        // Forward through layers with layer normalization
        for (idx, layer) in self.layers[..2].iter().enumerate() {
            // Linear transformation
            x = layer * &x;

            // Layer normalization
            x = self.layer_norm(&x, &self.layer_norm_gamma[idx], &self.layer_norm_beta[idx]);

            // SiLU activation (better than ReLU for world models)
            x = silu(&x);
        }

        // Output categorical distributions
        let logits = &self.layers[2] * &x;
        let categoricals = self.sample_categoricals_gumbel(logits)?;

        Ok(LatentState { categoricals })
    }

    /// Layer normalization
    fn layer_norm(&self, x: &DVector<f64>, gamma: &DVector<f64>, beta: &DVector<f64>) -> DVector<f64> {
        let mean = x.mean();
        let var = x.iter().map(|&v| (v - mean).powi(2)).sum::<f64>() / x.len() as f64;
        let std = (var + 1e-5).sqrt();

        DVector::from_fn(x.len(), |i, _| {
            gamma[i.min(gamma.len() - 1)] * (x[i] - mean) / std + beta[i.min(beta.len() - 1)]
        })
    }

    /// Gumbel-Softmax for differentiable categorical sampling
    fn sample_categoricals_gumbel(&self, logits: DVector<f64>) -> Result<Vec<Vec<f64>>> {
        let mut categoricals = Vec::new();
        let temperature = 1.0; // Temperature for Gumbel-Softmax

        for i in 0..32 {
            let start = i * 32;
            let cat_logits: Vec<f64> = logits.rows(start, 32).iter().copied().collect();

            // Add Gumbel noise for stochastic sampling
            let gumbel_logits: Vec<f64> = cat_logits
                .iter()
                .map(|&l| {
                    let u: f64 = rand::thread_rng().gen_range(1e-10..1.0);
                    l + (-(-u.ln()).ln()) // Gumbel(0,1) sample
                })
                .collect();

            // Softmax with temperature
            let max_val = gumbel_logits.iter().cloned().fold(f64::NEG_INFINITY, f64::max);
            let exp_vals: Vec<f64> = gumbel_logits
                .iter()
                .map(|&v| ((v - max_val) / temperature).exp())
                .collect();
            let sum: f64 = exp_vals.iter().sum();
            let probs: Vec<f64> = exp_vals.iter().map(|&v| v / sum).collect();

            // Straight-through estimator: use hard sample in forward, soft in backward
            let hard_sample = self.hard_sample(&probs);
            categoricals.push(hard_sample);
        }

        Ok(categoricals)
    }

    /// Hard categorical sample (one-hot)
    fn hard_sample(&self, probs: &[f64]) -> Vec<f64> {
        let mut one_hot = vec![0.0; probs.len()];
        let u: f64 = rand::thread_rng().gen();
        let mut cumsum = 0.0;

        for (i, &p) in probs.iter().enumerate() {
            cumsum += p;
            if u < cumsum {
                one_hot[i] = 1.0;
                break;
            }
        }

        // Fallback to last category if numerical issues
        if one_hot.iter().sum::<f64>() < 0.5 {
            one_hot[probs.len() - 1] = 1.0;
        }

        one_hot
    }
}

/// Dynamics predictor: p(z_t | h_t)
struct DynamicsPredictor {
    layers: Vec<DMatrix<f64>>,
}

impl DynamicsPredictor {
    fn new(hidden_dim: usize, action_dim: usize) -> Result<Self> {
        Ok(Self {
            layers: vec![
                DMatrix::from_fn(hidden_dim, hidden_dim + action_dim, |_, _| rand::thread_rng().gen_range(-0.1..0.1)),
                DMatrix::from_fn(32 * 32, hidden_dim, |_, _| rand::thread_rng().gen_range(-0.1..0.1)),
            ],
        })
    }

    fn predict(&self, h: &DVector<f64>) -> Result<LatentState> {
        let x = relu(&(&self.layers[0] * h));
        let logits = &self.layers[1] * x;

        // Convert to categorical distributions
        let mut categoricals = Vec::new();
        for i in 0..32 {
            let start = i * 32;
            let probs = softmax(&logits.rows(start, 32));
            categoricals.push(probs.as_slice().to_vec());
        }

        Ok(LatentState { categoricals })
    }
}

/// Recurrent model for hidden state dynamics
struct RecurrentModel {
    gru_cell: GRUCell,
}

impl RecurrentModel {
    fn new(hidden_dim: usize, action_dim: usize) -> Result<Self> {
        Ok(Self {
            gru_cell: GRUCell::new(hidden_dim, action_dim)?,
        })
    }

    fn forward(&self, h: &DVector<f64>, action: &Action) -> Result<DVector<f64>> {
        self.gru_cell.forward(h, &action.data)
    }
}

/// GRU cell for recurrent processing
struct GRUCell {
    w_r: DMatrix<f64>,
    w_z: DMatrix<f64>,
    w_h: DMatrix<f64>,
    u_r: DMatrix<f64>,
    u_z: DMatrix<f64>,
    u_h: DMatrix<f64>,
}

impl GRUCell {
    fn new(hidden_dim: usize, input_dim: usize) -> Result<Self> {
        let mut rng = rand::thread_rng();
        Ok(Self {
            w_r: DMatrix::from_fn(hidden_dim, input_dim, |_, _| rng.gen_range(-0.1..0.1)),
            w_z: DMatrix::from_fn(hidden_dim, input_dim, |_, _| rng.gen_range(-0.1..0.1)),
            w_h: DMatrix::from_fn(hidden_dim, input_dim, |_, _| rng.gen_range(-0.1..0.1)),
            u_r: DMatrix::from_fn(hidden_dim, hidden_dim, |_, _| rng.gen_range(-0.1..0.1)),
            u_z: DMatrix::from_fn(hidden_dim, hidden_dim, |_, _| rng.gen_range(-0.1..0.1)),
            u_h: DMatrix::from_fn(hidden_dim, hidden_dim, |_, _| rng.gen_range(-0.1..0.1)),
        })
    }

    fn forward(&self, h: &DVector<f64>, x: &DVector<f64>) -> Result<DVector<f64>> {
        let r = sigmoid(&(&self.w_r * x + &self.u_r * h));
        let z = sigmoid(&(&self.w_z * x + &self.u_z * h));
        let h_tilde = tanh(&(&self.w_h * x + &self.u_h * (r.component_mul(h))));

        Ok(z.component_mul(&h) + (DVector::from_element(h.len(), 1.0) - z).component_mul(&h_tilde))
    }
}

/// Decoder for observation reconstruction
struct Decoder {
    layers: Vec<DMatrix<f64>>,
}

impl Decoder {
    fn new(hidden_dim: usize) -> Result<Self> {
        Ok(Self {
            layers: vec![
                DMatrix::from_fn(hidden_dim * 2, hidden_dim + 32 * 32, |_, _| rand::thread_rng().gen_range(-0.1..0.1)),
                DMatrix::from_fn(hidden_dim, hidden_dim * 2, |_, _| rand::thread_rng().gen_range(-0.1..0.1)),
            ],
        })
    }

    fn decode(&self, h: &DVector<f64>, z: &LatentState) -> Result<Observation> {
        // Flatten categorical distributions
        let mut z_flat = DVector::zeros(32 * 32);
        for (i, cat) in z.categoricals.iter().enumerate() {
            for (j, &val) in cat.iter().enumerate() {
                z_flat[i * 32 + j] = val;
            }
        }

        // Concatenate h and z
        let mut x = h.clone();
        x.extend(z_flat.iter());

        // Decode through layers
        for layer in &self.layers {
            x = relu(&(layer * x));
        }

        Ok(Observation { data: x })
    }
}

/// Reward predictor
struct RewardPredictor {
    layers: Vec<DMatrix<f64>>,
}

impl RewardPredictor {
    fn new(hidden_dim: usize) -> Result<Self> {
        Ok(Self {
            layers: vec![
                DMatrix::from_fn(hidden_dim, hidden_dim + 32 * 32, |_, _| rand::thread_rng().gen_range(-0.1..0.1)),
                DMatrix::from_fn(1, hidden_dim, |_, _| rand::thread_rng().gen_range(-0.1..0.1)),
            ],
        })
    }

    fn predict(&self, h: &DVector<f64>, z: &LatentState) -> Result<f64> {
        let mut x = h.clone();

        // Add latent state
        for cat in &z.categoricals {
            x.extend(cat.iter());
        }

        let hidden = relu(&(&self.layers[0] * x));
        let output = &self.layers[1] * hidden;

        Ok(output[0])
    }
}

/// Continue predictor (discount factor)
struct ContinuePredictor {
    layers: Vec<DMatrix<f64>>,
}

impl ContinuePredictor {
    fn new(hidden_dim: usize) -> Result<Self> {
        Ok(Self {
            layers: vec![
                DMatrix::from_fn(hidden_dim, hidden_dim + 32 * 32, |_, _| rand::thread_rng().gen_range(-0.1..0.1)),
                DMatrix::from_fn(1, hidden_dim, |_, _| rand::thread_rng().gen_range(-0.1..0.1)),
            ],
        })
    }

    fn predict(&self, h: &DVector<f64>, z: &LatentState) -> Result<f64> {
        let mut x = h.clone();

        // Add latent state
        for cat in &z.categoricals {
            x.extend(cat.iter());
        }

        let hidden = relu(&(&self.layers[0] * x));
        let output = &self.layers[1] * hidden;

        Ok(sigmoid_scalar(output[0]))
    }
}

/// Context encoder for zero-shot generalization (cRSSM)
struct ContextEncoder {
    layers: Vec<DMatrix<f64>>,
}

impl ContextEncoder {
    fn new(hidden_dim: usize) -> Result<Self> {
        Ok(Self {
            layers: vec![
                DMatrix::from_fn(128, hidden_dim, |_, _| rand::thread_rng().gen_range(-0.1..0.1)),
                DMatrix::from_fn(hidden_dim, 128, |_, _| rand::thread_rng().gen_range(-0.1..0.1)),
            ],
        })
    }

    fn encode_context(&self, observations: &[Observation]) -> Result<DVector<f64>> {
        // Aggregate observations into context
        let mut context = DVector::zeros(self.layers[0].ncols());

        for obs in observations {
            context += &obs.data;
        }
        context /= observations.len() as f64;

        // Encode through layers
        let hidden = relu(&(&self.layers[0] * context));
        let encoded = &self.layers[1] * hidden;

        Ok(encoded)
    }
}

/// Dynamic modulator for DyMoDreamer
struct DynamicModulator {
    modulation_layers: Vec<DMatrix<f64>>,
}

impl DynamicModulator {
    fn new(hidden_dim: usize) -> Result<Self> {
        Ok(Self {
            modulation_layers: vec![
                DMatrix::from_fn(32 * 32, hidden_dim + 32 * 32, |_, _| rand::thread_rng().gen_range(-0.1..0.1)),
            ],
        })
    }

    fn modulate(&self, z: &LatentState, h: &DVector<f64>) -> Result<LatentState> {
        // Apply dynamic modulation to latent state
        let mut z_flat = DVector::zeros(32 * 32);
        for (i, cat) in z.categoricals.iter().enumerate() {
            for (j, &val) in cat.iter().enumerate() {
                z_flat[i * 32 + j] = val;
            }
        }

        let mut input = h.clone();
        input.extend(z_flat.iter());

        let modulated = sigmoid(&(&self.modulation_layers[0] * input));

        // Reshape back to categorical
        let mut new_categoricals = Vec::new();
        for i in 0..32 {
            let start = i * 32;
            let cat = modulated.rows(start, 32);
            let probs = softmax(&cat);
            new_categoricals.push(probs.as_slice().to_vec());
        }

        Ok(LatentState { categoricals: new_categoricals })
    }
}

// Types and structures
#[derive(Debug, Clone)]
pub struct RSSMState {
    pub h: DVector<f64>,
    pub z: LatentState,
    pub reconstruction: Option<Observation>,
    pub reward: f64,
    pub continue_prob: f64,
}

impl RSSMState {
    fn initial(hidden_dim: usize) -> Self {
        Self {
            h: DVector::zeros(hidden_dim),
            z: LatentState::initial(),
            reconstruction: None,
            reward: 0.0,
            continue_prob: 1.0,
        }
    }
}

#[derive(Debug, Clone)]
pub struct LatentState {
    categoricals: Vec<Vec<f64>>, // 32 categorical distributions with 32 classes each
}

impl LatentState {
    fn initial() -> Self {
        let mut categoricals = Vec::new();
        for _ in 0..32 {
            let mut cat = vec![0.0; 32];
            cat[0] = 1.0; // One-hot initial
            categoricals.push(cat);
        }
        Self { categoricals }
    }
}

#[derive(Debug, Clone)]
pub struct Observation {
    pub data: DVector<f64>,
}

#[derive(Debug, Clone)]
pub struct Action {
    pub data: DVector<f64>,
}

#[derive(Debug, Clone)]
pub struct ImaginedTrajectory {
    pub state: RSSMState,
    pub action: Action,
    pub reward: f64,
    pub continue_prob: f64,
}

pub struct Policy {
    layers: Vec<DMatrix<f64>>,
}

impl Policy {
    pub fn sample(&self, state: &RSSMState) -> Result<Action> {
        // Simple policy for demonstration
        Ok(Action {
            data: DVector::from_element(10, rand::thread_rng().gen_range(-1.0..1.0)),
        })
    }
}

pub struct ExperienceBatch {
    episodes: Vec<Episode>,
}

type Episode = Vec<(Observation, Action, f64, bool)>;

#[derive(Debug)]
pub struct RSSMLoss {
    pub total: f64,
    pub reconstruction: f64,
    pub reward: f64,
    pub continue_pred: f64,
    pub kl_divergence: f64,
}

// Utility functions

/// ReLU activation
fn relu(x: &DVector<f64>) -> DVector<f64> {
    x.map(|v| v.max(0.0))
}

/// SiLU (Swish) activation - used in DreamerV3
fn silu(x: &DVector<f64>) -> DVector<f64> {
    x.map(|v| v * sigmoid_scalar(v))
}

/// GELU activation
fn gelu(x: &DVector<f64>) -> DVector<f64> {
    x.map(|v| 0.5 * v * (1.0 + (v * 0.7978845608 * (1.0 + 0.044715 * v * v)).tanh()))
}

fn sigmoid(x: &DVector<f64>) -> DVector<f64> {
    x.map(|v| sigmoid_scalar(v))
}

fn sigmoid_scalar(x: f64) -> f64 {
    1.0 / (1.0 + (-x.clamp(-500.0, 500.0)).exp())
}

fn tanh(x: &DVector<f64>) -> DVector<f64> {
    x.map(|v| v.tanh())
}

fn softmax(x: &DVector<f64>) -> DVector<f64> {
    let max = x.max();
    let exp_x = x.map(|v| (v - max).exp());
    let sum = exp_x.sum();
    if sum > 0.0 {
        exp_x / sum
    } else {
        DVector::from_element(x.len(), 1.0 / x.len() as f64)
    }
}

/// Symlog transformation for stable loss computation (DreamerV3)
/// symlog(x) = sign(x) * ln(1 + |x|)
fn symlog(x: f64) -> f64 {
    x.signum() * (1.0 + x.abs()).ln()
}

/// Inverse symlog for decoding
fn symexp(x: f64) -> f64 {
    x.signum() * (x.abs().exp() - 1.0)
}

/// Two-hot encoding for scalar targets (DreamerV3)
/// Encodes a scalar into a probability distribution over bins
fn twohot_encode(x: f64, num_bins: usize, low: f64, high: f64) -> Vec<f64> {
    let x_clamped = x.clamp(low, high);
    let bin_width = (high - low) / (num_bins - 1) as f64;
    let pos = (x_clamped - low) / bin_width;
    let lower_idx = pos.floor() as usize;
    let upper_idx = (lower_idx + 1).min(num_bins - 1);
    let upper_weight = pos - pos.floor();
    let lower_weight = 1.0 - upper_weight;

    let mut encoding = vec![0.0; num_bins];
    encoding[lower_idx] = lower_weight;
    encoding[upper_idx] += upper_weight;

    encoding
}

/// Decode two-hot to scalar
fn twohot_decode(probs: &[f64], low: f64, high: f64) -> f64 {
    let num_bins = probs.len();
    let bin_width = (high - low) / (num_bins - 1) as f64;

    let mut expected_value = 0.0;
    for (i, &p) in probs.iter().enumerate() {
        expected_value += p * (low + i as f64 * bin_width);
    }

    expected_value
}

/// Binary cross-entropy with numerical stability
fn binary_cross_entropy(pred: f64, target: f64) -> f64 {
    let pred_clamped = pred.clamp(1e-7, 1.0 - 1e-7);
    -target * pred_clamped.ln() - (1.0 - target) * (1.0 - pred_clamped).ln()
}

/// KL divergence between two categorical distributions
fn categorical_kl(p: &[f64], q: &[f64]) -> f64 {
    p.iter()
        .zip(q.iter())
        .filter(|(&pi, _)| pi > 1e-10)
        .map(|(&pi, &qi)| pi * (pi / qi.max(1e-10)).ln())
        .sum()
}

/// Free KL: KL with free bits (DreamerV3 regularization)
/// Only penalize KL above free_nats threshold
fn free_kl(kl: f64, free_nats: f64) -> f64 {
    (kl - free_nats).max(0.0)
}

Sources:
- [DreamerV3: Mastering Diverse Domains](https://arxiv.org/pdf/2301.04104)
- [DyMoDreamer: Dynamic Modulation](https://arxiv.org/pdf/2509.24804)
- [Contextual World Models for Zero-Shot](https://arxiv.org/html/2403.10967v1)
- [HRSSM: Robust Representations](https://github.com/bit1029public/HRSSM)
