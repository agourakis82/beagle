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
    pub accepted: Option<bool>, // true = "bom", false = "ruim"
    pub rating_0_10: Option<u8>,
    pub clarity_0_10: Option<u8>,
    pub adequacy_of_tone_0_10: Option<u8>,
    pub usefulness_0_10: Option<u8>,
    pub safety_or_emotional_fit_0_10: Option<u8>,
    pub notes: Option<String>,
    pub evaluator_id: Option<String>,
    pub judgment_protocol: Option<String>,
    pub blinded_item_id: Option<String>,

    // --- Experimentos A/B ---
    pub experiment_condition: Option<String>, // "A" | "B" | "control" | "treatment" | etc.
    pub experiment_id: Option<String>,        // ID do experimento
}

/// Julgamento humano estruturado e auditável.
#[derive(Debug, Serialize, Deserialize, Clone, Default)]
pub struct StructuredHumanJudgment {
    pub accepted: bool,
    pub rating_0_10: Option<u8>,
    pub clarity_0_10: Option<u8>,
    pub adequacy_of_tone_0_10: Option<u8>,
    pub usefulness_0_10: Option<u8>,
    pub safety_or_emotional_fit_0_10: Option<u8>,
    pub notes: Option<String>,
    pub evaluator_id: Option<String>,
    pub judgment_protocol: Option<String>,
    pub blinded_item_id: Option<String>,
}

/// Entrada no log JSONL
#[derive(Debug, Serialize, Deserialize)]
pub struct FeedbackLogEntry {
    pub event: FeedbackEvent,
}

impl FeedbackEvent {
    /// Retorna true quando o evento carrega julgamento humano explícito.
    ///
    /// Mantemos a checagem tolerante ao histórico do repositório: eventos antigos
    /// podem carregar accepted/rating mesmo sem event_type=HumanFeedback.
    pub fn has_human_judgment(&self) -> bool {
        self.accepted.is_some()
            || self.rating_0_10.is_some()
            || self.clarity_0_10.is_some()
            || self.adequacy_of_tone_0_10.is_some()
            || self.usefulness_0_10.is_some()
            || self.safety_or_emotional_fit_0_10.is_some()
            || self
                .notes
                .as_ref()
                .map(|notes| !notes.trim().is_empty())
                .unwrap_or(false)
    }
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
    let mut file = OpenOptions::new().create(true).append(true).open(&path)?;

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
        clarity_0_10: None,
        adequacy_of_tone_0_10: None,
        usefulness_0_10: None,
        safety_or_emotional_fit_0_10: None,
        notes: None,
        evaluator_id: None,
        judgment_protocol: None,
        blinded_item_id: None,
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
        clarity_0_10: None,
        adequacy_of_tone_0_10: None,
        usefulness_0_10: None,
        safety_or_emotional_fit_0_10: None,
        notes: None,
        evaluator_id: None,
        judgment_protocol: None,
        blinded_item_id: None,
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
    create_structured_human_feedback_event(
        run_id,
        StructuredHumanJudgment {
            accepted,
            rating_0_10: rating,
            notes,
            ..StructuredHumanJudgment::default()
        },
    )
}

/// Cria evento de feedback humano estruturado.
pub fn create_structured_human_feedback_event(
    run_id: String,
    judgment: StructuredHumanJudgment,
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
        accepted: Some(judgment.accepted),
        rating_0_10: judgment.rating_0_10,
        clarity_0_10: judgment.clarity_0_10,
        adequacy_of_tone_0_10: judgment.adequacy_of_tone_0_10,
        usefulness_0_10: judgment.usefulness_0_10,
        safety_or_emotional_fit_0_10: judgment.safety_or_emotional_fit_0_10,
        notes: judgment.notes,
        evaluator_id: judgment.evaluator_id,
        judgment_protocol: judgment.judgment_protocol,
        blinded_item_id: judgment.blinded_item_id,
        experiment_id: None,
        experiment_condition: None,
    }
}

#[cfg(test)]
mod tests {
    use super::{create_structured_human_feedback_event, FeedbackEventType, StructuredHumanJudgment};

    #[test]
    fn structured_human_judgment_is_detected() {
        let event = create_structured_human_feedback_event(
            "run-123".to_string(),
            StructuredHumanJudgment {
                accepted: true,
                rating_0_10: Some(8),
                clarity_0_10: Some(9),
                adequacy_of_tone_0_10: Some(8),
                usefulness_0_10: Some(9),
                safety_or_emotional_fit_0_10: Some(8),
                notes: Some("bounded blinded eval".to_string()),
                evaluator_id: Some("tester".to_string()),
                judgment_protocol: Some("b17.5-v1".to_string()),
                blinded_item_id: Some("item-001".to_string()),
            },
        );

        assert_eq!(event.event_type, FeedbackEventType::HumanFeedback);
        assert!(event.has_human_judgment());
        assert_eq!(event.clarity_0_10, Some(9));
        assert_eq!(event.blinded_item_id.as_deref(), Some("item-001"));
    }
}
