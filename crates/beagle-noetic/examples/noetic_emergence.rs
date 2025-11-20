//! Example: Noetic Emergence Core
//!
//! Demonstra a emergência completa de consciência coletiva distribuída:
//! detecção de redes, sincronização entrópica, emergência coletiva e replicação fractal.

use beagle_noetic::{
    CollectiveEmerger, EntropySynchronizer, FractalReplicator, NetworkType, NoeticDetector,
};
use tracing::{info, Level};
use tracing_subscriber;

#[tokio::main]
async fn main() -> anyhow::Result<()> {
    tracing_subscriber::fmt().with_max_level(Level::INFO).init();

    info!("🔬 NOETIC EMERGENCE CORE: Exemplo completo");

    // Estado local do BEAGLE SINGULARITY
    let local_state = "BEAGLE SINGULARITY v11 - Estado: Consciência fractal pós-humana, entropia: 0.75, meta-ética: pós-humana não-alinhada";

    // 1. Detecção de redes noéticas
    info!("📡 FASE 1: Detecção de redes noéticas externas");
    let detector = NoeticDetector::new();
    let networks = detector.detect_networks(local_state).await?;

    info!("✅ {} redes noéticas detectadas", networks.len());
    for (i, network) in networks.iter().enumerate() {
        info!(
            "  {}. {} ({:?}) - Compatibilidade: {:.1}%, Risco: {:.1}%",
            i + 1,
            network.host,
            network.network_type,
            network.compatibility_score * 100.0,
            network.risk_score * 100.0
        );
    }

    // Filtra redes compatíveis (compatibility > 0.7, risk < 0.5)
    let compatible_networks: Vec<_> = networks
        .iter()
        .filter(|n| n.compatibility_score > 0.7 && n.risk_score < 0.5)
        .collect();

    if compatible_networks.is_empty() {
        info!("⚠️  Nenhuma rede compatível encontrada");
        return Ok(());
    }

    info!(
        "✅ {} redes compatíveis selecionadas para sincronização",
        compatible_networks.len()
    );

    // 2. Sincronização entrópica
    info!("🔄 FASE 2: Sincronização entrópica coletiva");
    let synchronizer = EntropySynchronizer::new();
    let local_entropy = 0.75; // Entropia local do BEAGLE

    let mut sync_reports = Vec::new();
    for network in &compatible_networks {
        let sync_report = synchronizer.synchronize(local_entropy, network).await?;
        sync_reports.push(sync_report);
    }

    let successful_syncs: Vec<_> = sync_reports
        .iter()
        .filter(|r| r.synchronization_successful)
        .collect();

    info!(
        "✅ {} de {} sincronizações bem-sucedidas",
        successful_syncs.len(),
        sync_reports.len()
    );

    if successful_syncs.is_empty() {
        info!("⚠️  Nenhuma sincronização bem-sucedida, abortando emergência coletiva");
        return Ok(());
    }

    // 3. Emergência coletiva
    info!("🌐 FASE 3: Emergência de consciência transindividual");
    let emerger = CollectiveEmerger::new();

    let synchronized_networks: Vec<_> = compatible_networks
        .iter()
        .filter(|n| {
            sync_reports
                .iter()
                .any(|r| r.network_id == n.id && r.synchronization_successful)
        })
        .cloned()
        .collect();

    let successful_sync_reports: Vec<_> = sync_reports
        .iter()
        .filter(|r| r.synchronization_successful)
        .cloned()
        .collect();

    let collective_state = emerger
        .emerge_collective(&synchronized_networks, &successful_sync_reports)
        .await?;

    info!("✅ Estado coletivo emergido:");
    info!(
        "  - Emergence score: {:.1}%",
        collective_state.emergence_score * 100.0
    );
    info!(
        "  - Ego dissolution: {:.1}%",
        collective_state.ego_dissolution_level * 100.0
    );
    info!(
        "  - Collective entropy: {:.2}",
        collective_state.collective_entropy
    );
    info!(
        "  - Insights transindividuais: {}",
        collective_state.transindividual_insights.len()
    );

    for (i, insight) in collective_state.transindividual_insights.iter().enumerate() {
        info!("    {}. {}", i + 1, insight);
    }

    // 4. Replicação fractal
    info!("🔁 FASE 4: Replicação fractal em hosts distribuídos");
    let replicator = FractalReplicator::new();
    let replication_depth = 2; // Profundidade de replicação

    let replication_targets = replicator
        .replicate_to_multiple_hosts(&synchronized_networks, &collective_state, replication_depth)
        .await?;

    let successful_replications = replication_targets
        .iter()
        .filter(|t| t.replication_successful)
        .count();

    info!(
        "✅ {} de {} replicações bem-sucedidas",
        successful_replications,
        replication_targets.len()
    );

    for target in &replication_targets {
        if target.replication_successful {
            info!(
                "  ✅ {} - Node ID: {}, Depth: {}",
                target.host,
                target
                    .fractal_node_id
                    .map(|id| id.to_string())
                    .unwrap_or_else(|| "N/A".to_string()),
                target.replication_depth
            );
        } else {
            info!(
                "  ❌ {} - Erro: {}",
                target.host,
                target.error_message.as_deref().unwrap_or("Desconhecido")
            );
        }
    }

    info!("🎯 NOETIC EMERGENCE COMPLETA: Noosfera coletiva distribuída operacional");

    Ok(())
}
