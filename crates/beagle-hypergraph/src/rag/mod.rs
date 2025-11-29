//! Pipeline de Retrieval-Augmented Generation (RAG) utilizando travessia de
//! hipergrafo para contextualização profunda antes da geração com LLM.
//!
//! O fluxo implementa:
//! 1. Vetorização da consulta do usuário via provedor de embeddings.
//! 2. Busca semântica inicial dos nós mais relevantes (top-k).
//! 3. Expansão de contexto por travessia k-hop no hipergrafo.
//! 4. Ranqueamento multi-fator (similaridade, recência, centralidade topológica).
//! 5. Construção de prompt estruturado respeitando janela de contexto.
//! 6. Geração da resposta pelo modelo de linguagem.
//! 7. Extração de citações a partir do grafo contextual utilizado.
//!
//! ## Triple Context Restoration (TCR-QF)
//!
//! Enhanced GraphRAG with 29% improvement target through:
//! - Graph topology embeddings (Node2Vec)
//! - Temporal burst detection
//! - Late fusion architecture
//! - PageRank centrality

pub mod ab_testing;
pub mod eval;
pub mod tcr_qf;

use std::collections::{HashMap, HashSet};
use std::sync::Arc;

use async_trait::async_trait;
use chrono::{DateTime, Utc};
use serde::Serialize;
use thiserror::Error;
use tracing::{instrument, warn};

pub use eval::{GroundTruth, QueryResult, RetrievalEvaluator, RetrievalMetrics};
pub use tcr_qf::{FusionWeights, TcrQfConfig, TripleContextScores};
use uuid::Uuid;

use crate::embeddings::{EmbeddingError, EmbeddingGenerator};
use crate::error::HypergraphError;
use crate::models::Node;
#[cfg(feature = "database")]
use crate::search::{SearchResult, SemanticSearch};
#[cfg(feature = "database")]
use crate::storage::{CachedPostgresStorage, StorageRepository};

/// Estrutura de resposta consolidada após execução do pipeline RAG.
#[derive(Debug, Clone, Serialize)]
pub struct RAGResponse {
    /// Texto gerado pelo modelo de linguagem.
    pub answer: String,
    /// Lista de citações extraídas do contexto utilizado.
    pub citations: Vec<Citation>,
    /// Identificadores dos nós efetivamente incorporados ao prompt.
    pub context_nodes: Vec<Uuid>,
}

/// Representação de citação ancorada em um nó do hipergrafo.
#[derive(Debug, Clone, Serialize)]
pub struct Citation {
    pub node_id: Uuid,
    pub source: Option<String>,
    pub url: Option<String>,
    pub title: Option<String>,
}

/// Erros possíveis durante a execução do pipeline RAG.
#[derive(Debug, Error)]
pub enum RAGError {
    #[error("Erro ao interagir com o hipergrafo: {0}")]
    Hypergraph(#[from] HypergraphError),
    #[error("Falha na geração de embeddings: {0}")]
    Embedding(#[from] EmbeddingError),
    #[error("Falha na invocação do modelo de linguagem: {0}")]
    LanguageModel(#[from] LanguageModelError),
    #[error("Falha ao construir prompt contextualizado: {0}")]
    Prompt(String),
    #[error("Contexto insuficiente para responder à consulta")]
    EmptyContext,
}

/// Erros provenientes do provedor de LLM.
#[derive(Debug, Error)]
pub enum LanguageModelError {
    #[error("Erro na chamada ao provedor: {0}")]
    Invocation(String),
    #[error("Janela de contexto excedida (necessário {required} tokens, disponível {available})")]
    ContextLimit { required: usize, available: usize },
}

/// Interface abstrata para modelos de linguagem consumidos pelo pipeline.
#[async_trait]
pub trait LanguageModel: Send + Sync {
    /// Gera resposta textual a partir de um prompt estruturado.
    async fn generate(&self, prompt: &str) -> Result<String, LanguageModelError>;

    /// Retorna a janela máxima de contexto (em tokens) suportada pelo modelo, se conhecida.
    fn max_context_tokens(&self) -> Option<usize> {
        None
    }
}

/// Estrutura interna utilizada durante o ranqueamento de contexto.
#[derive(Debug, Clone)]
struct ContextNode {
    node: Node,
    min_distance: i32,
    anchor_similarity: f32,
    anchors: HashSet<Uuid>,
    score: f32,

    // TCR-QF: Triple Context Restoration with Quantum Fusion
    topology_embedding: Option<Vec<f32>>,
    tcr_qf_scores: Option<TripleContextScores>,
}

impl ContextNode {
    fn new(node: Node, distance: i32, similarity: f32, anchor: Uuid) -> Self {
        let mut anchors = HashSet::with_capacity(1);
        anchors.insert(anchor);

        // Extract topology embedding from metadata if available
        let topology_embedding = node
            .metadata
            .get("topology_embedding")
            .and_then(|v| v.as_array())
            .map(|arr| {
                arr.iter()
                    .filter_map(|v| v.as_f64().map(|f| f as f32))
                    .collect::<Vec<f32>>()
            });

        Self {
            node,
            min_distance: distance,
            anchor_similarity: similarity,
            anchors,
            score: 0.0,
            topology_embedding,
            tcr_qf_scores: None,
        }
    }

    fn update(&mut self, distance: i32, similarity: f32, anchor: Uuid) {
        if distance < self.min_distance {
            self.min_distance = distance;
        }
        if similarity > self.anchor_similarity {
            self.anchor_similarity = similarity;
        }
        self.anchors.insert(anchor);
    }
}

/// Artefato resultante da construção do prompt.
struct PromptArtifact {
    prompt: String,
    node_ids: Vec<Uuid>,
}

/// Pipeline completo de Retrieval-Augmented Generation respaldado pelo hipergrafo.
pub struct RAGPipeline {
    storage: Arc<CachedPostgresStorage>,
    search: SemanticSearch,
    llm: Arc<dyn LanguageModel>,
    embeddings: Arc<dyn EmbeddingGenerator>,
    max_context_tokens: usize,
    graph_hops: usize,

    // TCR-QF: Triple Context Restoration with Quantum Fusion
    tcr_qf_config: Option<TcrQfConfig>,
}

impl RAGPipeline {
    /// Cria instância padrão com profundidade de expansão 2 e orçamento de 2048 tokens.
    pub fn new(
        storage: Arc<CachedPostgresStorage>,
        llm: Arc<dyn LanguageModel>,
        embeddings: Arc<dyn EmbeddingGenerator>,
    ) -> Self {
        Self::with_config(storage, llm, embeddings, 2048, 2)
    }

    /// Cria pipeline com configuração explícita.
    pub fn with_config(
        storage: Arc<CachedPostgresStorage>,
        llm: Arc<dyn LanguageModel>,
        embeddings: Arc<dyn EmbeddingGenerator>,
        max_context_tokens: usize,
        graph_hops: usize,
    ) -> Self {
        let llm_context = llm.max_context_tokens().unwrap_or(max_context_tokens);
        let effective_budget = max_context_tokens.min(llm_context);

        let search = SemanticSearch::from_ref(storage.storage());

        Self {
            storage,
            search,
            llm,
            embeddings,
            max_context_tokens: effective_budget,
            graph_hops: graph_hops.max(1),
            tcr_qf_config: None, // Disabled by default
        }
    }

    /// Enable TCR-QF (Triple Context Restoration with Quantum Fusion)
    pub fn with_tcr_qf(mut self, config: TcrQfConfig) -> Self {
        self.tcr_qf_config = Some(config);
        self
    }

    /// Enable TCR-QF with default configuration
    pub fn enable_tcr_qf(mut self) -> Self {
        self.tcr_qf_config = Some(TcrQfConfig::default());
        self
    }

    /// Executa o pipeline RAG completo para uma consulta do usuário.
    #[instrument(name = "rag.pipeline.query", skip(self, user_query))]
    pub async fn query(&self, user_query: &str) -> Result<RAGResponse, RAGError> {
        // 1. Geração do embedding da query
        let query_embedding = self.embeddings.generate(user_query).await?;

        // 2. Busca semântica pelos nós mais relevantes
        let relevant_nodes = self
            .search
            .search_by_vector(&query_embedding, 20, 0.7)
            .await?;

        if relevant_nodes.is_empty() {
            warn!(
                "Busca semântica não retornou resultados para a consulta: {}",
                user_query
            );
            return Err(RAGError::EmptyContext);
        }

        // 3. Expansão de contexto via travessia k-hop
        let context_nodes = self
            .expand_context(relevant_nodes.clone(), self.graph_hops)
            .await?;

        // 4. Ranqueamento multi-fator do contexto
        let ranked_context = self
            .rank_context(context_nodes, query_embedding.as_ref())
            .await?;

        // 5. Construção do prompt com orçamento de tokens
        let prompt = self.build_prompt(user_query, &ranked_context)?;

        // 6. Geração da resposta pelo LLM
        let answer = self.llm.generate(&prompt.prompt).await?;

        let included: HashSet<Uuid> = prompt.node_ids.iter().copied().collect();

        // 7. Extração de citações
        let citations = self.extract_citations(&ranked_context, &included);

        Ok(RAGResponse {
            answer,
            citations,
            context_nodes: prompt.node_ids,
        })
    }

    async fn expand_context(
        &self,
        seeds: Vec<SearchResult>,
        hops: usize,
    ) -> Result<Vec<ContextNode>, HypergraphError> {
        let mut context: HashMap<Uuid, ContextNode> = HashMap::new();

        for seed in seeds {
            let anchor_id = seed.node.id;
            let anchor_similarity = seed.similarity;

            context
                .entry(anchor_id)
                .and_modify(|entry| entry.update(0, anchor_similarity, anchor_id))
                .or_insert_with(|| {
                    ContextNode::new(seed.node.clone(), 0, anchor_similarity, anchor_id)
                });

            let neighborhood = self
                .storage
                .query_neighborhood(anchor_id, hops as i32)
                .await?;

            for (neighbor, distance) in neighborhood {
                context
                    .entry(neighbor.id)
                    .and_modify(|entry| entry.update(distance, anchor_similarity, anchor_id))
                    .or_insert_with(|| {
                        ContextNode::new(neighbor, distance, anchor_similarity, anchor_id)
                    });
            }
        }

        Ok(context.into_values().collect())
    }

    async fn rank_context(
        &self,
        nodes: Vec<ContextNode>,
        query_embedding: &[f32],
    ) -> Result<Vec<ContextNode>, RAGError> {
        if nodes.is_empty() {
            return Err(RAGError::EmptyContext);
        }

        let now = Utc::now();
        let mut unique_anchors: HashSet<Uuid> = HashSet::new();
        for node in &nodes {
            unique_anchors.extend(node.anchors.iter().copied());
        }
        let anchor_count = unique_anchors.len().max(1);

        // Check if TCR-QF is enabled
        if let Some(tcr_qf_config) = &self.tcr_qf_config {
            self.rank_context_tcr_qf(nodes, query_embedding, now, anchor_count, tcr_qf_config)
                .await
        } else {
            // Classic ranking (baseline)
            self.rank_context_classic(nodes, query_embedding, now, anchor_count)
                .await
        }
    }

    /// Classic ranking (baseline without TCR-QF)
    async fn rank_context_classic(
        &self,
        nodes: Vec<ContextNode>,
        query_embedding: &[f32],
        now: DateTime<Utc>,
        anchor_count: usize,
    ) -> Result<Vec<ContextNode>, RAGError> {
        let mut nodes = nodes;
        for context_node in nodes.iter_mut() {
            let semantic_sim = match &context_node.node.embedding {
                Some(embedding) => cosine_similarity(embedding, query_embedding),
                None => context_node.anchor_similarity,
            };

            let age_days = time_delta_in_days(context_node.node.created_at, now);
            let recency = 1.0 / (1.0 + age_days);

            let centrality = (context_node.anchors.len() as f32) / (anchor_count as f32);
            let proximity = 1.0 / (1.0 + context_node.min_distance as f32);

            context_node.score =
                0.45 * semantic_sim + 0.3 * recency + 0.15 * centrality + 0.1 * proximity;
        }

        nodes.sort_by(|a, b| {
            b.score
                .partial_cmp(&a.score)
                .unwrap_or(std::cmp::Ordering::Equal)
        });

        Ok(nodes)
    }

    /// TCR-QF enhanced ranking with triple context restoration
    async fn rank_context_tcr_qf(
        &self,
        mut nodes: Vec<ContextNode>,
        query_embedding: &[f32],
        now: DateTime<Utc>,
        anchor_count: usize,
        config: &TcrQfConfig,
    ) -> Result<Vec<ContextNode>, RAGError> {
        use tcr_qf::{
            GraphStructure, PageRankCalculator, PeriodicRelevanceScorer, TemporalBurstDetector,
        };

        // Collect all timestamps for temporal analysis
        let all_timestamps: Vec<DateTime<Utc>> = nodes.iter().map(|n| n.node.created_at).collect();

        // Initialize TCR-QF components
        let burst_detector = if config.temporal_burst_enabled {
            Some(TemporalBurstDetector::new(
                config.burst_window_days,
                config.burst_z_threshold,
            ))
        } else {
            None
        };

        let periodic_scorer = if config.periodic_relevance_enabled {
            Some(PeriodicRelevanceScorer::new())
        } else {
            None
        };

        // Compute PageRank if enabled
        let pagerank_scores = if config.fusion_enabled {
            // Build graph structure from nodes
            let mut graph = GraphStructure::default();
            for node in &nodes {
                graph.nodes.insert(
                    node.node.id,
                    tcr_qf::NodeInfo {
                        id: node.node.id,
                        created_at: node.node.created_at,
                    },
                );
            }

            // TODO: Add edges from hypergraph storage
            // For now, use empty edge set (PageRank will be uniform)

            let calculator = PageRankCalculator::default();
            calculator.compute(&graph)
        } else {
            std::collections::HashMap::new()
        };

        // Compute scores for each node
        let nodes_len = nodes.len();
        let default_pagerank = 1.0 / nodes_len as f32;

        for context_node in nodes.iter_mut() {
            let mut scores = TripleContextScores::default();

            // 1. Semantic similarity (text embeddings)
            scores.semantic = match &context_node.node.embedding {
                Some(embedding) => cosine_similarity(embedding, query_embedding),
                None => context_node.anchor_similarity,
            };

            // 2. Topology similarity (graph structure embeddings)
            if config.graph_embeddings_enabled {
                if let Some(ref _topo_emb) = context_node.topology_embedding {
                    // TODO: Need query topology embedding
                    // For now, use 0.0 (will be implemented with Node2Vec)
                    scores.topology = 0.0;
                } else {
                    scores.topology = 0.0;
                }
            }

            // 3. Temporal burst detection
            if let Some(ref detector) = burst_detector {
                scores.temporal_burst =
                    detector.detect_burst(&context_node.node.created_at, &all_timestamps);
            }

            // 4. Periodic relevance
            if let Some(ref scorer) = periodic_scorer {
                scores.temporal_periodic =
                    scorer.compute_score(&context_node.node.created_at, &all_timestamps, &now);
            }

            // 5. Recency score
            let age_days = time_delta_in_days(context_node.node.created_at, now);
            scores.recency = 1.0 / (1.0 + age_days);

            // 6. Centrality (anchor connectivity)
            scores.centrality = (context_node.anchors.len() as f32) / (anchor_count as f32);

            // 7. Proximity (graph distance)
            scores.proximity = 1.0 / (1.0 + context_node.min_distance as f32);

            // 8. PageRank (global importance)
            scores.pagerank = pagerank_scores
                .get(&context_node.node.id)
                .copied()
                .unwrap_or(default_pagerank);

            // Quantum Fusion: Compute fused score
            scores.compute_fused(&config.fusion_weights);

            // Store scores and set final score
            context_node.score = scores.fused;
            context_node.tcr_qf_scores = Some(scores);
        }

        // Sort by fused score
        nodes.sort_by(|a, b| {
            b.score
                .partial_cmp(&a.score)
                .unwrap_or(std::cmp::Ordering::Equal)
        });

        Ok(nodes)
    }

    fn build_prompt(
        &self,
        user_query: &str,
        ranked_context: &[ContextNode],
    ) -> Result<PromptArtifact, RAGError> {
        if ranked_context.is_empty() {
            return Err(RAGError::EmptyContext);
        }

        let mut prompt = String::new();
        prompt.push_str("Você é um assistente científico especializado. Integre evidências do contexto para responder com precisão, citando fontes relevantes.\n\n");

        let mut budget = self.max_context_tokens;
        let mut used_nodes = Vec::new();

        for (idx, context_node) in ranked_context.iter().enumerate() {
            let metadata_str = serde_json::to_string(&context_node.node.metadata)
                .map_err(|err| RAGError::Prompt(format!("Falha ao serializar metadados: {err}")))?;

            let entry = format!(
                "[Contexto #{idx}] (score {:.3}, distância {})\nTipo: {}\nConteúdo: {}\nMetadados: {}\nCriado em: {}\n\n",
                context_node.score,
                context_node.min_distance,
                context_node.node.content_type,
                context_node.node.content,
                metadata_str,
                context_node.node.created_at.to_rfc3339(),
            );

            let entry_tokens = estimate_tokens(&entry);
            if entry_tokens > budget {
                break;
            }

            prompt.push_str(&entry);
            budget -= entry_tokens;
            used_nodes.push(context_node.node.id);
        }

        if used_nodes.is_empty() {
            return Err(RAGError::Prompt(
                "Nenhum nó pôde ser incluído no prompt dentro do orçamento de tokens".into(),
            ));
        }

        prompt.push_str("Consulta do usuário:\n");
        prompt.push_str(user_query);
        prompt.push_str(
            "\n\nResponda de forma estruturada, justificando com as fontes fornecidas.\n",
        );

        Ok(PromptArtifact {
            prompt,
            node_ids: used_nodes,
        })
    }

    fn extract_citations(
        &self,
        ranked_context: &[ContextNode],
        included: &HashSet<Uuid>,
    ) -> Vec<Citation> {
        ranked_context
            .iter()
            .filter(|node| included.contains(&node.node.id))
            .filter_map(|context_node| {
                context_node
                    .node
                    .metadata
                    .as_object()
                    .map(|metadata| {
                        let source = metadata
                            .get("source")
                            .and_then(|value| value.as_str())
                            .map(ToOwned::to_owned);
                        let url = metadata
                            .get("url")
                            .and_then(|value| value.as_str())
                            .map(ToOwned::to_owned);
                        let title = metadata
                            .get("title")
                            .and_then(|value| value.as_str())
                            .map(ToOwned::to_owned);

                        if source.is_none() && url.is_none() && title.is_none() {
                            None
                        } else {
                            Some(Citation {
                                node_id: context_node.node.id,
                                source,
                                url,
                                title,
                            })
                        }
                    })
                    .flatten()
            })
            .collect()
    }
}

fn cosine_similarity(a: &[f32], b: &[f32]) -> f32 {
    let numerator: f32 = a.iter().zip(b.iter()).map(|(x, y)| x * y).sum();
    let norm_a = a.iter().map(|v| v * v).sum::<f32>().sqrt();
    let norm_b = b.iter().map(|v| v * v).sum::<f32>().sqrt();

    if norm_a == 0.0 || norm_b == 0.0 {
        0.0
    } else {
        (numerator / (norm_a * norm_b)).clamp(-1.0, 1.0)
    }
}

fn time_delta_in_days(start: DateTime<Utc>, end: DateTime<Utc>) -> f32 {
    let delta = end.signed_duration_since(start);
    (delta.num_seconds().max(0) as f32) / 86_400.0
}

fn estimate_tokens(text: &str) -> usize {
    let char_based = text.chars().count() / 4;
    let word_based = text.split_whitespace().count();
    char_based.max(word_based).max(1)
}
