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
        .merge(crate::http_memory::memory_routes())
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

    // Chama LLM via router.complete() que retorna String
    let text = ctx.router.complete(&req.prompt).await.map_err(|e| {
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
        hrv_ms: req.hrv_ms,
        heart_rate_bpm: req.heart_rate_bpm,
        spo2_percent: req.spo2_percent,
        resp_rate_bpm: req.resp_rate_bpm,
        skin_temp_c: req.skin_temp_c,
        body_temp_c: req.body_temp_c,
        steps: req.steps,
        energy_burned_kcal: req.energy_burned_kcal,
        vo2max_ml_kg_min: req.vo2max_ml_kg_min,
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
        latitude_deg: req.latitude_deg,
        longitude_deg: req.longitude_deg,
        altitude_m: req.altitude_m,
        baro_pressure_hpa: req.baro_pressure_hpa,
        ambient_temp_c: req.ambient_temp_c,
        humidity_percent: req.humidity_percent,
        wind_speed_m_s: req.wind_speed_m_s,
        wind_dir_deg: req.wind_dir_deg,
        uv_index: req.uv_index,
        noise_db: req.noise_db,
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
        kp_index: req.kp_index,
        dst_index: req.dst_index,
        solar_wind_speed_km_s: req.solar_wind_speed_km_s,
        solar_wind_density_n_cm3: req.solar_wind_density_n_cm3,
        proton_flux_pfu: req.proton_flux_pfu,
        electron_flux: req.electron_flux,
        xray_flux: req.xray_flux,
        radio_flux_sfu: req.radio_flux_sfu,
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
) -> Result<Json<beagle_observer::UserContext>, StatusCode> {
    let ctx = state.observer.current_user_context().await.map_err(|e| {
        tracing::error!("Falha ao obter contexto do usuário: {}", e);
        StatusCode::INTERNAL_SERVER_ERROR
    })?;

    Ok(Json(ctx))
}

async fn observer_context_handler(
    axum::extract::State(state): axum::extract::State<AppState>,
    axum::extract::Path(run_id): axum::extract::Path<String>,
) -> Result<Json<beagle_observer::UserContext>, StatusCode> {
    // Por enquanto, retorna contexto atual (pode ser expandido para filtrar por run_id no futuro)
    let ctx = state.observer.current_user_context().await.map_err(|e| {
        tracing::error!("Falha ao obter contexto para run_id {}: {}", run_id, e);
        StatusCode::INTERNAL_SERVER_ERROR
    })?;

    Ok(Json(ctx))
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
