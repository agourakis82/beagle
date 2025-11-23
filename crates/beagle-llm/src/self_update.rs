//! BEAGLE Self-Updating System
//!
//! Uses Claude Code CLI to update itself based on:
//! - User feedback
//! - Performance metrics
//! - Bug reports
//! - Feature requests
//!
//! This enables BEAGLE to continuously improve its own codebase!

use crate::clients::claude_cli::ClaudeCliClient;
use crate::{ChatMessage, LlmClient, LlmRequest};
use std::path::PathBuf;
use tokio::fs;
use tracing::{info, warn};

/// Self-update context
pub struct SelfUpdateContext {
    claude: ClaudeCliClient,
    workspace_root: PathBuf,
}

impl SelfUpdateContext {
    /// Create new self-update context
    pub fn new() -> anyhow::Result<Self> {
        let claude = ClaudeCliClient::new()?;

        // Find workspace root (look for Cargo.toml)
        let workspace_root = std::env::current_dir()?
            .ancestors()
            .find(|p| p.join("Cargo.toml").exists())
            .ok_or_else(|| anyhow::anyhow!("Could not find workspace root"))?
            .to_path_buf();

        Ok(Self {
            claude,
            workspace_root,
        })
    }

    /// Analyze performance metrics and suggest improvements
    pub async fn analyze_metrics(&self, metrics: &str) -> anyhow::Result<String> {
        let prompt = format!(
            "You are BEAGLE's self-improvement AI. Analyze these performance metrics \
             and suggest code improvements:\n\n{}\n\n\
             Provide specific, actionable suggestions with file paths and code snippets.",
            metrics
        );

        let request = LlmRequest {
            model: "claude-sonnet-4.5".to_string(),
            messages: vec![
                ChatMessage::system(
                    "You are an expert Rust developer helping BEAGLE improve itself. \
                     Provide concrete code suggestions.",
                ),
                ChatMessage::user(prompt),
            ],
            temperature: Some(0.3),
            max_tokens: Some(4096),
        };

        self.claude.chat(request).await
    }

    /// Generate code improvements based on issue description
    pub async fn generate_fix(&self, issue: &str, file_path: &str) -> anyhow::Result<String> {
        // Read current file content
        let full_path = self.workspace_root.join(file_path);
        let current_code = fs::read_to_string(&full_path).await?;

        let prompt = format!(
            "Fix this issue in BEAGLE:\n\n\
             Issue: {}\n\n\
             File: {}\n\n\
             Current code:\n```rust\n{}\n```\n\n\
             Provide the complete fixed code.",
            issue, file_path, current_code
        );

        let request = LlmRequest {
            model: "claude-sonnet-4.5".to_string(),
            messages: vec![
                ChatMessage::system(
                    "You are an expert Rust developer. Provide complete, production-ready code fixes."
                ),
                ChatMessage::user(prompt),
            ],
            temperature: Some(0.2),
            max_tokens: Some(8192),
        };

        self.claude.chat(request).await
    }

    /// Implement a new feature
    pub async fn implement_feature(
        &self,
        description: &str,
        target_crate: &str,
    ) -> anyhow::Result<String> {
        let prompt = format!(
            "Implement this feature for BEAGLE:\n\n\
             Feature: {}\n\n\
             Target crate: {}\n\n\
             Provide:\n\
             1. New file paths and complete code\n\
             2. Modifications to existing files\n\
             3. Tests\n\
             4. Documentation",
            description, target_crate
        );

        let request = LlmRequest {
            model: "claude-sonnet-4.5".to_string(),
            messages: vec![
                ChatMessage::system(
                    "You are an expert Rust developer implementing new features for BEAGLE. \
                     Follow Q1 systems-paper quality standards.",
                ),
                ChatMessage::user(prompt),
            ],
            temperature: Some(0.3),
            max_tokens: Some(8192),
        };

        self.claude.chat(request).await
    }

    /// Review code changes before applying
    pub async fn review_changes(
        &self,
        file_path: &str,
        old_code: &str,
        new_code: &str,
    ) -> anyhow::Result<bool> {
        let prompt = format!(
            "Review this code change for BEAGLE:\n\n\
             File: {}\n\n\
             Old code:\n```rust\n{}\n```\n\n\
             New code:\n```rust\n{}\n```\n\n\
             Is this change safe and correct? Answer YES or NO, then explain.",
            file_path, old_code, new_code
        );

        let request = LlmRequest {
            model: "claude-sonnet-4.5".to_string(),
            messages: vec![
                ChatMessage::system(
                    "You are a senior code reviewer. Be strict about correctness and safety.",
                ),
                ChatMessage::user(prompt),
            ],
            temperature: Some(0.1),
            max_tokens: Some(2048),
        };

        let response = self.claude.chat(request).await?;
        Ok(response.to_lowercase().starts_with("yes"))
    }

    /// Apply code changes to file
    pub async fn apply_changes(
        &self,
        file_path: &str,
        new_code: &str,
        dry_run: bool,
    ) -> anyhow::Result<()> {
        let full_path = self.workspace_root.join(file_path);

        if dry_run {
            info!("DRY RUN: Would write to {}", full_path.display());
            info!("Content preview:\n{}", &new_code[..new_code.len().min(200)]);
            return Ok(());
        }

        // Read old code for review
        let old_code = fs::read_to_string(&full_path).await.unwrap_or_default();

        // Review changes
        if !self.review_changes(file_path, &old_code, new_code).await? {
            anyhow::bail!("Code review failed - changes rejected");
        }

        // Create backup
        let backup_path = full_path.with_extension("rs.backup");
        if !old_code.is_empty() {
            fs::write(&backup_path, &old_code).await?;
            info!("Created backup: {}", backup_path.display());
        }

        // Write new code
        fs::write(&full_path, new_code).await?;
        info!("Updated: {}", full_path.display());

        Ok(())
    }

    /// Full self-improvement cycle
    pub async fn self_improve(&self, feedback: &str, dry_run: bool) -> anyhow::Result<Vec<String>> {
        info!("Starting self-improvement cycle...");

        // 1. Analyze feedback
        let analysis = self.analyze_metrics(feedback).await?;
        info!("Analysis:\n{}", analysis);

        // 2. Extract action items (simplified - would parse analysis in real implementation)
        let mut changes_made = Vec::new();

        // For now, just return the analysis
        changes_made.push(format!("Analysis complete:\n{}", analysis));

        if dry_run {
            info!("DRY RUN: No changes applied");
        }

        Ok(changes_made)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[tokio::test]
    #[ignore] // Requires claude CLI
    async fn test_self_update_context() {
        let ctx = SelfUpdateContext::new().unwrap();

        let metrics = "Test latency: 500ms (target: <100ms)\nMemory usage: 2GB (target: <1GB)";
        let analysis = ctx.analyze_metrics(metrics).await.unwrap();

        println!("Analysis: {}", analysis);
        assert!(!analysis.is_empty());
    }

    #[tokio::test]
    #[ignore]
    async fn test_generate_fix() {
        let ctx = SelfUpdateContext::new().unwrap();

        let issue = "Reduce memory allocation in hot loop";
        let file = "src/lib.rs";

        let fix = ctx.generate_fix(issue, file).await.unwrap();
        println!("Generated fix:\n{}", fix);
    }
}
