//! Camada de integração com provedores LLM para o ecossistema Beagle.
//!
//! Nesta fase, expomos clientes Vertex AI especializados nos modelos
//! Claude 3.5 (Anthropic) e Gemini 1.5 (Google).

pub mod anthropic;
pub mod gemini;
pub mod models;
pub mod vertex;

pub use anthropic::AnthropicClient;
pub use gemini::GeminiClient;
pub use models::{CompletionRequest, CompletionResponse, Message, ModelType};
pub use vertex::VertexAIClient;

/// Alias canônico para resultados com `anyhow`.
pub type Result<T> = anyhow::Result<T>;
