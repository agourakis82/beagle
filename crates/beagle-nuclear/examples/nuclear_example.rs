//! Exemplo de uso do BEAGLE Nuclear Wrapper
//!
//! Roda com: cargo run --example nuclear_example --package beagle-nuclear

use beagle_nuclear::nuclear_query;

#[tokio::main]
async fn main() {
    tracing_subscriber::fmt::init();

    // Exemplo 1: Query simples (Grok 3)
    println!("🔬 Query simples (Grok 3)...");
    let answer = nuclear_query("Qual é a natureza da consciência?", 50000).await;
    println!("BEAGLE: {}\n", answer);

    // Exemplo 2: Query com contexto grande (Grok 4 Heavy)
    println!("🚀 Query com contexto grande (Grok 4 Heavy)...");
    let answer = nuclear_query("Analisa este paper completo...", 150000).await;
    println!("BEAGLE: {}\n", answer);
}
