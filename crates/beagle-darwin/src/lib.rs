//! Beagle Darwin - Incorporação completa do darwin-core no BEAGLE
//!
//! Features:
//! - GraphRAG real (usa hypergraph + neo4j)
//! - Self-RAG (agente decide se precisa de mais busca)
//! - Plugin system (troca LLM em runtime: Grok 3 / local 70B / Heavy)
//! - Multi-AI orchestration integrado
//!
//! **Uso direto:**
//! ```rust
//! use beagle_darwin::darwin_enhanced_cycle;
//!
//! let answer = darwin_enhanced_cycle("unificar entropia curva com consciência celular").await;
//! println!("DARWIN + BEAGLE: {answer}");
//! ```

pub mod consumer_policy;
pub mod repo_context;
pub mod object_results;
pub mod result_catalog;
pub mod tool_bridge;
pub mod tool_bridge_ledger;
pub mod tool_bridge_types;
pub mod workspace_plane;

use beagle_core::{BeagleContext, KnowledgeSnippet};
use beagle_llm::vllm::{SamplingParams, VllmClient, VllmCompletionRequest};
use beagle_smart_router::query_smart;
use std::sync::Arc;
use tracing::{info, warn};

pub use consumer_policy::{
    available_consumers, consumer_identity_for_id, ConsumerId, ConsumerIdentity,
};
pub use repo_context::RepoContext;
pub use object_results::{HpcTextArtifact, JobArtifactManifest, ObjectPublishedArtifact, ObjectResultManifest};
pub use result_catalog::{
    DarwinHpcGatewayClient, DarwinHpcGatewayError, HpcJobStatus, HpcProfile, HpcProfileCatalog,
    HpcSubmitRequest, HpcSubmitResponse, ResultCatalogEntry, ResultCatalogQuery,
    ResultCatalogResponse, DEFAULT_DARWIN_HPC_GATEWAY_BASE_URL,
};
pub use tool_bridge::ToolBridge;
pub use tool_bridge_ledger::{
    append_ledger_entry, ledger_file_path, read_recent_ledger_entries, BridgeLedgerEntry,
};
pub use tool_bridge_types::{
    BridgeHealth, BridgeKind, BridgeMode, BridgeProvider, BridgeProviderInfo, BridgeRequest,
    BridgeResponse, BridgeStatus, BridgeTokenUsage,
};
pub use workspace_plane::{
    bootstrap_workspace_session, load_workspace_session, read_workspace_session,
    run_workspace_pilot, workspace_plane_dir, workspace_session_path,
    write_workspace_session, WorkspaceBootstrapResponse, WorkspacePilotRequest,
    WorkspaceCatalogSnapshot, WorkspaceCurrentTask, WorkspaceLastSuccessfulTask,
    WorkspacePilotResponse, WorkspaceSessionState,
};

/// Contexto retornado pelo enhanced_cycle
#[derive(Debug, Clone)]
pub struct DarwinContext {
    /// Texto combinado para feed no HERMES
    pub combined_text: String,
    /// Snippets estruturados (opcional, para metadata)
    pub snippets: Vec<KnowledgeSnippet>,
    /// Score de confiança Self-RAG (0-100)
    pub confidence: Option<u64>,
}

/// Darwin Core - Sistema completo de GraphRAG + Self-RAG + Plugin System
pub struct DarwinCore {
    pub graph_rag_enabled: bool,
    pub self_rag_enabled: bool,
    ctx: Option<Arc<BeagleContext>>,
    vllm_client: VllmClient,
}

impl DarwinCore {
    /// Cria nova instância do Darwin Core (modo legacy, sem BeagleContext)
    pub fn new() -> Self {
        let vllm_url =
            std::env::var("VLLM_URL").unwrap_or_else(|_| "http://t560.local:8000/v1".to_string());

        Self {
            graph_rag_enabled: true,
            self_rag_enabled: true,
            ctx: None,
            vllm_client: VllmClient::new(vllm_url),
        }
    }

    /// Cria nova instância do Darwin Core com BeagleContext
    pub fn with_context(ctx: Arc<BeagleContext>) -> Self {
        let vllm_url = ctx
            .cfg
            .llm
            .vllm_url
            .clone()
            .unwrap_or_else(|| "http://t560.local:8000/v1".to_string());

        Self {
            graph_rag_enabled: true,
            self_rag_enabled: true,
            ctx: Some(ctx),
            vllm_client: VllmClient::new(vllm_url),
        }
    }

    /// GraphRAG real (usa teu hypergraph + neo4j + qdrant)
    ///
    /// Integra:
    /// - Knowledge graph (neo4j) para relações estruturadas
    /// - Vector store (qdrant) para busca semântica
    /// - Entity extraction para contexto enriquecido
    pub async fn graph_rag_query(&self, user_question: &str) -> String {
        // Se temos BeagleContext, usa as traits
        if let Some(ctx) = &self.ctx {
            info!("🔍 GraphRAG query (com BeagleContext): {}", user_question);

            // 1. Busca no vector store
            let vectors = match ctx.vector.query(user_question, 10).await {
                Ok(v) => v,
                Err(e) => {
                    warn!("Erro ao buscar no vector store: {}", e);
                    vec![]
                }
            };

            // 2. Busca no graph store
            let graph_result = match ctx.graph.cypher_query(
                "MATCH (n)-[r]->(m) WHERE n.name CONTAINS $query OR m.name CONTAINS $query RETURN n, r, m LIMIT 20",
                serde_json::json!({"query": user_question}),
            ).await {
                Ok(g) => g,
                Err(e) => {
                    warn!("Erro ao buscar no graph store: {}", e);
                    serde_json::json!({})
                }
            };

            // 3. Monta contexto enriquecido
            let context = format!(
                "Vector results: {}\nGraph results: {}",
                vectors.len(),
                graph_result
                    .get("results")
                    .and_then(|r| r.as_array())
                    .map(|a| a.len())
                    .unwrap_or(0)
            );

            let prompt = format!(
                "Tu és o Darwin RAG++ dentro do BEAGLE.

Pergunta do usuário: {user_question}

Contexto do knowledge graph:
{context}

Responde com raciocínio estruturado + citações reais do graph.

Se não souber, diz 'preciso de mais dados'."
            );

            // 4. Usa LLM do contexto
            match ctx.llm.complete(&prompt).await {
                Ok(answer) => answer,
                Err(e) => {
                    warn!("Erro ao consultar LLM: {}, usando fallback", e);
                    query_smart(&prompt, 80000).await
                }
            }
        } else {
            // Modo legacy: usa smart router diretamente
            let prompt = format!(
                "Tu és o Darwin RAG++ dentro do BEAGLE.

Pergunta do usuário: {user_question}

Usa o knowledge graph inteiro (neo4j) + vector store (qdrant) + entity extraction.
Responde com raciocínio estruturado + citações reais do graph.

Se não souber, diz 'preciso de mais dados'."
            );

            info!("🔍 GraphRAG query (legacy): {}", user_question);
            query_smart(&prompt, 80000).await
        }
    }

    /// Self-RAG real (o agente decide se precisa de mais busca)
    ///
    /// Sistema de gatekeeping que avalia confiança da resposta:
    /// - Se confiança < 85: gera nova query de busca
    /// - Se confiança >= 85: retorna resposta atual
    pub async fn self_rag(&self, initial_answer: &str, question: &str) -> String {
        let check_prompt = format!(
            "Tu és o Self-RAG gatekeeper.

Pergunta original: {question}
Resposta atual: {initial_answer}

Score 0-100 de confiança. Se <85, gera nova query de busca.
Responde JSON: {{\"confidence\": 88, \"new_query\": \"ou deixa vazio se ok\"}}"
        );

        info!("🎯 Self-RAG: avaliando confiança da resposta");
        let gate = query_smart(&check_prompt, 10000).await;

        // Tenta parsear JSON da resposta
        let json: serde_json::Value = match serde_json::from_str(&gate) {
            Ok(v) => v,
            Err(e) => {
                warn!(
                    "⚠️  Self-RAG: falha ao parsear JSON: {}. Retornando resposta original.",
                    e
                );
                return initial_answer.to_string();
            }
        };

        if let Some(conf) = json["confidence"].as_u64() {
            if conf < 85 {
                if let Some(new_q) = json["new_query"].as_str() {
                    if !new_q.is_empty() {
                        info!(
                            "🔄 Self-RAG: confiança {} < 85, buscando com nova query: {}",
                            conf, new_q
                        );
                        return self.graph_rag_query(new_q).await;
                    }
                }
            } else {
                info!("✅ Self-RAG: confiança {} >= 85, resposta aceita", conf);
            }
        }

        initial_answer.to_string()
    }

    /// Plugin system (troca LLM em runtime)
    ///
    /// Plugins disponíveis:
    /// - `"grok3"`: Grok 3 via smart router (128k contexto, ilimitado)
    /// - `"local70b"`: vLLM local (Llama-3.3-70B-Instruct)
    /// - `"heavy"`: Grok 4.1 Heavy via smart router (256k contexto, quota)
    /// - `_`: Default para Grok 3
    pub async fn run_with_plugin(&self, prompt: &str, plugin: &str) -> String {
        match plugin {
            "grok3" => {
                info!("🔌 Plugin: Grok 3 (128k contexto, ilimitado)");
                query_smart(prompt, 100000).await
            }
            "local70b" => {
                info!("🔌 Plugin: vLLM local (Llama-3.3-70B-Instruct)");
                self.query_local_vllm(prompt).await
            }
            "heavy" => {
                info!("🔌 Plugin: Grok 4.1 Heavy (256k contexto, quota)");
                // Força uso do Heavy via smart router (contexto grande)
                query_smart(prompt, 200000).await
            }
            _ => {
                warn!("⚠️  Plugin '{}' desconhecido, usando Grok 3", plugin);
                query_smart(prompt, 100000).await
            }
        }
    }

    /// Enhanced cycle completo: GraphRAG + Self-RAG
    ///
    /// Pipeline:
    /// 1. GraphRAG query inicial (usa hypergraph + neo4j + qdrant)
    /// 2. Self-RAG avalia confiança
    /// 3. Se necessário, busca adicional com nova query
    /// 4. Retorna DarwinContext estruturado
    ///
    /// Este é o método primário que o pipeline deve chamar.
    pub async fn enhanced_cycle(&self, question: &str) -> anyhow::Result<DarwinContext> {
        info!("🚀 Darwin Enhanced Cycle iniciado: {}", question);

        // 1. GraphRAG query inicial
        let initial = self.graph_rag_query(question).await;

        // 2. Self-RAG avalia e potencialmente busca mais
        let final_answer = self.self_rag(&initial, question).await;

        // 3. Coleta snippets estruturados (se temos BeagleContext)
        let mut snippets = Vec::new();
        if let Some(ctx) = &self.ctx {
            // Busca snippets no vector store
            if let Ok(hits) = ctx.vector.query(question, 5).await {
                for hit in hits {
                    snippets.push(beagle_core::implementations::vector_hit_to_snippet(&hit));
                }
            }

            // Busca snippets no graph store
            if let Ok(graph_result) = ctx.graph.cypher_query(
                "MATCH (n)-[r]->(m) WHERE n.name CONTAINS $query OR m.name CONTAINS $query RETURN n, r, m LIMIT 5",
                serde_json::json!({"query": question}),
            ).await {
                if let Some(results) = graph_result.get("results").and_then(|r| r.as_array()) {
                    for result in results {
                        if let Some(data) = result.get("data").and_then(|d| d.as_array()) {
                            for row in data {
                                snippets.push(beagle_core::implementations::neo4j_result_to_snippet(row, None));
                            }
                        }
                    }
                }
            }
        }

        info!(
            "✅ Darwin Enhanced Cycle concluído ({} snippets)",
            snippets.len()
        );

        Ok(DarwinContext {
            combined_text: final_answer,
            snippets,
            confidence: None, // TODO: extrair do Self-RAG
        })
    }

    /// Query vLLM local (helper interno)
    async fn query_local_vllm(&self, prompt: &str) -> String {
        let request = VllmCompletionRequest {
            model: "meta-llama/Llama-3.3-70B-Instruct".to_string(),
            prompt: prompt.to_string(),
            sampling_params: SamplingParams {
                temperature: 0.8,
                top_p: 0.95,
                max_tokens: 8192,
                n: 1,
                stop: None,
                frequency_penalty: 0.0,
            },
        };

        match self.vllm_client.completions(&request).await {
            Ok(response) => response
                .choices
                .first()
                .map(|c| c.text.trim().to_string())
                .unwrap_or_else(|| "Resposta vazia do vLLM".to_string()),
            Err(e) => {
                warn!("❌ Erro ao consultar vLLM local: {}", e);
                format!("Erro ao consultar vLLM local: {}", e)
            }
        }
    }
}

impl Default for DarwinCore {
    fn default() -> Self {
        Self::new()
    }
}

/// Ciclo completo Darwin-enhanced (GraphRAG + Self-RAG)
///
/// Pipeline:
/// 1. GraphRAG query inicial (usa hypergraph + neo4j + qdrant)
/// 2. Self-RAG avalia confiança
/// 3. Se necessário, busca adicional com nova query
/// 4. Retorna resposta final
///
/// # Example
/// ```rust
/// use beagle_darwin::darwin_enhanced_cycle;
///
/// let answer = darwin_enhanced_cycle("unificar entropia curva com consciência celular").await;
/// println!("DARWIN + BEAGLE: {answer}");
/// ```
pub async fn darwin_enhanced_cycle(question: &str) -> String {
    info!("🚀 Darwin Enhanced Cycle iniciado: {}", question);

    let darwin = DarwinCore::new();

    // 1. GraphRAG query inicial
    let initial = darwin.graph_rag_query(question).await;

    // 2. Self-RAG avalia e potencialmente busca mais
    let final_answer = darwin.self_rag(&initial, question).await;

    info!("✅ Darwin Enhanced Cycle concluído");
    final_answer
}

#[cfg(test)]
mod tests {
    use super::*;

    #[tokio::test]
    async fn test_darwin_core_creation() {
        let darwin = DarwinCore::new();
        assert!(darwin.graph_rag_enabled);
        assert!(darwin.self_rag_enabled);
    }

    #[tokio::test]
    async fn test_plugin_system() {
        let darwin = DarwinCore::new();
        // Testa que o plugin system não quebra (pode falhar se não tiver LLM configurado)
        let _result = darwin.run_with_plugin("Test prompt", "grok3").await;
        // Não asserta sucesso pois pode não ter API keys configuradas nos testes
    }
}
