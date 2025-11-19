//! PCS Meta Repo - Interface Rust para Julia
//! Symbolic Computational Psychiatry

use anyhow::{Context, Result};
use serde_json::Value;
use std::process::Command;
use tracing::info;

pub struct PCSSymbolicPsychiatry;

impl PCSSymbolicPsychiatry {
    pub fn new() -> Self {
        info!("🧠 PCS Symbolic Psychiatry inicializado (Julia backend)");
        Self
    }

    pub async fn reason_symbolically(&self, symptoms: &str) -> Result<Value> {
        info!("🔬 Raciocínio simbólico sobre sintomas");
        
        let script = format!(
            r#"
            using Pkg
            Pkg.activate("beagle-julia")
            include("beagle-julia/pcs_symbolic_psychiatry.jl")
            using .PCSSymbolicPsychiatry
            using JSON3
            
            model = PCSSymbolicPsychiatry.SymbolicPsychiatryModel()
            symptoms = {}
            result = PCSSymbolicPsychiatry.reason_symbolically(model, symptoms)
            println(JSON3.write(result))
            "#,
            symptoms
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

impl Default for PCSSymbolicPsychiatry {
    fn default() -> Self {
        Self::new()
    }
}

