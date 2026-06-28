//! Routing resilience primitives (#13): per-key circuit breaker + token-bucket rate limiter.
//!
//! The unified router (`TieredRouter::complete_robust`) used a fixed fallback chain with bounded
//! backoff but had no breaker (a dead provider was retried on every call) and no rate limiting.
//! These are small, dependency-free, unit-tested primitives wired into the robust path.

use std::collections::HashMap;
use std::sync::Mutex;
use std::time::{Duration, Instant};

/// Per-key circuit breaker. After `threshold` consecutive failures a key is **open** (skipped) for
/// `cooldown`; the next attempt after cooldown is allowed (half-open) and a success closes it.
pub struct CircuitBreaker {
    threshold: u32,
    cooldown: Duration,
    state: Mutex<HashMap<String, BreakerEntry>>,
}

#[derive(Default, Clone)]
struct BreakerEntry {
    consecutive_failures: u32,
    open_until: Option<Instant>,
}

impl CircuitBreaker {
    pub fn new(threshold: u32, cooldown: Duration) -> Self {
        Self {
            threshold: threshold.max(1),
            cooldown,
            state: Mutex::new(HashMap::new()),
        }
    }

    /// Whether a call to `key` is allowed right now (closed, or half-open after cooldown).
    pub fn allow(&self, key: &str) -> bool {
        self.allow_at(key, Instant::now())
    }

    /// Record a successful call — closes the breaker for `key`.
    pub fn record_success(&self, key: &str) {
        let mut s = self.state.lock().unwrap();
        s.insert(key.to_string(), BreakerEntry::default());
    }

    /// Record a failed call — trips the breaker open once `threshold` is reached.
    pub fn record_failure(&self, key: &str) {
        self.record_failure_at(key, Instant::now());
    }

    // --- testable, clock-injected internals ---
    fn allow_at(&self, key: &str, now: Instant) -> bool {
        let s = self.state.lock().unwrap();
        match s.get(key).and_then(|e| e.open_until) {
            Some(until) => now >= until, // half-open once cooldown elapses
            None => true,
        }
    }

    fn record_failure_at(&self, key: &str, now: Instant) {
        let mut s = self.state.lock().unwrap();
        let e = s.entry(key.to_string()).or_default();
        e.consecutive_failures += 1;
        if e.consecutive_failures >= self.threshold {
            e.open_until = Some(now + self.cooldown);
        }
    }
}

// ============================================================================
// Bounded jittered exponential backoff helper (#13)
// ============================================================================

/// Compute the bounded jittered backoff sleep duration for retry attempt `attempt` (0-indexed,
/// where 0 = first fallback — no sleep before the primary attempt).
///
/// Formula: `clamp(base_ms * 2^attempt, 0, max_ms) + uniform_jitter(0..jitter_ms)`.
///
/// The jitter source is the low bits of an `Instant::now()` read — fine for non-crypto use.
pub fn backoff_duration(attempt: u32, base_ms: u64, max_ms: u64) -> std::time::Duration {
    let shift = attempt.min(10); // cap shift to avoid u64 overflow (2^10 = 1024)
    let exp = base_ms.saturating_mul(1u64 << shift).min(max_ms);
    let jitter_range = (exp / 4).max(1); // +-25% jitter
                                         // Low bits of Instant are a cheap entropy source for non-security jitter.
    let raw = {
        // Use duration_since a fixed epoch approximation via elapsed nanos mod jitter_range.
        // `Instant::now()` subsec ns is enough entropy for backoff jitter.
        let nanos = std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)
            .map(|d| d.subsec_nanos() as u64)
            .unwrap_or_else(|_| {
                // Fallback: use Instant elapsed nanos (always positive, no epoch dependency).
                static START: std::sync::OnceLock<std::time::Instant> = std::sync::OnceLock::new();
                START
                    .get_or_init(std::time::Instant::now)
                    .elapsed()
                    .subsec_nanos() as u64
            });
        nanos % jitter_range
    };
    let total = (exp + raw).min(max_ms);
    std::time::Duration::from_millis(total)
}

/// Per-key token bucket. `capacity` tokens, refilled at `refill_per_sec`. `try_acquire` consumes one
/// token if available. Lazily refills based on elapsed wall-clock time.
pub struct TokenBucket {
    capacity: f64,
    refill_per_sec: f64,
    state: Mutex<HashMap<String, BucketEntry>>,
}

#[derive(Clone)]
struct BucketEntry {
    tokens: f64,
    last: Instant,
}

impl TokenBucket {
    pub fn new(capacity: f64, refill_per_sec: f64) -> Self {
        Self {
            capacity: capacity.max(1.0),
            refill_per_sec: refill_per_sec.max(0.0),
            state: Mutex::new(HashMap::new()),
        }
    }

    /// Try to consume one token for `key`. Returns true if allowed.
    pub fn try_acquire(&self, key: &str) -> bool {
        self.try_acquire_at(key, Instant::now())
    }

    fn try_acquire_at(&self, key: &str, now: Instant) -> bool {
        let mut s = self.state.lock().unwrap();
        let e = s.entry(key.to_string()).or_insert(BucketEntry {
            tokens: self.capacity,
            last: now,
        });
        let elapsed = now.saturating_duration_since(e.last).as_secs_f64();
        e.tokens = (e.tokens + elapsed * self.refill_per_sec).min(self.capacity);
        e.last = now;
        if e.tokens >= 1.0 {
            e.tokens -= 1.0;
            true
        } else {
            false
        }
    }
}

/// Router-facing rate limiter (#13): a thin, env-configurable wrapper over [`TokenBucket`] that can
/// be fully disabled. When disabled (`capacity ≤ 0`, the default), `allow` is a no-op that always
/// returns true — so wiring it into the hot path never changes behavior unless an operator opts in
/// via `BEAGLE_LLM_RATE_CAPACITY`.
pub struct RateLimit {
    bucket: Option<TokenBucket>,
}

impl RateLimit {
    /// Build from env: `BEAGLE_LLM_RATE_CAPACITY` (max burst tokens per identity) and
    /// `BEAGLE_LLM_RATE_REFILL_PER_SEC` (sustained tokens/sec). When refill is unset it defaults
    /// to `capacity`, i.e. the bucket refills fully every second → `capacity` requests/sec
    /// sustained, with bursts up to `capacity`. Set refill explicitly (e.g. `1`) for a tighter
    /// sustained rate. Capacity ≤ 0 or unset → disabled.
    pub fn from_env() -> Self {
        let capacity = std::env::var("BEAGLE_LLM_RATE_CAPACITY")
            .ok()
            .and_then(|v| v.parse::<f64>().ok())
            .unwrap_or(0.0);
        if capacity <= 0.0 {
            return Self::disabled();
        }
        let refill = std::env::var("BEAGLE_LLM_RATE_REFILL_PER_SEC")
            .ok()
            .and_then(|v| v.parse::<f64>().ok())
            .unwrap_or(capacity);
        Self {
            bucket: Some(TokenBucket::new(capacity, refill)),
        }
    }

    /// An always-allow limiter (rate limiting off).
    pub fn disabled() -> Self {
        Self { bucket: None }
    }

    /// An enabled limiter with explicit parameters (used by tests / programmatic config).
    pub fn enabled(capacity: f64, refill_per_sec: f64) -> Self {
        Self {
            bucket: Some(TokenBucket::new(capacity, refill_per_sec)),
        }
    }

    /// True if this limiter actually enforces a limit (vs. always-allow).
    pub fn is_enabled(&self) -> bool {
        self.bucket.is_some()
    }

    /// Try to admit one request for `identity`. Always true when disabled.
    pub fn allow(&self, identity: &str) -> bool {
        match &self.bucket {
            Some(b) => b.try_acquire(identity),
            None => true,
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn ratelimit_disabled_always_allows() {
        let rl = RateLimit::disabled();
        assert!(!rl.is_enabled());
        for _ in 0..1000 {
            assert!(rl.allow("anon"));
        }
    }

    #[test]
    fn ratelimit_enabled_throttles_per_identity() {
        let rl = RateLimit::enabled(2.0, 0.0); // 2 tokens, no refill
        assert!(rl.is_enabled());
        assert!(rl.allow("alice"));
        assert!(rl.allow("alice"));
        assert!(!rl.allow("alice"), "alice exhausted her 2 tokens");
        assert!(rl.allow("bob"), "bob has his own independent bucket");
    }

    #[test]
    fn breaker_opens_after_threshold_and_half_opens_after_cooldown() {
        let cb = CircuitBreaker::new(3, Duration::from_secs(10));
        let t0 = Instant::now();
        assert!(cb.allow_at("grok", t0));
        cb.record_failure_at("grok", t0);
        cb.record_failure_at("grok", t0);
        assert!(cb.allow_at("grok", t0), "still closed below threshold");
        cb.record_failure_at("grok", t0); // 3rd -> open
        assert!(!cb.allow_at("grok", t0), "open after threshold");
        assert!(
            !cb.allow_at("grok", t0 + Duration::from_secs(5)),
            "still open within cooldown"
        );
        assert!(
            cb.allow_at("grok", t0 + Duration::from_secs(11)),
            "half-open after cooldown"
        );
        // a success closes it
        cb.record_success("grok");
        assert!(cb.allow_at("grok", t0 + Duration::from_secs(11)));
    }

    #[test]
    fn breaker_isolates_keys() {
        let cb = CircuitBreaker::new(1, Duration::from_secs(10));
        let t = Instant::now();
        cb.record_failure_at("a", t);
        assert!(!cb.allow_at("a", t));
        assert!(cb.allow_at("b", t), "other key unaffected");
    }

    #[test]
    fn token_bucket_limits_then_refills() {
        let tb = TokenBucket::new(2.0, 1.0); // 2 tokens, +1/s
        let t = Instant::now();
        assert!(tb.try_acquire_at("u", t));
        assert!(tb.try_acquire_at("u", t));
        assert!(!tb.try_acquire_at("u", t), "bucket empty");
        assert!(
            tb.try_acquire_at("u", t + Duration::from_secs(1)),
            "refilled 1 token after 1s"
        );
        assert!(tb.try_acquire_at("v", t), "other key has its own bucket");
    }
}
