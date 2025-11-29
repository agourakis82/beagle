//! Real Transformer Implementation with Multi-Head Attention

use ndarray::{Array1, Array2, Array3, Axis};
use rand::distributions::Distribution;
use rand_distr::Normal;
use serde::{Deserialize, Serialize};
use std::collections::HashMap;
use std::f32::consts::PI;

/// Real Transformer model with attention mechanism
pub struct Transformer {
    config: TransformerConfig,
    layers: Vec<TransformerLayer>,
    embeddings: EmbeddingLayer,
    positional_encoding: PositionalEncoding,
    output_projection: Linear,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct TransformerConfig {
    pub vocab_size: usize,
    pub hidden_size: usize,
    pub num_layers: usize,
    pub num_heads: usize,
    pub ff_size: usize,
    pub max_seq_len: usize,
    pub dropout: f32,
    pub layer_norm_eps: f32,
}

impl Default for TransformerConfig {
    fn default() -> Self {
        Self {
            vocab_size: 50257, // GPT-2 vocab size
            hidden_size: 768,
            num_layers: 12,
            num_heads: 12,
            ff_size: 3072,
            max_seq_len: 512,
            dropout: 0.1,
            layer_norm_eps: 1e-5,
        }
    }
}

/// Single transformer layer
struct TransformerLayer {
    attention: MultiHeadAttention,
    feed_forward: FeedForward,
    norm1: LayerNorm,
    norm2: LayerNorm,
    dropout: f32,
}

/// Multi-head attention mechanism
struct MultiHeadAttention {
    num_heads: usize,
    head_dim: usize,
    w_q: Linear,
    w_k: Linear,
    w_v: Linear,
    w_o: Linear,
    scale: f32,
}

/// Feed-forward network
struct FeedForward {
    linear1: Linear,
    linear2: Linear,
    activation: Activation,
    dropout: f32,
}

/// Linear layer
#[derive(Clone)]
struct Linear {
    weight: Array2<f32>,
    bias: Option<Array1<f32>>,
}

/// Layer normalization
struct LayerNorm {
    gamma: Array1<f32>,
    beta: Array1<f32>,
    eps: f32,
}

/// Embedding layer
struct EmbeddingLayer {
    embeddings: Array2<f32>,
}

/// Positional encoding
struct PositionalEncoding {
    encoding: Array2<f32>,
}

#[derive(Clone)]
enum Activation {
    Gelu,
    Relu,
}

impl Transformer {
    /// Create new transformer model
    pub fn new(config: TransformerConfig) -> Self {
        let mut layers = Vec::new();

        for _ in 0..config.num_layers {
            layers.push(TransformerLayer::new(&config));
        }

        Self {
            embeddings: EmbeddingLayer::new(config.vocab_size, config.hidden_size),
            positional_encoding: PositionalEncoding::new(config.max_seq_len, config.hidden_size),
            layers,
            output_projection: Linear::new(config.hidden_size, config.vocab_size, true),
            config,
        }
    }

    /// Forward pass through the transformer
    pub fn forward(&self, input_ids: &[usize], attention_mask: Option<&[bool]>) -> Array2<f32> {
        let seq_len = input_ids.len();
        let hidden_size = self.config.hidden_size;

        // Token embeddings + positional encoding
        let mut hidden = Array2::<f32>::zeros((seq_len, hidden_size));
        for (i, &token_id) in input_ids.iter().enumerate() {
            let token_emb = self.embeddings.forward(token_id);
            let pos_emb = self.positional_encoding.get(i);
            hidden.row_mut(i).assign(&(token_emb + pos_emb));
        }

        // Create attention mask if not provided
        let mask = attention_mask
            .map(|m| m.to_vec())
            .unwrap_or_else(|| vec![true; seq_len]);

        // Pass through transformer layers
        for layer in &self.layers {
            hidden = layer.forward(hidden, &mask);
        }

        // Output projection
        self.output_projection.forward(&hidden)
    }

    /// Generate text autoregressively
    pub fn generate(&self, prompt: &[usize], max_length: usize, temperature: f32) -> Vec<usize> {
        let mut generated = prompt.to_vec();

        while generated.len() < max_length {
            // Get logits for next token
            let logits = self.forward(&generated, None);
            let last_logits = logits.row(logits.nrows() - 1);

            // Apply temperature
            let scaled_logits = last_logits.mapv(|x| x / temperature);

            // Convert to probabilities with softmax
            let probs = softmax(&scaled_logits);

            // Sample next token
            let next_token = sample_from_probs(&probs);
            generated.push(next_token);

            // Stop at EOS token (assuming 0 is EOS)
            if next_token == 0 {
                break;
            }
        }

        generated
    }
}

impl TransformerLayer {
    fn new(config: &TransformerConfig) -> Self {
        Self {
            attention: MultiHeadAttention::new(config.hidden_size, config.num_heads),
            feed_forward: FeedForward::new(config.hidden_size, config.ff_size, config.dropout),
            norm1: LayerNorm::new(config.hidden_size, config.layer_norm_eps),
            norm2: LayerNorm::new(config.hidden_size, config.layer_norm_eps),
            dropout: config.dropout,
        }
    }

    fn forward(&self, input: Array2<f32>, mask: &[bool]) -> Array2<f32> {
        // Self-attention with residual connection
        let normed = self.norm1.forward(&input);
        let attention_out = self.attention.forward(&normed, &normed, &normed, mask);
        let attention_out = dropout(attention_out, self.dropout);
        let hidden = input + attention_out;

        // Feed-forward with residual connection
        let normed = self.norm2.forward(&hidden);
        let ff_out = self.feed_forward.forward(&normed);
        let ff_out = dropout(ff_out, self.dropout);

        hidden + ff_out
    }
}

impl MultiHeadAttention {
    fn new(hidden_size: usize, num_heads: usize) -> Self {
        assert_eq!(hidden_size % num_heads, 0);
        let head_dim = hidden_size / num_heads;

        Self {
            num_heads,
            head_dim,
            w_q: Linear::new(hidden_size, hidden_size, false),
            w_k: Linear::new(hidden_size, hidden_size, false),
            w_v: Linear::new(hidden_size, hidden_size, false),
            w_o: Linear::new(hidden_size, hidden_size, false),
            scale: (head_dim as f32).sqrt(),
        }
    }

    fn forward(
        &self,
        query: &Array2<f32>,
        key: &Array2<f32>,
        value: &Array2<f32>,
        mask: &[bool],
    ) -> Array2<f32> {
        let seq_len = query.nrows();
        let hidden_size = query.ncols();

        // Linear projections
        let q = self.w_q.forward(query);
        let k = self.w_k.forward(key);
        let v = self.w_v.forward(value);

        // Reshape for multi-head attention
        let q = self.reshape_for_attention(&q);
        let k = self.reshape_for_attention(&k);
        let v = self.reshape_for_attention(&v);

        // Scaled dot-product attention for each head
        let mut attention_outputs = Vec::new();

        for head in 0..self.num_heads {
            let q_head = q.slice(s![.., head * self.head_dim..(head + 1) * self.head_dim]);
            let k_head = k.slice(s![.., head * self.head_dim..(head + 1) * self.head_dim]);
            let v_head = v.slice(s![.., head * self.head_dim..(head + 1) * self.head_dim]);

            // Compute attention scores
            let scores = q_head.dot(&k_head.t()) / self.scale;

            // Apply mask
            let mut scores = scores;
            for i in 0..seq_len {
                for j in 0..seq_len {
                    if !mask[j] {
                        scores[[i, j]] = -1e9;
                    }
                }
            }

            // Softmax
            let attention_weights = Array2::from_shape_fn((seq_len, seq_len), |(i, j)| {
                let row = scores.row(i);
                let max = row.fold(f32::NEG_INFINITY, |a, &b| a.max(b));
                let exp_scores: Vec<f32> = row.iter().map(|&x| (x - max).exp()).collect();
                let sum: f32 = exp_scores.iter().sum();
                exp_scores[j] / sum
            });

            // Apply attention to values
            let attention_output = attention_weights.dot(&v_head.to_owned());
            attention_outputs.push(attention_output);
        }

        // Concatenate heads
        let mut output = Array2::zeros((seq_len, hidden_size));
        for (head, head_output) in attention_outputs.iter().enumerate() {
            let start = head * self.head_dim;
            let end = (head + 1) * self.head_dim;
            output.slice_mut(s![.., start..end]).assign(head_output);
        }

        // Output projection
        self.w_o.forward(&output)
    }

    fn reshape_for_attention(&self, x: &Array2<f32>) -> Array2<f32> {
        // In practice, this would reshape to (batch, num_heads, seq_len, head_dim)
        // For simplicity, we keep it 2D
        x.clone()
    }
}

impl FeedForward {
    fn new(hidden_size: usize, ff_size: usize, dropout: f32) -> Self {
        Self {
            linear1: Linear::new(hidden_size, ff_size, true),
            linear2: Linear::new(ff_size, hidden_size, true),
            activation: Activation::Gelu,
            dropout,
        }
    }

    fn forward(&self, input: &Array2<f32>) -> Array2<f32> {
        let hidden = self.linear1.forward(input);
        let hidden = self.activation.forward(&hidden);
        let hidden = dropout(hidden, self.dropout);
        self.linear2.forward(&hidden)
    }
}

impl Linear {
    fn new(in_features: usize, out_features: usize, bias: bool) -> Self {
        let normal = Normal::new(0.0, (2.0 / in_features as f32).sqrt()).unwrap();
        let mut rng = rand::thread_rng();

        let weight =
            Array2::from_shape_fn((out_features, in_features), |_| normal.sample(&mut rng));

        let bias = if bias {
            Some(Array1::zeros(out_features))
        } else {
            None
        };

        Self { weight, bias }
    }

    fn forward(&self, input: &Array2<f32>) -> Array2<f32> {
        let output = input.dot(&self.weight.t());

        if let Some(bias) = &self.bias {
            output + bias
        } else {
            output
        }
    }
}

impl LayerNorm {
    fn new(hidden_size: usize, eps: f32) -> Self {
        Self {
            gamma: Array1::ones(hidden_size),
            beta: Array1::zeros(hidden_size),
            eps,
        }
    }

    fn forward(&self, input: &Array2<f32>) -> Array2<f32> {
        let mean = input.mean_axis(Axis(1)).unwrap().insert_axis(Axis(1));
        let var = input.var_axis(Axis(1), 0.0).insert_axis(Axis(1));

        let normalized = (input - &mean) / (var + self.eps).mapv(f32::sqrt);
        normalized * &self.gamma + &self.beta
    }
}

impl EmbeddingLayer {
    fn new(vocab_size: usize, hidden_size: usize) -> Self {
        let normal = Normal::new(0.0, 0.02).unwrap();
        let mut rng = rand::thread_rng();

        let embeddings =
            Array2::from_shape_fn((vocab_size, hidden_size), |_| normal.sample(&mut rng));

        Self { embeddings }
    }

    fn forward(&self, token_id: usize) -> Array1<f32> {
        self.embeddings.row(token_id).to_owned()
    }
}

impl PositionalEncoding {
    fn new(max_len: usize, hidden_size: usize) -> Self {
        let mut encoding = Array2::zeros((max_len, hidden_size));

        for pos in 0..max_len {
            for i in 0..hidden_size {
                let angle = pos as f32 / 10000_f32.powf((2 * (i / 2)) as f32 / hidden_size as f32);

                if i % 2 == 0 {
                    encoding[[pos, i]] = angle.sin();
                } else {
                    encoding[[pos, i]] = angle.cos();
                }
            }
        }

        Self { encoding }
    }

    fn get(&self, position: usize) -> Array1<f32> {
        self.encoding.row(position).to_owned()
    }
}

impl Activation {
    fn forward(&self, input: &Array2<f32>) -> Array2<f32> {
        match self {
            Activation::Gelu => {
                // GELU activation: x * Φ(x)
                input.mapv(|x| {
                    x * 0.5 * (1.0 + ((2.0 / PI).sqrt() * (x + 0.044715 * x.powi(3))).tanh())
                })
            }
            Activation::Relu => input.mapv(|x| x.max(0.0)),
        }
    }
}

// Helper functions

fn softmax(logits: &Array1<f32>) -> Array1<f32> {
    let max = logits.fold(f32::NEG_INFINITY, |a, &b| a.max(b));
    let exp_logits = logits.mapv(|x| (x - max).exp());
    let sum = exp_logits.sum();
    exp_logits / sum
}

fn dropout(input: Array2<f32>, rate: f32) -> Array2<f32> {
    if rate == 0.0 {
        return input;
    }

    // In training mode, randomly drop elements
    // For inference, we skip dropout
    input // Simplified: no dropout in inference
}

fn sample_from_probs(probs: &Array1<f32>) -> usize {
    let mut rng = rand::thread_rng();
    let sample = rand::random::<f32>();

    let mut cumsum = 0.0;
    for (i, &p) in probs.iter().enumerate() {
        cumsum += p;
        if sample < cumsum {
            return i;
        }
    }

    probs.len() - 1
}

// Macro imports for slicing
use ndarray::s;

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_transformer_forward() {
        let config = TransformerConfig {
            vocab_size: 100,
            hidden_size: 64,
            num_layers: 2,
            num_heads: 4,
            ff_size: 128,
            max_seq_len: 32,
            dropout: 0.0,
            layer_norm_eps: 1e-5,
        };

        let model = Transformer::new(config);
        let input_ids = vec![1, 2, 3, 4, 5];
        let output = model.forward(&input_ids, None);

        assert_eq!(output.shape(), &[5, 100]);
    }

    #[test]
    fn test_attention_mechanism() {
        let attention = MultiHeadAttention::new(64, 4);

        let seq_len = 10;
        let hidden_size = 64;
        let input = Array2::ones((seq_len, hidden_size));
        let mask = vec![true; seq_len];

        let output = attention.forward(&input, &input, &input, &mask);
        assert_eq!(output.shape(), &[seq_len, hidden_size]);
    }
}
