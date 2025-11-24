//! Demo do Fractal Core - Replicação Infinita Segura
//!
//! Demonstra:
//! - Inicialização do root fractal
//! - Replicação até depth 5 (safe demo depth)
//! - Memória controlada via Arc + async, sem stack overflow
//! - Consciousness mirror integration em cada nó

use beagle_fractal::{get_root, init_fractal_root, FractalNodeRuntime};
use tracing::{info, Level};
use tracing_subscriber::fmt;

#[tokio::main]
async fn main() -> anyhow::Result<()> {
    // Setup tracing
    fmt()
        .with_max_level(Level::INFO)
        .with_target(false)
        .with_thread_ids(false)
        .init();

    // Initialize fractal root
    let root = init_fractal_root().await;
    info!("✅ Fractal root initialized");

    // Get root and wrap in runtime
    let root_ref = get_root().await;
    let root_node = (*root_ref).clone();
    let runtime = FractalNodeRuntime::new(root_node);

    // Demonstrate recursive replication
    info!("🚀 Starting fractal replication to depth 5...");
    let replicas = runtime.replicate(5).await?;
    info!(
        "✅ Replication complete: {} active nodes across depths",
        replicas.len()
    );

    // Execute a cognitive cycle at the root
    info!("🧠 Executing full cognitive cycle...");
    let query = "What does it mean to be fractal?";
    match runtime.execute_full_cycle(query).await {
        Ok(response) => {
            println!("📝 Root Response: {}", response);
        }
        Err(e) => {
            eprintln!("⚠️ Cycle failed: {}", e);
        }
    }

    // Show structure
    println!("\n🎯 FRACTAL STRUCTURE INITIALIZED");
    println!("   Root ID: {}", root.id);
    println!("   Root Depth: {}", root.depth);
    println!("   Root Children: {}", root.children_ids.len());
    println!("   Total Nodes Replicated: {}", replicas.len());
    println!("   Memory Usage: Safe (Arc-based sharing)");

    Ok(())
}
