//! Ponto de entrada do servidor Beagle.
//!
//! Inicializa telemetria, carrega configuração e publica o roteador Axum
//! com autenticação JWT, rate limiting e documentação OpenAPI.

mod api;
mod auth;
mod config;
mod error;
mod metrics;
mod middleware;
mod state;

use std::{net::SocketAddr, num::NonZeroU32, time::Duration};

use axum::{middleware::from_fn, Router};
use tokio::net::TcpListener;
use middleware::rate_limit::RateLimitLayer;
use state::AppState;
use tower_http::{compression::CompressionLayer, cors::CorsLayer, trace::TraceLayer};
use tracing::info;
use utoipa::OpenApi;

#[tokio::main]
async fn main() -> anyhow::Result<()> {
    dotenvy::dotenv().ok();

    init_tracing();

    info!("Inicializando Beagle API Server");

    let config = config::Config::from_env()?;
    let state = AppState::new(&config).await?;

    let openapi = api::openapi::ApiDoc::openapi();

    let rate_limit = NonZeroU32::new(config.rate_limit_requests_per_minute())
        .expect("rate limit requests must be greater than zero");
    let rate_period = Duration::from_secs(60);

    let app = Router::new()
        .merge(api::routes::health_routes())
        .merge(api::routes::node_routes())
        .merge(api::routes::hyperedge_routes())
        .merge(api::routes::search_routes())
        .merge(api::routes::auth_routes())
        .merge(api::routes::metrics_routes())
        .merge(
            utoipa_swagger_ui::SwaggerUi::new("/swagger-ui").url("/api-docs/openapi.json", openapi),
        )
        .layer(TraceLayer::new_for_http())
        .layer(CompressionLayer::new())
        .layer(CorsLayer::permissive())
        .layer(RateLimitLayer::new(rate_limit, rate_period))
        .layer(from_fn(metrics::track_http_requests))
        .with_state(state);

    let addr: SocketAddr = (config.host().parse::<std::net::IpAddr>()?, config.port()).into();
    let listener = TcpListener::bind(addr).await?;
    info!(addr = %listener.local_addr()?, "Servidor iniciado");

    axum::serve(listener, app.into_make_service_with_connect_info::<SocketAddr>())
        .await?;

    Ok(())
}

fn init_tracing() {
    use tracing_subscriber::{fmt, layer::SubscriberExt, EnvFilter, Registry};

    let env_filter = EnvFilter::try_from_default_env().unwrap_or_else(|_| {
        EnvFilter::new("beagle_server=info,beagle_hypergraph=info,tower_http=info")
    });

    let fmt_layer = fmt::layer()
        .with_target(true)
        .with_line_number(true)
        .with_thread_ids(true)
        .with_level(true);

    let registry = Registry::default().with(env_filter).with(fmt_layer);

    tracing::subscriber::set_global_default(registry)
        .expect("failed to initialize tracing subscriber");
}
