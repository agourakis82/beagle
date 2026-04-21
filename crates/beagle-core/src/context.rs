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
    pub llm_stats: Arc<LlmStatsRegistry>,
    // Memory engine (opcional, só disponível com feature "memory")
    #[cfg(feature = "memory")]
    pub memory: Option<Arc<beagle_memory::MemoryEngine>>,
    // World model (opcional, só disponível com feature "worldmodel")
    #[cfg(feature = "worldmodel")]
    pub worldmodel: Option<Arc<beagle_worldmodel::WorldModel>>,
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
            use beagle_memory::{ContextBridge, MemoryEngine, MemoryEngineConfig};

            if let (Some(pg_url), Some(redis_url)) =
                (&cfg.hermes.database_url, &cfg.hermes.redis_url)
            {
                match CachedPostgresStorage::new(pg_url, redis_url).await {
                    Ok(storage) => {
                        let bridge = Arc::new(ContextBridge::new(Arc::new(storage)));
                        let memory_config = MemoryEngineConfig::from_runtime(
                            cfg.graph.qdrant_url.clone(),
                            std::env::var("BEAGLE_MEMORY_EMBEDDING_URL")
                                .or_else(|_| std::env::var("EMBEDDING_URL"))
                                .ok(),
                            Some(cfg.storage.data_dir_path()),
                        );
                        info!("MemoryEngine initialized with Postgres+Redis");
                        Some(Arc::new(MemoryEngine::new(Some(bridge), memory_config)))
                    }
                    Err(e) => {
                        warn!(
                            "Failed to initialize MemoryEngine bridge: {}; continuing with local memory mode",
                            e
                        );
                        let memory_config = MemoryEngineConfig::from_runtime(
                            cfg.graph.qdrant_url.clone(),
                            std::env::var("BEAGLE_MEMORY_EMBEDDING_URL")
                                .or_else(|_| std::env::var("EMBEDDING_URL"))
                                .ok(),
                            Some(cfg.storage.data_dir_path()),
                        );
                        Some(Arc::new(MemoryEngine::new(None, memory_config)))
                    }
                }
            } else {
                warn!("MemoryEngine bridge requires DATABASE_URL and REDIS_URL; using local memory mode");
                let memory_config = MemoryEngineConfig::from_runtime(
                    cfg.graph.qdrant_url.clone(),
                    std::env::var("BEAGLE_MEMORY_EMBEDDING_URL")
                        .or_else(|_| std::env::var("EMBEDDING_URL"))
                        .ok(),
                    Some(cfg.storage.data_dir_path()),
                );
                Some(Arc::new(MemoryEngine::new(None, memory_config)))
            }
        };
        #[cfg(not(feature = "memory"))]
        let _memory = None::<Arc<()>>; // Placeholder quando feature não habilitada

        // Initialize WorldModel if feature enabled
        #[cfg(feature = "worldmodel")]
        let worldmodel = {
            match beagle_worldmodel::WorldModel::new().await {
                Ok(model) => {
                    info!("WorldModel initialized successfully");
                    Some(Arc::new(model))
                }
                Err(e) => {
                    warn!("Failed to initialize WorldModel: {}", e);
                    None
                }
            }
        };
        #[cfg(not(feature = "worldmodel"))]
        let _worldmodel = None::<Arc<()>>; // Placeholder quando feature não habilitada

        // Darwin é inicializado no beagle-monorepo com with_context()
        // para evitar dependência circular

        #[cfg(feature = "memory")]
        {
            if let Some(ref engine) = &memory {
                let health = engine.qdrant_health().await;
                info!(
                    target: "beagle_memory",
                    qdrant_status = %health.status,
                    qdrant_configured = health.configured,
                    qdrant_collection = %health.collection,
                    qdrant_http_status = ?health.http_status,
                    "MemoryEngine Qdrant health snapshot at startup"
                );
            }
        }

        Ok(Self {
            cfg,
            router,
            llm,
            vector,
            graph,
            llm_stats: Arc::new(LlmStatsRegistry::new()),
            #[cfg(feature = "memory")]
            memory,
            #[cfg(feature = "worldmodel")]
            worldmodel,
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
            llm_stats: Arc::new(LlmStatsRegistry::new()),
            #[cfg(feature = "memory")]
            memory: None,
            #[cfg(feature = "worldmodel")]
            worldmodel: None,
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

    /// Estado de ligação ao Qdrant para o índice vectorial da memória (sem payloads).
    #[cfg(feature = "memory")]
    pub async fn memory_qdrant_health(&self) -> beagle_memory::MemoryQdrantHealth {
        match &self.memory {
            Some(engine) => engine.qdrant_health().await,
            None => beagle_memory::MemoryQdrantHealth {
                configured: false,
                status: "memory_engine_disabled".to_string(),
                http_status: None,
                collection: String::new(),
                base_url: None,
                error: None,
            },
        }
    }

    /// Helper para descrever a coleção canônica de retrieval híbrida
    #[cfg(feature = "memory")]
    pub fn memory_retrieval_collection(&self) -> anyhow::Result<beagle_memory::RetrievalCollection> {
        if let Some(ref memory) = self.memory {
            Ok(memory.retrieval_collection())
        } else {
            anyhow::bail!("MemoryEngine not initialized")
        }
    }

    /// Helper para retrieval híbrida com dense+sparse e filtros explícitos
    #[cfg(feature = "memory")]
    pub async fn memory_hybrid_retrieve(
        &self,
        q: beagle_memory::RetrievalQuery,
    ) -> anyhow::Result<beagle_memory::RetrievalResult> {
        if let Some(ref memory) = self.memory {
            memory.hybrid_retrieve(q).await
        } else {
            anyhow::bail!("MemoryEngine not initialized")
        }
    }

    #[cfg(feature = "memory")]
    pub async fn memory_code_retrieve(
        &self,
        q: beagle_memory::CodeRetrievalQuery,
    ) -> anyhow::Result<beagle_memory::CodeRetrievalResult> {
        if let Some(ref memory) = self.memory {
            memory.code_retrieve(q).await
        } else {
            anyhow::bail!("MemoryEngine not initialized")
        }
    }

    #[cfg(feature = "memory")]
    pub async fn memory_sovereign_retrieve(
        &self,
        q: beagle_memory::SovereignRetrievalQuery,
    ) -> anyhow::Result<beagle_memory::SovereignRetrievalResult> {
        if let Some(ref memory) = self.memory {
            memory.sovereign_retrieve(q).await
        } else {
            anyhow::bail!("MemoryEngine not initialized")
        }
    }

    #[cfg(feature = "memory")]
    pub fn memory_classify_retrieval_query(
        &self,
        q: &beagle_memory::RoutedRetrievalQuery,
    ) -> anyhow::Result<beagle_memory::RetrievalQueryType> {
        if let Some(ref memory) = self.memory {
            Ok(memory.classify_retrieval_query(q))
        } else {
            anyhow::bail!("MemoryEngine not initialized")
        }
    }

    #[cfg(feature = "memory")]
    pub fn memory_retrieval_routing_decision(
        &self,
        q: &beagle_memory::RoutedRetrievalQuery,
    ) -> anyhow::Result<beagle_memory::RetrievalRoutingDecision> {
        if let Some(ref memory) = self.memory {
            Ok(memory.retrieval_routing_decision(q))
        } else {
            anyhow::bail!("MemoryEngine not initialized")
        }
    }

    #[cfg(feature = "memory")]
    pub async fn memory_routed_retrieve(
        &self,
        q: beagle_memory::RoutedRetrievalQuery,
    ) -> anyhow::Result<beagle_memory::RoutedRetrievalResult> {
        if let Some(ref memory) = self.memory {
            memory.routed_retrieve(q).await
        } else {
            anyhow::bail!("MemoryEngine not initialized")
        }
    }

    #[cfg(feature = "memory")]
    pub async fn memory_reranked_routed_retrieve(
        &self,
        q: beagle_memory::RoutedRetrievalQuery,
    ) -> anyhow::Result<beagle_memory::RerankedResult> {
        if let Some(ref memory) = self.memory {
            memory.reranked_routed_retrieve(q).await
        } else {
            anyhow::bail!("MemoryEngine not initialized")
        }
    }

    #[cfg(feature = "memory")]
    pub fn memory_embedding_backend_matrix(
        &self,
    ) -> anyhow::Result<beagle_memory::EmbeddingBackendMatrix> {
        if let Some(ref memory) = self.memory {
            Ok(memory.embedding_backend_matrix())
        } else {
            anyhow::bail!("MemoryEngine not initialized")
        }
    }

    #[cfg(feature = "memory")]
    pub fn memory_sovereign_retrieval_backend_profile(
        &self,
    ) -> anyhow::Result<beagle_memory::SovereignRetrievalBackendProfile> {
        if let Some(ref memory) = self.memory {
            Ok(memory.sovereign_retrieval_backend_profile())
        } else {
            anyhow::bail!("MemoryEngine not initialized")
        }
    }

    #[cfg(feature = "memory")]
    pub fn memory_embedding_backend_contract(
        &self,
    ) -> anyhow::Result<beagle_memory::EmbeddingBackendContract> {
        if let Some(ref memory) = self.memory {
            Ok(memory.embedding_backend_contract())
        } else {
            anyhow::bail!("MemoryEngine not initialized")
        }
    }

    #[cfg(feature = "memory")]
    pub fn memory_reranking_profile(&self) -> anyhow::Result<beagle_memory::RerankingProfile> {
        if let Some(ref memory) = self.memory {
            Ok(memory.reranking_profile())
        } else {
            anyhow::bail!("MemoryEngine not initialized")
        }
    }

    #[cfg(feature = "memory")]
    pub async fn memory_retrieval_benchmark(
        &self,
        request: beagle_memory::RetrievalBenchmarkRequest,
    ) -> anyhow::Result<beagle_memory::RetrievalBenchmarkReport> {
        if let Some(ref memory) = self.memory {
            memory.benchmark_retrieval(request).await
        } else {
            anyhow::bail!("MemoryEngine not initialized")
        }
    }

    #[cfg(feature = "memory")]
    pub async fn memory_retrieval_evaluate(
        &self,
        request: beagle_memory::RetrievalEvalRequest,
    ) -> anyhow::Result<beagle_memory::RetrievalEvalReport> {
        if let Some(ref memory) = self.memory {
            memory.evaluate_retrieval(request).await
        } else {
            anyhow::bail!("MemoryEngine not initialized")
        }
    }

    #[cfg(feature = "memory")]
    pub async fn memory_feedback_adjusted_routed_retrieve(
        &self,
        request: beagle_memory::RelevanceFeedbackInput,
    ) -> anyhow::Result<beagle_memory::FeedbackLoopResult> {
        if let Some(ref memory) = self.memory {
            memory.feedback_adjusted_routed_retrieve(request).await
        } else {
            anyhow::bail!("MemoryEngine not initialized")
        }
    }

    #[cfg(feature = "memory")]
    pub fn memory_compiler_contract(
        &self,
    ) -> anyhow::Result<beagle_memory::MemoryCompilerContract> {
        if let Some(ref memory) = self.memory {
            Ok(memory.memory_compiler_contract())
        } else {
            anyhow::bail!("MemoryEngine not initialized")
        }
    }

    #[cfg(feature = "memory")]
    pub fn memory_context_budget_profile(
        &self,
        task_profile: &str,
    ) -> anyhow::Result<beagle_memory::ContextBudgetProfile> {
        if let Some(ref memory) = self.memory {
            memory.context_budget_profile(task_profile)
        } else {
            anyhow::bail!("MemoryEngine not initialized")
        }
    }

    #[cfg(feature = "memory")]
    pub async fn memory_compile_context(
        &self,
        request: beagle_memory::CompiledContextRequest,
    ) -> anyhow::Result<beagle_memory::CompiledContextPacket> {
        if let Some(ref memory) = self.memory {
            memory.compile_context(request).await
        } else {
            anyhow::bail!("MemoryEngine not initialized")
        }
    }

    #[cfg(feature = "memory")]
    pub async fn memory_evaluate_compiler_policies(
        &self,
        request: beagle_memory::CompilerEvalRequest,
    ) -> anyhow::Result<beagle_memory::CompilerEvalReport> {
        if let Some(ref memory) = self.memory {
            memory.evaluate_compiler_policies(request).await
        } else {
            anyhow::bail!("MemoryEngine not initialized")
        }
    }

    #[cfg(feature = "memory")]
    pub fn memory_derive_compiler_policy(
        &self,
        report: &beagle_memory::CompilerEvalReport,
    ) -> anyhow::Result<beagle_memory::CompilerPolicy> {
        if let Some(ref memory) = self.memory {
            Ok(memory.derive_compiler_policy(report))
        } else {
            anyhow::bail!("MemoryEngine not initialized")
        }
    }

    #[cfg(feature = "memory")]
    pub fn memory_derive_retrieval_policy(
        &self,
        report: &beagle_memory::RetrievalEvalReport,
    ) -> anyhow::Result<beagle_memory::RetrievalPolicy> {
        if let Some(ref memory) = self.memory {
            Ok(memory.derive_retrieval_policy(report))
        } else {
            anyhow::bail!("MemoryEngine not initialized")
        }
    }

    #[cfg(feature = "memory")]
    pub fn memory_promotion_policy(
        &self,
    ) -> anyhow::Result<beagle_memory::MemoryPromotionPolicy> {
        if let Some(ref memory) = self.memory {
            Ok(memory.memory_promotion_policy())
        } else {
            anyhow::bail!("MemoryEngine not initialized")
        }
    }

    #[cfg(feature = "memory")]
    pub fn memory_retention_policy(
        &self,
    ) -> anyhow::Result<beagle_memory::MemoryRetentionPolicy> {
        if let Some(ref memory) = self.memory {
            Ok(memory.memory_retention_policy())
        } else {
            anyhow::bail!("MemoryEngine not initialized")
        }
    }

    #[cfg(feature = "memory")]
    pub fn memory_temporal_schema(
        &self,
    ) -> anyhow::Result<beagle_memory::TemporalMemorySchema> {
        if let Some(ref memory) = self.memory {
            Ok(memory.temporal_memory_schema())
        } else {
            anyhow::bail!("MemoryEngine not initialized")
        }
    }

    #[cfg(feature = "memory")]
    pub async fn memory_temporal_query(
        &self,
        query: beagle_memory::TemporalQuery,
    ) -> anyhow::Result<beagle_memory::TemporalQueryResult> {
        if let Some(ref memory) = self.memory {
            memory.temporal_query(query).await
        } else {
            anyhow::bail!("MemoryEngine not initialized")
        }
    }

    #[cfg(feature = "memory")]
    pub fn memory_graph_rag_query_mode(
        &self,
        query: &beagle_memory::GraphRagQuery,
    ) -> anyhow::Result<beagle_memory::GraphRagQueryModeDecision> {
        if let Some(ref memory) = self.memory {
            Ok(memory.graph_rag_query_mode(query))
        } else {
            anyhow::bail!("MemoryEngine not initialized")
        }
    }

    #[cfg(feature = "memory")]
    pub async fn memory_evaluate_promotion(
        &self,
        memory_id: &str,
    ) -> anyhow::Result<Option<beagle_memory::PromotedMemory>> {
        if let Some(ref memory) = self.memory {
            memory.evaluate_memory_promotion(memory_id).await
        } else {
            anyhow::bail!("MemoryEngine not initialized")
        }
    }

    #[cfg(feature = "memory")]
    pub async fn memory_graph_rag_query(
        &self,
        query: beagle_memory::GraphRagQuery,
    ) -> anyhow::Result<beagle_memory::GraphRagResult> {
        if let Some(ref memory) = self.memory {
            memory.graph_rag_query(query).await
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

    /// WorldModel: Update world state from observations
    #[cfg(feature = "worldmodel")]
    pub async fn worldmodel_update(
        &self,
        observations: Vec<beagle_worldmodel::perception::Observation>,
    ) -> anyhow::Result<()> {
        if let Some(ref worldmodel) = self.worldmodel {
            worldmodel.update(observations).await?;
            Ok(())
        } else {
            anyhow::bail!("WorldModel not initialized")
        }
    }

    /// WorldModel: Predict future states
    #[cfg(feature = "worldmodel")]
    pub async fn worldmodel_predict(
        &self,
        horizon: usize,
    ) -> anyhow::Result<Vec<beagle_worldmodel::predictive::Prediction>> {
        if let Some(ref worldmodel) = self.worldmodel {
            Ok(worldmodel.predict(horizon).await?)
        } else {
            anyhow::bail!("WorldModel not initialized")
        }
    }

    /// WorldModel: Perform causal query
    #[cfg(feature = "worldmodel")]
    pub async fn worldmodel_causal_query(
        &self,
        query: beagle_worldmodel::causal::CausalQuery,
    ) -> anyhow::Result<f64> {
        if let Some(ref worldmodel) = self.worldmodel {
            Ok(worldmodel.causal_query(query).await?)
        } else {
            anyhow::bail!("WorldModel not initialized")
        }
    }

    /// WorldModel: Counterfactual reasoning
    #[cfg(feature = "worldmodel")]
    pub async fn worldmodel_counterfactual(
        &self,
        intervention: beagle_worldmodel::counterfactual::Intervention,
    ) -> anyhow::Result<beagle_worldmodel::state::WorldState> {
        if let Some(ref worldmodel) = self.worldmodel {
            Ok(worldmodel.counterfactual(intervention).await?)
        } else {
            anyhow::bail!("WorldModel not initialized")
        }
    }

    /// WorldModel: Query with natural language
    #[cfg(feature = "worldmodel")]
    pub async fn worldmodel_query(
        &self,
        query: &str,
    ) -> anyhow::Result<beagle_worldmodel::QueryResult> {
        if let Some(ref worldmodel) = self.worldmodel {
            Ok(worldmodel.query(query).await?)
        } else {
            anyhow::bail!("WorldModel not initialized")
        }
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

    /// Get router reference (convenience method for agents)
    pub fn router(&self) -> &TieredRouter {
        &self.router
    }

    /// Get current LLM stats for default run (convenience method)
    pub async fn get_current_stats(&self) -> beagle_llm::stats::LlmCallsStats {
        self.llm_stats.get_or_create("default")
    }

    /// Get LLM stats for a specific run_id
    pub fn get_stats_for_run(&self, run_id: &str) -> beagle_llm::stats::LlmCallsStats {
        self.llm_stats.get_or_create(run_id)
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
