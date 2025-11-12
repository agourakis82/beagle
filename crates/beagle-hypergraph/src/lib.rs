//! Núcleo público da crate `beagle-hypergraph`.
//!
//! Este módulo expõe estruturas de domínio, tipos de erro, backends de
//! armazenamento e a fachada [`Hypergraph`], permitindo a composição de
//! fluxos de negócio sobre o hipergrafo com diferentes provedores de dados.
pub mod cache;
mod graph;
mod metrics;
mod profiling;
pub mod resilience;
pub mod search;
mod serde_helpers;
mod sync;
pub mod traits;
pub mod types;

/// Geração e pipelines de embeddings.
pub mod embeddings;
/// Tipos de erro compartilhados por operações do hipergrafo.
pub mod error;
/// Modelos de domínio e validações canônicas.
pub mod models;
/// Pipelines de Retrieval-Augmented Generation sobre o hipergrafo.
pub mod rag;
/// Abstrações e implementações concretas de armazenamento.
pub mod storage;

pub use cache::{CacheStats, RedisCache};
pub use error::{HypergraphError, Result};
pub use models::{ContentType, Hyperedge, Node};
pub use rag::{Citation, LanguageModel, LanguageModelError, RAGError, RAGPipeline, RAGResponse};
pub use storage::{
    CachedPostgresStorage, HypergraphStorage, NodeFilters, PostgresStorage, StorageRepository,
};

use uuid::Uuid;

/// Fachada de alto nível para operar sobre o hipergrafo Beagle.
///
/// É parametrizada por um backend que implementa [`HypergraphStorage`],
/// permitindo alternância entre bancos de dados sem alterar a API externa.
///
/// # Examples
/// ```no_run
/// use beagle_hypergraph::{ContentType, Hypergraph, PostgresStorage};
/// use serde_json::json;
///
/// #[tokio::main]
/// async fn main() -> beagle_hypergraph::Result<()> {
///     let storage = PostgresStorage::new("postgresql://localhost/beagle").await?;
///     let hypergraph = Hypergraph::new(storage);
///
///     let node = hypergraph
///         .create_node(
///             "Test thought".into(),
///             ContentType::Thought,
///             json!({"priority": 5}),
///             "device-alpha",
///         )
///         .await?;
///
///     println!("Created node {}", node.id);
///     Ok(())
/// }
/// ```
pub struct Hypergraph<S: HypergraphStorage> {
    storage: S,
}

impl<S: HypergraphStorage> Hypergraph<S> {
    /// Cria uma fachada a partir de um backend de armazenamento.
    pub fn new(storage: S) -> Self {
        Self { storage }
    }

    /// Retorna referência ao backend interno.
    pub fn storage(&self) -> &S {
        &self.storage
    }

    /// Cria um [`Node`] delegando ao backend de armazenamento.
    pub async fn create_node(
        &self,
        content: String,
        content_type: ContentType,
        metadata: serde_json::Value,
        device_id: &str,
    ) -> Result<Node> {
        let node = Node::builder()
            .content(content)
            .content_type(content_type)
            .metadata(metadata)
            .device_id(device_id)
            .build()?;
        self.storage.create_node(node).await
    }

    /// Recupera um [`Node`] por identificador.
    pub async fn get_node(&self, id: Uuid) -> Result<Node> {
        self.storage.get_node(id).await
    }

    /// Remove logicamente um [`Node`].
    pub async fn delete_node(&self, id: Uuid) -> Result<()> {
        self.storage.delete_node(id).await
    }

    /// Cria um [`Hyperedge`] conectando os nós informados.
    pub async fn create_hyperedge(
        &self,
        node_ids: Vec<Uuid>,
        label: String,
        device_id: &str,
        is_directed: bool,
        metadata: serde_json::Value,
    ) -> Result<Hyperedge> {
        let mut edge = Hyperedge::new(label, node_ids, is_directed, device_id.to_string())?;
        edge.metadata = metadata;
        self.storage.create_hyperedge(edge).await
    }

    /// Explora a vizinhança de um nó até a profundidade solicitada.
    pub async fn explore(&self, start_node: Uuid, depth: i32) -> Result<Vec<(Node, i32)>> {
        self.storage.query_neighborhood(start_node, depth).await
    }
}

impl<S: HypergraphStorage + Clone> Clone for Hypergraph<S> {
    fn clone(&self) -> Self {
        Self {
            storage: self.storage.clone(),
        }
    }
}

/// Conjunto de importações usuais para ergonomia em aplicações consumidoras.
pub mod prelude {
    pub use crate::{
        error::{HypergraphError, Result},
        models::{ContentType, Hyperedge, Node},
        storage::{HypergraphStorage, NodeFilters, PostgresStorage},
        Hypergraph,
    };
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::json;

    #[tokio::test]
    #[ignore] // Requer infraestrutura PostgreSQL ativa
    async fn test_hypergraph_end_to_end() {
        let storage = PostgresStorage::new(
            "postgresql://beagle_user:beagle_dev_password_CHANGE_IN_PRODUCTION@localhost:5432/beagle_dev",
        )
        .await
        .unwrap();

        let hg = Hypergraph::new(storage);

        let node_a = hg
            .create_node(
                "Node A".into(),
                ContentType::Thought,
                json!({}),
                "device-alpha",
            )
            .await
            .unwrap();
        let node_b = hg
            .create_node(
                "Node B".into(),
                ContentType::Memory,
                json!({}),
                "device-alpha",
            )
            .await
            .unwrap();

        let edge = hg
            .create_hyperedge(
                vec![node_a.id, node_b.id],
                "relates".into(),
                "device-alpha",
                false,
                json!({}),
            )
            .await
            .unwrap();
        assert_eq!(edge.node_ids.len(), 2);

        let neighbors = hg.explore(node_a.id, 1).await.unwrap();
        assert!(
            neighbors.iter().any(|(node, _)| node.id == node_a.id),
            "Node A deve aparecer na vizinhança"
        );
        assert!(
            neighbors.iter().any(|(node, _)| node.id == node_b.id),
            "Node B deve aparecer na vizinhança"
        );
    }
}
