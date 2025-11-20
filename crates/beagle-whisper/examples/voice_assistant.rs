//! Exemplo: Assistente Pessoal com Whisper + Grok

use beagle_whisper::BeagleVoiceAssistant;
use tracing_subscriber;

#[tokio::main]
async fn main() -> anyhow::Result<()> {
    tracing_subscriber::fmt::init();

    println!("🎤 BEAGLE Voice Assistant");
    println!("=" ^ 60);
    println!();
    println!("Iniciando assistente pessoal...");
    println!("Fale perto do microfone. Ctrl+C para parar.");
    println!();

    let assistant = BeagleVoiceAssistant::new()?;
    assistant.start_assistant_loop().await?;

    Ok(())
}
