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

use crate::output::TokenUsage;
use crate::{LlmClient, LlmOutput, LlmRequest};
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

/// Token usage object returned by the XAI / Grok API.
#[derive(Debug, serde::Deserialize)]
struct GrokUsage {
    prompt_tokens: u32,
    completion_tokens: u32,
    total_tokens: u32,
}

#[derive(Debug, serde::Deserialize)]
struct ApiResponse {
    choices: Vec<Choice>,
    /// Present in all successful XAI API responses.
    usage: Option<GrokUsage>,
}

impl GrokClient {
    pub fn new() -> Self {
        Self::new_with_key(String::new())
    }

    /// Construct a GrokClient with an explicit API key.
    ///
    /// If `api_key` is empty the constructor falls back to the `XAI_API_KEY`
    /// environment variable (so the old zero-argument `new()` still works).
    /// Callers that hold an explicit key should prefer this constructor so the
    /// client actually uses it instead of silently re-reading the environment.
    pub fn new_with_key(api_key: String) -> Self {
        let api_key = if api_key.is_empty() {
            env::var("XAI_API_KEY").unwrap_or_else(|_| {
                warn!("XAI_API_KEY não configurada, usando valor vazio (falhará em runtime)");
                String::new()
            })
        } else {
            api_key
        };

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
            // grok-4-1-fast-reasoning: reasoning-capable, ~3s latency, much better than grok-3
            "grok-4-1-fast-reasoning".to_string()
        }
    }

    /// Cria um novo GrokClient configurado para usar Heavy
    pub fn new_heavy() -> Self {
        Self::new()
    }
}

#[async_trait]
impl LlmClient for GrokClient {
    /// Override: captures real usage from the XAI API response instead of estimating chars/4.
    async fn complete(&self, prompt: &str) -> anyhow::Result<LlmOutput> {
        let req = LlmRequest {
            model: "default".to_string(),
            messages: vec![crate::ChatMessage::user(prompt)],
            temperature: Some(0.7),
            max_tokens: Some(2048),
        };
        self.chat_metered(req, prompt).await
    }

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
                // Bounded exponential backoff with jitter (was uncapped initial*2^(attempt-1)). Cap 30s.
                let base = self
                    .initial_backoff_ms
                    .saturating_mul(1u64 << (attempt - 1).min(6))
                    .min(30_000);
                let jitter = std::time::SystemTime::now()
                    .duration_since(std::time::UNIX_EPOCH)
                    .map(|d| (d.subsec_nanos() as u64) % (base / 2 + 1))
                    .unwrap_or(0);
                let backoff = (base + jitter).min(30_000);
                info!(
                    "GrokClient: retry {}/{}, aguardando {}ms",
                    attempt, self.max_retries, backoff
                );
                tokio::time::sleep(Duration::from_millis(backoff)).await;
            }

            match self.try_request(&request_body, &req.model).await {
                Ok((text, _usage)) => {
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
    /// Tenta fazer a requisição uma vez.
    /// Returns (text, Option<measured TokenUsage>).
    async fn try_request(
        &self,
        request_body: &serde_json::Value,
        model: &str,
    ) -> anyhow::Result<(String, Option<TokenUsage>)> {
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

        let text = resp.choices[0].message.content.clone();
        let usage = resp
            .usage
            .map(|u| TokenUsage::measured(u.prompt_tokens, u.completion_tokens, u.total_tokens));

        Ok((text, usage))
    }

    /// Versão metered: retorna (text, LlmOutput com usage real se disponível).
    pub async fn chat_metered(
        &self,
        mut req: LlmRequest,
        prompt_for_fallback: &str,
    ) -> anyhow::Result<LlmOutput> {
        let force_heavy = req.model.contains("heavy") || req.model.contains("4-heavy");
        req.model = self.choose_model(&req, force_heavy);

        let request_body = serde_json::json!({
            "model": req.model,
            "messages": req.messages,
            "temperature": req.temperature.unwrap_or(0.7),
            "max_tokens": req.max_tokens.unwrap_or(8192),
        });

        let mut last_error = None;
        for attempt in 0..=self.max_retries {
            if attempt > 0 {
                let base = self
                    .initial_backoff_ms
                    .saturating_mul(1u64 << (attempt - 1).min(6))
                    .min(30_000);
                let jitter = std::time::SystemTime::now()
                    .duration_since(std::time::UNIX_EPOCH)
                    .map(|d| (d.subsec_nanos() as u64) % (base / 2 + 1))
                    .unwrap_or(0);
                tokio::time::sleep(Duration::from_millis((base + jitter).min(30_000))).await;
            }
            match self.try_request(&request_body, &req.model).await {
                Ok((text, maybe_usage)) => {
                    let output = match maybe_usage {
                        Some(u) => LlmOutput::with_measured_usage(text, prompt_for_fallback, u),
                        None => LlmOutput::from_text(text, prompt_for_fallback),
                    };
                    return Ok(output);
                }
                Err(e) => {
                    if Self::is_retryable_error(&e) {
                        last_error = Some(e);
                        continue;
                    } else {
                        return Err(e);
                    }
                }
            }
        }
        Err(last_error.unwrap_or_else(|| anyhow::anyhow!("Grok API: max retries exceeded")))
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
