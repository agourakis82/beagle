//! Evaluation metrics for GraphRAG retrieval quality
//!
//! Implements standard Information Retrieval metrics:
//! - MRR (Mean Reciprocal Rank)
//! - Recall@k
//! - NDCG@k (Normalized Discounted Cumulative Gain)
//! - MAP (Mean Average Precision)

use serde::{Deserialize, Serialize};
use std::collections::{HashMap, HashSet};
use uuid::Uuid;

/// Retrieval evaluation metrics
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct RetrievalMetrics {
    /// Mean Reciprocal Rank: 1/N * Σ(1/rank_of_first_relevant)
    pub mrr: f32,

    /// Recall at different k values: |retrieved ∩ relevant| / |relevant|
    pub recall_at_k: HashMap<usize, f32>,

    /// Normalized Discounted Cumulative Gain at different k values
    pub ndcg_at_k: HashMap<usize, f32>,

    /// Mean Average Precision
    pub map: f32,

    /// Precision at different k values: |retrieved ∩ relevant| / k
    pub precision_at_k: HashMap<usize, f32>,

    /// Total number of queries evaluated
    pub num_queries: usize,

    /// Average latency in milliseconds
    pub avg_latency_ms: f32,

    /// 50th percentile latency
    pub p50_latency_ms: f32,

    /// 95th percentile latency
    pub p95_latency_ms: f32,

    /// 99th percentile latency
    pub p99_latency_ms: f32,
}

impl Default for RetrievalMetrics {
    fn default() -> Self {
        let mut recall_at_k = HashMap::new();
        recall_at_k.insert(1, 0.0);
        recall_at_k.insert(5, 0.0);
        recall_at_k.insert(10, 0.0);
        recall_at_k.insert(20, 0.0);

        let mut ndcg_at_k = HashMap::new();
        ndcg_at_k.insert(1, 0.0);
        ndcg_at_k.insert(5, 0.0);
        ndcg_at_k.insert(10, 0.0);
        ndcg_at_k.insert(20, 0.0);

        let mut precision_at_k = HashMap::new();
        precision_at_k.insert(1, 0.0);
        precision_at_k.insert(5, 0.0);
        precision_at_k.insert(10, 0.0);
        precision_at_k.insert(20, 0.0);

        Self {
            mrr: 0.0,
            recall_at_k,
            ndcg_at_k,
            map: 0.0,
            precision_at_k,
            num_queries: 0,
            avg_latency_ms: 0.0,
            p50_latency_ms: 0.0,
            p95_latency_ms: 0.0,
            p99_latency_ms: 0.0,
        }
    }
}

impl RetrievalMetrics {
    /// Pretty print metrics for display
    pub fn display(&self) -> String {
        format!(
            r#"Retrieval Metrics (n={})
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  MRR:              {:.4}
  MAP:              {:.4}

  Recall@1:         {:.4}
  Recall@5:         {:.4}
  Recall@10:        {:.4}
  Recall@20:        {:.4}

  NDCG@1:           {:.4}
  NDCG@5:           {:.4}
  NDCG@10:          {:.4}
  NDCG@20:          {:.4}

  Precision@1:      {:.4}
  Precision@5:      {:.4}
  Precision@10:     {:.4}
  Precision@20:     {:.4}

  Latency (avg):    {:.1}ms
  Latency (p50):    {:.1}ms
  Latency (p95):    {:.1}ms
  Latency (p99):    {:.1}ms
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"#,
            self.num_queries,
            self.mrr,
            self.map,
            self.recall_at_k.get(&1).unwrap_or(&0.0),
            self.recall_at_k.get(&5).unwrap_or(&0.0),
            self.recall_at_k.get(&10).unwrap_or(&0.0),
            self.recall_at_k.get(&20).unwrap_or(&0.0),
            self.ndcg_at_k.get(&1).unwrap_or(&0.0),
            self.ndcg_at_k.get(&5).unwrap_or(&0.0),
            self.ndcg_at_k.get(&10).unwrap_or(&0.0),
            self.ndcg_at_k.get(&20).unwrap_or(&0.0),
            self.precision_at_k.get(&1).unwrap_or(&0.0),
            self.precision_at_k.get(&5).unwrap_or(&0.0),
            self.precision_at_k.get(&10).unwrap_or(&0.0),
            self.precision_at_k.get(&20).unwrap_or(&0.0),
            self.avg_latency_ms,
            self.p50_latency_ms,
            self.p95_latency_ms,
            self.p99_latency_ms,
        )
    }

    /// Compare with another metric set and show improvement
    pub fn compare(&self, baseline: &RetrievalMetrics) -> String {
        let mrr_improvement = ((self.mrr - baseline.mrr) / baseline.mrr * 100.0).max(-100.0);
        let recall10_improvement = ((self.recall_at_k.get(&10).unwrap_or(&0.0)
            - baseline.recall_at_k.get(&10).unwrap_or(&0.0))
            / baseline.recall_at_k.get(&10).unwrap_or(&1.0)
            * 100.0)
            .max(-100.0);
        let ndcg10_improvement = ((self.ndcg_at_k.get(&10).unwrap_or(&0.0)
            - baseline.ndcg_at_k.get(&10).unwrap_or(&0.0))
            / baseline.ndcg_at_k.get(&10).unwrap_or(&1.0)
            * 100.0)
            .max(-100.0);
        let latency_change =
            ((self.avg_latency_ms - baseline.avg_latency_ms) / baseline.avg_latency_ms * 100.0)
                .max(-100.0);

        format!(
            r#"Improvement vs Baseline
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  MRR:              {:+.1}%  ({:.4} → {:.4})
  Recall@10:        {:+.1}%  ({:.4} → {:.4})
  NDCG@10:          {:+.1}%  ({:.4} → {:.4})
  Latency:          {:+.1}%  ({:.1}ms → {:.1}ms)
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"#,
            mrr_improvement,
            baseline.mrr,
            self.mrr,
            recall10_improvement,
            baseline.recall_at_k.get(&10).unwrap_or(&0.0),
            self.recall_at_k.get(&10).unwrap_or(&0.0),
            ndcg10_improvement,
            baseline.ndcg_at_k.get(&10).unwrap_or(&0.0),
            self.ndcg_at_k.get(&10).unwrap_or(&0.0),
            latency_change,
            baseline.avg_latency_ms,
            self.avg_latency_ms,
        )
    }
}

/// Single query result for evaluation
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct QueryResult {
    /// Retrieved node IDs in ranked order
    pub retrieved: Vec<Uuid>,

    /// Latency in milliseconds
    pub latency_ms: f32,
}

/// Ground truth for a single query
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct GroundTruth {
    /// Relevant node IDs
    pub relevant: HashSet<Uuid>,

    /// Relevance scores (0.0-1.0) for graded relevance
    pub relevance_scores: HashMap<Uuid, f32>,
}

/// Evaluator for retrieval quality
pub struct RetrievalEvaluator {
    k_values: Vec<usize>,
}

impl Default for RetrievalEvaluator {
    fn default() -> Self {
        Self {
            k_values: vec![1, 5, 10, 20],
        }
    }
}

impl RetrievalEvaluator {
    pub fn new(k_values: Vec<usize>) -> Self {
        Self { k_values }
    }

    /// Evaluate retrieval results against ground truth
    pub fn evaluate(
        &self,
        results: &[QueryResult],
        ground_truths: &[GroundTruth],
    ) -> RetrievalMetrics {
        assert_eq!(
            results.len(),
            ground_truths.len(),
            "Results and ground truths must have same length"
        );

        let num_queries = results.len();
        if num_queries == 0 {
            return RetrievalMetrics::default();
        }

        // Compute MRR
        let mrr = self.compute_mrr(results, ground_truths);

        // Compute Recall@k
        let mut recall_at_k = HashMap::new();
        for &k in &self.k_values {
            recall_at_k.insert(k, self.compute_recall_at_k(results, ground_truths, k));
        }

        // Compute NDCG@k
        let mut ndcg_at_k = HashMap::new();
        for &k in &self.k_values {
            ndcg_at_k.insert(k, self.compute_ndcg_at_k(results, ground_truths, k));
        }

        // Compute MAP
        let map = self.compute_map(results, ground_truths);

        // Compute Precision@k
        let mut precision_at_k = HashMap::new();
        for &k in &self.k_values {
            precision_at_k.insert(k, self.compute_precision_at_k(results, ground_truths, k));
        }

        // Compute latency statistics
        let mut latencies: Vec<f32> = results.iter().map(|r| r.latency_ms).collect();
        latencies.sort_by(|a, b| a.partial_cmp(b).unwrap_or(std::cmp::Ordering::Equal));

        let avg_latency_ms = latencies.iter().sum::<f32>() / latencies.len() as f32;
        let p50_latency_ms = latencies[latencies.len() / 2];
        let p95_latency_ms = latencies[latencies.len() * 95 / 100];
        let p99_latency_ms = latencies[latencies.len() * 99 / 100];

        RetrievalMetrics {
            mrr,
            recall_at_k,
            ndcg_at_k,
            map,
            precision_at_k,
            num_queries,
            avg_latency_ms,
            p50_latency_ms,
            p95_latency_ms,
            p99_latency_ms,
        }
    }

    /// Mean Reciprocal Rank: 1/N * Σ(1/rank_of_first_relevant)
    fn compute_mrr(&self, results: &[QueryResult], ground_truths: &[GroundTruth]) -> f32 {
        let mut sum = 0.0;

        for (result, gt) in results.iter().zip(ground_truths.iter()) {
            for (rank, &node_id) in result.retrieved.iter().enumerate() {
                if gt.relevant.contains(&node_id) {
                    sum += 1.0 / (rank + 1) as f32;
                    break;
                }
            }
        }

        sum / results.len() as f32
    }

    /// Recall@k: |retrieved_at_k ∩ relevant| / |relevant|
    fn compute_recall_at_k(
        &self,
        results: &[QueryResult],
        ground_truths: &[GroundTruth],
        k: usize,
    ) -> f32 {
        let mut sum = 0.0;

        for (result, gt) in results.iter().zip(ground_truths.iter()) {
            if gt.relevant.is_empty() {
                continue;
            }

            let retrieved_at_k: HashSet<Uuid> = result.retrieved.iter().take(k).copied().collect();
            let intersection_size = retrieved_at_k.intersection(&gt.relevant).count();

            sum += intersection_size as f32 / gt.relevant.len() as f32;
        }

        sum / results.len() as f32
    }

    /// Precision@k: |retrieved_at_k ∩ relevant| / k
    fn compute_precision_at_k(
        &self,
        results: &[QueryResult],
        ground_truths: &[GroundTruth],
        k: usize,
    ) -> f32 {
        let mut sum = 0.0;

        for (result, gt) in results.iter().zip(ground_truths.iter()) {
            let retrieved_at_k: HashSet<Uuid> = result.retrieved.iter().take(k).copied().collect();
            let intersection_size = retrieved_at_k.intersection(&gt.relevant).count();

            sum += intersection_size as f32 / k as f32;
        }

        sum / results.len() as f32
    }

    /// NDCG@k: Normalized Discounted Cumulative Gain
    fn compute_ndcg_at_k(
        &self,
        results: &[QueryResult],
        ground_truths: &[GroundTruth],
        k: usize,
    ) -> f32 {
        let mut sum = 0.0;

        for (result, gt) in results.iter().zip(ground_truths.iter()) {
            let dcg = self.compute_dcg(&result.retrieved, &gt.relevance_scores, k);
            let idcg = self.compute_idcg(&gt.relevance_scores, k);

            if idcg > 0.0 {
                sum += dcg / idcg;
            }
        }

        sum / results.len() as f32
    }

    /// DCG: Discounted Cumulative Gain
    fn compute_dcg(
        &self,
        retrieved: &[Uuid],
        relevance_scores: &HashMap<Uuid, f32>,
        k: usize,
    ) -> f32 {
        let mut dcg = 0.0;

        for (i, &node_id) in retrieved.iter().take(k).enumerate() {
            let relevance = relevance_scores.get(&node_id).copied().unwrap_or(0.0);
            let rank = i + 1;

            // DCG = Σ (2^rel - 1) / log2(rank + 1)
            dcg += (2.0_f32.powf(relevance) - 1.0) / (rank as f32 + 1.0).log2();
        }

        dcg
    }

    /// IDCG: Ideal DCG (best possible ranking)
    fn compute_idcg(&self, relevance_scores: &HashMap<Uuid, f32>, k: usize) -> f32 {
        let mut scores: Vec<f32> = relevance_scores.values().copied().collect();
        scores.sort_by(|a, b| b.partial_cmp(a).unwrap_or(std::cmp::Ordering::Equal));

        let mut idcg = 0.0;
        for (i, &score) in scores.iter().take(k).enumerate() {
            let rank = i + 1;
            idcg += (2.0_f32.powf(score) - 1.0) / (rank as f32 + 1.0).log2();
        }

        idcg
    }

    /// MAP: Mean Average Precision
    fn compute_map(&self, results: &[QueryResult], ground_truths: &[GroundTruth]) -> f32 {
        let mut sum = 0.0;

        for (result, gt) in results.iter().zip(ground_truths.iter()) {
            sum += self.compute_average_precision(&result.retrieved, &gt.relevant);
        }

        sum / results.len() as f32
    }

    /// Average Precision for a single query
    fn compute_average_precision(&self, retrieved: &[Uuid], relevant: &HashSet<Uuid>) -> f32 {
        if relevant.is_empty() {
            return 0.0;
        }

        let mut sum = 0.0;
        let mut num_relevant_found = 0;

        for (i, &node_id) in retrieved.iter().enumerate() {
            if relevant.contains(&node_id) {
                num_relevant_found += 1;
                let precision_at_i = num_relevant_found as f32 / (i + 1) as f32;
                sum += precision_at_i;
            }
        }

        sum / relevant.len() as f32
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_mrr_perfect() {
        let evaluator = RetrievalEvaluator::default();

        let node1 = Uuid::new_v4();
        let node2 = Uuid::new_v4();

        let results = vec![QueryResult {
            retrieved: vec![node1, node2],
            latency_ms: 100.0,
        }];

        let mut relevant = HashSet::new();
        relevant.insert(node1);

        let ground_truths = vec![GroundTruth {
            relevant,
            relevance_scores: HashMap::new(),
        }];

        let metrics = evaluator.evaluate(&results, &ground_truths);
        assert_eq!(
            metrics.mrr, 1.0,
            "MRR should be 1.0 when first result is relevant"
        );
    }

    #[test]
    fn test_recall_at_k() {
        let evaluator = RetrievalEvaluator::default();

        let node1 = Uuid::new_v4();
        let node2 = Uuid::new_v4();
        let node3 = Uuid::new_v4();

        let results = vec![QueryResult {
            retrieved: vec![node1, node3],
            latency_ms: 100.0,
        }];

        let mut relevant = HashSet::new();
        relevant.insert(node1);
        relevant.insert(node2);

        let ground_truths = vec![GroundTruth {
            relevant,
            relevance_scores: HashMap::new(),
        }];

        let metrics = evaluator.evaluate(&results, &ground_truths);
        assert_eq!(
            metrics.recall_at_k.get(&10).unwrap(),
            &0.5,
            "Recall@10 should be 0.5 (1 of 2 relevant retrieved)"
        );
    }
}
