use axum::{routing::{post, get}, Json, Router, extract::Path};
use axum::http::StatusCode;
use beagle_config::{classify_hrv, beagle_data_dir};
use beagle_core::BeagleContext;
use beagle_feedback::{append_event, create_triad_event};
use beagle_llm::{RequestMeta, ProviderTier};
use crate::{run_beagle_pipeline, RunState, RunStatus, ScienceJobRegistry, ScienceJobState, ScienceJobKind, ScienceJobStatus};
use beagle_observer::UniversalObserver;
use beagle_triad::{run_triad, TriadInput};
use chrono::Utc;
use serde::{Deserialize, Serialize};
use std::io::Write;
use std::path::PathBuf;
use std::sync::Arc;
use tokio::sync::Mutex;
use tracing::{info, error, warn};
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

use crate::jobs::JobRegistry;

#[derive(Clone)]
pub struct AppState {
    pub ctx: Arc<Mutex<BeagleContext>>,
    pub jobs: Arc<JobRegistry>,
    pub science_jobs: Arc<ScienceJobRegistry>,
    pub observer: Arc<UniversalObserver>,
}

pub fn build_router(state: AppState) -> Router {
    Router::new()
        .route("/api/llm/complete", post(llm_complete_handler))
        .route("/api/pipeline/start", post(pipeline_start_handler))
        .route("/api/pipeline/status/:run_id", get(pipeline_status_handler))
        .route("/api/run/:run_id/artifacts", get(run_artifacts_handler))
        .route("/api/runs/recent", get(runs_recent_handler))
        .route("/api/observer/physio", post(observer_physio_handler))
        .route("/api/observer/context/:run_id", get(observer_context_handler))
        .route("/api/jobs/science/start", post(science_job_start_handler))
        .route("/api/jobs/science/status/:job_id", get(science_job_status_handler))
        .route("/api/jobs/science/:job_id/artifacts", get(science_job_artifacts_handler))
        .route("/api/pcs/reason", post(pcs_reason_handler))
        .route("/api/fractal/grow", post(fractal_grow_handler))
        .route("/api/worldmodel/predict", post(worldmodel_predict_handler))
        .route("/health", get(health_handler))
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
    
    // Chama LLM
    let output = client
        .complete(&req.prompt)
        .await
        .map_err(|e| {
            tracing::error!("LLM error: {}", e);
            StatusCode::BAD_GATEWAY
        })?;
    
    // Atualiza stats
    ctx.llm_stats.update(run_id, |stats| {
        match tier {
            ProviderTier::Grok3 => {
                stats.grok3_calls += 1;
                stats.grok3_tokens_in += output.tokens_in_est as u32;
                stats.grok3_tokens_out += output.tokens_out_est as u32;
            }
            ProviderTier::Grok4Heavy => {
                stats.grok4_calls += 1;
                stats.grok4_tokens_in += output.tokens_in_est as u32;
                stats.grok4_tokens_out += output.tokens_out_est as u32;
            }
            _ => {
                // Outros tiers contam como Grok3 por enquanto
                stats.grok3_calls += 1;
                stats.grok3_tokens_in += output.tokens_in_est as u32;
                stats.grok3_tokens_out += output.tokens_out_est as u32;
            }
        }
    });
    
    info!(
        tier = ?tier,
        provider = client.name(),
        "LLM request routed"
    );
    
    Ok(Json(LlmResponse {
        text: output.text,
        provider: client.name().to_string(),
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
    let run_state = state.jobs.create_run(run_id.clone(), req.question.clone()).await;
    
    // Clona state para usar no spawn
    let ctx_clone = state.ctx.clone();
    let jobs_clone = state.jobs.clone();
    let observer_clone = state.observer.clone();
    let question = req.question.clone();
    let with_triad = req.with_triad;
    
    // Dispara pipeline em background
    tokio::spawn(async move {
        let mut ctx = ctx_clone.lock().await;
        
        // Atualiza status para Running
        jobs_clone.update_status(&run_id_clone, RunStatus::Running).await;
        
        // Executa pipeline com observer (sem science_job_ids por enquanto - podem ser adicionados depois)
        match run_beagle_pipeline(&mut ctx, &question, &run_id_clone, Some(observer_clone), None).await {
            Ok(paths) => {
                if with_triad {
                    // Atualiza para TriadRunning
                    jobs_clone.update_status(&run_id_clone, RunStatus::TriadRunning).await;
                    
                    // Executa Triad
                    let triad_input = TriadInput {
                        run_id: run_id_clone.clone(),
                        draft_path: paths.draft_md.clone(),
                        context_summary: None,
                    };
                    
                    match run_triad(&triad_input, &ctx).await {
                        Ok(report) => {
                            jobs_clone.update_status(&run_id_clone, RunStatus::TriadDone).await;
                            
                            // Cria feedback event para TriadCompleted
                            let data_dir = beagle_data_dir();
                            let triad_dir = data_dir.join("triad").join(&run_id_clone);
                            std::fs::create_dir_all(&triad_dir).ok();
                            
                            let triad_final_md = triad_dir.join("draft_reviewed.md");
                            let triad_report_json = triad_dir.join("triad_report.json");
                            
                            // Salva draft final e report
                            std::fs::write(&triad_final_md, &report.final_draft).ok();
                            std::fs::write(&triad_report_json, serde_json::to_string_pretty(&report).unwrap_or_default()).ok();
                            
                            // Extrai question do run_report.json se disponível
                            let question = None; // Poderia buscar do run_report.json
                            
                            // Cria evento com stats LLM
                            let llm_stats_tuple = (
                                report.llm_stats.grok3_calls as u32,
                                report.llm_stats.grok4_calls as u32,
                                (report.llm_stats.grok3_tokens_in + report.llm_stats.grok3_tokens_out) as u32,
                                (report.llm_stats.grok4_tokens_in + report.llm_stats.grok4_tokens_out) as u32,
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
                            jobs_clone.set_error(&run_id_clone, format!("Triad failed: {}", e)).await;
                        }
                    }
                } else {
                    jobs_clone.update_status(&run_id_clone, RunStatus::Done).await;
                }
            }
            Err(e) => {
                error!("Pipeline failed for run {}: {}", run_id_clone, e);
                jobs_clone.set_error(&run_id_clone, format!("Pipeline failed: {}", e)).await;
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
    let run_state = state.jobs.get_run(&run_id).await
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
    pub source: String, // ex.: "ios_healthkit"
    pub hrv_ms: f32,
    #[serde(default)]
    pub heart_rate_bpm: Option<f32>,
    #[serde(default)]
    pub session_id: Option<String>,
}

#[derive(Serialize)]
pub struct PhysioEventResponse {
    pub status: String, // "ok"
    pub hrv_level: String, // "low" | "normal" | "high"
}

async fn observer_physio_handler(
    axum::extract::State(state): axum::extract::State<AppState>,
    Json(req): Json<PhysioEventRequest>,
) -> Result<Json<PhysioEventResponse>, StatusCode> {
    // Classifica HRV
    let hrv_level = classify_hrv(req.hrv_ms, None);
    
    // Atualiza observer
    state.observer.update_hrv(req.hrv_ms, hrv_level.clone(), req.heart_rate_bpm).await;
    
    // Loga evento em logs/observer/physio.jsonl
    let ctx = state.ctx.lock().await;
    let data_dir = PathBuf::from(&ctx.cfg.storage.data_dir);
    let log_dir = data_dir.join("logs").join("observer");
    std::fs::create_dir_all(&log_dir).map_err(|_| StatusCode::INTERNAL_SERVER_ERROR)?;
    
    let log_file = log_dir.join("physio.jsonl");
    let log_entry = serde_json::json!({
        "timestamp": req.timestamp.unwrap_or_else(|| Utc::now().to_rfc3339()),
        "source": req.source,
        "hrv_ms": req.hrv_ms,
        "hrv_level": hrv_level,
        "heart_rate_bpm": req.heart_rate_bpm,
        "session_id": req.session_id,
    });
    
    if let Ok(mut file) = std::fs::OpenOptions::new()
        .create(true)
        .append(true)
        .open(&log_file)
    {
        let _ = writeln!(file, "{}", serde_json::to_string(&log_entry).unwrap_or_default());
    }
    
            Ok(Json(PhysioEventResponse {
                status: "ok".to_string(),
                hrv_level,
            }))
        }

async fn observer_context_handler(
    axum::extract::State(state): axum::extract::State<AppState>,
    axum::extract::Path(run_id): axum::extract::Path<String>,
) -> Result<Json<beagle_observer::ContextSummary>, StatusCode> {
    let summary = state.observer.summarize_context_for_run(&run_id).await
        .map_err(|e| {
            tracing::error!("Falha ao resumir contexto para run_id {}: {}", run_id, e);
            StatusCode::INTERNAL_SERVER_ERROR
        })?;
    
    Ok(Json(summary))
}

// ============================================================================
// Science Jobs endpoints
// ============================================================================

#[derive(Deserialize)]
pub struct ScienceJobStartRequest {
    pub kind: String,  // "pbpk", "scaffold", "helio", "pcs", "kec"
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
    
    let job_state = ScienceJobState::new(job_id.clone(), kind, req.params);
    state.science_jobs.add_job(job_state.clone()).await;
    
    info!("Science job start requested: job_id={}, kind={:?}", job_id, job_state.kind);
    
    // Dispara job científico em background (via Julia)
    let jobs_clone = state.science_jobs.clone();
    let job_id_clone = job_id.clone();
    let kind_clone = job_state.kind.clone();
    
    tokio::spawn(async move {
        jobs_clone.update_job(&job_id_clone, |s| s.update_status(ScienceJobStatus::Running)).await;
        info!("Starting science job for job_id: {}", job_id_clone);
        
        // Por enquanto, apenas placeholder
        // TODO: Implementar chamada real ao Julia via std::process::Command
        // ou HTTP interno ao servidor Julia
        
        // Simula execução (será substituído por chamada Julia real)
        tokio::time::sleep(tokio::time::Duration::from_secs(2)).await;
        
        // Por enquanto, marca como done sem resultados reais
        jobs_clone.update_job(&job_id_clone, |s| {
            s.update_status(ScienceJobStatus::Done);
            s.output_paths = vec![]; // TODO: preencher com paths reais do Julia
            s.result_json = Some(serde_json::json!({
                "status": "completed",
                "kind": format!("{:?}", kind_clone),
                "note": "placeholder - implementar chamada Julia"
            }));
        }).await;
        
        info!("Science job completed for job_id: {}", job_id_clone);
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
    state.science_jobs.get_job(&job_id)
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
    let job = state.science_jobs.get_job(&job_id)
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
    
    // Placeholder - implementar chamada real ao Julia
    Ok(Json(FractalGrowResponse {
        node_count: 0,
        max_depth: req.max_depth.unwrap_or(5),
        root_id: uuid::Uuid::new_v4().to_string(),
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
    
    // Placeholder - implementar chamada real
    Ok(Json(WorldmodelPredictResponse {
        predictions: vec![],
        confidence: 0.0,
    }))
}
