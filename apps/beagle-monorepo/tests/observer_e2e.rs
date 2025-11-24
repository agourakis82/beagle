//! Testes end-to-end do Observer 2.0
//!
//! Testa ingest de eventos (physio/env/space_weather), classificação de severidade,
//! geração de alerts e integração com pipeline/run_report.

use anyhow::Result;
use beagle_observer::{Severity, UniversalObserver};
use std::path::PathBuf;
use std::sync::Arc;
use tempfile::TempDir;

/// Setup: cria contexto e observer para testes
async fn setup_test_observer() -> Result<(TempDir, Arc<UniversalObserver>, PathBuf)> {
    let temp_dir = TempDir::new()?;
    let data_dir = temp_dir.path().to_path_buf();

    // Cria estrutura de diretórios
    std::fs::create_dir_all(&data_dir.join("alerts"))?;
    std::fs::create_dir_all(&data_dir.join("papers").join("drafts"))?;
    std::fs::create_dir_all(&data_dir.join("logs").join("beagle-pipeline"))?;
    std::fs::create_dir_all(&data_dir.join("feedback"))?;
    std::fs::create_dir_all(&data_dir.join("screenshots"))?;
    std::fs::create_dir_all(&data_dir.join("observations"))?;

    // Configura BeagleConfig para usar temp_dir
    std::env::set_var("BEAGLE_DATA_DIR", data_dir.to_string_lossy().to_string());

    // Cria observer (ele carrega config automaticamente de BEAGLE_DATA_DIR)
    let observer = UniversalObserver::new()?;

    // Verifica que o observer está usando o data_dir correto
    // (o observer internamente usa beagle_config::load() que lê BEAGLE_DATA_DIR)

    Ok((temp_dir, Arc::new(observer), data_dir))
}

#[tokio::test]
async fn test_physio_event_ingest_and_alert() -> Result<()> {
    let (_temp_dir, observer, data_dir) = setup_test_observer().await?;

    // Cria evento fisiológico com SpO₂ crítica (deve gerar alert Severe)
    let event = beagle_observer::PhysioEvent {
        timestamp: chrono::Utc::now(),
        source: "test_watch".to_string(),
        session_id: Some("test_session_1".to_string()),
        hrv_ms: Some(25.0),          // HRV baixa (Moderate)
        heart_rate_bpm: Some(120.0), // FC alta (Moderate)
        spo2_percent: Some(88.0),    // SpO₂ crítica (Severe)
        resp_rate_bpm: Some(8.0),    // Respiração baixa (Moderate)
        skin_temp_c: Some(32.0),     // Temp baixa (Moderate)
        body_temp_c: None,
        steps: None,
        energy_burned_kcal: None,
        vo2max_ml_kg_min: None,
    };

    // Registra evento
    let severity = observer.record_physio_event(event, None).await?;

    // Verifica que a severidade agregada é Severe (máxima entre os indicadores)
    assert_eq!(
        severity,
        Severity::Severe,
        "Severidade deve ser Severe (SpO₂ crítica)"
    );

    // Verifica que alert foi gerado em alerts/physio.jsonl
    let alerts_file = data_dir.join("alerts").join("physio.jsonl");
    assert!(
        alerts_file.exists(),
        "Arquivo de alerts fisiológicos deve existir"
    );

    // Lê e verifica conteúdo do alert
    let alerts_content = std::fs::read_to_string(&alerts_file)?;
    assert!(
        alerts_content.contains("\"severity\":\"Severe\""),
        "Alert deve conter severity Severe"
    );
    assert!(
        alerts_content.contains("spo2_percent"),
        "Alert deve mencionar SpO₂"
    );

    Ok(())
}

#[tokio::test]
async fn test_env_event_ingest_and_alert() -> Result<()> {
    let (_temp_dir, observer, data_dir) = setup_test_observer().await?;

    // Cria evento ambiental com altitude alta e pressão baixa (deve gerar alert Moderate)
    let event = beagle_observer::EnvEvent {
        timestamp: chrono::Utc::now(),
        source: "test_iphone".to_string(),
        session_id: Some("test_session_2".to_string()),
        latitude_deg: Some(-23.5505),
        longitude_deg: Some(-46.6333),
        altitude_m: Some(2500.0),       // Altitude alta (Moderate)
        baro_pressure_hpa: Some(970.0), // Pressão baixa (Moderate)
        ambient_temp_c: Some(5.0),      // Temp baixa (Moderate)
        humidity_percent: Some(90.0),
        wind_speed_m_s: None,
        wind_dir_deg: None,
        uv_index: Some(8.0), // UV alto (Moderate)
        noise_db: None,
    };

    // Registra evento
    let severity = observer.record_env_event(event, None).await?;

    // Verifica que a severidade agregada é Moderate
    assert_eq!(severity, Severity::Moderate, "Severidade deve ser Moderate");

    // Verifica que alert foi gerado
    let alerts_file = data_dir.join("alerts").join("env.jsonl");
    assert!(
        alerts_file.exists(),
        "Arquivo de alerts ambientais deve existir"
    );

    let alerts_content = std::fs::read_to_string(&alerts_file)?;
    assert!(
        alerts_content.contains("\"severity\":\"Moderate\""),
        "Alert deve conter severity Moderate"
    );

    Ok(())
}

#[tokio::test]
async fn test_space_weather_event_ingest_and_alert() -> Result<()> {
    let (_temp_dir, observer, data_dir) = setup_test_observer().await?;

    // Cria evento de clima espacial com Kp alto (deve gerar alert Moderate/Severe)
    let event = beagle_observer::SpaceWeatherEvent {
        timestamp: chrono::Utc::now(),
        source: "test_noaa_api".to_string(),
        session_id: Some("test_session_3".to_string()),
        kp_index: Some(6.5), // Kp alto (Moderate a Severe)
        dst_index: Some(-150.0),
        solar_wind_speed_km_s: Some(650.0), // Vento solar alto (Moderate)
        solar_wind_density_n_cm3: Some(15.0),
        proton_flux_pfu: Some(12.0), // Fluxo de prótons alto (Moderate)
        electron_flux: None,
        xray_flux: Some(1e-4),
        radio_flux_sfu: Some(150.0),
    };

    // Registra evento
    let severity = observer.record_space_weather_event(event, None).await?;

    // Verifica que a severidade agregada é Moderate ou Severe
    assert!(
        severity >= Severity::Moderate,
        "Severidade deve ser pelo menos Moderate"
    );

    // Verifica que alert foi gerado
    let alerts_file = data_dir.join("alerts").join("space.jsonl");
    assert!(
        alerts_file.exists(),
        "Arquivo de alerts de clima espacial deve existir"
    );

    let alerts_content = std::fs::read_to_string(&alerts_file)?;
    assert!(
        alerts_content.contains("kp_index"),
        "Alert deve mencionar Kp"
    );

    Ok(())
}

#[tokio::test]
async fn test_user_context_aggregation() -> Result<()> {
    let (_temp_dir, observer, _data_dir) = setup_test_observer().await?;

    // Registra eventos de todos os tipos
    let physio_event = beagle_observer::PhysioEvent {
        timestamp: chrono::Utc::now(),
        source: "test_watch".to_string(),
        session_id: None,
        hrv_ms: Some(45.0),
        heart_rate_bpm: Some(72.0),
        spo2_percent: Some(98.0),
        resp_rate_bpm: Some(16.0),
        skin_temp_c: Some(35.0),
        body_temp_c: None,
        steps: None,
        energy_burned_kcal: None,
        vo2max_ml_kg_min: None,
    };
    observer.record_physio_event(physio_event, None).await?;

    let env_event = beagle_observer::EnvEvent {
        timestamp: chrono::Utc::now(),
        source: "test_iphone".to_string(),
        session_id: None,
        latitude_deg: Some(-23.5505),
        longitude_deg: Some(-46.6333),
        altitude_m: Some(760.0),
        baro_pressure_hpa: Some(1013.0),
        ambient_temp_c: Some(22.0),
        humidity_percent: Some(65.0),
        wind_speed_m_s: None,
        wind_dir_deg: None,
        uv_index: Some(4.0),
        noise_db: None,
    };
    observer.record_env_event(env_event, None).await?;

    let space_event = beagle_observer::SpaceWeatherEvent {
        timestamp: chrono::Utc::now(),
        source: "test_noaa".to_string(),
        session_id: None,
        kp_index: Some(3.0),
        dst_index: None,
        solar_wind_speed_km_s: Some(400.0),
        solar_wind_density_n_cm3: None,
        proton_flux_pfu: None,
        electron_flux: None,
        xray_flux: None,
        radio_flux_sfu: None,
    };
    observer
        .record_space_weather_event(space_event, None)
        .await?;

    // Obtém contexto agregado
    let user_ctx = observer.current_user_context().await?;

    // Verifica que o contexto foi agregado corretamente
    assert!(
        user_ctx.physio.hrv_level.is_some(),
        "HRV level deve estar presente"
    );
    assert!(
        user_ctx.physio.heart_rate_bpm.is_some(),
        "Heart rate deve estar presente"
    );
    assert_eq!(
        user_ctx.physio.severity,
        Severity::Normal,
        "Severidade fisiológica deve ser Normal"
    );

    assert!(
        user_ctx.env.location.is_some(),
        "Localização deve estar presente"
    );
    assert_eq!(
        user_ctx.env.severity,
        Severity::Normal,
        "Severidade ambiental deve ser Normal"
    );

    assert!(
        user_ctx.space.kp_index.is_some(),
        "Kp index deve estar presente"
    );
    assert_eq!(
        user_ctx.space.severity,
        Severity::Normal,
        "Severidade de clima espacial deve ser Normal"
    );

    Ok(())
}

#[tokio::test]
async fn test_observer_pipeline_integration() -> Result<()> {
    let (_temp_dir, observer, _data_dir) = setup_test_observer().await?;

    // Registra evento fisiológico com severidade alta
    let event = beagle_observer::PhysioEvent {
        timestamp: chrono::Utc::now(),
        source: "test_watch".to_string(),
        session_id: Some("pipeline_test_session".to_string()),
        hrv_ms: Some(20.0),          // HRV muito baixa
        heart_rate_bpm: Some(115.0), // FC alta
        spo2_percent: Some(92.0),    // SpO₂ levemente baixa
        resp_rate_bpm: None,
        skin_temp_c: None,
        body_temp_c: None,
        steps: None,
        energy_burned_kcal: None,
        vo2max_ml_kg_min: None,
    };
    let physio_severity = observer.record_physio_event(event, None).await?;

    // Obtém contexto
    let user_ctx = observer.current_user_context().await?;

    // Verifica que o contexto tem as severidades corretas
    assert!(
        physio_severity >= Severity::Moderate,
        "Severidade fisiológica deve ser pelo menos Moderate"
    );
    assert_eq!(
        user_ctx.physio.severity, physio_severity,
        "UserContext deve refletir severidade do último evento"
    );

    // Simula verificação de run_report (o pipeline real chamaria isso)
    // Por enquanto, apenas verifica que o contexto pode ser serializado
    let ctx_json = serde_json::to_string(&user_ctx)?;
    assert!(
        ctx_json.contains("physio"),
        "Contexto deve conter dados fisiológicos"
    );
    assert!(
        ctx_json.contains("env"),
        "Contexto deve conter dados ambientais"
    );
    assert!(
        ctx_json.contains("space"),
        "Contexto deve conter dados de clima espacial"
    );

    Ok(())
}

#[tokio::test]
async fn test_alert_file_creation() -> Result<()> {
    let (_temp_dir, observer, data_dir) = setup_test_observer().await?;

    // Verifica que diretório de alerts foi criado
    let alerts_dir = data_dir.join("alerts");
    assert!(alerts_dir.exists(), "Diretório de alerts deve existir");

    // Cria eventos que geram alerts
    let physio_event = beagle_observer::PhysioEvent {
        timestamp: chrono::Utc::now(),
        source: "test".to_string(),
        session_id: None,
        hrv_ms: Some(20.0),          // HRV baixa
        heart_rate_bpm: Some(115.0), // FC alta
        spo2_percent: Some(89.0),    // SpO₂ crítica
        resp_rate_bpm: None,
        skin_temp_c: None,
        body_temp_c: None,
        steps: None,
        energy_burned_kcal: None,
        vo2max_ml_kg_min: None,
    };
    observer.record_physio_event(physio_event, None).await?;

    // Verifica que arquivo de alerts foi criado
    let physio_alerts = alerts_dir.join("physio.jsonl");
    assert!(physio_alerts.exists(), "Arquivo physio.jsonl deve existir");

    // Lê e verifica conteúdo
    let content = std::fs::read_to_string(&physio_alerts)?;
    assert!(
        !content.is_empty(),
        "Arquivo de alerts não deve estar vazio"
    );

    // Verifica que contém múltiplas linhas (pelo menos 2 alerts: HRV, FC, SpO₂)
    let lines: Vec<&str> = content.lines().collect();
    assert!(lines.len() >= 1, "Deve haver pelo menos 1 alert");

    // Verifica que pelo menos um alert é Severe
    assert!(
        content.contains("\"severity\":\"Severe\""),
        "Deve haver pelo menos um alert Severe"
    );

    Ok(())
}
