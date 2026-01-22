//! Clientes LLM para diferentes provedores

pub mod claude;
pub mod claude_cli;
pub mod codex_cli;
pub mod copilot;
pub mod cursor;
pub mod deepseek;
pub mod grok;
pub mod minimax;
pub mod zai;
pub mod local_gemma;
pub mod mock;

pub use claude::{ClaudeClient, ClaudeModel};
pub use claude_cli::ClaudeCliClient;
pub use codex_cli::CodexCliClient;
pub use copilot::{CopilotClient, CopilotModel};
pub use cursor::{CursorClient, CursorModel};
pub use deepseek::DeepSeekClient;
pub use grok::GrokClient;
pub use minimax::MiniMaxClient;
pub use zai::ZaiClient;
pub use local_gemma::{LocalGemmaClient, GemmaModel};
