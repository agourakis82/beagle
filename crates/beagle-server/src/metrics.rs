//! Subsistema de métricas HTTP expostas via Prometheus.
//!
//! Este módulo centraliza o registro de coletores globais associados ao
//! servidor Axum, fornece handlers de exportação no formato OpenMetrics e
//! disponibiliza utilitários de instrumentação a serem aplicados como
//! *middleware*.

use axum::{
    body::Body,
    extract::MatchedPath,
    http::{header::CONTENT_TYPE, HeaderValue, Request},
    middleware::Next,
    response::{IntoResponse, Response},
};
use once_cell::sync::Lazy;
use prometheus::{Encoder, IntCounterVec, Opts, Registry, TextEncoder};

use crate::error::ApiError;

/// Registro global do Prometheus utilizado por toda a aplicação.
pub static REGISTRY: Lazy<Registry> = Lazy::new(Registry::new);

/// Contador total de requisições HTTP segmentado por método, rota e status.
pub static HTTP_REQUESTS: Lazy<IntCounterVec> = Lazy::new(|| {
    let counter = IntCounterVec::new(
        Opts::new("http_requests_total", "Total HTTP requests"),
        &["method", "path", "status"],
    )
    .expect("configuração válida do contador de requisições HTTP");

    REGISTRY
        .register(Box::new(counter.clone()))
        .expect("registro do contador http_requests_total no Registry global");

    counter
});

/// Handler HTTP que serializa e retorna as métricas coletadas.
pub async fn metrics_handler() -> Result<impl IntoResponse, ApiError> {
    let encoder = TextEncoder::new();
    let metric_families = REGISTRY.gather();

    let mut buffer = Vec::new();
    encoder
        .encode(&metric_families, &mut buffer)
        .map_err(|err| {
            ApiError::Internal(format!("Falha ao codificar métricas Prometheus: {err}"))
        })?;

    let body = String::from_utf8(buffer)
        .map_err(|err| ApiError::Internal(format!("Buffer de métricas não UTF-8: {err}")))?;

    Ok((
        [(
            CONTENT_TYPE,
            HeaderValue::from_static("text/plain; charset=utf-8"),
        )],
        body,
    ))
}

/// Middleware que incrementa contadores de requisições HTTP.
pub async fn track_http_requests(request: Request<Body>, next: Next) -> Response {
    let method = request.method().to_string();
    let matched_path: String = request
        .extensions()
        .get::<MatchedPath>()
        .map(|p| p.as_str().to_owned())
        .unwrap_or_else(|| request.uri().path().to_owned());

    let response = next.run(request).await;

    let status = response.status().as_u16().to_string();
    HTTP_REQUESTS
        .with_label_values(&[method.as_str(), matched_path.as_str(), status.as_str()])
        .inc();

    response
}
