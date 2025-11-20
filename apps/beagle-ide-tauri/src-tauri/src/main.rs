#![cfg_attr(all(not(debug_assertions), target_os = "windows"), windows_subsystem = "windows")]

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

fn main() {
    tauri::Builder::default()
        .invoke_handler(tauri::generate_handler![voice_command, yjs_sync])
        .run(tauri::generate_context!())
        .expect("BEAGLE IDE rodando");
}

