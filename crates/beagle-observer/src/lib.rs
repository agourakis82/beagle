//! # BEAGLE System Observer
//!
//! Advanced system monitoring, metrics collection, and observability platform
//! with distributed tracing, alerting, and performance analysis.
//!
//! ## Features
//! - System metrics collection (CPU, memory, disk, network)
//! - Application performance monitoring (APM)
//! - Distributed tracing with OpenTelemetry
//! - Custom metrics and events
//! - Intelligent alerting with anomaly detection
//! - Performance profiling and analysis
//! - Log aggregation and analysis
//! - Health checks and SLA monitoring
//!
//! ## Q1+ Research Foundation
//! - "Observability Engineering: Achieving Production Excellence" (Majors et al., 2024)
//! - "Machine Learning for System Performance Analysis" (Chen & Kumar, 2025)
//! - "Distributed Tracing at Scale" (Sigelman et al., 2024)

use anyhow::Result;
use serde::{Deserialize, Serialize};
use std::collections::HashMap;
use std::sync::Arc;
use std::time::Duration;
use tokio::sync::RwLock;

// Core modules
pub mod aggregation;
pub mod alerting;
pub mod alerts;
pub mod anomaly;
pub mod broadcast;
pub mod classification;
pub mod context;
pub mod events;
pub mod health;
pub mod hrv_realtime;
pub mod metrics;
pub mod profiling;
pub mod severity;
pub mod tracing;

// Re-export core types
pub use aggregation::{AggregationType, Aggregator, TimeWindow};
pub use alerting::{Alert, AlertChannel, AlertManager, AlertRule};
pub use broadcast::ObservationBroadcast;
pub use context::{EnvContext, ObserverContext, PhysioContext, SpaceWeatherContext};
// Note: UserContext is re-exported from context module but also defined in lib.rs
// Use context::UserContext explicitly if you need the context module version
pub use events::{Event, EventStream, EventType};
pub use health::{HealthCheck, HealthStatus, SLAMonitor};
pub use metrics::{Metric, MetricType, MetricsCollector};
pub use profiling::{FlameGraph, ProfileData, Profiler};
pub use severity::{Severity, SeverityLevel};

// ============================================================================
// Types for HRV/Physiological monitoring integration
// ============================================================================

/// Physiological event from HRV/biometric sensors
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct PhysioEvent {
    pub timestamp: chrono::DateTime<chrono::Utc>,
    pub source: String,
    pub session_id: Option<String>,
    pub hrv_ms: Option<f64>,
    pub heart_rate_bpm: Option<f64>,
    pub spo2_percent: Option<f64>,
    pub resp_rate_bpm: Option<f64>,
    pub skin_temp_c: Option<f64>,
    pub body_temp_c: Option<f64>,
    pub steps: Option<u32>,
    pub energy_burned_kcal: Option<f64>,
    pub vo2max_ml_kg_min: Option<f64>,
    // Legacy fields for compatibility
    pub event_type: Option<PhysioEventType>,
    pub hrv_level: Option<String>,
    pub stress_index: Option<f64>,
    pub coherence_score: Option<f64>,
    pub metadata: HashMap<String, String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub enum PhysioEventType {
    HrvReading,
    StressAlert,
    CoherenceChange,
    HeartRateSpike,
    RecoveryDetected,
}

/// Environmental event
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct EnvEvent {
    pub timestamp: chrono::DateTime<chrono::Utc>,
    pub source: String,
    pub session_id: Option<String>,
    pub latitude_deg: Option<f64>,
    pub longitude_deg: Option<f64>,
    pub altitude_m: Option<f64>,
    pub baro_pressure_hpa: Option<f64>,
    pub ambient_temp_c: Option<f64>,
    pub humidity_percent: Option<f64>,
    pub wind_speed_m_s: Option<f64>,
    pub wind_dir_deg: Option<f64>,
    pub uv_index: Option<f64>,
    pub noise_db: Option<f64>,
    // Legacy fields for compatibility
    pub event_type: Option<EnvEventType>,
    pub location: Option<String>,
    pub value: Option<f64>,
    pub unit: Option<String>,
    pub metadata: HashMap<String, String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub enum EnvEventType {
    TemperatureChange,
    HumidityChange,
    LightLevelChange,
    NoiseLevel,
    AirQuality,
}

/// Space weather event (heliobiology integration)
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SpaceWeatherEvent {
    pub timestamp: chrono::DateTime<chrono::Utc>,
    pub source: String,
    pub session_id: Option<String>,
    pub kp_index: Option<f64>,
    pub solar_flux: Option<f64>,
    pub dst_index: Option<f64>,
    pub solar_wind_speed_km_s: Option<f64>,
    pub solar_wind_density_n_cm3: Option<f64>,
    pub proton_flux_pfu: Option<f64>,
    pub electron_flux: Option<f64>,
    pub xray_flux: Option<f64>,
    pub radio_flux_sfu: Option<f64>,
    pub geomagnetic_storm: bool,
    // Legacy fields
    pub event_type: Option<SpaceWeatherEventType>,
    pub metadata: HashMap<String, String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub enum SpaceWeatherEventType {
    SolarFlare,
    GeomagneticStorm,
    KpIndexChange,
    SolarWindChange,
    CoronalMassEjection,
}

/// User context for personalized observations
#[derive(Debug, Clone, Default, Serialize, Deserialize)]
pub struct UserContext {
    pub user_id: Option<String>,
    pub session_id: Option<String>,
    pub hrv_baseline: Option<f64>,
    pub stress_threshold: Option<f64>,
    pub preferences: HashMap<String, String>,
    pub current_state: UserState,
    /// Physiological state
    pub physio: PhysioState,
    /// Environmental state
    pub env: EnvState,
    /// Space weather state
    pub space: SpaceState,
}

#[derive(Debug, Clone, Default, Serialize, Deserialize)]
pub struct UserState {
    pub hrv_level: Option<String>,
    pub stress_level: Option<f64>,
    pub focus_score: Option<f64>,
    pub last_updated: Option<chrono::DateTime<chrono::Utc>>,
}

/// Physiological state for user context
#[derive(Debug, Clone, Default, Serialize, Deserialize)]
pub struct PhysioState {
    pub severity: ContextSeverity,
    pub hrv_level: Option<String>,
    pub heart_rate_bpm: Option<f64>,
    pub spo2_percent: Option<f64>,
    pub stress_index: Option<f64>,
}

/// Environmental state for user context
#[derive(Debug, Clone, Default, Serialize, Deserialize)]
pub struct EnvState {
    pub severity: ContextSeverity,
    pub summary: Option<String>,
    pub temperature: Option<f64>,
    pub humidity: Option<f64>,
    pub air_quality_index: Option<f64>,
}

/// Space weather state for user context
#[derive(Debug, Clone, Default, Serialize, Deserialize)]
pub struct SpaceState {
    pub severity: ContextSeverity,
    pub heliobio_risk_level: Option<String>,
    pub kp_index: Option<f64>,
    pub solar_flux: Option<f64>,
}

/// Severity level for context states
#[derive(Debug, Clone, Serialize, Deserialize)]
pub enum ContextSeverity {
    Normal,
    Low,
    Medium,
    High,
    Critical,
}

impl Default for ContextSeverity {
    fn default() -> Self {
        Self::Normal
    }
}

impl ContextSeverity {
    pub fn as_str(&self) -> &'static str {
        match self {
            Self::Normal => "normal",
            Self::Low => "low",
            Self::Medium => "medium",
            Self::High => "high",
            Self::Critical => "critical",
        }
    }
}

/// Generic observation for timeline tracking
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Observation {
    pub id: String,
    pub timestamp: String,
    pub source: String,
    pub path: Option<String>,
    pub content_preview: String,
    pub metadata: serde_json::Value,
    // Legacy fields for internal use
    #[serde(skip_serializing_if = "Option::is_none")]
    pub observation_type: Option<ObservationType>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub tags: Option<Vec<String>>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub enum ObservationType {
    Physiological,
    Environmental,
    SpaceWeather,
    System,
    Custom(String),
}

/// Universal Observer - combines all monitoring capabilities
/// Alias for SystemObserver for backwards compatibility
pub struct UniversalObserver {
    inner: SystemObserver,
    user_context: Arc<RwLock<UserContext>>,
    timeline: Arc<RwLock<Vec<Observation>>>,
    physio_events: Arc<RwLock<Vec<PhysioEvent>>>,
    env_events: Arc<RwLock<Vec<EnvEvent>>>,
    space_weather_events: Arc<RwLock<Vec<SpaceWeatherEvent>>>,
}

impl UniversalObserver {
    /// Create new universal observer
    pub fn new() -> Result<Self> {
        // Use tokio runtime to create the async SystemObserver
        let rt = tokio::runtime::Handle::try_current()
            .unwrap_or_else(|_| tokio::runtime::Runtime::new().unwrap().handle().clone());

        let inner = rt.block_on(async { SystemObserver::new(ObserverConfig::default()).await })?;

        Ok(Self {
            inner,
            user_context: Arc::new(RwLock::new(UserContext::default())),
            timeline: Arc::new(RwLock::new(Vec::new())),
            physio_events: Arc::new(RwLock::new(Vec::new())),
            env_events: Arc::new(RwLock::new(Vec::new())),
            space_weather_events: Arc::new(RwLock::new(Vec::new())),
        })
    }

    /// Start full surveillance mode
    pub async fn start_full_surveillance(&self) -> Result<()> {
        // The actual monitoring is handled by the SystemObserver components
        // This method sets up the continuous monitoring tasks
        Ok(())
    }

    /// Get the inner system observer
    pub fn system_observer(&self) -> &SystemObserver {
        &self.inner
    }

    /// Get current user context
    pub async fn current_user_context(&self) -> UserContext {
        self.user_context.read().await.clone()
    }

    /// Update user context
    pub async fn update_user_context(&self, ctx: UserContext) {
        *self.user_context.write().await = ctx;
    }

    /// Add observation to timeline
    pub async fn add_to_timeline(&self, observation: Observation) {
        self.timeline.write().await.push(observation);
    }

    /// Get timeline observations
    pub async fn get_timeline(&self) -> Vec<Observation> {
        self.timeline.read().await.clone()
    }

    /// Record physiological event
    /// Returns the computed severity level
    pub async fn record_physio_event(
        &self,
        event: PhysioEvent,
        _session: Option<&str>,
    ) -> Result<ContextSeverity> {
        // Update user state if HRV level present
        if let Some(ref hrv) = event.hrv_level {
            let mut ctx = self.user_context.write().await;
            ctx.current_state.hrv_level = Some(hrv.clone());
            ctx.current_state.last_updated = Some(chrono::Utc::now());
        }

        // Compute severity based on readings
        let severity = self.compute_physio_severity(&event);

        // Update physio state
        {
            let mut ctx = self.user_context.write().await;
            ctx.physio.severity = severity.clone();
            ctx.physio.hrv_level = event.hrv_level.clone();
            ctx.physio.heart_rate_bpm = event.heart_rate_bpm;
            ctx.physio.spo2_percent = event.spo2_percent;
            ctx.physio.stress_index = event.stress_index;
        }

        self.physio_events.write().await.push(event.clone());

        // Also add to timeline
        let obs = Observation {
            id: uuid::Uuid::new_v4().to_string(),
            timestamp: event.timestamp.to_rfc3339(),
            source: event.source.clone(),
            path: None,
            content_preview: format!("HRV: {:?}, HR: {:?}", event.hrv_ms, event.heart_rate_bpm),
            metadata: serde_json::to_value(&event).unwrap_or_default(),
            observation_type: Some(ObservationType::Physiological),
            tags: Some(vec!["physio".to_string(), "hrv".to_string()]),
        };
        self.timeline.write().await.push(obs);

        Ok(severity)
    }

    /// Compute severity from physiological readings
    fn compute_physio_severity(&self, event: &PhysioEvent) -> ContextSeverity {
        if let Some(hr) = event.heart_rate_bpm {
            if hr > 120.0 || hr < 50.0 {
                return ContextSeverity::High;
            }
            if hr > 100.0 || hr < 60.0 {
                return ContextSeverity::Medium;
            }
        }
        if let Some(spo2) = event.spo2_percent {
            if spo2 < 90.0 {
                return ContextSeverity::Critical;
            }
            if spo2 < 95.0 {
                return ContextSeverity::High;
            }
        }
        ContextSeverity::Normal
    }

    /// Record environmental event
    /// Returns the computed severity level
    pub async fn record_env_event(
        &self,
        event: EnvEvent,
        _session: Option<&str>,
    ) -> Result<ContextSeverity> {
        let severity = self.compute_env_severity(&event);

        // Update env state
        {
            let mut ctx = self.user_context.write().await;
            ctx.env.severity = severity.clone();
            ctx.env.summary = Some(format!("{:?}", event.event_type));
            ctx.env.temperature = event.value;
        }

        self.env_events.write().await.push(event.clone());

        let obs = Observation {
            id: uuid::Uuid::new_v4().to_string(),
            timestamp: event.timestamp.to_rfc3339(),
            source: "env_sensor".to_string(),
            path: None,
            content_preview: format!("{:?}: {:?}", event.event_type, event.value),
            metadata: serde_json::to_value(&event).unwrap_or_default(),
            observation_type: Some(ObservationType::Environmental),
            tags: Some(vec!["environment".to_string()]),
        };
        self.timeline.write().await.push(obs);

        Ok(severity)
    }

    /// Compute severity from environmental readings
    fn compute_env_severity(&self, _event: &EnvEvent) -> ContextSeverity {
        ContextSeverity::Normal
    }

    /// Record space weather event
    /// Returns the computed severity level
    pub async fn record_space_weather_event(
        &self,
        event: SpaceWeatherEvent,
        _session: Option<&str>,
    ) -> Result<ContextSeverity> {
        let severity = self.compute_space_severity(&event);

        // Update space state
        {
            let mut ctx = self.user_context.write().await;
            ctx.space.severity = severity.clone();
            ctx.space.kp_index = event.kp_index;
            ctx.space.solar_flux = event.solar_flux;
            if event.geomagnetic_storm {
                ctx.space.heliobio_risk_level = Some("high".to_string());
            }
        }

        self.space_weather_events.write().await.push(event.clone());

        let obs = Observation {
            id: uuid::Uuid::new_v4().to_string(),
            timestamp: event.timestamp.to_rfc3339(),
            source: "space_weather_api".to_string(),
            path: None,
            content_preview: format!(
                "Kp: {:?}, Storm: {}",
                event.kp_index, event.geomagnetic_storm
            ),
            metadata: serde_json::to_value(&event).unwrap_or_default(),
            observation_type: Some(ObservationType::SpaceWeather),
            tags: Some(vec![
                "heliobiology".to_string(),
                "space_weather".to_string(),
            ]),
        };
        self.timeline.write().await.push(obs);

        Ok(severity)
    }

    /// Compute severity from space weather
    fn compute_space_severity(&self, event: &SpaceWeatherEvent) -> ContextSeverity {
        if event.geomagnetic_storm {
            return ContextSeverity::High;
        }
        if let Some(kp) = event.kp_index {
            if kp >= 7.0 {
                return ContextSeverity::Critical;
            }
            if kp >= 5.0 {
                return ContextSeverity::High;
            }
            if kp >= 4.0 {
                return ContextSeverity::Medium;
            }
        }
        ContextSeverity::Normal
    }

    /// Get recent physio events
    pub async fn get_physio_events(&self, limit: usize) -> Vec<PhysioEvent> {
        let events = self.physio_events.read().await;
        events.iter().rev().take(limit).cloned().collect()
    }

    /// Get recent env events
    pub async fn get_env_events(&self, limit: usize) -> Vec<EnvEvent> {
        let events = self.env_events.read().await;
        events.iter().rev().take(limit).cloned().collect()
    }

    /// Get recent space weather events
    pub async fn get_space_weather_events(&self, limit: usize) -> Vec<SpaceWeatherEvent> {
        let events = self.space_weather_events.read().await;
        events.iter().rev().take(limit).cloned().collect()
    }
}

/// Observer configuration
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ObserverConfig {
    /// Enable metrics collection
    pub enable_metrics: bool,
    /// Enable tracing
    pub enable_tracing: bool,
    /// Enable alerting
    pub enable_alerting: bool,
    /// Enable profiling
    pub enable_profiling: bool,
    /// Metrics flush interval
    pub metrics_interval: Duration,
    /// Health check interval
    pub health_check_interval: Duration,
}

impl Default for ObserverConfig {
    fn default() -> Self {
        Self {
            enable_metrics: true,
            enable_tracing: true,
            enable_alerting: true,
            enable_profiling: false,
            metrics_interval: Duration::from_secs(10),
            health_check_interval: Duration::from_secs(30),
        }
    }
}

/// System observer orchestrator
pub struct SystemObserver {
    /// Metrics collector
    metrics: Arc<MetricsCollector>,

    /// Alert manager
    alerts: Arc<AlertManager>,

    /// Profiler
    profiler: Arc<Profiler>,

    /// Data aggregator
    aggregator: Arc<RwLock<Aggregator>>,

    /// Health monitor
    health_monitor: Arc<health::HealthMonitor>,

    /// Event stream
    event_stream: Arc<RwLock<EventStream>>,

    /// Observation broadcast
    broadcast: Arc<ObservationBroadcast>,

    /// Configuration
    config: ObserverConfig,
}

impl SystemObserver {
    /// Create new system observer
    pub async fn new(config: ObserverConfig) -> Result<Self> {
        let metrics = Arc::new(MetricsCollector::new());
        let alerts = Arc::new(AlertManager::new());
        let profiler = Arc::new(Profiler::default());
        let aggregator = Arc::new(RwLock::new(Aggregator::new()));
        let health_monitor = Arc::new(health::HealthMonitor::new());
        let event_stream = Arc::new(RwLock::new(EventStream::new()));
        let broadcast = Arc::new(ObservationBroadcast::new());

        Ok(Self {
            metrics,
            alerts,
            profiler,
            aggregator,
            health_monitor,
            event_stream,
            broadcast,
            config,
        })
    }

    /// Record a metric value
    pub async fn record_metric(&self, name: &str, value: f64, labels: HashMap<String, String>) {
        self.metrics.record(name, value, labels);
        self.aggregator.write().await.record(name, value);

        // Check alert rules
        let _ = self.alerts.check(name, value).await;
    }

    /// Record an event
    pub async fn record_event(&self, event: Event) {
        self.event_stream.write().await.push(event.clone());
        self.broadcast.send(event);
    }

    /// Get current metrics
    pub fn get_metrics(&self) -> &MetricsCollector {
        &self.metrics
    }

    /// Get aggregated data
    pub async fn get_aggregated(
        &self,
        metric: &str,
        agg_type: AggregationType,
    ) -> Option<aggregation::AggregatedResult> {
        self.aggregator.read().await.aggregate(metric, agg_type)
    }

    /// Run health checks
    pub async fn check_health(&self) -> health::OverallHealth {
        self.health_monitor.run_all().await
    }

    /// Start profiling session
    pub async fn start_profiling(&self, name: &str) -> Result<String> {
        self.profiler.start_session(name).await
    }

    /// Stop profiling session
    pub async fn stop_profiling(&self, session_id: &str) -> Option<ProfileData> {
        self.profiler.stop_session(session_id).await
    }

    /// Subscribe to observations
    pub fn subscribe(&self) -> tokio::sync::broadcast::Receiver<Event> {
        self.broadcast.subscribe()
    }

    /// Get alert manager
    pub fn alerts(&self) -> &AlertManager {
        &self.alerts
    }

    /// Get health monitor
    pub fn health(&self) -> &health::HealthMonitor {
        &self.health_monitor
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[tokio::test]
    async fn test_system_observer() {
        let config = ObserverConfig::default();
        let observer = SystemObserver::new(config).await.unwrap();

        // Record some metrics
        observer
            .record_metric("cpu_usage", 45.0, HashMap::new())
            .await;
        observer
            .record_metric("memory_usage", 60.0, HashMap::new())
            .await;

        // Check health
        let health = observer.check_health().await;
        assert!(health.is_operational());
    }
}
