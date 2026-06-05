//! Hybrid retrieval fusion (#8).
//!
//! The memory retrieval spine advertised hybrid (dense + sparse/lexical) via DTO fields but executed
//! a single dense Qdrant search. This module supplies the missing primitive: a real **lexical score**
//! over candidate text plus **Reciprocal Rank Fusion** of the dense and lexical orderings. It needs no
//! sparse vectors in the index — the retrieval over-fetches dense candidates and re-fuses them
//! client-side, so it works on any existing dense collection and degrades to dense-only gracefully.

use std::collections::{HashMap, HashSet};

/// Tokenize to lowercase alphanumeric terms of length >= 2.
fn tokenize(text: &str) -> Vec<String> {
    text.split(|c: char| !c.is_alphanumeric())
        .filter(|t| t.len() >= 2)
        .map(|t| t.to_lowercase())
        .collect()
}

/// Lexical relevance of `text` to `query`: total query-term frequency in the text, length-normalized
/// (a lightweight BM25-style signal). 0.0 when there is no lexical overlap. Used purely to produce a
/// ranking that RRF then fuses with the dense ranking — absolute scale does not matter.
pub fn lexical_score(query: &str, text: &str) -> f32 {
    let q_terms: HashSet<String> = tokenize(query).into_iter().collect();
    if q_terms.is_empty() {
        return 0.0;
    }
    let t_terms = tokenize(text);
    if t_terms.is_empty() {
        return 0.0;
    }
    let mut tf: HashMap<&str, u32> = HashMap::new();
    for term in &t_terms {
        *tf.entry(term.as_str()).or_insert(0) += 1;
    }
    let mut matches = 0u32;
    for q in &q_terms {
        matches += tf.get(q.as_str()).copied().unwrap_or(0);
    }
    matches as f32 / (t_terms.len() as f32).sqrt()
}

/// Reciprocal Rank Fusion over several ranked lists of item indices.
///
/// `score(i) = Σ_lists 1/(k + rank_in_list(i))` (rank is 0-based here, so the standard 1/(k+rank+1)).
/// Returns the item indices ordered by fused score, best first. `k` is the standard RRF constant
/// (60.0 is typical). Items missing from a list simply contribute nothing from that list.
pub fn rrf_fuse(rankings: &[Vec<usize>], k: f32) -> Vec<usize> {
    let mut scores: HashMap<usize, f32> = HashMap::new();
    for ranking in rankings {
        for (rank, &idx) in ranking.iter().enumerate() {
            *scores.entry(idx).or_insert(0.0) += 1.0 / (k + rank as f32 + 1.0);
        }
    }
    let mut fused: Vec<(usize, f32)> = scores.into_iter().collect();
    // Sort by score desc; tie-break by index asc for determinism.
    fused.sort_by(|a, b| {
        b.1.partial_cmp(&a.1)
            .unwrap_or(std::cmp::Ordering::Equal)
            .then(a.0.cmp(&b.0))
    });
    fused.into_iter().map(|(idx, _)| idx).collect()
}

/// Fuse dense-ordered candidates with a lexical re-ranking of the same candidates.
///
/// `dense_texts` is the candidate texts in DENSE rank order (index 0 = top dense hit). Returns the
/// candidate indices in fused (hybrid) order. When the query has no lexical signal against any
/// candidate, the dense order is preserved (graceful dense-only behavior).
pub fn fuse_dense_lexical(query: &str, dense_texts: &[&str], k: f32) -> Vec<usize> {
    let n = dense_texts.len();
    if n <= 1 {
        return (0..n).collect();
    }
    let dense_order: Vec<usize> = (0..n).collect();
    let mut lex: Vec<(usize, f32)> = dense_texts
        .iter()
        .enumerate()
        .map(|(i, t)| (i, lexical_score(query, t)))
        .collect();
    if lex.iter().all(|(_, s)| *s == 0.0) {
        return dense_order; // no lexical signal -> keep dense order
    }
    lex.sort_by(|a, b| {
        b.1.partial_cmp(&a.1)
            .unwrap_or(std::cmp::Ordering::Equal)
            .then(a.0.cmp(&b.0))
    });
    let lexical_order: Vec<usize> = lex.into_iter().map(|(i, _)| i).collect();
    rrf_fuse(&[dense_order, lexical_order], k)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn lexical_scores_overlap() {
        assert!(lexical_score("gpu memory", "gpu gpu memory bandwidth") > 0.0);
        assert_eq!(lexical_score("gpu memory", "totally unrelated content"), 0.0);
        assert_eq!(lexical_score("", "anything"), 0.0);
        // more query-term occurrences -> higher score
        assert!(
            lexical_score("nccl", "nccl nccl nccl gpu")
                > lexical_score("nccl", "nccl gpu fabric mesh")
        );
    }

    #[test]
    fn rrf_basic_and_consensus() {
        // item 2 is top in BOTH lists -> must rank first after fusion.
        let a = vec![2usize, 0, 1];
        let b = vec![2usize, 1, 0];
        let fused = rrf_fuse(&[a, b], 60.0);
        assert_eq!(fused.len(), 3);
        assert_eq!(fused[0], 2, "item ranked high in both lists should win");
    }

    #[test]
    fn fuse_promotes_lexical_match() {
        // Dense puts the keyword doc last; lexical should pull it up via fusion.
        let dense = ["about cats and dogs", "weather today", "NCCL GPUDirect RDMA over PCIe"];
        let fused = fuse_dense_lexical("NCCL RDMA PCIe", &dense, 60.0);
        // the lexical-matching doc (index 2) should no longer be last.
        assert_ne!(*fused.last().unwrap(), 2);
    }

    #[test]
    fn fuse_no_signal_preserves_dense() {
        let dense = ["alpha", "beta", "gamma"];
        let fused = fuse_dense_lexical("zzz qqq", &dense, 60.0);
        assert_eq!(fused, vec![0, 1, 2]);
    }

    #[test]
    fn fuse_trivial_sizes() {
        assert_eq!(fuse_dense_lexical("q", &[], 60.0), Vec::<usize>::new());
        assert_eq!(fuse_dense_lexical("q", &["only"], 60.0), vec![0]);
    }
}
