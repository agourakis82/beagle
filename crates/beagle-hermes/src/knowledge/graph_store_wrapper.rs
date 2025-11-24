//! Wrapper para KnowledgeGraph que usa GraphStore trait quando disponível
//!
//! Permite que HERMES reutilize o GraphStore do BeagleContext,
//! mantendo compatibilidade com a API existente do KnowledgeGraph.
//!
//! **Status**: Preparado para uso futuro. Por enquanto, HERMES continua
//! usando KnowledgeGraph direto para manter compatibilidade.

use crate::{thought_capture::CapturedInsight, HermesError, Result};
use beagle_core::GraphStore;
use serde_json::json;
use std::sync::Arc;
use tracing::info;
use uuid::Uuid;

// Re-export para compatibilidade
pub use crate::knowledge::graph_client::KnowledgeGraph;

/// KnowledgeGraph que pode usar GraphStore trait quando disponível
#[derive(Clone)]
pub enum KnowledgeGraphWrapper {
    /// Usa GraphStore trait (do BeagleContext)
    WithGraphStore(Arc<dyn GraphStore>),
    /// Usa KnowledgeGraph original (modo legacy)
    Legacy(Arc<crate::knowledge::KnowledgeGraph>),
}

impl KnowledgeGraphWrapper {
    /// Cria wrapper com GraphStore
    pub fn with_graph_store(graph_store: Arc<dyn GraphStore>) -> Self {
        info!("KnowledgeGraphWrapper usando GraphStore trait");
        Self::WithGraphStore(graph_store)
    }

    /// Cria wrapper com KnowledgeGraph original (legacy)
    pub fn with_legacy(knowledge_graph: Arc<crate::knowledge::KnowledgeGraph>) -> Self {
        info!("KnowledgeGraphWrapper usando modo legacy");
        Self::Legacy(knowledge_graph)
    }

    /// Store insight in knowledge graph
    pub async fn store_insight(&self, insight: &CapturedInsight) -> Result<Uuid> {
        match self {
            Self::WithGraphStore(graph_store) => {
                // Usa GraphStore trait
                let query = format!(
                    "CREATE (i:Insight {{
                        id: $id,
                        text: $text,
                        source: $source,
                        timestamp: $timestamp,
                        confidence: $confidence
                    }})
                    RETURN i.id as id",
                );

                let params = json!({
                    "id": insight.id.to_string(),
                    "text": insight.text,
                    "source": format!("{:?}", insight.source),
                    "timestamp": insight.timestamp.to_rfc3339(),
                    "confidence": insight.metadata.confidence,
                });

                let result = graph_store
                    .cypher_query(&query, params)
                    .await
                    .map_err(|e| HermesError::Neo4jError(format!("GraphStore error: {}", e)))?;

                // Extrai ID do resultado
                if let Some(results) = result.get("results").and_then(|r| r.as_array()) {
                    if let Some(data) = results
                        .first()
                        .and_then(|r| r.get("data"))
                        .and_then(|d| d.as_array())
                    {
                        if let Some(row) = data.first() {
                            if let Some(id_str) = row.get("id").and_then(|v| v.as_str()) {
                                return Ok(Uuid::parse_str(id_str).map_err(|e| {
                                    HermesError::Neo4jError(format!("Invalid UUID: {}", e))
                                })?);
                            }
                        }
                    }
                }

                Ok(insight.id)
            }
            Self::Legacy(kg) => {
                // Usa KnowledgeGraph original (delega para implementação existente)
                // Por enquanto, mantém compatibilidade
                // TODO: migrar métodos de KnowledgeGraph para usar GraphStore quando possível
                kg.store_insight(insight)
                    .await
                    .map_err(|e| HermesError::Neo4jError(format!("KnowledgeGraph error: {}", e)))
            }
        }
    }
}
