//! Servidor standalone do Darwin Core
//!
//! Demonstra como rodar o darwin-core como servidor HTTP independente.
//!
//! Roda com:
//! ```bash
//! cargo run --example standalone_server --package beagle-darwin-core
//! ```
//!
//! Endpoints disponíveis:
//! - POST /darwin/rag - GraphRAG query
//! - POST /darwin/self-rag - Self-RAG com gatekeeping
//! - POST /darwin/plugin - Plugin system (grok3/local70b/heavy)

use axum::Router;
use beagle_darwin_core::darwin_routes;
use std::net::SocketAddr;
use tracing_subscriber;

#[tokio::main]
async fn main() -> anyhow::Result<()> {
    // Configurar logging
    tracing_subscriber::fmt()
        .with_max_level(tracing::Level::INFO)
        .init();

    // Criar app com rotas do Darwin
    let app = Router::new().merge(darwin_routes());

    // Bind e serve
    let addr = SocketAddr::from(([0, 0, 0, 0], 3001));
    println!("🚀 Darwin Core Server rodando em http://{}", addr);
    println!("📋 Endpoints:");
    println!("   POST /darwin/rag - GraphRAG query");
    println!("   POST /darwin/self-rag - Self-RAG com gatekeeping");
    println!("   POST /darwin/plugin - Plugin system");

    let listener = tokio::net::TcpListener::bind(addr).await?;
    axum::serve(listener, app).await?;

    Ok(())
}
