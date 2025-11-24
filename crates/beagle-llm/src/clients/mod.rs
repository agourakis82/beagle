//! Clientes LLM para diferentes provedores

pub mod claude;
pub mod claude_cli;
pub mod codex_cli;
pub mod copilot;
pub mod cursor;
pub mod deepseek;
pub mod grok;
pub mod mock;
// pub mod local_gemma;  // Futuro

pub use claude::{ClaudeClient, ClaudeModel};
pub use claude_cli::ClaudeCliClient;
pub use codex_cli::CodexCliClient;
pub use copilot::{CopilotClient, CopilotModel};
pub use cursor::{CursorClient, CursorModel};
pub use deepseek::DeepSeekClient;
pub use grok::GrokClient;
