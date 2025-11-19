//! KEC 3.0 GPU-accelerated - Interface Rust para Julia

use anyhow::{Context, Result};
use serde_json::Value;
use std::process::Command;
use tracing::info;

pub struct Kec3Engine;

impl Kec3Engine {
    pub fn new() -> Self {
        info!("🔧 KEC 3.0 Engine inicializado (Julia backend)");
        Self
    }

    pub async fn compute_all_metrics(&self, graph_data: &[f64]) -> Result<Value> {
        info!("📊 Computando métricas KEC 3.0 (Julia)");
        
        let json_data = serde_json::to_string(graph_data)?;
        
        let script = format!(
            r#"
            using Pkg
            Pkg.activate("beagle-julia")
            include("beagle-julia/kec_3_gpu.jl")
            using .KEC3GPU
            using JSON3
            
            graph_data = {}
            engine = KEC3GPU.Kec3Engine()
            metrics = KEC3GPU.compute_all_metrics(engine, graph_data)
            println(JSON3.write(metrics))
            "#,
            json_data
        );
        
        let output = Command::new("julia")
            .arg("--project=beagle-julia")
            .arg("-e")
            .arg(&script)
            .current_dir("/mnt/e/workspace/beagle-remote")
            .output()
            .context("Falha ao executar Julia")?;

        let stdout = String::from_utf8(output.stdout)?;
        let metrics: Value = serde_json::from_str(&stdout.trim())?;
        
        Ok(metrics)
    }
}

impl Default for Kec3Engine {
    fn default() -> Self {
        Self::new()
    }
}
