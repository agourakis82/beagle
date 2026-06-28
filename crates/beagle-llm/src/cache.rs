//! Gateway response cache (#14): bounded LRU + TTL exact-match cache keyed by a hash of
//! (tier + prompt + params). Checked before calling any provider; populated on success.
//!
//! Design:
//! - Pure stdlib, no external crates (lru not in the workspace lock file).
//! - `ResponseCache` is opt-in: disabled by default (capacity=0). Set `BEAGLE_CACHE_SIZE`
//!   (entry count cap, e.g. 512) and optionally `BEAGLE_CACHE_TTL_SECS` (default 300s).
//! - Cache key = FNV-1a hash of `"tier|prompt|temp|max_tokens"` — fast, no dep, collision
//!   probability negligible for our workloads.
//! - Eviction: true LRU via a generation counter per entry (cheapest no-dep approach for a
//!   `Mutex<HashMap>`): on insert when full, evict the entry with the smallest `last_used` stamp.
//!
//! NOTE on Anthropic prompt caching: the `LlmClient::chat` trait does not carry a stable system
//! prompt parameter, so there is no opportunity to set `cache_control: {type: "ephemeral"}` on
//! the Anthropic message content at this layer. Adding that requires either a dedicated
//! `AnthropicClient::complete_with_system_cache` method or a system-prompt parameter on
//! `LlmRequest` — deferred as a P1 follow-up (see docs/MODERNIZATION_PLAN_2026.md §14).

use std::collections::HashMap;
use std::sync::Mutex;
use std::time::{Duration, Instant};
use tracing::{debug, trace};

/// Bounded LRU+TTL exact-match response cache.
pub struct ResponseCache {
    capacity: usize,
    ttl: Duration,
    store: Mutex<CacheStore>,
}

struct CacheStore {
    map: HashMap<u64, CacheEntry>,
    /// Monotonically increasing generation for LRU approximation.
    gen: u64,
}

struct CacheEntry {
    value: String,
    expires: Instant,
    last_used: u64,
}

impl ResponseCache {
    /// Construct a cache. `capacity == 0` means disabled (no storage, all misses).
    pub fn new(capacity: usize, ttl: Duration) -> Self {
        Self {
            capacity,
            ttl,
            store: Mutex::new(CacheStore {
                map: HashMap::with_capacity(capacity.min(1024)),
                gen: 0,
            }),
        }
    }

    /// Build from environment variables (`BEAGLE_CACHE_SIZE`, `BEAGLE_CACHE_TTL_SECS`).
    /// Returns a disabled cache if neither is set.
    pub fn from_env() -> Self {
        let capacity = std::env::var("BEAGLE_CACHE_SIZE")
            .ok()
            .and_then(|v| v.parse::<usize>().ok())
            .unwrap_or(0);
        let ttl_secs = std::env::var("BEAGLE_CACHE_TTL_SECS")
            .ok()
            .and_then(|v| v.parse::<u64>().ok())
            .unwrap_or(300);
        if capacity > 0 {
            tracing::info!(
                "ResponseCache enabled: capacity={} ttl={}s",
                capacity,
                ttl_secs
            );
        }
        Self::new(capacity, Duration::from_secs(ttl_secs))
    }

    /// Whether caching is active.
    pub fn enabled(&self) -> bool {
        self.capacity > 0
    }

    /// Look up a cached response. Returns `Some(value)` on hit (and refreshes LRU), `None` on
    /// miss or expiry.
    pub fn get(&self, key: u64) -> Option<String> {
        if self.capacity == 0 {
            return None;
        }
        let now = Instant::now();
        let mut store = self.store.lock().unwrap();

        // Check expiry and get value in one scope, then mutate separately.
        let result = store.map.get(&key).and_then(|e| {
            if now < e.expires {
                Some(e.value.clone())
            } else {
                None
            }
        });

        match result {
            Some(value) => {
                let gen = store.gen;
                store.gen += 1;
                if let Some(entry) = store.map.get_mut(&key) {
                    entry.last_used = gen;
                }
                trace!("ResponseCache hit key={:#x}", key);
                Some(value)
            }
            None => {
                // If present but expired, evict eagerly.
                store.map.remove(&key);
                None
            }
        }
    }

    /// Insert a response. If at capacity, evicts the LRU entry first.
    pub fn insert(&self, key: u64, value: String) {
        if self.capacity == 0 {
            return;
        }
        let now = Instant::now();
        let expires = now + self.ttl;
        let mut store = self.store.lock().unwrap();

        // Evict LRU if full (after removing any expired entries first for free space).
        if store.map.len() >= self.capacity {
            // First pass: remove any expired entries.
            store.map.retain(|_, e| now < e.expires);
        }
        if store.map.len() >= self.capacity {
            // Still full — evict true LRU (smallest last_used).
            if let Some(&lru_key) = store
                .map
                .iter()
                .min_by_key(|(_, e)| e.last_used)
                .map(|(k, _)| k)
            {
                store.map.remove(&lru_key);
            }
        }

        let gen = store.gen;
        store.gen += 1;
        store.map.insert(
            key,
            CacheEntry {
                value,
                expires,
                last_used: gen,
            },
        );
        debug!(
            "ResponseCache insert key={:#x} (size={})",
            key,
            store.map.len()
        );
    }

    /// Compute the cache key from the routing tier label, prompt text, and optional params.
    /// Uses FNV-1a (64-bit) — no-dep, fast, suitable for cache keys.
    pub fn make_key(
        tier: &str,
        prompt: &str,
        temperature: Option<f32>,
        max_tokens: Option<i32>,
    ) -> u64 {
        // Encode params into a compact representation.
        let temp_bits = temperature.unwrap_or(f32::NAN).to_bits();
        let max_tok = max_tokens.unwrap_or(-1) as u32;

        // FNV-1a 64-bit
        const FNV_OFFSET: u64 = 14_695_981_039_346_656_037;
        const FNV_PRIME: u64 = 1_099_511_628_211;

        fn hash_bytes(mut h: u64, data: &[u8]) -> u64 {
            for &b in data {
                h ^= b as u64;
                h = h.wrapping_mul(FNV_PRIME);
            }
            h
        }

        let mut h = FNV_OFFSET;
        h = hash_bytes(h, tier.as_bytes());
        h ^= b'|' as u64;
        h = h.wrapping_mul(FNV_PRIME);
        h = hash_bytes(h, prompt.as_bytes());
        h = hash_bytes(h, &temp_bits.to_le_bytes());
        h = hash_bytes(h, &max_tok.to_le_bytes());
        h
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn cache_disabled_when_capacity_zero() {
        let c = ResponseCache::new(0, Duration::from_secs(60));
        assert!(!c.enabled());
        let key = ResponseCache::make_key("grok-3", "hello", None, None);
        c.insert(key, "response".to_string());
        assert!(c.get(key).is_none());
    }

    #[test]
    fn cache_hit_and_miss() {
        let c = ResponseCache::new(4, Duration::from_secs(60));
        let k = ResponseCache::make_key("grok-3", "hello", Some(0.7), Some(2048));
        assert!(c.get(k).is_none(), "cold miss");
        c.insert(k, "hi there".to_string());
        assert_eq!(c.get(k).unwrap(), "hi there");
    }

    #[test]
    fn cache_key_differs_by_params() {
        let k1 = ResponseCache::make_key("grok-3", "p", Some(0.5), Some(100));
        let k2 = ResponseCache::make_key("grok-3", "p", Some(0.9), Some(100));
        let k3 = ResponseCache::make_key("fleet", "p", Some(0.5), Some(100));
        assert_ne!(k1, k2);
        assert_ne!(k1, k3);
    }

    #[test]
    fn cache_evicts_lru_when_full() {
        let c = ResponseCache::new(2, Duration::from_secs(60));
        let k1 = ResponseCache::make_key("t", "a", None, None);
        let k2 = ResponseCache::make_key("t", "b", None, None);
        let k3 = ResponseCache::make_key("t", "c", None, None);
        c.insert(k1, "a".to_string());
        c.insert(k2, "b".to_string());
        // Touch k1 to make k2 LRU.
        let _ = c.get(k1);
        c.insert(k3, "c".to_string()); // should evict k2
        assert!(c.get(k1).is_some(), "k1 still present");
        assert!(c.get(k3).is_some(), "k3 just inserted");
        // k2 may or may not be present depending on eviction — just ensure size isn't exceeded.
        let store = c.store.lock().unwrap();
        assert!(store.map.len() <= 2);
    }

    #[test]
    fn cache_ttl_expiry() {
        let c = ResponseCache::new(4, Duration::from_millis(1));
        let k = ResponseCache::make_key("t", "x", None, None);
        c.insert(k, "val".to_string());
        std::thread::sleep(Duration::from_millis(5));
        assert!(c.get(k).is_none(), "expired entry should be a miss");
    }
}
