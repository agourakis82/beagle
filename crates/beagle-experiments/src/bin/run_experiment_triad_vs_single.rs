//! Binário para executar experimento Triad vs Single LLM
//!
//! Uso:
//!   run_experiment_triad_vs_single [--experiment-id ID] [--n-total N] [--question-template TEMPLATE] [--beagle-core-url URL]
//!
//! Divide N_TOTAL runs em duas condições (N/2 cada):
//! - Condição "triad": with_triad=true
//! - Condição "single": with_triad=false
//!
//! Cada run é registrado em experiments/events.jsonl com snapshot de config.

use anyhow::Result;
use beagle_config::{beagle_data_dir, load as load_config};
use beagle_experiments::{append_experiment_tag, ExperimentRunTag};
use chrono::Utc;
use clap::Parser;
use serde_json::json;
use std::path::PathBuf;
use std::time::Duration;
use tracing::{info, warn};

#[derive(Parser)]
#[command(name = "run_experiment_triad_vs_single", version)]
struct Cli {
    /// ID do experimento (default: "triad_vs_single_v1")
    #[arg(long, default_value = "triad_vs_single_v1")]
    experiment_id: String,
    
    /// Número total de runs (default: 20)
    #[arg(long, default_value_t = 20)]
    n_total: usize,
    
    /// Template da pergunta (usa {i} como placeholder para índice)
    #[arg(long, default_value = "Paper idea {i}: Explorar aplicações de scaffolds biológicos em medicina regenerativa")]
    question_template: String,
    
    /// URL do BEAGLE core server (default: http://localhost:8080)
    #[arg(long, default_value = "http://localhost:8080")]
    beagle_core_url: String,
    
    /// Intervalo entre runs em segundos (default: 5)
    #[arg(long, default_value_t = 5)]
    interval_secs: u64,
}

#[tokio::main]
async fn main() -> Result<()> {
    tracing_subscriber::fmt()
        .with_env_filter(tracing_subscriber::EnvFilter::from_default_env())
        .init();
    
    let args = Cli::parse();
    
    info!("🚀 Iniciando experimento: {}", args.experiment_id);
    info!("   Total de runs: {}", args.n_total);
    info!("   Condições: triad (N/2) vs single (N/2)");
    info!("   Core URL: {}", args.beagle_core_url);
    
    let data_dir = beagle_data_dir();
    let cfg = load_config();
    
    // Divide runs entre as duas condições
    let n_per_condition = args.n_total / 2;
    let client = reqwest::Client::new();
    
    let mut run_ids = Vec::new();
    
    // Executa runs com Triad (condição "triad")
    info!("📊 Fase 1: Executando {} runs com Triad ENABLED", n_per_condition);
    for i in 0..n_per_condition {
        let question = args.question_template.replace("{i}", &(i + 1).to_string());
        info!("Run {}/{} (triad): {}", i + 1, n_per_condition, question);
        
        let run_id = execute_pipeline_run(
            &client,
            &args.beagle_core_url,
            &question,
            true, // with_triad = true
        ).await?;
        
        run_ids.push((run_id.clone(), "triad".to_string()));
        
        // Aguarda intervalo entre runs
        if i < n_per_condition - 1 {
            tokio::time::sleep(Duration::from_secs(args.interval_secs)).await;
        }
    }
    
    // Executa runs sem Triad (condição "single")
    info!("📊 Fase 2: Executando {} runs com Triad DISABLED", n_per_condition);
    for i in 0..n_per_condition {
        let question = args.question_template.replace("{i}", &(i + 1 + n_per_condition).to_string());
        info!("Run {}/{} (single): {}", i + 1, n_per_condition, question);
        
        let run_id = execute_pipeline_run(
            &client,
            &args.beagle_core_url,
            &question,
            false, // with_triad = false
        ).await?;
        
        run_ids.push((run_id.clone(), "single".to_string()));
        
        // Aguarda intervalo entre runs
        if i < n_per_condition - 1 {
            tokio::time::sleep(Duration::from_secs(args.interval_secs)).await;
        }
    }
    
    // Marca todos os runs com tags experimentais
    info!("📋 Marcando runs com tags experimentais...");
    for (run_id, condition) in &run_ids {
        let tag = ExperimentRunTag {
            experiment_id: args.experiment_id.clone(),
            run_id: run_id.clone(),
            condition: condition.clone(),
            timestamp: Utc::now(),
            notes: None,
            triad_enabled: condition == "triad",
            hrv_aware: true, // Assume que Observer está ativo (pode ser inferido do run_report)
            serendipity_enabled: cfg.serendipity_enabled(),
            space_aware: false, // Assume false por padrão (pode ser inferido do run_report)
        };
        
        append_experiment_tag(&data_dir, &tag)?;
        info!("✅ Tag criada: run_id={}, condition={}", run_id, condition);
    }
    
    info!("🎉 Experimento concluído!");
    info!("   Total de runs: {}", run_ids.len());
    info!("   Tags salvas em: {}/experiments/events.jsonl", data_dir.display());
    info!("   Execute 'analyze_experiments {}' para analisar resultados", args.experiment_id);
    
    Ok(())
}

/// Executa um run do pipeline via HTTP e aguarda conclusão
async fn execute_pipeline_run(
    client: &reqwest::Client,
    base_url: &str,
    question: &str,
    with_triad: bool,
) -> Result<String> {
    // Inicia pipeline
    let start_response = client
        .post(&format!("{}/api/pipeline/start", base_url))
        .json(&json!({
            "question": question,
            "with_triad": with_triad,
        }))
        .send()
        .await?;
    
    if !start_response.status().is_success() {
        anyhow::bail!("Falha ao iniciar pipeline: {}", start_response.status());
    }
    
    let start_json: serde_json::Value = start_response.json().await?;
    let run_id = start_json.get("run_id")
        .and_then(|v| v.as_str())
        .ok_or_else(|| anyhow::anyhow!("Resposta não contém run_id"))?;
    
    // Aguarda conclusão
    let max_wait_secs = 600; // 10 minutos máximo
    let poll_interval = Duration::from_secs(2);
    let mut elapsed = Duration::ZERO;
    
    loop {
        tokio::time::sleep(poll_interval).await;
        elapsed += poll_interval;
        
        if elapsed > Duration::from_secs(max_wait_secs) {
            warn!("Timeout aguardando pipeline run_id={}", run_id);
            return Ok(run_id.to_string());
        }
        
        let status_response = client
            .get(&format!("{}/api/pipeline/status/{}", base_url, run_id))
            .send()
            .await?;
        
        if status_response.status().is_success() {
            let status_json: serde_json::Value = status_response.json().await?;
            let status = status_json.get("status")
                .and_then(|v| v.as_str())
                .unwrap_or("unknown");
            
            if status == "done" || status == "failed" {
                return Ok(run_id.to_string());
            }
            
            // Continua aguardando se ainda está "running" ou "triad_running"
        }
    }
}

