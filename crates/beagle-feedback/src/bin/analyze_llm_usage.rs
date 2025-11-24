//! CLI para analisar uso de LLMs (Grok 3 vs Heavy, tokens, custos estimados)

use beagle_config::load as load_config;
use beagle_feedback::load_all_events;
use std::collections::HashMap;
use std::path::PathBuf;

#[derive(Debug, Default)]
struct LlmUsageStats {
    total_runs: usize,
    grok3_runs: usize,
    heavy_runs: usize,
    grok3_total_calls: u32,
    heavy_total_calls: u32,
    grok3_total_tokens: u32,
    heavy_total_tokens: u32,
    runs_by_provider: HashMap<String, usize>,
}

fn main() -> anyhow::Result<()> {
    let cfg = load_config();
    let data_dir = PathBuf::from(&cfg.storage.data_dir);

    let events = load_all_events(&data_dir)?;

    let mut stats = LlmUsageStats::default();
    let mut run_ids = std::collections::HashSet::new();

    for ev in &events {
        run_ids.insert(ev.run_id.clone());

        if let Some(provider) = &ev.llm_provider_main {
            *stats.runs_by_provider.entry(provider.clone()).or_insert(0) += 1;
        }

        if let Some(calls) = ev.grok3_calls {
            if calls > 0 {
                stats.grok3_runs += 1;
                stats.grok3_total_calls += calls;
            }
        }

        if let Some(calls) = ev.grok4_heavy_calls {
            if calls > 0 {
                stats.heavy_runs += 1;
                stats.heavy_total_calls += calls;
            }
        }

        if let Some(tokens) = ev.grok3_tokens_est {
            stats.grok3_total_tokens += tokens;
        }

        if let Some(tokens) = ev.grok4_tokens_est {
            stats.heavy_total_tokens += tokens;
        }
    }

    stats.total_runs = run_ids.len();

    println!("=== BEAGLE LLM USAGE ANALYSIS ===");
    println!();
    println!("Total de runs distintos: {}", stats.total_runs);
    println!();

    println!("Runs por Provider:");
    for (provider, count) in &stats.runs_by_provider {
        let pct = (*count as f64 / stats.total_runs as f64) * 100.0;
        println!("  {}: {} ({:.1}%)", provider, count, pct);
    }
    println!();

    println!("Grok 3:");
    println!(
        "  Runs usando Grok 3: {} ({:.1}%)",
        stats.grok3_runs,
        (stats.grok3_runs as f64 / stats.total_runs.max(1) as f64) * 100.0
    );
    println!("  Total de calls: {}", stats.grok3_total_calls);
    println!("  Total de tokens (est): {}", stats.grok3_total_tokens);
    println!();

    println!("Grok 4 Heavy:");
    println!(
        "  Runs usando Heavy: {} ({:.1}%)",
        stats.heavy_runs,
        (stats.heavy_runs as f64 / stats.total_runs.max(1) as f64) * 100.0
    );
    println!("  Total de calls: {}", stats.heavy_total_calls);
    println!("  Total de tokens (est): {}", stats.heavy_total_tokens);
    println!();

    let total_calls = stats.grok3_total_calls + stats.heavy_total_calls;
    let total_tokens = stats.grok3_total_tokens + stats.heavy_total_tokens;

    if total_calls > 0 {
        let heavy_pct = (stats.heavy_total_calls as f64 / total_calls as f64) * 100.0;
        println!("Heavy Usage: {:.1}% das calls totais", heavy_pct);
    }

    if total_tokens > 0 {
        let heavy_token_pct = (stats.heavy_total_tokens as f64 / total_tokens as f64) * 100.0;
        println!("Heavy Tokens: {:.1}% dos tokens totais", heavy_token_pct);
    }

    // Estimativa de custo (placeholder - valores reais dependem da API)
    println!();
    println!("Estimativa de custo (placeholder):");
    println!("  Grok 3: $0.00 (ilimitado)");
    println!(
        "  Grok 4 Heavy: ~${:.2} (estimado)",
        stats.heavy_total_tokens as f64 * 0.00001
    );

    // Exporta JSON com estatísticas detalhadas
    let output = serde_json::json!({
        "total_runs": stats.total_runs,
        "runs_by_provider": stats.runs_by_provider,
        "grok3": {
            "runs": stats.grok3_runs,
            "total_calls": stats.grok3_total_calls,
            "total_tokens": stats.grok3_total_tokens,
            "avg_calls_per_run": if stats.grok3_runs > 0 { stats.grok3_total_calls as f64 / stats.grok3_runs as f64 } else { 0.0 },
        },
        "grok4_heavy": {
            "runs": stats.heavy_runs,
            "total_calls": stats.heavy_total_calls,
            "total_tokens": stats.heavy_total_tokens,
            "avg_calls_per_run": if stats.heavy_runs > 0 { stats.heavy_total_calls as f64 / stats.heavy_runs as f64 } else { 0.0 },
        },
        "heavy_usage_percentage": if total_calls > 0 { (stats.heavy_total_calls as f64 / total_calls as f64) * 100.0 } else { 0.0 },
    });

    let output_file = data_dir.join("feedback").join("llm_usage_stats.json");
    std::fs::create_dir_all(output_file.parent().unwrap())?;
    std::fs::write(&output_file, serde_json::to_string_pretty(&output)?)?;

    println!();
    println!("✅ Estatísticas exportadas para: {}", output_file.display());

    Ok(())
}
