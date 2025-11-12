use std::env;
use std::time::Instant;

use beagle_hypergraph::{
    cache::CacheStats, storage::StorageRepository, CachedPostgresStorage, ContentType, Node,
    RedisCache,
};
use uuid::Uuid;

const DEFAULT_REDIS_URL: &str = "redis://localhost:6379";

fn redis_url() -> String {
    env::var("REDIS_URL").unwrap_or_else(|_| DEFAULT_REDIS_URL.to_string())
}

#[tokio::test]
async fn test_redis_cache_roundtrip() {
    let cache = match RedisCache::new(&redis_url()).await {
        Ok(cache) => cache,
        Err(err) => {
            eprintln!("Skipping test_redis_cache_roundtrip: {err}");
            return;
        }
    };

    cache.flush_all().await.ok();

    let node = Node::builder()
        .content("Test caching")
        .content_type(ContentType::Thought)
        .device_id("test")
        .build()
        .expect("builder should produce valid node");

    cache.set(&node).await.expect("set should succeed");

    let cached = cache
        .get(node.id)
        .await
        .expect("cache get should succeed")
        .expect("node should be present");

    assert_eq!(cached.id, node.id);
}

#[tokio::test]
async fn test_cache_invalidation() {
    let cache = match RedisCache::new(&redis_url()).await {
        Ok(cache) => cache,
        Err(err) => {
            eprintln!("Skipping test_cache_invalidation: {err}");
            return;
        }
    };

    cache.flush_all().await.ok();

    let node = Node::builder()
        .content("To be invalidated")
        .content_type(ContentType::Task)
        .device_id("test")
        .build()
        .expect("builder should produce valid node");

    cache.set(&node).await.expect("set should succeed");
    assert!(cache
        .get(node.id)
        .await
        .expect("get should succeed")
        .is_some());

    cache
        .invalidate(node.id)
        .await
        .expect("invalidate should succeed");

    assert!(cache
        .get(node.id)
        .await
        .expect("get should succeed")
        .is_none());
}

#[tokio::test]
async fn test_cached_storage_pattern() {
    let database_url = match env::var("DATABASE_URL") {
        Ok(url) => url,
        Err(_) => {
            eprintln!("Skipping test_cached_storage_pattern: DATABASE_URL not set");
            return;
        }
    };

    let storage = match CachedPostgresStorage::new(&database_url, &redis_url()).await {
        Ok(storage) => storage,
        Err(err) => {
            eprintln!("Skipping test_cached_storage_pattern: {err}");
            return;
        }
    };

    let node = Node::builder()
        .content("Cache-aside pattern test")
        .content_type(ContentType::Memory)
        .device_id("test")
        .build()
        .expect("builder should produce valid node");

    let created = storage
        .create_node(node.clone())
        .await
        .expect("create should succeed");
    let id = created.id;

    let _ = storage.cache().flush_all().await;

    let start_db = Instant::now();
    let fetched = storage.get_node(id).await.expect("DB fetch should succeed");
    let db_latency = start_db.elapsed();
    assert_eq!(fetched.id, id);

    let start_cache = Instant::now();
    let cached = storage
        .get_node(id)
        .await
        .expect("cache fetch should succeed");
    let cache_latency = start_cache.elapsed();
    assert_eq!(cached.id, id);
    assert!(
        cache_latency <= db_latency,
        "cache latency ({:?}) should not exceed initial DB latency ({:?})",
        cache_latency,
        db_latency
    );

    let stats = storage
        .cache_stats()
        .await
        .expect("stats should be retrievable");
    assert!(
        stats.hits >= 1,
        "expected at least one cache hit, got {stats:?}"
    );

    storage.delete_node(id).await.ok();
}

#[tokio::test]
async fn test_cache_stats() {
    let cache = match RedisCache::new(&redis_url()).await {
        Ok(cache) => cache,
        Err(err) => {
            eprintln!("Skipping test_cache_stats: {err}");
            return;
        }
    };

    cache.flush_all().await.ok();

    let node = Node::builder()
        .content("Stats test")
        .content_type(ContentType::Note)
        .device_id("test")
        .build()
        .expect("builder should produce valid node");

    cache.set(&node).await.expect("set should succeed");
    let _ = cache.get(node.id).await;
    let _ = cache.get(Uuid::new_v4()).await;

    let stats: CacheStats = cache.stats().await.expect("stats should succeed");
    assert!(stats.hits + stats.misses > 0);
}
