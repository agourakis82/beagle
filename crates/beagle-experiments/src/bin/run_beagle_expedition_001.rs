//! Beagle Expedition 001 – Triad vs Single LLM
//!
//! Hypothesis H1: Triad ON produces drafts with higher human ratings and
//! accepted ratio than Triad OFF (single LLM) under typical working conditions.
//!
//! Uso:
//!   run_beagle_expedition_001 [--experiment-id ID] [--n-total N] [--question-template TEMPLATE] [--beagle-core-url URL]

use anyhow::Result;
use beagle_config::{beagle_data_dir, load as load_config};
use beagle_experiments::{
    append_experiment_tag,
    exp001::{
        assert_expedition_001_llm_config, single_condition_flags, triad_condition_flags,
        Expedition001Config, EXPEDITION_001_DEFAULT_N, EXPEDITION_001_ID,
    },
    ExperimentRunTag,
};
use chrono::Utc;
use clap::Parser;
use serde_json::json;
use std::time::Duration;
use tracing::{info, warn};

#[derive(Parser)]
#[command(name = "run_beagle_expedition_001", version)]
struct Cli {
    /// ID do experimento (default: beagle_exp_001_triad_vs_single)
    #[arg(long)]
    experiment_id: Option<String>,

    /// Número total de runs a adicionar NESTE LOTE (não o total acumulado)
    #[arg(long)]
    n_total: Option<usize>,

    /// Semente RNG opcional (para reprodução do order de condições / variação)
    #[arg(long)]
    seed: Option<u64>,

    /// Opcional: descrição textual deste lote (e.g. "dia1_manha", "dia1_tarde")
    #[arg(long)]
    batch_label: Option<String>,

    /// Template da pergunta (default: Expedition 001 template)
    #[arg(long)]
    question_template: Option<String>,

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

    // Resolve config (usa defaults de Expedition 001 se não fornecidos)
    let config =
        Expedition001Config::with_custom(args.experiment_id, args.n_total, args.question_template);

    // Print header
    println!("\n{}", "=".repeat(70));
    println!("Beagle Expedition 001 – Triad vs Single LLM");
    println!("{}", "=".repeat(70));
    println!("Experiment ID: {}", config.experiment_id);
    println!("N total: {}", config.n_total);
    println!("Question template: {}", config.question_template);
    println!("Core URL: {}", args.beagle_core_url);
    println!();

    let data_dir = beagle_data_dir();
    let cfg = load_config();

    // Valida configuração LLM/Router para Expedition 001
    info!("🔍 Validando configuração LLM/Router para Expedition 001...");
    if let Err(e) = assert_expedition_001_llm_config(&cfg) {
        anyhow::bail!("❌ Configuração inválida para Expedition 001: {}", e);
    }

    // Loga config relevante para auditoria
    info!("📋 Configuração congelada para Expedition 001:");
    info!("   profile: {}", cfg.profile);
    info!("   safe_mode: {}", cfg.safe_mode);
    info!("   grok_model: {}", cfg.llm.grok_model);
    info!("   serendipity_enabled: {}", cfg.serendipity_enabled());
    info!("   serendipity_in_triad: {}", cfg.serendipity_in_triad());

    // Loga batch info
    info!("🚀 Iniciando Expedition 001: {}", config.experiment_id);
    info!("   Total de runs NESTE LOTE: {}", config.n_total);
    if let Some(ref label) = args.batch_label {
        info!("   Batch label: {}", label);
    }
    if let Some(seed) = args.seed {
        info!("   Seed: {}", seed);
    }
    info!("   Core URL: {}", args.beagle_core_url);

    // Divide runs entre as duas condições
    let (n_triad, n_single) = config.n_per_condition();

    // Se n_total for ímpar, loga aviso (diferença de 1 é aceitável)
    if n_triad != n_single {
        warn!(
            "⚠️  Número ímpar de runs: diferença de {} entre condições (aceitável)",
            (n_triad as i32 - n_single as i32).abs()
        );
    }

    info!(
        "   Condições: triad (N={}) vs single (N={})",
        n_triad, n_single
    );

    let client = reqwest::Client::new();
    let mut run_ids = Vec::new();

    // Gera sequência balanceada de condições (alternando ou com seed)
    let conditions = generate_condition_sequence(config.n_total, args.seed);

    // Obter flags para cada condição
    let (triad_enabled, hrv_aware_triad, serendipity_enabled, space_aware) =
        triad_condition_flags();
    let (single_triad_enabled, hrv_aware_single, _, _) = single_condition_flags();

    // Executa runs seguindo a sequência de condições
    for (i, condition) in conditions.iter().enumerate() {
        let question = if config.question_template.contains("{i}") {
            config
                .question_template
                .replace("{i}", &(i + 1).to_string())
        } else {
            format!(
                "{} (run {}/{}, batch={})",
                config.question_template,
                i + 1,
                config.n_total,
                args.batch_label.as_deref().unwrap_or("default")
            )
        };

        let (with_triad, hrv_aware) = match condition.as_str() {
            "triad" => (triad_enabled, hrv_aware_triad),
            "single" => (single_triad_enabled, hrv_aware_single),
            _ => {
                warn!(
                    "Condição desconhecida: {}, usando triad como fallback",
                    condition
                );
                (triad_enabled, hrv_aware_triad)
            }
        };

        info!(
            "Run {}/{} ({}): {}",
            i + 1,
            config.n_total,
            condition,
            question
        );

        let run_id = execute_pipeline_run(
            &client,
            &args.beagle_core_url,
            &question,
            with_triad,
            hrv_aware,
        )
        .await?;

        run_ids.push((run_id.clone(), condition.clone()));

        // Aguarda intervalo entre runs
        if i < config.n_total - 1 {
            tokio::time::sleep(Duration::from_secs(args.interval_secs)).await;
        }
    }

    // Marca todos os runs com tags experimentais
    info!("📋 Marcando runs com tags experimentais...");
    for (run_id, condition) in &run_ids {
        let (triad_enabled, hrv_aware, serendipity_enabled, space_aware) = match condition.as_str()
        {
            "triad" => triad_condition_flags(),
            "single" => single_condition_flags(),
            _ => {
                warn!("Condição desconhecida: {}, usando defaults", condition);
                (false, true, false, false)
            }
        };

        // Adiciona batch_label às notes se fornecido
        let notes = if let Some(ref label) = args.batch_label {
            Some(format!("batch_label={}", label))
        } else {
            None
        };

        let tag = ExperimentRunTag {
            experiment_id: config.experiment_id.clone(),
            run_id: run_id.clone(),
            condition: condition.clone(),
            timestamp: Utc::now(),
            notes,
            triad_enabled,
            hrv_aware,
            serendipity_enabled,
            space_aware,
        };

        append_experiment_tag(&data_dir, &tag)?;
        info!("✅ Tag criada: run_id={}, condition={}", run_id, condition);
    }

    // Print summary
    println!("\n{}", "=".repeat(70));
    println!("Expedition 001 complete");
    println!("{}", "=".repeat(70));
    println!("Triad runs: {}", n_triad);
    println!("Single runs: {}", n_single);
    println!("Total runs: {}", run_ids.len());
    println!(
        "\nExperiment tags written to: {}/experiments/events.jsonl",
        data_dir.display()
    );
    println!("\nNext steps:");
    println!("1. Review drafts in {}/papers/drafts/", data_dir.display());
    println!("2. Tag each run with: tag_run <run_id> <accepted 0/1> [rating 0-10] [notes...]");
    println!(
        "3. Analyze results: analyze_experiments {} --output-format csv",
        config.experiment_id
    );
    println!();

    info!("🎉 Expedition 001 concluída!");
    info!(
        "   Execute 'analyze_experiments {}' para analisar resultados",
        config.experiment_id
    );

    Ok(())
}

/// Gera sequência balanceada de condições (triad/single) com seed opcional
fn generate_condition_sequence(n_total: usize, seed: Option<u64>) -> Vec<String> {
    let n_triad = n_total / 2;
    let n_single = n_total - n_triad;

    let mut conditions = Vec::with_capacity(n_total);

    // Preenche com triad e single balanceados
    for _ in 0..n_triad {
        conditions.push("triad".to_string());
    }
    for _ in 0..n_single {
        conditions.push("single".to_string());
    }

    // Se seed fornecida, embaralha com RNG determinístico
    if let Some(seed_val) = seed {
        use std::collections::hash_map::DefaultHasher;
        use std::hash::{Hash, Hasher};
        // Shuffle simples baseado em seed (Fisher-Yates aproximado)
        for i in (1..conditions.len()).rev() {
            let mut hasher = DefaultHasher::new();
            seed_val.hash(&mut hasher);
            (i + seed_val as usize).hash(&mut hasher);
            let j = (hasher.finish() as usize) % (i + 1);
            conditions.swap(i, j);
        }
    }

    conditions
}

/// Executa um run do pipeline via HTTP e aguarda conclusão
async fn execute_pipeline_run(
    client: &reqwest::Client,
    base_url: &str,
    question: &str,
    with_triad: bool,
    hrv_aware: bool,
) -> Result<String> {
    // Inicia pipeline
    let mut request_body = json!({
        "question": question,
        "with_triad": with_triad,
    });

    // Adiciona hrv_aware se endpoint suportar
    request_body["hrv_aware"] = json!(hrv_aware);

    let start_response = client
        .post(&format!("{}/api/pipeline/start", base_url))
        .json(&request_body)
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
    // Aumentado para 20 minutos: runs com Triad demoram ~9-10 min
    let max_wait_secs = 1200; // 20 minutos máximo
    let poll_interval = Duration::from_secs(5); // Aumentado para reduzir overhead
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

            // Continua aguardando se ainda está "running" ou "triad_running"
        }
    }
}
