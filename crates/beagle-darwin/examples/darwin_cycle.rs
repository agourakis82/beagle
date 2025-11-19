//! Exemplo de uso do Darwin Enhanced Cycle
//!
//! Demonstra como usar o darwin-core integrado no BEAGLE:
//! - GraphRAG com hypergraph + neo4j + qdrant
//! - Self-RAG com gatekeeping automático
//! - Plugin system para trocar LLM em runtime
//!
//! Roda com:
//! ```bash
//! cargo run --example darwin_cycle --package beagle-darwin
//! ```

use beagle_darwin::{darwin_enhanced_cycle, DarwinCore};
use tracing_subscriber;

#[tokio::main]
async fn main() -> anyhow::Result<()> {
    // Configurar logging
    tracing_subscriber::fmt()
        .with_max_level(tracing::Level::INFO)
        .init();

    println!("🚀 BEAGLE + DARWIN - Ciclo Enhanced");
    println!("{}", "=".repeat(50));
    println!();

    // Exemplo 1: Ciclo completo Darwin-enhanced
    let question = "unificar entropia curva com consciência celular";
    println!("📋 Pergunta: {}", question);
    println!();

    let answer = darwin_enhanced_cycle(question).await;
    println!("✅ Resposta:");
    println!("{}", answer);
    println!();

    // Exemplo 2: Plugin system
    println!("🔌 Testando Plugin System:");
    let darwin = DarwinCore::new();
    
    let plugins = vec!["grok3", "local70b", "heavy"];
    for plugin in plugins {
        println!("  Plugin: {}", plugin);
        let result = darwin.run_with_plugin("Explique quantum entanglement em uma frase.", plugin).await;
        println!("  Resposta (truncada): {}...", &result[..result.len().min(100)]);
        println!();
    }

    Ok(())
}

