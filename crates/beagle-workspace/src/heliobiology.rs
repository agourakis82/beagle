//! Heliobiology - Interface Rust para Julia
//! Kairos Forecaster, WESAD, HRV Mood Pipeline

use anyhow::{Context, Result};
// use serde_json::Value; // TODO: usar quando implementar
use std::process::Command;
use tracing::info;

pub struct HeliobiologyPlatform;

impl HeliobiologyPlatform {
    pub fn new() -> Self {
        info!("☀️  Heliobiology Platform inicializado (Julia backend)");
        Self
    }

    pub async fn forecast_kairos(&self, history: &[f32]) -> Result<Vec<f32>> {
        info!("🔮 Forecasting com Kairos");

        let history_json = serde_json::to_string(history)?;

        let script = format!(
            r#"
            using Pkg
            Pkg.activate("beagle-julia")
            include("beagle-julia/kairos_forecaster.jl")
            using .KairosForecaster
            using JSON3
            
            history = {}
            forecaster = KairosForecaster.KairosForecaster()
            pred = KairosForecaster.forecast(forecaster, history)
            println(JSON3.write(pred))
            "#,
            history_json
        );

        let output = Command::new("julia")
            .arg("--project=beagle-julia")
            .arg("-e")
            .arg(&script)
            .current_dir("/mnt/e/workspace/beagle-remote")
            .output()
            .context("Falha ao executar Julia")?;

        let stdout = String::from_utf8(output.stdout)?;
        let pred: Vec<f32> = serde_json::from_str(&stdout.trim())?;

        Ok(pred)
    }

    pub async fn predict_mood_hrv(&self, rr_intervals: &[f32]) -> Result<Vec<f32>> {
        info!("😊 Predizendo humor via HRV");

        let rr_json = serde_json::to_string(rr_intervals)?;

        let script = format!(
            r#"
            using Pkg
            Pkg.activate("beagle-julia")
            include("beagle-julia/hrv_mood_pipeline.jl")
            using .HRVMoodPipeline
            using JSON3
            
            rr_intervals = {}
            pipeline = HRVMoodPipeline.HRVMoodPipeline()
            pred = HRVMoodPipeline.predict_mood(pipeline, rr_intervals)
            println(JSON3.write(pred))
            "#,
            rr_json
        );

        let output = Command::new("julia")
            .arg("--project=beagle-julia")
            .arg("-e")
            .arg(&script)
            .current_dir("/mnt/e/workspace/beagle-remote")
            .output()
            .context("Falha ao executar Julia")?;

        let stdout = String::from_utf8(output.stdout)?;
        let pred: Vec<f32> = serde_json::from_str(&stdout.trim())?;

        Ok(pred)
    }
}

impl Default for HeliobiologyPlatform {
    fn default() -> Self {
        Self::new()
    }
}
