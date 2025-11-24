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
