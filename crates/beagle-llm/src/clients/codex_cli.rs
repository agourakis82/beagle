//! OpenAI Codex CLI Client
//!
//! Uses local Codex CLI (`codex exec`) with ChatGPT Pro subscription.
//! No API key required - leverages your $200/month Pro subscription.
//!
//! Features:
//! - No API key required (uses `codex` command)
//! - Direct access to GPT-5.1 Codex Max
//! - Configurable reasoning effort (low, medium, high)
//! - Uses your existing ChatGPT Pro subscription
//!
//! Setup:
//! 1. Install: `npm install -g @openai/codex-cli`
//! 2. Login: `codex auth login`
//! 3. BEAGLE will automatically use it!

use crate::models::{CompletionRequest, CompletionResponse, Message};
use anyhow::{Context, Result};
use serde_json::Value;
use std::io::Write;
use std::process::{Command, Stdio};
use tracing::{debug, info, warn};

/// OpenAI Codex CLI client
pub struct CodexCliClient {
    /// Path to codex executable
    codex_path: String,
    /// Reasoning effort level (low, medium, high)
    reasoning_effort: String,
}

impl CodexCliClient {
    /// Create new client (auto-detects `codex` command)
    pub fn new() -> Result<Self> {
        let codex_path = Self::find_codex_cli()?;

        info!("Codex CLI found at: {}", codex_path);

        Ok(Self {
            codex_path,
            reasoning_effort: "medium".to_string(),
        })
    }

    /// Configure reasoning effort level
    pub fn with_reasoning_effort(mut self, effort: impl Into<String>) -> Self {
        self.reasoning_effort = effort.into();
        self
    }

    /// Check if Codex CLI is available
    pub fn check_available() -> bool {
        Command::new("which")
            .arg("codex")
            .output()
            .map(|output| output.status.success())
            .unwrap_or(false)
    }

    /// Try to find codex CLI in PATH
    fn find_codex_cli() -> Result<String> {
        let output = Command::new("which")
            .arg("codex")
            .output()
            .context("Failed to check if 'codex' CLI is installed")?;

        if !output.status.success() {
            anyhow::bail!("Codex CLI not found. Install with: npm install -g @openai/codex-cli");
        }

        let path = String::from_utf8(output.stdout)
            .context("Codex path contains invalid characters")?
            .trim()
            .to_string();

        Ok(path)
    }

    /// Execute completion using Codex CLI
    pub async fn complete(&self, request: CompletionRequest) -> Result<CompletionResponse> {
        let CompletionRequest {
            model: _,
            messages,
            max_tokens: _,
            temperature: _,
            system,
        } = request;

        // Build prompt from messages
        let prompt = self.build_prompt(&messages, system.as_deref())?;

        debug!(
            prompt_length = prompt.len(),
            reasoning_effort = %self.reasoning_effort,
            "Sending request to Codex CLI"
        );

        // Execute Codex CLI
        // Note: Codex uses Pro subscription authentication automatically
        let mut child = Command::new(&self.codex_path)
            .arg("exec")
            .arg("--skip-git-repo-check") // Allow use outside git repos
            .arg("-c")
            .arg(format!("model_reasoning_effort={}", self.reasoning_effort))
            .stdin(Stdio::piped())
            .stdout(Stdio::piped())
            .stderr(Stdio::piped())
            .spawn()
            .context("Failed to execute Codex CLI")?;

        // Write prompt to stdin
        {
            let stdin = child
                .stdin
                .as_mut()
                .ok_or_else(|| anyhow::anyhow!("Failed to open Codex CLI stdin"))?;
            stdin
                .write_all(prompt.as_bytes())
                .context("Failed to write prompt to stdin")?;
        }

        // Wait for response
        let output = child
            .wait_with_output()
            .context("Failed to wait for Codex CLI response")?;

        if !output.status.success() {
            let stderr = String::from_utf8_lossy(&output.stderr);
            warn!("Codex CLI returned error: {}", stderr);
            anyhow::bail!("Codex CLI failed: {}", stderr);
        }

        let full_output = String::from_utf8(output.stdout)
            .context("Codex CLI response contains invalid characters")?;

        debug!("Raw Codex output:\n{}", full_output);

        // Parse Codex output to extract response
        let content = self.parse_codex_output(&full_output)?;

        debug!(
            response_length = content.len(),
            "Response received from Codex CLI"
        );

        Ok(CompletionResponse {
            content,
            model: "gpt-5.1-codex-max".to_string(),
            usage: Value::Null, // Codex CLI doesn't return structured usage info
        })
    }

    /// Parse Codex CLI output to extract response
    ///
    /// Codex CLI returns format like:
    /// ```text
    /// Reading prompt from stdin...
    /// OpenAI Codex v0.46.0 (research preview)
    /// --------
    /// [metadata]
    /// --------
    /// user
    /// [prompt]
    ///
    /// thinking
    /// [reasoning]
    /// codex
    /// [response]
    /// tokens used
    /// [count]
    /// [response again]
    /// ```
    fn parse_codex_output(&self, output: &str) -> Result<String> {
        let trimmed = output.trim();

        // Simple case: if output is short and no special formatting,
        // return directly (Codex sometimes simplifies output)
        if !trimmed.contains("codex") && !trimmed.contains("thinking") && trimmed.len() < 1000 {
            return Ok(trimmed.to_string());
        }

        // Look for "codex" section containing the response
        let lines: Vec<&str> = output.lines().collect();

        let mut in_codex_section = false;
        let mut in_tokens_section = false;
        let mut response_lines = Vec::new();

        for line in lines {
            if line.trim() == "codex" {
                in_codex_section = true;
                continue;
            }

            if line.trim() == "tokens used" {
                in_tokens_section = true;
                in_codex_section = false;
                continue;
            }

            if in_codex_section && !line.trim().is_empty() {
                response_lines.push(line);
            }

            // Last line after "tokens used" also contains response
            if in_tokens_section && !line.trim().is_empty() {
                // Skip token number
                if line
                    .chars()
                    .all(|c| c.is_numeric() || c.is_whitespace() || c == ',')
                {
                    continue;
                }
                response_lines.push(line);
                break; // Final response is last line
            }
        }

        if response_lines.is_empty() {
            // Fallback: get last non-empty line that isn't a number
            // (Codex repeats final response on last line)
            let all_lines: Vec<&str> = output.lines().collect();
            for line in all_lines.iter().rev() {
                let trimmed = line.trim();

                // Ignore empty lines
                if trimmed.is_empty() {
                    continue;
                }

                // Ignore pure numbers (token count)
                if trimmed
                    .chars()
                    .all(|c| c.is_numeric() || c == ',' || c.is_whitespace())
                {
                    continue;
                }

                // Ignore known headers
                if trimmed == "tokens used"
                    || trimmed == "codex"
                    || trimmed == "thinking"
                    || trimmed.starts_with("**")
                {
                    continue;
                }

                // This is the response!
                return Ok(trimmed.to_string());
            }

            anyhow::bail!("Failed to parse Codex CLI response");
        }

        Ok(response_lines.join("\n").trim().to_string())
    }

    /// Build prompt from messages
    fn build_prompt(&self, messages: &[Message], system: Option<&str>) -> Result<String> {
        let mut prompt = String::new();

        // Add system prompt if provided
        if let Some(sys) = system {
            prompt.push_str("Context: ");
            prompt.push_str(sys);
            prompt.push_str("\n\n");
        }

        // Add messages
        for msg in messages {
            match msg.role.as_str() {
                "user" => {
                    prompt.push_str(&msg.content);
                    prompt.push('\n');
                }
                "assistant" => {
                    // For multi-turn conversations
                    prompt.push_str("Previous response: ");
                    prompt.push_str(&msg.content);
                    prompt.push_str("\n\n");
                }
                _ => {
                    warn!("Unknown message role: {}", msg.role);
                }
            }
        }

        Ok(prompt)
    }
}

impl Default for CodexCliClient {
    fn default() -> Self {
        Self::new().expect("Failed to create CodexCliClient")
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_check_available() {
        let available = CodexCliClient::check_available();
        println!("Codex CLI available: {}", available);
    }

    #[test]
    fn test_build_prompt() {
        if let Ok(client) = CodexCliClient::new() {
            let messages = vec![Message::user("What is CRISPR?")];
            let prompt = client.build_prompt(&messages, None).unwrap();
            assert!(prompt.contains("What is CRISPR?"));
        }
    }

    #[test]
    fn test_parse_codex_output() {
        if let Ok(client) = CodexCliClient::new() {
            let sample_output = r#"Reading prompt from stdin...
OpenAI Codex v0.46.0 (research preview)
--------
workdir: /tmp
--------
user
What is 2+2?

thinking
Doing simple math
codex
4
tokens used
1234
4"#;

            let result = client.parse_codex_output(sample_output).unwrap();
            assert_eq!(result, "4");
        }
    }
}
