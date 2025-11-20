//! vLLM Client - Integração com vLLM server local
//!
//! Suporta batch completions (n > 1) para geração paralela de hipóteses

use anyhow::{Context, Result};
use reqwest::Client;
use serde::{Deserialize, Serialize};
use tracing::debug;

const DEFAULT_VLLM_URL: &str = "http://t560.local:8000/v1";

/// Request específico para vLLM (formato diferente do CompletionRequest padrão)
#[derive(Debug, Clone)]
pub struct VllmCompletionRequest {
    pub model: String,
    pub prompt: String,
    pub sampling_params: SamplingParams,
}

#[derive(Debug, Clone)]
pub struct VllmClient {
    client: Client,
    base_url: String,
}

#[derive(Debug, Serialize)]
struct VllmRequest {
    model: String,
    prompt: String,
    temperature: f64,
    top_p: f64,
    max_tokens: u32,
    n: u32,
    frequency_penalty: Option<f64>,
    stop: Option<Vec<String>>,
}

#[derive(Debug, Deserialize)]
pub struct VllmResponse {
    pub choices: Vec<VllmChoice>,
}

#[derive(Debug, Deserialize)]
pub struct VllmChoice {
    pub text: String,
    pub finish_reason: Option<String>,
}

#[derive(Debug, Clone)]
pub struct SamplingParams {
    pub temperature: f64,
    pub top_p: f64,
    pub max_tokens: u32,
    pub n: u32,
    pub stop: Option<Vec<String>>,
    pub frequency_penalty: f64,
}

impl Default for SamplingParams {
    fn default() -> Self {
        Self {
            temperature: 0.7,
            top_p: 0.95,
            max_tokens: 512,
            n: 1,
            stop: None,
            frequency_penalty: 0.0,
        }
    }
}

impl VllmClient {
    pub fn new(base_url: impl Into<String>) -> Self {
        Self {
            client: Client::new(),
            base_url: base_url.into(),
        }
    }

    pub fn default() -> Self {
        Self::new(DEFAULT_VLLM_URL)
    }

    /// Executa completions com suporte a batch (n > 1)
    pub async fn completions(&self, request: &VllmCompletionRequest) -> Result<VllmResponse> {
        let url = format!("{}/completions", self.base_url);

        let vllm_req = VllmRequest {
            model: request.model.clone(),
            prompt: request.prompt.clone(),
            temperature: request.sampling_params.temperature,
            top_p: request.sampling_params.top_p,
            max_tokens: request.sampling_params.max_tokens,
            n: request.sampling_params.n,
            frequency_penalty: Some(request.sampling_params.frequency_penalty),
            stop: request.sampling_params.stop.clone(),
        };

        debug!("Enviando requisição vLLM: {} hipóteses", vllm_req.n);

        let response = self
            .client
            .post(&url)
            .json(&vllm_req)
            .send()
            .await
            .context("Falha ao enviar requisição para vLLM")?;

        let status = response.status();
        if !status.is_success() {
            let error_text = response.text().await.unwrap_or_default();
            anyhow::bail!("vLLM retornou erro {}: {}", status, error_text);
        }

        let vllm_response: VllmResponse = response
            .json()
            .await
            .context("Falha ao decodificar resposta JSON do vLLM")?;

        debug!("vLLM retornou {} choices", vllm_response.choices.len());
        Ok(vllm_response)
    }
}
