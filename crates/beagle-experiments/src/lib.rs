//! BEAGLE Experiments - Infraestrutura para Experimentos Científicos
//!
//! Registra condições experimentais para:
//! - A/B testing (Triad vs ensemble, etc.)
//! - MAD vs ensemble
//! - HRV-blind vs HRV-aware
//! - Outros experimentos rigorosos sobre o próprio BEAGLE

pub mod analysis;
pub mod exp001;

use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};
use std::io::{BufRead, BufReader, Write};
use std::path::{Path, PathBuf};
use tracing::info;

pub use analysis::{ExperimentDataPoint, ExperimentMetrics, ConditionMetrics};
pub use exp001::{
    assert_expedition_001_llm_config, Expedition001Config, EXPEDITION_001_ID, EXPEDITION_001_DEFAULT_N,
};

/// Tag experimental para um run_id
///
/// Inclui snapshot de configuração no momento do run para reprodutibilidade
/// (padrão HELM/AgentBench: logging completo de config/condição).
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ExperimentRunTag {
    pub experiment_id: String,
    pub run_id: String,
    pub condition: String,
    pub timestamp: DateTime<Utc>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub notes: Option<String>,
    
    // Snapshot de config relevante no momento do run
    pub triad_enabled: bool,
    pub hrv_aware: bool,
    pub serendipity_enabled: bool,
    pub space_aware: bool,
}

/// Anexa tag experimental ao log de experimentos
///
/// Formato: {"tag": ExperimentRunTag} por linha (JSONL)
pub fn append_experiment_tag(_data_dir: &Path, tag: &ExperimentRunTag) -> anyhow::Result<()> {
    use beagle_config::experiments_dir;
    let experiments_dir = experiments_dir();
    std::fs::create_dir_all(&experiments_dir)?;
    
    let log_file = experiments_dir.join("events.jsonl");
    
    let mut file = std::fs::OpenOptions::new()
        .create(true)
        .append(true)
        .open(&log_file)?;
    
    // Formato: {"tag": ExperimentRunTag} por linha (JSONL)
    let entry = serde_json::json!({
        "tag": tag
    });
    let json = serde_json::to_string(&entry)?;
    writeln!(file, "{}", json)?;
    
    info!("📊 Tag experimental anexada: experiment_id={}, run_id={}, condition={}", 
          tag.experiment_id, tag.run_id, tag.condition);
    
    Ok(())
}

/// Lê todas as tags experimentais de um arquivo
///
/// Formato esperado: {"tag": ExperimentRunTag} por linha (JSONL)
pub fn load_experiment_tags(_data_dir: &Path) -> anyhow::Result<Vec<ExperimentRunTag>> {
    use beagle_config::experiments_dir;
    let log_file = experiments_dir().join("events.jsonl");
    
    if !log_file.exists() {
        return Ok(Vec::new());
    }
    
    let file = std::fs::File::open(&log_file)?;
    let reader = BufReader::new(file);
    
    let mut tags = Vec::new();
    for line in reader.lines() {
        let line = line?;
        if line.trim().is_empty() {
            continue;
        }
        // Tenta parsear como {"tag": ExperimentRunTag}
        if let Ok(json_value) = serde_json::from_str::<serde_json::Value>(&line) {
            if let Some(tag_value) = json_value.get("tag") {
                if let Ok(tag) = serde_json::from_value::<ExperimentRunTag>(tag_value.clone()) {
                    tags.push(tag);
                    continue;
                }
            }
        }
        // Fallback: tenta parsear diretamente (compatibilidade com formato antigo)
        if let Ok(tag) = serde_json::from_str::<ExperimentRunTag>(&line) {
            tags.push(tag);
        }
    }
    
    Ok(tags)
}

/// Lê tags experimentais filtradas por experiment_id
pub fn load_experiment_tags_by_id(data_dir: &Path, experiment_id: &str) -> anyhow::Result<Vec<ExperimentRunTag>> {
    let all_tags = load_experiment_tags(data_dir)?;
    Ok(all_tags.into_iter()
        .filter(|t| t.experiment_id == experiment_id)
        .collect())
}

/// Alias para compatibilidade (mantém função antiga)
pub fn read_experiment_tags(data_dir: &PathBuf) -> anyhow::Result<Vec<ExperimentRunTag>> {
    load_experiment_tags(data_dir)
}

/// Agrupa runs por experiment_id e condition
pub fn group_by_experiment(tags: &[ExperimentRunTag]) -> std::collections::HashMap<String, std::collections::HashMap<String, Vec<String>>> {
    let mut groups: std::collections::HashMap<String, std::collections::HashMap<String, Vec<String>>> = 
        std::collections::HashMap::new();
    
    for tag in tags {
        groups
            .entry(tag.experiment_id.clone())
            .or_insert_with(std::collections::HashMap::new)
            .entry(tag.condition.clone())
            .or_insert_with(Vec::new)
            .push(tag.run_id.clone());
    }
    
    groups
}

/// Analisa experimentos cruzando com FeedbackEvent
pub fn analyze_experiment(
    experiment_id: &str,
    data_dir: &PathBuf,
) -> anyhow::Result<ExperimentAnalysis> {
    // Lê tags experimentais
    let tags = load_experiment_tags(data_dir)?;
    let experiment_tags: Vec<_> = tags.iter()
        .filter(|t| t.experiment_id == experiment_id)
        .collect();
    
    if experiment_tags.is_empty() {
        return Ok(ExperimentAnalysis {
            experiment_id: experiment_id.to_string(),
            condition_counts: std::collections::HashMap::new(),
            run_ids_by_condition: std::collections::HashMap::new(),
            total_runs: 0,
        });
    }
    
    // Agrupa por condition
    let mut condition_counts: std::collections::HashMap<String, usize> = std::collections::HashMap::new();
    let mut run_ids_by_condition: std::collections::HashMap<String, Vec<String>> = std::collections::HashMap::new();
    
    for tag in &experiment_tags {
        *condition_counts.entry(tag.condition.clone()).or_insert(0) += 1;
        run_ids_by_condition
            .entry(tag.condition.clone())
            .or_insert_with(Vec::new)
            .push(tag.run_id.clone());
    }
    
    Ok(ExperimentAnalysis {
        experiment_id: experiment_id.to_string(),
        condition_counts,
        run_ids_by_condition,
        total_runs: experiment_tags.len(),
    })
}

/// Análise de um experimento
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ExperimentAnalysis {
    pub experiment_id: String,
    pub condition_counts: std::collections::HashMap<String, usize>,
    pub run_ids_by_condition: std::collections::HashMap<String, Vec<String>>,
    pub total_runs: usize,
}

/// Helper para garantir que experiments_dir existe
pub fn ensure_experiments_dir() -> anyhow::Result<PathBuf> {
    use beagle_config::experiments_dir;
    let dir = experiments_dir();
    std::fs::create_dir_all(&dir)?;
    Ok(dir)
}

