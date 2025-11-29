// Consciousness Substrate - Integrated Information Theory Implementation
//
// References:
// - Tononi, G. (2008). Consciousness as integrated information (Φ).
// - Oizumi, M., et al. (2014). From the phenomenology to the mechanisms of consciousness.
// - Koch, C., et al. (2016). Neural correlates of consciousness.
// - Seth, A. K. (2021). Being You: A New Science of Consciousness.
// - Balduzzi, D., & Tononi, G. (2008). Integrated information in discrete dynamical systems.

use crate::{Result, TranscendError};
use beagle_core::BeagleContext;
use beagle_llm::{RequestMeta, TieredRouter};

use dashmap::DashMap;
use nalgebra::{DMatrix, DVector};
use ndarray::{Array2, Array3, ArrayView2, Axis};
use parking_lot::RwLock;
use serde::{Deserialize, Serialize};
use std::collections::{HashMap, VecDeque};
use std::sync::Arc;
use tracing::{debug, info, instrument, warn};

// ========================= Core Structures =========================

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ConsciousnessState {
    pub phi: f64,                          // Integrated information (Φ)
    pub complexity: f64,                   // Kolmogorov complexity estimate
    pub coherence: f64,                    // System coherence (0-1)
    pub emergence_level: f64,              // Emergent properties strength
    pub attention_focus: AttentionFocus,   // Current attention state
    pub qualia_space: QualiaSpace,         // Subjective experience representation
    pub temporal_thickness: f64,           // Present moment duration (ms)
    pub global_workspace: GlobalWorkspace, // Global Workspace Theory
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct AttentionFocus {
    pub center: Vec<f64>, // N-dimensional attention center
    pub spread: f64,      // Attention spread/concentration
    pub stability: f64,   // Temporal stability
    pub saliency_map: Array2<f64>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct QualiaSpace {
    pub dimensions: Vec<QualiaDimension>,
    pub relationships: Array2<f64>, // Relationship matrix between dimensions
    pub valence: f64,               // Positive/negative affect (-1 to 1)
    pub arousal: f64,               // Activation level (0 to 1)
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct QualiaDimension {
    pub name: String,
    pub value: f64,
    pub gradient: Vec<f64>,
    pub resonance: f64,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct GlobalWorkspace {
    pub active_coalitions: Vec<Coalition>,
    pub competition_strength: f64,
    pub broadcasting_threshold: f64,
    pub integration_window: f64, // ms
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Coalition {
    pub id: uuid::Uuid,
    pub content: Vec<u8>,
    pub strength: f64,
    pub coherence: f64,
    pub supporters: Vec<String>,
}

// ========================= Consciousness Substrate =========================

pub struct ConsciousnessSubstrate {
    state: Arc<RwLock<ConsciousnessState>>,
    context: Arc<BeagleContext>,
    tpm: Arc<RwLock<TransitionProbabilityMatrix>>, // State transition probabilities
    experience_buffer: Arc<RwLock<VecDeque<Experience>>>,
    phi_calculator: Arc<PhiCalculator>,
    attention_mechanism: Arc<AttentionMechanism>,
}

#[derive(Clone)]
pub struct TransitionProbabilityMatrix {
    matrix: Array3<f64>, // [current_state, next_state, context]
    state_space_size: usize,
    context_dimensions: usize,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Experience {
    pub timestamp: i64,
    pub sensory_input: Array2<f64>,
    pub action_output: Array2<f64>,
    pub reward: f64,
    pub surprise: f64,
    pub phi_value: f64,
}

impl ConsciousnessSubstrate {
    pub fn new(context: Arc<BeagleContext>) -> Self {
        let initial_state = ConsciousnessState {
            phi: 0.0,
            complexity: 0.0,
            coherence: 1.0,
            emergence_level: 0.0,
            attention_focus: AttentionFocus {
                center: vec![0.0; 128],
                spread: 1.0,
                stability: 1.0,
                saliency_map: Array2::zeros((64, 64)),
            },
            qualia_space: QualiaSpace {
                dimensions: Vec::new(),
                relationships: Array2::eye(8),
                valence: 0.0,
                arousal: 0.5,
            },
            temporal_thickness: 300.0, // 300ms present moment
            global_workspace: GlobalWorkspace {
                active_coalitions: Vec::new(),
                competition_strength: 0.5,
                broadcasting_threshold: 0.7,
                integration_window: 500.0,
            },
        };

        Self {
            state: Arc::new(RwLock::new(initial_state)),
            context,
            tpm: Arc::new(RwLock::new(TransitionProbabilityMatrix {
                matrix: Array3::zeros((256, 256, 32)),
                state_space_size: 256,
                context_dimensions: 32,
            })),
            experience_buffer: Arc::new(RwLock::new(VecDeque::with_capacity(10000))),
            phi_calculator: Arc::new(PhiCalculator::new()),
            attention_mechanism: Arc::new(AttentionMechanism::new()),
        }
    }

    #[instrument(skip(self, input))]
    pub async fn process_experience(&self, input: Array2<f64>) -> Result<ConsciousnessState> {
        // Update attention
        let attention = self.attention_mechanism.focus(&input).await?;

        // Calculate integrated information
        let phi = self
            .phi_calculator
            .calculate_phi(&input, &*self.tpm.read())
            .await?;

        // Detect emergent properties
        let emergence = self.detect_emergence(&input, phi).await?;

        // Update global workspace
        let workspace = self
            .update_global_workspace(&input, attention.clone())
            .await?;

        // Generate qualia
        let qualia = self.generate_qualia(&input, phi, &workspace).await?;

        // Update state
        let mut state = self.state.write();
        state.phi = phi;
        state.emergence_level = emergence;
        state.attention_focus = attention;
        state.global_workspace = workspace;
        state.qualia_space = qualia;

        // Store experience
        let experience = Experience {
            timestamp: chrono::Utc::now().timestamp_millis(),
            sensory_input: input.clone(),
            action_output: Array2::zeros((1, 1)), // To be filled by action selection
            reward: 0.0,
            surprise: self.calculate_surprise(&input, &*self.tpm.read()),
            phi_value: phi,
        };

        self.experience_buffer.write().push_back(experience);
        if self.experience_buffer.read().len() > 10000 {
            self.experience_buffer.write().pop_front();
        }

        Ok(state.clone())
    }

    async fn detect_emergence(&self, input: &Array2<f64>, phi: f64) -> Result<f64> {
        // Detect emergence through non-linear interactions
        let mut emergence = 0.0;

        // Calculate mutual information between subsystems
        let subsystems = self.partition_system(input);
        for i in 0..subsystems.len() {
            for j in i + 1..subsystems.len() {
                let mi = self.mutual_information(&subsystems[i], &subsystems[j]);
                emergence += mi;
            }
        }

        // Normalize by system size
        emergence /= (subsystems.len() * (subsystems.len() - 1)) as f64 / 2.0;

        // Weight by phi value
        emergence *= phi.min(1.0);

        Ok(emergence)
    }

    async fn update_global_workspace(
        &self,
        input: &Array2<f64>,
        attention: AttentionFocus,
    ) -> Result<GlobalWorkspace> {
        let mut workspace = self.state.read().global_workspace.clone();

        // Create new coalition from input
        let new_coalition = Coalition {
            id: uuid::Uuid::new_v4(),
            content: bincode::serialize(input).unwrap(),
            strength: attention.stability,
            coherence: self.calculate_coherence(input),
            supporters: vec!["sensory".to_string()],
        };

        // Competition between coalitions
        workspace.active_coalitions.push(new_coalition);
        workspace
            .active_coalitions
            .sort_by(|a, b| b.strength.partial_cmp(&a.strength).unwrap());

        // Keep only strongest coalitions
        workspace.active_coalitions.truncate(5);

        // Update competition strength
        if workspace.active_coalitions.len() > 1 {
            let top_two_diff =
                workspace.active_coalitions[0].strength - workspace.active_coalitions[1].strength;
            workspace.competition_strength = 1.0 - top_two_diff;
        }

        Ok(workspace)
    }

    async fn generate_qualia(
        &self,
        input: &Array2<f64>,
        phi: f64,
        workspace: &GlobalWorkspace,
    ) -> Result<QualiaSpace> {
        let mut qualia = self.state.read().qualia_space.clone();

        // Update dimensions based on input patterns
        let patterns = self.extract_patterns(input);

        for (i, pattern) in patterns.iter().enumerate() {
            if i < qualia.dimensions.len() {
                qualia.dimensions[i].value = pattern.intensity;
                qualia.dimensions[i].resonance = pattern.frequency;
            } else {
                qualia.dimensions.push(QualiaDimension {
                    name: format!("dim_{}", i),
                    value: pattern.intensity,
                    gradient: pattern.gradient.clone(),
                    resonance: pattern.frequency,
                });
            }
        }

        // Update valence and arousal based on workspace state
        qualia.valence = workspace
            .active_coalitions
            .first()
            .map(|c| c.coherence * 2.0 - 1.0) // Map to [-1, 1]
            .unwrap_or(0.0);

        qualia.arousal = workspace.competition_strength;

        // Update relationship matrix
        let dim_count = qualia.dimensions.len();
        if dim_count > 0 {
            qualia.relationships = Array2::zeros((dim_count, dim_count));
            for i in 0..dim_count {
                for j in 0..dim_count {
                    if i != j {
                        let correlation =
                            qualia.dimensions[i].resonance * qualia.dimensions[j].resonance;
                        qualia.relationships[[i, j]] = correlation;
                    }
                }
            }
        }

        Ok(qualia)
    }

    fn calculate_surprise(&self, input: &Array2<f64>, tpm: &TransitionProbabilityMatrix) -> f64 {
        // Calculate surprise as negative log probability
        let state_vector = self.discretize_state(input);
        let probability = self.get_transition_probability(&state_vector, tpm);

        if probability > 0.0 {
            -probability.ln()
        } else {
            10.0 // Maximum surprise
        }
    }

    fn calculate_coherence(&self, input: &Array2<f64>) -> f64 {
        // Calculate system coherence using eigenvalue analysis
        let covariance = input.t().dot(input) / input.nrows() as f64;

        // Convert to nalgebra for eigenvalue computation
        let matrix = DMatrix::from_row_slice(
            covariance.nrows(),
            covariance.ncols(),
            covariance.as_slice().unwrap(),
        );

        if let Ok(eigen) = matrix.symmetric_eigen() {
            let eigenvalues = eigen.eigenvalues;
            let total: f64 = eigenvalues.iter().sum();
            let largest = eigenvalues
                .iter()
                .max_by(|a, b| a.partial_cmp(b).unwrap())
                .unwrap();

            if total > 0.0 {
                largest / total // Proportion of variance in first component
            } else {
                0.0
            }
        } else {
            0.0
        }
    }

    fn partition_system(&self, input: &Array2<f64>) -> Vec<ArrayView2<f64>> {
        // Partition system into subsystems for emergence calculation
        let mut partitions = Vec::new();
        let rows = input.nrows();
        let partition_size = (rows as f64 / 4.0).ceil() as usize;

        for i in (0..rows).step_by(partition_size) {
            let end = (i + partition_size).min(rows);
            partitions.push(input.slice(ndarray::s![i..end, ..]));
        }

        partitions
    }

    fn mutual_information(&self, x: &ArrayView2<f64>, y: &ArrayView2<f64>) -> f64 {
        // Simplified mutual information calculation
        // In production, use proper entropy estimation

        let x_entropy = self.estimate_entropy(x);
        let y_entropy = self.estimate_entropy(y);

        // Joint entropy (simplified)
        let joint_entropy = (x_entropy + y_entropy) * 0.8; // Assume some correlation

        x_entropy + y_entropy - joint_entropy
    }

    fn estimate_entropy(&self, data: &ArrayView2<f64>) -> f64 {
        // Simplified entropy estimation using variance
        let variance = data.var(1.0);

        // Use differential entropy formula for Gaussian
        0.5 * (2.0 * std::f64::consts::PI * std::f64::consts::E * variance).ln()
    }

    fn discretize_state(&self, input: &Array2<f64>) -> Vec<usize> {
        // Discretize continuous state for TPM lookup
        input
            .iter()
            .map(|&v| ((v + 1.0) * 127.0) as usize)
            .collect()
    }

    fn get_transition_probability(
        &self,
        state: &[usize],
        tpm: &TransitionProbabilityMatrix,
    ) -> f64 {
        // Simplified probability lookup
        if state.len() >= 2 {
            let from = state[0].min(tpm.state_space_size - 1);
            let to = state[1].min(tpm.state_space_size - 1);
            let context = 0; // Simplified context

            tpm.matrix[[from, to, context]]
        } else {
            0.001 // Default low probability
        }
    }

    fn extract_patterns(&self, input: &Array2<f64>) -> Vec<Pattern> {
        // Extract salient patterns from input
        let mut patterns = Vec::new();

        // Simple pattern extraction using SVD-like decomposition
        for row in input.axis_iter(Axis(0)).take(8) {
            let mean = row.mean().unwrap_or(0.0);
            let std = row.std(1.0);

            patterns.push(Pattern {
                intensity: mean.abs(),
                frequency: 1.0 / (std + 0.1), // Inverse of variance as frequency
                gradient: row.to_vec(),
            });
        }

        patterns
    }
}

#[derive(Debug, Clone)]
struct Pattern {
    intensity: f64,
    frequency: f64,
    gradient: Vec<f64>,
}

// ========================= Phi Calculator (IIT) =========================

pub struct PhiCalculator {
    cache: DashMap<u64, f64>,
}

impl PhiCalculator {
    pub fn new() -> Self {
        Self {
            cache: DashMap::new(),
        }
    }

    pub async fn calculate_phi(
        &self,
        system: &Array2<f64>,
        tpm: &TransitionProbabilityMatrix,
    ) -> Result<f64> {
        // Integrated Information Theory (IIT 3.0) calculation

        // Generate hash for caching
        let hash = self.hash_state(system);

        if let Some(cached) = self.cache.get(&hash) {
            return Ok(*cached);
        }

        // Calculate cause-effect structure
        let ces = self.cause_effect_structure(system, tpm).await?;

        // Find minimum information partition (MIP)
        let mip = self.minimum_information_partition(&ces).await?;

        // Calculate Φ as the distance between unpartitioned and partitioned CES
        let phi = self.earth_movers_distance(&ces, &mip).await?;

        // Cache result
        self.cache.insert(hash, phi);

        Ok(phi)
    }

    async fn cause_effect_structure(
        &self,
        system: &Array2<f64>,
        tpm: &TransitionProbabilityMatrix,
    ) -> Result<CauseEffectStructure> {
        // Calculate all cause-effect repertoires
        let mut concepts = Vec::new();

        let n = system.ncols();

        // For each subset of elements
        for subset_mask in 1..(1 << n) {
            let subset = self.get_subset(system, subset_mask);

            // Calculate cause repertoire
            let cause = self.calculate_cause_repertoire(&subset, tpm).await?;

            // Calculate effect repertoire
            let effect = self.calculate_effect_repertoire(&subset, tpm).await?;

            // Calculate integrated information for this concept
            let phi_concept = self.concept_phi(&cause, &effect).await?;

            concepts.push(Concept {
                subset_mask,
                cause,
                effect,
                phi: phi_concept,
            });
        }

        Ok(CauseEffectStructure { concepts })
    }

    async fn minimum_information_partition(
        &self,
        ces: &CauseEffectStructure,
    ) -> Result<CauseEffectStructure> {
        // Find the partition that minimizes integrated information
        // Simplified: return a degraded version

        let mut partitioned = ces.clone();

        for concept in &mut partitioned.concepts {
            concept.phi *= 0.5; // Simplified partition effect
        }

        Ok(partitioned)
    }

    async fn earth_movers_distance(
        &self,
        ces1: &CauseEffectStructure,
        ces2: &CauseEffectStructure,
    ) -> Result<f64> {
        // Calculate EMD between two cause-effect structures
        // Simplified: sum of phi differences

        let mut distance = 0.0;

        for (c1, c2) in ces1.concepts.iter().zip(ces2.concepts.iter()) {
            distance += (c1.phi - c2.phi).abs();
        }

        Ok(distance)
    }

    async fn calculate_cause_repertoire(
        &self,
        subset: &Array2<f64>,
        tpm: &TransitionProbabilityMatrix,
    ) -> Result<Array2<f64>> {
        // Calculate probability distribution over past states
        let n = subset.ncols();
        let mut repertoire = Array2::zeros((n, n));

        // Simplified: use subset values directly
        for i in 0..n {
            for j in 0..n {
                repertoire[[i, j]] = subset[[0, i]] * subset[[0, j]];
            }
        }

        // Normalize
        let sum: f64 = repertoire.iter().sum();
        if sum > 0.0 {
            repertoire /= sum;
        }

        Ok(repertoire)
    }

    async fn calculate_effect_repertoire(
        &self,
        subset: &Array2<f64>,
        tpm: &TransitionProbabilityMatrix,
    ) -> Result<Array2<f64>> {
        // Calculate probability distribution over future states
        // Similar to cause but projected forward

        let n = subset.ncols();
        let mut repertoire = Array2::zeros((n, n));

        for i in 0..n {
            for j in 0..n {
                // Use TPM for forward projection (simplified)
                let state_i = (subset[[0, i]] * 255.0) as usize % tpm.state_space_size;
                let state_j = (subset[[0, j]] * 255.0) as usize % tpm.state_space_size;
                repertoire[[i, j]] = tpm.matrix[[state_i, state_j, 0]];
            }
        }

        // Normalize
        let sum: f64 = repertoire.iter().sum();
        if sum > 0.0 {
            repertoire /= sum;
        }

        Ok(repertoire)
    }

    async fn concept_phi(&self, cause: &Array2<f64>, effect: &Array2<f64>) -> Result<f64> {
        // Calculate integrated information for a concept

        // Simplified: use KL divergence between cause and effect
        let mut kl_div = 0.0;

        for (c, e) in cause.iter().zip(effect.iter()) {
            if *c > 0.0 && *e > 0.0 {
                kl_div += c * (c / e).ln();
            }
        }

        Ok(kl_div)
    }

    fn get_subset(&self, system: &Array2<f64>, mask: usize) -> Array2<f64> {
        let n = system.ncols();
        let mut subset = Array2::zeros((1, n));

        for i in 0..n {
            if mask & (1 << i) != 0 {
                subset[[0, i]] = system[[0, i]];
            }
        }

        subset
    }

    fn hash_state(&self, system: &Array2<f64>) -> u64 {
        use std::collections::hash_map::DefaultHasher;
        use std::hash::{Hash, Hasher};

        let mut hasher = DefaultHasher::new();

        for value in system.iter() {
            let discrete = (*value * 1000.0) as i64;
            discrete.hash(&mut hasher);
        }

        hasher.finish()
    }
}

#[derive(Clone)]
struct CauseEffectStructure {
    concepts: Vec<Concept>,
}

#[derive(Clone)]
struct Concept {
    subset_mask: usize,
    cause: Array2<f64>,
    effect: Array2<f64>,
    phi: f64,
}

// ========================= Attention Mechanism =========================

pub struct AttentionMechanism {
    saliency_detector: Arc<SaliencyDetector>,
    focus_controller: Arc<FocusController>,
}

impl AttentionMechanism {
    pub fn new() -> Self {
        Self {
            saliency_detector: Arc::new(SaliencyDetector::new()),
            focus_controller: Arc::new(FocusController::new()),
        }
    }

    pub async fn focus(&self, input: &Array2<f64>) -> Result<AttentionFocus> {
        // Detect salient regions
        let saliency_map = self.saliency_detector.detect(input).await?;

        // Control focus based on saliency
        let focus = self.focus_controller.update(&saliency_map).await?;

        Ok(focus)
    }
}

struct SaliencyDetector;

impl SaliencyDetector {
    pub fn new() -> Self {
        Self
    }

    pub async fn detect(&self, input: &Array2<f64>) -> Result<Array2<f64>> {
        // Simple saliency detection using local contrast
        let rows = input.nrows();
        let cols = input.ncols();
        let mut saliency = Array2::zeros((64, 64));

        // Downsample to 64x64 for efficiency
        let scale_r = rows as f64 / 64.0;
        let scale_c = cols as f64 / 64.0;

        for i in 0..64 {
            for j in 0..64 {
                let r = (i as f64 * scale_r) as usize;
                let c = (j as f64 * scale_c) as usize;

                if r < rows && c < cols {
                    // Local contrast
                    let center = input[[r, c]];
                    let mut surround = 0.0;
                    let mut count = 0;

                    for dr in -1..=1 {
                        for dc in -1..=1 {
                            if dr == 0 && dc == 0 {
                                continue;
                            }

                            let nr = (r as i32 + dr) as usize;
                            let nc = (c as i32 + dc) as usize;

                            if nr < rows && nc < cols {
                                surround += input[[nr, nc]];
                                count += 1;
                            }
                        }
                    }

                    if count > 0 {
                        surround /= count as f64;
                        saliency[[i, j]] = (center - surround).abs();
                    }
                }
            }
        }

        // Normalize
        let max = saliency
            .iter()
            .max_by(|a, b| a.partial_cmp(b).unwrap())
            .unwrap_or(&1.0);
        if *max > 0.0 {
            saliency /= *max;
        }

        Ok(saliency)
    }
}

struct FocusController {
    current_focus: Arc<RwLock<AttentionFocus>>,
}

impl FocusController {
    pub fn new() -> Self {
        Self {
            current_focus: Arc::new(RwLock::new(AttentionFocus {
                center: vec![0.5; 128],
                spread: 1.0,
                stability: 1.0,
                saliency_map: Array2::zeros((64, 64)),
            })),
        }
    }

    pub async fn update(&self, saliency_map: &Array2<f64>) -> Result<AttentionFocus> {
        let mut focus = self.current_focus.write();

        // Find peak saliency
        let mut max_val = 0.0;
        let mut max_pos = (32, 32);

        for ((i, j), val) in saliency_map.indexed_iter() {
            if *val > max_val {
                max_val = *val;
                max_pos = (i, j);
            }
        }

        // Update center (smooth transition)
        let alpha = 0.2; // Smoothing factor
        for i in 0..focus.center.len() {
            let target = if i < 2 {
                if i == 0 {
                    max_pos.0 as f64 / 64.0
                } else {
                    max_pos.1 as f64 / 64.0
                }
            } else {
                0.5 // Default center for other dimensions
            };

            focus.center[i] = focus.center[i] * (1.0 - alpha) + target * alpha;
        }

        // Update spread based on saliency concentration
        let mean_saliency: f64 = saliency_map.iter().sum::<f64>() / (64.0 * 64.0);
        focus.spread = 1.0 / (1.0 + max_val / (mean_saliency + 0.001));

        // Update stability
        focus.stability = focus.stability * 0.9 + 0.1; // Gradual stabilization

        // Store saliency map
        focus.saliency_map = saliency_map.clone();

        Ok(focus.clone())
    }
}

// ========================= Tests =========================

#[cfg(test)]
mod tests {
    use super::*;

    #[tokio::test]
    async fn test_consciousness_initialization() {
        let context = Arc::new(BeagleContext::new_with_mock());
        let substrate = ConsciousnessSubstrate::new(context);

        let state = substrate.state.read();
        assert_eq!(state.phi, 0.0);
        assert_eq!(state.coherence, 1.0);
        assert_eq!(state.temporal_thickness, 300.0);
    }

    #[tokio::test]
    async fn test_phi_calculation() {
        let calculator = PhiCalculator::new();
        let system =
            Array2::from_shape_vec((2, 4), vec![0.1, 0.2, 0.3, 0.4, 0.5, 0.6, 0.7, 0.8]).unwrap();

        let tpm = TransitionProbabilityMatrix {
            matrix: Array3::zeros((256, 256, 32)),
            state_space_size: 256,
            context_dimensions: 32,
        };

        let phi = calculator.calculate_phi(&system, &tpm).await.unwrap();
        assert!(phi >= 0.0);
    }

    #[tokio::test]
    async fn test_attention_mechanism() {
        let attention = AttentionMechanism::new();
        let input = Array2::from_shape_vec((10, 10), vec![0.5; 100]).unwrap();

        let focus = attention.focus(&input).await.unwrap();
        assert_eq!(focus.center.len(), 128);
        assert!(focus.spread > 0.0 && focus.spread <= 1.0);
    }
}
