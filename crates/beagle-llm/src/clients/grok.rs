//! GrokClient - Grok 3 + Grok 4 Heavy no mesmo client
//!
//! Escolhe modelo dinamicamente:
//! - Grok 3: default (ilimitado, rápido)
//! - Grok 4 Heavy: quando model contém "heavy" ou max_tokens > 16000
//!
//! Features:
//! - Retry logic com exponential backoff
//! - Melhor tratamento de erros de rede
//! - Logging detalhado com contexto

use crate::{LlmClient, LlmRequest};
use async_trait::async_trait;
use reqwest::Client;
use std::env;
use std::time::Duration;
use tracing::{debug, error, info, warn};

#[derive(Clone)]
pub struct GrokClient {
    client: Client,
    api_key: String,
    max_retries: u32,
    initial_backoff_ms: u64,
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
        let api_key = env::var("XAI_API_KEY").unwrap_or_else(|_| {
            warn!("XAI_API_KEY não configurada, usando valor vazio (falhará em runtime)");
            String::new()
        });

        let max_retries = env::var("BEAGLE_LLM_MAX_RETRIES")
            .ok()
            .and_then(|v| v.parse().ok())
            .unwrap_or(3);

        let initial_backoff_ms = env::var("BEAGLE_LLM_BACKOFF_MS")
            .ok()
            .and_then(|v| v.parse().ok())
            .unwrap_or(1000);

        Self {
            client: Client::builder()
                .timeout(Duration::from_secs(300)) // 5 min timeout
                .build()
                .unwrap_or_else(|_| Client::new()),
            api_key,
            max_retries,
            initial_backoff_ms,
        }
    }

    /// Escolhe modelo baseado em request e flags
    fn choose_model(&self, req: &LlmRequest, force_heavy: bool) -> String {
        // Se o modelo já contém "heavy" ou "4-heavy", usa Heavy
        if req.model.contains("heavy") || req.model.contains("4-heavy") {
            return "grok-4-heavy".to_string();
        }

        // Se force_heavy ou max_tokens muito alto, usa Heavy
        if force_heavy || req.max_tokens.unwrap_or(0) > 16000 {
            "grok-4-heavy".to_string()
        } else {
            "grok-3".to_string()
        }
    }

    /// Cria um novo GrokClient configurado para usar Heavy
    pub fn new_heavy() -> Self {
        Self::new()
    }
}

#[async_trait]
impl LlmClient for GrokClient {
    async fn chat(&self, mut req: LlmRequest) -> anyhow::Result<String> {
        // Detecta se deve forçar Heavy
        let force_heavy = req.model.contains("heavy") || req.model.contains("4-heavy");

        // Escolhe modelo dinamicamente
        req.model = self.choose_model(&req, force_heavy);

        debug!(
            "GrokClient: usando modelo {} (retries: {})",
            req.model, self.max_retries
        );

        let request_body = serde_json::json!({
            "model": req.model,
            "messages": req.messages,
            "temperature": req.temperature.unwrap_or(0.7),
            "max_tokens": req.max_tokens.unwrap_or(8192),
        });

        // Retry loop com exponential backoff
        let mut last_error = None;
        for attempt in 0..=self.max_retries {
            if attempt > 0 {
                let backoff = self.initial_backoff_ms * 2_u64.pow(attempt - 1);
                info!(
                    "GrokClient: retry {}/{}, aguardando {}ms",
                    attempt, self.max_retries, backoff
                );
                tokio::time::sleep(Duration::from_millis(backoff)).await;
            }

            match self.try_request(&request_body, &req.model).await {
                Ok(text) => {
                    if attempt > 0 {
                        info!("GrokClient: sucesso após {} tentativas", attempt);
                    }
                    return Ok(text);
                }
                Err(e) => {
                    if Self::is_retryable_error(&e) {
                        warn!(
                            "GrokClient: erro retryable na tentativa {}: {}",
                            attempt + 1,
                            e
                        );
                        last_error = Some(e);
                        continue;
                    } else {
                        error!("GrokClient: erro não-retryable: {}", e);
                        return Err(e);
                    }
                }
            }
        }

        // Todas as tentativas falharam
        error!(
            "GrokClient: todas as {} tentativas falharam",
            self.max_retries + 1
        );
        Err(last_error.unwrap_or_else(|| anyhow::anyhow!("Grok API: max retries exceeded")))
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

impl GrokClient {
    /// Tenta fazer a requisição uma vez
    async fn try_request(
        &self,
        request_body: &serde_json::Value,
        model: &str,
    ) -> anyhow::Result<String> {
        let response = self
            .client
            .post("https://api.x.ai/v1/chat/completions")
            .header("Authorization", format!("Bearer {}", self.api_key))
            .header("Content-Type", "application/json")
            .json(request_body)
            .send()
            .await
            .map_err(|e| {
                if e.is_timeout() {
                    anyhow::anyhow!("Grok API timeout (modelo: {}): {}", model, e)
                } else if e.is_connect() {
                    anyhow::anyhow!("Grok API connection error (modelo: {}): {}", model, e)
                } else {
                    anyhow::anyhow!("Grok API network error (modelo: {}): {}", model, e)
                }
            })?;

        let status = response.status();
        if !status.is_success() {
            let error_text = response.text().await.unwrap_or_default();

            // Contexto rico no erro
            let error_msg = format!(
                "Grok API error (modelo: {}, status: {}): {}",
                model, status, error_text
            );

            anyhow::bail!(error_msg);
        }

        let resp: ApiResponse = response.json().await?;

        if resp.choices.is_empty() {
            anyhow::bail!("Grok API retornou resposta vazia");
        }

        Ok(resp.choices[0].message.content.clone())
    }

    /// Verifica se um erro é retryable (transient)
    fn is_retryable_error(error: &anyhow::Error) -> bool {
        let error_msg = error.to_string().to_lowercase();

        // Network errors que podem ser temporários
        if error_msg.contains("timeout")
            || error_msg.contains("connection")
            || error_msg.contains("network")
            || error_msg.contains("dns")
        {
            return true;
        }

        // HTTP status codes retryable (rate limit, server errors)
        if error_msg.contains("429") // Rate limit
            || error_msg.contains("500") // Internal server error
            || error_msg.contains("502") // Bad gateway
            || error_msg.contains("503") // Service unavailable
            || error_msg.contains("504")
        // Gateway timeout
        {
            return true;
        }

        // Não retryable: auth errors, bad requests, etc.
        false
    }
}
