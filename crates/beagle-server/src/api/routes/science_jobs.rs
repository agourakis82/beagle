//! Endpoints para orquestração de jobs científicos Julia (PBPK, Heliobiology, Scaffolds, PCS, KEC)

use axum::{
    extract::{Path, State},
    routing::{get, post},
    Json, Router,
};
use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};
use std::collections::HashMap;
use std::path::PathBuf;
use std::process::Stdio;
use std::sync::Arc;
use tokio::process::Command;
use tokio::sync::Mutex;
use tracing::{error, info};
use utoipa::ToSchema;
use uuid::Uuid;

use beagle_config::jobs_dir;

use crate::{error::ApiError, state::AppState};

/// Estado de um job científico
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "lowercase")]
pub enum ScienceJobStatus {
    Pending,
    Running,
    Done,
    Error,
}

/// Tipo de job científico
#[derive(Debug, Clone, Serialize, Deserialize, ToSchema)]
#[serde(rename_all = "lowercase")]
pub enum ScienceJobKind {
    Pbpk,
    Helio,
    Scaffold,
    Pcs,
    Kec,
}

impl std::str::FromStr for ScienceJobKind {
    type Err = String;

    fn from_str(s: &str) -> Result<Self, Self::Err> {
        match s.to_lowercase().as_str() {
            "pbpk" => Ok(ScienceJobKind::Pbpk),
            "helio" => Ok(ScienceJobKind::Helio),
            "scaffold" => Ok(ScienceJobKind::Scaffold),
            "pcs" => Ok(ScienceJobKind::Pcs),
            "kec" => Ok(ScienceJobKind::Kec),
            _ => Err(format!("Tipo de job desconhecido: {}", s)),
        }
    }
}

/// Estado de um job científico
#[derive(Debug, Clone, Serialize, ToSchema)]
pub struct ScienceJobState {
    pub job_id: String,
    pub kind: String,
    pub status: String,
    pub created_at: DateTime<Utc>,
    pub updated_at: DateTime<Utc>,
    pub error: Option<String>,
}

/// Request para iniciar um job científico
#[derive(Debug, Deserialize, ToSchema)]
pub struct StartScienceJobRequest {
    pub kind: String,
    pub config: serde_json::Value,
}

/// Response de início de job
#[derive(Debug, Serialize, ToSchema)]
pub struct StartScienceJobResponse {
    pub job_id: String,
    pub kind: String,
    pub status: String,
}

/// Response de status de job
#[derive(Debug, Serialize, ToSchema)]
pub struct ScienceJobStatusResponse {
    pub job_id: String,
    pub kind: String,
    pub status: String,
    pub created_at: DateTime<Utc>,
    pub updated_at: DateTime<Utc>,
    pub error: Option<String>,
}

/// Response de artefatos de job
#[derive(Debug, Serialize, ToSchema)]
pub struct ScienceJobArtifactsResponse {
    pub job_id: String,
    pub kind: String,
    pub result_path: Option<String>,
    pub output_paths: Vec<String>,
}

/// Registro global de jobs científicos
type ScienceJobRegistry = Arc<Mutex<HashMap<String, ScienceJobState>>>;

/// Roteador com endpoints de jobs científicos
pub fn router() -> Router<AppState> {
    Router::new()
        .route("/api/jobs/science/start", post(start_science_job))
        .route(
            "/api/jobs/science/status/:job_id",
            get(get_science_job_status),
        )
        .route(
            "/api/jobs/science/:job_id/artifacts",
            get(get_science_job_artifacts),
        )
}

/// Inicia um job científico
#[utoipa::path(
    post,
    path = "/api/jobs/science/start",
    request_body = StartScienceJobRequest,
    responses(
        (status = 200, description = "Job iniciado", body = StartScienceJobResponse),
        (status = 400, description = "Request inválido")
    )
)]
pub async fn start_science_job(
    State(state): State<AppState>,
    Json(req): Json<StartScienceJobRequest>,
) -> Result<Json<StartScienceJobResponse>, ApiError> {
    // Valida tipo de job
    let kind: ScienceJobKind = req
        .kind
        .parse()
        .map_err(|e| ApiError::BadRequest(format!("Tipo de job inválido: {}", e)))?;

    // Gera job_id único
    let job_id = Uuid::new_v4().to_string();

    // Cria diretório do job
    let jobs_base = jobs_dir();
    let job_dir = jobs_base.join(&job_id);
    std::fs::create_dir_all(&job_dir)
        .map_err(|e| ApiError::Internal(format!("Falha ao criar diretório do job: {}", e)))?;

    // Escreve config JSON
    let config_path = job_dir.join("job_config.json");
    let config_json = serde_json::json!({
        "kind": req.kind.to_lowercase(),
        "job_id": job_id.clone(),
        "config": req.config
    });
    let config_json_str = serde_json::to_string_pretty(&config_json)
        .map_err(|e| ApiError::Internal(format!("Falha ao serializar config do job: {}", e)))?;
    std::fs::write(&config_path, config_json_str)
        .map_err(|e| ApiError::Internal(format!("Falha ao escrever config do job: {}", e)))?;

    // Registra job como Pending
    let job_state = ScienceJobState {
        job_id: job_id.clone(),
        kind: req.kind.clone(),
        status: "pending".to_string(),
        created_at: Utc::now(),
        updated_at: Utc::now(),
        error: None,
    };

    // Obtém ou cria registry no AppState
    // Por enquanto, vamos usar um registry temporário em memória
    // TODO: mover para AppState se necessário persistência
    info!("🔬 Iniciando job científico: {} (id: {})", req.kind, job_id);

    // Dispara execução assíncrona do job Julia
    let job_dir_clone = job_dir.clone();
    let job_id_for_spawn = job_id.clone();
    let kind_clone = req.kind.clone();

    tokio::spawn(async move {
        execute_science_job(job_id_for_spawn, kind_clone, job_dir_clone).await;
    });

    Ok(Json(StartScienceJobResponse {
        job_id: job_id.clone(),
        kind: req.kind,
        status: "pending".to_string(),
    }))
}

/// Executa um job científico Julia em background
async fn execute_science_job(job_id: String, kind: String, job_dir: PathBuf) {
    info!("🔬 Executando job científico: {} (id: {})", kind, job_id);

    // TODO: usar registry global para atualizar status
    // Por enquanto, apenas loga

    // Encontra script Julia do orchestrator
    // Assumindo que beagle-julia está no mesmo repo ou configurado via env
    let julia_project =
        std::env::var("BEAGLE_JULIA_PROJECT").unwrap_or_else(|_| "beagle-julia".to_string());

    let script_path = format!("{}/run_job_cli.jl", julia_project);

    // Comando Julia
    let config_path = job_dir.join("job_config.json");

    let output = Command::new("julia")
        .arg("--project=.")
        .arg(&script_path)
        .arg(config_path)
        .arg(&job_dir)
        .stdout(Stdio::piped())
        .stderr(Stdio::piped())
        .current_dir(&julia_project)
        .output()
        .await;

    match output {
        Ok(output) => {
            if output.status.success() {
                // Salva resultado JSON
                let result_path = job_dir.join("result.json");
                if let Ok(stdout) = String::from_utf8(output.stdout) {
                    if let Err(e) = std::fs::write(&result_path, &stdout) {
                        error!("Falha ao salvar resultado do job {}: {}", job_id, e);
                    }
                }

                info!("✅ Job científico concluído: {} (id: {})", kind, job_id);
            } else {
                let stderr = String::from_utf8_lossy(&output.stderr);
                error!(
                    "❌ Job científico falhou: {} (id: {})\n{}",
                    kind, job_id, stderr
                );

                // Salva erro
                let error_path = job_dir.join("error.txt");
                let _ = std::fs::write(&error_path, stderr.as_ref());
            }
        }
        Err(e) => {
            error!(
                "❌ Falha ao executar job científico {} (id: {}): {}",
                kind, job_id, e
            );

            // Salva erro
            let error_path = job_dir.join("error.txt");
            let _ = std::fs::write(&error_path, format!("Erro ao executar: {}", e));
        }
    }
}

/// Obtém status de um job científico
#[utoipa::path(
    get,
    path = "/api/jobs/science/status/{job_id}",
    params(
        ("job_id" = String, Path, description = "ID do job")
    ),
    responses(
        (status = 200, description = "Status do job", body = ScienceJobStatusResponse),
        (status = 404, description = "Job não encontrado")
    )
)]
pub async fn get_science_job_status(
    Path(job_id): Path<String>,
    State(_state): State<AppState>,
) -> Result<Json<ScienceJobStatusResponse>, ApiError> {
    let jobs_base = jobs_dir();
    let job_dir = jobs_base.join(&job_id);

    if !job_dir.exists() {
        return Err(ApiError::NotFound(format!("Job {} não encontrado", job_id)));
    }

    // Lê config do job para obter tipo e timestamps
    let config_path = job_dir.join("job_config.json");
    let config: serde_json::Value = serde_json::from_reader(
        std::fs::File::open(&config_path)
            .map_err(|_| ApiError::NotFound(format!("Config do job {} não encontrado", job_id)))?,
    )
    .map_err(|e| ApiError::Internal(format!("Falha ao ler config: {}", e)))?;

    let kind = config["kind"].as_str().unwrap_or("unknown").to_string();

    // Determina status baseado em arquivos existentes
    let result_path = job_dir.join("result.json");
    let error_path = job_dir.join("error.txt");
    let running_marker = job_dir.join(".running");

    let (status, error) = if error_path.exists() {
        let error_msg = std::fs::read_to_string(&error_path).ok();
        ("error".to_string(), error_msg)
    } else if result_path.exists() {
        ("done".to_string(), None)
    } else if running_marker.exists() {
        ("running".to_string(), None)
    } else {
        ("pending".to_string(), None)
    };

    // Timestamps do diretório (usa Utc::now se metadata não disponível)
    let created_at = job_dir
        .metadata()
        .ok()
        .and_then(|m| m.created().ok())
        .map(|t| DateTime::<Utc>::from(t))
        .unwrap_or_else(Utc::now);

    let updated_at = if result_path.exists() {
        result_path
            .metadata()
            .ok()
            .and_then(|m| m.modified().ok())
            .map(|t| DateTime::<Utc>::from(t))
            .unwrap_or_else(Utc::now)
    } else {
        Utc::now()
    };

    Ok(Json(ScienceJobStatusResponse {
        job_id,
        kind,
        status,
        created_at,
        updated_at,
        error,
    }))
}

/// Obtém artefatos de um job científico
#[utoipa::path(
    get,
    path = "/api/jobs/science/{job_id}/artifacts",
    params(
        ("job_id" = String, Path, description = "ID do job")
    ),
    responses(
        (status = 200, description = "Artefatos do job", body = ScienceJobArtifactsResponse),
        (status = 404, description = "Job não encontrado")
    )
)]
pub async fn get_science_job_artifacts(
    Path(job_id): Path<String>,
    State(_state): State<AppState>,
) -> Result<Json<ScienceJobArtifactsResponse>, ApiError> {
    let jobs_base = jobs_dir();
    let job_dir = jobs_base.join(&job_id);

    if !job_dir.exists() {
        return Err(ApiError::NotFound(format!("Job {} não encontrado", job_id)));
    }

    // Lê config do job
    let config_path = job_dir.join("job_config.json");
    let config: serde_json::Value = serde_json::from_reader(
        std::fs::File::open(&config_path)
            .map_err(|_| ApiError::NotFound(format!("Config do job {} não encontrado", job_id)))?,
    )
    .map_err(|e| ApiError::Internal(format!("Falha ao ler config: {}", e)))?;

    let kind = config["kind"].as_str().unwrap_or("unknown").to_string();

    // Lista arquivos de output
    let mut output_paths = Vec::new();
    let result_path = job_dir.join("result.json");

    if result_path.exists() {
        // Se houver result.json, tenta ler output_paths dele
        if let Ok(result_json) = std::fs::read_to_string(&result_path) {
            if let Ok(result) = serde_json::from_str::<serde_json::Value>(&result_json) {
                if let Some(paths) = result["output_paths"].as_array() {
                    for path in paths {
                        if let Some(path_str) = path.as_str() {
                            output_paths.push(path_str.to_string());
                        }
                    }
                }
            }
        }

        // Sempre inclui result.json
        output_paths.push(format!("jobs/{}/result.json", job_id));
    }

    // Procura outros arquivos comuns
    let common_extensions = vec!["csv", "json", "png", "pdf", "txt"];
    if let Ok(entries) = std::fs::read_dir(&job_dir) {
        for entry in entries.flatten() {
            let path = entry.path();
            if let Some(ext) = path.extension().and_then(|e| e.to_str()) {
                if common_extensions.contains(&ext) {
                    if let Some(file_name) = path.file_name().and_then(|n| n.to_str()) {
                        let rel_path = format!("jobs/{}/{}", job_id, file_name);
                        if !output_paths.contains(&rel_path) {
                            output_paths.push(rel_path);
                        }
                    }
                }
            }
        }
    }

    let job_id_for_result = job_id.clone();
    Ok(Json(ScienceJobArtifactsResponse {
        job_id,
        kind,
        result_path: if result_path.exists() {
            Some(format!("jobs/{}/result.json", job_id_for_result))
        } else {
            None
        },
        output_paths,
    }))
}
