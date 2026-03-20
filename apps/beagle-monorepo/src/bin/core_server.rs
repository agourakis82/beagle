use std::net::SocketAddr;
use std::sync::Arc;

use anyhow::Context;
use beagle_config::{bootstrap, load as load_config};
use beagle_core::BeagleContext;
use beagle_monorepo::http::{build_router, AppState};
use beagle_observability::init_observability;
use beagle_observer::UniversalObserver;
use tokio::sync::Mutex;
use tracing::info;

fn main() -> anyhow::Result<()> {
    let runtime = tokio::runtime::Builder::new_multi_thread()
        .enable_io()
        .enable_time()
        .build()
        .context("Falha ao criar runtime Tokio do core server")?;

    runtime.block_on(async_main())
}

async fn async_main() -> anyhow::Result<()> {
    init_observability().context("Falha ao inicializar observabilidade")?;

    // Bootstrap: verifica e cria BEAGLE_DATA_DIR
    bootstrap().context("Falha no bootstrap do BEAGLE_DATA_DIR")?;

    let cfg = load_config();
    info!(
        "BEAGLE core server | profile={} | safe_mode={} | data_dir={}",
        cfg.profile, cfg.safe_mode, cfg.storage.data_dir
    );

    let ctx = BeagleContext::new(cfg).await?;
    let observer = UniversalObserver::new_async()
        .await
        .context("Falha ao criar UniversalObserver")?;

    let state = AppState {
        ctx: Arc::new(Mutex::new(ctx)),
        jobs: Arc::new(beagle_monorepo::JobRegistry::new()),
        science_jobs: Arc::new(beagle_monorepo::ScienceJobRegistry::new()),
        observer: Arc::new(observer),
    };

    let router = build_router(state);

    let addr = bind_addr().context("Falha ao resolver endereço de bind do core server")?;

    info!(
        "Iniciando BEAGLE core server em http://{addr} | health=/health"
    );
    let listener = tokio::net::TcpListener::bind(&addr).await?;
    axum::serve(listener, router).await?;

    Ok(())
}

fn bind_addr() -> anyhow::Result<SocketAddr> {
    std::env::var("BEAGLE_BIND_ADDR")
        .or_else(|_| std::env::var("BEAGLE_CORE_ADDR"))
        .unwrap_or_else(|_| "0.0.0.0:8080".to_string())
        .parse()
        .context("endereço inválido em BEAGLE_BIND_ADDR/BEAGLE_CORE_ADDR")
}
