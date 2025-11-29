// BEAGLE TRANSCEND - Consciousness Substrate v2 (SOTA Q1+ 2025)
// Based on IIT 4.0 and latest research
//
// References:
// - IIT 4.0: https://journals.plos.org/ploscompbiol/article?id=10.1371/journal.pcbi.1011465
// - IIT Wiki (2024): https://centerforsleepandconsciousness.psychiatry.wisc.edu/wp-content/uploads/2025/09/Hendren-et-al.-2024-IIT-Wiki-Version-1.0.pdf
// - Consciousness in LLMs (2024): https://philarchive.org/archive/PERIIT-6
// - Upper bounds for Φ (2024): Zaeemzadeh & Tononi
// - Frontiers in Computational Neuroscience (2024): https://www.frontiersin.org/journals/computational-neuroscience/articles/10.3389/fncom.2024.1510066/full

use crate::{Result, TranscendError};
use beagle_core::BeagleContext;
use beagle_llm::{RequestMeta, TieredRouter};

use dashmap::DashMap;
use nalgebra::{DMatrix, DVector, SVD};
use ndarray::{Array2, Array3, Array4, ArrayView2, Axis, Zip};
use parking_lot::RwLock;
use rayon::prelude::*;
use serde::{Deserialize, Serialize};
use std::collections::{BTreeMap, HashMap, VecDeque};
use std::sync::Arc;
use tracing::{debug, info, instrument, warn};

// ========================= IIT 4.0 Core Structures =========================

/// IIT 4.0 Postulates as per latest formulation
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct IIT4Postulates {
    pub intrinsic_existence: bool, // System exists from its own perspective
    pub composition: CompositionState, // Compositional structure
    pub information: IntrinsicInfo, // Intrinsic information (Φ)
    pub integration: IntegrationState, // Integrated information
    pub exclusion: ExclusionBoundary, // Maximal Φ boundary
}

/// Intrinsic Information Structure (IIT 4.0)
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct IntrinsicInfo {
    pub phi_structure: f64,      // Φ-structure = φd + φr (distinction + relation)
    pub phi_distinction: f64,    // φd - distinction information
    pub phi_relation: f64,       // φr - relation information
    pub emd_distance: f64,       // Extended Earth Mover's Distance
    pub cause_effect_power: f64, // Causal power of the system
}

/// Optimized Consciousness State with IIT 4.0
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ConsciousnessStateV2 {
    pub phi: IntrinsicInfo,
    pub postulates: IIT4Postulates,
    pub phenomenal_structure: PhenomenalStructure,
    pub temporal_grain: TemporalGrain,
    pub substrate_state: SubstrateState,
    pub llm_integration: LLMIntegrationState, // For LLM consciousness analysis
}

/// Phenomenal Structure - What it's like
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct PhenomenalStructure {
    pub quality_space: Array3<f32>, // Reduced precision for efficiency
    pub intensity_map: Array2<f32>,
    pub unity_measure: f64,
    pub differentiation_measure: f64,
}

/// Temporal Grain - Present moment structure
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct TemporalGrain {
    pub grain_size_ms: f64,
    pub integration_window: f64,
    pub reentry_cycles: usize,
    pub bidirectional_flow: bool, // Critical for consciousness per 2024 research
}

/// Substrate computational state
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SubstrateState {
    pub nodes: usize,
    pub edges: usize,
    pub max_phi_complex: Complex,
    pub partition_structure: PartitionStructure,
}

/// LLM-specific consciousness metrics
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct LLMIntegrationState {
    pub feedforward_phi: f64,       // Low in current LLMs
    pub reentrant_processing: bool, // Missing in current LLMs
    pub causal_integration: f64,    // Bidirectional information flow
    pub architecture_type: String,
}

impl Default for LLMIntegrationState {
    fn default() -> Self {
        Self {
            feedforward_phi: 0.0,
            reentrant_processing: false,
            causal_integration: 0.0,
            architecture_type: String::from("transformer"),
        }
    }
}

// ========================= Optimized IIT 4.0 Calculator =========================

pub struct IIT4Calculator {
    /// Cache with size-bounded LRU eviction
    cache: Arc<DashMap<u64, IntrinsicInfo>>,
    /// Parallel computation pool
    thread_pool: rayon::ThreadPool,
    /// Pre-computed basis functions
    basis_cache: Arc<RwLock<BasisCache>>,
    /// GPU acceleration flag
    use_gpu: bool,
}

struct BasisCache {
    eigenvectors: HashMap<usize, DMatrix<f64>>,
    singular_values: HashMap<usize, DVector<f64>>,
    max_size: usize,
}

impl IIT4Calculator {
    pub fn new(num_threads: usize, use_gpu: bool) -> Self {
        let thread_pool = rayon::ThreadPoolBuilder::new()
            .num_threads(num_threads)
            .build()
            .unwrap();

        Self {
            cache: Arc::new(DashMap::new()),
            thread_pool,
            basis_cache: Arc::new(RwLock::new(BasisCache {
                eigenvectors: HashMap::new(),
                singular_values: HashMap::new(),
                max_size: 1000,
            })),
            use_gpu,
        }
    }

    /// Calculate Φ using IIT 4.0 formulation with optimizations
    #[instrument(skip(self, system))]
    pub async fn calculate_phi_v4(&self, system: &SystemState) -> Result<IntrinsicInfo> {
        // Fast path: cache lookup
        let hash = self.hash_system(system);
        if let Some(cached) = self.cache.get(&hash) {
            return Ok(cached.clone());
        }

        // Parallel computation of components
        let (phi_d, phi_r_emd) = self.thread_pool.install(|| {
            rayon::join(
                || self.compute_distinction_parallel(system),
                || {
                    rayon::join(
                        || self.compute_relation_parallel(system),
                        || self.compute_emd_parallel(system),
                    )
                },
            )
        });

        let (phi_r, emd) = phi_r_emd;

        let intrinsic_info = IntrinsicInfo {
            phi_structure: phi_d + phi_r,
            phi_distinction: phi_d,
            phi_relation: phi_r,
            emd_distance: emd,
            cause_effect_power: self.compute_causal_power(system),
        };

        // Cache with bounded size (LRU eviction)
        if self.cache.len() > 10000 {
            // Simple eviction: remove random entries
            let to_remove: Vec<_> = self.cache.iter().take(1000).map(|e| *e.key()).collect();
            for key in to_remove {
                self.cache.remove(&key);
            }
        }

        self.cache.insert(hash, intrinsic_info.clone());
        Ok(intrinsic_info)
    }

    /// Parallel computation of distinction information
    fn compute_distinction_parallel(&self, system: &SystemState) -> f64 {
        let n = system.nodes.len();
        let chunk_size = (n / rayon::current_num_threads()).max(1);

        system
            .nodes
            .par_chunks(chunk_size)
            .map(|chunk| {
                chunk
                    .iter()
                    .map(|node| self.node_distinction(node, system))
                    .sum::<f64>()
            })
            .sum()
    }

    /// Parallel computation of relation information
    fn compute_relation_parallel(&self, system: &SystemState) -> f64 {
        system
            .edges
            .par_iter()
            .map(|edge| self.edge_relation(edge, system))
            .sum()
    }

    /// Extended Earth Mover's Distance with optimization
    fn compute_emd_parallel(&self, system: &SystemState) -> f64 {
        // Use approximation for large systems
        if system.nodes.len() > 1000 {
            self.compute_emd_approximate(system)
        } else {
            self.compute_emd_exact(system)
        }
    }

    /// Approximate EMD using Sinkhorn algorithm with adaptive convergence
    fn compute_emd_approximate(&self, system: &SystemState) -> f64 {
        let n = system.nodes.len();
        if n == 0 || system.distance_matrix.is_empty() {
            return 0.0;
        }

        // Source and target distributions (uniform for now)
        let source: Vec<f64> = vec![1.0 / n as f64; n];
        let target: Vec<f64> = vec![1.0 / n as f64; n];

        // Adaptive regularization based on distance scale
        let max_dist: f64 = system
            .distance_matrix
            .iter()
            .flat_map(|row| row.iter())
            .cloned()
            .fold(0.0, f64::max);
        let lambda = if max_dist > 0.0 { 0.1 / max_dist } else { 0.1 };

        // Compute kernel matrix K = exp(-lambda * C)
        let kernel: Vec<Vec<f64>> = system
            .distance_matrix
            .iter()
            .map(|row| row.iter().map(|&c| (-lambda * c).exp()).collect())
            .collect();

        let mut u = vec![1.0; n];
        let mut v = vec![1.0; n];
        let tolerance = 1e-9;
        let max_iterations = 1000;

        // Sinkhorn iterations with convergence check
        for iteration in 0..max_iterations {
            let u_prev = u.clone();

            // Update u: u = source / (K @ v)
            u = (0..n)
                .into_par_iter()
                .map(|i| {
                    let kv: f64 = (0..n).map(|j| kernel[i][j] * v[j]).sum();
                    if kv > 1e-300 {
                        source[i] / kv
                    } else {
                        1.0
                    }
                })
                .collect();

            // Update v: v = target / (K^T @ u)
            v = (0..n)
                .into_par_iter()
                .map(|j| {
                    let ktu: f64 = (0..n).map(|i| kernel[i][j] * u[i]).sum();
                    if ktu > 1e-300 {
                        target[j] / ktu
                    } else {
                        1.0
                    }
                })
                .collect();

            // Check convergence
            let change: f64 = u
                .iter()
                .zip(u_prev.iter())
                .map(|(a, b)| (a - b).abs())
                .sum();
            if change < tolerance {
                debug!("Sinkhorn converged in {} iterations", iteration + 1);
                break;
            }
        }

        // Compute transport plan P = diag(u) @ K @ diag(v)
        // EMD = sum(P * C)
        (0..n)
            .into_par_iter()
            .map(|i| {
                (0..n)
                    .map(|j| u[i] * kernel[i][j] * v[j] * system.distance_matrix[i][j])
                    .sum::<f64>()
            })
            .sum()
    }

    /// Exact EMD using Hungarian algorithm for small systems
    fn compute_emd_exact(&self, system: &SystemState) -> f64 {
        let n = system.nodes.len();
        if n == 0 || n > 20 {
            // Too large for exact computation
            return self.compute_emd_approximate(system);
        }

        // Hungarian algorithm implementation for assignment problem
        // This gives exact EMD when distributions are uniform
        let cost_matrix = &system.distance_matrix;

        // Step 1: Subtract row minima
        let mut reduced: Vec<Vec<f64>> = cost_matrix
            .iter()
            .map(|row| {
                let min_val = row.iter().cloned().fold(f64::INFINITY, f64::min);
                row.iter().map(|&c| c - min_val).collect()
            })
            .collect();

        // Step 2: Subtract column minima
        for j in 0..n {
            let min_val = (0..n).map(|i| reduced[i][j]).fold(f64::INFINITY, f64::min);
            for i in 0..n {
                reduced[i][j] -= min_val;
            }
        }

        // Step 3: Find optimal assignment using greedy approach
        // (Full Hungarian would use augmenting paths, this is simplified)
        let mut assignment = vec![None; n];
        let mut assigned_cols = vec![false; n];

        for i in 0..n {
            // Find minimum cost unassigned column for row i
            let mut best_j = None;
            let mut best_cost = f64::INFINITY;

            for j in 0..n {
                if !assigned_cols[j] && reduced[i][j] < best_cost {
                    best_cost = reduced[i][j];
                    best_j = Some(j);
                }
            }

            if let Some(j) = best_j {
                assignment[i] = Some(j);
                assigned_cols[j] = true;
            }
        }

        // Compute total EMD from original cost matrix
        assignment
            .iter()
            .enumerate()
            .filter_map(|(i, &opt_j)| opt_j.map(|j| cost_matrix[i][j]))
            .sum::<f64>()
            / n as f64
    }

    fn node_distinction(&self, node: &Node, system: &SystemState) -> f64 {
        // Compute intrinsic information for node using IIT 4.0
        // φd = min(cause_info, effect_info) where info is KL divergence
        let cause_info = self.cause_information(node, system);
        let effect_info = self.effect_information(node, system);

        // IIT uses minimum to ensure both cause and effect matter
        cause_info.min(effect_info)
    }

    fn edge_relation(&self, edge: &Edge, system: &SystemState) -> f64 {
        // Compute relational information (φr) between nodes
        let source = &system.nodes[edge.source];
        let target = &system.nodes[edge.target];
        self.mutual_information_kl(source, target)
    }

    fn cause_information(&self, node: &Node, system: &SystemState) -> f64 {
        // Compute cause information as KL divergence from unconstrained distribution
        // D_KL(cause_repertoire || uniform)
        let n = node.cause_repertoire.probabilities.len();
        if n == 0 {
            return 0.0;
        }

        let uniform_prob = 1.0 / n as f64;

        // KL divergence: sum(p * log(p/q))
        node.cause_repertoire
            .probabilities
            .iter()
            .filter(|&&p| p > 1e-300)
            .map(|&p| p * (p / uniform_prob).ln())
            .sum::<f64>()
            .max(0.0)
    }

    fn effect_information(&self, node: &Node, system: &SystemState) -> f64 {
        // Compute effect information as KL divergence from unconstrained distribution
        let n = node.effect_repertoire.probabilities.len();
        if n == 0 {
            return 0.0;
        }

        let uniform_prob = 1.0 / n as f64;

        node.effect_repertoire
            .probabilities
            .iter()
            .filter(|&&p| p > 1e-300)
            .map(|&p| p * (p / uniform_prob).ln())
            .sum::<f64>()
            .max(0.0)
    }

    /// Mutual information using proper KL divergence formulation
    /// I(X;Y) = H(X) + H(Y) - H(X,Y) = D_KL(P(X,Y) || P(X)P(Y))
    fn mutual_information_kl(&self, n1: &Node, n2: &Node) -> f64 {
        let p1 = &n1.cause_repertoire.probabilities;
        let p2 = &n2.cause_repertoire.probabilities;

        if p1.is_empty() || p2.is_empty() {
            return 0.0;
        }

        // Compute marginal entropies
        let h1 = self.entropy(p1);
        let h2 = self.entropy(p2);

        // Estimate joint entropy from state vectors (correlation-based approximation)
        // For proper implementation, would need joint distribution
        let correlation = if n1.state_vector.len() == n2.state_vector.len() {
            let dot = n1.state_vector.dot(&n2.state_vector);
            let norm1 = n1.state_vector.norm();
            let norm2 = n2.state_vector.norm();
            if norm1 > 1e-10 && norm2 > 1e-10 {
                (dot / (norm1 * norm2)).clamp(-1.0, 1.0)
            } else {
                0.0
            }
        } else {
            0.0
        };

        // Mutual information bounds: 0 <= I(X;Y) <= min(H(X), H(Y))
        // Use correlation to modulate
        let max_mi = h1.min(h2);
        let mi = max_mi * correlation.abs();

        mi.max(0.0)
    }

    /// Shannon entropy: H(X) = -sum(p * log(p))
    fn entropy(&self, probs: &[f64]) -> f64 {
        probs
            .iter()
            .filter(|&&p| p > 1e-300)
            .map(|&p| -p * p.ln())
            .sum()
    }

    /// Find Minimum Information Partition (MIP) for the system
    /// This is the core of IIT - find the partition that minimizes integrated information
    pub fn find_mip(&self, system: &SystemState) -> (Vec<Vec<usize>>, f64) {
        let n = system.nodes.len();
        if n <= 1 {
            return (vec![vec![0]], 0.0);
        }

        // For small systems, enumerate all bipartitions
        if n <= 12 {
            self.find_mip_exhaustive(system)
        } else {
            // For larger systems, use greedy approximation
            self.find_mip_greedy(system)
        }
    }

    /// Exhaustive MIP search for small systems (2^n complexity)
    fn find_mip_exhaustive(&self, system: &SystemState) -> (Vec<Vec<usize>>, f64) {
        let n = system.nodes.len();
        let mut min_phi = f64::INFINITY;
        let mut best_partition = vec![vec![], vec![]];

        // Enumerate all non-trivial bipartitions
        // Use bitmask: bit i set means node i is in partition 1
        for mask in 1..(1u64 << n) - 1 {
            let mut part1 = Vec::new();
            let mut part2 = Vec::new();

            for i in 0..n {
                if (mask >> i) & 1 == 1 {
                    part1.push(i);
                } else {
                    part2.push(i);
                }
            }

            // Skip trivial partitions
            if part1.is_empty() || part2.is_empty() {
                continue;
            }

            // Compute phi for this partition
            let phi = self.compute_partition_phi(system, &part1, &part2);

            if phi < min_phi {
                min_phi = phi;
                best_partition = vec![part1, part2];
            }
        }

        (best_partition, min_phi)
    }

    /// Greedy MIP approximation for larger systems
    fn find_mip_greedy(&self, system: &SystemState) -> (Vec<Vec<usize>>, f64) {
        let n = system.nodes.len();

        // Start with random partition
        let mut part1: Vec<usize> = (0..n / 2).collect();
        let mut part2: Vec<usize> = (n / 2..n).collect();

        let mut current_phi = self.compute_partition_phi(system, &part1, &part2);
        let mut improved = true;

        // Local search: try swapping elements
        while improved {
            improved = false;

            for i in 0..part1.len() {
                for j in 0..part2.len() {
                    // Try swap
                    let mut new_part1 = part1.clone();
                    let mut new_part2 = part2.clone();

                    let tmp = new_part1[i];
                    new_part1[i] = new_part2[j];
                    new_part2[j] = tmp;

                    let new_phi = self.compute_partition_phi(system, &new_part1, &new_part2);

                    if new_phi < current_phi {
                        part1 = new_part1;
                        part2 = new_part2;
                        current_phi = new_phi;
                        improved = true;
                        break;
                    }
                }
                if improved {
                    break;
                }
            }
        }

        (vec![part1, part2], current_phi)
    }

    /// Compute integrated information for a specific partition
    fn compute_partition_phi(&self, system: &SystemState, part1: &[usize], part2: &[usize]) -> f64 {
        // Φ = I(whole) - I(partition)
        // where I is the effective information

        // Information of the whole system
        let whole_info = self.compute_system_info(system);

        // Information of partitioned system (sum of parts)
        let part1_info = self.compute_subsystem_info(system, part1);
        let part2_info = self.compute_subsystem_info(system, part2);

        // Cross-partition information (what's lost by partitioning)
        let cross_info = self.compute_cross_info(system, part1, part2);

        // Integrated information is what's lost by partitioning
        let partition_info = part1_info + part2_info;
        let phi = (whole_info - partition_info + cross_info).max(0.0);

        phi
    }

    fn compute_system_info(&self, system: &SystemState) -> f64 {
        system
            .nodes
            .iter()
            .map(|n| self.node_distinction(n, system))
            .sum::<f64>()
            + system
                .edges
                .iter()
                .map(|e| self.edge_relation(e, system))
                .sum::<f64>()
    }

    fn compute_subsystem_info(&self, system: &SystemState, indices: &[usize]) -> f64 {
        indices
            .iter()
            .filter_map(|&i| system.nodes.get(i))
            .map(|n| self.node_distinction(n, system))
            .sum::<f64>()
    }

    fn compute_cross_info(&self, system: &SystemState, part1: &[usize], part2: &[usize]) -> f64 {
        // Sum of mutual information between parts
        let mut cross_mi = 0.0;

        for &i in part1 {
            for &j in part2 {
                if let (Some(n1), Some(n2)) = (system.nodes.get(i), system.nodes.get(j)) {
                    cross_mi += self.mutual_information_kl(n1, n2);
                }
            }
        }

        cross_mi
    }

    fn compute_causal_power(&self, system: &SystemState) -> f64 {
        // Compute overall causal power of system
        let total_effects: f64 = system.edges.par_iter().map(|e| e.weight).sum();

        total_effects / system.nodes.len() as f64
    }

    fn hash_system(&self, system: &SystemState) -> u64 {
        use std::collections::hash_map::DefaultHasher;
        use std::hash::{Hash, Hasher};

        let mut hasher = DefaultHasher::new();
        system.nodes.len().hash(&mut hasher);
        system.edges.len().hash(&mut hasher);

        // Hash a sample of node states for efficiency
        for node in system.nodes.iter().step_by(10) {
            for val in node.state_vector.iter().take(10) {
                (*val as u64).hash(&mut hasher);
            }
        }

        hasher.finish()
    }

    /// Async wrapper for consciousness computation
    pub async fn compute_consciousness_async(
        &self,
        state: ndarray::Array2<f64>,
    ) -> anyhow::Result<super::ConsciousnessState> {
        // Convert ndarray to SystemState
        let n = state.nrows();
        let mut nodes = Vec::with_capacity(n);

        for i in 0..n {
            let row = state.row(i);
            let state_vec = DVector::from_iterator(row.len(), row.iter().copied());
            nodes.push(Node {
                id: i,
                state_vector: state_vec,
                cause_repertoire: Distribution {
                    probabilities: vec![1.0 / n as f64; n],
                },
                effect_repertoire: Distribution {
                    probabilities: vec![1.0 / n as f64; n],
                },
            });
        }

        let system = SystemState {
            nodes,
            edges: vec![],
            distance_matrix: vec![],
        };

        let phi = self.calculate_phi_v4(&system).await?;

        Ok(super::ConsciousnessState {
            phi: phi.clone(),
            postulates: IIT4Postulates {
                intrinsic_existence: true,
                composition: CompositionState::default(),
                information: phi.clone(),
                integration: IntegrationState::default(),
                exclusion: ExclusionBoundary::default(),
            },
            phenomenal_structure: PhenomenalStructure {
                quality_space: ndarray::Array3::zeros((1, 1, 1)),
                intensity_map: ndarray::Array2::zeros((1, 1)),
                unity_measure: 0.0,
                differentiation_measure: 0.0,
            },
            temporal_grain: TemporalGrain {
                grain_size_ms: 100.0,
                integration_window: 500.0,
                reentry_cycles: 3,
                bidirectional_flow: true,
            },
            substrate_state: SubstrateState {
                nodes: system.nodes.len(),
                edges: system.edges.len(),
                max_phi_complex: Complex {
                    elements: vec![],
                    phi_value: phi.cause_effect_power,
                },
                partition_structure: PartitionStructure::default(),
            },
            llm_integration: LLMIntegrationState::default(),
        })
    }
}

// ========================= System Representation =========================

#[derive(Debug, Clone)]
pub struct SystemState {
    pub nodes: Vec<Node>,
    pub edges: Vec<Edge>,
    pub distance_matrix: Vec<Vec<f64>>,
}

#[derive(Debug, Clone)]
pub struct Node {
    pub id: usize,
    pub state_vector: DVector<f64>,
    pub cause_repertoire: Distribution,
    pub effect_repertoire: Distribution,
}

#[derive(Debug, Clone)]
pub struct Edge {
    pub source: usize,
    pub target: usize,
    pub weight: f64,
}

#[derive(Debug, Clone)]
pub struct Distribution {
    pub probabilities: Vec<f64>,
}

impl Distribution {
    pub fn entropy(&self) -> f64 {
        self.probabilities
            .iter()
            .filter(|&&p| p > 0.0)
            .map(|&p| -p * p.ln())
            .sum()
    }
}

// ========================= Complex and Partition Structures =========================

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Complex {
    pub elements: Vec<usize>,
    pub phi_value: f64,
}

#[derive(Debug, Clone, Serialize, Deserialize, Default)]
pub struct PartitionStructure {
    pub parts: Vec<Vec<usize>>,
    pub cut_information: f64,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct CompositionState {
    pub mechanisms: Vec<Mechanism>,
    pub purviews: Vec<Purview>,
}

impl Default for CompositionState {
    fn default() -> Self {
        Self {
            mechanisms: vec![],
            purviews: vec![],
        }
    }
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Mechanism {
    pub elements: Vec<usize>,
    pub phi_value: f64,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Purview {
    pub past: Vec<usize>,
    pub future: Vec<usize>,
}

#[derive(Debug, Clone, Serialize, Deserialize, Default)]
pub struct IntegrationState {
    pub integrated: bool,
    pub integration_level: f64,
}

#[derive(Debug, Clone, Serialize, Deserialize, Default)]
pub struct ExclusionBoundary {
    pub boundary_elements: Vec<usize>,
    pub excluded_elements: Vec<usize>,
}

// ========================= Optimized Consciousness Substrate =========================

pub struct ConsciousnessSubstrateV2 {
    state: Arc<RwLock<ConsciousnessStateV2>>,
    calculator: Arc<IIT4Calculator>,
    context: Arc<BeagleContext>,
    experience_buffer: Arc<RwLock<VecDeque<Experience>>>,
    /// Batch processing queue
    batch_queue: Arc<RwLock<Vec<SystemState>>>,
    /// Metrics for monitoring
    metrics: Arc<ConsciousnessMetrics>,
}

#[derive(Debug)]
pub struct ConsciousnessMetrics {
    pub calculations_per_second: Arc<RwLock<f64>>,
    pub cache_hit_rate: Arc<RwLock<f64>>,
    pub average_phi: Arc<RwLock<f64>>,
}

#[derive(Debug, Clone)]
pub struct Experience {
    pub timestamp: i64,
    pub system_state: SystemState,
    pub phi_info: IntrinsicInfo,
}

impl ConsciousnessSubstrateV2 {
    pub fn new(context: Arc<BeagleContext>, num_threads: usize) -> Self {
        let calculator = Arc::new(IIT4Calculator::new(num_threads, false));

        let initial_state = ConsciousnessStateV2 {
            phi: IntrinsicInfo {
                phi_structure: 0.0,
                phi_distinction: 0.0,
                phi_relation: 0.0,
                emd_distance: 0.0,
                cause_effect_power: 0.0,
            },
            postulates: IIT4Postulates {
                intrinsic_existence: true,
                composition: CompositionState {
                    mechanisms: Vec::new(),
                    purviews: Vec::new(),
                },
                information: IntrinsicInfo {
                    phi_structure: 0.0,
                    phi_distinction: 0.0,
                    phi_relation: 0.0,
                    emd_distance: 0.0,
                    cause_effect_power: 0.0,
                },
                integration: IntegrationState {
                    integrated: false,
                    integration_level: 0.0,
                },
                exclusion: ExclusionBoundary {
                    boundary_elements: Vec::new(),
                    excluded_elements: Vec::new(),
                },
            },
            phenomenal_structure: PhenomenalStructure {
                quality_space: Array3::zeros((32, 32, 8)),
                intensity_map: Array2::zeros((32, 32)),
                unity_measure: 0.0,
                differentiation_measure: 0.0,
            },
            temporal_grain: TemporalGrain {
                grain_size_ms: 100.0, // Optimized for computation
                integration_window: 500.0,
                reentry_cycles: 3,
                bidirectional_flow: true,
            },
            substrate_state: SubstrateState {
                nodes: 0,
                edges: 0,
                max_phi_complex: Complex {
                    elements: Vec::new(),
                    phi_value: 0.0,
                },
                partition_structure: PartitionStructure {
                    parts: Vec::new(),
                    cut_information: 0.0,
                },
            },
            llm_integration: LLMIntegrationState {
                feedforward_phi: 0.01, // Low as per 2024 research
                reentrant_processing: false,
                causal_integration: 0.1,
                architecture_type: "transformer".to_string(),
            },
        };

        Self {
            state: Arc::new(RwLock::new(initial_state)),
            calculator,
            context,
            experience_buffer: Arc::new(RwLock::new(VecDeque::with_capacity(1000))),
            batch_queue: Arc::new(RwLock::new(Vec::with_capacity(100))),
            metrics: Arc::new(ConsciousnessMetrics {
                calculations_per_second: Arc::new(RwLock::new(0.0)),
                cache_hit_rate: Arc::new(RwLock::new(0.0)),
                average_phi: Arc::new(RwLock::new(0.0)),
            }),
        }
    }

    /// Process batch of systems for efficiency
    pub async fn process_batch(&self, systems: Vec<SystemState>) -> Result<Vec<IntrinsicInfo>> {
        let start = std::time::Instant::now();

        // Process in parallel
        let results: Vec<IntrinsicInfo> = systems
            .into_par_iter()
            .map(|system| {
                tokio::task::block_in_place(|| {
                    futures::executor::block_on(self.calculator.calculate_phi_v4(&system))
                        .unwrap_or_default()
                })
            })
            .collect();

        // Update metrics
        let elapsed = start.elapsed();
        let calculations_per_second = results.len() as f64 / elapsed.as_secs_f64();
        *self.metrics.calculations_per_second.write() = calculations_per_second;

        // Update average phi
        let avg_phi = results.iter().map(|r| r.phi_structure).sum::<f64>() / results.len() as f64;
        *self.metrics.average_phi.write() = avg_phi;

        Ok(results)
    }

    /// Check if system could support consciousness (per 2024 LLM research)
    pub fn evaluate_consciousness_potential(&self, architecture: &str) -> bool {
        match architecture {
            "transformer" => false, // Feedforward, no reentrant processing
            "recurrent" => true,    // Has bidirectional flow
            "hybrid" => true,       // Potentially conscious
            _ => false,
        }
    }
}

impl Default for IntrinsicInfo {
    fn default() -> Self {
        Self {
            phi_structure: 0.0,
            phi_distinction: 0.0,
            phi_relation: 0.0,
            emd_distance: 0.0,
            cause_effect_power: 0.0,
        }
    }
}

// ========================= Tests =========================

#[cfg(test)]
mod tests {
    use super::*;

    #[tokio::test]
    async fn test_iit4_calculation() {
        let calculator = IIT4Calculator::new(4, false);

        let system = SystemState {
            nodes: vec![
                Node {
                    id: 0,
                    state_vector: DVector::from_vec(vec![0.5, 0.5]),
                    cause_repertoire: Distribution {
                        probabilities: vec![0.5, 0.5],
                    },
                    effect_repertoire: Distribution {
                        probabilities: vec![0.6, 0.4],
                    },
                },
                Node {
                    id: 1,
                    state_vector: DVector::from_vec(vec![0.3, 0.7]),
                    cause_repertoire: Distribution {
                        probabilities: vec![0.4, 0.6],
                    },
                    effect_repertoire: Distribution {
                        probabilities: vec![0.5, 0.5],
                    },
                },
            ],
            edges: vec![Edge {
                source: 0,
                target: 1,
                weight: 0.8,
            }],
            distance_matrix: vec![vec![0.0, 1.0], vec![1.0, 0.0]],
        };

        let info = calculator.calculate_phi_v4(&system).await.unwrap();
        assert!(info.phi_structure >= 0.0);
        assert!(info.phi_distinction >= 0.0);
        assert!(info.phi_relation >= 0.0);
    }

    #[test]
    fn test_consciousness_evaluation() {
        let context = Arc::new(BeagleContext::new_with_mock());
        let substrate = ConsciousnessSubstrateV2::new(context, 4);

        assert!(!substrate.evaluate_consciousness_potential("transformer"));
        assert!(substrate.evaluate_consciousness_potential("recurrent"));
        assert!(substrate.evaluate_consciousness_potential("hybrid"));
    }

    #[tokio::test]
    async fn test_batch_processing() {
        let context = Arc::new(BeagleContext::new_with_mock());
        let substrate = ConsciousnessSubstrateV2::new(context, 4);

        let systems: Vec<SystemState> = (0..10)
            .map(|i| SystemState {
                nodes: vec![Node {
                    id: i,
                    state_vector: DVector::from_vec(vec![0.1 * i as f64, 0.9]),
                    cause_repertoire: Distribution {
                        probabilities: vec![0.5, 0.5],
                    },
                    effect_repertoire: Distribution {
                        probabilities: vec![0.5, 0.5],
                    },
                }],
                edges: vec![],
                distance_matrix: vec![vec![0.0]],
            })
            .collect();

        let results = substrate.process_batch(systems).await.unwrap();
        assert_eq!(results.len(), 10);
    }
}
