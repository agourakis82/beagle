use crate::auth::api_token_auth;
use crate::{
    run_beagle_pipeline, ExperimentFlags, RunState, RunStatus, ScienceJobKind, ScienceJobRegistry,
    ScienceJobState, ScienceJobStatus,
};
use axum::http::StatusCode;
use axum::{
    extract::Path,
    middleware,
    routing::{get, post},
    Json, Router,
};
use beagle_config::{beagle_data_dir, classify_hrv};
use beagle_core::BeagleContext;
use beagle_feedback::{append_event, create_triad_event};
use beagle_llm::{ProviderTier, RequestMeta};
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
use tokio::sync::Mutex;
use tower_http::trace::TraceLayer;
use tracing::{error, info, warn};
use uuid::Uuid;

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

use crate::jobs::JobRegistry;

#[derive(Clone)]
pub struct AppState {
    pub ctx: Arc<Mutex<BeagleContext>>,
    pub jobs: Arc<JobRegistry>,
    pub science_jobs: Arc<ScienceJobRegistry>,
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
        .merge(crate::http_darwin_hpc::darwin_hpc_routes())
        .merge(crate::http_memory::memory_routes())
        .merge(crate::http_exocortex::exocortex_routes())
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
        .route("/api/v1/round-table", post(round_table_handler))
        .route("/api/v1/cognitive/state", get(cognitive_state_handler))
        // Go Deeper modality routes (used by iOS GoDeepStore)
        .route("/dev/deep-research", post(go_deep_generic_handler))
        .route("/dev/swarm", post(go_deep_generic_handler))
        .route("/dev/temporal", post(go_deep_generic_handler))
        .route("/dev/neurosymbolic", post(go_deep_generic_handler))
        .route("/dev/causal", post(go_deep_generic_handler))
        .route("/dev/debate", post(go_deep_debate_handler))
        // Wave 3 — restored reasoning engines
        .route("/dev/quantum-reasoning", post(quantum_reasoning_handler))
        .route("/dev/adversarial-compete", post(adversarial_compete_handler))
        .route("/dev/causal/intervention", post(causal_intervention_handler))
        .route(
            "/api/worldmodel/counterfactual",
            post(worldmodel_counterfactual_handler),
        )
        .route(
            "/api/hyperedges",
            get(hyperedges_list_handler).post(hyperedges_create_handler),
        )
        .route("/api/v1/feedback", post(feedback_handler))
        .route_layer(middleware::from_fn_with_state(
            state.clone(),
            api_token_auth,
        ));

    // Rotas públicas (sem autenticação - para health checks e monitoring)
    let public_routes = Router::new().route("/health", get(health_handler));

    // Combina rotas protegidas e públicas
    Router::new()
        .merge(protected_routes)
        .merge(public_routes)
        .layer(TraceLayer::new_for_http())
        .with_state(state)
}

async fn llm_complete_handler(
    axum::extract::State(state): axum::extract::State<AppState>,
    Json(req): Json<LlmRequest>,
) -> Result<Json<LlmResponse>, StatusCode> {
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
    // ctx.router.complete(), which re-routes via the non-limit-aware choose() and discards the
    // chosen client + the request's RequestMeta flags (budgets bypassed).
    let text = ctx
        .router
        .complete_chosen(&client, tier, &req.prompt)
        .await
        .map_err(|e| {
            tracing::error!("LLM error: {}", e);
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
    use beagle_observer::{PhysioEvent, Severity};

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
        hrv_level: None,
        stress_index: None,
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

    // Classifica HRV para resposta (compatibilidade)
    let hrv_level = req.hrv_ms.map(|hrv| classify_hrv(hrv, None));

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
    tier: String,
    model: String,
}

async fn pcs_reason_handler(
    axum::extract::State(state): axum::extract::State<AppState>,
    Json(req): Json<PCSReasonRequest>,
) -> Result<Json<PCSReasonResponse>, StatusCode> {
    info!("PCS symbolic reasoning request");

    let symptoms_json = serde_json::to_string_pretty(&req.symptoms).map_err(|e| {
        error!("Falha ao serializar symptoms: {}", e);
        StatusCode::BAD_REQUEST
    })?;

    // PCS = Probabilistic Causal/Symbolic clinical reasoning. This is a critical,
    // high-stakes clinical reasoning task — escalate to the highest quality tier and
    // ask for a strictly-typed JSON answer so we can parse a real diagnosis + confidence.
    let prompt = format!(
        "You are a rigorous clinical reasoning engine (PCS: Probabilistic Causal-Symbolic reasoning).\n\
         Given the following structured patient symptoms/observations (JSON), perform careful \
         differential diagnosis reasoning. Weigh competing hypotheses, consider base rates, and be \
         explicit about uncertainty. Do NOT fabricate findings not supported by the input.\n\n\
         SYMPTOMS (JSON):\n{symptoms}\n\n\
         Respond with ONLY a single JSON object (no markdown, no prose outside the JSON) with this \
         exact schema:\n\
         {{\n  \
           \"primary_diagnosis\": string,\n  \
           \"differential\": [ {{ \"condition\": string, \"probability\": number, \"rationale\": string }} ],\n  \
           \"red_flags\": [string],\n  \
           \"recommended_workup\": [string],\n  \
           \"reasoning\": string,\n  \
           \"confidence\": number  // overall confidence in primary_diagnosis, 0.0..1.0\n\
         }}",
        symptoms = symptoms_json
    );

    let mut ctx = state.ctx.lock().await;

    // Critical clinical reasoning -> request the premium reasoning tier explicitly.
    let mut meta = RequestMeta::from_prompt(&prompt);
    meta.requires_high_quality = true;
    meta.requires_phd_level_reasoning = true;
    meta.critical_section = true;

    let run_id = "http_pcs_reason";
    let current_stats = ctx.llm_stats.get_or_create(run_id);

    let (client, tier) = ctx.router.choose_with_limits(&meta, &current_stats);
    let model = client.name().to_string();

    let text = ctx
        .router
        .complete_chosen(&client, tier, &prompt)
        .await
        .map_err(|e| {
            error!("PCS LLM error: {}", e);
            StatusCode::BAD_GATEWAY
        })?;

    // Budget accounting (~4 chars/token estimate), same pattern as llm_complete_handler.
    let tokens_in_est = (prompt.len() / 4) as u32;
    let tokens_out_est = (text.len() / 4) as u32;
    ctx.llm_stats.update(run_id, |stats| match tier {
        ProviderTier::Grok4Heavy => {
            stats.grok4_calls += 1;
            stats.grok4_tokens_in += tokens_in_est;
            stats.grok4_tokens_out += tokens_out_est;
        }
        _ => {
            stats.grok3_calls += 1;
            stats.grok3_tokens_in += tokens_in_est;
            stats.grok3_tokens_out += tokens_out_est;
        }
    });
    drop(ctx);

    // Parse the model's JSON answer. Tolerate fenced code blocks / surrounding prose by
    // extracting the first JSON object.
    let diagnosis = parse_first_json_object(&text).unwrap_or_else(|| {
        serde_json::json!({ "raw": text, "parse_error": "model did not return strict JSON" })
    });

    let confidence = diagnosis
        .get("confidence")
        .and_then(|v| v.as_f64())
        .unwrap_or(0.0)
        .clamp(0.0, 1.0);

    info!(tier = ?tier, model = %model, "PCS reasoning completed");

    Ok(Json(PCSReasonResponse {
        diagnosis,
        confidence,
        tier: format!("{:?}", tier),
        model,
    }))
}

/// Extract and parse the first balanced top-level JSON object from arbitrary LLM text.
/// Handles plain JSON, JSON wrapped in ```json fences, or JSON embedded in prose.
fn parse_first_json_object(text: &str) -> Option<serde_json::Value> {
    if let Ok(v) = serde_json::from_str::<serde_json::Value>(text.trim()) {
        return Some(v);
    }
    let bytes = text.as_bytes();
    let start = text.find('{')?;
    let mut depth = 0usize;
    let mut in_str = false;
    let mut escaped = false;
    for i in start..bytes.len() {
        let c = bytes[i] as char;
        if in_str {
            if escaped {
                escaped = false;
            } else if c == '\\' {
                escaped = true;
            } else if c == '"' {
                in_str = false;
            }
            continue;
        }
        match c {
            '"' => in_str = true,
            '{' => depth += 1,
            '}' => {
                depth -= 1;
                if depth == 0 {
                    let candidate = &text[start..=i];
                    return serde_json::from_str::<serde_json::Value>(candidate).ok();
                }
            }
            _ => {}
        }
    }
    None
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
    axum::extract::State(state): axum::extract::State<AppState>,
    Json(req): Json<SerendipityDiscoverRequest>,
) -> Result<Json<SerendipityDiscoverResponse>, StatusCode> {
    info!(
        "Serendipity discovery request: focus_project={}",
        req.focus_project
    );

    let max_connections = req.max_connections.unwrap_or(5).clamp(1, 20);

    // 1) Embed the focus project / query so the SerendipityEngine explores around a real point
    //    in semantic space. Uses the same EmbeddingClient path as the vector store.
    let embedding_url = std::env::var("EMBEDDING_URL")
        .ok()
        .or_else(|| std::env::var("BEAGLE_EMBEDDING_URL").ok());
    let embed_client = match embedding_url {
        Some(url) => beagle_llm::embedding::EmbeddingClient::new(url),
        None => beagle_llm::embedding::EmbeddingClient::default(),
    };
    let embedding_vec = embed_client
        .embed(&req.focus_project)
        .await
        .map_err(|e| {
            error!("Serendipity embedding failed: {}", e);
            StatusCode::BAD_GATEWAY
        })?;

    // 2) Build a BeagleContext for the engine. The engine owns an Arc<BeagleContext> and uses it
    //    for the LLM router during exploration/impact assessment. The HTTP state holds the context
    //    behind a Mutex (not shareable as Arc<BeagleContext>), so we construct a fresh context from
    //    the same live config — same router/providers, real LLM calls.
    let cfg = {
        let ctx = state.ctx.lock().await;
        ctx.cfg.clone()
    };

    // 3) Run the real serendipity exploration. The engine internally holds a `ThreadRng` (!Send)
    //    across .await points, so its future is !Send and cannot live in an axum (Send) handler
    //    future directly. Run it on a dedicated current-thread runtime inside spawn_blocking; the
    //    returned SerendipityResult IS Send, so it crosses back cleanly.
    let focus = req.focus_project.clone();
    let result = tokio::task::spawn_blocking(move || -> anyhow::Result<beagle_serendipity::SerendipityResult> {
        let rt = tokio::runtime::Builder::new_current_thread()
            .enable_all()
            .build()?;
        rt.block_on(async move {
            let engine_ctx = beagle_core::BeagleContext::new(cfg).await?;
            let engine = beagle_serendipity::SerendipityEngine::new(
                beagle_serendipity::SerendipityConfig::default(),
                Arc::new(engine_ctx),
            );
            let context_embedding = nalgebra::DVector::from_vec(embedding_vec);
            engine.inject_serendipity(&focus, context_embedding).await
        })
    })
    .await
    .map_err(|e| {
        error!("Serendipity join error: {}", e);
        StatusCode::INTERNAL_SERVER_ERROR
    })?
    .map_err(|e| {
        error!("Serendipity engine error: {}", e);
        StatusCode::BAD_GATEWAY
    })?;

    // 4) Map real Discovery items into the API's connection shape. Each discovery is a
    //    serendipitous link FROM the focus project TO a discovered concept; novelty/impact come
    //    straight from the engine.
    let connections: Vec<SerendipityConnection> = result
        .discoveries
        .iter()
        .take(max_connections)
        .map(|d| {
            let target_concept = d
                .context
                .get("target")
                .or_else(|| d.context.get("domain"))
                .cloned()
                .unwrap_or_else(|| {
                    d.content.chars().take(80).collect::<String>()
                });
            let target_project = d
                .context
                .get("target_project")
                .or_else(|| d.context.get("domain"))
                .cloned()
                .unwrap_or_else(|| "cross-domain".to_string());
            SerendipityConnection {
                id: d.id.to_string(),
                source_project: req.focus_project.clone(),
                target_project,
                source_concept: req.focus_project.clone(),
                target_concept,
                similarity_score: result.novelty_score as f32,
                novelty_score: d.novelty_score as f32,
                connection_type: format!("{:?}", d.discovery_type),
                explanation: d.content.clone(),
                potential_impact: format!("impact_score={:.2}", d.impact_score),
            }
        })
        .collect();

    let count = connections.len();
    info!(
        "Serendipity: {} connections from {} discoveries (novelty={:.2})",
        count,
        result.discoveries.len(),
        result.novelty_score
    );

    Ok(Json(SerendipityDiscoverResponse { connections, count }))
}

// ============================================================================
// COGNITIVE STATE ENDPOINT (iOS Mind tab dashboard)
// ============================================================================

/// One pod row inside an agent session (matches iOS `AgentPod`: name/phase/ready).
#[derive(Serialize)]
struct CognitiveAgentPod {
    name: String,
    phase: String,
    ready: bool,
}

/// An agent/job session row. Field names are camelCase to match the iOS `AgentSession`
/// model, which has NO explicit CodingKeys and the BeagleClient decoder uses NO
/// key-conversion strategy — so Swift decodes by verbatim property name
/// (kind, name, replicas, readyReplicas, createdAt, pods, status, truthMode, action).
#[derive(Serialize)]
struct CognitiveAgentSession {
    kind: String,
    name: String,
    replicas: i32,
    #[serde(rename = "readyReplicas")]
    ready_replicas: i32,
    #[serde(rename = "createdAt")]
    created_at: String,
    pods: Vec<CognitiveAgentPod>,
    status: String,
    #[serde(rename = "truthMode")]
    truth_mode: String,
    action: Option<String>,
}

/// Aggregated cognitive dashboard state. Keys match the iOS `CognitiveState` CodingKeys
/// (snake_case for the top level). Sub-dashboards core_server does not aggregate are
/// returned as null (all iOS fields are optional). `agent_sessions` + `running_agent_count`
/// carry the real running-work data core_server knows about.
#[derive(Serialize)]
struct CognitiveStateResponse {
    hrv: Option<serde_json::Value>,
    recent_drafts: Option<serde_json::Value>,
    triad_latest: Option<serde_json::Value>,
    agent_sessions: Vec<CognitiveAgentSession>,
    recent_void_journeys: Option<serde_json::Value>,
    recent_fractal_trees: Option<serde_json::Value>,
    recent_phi_measurements: Option<serde_json::Value>,
    // Non-iOS-decoded extras (ignored by Swift's decoder, useful for other consumers):
    #[serde(rename = "runningAgentCount")]
    running_agent_count: usize,
    generated_at: String,
    source: String,
}

async fn cognitive_state_handler(
    axum::extract::State(state): axum::extract::State<AppState>,
) -> Json<CognitiveStateResponse> {
    info!("Cognitive state request");

    let mut sessions: Vec<CognitiveAgentSession> = Vec::new();

    // Pipeline runs (JobRegistry) are real in-process agent work core_server tracks.
    for run in state.jobs.list_recent(50).await {
        let (status_str, running) = match &run.status {
            RunStatus::Created => ("created".to_string(), false),
            RunStatus::Running => ("running".to_string(), true),
            RunStatus::Done => ("done".to_string(), false),
            RunStatus::TriadRunning => ("triad_running".to_string(), true),
            RunStatus::TriadDone => ("triad_done".to_string(), false),
            RunStatus::Error(e) => (format!("error: {}", e), false),
        };
        let ready = if running { 1 } else { 0 };
        sessions.push(CognitiveAgentSession {
            kind: "pipeline".to_string(),
            name: run.question.chars().take(80).collect::<String>(),
            replicas: 1,
            ready_replicas: ready,
            created_at: run.created_at.to_rfc3339(),
            pods: vec![CognitiveAgentPod {
                name: run.run_id.clone(),
                phase: status_str.clone(),
                ready: running,
            }],
            status: status_str,
            truth_mode: "measured".to_string(),
            action: None,
        });
    }

    // Science jobs (PBPK / scaffold / helio / PCS / KEC) are also real tracked work.
    for job in state.science_jobs.get_recent_jobs(50).await {
        let status_str = job.status.to_string();
        let running = matches!(job.status, ScienceJobStatus::Running);
        let ready = if running { 1 } else { 0 };
        let kind = serde_json::to_value(&job.kind)
            .ok()
            .and_then(|v| v.as_str().map(|s| s.to_string()))
            .unwrap_or_else(|| "science".to_string());
        sessions.push(CognitiveAgentSession {
            kind: format!("science:{}", kind),
            name: format!("{} job {}", kind, &job.job_id[..job.job_id.len().min(8)]),
            replicas: 1,
            ready_replicas: ready,
            created_at: job.created_at.to_rfc3339(),
            pods: vec![CognitiveAgentPod {
                name: job.job_id.clone(),
                phase: status_str.clone(),
                ready: running,
            }],
            status: status_str,
            truth_mode: "measured".to_string(),
            action: None,
        });
    }

    let running_agent_count = sessions.iter().filter(|s| s.ready_replicas > 0).count();

    Json(CognitiveStateResponse {
        hrv: None,
        recent_drafts: None,
        triad_latest: None,
        agent_sessions: sessions,
        recent_void_journeys: None,
        recent_fractal_trees: None,
        recent_phi_measurements: None,
        running_agent_count,
        generated_at: Utc::now().to_rfc3339(),
        // Honest provenance: core_server only sees its own in-process job registries.
        // Kubernetes/cockpit-managed agent pods are NOT visible here.
        source: "core_server:job_registries".to_string(),
    })
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

// ── Round Table ─────────────────────────────────────────────────

#[derive(Debug, Deserialize)]
struct RoundTableRequest {
    prompt: String,
    #[serde(default)]
    voices: Vec<String>,
}

#[derive(Debug, Serialize)]
struct RoundTableResponse {
    voices: Vec<RoundTableVoice>,
    pci_score: f64,
    synthesis: String,
}

#[derive(Debug, Clone, Serialize)]
struct RoundTableVoice {
    name: String,
    perspective: String,
    content: String,
}

fn truncate_chars(value: &str, max_chars: usize) -> String {
    value.chars().take(max_chars).collect()
}

fn normalize_round_table_voices(requested: &[String]) -> Vec<String> {
    const ALLOWED_VOICES: [&str; 8] = [
        "consciousness",
        "paradox",
        "quantum",
        "void",
        "reality",
        "noetic",
        "fractal",
        "cosmo",
    ];

    let requested = if requested.is_empty() {
        vec![
            "consciousness".to_string(),
            "paradox".to_string(),
            "quantum".to_string(),
        ]
    } else {
        requested.to_vec()
    };

    let mut voices = Vec::new();
    for voice in requested {
        let normalized = voice.trim().to_lowercase();
        if ALLOWED_VOICES.contains(&normalized.as_str()) && !voices.contains(&normalized) {
            voices.push(normalized);
        }
        if voices.len() == 5 {
            break;
        }
    }
    voices
}

fn first_string(value: Option<&serde_json::Value>, keys: &[&str]) -> Option<String> {
    let value = value?;
    keys.iter()
        .filter_map(|key| value.get(*key)?.as_str())
        .map(str::trim)
        .find(|text| !text.is_empty())
        .map(ToOwned::to_owned)
}

fn string_list(value: Option<&serde_json::Value>, key: &str) -> Vec<String> {
    match value.and_then(|v| v.get(key)) {
        Some(serde_json::Value::Array(items)) => items
            .iter()
            .filter_map(|item| item.as_str())
            .map(str::trim)
            .filter(|text| !text.is_empty())
            .map(ToOwned::to_owned)
            .collect(),
        Some(serde_json::Value::String(text)) => text
            .split(['\n', ';'])
            .map(|line| line.trim().trim_start_matches(['-', '*', '•', ' ']))
            .filter(|line| !line.is_empty())
            .map(ToOwned::to_owned)
            .collect(),
        _ => Vec::new(),
    }
}

fn text_points(text: &str, limit: usize) -> Vec<String> {
    text.lines()
        .map(|line| line.trim().trim_start_matches(['-', '*', '•', ' ']))
        .filter(|line| !line.is_empty())
        .take(limit)
        .map(ToOwned::to_owned)
        .collect()
}

fn first_insight(parsed: Option<&serde_json::Value>, text: &str, keys: &[&str]) -> String {
    first_string(parsed, keys)
        .or_else(|| text_points(text, 1).into_iter().next())
        .unwrap_or_else(|| truncate_chars(text.trim(), 700))
}

fn go_deep_ios_response(
    path: &str,
    parsed: Option<&serde_json::Value>,
    output_text: &str,
) -> serde_json::Value {
    let fallback_result = parsed
        .cloned()
        .unwrap_or_else(|| serde_json::json!({ "response": output_text }));

    match path {
        "/dev/deep-research" => {
            let best_hypothesis = first_insight(
                parsed,
                output_text,
                &[
                    "best_hypothesis",
                    "research_summary",
                    "summary",
                    "analysis",
                    "response",
                ],
            );
            let iterations = parsed
                .and_then(|v| v.get("iterations"))
                .and_then(|v| v.as_u64())
                .unwrap_or(1);
            let tree_size = parsed
                .and_then(|v| v.get("tree_size"))
                .and_then(|v| v.as_u64())
                .unwrap_or_else(|| string_list(parsed, "key_findings").len().max(1) as u64);

            serde_json::json!({
                "tree_size": tree_size,
                "best_hypothesis": best_hypothesis,
                "iterations": iterations,
                "result": fallback_result,
            })
        }
        "/dev/swarm" => {
            let mut consensus = string_list(parsed, "consensus");
            if consensus.is_empty() {
                consensus = string_list(parsed, "key_findings");
            }
            if consensus.is_empty() {
                consensus = text_points(output_text, 3);
            }
            if consensus.is_empty() {
                consensus.push(truncate_chars(output_text.trim(), 700));
            }

            let n_agents = parsed
                .and_then(|v| v.get("n_agents").or_else(|| v.get("nAgents")))
                .and_then(|v| v.as_u64())
                .or_else(|| {
                    parsed
                        .and_then(|v| v.get("individual_perspectives"))
                        .and_then(|v| v.as_array())
                        .map(|items| items.len() as u64)
                })
                .unwrap_or(3);
            let iterations = parsed
                .and_then(|v| v.get("iterations"))
                .and_then(|v| v.as_u64())
                .unwrap_or(1);

            serde_json::json!({
                "consensus": consensus,
                "iterations": iterations,
                "n_agents": n_agents,
                "result": fallback_result,
            })
        }
        "/dev/temporal" => {
            let summary = first_insight(
                parsed,
                output_text,
                &["summary", "analysis", "temporal_patterns", "response"],
            );
            serde_json::json!({ "summary": summary, "result": fallback_result })
        }
        "/dev/neurosymbolic" => {
            let summary = first_insight(
                parsed,
                output_text,
                &[
                    "summary",
                    "integrated_conclusion",
                    "neural_insights",
                    "response",
                ],
            );
            serde_json::json!({ "summary": summary, "result": fallback_result })
        }
        "/dev/causal" => {
            if parsed
                .and_then(|v| v.get("nodes"))
                .and_then(|v| v.as_array())
                .is_some()
            {
                fallback_result
            } else {
                let summary =
                    first_insight(parsed, output_text, &["summary", "analysis", "response"]);
                serde_json::json!({
                    "nodes": [],
                    "edges": [],
                    "summary": summary,
                    "result": fallback_result,
                })
            }
        }
        _ => {
            let summary = first_insight(parsed, output_text, &["summary", "analysis", "response"]);
            serde_json::json!({ "summary": summary, "result": fallback_result })
        }
    }
}

async fn round_table_handler(
    axum::extract::State(_state): axum::extract::State<AppState>,
    Json(req): Json<RoundTableRequest>,
) -> Result<Json<RoundTableResponse>, (StatusCode, String)> {
    use beagle_llm::{GrokClient, LlmClient};
    use std::sync::Arc;

    let start = std::time::Instant::now();
    tracing::info!(
        "🎭 /api/v1/round-table — prompt: {}, voices: {:?}",
        req.prompt,
        req.voices
    );

    if req.prompt.trim().is_empty() {
        return Err((
            StatusCode::BAD_REQUEST,
            "Prompt cannot be empty".to_string(),
        ));
    }

    let voices = normalize_round_table_voices(&req.voices);
    if voices.is_empty() {
        return Err((
            StatusCode::BAD_REQUEST,
            "No supported voices requested".to_string(),
        ));
    }

    let llm: Arc<dyn LlmClient> = Arc::new(GrokClient::new());

    // Run all voices in parallel
    let mut handles = Vec::new();
    for voice in &voices {
        let client = llm.clone();
        let voice_name = voice.clone();
        let prompt = req.prompt.clone();

        let perspective = match voice.as_str() {
            "consciousness" => "You are the Consciousness voice — IIT and Global Workspace Theory. What does this trigger in self-referential awareness?",
            "paradox" => "You are the Paradox voice — Gödel incompleteness. Find the paradox. What cannot be proven within the system?",
            "quantum" => "You are the Quantum voice — superposition and interference. Hold contradictions simultaneously. Where do they interfere?",
            "void" => "You are the Void voice — ontological void. What remains when all assumptions dissolve?",
            "reality" => "You are the Reality voice — design an experimental protocol to test this in physical reality.",
            "noetic" => "You are the Noetic voice — collective consciousness. What would a collective mind understand that no individual can?",
            "fractal" => "You are the Fractal voice — recursive patterns. What does this look like at scales above and below?",
            "cosmo" => "You are the Cosmo voice — does this align with physical laws? Thermodynamics? Conservation? Causality?",
            _ => "You are an exotic reasoning voice. Respond with deep insight.",
        };

        let system_prompt = format!(
            "{}\n\nQuestion: {}\n\nRespond concisely (2-3 paragraphs).",
            perspective, prompt
        );

        handles.push(tokio::spawn(async move {
            match client.complete(&system_prompt).await {
                Ok(output) => Some(RoundTableVoice {
                    name: voice_name,
                    perspective: perspective.split('.').next().unwrap_or("").to_string(),
                    content: output.text,
                }),
                Err(e) => {
                    tracing::warn!("Voice {} failed: {}", voice_name, e);
                    None
                }
            }
        }));
    }

    let mut results = Vec::new();
    for handle in handles {
        if let Ok(Some(r)) = handle.await {
            results.push(r);
        }
    }

    if results.is_empty() {
        return Err((
            StatusCode::SERVICE_UNAVAILABLE,
            "All voices failed".to_string(),
        ));
    }

    // Simple PCI
    let pci = if results.len() >= 2 {
        let mut j = 0.0;
        let mut p = 0;
        for i in 0..results.len() {
            for k in (i + 1)..results.len() {
                let a: std::collections::HashSet<&str> =
                    results[i].content.split_whitespace().collect();
                let b: std::collections::HashSet<&str> =
                    results[k].content.split_whitespace().collect();
                j += a.intersection(&b).count() as f64 / a.union(&b).count().max(1) as f64;
                p += 1;
            }
        }
        let avg = j / p.max(1) as f64;
        ((1.0 - avg) * 0.5 + avg * 0.3 + (results.len() as f64 / 9.0).min(1.0) * 0.2).min(1.0)
    } else {
        0.0
    };

    // Synthesis
    let mut ctx = format!(
        "Synthesize these {} perspectives on: {}\n\n",
        results.len(),
        req.prompt
    );
    for v in &results {
        ctx.push_str(&format!(
            "— {}: {}\n\n",
            v.name.to_uppercase(),
            truncate_chars(&v.content, 400)
        ));
    }
    ctx.push_str("Synthesize into 2 paragraphs. What does the collision reveal?");

    let synthesis = match llm.complete(&ctx).await {
        Ok(o) => o.text,
        Err(_) => format!("{} voices responded with PCI {:.2}", results.len(), pci),
    };

    tracing::info!(
        "✅ Round table in {}ms — {} voices, PCI {:.3}",
        start.elapsed().as_millis(),
        results.len(),
        pci
    );

    Ok(Json(RoundTableResponse {
        voices: results,
        pci_score: pci,
        synthesis,
    }))
}

// ── Go Deeper modality handlers ─────────────────────────────────
// These routes implement /dev/swarm, /dev/temporal, /dev/neurosymbolic etc.
// Each modality sends the query to Grok with a modality-specific system prompt
// and returns a structured response matching what the iOS GoDeepStore expects.

async fn go_deep_generic_handler(
    axum::extract::State(_state): axum::extract::State<AppState>,
    uri: axum::http::Uri,
    Json(body): Json<serde_json::Value>,
) -> Result<Json<serde_json::Value>, (StatusCode, String)> {
    use beagle_llm::{GrokClient, LlmClient};

    let path = uri.path();
    let query = body
        .get("research_question")
        .or(body.get("exploration_query"))
        .or(body.get("query"))
        .or(body.get("problem"))
        .and_then(|v| v.as_str())
        .or_else(|| {
            body.get("events")
                .and_then(|v| v.as_array())
                .and_then(|a| a.first())
                .and_then(|v| v.as_str())
        })
        .unwrap_or("no query provided");

    let (modality, system_prompt) = match path {
        "/dev/deep-research" => ("deep_research", "You are a deep research agent. Perform Monte Carlo Tree Search-style reasoning. Provide: research_summary, key_findings (list), methodology, confidence_score (0-1), sources_consulted (list)."),
        "/dev/swarm" => ("swarm", "You are a swarm intelligence agent. Multiple perspectives explore the query simultaneously. Provide: consensus, individual_perspectives (list of {agent, position, confidence}), dissenting_views, exploration_paths."),
        "/dev/temporal" => ("temporal", "You are a temporal multi-scale reasoning agent. Analyze across time scales. Provide: analysis, time_scales (list of {scale, insight}), causal_chains, temporal_patterns."),
        "/dev/neurosymbolic" => ("neurosymbolic", "You are a neuro-symbolic hybrid reasoning agent. Combine neural pattern recognition with symbolic logic. Provide: neural_insights, symbolic_rules (list), integrated_conclusion, confidence."),
        "/dev/causal" => ("causal", "You are a causal reasoning agent. Extract causal relationships. Provide: nodes (list of {id, label}), edges (list of {source, target, strength}), summary."),
        _ => ("generic", "Analyze this deeply and provide structured insights."),
    };

    tracing::info!(
        "🔬 Go Deeper {} — query: {}",
        modality,
        truncate_chars(query, 80)
    );

    let client = GrokClient::new();
    let prompt = format!(
        "{}\n\nQuery: {}\n\nRespond in valid JSON matching the fields described above.",
        system_prompt, query
    );

    match client.complete(&prompt).await {
        Ok(output) => {
            let parsed = serde_json::from_str::<serde_json::Value>(&output.text).ok();
            Ok(Json(go_deep_ios_response(
                path,
                parsed.as_ref(),
                &output.text,
            )))
        }
        Err(e) => {
            tracing::error!("Go Deeper {} failed: {}", modality, e);
            Err((StatusCode::INTERNAL_SERVER_ERROR, e.to_string()))
        }
    }
}

async fn go_deep_debate_handler(
    axum::extract::State(state): axum::extract::State<AppState>,
    Json(body): Json<serde_json::Value>,
) -> Result<Json<serde_json::Value>, (StatusCode, String)> {
    // Real Triad debate via beagle_triad::run_triad (ATHENA/HERMES/ARGOS/Judge,
    // each routed through the TieredRouter inside the crate). We mint a real
    // run_id so iOS feedback can correlate via POST /api/v1/feedback.

    let topic = body
        .get("topic")
        .or_else(|| body.get("prompt"))
        .and_then(|v| v.as_str())
        .unwrap_or("no topic")
        .to_string();
    let run_id = format!("debate_{}", Uuid::new_v4());
    info!(
        "🥊 /dev/debate (run_id={}) — topic: {}",
        run_id,
        truncate_chars(&topic, 80)
    );

    // run_triad reads a draft from disk; seed one with the topic as the draft
    // under BEAGLE_DATA_DIR so the Triad has material to critique.
    let data_dir = beagle_data_dir();
    let debate_dir = data_dir.join("debate").join(&run_id);
    if let Err(e) = std::fs::create_dir_all(&debate_dir) {
        return Err((StatusCode::INTERNAL_SERVER_ERROR, e.to_string()));
    }
    let draft_path = debate_dir.join("draft.md");
    let seed_draft = format!(
        "# Debate Topic\n\n{}\n\nProvide a rigorous, well-structured analysis of this topic.\n",
        topic
    );
    if let Err(e) = std::fs::write(&draft_path, &seed_draft) {
        return Err((StatusCode::INTERNAL_SERVER_ERROR, e.to_string()));
    }

    let triad_input = TriadInput {
        run_id: run_id.clone(),
        draft_path,
        context_summary: Some(format!("Debate topic: {}", topic)),
    };

    let ctx = state.ctx.lock().await;
    let report = match run_triad(&triad_input, &ctx).await {
        Ok(r) => r,
        Err(e) => {
            error!("Triad debate failed (run_id={}): {}", run_id, e);
            return Err((StatusCode::INTERNAL_SERVER_ERROR, e.to_string()));
        }
    };
    drop(ctx);

    // Map the three opinions to named agents for the iOS TriadResult shape.
    let find = |agent: &str| report.opinions.iter().find(|o| o.agent.eq_ignore_ascii_case(agent));
    let athena = find("ATHENA");
    let hermes = find("HERMES");
    let argos = find("ARGOS");
    let opinion_json = |o: Option<&beagle_triad::TriadOpinion>| match o {
        Some(o) => serde_json::json!({
            "agent": o.agent,
            "opinion": o.summary,
            "confidence": o.score,
        }),
        None => serde_json::json!(null),
    };

    let athena_score = athena.map(|o| o.score).unwrap_or(0.0);
    let hermes_score = hermes.map(|o| o.score).unwrap_or(0.0);
    let argos_score = argos.map(|o| o.score).unwrap_or(0.0);
    let judge_score = ((athena_score + hermes_score + argos_score) / 3.0).clamp(0.0, 1.0);

    Ok(Json(serde_json::json!({
        "run_id": run_id,
        "athena": opinion_json(athena),
        "hermes": opinion_json(hermes),
        "argos": opinion_json(argos),
        "judge": {
            "agent": "JUDGE",
            "opinion": report.final_draft,
            "confidence": judge_score,
        },
        "consensus": report.final_draft,
        "scores": {
            "athena": athena_score,
            "hermes": hermes_score,
            "argos": argos_score,
            "judge": judge_score,
        },
    })))
}

// ════════════════════════════════════════════════════════════════════════
// Wave 3 — RESTORED reasoning engines (quantum, adversarial, causal,
// worldmodel counterfactual, hyperedges, debate-via-triad, feedback).
// Ported from the retired beagle-server endpoints onto their real engine
// crates and wired into the authenticated route group.
// ════════════════════════════════════════════════════════════════════════

// ── POST /dev/quantum-reasoning ──────────────────────────────────
// Real quantum-inspired reasoning: superposition + interference + measurement
// from beagle_agents::quantum. Ported from a0c4d8e quantum_endpoint.rs.

#[derive(Deserialize)]
struct QuantumHypothesisInput {
    content: String,
    #[serde(default = "default_initial_probability")]
    initial_probability: f64,
    #[serde(default)]
    confidence: f64,
    #[serde(default)]
    source: String,
}

fn default_initial_probability() -> f64 {
    0.5
}

#[derive(Deserialize)]
struct QuantumReasoningRequest {
    hypotheses: Vec<QuantumHypothesisInput>,
    #[serde(default)]
    correlation_matrix: Option<Vec<Vec<f64>>>,
    #[serde(default = "default_quantum_threshold")]
    threshold: f64,
    #[serde(default = "default_interference_strength")]
    interference_strength: f64,
    #[serde(default)]
    probabilistic: bool,
    #[serde(default)]
    apply_decoherence: bool,
}

fn default_quantum_threshold() -> f64 {
    0.15
}

fn default_interference_strength() -> f64 {
    1.0
}

#[derive(Serialize)]
struct QuantumRankedHypothesis {
    content: String,
    probability: f64,
    confidence: f64,
}

#[derive(Serialize)]
struct QuantumMetadata {
    total_hypotheses: usize,
    interference_applied: bool,
    decoherence_applied: bool,
    processing_time_ms: u64,
}

#[derive(Serialize)]
struct QuantumReasoningResponse {
    selected_hypothesis: String,
    probability: f64,
    ranked_hypotheses: Vec<QuantumRankedHypothesis>,
    alternatives: Vec<QuantumRankedHypothesis>,
    metadata: QuantumMetadata,
}

async fn quantum_reasoning_handler(
    axum::extract::State(_state): axum::extract::State<AppState>,
    Json(req): Json<QuantumReasoningRequest>,
) -> Result<Json<QuantumReasoningResponse>, (StatusCode, String)> {
    use beagle_agents::{
        HypothesisMetadata, InterferenceEngine, MeasurementOperator, SuperpositionState,
    };

    let start = std::time::Instant::now();
    info!(
        "🌀 Quantum reasoning request with {} hypotheses",
        req.hypotheses.len()
    );

    if req.hypotheses.is_empty() {
        return Err((StatusCode::BAD_REQUEST, "empty hypotheses".into()));
    }
    if req.hypotheses.len() > 100 {
        return Err((StatusCode::BAD_REQUEST, "too many hypotheses (max 100)".into()));
    }

    // Build superposition state with all hypotheses.
    let mut superposition = SuperpositionState::new();
    for (i, hyp) in req.hypotheses.iter().enumerate() {
        let metadata = HypothesisMetadata {
            source: if hyp.source.is_empty() {
                "user".to_string()
            } else {
                hyp.source.clone()
            },
            confidence: hyp.confidence,
            evidence_count: 0,
            created_at: i as f64,
        };
        superposition.add_hypothesis(
            hyp.content.clone(),
            hyp.initial_probability.clamp(0.001, 0.999),
            metadata,
        );
    }
    superposition.normalize();

    // Apply interference (custom matrix, or auto-generated for small sets).
    let mut interference_applied = false;
    if req.hypotheses.len() > 1 {
        let mut engine = InterferenceEngine::with_strength(req.interference_strength);
        if let Some(matrix) = &req.correlation_matrix {
            if matrix.len() == req.hypotheses.len()
                && matrix.iter().all(|row| row.len() == req.hypotheses.len())
            {
                engine.apply_global_interference(&mut superposition, matrix);
                interference_applied = true;
            } else {
                warn!("Invalid correlation matrix dimensions, skipping interference");
            }
        } else if req.hypotheses.len() <= 10 {
            let n = req.hypotheses.len();
            let mut auto_matrix = vec![vec![0.0; n]; n];
            for i in 0..n {
                for j in (i + 1)..n {
                    let correlation = if j == i + 1 { 0.3 } else { 0.0 };
                    auto_matrix[i][j] = correlation;
                    auto_matrix[j][i] = correlation;
                }
            }
            engine.apply_global_interference(&mut superposition, &auto_matrix);
            interference_applied = true;
        }
    }

    // Optional decoherence before measurement.
    let mut decoherence_applied = false;
    if req.apply_decoherence {
        let op = MeasurementOperator::with_decoherence(req.threshold, 0.1);
        op.apply_decoherence(&mut superposition, 5.0);
        decoherence_applied = true;
    }

    // Measurement / wavefunction collapse.
    let op = MeasurementOperator::new(req.threshold);
    let measurement = if req.probabilistic {
        op.probabilistic_collapse(&mut superposition)
    } else {
        op.collapse(&mut superposition)
    };
    let result = measurement.ok_or((
        StatusCode::UNPROCESSABLE_ENTITY,
        "no viable hypothesis above threshold".to_string(),
    ))?;

    let ranked_hypotheses: Vec<QuantumRankedHypothesis> = superposition
        .get_ranked_hypotheses()
        .iter()
        .map(|(content, prob, _)| QuantumRankedHypothesis {
            content: content.clone(),
            probability: *prob,
            confidence: *prob,
        })
        .collect();

    let alternatives: Vec<QuantumRankedHypothesis> = result
        .collapsed_alternatives
        .iter()
        .map(|(content, prob)| QuantumRankedHypothesis {
            content: content.clone(),
            probability: *prob,
            confidence: *prob,
        })
        .collect();

    let elapsed = start.elapsed().as_millis() as u64;
    info!(
        "✅ Quantum reasoning in {}ms: '{}' (p={:.3})",
        elapsed, result.selected_hypothesis, result.probability
    );

    Ok(Json(QuantumReasoningResponse {
        selected_hypothesis: result.selected_hypothesis,
        probability: result.probability,
        ranked_hypotheses,
        alternatives,
        metadata: QuantumMetadata {
            total_hypotheses: req.hypotheses.len(),
            interference_applied,
            decoherence_applied,
            processing_time_ms: elapsed,
        },
    }))
}

// ── POST /dev/adversarial-compete ────────────────────────────────
// Real adversarial self-play tournament. We keep beagle_agents::adversarial's
// Strategy/ResearchPlayer for diverse strategy generation + ELO bookkeeping,
// but drive the actual LLM competition through the project's TieredRouter
// (Grok / local fleet) — exactly like pcs_reason_handler / llm_complete_handler.
// No Anthropic key required: matches route through whatever the router selects.
//
// Each of `rounds` rounds: every player produces a competing answer to `query`
// (prompted with its distinct strategy/angle, routed via the router), then a
// judge prompt scores every answer (0..1) and picks a winner. Per-round ELO is
// updated pairwise for each player against the round's mean opponent ELO based
// on whether the player beat the round median judge-score. Final ranking +
// winner come from the accumulated ELO.

#[derive(Deserialize)]
struct AdversarialCompeteRequest {
    query: String,
    #[serde(default = "default_player_count")]
    player_count: usize,
    // Accepted for request-shape compatibility with the iOS client; the
    // router-driven tournament does not branch on a bracket format.
    #[serde(default)]
    #[allow(dead_code)]
    format: String,
    #[serde(default = "default_adversarial_rounds")]
    rounds: usize,
}

fn default_player_count() -> usize {
    4
}

fn default_adversarial_rounds() -> usize {
    3
}

#[derive(Serialize)]
struct AdversarialAgentInfo {
    name: String,
    score: f64,
    strategy: String,
}

#[derive(Serialize)]
struct AdversarialCompeteResponse {
    winner: String,
    agents: Vec<AdversarialAgentInfo>,
    rounds: usize,
    summary: String,
}

fn create_diverse_strategies(count: usize) -> Vec<beagle_agents::Strategy> {
    use beagle_agents::Strategy;
    let base = vec![
        Strategy::new_aggressive(),
        Strategy::new_conservative(),
        Strategy::new_exploratory(),
        Strategy::new_exploitative(),
    ];
    let mut out = Vec::new();
    for i in 0..count {
        let b = &base[i % base.len()];
        if i < base.len() {
            out.push(b.clone());
        } else {
            out.push(b.mutate());
        }
    }
    out
}

/// Distinct angle/instruction for each research approach so the competing
/// players actually argue from different stances (not just temperature noise).
fn strategy_angle(approach: &beagle_agents::ResearchApproach) -> &'static str {
    use beagle_agents::ResearchApproach;
    match approach {
        ResearchApproach::Aggressive => {
            "Take a bold, contrarian stance. Propose the most novel, high-risk/high-reward \
             answer and defend it forcefully."
        }
        ResearchApproach::Conservative => {
            "Take a careful, well-grounded stance. Prefer the safest, most defensible answer \
             with strong evidentiary support and minimal speculation."
        }
        ResearchApproach::Exploratory => {
            "Take a divergent, exploratory stance. Surface non-obvious angles, surprising \
             connections, and creative possibilities others would miss."
        }
        ResearchApproach::Exploitative => {
            "Take a focused, optimizing stance. Refine the single strongest known line of \
             reasoning to its sharpest, most actionable form."
        }
    }
}

async fn adversarial_compete_handler(
    axum::extract::State(state): axum::extract::State<AppState>,
    Json(req): Json<AdversarialCompeteRequest>,
) -> Result<Json<AdversarialCompeteResponse>, (StatusCode, String)> {
    use beagle_agents::ResearchPlayer;

    if req.player_count < 2 {
        return Err((StatusCode::BAD_REQUEST, "need at least 2 players".into()));
    }
    if req.player_count > 32 {
        return Err((StatusCode::BAD_REQUEST, "too many players (max 32)".into()));
    }
    let rounds = req.rounds.clamp(1, 10);

    info!(
        "🥊 Adversarial competition (router-driven): {} players, {} rounds on '{}'",
        req.player_count,
        rounds,
        truncate_chars(&req.query, 80)
    );

    let mut players: Vec<ResearchPlayer> = create_diverse_strategies(req.player_count)
        .into_iter()
        .enumerate()
        .map(|(i, s)| ResearchPlayer::new(format!("Player_{i}"), s))
        .collect();

    let mut ctx = state.ctx.lock().await;
    let run_id = "http_adversarial_compete";

    // Real multi-agent competition driven by the TieredRouter (Grok / local
    // fleet), not a hardcoded Claude client. Each round every player produces a
    // competing answer (prompted from its distinct strategy), then a judge
    // scores them 0..1; per-round ELO is updated vs the round median.
    for round in 0..rounds {
        info!("Round {}/{}", round + 1, rounds);

        // 1) Each player generates a competing answer via the router.
        let mut answers: Vec<String> = Vec::with_capacity(players.len());
        for player in players.iter() {
            let angle = strategy_angle(&player.strategy.approach);
            let boldness = player
                .strategy
                .parameters
                .get("boldness")
                .copied()
                .unwrap_or(0.5);
            let prompt = format!(
                "You are {name}, a research agent competing in an adversarial tournament.\n\
                 QUERY: {query}\n\n\
                 YOUR STRATEGY ({approach:?}, boldness {boldness:.2}): {angle}\n\n\
                 Produce your single best competing answer to the QUERY (max ~180 words). \
                 Be concrete and persuasive; you are being scored against rival agents on \
                 novelty, plausibility, and usefulness.",
                name = player.name,
                query = req.query,
                approach = player.strategy.approach,
                angle = angle,
                boldness = boldness,
            );

            let meta = RequestMeta::from_prompt(&prompt);
            let current_stats = ctx.llm_stats.get_or_create(run_id);
            let (client, tier) = ctx.router.choose_with_limits(&meta, &current_stats);
            let text = ctx
                .router
                .complete_chosen(&client, tier, &prompt)
                .await
                .map_err(|e| {
                    warn!("Adversarial player completion failed: {e}");
                    (StatusCode::BAD_GATEWAY, format!("router error: {e}"))
                })?;
            let tokens_in_est = (prompt.len() / 4) as u32;
            let tokens_out_est = (text.len() / 4) as u32;
            ctx.llm_stats.update(run_id, |stats| match tier {
                ProviderTier::Grok4Heavy => {
                    stats.grok4_calls += 1;
                    stats.grok4_tokens_in += tokens_in_est;
                    stats.grok4_tokens_out += tokens_out_est;
                }
                _ => {
                    stats.grok3_calls += 1;
                    stats.grok3_tokens_in += tokens_in_est;
                    stats.grok3_tokens_out += tokens_out_est;
                }
            });
            answers.push(text);
        }

        // 2) Judge scores every answer 0..1 via the router (high-quality tier).
        let mut judge_prompt = format!(
            "You are an impartial scientific judge in an adversarial research tournament.\n\
             QUERY: {query}\n\n\
             Score each competing ANSWER from 0.0 to 1.0 on novelty, plausibility, and \
             usefulness combined. Be discriminating — do not give everyone the same score.\n\n",
            query = req.query
        );
        for (i, ans) in answers.iter().enumerate() {
            judge_prompt.push_str(&format!(
                "ANSWER {i} ({name}):\n{body}\n\n",
                i = i,
                name = players[i].name,
                body = truncate_chars(ans, 1200)
            ));
        }
        judge_prompt.push_str(&format!(
            "Respond with ONLY a JSON object of the exact shape \
             {{ \"scores\": [<{n} numbers in 0.0..1.0, one per ANSWER in order>] }}. \
             No prose, no markdown.",
            n = players.len()
        ));

        let mut judge_meta = RequestMeta::from_prompt(&judge_prompt);
        judge_meta.requires_high_quality = true;
        // judge stays on the high-quality tier (not critical) to avoid the misconfigured deepseek-math math tier
        let current_stats = ctx.llm_stats.get_or_create(run_id);
        let (jclient, jtier) = ctx.router.choose_with_limits(&judge_meta, &current_stats);
        let judge_text = ctx
            .router
            .complete_chosen(&jclient, jtier, &judge_prompt)
            .await
            .map_err(|e| {
                warn!("Adversarial judge completion failed: {e}");
                (StatusCode::BAD_GATEWAY, format!("judge router error: {e}"))
            })?;
        let j_in = (judge_prompt.len() / 4) as u32;
        let j_out = (judge_text.len() / 4) as u32;
        ctx.llm_stats.update(run_id, |stats| match jtier {
            ProviderTier::Grok4Heavy => {
                stats.grok4_calls += 1;
                stats.grok4_tokens_in += j_in;
                stats.grok4_tokens_out += j_out;
            }
            _ => {
                stats.grok3_calls += 1;
                stats.grok3_tokens_in += j_in;
                stats.grok3_tokens_out += j_out;
            }
        });

        // 3) Parse judge scores (tolerant); fill any gaps with a neutral 0.5.
        let mut scores: Vec<f64> = parse_first_json_object(&judge_text)
            .and_then(|v| {
                v.get("scores").and_then(|s| s.as_array()).map(|arr| {
                    arr.iter()
                        .map(|x| x.as_f64().unwrap_or(0.5).clamp(0.0, 1.0))
                        .collect::<Vec<f64>>()
                })
            })
            .unwrap_or_default();
        scores.resize(players.len(), 0.5);

        // 4) Turn this round's judge scores into pairwise ELO updates: each
        // player is graded vs the round median (>= median → win, else loss)
        // against the mean opponent ELO. Genuinely competitive, judge-driven.
        let mut sorted = scores.clone();
        sorted.sort_by(|a, b| a.partial_cmp(b).unwrap_or(std::cmp::Ordering::Equal));
        let median = sorted[sorted.len() / 2];
        let mean_elo: f64 =
            players.iter().map(|p| p.elo_rating).sum::<f64>() / players.len() as f64;
        for (i, player) in players.iter_mut().enumerate() {
            if scores[i] >= median {
                player.record_win(mean_elo);
            } else {
                player.record_loss(mean_elo);
            }
        }
    }

    drop(ctx);

    let champion = players
        .iter()
        .max_by(|a, b| {
            a.elo_rating
                .partial_cmp(&b.elo_rating)
                .unwrap_or(std::cmp::Ordering::Equal)
        })
        .cloned()
        .ok_or((StatusCode::INTERNAL_SERVER_ERROR, "no players".to_string()))?;

    let agents: Vec<AdversarialAgentInfo> = players
        .iter()
        .map(|p| AdversarialAgentInfo {
            name: p.name.clone(),
            score: p.elo_rating,
            strategy: format!("{:?}", p.strategy.approach),
        })
        .collect();

    info!(
        "✅ Competition complete: champion {} (ELO {:.1})",
        champion.name, champion.elo_rating,
    );

    Ok(Json(AdversarialCompeteResponse {
        winner: champion.name.clone(),
        agents,
        rounds,
        summary: format!(
            "Champion {} ({:?}) won with ELO {:.1} over {} players across {} judged rounds \
             (routed via the tiered router, not a hardcoded Claude client).",
            champion.name,
            champion.strategy.approach,
            champion.elo_rating,
            players.len(),
            rounds,
        ),
    }))
}

// ── POST /dev/causal/intervention & /api/worldmodel/counterfactual ─
// Both back onto beagle_worldmodel::CounterfactualReasoner. The iOS app
// sends free text; we parse a structured Intervention out of it, run the
// abduction-action-prediction loop, and summarize the resulting WorldState.

/// Parse free-text like "increase temperature to 25, reduce pressure by 3"
/// into a structured beagle_worldmodel::Intervention with numeric targets,
/// plus a seeded WorldState carrying those variables so the reasoner has
/// something to intervene on.
fn parse_intervention_freetext(
    text: &str,
) -> (
    beagle_worldmodel::Intervention,
    beagle_worldmodel::WorldState,
) {
    use beagle_worldmodel::counterfactual::InterventionTarget;
    use beagle_worldmodel::state::{BeliefState, Entity, EntityType, Properties};
    use beagle_worldmodel::{Intervention, WorldState};

    let mut intervention = Intervention::default();
    let mut props = Properties::new();

    // Heuristic numeric extraction: look for "<verb> <var> ... <number>".
    // We scan tokens and pair the nearest preceding alphabetic word with each
    // number, choosing SetValue/Shift/Scale from nearby verbs.
    let lower = text.to_lowercase();
    let tokens: Vec<&str> = lower.split(|c: char| !c.is_alphanumeric() && c != '.' && c != '-').filter(|t| !t.is_empty()).collect();

    let mut last_word: Option<String> = None;
    let mut verb_scale = false;
    let mut verb_shift = false;
    for tok in &tokens {
        match *tok {
            "scale" | "multiply" | "double" | "triple" => verb_scale = true,
            "increase" | "raise" | "add" | "boost" => {
                verb_shift = true;
            }
            "decrease" | "reduce" | "lower" | "drop" | "cut" => {
                verb_shift = true;
            }
            _ => {}
        }
        if let Ok(num) = tok.parse::<f64>() {
            if let Some(var) = last_word.clone() {
                let target = if verb_scale {
                    InterventionTarget::Scale(num)
                } else if verb_shift {
                    InterventionTarget::Shift(num)
                } else {
                    InterventionTarget::SetValue(num)
                };
                // Seed the world with a baseline value so Shift/Scale have an effect.
                props.set_number(var.clone(), 1.0);
                intervention.targets.insert(var, target);
                verb_scale = false;
                verb_shift = false;
            }
        } else if tok.chars().next().map(|c| c.is_alphabetic()).unwrap_or(false) {
            // Track candidate variable names (skip common verbs/stopwords).
            if !matches!(
                *tok,
                "to" | "by" | "the" | "a" | "of" | "and" | "with" | "for" | "what" | "if"
                    | "scale" | "multiply" | "increase" | "raise" | "add" | "decrease"
                    | "reduce" | "lower" | "drop" | "cut" | "double" | "triple" | "boost"
            ) {
                last_word = Some((*tok).to_string());
            }
        }
    }

    // Fallback: if no targets parsed, set a generic "outcome" variable so the
    // reasoner still produces a non-trivial counterfactual world.
    if intervention.targets.is_empty() {
        props.set_number("outcome".to_string(), 1.0);
        intervention
            .targets
            .insert("outcome".to_string(), InterventionTarget::SetValue(0.0));
    }

    let mut state = WorldState::new();
    let entity = Entity {
        id: uuid::Uuid::new_v4(),
        entity_type: EntityType::Object("scenario".to_string()),
        properties: props,
        spatial: None,
        temporal: None,
        beliefs: BeliefState::new_uniform(10),
        active: true,
    };
    state.add_entity(entity);

    (intervention, state)
}

/// Summarize a WorldState into a human-readable string of its numeric vars.
fn summarize_world_state(state: &beagle_worldmodel::WorldState) -> String {
    let mut parts: Vec<String> = Vec::new();
    for entity in state.entities.values() {
        for (k, v) in &entity.properties.numbers {
            parts.push(format!("{k}={v:.3}"));
        }
    }
    for (k, v) in &state.globals.numbers {
        parts.push(format!("{k}={v:.3}"));
    }
    if parts.is_empty() {
        format!("world state has {} entities, uncertainty {:.3}", state.entities.len(), state.uncertainty)
    } else {
        parts.sort();
        format!(
            "{} (uncertainty {:.3})",
            parts.join(", "),
            state.uncertainty
        )
    }
}

async fn run_counterfactual(
    text: &str,
) -> Result<(beagle_worldmodel::WorldState, beagle_worldmodel::WorldState), String> {
    use beagle_worldmodel::CounterfactualReasoner;

    let (intervention, factual) = parse_intervention_freetext(text);
    let reasoner = CounterfactualReasoner::new();
    let counterfactual = reasoner
        .reason(&factual, intervention)
        .await
        .map_err(|e| e.to_string())?;
    Ok((factual, counterfactual))
}

#[derive(Deserialize)]
struct CausalInterventionRequest {
    #[serde(default)]
    graph_id: String,
    #[serde(default)]
    intervention: String,
    #[serde(default)]
    query: String,
}

#[derive(Serialize)]
struct CausalInterventionResponse {
    outcome: String,
    effect: String,
    confidence: f64,
}

async fn causal_intervention_handler(
    axum::extract::State(_state): axum::extract::State<AppState>,
    Json(req): Json<CausalInterventionRequest>,
) -> Result<Json<CausalInterventionResponse>, (StatusCode, String)> {
    let text = if !req.intervention.is_empty() {
        req.intervention.clone()
    } else if !req.query.is_empty() {
        req.query.clone()
    } else {
        return Err((StatusCode::BAD_REQUEST, "empty intervention".into()));
    };

    info!(
        "🔗 Causal intervention (graph={}): {}",
        req.graph_id,
        truncate_chars(&text, 80)
    );

    let (factual, counterfactual) = run_counterfactual(&text)
        .await
        .map_err(|e| (StatusCode::INTERNAL_SERVER_ERROR, e))?;

    // Confidence: shrink with the relative uncertainty growth of the cf world.
    let confidence = (1.0 / (1.0 + (counterfactual.uncertainty - factual.uncertainty).abs()))
        .clamp(0.0, 1.0);

    Ok(Json(CausalInterventionResponse {
        outcome: summarize_world_state(&counterfactual),
        effect: format!(
            "Intervention shifted the world from [{}] to [{}].",
            summarize_world_state(&factual),
            summarize_world_state(&counterfactual)
        ),
        confidence,
    }))
}

#[derive(Deserialize)]
struct WorldModelCounterfactualRequest {
    #[serde(default)]
    query: String,
    #[serde(default)]
    context: String,
}

#[derive(Serialize)]
struct WorldModelCounterfactualResponse {
    result: serde_json::Value,
    summary: String,
}

async fn worldmodel_counterfactual_handler(
    axum::extract::State(_state): axum::extract::State<AppState>,
    Json(req): Json<WorldModelCounterfactualRequest>,
) -> Result<Json<WorldModelCounterfactualResponse>, (StatusCode, String)> {
    let text = if !req.query.is_empty() {
        req.query.clone()
    } else if !req.context.is_empty() {
        req.context.clone()
    } else {
        return Err((StatusCode::BAD_REQUEST, "empty query".into()));
    };

    info!(
        "🌍 World model counterfactual: {}",
        truncate_chars(&text, 80)
    );

    let (factual, counterfactual) = run_counterfactual(&text)
        .await
        .map_err(|e| (StatusCode::INTERNAL_SERVER_ERROR, e))?;

    let result = serde_json::json!({
        "factual": summarize_world_state(&factual),
        "counterfactual": summarize_world_state(&counterfactual),
        "factual_uncertainty": factual.uncertainty,
        "counterfactual_uncertainty": counterfactual.uncertainty,
        "entities": counterfactual.entities.len(),
    });

    Ok(Json(WorldModelCounterfactualResponse {
        summary: format!(
            "Counterfactual world: {}",
            summarize_world_state(&counterfactual)
        ),
        result,
    }))
}

// ── GET + POST /api/hyperedges ───────────────────────────────────
// Backed by beagle_hypergraph::PostgresStorage (StorageRepository).
// GET ?node_id= lists edges for a node (or all); POST {label,node_ids}
// creates a hyperedge. Needs DATABASE_URL — returns 503 if not configured.

async fn hyperedge_storage() -> Result<beagle_hypergraph::PostgresStorage, (StatusCode, String)> {
    let db_url = std::env::var("DATABASE_URL")
        .or_else(|_| std::env::var("HERMES_DATABASE_URL"))
        .map_err(|_| {
            (
                StatusCode::SERVICE_UNAVAILABLE,
                "DATABASE_URL not configured — hyperedge store unavailable".to_string(),
            )
        })?;
    let storage = beagle_hypergraph::PostgresStorage::new(&db_url)
        .await
        .map_err(|e| {
            (
                StatusCode::SERVICE_UNAVAILABLE,
                format!("failed to connect hyperedge store: {e}"),
            )
        })?;
    // Ensure the hypergraph schema exists (idempotent; creates tables/extensions on first use).
    storage.migrate().await.map_err(|e| {
        (
            StatusCode::SERVICE_UNAVAILABLE,
            format!("hyperedge schema migrate failed: {e}"),
        )
    })?;
    Ok(storage)
}

#[derive(Serialize)]
struct HyperedgeJson {
    id: String,
    label: String,
    node_ids: Vec<String>,
    directed: bool,
    created_at: String,
}

fn hyperedge_to_json(edge: &beagle_hypergraph::Hyperedge) -> HyperedgeJson {
    HyperedgeJson {
        id: edge.id.to_string(),
        label: edge.edge_type.clone(),
        node_ids: edge.node_ids.iter().map(|n| n.to_string()).collect(),
        directed: edge.directed,
        created_at: edge.created_at.to_rfc3339(),
    }
}

#[derive(Deserialize)]
struct HyperedgesQuery {
    node_id: Option<String>,
}

async fn hyperedges_list_handler(
    axum::extract::State(_state): axum::extract::State<AppState>,
    axum::extract::Query(q): axum::extract::Query<HyperedgesQuery>,
) -> Result<Json<Vec<HyperedgeJson>>, (StatusCode, String)> {
    use beagle_hypergraph::storage::StorageRepository;

    let storage = hyperedge_storage().await?;
    let node_filter = match &q.node_id {
        Some(s) => Some(uuid::Uuid::parse_str(s).map_err(|_| {
            (StatusCode::BAD_REQUEST, format!("invalid node_id uuid: {s}"))
        })?),
        None => None,
    };

    let edges = storage
        .list_hyperedges(node_filter)
        .await
        .map_err(|e| (StatusCode::INTERNAL_SERVER_ERROR, e.to_string()))?;

    info!("📐 Listed {} hyperedges (node={:?})", edges.len(), q.node_id);
    Ok(Json(edges.iter().map(hyperedge_to_json).collect()))
}

#[derive(Deserialize)]
struct CreateHyperedgeRequest {
    label: String,
    node_ids: Vec<String>,
    #[serde(default)]
    directed: bool,
}

async fn hyperedges_create_handler(
    axum::extract::State(_state): axum::extract::State<AppState>,
    Json(req): Json<CreateHyperedgeRequest>,
) -> Result<Json<HyperedgeJson>, (StatusCode, String)> {
    use beagle_hypergraph::storage::StorageRepository;
    use beagle_hypergraph::Hyperedge;

    let node_ids: Vec<uuid::Uuid> = req
        .node_ids
        .iter()
        .map(|s| {
            uuid::Uuid::parse_str(s)
                .map_err(|_| (StatusCode::BAD_REQUEST, format!("invalid node_id uuid: {s}")))
        })
        .collect::<Result<_, _>>()?;

    let edge = Hyperedge::new(req.label.clone(), node_ids, req.directed, "beagle-core".to_string())
        .map_err(|e| (StatusCode::BAD_REQUEST, e.to_string()))?;

    let storage = hyperedge_storage().await?;
    let created = storage
        .create_hyperedge(edge)
        .await
        .map_err(|e| (StatusCode::INTERNAL_SERVER_ERROR, e.to_string()))?;

    info!("📐 Created hyperedge {} '{}'", created.id, created.edge_type);
    Ok(Json(hyperedge_to_json(&created)))
}

// ── POST /api/v1/feedback ────────────────────────────────────────
// Persists human feedback for a run via beagle_feedback (JSONL under
// BEAGLE_DATA_DIR). Lets the iOS feedback loop correlate by run_id.

#[derive(Deserialize)]
struct FeedbackRequest {
    run_id: String,
    #[serde(default)]
    event_type: String,
    #[serde(default)]
    rating_0_10: Option<u8>,
    #[serde(default)]
    notes: Option<String>,
}

#[derive(Serialize)]
struct FeedbackAckResponse {
    ok: bool,
    event_id: String,
    status: String,
}

async fn feedback_handler(
    axum::extract::State(_state): axum::extract::State<AppState>,
    Json(req): Json<FeedbackRequest>,
) -> Result<Json<FeedbackAckResponse>, (StatusCode, String)> {
    use beagle_feedback::create_human_feedback_event;

    if req.run_id.is_empty() {
        return Err((StatusCode::BAD_REQUEST, "run_id required".into()));
    }

    // accepted heuristic: rating >= 6 (out of 10) counts as accepted.
    let accepted = req.rating_0_10.map(|r| r >= 6).unwrap_or(true);

    let mut event = create_human_feedback_event(
        req.run_id.clone(),
        accepted,
        req.rating_0_10,
        req.notes.clone(),
    );
    // Stamp the event_type label into notes if a non-default kind was supplied.
    if !req.event_type.is_empty() && req.event_type != "human_feedback" {
        let tag = format!("[event_type={}]", req.event_type);
        event.notes = Some(match event.notes.take() {
            Some(n) => format!("{tag} {n}"),
            None => tag,
        });
    }

    let data_dir = beagle_data_dir();
    beagle_feedback::append_event(&data_dir, &event)
        .map_err(|e| (StatusCode::INTERNAL_SERVER_ERROR, e.to_string()))?;

    let event_id = Uuid::new_v4().to_string();
    info!(
        "📝 Feedback recorded for run {} (rating={:?})",
        req.run_id, req.rating_0_10
    );

    Ok(Json(FeedbackAckResponse {
        ok: true,
        event_id,
        status: "recorded".to_string(),
    }))
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

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn truncate_chars_respects_utf8_boundaries() {
        let value = format!("{}é🚀", "a".repeat(399));
        let truncated = truncate_chars(&value, 400);
        assert_eq!(truncated.chars().count(), 400);
        assert!(truncated.ends_with('é'));
    }

    #[test]
    fn go_deep_deep_research_shape_matches_swift_contract() {
        let parsed = serde_json::json!({
            "research_summary": "Beagle precisa parecer continuidade.",
            "key_findings": ["Home primeiro", "MCP como sistema nervoso"]
        });
        let response = go_deep_ios_response("/dev/deep-research", Some(&parsed), "fallback");
        assert!(
            response
                .get("tree_size")
                .and_then(|v| v.as_u64())
                .unwrap_or(0)
                >= 1
        );
        assert_eq!(
            response.get("best_hypothesis").and_then(|v| v.as_str()),
            Some("Beagle precisa parecer continuidade.")
        );
        assert!(response.get("iterations").is_some());
    }

    #[test]
    fn round_table_voices_are_deduped_allowed_and_capped() {
        let voices = normalize_round_table_voices(&[
            "Quantum".to_string(),
            "quantum".to_string(),
            "invalid".to_string(),
            "void".to_string(),
            "reality".to_string(),
            "noetic".to_string(),
            "fractal".to_string(),
            "cosmo".to_string(),
        ]);
        assert_eq!(
            voices,
            vec!["quantum", "void", "reality", "noetic", "fractal"]
        );
    }
}
