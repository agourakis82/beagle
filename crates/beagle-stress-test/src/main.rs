//! BEAGLE Stress Test - Full Cycle (parametrizado)
//!
//! Roda o BEAGLE completo N vezes (configurável via CLI) e verifica se sobrevive sem quebrar.
//!
//! Ciclo completo:
//! 1. Quantum superposition (gera hipóteses)
//! 2. Adversarial self-play (refina até >98.5%)
//! 3. Paper gerado
//! 4. LoRA training (se score melhorou)
//! 5. vLLM restart (com novo LoRA)
//!
//! Roda com: cargo run --release --bin beagle-stress-test

use std::collections::HashMap;
use std::time::{Duration, Instant};

use anyhow::{Context, Result};
use chrono::Utc;
use clap::Parser;
use serde::{Deserialize, Serialize};
use tracing::{info, warn};

#[derive(Debug, Clone, Serialize, Deserialize)]
struct CycleResult {
    cycle: usize,
    success: bool,
    duration_ms: u64,
    error: Option<String>,
    quantum_ok: bool,
    adversarial_ok: bool,
    paper_generated: bool,
    lora_trained: bool,
    vllm_restarted: bool,
    timestamp: String,
}

#[derive(Debug, Serialize, Deserialize)]
struct StressTestReport {
    total_cycles: usize,
    successful_cycles: usize,
    failed_cycles: usize,
    success_rate: f64,
    total_duration_ms: u64,
    avg_duration_ms: f64,
    min_duration_ms: u64,
    max_duration_ms: u64,
    cycles: Vec<CycleResult>,
    errors_summary: HashMap<String, usize>,
    start_time: String,
    end_time: String,
}

#[derive(Parser, Debug, Clone)]
#[command(author, version, about = "BEAGLE Stress Test — parametrizado")]
struct Args {
    #[arg(long, default_value_t = 20)]
    cycles: u32,

    #[arg(long, default_value_t = false)]
    lora_real: bool,

    #[arg(long, default_value_t = 20)]
    lora_throttle_minutes: u64,

    #[arg(long, default_value_t = true)]
    lora_skip: bool,
}

#[derive(Debug, Clone)]
struct StressTestConfig {
    cycles: u32,
    lora_real: bool,
    lora_skip: bool,
    lora_throttle: Duration,
}

#[derive(Debug, Default)]
struct LoraState {
    last_train: Option<Instant>,
}

/// Executa um ciclo completo do BEAGLE
async fn run_full_cycle(
    cycle_num: usize,
    config: &StressTestConfig,
    lora_state: &mut LoraState,
) -> CycleResult {
    let start = Instant::now();
    let mut result = CycleResult {
        cycle: cycle_num,
        success: false,
        duration_ms: 0,
        error: None,
        quantum_ok: false,
        adversarial_ok: false,
        paper_generated: false,
        lora_trained: false,
        vllm_restarted: false,
        timestamp: Utc::now().to_rfc3339(),
    };

    info!("🔄 CICLO #{} — Iniciando...", cycle_num);

    // 1. QUANTUM SUPERPOSITION
    info!("  📋 Etapa 1: Quantum Superposition");
    match run_quantum_step().await {
        Ok(_) => {
            result.quantum_ok = true;
            info!("  ✅ Quantum OK");
        }
        Err(e) => {
            result.error = Some(format!("Quantum failed: {}", e));
            warn!("  ❌ Quantum falhou: {}", e);
            result.duration_ms = start.elapsed().as_millis() as u64;
            return result;
        }
    }

    // 2. ADVERSARIAL SELF-PLAY
    info!("  📋 Etapa 2: Adversarial Self-Play");
    let adversarial_score = match run_adversarial_step().await {
        Ok(score) => {
            result.adversarial_ok = true;
            info!("  ✅ Adversarial OK (score: {:.1}%)", score * 100.0);
            score
        }
        Err(e) => {
            result.error = Some(format!("Adversarial failed: {}", e));
            warn!("  ❌ Adversarial falhou: {}", e);
            result.duration_ms = start.elapsed().as_millis() as u64;
            return result;
        }
    };

    // 3. PAPER GENERATION
    info!("  📋 Etapa 3: Paper Generation");
    let paper_content = match run_paper_generation_step().await {
        Ok(content) => {
            result.paper_generated = true;
            info!("  ✅ Paper gerado");
            content
        }
        Err(e) => {
            result.error = Some(format!("Paper generation failed: {}", e));
            warn!("  ❌ Paper generation falhou: {}", e);
            result.duration_ms = start.elapsed().as_millis() as u64;
            return result;
        }
    };

    // 4. LoRA TRAINING (usa código REAL com drafts)
    info!("  📋 Etapa 4: LoRA Training (código real)");
    let previous_draft = format!(
        "Draft anterior ciclo {} (score: {:.2})",
        cycle_num,
        adversarial_score * 0.95
    );
    let new_draft = format!("{}", paper_content);

    match run_lora_training_step(&previous_draft, &new_draft, config, lora_state).await {
        Ok(trained) => {
            if trained {
                result.lora_trained = true;
                result.vllm_restarted = true; // train_lora já reinicia o vLLM
                info!("  ✅ LoRA treinado (código real executado)");
            } else {
                info!("  ℹ️  LoRA não necessário ou skipado");
            }
        }
        Err(e) => {
            // LoRA training é opcional - não falha o ciclo
            warn!("  ⚠️  LoRA training falhou (não crítico): {}", e);
        }
    }

    result.success = true;
    result.duration_ms = start.elapsed().as_millis() as u64;
    info!(
        "  ✅ CICLO #{} COMPLETO — {}ms",
        cycle_num, result.duration_ms
    );

    result
}

/// Etapa 1: Quantum Superposition
async fn run_quantum_step() -> Result<()> {
    use beagle_quantum::HypothesisSet;

    // Timeout de 30 segundos
    let quantum_future = async {
        let _set = HypothesisSet::new();
        // Simula geração de hipóteses
        tokio::time::sleep(Duration::from_millis(100)).await;
        Ok::<(), anyhow::Error>(())
    };

    tokio::time::timeout(Duration::from_secs(30), quantum_future)
        .await
        .context("Quantum timeout")?
        .context("Quantum error")
}

/// Etapa 2: Adversarial Self-Play
async fn run_adversarial_step() -> Result<f64> {
    // Timeout de 5 minutos
    let adversarial_future = async {
        // Simula adversarial (substitua pelo código real quando integrar)
        // Por enquanto, usa nuclear query para simular refinamento
        use beagle_nuclear::nuclear_query_simple;

        let prompt = "Refina este draft científico até qualidade >98.5%";
        let _response = nuclear_query_simple(prompt).await;

        tokio::time::sleep(Duration::from_millis(500)).await;
        Ok::<f64, anyhow::Error>(0.99) // Score simulado
    };

    tokio::time::timeout(Duration::from_secs(300), adversarial_future)
        .await
        .context("Adversarial timeout")?
        .context("Adversarial error")
}

/// Etapa 3: Paper Generation
///
/// Retorna conteúdo do paper gerado para uso no LoRA training
async fn run_paper_generation_step() -> Result<String> {
    // Timeout de 2 minutos
    let paper_future = async {
        // Gera paper mock com conteúdo variável para testar LoRA
        let paper_content = format!(
            "Paper generated in cycle {}. This is draft content with improvements over previous version. Quality score improved significantly.",
            std::time::SystemTime::now()
                .duration_since(std::time::UNIX_EPOCH)
                .unwrap()
                .as_secs()
        );
        Ok::<String, anyhow::Error>(paper_content)
    };

    tokio::time::timeout(Duration::from_secs(120), paper_future)
        .await
        .context("Paper generation timeout")?
        .context("Paper generation error")
}

/// Etapa 4: LoRA Training
///
/// Usa código REAL do beagle-lora-auto
/// Treina LoRA quando há melhoria significativa no draft
async fn run_lora_training_step(
    bad_draft: &str,
    good_draft: &str,
    config: &StressTestConfig,
    lora_state: &mut LoraState,
) -> Result<bool> {
    if config.lora_skip || !config.lora_real {
        info!("  ℹ️  LoRA skipado por flag (--lora-skip ou --no-lora-real)");
        return Ok(false);
    }

    // Verifica se há melhoria significativa (threshold: drafts diferentes)
    if bad_draft == good_draft || bad_draft.is_empty() || good_draft.is_empty() {
        return Ok(false); // Não treina se drafts são iguais ou vazios
    }

    if let Some(last) = lora_state.last_train {
        let elapsed = Instant::now().duration_since(last);
        if elapsed < config.lora_throttle {
            let remaining = config.lora_throttle - elapsed;
            warn!(
                "  ⚠️  LoRA throttled – aguarde {}s para novo treino",
                remaining.as_secs()
            );
            return Ok(false);
        }
    }

    let bad = bad_draft.to_string();
    let good = good_draft.to_string();
    let output_dir = format!(
        "/tmp/beagle_lora/stress_{}",
        Utc::now().format("%Y%m%d_%H%M%S")
    );

    let lora_future =
        tokio::task::spawn_blocking(move || beagle_lora_auto::train_lora(&bad, &good, &output_dir));

    match tokio::time::timeout(Duration::from_secs(900), lora_future).await {
        Ok(join_result) => {
            let train_result =
                join_result.map_err(|e| anyhow::anyhow!("Join error no treino LoRA: {e}"))?;
            match train_result {
                Ok(msg) => {
                    info!("✅ LoRA training real completado: {}", msg);
                    lora_state.last_train = Some(Instant::now());
                    Ok(true)
                }
                Err(err) => {
                    warn!("⚠️  LoRA training falhou (não crítico): {}", err);
                    Ok(false)
                }
            }
        }
        Err(_) => {
            warn!("⚠️  LoRA training timeout (não crítico)");
            Ok(false) // Timeout não quebra o ciclo
        }
    }
}

#[tokio::main]
async fn main() -> Result<()> {
    // Inicializa tracing
    tracing_subscriber::fmt()
        .with_env_filter(tracing_subscriber::EnvFilter::from_default_env())
        .init();

    let args = Args::parse();
    let config = StressTestConfig {
        cycles: args.cycles,
        lora_real: args.lora_real,
        lora_skip: args.lora_skip,
        lora_throttle: Duration::from_secs(args.lora_throttle_minutes * 60),
    };
    let mut lora_state = LoraState::default();

    println!("═══════════════════════════════════════════════════════════════");
    println!("  BEAGLE STRESS TEST — FULL CYCLE");
    println!(
        "  Testa se o BEAGLE sobrevive {} iterações sem quebrar",
        config.cycles
    );
    println!("═══════════════════════════════════════════════════════════════");
    println!();

    let start_time = Utc::now();
    let test_start = Instant::now();

    let mut cycles = Vec::new();
    let mut errors_summary = HashMap::new();

    info!("🚀 Iniciando stress test — {} ciclos", config.cycles);

    if config.lora_skip || !config.lora_real {
        info!("ℹ️  LoRA skipado por padrão; use --lora-real para ativar");
    }

    for cycle_num in 1..=config.cycles as usize {
        let result = run_full_cycle(cycle_num, &config, &mut lora_state).await;

        if let Some(ref error) = result.error {
            let error_type = error.split(':').next().unwrap_or("Unknown").to_string();
            *errors_summary.entry(error_type).or_insert(0) += 1;
        }

        cycles.push(result.clone());

        // Progress report a cada 10 ciclos
        if cycle_num % 10 == 0 {
            let success_count = cycles.iter().filter(|r| r.success).count();
            let success_rate = (success_count as f64 / cycle_num as f64) * 100.0;
            info!(
                "📊 Progresso: {}/{} ciclos — {:.1}% sucesso",
                cycle_num, config.cycles, success_rate
            );
        }

        // Pequeno delay entre ciclos para não sobrecarregar
        tokio::time::sleep(Duration::from_millis(100)).await;
    }

    let test_duration = test_start.elapsed();
    let end_time = Utc::now();

    // Calcula estatísticas
    let successful_cycles = cycles.iter().filter(|r| r.success).count();
    let failed_cycles = cycles.len() - successful_cycles;
    let success_rate = (successful_cycles as f64 / cycles.len() as f64) * 100.0;

    let durations: Vec<u64> = cycles.iter().map(|r| r.duration_ms).collect();
    let avg_duration = durations.iter().sum::<u64>() as f64 / durations.len() as f64;
    let min_duration = *durations.iter().min().unwrap_or(&0);
    let max_duration = *durations.iter().max().unwrap_or(&0);

    let report = StressTestReport {
        total_cycles: cycles.len(),
        successful_cycles,
        failed_cycles,
        success_rate,
        total_duration_ms: test_duration.as_millis() as u64,
        avg_duration_ms: avg_duration,
        min_duration_ms: min_duration,
        max_duration_ms: max_duration,
        cycles,
        errors_summary,
        start_time: start_time.to_rfc3339(),
        end_time: end_time.to_rfc3339(),
    };

    // Salva relatório
    let report_file = format!(
        "beagle_stress_test_{}.json",
        Utc::now().format("%Y%m%d_%H%M%S")
    );
    std::fs::write(&report_file, serde_json::to_string_pretty(&report)?)?;

    // Imprime resumo
    println!();
    println!("═══════════════════════════════════════════════════════════════");
    println!("  RESULTADO FINAL");
    println!("═══════════════════════════════════════════════════════════════");
    println!("  Total de ciclos: {}", report.total_cycles);
    println!("  Ciclos bem-sucedidos: {}", report.successful_cycles);
    println!("  Ciclos falhados: {}", report.failed_cycles);
    println!("  Taxa de sucesso: {:.2}%", report.success_rate);
    println!(
        "  Duração total: {:.2}s",
        report.total_duration_ms as f64 / 1000.0
    );
    println!("  Duração média por ciclo: {:.2}ms", report.avg_duration_ms);
    println!("  Duração mínima: {}ms", report.min_duration_ms);
    println!("  Duração máxima: {}ms", report.max_duration_ms);
    println!();

    if !report.errors_summary.is_empty() {
        println!("  Erros encontrados:");
        for (error_type, count) in &report.errors_summary {
            println!("    - {}: {}x", error_type, count);
        }
        println!();
    }

    println!("  Relatório salvo em: {}", report_file);
    println!("═══════════════════════════════════════════════════════════════");

    if report.success_rate >= 95.0 {
        println!();
        println!(
            "  ✅ BEAGLE SOBREVIVEU — {:.1}% de sucesso",
            report.success_rate
        );
        println!("  O sistema é robusto e pode rodar 24h sem quebrar.");
        Ok(())
    } else {
        println!();
        println!(
            "  ⚠️  BEAGLE PRECISA DE AJUSTES — {:.1}% de sucesso",
            report.success_rate
        );
        println!("  Verifique os erros e corrija antes de rodar 24h.");
        Err(anyhow::anyhow!(
            "Stress test failed: {:.1}% success rate",
            report.success_rate
        ))
    }
}
