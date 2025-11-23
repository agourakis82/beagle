//! Binário para analisar resultados de experimentos
//!
//! Uso:
//!   analyze_experiments <experiment_id> [--output-format csv|json] [--output-file PATH]
//!
//! Agrega métricas por condição:
//! - n_runs, n_with_feedback
//! - rating_mean, rating_std, rating_p50, rating_p90
//! - accepted_ratio
//! - Distribuição de severidades (physio/env/space)
//! - stress_index_mean
//! - avg_tokens, avg_grok3_calls, avg_grok4_calls

use anyhow::Result;
use beagle_config::beagle_data_dir;
use beagle_experiments::{
    load_experiment_tags_by_id,
    analysis::{
        load_feedback_events,
        load_run_reports,
        join_experiment_data,
        calculate_metrics,
        export_summary_csv,
        export_summary_json,
    },
};
use clap::Parser;
use std::collections::HashMap;
use std::path::PathBuf;
use tracing::info;

#[derive(Parser)]
#[command(name = "analyze_experiments", version)]
struct Cli {
    /// ID do experimento (obrigatório)
    experiment_id: String,
    
    /// Formato de saída (csv|json|terminal, default: terminal)
    #[arg(long, default_value = "terminal")]
    output_format: String,
    
    /// Arquivo de saída (opcional, default: experiments/<experiment_id>_summary.{csv|json})
    #[arg(long)]
    output_file: Option<PathBuf>,
}

fn main() -> Result<()> {
    tracing_subscriber::fmt()
        .with_env_filter(tracing_subscriber::EnvFilter::from_default_env())
        .init();
    
    let args = Cli::parse();
    
    info!("📊 Analisando experimento: {}", args.experiment_id);
    
    let data_dir = beagle_data_dir();
    
    // Carrega tags do experimento
    let tags = load_experiment_tags_by_id(&data_dir, &args.experiment_id)?;
    
    if tags.is_empty() {
        eprintln!("⚠️  Nenhuma tag encontrada para experiment_id: {}", args.experiment_id);
        return Ok(());
    }
    
    info!("   Tags encontradas: {}", tags.len());
    
    // Extrai run_ids
    let run_ids: Vec<String> = tags.iter().map(|t| t.run_id.clone()).collect();
    
    // Carrega feedback events
    let feedback_events = load_feedback_events(&data_dir)?;
    info!("   Feedback events encontrados: {}", feedback_events.len());
    
    // Carrega run reports
    let run_reports = load_run_reports(&data_dir, &run_ids)?;
    info!("   Run reports encontrados: {}", run_reports.len());
    
    // Faz join de dados
    let data_points = join_experiment_data(tags, feedback_events, run_reports);
    
    // Calcula métricas
    let metrics = calculate_metrics(&data_points);
    
    // Imprime resumo no terminal
    print_summary(&metrics);
    
    // Se for Expedition 001, imprime análise adicional
    if args.experiment_id.starts_with("beagle_exp_001") {
        print_expedition_001_analysis(&metrics);
    }
    
    // Exporta se solicitado
    match args.output_format.as_str() {
        "csv" => {
            let output_file = args.output_file.unwrap_or_else(|| {
                data_dir.join("experiments").join(format!("{}_summary.csv", args.experiment_id))
            });
            let csv = export_summary_csv(&data_points)?;
            std::fs::write(&output_file, csv)?;
            info!("✅ Resumo CSV salvo em: {}", output_file.display());
        }
        "json" => {
            let output_file = args.output_file.unwrap_or_else(|| {
                data_dir.join("experiments").join(format!("{}_summary.json", args.experiment_id))
            });
            let json = export_summary_json(&metrics)?;
            std::fs::write(&output_file, json)?;
            info!("✅ Resumo JSON salvo em: {}", output_file.display());
        }
        _ => {
            // Apenas terminal, já impresso acima
        }
    }
    
    Ok(())
}

/// Imprime resumo formatado no terminal
fn print_summary(metrics: &beagle_experiments::analysis::ExperimentMetrics) {
    println!("\n📊 Experimento: {}", metrics.experiment_id);
    println!("   Total de runs: {}", metrics.total_runs);
    println!();
    
    // Ordena condições para output consistente
    let mut conditions: Vec<_> = metrics.conditions.keys().collect();
    conditions.sort();
    
    for condition in conditions {
        let cond_metrics = &metrics.conditions[condition];
        println!("Condition {}:", condition);
        println!("  runs: {} (feedback: {})", cond_metrics.n_runs, cond_metrics.n_with_feedback);
        
        if let Some(mean) = cond_metrics.rating_mean {
            if let Some(std) = cond_metrics.rating_std {
                println!("  rating mean: {:.2} (std {:.2})", mean, std);
            }
            if let Some(p50) = cond_metrics.rating_p50 {
                println!("  rating p50: {:.2}", p50);
            }
            if let Some(p90) = cond_metrics.rating_p90 {
                println!("  rating p90: {:.2}", p90);
            }
        }
        
        if let Some(ratio) = cond_metrics.accepted_ratio {
            println!("  accepted: {}/{} ({:.1}%)", 
                cond_metrics.accepted_count, 
                cond_metrics.n_with_feedback,
                ratio * 100.0);
        }
        
        if !cond_metrics.physio_severity_counts.is_empty() {
            println!("  physio_severity: {}", format_severity_counts(&cond_metrics.physio_severity_counts));
        }
        if !cond_metrics.env_severity_counts.is_empty() {
            println!("  env_severity: {}", format_severity_counts(&cond_metrics.env_severity_counts));
        }
        if !cond_metrics.space_severity_counts.is_empty() {
            println!("  space_severity: {}", format_severity_counts(&cond_metrics.space_severity_counts));
        }
        
        if let Some(stress) = cond_metrics.stress_index_mean {
            println!("  stress_index_mean: {:.3}", stress);
        }
        
        if let Some(tokens) = cond_metrics.avg_tokens {
            println!("  avg_tokens: {:.0}", tokens);
        }
        if let Some(g3) = cond_metrics.avg_grok3_calls {
            println!("  avg_grok3_calls: {:.1}", g3);
        }
        if let Some(g4) = cond_metrics.avg_grok4_calls {
            println!("  avg_grok4_calls: {:.1}", g4);
        }
        
        println!();
    }
}

/// Formata contagens de severidade como string
fn format_severity_counts(counts: &HashMap<String, usize>) -> String {
    let mut parts: Vec<String> = counts.iter()
        .map(|(k, v)| format!("{}:{}", k, v))
        .collect();
    parts.sort();
    parts.join(" ")
}

/// Análise específica para Expedition 001
fn print_expedition_001_analysis(metrics: &beagle_experiments::analysis::ExperimentMetrics) {
    use beagle_experiments::analysis::ConditionMetrics;
    
    println!("\n{}", "=".repeat(70));
    println!("Expedition 001 – Detailed Analysis");
    println!("{}", "=".repeat(70));
    
    // Verifica se temos as duas condições esperadas
    let triad_metrics = metrics.conditions.get("triad");
    let single_metrics = metrics.conditions.get("single");
    
    if triad_metrics.is_none() || single_metrics.is_none() {
        println!("⚠️  Expedition 001 espera condições 'triad' e 'single'.");
        return;
    }
    
    let triad = triad_metrics.unwrap();
    let single = single_metrics.unwrap();
    
    // Análise de ratings
    println!("\n📊 Ratings Analysis:");
    if let (Some(triad_mean), Some(single_mean)) = (triad.rating_mean, single.rating_mean) {
        println!("  Condition: triad");
        println!("    runs (with feedback): {}", triad.n_with_feedback);
        println!("    mean rating: {:.2}", triad_mean);
        if let Some(std) = triad.rating_std {
            println!("    std: {:.2}", std);
        }
        if let Some(p50) = triad.rating_p50 {
            println!("    p50: {:.2}", p50);
        }
        if let Some(p90) = triad.rating_p90 {
            println!("    p90: {:.2}", p90);
        }
        
        println!("\n  Condition: single");
        println!("    runs (with feedback): {}", single.n_with_feedback);
        println!("    mean rating: {:.2}", single_mean);
        if let Some(std) = single.rating_std {
            println!("    std: {:.2}", std);
        }
        if let Some(p50) = single.rating_p50 {
            println!("    p50: {:.2}", p50);
        }
        if let Some(p90) = single.rating_p90 {
            println!("    p90: {:.2}", p90);
        }
        
        // Effect size (diferença de médias)
        let delta = triad_mean - single_mean;
        println!("\n  Effect (triad - single):");
        println!("    Δ rating mean: {:.2}", delta);
        if delta > 0.0 {
            println!("    → Triad produces higher ratings (positive effect)");
        } else if delta < 0.0 {
            println!("    → Single produces higher ratings (negative effect)");
        } else {
            println!("    → No difference detected");
        }
    } else {
        println!("  ⚠️  Insufficient rating data for analysis");
    }
    
    // Análise de aceitação
    println!("\n✅ Acceptance Analysis:");
    if let (Some(triad_ratio), Some(single_ratio)) = (triad.accepted_ratio, single.accepted_ratio) {
        println!("  Condition: triad");
        println!("    accepted: {}/{} ({:.1}%)", 
            triad.accepted_count, 
            triad.n_with_feedback,
            triad_ratio * 100.0);
        
        println!("  Condition: single");
        println!("    accepted: {}/{} ({:.1}%)", 
            single.accepted_count, 
            single.n_with_feedback,
            single_ratio * 100.0);
        
        let delta_ratio = triad_ratio - single_ratio;
        println!("\n  Effect (triad - single):");
        println!("    Δ accepted ratio: {:.1}%", delta_ratio * 100.0);
    }
    
    // Distribuição de severidades por condição
    println!("\n🏥 Observer Severity Distribution:");
    println!("  Condition: triad");
    if !triad.physio_severity_counts.is_empty() {
        println!("    physio_severity: {}", format_severity_counts_detailed(&triad.physio_severity_counts));
    }
    if !triad.env_severity_counts.is_empty() {
        println!("    env_severity: {}", format_severity_counts_detailed(&triad.env_severity_counts));
    }
    if !triad.space_severity_counts.is_empty() {
        println!("    space_severity: {}", format_severity_counts_detailed(&triad.space_severity_counts));
    }
    
    println!("  Condition: single");
    if !single.physio_severity_counts.is_empty() {
        println!("    physio_severity: {}", format_severity_counts_detailed(&single.physio_severity_counts));
    }
    if !single.env_severity_counts.is_empty() {
        println!("    env_severity: {}", format_severity_counts_detailed(&single.env_severity_counts));
    }
    if !single.space_severity_counts.is_empty() {
        println!("    space_severity: {}", format_severity_counts_detailed(&single.space_severity_counts));
    }
    
    // Stress index
    if let (Some(triad_stress), Some(single_stress)) = (triad.stress_index_mean, single.stress_index_mean) {
        println!("\n📈 Stress Index:");
        println!("  triad mean: {:.3}", triad_stress);
        println!("  single mean: {:.3}", single_stress);
        let delta_stress = triad_stress - single_stress;
        println!("  Δ: {:.3}", delta_stress);
    }
    
    // Tokens (opcional)
    if let (Some(triad_tokens), Some(single_tokens)) = (triad.avg_tokens, single.avg_tokens) {
        println!("\n💻 LLM Usage:");
        println!("  triad avg_tokens: {:.0}", triad_tokens);
        println!("  single avg_tokens: {:.0}", single_tokens);
        let delta_tokens = triad_tokens - single_tokens;
        println!("  Δ: {:.0}", delta_tokens);
    }
    
    // Nota sobre testes estatísticos
    println!("\n{}", "=".repeat(70));
    println!("Note: Statistical significance and deeper analysis (t-tests, Mann-Whitney U,");
    println!("      effect size calculations, confidence intervals) to be done in");
    println!("      Julia/Python notebooks using the exported CSV/JSON data.");
    println!("{}", "=".repeat(70));
    println!();
}

/// Formata contagens de severidade de forma mais legível para Expedition 001
fn format_severity_counts_detailed(counts: &HashMap<String, usize>) -> String {
    let order = ["Normal", "Mild", "Moderate", "Severe"];
    let mut parts = Vec::new();
    
    for severity in &order {
        if let Some(&count) = counts.get(*severity) {
            parts.push(format!("{}={}", severity, count));
        }
    }
    
    // Adiciona qualquer severidade que não esteja na lista padrão
    for (k, v) in counts {
        if !order.contains(&k.as_str()) {
            parts.push(format!("{}={}", k, v));
        }
    }
    
    parts.join(" ")
}

