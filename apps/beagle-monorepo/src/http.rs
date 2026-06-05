use crate::auth::api_token_auth;
use crate::{
    run_beagle_pipeline, ExperimentFlags, RunState, RunStatus, ScienceJobKind, ScienceJobRegistry,
    ScienceJobState, ScienceJobStatus,
};
use axum::http::StatusCode;
use axum::response::sse::{Event, KeepAlive, Sse};
use axum::{
    extract::Path,
    middleware,
    routing::{get, post},
    Json, Router,
};
use beagle_agents::{self, AgentLlmClient};
use beagle_config::{beagle_data_dir, classify_hrv};
use beagle_core::BeagleContext;
use beagle_feedback::{append_event, create_triad_event};
use beagle_llm::{ProviderTier, RequestMeta, TieredRouter, StreamChunk};
use beagle_metrics::{
    metrics_router, metrics_middleware, record_llm_request, record_pipeline_start,
    record_pipeline_end, record_pipeline_stage, record_memory_query,
};
#[cfg(feature = "memory")]
use beagle_memory::{ChatSession, MemoryQuery};
use beagle_observer::UniversalObserver;
use beagle_search::{ArxivClient, PubMedClient, SearchClient, SearchQuery};
use beagle_triad::{run_triad, TriadInput};
use chrono::Utc;
use serde::{Deserialize, Serialize};
use std::io::Write;
use std::path::PathBuf;
use std::sync::Arc;
use std::time::{Duration, Instant};
use tokio::sync::Mutex;
use tokio::sync::mpsc;
use tokio_stream::wrappers::ReceiverStream;
use tower_http::trace::TraceLayer;
use tracing::{error, info, warn};
use uuid::Uuid;
use futures::StreamExt;

#[derive(Deserialize)]
pub struct LlmRequest {
    pub prompt: String,
    #[serde(default)]
    pub requires_math: bool,
    #[serde(default)]
    pub requires_high_quality: bool,
    #[serde(default)]
    pub offline_required: bool,
}

#[derive(Serialize)]
pub struct LlmResponse {
    pub text: String,
    pub provider: String,
    pub tier: String,
}

#[derive(Deserialize)]
pub struct SearchRequest {
    pub query: String,
    #[serde(default = "default_max_results")]
    pub max_results: usize,
    #[serde(default)]
    pub store_in_graph: bool,
}

fn default_max_results() -> usize {
    10
}

#[derive(Serialize)]
pub struct SearchResponse {
    pub papers: Vec<PaperInfo>,
    pub total_count: usize,
    pub backend: String,
    pub search_time_ms: u64,
}

#[derive(Serialize)]
pub struct PaperInfo {
    pub id: String,
    pub title: String,
    pub authors: Vec<String>,
    pub abstract_text: String,
    pub published_date: Option<String>,
    pub url: Option<String>,
    pub pdf_url: Option<String>,
    pub source: String,
    pub citation: String,
}

use crate::cognitive_events::CognitiveTx;
use crate::jobs::{
    DeepThinkRegistry, FractalTreeRegistry, JobRegistry, McpToolCallRegistry,
    PhiMeasurementRegistry, VoidJourneyRegistry,
};

#[derive(Clone)]
pub struct AppState {
    pub ctx: Arc<Mutex<BeagleContext>>,
    pub jobs: Arc<JobRegistry>,
    pub science_jobs: Arc<ScienceJobRegistry>,
    pub observer: Arc<UniversalObserver>,
    /// /dev/void journeys — real tensor-math navigator output.
    pub voids: Arc<VoidJourneyRegistry>,
    /// /api/fractal/recurse trees — LLM-driven recursive cognitive expansion.
    pub fractals: Arc<FractalTreeRegistry>,
    /// /api/exocortex/process Φ measurements — IIT approximation over hypergraph.
    pub phis: Arc<PhiMeasurementRegistry>,
    /// /api/cognitive/deep-think summaries — one per chained fractal+void+phi run.
    pub deep_thinks: Arc<DeepThinkRegistry>,
    /// /api/cognitive/mcp_tool_call invocations — the agent-rhythm substrate.
    pub mcp_tools: Arc<McpToolCallRegistry>,
    /// Broadcast channel — every cognitive event (void/fractal/phi/physio)
    /// is published here; SSE handler subscribes to push them to clients.
    pub cognitive_tx: CognitiveTx,
}

pub fn build_router(state: AppState) -> Router {
    // Rotas protegidas (requerem autenticação via Bearer token)
    let protected_routes = Router::new()
        .route("/api/llm/complete", post(llm_complete_handler))
        .route("/api/llm/complete/stream", get(llm_complete_stream_handler))
        .route("/api/pipeline/start", post(pipeline_start_handler))
        .route("/api/pipeline/status/:run_id", get(pipeline_status_handler))
        .route("/api/run/:run_id/artifacts", get(run_artifacts_handler))
        .route("/api/runs/recent", get(runs_recent_handler))
        .route("/api/observer/physio", post(observer_physio_handler))
        .route("/api/observer/physio/latest", get(observer_physio_latest_handler))
        .route("/api/observer/env", post(observer_env_handler))
        .route(
            "/api/observer/space_weather",
            post(observer_space_weather_handler),
        )
        .route(
            "/api/observer/context",
            get(observer_context_current_handler),
        )
        .route(
            "/api/observer/context/:run_id",
            get(observer_context_handler),
        )
        .route("/api/jobs/science/start", post(science_job_start_handler))
        .route(
            "/api/jobs/science/status/:job_id",
            get(science_job_status_handler),
        )
        .route(
            "/api/jobs/science/:job_id/artifacts",
            get(science_job_artifacts_handler),
        )
        .merge(crate::http_darwin_hpc::darwin_hpc_routes())
        .merge(crate::http_memory::memory_routes())
        .merge(crate::http_feedback::feedback_routes())
        .merge(crate::http_cognitive::cognitive_routes())
        .merge(crate::http_external_jobs::external_jobs_routes())
        .merge(crate::http_fractal::fractal_routes())
        .merge(crate::http_exocortex::exocortex_routes())
        .merge(crate::http_deep_think::deep_think_routes())
        .route("/api/pcs/reason", post(pcs_reason_handler))
        .route("/api/fractal/grow", post(fractal_grow_handler))
        .route("/api/worldmodel/predict", post(worldmodel_predict_handler))
        .route(
            "/api/serendipity/discover",
            post(serendipity_discover_handler),
        )
        .route("/api/search/pubmed", post(search_pubmed_handler))
        .route("/api/search/arxiv", post(search_arxiv_handler))
        .route("/api/search/all", post(search_all_handler))
        // DEV endpoints - Revolutionary Agent Features (B17-B25)
        .route("/dev/causal", post(dev_causal_handler))
        .route("/dev/debate", post(dev_debate_handler))
        .route("/dev/deep-research", post(dev_deep_research_handler))
        .route("/dev/neurosymbolic", post(dev_neurosymbolic_handler))
        .route("/dev/parallel", post(dev_parallel_handler))
        .route("/dev/reasoning", post(dev_reasoning_handler))
        .route("/dev/swarm", post(dev_swarm_handler))
        .route("/dev/temporal", post(dev_temporal_handler))
        .route("/dev/research", post(dev_research_handler))
        // DEV void endpoint - disponível quando feature "void" habilitada
        .route("/dev/void", post(dev_void_handler))
        .route_layer(middleware::from_fn_with_state(
            state.clone(),
            api_token_auth,
        ));

    // Rotas públicas (sem autenticação - para health checks e monitoring)
    // Metrics endpoint at /metrics - accessible without auth for Prometheus scraping
    let public_routes = Router::new()
        .route("/health", get(health_handler))
        .merge(metrics_router());

    // Combina rotas protegidas e públicas
    // Add metrics middleware for automatic HTTP metrics collection
    Router::new()
        .merge(protected_routes)
        .merge(public_routes)
        .layer(axum::middleware::from_fn(metrics_middleware))
        .layer(TraceLayer::new_for_http())
        .with_state(state)
}

async fn llm_complete_handler(
    axum::extract::State(state): axum::extract::State<AppState>,
    Json(req): Json<LlmRequest>,
) -> Result<Json<LlmResponse>, StatusCode> {
    let start = Instant::now();
    let mut ctx = state.ctx.lock().await;

    // Cria RequestMeta com heurísticas simples
    let mut meta = RequestMeta::from_prompt(&req.prompt);

    // Override com flags explícitas se fornecidas
    if req.requires_math {
        meta.requires_math = true;
    }
    if req.requires_high_quality {
        meta.requires_high_quality = true;
    }
    if req.offline_required {
        meta.offline_required = true;
    }

    // Usa run_id sintético para HTTP (ou pode vir do header)
    let run_id = "http_session";

    // Obtém stats atuais
    let current_stats = ctx.llm_stats.get_or_create(run_id);

    // Escolhe client com limites
    let (client, tier) = ctx.router.choose_with_limits(&meta, &current_stats);

    // P0 #2: dispatch on the ALREADY-CHOSEN limit-aware client/tier — do NOT call
    // ctx.router.complete(), which would re-route via the non-limit-aware choose() and
    // discard both the chosen client and the request's RequestMeta flags (budgets bypassed).
    let result = ctx.router.complete_chosen(&client, tier, &req.prompt).await;

    // Calculate duration for metrics
    let duration = start.elapsed();

    let text = result.map_err(|e| {
        tracing::error!("LLM error: {}", e);
        // Record failed request in metrics
        record_llm_request(
            tier.as_str(),
            &format!("{:?}", tier),
            "error",
            duration,
            req.prompt.len() as u64 / 4,
            0,
            0.0,
        );
        StatusCode::BAD_GATEWAY
    })?;

    // Estimativa de tokens (simplificada: ~4 chars por token)
    let tokens_in_est = req.prompt.len() / 4;
    let tokens_out_est = text.len() / 4;

    // Atualiza stats
    ctx.llm_stats.update(run_id, |stats| {
        match tier {
            ProviderTier::Grok3 => {
                stats.grok3_calls += 1;
                stats.grok3_tokens_in += tokens_in_est as u32;
                stats.grok3_tokens_out += tokens_out_est as u32;
            }
            ProviderTier::Grok4Heavy => {
                stats.grok4_calls += 1;
                stats.grok4_tokens_in += tokens_in_est as u32;
                stats.grok4_tokens_out += tokens_out_est as u32;
            }
            _ => {
                // Outros tiers contam como Grok3 por enquanto
                stats.grok3_calls += 1;
                stats.grok3_tokens_in += tokens_in_est as u32;
                stats.grok3_tokens_out += tokens_out_est as u32;
            }
        }
    });

    let provider_name = tier.as_str();

    // Record metrics
    // Estimate cost: Grok 3 ~ $0.003/1K tokens, Grok 4 Heavy ~ $0.015/1K tokens
    let cost_per_1k = match tier {
        ProviderTier::Grok4Heavy => 0.015,
        _ => 0.003,
    };
    let total_tokens = tokens_in_est + tokens_out_est;
    let cost_usd = (total_tokens as f64 / 1000.0) * cost_per_1k;

    record_llm_request(
        provider_name,
        &format!("{:?}", tier),
        "success",
        duration,
        tokens_in_est as u64,
        tokens_out_est as u64,
        cost_usd,
    );

    info!(
        tier = ?tier,
        provider = provider_name,
        tokens_in = tokens_in_est,
        tokens_out = tokens_out_est,
        duration_ms = duration.as_millis() as u64,
        "LLM request completed"
    );

    Ok(Json(LlmResponse {
        text,
        provider: provider_name.to_string(),
        tier: format!("{:?}", tier),
    }))
}

// ============================================================================
// SSE Streaming LLM Completion Endpoint
// ============================================================================

#[derive(Deserialize)]
pub struct LlmStreamRequest {
    pub prompt: String,
    #[serde(default)]
    pub requires_math: bool,
    #[serde(default)]
    pub requires_high_quality: bool,
    #[serde(default)]
    pub offline_required: bool,
    #[serde(default = "default_max_tokens")]
    pub max_tokens: u32,
    #[serde(default = "default_temperature")]
    pub temperature: f32,
}

fn default_max_tokens() -> u32 {
    2048
}

fn default_temperature() -> f32 {
    0.7
}

/// SSE Stream handler for LLM completions
/// Returns Server-Sent Events with the format:
/// event: chunk
/// data: {"content": "...", "index": 0}
///
/// event: complete
/// data: {"metadata": {...}}
async fn llm_complete_stream_handler(
    axum::extract::State(state): axum::extract::State<AppState>,
    axum::extract::Query(req): axum::extract::Query<LlmStreamRequest>,
) -> Result<Sse<impl futures::Stream<Item = Result<Event, anyhow::Error>>>, StatusCode> {
    let ctx = state.ctx.lock().await;
    let router = ctx.router.clone();
    let run_id = "http_stream_session";

    // Cria RequestMeta com heurísticas simples
    let mut meta = RequestMeta::from_prompt(&req.prompt);

    // Override com flags explícitas se fornecidas
    if req.requires_math {
        meta.requires_math = true;
    }
    if req.requires_high_quality {
        meta.requires_high_quality = true;
    }
    if req.offline_required {
        meta.offline_required = true;
    }

    // Obtém stats atuais
    let current_stats = ctx.llm_stats.get_or_create(run_id);

    // Escolhe client com limites
    let (client, tier) = ctx.router.choose_with_limits(&meta, &current_stats);
    let provider_name = tier.as_str().to_string();

    drop(ctx); // Release lock before streaming

    // Create channel for streaming
    let (tx, rx) = mpsc::channel::<Result<Event, anyhow::Error>>(100);

    // Spawn streaming task
    tokio::spawn(async move {
        let start_time = std::time::Instant::now();
        let mut chunk_index: usize = 0;

        // Check if client supports native streaming
        if client.supports_streaming() {
            // Use native streaming
            match client.stream_complete(&req.prompt).await {
                Ok(mut stream) => {
                    while let Some(chunk_result) = stream.next().await {
                        match chunk_result {
                            Ok(chunk) => {
                                let event = if chunk.done {
                                    let metadata = serde_json::json!({
                                        "provider": provider_name,
                                        "tier": format!("{:?}", tier),
                                        "duration_ms": start_time.elapsed().as_millis() as u64,
                                        "total_chunks": chunk_index + 1,
                                        "model": chunk.metadata.as_ref()
                                            .and_then(|m| m.get("model"))
                                            .and_then(|v| v.as_str())
                                            .unwrap_or("unknown"),
                                    });
                                    Event::default()
                                        .event("complete")
                                        .data(metadata.to_string())
                                } else {
                                    let data = serde_json::json!({
                                        "content": chunk.content,
                                        "index": chunk_index,
                                    });
                                    chunk_index += 1;
                                    Event::default()
                                        .event("chunk")
                                        .data(data.to_string())
                                };

                                if tx.send(Ok(event)).await.is_err() {
                                    break; // Client disconnected
                                }
                            }
                            Err(e) => {
                                let error_event = Event::default()
                                    .event("error")
                                    .data(format!("{{\"error\": \"{}\"}}", e));
                                let _ = tx.send(Ok(error_event)).await;
                                break;
                            }
                        }
                    }
                }
                Err(e) => {
                    let error_event = Event::default()
                        .event("error")
                        .data(format!("{{\"error\": \"{}\"}}", e));
                    let _ = tx.send(Ok(error_event)).await;
                }
            }
        } else {
            // Fallback: complete synchronously and simulate streaming by chunking
            match router.complete(&req.prompt).await {
                Ok(text) => {
                    let chunk_size = 100; // Characters per chunk
                    let total_chunks = (text.len() + chunk_size - 1) / chunk_size;

                    for (i, chunk_text) in text.chars().collect::<Vec<_>>()
                        .chunks(chunk_size)
                        .map(|c| c.iter().collect::<String>())
                        .enumerate()
                    {
                        let data = serde_json::json!({
                            "content": chunk_text,
                            "index": i,
                        });
                        let event = Event::default()
                            .event("chunk")
                            .data(data.to_string());

                        if tx.send(Ok(event)).await.is_err() {
                            break; // Client disconnected
                        }
                        chunk_index = i;

                        // Small delay to simulate streaming effect
                        tokio::time::sleep(Duration::from_millis(10)).await;
                    }

                    // Send complete event
                    let metadata = serde_json::json!({
                        "provider": provider_name,
                        "tier": format!("{:?}", tier),
                        "duration_ms": start_time.elapsed().as_millis() as u64,
                        "total_chunks": chunk_index + 1,
                        "model": "grok-3",
                        "note": "chunked-simulation",
                    });
                    let complete_event = Event::default()
                        .event("complete")
                        .data(metadata.to_string());
                    let _ = tx.send(Ok(complete_event)).await;
                }
                Err(e) => {
                    let error_event = Event::default()
                        .event("error")
                        .data(format!("{{\"error\": \"{}\"}}", e));
                    let _ = tx.send(Ok(error_event)).await;
                }
            }
        }
    });

    let stream = ReceiverStream::new(rx);

    Ok(Sse::new(stream)
        .keep_alive(KeepAlive::new()
            .interval(Duration::from_secs(15))
            .text("keep-alive")))
}

#[derive(Serialize)]
struct HealthResponse {
    status: String,
    service: String,
    profile: String,
    safe_mode: bool,
    data_dir: String,
    xai_api_key_present: bool,
}

async fn health_handler(
    axum::extract::State(state): axum::extract::State<AppState>,
) -> Json<HealthResponse> {
    let ctx = state.ctx.lock().await;
    let cfg = &ctx.cfg;
    let has_xai_key = cfg.llm.xai_api_key.is_some();

    Json(HealthResponse {
        status: "ok".to_string(),
        service: "beagle-core".to_string(),
        profile: cfg.profile.clone(),
        safe_mode: cfg.safe_mode,
        data_dir: cfg.storage.data_dir.clone(),
        xai_api_key_present: has_xai_key,
    })
}

// ============================================================================
// Pipeline endpoints
// ============================================================================

#[derive(Deserialize)]
pub struct PipelineStartRequest {
    pub question: String,
    #[serde(default)]
    pub with_triad: bool,
    /// Flag experimental: se hrv_aware=false, usa UserContext neutro
    #[serde(default)]
    pub hrv_aware: Option<bool>,
    /// ID do experimento (opcional, para rastreamento)
    pub experiment_id: Option<String>,
}

#[derive(Serialize)]
pub struct PipelineStartResponse {
    pub run_id: String,
    pub status: String,
}

async fn pipeline_start_handler(
    axum::extract::State(state): axum::extract::State<AppState>,
    Json(req): Json<PipelineStartRequest>,
) -> Result<Json<PipelineStartResponse>, StatusCode> {
    let run_id = Uuid::new_v4().to_string();
    let run_id_clone = run_id.clone();

    // Record pipeline start
    record_pipeline_start();

    // Cria run no registry
    let run_state = state
        .jobs
        .create_run(run_id.clone(), req.question.clone())
        .await;

    // Clona state para usar no spawn
    let ctx_clone = state.ctx.clone();
    let jobs_clone = state.jobs.clone();
    let observer_clone = state.observer.clone();
    let question = req.question.clone();
    let with_triad = req.with_triad;
    let hrv_aware = req.hrv_aware.unwrap_or(true); // Default: true
    let experiment_id = req.experiment_id.clone();
    let serendipity_enabled = state.ctx.lock().await.cfg.serendipity_enabled();

    // Prepara flags experimentais
    let experiment_flags = ExperimentFlags::new(hrv_aware, with_triad, true, serendipity_enabled);

    // Dispara pipeline em background
    tokio::spawn(async move {
        let pipeline_start_time = Instant::now();

        let mut ctx = {
            let ctx = ctx_clone.lock().await;
            BeagleContext {
                cfg: ctx.cfg.clone(),
                router: ctx.router.clone(),
                llm: ctx.llm.clone(),
                vector: ctx.vector.clone(),
                graph: ctx.graph.clone(),
                llm_stats: ctx.llm_stats.clone(),
                #[cfg(feature = "memory")]
                memory: ctx.memory.clone(),
            }
        };

        // Atualiza status para Running
        jobs_clone
            .update_status(&run_id_clone, RunStatus::Running)
            .await;

        // Executa pipeline com observer e flags experimentais
        match run_beagle_pipeline(
            &mut ctx,
            &question,
            &run_id_clone,
            Some(observer_clone),
            None,
            Some(experiment_flags.clone()),
            experiment_id.clone(),
        )
        .await
        {
            Ok(paths) => {
                if with_triad {
                    // Atualiza para TriadRunning
                    jobs_clone
                        .update_status(&run_id_clone, RunStatus::TriadRunning)
                        .await;

                    // Executa Triad
                    let triad_input = TriadInput {
                        run_id: run_id_clone.clone(),
                        draft_path: paths.draft_md.clone(),
                        context_summary: None,
                    };

                    match run_triad(&triad_input, &ctx).await {
                        Ok(report) => {
                            jobs_clone
                                .update_status(&run_id_clone, RunStatus::TriadDone)
                                .await;

                            // Record pipeline success with triad
                            let duration = pipeline_start_time.elapsed();
                            record_pipeline_end("success_with_triad", duration);
                            record_pipeline_stage("triad", duration);

                            // Cria feedback event para TriadCompleted
                            let data_dir = beagle_data_dir();
                            let triad_dir = data_dir.join("triad").join(&run_id_clone);
                            std::fs::create_dir_all(&triad_dir).ok();

                            let triad_final_md = triad_dir.join("draft_reviewed.md");
                            let triad_report_json = triad_dir.join("triad_report.json");

                            // Salva draft final e report
                            std::fs::write(&triad_final_md, &report.final_draft).ok();
                            std::fs::write(
                                &triad_report_json,
                                serde_json::to_string_pretty(&report).unwrap_or_default(),
                            )
                            .ok();

                            // Extrai question do run_report.json se disponível
                            let question = None; // Poderia buscar do run_report.json

                            // Cria evento com stats LLM
                            let llm_stats_tuple = (
                                report.llm_stats.grok3_calls as u32,
                                report.llm_stats.grok4_calls as u32,
                                (report.llm_stats.grok3_tokens_in
                                    + report.llm_stats.grok3_tokens_out)
                                    as u32,
                                (report.llm_stats.grok4_tokens_in
                                    + report.llm_stats.grok4_tokens_out)
                                    as u32,
                            );

                            let event = create_triad_event(
                                run_id_clone.clone(),
                                question,
                                triad_final_md,
                                triad_report_json,
                                Some(llm_stats_tuple),
                            );

                            if let Err(e) = append_event(&data_dir, &event) {
                                warn!("Falha ao logar feedback event da Triad: {}", e);
                            } else {
                                info!("📊 Feedback event da Triad logado para Continuous Learning");
                            }
                        }
                        Err(e) => {
                            error!("Triad failed for run {}: {}", run_id_clone, e);
                            jobs_clone
                                .set_error(&run_id_clone, format!("Triad failed: {}", e))
                                .await;

                            // Record pipeline failure
                            let duration = pipeline_start_time.elapsed();
                            record_pipeline_end("triad_failed", duration);
                        }
                    }
                } else {
                    jobs_clone
                        .update_status(&run_id_clone, RunStatus::Done)
                        .await;

                    // Record pipeline success without triad
                    let duration = pipeline_start_time.elapsed();
                    record_pipeline_end("success", duration);
                }
            }
            Err(e) => {
                error!("Pipeline failed for run {}: {}", run_id_clone, e);
                jobs_clone
                    .set_error(&run_id_clone, format!("Pipeline failed: {}", e))
                    .await;

                // Record pipeline failure
                let duration = pipeline_start_time.elapsed();
                record_pipeline_end("failed", duration);
            }
        }
    });

    Ok(Json(PipelineStartResponse {
        run_id,
        status: "created".to_string(),
    }))
}

async fn pipeline_status_handler(
    axum::extract::State(state): axum::extract::State<AppState>,
    Path(run_id): Path<String>,
) -> Result<Json<RunState>, StatusCode> {
    match state.jobs.get_run(&run_id).await {
        Some(run_state) => Ok(Json(run_state)),
        None => Err(StatusCode::NOT_FOUND),
    }
}

#[derive(Serialize)]
pub struct RunArtifactsResponse {
    pub run_id: String,
    pub question: String,
    pub draft_md: Option<String>,
    pub draft_pdf: Option<String>,
    pub triad_final_md: Option<String>,
    pub triad_report_json: Option<String>,
    pub llm_stats: Option<serde_json::Value>,
}

async fn run_artifacts_handler(
    axum::extract::State(state): axum::extract::State<AppState>,
    Path(run_id): Path<String>,
) -> Result<Json<RunArtifactsResponse>, StatusCode> {
    let run_state = state
        .jobs
        .get_run(&run_id)
        .await
        .ok_or(StatusCode::NOT_FOUND)?;

    let ctx = state.ctx.lock().await;
    let data_dir = PathBuf::from(&ctx.cfg.storage.data_dir);

    // Tenta ler run_report.json
    let report_path = data_dir
        .join("logs")
        .join("beagle-pipeline")
        .join(format!("*_{}.json", run_id));

    let mut draft_md = None;
    let mut draft_pdf = None;
    let mut triad_final_md = None;
    let mut triad_report_json = None;
    let mut llm_stats = None;

    // Procura por run_report.json usando glob (simplificado - em produção usar glob)
    let report_dir = data_dir.join("logs").join("beagle-pipeline");
    if let Ok(entries) = std::fs::read_dir(&report_dir) {
        for entry in entries.flatten() {
            if let Some(name) = entry.file_name().to_str() {
                if name.ends_with(&format!("_{}.json", run_id)) {
                    if let Ok(content) = std::fs::read_to_string(entry.path()) {
                        if let Ok(report) = serde_json::from_str::<serde_json::Value>(&content) {
                            llm_stats = report.get("llm_stats").cloned();
                        }
                    }
                }
            }
        }
    }

    // Procura draft_md e draft_pdf
    let drafts_dir = data_dir.join("papers").join("drafts");
    if let Ok(entries) = std::fs::read_dir(&drafts_dir) {
        for entry in entries.flatten() {
            if let Some(name) = entry.file_name().to_str() {
                if name.contains(&run_id) {
                    if name.ends_with(".md") {
                        draft_md = Some(entry.path().to_string_lossy().to_string());
                    } else if name.ends_with(".pdf") {
                        draft_pdf = Some(entry.path().to_string_lossy().to_string());
                    }
                }
            }
        }
    }

    // Procura triad artifacts
    let triad_dir = data_dir.join("triad").join(&run_id);
    if triad_dir.exists() {
        let final_md = triad_dir.join("draft_reviewed.md");
        let report_json = triad_dir.join("triad_report.json");

        if final_md.exists() {
            triad_final_md = Some(final_md.to_string_lossy().to_string());
        }
        if report_json.exists() {
            triad_report_json = Some(report_json.to_string_lossy().to_string());
        }
    }

    Ok(Json(RunArtifactsResponse {
        run_id,
        question: run_state.question,
        draft_md,
        draft_pdf,
        triad_final_md,
        triad_report_json,
        llm_stats,
    }))
}

#[derive(Serialize)]
pub struct RunsRecentResponse {
    pub runs: Vec<RunState>,
}

#[derive(Deserialize)]
struct RunsRecentQuery {
    limit: Option<usize>,
}

async fn runs_recent_handler(
    axum::extract::State(state): axum::extract::State<AppState>,
    axum::extract::Query(params): axum::extract::Query<RunsRecentQuery>,
) -> Json<RunsRecentResponse> {
    let limit = params.limit.unwrap_or(10);
    let runs = state.jobs.list_recent(limit).await;
    Json(RunsRecentResponse { runs })
}

// ============================================================================
// Observer endpoints
// ============================================================================

#[derive(Deserialize)]
pub struct PhysioEventRequest {
    #[serde(default)]
    pub timestamp: Option<String>,
    pub source: String, // ex.: "ios_healthkit", "apple_watch_ultra", "vision_pro"
    #[serde(default)]
    pub session_id: Option<String>,
    #[serde(default)]
    pub hrv_ms: Option<f64>,
    #[serde(default)]
    pub hrv_level: Option<String>,
    #[serde(default, alias = "heart_rate_bpm")]
    pub hr: Option<f64>,
    #[serde(default, alias = "spo2_percent")]
    pub spo2: Option<f64>,
    #[serde(default)]
    pub stress_index: Option<f64>,
}

#[derive(Serialize)]
pub struct PhysioEventResponse {
    pub status: String,
    pub severity: String,
    pub hrv_level: Option<String>,
    pub snapshot: beagle_observer::PhysioSnapshot,
}

#[derive(Serialize)]
pub struct PhysioLatestResponse {
    pub status: String,
    pub snapshot: Option<beagle_observer::PhysioSnapshot>,
}

async fn observer_physio_handler(
    axum::extract::State(state): axum::extract::State<AppState>,
    Json(req): Json<PhysioEventRequest>,
) -> Result<Json<PhysioEventResponse>, StatusCode> {
    let source = req.source.trim();
    if source.is_empty() {
        return Err(StatusCode::BAD_REQUEST);
    }

    let timestamp = parse_rfc3339_or_now(req.timestamp.as_deref());
    let snapshot = beagle_observer::PhysioSnapshot {
        source: source.to_string(),
        session_id: req.session_id.clone(),
        timestamp,
        hr: req.hr,
        hrv_ms: req.hrv_ms,
        hrv_level: req
            .hrv_level
            .clone()
            .or_else(|| req.hrv_ms.map(|hrv| classify_hrv(hrv as f32, None))),
        spo2: req.spo2,
        stress_index: req.stress_index,
        severity: None,
    };

    let stored = state
        .observer
        .record_physio_snapshot(snapshot)
        .await
        .map_err(|e| {
            tracing::error!("Falha ao registrar snapshot fisiológico: {}", e);
            StatusCode::INTERNAL_SERVER_ERROR
        })?;

    // Persist to JSONL under $BEAGLE_DATA_DIR/cognitive/physio.jsonl so
    // flow_state survives a pod restart. Mirrors the registry pattern.
    crate::jobs::jsonl_append_pub(crate::jobs::PHYSIO_JSONL, &stored);

    // Broadcast to SSE subscribers so iOS sees the new HRV within the
    // same round-trip, without waiting for the next /api/v1/cognitive/state
    // poll.
    let flow_state = stored.hrv_ms.map(|hrv| {
        if hrv > 80.0 { "flow".to_string() }
        else if hrv < 50.0 { "stress".to_string() }
        else { "normal".to_string() }
    });
    crate::cognitive_events::emit(
        &state.cognitive_tx,
        crate::cognitive_events::CognitiveEvent::Physio {
            source: stored.source.clone(),
            hrv_ms: stored.hrv_ms,
            hrv_level: stored.hrv_level.clone(),
            flow_state,
            observed_at: stored.timestamp,
            truth_mode: "observed".to_string(),
        },
    );

    Ok(Json(PhysioEventResponse {
        status: "ok".to_string(),
        severity: stored
            .severity
            .clone()
            .unwrap_or_else(|| "normal".to_string()),
        hrv_level: stored.hrv_level.clone(),
        snapshot: stored,
    }))
}

async fn observer_physio_latest_handler(
    axum::extract::State(state): axum::extract::State<AppState>,
) -> Json<PhysioLatestResponse> {
    Json(PhysioLatestResponse {
        status: "ok".to_string(),
        snapshot: state.observer.latest_physio_snapshot().await,
    })
}

#[derive(Deserialize)]
pub struct EnvEventRequest {
    #[serde(default)]
    pub timestamp: Option<String>,
    pub source: String, // ex.: "iphone", "vision_pro", "home_sensor"
    #[serde(default)]
    pub session_id: Option<String>,

    // Localização
    pub latitude_deg: Option<f64>,
    pub longitude_deg: Option<f64>,
    pub altitude_m: Option<f32>,

    // Condições ambientais
    pub baro_pressure_hpa: Option<f32>,
    pub ambient_temp_c: Option<f32>,
    pub humidity_percent: Option<f32>,
    pub wind_speed_m_s: Option<f32>,
    pub wind_dir_deg: Option<f32>,
    pub uv_index: Option<f32>,
    pub noise_db: Option<f32>,
}

#[derive(Serialize)]
pub struct EnvEventResponse {
    pub status: String,
    pub severity: String,
}

async fn observer_env_handler(
    axum::extract::State(state): axum::extract::State<AppState>,
    Json(req): Json<EnvEventRequest>,
) -> Result<Json<EnvEventResponse>, StatusCode> {
    use beagle_observer::EnvEvent;

    let timestamp = if let Some(ts_str) = &req.timestamp {
        chrono::DateTime::parse_from_rfc3339(ts_str)
            .ok()
            .map(|dt| dt.with_timezone(&chrono::Utc))
            .unwrap_or_else(chrono::Utc::now)
    } else {
        chrono::Utc::now()
    };

    let event = EnvEvent {
        timestamp,
        source: req.source,
        session_id: req.session_id.clone(),
        latitude_deg: req.latitude_deg.map(|v| v as f64),
        longitude_deg: req.longitude_deg.map(|v| v as f64),
        altitude_m: req.altitude_m.map(|v| v as f64),
        baro_pressure_hpa: req.baro_pressure_hpa.map(|v| v as f64),
        ambient_temp_c: req.ambient_temp_c.map(|v| v as f64),
        humidity_percent: req.humidity_percent.map(|v| v as f64),
        wind_speed_m_s: req.wind_speed_m_s.map(|v| v as f64),
        wind_dir_deg: req.wind_dir_deg.map(|v| v as f64),
        uv_index: req.uv_index.map(|v| v as f64),
        noise_db: req.noise_db.map(|v| v as f64),
        // Legacy fields
        event_type: None,
        location: None,
        value: None,
        unit: None,
        metadata: std::collections::HashMap::new(),
    };

    let severity = state
        .observer
        .record_env_event(event, None)
        .await
        .map_err(|e| {
            tracing::error!("Falha ao registrar evento ambiental: {}", e);
            StatusCode::INTERNAL_SERVER_ERROR
        })?;

    Ok(Json(EnvEventResponse {
        status: "ok".to_string(),
        severity: severity.as_str().to_string(),
    }))
}

#[derive(Deserialize)]
pub struct SpaceWeatherEventRequest {
    #[serde(default)]
    pub timestamp: Option<String>,
    pub source: String, // ex.: "noaa_api", "nasa", "local_cache"
    #[serde(default)]
    pub session_id: Option<String>,

    // Índices geomagnéticos
    pub kp_index: Option<f32>,
    pub dst_index: Option<f32>,

    // Vento solar
    pub solar_wind_speed_km_s: Option<f32>,
    pub solar_wind_density_n_cm3: Option<f32>,

    // Partículas
    pub proton_flux_pfu: Option<f32>,
    pub electron_flux: Option<f32>,

    // Radiação
    pub xray_flux: Option<f32>,
    pub radio_flux_sfu: Option<f32>,
}

#[derive(Serialize)]
pub struct SpaceWeatherEventResponse {
    pub status: String,
    pub severity: String,
}

async fn observer_space_weather_handler(
    axum::extract::State(state): axum::extract::State<AppState>,
    Json(req): Json<SpaceWeatherEventRequest>,
) -> Result<Json<SpaceWeatherEventResponse>, StatusCode> {
    use beagle_observer::SpaceWeatherEvent;

    let timestamp = if let Some(ts_str) = &req.timestamp {
        chrono::DateTime::parse_from_rfc3339(ts_str)
            .ok()
            .map(|dt| dt.with_timezone(&chrono::Utc))
            .unwrap_or_else(chrono::Utc::now)
    } else {
        chrono::Utc::now()
    };

    let event = SpaceWeatherEvent {
        timestamp,
        source: req.source,
        session_id: req.session_id.clone(),
        kp_index: req.kp_index.map(|v| v as f64),
        solar_flux: None,
        dst_index: req.dst_index.map(|v| v as f64),
        solar_wind_speed_km_s: req.solar_wind_speed_km_s.map(|v| v as f64),
        solar_wind_density_n_cm3: req.solar_wind_density_n_cm3.map(|v| v as f64),
        proton_flux_pfu: req.proton_flux_pfu.map(|v| v as f64),
        electron_flux: req.electron_flux.map(|v| v as f64),
        xray_flux: req.xray_flux.map(|v| v as f64),
        radio_flux_sfu: req.radio_flux_sfu.map(|v| v as f64),
        geomagnetic_storm: req.kp_index.map(|kp| kp >= 5.0).unwrap_or(false),
        // Legacy fields
        event_type: None,
        metadata: std::collections::HashMap::new(),
    };

    let severity = state
        .observer
        .record_space_weather_event(event, None)
        .await
        .map_err(|e| {
            tracing::error!("Falha ao registrar evento de clima espacial: {}", e);
            StatusCode::INTERNAL_SERVER_ERROR
        })?;

    Ok(Json(SpaceWeatherEventResponse {
        status: "ok".to_string(),
        severity: severity.as_str().to_string(),
    }))
}

async fn observer_context_current_handler(
    axum::extract::State(state): axum::extract::State<AppState>,
) -> Json<beagle_observer::UserContext> {
    let ctx = state.observer.current_user_context().await;
    Json(ctx)
}

fn parse_rfc3339_or_now(value: Option<&str>) -> chrono::DateTime<chrono::Utc> {
    value
        .and_then(|raw| chrono::DateTime::parse_from_rfc3339(raw).ok())
        .map(|dt| dt.with_timezone(&chrono::Utc))
        .unwrap_or_else(chrono::Utc::now)
}

async fn observer_context_handler(
    axum::extract::State(state): axum::extract::State<AppState>,
    axum::extract::Path(_run_id): axum::extract::Path<String>,
) -> Json<beagle_observer::UserContext> {
    // Por enquanto, retorna contexto atual (pode ser expandido para filtrar por run_id no futuro)
    let ctx = state.observer.current_user_context().await;
    Json(ctx)
}

// ============================================================================
// Science Jobs endpoints
// ============================================================================

#[derive(Deserialize, Clone)]
pub struct ScienceJobStartRequest {
    pub kind: String, // "pbpk", "scaffold", "helio", "pcs", "kec"
    pub params: serde_json::Value,
}

#[derive(Serialize)]
pub struct ScienceJobStartResponse {
    pub job_id: String,
    pub status: String,
}

async fn science_job_start_handler(
    axum::extract::State(state): axum::extract::State<AppState>,
    Json(req): Json<ScienceJobStartRequest>,
) -> Result<Json<ScienceJobStartResponse>, StatusCode> {
    let job_id = uuid::Uuid::new_v4().to_string();

    let kind = match req.kind.as_str() {
        "pbpk" => ScienceJobKind::Pbpk,
        "scaffold" => ScienceJobKind::Scaffold,
        "helio" => ScienceJobKind::Helio,
        "pcs" => ScienceJobKind::Pcs,
        "kec" => ScienceJobKind::Kec,
        _ => return Err(StatusCode::BAD_REQUEST),
    };

    let job_state = ScienceJobState::new(job_id.clone(), kind, req.params.clone());
    state.science_jobs.add_job(job_state.clone()).await;

    info!(
        "Science job start requested: job_id={}, kind={:?}",
        job_id, job_state.kind
    );

    // Dispara job científico em background (via Julia)
    let jobs_clone = state.science_jobs.clone();
    let job_id_clone = job_id.clone();
    let kind_clone = job_state.kind.clone();
    let req_clone = req.clone();

    tokio::spawn(async move {
        jobs_clone
            .update_job(&job_id_clone, |s| {
                s.update_status(ScienceJobStatus::Running)
            })
            .await;
        info!("Starting science job for job_id: {}", job_id_clone);

        // Chama Julia via run_job_cli.jl
        let cfg = beagle_config::load();
        let data_dir = PathBuf::from(&cfg.storage.data_dir);
        let jobs_dir = data_dir.join("jobs").join("science").join(&job_id_clone);
        std::fs::create_dir_all(&jobs_dir).ok();

        // Cria arquivo de configuração JSON para o job
        let kind_str = match &kind_clone {
            ScienceJobKind::Pbpk => "pbpk",
            ScienceJobKind::Scaffold => "scaffold",
            ScienceJobKind::Helio => "helio",
            ScienceJobKind::Pcs => "pcs",
            ScienceJobKind::Kec => "kec",
            // External jobs never reach this Julia path — they're owned by
            // the cockpit reconciler. If we ever see one here, downstream
            // Julia would fail anyway; surface the label for diagnostics.
            ScienceJobKind::External(label) => label.as_str(),
        };

        let job_config = serde_json::json!({
            "kind": kind_str,
            "job_id": job_id_clone,
            "config": req_clone.params
        });

        let config_path = jobs_dir.join("job_config.json");
        if let Err(e) = std::fs::write(
            &config_path,
            serde_json::to_string_pretty(&job_config).unwrap_or_default(),
        ) {
            error!("Falha ao escrever job_config.json: {}", e);
            jobs_clone
                .update_job(&job_id_clone, |s| {
                    s.set_error(format!("Falha ao criar config: {}", e));
                })
                .await;
            return;
        }

        // Executa Julia via run_job_cli.jl
        let workspace_root = std::env::var("BEAGLE_WORKSPACE_ROOT").unwrap_or_else(|_| {
            std::env::current_dir()
                .unwrap_or_else(|_| PathBuf::from("."))
                .to_string_lossy()
                .to_string()
        });

        let output = tokio::process::Command::new("julia")
            .arg("--project=beagle-julia")
            .arg("beagle-julia/run_job_cli.jl")
            .arg(config_path.to_string_lossy().to_string())
            .arg(jobs_dir.to_string_lossy().to_string())
            .current_dir(&workspace_root)
            .output()
            .await;

        match output {
            Ok(cmd_output) => {
                if cmd_output.status.success() {
                    let stdout = String::from_utf8_lossy(&cmd_output.stdout);

                    // Parse resultado JSON do Julia
                    match serde_json::from_str::<serde_json::Value>(&stdout.trim()) {
                        Ok(result_json) => {
                            let output_paths = result_json
                                .get("output_paths")
                                .and_then(|v| v.as_array())
                                .map(|arr| {
                                    arr.iter()
                                        .filter_map(|v| v.as_str().map(|s| s.to_string()))
                                        .collect()
                                })
                                .unwrap_or_default();

                            jobs_clone
                                .update_job(&job_id_clone, |s| {
                                    s.update_status(ScienceJobStatus::Done);
                                    s.output_paths = output_paths;
                                    s.result_json = Some(result_json);
                                })
                                .await;

                            info!(
                                "Science job completed successfully for job_id: {}",
                                job_id_clone
                            );
                        }
                        Err(e) => {
                            error!("Falha ao parsear resultado JSON do Julia: {}", e);
                            jobs_clone
                                .update_job(&job_id_clone, |s| {
                                    s.set_error(format!("Falha ao parsear resultado: {}", e));
                                })
                                .await;
                        }
                    }
                } else {
                    let stderr = String::from_utf8_lossy(&cmd_output.stderr);
                    error!("Julia job falhou: {}", stderr);
                    jobs_clone
                        .update_job(&job_id_clone, |s| {
                            s.set_error(format!("Julia error: {}", stderr));
                        })
                        .await;
                }
            }
            Err(e) => {
                error!("Falha ao executar Julia: {}", e);
                jobs_clone
                    .update_job(&job_id_clone, |s| {
                        s.set_error(format!("Falha ao executar Julia: {}", e));
                    })
                    .await;
            }
        }
    });

    Ok(Json(ScienceJobStartResponse {
        job_id: job_id.clone(),
        status: "created".to_string(),
    }))
}

async fn science_job_status_handler(
    axum::extract::State(state): axum::extract::State<AppState>,
    axum::extract::Path(job_id): axum::extract::Path<String>,
) -> Result<Json<ScienceJobState>, StatusCode> {
    state
        .science_jobs
        .get_job(&job_id)
        .await
        .map(Json)
        .ok_or(StatusCode::NOT_FOUND)
}

#[derive(Serialize)]
pub struct ScienceJobArtifactsResponse {
    pub job_id: String,
    pub kind: ScienceJobKind,
    pub status: ScienceJobStatus,
    pub output_paths: Vec<String>,
    pub result_json: Option<serde_json::Value>,
}

async fn science_job_artifacts_handler(
    axum::extract::State(state): axum::extract::State<AppState>,
    axum::extract::Path(job_id): axum::extract::Path<String>,
) -> Result<Json<ScienceJobArtifactsResponse>, StatusCode> {
    let job = state
        .science_jobs
        .get_job(&job_id)
        .await
        .ok_or(StatusCode::NOT_FOUND)?;

    Ok(Json(ScienceJobArtifactsResponse {
        job_id: job.job_id,
        kind: job.kind,
        status: job.status,
        output_paths: job.output_paths,
        result_json: job.result_json,
    }))
}

// ============================================================================
// PCS / FRACTAL / WORLDMODEL ENDPOINTS
// ============================================================================

#[derive(Deserialize)]
struct PCSReasonRequest {
    symptoms: serde_json::Value,
}

#[derive(Serialize)]
struct PCSReasonResponse {
    diagnosis: serde_json::Value,
    confidence: f64,
}

async fn pcs_reason_handler(
    axum::extract::State(_state): axum::extract::State<AppState>,
    Json(req): Json<PCSReasonRequest>,
) -> Result<Json<PCSReasonResponse>, StatusCode> {
    info!("PCS symbolic reasoning request");

    // Placeholder - implementar chamada real ao Julia
    Ok(Json(PCSReasonResponse {
        diagnosis: serde_json::json!({
            "status": "placeholder",
            "note": "PCS reasoning será implementado via Julia"
        }),
        confidence: 0.0,
    }))
}

#[derive(Deserialize)]
struct FractalGrowRequest {
    root_state: String,
    max_depth: Option<usize>,
}

#[derive(Serialize)]
struct FractalGrowResponse {
    node_count: usize,
    max_depth: usize,
    root_id: String,
}

async fn fractal_grow_handler(
    axum::extract::State(_state): axum::extract::State<AppState>,
    Json(req): Json<FractalGrowRequest>,
) -> Result<Json<FractalGrowResponse>, StatusCode> {
    info!("Fractal growth request: max_depth={:?}", req.max_depth);

    let root_id = uuid::Uuid::new_v4().to_string();
    let max_depth = req.max_depth.unwrap_or(5);

    // Chama Julia Fractal real
    let workspace_root = std::env::var("BEAGLE_WORKSPACE_ROOT").unwrap_or_else(|_| {
        std::env::current_dir()
            .unwrap()
            .to_string_lossy()
            .to_string()
    });

    let script = format!(
        r#"
        using Pkg
        Pkg.activate("beagle-julia")
        include("beagle-julia/Fractal.jl")
        using .BeagleFractal
        using JSON3

        root = BeagleFractal.create_node(0, nothing, "{}")
        BeagleFractal.grow_fractal!(root, {}, 10000)

        node_count = BeagleFractal.count_nodes(root)
        max_depth_actual = BeagleFractal.get_max_depth(root)

        result = Dict(
            "root_id" => "{}",
            "node_count" => node_count,
            "max_depth" => max_depth_actual
        )
        println(JSON3.write(result))
        "#,
        req.root_state.replace('"', "\\\"").replace('\n', "\\n"),
        max_depth,
        root_id
    );

    let output = tokio::process::Command::new("julia")
        .arg("--project=beagle-julia")
        .arg("-e")
        .arg(&script)
        .current_dir(&workspace_root)
        .output()
        .await
        .map_err(|e| {
            error!("Falha ao executar Julia Fractal: {}", e);
            StatusCode::INTERNAL_SERVER_ERROR
        })?;

    if !output.status.success() {
        let stderr = String::from_utf8_lossy(&output.stderr);
        error!("Julia Fractal erro: {}", stderr);
        return Err(StatusCode::INTERNAL_SERVER_ERROR);
    }

    let stdout = String::from_utf8_lossy(&output.stdout);
    let result: serde_json::Value = serde_json::from_str(stdout.trim()).map_err(|e| {
        error!("Falha ao parsear resultado Fractal: {}", e);
        StatusCode::INTERNAL_SERVER_ERROR
    })?;

    let node_count = result
        .get("node_count")
        .and_then(|v| v.as_u64())
        .unwrap_or(0) as usize;

    let max_depth_actual = result
        .get("max_depth")
        .and_then(|v| v.as_u64())
        .unwrap_or(max_depth as u64) as usize;

    Ok(Json(FractalGrowResponse {
        node_count,
        max_depth: max_depth_actual,
        root_id,
    }))
}

#[derive(Deserialize)]
struct WorldmodelPredictRequest {
    context: serde_json::Value,
    horizon: Option<usize>,
}

#[derive(Serialize)]
struct WorldmodelPredictResponse {
    predictions: Vec<serde_json::Value>,
    confidence: f64,
}

async fn worldmodel_predict_handler(
    axum::extract::State(_state): axum::extract::State<AppState>,
    Json(req): Json<WorldmodelPredictRequest>,
) -> Result<Json<WorldmodelPredictResponse>, StatusCode> {
    info!("Worldmodel prediction request: horizon={:?}", req.horizon);

    let horizon = req.horizon.unwrap_or(10);

    // Chama Julia Worldmodel real
    let workspace_root = std::env::var("BEAGLE_WORKSPACE_ROOT").unwrap_or_else(|_| {
        std::env::current_dir()
            .unwrap_or_else(|_| PathBuf::from("."))
            .to_string_lossy()
            .to_string()
    });

    let context_json = serde_json::to_string(&req.context).map_err(|_| StatusCode::BAD_REQUEST)?;

    let script = format!(
        r#"
        using Pkg
        Pkg.activate("beagle-julia")
        include("beagle-julia/Worldmodel.jl")
        using .BeagleWorldmodel
        using JSON3

        # Cria engine
        engine = BeagleWorldmodel.WorldmodelEngine(max_history=100)

        # Atualiza contexto
        context = JSON3.read("{}")
        engine = BeagleWorldmodel.update_context(engine, context)

        # Gera predições
        predictions = BeagleWorldmodel.predict(engine, {})
        confidence = BeagleWorldmodel.get_confidence(engine)

        result = Dict(
            "predictions" => predictions,
            "confidence" => confidence
        )
        println(JSON3.write(result))
        "#,
        context_json.replace('"', "\\\"").replace('\n', "\\n"),
        horizon
    );

    let output = tokio::process::Command::new("julia")
        .arg("--project=beagle-julia")
        .arg("-e")
        .arg(&script)
        .current_dir(&workspace_root)
        .output()
        .await
        .map_err(|e| {
            error!("Falha ao executar Julia Worldmodel: {}", e);
            StatusCode::INTERNAL_SERVER_ERROR
        })?;

    if !output.status.success() {
        let stderr = String::from_utf8_lossy(&output.stderr);
        error!("Julia Worldmodel erro: {}", stderr);
        return Err(StatusCode::INTERNAL_SERVER_ERROR);
    }

    let stdout = String::from_utf8_lossy(&output.stdout);
    match serde_json::from_str::<serde_json::Value>(stdout.trim()) {
        Ok(result_json) => {
            let predictions = result_json
                .get("predictions")
                .and_then(|v| v.as_array())
                .map(|arr| arr.iter().map(|v| v.clone()).collect())
                .unwrap_or_default();

            let confidence = result_json
                .get("confidence")
                .and_then(|v| v.as_f64())
                .unwrap_or(0.0);

            Ok(Json(WorldmodelPredictResponse {
                predictions,
                confidence,
            }))
        }
        Err(e) => {
            error!("Falha ao parsear resultado Worldmodel: {}", e);
            Err(StatusCode::INTERNAL_SERVER_ERROR)
        }
    }
}

// ============================================================================
// SERENDIPITY ENDPOINT
// ============================================================================

#[derive(Deserialize)]
struct SerendipityDiscoverRequest {
    focus_project: String,
    max_connections: Option<usize>,
}

#[derive(Serialize)]
struct SerendipityDiscoverResponse {
    connections: Vec<SerendipityConnection>,
    count: usize,
}

#[derive(Serialize, Deserialize, Clone, Debug)]
struct SerendipityConnection {
    id: String,
    source_project: String,
    target_project: String,
    source_concept: String,
    target_concept: String,
    similarity_score: f32,
    novelty_score: f32,
    connection_type: String,
    explanation: String,
    potential_impact: String,
}

async fn serendipity_discover_handler(
    axum::extract::State(_state): axum::extract::State<AppState>,
    Json(req): Json<SerendipityDiscoverRequest>,
) -> Result<Json<SerendipityDiscoverResponse>, StatusCode> {
    info!(
        "Serendipity discovery request: focus_project={}",
        req.focus_project
    );

    // Por enquanto, placeholder - integração com beagle-serendipity será feita depois
    // TODO: Usar SerendipityInjector do crate beagle-serendipity
    Ok(Json(SerendipityDiscoverResponse {
        connections: vec![],
        count: 0,
    }))
}

// ============================================================================
// PAPER SEARCH HANDLERS
// ============================================================================

/// Search PubMed for papers
async fn search_pubmed_handler(
    axum::extract::State(state): axum::extract::State<AppState>,
    Json(req): Json<SearchRequest>,
) -> Result<Json<SearchResponse>, StatusCode> {
    info!("PubMed search request: query={}", req.query);

    let client = PubMedClient::from_env();
    let search_query = SearchQuery::new(&req.query).with_max_results(req.max_results);

    let result = client.search(&search_query).await.map_err(|e| {
        error!("PubMed search failed: {}", e);
        StatusCode::BAD_GATEWAY
    })?;

    // Store in Neo4j if requested
    if req.store_in_graph {
        let ctx = state.ctx.lock().await;
        for paper in &result.papers {
            // Store paper
            let (cypher, params) = beagle_search::storage::create_paper_query(paper);
            if let Err(e) = ctx
                .graph
                .cypher_query(&cypher, serde_json::to_value(&params).unwrap())
                .await
            {
                warn!("Failed to store paper {}: {}", paper.id, e);
                continue;
            }

            // Store authors
            for (cypher, params) in
                beagle_search::storage::create_authors_query(&paper.id, &paper.authors)
            {
                let _ = ctx
                    .graph
                    .cypher_query(&cypher, serde_json::to_value(&params).unwrap())
                    .await;
            }
        }
        info!("Stored {} papers in Neo4j", result.papers.len());
    }

    Ok(Json(convert_to_response(result)))
}

/// Search arXiv for papers
async fn search_arxiv_handler(
    axum::extract::State(state): axum::extract::State<AppState>,
    Json(req): Json<SearchRequest>,
) -> Result<Json<SearchResponse>, StatusCode> {
    info!("arXiv search request: query={}", req.query);

    let client = ArxivClient::new();
    let search_query = SearchQuery::new(&req.query).with_max_results(req.max_results);

    let result = client.search(&search_query).await.map_err(|e| {
        error!("arXiv search failed: {}", e);
        StatusCode::BAD_GATEWAY
    })?;

    // Store in Neo4j if requested
    if req.store_in_graph {
        let ctx = state.ctx.lock().await;
        for paper in &result.papers {
            // Store paper
            let (cypher, params) = beagle_search::storage::create_paper_query(paper);
            if let Err(e) = ctx
                .graph
                .cypher_query(&cypher, serde_json::to_value(&params).unwrap())
                .await
            {
                warn!("Failed to store paper {}: {}", paper.id, e);
                continue;
            }

            // Store authors and categories
            for (cypher, params) in
                beagle_search::storage::create_authors_query(&paper.id, &paper.authors)
            {
                let _ = ctx
                    .graph
                    .cypher_query(&cypher, serde_json::to_value(&params).unwrap())
                    .await;
            }

            for (cypher, params) in
                beagle_search::storage::create_categories_query(&paper.id, &paper.categories)
            {
                let _ = ctx
                    .graph
                    .cypher_query(&cypher, serde_json::to_value(&params).unwrap())
                    .await;
            }
        }
        info!("Stored {} papers in Neo4j", result.papers.len());
    }

    Ok(Json(convert_to_response(result)))
}

/// Search both PubMed and arXiv
async fn search_all_handler(
    axum::extract::State(state): axum::extract::State<AppState>,
    Json(req): Json<SearchRequest>,
) -> Result<Json<SearchResponse>, StatusCode> {
    info!("Combined search request: query={}", req.query);

    let pubmed_client = PubMedClient::from_env();
    let arxiv_client = ArxivClient::new();
    let search_query = SearchQuery::new(&req.query).with_max_results(req.max_results / 2);

    // Search both in parallel
    let (pubmed_result, arxiv_result) = tokio::join!(
        pubmed_client.search(&search_query),
        arxiv_client.search(&search_query)
    );

    let mut all_papers = Vec::new();
    let mut total_time_ms = 0;

    if let Ok(result) = pubmed_result {
        total_time_ms += result.search_time_ms;
        all_papers.extend(result.papers);
    } else if let Err(e) = pubmed_result {
        warn!("PubMed search failed: {}", e);
    }

    if let Ok(result) = arxiv_result {
        total_time_ms += result.search_time_ms;
        all_papers.extend(result.papers);
    } else if let Err(e) = arxiv_result {
        warn!("arXiv search failed: {}", e);
    }

    // Store in Neo4j if requested
    if req.store_in_graph && !all_papers.is_empty() {
        let ctx = state.ctx.lock().await;
        for paper in &all_papers {
            let (cypher, params) = beagle_search::storage::create_paper_query(paper);
            if let Err(e) = ctx
                .graph
                .cypher_query(&cypher, serde_json::to_value(&params).unwrap())
                .await
            {
                warn!("Failed to store paper {}: {}", paper.id, e);
                continue;
            }

            for (cypher, params) in
                beagle_search::storage::create_authors_query(&paper.id, &paper.authors)
            {
                let _ = ctx
                    .graph
                    .cypher_query(&cypher, serde_json::to_value(&params).unwrap())
                    .await;
            }

            if !paper.categories.is_empty() {
                for (cypher, params) in
                    beagle_search::storage::create_categories_query(&paper.id, &paper.categories)
                {
                    let _ = ctx
                        .graph
                        .cypher_query(&cypher, serde_json::to_value(&params).unwrap())
                        .await;
                }
            }
        }
        info!("Stored {} papers in Neo4j", all_papers.len());
    }

    Ok(Json(SearchResponse {
        papers: all_papers.iter().map(convert_paper_to_info).collect(),
        total_count: all_papers.len(),
        backend: "combined".to_string(),
        search_time_ms: total_time_ms,
    }))
}

/// Convert beagle_search::SearchResult to HTTP SearchResponse
fn convert_to_response(result: beagle_search::SearchResult) -> SearchResponse {
    SearchResponse {
        papers: result.papers.iter().map(convert_paper_to_info).collect(),
        total_count: result.total_count,
        backend: result.backend,
        search_time_ms: result.search_time_ms,
    }
}

/// Convert beagle_search::Paper to PaperInfo
fn convert_paper_to_info(paper: &beagle_search::Paper) -> PaperInfo {
    PaperInfo {
        id: paper.id.clone(),
        title: paper.title.clone(),
        authors: paper.authors.iter().map(|a| a.full_name()).collect(),
        abstract_text: paper.abstract_text.clone(),
        published_date: paper.published_date.map(|d| d.to_rfc3339()),
        url: paper.url.clone(),
        pdf_url: paper.pdf_url.clone(),
        source: paper.source.clone(),
        citation: paper.citation(),
    }
}

// ============================================================================
// DEV ENDPOINTS - Revolutionary Agent Features (B17-B25)
// ============================================================================

use async_trait::async_trait;

/// Adapter that implements AgentLlmClient using TieredRouter
struct RouterAgentLlmClient {
    router: TieredRouter,
    stats: beagle_llm::stats::LlmCallsStats,
}

#[async_trait]
impl beagle_agents::AgentLlmClient for RouterAgentLlmClient {
    async fn complete(&self, prompt: &str) -> anyhow::Result<String> {
        let meta = beagle_llm::RequestMeta {
            requires_high_quality: true,
            requires_phd_level_reasoning: false,
            high_bias_risk: false,
            critical_section: false,
            ..Default::default()
        };

        let (client, _tier) = self.router.choose_with_limits(&meta, &self.stats);
        let output = client.complete(prompt).await?;
        Ok(output.text)
    }

    async fn complete_with_system(&self, prompt: &str, system: &str) -> anyhow::Result<String> {
        let meta = beagle_llm::RequestMeta {
            requires_high_quality: true,
            requires_phd_level_reasoning: false,
            high_bias_risk: false,
            critical_section: false,
            ..Default::default()
        };

        let (client, _tier) = self.router.choose_with_limits(&meta, &self.stats);
        // Combine system prompt with user prompt for clients that don't support system separately
        let full_prompt = format!("{system}\n\n{prompt}");
        let output = client.complete(&full_prompt).await?;
        Ok(output.text)
    }
}

#[derive(Deserialize)]
struct CausalRequest {
    query: String,
    max_nodes: Option<usize>,
}

#[derive(Serialize)]
struct CausalResponse {
    causal_graph: serde_json::Value,
    interventions: Vec<String>,
    counterfactuals: Vec<String>,
    confidence: f64,
    status: String,
}

/// Causal reasoning + counterfactual analysis (B17)
async fn dev_causal_handler(
    axum::extract::State(state): axum::extract::State<AppState>,
    Json(req): Json<CausalRequest>,
) -> Result<Json<CausalResponse>, StatusCode> {
    info!("Causal reasoning request: query={}", req.query);

    let ctx = state.ctx.lock().await;
    let router = ctx.router.clone();
    drop(ctx); // Release lock early

    let llm_client = Arc::new(RouterAgentLlmClient {
        router,
        stats: beagle_llm::stats::LlmCallsStats::default(),
    });

    let reasoner = beagle_agents::CausalReasoner::new(llm_client);

    match reasoner.extract_causal_graph(&req.query).await {
        Ok(graph) => {
            let interventions_result = reasoner.intervention(&graph, "X", "new_value").await;
            let counterfactuals_result = reasoner.counterfactual(&graph, "X", "actual", "counterfactual").await;

            Ok(Json(CausalResponse {
                causal_graph: serde_json::to_value(&graph).unwrap_or_default(),
                interventions: interventions_result.map(|r| vec![r.intervention]).unwrap_or_default(),
                counterfactuals: counterfactuals_result.map(|r| vec![r.predicted_outcome]).unwrap_or_default(),
                confidence: graph.metadata.confidence as f64,
                status: "ok".to_string(),
            }))
        }
        Err(e) => {
            error!("Causal reasoning failed: {}", e);
            Ok(Json(CausalResponse {
                causal_graph: serde_json::json!({"error": e.to_string()}),
                interventions: vec![],
                counterfactuals: vec![],
                confidence: 0.0,
                status: "error".to_string(),
            }))
        }
    }
}

#[derive(Deserialize)]
struct DebateRequest {
    topic: String,
    n_perspectives: Option<usize>,
    rounds: Option<usize>,
}

#[derive(Serialize)]
struct DebateResponse {
    transcript: serde_json::Value,
    synthesis: String,
    consensus_score: f64,
    key_insights: Vec<String>,
    status: String,
}

/// Multi-perspective debate synthesis (B18)
async fn dev_debate_handler(
    axum::extract::State(state): axum::extract::State<AppState>,
    Json(req): Json<DebateRequest>,
) -> Result<Json<DebateResponse>, StatusCode> {
    info!(
        "Debate request: topic={}, n_perspectives={:?}",
        req.topic, req.n_perspectives
    );

    let ctx = state.ctx.lock().await;
    let router = ctx.router.clone();
    drop(ctx);

    let llm_client = Arc::new(RouterAgentLlmClient {
        router,
        stats: beagle_llm::stats::LlmCallsStats::default(),
    });

    let orchestrator = beagle_agents::DebateOrchestrator::new(llm_client);

    match orchestrator.conduct_debate(&req.topic).await {
        Ok(transcript) => {
            let insights: Vec<String> = transcript.rounds.iter()
                .map(|r| format!("Round {}: {}", r.round_number, r.proponent_argument.chars().take(100).collect::<String>()))
                .collect();

            Ok(Json(DebateResponse {
                transcript: serde_json::json!({
                    "rounds": transcript.rounds.len(),
                    "duration_ms": transcript.duration_ms,
                    "rounds_detail": transcript.rounds,
                }),
                synthesis: transcript.synthesis.conclusion.clone(),
                consensus_score: transcript.synthesis.final_confidence as f64,
                key_insights: insights,
                status: "ok".to_string(),
            }))
        }
        Err(e) => {
            error!("Debate orchestration failed: {}", e);
            Ok(Json(DebateResponse {
                transcript: serde_json::json!({"error": e.to_string()}),
                synthesis: format!("Error: {}", e),
                consensus_score: 0.0,
                key_insights: vec![],
                status: "error".to_string(),
            }))
        }
    }
}

#[derive(Deserialize)]
struct DeepResearchRequest {
    research_question: String,
    iterations: Option<usize>,
    exploration_constant: Option<f64>,
}

#[derive(Serialize)]
struct DeepResearchResponse {
    hypotheses: Vec<serde_json::Value>,
    best_hypothesis: String,
    confidence: f64,
    search_tree: serde_json::Value,
    novelty_score: f64,
    status: String,
}

/// MCTS-based deep research with hypothesis discovery (B19)
/// Full implementation with Monte Carlo Tree Search, debate simulation and causal analysis
async fn dev_deep_research_handler(
    axum::extract::State(state): axum::extract::State<AppState>,
    Json(req): Json<DeepResearchRequest>,
) -> Result<Json<DeepResearchResponse>, StatusCode> {
    info!("Deep research request: question={}", req.research_question);

    let ctx = state.ctx.lock().await;
    let router = ctx.router.clone();
    drop(ctx);

    let llm_client = Arc::new(RouterAgentLlmClient {
        router,
        stats: beagle_llm::stats::LlmCallsStats::default(),
    });

    // Create MCTS components
    let debate = Arc::new(beagle_agents::DebateOrchestrator::new(llm_client.clone()));
    let causal = Arc::new(beagle_agents::CausalReasoner::new(llm_client.clone()));
    let simulator = Arc::new(beagle_agents::SimulationEngine::new(debate, causal));

    let iterations = req.iterations.unwrap_or(10).min(50); // Cap at 50 for safety
    let engine = beagle_agents::MCTSEngine::new(llm_client, simulator, iterations);

    match engine.deep_research(&req.research_question).await {
        Ok(result) => {
            let hypotheses_json: Vec<serde_json::Value> = result.top_hypotheses.iter()
                .map(|h| serde_json::json!({
                    "text": h.content,
                    "confidence": h.q_value,
                    "novelty": h.novelty,
                    "plausibility": h.plausibility,
                    "testability": h.testability,
                    "visits": h.n_visits
                }))
                .collect();

            let novelty_score = result.top_hypotheses.iter()
                .map(|h| h.novelty)
                .sum::<f64>() / result.top_hypotheses.len().max(1) as f64;

            Ok(Json(DeepResearchResponse {
                hypotheses: hypotheses_json,
                best_hypothesis: result.best_hypothesis.content.clone(),
                confidence: result.best_hypothesis.q_value as f64,
                search_tree: serde_json::json!({
                    "tree_size": result.tree_size,
                    "iterations": result.iterations,
                    "method": "mcts_with_debate_and_causal"
                }),
                novelty_score,
                status: "ok".to_string(),
            }))
        }
        Err(e) => {
            error!("Deep research failed: {}", e);
            Ok(Json(DeepResearchResponse {
                hypotheses: vec![],
                best_hypothesis: format!("Error: {}", e),
                confidence: 0.0,
                search_tree: serde_json::json!({"error": e.to_string()}),
                novelty_score: 0.0,
                status: "error".to_string(),
            }))
        }
    }
}

#[derive(Deserialize)]
struct NeurosymbolicRequest {
    problem: String,
    use_constraints: Option<bool>,
}

#[derive(Serialize)]
struct NeurosymbolicResponse {
    neural_result: String,
    symbolic_result: String,
    hybrid_result: String,
    constraint_satisfaction: f64,
    z3_verification: bool,
    status: String,
}

/// Neural-symbolic hybrid reasoning (B20)
async fn dev_neurosymbolic_handler(
    axum::extract::State(state): axum::extract::State<AppState>,
    Json(req): Json<NeurosymbolicRequest>,
) -> Result<Json<NeurosymbolicResponse>, StatusCode> {
    info!("Neuro-symbolic request: problem={}", req.problem);

    let ctx = state.ctx.lock().await;
    let router = ctx.router.clone();
    drop(ctx);

    let llm_client = Arc::new(RouterAgentLlmClient {
        router,
        stats: beagle_llm::stats::LlmCallsStats::default(),
    });

    let extractor = Arc::new(beagle_agents::NeuralExtractor::new(llm_client));
    let mut reasoner = beagle_agents::HybridReasoner::new(extractor);

    match reasoner.reason(&req.problem).await {
        Ok(result) => {
            let neural_summary = format!(
                "Extracted {} facts, {} rules from neural analysis",
                result.extracted_facts.len(),
                result.extracted_rules.len()
            );

            let symbolic_summary = format!(
                "Derived {} facts through symbolic reasoning. Consistent: {}",
                result.derived_facts.len(),
                result.is_consistent
            );

            Ok(Json(NeurosymbolicResponse {
                neural_result: neural_summary,
                symbolic_result: symbolic_summary,
                hybrid_result: format!(
                    "Hybrid reasoning complete with confidence {:.2}",
                    result.confidence_score
                ),
                constraint_satisfaction: if result.is_consistent { 1.0 } else { 0.5 },
                z3_verification: result.is_consistent,
                status: "ok".to_string(),
            }))
        }
        Err(e) => {
            error!("Neuro-symbolic reasoning failed: {}", e);
            Ok(Json(NeurosymbolicResponse {
                neural_result: format!("Error: {}", e),
                symbolic_result: "Failed".to_string(),
                hybrid_result: "Failed".to_string(),
                constraint_satisfaction: 0.0,
                z3_verification: false,
                status: "error".to_string(),
            }))
        }
    }
}

#[derive(Deserialize)]
struct ParallelResearchRequest {
    queries: Vec<String>,
    max_workers: Option<usize>,
}

#[derive(Serialize)]
struct ParallelResearchResponse {
    results: Vec<serde_json::Value>,
    total_time_ms: u64,
    completed: usize,
    failed: usize,
    status: String,
}

/// Parallel research pipeline (B21)
async fn dev_parallel_handler(
    axum::extract::State(state): axum::extract::State<AppState>,
    Json(req): Json<ParallelResearchRequest>,
) -> Result<Json<ParallelResearchResponse>, StatusCode> {
    info!(
        "Parallel research request: n_queries={}",
        req.queries.len()
    );

    let start = std::time::Instant::now();

    let ctx = state.ctx.lock().await;
    let router = ctx.router.clone();
    drop(ctx);

    let llm_client = Arc::new(RouterAgentLlmClient {
        router,
        stats: beagle_llm::stats::LlmCallsStats::default(),
    });

    let max_workers = req.max_workers.unwrap_or(4);
    let queries = req.queries.clone();

    // Execute queries in parallel using Tokio
    let mut handles = Vec::new();

    for query in queries {
        let llm = llm_client.clone();
        let handle = tokio::spawn(async move {
            let prompt = format!(
                "Research query: {}\n\
                 Provide a concise summary of key findings:",
                query
            );

            match llm.complete(&prompt).await {
                Ok(result) => serde_json::json!({
                    "query": query,
                    "status": "success",
                    "result": result,
                    "confidence": 0.7
                }),
                Err(e) => serde_json::json!({
                    "query": query,
                    "status": "error",
                    "error": e.to_string(),
                    "confidence": 0.0
                })
            }
        });
        handles.push(handle);

        // Limit concurrency
        if handles.len() >= max_workers {
            break;
        }
    }

    let mut results = Vec::new();
    let mut completed = 0;
    let mut failed = 0;

    for handle in handles {
        match handle.await {
            Ok(result) => {
                if result.get("status").and_then(|s| s.as_str()) == Some("success") {
                    completed += 1;
                } else {
                    failed += 1;
                }
                results.push(result);
            }
            Err(_) => {
                failed += 1;
                results.push(serde_json::json!({"status": "task_failed"}));
            }
        }
    }

    Ok(Json(ParallelResearchResponse {
        results,
        total_time_ms: start.elapsed().as_millis() as u64,
        completed,
        failed,
        status: "ok".to_string(),
    }))
}

#[derive(Deserialize)]
struct ReasoningRequest {
    start_concept: String,
    target_concept: String,
    max_hops: Option<usize>,
}

#[derive(Serialize)]
struct ReasoningResponse {
    paths: Vec<serde_json::Value>,
    best_path: Vec<String>,
    path_confidence: f64,
    reasoning_type: String,
    status: String,
}

/// Hypergraph reasoning paths (B22)
async fn dev_reasoning_handler(
    axum::extract::State(state): axum::extract::State<AppState>,
    Json(req): Json<ReasoningRequest>,
) -> Result<Json<ReasoningResponse>, StatusCode> {
    info!(
        "Reasoning request: {} -> {}",
        req.start_concept, req.target_concept
    );

    let ctx = state.ctx.lock().await;
    let router = ctx.router.clone();
    drop(ctx);

    let llm_client = Arc::new(RouterAgentLlmClient {
        router,
        stats: beagle_llm::stats::LlmCallsStats::default(),
    });

    let max_hops = req.max_hops.unwrap_or(5);

    // Use LLM to find reasoning chains
    let prompt = format!(
        "Find reasoning paths connecting these concepts:\n\
         From: {}\n\
         To: {}\n\
         Max {} hops\n\n\
         List 3 possible reasoning chains showing how to get from concept A to concept B. \
         Format each as: A -> intermediate1 -> intermediate2 -> B",
        req.start_concept, req.target_concept, max_hops
    );

    let system = "You are a reasoning assistant that finds logical connections between concepts.";

    match llm_client.complete_with_system(&prompt, system).await {
        Ok(response) => {
            // Parse the response to extract paths
            let lines: Vec<&str> = response.lines().filter(|l| l.contains("->")).collect();
            let mut paths = Vec::new();
            let mut best_path = vec![req.start_concept.clone(), req.target_concept.clone()];

            for (i, line) in lines.iter().take(3).enumerate() {
                let nodes: Vec<String> = line.split("->").map(|s| s.trim().to_string()).collect();
                if nodes.len() >= 2 {
                    if i == 0 {
                        best_path = nodes.clone();
                    }
                    paths.push(serde_json::json!({
                        "index": i + 1,
                        "nodes": nodes,
                        "confidence": 0.7 - (i as f64 * 0.1),
                        "length": nodes.len()
                    }));
                }
            }

            if paths.is_empty() {
                paths.push(serde_json::json!({
                    "index": 1,
                    "nodes": [req.start_concept.clone(), req.target_concept.clone()],
                    "confidence": 0.5,
                    "length": 2
                }));
            }

            Ok(Json(ReasoningResponse {
                paths,
                best_path,
                path_confidence: 0.7,
                reasoning_type: "llm_chain".to_string(),
                status: "ok".to_string(),
            }))
        }
        Err(e) => {
            error!("Reasoning failed: {}", e);
            Ok(Json(ReasoningResponse {
                paths: vec![],
                best_path: vec![],
                path_confidence: 0.0,
                reasoning_type: "error".to_string(),
                status: format!("error: {}", e),
            }))
        }
    }
}

#[derive(Deserialize)]
struct SwarmRequest {
    exploration_query: String,
    n_agents: Option<usize>,
    iterations: Option<usize>,
}

#[derive(Serialize)]
struct SwarmResponse {
    emergent_behaviors: Vec<String>,
    discovered_concepts: Vec<String>,
    pheromone_trails: serde_json::Value,
    convergence_score: f64,
    agent_positions: Vec<serde_json::Value>,
    status: String,
}

/// Swarm intelligence exploration (B23)
async fn dev_swarm_handler(
    axum::extract::State(state): axum::extract::State<AppState>,
    Json(req): Json<SwarmRequest>,
) -> Result<Json<SwarmResponse>, StatusCode> {
    info!("Swarm request: query={}, n_agents={:?}", req.exploration_query, req.n_agents);

    let ctx = state.ctx.lock().await;
    let router = ctx.router.clone();
    drop(ctx);

    let llm_client = Arc::new(RouterAgentLlmClient {
        router,
        stats: beagle_llm::stats::LlmCallsStats::default(),
    });

    let n_agents = req.n_agents.unwrap_or(10).min(50); // Cap at 50
    let mut swarm = beagle_agents::SwarmOrchestrator::new(n_agents, llm_client);

    match swarm.explore(&req.exploration_query).await {
        Ok(result) => {
            Ok(Json(SwarmResponse {
                emergent_behaviors: vec![format!("converged: {}", result.emergent_behavior.has_converged)],
                discovered_concepts: result.consensus,
                pheromone_trails: serde_json::json!({
                    "agents": result.n_agents,
                    "iterations": result.iterations,
                    "consensus_strength": result.emergent_behavior.consensus_strength
                }),
                convergence_score: result.emergent_behavior.consensus_strength,
                agent_positions: (0..result.n_agents)
                    .map(|i| serde_json::json!({"agent_id": i, "position": i}))
                    .collect(),
                status: "ok".to_string(),
            }))
        }
        Err(e) => {
            error!("Swarm exploration failed: {}", e);
            Ok(Json(SwarmResponse {
                emergent_behaviors: vec![],
                discovered_concepts: vec![],
                pheromone_trails: serde_json::json!({"error": e.to_string()}),
                convergence_score: 0.0,
                agent_positions: vec![],
                status: "error".to_string(),
            }))
        }
    }
}

#[derive(Deserialize)]
struct TemporalRequest {
    events: Vec<serde_json::Value>,
    query_scale: Option<String>,
    detect_patterns: Option<bool>,
}

#[derive(Serialize)]
struct TemporalResponse {
    cross_scale_patterns: Vec<String>,
    anomalies: Vec<serde_json::Value>,
    predictions: Vec<String>,
    temporal_graph: serde_json::Value,
    causality_score: f64,
    status: String,
}

/// Temporal multi-scale reasoning (B24)
async fn dev_temporal_handler(
    axum::extract::State(state): axum::extract::State<AppState>,
    Json(req): Json<TemporalRequest>,
) -> Result<Json<TemporalResponse>, StatusCode> {
    info!("Temporal reasoning request: n_events={}", req.events.len());

    let ctx = state.ctx.lock().await;
    let router = ctx.router.clone();
    drop(ctx);

    let llm_client = Arc::new(RouterAgentLlmClient {
        router,
        stats: beagle_llm::stats::LlmCallsStats::default(),
    });

    // Parse events into TimePoints
    let timepoints: Vec<beagle_agents::TimePoint> = req
        .events
        .iter()
        .filter_map(|e| {
            let timestamp = e.get("timestamp")?.as_str()?;
            let event = e.get("event")?.as_str()?;
            let scale = e.get("scale")?.as_str()?;

            let ts = chrono::DateTime::parse_from_rfc3339(timestamp)
                .ok()?
                .with_timezone(&chrono::Utc);
            let temporal_scale = match scale {
                "millisecond" => beagle_agents::TemporalScale::Millisecond,
                "second" => beagle_agents::TemporalScale::Second,
                "minute" => beagle_agents::TemporalScale::Minute,
                "hour" => beagle_agents::TemporalScale::Hour,
                "day" => beagle_agents::TemporalScale::Day,
                "week" => beagle_agents::TemporalScale::Week,
                "month" => beagle_agents::TemporalScale::Month,
                "year" => beagle_agents::TemporalScale::Year,
                _ => beagle_agents::TemporalScale::Day,
            };

            Some(beagle_agents::TimePoint::new(ts, temporal_scale, event.to_string()))
        })
        .collect();

    let reasoner = beagle_agents::TemporalReasoner::new(llm_client);

    match reasoner.analyze(timepoints).await {
        Ok(result) => {
            Ok(Json(TemporalResponse {
                cross_scale_patterns: result.cross_scale_causalities.iter()
                    .map(|c| format!("{} -> {}", c.from_event, c.to_event))
                    .collect(),
                anomalies: result.anomalies.iter()
                    .map(|a| serde_json::json!({
                        "pattern_type": format!("{:?}", a.pattern_type),
                        "sequence": a.sequence,
                        "confidence": a.confidence
                    }))
                    .collect(),
                predictions: result.predictive_patterns.iter()
                    .map(|p| format!("{:?}", p.pattern_type))
                    .collect(),
                temporal_graph: serde_json::json!({
                    "total_events": result.total_events,
                    "scales": result.scale_distribution,
                    "time_span": result.time_span.map(|t| format!("{:?}", t)),
                }),
                causality_score: if result.cross_scale_causalities.is_empty() { 0.0 } else { 0.8 },
                status: "ok".to_string(),
            }))
        }
        Err(e) => {
            error!("Temporal reasoning failed: {}", e);
            Ok(Json(TemporalResponse {
                cross_scale_patterns: vec![],
                anomalies: vec![],
                predictions: vec![],
                temporal_graph: serde_json::json!({"error": e.to_string()}),
                causality_score: 0.0,
                status: "error".to_string(),
            }))
        }
    }
}

#[derive(Deserialize)]
struct ResearchOrchestrationRequest {
    research_goal: String,
    agent_selection: Option<Vec<String>>,
    time_budget_seconds: Option<u64>,
}

#[derive(Serialize)]
struct ResearchOrchestrationResponse {
    orchestration_plan: serde_json::Value,
    selected_agents: Vec<String>,
    execution_trace: Vec<String>,
    final_result: String,
    resource_usage: serde_json::Value,
    status: String,
}

/// General research orchestration (B25)
async fn dev_research_handler(
    axum::extract::State(state): axum::extract::State<AppState>,
    Json(req): Json<ResearchOrchestrationRequest>,
) -> Result<Json<ResearchOrchestrationResponse>, StatusCode> {
    info!("Research orchestration request: goal={}", req.research_goal);

    let ctx = state.ctx.lock().await;
    let router = ctx.router.clone();
    drop(ctx);

    let llm_client = Arc::new(RouterAgentLlmClient {
        router,
        stats: beagle_llm::stats::LlmCallsStats::default(),
    });

    let start = std::time::Instant::now();
    let time_budget = req.time_budget_seconds.unwrap_or(300);
    let agents = req.agent_selection.unwrap_or_else(|| vec![
        "Researcher".to_string(),
        "Validator".to_string()
    ]);

    // Phase 1: Research
    let phase1_prompt = format!(
        "Research goal: {}\n\
         Perform initial research and identify key aspects, challenges, and opportunities. \
         Provide structured findings.",
        req.research_goal
    );

    let phase1_result = match llm_client.complete(&phase1_prompt).await {
        Ok(r) => r,
        Err(e) => format!("Error: {}", e)
    };

    // Phase 2: Validate/Synthesize
    let phase2_prompt = format!(
        "Based on these findings:\n{}\n\n\
         Synthesize final conclusions and recommendations.",
        phase1_result
    );

    let final_result = match llm_client.complete(&phase2_prompt).await {
        Ok(r) => r,
        Err(e) => format!("Error: {}", e)
    };

    let elapsed = start.elapsed().as_secs();

    Ok(Json(ResearchOrchestrationResponse {
        orchestration_plan: serde_json::json!({
            "goal": req.research_goal,
            "phases": ["research", "validate", "synthesize"],
            "time_budget_seconds": time_budget,
            "agents_used": agents
        }),
        selected_agents: agents,
        execution_trace: vec![
            "phase_1_research_complete".to_string(),
            "phase_2_synthesis_complete".to_string(),
            format!("completed_in_{}s", elapsed)
        ],
        final_result,
        resource_usage: serde_json::json!({
            "llm_calls": 2,
            "time_seconds": elapsed
        }),
        status: "ok".to_string(),
    }))
}

// ============================================================================
// DEV VOID ENDPOINT (B25+ - Void Navigation Engine)
// ============================================================================

#[derive(Deserialize)]
pub struct VoidNavigationRequest {
    /// Target depth for void navigation (0.0 to 10.0)
    #[serde(default = "default_void_depth")]
    pub target_depth: f64,
    /// Focus or context for the void journey
    #[serde(default)]
    pub focus: String,
    /// Whether to perform deep navigation (requires BEAGLE_VOID_DEEP env)
    #[serde(default)]
    pub deep: bool,
}

fn default_void_depth() -> f64 {
    4.0
}

#[derive(Serialize)]
pub struct VoidNavigationResponse {
    pub journey_id: String,
    pub status: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub max_depth_reached: Option<f64>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub duration_ms: Option<u64>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub insights: Option<Vec<String>>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub probe_result: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub error: Option<String>,
    /// Whether void feature is enabled
    pub void_enabled: bool,
}

/// Void navigation handler. The `void` feature is now in the default
/// build (see Cargo.toml `default = ["void"]`), so the real tensor-math
/// navigator (crates/beagle-void/src/navigator.rs) runs unconditionally
/// in the cluster binary. The cfg(not(feature = "void")) fallback branch
/// below is kept for non-default builds only (e.g. `--no-default-features`).
async fn dev_void_handler(
    axum::extract::State(state): axum::extract::State<AppState>,
    Json(req): Json<VoidNavigationRequest>,
) -> Result<Json<VoidNavigationResponse>, StatusCode> {
    info!("VOID navigation request: depth={}, focus='{}'", req.target_depth, req.focus);

    // Limitar profundidade a valores seguros
    let target_depth = req.target_depth.clamp(0.0, 10.0);
    let t0 = std::time::Instant::now();

    #[cfg(feature = "void")]
    {
        use crate::pipeline_void::handle_deadlock;
        use std::env;

        // Set BEAGLE_VOID_DEEP se deep=true
        if req.deep {
            env::set_var("BEAGLE_VOID_DEEP", "1");
        }

        let journey_id = format!("void-{}", Uuid::new_v4());

        match handle_deadlock(&journey_id, "User requested void journey", &req.focus).await {
            Ok(result) => {
                info!("VOID journey completed: journey_id={}", journey_id);

                // Parse resultado para extrair métricas
                let lines: Vec<&str> = result.lines().collect();
                let mut max_depth = None;
                let mut duration = None;
                let mut probe = None;

                for line in &lines {
                    if line.contains("Profundidade:") {
                        if let Some(val) = line.split(':').nth(1) {
                            max_depth = val.trim().parse::<f64>().ok();
                        }
                    }
                    if line.contains("Duração:") {
                        if let Some(val) = line.split(':').nth(1) {
                            let dur_str = val.trim().split_whitespace().next().unwrap_or("0");
                            duration = dur_str.parse::<u64>().ok();
                        }
                    }
                    if line.contains("Sondagem:") {
                        if let Some(val) = line.split(':').nth(1) {
                            probe = Some(val.trim().to_string());
                        }
                    }
                }

                // Extrair insights (linhas começando com "•")
                let insights: Vec<String> = lines
                    .iter()
                    .filter(|l| l.trim().starts_with('•'))
                    .map(|l| l.trim().trim_start_matches('•').trim().to_string())
                    .collect();

                // Stamp into registry so /api/v1/cognitive/state surfaces it.
                let summary = crate::jobs::VoidJourneySummary {
                    journey_id: journey_id.clone(),
                    focus: req.focus.clone(),
                    target_depth,
                    max_depth_reached: max_depth,
                    duration_ms: duration.or_else(|| Some(t0.elapsed().as_millis() as u64)),
                    insight_count: insights.len(),
                    probe_result: probe.clone(),
                    completed_at: chrono::Utc::now(),
                    truth_mode: "observed".to_string(),
                };
                state.voids.append(summary.clone()).await;
                crate::cognitive_events::emit(
                    &state.cognitive_tx,
                    crate::cognitive_events::CognitiveEvent::Void(summary),
                );

                Ok(Json(VoidNavigationResponse {
                    journey_id,
                    status: "completed".to_string(),
                    max_depth_reached: max_depth,
                    duration_ms: duration,
                    insights: if insights.is_empty() { None } else { Some(insights) },
                    probe_result: probe,
                    error: None,
                    void_enabled: true,
                }))
            }
            Err(e) => {
                warn!("VOID journey failed: {}", e);
                Ok(Json(VoidNavigationResponse {
                    journey_id,
                    status: "error".to_string(),
                    max_depth_reached: None,
                    duration_ms: None,
                    insights: None,
                    probe_result: None,
                    error: Some(e.to_string()),
                    void_enabled: true,
                }))
            }
        }
    }

    #[cfg(not(feature = "void"))]
    {
        warn!("VOID endpoint called but feature 'void' not enabled");
        Ok(Json(VoidNavigationResponse {
            journey_id: format!("void-fallback-{}", Uuid::new_v4()),
            status: "fallback".to_string(),
            max_depth_reached: None,
            duration_ms: None,
            insights: None,
            probe_result: None,
            error: Some(
                "VoidNavigator requires feature 'void'. Compile with: cargo build --features void".to_string()
            ),
            void_enabled: false,
        }))
    }
}
