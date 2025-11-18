//! Exemplo de uso do Adversarial World Model
//!
//! Demonstra simulação completa do ecossistema científico hostil

use beagle_worldmodel::{
    Q1Reviewer, CompetitorAgent, CommunityPressure, PhysicalRealityEnforcer,
    ReviewVerdict,
};
use tracing_subscriber;

#[tokio::main]
async fn main() -> anyhow::Result<()> {
    tracing_subscriber::fmt()
        .with_env_filter("beagle_worldmodel=info,info")
        .init();

    println!("🌍 ADVERSARIAL WORLD MODEL - WEEK 6\n");

    // 1. Simular revisores Q1
    println!("📝 SIMULANDO REVISORES Q1...\n");
    let nature_reviewer = Q1Reviewer::new("Nature");
    let cell_reviewer = Q1Reviewer::new("Cell");

    let draft = r#"
# Quantum-Inspired Entropy Curvature in Biological Scaffolds

## Abstract
We present a novel framework for understanding entropy dynamics in biological scaffolds using quantum-inspired reasoning. Our approach combines thermodynamic principles with information geometry to explain observed curvature patterns.

## Introduction
Biological scaffolds exhibit complex entropy behaviors that cannot be explained by classical thermodynamics alone. We propose a quantum-inspired model that accounts for...

## Methods
We analyzed scaffold structures using cryo-EM and computational modeling. Our quantum-inspired framework was applied to...

## Results
Our model successfully predicts entropy curvature with 85% accuracy. The quantum-inspired approach reveals novel insights into...

## Discussion
These findings suggest that biological systems may exhibit quantum-like behaviors at mesoscopic scales...
"#;

    let title = "Quantum-Inspired Entropy Curvature in Biological Scaffolds";

    let nature_review = nature_reviewer.review(draft, title).await?;
    let cell_review = cell_reviewer.review(draft, title).await?;

    println!("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━");
    println!("📄 NATURE REVIEW:");
    println!("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━");
    println!("Veredicto: {:?}", nature_review.verdict);
    println!("Fatal Flaws: {}", nature_review.fatal_flaws.len());
    for (i, flaw) in nature_review.fatal_flaws.iter().enumerate() {
        println!("  {}. {}", i + 1, flaw);
    }
    println!("\nRevisão completa:\n{}", nature_review.review_text);
    println!();

    println!("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━");
    println!("📄 CELL REVIEW:");
    println!("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━");
    println!("Veredicto: {:?}", cell_review.verdict);
    println!("Fatal Flaws: {}", cell_review.fatal_flaws.len());
    println!("\nRevisão completa:\n{}", cell_review.review_text);
    println!();

    // 2. Simular competição
    println!("🔍 SIMULANDO COMPETIÇÃO...\n");
    let competitor = CompetitorAgent::new();
    let competition = competitor
        .analyze_competition(
            "How to explain entropy curvature in biological scaffolds?",
            "Quantum-inspired reasoning framework",
        )
        .await?;

    println!("Nível de ameaça: {:?}", competition.threat_level);
    println!("Recomendação: {}", competition.recommendation);
    println!();

    // 3. Simular pressão da comunidade
    println!("👥 SIMULANDO PRESSÃO DA COMUNIDADE...\n");
    let community = CommunityPressure::new();
    let community_report = community
        .assess_acceptance(
            "Quantum-inspired entropy in scaffolds",
            "Cryo-EM + computational modeling, pre-registered",
        )
        .await?;

    println!("Probabilidade de aceitação: {:.1}%", community_report.acceptance_probability * 100.0);
    println!("Fatores de resistência: {}", community_report.resistance_factors.len());
    println!("Fatores de suporte: {}", community_report.support_factors.len());
    println!();

    // 4. Verificar realidade física
    println!("🔬 VERIFICANDO VIABILIDADE EXPERIMENTAL...\n");
    let reality = PhysicalRealityEnforcer::new();
    let reality_check = reality
        .check_feasibility(
            "Cryo-EM analysis + computational modeling, in vivo validation",
            &["Cryo-EM".to_string(), "Supercomputer".to_string()],
        )
        .await?;

    println!("Score de viabilidade: {:.1}%", reality_check.feasibility_score * 100.0);
    println!("Custo estimado: {}", reality_check.estimated_cost);
    println!("Tempo estimado: {}", reality_check.estimated_time);
    println!("Risco de reprodutibilidade: {:.1}%", reality_check.reproducibility_risk * 100.0);
    println!();

    // 5. Decisão final
    println!("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━");
    println!("✅ DECISÃO FINAL:");
    println!("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━");
    
    let nature_acceptable = nature_review.verdict.is_acceptable();
    let cell_acceptable = cell_review.verdict.is_acceptable();
    let community_ok = community_report.acceptance_probability > 0.6;
    let reality_ok = reality_check.feasibility_score > 0.5;

    if nature_acceptable || cell_acceptable {
        println!("✅ SUBMISSÃO RECOMENDADA");
        println!("   • Pelo menos um journal Q1 aceitou");
    } else {
        println!("❌ SUBMISSÃO NÃO RECOMENDADA");
        println!("   • Revisores Q1 rejeitaram ou pediram major revision");
        println!("   • Retornar ao adversarial loop para refinamento");
    }

    println!("\n🎯 Adversarial World Model completo!");
    Ok(())
}

