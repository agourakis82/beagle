//! Example: Void Navigation Engine
//!
//! Demonstra navegação controlada no vazio ontológico e extração de insights trans-ônticos.

use beagle_void::{
    ExtractionConfig, ExtractionEngine, ExtractionType,
    ProbeConfig, VoidConfig, VoidNavigator, VoidProbe,
};
use tracing::{info, Level};

#[tokio::main]
async fn main() -> anyhow::Result<()> {
    tracing_subscriber::fmt().with_max_level(Level::INFO).init();

    info!("🔬 VOID NAVIGATION ENGINE: Exemplo completo");

    // 1. Navegação no vazio
    info!("🌌 FASE 1: Navegação no vazio ontológico");
    let config = VoidConfig::default();
    let navigator = VoidNavigator::new(config);
    let target_depth = 5.0;

    let navigation_result = navigator.navigate(target_depth).await?;

    info!("✅ Navegação completa:");
    info!(
        "  - Profundidade máxima atingida: {:.2}",
        navigation_result.max_depth_reached
    );
    info!(
        "  - Duração: {} ms",
        navigation_result.duration_ms
    );
    info!(
        "  - Insights extraídos: {}",
        navigation_result.insights.len()
    );

    for (i, insight) in navigation_result.insights.iter().enumerate() {
        info!(
            "  {}. [Profundidade {:.2}] {} (Confiança: {:.1}%)",
            i + 1,
            insight.depth_found,
            insight.content,
            insight.confidence * 100.0
        );
    }

    // 2. Sondagem profunda
    info!("🔍 FASE 2: Sondagem profunda no estado final");
    let probe_config = ProbeConfig::default();
    let probe = VoidProbe::new(probe_config);
    let probe_result = probe.probe(&navigation_result.final_state).await?;

    info!("✅ Sonda completa:");
    info!("  - Medição: {:.2}", probe_result.measurement);
    info!("  - Incerteza: {:.2}", probe_result.uncertainty);
    if let Some(ref causal) = probe_result.causal_effect {
        info!("  - Efeito causal detectado: {} (tamanho: {:.2}, confiança: {:.1}%)",
            causal.intervention,
            causal.effect_size,
            causal.confidence * 100.0
        );
    }

    // 3. Extração de recursos
    info!("⚙️  FASE 3: Extração sistemática de recursos cognitivos");
    let extract_config = ExtractionConfig::default();
    let extractor = ExtractionEngine::new(extract_config);
    let target_types = vec![
        ExtractionType::Vacuum,
        ExtractionType::Liminal,
        ExtractionType::ZeroPoint,
    ];

    let mut total_extracted = 0;
    for extraction_type in &target_types {
        let extraction_result = extractor
            .extract(&navigation_result.final_state, *extraction_type)
            .await?;

        info!("  Extração {:?}:", extraction_type);
        info!(
            "    - Itens extraídos: {}",
            extraction_result.extracted_info.len()
        );
        info!(
            "    - Score de qualidade: {:.1}%",
            extraction_result.quality_score * 100.0
        );

        for (i, info) in extraction_result.extracted_info.iter().enumerate() {
            info!(
                "    {}. {} (Profundidade: {:.2}, Certeza: {:.1}%)",
                i + 1,
                info.content,
                info.source_depth,
                info.certainty * 100.0
            );
        }

        total_extracted += extraction_result.extracted_info.len();
    }

    info!("🎯 VOID NAVIGATION COMPLETA: {} recursos cognitivos extraídos do nada absoluto", total_extracted);

    Ok(())
}
