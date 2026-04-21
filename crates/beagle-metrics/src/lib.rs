//! Prometheus Metrics Implementation for BEAGLE Observability
//!
//! Exports metrics in Prometheus format at /metrics endpoint
//!
//! ## Core Metrics Implemented:
//!
//! ### LLM Router Metrics:
//! - `beagle_llm_requests_total` (counter, labels: provider, tier, status)
//! - `beagle_llm_request_duration_seconds` (histogram, buckets: 0.1, 0.5, 1, 2, 5, 10)
//! - `beagle_llm_tokens_total` (counter, labels: provider, type=input/output)
//! - `beagle_llm_cost_usd_total` (counter, labels: provider)
//!
//! ### Memory Metrics:
//! - `beagle_memory_queries_total` (counter, labels: source=qdrant/postgres, status)
//! - `beagle_memory_query_duration_seconds` (histogram)
//! - `beagle_memory_index_size` (gauge, labels: index_type)
//! - `beagle_qdrant_health_status` (gauge: 1=healthy, 0=unhealthy)
//!
//! ### Pipeline Metrics:
//! - `beagle_pipeline_runs_total` (counter, labels: status)
//! - `beagle_pipeline_duration_seconds` (histogram)
//! - `beagle_pipeline_stages_duration_seconds` (histogram, labels: stage)
//!
//! ### System Metrics:
//! - `beagle_active_connections` (gauge)
//! - `beagle_rate_limit_hits_total` (counter, labels: identifier)

use anyhow::{Context, Result};
use axum::{
    extract::State,
    http::StatusCode,
    response::{IntoResponse, Response},
    routing::get,
    Router,
};
use lazy_static::lazy_static;
use prometheus::{
    register_counter_vec, register_gauge_vec, register_histogram_vec, register_int_counter_vec,
    register_int_gauge, register_int_gauge_vec,
    CounterVec, Encoder, GaugeVec, HistogramVec, IntCounter, IntCounterVec, IntGauge, IntGaugeVec,
    TextEncoder,
};
use std::collections::HashMap;
use std::sync::Arc;
use std::time::{Duration, Instant};
use tokio::sync::RwLock;
use tracing::{debug, error, info, warn};

// ============================================
// LLM Router Metrics
// ============================================

lazy_static! {
    /// Total LLM requests by provider, tier, and status
    pub static ref LLM_REQUESTS_TOTAL: IntCounterVec = register_int_counter_vec!(
        "beagle_llm_requests_total",
        "Total LLM requests by provider, tier, and status",
        &["provider", "tier", "status"]
    ).expect("Failed to register beagle_llm_requests_total");

    /// LLM request duration in seconds (histogram with custom buckets)
    pub static ref LLM_REQUEST_DURATION_SECONDS: HistogramVec = register_histogram_vec!(
        "beagle_llm_request_duration_seconds",
        "LLM request duration in seconds",
        &["provider", "tier"],
        vec![0.1, 0.5, 1.0, 2.0, 5.0, 10.0]
    ).expect("Failed to register beagle_llm_request_duration_seconds");

    /// Total LLM tokens processed by provider and type (input/output)
    pub static ref LLM_TOKENS_TOTAL: IntCounterVec = register_int_counter_vec!(
        "beagle_llm_tokens_total",
        "Total LLM tokens processed by provider and type",
        &["provider", "type"]
    ).expect("Failed to register beagle_llm_tokens_total");

    /// Total LLM cost in USD by provider
    pub static ref LLM_COST_USD_TOTAL: CounterVec = register_counter_vec!(
        "beagle_llm_cost_usd_total",
        "Total LLM cost in USD by provider",
        &["provider"]
    ).expect("Failed to register beagle_llm_cost_usd_total");
}

// ============================================
// Memory Metrics
// ============================================

lazy_static! {
    /// Total memory queries by source and status
    pub static ref MEMORY_QUERIES_TOTAL: IntCounterVec = register_int_counter_vec!(
        "beagle_memory_queries_total",
        "Total memory queries by source and status",
        &["source", "status"]
    ).expect("Failed to register beagle_memory_queries_total");

    /// Memory query duration in seconds
    pub static ref MEMORY_QUERY_DURATION_SECONDS: HistogramVec = register_histogram_vec!(
        "beagle_memory_query_duration_seconds",
        "Memory query duration in seconds",
        &["source"],
        vec![0.01, 0.05, 0.1, 0.25, 0.5, 1.0, 2.5, 5.0]
    ).expect("Failed to register beagle_memory_query_duration_seconds");

    /// Memory index size by index type
    pub static ref MEMORY_INDEX_SIZE: IntGaugeVec = register_int_gauge_vec!(
        "beagle_memory_index_size",
        "Memory index size by index type",
        &["index_type"]
    ).expect("Failed to register beagle_memory_index_size");

    /// Qdrant health status (1=healthy, 0=unhealthy)
    pub static ref QDRANT_HEALTH_STATUS: IntGauge = register_int_gauge!(
        "beagle_qdrant_health_status",
        "Qdrant health status (1=healthy, 0=unhealthy)"
    ).expect("Failed to register beagle_qdrant_health_status");
}

// ============================================
// Pipeline Metrics
// ============================================

lazy_static! {
    /// Total pipeline runs by status
    pub static ref PIPELINE_RUNS_TOTAL: IntCounterVec = register_int_counter_vec!(
        "beagle_pipeline_runs_total",
        "Total pipeline runs by status",
        &["status"]
    ).expect("Failed to register beagle_pipeline_runs_total");

    /// Pipeline duration in seconds
    pub static ref PIPELINE_DURATION_SECONDS: HistogramVec = register_histogram_vec!(
        "beagle_pipeline_duration_seconds",
        "Pipeline duration in seconds",
        &["status"],
        vec![1.0, 5.0, 10.0, 30.0, 60.0, 120.0, 300.0, 600.0]
    ).expect("Failed to register beagle_pipeline_duration_seconds");

    /// Pipeline stage duration in seconds by stage
    pub static ref PIPELINE_STAGES_DURATION_SECONDS: HistogramVec = register_histogram_vec!(
        "beagle_pipeline_stages_duration_seconds",
        "Pipeline stage duration in seconds by stage",
        &["stage"],
        vec![0.5, 1.0, 2.5, 5.0, 10.0, 30.0, 60.0]
    ).expect("Failed to register beagle_pipeline_stages_duration_seconds");
}

// ============================================
// System Metrics
// ============================================

lazy_static! {
    /// Number of active connections
    pub static ref ACTIVE_CONNECTIONS: IntGauge = register_int_gauge!(
        "beagle_active_connections",
        "Number of active connections"
    ).expect("Failed to register beagle_active_connections");

    /// Total rate limit hits by identifier
    pub static ref RATE_LIMIT_HITS_TOTAL: IntCounterVec = register_int_counter_vec!(
        "beagle_rate_limit_hits_total",
        "Total rate limit hits by identifier",
        &["identifier"]
    ).expect("Failed to register beagle_rate_limit_hits_total");
}

// ============================================
// Additional BEAGLE-Specific Metrics
// ============================================

lazy_static! {
    /// HTTP request metrics (RED method)
    pub static ref HTTP_REQUESTS_TOTAL: IntCounterVec = register_int_counter_vec!(
        "beagle_http_requests_total",
        "Total HTTP requests by method, endpoint, and status",
        &["method", "endpoint", "status"]
    ).expect("Failed to register beagle_http_requests_total");

    /// HTTP request duration
    pub static ref HTTP_REQUEST_DURATION_SECONDS: HistogramVec = register_histogram_vec!(
        "beagle_http_request_duration_seconds",
        "HTTP request duration in seconds",
        &["method", "endpoint"],
        vec![0.001, 0.005, 0.01, 0.025, 0.05, 0.1, 0.25, 0.5, 1.0, 2.5, 5.0]
    ).expect("Failed to register beagle_http_request_duration_seconds");

    /// Active pipelines gauge
    pub static ref ACTIVE_PIPELINES: IntGauge = register_int_gauge!(
        "beagle_active_pipelines",
        "Number of active pipelines"
    ).expect("Failed to register beagle_active_pipelines");

    /// LLM cache hits/misses
    pub static ref LLM_CACHE_TOTAL: IntCounterVec = register_int_counter_vec!(
        "beagle_llm_cache_total",
        "LLM cache hits and misses",
        &["status"]
    ).expect("Failed to register beagle_llm_cache_total");
}

// ============================================
// Metrics Collector
// ============================================

/// Global metrics collector instance
pub static METRICS: once_cell::sync::Lazy<Arc<MetricsCollector>> =
    once_cell::sync::Lazy::new(|| {
        Arc::new(MetricsCollector::new(MetricsConfig::default()))
    });

/// Metrics configuration
#[derive(Debug, Clone)]
pub struct MetricsConfig {
    /// Enable detailed cardinality tracking
    pub enable_cardinality_tracking: bool,
    /// Maximum label cardinality before warning
    pub max_cardinality_per_metric: usize,
}

impl Default for MetricsConfig {
    fn default() -> Self {
        Self {
            enable_cardinality_tracking: true,
            max_cardinality_per_metric: 1000,
        }
    }
}

/// Metrics collector and exporter
pub struct MetricsCollector {
    config: MetricsConfig,
    cardinality_tracker: Arc<RwLock<HashMap<String, HashMap<String, usize>>>>,
}

impl MetricsCollector {
    /// Create new metrics collector
    pub fn new(config: MetricsConfig) -> Self {
        Self {
            config,
            cardinality_tracker: Arc::new(RwLock::new(HashMap::new())),
        }
    }

    // ============================================
    // LLM Metrics Recording
    // ============================================

    /// Record an LLM request with full details
    pub fn record_llm_request(
        &self,
        provider: &str,
        tier: &str,
        status: &str,
        duration: Duration,
        tokens_in: u64,
        tokens_out: u64,
        cost_usd: f64,
    ) {
        // Increment request counter
        LLM_REQUESTS_TOTAL
            .with_label_values(&[provider, tier, status])
            .inc();

        // Record duration
        LLM_REQUEST_DURATION_SECONDS
            .with_label_values(&[provider, tier])
            .observe(duration.as_secs_f64());

        // Record token usage
        if tokens_in > 0 {
            LLM_TOKENS_TOTAL
                .with_label_values(&[provider, "input"])
                .inc_by(tokens_in);
        }
        if tokens_out > 0 {
            LLM_TOKENS_TOTAL
                .with_label_values(&[provider, "output"])
                .inc_by(tokens_out);
        }

        // Record cost
        if cost_usd > 0.0 {
            LLM_COST_USD_TOTAL
                .with_label_values(&[provider])
                .inc_by(cost_usd);
        }

        // Track cardinality if enabled
        if self.config.enable_cardinality_tracking {
            self.track_cardinality(
                "llm_requests",
                &[provider, tier, status],
            );
        }

        debug!(
            provider = provider,
            tier = tier,
            status = status,
            duration_ms = duration.as_millis() as u64,
            tokens_in = tokens_in,
            tokens_out = tokens_out,
            cost_usd = cost_usd,
            "LLM request recorded"
        );
    }

    /// Record LLM cache hit/miss
    pub fn record_llm_cache(&self, hit: bool) {
        let status = if hit { "hit" } else { "miss" };
        LLM_CACHE_TOTAL.with_label_values(&[status]).inc();
    }

    // ============================================
    // Memory Metrics Recording
    // ============================================

    /// Record a memory query
    pub fn record_memory_query(
        &self,
        source: &str,
        status: &str,
        duration: Duration,
    ) {
        MEMORY_QUERIES_TOTAL
            .with_label_values(&[source, status])
            .inc();

        MEMORY_QUERY_DURATION_SECONDS
            .with_label_values(&[source])
            .observe(duration.as_secs_f64());

        debug!(
            source = source,
            status = status,
            duration_ms = duration.as_millis() as u64,
            "Memory query recorded"
        );
    }

    /// Update memory index size
    pub fn set_memory_index_size(&self, index_type: &str, size: i64) {
        MEMORY_INDEX_SIZE
            .with_label_values(&[index_type])
            .set(size);
    }

    /// Update Qdrant health status
    pub fn set_qdrant_health(&self, healthy: bool) {
        let value = if healthy { 1 } else { 0 };
        QDRANT_HEALTH_STATUS.set(value);
    }

    // ============================================
    // Pipeline Metrics Recording
    // ============================================

    /// Record pipeline run start
    pub fn record_pipeline_start(&self) {
        ACTIVE_PIPELINES.inc();
    }

    /// Record pipeline run completion
    pub fn record_pipeline_end(
        &self,
        status: &str,
        duration: Duration,
    ) {
        ACTIVE_PIPELINES.dec();
        PIPELINE_RUNS_TOTAL.with_label_values(&[status]).inc();
        PIPELINE_DURATION_SECONDS
            .with_label_values(&[status])
            .observe(duration.as_secs_f64());

        debug!(
            status = status,
            duration_secs = duration.as_secs_f64(),
            "Pipeline run recorded"
        );
    }

    /// Record pipeline stage duration
    pub fn record_pipeline_stage(
        &self,
        stage: &str,
        duration: Duration,
    ) {
        PIPELINE_STAGES_DURATION_SECONDS
            .with_label_values(&[stage])
            .observe(duration.as_secs_f64());

        debug!(
            stage = stage,
            duration_secs = duration.as_secs_f64(),
            "Pipeline stage recorded"
        );
    }

    // ============================================
    // System Metrics Recording
    // ============================================

    /// Increment active connections
    pub fn increment_connections(&self) {
        ACTIVE_CONNECTIONS.inc();
    }

    /// Decrement active connections
    pub fn decrement_connections(&self) {
        ACTIVE_CONNECTIONS.dec();
    }

    /// Record rate limit hit
    pub fn record_rate_limit_hit(&self, identifier: &str) {
        RATE_LIMIT_HITS_TOTAL.with_label_values(&[identifier]).inc();
        warn!(identifier = identifier, "Rate limit hit recorded");
    }

    // ============================================
    // HTTP Metrics Recording
    // ============================================

    /// Record HTTP request
    pub fn record_http_request(
        &self,
        method: &str,
        endpoint: &str,
        status: u16,
        duration: Duration,
    ) {
        let status_str = status.to_string();

        HTTP_REQUESTS_TOTAL
            .with_label_values(&[method, endpoint, &status_str])
            .inc();

        HTTP_REQUEST_DURATION_SECONDS
            .with_label_values(&[method, endpoint])
            .observe(duration.as_secs_f64());

        // Track cardinality if enabled
        if self.config.enable_cardinality_tracking {
            self.track_cardinality("http_requests", &[method, endpoint, &status_str]);
        }
    }

    // ============================================
    // Cardinality Tracking
    // ============================================

    fn track_cardinality(&self, metric_name: &str, labels: &[&str]) {
        if !self.config.enable_cardinality_tracking {
            return;
        }

        let key = labels.join(",");
        let metric_name = metric_name.to_string();
        let max_cardinality = self.config.max_cardinality_per_metric;
        let tracker = self.cardinality_tracker.clone();

        tokio::spawn(async move {
            let mut tracker = tracker.write().await;
            let metric_labels = tracker
                .entry(metric_name.clone())
                .or_insert_with(HashMap::new);

            *metric_labels.entry(key).or_insert(0) += 1;

            if metric_labels.len() > max_cardinality {
                warn!(
                    metric = metric_name,
                    cardinality = metric_labels.len(),
                    max = max_cardinality,
                    "High cardinality detected"
                );
            }
        });
    }

    /// Get cardinality report
    pub async fn get_cardinality_report(&self) -> HashMap<String, usize> {
        let tracker = self.cardinality_tracker.read().await;
        tracker
            .iter()
            .map(|(metric, labels)| (metric.clone(), labels.len()))
            .collect()
    }

    // ============================================
    // Export
    // ============================================

    /// Export metrics in Prometheus text format
    pub fn export(&self) -> Result<String> {
        let encoder = TextEncoder::new();
        let metric_families = prometheus::gather();

        let mut buffer = Vec::new();
        encoder
            .encode(&metric_families, &mut buffer)
            .context("Failed to encode metrics")?;

        String::from_utf8(buffer).context("Failed to convert metrics to UTF-8")
    }
}

// ============================================
// Convenience Functions (Global Access)
// ============================================

/// Record an LLM request (convenience function)
pub fn record_llm_request(
    provider: &str,
    tier: &str,
    status: &str,
    duration: Duration,
    tokens_in: u64,
    tokens_out: u64,
    cost_usd: f64,
) {
    METRICS.record_llm_request(provider, tier, status, duration, tokens_in, tokens_out, cost_usd);
}

/// Record LLM cache hit/miss
pub fn record_llm_cache(hit: bool) {
    METRICS.record_llm_cache(hit);
}

/// Record memory query
pub fn record_memory_query(source: &str, status: &str, duration: Duration) {
    METRICS.record_memory_query(source, status, duration);
}

/// Set memory index size
pub fn set_memory_index_size(index_type: &str, size: i64) {
    METRICS.set_memory_index_size(index_type, size);
}

/// Set Qdrant health status
pub fn set_qdrant_health(healthy: bool) {
    METRICS.set_qdrant_health(healthy);
}

/// Record pipeline start
pub fn record_pipeline_start() {
    METRICS.record_pipeline_start();
}

/// Record pipeline end
pub fn record_pipeline_end(status: &str, duration: Duration) {
    METRICS.record_pipeline_end(status, duration);
}

/// Record pipeline stage
pub fn record_pipeline_stage(stage: &str, duration: Duration) {
    METRICS.record_pipeline_stage(stage, duration);
}

/// Increment active connections
pub fn increment_connections() {
    METRICS.increment_connections();
}

/// Decrement active connections
pub fn decrement_connections() {
    METRICS.decrement_connections();
}

/// Record rate limit hit
pub fn record_rate_limit_hit(identifier: &str) {
    METRICS.record_rate_limit_hit(identifier);
}

/// Record HTTP request
pub fn record_http_request(method: &str, endpoint: &str, status: u16, duration: Duration) {
    METRICS.record_http_request(method, endpoint, status, duration);
}

/// Export metrics
pub fn export_metrics() -> Result<String> {
    METRICS.export()
}

// ============================================
// Axum Integration
// ============================================

/// Create Axum router for metrics endpoints.
/// The routes themselves are stateless, but making the router generic lets it
/// merge cleanly into services that already carry application state.
pub fn metrics_router<S>() -> Router<S>
where
    S: Clone + Send + Sync + 'static,
{
    Router::new()
        .route("/metrics", get(prometheus_handler))
        .route("/metrics/health", get(metrics_health_handler))
}

/// Prometheus metrics handler - exports in Prometheus text format
async fn prometheus_handler() -> Result<Response, StatusCode> {
    match export_metrics() {
        Ok(metrics) => Ok(Response::builder()
            .status(StatusCode::OK)
            .header("Content-Type", "text/plain; version=0.0.4; charset=utf-8")
            .body(metrics)
            .unwrap()
            .into_response()),
        Err(e) => {
            error!("Failed to export metrics: {}", e);
            Err(StatusCode::INTERNAL_SERVER_ERROR)
        }
    }
}

/// Metrics health check
async fn metrics_health_handler() -> impl IntoResponse {
    let report = METRICS.get_cardinality_report().await;
    let metrics_count = prometheus::gather().len();

    axum::Json(serde_json::json!({
        "healthy": true,
        "metrics_count": metrics_count,
        "cardinality": report,
    }))
}

/// Middleware for automatic HTTP metrics collection
pub async fn metrics_middleware(
    req: axum::extract::Request,
    next: axum::middleware::Next,
) -> impl IntoResponse {
    let method = req.method().to_string();
    let path = req.uri().path().to_string();
    let start = Instant::now();

    // Increment active connections
    increment_connections();

    let response = next.run(req).await;

    // Decrement active connections
    decrement_connections();

    let duration = start.elapsed();
    let status = response.status().as_u16();

    // Record the request
    record_http_request(&method, &path, status, duration);

    response
}

// ============================================
// Timer Helper
// ============================================

/// Timer for measuring operation duration
pub struct MetricsTimer {
    start: Instant,
    recorded: bool,
}

impl MetricsTimer {
    /// Create a new timer
    pub fn new() -> Self {
        Self {
            start: Instant::now(),
            recorded: false,
        }
    }

    /// Get elapsed time
    pub fn elapsed(&self) -> Duration {
        self.start.elapsed()
    }
}

impl Default for MetricsTimer {
    fn default() -> Self {
        Self::new()
    }
}

// ============================================
// Tests
// ============================================

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_metrics_collector_creation() {
        let config = MetricsConfig::default();
        let collector = MetricsCollector::new(config);
        // Just verify it doesn't panic
    }

    #[test]
    fn test_llm_metrics_recording() {
        METRICS.record_llm_request(
            "grok",
            "standard",
            "success",
            Duration::from_secs(2),
            100,
            150,
            0.005,
        );

        // Verify metrics were recorded
        let families = prometheus::gather();
        assert!(families
            .iter()
            .any(|f| f.get_name() == "beagle_llm_requests_total"));
        assert!(families
            .iter()
            .any(|f| f.get_name() == "beagle_llm_tokens_total"));
        assert!(families
            .iter()
            .any(|f| f.get_name() == "beagle_llm_cost_usd_total"));
    }

    #[test]
    fn test_memory_metrics_recording() {
        METRICS.record_memory_query("qdrant", "success", Duration::from_millis(50));
        METRICS.set_memory_index_size("embeddings", 1000);
        METRICS.set_qdrant_health(true);

        let families = prometheus::gather();
        assert!(families
            .iter()
            .any(|f| f.get_name() == "beagle_memory_queries_total"));
        assert!(families
            .iter()
            .any(|f| f.get_name() == "beagle_memory_index_size"));
        assert!(families
            .iter()
            .any(|f| f.get_name() == "beagle_qdrant_health_status"));
    }

    #[test]
    fn test_pipeline_metrics_recording() {
        METRICS.record_pipeline_start();
        METRICS.record_pipeline_stage("ingest", Duration::from_secs(1));
        METRICS.record_pipeline_end("success", Duration::from_secs(10));

        let families = prometheus::gather();
        assert!(families
            .iter()
            .any(|f| f.get_name() == "beagle_pipeline_runs_total"));
        assert!(families
            .iter()
            .any(|f| f.get_name() == "beagle_pipeline_stages_duration_seconds"));
    }

    #[test]
    fn test_system_metrics_recording() {
        METRICS.increment_connections();
        METRICS.record_rate_limit_hit("api_key_123");
        METRICS.decrement_connections();

        let families = prometheus::gather();
        assert!(families
            .iter()
            .any(|f| f.get_name() == "beagle_active_connections"));
        assert!(families
            .iter()
            .any(|f| f.get_name() == "beagle_rate_limit_hits_total"));
    }

    #[test]
    fn test_export_metrics() {
        // Record some data
        METRICS.record_llm_request(
            "grok",
            "standard",
            "success",
            Duration::from_secs(1),
            50,
            100,
            0.002,
        );

        // Export and verify format
        let output = export_metrics().unwrap();
        assert!(output.contains("beagle_llm_requests_total"));
        assert!(output.contains("# HELP"));
        assert!(output.contains("# TYPE"));
    }
}
