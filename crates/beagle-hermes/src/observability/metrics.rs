//! Prometheus Metrics

use lazy_static::lazy_static;
use prometheus::{
    register_histogram_vec, register_int_counter_vec, register_int_gauge_vec, HistogramOpts,
    HistogramVec, IntCounterVec, IntGaugeVec, Opts,
};

lazy_static! {
    // Manuscripts
    pub static ref MANUSCRIPTS_TOTAL: IntGaugeVec = register_int_gauge_vec!(
        Opts::new(
            "hermes_manuscripts_total",
            "Total manuscripts by state"
        ),
        &["state"]
    ).unwrap();

    // Insights
    pub static ref INSIGHTS_TOTAL: IntCounterVec = register_int_counter_vec!(
        Opts::new(
            "hermes_insights_total",
            "Total insights captured"
        ),
        &["source"]
    ).unwrap();

    // Synthesis jobs
    pub static ref SYNTHESIS_TOTAL: IntCounterVec = register_int_counter_vec!(
        Opts::new(
            "hermes_synthesis_total",
            "Total synthesis jobs"
        ),
        &["status"]
    ).unwrap();

    pub static ref SYNTHESIS_SUCCESS_TOTAL: IntCounterVec = register_int_counter_vec!(
        Opts::new(
            "hermes_synthesis_success_total",
            "Successful synthesis jobs"
        ),
        &["cluster"]
    ).unwrap();

    // Latency
    pub static ref API_LATENCY: HistogramVec = register_histogram_vec!(
        HistogramOpts::new(
            "hermes_api_latency_seconds",
            "API endpoint latency"
        ),
        &["endpoint", "method"]
    ).unwrap();

    // LLM calls
    pub static ref LLM_CALLS_TOTAL: IntCounterVec = register_int_counter_vec!(
        Opts::new(
            "hermes_llm_calls_total",
            "Total LLM API calls"
        ),
        &["model", "status"]
    ).unwrap();

    pub static ref LLM_TOKENS_TOTAL: IntCounterVec = register_int_counter_vec!(
        Opts::new(
            "hermes_llm_tokens_total",
            "Total tokens consumed"
        ),
        &["model", "type"]
    ).unwrap();
}

/// Initialize metrics
pub fn init_metrics() {
    // Register all metrics (lazy_static handles registration)
    let _ = &*MANUSCRIPTS_TOTAL;
    let _ = &*INSIGHTS_TOTAL;
    let _ = &*SYNTHESIS_TOTAL;
    let _ = &*SYNTHESIS_SUCCESS_TOTAL;
    let _ = &*API_LATENCY;
    let _ = &*LLM_CALLS_TOTAL;
    let _ = &*LLM_TOKENS_TOTAL;

    tracing::info!("✅ Prometheus metrics initialized");
}

/// Expose metrics endpoint
pub async fn metrics_handler() -> String {
    use prometheus::{Encoder, TextEncoder};

    let encoder = TextEncoder::new();
    let metric_families = prometheus::gather();

    let mut buffer = Vec::new();
    encoder.encode(&metric_families, &mut buffer).unwrap();

    String::from_utf8(buffer).unwrap()
}

/// Helper to record insight capture
pub fn record_insight_captured(source: &str) {
    INSIGHTS_TOTAL.with_label_values(&[source]).inc();
}

/// Helper to record synthesis job
pub fn record_synthesis(status: &str, cluster: Option<&str>) {
    SYNTHESIS_TOTAL.with_label_values(&[status]).inc();
    if status == "success" {
        let cluster_label = cluster.unwrap_or("unknown");
        SYNTHESIS_SUCCESS_TOTAL
            .with_label_values(&[cluster_label])
            .inc();
    }
}

/// Helper to record LLM call
pub fn record_llm_call(model: &str, status: &str) {
    LLM_CALLS_TOTAL.with_label_values(&[model, status]).inc();
}

/// Helper to record LLM tokens
pub fn record_llm_tokens(model: &str, token_type: &str, count: u64) {
    LLM_TOKENS_TOTAL
        .with_label_values(&[model, token_type])
        .inc_by(count);
}

/// Helper to record API latency
pub fn record_api_latency(endpoint: &str, method: &str, duration_seconds: f64) {
    API_LATENCY
        .with_label_values(&[endpoint, method])
        .observe(duration_seconds);
}

/// Helper to update manuscript count
pub fn update_manuscript_count(state: &str, count: i64) {
    MANUSCRIPTS_TOTAL.with_label_values(&[state]).set(count);
}
