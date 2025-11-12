//! Operadores de fusão multimodal com observabilidade reforçada.
//!
//! Este módulo consolida abstrações para combinar embeddings oriundos de
//! diferentes modalidades (texto, imagem, áudio, vídeo) com garantias de
//! normalização, rastreabilidade e telemetria alinhadas ao plano de
//! hardening da semana 5.

use std::fmt::Display;
use std::time::Instant;

use prometheus::{Counter, Gauge, Histogram, HistogramOpts, Opts, Registry};
use slog::{info, o, warn, Logger};
use thiserror::Error;
use tracing::instrument;

use crate::types::{Embedding, EMBEDDING_DIMENSION};

/// Modalidades suportadas no pipeline multimodal.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
pub enum Modality {
    Text,
    Image,
    Audio,
    Video,
}

impl Modality {
    pub fn all() -> [Modality; 4] {
        [
            Modality::Text,
            Modality::Image,
            Modality::Audio,
            Modality::Video,
        ]
    }
}

impl Display for Modality {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            Modality::Text => write!(f, "text"),
            Modality::Image => write!(f, "image"),
            Modality::Audio => write!(f, "audio"),
            Modality::Video => write!(f, "video"),
        }
    }
}

/// Erros potenciais durante a fusão multimodal.
#[derive(Debug, Error)]
pub enum FuseError {
    #[error("nenhum embedding informado")]
    EmptyInput,
    #[error("modalidade {modality} não possui projeção configurada")]
    MissingProjection { modality: Modality },
    #[error("dimensão incompatível: esperado {expected}, recebido {got}")]
    DimensionMismatch { expected: usize, got: usize },
    #[error("vetor resultante com norma zero (não normalizável)")]
    ZeroVector,
    #[error("falha ao construir embedding final: {0}")]
    InvalidEmbedding(String),
}

/// Estratégia de fusão multimodal.
pub trait FusionStrategy: Send + Sync {
    fn name(&self) -> &'static str;
    fn expected_dimension(&self) -> usize;
    fn fuse(&self, input: &MultiModalEmbeddingInput) -> Result<Embedding, FuseError>;
}

/// Configuração de normalização do resultado.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Default)]
pub enum Normalization {
    None,
    #[default]
    L2,
}

/// Matriz de projeção densa em formato linha-major.
#[derive(Debug, Clone)]
pub struct ProjectionMatrix {
    rows: usize,
    cols: usize,
    weights: Vec<f32>,
}

impl ProjectionMatrix {
    pub fn new(rows: usize, cols: usize, weights: Vec<f32>) -> Result<Self, FuseError> {
        if weights.len() != rows * cols {
            return Err(FuseError::DimensionMismatch {
                expected: rows * cols,
                got: weights.len(),
            });
        }
        Ok(Self {
            rows,
            cols,
            weights,
        })
    }

    pub fn identity(dimension: usize) -> Self {
        let mut weights = vec![0.0f32; dimension * dimension];
        for i in 0..dimension {
            weights[i * dimension + i] = 1.0;
        }
        Self {
            rows: dimension,
            cols: dimension,
            weights,
        }
    }

    pub fn project(&self, embedding: &Embedding) -> Result<Vec<f32>, FuseError> {
        if embedding.dimension() != self.cols {
            return Err(FuseError::DimensionMismatch {
                expected: self.cols,
                got: embedding.dimension(),
            });
        }

        let mut output = vec![0.0f32; self.rows];
        for (row, slot) in output.iter_mut().enumerate() {
            let base = row * self.cols;
            let weights_slice = &self.weights[base..base + self.cols];
            let mut acc = 0.0f32;
            for (weight, component) in weights_slice.iter().zip(embedding.iter()) {
                acc += weight * component;
            }
            *slot = acc;
        }
        Ok(output)
    }
}

/// Projeção configurável por modalidade.
#[derive(Debug, Clone)]
pub enum Projection {
    Identity,
    Linear(ProjectionMatrix),
}

impl Projection {
    fn apply(&self, embedding: &Embedding) -> Result<Vec<f32>, FuseError> {
        match self {
            Projection::Identity => Ok(embedding.clone().into()),
            Projection::Linear(matrix) => matrix.project(embedding),
        }
    }

    fn output_dimension(&self) -> usize {
        match self {
            Projection::Identity => EMBEDDING_DIMENSION,
            Projection::Linear(matrix) => matrix.rows,
        }
    }
}

/// Estratégia padrão de fusão linear com normalização L2.
pub struct LateFusionLinear {
    projections: Vec<(Modality, Projection)>,
    bias: Option<Vec<f32>>,
    normalization: Normalization,
    expected_dimension: usize,
}

impl LateFusionLinear {
    pub fn builder() -> LateFusionBuilder {
        LateFusionBuilder::default()
    }

    fn validate_dimension(&self) -> Result<(), FuseError> {
        for (_, projection) in &self.projections {
            if projection.output_dimension() != self.expected_dimension {
                return Err(FuseError::DimensionMismatch {
                    expected: self.expected_dimension,
                    got: projection.output_dimension(),
                });
            }
        }
        if let Some(bias) = &self.bias {
            if bias.len() != self.expected_dimension {
                return Err(FuseError::DimensionMismatch {
                    expected: self.expected_dimension,
                    got: bias.len(),
                });
            }
        }
        Ok(())
    }
}

impl FusionStrategy for LateFusionLinear {
    fn name(&self) -> &'static str {
        "late_fusion_linear"
    }

    fn expected_dimension(&self) -> usize {
        self.expected_dimension
    }

    fn fuse(&self, input: &MultiModalEmbeddingInput) -> Result<Embedding, FuseError> {
        self.validate_dimension()?;

        let mut accumulator = vec![0.0f32; self.expected_dimension];
        let mut used_modalities = 0usize;

        for (modality, projection) in &self.projections {
            if let Some(embedding) = input.get(*modality) {
                let projected = projection.apply(embedding)?;
                for (dst, value) in accumulator.iter_mut().zip(projected.iter()) {
                    *dst += value;
                }
                used_modalities += 1;
            }
        }

        if used_modalities == 0 {
            return Err(FuseError::EmptyInput);
        }

        if let Some(bias) = &self.bias {
            for (dst, value) in accumulator.iter_mut().zip(bias.iter()) {
                *dst += value;
            }
        }

        if self.normalization == Normalization::L2 {
            l2_normalize(&mut accumulator)?;
        }

        Embedding::new(accumulator).map_err(FuseError::InvalidEmbedding)
    }
}

/// Builder ergonômico para [`LateFusionLinear`].
pub struct LateFusionBuilder {
    projections: Vec<(Modality, Projection)>,
    bias: Option<Vec<f32>>,
    normalization: Normalization,
    expected_dimension: usize,
}

impl LateFusionBuilder {
    pub fn new() -> Self {
        Self {
            normalization: Normalization::default(),
            expected_dimension: EMBEDDING_DIMENSION,
            projections: Vec::new(),
            bias: None,
        }
    }

    pub fn expected_dimension(mut self, dimension: usize) -> Self {
        self.expected_dimension = dimension;
        self
    }

    pub fn normalization(mut self, normalization: Normalization) -> Self {
        self.normalization = normalization;
        self
    }

    pub fn with_projection(mut self, modality: Modality, projection: Projection) -> Self {
        self.projections.push((modality, projection));
        self
    }

    pub fn bias(mut self, bias: Vec<f32>) -> Self {
        self.bias = Some(bias);
        self
    }

    pub fn build(self) -> LateFusionLinear {
        LateFusionLinear {
            projections: self.projections,
            bias: self.bias,
            normalization: self.normalization,
            expected_dimension: self.expected_dimension,
        }
    }
}

impl Default for LateFusionBuilder {
    fn default() -> Self {
        Self::new()
    }
}

/// Multiset de embeddings recebidos para fusão.
#[derive(Debug, Default)]
pub struct MultiModalEmbeddingInput {
    text: Option<Embedding>,
    image: Option<Embedding>,
    audio: Option<Embedding>,
    video: Option<Embedding>,
}

impl MultiModalEmbeddingInput {
    pub fn with_text(mut self, embedding: Embedding) -> Self {
        self.text = Some(embedding);
        self
    }

    pub fn with_image(mut self, embedding: Embedding) -> Self {
        self.image = Some(embedding);
        self
    }

    pub fn with_audio(mut self, embedding: Embedding) -> Self {
        self.audio = Some(embedding);
        self
    }

    pub fn with_video(mut self, embedding: Embedding) -> Self {
        self.video = Some(embedding);
        self
    }

    pub fn get(&self, modality: Modality) -> Option<&Embedding> {
        match modality {
            Modality::Text => self.text.as_ref(),
            Modality::Image => self.image.as_ref(),
            Modality::Audio => self.audio.as_ref(),
            Modality::Video => self.video.as_ref(),
        }
    }

    pub fn present_modalities(&self) -> Vec<Modality> {
        let mut result = Vec::with_capacity(4);
        if self.text.is_some() {
            result.push(Modality::Text);
        }
        if self.image.is_some() {
            result.push(Modality::Image);
        }
        if self.audio.is_some() {
            result.push(Modality::Audio);
        }
        if self.video.is_some() {
            result.push(Modality::Video);
        }
        result
    }

    pub fn into_embedding(self, fused: Embedding) -> MultiModalEmbedding {
        MultiModalEmbedding {
            text: self.text,
            image: self.image,
            audio: self.audio,
            video: self.video,
            fused,
        }
    }
}

/// Resultado da fusão multimodal com componentes individuais preservados.
#[derive(Debug)]
pub struct MultiModalEmbedding {
    pub text: Option<Embedding>,
    pub image: Option<Embedding>,
    pub audio: Option<Embedding>,
    pub video: Option<Embedding>,
    pub fused: Embedding,
}

impl MultiModalEmbedding {
    pub fn modalities(&self) -> Vec<Modality> {
        let mut result = Vec::with_capacity(4);
        if self.text.is_some() {
            result.push(Modality::Text);
        }
        if self.image.is_some() {
            result.push(Modality::Image);
        }
        if self.audio.is_some() {
            result.push(Modality::Audio);
        }
        if self.video.is_some() {
            result.push(Modality::Video);
        }
        result
    }

    pub fn fused_norm(&self) -> f32 {
        l2_norm(&self.fused)
    }
}

/// Métricas Prometheus específicas para o pipeline multimodal.
#[derive(Debug, Clone)]
pub struct FusionMetrics {
    registry: Registry,
    fuse_latency: Histogram,
    fuse_failures: Counter,
    missing_modalities: Gauge,
    fused_norm: Gauge,
}

impl FusionMetrics {
    pub fn new(registry: &Registry) -> Result<Self, prometheus::Error> {
        let fuse_latency_opts = HistogramOpts::new(
            "beagle_multimodal_fuse_latency_seconds",
            "Latência do operador de fusão multimodal",
        )
        .buckets(vec![
            0.0005, 0.001, 0.005, 0.01, 0.025, 0.05, 0.1, 0.25, 0.5, 1.0,
        ]);
        let fuse_latency = Histogram::with_opts(fuse_latency_opts)?;

        let fuse_failures = Counter::with_opts(Opts::new(
            "beagle_multimodal_fuse_failures_total",
            "Falhas acumuladas do operador de fusão multimodal",
        ))?;

        let missing_modalities = Gauge::with_opts(Opts::new(
            "beagle_multimodal_missing_modalities",
            "Quantidade de modalidades ausentes por operação de fusão",
        ))?;

        let fused_norm = Gauge::with_opts(Opts::new(
            "beagle_multimodal_fused_norm",
            "Norma L2 do embedding após fusão",
        ))?;

        registry.register(Box::new(fuse_latency.clone()))?;
        registry.register(Box::new(fuse_failures.clone()))?;
        registry.register(Box::new(missing_modalities.clone()))?;
        registry.register(Box::new(fused_norm.clone()))?;

        Ok(Self {
            registry: registry.clone(),
            fuse_latency,
            fuse_failures,
            missing_modalities,
            fused_norm,
        })
    }

    pub fn registry(&self) -> &Registry {
        &self.registry
    }

    pub fn observe_success(&self, duration_secs: f64, missing: usize, fused_norm: f64) {
        self.fuse_latency.observe(duration_secs);
        self.missing_modalities.set(missing as f64);
        self.fused_norm.set(fused_norm);
    }

    pub fn observe_failure(&self) {
        self.fuse_failures.inc();
    }
}

/// Fachada principal que orquestra estratégia, métricas e logging.
pub struct FusionLayer<S: FusionStrategy> {
    strategy: S,
    metrics: Option<FusionMetrics>,
    logger: Logger,
}

impl<S: FusionStrategy> FusionLayer<S> {
    pub fn new(strategy: S) -> Self {
        Self {
            strategy,
            metrics: None,
            logger: Logger::root(slog::Discard, o!()),
        }
    }

    pub fn with_metrics(mut self, metrics: FusionMetrics) -> Self {
        self.metrics = Some(metrics);
        self
    }

    pub fn with_logger(mut self, logger: Logger) -> Self {
        self.logger = logger;
        self
    }

    #[instrument(
        name = "beagle.multimodal.fuse",
        skip(self, input),
        fields(strategy = self.strategy.name())
    )]
    pub fn fuse(&self, input: MultiModalEmbeddingInput) -> Result<MultiModalEmbedding, FuseError> {
        let start = Instant::now();
        let present = input.present_modalities();
        let missing_modalities = Modality::all()
            .iter()
            .filter(|modality| !present.contains(modality))
            .count();

        match self.strategy.fuse(&input) {
            Ok(fused) => {
                let duration = start.elapsed();
                let fused_norm = l2_norm(&fused) as f64;

                if let Some(metrics) = &self.metrics {
                    metrics.observe_success(duration.as_secs_f64(), missing_modalities, fused_norm);
                }

                info!(
                    self.logger,
                    "fusion_success";
                    "strategy" => self.strategy.name(),
                    "modalities_present" => format_modalities(&present),
                    "missing_modalities" => missing_modalities,
                    "latency_ms" => duration.as_secs_f64() * 1000.0,
                    "fused_norm" => fused_norm
                );

                Ok(input.into_embedding(fused))
            }
            Err(error) => {
                if let Some(metrics) = &self.metrics {
                    metrics.observe_failure();
                }
                warn!(
                    self.logger,
                    "fusion_failure";
                    "strategy" => self.strategy.name(),
                    "modalities_present" => format_modalities(&present),
                    "error" => error.to_string()
                );
                Err(error)
            }
        }
    }
}

fn l2_norm(embedding: &Embedding) -> f32 {
    embedding
        .iter()
        .map(|value| value * value)
        .sum::<f32>()
        .sqrt()
}

fn l2_normalize(vector: &mut [f32]) -> Result<(), FuseError> {
    let norm = vector.iter().map(|x| x * x).sum::<f32>().sqrt();
    if norm == 0.0 {
        return Err(FuseError::ZeroVector);
    }
    for value in vector.iter_mut() {
        *value /= norm;
    }
    Ok(())
}

fn format_modalities(modalities: &[Modality]) -> String {
    modalities
        .iter()
        .map(|m| m.to_string())
        .collect::<Vec<_>>()
        .join(",")
}

#[cfg(test)]
mod tests {
    use super::*;
    use proptest::prelude::*;

    fn create_strategy() -> LateFusionLinear {
        LateFusionLinear::builder()
            .expected_dimension(EMBEDDING_DIMENSION)
            .with_projection(Modality::Text, Projection::Identity)
            .with_projection(Modality::Image, Projection::Identity)
            .build()
    }

    fn dummy_embedding(value: f32) -> Embedding {
        let mut data = vec![0.0f32; EMBEDDING_DIMENSION];
        data.iter_mut().for_each(|v| *v = value);
        Embedding::from(data)
    }

    #[test]
    fn fuse_text_only() {
        let strategy = create_strategy();
        let layer = FusionLayer::new(strategy);

        let input = MultiModalEmbeddingInput::default().with_text(dummy_embedding(1.0));
        let result = layer.fuse(input).expect("fusão deve funcionar");
        assert!(result.fused_norm() > 0.0);
        assert!(result.image.is_none());
    }

    #[test]
    fn fuse_empty_input_fails() {
        let strategy = create_strategy();
        let layer = FusionLayer::new(strategy);
        let result = layer.fuse(MultiModalEmbeddingInput::default());
        assert!(matches!(result, Err(FuseError::EmptyInput)));
    }

    proptest! {
        #[test]
        fn normalization_preserves_unit_norm(values in prop::collection::vec(-1.0f32..1.0, EMBEDDING_DIMENSION)) {
            prop_assume!(values.iter().any(|v| *v != 0.0));
            let embedding = Embedding::from(values);
            let strategy = LateFusionLinear::builder()
                .expected_dimension(EMBEDDING_DIMENSION)
                .with_projection(Modality::Text, Projection::Identity)
                .build();
            let layer = FusionLayer::new(strategy);
            let result = layer
                .fuse(MultiModalEmbeddingInput::default().with_text(embedding))
                .expect("fusão com normalização deve funcionar");
            prop_assert!((result.fused_norm() - 1.0).abs() < 1e-4);
        }
    }
}
