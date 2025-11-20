//! BEAGLE LoRA Voice - 100% Automático no Loop Adversarial
//! 
//! Treina LoRA voice automaticamente a cada draft melhor.
//! Usa MLX no M3 Max, atualiza vLLM, nunca quebra.

use std::fs;
use std::process::Command;
use tracing::{info, error};
use anyhow::Result;
use chrono::Utc;

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
    let adapter_path = format!("/home/agourakis82/beagle-data/lora/voice_{timestamp}");

    fs::write("/tmp/bad.txt", bad_draft)?;
    fs::write("/tmp/good.txt", good_draft)?;

    info!("🎤 LoRA voice training iniciado — M3 Max");

    let status = Command::new("python3")
        .arg("/home/agourakis82/beagle/scripts/train_lora_mlx.py")
        .env("BAD", "/tmp/bad.txt")
        .env("GOOD", "/tmp/good.txt")
        .env("OUTPUT", &adapter_path)
        .status()?;

    if !status.success() {
        error!("❌ LoRA training falhou");
        return Err(anyhow::anyhow!("MLX falhou"));
    }

    // Cria diretório current_voice se não existir
    fs::create_dir_all("/home/agourakis82/beagle-data/lora/current_voice")?;

    // Atualiza vLLM
    fs::copy(
        format!("{}/adapter_model.bin", adapter_path),
        "/home/agourakis82/beagle-data/lora/current_voice/adapter_model.bin",
    )?;
    fs::copy(
        format!("{}/adapter_config.json", adapter_path),
        "/home/agourakis82/beagle-data/lora/current_voice/adapter_config.json",
    )?;

    Command::new("ssh")
        .arg("maria")
        .arg("cd /home/ubuntu/beagle && docker-compose restart vllm")
        .status()?;

    info!("✅ LoRA voice 100% atualizado — tua voz perfeita agora");

    Ok(())
}

