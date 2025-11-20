use std::net::SocketAddr;
use std::sync::Arc;

use beagle_config::load as load_config;
use beagle_core::BeagleContext;
use beagle_monorepo::{http::{build_router, AppState}, init_tracing};
use tokio::sync::Mutex;
use tracing::info;

#[tokio::main]
async fn main() -> anyhow::Result<()> {
    init_tracing();

    let cfg = load_config();
    let ctx = BeagleContext::new(cfg).await?;
    let state = AppState {
        ctx: Arc::new(Mutex::new(ctx)),
    };

    let router = build_router(state);

    let addr: SocketAddr = std::env::var("BEAGLE_CORE_ADDR")
        .unwrap_or_else(|_| "0.0.0.0:8080".to_string())
        .parse()
        .expect("endereço inválido em BEAGLE_CORE_ADDR");

    info!("Iniciando BEAGLE core server em http://{addr}");
    axum::Server::bind(&addr)
        .serve(router.into_make_service())
        .await?;

    Ok(())
}
