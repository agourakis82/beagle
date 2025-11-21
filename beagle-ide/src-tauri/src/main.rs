// Prevents additional console window on Windows in release, DO NOT REMOVE!!
#![cfg_attr(not(debug_assertions), windows_subsystem = "windows")]

use tauri::Manager;
use tracing_subscriber;

mod commands;
mod lsp;

fn main() {
    tracing_subscriber::fmt()
        .with_env_filter(
            tracing_subscriber::EnvFilter::try_from_default_env()
                .unwrap_or_else(|_| tracing_subscriber::EnvFilter::new("info")),
        )
        .init();

    tauri::Builder::default()
        .plugin(tauri_plugin_shell::init())
        .plugin(tauri_plugin_fs::init())
        .plugin(tauri_plugin_dialog::init())
        .invoke_handler(tauri::generate_handler![
            commands::voice_command,
            commands::yjs_sync,
            commands::cluster_status,
            commands::cluster_logs,
            commands::cluster_exec,
            commands::git_semantic_blame,
            commands::lsp_start,
            commands::lsp_completion,
            commands::lsp_hover,
            commands::lsp_goto_definition,
            commands::lsp_did_open,
            commands::lsp_did_change,
            // BEAGLE Core HTTP integration
            commands::beagle_pipeline_start,
            commands::beagle_pipeline_status,
            commands::beagle_run_artifacts,
            commands::beagle_recent_runs,
            commands::beagle_tag_run,
        ])
        .setup(|app| {
            let window = app.get_webview_window("main").unwrap();
            window.set_title("BEAGLE IDE").unwrap();
            tracing::info!("BEAGLE IDE iniciado");
            Ok(())
        })
        .run(tauri::generate_context!())
        .expect("Erro ao executar BEAGLE IDE");
}

