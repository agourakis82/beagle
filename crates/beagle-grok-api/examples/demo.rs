//! Demo do Grok API Client
//!
//! Exemplo de uso do cliente xAI Grok 4 Heavy

use beagle_grok_api::GrokClient;
use tracing::Level;
use tracing_subscriber::fmt;

#[tokio::main]
async fn main() -> anyhow::Result<()> {
    fmt()
        .with_max_level(Level::INFO)
        .with_target(false)
        .with_thread_ids(false)
        .init();

    println!("🤖 BEAGLE GROK API - Demo\n");

    // Obtém API key do ambiente ou usa placeholder
    let api_key =
        std::env::var("XAI_API_KEY").unwrap_or_else(|_| "xai-YOUR_API_KEY_HERE".to_string());

    if api_key.contains("YOUR_API_KEY") {
        println!("⚠️  Configure XAI_API_KEY no ambiente ou edite o código");
        println!("   export XAI_API_KEY='xai-...'");
        return Ok(());
    }

    let client = GrokClient::new(&api_key);

    println!("📤 Enviando prompt para Grok-4-Heavy...\n");

    let prompt = "Escreve uma introdução científica sobre entropia curva em scaffolds biológicos e consciência celular via geometria não-comutativa. Seja técnico, direto, estilo Q1.";

    match client.query(prompt).await {
        Ok(response) => {
            println!("✅ Resposta recebida:\n");
            println!("{}", response);
        }
        Err(e) => {
            eprintln!("❌ Erro: {}", e);
        }
    }

    Ok(())
}
