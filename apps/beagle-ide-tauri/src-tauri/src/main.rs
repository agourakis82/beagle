#![cfg_attr(all(not(debug_assertions), target_os = "windows"), windows_subsystem = "windows")]

use beagle_config::beagle_data_dir;
use serde::{Deserialize, Serialize};
use std::fs;
use std::path::PathBuf;
use tauri::Manager;

#[tauri::command]
async fn voice_command(command: String) -> Result<String, String> {
    // Aqui tu integra com teu assistente pessoal ou Grok
    Ok(format!("Comando recebido: {command} — executado"))
}

#[tauri::command]
async fn yjs_sync(update: Vec<u8>) -> Vec<u8> {
    // Teu server Yjs real (ou local)
    update
}

#[derive(Debug, Serialize, Deserialize)]
struct RunSummary {
    run_id: String,
    profile: String,
    safe_mode: bool,
    question: String,
    timestamp_utc: String,
    draft_path: Option<String>,
    pdf_path: Option<String>,
}

fn runs_dir() -> PathBuf {
    beagle_data_dir().join("logs").join("beagle-monorepo")
}

fn draft_path(run_id: &str) -> PathBuf {
    beagle_data_dir()
        .join("papers")
        .join("drafts")
        .join(run_id)
        .join("draft.md")
}

#[tauri::command]
async fn list_runs(limit: Option<usize>) -> Result<Vec<RunSummary>, String> {
    let dir = runs_dir();
    let entries = fs::read_dir(&dir).map_err(|e| e.to_string())?;
    let mut files: Vec<_> = entries
        .filter_map(|e| e.ok())
        .filter(|e| e.path().extension().and_then(|v| v.to_str()) == Some("json"))
        .collect();
    files.sort_by_key(|e| e.file_name());
    let limit = limit.unwrap_or(20);

    let mut summaries = Vec::new();
    for entry in files.into_iter().rev().take(limit) {
        let data = fs::read_to_string(entry.path()).map_err(|e| e.to_string())?;
        if let Ok(summary) = serde_json::from_str::<RunSummary>(&data) {
            summaries.push(summary);
        }
    }
    Ok(summaries)
}

#[tauri::command]
async fn load_draft(run_id: String) -> Result<String, String> {
    let path = draft_path(&run_id);
    fs::read_to_string(&path).map_err(|e| format!("Erro lendo {:?}: {}", path, e))
}

fn main() {
    tauri::Builder::default()
        .invoke_handler(tauri::generate_handler![
            voice_command,
            yjs_sync,
            list_runs,
            load_draft
        ])
        .run(tauri::generate_context!())
        .expect("BEAGLE IDE rodando");
}
