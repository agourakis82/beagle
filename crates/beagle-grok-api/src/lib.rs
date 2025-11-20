//! xAI Grok API Client - Integração com Grok 4 / Grok 4 Heavy
//!
//! Wrapper completo para API xAI Grok:
//! • Suporta Grok-4 e Grok-4-Heavy
//! • Contexto 256k real (sem derretimento)
//! • Zero censura (paradox/void/abyss roda livre)
//! • Custo 75-80% menor que Anthropic
//!
//! Compatível 100% com estilo do código atual (mesmo padrão vLLM client).

use anyhow::Result;
use reqwest::{header, Client};
use serde::{Deserialize, Serialize};
use thiserror::Error;
use tracing::{debug, info, warn};

const GROK_API_URL: &str = "https://api.x.ai/v1/chat/completions";

#[derive(Error, Debug)]
pub enum GrokError {
    #[error("HTTP error: {0}")]
    Http(#[from] reqwest::Error),
    #[error("API error: {0}")]
    Api(String),
    #[error("Invalid response: {0}")]
    InvalidResponse(String),
}

/// Modelos disponíveis na xAI Grok API
#[derive(Debug, Clone, Copy)]
pub enum GrokModel {
    /// Grok-3 (rápido, 128k contexto, ILIMITADO no plano Heavy, qualidade Claude Sonnet 4.5)
    Grok3,
    /// Grok-4 (modelo padrão)
    Grok4,
    /// Grok-4-Heavy (monstro 256k, quota alta mas não ilimitada)
    Grok4Heavy,
}

impl GrokModel {
    pub fn as_str(&self) -> &'static str {
        match self {
            GrokModel::Grok3 => "grok-3",
            GrokModel::Grok4 => "grok-4",
            GrokModel::Grok4Heavy => "grok-4-heavy",
        }
    }
}

#[derive(Debug, Serialize, Deserialize, Clone)]
pub struct GrokMessage {
    role: String,
    content: String,
}

#[derive(Debug, Serialize)]
struct GrokRequest {
    model: String,
    messages: Vec<GrokMessage>,
    #[serde(skip_serializing_if = "Option::is_none")]
    temperature: Option<f32>,
    #[serde(skip_serializing_if = "Option::is_none")]
    max_tokens: Option<u32>,
    #[serde(skip_serializing_if = "Option::is_none")]
    top_p: Option<f32>,
}

#[derive(Debug, Deserialize)]
struct GrokChoice {
    message: GrokMessage,
    #[serde(default)]
    finish_reason: Option<String>,
}

#[derive(Debug, Deserialize)]
struct GrokResponse {
    choices: Vec<GrokChoice>,
    #[serde(default)]
    usage: Option<GrokUsage>,
}

#[derive(Debug, Deserialize)]
struct GrokUsage {
    #[serde(default)]
    prompt_tokens: Option<u32>,
    #[serde(default)]
    completion_tokens: Option<u32>,
    #[serde(default)]
    total_tokens: Option<u32>,
}

/// Cliente para API xAI Grok
pub struct GrokClient {
    client: Client,
    #[allow(dead_code)] // Mantido para possível uso futuro (rate limiting, etc)
    api_key: String,
    model: GrokModel,
}

impl GrokClient {
    /// Cria novo cliente Grok com API key
    pub fn new(api_key: &str) -> Self {
        Self::with_model(api_key, GrokModel::Grok4Heavy)
    }

    /// Cria cliente com modelo específico
    pub fn with_model(api_key: &str, model: GrokModel) -> Self {
        let mut headers = header::HeaderMap::new();
        headers.insert(
            "Authorization",
            header::HeaderValue::from_str(&format!("Bearer {}", api_key))
                .expect("Invalid API key format"),
        );
        headers.insert(
            "Content-Type",
            header::HeaderValue::from_static("application/json"),
        );

        let client = Client::builder()
            .default_headers(headers)
            .build()
            .expect("Failed to create HTTP client");

        Self {
            client,
            api_key: api_key.to_string(),
            model,
        }
    }

    /// Chat completo com sistema e usuário
    pub async fn chat(&self, prompt: &str, system: Option<&str>) -> Result<String, GrokError> {
        let mut messages = vec![];

        if let Some(sys) = system {
            messages.push(GrokMessage {
                role: "system".to_string(),
                content: sys.to_string(),
            });
        }

        messages.push(GrokMessage {
            role: "user".to_string(),
            content: prompt.to_string(),
        });

        self.chat_with_messages(messages, None, None, None).await
    }

    /// Chat com controle completo de parâmetros
    pub async fn chat_with_params(
        &self,
        prompt: &str,
        system: Option<&str>,
        temperature: Option<f32>,
        max_tokens: Option<u32>,
        top_p: Option<f32>,
    ) -> Result<String, GrokError> {
        let mut messages = vec![];

        if let Some(sys) = system {
            messages.push(GrokMessage {
                role: "system".to_string(),
                content: sys.to_string(),
            });
        }

        messages.push(GrokMessage {
            role: "user".to_string(),
            content: prompt.to_string(),
        });

        self.chat_with_messages(messages, temperature, max_tokens, top_p)
            .await
    }

    /// Chat com lista de mensagens (para conversas multi-turn)
    pub async fn chat_with_messages(
        &self,
        messages: Vec<GrokMessage>,
        temperature: Option<f32>,
        max_tokens: Option<u32>,
        top_p: Option<f32>,
    ) -> Result<String, GrokError> {
        let request_body = GrokRequest {
            model: self.model.as_str().to_string(),
            messages,
            temperature: temperature.or(Some(0.8)),
            max_tokens: max_tokens.or(Some(8192)),
            top_p: top_p.or(Some(0.95)),
        };

        debug!("Enviando requisição para Grok {}...", self.model.as_str());

        let response = self
            .client
            .post(GROK_API_URL)
            .json(&request_body)
            .send()
            .await
            .map_err(GrokError::Http)?;

        let status = response.status();

        if !status.is_success() {
            let text = response.text().await.unwrap_or_default();
            warn!("xAI Grok API error {}: {}", status, text);
            return Err(GrokError::Api(format!("Status {}: {}", status, text)));
        }

        let grok_resp: GrokResponse = response
            .json()
            .await
            .map_err(|e| GrokError::InvalidResponse(format!("Failed to parse response: {}", e)))?;

        if grok_resp.choices.is_empty() {
            return Err(GrokError::InvalidResponse(
                "No choices in API response".to_string(),
            ));
        }

        let content = grok_resp.choices[0].message.content.clone();

        // Log usage se disponível
        if let Some(usage) = grok_resp.usage {
            debug!(
                "Grok tokens: prompt={:?}, completion={:?}, total={:?}",
                usage.prompt_tokens, usage.completion_tokens, usage.total_tokens
            );
        }

        info!(
            "✅ Grok {} response recebido - {} chars",
            self.model.as_str(),
            content.len()
        );

        Ok(content)
    }

    /// Função simples pra usar igual query_llm atual (compatibilidade)
    pub async fn query(&self, prompt: &str) -> Result<String, GrokError> {
        self.chat(prompt, None).await
    }

    /// Query com temperatura customizada
    pub async fn query_with_temp(
        &self,
        prompt: &str,
        temperature: f32,
    ) -> Result<String, GrokError> {
        self.chat_with_params(prompt, None, Some(temperature), None, None)
            .await
    }

    /// Define modelo e retorna Self (builder pattern)
    ///
    /// # Example
    /// ```rust
    /// let client = GrokClient::new("key").model("grok-3");
    /// ```
    pub fn model(mut self, model_str: &str) -> Self {
        self.model = match model_str {
            "grok-3" => GrokModel::Grok3,
            "grok-4" => GrokModel::Grok4,
            "grok-4-heavy" => GrokModel::Grok4Heavy,
            _ => GrokModel::Grok3, // Default para grok-3
        };
        self
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_grok_model_str() {
        assert_eq!(GrokModel::Grok3.as_str(), "grok-3");
        assert_eq!(GrokModel::Grok4.as_str(), "grok-4");
        assert_eq!(GrokModel::Grok4Heavy.as_str(), "grok-4-heavy");
    }

    #[tokio::test]
    #[ignore] // Requer API key real
    async fn test_grok_client_creation() {
        let client = GrokClient::new("test-key");
        assert_eq!(client.model.as_str(), "grok-4-heavy");
    }

    #[tokio::test]
    async fn test_grok_client_with_model() {
        let client = GrokClient::with_model("test-key", GrokModel::Grok4);
        assert_eq!(client.model.as_str(), "grok-4");
    }
}
