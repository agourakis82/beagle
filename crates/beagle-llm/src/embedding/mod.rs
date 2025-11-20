//! Embedding Client - Integração com servidor de embeddings
//!
//! Suporta embedding de texto e cálculo de cosine similarity

use anyhow::{Context, Result};
use reqwest::Client;
use serde::{Deserialize, Serialize};
use tracing::debug;

const DEFAULT_EMBEDDING_URL: &str = "http://t560.local:8001/v1";

/// Tipo para representar um vetor de embedding
pub type Embedding = Vec<f64>;

#[derive(Debug, Clone)]
pub struct EmbeddingClient {
    client: Client,
    base_url: String,
}

#[derive(Debug, Serialize)]
struct EmbeddingRequest {
    model: String,
    input: Vec<String>,
}

#[derive(Debug, Deserialize)]
struct EmbeddingResponse {
    data: Vec<EmbeddingData>,
}

#[derive(Debug, Deserialize)]
struct EmbeddingData {
    embedding: Embedding,
    #[allow(dead_code)]
    index: usize,
}

impl EmbeddingClient {
    pub fn new(base_url: impl Into<String>) -> Self {
        Self {
            client: Client::new(),
            base_url: base_url.into(),
        }
    }

    pub fn default() -> Self {
        Self::new(DEFAULT_EMBEDDING_URL)
    }

    /// Gera embedding para um texto
    pub async fn embed(&self, text: &str) -> Result<Embedding> {
        let url = format!("{}/embeddings", self.base_url);

        let request = EmbeddingRequest {
            model: "BAAI/bge-large-en-v1.5".to_string(),
            input: vec![text.to_string()],
        };

        debug!(
            "Gerando embedding para texto: {}...",
            &text[..text.len().min(50)]
        );

        let response = self
            .client
            .post(&url)
            .json(&request)
            .send()
            .await
            .context("Falha ao enviar requisição de embedding")?;

        let status = response.status();
        if !status.is_success() {
            let error_text = response.text().await.unwrap_or_default();
            anyhow::bail!(
                "Servidor de embedding retornou erro {}: {}",
                status,
                error_text
            );
        }

        let embedding_response: EmbeddingResponse = response
            .json()
            .await
            .context("Falha ao decodificar resposta JSON do embedding")?;

        if embedding_response.data.is_empty() {
            anyhow::bail!("Resposta de embedding vazia");
        }

        Ok(embedding_response.data[0].embedding.clone())
    }

    /// Gera embeddings em batch
    pub async fn embed_batch(&self, texts: &[&str]) -> Result<Vec<Embedding>> {
        let url = format!("{}/embeddings", self.base_url);

        let request = EmbeddingRequest {
            model: "BAAI/bge-large-en-v1.5".to_string(),
            input: texts.iter().map(|s| s.to_string()).collect(),
        };

        debug!("Gerando {} embeddings em batch", texts.len());

        let response = self
            .client
            .post(&url)
            .json(&request)
            .send()
            .await
            .context("Falha ao enviar requisição de embedding batch")?;

        let status = response.status();
        if !status.is_success() {
            let error_text = response.text().await.unwrap_or_default();
            anyhow::bail!(
                "Servidor de embedding retornou erro {}: {}",
                status,
                error_text
            );
        }

        let embedding_response: EmbeddingResponse = response
            .json()
            .await
            .context("Falha ao decodificar resposta JSON do embedding batch")?;

        let mut embeddings = Vec::new();
        for data in embedding_response.data {
            embeddings.push(data.embedding);
        }

        Ok(embeddings)
    }

    /// Calcula cosine similarity entre dois embeddings
    pub fn cosine_similarity(a: &Embedding, b: &Embedding) -> f64 {
        if a.len() != b.len() {
            return 0.0;
        }

        let dot_product: f64 = a.iter().zip(b.iter()).map(|(x, y)| x * y).sum();
        let norm_a: f64 = a.iter().map(|x| x * x).sum::<f64>().sqrt();
        let norm_b: f64 = b.iter().map(|x| x * x).sum::<f64>().sqrt();

        if norm_a == 0.0 || norm_b == 0.0 {
            return 0.0;
        }

        dot_product / (norm_a * norm_b)
    }
}
