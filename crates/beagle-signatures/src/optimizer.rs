//! Prompt optimizer inspired by DSPy MIPROv2
//!
//! Provides automatic prompt optimization through:
//! 1. Bootstrapping - Collecting high-scoring traces
//! 2. Proposal - Generating improved instructions
//! 3. Search - Evaluating combinations

use std::collections::HashMap;
use std::sync::Arc;

use chrono::{DateTime, Utc};
use serde::{de::DeserializeOwned, Deserialize, Serialize};
use tokio::sync::RwLock;
use uuid::Uuid;

use crate::error::{SignatureError, SignatureResult};
use crate::signature::{PromptSignature, SignatureExample, SignatureMetadata};

/// A trace of a signature execution
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ExecutionTrace<I, O>
where
    I: Serialize + Clone,
    O: Serialize + Clone,
{
    /// Unique trace ID
    pub id: Uuid,
    /// Input used
    pub input: I,
    /// Output produced
    pub output: O,
    /// Score from metric
    pub score: f64,
    /// Latency in milliseconds
    pub latency_ms: u64,
    /// Timestamp
    pub timestamp: DateTime<Utc>,
    /// Instructions used (if any custom)
    pub instructions: Option<String>,
    /// Provider/model used
    pub provider: Option<String>,
}

impl<I, O> ExecutionTrace<I, O>
where
    I: Serialize + Clone,
    O: Serialize + Clone,
{
    /// Create a new trace
    pub fn new(input: I, output: O, score: f64, latency_ms: u64) -> Self {
        Self {
            id: Uuid::new_v4(),
            input,
            output,
            score,
            latency_ms,
            timestamp: Utc::now(),
            instructions: None,
            provider: None,
        }
    }
}

/// Result of optimization
#[derive(Debug, Clone)]
pub struct OptimizationResult<S: PromptSignature> {
    /// Best instructions found
    pub best_instructions: String,
    /// Best examples for few-shot
    pub best_examples: Vec<SignatureExample>,
    /// Score improvement (from baseline to optimized)
    pub score_improvement: f64,
    /// Final validation score
    pub final_score: f64,
    /// Number of iterations run
    pub iterations: usize,
    /// Optimized signature (with updated metadata)
    pub optimized_signature: S,
}

impl<S: PromptSignature + Default> Default for OptimizationResult<S> {
    fn default() -> Self {
        Self {
            best_instructions: String::new(),
            best_examples: Vec::new(),
            score_improvement: 0.0,
            final_score: 0.0,
            iterations: 0,
            optimized_signature: S::default(),
        }
    }
}

/// Configuration for the optimizer
#[derive(Debug, Clone)]
pub struct OptimizerConfig {
    /// Minimum score to keep a trace in bootstrap
    pub min_bootstrap_score: f64,
    /// Maximum traces to keep
    pub max_traces: usize,
    /// Number of instruction candidates to generate
    pub num_candidates: usize,
    /// Number of examples for few-shot
    pub num_examples: usize,
    /// Validation batch size
    pub validation_batch_size: usize,
    /// Maximum optimization iterations
    pub max_iterations: usize,
    /// Early stopping threshold (stop if improvement < this)
    pub early_stop_threshold: f64,
}

impl Default for OptimizerConfig {
    fn default() -> Self {
        Self {
            min_bootstrap_score: 0.7,
            max_traces: 100,
            num_candidates: 5,
            num_examples: 3,
            validation_batch_size: 10,
            max_iterations: 10,
            early_stop_threshold: 0.01,
        }
    }
}

/// Prompt optimizer using DSPy-style optimization
pub struct PromptOptimizer<S, I, O>
where
    S: PromptSignature<Input = I, Output = O> + Clone,
    I: Serialize + DeserializeOwned + Clone + Send + Sync,
    O: Serialize + DeserializeOwned + Clone + Send + Sync,
{
    /// Base signature
    signature: S,
    /// Configuration
    config: OptimizerConfig,
    /// Collected traces
    traces: Arc<RwLock<Vec<ExecutionTrace<I, O>>>>,
    /// Metric function (output -> score)
    metric: Arc<dyn Fn(&O) -> f64 + Send + Sync>,
    /// Best instructions so far
    best_instructions: Arc<RwLock<Option<String>>>,
    /// Best examples so far
    best_examples: Arc<RwLock<Vec<SignatureExample>>>,
    /// Baseline score
    baseline_score: Arc<RwLock<Option<f64>>>,
}

impl<S, I, O> PromptOptimizer<S, I, O>
where
    S: PromptSignature<Input = I, Output = O> + Clone + Send + Sync,
    I: Serialize + DeserializeOwned + Clone + Send + Sync + 'static,
    O: Serialize + DeserializeOwned + Clone + Send + Sync + 'static,
{
    /// Create a new optimizer
    pub fn new<F>(signature: S, metric: F) -> Self
    where
        F: Fn(&O) -> f64 + Send + Sync + 'static,
    {
        Self {
            signature,
            config: OptimizerConfig::default(),
            traces: Arc::new(RwLock::new(Vec::new())),
            metric: Arc::new(metric),
            best_instructions: Arc::new(RwLock::new(None)),
            best_examples: Arc::new(RwLock::new(Vec::new())),
            baseline_score: Arc::new(RwLock::new(None)),
        }
    }

    /// Create with custom config
    pub fn with_config<F>(signature: S, metric: F, config: OptimizerConfig) -> Self
    where
        F: Fn(&O) -> f64 + Send + Sync + 'static,
    {
        Self {
            signature,
            config,
            traces: Arc::new(RwLock::new(Vec::new())),
            metric: Arc::new(metric),
            best_instructions: Arc::new(RwLock::new(None)),
            best_examples: Arc::new(RwLock::new(Vec::new())),
            baseline_score: Arc::new(RwLock::new(None)),
        }
    }

    /// Add a trace from execution
    pub async fn add_trace(&self, trace: ExecutionTrace<I, O>) {
        let mut traces = self.traces.write().await;

        // Only keep high-scoring traces
        if trace.score >= self.config.min_bootstrap_score {
            traces.push(trace);

            // Keep only top traces by score
            if traces.len() > self.config.max_traces {
                traces.sort_by(|a, b| b.score.partial_cmp(&a.score).unwrap());
                traces.truncate(self.config.max_traces);
            }
        }
    }

    /// Bootstrap phase: execute signature on inputs and collect traces
    pub async fn bootstrap<F, Fut>(
        &self,
        inputs: &[I],
        execute_fn: F,
    ) -> SignatureResult<usize>
    where
        F: Fn(&S, &I) -> Fut + Send + Sync,
        Fut: std::future::Future<Output = SignatureResult<O>> + Send,
    {
        let mut collected = 0;

        for input in inputs {
            let start = std::time::Instant::now();

            match execute_fn(&self.signature, input).await {
                Ok(output) => {
                    let latency = start.elapsed().as_millis() as u64;
                    let score = (self.metric)(&output);

                    let trace = ExecutionTrace::new(input.clone(), output, score, latency);
                    self.add_trace(trace).await;
                    collected += 1;
                }
                Err(e) => {
                    tracing::warn!("Bootstrap execution failed: {}", e);
                }
            }
        }

        // Calculate baseline score
        let traces = self.traces.read().await;
        if !traces.is_empty() {
            let avg_score = traces.iter().map(|t| t.score).sum::<f64>() / traces.len() as f64;
            *self.baseline_score.write().await = Some(avg_score);
        }

        Ok(collected)
    }

    /// Propose improved instructions based on traces
    pub async fn propose_instructions<F, Fut>(
        &self,
        propose_fn: F,
    ) -> SignatureResult<Vec<String>>
    where
        F: Fn(String) -> Fut + Send + Sync,
        Fut: std::future::Future<Output = SignatureResult<String>> + Send,
    {
        let traces = self.traces.read().await;

        if traces.is_empty() {
            return Err(SignatureError::Optimization(
                "No traces available for proposal".to_string(),
            ));
        }

        // Sort by score and take top traces
        let mut sorted_traces: Vec<_> = traces.iter().collect();
        sorted_traces.sort_by(|a, b| b.score.partial_cmp(&a.score).unwrap());

        // Build meta-prompt for instruction generation
        let meta = self.signature.metadata();
        let top_traces: Vec<_> = sorted_traces.iter().take(5).collect();

        let meta_prompt = format!(
            r#"You are an expert prompt engineer. Your task is to improve the instructions for a prompt signature.

Current signature: {}
Description: {}
Current instructions: {}

Here are examples of high-scoring executions:
{}

Based on these successful patterns, generate {} improved instruction variants.
Each variant should be a complete instruction set that could replace the current one.
Focus on:
1. Clarity and specificity
2. Structure and organization
3. Guidance for edge cases
4. Tone and style appropriate for the task

Return each variant as a numbered list:
1. [First improved instruction set]
2. [Second improved instruction set]
..."#,
            meta.name,
            meta.description,
            meta.instructions.as_deref().unwrap_or("None"),
            top_traces
                .iter()
                .enumerate()
                .map(|(i, t)| format!(
                    "Example {}: Score {:.2}\nInput: {:?}\nOutput: {:?}",
                    i + 1,
                    t.score,
                    serde_json::to_string(&t.input).unwrap_or_default(),
                    serde_json::to_string(&t.output).unwrap_or_default()
                ))
                .collect::<Vec<_>>()
                .join("\n\n"),
            self.config.num_candidates
        );

        let response = propose_fn(meta_prompt).await?;

        // Parse numbered list from response
        let candidates: Vec<String> = crate::parser::OutputParser::parse_numbered_list(&response)
            .into_iter()
            .take(self.config.num_candidates)
            .collect();

        if candidates.is_empty() {
            // Fall back to the whole response as one candidate
            Ok(vec![response])
        } else {
            Ok(candidates)
        }
    }

    /// Select best examples for few-shot learning
    pub async fn select_examples(&self) -> Vec<SignatureExample> {
        let traces = self.traces.read().await;

        // Sort by score and take top N
        let mut sorted_traces: Vec<_> = traces.iter().collect();
        sorted_traces.sort_by(|a, b| b.score.partial_cmp(&a.score).unwrap());

        sorted_traces
            .iter()
            .take(self.config.num_examples)
            .map(|t| SignatureExample {
                input: serde_json::to_value(&t.input).unwrap_or_default(),
                output: serde_json::to_value(&t.output).unwrap_or_default(),
                explanation: None,
            })
            .collect()
    }

    /// Evaluate a candidate instruction on validation set
    pub async fn evaluate_candidate<F, Fut>(
        &self,
        instructions: &str,
        validation_inputs: &[I],
        execute_fn: F,
    ) -> SignatureResult<f64>
    where
        F: Fn(&S, &I, &str) -> Fut + Send + Sync,
        Fut: std::future::Future<Output = SignatureResult<O>> + Send,
    {
        let mut scores = Vec::new();

        for input in validation_inputs.iter().take(self.config.validation_batch_size) {
            match execute_fn(&self.signature, input, instructions).await {
                Ok(output) => {
                    let score = (self.metric)(&output);
                    scores.push(score);
                }
                Err(e) => {
                    tracing::warn!("Validation execution failed: {}", e);
                    scores.push(0.0);
                }
            }
        }

        if scores.is_empty() {
            return Ok(0.0);
        }

        Ok(scores.iter().sum::<f64>() / scores.len() as f64)
    }

    /// Get current best configuration
    pub async fn get_best(&self) -> (Option<String>, Vec<SignatureExample>) {
        let instructions = self.best_instructions.read().await.clone();
        let examples = self.best_examples.read().await.clone();
        (instructions, examples)
    }

    /// Get trace count
    pub async fn trace_count(&self) -> usize {
        self.traces.read().await.len()
    }

    /// Get average trace score
    pub async fn average_score(&self) -> Option<f64> {
        let traces = self.traces.read().await;
        if traces.is_empty() {
            None
        } else {
            Some(traces.iter().map(|t| t.score).sum::<f64>() / traces.len() as f64)
        }
    }

    /// Get baseline score
    pub async fn baseline_score(&self) -> Option<f64> {
        *self.baseline_score.read().await
    }

    /// Clear all traces
    pub async fn clear_traces(&self) {
        self.traces.write().await.clear();
    }
}

/// Statistics about optimization
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct OptimizationStats {
    /// Number of traces collected
    pub trace_count: usize,
    /// Average trace score
    pub average_score: f64,
    /// Best trace score
    pub best_score: f64,
    /// Worst trace score
    pub worst_score: f64,
    /// Score standard deviation
    pub score_std_dev: f64,
    /// Average latency in ms
    pub average_latency_ms: f64,
}

impl OptimizationStats {
    /// Calculate stats from traces
    pub fn from_traces<I, O>(traces: &[ExecutionTrace<I, O>]) -> Self
    where
        I: Serialize + Clone,
        O: Serialize + Clone,
    {
        if traces.is_empty() {
            return Self {
                trace_count: 0,
                average_score: 0.0,
                best_score: 0.0,
                worst_score: 0.0,
                score_std_dev: 0.0,
                average_latency_ms: 0.0,
            };
        }

        let scores: Vec<f64> = traces.iter().map(|t| t.score).collect();
        let latencies: Vec<f64> = traces.iter().map(|t| t.latency_ms as f64).collect();

        let avg_score = scores.iter().sum::<f64>() / scores.len() as f64;
        let avg_latency = latencies.iter().sum::<f64>() / latencies.len() as f64;

        let variance = scores.iter().map(|s| (s - avg_score).powi(2)).sum::<f64>()
            / scores.len() as f64;

        Self {
            trace_count: traces.len(),
            average_score: avg_score,
            best_score: scores.iter().cloned().fold(f64::MIN, f64::max),
            worst_score: scores.iter().cloned().fold(f64::MAX, f64::min),
            score_std_dev: variance.sqrt(),
            average_latency_ms: avg_latency,
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::signature::{DynamicSignature, SignatureBuilder};

    fn create_test_signature() -> DynamicSignature {
        DynamicSignature::from_builder(
            SignatureBuilder::new("TestSig")
                .description("Test signature")
                .input("question", "The question")
                .output("answer", "The answer"),
        )
    }

    #[tokio::test]
    async fn test_optimizer_creation() {
        let sig = create_test_signature();
        let optimizer = PromptOptimizer::new(sig, |_output: &serde_json::Value| 0.8);

        assert_eq!(optimizer.trace_count().await, 0);
        assert!(optimizer.average_score().await.is_none());
    }

    #[tokio::test]
    async fn test_add_trace() {
        let sig = create_test_signature();
        let optimizer = PromptOptimizer::new(sig, |_output: &serde_json::Value| 0.8);

        let trace = ExecutionTrace::new(
            serde_json::json!({"question": "test"}),
            serde_json::json!({"answer": "result"}),
            0.85,
            100,
        );

        optimizer.add_trace(trace).await;
        assert_eq!(optimizer.trace_count().await, 1);
    }

    #[tokio::test]
    async fn test_trace_filtering() {
        let sig = create_test_signature();
        let config = OptimizerConfig {
            min_bootstrap_score: 0.8,
            ..Default::default()
        };
        let optimizer =
            PromptOptimizer::with_config(sig, |_output: &serde_json::Value| 0.8, config);

        // Low score trace should be filtered
        let low_trace = ExecutionTrace::new(
            serde_json::json!({"question": "test"}),
            serde_json::json!({"answer": "result"}),
            0.5, // Below threshold
            100,
        );
        optimizer.add_trace(low_trace).await;
        assert_eq!(optimizer.trace_count().await, 0);

        // High score trace should be kept
        let high_trace = ExecutionTrace::new(
            serde_json::json!({"question": "test"}),
            serde_json::json!({"answer": "result"}),
            0.9, // Above threshold
            100,
        );
        optimizer.add_trace(high_trace).await;
        assert_eq!(optimizer.trace_count().await, 1);
    }

    #[tokio::test]
    async fn test_select_examples() {
        let sig = create_test_signature();
        let optimizer = PromptOptimizer::new(sig, |_output: &serde_json::Value| 0.8);

        // Add some traces
        for i in 0..5 {
            let trace = ExecutionTrace::new(
                serde_json::json!({"question": format!("q{}", i)}),
                serde_json::json!({"answer": format!("a{}", i)}),
                0.7 + (i as f64 * 0.05), // Increasing scores
                100,
            );
            optimizer.add_trace(trace).await;
        }

        let examples = optimizer.select_examples().await;
        assert_eq!(examples.len(), 3); // Default num_examples
    }

    #[test]
    fn test_optimization_stats() {
        let traces: Vec<ExecutionTrace<serde_json::Value, serde_json::Value>> = vec![
            ExecutionTrace::new(serde_json::json!({}), serde_json::json!({}), 0.8, 100),
            ExecutionTrace::new(serde_json::json!({}), serde_json::json!({}), 0.9, 150),
            ExecutionTrace::new(serde_json::json!({}), serde_json::json!({}), 0.7, 80),
        ];

        let stats = OptimizationStats::from_traces(&traces);

        assert_eq!(stats.trace_count, 3);
        assert!((stats.average_score - 0.8).abs() < 0.01);
        assert!((stats.best_score - 0.9).abs() < 0.01);
        assert!((stats.worst_score - 0.7).abs() < 0.01);
    }
}
