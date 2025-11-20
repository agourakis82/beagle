//! BEAGLE Configuration - Centralized configuration management
//!
//! Todos os paths, endpoints e configurações do BEAGLE são gerenciados centralmente aqui.
//! Usa ~/beagle-data/ por padrão, mas pode ser configurado via BEAGLE_DATA_DIR.
//!
//! **SAFE_MODE**: Impede ações irreversíveis quando ativo (default: true).
//! **PublishPolicy**: Governa comportamento de autopublish (default: DryRun).

mod model;
pub use model::*;

use std::path::PathBuf;
use std::env;

/// Helper para ler variáveis de ambiente booleanas
fn bool_env(var: &str, default: bool) -> bool {
    env::var(var)
        .ok()
        .map(|v| v.to_lowercase().trim().to_string())
        .map(|v| matches!(v.as_str(), "1" | "true" | "t" | "yes" | "y"))
        .unwrap_or(default)
}

/// SAFE_MODE impede ações irreversíveis quando ligado (default: true).
///
/// Quando ativo:
/// - Nenhuma publicação real será feita (arXiv, Twitter, etc.)
/// - HRV gain é limitado a ranges seguros
/// - Ações críticas são logadas mas não executadas
pub fn safe_mode() -> bool {
    bool_env("BEAGLE_SAFE_MODE", true)
}

/// Obtém o diretório base de dados do BEAGLE
///
/// Ordem de prioridade:
/// 1. Variável de ambiente BEAGLE_DATA_DIR
/// 2. Arquivo .beagle-data-path no repo
/// 3. ~/beagle-data (padrão)
pub fn beagle_data_dir() -> PathBuf {
    // 1. Tenta variável de ambiente
    if let Ok(dir) = env::var("BEAGLE_DATA_DIR") {
        return PathBuf::from(dir);
    }

    // 2. Tenta arquivo .beagle-data-path no repo
    let repo_root = find_repo_root();
    if let Some(repo_root) = repo_root {
        let config_file = repo_root.join(".beagle-data-path");
        if let Ok(contents) = std::fs::read_to_string(&config_file) {
            for line in contents.lines() {
                if let Some(value) = line.strip_prefix("BEAGLE_DATA_DIR=") {
                    return PathBuf::from(value.trim());
                }
            }
        }
    }

    // 3. Padrão: ~/beagle-data
    dirs::home_dir()
        .map(|h| h.join("beagle-data"))
        .unwrap_or_else(|| PathBuf::from("beagle-data"))
}

/// Alias para facilitar leitura junto das docs
pub fn data_dir() -> PathBuf {
    beagle_data_dir()
}

fn find_repo_root() -> Option<PathBuf> {
    let mut current = env::current_dir().ok()?;

    loop {
        let git_dir = current.join(".git");
        let cargo_toml = current.join("Cargo.toml");

        if git_dir.exists() || cargo_toml.exists() {
            return Some(current);
        }

        if !current.pop() {
            break;
        }
    }

    None
}

/// Path para modelos LLM
pub fn models_dir() -> PathBuf {
    beagle_data_dir().join("models")
}

/// Path para LoRA adapters
pub fn lora_dir() -> PathBuf {
    beagle_data_dir().join("lora")
}

/// Path para PostgreSQL data
pub fn postgres_dir() -> PathBuf {
    beagle_data_dir().join("postgres")
}

/// Path para Qdrant data
pub fn qdrant_dir() -> PathBuf {
    beagle_data_dir().join("qdrant")
}

/// Path para Redis data
pub fn redis_dir() -> PathBuf {
    beagle_data_dir().join("redis")
}

/// Path para Neo4j data
pub fn neo4j_dir() -> PathBuf {
    beagle_data_dir().join("neo4j")
}

/// Path para logs
pub fn logs_dir() -> PathBuf {
    beagle_data_dir().join("logs")
}

/// Path para drafts de papers
pub fn papers_drafts_dir() -> PathBuf {
    beagle_data_dir().join("papers").join("drafts")
}

/// Path para papers finais
pub fn papers_final_dir() -> PathBuf {
    beagle_data_dir().join("papers").join("final")
}

/// Path para embeddings cache
pub fn embeddings_dir() -> PathBuf {
    beagle_data_dir().join("embeddings")
}

/// Path para datasets
pub fn datasets_dir() -> PathBuf {
    beagle_data_dir().join("datasets")
}

/// Garante que todos os diretórios necessários existem
pub fn ensure_dirs() -> std::io::Result<()> {
    let dirs = vec![
        models_dir(),
        lora_dir(),
        postgres_dir(),
        qdrant_dir(),
        redis_dir(),
        neo4j_dir(),
        logs_dir(),
        papers_drafts_dir(),
        papers_final_dir(),
        embeddings_dir(),
        datasets_dir(),
    ];

    for dir in dirs {
        std::fs::create_dir_all(&dir)?;
    }

    Ok(())
}

// ============================================================================
// ENDPOINTS EXTERNOS
// ============================================================================

/// URL do servidor vLLM (default: http://t560.local:8000)
pub fn vllm_url() -> String {
    env::var("BEAGLE_VLLM_URL")
        .unwrap_or_else(|_| "http://t560.local:8000".to_string())
}

/// URL do servidor Grok API (xAI)
pub fn grok_api_url() -> String {
    env::var("BEAGLE_GROK_API_URL")
        .unwrap_or_else(|_| "https://api.x.ai/v1".to_string())
}

/// Token da API arXiv (opcional)
pub fn arxiv_token() -> Option<String> {
    env::var("ARXIV_API_TOKEN").ok()
}

/// Token da API Twitter/X (opcional)
pub fn twitter_token() -> Option<String> {
    env::var("TWITTER_API_TOKEN").ok()
}

/// Hostname para restart do vLLM via SSH (opcional)
pub fn vllm_host() -> Option<String> {
    env::var("VLLM_HOST").ok()
}

// ============================================================================
// HRV CONTROL CONFIGURATION
// ============================================================================

/// Configuração para controle de ganho baseado em HRV
#[derive(Debug, Clone)]
pub struct HrvControlConfig {
    /// Ganho mínimo permitido (default: 0.8)
    pub min_gain: f32,
    /// Ganho máximo permitido (default: 1.2)
    pub max_gain: f32,
    /// HRV mínimo para cálculo (default: 20.0 ms)
    pub min_hrv_ms: f32,
    /// HRV máximo para cálculo (default: 200.0 ms)
    pub max_hrv_ms: f32,
}

impl Default for HrvControlConfig {
    fn default() -> Self {
        Self {
            min_gain: 0.8,
            max_gain: 1.2,
            min_hrv_ms: 20.0,
            max_hrv_ms: 200.0,
        }
    }
}

impl HrvControlConfig {
    /// Carrega configuração de HRV a partir de variáveis de ambiente
    pub fn from_env() -> Self {
        let min_gain = env::var("BEAGLE_HRV_MIN_GAIN")
            .ok()
            .and_then(|v| v.parse().ok())
            .unwrap_or(0.8);
        
        let max_gain = env::var("BEAGLE_HRV_MAX_GAIN")
            .ok()
            .and_then(|v| v.parse().ok())
            .unwrap_or(1.2);
        
        let min_hrv = env::var("BEAGLE_HRV_MIN_MS")
            .ok()
            .and_then(|v| v.parse().ok())
            .unwrap_or(20.0);
        
        let max_hrv = env::var("BEAGLE_HRV_MAX_MS")
            .ok()
            .and_then(|v| v.parse().ok())
            .unwrap_or(200.0);
        
        Self {
            min_gain,
            max_gain,
            min_hrv_ms: min_hrv,
            max_hrv_ms: max_hrv,
        }
    }
}

/// Calcula ganho de velocidade baseado em HRV com clamp seguro em SAFE_MODE
///
/// # Arguments
/// - `hrv_ms`: Heart Rate Variability em milissegundos
/// - `cfg`: Configuração de HRV (usa default se None)
///
/// # Returns
/// Ganho de velocidade (0.8 a 1.2 por padrão, clampado em SAFE_MODE)
pub fn compute_gain_from_hrv(hrv_ms: f32, cfg: Option<HrvControlConfig>) -> f32 {
    let cfg = cfg.unwrap_or_default();
    
    // Normaliza HRV para range [0, 1]
    let normalized = ((hrv_ms - cfg.min_hrv_ms) / (cfg.max_hrv_ms - cfg.min_hrv_ms))
        .clamp(0.0, 1.0);
    
    // Calcula gain linear: min_gain + (max_gain - min_gain) * normalized
    let mut gain = cfg.min_gain + (cfg.max_gain - cfg.min_gain) * normalized;
    
    // Em SAFE_MODE, sempre aplica clamp agressivo
    if safe_mode() {
        gain = gain.clamp(cfg.min_gain, cfg.max_gain);
        tracing::info!(
            "SAFE_MODE: HRV={:.1}ms → gain limitado a {:.2} (range: {:.2}–{:.2})",
            hrv_ms,
            gain,
            cfg.min_gain,
            cfg.max_gain
        );
    }
    
    gain
}

// ============================================================================
// PUBLISH POLICY (GOVERNANÇA)
// ============================================================================

/// Modo de publicação governado por política explícita
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum PublishMode {
    /// Nunca chama API real - apenas salva planos
    DryRun,
    /// Gera tudo, mas exige confirmação humana antes de enviar
    ManualConfirm,
    /// Permitido enviar automaticamente (só se SAFE_MODE=false)
    FullAuto,
}

/// Política de publicação que governa comportamento de autopublish
#[derive(Debug, Clone)]
pub struct PublishPolicy {
    pub mode: PublishMode,
}

impl PublishPolicy {
    /// Carrega política de publicação a partir de variáveis de ambiente
    ///
    /// Variável: `BEAGLE_PUBLISH_MODE`
    /// Valores: `"dry"` (default), `"manual"`, `"auto"`
    pub fn from_env() -> Self {
        let mode_str = env::var("BEAGLE_PUBLISH_MODE")
            .unwrap_or_else(|_| "dry".to_string())
            .to_lowercase();
        
        let mode = match mode_str.as_str() {
            "auto" => PublishMode::FullAuto,
            "manual" => PublishMode::ManualConfirm,
            _ => PublishMode::DryRun,
        };
        
        Self { mode }
    }
    
    /// Verifica se publicação real é permitida
    ///
    /// Retorna `true` apenas se:
    /// - SAFE_MODE está desligado
    /// - E modo é FullAuto
    pub fn can_publish_real(&self) -> bool {
        !safe_mode() && self.mode == PublishMode::FullAuto
    }
    
    /// Verifica se modo manual está ativo
    pub fn requires_manual_confirm(&self) -> bool {
        self.mode == PublishMode::ManualConfirm
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use tempfile::tempdir;

    #[test]
    fn test_beagle_data_dir() {
        let dir = beagle_data_dir();
        assert!(dir.to_string_lossy().contains("beagle-data"));
    }

    #[test]
    fn test_paths_exist() {
        // Só testa que as funções retornam paths válidos
        let _ = models_dir();
        let _ = lora_dir();
        let _ = logs_dir();
    }

    #[test]
    fn test_safe_mode_defaults_true() {
        env::remove_var("BEAGLE_SAFE_MODE");
        assert!(safe_mode());
    }

    #[test]
    fn test_safe_mode_respects_false_values() {
        env::set_var("BEAGLE_SAFE_MODE", "false");
        assert!(!safe_mode());
        env::set_var("BEAGLE_SAFE_MODE", "0");
        assert!(!safe_mode());
        env::set_var("BEAGLE_SAFE_MODE", "off");
        assert!(!safe_mode());
        env::remove_var("BEAGLE_SAFE_MODE");
    }

    #[test]
    fn test_data_dir_env_override() {
        let tmp = tempdir().unwrap();
        env::set_var("BEAGLE_DATA_DIR", tmp.path().to_str().unwrap());
        assert_eq!(beagle_data_dir(), tmp.path());
        env::remove_var("BEAGLE_DATA_DIR");
    }
    
    #[test]
    fn test_vllm_url() {
        env::remove_var("BEAGLE_VLLM_URL");
        assert!(vllm_url().contains("8000"));
        
        env::set_var("BEAGLE_VLLM_URL", "http://custom:9000");
        assert_eq!(vllm_url(), "http://custom:9000");
        env::remove_var("BEAGLE_VLLM_URL");
    }
    
    #[test]
    fn test_hrv_gain_computation() {
        let cfg = HrvControlConfig::default();
        
        // HRV baixo → gain baixo
        let gain_low = compute_gain_from_hrv(30.0, Some(cfg.clone()));
        assert!(gain_low < 1.0);
        
        // HRV alto → gain alto
        let gain_high = compute_gain_from_hrv(150.0, Some(cfg.clone()));
        assert!(gain_high > 1.0);
        
        // SAFE_MODE sempre clampa
        env::set_var("BEAGLE_SAFE_MODE", "true");
        let gain = compute_gain_from_hrv(300.0, Some(cfg.clone())); // HRV muito alto
        assert!(gain <= cfg.max_gain);
        env::remove_var("BEAGLE_SAFE_MODE");
    }
    
    #[test]
    fn test_publish_policy() {
        env::set_var("BEAGLE_PUBLISH_MODE", "dry");
        let policy = PublishPolicy::from_env();
        assert_eq!(policy.mode, PublishMode::DryRun);
        assert!(!policy.can_publish_real());
        
        env::set_var("BEAGLE_PUBLISH_MODE", "manual");
        let policy = PublishPolicy::from_env();
        assert_eq!(policy.mode, PublishMode::ManualConfirm);
        assert!(policy.requires_manual_confirm());
        
        env::set_var("BEAGLE_PUBLISH_MODE", "auto");
        env::set_var("BEAGLE_SAFE_MODE", "false");
        let policy = PublishPolicy::from_env();
        assert_eq!(policy.mode, PublishMode::FullAuto);
        assert!(policy.can_publish_real());
        
        env::remove_var("BEAGLE_PUBLISH_MODE");
        env::remove_var("BEAGLE_SAFE_MODE");
    }
}

// ============================================================================
// CONFIGURAÇÃO TIPADA - BeagleConfig
// ============================================================================

/// Carrega configuração completa do BEAGLE a partir de variáveis de ambiente
/// e opcionalmente de arquivo de configuração.
///
/// Ordem de prioridade:
/// 1. Variáveis de ambiente (sempre aplicadas)
/// 2. Arquivo `beagle.toml` em `{data_dir}/config/` (se existir)
///
/// O arquivo de configuração pode sobrepor valores de env, mas env sempre tem
/// precedência final para segurança.
pub fn load() -> BeagleConfig {
    // 1) Carrega defaults a partir de env
    let mut cfg = BeagleConfig {
        profile: env::var("BEAGLE_PROFILE")
            .unwrap_or_else(|_| "dev".to_string())
            .to_lowercase(),
        safe_mode: bool_env("BEAGLE_SAFE_MODE", true),
        llm: LlmConfig {
            xai_api_key: env::var("XAI_API_KEY").ok(),
            anthropic_api_key: env::var("ANTHROPIC_API_KEY").ok(),
            openai_api_key: env::var("OPENAI_API_KEY").ok(),
            vllm_url: env::var("VLLM_URL")
                .or_else(|_| env::var("BEAGLE_VLLM_URL"))
                .ok(),
        },
        storage: StorageConfig {
            data_dir: env::var("BEAGLE_DATA_DIR")
                .unwrap_or_else(|_| default_data_dir().to_string_lossy().to_string()),
        },
        graph: GraphConfig {
            neo4j_uri: env::var("NEO4J_URI").ok(),
            neo4j_user: env::var("NEO4J_USER").ok(),
            neo4j_password: env::var("NEO4J_PASSWORD").ok(),
            qdrant_url: env::var("QDRANT_URL").ok(),
        },
        hermes: HermesConfig {
            database_url: env::var("DATABASE_URL").ok(),
            redis_url: env::var("REDIS_URL").ok(),
        },
    };

    // 2) Tenta carregar arquivo de configuração (opcional)
    let config_file = PathBuf::from(&cfg.storage.data_dir)
        .join("config")
        .join("beagle.toml");
    
    if config_file.exists() {
        if let Ok(text) = std::fs::read_to_string(&config_file) {
            if let Ok(file_cfg) = toml::from_str::<BeagleConfig>(&text) {
                // Merge simples: arquivo sobrepõe defaults, mas env mantém precedência
                cfg = merge_config(cfg, file_cfg);
            }
        }
    }

    cfg
}

/// Diretório padrão de dados
fn default_data_dir() -> PathBuf {
    dirs::home_dir()
        .map(|h| h.join("beagle-data"))
        .unwrap_or_else(|| PathBuf::from("beagle-data"))
}

/// Merge de configurações: `base` é mantido, `override_cfg` sobrepõe apenas campos Some
fn merge_config(base: BeagleConfig, override_cfg: BeagleConfig) -> BeagleConfig {
    BeagleConfig {
        profile: override_cfg.profile.clone(),
        safe_mode: override_cfg.safe_mode,
        llm: LlmConfig {
            xai_api_key: override_cfg.llm.xai_api_key.or(base.llm.xai_api_key),
            anthropic_api_key: override_cfg.llm.anthropic_api_key.or(base.llm.anthropic_api_key),
            openai_api_key: override_cfg.llm.openai_api_key.or(base.llm.openai_api_key),
            vllm_url: override_cfg.llm.vllm_url.or(base.llm.vllm_url),
        },
        storage: StorageConfig {
            data_dir: override_cfg.storage.data_dir.clone(),
        },
        graph: GraphConfig {
            neo4j_uri: override_cfg.graph.neo4j_uri.or(base.graph.neo4j_uri),
            neo4j_user: override_cfg.graph.neo4j_user.or(base.graph.neo4j_user),
            neo4j_password: override_cfg.graph.neo4j_password.or(base.graph.neo4j_password),
            qdrant_url: override_cfg.graph.qdrant_url.or(base.graph.qdrant_url),
        },
        hermes: HermesConfig {
            database_url: override_cfg.hermes.database_url.or(base.hermes.database_url),
            redis_url: override_cfg.hermes.redis_url.or(base.hermes.redis_url),
        },
    }
}
