//! FeedbackEvent - Estrutura para Continuous Learning
//!
//! Captura eventos de feedback para treinamento futuro de LoRA:
//! - Entrada (pergunta, contexto)
//! - Saída do pipeline (draft)
//! - Triad final
//! - Dados fisiológicos (HRV)
//! - Intervenção manual (aceitou, editou, rejeitou)

use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};
use std::path::PathBuf;

/// Evento de feedback para Continuous Learning
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct FeedbackEvent {
    pub run_id: String,
    pub timestamp: DateTime<Utc>,
    pub question: String,
    pub draft_path: PathBuf,
    pub final_path: Option<PathBuf>,
    pub triad_present: bool,
    pub hrv_level: Option<String>, // ex.: "low", "normal", "high"
    pub accepted: Option<bool>,    // preenchido quando você marcar manualmente
    pub edited: Option<bool>,      // se você editou manualmente
    pub notes: Option<String>,     // notas adicionais
}

impl FeedbackEvent {
    /// Cria novo evento de feedback
    pub fn new(run_id: String, question: String, draft_path: PathBuf) -> Self {
        Self {
            run_id,
            timestamp: Utc::now(),
            question,
            draft_path,
            final_path: None,
            triad_present: false,
            hrv_level: None,
            accepted: None,
            edited: None,
            notes: None,
        }
    }
    
    /// Salva evento em arquivo JSONL
    pub fn save(&self, data_dir: &PathBuf) -> anyhow::Result<()> {
        let feedback_dir = data_dir.join("feedback");
        std::fs::create_dir_all(&feedback_dir)?;
        
        let events_file = feedback_dir.join("events.jsonl");
        let line = serde_json::to_string(self)?;
        
        use std::io::Write;
        let mut file = std::fs::OpenOptions::new()
            .create(true)
            .append(true)
            .open(&events_file)?;
        
        writeln!(file, "{}", line)?;
        
        Ok(())
    }
    
    /// Carrega todos os eventos de feedback
    pub fn load_all(data_dir: &PathBuf) -> anyhow::Result<Vec<Self>> {
        let events_file = data_dir.join("feedback").join("events.jsonl");
        
        if !events_file.exists() {
            return Ok(Vec::new());
        }
        
        let content = std::fs::read_to_string(&events_file)?;
        let mut events = Vec::new();
        
        for line in content.lines() {
            if line.trim().is_empty() {
                continue;
            }
            let event: Self = serde_json::from_str(line)?;
            events.push(event);
        }
        
        Ok(events)
    }
}

