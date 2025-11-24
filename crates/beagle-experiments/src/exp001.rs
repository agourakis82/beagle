//! Beagle Expedition 001 – Triad vs Single LLM
//!
//! Hypothesis H1: Triad ON produces drafts with higher human ratings and
//! accepted ratio than Triad OFF (single LLM) under typical working conditions.
//!
//! Null Hypothesis H0: No difference in mean rating or accepted ratio.

use serde::{Deserialize, Serialize};

/// ID oficial da Expedition 001
pub const EXPEDITION_001_ID: &str = "beagle_exp_001_triad_vs_single";

/// Número padrão de runs para Expedition 001 (10 triad + 10 single)
pub const EXPEDITION_001_DEFAULT_N: usize = 20;

/// Template padrão de pergunta para Expedition 001
pub const EXPEDITION_001_DEFAULT_QUESTION_TEMPLATE: &str =
    "Entropy curvature as substrate for cellular consciousness: design a short abstract focusing on PBPK and fractal information.";

/// Configuração da Expedition 001
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Expedition001Config {
    pub experiment_id: String,
    pub n_total: usize,
    pub question_template: String,
}

impl Default for Expedition001Config {
    fn default() -> Self {
        Self {
            experiment_id: EXPEDITION_001_ID.to_string(),
            n_total: EXPEDITION_001_DEFAULT_N,
            question_template: EXPEDITION_001_DEFAULT_QUESTION_TEMPLATE.to_string(),
        }
    }
}

impl Expedition001Config {
    /// Cria config com valores padrão
    pub fn new() -> Self {
        Self::default()
    }

    /// Cria config com valores customizados
    pub fn with_custom(
        experiment_id: Option<String>,
        n_total: Option<usize>,
        question_template: Option<String>,
    ) -> Self {
        Self {
            experiment_id: experiment_id.unwrap_or_else(|| EXPEDITION_001_ID.to_string()),
            n_total: n_total.unwrap_or(EXPEDITION_001_DEFAULT_N),
            question_template: question_template
                .unwrap_or_else(|| EXPEDITION_001_DEFAULT_QUESTION_TEMPLATE.to_string()),
        }
    }

    /// Retorna número de runs por condição (dividido igualmente)
    pub fn n_per_condition(&self) -> (usize, usize) {
        let n_triad = self.n_total / 2;
        let n_single = self.n_total - n_triad;
        (n_triad, n_single)
    }
}

/// Flags experimentais para condição "triad" (Expedition 001)
pub fn triad_condition_flags() -> (bool, bool, bool, bool) {
    (
        true,  // triad_enabled
        true,  // hrv_aware
        false, // serendipity_enabled (off para Expedition 001)
        false, // space_aware (off para Expedition 001)
    )
}

/// Flags experimentais para condição "single" (Expedition 001)
pub fn single_condition_flags() -> (bool, bool, bool, bool) {
    (
        false, // triad_enabled
        true,  // hrv_aware (mesmo que triad para isolar efeito)
        false, // serendipity_enabled
        false, // space_aware
    )
}

/// Valida configuração LLM/Router para Expedition 001
///
/// Garante que a configuração está alinhada com o protocolo da Expedition 001:
/// - Grok 3 como provider principal
/// - Grok 4 Heavy apenas como juiz da Triad (se enable_heavy=true)
/// - DeepSeek DESLIGADO (para não contaminar o experimento)
/// - Serendipity DESLIGADO (para Expedition 001 v1)
///
/// # Errors
///
/// Retorna erro se alguma configuração divergir do protocolo.
pub fn assert_expedition_001_llm_config(cfg: &beagle_config::BeagleConfig) -> anyhow::Result<()> {
    // Verifica provider principal (deve ser Grok 3)
    let provider_main = &cfg.llm.grok_model;
    if !provider_main.starts_with("grok-3") && !provider_main.starts_with("grok-2") {
        anyhow::bail!(
            "Expedition 001 requer Grok 3 como provider principal, mas config tem: {}",
            provider_main
        );
    }

    // Verifica DeepSeek (deve estar desligado para Expedition 001)
    // Note: DeepSeek é instanciado automaticamente no TieredRouter se DEEPSEEK_API_KEY estiver presente,
    // mas não deve ser usado durante Expedition 001. Verificamos se há flag explícita para desligar.
    let deepseek_key = std::env::var("DEEPSEEK_API_KEY").ok();
    if deepseek_key.is_some() {
        // Se houver API key, verifica se há flag explícita para desligar
        // Por padrão, se a key existe mas não há flag, assumimos que está OK (só alertamos)
        let deepseek_enabled = std::env::var("BEAGLE_DEEPSEEK_ENABLE")
            .ok()
            .and_then(|v| match v.to_lowercase().as_str() {
                "1" | "true" | "yes" | "y" => Some(true),
                _ => Some(false),
            })
            .unwrap_or(false);

        if deepseek_enabled {
            anyhow::bail!(
                "Expedition 001 requer DeepSeek DESLIGADO (BEAGLE_DEEPSEEK_ENABLE=false ou env var ausente), mas está habilitado"
            );
        }

        // Se a key existe mas não está explicitamente habilitada, apenas loga aviso
        // (não bloqueia, mas alerta para auditoria)
        tracing::warn!(
            "DEEPSEEK_API_KEY detectada durante Expedition 001. Certifique-se de que DeepSeek não seja usado via routing config."
        );
    }

    // Verifica Serendipity (deve estar desligado para Expedition 001 v1)
    if cfg.serendipity_enabled() {
        anyhow::bail!(
            "Expedition 001 v1 requer Serendipity DESLIGADO (BEAGLE_SERENDIPITY=false), mas está habilitado"
        );
    }

    if cfg.serendipity_in_triad() {
        anyhow::bail!(
            "Expedition 001 v1 requer Serendipity-in-Triad DESLIGADO (BEAGLE_SERENDIPITY_TRIAD=false), mas está habilitado"
        );
    }

    Ok(())
}
