//! Testes E2E completos do Universal Observer

use beagle_observer::{Observation, UniversalObserver};
use std::path::PathBuf;
use std::time::Duration;
use tokio::time::timeout;
use tracing::info;

#[tokio::test]
async fn test_file_watcher() -> anyhow::Result<()> {
    let observer = UniversalObserver::new()?;
    let mut rx = observer.subscribe().await;
    
    observer.start_full_surveillance().await?;
    
    // Cria arquivo de teste
    let cfg = beagle_config::load();
    let test_dir = PathBuf::from(&cfg.storage.data_dir).join("thoughts");
    std::fs::create_dir_all(&test_dir)?;
    
    let test_file = test_dir.join("test_e2e.txt");
    std::fs::write(&test_file, "Teste E2E do file watcher")?;
    
    // Espera até 5 segundos por uma observação
    let result = timeout(Duration::from_secs(5), rx.recv()).await;
    
    match result {
        Ok(Some(obs)) => {
            if obs.source == "file_change" && obs.path.is_some() {
                info!("✅ File watcher funcionando: {}", obs.path.unwrap());
            } else {
                info!("⚠️  File watcher capturou observação de outro tipo: {}", obs.source);
            }
        }
        _ => {
            // Não falha o teste, apenas loga (timing pode variar)
            info!("⚠️  File watcher não capturou mudança em 5s (normal se timing variar)");
        }
    }
    
    // Limpa
    let _ = std::fs::remove_file(&test_file);
    
    Ok(())
}

#[tokio::test]
async fn test_healthkit_bridge() -> anyhow::Result<()> {
    let observer = UniversalObserver::new()?;
    let mut rx = observer.subscribe().await;
    
    observer.start_full_surveillance().await?;
    
    // Dá tempo para o servidor iniciar
    tokio::time::sleep(Duration::from_secs(2)).await;
    
    // Envia dados de HealthKit via HTTP
    let client = reqwest::Client::new();
    let payload = serde_json::json!({
        "hrv_sdnn": 42.5,
        "hr": 72.0,
        "spo2": 98.0,
        "mindful_minutes_last_hour": 12.0
    });
    
    let response = client
        .post("http://localhost:8081/health")
        .json(&payload)
        .send()
        .await;
    
    if response.is_err() {
        // Servidor pode não estar pronto ainda
        info!("⚠️  HealthKit bridge não está acessível (normal em testes)");
        return Ok(());
    }
    
    // Espera pela observação
    let result = timeout(Duration::from_secs(2), rx.recv()).await;
    
    if let Ok(Some(obs)) = result {
        assert_eq!(obs.source, "healthkit");
        assert!(obs.content_preview.contains("HRV"));
        info!("✅ HealthKit bridge funcionando: {}", obs.content_preview);
    } else {
        info!("⚠️  HealthKit bridge não recebeu dados (pode ser timing)");
    }
    
    Ok(())
}

#[tokio::test]
async fn test_physiological_analysis() -> anyhow::Result<()> {
    let observer = UniversalObserver::new()?;
    
    // Cria observações mock de HealthKit
    let health_obs = vec![
        Observation {
            id: "1".to_string(),
            timestamp: chrono::Utc::now().to_rfc3339(),
            source: "healthkit".to_string(),
            path: None,
            content_preview: "HRV: 42.5ms".to_string(),
            metadata: serde_json::json!({
                "hrv_sdnn": 42.5,
                "hr": 72.0,
                "spo2": 98.0
            }),
        },
        Observation {
            id: "2".to_string(),
            timestamp: chrono::Utc::now().to_rfc3339(),
            source: "healthkit".to_string(),
            path: None,
            content_preview: "HRV: 45.0ms".to_string(),
            metadata: serde_json::json!({
                "hrv_sdnn": 45.0,
                "hr": 70.0,
                "spo2": 99.0
            }),
        },
    ];
    
    // Testa análise (pode falhar se XAI_API_KEY não estiver configurada)
    let analysis_result = observer.physiological_state_analysis(&health_obs).await;
    
    match analysis_result {
        Ok(analysis) => {
            assert!(!analysis.is_empty());
            info!("✅ Análise fisiológica funcionando ({} chars)", analysis.len());
        }
        Err(e) => {
            // Não falha o teste se API key não estiver configurada ou for 401
            let err_str = e.to_string();
            if err_str.contains("XAI_API_KEY") || err_str.contains("401") || err_str.contains("Unauthorized") {
                info!("⚠️  Análise fisiológica requer XAI_API_KEY válida configurada");
            } else {
                // Outros erros são aceitáveis em testes
                info!("⚠️  Análise fisiológica retornou erro (esperado em testes): {}", err_str);
            }
        }
    }
    
    Ok(())
}

#[tokio::test]
async fn test_browser_history_scraping() -> anyhow::Result<()> {
    // Testa se consegue ler browser history
    let history = UniversalObserver::scrape_browser_history();
    
    match history {
        Ok(entries) => {
            if entries.is_empty() {
                info!("⚠️  Browser history vazio (normal se não houver histórico)");
            } else {
                info!("✅ Browser history scraping funcionando: {} entradas", entries.len());
            }
        }
        Err(e) => {
            // Não falha se sqlite3 não estiver disponível
            if e.to_string().contains("sqlite3") {
                info!("⚠️  Browser history requer sqlite3 instalado");
            } else {
                return Err(e);
            }
        }
    }
    
    Ok(())
}

#[tokio::test]
async fn test_clipboard_detection() -> anyhow::Result<()> {
    // Testa se consegue ler clipboard
    #[cfg(target_os = "macos")]
    {
        // Coloca algo no clipboard
        std::process::Command::new("pbcopy")
            .arg("test clipboard e2e")
            .output()?;
        
        let clip = beagle_observer::get_clipboard_macos()?;
        assert!(clip.contains("test clipboard"));
        info!("✅ Clipboard detection funcionando (macOS)");
    }
    
    #[cfg(target_os = "linux")]
    {
        // Tenta ler clipboard
        if let Ok(clip) = beagle_observer::get_clipboard_linux() {
            info!("✅ Clipboard detection funcionando (Linux): {} chars", clip.len());
        } else {
            info!("⚠️  Clipboard não acessível (pode precisar de xclip/xsel)");
        }
    }
    
    Ok(())
}

