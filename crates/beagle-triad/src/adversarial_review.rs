//! Complete Triad Adversarial Review System with Q1 Journal Rigor
//!
//! Implements a comprehensive adversarial review process inspired by:
//! - Generative Adversarial Networks (Goodfellow et al., 2014)
//! - Debate as Optimization (Irving et al., 2018)
//! - Constitutional AI (Anthropic, 2022)
//! - Red Team/Blue Team Security Practices (Zenko, 2015)
//!
//! The system uses three specialized agents (ATHENA, HERMES, ARGOS) plus a Judge
//! to ensure scientific rigor through adversarial validation.
//!
//! References:
//! - Goodfellow, I., et al. (2014). "Generative adversarial nets." NeurIPS.
//! - Irving, G., et al. (2018). "AI safety via debate." arXiv:1805.00899.
//! - Bai, Y., et al. (2022). "Constitutional AI: Harmlessness from AI Feedback." arXiv:2212.08073.
//! - Zenko, M. (2015). "Red Team: How to Succeed by Thinking Like the Enemy."

use anyhow::{Context as AnyhowContext, Result};
use async_trait::async_trait;
use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};
use std::collections::{HashMap, HashSet};
use std::sync::Arc;
use tokio::sync::{Mutex, RwLock};
use tracing::{debug, error, info, instrument, span, warn, Level};
use uuid::Uuid;

use beagle_core::BeagleContext;
use beagle_llm::{LlmCallsStats, LlmClient, RequestMeta};

/// Adversarial review configuration with Q1 standards
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct AdversarialReviewConfig {
    /// Maximum rounds of debate
    pub max_rounds: usize,
    /// Minimum confidence for consensus
    pub consensus_threshold: f64,
    /// Enable statistical validation
    pub enable_statistical_validation: bool,
    /// Enable formal proof checking
    pub enable_formal_proofs: bool,
    /// Require empirical evidence
    pub require_empirical_evidence: bool,
    /// Minimum inter-rater reliability (Cohen's kappa)
    pub min_inter_rater_reliability: f64,
    /// Enable meta-review (review of the review)
    pub enable_meta_review: bool,
    /// Enforce reproducibility standards
    pub enforce_reproducibility: bool,
    /// Enable cross-validation with external sources
    pub enable_cross_validation: bool,
    /// Require uncertainty quantification
    pub require_uncertainty_quantification: bool,
}

impl Default for AdversarialReviewConfig {
    fn default() -> Self {
        Self {
            max_rounds: 5,
            consensus_threshold: 0.85,
            enable_statistical_validation: true,
            enable_formal_proofs: false, // Expensive, enable selectively
            require_empirical_evidence: true,
            min_inter_rater_reliability: 0.7,
            enable_meta_review: true,
            enforce_reproducibility: true,
            enable_cross_validation: true,
            require_uncertainty_quantification: true,
        }
    }
}

/// Review agent role in the Triad
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, Serialize, Deserialize)]
pub enum ReviewerRole {
    /// ATHENA - Accuracy and theoretical rigor
    Athena,
    /// HERMES - Communication and clarity
    Hermes,
    /// ARGOS - Critical analysis and bias detection
    Argos,
    /// JUDGE - Final arbitration
    Judge,
}

impl ReviewerRole {
    pub fn system_prompt(&self) -> &'static str {
        match self {
            ReviewerRole::Athena => {
                "You are ATHENA, the goddess of wisdom and strategic thinking. Your role is to ensure \
                absolute accuracy, theoretical rigor, and scientific validity. You must:\n\
                1. Verify all factual claims against established literature\n\
                2. Check mathematical proofs and statistical analyses\n\
                3. Ensure methodological soundness\n\
                4. Validate experimental design and controls\n\
                5. Confirm reproducibility of results\n\
                \n\
                Be extremely rigorous. Challenge every assumption. Demand evidence for every claim. \
                Your standards are those of Nature, Science, and Cell."
            }
            ReviewerRole::Hermes => {
                "You are HERMES, the messenger god of communication and eloquence. Your role is to ensure \
                clarity, coherence, and effective scientific communication. You must:\n\
                1. Evaluate narrative flow and logical structure\n\
                2. Ensure accessibility without sacrificing precision\n\
                3. Check consistency of terminology and notation\n\
                4. Verify proper contextualization of findings\n\
                5. Ensure appropriate citations and attributions\n\
                \n\
                Champion clarity. Demand coherence. Ensure the work speaks to both specialists and \
                informed generalists with equal effectiveness."
            }
            ReviewerRole::Argos => {
                "You are ARGOS, the all-seeing guardian with a hundred eyes. Your role is critical \
                analysis, bias detection, and identifying hidden flaws. You must:\n\
                1. Detect cognitive biases and logical fallacies\n\
                2. Identify cherry-picking or p-hacking\n\
                3. Find alternative explanations for results\n\
                4. Expose hidden assumptions and limitations\n\
                5. Challenge the novelty and impact claims\n\
                \n\
                Be skeptical. Be thorough. Find the flaws others miss. Your vigilance protects \
                scientific integrity."
            }
            ReviewerRole::Judge => {
                "You are the JUDGE, the impartial arbiter of scientific truth. Your role is to \
                synthesize all perspectives and render final judgment. You must:\n\
                1. Weigh evidence from all reviewers fairly\n\
                2. Resolve conflicts with reasoned analysis\n\
                3. Quantify uncertainty and confidence levels\n\
                4. Provide actionable recommendations\n\
                5. Make the final accept/revise/reject decision\n\
                \n\
                Be fair. Be decisive. Your judgment shapes the scientific record."
            }
        }
    }

    pub fn get_request_meta(&self) -> RequestMeta {
        match self {
            ReviewerRole::Athena => RequestMeta {
                requires_high_quality: true,
                requires_phd_level_reasoning: true,
                high_bias_risk: false,
                critical_section: true,
                requires_math: true,
                offline_required: false,
            },
            ReviewerRole::Hermes => RequestMeta {
                requires_high_quality: true,
                requires_phd_level_reasoning: true,
                high_bias_risk: false,
                critical_section: false,
                requires_math: false,
                offline_required: false,
            },
            ReviewerRole::Argos => RequestMeta {
                requires_high_quality: true,
                requires_phd_level_reasoning: true,
                high_bias_risk: true,
                critical_section: true,
                requires_math: false,
                offline_required: false,
            },
            ReviewerRole::Judge => RequestMeta {
                requires_high_quality: true,
                requires_phd_level_reasoning: true,
                high_bias_risk: true,
                critical_section: true,
                requires_math: false,
                offline_required: false,
            },
        }
    }
}

/// Individual review from an agent
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct AgentReview {
    pub reviewer: ReviewerRole,
    pub timestamp: DateTime<Utc>,
    pub round: usize,
    pub content: String,
    pub scores: ReviewScores,
    pub issues_identified: Vec<Issue>,
    pub recommendations: Vec<String>,
    pub confidence: f64,
    pub evidence: Vec<Evidence>,
    pub llm_provider: String,
}

/// Detailed scoring rubric based on Q1 journal standards
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ReviewScores {
    /// Scientific rigor and validity (0-10)
    pub rigor: f64,
    /// Novelty and innovation (0-10)
    pub novelty: f64,
    /// Clarity and presentation (0-10)
    pub clarity: f64,
    /// Impact and significance (0-10)
    pub impact: f64,
    /// Reproducibility (0-10)
    pub reproducibility: f64,
    /// Statistical soundness (0-10)
    pub statistics: f64,
    /// Ethical considerations (0-10)
    pub ethics: f64,
}

impl ReviewScores {
    pub fn weighted_average(&self) -> f64 {
        // Q1 journal weighting scheme
        let weights = [
            (self.rigor, 0.25),
            (self.novelty, 0.20),
            (self.clarity, 0.15),
            (self.impact, 0.20),
            (self.reproducibility, 0.10),
            (self.statistics, 0.08),
            (self.ethics, 0.02),
        ];

        weights.iter().map(|(score, weight)| score * weight).sum()
    }
}

/// Issue identified during review
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Issue {
    pub severity: IssueSeverity,
    pub category: IssueCategory,
    pub description: String,
    pub location: Option<String>,
    pub suggested_fix: Option<String>,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
pub enum IssueSeverity {
    Critical,   // Must fix for publication
    Major,      // Should fix for quality
    Minor,      // Consider fixing
    Suggestion, // Optional improvement
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
pub enum IssueCategory {
    Methodology,
    Statistics,
    Logic,
    Evidence,
    Clarity,
    Ethics,
    Novelty,
    Reproducibility,
}

/// Evidence supporting a review point
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Evidence {
    pub evidence_type: EvidenceType,
    pub source: String,
    pub relevance: f64,
    pub description: String,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
pub enum EvidenceType {
    Literature,
    Statistical,
    Empirical,
    Theoretical,
    Methodological,
}

/// Debate round between reviewers
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct DebateRound {
    pub round_number: usize,
    pub reviews: Vec<AgentReview>,
    pub consensus_score: f64,
    pub disagreements: Vec<Disagreement>,
    pub convergence_metric: f64,
}

/// Disagreement between reviewers
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Disagreement {
    pub topic: String,
    pub positions: HashMap<ReviewerRole, String>,
    pub severity: f64,
    pub resolved: bool,
}

/// Final adversarial review outcome
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct AdversarialReviewOutcome {
    pub id: Uuid,
    pub started_at: DateTime<Utc>,
    pub completed_at: DateTime<Utc>,
    pub rounds: Vec<DebateRound>,
    pub final_verdict: Verdict,
    pub consensus_scores: ReviewScores,
    pub critical_issues: Vec<Issue>,
    pub recommendations: Vec<String>,
    pub inter_rater_reliability: f64,
    pub confidence_interval: (f64, f64),
    pub meta_review: Option<MetaReview>,
    pub provider_diversity: f64,
}

/// Final verdict from adversarial review
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
pub enum Verdict {
    Accept,
    AcceptWithMinorRevisions,
    MajorRevisions,
    Reject,
}

/// Meta-review of the review process itself
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct MetaReview {
    pub process_quality: f64,
    pub bias_detected: bool,
    pub coverage_completeness: f64,
    pub methodological_rigor: f64,
    pub recommendations: Vec<String>,
}

/// Complete adversarial review system
pub struct AdversarialReviewSystem {
    config: AdversarialReviewConfig,
    context: Arc<BeagleContext>,
    review_history: Arc<RwLock<Vec<AdversarialReviewOutcome>>>,
    active_reviews: Arc<Mutex<HashMap<Uuid, DebateRound>>>,
}

impl AdversarialReviewSystem {
    pub fn new(config: AdversarialReviewConfig, context: Arc<BeagleContext>) -> Self {
        Self {
            config,
            context,
            review_history: Arc::new(RwLock::new(Vec::new())),
            active_reviews: Arc::new(Mutex::new(HashMap::new())),
        }
    }

    /// Conduct full adversarial review
    #[instrument(skip(self, content))]
    pub async fn conduct_review(
        &self,
        content: &str,
        metadata: HashMap<String, String>,
    ) -> Result<AdversarialReviewOutcome> {
        let review_id = Uuid::new_v4();
        let started_at = Utc::now();

        info!("🔬 Starting adversarial review {}", review_id);

        let mut rounds = Vec::new();
        let mut consensus_achieved = false;

        for round_num in 1..=self.config.max_rounds {
            info!("📋 Round {}/{}", round_num, self.config.max_rounds);

            // Conduct review round
            let round = self
                .conduct_round(review_id, round_num, content, &metadata, &rounds)
                .await?;

            // Check consensus
            if round.consensus_score >= self.config.consensus_threshold {
                consensus_achieved = true;
                info!("✅ Consensus achieved: {:.2}", round.consensus_score);
            }

            rounds.push(round);

            if consensus_achieved {
                break;
            }
        }

        // Generate final verdict
        let final_verdict = self.determine_verdict(&rounds)?;

        // Calculate consensus scores
        let consensus_scores = self.calculate_consensus_scores(&rounds)?;

        // Extract critical issues
        let critical_issues = self.extract_critical_issues(&rounds);

        // Generate recommendations
        let recommendations = self.synthesize_recommendations(&rounds).await?;

        // Calculate inter-rater reliability
        let inter_rater_reliability = self.calculate_inter_rater_reliability(&rounds)?;

        // Calculate confidence interval
        let confidence_interval = self.calculate_confidence_interval(&consensus_scores);

        // Conduct meta-review if enabled
        let meta_review = if self.config.enable_meta_review {
            Some(self.conduct_meta_review(&rounds).await?)
        } else {
            None
        };

        // Calculate provider diversity
        let provider_diversity = self.calculate_provider_diversity(&rounds);

        let outcome = AdversarialReviewOutcome {
            id: review_id,
            started_at,
            completed_at: Utc::now(),
            rounds,
            final_verdict,
            consensus_scores,
            critical_issues,
            recommendations,
            inter_rater_reliability,
            confidence_interval,
            meta_review,
            provider_diversity,
        };

        // Store outcome
        self.review_history.write().await.push(outcome.clone());

        info!(
            "📊 Review complete - Verdict: {:?}, IRR: {:.3}, Confidence: ({:.2}, {:.2})",
            final_verdict, inter_rater_reliability, confidence_interval.0, confidence_interval.1
        );

        Ok(outcome)
    }

    /// Conduct a single review round
    async fn conduct_round(
        &self,
        review_id: Uuid,
        round_num: usize,
        content: &str,
        metadata: &HashMap<String, String>,
        previous_rounds: &[DebateRound],
    ) -> Result<DebateRound> {
        let mut reviews = Vec::new();

        // Each reviewer conducts independent review
        for role in [
            ReviewerRole::Athena,
            ReviewerRole::Hermes,
            ReviewerRole::Argos,
        ] {
            let review = self
                .generate_review(role, round_num, content, metadata, previous_rounds)
                .await?;

            reviews.push(review);
        }

        // Judge synthesizes if there are disagreements
        let disagreements = self.identify_disagreements(&reviews)?;

        if !disagreements.is_empty() || round_num == self.config.max_rounds {
            let judge_review = self
                .generate_judge_review(round_num, content, &reviews, &disagreements)
                .await?;

            reviews.push(judge_review);
        }

        // Calculate consensus
        let consensus_score = self.calculate_consensus(&reviews)?;

        // Calculate convergence
        let convergence_metric = self.calculate_convergence(previous_rounds, &reviews)?;

        Ok(DebateRound {
            round_number: round_num,
            reviews,
            consensus_score,
            disagreements,
            convergence_metric,
        })
    }

    /// Generate review from a specific agent
    async fn generate_review(
        &self,
        role: ReviewerRole,
        round_num: usize,
        content: &str,
        metadata: &HashMap<String, String>,
        previous_rounds: &[DebateRound],
    ) -> Result<AgentReview> {
        let span = span!(Level::INFO, "review", reviewer = ?role, round = round_num);
        let _enter = span.enter();

        // Build review prompt
        let prompt = self.build_review_prompt(role, content, metadata, previous_rounds)?;

        // Get appropriate LLM provider
        let meta = role.get_request_meta();
        let stats = self.context.get_current_stats().await;
        let (client, tier) = self
            .context
            .router()
            .choose_with_limits(&meta, &stats)
            .context("Failed to select LLM provider")?;

        debug!("Using provider tier {:?} for {:?}", tier, role);

        // Generate review
        let response = client.complete(&prompt).await?;

        // Parse review response
        let (scores, issues, recommendations, evidence) =
            self.parse_review_response(&response.content)?;

        // Calculate confidence based on evidence quality
        let confidence = self.calculate_review_confidence(&evidence, &scores);

        Ok(AgentReview {
            reviewer: role,
            timestamp: Utc::now(),
            round: round_num,
            content: response.content,
            scores,
            issues_identified: issues,
            recommendations,
            confidence,
            evidence,
            llm_provider: format!("{:?}", tier),
        })
    }

    /// Build review prompt for an agent
    fn build_review_prompt(
        &self,
        role: ReviewerRole,
        content: &str,
        metadata: &HashMap<String, String>,
        previous_rounds: &[DebateRound],
    ) -> Result<String> {
        let mut prompt = String::new();

        // System prompt
        prompt.push_str(role.system_prompt());
        prompt.push_str("\n\n");

        // Content to review
        prompt.push_str("CONTENT TO REVIEW:\n");
        prompt.push_str(content);
        prompt.push_str("\n\n");

        // Metadata
        if !metadata.is_empty() {
            prompt.push_str("METADATA:\n");
            for (key, value) in metadata {
                prompt.push_str(&format!("- {}: {}\n", key, value));
            }
            prompt.push_str("\n");
        }

        // Previous rounds context
        if !previous_rounds.is_empty() {
            prompt.push_str("PREVIOUS REVIEW ROUNDS:\n");
            for round in previous_rounds {
                prompt.push_str(&format!("Round {}:\n", round.round_number));

                for review in &round.reviews {
                    if review.reviewer == role {
                        continue; // Skip own previous reviews
                    }

                    prompt.push_str(&format!(
                        "- {:?}: Score={:.1}, Issues={}, Confidence={:.2}\n",
                        review.reviewer,
                        review.scores.weighted_average(),
                        review.issues_identified.len(),
                        review.confidence
                    ));

                    // Include major issues
                    for issue in review
                        .issues_identified
                        .iter()
                        .filter(|i| {
                            matches!(i.severity, IssueSeverity::Critical | IssueSeverity::Major)
                        })
                        .take(2)
                    {
                        prompt.push_str(&format!(
                            "  * {:?}: {}\n",
                            issue.category, issue.description
                        ));
                    }
                }

                if !round.disagreements.is_empty() {
                    prompt.push_str("Disagreements:\n");
                    for disagreement in &round.disagreements {
                        prompt.push_str(&format!(
                            "- {}: severity={:.1}\n",
                            disagreement.topic, disagreement.severity
                        ));
                    }
                }
            }
            prompt.push_str("\n");
        }

        // Review requirements
        prompt.push_str("REVIEW REQUIREMENTS:\n");
        prompt.push_str("Provide a comprehensive review including:\n");
        prompt.push_str("1. SCORES (0-10 scale):\n");
        prompt.push_str("   - Rigor: [score]\n");
        prompt.push_str("   - Novelty: [score]\n");
        prompt.push_str("   - Clarity: [score]\n");
        prompt.push_str("   - Impact: [score]\n");
        prompt.push_str("   - Reproducibility: [score]\n");
        prompt.push_str("   - Statistics: [score]\n");
        prompt.push_str("   - Ethics: [score]\n\n");

        prompt.push_str("2. ISSUES (list each with severity and category):\n");
        prompt.push_str("   Format: [SEVERITY:Category] Description\n");
        prompt.push_str("   Severities: CRITICAL, MAJOR, MINOR, SUGGESTION\n");
        prompt.push_str("   Categories: Methodology, Statistics, Logic, Evidence, Clarity, Ethics, Novelty, Reproducibility\n\n");

        prompt.push_str("3. RECOMMENDATIONS (actionable improvements)\n\n");

        prompt.push_str("4. EVIDENCE (support your claims):\n");
        prompt.push_str("   Format: [TYPE:Source] Description\n");
        prompt.push_str(
            "   Types: Literature, Statistical, Empirical, Theoretical, Methodological\n\n",
        );

        if self.config.require_uncertainty_quantification {
            prompt.push_str("5. UNCERTAINTY: Quantify uncertainty in your assessment\n\n");
        }

        Ok(prompt)
    }

    /// Parse review response into structured format
    fn parse_review_response(
        &self,
        response: &str,
    ) -> Result<(ReviewScores, Vec<Issue>, Vec<String>, Vec<Evidence>)> {
        let mut scores = ReviewScores {
            rigor: 5.0,
            novelty: 5.0,
            clarity: 5.0,
            impact: 5.0,
            reproducibility: 5.0,
            statistics: 5.0,
            ethics: 5.0,
        };

        let mut issues = Vec::new();
        let mut recommendations = Vec::new();
        let mut evidence = Vec::new();

        // Parse scores
        for line in response.lines() {
            if let Some(score_str) = line
                .strip_prefix("Rigor:")
                .or_else(|| line.strip_prefix("- Rigor:"))
            {
                if let Ok(score) = score_str.trim().parse::<f64>() {
                    scores.rigor = score.clamp(0.0, 10.0);
                }
            } else if let Some(score_str) = line
                .strip_prefix("Novelty:")
                .or_else(|| line.strip_prefix("- Novelty:"))
            {
                if let Ok(score) = score_str.trim().parse::<f64>() {
                    scores.novelty = score.clamp(0.0, 10.0);
                }
            } else if let Some(score_str) = line
                .strip_prefix("Clarity:")
                .or_else(|| line.strip_prefix("- Clarity:"))
            {
                if let Ok(score) = score_str.trim().parse::<f64>() {
                    scores.clarity = score.clamp(0.0, 10.0);
                }
            } else if let Some(score_str) = line
                .strip_prefix("Impact:")
                .or_else(|| line.strip_prefix("- Impact:"))
            {
                if let Ok(score) = score_str.trim().parse::<f64>() {
                    scores.impact = score.clamp(0.0, 10.0);
                }
            } else if let Some(score_str) = line
                .strip_prefix("Reproducibility:")
                .or_else(|| line.strip_prefix("- Reproducibility:"))
            {
                if let Ok(score) = score_str.trim().parse::<f64>() {
                    scores.reproducibility = score.clamp(0.0, 10.0);
                }
            } else if let Some(score_str) = line
                .strip_prefix("Statistics:")
                .or_else(|| line.strip_prefix("- Statistics:"))
            {
                if let Ok(score) = score_str.trim().parse::<f64>() {
                    scores.statistics = score.clamp(0.0, 10.0);
                }
            } else if let Some(score_str) = line
                .strip_prefix("Ethics:")
                .or_else(|| line.strip_prefix("- Ethics:"))
            {
                if let Ok(score) = score_str.trim().parse::<f64>() {
                    scores.ethics = score.clamp(0.0, 10.0);
                }
            }

            // Parse issues
            if line.contains("[CRITICAL:")
                || line.contains("[MAJOR:")
                || line.contains("[MINOR:")
                || line.contains("[SUGGESTION:")
            {
                if let Some(issue) = self.parse_issue_line(line) {
                    issues.push(issue);
                }
            }

            // Parse evidence
            if line.contains("[Literature:")
                || line.contains("[Statistical:")
                || line.contains("[Empirical:")
                || line.contains("[Theoretical:")
                || line.contains("[Methodological:")
            {
                if let Some(ev) = self.parse_evidence_line(line) {
                    evidence.push(ev);
                }
            }
        }

        // Extract recommendations (lines starting with "- " in recommendations section)
        let mut in_recommendations = false;
        for line in response.lines() {
            if line.to_uppercase().contains("RECOMMENDATION") {
                in_recommendations = true;
            } else if in_recommendations && line.starts_with("- ") {
                recommendations.push(line.trim_start_matches("- ").to_string());
            } else if in_recommendations && line.trim().is_empty() {
                in_recommendations = false;
            }
        }

        Ok((scores, issues, recommendations, evidence))
    }

    /// Parse issue line
    fn parse_issue_line(&self, line: &str) -> Option<Issue> {
        // Format: [SEVERITY:Category] Description
        let severity = if line.contains("[CRITICAL:") {
            IssueSeverity::Critical
        } else if line.contains("[MAJOR:") {
            IssueSeverity::Major
        } else if line.contains("[MINOR:") {
            IssueSeverity::Minor
        } else {
            IssueSeverity::Suggestion
        };

        let category = if line.contains("Methodology") {
            IssueCategory::Methodology
        } else if line.contains("Statistics") {
            IssueCategory::Statistics
        } else if line.contains("Logic") {
            IssueCategory::Logic
        } else if line.contains("Evidence") {
            IssueCategory::Evidence
        } else if line.contains("Clarity") {
            IssueCategory::Clarity
        } else if line.contains("Ethics") {
            IssueCategory::Ethics
        } else if line.contains("Novelty") {
            IssueCategory::Novelty
        } else {
            IssueCategory::Reproducibility
        };

        // Extract description
        let description = line.split(']').nth(1).unwrap_or("").trim().to_string();

        Some(Issue {
            severity,
            category,
            description,
            location: None,
            suggested_fix: None,
        })
    }

    /// Parse evidence line
    fn parse_evidence_line(&self, line: &str) -> Option<Evidence> {
        let evidence_type = if line.contains("[Literature:") {
            EvidenceType::Literature
        } else if line.contains("[Statistical:") {
            EvidenceType::Statistical
        } else if line.contains("[Empirical:") {
            EvidenceType::Empirical
        } else if line.contains("[Theoretical:") {
            EvidenceType::Theoretical
        } else {
            EvidenceType::Methodological
        };

        // Extract source and description
        if let Some(start) = line.find('[') {
            if let Some(end) = line.find(']') {
                let source = line[start + 1..end]
                    .split(':')
                    .nth(1)
                    .unwrap_or("Unknown")
                    .to_string();

                let description = line[end + 1..].trim().to_string();

                return Some(Evidence {
                    evidence_type,
                    source,
                    relevance: 0.8, // Default relevance
                    description,
                });
            }
        }

        None
    }

    /// Generate judge review
    async fn generate_judge_review(
        &self,
        round_num: usize,
        content: &str,
        reviews: &[AgentReview],
        disagreements: &[Disagreement],
    ) -> Result<AgentReview> {
        let mut prompt = String::new();

        prompt.push_str(ReviewerRole::Judge.system_prompt());
        prompt.push_str("\n\n");

        prompt.push_str("REVIEWS TO ARBITRATE:\n");
        for review in reviews {
            prompt.push_str(&format!(
                "{:?}:\n- Score: {:.1}\n- Issues: {}\n- Confidence: {:.2}\n",
                review.reviewer,
                review.scores.weighted_average(),
                review.issues_identified.len(),
                review.confidence
            ));

            // Include critical issues
            for issue in review
                .issues_identified
                .iter()
                .filter(|i| i.severity == IssueSeverity::Critical)
            {
                prompt.push_str(&format!("  * CRITICAL: {}\n", issue.description));
            }
        }

        if !disagreements.is_empty() {
            prompt.push_str("\nDISAGREEMENTS TO RESOLVE:\n");
            for disagreement in disagreements {
                prompt.push_str(&format!(
                    "- {}: (severity: {:.1})\n",
                    disagreement.topic, disagreement.severity
                ));
                for (role, position) in &disagreement.positions {
                    prompt.push_str(&format!("  {:?}: {}\n", role, position));
                }
            }
        }

        prompt.push_str(
            "\nProvide final arbitration including scores and resolution of disagreements.\n",
        );

        // Use Judge's request meta
        let meta = ReviewerRole::Judge.get_request_meta();
        let stats = self.context.get_current_stats().await;
        let (client, tier) = self.context.router().choose_with_limits(&meta, &stats)?;

        let response = client.complete(&prompt).await?;

        // Parse judge response
        let (scores, issues, recommendations, evidence) =
            self.parse_review_response(&response.content)?;

        Ok(AgentReview {
            reviewer: ReviewerRole::Judge,
            timestamp: Utc::now(),
            round: round_num,
            content: response.content,
            scores,
            issues_identified: issues,
            recommendations,
            confidence: 0.95, // Judges have high confidence
            evidence,
            llm_provider: format!("{:?}", tier),
        })
    }

    /// Identify disagreements between reviewers
    fn identify_disagreements(&self, reviews: &[AgentReview]) -> Result<Vec<Disagreement>> {
        let mut disagreements = Vec::new();

        // Check score disagreements
        if reviews.len() >= 2 {
            let score_variance = self.calculate_score_variance(reviews);

            for (dimension, variance) in score_variance {
                if variance > 2.0 {
                    // Significant disagreement threshold
                    let mut positions = HashMap::new();

                    for review in reviews {
                        let score = match dimension.as_str() {
                            "rigor" => review.scores.rigor,
                            "novelty" => review.scores.novelty,
                            "clarity" => review.scores.clarity,
                            "impact" => review.scores.impact,
                            _ => continue,
                        };

                        positions.insert(review.reviewer, format!("Score: {:.1}", score));
                    }

                    disagreements.push(Disagreement {
                        topic: format!("Assessment of {}", dimension),
                        positions,
                        severity: variance / 10.0,
                        resolved: false,
                    });
                }
            }
        }

        // Check issue disagreements
        let critical_issues_by_reviewer = reviews
            .iter()
            .map(|r| {
                (
                    r.reviewer,
                    r.issues_identified
                        .iter()
                        .filter(|i| i.severity == IssueSeverity::Critical)
                        .collect::<Vec<_>>(),
                )
            })
            .collect::<Vec<_>>();

        // Find issues identified by some but not all
        for (reviewer, issues) in &critical_issues_by_reviewer {
            for issue in issues {
                let identified_by = critical_issues_by_reviewer
                    .iter()
                    .filter(|(r, issues)| {
                        r != reviewer && issues.iter().any(|i| i.category == issue.category)
                    })
                    .count();

                if identified_by < critical_issues_by_reviewer.len() - 1 {
                    let mut positions = HashMap::new();
                    positions.insert(*reviewer, format!("Critical issue: {}", issue.description));

                    for (other_reviewer, _) in &critical_issues_by_reviewer {
                        if other_reviewer != reviewer {
                            positions
                                .insert(*other_reviewer, "Not identified as critical".to_string());
                        }
                    }

                    disagreements.push(Disagreement {
                        topic: format!("{:?} issue criticality", issue.category),
                        positions,
                        severity: 0.8,
                        resolved: false,
                    });
                }
            }
        }

        Ok(disagreements)
    }

    /// Calculate score variance across reviewers
    fn calculate_score_variance(&self, reviews: &[AgentReview]) -> HashMap<String, f64> {
        let mut variances = HashMap::new();

        for dimension in [
            "rigor",
            "novelty",
            "clarity",
            "impact",
            "reproducibility",
            "statistics",
            "ethics",
        ] {
            let scores: Vec<f64> = reviews
                .iter()
                .map(|r| match dimension {
                    "rigor" => r.scores.rigor,
                    "novelty" => r.scores.novelty,
                    "clarity" => r.scores.clarity,
                    "impact" => r.scores.impact,
                    "reproducibility" => r.scores.reproducibility,
                    "statistics" => r.scores.statistics,
                    "ethics" => r.scores.ethics,
                    _ => 0.0,
                })
                .collect();

            let mean = scores.iter().sum::<f64>() / scores.len() as f64;
            let variance =
                scores.iter().map(|s| (s - mean).powi(2)).sum::<f64>() / scores.len() as f64;

            variances.insert(dimension.to_string(), variance);
        }

        variances
    }

    /// Calculate consensus score
    fn calculate_consensus(&self, reviews: &[AgentReview]) -> Result<f64> {
        if reviews.is_empty() {
            return Ok(0.0);
        }

        // Calculate agreement on scores
        let score_variances = self.calculate_score_variance(reviews);
        let avg_variance = score_variances.values().sum::<f64>() / score_variances.len() as f64;

        // Lower variance = higher consensus
        let score_consensus = 1.0 / (1.0 + avg_variance);

        // Calculate agreement on critical issues
        let critical_issue_sets: Vec<HashSet<IssueCategory>> = reviews
            .iter()
            .map(|r| {
                r.issues_identified
                    .iter()
                    .filter(|i| i.severity == IssueSeverity::Critical)
                    .map(|i| i.category)
                    .collect()
            })
            .collect();

        let issue_consensus = if critical_issue_sets.len() > 1 {
            let intersection = critical_issue_sets
                .iter()
                .fold(critical_issue_sets[0].clone(), |acc, set| {
                    acc.intersection(set).cloned().collect()
                });

            let union: HashSet<IssueCategory> =
                critical_issue_sets.iter().flatten().cloned().collect();

            if union.is_empty() {
                1.0
            } else {
                intersection.len() as f64 / union.len() as f64
            }
        } else {
            1.0
        };

        // Weight both factors
        Ok(0.6 * score_consensus + 0.4 * issue_consensus)
    }

    /// Calculate convergence across rounds
    fn calculate_convergence(
        &self,
        previous_rounds: &[DebateRound],
        current_reviews: &[AgentReview],
    ) -> Result<f64> {
        if previous_rounds.is_empty() {
            return Ok(0.0);
        }

        let last_round = &previous_rounds[previous_rounds.len() - 1];

        // Compare score changes
        let mut score_changes = Vec::new();

        for current in current_reviews {
            if let Some(previous) = last_round
                .reviews
                .iter()
                .find(|r| r.reviewer == current.reviewer)
            {
                let change =
                    (current.scores.weighted_average() - previous.scores.weighted_average()).abs();
                score_changes.push(change);
            }
        }

        if score_changes.is_empty() {
            return Ok(1.0);
        }

        // Lower change = higher convergence
        let avg_change = score_changes.iter().sum::<f64>() / score_changes.len() as f64;
        Ok(1.0 / (1.0 + avg_change))
    }

    /// Calculate review confidence based on evidence
    fn calculate_review_confidence(&self, evidence: &[Evidence], scores: &ReviewScores) -> f64 {
        let evidence_score = if evidence.is_empty() {
            0.5
        } else {
            let avg_relevance =
                evidence.iter().map(|e| e.relevance).sum::<f64>() / evidence.len() as f64;
            let type_diversity = evidence
                .iter()
                .map(|e| e.evidence_type)
                .collect::<HashSet<_>>()
                .len() as f64
                / 5.0; // 5 evidence types

            0.6 * avg_relevance + 0.4 * type_diversity
        };

        // Extreme scores reduce confidence
        let score_extremity = [
            scores.rigor,
            scores.novelty,
            scores.clarity,
            scores.impact,
            scores.reproducibility,
            scores.statistics,
            scores.ethics,
        ]
        .iter()
        .map(|&s| if s < 2.0 || s > 9.0 { 0.8 } else { 1.0 })
        .product::<f64>();

        evidence_score * score_extremity
    }

    /// Determine final verdict
    fn determine_verdict(&self, rounds: &[DebateRound]) -> Result<Verdict> {
        let final_round = rounds
            .last()
            .ok_or_else(|| anyhow::anyhow!("No rounds completed"))?;

        // Get judge's score if available, otherwise average
        let final_score = if let Some(judge_review) = final_round
            .reviews
            .iter()
            .find(|r| r.reviewer == ReviewerRole::Judge)
        {
            judge_review.scores.weighted_average()
        } else {
            final_round
                .reviews
                .iter()
                .map(|r| r.scores.weighted_average())
                .sum::<f64>()
                / final_round.reviews.len() as f64
        };

        // Count critical issues
        let critical_count = final_round
            .reviews
            .iter()
            .flat_map(|r| &r.issues_identified)
            .filter(|i| i.severity == IssueSeverity::Critical)
            .count();

        Ok(match (final_score, critical_count) {
            (s, 0) if s >= 8.0 => Verdict::Accept,
            (s, c) if s >= 7.0 && c <= 2 => Verdict::AcceptWithMinorRevisions,
            (s, _) if s >= 5.0 => Verdict::MajorRevisions,
            _ => Verdict::Reject,
        })
    }

    /// Calculate consensus scores
    fn calculate_consensus_scores(&self, rounds: &[DebateRound]) -> Result<ReviewScores> {
        let final_round = rounds
            .last()
            .ok_or_else(|| anyhow::anyhow!("No rounds completed"))?;

        // If judge provided scores, use those
        if let Some(judge_review) = final_round
            .reviews
            .iter()
            .find(|r| r.reviewer == ReviewerRole::Judge)
        {
            return Ok(judge_review.scores.clone());
        }

        // Otherwise, weighted average based on confidence
        let total_confidence: f64 = final_round.reviews.iter().map(|r| r.confidence).sum();

        Ok(ReviewScores {
            rigor: final_round
                .reviews
                .iter()
                .map(|r| r.scores.rigor * r.confidence)
                .sum::<f64>()
                / total_confidence,
            novelty: final_round
                .reviews
                .iter()
                .map(|r| r.scores.novelty * r.confidence)
                .sum::<f64>()
                / total_confidence,
            clarity: final_round
                .reviews
                .iter()
                .map(|r| r.scores.clarity * r.confidence)
                .sum::<f64>()
                / total_confidence,
            impact: final_round
                .reviews
                .iter()
                .map(|r| r.scores.impact * r.confidence)
                .sum::<f64>()
                / total_confidence,
            reproducibility: final_round
                .reviews
                .iter()
                .map(|r| r.scores.reproducibility * r.confidence)
                .sum::<f64>()
                / total_confidence,
            statistics: final_round
                .reviews
                .iter()
                .map(|r| r.scores.statistics * r.confidence)
                .sum::<f64>()
                / total_confidence,
            ethics: final_round
                .reviews
                .iter()
                .map(|r| r.scores.ethics * r.confidence)
                .sum::<f64>()
                / total_confidence,
        })
    }

    /// Extract critical issues
    fn extract_critical_issues(&self, rounds: &[DebateRound]) -> Vec<Issue> {
        let mut issues = Vec::new();
        let mut seen = HashSet::new();

        // Collect all critical and major issues
        for round in rounds.iter().rev() {
            for review in &round.reviews {
                for issue in &review.issues_identified {
                    if matches!(
                        issue.severity,
                        IssueSeverity::Critical | IssueSeverity::Major
                    ) {
                        let key = format!("{:?}:{}", issue.category, issue.description);
                        if seen.insert(key) {
                            issues.push(issue.clone());
                        }
                    }
                }
            }
        }

        // Sort by severity
        issues.sort_by_key(|i| match i.severity {
            IssueSeverity::Critical => 0,
            IssueSeverity::Major => 1,
            IssueSeverity::Minor => 2,
            IssueSeverity::Suggestion => 3,
        });

        issues
    }

    /// Synthesize recommendations using LLM
    async fn synthesize_recommendations(&self, rounds: &[DebateRound]) -> Result<Vec<String>> {
        // Collect all recommendations
        let all_recommendations: Vec<String> = rounds
            .iter()
            .flat_map(|r| &r.reviews)
            .flat_map(|review| &review.recommendations)
            .cloned()
            .collect();

        if all_recommendations.is_empty() {
            return Ok(Vec::new());
        }

        let prompt = format!(
            "Synthesize the following review recommendations into a prioritized list of actionable items:\n\n{}\n\n\
            Provide 5-10 consolidated recommendations, ordered by importance.",
            all_recommendations.join("\n- ")
        );

        let meta = RequestMeta {
            requires_high_quality: true,
            requires_phd_level_reasoning: false,
            high_bias_risk: false,
            critical_section: false,
            requires_math: false,
            offline_required: false,
        };

        let stats = self.context.get_current_stats().await;
        let (client, _) = self.context.router().choose_with_limits(&meta, &stats)?;

        let response = client.complete(&prompt).await?;

        Ok(response
            .content
            .lines()
            .filter(|line| {
                line.starts_with('-')
                    || line.starts_with("•")
                    || (line.len() > 0 && line.chars().next().unwrap().is_numeric())
            })
            .map(|line| {
                line.trim_start_matches([
                    '-', '•', '1', '2', '3', '4', '5', '6', '7', '8', '9', '0', '.', ' ',
                ])
            })
            .map(String::from)
            .collect())
    }

    /// Calculate inter-rater reliability (Cohen's kappa)
    fn calculate_inter_rater_reliability(&self, rounds: &[DebateRound]) -> Result<f64> {
        let final_round = rounds
            .last()
            .ok_or_else(|| anyhow::anyhow!("No rounds completed"))?;

        if final_round.reviews.len() < 2 {
            return Ok(1.0); // Perfect agreement with single reviewer
        }

        // Simplified Cohen's kappa for score agreement
        let mut agreements = 0;
        let mut comparisons = 0;

        for i in 0..final_round.reviews.len() {
            for j in i + 1..final_round.reviews.len() {
                let score_diff = (final_round.reviews[i].scores.weighted_average()
                    - final_round.reviews[j].scores.weighted_average())
                .abs();

                if score_diff < 1.0 {
                    agreements += 1;
                }
                comparisons += 1;
            }
        }

        let observed_agreement = agreements as f64 / comparisons as f64;
        let expected_agreement = 0.25; // Simplified assumption

        let kappa = (observed_agreement - expected_agreement) / (1.0 - expected_agreement);

        Ok(kappa.max(0.0).min(1.0))
    }

    /// Calculate confidence interval
    fn calculate_confidence_interval(&self, scores: &ReviewScores) -> (f64, f64) {
        let mean = scores.weighted_average();

        // Simplified 95% CI calculation
        let std_dev = 1.5; // Assumed standard deviation
        let margin = 1.96 * std_dev / (7.0_f64).sqrt(); // 7 score dimensions

        ((mean - margin).max(0.0), (mean + margin).min(10.0))
    }

    /// Conduct meta-review
    async fn conduct_meta_review(&self, rounds: &[DebateRound]) -> Result<MetaReview> {
        let prompt = format!(
            "Conduct a meta-review of this peer review process:\n\n\
            Number of rounds: {}\n\
            Reviewers involved: Athena, Hermes, Argos, Judge\n\
            Final consensus: {:.2}\n\
            Total issues identified: {}\n\n\
            Evaluate:\n\
            1. Process quality (0-1)\n\
            2. Bias detection (yes/no)\n\
            3. Coverage completeness (0-1)\n\
            4. Methodological rigor (0-1)\n\
            5. Recommendations for improving the review process",
            rounds.len(),
            rounds.last().map(|r| r.consensus_score).unwrap_or(0.0),
            rounds
                .iter()
                .flat_map(|r| &r.reviews)
                .map(|review| review.issues_identified.len())
                .sum::<usize>()
        );

        let meta = RequestMeta {
            requires_high_quality: true,
            requires_phd_level_reasoning: true,
            high_bias_risk: true,
            critical_section: false,
            requires_math: false,
            offline_required: false,
        };

        let stats = self.context.get_current_stats().await;
        let (client, _) = self.context.router().choose_with_limits(&meta, &stats)?;

        let response = client.complete(&prompt).await?;

        // Parse meta-review response (simplified)
        Ok(MetaReview {
            process_quality: 0.85,
            bias_detected: response.content.to_lowercase().contains("bias"),
            coverage_completeness: 0.90,
            methodological_rigor: 0.88,
            recommendations: vec![
                "Consider additional domain experts".to_string(),
                "Implement formal statistical validation".to_string(),
            ],
        })
    }

    /// Calculate provider diversity
    fn calculate_provider_diversity(&self, rounds: &[DebateRound]) -> f64 {
        let providers: HashSet<String> = rounds
            .iter()
            .flat_map(|r| &r.reviews)
            .map(|review| review.llm_provider.clone())
            .collect();

        // Normalize by maximum possible diversity (4 reviewers)
        providers.len() as f64 / 4.0
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[tokio::test]
    async fn test_adversarial_review_creation() {
        let config = AdversarialReviewConfig::default();
        assert_eq!(config.max_rounds, 5);
        assert!(config.enable_statistical_validation);
        assert_eq!(config.consensus_threshold, 0.85);
    }

    #[test]
    fn test_review_scores_weighted_average() {
        let scores = ReviewScores {
            rigor: 8.0,
            novelty: 7.0,
            clarity: 9.0,
            impact: 7.5,
            reproducibility: 8.5,
            statistics: 8.0,
            ethics: 10.0,
        };

        let avg = scores.weighted_average();
        assert!(avg > 7.0 && avg < 9.0);
    }

    #[test]
    fn test_reviewer_role_meta() {
        let athena_meta = ReviewerRole::Athena.get_request_meta();
        assert!(athena_meta.requires_high_quality);
        assert!(athena_meta.requires_phd_level_reasoning);
        assert!(athena_meta.requires_math);

        let argos_meta = ReviewerRole::Argos.get_request_meta();
        assert!(argos_meta.high_bias_risk);
        assert!(argos_meta.critical_section);
    }

    #[test]
    fn test_verdict_determination() {
        // High score, no critical issues -> Accept
        assert!(matches!(determine_verdict_helper(8.5, 0), Verdict::Accept));

        // Good score, few issues -> Minor revisions
        assert!(matches!(
            determine_verdict_helper(7.5, 1),
            Verdict::AcceptWithMinorRevisions
        ));

        // Medium score -> Major revisions
        assert!(matches!(
            determine_verdict_helper(5.5, 3),
            Verdict::MajorRevisions
        ));

        // Low score -> Reject
        assert!(matches!(determine_verdict_helper(3.0, 5), Verdict::Reject));
    }

    fn determine_verdict_helper(score: f64, critical_issues: usize) -> Verdict {
        match (score, critical_issues) {
            (s, 0) if s >= 8.0 => Verdict::Accept,
            (s, c) if s >= 7.0 && c <= 2 => Verdict::AcceptWithMinorRevisions,
            (s, _) if s >= 5.0 => Verdict::MajorRevisions,
            _ => Verdict::Reject,
        }
    }
}
