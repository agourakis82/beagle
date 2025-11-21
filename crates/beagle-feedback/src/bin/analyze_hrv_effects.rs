//! CLI para analisar efeitos do HRV nos resultados (ratings, aceitação)

use beagle_config::load as load_config;
use beagle_feedback::load_all_events;
use std::collections::HashMap;
use std::path::PathBuf;

#[derive(Debug, Default)]
struct HrvStats {
    low_count: usize,
    normal_count: usize,
    high_count: usize,
    low_ratings: Vec<u8>,
    normal_ratings: Vec<u8>,
    high_ratings: Vec<u8>,
    low_accepted: usize,
    normal_accepted: usize,
    high_accepted: usize,
    low_total: usize,
    normal_total: usize,
    high_total: usize,
}

fn main() -> anyhow::Result<()> {
    let cfg = load_config();
    let data_dir = PathBuf::from(&cfg.storage.data_dir);

    let events = load_all_events(&data_dir)?;

    let mut stats = HrvStats::default();
    let mut hrv_by_run: HashMap<String, String> = HashMap::new();

    // Primeiro, mapeia HRV por run_id
    for ev in &events {
        if let Some(hrv) = &ev.hrv_level {
            hrv_by_run.insert(ev.run_id.clone(), hrv.clone());
        }
    }

    // Depois, analisa feedback humano agrupado por HRV
    for ev in &events {
        if ev.event_type == beagle_feedback::FeedbackEventType::HumanFeedback {
            if let Some(hrv_level) = hrv_by_run.get(&ev.run_id) {
                match hrv_level.as_str() {
                    "low" => {
                        stats.low_total += 1;
                        if let Some(accepted) = ev.accepted {
                            if accepted {
                                stats.low_accepted += 1;
                            }
                        }
                        if let Some(rating) = ev.rating_0_10 {
                            stats.low_ratings.push(rating);
                        }
                    }
                    "normal" => {
                        stats.normal_total += 1;
                        if let Some(accepted) = ev.accepted {
                            if accepted {
                                stats.normal_accepted += 1;
                            }
                        }
                        if let Some(rating) = ev.rating_0_10 {
                            stats.normal_ratings.push(rating);
                        }
                    }
                    "high" => {
                        stats.high_total += 1;
                        if let Some(accepted) = ev.accepted {
                            if accepted {
                                stats.high_accepted += 1;
                            }
                        }
                        if let Some(rating) = ev.rating_0_10 {
                            stats.high_ratings.push(rating);
                        }
                    }
                    _ => {}
                }
            }
        }
    }

    println!("=== BEAGLE HRV EFFECTS ANALYSIS ===");
    println!();
    
    println!("Feedback por HRV Level:");
    println!();
    
    if stats.low_total > 0 {
        let accept_rate = (stats.low_accepted as f64 / stats.low_total as f64) * 100.0;
        let avg_rating = if !stats.low_ratings.is_empty() {
            stats.low_ratings.iter().sum::<u8>() as f64 / stats.low_ratings.len() as f64
        } else {
            0.0
        };
        println!("HRV LOW:");
        println!("  Total feedback: {}", stats.low_total);
        println!("  Accepted: {} ({:.1}%)", stats.low_accepted, accept_rate);
        println!("  Rating médio: {:.2}/10", avg_rating);
        if !stats.low_ratings.is_empty() {
            stats.low_ratings.sort();
            let p50 = stats.low_ratings[stats.low_ratings.len() / 2];
            println!("  Rating p50: {}/10", p50);
        }
        println!();
    }
    
    if stats.normal_total > 0 {
        let accept_rate = (stats.normal_accepted as f64 / stats.normal_total as f64) * 100.0;
        let avg_rating = if !stats.normal_ratings.is_empty() {
            stats.normal_ratings.iter().map(|&r| r as f64).sum::<f64>() / stats.normal_ratings.len() as f64
        } else {
            0.0
        };
        println!("HRV NORMAL:");
        println!("  Total feedback: {}", stats.normal_total);
        println!("  Accepted: {} ({:.1}%)", stats.normal_accepted, accept_rate);
        println!("  Rating médio: {:.2}/10", avg_rating);
        if !stats.normal_ratings.is_empty() {
            stats.normal_ratings.sort();
            let p50 = stats.normal_ratings[stats.normal_ratings.len() / 2];
            println!("  Rating p50: {}/10", p50);
        }
        println!();
    }
    
    if stats.high_total > 0 {
        let accept_rate = (stats.high_accepted as f64 / stats.high_total as f64) * 100.0;
        let avg_rating = if !stats.high_ratings.is_empty() {
            stats.high_ratings.iter().map(|&r| r as f64).sum::<f64>() / stats.high_ratings.len() as f64
        } else {
            0.0
        };
        println!("HRV HIGH:");
        println!("  Total feedback: {}", stats.high_total);
        println!("  Accepted: {} ({:.1}%)", stats.high_accepted, accept_rate);
        println!("  Rating médio: {:.2}/10", avg_rating);
        if !stats.high_ratings.is_empty() {
            stats.high_ratings.sort();
            let p50 = stats.high_ratings[stats.high_ratings.len() / 2];
            println!("  Rating p50: {}/10", p50);
        }
        println!();
    }
    
    if stats.low_total == 0 && stats.normal_total == 0 && stats.high_total == 0 {
        println!("Nenhum feedback com HRV level disponível.");
    }

    // Calcula uso médio de Heavy por HRV level
    let mut heavy_usage_by_hrv: HashMap<String, (u32, usize)> = HashMap::new();
    for ev in &events {
        if let Some(hrv_level) = &ev.hrv_level {
            if let Some(heavy_calls) = ev.grok4_heavy_calls {
                let entry = heavy_usage_by_hrv.entry(hrv_level.clone()).or_insert((0, 0));
                entry.0 += heavy_calls;
                entry.1 += 1;
            }
        }
    }

    println!("Uso médio de Heavy por HRV Level:");
    for (hrv_level, (total_calls, count)) in &heavy_usage_by_hrv {
        let avg = if *count > 0 { *total_calls as f64 / *count as f64 } else { 0.0 };
        println!("  {}: {:.2} calls/run (total: {} calls em {} runs)", hrv_level, avg, total_calls, count);
    }
    println!();

    // Exporta JSON com estatísticas
    let output = serde_json::json!({
        "low": if stats.low_total > 0 {
            serde_json::json!({
                "total": stats.low_total,
                "accepted": stats.low_accepted,
                "accept_rate": (stats.low_accepted as f64 / stats.low_total as f64) * 100.0,
                "avg_rating": if !stats.low_ratings.is_empty() {
                    stats.low_ratings.iter().sum::<u8>() as f64 / stats.low_ratings.len() as f64
                } else { 0.0 },
                "p50_rating": if !stats.low_ratings.is_empty() {
                    let mut sorted = stats.low_ratings.clone();
                    sorted.sort();
                    sorted[sorted.len() / 2]
                } else { 0 },
                "heavy_avg_calls": heavy_usage_by_hrv.get("low").map(|(calls, count)| {
                    if *count > 0 { *calls as f64 / *count as f64 } else { 0.0 }
                }).unwrap_or(0.0),
            })
        } else { serde_json::Value::Null },
        "normal": if stats.normal_total > 0 {
            serde_json::json!({
                "total": stats.normal_total,
                "accepted": stats.normal_accepted,
                "accept_rate": (stats.normal_accepted as f64 / stats.normal_total as f64) * 100.0,
                "avg_rating": if !stats.normal_ratings.is_empty() {
                    stats.normal_ratings.iter().sum::<u8>() as f64 / stats.normal_ratings.len() as f64
                } else { 0.0 },
                "p50_rating": if !stats.normal_ratings.is_empty() {
                    let mut sorted = stats.normal_ratings.clone();
                    sorted.sort();
                    sorted[sorted.len() / 2]
                } else { 0 },
                "heavy_avg_calls": heavy_usage_by_hrv.get("normal").map(|(calls, count)| {
                    if *count > 0 { *calls as f64 / *count as f64 } else { 0.0 }
                }).unwrap_or(0.0),
            })
        } else { serde_json::Value::Null },
        "high": if stats.high_total > 0 {
            serde_json::json!({
                "total": stats.high_total,
                "accepted": stats.high_accepted,
                "accept_rate": (stats.high_accepted as f64 / stats.high_total as f64) * 100.0,
                "avg_rating": if !stats.high_ratings.is_empty() {
                    stats.high_ratings.iter().sum::<u8>() as f64 / stats.high_ratings.len() as f64
                } else { 0.0 },
                "p50_rating": if !stats.high_ratings.is_empty() {
                    let mut sorted = stats.high_ratings.clone();
                    sorted.sort();
                    sorted[sorted.len() / 2]
                } else { 0 },
                "heavy_avg_calls": heavy_usage_by_hrv.get("high").map(|(calls, count)| {
                    if *count > 0 { *calls as f64 / *count as f64 } else { 0.0 }
                }).unwrap_or(0.0),
            })
        } else { serde_json::Value::Null },
    });
    
    let output_file = data_dir.join("feedback").join("hrv_effects_stats.json");
    std::fs::create_dir_all(output_file.parent().unwrap())?;
    std::fs::write(&output_file, serde_json::to_string_pretty(&output)?)?;
    
    println!("✅ Estatísticas exportadas para: {}", output_file.display());

    Ok(())
}

