//! BEAGLE LoRA Voice - 100% Automático no Loop Adversarial
//!
//! Treina LoRA voice automaticamente a cada draft melhor.
//! Usa MLX no M3 Max, atualiza vLLM, nunca quebra.

use anyhow::Result;
use beagle_config::beagle_data_dir;
use chrono::Utc;
use std::fs;
use std::path::PathBuf;
use std::process::Command;
use tracing::{error, info};

/// Get LoRA directory from BEAGLE_DATA_DIR
fn lora_dir() -> PathBuf {
    beagle_data_dir().join("lora")
}

/// Treina LoRA voice e atualiza vLLM automaticamente
///
/// **100% AUTOMÁTICO:**
/// - Treina a cada draft melhor
/// - Salva adapter novo com timestamp
/// - Atualiza o vLLM automaticamente
/// - Nunca quebra (se falhar, só loga e continua)
/// - Roda no M3 Max via MLX
///
/// # Arguments
/// - `bad_draft`: Draft anterior (pior)
/// - `good_draft`: Draft novo (melhor)
///
/// # Returns
/// `Ok(())` se sucesso, `Err` se falhar (mas não quebra o loop principal)
pub async fn train_and_update_voice(bad_draft: &str, good_draft: &str) -> Result<()> {
    let timestamp = Utc::now().format("%Y%m%d_%H%M%S");
    let base_lora_dir = lora_dir();
    let adapter_path = base_lora_dir.join(format!("voice_{timestamp}"));
    let current_voice_dir = base_lora_dir.join("current_voice");

    fs::write("/tmp/bad.txt", bad_draft)?;
    fs::write("/tmp/good.txt", good_draft)?;

    info!("🎤 LoRA voice training iniciado — M3 Max");

    // Get scripts directory from workspace root or fallback
    let scripts_dir = std::env::var("BEAGLE_WORKSPACE_ROOT")
        .map(PathBuf::from)
        .unwrap_or_else(|_| PathBuf::from("."))
        .join("scripts");

    let status = Command::new("python3")
        .arg(scripts_dir.join("train_lora_mlx.py"))
        .env("BAD", "/tmp/bad.txt")
        .env("GOOD", "/tmp/good.txt")
        .env("OUTPUT", &adapter_path)
        .status()?;

    if !status.success() {
        error!("❌ LoRA training falhou");
        return Err(anyhow::anyhow!("MLX falhou"));
    }

    // Cria diretório current_voice se não existir
    fs::create_dir_all(&current_voice_dir)?;

    // Atualiza vLLM
    fs::copy(
        adapter_path.join("adapter_model.bin"),
        current_voice_dir.join("adapter_model.bin"),
    )?;
    fs::copy(
        adapter_path.join("adapter_config.json"),
        current_voice_dir.join("adapter_config.json"),
    )?;

    // Restart vLLM if SSH host is configured
    if let Ok(vllm_host) = std::env::var("BEAGLE_VLLM_SSH_HOST") {
        let restart_cmd = std::env::var("BEAGLE_VLLM_RESTART_CMD").unwrap_or_else(|_| {
            "cd /home/ubuntu/beagle && docker-compose restart vllm".to_string()
        });
        Command::new("ssh")
            .arg(&vllm_host)
            .arg(&restart_cmd)
            .status()?;
    }

    info!("✅ LoRA voice 100% atualizado — tua voz perfeita agora");

    Ok(())
}
