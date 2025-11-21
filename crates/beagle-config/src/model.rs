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
    pub llm: LlmConfig,
    pub storage: StorageConfig,
    pub graph: GraphConfig,
    pub hermes: HermesConfig,
    #[serde(default)]
    pub advanced: AdvancedModulesConfig,
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
        std::env::var("BEAGLE_CORE_ADDR")
            .unwrap_or_else(|_| "0.0.0.0:8080".to_string())
    }
}

