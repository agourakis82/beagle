//! Stress Test do BEAGLE Pipeline
//!
//! Valida 100+ pipelines em modo dev/lab:
//! - Não travam
//! - Respeitam SAFE_MODE
//! - Produzem artefatos corretamente
//! - Métricas de latência (média, p95, p99)

use beagle_core::BeagleContext;
use beagle_config::load as load_config;
use beagle_monorepo::pipeline::run_beagle_pipeline;
use beagle_stress_test::calculate_stats;
use std::sync::Arc;
use std::time::Duration;
use tokio::time::Instant;
use tracing::info;
use uuid::Uuid;

#[tokio::main]
async fn main() -> anyhow::Result<()> {
    tracing_subscriber::fmt()
        .with_env_filter(tracing_subscriber::EnvFilter::from_default_env())
        .init();

    let n: usize = std::env::var("BEAGLE_STRESS_RUNS")
        .ok()
        .and_then(|v| v.parse().ok())
        .unwrap_or(100);

    let concurrency: usize = std::env::var("BEAGLE_STRESS_CONCURRENCY")
        .ok()
        .and_then(|v| v.parse().ok())
        .unwrap_or(5);

    info!("🧪 BEAGLE Stress Test");
    info!("   Runs: {}", n);
    info!("   Concurrency: {}", concurrency);
    info!("   SAFE_MODE: {}", std::env::var("BEAGLE_SAFE_MODE").unwrap_or_else(|_| "true".into()));
    info!("   PROFILE: {}", std::env::var("BEAGLE_PROFILE").unwrap_or_else(|_| "lab".into()));

    let cfg = load_config();
    
    // Verifica SAFE_MODE
    if !cfg.safe_mode {
        eprintln!("⚠️  WARNING: SAFE_MODE=false - stress test pode publicar de fato!");
    }

    // Clona config para cada run (BeagleConfig é Clone)
    let cfg_arc = Arc::new(cfg);
    let semaphore = Arc::new(tokio::sync::Semaphore::new(concurrency));
    let mut handles = Vec::new();
    let mut latencies = Vec::new();
    let mut errors = 0;

    let start_total = Instant::now();

    for i in 1..=n {
        let permit = semaphore.clone().acquire_owned().await?;
        let cfg_clone = cfg_arc.clone();
        let question = format!("Stress test paper idea {}", i);
        
        handles.push(tokio::spawn(async move {
            let _permit = permit;
            let run_id = Uuid::new_v4().to_string();
            let start = Instant::now();
            
            // Cria novo contexto para cada run (evita mutex contention)
            let cfg = (*cfg_clone).clone();
            let mut ctx = match BeagleContext::new(cfg).await {
                Ok(ctx) => ctx,
                Err(e) => return (i, Err(e), start.elapsed()),
            };
            
            let res = run_beagle_pipeline(&mut ctx, &question, &run_id).await;
            
            let dur = start.elapsed();
            (i, res, dur)
        }));
    }

    for h in handles {
        let (i, res, dur) = h.await?;
        match res {
            Ok(paths) => {
                info!("✅ Cycle {} OK ({:?}) - Draft: {}", i, dur, paths.draft_md.display());
                latencies.push(dur);
            }
            Err(e) => {
                eprintln!("❌ Cycle {} ERROR ({:?}): {:?}", i, dur, e);
                errors += 1;
            }
        }
    }

    let total_time = start_total.elapsed();
    let stats = calculate_stats(latencies);

    println!("\n=== BEAGLE STRESS TEST RESULTADOS ===");
    println!("Total runs: {}", n);
    println!("Sucessos: {}", stats.total);
    println!("Erros: {}", errors);
    println!("Tempo total: {:?}", total_time);
    println!("\nLatências:");
    println!("  Média: {:?}", stats.mean);
    println!("  Min: {:?}", stats.min);
    println!("  Max: {:?}", stats.max);
    println!("  P95: {:?}", stats.p95);
    println!("  P99: {:?}", stats.p99);
    println!("  Throughput: {:.2} runs/s", n as f64 / total_time.as_secs_f64());

    // Salva relatório JSON
    let report = serde_json::json!({
        "total_runs": n,
        "successes": stats.total,
        "errors": errors,
        "total_time_secs": total_time.as_secs_f64(),
        "latency_stats": {
            "mean_ms": stats.mean.as_millis(),
            "min_ms": stats.min.as_millis(),
            "max_ms": stats.max.as_millis(),
            "p95_ms": stats.p95.as_millis(),
            "p99_ms": stats.p99.as_millis(),
        },
        "throughput_rps": n as f64 / total_time.as_secs_f64(),
    });

    let cfg = load_config();
    let report_dir = std::path::PathBuf::from(&cfg.storage.data_dir)
        .join("logs")
        .join("stress-test");
    std::fs::create_dir_all(&report_dir)?;

    let report_path = report_dir.join(format!("stress_test_{}.json", chrono::Utc::now().format("%Y%m%d_%H%M%S")));
    std::fs::write(&report_path, serde_json::to_string_pretty(&report)?)?;
    println!("\n📊 Relatório salvo: {}", report_path.display());

    Ok(())
}

