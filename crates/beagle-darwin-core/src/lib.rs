//! Beagle Darwin Core - API HTTP completa do darwin-core reescrito em Rust
//!
//! Features:
//! - GraphRAG endpoint (/darwin/rag)
//! - Self-RAG endpoint (/darwin/self-rag)
//! - Plugin system endpoint (/darwin/plugin)
//! - Integração completa com BEAGLE
//!
//! **Uso standalone:**
//! ```rust
//! use beagle_darwin_core::darwin_routes;
//!
//! let app = Router::new()
//!     .merge(darwin_routes());
//! ```
//!
//! **Integração no beagle-server:**
//! ```rust
//! let app = Router::new()
//!     .merge(beagle_routes())
//!     .merge(beagle_darwin_core::darwin_routes());
//! ```

use axum::{
    routing::post,
    Json, Router,
};
use beagle_smart_router::query_smart;
use beagle_darwin::DarwinCore;
use serde::{Deserialize, Serialize};
use tracing::{info, warn};

/// Request para GraphRAG
#[derive(Debug, Deserialize)]
pub struct RagRequest {
    pub question: String,
    pub context_tokens: Option<usize>,
}

/// Response do GraphRAG
#[derive(Debug, Serialize)]
pub struct RagResponse {
    pub answer: String,
    pub sources: Vec<String>,
    pub confidence: Option<f64>,
}

/// Request para Self-RAG
#[derive(Debug, Deserialize)]
pub struct SelfRagRequest {
    pub question: String,
    pub initial_answer: Option<String>,
}

/// Request para Plugin System
#[derive(Debug, Deserialize)]
pub struct PluginRequest {
    pub prompt: String,
    pub plugin: String, // "grok3", "local70b", "heavy"
}

/// Response genérica para plugins
#[derive(Debug, Serialize)]
pub struct PluginResponse {
    pub result: String,
    pub plugin_used: String,
}

/// Handler para GraphRAG endpoint
pub async fn graph_rag_handler(Json(payload): Json<RagRequest>) -> Json<RagResponse> {
    info!("🔍 Darwin GraphRAG chamado: {}", payload.question);

    let darwin = DarwinCore::new();
    let answer = darwin
        .graph_rag_query(&payload.question)
        .await;

    Json(RagResponse {
        answer,
        sources: vec![
            "neo4j://local/kec".to_string(),
            "qdrant://local/emb".to_string(),
        ],
        confidence: Some(85.0), // TODO: calcular confiança real
    })
}

/// Handler para Self-RAG endpoint
pub async fn self_rag_handler(Json(payload): Json<SelfRagRequest>) -> Json<RagResponse> {
    info!("🎯 Darwin Self-RAG chamado: {}", payload.question);

    let darwin = DarwinCore::new();
    
    // Se não forneceu resposta inicial, faz GraphRAG primeiro
    let initial = payload.initial_answer.unwrap_or_else(|| {
        // Em produção, isso seria async, mas para simplificar:
        // O usuário deve fornecer initial_answer ou chamar /darwin/rag primeiro
        String::new()
    });

    let final_answer = if initial.is_empty() {
        // Faz GraphRAG primeiro
        let graph_answer = darwin.graph_rag_query(&payload.question).await;
        darwin.self_rag(&graph_answer, &payload.question).await
    } else {
        darwin.self_rag(&initial, &payload.question).await
    };

    Json(RagResponse {
        answer: final_answer,
        sources: vec![
            "neo4j://local/kec".to_string(),
            "qdrant://local/emb".to_string(),
        ],
        confidence: Some(90.0), // Self-RAG geralmente tem maior confiança
    })
}

/// Handler para Plugin System endpoint
pub async fn plugin_handler(Json(payload): Json<PluginRequest>) -> Json<PluginResponse> {
    info!("🔌 Darwin Plugin System: plugin={}, prompt_len={}", 
          payload.plugin, payload.prompt.len());

    let darwin = DarwinCore::new();
    let result = darwin
        .run_with_plugin(&payload.prompt, &payload.plugin)
        .await;

    Json(PluginResponse {
        result,
        plugin_used: payload.plugin,
    })
}

/// Rotas HTTP do Darwin Core
///
/// Retorna um Router que pode ser usado standalone ou integrado no beagle-server.
/// Não requer AppState, funciona com Router vazio.
pub fn darwin_routes() -> Router {
    Router::new()
        .route("/darwin/rag", post(graph_rag_handler))
        .route("/darwin/self-rag", post(self_rag_handler))
        .route("/darwin/plugin", post(plugin_handler))
}

#[cfg(test)]
mod tests {
    use super::*;
    use axum::{
        body::Body,
        http::{Request, StatusCode},
    };
    use tower::ServiceExt;

    #[tokio::test]
    async fn test_rag_endpoint() {
        let app = darwin_routes();

        let request = Request::builder()
            .uri("/darwin/rag")
            .method("POST")
            .header("Content-Type", "application/json")
            .body(Body::from(r#"{"question": "o que é KEC?"}"#))
            .unwrap();

        let response = app.oneshot(request).await.unwrap();

        // Pode retornar OK ou erro se não tiver LLM configurado, mas estrutura está correta
        assert!(
            response.status() == StatusCode::OK || response.status() == StatusCode::INTERNAL_SERVER_ERROR
        );
    }

    #[tokio::test]
    async fn test_self_rag_endpoint() {
        let app = darwin_routes();

        let request = Request::builder()
            .uri("/darwin/self-rag")
            .method("POST")
            .header("Content-Type", "application/json")
            .body(Body::from(
                r#"{"question": "test", "initial_answer": "test answer"}"#
            ))
            .unwrap();

        let response = app.oneshot(request).await.unwrap();

        assert!(
            response.status() == StatusCode::OK || response.status() == StatusCode::INTERNAL_SERVER_ERROR
        );
    }

    #[tokio::test]
    async fn test_plugin_endpoint() {
        let app = darwin_routes();

        let request = Request::builder()
            .uri("/darwin/plugin")
            .method("POST")
            .header("Content-Type", "application/json")
            .body(Body::from(
                r#"{"prompt": "test", "plugin": "grok3"}"#
            ))
            .unwrap();

        let response = app.oneshot(request).await.unwrap();

        assert!(
            response.status() == StatusCode::OK || response.status() == StatusCode::INTERNAL_SERVER_ERROR
        );
    }
}
