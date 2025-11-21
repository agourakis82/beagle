//! beagle-feedback - Sistema de Continuous Learning
//!
//! Captura eventos de aprendizado para treinamento futuro de LoRA:
//! - Pergunta
//! - Drafts gerados
//! - Versão final pós-Triad
//! - Estado fisiológico (HRV / Observer)
//! - Qual LLM foi usado (Grok 3 vs 4 Heavy)
//! - Avaliação humana (aceito, rating, notas)

use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};
use std::fs::OpenOptions;
use std::io::Write;
use std::path::{Path, PathBuf};

const FEEDBACK_FILE: &str = "feedback_events.jsonl";

/// Tipo de evento de feedback
#[derive(Debug, Serialize, Deserialize, Clone, PartialEq, Eq)]
#[serde(rename_all = "snake_case")]
pub enum FeedbackEventType {
    /// Depois de pipeline v0.1
    PipelineRun,
    /// Depois da Triad
    TriadCompleted,
    /// Julgamento humano explícito
    HumanFeedback,
}

/// Evento de feedback para Continuous Learning
#[derive(Debug, Serialize, Deserialize, Clone)]
pub struct FeedbackEvent {
    pub event_type: FeedbackEventType,
    pub run_id: String,
    pub timestamp: DateTime<Utc>,

    // --- Core context ---
    pub question: Option<String>, // pode vir do pipeline ou ser vazio em HumanFeedback

    // --- Artefatos ---
    pub draft_md: Option<PathBuf>,
    pub draft_pdf: Option<PathBuf>,
    pub triad_final_md: Option<PathBuf>,
    pub triad_report_json: Option<PathBuf>,

    // --- Estado fisiológico / observer ---
    pub hrv_level: Option<String>, // "low" | "normal" | "high" | raw string

    // --- LLM: stats agregados (por run) ---
    pub llm_provider_main: Option<String>, // "grok3", "grok4_heavy", etc.
    pub grok3_calls: Option<u32>,
    pub grok4_heavy_calls: Option<u32>,
    pub grok3_tokens_est: Option<u32>,
    pub grok4_tokens_est: Option<u32>,

    // --- Julgamento humano (preenchido depois) ---
    pub accepted: Option<bool>,   // true = "bom", false = "ruim"
    pub rating_0_10: Option<u8>,
    pub notes: Option<String>,
    
    // --- Experimentos A/B ---
    pub experiment_condition: Option<String>, // "A" | "B" | "control" | "treatment" | etc.
    pub experiment_id: Option<String>,        // ID do experimento
}

/// Entrada no log JSONL
#[derive(Debug, Serialize, Deserialize)]
pub struct FeedbackLogEntry {
    pub event: FeedbackEvent,
}

/// Retorna o caminho do arquivo de feedback
pub fn feedback_file_path(data_dir: &Path) -> PathBuf {
    data_dir.join("feedback").join(FEEDBACK_FILE)
}

/// Adiciona evento ao log JSONL
pub fn append_event(data_dir: &Path, event: &FeedbackEvent) -> anyhow::Result<()> {
    let feedback_dir = data_dir.join("feedback");
    std::fs::create_dir_all(&feedback_dir)?;

    let path = feedback_file_path(data_dir);
    let mut file = OpenOptions::new()
        .create(true)
        .append(true)
        .open(&path)?;

    let entry = FeedbackLogEntry {
        event: event.clone(),
    };
    let json = serde_json::to_string(&entry)?;
    writeln!(file, "{}", json)?;

    Ok(())
}

/// Carrega todos os eventos de feedback
pub fn load_all_events(data_dir: &Path) -> anyhow::Result<Vec<FeedbackEvent>> {
    let path = feedback_file_path(data_dir);

    if !path.exists() {
        return Ok(Vec::new());
    }

    let content = std::fs::read_to_string(&path)?;
    let mut events = Vec::new();

    for line in content.lines() {
        if line.trim().is_empty() {
            continue;
        }
        let entry: FeedbackLogEntry = serde_json::from_str(line)?;
        events.push(entry.event);
    }

    Ok(events)
}

/// Carrega eventos por run_id
pub fn load_events_by_run_id(data_dir: &Path, run_id: &str) -> anyhow::Result<Vec<FeedbackEvent>> {
    let all_events = load_all_events(data_dir)?;
    Ok(all_events
        .into_iter()
        .filter(|e| e.run_id == run_id)
        .collect())
}

/// Cria evento base do pipeline
pub fn create_pipeline_event(
    run_id: String,
    question: String,
    draft_md: PathBuf,
    draft_pdf: PathBuf,
    hrv_level: Option<String>,
    llm_provider_main: Option<String>,
) -> FeedbackEvent {
    FeedbackEvent {
        event_type: FeedbackEventType::PipelineRun,
        run_id,
        timestamp: Utc::now(),
        question: Some(question),
        draft_md: Some(draft_md),
        draft_pdf: Some(draft_pdf),
        triad_final_md: None,
        triad_report_json: None,
        hrv_level,
        llm_provider_main,
        grok3_calls: None,
        grok4_heavy_calls: None,
        grok3_tokens_est: None,
        grok4_tokens_est: None,
        accepted: None,
        rating_0_10: None,
        notes: None,
        experiment_id: None,
        experiment_condition: None,
    }
}

/// Cria evento de Triad
pub fn create_triad_event(
    run_id: String,
    question: Option<String>,
    triad_final_md: PathBuf,
    triad_report_json: PathBuf,
    llm_stats: Option<(u32, u32, u32, u32)>, // (grok3_calls, heavy_calls, grok3_tokens, heavy_tokens)
) -> FeedbackEvent {
    let (grok3_calls, heavy_calls, grok3_tokens, heavy_tokens) = llm_stats.unwrap_or((0, 0, 0, 0));
    
    let llm_provider_main = if heavy_calls > grok3_calls {
        Some("grok4_heavy".to_string())
    } else {
        Some("grok3".to_string())
    };

    FeedbackEvent {
        event_type: FeedbackEventType::TriadCompleted,
        run_id,
        timestamp: Utc::now(),
        question,
        draft_md: None,
        draft_pdf: None,
        triad_final_md: Some(triad_final_md),
        triad_report_json: Some(triad_report_json),
        hrv_level: None,
        llm_provider_main,
        grok3_calls: Some(grok3_calls),
        grok4_heavy_calls: Some(heavy_calls),
        grok3_tokens_est: Some(grok3_tokens),
        grok4_tokens_est: Some(heavy_tokens),
        accepted: None,
        rating_0_10: None,
        notes: None,
        experiment_id: None,
        experiment_condition: None,
    }
}

/// Cria evento de feedback humano
pub fn create_human_feedback_event(
    run_id: String,
    accepted: bool,
    rating: Option<u8>,
    notes: Option<String>,
) -> FeedbackEvent {
    FeedbackEvent {
        event_type: FeedbackEventType::HumanFeedback,
        run_id,
        timestamp: Utc::now(),
        question: None,
        draft_md: None,
        draft_pdf: None,
        triad_final_md: None,
        triad_report_json: None,
        hrv_level: None,
        llm_provider_main: None,
        grok3_calls: None,
        grok4_heavy_calls: None,
        grok3_tokens_est: None,
        grok4_tokens_est: None,
        accepted: Some(accepted),
        rating_0_10: rating,
        notes,
        experiment_id: None,
        experiment_condition: None,
    }
}
