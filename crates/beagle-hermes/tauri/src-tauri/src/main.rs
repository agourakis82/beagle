// Prevents additional console window on Windows in release, DO NOT REMOVE!!
#![cfg_attr(not(debug_assertions), windows_subsystem = "windows")]

use tauri::Manager;
use tracing_subscriber;

mod commands;

fn main() {
    tracing_subscriber::fmt::init();

    tauri::Builder::default()
        .plugin(tauri_plugin_shell::init())
        .plugin(tauri_plugin_fs::init())
        .plugin(tauri_plugin_dialog::init())
        .invoke_handler(tauri::generate_handler![
            commands::list_manuscripts,
            commands::get_manuscript,
            commands::get_manuscript_status,
            commands::upload_voice_note,
            commands::capture_text_insight,
            commands::trigger_synthesis,
        ])
        .setup(|app| {
            let window = app.get_webview_window("main").unwrap();
            window.set_title("HERMES BPSE").unwrap();
            Ok(())
        })
        .run(tauri::generate_context!())
        .expect("error while running tauri application");
}

