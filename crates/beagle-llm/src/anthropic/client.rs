use anyhow::{anyhow, Context, Result};
use bytes::Bytes;
use eventsource_stream::Eventsource;
use futures::stream::{self, BoxStream, StreamExt};
use reqwest::Client;
use serde_json::{json, Value};
use tracing::{debug, info, warn};

use super::claude_code_session::ClaudeCodeSessionReader;
use crate::models::{CompletionRequest, CompletionResponse, ModelType};
use crate::StreamChunk;

const API_URL: &str = "https://api.anthropic.com/v1/messages";
const STREAM_URL: &str = "https://api.anthropic.com/v1/messages";
const ANTHROPIC_VERSION: &str = "2023-06-01";

/// Tipo de autenticação usada pelo cliente.
#[derive(Debug, Clone)]
enum AuthType {
    /// API Key tradicional (sk-ant-api03-...)
    ApiKey(String),
    /// OAuth token do Claude Code (sk-ant-oat01-...)
    OAuth(String),
}

/// Cliente HTTP direto para a API pública da Anthropic.
pub struct AnthropicClient {
    http: Client,
    auth: AuthType,
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

        Ok(Self {
            http,
            auth: AuthType::ApiKey(api_key),
        })
    }

    /// Cria um cliente usando a sessão OAuth do Claude Code.
    ///
    /// Tenta ler as credenciais de `~/.claude/.credentials.json`.
    /// Requer que o Claude Code extension esteja instalado e autenticado.
    pub fn from_claude_code_session() -> Result<Self> {
        let reader = ClaudeCodeSessionReader::new();
        let session = reader
            .read_session()
            .context("Falha ao ler sessão do Claude Code")?;

        if session.claude_ai_oauth.is_expired() {
            warn!("OAuth token do Claude Code está expirado, mas tentando usar mesmo assim");
            // Nota: A API pode aceitar o token expirado se o servidor fizer refresh automático
            // ou podemos implementar refresh usando o refresh_token futuramente
        }

        let http = Client::builder()
            .build()
            .context("Falha ao construir cliente HTTP Anthropic")?;

        info!(
            subscription = %session.claude_ai_oauth.subscription_type,
            rate_limit = %session.claude_ai_oauth.rate_limit_tier,
            "Cliente Anthropic criado usando sessão do Claude Code"
        );

        Ok(Self {
            http,
            auth: AuthType::OAuth(session.claude_ai_oauth.access_token),
        })
    }

    /// Tenta criar um cliente do Claude Code, fallback para API key se falhar.
    ///
    /// NOTA: A API pública da Anthropic atualmente NÃO aceita OAuth tokens do Claude Code.
    /// Este método sempre usa API key. A infraestrutura OAuth é mantida para compatibilidade futura.
    #[allow(dead_code)]
    pub fn new_with_claude_code_fallback(api_key: impl Into<String>) -> Result<Self> {
        // Check if Claude Code session exists (for logging purposes)
        match Self::from_claude_code_session() {
            Ok(_client) => {
                info!("Claude Code OAuth session found (MAX subscription)");
                info!("Note: Anthropic API doesn't support OAuth tokens yet, using API key");
            }
            Err(e) => {
                debug!("Claude Code session not found: {}", e);
            }
        }

        // Always use API key for now
        Self::new(api_key)
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

        // Configura autenticação baseada no tipo
        let mut request_builder = self.http.post(API_URL);

        match &self.auth {
            AuthType::ApiKey(key) => {
                request_builder = request_builder.header("x-api-key", key);
            }
            AuthType::OAuth(token) => {
                request_builder =
                    request_builder.header("authorization", format!("Bearer {}", token));
            }
        }

        let response = request_builder
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

    /// Stream completion from Anthropic API using Server-Sent Events (SSE)
    pub async fn stream_complete(
        &self,
        request: CompletionRequest,
    ) -> Result<BoxStream<'static, Result<StreamChunk>>> {
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
            "stream": true,
        });

        if let Some(system_prompt) = system {
            body["system"] = json!(system_prompt);
        }

        debug!(
            model = %model,
            max_tokens = max_tokens,
            "Iniciando streaming da Anthropic"
        );

        // Configura autenticação baseada no tipo
        let mut request_builder = self.http.post(STREAM_URL);

        match &self.auth {
            AuthType::ApiKey(key) => {
                request_builder = request_builder.header("x-api-key", key);
            }
            AuthType::OAuth(token) => {
                request_builder =
                    request_builder.header("authorization", format!("Bearer {}", token));
            }
        }

        let response = request_builder
            .header("anthropic-version", ANTHROPIC_VERSION)
            .header("accept", "text/event-stream")
            .json(&body)
            .send()
            .await
            .context("Falha ao iniciar streaming da Anthropic")?;

        let status = response.status();
        if !status.is_success() {
            let error_text = response.text().await.unwrap_or_default();
            anyhow::bail!("Anthropic streaming error ({}): {}", status, error_text);
        }

        let model_name = model.to_string();
        let stream = response
            .bytes_stream()
            .eventsource()
            .enumerate()
            .filter_map(move |(index, event)| {
                let model_name = model_name.clone();
                async move {
                    match event {
                        Ok(event) => {
                            if event.data == "[DONE]" {
                                return Some(Ok(StreamChunk {
                                    content: String::new(),
                                    index,
                                    done: true,
                                    metadata: Some(json!({"model": model_name})),
                                }));
                            }

                            // Parse SSE data as JSON
                            match serde_json::from_str::<Value>(&event.data) {
                                Ok(data) => {
                                    // Extract content from content_block_delta events
                                    if let Some(delta) = data.get("delta") {
                                        if let Some(text) = delta.get("text").and_then(Value::as_str) {
                                            return Some(Ok(StreamChunk {
                                                content: text.to_string(),
                                                index,
                                                done: false,
                                                metadata: None,
                                            }));
                                        }
                                    }
                                    // Handle content_block_start
                                    if let Some(content_block) = data.get("content_block") {
                                        if let Some(text) = content_block.get("text").and_then(Value::as_str) {
                                            return Some(Ok(StreamChunk {
                                                content: text.to_string(),
                                                index,
                                                done: false,
                                                metadata: None,
                                            }));
                                        }
                                    }
                                    None
                                }
                                Err(e) => {
                                    warn!("Failed to parse SSE event: {}", e);
                                    None
                                }
                            }
                        }
                        Err(e) => Some(Err(anyhow!("SSE error: {}", e))),
                    }
                }
            })
            .boxed();

        Ok(stream)
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
