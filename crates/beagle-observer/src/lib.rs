//! Universal Observer v0.2 + v0.3 - "Ativa Tudo"
//!
//! Captura completa de:
//! - File changes (papers, notes, thoughts)
//! - Clipboard (a cada 3s)
//! - Screenshots (a cada 30s)
//! - Input activity (teclado/mouse)
//! - Browser history (Chrome + Firefox)
//! - HealthKit data (v0.3 - macOS/iOS)

use axum::{routing::post, Json, Router};
use chrono::Utc;
use notify::{EventKind, RecursiveMode, Watcher};
use serde::{Deserialize, Serialize};
use serde_json::Value;
use std::path::{Path, PathBuf};
use std::sync::Arc;
use std::time::{Duration, Instant};
use tokio::sync::mpsc;
use tokio::time;
use tracing::{error, info, warn};
use uuid::Uuid;
mod alerts;
mod broadcast;
mod classification;
mod context;
mod events;
mod severity;

pub use alerts::AlertEvent;
pub use context::{EnvContext, PhysioContext, SpaceWeatherContext, UserContext};
pub use events::{EnvEvent, PhysioEvent, SpaceWeatherEvent};
pub use severity::Severity;

use broadcast::ObservationBroadcast;

#[derive(Serialize, Clone, Debug)]
pub struct Observation {
    pub id: String,
    pub timestamp: String,
    pub source: String,
    pub path: Option<String>,
    pub content_preview: String,
    pub metadata: serde_json::Value,
}

#[derive(Deserialize, Clone, Debug)]
pub struct BrowserEntry {
    url: String,
    title: Option<String>,
    visit_time: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct PhysiologicalState {
    pub hrv_ms: Option<f32>,
    pub hrv_level: Option<String>, // "low" | "normal" | "high"
    pub heart_rate_bpm: Option<f32>,
    pub last_updated: Option<String>, // ISO 8601 timestamp
}

pub struct UniversalObserver {
    broadcast: Arc<ObservationBroadcast>,
    observations_tx: Arc<mpsc::UnboundedSender<Observation>>,
    data_dir: PathBuf,
    physio_state: Arc<tokio::sync::RwLock<PhysiologicalState>>,
    // Timeline de contexto por run_id
    context_timeline: Arc<tokio::sync::RwLock<std::collections::HashMap<String, Vec<Observation>>>>,
    // Observer 2.0: Eventos estruturados (Physio, Env, SpaceWeather)
    physio_events: Arc<tokio::sync::RwLock<Vec<PhysioEvent>>>,
    env_events: Arc<tokio::sync::RwLock<Vec<EnvEvent>>>,
    space_weather_events: Arc<tokio::sync::RwLock<Vec<SpaceWeatherEvent>>>,
    // Configuração de thresholds
    thresholds: beagle_config::ObserverThresholds,
}

impl UniversalObserver {
    pub fn new() -> anyhow::Result<Self> {
        let broadcast = Arc::new(ObservationBroadcast::new());
        let (tx, mut rx) = mpsc::unbounded_channel();
        let broadcast_clone = broadcast.clone();

        // Task que repassa todas as observações para o broadcast
        tokio::spawn(async move {
            while let Some(obs) = rx.recv().await {
                broadcast_clone.broadcast(obs).await;
            }
        });

        let cfg = beagle_config::load();
        let data_dir = PathBuf::from(&cfg.storage.data_dir);

        // Cria diretórios necessários
        std::fs::create_dir_all(&data_dir.join("screenshots"))?;
        std::fs::create_dir_all(&data_dir.join("observations"))?;

        let thresholds = cfg.observer.clone();

        Ok(Self {
            broadcast,
            observations_tx: Arc::new(tx),
            data_dir,
            physio_state: Arc::new(tokio::sync::RwLock::new(PhysiologicalState {
                hrv_ms: None,
                hrv_level: None,
                heart_rate_bpm: None,
                last_updated: None,
            })),
            context_timeline: Arc::new(tokio::sync::RwLock::new(std::collections::HashMap::new())),
            physio_events: Arc::new(tokio::sync::RwLock::new(Vec::new())),
            env_events: Arc::new(tokio::sync::RwLock::new(Vec::new())),
            space_weather_events: Arc::new(tokio::sync::RwLock::new(Vec::new())),
            thresholds,
        })
    }

    /// Registra um evento fisiológico e processa alertas se necessário
    pub async fn record_physio_event(
        &self,
        event: PhysioEvent,
        run_id: Option<String>,
    ) -> anyhow::Result<Severity> {
        use crate::alerts::{log_alert, AlertEvent};
        use crate::classification::aggregate_physio_severity;

        // Calcula severidade agregada
        let severity = aggregate_physio_severity(&event, &self.thresholds.physio);

        // Armazena evento (mantém apenas os últimos 1000 eventos)
        {
            let mut events = self.physio_events.write().await;
            events.push(event.clone());
            if events.len() > 1000 {
                events.remove(0);
            }
        }

        // Atualiza estado fisiológico simplificado (compatibilidade)
        if let Some(hrv) = event.hrv_ms {
            let hrv_level = beagle_config::classify_hrv(hrv, None);
            self.update_hrv(hrv, hrv_level, event.heart_rate_bpm).await;
        }

        // Gera alertas se necessário (Moderate ou Severe)
        if severity >= Severity::Moderate {
            let alerts = self.generate_physio_alerts(&event, severity, run_id.clone());
            for alert in alerts {
                log_alert(&self.data_dir, &alert)?;
            }
        }

        Ok(severity)
    }

    /// Registra um evento ambiental e processa alertas se necessário
    pub async fn record_env_event(
        &self,
        event: EnvEvent,
        run_id: Option<String>,
    ) -> anyhow::Result<Severity> {
        use crate::alerts::{log_alert, AlertEvent};
        use crate::classification::aggregate_env_severity;

        // Calcula severidade agregada
        let severity = aggregate_env_severity(&event, &self.thresholds.env);

        // Armazena evento (mantém apenas os últimos 1000 eventos)
        {
            let mut events = self.env_events.write().await;
            events.push(event.clone());
            if events.len() > 1000 {
                events.remove(0);
            }
        }

        // Gera alertas se necessário
        if severity >= Severity::Moderate {
            let alerts = self.generate_env_alerts(&event, severity, run_id.clone());
            for alert in alerts {
                log_alert(&self.data_dir, &alert)?;
            }
        }

        Ok(severity)
    }

    /// Registra um evento de clima espacial e processa alertas se necessário
    pub async fn record_space_weather_event(
        &self,
        event: SpaceWeatherEvent,
        run_id: Option<String>,
    ) -> anyhow::Result<Severity> {
        use crate::alerts::{log_alert, AlertEvent};
        use crate::classification::aggregate_space_severity;

        // Calcula severidade agregada
        let severity = aggregate_space_severity(&event, &self.thresholds.space_weather);

        // Armazena evento (mantém apenas os últimos 1000 eventos)
        {
            let mut events = self.space_weather_events.write().await;
            events.push(event.clone());
            if events.len() > 1000 {
                events.remove(0);
            }
        }

        // Gera alertas se necessário
        if severity >= Severity::Moderate {
            let alerts = self.generate_space_weather_alerts(&event, severity, run_id.clone());
            for alert in alerts {
                log_alert(&self.data_dir, &alert)?;
            }
        }

        Ok(severity)
    }

    /// Gera alertas fisiológicos a partir de um evento
    fn generate_physio_alerts(
        &self,
        event: &PhysioEvent,
        _severity: Severity,
        run_id: Option<String>,
    ) -> Vec<AlertEvent> {
        use crate::alerts::AlertEvent;
        use crate::classification::*;

        let mut alerts = Vec::new();
        let t = &self.thresholds.physio;

        if let Some(hrv) = event.hrv_ms {
            let sev = classify_hrv(hrv, t);
            if sev >= Severity::Moderate {
                alerts.push(AlertEvent::physio(
                    "hrv_ms",
                    sev,
                    hrv,
                    t.hrv_low_ms,
                    event.session_id.clone(),
                    run_id.clone(),
                ));
            }
        }

        if let Some(hr) = event.heart_rate_bpm {
            let sev = classify_hr(hr, t);
            if sev >= Severity::Moderate {
                if hr >= t.hr_tachy_bpm {
                    alerts.push(AlertEvent::physio(
                        "heart_rate_bpm",
                        sev,
                        hr,
                        t.hr_tachy_bpm,
                        event.session_id.clone(),
                        run_id.clone(),
                    ));
                } else if hr <= t.hr_brady_bpm {
                    alerts.push(AlertEvent::physio(
                        "heart_rate_bpm",
                        sev,
                        hr,
                        t.hr_brady_bpm,
                        event.session_id.clone(),
                        run_id.clone(),
                    ));
                }
            }
        }

        if let Some(spo2) = event.spo2_percent {
            let sev = classify_spo2(spo2, t);
            if sev >= Severity::Moderate {
                alerts.push(AlertEvent::physio(
                    "spo2_percent",
                    sev,
                    spo2,
                    t.spo2_warning,
                    event.session_id.clone(),
                    run_id.clone(),
                ));
            }
        }

        alerts
    }

    /// Gera alertas ambientais a partir de um evento
    fn generate_env_alerts(
        &self,
        event: &EnvEvent,
        severity: Severity,
        run_id: Option<String>,
    ) -> Vec<AlertEvent> {
        use crate::alerts::AlertEvent;
        use crate::classification::*;

        let mut alerts = Vec::new();
        let t = &self.thresholds.env;

        if let Some(altitude) = event.altitude_m {
            let sev = classify_altitude(altitude, t);
            if sev >= Severity::Moderate {
                alerts.push(AlertEvent::env(
                    "altitude_m",
                    sev,
                    altitude,
                    t.altitude_high_m,
                    event.session_id.clone(),
                    run_id.clone(),
                ));
            }
        }

        if let Some(pressure) = event.baro_pressure_hpa {
            let sev = classify_baro_pressure(pressure, t);
            if sev >= Severity::Moderate {
                if pressure <= t.baro_low_hpa {
                    alerts.push(AlertEvent::env(
                        "baro_pressure_hpa",
                        sev,
                        pressure,
                        t.baro_low_hpa,
                        event.session_id.clone(),
                        run_id.clone(),
                    ));
                } else if pressure >= t.baro_high_hpa {
                    alerts.push(AlertEvent::env(
                        "baro_pressure_hpa",
                        sev,
                        pressure,
                        t.baro_high_hpa,
                        event.session_id.clone(),
                        run_id.clone(),
                    ));
                }
            }
        }

        if let Some(temp) = event.ambient_temp_c {
            let sev = classify_ambient_temp(temp, t);
            if sev >= Severity::Moderate {
                if temp <= t.temp_cold_c {
                    alerts.push(AlertEvent::env(
                        "ambient_temp_c",
                        sev,
                        temp,
                        t.temp_cold_c,
                        event.session_id.clone(),
                        run_id.clone(),
                    ));
                } else if temp >= t.temp_heat_c {
                    alerts.push(AlertEvent::env(
                        "ambient_temp_c",
                        sev,
                        temp,
                        t.temp_heat_c,
                        event.session_id.clone(),
                        run_id.clone(),
                    ));
                }
            }
        }

        if let Some(uv) = event.uv_index {
            let sev = classify_uv_index(uv, t);
            if sev >= Severity::Moderate {
                alerts.push(AlertEvent::env(
                    "uv_index",
                    sev,
                    uv,
                    t.uv_high,
                    event.session_id.clone(),
                    run_id.clone(),
                ));
            }
        }

        alerts
    }

    /// Gera alertas de clima espacial a partir de um evento
    fn generate_space_weather_alerts(
        &self,
        event: &SpaceWeatherEvent,
        severity: Severity,
        run_id: Option<String>,
    ) -> Vec<AlertEvent> {
        use crate::alerts::AlertEvent;
        use crate::classification::*;

        let mut alerts = Vec::new();
        let t = &self.thresholds.space_weather;

        if let Some(kp) = event.kp_index {
            let sev = classify_kp_index(kp, t);
            if sev >= Severity::Moderate {
                alerts.push(AlertEvent::space_weather(
                    "kp_index",
                    sev,
                    kp,
                    t.kp_storm,
                    event.session_id.clone(),
                    run_id.clone(),
                ));
            }
        }

        if let Some(proton_flux) = event.proton_flux_pfu {
            let sev = classify_proton_flux(proton_flux, t);
            if sev >= Severity::Moderate {
                alerts.push(AlertEvent::space_weather(
                    "proton_flux_pfu",
                    sev,
                    proton_flux,
                    t.proton_flux_high_pfu,
                    event.session_id.clone(),
                    run_id.clone(),
                ));
            }
        }

        if let Some(solar_wind) = event.solar_wind_speed_km_s {
            let sev = classify_solar_wind_speed(solar_wind, t);
            if sev >= Severity::Moderate {
                alerts.push(AlertEvent::space_weather(
                    "solar_wind_speed_km_s",
                    sev,
                    solar_wind,
                    t.solar_wind_speed_high_km_s,
                    event.session_id.clone(),
                    run_id.clone(),
                ));
            }
        }

        alerts
    }

    /// Obtém contexto completo do usuário agregando todos os eventos recentes
    pub async fn current_user_context(&self) -> anyhow::Result<UserContext> {
        use crate::classification::*;
        use crate::context::*;
        use beagle_config::classify_hrv;

        // Obtém último evento fisiológico
        let physio_ctx = {
            let events = self.physio_events.read().await;
            if let Some(last) = events.last() {
                let severity = aggregate_physio_severity(last, &self.thresholds.physio);
                let hrv_level = last.hrv_ms.map(|hrv| classify_hrv(hrv, None));
                let stress_index =
                    PhysioContext::compute_stress_index(last.hrv_ms, last.heart_rate_bpm);

                PhysioContext {
                    last_update: Some(last.timestamp),
                    hrv_level,
                    severity,
                    heart_rate_bpm: last.heart_rate_bpm,
                    spo2_percent: last.spo2_percent,
                    stress_index,
                }
            } else {
                PhysioContext::default()
            }
        };

        // Obtém último evento ambiental
        let env_ctx = {
            let events = self.env_events.read().await;
            if let Some(last) = events.last() {
                let severity = aggregate_env_severity(last, &self.thresholds.env);
                let location = match (last.latitude_deg, last.longitude_deg, last.altitude_m) {
                    (Some(lat), Some(lon), Some(alt)) => Some((lat, lon, alt)),
                    _ => None,
                };

                let mut ctx = EnvContext {
                    last_update: Some(last.timestamp),
                    severity,
                    location,
                    ambient_temp_c: last.ambient_temp_c,
                    humidity_percent: last.humidity_percent,
                    uv_index: last.uv_index,
                    summary: None,
                };
                ctx.summary = ctx.compute_summary();

                ctx
            } else {
                EnvContext::default()
            }
        };

        // Obtém último evento de clima espacial
        let space_ctx = {
            let events = self.space_weather_events.read().await;
            if let Some(last) = events.last() {
                let severity = aggregate_space_severity(last, &self.thresholds.space_weather);
                let heliobio_risk_level = SpaceWeatherContext::compute_heliobio_risk(last.kp_index);

                SpaceWeatherContext {
                    last_update: Some(last.timestamp),
                    severity,
                    kp_index: last.kp_index,
                    heliobio_risk_level,
                }
            } else {
                SpaceWeatherContext::default()
            }
        };

        Ok(UserContext {
            physio: physio_ctx,
            env: env_ctx,
            space: space_ctx,
        })
    }

    /// Atualiza estado fisiológico
    pub async fn update_hrv(&self, hrv_ms: f32, hrv_level: String, heart_rate_bpm: Option<f32>) {
        let mut state = self.physio_state.write().await;
        state.hrv_ms = Some(hrv_ms);
        state.hrv_level = Some(hrv_level);
        state.heart_rate_bpm = heart_rate_bpm;
        state.last_updated = Some(Utc::now().to_rfc3339());
    }

    /// Obtém estado fisiológico atual
    pub async fn current_physio_state(&self) -> PhysiologicalState {
        self.physio_state.read().await.clone()
    }

    /// Retorna um receiver para observações
    pub async fn subscribe(&self) -> mpsc::UnboundedReceiver<Observation> {
        self.broadcast.subscribe().await
    }

    pub async fn start_full_surveillance(&self) -> anyhow::Result<()> {
        let tx = self.observations_tx.clone();
        let data_dir = self.data_dir.clone();

        // 1. File watcher (papers, notes, thoughts)
        let tx1 = tx.clone();
        let data_dir1 = data_dir.clone();
        tokio::spawn(async move {
            let mut watcher = match notify::recommended_watcher(
                move |res: Result<notify::Event, notify::Error>| {
                    if let Ok(event) = res {
                        if matches!(event.kind, EventKind::Create(_) | EventKind::Modify(_)) {
                            for path in event.paths {
                                let content = std::fs::read_to_string(&path).unwrap_or_default();
                                let preview = content.chars().take(280).collect::<String>();

                                let _ = tx1.send(Observation {
                                    id: Uuid::new_v4().to_string(),
                                    timestamp: Utc::now().to_rfc3339(),
                                    source: "file_change".to_string(),
                                    path: Some(path.to_string_lossy().to_string()),
                                    content_preview: preview,
                                    metadata: serde_json::json!({
                                        "kind": format!("{:?}", event.kind)
                                    }),
                                });
                            }
                        }
                    }
                },
            ) {
                Ok(w) => w,
                Err(e) => {
                    error!("Falha ao criar file watcher: {}", e);
                    return;
                }
            };

            for p in &["thoughts", "papers/drafts", "notes"] {
                let path = data_dir1.join(p);
                if path.exists() {
                    if let Err(e) = watcher.watch(&path, RecursiveMode::Recursive) {
                        warn!("Falha ao observar {}: {}", path.display(), e);
                    } else {
                        info!("Observando: {}", path.display());
                    }
                }
            }

            std::future::pending::<()>().await;
        });

        // 2. Clipboard watcher (a cada 3s)
        let tx2 = tx.clone();
        tokio::spawn(async move {
            let mut last = String::new();
            loop {
                #[cfg(target_os = "macos")]
                {
                    if let Ok(clip) = get_clipboard_macos() {
                        if clip != last && !clip.trim().is_empty() && clip.len() < 5000 {
                            let _ = tx2.send(Observation {
                                id: Uuid::new_v4().to_string(),
                                timestamp: Utc::now().to_rfc3339(),
                                source: "clipboard".to_string(),
                                path: None,
                                content_preview: clip.clone(),
                                metadata: serde_json::json!({ "length": clip.len() }),
                            });
                            last = clip;
                        }
                    }
                }
                #[cfg(target_os = "linux")]
                {
                    if let Ok(clip) = get_clipboard_linux() {
                        if clip != last && !clip.trim().is_empty() && clip.len() < 5000 {
                            let _ = tx2.send(Observation {
                                id: Uuid::new_v4().to_string(),
                                timestamp: Utc::now().to_rfc3339(),
                                source: "clipboard".to_string(),
                                path: None,
                                content_preview: clip.clone(),
                                metadata: serde_json::json!({ "length": clip.len() }),
                            });
                            last = clip;
                        }
                    }
                }
                #[cfg(target_os = "windows")]
                {
                    if let Ok(clip) = get_clipboard_windows() {
                        if clip != last && !clip.trim().is_empty() && clip.len() < 5000 {
                            let _ = tx2.send(Observation {
                                id: Uuid::new_v4().to_string(),
                                timestamp: Utc::now().to_rfc3339(),
                                source: "clipboard".to_string(),
                                path: None,
                                content_preview: clip.clone(),
                                metadata: serde_json::json!({ "length": clip.len() }),
                            });
                            last = clip;
                        }
                    }
                }
                time::sleep(Duration::from_secs(3)).await;
            }
        });

        // 3. Screenshot a cada 30s
        let tx3 = tx.clone();
        let screenshot_dir = data_dir.join("screenshots");
        tokio::spawn(async move {
            let mut interval = time::interval(Duration::from_secs(30));
            loop {
                interval.tick().await;
                let filename = format!("{}.png", Utc::now().format("%Y%m%d_%H%M%S"));
                let path = screenshot_dir.join(&filename);

                if capture_screenshot(&path).is_ok() {
                    let _ = tx3.send(Observation {
                        id: Uuid::new_v4().to_string(),
                        timestamp: Utc::now().to_rfc3339(),
                        source: "screenshot".to_string(),
                        path: Some(path.to_string_lossy().to_string()),
                        content_preview: String::new(),
                        metadata: serde_json::json!({ "filename": filename }),
                    });
                }
            }
        });

        // 4. Input activity (teclado/mouse) - detecta se está ativo
        let tx4 = tx.clone();
        tokio::spawn(async move {
            let mut last_activity = Instant::now();
            loop {
                let has_activity = check_input_activity();
                if has_activity {
                    if last_activity.elapsed() > Duration::from_secs(60) {
                        let _ = tx4.send(Observation {
                            id: Uuid::new_v4().to_string(),
                            timestamp: Utc::now().to_rfc3339(),
                            source: "input_activity".to_string(),
                            path: None,
                            content_preview: "Usuário ativo".to_string(),
                            metadata: serde_json::json!({}),
                        });
                    }
                    last_activity = Instant::now();
                }
                time::sleep(Duration::from_millis(500)).await;
            }
        });

        // 5. Browser history (Chrome + Firefox) - a cada 5 min
        let tx5 = tx.clone();
        tokio::spawn(async move {
            let mut interval = time::interval(Duration::from_secs(300));
            loop {
                interval.tick().await;
                if let Ok(history) = Self::scrape_browser_history() {
                    for entry in history.iter().take(10) {
                        let _ = tx5.send(Observation {
                            id: Uuid::new_v4().to_string(),
                            timestamp: Utc::now().to_rfc3339(),
                            source: "browser_history".to_string(),
                            path: None,
                            content_preview: entry
                                .title
                                .clone()
                                .unwrap_or_else(|| entry.url.clone()),
                            metadata: serde_json::json!({
                                "url": entry.url,
                                "visit_time": entry.visit_time
                            }),
                        });
                    }
                }
            }
        });

        // 6. HealthKit bridge (v0.3) - localhost:8081
        let tx6 = tx.clone();
        tokio::spawn(async move {
            let app = Router::new().route(
                "/health",
                post(move |Json(payload): Json<Value>| {
                    let tx = tx6.clone();
                    async move {
                        let hrv = payload
                            .get("hrv_sdnn")
                            .and_then(|v| v.as_f64())
                            .unwrap_or(0.0);
                        let hr = payload.get("hr").and_then(|v| v.as_f64()).unwrap_or(0.0);
                        let spo2 = payload.get("spo2").and_then(|v| v.as_f64()).unwrap_or(0.0);

                        let _ = tx.send(Observation {
                            id: Uuid::new_v4().to_string(),
                            timestamp: Utc::now().to_rfc3339(),
                            source: "healthkit".to_string(),
                            path: None,
                            content_preview: format!(
                                "HRV: {:.1}ms, HR: {:.0}bpm, SpO2: {:.0}%",
                                hrv, hr, spo2
                            ),
                            metadata: payload,
                        });
                        "ok"
                    }
                }),
            );

            info!("HealthKit bridge ativo em http://localhost:8081/health");

            let listener = tokio::net::TcpListener::bind("0.0.0.0:8081")
                .await
                .expect("Falha ao bind na porta 8081");

            axum::serve(listener, app)
                .await
                .expect("Falha ao iniciar servidor HealthKit");
        });

        info!("Universal Observer v0.2 + v0.3 ATIVA TUDO – surveillance total iniciada");
        Ok(())
    }

    pub fn scrape_browser_history() -> anyhow::Result<Vec<BrowserEntry>> {
        // Chrome (Linux/macOS)
        let home = std::env::var("HOME")?;
        let chrome_paths = [
            format!("{}/.config/google-chrome/Default/History", home),
            format!(
                "{}/Library/Application Support/Google/Chrome/Default/History",
                home
            ),
        ];

        for path in &chrome_paths {
            if Path::new(path).exists() {
                if let Ok(output) = std::process::Command::new("sqlite3")
                    .arg(path)
                    .arg("SELECT url, title, datetime(last_visit_time/1000000-11644473600, 'unixepoch') FROM urls ORDER BY last_visit_time DESC LIMIT 10")
                    .output()
                {
                    let text = String::from_utf8_lossy(&output.stdout);
                    let mut entries = Vec::new();
                    for line in text.lines() {
                        let parts: Vec<&str> = line.split('|').collect();
                        if parts.len() >= 2 {
                            entries.push(BrowserEntry {
                                url: parts[0].to_string(),
                                title: Some(parts[1].to_string()),
                                visit_time: parts.get(2).map(|s| s.to_string()),
                            });
                        }
                    }
                    if !entries.is_empty() {
                        return Ok(entries);
                    }
                }
            }
        }

        // Firefox (Linux/macOS)
        let firefox_pattern = format!("{}/.mozilla/firefox/*/places.sqlite", home);
        if let Ok(output) = std::process::Command::new("sh")
            .arg("-c")
            .arg(format!(
                "find {} -name places.sqlite 2>/dev/null | head -1",
                firefox_pattern.replace("/*/", "/")
            ))
            .output()
        {
            let path = String::from_utf8_lossy(&output.stdout).trim().to_string();
            if !path.is_empty() && Path::new(&path).exists() {
                if let Ok(output) = std::process::Command::new("sqlite3")
                    .arg(&path)
                    .arg("SELECT url, title, datetime(last_visit_date/1000000, 'unixepoch') FROM moz_places ORDER BY last_visit_date DESC LIMIT 10")
                    .output()
                {
                    let text = String::from_utf8_lossy(&output.stdout);
                    let mut entries = Vec::new();
                    for line in text.lines() {
                        let parts: Vec<&str> = line.split('|').collect();
                        if parts.len() >= 2 {
                            entries.push(BrowserEntry {
                                url: parts[0].to_string(),
                                title: Some(parts[1].to_string()),
                                visit_time: parts.get(2).map(|s| s.to_string()),
                            });
                        }
                    }
                    if !entries.is_empty() {
                        return Ok(entries);
                    }
                }
            }
        }

        Ok(Vec::new())
    }

    /// Obtém timeline de contexto para um run_id específico
    pub async fn get_context_timeline(&self, run_id: &str) -> Vec<Observation> {
        let timeline = self.context_timeline.read().await;
        timeline.get(run_id).cloned().unwrap_or_default()
    }

    /// Adiciona observação à timeline de um run_id
    pub async fn add_to_timeline(&self, run_id: &str, observation: Observation) {
        let mut timeline = self.context_timeline.write().await;
        timeline
            .entry(run_id.to_string())
            .or_insert_with(Vec::new)
            .push(observation);
    }

    /// Obtém todas as observações dentro de um intervalo de tempo para um run_id
    pub async fn get_context_timeline_range(
        &self,
        run_id: &str,
        start_time: Option<chrono::DateTime<Utc>>,
        end_time: Option<chrono::DateTime<Utc>>,
    ) -> Vec<Observation> {
        let timeline = self.context_timeline.read().await;
        let observations = timeline.get(run_id).cloned().unwrap_or_default();

        if start_time.is_none() && end_time.is_none() {
            return observations;
        }

        observations
            .into_iter()
            .filter(|obs| {
                if let Ok(timestamp) = chrono::DateTime::parse_from_rfc3339(&obs.timestamp) {
                    let dt = timestamp.with_timezone(&chrono::Utc);
                    let after_start = start_time.map(|st| dt >= st).unwrap_or(true);
                    let before_end = end_time.map(|et| dt <= et).unwrap_or(true);
                    after_start && before_end
                } else {
                    false
                }
            })
            .collect()
    }

    pub async fn physiological_state_analysis(
        &self,
        observations: &[Observation],
    ) -> anyhow::Result<String> {
        let health_obs: Vec<&Observation> = observations
            .iter()
            .filter(|o| o.source == "healthkit")
            .rev()
            .take(10)
            .collect();

        if health_obs.is_empty() {
            return Ok("Nenhum dado de HealthKit disponível ainda.".to_string());
        }

        let prompt = format!(
            "Você é o metacognitor fisiológico do Demetrios.\n\
            Aqui estão os últimos {} pontos de HealthKit (HRV, frequência cardíaca, SpO2, minutos mindful).\n\n\
            Dados:\n{}\n\n\
            Diagnóstico brutal em 5 linhas:\n\
            1. Estado cognitivo atual (flow / stress / burnout)\n\
            2. Qualidade do sono recente\n\
            3. Nível real de mindfulness vs intenção\n\
            4. Recomendação fisiológica imediata (respiração 4-7-8, caminhada, cochilo, etc.)\n\
            5. Impacto previsto na produtividade científica hoje\n\nResposta:",
            health_obs.len(),
            serde_json::to_string_pretty(&health_obs)?
        );

        let router = beagle_llm::BeagleRouter;
        router.complete(&prompt).await
    }

    /// Resume contexto para um run_id específico
    pub async fn summarize_context_for_run(&self, run_id: &str) -> anyhow::Result<ContextSummary> {
        let observations = self.get_context_timeline(run_id).await;

        // Últimas N observações (limitado a 50 mais recentes)
        let recent_obs = observations
            .iter()
            .rev()
            .take(50)
            .cloned()
            .collect::<Vec<_>>();

        // Extrai tags dominantes dos metadados
        let mut tag_counts: std::collections::HashMap<String, usize> =
            std::collections::HashMap::new();
        for obs in &observations {
            if let Some(tags) = obs.metadata.get("tags").and_then(|v| v.as_array()) {
                for tag in tags {
                    if let Some(tag_str) = tag.as_str() {
                        *tag_counts.entry(tag_str.to_string()).or_insert(0) += 1;
                    }
                }
            }

            // Extrai tags implícitas de source
            match obs.source.as_str() {
                "pbpk" | "PBPK" => *tag_counts.entry("PBPK".to_string()).or_insert(0) += 1,
                "helio" | "Heliobiology" => {
                    *tag_counts.entry("Helio".to_string()).or_insert(0) += 1
                }
                "scaffold" | "Scaffold" => {
                    *tag_counts.entry("Scaffold".to_string()).or_insert(0) += 1
                }
                "pcs" | "PCS" => *tag_counts.entry("PCS".to_string()).or_insert(0) += 1,
                _ => {}
            }
        }

        // Top N tags (ordenadas por frequência)
        let mut tags: Vec<(String, usize)> = tag_counts.into_iter().collect();
        tags.sort_by(|a, b| b.1.cmp(&a.1));
        let dominant_tags: Vec<String> = tags.into_iter().take(5).map(|(tag, _)| tag).collect();

        // Calcula entropia/fragmentação simplificada
        // Baseado na diversidade de sources
        let unique_sources: std::collections::HashSet<String> =
            observations.iter().map(|o| o.source.clone()).collect();
        let entropy_level = if observations.is_empty() {
            None
        } else {
            // Normaliza para [0, 1] onde 1 = alta fragmentação
            Some(unique_sources.len() as f32 / observations.len().max(1) as f32)
        };

        Ok(ContextSummary {
            run_id: run_id.to_string(),
            recent_events: recent_obs,
            dominant_tags,
            entropy_level,
        })
    }
}

/// Resumo de contexto para um run_id
#[derive(Debug, Clone, Serialize)]
pub struct ContextSummary {
    pub run_id: String,
    pub recent_events: Vec<Observation>,
    pub dominant_tags: Vec<String>,
    pub entropy_level: Option<f32>,
}

// Clipboard functions
#[cfg(target_os = "macos")]
pub fn get_clipboard_macos() -> anyhow::Result<String> {
    use std::process::Command;
    let output = Command::new("pbpaste").output()?;
    Ok(String::from_utf8_lossy(&output.stdout).to_string())
}

#[cfg(target_os = "linux")]
pub fn get_clipboard_linux() -> anyhow::Result<String> {
    use std::process::Command;
    // Tenta xclip primeiro
    if let Ok(output) = Command::new("xclip")
        .arg("-selection")
        .arg("clipboard")
        .arg("-o")
        .output()
    {
        if output.status.success() {
            return Ok(String::from_utf8_lossy(&output.stdout).to_string());
        }
    }
    // Fallback para xsel
    let output = Command::new("xsel")
        .arg("--clipboard")
        .arg("--output")
        .output()?;
    Ok(String::from_utf8_lossy(&output.stdout).to_string())
}

#[cfg(target_os = "windows")]
fn get_clipboard_windows() -> anyhow::Result<String> {
    // Windows clipboard via PowerShell
    use std::process::Command;
    let output = Command::new("powershell")
        .arg("-Command")
        .arg("Get-Clipboard")
        .output()?;
    Ok(String::from_utf8_lossy(&output.stdout).to_string())
}

// Screenshot functions
fn capture_screenshot(path: &Path) -> anyhow::Result<()> {
    #[cfg(target_os = "macos")]
    {
        use std::process::Command;
        Command::new("screencapture").arg("-x").arg(path).output()?;
        Ok(())
    }

    #[cfg(target_os = "linux")]
    {
        use std::process::Command;
        // Tenta gnome-screenshot primeiro
        if Command::new("gnome-screenshot")
            .arg("-f")
            .arg(path)
            .output()
            .is_ok()
        {
            return Ok(());
        }
        // Fallback para scrot
        Command::new("scrot").arg(path).output()?;
        Ok(())
    }

    #[cfg(target_os = "windows")]
    {
        // Windows screenshot via PowerShell
        use std::process::Command;
        let script = format!(
            "Add-Type -AssemblyName System.Windows.Forms,System.Drawing; $bounds = [System.Windows.Forms.Screen]::PrimaryScreen.Bounds; $bmp = New-Object System.Drawing.Bitmap $bounds.Width, $bounds.Height; $graphics = [System.Drawing.Graphics]::FromImage($bmp); $graphics.CopyFromScreen($bounds.Location, [System.Drawing.Point]::Empty, $bounds.Size); $bmp.Save('{}'); $graphics.Dispose(); $bmp.Dispose()",
            path.display()
        );
        Command::new("powershell")
            .arg("-Command")
            .arg(&script)
            .output()?;
        Ok(())
    }

    #[cfg(not(any(target_os = "macos", target_os = "linux", target_os = "windows")))]
    {
        Err(anyhow::anyhow!("Screenshot não suportado nesta plataforma"))
    }
}

// Input activity detection
fn check_input_activity() -> bool {
    #[cfg(target_os = "macos")]
    {
        // macOS: verifica se há processos de input ativos
        use std::process::Command;
        if let Ok(output) = Command::new("ps").arg("aux").output() {
            let text = String::from_utf8_lossy(&output.stdout);
            // Verifica se há atividade de teclado/mouse (simplificado)
            return text.contains("WindowServer") || text.contains("loginwindow");
        }
    }

    #[cfg(target_os = "linux")]
    {
        // Linux: verifica eventos de input
        use std::process::Command;
        if let Ok(output) = Command::new("xset").arg("q").output() {
            return output.status.success();
        }
    }

    #[cfg(target_os = "windows")]
    {
        // Windows: sempre retorna true (simplificado)
        return true;
    }

    false
}
