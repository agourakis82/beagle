//! Observer 2.0 - Eventos estruturados de baixo nível
//!
//! Três tipos de evento: fisiológico, ambiental local e clima espacial

use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};

/// Evento fisiológico (HRV, FC, SpO₂, temperatura, atividade)
#[derive(Serialize, Deserialize, Debug, Clone)]
pub struct PhysioEvent {
    pub timestamp: DateTime<Utc>,
    pub source: String, // "apple_watch_ultra", "iphone", "vision_pro", "airpods", etc.
    pub session_id: Option<String>, // para agrupar amostras por sessão de uso

    // Métricas cardiorrespiratórias
    pub hrv_ms: Option<f32>, // HRV (SDNN) em ms
    pub heart_rate_bpm: Option<f32>,
    pub spo2_percent: Option<f32>,  // SatO₂ estimada (%)
    pub resp_rate_bpm: Option<f32>, // frequência respiratória, se disponível

    // Temperatura (se disponíveis)
    pub skin_temp_c: Option<f32>, // temperatura de pele
    pub body_temp_c: Option<f32>, // temperatura corporal

    // Atividade
    pub steps: Option<u32>,
    pub energy_burned_kcal: Option<f32>,
    pub vo2max_ml_kg_min: Option<f32>,
}

/// Evento ambiental local (GPS, altitude, pressão, clima)
#[derive(Serialize, Deserialize, Debug, Clone)]
pub struct EnvEvent {
    pub timestamp: DateTime<Utc>,
    pub source: String, // "iphone", "vision_pro", "home_sensor", etc.
    pub session_id: Option<String>,

    // Localização
    pub latitude_deg: Option<f64>,
    pub longitude_deg: Option<f64>,
    pub altitude_m: Option<f32>,

    // Condições ambientais
    pub baro_pressure_hpa: Option<f32>,
    pub ambient_temp_c: Option<f32>,
    pub humidity_percent: Option<f32>,
    pub wind_speed_m_s: Option<f32>,
    pub wind_dir_deg: Option<f32>,
    pub uv_index: Option<f32>,
    pub noise_db: Option<f32>, // nível de ruído ambiente, se disponível
}

/// Evento de clima espacial (Kp, fluxo de partículas, vento solar)
#[derive(Serialize, Deserialize, Debug, Clone)]
pub struct SpaceWeatherEvent {
    pub timestamp: DateTime<Utc>,
    pub source: String, // "noaa_api", "nasa", "local_cache"
    pub session_id: Option<String>,

    // Índices geomagnéticos
    pub kp_index: Option<f32>,  // Kp 0–9 (NOAA)
    pub dst_index: Option<f32>, // se usar

    // Vento solar
    pub solar_wind_speed_km_s: Option<f32>,
    pub solar_wind_density_n_cm3: Option<f32>,

    // Partículas
    pub proton_flux_pfu: Option<f32>,
    pub electron_flux: Option<f32>,

    // Radiação
    pub xray_flux: Option<f32>,
    pub radio_flux_sfu: Option<f32>,
}

impl Default for PhysioEvent {
    fn default() -> Self {
        Self {
            timestamp: Utc::now(),
            source: String::new(),
            session_id: None,
            hrv_ms: None,
            heart_rate_bpm: None,
            spo2_percent: None,
            resp_rate_bpm: None,
            skin_temp_c: None,
            body_temp_c: None,
            steps: None,
            energy_burned_kcal: None,
            vo2max_ml_kg_min: None,
        }
    }
}

impl Default for EnvEvent {
    fn default() -> Self {
        Self {
            timestamp: Utc::now(),
            source: String::new(),
            session_id: None,
            latitude_deg: None,
            longitude_deg: None,
            altitude_m: None,
            baro_pressure_hpa: None,
            ambient_temp_c: None,
            humidity_percent: None,
            wind_speed_m_s: None,
            wind_dir_deg: None,
            uv_index: None,
            noise_db: None,
        }
    }
}

impl Default for SpaceWeatherEvent {
    fn default() -> Self {
        Self {
            timestamp: Utc::now(),
            source: String::new(),
            session_id: None,
            kp_index: None,
            dst_index: None,
            solar_wind_speed_km_s: None,
            solar_wind_density_n_cm3: None,
            proton_flux_pfu: None,
            electron_flux: None,
            xray_flux: None,
            radio_flux_sfu: None,
        }
    }
}

// =============================================================================
// Generic Event System for System Observer
// =============================================================================

use std::collections::HashMap;
use std::sync::Arc;
use tokio::sync::RwLock;

/// Generic event type for the observer system
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq, Hash)]
pub enum EventType {
    /// System metrics event
    Metric,
    /// Log event
    Log,
    /// Trace span event
    Trace,
    /// Alert event
    Alert,
    /// Health check event
    Health,
    /// Profile event
    Profile,
    /// Physiological event
    Physio,
    /// Environmental event
    Environment,
    /// Space weather event
    SpaceWeather,
    /// Custom event type
    Custom(String),
}

impl Default for EventType {
    fn default() -> Self {
        Self::Custom("unknown".to_string())
    }
}

/// Generic event for the observer system
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Event {
    /// Unique event ID
    pub id: String,
    /// Event type
    pub event_type: EventType,
    /// Event timestamp
    pub timestamp: DateTime<Utc>,
    /// Source of the event
    pub source: String,
    /// Event severity level
    pub severity: super::severity::Severity,
    /// Event message
    pub message: String,
    /// Structured data associated with the event
    pub data: HashMap<String, serde_json::Value>,
    /// Event tags for filtering
    pub tags: Vec<String>,
    /// Parent event ID for correlation
    pub parent_id: Option<String>,
    /// Trace ID for distributed tracing
    pub trace_id: Option<String>,
    /// Span ID for distributed tracing
    pub span_id: Option<String>,
}

impl Event {
    /// Create a new event
    pub fn new(event_type: EventType, source: &str, message: &str) -> Self {
        Self {
            id: uuid::Uuid::new_v4().to_string(),
            event_type,
            timestamp: Utc::now(),
            source: source.to_string(),
            severity: super::severity::Severity::Normal,
            message: message.to_string(),
            data: HashMap::new(),
            tags: Vec::new(),
            parent_id: None,
            trace_id: None,
            span_id: None,
        }
    }

    /// Create metric event
    pub fn metric(source: &str, name: &str, value: f64) -> Self {
        let mut event = Self::new(EventType::Metric, source, &format!("{}={}", name, value));
        event
            .data
            .insert("metric_name".to_string(), serde_json::json!(name));
        event
            .data
            .insert("metric_value".to_string(), serde_json::json!(value));
        event
    }

    /// Create log event
    pub fn log(source: &str, level: &str, message: &str) -> Self {
        let mut event = Self::new(EventType::Log, source, message);
        event
            .data
            .insert("level".to_string(), serde_json::json!(level));
        event
    }

    /// Create alert event
    pub fn alert(source: &str, rule_name: &str, message: &str) -> Self {
        let mut event = Self::new(EventType::Alert, source, message);
        event
            .data
            .insert("rule".to_string(), serde_json::json!(rule_name));
        event.severity = super::severity::Severity::High;
        event
    }

    /// Create health event
    pub fn health(source: &str, status: &str, message: &str) -> Self {
        let mut event = Self::new(EventType::Health, source, message);
        event
            .data
            .insert("status".to_string(), serde_json::json!(status));
        event
    }

    /// Set severity
    pub fn with_severity(mut self, severity: super::severity::Severity) -> Self {
        self.severity = severity;
        self
    }

    /// Add data field
    pub fn with_data(mut self, key: &str, value: serde_json::Value) -> Self {
        self.data.insert(key.to_string(), value);
        self
    }

    /// Add tag
    pub fn with_tag(mut self, tag: &str) -> Self {
        self.tags.push(tag.to_string());
        self
    }

    /// Set parent ID for correlation
    pub fn with_parent(mut self, parent_id: &str) -> Self {
        self.parent_id = Some(parent_id.to_string());
        self
    }

    /// Set trace context
    pub fn with_trace(mut self, trace_id: &str, span_id: &str) -> Self {
        self.trace_id = Some(trace_id.to_string());
        self.span_id = Some(span_id.to_string());
        self
    }

    /// Convert from PhysioEvent
    pub fn from_physio(physio: &PhysioEvent) -> Self {
        let mut event = Self::new(EventType::Physio, &physio.source, "Physiological event");
        event.timestamp = physio.timestamp;
        if let Some(hrv) = physio.hrv_ms {
            event
                .data
                .insert("hrv_ms".to_string(), serde_json::json!(hrv));
        }
        if let Some(hr) = physio.heart_rate_bpm {
            event
                .data
                .insert("heart_rate_bpm".to_string(), serde_json::json!(hr));
        }
        if let Some(spo2) = physio.spo2_percent {
            event
                .data
                .insert("spo2_percent".to_string(), serde_json::json!(spo2));
        }
        event
    }

    /// Convert from EnvEvent
    pub fn from_env(env: &EnvEvent) -> Self {
        let mut event = Self::new(EventType::Environment, &env.source, "Environmental event");
        event.timestamp = env.timestamp;
        if let Some(temp) = env.ambient_temp_c {
            event
                .data
                .insert("ambient_temp_c".to_string(), serde_json::json!(temp));
        }
        if let Some(lat) = env.latitude_deg {
            event
                .data
                .insert("latitude_deg".to_string(), serde_json::json!(lat));
        }
        if let Some(lon) = env.longitude_deg {
            event
                .data
                .insert("longitude_deg".to_string(), serde_json::json!(lon));
        }
        event
    }

    /// Convert from SpaceWeatherEvent
    pub fn from_space_weather(space: &SpaceWeatherEvent) -> Self {
        let mut event = Self::new(
            EventType::SpaceWeather,
            &space.source,
            "Space weather event",
        );
        event.timestamp = space.timestamp;
        if let Some(kp) = space.kp_index {
            event
                .data
                .insert("kp_index".to_string(), serde_json::json!(kp));
        }
        if let Some(wind) = space.solar_wind_speed_km_s {
            event
                .data
                .insert("solar_wind_speed_km_s".to_string(), serde_json::json!(wind));
        }
        event
    }
}

impl Default for Event {
    fn default() -> Self {
        Self::new(EventType::default(), "unknown", "")
    }
}

/// Event stream for collecting and processing events
#[derive(Debug)]
pub struct EventStream {
    /// Internal event buffer
    events: Vec<Event>,
    /// Maximum buffer size
    max_size: usize,
    /// Event filters by type
    filters: Vec<EventType>,
}

impl EventStream {
    /// Create a new event stream
    pub fn new() -> Self {
        Self {
            events: Vec::new(),
            max_size: 10000,
            filters: Vec::new(),
        }
    }

    /// Create with custom max size
    pub fn with_max_size(max_size: usize) -> Self {
        Self {
            events: Vec::new(),
            max_size,
            filters: Vec::new(),
        }
    }

    /// Push an event to the stream
    pub fn push(&mut self, event: Event) {
        // Check filters
        if !self.filters.is_empty() && !self.filters.contains(&event.event_type) {
            return;
        }

        self.events.push(event);

        // Trim if over max size
        if self.events.len() > self.max_size {
            self.events.drain(0..self.events.len() - self.max_size);
        }
    }

    /// Get all events
    pub fn events(&self) -> &[Event] {
        &self.events
    }

    /// Get events by type
    pub fn by_type(&self, event_type: &EventType) -> Vec<&Event> {
        self.events
            .iter()
            .filter(|e| &e.event_type == event_type)
            .collect()
    }

    /// Get events within time window
    pub fn in_window(&self, window: chrono::Duration) -> Vec<&Event> {
        let cutoff = Utc::now() - window;
        self.events
            .iter()
            .filter(|e| e.timestamp > cutoff)
            .collect()
    }

    /// Get events by source
    pub fn by_source(&self, source: &str) -> Vec<&Event> {
        self.events.iter().filter(|e| e.source == source).collect()
    }

    /// Get events with tag
    pub fn with_tag(&self, tag: &str) -> Vec<&Event> {
        self.events
            .iter()
            .filter(|e| e.tags.contains(&tag.to_string()))
            .collect()
    }

    /// Get events by trace ID
    pub fn by_trace(&self, trace_id: &str) -> Vec<&Event> {
        self.events
            .iter()
            .filter(|e| e.trace_id.as_deref() == Some(trace_id))
            .collect()
    }

    /// Add filter for event type
    pub fn add_filter(&mut self, event_type: EventType) {
        self.filters.push(event_type);
    }

    /// Clear filters
    pub fn clear_filters(&mut self) {
        self.filters.clear();
    }

    /// Get event count
    pub fn len(&self) -> usize {
        self.events.len()
    }

    /// Check if empty
    pub fn is_empty(&self) -> bool {
        self.events.is_empty()
    }

    /// Clear all events
    pub fn clear(&mut self) {
        self.events.clear();
    }

    /// Get statistics
    pub fn stats(&self) -> EventStreamStats {
        let mut by_type: HashMap<String, usize> = HashMap::new();
        let mut by_source: HashMap<String, usize> = HashMap::new();
        let mut by_severity: HashMap<String, usize> = HashMap::new();

        for event in &self.events {
            *by_type
                .entry(format!("{:?}", event.event_type))
                .or_insert(0) += 1;
            *by_source.entry(event.source.clone()).or_insert(0) += 1;
            *by_severity
                .entry(format!("{:?}", event.severity))
                .or_insert(0) += 1;
        }

        EventStreamStats {
            total_events: self.events.len(),
            by_type,
            by_source,
            by_severity,
        }
    }
}

impl Default for EventStream {
    fn default() -> Self {
        Self::new()
    }
}

/// Event stream statistics
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct EventStreamStats {
    pub total_events: usize,
    pub by_type: HashMap<String, usize>,
    pub by_source: HashMap<String, usize>,
    pub by_severity: HashMap<String, usize>,
}

#[cfg(test)]
mod event_tests {
    use super::*;

    #[test]
    fn test_event_creation() {
        let event = Event::new(EventType::Metric, "test", "test message");
        assert_eq!(event.source, "test");
        assert_eq!(event.message, "test message");
        assert_eq!(event.event_type, EventType::Metric);
    }

    #[test]
    fn test_event_stream() {
        let mut stream = EventStream::new();

        stream.push(Event::new(EventType::Metric, "test", "metric 1"));
        stream.push(Event::new(EventType::Log, "test", "log 1"));
        stream.push(Event::new(EventType::Alert, "alert", "alert 1"));

        assert_eq!(stream.len(), 3);
        assert_eq!(stream.by_type(&EventType::Metric).len(), 1);
        assert_eq!(stream.by_source("test").len(), 2);
    }

    #[test]
    fn test_event_from_physio() {
        let physio = PhysioEvent {
            heart_rate_bpm: Some(72.0),
            hrv_ms: Some(45.0),
            ..Default::default()
        };

        let event = Event::from_physio(&physio);
        assert_eq!(event.event_type, EventType::Physio);
        assert!(event.data.contains_key("heart_rate_bpm"));
        assert!(event.data.contains_key("hrv_ms"));
    }
}
