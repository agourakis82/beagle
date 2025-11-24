use beagle_config::{data_dir, safe_mode};
use serde::{Deserialize, Serialize};
use std::fs;
use std::path::PathBuf;
use uuid::Uuid;

/// Metadados de uma execução de publicação.
#[derive(Debug, Serialize, Deserialize, Clone)]
pub struct RunMetadata {
    pub run_id: String,
    pub component: String,
    pub git_commit: Option<String>,
    pub safe_mode: bool,
    pub publish_mode: String,
    pub timestamp_utc: String,
    pub paper_title: String,
    pub target: String, // ex: "arxiv", "overleaf", "local-pdf"
    pub dry_run: bool,
    pub notes: Option<String>,
}

/// Diretório onde os logs do beagle-publish são guardados.
pub fn logs_dir() -> PathBuf {
    data_dir().join("logs").join("beagle-publish")
}

/// Inicializa metadados básicos para um run de publicação.
pub fn init_run(
    component: &str,
    publish_mode: &str,
    paper_title: &str,
    target: &str,
    dry_run: bool,
) -> RunMetadata {
    let run_id = Uuid::new_v4().to_string();
    let timestamp_utc = chrono::Utc::now().to_rfc3339();

    let git_commit = std::process::Command::new("git")
        .args(["rev-parse", "HEAD"])
        .output()
        .ok()
        .and_then(|o| String::from_utf8(o.stdout).ok())
        .map(|s| s.trim().to_string())
        .filter(|s| !s.is_empty());

    RunMetadata {
        run_id,
        component: component.to_string(),
        git_commit,
        safe_mode: safe_mode(),
        publish_mode: publish_mode.to_string(),
        timestamp_utc,
        paper_title: paper_title.to_string(),
        target: target.to_string(),
        dry_run,
        notes: None,
    }
}

/// Persiste metadados do run em JSON estruturado.
pub fn save_run_metadata(meta: &RunMetadata) -> anyhow::Result<PathBuf> {
    let dir = logs_dir();
    fs::create_dir_all(&dir)?;
    let filename = format!(
        "{}_{}.json",
        meta.timestamp_utc.replace(':', "-"),
        meta.run_id
    );
    let path = dir.join(filename);
    let json = serde_json::to_string_pretty(meta)?;
    fs::write(&path, json)?;
    tracing::info!("RunMetadata salvo em {:?}", path);
    Ok(path)
}
