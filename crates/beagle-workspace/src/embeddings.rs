//! Embeddings SOTA - 100% Rust
//! Suporta: nomic, jina, gte-Qwen2 via HTTP

use anyhow::{Context, Result};
use reqwest::Client;
use serde::{Deserialize, Serialize};
use serde_json::json;
use std::fmt;
use tracing::info;

#[derive(Debug, Clone, Copy)]
pub enum EmbeddingModel {
    Nomic,
    Jina,
    GteQwen2,
}

impl fmt::Display for EmbeddingModel {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            EmbeddingModel::Nomic => write!(f, "nomic-embed-text-v1"),
            EmbeddingModel::Jina => write!(f, "jina-embeddings-v2-base-en"),
            EmbeddingModel::GteQwen2 => write!(f, "gte-Qwen2"),
        }
    }
}

pub struct EmbeddingManager {
    model: EmbeddingModel,
    client: Client,
    api_key: Option<String>,
}

impl EmbeddingManager {
    pub fn new(model: EmbeddingModel) -> Self {
        info!("🧠 EmbeddingManager inicializado: {}", model);
        Self {
            model,
            client: Client::new(),
            api_key: std::env::var("EMBEDDING_API_KEY").ok(),
        }
    }

    pub async fn encode(&self, texts: &[String]) -> Result<Vec<Vec<f32>>> {
        info!("📝 Encoding {} textos com {}", texts.len(), self.model);
        
        match self.model {
            EmbeddingModel::Nomic => self.encode_nomic(texts).await,
            EmbeddingModel::Jina => self.encode_jina(texts).await,
            EmbeddingModel::GteQwen2 => self.encode_gte_qwen2(texts).await,
        }
    }

    async fn encode_nomic(&self, texts: &[String]) -> Result<Vec<Vec<f32>>> {
        let url = "https://api-atlas.nomic.ai/v1/embedding/text";
        let body = json!({
            "model": "nomic-embed-text-v1",
            "texts": texts,
            "task_type": "search_document"
        });

        let mut req = self.client.post(url).json(&body);
        if let Some(key) = &self.api_key {
            req = req.header("Authorization", format!("Bearer {}", key));
        }

        let resp = req.send().await.context("Falha ao chamar Nomic API")?;
        let data: serde_json::Value = resp.json().await?;
        
        let embeddings: Vec<Vec<f32>> = data["embeddings"]
            .as_array()
            .context("Resposta inválida")?
            .iter()
            .map(|v| {
                v.as_array()
                    .unwrap()
                    .iter()
                    .map(|x| x.as_f64().unwrap() as f32)
                    .collect()
            })
            .collect();

        Ok(embeddings)
    }

    async fn encode_jina(&self, texts: &[String]) -> Result<Vec<Vec<f32>>> {
        let url = "https://api.jina.ai/v1/embeddings";
        let body = json!({
            "model": "jina-embeddings-v2-base-en",
            "input": texts
        });

        let mut req = self.client.post(url).json(&body);
        if let Some(key) = &self.api_key {
            req = req.header("Authorization", format!("Bearer {}", key));
        }

        let resp = req.send().await.context("Falha ao chamar Jina API")?;
        let data: serde_json::Value = resp.json().await?;
        
        let embeddings: Vec<Vec<f32>> = data["data"]
            .as_array()
            .context("Resposta inválida")?
            .iter()
            .map(|item| {
                item["embedding"]
                    .as_array()
                    .unwrap()
                    .iter()
                    .map(|x| x.as_f64().unwrap() as f32)
                    .collect()
            })
            .collect();

        Ok(embeddings)
    }

    async fn encode_gte_qwen2(&self, texts: &[String]) -> Result<Vec<Vec<f32>>> {
        let url = std::env::var("GTE_QWEN2_URL")
            .unwrap_or_else(|_| "http://localhost:8001/v1/embeddings".to_string());
        
        let body = json!({
            "model": "gte-Qwen2",
            "input": texts
        });

        let resp = self
            .client
            .post(&url)
            .json(&body)
            .send()
            .await
            .context("Falha ao chamar GTE-Qwen2")?;
        
        let data: serde_json::Value = resp.json().await?;
        
        let embeddings: Vec<Vec<f32>> = data["data"]
            .as_array()
            .context("Resposta inválida")?
            .iter()
            .map(|item| {
                item["embedding"]
                    .as_array()
                    .unwrap()
                    .iter()
                    .map(|x| x.as_f64().unwrap() as f32)
                    .collect()
            })
            .collect();

        Ok(embeddings)
    }
}
