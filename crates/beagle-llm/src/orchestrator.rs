//! LLM Orchestrator for multi-provider routing and ensemble modes.

use crate::anthropic::AnthropicClient;
use crate::clients::claude_cli::ClaudeCliClient;
use crate::clients::codex_cli::CodexCliClient;
use crate::clients::deepseek::DeepSeekClient;
use crate::models::{CompletionRequest, CompletionResponse};
use anyhow::Result;
use beagle_grok_api::GrokClient;
use beagle_personality::PersonalityEngine;
use std::sync::Arc;

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum Provider {
    Anthropic,
    OpenAI,
    Grok,
    DeepSeek,
    Gemini,
}

#[derive(Debug, Clone)]
pub enum ProviderStrategy {
    /// Route to single best provider based on task complexity
    SmartRouting,
    /// Use all available providers and combine results
    Ensemble,
    /// Specific provider only
    Specific(Provider),
}

#[derive(Clone)]
pub struct LLMOrchestrator {
    // CLI providers (highest priority - use paid subscriptions)
    claude_cli: Option<Arc<ClaudeCliClient>>,
    codex_cli: Option<Arc<CodexCliClient>>,

    // API providers (fallback when CLI unavailable)
    anthropic_api: Option<Arc<AnthropicClient>>,
    grok_api: Option<Arc<GrokClient>>,
    deepseek_api: Option<Arc<DeepSeekClient>>,

    strategy: ProviderStrategy,
}

pub struct ProviderResponse {
    pub provider: Provider,
    pub response: CompletionResponse,
}

pub struct EnsembleResult {
    pub responses: Vec<ProviderResponse>,
    pub combined: String,
}

impl LLMOrchestrator {
    /// Auto-configure orchestrator with available providers
    /// Priority: Claude CLI > Codex CLI > Claude OAuth > API keys
    pub fn auto_configure() -> Self {
        // Try CLI tools first (highest priority - uses paid subscriptions)
        let claude_cli = ClaudeCliClient::check_available()
            .then(|| ClaudeCliClient::new())
            .and_then(|r| r.ok())
            .map(Arc::new);

        let codex_cli = CodexCliClient::check_available()
            .then(|| CodexCliClient::new())
            .and_then(|r| r.ok())
            .map(Arc::new);

        // Fallback to API providers
        let anthropic_api = AnthropicClient::from_claude_code_session()
            .ok()
            .or_else(|| {
                std::env::var("ANTHROPIC_API_KEY")
                    .ok()
                    .and_then(|key| AnthropicClient::new(key).ok())
            })
            .map(Arc::new);

        // Grok API (xAI)
        let grok_api = std::env::var("XAI_API_KEY")
            .ok()
            .map(|key| Arc::new(GrokClient::new(&key)));

        // DeepSeek API (reads from env internally)
        let deepseek_api = std::env::var("DEEPSEEK_API_KEY")
            .ok()
            .map(|_| Arc::new(DeepSeekClient::new()));

        Self {
            claude_cli,
            codex_cli,
            anthropic_api,
            grok_api,
            deepseek_api,
            strategy: ProviderStrategy::SmartRouting,
        }
    }

    /// Create with specific strategy
    pub fn with_strategy(strategy: ProviderStrategy) -> Self {
        let mut orch = Self::auto_configure();
        orch.strategy = strategy;
        orch
    }

    /// Get list of available providers
    pub fn available_providers(&self) -> Vec<Provider> {
        let mut providers = Vec::new();
        if self.claude_cli.is_some() || self.anthropic_api.is_some() {
            providers.push(Provider::Anthropic);
        }
        if self.codex_cli.is_some() {
            providers.push(Provider::OpenAI);
        }
        if self.grok_api.is_some() {
            providers.push(Provider::Grok);
        }
        if self.deepseek_api.is_some() {
            providers.push(Provider::DeepSeek);
        }
        providers
    }

    /// Complete a request using the configured strategy
    pub async fn complete(&self, request: CompletionRequest) -> Result<CompletionResponse> {
        match &self.strategy {
            ProviderStrategy::SmartRouting => self.smart_route(request).await,
            ProviderStrategy::Specific(provider) => self.use_provider(provider, request).await,
            ProviderStrategy::Ensemble => {
                let ensemble = self.ensemble(request).await?;
                Ok(CompletionResponse {
                    content: ensemble.combined,
                    model: "ensemble".to_string(),
                    usage: serde_json::json!({}),
                })
            }
        }
    }

    /// Smart routing based on task complexity
    /// Priority: Claude CLI > Codex CLI > Anthropic OAuth/API
    async fn smart_route(&self, request: CompletionRequest) -> Result<CompletionResponse> {
        // Highest priority: Claude CLI (uses Claude MAX subscription)
        if let Some(cli) = &self.claude_cli {
            return cli.complete(request).await;
        }

        // Second priority: Codex CLI (uses ChatGPT Pro subscription)
        if let Some(cli) = &self.codex_cli {
            return cli.complete(request).await;
        }

        // Fallback: Anthropic API (OAuth or API key)
        if let Some(api) = &self.anthropic_api {
            return api.complete(request).await;
        }

        anyhow::bail!(
            "No providers available. Install 'claude' or 'codex' CLI, or set ANTHROPIC_API_KEY."
        )
    }

    /// Use a specific provider
    async fn use_provider(
        &self,
        provider: &Provider,
        request: CompletionRequest,
    ) -> Result<CompletionResponse> {
        match provider {
            Provider::Anthropic => {
                // Try CLI first, then API
                if let Some(cli) = &self.claude_cli {
                    cli.complete(request).await
                } else if let Some(api) = &self.anthropic_api {
                    api.complete(request).await
                } else {
                    anyhow::bail!("Anthropic provider not available. Install 'claude' CLI or set ANTHROPIC_API_KEY.")
                }
            }
            Provider::OpenAI => {
                // Use Codex CLI
                if let Some(cli) = &self.codex_cli {
                    cli.complete(request).await
                } else {
                    anyhow::bail!("OpenAI provider not available. Install 'codex' CLI (ChatGPT Pro required).")
                }
            }
            Provider::Grok => {
                if let Some(client) = &self.grok_api {
                    use serde_json::json;
                    // Extract prompt from messages
                    let prompt = request
                        .messages
                        .iter()
                        .map(|m| m.content.clone())
                        .collect::<Vec<_>>()
                        .join("\n");
                    let system = request.system.as_deref();
                    let response = client.chat(&prompt, system).await?;
                    Ok(CompletionResponse {
                        content: response,
                        model: "grok-4".to_string(),
                        usage: json!({}), // Grok doesn't provide token usage in response
                    })
                } else {
                    anyhow::bail!(
                        "Grok provider not available. Set XAI_API_KEY environment variable."
                    )
                }
            }
            Provider::DeepSeek => {
                if let Some(client) = &self.deepseek_api {
                    use crate::LlmClient;
                    use serde_json::json;
                    // Extract prompt from messages
                    let prompt = request
                        .messages
                        .iter()
                        .map(|m| m.content.clone())
                        .collect::<Vec<_>>()
                        .join("\n");
                    let output = client.complete(&prompt).await?;
                    Ok(CompletionResponse {
                        content: output.text,
                        model: "deepseek-chat".to_string(),
                        usage: json!({
                            "prompt_tokens": output.tokens_in_est,
                            "completion_tokens": output.tokens_out_est,
                            "total_tokens": output.tokens_in_est + output.tokens_out_est
                        }),
                    })
                } else {
                    anyhow::bail!("DeepSeek provider not available. Set DEEPSEEK_API_KEY environment variable.")
                }
            }
            Provider::Gemini => {
                anyhow::bail!("Gemini provider not yet integrated. Set GOOGLE_API_KEY to enable.")
            }
        }
    }

    /// Run ensemble mode (all providers)
    pub async fn ensemble(&self, request: CompletionRequest) -> Result<EnsembleResult> {
        let mut responses = Vec::new();

        // Collect responses from all available providers in parallel
        let mut tasks = Vec::new();

        // Claude CLI
        if let Some(cli) = &self.claude_cli {
            let cli = cli.clone();
            let req = request.clone();
            tasks.push(tokio::spawn(async move {
                cli.complete(req).await.map(|resp| ProviderResponse {
                    provider: Provider::Anthropic,
                    response: resp,
                })
            }));
        }

        // Codex CLI
        if let Some(cli) = &self.codex_cli {
            let cli = cli.clone();
            let req = request.clone();
            tasks.push(tokio::spawn(async move {
                cli.complete(req).await.map(|resp| ProviderResponse {
                    provider: Provider::OpenAI,
                    response: resp,
                })
            }));
        }

        // Anthropic API (if no CLI available)
        if self.claude_cli.is_none() && self.anthropic_api.is_some() {
            let api = self.anthropic_api.as_ref().unwrap().clone();
            let req = request.clone();
            tasks.push(tokio::spawn(async move {
                api.complete(req).await.map(|resp| ProviderResponse {
                    provider: Provider::Anthropic,
                    response: resp,
                })
            }));
        }

        if tasks.is_empty() {
            anyhow::bail!("No providers available for ensemble. Install 'claude' or 'codex' CLI.");
        }

        // Wait for all tasks to complete
        for task in tasks {
            if let Ok(Ok(provider_resp)) = task.await {
                responses.push(provider_resp);
            }
        }

        if responses.is_empty() {
            anyhow::bail!("All providers failed in ensemble mode.");
        }

        // Simple combination: just use first response for now
        // TODO: Implement proper ensemble combination (voting, averaging, etc.)
        let combined = responses[0].response.content.clone();

        Ok(EnsembleResult {
            responses,
            combined,
        })
    }

    /// Apply adaptive system prompt based on query content
    pub fn apply_personality(&self, mut request: CompletionRequest) -> CompletionRequest {
        // Extract query from first user message
        let query = request
            .messages
            .iter()
            .find(|m| m.role == "user")
            .map(|m| m.content.as_str())
            .unwrap_or("");

        // Generate adaptive system prompt
        let personality = PersonalityEngine::new();
        let system_prompt = personality.system_prompt_for(query);

        // Apply to request
        request.system = Some(system_prompt);
        request
    }

    /// Complete with automatic personality adaptation
    pub async fn complete_adaptive(
        &self,
        request: CompletionRequest,
    ) -> Result<CompletionResponse> {
        let adapted_request = self.apply_personality(request);
        self.complete(adapted_request).await
    }
}
