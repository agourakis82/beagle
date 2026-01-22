use crate::auth::api_token_auth;
use crate::{
    run_beagle_pipeline, ExperimentFlags, RunState, RunStatus, ScienceJobKind, ScienceJobRegistry,
    ScienceJobState, ScienceJobStatus,
};
use axum::http::StatusCode;
use axum::{
    body::Bytes,
    extract::Path,
    http::HeaderMap,
    middleware,
    routing::{get, post},
    response::Response,
    Json, Router,
};
use beagle_config::{beagle_data_dir, classify_hrv};
use beagle_core::BeagleContext;
use beagle_exocortex::{ExocortexConfig, ExocortexInput, InputModality, PersonalExocortex};
use beagle_feedback::{append_event, create_triad_event};
use beagle_llm::{EmbeddingClient, ProviderTier, RequestMeta};
use beagle_observer::UniversalObserver;
use beagle_search::{ArxivClient, PubMedClient, SearchClient, SearchQuery};
use beagle_triad::{run_triad, TriadInput};
use chrono::TimeZone;
use serde::{Deserialize, Serialize};
use std::path::PathBuf;
use std::sync::Arc;
use tokio::sync::Mutex;
use tracing::{error, info, warn};
use uuid::Uuid;
use {
    beagle_rag_update::github::GitHubClient,
    beagle_rag_update::indexer::{run_incremental, IndexerConfig, RepoTarget},
    beagle_rag_update::ledger::IngestionLedger,
    beagle_rag_update::repo_targets::load_repo_targets_file,
    hmac::{Hmac, Mac},
    sha2::Sha256,
    std::collections::HashSet,
};

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

#[derive(Debug, Deserialize)]
struct ExocortexProcessRequest {
    user_id: String,
    query: String,
    #[serde(default)]
    intent: Option<String>,
    #[serde(default)]
    context: Option<String>,
    #[serde(default)]
    urgency: Option<f32>,
    #[serde(default)]
    modality: Option<InputModality>,
    #[serde(default)]
    config: Option<ExocortexConfig>,
}

#[derive(Serialize)]
struct ExocortexProcessResponse {
    status: String,
    output: beagle_exocortex::ExocortexOutput,
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

use crate::jobs::{DarwinJobKind, DarwinJobRegistry, DarwinJobState, DarwinJobStatus, JobRegistry};

#[derive(Clone)]
pub struct AppState {
    pub ctx: Arc<Mutex<BeagleContext>>,
    pub jobs: Arc<JobRegistry>,
    pub science_jobs: Arc<ScienceJobRegistry>,
    pub darwin_jobs: Arc<DarwinJobRegistry>,
    pub observer: Arc<UniversalObserver>,
}

pub fn build_router(state: AppState) -> Router {
    // Rotas protegidas (requerem autenticação via Bearer token)
    let protected_routes = Router::new()
        .route("/api/llm/complete", post(llm_complete_handler))
        .route("/api/pipeline/start", post(pipeline_start_handler))
        .route("/api/pipeline/status/:run_id", get(pipeline_status_handler))
        .route("/api/run/:run_id/artifacts", get(run_artifacts_handler))
        .route("/api/runs/recent", get(runs_recent_handler))
        .route("/api/hrv", post(hrv_compat_handler))
        .route("/api/voice/tts", post(voice_tts_handler))
        .route("/api/observer/physio", post(observer_physio_handler))
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
        .route("/api/jobs/darwin/start", post(darwin_job_start_handler))
        .route("/api/jobs/darwin/status/:job_id", get(darwin_job_status_handler))
        .route("/api/jobs/darwin/recent", get(darwin_jobs_recent_handler))
        .route(
            "/api/jobs/darwin/:job_id/artifacts",
            get(darwin_job_artifacts_handler),
        )
        .merge(crate::http_memory::memory_routes())
        .route("/api/exocortex/process", post(exocortex_process_handler))
        .route("/api/pcs/reason", post(pcs_reason_handler))
        .route("/api/fractal/grow", post(fractal_grow_handler))
        .route("/api/worldmodel/predict", post(worldmodel_predict_handler))
        .route(
            "/api/serendipity/discover",
            post(serendipity_discover_handler),
        )
        .route("/api/serendipity/toggle", post(serendipity_toggle_handler))
        .route("/api/serendipity/perturb", post(serendipity_perturb_handler))
        .route("/api/void/toggle", post(void_toggle_handler))
        .route("/api/void/break_loop", post(void_break_loop_handler))
        .route("/api/search/pubmed", post(search_pubmed_handler))
        .route("/api/search/arxiv", post(search_arxiv_handler))
        .route("/api/search/all", post(search_all_handler))
        .route_layer(middleware::from_fn_with_state(
            state.clone(),
            api_token_auth,
        ));

    // Rotas públicas (sem autenticação - para health checks e monitoring)
    let public_routes = Router::new()
        .route("/health", get(health_handler))
        .route("/webhooks/github/push", post(github_push_webhook_handler));

    // Combina rotas protegidas e públicas
    Router::new()
        .merge(protected_routes)
        .merge(public_routes)
        .with_state(state)
}

#[derive(Debug, Deserialize)]
struct VoiceTtsRequest {
    text: String,
    #[serde(default)]
    language: Option<String>,
    #[serde(default)]
    voice: Option<String>,
    #[serde(default)]
    rate_wpm: Option<u32>,
    #[serde(default)]
    use_hrv_rate: Option<bool>,
}

fn detect_espeak_command() -> Option<&'static str> {
    if std::process::Command::new("espeak-ng")
        .arg("--version")
        .output()
        .is_ok()
    {
        return Some("espeak-ng");
    }
    if std::process::Command::new("espeak")
        .arg("--version")
        .output()
        .is_ok()
    {
        return Some("espeak");
    }
    None
}

fn normalize_language_to_espeak_voice(language: &str) -> String {
    let lower = language.trim().to_lowercase();

    // Common mappings
    if lower == "pt" || lower.starts_with("pt-") || lower.starts_with("pt_") {
        return "pt-br".to_string();
    }
    if lower == "en" || lower.starts_with("en-") || lower.starts_with("en_") {
        return "en-us".to_string();
    }

    // espeak typically accepts language tags like "es", "fr", "de", "it", etc.
    lower
}

fn compute_tts_rate_wpm(default_rate_wpm: u32, hrv_level: Option<&str>) -> u32 {
    let base = match hrv_level {
        Some("low") => 135,
        Some("high") => 175,
        Some("normal") | None | Some(_) => default_rate_wpm,
    };
    base.clamp(80, 300)
}

fn synthesize_wav_with_espeak(
    espeak_cmd: &str,
    voice: &str,
    rate_wpm: u32,
    text: &str,
) -> std::io::Result<Vec<u8>> {
    use std::io::Write;
    use std::process::{Command, Stdio};

    let mut child = Command::new(espeak_cmd)
        .args([
            "--stdout",
            "--stdin",
            "-v",
            voice,
            "-s",
            &rate_wpm.to_string(),
        ])
        .stdin(Stdio::piped())
        .stdout(Stdio::piped())
        .stderr(Stdio::piped())
        .spawn()?;

    if let Some(mut stdin) = child.stdin.take() {
        stdin.write_all(text.as_bytes())?;
    }

    let output = child.wait_with_output()?;
    if output.status.success() {
        return Ok(output.stdout);
    }

    let stderr = String::from_utf8_lossy(&output.stderr);
    Err(std::io::Error::new(
        std::io::ErrorKind::Other,
        format!("espeak failed: {stderr}"),
    ))
}

async fn voice_tts_handler(
    axum::extract::State(state): axum::extract::State<AppState>,
    Json(req): Json<VoiceTtsRequest>,
) -> Result<Response, StatusCode> {
    if req.text.trim().is_empty() {
        return Err(StatusCode::BAD_REQUEST);
    }
    if req.text.len() > 20_000 {
        return Err(StatusCode::PAYLOAD_TOO_LARGE);
    }

    let Some(espeak_cmd) = detect_espeak_command() else {
        warn!("TTS requested but neither espeak-ng nor espeak is available");
        return Err(StatusCode::SERVICE_UNAVAILABLE);
    };

    let language = req.language.unwrap_or_else(|| "pt-BR".to_string());
    let voice = req
        .voice
        .unwrap_or_else(|| normalize_language_to_espeak_voice(&language));

    let use_hrv_rate = req.use_hrv_rate.unwrap_or(true);
    let default_rate_wpm = req.rate_wpm.unwrap_or(155).clamp(80, 300);
    let hrv_level = if use_hrv_rate {
        state
            .observer
            .current_user_context()
            .await
            .physio
            .hrv_level
    } else {
        None
    };
    let rate_wpm = compute_tts_rate_wpm(default_rate_wpm, hrv_level.as_deref());

    let text = req.text.clone();
    let wav_bytes = tokio::time::timeout(
        std::time::Duration::from_secs(20),
        tokio::task::spawn_blocking(move || {
            synthesize_wav_with_espeak(espeak_cmd, &voice, rate_wpm, &text)
        }),
    )
    .await
    .map_err(|_| StatusCode::REQUEST_TIMEOUT)?
    .map_err(|_| StatusCode::INTERNAL_SERVER_ERROR)?
    .map_err(|e| {
        warn!("TTS synthesis failed: {}", e);
        StatusCode::BAD_GATEWAY
    })?;

    let mut response = Response::new(axum::body::Body::from(wav_bytes));
    response.headers_mut().insert(
        axum::http::header::CONTENT_TYPE,
        axum::http::HeaderValue::from_static("audio/wav"),
    );
    response.headers_mut().insert(
        axum::http::header::CACHE_CONTROL,
        axum::http::HeaderValue::from_static("no-store"),
    );
    Ok(response)
}

#[derive(Debug, Deserialize)]
struct HrvCompatRequest {
    hrv: f64,
    state: String,
    timestamp: f64,
}

#[derive(Debug, Serialize)]
struct HrvCompatResponse {
    status: String,
    hrv_level: String,
    speed_multiplier: f64,
}

async fn hrv_compat_handler(
    axum::extract::State(state): axum::extract::State<AppState>,
    Json(payload): Json<HrvCompatRequest>,
) -> Result<Json<HrvCompatResponse>, StatusCode> {
    let hrv_level = classify_hrv(payload.hrv as f32, None);

    // Convert unix timestamp (seconds, float) to RFC3339 for storage.
    let seconds = payload.timestamp.trunc() as i64;
    let nanos = (payload.timestamp.fract().abs() * 1_000_000_000.0) as u32;
    let timestamp = chrono::Utc
        .timestamp_opt(seconds, nanos)
        .single()
        .unwrap_or_else(chrono::Utc::now);

    let event = beagle_observer::PhysioEvent {
        timestamp,
        source: "ios_healthkit".to_string(),
        session_id: None,
        hrv_ms: Some(payload.hrv),
        heart_rate_bpm: None,
        spo2_percent: None,
        resp_rate_bpm: None,
        skin_temp_c: None,
        body_temp_c: None,
        steps: None,
        energy_burned_kcal: None,
        vo2max_ml_kg_min: None,
        event_type: None,
        hrv_level: Some(hrv_level.clone()),
        stress_index: None,
        coherence_score: None,
        metadata: std::collections::HashMap::new(),
    };

    let _ = state
        .observer
        .record_physio_event(event, None)
        .await
        .map_err(|_| StatusCode::INTERNAL_SERVER_ERROR)?;

    // Maintain compatibility with the older beagle-server endpoint semantics.
    let _ = beagle_physio::integrate_physio_metrics(payload.hrv, 0.0, 0.0)
        .await
        .map_err(|_| StatusCode::INTERNAL_SERVER_ERROR)?;

    let hrv_cfg = beagle_config::HrvControlConfig::from_env();
    let speed_multiplier =
        beagle_config::compute_gain_from_hrv(payload.hrv as f32, Some(hrv_cfg)) as f64;
    beagle_physio::speed_control::set_global_speed_multiplier(speed_multiplier);

    if payload.state.eq_ignore_ascii_case("FLOW") {
        info!(
            "📊 HRV compat: FLOW — hrv={:.1}ms, multiplier={:.2}x",
            payload.hrv, speed_multiplier
        );
    } else if payload.state.eq_ignore_ascii_case("STRESS") {
        warn!(
            "📊 HRV compat: STRESS — hrv={:.1}ms, multiplier={:.2}x",
            payload.hrv, speed_multiplier
        );
    } else {
        info!(
            "📊 HRV compat: {} — hrv={:.1}ms, multiplier={:.2}x",
            payload.state, payload.hrv, speed_multiplier
        );
    }

    Ok(Json(HrvCompatResponse {
        status: "ok".to_string(),
        hrv_level,
        speed_multiplier,
    }))
}

#[derive(Debug, Deserialize)]
struct GitHubPushEvent {
    repository: GitHubRepo,
}

#[derive(Debug, Deserialize)]
struct GitHubRepo {
    name: String,
    full_name: Option<String>,
    clone_url: Option<String>,
    ssh_url: Option<String>,
}

fn expand_tilde(s: &str) -> std::path::PathBuf {
    if let Some(rest) = s.strip_prefix("~/") {
        if let Some(home) = std::env::var_os("HOME") {
            return std::path::PathBuf::from(home).join(rest);
        }
    }
    std::path::PathBuf::from(s)
}

fn verify_github_signature(headers: &HeaderMap, body: &[u8]) -> Result<(), StatusCode> {
    let secret = std::env::var("GITHUB_WEBHOOK_SECRET")
        .or_else(|_| std::env::var("DARWIN_GITHUB_WEBHOOK_SECRET"))
        .map_err(|_| StatusCode::UNAUTHORIZED)?;

    let sig = headers
        .get("x-hub-signature-256")
        .and_then(|h| h.to_str().ok())
        .ok_or(StatusCode::UNAUTHORIZED)?;

    let expected = sig.strip_prefix("sha256=").ok_or(StatusCode::UNAUTHORIZED)?;
    let expected_bytes = hex::decode(expected).map_err(|_| StatusCode::UNAUTHORIZED)?;

    let mut mac = Hmac::<Sha256>::new_from_slice(secret.as_bytes()).map_err(|_| StatusCode::INTERNAL_SERVER_ERROR)?;
    mac.update(body);
    mac.verify_slice(&expected_bytes)
        .map_err(|_| StatusCode::UNAUTHORIZED)?;
    Ok(())
}

async fn github_push_webhook_handler(
    headers: HeaderMap,
    body: Bytes,
) -> Result<Json<serde_json::Value>, StatusCode> {
    verify_github_signature(&headers, &body)?;

    let event: GitHubPushEvent =
        serde_json::from_slice(&body).map_err(|_| StatusCode::BAD_REQUEST)?;

    let prefer_ssh = std::env::var("DARWIN_GITHUB_WEBHOOK_CLONE_SSH")
        .ok()
        .map(|v| v == "1" || v.eq_ignore_ascii_case("true"))
        .unwrap_or(false);

    let repo = event.repository;
    let repo_name = repo.name;
    let repo_url = if prefer_ssh {
        repo.ssh_url.or(repo.clone_url)
    } else {
        repo.clone_url.or(repo.ssh_url)
    };

    // Use env configuration consistent with the CLI defaults.
    let repos_dir = std::env::var("DARWIN_REPOS_DIR").unwrap_or_else(|_| "~/repos".to_string());
    let state_file = std::env::var("DARWIN_INDEX_STATE_FILE")
        .unwrap_or_else(|_| "~/.darwin_index_state.json".to_string());

    let qdrant_url = std::env::var("QDRANT_URL").unwrap_or_else(|_| "http://localhost:6333".to_string());
    let embedding_url =
        std::env::var("EMBEDDING_URL").unwrap_or_else(|_| "http://localhost:8001/v1".to_string());
    let embedding_model =
        std::env::var("EMBEDDING_MODEL").unwrap_or_else(|_| "NV-Embed-v2".to_string());
    let collection = std::env::var("DARWIN_QDRANT_COLLECTION")
        .unwrap_or_else(|_| "darwin-repos".to_string());
    let error_webhook_url = std::env::var("DARWIN_INDEX_ERROR_WEBHOOK_URL").ok();
    let success_webhook_url = std::env::var("DARWIN_INDEX_SUCCESS_WEBHOOK_URL").ok();

    let extensions: HashSet<String> = [".py", ".rs", ".md", ".txt", ".json", ".yaml", ".yml", ".toml"]
        .into_iter()
        .map(|s| s.to_string())
        .collect();
    let ignore_dirs: HashSet<String> = [
        ".git",
        "node_modules",
        "target",
        "__pycache__",
        ".venv",
        "venv",
    ]
    .into_iter()
    .map(|s| s.to_string())
    .collect();

    let cfg = IndexerConfig {
        repos_dir: expand_tilde(&repos_dir),
        state_file: expand_tilde(&state_file),
        qdrant_url,
        embedding_url,
        embedding_model,
        collection,
        chunk_size: 1500,
        chunk_overlap: 200,
        extensions,
        ignore_dirs,
        max_file_size: 500_000,
        error_webhook_url,
        success_webhook_url,
        ledger: None,
    };

    let repo_path = cfg.repos_dir.join(&repo_name);
    let target = RepoTarget {
        name: repo_name.clone(),
        path: repo_path,
        url: repo_url,
    };

    let ledger_db_url = std::env::var("DARWIN_LEDGER_DATABASE_URL").ok();
    tokio::spawn(async move {
        let mut cfg = cfg;
        if let Some(db_url) = ledger_db_url {
            match IngestionLedger::connect(&db_url).await {
                Ok(ledger) => {
                    if let Err(e) = ledger.ensure_schema().await {
                        warn!("Ledger schema init failed (continuing without ledger): {e:#}");
                    } else {
                        cfg.ledger = Some(ledger);
                    }
                }
                Err(e) => warn!("Ledger connect failed (continuing without ledger): {e:#}"),
            }
        }

        if let Err(e) = run_incremental(&cfg, vec![target], false, true).await {
            error!("GitHub webhook indexing failed: {e:#}");
        }
    });

    Ok(Json(serde_json::json!({
        "status": "accepted",
        "repo": repo_name,
    })))
}

async fn llm_complete_handler(
    axum::extract::State(state): axum::extract::State<AppState>,
    Json(req): Json<LlmRequest>,
) -> Result<Json<LlmResponse>, StatusCode> {
    let ctx = state.ctx.lock().await;

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

    // Execute using the selected client so quotas/limits match the chosen tier.
    let text = client.complete_text(&req.prompt).await.map_err(|e| {
        tracing::error!("LLM error (tier={:?}): {}", tier, e);
        StatusCode::BAD_GATEWAY
    })?;

    // Estimativa de tokens (simplificada: ~4 chars por token)
    let tokens_in_est = req.prompt.len() / 4;
    let tokens_out_est = text.len() / 4;

    // Atualiza stats
    ctx.llm_stats.update(run_id, |stats| {
        match tier {
            ProviderTier::MiniMax => {
                stats.minimax_calls += 1;
                stats.minimax_tokens_in += tokens_in_est as u32;
                stats.minimax_tokens_out += tokens_out_est as u32;
            }
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

    info!(
        tier = ?tier,
        provider = provider_name,
        tokens_in = tokens_in_est,
        tokens_out = tokens_out_est,
        "LLM request completed"
    );

    Ok(Json(LlmResponse {
        text,
        provider: provider_name.to_string(),
        tier: format!("{:?}", tier),
    }))
}

async fn exocortex_process_handler(
    axum::extract::State(state): axum::extract::State<AppState>,
    Json(req): Json<ExocortexProcessRequest>,
) -> Result<Json<ExocortexProcessResponse>, StatusCode> {
    let beagle_ctx_arc = {
        let ctx = state.ctx.lock().await;
        Arc::new(beagle_core::BeagleContext {
            cfg: ctx.cfg.clone(),
            router: ctx.router.clone(),
            llm: ctx.llm.clone(),
            vector: ctx.vector.clone(),
            graph: ctx.graph.clone(),
            llm_stats: ctx.llm_stats.clone(),
            #[cfg(feature = "memory")]
            memory: ctx.memory.clone(),
        })
    };

    let mut config = req.config.unwrap_or_default();
    config.features.enable_observer = true;
    config.features.enable_proactive = false;

    let exocortex = PersonalExocortex::with_context(config, beagle_ctx_arc)
        .await
        .map_err(|e| {
            error!("Exocortex init error: {}", e);
            StatusCode::BAD_GATEWAY
        })?;

    exocortex.load_user(&req.user_id).await.map_err(|e| {
        error!("Exocortex load_user error: {}", e);
        StatusCode::BAD_GATEWAY
    })?;

    // Best-effort physio update from current observer context.
    let user_ctx = state.observer.current_user_context().await;
    let stress = user_ctx.physio.stress_index.unwrap_or(0.3) as f32;
    let energy = (1.0 - stress).clamp(0.0, 1.0);
    let focus = match user_ctx.physio.hrv_level.as_deref() {
        Some("high") => 0.8,
        Some("normal") => 0.5,
        Some("low") => 0.3,
        _ => 0.5,
    };
    exocortex.update_physio_context(stress, energy, focus).await;

    let urgency = req.urgency.unwrap_or(0.6).clamp(0.0, 1.0);
    let input = ExocortexInput {
        query: req.query,
        intent: req.intent,
        modality: req.modality.unwrap_or_default(),
        context: req.context,
        urgency,
    };

    let output = exocortex.process(input).await.map_err(|e| {
        error!("Exocortex process error: {}", e);
        StatusCode::BAD_GATEWAY
    })?;

    Ok(Json(ExocortexProcessResponse {
        status: "ok".to_string(),
        output,
    }))
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

    // Cria run no registry
    let _run_state = state
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
    let _experiment_id = req.experiment_id.clone();

    // Prepara flags experimentais
    let experiment_flags = ExperimentFlags::new(hrv_aware, with_triad);

    // Dispara pipeline em background
    tokio::spawn(async move {
        let mut ctx = ctx_clone.lock().await;

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
                        }
                    }
                } else {
                    jobs_clone
                        .update_status(&run_id_clone, RunStatus::Done)
                        .await;
                }
            }
            Err(e) => {
                error!("Pipeline failed for run {}: {}", run_id_clone, e);
                jobs_clone
                    .set_error(&run_id_clone, format!("Pipeline failed: {}", e))
                    .await;
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

    // Métricas cardiorrespiratórias
    pub hrv_ms: Option<f32>,
    pub heart_rate_bpm: Option<f32>,
    pub spo2_percent: Option<f32>,
    pub resp_rate_bpm: Option<f32>,

    // Temperatura
    pub skin_temp_c: Option<f32>,
    pub body_temp_c: Option<f32>,

    // Atividade
    pub steps: Option<u32>,
    pub energy_burned_kcal: Option<f32>,
    pub vo2max_ml_kg_min: Option<f32>,
}

#[derive(Serialize)]
pub struct PhysioEventResponse {
    pub status: String,            // "ok"
    pub severity: String,          // "Normal" | "Mild" | "Moderate" | "Severe"
    pub hrv_level: Option<String>, // "low" | "normal" | "high"
}

async fn observer_physio_handler(
    axum::extract::State(state): axum::extract::State<AppState>,
    Json(req): Json<PhysioEventRequest>,
) -> Result<Json<PhysioEventResponse>, StatusCode> {
    use beagle_observer::PhysioEvent;

    let hrv_level = req.hrv_ms.map(|hrv| classify_hrv(hrv, None));
    let stress_index = beagle_observer::context::PhysioContext::compute_stress_index(
        req.hrv_ms,
        req.heart_rate_bpm,
    )
    .map(|v| v as f64);

    // Constrói PhysioEvent a partir do request
    let timestamp = if let Some(ts_str) = &req.timestamp {
        chrono::DateTime::parse_from_rfc3339(ts_str)
            .ok()
            .map(|dt| dt.with_timezone(&chrono::Utc))
            .unwrap_or_else(chrono::Utc::now)
    } else {
        chrono::Utc::now()
    };

    let event = PhysioEvent {
        timestamp,
        source: req.source,
        session_id: req.session_id.clone(),
        hrv_ms: req.hrv_ms.map(|v| v as f64),
        heart_rate_bpm: req.heart_rate_bpm.map(|v| v as f64),
        spo2_percent: req.spo2_percent.map(|v| v as f64),
        resp_rate_bpm: req.resp_rate_bpm.map(|v| v as f64),
        skin_temp_c: req.skin_temp_c.map(|v| v as f64),
        body_temp_c: req.body_temp_c.map(|v| v as f64),
        steps: req.steps,
        energy_burned_kcal: req.energy_burned_kcal.map(|v| v as f64),
        vo2max_ml_kg_min: req.vo2max_ml_kg_min.map(|v| v as f64),
        // Legacy fields
        event_type: None,
        hrv_level: hrv_level.clone(),
        stress_index,
        coherence_score: None,
        metadata: std::collections::HashMap::new(),
    };

    // Registra evento e obtém severidade
    let severity = state
        .observer
        .record_physio_event(event, None)
        .await
        .map_err(|e| {
            tracing::error!("Falha ao registrar evento fisiológico: {}", e);
            StatusCode::INTERNAL_SERVER_ERROR
        })?;

    Ok(Json(PhysioEventResponse {
        status: "ok".to_string(),
        severity: severity.as_str().to_string(),
        hrv_level,
    }))
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
        let kind_str = match kind_clone {
            ScienceJobKind::Pbpk => "pbpk",
            ScienceJobKind::Scaffold => "scaffold",
            ScienceJobKind::Helio => "helio",
            ScienceJobKind::Pcs => "pcs",
            ScienceJobKind::Kec => "kec",
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
// Darwin Jobs endpoints (Continuous RAG + ResearchOps)
// ============================================================================

fn key_looks_sensitive(k: &str) -> bool {
    let upper = k.to_ascii_uppercase();
    upper.contains("API_KEY")
        || upper.contains("KEY")
        || upper.contains("TOKEN")
        || upper.contains("SECRET")
        || upper.contains("PASSWORD")
        || upper.contains("PASS")
}

fn redact_secrets(v: &serde_json::Value) -> serde_json::Value {
    match v {
        serde_json::Value::Object(map) => {
            let mut out = serde_json::Map::with_capacity(map.len());
            for (k, v) in map {
                if key_looks_sensitive(k) {
                    out.insert(k.clone(), serde_json::Value::String("<redacted>".to_string()));
                } else {
                    out.insert(k.clone(), redact_secrets(v));
                }
            }
            serde_json::Value::Object(out)
        }
        serde_json::Value::Array(items) => {
            serde_json::Value::Array(items.iter().map(redact_secrets).collect())
        }
        other => other.clone(),
    }
}

#[derive(Deserialize, Clone)]
pub struct DarwinJobStartRequest {
    /// "indexer" | "research_harvester" | "web_harvester" | "knowledge_manager" | "brief" | "eval" | "nightly"
    pub kind: String,
    #[serde(default)]
    pub params: serde_json::Value,
}

#[derive(Serialize)]
pub struct DarwinJobStartResponse {
    pub job_id: String,
    pub status: String,
}

#[derive(Serialize)]
pub struct DarwinJobArtifactsResponse {
    pub job_id: String,
    pub kind: DarwinJobKind,
    pub status: DarwinJobStatus,
    pub output_paths: Vec<String>,
    pub result_json: Option<serde_json::Value>,
}

#[derive(Debug, Deserialize, Default)]
struct DarwinCommandJobParams {
    /// CLI argv (excluding the binary name).
    #[serde(default)]
    argv: Vec<String>,
    /// Optional environment overrides for the spawned job.
    #[serde(default)]
    env: std::collections::HashMap<String, String>,
    /// Optional timeout for the job process.
    timeout_secs: Option<u64>,
}

#[derive(Debug, Deserialize, Default)]
struct DarwinIndexerJobParams {
    #[serde(default)]
    force: bool,
    #[serde(default)]
    sync: bool,
    #[serde(default)]
    repo_path: Vec<String>,
    #[serde(default)]
    repo_url: Vec<String>,
    #[serde(default)]
    repos_file: Vec<String>,
    #[serde(default)]
    github_user: Vec<String>,
    #[serde(default)]
    github_org: Vec<String>,
    #[serde(default)]
    github_me: bool,
    github_api_base: Option<String>,
    github_token: Option<String>,
    #[serde(default)]
    github_include_forks: bool,
    #[serde(default)]
    github_clone_ssh: bool,
    repos_dir: Option<String>,
    state_file: Option<String>,
    qdrant_url: Option<String>,
    embedding_url: Option<String>,
    embedding_model: Option<String>,
    collection: Option<String>,
    error_webhook_url: Option<String>,
    success_webhook_url: Option<String>,
}

async fn darwin_job_start_handler(
    axum::extract::State(state): axum::extract::State<AppState>,
    Json(req): Json<DarwinJobStartRequest>,
) -> Result<Json<DarwinJobStartResponse>, StatusCode> {
    let job_id = uuid::Uuid::new_v4().to_string();

    let kind = match req.kind.as_str() {
        "indexer" => DarwinJobKind::Indexer,
        "research_harvester" => DarwinJobKind::ResearchHarvester,
        "web_harvester" => DarwinJobKind::WebHarvester,
        "knowledge_manager" => DarwinJobKind::KnowledgeManager,
        "brief" => DarwinJobKind::Brief,
        "eval" => DarwinJobKind::Eval,
        "nightly" => DarwinJobKind::Nightly,
        _ => return Err(StatusCode::BAD_REQUEST),
    };

    let job_state = DarwinJobState::new(job_id.clone(), kind, req.params.clone());
    state.darwin_jobs.add_job(job_state.clone()).await;

    info!(
        "Darwin job start requested: job_id={}, kind={:?}",
        job_id, job_state.kind
    );

    let jobs_clone = state.darwin_jobs.clone();
    let job_id_clone = job_id.clone();
    let kind_clone = job_state.kind.clone();
    let req_clone = req.clone();

    tokio::spawn(async move {
        jobs_clone
            .update_job(&job_id_clone, |s| s.update_status(DarwinJobStatus::Running))
            .await;

        let cfg = beagle_config::load();
        let data_dir = PathBuf::from(&cfg.storage.data_dir);
        let jobs_dir = data_dir.join("jobs").join("darwin").join(&job_id_clone);
        std::fs::create_dir_all(&jobs_dir).ok();

        let kind_str = match kind_clone {
            DarwinJobKind::Indexer => "indexer",
            DarwinJobKind::ResearchHarvester => "research_harvester",
            DarwinJobKind::WebHarvester => "web_harvester",
            DarwinJobKind::KnowledgeManager => "knowledge_manager",
            DarwinJobKind::Brief => "brief",
            DarwinJobKind::Eval => "eval",
            DarwinJobKind::Nightly => "nightly",
        };

        let job_config = serde_json::json!({
            "kind": kind_str,
            "job_id": job_id_clone,
            "params": redact_secrets(&req_clone.params),
        });

        let config_path = jobs_dir.join("job_config.json");
        let _ = std::fs::write(
            &config_path,
            serde_json::to_string_pretty(&job_config).unwrap_or_default(),
        );

        let workspace_root = std::env::var("BEAGLE_WORKSPACE_ROOT").unwrap_or_else(|_| {
            std::env::current_dir()
                .unwrap_or_else(|_| PathBuf::from("."))
                .to_string_lossy()
                .to_string()
        });

        let log_path = jobs_dir.join("job.log");
        let summary_path = jobs_dir.join("job_summary.json");

        let (status, result_json) = match kind_clone {
            DarwinJobKind::Indexer => match run_darwin_indexer_job(&req_clone.params).await {
                Ok(result_json) => (DarwinJobStatus::Done, Some(result_json)),
                Err(e) => (DarwinJobStatus::Error(e), None),
            },
            DarwinJobKind::ResearchHarvester
            | DarwinJobKind::WebHarvester
            | DarwinJobKind::KnowledgeManager
            | DarwinJobKind::Brief
            | DarwinJobKind::Eval
            | DarwinJobKind::Nightly => {
                let params: DarwinCommandJobParams =
                    serde_json::from_value(req_clone.params.clone()).unwrap_or_default();

                let (bin, argv) = match kind_clone {
                    DarwinJobKind::ResearchHarvester => ("darwin-research-harvester", params.argv),
                    DarwinJobKind::WebHarvester => ("darwin-web-harvester", params.argv),
                    DarwinJobKind::KnowledgeManager => ("darwin-knowledge-manager", params.argv),
                    DarwinJobKind::Brief => ("darwin-brief", params.argv),
                    DarwinJobKind::Eval => ("darwin-eval", params.argv),
                    DarwinJobKind::Nightly => {
                        // Runs the same script used by systemd timers:
                        // `scripts/systemd/darwin-nightly.sh` (relative to BEAGLE_WORKSPACE_ROOT).
                        let mut argv = vec!["scripts/systemd/darwin-nightly.sh".to_string()];
                        argv.extend(params.argv);
                        ("bash", argv)
                    }
                    DarwinJobKind::Indexer => unreachable!(),
                };

                match run_darwin_command_job(
                    bin,
                    &argv,
                    &params.env,
                    params.timeout_secs,
                    &workspace_root,
                    &config_path,
                    &log_path,
                )
                .await
                {
                    Ok(result_json) => (DarwinJobStatus::Done, Some(result_json)),
                    Err(e) => (DarwinJobStatus::Error(e), None),
                }
            }
        };

        let output_paths = vec![
            config_path.to_string_lossy().to_string(),
            summary_path.to_string_lossy().to_string(),
            log_path.to_string_lossy().to_string(),
        ];

        let summary_json = serde_json::json!({
            "kind": kind_str,
            "job_id": job_id_clone,
            "status": status.to_string(),
            "result_json": result_json,
            "output_paths": output_paths,
        });

        let _ = std::fs::write(
            &summary_path,
            serde_json::to_string_pretty(&summary_json).unwrap_or_default(),
        );

        if !log_path.exists() {
            let _ = std::fs::write(
                &log_path,
                serde_json::to_string_pretty(&summary_json).unwrap_or_default(),
            );
        }

        jobs_clone
            .update_job(&job_id_clone, |s| {
                match status {
                    DarwinJobStatus::Error(ref err) => s.set_error(err.clone()),
                    _ => s.update_status(status.clone()),
                }
                s.output_paths = output_paths;
                s.result_json = result_json;
            })
            .await;
    });

    Ok(Json(DarwinJobStartResponse {
        job_id: job_id.clone(),
        status: "created".to_string(),
    }))
}

async fn darwin_job_status_handler(
    axum::extract::State(state): axum::extract::State<AppState>,
    axum::extract::Path(job_id): axum::extract::Path<String>,
) -> Result<Json<DarwinJobState>, StatusCode> {
    state
        .darwin_jobs
        .get_job(&job_id)
        .await
        .map(Json)
        .ok_or(StatusCode::NOT_FOUND)
}

async fn darwin_job_artifacts_handler(
    axum::extract::State(state): axum::extract::State<AppState>,
    axum::extract::Path(job_id): axum::extract::Path<String>,
) -> Result<Json<DarwinJobArtifactsResponse>, StatusCode> {
    let job = state
        .darwin_jobs
        .get_job(&job_id)
        .await
        .ok_or(StatusCode::NOT_FOUND)?;

    Ok(Json(DarwinJobArtifactsResponse {
        job_id: job.job_id,
        kind: job.kind,
        status: job.status,
        output_paths: job.output_paths,
        result_json: job.result_json,
    }))
}

#[derive(Deserialize)]
struct ListRecentDarwinJobsQuery {
    limit: Option<usize>,
}

#[derive(Serialize)]
struct RecentDarwinJobsResponse {
    jobs: Vec<RecentDarwinJobInfo>,
}

#[derive(Serialize)]
struct RecentDarwinJobInfo {
    job_id: String,
    kind: DarwinJobKind,
    status: DarwinJobStatus,
    created_at: chrono::DateTime<chrono::Utc>,
    updated_at: chrono::DateTime<chrono::Utc>,
    error: Option<String>,
}

async fn darwin_jobs_recent_handler(
    axum::extract::State(state): axum::extract::State<AppState>,
    axum::extract::Query(query): axum::extract::Query<ListRecentDarwinJobsQuery>,
) -> Json<RecentDarwinJobsResponse> {
    let limit = query.limit.unwrap_or(10).clamp(1, 50);
    let jobs = state
        .darwin_jobs
        .get_recent_jobs(limit)
        .await
        .into_iter()
        .map(|j| RecentDarwinJobInfo {
            job_id: j.job_id,
            kind: j.kind,
            status: j.status,
            created_at: j.created_at,
            updated_at: j.updated_at,
            error: j.error,
        })
        .collect();
    Json(RecentDarwinJobsResponse { jobs })
}

async fn run_darwin_indexer_job(params: &serde_json::Value) -> Result<serde_json::Value, String> {
    let params: DarwinIndexerJobParams =
        serde_json::from_value(params.clone()).unwrap_or_default();

    if params.repo_path.is_empty()
        && params.repo_url.is_empty()
        && params.repos_file.is_empty()
        && params.github_user.is_empty()
        && params.github_org.is_empty()
        && !params.github_me
    {
        return Err(
            "provide at least one repo source: repo_path, repo_url, repos_file, github_user, github_org, or github_me"
                .to_string(),
        );
    }

    let repos_dir = expand_tilde(params.repos_dir.as_deref().unwrap_or("~/repos"));
    let state_file = expand_tilde(
        params
            .state_file
            .as_deref()
            .unwrap_or("~/.darwin_index_state.json"),
    );

    let qdrant_url = params.qdrant_url.unwrap_or_else(|| {
        std::env::var("QDRANT_URL").unwrap_or_else(|_| "http://localhost:6333".to_string())
    });
    let embedding_url = params.embedding_url.unwrap_or_else(|| {
        std::env::var("EMBEDDING_URL").unwrap_or_else(|_| "http://localhost:8001/v1".to_string())
    });
    let embedding_model = params.embedding_model.unwrap_or_else(|| {
        std::env::var("EMBEDDING_MODEL").unwrap_or_else(|_| "NV-Embed-v2".to_string())
    });
    let collection = params.collection.unwrap_or_else(|| {
        std::env::var("DARWIN_QDRANT_COLLECTION").unwrap_or_else(|_| "darwin-repos".to_string())
    });

    let extensions: HashSet<String> = [".py", ".rs", ".md", ".txt", ".json", ".yaml", ".yml", ".toml"]
        .into_iter()
        .map(|s| s.to_string())
        .collect();
    let ignore_dirs: HashSet<String> = [
        ".git",
        "node_modules",
        "target",
        "__pycache__",
        ".venv",
        "venv",
    ]
    .into_iter()
    .map(|s| s.to_string())
    .collect();

    let mut cfg = IndexerConfig {
        repos_dir: repos_dir.clone(),
        state_file,
        qdrant_url,
        embedding_url,
        embedding_model,
        collection,
        chunk_size: 1500,
        chunk_overlap: 200,
        extensions,
        ignore_dirs,
        max_file_size: 500_000,
        error_webhook_url: params
            .error_webhook_url
            .clone()
            .or_else(|| std::env::var("DARWIN_INDEX_ERROR_WEBHOOK_URL").ok()),
        success_webhook_url: params
            .success_webhook_url
            .clone()
            .or_else(|| std::env::var("DARWIN_INDEX_SUCCESS_WEBHOOK_URL").ok()),
        ledger: None,
    };

    if let Ok(db_url) = std::env::var("DARWIN_LEDGER_DATABASE_URL") {
        match IngestionLedger::connect(&db_url).await {
            Ok(ledger) => {
                if ledger.ensure_schema().await.is_ok() {
                    cfg.ledger = Some(ledger);
                }
            }
            Err(_) => {}
        }
    }

    let mut repos: Vec<RepoTarget> = Vec::new();

    for f in &params.repos_file {
        let path = expand_tilde(f);
        let mut targets = load_repo_targets_file(&path, &repos_dir).map_err(|e| e.to_string())?;
        repos.append(&mut targets);
    }

    for p in &params.repo_path {
        let path = expand_tilde(p);
        let name = path
            .file_name()
            .and_then(|s| s.to_str())
            .unwrap_or("repo")
            .to_string();
        repos.push(RepoTarget {
            name,
            path,
            url: None,
        });
    }
    for url in &params.repo_url {
        let name = url
            .split('/')
            .last()
            .unwrap_or("repo")
            .trim_end_matches(".git")
            .to_string();
        let path = repos_dir.join(&name);
        repos.push(RepoTarget {
            name,
            path,
            url: Some(url.clone()),
        });
    }

    if !params.github_user.is_empty() || !params.github_org.is_empty() || params.github_me {
        let api_base = params
            .github_api_base
            .clone()
            .unwrap_or_else(|| "https://api.github.com".to_string());
        let token = params.github_token.clone().or_else(GitHubClient::token_from_env);
        let gh = GitHubClient::new(api_base, token).map_err(|e| e.to_string())?;

        for user in &params.github_user {
            let gh_repos = gh
                .list_user_repos(user, params.github_include_forks)
                .await
                .map_err(|e| e.to_string())?;
            for r in gh_repos {
                let url = if params.github_clone_ssh {
                    r.ssh_url.or(r.clone_url)
                } else {
                    r.clone_url.or(r.ssh_url)
                };
                let Some(url) = url else { continue };
                let name = r.name;
                let path = repos_dir.join(&name);
                repos.push(RepoTarget {
                    name,
                    path,
                    url: Some(url),
                });
            }
        }

        for org in &params.github_org {
            let gh_repos = gh
                .list_org_repos(org, params.github_include_forks)
                .await
                .map_err(|e| e.to_string())?;
            for r in gh_repos {
                let url = if params.github_clone_ssh {
                    r.ssh_url.or(r.clone_url)
                } else {
                    r.clone_url.or(r.ssh_url)
                };
                let Some(url) = url else { continue };
                let name = r.name;
                let path = repos_dir.join(&name);
                repos.push(RepoTarget {
                    name,
                    path,
                    url: Some(url),
                });
            }
        }

        if params.github_me {
            let gh_repos = gh
                .list_authenticated_user_repos(params.github_include_forks)
                .await
                .map_err(|e| e.to_string())?;
            for r in gh_repos {
                let url = if params.github_clone_ssh {
                    r.ssh_url.or(r.clone_url)
                } else {
                    r.clone_url.or(r.ssh_url)
                };
                let Some(url) = url else { continue };
                let name = r.name;
                let path = repos_dir.join(&name);
                repos.push(RepoTarget {
                    name,
                    path,
                    url: Some(url),
                });
            }
        }
    }

    // Deduplicate targets (common when mixing repos_file + github discovery + explicit paths).
    let mut seen: HashSet<(String, String)> = HashSet::new();
    repos.retain(|r| seen.insert((r.name.clone(), r.path.to_string_lossy().to_string())));

    if repos.is_empty() {
        return Err("no repos resolved from provided sources".to_string());
    }

    match run_incremental(&cfg, repos, params.force, params.sync).await {
        Ok(summary) => Ok(serde_json::json!({
            "repos": summary.repos,
            "files_added": summary.files_added,
            "files_modified": summary.files_modified,
            "files_deleted": summary.files_deleted,
            "files_skipped_unchanged": summary.files_skipped_unchanged,
            "chunks_upserted": summary.chunks_upserted,
        })),
        Err(e) => Err(format!("{e:#}")),
    }
}

async fn run_darwin_command_job(
    bin: &str,
    argv: &[String],
    env_overrides: &std::collections::HashMap<String, String>,
    timeout_secs: Option<u64>,
    workspace_root: &str,
    config_path: &PathBuf,
    log_path: &PathBuf,
) -> Result<serde_json::Value, String> {
    let Some(bin_path) = resolve_executable(bin) else {
        return Err(format!(
            "binary not found: {bin} (set PATH or DARWIN_BIN_DIR)"
        ));
    };

    let mut cmd = tokio::process::Command::new(&bin_path);
    cmd.args(argv);
    cmd.current_dir(workspace_root);
    cmd.env("DARWIN_JOB_CONFIG", config_path.to_string_lossy().to_string());
    for (k, v) in env_overrides {
        cmd.env(k, v);
    }

    cmd.stdout(std::process::Stdio::piped());
    cmd.stderr(std::process::Stdio::piped());
    let mut child = cmd.spawn().map_err(|e| format!("spawn failed: {e}"))?;

    let stdout_pipe = child
        .stdout
        .take()
        .ok_or_else(|| "failed to capture stdout".to_string())?;
    let stderr_pipe = child
        .stderr
        .take()
        .ok_or_else(|| "failed to capture stderr".to_string())?;

    let stdout_task = tokio::spawn(async move {
        let mut buf = Vec::new();
        let mut r = stdout_pipe;
        tokio::io::AsyncReadExt::read_to_end(&mut r, &mut buf)
            .await
            .map_err(|e| format!("stdout read failed: {e}"))?;
        Ok::<Vec<u8>, String>(buf)
    });

    let stderr_task = tokio::spawn(async move {
        let mut buf = Vec::new();
        let mut r = stderr_pipe;
        tokio::io::AsyncReadExt::read_to_end(&mut r, &mut buf)
            .await
            .map_err(|e| format!("stderr read failed: {e}"))?;
        Ok::<Vec<u8>, String>(buf)
    });

    let status = if let Some(secs) = timeout_secs {
        match tokio::time::timeout(std::time::Duration::from_secs(secs), child.wait()).await {
            Ok(res) => res.map_err(|e| format!("wait failed: {e}"))?,
            Err(_) => {
                let _ = child.kill().await;
                let _ = child.wait().await;
                let stdout_buf = stdout_task
                    .await
                    .map_err(|e| format!("stdout join failed: {e}"))??;
                let stderr_buf = stderr_task
                    .await
                    .map_err(|e| format!("stderr join failed: {e}"))??;
                let stdout = String::from_utf8_lossy(&stdout_buf).to_string();
                let stderr = String::from_utf8_lossy(&stderr_buf).to_string();
                let _ = std::fs::write(
                    log_path,
                    format!(
                        "bin: {}\nargv: {:?}\nexit_code: timeout\n\n--- stdout ---\n{}\n\n--- stderr ---\n{}\n",
                        bin_path.display(),
                        argv,
                        stdout,
                        stderr
                    ),
                );
                return Err(format!("job timed out after {secs}s (see {})", log_path.display()));
            }
        }
    } else {
        child
            .wait()
            .await
            .map_err(|e| format!("wait failed: {e}"))?
    };

    let stdout_buf = stdout_task
        .await
        .map_err(|e| format!("stdout join failed: {e}"))??;
    let stderr_buf = stderr_task
        .await
        .map_err(|e| format!("stderr join failed: {e}"))??;
    let stdout = String::from_utf8_lossy(&stdout_buf).to_string();
    let stderr = String::from_utf8_lossy(&stderr_buf).to_string();
    let exit_code = status.code();

    let _ = std::fs::write(
        log_path,
        format!(
            "bin: {}\nargv: {:?}\nexit_code: {:?}\n\n--- stdout ---\n{}\n\n--- stderr ---\n{}\n",
            bin_path.display(),
            argv,
            exit_code,
            stdout,
            stderr
        ),
    );

    if !status.success() {
        return Err(format!(
            "job failed: {bin} exit_code={:?} (see {})",
            exit_code,
            log_path.display()
        ));
    }

    Ok(serde_json::json!({
        "bin": bin,
        "argv": argv,
        "exit_code": exit_code,
        "log_path": log_path,
    }))
}

fn resolve_executable(name: &str) -> Option<PathBuf> {
    if let Ok(dir) = std::env::var("DARWIN_BIN_DIR") {
        let candidate = PathBuf::from(dir).join(name);
        if candidate.exists() {
            return Some(candidate);
        }
    }

    let mut candidates = Vec::new();
    if let Ok(path) = std::env::var("PATH") {
        for p in path.split(':') {
            if !p.trim().is_empty() {
                candidates.push(PathBuf::from(p).join(name));
            }
        }
    }
    for p in [
        "/usr/local/bin",
        "/usr/bin",
        "/bin",
        "/root/.cargo/bin",
        "/home/demetrios/.cargo/bin",
    ] {
        candidates.push(PathBuf::from(p).join(name));
    }

    candidates.into_iter().find(|p| p.exists())
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
    Json(_req): Json<PCSReasonRequest>,
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

#[derive(Debug, Deserialize)]
struct SerendipityToggleRequest {
    enabled: bool,
    /// Optional: control Triad prompt perturbation separately.
    in_triad: Option<bool>,
}

#[derive(Serialize)]
struct SerendipityToggleResponse {
    status: String,
    enabled: bool,
    in_triad: bool,
    persisted: bool,
}

#[derive(Debug, Deserialize)]
struct SerendipityPerturbRequest {
    prompt: String,
    max_accidents: Option<usize>,
}

#[derive(Serialize)]
struct SerendipityPerturbResponse {
    mutated_prompt: String,
    delta_description: String,
    message: String,
    enabled: bool,
}

#[derive(Debug, Deserialize)]
struct VoidBreakLoopRequest {
    run_id: String,
    reason: String,
    focus: Option<String>,
}

#[derive(Debug, Deserialize)]
struct VoidToggleRequest {
    enabled: bool,
}

#[derive(Serialize)]
struct VoidToggleResponse {
    status: String,
    enabled: bool,
    persisted: bool,
}

#[derive(Serialize)]
struct VoidBreakLoopResponse {
    status: String,
    run_id: String,
    action: String,
    description: String,
    message: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    void_insight: Option<String>,
    enabled: bool,
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

    let max_connections = req.max_connections.unwrap_or(5).clamp(1, 20);

    let mut cfg = beagle_serendipity::SerendipityConfig::default();
    // Endpoint explícito: sempre gerar sugestões quando chamado.
    cfg.exploration_rate = 1.0;

    let injector = beagle_serendipity::SerendipityInjector::with_config(cfg);
    let quantum_state = beagle_quantum::HypothesisSet::new();

    let accidents = injector
        .inject_fertile_accident(&quantum_state, &req.focus_project)
        .await
        .map_err(|e| {
            error!("SerendipityInjector error: {}", e);
            StatusCode::BAD_GATEWAY
        })?;

    let embedding_url = std::env::var("EMBEDDING_URL")
        .or_else(|_| std::env::var("BEAGLE_EMBEDDING_URL"))
        .ok();
    let embedder = embedding_url.as_ref().map(|url| EmbeddingClient::new(url.clone()));
    let focus_embedding = if let Some(embedder) = &embedder {
        match embedder.embed(&req.focus_project).await {
            Ok(v) => Some(v),
            Err(e) => {
                warn!("Embedding error (focus_project): {}", e);
                None
            }
        }
    } else {
        None
    };

    fn infer_target_project(description: &str) -> Option<String> {
        let trimmed = description.trim_start();
        if !trimmed.starts_with('[') {
            return None;
        }
        let end = trimmed.find(']')?;
        if end <= 1 {
            return None;
        }
        Some(trimmed[1..end].to_string())
    }

    let mut connections = Vec::new();
    for accident in accidents.into_iter().take(max_connections) {
        let similarity_score = if let (Some(embedder), Some(focus_embedding)) =
            (&embedder, &focus_embedding)
        {
            match embedder.embed(&accident.description).await {
                Ok(other) => EmbeddingClient::cosine_similarity(focus_embedding, &other) as f32,
                Err(e) => {
                    warn!("Embedding error (accident): {}", e);
                    0.0
                }
            }
        } else {
            0.0
        };

        let novelty_score = accident.novelty_score as f32;
        let potential_impact = if novelty_score >= 0.9 {
            "High"
        } else if novelty_score >= 0.78 {
            "Medium"
        } else {
            "Low"
        }
        .to_string();

        connections.push(SerendipityConnection {
            id: accident.id.to_string(),
            source_project: req.focus_project.clone(),
            target_project: infer_target_project(&accident.description)
                .unwrap_or_else(|| "unknown".to_string()),
            source_concept: req.focus_project.clone(),
            target_concept: accident.description.clone(),
            similarity_score,
            novelty_score,
            connection_type: format!("{:?}", accident.source),
            explanation: "Generated by BEAGLE SerendipityInjector".to_string(),
            potential_impact,
        });
    }

    Ok(Json(SerendipityDiscoverResponse {
        count: connections.len(),
        connections,
    }))
}

async fn serendipity_toggle_handler(
    axum::extract::State(state): axum::extract::State<AppState>,
    Json(req): Json<SerendipityToggleRequest>,
) -> Result<Json<SerendipityToggleResponse>, StatusCode> {
    let mut ctx = state.ctx.lock().await;

    ctx.cfg.advanced.serendipity_enabled = req.enabled;
    if let Some(in_triad) = req.in_triad {
        ctx.cfg.advanced.serendipity_in_triad = in_triad;
    }

    let overrides_path = PathBuf::from(&ctx.cfg.storage.data_dir)
        .join("config")
        .join("runtime_overrides.json");
    let persisted = (|| {
        if let Some(parent) = overrides_path.parent() {
            std::fs::create_dir_all(parent).ok()?;
        }

        let mut body = match std::fs::read_to_string(&overrides_path) {
            Ok(text) => serde_json::from_str::<serde_json::Value>(&text)
                .unwrap_or_else(|_| serde_json::json!({})),
            Err(_) => serde_json::json!({}),
        };

        if !body.is_object() {
            body = serde_json::json!({});
        }

        if !body.get("advanced").map(|v| v.is_object()).unwrap_or(false) {
            body["advanced"] = serde_json::json!({});
        }

        body["advanced"]["serendipity_enabled"] =
            serde_json::json!(ctx.cfg.advanced.serendipity_enabled);
        body["advanced"]["serendipity_in_triad"] =
            serde_json::json!(ctx.cfg.advanced.serendipity_in_triad);

        std::fs::write(
            &overrides_path,
            serde_json::to_string_pretty(&body).unwrap_or_default(),
        )
        .ok()?;
        Some(())
    })()
    .is_some();

    Ok(Json(SerendipityToggleResponse {
        status: "ok".to_string(),
        enabled: ctx.cfg.advanced.serendipity_enabled,
        in_triad: ctx.cfg.advanced.serendipity_in_triad,
        persisted,
    }))
}

async fn serendipity_perturb_handler(
    axum::extract::State(state): axum::extract::State<AppState>,
    Json(req): Json<SerendipityPerturbRequest>,
) -> Result<Json<SerendipityPerturbResponse>, StatusCode> {
    let prompt = req.prompt;
    let max_accidents = req.max_accidents.unwrap_or(3).clamp(1, 10);

    let enabled = {
        let ctx = state.ctx.lock().await;
        ctx.cfg.serendipity_enabled()
    };

    if !enabled {
        return Ok(Json(SerendipityPerturbResponse {
            mutated_prompt: prompt.clone(),
            delta_description: "Serendipity disabled; no mutation applied".to_string(),
            message: "Serendipity Engine is disabled".to_string(),
            enabled,
        }));
    }

    let mut cfg = beagle_serendipity::SerendipityConfig::default();
    cfg.exploration_rate = 1.0;
    let injector = beagle_serendipity::SerendipityInjector::with_config(cfg);
    let quantum_state = beagle_quantum::HypothesisSet::new();

    let accidents = injector
        .inject_fertile_accident(&quantum_state, &prompt)
        .await
        .map_err(|e| {
            error!("SerendipityInjector error (perturb): {}", e);
            StatusCode::BAD_GATEWAY
        })?;

    let accident_lines: Vec<String> = accidents
        .into_iter()
        .take(max_accidents)
        .map(|a| a.to_string())
        .collect();

    let (mutated_prompt, delta_description) = if accident_lines.is_empty() {
        (
            prompt.clone(),
            "Serendipity produced no mutations".to_string(),
        )
    } else {
        (
            format!(
                "{prompt}\n\n=== SERENDIPITY (EXPERIMENTAL) ===\n{}\n",
                accident_lines.join("\n")
            ),
            format!("Appended {} serendipity angles", accident_lines.len()),
        )
    };

    Ok(Json(SerendipityPerturbResponse {
        mutated_prompt,
        delta_description,
        message: "Serendipity perturbation applied (experimental)".to_string(),
        enabled,
    }))
}

async fn void_toggle_handler(
    axum::extract::State(state): axum::extract::State<AppState>,
    Json(req): Json<VoidToggleRequest>,
) -> Result<Json<VoidToggleResponse>, StatusCode> {
    let mut ctx = state.ctx.lock().await;
    ctx.cfg.advanced.void_enabled = req.enabled;

    let overrides_path = PathBuf::from(&ctx.cfg.storage.data_dir)
        .join("config")
        .join("runtime_overrides.json");

    let persisted = (|| {
        if let Some(parent) = overrides_path.parent() {
            std::fs::create_dir_all(parent).ok()?;
        }

        let mut body = match std::fs::read_to_string(&overrides_path) {
            Ok(text) => serde_json::from_str::<serde_json::Value>(&text)
                .unwrap_or_else(|_| serde_json::json!({})),
            Err(_) => serde_json::json!({}),
        };

        if !body.is_object() {
            body = serde_json::json!({});
        }

        if !body.get("advanced").map(|v| v.is_object()).unwrap_or(false) {
            body["advanced"] = serde_json::json!({});
        }

        body["advanced"]["void_enabled"] = serde_json::json!(ctx.cfg.advanced.void_enabled);

        std::fs::write(
            &overrides_path,
            serde_json::to_string_pretty(&body).unwrap_or_default(),
        )
        .ok()?;
        Some(())
    })()
    .is_some();

    Ok(Json(VoidToggleResponse {
        status: "ok".to_string(),
        enabled: ctx.cfg.advanced.void_enabled,
        persisted,
    }))
}

async fn void_break_loop_handler(
    axum::extract::State(state): axum::extract::State<AppState>,
    Json(req): Json<VoidBreakLoopRequest>,
) -> Result<Json<VoidBreakLoopResponse>, StatusCode> {
    info!("Void break loop request: run_id={}", req.run_id);

    let enabled = {
        let ctx = state.ctx.lock().await;
        ctx.cfg.void_enabled()
    };

    if !enabled {
        return Ok(Json(VoidBreakLoopResponse {
            status: "ok".to_string(),
            run_id: req.run_id,
            action: "void_disabled".to_string(),
            description: "Void is disabled; no action taken".to_string(),
            message: "Set BEAGLE_VOID_ENABLED=true (or persist via runtime overrides) to enable Void"
                .to_string(),
            void_insight: None,
            enabled,
        }));
    }

    let focus = req.focus.clone().unwrap_or_else(|| "".to_string());
    let insight =
        crate::pipeline_void::handle_deadlock(&req.run_id, &req.reason, &focus)
            .await
            .map_err(|e| {
                error!("Void handler error: {}", e);
                StatusCode::BAD_GATEWAY
            })?;

    Ok(Json(VoidBreakLoopResponse {
        status: "ok".to_string(),
        run_id: req.run_id.clone(),
        action: "void_break_applied".to_string(),
        description: format!("Void behavior applied to run {}: {}", req.run_id, req.reason),
        message: "Void break applied (experimental)".to_string(),
        void_insight: Some(insight),
        enabled,
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
