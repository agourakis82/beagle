//! Analisador de feedback - Métricas sintetizadas
//!
//! Uso:
//!   cargo run --bin analyze-feedback --package beagle-feedback

use beagle_config::load as load_config;
use beagle_feedback::{load_all_events, FeedbackEventType};
use std::path::PathBuf;

fn main() -> anyhow::Result<()> {
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

    for ev in &events {
        match ev.event_type {
            FeedbackEventType::PipelineRun => total_pipeline += 1,
            FeedbackEventType::TriadCompleted => {
                total_triad += 1;
                if let Some(c) = ev.grok3_calls {
                    grok3_total_calls += c;
                }
                if let Some(c) = ev.grok4_heavy_calls {
                    heavy_total_calls += c;
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
                if let Some(a) = ev.accepted {
                    if a {
                        accepted += 1;
                    } else {
                        rejected += 1;
                    }
                }
                if let Some(r) = ev.rating_0_10 {
                    ratings.push(r);
                }
            }
        }
    }

    println!("=== BEAGLE FEEDBACK ANALYSIS ===");
    println!();
    println!("Eventos por tipo:");
    println!("  Pipeline runs:   {}", total_pipeline);
    println!("  Triad completas: {}", total_triad);
    println!("  Feedback humano: {}", total_human);
    println!();

    if total_triad > 0 {
        println!("LLM Usage (Triad):");
        println!("  Grok 3 calls:      {}", grok3_total_calls);
        println!("  Grok 4 Heavy calls: {}", heavy_total_calls);
        println!("  Grok 3 tokens est: {}", grok3_total_tokens);
        println!("  Heavy tokens est:   {}", heavy_total_tokens);
        if heavy_total_calls > 0 {
            let heavy_pct = (heavy_total_calls as f64 / (grok3_total_calls + heavy_total_calls) as f64) * 100.0;
            println!("  Heavy usage: {:.1}%", heavy_pct);
        }
        println!();
    }

    if total_human > 0 {
        println!("Feedback Humano:");
        println!("  Accepted: {} | Rejected: {}", accepted, rejected);
        if !ratings.is_empty() {
            ratings.sort();
            let n = ratings.len();
            let avg: f32 = ratings.iter().map(|&r| r as f32).sum::<f32>() / n as f32;
            let p50 = ratings[n / 2];
            let p90_idx = ((n as f32 * 0.9) as usize).min(n - 1);
            let p90 = ratings[p90_idx];
            println!("  Rating média: {:.2}/10", avg);
            println!("  Rating p50:   {}/10", p50);
            println!("  Rating p90:   {}/10", p90);
        }
    } else {
        println!("Nenhum feedback humano registrado ainda.");
    }

    Ok(())
}

