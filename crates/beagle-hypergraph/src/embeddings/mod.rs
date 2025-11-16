//! Abstrações e implementações de geração de embeddings para o hipergrafo.
//!
//! Este módulo consolida integrações remotas (OpenAI), pipelines locais
//! baseados em `SentenceTransformer` e estratégias híbridas com *circuit breaker*
//! e política de *fallback*. O objetivo é prover uma trait uniforme,
//! resiliente e extensível que possa ser consumida por motores semânticos,
//! rotinas de ingestão e serviços de sincronização.

pub mod fusion;

use std::{
    sync::Arc,
    time::{Duration, Instant},
};

use async_trait::async_trait;
use serde::{Deserialize, Serialize};
use tokio::sync::Mutex;
use tokio::time::sleep;

use crate::{
    resilience::retry::CircuitBreakerConfig,
    types::{Embedding, EMBEDDING_DIMENSION},
};

pub use fusion::{
    FuseError, FusionLayer, FusionMetrics, FusionStrategy, LateFusionBuilder, LateFusionLinear,
    Modality, MultiModalEmbedding, MultiModalEmbeddingInput, Normalization, Projection,
    ProjectionMatrix,
};

/// Erro especializado para geração de embeddings.
#[derive(Debug, thiserror::Error)]
pub enum EmbeddingError {
    #[error("Upstream service error: {0}")]
    Upstream(String),
    #[error("Rate limited; retry suggested after {0:?}")]
    RateLimited(Option<Duration>),
    #[error("Invalid embedding dimension: expected {expected}, got {got}")]
    InvalidDimension { expected: usize, got: usize },
    #[error("Circuit breaker open; retry after {remaining:?}")]
    CircuitOpen { remaining: Duration },
    #[error("Local model error: {0}")]
    LocalModel(String),
    #[error("Empty embedding response")]
    EmptyResponse,
    #[error("Internal embedding error: {0}")]
    Internal(String),
}

impl EmbeddingError {
    /// Indica se a falha é potencialmente transitória (elegível para fallback).
    pub fn is_transient(&self) -> bool {
        matches!(
            self,
            EmbeddingError::Upstream(_)
                | EmbeddingError::RateLimited(_)
                | EmbeddingError::CircuitOpen { .. }
        )
    }
}

/// Gerador assíncrono de embeddings para textos.
#[async_trait]
pub trait EmbeddingGenerator: Send + Sync {
    async fn generate(&self, text: &str) -> Result<Embedding, EmbeddingError>;

    async fn batch_generate(&self, texts: &[&str]) -> Result<Vec<Embedding>, EmbeddingError>;

    fn model_name(&self) -> &str;

    fn dimension(&self) -> usize;
}

/// Rate limiter simples baseado em janela deslizante.
#[derive(Debug)]
pub struct RateLimiter {
    interval: Duration,
    state: Mutex<Instant>,
}

impl RateLimiter {
    pub fn new(interval: Duration) -> Self {
        Self {
            interval,
            state: Mutex::new(
                Instant::now()
                    .checked_sub(interval)
                    .unwrap_or_else(Instant::now),
            ),
        }
    }

    pub async fn until_ready(&self) {
        let mut last = self.state.lock().await;
        let now = Instant::now();
        if let Some(remaining) = self
            .interval
            .checked_sub(now.saturating_duration_since(*last))
        {
            sleep(remaining).await;
        }
        *last = Instant::now();
    }
}

/// Implementação de embeddings via API OpenAI.
#[derive(Debug)]
pub struct OpenAIEmbeddings {
    client: reqwest::Client,
    api_key: String,
    model: String,
    rate_limiter: Arc<RateLimiter>,
    expected_dimension: usize,
}

impl OpenAIEmbeddings {
    pub fn new(api_key: String) -> Self {
        Self::with_model(api_key, "text-embedding-3-large".into())
    }

    pub fn with_model(api_key: String, model: String) -> Self {
        Self {
            client: reqwest::Client::new(),
            api_key,
            model,
            rate_limiter: Arc::new(RateLimiter::new(Duration::from_millis(100))),
            expected_dimension: EMBEDDING_DIMENSION,
        }
    }

    pub fn with_rate_limiter(mut self, rate_limiter: Arc<RateLimiter>) -> Self {
        self.rate_limiter = rate_limiter;
        self
    }

    async fn call_openai(&self, inputs: &[&str]) -> Result<Vec<Vec<f32>>, EmbeddingError> {
        #[derive(Serialize)]
        struct EmbedRequest<'a> {
            input: &'a [&'a str],
            model: &'a str,
        }

        #[derive(Deserialize)]
        struct EmbedResponse {
            data: Vec<EmbedData>,
        }

        #[derive(Deserialize)]
        struct EmbedData {
            embedding: Vec<f32>,
        }

        self.rate_limiter.until_ready().await;

        let response = self
            .client
            .post("https://api.openai.com/v1/embeddings")
            .bearer_auth(&self.api_key)
            .json(&EmbedRequest {
                input: inputs,
                model: &self.model,
            })
            .send()
            .await
            .map_err(|err| EmbeddingError::Upstream(format!("request error: {err}")))?;

        let status = response.status();

        if !status.is_success() {
            let detail = response
                .text()
                .await
                .unwrap_or_else(|_| "unknown error".to_string());

            return match status.as_u16() {
                429 => Err(EmbeddingError::RateLimited(None)),
                500..=599 => Err(EmbeddingError::Upstream(format!(
                    "server error {status}: {detail}"
                ))),
                _ => Err(EmbeddingError::Upstream(format!(
                    "unexpected status {status}: {detail}"
                ))),
            };
        }

        let payload = response
            .json::<EmbedResponse>()
            .await
            .map_err(|err| EmbeddingError::Upstream(format!("parse error: {err}")))?;

        if payload.data.is_empty() {
            return Err(EmbeddingError::EmptyResponse);
        }

        Ok(payload
            .data
            .into_iter()
            .map(|item| item.embedding)
            .collect())
    }

    fn validate_dimension(&self, vector: &[f32]) -> Result<(), EmbeddingError> {
        if vector.len() != self.expected_dimension {
            return Err(EmbeddingError::InvalidDimension {
                expected: self.expected_dimension,
                got: vector.len(),
            });
        }
        Ok(())
    }
}

#[async_trait]
impl EmbeddingGenerator for OpenAIEmbeddings {
    async fn generate(&self, text: &str) -> Result<Embedding, EmbeddingError> {
        let mut embeddings = self.batch_generate(&[text]).await?;
        embeddings.pop().ok_or(EmbeddingError::EmptyResponse)
    }

    async fn batch_generate(&self, texts: &[&str]) -> Result<Vec<Embedding>, EmbeddingError> {
        if texts.is_empty() {
            return Ok(Vec::new());
        }

        let raw_vectors = self.call_openai(texts).await?;

        if raw_vectors.len() != texts.len() {
            return Err(EmbeddingError::Internal(format!(
                "expected {} embeddings, received {}",
                texts.len(),
                raw_vectors.len()
            )));
        }

        let mut embeddings = Vec::with_capacity(raw_vectors.len());
        for vector in raw_vectors {
            self.validate_dimension(&vector)?;
            embeddings.push(Embedding::from(vector));
        }

        Ok(embeddings)
    }

    fn model_name(&self) -> &str {
        &self.model
    }

    fn dimension(&self) -> usize {
        self.expected_dimension
    }
}

/// Representa dispositivo de execução para modelos locais.
#[derive(Debug, Clone)]
pub enum Device {
    Cpu,
    Gpu(String),
}

/// Implementação minimalista de sentence transformer baseada em closures.
#[derive(Clone)]
pub struct SentenceTransformer {
    encoder: Arc<dyn Fn(&[&str]) -> anyhow::Result<Vec<Vec<f32>>> + Send + Sync>,
    dimension: usize,
}

impl SentenceTransformer {
    pub fn new<F>(dimension: usize, encoder: F) -> Self
    where
        F: Fn(&[&str]) -> anyhow::Result<Vec<Vec<f32>>> + Send + Sync + 'static,
    {
        Self {
            encoder: Arc::new(encoder),
            dimension,
        }
    }

    pub fn encode(&self, inputs: &[&str]) -> anyhow::Result<Vec<Vec<f32>>> {
        (self.encoder)(inputs)
    }

    pub fn dimension(&self) -> usize {
        self.dimension
    }
}

/// Implementação local baseada em `SentenceTransformer`.
#[derive(Clone)]
pub struct LocalEmbeddings {
    model: Arc<SentenceTransformer>,
    _device: Device,
}

impl LocalEmbeddings {
    pub fn new(model: Arc<SentenceTransformer>, device: Device) -> Self {
        Self {
            model,
            _device: device,
        }
    }

    fn validate_dimension(&self, vector: &[f32]) -> Result<(), EmbeddingError> {
        if vector.len() != self.model.dimension() {
            return Err(EmbeddingError::InvalidDimension {
                expected: self.model.dimension(),
                got: vector.len(),
            });
        }
        Ok(())
    }
}

#[async_trait]
impl EmbeddingGenerator for LocalEmbeddings {
    async fn generate(&self, text: &str) -> Result<Embedding, EmbeddingError> {
        let mut embeddings = self.batch_generate(&[text]).await?;
        embeddings.pop().ok_or(EmbeddingError::EmptyResponse)
    }

    async fn batch_generate(&self, texts: &[&str]) -> Result<Vec<Embedding>, EmbeddingError> {
        if texts.is_empty() {
            return Ok(Vec::new());
        }

        let model = self.model.clone();
        let inputs: Vec<String> = texts.iter().map(|t| t.to_string()).collect();

        let encoded = tokio::task::spawn_blocking(move || {
            let borrowed: Vec<&str> = inputs.iter().map(|s| s.as_str()).collect();
            model.encode(&borrowed)
        })
        .await
        .map_err(|err| EmbeddingError::Internal(format!("join error: {err}")))?
        .map_err(|err| EmbeddingError::LocalModel(err.to_string()))?;

        if encoded.len() != texts.len() {
            return Err(EmbeddingError::Internal(format!(
                "expected {} embeddings, received {}",
                texts.len(),
                encoded.len()
            )));
        }

        let mut embeddings = Vec::with_capacity(encoded.len());
        for vector in encoded {
            self.validate_dimension(&vector)?;
            embeddings.push(Embedding::from(vector));
        }

        Ok(embeddings)
    }

    fn model_name(&self) -> &str {
        "local-sentence-transformer"
    }

    fn dimension(&self) -> usize {
        self.model.dimension()
    }
}

/// Circuit breaker específico para pipelines híbridos.
#[derive(Debug, Clone)]
pub struct CircuitBreaker {
    inner: Arc<BreakerInner>,
}

#[derive(Debug)]
struct BreakerInner {
    config: CircuitBreakerConfig,
    state: Mutex<BreakerState>,
}

#[derive(Debug)]
enum BreakerState {
    Closed { consecutive_failures: usize },
    Open { opened_at: Instant },
    HalfOpen { consecutive_successes: usize },
}

#[derive(Debug)]
enum BreakerTransition {
    StillClosed,
    Opened,
}

impl CircuitBreaker {
    pub fn new(config: CircuitBreakerConfig) -> Self {
        assert!(
            config.failure_threshold > 0,
            "failure_threshold deve ser >= 1"
        );
        assert!(
            config.open_interval > Duration::from_millis(0),
            "open_interval deve ser positivo"
        );
        assert!(
            config.half_open_success_threshold > 0,
            "half_open_success_threshold deve ser >= 1"
        );
        let state = BreakerState::Closed {
            consecutive_failures: 0,
        };
        Self {
            inner: Arc::new(BreakerInner {
                config,
                state: Mutex::new(state),
            }),
        }
    }

    async fn can_execute(&self) -> Result<(), Duration> {
        let mut state = self.inner.state.lock().await;
        match &mut *state {
            BreakerState::Closed { .. } => Ok(()),
            BreakerState::Open { opened_at } => {
                let elapsed = opened_at.elapsed();
                if elapsed >= self.inner.config.open_interval {
                    *state = BreakerState::HalfOpen {
                        consecutive_successes: 0,
                    };
                    Ok(())
                } else {
                    Err(self.inner.config.open_interval.saturating_sub(elapsed))
                }
            }
            BreakerState::HalfOpen { .. } => Ok(()),
        }
    }

    async fn record_success(&self) {
        let mut state = self.inner.state.lock().await;
        match &mut *state {
            BreakerState::Closed {
                consecutive_failures,
            } => {
                *consecutive_failures = 0;
            }
            BreakerState::HalfOpen {
                consecutive_successes,
            } => {
                *consecutive_successes += 1;
                if *consecutive_successes >= self.inner.config.half_open_success_threshold {
                    *state = BreakerState::Closed {
                        consecutive_failures: 0,
                    };
                }
            }
            BreakerState::Open { .. } => {
                *state = BreakerState::Closed {
                    consecutive_failures: 0,
                };
            }
        }
    }

    async fn record_failure(&self) -> BreakerTransition {
        let mut state = self.inner.state.lock().await;
        match &mut *state {
            BreakerState::Closed {
                consecutive_failures,
            } => {
                *consecutive_failures += 1;
                if *consecutive_failures >= self.inner.config.failure_threshold {
                    *state = BreakerState::Open {
                        opened_at: Instant::now(),
                    };
                    BreakerTransition::Opened
                } else {
                    BreakerTransition::StillClosed
                }
            }
            BreakerState::HalfOpen { .. } => {
                *state = BreakerState::Open {
                    opened_at: Instant::now(),
                };
                BreakerTransition::Opened
            }
            BreakerState::Open { opened_at: _ } => BreakerTransition::Opened,
        }
    }
}

/// Pipeline com fallback controlado por circuit breaker.
pub struct HybridEmbeddingPipeline {
    primary: Box<dyn EmbeddingGenerator>,
    fallback: Box<dyn EmbeddingGenerator>,
    circuit_breaker: CircuitBreaker,
}

impl HybridEmbeddingPipeline {
    pub fn new(
        primary: Box<dyn EmbeddingGenerator>,
        fallback: Box<dyn EmbeddingGenerator>,
        circuit_breaker: CircuitBreaker,
    ) -> Self {
        Self {
            primary,
            fallback,
            circuit_breaker,
        }
    }

    async fn guard_primary(&self) -> Result<(), EmbeddingError> {
        match self.circuit_breaker.can_execute().await {
            Ok(()) => Ok(()),
            Err(remaining) => Err(EmbeddingError::CircuitOpen { remaining }),
        }
    }
}

#[async_trait]
impl EmbeddingGenerator for HybridEmbeddingPipeline {
    async fn generate(&self, text: &str) -> Result<Embedding, EmbeddingError> {
        if let Err(err) = self.guard_primary().await {
            if err.is_transient() {
                return self.fallback.generate(text).await;
            }
            return Err(err);
        }

        match self.primary.generate(text).await {
            Ok(result) => {
                self.circuit_breaker.record_success().await;
                Ok(result)
            }
            Err(primary_error) => {
                let transition = self.circuit_breaker.record_failure().await;
                if primary_error.is_transient() || matches!(transition, BreakerTransition::Opened) {
                    self.fallback.generate(text).await
                } else {
                    Err(primary_error)
                }
            }
        }
    }

    async fn batch_generate(&self, texts: &[&str]) -> Result<Vec<Embedding>, EmbeddingError> {
        if let Err(err) = self.guard_primary().await {
            if err.is_transient() {
                return self.fallback.batch_generate(texts).await;
            }
            return Err(err);
        }

        match self.primary.batch_generate(texts).await {
            Ok(result) => {
                self.circuit_breaker.record_success().await;
                Ok(result)
            }
            Err(primary_error) => {
                let transition = self.circuit_breaker.record_failure().await;
                if primary_error.is_transient() || matches!(transition, BreakerTransition::Opened) {
                    self.fallback.batch_generate(texts).await
                } else {
                    Err(primary_error)
                }
            }
        }
    }

    fn model_name(&self) -> &str {
        self.primary.model_name()
    }

    fn dimension(&self) -> usize {
        self.primary.dimension()
    }
}

/// Mock determinístico para cenários de teste.
pub struct MockEmbeddingGenerator;

#[async_trait]
impl EmbeddingGenerator for MockEmbeddingGenerator {
    async fn generate(&self, text: &str) -> Result<Embedding, EmbeddingError> {
        let mut result = vec![0.0f32; EMBEDDING_DIMENSION];
        let bytes = text.as_bytes();
        for (idx, value) in result.iter_mut().enumerate() {
            let byte = bytes.get(idx % bytes.len()).copied().unwrap_or(0);
            *value = (byte as f32 / 255.0) * 2.0 - 1.0;
        }
        Ok(Embedding::from(result))
    }

    async fn batch_generate(&self, texts: &[&str]) -> Result<Vec<Embedding>, EmbeddingError> {
        let mut outputs = Vec::with_capacity(texts.len());
        for text in texts {
            outputs.push(self.generate(text).await?);
        }
        Ok(outputs)
    }

    fn model_name(&self) -> &str {
        "mock-embedding-generator"
    }

    fn dimension(&self) -> usize {
        EMBEDDING_DIMENSION
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[tokio::test]
    async fn openai_dimension_validation() {
        let generator = OpenAIEmbeddings::with_model("sk-test".into(), "test-model".into());
        assert_eq!(generator.dimension(), EMBEDDING_DIMENSION);
    }

    #[tokio::test]
    async fn mock_generator_is_deterministic() {
        let generator = MockEmbeddingGenerator;
        let a = generator.generate("hello").await.unwrap();
        let b = generator.generate("hello").await.unwrap();
        assert_eq!(*a, *b);
    }

    #[tokio::test]
    async fn local_embeddings_respects_dimension() {
        let encoder = SentenceTransformer::new(EMBEDDING_DIMENSION, |inputs| {
            Ok(inputs
                .iter()
                .map(|_| vec![0.1f32; EMBEDDING_DIMENSION])
                .collect())
        });
        let generator = LocalEmbeddings::new(Arc::new(encoder), Device::Cpu);
        let embedding = generator.generate("test").await.unwrap();
        assert_eq!(embedding.dimension(), EMBEDDING_DIMENSION);
    }
}
