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
    pub vllm_url: Option<String>,
    /// Modelo Grok padrão (default: "grok-3")
    #[serde(default = "default_grok_model")]
    pub grok_model: String,
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

impl Default for LlmConfig {
    fn default() -> Self {
        Self {
            xai_api_key: None,
            anthropic_api_key: None,
            openai_api_key: None,
            vllm_url: None,
            grok_model: default_grok_model(),
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
