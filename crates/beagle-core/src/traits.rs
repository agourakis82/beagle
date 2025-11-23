//! Traits centrais do BEAGLE para abstração de serviços externos

use anyhow::Result;
use async_trait::async_trait;
use serde_json::Value;

/// Mensagem de chat para LLMs
#[derive(Debug, Clone)]
pub struct ChatMessage {
    pub role: String,
    pub content: String,
}

impl ChatMessage {
    pub fn user(content: impl Into<String>) -> Self {
        Self {
            role: "user".to_string(),
            content: content.into(),
        }
    }

    pub fn assistant(content: impl Into<String>) -> Self {
        Self {
            role: "assistant".to_string(),
            content: content.into(),
        }
    }

    pub fn system(content: impl Into<String>) -> Self {
        Self {
            role: "system".to_string(),
            content: content.into(),
        }
    }
}

/// Trait para clientes LLM (Grok, Claude, OpenAI, vLLM, etc.)
#[async_trait]
pub trait LlmClient: Send + Sync {
    /// Gera completão de texto a partir de um prompt
    async fn complete(&self, prompt: &str) -> Result<String>;

    /// Gera resposta de chat a partir de mensagens
    async fn chat(&self, messages: &[ChatMessage]) -> Result<String>;
}

/// Resultado de busca em vector store
#[derive(Debug, Clone)]
pub struct VectorHit {
    pub id: String,
    pub score: f32,
    pub metadata: Value,
}

/// Knowledge snippet unificado de diferentes fontes (Qdrant, Neo4j, Memory)
///
/// Usado por DarwinCore para agregar contexto de múltiplas fontes
#[derive(Debug, Clone)]
pub struct KnowledgeSnippet {
    /// Fonte do snippet: "qdrant", "neo4j", "memory", etc.
    pub source: String,
    /// Título opcional do documento/nó
    pub title: Option<String>,
    /// Texto do snippet
    pub text: String,
    /// Score de relevância (0.0-1.0), se disponível
    pub score: Option<f32>,
    /// Metadata adicional (JSON)
    pub meta: Value,
}

/// Trait para vector stores (Qdrant, Pinecone, etc.)
#[async_trait]
pub trait VectorStore: Send + Sync {
    /// Busca vetores similares a um texto
    ///
    /// # Arguments
    /// * `text` - Texto para buscar
    /// * `top_k` - Número máximo de resultados
    ///
    /// # Returns
    /// Lista de hits ordenados por score (maior primeiro)
    async fn query(&self, text: &str, top_k: usize) -> Result<Vec<VectorHit>>;
}

/// Trait para graph stores (Neo4j, etc.)
#[async_trait]
pub trait GraphStore: Send + Sync {
    /// Executa query Cypher no graph
    ///
    /// # Arguments
    /// * `query` - Query Cypher
    /// * `params` - Parâmetros da query (JSON)
    ///
    /// # Returns
    /// Resultado da query como JSON
    async fn cypher_query(&self, query: &str, params: Value) -> Result<Value>;
}
