//! Universal Observer - Binário principal
//!
//! Ativa todas as capturas:
//! - File watcher
//! - Clipboard
//! - Screenshots
//! - Input activity
//! - Browser history
//! - HealthKit bridge

use beagle_observer::UniversalObserver;
use tracing::info;

#[tokio::main]
async fn main() -> anyhow::Result<()> {
    tracing_subscriber::fmt()
        .with_env_filter(tracing_subscriber::EnvFilter::from_default_env())
        .init();

    info!("🚀 Iniciando Universal Observer v0.2 + v0.3...");

    let observer = UniversalObserver::new()?;
    observer.start_full_surveillance().await?;

    info!("✅ BEAGLE ESTÁ TE OBSERVANDO – TUDO ATIVADO");
    info!("   - File watcher: papers/notes/thoughts");
    info!("   - Clipboard: a cada 3s");
    info!("   - Screenshots: a cada 30s");
    info!("   - Input activity: monitorando");
    info!("   - Browser history: a cada 5min");
    info!("   - HealthKit bridge: http://localhost:8081/health");

    // Mantém o processo rodando
    std::future::pending::<()>().await;

    Ok(())
}
