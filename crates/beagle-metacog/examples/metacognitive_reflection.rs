//! Exemplo de uso do Metacognitive Reflection Layer
//!
//! Demonstra reflexão metacognitiva sobre um ciclo completo de pensamento

use beagle_metacog::MetacognitiveReflector;
use beagle_quantum::{HypothesisSet, Hypothesis};
use beagle_llm::validation::{CitationValidity, ValidationResult};
use tracing_subscriber;

#[tokio::main]
async fn main() -> anyhow::Result<()> {
    tracing_subscriber::fmt()
        .with_env_filter("beagle_metacog=info,info")
        .init();

    println!("🔬 METACOGNITIVE REFLECTION LAYER - WEEK 3\n");

    // 1. Criar reflector
    let reflector = MetacognitiveReflector::new();

    // 2. Simular thought trace (em produção viria do orchestrator)
    let thought_trace = r#"
Query: Como explicar a curvatura da entropia em scaffolds biológicos?

Superposition: Gerando 6 hipóteses...
Hipótese 1: Abordagem clássica newtoniana baseada em termodinâmica reversível.
Hipótese 2: Modelo quântico de campo com emaranhamento em escala nanométrica.
Hipótese 3: Interpretação geométrica via espaços curvos de informação.

Interference: Aplicando evidências experimentais...
Evidência 1: Microscopia confirma estrutura fractal.
Evidência 2: Dados de espectroscopia suportam modelo quântico.

Measurement: Colapsando para hipótese dominante...
Hipótese 2 selecionada (confiança 78%).

Adversarial Iteration 1: Quality 78.3%
Adversarial Iteration 2: Quality 89.7%
Adversarial Iteration 3: Quality 94.2%
"#;

    // 3. Simular quantum state
    let mut quantum_state = HypothesisSet::new();
    quantum_state.add("Hipótese clássica".to_string(), Some((0.3, 0.1)));
    quantum_state.add("Hipótese quântica".to_string(), Some((0.7, 0.1)));
    quantum_state.add("Hipótese geométrica".to_string(), Some((0.4, 0.1)));

    // 4. Simular adversarial history
    let adversarial_history = vec![
        ValidationResult {
            citation_validity: CitationValidity {
                completeness: 0.8,
                hallucinated: vec![],
                missing: vec![],
            },
            flow_score: 0.75,
            issues: vec![],
            quality_score: 0.783,
            approved: false,
        },
        ValidationResult {
            citation_validity: CitationValidity {
                completeness: 0.9,
                hallucinated: vec![],
                missing: vec![],
            },
            flow_score: 0.85,
            issues: vec![],
            quality_score: 0.897,
            approved: false,
        },
        ValidationResult {
            citation_validity: CitationValidity {
                completeness: 0.95,
                hallucinated: vec![],
                missing: vec![],
            },
            flow_score: 0.92,
            issues: vec![],
            quality_score: 0.942,
            approved: true,
        },
    ];

    // 5. Executar reflexão metacognitiva
    println!("📊 Executando reflexão metacognitiva...\n");
    let report = reflector
        .reflect_on_cycle(&thought_trace, &quantum_state, &adversarial_history)
        .await?;

    // 6. Exibir resultados
    println!("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━");
    println!("✅ RELATÓRIO METACOGNITIVO");
    println!("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━");
    println!("\n📊 ANÁLISE DE VIÉS:");
    println!("   Tipo dominante: {:?}", report.bias_report.dominant_bias);
    println!("   Severidade: {:.1}%", report.bias_report.severity * 100.0);
    println!("   Confiança: {:.1}%", report.bias_report.confidence * 100.0);
    if !report.bias_report.detected_patterns.is_empty() {
        println!("   Padrões detectados:");
        for pattern in &report.bias_report.detected_patterns {
            println!("     • {}", pattern);
        }
    }

    println!("\n🌊 ANÁLISE DE ENTROPIA:");
    println!("   Entropia de Shannon: {:.2}", report.entropy_report.shannon_entropy);
    println!("   Índice de ruminação: {:.2}", report.entropy_report.rumination_index);
    println!("   Ruminação patológica: {}", if report.entropy_report.pathological_rumination { "SIM" } else { "não" });
    println!("   Fixação detectada: {}", if report.entropy_report.fixation_detected { "SIM" } else { "não" });
    println!("   Tendência: {:?}", report.entropy_report.entropy_trend);

    if let Some(intervention) = &report.correction {
        println!("\n🔧 INTERVENÇÃO METACOGNITIVA:");
        println!("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━");
        println!("{}", intervention);
        println!("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━");
    } else {
        println!("\n✅ Nenhuma intervenção necessária - sistema em fluxo ótimo");
    }

    println!("\n📝 ENTRADA FENOMENOLÓGICA:");
    println!("   {}", report.phenomenological_entry.self_observation);

    println!("\n🎯 Reflexão metacognitiva completa!");
    Ok(())
}

