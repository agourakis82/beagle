//! Binário para executar experimento Serendipity on/off
//!
//! Uso:
//!   run_experiment_serendipity [--experiment-id ID] [--n-total N] [--question-template TEMPLATE] [--beagle-core-url URL]
//!
//! Divide N_TOTAL runs em duas condições (N/2 cada):
//! - Condição "serendipity_on": serendipity_enabled=true
//! - Condição "serendipity_off": serendipity_enabled=false
//!
//! Nota: Requer que pipeline respeite BEAGLE_SERENDIPITY env var ou config.

use anyhow::Result;
use beagle_config::{beagle_data_dir, load as load_config};
use beagle_experiments::{append_experiment_tag, ExperimentRunTag};
use chrono::Utc;
use clap::Parser;
use serde_json::json;
use std::env;
use std::time::Duration;
use tracing::{info, warn};

#[derive(Parser)]
#[command(name = "run_experiment_serendipity", version)]
struct Cli {
    /// ID do experimento (default: "serendipity_on_off_v1")
    #[arg(long, default_value = "serendipity_on_off_v1")]
    experiment_id: String,

    /// Número total de runs (default: 20)
    #[arg(long, default_value_t = 20)]
    n_total: usize,

    /// Template da pergunta (usa {i} como placeholder para índice)
    #[arg(
        long,
        default_value = "Paper idea {i}: Explorar conexões interdisciplinares em síntese científica"
    )]
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
    info!("   Condições: serendipity_on (N/2) vs serendipity_off (N/2)");
    info!("   Core URL: {}", args.beagle_core_url);

    let data_dir = beagle_data_dir();
    let cfg = load_config();

    // Salva valor original de BEAGLE_SERENDIPITY
    let old_serendipity = env::var("BEAGLE_SERENDIPITY").ok();

    // Divide runs entre as duas condições
    let n_per_condition = args.n_total / 2;
    let client = reqwest::Client::new();

    let mut run_ids = Vec::new();

    // Executa runs com Serendipity ON (condição "serendipity_on")
    info!(
        "📊 Fase 1: Executando {} runs com Serendipity ENABLED",
        n_per_condition
    );
    env::set_var("BEAGLE_SERENDIPITY", "true");

    for i in 0..n_per_condition {
        let question = args.question_template.replace("{i}", &(i + 1).to_string());
        info!(
            "Run {}/{} (serendipity_on): {}",
            i + 1,
            n_per_condition,
            question
        );

        let run_id = execute_pipeline_run(
            &client,
            &args.beagle_core_url,
            &question,
            true, // serendipity_enabled = true
        )
        .await?;

        run_ids.push((run_id.clone(), "serendipity_on".to_string()));

        // Aguarda intervalo entre runs
        if i < n_per_condition - 1 {
            tokio::time::sleep(Duration::from_secs(args.interval_secs)).await;
        }
    }

    // Executa runs com Serendipity OFF (condição "serendipity_off")
    info!(
        "📊 Fase 2: Executando {} runs com Serendipity DISABLED",
        n_per_condition
    );
    env::set_var("BEAGLE_SERENDIPITY", "false");

    for i in 0..n_per_condition {
        let question = args
            .question_template
            .replace("{i}", &(i + 1 + n_per_condition).to_string());
        info!(
            "Run {}/{} (serendipity_off): {}",
            i + 1,
            n_per_condition,
            question
        );

        let run_id = execute_pipeline_run(
            &client,
            &args.beagle_core_url,
            &question,
            false, // serendipity_enabled = false
        )
        .await?;

        run_ids.push((run_id.clone(), "serendipity_off".to_string()));

        // Aguarda intervalo entre runs
        if i < n_per_condition - 1 {
            tokio::time::sleep(Duration::from_secs(args.interval_secs)).await;
        }
    }

    // Restaura valor original de BEAGLE_SERENDIPITY
    if let Some(old) = old_serendipity {
        env::set_var("BEAGLE_SERENDIPITY", old);
    } else {
        env::remove_var("BEAGLE_SERENDIPITY");
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
            triad_enabled: true, // Assume que Triad está habilitada (pode ser inferido)
            hrv_aware: true,     // Assume que Observer está ativo
            serendipity_enabled: condition == "serendipity_on",
            space_aware: false, // Assume false por padrão
        };

        append_experiment_tag(&data_dir, &tag)?;
        info!("✅ Tag criada: run_id={}, condition={}", run_id, condition);
    }

    info!("🎉 Experimento concluído!");
    info!("   Total de runs: {}", run_ids.len());
    info!(
        "   Tags salvas em: {}/experiments/events.jsonl",
        data_dir.display()
    );
    info!(
        "   Execute 'analyze_experiments {}' para analisar resultados",
        args.experiment_id
    );

    Ok(())
}

/// Executa um run do pipeline via HTTP e aguarda conclusão
async fn execute_pipeline_run(
    client: &reqwest::Client,
    base_url: &str,
    question: &str,
    serendipity_enabled: bool,
) -> Result<String> {
    // Nota: Serendipity é controlado via env var BEAGLE_SERENDIPITY
    // O pipeline deve recarregar config ou ler env var a cada run

    let start_response = client
        .post(&format!("{}/api/pipeline/start", base_url))
        .json(&json!({
            "question": question,
            "with_triad": true, // Pode variar conforme necessidade
        }))
        .send()
        .await?;

    if !start_response.status().is_success() {
        anyhow::bail!("Falha ao iniciar pipeline: {}", start_response.status());
    }

    let start_json: serde_json::Value = start_response.json().await?;
    let run_id = start_json
        .get("run_id")
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
            let status = status_json
                .get("status")
                .and_then(|v| v.as_str())
                .unwrap_or("unknown");

            if status == "done" || status == "failed" {
                return Ok(run_id.to_string());
            }
        }
    }
}
