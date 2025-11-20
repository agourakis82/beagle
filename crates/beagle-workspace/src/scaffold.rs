//! Darwin Scaffold Studio - Interface Rust para Julia
//! Processamento de imagens MicroCT

use anyhow::{Context, Result};
use serde_json::Value;
use std::process::Command;
use tracing::info;

pub struct ScaffoldStudio;

impl ScaffoldStudio {
    pub fn new() -> Self {
        info!("🔬 Scaffold Studio inicializado (Julia backend)");
        Self
    }

    pub async fn process_microct(&self, image_path: &str) -> Result<Value> {
        info!("📸 Processando MicroCT: {}", image_path);

        let script = format!(
            r#"
            using Pkg
            Pkg.activate("beagle-julia")
            include("beagle-julia/scaffold_studio.jl")
            using .ScaffoldStudio
            using JSON3
            
            processor = ScaffoldStudio.ScaffoldProcessor()
            result = ScaffoldStudio.process_microct(processor, "{}")
            println(JSON3.write(result))
            "#,
            image_path
        );

        let output = Command::new("julia")
            .arg("--project=beagle-julia")
            .arg("-e")
            .arg(&script)
            .current_dir("/mnt/e/workspace/beagle-remote")
            .output()
            .context("Falha ao executar Julia")?;

        let stdout = String::from_utf8(output.stdout)?;
        let result: Value = serde_json::from_str(&stdout.trim())?;

        Ok(result)
    }
}

impl Default for ScaffoldStudio {
    fn default() -> Self {
        Self::new()
    }
}
