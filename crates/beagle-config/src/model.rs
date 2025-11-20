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
}

impl Default for LlmConfig {
    fn default() -> Self {
        Self {
            xai_api_key: None,
            anthropic_api_key: None,
            openai_api_key: None,
            vllm_url: None,
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

/// Configuração completa do BEAGLE
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct BeagleConfig {
    pub profile: String, // "dev" | "lab" | "prod"
    pub safe_mode: bool,
    pub llm: LlmConfig,
    pub storage: StorageConfig,
    pub graph: GraphConfig,
    pub hermes: HermesConfig,
}

impl BeagleConfig {
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
}

