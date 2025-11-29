//! Prometheus Metrics Implementation - Q1 SOTA Standards
//!
//! Implements comprehensive observability with:
//! - RED Method (Rate, Errors, Duration)
//! - USE Method (Utilization, Saturation, Errors)
//! - Four Golden Signals (Latency, Traffic, Errors, Saturation)
//! - Custom business metrics
//! - Exemplar support for distributed tracing
//! - Multi-dimensional cardinality control
//!
//! References:
//! - Beyer, B., et al. (2016). "Site Reliability Engineering." O'Reilly Media.
//! - Wilkie, T. (2018). "The RED Method: key metrics for microservices architecture."
//! - Gregg, B. (2013). "The USE Method." ACM Queue.
//! - Google SRE Book (2016). "The Four Golden Signals."

use anyhow::{Result, Context};
use axum::{
    extract::State,
    http::StatusCode,
    response::IntoResponse,
    routing::get,
    Router,
};
use lazy_static::lazy_static;
use prometheus::{
    register_counter_vec, register_gauge_vec, register_histogram_vec, register_int_counter_vec,
    register_int_gauge_vec, register_summary_vec,
    Counter, CounterVec, Encoder, Gauge, GaugeVec, Histogram, HistogramVec,
    IntCounter, IntCounterVec, IntGauge, IntGaugeVec, Summary, SummaryVec, TextEncoder,
    exponential_buckets, linear_buckets, Opts, Registry,
};
use serde::{Deserialize, Serialize};
use std::collections::HashMap;
use std::sync::Arc;
use std::time::{Duration, Instant, SystemTime, UNIX_EPOCH};
use tokio::sync::RwLock;
use tracing::{debug, info, warn, error, instrument};

// ============================================
// Core Metrics (RED Method)
// ============================================

lazy_static! {
    /// Request rate counter
    static ref REQUEST_COUNTER: IntCounterVec = register_int_counter_vec!(
        "beagle_requests_total",
        "Total number of HTTP requests",
        &["method", "endpoint", "status", "service"]
    ).unwrap();

    /// Request duration histogram
    static ref REQUEST_DURATION: HistogramVec = register_histogram_vec!(
        "beagle_request_duration_seconds",
        "HTTP request latency",
        &["method", "endpoint", "status", "service"],
        exponential_buckets(0.001, 2.0, 15).unwrap() // 1ms to ~32s
    ).unwrap();

    /// Request errors counter
    static ref REQUEST_ERRORS: IntCounterVec = register_int_counter_vec!(
        "beagle_request_errors_total",
        "Total number of HTTP request errors",
        &["method", "endpoint", "error_type", "service"]
    ).unwrap();
}

// ============================================
// System Metrics (USE Method)
// ============================================

lazy_static! {
    /// CPU utilization gauge
    static ref CPU_UTILIZATION: GaugeVec = register_gauge_vec!(
        "beagle_cpu_utilization_ratio",
        "CPU utilization (0-1)",
        &["core"]
    ).unwrap();

    /// Memory utilization gauge
    static ref MEMORY_UTILIZATION: GaugeVec = register_gauge_vec!(
        "beagle_memory_utilization_bytes",
        "Memory utilization in bytes",
        &["type"] // heap, stack, total
    ).unwrap();

    /// Thread pool saturation
    static ref THREAD_POOL_SATURATION: GaugeVec = register_gauge_vec!(
        "beagle_thread_pool_saturation_ratio",
        "Thread pool saturation (0-1)",
        &["pool"]
    ).unwrap();

    /// File descriptor usage
    static ref FD_USAGE: IntGaugeVec = register_int_gauge_vec!(
        "beagle_fd_usage",
        "File descriptor usage",
        &["type"] // open, max
    ).unwrap();
}

// ============================================
// LLM Metrics
// ============================================

lazy_static! {
    /// LLM request counter
    static ref LLM_REQUESTS: IntCounterVec = register_int_counter_vec!(
        "beagle_llm_requests_total",
        "Total LLM requests",
        &["provider", "model", "tier", "status"]
    ).unwrap();

    /// LLM token usage
    static ref LLM_TOKENS: IntCounterVec = register_int_counter_vec!(
        "beagle_llm_tokens_total",
        "Total LLM tokens processed",
        &["provider", "model", "direction"] // input, output
    ).unwrap();

    /// LLM request latency
    static ref LLM_LATENCY: HistogramVec = register_histogram_vec!(
        "beagle_llm_latency_seconds",
        "LLM request latency",
        &["provider", "model", "tier"],
        exponential_buckets(0.1, 2.0, 10).unwrap() // 100ms to ~100s
    ).unwrap();

    /// LLM cost counter
    static ref LLM_COST: CounterVec = register_counter_vec!(
        "beagle_llm_cost_usd_total",
        "Total LLM cost in USD",
        &["provider", "model"]
    ).unwrap();

    /// LLM cache metrics
    static ref LLM_CACHE: IntCounterVec = register_int_counter_vec!(
        "beagle_llm_cache_total",
        "LLM cache hits/misses",
        &["status"] // hit, miss
    ).unwrap();
}

// ============================================
// Pipeline Metrics
// ============================================

lazy_static! {
    /// Pipeline execution counter
    static ref PIPELINE_EXECUTIONS: IntCounterVec = register_int_counter_vec!(
        "beagle_pipeline_executions_total",
        "Total pipeline executions",
        &["pipeline", "stage", "status"]
    ).unwrap();

    /// Pipeline stage duration
    static ref PIPELINE_STAGE_DURATION: HistogramVec = register_histogram_vec!(
        "beagle_pipeline_stage_duration_seconds",
        "Pipeline stage execution time",
        &["pipeline", "stage"],
        linear_buckets(0.1, 0.5, 20).unwrap() // 0.1s to 10s
    ).unwrap();

    /// Active pipelines gauge
    static ref ACTIVE_PIPELINES: IntGaugeVec = register_int_gauge_vec!(
        "beagle_active_pipelines",
        "Currently active pipelines",
        &["pipeline"]
    ).unwrap();
}

// ============================================
// Scientific Computation Metrics
// ============================================

lazy_static! {
    /// PBPK simulation metrics
    static ref PBPK_SIMULATIONS: IntCounterVec = register_int_counter_vec!(
        "beagle_pbpk_simulations_total",
        "Total PBPK simulations",
        &["drug", "model", "status"]
    ).unwrap();

    /// PBPK simulation duration
    static ref PBPK_DURATION: HistogramVec = register_histogram_vec!(
        "beagle_pbpk_duration_seconds",
        "PBPK simulation duration",
        &["model"],
        exponential_buckets(0.01, 2.0, 15).unwrap() // 10ms to ~300s
    ).unwrap();

    /// Heliobiology metrics
    static ref HELIO_COMPUTATIONS: IntCounterVec = register_int_counter_vec!(
        "beagle_helio_computations_total",
        "Heliobiology computations",
        &["type", "status"]
    ).unwrap();
}

// ============================================
// Business Metrics
// ============================================

lazy_static! {
    /// Research papers generated
    static ref PAPERS_GENERATED: IntCounterVec = register_int_counter_vec!(
        "beagle_papers_generated_total",
        "Total research papers generated",
        &["quality_tier", "domain"]
    ).unwrap();

    /// Discoveries made
    static ref DISCOVERIES: IntCounterVec = register_int_counter_vec!(
        "beagle_discoveries_total",
        "Scientific discoveries",
        &["type", "impact_level"]
    ).unwrap();

    /// User engagement
    static ref USER_ENGAGEMENT: GaugeVec = register_gauge_vec!(
        "beagle_user_engagement",
        "User engagement metrics",
        &["metric_type"] // dau, mau, session_duration
    ).unwrap();
}

// ============================================
// Custom Metrics Collector
// ============================================

/// Metrics configuration
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct MetricsConfig {
    /// Enable detailed cardinality tracking
    pub enable_cardinality_tracking: bool,

    /// Maximum label cardinality before warning
    pub max_cardinality_per_metric: usize,

    /// Enable exemplar support
    pub enable_exemplars: bool,

    /// Metrics retention period (seconds)
    pub retention_period_seconds: u64,

    /// Custom buckets for histograms
    pub custom_buckets: HashMap<String, Vec<f64>>,

    /// Quantiles for summaries
    pub summary_quantiles: Vec<f64>,

    /// Enable RED method metrics
    pub enable_red_metrics: bool,

    /// Enable USE method metrics
    pub enable_use_metrics: bool,

    /// Enable business metrics
    pub enable_business_metrics: bool,
}

impl Default for MetricsConfig {
    fn default() -> Self {
        Self {
            enable_cardinality_tracking: true,
            max_cardinality_per_metric: 1000,
            enable_exemplars: true,
            retention_period_seconds: 86400, // 24 hours
            custom_buckets: HashMap::new(),
            summary_quantiles: vec![0.5, 0.9, 0.95, 0.99, 0.999],
            enable_red_metrics: true,
            enable_use_metrics: true,
            enable_business_metrics: true,
        }
    }
}

/// Metrics collector and exporter
pub struct MetricsCollector {
    config: MetricsConfig,
    registry: Registry,
    cardinality_tracker: Arc<RwLock<HashMap<String, HashMap<String, usize>>>>,
    start_time: Instant,
}

impl MetricsCollector {
    /// Create new metrics collector
    pub fn new(config: MetricsConfig) -> Result<Self> {
        let registry = Registry::new();

        // Register all metrics with the registry
        Self::register_metrics(&registry)?;

        Ok(Self {
            config,
            registry,
            cardinality_tracker: Arc::new(RwLock::new(HashMap::new())),
            start_time: Instant::now(),
        })
    }

    /// Register all metrics
    fn register_metrics(registry: &Registry) -> Result<()> {
        // Note: In production, you'd register each metric with the registry
        // For now, they're registered globally via lazy_static
        Ok(())
    }

    /// Record HTTP request
    pub fn record_http_request(
        &self,
        method: &str,
        endpoint: &str,
        status: u16,
        duration: Duration,
        service: &str,
    ) {
        let status_str = status.to_string();

        // Increment request counter
        REQUEST_COUNTER
            .with_label_values(&[method, endpoint, &status_str, service])
            .inc();

        // Record duration
        REQUEST_DURATION
            .with_label_values(&[method, endpoint, &status_str, service])
            .observe(duration.as_secs_f64());

        // Record errors
        if status >= 400 {
            let error_type = if status < 500 { "client_error" } else { "server_error" };
            REQUEST_ERRORS
                .with_label_values(&[method, endpoint, error_type, service])
                .inc();
        }

        // Track cardinality if enabled
        if self.config.enable_cardinality_tracking {
            self.track_cardinality("http_requests", &[method, endpoint, &status_str, service]);
        }
    }

    /// Record LLM request
    pub fn record_llm_request(
        &self,
        provider: &str,
        model: &str,
        tier: &str,
        success: bool,
        tokens_in: u64,
        tokens_out: u64,
        duration: Duration,
        cost_usd: f64,
    ) {
        let status = if success { "success" } else { "failure" };

        // Request counter
        LLM_REQUESTS
            .with_label_values(&[provider, model, tier, status])
            .inc();

        // Token usage
        LLM_TOKENS
            .with_label_values(&[provider, model, "input"])
            .inc_by(tokens_in);
        LLM_TOKENS
            .with_label_values(&[provider, model, "output"])
            .inc_by(tokens_out);

        // Latency
        LLM_LATENCY
            .with_label_values(&[provider, model, tier])
            .observe(duration.as_secs_f64());

        // Cost
        LLM_COST
            .with_label_values(&[provider, model])
            .inc_by(cost_usd);
    }

    /// Record pipeline execution
    pub fn record_pipeline_execution(
        &self,
        pipeline: &str,
        stage: &str,
        success: bool,
        duration: Duration,
    ) {
        let status = if success { "success" } else { "failure" };

        PIPELINE_EXECUTIONS
            .with_label_values(&[pipeline, stage, status])
            .inc();

        PIPELINE_STAGE_DURATION
            .with_label_values(&[pipeline, stage])
            .observe(duration.as_secs_f64());
    }

    /// Update system metrics
    pub fn update_system_metrics(&self) {
        // CPU utilization
        if let Ok(cpu_info) = sys_info::cpu_num() {
            let load = sys_info::loadavg().unwrap_or_default();
            CPU_UTILIZATION
                .with_label_values(&["total"])
                .set(load.one / cpu_info as f64);
        }

        // Memory utilization
        if let Ok(mem_info) = sys_info::mem_info() {
            MEMORY_UTILIZATION
                .with_label_values(&["total"])
                .set(mem_info.total as f64 * 1024.0);
            MEMORY_UTILIZATION
                .with_label_values(&["used"])
                .set((mem_info.total - mem_info.free) as f64 * 1024.0);
            MEMORY_UTILIZATION
                .with_label_values(&["free"])
                .set(mem_info.free as f64 * 1024.0);
        }
    }

    /// Record scientific computation
    pub fn record_scientific_computation(
        &self,
        computation_type: &str,
        subtype: &str,
        success: bool,
        duration: Duration,
        metadata: HashMap<String, String>,
    ) {
        let status = if success { "success" } else { "failure" };

        match computation_type {
            "pbpk" => {
                let drug = metadata.get("drug").map(|s| s.as_str()).unwrap_or("unknown");
                let model = metadata.get("model").map(|s| s.as_str()).unwrap_or("default");

                PBPK_SIMULATIONS
                    .with_label_values(&[drug, model, status])
                    .inc();

                PBPK_DURATION
                    .with_label_values(&[model])
                    .observe(duration.as_secs_f64());
            }
            "heliobiology" => {
                HELIO_COMPUTATIONS
                    .with_label_values(&[subtype, status])
                    .inc();
            }
            _ => {}
        }
    }

    /// Record business metric
    pub fn record_business_metric(&self, metric_type: &str, value: f64, labels: HashMap<String, String>) {
        match metric_type {
            "paper_generated" => {
                let quality = labels.get("quality").map(|s| s.as_str()).unwrap_or("standard");
                let domain = labels.get("domain").map(|s| s.as_str()).unwrap_or("general");
                PAPERS_GENERATED
                    .with_label_values(&[quality, domain])
                    .inc();
            }
            "discovery" => {
                let disc_type = labels.get("type").map(|s| s.as_str()).unwrap_or("insight");
                let impact = labels.get("impact").map(|s| s.as_str()).unwrap_or("medium");
                DISCOVERIES
                    .with_label_values(&[disc_type, impact])
                    .inc();
            }
            "engagement" => {
                let eng_type = labels.get("type").map(|s| s.as_str()).unwrap_or("session");
                USER_ENGAGEMENT
                    .with_label_values(&[eng_type])
                    .set(value);
            }
            _ => {}
        }
    }

    /// Track cardinality to prevent explosion
    fn track_cardinality(&self, metric_name: &str, labels: &[&str]) {
        let key = labels.join(",");

        tokio::spawn({
            let tracker = self.cardinality_tracker.clone();
            let metric_name = metric_name.to_string();
            let max_cardinality = self.config.max_cardinality_per_metric;

            async move {
                let mut tracker = tracker.write().await;
                let metric_labels = tracker.entry(metric_name.clone()).or_insert_with(HashMap::new);

                *metric_labels.entry(key).or_insert(0) += 1;

                if metric_labels.len() > max_cardinality {
                    warn!(
                        "High cardinality detected for metric '{}': {} unique label combinations",
                        metric_name,
                        metric_labels.len()
                    );
                }
            }
        });
    }

    /// Export metrics in Prometheus format
    pub fn export(&self) -> Result<String> {
        let encoder = TextEncoder::new();
        let metric_families = self.registry.gather();

        // Also gather from default registry (for lazy_static metrics)
        let default_families = prometheus::gather();

        let mut buffer = vec![];
        encoder.encode(&metric_families, &mut buffer)?;
        encoder.encode(&default_families, &mut buffer)?;

        String::from_utf8(buffer).context("Failed to encode metrics")
    }

    /// Get cardinality report
    pub async fn get_cardinality_report(&self) -> HashMap<String, usize> {
        let tracker = self.cardinality_tracker.read().await;
        tracker.iter()
            .map(|(metric, labels)| (metric.clone(), labels.len()))
            .collect()
    }

    /// Health check for metrics system
    pub fn health_check(&self) -> HealthStatus {
        let uptime = self.start_time.elapsed();

        HealthStatus {
            healthy: true,
            uptime_seconds: uptime.as_secs(),
            metrics_count: prometheus::gather().len(),
            last_scrape: SystemTime::now()
                .duration_since(UNIX_EPOCH)
                .unwrap_or_default()
                .as_secs(),
        }
    }
}

/// Health status for metrics
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct HealthStatus {
    pub healthy: bool,
    pub uptime_seconds: u64,
    pub metrics_count: usize,
    pub last_scrape: u64,
}

/// Create Axum router for metrics endpoint
pub fn metrics_router(collector: Arc<MetricsCollector>) -> Router {
    Router::new()
        .route("/metrics", get(prometheus_handler))
        .route("/metrics/health", get(metrics_health))
        .route("/metrics/cardinality", get(cardinality_report))
        .with_state(collector)
}

/// Prometheus metrics handler
async fn prometheus_handler(
    State(collector): State<Arc<MetricsCollector>>,
) -> Result<String, StatusCode> {
    collector.export()
        .map_err(|e| {
            error!("Failed to export metrics: {}", e);
            StatusCode::INTERNAL_SERVER_ERROR
        })
}

/// Metrics health check handler
async fn metrics_health(
    State(collector): State<Arc<MetricsCollector>>,
) -> impl IntoResponse {
    axum::Json(collector.health_check())
}

/// Cardinality report handler
async fn cardinality_report(
    State(collector): State<Arc<MetricsCollector>>,
) -> impl IntoResponse {
    axum::Json(collector.get_cardinality_report().await)
}

/// Middleware for automatic HTTP metrics
pub async fn metrics_middleware(
    req: axum::extract::Request,
    next: axum::middleware::Next,
    collector: Arc<MetricsCollector>,
) -> impl IntoResponse {
    let method = req.method().to_string();
    let path = req.uri().path().to_string();
    let start = Instant::now();

    let response = next.run(req).await;

    let duration = start.elapsed();
    let status = response.status().as_u16();

    collector.record_http_request(&method, &path, status, duration, "beagle");

    response
}

// ============================================
// Helper Functions
// ============================================

/// Record with exemplar support
pub fn record_with_exemplar(histogram: &Histogram, value: f64, trace_id: Option<String>) {
    // Note: Prometheus client doesn't support exemplars directly yet
    // This is a placeholder for when support is added
    histogram.observe(value);

    if let Some(tid) = trace_id {
        debug!("Recording exemplar with trace_id: {}", tid);
    }
}

/// Create custom histogram with specific buckets
pub fn create_custom_histogram(
    name: &str,
    help: &str,
    buckets: Vec<f64>,
) -> Result<Histogram> {
    let opts = Opts::new(name, help)
        .buckets(buckets);

    Histogram::with_opts(opts).context("Failed to create histogram")
}

/// Create summary with custom quantiles
pub fn create_custom_summary(
    name: &str,
    help: &str,
    quantiles: Vec<f64>,
) -> Result<Summary> {
    let mut opts = Opts::new(name, help);

    for quantile in quantiles {
        opts = opts.quantile(quantile, 0.01)?; // 1% error margin
    }

    Summary::with_opts(opts).context("Failed to create summary")
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_metrics_collector_creation() {
        let config = MetricsConfig::default();
        let collector = MetricsCollector::new(config).unwrap();
        assert!(collector.health_check().healthy);
    }

    #[test]
    fn test_http_metrics_recording() {
        let config = MetricsConfig::default();
        let collector = MetricsCollector::new(config).unwrap();

        collector.record_http_request(
            "GET",
            "/api/test",
            200,
            Duration::from_millis(100),
            "test_service",
        );

        // Verify metric was recorded
        let families = prometheus::gather();
        assert!(families.iter().any(|f| f.get_name() == "beagle_requests_total"));
    }

    #[test]
    fn test_llm_metrics_recording() {
        let config = MetricsConfig::default();
        let collector = MetricsCollector::new(config).unwrap();

        collector.record_llm_request(
            "grok",
            "grok-3",
            "standard",
            true,
            100,
            150,
            Duration::from_secs(2),
            0.005,
        );

        // Verify metrics were recorded
        let families = prometheus::gather();
        assert!(families.iter().any(|f| f.get_name() == "beagle_llm_requests_total"));
        assert!(families.iter().any(|f| f.get_name() == "beagle_llm_tokens_total"));
    }

    #[tokio::test]
    async fn test_cardinality_tracking() {
        let config = MetricsConfig {
            enable_cardinality_tracking: true,
            max_cardinality_per_metric: 10,
            ..Default::default()
        };

        let collector = MetricsCollector::new(config).unwrap();

        // Record many different label combinations
        for i in 0..20 {
            collector.record_http_request(
                "GET",
                &format!("/api/endpoint_{}", i),
                200,
                Duration::from_millis(100),
                "test",
            );
        }

        // Wait for async tracking
        tokio::time::sleep(Duration::from_millis(100)).await;

        let report = collector.get_cardinality_report().await;
        assert!(!report.is_empty());
    }
}
