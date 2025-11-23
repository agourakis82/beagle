//! Binário para executar experimento HRV-aware vs HRV-blind
//!
//! Uso:
//!   run_experiment_hrv_aware_vs_blind [--experiment-id ID] [--n-total N] [--question-template TEMPLATE] [--beagle-core-url URL]
//!
//! Divide N_TOTAL runs em duas condições (N/2 cada):
//! - Condição "hrv_aware": Observer context ativo
//! - Condição "hrv_blind": Observer context neutro/desabilitado
//!
//! Nota: Requer que pipeline aceite flag hrv_aware (ver EXP4).

use anyhow::Result;
use beagle_config::{beagle_data_dir, load as load_config};
use beagle_experiments::{append_experiment_tag, ExperimentRunTag};
use chrono::Utc;
use clap::Parser;
use serde_json::json;
use std::time::Duration;
use tracing::{info, warn};

#[derive(Parser)]
#[command(name = "run_experiment_hrv_aware_vs_blind", version)]
struct Cli {
    /// ID do experimento (default: "hrv_aware_vs_blind_v1")
    #[arg(long, default_value = "hrv_aware_vs_blind_v1")]
    experiment_id: String,
    
    /// Número total de runs (default: 20)
    #[arg(long, default_value_t = 20)]
    n_total: usize,
    
    /// Template da pergunta (usa {i} como placeholder para índice)
    #[arg(long, default_value = "Paper idea {i}: Explorar efeitos do estado fisiológico em síntese científica")]
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
    info!("   Condições: hrv_aware (N/2) vs hrv_blind (N/2)");
    info!("   Core URL: {}", args.beagle_core_url);
    
    let data_dir = beagle_data_dir();
    let cfg = load_config();
    
    // Divide runs entre as duas condições
    let n_per_condition = args.n_total / 2;
    let client = reqwest::Client::new();
    
    let mut run_ids = Vec::new();
    
    // Executa runs com HRV-aware (condição "hrv_aware")
    info!("📊 Fase 1: Executando {} runs com HRV-aware ENABLED", n_per_condition);
    for i in 0..n_per_condition {
        let question = args.question_template.replace("{i}", &(i + 1).to_string());
        info!("Run {}/{} (hrv_aware): {}", i + 1, n_per_condition, question);
        
        let run_id = execute_pipeline_run(
            &client,
            &args.beagle_core_url,
            &question,
            true, // hrv_aware = true
            true, // with_triad = true (pode variar)
        ).await?;
        
        run_ids.push((run_id.clone(), "hrv_aware".to_string()));
        
        // Aguarda intervalo entre runs
        if i < n_per_condition - 1 {
            tokio::time::sleep(Duration::from_secs(args.interval_secs)).await;
        }
    }
    
    // Executa runs com HRV-blind (condição "hrv_blind")
    info!("📊 Fase 2: Executando {} runs com HRV-aware DISABLED", n_per_condition);
    for i in 0..n_per_condition {
        let question = args.question_template.replace("{i}", &(i + 1 + n_per_condition).to_string());
        info!("Run {}/{} (hrv_blind): {}", i + 1, n_per_condition, question);
        
        let run_id = execute_pipeline_run(
            &client,
            &args.beagle_core_url,
            &question,
            false, // hrv_aware = false
            true,  // with_triad = true (pode variar)
        ).await?;
        
        run_ids.push((run_id.clone(), "hrv_blind".to_string()));
        
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
            triad_enabled: true, // Assume que Triad está habilitada (pode ser inferido do run_report)
            hrv_aware: condition == "hrv_aware",
            serendipity_enabled: cfg.serendipity_enabled(),
            space_aware: false, // Assume false por padrão
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
    hrv_aware: bool,
    with_triad: bool,
) -> Result<String> {
    // Inicia pipeline (nota: hrv_aware será implementado em EXP4)
    let mut request_body = json!({
        "question": question,
        "with_triad": with_triad,
    });
    
    // Adiciona hrv_aware se endpoint suportar (ver EXP4.2)
    if let Ok(_) = serde_json::to_value(hrv_aware) {
        request_body["hrv_aware"] = json!(hrv_aware);
    }
    
    let start_response = client
        .post(&format!("{}/api/pipeline/start", base_url))
        .json(&request_body)
        .send()
        .await?;
    
    if !start_response.status().is_success() {
        anyhow::bail!("Falha ao iniciar pipeline: {}", start_response.status());
    }
    
    let start_json: serde_json::Value = start_response.json().await?;
    let run_id = start_json.get("run_id")
        .and_then(|v| v.as_str())
        .ok_or_else(|| anyhow::anyhow!("Resposta não contém run_id"))?;
    
    // Aguarda conclusão (mesma lógica do run_experiment_triad_vs_single)
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
        }
    }
}

