//! Iterative refinement of synthesized drafts

use crate::{Result, HermesError};
use beagle_llm::{AnthropicClient, CompletionRequest, Message, ModelType};
use std::sync::Arc;
use tracing::{info, debug};

pub struct RefinementEngine {
    llm_client: Arc<AnthropicClient>,
    max_iterations: usize,
}

impl RefinementEngine {
    pub fn new(llm_client: Arc<AnthropicClient>) -> Self {
        Self {
            llm_client,
            max_iterations: 3,
        }
    }

    /// Refine draft based on validation issues
    pub async fn refine(
        &self,
        draft: &str,
        issues: &[crate::agents::argos::Issue],
        original_context: &str,
    ) -> Result<String> {
        if issues.is_empty() {
            return Ok(draft.to_string());
        }

        info!("Refining draft based on {} issues", issues.len());

        // Group issues by type
        let mut transition_issues = Vec::new();
        let mut claim_issues = Vec::new();
        let mut reference_issues = Vec::new();
        let mut grammar_issues = Vec::new();

        for issue in issues {
            match issue.issue_type {
                crate::agents::argos::IssueType::MissingTransition => {
                    transition_issues.push(&issue.description);
                }
                crate::agents::argos::IssueType::UnsupportedClaim => {
                    claim_issues.push(&issue.description);
                }
                crate::agents::argos::IssueType::UnclearReference => {
                    reference_issues.push(&issue.description);
                }
                crate::agents::argos::IssueType::GrammaticalError => {
                    grammar_issues.push(&issue.description);
                }
            }
        }

        // Build refinement prompt
        let mut refinement_instructions = String::new();

        if !transition_issues.is_empty() {
            refinement_instructions.push_str("TRANSITION ISSUES:\n");
            for issue in &transition_issues {
                refinement_instructions.push_str(&format!("- {}\n", issue));
            }
            refinement_instructions.push_str("Action: Add appropriate transition words or phrases.\n\n");
        }

        if !claim_issues.is_empty() {
            refinement_instructions.push_str("UNSUPPORTED CLAIMS:\n");
            for issue in &claim_issues {
                refinement_instructions.push_str(&format!("- {}\n", issue));
            }
            refinement_instructions.push_str("Action: Add citations [X] to support these claims.\n\n");
        }

        if !reference_issues.is_empty() {
            refinement_instructions.push_str("UNCLEAR REFERENCES:\n");
            for issue in &reference_issues {
                refinement_instructions.push_str(&format!("- {}\n", issue));
            }
            refinement_instructions.push_str("Action: Clarify pronoun references or replace with explicit nouns.\n\n");
        }

        if !grammar_issues.is_empty() {
            refinement_instructions.push_str("GRAMMATICAL ISSUES:\n");
            for issue in &grammar_issues {
                refinement_instructions.push_str(&format!("- {}\n", issue));
            }
            refinement_instructions.push_str("Action: Fix grammatical errors.\n\n");
        }

        let prompt = format!(
            r#"You are an expert scientific editor. Refine the following draft based on the issues identified.

ORIGINAL CONTEXT:
{}

CURRENT DRAFT:
{}

ISSUES TO FIX:
{}

INSTRUCTIONS:
1. Fix all identified issues
2. Maintain the original meaning and scientific rigor
3. Preserve the author's voice and writing style
4. Do not add new content beyond fixing the issues
5. Return the refined draft in markdown format

REFINED DRAFT:
"#,
            original_context,
            draft,
            refinement_instructions
        );

        let request = CompletionRequest {
            model: ModelType::ClaudeSonnet45,
            messages: vec![Message::user(prompt)],
            max_tokens: (draft.len() as f64 * 1.2) as u32, // 20% buffer
            temperature: 0.3, // Lower temperature for refinement
            system: Some("You are an expert scientific editor specializing in academic writing refinement.".to_string()),
        };

        let response = self.llm_client.complete(request).await
            .map_err(|e| HermesError::LLMError(e))?;

        info!("Draft refined: {} -> {} chars", draft.len(), response.content.len());
        Ok(response.content)
    }

    /// Iterative refinement loop
    pub async fn refine_iteratively(
        &self,
        mut draft: String,
        original_context: &str,
        validation_fn: impl Fn(&str) -> Result<Vec<crate::agents::argos::Issue>>,
    ) -> Result<String> {
        for iteration in 1..=self.max_iterations {
            debug!("Refinement iteration {}/{}", iteration, self.max_iterations);

            // Validate current draft
            let issues = validation_fn(&draft)?;

            if issues.is_empty() {
                info!("Draft meets quality standards after {} iterations", iteration);
                break;
            }

            // Refine based on issues
            draft = self.refine(&draft, &issues, original_context).await?;
        }

        Ok(draft)
    }
}

