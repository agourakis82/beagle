//! Development/test endpoints com memória conversacional.

use axum::{extract::State, http::StatusCode, routing::post, Json, Router};
use beagle_memory::{ConversationTurn, PerformanceMetrics};
use beagle_personality::{Domain, PersonalityEngine};
use serde::{Deserialize, Serialize};
use std::time::Instant;
use tracing::{error, info};
use uuid::Uuid;

use super::{
    adversarial_endpoint, causal_endpoint, debate, deep_research_endpoint, metacognitive_endpoint,
    neurosymbolic_endpoint, parallel_research, quantum_endpoint, reasoning_endpoint, research,
    swarm_endpoint, temporal_endpoint,
};
use crate::state::AppState;
use beagle_llm::{CompletionRequest, Message, ModelType};

#[derive(Debug, Deserialize)]
pub struct DevChatRequest {
    message: String,

    #[serde(default)]
    model: Option<String>,

    /// Força domínio específico (bypass da detecção automática)
    #[serde(default)]
    domain: Option<String>,

    /// Session ID for conversation continuity
    #[serde(default)]
    session_id: Option<Uuid>,

    /// Include past context from session
    #[serde(default)]
    include_context: bool,
}

#[derive(Debug, Serialize)]
pub struct DevChatResponse {
    response: String,
    model: String,
    domain: String,
    session_id: Uuid,
    turn_id: Uuid,
    context_used: bool,
    system_prompt_preview: String,
    performance: PerformanceMetrics,
}

pub async fn dev_chat(
    State(state): State<AppState>,
    Json(req): Json<DevChatRequest>,
) -> Result<Json<DevChatResponse>, (StatusCode, String)> {
    let start = Instant::now();

    info!("🧪 DEV /chat - message: {}", req.message);

    // Get or create session
    let session_id = if let Some(sid) = req.session_id {
        info!("📂 Using existing session: {}", sid);
        sid
    } else {
        let session = state
            .context_bridge()
            .create_session(None)
            .await
            .map_err(|e| (StatusCode::INTERNAL_SERVER_ERROR, e.to_string()))?;
        info!("📂 Created new session: {}", session.id);
        session.id
    };

    // Initialize personality engine
    let engine = PersonalityEngine::new();
    let detected_domain = engine.detect_domain(&req.message);
    let domain = req
        .domain
        .as_ref()
        .and_then(|d| parse_domain_override(d))
        .unwrap_or(detected_domain);
    info!("🎯 Detected domain: {:?}", domain);

    // Retrieve past context if requested
    let mut context_string = String::new();
    let mut context_turns = 0;

    if req.include_context {
        match state
            .context_bridge()
            .get_session_history(session_id, 5)
            .await
        {
            Ok(history) => {
                if !history.is_empty() {
                    context_turns = history.len();
                    context_string = format!(
                        "=== Previous conversation (last {} turns) ===\n",
                        context_turns
                    );

                    for turn in history {
                        context_string.push_str(&format!(
                            "User: {}\nAssistant: {}\n\n",
                            turn.query, turn.response
                        ));
                    }

                    info!("📚 Included {} past turns", context_turns);
                }
            }
            Err(e) => {
                error!("⚠️ Failed to retrieve context: {}", e);
            }
        }
    }

    // Get adaptive system prompt
    let mut system_prompt = engine.system_prompt_for_domain(domain);

    // Append context if available
    if !context_string.is_empty() {
        system_prompt.push_str("\n\n");
        system_prompt.push_str(&context_string);
    }

    let system_prompt_preview = system_prompt
        .chars()
        .take(200)
        .collect::<String>()
        .replace('\n', " ");

    info!(
        "📝 System prompt: {} chars (context: {} turns)",
        system_prompt.len(),
        context_turns
    );

    // Determine model
    let model = match req.model.as_deref() {
        Some("sonnet") | Some("sonnet-4.5") => ModelType::ClaudeSonnet45,
        _ => ModelType::ClaudeHaiku45,
    };

    // Get client
    let client = state.anthropic_client().ok_or((
        StatusCode::SERVICE_UNAVAILABLE,
        "Anthropic client not configured".to_string(),
    ))?;

    // Create request
    let request = CompletionRequest {
        model: model.clone(),
        messages: vec![Message {
            role: "user".to_string(),
            content: req.message.clone(),
        }],
        max_tokens: 1000,
        temperature: 1.0,
        system: Some(system_prompt),
    };

    // Send to LLM
    let response = client
        .complete(request)
        .await
        .map_err(|e| (StatusCode::INTERNAL_SERVER_ERROR, e.to_string()))?;

    let latency = start.elapsed();

    info!(
        "✅ Response: {} chars in {:?}",
        response.content.len(),
        latency
    );

    // Store in memory
    let mut turn = ConversationTurn::new(
        session_id,
        req.message,
        response.content.clone(),
        domain,
        response.model.clone(),
    );

    turn.metadata.metrics = PerformanceMetrics {
        latency_ms: latency.as_millis() as u64,
        tokens_input: None, // TODO: extract from response.usage
        tokens_output: None,
        cost_usd: None,
    };
    turn.metadata.system_prompt_preview = Some(system_prompt_preview.clone());

    let turn_id = turn.id;

    match state.context_bridge().store_turn(turn).await {
        Ok(_) => info!("💾 Stored turn in memory"),
        Err(e) => error!("⚠️ Failed to store turn: {}", e),
    }

    Ok(Json(DevChatResponse {
        response: response.content,
        model: response.model,
        domain: format!("{:?}", domain),
        session_id,
        turn_id,
        context_used: context_turns > 0,
        system_prompt_preview,
        performance: PerformanceMetrics {
            latency_ms: latency.as_millis() as u64,
            tokens_input: None,
            tokens_output: None,
            cost_usd: None,
        },
    }))
}

pub fn dev_routes() -> Router<AppState> {
    Router::new()
        // v1.0 features
        .route("/dev/chat", post(dev_chat))
        .route("/dev/research", post(research::research))
        .route(
            "/dev/research/parallel",
            post(parallel_research::parallel_research),
        )
        .route("/dev/debate", post(debate::debate))
        .route("/dev/reasoning", post(reasoning_endpoint::reasoning))
        .route(
            "/dev/causal/extract",
            post(causal_endpoint::extract_causal_graph),
        )
        .route(
            "/dev/causal/intervention",
            post(causal_endpoint::intervention),
        )
        // v2.0 revolutionary features
        .route(
            "/dev/deep-research",
            post(deep_research_endpoint::deep_research),
        )
        .route("/dev/swarm", post(swarm_endpoint::swarm_explore))
        .route("/dev/temporal", post(temporal_endpoint::temporal_analyze))
        .route(
            "/dev/neurosymbolic",
            post(neurosymbolic_endpoint::neurosymbolic_reason),
        )
        .route(
            "/dev/quantum-reasoning",
            post(quantum_endpoint::quantum_reasoning),
        )
        .route(
            "/dev/adversarial-compete",
            post(adversarial_endpoint::adversarial_compete),
        )
        // Metacognitive self-improvement
        .route(
            "/dev/metacognitive/analyze-performance",
            post(metacognitive_endpoint::analyze_performance),
        )
        .route(
            "/dev/metacognitive/analyze-failures",
            post(metacognitive_endpoint::analyze_failures),
        )
}

fn parse_domain_override(raw: &str) -> Option<Domain> {
    match raw.to_ascii_lowercase().as_str() {
        "pbpk" => Some(Domain::PBPK),
        "philosophy" => Some(Domain::Philosophy),
        "beagleengine" | "beagle_engine" | "engine" => Some(Domain::BeagleEngine),
        "music" => Some(Domain::Music),
        "clinicalmedicine" | "clinical_medicine" | "medicine" => Some(Domain::ClinicalMedicine),
        "psychiatry" => Some(Domain::Psychiatry),
        "medicallaw" | "medical_law" => Some(Domain::MedicalLaw),
        "chemicalengineering" | "chemical_engineering" | "chemeng" => {
            Some(Domain::ChemicalEngineering)
        }
        "neuroscience" => Some(Domain::Neuroscience),
        "general" => Some(Domain::General),
        _ => None,
    }
}
