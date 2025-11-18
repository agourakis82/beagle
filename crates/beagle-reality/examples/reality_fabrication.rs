//! Example: Reality Fabrication Layer
//!
//! Demonstra a geração completa de protocolos experimentais, simulação adversarial
//! e síntese de biomateriais com validação ética.

use beagle_reality::{ProtocolGenerator, AdversarialSimulator, BiomaterialSynthesizer, MaterialType};
use std::path::PathBuf;
use tracing::{info, Level};
use tracing_subscriber;

#[tokio::main]
async fn main() -> anyhow::Result<()> {
    tracing_subscriber::fmt()
        .with_max_level(Level::INFO)
        .init();

    info!("🔬 REALITY FABRICATION LAYER: Exemplo completo");

    // 1. Geração de protocolo experimental
    info!("📋 FASE 1: Geração de protocolo experimental");
    let protocol_gen = ProtocolGenerator::new();
    
    let hypothesis = "Scaffolds entrópicos com estrutura fractal auto-similar podem induzir regeneração neural acelerada em lesões medulares";
    let constraints = "Orçamento < R$10k, sem uso de animais, aprovação IRB necessária";
    
    let protocol = protocol_gen.generate_protocol(hypothesis, constraints).await?;
    info!("✅ Protocolo gerado: {} palavras", protocol.word_count);

    // Salva protocolo
    let output_dir = PathBuf::from("./experiments");
    let protocol_path = protocol_gen.save_protocol(&protocol, &output_dir).await?;
    info!("💾 Protocolo salvo em: {:?}", protocol_path);

    // 2. Simulação adversarial
    info!("🌍 FASE 2: Simulação adversarial de resultados");
    let simulator = AdversarialSimulator::new();
    let simulation = simulator.simulate_adversarial(&protocol).await?;
    
    info!(
        "✅ Simulação completa: Probabilidade de sucesso {:.1}%, Viabilidade física {:.1}%",
        simulation.success_probability * 100.0,
        simulation.physical_viability_score * 100.0
    );
    
    info!("⚠️  Modos de falha identificados: {}", simulation.failure_modes.len());
    for (i, failure) in simulation.failure_modes.iter().enumerate() {
        info!(
            "  {}. {} (prob: {:.1}%, severidade: {:?})",
            i + 1,
            failure.description,
            failure.probability * 100.0,
            failure.severity
        );
    }

    // 3. Síntese de biomaterial
    info!("🧬 FASE 3: Síntese de biomaterial com validação ética");
    let synthesizer = BiomaterialSynthesizer::new();
    let biomaterial = synthesizer
        .synthesize_biomaterial(&protocol, MaterialType::ScaffoldEntropic)
        .await?;
    
    info!("✅ Biomaterial especificado: {}", biomaterial.name);
    info!(
        "  - Resistência: {:.1} MPa",
        biomaterial.properties.mechanical_strength
    );
    info!(
        "  - Biocompatibilidade: {:.1}%",
        biomaterial.properties.biocompatibility_score * 100.0
    );
    info!(
        "  - Aprovação ética: {}",
        if biomaterial.ethical_approval.approved { "SIM" } else { "NÃO" }
    );

    info!("🎯 REALITY FABRICATION COMPLETA: Protocolo pronto para execução física");

    Ok(())
}

