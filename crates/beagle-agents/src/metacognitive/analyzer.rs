use super::monitor::PerformanceMonitor;
use anyhow::Result;
use beagle_llm::{AnthropicClient, CompletionRequest, Message, ModelType};
use serde::{Deserialize, Serialize};
use std::sync::Arc;
use tracing::info;

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct FailurePattern {
    pub pattern_type: String,
    pub description: String,
    pub frequency: usize,
    pub example_queries: Vec<String>,
    pub recommended_fix: String,
}

pub struct WeaknessAnalyzer {
    llm: Arc<AnthropicClient>,
}

impl WeaknessAnalyzer {
    pub fn new(llm: Arc<AnthropicClient>) -> Self {
        Self { llm }
    }

    pub async fn analyze_failures(
        &self,
        monitor: &PerformanceMonitor,
    ) -> Result<Vec<FailurePattern>> {
        info!("🔍 Analyzing failure patterns...");

        let failures = monitor.get_failures(50);

        if failures.is_empty() {
            return Ok(vec![]);
        }

        // Group failures by characteristics
        let failure_summary = failures
            .iter()
            .map(|f| {
                format!(
                    "Query: {} | Domain: {} | Error: {} | Quality: {:.2}",
                    &f.query[..50.min(f.query.len())],
                    f.domain,
                    f.error.as_ref().unwrap_or(&"low_quality".to_string()),
                    f.quality_score
                )
            })
            .collect::<Vec<_>>()
            .join("\n");

        let prompt = format!(
            "Analyze these query failures and identify patterns:\n\n{}\n\n\
             Identify 3-5 distinct failure patterns. For each pattern:\n\
             1. Pattern type (e.g., 'Complex causal queries', 'Multi-domain integration')\n\
             2. Description of the pattern\n\
             3. Why the system struggles\n\
             4. Recommended architectural improvement\n\n\
             Format as JSON array:\n\
             [{{\n  \
               \"pattern_type\": \"...\",\n  \
               \"description\": \"...\",\n  \
               \"recommended_fix\": \"...\"\n\
             }}]",
            failure_summary
        );

        let request = CompletionRequest {
            model: ModelType::ClaudeSonnet4,
            messages: vec![Message::user(prompt)],
            max_tokens: 2000,
            temperature: 0.3,
            system: Some("You are an AI systems analyst identifying failure patterns.".to_string()),
        };

        let response = self.llm.complete(request).await?;

        // Parse JSON
        let content = response.content.trim();
        let json_content = if content.contains("```json") {
            content
                .lines()
                .skip_while(|l| !l.contains('['))
                .take_while(|l| !l.starts_with("```"))
                .collect::<Vec<_>>()
                .join("\n")
        } else {
            content.to_string()
        };

        #[derive(Deserialize)]
        struct PatternData {
            pattern_type: String,
            description: String,
            recommended_fix: String,
        }

        let patterns: Vec<PatternData> =
            serde_json::from_str(&json_content).unwrap_or_else(|_| vec![]);

        let failure_patterns: Vec<FailurePattern> = patterns
            .into_iter()
            .map(|p| FailurePattern {
                pattern_type: p.pattern_type,
                description: p.description,
                frequency: 1,
                example_queries: vec![],
                recommended_fix: p.recommended_fix,
            })
            .collect();

        info!("✅ Identified {} failure patterns", failure_patterns.len());

        Ok(failure_patterns)
    }

    pub async fn identify_missing_capabilities(
        &self,
        patterns: &[FailurePattern],
    ) -> Result<Vec<String>> {
        let patterns_summary = patterns
            .iter()
            .map(|p| format!("{}: {}", p.pattern_type, p.recommended_fix))
            .collect::<Vec<_>>()
            .join("\n");

        let prompt = format!(
            "Based on these failure patterns:\n\n{}\n\n\
             What specialized agent capabilities are missing?\n\
             List 3-5 specific agent types that should be created.\n\
             Format as JSON array of strings: [\"agent_type_1\", \"agent_type_2\", ...]",
            patterns_summary
        );

        let request = CompletionRequest {
            model: ModelType::ClaudeSonnet4,
            messages: vec![Message::user(prompt)],
            max_tokens: 500,
            temperature: 0.5,
            system: Some("You are an AI architect designing specialized agents.".to_string()),
        };

        let response = self.llm.complete(request).await?;

        let capabilities: Vec<String> = serde_json::from_str(response.content.trim())
            .unwrap_or_else(|_| vec!["GeneralizedAgent".to_string()]);

        Ok(capabilities)
    }
}
