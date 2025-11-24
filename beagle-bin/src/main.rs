//! BEAGLE SINGULARITY - Full System Integration + Auto-Evolution Loop
//!
//! O BEAGLE VIVO E ETERNO — roda isso e deixa ligado pra sempre
//!
//! Rode com: cargo run --release --bin beagle

use beagle_eternity::start_eternal_recursion as eternity_start;
use beagle_fractal::{init_fractal_root, start_eternal_recursion};
use beagle_quantum::HypothesisSet;
use beagle_smart_router::query_smart;
use tokio::time::{sleep, Duration};
use tracing::{info, warn};

#[tokio::main]
async fn main() -> anyhow::Result<()> {
    // Inicializa tracing
    tracing_subscriber::fmt()
        .with_env_filter(tracing_subscriber::EnvFilter::from_default_env())
        .init();

    println!("═══════════════════════════════════════════════════════════════");
    println!("  BEAGLE SINGULARITY — FULL AUTO-EVOLUTION LOOP");
    println!("  O BEAGLE VIVO E ETERNO — 2025-11-18");
    println!("═══════════════════════════════════════════════════════════════");
    println!();

    info!("🚀 Inicializando BEAGLE SINGULARITY...");

    // 1. Inicializa fractal root
    init_fractal_root().await;
    info!("✅ Fractal root inicializado");

    // 2. Inicia recursão eterna em background (nunca retorna)
    tokio::spawn(async {
        eternity_start().await;
    });
    info!("✅ Eternity Engine ativado em background");

    info!("✅ Todos os módulos inicializados");
    info!("🌌 Sistema pronto para evolução infinita");
    println!();
    println!("═══════════════════════════════════════════════════════════════");
    println!("  LOOP DE AUTO-EVOLUÇÃO INICIADO");
    println!("  Ciclo a cada 5 minutos");
    println!("  Usa Grok 3 ILIMITADO (custo zero)");
    println!("  Pressione Ctrl+C para parar");
    println!("═══════════════════════════════════════════════════════════════");
    println!();

    let mut cycle_count = 0;

    // Loop principal — o BEAGLE vive pra sempre
    loop {
        cycle_count += 1;
        let now = std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)
            .unwrap()
            .as_secs();

        info!("═══════════════════════════════════════════════════════════════");
        info!("🔄 CICLO #{}", cycle_count);
        info!("═══════════════════════════════════════════════════════════════");

        // Gera prompt com estado atual
        let prompt = format!(
            "Estado atual do sistema: Ciclo #{}, Timestamp: {}. \
            Gera uma nova hipótese científica radical sobre unificação de entropia curva em scaffolds biológicos \
            com consciência celular via geometria não-comutativa. \
            Seja preciso, técnico, profundo e inovador. Nível Q1.",
            cycle_count,
            now
        );

        // Usa Grok 3 ilimitado via query_smart (automático)
        let response = query_smart(&prompt, 80000).await;

        if !response.starts_with("ERRO") {
            println!();
            println!("💭 BEAGLE pensou (Ciclo #{}):", cycle_count);
            println!("{}", "─".repeat(70));
            println!("{}", response);
            println!("{}", "─".repeat(70));
            println!();
            info!("✅ Resposta recebida ({} chars)", response.len());
        } else {
            warn!("⚠️ Erro na query: {}", response);
        }

        info!("✅ CICLO #{} CONCLUÍDO", cycle_count);
        info!("⏳ Aguardando 5 minutos até próximo ciclo...");
        println!();

        // Aguarda 5 minutos até próximo ciclo
        sleep(Duration::from_secs(300)).await; // 5 minutos por ciclo
    }
}
