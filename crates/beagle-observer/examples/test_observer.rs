//! Teste do Universal Observer
//!
//! Demonstra todas as funcionalidades:
//! - File watcher
//! - Clipboard
//! - Screenshots
//! - Input activity
//! - Browser history
//! - HealthKit bridge

use beagle_observer::{Observation, UniversalObserver};
use std::time::Duration;
use tracing::info;

#[tokio::main]
async fn main() -> anyhow::Result<()> {
    tracing_subscriber::fmt()
        .with_env_filter("beagle_observer=info")
        .init();

    info!("🧪 Testando Universal Observer...");

    let mut observer = UniversalObserver::new()?;
    let mut rx = observer.get_observations_receiver()
        .ok_or_else(|| anyhow::anyhow!("Falha ao obter receiver"))?;
    
    // Inicia surveillance
    observer.start_full_surveillance().await?;
    
    info!("✅ Observer iniciado. Coletando observações por 10 segundos...");
    
    // Coleta observações por 10 segundos
    let mut observations = Vec::new();
    let timeout = tokio::time::sleep(Duration::from_secs(10));
    tokio::pin!(timeout);
    
    loop {
        tokio::select! {
            _ = &mut timeout => {
                info!("⏱️  Timeout atingido. Total de observações: {}", observations.len());
                break;
            }
            Some(obs) = rx.recv() => {
                info!("📊 Observação: {} - {}", obs.source, obs.content_preview.chars().take(50).collect::<String>());
                observations.push(obs);
            }
        }
    }
    
    // Análise fisiológica se houver dados de HealthKit
    let health_obs: Vec<Observation> = observations
        .iter()
        .filter(|o| o.source == "healthkit")
        .cloned()
        .collect();
    
    if !health_obs.is_empty() {
        info!("🏥 Analisando {} observações de HealthKit...", health_obs.len());
        let analysis = observer.physiological_state_analysis(&health_obs).await?;
        info!("📋 Análise fisiológica:\n{}", analysis);
    }
    
    info!("✅ Teste concluído!");
    Ok(())
}

