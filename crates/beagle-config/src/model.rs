//! Modelo tipado de configuração do BEAGLE
//!
//! Estruturas centralizadas para todas as configurações do sistema,
//! substituindo acesso direto a variáveis de ambiente espalhadas.

use serde::{Deserialize, Serialize};
use std::path::PathBuf;

/// Configuração de LLMs (Grok, Claude, OpenAI, vLLM)
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct LlmConfig {
    pub xai_api_key: Option<String>,
    pub anthropic_api_key: Option<String>,
    pub openai_api_key: Option<String>,
    pub deepseek_api_key: Option<String>,
    pub zai_api_key: Option<String>,
    pub groq_api_key: Option<String>,
    pub minimax_api_key: Option<String>,
    pub vllm_url: Option<String>,
    pub deepseek_base_url: Option<String>,
    pub zai_base_url: Option<String>,
    pub groq_base_url: Option<String>,
    pub xai_base_url: Option<String>,
    pub minimax_base_url: Option<String>,
    /// Modelo Grok padrão (default: "grok-3")
    #[serde(default = "default_grok_model")]
    pub grok_model: String,
    /// Modelo Kimi padrão no backend Groq
    #[serde(default = "default_kimi_model")]
    pub kimi_model: String,
    /// Configuração de roteamento e limites
    #[serde(default)]
    pub routing: LlmRoutingConfig,
}

/// Configuração de roteamento de LLM e limites de uso
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct LlmRoutingConfig {
    /// Habilita uso de Grok 4 Heavy (Tier 2)
    #[serde(default)]
    pub enable_heavy: bool,

    /// Máximo de chamadas Heavy por run
    #[serde(default = "default_heavy_max_calls_per_run")]
    pub heavy_max_calls_per_run: u32,

    /// Máximo de tokens Heavy por run
    #[serde(default = "default_heavy_max_tokens_per_run")]
    pub heavy_max_tokens_per_run: u32,

    /// Máximo de chamadas Heavy por dia (reservado para implementação futura)
    #[serde(default = "default_heavy_max_calls_per_day")]
    pub heavy_max_calls_per_day: u32,
}

fn default_heavy_max_calls_per_run() -> u32 {
    5
}

fn default_heavy_max_tokens_per_run() -> u32 {
    50_000
}

fn default_heavy_max_calls_per_day() -> u32 {
    100
}

impl Default for LlmRoutingConfig {
    fn default() -> Self {
        Self {
            enable_heavy: false,
            heavy_max_calls_per_run: default_heavy_max_calls_per_run(),
            heavy_max_tokens_per_run: default_heavy_max_tokens_per_run(),
            heavy_max_calls_per_day: default_heavy_max_calls_per_day(),
        }
    }
}

impl LlmRoutingConfig {
    /// Carrega configuração de roteamento baseada no profile
    pub fn from_profile(profile: Profile) -> Self {
        match profile {
            Profile::Dev => Self {
                enable_heavy: false,
                heavy_max_calls_per_run: 0,
                heavy_max_tokens_per_run: 0,
                heavy_max_calls_per_day: 0,
            },
            Profile::Lab => Self {
                enable_heavy: true,
                heavy_max_calls_per_run: 5,
                heavy_max_tokens_per_run: 50_000,
                heavy_max_calls_per_day: 50,
            },
            Profile::Prod => Self {
                enable_heavy: true,
                heavy_max_calls_per_run: 10,
                heavy_max_tokens_per_run: 100_000,
                heavy_max_calls_per_day: 200,
            },
        }
    }

    /// Carrega da configuração aplicando overrides de env vars
    pub fn from_env(profile: Profile) -> Self {
        use std::env;

        let mut config = Self::from_profile(profile);

        // Override com env vars se presentes
        if let Ok(val) = env::var("BEAGLE_HEAVY_ENABLE") {
            config.enable_heavy = matches!(val.to_lowercase().as_str(), "1" | "true" | "yes");
        }

        if let Ok(val) = env::var("BEAGLE_HEAVY_MAX_CALLS_PER_RUN") {
            if let Ok(num) = val.parse() {
                config.heavy_max_calls_per_run = num;
            }
        }

        if let Ok(val) = env::var("BEAGLE_HEAVY_MAX_TOKENS_PER_RUN") {
            if let Ok(num) = val.parse() {
                config.heavy_max_tokens_per_run = num;
            }
        }

        if let Ok(val) = env::var("BEAGLE_HEAVY_MAX_CALLS_PER_DAY") {
            if let Ok(num) = val.parse() {
                config.heavy_max_calls_per_day = num;
            }
        }

        config
    }
}

fn default_grok_model() -> String {
    "grok-3".to_string()
}

fn default_kimi_model() -> String {
    "moonshotai/kimi-k2-instruct-0905".to_string()
}

impl Default for LlmConfig {
    fn default() -> Self {
        Self {
            xai_api_key: None,
            anthropic_api_key: None,
            openai_api_key: None,
            deepseek_api_key: None,
            zai_api_key: None,
            groq_api_key: None,
            minimax_api_key: None,
            vllm_url: None,
            deepseek_base_url: None,
            zai_base_url: None,
            groq_base_url: None,
            xai_base_url: None,
            minimax_base_url: None,
            grok_model: default_grok_model(),
            kimi_model: default_kimi_model(),
            routing: LlmRoutingConfig::default(),
        }
    }
}

/// Configuração de armazenamento
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct StorageConfig {
    pub data_dir: String,
}

impl StorageConfig {
    pub fn data_dir_path(&self) -> PathBuf {
        PathBuf::from(&self.data_dir)
    }
}

/// Configuração de grafos (Neo4j, Qdrant)
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct GraphConfig {
    pub neo4j_uri: Option<String>,
    pub neo4j_user: Option<String>,
    pub neo4j_password: Option<String>,
    pub qdrant_url: Option<String>,
}

impl Default for GraphConfig {
    fn default() -> Self {
        Self {
            neo4j_uri: None,
            neo4j_user: None,
            neo4j_password: None,
            qdrant_url: None,
        }
    }
}

/// Configuração do HERMES (Postgres, Redis)
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct HermesConfig {
    pub database_url: Option<String>,
    pub redis_url: Option<String>,
}

impl Default for HermesConfig {
    fn default() -> Self {
        Self {
            database_url: None,
            redis_url: None,
        }
    }
}

/// Configuração de módulos avançados (Serendipity, Void, MemoryRetrieval)
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct AdvancedModulesConfig {
    /// Habilita módulo Serendipity (descoberta de conexões inesperadas)
    #[serde(default = "default_false")]
    pub serendipity_enabled: bool,
    /// Aplica Serendipity na Triad (perturbação de prompts)
    #[serde(default = "default_false")]
    pub serendipity_in_triad: bool,
    /// Habilita módulo Void (detecção e resolução de deadlocks)
    #[serde(default = "default_false")]
    pub void_enabled: bool,
    /// Habilita retrieval de memória no pipeline (Memory RAG injection)
    #[serde(default = "default_false")]
    pub memory_retrieval_enabled: bool,
}

fn default_false() -> bool {
    false
}

fn default_true() -> bool {
    true
}

impl Default for AdvancedModulesConfig {
    fn default() -> Self {
        Self {
            serendipity_enabled: false,
            serendipity_in_triad: false,
            void_enabled: false,
            memory_retrieval_enabled: false,
        }
    }
}

/// Configuração mínima da bridge de tools/providers do Beagle.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ToolBridgeConfig {
    #[serde(default = "default_bridge_timeout_seconds")]
    pub default_timeout_seconds: u64,
    #[serde(default = "default_true")]
    pub ledger_enabled: bool,
    #[serde(default = "default_false")]
    pub dry_run: bool,
}

const fn default_bridge_timeout_seconds() -> u64 {
    60
}

impl Default for ToolBridgeConfig {
    fn default() -> Self {
        Self {
            default_timeout_seconds: default_bridge_timeout_seconds(),
            ledger_enabled: true,
            dry_run: false,
        }
    }
}

/// Configuração mínima da workspace plane do Beagle.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct WorkspacePlaneConfig {
    pub canonical_workspace_id: String,
    pub canonical_repo: String,
    pub canonical_branch: String,
    pub canonical_track: String,
    pub operator_name: Option<String>,
    pub default_dev_plane: String,
    pub vm_fallback_role: String,
    pub promotion_scope: String,
    #[serde(default = "default_cutover_workstream")]
    pub cutover_workstream: String,
    #[serde(default = "default_cutover_state")]
    pub cutover_state: String,
    #[serde(default = "default_cutover_last_transition")]
    pub cutover_last_transition: String,
    #[serde(default = "default_cutover_branch_lineage")]
    pub cutover_branch_lineage: String,
    #[serde(default = "default_cutover_default_profile")]
    pub cutover_default_profile: String,
    #[serde(default = "default_cutover_batch_profile")]
    pub cutover_batch_profile: String,
    #[serde(default = "default_cutover_advanced_profile")]
    pub cutover_advanced_profile: String,
    #[serde(default = "default_cutover_result_publication")]
    pub cutover_result_publication: String,
    #[serde(default = "default_cutover_result_retrieval")]
    pub cutover_result_retrieval: String,
    #[serde(default = "default_cutover_result_retention_policy")]
    pub cutover_result_retention_policy: String,
    #[serde(default = "default_cutover_operator_consumer_policy")]
    pub cutover_operator_consumer_policy: String,
    #[serde(default = "default_cutover_research_consumer_policy")]
    pub cutover_research_consumer_policy: String,
    #[serde(default = "default_true")]
    pub cutover_recovery_required: bool,
    #[serde(default = "default_true")]
    pub cutover_handoff_required: bool,
    #[serde(default = "default_true")]
    pub bootstrap_enabled: bool,
    #[serde(default)]
    pub habitat: WorkspaceHabitatConfig,
}

/// Configuração bounded do habitat de workspace remoto no cluster.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct WorkspaceHabitatConfig {
    #[serde(default = "default_true")]
    pub enabled: bool,
    #[serde(default = "default_workspace_habitat_ide")]
    pub ide_kind: String,
    #[serde(default = "default_false")]
    pub ssh_enabled: bool,
    #[serde(default = "default_workspace_habitat_namespace")]
    pub namespace: String,
    #[serde(default = "default_workspace_habitat_service_name")]
    pub service_name: String,
    #[serde(default = "default_workspace_habitat_internal_base_url")]
    pub internal_base_url: String,
    #[serde(default = "default_workspace_habitat_health_path")]
    pub health_path: String,
    #[serde(default = "default_workspace_habitat_ssh_service_port")]
    pub ssh_service_port: u16,
    #[serde(default = "default_workspace_habitat_ssh_user")]
    pub ssh_user: String,
    #[serde(default = "default_workspace_habitat_workspace_root")]
    pub workspace_root: String,
    #[serde(default = "default_workspace_habitat_context_dir")]
    pub context_dir: String,
    #[serde(default = "default_workspace_habitat_context_packet_file")]
    pub context_packet_file: String,
    #[serde(default = "default_workspace_habitat_env_file")]
    pub context_env_file: String,
}

/// Binding explícito entre um workstream e um habitat/workspace remoto dedicado.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct WorkspaceHabitatBindingConfig {
    pub workstream_id: String,
    #[serde(default)]
    pub workspace_id: String,
    #[serde(default)]
    pub session_id: String,
    #[serde(default)]
    pub canonical_repo: String,
    #[serde(default)]
    pub canonical_branch: String,
    #[serde(default)]
    pub canonical_track: String,
    #[serde(default)]
    pub branch_lineage: String,
    #[serde(default)]
    pub governance_state: String,
    #[serde(default)]
    pub governance_last_transition: String,
    #[serde(default)]
    pub default_dev_plane: String,
    #[serde(default)]
    pub vm_fallback_role: String,
    #[serde(default)]
    pub promotion_scope: String,
    #[serde(default)]
    pub ide_kind: String,
    #[serde(default)]
    pub ssh_enabled: bool,
    #[serde(default)]
    pub namespace: String,
    #[serde(default)]
    pub service_name: String,
    #[serde(default)]
    pub internal_base_url: String,
    #[serde(default)]
    pub health_path: String,
    #[serde(default)]
    pub ssh_service_port: u16,
    #[serde(default)]
    pub ssh_user: String,
    #[serde(default)]
    pub workspace_root: String,
    #[serde(default)]
    pub context_dir: String,
    #[serde(default)]
    pub context_packet_file: String,
    #[serde(default)]
    pub context_env_file: String,
}

impl Default for WorkspaceHabitatBindingConfig {
    fn default() -> Self {
        Self {
            workstream_id: String::new(),
            workspace_id: String::new(),
            session_id: String::new(),
            canonical_repo: String::new(),
            canonical_branch: String::new(),
            canonical_track: String::new(),
            branch_lineage: String::new(),
            governance_state: String::new(),
            governance_last_transition: String::new(),
            default_dev_plane: String::new(),
            vm_fallback_role: String::new(),
            promotion_scope: String::new(),
            ide_kind: String::new(),
            ssh_enabled: false,
            namespace: String::new(),
            service_name: String::new(),
            internal_base_url: String::new(),
            health_path: String::new(),
            ssh_service_port: 0,
            ssh_user: String::new(),
            workspace_root: String::new(),
            context_dir: String::new(),
            context_packet_file: String::new(),
            context_env_file: String::new(),
        }
    }
}

/// Binding fully resolved for a workstream-specific habitat after merging defaults.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ResolvedWorkspaceHabitatBinding {
    pub workstream_id: String,
    pub workspace_id: String,
    pub session_id: String,
    pub canonical_repo: String,
    pub canonical_branch: String,
    pub canonical_track: String,
    pub branch_lineage: String,
    pub governance_state: String,
    pub governance_last_transition: String,
    pub default_dev_plane: String,
    pub vm_fallback_role: String,
    pub promotion_scope: String,
    pub ide_kind: String,
    pub ssh_enabled: bool,
    pub namespace: String,
    pub service_name: String,
    pub internal_base_url: String,
    pub health_path: String,
    pub ssh_service_port: u16,
    pub ssh_user: String,
    pub workspace_root: String,
    pub context_dir: String,
    pub context_packet_file: String,
    pub context_env_file: String,
}

impl Default for WorkspaceHabitatConfig {
    fn default() -> Self {
        Self {
            enabled: true,
            ide_kind: default_workspace_habitat_ide(),
            ssh_enabled: default_false(),
            namespace: default_workspace_habitat_namespace(),
            service_name: default_workspace_habitat_service_name(),
            internal_base_url: default_workspace_habitat_internal_base_url(),
            health_path: default_workspace_habitat_health_path(),
            ssh_service_port: default_workspace_habitat_ssh_service_port(),
            ssh_user: default_workspace_habitat_ssh_user(),
            workspace_root: default_workspace_habitat_workspace_root(),
            context_dir: default_workspace_habitat_context_dir(),
            context_packet_file: default_workspace_habitat_context_packet_file(),
            context_env_file: default_workspace_habitat_env_file(),
        }
    }
}

impl Default for WorkspacePlaneConfig {
    fn default() -> Self {
        Self {
            canonical_workspace_id: "beagle-cluster-pilot".to_string(),
            canonical_repo: "agourakis82/beagle".to_string(),
            canonical_branch: "main".to_string(),
            canonical_track: "darwin-hpc".to_string(),
            operator_name: None,
            default_dev_plane: "beagle-cluster".to_string(),
            vm_fallback_role: "fallback-only".to_string(),
            promotion_scope: "beagle-darwin-hpc-general-noninfra".to_string(),
            cutover_workstream: "beagle-darwin-hpc-governance".to_string(),
            cutover_state: "canonical".to_string(),
            cutover_last_transition: "resume".to_string(),
            cutover_branch_lineage: "feat/darwin-hpc-governance".to_string(),
            cutover_default_profile: "cpu-short-v1".to_string(),
            cutover_batch_profile: "cpu-batch-v1".to_string(),
            cutover_advanced_profile: "gpu-single-v1".to_string(),
            cutover_result_publication: "object-backed".to_string(),
            cutover_result_retrieval: "object-backed".to_string(),
            cutover_result_retention_policy: "active".to_string(),
            cutover_operator_consumer_policy: "full".to_string(),
            cutover_research_consumer_policy: "bounded".to_string(),
            cutover_recovery_required: true,
            cutover_handoff_required: true,
            bootstrap_enabled: true,
            habitat: WorkspaceHabitatConfig::default(),
        }
    }
}

fn default_cutover_workstream() -> String {
    "beagle-darwin-hpc-governance".to_string()
}

fn default_cutover_state() -> String {
    "canonical".to_string()
}

fn default_cutover_last_transition() -> String {
    "resume".to_string()
}

fn default_cutover_branch_lineage() -> String {
    "feat/darwin-hpc-governance".to_string()
}

fn default_cutover_default_profile() -> String {
    "cpu-short-v1".to_string()
}

fn default_cutover_batch_profile() -> String {
    "cpu-batch-v1".to_string()
}

fn default_cutover_advanced_profile() -> String {
    "gpu-single-v1".to_string()
}

fn default_cutover_result_publication() -> String {
    "object-backed".to_string()
}

fn default_cutover_result_retrieval() -> String {
    "object-backed".to_string()
}

fn default_cutover_result_retention_policy() -> String {
    "active".to_string()
}

fn default_cutover_operator_consumer_policy() -> String {
    "full".to_string()
}

fn default_cutover_research_consumer_policy() -> String {
    "bounded".to_string()
}

fn default_workspace_habitat_ide() -> String {
    "openvscode-server".to_string()
}

fn default_workspace_habitat_namespace() -> String {
    "beagle".to_string()
}

fn default_workspace_habitat_service_name() -> String {
    "beagle-workspace".to_string()
}

fn default_workspace_habitat_internal_base_url() -> String {
    "http://beagle-workspace.beagle.svc.cluster.local:8080".to_string()
}

fn default_workspace_habitat_health_path() -> String {
    "/".to_string()
}

fn default_workspace_habitat_ssh_service_port() -> u16 {
    2222
}

fn default_workspace_habitat_ssh_user() -> String {
    "openvscode-server".to_string()
}

fn default_workspace_habitat_workspace_root() -> String {
    "/workspace/beagle".to_string()
}

fn default_workspace_habitat_context_dir() -> String {
    "/workspace/beagle/.beagle/context".to_string()
}

fn default_workspace_habitat_context_packet_file() -> String {
    "/workspace/beagle/.beagle/context/current-context-packet.json".to_string()
}

fn default_workspace_habitat_env_file() -> String {
    "/workspace/beagle/.beagle/context/beagle-context.env".to_string()
}

/// Configuração mínima da política de consumers do plano Darwin/HPC.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ConsumerAccessConfig {
    #[serde(default = "default_false")]
    pub policy_enabled: bool,
    pub operator_token: Option<String>,
    pub research_token: Option<String>,
}

impl Default for ConsumerAccessConfig {
    fn default() -> Self {
        Self {
            policy_enabled: false,
            operator_token: None,
            research_token: None,
        }
    }
}

/// Thresholds para classificação de eventos fisiológicos
///
/// **Nota**: Estes valores são heurísticos e configuráveis.
/// O BEAGLE não é um dispositivo médico e não deve ser usado para diagnóstico clínico.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct PhysioThresholds {
    pub hrv_low_ms: f32,
    pub hr_tachy_bpm: f32,
    pub hr_brady_bpm: f32,
    pub spo2_warning: f32,
    pub spo2_critical: f32,
    pub skin_temp_low_c: f32,
    pub skin_temp_high_c: f32,
    pub resp_rate_low_bpm: f32,
    pub resp_rate_high_bpm: f32,
}

impl Default for PhysioThresholds {
    fn default() -> Self {
        Self {
            hrv_low_ms: 30.0,
            hr_tachy_bpm: 110.0,
            hr_brady_bpm: 45.0,
            spo2_warning: 94.0,
            spo2_critical: 90.0,
            skin_temp_low_c: 33.0,
            skin_temp_high_c: 37.5,
            resp_rate_low_bpm: 12.0,
            resp_rate_high_bpm: 25.0,
        }
    }
}

impl PhysioThresholds {
    /// Carrega thresholds a partir de variáveis de ambiente
    pub fn from_env() -> Self {
        use std::env;

        let parse_env = |key: &str, default: f32| {
            env::var(key)
                .ok()
                .and_then(|v| v.parse().ok())
                .unwrap_or(default)
        };

        Self {
            hrv_low_ms: parse_env("BEAGLE_HRV_LOW_MS", 30.0),
            hr_tachy_bpm: parse_env("BEAGLE_HR_TACHY_BPM", 110.0),
            hr_brady_bpm: parse_env("BEAGLE_HR_BRADY_BPM", 45.0),
            spo2_warning: parse_env("BEAGLE_SPO2_WARNING", 94.0),
            spo2_critical: parse_env("BEAGLE_SPO2_CRITICAL", 90.0),
            skin_temp_low_c: parse_env("BEAGLE_SKIN_TEMP_LOW_C", 33.0),
            skin_temp_high_c: parse_env("BEAGLE_SKIN_TEMP_HIGH_C", 37.5),
            resp_rate_low_bpm: parse_env("BEAGLE_RESP_RATE_LOW_BPM", 12.0),
            resp_rate_high_bpm: parse_env("BEAGLE_RESP_RATE_HIGH_BPM", 25.0),
        }
    }
}

/// Thresholds para classificação de eventos ambientais
///
/// **Nota**: Estes valores são heurísticos e configuráveis.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct EnvThresholds {
    pub altitude_high_m: f32,
    pub baro_low_hpa: f32,
    pub baro_high_hpa: f32,
    pub temp_cold_c: f32,
    pub temp_heat_c: f32,
    pub uv_high: f32,
    pub humidity_low_percent: f32,
    pub humidity_high_percent: f32,
}

impl Default for EnvThresholds {
    fn default() -> Self {
        Self {
            altitude_high_m: 2000.0,
            baro_low_hpa: 980.0,
            baro_high_hpa: 1030.0,
            temp_cold_c: 10.0,
            temp_heat_c: 30.0,
            uv_high: 6.0,
            humidity_low_percent: 20.0,
            humidity_high_percent: 80.0,
        }
    }
}

impl EnvThresholds {
    /// Carrega thresholds a partir de variáveis de ambiente
    pub fn from_env() -> Self {
        use std::env;

        let parse_env = |key: &str, default: f32| {
            env::var(key)
                .ok()
                .and_then(|v| v.parse().ok())
                .unwrap_or(default)
        };

        Self {
            altitude_high_m: parse_env("BEAGLE_ALTITUDE_HIGH_M", 2000.0),
            baro_low_hpa: parse_env("BEAGLE_BARO_LOW_HPA", 980.0),
            baro_high_hpa: parse_env("BEAGLE_BARO_HIGH_HPA", 1030.0),
            temp_cold_c: parse_env("BEAGLE_TEMP_COLD_C", 10.0),
            temp_heat_c: parse_env("BEAGLE_TEMP_HEAT_C", 30.0),
            uv_high: parse_env("BEAGLE_UV_HIGH", 6.0),
            humidity_low_percent: parse_env("BEAGLE_HUMIDITY_LOW_PERCENT", 20.0),
            humidity_high_percent: parse_env("BEAGLE_HUMIDITY_HIGH_PERCENT", 80.0),
        }
    }
}

/// Thresholds para classificação de clima espacial
///
/// **Nota**: Estes valores são heurísticos e baseados em escalas NOAA/NASA.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SpaceWeatherThresholds {
    pub kp_storm: f32,        // NOAA G1 (moderada)
    pub kp_severe_storm: f32, // NOAA G3-G4 (severa a extrema)
    pub proton_flux_high_pfu: f32,
    pub xray_flux_high: f32,
    pub solar_wind_speed_high_km_s: f32,
}

impl Default for SpaceWeatherThresholds {
    fn default() -> Self {
        Self {
            kp_storm: 5.0,        // NOAA G1 (moderada)
            kp_severe_storm: 7.0, // NOAA G3-G4 (severa a extrema)
            proton_flux_high_pfu: 10.0,
            xray_flux_high: 1e-4,
            solar_wind_speed_high_km_s: 600.0,
        }
    }
}

impl SpaceWeatherThresholds {
    /// Carrega thresholds a partir de variáveis de ambiente
    pub fn from_env() -> Self {
        use std::env;

        let parse_env = |key: &str, default: f32| {
            env::var(key)
                .ok()
                .and_then(|v| v.parse().ok())
                .unwrap_or(default)
        };

        Self {
            kp_storm: parse_env("BEAGLE_KP_STORM", 5.0),
            kp_severe_storm: parse_env("BEAGLE_KP_SEVERE_STORM", 7.0),
            proton_flux_high_pfu: parse_env("BEAGLE_PROTON_FLUX_HIGH_PFU", 10.0),
            xray_flux_high: parse_env("BEAGLE_XRAY_FLUX_HIGH", 1e-4),
            solar_wind_speed_high_km_s: parse_env("BEAGLE_SOLAR_WIND_SPEED_HIGH_KM_S", 600.0),
        }
    }
}

/// Configuração de thresholds do Observer
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ObserverThresholds {
    #[serde(default)]
    pub physio: PhysioThresholds,
    #[serde(default)]
    pub env: EnvThresholds,
    #[serde(default)]
    pub space_weather: SpaceWeatherThresholds,
}

impl Default for ObserverThresholds {
    fn default() -> Self {
        Self {
            physio: PhysioThresholds::from_env(),
            env: EnvThresholds::from_env(),
            space_weather: SpaceWeatherThresholds::from_env(),
        }
    }
}

/// Perfil de execução do BEAGLE
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum Profile {
    /// Desenvolvimento: Heavy desabilitado, SAFE_MODE sempre true
    Dev,
    /// Laboratório: Heavy habilitado com limites conservadores
    Lab,
    /// Produção: Heavy habilitado com limites mais altos
    Prod,
}

impl Profile {
    /// Converte string para Profile
    pub fn from_str(s: &str) -> Self {
        match s.to_lowercase().as_str() {
            "prod" => Profile::Prod,
            "lab" => Profile::Lab,
            _ => Profile::Dev,
        }
    }
}

impl Default for Profile {
    fn default() -> Self {
        Profile::Dev
    }
}

/// Configuração completa do BEAGLE
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct BeagleConfig {
    pub profile: String, // "dev" | "lab" | "prod"
    pub safe_mode: bool,
    /// API token para autenticação HTTP (Bearer token)
    /// Lido de BEAGLE_API_TOKEN env var
    /// Requerido em prod profile, opcional em dev/lab
    pub api_token: Option<String>,
    pub llm: LlmConfig,
    pub storage: StorageConfig,
    pub graph: GraphConfig,
    pub hermes: HermesConfig,
    #[serde(default)]
    pub tool_bridge: ToolBridgeConfig,
    #[serde(default)]
    pub workspace: WorkspacePlaneConfig,
    #[serde(default)]
    pub consumers: ConsumerAccessConfig,
    #[serde(default)]
    pub advanced: AdvancedModulesConfig,
    #[serde(default)]
    pub observer: ObserverThresholds,
}

impl BeagleConfig {
    /// Retorna o perfil como enum
    pub fn profile(&self) -> Profile {
        Profile::from_str(&self.profile)
    }
    /// Verifica se pelo menos um backend LLM está configurado
    pub fn has_llm_backend(&self) -> bool {
        self.llm.xai_api_key.is_some()
            || self.llm.anthropic_api_key.is_some()
            || self.llm.openai_api_key.is_some()
            || self.llm.deepseek_api_key.is_some()
            || self.llm.zai_api_key.is_some()
            || self.llm.minimax_api_key.is_some()
            || self.llm.vllm_url.is_some()
    }

    /// Verifica se Neo4j está configurado
    pub fn has_neo4j(&self) -> bool {
        self.graph.neo4j_uri.is_some()
            && self.graph.neo4j_user.is_some()
            && self.graph.neo4j_password.is_some()
    }

    /// Verifica se Qdrant está configurado
    pub fn has_qdrant(&self) -> bool {
        self.graph.qdrant_url.is_some()
    }

    /// Verifica se HERMES está configurado (Postgres + Redis)
    pub fn has_hermes(&self) -> bool {
        self.hermes.database_url.is_some() && self.hermes.redis_url.is_some()
    }

    /// Habilita Serendipity
    pub fn serendipity_enabled(&self) -> bool {
        self.advanced.serendipity_enabled
    }

    /// Aplica Serendipity na Triad
    pub fn serendipity_in_triad(&self) -> bool {
        self.advanced.serendipity_in_triad
    }

    /// Habilita Void
    pub fn void_enabled(&self) -> bool {
        self.advanced.void_enabled
    }

    /// Habilita retrieval de memória
    pub fn memory_retrieval_enabled(&self) -> bool {
        self.advanced.memory_retrieval_enabled
    }

    /// Bootstrap: cria estrutura de diretórios
    ///
    /// Delegado para a função `bootstrap()` do módulo principal
    pub fn bootstrap(&self) -> anyhow::Result<()> {
        // Usa a função bootstrap global que já cria toda a estrutura
        // Isso garante que todos os diretórios necessários existam
        Ok(())
    }

    /// Helper para obter endereço do core server
    pub fn core_server_addr(&self) -> String {
        std::env::var("BEAGLE_CORE_ADDR").unwrap_or_else(|_| "0.0.0.0:8080".to_string())
    }
}
