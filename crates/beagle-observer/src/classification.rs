//! Observer 2.0 - Classificação de severidade

use crate::events::{EnvEvent, PhysioEvent, SpaceWeatherEvent};
use crate::severity::Severity;
use beagle_config::{EnvThresholds, PhysioThresholds, SpaceWeatherThresholds};

/// Classifica HRV em nível de severidade
pub fn classify_hrv(hrv_ms: f32, t: &PhysioThresholds) -> Severity {
    if hrv_ms <= t.hrv_low_ms {
        Severity::Moderate
    } else if hrv_ms <= t.hrv_low_ms * 1.5 {
        Severity::Mild
    } else {
        Severity::Normal
    }
}

/// Classifica SpO₂ em nível de severidade
pub fn classify_spo2(spo2: f32, t: &PhysioThresholds) -> Severity {
    if spo2 <= t.spo2_critical {
        Severity::Severe
    } else if spo2 <= t.spo2_warning {
        Severity::Moderate
    } else if spo2 < t.spo2_warning + 2.0 {
        Severity::Mild
    } else {
        Severity::Normal
    }
}

/// Classifica frequência cardíaca em nível de severidade
pub fn classify_hr(hr_bpm: f32, t: &PhysioThresholds) -> Severity {
    if hr_bpm >= t.hr_tachy_bpm || hr_bpm <= t.hr_brady_bpm {
        Severity::Moderate
    } else if hr_bpm >= t.hr_tachy_bpm * 0.9 || hr_bpm <= t.hr_brady_bpm * 1.1 {
        Severity::Mild
    } else {
        Severity::Normal
    }
}

/// Classifica frequência respiratória em nível de severidade
pub fn classify_resp_rate(resp_rate_bpm: f32, t: &PhysioThresholds) -> Severity {
    if resp_rate_bpm <= t.resp_rate_low_bpm || resp_rate_bpm >= t.resp_rate_high_bpm {
        Severity::Moderate
    } else if resp_rate_bpm <= t.resp_rate_low_bpm * 1.2
        || resp_rate_bpm >= t.resp_rate_high_bpm * 0.9
    {
        Severity::Mild
    } else {
        Severity::Normal
    }
}

/// Classifica temperatura de pele em nível de severidade
pub fn classify_skin_temp(temp_c: f32, t: &PhysioThresholds) -> Severity {
    if temp_c <= t.skin_temp_low_c || temp_c >= t.skin_temp_high_c {
        Severity::Moderate
    } else if temp_c <= t.skin_temp_low_c * 1.05 || temp_c >= t.skin_temp_high_c * 0.95 {
        Severity::Mild
    } else {
        Severity::Normal
    }
}

/// Agrega severidade de todos os indicadores fisiológicos
pub fn aggregate_physio_severity(ev: &PhysioEvent, th: &PhysioThresholds) -> Severity {
    let mut sev = Severity::Normal;

    if let Some(hrv) = ev.hrv_ms {
        sev = Severity::max(sev, classify_hrv(hrv, th));
    }
    if let Some(hr) = ev.heart_rate_bpm {
        sev = Severity::max(sev, classify_hr(hr, th));
    }
    if let Some(spo2) = ev.spo2_percent {
        sev = Severity::max(sev, classify_spo2(spo2, th));
    }
    if let Some(resp_rate) = ev.resp_rate_bpm {
        sev = Severity::max(sev, classify_resp_rate(resp_rate, th));
    }
    if let Some(skin_temp) = ev.skin_temp_c {
        sev = Severity::max(sev, classify_skin_temp(skin_temp, th));
    }

    sev
}

/// Classifica altitude em nível de severidade
pub fn classify_altitude(altitude_m: f32, t: &EnvThresholds) -> Severity {
    if altitude_m >= t.altitude_high_m {
        Severity::Moderate
    } else if altitude_m >= t.altitude_high_m * 0.7 {
        Severity::Mild
    } else {
        Severity::Normal
    }
}

/// Classifica pressão barométrica em nível de severidade
pub fn classify_baro_pressure(pressure_hpa: f32, t: &EnvThresholds) -> Severity {
    if pressure_hpa <= t.baro_low_hpa || pressure_hpa >= t.baro_high_hpa {
        Severity::Moderate
    } else if pressure_hpa <= t.baro_low_hpa * 1.02 || pressure_hpa >= t.baro_high_hpa * 0.98 {
        Severity::Mild
    } else {
        Severity::Normal
    }
}

/// Classifica temperatura ambiente em nível de severidade
pub fn classify_ambient_temp(temp_c: f32, t: &EnvThresholds) -> Severity {
    if temp_c <= t.temp_cold_c || temp_c >= t.temp_heat_c {
        Severity::Moderate
    } else if temp_c <= t.temp_cold_c * 1.2 || temp_c >= t.temp_heat_c * 0.9 {
        Severity::Mild
    } else {
        Severity::Normal
    }
}

/// Classifica índice UV em nível de severidade
pub fn classify_uv_index(uv: f32, t: &EnvThresholds) -> Severity {
    if uv >= t.uv_high {
        Severity::Moderate
    } else if uv >= t.uv_high * 0.8 {
        Severity::Mild
    } else {
        Severity::Normal
    }
}

/// Agrega severidade de todos os indicadores ambientais
pub fn aggregate_env_severity(ev: &EnvEvent, th: &EnvThresholds) -> Severity {
    let mut sev = Severity::Normal;

    if let Some(altitude) = ev.altitude_m {
        sev = Severity::max(sev, classify_altitude(altitude, th));
    }
    if let Some(pressure) = ev.baro_pressure_hpa {
        sev = Severity::max(sev, classify_baro_pressure(pressure, th));
    }
    if let Some(temp) = ev.ambient_temp_c {
        sev = Severity::max(sev, classify_ambient_temp(temp, th));
    }
    if let Some(uv) = ev.uv_index {
        sev = Severity::max(sev, classify_uv_index(uv, th));
    }

    sev
}

/// Classifica índice Kp (clima espacial) em nível de severidade
pub fn classify_kp_index(kp: f32, t: &SpaceWeatherThresholds) -> Severity {
    if kp >= t.kp_severe_storm {
        Severity::Severe
    } else if kp >= t.kp_storm {
        Severity::Moderate
    } else if kp >= t.kp_storm * 0.8 {
        Severity::Mild
    } else {
        Severity::Normal
    }
}

/// Classifica fluxo de prótons em nível de severidade
pub fn classify_proton_flux(flux_pfu: f32, t: &SpaceWeatherThresholds) -> Severity {
    if flux_pfu >= t.proton_flux_high_pfu {
        Severity::Moderate
    } else if flux_pfu >= t.proton_flux_high_pfu * 0.7 {
        Severity::Mild
    } else {
        Severity::Normal
    }
}

/// Classifica velocidade do vento solar em nível de severidade
pub fn classify_solar_wind_speed(speed_km_s: f32, t: &SpaceWeatherThresholds) -> Severity {
    if speed_km_s >= t.solar_wind_speed_high_km_s {
        Severity::Moderate
    } else if speed_km_s >= t.solar_wind_speed_high_km_s * 0.8 {
        Severity::Mild
    } else {
        Severity::Normal
    }
}

/// Agrega severidade de todos os indicadores de clima espacial
pub fn aggregate_space_severity(ev: &SpaceWeatherEvent, th: &SpaceWeatherThresholds) -> Severity {
    let mut sev = Severity::Normal;

    if let Some(kp) = ev.kp_index {
        sev = Severity::max(sev, classify_kp_index(kp, th));
    }
    if let Some(proton_flux) = ev.proton_flux_pfu {
        sev = Severity::max(sev, classify_proton_flux(proton_flux, th));
    }
    if let Some(solar_wind) = ev.solar_wind_speed_km_s {
        sev = Severity::max(sev, classify_solar_wind_speed(solar_wind, th));
    }

    sev
}
