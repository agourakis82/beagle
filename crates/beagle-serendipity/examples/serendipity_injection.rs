//! Exemplo de uso do Serendipity Engine
//!
//! Demonstra injeção de acidentes científicos férteis

use beagle_serendipity::SerendipityInjector;
use beagle_quantum::{HypothesisSet, Hypothesis};
use tracing_subscriber;

#[tokio::main]
async fn main() -> anyhow::Result<()> {
    tracing_subscriber::fmt()
        .with_env_filter("beagle_serendipity=info,info")
        .init();

    println!("🔬 SERENDIPITY ENGINE - WEEK 4\n");

    // 1. Criar injector
    let injector = SerendipityInjector::new();

    // 2. Simular estado quântico atual (hipóteses estabilizadas)
    let mut current_set = HypothesisSet::new();
    current_set.add(
        "Scaffolds biomateriais seguem princípios de termodinâmica reversível".to_string(),
        Some((0.8, 0.1)),
    );
    current_set.add(
        "Estrutura fractal emerge de processos de auto-organização".to_string(),
        Some((0.6, 0.1)),
    );
    current_set.add(
        "Propriedades mecânicas dependem de densidade de cross-linking".to_string(),
        Some((0.7, 0.1)),
    );

    println!("📊 Estado quântico atual: {} hipóteses estabilizadas", current_set.hypotheses.len());
    for (i, hyp) in current_set.hypotheses.iter().enumerate() {
        println!("  {}. [{:.1}%] {}", i + 1, hyp.confidence * 100.0,
                 &hyp.content[..hyp.content.len().min(60)]);
    }
    println!();

    // 3. Contexto de pesquisa
    let research_context = "Como explicar a curvatura da entropia em scaffolds biológicos? \
                           Estamos investigando propriedades termodinâmicas de materiais \
                           biomiméticos com estrutura fractal.";

    println!("🔬 Contexto de pesquisa:");
    println!("   {}\n", research_context);

    // 4. Injetar serendipidade
    println!("🚀 Injetando acidentes férteis...\n");
    let accidents = injector
        .inject_fertile_accident(&current_set, research_context)
        .await?;

    // 5. Resultados
    if accidents.is_empty() {
        println!("⚠️  Nenhum acidente fértil gerado (pode ser rejeitado pelo metacog)");
    } else {
        println!("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━");
        println!("✅ ACIDENTES FÉRTEIS GERADOS: {}", accidents.len());
        println!("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━");
        for (i, accident) in accidents.iter().enumerate() {
            println!("\n{}. {}", i + 1, accident);
        }
        println!("\n━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━");
    }

    println!("\n🎯 Serendipity Engine completo!");
    Ok(())
}

