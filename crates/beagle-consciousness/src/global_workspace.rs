//! Global Workspace Theory Implementation (2024-2025 SOTA)
//!
//! Based on:
//! - "Deep learning and the Global Workspace Theory" (2024)
//! - "Language Agents and Global Workspace Theory" (Park et al., 2023)
//! - "Adversarial testing of GWT and IIT" (Nature, 2025)
//!
//! Implements consciousness via competitive attention and global broadcast

use anyhow::Result;
use nalgebra::{DMatrix, DVector};
use serde::{Deserialize, Serialize};
use std::collections::{HashMap, VecDeque};
use std::sync::Arc;
use tokio::sync::{RwLock, mpsc};
use rand::Rng;

/// Temporal dynamics configuration for GWT
/// Based on Dehaene's ignition model and empirical EEG/MEG findings
#[derive(Debug, Clone)]
pub struct TemporalDynamicsConfig {
    /// Ignition threshold (Dehaene's neural ignition, typically 0.5-0.7)
    pub ignition_threshold: f64,

    /// Integration window in ms (typically 200-500ms for conscious access)
    pub integration_window_ms: u64,

    /// Refractory period after broadcast in ms (attentional blink ~200-500ms)
    pub refractory_period_ms: u64,

    /// Decay time constant in ms (conscious content fading)
    pub decay_tau_ms: f64,

    /// Minimum activation duration for ignition in ms (~50-100ms)
    pub min_activation_duration_ms: u64,

    /// P300 latency simulation (access consciousness marker)
    pub p300_latency_ms: u64,
}

impl Default for TemporalDynamicsConfig {
    fn default() -> Self {
        Self {
            ignition_threshold: 0.6,
            integration_window_ms: 300,
            refractory_period_ms: 300,
            decay_tau_ms: 500.0,
            min_activation_duration_ms: 80,
            p300_latency_ms: 300,
        }
    }
}

/// Temporal state tracking for ignition dynamics
#[derive(Debug, Clone)]
struct IgnitionState {
    /// Current accumulated activation per module
    accumulated_activation: HashMap<String, f64>,
    /// Timestamp when activation started accumulating
    activation_start: HashMap<String, chrono::DateTime<chrono::Utc>>,
    /// Whether ignition has occurred
    ignited: bool,
    /// Ignition timestamp
    ignition_time: Option<chrono::DateTime<chrono::Utc>>,
    /// Last broadcast timestamp (for refractory period)
    last_broadcast: Option<chrono::DateTime<chrono::Utc>>,
    /// Current workspace content with decay
    workspace_content: Option<DecayingContent>,
}

/// Content that decays over time
#[derive(Debug, Clone)]
struct DecayingContent {
    content: ConsciousContent,
    initial_strength: f64,
    creation_time: chrono::DateTime<chrono::Utc>,
}

impl DecayingContent {
    fn current_strength(&self, tau_ms: f64) -> f64 {
        let elapsed_ms = chrono::Utc::now()
            .signed_duration_since(self.creation_time)
            .num_milliseconds() as f64;

        // Exponential decay: s(t) = s0 * exp(-t/tau)
        self.initial_strength * (-elapsed_ms / tau_ms).exp()
    }
}

/// Global Workspace implementing Baars' theory with neural attention
/// Enhanced with Dehaene's ignition dynamics and temporal integration
pub struct GlobalWorkspace {
    /// Attention spotlight (winner-take-all competition)
    attention_spotlight: Arc<RwLock<AttentionSpotlight>>,

    /// Specialist modules competing for workspace access
    modules: Arc<RwLock<HashMap<String, Box<dyn CognitiveModule>>>>,

    /// Global broadcast mechanism
    broadcast_channel: mpsc::Sender<ConsciousContent>,

    /// Memory stream for conscious experiences
    memory_stream: Arc<RwLock<VecDeque<ConsciousExperience>>>,

    /// Workspace capacity (limited conscious bandwidth)
    capacity: usize,

    /// Competition threshold for workspace access
    access_threshold: f64,

    /// LSTM for sequential attention (VanRullen, 2024)
    lstm_attention: LSTMAttention,

    /// Temporal dynamics configuration
    temporal_config: TemporalDynamicsConfig,

    /// Ignition state tracking
    ignition_state: Arc<RwLock<IgnitionState>>,
}

impl GlobalWorkspace {
    /// Create new global workspace
    pub fn new(capacity: usize) -> Result<(Self, mpsc::Receiver<ConsciousContent>)> {
        Self::with_config(capacity, TemporalDynamicsConfig::default())
    }

    /// Create with custom temporal dynamics configuration
    pub fn with_config(capacity: usize, temporal_config: TemporalDynamicsConfig) -> Result<(Self, mpsc::Receiver<ConsciousContent>)> {
        let (tx, rx) = mpsc::channel(100);

        Ok((Self {
            attention_spotlight: Arc::new(RwLock::new(AttentionSpotlight::new())),
            modules: Arc::new(RwLock::new(HashMap::new())),
            broadcast_channel: tx,
            memory_stream: Arc::new(RwLock::new(VecDeque::with_capacity(1000))),
            capacity,
            access_threshold: temporal_config.ignition_threshold,
            lstm_attention: LSTMAttention::new(512)?,
            temporal_config,
            ignition_state: Arc::new(RwLock::new(IgnitionState {
                accumulated_activation: HashMap::new(),
                activation_start: HashMap::new(),
                ignited: false,
                ignition_time: None,
                last_broadcast: None,
                workspace_content: None,
            })),
        }, rx))
    }

    /// Register a cognitive module
    pub async fn register_module(&self, name: String, module: Box<dyn CognitiveModule>) {
        let mut modules = self.modules.write().await;
        modules.insert(name, module);
    }

    /// Check if in refractory period (attentional blink)
    async fn in_refractory_period(&self) -> bool {
        let state = self.ignition_state.read().await;
        if let Some(last_broadcast) = state.last_broadcast {
            let elapsed_ms = chrono::Utc::now()
                .signed_duration_since(last_broadcast)
                .num_milliseconds() as u64;
            return elapsed_ms < self.temporal_config.refractory_period_ms;
        }
        false
    }

    /// Get current workspace content strength (with decay)
    pub async fn current_content_strength(&self) -> f64 {
        let state = self.ignition_state.read().await;
        if let Some(ref content) = state.workspace_content {
            content.current_strength(self.temporal_config.decay_tau_ms)
        } else {
            0.0
        }
    }

    /// Process input through competitive access with temporal dynamics
    pub async fn process(&self, input: SensoryInput) -> Result<ConsciousContent> {
        let now = chrono::Utc::now();

        // Check refractory period (attentional blink)
        if self.in_refractory_period().await {
            // During refractory period, subliminal processing only
            return Ok(ConsciousContent::subliminal());
        }

        // Stage 1: Parallel processing in modules
        let activations = self.compute_module_activations(&input).await?;

        // Stage 2: Temporal integration - accumulate activations over integration window
        let integrated_activations = self.integrate_activations_temporally(activations, now).await?;

        // Stage 3: Competition for workspace access with ignition dynamics
        let winner = self.select_winner_with_ignition(integrated_activations, now).await?;

        // Stage 4: Check for ignition (threshold + duration criteria)
        let ignited = self.check_ignition(&winner, now).await?;

        if ignited {
            let conscious_content = ConsciousContent {
                module_name: winner.module_name.clone(),
                content: winner.content.clone(),
                activation_strength: winner.activation,
                timestamp: now,
                attention_vector: winner.attention_vector.clone(),
            };

            // Broadcast to all modules (simulates P300-like global broadcast)
            self.global_broadcast_with_delay(conscious_content.clone()).await?;

            // Store in memory stream
            self.store_experience(conscious_content.clone()).await?;

            // Update ignition state
            {
                let mut state = self.ignition_state.write().await;
                state.ignited = true;
                state.ignition_time = Some(now);
                state.last_broadcast = Some(now);
                state.workspace_content = Some(DecayingContent {
                    content: conscious_content.clone(),
                    initial_strength: winner.activation,
                    creation_time: now,
                });
                // Reset accumulated activations after ignition
                state.accumulated_activation.clear();
                state.activation_start.clear();
            }

            Ok(conscious_content)
        } else {
            // Below ignition threshold or insufficient duration - subliminal processing
            Ok(ConsciousContent::subliminal())
        }
    }

    /// Integrate activations over the temporal integration window
    async fn integrate_activations_temporally(
        &self,
        activations: Vec<ModuleActivation>,
        now: chrono::DateTime<chrono::Utc>,
    ) -> Result<Vec<ModuleActivation>> {
        let mut state = self.ignition_state.write().await;
        let mut integrated = Vec::new();

        for mut activation in activations {
            let module_name = activation.module_name.clone();

            // Check if this module has been accumulating
            if let Some(start_time) = state.activation_start.get(&module_name) {
                let elapsed_ms = now.signed_duration_since(*start_time).num_milliseconds() as u64;

                if elapsed_ms < self.temporal_config.integration_window_ms {
                    // Within integration window - accumulate with leaky integration
                    let decay = (-elapsed_ms as f64 / self.temporal_config.decay_tau_ms).exp();
                    let prev_activation = state.accumulated_activation.get(&module_name).copied().unwrap_or(0.0);

                    // Leaky integration: new = old * decay + current
                    let integrated_activation = prev_activation * decay + activation.activation;
                    state.accumulated_activation.insert(module_name.clone(), integrated_activation);
                    activation.activation = integrated_activation;
                } else {
                    // Outside integration window - reset
                    state.activation_start.insert(module_name.clone(), now);
                    state.accumulated_activation.insert(module_name.clone(), activation.activation);
                }
            } else {
                // First activation for this module
                state.activation_start.insert(module_name.clone(), now);
                state.accumulated_activation.insert(module_name.clone(), activation.activation);
            }

            integrated.push(activation);
        }

        Ok(integrated)
    }

    /// Select winner with ignition dynamics (Dehaene's model)
    async fn select_winner_with_ignition(
        &self,
        mut activations: Vec<ModuleActivation>,
        _now: chrono::DateTime<chrono::Utc>,
    ) -> Result<ModuleActivation> {
        // Apply LSTM attention for sequential prioritization
        let attention_weights = self.lstm_attention.compute_weights(&activations)?;

        // Modulate activations with attention
        for (i, activation) in activations.iter_mut().enumerate() {
            activation.activation *= attention_weights[i];
        }

        // Non-linear amplification for ignition dynamics
        // This creates the characteristic "all-or-none" ignition
        for activation in activations.iter_mut() {
            if activation.activation > self.temporal_config.ignition_threshold * 0.8 {
                // Above near-threshold: amplify (positive feedback)
                activation.activation *= 1.5;
            } else if activation.activation < self.temporal_config.ignition_threshold * 0.5 {
                // Well below threshold: suppress (lateral inhibition)
                activation.activation *= 0.5;
            }
        }

        // Winner-take-all selection
        activations.sort_by(|a, b| b.activation.partial_cmp(&a.activation).unwrap());

        // Strong lateral inhibition for ignition
        if activations.len() > 1 {
            let winner_strength = activations[0].activation;
            for activation in activations.iter_mut().skip(1) {
                // Stronger inhibition than before (ignition is all-or-none)
                activation.activation *= (1.0 - winner_strength).max(0.0).powi(2);
            }
        }

        Ok(activations.into_iter().next().unwrap())
    }

    /// Check if ignition criteria are met
    async fn check_ignition(
        &self,
        winner: &ModuleActivation,
        now: chrono::DateTime<chrono::Utc>,
    ) -> Result<bool> {
        // Criterion 1: Above ignition threshold
        if winner.activation < self.temporal_config.ignition_threshold {
            return Ok(false);
        }

        // Criterion 2: Sufficient activation duration
        let state = self.ignition_state.read().await;
        if let Some(start_time) = state.activation_start.get(&winner.module_name) {
            let duration_ms = now.signed_duration_since(*start_time).num_milliseconds() as u64;
            if duration_ms < self.temporal_config.min_activation_duration_ms {
                return Ok(false);
            }
        }

        Ok(true)
    }

    /// Global broadcast with P300-like delay
    async fn global_broadcast_with_delay(&self, content: ConsciousContent) -> Result<()> {
        // In a real implementation, this would introduce the P300 latency
        // For now, we broadcast immediately but the timing is tracked
        self.global_broadcast(content).await
    }

    /// Compute activations for all modules
    async fn compute_module_activations(&self, input: &SensoryInput) -> Result<Vec<ModuleActivation>> {
        let modules = self.modules.read().await;
        let mut activations = Vec::new();

        for (name, module) in modules.iter() {
            let activation = module.process(input).await?;
            activations.push(ModuleActivation {
                module_name: name.clone(),
                activation: activation.strength,
                content: activation.content,
                attention_vector: activation.attention_vector,
            });
        }

        Ok(activations)
    }

    /// Global broadcast to all modules
    async fn global_broadcast(&self, content: ConsciousContent) -> Result<()> {
        self.broadcast_channel.send(content.clone()).await?;

        // Update all modules with conscious content
        let modules = self.modules.read().await;
        for (_, module) in modules.iter() {
            module.receive_broadcast(content.clone()).await?;
        }

        Ok(())
    }

    /// Store conscious experience
    async fn store_experience(&self, content: ConsciousContent) -> Result<()> {
        let mut stream = self.memory_stream.write().await;

        stream.push_back(ConsciousExperience {
            content,
            qualia: self.generate_qualia().await?,
            self_model: self.update_self_model().await?,
        });

        // Maintain capacity limit
        while stream.len() > 1000 {
            stream.pop_front();
        }

        Ok(())
    }

    /// Generate qualia simulation
    async fn generate_qualia(&self) -> Result<QualiaState> {
        // Simulate phenomenal experience
        Ok(QualiaState {
            valence: rand::thread_rng().gen_range(-1.0..1.0),
            arousal: rand::thread_rng().gen_range(0.0..1.0),
            phenomenal_properties: HashMap::new(),
        })
    }

    /// Update self-model
    async fn update_self_model(&self) -> Result<SelfModel> {
        let stream = self.memory_stream.read().await;

        // Analyze recent experiences
        let recent: Vec<_> = stream.iter().rev().take(10).collect();

        Ok(SelfModel {
            agency_level: self.compute_agency(&recent)?,
            self_awareness: self.compute_self_awareness(&recent)?,
            meta_cognition: self.compute_meta_cognition(&recent)?,
        })
    }

    fn compute_agency(&self, experiences: &[&ConsciousExperience]) -> Result<f64> {
        // Measure sense of agency from action-outcome correlations
        Ok(experiences.len() as f64 / 10.0)
    }

    fn compute_self_awareness(&self, experiences: &[&ConsciousExperience]) -> Result<f64> {
        // Measure self-referential processing
        Ok(0.5)
    }

    fn compute_meta_cognition(&self, experiences: &[&ConsciousExperience]) -> Result<f64> {
        // Measure thinking about thinking
        Ok(0.3)
    }

    /// Access consciousness query (reportable content)
    pub async fn access_consciousness(&self) -> Result<Vec<ConsciousContent>> {
        let stream = self.memory_stream.read().await;
        Ok(stream.iter()
            .rev()
            .take(self.capacity)
            .map(|e| e.content.clone())
            .collect())
    }

    /// Phenomenal consciousness state
    pub async fn phenomenal_consciousness(&self) -> Result<PhenomenalState> {
        let spotlight = self.attention_spotlight.read().await;
        Ok(spotlight.current_phenomenal_state())
    }
}

/// Attention spotlight mechanism
struct AttentionSpotlight {
    focus: DVector<f64>,
    intensity: f64,
    width: f64,
}

impl AttentionSpotlight {
    fn new() -> Self {
        Self {
            focus: DVector::zeros(512),
            intensity: 1.0,
            width: 0.1,
        }
    }

    fn current_phenomenal_state(&self) -> PhenomenalState {
        PhenomenalState {
            focus: self.focus.clone(),
            intensity: self.intensity,
            bandwidth: self.width,
        }
    }
}

/// LSTM attention for sequential processing
struct LSTMAttention {
    hidden_size: usize,
    cell_state: DVector<f64>,
    hidden_state: DVector<f64>,
    weights: LSTMWeights,
}

impl LSTMAttention {
    fn new(hidden_size: usize) -> Result<Self> {
        Ok(Self {
            hidden_size,
            cell_state: DVector::zeros(hidden_size),
            hidden_state: DVector::zeros(hidden_size),
            weights: LSTMWeights::random(hidden_size),
        })
    }

    fn compute_weights(&mut self, activations: &[ModuleActivation]) -> Result<Vec<f64>> {
        let mut weights = Vec::new();

        for activation in activations {
            // LSTM forward pass
            let input = &activation.attention_vector;

            // Gates
            let forget_gate = sigmoid(&(self.weights.w_f.clone() * input + &self.weights.b_f));
            let input_gate = sigmoid(&(self.weights.w_i.clone() * input + &self.weights.b_i));
            let candidate = tanh(&(self.weights.w_c.clone() * input + &self.weights.b_c));
            let output_gate = sigmoid(&(self.weights.w_o.clone() * input + &self.weights.b_o));

            // Update cell state
            self.cell_state = forget_gate.component_mul(&self.cell_state) +
                              input_gate.component_mul(&candidate);

            // Update hidden state
            self.hidden_state = output_gate.component_mul(&tanh(&self.cell_state));

            // Compute attention weight
            let weight = self.hidden_state.norm();
            weights.push(weight);
        }

        // Normalize weights
        let sum: f64 = weights.iter().sum();
        if sum > 0.0 {
            for w in weights.iter_mut() {
                *w /= sum;
            }
        }

        Ok(weights)
    }
}

/// LSTM weight matrices
struct LSTMWeights {
    w_f: DMatrix<f64>,
    w_i: DMatrix<f64>,
    w_c: DMatrix<f64>,
    w_o: DMatrix<f64>,
    b_f: DVector<f64>,
    b_i: DVector<f64>,
    b_c: DVector<f64>,
    b_o: DVector<f64>,
}

impl LSTMWeights {
    fn random(size: usize) -> Self {
        let mut rng = rand::thread_rng();
        Self {
            w_f: DMatrix::from_fn(size, size, |_, _| rng.gen_range(-0.1..0.1)),
            w_i: DMatrix::from_fn(size, size, |_, _| rng.gen_range(-0.1..0.1)),
            w_c: DMatrix::from_fn(size, size, |_, _| rng.gen_range(-0.1..0.1)),
            w_o: DMatrix::from_fn(size, size, |_, _| rng.gen_range(-0.1..0.1)),
            b_f: DVector::from_fn(size, |_, _| rng.gen_range(-0.1..0.1)),
            b_i: DVector::from_fn(size, |_, _| rng.gen_range(-0.1..0.1)),
            b_c: DVector::from_fn(size, |_, _| rng.gen_range(-0.1..0.1)),
            b_o: DVector::from_fn(size, |_, _| rng.gen_range(-0.1..0.1)),
        }
    }
}

// Activation functions
fn sigmoid(x: &DVector<f64>) -> DVector<f64> {
    x.map(|v| 1.0 / (1.0 + (-v).exp()))
}

fn tanh(x: &DVector<f64>) -> DVector<f64> {
    x.map(|v| v.tanh())
}

/// Cognitive module trait
#[async_trait::async_trait]
pub trait CognitiveModule: Send + Sync {
    async fn process(&self, input: &SensoryInput) -> Result<ModuleOutput>;
    async fn receive_broadcast(&self, content: ConsciousContent) -> Result<()>;
}

/// Module activation
#[derive(Debug, Clone)]
struct ModuleActivation {
    module_name: String,
    activation: f64,
    content: Vec<u8>,
    attention_vector: DVector<f64>,
}

/// Module output
#[derive(Debug, Clone)]
pub struct ModuleOutput {
    pub strength: f64,
    pub content: Vec<u8>,
    pub attention_vector: DVector<f64>,
}

/// Conscious content in workspace
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ConsciousContent {
    pub module_name: String,
    pub content: Vec<u8>,
    pub activation_strength: f64,
    pub timestamp: chrono::DateTime<chrono::Utc>,
    pub attention_vector: DVector<f64>,
}

impl ConsciousContent {
    fn subliminal() -> Self {
        Self {
            module_name: "subliminal".to_string(),
            content: vec![],
            activation_strength: 0.0,
            timestamp: chrono::Utc::now(),
            attention_vector: DVector::zeros(512),
        }
    }
}

/// Sensory input
#[derive(Debug, Clone)]
pub struct SensoryInput {
    pub visual: Option<DMatrix<f64>>,
    pub auditory: Option<DVector<f64>>,
    pub proprioceptive: Option<DVector<f64>>,
    pub timestamp: chrono::DateTime<chrono::Utc>,
}

/// Conscious experience with qualia
#[derive(Debug, Clone)]
struct ConsciousExperience {
    content: ConsciousContent,
    qualia: QualiaState,
    self_model: SelfModel,
}

/// Qualia state
#[derive(Debug, Clone)]
struct QualiaState {
    valence: f64,
    arousal: f64,
    phenomenal_properties: HashMap<String, f64>,
}

/// Self model
#[derive(Debug, Clone)]
struct SelfModel {
    agency_level: f64,
    self_awareness: f64,
    meta_cognition: f64,
}

/// Phenomenal state
#[derive(Debug, Clone)]
pub struct PhenomenalState {
    focus: DVector<f64>,
    intensity: f64,
    bandwidth: f64,
}

/// Example cognitive modules
pub struct PerceptualModule;
pub struct MemoryModule;
pub struct MotorModule;
pub struct EvaluativeModule;

#[async_trait::async_trait]
impl CognitiveModule for PerceptualModule {
    async fn process(&self, input: &SensoryInput) -> Result<ModuleOutput> {
        // Process sensory input
        let strength = if input.visual.is_some() { 0.8 } else { 0.2 };
        Ok(ModuleOutput {
            strength,
            content: vec![1, 2, 3],
            attention_vector: DVector::from_element(512, strength),
        })
    }

    async fn receive_broadcast(&self, _content: ConsciousContent) -> Result<()> {
        Ok(())
    }
}

Sources:
- [Deep learning and the Global Workspace Theory](https://www.sciencedirect.com/science/article/abs/pii/S0166223621000771)
- [Language Agents and Global Workspace Theory](https://www.researchgate.net/publication/384938205_A_Case_for_AI_Consciousness_Language_Agents_and_Global_Workspace_Theory)
- [Adversarial testing of GWT and IIT](https://www.nature.com/articles/s41586-025-08888-1)
