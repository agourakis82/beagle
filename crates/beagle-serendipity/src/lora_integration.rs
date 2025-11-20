//! LoRA Auto Integration - Integra treinamento automático de LoRA no loop adversarial
//! 
//! **100% AUTOMÁTICO:**
//! - Treina quando score > best_score
//! - Roda em background (não bloqueia loop)
//! - Nunca quebra (se falhar, só loga)

use beagle_lora_voice_auto::train_and_update_voice;
use tracing::{info, error};

/// Integra LoRA automático no loop de refinamento
/// 
/// **100% AUTOMÁTICO:**
/// - Treina quando score > best_score
/// - Roda em background (não bloqueia loop)
/// - Nunca quebra (se falhar, só loga)
/// 
/// # Usage
/// ```rust
/// // No adversarial loop, quando score > best_score:
/// if score > best_score {
///     let bad = current_draft.clone();
///     let good = new_draft.clone();
///     
///     tokio::spawn(async move {
///         if let Err(e) = beagle_lora_auto::train_and_update(&bad, &good).await {
///             error!("LoRA auto falhou: {}", e);
///         } else {
///             info!("LoRA atualizado — tua voz perfeita agora");
///         }
///     });
/// }
/// ```
pub async fn integrate_lora_in_refinement_loop(
    old_draft: &str,
    new_draft: &str,
    score: f64,
    best_score: f64,
) -> anyhow::Result<()> {
    // Só treina se o novo draft é melhor
    if score > best_score {
        info!("🎤 Novo draft melhor (score: {} > {}). Treinando LoRA...", score, best_score);
        
        let bad = old_draft.to_string();
        let good = new_draft.to_string();
        
        // Roda em background (não bloqueia loop)
        tokio::spawn(async move {
            match train_and_update_voice(&bad, &good).await {
                Ok(_) => {
                    info!("✅ LoRA atualizado — tua voz perfeita agora");
                }
                Err(e) => {
                    error!("❌ LoRA auto falhou: {}", e);
                    // Não propaga erro - loop continua normalmente
                }
            }
        });
        
        info!("✅ LoRA training iniciado em background");
    }
    
    Ok(())
}

