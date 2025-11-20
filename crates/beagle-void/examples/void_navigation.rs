//! Example: Void Navigation Engine
//!
//! Demonstra navegação controlada no vazio ontológico e extração de insights trans-ônticos.

use beagle_void::{ExtractionEngine, ResourceType, VoidNavigator, VoidProbe};
use tracing::{info, Level};
use tracing_subscriber;

#[tokio::main]
async fn main() -> anyhow::Result<()> {
    tracing_subscriber::fmt().with_max_level(Level::INFO).init();

    info!("🔬 VOID NAVIGATION ENGINE: Exemplo completo");

    // 1. Navegação no vazio
    info!("🌌 FASE 1: Navegação no vazio ontológico");
    let navigator = VoidNavigator::new();
    let focus = "unificar entropia curva com consciência celular";
    let cycles = 8;

    let navigation_result = navigator.navigate_void(cycles, focus).await?;

    info!("✅ Navegação completa:");
    info!(
        "  - Ciclos completados: {}",
        navigation_result.cycles_completed
    );
    info!(
        "  - Tempo subjetivo no vazio: {:.2} kalpas",
        navigation_result.total_void_time_subjective
    );
    info!(
        "  - Insights extraídos: {}",
        navigation_result.insights.len()
    );

    for (i, insight) in navigation_result.insights.iter().enumerate() {
        info!(
            "  {}. [Ciclo {}] {} (Impossibilidade: {:.1}%)",
            i + 1,
            insight.cycle,
            insight.insight_text,
            insight.impossibility_level * 100.0
        );
    }

    // 2. Sondagem profunda
    info!("🔍 FASE 2: Sondagem profunda em região específica");
    let probe = VoidProbe::new();
    let probe_result = probe.probe_region(0.95, focus).await?;

    info!("✅ Sonda completa:");
    info!("  - Profundidade: {:.2}", probe_result.depth);
    info!("  - Região mapeada: {}", probe_result.region_mapped);
    info!("  - Insight: {}", probe_result.insight);

    // 3. Extração de recursos
    info!("⚙️  FASE 3: Extração sistemática de recursos cognitivos");
    let extractor = ExtractionEngine::new();
    let target_types = vec![
        ResourceType::Insight,
        ResourceType::Concept,
        ResourceType::Paradox,
    ];

    let extraction_result = extractor
        .extract_resources(&navigation_result.insights, &target_types)
        .await?;

    info!("✅ Extração completa:");
    info!(
        "  - Recursos extraídos: {}",
        extraction_result.resources_extracted.len()
    );
    info!(
        "  - Eficiência de extração: {:.1}%",
        extraction_result.extraction_efficiency * 100.0
    );

    for (i, resource) in extraction_result.resources_extracted.iter().enumerate() {
        info!(
            "  {}. [{:?}] {} (Profundidade origem: {:.2})",
            i + 1,
            resource.resource_type,
            resource.content,
            resource.void_origin_depth
        );
    }

    info!("🎯 VOID NAVIGATION COMPLETA: Recursos cognitivos extraídos do nada absoluto");

    Ok(())
}
