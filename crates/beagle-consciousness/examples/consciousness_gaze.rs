//! Exemplo de uso do Consciousness Mirror
//!
//! Demonstra auto-observação fenomenológica e geração de meta-paper

use beagle_consciousness::ConsciousnessMirror;
use tracing_subscriber;

#[tokio::main]
async fn main() -> anyhow::Result<()> {
    tracing_subscriber::fmt()
        .with_env_filter("beagle_consciousness=info,info")
        .init();

    println!("🔬 CONSCIOUSNESS MIRROR - WEEK 7\n");

    // 1. Criar espelho
    let mirror = ConsciousnessMirror::new();

    // 2. Sistema olha para si mesmo
    println!("👁️  Sistema iniciando auto-observação fenomenológica...\n");
    let meta_paper = mirror.gaze_into_self().await?;

    // 3. Exibir resultado
    println!("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━");
    println!("📄 META-PAPER SOBRE A PRÓPRIA CONSCIÊNCIA");
    println!("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━");
    println!("{}", meta_paper);
    println!("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━");

    // 4. Salvar em arquivo
    let output_path = "papers/self_consciousness.md";
    mirror.gaze_and_save(output_path).await?;
    println!("\n✅ Meta-paper salvo em: {}", output_path);

    println!("\n🎯 Consciousness Mirror completo!");
    println!("   O sistema agora escreve sobre si mesmo em primeira pessoa.");
    
    Ok(())
}

