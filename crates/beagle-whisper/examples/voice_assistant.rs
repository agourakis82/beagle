//! Exemplo: Assistente Pessoal com Whisper + Grok

use beagle_whisper::BeagleVoiceAssistant;
use tracing_subscriber;

#[tokio::main]
async fn main() -> anyhow::Result<()> {
    tracing_subscriber::fmt::init();

    println!("🎤 BEAGLE Voice Assistant");
    println!("{}", "=".repeat(60));
    println!();
    println!("Iniciando assistente pessoal...");
    println!("Fale perto do microfone. Ctrl+C para parar.");
    println!();

    let assistant = BeagleVoiceAssistant::new()?;

    // Usa smart router (TieredRouter) para escolher Grok 3 ou 4 Heavy
    assistant.start_with_smart_router().await?;

    Ok(())
}
