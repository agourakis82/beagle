//! Abstrações polimórficas para operações de armazenamento, travessia e consulta
//! sobre o hipergrafo Beagle.
//!
//! Este módulo define traits assíncronos que separam o domínio cognitivo das
//! infraestruturas subjacentes (PostgreSQL, Redis, camadas em memória e caches
//! híbridos), habilitando composição e testabilidade.

use std::collections::HashMap;

use async_trait::async_trait;
use chrono::{DateTime, Utc};
use uuid::Uuid;

use crate::{
    error::HypergraphError,
    models::{ContentType, Hyperedge, Node},
};

/// Métricas agregadas de armazenamento para observabilidade e tuning.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct StorageMetrics {
    /// Total de nós ativos.
    pub total_nodes: usize,
    /// Total de hiperedges ativos.
    pub total_hyperedges: usize,
    /// Quantidade de dispositivos ativos no cluster.
    pub active_devices: usize,
    /// Tamanho aproximado do backend em bytes (quando disponível).
    pub storage_size_bytes: Option<u64>,
}

impl StorageMetrics {
    /// Cria métricas com valores iniciais.
    pub fn new(
        total_nodes: usize,
        total_hyperedges: usize,
        active_devices: usize,
        storage_size_bytes: Option<u64>,
    ) -> Self {
        Self {
            total_nodes,
            total_hyperedges,
            active_devices,
            storage_size_bytes,
        }
    }
}

/// Trait para backends de armazenamento do hipergrafo.
///
/// Abstrai implementações heterogêneas (PostgreSQL, Redis, memória, etc.)
/// utilizando interface assíncrona compatível com operações I/O-bound.
///
/// # Exemplo: Implementando `HypergraphStorage`
///
/// ```no_run
/// use std::collections::HashMap;
/// use std::sync::Arc;
///
/// use async_trait::async_trait;
/// use tokio::sync::RwLock;
/// use uuid::Uuid;
///
/// use beagle_hypergraph::{
///     error::HypergraphError,
///     models::Node,
///     traits::{HypergraphStorage, StorageMetrics},
/// };
///
/// struct InMemoryStorage {
///     nodes: Arc<RwLock<HashMap<Uuid, Node>>>,
/// }
///
/// impl InMemoryStorage {
///     fn new() -> Self {
///         Self {
///             nodes: Arc::new(RwLock::new(HashMap::new())),
///         }
///     }
/// }
///
/// #[async_trait]
/// impl HypergraphStorage for InMemoryStorage {
///     async fn create_node(&self, node: &Node) -> Result<Uuid, HypergraphError> {
///         let mut nodes = self.nodes.write().await;
///         nodes.insert(node.id, node.clone());
///         Ok(node.id)
///     }
///
///     async fn get_node(&self, id: Uuid) -> Result<Option<Node>, HypergraphError> {
///         let nodes = self.nodes.read().await;
///         Ok(nodes.get(&id).cloned())
///     }
///
///     async fn update_node(&self, node: &Node) -> Result<(), HypergraphError> {
///         let mut nodes = self.nodes.write().await;
///         nodes.insert(node.id, node.clone());
///         Ok(())
///     }
///
///     async fn delete_node(&self, id: Uuid) -> Result<(), HypergraphError> {
///         let mut nodes = self.nodes.write().await;
///         nodes.remove(&id);
///         Ok(())
///     }
///
///     async fn get_nodes_by_device(
///         &self,
///         device_id: &str,
///     ) -> Result<Vec<Node>, HypergraphError> {
///         let nodes = self.nodes.read().await;
///         Ok(nodes
///             .values()
///             .filter(|node| node.device_id == device_id)
///             .cloned()
///             .collect())
///     }
///
///     async fn create_nodes_batch(
///         &self,
///         nodes: &[Node],
///     ) -> Result<Vec<Uuid>, HypergraphError> {
///         let mut lock = self.nodes.write().await;
///         for node in nodes {
///             lock.insert(node.id, node.clone());
///         }
///         Ok(nodes.iter().map(|node| node.id).collect())
///     }
///
///     async fn create_hyperedge(
///         &self,
///         _edge: &beagle_hypergraph::models::Hyperedge,
///     ) -> Result<Uuid, HypergraphError> {
///         unimplemented!("Hyperedge support not implemented no exemplo");
///     }
///
///     // ... demais métodos omitidos
///
///     async fn health_check(&self) -> Result<bool, HypergraphError> {
///         Ok(true)
///     }
///
///     async fn get_metrics(&self) -> Result<StorageMetrics, HypergraphError> {
///         Ok(StorageMetrics::new(0, 0, 0, None))
///     }
/// }
/// ```
#[async_trait]
pub trait HypergraphStorage: Send + Sync {
    // ====== OPERAÇÕES COM NÓS ======

    /// Cria um novo nó no backend.
    async fn create_node(&self, node: &Node) -> Result<Uuid, HypergraphError>;

    /// Recupera um nó pelo identificador.
    async fn get_node(&self, id: Uuid) -> Result<Option<Node>, HypergraphError>;

    /// Atualiza o nó existente.
    async fn update_node(&self, node: &Node) -> Result<(), HypergraphError>;

    /// Marca o nó como deletado logicamente.
    async fn delete_node(&self, id: Uuid) -> Result<(), HypergraphError>;

    /// Lista nós associados a um dispositivo.
    async fn get_nodes_by_device(&self, device_id: &str) -> Result<Vec<Node>, HypergraphError>;

    /// Cria múltiplos nós de forma otimizada.
    async fn create_nodes_batch(&self, nodes: &[Node]) -> Result<Vec<Uuid>, HypergraphError>;

    // ====== OPERAÇÕES COM HIPEREDGES ======

    /// Cria novo hiperedge no backend.
    async fn create_hyperedge(&self, edge: &Hyperedge) -> Result<Uuid, HypergraphError>;

    /// Recupera hiperedge pelo identificador.
    async fn get_hyperedge(&self, id: Uuid) -> Result<Option<Hyperedge>, HypergraphError>;

    /// Recupera hiperedges que conectam o nó informado.
    async fn get_hyperedges_for_node(
        &self,
        node_id: Uuid,
    ) -> Result<Vec<Hyperedge>, HypergraphError>;

    /// Remove hiperedge.
    async fn delete_hyperedge(&self, id: Uuid) -> Result<(), HypergraphError>;

    // ====== CONSULTAS / BUSCAS ======

    /// Pesquisa nós por conteúdo textual (full-text).
    async fn search_nodes(&self, query: &str, limit: usize) -> Result<Vec<Node>, HypergraphError>;

    /// Recupera nós por tipo semântico.
    async fn get_nodes_by_type(
        &self,
        content_type: ContentType,
        limit: usize,
    ) -> Result<Vec<Node>, HypergraphError>;

    /// Busca semântica por similaridade vetorial.
    async fn semantic_search(
        &self,
        embedding: &[f32],
        limit: usize,
        threshold: f32,
    ) -> Result<Vec<(Node, f32)>, HypergraphError>;

    // ====== SAÚDE & MÉTRICAS ======

    /// Verifica saúde do backend.
    async fn health_check(&self) -> Result<bool, HypergraphError>;

    /// Recupera métricas agregadas.
    async fn get_metrics(&self) -> Result<StorageMetrics, HypergraphError>;
}

/// Trait para operações de travessia em grafos.
///
/// Permite implementar diferentes estratégias (BFS, DFS, heurísticas híbridas).
#[async_trait]
pub trait Traversable: Send + Sync {
    /// Recupera a vizinhança imediata de um nó.
    async fn get_neighbors(&self, node_id: Uuid) -> Result<Vec<Node>, HypergraphError>;

    /// Recupera vizinhanças até profundidade `max_depth`.
    ///
    /// Retorna um mapa profundidade → nós nessa camada.
    async fn get_neighborhood(
        &self,
        node_id: Uuid,
        max_depth: usize,
    ) -> Result<HashMap<usize, Vec<Node>>, HypergraphError>;

    /// Encontra caminho mais curto entre dois nós (caso exista).
    async fn shortest_path(
        &self,
        start: Uuid,
        end: Uuid,
    ) -> Result<Option<Vec<Node>>, HypergraphError>;

    /// Encontra múltiplos caminhos entre nós, limitado por `max_paths`.
    async fn find_paths(
        &self,
        start: Uuid,
        end: Uuid,
        max_paths: usize,
    ) -> Result<Vec<Vec<Node>>, HypergraphError>;

    /// Recupera o componente conectado que contém o nó.
    async fn connected_component(&self, node_id: Uuid) -> Result<Vec<Node>, HypergraphError>;
}

/// Trait para consultas complexas sobre o hipergrafo.
#[async_trait]
pub trait Queryable: Send + Sync {
    /// Consulta nós com base em predicado arbitrário.
    async fn query_nodes(
        &self,
        predicate: &(dyn Fn(&Node) -> bool + Send + Sync),
        limit: usize,
    ) -> Result<Vec<Node>, HypergraphError>
    where
        Self: Sized;

    /// Recupera nós criados dentro de um intervalo temporal.
    async fn get_nodes_in_range(
        &self,
        start: DateTime<Utc>,
        end: DateTime<Utc>,
    ) -> Result<Vec<Node>, HypergraphError>;

    /// Obtém nós mais conectados por contagem de hiperedges.
    async fn get_most_connected_nodes(
        &self,
        limit: usize,
    ) -> Result<Vec<(Node, usize)>, HypergraphError>;

    /// Recupera nós órfãos (sem hiperedge associado).
    async fn get_orphan_nodes(&self) -> Result<Vec<Node>, HypergraphError>;

    /// Recupera hiperedges que conectam os nós informados.
    async fn get_hyperedges_between(
        &self,
        node_ids: &[Uuid],
    ) -> Result<Vec<Hyperedge>, HypergraphError>;

    /// Agrega estatísticas por `ContentType`.
    async fn aggregate_by_type(&self) -> Result<HashMap<ContentType, usize>, HypergraphError>;
}

/// Trait para estratégias de cache.
#[async_trait]
pub trait Cacheable: Send + Sync {
    /// Recupera nó do cache (ou storage) de forma transparente.
    async fn get_cached_node(&self, id: Uuid) -> Result<Option<Node>, HypergraphError>;

    /// Invalida item do cache.
    async fn invalidate_cache(&self, id: Uuid) -> Result<(), HypergraphError>;

    /// Realiza aquecimento de cache com nós frequentes.
    async fn warm_cache(&self, node_ids: &[Uuid]) -> Result<usize, HypergraphError>;

    /// Limpa completamente o cache.
    async fn clear_cache(&self) -> Result<(), HypergraphError>;
}

/// Trait para operações transacionais (garantias ACID).
#[async_trait]
pub trait Transactional: Send + Sync {
    /// Inicia transação.
    async fn begin_transaction(&self) -> Result<TransactionId, HypergraphError>;

    /// Comita transação.
    async fn commit(&self, tx_id: TransactionId) -> Result<(), HypergraphError>;

    /// Realiza rollback.
    async fn rollback(&self, tx_id: TransactionId) -> Result<(), HypergraphError>;

    /// Executa closure dentro de transação (auto commit/rollback).
    async fn with_transaction<F, T>(&self, f: F) -> Result<T, HypergraphError>
    where
        F: FnOnce(TransactionId) -> Result<T, HypergraphError> + Send,
        T: Send,
        Self: Sized;
}

/// Identificador opaco de transação.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
pub struct TransactionId(Uuid);

impl TransactionId {
    /// Cria novo identificador randômico.
    pub fn new() -> Self {
        Self(Uuid::new_v4())
    }

    /// Acessa o UUID subjacente.
    pub fn as_uuid(self) -> Uuid {
        self.0
    }
}

impl From<Uuid> for TransactionId {
    fn from(value: Uuid) -> Self {
        Self(value)
    }
}

impl From<TransactionId> for Uuid {
    fn from(value: TransactionId) -> Self {
        value.0
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::sync::Arc;

    struct MockStorage;

    #[async_trait]
    impl HypergraphStorage for MockStorage {
        async fn create_node(&self, node: &Node) -> Result<Uuid, HypergraphError> {
            Ok(node.id)
        }

        async fn get_node(&self, _id: Uuid) -> Result<Option<Node>, HypergraphError> {
            Ok(None)
        }

        async fn update_node(&self, _node: &Node) -> Result<(), HypergraphError> {
            Ok(())
        }

        async fn delete_node(&self, _id: Uuid) -> Result<(), HypergraphError> {
            Ok(())
        }

        async fn get_nodes_by_device(
            &self,
            _device_id: &str,
        ) -> Result<Vec<Node>, HypergraphError> {
            Ok(Vec::new())
        }

        async fn create_nodes_batch(&self, nodes: &[Node]) -> Result<Vec<Uuid>, HypergraphError> {
            Ok(nodes.iter().map(|node| node.id).collect())
        }

        async fn create_hyperedge(&self, edge: &Hyperedge) -> Result<Uuid, HypergraphError> {
            Ok(edge.id)
        }

        async fn get_hyperedge(&self, _id: Uuid) -> Result<Option<Hyperedge>, HypergraphError> {
            Ok(None)
        }

        async fn get_hyperedges_for_node(
            &self,
            _node_id: Uuid,
        ) -> Result<Vec<Hyperedge>, HypergraphError> {
            Ok(Vec::new())
        }

        async fn delete_hyperedge(&self, _id: Uuid) -> Result<(), HypergraphError> {
            Ok(())
        }

        async fn search_nodes(
            &self,
            _query: &str,
            _limit: usize,
        ) -> Result<Vec<Node>, HypergraphError> {
            Ok(Vec::new())
        }

        async fn get_nodes_by_type(
            &self,
            _content_type: ContentType,
            _limit: usize,
        ) -> Result<Vec<Node>, HypergraphError> {
            Ok(Vec::new())
        }

        async fn semantic_search(
            &self,
            _embedding: &[f32],
            _limit: usize,
            _threshold: f32,
        ) -> Result<Vec<(Node, f32)>, HypergraphError> {
            Ok(Vec::new())
        }

        async fn health_check(&self) -> Result<bool, HypergraphError> {
            Ok(true)
        }

        async fn get_metrics(&self) -> Result<StorageMetrics, HypergraphError> {
            Ok(StorageMetrics::new(0, 0, 0, None))
        }
    }

    #[tokio::test]
    async fn test_trait_object() {
        let storage: Arc<dyn HypergraphStorage> = Arc::new(MockStorage);
        let result = storage.health_check().await;
        assert!(result.is_ok());
        assert_eq!(result.unwrap(), true);
    }
}
