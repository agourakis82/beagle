//! Endpoint de conversação com Vertex AI (Claude 3.5).

use axum::{extract::State, routing::post, Json, Router};
use beagle_llm::{CompletionRequest, Message, ModelType};
use serde::{Deserialize, Serialize};
use utoipa::ToSchema;

use crate::{
    api::models::ModelChoice,
    error::{ApiError, ApiResult},
    state::AppState,
};

/// Payload da requisição de chat.
#[derive(Debug, Deserialize, ToSchema)]
pub struct ChatRequest {
    #[schema(example = "Explique o paradoxo de Fermi em linguagem técnica.")]
    pub message: String,
    #[serde(default)]
    #[schema(value_type = String, example = "auto")]
    pub model: ModelChoice,
    #[serde(default)]
    #[schema(example = 1024)]
    pub max_tokens: Option<u32>,
    #[serde(default)]
    #[schema(example = 0.7)]
    pub temperature: Option<f32>,
}

/// Resposta do endpoint de chat.
#[derive(Debug, Serialize, ToSchema)]
pub struct ChatResponse {
    #[schema(example = "O paradoxo de Fermi emerge da disparidade...")]
    pub response: String,
    #[schema(example = "claude-haiku-4.5")]
    pub model: String,
    #[schema(value_type = Object)]
    pub usage: serde_json::Value,
    #[schema(example = "vertex-anthropic")]
    pub provider: String,
}

/// Roteador HTTP para o recurso de chat.
pub fn router() -> Router<AppState> {
    Router::new().route("/api/v1/chat", post(chat_completion))
}

/// Realiza uma requisição single-turn ao Vertex AI.
#[utoipa::path(
    post,
    path = "/api/v1/chat",
    tag = "chat",
    request_body = ChatRequest,
    responses(
        (status = 200, description = "Resposta gerada com sucesso", body = ChatResponse),
        (status = 400, description = "Requisição inválida"),
        (status = 503, description = "Integração com Vertex AI indisponível")
    )
)]
pub async fn chat_completion(
    State(state): State<AppState>,
    Json(payload): Json<ChatRequest>,
) -> ApiResult<Json<ChatResponse>> {
    if payload.message.trim().is_empty() {
        return Err(ApiError::BadRequest(
            "O campo 'message' não pode ser vazio".into(),
        ));
    }

    let model_choice = match payload.model {
        ModelChoice::Auto => ModelChoice::auto_select(&payload.message),
        other => other,
    };

    let max_tokens = payload.max_tokens.unwrap_or(1024).max(1).min(4096);
    let temperature = payload
        .temperature
        .unwrap_or(0.7_f32)
        .clamp(0.0_f32, 2.0_f32);

    let mut completion_request = CompletionRequest {
        model: match model_choice {
            ModelChoice::ClaudeSonnet45 => ModelType::ClaudeSonnet45,
            _ => ModelType::ClaudeHaiku45,
        },
        messages: vec![Message::user(payload.message.clone())],
        max_tokens,
        temperature,
        system: None,
    };

    match model_choice {
        ModelChoice::Gemini15Pro => {
            let client = state
                .gemini_client()
                .ok_or_else(|| ApiError::Internal("Gemini client não configurado".into()))?;

            // Gemini ignora o campo `model`; o construtor já definiu ID correto.
            completion_request.model = ModelType::ClaudeHaiku45;

            let completion = client.complete(completion_request).await?;
            Ok(Json(ChatResponse {
                response: completion.content,
                model: completion.model,
                usage: completion.usage,
                provider: "vertex-gemini".to_string(),
            }))
        }
        ModelChoice::ClaudeHaiku45 | ModelChoice::ClaudeSonnet45 => {
            let client = state
                .vertex_client()
                .ok_or_else(|| ApiError::Internal("Integração Vertex AI não configurada".into()))?;

            let completion = client.complete(completion_request).await?;
            Ok(Json(ChatResponse {
                response: completion.content,
                model: completion.model,
                usage: completion.usage,
                provider: "vertex-anthropic".to_string(),
            }))
        }
        ModelChoice::Auto => unreachable!("ramo 'auto' já resolvido"),
    }
}
