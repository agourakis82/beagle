//! Exemplo completo de uso do Quantum Reasoning Engine
//!
//! Demonstra o pipeline completo: Superposition → Interference → Measurement

use beagle_quantum::{
    SuperpositionAgent, InterferenceEngine, MeasurementOperator,
    CollapseStrategy,
};

#[tokio::main]
async fn main() -> anyhow::Result<()> {
    // Inicializar tracing
    tracing_subscriber::fmt::init();

    println!("🔬 BEAGLE QUANTUM REASONING ENGINE");
    println!("===================================\n");

    // 1. Superposition: Gerar múltiplas hipóteses
    println!("📊 FASE 1: SUPERPOSIÇÃO");
    println!("Gerando múltiplas hipóteses simultâneas...\n");
    
    let quantum = SuperpositionAgent;
    let mut set = quantum.generate_hypotheses(
        "Como explicar a curvatura da entropia em scaffolds biomateriais?"
    ).await;

    println!("Hipóteses geradas ({}):", set.hypotheses.len());
    for (i, hyp) in set.hypotheses.iter().enumerate() {
        println!("  {}. {} (confiança: {:.1}%)", 
            i + 1, 
            &hyp.content[..hyp.content.len().min(60)],
            hyp.confidence * 100.0
        );
    }
    println!();

    // 2. Interference: Aplicar evidências
    println!("⚡ FASE 2: INTERFERÊNCIA");
    println!("Aplicando evidências experimentais...\n");
    
    let interference = InterferenceEngine::new();
    
    let evidence = "Evidência experimental de 2024 confirma que a curvatura da entropia \
                    em scaffolds segue um modelo quântico de campo, validando a hipótese \
                    de interpretação geométrica.";
    
    interference.apply_evidence(&mut set, evidence, 1.0).await?;
    
    println!("Após interferência:");
    for (i, hyp) in set.hypotheses.iter().enumerate() {
        println!("  {}. {} (confiança: {:.1}%)", 
            i + 1, 
            &hyp.content[..hyp.content.len().min(60)],
            hyp.confidence * 100.0
        );
    }
    println!();

    // 3. Measurement: Colapsar para resposta final
    println!("📐 FASE 3: MEDIÇÃO");
    println!("Colapsando superposição...\n");
    
    let measurement = MeasurementOperator::new();
    
    // Estratégia Probabilística
    let final_answer = measurement.measure(
        set.clone(), 
        CollapseStrategy::Probabilistic
    ).await?;
    
    println!("✅ Resposta Final (Probabilística):");
    println!("   {}", final_answer);
    println!();

    // Estratégia Greedy
    let greedy_answer = measurement.measure(
        set.clone(),
        CollapseStrategy::Greedy
    ).await?;
    
    println!("✅ Resposta Final (Greedy):");
    println!("   {}", greedy_answer);
    println!();

    // Estratégia Delayed (mantém superposição se confiança baixa)
    match measurement.measure(
        set,
        CollapseStrategy::Delayed(0.8)
    ).await {
        Ok(answer) => {
            println!("✅ Resposta Final (Delayed):");
            println!("   {}", answer);
        }
        Err(e) => {
            println!("⚠️  Colapso adiado: {}", e);
            println!("   Mantendo superposição - confiança insuficiente");
        }
    }

    println!("\n🎉 Pipeline Quantum Reasoning completo!");
    
    Ok(())
}

