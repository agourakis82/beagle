//! CLI para analisar resultados da Expedition 001
//!
//! Uso:
//!   exp001-analyze [--experiment-id ID] [--output-format csv|json|md]

use anyhow::Result;
use beagle_config::load as load_config;
use beagle_experiments::{
    analysis::{calculate_metrics, join_experiment_data, load_feedback_events, load_run_reports},
    exp001::EXPEDITION_001_ID,
    load_experiment_tags_by_id,
};
use chrono::Utc;
use clap::{Parser, ValueEnum};
use std::path::PathBuf;
use tracing::info;

#[derive(Parser)]
#[command(name = "exp001-analyze", version)]
struct Cli {
    /// ID do experimento (default: beagle_exp_001_triad_vs_single)
    #[arg(long, default_value = EXPEDITION_001_ID)]
    experiment_id: String,

    /// Formato de saída (default: terminal)
    #[arg(long)]
    output_format: Option<OutputFormat>,

    /// Prefixo do arquivo de saída (default: exp001_<timestamp>)
    #[arg(long)]
    output_prefix: Option<String>,
}

#[derive(Debug, Clone, ValueEnum)]
enum OutputFormat {
    Csv,
    Json,
    Md,
}

#[tokio::main]
async fn main() -> Result<()> {
    tracing_subscriber::fmt()
        .with_env_filter(tracing_subscriber::EnvFilter::from_default_env())
        .init();

    let args = Cli::parse();

    let cfg = load_config();
    let data_dir = PathBuf::from(&cfg.storage.data_dir);

    info!("📊 Analisando Expedition 001: {}", args.experiment_id);

    // Carrega tags experimentais
    let tags = load_experiment_tags_by_id(&data_dir, &args.experiment_id)?;
    if tags.is_empty() {
        eprintln!("❌ Nenhuma tag encontrada para experiment_id: {}", args.experiment_id);
        std::process::exit(1);
    }

    info!("   Tags encontradas: {}", tags.len());

    // Carrega feedback e run reports
    let feedback = load_feedback_events(&data_dir)?;
    let run_ids: Vec<String> = tags.iter().map(|t| t.run_id.clone()).collect();
    let run_reports = load_run_reports(&data_dir, &run_ids)?;

    // Calcula métricas
    let data_points = join_experiment_data(tags, feedback, run_reports);
    let metrics = calculate_metrics(&data_points);

    // Imprime resumo no terminal (sempre)
    print_summary(&metrics);

    // Exporta se solicitado
    if let Some(format) = args.output_format {
        let prefix = args
            .output_prefix
            .unwrap_or_else(|| format!("exp001_{}", Utc::now().format("%Y%m%d_%H%M%S")));

        let output_dir = data_dir.join("experiments");
        std::fs::create_dir_all(&output_dir)?;

        match format {
            OutputFormat::Csv => {
                let csv_path = output_dir.join(format!("{}_summary.csv", prefix));
                export_csv(&metrics, &csv_path)?;
                println!("✅ CSV exportado para: {}", csv_path.display());
            }
            OutputFormat::Json => {
                let json_path = output_dir.join(format!("{}_summary.json", prefix));
                export_json(&metrics, &json_path)?;
                println!("✅ JSON exportado para: {}", json_path.display());
            }
            OutputFormat::Md => {
                let md_path = output_dir.join(format!("{}_report.md", prefix));
                export_markdown(&metrics, &cfg, &md_path)?;
                println!("✅ Relatório Markdown exportado para: {}", md_path.display());
            }
        }
    }

    Ok(())
}

fn print_summary(metrics: &beagle_experiments::analysis::ExperimentMetrics) {
    println!("\n{}", "=".repeat(70));
    println!("Expedition 001 – Análise");
    println!("{}", "=".repeat(70));
    println!("Experiment ID: {}", metrics.experiment_id);
    println!("Total de runs: {}", metrics.total_runs);
    println!();

    for (condition, cond_metrics) in &metrics.conditions {
        println!("Condition {}:", condition);
        println!("  runs: {} (feedback: {})", cond_metrics.n_runs, cond_metrics.n_with_feedback);
        if let Some(mean) = cond_metrics.rating_mean {
            println!("  rating mean: {:.2} (std: {:.2})", mean, cond_metrics.rating_std.unwrap_or(0.0));
        }
        if let Some(ratio) = cond_metrics.accepted_ratio {
            println!("  accepted: {:.1}%", ratio * 100.0);
        }
        println!();
    }

    // Effect size
    let triad_metrics = metrics.conditions.get("triad");
    let single_metrics = metrics.conditions.get("single");

    if let (Some(tm), Some(sm)) = (triad_metrics, single_metrics) {
        if let (Some(triad_mean), Some(single_mean)) = (tm.rating_mean, sm.rating_mean) {
            println!("📊 Effect (triad - single):");
            println!("  Δ rating mean: {:.2}", triad_mean - single_mean);
        }
        if let (Some(triad_ratio), Some(single_ratio)) = (tm.accepted_ratio, sm.accepted_ratio) {
            println!("  Δ accepted ratio: {:.2}", (triad_ratio - single_ratio) * 100.0);
        }
    }

    println!("{}", "=".repeat(70));
}

fn export_csv(
    metrics: &beagle_experiments::analysis::ExperimentMetrics,
    path: &PathBuf,
) -> Result<()> {
    use std::fs::File;
    use std::io::Write;

    let mut file = File::create(path)?;
    writeln!(file, "experiment_id,condition,n_runs,n_with_feedback,rating_mean,rating_std,accepted_ratio")?;

    for (condition, cond_metrics) in &metrics.conditions {
        writeln!(
            file,
            "{},{},{},{},{:.2},{:.2},{:.2}",
            metrics.experiment_id,
            condition,
            cond_metrics.n_runs,
            cond_metrics.n_with_feedback,
            cond_metrics.rating_mean.unwrap_or(0.0),
            cond_metrics.rating_std.unwrap_or(0.0),
            cond_metrics.accepted_ratio.unwrap_or(0.0)
        )?;
    }

    Ok(())
}

fn export_json(
    metrics: &beagle_experiments::analysis::ExperimentMetrics,
    path: &PathBuf,
) -> Result<()> {
    use std::fs::File;
    use std::io::Write;

    let json = serde_json::to_string_pretty(metrics)?;
    let mut file = File::create(path)?;
    write!(file, "{}", json)?;

    Ok(())
}

fn export_markdown(
    metrics: &beagle_experiments::analysis::ExperimentMetrics,
    cfg: &beagle_config::BeagleConfig,
    path: &PathBuf,
) -> Result<()> {
    use std::fs::File;
    use std::io::Write;

    let mut file = File::create(path)?;

    writeln!(file, "# Beagle Expedition 001 – Relatório de Análise")?;
    writeln!(file)?;
    writeln!(file, "**Experiment ID**: `{}`", metrics.experiment_id)?;
    writeln!(file, "**Data de Análise**: {}", Utc::now().format("%Y-%m-%d %H:%M:%S UTC"))?;
    writeln!(file)?;

    writeln!(file, "## Configuração LLM/Triad (Congelada)")?;
    writeln!(file)?;
    writeln!(file, "- **profile**: {}", cfg.profile)?;
    writeln!(file, "- **safe_mode**: {}", cfg.safe_mode)?;
    writeln!(file, "- **grok_model**: {}", cfg.llm.grok_model)?;
    writeln!(file, "- **serendipity_enabled**: {}", cfg.serendipity_enabled())?;
    writeln!(file, "- **serendipity_in_triad**: {}", cfg.serendipity_in_triad())?;
    writeln!(file)?;

    writeln!(file, "## Resultados")?;
    writeln!(file)?;
    writeln!(file, "**Total de runs**: {}", metrics.total_runs)?;
    writeln!(file)?;

    for (condition, cond_metrics) in &metrics.conditions {
        writeln!(file, "### Condition: `{}`", condition)?;
        writeln!(file)?;
        writeln!(file, "- **runs**: {}", cond_metrics.n_runs)?;
        writeln!(file, "- **feedback**: {}", cond_metrics.n_with_feedback)?;
        if let Some(mean) = cond_metrics.rating_mean {
            writeln!(
                file,
                "- **rating mean**: {:.2} (std: {:.2})",
                mean,
                cond_metrics.rating_std.unwrap_or(0.0)
            )?;
        }
        if let Some(ratio) = cond_metrics.accepted_ratio {
            writeln!(file, "- **accepted ratio**: {:.1}%", ratio * 100.0)?;
        }
        writeln!(file)?;
    }

    // Effect size
    let triad_metrics = metrics.conditions.get("triad");
    let single_metrics = metrics.conditions.get("single");

    if let (Some(tm), Some(sm)) = (triad_metrics, single_metrics) {
        writeln!(file, "## Effect Size (Triad - Single)")?;
        writeln!(file)?;

        if let (Some(triad_mean), Some(single_mean)) = (tm.rating_mean, sm.rating_mean) {
            writeln!(file, "- **Δ rating mean**: {:.2}", triad_mean - single_mean)?;
        }
        if let (Some(triad_ratio), Some(single_ratio)) = (tm.accepted_ratio, sm.accepted_ratio) {
            writeln!(
                file,
                "- **Δ accepted ratio**: {:.2}%",
                (triad_ratio - single_ratio) * 100.0
            )?;
        }

        writeln!(file)?;
    }

    writeln!(file, "---")?;
    writeln!(file)?;
    writeln!(
        file,
        "**Nota**: Análise estatística completa (t-tests, Mann-Whitney U, effect size, confidence intervals) deve ser feita em Julia/Python notebooks usando os dados exportados em CSV/JSON."
    )?;

    Ok(())
}

