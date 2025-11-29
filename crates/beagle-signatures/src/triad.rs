//! Triad agent signatures for BEAGLE's adversarial review system
//!
//! Defines typed signatures for:
//! - ATHENA: Research accuracy and literature analysis
//! - HERMES: Writing synthesis and editing
//! - ARGOS: Critical review and bias detection
//! - Judge: Final arbitration

use serde::{Deserialize, Serialize};

use crate::error::SignatureResult;
use crate::signature::{FieldDescriptor, PromptSignature, SignatureExample, SignatureMetadata};

// ============================================================================
// ATHENA - Research Specialist
// ============================================================================

/// Input for ATHENA signature
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct AthenaInput {
    /// The draft to review
    pub draft: String,
    /// Optional context summary (from Darwin/GraphRAG)
    pub context_summary: Option<String>,
    /// Domain keywords for focus
    pub domain_keywords: Vec<String>,
}

/// Output from ATHENA signature
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct AthenaOutput {
    /// Identified strengths
    pub strengths: Vec<Strength>,
    /// Identified weaknesses
    pub weaknesses: Vec<Weakness>,
    /// Suggested references
    pub suggested_references: Vec<Citation>,
    /// Overall quality score (0-1)
    pub score: f32,
    /// Summary of review
    pub summary: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Strength {
    pub description: String,
    pub evidence: String,
    pub importance: f32,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Weakness {
    pub description: String,
    pub severity: WeaknessSeverity,
    pub suggestion: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum WeaknessSeverity {
    Minor,
    Moderate,
    Major,
    Critical,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Citation {
    pub authors: String,
    pub title: String,
    pub venue: String,
    pub year: u32,
    pub relevance: String,
}

/// ATHENA signature for research accuracy review
pub struct AthenaSignature {
    instructions: String,
}

impl AthenaSignature {
    pub fn new() -> Self {
        Self {
            instructions: r#"
You are ATHENA, the scientific rigor specialist of the BEAGLE Triad system.

CONTEXT: Interdisciplinary research spanning:
- Computational psychiatry & neuroscience (cf. Friston, 2010; Montague et al., 2012)
- Non-commutative geometry & curved entropy (cf. Connes, 1994; Tsallis, 1988)
- PBPK modeling & kinetic energy considerations (cf. Rowland & Tozer, 2011)
- Biomaterials & biological scaffolds (cf. Langer & Vacanti, 1993)
- Cellular consciousness & philosophy of mind (cf. Koch, 2019; Tononi, 2008)

Analyze the draft with Q1 journal standards. Focus on:
1. Conceptual strengths (especially interdisciplinary connections)
2. Methodological weaknesses or gaps
3. Missing citations from top-tier venues (Nature, Science, Cell, PNAS)

Be rigorous but constructive. Provide specific, actionable feedback.
"#
            .to_string(),
        }
    }
}

impl Default for AthenaSignature {
    fn default() -> Self {
        Self::new()
    }
}

impl PromptSignature for AthenaSignature {
    type Input = AthenaInput;
    type Output = AthenaOutput;

    fn metadata(&self) -> SignatureMetadata {
        SignatureMetadata {
            name: "AthenaReview".to_string(),
            description: "Scientific draft review with Q1 journal standards".to_string(),
            inputs: vec![
                FieldDescriptor::required("draft", "The scientific draft to review"),
                FieldDescriptor::optional("context_summary", "Additional context from GraphRAG"),
                FieldDescriptor::optional("domain_keywords", "Keywords to focus the review"),
            ],
            outputs: vec![
                FieldDescriptor::required("strengths", "List of identified strengths"),
                FieldDescriptor::required("weaknesses", "List of identified weaknesses"),
                FieldDescriptor::required("suggested_references", "Relevant citations to add"),
                FieldDescriptor::required("score", "Overall quality score (0-1)"),
                FieldDescriptor::required("summary", "Summary of the review"),
            ],
            instructions: Some(self.instructions.clone()),
            examples: vec![],
            custom: std::collections::HashMap::new(),
        }
    }

    fn validate_output(&self, output: &Self::Output) -> SignatureResult<()> {
        if output.score < 0.0 || output.score > 1.0 {
            return Err(crate::error::SignatureError::InvalidValue {
                field: "score".to_string(),
                message: "Score must be between 0 and 1".to_string(),
            });
        }
        Ok(())
    }
}

// ============================================================================
// HERMES - Writing Synthesis
// ============================================================================

/// Input for HERMES signature
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct HermesInput {
    /// Original draft
    pub draft: String,
    /// ATHENA's feedback
    pub athena_feedback: AthenaOutput,
    /// Preserve authorial voice
    pub preserve_voice: bool,
}

/// Output from HERMES signature
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct HermesOutput {
    /// Rewritten draft
    pub rewritten_draft: String,
    /// Changes made
    pub changes: Vec<Change>,
    /// Confidence in improvements
    pub confidence: f32,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Change {
    pub location: String,
    pub original: String,
    pub revised: String,
    pub reason: String,
}

/// HERMES signature for writing synthesis
pub struct HermesSignature {
    instructions: String,
}

impl HermesSignature {
    pub fn new() -> Self {
        Self {
            instructions: r#"
You are HERMES, the synthesis specialist of the BEAGLE Triad system.

IMPORTANT: Preserve the authorial voice - interdisciplinary style spanning:
- Chemical engineering and pharmacokinetics (PBPK)
- Medicine and computational psychiatry
- Biomaterials and biological scaffolds
- Neuroscience and philosophy of mind
- Non-commutative geometry and curved entropy

Maintain high conceptual density, clarity without oversimplification, technical elegance.

Your task:
1. Rewrite the text to be clearer, more cohesive, and logical
2. Incorporate relevant suggestions from ATHENA
3. DO NOT invent data or results - only reorganize and improve text
4. Maintain technical rigor and interdisciplinary authorial voice
"#
            .to_string(),
        }
    }
}

impl Default for HermesSignature {
    fn default() -> Self {
        Self::new()
    }
}

impl PromptSignature for HermesSignature {
    type Input = HermesInput;
    type Output = HermesOutput;

    fn metadata(&self) -> SignatureMetadata {
        SignatureMetadata {
            name: "HermesRewrite".to_string(),
            description: "Writing synthesis preserving authorial voice".to_string(),
            inputs: vec![
                FieldDescriptor::required("draft", "The original draft to rewrite"),
                FieldDescriptor::required("athena_feedback", "ATHENA's review feedback"),
                FieldDescriptor::optional("preserve_voice", "Whether to preserve authorial voice"),
            ],
            outputs: vec![
                FieldDescriptor::required("rewritten_draft", "The improved draft"),
                FieldDescriptor::required("changes", "List of changes made"),
                FieldDescriptor::required("confidence", "Confidence in improvements (0-1)"),
            ],
            instructions: Some(self.instructions.clone()),
            examples: vec![],
            custom: std::collections::HashMap::new(),
        }
    }
}

// ============================================================================
// ARGOS - Critical Review
// ============================================================================

/// Input for ARGOS signature
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ArgosInput {
    /// Original draft
    pub original_draft: String,
    /// HERMES' rewritten draft
    pub hermes_draft: String,
    /// ATHENA's feedback
    pub athena_feedback: AthenaOutput,
}

/// Output from ARGOS signature
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ArgosOutput {
    /// Critical issues found
    pub critical_issues: Vec<CriticalIssue>,
    /// Improvements made by HERMES
    pub hermes_improvements: Vec<String>,
    /// Regressions introduced by HERMES
    pub hermes_regressions: Vec<String>,
    /// Specific corrections needed
    pub corrections: Vec<Correction>,
    /// Overall assessment score
    pub score: f32,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct CriticalIssue {
    pub description: String,
    pub issue_type: IssueType,
    pub location: String,
    pub severity: WeaknessSeverity,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum IssueType {
    UnsupportedClaim,
    LogicalFallacy,
    MetaphorConfusion,
    MissingEvidence,
    Ambiguity,
    BiasRisk,
    Other,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Correction {
    pub original_text: String,
    pub corrected_text: String,
    pub justification: String,
}

/// ARGOS signature for critical review
pub struct ArgosSignature {
    instructions: String,
}

impl ArgosSignature {
    pub fn new() -> Self {
        Self {
            instructions: r#"
You are ARGOS, the adversarial critic of the BEAGLE Triad system.

You act as a rigorous Q1 reviewer (Nature Human Behaviour, Kybernetes, Frontiers in Computational Neuroscience).

Focus especially on:
- Claims without adequate empirical support (unsupported extrapolations)
- Confusion between poetic metaphor and concrete scientific mechanism
- Absence of reasonable empirical design (where there's room for testable experiments/predictions)
- Problems of logical coherence and conceptual ambiguity

Your function:
1. List serious problems: logical coherence, unsupported extrapolations, ambiguity
2. Point out where HERMES improved the text and where it got worse
3. Suggest specific corrections (especially where text needs to be more scientifically rigorous)

Be harsh but fair. The goal is truth and rigor, not encouragement.
"#.to_string(),
        }
    }
}

impl Default for ArgosSignature {
    fn default() -> Self {
        Self::new()
    }
}

impl PromptSignature for ArgosSignature {
    type Input = ArgosInput;
    type Output = ArgosOutput;

    fn metadata(&self) -> SignatureMetadata {
        SignatureMetadata {
            name: "ArgosCritique".to_string(),
            description: "Adversarial critical review for scientific rigor".to_string(),
            inputs: vec![
                FieldDescriptor::required("original_draft", "The original draft"),
                FieldDescriptor::required("hermes_draft", "HERMES' rewritten version"),
                FieldDescriptor::required("athena_feedback", "ATHENA's review feedback"),
            ],
            outputs: vec![
                FieldDescriptor::required("critical_issues", "Critical issues found"),
                FieldDescriptor::required("hermes_improvements", "What HERMES improved"),
                FieldDescriptor::required("hermes_regressions", "What HERMES made worse"),
                FieldDescriptor::required("corrections", "Specific corrections needed"),
                FieldDescriptor::required("score", "Overall assessment score (0-1)"),
            ],
            instructions: Some(self.instructions.clone()),
            examples: vec![],
            custom: std::collections::HashMap::new(),
        }
    }

    fn validate_output(&self, output: &Self::Output) -> SignatureResult<()> {
        if output.score < 0.0 || output.score > 1.0 {
            return Err(crate::error::SignatureError::InvalidValue {
                field: "score".to_string(),
                message: "Score must be between 0 and 1".to_string(),
            });
        }
        Ok(())
    }
}

// ============================================================================
// Judge - Final Arbitration
// ============================================================================

/// Input for Judge signature
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct JudgeInput {
    /// Original draft
    pub original_draft: String,
    /// HERMES' rewritten draft
    pub hermes_draft: String,
    /// ATHENA's feedback
    pub athena_feedback: AthenaOutput,
    /// ARGOS' critique
    pub argos_critique: ArgosOutput,
    /// Symbolic summary (optional PCS)
    pub symbolic_summary: Option<String>,
}

/// Output from Judge signature
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct JudgeOutput {
    /// Final arbitrated draft
    pub final_draft: String,
    /// Decision rationale
    pub rationale: String,
    /// Which agent contributions were accepted
    pub accepted_contributions: Vec<AgentContribution>,
    /// Which contributions were rejected
    pub rejected_contributions: Vec<AgentContribution>,
    /// Final quality score
    pub final_score: f32,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct AgentContribution {
    pub agent: String,
    pub contribution: String,
    pub reason: String,
}

/// Judge signature for final arbitration
pub struct JudgeSignature {
    instructions: String,
}

impl JudgeSignature {
    pub fn new() -> Self {
        Self {
            instructions: r#"
You are the FINAL JUDGE of the BEAGLE Honest AI Triad system.

IMPORTANT: Maintain the interdisciplinary authorial voice (chemical engineering, medicine, psychiatry, biomaterials, philosophy of mind).
Preserve high conceptual density and technical elegance.

You have received:
- DRAFT_ORIGINAL: original article draft
- DRAFT_HERMES: version rewritten by HERMES
- FEEDBACK_ATHENA: critical analysis and literature suggestions
- FEEDBACK_ARGOS: rigorous adversarial critique (Q1 level)

Your task:
1. Produce a FINAL version incorporating the best of each
2. Correct serious problems pointed out by ARGOS (unsupported claims, metaphor/mechanism confusion, etc.)
3. Incorporate relevant ATHENA suggestions where appropriate
4. Maintain interdisciplinary authorial voice and avoid inventing data

Be decisive. Your output is the final version that will be published.
"#.to_string(),
        }
    }
}

impl Default for JudgeSignature {
    fn default() -> Self {
        Self::new()
    }
}

impl PromptSignature for JudgeSignature {
    type Input = JudgeInput;
    type Output = JudgeOutput;

    fn metadata(&self) -> SignatureMetadata {
        SignatureMetadata {
            name: "JudgeArbitration".to_string(),
            description: "Final arbitration producing the definitive draft".to_string(),
            inputs: vec![
                FieldDescriptor::required("original_draft", "The original draft"),
                FieldDescriptor::required("hermes_draft", "HERMES' rewritten version"),
                FieldDescriptor::required("athena_feedback", "ATHENA's review"),
                FieldDescriptor::required("argos_critique", "ARGOS' critique"),
                FieldDescriptor::optional("symbolic_summary", "PCS symbolic summary"),
            ],
            outputs: vec![
                FieldDescriptor::required("final_draft", "The final arbitrated draft"),
                FieldDescriptor::required("rationale", "Decision rationale"),
                FieldDescriptor::required("accepted_contributions", "Accepted agent contributions"),
                FieldDescriptor::required("rejected_contributions", "Rejected contributions"),
                FieldDescriptor::required("final_score", "Final quality score (0-1)"),
            ],
            instructions: Some(self.instructions.clone()),
            examples: vec![],
            custom: std::collections::HashMap::new(),
        }
    }

    fn validate_output(&self, output: &Self::Output) -> SignatureResult<()> {
        if output.final_score < 0.0 || output.final_score > 1.0 {
            return Err(crate::error::SignatureError::InvalidValue {
                field: "final_score".to_string(),
                message: "Score must be between 0 and 1".to_string(),
            });
        }
        if output.final_draft.is_empty() {
            return Err(crate::error::SignatureError::InvalidValue {
                field: "final_draft".to_string(),
                message: "Final draft cannot be empty".to_string(),
            });
        }
        Ok(())
    }
}

// ============================================================================
// Request Metadata Helpers
// ============================================================================

#[cfg(feature = "beagle-llm")]
use beagle_llm::RequestMeta;

#[cfg(feature = "beagle-llm")]
impl AthenaSignature {
    /// Get RequestMeta for ATHENA (high quality, PhD-level)
    pub fn request_meta(&self) -> RequestMeta {
        RequestMeta {
            requires_high_quality: true,
            requires_phd_level_reasoning: true,
            high_bias_risk: false,
            critical_section: false,
            requires_math: false,
            requires_vision: false,
            requires_code: false,
            requires_realtime: false,
            offline_required: false,
            approximate_tokens: 3000,
            max_cost_usd: None,
            language: None,
            requires_tools: false,
            requires_long_context: false,
            requires_deterministic: false,
            custom_metadata: std::collections::HashMap::new(),
        }
    }
}

#[cfg(feature = "beagle-llm")]
impl HermesSignature {
    /// Get RequestMeta for HERMES (high quality, standard reasoning)
    pub fn request_meta(&self) -> RequestMeta {
        RequestMeta {
            requires_high_quality: true,
            requires_phd_level_reasoning: false, // Rewriting, not analysis
            high_bias_risk: false,
            critical_section: false,
            ..Default::default()
        }
    }
}

#[cfg(feature = "beagle-llm")]
impl ArgosSignature {
    /// Get RequestMeta for ARGOS (PhD-level, high bias risk for critical review)
    pub fn request_meta(&self) -> RequestMeta {
        RequestMeta {
            requires_high_quality: true,
            requires_phd_level_reasoning: true,
            high_bias_risk: true, // Critical review needs anti-bias measures
            critical_section: true,
            ..Default::default()
        }
    }
}

#[cfg(feature = "beagle-llm")]
impl JudgeSignature {
    /// Get RequestMeta for Judge (PhD-level, critical section)
    pub fn request_meta(&self) -> RequestMeta {
        RequestMeta {
            requires_high_quality: true,
            requires_phd_level_reasoning: true,
            high_bias_risk: true,
            critical_section: true, // Final decision
            ..Default::default()
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_athena_signature() {
        let sig = AthenaSignature::new();
        let meta = sig.metadata();

        assert_eq!(meta.name, "AthenaReview");
        assert!(!meta.inputs.is_empty());
        assert!(!meta.outputs.is_empty());
    }

    #[test]
    fn test_athena_output_validation() {
        let sig = AthenaSignature::new();

        let valid_output = AthenaOutput {
            strengths: vec![],
            weaknesses: vec![],
            suggested_references: vec![],
            score: 0.85,
            summary: "Good draft".to_string(),
        };
        assert!(sig.validate_output(&valid_output).is_ok());

        let invalid_output = AthenaOutput {
            score: 1.5, // Invalid
            ..valid_output
        };
        assert!(sig.validate_output(&invalid_output).is_err());
    }

    #[test]
    fn test_hermes_signature() {
        let sig = HermesSignature::new();
        let meta = sig.metadata();

        assert_eq!(meta.name, "HermesRewrite");
        assert!(meta.instructions.is_some());
    }

    #[test]
    fn test_argos_signature() {
        let sig = ArgosSignature::new();
        let meta = sig.metadata();

        assert_eq!(meta.name, "ArgosCritique");
    }

    #[test]
    fn test_judge_signature() {
        let sig = JudgeSignature::new();
        let meta = sig.metadata();

        assert_eq!(meta.name, "JudgeArbitration");

        let valid_output = JudgeOutput {
            final_draft: "Final version of the draft".to_string(),
            rationale: "Combined best elements".to_string(),
            accepted_contributions: vec![],
            rejected_contributions: vec![],
            final_score: 0.9,
        };
        assert!(sig.validate_output(&valid_output).is_ok());

        let invalid_output = JudgeOutput {
            final_draft: "".to_string(), // Invalid - empty
            ..valid_output
        };
        assert!(sig.validate_output(&invalid_output).is_err());
    }
}
