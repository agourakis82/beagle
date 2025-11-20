//! Abstrações de persistência para o hipergrafo Beagle.

#[cfg(feature = "database")]
use async_trait::async_trait;
#[cfg(feature = "database")]
use chrono::{DateTime, Utc};
#[cfg(feature = "database")]
use uuid::Uuid;

#[cfg(feature = "database")]
use crate::{
    error::Result,
    models::{ContentType, Hyperedge, Node},
};

#[cfg(feature = "database")]
pub mod cached_postgres;
#[cfg(feature = "database")]
pub mod postgres;

#[cfg(feature = "database")]
pub use cached_postgres::CachedPostgresStorage;
#[cfg(feature = "database")]
pub use postgres::{HealthStatus, PostgresStorage};

/// Filtros opcionais utilizados para consultas de nós.
#[derive(Debug, Clone, Default)]
pub struct NodeFilters {
    /// Filtra por tipo de conteúdo.
    pub content_type: Option<ContentType>,
    /// Filtra por identificador do dispositivo.
    pub device_id: Option<String>,
    /// Filtra nós criados após o timestamp informado.
    pub created_after: Option<DateTime<Utc>>,
    /// Filtra nós criados antes do timestamp informado.
    pub created_before: Option<DateTime<Utc>>,
}

/// Contrato assíncrono para camadas de armazenamento do hipergrafo.
///
/// Este trait é um alias semântico para [`StorageRepository`], preservando a
/// compatibilidade com a API pública da crate.
pub trait HypergraphStorage: StorageRepository {}

impl<T> HypergraphStorage for T where T: StorageRepository {}

/// Interface de alto nível para operações completas sobre o hipergrafo.
#[async_trait]
pub trait StorageRepository: Send + Sync {
    // ===== nós =====
    async fn create_node(&self, node: Node) -> Result<Node>;
    async fn get_node(&self, id: Uuid) -> Result<Node>;
    async fn update_node(&self, node: Node) -> Result<Node>;
    async fn delete_node(&self, id: Uuid) -> Result<()>;
    async fn list_nodes(&self, filters: Option<NodeFilters>) -> Result<Vec<Node>>;
    async fn batch_get_nodes(&self, ids: Vec<Uuid>) -> Result<Vec<Node>>;

    // ===== hiperedges =====
    async fn create_hyperedge(&self, edge: Hyperedge) -> Result<Hyperedge>;
    async fn get_hyperedge(&self, id: Uuid) -> Result<Hyperedge>;
    async fn update_hyperedge(&self, edge: Hyperedge) -> Result<Hyperedge>;
    async fn delete_hyperedge(&self, id: Uuid) -> Result<()>;
    async fn list_hyperedges(&self, node_id: Option<Uuid>) -> Result<Vec<Hyperedge>>;

    // ===== consultas e travessias =====
    async fn query_neighborhood(&self, start_node: Uuid, depth: i32) -> Result<Vec<(Node, i32)>>;
    async fn get_connected_nodes(&self, edge_id: Uuid) -> Result<Vec<Node>>;
    async fn get_edges_for_node(&self, node_id: Uuid) -> Result<Vec<Hyperedge>>;
    async fn semantic_search(
        &self,
        query_embedding: Vec<f32>,
        limit: usize,
        threshold: f32,
    ) -> Result<Vec<(Node, f32)>>;

    // ===== saúde =====
    async fn health_check(&self) -> Result<HealthStatus>;
}

// Futuras implementações:
// pub mod in_memory;
// pub use in_memory::InMemoryStorage;
