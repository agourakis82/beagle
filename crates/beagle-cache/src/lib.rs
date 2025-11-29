//! Distributed Cache with Redis - Q1 SOTA Implementation
//!
//! Implements a comprehensive distributed caching system with:
//! - Multi-tier caching (L1: in-memory, L2: Redis, L3: disk)
//! - Consistent hashing for distribution
//! - Cache invalidation strategies
//! - TTL and LRU eviction policies
//! - Bloom filters for existence checks
//! - Write-through and write-behind patterns
//!
//! References:
//! - Fitzpatrick, B. (2004). "Distributed caching with memcached."
//! - Nishtala, R., et al. (2013). "Scaling Memcache at Facebook." NSDI.
//! - Lim, H., et al. (2014). "MICA: A Holistic Approach to Fast In-Memory Key-Value Storage." NSDI.
//! - Fan, B., et al. (2000). "Summary cache: a scalable wide-area web cache sharing protocol."

use anyhow::{Result, Context};
use async_trait::async_trait;
use bloomfilter::Bloom;
use chrono::{DateTime, Duration, Utc};
use redis::{aio::ConnectionManager, AsyncCommands, RedisResult};
use serde::{Deserialize, Serialize, de::DeserializeOwned};
use sha2::{Sha256, Digest};
use std::collections::{HashMap, VecDeque};
use std::hash::{Hash, Hasher};
use std::sync::Arc;
use std::time::Instant;
use tokio::sync::{RwLock, Mutex};
use tracing::{debug, info, warn, error, instrument};

/// Cache configuration
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct CacheConfig {
    /// Redis connection URL
    pub redis_url: String,

    /// L1 cache size (in-memory, number of entries)
    pub l1_max_entries: usize,

    /// L2 cache TTL (Redis, seconds)
    pub l2_ttl_seconds: u64,

    /// L3 cache directory (disk)
    pub l3_directory: Option<String>,

    /// Enable bloom filter for existence checks
    pub enable_bloom_filter: bool,

    /// Bloom filter capacity
    pub bloom_capacity: usize,

    /// Bloom filter false positive rate
    pub bloom_fp_rate: f64,

    /// Enable consistent hashing for distribution
    pub enable_consistent_hashing: bool,

    /// Number of virtual nodes for consistent hashing
    pub virtual_nodes: usize,

    /// Write strategy
    pub write_strategy: WriteStrategy,

    /// Eviction policy
    pub eviction_policy: EvictionPolicy,

    /// Enable compression for large values
    pub enable_compression: bool,

    /// Compression threshold (bytes)
    pub compression_threshold: usize,

    /// Enable metrics collection
    pub enable_metrics: bool,
}

impl Default for CacheConfig {
    fn default() -> Self {
        Self {
            redis_url: std::env::var("REDIS_URL")
                .unwrap_or_else(|_| "redis://localhost:6379".to_string()),
            l1_max_entries: 10000,
            l2_ttl_seconds: 3600, // 1 hour
            l3_directory: Some(
                std::env::var("BEAGLE_DATA_DIR")
                    .map(|d| format!("{}/cache", d))
                    .unwrap_or_else(|_| "/tmp/beagle_cache".to_string())
            ),
            enable_bloom_filter: true,
            bloom_capacity: 1_000_000,
            bloom_fp_rate: 0.01,
            enable_consistent_hashing: true,
            virtual_nodes: 150,
            write_strategy: WriteStrategy::WriteThrough,
            eviction_policy: EvictionPolicy::LRU,
            enable_compression: true,
            compression_threshold: 1024, // 1KB
            enable_metrics: true,
        }
    }
}

/// Write strategy for cache updates
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
pub enum WriteStrategy {
    /// Write to cache and backing store synchronously
    WriteThrough,
    /// Write to cache immediately, backing store asynchronously
    WriteBehind,
    /// Write only to backing store, invalidate cache
    WriteAround,
}

/// Cache eviction policy
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
pub enum EvictionPolicy {
    /// Least Recently Used
    LRU,
    /// Least Frequently Used
    LFU,
    /// First In First Out
    FIFO,
    /// Random Replacement
    Random,
    /// Adaptive Replacement Cache
    ARC,
}

/// Cache entry with metadata
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct CacheEntry<T> {
    pub value: T,
    pub created_at: DateTime<Utc>,
    pub accessed_at: DateTime<Utc>,
    pub access_count: u64,
    pub ttl: Option<Duration>,
    pub compressed: bool,
}

impl<T> CacheEntry<T> {
    pub fn new(value: T, ttl: Option<Duration>) -> Self {
        let now = Utc::now();
        Self {
            value,
            created_at: now,
            accessed_at: now,
            access_count: 1,
            ttl,
            compressed: false,
        }
    }

    pub fn is_expired(&self) -> bool {
        if let Some(ttl) = self.ttl {
            Utc::now() > self.created_at + ttl
        } else {
            false
        }
    }

    pub fn touch(&mut self) {
        self.accessed_at = Utc::now();
        self.access_count += 1;
    }
}

/// L1 in-memory cache
struct L1Cache<K, V>
where
    K: Eq + Hash + Clone,
    V: Clone,
{
    entries: HashMap<K, CacheEntry<V>>,
    access_order: VecDeque<K>,
    max_entries: usize,
    eviction_policy: EvictionPolicy,
}

impl<K, V> L1Cache<K, V>
where
    K: Eq + Hash + Clone,
    V: Clone,
{
    fn new(max_entries: usize, eviction_policy: EvictionPolicy) -> Self {
        Self {
            entries: HashMap::new(),
            access_order: VecDeque::new(),
            max_entries,
            eviction_policy,
        }
    }

    fn get(&mut self, key: &K) -> Option<V> {
        if let Some(entry) = self.entries.get_mut(key) {
            if entry.is_expired() {
                self.remove(key);
                return None;
            }

            entry.touch();

            // Update access order for LRU
            if self.eviction_policy == EvictionPolicy::LRU {
                self.access_order.retain(|k| k != key);
                self.access_order.push_back(key.clone());
            }

            Some(entry.value.clone())
        } else {
            None
        }
    }

    fn put(&mut self, key: K, value: V, ttl: Option<Duration>) {
        // Check if we need to evict
        if self.entries.len() >= self.max_entries && !self.entries.contains_key(&key) {
            self.evict();
        }

        let entry = CacheEntry::new(value, ttl);
        self.entries.insert(key.clone(), entry);
        self.access_order.push_back(key);
    }

    fn remove(&mut self, key: &K) -> Option<V> {
        self.access_order.retain(|k| k != key);
        self.entries.remove(key).map(|e| e.value)
    }

    fn evict(&mut self) {
        let key_to_evict = match self.eviction_policy {
            EvictionPolicy::LRU => self.access_order.pop_front(),
            EvictionPolicy::FIFO => self.access_order.pop_front(),
            EvictionPolicy::Random => {
                let keys: Vec<K> = self.entries.keys().cloned().collect();
                if !keys.is_empty() {
                    Some(keys[rand::random::<usize>() % keys.len()].clone())
                } else {
                    None
                }
            }
            EvictionPolicy::LFU => {
                // Find least frequently used
                self.entries.iter()
                    .min_by_key(|(_, e)| e.access_count)
                    .map(|(k, _)| k.clone())
            }
            EvictionPolicy::ARC => {
                // Simplified ARC: combine recency and frequency
                self.entries.iter()
                    .min_by_key(|(_, e)| {
                        let recency_score = (Utc::now() - e.accessed_at).num_seconds();
                        let frequency_score = e.access_count as i64;
                        recency_score - frequency_score
                    })
                    .map(|(k, _)| k.clone())
            }
        };

        if let Some(key) = key_to_evict {
            self.remove(&key);
        }
    }

    fn clear(&mut self) {
        self.entries.clear();
        self.access_order.clear();
    }
}

/// Consistent hashing for distributed caching
struct ConsistentHash {
    ring: Vec<(u64, String)>,
    nodes: Vec<String>,
    virtual_nodes: usize,
}

impl ConsistentHash {
    fn new(nodes: Vec<String>, virtual_nodes: usize) -> Self {
        let mut hash = Self {
            ring: Vec::new(),
            nodes: nodes.clone(),
            virtual_nodes,
        };

        for node in &nodes {
            hash.add_node(node);
        }

        hash.ring.sort_by_key(|&(h, _)| h);
        hash
    }

    fn add_node(&mut self, node: &str) {
        for i in 0..self.virtual_nodes {
            let virtual_node = format!("{}:{}", node, i);
            let hash = self.hash_key(&virtual_node);
            self.ring.push((hash, node.to_string()));
        }
    }

    fn remove_node(&mut self, node: &str) {
        self.ring.retain(|(_, n)| n != node);
    }

    fn get_node(&self, key: &str) -> Option<String> {
        if self.ring.is_empty() {
            return None;
        }

        let hash = self.hash_key(key);

        // Binary search for the first node with hash >= key hash
        let idx = self.ring.binary_search_by_key(&hash, |&(h, _)| h)
            .unwrap_or_else(|i| i % self.ring.len());

        Some(self.ring[idx].1.clone())
    }

    fn hash_key(&self, key: &str) -> u64 {
        let mut hasher = std::collections::hash_map::DefaultHasher::new();
        key.hash(&mut hasher);
        hasher.finish()
    }
}

/// Distributed cache implementation
pub struct DistributedCache {
    config: CacheConfig,
    l1_cache: Arc<RwLock<L1Cache<String, Vec<u8>>>>,
    redis_conn: Arc<Mutex<ConnectionManager>>,
    bloom_filter: Arc<RwLock<Option<Bloom<String>>>>,
    consistent_hash: Arc<RwLock<Option<ConsistentHash>>>,
    metrics: Arc<RwLock<CacheMetrics>>,
}

/// Cache metrics for monitoring
#[derive(Debug, Clone, Default, Serialize, Deserialize)]
pub struct CacheMetrics {
    pub l1_hits: u64,
    pub l1_misses: u64,
    pub l2_hits: u64,
    pub l2_misses: u64,
    pub l3_hits: u64,
    pub l3_misses: u64,
    pub bloom_true_positives: u64,
    pub bloom_false_positives: u64,
    pub evictions: u64,
    pub compressions: u64,
    pub decompressions: u64,
    pub total_bytes_saved: u64,
}

impl CacheMetrics {
    pub fn hit_rate(&self, level: &str) -> f64 {
        match level {
            "l1" => {
                let total = self.l1_hits + self.l1_misses;
                if total > 0 {
                    self.l1_hits as f64 / total as f64
                } else {
                    0.0
                }
            }
            "l2" => {
                let total = self.l2_hits + self.l2_misses;
                if total > 0 {
                    self.l2_hits as f64 / total as f64
                } else {
                    0.0
                }
            }
            _ => 0.0,
        }
    }
}

impl DistributedCache {
    /// Create new distributed cache
    pub async fn new(config: CacheConfig) -> Result<Self> {
        // Connect to Redis
        let client = redis::Client::open(config.redis_url.as_str())
            .context("Failed to create Redis client")?;

        let conn_manager = ConnectionManager::new(client).await
            .context("Failed to connect to Redis")?;

        // Initialize L1 cache
        let l1_cache = Arc::new(RwLock::new(
            L1Cache::new(config.l1_max_entries, config.eviction_policy)
        ));

        // Initialize bloom filter if enabled
        let bloom_filter = if config.enable_bloom_filter {
            let bloom = Bloom::new_for_fp_rate(config.bloom_capacity, config.bloom_fp_rate);
            Arc::new(RwLock::new(Some(bloom)))
        } else {
            Arc::new(RwLock::new(None))
        };

        // Initialize consistent hashing if enabled
        let consistent_hash = if config.enable_consistent_hashing {
            // For now, use single node (current Redis instance)
            let nodes = vec![config.redis_url.clone()];
            Arc::new(RwLock::new(Some(ConsistentHash::new(nodes, config.virtual_nodes))))
        } else {
            Arc::new(RwLock::new(None))
        };

        Ok(Self {
            config,
            l1_cache,
            redis_conn: Arc::new(Mutex::new(conn_manager)),
            bloom_filter,
            consistent_hash,
            metrics: Arc::new(RwLock::new(CacheMetrics::default())),
        })
    }

    /// Get value from cache
    #[instrument(skip(self))]
    pub async fn get<V>(&self, key: &str) -> Result<Option<V>>
    where
        V: DeserializeOwned,
    {
        // Check bloom filter first (if enabled)
        if self.config.enable_bloom_filter {
            let bloom = self.bloom_filter.read().await;
            if let Some(ref filter) = *bloom {
                if !filter.check(&key.to_string()) {
                    self.metrics.write().await.bloom_true_positives += 1;
                    return Ok(None);
                }
            }
        }

        // Try L1 cache
        {
            let mut l1 = self.l1_cache.write().await;
            if let Some(bytes) = l1.get(&key.to_string()) {
                self.metrics.write().await.l1_hits += 1;

                let value = if self.is_compressed(&bytes) {
                    self.decompress_and_deserialize(&bytes)?
                } else {
                    bincode::deserialize(&bytes)?
                };

                return Ok(Some(value));
            }
            self.metrics.write().await.l1_misses += 1;
        }

        // Try L2 cache (Redis)
        {
            let mut conn = self.redis_conn.lock().await;
            let result: RedisResult<Vec<u8>> = conn.get(key).await;

            if let Ok(bytes) = result {
                self.metrics.write().await.l2_hits += 1;

                // Store in L1
                self.l1_cache.write().await.put(
                    key.to_string(),
                    bytes.clone(),
                    Some(Duration::seconds(self.config.l2_ttl_seconds as i64))
                );

                let value = if self.is_compressed(&bytes) {
                    self.decompress_and_deserialize(&bytes)?
                } else {
                    bincode::deserialize(&bytes)?
                };

                return Ok(Some(value));
            }
            self.metrics.write().await.l2_misses += 1;
        }

        // Try L3 cache (disk) if configured
        if let Some(ref dir) = self.config.l3_directory {
            let path = self.get_disk_path(dir, key);
            if tokio::fs::metadata(&path).await.is_ok() {
                let bytes = tokio::fs::read(&path).await?;
                self.metrics.write().await.l3_hits += 1;

                // Promote to L2 and L1
                self.promote_to_l2(key, &bytes).await?;
                self.l1_cache.write().await.put(
                    key.to_string(),
                    bytes.clone(),
                    Some(Duration::seconds(self.config.l2_ttl_seconds as i64))
                );

                let value = if self.is_compressed(&bytes) {
                    self.decompress_and_deserialize(&bytes)?
                } else {
                    bincode::deserialize(&bytes)?
                };

                return Ok(Some(value));
            }
            self.metrics.write().await.l3_misses += 1;
        }

        Ok(None)
    }

    /// Put value in cache
    #[instrument(skip(self, value))]
    pub async fn put<V>(&self, key: &str, value: &V, ttl: Option<Duration>) -> Result<()>
    where
        V: Serialize,
    {
        let bytes = bincode::serialize(value)?;

        // Compress if needed
        let final_bytes = if self.should_compress(&bytes) {
            self.metrics.write().await.compressions += 1;
            self.compress(&bytes)?
        } else {
            bytes
        };

        // Update bloom filter
        if self.config.enable_bloom_filter {
            let mut bloom = self.bloom_filter.write().await;
            if let Some(ref mut filter) = *bloom {
                filter.set(&key.to_string());
            }
        }

        // Handle write strategy
        match self.config.write_strategy {
            WriteStrategy::WriteThrough => {
                // Write to all levels synchronously
                self.write_all_levels(key, &final_bytes, ttl).await?;
            }
            WriteStrategy::WriteBehind => {
                // Write to L1 immediately, others async
                self.l1_cache.write().await.put(
                    key.to_string(),
                    final_bytes.clone(),
                    ttl
                );

                // Async write to L2/L3
                let key = key.to_string();
                let bytes = final_bytes.clone();
                let ttl = ttl.clone();
                let redis = self.redis_conn.clone();
                let l3_dir = self.config.l3_directory.clone();
                let l2_ttl = self.config.l2_ttl_seconds;

                tokio::spawn(async move {
                    // Write to Redis
                    if let Ok(mut conn) = redis.lock().await.try_lock() {
                        let ttl_secs = ttl.map(|d| d.num_seconds()).unwrap_or(l2_ttl as i64);
                        let _: RedisResult<()> = conn.set_ex(&key, &bytes, ttl_secs as usize).await;
                    }

                    // Write to disk
                    if let Some(dir) = l3_dir {
                        let path = format!("{}/{}", dir, Self::hash_key(&key));
                        let _ = tokio::fs::write(&path, &bytes).await;
                    }
                });
            }
            WriteStrategy::WriteAround => {
                // Write only to backing store, invalidate cache
                self.invalidate(key).await?;

                // Write to L2 and L3
                self.write_to_l2(key, &final_bytes, ttl).await?;
                if let Some(ref dir) = self.config.l3_directory {
                    self.write_to_l3(dir, key, &final_bytes).await?;
                }
            }
        }

        Ok(())
    }

    /// Invalidate cache entry
    pub async fn invalidate(&self, key: &str) -> Result<()> {
        // Remove from L1
        self.l1_cache.write().await.remove(&key.to_string());

        // Remove from L2
        let mut conn = self.redis_conn.lock().await;
        let _: RedisResult<()> = conn.del(key).await;

        // Remove from L3
        if let Some(ref dir) = self.config.l3_directory {
            let path = self.get_disk_path(dir, key);
            let _ = tokio::fs::remove_file(&path).await;
        }

        Ok(())
    }

    /// Clear all cache levels
    pub async fn clear(&self) -> Result<()> {
        // Clear L1
        self.l1_cache.write().await.clear();

        // Clear L2 (be careful in production!)
        let mut conn = self.redis_conn.lock().await;
        let _: RedisResult<()> = redis::cmd("FLUSHDB").query_async(&mut *conn).await;

        // Clear L3
        if let Some(ref dir) = self.config.l3_directory {
            let _ = tokio::fs::remove_dir_all(dir).await;
            tokio::fs::create_dir_all(dir).await?;
        }

        // Reset bloom filter
        if self.config.enable_bloom_filter {
            let mut bloom = self.bloom_filter.write().await;
            if bloom.is_some() {
                *bloom = Some(Bloom::new_for_fp_rate(
                    self.config.bloom_capacity,
                    self.config.bloom_fp_rate
                ));
            }
        }

        Ok(())
    }

    /// Get cache metrics
    pub async fn get_metrics(&self) -> CacheMetrics {
        self.metrics.read().await.clone()
    }

    // Helper methods

    fn should_compress(&self, data: &[u8]) -> bool {
        self.config.enable_compression && data.len() >= self.config.compression_threshold
    }

    fn is_compressed(&self, data: &[u8]) -> bool {
        // Check magic bytes for compression
        data.len() >= 2 && data[0] == 0x78 && data[1] == 0x9c
    }

    fn compress(&self, data: &[u8]) -> Result<Vec<u8>> {
        use flate2::write::ZlibEncoder;
        use flate2::Compression;
        use std::io::Write;

        let mut encoder = ZlibEncoder::new(Vec::new(), Compression::default());
        encoder.write_all(data)?;
        Ok(encoder.finish()?)
    }

    fn decompress_and_deserialize<V>(&self, data: &[u8]) -> Result<V>
    where
        V: DeserializeOwned,
    {
        use flate2::read::ZlibDecoder;
        use std::io::Read;

        self.metrics.write().await.decompressions += 1;

        let mut decoder = ZlibDecoder::new(data);
        let mut decompressed = Vec::new();
        decoder.read_to_end(&mut decompressed)?;

        Ok(bincode::deserialize(&decompressed)?)
    }

    async fn write_all_levels(&self, key: &str, data: &[u8], ttl: Option<Duration>) -> Result<()> {
        // Write to L1
        self.l1_cache.write().await.put(key.to_string(), data.to_vec(), ttl);

        // Write to L2
        self.write_to_l2(key, data, ttl).await?;

        // Write to L3
        if let Some(ref dir) = self.config.l3_directory {
            self.write_to_l3(dir, key, data).await?;
        }

        Ok(())
    }

    async fn write_to_l2(&self, key: &str, data: &[u8], ttl: Option<Duration>) -> Result<()> {
        let mut conn = self.redis_conn.lock().await;
        let ttl_secs = ttl
            .map(|d| d.num_seconds())
            .unwrap_or(self.config.l2_ttl_seconds as i64);

        let _: RedisResult<()> = conn.set_ex(key, data, ttl_secs as usize).await;
        Ok(())
    }

    async fn write_to_l3(&self, dir: &str, key: &str, data: &[u8]) -> Result<()> {
        tokio::fs::create_dir_all(dir).await?;
        let path = self.get_disk_path(dir, key);
        tokio::fs::write(&path, data).await?;
        Ok(())
    }

    async fn promote_to_l2(&self, key: &str, data: &[u8]) -> Result<()> {
        self.write_to_l2(key, data, Some(Duration::seconds(self.config.l2_ttl_seconds as i64))).await
    }

    fn get_disk_path(&self, dir: &str, key: &str) -> String {
        format!("{}/{}", dir, Self::hash_key(key))
    }

    fn hash_key(key: &str) -> String {
        let mut hasher = Sha256::new();
        hasher.update(key.as_bytes());
        format!("{:x}", hasher.finalize())
    }
}

/// Cache trait for generic caching
#[async_trait]
pub trait Cache: Send + Sync {
    async fn get<V>(&self, key: &str) -> Result<Option<V>>
    where
        V: DeserializeOwned + Send;

    async fn put<V>(&self, key: &str, value: &V, ttl: Option<Duration>) -> Result<()>
    where
        V: Serialize + Send + Sync;

    async fn invalidate(&self, key: &str) -> Result<()>;

    async fn clear(&self) -> Result<()>;
}

#[async_trait]
impl Cache for DistributedCache {
    async fn get<V>(&self, key: &str) -> Result<Option<V>>
    where
        V: DeserializeOwned + Send,
    {
        self.get(key).await
    }

    async fn put<V>(&self, key: &str, value: &V, ttl: Option<Duration>) -> Result<()>
    where
        V: Serialize + Send + Sync,
    {
        self.put(key, value, ttl).await
    }

    async fn invalidate(&self, key: &str) -> Result<()> {
        self.invalidate(key).await
    }

    async fn clear(&self) -> Result<()> {
        self.clear().await
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_l1_cache_lru() {
        let mut cache = L1Cache::new(2, EvictionPolicy::LRU);

        cache.put("a".to_string(), vec![1], None);
        cache.put("b".to_string(), vec![2], None);

        // Access 'a' to make it more recent
        assert_eq!(cache.get(&"a".to_string()), Some(vec![1]));

        // Add 'c', should evict 'b' (least recently used)
        cache.put("c".to_string(), vec![3], None);

        assert_eq!(cache.get(&"a".to_string()), Some(vec![1]));
        assert_eq!(cache.get(&"b".to_string()), None);
        assert_eq!(cache.get(&"c".to_string()), Some(vec![3]));
    }

    #[test]
    fn test_consistent_hash() {
        let nodes = vec!["node1".to_string(), "node2".to_string(), "node3".to_string()];
        let hash = ConsistentHash::new(nodes, 100);

        // Same key should always map to same node
        let node1 = hash.get_node("key1").unwrap();
        let node2 = hash.get_node("key1").unwrap();
        assert_eq!(node1, node2);

        // Different keys should distribute
        let keys: Vec<String> = (0..100).map(|i| format!("key{}", i)).collect();
        let mut distribution: HashMap<String, usize> = HashMap::new();

        for key in &keys {
            let node = hash.get_node(key).unwrap();
            *distribution.entry(node).or_insert(0) += 1;
        }

        // Check reasonable distribution (not all on one node)
        assert!(distribution.len() > 1);
    }

    #[test]
    fn test_cache_entry_expiration() {
        let entry = CacheEntry::new(vec![1, 2, 3], Some(Duration::seconds(-1)));
        assert!(entry.is_expired());

        let entry = CacheEntry::new(vec![1, 2, 3], Some(Duration::seconds(60)));
        assert!(!entry.is_expired());

        let entry = CacheEntry::new(vec![1, 2, 3], None);
        assert!(!entry.is_expired());
    }
}
