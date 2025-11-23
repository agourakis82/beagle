//! Claude Code CLI Client
//!
//! Uses local Claude Code CLI installation instead of API keys.
//! This leverages your Claude MAX subscription via the CLI tool.
//!
//! Features:
//! - No API key required (uses `claude` command)
//! - Direct access to Claude Sonnet 4.5
//! - Perfect for self-updating BEAGLE
//! - Uses your existing Claude MAX subscription
//!
//! Setup:
//! 1. Install Claude Code: https://claude.ai/download
//! 2. Login: `claude auth login`
//! 3. BEAGLE will automatically use it!

use crate::{ChatMessage, LlmClient, LlmRequest, Tier};
use async_trait::async_trait;
use std::process::Stdio;
use tokio::io::{AsyncReadExt, AsyncWriteExt};
use tokio::process::Command;
use tracing::{debug, info, warn};

/// Claude Code CLI client
pub struct ClaudeCliClient {
    cli_path: String,
    model: String,
}

impl ClaudeCliClient {
    /// Create new client (auto-detects `claude` command)
    pub fn new() -> anyhow::Result<Self> {
        // Check if claude command exists
        let cli_path = Self::find_claude_cli()?;

        Ok(Self {
            cli_path,
            model: "claude-sonnet-4.5".to_string(),
        })
    }

    /// Try to find claude CLI in PATH
    fn find_claude_cli() -> anyhow::Result<String> {
        // Try common locations
        let home_path = std::env::var("HOME")
            .ok()
            .map(|h| format!("{}/.local/bin/claude", h))
            .unwrap_or_default();

        let candidates = vec![
            "claude",                   // In PATH
            "/usr/local/bin/claude",    // Linux/macOS
            "/opt/homebrew/bin/claude", // macOS Homebrew
            "~/.local/bin/claude",      // User install
            &home_path,
        ];

        for candidate in candidates {
            if candidate.is_empty() {
                continue;
            }

            // Expand ~ to home directory
            let path = if candidate.starts_with("~") {
                if let Ok(home) = std::env::var("HOME") {
                    candidate.replace("~", &home)
                } else {
                    candidate.to_string()
                }
            } else {
                candidate.to_string()
            };

            // Check if executable exists
            if std::process::Command::new(&path)
                .arg("--version")
                .output()
                .is_ok()
            {
                info!("Found Claude CLI at: {}", path);
                return Ok(path);
            }
        }

        anyhow::bail!(
            "Claude CLI not found. Please install from https://claude.ai/download \
             or login with: claude auth login"
        )
    }

    /// Check if user is logged in
    pub async fn is_logged_in(&self) -> bool {
        Command::new(&self.cli_path)
            .arg("auth")
            .arg("status")
            .output()
            .await
            .map(|out| out.status.success())
            .unwrap_or(false)
    }

    /// Prompt user to login (returns instructions)
    pub fn login_instructions() -> String {
        "To use Claude CLI:\n\
         1. Install: https://claude.ai/download\n\
         2. Login: claude auth login\n\
         3. BEAGLE will automatically detect it!"
            .to_string()
    }
}

impl Default for ClaudeCliClient {
    fn default() -> Self {
        Self::new().unwrap_or_else(|_| {
            warn!("Claude CLI not available, using placeholder");
            Self {
                cli_path: "claude".to_string(),
                model: "claude-sonnet-4.5".to_string(),
            }
        })
    }
}

#[async_trait]
impl LlmClient for ClaudeCliClient {
    fn name(&self) -> &'static str {
        "claude-cli"
    }

    fn tier(&self) -> Tier {
        Tier::CloudGrokMain // High quality tier
    }

    async fn chat(&self, request: LlmRequest) -> anyhow::Result<String> {
        debug!(
            "Calling Claude CLI with {} messages",
            request.messages.len()
        );

        // Check if logged in first
        if !self.is_logged_in().await {
            anyhow::bail!(
                "Not logged in to Claude CLI. Run: claude auth login\n{}",
                Self::login_instructions()
            );
        }

        // Build prompt from messages
        let mut prompt = String::new();
        for msg in &request.messages {
            match msg.role.as_str() {
                "system" => {
                    prompt.push_str(&format!("System: {}\n\n", msg.content));
                }
                "user" => {
                    prompt.push_str(&format!("User: {}\n\n", msg.content));
                }
                "assistant" => {
                    prompt.push_str(&format!("Assistant: {}\n\n", msg.content));
                }
                _ => {}
            }
        }

        // Call claude CLI
        let mut child = Command::new(&self.cli_path)
            .arg("chat")
            .arg("--model")
            .arg(&self.model)
            .stdin(Stdio::piped())
            .stdout(Stdio::piped())
            .stderr(Stdio::piped())
            .spawn()?;

        // Write prompt to stdin
        if let Some(mut stdin) = child.stdin.take() {
            stdin.write_all(prompt.as_bytes()).await?;
            drop(stdin); // Close stdin to signal end of input
        }

        // Read response
        let mut stdout = child.stdout.take().unwrap();
        let mut stderr = child.stderr.take().unwrap();

        let mut response = String::new();
        let mut error = String::new();

        // Read both stdout and stderr
        tokio::try_join!(
            stdout.read_to_string(&mut response),
            stderr.read_to_string(&mut error)
        )?;

        // Wait for process to finish
        let status = child.wait().await?;

        if !status.success() {
            anyhow::bail!("Claude CLI error: {}", error);
        }

        if !error.is_empty() {
            warn!("Claude CLI stderr: {}", error);
        }

        info!("Claude CLI response: {} chars", response.len());

        Ok(response.trim().to_string())
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[tokio::test]
    #[ignore] // Requires claude CLI installed and logged in
    async fn test_claude_cli_client() {
        let client = ClaudeCliClient::new().unwrap();

        assert!(
            client.is_logged_in().await,
            "Please login: claude auth login"
        );

        let request = LlmRequest {
            model: "claude-sonnet-4.5".to_string(),
            messages: vec![ChatMessage::user(
                "What is 2+2? Answer with just the number.",
            )],
            temperature: Some(0.0),
            max_tokens: Some(10),
        };

        let response = client.chat(request).await.unwrap();
        println!("Response: {}", response);
        assert!(response.contains("4"));
    }

    #[test]
    fn test_find_claude_cli() {
        // This will fail if claude not installed, which is expected
        match ClaudeCliClient::find_claude_cli() {
            Ok(path) => println!("Found Claude CLI at: {}", path),
            Err(e) => println!("Claude CLI not found (expected): {}", e),
        }
    }
}
