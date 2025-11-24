//! Endpoint de chat adaptativo com detecção de domínio e orquestração multi-provider.
//!
//! Este endpoint integra:
//! - LLMOrchestrator para roteamento inteligente entre providers
//! - PersonalityEngine para detecção automática de domínio científico
//! - System prompts adaptativos baseados em 19 perfis especializados

use axum::{extract::State, routing::post, Json, Router};
use beagle_llm::{CompletionRequest, LLMOrchestrator, Message, ModelType, ProviderStrategy};
use serde::{Deserialize, Serialize};
use utoipa::ToSchema;

use crate::{
    error::{ApiError, ApiResult},
    state::AppState,
};

/// Payload da requisição de chat adaptativo.
#[derive(Debug, Deserialize, ToSchema)]
pub struct AdaptiveChatRequest {
    #[schema(
        example = "Como calcular o clearance renal em modelos PBPK considerando a filtração glomerular?"
    )]
    pub message: String,

    #[serde(default)]
    #[schema(example = 2048)]
    pub max_tokens: Option<u32>,

    #[serde(default)]
    #[schema(example = 0.7)]
    pub temperature: Option<f32>,

    #[serde(default)]
    #[schema(value_type = String, example = "smart_routing")]
    pub strategy: Option<String>,
}

/// Resposta do endpoint de chat adaptativo.
#[derive(Debug, Serialize, ToSchema)]
pub struct AdaptiveChatResponse {
    #[schema(example = "Em modelos PBPK, o clearance renal (CLr) é calculado...")]
    pub response: String,

    #[schema(example = "claude-sonnet-4.5")]
    pub model: String,

    #[schema(example = "PBPK")]
    pub detected_domain: String,

    #[schema(example = "Você é um especialista em farmacocinética...")]
    pub system_prompt: String,

    #[schema(example = "anthropic")]
    pub provider: String,

    #[schema(value_type = Object)]
    pub usage: serde_json::Value,
}

/// Roteador HTTP para o recurso de chat adaptativo.
pub fn router() -> Router<AppState> {
    Router::new().route("/api/v1/chat/adaptive", post(adaptive_chat))
}

/// Realiza uma requisição de chat com detecção automática de domínio e adaptação de personalidade.
///
/// Este endpoint:
/// 1. Detecta o domínio científico da query (PBPK, Quantum, Neuroscience, etc.)
/// 2. Aplica system prompt especializado baseado no domínio
/// 3. Roteia para o provider mais adequado usando estratégia configurável
/// 4. Retorna resposta contextualizada com metadados do processo
#[utoipa::path(
    post,
    path = "/api/v1/chat/adaptive",
    tag = "chat",
    request_body = AdaptiveChatRequest,
    responses(
        (status = 200, description = "Resposta gerada com adaptação de domínio", body = AdaptiveChatResponse),
        (status = 400, description = "Requisição inválida"),
        (status = 503, description = "Nenhum provider LLM disponível")
    )
)]
pub async fn adaptive_chat(
    State(state): State<AppState>,
    Json(payload): Json<AdaptiveChatRequest>,
) -> ApiResult<Json<AdaptiveChatResponse>> {
    if payload.message.trim().is_empty() {
        return Err(ApiError::BadRequest(
            "O campo 'message' não pode ser vazio".into(),
        ));
    }

    let max_tokens = payload.max_tokens.unwrap_or(2048).max(100).min(8192);
    let temperature = payload
        .temperature
        .unwrap_or(0.7_f32)
        .clamp(0.0_f32, 2.0_f32);

    // Parse strategy
    let strategy = match payload.strategy.as_deref() {
        Some("smart_routing") | None => ProviderStrategy::SmartRouting,
        Some("ensemble") => ProviderStrategy::Ensemble,
        Some(provider_name) => {
            // Try to parse as specific provider
            match provider_name {
                "anthropic" => ProviderStrategy::Specific(beagle_llm::Provider::Anthropic),
                "openai" => ProviderStrategy::Specific(beagle_llm::Provider::OpenAI),
                "grok" => ProviderStrategy::Specific(beagle_llm::Provider::Grok),
                "gemini" => ProviderStrategy::Specific(beagle_llm::Provider::Gemini),
                _ => ProviderStrategy::SmartRouting,
            }
        }
    };

    // Use orchestrator from state
    let orchestrator = state.orchestrator();

    // Create orchestrator with specified strategy if different from default
    let orchestrator = if !matches!(strategy, ProviderStrategy::SmartRouting) {
        LLMOrchestrator::with_strategy(strategy)
    } else {
        (*orchestrator).clone()
    };

    // Check if any providers are available
    if orchestrator.available_providers().is_empty() {
        return Err(ApiError::Internal(
            "Nenhum provider LLM configurado. Defina ANTHROPIC_API_KEY ou outros providers.".into(),
        ));
    }

    // Create base request
    let request = CompletionRequest {
        model: ModelType::ClaudeSonnet45, // Default model, may be overridden by orchestrator
        messages: vec![Message::user(payload.message.clone())],
        max_tokens,
        temperature,
        system: None, // Will be set by personality engine
    };

    // Apply personality detection and adaptation
    let adapted_request = orchestrator.apply_personality(request);

    // Detect domain for response metadata
    let detected_domain = beagle_personality::detect_domain(&payload.message);
    let system_prompt = adapted_request
        .system
        .clone()
        .unwrap_or_else(|| "Você é um assistente inteligente e versátil.".to_string());

    // Complete request through orchestrator
    let completion = orchestrator
        .complete_adaptive(adapted_request)
        .await
        .map_err(|e| ApiError::Internal(format!("Falha na completion adaptativa: {}", e)))?;

    Ok(Json(AdaptiveChatResponse {
        response: completion.content,
        model: completion.model,
        detected_domain: format!("{:?}", detected_domain),
        system_prompt: system_prompt[..system_prompt.len().min(200)].to_string(), // Truncate for response
        provider: "orchestrated".to_string(), // TODO: track actual provider used
        usage: completion.usage,
    }))
}
