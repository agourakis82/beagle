use async_trait::async_trait;
use tracing::{debug, instrument};
use uuid::Uuid;

use super::{
    postgres::{HealthStatus, PoolConfig, PoolStats, PostgresStorage},
    NodeFilters, StorageRepository,
};
use crate::{
    cache::{CacheStats, RedisCache},
    error::{HypergraphError, Result},
    models::{Hyperedge, Node},
};

/// Implementação decoradora que aplica cache Redis sobre o backend PostgreSQL.
#[derive(Clone)]
pub struct CachedPostgresStorage {
    storage: PostgresStorage,
    cache: RedisCache,
}

impl CachedPostgresStorage {
    /// Inicializa uma nova instância com conexões para PostgreSQL e Redis.
    #[instrument(name = "cached_storage.new", skip(database_url, redis_url))]
    pub async fn new(database_url: &str, redis_url: &str) -> Result<Self> {
        let storage = PostgresStorage::new(database_url).await?;
        let cache = RedisCache::new(redis_url).await?;
        Ok(Self { storage, cache })
    }

    /// Inicializa com configuração explícita de pool e TTL customizado.
    #[instrument(
        name = "cached_storage.new_with_config",
        skip(database_url, redis_url, pool_config, ttl)
    )]
    pub async fn new_with_config(
        database_url: &str,
        redis_url: &str,
        pool_config: PoolConfig,
        ttl: std::time::Duration,
    ) -> Result<Self> {
        let storage = PostgresStorage::new_with_config(database_url, pool_config).await?;
        let cache = RedisCache::with_ttl(redis_url, ttl).await?;
        Ok(Self { storage, cache })
    }

    /// Retorna referência ao backend PostgreSQL.
    pub fn storage(&self) -> &PostgresStorage {
        &self.storage
    }

    /// Retorna referência ao adaptador de cache.
    pub fn cache(&self) -> &RedisCache {
        &self.cache
    }

    /// Estatísticas atuais do pool PostgreSQL.
    pub fn pool_stats(&self) -> PoolStats {
        self.storage.pool_stats()
    }

    /// Estatísticas do cache Redis.
    pub async fn cache_stats(&self) -> std::result::Result<CacheStats, HypergraphError> {
        self.cache.stats().await
    }

    /// Executa migrações pendentes do banco.
    pub async fn migrate(&self) -> Result<()> {
        self.storage.migrate().await
    }
}

#[async_trait]
impl StorageRepository for CachedPostgresStorage {
    #[instrument(name = "cached_storage.create_node", skip(self, node))]
    async fn create_node(&self, node: Node) -> Result<Node> {
        let created = self.storage.create_node(node).await?;

        if let Err(err) = self.cache.set(&created).await {
            debug!(error = %err, "Failed to cache newly created node");
        }

        Ok(created)
    }

    #[instrument(name = "cached_storage.get_node", skip(self), fields(node.id = %id))]
    async fn get_node(&self, id: Uuid) -> Result<Node> {
        if let Some(node) = self.cache.get(id).await? {
            debug!(node.id = %id, "Returned from cache");
            return Ok(node);
        }

        debug!(node.id = %id, "Cache miss, fetching from database");
        let node = self.storage.get_node(id).await?;

        if let Err(err) = self.cache.set(&node).await {
            debug!(error = %err, "Failed to cache node after DB fetch");
        }

        Ok(node)
    }

    #[instrument(name = "cached_storage.update_node", skip(self, node))]
    async fn update_node(&self, node: Node) -> Result<Node> {
        let updated = self.storage.update_node(node).await?;

        if let Err(err) = self.cache.set(&updated).await {
            debug!(error = %err, "Failed to refresh cache after update");
        }

        Ok(updated)
    }

    #[instrument(name = "cached_storage.delete_node", skip(self), fields(node.id = %id))]
    async fn delete_node(&self, id: Uuid) -> Result<()> {
        self.storage.delete_node(id).await?;

        if let Err(err) = self.cache.invalidate(id).await {
            debug!(error = %err, "Failed to invalidate cache entry");
        }

        Ok(())
    }

    async fn list_nodes(&self, filters: Option<NodeFilters>) -> Result<Vec<Node>> {
        self.storage.list_nodes(filters).await
    }

    async fn batch_get_nodes(&self, ids: Vec<Uuid>) -> Result<Vec<Node>> {
        let nodes = self.storage.batch_get_nodes(ids).await?;

        if !nodes.is_empty() {
            if let Err(err) = self.cache.warm_cache(nodes.as_slice()).await {
                debug!(error = %err, "Failed to warm cache from batch_get_nodes");
            }
        }

        Ok(nodes)
    }

    async fn create_hyperedge(&self, edge: Hyperedge) -> Result<Hyperedge> {
        self.storage.create_hyperedge(edge).await
    }

    async fn get_hyperedge(&self, id: Uuid) -> Result<Hyperedge> {
        self.storage.get_hyperedge(id).await
    }

    async fn update_hyperedge(&self, edge: Hyperedge) -> Result<Hyperedge> {
        self.storage.update_hyperedge(edge).await
    }

    async fn delete_hyperedge(&self, id: Uuid) -> Result<()> {
        self.storage.delete_hyperedge(id).await
    }

    async fn list_hyperedges(&self, node_id: Option<Uuid>) -> Result<Vec<Hyperedge>> {
        self.storage.list_hyperedges(node_id).await
    }

    async fn query_neighborhood(&self, start_node: Uuid, depth: i32) -> Result<Vec<(Node, i32)>> {
        self.storage.query_neighborhood(start_node, depth).await
    }

    async fn get_connected_nodes(&self, edge_id: Uuid) -> Result<Vec<Node>> {
        self.storage.get_connected_nodes(edge_id).await
    }

    async fn get_edges_for_node(&self, node_id: Uuid) -> Result<Vec<Hyperedge>> {
        self.storage.get_edges_for_node(node_id).await
    }

    async fn semantic_search(
        &self,
        query_embedding: Vec<f32>,
        limit: usize,
        threshold: f32,
    ) -> Result<Vec<(Node, f32)>> {
        self.storage
            .semantic_search(query_embedding, limit, threshold)
            .await
    }

    async fn health_check(&self) -> Result<HealthStatus> {
        self.storage.health_check().await
    }
}
