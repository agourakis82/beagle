use std::net::SocketAddr;
use std::sync::Arc;

use anyhow::Context;
use beagle_config::{bootstrap, load as load_config};
use beagle_core::BeagleContext;
use beagle_monorepo::http::{build_router, AppState};
use beagle_observer::UniversalObserver;
use tokio::sync::Mutex;
use tracing::info;

#[tokio::main]
async fn main() -> anyhow::Result<()> {
    tracing_subscriber::fmt()
        .with_env_filter(tracing_subscriber::EnvFilter::from_default_env())
        .init();

    // Bootstrap: verifica e cria BEAGLE_DATA_DIR
    bootstrap().context("Falha no bootstrap do BEAGLE_DATA_DIR")?;

    let cfg = load_config();
    info!(
        "BEAGLE core server | profile={} | safe_mode={} | data_dir={}",
        cfg.profile, cfg.safe_mode, cfg.storage.data_dir
    );

    let ctx = BeagleContext::new(cfg).await?;
    let observer = UniversalObserver::new().context("Falha ao criar UniversalObserver")?;

    let state = AppState {
        ctx: Arc::new(Mutex::new(ctx)),
        jobs: Arc::new(beagle_monorepo::JobRegistry::new()),
        science_jobs: Arc::new(beagle_monorepo::ScienceJobRegistry::new()),
        observer: Arc::new(observer),
    };

    let router = build_router(state);

    let addr: SocketAddr = std::env::var("BEAGLE_CORE_ADDR")
        .unwrap_or_else(|_| "0.0.0.0:8080".to_string())
        .parse()
        .expect("endereço inválido em BEAGLE_CORE_ADDR");

    info!("Iniciando BEAGLE core server em http://{addr}");
    let listener = tokio::net::TcpListener::bind(&addr).await?;
    axum::serve(listener, router).await?;

    Ok(())
}
