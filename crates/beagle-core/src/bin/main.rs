//! beagle-core - Endpoint HTTP para completions LLM
//!
//! Endpoint: POST /api/llm/complete
//! Usa BeagleRouter com detecção automática de viés

use axum::{routing::post, Router, Json};
use serde::Deserialize;
use beagle_llm::BeagleRouter;
use tracing::{info, warn};

#[derive(Deserialize)]
struct CompleteRequest {
    prompt: String,
}

async fn complete(Json(payload): Json<CompleteRequest>) -> Result<Json<serde_json::Value>, String> {
    let router = BeagleRouter;
    
    match router.complete(&payload.prompt).await {
        Ok(answer) => Ok(Json(serde_json::json!({
            "answer": answer,
            "status": "ok"
        }))),
        Err(e) => {
            warn!("Erro ao completar: {}", e);
            Err(format!("Erro: {}", e))
        }
    }
}

#[tokio::main]
async fn main() {
    tracing_subscriber::fmt::init();
    
    let app = Router::new()
        .route("/api/llm/complete", post(complete));
    
    info!("beagle-core rodando → http://localhost:8080");
    info!("Endpoint: POST /api/llm/complete");
    
    let listener = tokio::net::TcpListener::bind("0.0.0.0:8080")
        .await
        .expect("Falha ao bind na porta 8080");
    
    axum::serve(listener, app)
        .await
        .expect("Falha ao iniciar servidor");
}

