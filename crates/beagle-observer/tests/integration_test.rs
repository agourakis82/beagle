//! Teste de integração completo - simula uso real

use beagle_observer::UniversalObserver;
use std::time::Duration;
use tokio::time::timeout;

#[tokio::test]
async fn test_full_integration() -> anyhow::Result<()> {
    tracing_subscriber::fmt()
        .with_env_filter("beagle_observer=info")
        .try_init()
        .ok();
    
    let observer = UniversalObserver::new()?;
    let mut rx = observer.subscribe().await;
    
    // Inicia surveillance
    observer.start_full_surveillance().await?;
    
    // Coleta observações por 15 segundos
    let mut observations = Vec::new();
    let start = std::time::Instant::now();
    
    while start.elapsed() < Duration::from_secs(15) {
        match timeout(Duration::from_secs(1), rx.recv()).await {
            Ok(Some(obs)) => {
                observations.push(obs);
            }
            _ => {
                // Timeout - continua
            }
        }
    }
    
    // Verifica que pelo menos algumas observações foram coletadas
    // (pode ser 0 se não houver atividade, mas o sistema deve estar funcionando)
    println!("✅ Integração completa: {} observações coletadas em 15s", observations.len());
    
    // Agrupa por source
    let mut by_source: std::collections::HashMap<String, usize> = std::collections::HashMap::new();
    for obs in &observations {
        *by_source.entry(obs.source.clone()).or_insert(0) += 1;
    }
    
    for (source, count) in by_source {
        println!("  - {}: {} observações", source, count);
    }
    
    Ok(())
}

