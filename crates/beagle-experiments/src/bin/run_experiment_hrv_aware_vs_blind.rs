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
use beagle_config::beagle_data_dir;
use beagle_experiments::{
    append_experiment_tag, expedition_002_condition_sequence,
    expedition_002_hrv_aware_condition_flags, expedition_002_hrv_blind_condition_flags,
    ExperimentRunTag, Expedition002Config,
};
use chrono::Utc;
use clap::Parser;
use serde_json::json;
use std::time::Duration;
use tracing::{info, warn};

#[derive(Parser)]
#[command(name = "run_experiment_hrv_aware_vs_blind", version)]
struct Cli {
    /// ID do experimento (default: canonical Expedition 002 id)
    #[arg(long)]
    experiment_id: Option<String>,

    /// Número total de runs neste lote
    #[arg(long)]
    n_total: Option<usize>,

    /// Rótulo opcional do lote
    #[arg(long)]
    batch_label: Option<String>,

    /// Template da pergunta (usa {i} como placeholder para índice)
    #[arg(long)]
    question_template: Option<String>,

    /// URL do BEAGLE core server (default: http://localhost:8080)
    #[arg(long, default_value = "http://localhost:8080")]
    beagle_core_url: String,

    /// Token Bearer para a surface protegida do core server
    #[arg(long)]
    api_token: Option<String>,

    /// Consumer header usado nas chamadas ao core server
    #[arg(long, default_value = "beagle-operator")]
    consumer: String,

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
    let config = Expedition002Config::with_custom(
        args.experiment_id.clone(),
        args.n_total,
        args.question_template.clone(),
    );
    let data_dir = beagle_data_dir();
    let client = reqwest::Client::new();
    let mut run_ids = Vec::new();
    let conditions = expedition_002_condition_sequence(config.n_total);
    let (n_hrv_aware, n_hrv_blind) = config.n_per_condition();
    let api_token = args
        .api_token
        .clone()
        .or_else(|| std::env::var("BEAGLE_OPERATOR_API_TOKEN").ok())
        .or_else(|| std::env::var("BEAGLE_API_TOKEN").ok());

    println!("\n{}", "=".repeat(70));
    println!("Beagle Expedition 002 – HRV-aware vs blind");
    println!("{}", "=".repeat(70));
    println!("Experiment ID: {}", config.experiment_id);
    println!("N total: {}", config.n_total);
    println!("Conditions: hrv_aware={} | hrv_blind={}", n_hrv_aware, n_hrv_blind);
    println!("Core URL: {}", args.beagle_core_url);
    if let Some(ref label) = args.batch_label {
        println!("Batch label: {}", label);
    }
    println!();

    info!("🚀 Iniciando experimento: {}", config.experiment_id);
    info!("   Total de runs neste lote: {}", config.n_total);
    info!(
        "   Condições balanceadas: hrv_aware={} | hrv_blind={}",
        n_hrv_aware, n_hrv_blind
    );
    info!("   Core URL: {}", args.beagle_core_url);
    if let Some(ref label) = args.batch_label {
        info!("   Batch label: {}", label);
    }

    for (i, condition) in conditions.iter().enumerate() {
        let question = if config.question_template.contains("{i}") {
            config
                .question_template
                .replace("{i}", &(i + 1).to_string())
        } else {
            format!("{} (run {}/{})", config.question_template, i + 1, config.n_total)
        };

        let (with_triad, hrv_aware, _, _) = match condition.as_str() {
            "hrv_aware" => expedition_002_hrv_aware_condition_flags(),
            "hrv_blind" => expedition_002_hrv_blind_condition_flags(),
            other => {
                warn!("Condição desconhecida: {}, usando hrv_blind", other);
                expedition_002_hrv_blind_condition_flags()
            }
        };

        info!("Run {}/{} ({}): {}", i + 1, config.n_total, condition, question);

        let run_id = execute_pipeline_run(
            &client,
            &args.beagle_core_url,
            &question,
            &config.experiment_id,
            api_token.as_deref(),
            &args.consumer,
            hrv_aware,
            with_triad,
        )
        .await?;
        run_ids.push((run_id.clone(), condition.clone()));

        if i < config.n_total - 1 {
            tokio::time::sleep(Duration::from_secs(args.interval_secs)).await;
        }
    }

    // Marca todos os runs com tags experimentais
    info!("📋 Marcando runs com tags experimentais...");
    for (run_id, condition) in &run_ids {
        let (triad_enabled, hrv_aware, serendipity_enabled, space_aware) =
            match condition.as_str() {
                "hrv_aware" => expedition_002_hrv_aware_condition_flags(),
                "hrv_blind" => expedition_002_hrv_blind_condition_flags(),
                _ => expedition_002_hrv_blind_condition_flags(),
            };
        let tag = ExperimentRunTag {
            experiment_id: config.experiment_id.clone(),
            run_id: run_id.clone(),
            condition: condition.clone(),
            timestamp: Utc::now(),
            notes: args
                .batch_label
                .as_ref()
                .map(|label| format!("batch_label={}", label)),
            triad_enabled,
            hrv_aware,
            serendipity_enabled,
            space_aware,
        };

        append_experiment_tag(&data_dir, &tag)?;
        info!("✅ Tag criada: run_id={}, condition={}", run_id, condition);
    }

    println!("\n{}", "=".repeat(70));
    println!("Expedition 002 complete");
    println!("{}", "=".repeat(70));
    println!("HRV-aware runs: {}", n_hrv_aware);
    println!("HRV-blind runs: {}", n_hrv_blind);
    println!("Total runs: {}", run_ids.len());
    println!(
        "\nExperiment tags written to: {}/experiments/events.jsonl",
        data_dir.display()
    );
    println!("\nNext steps:");
    println!(
        "1. Analyze results: analyze_experiments {} --output-format json",
        config.experiment_id
    );
    println!();

    info!("🎉 Experimento concluído!");
    info!("   Total de runs: {}", run_ids.len());
    info!(
        "   Tags salvas em: {}/experiments/events.jsonl",
        data_dir.display()
    );
    info!(
        "   Execute 'analyze_experiments {}' para analisar resultados",
        config.experiment_id
    );

    Ok(())
}

/// Executa um run do pipeline via HTTP e aguarda conclusão
async fn execute_pipeline_run(
    client: &reqwest::Client,
    base_url: &str,
    question: &str,
    experiment_id: &str,
    api_token: Option<&str>,
    consumer: &str,
    hrv_aware: bool,
    with_triad: bool,
) -> Result<String> {
    let mut request_body = json!({
        "question": question,
        "with_triad": with_triad,
        "experiment_id": experiment_id,
    });

    if let Ok(_) = serde_json::to_value(hrv_aware) {
        request_body["hrv_aware"] = json!(hrv_aware);
    }

    let mut start_request = client
        .post(&format!("{}/api/pipeline/start", base_url))
        .header("X-Beagle-Consumer", consumer)
        .json(&request_body);
    if let Some(token) = api_token {
        start_request = start_request.bearer_auth(token);
    }
    let start_response = start_request.send().await?;

    if !start_response.status().is_success() {
        anyhow::bail!("Falha ao iniciar pipeline: {}", start_response.status());
    }

    let start_json: serde_json::Value = start_response.json().await?;
    let run_id = start_json
        .get("run_id")
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

        let mut status_request = client
            .get(&format!("{}/api/pipeline/status/{}", base_url, run_id))
            .header("X-Beagle-Consumer", consumer);
        if let Some(token) = api_token {
            status_request = status_request.bearer_auth(token);
        }
        let status_response = status_request.send().await?;

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
