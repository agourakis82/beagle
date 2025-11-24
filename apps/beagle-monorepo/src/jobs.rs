//! JobRegistry - Gerenciamento de jobs assíncronos (pipeline, Triad)
//!
//! Gerencia estado de execução de pipelines e Triads com run_id único.

use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};
use std::collections::HashMap;
use std::sync::Arc;
use tokio::sync::Mutex;

/// Status de execução de um run
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum RunStatus {
    /// Run criado, aguardando execução
    Created,
    /// Pipeline em execução
    Running,
    /// Pipeline concluído com sucesso
    Done,
    /// Pipeline falhou
    Error(String),
    /// Triad em execução
    TriadRunning,
    /// Triad concluída
    TriadDone,
}

/// Estado de um run
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct RunState {
    pub run_id: String,
    pub question: String,
    pub status: RunStatus,
    pub created_at: DateTime<Utc>,
    pub updated_at: DateTime<Utc>,
    pub error: Option<String>,
}

impl RunState {
    pub fn new(run_id: String, question: String) -> Self {
        let now = Utc::now();
        Self {
            run_id,
            question,
            status: RunStatus::Created,
            created_at: now,
            updated_at: now,
            error: None,
        }
    }

    pub fn update_status(&mut self, status: RunStatus) {
        self.status = status;
        self.updated_at = Utc::now();
    }

    pub fn set_error(&mut self, error: String) {
        self.status = RunStatus::Error(error.clone());
        self.error = Some(error);
        self.updated_at = Utc::now();
    }
}

/// Registry de jobs (runs)
#[derive(Debug, Clone)]
pub struct JobRegistry {
    runs: Arc<Mutex<HashMap<String, RunState>>>,
}

impl JobRegistry {
    pub fn new() -> Self {
        Self {
            runs: Arc::new(Mutex::new(HashMap::new())),
        }
    }

    /// Cria um novo run
    pub async fn create_run(&self, run_id: String, question: String) -> RunState {
        let state = RunState::new(run_id.clone(), question);
        let mut runs = self.runs.lock().await;
        runs.insert(run_id, state.clone());
        state
    }

    /// Obtém estado de um run
    pub async fn get_run(&self, run_id: &str) -> Option<RunState> {
        let runs = self.runs.lock().await;
        runs.get(run_id).cloned()
    }

    /// Atualiza status de um run
    pub async fn update_status(&self, run_id: &str, status: RunStatus) -> bool {
        let mut runs = self.runs.lock().await;
        if let Some(state) = runs.get_mut(run_id) {
            state.update_status(status);
            true
        } else {
            false
        }
    }

    /// Define erro em um run
    pub async fn set_error(&self, run_id: &str, error: String) -> bool {
        let mut runs = self.runs.lock().await;
        if let Some(state) = runs.get_mut(run_id) {
            state.set_error(error);
            true
        } else {
            false
        }
    }

    /// Lista runs recentes (ordenados por created_at desc)
    pub async fn list_recent(&self, limit: usize) -> Vec<RunState> {
        let runs = self.runs.lock().await;
        let mut states: Vec<RunState> = runs.values().cloned().collect();
        states.sort_by(|a, b| b.created_at.cmp(&a.created_at));
        states.into_iter().take(limit).collect()
    }
}

impl Default for JobRegistry {
    fn default() -> Self {
        Self::new()
    }
}

// ============================================================================
// SCIENCE JOBS
// ============================================================================

/// Tipo de job científico
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum ScienceJobKind {
    Pbpk,
    Scaffold,
    Helio,
    Pcs,
    Kec,
}

/// Status de um job científico
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum ScienceJobStatus {
    Created,
    Running,
    Error(String),
    Done,
}

impl ToString for ScienceJobStatus {
    fn to_string(&self) -> String {
        match self {
            ScienceJobStatus::Created => "created".to_string(),
            ScienceJobStatus::Running => "running".to_string(),
            ScienceJobStatus::Error(_) => "error".to_string(),
            ScienceJobStatus::Done => "done".to_string(),
        }
    }
}

/// Estado de um job científico em execução
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ScienceJobState {
    pub job_id: String,
    pub kind: ScienceJobKind,
    pub status: ScienceJobStatus,
    pub params: serde_json::Value,
    pub created_at: DateTime<Utc>,
    pub updated_at: DateTime<Utc>,
    pub error: Option<String>,
    pub output_paths: Vec<String>,
    pub result_json: Option<serde_json::Value>,
}

impl ScienceJobState {
    pub fn new(job_id: String, kind: ScienceJobKind, params: serde_json::Value) -> Self {
        let now = Utc::now();
        Self {
            job_id,
            kind,
            status: ScienceJobStatus::Created,
            params,
            created_at: now,
            updated_at: now,
            error: None,
            output_paths: Vec::new(),
            result_json: None,
        }
    }

    pub fn update_status(&mut self, status: ScienceJobStatus) {
        self.status = status;
        self.updated_at = Utc::now();
    }

    pub fn set_error(&mut self, error_msg: String) {
        self.status = ScienceJobStatus::Error(error_msg.clone());
        self.error = Some(error_msg);
        self.updated_at = Utc::now();
    }
}

/// Registry de jobs científicos
#[derive(Debug, Clone)]
pub struct ScienceJobRegistry {
    jobs: Arc<Mutex<HashMap<String, ScienceJobState>>>,
}

impl ScienceJobRegistry {
    pub fn new() -> Self {
        Self {
            jobs: Arc::new(Mutex::new(HashMap::new())),
        }
    }

    pub async fn add_job(&self, job_state: ScienceJobState) {
        let mut jobs = self.jobs.lock().await;
        jobs.insert(job_state.job_id.clone(), job_state);
    }

    pub async fn get_job(&self, job_id: &str) -> Option<ScienceJobState> {
        let jobs = self.jobs.lock().await;
        jobs.get(job_id).cloned()
    }

    pub async fn update_job<F>(&self, job_id: &str, f: F)
    where
        F: FnOnce(&mut ScienceJobState),
    {
        let mut jobs = self.jobs.lock().await;
        if let Some(job_state) = jobs.get_mut(job_id) {
            f(job_state);
        }
    }

    pub async fn get_recent_jobs(&self, limit: usize) -> Vec<ScienceJobState> {
        let jobs = self.jobs.lock().await;
        let mut sorted_jobs: Vec<ScienceJobState> = jobs.values().cloned().collect();
        sorted_jobs.sort_by(|a, b| b.created_at.cmp(&a.created_at));
        sorted_jobs.into_iter().take(limit).collect()
    }
}

impl Default for ScienceJobRegistry {
    fn default() -> Self {
        Self::new()
    }
}
