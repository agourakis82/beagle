//! Abstrações de persistência para o hipergrafo Beagle.

use async_trait::async_trait;
use chrono::{DateTime, Utc};
use uuid::Uuid;

use crate::{
    error::Result,
    models::{ContentType, Hyperedge, Node},
};

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
#[async_trait]
pub trait HypergraphStorage: Send + Sync {
    /// Persiste um novo [`Node`] mantendo validações e invariantes.
    ///
    /// # Parameters
    /// - `node`: estrutura já validada a ser inserida.
    ///
    /// # Returns
    /// Novo nó persistido (com eventuais ajustes de backend).
    ///
    /// # Errors
    /// - [`HypergraphError::ValidationError`](crate::error::HypergraphError::ValidationError): invariantes violadas.
    /// - [`HypergraphError::DatabaseError`](crate::error::HypergraphError::DatabaseError): falhas de infraestrutura.
    /// - [`HypergraphError::VersionConflict`](crate::error::HypergraphError::VersionConflict): inconsistência detectada.
    ///
    /// # Examples
    /// ```
    /// # use beagle_hypergraph::storage::{HypergraphStorage, NodeFilters};
    /// # async fn demo<S: HypergraphStorage>(storage: &S) -> beagle_hypergraph::error::Result<()> {
    /// use beagle_hypergraph::models::{Node, ContentType};
    /// let node = Node::new("Insight", ContentType::Thought, "device-alpha")?;
    /// let persisted = storage.create_node(node).await?;
    /// # Ok(())
    /// # }
    /// ```
    async fn create_node(&self, node: Node) -> Result<Node>;

    /// Recupera um [`Node`] pelo identificador global.
    ///
    /// # Parameters
    /// - `id`: identificador do nó.
    ///
    /// # Returns
    /// Nó correspondente, caso exista.
    ///
    /// # Errors
    /// - [`HypergraphError::NodeNotFound`](crate::error::HypergraphError::NodeNotFound): quando ausente.
    /// - [`HypergraphError::InvalidUuid`](crate::error::HypergraphError::InvalidUuid): UUID inválido.
    /// - [`HypergraphError::DatabaseError`](crate::error::HypergraphError::DatabaseError): erros de backend.
    async fn get_node(&self, id: Uuid) -> Result<Node>;

    /// Atualiza um [`Node`] existente garantindo controle de versão.
    ///
    /// # Parameters
    /// - `node`: entidade com novas informações e versão.
    ///
    /// # Returns
    /// Instância atualizada a partir da persistência.
    ///
    /// # Errors
    /// - [`HypergraphError::NodeNotFound`](crate::error::HypergraphError::NodeNotFound)
    /// - [`HypergraphError::ValidationError`](crate::error::HypergraphError::ValidationError)
    /// - [`HypergraphError::VersionConflict`](crate::error::HypergraphError::VersionConflict)
    /// - [`HypergraphError::DatabaseError`](crate::error::HypergraphError::DatabaseError)
    async fn update_node(&self, node: Node) -> Result<Node>;

    /// Marca um [`Node`] como removido logicamente ou o elimina fisicamente.
    ///
    /// # Parameters
    /// - `id`: identificador a ser removido.
    ///
    /// # Returns
    /// Unidade em caso de sucesso.
    ///
    /// # Errors
    /// - [`HypergraphError::NodeNotFound`](crate::error::HypergraphError::NodeNotFound)
    /// - [`HypergraphError::DatabaseError`](crate::error::HypergraphError::DatabaseError)
    async fn delete_node(&self, id: Uuid) -> Result<()>;

    /// Lista [`Node`]s segundo filtros opcionais.
    ///
    /// # Parameters
    /// - `filters`: filtro composto opcional (ver [`NodeFilters`]).
    ///
    /// # Returns
    /// Coleção de nós correspondentes.
    ///
    /// # Errors
    /// - [`HypergraphError::DatabaseError`](crate::error::HypergraphError::DatabaseError)
    /// - [`HypergraphError::ValidationError`](crate::error::HypergraphError::ValidationError)
    async fn list_nodes(&self, filters: Option<NodeFilters>) -> Result<Vec<Node>>;

    /// Recupera múltiplos [`Node`]s por lote utilizando uma lista de UUIDs.
    ///
    /// # Parameters
    /// - `ids`: coleção de identificadores.
    ///
    /// # Returns
    /// Nós encontrados (pode ser subconjunto dos solicitados).
    ///
    /// # Errors
    /// - [`HypergraphError::DatabaseError`](crate::error::HypergraphError::DatabaseError)
    async fn batch_get_nodes(&self, ids: Vec<Uuid>) -> Result<Vec<Node>>;

    /// Cria um novo [`Hyperedge`] com validação de invariantes.
    ///
    /// # Parameters
    /// - `edge`: hiperedge preparado para inserção.
    ///
    /// # Returns
    /// Hiperedge persistido.
    ///
    /// # Errors
    /// - [`HypergraphError::ValidationError`](crate::error::HypergraphError::ValidationError)
    /// - [`HypergraphError::DatabaseError`](crate::error::HypergraphError::DatabaseError)
    async fn create_hyperedge(&self, edge: Hyperedge) -> Result<Hyperedge>;

    /// Recupera um [`Hyperedge`] pelo identificador.
    ///
    /// # Parameters
    /// - `id`: UUID do hiperedge.
    ///
    /// # Returns
    /// Hiperedge correspondente.
    ///
    /// # Errors
    /// - [`HypergraphError::HyperedgeNotFound`](crate::error::HypergraphError::HyperedgeNotFound)
    /// - [`HypergraphError::DatabaseError`](crate::error::HypergraphError::DatabaseError)
    async fn get_hyperedge(&self, id: Uuid) -> Result<Hyperedge>;

    /// Atualiza um [`Hyperedge`] existente garantindo integridade da relação.
    ///
    /// # Parameters
    /// - `edge`: entidade com alterações.
    ///
    /// # Returns
    /// Versão atualizada do hiperedge.
    ///
    /// # Errors
    /// - [`HypergraphError::HyperedgeNotFound`](crate::error::HypergraphError::HyperedgeNotFound)
    /// - [`HypergraphError::ValidationError`](crate::error::HypergraphError::ValidationError)
    /// - [`HypergraphError::VersionConflict`](crate::error::HypergraphError::VersionConflict)
    async fn update_hyperedge(&self, edge: Hyperedge) -> Result<Hyperedge>;

    /// Remove logicamente ou fisicamente um [`Hyperedge`].
    ///
    /// # Parameters
    /// - `id`: UUID do hiperedge.
    ///
    /// # Returns
    /// Unidade em caso de sucesso.
    ///
    /// # Errors
    /// - [`HypergraphError::HyperedgeNotFound`](crate::error::HypergraphError::HyperedgeNotFound)
    /// - [`HypergraphError::DatabaseError`](crate::error::HypergraphError::DatabaseError)
    async fn delete_hyperedge(&self, id: Uuid) -> Result<()>;

    /// Lista hiperedges, opcionalmente filtrando por nó relacionado.
    ///
    /// # Parameters
    /// - `node_id`: se fornecido, retorna apenas hiperedges conectados ao nó.
    ///
    /// # Returns
    /// Coleção de hiperedges compatíveis.
    ///
    /// # Errors
    /// - [`HypergraphError::DatabaseError`](crate::error::HypergraphError::DatabaseError)
    async fn list_hyperedges(&self, node_id: Option<Uuid>) -> Result<Vec<Hyperedge>>;

    /// Consulta vizinhança de um nó por busca em largura até profundidade fixada.
    ///
    /// # Parameters
    /// - `start_node`: nó inicial da travessia.
    /// - `depth`: profundidade máxima.
    ///
    /// # Returns
    /// Vetor de pares `(Node, distância)`.
    ///
    /// # Errors
    /// - [`HypergraphError::NodeNotFound`](crate::error::HypergraphError::NodeNotFound)
    /// - [`HypergraphError::DatabaseError`](crate::error::HypergraphError::DatabaseError)
    async fn query_neighborhood(&self, start_node: Uuid, depth: i32) -> Result<Vec<(Node, i32)>>;

    /// Obtém nós conectados a um hiperedge específico.
    ///
    /// # Parameters
    /// - `edge_id`: identificador do hiperedge.
    ///
    /// # Returns
    /// Lista de [`Node`] conectados.
    ///
    /// # Errors
    /// - [`HypergraphError::HyperedgeNotFound`](crate::error::HypergraphError::HyperedgeNotFound)
    /// - [`HypergraphError::DatabaseError`](crate::error::HypergraphError::DatabaseError)
    async fn get_connected_nodes(&self, edge_id: Uuid) -> Result<Vec<Node>>;

    /// Recupera hiperedges associados a um nó específico.
    ///
    /// # Parameters
    /// - `node_id`: identificador do nó.
    ///
    /// # Returns
    /// Vetor de [`Hyperedge`].
    ///
    /// # Errors
    /// - [`HypergraphError::NodeNotFound`](crate::error::HypergraphError::NodeNotFound)
    /// - [`HypergraphError::DatabaseError`](crate::error::HypergraphError::DatabaseError)
    async fn get_edges_for_node(&self, node_id: Uuid) -> Result<Vec<Hyperedge>>;

    /// Executa busca semântica utilizando embeddings para ranqueamento.
    ///
    /// # Parameters
    /// - `query_embedding`: vetor de consulta.
    /// - `limit`: número máximo de resultados.
    /// - `threshold`: similaridade mínima.
    ///
    /// # Returns
    /// Lista de pares `(Node, score)` ordenados por relevância.
    ///
    /// # Errors
    /// - [`HypergraphError::DatabaseError`](crate::error::HypergraphError::DatabaseError)
    /// - [`HypergraphError::OperationNotPermitted`](crate::error::HypergraphError::OperationNotPermitted)
    async fn semantic_search(
        &self,
        query_embedding: Vec<f32>,
        limit: usize,
        threshold: f32,
    ) -> Result<Vec<(Node, f32)>>;

    /// Avalia a saúde do backend de armazenamento.
    ///
    /// # Returns
    /// Unidade quando o backend está operacional.
    ///
    /// # Errors
    /// - [`HypergraphError::DatabaseError`](crate::error::HypergraphError::DatabaseError)
    /// - [`HypergraphError::InternalError`](crate::error::HypergraphError::InternalError)
    async fn health_check(&self) -> Result<()>;
}

pub mod postgres;
pub use postgres::PostgresStorage;

// Futuras implementações:
// pub mod in_memory;
// pub use in_memory::InMemoryStorage;
