use crate::{error::HypergraphError, models::Node};

use redis::{aio::ConnectionManager, AsyncCommands, Client};
use std::time::Duration;
use tracing::{debug, info, instrument, warn};
use uuid::Uuid;

/// Adaptador de cache para nós quentes utilizando Redis com políticas LRU.
#[derive(Clone)]
pub struct RedisCache {
    connection: ConnectionManager,
    ttl: Duration,
    key_prefix: String,
}

impl RedisCache {
    /// Constrói uma nova instância de cache com TTL padrão de 5 minutos.
    #[instrument(name = "redis.new", skip(redis_url))]
    pub async fn new(redis_url: &str) -> Result<Self, HypergraphError> {
        info!(redis_url = redis_url, "Estabelecendo conexão com Redis");

        let client = Client::open(redis_url)
            .map_err(|e| HypergraphError::CacheError(format!("Redis client error: {e}")))?;

        let connection = ConnectionManager::new(client)
            .await
            .map_err(|e| HypergraphError::CacheError(format!("Redis connection error: {e}")))?;

        Ok(Self {
            connection,
            ttl: Duration::from_secs(300),
            key_prefix: "beagle:node:".to_string(),
        })
    }

    /// Variante auxiliar que permite personalizar o TTL.
    pub async fn with_ttl(redis_url: &str, ttl: Duration) -> Result<Self, HypergraphError> {
        let mut cache = Self::new(redis_url).await?;
        cache.ttl = ttl;
        Ok(cache)
    }

    /// Retorna a chave Redis padronizada para um nó específico.
    fn cache_key(&self, node_id: Uuid) -> String {
        format!("{}{}", self.key_prefix, node_id)
    }

    /// Obtém um nó do cache, se disponível.
    #[instrument(name = "redis.get", skip(self), fields(node.id = %node_id))]
    pub async fn get(&self, node_id: Uuid) -> Result<Option<Node>, HypergraphError> {
        let key = self.cache_key(node_id);
        let mut conn = self.connection.clone();

        let result: Option<String> = conn
            .get(&key)
            .await
            .map_err(|e| HypergraphError::CacheError(format!("Redis GET error: {e}")))?;

        match result {
            Some(json) => {
                debug!(node.id = %node_id, "Cache hit");
                let node: Node =
                    serde_json::from_str(&json).map_err(HypergraphError::SerializationError)?;
                Ok(Some(node))
            }
            None => {
                debug!(node.id = %node_id, "Cache miss");
                Ok(None)
            }
        }
    }

    /// Persiste um nó no cache com TTL.
    #[instrument(name = "redis.set", skip(self, node), fields(node.id = %node.id))]
    pub async fn set(&self, node: &Node) -> Result<(), HypergraphError> {
        let key = self.cache_key(node.id);
        let json = serde_json::to_string(node).map_err(HypergraphError::SerializationError)?;

        let mut conn = self.connection.clone();
        let ttl_secs: u64 = self.ttl.as_secs();
        conn.set_ex::<_, _, ()>(&key, json, ttl_secs)
            .await
            .map_err(|e| HypergraphError::CacheError(format!("Redis SET error: {e}")))?;

        debug!(
            node.id = %node.id,
            ttl_secs = self.ttl.as_secs(),
            "Node cached"
        );
        Ok(())
    }

    /// Remove explicitamente um nó do cache.
    #[instrument(name = "redis.invalidate", skip(self), fields(node.id = %node_id))]
    pub async fn invalidate(&self, node_id: Uuid) -> Result<(), HypergraphError> {
        let key = self.cache_key(node_id);
        let mut conn = self.connection.clone();

        let deleted: i32 = conn
            .del(&key)
            .await
            .map_err(|e| HypergraphError::CacheError(format!("Redis DEL error: {e}")))?;

        if deleted > 0 {
            debug!(node.id = %node_id, "Cache invalidated");
        }

        Ok(())
    }

    /// Invalida múltiplas chaves como operação de lote.
    #[instrument(name = "redis.invalidate_batch", skip(self, node_ids))]
    pub async fn invalidate_batch(&self, node_ids: &[Uuid]) -> Result<(), HypergraphError> {
        if node_ids.is_empty() {
            return Ok(());
        }

        let keys: Vec<String> = node_ids.iter().map(|id| self.cache_key(*id)).collect();

        let mut conn = self.connection.clone();
        let deleted: i32 = conn
            .del(&keys)
            .await
            .map_err(|e| HypergraphError::CacheError(format!("Redis batch DEL error: {e}")))?;

        debug!(count = deleted, "Batch cache invalidation completed");
        Ok(())
    }

    /// Pré-carrega o cache com uma coleção de nós.
    #[instrument(name = "redis.warm", skip(self, nodes))]
    pub async fn warm_cache(&self, nodes: &[Node]) -> Result<usize, HypergraphError> {
        let mut cached = 0usize;

        for node in nodes {
            if let Ok(()) = self.set(node).await {
                cached += 1;
            }
        }

        info!(nodes_cached = cached, total = nodes.len(), "Cache warmed");
        Ok(cached)
    }

    /// Limpa o database corrente do Redis (cautela).
    #[instrument(name = "redis.flush", skip(self))]
    pub async fn flush_all(&self) -> Result<(), HypergraphError> {
        warn!("Flushing entire cache");
        let mut conn = self.connection.clone();

        redis::cmd("FLUSHDB")
            .query_async::<_, ()>(&mut conn)
            .await
            .map_err(|e| HypergraphError::CacheError(format!("Redis FLUSHDB error: {e}")))?;

        Ok(())
    }

    /// Recupera estatísticas agregadas do Redis.
    pub async fn stats(&self) -> Result<CacheStats, HypergraphError> {
        let mut conn = self.connection.clone();

        let info: String = redis::cmd("INFO")
            .arg("stats")
            .query_async(&mut conn)
            .await
            .map_err(|e| HypergraphError::CacheError(format!("Redis INFO error: {e}")))?;

        let hits = Self::parse_stat(&info, "keyspace_hits").unwrap_or(0);
        let misses = Self::parse_stat(&info, "keyspace_misses").unwrap_or(0);
        let evictions = Self::parse_stat(&info, "evicted_keys").unwrap_or(0);

        let hit_rate = if hits + misses > 0 {
            (hits as f64 / (hits + misses) as f64) * 100.0
        } else {
            0.0
        };

        Ok(CacheStats {
            hits,
            misses,
            hit_rate,
            evictions,
        })
    }

    /// Parser simplificado para o payload retornado por `INFO`.
    fn parse_stat(info: &str, key: &str) -> Option<u64> {
        info.lines()
            .find(|line| line.starts_with(key))
            .and_then(|line| line.split(':').nth(1))
            .and_then(|value| value.trim().parse().ok())
    }
}

/// Estrutura consolidando métricas principais do cache.
#[derive(Debug, Clone)]
pub struct CacheStats {
    pub hits: u64,
    pub misses: u64,
    pub hit_rate: f64,
    pub evictions: u64,
}
