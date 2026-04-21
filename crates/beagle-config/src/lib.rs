//! BEAGLE Configuration - Centralized configuration management
//!
//! Todos os paths, endpoints e configurações do BEAGLE são gerenciados centralmente aqui.
//! Usa ~/beagle-data/ por padrão, mas pode ser configurado via BEAGLE_DATA_DIR.
//!
//! **SAFE_MODE**: Impede ações irreversíveis quando ativo (default: true).
//! **PublishPolicy**: Governa comportamento de autopublish (default: DryRun).

mod model;
pub use model::*;

use std::env;
use std::path::PathBuf;

fn optional_non_empty_or(value: &str, fallback: &str) -> String {
    let trimmed = value.trim();
    if trimmed.is_empty() {
        fallback.to_string()
    } else {
        trimmed.to_string()
    }
}

fn default_grok_model() -> String {
    "grok-3".to_string()
}

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

/// Path para triad (revisões adversarial)
pub fn triad_dir() -> PathBuf {
    beagle_data_dir().join("triad")
}

/// Path para feedback (eventos de Continuous Learning)
pub fn feedback_dir() -> PathBuf {
    beagle_data_dir().join("feedback")
}

/// Path para experimentos (tags experimentais)
pub fn experiments_dir() -> PathBuf {
    beagle_data_dir().join("experiments")
}

/// Path para jobs científicos (PBPK, Heliobiology, Scaffolds, PCS, KEC)
pub fn jobs_dir() -> PathBuf {
    beagle_data_dir().join("jobs")
}

/// Path para logs do pipeline
pub fn pipeline_logs_dir() -> PathBuf {
    logs_dir().join("beagle-pipeline")
}

/// Path para logs do observer
pub fn observer_logs_dir() -> PathBuf {
    logs_dir().join("observer")
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
        pipeline_logs_dir(),
        observer_logs_dir(),
        papers_drafts_dir(),
        papers_final_dir(),
        embeddings_dir(),
        datasets_dir(),
        triad_dir(),
        feedback_dir(),
        experiments_dir(),
        jobs_dir(),
        beagle_data_dir().join("alerts"), // Diretório para alerts
    ];

    for dir in dirs {
        std::fs::create_dir_all(&dir)?;
    }

    Ok(())
}

/// Bootstrap completo: verifica BEAGLE_DATA_DIR e cria estrutura
///
/// Retorna erro se:
/// - BEAGLE_DATA_DIR não existe e não pode ser criado
/// - BEAGLE_DATA_DIR não é gravável
///
/// Loga informações sobre profile, safe_mode e data_dir
pub fn bootstrap() -> anyhow::Result<()> {
    use tracing::info;

    let data_dir = beagle_data_dir();

    // Verifica se existe
    if !data_dir.exists() {
        info!("Criando BEAGLE_DATA_DIR: {}", data_dir.display());
        std::fs::create_dir_all(&data_dir)?;
    }

    // Verifica se é gravável
    let test_file = data_dir.join(".beagle_write_test");
    std::fs::write(&test_file, "test")?;
    std::fs::remove_file(&test_file)?;

    // Cria estrutura completa
    ensure_dirs()?;

    // Loga configuração
    let profile = std::env::var("BEAGLE_PROFILE").unwrap_or_else(|_| "dev".to_string());
    let safe_mode = safe_mode();

    info!(
        "BEAGLE bootstrap completo | profile={} | safe_mode={} | data_dir={}",
        profile,
        safe_mode,
        data_dir.display()
    );

    Ok(())
}

pub fn workspace_habitat_bindings_from_env() -> Vec<WorkspaceHabitatBindingConfig> {
    env::var("BEAGLE_WORKSPACE_HABITATS_JSON")
        .ok()
        .and_then(|value| serde_json::from_str::<Vec<WorkspaceHabitatBindingConfig>>(&value).ok())
        .unwrap_or_default()
}

pub fn resolve_workspace_habitat_binding(
    cfg: &BeagleConfig,
    workstream_id: &str,
) -> Option<ResolvedWorkspaceHabitatBinding> {
    let requested = workstream_id.trim();
    if requested.is_empty() {
        return None;
    }

    if let Some(binding) = workspace_habitat_bindings_from_env()
        .into_iter()
        .find(|binding| binding.workstream_id.trim() == requested)
    {
        return Some(ResolvedWorkspaceHabitatBinding {
            workstream_id: requested.to_string(),
            workspace_id: optional_non_empty_or(&binding.workspace_id, &cfg.workspace.canonical_workspace_id),
            session_id: optional_non_empty_or(&binding.session_id, "unassigned-session"),
            canonical_repo: optional_non_empty_or(&binding.canonical_repo, &cfg.workspace.canonical_repo),
            canonical_branch: optional_non_empty_or(&binding.canonical_branch, &cfg.workspace.canonical_branch),
            canonical_track: optional_non_empty_or(&binding.canonical_track, &cfg.workspace.canonical_track),
            branch_lineage: optional_non_empty_or(
                &binding.branch_lineage,
                if cfg.workspace.cutover_workstream == requested {
                    &cfg.workspace.cutover_branch_lineage
                } else {
                    &cfg.workspace.canonical_branch
                },
            ),
            governance_state: optional_non_empty_or(
                &binding.governance_state,
                if cfg.workspace.cutover_workstream == requested {
                    &cfg.workspace.cutover_state
                } else {
                    "canonical"
                },
            ),
            governance_last_transition: optional_non_empty_or(
                &binding.governance_last_transition,
                if cfg.workspace.cutover_workstream == requested {
                    &cfg.workspace.cutover_last_transition
                } else {
                    "resume"
                },
            ),
            default_dev_plane: optional_non_empty_or(&binding.default_dev_plane, &cfg.workspace.default_dev_plane),
            vm_fallback_role: optional_non_empty_or(&binding.vm_fallback_role, &cfg.workspace.vm_fallback_role),
            promotion_scope: optional_non_empty_or(&binding.promotion_scope, &cfg.workspace.promotion_scope),
            ide_kind: optional_non_empty_or(&binding.ide_kind, &cfg.workspace.habitat.ide_kind),
            ssh_enabled: if binding.ssh_enabled {
                true
            } else {
                cfg.workspace.habitat.ssh_enabled
            },
            namespace: optional_non_empty_or(&binding.namespace, &cfg.workspace.habitat.namespace),
            service_name: optional_non_empty_or(&binding.service_name, &cfg.workspace.habitat.service_name),
            internal_base_url: optional_non_empty_or(
                &binding.internal_base_url,
                &cfg.workspace.habitat.internal_base_url,
            ),
            health_path: optional_non_empty_or(&binding.health_path, &cfg.workspace.habitat.health_path),
            ssh_service_port: if binding.ssh_service_port == 0 {
                cfg.workspace.habitat.ssh_service_port
            } else {
                binding.ssh_service_port
            },
            ssh_user: optional_non_empty_or(&binding.ssh_user, &cfg.workspace.habitat.ssh_user),
            workspace_root: optional_non_empty_or(&binding.workspace_root, &cfg.workspace.habitat.workspace_root),
            context_dir: optional_non_empty_or(&binding.context_dir, &cfg.workspace.habitat.context_dir),
            context_packet_file: optional_non_empty_or(
                &binding.context_packet_file,
                &cfg.workspace.habitat.context_packet_file,
            ),
            context_env_file: optional_non_empty_or(&binding.context_env_file, &cfg.workspace.habitat.context_env_file),
        });
    }

    if cfg.workspace.cutover_workstream == requested {
        return Some(ResolvedWorkspaceHabitatBinding {
            workstream_id: requested.to_string(),
            workspace_id: cfg.workspace.canonical_workspace_id.clone(),
            session_id: "unassigned-session".to_string(),
            canonical_repo: cfg.workspace.canonical_repo.clone(),
            canonical_branch: cfg.workspace.canonical_branch.clone(),
            canonical_track: cfg.workspace.canonical_track.clone(),
            branch_lineage: cfg.workspace.cutover_branch_lineage.clone(),
            governance_state: cfg.workspace.cutover_state.clone(),
            governance_last_transition: cfg.workspace.cutover_last_transition.clone(),
            default_dev_plane: cfg.workspace.default_dev_plane.clone(),
            vm_fallback_role: cfg.workspace.vm_fallback_role.clone(),
            promotion_scope: cfg.workspace.promotion_scope.clone(),
            ide_kind: cfg.workspace.habitat.ide_kind.clone(),
            ssh_enabled: cfg.workspace.habitat.ssh_enabled,
            namespace: cfg.workspace.habitat.namespace.clone(),
            service_name: cfg.workspace.habitat.service_name.clone(),
            internal_base_url: cfg.workspace.habitat.internal_base_url.clone(),
            health_path: cfg.workspace.habitat.health_path.clone(),
            ssh_service_port: cfg.workspace.habitat.ssh_service_port,
            ssh_user: cfg.workspace.habitat.ssh_user.clone(),
            workspace_root: cfg.workspace.habitat.workspace_root.clone(),
            context_dir: cfg.workspace.habitat.context_dir.clone(),
            context_packet_file: cfg.workspace.habitat.context_packet_file.clone(),
            context_env_file: cfg.workspace.habitat.context_env_file.clone(),
        });
    }

    None
}

// ============================================================================
// ENDPOINTS EXTERNOS
// ============================================================================

/// URL do servidor vLLM (default: http://t560.local:8000)
pub fn vllm_url() -> String {
    env::var("BEAGLE_VLLM_URL").unwrap_or_else(|_| "http://t560.local:8000".to_string())
}

/// URL do servidor Grok API (xAI)
pub fn grok_api_url() -> String {
    env::var("BEAGLE_GROK_API_URL").unwrap_or_else(|_| "https://api.x.ai/v1".to_string())
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

        // Thresholds são usados em classify_hrv, não aqui
        let _min_hrv = env::var("BEAGLE_HRV_LOW_THRESHOLD")
            .ok()
            .and_then(|v| v.parse().ok())
            .or_else(|| {
                env::var("BEAGLE_HRV_MIN_MS")
                    .ok()
                    .and_then(|v| v.parse().ok())
            })
            .unwrap_or(30.0); // Threshold padrão para "low"

        let _max_hrv = env::var("BEAGLE_HRV_HIGH_THRESHOLD")
            .ok()
            .and_then(|v| v.parse().ok())
            .or_else(|| {
                env::var("BEAGLE_HRV_MAX_MS")
                    .ok()
                    .and_then(|v| v.parse().ok())
            })
            .unwrap_or(70.0); // Threshold padrão para "high"

        Self {
            min_gain,
            max_gain,
            min_hrv_ms: env::var("BEAGLE_HRV_MIN_MS")
                .ok()
                .and_then(|v| v.parse().ok())
                .unwrap_or(20.0),
            max_hrv_ms: env::var("BEAGLE_HRV_MAX_MS")
                .ok()
                .and_then(|v| v.parse().ok())
                .unwrap_or(200.0),
        }
    }
}

/// Classifica HRV em nível (low, normal, high)
///
/// # Arguments
/// - `hrv_ms`: Heart Rate Variability em milissegundos
/// - `cfg`: Configuração de HRV (usa default se None)
///
/// # Returns
/// String: "low" | "normal" | "high"
pub fn classify_hrv(hrv_ms: f32, _cfg: Option<&HrvControlConfig>) -> String {
    // Thresholds configuráveis via env (padrões: 30ms = low, 70ms = high)
    let low_threshold = env::var("BEAGLE_HRV_LOW_THRESHOLD")
        .ok()
        .and_then(|v| v.parse().ok())
        .unwrap_or(30.0);

    let high_threshold = env::var("BEAGLE_HRV_HIGH_THRESHOLD")
        .ok()
        .and_then(|v| v.parse().ok())
        .unwrap_or(70.0);

    if hrv_ms < low_threshold {
        "low".to_string()
    } else if hrv_ms > high_threshold {
        "high".to_string()
    } else {
        "normal".to_string()
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
    let normalized =
        ((hrv_ms - cfg.min_hrv_ms) / (cfg.max_hrv_ms - cfg.min_hrv_ms)).clamp(0.0, 1.0);

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

    #[test]
    fn test_workspace_habitat_binding_resolves_requested_workstream() {
        let previous = env::var("BEAGLE_WORKSPACE_HABITATS_JSON").ok();
        env::set_var(
            "BEAGLE_WORKSPACE_HABITATS_JSON",
            r#"[{
                "workstream_id":"sounio-lang-main",
                "workspace_id":"sounio-cluster-pilot",
                "session_id":"ws-cluster-sounio-habitat",
                "canonical_repo":"sounio-lang/sounio",
                "canonical_branch":"main",
                "canonical_track":"sounio-cluster",
                "branch_lineage":"main",
                "governance_state":"pilot",
                "governance_last_transition":"bootstrap",
                "default_dev_plane":"cluster",
                "vm_fallback_role":"dev-laptop",
                "promotion_scope":"sounio-lang-compiler-mainline",
                "ide_kind":"openvscode-server",
                "ssh_enabled":true,
                "namespace":"beagle",
                "service_name":"sounio-workspace",
                "internal_base_url":"http://sounio-workspace.beagle.svc.cluster.local:8080",
                "health_path":"/",
                "ssh_service_port":2222,
                "ssh_user":"openvscode-server",
                "workspace_root":"/workspace/sounio",
                "context_dir":"/workspace/sounio/.beagle/context",
                "context_packet_file":"/workspace/sounio/.beagle/context/workspace-context-packet.json",
                "context_env_file":"/workspace/sounio/.beagle/context/workspace-context.env"
            }]"#,
        );

        let cfg = load();
        let binding =
            resolve_workspace_habitat_binding(&cfg, "sounio-lang-main").expect("binding should resolve");

        assert_eq!(binding.workspace_id, "sounio-cluster-pilot");
        assert_eq!(binding.session_id, "ws-cluster-sounio-habitat");
        assert_eq!(binding.canonical_repo, "sounio-lang/sounio");
        assert_eq!(binding.canonical_branch, "main");
        assert_eq!(binding.service_name, "sounio-workspace");
        assert_eq!(binding.workspace_root, "/workspace/sounio");
        assert_eq!(
            binding.internal_base_url,
            "http://sounio-workspace.beagle.svc.cluster.local:8080"
        );

        if let Some(value) = previous {
            env::set_var("BEAGLE_WORKSPACE_HABITATS_JSON", value);
        } else {
            env::remove_var("BEAGLE_WORKSPACE_HABITATS_JSON");
        }
    }

    #[test]
    fn test_workspace_habitat_binding_falls_back_to_cutover_workspace() {
        let previous = env::var("BEAGLE_WORKSPACE_HABITATS_JSON").ok();
        let previous_cutover_workstream = env::var("BEAGLE_WORKSPACE_CUTOVER_WORKSTREAM").ok();
        let previous_workspace_id = env::var("BEAGLE_CANONICAL_WORKSPACE_ID").ok();
        let previous_repo = env::var("BEAGLE_WORKSPACE_CANONICAL_REPO").ok();
        let previous_branch = env::var("BEAGLE_WORKSPACE_CANONICAL_BRANCH").ok();
        let previous_track = env::var("BEAGLE_WORKSPACE_CANONICAL_TRACK").ok();
        let previous_cutover_state = env::var("BEAGLE_WORKSPACE_CUTOVER_STATE").ok();
        let previous_cutover_transition =
            env::var("BEAGLE_WORKSPACE_CUTOVER_LAST_TRANSITION").ok();
        env::remove_var("BEAGLE_WORKSPACE_HABITATS_JSON");
        env::set_var("BEAGLE_WORKSPACE_CUTOVER_WORKSTREAM", "beagle-darwin-hpc-governance");
        env::set_var("BEAGLE_CANONICAL_WORKSPACE_ID", "beagle-cluster-pilot");
        env::set_var("BEAGLE_WORKSPACE_CANONICAL_REPO", "sounio-lang/beagle");
        env::set_var("BEAGLE_WORKSPACE_CANONICAL_BRANCH", "main");
        env::set_var("BEAGLE_WORKSPACE_CANONICAL_TRACK", "beagle-cluster");
        env::set_var("BEAGLE_WORKSPACE_CUTOVER_STATE", "pilot");
        env::set_var("BEAGLE_WORKSPACE_CUTOVER_LAST_TRANSITION", "resume");

        let cfg = load();
        let binding = resolve_workspace_habitat_binding(&cfg, "beagle-darwin-hpc-governance")
            .expect("cutover fallback should resolve");

        assert_eq!(binding.workspace_id, "beagle-cluster-pilot");
        assert_eq!(binding.canonical_repo, "sounio-lang/beagle");
        assert_eq!(binding.canonical_branch, "main");
        assert_eq!(binding.governance_state, "pilot");
        assert_eq!(binding.governance_last_transition, "resume");

        if let Some(value) = previous {
            env::set_var("BEAGLE_WORKSPACE_HABITATS_JSON", value);
        } else {
            env::remove_var("BEAGLE_WORKSPACE_HABITATS_JSON");
        }
        if let Some(value) = previous_cutover_workstream {
            env::set_var("BEAGLE_WORKSPACE_CUTOVER_WORKSTREAM", value);
        } else {
            env::remove_var("BEAGLE_WORKSPACE_CUTOVER_WORKSTREAM");
        }
        if let Some(value) = previous_workspace_id {
            env::set_var("BEAGLE_CANONICAL_WORKSPACE_ID", value);
        } else {
            env::remove_var("BEAGLE_CANONICAL_WORKSPACE_ID");
        }
        if let Some(value) = previous_repo {
            env::set_var("BEAGLE_WORKSPACE_CANONICAL_REPO", value);
        } else {
            env::remove_var("BEAGLE_WORKSPACE_CANONICAL_REPO");
        }
        if let Some(value) = previous_branch {
            env::set_var("BEAGLE_WORKSPACE_CANONICAL_BRANCH", value);
        } else {
            env::remove_var("BEAGLE_WORKSPACE_CANONICAL_BRANCH");
        }
        if let Some(value) = previous_track {
            env::set_var("BEAGLE_WORKSPACE_CANONICAL_TRACK", value);
        } else {
            env::remove_var("BEAGLE_WORKSPACE_CANONICAL_TRACK");
        }
        if let Some(value) = previous_cutover_state {
            env::set_var("BEAGLE_WORKSPACE_CUTOVER_STATE", value);
        } else {
            env::remove_var("BEAGLE_WORKSPACE_CUTOVER_STATE");
        }
        if let Some(value) = previous_cutover_transition {
            env::set_var("BEAGLE_WORKSPACE_CUTOVER_LAST_TRANSITION", value);
        } else {
            env::remove_var("BEAGLE_WORKSPACE_CUTOVER_LAST_TRANSITION");
        }
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
    use model::AdvancedModulesConfig;

    // 1) Carrega defaults a partir de env
    let profile = env::var("BEAGLE_PROFILE")
        .unwrap_or_else(|_| "dev".to_string())
        .to_lowercase();

    let api_token = env::var("BEAGLE_API_TOKEN").ok();

    // Valida token em prod profile
    if profile == "prod" && api_token.is_none() {
        tracing::error!("BEAGLE_API_TOKEN é obrigatório no profile 'prod'");
        panic!("BEAGLE_API_TOKEN must be set when BEAGLE_PROFILE=prod");
    }

    // Log warning em dev/lab se token não estiver configurado
    if profile != "prod" && api_token.is_none() {
        tracing::warn!(
            "BEAGLE_API_TOKEN não configurado no profile '{}' - endpoints HTTP não terão autenticação",
            profile
        );
    }

    // Parse profile enum for routing config
    let profile_enum = model::Profile::from_str(&profile);

    let mut cfg = BeagleConfig {
        profile,
        safe_mode: bool_env("BEAGLE_SAFE_MODE", true),
        api_token,
        llm: LlmConfig {
            xai_api_key: env::var("XAI_API_KEY").ok(),
            anthropic_api_key: env::var("ANTHROPIC_API_KEY").ok(),
            openai_api_key: env::var("OPENAI_API_KEY").ok(),
            deepseek_api_key: env::var("DEEPSEEK_API_KEY").ok(),
            zai_api_key: env::var("ZAI_API_KEY").ok(),
            groq_api_key: env::var("GROQ_API_KEY").ok(),
            minimax_api_key: env::var("MINIMAX_API_KEY").ok(),
            vllm_url: env::var("VLLM_URL")
                .or_else(|_| env::var("BEAGLE_VLLM_URL"))
                .ok(),
            deepseek_base_url: env::var("BEAGLE_DEEPSEEK_BASE_URL")
                .or_else(|_| env::var("DEEPSEEK_BASE_URL"))
                .ok(),
            zai_base_url: env::var("BEAGLE_ZAI_BASE_URL")
                .or_else(|_| env::var("ZAI_BASE_URL"))
                .ok(),
            groq_base_url: env::var("BEAGLE_GROQ_BASE_URL")
                .or_else(|_| env::var("GROQ_BASE_URL"))
                .ok(),
            xai_base_url: env::var("BEAGLE_XAI_BASE_URL")
                .or_else(|_| env::var("XAI_BASE_URL"))
                .ok(),
            minimax_base_url: env::var("BEAGLE_MINIMAX_BASE_URL")
                .or_else(|_| env::var("MINIMAX_BASE_URL"))
                .ok(),
            grok_model: env::var("BEAGLE_GROK_MODEL").unwrap_or_else(|_| "grok-3".to_string()),
            kimi_model: env::var("BEAGLE_KIMI_MODEL")
                .unwrap_or_else(|_| "moonshotai/kimi-k2-instruct-0905".to_string()),
            routing: model::LlmRoutingConfig::from_env(profile_enum),
        },
        storage: StorageConfig {
            data_dir: beagle_data_dir().to_string_lossy().to_string(),
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
        tool_bridge: model::ToolBridgeConfig {
            default_timeout_seconds: env::var("BEAGLE_TOOL_BRIDGE_TIMEOUT_SECONDS")
                .ok()
                .and_then(|v| v.parse().ok())
                .unwrap_or(60),
            ledger_enabled: bool_env("BEAGLE_TOOL_BRIDGE_LEDGER_ENABLED", true),
            dry_run: bool_env("BEAGLE_TOOL_BRIDGE_DRY_RUN", false),
        },
        workspace: model::WorkspacePlaneConfig {
            canonical_workspace_id: env::var("BEAGLE_WORKSPACE_CANONICAL_ID")
                .unwrap_or_else(|_| "beagle-cluster-pilot".to_string()),
            canonical_repo: env::var("BEAGLE_WORKSPACE_CANONICAL_REPO")
                .unwrap_or_else(|_| "agourakis82/beagle".to_string()),
            canonical_branch: env::var("BEAGLE_WORKSPACE_CANONICAL_BRANCH")
                .unwrap_or_else(|_| "main".to_string()),
            canonical_track: env::var("BEAGLE_WORKSPACE_CANONICAL_TRACK")
                .unwrap_or_else(|_| "darwin-hpc".to_string()),
            operator_name: env::var("BEAGLE_WORKSPACE_OPERATOR").ok(),
            default_dev_plane: env::var("BEAGLE_WORKSPACE_DEFAULT_DEV_PLANE")
                .unwrap_or_else(|_| "beagle-cluster".to_string()),
            vm_fallback_role: env::var("BEAGLE_WORKSPACE_VM_FALLBACK_ROLE")
                .unwrap_or_else(|_| "fallback-only".to_string()),
            promotion_scope: env::var("BEAGLE_WORKSPACE_PROMOTION_SCOPE")
                .unwrap_or_else(|_| "beagle-darwin-hpc-general-noninfra".to_string()),
            cutover_workstream: env::var("BEAGLE_WORKSPACE_CUTOVER_WORKSTREAM")
                .unwrap_or_else(|_| "beagle-darwin-hpc-governance".to_string()),
            cutover_state: env::var("BEAGLE_WORKSPACE_CUTOVER_STATE")
                .unwrap_or_else(|_| "canonical".to_string()),
            cutover_last_transition: env::var("BEAGLE_WORKSTREAM_LAST_TRANSITION")
                .unwrap_or_else(|_| "resume".to_string()),
            cutover_branch_lineage: env::var("BEAGLE_WORKSPACE_CUTOVER_BRANCH_LINEAGE")
                .unwrap_or_else(|_| "feat/darwin-hpc-governance".to_string()),
            cutover_default_profile: env::var("BEAGLE_WORKSTREAM_DEFAULT_PROFILE")
                .unwrap_or_else(|_| "cpu-short-v1".to_string()),
            cutover_batch_profile: env::var("BEAGLE_WORKSTREAM_BATCH_PROFILE")
                .unwrap_or_else(|_| "cpu-batch-v1".to_string()),
            cutover_advanced_profile: env::var("BEAGLE_WORKSTREAM_ADVANCED_PROFILE")
                .unwrap_or_else(|_| "gpu-single-v1".to_string()),
            cutover_result_publication: env::var("BEAGLE_WORKSTREAM_RESULT_PUBLICATION")
                .unwrap_or_else(|_| "object-backed".to_string()),
            cutover_result_retrieval: env::var("BEAGLE_WORKSTREAM_RESULT_RETRIEVAL")
                .unwrap_or_else(|_| "object-backed".to_string()),
            cutover_result_retention_policy: env::var(
                "BEAGLE_WORKSTREAM_RESULT_RETENTION_POLICY",
            )
            .unwrap_or_else(|_| "active".to_string()),
            cutover_operator_consumer_policy: env::var(
                "BEAGLE_WORKSTREAM_OPERATOR_CONSUMER_POLICY",
            )
            .unwrap_or_else(|_| "full".to_string()),
            cutover_research_consumer_policy: env::var(
                "BEAGLE_WORKSTREAM_RESEARCH_CONSUMER_POLICY",
            )
            .unwrap_or_else(|_| "bounded".to_string()),
            cutover_recovery_required: bool_env(
                "BEAGLE_WORKSPACE_CUTOVER_RECOVERY_REQUIRED",
                true,
            ),
            cutover_handoff_required: bool_env(
                "BEAGLE_WORKSPACE_CUTOVER_HANDOFF_REQUIRED",
                true,
            ),
            bootstrap_enabled: bool_env("BEAGLE_WORKSPACE_BOOTSTRAP_ENABLED", true),
            habitat: model::WorkspaceHabitatConfig {
                enabled: bool_env("BEAGLE_WORKSPACE_HABITAT_ENABLED", true),
                ide_kind: env::var("BEAGLE_WORKSPACE_HABITAT_IDE")
                    .unwrap_or_else(|_| "openvscode-server".to_string()),
                ssh_enabled: bool_env("BEAGLE_WORKSPACE_HABITAT_SSH_ENABLED", false),
                namespace: env::var("BEAGLE_WORKSPACE_HABITAT_NAMESPACE")
                    .unwrap_or_else(|_| "beagle".to_string()),
                service_name: env::var("BEAGLE_WORKSPACE_HABITAT_SERVICE_NAME")
                    .unwrap_or_else(|_| "beagle-workspace".to_string()),
                internal_base_url: env::var("BEAGLE_WORKSPACE_HABITAT_INTERNAL_BASE_URL")
                    .unwrap_or_else(|_| {
                        "http://beagle-workspace.beagle.svc.cluster.local:8080".to_string()
                    }),
                health_path: env::var("BEAGLE_WORKSPACE_HABITAT_HEALTH_PATH")
                    .unwrap_or_else(|_| "/".to_string()),
                ssh_service_port: env::var("BEAGLE_WORKSPACE_HABITAT_SSH_SERVICE_PORT")
                    .ok()
                    .and_then(|value| value.parse::<u16>().ok())
                    .unwrap_or(2222),
                ssh_user: env::var("BEAGLE_WORKSPACE_HABITAT_SSH_USER")
                    .unwrap_or_else(|_| "openvscode-server".to_string()),
                workspace_root: env::var("BEAGLE_WORKSPACE_HABITAT_WORKSPACE_ROOT")
                    .unwrap_or_else(|_| "/workspace/beagle".to_string()),
                context_dir: env::var("BEAGLE_WORKSPACE_HABITAT_CONTEXT_DIR")
                    .unwrap_or_else(|_| "/workspace/beagle/.beagle/context".to_string()),
                context_packet_file: env::var("BEAGLE_WORKSPACE_HABITAT_CONTEXT_PACKET_FILE")
                    .unwrap_or_else(|_| {
                        "/workspace/beagle/.beagle/context/current-context-packet.json"
                            .to_string()
                    }),
                context_env_file: env::var("BEAGLE_WORKSPACE_HABITAT_ENV_FILE")
                    .unwrap_or_else(|_| {
                        "/workspace/beagle/.beagle/context/beagle-context.env".to_string()
                    }),
            },
        },
        consumers: model::ConsumerAccessConfig {
            policy_enabled: bool_env("BEAGLE_CONSUMER_POLICY_ENABLED", false),
            operator_token: env::var("BEAGLE_OPERATOR_API_TOKEN")
                .ok()
                .or_else(|| env::var("BEAGLE_API_TOKEN").ok()),
            research_token: env::var("BEAGLE_RESEARCH_API_TOKEN").ok(),
        },
        advanced: AdvancedModulesConfig {
            serendipity_enabled: bool_env("BEAGLE_SERENDIPITY", false),
            serendipity_in_triad: bool_env("BEAGLE_SERENDIPITY_TRIAD", false),
            void_enabled: bool_env("BEAGLE_VOID_ENABLED", false),
            memory_retrieval_enabled: bool_env("BEAGLE_MEMORY_RETRIEVAL", false),
        },
        observer: model::ObserverThresholds::default(),
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

// default_data_dir removido - agora usa beagle_data_dir() diretamente

///// Merge de configurações: `base` é mantido, `override_cfg` sobrepõe apenas campos Some
fn merge_config(base: BeagleConfig, override_cfg: BeagleConfig) -> BeagleConfig {
    use model::AdvancedModulesConfig;

    BeagleConfig {
        profile: override_cfg.profile.clone(),
        safe_mode: override_cfg.safe_mode,
        api_token: override_cfg.api_token.or(base.api_token),
        llm: LlmConfig {
            xai_api_key: override_cfg.llm.xai_api_key.or(base.llm.xai_api_key),
            anthropic_api_key: override_cfg
                .llm
                .anthropic_api_key
                .or(base.llm.anthropic_api_key),
            openai_api_key: override_cfg.llm.openai_api_key.or(base.llm.openai_api_key),
            deepseek_api_key: override_cfg.llm.deepseek_api_key.or(base.llm.deepseek_api_key),
            zai_api_key: override_cfg.llm.zai_api_key.or(base.llm.zai_api_key),
            groq_api_key: override_cfg.llm.groq_api_key.or(base.llm.groq_api_key),
            minimax_api_key: override_cfg.llm.minimax_api_key.or(base.llm.minimax_api_key),
            vllm_url: override_cfg.llm.vllm_url.or(base.llm.vllm_url),
            deepseek_base_url: override_cfg
                .llm
                .deepseek_base_url
                .or(base.llm.deepseek_base_url),
            zai_base_url: override_cfg.llm.zai_base_url.or(base.llm.zai_base_url),
            groq_base_url: override_cfg.llm.groq_base_url.or(base.llm.groq_base_url),
            xai_base_url: override_cfg.llm.xai_base_url.or(base.llm.xai_base_url),
            minimax_base_url: override_cfg
                .llm
                .minimax_base_url
                .or(base.llm.minimax_base_url),
            grok_model: if override_cfg.llm.grok_model != default_grok_model() {
                override_cfg.llm.grok_model
            } else {
                base.llm.grok_model
            },
            kimi_model: if override_cfg.llm.kimi_model != "moonshotai/kimi-k2-instruct-0905" {
                override_cfg.llm.kimi_model
            } else {
                base.llm.kimi_model
            },
            routing: override_cfg.llm.routing.clone(),
        },
        storage: StorageConfig {
            data_dir: override_cfg.storage.data_dir.clone(),
        },
        graph: GraphConfig {
            neo4j_uri: override_cfg.graph.neo4j_uri.or(base.graph.neo4j_uri),
            neo4j_user: override_cfg.graph.neo4j_user.or(base.graph.neo4j_user),
            neo4j_password: override_cfg
                .graph
                .neo4j_password
                .or(base.graph.neo4j_password),
            qdrant_url: override_cfg.graph.qdrant_url.or(base.graph.qdrant_url),
        },
        hermes: HermesConfig {
            database_url: override_cfg
                .hermes
                .database_url
                .or(base.hermes.database_url),
            redis_url: override_cfg.hermes.redis_url.or(base.hermes.redis_url),
        },
        tool_bridge: override_cfg.tool_bridge.clone(),
        workspace: model::WorkspacePlaneConfig {
            canonical_workspace_id: if override_cfg.workspace.canonical_workspace_id
                != model::WorkspacePlaneConfig::default().canonical_workspace_id
            {
                override_cfg.workspace.canonical_workspace_id
            } else {
                base.workspace.canonical_workspace_id
            },
            canonical_repo: if override_cfg.workspace.canonical_repo
                != model::WorkspacePlaneConfig::default().canonical_repo
            {
                override_cfg.workspace.canonical_repo
            } else {
                base.workspace.canonical_repo
            },
            canonical_branch: if override_cfg.workspace.canonical_branch
                != model::WorkspacePlaneConfig::default().canonical_branch
            {
                override_cfg.workspace.canonical_branch
            } else {
                base.workspace.canonical_branch
            },
            canonical_track: if override_cfg.workspace.canonical_track
                != model::WorkspacePlaneConfig::default().canonical_track
            {
                override_cfg.workspace.canonical_track
            } else {
                base.workspace.canonical_track
            },
            operator_name: override_cfg.workspace.operator_name.or(base.workspace.operator_name),
            default_dev_plane: if override_cfg.workspace.default_dev_plane
                != model::WorkspacePlaneConfig::default().default_dev_plane
            {
                override_cfg.workspace.default_dev_plane
            } else {
                base.workspace.default_dev_plane
            },
            vm_fallback_role: if override_cfg.workspace.vm_fallback_role
                != model::WorkspacePlaneConfig::default().vm_fallback_role
            {
                override_cfg.workspace.vm_fallback_role
            } else {
                base.workspace.vm_fallback_role
            },
            promotion_scope: if override_cfg.workspace.promotion_scope
                != model::WorkspacePlaneConfig::default().promotion_scope
            {
                override_cfg.workspace.promotion_scope
            } else {
                base.workspace.promotion_scope
            },
            cutover_workstream: if override_cfg.workspace.cutover_workstream
                != model::WorkspacePlaneConfig::default().cutover_workstream
            {
                override_cfg.workspace.cutover_workstream
            } else {
                base.workspace.cutover_workstream
            },
            cutover_state: if override_cfg.workspace.cutover_state
                != model::WorkspacePlaneConfig::default().cutover_state
            {
                override_cfg.workspace.cutover_state
            } else {
                base.workspace.cutover_state
            },
            cutover_last_transition: if override_cfg.workspace.cutover_last_transition
                != model::WorkspacePlaneConfig::default().cutover_last_transition
            {
                override_cfg.workspace.cutover_last_transition
            } else {
                base.workspace.cutover_last_transition
            },
            cutover_branch_lineage: if override_cfg.workspace.cutover_branch_lineage
                != model::WorkspacePlaneConfig::default().cutover_branch_lineage
            {
                override_cfg.workspace.cutover_branch_lineage
            } else {
                base.workspace.cutover_branch_lineage
            },
            cutover_default_profile: if override_cfg.workspace.cutover_default_profile
                != model::WorkspacePlaneConfig::default().cutover_default_profile
            {
                override_cfg.workspace.cutover_default_profile
            } else {
                base.workspace.cutover_default_profile
            },
            cutover_batch_profile: if override_cfg.workspace.cutover_batch_profile
                != model::WorkspacePlaneConfig::default().cutover_batch_profile
            {
                override_cfg.workspace.cutover_batch_profile
            } else {
                base.workspace.cutover_batch_profile
            },
            cutover_advanced_profile: if override_cfg.workspace.cutover_advanced_profile
                != model::WorkspacePlaneConfig::default().cutover_advanced_profile
            {
                override_cfg.workspace.cutover_advanced_profile
            } else {
                base.workspace.cutover_advanced_profile
            },
            cutover_result_publication: if override_cfg.workspace.cutover_result_publication
                != model::WorkspacePlaneConfig::default().cutover_result_publication
            {
                override_cfg.workspace.cutover_result_publication
            } else {
                base.workspace.cutover_result_publication
            },
            cutover_result_retrieval: if override_cfg.workspace.cutover_result_retrieval
                != model::WorkspacePlaneConfig::default().cutover_result_retrieval
            {
                override_cfg.workspace.cutover_result_retrieval
            } else {
                base.workspace.cutover_result_retrieval
            },
            cutover_result_retention_policy: if override_cfg
                .workspace
                .cutover_result_retention_policy
                != model::WorkspacePlaneConfig::default().cutover_result_retention_policy
            {
                override_cfg.workspace.cutover_result_retention_policy
            } else {
                base.workspace.cutover_result_retention_policy
            },
            cutover_operator_consumer_policy: if override_cfg
                .workspace
                .cutover_operator_consumer_policy
                != model::WorkspacePlaneConfig::default().cutover_operator_consumer_policy
            {
                override_cfg.workspace.cutover_operator_consumer_policy
            } else {
                base.workspace.cutover_operator_consumer_policy
            },
            cutover_research_consumer_policy: if override_cfg
                .workspace
                .cutover_research_consumer_policy
                != model::WorkspacePlaneConfig::default().cutover_research_consumer_policy
            {
                override_cfg.workspace.cutover_research_consumer_policy
            } else {
                base.workspace.cutover_research_consumer_policy
            },
            cutover_recovery_required: override_cfg.workspace.cutover_recovery_required
                || base.workspace.cutover_recovery_required,
            cutover_handoff_required: override_cfg.workspace.cutover_handoff_required
                || base.workspace.cutover_handoff_required,
            bootstrap_enabled: override_cfg.workspace.bootstrap_enabled
                || base.workspace.bootstrap_enabled,
            habitat: model::WorkspaceHabitatConfig {
                enabled: override_cfg.workspace.habitat.enabled || base.workspace.habitat.enabled,
                ide_kind: if override_cfg.workspace.habitat.ide_kind
                    != model::WorkspaceHabitatConfig::default().ide_kind
                {
                    override_cfg.workspace.habitat.ide_kind
                } else {
                    base.workspace.habitat.ide_kind
                },
                ssh_enabled: override_cfg.workspace.habitat.ssh_enabled
                    || base.workspace.habitat.ssh_enabled,
                namespace: if override_cfg.workspace.habitat.namespace
                    != model::WorkspaceHabitatConfig::default().namespace
                {
                    override_cfg.workspace.habitat.namespace
                } else {
                    base.workspace.habitat.namespace
                },
                service_name: if override_cfg.workspace.habitat.service_name
                    != model::WorkspaceHabitatConfig::default().service_name
                {
                    override_cfg.workspace.habitat.service_name
                } else {
                    base.workspace.habitat.service_name
                },
                internal_base_url: if override_cfg.workspace.habitat.internal_base_url
                    != model::WorkspaceHabitatConfig::default().internal_base_url
                {
                    override_cfg.workspace.habitat.internal_base_url
                } else {
                    base.workspace.habitat.internal_base_url
                },
                health_path: if override_cfg.workspace.habitat.health_path
                    != model::WorkspaceHabitatConfig::default().health_path
                {
                    override_cfg.workspace.habitat.health_path
                } else {
                    base.workspace.habitat.health_path
                },
                ssh_service_port: if override_cfg.workspace.habitat.ssh_service_port
                    != model::WorkspaceHabitatConfig::default().ssh_service_port
                {
                    override_cfg.workspace.habitat.ssh_service_port
                } else {
                    base.workspace.habitat.ssh_service_port
                },
                ssh_user: if override_cfg.workspace.habitat.ssh_user
                    != model::WorkspaceHabitatConfig::default().ssh_user
                {
                    override_cfg.workspace.habitat.ssh_user
                } else {
                    base.workspace.habitat.ssh_user
                },
                workspace_root: if override_cfg.workspace.habitat.workspace_root
                    != model::WorkspaceHabitatConfig::default().workspace_root
                {
                    override_cfg.workspace.habitat.workspace_root
                } else {
                    base.workspace.habitat.workspace_root
                },
                context_dir: if override_cfg.workspace.habitat.context_dir
                    != model::WorkspaceHabitatConfig::default().context_dir
                {
                    override_cfg.workspace.habitat.context_dir
                } else {
                    base.workspace.habitat.context_dir
                },
                context_packet_file: if override_cfg.workspace.habitat.context_packet_file
                    != model::WorkspaceHabitatConfig::default().context_packet_file
                {
                    override_cfg.workspace.habitat.context_packet_file
                } else {
                    base.workspace.habitat.context_packet_file
                },
                context_env_file: if override_cfg.workspace.habitat.context_env_file
                    != model::WorkspaceHabitatConfig::default().context_env_file
                {
                    override_cfg.workspace.habitat.context_env_file
                } else {
                    base.workspace.habitat.context_env_file
                },
            },
        },
        consumers: model::ConsumerAccessConfig {
            policy_enabled: override_cfg.consumers.policy_enabled || base.consumers.policy_enabled,
            operator_token: override_cfg.consumers.operator_token.or(base.consumers.operator_token),
            research_token: override_cfg.consumers.research_token.or(base.consumers.research_token),
        },
        advanced: AdvancedModulesConfig {
            serendipity_enabled: override_cfg.advanced.serendipity_enabled
                || base.advanced.serendipity_enabled,
            serendipity_in_triad: override_cfg.advanced.serendipity_in_triad
                || base.advanced.serendipity_in_triad,
            void_enabled: override_cfg.advanced.void_enabled || base.advanced.void_enabled,
            memory_retrieval_enabled: override_cfg.advanced.memory_retrieval_enabled
                || base.advanced.memory_retrieval_enabled,
        },
        observer: override_cfg.observer.clone(),
    }
}
