//! GrokClient - Grok 3 + Grok 4 Heavy no mesmo client
//!
//! Escolhe modelo dinamicamente:
//! - Grok 3: default (ilimitado, rápido)
//! - Grok 4 Heavy: quando model contém "heavy" ou max_tokens > 16000

use crate::{LlmClient, LlmRequest};
use async_trait::async_trait;
use reqwest::Client;
use std::env;
use tracing::{debug, warn};

#[derive(Clone)]
pub struct GrokClient {
    client: Client,
    api_key: String,
}

#[derive(Debug, serde::Deserialize)]
struct ChoiceMessage {
    content: String,
}

#[derive(Debug, serde::Deserialize)]
struct Choice {
    message: ChoiceMessage,
}

#[derive(Debug, serde::Deserialize)]
struct ApiResponse {
    choices: Vec<Choice>,
}

impl GrokClient {
    pub fn new() -> Self {
        let api_key = env::var("XAI_API_KEY")
            .unwrap_or_else(|_| {
                warn!("XAI_API_KEY não configurada, usando valor vazio (falhará em runtime)");
                String::new()
            });

        Self {
            client: Client::new(),
            api_key,
        }
    }

    /// Escolhe modelo baseado em request e flags
    fn choose_model(&self, req: &LlmRequest, force_heavy: bool) -> String {
        if force_heavy || req.max_tokens.unwrap_or(0) > 16000 {
            "grok-4-heavy".to_string()
        } else {
            "grok-3".to_string()
        }
    }
}

#[async_trait]
impl LlmClient for GrokClient {
    async fn chat(&self, mut req: LlmRequest) -> anyhow::Result<String> {
        // Detecta se deve forçar Heavy
        let force_heavy = req.model.contains("heavy") || req.model.contains("4-heavy");
        
        // Escolhe modelo dinamicamente
        req.model = self.choose_model(&req, force_heavy);

        debug!("GrokClient: usando modelo {}", req.model);

        let request_body = serde_json::json!({
            "model": req.model,
            "messages": req.messages,
            "temperature": req.temperature.unwrap_or(0.7),
            "max_tokens": req.max_tokens.unwrap_or(8192),
        });

        let response = self
            .client
            .post("https://api.x.ai/v1/chat/completions")
            .header("Authorization", format!("Bearer {}", self.api_key))
            .header("Content-Type", "application/json")
            .json(&request_body)
            .send()
            .await?;

        let status = response.status();
        if !status.is_success() {
            let error_text = response.text().await.unwrap_or_default();
            anyhow::bail!("Grok API error {}: {}", status, error_text);
        }

        let resp: ApiResponse = response.json().await?;

        if resp.choices.is_empty() {
            anyhow::bail!("Grok API retornou resposta vazia");
        }

        Ok(resp.choices[0].message.content.clone())
    }

    fn name(&self) -> &'static str {
        "grok"
    }

    fn tier(&self) -> crate::Tier {
        crate::Tier::CloudGrokMain
    }

    fn prefers_heavy(&self) -> bool {
        true // Grok 4 Heavy existe e é melhor em viés
    }
}

