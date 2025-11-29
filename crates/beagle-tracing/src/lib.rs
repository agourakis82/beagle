//! Distributed Tracing with OpenTelemetry - Q1 SOTA Observability
//!
//! References:
//! - Shkuro, Y. (2019). Mastering Distributed Tracing. Packt Publishing.
//! - Sigelman, B. H., et al. (2010). Dapper, a Large-Scale Distributed Systems Tracing Infrastructure. Google.
//! - OpenTelemetry Specification v1.26.0
//! - Jaeger: Open source, end-to-end distributed tracing (CNCF)

use opentelemetry::{
    global,
    trace::{SpanKind, Status, TraceContextExt, TraceError, Tracer},
    Context as OtelContext, KeyValue,
};
use opentelemetry_otlp::WithExportConfig;
use opentelemetry_sdk::{
    propagation::TraceContextPropagator,
    trace::{self, RandomIdGenerator, Sampler},
    Resource,
};
use opentelemetry_semantic_conventions::resource::{
    DEPLOYMENT_ENVIRONMENT, SERVICE_NAME, SERVICE_NAMESPACE, SERVICE_VERSION,
};
use tracing::{error, info, instrument, span, Level, Span};

use dashmap::DashMap;
use parking_lot::RwLock;
use serde::{Deserialize, Serialize};
use std::collections::HashMap;
use std::sync::Arc;
use std::time::{Duration, SystemTime};
use thiserror::Error;
use uuid::Uuid;

#[cfg(feature = "axum-integration")]
pub mod axum_integration;

#[cfg(feature = "sqlx-integration")]
pub mod sqlx_integration;

// ========================= Error Types =========================

#[derive(Error, Debug)]
pub enum TracingError {
    #[error("Failed to initialize tracer: {0}")]
    InitializationError(String),

    #[error("Failed to export spans: {0}")]
    ExportError(String),

    #[error("Sampling error: {0}")]
    SamplingError(String),

    #[error("Propagation error: {0}")]
    PropagationError(String),

    #[error("OpenTelemetry error: {0}")]
    OtelError(#[from] TraceError),
}

pub type Result<T> = std::result::Result<T, TracingError>;

// ========================= Configuration =========================

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct TracingConfig {
    pub service_name: String,
    pub service_namespace: String,
    pub service_version: String,
    pub environment: String,
    pub jaeger_endpoint: String,
    pub otlp_endpoint: Option<String>,
    pub sampling_rate: f64,
    pub batch_size: usize,
    pub export_timeout_ms: u64,
    pub max_attributes_per_span: u32,
    pub max_events_per_span: u32,
    pub max_links_per_span: u32,
    pub enable_console_exporter: bool,
    pub enable_jaeger_exporter: bool,
    pub enable_otlp_exporter: bool,
    pub propagators: Vec<String>,
}

impl Default for TracingConfig {
    fn default() -> Self {
        Self {
            service_name: "beagle".to_string(),
            service_namespace: "beagle".to_string(),
            service_version: env!("CARGO_PKG_VERSION").to_string(),
            environment: "development".to_string(),
            jaeger_endpoint: "http://localhost:14268/api/traces".to_string(),
            otlp_endpoint: Some("http://localhost:4317".to_string()),
            sampling_rate: 0.1, // 10% sampling by default
            batch_size: 512,
            export_timeout_ms: 30000,
            max_attributes_per_span: 128,
            max_events_per_span: 128,
            max_links_per_span: 128,
            enable_console_exporter: false,
            enable_jaeger_exporter: true,
            enable_otlp_exporter: false,
            propagators: vec!["tracecontext".to_string(), "baggage".to_string()],
        }
    }
}

// ========================= Adaptive Sampling =========================

pub trait SamplingStrategy: Send + Sync {
    fn should_sample(&self, attributes: &[KeyValue]) -> bool;
    fn update_rate(&mut self, new_rate: f64);
}

pub struct AdaptiveSampler {
    base_rate: f64,
    current_rate: Arc<RwLock<f64>>,
    error_boost: f64,
    latency_threshold_ms: u64,
    priority_operations: Arc<DashMap<String, f64>>,
}

impl AdaptiveSampler {
    pub fn new(base_rate: f64, error_boost: f64, latency_threshold_ms: u64) -> Self {
        let priority_ops = DashMap::new();

        // High-priority operations always sampled
        priority_ops.insert("llm.complete".to_string(), 1.0);
        priority_ops.insert("triad.debate".to_string(), 1.0);
        priority_ops.insert("scientific.compute".to_string(), 1.0);
        priority_ops.insert("websocket.sync".to_string(), 0.5);

        Self {
            base_rate,
            current_rate: Arc::new(RwLock::new(base_rate)),
            error_boost,
            latency_threshold_ms,
            priority_operations: Arc::new(priority_ops),
        }
    }

    pub fn adjust_rate_based_on_load(&self, requests_per_second: f64) {
        // Reduce sampling rate under high load
        let new_rate = if requests_per_second > 10000.0 {
            0.001 // 0.1% for very high load
        } else if requests_per_second > 1000.0 {
            0.01 // 1% for high load
        } else if requests_per_second > 100.0 {
            0.1 // 10% for moderate load
        } else {
            self.base_rate // Base rate for low load
        };

        *self.current_rate.write() = new_rate;
    }
}

impl SamplingStrategy for AdaptiveSampler {
    fn should_sample(&self, attributes: &[KeyValue]) -> bool {
        use opentelemetry::Value;

        // Check if it's a priority operation
        for attr in attributes {
            let key_str = attr.key.as_str();

            if key_str == "operation.name" {
                if let Value::String(op_name) = &attr.value {
                    if let Some(rate) = self.priority_operations.get(op_name.as_str()) {
                        return rand::random::<f64>() < *rate;
                    }
                }
            }

            // Always sample errors
            if key_str == "error" {
                if let Value::Bool(true) = &attr.value {
                    return true;
                }
            }

            // Boost sampling for slow operations
            if key_str == "duration_ms" {
                if let Value::I64(duration) = &attr.value {
                    if *duration as u64 > self.latency_threshold_ms {
                        return rand::random::<f64>() < (*self.current_rate.read() * 10.0).min(1.0);
                    }
                }
            }
        }

        // Default sampling
        rand::random::<f64>() < *self.current_rate.read()
    }

    fn update_rate(&mut self, new_rate: f64) {
        self.base_rate = new_rate;
        *self.current_rate.write() = new_rate;
    }
}

// ========================= Trace Context Propagation =========================

#[derive(Debug, Clone)]
pub struct TraceContext {
    pub trace_id: String,
    pub span_id: String,
    pub parent_span_id: Option<String>,
    pub baggage: HashMap<String, String>,
    pub flags: u8,
}

impl TraceContext {
    pub fn new() -> Self {
        Self {
            trace_id: Uuid::new_v4().to_string(),
            span_id: Uuid::new_v4().to_string(),
            parent_span_id: None,
            baggage: HashMap::new(),
            flags: 1, // Sampled
        }
    }

    pub fn child(&self) -> Self {
        Self {
            trace_id: self.trace_id.clone(),
            span_id: Uuid::new_v4().to_string(),
            parent_span_id: Some(self.span_id.clone()),
            baggage: self.baggage.clone(),
            flags: self.flags,
        }
    }

    pub fn inject_into_headers(&self, headers: &mut HashMap<String, String>) {
        headers.insert("x-trace-id".to_string(), self.trace_id.clone());
        headers.insert("x-span-id".to_string(), self.span_id.clone());
        if let Some(parent) = &self.parent_span_id {
            headers.insert("x-parent-span-id".to_string(), parent.clone());
        }
        headers.insert("x-trace-flags".to_string(), self.flags.to_string());

        // Inject baggage
        for (key, value) in &self.baggage {
            headers.insert(format!("x-baggage-{}", key), value.clone());
        }
    }

    pub fn extract_from_headers(headers: &HashMap<String, String>) -> Option<Self> {
        let trace_id = headers.get("x-trace-id")?.clone();
        let span_id = headers.get("x-span-id")?.clone();
        let parent_span_id = headers.get("x-parent-span-id").cloned();
        let flags = headers
            .get("x-trace-flags")
            .and_then(|f| f.parse().ok())
            .unwrap_or(1);

        let mut baggage = HashMap::new();
        for (key, value) in headers {
            if key.starts_with("x-baggage-") {
                let baggage_key = key.strip_prefix("x-baggage-").unwrap();
                baggage.insert(baggage_key.to_string(), value.clone());
            }
        }

        Some(Self {
            trace_id,
            span_id,
            parent_span_id,
            baggage,
            flags,
        })
    }
}

impl Default for TraceContext {
    fn default() -> Self {
        Self::new()
    }
}

// ========================= Tracer Manager =========================

pub struct TracerManager {
    config: Arc<TracingConfig>,
    sampler: Arc<RwLock<Box<dyn SamplingStrategy>>>,
}

impl TracerManager {
    pub fn new(config: TracingConfig) -> Result<Self> {
        let sampler = AdaptiveSampler::new(
            config.sampling_rate,
            2.0,  // Error boost factor
            1000, // Latency threshold ms
        );

        Ok(Self {
            config: Arc::new(config),
            sampler: Arc::new(RwLock::new(Box::new(sampler))),
        })
    }

    #[instrument(skip(self))]
    pub async fn initialize(&self) -> Result<()> {
        // Set global propagator
        global::set_text_map_propagator(TraceContextPropagator::new());

        // Create resource
        let resource = Resource::new(vec![
            KeyValue::new(SERVICE_NAME, self.config.service_name.clone()),
            KeyValue::new(SERVICE_NAMESPACE, self.config.service_namespace.clone()),
            KeyValue::new(SERVICE_VERSION, self.config.service_version.clone()),
            KeyValue::new(DEPLOYMENT_ENVIRONMENT, self.config.environment.clone()),
        ]);

        // Create tracer provider config
        let config = trace::Config::default()
            .with_sampler(Sampler::AlwaysOn)
            .with_id_generator(RandomIdGenerator::default())
            .with_max_attributes_per_span(self.config.max_attributes_per_span)
            .with_max_events_per_span(self.config.max_events_per_span)
            .with_max_links_per_span(self.config.max_links_per_span)
            .with_resource(resource);

        // Create tracer provider with OTLP exporter
        let mut provider_builder =
            opentelemetry_sdk::trace::TracerProvider::builder().with_config(config);

        // Add OTLP exporter if enabled
        if self.config.enable_otlp_exporter {
            if let Some(endpoint) = &self.config.otlp_endpoint {
                let otlp_exporter = opentelemetry_otlp::new_exporter()
                    .tonic()
                    .with_endpoint(endpoint)
                    .with_timeout(Duration::from_millis(self.config.export_timeout_ms))
                    .build_span_exporter()
                    .map_err(|e| TracingError::InitializationError(e.to_string()))?;

                let batch_processor = opentelemetry_sdk::trace::BatchSpanProcessor::builder(
                    otlp_exporter,
                    opentelemetry_sdk::runtime::Tokio,
                )
                .with_max_queue_size(2048)
                .with_scheduled_delay(Duration::from_millis(5000))
                .with_max_export_batch_size(self.config.batch_size)
                .build();

                provider_builder = provider_builder.with_span_processor(batch_processor);
            }
        }

        // Build and set global provider
        let provider = provider_builder.build();
        global::set_tracer_provider(provider);

        info!(
            "Distributed tracing initialized with OTLP endpoint: {:?}",
            self.config.otlp_endpoint
        );

        Ok(())
    }

    pub fn create_span(&self, name: &str) -> Span {
        span!(
            Level::INFO,
            "beagle_span",
            name = %name,
            service.name = %self.config.service_name,
            service.version = %self.config.service_version,
        )
    }

    pub fn inject_context(&self, _span: &Span, headers: &mut HashMap<String, String>) {
        // Inject trace context into headers for propagation
        let ctx = TraceContext::new();
        ctx.inject_into_headers(headers);
    }

    pub fn shutdown(&self) {
        global::shutdown_tracer_provider();
        info!("Tracer provider shut down");
    }
}

// ========================= Span Enrichment =========================

pub trait SpanEnricher: Send + Sync {
    fn enrich(&self, span: &Span, metadata: &HashMap<String, String>);
}

pub struct LLMSpanEnricher;

impl SpanEnricher for LLMSpanEnricher {
    fn enrich(&self, span: &Span, metadata: &HashMap<String, String>) {
        span.record(
            "llm.provider",
            metadata
                .get("provider")
                .unwrap_or(&"unknown".to_string())
                .as_str(),
        );
        span.record(
            "llm.model",
            metadata
                .get("model")
                .unwrap_or(&"unknown".to_string())
                .as_str(),
        );

        if let Some(tokens) = metadata.get("tokens") {
            span.record("llm.tokens", tokens.as_str());
        }

        if let Some(tier) = metadata.get("tier") {
            span.record("llm.tier", tier.as_str());
        }
    }
}

pub struct WebSocketSpanEnricher;

impl SpanEnricher for WebSocketSpanEnricher {
    fn enrich(&self, span: &Span, metadata: &HashMap<String, String>) {
        span.record(
            "ws.client_id",
            metadata
                .get("client_id")
                .unwrap_or(&"unknown".to_string())
                .as_str(),
        );
        span.record(
            "ws.message_type",
            metadata
                .get("message_type")
                .unwrap_or(&"unknown".to_string())
                .as_str(),
        );

        if let Some(size) = metadata.get("message_size") {
            span.record("ws.message_size", size.as_str());
        }
    }
}

pub struct ScientificComputeEnricher;

impl SpanEnricher for ScientificComputeEnricher {
    fn enrich(&self, span: &Span, metadata: &HashMap<String, String>) {
        span.record(
            "compute.algorithm",
            metadata
                .get("algorithm")
                .unwrap_or(&"unknown".to_string())
                .as_str(),
        );

        if let Some(complexity) = metadata.get("complexity") {
            span.record("compute.complexity", complexity.as_str());
        }

        if let Some(iterations) = metadata.get("iterations") {
            span.record("compute.iterations", iterations.as_str());
        }
    }
}

// ========================= Integration Helpers =========================

pub fn record_error(span: &Span, error: &dyn std::error::Error) {
    span.record("error", true);
    span.record("error.type", std::any::type_name_of_val(error));
    span.record("error.message", &format!("{}", error));

    if let Some(source) = error.source() {
        span.record("error.source", &format!("{}", source));
    }
}

// ========================= Metrics Integration =========================

pub struct TracingMetrics {
    spans_created: prometheus::IntCounter,
    spans_ended: prometheus::IntCounter,
    spans_dropped: prometheus::IntCounter,
    export_duration: prometheus::Histogram,
    sampling_rate: prometheus::Gauge,
}

impl TracingMetrics {
    pub fn new() -> Self {
        Self {
            spans_created: prometheus::register_int_counter!(
                "tracing_spans_created_total",
                "Total number of spans created"
            )
            .unwrap(),

            spans_ended: prometheus::register_int_counter!(
                "tracing_spans_ended_total",
                "Total number of spans ended"
            )
            .unwrap(),

            spans_dropped: prometheus::register_int_counter!(
                "tracing_spans_dropped_total",
                "Total number of spans dropped"
            )
            .unwrap(),

            export_duration: prometheus::register_histogram!(
                "tracing_export_duration_seconds",
                "Duration of span export operations"
            )
            .unwrap(),

            sampling_rate: prometheus::register_gauge!(
                "tracing_sampling_rate",
                "Current sampling rate"
            )
            .unwrap(),
        }
    }

    pub fn record_span_created(&self) {
        self.spans_created.inc();
    }

    pub fn record_span_ended(&self) {
        self.spans_ended.inc();
    }

    pub fn record_span_dropped(&self) {
        self.spans_dropped.inc();
    }

    pub fn record_export_duration(&self, duration: Duration) {
        self.export_duration.observe(duration.as_secs_f64());
    }

    pub fn set_sampling_rate(&self, rate: f64) {
        self.sampling_rate.set(rate);
    }
}

impl Default for TracingMetrics {
    fn default() -> Self {
        Self::new()
    }
}

// ========================= Tests =========================

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_trace_context() {
        let context = TraceContext::new();
        assert!(!context.trace_id.is_empty());
        assert!(!context.span_id.is_empty());
        assert!(context.parent_span_id.is_none());

        let child = context.child();
        assert_eq!(child.trace_id, context.trace_id);
        assert_ne!(child.span_id, context.span_id);
        assert_eq!(child.parent_span_id, Some(context.span_id.clone()));
    }

    #[test]
    fn test_context_propagation() {
        let mut context = TraceContext::new();
        context
            .baggage
            .insert("user_id".to_string(), "12345".to_string());

        let mut headers = HashMap::new();
        context.inject_into_headers(&mut headers);

        assert!(headers.contains_key("x-trace-id"));
        assert!(headers.contains_key("x-span-id"));
        assert!(headers.contains_key("x-baggage-user_id"));

        let extracted = TraceContext::extract_from_headers(&headers).unwrap();
        assert_eq!(extracted.trace_id, context.trace_id);
        assert_eq!(extracted.span_id, context.span_id);
        assert_eq!(extracted.baggage.get("user_id"), Some(&"12345".to_string()));
    }

    #[test]
    fn test_adaptive_sampler() {
        let sampler = AdaptiveSampler::new(0.1, 2.0, 1000);

        // Test load-based adjustment
        sampler.adjust_rate_based_on_load(50.0);
        assert_eq!(*sampler.current_rate.read(), 0.1);

        sampler.adjust_rate_based_on_load(500.0);
        assert_eq!(*sampler.current_rate.read(), 0.1);

        sampler.adjust_rate_based_on_load(5000.0);
        assert_eq!(*sampler.current_rate.read(), 0.01);

        sampler.adjust_rate_based_on_load(50000.0);
        assert_eq!(*sampler.current_rate.read(), 0.001);
    }

    #[tokio::test]
    async fn test_tracer_manager_creation() {
        let config = TracingConfig {
            enable_console_exporter: false,
            enable_jaeger_exporter: false,
            enable_otlp_exporter: false,
            ..Default::default()
        };

        let manager = TracerManager::new(config).unwrap();
        // Can create spans without full initialization
        let span = manager.create_span("test_span");
        assert!(!span.is_disabled());
    }
}
