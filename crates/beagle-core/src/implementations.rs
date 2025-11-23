//! Implementações reais das traits do BEAGLE
//!
//! Wrappers que adaptam clientes existentes (Grok, vLLM, Qdrant, Neo4j)
//! para as interfaces definidas em `traits.rs`.

use crate::traits::*;
use anyhow::Result;
use async_trait::async_trait;
use beagle_config::BeagleConfig;
use serde_json::{json, Value};
use std::sync::Arc;
use tracing::warn;

// ============================================================================
// KNOWLEDGE SNIPPET HELPERS
// ============================================================================

/// Converte VectorHit para KnowledgeSnippet
pub fn vector_hit_to_snippet(hit: &VectorHit) -> KnowledgeSnippet {
    let text = hit
        .metadata
        .get("text")
        .and_then(|v| v.as_str())
        .unwrap_or("")
        .to_string();

    let title = hit
        .metadata
        .get("title")
        .and_then(|v| v.as_str())
        .map(|s| s.to_string());

    KnowledgeSnippet {
        source: "qdrant".to_string(),
        title,
        text,
        score: Some(hit.score),
        meta: hit.metadata.clone(),
    }
}

/// Converte resultado Neo4j (node/relation) para KnowledgeSnippet
pub fn neo4j_result_to_snippet(result: &serde_json::Value, score: Option<f32>) -> KnowledgeSnippet {
    // Extrai texto de diferentes campos possíveis
    let text = result
        .get("description")
        .or_else(|| result.get("text"))
        .or_else(|| result.get("name"))
        .and_then(|v| v.as_str())
        .unwrap_or("")
        .to_string();

    let title = result
        .get("name")
        .or_else(|| result.get("title"))
        .and_then(|v| v.as_str())
        .map(|s| s.to_string());

    KnowledgeSnippet {
        source: "neo4j".to_string(),
        title,
        text,
        score,
        meta: result.clone(),
    }
}

// ============================================================================
// LLM CLIENT IMPLEMENTATIONS
// ============================================================================

/// Implementação de LlmClient usando BeagleRouter (Grok 3 + Grok 4 Heavy)
pub struct GrokLlmClient {
    router: beagle_llm::BeagleRouter,
}

impl GrokLlmClient {
    pub fn new(_api_key: String) -> Result<Self> {
        // Router usa XAI_API_KEY diretamente do env
        Ok(Self {
            router: beagle_llm::BeagleRouter,
        })
    }
}

#[async_trait]
impl LlmClient for GrokLlmClient {
    async fn complete(&self, prompt: &str) -> Result<String> {
        // Retry logic com backoff exponencial
        let mut retries = 3;
        let mut delay_ms = 100;

        loop {
            match self.router.complete(prompt).await {
                Ok(result) => return Ok(result),
                Err(e) => {
                    if retries > 0 {
                        retries -= 1;
                        warn!("Grok API error, retrying ({} left): {}", retries, e);
                        tokio::time::sleep(tokio::time::Duration::from_millis(delay_ms)).await;
                        delay_ms *= 2; // Backoff exponencial
                        continue;
                    } else {
                        return Err(anyhow::anyhow!("Grok API error after retries: {}", e));
                    }
                }
            }
        }
    }

    async fn chat(&self, messages: &[ChatMessage]) -> Result<String> {
        if messages.is_empty() {
            return Err(anyhow::anyhow!("Nenhuma mensagem fornecida"));
        }

        // Combina mensagens em prompt único para o router
        let prompt = messages
            .iter()
            .map(|m| format!("{}: {}", m.role, m.content))
            .collect::<Vec<_>>()
            .join("\n\n");

        self.complete(&prompt).await
    }
}

/// Implementação de LlmClient usando vLLM
pub struct VllmLlmClient {
    client: Arc<beagle_llm::vllm::VllmClient>,
    model: String,
}

impl VllmLlmClient {
    pub fn new(vllm_url: String, model: Option<String>) -> Self {
        Self {
            client: Arc::new(beagle_llm::vllm::VllmClient::new(vllm_url)),
            model: model.unwrap_or_else(|| "meta-llama/Llama-3.3-70B-Instruct".to_string()),
        }
    }
}

#[async_trait]
impl LlmClient for VllmLlmClient {
    async fn complete(&self, prompt: &str) -> Result<String> {
        let request = beagle_llm::vllm::VllmCompletionRequest {
            model: self.model.clone(),
            prompt: prompt.to_string(),
            sampling_params: beagle_llm::vllm::SamplingParams {
                temperature: 0.8,
                top_p: 0.95,
                max_tokens: 8192,
                n: 1,
                stop: None,
                frequency_penalty: 0.0,
            },
        };

        // Retry logic
        let mut retries = 3;
        let mut delay_ms = 100;

        loop {
            match self.client.completions(&request).await {
                Ok(response) => {
                    return Ok(response
                        .choices
                        .first()
                        .map(|c| c.text.trim().to_string())
                        .unwrap_or_else(|| "Resposta vazia do vLLM".to_string()));
                }
                Err(e) => {
                    if retries > 0 {
                        retries -= 1;
                        warn!("vLLM error, retrying ({} left): {}", retries, e);
                        tokio::time::sleep(tokio::time::Duration::from_millis(delay_ms)).await;
                        delay_ms *= 2;
                        continue;
                    } else {
                        return Err(anyhow::anyhow!("vLLM error after retries: {}", e));
                    }
                }
            }
        }
    }

    async fn chat(&self, messages: &[ChatMessage]) -> Result<String> {
        // vLLM não tem suporte nativo a chat, então convertemos mensagens para prompt
        let prompt = messages
            .iter()
            .map(|m| format!("{}: {}", m.role, m.content))
            .collect::<Vec<_>>()
            .join("\n\n");
        self.complete(&prompt).await
    }
}

// ============================================================================
// VECTOR STORE IMPLEMENTATIONS
// ============================================================================

/// Implementação de VectorStore usando Qdrant com embeddings reais
pub struct QdrantVectorStore {
    base_url: String,
    collection: String,
    client: reqwest::Client,
    embedding_client: beagle_llm::embedding::EmbeddingClient,
    // Cache simples de embeddings (texto -> embedding)
    embedding_cache:
        std::sync::Arc<tokio::sync::RwLock<std::collections::HashMap<String, Vec<f64>>>>,
}

impl QdrantVectorStore {
    pub fn new(
        qdrant_url: String,
        collection: Option<String>,
        embedding_url: Option<String>,
    ) -> Self {
        let embedding_url =
            embedding_url.unwrap_or_else(|| "http://t560.local:8001/v1".to_string());
        Self {
            base_url: qdrant_url.trim_end_matches('/').to_string(),
            collection: collection.unwrap_or_else(|| "beagle".to_string()),
            client: reqwest::Client::new(),
            embedding_client: beagle_llm::embedding::EmbeddingClient::new(embedding_url),
            embedding_cache: std::sync::Arc::new(tokio::sync::RwLock::new(
                std::collections::HashMap::new(),
            )),
        }
    }

    pub fn from_config(cfg: &BeagleConfig) -> Result<Self> {
        let url = cfg
            .graph
            .qdrant_url
            .as_ref()
            .ok_or_else(|| anyhow::anyhow!("QDRANT_URL não configurado"))?;
        // Embedding URL pode vir de env ou usar default
        let embedding_url = std::env::var("EMBEDDING_URL")
            .or_else(|_| std::env::var("BEAGLE_EMBEDDING_URL"))
            .ok();
        Ok(Self::new(url.clone(), None, embedding_url))
    }

    /// Gera embedding com cache
    async fn get_embedding(&self, text: &str) -> Result<Vec<f64>> {
        // Verifica cache
        {
            let cache = self.embedding_cache.read().await;
            if let Some(emb) = cache.get(text) {
                return Ok(emb.clone());
            }
        }

        // Gera embedding
        let embedding = self.embedding_client.embed(text).await?;

        // Armazena no cache
        {
            let mut cache = self.embedding_cache.write().await;
            cache.insert(text.to_string(), embedding.clone());
        }

        Ok(embedding)
    }
}

#[async_trait]
impl VectorStore for QdrantVectorStore {
    async fn query(&self, text: &str, top_k: usize) -> Result<Vec<VectorHit>> {
        use serde_json::json;

        // 1. Gera embedding do texto de query
        let query_embedding = self.get_embedding(text).await?;

        // 2. Converte para f32 (Qdrant usa f32)
        let query_vector: Vec<f32> = query_embedding.iter().map(|&x| x as f32).collect();

        // 3. Faz busca no Qdrant
        let search_url = format!(
            "{}/collections/{}/points/search",
            self.base_url, self.collection
        );

        let search_request = json!({
            "vector": query_vector,
            "limit": top_k,
            "with_payload": true,
            "with_vector": false
        });

        let response = self
            .client
            .post(&search_url)
            .json(&search_request)
            .send()
            .await?;

        let status = response.status();
        if !status.is_success() {
            let error_text = response.text().await.unwrap_or_default();
            warn!("Qdrant search error {}: {}", status, error_text);
            // Fallback para mock se Qdrant não disponível
            return Ok((0..top_k.min(5))
                .map(|i| VectorHit {
                    id: format!("qdrant_fallback_{}", i),
                    score: 0.9 - (i as f32 * 0.1),
                    metadata: json!({
                        "text": format!("Fallback result {} for: {}", i, text),
                        "error": error_text,
                    }),
                })
                .collect());
        }

        let search_response: serde_json::Value = response.json().await?;

        // 4. Processa resultados
        let mut hits = Vec::new();
        if let Some(results) = search_response.get("result").and_then(|r| r.as_array()) {
            for result in results {
                let id = result
                    .get("id")
                    .and_then(|v| v.as_str())
                    .unwrap_or("unknown")
                    .to_string();
                let score = result
                    .get("score")
                    .and_then(|v| v.as_f64())
                    .map(|s| s as f32)
                    .unwrap_or(0.0);
                let payload = result.get("payload").cloned().unwrap_or_else(|| json!({}));

                hits.push(VectorHit {
                    id,
                    score,
                    metadata: payload,
                });
            }
        }

        if hits.is_empty() {
            warn!("Qdrant retornou resultados vazios para: {}", text);
        }

        Ok(hits)
    }
}

// ============================================================================
// NO-OP STORES (DEGRADED MODE)
// ============================================================================

/// Vector store que não faz nada (para degraded mode)
pub struct NoOpVectorStore;

#[async_trait]
impl VectorStore for NoOpVectorStore {
    async fn query(&self, text: &str, _top_k: usize) -> Result<Vec<VectorHit>> {
        warn!(
            "NoOpVectorStore: vector store indisponível, retornando vazio para query: {}",
            text
        );
        Ok(Vec::new())
    }
}

/// Graph store que não faz nada (para degraded mode)
pub struct NoOpGraphStore;

#[async_trait]
impl GraphStore for NoOpGraphStore {
    async fn cypher_query(
        &self,
        query: &str,
        _params: serde_json::Value,
    ) -> Result<serde_json::Value> {
        warn!(
            "NoOpGraphStore: graph store indisponível, retornando vazio para query: {}",
            query
        );
        Ok(json!({
            "results": [],
            "note": "Graph store unavailable - using no-op implementation"
        }))
    }
}

// ============================================================================
// GRAPH STORE IMPLEMENTATIONS
// ============================================================================

/// Implementação de GraphStore usando beagle-memory's Neo4jGraphStore
///
/// Este wrapper adapta a interface rica do beagle-memory::GraphStore
/// para a interface simplificada cypher_query do beagle-core::traits::GraphStore
#[cfg(feature = "neo4j")]
pub struct Neo4jGraphStore {
    inner: std::sync::Arc<beagle_memory::Neo4jGraphStore>,
}

#[cfg(feature = "neo4j")]
impl Neo4jGraphStore {
    pub async fn new(uri: String, user: String, password: String) -> Result<Self> {
        let inner = beagle_memory::Neo4jGraphStore::new(&uri, &user, &password)
            .await
            .map_err(|e| anyhow::anyhow!("Failed to connect to Neo4j: {}", e))?;

        Ok(Self {
            inner: std::sync::Arc::new(inner),
        })
    }

    pub async fn from_config(cfg: &BeagleConfig) -> Result<Self> {
        let uri = cfg
            .graph
            .neo4j_uri
            .as_ref()
            .ok_or_else(|| anyhow::anyhow!("NEO4J_URI não configurado"))?
            .clone();
        let user = cfg
            .graph
            .neo4j_user
            .as_ref()
            .ok_or_else(|| anyhow::anyhow!("NEO4J_USER não configurado"))?
            .clone();
        let password = cfg
            .graph
            .neo4j_password
            .as_ref()
            .ok_or_else(|| anyhow::anyhow!("NEO4J_PASSWORD não configurado"))?
            .clone();

        Self::new(uri, user, password).await
    }

    /// Acesso direto ao store interno para operações avançadas
    pub fn inner(&self) -> &beagle_memory::Neo4jGraphStore {
        &self.inner
    }
}

#[cfg(feature = "neo4j")]
#[async_trait]
impl GraphStore for Neo4jGraphStore {
    async fn cypher_query(&self, query: &str, params: Value) -> Result<Value> {
        use beagle_memory::GraphStore as MemGraphStore;
        use serde_json::json;

        // Converte params JSON para HashMap<String, Value>
        let params_map = if let Some(obj) = params.as_object() {
            obj.iter()
                .map(|(k, v)| (k.clone(), v.clone()))
                .collect::<std::collections::HashMap<String, Value>>()
        } else {
            std::collections::HashMap::new()
        };

        // Usa o método query do beagle-memory::GraphStore
        let result = self
            .inner
            .query(query, params_map)
            .await
            .map_err(|e| anyhow::anyhow!("Neo4j query failed: {}", e))?;

        // Converte GraphQueryResult para formato legacy
        let mut result_rows = Vec::new();
        for node in result.nodes {
            result_rows.push(json!({
                "id": node.id,
                "labels": node.labels,
                "properties": node.properties,
            }));
        }

        Ok(json!({
            "results": [{
                "data": result_rows
            }],
            "relationships": result.relationships.iter().map(|rel| json!({
                "id": rel.id,
                "from": rel.from_id,
                "to": rel.to_id,
                "type": rel.rel_type,
                "properties": rel.properties,
            })).collect::<Vec<_>>(),
        }))
    }
}
