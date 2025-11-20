use std::sync::Arc;
use tokio::time::{Duration, Instant};

use anyhow::Result;
use beagle_monorepo::pipeline::run_beagle_pipeline;
use beagle_core::BeagleContext;

#[tokio::main]
async fn main() -> Result<()> {
    let total: usize = std::env::var("BEAGLE_STRESS_RUNS")
        .ok()
        .and_then(|v| v.parse().ok())
        .unwrap_or(50);

    let concurrency: usize = std::env::var("BEAGLE_STRESS_CONCURRENCY")
        .ok()
        .and_then(|v| v.parse().ok())
        .unwrap_or(5);

    println!(
        "Iniciando stress test: {} runs, concurrency {}",
        total, concurrency
    );

    let cfg = beagle_config::load();
    let ctx = BeagleContext::new(cfg).await?;
    let ctx = Arc::new(tokio::sync::Mutex::new(ctx));
    let semaphore = Arc::new(tokio::sync::Semaphore::new(concurrency));

    let mut handles = Vec::with_capacity(total);
    let mut latencies = Vec::with_capacity(total);

    for i in 1..=total {
        let permit = semaphore.clone().acquire_owned().await?;
        let ctx_cloned = ctx.clone();

        let question = format!("Stress test pipeline {}", i);

        handles.push(tokio::spawn(async move {
            let _permit = permit;
            let start = Instant::now();
            let res = {
                let mut ctx_guard = ctx_cloned.lock().await;
                run_beagle_pipeline(&mut ctx_guard, &question, &format!("run-{}", i)).await
            };
            let dur = start.elapsed();
            (i, res, dur)
        }));
    }

    let mut success = 0usize;

    for h in handles {
        let (i, res, dur) = h.await?;
        match res {
            Ok(_) => {
                println!("Cycle {:04} OK ({:?})", i, dur);
                success += 1;
                latencies.push(dur);
            }
            Err(e) => {
                eprintln!("Cycle {:04} ERROR: {:?}", i, e);
            }
        }
    }

    println!("\n=== RESUMO STRESS TEST ===");
    println!("Total: {}", total);
    println!("Sucesso: {}", success);
    println!("Falha:  {}", total - success);

    if !latencies.is_empty() {
        latencies.sort();
        let p50 = latencies[latencies.len() / 2];
        let p95 = latencies[(latencies.len() as f32 * 0.95) as usize.min(latencies.len() - 1)];
        let p99 = latencies[(latencies.len() as f32 * 0.99) as usize.min(latencies.len() - 1)];
        println!("p50: {:?}", p50);
        println!("p95: {:?}", p95);
        println!("p99: {:?}", p99);
    }

    Ok(())
}
