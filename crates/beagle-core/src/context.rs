//! BeagleContext - Contexto unificado com injeção de dependências
//!
//! Integra:
//! - Router com Grok 3 como Tier 1
//! - Darwin (GraphRAG)
//! - HERMES (síntese de papers)
//! - Observer (surveillance total)

use crate::implementations::*;
use crate::stats::LlmStatsRegistry;
use crate::traits::{GraphStore, LlmClient, VectorStore};
use anyhow::Result;
use beagle_config::BeagleConfig;
use beagle_llm::TieredRouter;
use std::sync::Arc;
use tracing::{info, warn};

/// Contexto unificado do BEAGLE com todas as dependências injetadas
pub struct BeagleContext {
    pub cfg: BeagleConfig,
    pub router: TieredRouter,
    pub llm: Arc<dyn LlmClient>,
    pub vector: Arc<dyn VectorStore>,
    pub graph: Arc<dyn GraphStore>,
    pub llm_stats: LlmStatsRegistry,
    // Memory engine (opcional, só disponível com feature "memory")
    #[cfg(feature = "memory")]
    pub memory: Option<Arc<beagle_memory::MemoryEngine>>,
    // Darwin, HERMES e Observer são inicializados no beagle-monorepo
    // para evitar dependências circulares. Eles podem ser passados
    // como parâmetros quando necessário ou armazenados externamente.
    // DarwinCore agora usa BeagleContext via with_context(), não precisa
    // estar dentro do contexto.
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
            cfg.profile, router.cfg.enable_heavy
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

        // Escolhe Vector Store (com degraded mode robusto)
        let vector: Arc<dyn VectorStore> = if let Some(qdrant_url) = &cfg.graph.qdrant_url {
            match QdrantVectorStore::from_config(&cfg) {
                Ok(store) => {
                    info!("✓ Qdrant vector store inicializado: {}", qdrant_url);
                    Arc::new(store)
                }
                Err(e) => {
                    warn!("⚠ Falha ao conectar Qdrant ({}), usando NoOpVectorStore", e);
                    Arc::new(NoOpVectorStore)
                }
            }
        } else {
            warn!("⚠ Qdrant não configurado, usando NoOpVectorStore (degraded mode)");
            Arc::new(NoOpVectorStore)
        };

        // Escolhe Graph Store (com degraded mode robusto)
        let graph: Arc<dyn GraphStore> = if cfg.has_neo4j() {
            #[cfg(feature = "neo4j")]
            {
                match Neo4jGraphStore::from_config(&cfg).await {
                    Ok(store) => {
                        info!("✓ Neo4j graph store inicializado");
                        Arc::new(store)
                    }
                    Err(e) => {
                        warn!("⚠ Falha ao conectar Neo4j ({}), usando NoOpGraphStore", e);
                        Arc::new(NoOpGraphStore)
                    }
                }
            }
            #[cfg(not(feature = "neo4j"))]
            {
                warn!("⚠ Neo4j feature não habilitada, usando NoOpGraphStore (degraded mode)");
                Arc::new(NoOpGraphStore)
            }
        } else {
            warn!("⚠ Neo4j não configurado, usando NoOpGraphStore (degraded mode)");
            Arc::new(NoOpGraphStore)
        };

        // Initialize MemoryEngine if hypergraph storage is available
        #[cfg(feature = "memory")]
        let memory = {
            use beagle_hypergraph::CachedPostgresStorage;
            use beagle_memory::{ContextBridge, MemoryEngine};

            if let (Some(pg_url), Some(redis_url)) =
                (&cfg.hermes.database_url, &cfg.hermes.redis_url)
            {
                match CachedPostgresStorage::new(pg_url, redis_url).await {
                    Ok(storage) => {
                        let bridge = Arc::new(ContextBridge::new(Arc::new(storage)));
                        info!("MemoryEngine initialized with Postgres+Redis");
                        Some(Arc::new(MemoryEngine::new(bridge)))
                    }
                    Err(e) => {
                        warn!("Failed to initialize MemoryEngine: {}", e);
                        None
                    }
                }
            } else {
                warn!("MemoryEngine requires DATABASE_URL and REDIS_URL");
                None
            }
        };
        #[cfg(not(feature = "memory"))]
        let _memory = None::<Arc<()>>; // Placeholder quando feature não habilitada

        // Darwin é inicializado no beagle-monorepo com with_context()
        // para evitar dependência circular

        Ok(Self {
            cfg,
            router,
            llm,
            vector,
            graph,
            llm_stats: LlmStatsRegistry::new(),
            #[cfg(feature = "memory")]
            memory,
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
            #[cfg(feature = "memory")]
            memory: None,
        }
    }

    /// Cria contexto com mocks usando config padrão (para testes simples)
    pub fn new_with_mock() -> anyhow::Result<Self> {
        let cfg = beagle_config::load();
        Ok(Self::new_with_mocks(cfg))
    }

    /// Helper para ingerir sessão de chat na memória
    #[cfg(feature = "memory")]
    pub async fn memory_ingest_session(
        &self,
        session: beagle_memory::ChatSession,
    ) -> anyhow::Result<beagle_memory::IngestStats> {
        if let Some(ref memory) = self.memory {
            memory.ingest_chat(session).await
        } else {
            anyhow::bail!("MemoryEngine not initialized")
        }
    }

    /// Helper para consultar memória
    #[cfg(feature = "memory")]
    pub async fn memory_query(
        &self,
        q: beagle_memory::MemoryQuery,
    ) -> anyhow::Result<beagle_memory::MemoryResult> {
        if let Some(ref memory) = self.memory {
            memory.query(q).await
        } else {
            anyhow::bail!("MemoryEngine not initialized")
        }
    }

    /// GraphRAG: Retrieve knowledge snippets from graph store
    ///
    /// Executes a Cypher query and converts results to knowledge snippets.
    /// This is the foundation for GraphRAG - combining graph knowledge with LLM generation.
    ///
    /// # Example
    /// ```ignore
    /// // Find related concepts for a query
    /// let snippets = ctx.graph_retrieve(
    ///     "MATCH (c:Concept)-[:RELATED_TO]->(related:Concept)
    ///      WHERE c.name CONTAINS $term
    ///      RETURN related.name as title, related.description as text
    ///      LIMIT 10",
    ///     serde_json::json!({"term": "quantum mechanics"})
    /// ).await?;
    /// ```
    pub async fn graph_retrieve(
        &self,
        cypher: &str,
        params: serde_json::Value,
    ) -> Result<Vec<KnowledgeSnippet>> {
        let result = self.graph.cypher_query(cypher, params).await?;

        let mut snippets = Vec::new();

        // Extract snippets from Neo4j result format
        if let Some(results) = result.get("results").and_then(|r| r.as_array()) {
            for result_set in results {
                if let Some(data) = result_set.get("data").and_then(|d| d.as_array()) {
                    for row in data {
                        let snippet = crate::implementations::neo4j_result_to_snippet(row, None);
                        snippets.push(snippet);
                    }
                }
            }
        }

        Ok(snippets)
    }

    /// GraphRAG: Hybrid retrieval combining vector and graph search
    ///
    /// First performs semantic vector search, then enriches results with graph context.
    /// This is the complete GraphRAG pattern: semantic search + graph structure.
    ///
    /// # Example
    /// ```ignore
    /// let snippets = ctx.graph_hybrid_retrieve(
    ///     "explain quantum entanglement",
    ///     5, // top_k vector results
    ///     2  // graph depth for each result
    /// ).await?;
    /// ```
    pub async fn graph_hybrid_retrieve(
        &self,
        query: &str,
        top_k: usize,
        graph_depth: usize,
    ) -> Result<Vec<KnowledgeSnippet>> {
        use serde_json::json;

        let mut all_snippets = Vec::new();

        // 1. Semantic vector search
        let vector_hits = self.vector.query(query, top_k).await?;

        // Convert vector hits to snippets
        for hit in &vector_hits {
            all_snippets.push(crate::implementations::vector_hit_to_snippet(hit));
        }

        // 2. Graph expansion - for each vector result, find connected knowledge
        for hit in &vector_hits {
            // Extract entity ID from metadata if available
            if let Some(entity_id) = hit.metadata.get("entity_id").and_then(|v| v.as_str()) {
                // Query graph for neighborhood (depth-limited traversal)
                let cypher = format!(
                    "MATCH path = (n {{id: $id}})-[*1..{}]-(related) \
                     RETURN related.name as title, related.description as text, \
                     length(path) as distance \
                     ORDER BY distance \
                     LIMIT 20",
                    graph_depth
                );

                if let Ok(graph_snippets) =
                    self.graph_retrieve(&cypher, json!({"id": entity_id})).await
                {
                    all_snippets.extend(graph_snippets);
                }
            }
        }

        Ok(all_snippets)
    }

    /// GraphRAG: Create knowledge graph nodes from research results
    ///
    /// This allows agents (like ResearcherAgent) to store discoveries in the graph
    /// for future retrieval and reasoning.
    ///
    /// # Example
    /// ```ignore
    /// ctx.graph_store_knowledge(
    ///     vec!["Concept".to_string(), "Physics".to_string()],
    ///     serde_json::json!({
    ///         "name": "Quantum Entanglement",
    ///         "description": "A physical phenomenon...",
    ///         "source": "paper_id_123"
    ///     })
    /// ).await?;
    /// ```
    pub async fn graph_store_knowledge(
        &self,
        labels: Vec<String>,
        properties: serde_json::Value,
    ) -> Result<String> {
        use serde_json::json;

        // Build CREATE query with parameters
        let labels_str = labels.join(":");
        let mut prop_names = Vec::new();
        let mut params = json!({});

        if let Some(obj) = properties.as_object() {
            for (key, value) in obj {
                prop_names.push(format!("{}: ${}", key, key));
                params[key] = value.clone();
            }
        }

        let props_str = if prop_names.is_empty() {
            String::new()
        } else {
            format!(" {{{}}}", prop_names.join(", "))
        };

        let cypher = format!(
            "CREATE (n:{}{}) RETURN elementId(n) as id",
            labels_str, props_str
        );

        let result = self.graph.cypher_query(&cypher, params).await?;

        // Extract node ID from result
        if let Some(results) = result.get("results").and_then(|r| r.as_array()) {
            for result_set in results {
                if let Some(data) = result_set.get("data").and_then(|d| d.as_array()) {
                    if let Some(row) = data.first() {
                        if let Some(id) = row.get("id").and_then(|v| v.as_str()) {
                            return Ok(id.to_string());
                        }
                    }
                }
            }
        }

        warn!("Failed to extract node ID from graph result");
        Ok("unknown".to_string())
    }

    /// GraphRAG: Create relationships between knowledge entities
    ///
    /// Links concepts together to build a rich knowledge graph.
    ///
    /// # Example
    /// ```ignore
    /// ctx.graph_link_knowledge(
    ///     "node_123",
    ///     "node_456",
    ///     "RELATES_TO",
    ///     serde_json::json!({"strength": 0.9})
    /// ).await?;
    /// ```
    pub async fn graph_link_knowledge(
        &self,
        from_id: &str,
        to_id: &str,
        rel_type: &str,
        properties: serde_json::Value,
    ) -> Result<String> {
        use serde_json::json;

        let mut prop_names = Vec::new();
        let mut params = json!({
            "from_id": from_id,
            "to_id": to_id
        });

        if let Some(obj) = properties.as_object() {
            for (key, value) in obj {
                prop_names.push(format!("{}: ${}", key, key));
                params[key] = value.clone();
            }
        }

        let props_str = if prop_names.is_empty() {
            String::new()
        } else {
            format!(" {{{}}}", prop_names.join(", "))
        };

        let cypher = format!(
            "MATCH (a), (b) WHERE elementId(a) = $from_id AND elementId(b) = $to_id \
             CREATE (a)-[r:{}{}]->(b) RETURN elementId(r) as id",
            rel_type, props_str
        );

        let result = self.graph.cypher_query(&cypher, params).await?;

        // Extract relationship ID from result
        if let Some(results) = result.get("results").and_then(|r| r.as_array()) {
            for result_set in results {
                if let Some(data) = result_set.get("data").and_then(|d| d.as_array()) {
                    if let Some(row) = data.first() {
                        if let Some(id) = row.get("id").and_then(|v| v.as_str()) {
                            return Ok(id.to_string());
                        }
                    }
                }
            }
        }

        warn!("Failed to extract relationship ID from graph result");
        Ok("unknown".to_string())
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
    async fn cypher_query(
        &self,
        query: &str,
        params: serde_json::Value,
    ) -> Result<serde_json::Value> {
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
