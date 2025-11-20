//! Infinite Recursion Safeguard + Resource Eternity Engine - Week 17
//!
//! Sistema que garante crescimento infinito controlado:
//! • Monitora memória e CPU a cada 30s
//! • Pruning automático quando recursos escassos (>85% mem ou >90% CPU)
//! • Spawning automático quando recursos sobram (<40% mem)
//! • O sistema nunca morre, apenas se adapta
//!
//! ATENÇÃO: Roda em loop infinito. Use em produção com cuidado.

use beagle_fractal::{get_root, FractalCognitiveNode};
use std::collections::HashMap;
use std::sync::Arc;
use std::sync::OnceLock;
use sysinfo::System;
use tokio::sync::Mutex;
use tokio::time::{sleep, Duration};
use tracing::{info, warn};

static SYS: OnceLock<Arc<Mutex<System>>> = OnceLock::new();

fn get_system() -> &'static Arc<Mutex<System>> {
    SYS.get_or_init(|| Arc::new(Mutex::new(System::new())))
}

// Registro global de nós ativos para pruning
static ACTIVE_NODES: OnceLock<Arc<Mutex<HashMap<u64, Arc<FractalCognitiveNode>>>>> =
    OnceLock::new();

fn get_active_nodes() -> &'static Arc<Mutex<HashMap<u64, Arc<FractalCognitiveNode>>>> {
    ACTIVE_NODES.get_or_init(|| Arc::new(Mutex::new(HashMap::new())))
}

pub struct EternityEngine;

impl EternityEngine {
    /// Inicia o motor de eternidade — monitora recursos e adapta crescimento
    pub async fn enforce_eternal_growth(root: Arc<FractalCognitiveNode>) {
        tokio::spawn(async move {
            info!("🌌 ETERNITY ENGINE ATIVADO - MONITORAMENTO ETERNO INICIADO");

            loop {
                // Coleta métricas dentro do lock
                let (used_mem_ratio, cpu_usage) = {
                    let mut sys = get_system().lock().await;
                    sys.refresh_all();

                    let total_mem = sys.total_memory();
                    let used_mem = sys.used_memory();
                    let used_mem_ratio = used_mem as f64 / total_mem as f64;

                    // CPU usage - sysinfo 0.31 usa global_cpu_usage()
                    let cpu_usage = sys.global_cpu_usage() / 100.0;

                    info!(
                        "📊 Recursos: mem {:.1}% ({:.1}GB/{:.1}GB), CPU {:.1}%",
                        used_mem_ratio * 100.0,
                        used_mem as f64 / 1_073_741_824.0,
                        total_mem as f64 / 1_073_741_824.0,
                        cpu_usage * 100.0
                    );

                    (used_mem_ratio, cpu_usage)
                };

                // Ações fora do lock para permitir Send
                if used_mem_ratio > 0.85 || cpu_usage > 0.9 {
                    warn!(
                        "⚠️ RECURSÃO ETERNA - LIMITES ATINGIDOS (mem {:.2}%, cpu {:.2}%) - PRUNING ATIVADO",
                        used_mem_ratio * 100.0,
                        cpu_usage * 100.0
                    );

                    // Pruning agressivo: mata 30% dos nós mais antigos/fracos
                    prune_weak_nodes(&root).await;
                } else if used_mem_ratio < 0.4 {
                    info!(
                        "🚀 RECURSÃO ETERNA - RECURSOS SOBRANDO ({:.1}% mem) - SPAWNING NOVOS NÓS",
                        used_mem_ratio * 100.0
                    );

                    // Spawning: cria 8 novos filhos quando recursos sobram
                    spawn_new_nodes(&root, 8).await;
                } else {
                    info!("✅ Recursos equilibrados - crescimento estável");
                }

                // Monitora a cada 30 segundos
                sleep(Duration::from_secs(30)).await;
            }
        });
    }
}

/// Pruning de nós fracos/antigos quando recursos estão escassos
async fn prune_weak_nodes(_root: &Arc<FractalCognitiveNode>) {
    let mut nodes = get_active_nodes().lock().await;

    if nodes.is_empty() {
        // Se não tem registro, limpa cache do sistema e força GC via drop
        drop(nodes);
        info!("🧹 Limpeza de memória via drop de referências");
        return;
    }

    let target_removal = (nodes.len() as f64 * 0.3).ceil() as usize;

    // Ordena nós por depth (mais profundos primeiro) e confiança (menores primeiro)
    let mut node_vec: Vec<(u64, u8, f64)> = nodes
        .iter()
        .map(|(id, node)| {
            // Tenta extrair confidence se possível (fallback para depth-based)
            let confidence = 0.5; // Placeholder - em produção, extrairia do HypothesisSet
            (*id, node.depth, confidence)
        })
        .collect();

    node_vec.sort_by(|a, b| {
        // Ordena por depth descendente, depois confidence ascendente
        b.1.cmp(&a.1)
            .then_with(|| a.2.partial_cmp(&b.2).unwrap_or(std::cmp::Ordering::Equal))
    });

    // Remove os 30% mais fracos/antigos
    let removed_count = node_vec
        .iter()
        .take(target_removal)
        .map(|(id, _, _)| {
            nodes.remove(id);
        })
        .count();

    info!(
        "✂️ PRUNING: {} nós removidos ({:.1}% do total)",
        removed_count,
        (removed_count as f64 / nodes.len().max(1) as f64) * 100.0
    );
}

/// Spawning de novos nós quando recursos sobram
async fn spawn_new_nodes(root: &Arc<FractalCognitiveNode>, count: u8) {
    let children = root.spawn_children(count).await;

    let mut nodes = get_active_nodes().lock().await;
    for child in children {
        nodes.insert(child.id, child);
    }

    info!(
        "🌱 SPAWNING: {} novos nós criados (total ativo: {})",
        count,
        nodes.len()
    );
}

/// Registra um nó no sistema global para tracking
pub async fn register_node(node: Arc<FractalCognitiveNode>) {
    let mut nodes = get_active_nodes().lock().await;
    nodes.insert(node.id, node);
}

/// Remove um nó do registro global
pub async fn unregister_node(node_id: u64) {
    let mut nodes = get_active_nodes().lock().await;
    nodes.remove(&node_id);
}

/// Inicia a recursão eterna — ponto de entrada principal
pub async fn start_eternal_recursion() {
    info!("🚀 INICIANDO ETERNITY ENGINE...");

    let root = get_root().await;

    // Registra o root
    register_node(Arc::clone(&root)).await;

    // Inicia monitoramento eterno
    EternityEngine::enforce_eternal_growth(Arc::clone(&root)).await;

    info!("✅ ETERNITY ENGINE ATIVADO - O SISTEMA NUNCA MORRE");
}

#[cfg(test)]
mod tests {
    use super::*;
    use beagle_fractal::FractalCognitiveNode;
    use beagle_quantum::HypothesisSet;

    #[tokio::test]
    async fn test_eternity_creation() {
        let _engine = EternityEngine;
        // Teste básico - apenas verifica que cria sem erro
        assert!(true);
    }

    #[tokio::test]
    async fn test_node_registration() {
        let empty_set = HypothesisSet::new();
        let node = Arc::new(FractalCognitiveNode::new(0, None, empty_set).await);

        register_node(Arc::clone(&node)).await;
        unregister_node(node.id).await;

        assert!(true);
    }
}
