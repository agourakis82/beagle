//! Demo do Fractal Core - Replicação Infinita Segura
//!
//! Roda recursão fractal até depth 12 (4^12 = 16.777.216 nós)
//! Memória controlada via Arc + async, sem stack overflow

use beagle_fractal::init_fractal_root;
use beagle_quantum::HypothesisSet;
use std::sync::Arc;
use tracing::{info, Level};
use tracing_subscriber::fmt;

#[tokio::main]
async fn main() {
    // Setup tracing
    fmt()
        .with_max_level(Level::INFO)
        .with_target(false)
        .with_thread_ids(false)
        .init();

    let empty_set = HypothesisSet::new();
    let root = init_fractal_root(empty_set).await;

    info!("🚀 Iniciando replicação fractal até depth 12 (4^12 = 16.777.216 nós)");

    let deepest = Arc::clone(&root).replicate_fractal(12).await;

    info!(
        "✅ Fractal replicado - deepest depth: {} - total nós estimado: >16M",
        deepest.depth
    );

    println!("🎯 FRACTAL INFINITO RODANDO - memória usada segura via Arc + async");
    println!("   Deepest node ID: {}", deepest.id);
    println!("   Depth: {}", deepest.depth);
    println!(
        "   Hologram size: {} bytes",
        deepest.compressed_hologram.len()
    );
}
