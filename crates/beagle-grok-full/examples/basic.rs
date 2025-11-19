//! Exemplo básico de uso do GrokFull

use beagle_grok_full::GrokFull;
use tracing_subscriber;

#[tokio::main]
async fn main() {
    // Inicializar tracing
    tracing_subscriber::fmt::init();

    println!("=== BEAGLE Grok Full - Exemplo Básico ===\n");

    // Exemplo 1: Grok 3 (default)
    println!("1. Testando Grok 3 (default)...");
    let response = GrokFull::instance().await
        .grok3("Explique em uma frase o que é RDMA (Remote Direct Memory Access).")
        .await;
    
    println!("Resposta: {}\n", response);

    // Exemplo 2: Grok 4 Heavy (quando precisar)
    println!("2. Testando Grok 4 Heavy...");
    let heavy_response = GrokFull::instance().await
        .grok4_heavy("Analise a relação entre entropia, consciência celular e heliobiology em um contexto científico interdisciplinar.")
        .await;
    
    println!("Resposta: {}\n", heavy_response);

    println!("=== Teste concluído ===");
}

