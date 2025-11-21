//! BeagleContext - Contexto unificado com injeção de dependências
//!
//! Integra:
//! - Router com Grok 3 como Tier 1
//! - Darwin (GraphRAG)
//! - HERMES (síntese de papers)
//! - Observer (surveillance total)

use crate::traits::{GraphStore, LlmClient, VectorStore};
use crate::implementations::*;
use crate::stats::LlmStatsRegistry;
use beagle_config::BeagleConfig;
use beagle_llm::TieredRouter;
use std::sync::Arc;
use anyhow::Result;
use tracing::{info, warn};

/// Contexto unificado do BEAGLE com todas as dependências injetadas
pub struct BeagleContext {
    pub cfg: BeagleConfig,
    pub router: TieredRouter,
    pub llm: Arc<dyn LlmClient>,
    pub vector: Arc<dyn VectorStore>,
    pub graph: Arc<dyn GraphStore>,
    pub llm_stats: LlmStatsRegistry,
    // Darwin, HERMES e Observer serão adicionados quando disponíveis
    // pub darwin: Arc<beagle_darwin::DarwinCore>,
    // pub hermes: Arc<beagle_hermes::HermesEngine>,
    // pub observer: Arc<beagle_observer::UniversalObserver>,
}

impl BeagleContext {
    /// Cria novo contexto a partir de configuração
    ///
    /// Escolhe implementações baseadas na configuração:
    /// - LLM: Grok (se XAI_API_KEY), vLLM (se VLLM_URL), ou Mock
    /// - Vector: Qdrant (se QDRANT_URL) ou Mock
    /// - Graph: Neo4j (se NEO4J_URI) ou Mock
    pub async fn new(cfg: BeagleConfig) -> Result<Self> {
        // Router com configuração baseada em perfil
        let router = TieredRouter::from_config(&cfg)?;
        info!(
            "Router inicializado | profile={} | heavy_enabled={}",
            cfg.profile,
            router.cfg.enable_heavy
        );

        // Escolhe LLM client (compatibilidade com código legado)
        let llm: Arc<dyn LlmClient> = if let Some(xai_key) = &cfg.llm.xai_api_key {
            info!("Usando Grok LLM client");
            Arc::new(GrokLlmClient::new(xai_key.clone())?)
        } else if let Some(vllm_url) = &cfg.llm.vllm_url {
            info!("Usando vLLM client: {}", vllm_url);
            Arc::new(VllmLlmClient::new(vllm_url.clone(), None))
        } else {
            warn!("Nenhum LLM configurado, usando MockLlmClient");
            MockLlmClient::new()
        };

        // Escolhe Vector Store
        let vector: Arc<dyn VectorStore> = if let Some(qdrant_url) = &cfg.graph.qdrant_url {
            info!("Usando Qdrant vector store: {}", qdrant_url);
            Arc::new(QdrantVectorStore::from_config(&cfg)?)
        } else {
            warn!("Qdrant não configurado, usando MockVectorStore");
            Arc::new(MockVectorStore)
        };

        // Escolhe Graph Store
        let graph: Arc<dyn GraphStore> = if cfg.has_neo4j() {
            info!("Usando Neo4j graph store");
            #[cfg(feature = "neo4j")]
            {
                Arc::new(Neo4jGraphStore::from_config(&cfg).await?)
            }
            #[cfg(not(feature = "neo4j"))]
            {
                warn!("Neo4j feature não habilitada, usando MockGraphStore");
                Arc::new(MockGraphStore)
            }
        } else {
            warn!("Neo4j não configurado, usando MockGraphStore");
            Arc::new(MockGraphStore)
        };

        Ok(Self {
            cfg,
            router,
            llm,
            vector,
            graph,
            llm_stats: LlmStatsRegistry::new(),
        })
    }

    /// Cria contexto com mocks explícitos (para testes)
    pub fn new_with_mocks(cfg: BeagleConfig) -> Self {
        Self {
            cfg: cfg.clone(),
            router: TieredRouter::new_with_mocks().unwrap_or_else(|_| TieredRouter::default()),
            llm: MockLlmClient::new(),
            vector: Arc::new(MockVectorStore),
            graph: Arc::new(MockGraphStore),
            llm_stats: LlmStatsRegistry::new(),
        }
    }
    
    /// Cria contexto com mocks usando config padrão (para testes simples)
    pub fn new_with_mock() -> anyhow::Result<Self> {
        let cfg = beagle_config::load();
        Ok(Self::new_with_mocks(cfg))
    }
}

// ============================================================================
// MOCKS (implementações mínimas para testes)
// ============================================================================

use crate::traits::*;
use async_trait::async_trait;
use serde_json::json;

// Mock LLM client para testes (implementa trait de beagle-core)
pub struct MockLlmClient;

#[async_trait]
impl LlmClient for MockLlmClient {
    async fn complete(&self, prompt: &str) -> Result<String> {
        Ok(format!("MOCK_ANSWER for: {}", prompt))
    }

    async fn chat(&self, messages: &[ChatMessage]) -> Result<String> {
        let content: String = messages
            .iter()
            .map(|m| m.content.clone())
            .collect::<Vec<_>>()
            .join("\n");
        Ok(format!("MOCK_CHAT response for: {}", content))
    }
}

impl MockLlmClient {
    pub fn new() -> Arc<Self> {
        Arc::new(Self)
    }
}

/// Mock Vector Store para testes
pub struct MockVectorStore;

#[async_trait]
impl VectorStore for MockVectorStore {
    async fn query(&self, text: &str, top_k: usize) -> Result<Vec<VectorHit>> {
        Ok((0..top_k.min(3))
            .map(|i| VectorHit {
                id: format!("mock_vector_{}", i),
                score: 0.9 - (i as f32 * 0.1),
                metadata: json!({
                    "text": format!("Mock result {} for: {}", i, text),
                }),
            })
            .collect())
    }
}

/// Mock Graph Store para testes
pub struct MockGraphStore;

#[async_trait]
impl GraphStore for MockGraphStore {
    async fn cypher_query(&self, query: &str, params: serde_json::Value) -> Result<serde_json::Value> {
        Ok(json!({
            "results": [{
                "data": [{
                    "row": [{
                        "id": "mock_node_1",
                        "label": "Concept",
                        "properties": {
                            "name": "Mock Concept",
                            "query": query,
                            "params": params
                        }
                    }]
                }]
            }]
        }))
    }
}

