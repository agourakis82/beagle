//! Local Gemma Client - Tier 3 LocalFallback
//!
//! Uses Ollama as the local inference backend for Gemma models.
//! Supports: gemma2:9b, gemma2:2b, gemma:7b
//!
//! Prerequisites:
//! 1. Install Ollama: https://ollama.ai
//! 2. Pull model: `ollama pull gemma2:9b`
//! 3. Run server: `ollama serve` (default port 11434)
//!
//! Environment variables:
//! - OLLAMA_HOST: Ollama server URL (default: http://localhost:11434)
//! - BEAGLE_LOCAL_MODEL: Model to use (default: gemma2:9b)

use async_trait::async_trait;
use reqwest::Client;
use serde::{Deserialize, Serialize};
use std::env;
use std::time::Duration;
use tracing::{debug, info, warn};

use crate::{ChatMessage, LlmClient, LlmOutput, LlmRequest, Tier};

/// Ollama API request
#[derive(Debug, Serialize)]
struct OllamaRequest {
    model: String,
    messages: Vec<OllamaMessage>,
    stream: bool,
    #[serde(skip_serializing_if = "Option::is_none")]
    options: Option<OllamaOptions>,
}

#[derive(Debug, Serialize)]
struct OllamaMessage {
    role: String,
    content: String,
}

#[derive(Debug, Serialize)]
struct OllamaOptions {
    #[serde(skip_serializing_if = "Option::is_none")]
    temperature: Option<f32>,
    #[serde(skip_serializing_if = "Option::is_none")]
    num_predict: Option<i32>,
    #[serde(skip_serializing_if = "Option::is_none")]
    top_p: Option<f32>,
}

/// Ollama API response
#[derive(Debug, Deserialize)]
struct OllamaResponse {
    message: OllamaResponseMessage,
    #[serde(default)]
    done: bool,
    #[serde(default)]
    eval_count: Option<u32>,
    #[serde(default)]
    prompt_eval_count: Option<u32>,
}

#[derive(Debug, Deserialize)]
struct OllamaResponseMessage {
    role: String,
    content: String,
}

/// Local Gemma model variants
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum GemmaModel {
    /// Gemma 2 9B - Best quality, requires ~10GB VRAM
    Gemma2_9B,
    /// Gemma 2 2B - Faster, requires ~3GB VRAM
    Gemma2_2B,
    /// Gemma 7B (original) - Good balance
    Gemma_7B,
    /// Custom model name
    Custom,
}

impl GemmaModel {
    pub fn as_str(&self) -> &'static str {
        match self {
            GemmaModel::Gemma2_9B => "gemma2:9b",
            GemmaModel::Gemma2_2B => "gemma2:2b",
            GemmaModel::Gemma_7B => "gemma:7b",
            GemmaModel::Custom => "custom",
        }
    }

    pub fn from_str(s: &str) -> Self {
        match s.to_lowercase().as_str() {
            "gemma2:9b" | "gemma2-9b" | "gemma2_9b" => GemmaModel::Gemma2_9B,
            "gemma2:2b" | "gemma2-2b" | "gemma2_2b" => GemmaModel::Gemma2_2B,
            "gemma:7b" | "gemma-7b" | "gemma_7b" | "gemma" => GemmaModel::Gemma_7B,
            _ => GemmaModel::Custom,
        }
    }
}

/// Local Gemma client using Ollama
#[derive(Clone)]
pub struct LocalGemmaClient {
    client: Client,
    base_url: String,
    model: String,
    timeout_secs: u64,
}

impl LocalGemmaClient {
    /// Create client from environment variables
    pub fn from_env() -> anyhow::Result<Self> {
        let base_url =
            env::var("OLLAMA_HOST").unwrap_or_else(|_| "http://localhost:11434".to_string());

        let model = env::var("BEAGLE_LOCAL_MODEL").unwrap_or_else(|_| "gemma2:9b".to_string());

        let timeout_secs = env::var("BEAGLE_LOCAL_TIMEOUT")
            .ok()
            .and_then(|v| v.parse().ok())
            .unwrap_or(120);

        Self::new(&base_url, &model, timeout_secs)
    }

    /// Create client with specific configuration
    pub fn new(base_url: &str, model: &str, timeout_secs: u64) -> anyhow::Result<Self> {
        let client = Client::builder()
            .timeout(Duration::from_secs(timeout_secs))
            .build()?;

        info!(
            "LocalGemmaClient initialized: base_url={}, model={}, timeout={}s",
            base_url, model, timeout_secs
        );

        Ok(Self {
            client,
            base_url: base_url.trim_end_matches('/').to_string(),
            model: model.to_string(),
            timeout_secs,
        })
    }

    /// Create client with default Gemma 2 9B
    pub fn new_gemma2_9b() -> anyhow::Result<Self> {
        Self::new("http://localhost:11434", "gemma2:9b", 120)
    }

    /// Create client with Gemma 2 2B (faster, less VRAM)
    pub fn new_gemma2_2b() -> anyhow::Result<Self> {
        Self::new("http://localhost:11434", "gemma2:2b", 60)
    }

    /// Check if Ollama server is available
    pub async fn health_check(&self) -> bool {
        let url = format!("{}/api/tags", self.base_url);
        match self.client.get(&url).send().await {
            Ok(resp) => resp.status().is_success(),
            Err(e) => {
                debug!("Ollama health check failed: {}", e);
                false
            }
        }
    }

    /// Check if specific model is available
    pub async fn model_available(&self) -> bool {
        let url = format!("{}/api/tags", self.base_url);
        match self.client.get(&url).send().await {
            Ok(resp) => {
                if let Ok(tags) = resp.json::<OllamaTagsResponse>().await {
                    tags.models
                        .iter()
                        .any(|m| m.name == self.model || m.name.starts_with(&self.model))
                } else {
                    false
                }
            }
            Err(_) => false,
        }
    }

    /// Pull model if not available (blocking operation)
    pub async fn ensure_model(&self) -> anyhow::Result<()> {
        if self.model_available().await {
            debug!("Model {} already available", self.model);
            return Ok(());
        }

        info!("Pulling model {} (this may take a while)...", self.model);

        let url = format!("{}/api/pull", self.base_url);
        let body = serde_json::json!({
            "name": self.model,
            "stream": false
        });

        let resp = self
            .client
            .post(&url)
            .json(&body)
            .timeout(Duration::from_secs(3600)) // 1 hour for large models
            .send()
            .await?;

        if resp.status().is_success() {
            info!("Model {} pulled successfully", self.model);
            Ok(())
        } else {
            let error = resp.text().await.unwrap_or_default();
            anyhow::bail!("Failed to pull model {}: {}", self.model, error)
        }
    }
}

#[derive(Debug, Deserialize)]
struct OllamaTagsResponse {
    models: Vec<OllamaModelInfo>,
}

#[derive(Debug, Deserialize)]
struct OllamaModelInfo {
    name: String,
    #[serde(default)]
    size: u64,
}

#[async_trait]
impl LlmClient for LocalGemmaClient {
    async fn chat(&self, req: LlmRequest) -> anyhow::Result<String> {
        let url = format!("{}/api/chat", self.base_url);

        // Convert messages to Ollama format
        let messages: Vec<OllamaMessage> = req
            .messages
            .iter()
            .map(|m| OllamaMessage {
                role: m.role.clone(),
                content: m.content.clone(),
            })
            .collect();

        let ollama_req = OllamaRequest {
            model: if req.model == "default" {
                self.model.clone()
            } else {
                req.model.clone()
            },
            messages,
            stream: false,
            options: Some(OllamaOptions {
                temperature: req.temperature,
                num_predict: req.max_tokens.map(|t| t as i32),
                top_p: None,
            }),
        };

        debug!("Ollama request: model={}", ollama_req.model);

        let response = self.client.post(&url).json(&ollama_req).send().await?;

        if !response.status().is_success() {
            let status = response.status();
            let error_text = response.text().await.unwrap_or_default();

            // Check for common errors
            if error_text.contains("model") && error_text.contains("not found") {
                anyhow::bail!(
                    "Model '{}' not found. Run: ollama pull {}",
                    self.model,
                    self.model
                );
            }
            if error_text.contains("connection refused") {
                anyhow::bail!("Ollama server not running. Start with: ollama serve");
            }

            anyhow::bail!("Ollama API error {}: {}", status, error_text);
        }

        let resp: OllamaResponse = response.json().await?;

        debug!(
            "Ollama response: tokens_in={:?}, tokens_out={:?}",
            resp.prompt_eval_count, resp.eval_count
        );

        Ok(resp.message.content)
    }

    async fn complete(&self, prompt: &str) -> anyhow::Result<LlmOutput> {
        let req = LlmRequest {
            model: self.model.clone(),
            messages: vec![ChatMessage::user(prompt)],
            temperature: Some(0.7),
            max_tokens: Some(2048),
        };

        let text = self.chat(req).await?;
        Ok(LlmOutput::from_text(text, prompt))
    }

    fn name(&self) -> &'static str {
        "local-gemma"
    }

    fn tier(&self) -> Tier {
        Tier::LocalFallback
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_gemma_model_from_str() {
        assert_eq!(GemmaModel::from_str("gemma2:9b"), GemmaModel::Gemma2_9B);
        assert_eq!(GemmaModel::from_str("gemma2:2b"), GemmaModel::Gemma2_2B);
        assert_eq!(GemmaModel::from_str("gemma:7b"), GemmaModel::Gemma_7B);
        assert_eq!(GemmaModel::from_str("unknown"), GemmaModel::Custom);
    }

    #[tokio::test]
    async fn test_client_creation() {
        let client = LocalGemmaClient::new("http://localhost:11434", "gemma2:9b", 60);
        assert!(client.is_ok());
    }

    #[tokio::test]
    #[ignore] // Requires running Ollama server
    async fn test_health_check() {
        let client = LocalGemmaClient::from_env().unwrap();
        let healthy = client.health_check().await;
        println!("Ollama healthy: {}", healthy);
    }

    #[tokio::test]
    #[ignore] // Requires running Ollama server with model
    async fn test_completion() {
        let client = LocalGemmaClient::from_env().unwrap();
        let result = client.complete("What is 2+2?").await;

        match result {
            Ok(output) => println!("Response: {}", output.text),
            Err(e) => println!("Error: {}", e),
        }
    }
}
