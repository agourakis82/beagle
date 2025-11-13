//! Integração com Vertex AI Anthropic Models (Claude 3.5 família).
//!
//! Fornece cliente autenticado com Application Default Credentials
//! e abstrações leves de mensagens e modelos compatíveis.

pub mod client;
pub mod models;

pub use client::VertexAIClient;
pub use models::{CompletionRequest, CompletionResponse, Message, ModelType};
