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
