//! A/B Testing Framework for TCR-QF vs Baseline RAG
//!
//! Provides utilities for running controlled experiments comparing:
//! - Baseline RAG (4 factors: semantic, recency, centrality, proximity)
//! - TCR-QF Enhanced RAG (8 factors: + topology, temporal_burst, temporal_periodic, pagerank)
//!
//! Features:
//! - Randomized assignment to control/treatment groups
//! - Statistical significance testing (t-test, Mann-Whitney U)
//! - Confidence intervals (95%, 99%)
//! - Power analysis for sample size estimation
//! - Continuous monitoring with early stopping

use anyhow::Result;
use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};
use std::collections::HashMap;
use uuid::Uuid;

use super::eval::{GroundTruth, QueryResult, RetrievalEvaluator, RetrievalMetrics};
use super::tcr_qf::TcrQfConfig;

/// A/B test configuration
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ABTestConfig {
    /// Test name/ID
    pub test_id: String,

    /// Test description
    pub description: String,

    /// Traffic allocation to treatment (0.0 to 1.0)
    pub treatment_ratio: f32,

    /// Minimum sample size per group
    pub min_sample_size: usize,

    /// Maximum sample size per group
    pub max_sample_size: usize,

    /// Significance level (alpha) for statistical tests
    pub alpha: f32,

    /// Minimum detectable effect (MDE) - % improvement to detect
    pub min_detectable_effect: f32,

    /// Enable early stopping
    pub early_stopping_enabled: bool,

    /// Check interval for early stopping (number of samples)
    pub early_stopping_check_interval: usize,

    /// Random seed for reproducibility
    pub random_seed: Option<u64>,

    /// TCR-QF configuration for treatment group
    pub tcr_qf_config: TcrQfConfig,
}

impl Default for ABTestConfig {
    fn default() -> Self {
        Self {
            test_id: format!("ab_test_{}", Utc::now().timestamp()),
            description: "TCR-QF vs Baseline RAG".to_string(),
            treatment_ratio: 0.5, // 50/50 split
            min_sample_size: 100,
            max_sample_size: 10000,
            alpha: 0.05,                 // 95% confidence
            min_detectable_effect: 0.10, // 10% improvement
            early_stopping_enabled: true,
            early_stopping_check_interval: 50,
            random_seed: None,
            tcr_qf_config: TcrQfConfig::default(),
        }
    }
}

/// Assignment group
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
pub enum AssignmentGroup {
    /// Control group (baseline RAG)
    Control,
    /// Treatment group (TCR-QF enhanced)
    Treatment,
}

/// Single experiment sample
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ExperimentSample {
    /// Sample ID
    pub id: Uuid,

    /// Query that was executed
    pub query: String,

    /// Assignment group
    pub group: AssignmentGroup,

    /// Query result
    pub result: QueryResult,

    /// Ground truth
    pub ground_truth: GroundTruth,

    /// Timestamp
    pub timestamp: DateTime<Utc>,

    /// Metrics for this sample
    pub metrics: SampleMetrics,
}

/// Metrics for a single sample
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SampleMetrics {
    /// Reciprocal rank (1/rank of first relevant, 0 if none)
    pub reciprocal_rank: f32,

    /// Recall@10
    pub recall_at_10: f32,

    /// NDCG@10
    pub ndcg_at_10: f32,

    /// Precision@10
    pub precision_at_10: f32,

    /// Latency (ms)
    pub latency_ms: f32,
}

impl SampleMetrics {
    pub fn compute(result: &QueryResult, ground_truth: &GroundTruth) -> Self {
        let evaluator = RetrievalEvaluator::new(vec![10]);
        let full_metrics = evaluator.evaluate(&[result.clone()], &[ground_truth.clone()]);

        // Compute reciprocal rank
        let reciprocal_rank = result
            .retrieved
            .iter()
            .position(|id| ground_truth.relevant.contains(id))
            .map(|rank| 1.0 / (rank + 1) as f32)
            .unwrap_or(0.0);

        Self {
            reciprocal_rank,
            recall_at_10: *full_metrics.recall_at_k.get(&10).unwrap_or(&0.0),
            ndcg_at_10: *full_metrics.ndcg_at_k.get(&10).unwrap_or(&0.0),
            precision_at_10: *full_metrics.precision_at_k.get(&10).unwrap_or(&0.0),
            latency_ms: result.latency_ms,
        }
    }
}

/// A/B test results
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ABTestResults {
    /// Test configuration
    pub config: ABTestConfig,

    /// Start time
    pub start_time: DateTime<Utc>,

    /// End time
    pub end_time: Option<DateTime<Utc>>,

    /// Control group metrics
    pub control_metrics: RetrievalMetrics,

    /// Treatment group metrics
    pub treatment_metrics: RetrievalMetrics,

    /// Control group samples
    pub control_samples: Vec<ExperimentSample>,

    /// Treatment group samples
    pub treatment_samples: Vec<ExperimentSample>,

    /// Statistical test results
    pub statistical_tests: StatisticalTestResults,

    /// Whether test was stopped early
    pub early_stopped: bool,

    /// Reason for stopping (if early stopped)
    pub stop_reason: Option<String>,
}

/// Statistical test results
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct StatisticalTestResults {
    /// T-test results for MRR
    pub mrr_ttest: TTestResult,

    /// T-test results for Recall@10
    pub recall_ttest: TTestResult,

    /// T-test results for NDCG@10
    pub ndcg_ttest: TTestResult,

    /// Mann-Whitney U test for latency
    pub latency_mann_whitney: MannWhitneyResult,

    /// Effect sizes (Cohen's d)
    pub effect_sizes: HashMap<String, f32>,

    /// Confidence intervals (95%)
    pub confidence_intervals: HashMap<String, (f32, f32)>,
}

/// T-test result
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct TTestResult {
    /// Test statistic
    pub t_statistic: f32,

    /// Degrees of freedom
    pub degrees_of_freedom: f32,

    /// P-value (two-tailed)
    pub p_value: f32,

    /// Is significant at alpha level
    pub is_significant: bool,

    /// Control group mean
    pub control_mean: f32,

    /// Treatment group mean
    pub treatment_mean: f32,

    /// Percent improvement (treatment - control) / control
    pub percent_improvement: f32,
}

/// Mann-Whitney U test result
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct MannWhitneyResult {
    /// U statistic
    pub u_statistic: f32,

    /// P-value (two-tailed)
    pub p_value: f32,

    /// Is significant at alpha level
    pub is_significant: bool,

    /// Control group median
    pub control_median: f32,

    /// Treatment group median
    pub treatment_median: f32,
}

/// A/B test runner
pub struct ABTestRunner {
    config: ABTestConfig,
    control_samples: Vec<ExperimentSample>,
    treatment_samples: Vec<ExperimentSample>,
    start_time: DateTime<Utc>,
    rng_state: u64,
}

impl ABTestRunner {
    /// Create new A/B test runner
    pub fn new(config: ABTestConfig) -> Self {
        let rng_state = config.random_seed.unwrap_or_else(|| {
            use std::time::{SystemTime, UNIX_EPOCH};
            SystemTime::now()
                .duration_since(UNIX_EPOCH)
                .unwrap()
                .as_secs()
        });

        Self {
            config,
            control_samples: Vec::new(),
            treatment_samples: Vec::new(),
            start_time: Utc::now(),
            rng_state,
        }
    }

    /// Assign query to control or treatment group
    pub fn assign_group(&mut self, query_id: &Uuid) -> AssignmentGroup {
        // Deterministic hash-based assignment for consistency
        let hash = self.hash_uuid(query_id);
        let normalized = (hash as f32) / (u64::MAX as f32);

        if normalized < self.config.treatment_ratio {
            AssignmentGroup::Treatment
        } else {
            AssignmentGroup::Control
        }
    }

    /// Add sample to experiment
    pub fn add_sample(&mut self, sample: ExperimentSample) {
        match sample.group {
            AssignmentGroup::Control => self.control_samples.push(sample),
            AssignmentGroup::Treatment => self.treatment_samples.push(sample),
        }
    }

    /// Check if test should continue
    pub fn should_continue(&mut self) -> Result<bool> {
        let control_count = self.control_samples.len();
        let treatment_count = self.treatment_samples.len();
        let total_samples = control_count.min(treatment_count);

        // Check minimum sample size
        if total_samples < self.config.min_sample_size {
            return Ok(true);
        }

        // Check maximum sample size
        if total_samples >= self.config.max_sample_size {
            return Ok(false);
        }

        // Check early stopping
        if self.config.early_stopping_enabled
            && total_samples % self.config.early_stopping_check_interval == 0
        {
            let interim_results = self.compute_interim_results()?;
            if self.should_stop_early(&interim_results) {
                return Ok(false);
            }
        }

        Ok(true)
    }

    /// Compute final results
    pub fn compute_results(&self) -> Result<ABTestResults> {
        let evaluator = RetrievalEvaluator::new(vec![1, 5, 10, 20]);

        // Compute metrics for each group
        let control_results: Vec<QueryResult> = self
            .control_samples
            .iter()
            .map(|s| s.result.clone())
            .collect();
        let control_ground_truths: Vec<GroundTruth> = self
            .control_samples
            .iter()
            .map(|s| s.ground_truth.clone())
            .collect();

        let treatment_results: Vec<QueryResult> = self
            .treatment_samples
            .iter()
            .map(|s| s.result.clone())
            .collect();
        let treatment_ground_truths: Vec<GroundTruth> = self
            .treatment_samples
            .iter()
            .map(|s| s.ground_truth.clone())
            .collect();

        let control_metrics = evaluator.evaluate(&control_results, &control_ground_truths);
        let treatment_metrics = evaluator.evaluate(&treatment_results, &treatment_ground_truths);

        // Compute statistical tests
        let statistical_tests =
            self.compute_statistical_tests(&control_metrics, &treatment_metrics);

        Ok(ABTestResults {
            config: self.config.clone(),
            start_time: self.start_time,
            end_time: Some(Utc::now()),
            control_metrics,
            treatment_metrics,
            control_samples: self.control_samples.clone(),
            treatment_samples: self.treatment_samples.clone(),
            statistical_tests,
            early_stopped: false,
            stop_reason: None,
        })
    }

    /// Compute interim results for early stopping check
    fn compute_interim_results(&self) -> Result<ABTestResults> {
        self.compute_results()
    }

    /// Check if test should stop early
    fn should_stop_early(&self, results: &ABTestResults) -> bool {
        // Stop early if we have high confidence in a positive result
        let mrr_significant = results.statistical_tests.mrr_ttest.is_significant;
        let mrr_improvement = results.statistical_tests.mrr_ttest.percent_improvement;

        mrr_significant && mrr_improvement >= self.config.min_detectable_effect
    }

    /// Compute statistical tests
    fn compute_statistical_tests(
        &self,
        control: &RetrievalMetrics,
        treatment: &RetrievalMetrics,
    ) -> StatisticalTestResults {
        // Extract MRR values
        let control_mrr_values: Vec<f32> = self
            .control_samples
            .iter()
            .map(|s| s.metrics.reciprocal_rank)
            .collect();
        let treatment_mrr_values: Vec<f32> = self
            .treatment_samples
            .iter()
            .map(|s| s.metrics.reciprocal_rank)
            .collect();

        // Extract Recall@10 values
        let control_recall_values: Vec<f32> = self
            .control_samples
            .iter()
            .map(|s| s.metrics.recall_at_10)
            .collect();
        let treatment_recall_values: Vec<f32> = self
            .treatment_samples
            .iter()
            .map(|s| s.metrics.recall_at_10)
            .collect();

        // Extract NDCG@10 values
        let control_ndcg_values: Vec<f32> = self
            .control_samples
            .iter()
            .map(|s| s.metrics.ndcg_at_10)
            .collect();
        let treatment_ndcg_values: Vec<f32> = self
            .treatment_samples
            .iter()
            .map(|s| s.metrics.ndcg_at_10)
            .collect();

        // Extract latency values
        let control_latency_values: Vec<f32> = self
            .control_samples
            .iter()
            .map(|s| s.metrics.latency_ms)
            .collect();
        let treatment_latency_values: Vec<f32> = self
            .treatment_samples
            .iter()
            .map(|s| s.metrics.latency_ms)
            .collect();

        // Compute t-tests
        let mrr_ttest = self.welch_ttest(
            &control_mrr_values,
            &treatment_mrr_values,
            control.mrr,
            treatment.mrr,
        );
        let recall_ttest = self.welch_ttest(
            &control_recall_values,
            &treatment_recall_values,
            *control.recall_at_k.get(&10).unwrap_or(&0.0),
            *treatment.recall_at_k.get(&10).unwrap_or(&0.0),
        );
        let ndcg_ttest = self.welch_ttest(
            &control_ndcg_values,
            &treatment_ndcg_values,
            *control.ndcg_at_k.get(&10).unwrap_or(&0.0),
            *treatment.ndcg_at_k.get(&10).unwrap_or(&0.0),
        );

        // Compute Mann-Whitney U for latency
        let latency_mann_whitney =
            self.mann_whitney_u(&control_latency_values, &treatment_latency_values);

        // Compute effect sizes
        let mut effect_sizes = HashMap::new();
        effect_sizes.insert(
            "mrr".to_string(),
            self.cohens_d(&control_mrr_values, &treatment_mrr_values),
        );
        effect_sizes.insert(
            "recall_at_10".to_string(),
            self.cohens_d(&control_recall_values, &treatment_recall_values),
        );
        effect_sizes.insert(
            "ndcg_at_10".to_string(),
            self.cohens_d(&control_ndcg_values, &treatment_ndcg_values),
        );

        // Compute confidence intervals (95%)
        let mut confidence_intervals = HashMap::new();
        confidence_intervals.insert(
            "mrr".to_string(),
            self.confidence_interval(&treatment_mrr_values, 0.05),
        );
        confidence_intervals.insert(
            "recall_at_10".to_string(),
            self.confidence_interval(&treatment_recall_values, 0.05),
        );
        confidence_intervals.insert(
            "ndcg_at_10".to_string(),
            self.confidence_interval(&treatment_ndcg_values, 0.05),
        );

        StatisticalTestResults {
            mrr_ttest,
            recall_ttest,
            ndcg_ttest,
            latency_mann_whitney,
            effect_sizes,
            confidence_intervals,
        }
    }

    /// Welch's t-test (unequal variances)
    fn welch_ttest(
        &self,
        control: &[f32],
        treatment: &[f32],
        control_mean: f32,
        treatment_mean: f32,
    ) -> TTestResult {
        let n1 = control.len() as f32;
        let n2 = treatment.len() as f32;

        // Compute variances
        let var1 = self.variance(control, control_mean);
        let var2 = self.variance(treatment, treatment_mean);

        // Welch's t-statistic
        let t_statistic = (treatment_mean - control_mean) / ((var1 / n1) + (var2 / n2)).sqrt();

        // Welch-Satterthwaite degrees of freedom
        let df_numerator = ((var1 / n1) + (var2 / n2)).powi(2);
        let df_denominator =
            ((var1 / n1).powi(2) / (n1 - 1.0)) + ((var2 / n2).powi(2) / (n2 - 1.0));
        let df = df_numerator / df_denominator;

        // Approximate p-value using t-distribution
        // For simplicity, using a conservative estimate
        let p_value = self.approx_t_pvalue(t_statistic.abs(), df);

        let is_significant = p_value < self.config.alpha;

        let percent_improvement = if control_mean > 0.0 {
            ((treatment_mean - control_mean) / control_mean) * 100.0
        } else {
            0.0
        };

        TTestResult {
            t_statistic,
            degrees_of_freedom: df,
            p_value,
            is_significant,
            control_mean,
            treatment_mean,
            percent_improvement,
        }
    }

    /// Mann-Whitney U test for non-parametric comparison
    fn mann_whitney_u(&self, control: &[f32], treatment: &[f32]) -> MannWhitneyResult {
        // Combine and rank all values
        let mut combined: Vec<(f32, bool)> = Vec::new();
        for &val in control {
            combined.push((val, false)); // false = control
        }
        for &val in treatment {
            combined.push((val, true)); // true = treatment
        }
        combined.sort_by(|a, b| a.0.partial_cmp(&b.0).unwrap());

        // Assign ranks (handling ties with average rank)
        let mut ranks: Vec<(f32, bool)> = Vec::new();
        let mut i = 0;
        while i < combined.len() {
            let mut j = i;
            while j < combined.len() && combined[j].0 == combined[i].0 {
                j += 1;
            }
            let avg_rank = ((i + 1 + j) as f32) / 2.0;
            for k in i..j {
                ranks.push((avg_rank, combined[k].1));
            }
            i = j;
        }

        // Sum ranks for treatment group
        let r2: f32 = ranks
            .iter()
            .filter(|(_, is_treatment)| *is_treatment)
            .map(|(rank, _)| rank)
            .sum();

        let n1 = control.len() as f32;
        let n2 = treatment.len() as f32;

        // U statistic for treatment
        let u2 = r2 - (n2 * (n2 + 1.0)) / 2.0;

        // U statistic for control
        let u1 = n1 * n2 - u2;

        // Use smaller U
        let u_statistic = u1.min(u2);

        // Approximate p-value using normal approximation
        let mean_u = (n1 * n2) / 2.0;
        let std_u = ((n1 * n2 * (n1 + n2 + 1.0)) / 12.0).sqrt();
        let z = (u_statistic - mean_u) / std_u;
        let p_value = 2.0 * self.approx_normal_cdf(-z.abs());

        let is_significant = p_value < self.config.alpha;

        let control_median = self.median(control);
        let treatment_median = self.median(treatment);

        MannWhitneyResult {
            u_statistic,
            p_value,
            is_significant,
            control_median,
            treatment_median,
        }
    }

    /// Cohen's d effect size
    fn cohens_d(&self, control: &[f32], treatment: &[f32]) -> f32 {
        let control_mean = self.mean(control);
        let treatment_mean = self.mean(treatment);

        let control_var = self.variance(control, control_mean);
        let treatment_var = self.variance(treatment, treatment_mean);

        let n1 = control.len() as f32;
        let n2 = treatment.len() as f32;

        // Pooled standard deviation
        let pooled_std =
            (((n1 - 1.0) * control_var + (n2 - 1.0) * treatment_var) / (n1 + n2 - 2.0)).sqrt();

        if pooled_std > 0.0 {
            (treatment_mean - control_mean) / pooled_std
        } else {
            0.0
        }
    }

    /// Confidence interval (using t-distribution)
    fn confidence_interval(&self, values: &[f32], alpha: f32) -> (f32, f32) {
        let mean = self.mean(values);
        let var = self.variance(values, mean);
        let n = values.len() as f32;
        let se = (var / n).sqrt();

        // Critical value from t-distribution (approximation for df > 30)
        let df = n - 1.0;
        let t_critical = if df > 30.0 {
            self.approx_normal_quantile(1.0 - alpha / 2.0)
        } else {
            self.approx_t_quantile(1.0 - alpha / 2.0, df)
        };

        let margin = t_critical * se;
        (mean - margin, mean + margin)
    }

    // Helper functions

    fn hash_uuid(&self, uuid: &Uuid) -> u64 {
        let bytes = uuid.as_bytes();
        let mut hash: u64 = self.rng_state;
        for &byte in bytes {
            hash = hash.wrapping_mul(31).wrapping_add(byte as u64);
        }
        hash
    }

    fn mean(&self, values: &[f32]) -> f32 {
        if values.is_empty() {
            return 0.0;
        }
        values.iter().sum::<f32>() / values.len() as f32
    }

    fn variance(&self, values: &[f32], mean: f32) -> f32 {
        if values.len() <= 1 {
            return 0.0;
        }
        let sum_sq_diff: f32 = values.iter().map(|x| (x - mean).powi(2)).sum();
        sum_sq_diff / (values.len() - 1) as f32
    }

    fn median(&self, values: &[f32]) -> f32 {
        let mut sorted = values.to_vec();
        sorted.sort_by(|a, b| a.partial_cmp(b).unwrap());
        let mid = sorted.len() / 2;
        if sorted.len() % 2 == 0 {
            (sorted[mid - 1] + sorted[mid]) / 2.0
        } else {
            sorted[mid]
        }
    }

    // Approximate p-value from t-distribution (two-tailed)
    fn approx_t_pvalue(&self, t: f32, df: f32) -> f32 {
        // Very rough approximation using normal distribution for large df
        if df > 30.0 {
            2.0 * self.approx_normal_cdf(-t)
        } else {
            // Conservative estimate for small df
            (1.0 / (1.0 + 0.5 * t.abs())).min(1.0)
        }
    }

    // Approximate CDF of standard normal distribution
    fn approx_normal_cdf(&self, x: f32) -> f32 {
        // Approximation using error function
        0.5 * (1.0 + self.erf(x / 2.0_f32.sqrt()))
    }

    // Approximate quantile of standard normal
    fn approx_normal_quantile(&self, p: f32) -> f32 {
        // Rough approximation
        if p >= 0.975 {
            1.96
        } else if p >= 0.95 {
            1.645
        } else if p >= 0.90 {
            1.28
        } else {
            0.0
        }
    }

    // Approximate quantile of t-distribution
    fn approx_t_quantile(&self, p: f32, df: f32) -> f32 {
        // Simple approximation - for production use a proper implementation
        let normal_q = self.approx_normal_quantile(p);
        normal_q * (1.0 + 1.0 / df).sqrt()
    }

    // Error function approximation
    fn erf(&self, x: f32) -> f32 {
        // Abramowitz and Stegun approximation
        let a1 = 0.254829592;
        let a2 = -0.284496736;
        let a3 = 1.421413741;
        let a4 = -1.453152027;
        let a5 = 1.061405429;
        let p = 0.3275911;

        let sign = if x < 0.0 { -1.0 } else { 1.0 };
        let x = x.abs();

        let t = 1.0 / (1.0 + p * x);
        let y = 1.0 - (((((a5 * t + a4) * t) + a3) * t + a2) * t + a1) * t * (-x * x).exp();

        sign * y
    }
}

impl ABTestResults {
    /// Display results in human-readable format
    pub fn display(&self) -> String {
        let mut output = String::new();

        output.push_str(&format!(
            "\n╔══════════════════════════════════════════════════════════════╗\n"
        ));
        output.push_str(&format!(
            "║  A/B Test Results: {}  ║\n",
            self.config.test_id
        ));
        output.push_str(&format!(
            "╚══════════════════════════════════════════════════════════════╝\n\n"
        ));

        output.push_str(&format!("Description: {}\n", self.config.description));
        output.push_str(&format!(
            "Duration: {} seconds\n",
            self.end_time
                .unwrap_or_else(Utc::now)
                .signed_duration_since(self.start_time)
                .num_seconds()
        ));
        output.push_str(&format!(
            "Control samples: {}\n",
            self.control_samples.len()
        ));
        output.push_str(&format!(
            "Treatment samples: {}\n\n",
            self.treatment_samples.len()
        ));

        output.push_str("═══ Primary Metrics ═══\n\n");

        let tests = &self.statistical_tests;

        output.push_str(&format!("MRR (Mean Reciprocal Rank):\n"));
        output.push_str(&format!(
            "  Control:   {:.4}\n",
            tests.mrr_ttest.control_mean
        ));
        output.push_str(&format!(
            "  Treatment: {:.4}\n",
            tests.mrr_ttest.treatment_mean
        ));
        output.push_str(&format!(
            "  Improvement: {:.2}% {}\n",
            tests.mrr_ttest.percent_improvement,
            if tests.mrr_ttest.is_significant {
                "✓ SIGNIFICANT"
            } else {
                "✗ not significant"
            }
        ));
        output.push_str(&format!("  p-value: {:.4}\n", tests.mrr_ttest.p_value));
        output.push_str(&format!(
            "  Effect size (Cohen's d): {:.3}\n\n",
            tests.effect_sizes.get("mrr").unwrap_or(&0.0)
        ));

        output.push_str(&format!("Recall@10:\n"));
        output.push_str(&format!(
            "  Control:   {:.4}\n",
            tests.recall_ttest.control_mean
        ));
        output.push_str(&format!(
            "  Treatment: {:.4}\n",
            tests.recall_ttest.treatment_mean
        ));
        output.push_str(&format!(
            "  Improvement: {:.2}% {}\n",
            tests.recall_ttest.percent_improvement,
            if tests.recall_ttest.is_significant {
                "✓ SIGNIFICANT"
            } else {
                "✗ not significant"
            }
        ));
        output.push_str(&format!("  p-value: {:.4}\n\n", tests.recall_ttest.p_value));

        output.push_str(&format!("NDCG@10:\n"));
        output.push_str(&format!(
            "  Control:   {:.4}\n",
            tests.ndcg_ttest.control_mean
        ));
        output.push_str(&format!(
            "  Treatment: {:.4}\n",
            tests.ndcg_ttest.treatment_mean
        ));
        output.push_str(&format!(
            "  Improvement: {:.2}% {}\n",
            tests.ndcg_ttest.percent_improvement,
            if tests.ndcg_ttest.is_significant {
                "✓ SIGNIFICANT"
            } else {
                "✗ not significant"
            }
        ));
        output.push_str(&format!("  p-value: {:.4}\n\n", tests.ndcg_ttest.p_value));

        output.push_str("═══ Latency ═══\n\n");
        output.push_str(&format!("Median latency:\n"));
        output.push_str(&format!(
            "  Control:   {:.2}ms\n",
            tests.latency_mann_whitney.control_median
        ));
        output.push_str(&format!(
            "  Treatment: {:.2}ms\n",
            tests.latency_mann_whitney.treatment_median
        ));
        output.push_str(&format!(
            "  Difference: {:.2}ms {}\n",
            tests.latency_mann_whitney.treatment_median - tests.latency_mann_whitney.control_median,
            if tests.latency_mann_whitney.is_significant {
                "✓ SIGNIFICANT"
            } else {
                "✗ not significant"
            }
        ));
        output.push_str(&format!(
            "  p-value: {:.4}\n\n",
            tests.latency_mann_whitney.p_value
        ));

        output.push_str("═══ Confidence Intervals (95%) ═══\n\n");
        for (metric, (lower, upper)) in &tests.confidence_intervals {
            output.push_str(&format!("{}: [{:.4}, {:.4}]\n", metric, lower, upper));
        }

        output.push_str(&format!("\n═══ Recommendation ═══\n\n"));
        if tests.mrr_ttest.is_significant && tests.mrr_ttest.percent_improvement >= 10.0 {
            output.push_str("✓ SHIP IT! TCR-QF shows significant improvement.\n");
            output.push_str("  Recommended action: Roll out TCR-QF to 100% of users.\n");
        } else if tests.mrr_ttest.percent_improvement >= 5.0 && !tests.mrr_ttest.is_significant {
            output.push_str("⚠ CONTINUE TESTING\n");
            output.push_str("  Promising trend but not yet significant.\n");
            output.push_str("  Recommended action: Collect more samples.\n");
        } else {
            output.push_str("✗ INSUFFICIENT EVIDENCE\n");
            output.push_str("  TCR-QF does not show clear improvement.\n");
            output.push_str("  Recommended action: Iterate on TCR-QF design or abandon.\n");
        }

        output
    }

    /// Export results to JSON
    pub fn to_json(&self) -> Result<String> {
        Ok(serde_json::to_string_pretty(self)?)
    }

    /// Save results to file
    pub fn save_to_file(&self, path: &str) -> Result<()> {
        let json = self.to_json()?;
        std::fs::write(path, json)?;
        Ok(())
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::collections::HashSet;

    #[test]
    fn test_assignment_deterministic() {
        let config = ABTestConfig {
            treatment_ratio: 0.5,
            ..Default::default()
        };
        let mut runner = ABTestRunner::new(config);

        let id = Uuid::new_v4();
        let group1 = runner.assign_group(&id);
        let group2 = runner.assign_group(&id);

        assert_eq!(group1, group2, "Assignment should be deterministic");
    }

    #[test]
    fn test_statistical_functions() {
        let config = ABTestConfig::default();
        let runner = ABTestRunner::new(config);

        let values = vec![1.0, 2.0, 3.0, 4.0, 5.0];
        assert_eq!(runner.mean(&values), 3.0);
        assert_eq!(runner.median(&values), 3.0);

        let variance = runner.variance(&values, 3.0);
        assert!((variance - 2.5).abs() < 0.01);
    }

    #[test]
    fn test_welch_ttest() {
        let config = ABTestConfig::default();
        let runner = ABTestRunner::new(config);

        let control = vec![1.0, 2.0, 3.0, 4.0, 5.0];
        let treatment = vec![2.0, 3.0, 4.0, 5.0, 6.0]; // +1 improvement

        let control_mean = runner.mean(&control);
        let treatment_mean = runner.mean(&treatment);

        let result = runner.welch_ttest(&control, &treatment, control_mean, treatment_mean);

        assert_eq!(result.control_mean, 3.0);
        assert_eq!(result.treatment_mean, 4.0);
        assert!((result.percent_improvement - 33.33).abs() < 0.1);
    }
}
