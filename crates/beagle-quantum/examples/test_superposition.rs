//! Teste de Superposition com vLLM Real
//!
//! Uso: cargo run --package beagle-quantum --example test_superposition -- "sua query aqui"

use beagle_quantum::SuperpositionAgent;
use tracing_subscriber;

#[tokio::main]
async fn main() -> anyhow::Result<()> {
    // Inicializar tracing
    tracing_subscriber::fmt::init();

    let query = std::env::args()
        .nth(1)
        .unwrap_or_else(|| "Como unificar gravidade quântica com termodinâmica em scaffolds biológicos?".to_string());

    println!("🔬 BEAGLE QUANTUM - Teste de Superposition com vLLM Real");
    println!("==========================================================\n");
    println!("Query: {}\n", query);

    let agent = SuperpositionAgent::new();
    
    println!("📡 Conectando ao vLLM (http://t560.local:8000/v1)...");
    println!("⏳ Gerando 6 hipóteses com diversidade máxima...\n");

    match agent.generate_hypotheses(&query).await {
        Ok(set) => {
            println!("✅ {} hipóteses geradas em superposição:\n", set.hypotheses.len());
            
            for (i, hyp) in set.hypotheses.iter().enumerate() {
                println!("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━");
                println!("HIPÓTESE {} (confiança: {:.1}%)", i + 1, hyp.confidence * 100.0);
                println!("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━");
                println!("{}\n", hyp.content);
            }
            
            println!("🎉 Superposição quântica completa!");
            println!("   Total: {} hipóteses simultâneas", set.hypotheses.len());
            println!("   Melhor: {} ({:.1}% confiança)", 
                &set.best().content[..set.best().content.len().min(60)],
                set.best().confidence * 100.0
            );
        }
        Err(e) => {
            eprintln!("❌ Erro ao gerar hipóteses: {}", e);
            eprintln!("\nPossíveis causas:");
            eprintln!("  - vLLM server não está rodando em http://t560.local:8000");
            eprintln!("  - Problema de conectividade de rede");
            eprintln!("  - Modelo não disponível no servidor");
            std::process::exit(1);
        }
    }

    Ok(())
}

