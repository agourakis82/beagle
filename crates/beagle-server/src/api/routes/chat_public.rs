//! Endpoint público (sem autenticação) para experimentos com LLMs.

use axum::{extract::State, routing::post, Json, Router};
use serde::{Deserialize, Serialize};
use tracing::{debug, info};

use crate::{api::models::ModelChoice, error::ApiError, state::AppState};
use beagle_llm::{CompletionRequest, Message, ModelType};

#[derive(Debug, Deserialize)]
pub struct ChatRequest {
    message: String,
    #[serde(default)]
    model: ModelChoice,
    #[serde(default = "default_max_tokens")]
    max_tokens: u32,
}

const fn default_max_tokens() -> u32 {
    1024
}

#[derive(Debug, Serialize)]
pub struct ChatResponse {
    response: String,
    model: String,
    provider: String,
    usage: serde_json::Value,
}

pub async fn chat_public(
    State(state): State<AppState>,
    Json(payload): Json<ChatRequest>,
) -> Result<Json<ChatResponse>, ApiError> {
    debug!("📨 Public chat request: {:?}", payload);

    let model_choice = match payload.model {
        ModelChoice::Auto => ModelChoice::auto_select(&payload.message),
        other => other,
    };

    info!("🎯 Model selected: {:?}", model_choice);

    match model_choice {
        ModelChoice::Gemini15Pro => {
            let client = state
                .gemini_client()
                .ok_or_else(|| ApiError::Internal("Gemini client não configurado".into()))?;

            let request = CompletionRequest {
                model: ModelType::ClaudeHaiku45, // ignorado pelo backend Gemini
                messages: vec![Message::user(payload.message)],
                max_tokens: payload.max_tokens,
                temperature: 1.0,
                system: None,
            };

            let completion = client
                .complete(request)
                .await
                .map_err(|e| ApiError::Internal(format!("Gemini error: {e}")))?;

            Ok(Json(ChatResponse {
                response: completion.content,
                model: completion.model,
                usage: completion.usage,
                provider: "vertex-gemini".into(),
            }))
        }
        ModelChoice::ClaudeHaiku45 | ModelChoice::ClaudeSonnet45 => {
            let client = state
                .vertex_client()
                .ok_or_else(|| ApiError::Internal("Vertex AI client não configurado".into()))?;

            let model = match model_choice {
                ModelChoice::ClaudeSonnet45 => ModelType::ClaudeSonnet45,
                _ => ModelType::ClaudeHaiku45,
            };

            let request = CompletionRequest {
                model,
                messages: vec![Message::user(payload.message)],
                max_tokens: payload.max_tokens,
                temperature: 1.0,
                system: None,
            };

            let completion = client
                .complete(request)
                .await
                .map_err(|e| ApiError::Internal(format!("Vertex error: {e}")))?;

            Ok(Json(ChatResponse {
                response: completion.content,
                model: completion.model,
                usage: completion.usage,
                provider: "vertex-anthropic".into(),
            }))
        }
        ModelChoice::Auto => unreachable!("ramo resolvido na correspondência anterior"),
    }
}

pub fn router() -> Router<AppState> {
    Router::new().route("/api/v1/chat/public", post(chat_public))
}
