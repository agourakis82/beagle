//! Observer 2.0 - Contexto agregado do usuário

use crate::severity::Severity;
use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};

/// Contexto fisiológico agregado
#[derive(Serialize, Deserialize, Debug, Clone)]
pub struct PhysioContext {
    pub last_update: Option<DateTime<Utc>>,
    pub hrv_level: Option<String>, // "low" | "normal" | "high"
    pub severity: Severity,
    pub heart_rate_bpm: Option<f32>,
    pub spo2_percent: Option<f32>,
    pub stress_index: Option<f32>, // índice derivado de HRV/FC
}

/// Contexto ambiental agregado
#[derive(Serialize, Deserialize, Debug, Clone)]
pub struct EnvContext {
    pub last_update: Option<DateTime<Utc>>,
    pub severity: Severity,
    pub location: Option<(f64, f64, f32)>, // lat, lon, alt
    pub ambient_temp_c: Option<f32>,
    pub humidity_percent: Option<f32>,
    pub uv_index: Option<f32>,
    pub summary: Option<String>,
}

/// Contexto de clima espacial agregado
#[derive(Serialize, Deserialize, Debug, Clone)]
pub struct SpaceWeatherContext {
    pub last_update: Option<DateTime<Utc>>,
    pub severity: Severity,
    pub kp_index: Option<f32>,
    pub heliobio_risk_level: Option<String>, // "calm" | "moderate" | "storm"
}

/// Contexto completo do usuário agregando fisiológico, ambiental e clima espacial
#[derive(Serialize, Deserialize, Debug, Clone)]
pub struct UserContext {
    pub physio: PhysioContext,
    pub env: EnvContext,
    pub space: SpaceWeatherContext,
}

impl Default for PhysioContext {
    fn default() -> Self {
        Self {
            last_update: None,
            hrv_level: None,
            severity: Severity::Normal,
            heart_rate_bpm: None,
            spo2_percent: None,
            stress_index: None,
        }
    }
}

impl Default for EnvContext {
    fn default() -> Self {
        Self {
            last_update: None,
            severity: Severity::Normal,
            location: None,
            ambient_temp_c: None,
            humidity_percent: None,
            uv_index: None,
            summary: None,
        }
    }
}

impl Default for SpaceWeatherContext {
    fn default() -> Self {
        Self {
            last_update: None,
            severity: Severity::Normal,
            kp_index: None,
            heliobio_risk_level: None,
        }
    }
}

impl Default for UserContext {
    fn default() -> Self {
        Self {
            physio: PhysioContext::default(),
            env: EnvContext::default(),
            space: SpaceWeatherContext::default(),
        }
    }
}

impl SpaceWeatherContext {
    /// Calcula nível de risco heliobiológico a partir do Kp
    pub fn compute_heliobio_risk(kp: Option<f32>) -> Option<String> {
        kp.map(|k| {
            if k >= 7.0 {
                "storm".to_string()
            } else if k >= 5.0 {
                "moderate".to_string()
            } else {
                "calm".to_string()
            }
        })
    }
}

impl PhysioContext {
    /// Calcula índice de stress derivado de HRV e FC
    pub fn compute_stress_index(hrv_ms: Option<f32>, hr_bpm: Option<f32>) -> Option<f32> {
        match (hrv_ms, hr_bpm) {
            (Some(hrv), Some(hr)) => {
                // Heurística simples: stress inversamente proporcional a HRV, proporcional a FC
                // Normaliza para [0, 1] onde 1 = alto stress
                let hrv_norm = (hrv / 100.0).min(1.0); // HRV normal ~50-100ms
                let hr_norm = ((hr - 60.0) / 60.0).max(0.0).min(1.0); // FC normal ~60-100bpm
                Some(1.0 - hrv_norm * 0.6 + hr_norm * 0.4)
            }
            _ => None,
        }
    }
}

impl EnvContext {
    /// Gera resumo textual do ambiente
    pub fn compute_summary(&self) -> Option<String> {
        let mut parts = Vec::new();

        if let Some((lat, lon, alt)) = self.location {
            parts.push(format!(
                "Localização: {:.4}°N, {:.4}°E, {:.0}m",
                lat, lon, alt
            ));
        }

        if let Some(temp) = self.ambient_temp_c {
            parts.push(format!("Temp: {:.1}°C", temp));
        }

        if let Some(hum) = self.humidity_percent {
            parts.push(format!("Umidade: {:.0}%", hum));
        }

        if let Some(uv) = self.uv_index {
            parts.push(format!("UV: {:.1}", uv));
        }

        if parts.is_empty() {
            None
        } else {
            Some(parts.join(", "))
        }
    }
}

// =============================================================================
// Observer Context for System Monitoring
// =============================================================================

use std::collections::HashMap;
use std::sync::Arc;
use tokio::sync::RwLock;

/// Observer context for system-wide monitoring configuration and state
#[derive(Debug, Clone)]
pub struct ObserverContext {
    /// Context name/identifier
    pub name: String,
    /// Whether metrics collection is enabled
    pub metrics_enabled: bool,
    /// Whether tracing is enabled
    pub tracing_enabled: bool,
    /// Whether alerting is enabled
    pub alerting_enabled: bool,
    /// Custom labels for all metrics in this context
    pub labels: HashMap<String, String>,
    /// Parent context for hierarchical organization
    pub parent: Option<Arc<ObserverContext>>,
    /// Sampling rate for traces (0.0-1.0)
    pub trace_sample_rate: f64,
    /// Log level threshold
    pub log_level: LogLevel,
}

/// Log level for filtering
#[derive(Debug, Clone, Copy, PartialEq, Eq, PartialOrd, Ord, Serialize, Deserialize)]
pub enum LogLevel {
    Trace,
    Debug,
    Info,
    Warn,
    Error,
}

impl Default for LogLevel {
    fn default() -> Self {
        Self::Info
    }
}

impl ObserverContext {
    /// Create a new observer context
    pub fn new(name: &str) -> Self {
        Self {
            name: name.to_string(),
            metrics_enabled: true,
            tracing_enabled: true,
            alerting_enabled: true,
            labels: HashMap::new(),
            parent: None,
            trace_sample_rate: 1.0,
            log_level: LogLevel::Info,
        }
    }

    /// Create child context
    pub fn child(&self, name: &str) -> Self {
        let mut child = Self::new(&format!("{}.{}", self.name, name));
        child.parent = Some(Arc::new(self.clone()));
        child.labels = self.labels.clone();
        child.trace_sample_rate = self.trace_sample_rate;
        child.log_level = self.log_level;
        child
    }

    /// Add label
    pub fn with_label(mut self, key: &str, value: &str) -> Self {
        self.labels.insert(key.to_string(), value.to_string());
        self
    }

    /// Set trace sample rate
    pub fn with_sample_rate(mut self, rate: f64) -> Self {
        self.trace_sample_rate = rate.clamp(0.0, 1.0);
        self
    }

    /// Set log level
    pub fn with_log_level(mut self, level: LogLevel) -> Self {
        self.log_level = level;
        self
    }

    /// Disable metrics
    pub fn without_metrics(mut self) -> Self {
        self.metrics_enabled = false;
        self
    }

    /// Disable tracing
    pub fn without_tracing(mut self) -> Self {
        self.tracing_enabled = false;
        self
    }

    /// Disable alerting
    pub fn without_alerting(mut self) -> Self {
        self.alerting_enabled = false;
        self
    }

    /// Get full context path
    pub fn path(&self) -> String {
        self.name.clone()
    }

    /// Get all labels including inherited
    pub fn all_labels(&self) -> HashMap<String, String> {
        let mut labels = HashMap::new();

        // Get parent labels first
        if let Some(parent) = &self.parent {
            labels.extend(parent.all_labels());
        }

        // Override with own labels
        labels.extend(self.labels.clone());

        labels
    }

    /// Check if should sample this trace
    pub fn should_sample(&self) -> bool {
        if self.trace_sample_rate >= 1.0 {
            return true;
        }
        if self.trace_sample_rate <= 0.0 {
            return false;
        }
        rand::random::<f64>() < self.trace_sample_rate
    }

    /// Check if log level is enabled
    pub fn is_level_enabled(&self, level: LogLevel) -> bool {
        level >= self.log_level
    }
}

impl Default for ObserverContext {
    fn default() -> Self {
        Self::new("default")
    }
}

#[cfg(test)]
mod observer_context_tests {
    use super::*;

    #[test]
    fn test_context_creation() {
        let ctx = ObserverContext::new("test");
        assert_eq!(ctx.name, "test");
        assert!(ctx.metrics_enabled);
        assert!(ctx.tracing_enabled);
    }

    #[test]
    fn test_child_context() {
        let parent = ObserverContext::new("parent").with_label("env", "test");
        let child = parent.child("child");

        assert_eq!(child.name, "parent.child");
        assert!(child.parent.is_some());
        assert_eq!(child.all_labels().get("env"), Some(&"test".to_string()));
    }

    #[test]
    fn test_log_level() {
        let ctx = ObserverContext::new("test").with_log_level(LogLevel::Warn);

        assert!(!ctx.is_level_enabled(LogLevel::Info));
        assert!(ctx.is_level_enabled(LogLevel::Warn));
        assert!(ctx.is_level_enabled(LogLevel::Error));
    }
}
