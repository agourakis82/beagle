// BEAGLE TRANSCEND - Multimodal Neural Fusion (SOTA Q1+ 2025)
// Based on latest multimodal research and architectures
//
// References:
// - Multimodal Fusion Survey (2024): https://arxiv.org/html/2504.02477v1
// - LLM-Centric Multimodal Fusion (2025): https://arxiv.org/html/2506.04788v1
// - Vision LLMs: https://cameronrwolfe.substack.com/p/vision-llms
// - Flamingo Architecture: https://towardsdatascience.com/flamingo-intuitively-and-exhaustively-explained-bf745611238b/
// - Audio-Visual Fusion Transformer: https://jeit.ac.cn/en/article/doi/10.11999/JEIT241090

use crate::{Result, TranscendError};
use beagle_core::BeagleContext;
use beagle_llm::{RequestMeta, TieredRouter};

use dashmap::DashMap;
use nalgebra::{DMatrix, DVector};
use ndarray::{concatenate, s, Array2, Array3, Array4, Axis};
use parking_lot::RwLock;
use rayon::prelude::*;
use serde::{Deserialize, Serialize};
use std::sync::Arc;
use tracing::{debug, info, instrument};

// ========================= Core Structures =========================

/// Multimodal token representation
#[derive(Debug, Clone)]
pub struct MultimodalToken {
    pub modality: Modality,
    pub features: Array2<f32>, // [seq_len, hidden_dim]
    pub position_encoding: Array2<f32>,
    pub attention_mask: Array2<bool>,
    pub metadata: TokenMetadata,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub enum Modality {
    Vision,
    Text,
    Audio,
    Video,
    Tactile,
    Olfactory,
    CrossModal(Box<Modality>, Box<Modality>),
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct TokenMetadata {
    pub timestamp_ms: i64,
    pub spatial_coords: Option<(f32, f32, f32)>,
    pub confidence: f32,
    pub source_id: String,
}

/// State-of-the-art fusion strategies
#[derive(Debug, Clone, Serialize, Deserialize)]
pub enum FusionStrategy {
    /// Early fusion with MLP adapters (2025 SOTA: LLaMA 4, Qwen-VL2)
    EarlyFusionMLP { adapter_dim: usize, dropout: f32 },
    /// Mid-layer cross-attention (LLaMA 3.2-Vision approach)
    MidLayerCrossAttention {
        attention_interval: usize, // Every N layers
        gated: bool,               // Flamingo-style gating
    },
    /// Late fusion with perceiver resampler
    PerceiverResampler {
        num_latents: usize,
        latent_dim: usize,
        depth: usize,
    },
    /// Hierarchical fusion for video/temporal data
    HierarchicalTemporal { window_size: usize, stride: usize },
    /// Novel: Quantum-enhanced fusion
    QuantumFusion { entanglement_dim: usize },
}

// ========================= Vision Encoder (CLIP-based) =========================

pub struct VisionEncoder {
    model_type: VisionBackbone,
    hidden_dim: usize,
    patch_size: usize,
    /// Pre-computed vision features cache
    cache: Arc<DashMap<u64, Array3<f32>>>,
}

#[derive(Debug, Clone)]
pub enum VisionBackbone {
    CLIPViT,    // OpenAI CLIP
    SigLIP,     // Google's improved CLIP
    DINOv2,     // Self-supervised vision
    EVA02,      // Scaled vision transformer
    PaliGemma2, // Google's multimodal
}

impl VisionEncoder {
    pub fn new(backbone: VisionBackbone, hidden_dim: usize) -> Self {
        Self {
            model_type: backbone,
            hidden_dim,
            patch_size: 14, // Standard for ViT
            cache: Arc::new(DashMap::new()),
        }
    }

    /// Encode image to patch features
    #[instrument(skip(self, image))]
    pub fn encode_image(&self, image: &Array3<f32>) -> Array2<f32> {
        let (h, w, c) = image.dim();

        // Extract patches
        let n_patches_h = h / self.patch_size;
        let n_patches_w = w / self.patch_size;
        let n_patches = n_patches_h * n_patches_w;

        // Simplified: flatten patches
        let mut patches = Array2::zeros((n_patches, self.hidden_dim));

        for i in 0..n_patches_h {
            for j in 0..n_patches_w {
                let patch_idx = i * n_patches_w + j;

                // Extract patch and project to hidden_dim
                let patch = image.slice(s![
                    i * self.patch_size..(i + 1) * self.patch_size,
                    j * self.patch_size..(j + 1) * self.patch_size,
                    ..
                ]);

                // Simplified projection (would use actual ViT layers)
                let flattened: Vec<f32> = patch.iter().cloned().collect();
                let projected = self.project_patch(&flattened);

                patches.row_mut(patch_idx).assign(&projected);
            }
        }

        // Add positional encodings
        self.add_positional_encoding(&mut patches);

        patches
    }

    fn project_patch(&self, patch: &[f32]) -> Array1<f32> {
        use ndarray::Array1;

        // Simplified linear projection
        let mut projected = Array1::zeros(self.hidden_dim);

        for (i, val) in patch.iter().enumerate().take(self.hidden_dim) {
            projected[i] = val * 0.1; // Simple scaling
        }

        projected
    }

    fn add_positional_encoding(&self, patches: &mut Array2<f32>) {
        let (n_patches, hidden_dim) = patches.dim();

        for i in 0..n_patches {
            for j in 0..hidden_dim {
                let pos_enc =
                    ((i as f32) / 10000_f32.powf((2.0 * j as f32) / hidden_dim as f32)).sin();
                patches[[i, j]] += pos_enc * 0.1;
            }
        }
    }
}

// ========================= Audio Encoder =========================

pub struct AudioEncoder {
    sample_rate: usize,
    n_mels: usize,
    hidden_dim: usize,
    window_size: usize,
}

impl AudioEncoder {
    pub fn new(hidden_dim: usize) -> Self {
        Self {
            sample_rate: 16000,
            n_mels: 128,
            hidden_dim,
            window_size: 400, // 25ms at 16kHz
        }
    }

    /// Encode audio waveform to features
    pub fn encode_audio(&self, waveform: &Array1<f32>) -> Array2<f32> {
        // Compute mel spectrogram (simplified)
        let n_frames = waveform.len() / self.window_size;
        let mut mel_spec = Array2::zeros((n_frames, self.n_mels));

        for i in 0..n_frames {
            let start = i * self.window_size;
            let end = ((i + 1) * self.window_size).min(waveform.len());

            let frame = &waveform.slice(s![start..end]);
            let mel_frame = self.compute_mel_frame(frame);

            mel_spec.row_mut(i).assign(&mel_frame);
        }

        // Project to hidden dimension
        self.project_mel_to_hidden(&mel_spec)
    }

    fn compute_mel_frame(&self, frame: &ArrayView1<f32>) -> Array1<f32> {
        use ndarray::Array1;

        // Simplified mel computation
        let mut mel = Array1::zeros(self.n_mels);

        for (i, val) in frame.iter().enumerate().take(self.n_mels) {
            mel[i] = val.abs(); // Simple energy
        }

        mel
    }

    fn project_mel_to_hidden(&self, mel_spec: &Array2<f32>) -> Array2<f32> {
        let (n_frames, n_mels) = mel_spec.dim();
        let mut hidden = Array2::zeros((n_frames, self.hidden_dim));

        // Simple linear projection
        for i in 0..n_frames {
            for j in 0..self.hidden_dim.min(n_mels) {
                hidden[[i, j]] = mel_spec[[i, j]];
            }
        }

        hidden
    }
}

// ========================= Learned Projection Layer =========================

/// Linear projection with learned weights (Xavier/He initialization)
#[derive(Debug, Clone)]
pub struct LearnedProjection {
    weight: Array2<f32>,
    bias: Array1<f32>,
    input_dim: usize,
    output_dim: usize,
}

impl LearnedProjection {
    /// Create with Xavier initialization (good for tanh/sigmoid)
    pub fn new_xavier(input_dim: usize, output_dim: usize) -> Self {
        use rand::Rng;
        let mut rng = rand::thread_rng();

        // Xavier: std = sqrt(2 / (fan_in + fan_out))
        let std = (2.0 / (input_dim + output_dim) as f32).sqrt();

        let weight = Array2::from_shape_fn((output_dim, input_dim), |_| rng.gen_range(-std..std));
        let bias = Array1::zeros(output_dim);

Self {
            weight,
            bias,
            input_dim,
            output_dim,
        }
}

    /// Create with He initialization (good for ReLU/GELU)
    pub fn new_he(input_dim: usize, output_dim: usize) -> Self {
        use rand::Rng;
        let mut rng = rand::thread_rng();

        // He: std = sqrt(2 / fan_in)
        let std = (2.0 / input_dim as f32).sqrt();

        let weight = Array2::from_shape_fn((output_dim, input_dim), |_| rng.gen_range(-std..std));
        let bias = Array1::zeros(output_dim);

Self {
            weight,
            bias,
            input_dim,
            output_dim,
        }
}

    /// Forward pass: y = Wx + b
    pub fn forward(&self, input: &Array2<f32>) -> Array2<f32> {
        let (seq_len, _) = input.dim();
        let mut output = Array2::zeros((seq_len, self.output_dim));

        for i in 0..seq_len {
            for j in 0..self.output_dim {
                let mut sum = self.bias[j];
                for k in 0..self.input_dim {
                    sum += self.weight[[j, k]] * input[[i, k]];
                }
                output[[i, j]] = sum;
            }
        }

        output
    }
}

// ========================= Layer Normalization =========================

/// RMSNorm (more efficient than LayerNorm, used in LLaMA)
#[derive(Debug, Clone)]
pub struct RMSNorm {
    weight: Array1<f32>,
    eps: f32,
}

impl RMSNorm {
    pub fn new(dim: usize) -> Self {
        Self {
            weight: Array1::ones(dim),
            eps: 1e-6,
        }
    }

    pub fn forward(&self, input: &Array2<f32>) -> Array2<f32> {
        let (seq_len, dim) = input.dim();
        let mut output = Array2::zeros((seq_len, dim));

        for i in 0..seq_len {
            // Compute RMS
            let rms: f32 = (input.row(i).mapv(|x| x * x).sum() / dim as f32 + self.eps).sqrt();

            // Normalize and scale
            for j in 0..dim {
                output[[i, j]] = (input[[i, j]] / rms) * self.weight[j];
            }
        }

        output
    }
}

// ========================= Rotary Position Embeddings (RoPE) =========================

/// RoPE implementation for cross-modal attention (LLaMA 3.2 style)
#[derive(Debug, Clone)]
pub struct RotaryPositionEmbedding {
    dim: usize,
    max_seq_len: usize,
    /// Precomputed cos/sin tables
    cos_cache: Array2<f32>,
    sin_cache: Array2<f32>,
    /// Base frequency (10000 standard, larger for longer context)
    base: f32,
}

impl RotaryPositionEmbedding {
    pub fn new(dim: usize, max_seq_len: usize) -> Self {
        Self::with_base(dim, max_seq_len, 10000.0)
    }

    pub fn with_base(dim: usize, max_seq_len: usize, base: f32) -> Self {
        // Precompute frequency bands
        let half_dim = dim / 2;
        let mut cos_cache = Array2::zeros((max_seq_len, dim));
        let mut sin_cache = Array2::zeros((max_seq_len, dim));

        for pos in 0..max_seq_len {
            for i in 0..half_dim {
                let freq = 1.0 / base.powf(2.0 * i as f32 / dim as f32);
                let angle = pos as f32 * freq;

                cos_cache[[pos, i]] = angle.cos();
                cos_cache[[pos, i + half_dim]] = angle.cos();
                sin_cache[[pos, i]] = angle.sin();
                sin_cache[[pos, i + half_dim]] = angle.sin();
            }
        }

Self {
            dim,
            max_seq_len,
            cos_cache,
            sin_cache,
            base,
        }
}

    /// Apply RoPE to query/key tensors
    pub fn apply(&self, x: &Array2<f32>, start_pos: usize) -> Array2<f32> {
        let (seq_len, dim) = x.dim();
        let half_dim = dim / 2;
        let mut output = x.clone();

        for i in 0..seq_len {
            let pos = start_pos + i;
            if pos >= self.max_seq_len {
                continue;
            }

            // Rotate pairs: (x0, x1) -> (x0*cos - x1*sin, x0*sin + x1*cos)
            for j in 0..half_dim {
                let x0 = x[[i, j]];
                let x1 = x[[i, j + half_dim]];
                let cos = self.cos_cache[[pos, j]];
                let sin = self.sin_cache[[pos, j]];

                output[[i, j]] = x0 * cos - x1 * sin;
                output[[i, j + half_dim]] = x0 * sin + x1 * cos;
            }
        }

        output
    }
}

// ========================= Cross-Attention Fusion Module =========================

/// SOTA Cross-Attention with learned projections, RoPE, and RMSNorm
pub struct CrossAttentionFusion {
    num_heads: usize,
    hidden_dim: usize,
    head_dim: usize,
    dropout: f32,
    /// Whether to use Flamingo-style gating
    use_gating: bool,
    /// Learned Q/K/V projections
    q_proj: LearnedProjection,
    k_proj: LearnedProjection,
    v_proj: LearnedProjection,
    o_proj: LearnedProjection,
    /// RoPE for positional encoding
    rope: RotaryPositionEmbedding,
    /// Pre-attention normalization
    q_norm: RMSNorm,
    kv_norm: RMSNorm,
    /// Gate projection for Flamingo-style gating
    gate_proj: Option<LearnedProjection>,
    /// Cache for attention weights
    attention_cache: Arc<DashMap<u64, Array3<f32>>>,
}

impl CrossAttentionFusion {
    pub fn new(num_heads: usize, hidden_dim: usize, use_gating: bool) -> Self {
        let head_dim = hidden_dim / num_heads;

        Self {
            num_heads,
            hidden_dim,
            head_dim,
            dropout: 0.1,
            use_gating,
            q_proj: LearnedProjection::new_xavier(hidden_dim, hidden_dim),
            k_proj: LearnedProjection::new_xavier(hidden_dim, hidden_dim),
            v_proj: LearnedProjection::new_xavier(hidden_dim, hidden_dim),
            o_proj: LearnedProjection::new_xavier(hidden_dim, hidden_dim),
            rope: RotaryPositionEmbedding::new(head_dim, 8192),
            q_norm: RMSNorm::new(hidden_dim),
            kv_norm: RMSNorm::new(hidden_dim),
            gate_proj: if use_gating {
                Some(LearnedProjection::new_xavier(hidden_dim, hidden_dim))
            } else {
                None
            },
            attention_cache: Arc::new(DashMap::new()),
        }
    }

    /// Fuse two modalities using cross-attention with learned projections
    pub fn fuse_modalities(
        &self,
        query_modality: &Array2<f32>,     // [seq_len_q, hidden_dim]
        key_value_modality: &Array2<f32>, // [seq_len_kv, hidden_dim]
    ) -> Array2<f32> {
        let (seq_len_q, hidden_dim) = query_modality.dim();
        let (seq_len_kv, _) = key_value_modality.dim();

        assert_eq!(hidden_dim, self.hidden_dim);

        // Pre-normalization (Pre-LN architecture)
        let query_norm = self.q_norm.forward(query_modality);
        let kv_norm = self.kv_norm.forward(key_value_modality);

        // Learned projections
        let q = self.q_proj.forward(&query_norm);
        let k = self.k_proj.forward(&kv_norm);
        let v = self.v_proj.forward(&kv_norm);

        // Multi-head attention computation
        let mut output = Array2::zeros((seq_len_q, hidden_dim));

        for head in 0..self.num_heads {
            let start = head * self.head_dim;
            let end = (head + 1) * self.head_dim;

            // Extract head-specific features
            let q_head = q.slice(s![.., start..end]).to_owned();
            let k_head = k.slice(s![.., start..end]).to_owned();
            let v_head = v.slice(s![.., start..end]).to_owned();

            // Apply RoPE to Q and K
            let q_rope = self.rope.apply(&q_head, 0);
            let k_rope = self.rope.apply(&k_head, 0);

            // Compute attention scores with RoPE-enhanced Q/K
            let scores = self.compute_attention_scores(&q_rope.view(), &k_rope.view());

            // Apply softmax
            let weights = self.softmax_2d(&scores);

            // Compute weighted values
            let attended = weights.dot(&v_head);

            // Copy to output
            for i in 0..seq_len_q {
                for j in 0..self.head_dim {
                    output[[i, start + j]] = attended[[i, j]];
                }
            }
        }

        // Output projection
        output = self.o_proj.forward(&output);

        // Residual connection
        output = output + query_modality;

        // Apply gating if enabled (Flamingo-style)
        if self.use_gating {
            if let Some(ref gate_proj) = self.gate_proj {
                let gate = self.compute_learned_gate(query_modality, gate_proj);
                output = output * gate.clone() + query_modality * (1.0 - gate);
            }
        }

        output
    }

    fn compute_attention_scores(&self, q: &ArrayView2<f32>, k: &ArrayView2<f32>) -> Array2<f32> {
        let seq_len_q = q.shape()[0];
        let seq_len_k = k.shape()[0];
        let head_dim = q.shape()[1];

        let scale = 1.0 / (head_dim as f32).sqrt();

        let mut scores = Array2::zeros((seq_len_q, seq_len_k));

        for i in 0..seq_len_q {
            for j in 0..seq_len_k {
                let score: f32 = q
                    .row(i)
                    .iter()
                    .zip(k.row(j).iter())
                    .map(|(qi, kj)| qi * kj)
                    .sum();
                scores[[i, j]] = score * scale;
            }
        }

        scores
    }

    fn softmax_2d(&self, scores: &Array2<f32>) -> Array2<f32> {
        let mut weights = scores.clone();

        for i in 0..weights.shape()[0] {
            // Find max for numerical stability
            let max = weights
                .row(i)
                .iter()
                .max_by(|a, b| a.partial_cmp(b).unwrap())
                .copied()
                .unwrap_or(0.0);

            // Subtract max and compute exp
            let mut exp_sum: f32 = 0.0;
            for j in 0..weights.shape()[1] {
                weights[[i, j]] = (weights[[i, j]] - max).exp();
                exp_sum += weights[[i, j]];
            }

            // Normalize
            for j in 0..weights.shape()[1] {
                weights[[i, j]] /= exp_sum;
            }
        }

        weights
    }

    fn compute_learned_gate(
        &self,
        features: &Array2<f32>,
        gate_proj: &LearnedProjection,
    ) -> Array2<f32> {
        // Learned gating with sigmoid activation
        let projected = gate_proj.forward(features);
        projected.mapv(|x| 1.0 / (1.0 + (-x).exp())) // Sigmoid
    }
}

// ========================= MLP Adapter (2025 SOTA) =========================

pub struct MLPAdapter {
    input_dim: usize,
    hidden_dim: usize,
    output_dim: usize,
    activation: Activation,
}

#[derive(Debug, Clone)]
pub enum Activation {
    GELU,
    SiLU,
    ReLU,
    Swish,
}

impl MLPAdapter {
    pub fn new(input_dim: usize, output_dim: usize) -> Self {
        Self {
            input_dim,
            hidden_dim: input_dim * 4, // Standard expansion
            output_dim,
            activation: Activation::SiLU, // Current preference in 2025
        }
    }

    /// Project features through MLP adapter
    pub fn forward(&self, input: &Array2<f32>) -> Array2<f32> {
        let (seq_len, _) = input.dim();

        // First linear layer (expand)
        let mut hidden = Array2::zeros((seq_len, self.hidden_dim));

        // Simplified linear transformation
        for i in 0..seq_len {
            for j in 0..self.hidden_dim.min(self.input_dim) {
                hidden[[i, j]] = input[[i, j % self.input_dim]];
            }
        }

        // Apply activation
        hidden = self.apply_activation(&hidden);

        // Second linear layer (project down)
        let mut output = Array2::zeros((seq_len, self.output_dim));

        for i in 0..seq_len {
            for j in 0..self.output_dim {
                output[[i, j]] = hidden[[i, j % self.hidden_dim]] * 0.1;
            }
        }

        output
    }

    fn apply_activation(&self, x: &Array2<f32>) -> Array2<f32> {
        match self.activation {
            Activation::GELU => x.mapv(|v| self.gelu(v)),
            Activation::SiLU => x.mapv(|v| v * (1.0 + (-v).exp()).recip()),
            Activation::ReLU => x.mapv(|v| v.max(0.0)),
            Activation::Swish => x.mapv(|v| v * (1.0 + (-v).exp()).recip()),
        }
    }

    fn gelu(&self, x: f32) -> f32 {
        0.5 * x * (1.0 + ((2.0 / std::f32::consts::PI).sqrt() * (x + 0.044715 * x.powi(3))).tanh())
    }
}

// ========================= Perceiver Resampler =========================

pub struct PerceiverResampler {
    num_latents: usize,
    latent_dim: usize,
    depth: usize,
    cross_attention: Arc<CrossAttentionFusion>,
}

impl PerceiverResampler {
    pub fn new(num_latents: usize, latent_dim: usize, depth: usize) -> Self {
        Self {
            num_latents,
            latent_dim,
            depth,
            cross_attention: Arc::new(CrossAttentionFusion::new(8, latent_dim, false)),
        }
    }

    /// Resample variable-length inputs to fixed latents
    pub fn resample(&self, input: &Array2<f32>) -> Array2<f32> {
        // Initialize learnable latent queries
        let mut latents = Array2::from_elem((self.num_latents, self.latent_dim), 0.1);

        // Iterative cross-attention refinement
        for _ in 0..self.depth {
            latents = self.cross_attention.fuse_modalities(&latents, input);

            // Add & norm (simplified)
            latents = latents.mapv(|v| v / (1.0 + v.abs()));
        }

        latents
    }
}

// ========================= Multimodal Fusion Engine =========================

pub struct MultimodalFusionEngine {
    vision_encoder: Arc<VisionEncoder>,
    audio_encoder: Arc<AudioEncoder>,
    fusion_strategy: FusionStrategy,
    cross_attention: Arc<CrossAttentionFusion>,
    mlp_adapter: Arc<MLPAdapter>,
    perceiver: Arc<PerceiverResampler>,
    output_dim: usize,
}

impl MultimodalFusionEngine {
    pub fn new(fusion_strategy: FusionStrategy, output_dim: usize) -> Self {
        let hidden_dim = 768; // Standard transformer dimension

        Self {
            vision_encoder: Arc::new(VisionEncoder::new(VisionBackbone::CLIPViT, hidden_dim)),
            audio_encoder: Arc::new(AudioEncoder::new(hidden_dim)),
            fusion_strategy,
            cross_attention: Arc::new(CrossAttentionFusion::new(12, hidden_dim, true)),
            mlp_adapter: Arc::new(MLPAdapter::new(hidden_dim, output_dim)),
            perceiver: Arc::new(PerceiverResampler::new(256, hidden_dim, 6)),
            output_dim,
        }
    }

    /// Fuse multiple modalities into unified representation
    #[instrument(skip(self, tokens))]
    pub fn fuse(&self, tokens: Vec<MultimodalToken>) -> Result<Array2<f32>> {
        // Group tokens by modality
        let mut vision_tokens = Vec::new();
        let mut text_tokens = Vec::new();
        let mut audio_tokens = Vec::new();

        for token in tokens {
            match token.modality {
                Modality::Vision => vision_tokens.push(token),
                Modality::Text => text_tokens.push(token),
                Modality::Audio => audio_tokens.push(token),
                _ => {}
            }
        }

        // Apply fusion strategy
        match &self.fusion_strategy {
            FusionStrategy::EarlyFusionMLP { .. } => {
                self.early_fusion_mlp(vision_tokens, text_tokens, audio_tokens)
            }
            FusionStrategy::MidLayerCrossAttention {
                attention_interval,
                gated,
            } => self.mid_layer_fusion(vision_tokens, text_tokens, *attention_interval, *gated),
            FusionStrategy::PerceiverResampler { .. } => {
                self.perceiver_fusion(vision_tokens, text_tokens, audio_tokens)
            }
            _ => {
                // Default to early fusion
                self.early_fusion_mlp(vision_tokens, text_tokens, audio_tokens)
            }
        }
    }

    /// Early fusion with MLP adapters (2025 SOTA)
    fn early_fusion_mlp(
        &self,
        vision: Vec<MultimodalToken>,
        text: Vec<MultimodalToken>,
        audio: Vec<MultimodalToken>,
    ) -> Result<Array2<f32>> {
        // Concatenate all features
        let mut all_features = Vec::new();

        for token in vision {
            all_features.push(token.features);
        }
        for token in text {
            all_features.push(token.features);
        }
        for token in audio {
            all_features.push(token.features);
        }

        if all_features.is_empty() {
            return Ok(Array2::zeros((1, self.output_dim)));
        }

        // Stack along sequence dimension
        let stacked = ndarray::stack(
            Axis(0),
            &all_features.iter().map(|a| a.view()).collect::<Vec<_>>(),
        )
        .map_err(|e| TranscendError::Fusion(e.to_string()))?;

        // Flatten to 2D
        let (n_tokens, seq_len, hidden_dim) = stacked.dim();
        let flattened = stacked
            .into_shape((n_tokens * seq_len, hidden_dim))
            .map_err(|e| TranscendError::Fusion(e.to_string()))?;

        // Apply MLP adapter
        Ok(self.mlp_adapter.forward(&flattened))
    }

    /// Mid-layer cross-attention fusion (LLaMA 3.2 style)
    fn mid_layer_fusion(
        &self,
        vision: Vec<MultimodalToken>,
        text: Vec<MultimodalToken>,
        attention_interval: usize,
        gated: bool,
    ) -> Result<Array2<f32>> {
        if text.is_empty() {
            return Ok(Array2::zeros((1, self.output_dim)));
        }

        // Start with text as base
        let mut fused = text[0].features.clone();

        // Apply cross-attention at intervals
        for (i, v_token) in vision.iter().enumerate() {
            if i % attention_interval == 0 {
                let ca = CrossAttentionFusion::new(12, fused.shape()[1], gated);
                fused = ca.fuse_modalities(&fused, &v_token.features);
            }
        }

        // Project to output dimension
        Ok(self.mlp_adapter.forward(&fused))
    }

    /// Perceiver-based fusion
    fn perceiver_fusion(
        &self,
        vision: Vec<MultimodalToken>,
        text: Vec<MultimodalToken>,
        audio: Vec<MultimodalToken>,
    ) -> Result<Array2<f32>> {
        // Concatenate all modalities
        let mut all_features = Vec::new();

        for token in vision.iter().chain(text.iter()).chain(audio.iter()) {
            all_features.push(token.features.view());
        }

        if all_features.is_empty() {
            return Ok(Array2::zeros((1, self.output_dim)));
        }

        // Stack features
        let stacked = ndarray::stack(Axis(0), &all_features)
            .map_err(|e| TranscendError::Fusion(e.to_string()))?;

        // Flatten
        let (n, s, d) = stacked.dim();
        let flat = stacked
            .into_shape((n * s, d))
            .map_err(|e| TranscendError::Fusion(e.to_string()))?;

        // Resample to fixed latents
        let latents = self.perceiver.resample(&flat);

        // Project to output
        Ok(self.mlp_adapter.forward(&latents))
    }
}

// ========================= Hierarchical Video Fusion =========================

pub struct HierarchicalVideoFusion {
    window_size: usize,
    stride: usize,
    temporal_encoder: Arc<TemporalEncoder>,
}

pub struct TemporalEncoder {
    hidden_dim: usize,
}

impl HierarchicalVideoFusion {
    pub fn new(window_size: usize, stride: usize, hidden_dim: usize) -> Self {
        Self {
            window_size,
            stride,
            temporal_encoder: Arc::new(TemporalEncoder { hidden_dim }),
        }
    }

    /// Process video with hierarchical temporal fusion
    pub fn process_video(&self, frames: Vec<Array3<f32>>) -> Array2<f32> {
        let mut windows = Vec::new();

        // Extract temporal windows
        let mut i = 0;
        while i < frames.len() {
            let end = (i + self.window_size).min(frames.len());
            let window: Vec<_> = frames[i..end].to_vec();

            // Process window
            let window_features = self.process_window(&window);
            windows.push(window_features);

            i += self.stride;
        }

        // Aggregate windows
        self.aggregate_windows(&windows)
    }

    fn process_window(&self, frames: &[Array3<f32>]) -> Array2<f32> {
        // Simplified: average pooling
        let hidden_dim = self.temporal_encoder.hidden_dim;
        let mut features = Array2::zeros((1, hidden_dim));

        for frame in frames {
            // Extract frame features (simplified)
            for i in 0..hidden_dim.min(frame.shape()[2]) {
                features[[0, i]] += frame[[0, 0, i]] / frames.len() as f32;
            }
        }

        features
    }

    fn aggregate_windows(&self, windows: &[Array2<f32>]) -> Array2<f32> {
        if windows.is_empty() {
            return Array2::zeros((1, self.temporal_encoder.hidden_dim));
        }

        // Stack and average
        let stacked = ndarray::stack(
            Axis(0),
            &windows.iter().map(|w| w.view()).collect::<Vec<_>>(),
        )
        .unwrap();

        stacked.mean_axis(Axis(0)).unwrap()
    }
}

use ndarray::{Array1, ArrayView1, ArrayView2};

// ========================= Tests =========================

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_vision_encoder() {
        let encoder = VisionEncoder::new(VisionBackbone::CLIPViT, 768);
        let image = Array3::from_elem((224, 224, 3), 0.5);

        let features = encoder.encode_image(&image);
        assert_eq!(features.shape()[1], 768);
        assert!(features.shape()[0] > 0);
    }

    #[test]
    fn test_cross_attention_fusion() {
        let fusion = CrossAttentionFusion::new(8, 768, true);

        let query = Array2::from_elem((10, 768), 0.1);
        let key_value = Array2::from_elem((20, 768), 0.2);

        let output = fusion.fuse_modalities(&query, &key_value);
        assert_eq!(output.shape(), query.shape());
    }

    #[test]
    fn test_mlp_adapter() {
        let adapter = MLPAdapter::new(768, 1024);
        let input = Array2::from_elem((10, 768), 0.5);

        let output = adapter.forward(&input);
        assert_eq!(output.shape(), (10, 1024));
    }

    #[test]
    fn test_multimodal_fusion() {
        let engine = MultimodalFusionEngine::new(
            FusionStrategy::EarlyFusionMLP {
                adapter_dim: 768,
                dropout: 0.1,
            },
            1024,
        );

        let tokens = vec![MultimodalToken {
            modality: Modality::Vision,
            features: Array2::from_elem((10, 768), 0.1),
            position_encoding: Array2::zeros((10, 768)),
            attention_mask: Array2::from_elem((10, 10), true),
            metadata: TokenMetadata {
                timestamp_ms: 0,
                spatial_coords: None,
                confidence: 1.0,
                source_id: "test".to_string(),
            },
        }];

        let result = engine.fuse(tokens).unwrap();
        assert_eq!(result.shape()[1], 1024);
    }
}
