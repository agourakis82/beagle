//! Deterministic nDCG@10 + Recall eval harness with a regression gate.
//!
//! This module provides:
//! - Pure, allocation-light metric functions: [`ndcg_at_k`] and [`recall_at_k`].
//! - A **frozen golden query set** — tiny, self-contained, no I/O required.
//! - A **regression gate** (`#[test] eval_gate_ndcg10_recall10`) that must stay
//!   green; it panics when averaged metrics fall below the stored baselines.
//!
//! The golden set is intentionally small (5 queries) and uses synthetic doc IDs
//! so the gate runs deterministically without any live retrieval or database.
//! Wire it to live retrieval in item #8.
//!
//! # nDCG formula
//!
//! ```text
//! DCG@k  = Σ_{i=1}^{k}  (2^rel_i − 1) / log2(i + 1)
//! IDCG@k = DCG of the ideal ranking (sorted descending by rel)
//! nDCG@k = DCG@k / IDCG@k        (0.0 when IDCG=0, i.e. no relevant docs)
//! ```
//!
//! Relevance is binary (1.0 if doc in relevant set, 0.0 otherwise).
//!
//! # Recall formula
//!
//! ```text
//! Recall@k = |retrieved[..k] ∩ relevant| / |relevant|
//! ```

use std::collections::HashSet;

// ---------------------------------------------------------------------------
// Core metric functions
// ---------------------------------------------------------------------------

/// Compute nDCG@k for a single query using **binary relevance**.
///
/// `ranked` — doc IDs in ranked order (position 0 = rank 1, highest score).
/// `relevant` — set of relevant doc IDs.
/// `k` — cutoff; only the first `k` entries of `ranked` are considered.
///
/// Returns a value in `[0.0, 1.0]`. Returns `0.0` when `relevant` is empty.
///
/// # Examples
/// ```
/// use std::collections::HashSet;
/// use beagle_hypergraph::rag::eval_gate::ndcg_at_k;
///
/// let ranked = vec![1u64, 2, 3, 4, 5];
/// let relevant: HashSet<u64> = [1, 3].into_iter().collect();
/// let score = ndcg_at_k(&ranked, &relevant, 5);
/// assert!(score > 0.0 && score <= 1.0);
/// ```
pub fn ndcg_at_k(ranked: &[u64], relevant: &HashSet<u64>, k: usize) -> f64 {
    if relevant.is_empty() || k == 0 {
        return 0.0;
    }

    let dcg = compute_dcg(ranked, relevant, k);
    let idcg = compute_idcg(relevant.len(), k);

    if idcg == 0.0 {
        0.0
    } else {
        (dcg / idcg).min(1.0)
    }
}

/// Compute Recall@k for a single query.
///
/// Returns the fraction of relevant documents found in the top-k results.
/// Returns `0.0` when `relevant` is empty.
///
/// # Examples
/// ```
/// use std::collections::HashSet;
/// use beagle_hypergraph::rag::eval_gate::recall_at_k;
///
/// let ranked = vec![1u64, 2, 3, 4, 5];
/// let relevant: HashSet<u64> = [1, 2, 10].into_iter().collect();
/// let score = recall_at_k(&ranked, &relevant, 5);
/// assert!((score - 2.0/3.0).abs() < 1e-9);
/// ```
pub fn recall_at_k(ranked: &[u64], relevant: &HashSet<u64>, k: usize) -> f64 {
    if relevant.is_empty() || k == 0 {
        return 0.0;
    }

    let hits = ranked
        .iter()
        .take(k)
        .filter(|id| relevant.contains(*id))
        .count();

    hits as f64 / relevant.len() as f64
}

// ---------------------------------------------------------------------------
// Internal DCG helpers
// ---------------------------------------------------------------------------

/// DCG with binary relevance: Σ (2^rel_i − 1) / log2(i+1+1).
/// Binary rel_i ∈ {0, 1} → gain ∈ {0, 1}.
fn compute_dcg(ranked: &[u64], relevant: &HashSet<u64>, k: usize) -> f64 {
    ranked
        .iter()
        .take(k)
        .enumerate()
        .filter_map(|(i, id)| {
            if relevant.contains(id) {
                // rank = i + 1, discount = log2(rank + 1) = log2(i + 2)
                let discount = ((i + 2) as f64).log2();
                Some(1.0_f64 / discount) // (2^1 - 1) / log2(rank+1) = 1/log2(rank+1)
            } else {
                None
            }
        })
        .sum()
}

/// IDCG: DCG of the ideal ranking where all `num_relevant` docs appear first.
fn compute_idcg(num_relevant: usize, k: usize) -> f64 {
    let top = num_relevant.min(k);
    (0..top)
        .map(|i| {
            let discount = ((i + 2) as f64).log2(); // log2(rank+1) where rank = i+1
            1.0_f64 / discount
        })
        .sum()
}

// ---------------------------------------------------------------------------
// Golden query fixture
// ---------------------------------------------------------------------------

/// A single frozen evaluation query.
pub struct GoldenQuery {
    /// Short label for diagnostic output.
    pub label: &'static str,
    /// Ranked result list (simulates what a retriever would return).
    /// Doc IDs are arbitrary u64 — chosen to be deterministic.
    pub ranked: &'static [u64],
    /// Ground-truth relevant doc IDs.
    pub relevant: &'static [u64],
}

/// Five frozen golden queries used by the regression gate.
///
/// Each query simulates a realistic retrieval scenario:
///   Q1: Perfect recall — all relevant docs in top positions.
///   Q2: Partial recall — half the relevant docs in top-k.
///   Q3: Worst case — no relevant docs in ranked list.
///   Q4: Single relevant at position 1 (perfect nDCG).
///   Q5: Mixed — relevant docs scattered across ranks.
///
/// The expected aggregate nDCG@10 and Recall@10 are computed analytically
/// and stored as `NDCG10_BASELINE` / `RECALL10_BASELINE`.
pub static GOLDEN_QUERIES: &[GoldenQuery] = &[
    GoldenQuery {
        label: "Q1-perfect-recall",
        // 3 relevant docs at positions 1,2,3; then irrelevant filler
        ranked: &[101, 102, 103, 201, 202, 203, 204, 205, 206, 207],
        relevant: &[101, 102, 103],
    },
    GoldenQuery {
        label: "Q2-partial-recall",
        // 2 of 4 relevant in top-10 (at positions 1,5)
        ranked: &[201, 301, 302, 303, 202, 304, 305, 306, 307, 308],
        relevant: &[201, 202, 203, 204],
    },
    GoldenQuery {
        label: "Q3-no-relevant-in-top10",
        // none of the relevant docs appear in the ranked list
        ranked: &[401, 402, 403, 404, 405, 406, 407, 408, 409, 410],
        relevant: &[501, 502, 503],
    },
    GoldenQuery {
        label: "Q4-single-relevant-at-rank1",
        // 1 relevant doc at position 1
        ranked: &[601, 602, 603, 604, 605, 606, 607, 608, 609, 610],
        relevant: &[601],
    },
    GoldenQuery {
        label: "Q5-scattered-relevant",
        // relevant at ranks 2, 5, 8 out of 10 total relevant
        ranked: &[701, 702, 703, 704, 705, 706, 707, 708, 709, 710],
        relevant: &[702, 705, 708, 801, 802],
    },
];

// ---------------------------------------------------------------------------
// Baseline thresholds (regression gate constants)
// ---------------------------------------------------------------------------

/// Minimum acceptable average nDCG@10 over the golden query set.
///
/// Analytically derived from GOLDEN_QUERIES:
/// Q1: nDCG@10 = 1.0  (perfect)
/// Q2: nDCG@10 ≈ 0.624 (docs at ranks 1,5 vs ideal ranks 1,2)
/// Q3: nDCG@10 = 0.0  (no hits)
/// Q4: nDCG@10 = 1.0  (sole relevant doc at rank 1)
/// Q5: nDCG@10 ≈ 0.408 (docs at ranks 2,5,8 of 5 total relevant)
/// Mean ≈ 0.606 → threshold set at 0.57 (5% slack below mean).
pub const NDCG10_BASELINE: f64 = 0.57;

/// Minimum acceptable average Recall@10 over the golden query set.
///
/// Q1: Recall@10 = 1.0   (3/3)
/// Q2: Recall@10 = 0.5   (2/4)
/// Q3: Recall@10 = 0.0   (0/3)
/// Q4: Recall@10 = 1.0   (1/1)
/// Q5: Recall@10 = 0.6   (3/5)
/// Mean = 0.62 → threshold set at 0.57 (5% slack below mean).
pub const RECALL10_BASELINE: f64 = 0.57;

// ---------------------------------------------------------------------------
// Public harness function (callable from non-test code if needed)
// ---------------------------------------------------------------------------

/// Evaluate the frozen golden set and return (mean_ndcg10, mean_recall10).
///
/// Returns `(0.0, 0.0)` when `GOLDEN_QUERIES` is empty.
pub fn evaluate_golden_set() -> (f64, f64) {
    if GOLDEN_QUERIES.is_empty() {
        return (0.0, 0.0);
    }

    let mut sum_ndcg = 0.0_f64;
    let mut sum_recall = 0.0_f64;

    for q in GOLDEN_QUERIES {
        let relevant: HashSet<u64> = q.relevant.iter().copied().collect();
        sum_ndcg += ndcg_at_k(q.ranked, &relevant, 10);
        sum_recall += recall_at_k(q.ranked, &relevant, 10);
    }

    let n = GOLDEN_QUERIES.len() as f64;
    (sum_ndcg / n, sum_recall / n)
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

#[cfg(test)]
mod tests {
    use super::*;

    // -----------------------------------------------------------------------
    // Unit tests — known inputs → known outputs
    // -----------------------------------------------------------------------

    #[test]
    fn ndcg_perfect_ranking_is_one() {
        // When all relevant docs are ranked first, nDCG = 1.0
        let relevant: HashSet<u64> = [1, 2, 3].into_iter().collect();
        let ranked = vec![1u64, 2, 3, 99, 98, 97, 96, 95, 94, 93];
        let score = ndcg_at_k(&ranked, &relevant, 10);
        assert!(
            (score - 1.0).abs() < 1e-9,
            "perfect ranking should yield nDCG=1.0, got {score}"
        );
    }

    #[test]
    fn ndcg_reversed_ranking_less_than_one() {
        // Relevant doc at last position → DCG < IDCG
        let relevant: HashSet<u64> = [10u64].into_iter().collect();
        let ranked = vec![1u64, 2, 3, 4, 5, 6, 7, 8, 9, 10];
        let score = ndcg_at_k(&ranked, &relevant, 10);
        // IDCG@10 = 1/log2(2) = 1.0; DCG@10 = 1/log2(11) ≈ 0.289
        let expected = 1.0 / 11_f64.log2();
        assert!(
            (score - expected).abs() < 1e-9,
            "rank-10 doc: expected {expected:.6}, got {score:.6}"
        );
        assert!(score < 1.0, "reversed ranking must be < 1.0");
    }

    #[test]
    fn ndcg_no_relevant_docs_is_zero() {
        let relevant: HashSet<u64> = HashSet::new();
        let ranked = vec![1u64, 2, 3];
        assert_eq!(ndcg_at_k(&ranked, &relevant, 10), 0.0);
    }

    #[test]
    fn ndcg_no_hits_in_top_k_is_zero() {
        let relevant: HashSet<u64> = [100, 200].into_iter().collect();
        let ranked = vec![1u64, 2, 3, 4, 5];
        assert_eq!(ndcg_at_k(&ranked, &relevant, 5), 0.0);
    }

    #[test]
    fn ndcg_k_zero_returns_zero() {
        let relevant: HashSet<u64> = [1].into_iter().collect();
        let ranked = vec![1u64, 2, 3];
        assert_eq!(ndcg_at_k(&ranked, &relevant, 0), 0.0);
    }

    #[test]
    fn ndcg_single_relevant_at_rank1() {
        let relevant: HashSet<u64> = [1].into_iter().collect();
        let ranked = vec![1u64, 2, 3, 4, 5, 6, 7, 8, 9, 10];
        let score = ndcg_at_k(&ranked, &relevant, 10);
        // IDCG@10 with 1 relevant = 1/log2(2) = 1.0; DCG = same → nDCG = 1.0
        assert!((score - 1.0).abs() < 1e-9, "single rel at rank 1 → nDCG=1");
    }

    #[test]
    fn recall_perfect_is_one() {
        let relevant: HashSet<u64> = [1, 2, 3].into_iter().collect();
        let ranked = vec![1u64, 2, 3, 4, 5];
        assert_eq!(recall_at_k(&ranked, &relevant, 5), 1.0);
    }

    #[test]
    fn recall_partial() {
        let relevant: HashSet<u64> = [1, 2, 10].into_iter().collect(); // 10 not in ranked
        let ranked = vec![1u64, 2, 3, 4, 5];
        let score = recall_at_k(&ranked, &relevant, 5);
        assert!((score - 2.0 / 3.0).abs() < 1e-9, "2/3 relevant found");
    }

    #[test]
    fn recall_no_relevant_docs_is_zero() {
        let relevant: HashSet<u64> = HashSet::new();
        let ranked = vec![1u64, 2, 3];
        assert_eq!(recall_at_k(&ranked, &relevant, 10), 0.0);
    }

    #[test]
    fn recall_empty_ranked_is_zero() {
        let relevant: HashSet<u64> = [1, 2].into_iter().collect();
        let ranked: Vec<u64> = vec![];
        assert_eq!(recall_at_k(&ranked, &relevant, 10), 0.0);
    }

    #[test]
    fn recall_k_zero_returns_zero() {
        let relevant: HashSet<u64> = [1].into_iter().collect();
        let ranked = vec![1u64, 2, 3];
        assert_eq!(recall_at_k(&ranked, &relevant, 0), 0.0);
    }

    #[test]
    fn recall_no_overlap_is_zero() {
        let relevant: HashSet<u64> = [100, 200].into_iter().collect();
        let ranked = vec![1u64, 2, 3, 4, 5];
        assert_eq!(recall_at_k(&ranked, &relevant, 5), 0.0);
    }

    // -----------------------------------------------------------------------
    // Golden set analytical sanity checks
    // -----------------------------------------------------------------------

    #[test]
    fn golden_q1_perfect_ndcg() {
        let q = &GOLDEN_QUERIES[0]; // Q1-perfect-recall
        let relevant: HashSet<u64> = q.relevant.iter().copied().collect();
        let score = ndcg_at_k(q.ranked, &relevant, 10);
        assert!(
            (score - 1.0).abs() < 1e-9,
            "Q1 should be perfect nDCG=1.0, got {score}"
        );
    }

    #[test]
    fn golden_q3_zero_ndcg_and_recall() {
        let q = &GOLDEN_QUERIES[2]; // Q3-no-relevant-in-top10
        let relevant: HashSet<u64> = q.relevant.iter().copied().collect();
        assert_eq!(ndcg_at_k(q.ranked, &relevant, 10), 0.0);
        assert_eq!(recall_at_k(q.ranked, &relevant, 10), 0.0);
    }

    #[test]
    fn golden_q4_single_relevant_at_rank1_ndcg_is_one() {
        let q = &GOLDEN_QUERIES[3]; // Q4-single-relevant-at-rank1
        let relevant: HashSet<u64> = q.relevant.iter().copied().collect();
        let score = ndcg_at_k(q.ranked, &relevant, 10);
        assert!(
            (score - 1.0).abs() < 1e-9,
            "Q4 sole relevant at rank 1 → nDCG=1.0, got {score}"
        );
    }

    // -----------------------------------------------------------------------
    // Regression gate — THIS IS THE CI GATE
    //
    // Computes mean nDCG@10 and Recall@10 over the frozen golden set.
    // Fails if either metric drops below the stored baseline threshold.
    // -----------------------------------------------------------------------

    #[test]
    fn eval_gate_ndcg10_recall10() {
        let (mean_ndcg, mean_recall) = evaluate_golden_set();

        println!("=== Eval Gate Results ===");
        println!("  mean nDCG@10 : {mean_ndcg:.6}  (threshold >= {NDCG10_BASELINE})");
        println!("  mean Recall@10: {mean_recall:.6}  (threshold >= {RECALL10_BASELINE})");

        // Per-query breakdown for diagnostic visibility
        for q in GOLDEN_QUERIES {
            let relevant: HashSet<u64> = q.relevant.iter().copied().collect();
            let ndcg = ndcg_at_k(q.ranked, &relevant, 10);
            let rec = recall_at_k(q.ranked, &relevant, 10);
            println!("  {} → nDCG@10={ndcg:.4}  Recall@10={rec:.4}", q.label);
        }

        assert!(
            mean_ndcg >= NDCG10_BASELINE,
            "REGRESSION: mean nDCG@10 = {mean_ndcg:.6} fell below baseline {NDCG10_BASELINE:.6}"
        );
        assert!(
            mean_recall >= RECALL10_BASELINE,
            "REGRESSION: mean Recall@10 = {mean_recall:.6} fell below baseline {RECALL10_BASELINE:.6}"
        );
    }
}
