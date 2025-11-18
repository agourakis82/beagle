//! Exemplo de uso do Adversarial Self-Play Engine
//!
//! Demonstra o loop de evolução: HERMES gera → ARGOS ataca → HERMES refina

use beagle_hermes::{
    adversarial::AdversarialSelfPlayEngine,
    agents::{HermesAgent, ArgosAgent, Draft},
    synthesis::VoiceProfile,
};
use std::sync::Arc;

#[tokio::main]
async fn main() -> anyhow::Result<()> {
    tracing_subscriber::fmt::init();

    println!("🔬 ADVERSARIAL SELF-PLAY ENGINE - WEEK 2\n");

    // 1. Inicializar agents
    println!("📦 Inicializando agents...");
    let voice_profile = VoiceProfile::default();
    let hermes = Arc::new(HermesAgent::new(voice_profile).await?);
    let argos = Arc::new(ArgosAgent::new().await?);

    // 2. Criar engine adversarial
    let adversarial = AdversarialSelfPlayEngine::new(hermes.clone(), argos.clone()).await?;

    // 3. Draft inicial (simulado - em produção viria do HERMES)
    let initial_draft = Draft {
        content: r#"
# Introduction

Scaffolds biomateriais são fundamentais para engenharia de tecidos. Eles fornecem suporte estrutural para células.

A literatura mostra que scaffolds podem ser feitos de vários materiais. Alguns estudos indicam que polímeros são bons.

Células precisam de um ambiente adequado para crescer. Scaffolds ajudam nisso.
"#
        .trim()
        .to_string(),
        word_count: 65,
        citations: vec!["1".to_string(), "2".to_string()],
    };

    println!("📝 Draft inicial: {} palavras\n", initial_draft.word_count);

    // 4. Papers de referência (simulado)
    let papers = vec![]; // Em produção viria da ATHENA

    // 5. Executar loop adversarial
    println!("🚀 Iniciando loop adversarial...\n");
    let evolved = adversarial.evolve_draft(initial_draft, &papers).await?;

    // 6. Resultados
    println!("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━");
    println!("✅ EVOLUÇÃO COMPLETA");
    println!("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━");
    println!("Iterações: {}", evolved.iterations);
    println!("Qualidade final: {:.1}%", evolved.final_quality * 100.0);
    println!("\nHistórico de evolução:");
    for metrics in &evolved.evolution_history {
        println!(
            "  Iteração {}: {:.1}% ({} issues)",
            metrics.iteration, metrics.quality_score * 100.0, metrics.issues_count
        );
    }
    println!("\nDraft final ({} palavras):", evolved.final_draft.word_count);
    println!("{}", evolved.final_draft.content);

    Ok(())
}

