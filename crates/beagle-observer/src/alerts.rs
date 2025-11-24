//! Observer 2.0 - Sistema de alerts

use crate::severity::Severity;
use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};

/// Evento de alerta gerado quando uma métrica excede thresholds
#[derive(Serialize, Deserialize, Debug, Clone)]
pub struct AlertEvent {
    pub timestamp: DateTime<Utc>,
    pub category: String, // "physio" | "env" | "space"
    pub metric: String,   // "spo2" | "hrv" | "kp" | "altitude" etc.
    pub severity: Severity,
    pub value: f32,
    pub threshold: f32,
    pub session_id: Option<String>,
    pub run_id: Option<String>,
    pub message: String,
}

impl AlertEvent {
    /// Cria um alerta fisiológico
    pub fn physio(
        metric: &str,
        severity: Severity,
        value: f32,
        threshold: f32,
        session_id: Option<String>,
        run_id: Option<String>,
    ) -> Self {
        let message = match severity {
            Severity::Severe => format!(
                "ALERTA CRÍTICO: {} = {:.2} (threshold: {:.2})",
                metric, value, threshold
            ),
            Severity::Moderate => format!(
                "ALERTA: {} = {:.2} (threshold: {:.2})",
                metric, value, threshold
            ),
            Severity::Mild => format!(
                "Aviso: {} = {:.2} (threshold: {:.2})",
                metric, value, threshold
            ),
            Severity::Normal => format!("{} = {:.2} (normal)", metric, value),
        };

        Self {
            timestamp: Utc::now(),
            category: "physio".to_string(),
            metric: metric.to_string(),
            severity,
            value,
            threshold,
            session_id,
            run_id,
            message,
        }
    }

    /// Cria um alerta ambiental
    pub fn env(
        metric: &str,
        severity: Severity,
        value: f32,
        threshold: f32,
        session_id: Option<String>,
        run_id: Option<String>,
    ) -> Self {
        let message = match severity {
            Severity::Severe => format!(
                "ALERTA AMBIENTAL CRÍTICO: {} = {:.2} (threshold: {:.2})",
                metric, value, threshold
            ),
            Severity::Moderate => format!(
                "ALERTA AMBIENTAL: {} = {:.2} (threshold: {:.2})",
                metric, value, threshold
            ),
            Severity::Mild => format!(
                "Aviso ambiental: {} = {:.2} (threshold: {:.2})",
                metric, value, threshold
            ),
            Severity::Normal => format!("{} = {:.2} (normal)", metric, value),
        };

        Self {
            timestamp: Utc::now(),
            category: "env".to_string(),
            metric: metric.to_string(),
            severity,
            value,
            threshold,
            session_id,
            run_id,
            message,
        }
    }

    /// Cria um alerta de clima espacial
    pub fn space_weather(
        metric: &str,
        severity: Severity,
        value: f32,
        threshold: f32,
        session_id: Option<String>,
        run_id: Option<String>,
    ) -> Self {
        let message = match severity {
            Severity::Severe => format!(
                "ALERTA CLIMA ESPACIAL CRÍTICO: {} = {:.2} (threshold: {:.2})",
                metric, value, threshold
            ),
            Severity::Moderate => format!(
                "ALERTA CLIMA ESPACIAL: {} = {:.2} (threshold: {:.2})",
                metric, value, threshold
            ),
            Severity::Mild => format!(
                "Aviso clima espacial: {} = {:.2} (threshold: {:.2})",
                metric, value, threshold
            ),
            Severity::Normal => format!("{} = {:.2} (normal)", metric, value),
        };

        Self {
            timestamp: Utc::now(),
            category: "space".to_string(),
            metric: metric.to_string(),
            severity,
            value,
            threshold,
            session_id,
            run_id,
            message,
        }
    }
}

/// Escreve um alerta em arquivo JSONL
pub fn log_alert(data_dir: &std::path::Path, alert: &AlertEvent) -> anyhow::Result<()> {
    use std::fs::OpenOptions;
    use std::io::Write;

    let alerts_dir = data_dir.join("alerts");
    std::fs::create_dir_all(&alerts_dir)?;

    let filename = match alert.category.as_str() {
        "physio" => "physio.jsonl",
        "env" => "env.jsonl",
        "space" => "space.jsonl",
        _ => "alerts.jsonl",
    };

    let file_path = alerts_dir.join(filename);

    let json_line = serde_json::to_string(alert)?;

    let mut file = OpenOptions::new()
        .create(true)
        .append(true)
        .open(&file_path)?;

    writeln!(file, "{}", json_line)?;

    Ok(())
}

/// Loga múltiplos alertas em batch
pub fn log_alerts(data_dir: &std::path::Path, alerts: &[AlertEvent]) -> anyhow::Result<()> {
    for alert in alerts {
        log_alert(data_dir, alert)?;
    }
    Ok(())
}
