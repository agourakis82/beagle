//! Redis Caching Layer

use anyhow::Result;
use redis::{AsyncCommands, Client};
use serde::{Deserialize, Serialize};
use std::time::Duration;
use tracing::{debug, info};
use uuid::Uuid;

pub struct CacheLayer {
    client: Client,
}

impl CacheLayer {
    pub fn new(redis_url: &str) -> Result<Self> {
        let client = Client::open(redis_url)?;
        info!("✅ Redis cache layer initialized: {}", redis_url);
        Ok(Self { client })
    }

    /// Cache manuscript preview (expires after 1 hour)
    pub async fn cache_preview(&self, manuscript_id: &Uuid, preview: &str) -> Result<()> {
        let mut conn = self.client.get_async_connection().await?;

        let key = format!("preview:{}", manuscript_id);

        conn.set_ex(&key, preview, 3600).await?; // 1 hour TTL

        debug!("Cached preview for manuscript: {}", manuscript_id);
        Ok(())
    }

    /// Get cached preview
    pub async fn get_preview(&self, manuscript_id: &Uuid) -> Result<Option<String>> {
        let mut conn = self.client.get_async_connection().await?;

        let key = format!("preview:{}", manuscript_id);

        let preview: Option<String> = conn.get(&key).await?;

        if preview.is_some() {
            debug!("Cache hit for manuscript: {}", manuscript_id);
        } else {
            debug!("Cache miss for manuscript: {}", manuscript_id);
        }

        Ok(preview)
    }

    /// Cache LLM response (24 hour TTL)
    pub async fn cache_llm_response(&self, prompt_hash: &str, response: &str) -> Result<()> {
        let mut conn = self.client.get_async_connection().await?;

        let key = format!("llm:{}", prompt_hash);

        conn.set_ex(&key, response, 86400).await?; // 24 hours

        debug!("Cached LLM response for prompt hash: {}", prompt_hash);
        Ok(())
    }

    /// Get cached LLM response
    pub async fn get_llm_response(&self, prompt_hash: &str) -> Result<Option<String>> {
        let mut conn = self.client.get_async_connection().await?;

        let key = format!("llm:{}", prompt_hash);

        let response: Option<String> = conn.get(&key).await?;

        if response.is_some() {
            debug!("Cache hit for LLM prompt: {}", prompt_hash);
        }

        Ok(response)
    }

    /// Cache concept cluster results (6 hour TTL)
    pub async fn cache_cluster_results(
        &self,
        threshold: usize,
        clusters: &str, // JSON serialized
    ) -> Result<()> {
        let mut conn = self.client.get_async_connection().await?;

        let key = format!("clusters:threshold:{}", threshold);

        conn.set_ex(&key, clusters, 21600).await?; // 6 hours

        debug!("Cached cluster results for threshold: {}", threshold);
        Ok(())
    }

    /// Get cached cluster results
    pub async fn get_cluster_results(&self, threshold: usize) -> Result<Option<String>> {
        let mut conn = self.client.get_async_connection().await?;

        let key = format!("clusters:threshold:{}", threshold);

        let clusters: Option<String> = conn.get(&key).await?;

        Ok(clusters)
    }

    /// Invalidate cache for a manuscript
    pub async fn invalidate_preview(&self, manuscript_id: &Uuid) -> Result<()> {
        let mut conn = self.client.get_async_connection().await?;

        let key = format!("preview:{}", manuscript_id);

        conn.del(&key).await?;

        debug!("Invalidated cache for manuscript: {}", manuscript_id);
        Ok(())
    }

    /// Clear all cache (use with caution)
    pub async fn clear_all(&self) -> Result<()> {
        let mut conn = self.client.get_async_connection().await?;

        // Only clear HERMES keys
        let pattern = "preview:*";
        let keys: Vec<String> = conn.keys(pattern).await?;

        if !keys.is_empty() {
            conn.del(&keys).await?;
            info!("Cleared {} cache keys", keys.len());
        }

        Ok(())
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[tokio::test]
    #[ignore] // Requires Redis running
    async fn test_cache_preview() {
        let cache = CacheLayer::new("redis://localhost:6379").unwrap();

        let manuscript_id = Uuid::new_v4();
        let preview = "Test preview content";

        // Cache
        cache.cache_preview(&manuscript_id, preview).await.unwrap();

        // Retrieve
        let cached = cache.get_preview(&manuscript_id).await.unwrap();
        assert_eq!(cached, Some(preview.to_string()));

        // Invalidate
        cache.invalidate_preview(&manuscript_id).await.unwrap();

        // Should be gone
        let cached_after = cache.get_preview(&manuscript_id).await.unwrap();
        assert_eq!(cached_after, None);
    }
}
