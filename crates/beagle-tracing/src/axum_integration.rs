// Axum integration for distributed tracing
//
// References:
// - Tower middleware documentation
// - OpenTelemetry HTTP semantic conventions

use crate::{TracerManager, TraceContext, record_error};
use axum::{
    body::Body,
    extract::Request,
    http::{HeaderMap, StatusCode},
    middleware::Next,
    response::{IntoResponse, Response},
};
use opentelemetry::trace::{FutureExt, SpanKind, TraceContextExt};
use std::time::Instant;
use tower::{Layer, Service};
use tracing::{info_span, Instrument, Span};
use uuid::Uuid;

// ========================= Tracing Middleware =========================

#[derive(Clone)]
pub struct TracingLayer {
    tracer_manager: std::sync::Arc<TracerManager>,
}

impl TracingLayer {
    pub fn new(tracer_manager: std::sync::Arc<TracerManager>) -> Self {
        Self { tracer_manager }
    }
}

impl<S> Layer<S> for TracingLayer {
    type Service = TracingMiddleware<S>;

    fn layer(&self, inner: S) -> Self::Service {
        TracingMiddleware {
            inner,
            tracer_manager: self.tracer_manager.clone(),
        }
    }
}

#[derive(Clone)]
pub struct TracingMiddleware<S> {
    inner: S,
    tracer_manager: std::sync::Arc<TracerManager>,
}

impl<S> Service<Request> for TracingMiddleware<S>
where
    S: Service<Request, Response = Response> + Send + 'static,
    S::Future: Send + 'static,
{
    type Response = S::Response;
    type Error = S::Error;
    type Future = std::pin::Pin<
        Box<dyn std::future::Future<Output = Result<Self::Response, Self::Error>> + Send>
    >;

    fn poll_ready(
        &mut self,
        cx: &mut std::task::Context<'_>,
    ) -> std::task::Poll<Result<(), Self::Error>> {
        self.inner.poll_ready(cx)
    }

    fn call(&mut self, request: Request) -> Self::Future {
        let tracer_manager = self.tracer_manager.clone();
        let future = self.inner.call(request);

        Box::pin(async move {
            future.await
        })
    }
}

// ========================= Request Tracing =========================

pub async fn trace_request(
    request: Request,
    next: Next,
) -> Result<Response, StatusCode> {
    let start_time = Instant::now();
    let request_id = Uuid::new_v4().to_string();

    // Extract trace context from headers
    let trace_context = extract_trace_context(request.headers());

    // Create span for this request
    let span = create_request_span(&request, &request_id, trace_context.as_ref());

    // Clone necessary data before moving request
    let method = request.method().clone();
    let uri = request.uri().clone();
    let version = request.version();

    // Enter span context
    let _enter = span.enter();

    // Process request
    let response = next.run(request).await;

    // Record response details
    let status = response.status();
    let duration = start_time.elapsed();

    span.record("http.status_code", status.as_u16());
    span.record("http.response_size", response.body().size_hint().0 as i64);
    span.record("duration_ms", duration.as_millis() as i64);

    if status.is_server_error() {
        span.record("error", true);
        span.record("error.type", "server_error");
    } else if status.is_client_error() {
        span.record("error", true);
        span.record("error.type", "client_error");
    }

    // Log request completion
    tracing::info!(
        target: "http_request",
        request_id = %request_id,
        method = %method,
        uri = %uri,
        version = ?version,
        status = %status,
        duration_ms = %duration.as_millis(),
        "Request completed"
    );

    Ok(response)
}

fn extract_trace_context(headers: &HeaderMap) -> Option<TraceContext> {
    let mut context_headers = std::collections::HashMap::new();

    for (key, value) in headers {
        if let Ok(value_str) = value.to_str() {
            context_headers.insert(key.as_str().to_string(), value_str.to_string());
        }
    }

    TraceContext::extract_from_headers(&context_headers)
}

fn create_request_span(
    request: &Request,
    request_id: &str,
    parent_context: Option<&TraceContext>,
) -> Span {
    let span = info_span!(
        "http_request",
        otel.name = %format!("{} {}", request.method(), request.uri().path()),
        otel.kind = ?SpanKind::Server,
        http.method = %request.method(),
        http.scheme = ?request.uri().scheme_str(),
        http.target = %request.uri().path(),
        http.host = ?request.headers().get("host").and_then(|v| v.to_str().ok()),
        http.user_agent = ?request.headers().get("user-agent").and_then(|v| v.to_str().ok()),
        http.request_id = %request_id,
        http.client_ip = ?extract_client_ip(request.headers()),
        trace.parent_id = parent_context.as_ref().map(|c| c.parent_span_id.as_deref()).flatten(),
    );

    if let Some(context) = parent_context {
        span.record("trace.trace_id", &context.trace_id);
        span.record("trace.span_id", &context.span_id);

        // Record baggage items
        for (key, value) in &context.baggage {
            span.record(&format!("baggage.{}", key), value.as_str());
        }
    }

    span
}

fn extract_client_ip(headers: &HeaderMap) -> Option<String> {
    // Check common headers for client IP
    let headers_to_check = [
        "x-forwarded-for",
        "x-real-ip",
        "cf-connecting-ip",
        "true-client-ip",
    ];

    for header_name in headers_to_check {
        if let Some(value) = headers.get(header_name) {
            if let Ok(ip_str) = value.to_str() {
                // Take first IP if it's a comma-separated list
                return Some(ip_str.split(',').next()?.trim().to_string());
            }
        }
    }

    None
}

// ========================= Response Tracing =========================

pub struct TracedResponse {
    inner: Response,
    span: Span,
}

impl TracedResponse {
    pub fn new(response: Response, span: Span) -> Self {
        Self { inner: response, span }
    }
}

impl IntoResponse for TracedResponse {
    fn into_response(self) -> Response {
        // Record final response details
        self.span.record("http.status_code", self.inner.status().as_u16());

        // Add trace headers to response
        let (mut parts, body) = self.inner.into_parts();

        if let Some(trace_id) = self.span.id() {
            parts.headers.insert(
                "x-trace-id",
                trace_id.to_string().parse().unwrap_or_default(),
            );
        }

        Response::from_parts(parts, body)
    }
}

// ========================= Error Tracing =========================

pub async fn trace_error_handler(
    err: Box<dyn std::error::Error + Send + Sync>,
) -> (StatusCode, String) {
    let span = tracing::error_span!(
        "error_handler",
        error = %err,
        error.type = %std::any::type_name_of_val(&*err),
    );

    let _enter = span.enter();

    record_error(&span, &*err);

    tracing::error!(
        target: "http_error",
        error = %err,
        "Request failed with error"
    );

    (
        StatusCode::INTERNAL_SERVER_ERROR,
        format!("Internal server error: {}", err),
    )
}

// ========================= WebSocket Tracing =========================

pub fn create_websocket_span(client_id: &Uuid, message_type: &str) -> Span {
    info_span!(
        "websocket_message",
        otel.name = %format!("ws:{}", message_type),
        otel.kind = ?SpanKind::Server,
        ws.client_id = %client_id,
        ws.message_type = %message_type,
    )
}

pub fn trace_websocket_connect(client_id: &Uuid, user_id: Option<&str>) -> Span {
    info_span!(
        "websocket_connect",
        otel.name = "ws:connect",
        otel.kind = ?SpanKind::Server,
        ws.client_id = %client_id,
        ws.user_id = user_id,
    )
}

pub fn trace_websocket_disconnect(client_id: &Uuid, reason: &str) -> Span {
    info_span!(
        "websocket_disconnect",
        otel.name = "ws:disconnect",
        otel.kind = ?SpanKind::Server,
        ws.client_id = %client_id,
        ws.disconnect_reason = %reason,
    )
}

// ========================= Database Tracing =========================

pub fn create_db_span(operation: &str, query: &str) -> Span {
    info_span!(
        "database_query",
        otel.name = %format!("db:{}", operation),
        otel.kind = ?SpanKind::Client,
        db.operation = %operation,
        db.statement = %truncate_query(query, 500),
        db.system = "postgresql",
    )
}

fn truncate_query(query: &str, max_len: usize) -> String {
    if query.len() <= max_len {
        query.to_string()
    } else {
        format!("{}...", &query[..max_len])
    }
}

// ========================= LLM Tracing =========================

pub fn create_llm_span(
    provider: &str,
    model: &str,
    operation: &str,
) -> Span {
    info_span!(
        "llm_operation",
        otel.name = %format!("llm:{}:{}", provider, operation),
        otel.kind = ?SpanKind::Client,
        llm.provider = %provider,
        llm.model = %model,
        llm.operation = %operation,
    )
}

pub fn trace_llm_request(
    span: &Span,
    prompt_tokens: usize,
    max_tokens: usize,
    temperature: f32,
) {
    span.record("llm.prompt_tokens", prompt_tokens as i64);
    span.record("llm.max_tokens", max_tokens as i64);
    span.record("llm.temperature", temperature);
}

pub fn trace_llm_response(
    span: &Span,
    completion_tokens: usize,
    total_tokens: usize,
    duration_ms: u64,
) {
    span.record("llm.completion_tokens", completion_tokens as i64);
    span.record("llm.total_tokens", total_tokens as i64);
    span.record("llm.duration_ms", duration_ms as i64);
    span.record("llm.tokens_per_second", (total_tokens as f64 / (duration_ms as f64 / 1000.0)));
}

// ========================= Scientific Computation Tracing =========================

pub fn create_computation_span(
    algorithm: &str,
    dataset_size: usize,
) -> Span {
    info_span!(
        "scientific_computation",
        otel.name = %format!("compute:{}", algorithm),
        otel.kind = ?SpanKind::Internal,
        compute.algorithm = %algorithm,
        compute.dataset_size = dataset_size as i64,
    )
}

pub fn trace_computation_progress(
    span: &Span,
    iteration: usize,
    total_iterations: usize,
    current_error: f64,
) {
    span.record("compute.iteration", iteration as i64);
    span.record("compute.total_iterations", total_iterations as i64);
    span.record("compute.current_error", current_error);
    span.record("compute.progress_percent", ((iteration as f64 / total_iterations as f64) * 100.0));
}

// ========================= Batch Processing Tracing =========================

pub fn create_batch_span(
    job_type: &str,
    batch_size: usize,
) -> Span {
    info_span!(
        "batch_processing",
        otel.name = %format!("batch:{}", job_type),
        otel.kind = ?SpanKind::Consumer,
        batch.job_type = %job_type,
        batch.size = batch_size as i64,
    )
}

pub fn trace_batch_item(
    parent_span: &Span,
    item_id: &str,
    index: usize,
) -> Span {
    info_span!(
        parent: parent_span.clone(),
        "batch_item",
        otel.name = "batch:item",
        batch.item_id = %item_id,
        batch.item_index = index as i64,
    )
}

// ========================= Tests =========================

#[cfg(test)]
mod tests {
    use super::*;
    use axum::http::Method;

    #[test]
    fn test_extract_client_ip() {
        let mut headers = HeaderMap::new();
        headers.insert("x-forwarded-for", "192.168.1.1, 10.0.0.1".parse().unwrap());

        let ip = extract_client_ip(&headers);
        assert_eq!(ip, Some("192.168.1.1".to_string()));

        let mut headers2 = HeaderMap::new();
        headers2.insert("x-real-ip", "192.168.1.2".parse().unwrap());

        let ip2 = extract_client_ip(&headers2);
        assert_eq!(ip2, Some("192.168.1.2".to_string()));
    }

    #[test]
    fn test_truncate_query() {
        let short_query = "SELECT * FROM users";
        assert_eq!(truncate_query(short_query, 50), short_query);

        let long_query = "SELECT * FROM users WHERE id IN (1, 2, 3, 4, 5, 6, 7, 8, 9, 10)";
        let truncated = truncate_query(long_query, 30);
        assert!(truncated.ends_with("..."));
        assert_eq!(truncated.len(), 33); // 30 + "..."
    }
}
