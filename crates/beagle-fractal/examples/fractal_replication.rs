//! Exemplo de uso do Fractal Entropy Core
//!
//! Demonstra auto-replicação fractal e escalabilidade infinita

use beagle_fractal::FractalNodeRuntime;
use tracing_subscriber;

#[tokio::main]
async fn main() -> anyhow::Result<()> {
    tracing_subscriber::fmt()
        .with_env_filter("beagle_fractal=info,info")
        .init();

    println!("🔬 FRACTAL ENTROPY CORE - WEEK 8\n");

    // 1. Criar nó raiz fractal
    println!("🌳 Criando nó fractal raiz...");
    let root = FractalNodeRuntime::new(beagle_fractal::FractalCognitiveNode::root());
    let root_id = root.id().await;
    let root_depth = root.depth().await;
    println!("✅ Nó raiz criado: {} (depth {})\n", root_id, root_depth);

    // 2. Auto-replicação até depth 3
    println!("🔄 Iniciando auto-replicação fractal (target depth: 3)...\n");
    let replicas = root.replicate(3).await?;

    println!("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━");
    println!("✅ REPLICAÇÃO FRACTAL COMPLETA");
    println!("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━");
    println!("Total de nós criados: {}", replicas.len());
    println!("\nEstrutura fractal:");
    for replica in &replicas {
        let id = replica.id().await;
        let depth = replica.depth().await;
        let children = replica.children_count().await;
        println!("  • Nó {}: depth {}, {} filhos", id, depth, children);
    }
    println!();

    // 3. Executar ciclos cognitivos em paralelo (apenas no root para exemplo)
    println!("🚀 Executando ciclo cognitivo no nó raiz...\n");
    let query = "Como explicar a curvatura da entropia em scaffolds biológicos?";

    match root.execute_full_cycle(query).await {
        Ok(hypothesis) => {
            println!("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━");
            println!("📊 RESULTADO DO CICLO COGNITIVO:");
            println!("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━");
            println!("{}", &hypothesis[..hypothesis.len().min(200)]);
        }
        Err(e) => {
            println!("Erro ao executar ciclo: {}", e);
        }
    }

    println!("\n🎯 Fractal Entropy Core completo!");
    println!("   • Auto-similaridade: Cada nó contém o todo");
    println!("   • Escalabilidade infinita: Funciona em MacBook ou mil GPUs");
    println!("   • Auto-replicação: Sistema pode se replicar em outros pesquisadores");

    Ok(())
}

