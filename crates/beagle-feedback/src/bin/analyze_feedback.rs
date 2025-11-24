//! Analisador de feedback - Métricas sintetizadas
//!
//! Uso:
//!   cargo run --bin analyze-feedback --package beagle-feedback
//!   cargo run --bin analyze-feedback --package beagle-feedback -- --dashboard
//!
//! Opções:
//!   --dashboard    Exibe dashboard detalhado com tabela de runs recentes

use beagle_config::load as load_config;
use beagle_feedback::{load_all_events, FeedbackEventType};
use chrono::{DateTime, Utc};
use std::collections::HashMap;
use std::path::PathBuf;

#[derive(Debug, Default)]
struct RunDetails {
    run_id: String,
    timestamp: Option<DateTime<Utc>>,
    question: Option<String>,
    hrv_level: Option<String>,
    has_pipeline: bool,
    has_triad: bool,
    has_feedback: bool,
    accepted: Option<bool>,
    rating: Option<u8>,
    grok3_calls: u32,
    grok4_calls: u32,
}

fn main() -> anyhow::Result<()> {
    // Check for --dashboard flag
    let args: Vec<String> = std::env::args().collect();
    let dashboard_mode = args.iter().any(|a| a == "--dashboard");

    let cfg = load_config();
    let data_dir = PathBuf::from(&cfg.storage.data_dir);

    let events = load_all_events(&data_dir)?;

    let mut total_pipeline = 0usize;
    let mut total_triad = 0usize;
    let mut total_human = 0usize;

    let mut accepted = 0usize;
    let mut rejected = 0usize;
    let mut ratings: Vec<u8> = Vec::new();

    let mut grok3_total_calls = 0u32;
    let mut heavy_total_calls = 0u32;
    let mut grok3_total_tokens = 0u32;
    let mut heavy_total_tokens = 0u32;

    // Para contar runs distintos e runs com Heavy
    let mut run_ids = std::collections::HashSet::new();
    let mut runs_with_heavy = std::collections::HashSet::new();

    // Para dashboard: agrupar por run_id
    let mut run_details: HashMap<String, RunDetails> = HashMap::new();

    for ev in &events {
        run_ids.insert(ev.run_id.clone());

        // Atualizar detalhes do run para dashboard
        let details = run_details
            .entry(ev.run_id.clone())
            .or_insert_with(|| RunDetails {
                run_id: ev.run_id.clone(),
                timestamp: Some(ev.timestamp),
                question: ev.question.clone(),
                hrv_level: ev.hrv_level.clone(),
                ..Default::default()
            });

        // Atualizar timestamp para o mais antigo
        if let Some(ts) = details.timestamp {
            if ev.timestamp < ts {
                details.timestamp = Some(ev.timestamp);
            }
        }

        match ev.event_type {
            FeedbackEventType::PipelineRun => {
                total_pipeline += 1;
                details.has_pipeline = true;
                if let Some(c) = ev.grok3_calls {
                    details.grok3_calls += c;
                }
                if let Some(c) = ev.grok4_heavy_calls {
                    details.grok4_calls += c;
                }
            }
            FeedbackEventType::TriadCompleted => {
                total_triad += 1;
                details.has_triad = true;
                if let Some(c) = ev.grok3_calls {
                    grok3_total_calls += c;
                    details.grok3_calls += c;
                }
                if let Some(c) = ev.grok4_heavy_calls {
                    heavy_total_calls += c;
                    details.grok4_calls += c;
                    if c > 0 {
                        runs_with_heavy.insert(ev.run_id.clone());
                    }
                }
                if let Some(t) = ev.grok3_tokens_est {
                    grok3_total_tokens += t;
                }
                if let Some(t) = ev.grok4_tokens_est {
                    heavy_total_tokens += t;
                }
            }
            FeedbackEventType::HumanFeedback => {
                total_human += 1;
                details.has_feedback = true;
                if let Some(a) = ev.accepted {
                    details.accepted = Some(a);
                    if a {
                        accepted += 1;
                    } else {
                        rejected += 1;
                    }
                }
                if let Some(r) = ev.rating_0_10 {
                    details.rating = Some(r);
                    ratings.push(r);
                }
            }
        }
    }

    if dashboard_mode {
        print_dashboard(
            &run_details,
            total_pipeline,
            total_triad,
            total_human,
            accepted,
            rejected,
            &ratings,
            grok3_total_calls,
            heavy_total_calls,
            grok3_total_tokens,
            heavy_total_tokens,
            &runs_with_heavy,
            &run_ids,
        );
    } else {
        print_summary(
            total_pipeline,
            total_triad,
            total_human,
            accepted,
            rejected,
            &ratings,
            grok3_total_calls,
            heavy_total_calls,
            grok3_total_tokens,
            heavy_total_tokens,
            &runs_with_heavy,
            &run_ids,
        );
    }

    Ok(())
}

fn print_summary(
    total_pipeline: usize,
    total_triad: usize,
    total_human: usize,
    accepted: usize,
    rejected: usize,
    ratings: &[u8],
    grok3_total_calls: u32,
    heavy_total_calls: u32,
    grok3_total_tokens: u32,
    heavy_total_tokens: u32,
    runs_with_heavy: &std::collections::HashSet<String>,
    run_ids: &std::collections::HashSet<String>,
) {
    println!("=== BEAGLE FEEDBACK ANALYSIS ===");
    println!();
    println!("Eventos por tipo:");
    println!("  Pipeline runs:   {}", total_pipeline);
    println!("  Triad completas: {}", total_triad);
    println!("  Feedback humano: {}", total_human);
    println!("  Runs distintos:  {}", run_ids.len());
    println!();

    if total_triad > 0 {
        println!("LLM Usage (Triad):");
        println!("  Grok 3 calls:      {}", grok3_total_calls);
        println!("  Grok 4 Heavy calls: {}", heavy_total_calls);
        println!("  Grok 3 tokens est: {}", grok3_total_tokens);
        println!("  Heavy tokens est:   {}", heavy_total_tokens);
        if heavy_total_calls > 0 {
            let heavy_pct =
                (heavy_total_calls as f64 / (grok3_total_calls + heavy_total_calls) as f64) * 100.0;
            println!("  Heavy usage: {:.1}%", heavy_pct);
        }
        println!(
            "  Runs com Heavy:    {} ({:.1}%)",
            runs_with_heavy.len(),
            (runs_with_heavy.len() as f64 / run_ids.len() as f64) * 100.0
        );
        println!();
    }

    if total_human > 0 {
        println!("Feedback Humano:");
        println!("  Accepted: {} | Rejected: {}", accepted, rejected);
        if !ratings.is_empty() {
            let mut sorted_ratings = ratings.to_vec();
            sorted_ratings.sort();
            let n = sorted_ratings.len();
            let avg: f32 = sorted_ratings.iter().map(|&r| r as f32).sum::<f32>() / n as f32;
            let p50 = sorted_ratings[n / 2];
            let p90_idx = ((n as f32 * 0.9) as usize).min(n - 1);
            let p90 = sorted_ratings[p90_idx];
            println!("  Rating média: {:.2}/10", avg);
            println!("  Rating p50:   {}/10", p50);
            println!("  Rating p90:   {}/10", p90);
        }
    } else {
        println!("Nenhum feedback humano registrado ainda.");
    }

    println!();
}

fn print_dashboard(
    run_details: &HashMap<String, RunDetails>,
    total_pipeline: usize,
    total_triad: usize,
    total_human: usize,
    accepted: usize,
    rejected: usize,
    ratings: &[u8],
    grok3_total_calls: u32,
    heavy_total_calls: u32,
    grok3_total_tokens: u32,
    heavy_total_tokens: u32,
    runs_with_heavy: &std::collections::HashSet<String>,
    run_ids: &std::collections::HashSet<String>,
) {
    println!("\n{}", "=".repeat(140));
    println!("{:^140}", "BEAGLE FEEDBACK DASHBOARD");
    println!("{}", "=".repeat(140));

    // Summary statistics
    println!("\n📊 SUMMARY STATISTICS");
    println!("{}", "-".repeat(140));
    println!(
        "Total Events: {} | Pipeline: {} | Triad: {} | Human Feedback: {} | Unique Runs: {}",
        total_pipeline + total_triad + total_human,
        total_pipeline,
        total_triad,
        total_human,
        run_ids.len()
    );

    if total_human > 0 {
        let accept_rate = (accepted as f64 / (accepted + rejected) as f64) * 100.0;
        println!(
            "Acceptance: ✓ {} ({:.1}%) | ✗ {} ({:.1}%)",
            accepted,
            accept_rate,
            rejected,
            100.0 - accept_rate
        );
    }

    if !ratings.is_empty() {
        let mut sorted_ratings = ratings.to_vec();
        sorted_ratings.sort();
        let n = sorted_ratings.len();
        let avg: f32 = sorted_ratings.iter().map(|&r| r as f32).sum::<f32>() / n as f32;
        let p50 = sorted_ratings[n / 2];
        let p90_idx = ((n as f32 * 0.9) as usize).min(n - 1);
        let p90 = sorted_ratings[p90_idx];
        println!(
            "Ratings: Avg {:.1}/10 | p50 {}/10 | p90 {}/10",
            avg, p50, p90
        );
    }

    if heavy_total_calls > 0 {
        let heavy_pct =
            (heavy_total_calls as f64 / (grok3_total_calls + heavy_total_calls) as f64) * 100.0;
        println!(
            "Heavy Usage: {} runs ({:.1}%) | {} calls ({:.1}%) | {} tokens",
            runs_with_heavy.len(),
            (runs_with_heavy.len() as f64 / run_ids.len() as f64) * 100.0,
            heavy_total_calls,
            heavy_pct,
            heavy_total_tokens
        );
    }

    // Recent runs table
    println!("\n📋 RECENT RUNS (Last 20)");
    println!("{}", "-".repeat(140));

    println!(
        "{:<38} {:<20} {:<40} {:^5} {:^5} {:^5} {:>6} {:>4} {:>4} {:>8}",
        "RUN_ID", "DATE", "QUESTION", "PIPE", "TRIAD", "FEED", "RATING", "G3", "G4", "HRV"
    );
    println!("{}", "=".repeat(140));

    // Sort by timestamp (most recent first)
    let mut runs: Vec<&RunDetails> = run_details.values().collect();
    runs.sort_by(|a, b| b.timestamp.cmp(&a.timestamp));

    for (i, run) in runs.iter().take(20).enumerate() {
        let date_str = run
            .timestamp
            .map(|ts| ts.format("%Y-%m-%d %H:%M").to_string())
            .unwrap_or_else(|| "N/A".to_string());

        let question_str = run
            .question
            .as_ref()
            .map(|q| {
                if q.len() > 37 {
                    format!("{}...", &q[..37])
                } else {
                    q.clone()
                }
            })
            .unwrap_or_else(|| "N/A".to_string());

        let pipe_mark = if run.has_pipeline { "✓" } else { "-" };
        let triad_mark = if run.has_triad { "✓" } else { "-" };
        let feedback_mark = if run.has_feedback { "✓" } else { "-" };

        let rating_str = run
            .rating
            .map(|r| {
                let symbol = match run.accepted {
                    Some(true) => "✓",
                    Some(false) => "✗",
                    None => " ",
                };
                format!("{}{}/10", symbol, r)
            })
            .unwrap_or_else(|| "-".to_string());

        let g3_str = if run.grok3_calls > 0 {
            format!("{}", run.grok3_calls)
        } else {
            "-".to_string()
        };

        let g4_str = if run.grok4_calls > 0 {
            format!("{}", run.grok4_calls)
        } else {
            "-".to_string()
        };

        let hrv_str = run
            .hrv_level
            .as_ref()
            .map(|h| match h.as_str() {
                "low" => "LOW",
                "high" => "HIGH",
                "normal" => "NORM",
                _ => "?",
            })
            .unwrap_or("-");

        // Alternate row colors (simulated with spacing)
        if i % 2 == 1 {
            print!("│ ");
        } else {
            print!("  ");
        }

        println!(
            "{:<38} {:<20} {:<40} {:^5} {:^5} {:^5} {:>6} {:>4} {:>4} {:>8}",
            &run.run_id[..38.min(run.run_id.len())],
            date_str,
            question_str,
            pipe_mark,
            triad_mark,
            feedback_mark,
            rating_str,
            g3_str,
            g4_str,
            hrv_str
        );
    }

    println!("{}", "=".repeat(140));
    println!("\n💡 TIP: Use 'list_runs' for complete run details");
    println!("💡 TIP: Use 'analyze-feedback' (without --dashboard) for summary only\n");
}
