use anyhow::{anyhow, Context, Result};
use reqwest::Client;
use serde_json::{json, Value};
use tracing::{debug, warn};

use crate::models::{CompletionRequest, CompletionResponse, ModelType};

const API_URL: &str = "https://api.anthropic.com/v1/messages";
const ANTHROPIC_VERSION: &str = "2023-06-01";

/// Cliente HTTP direto para a API pública da Anthropic.
pub struct AnthropicClient {
    http: Client,
    api_key: String,
}

impl AnthropicClient {
    /// Cria um novo cliente com a API key fornecida.
    pub fn new(api_key: impl Into<String>) -> Result<Self> {
        let api_key = api_key.into();
        if api_key.trim().is_empty() {
            anyhow::bail!("API key da Anthropic está vazia");
        }

        let http = Client::builder()
            .build()
            .context("Falha ao construir cliente HTTP Anthropic")?;

        Ok(Self { http, api_key })
    }

    /// Executa uma completion síncrona no endpoint `messages`.
    pub async fn complete(&self, request: CompletionRequest) -> Result<CompletionResponse> {
        let CompletionRequest {
            model,
            messages,
            max_tokens,
            temperature,
            system,
        } = request;

        let mut body = json!({
            "model": resolve_model_id(&model),
            "messages": messages
                .iter()
                .map(|message| {
                    json!({
                        "role": &message.role,
                        "content": [{
                            "type": "text",
                            "text": &message.content,
                        }],
                    })
                })
                .collect::<Vec<_>>(),
            "max_tokens": max_tokens,
            "temperature": temperature,
        });

        if let Some(system_prompt) = system {
            body["system"] = json!(system_prompt);
            debug!("🎭 Usando system prompt customizado");
        }

        debug!(
            model = %model,
            max_tokens = max_tokens,
            "Enviando requisição à Anthropic"
        );

        let response = self
            .http
            .post(API_URL)
            .header("x-api-key", &self.api_key)
            .header("anthropic-version", ANTHROPIC_VERSION)
            .json(&body)
            .send()
            .await
            .context("Falha ao enviar requisição para a Anthropic")?;

        let status = response.status();
        let payload = response
            .json::<Value>()
            .await
            .context("Falha ao decodificar resposta JSON da Anthropic")?;

        if !status.is_success() {
            warn!(%status, body = %payload, "Anthropic retornou erro HTTP");
            anyhow::bail!("Anthropic respondeu status {}: {}", status, payload);
        }

        let content =
            extract_content(&payload)?.ok_or_else(|| anyhow!("Resposta sem conteúdo textual"))?;

        let usage = payload.get("usage").cloned().unwrap_or(Value::Null);
        let model_name = payload
            .get("model")
            .and_then(Value::as_str)
            .map(|s| s.to_owned())
            .unwrap_or_else(|| model.to_string());

        Ok(CompletionResponse {
            content,
            model: model_name,
            usage,
        })
    }
}

fn extract_content(payload: &Value) -> Result<Option<String>> {
    if let Some(array) = payload.get("content").and_then(Value::as_array) {
        let mut buffer = String::new();
        for item in array {
            if let Some(text) = item.get("text").and_then(Value::as_str) {
                buffer.push_str(text);
            } else if let Some(inner) = item.get("content").and_then(Value::as_array) {
                for nested in inner {
                    if let Some(text) = nested.get("text").and_then(Value::as_str) {
                        buffer.push_str(text);
                    }
                }
            }
        }
        if !buffer.is_empty() {
            return Ok(Some(buffer));
        }
    }

    if let Some(text) = payload.get("output_text").and_then(Value::as_str) {
        return Ok(Some(text.to_owned()));
    }

    if let Some(text) = payload.get("content").and_then(Value::as_str) {
        return Ok(Some(text.to_owned()));
    }

    Ok(None)
}

fn resolve_model_id(model: &ModelType) -> &'static str {
    match model {
        ModelType::ClaudeHaiku45 => "claude-3-5-haiku-20241022",
        ModelType::ClaudeSonnet45 => "claude-3-5-sonnet-20241022",
        ModelType::ClaudeSonnet4 => "claude-sonnet-4-20250514",
    }
}
