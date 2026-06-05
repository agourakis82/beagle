//! Retrieval eval + regression gate (Qdrant).
//!
//! Runs the golden query set against live Qdrant collections, merges hits across collections by
//! score into one ranked list, and computes nDCG@k / Recall@k / MRR (binary relevance). It then
//! GATES on a committed baseline: if any headline metric drops more than `--tolerance` below the
//! baseline, it exits non-zero (CI regression gate). `--update-baseline` records the current run as
//! the new baseline. Mirrors the cockpit's /eval/run baseline+alert pattern, in the Rust stack.
//!
//! Activation (operational): fill `scripts/darwin-eval.yaml` with REAL doc_ids from the corpus and,
//! once the index is populated, seed the baseline with `--update-baseline` against live Qdrant.
//!
//! Note: the canonical library metric impl is `beagle_hypergraph::rag::RetrievalEvaluator`
//! (Uuid-based). This bin computes the same metrics inline over String doc_ids to stay a lean,
//! dependency-light standalone gate.

use anyhow::{Context, Result};
use beagle_rag_update::embed::EmbeddingClient;
use beagle_rag_update::qdrant::QdrantClient;
use clap::Parser;
use serde::{Deserialize, Serialize};
use std::collections::{HashMap, HashSet};
use std::path::PathBuf;
use tracing::{info, warn};

#[derive(Debug, Parser)]
#[command(name = "darwin-eval")]
#[command(about = "Evaluate retrieval quality vs a baseline (Qdrant) — CI regression gate")]
struct Args {
    #[arg(long, env = "QDRANT_URL", default_value = "http://localhost:6333")]
    qdrant_url: String,

    #[arg(long, env = "EMBEDDING_URL", default_value = "http://localhost:8001/v1")]
    embedding_url: String,

    #[arg(long, env = "EMBEDDING_MODEL", default_value = "NV-Embed-v2")]
    embedding_model: String,

    /// Path to eval file (YAML/TOML/JSON)
    #[arg(long, env = "DARWIN_EVAL_FILE", default_value = "scripts/darwin-eval.yaml")]
    eval_file: String,

    /// Path to the committed baseline metrics (JSON).
    #[arg(
        long,
        env = "DARWIN_EVAL_BASELINE",
        default_value = "scripts/darwin-eval-baseline.json"
    )]
    baseline: String,

    /// Record the current run as the new baseline instead of gating.
    #[arg(long)]
    update_baseline: bool,

    /// Max allowed absolute drop in a headline metric vs baseline before failing.
    #[arg(long, default_value_t = 0.02)]
    tolerance: f64,

    /// Default top-k per query (can be overridden in the eval file)
    #[arg(long, default_value_t = 10)]
    k: usize,
}

#[derive(Debug, Deserialize)]
struct EvalFile {
    #[serde(default)]
    collections: Vec<String>,
    #[serde(default)]
    k: Option<usize>,
    tests: Vec<EvalTest>,
}

#[derive(Debug, Deserialize)]
struct EvalTest {
    #[serde(default)]
    name: Option<String>,
    query: String,
    /// Expected doc_id values that SHOULD appear in the top-k results (the relevant set).
    expect_doc_ids: Vec<String>,
    #[serde(default)]
    collections: Vec<String>,
}

/// Headline retrieval metrics + the gate baseline shape.
#[derive(Debug, Clone, Serialize, Deserialize)]
struct EvalMetrics {
    k: usize,
    num_queries: usize,
    mrr: f64,
    recall_at_k: f64,
    ndcg_at_k: f64,
}

fn dcg_at(ranked: &[String], relevant: &HashSet<String>, k: usize) -> f64 {
    ranked
        .iter()
        .take(k)
        .enumerate()
        .map(|(i, doc)| {
            if relevant.contains(doc) {
                1.0 / ((i + 2) as f64).log2() // gain=1, discount = log2(rank+1), rank=i+1
            } else {
                0.0
            }
        })
        .sum()
}

fn idcg_at(num_relevant: usize, k: usize) -> f64 {
    (0..num_relevant.min(k))
        .map(|i| 1.0 / ((i + 2) as f64).log2())
        .sum()
}

#[tokio::main]
async fn main() -> Result<()> {
    tracing_subscriber::fmt()
        .with_env_filter(tracing_subscriber::EnvFilter::from_default_env())
        .init();

    let args = Args::parse();
    let eval_path = expand_tilde(&args.eval_file);

    let cfg = config::Config::builder()
        .add_source(config::File::from(eval_path.clone()))
        .build()
        .with_context(|| format!("failed to load eval file {}", eval_path.display()))?;
    let eval: EvalFile = cfg
        .try_deserialize()
        .context("failed to deserialize eval file")?;

    let default_k = eval.k.unwrap_or(args.k).clamp(1, 200);
    if eval.tests.is_empty() {
        anyhow::bail!("eval file has no tests");
    }

    let embed = EmbeddingClient::new(&args.embedding_url, &args.embedding_model);
    let qdrant = QdrantClient::new(&args.qdrant_url);

    let mut total = 0usize;
    let mut passed = 0usize;
    let mut rr_sum = 0.0f64;
    let mut recall_sum = 0.0f64;
    let mut ndcg_sum = 0.0f64;

    for test in eval.tests {
        total += 1;
        let name = test
            .name
            .clone()
            .unwrap_or_else(|| test.query.chars().take(48).collect());

        let collections = if !test.collections.is_empty() {
            test.collections.clone()
        } else if !eval.collections.is_empty() {
            eval.collections.clone()
        } else {
            vec![
                "darwin-papers".to_string(),
                "darwin-docs".to_string(),
                "darwin-books".to_string(),
                "darwin-repos".to_string(),
            ]
        };

        let vectors = embed.embed_batch(&[test.query.clone()]).await?;
        let query_vec = vectors
            .first()
            .cloned()
            .ok_or_else(|| anyhow::anyhow!("embedding returned empty vector list"))?;

        // Merge hits across collections into one ranked list (by score desc, dedup doc_id).
        let mut scored: HashMap<String, f64> = HashMap::new();
        for collection in &collections {
            let hits = qdrant
                .search_points(collection, &query_vec, default_k, true)
                .await
                .with_context(|| format!("qdrant search failed for collection={collection}"))?;
            for hit in &hits {
                let score = hit.get("score").and_then(|s| s.as_f64()).unwrap_or(0.0);
                let payload = hit.get("payload");
                let doc_id = payload
                    .and_then(|p| p.get("doc_id"))
                    .and_then(|v| v.as_str())
                    .map(|s| s.to_string())
                    .or_else(|| {
                        payload
                            .and_then(|p| p.get("title"))
                            .and_then(|v| v.as_str())
                            .map(|s| s.to_string())
                    });
                if let Some(doc_id) = doc_id {
                    let e = scored.entry(doc_id).or_insert(f64::MIN);
                    if score > *e {
                        *e = score;
                    }
                }
            }
        }
        let mut ranked: Vec<(String, f64)> = scored.into_iter().collect();
        ranked.sort_by(|a, b| b.1.partial_cmp(&a.1).unwrap_or(std::cmp::Ordering::Equal));
        let ranked_ids: Vec<String> = ranked.into_iter().map(|(d, _)| d).take(default_k).collect();

        let relevant: HashSet<String> = test.expect_doc_ids.into_iter().collect();

        // Per-query metrics (binary relevance).
        let rr = ranked_ids
            .iter()
            .position(|d| relevant.contains(d))
            .map(|i| 1.0 / (i + 1) as f64)
            .unwrap_or(0.0);
        let hit_count = ranked_ids.iter().filter(|d| relevant.contains(*d)).count();
        let recall = if relevant.is_empty() {
            0.0
        } else {
            hit_count as f64 / relevant.len() as f64
        };
        let idcg = idcg_at(relevant.len(), default_k);
        let ndcg = if idcg > 0.0 {
            dcg_at(&ranked_ids, &relevant, default_k) / idcg
        } else {
            0.0
        };

        rr_sum += rr;
        recall_sum += recall;
        ndcg_sum += ndcg;
        if rr > 0.0 {
            passed += 1;
            info!(name = %name, rr = %format!("{rr:.3}"), recall = %format!("{recall:.3}"), ndcg = %format!("{ndcg:.3}"), "PASS");
        } else {
            warn!(name = %name, k = default_k, "FAIL (no relevant doc in top-k)");
        }
    }

    let metrics = EvalMetrics {
        k: default_k,
        num_queries: total,
        mrr: rr_sum / total as f64,
        recall_at_k: recall_sum / total as f64,
        ndcg_at_k: ndcg_sum / total as f64,
    };
    info!(
        total,
        passed,
        failed = total - passed,
        mrr = %format!("{:.4}", metrics.mrr),
        recall_at_k = %format!("{:.4}", metrics.recall_at_k),
        ndcg_at_k = %format!("{:.4}", metrics.ndcg_at_k),
        k = metrics.k,
        "eval summary"
    );

    let baseline_path = expand_tilde(&args.baseline);

    if args.update_baseline {
        std::fs::write(&baseline_path, serde_json::to_string_pretty(&metrics)?)
            .with_context(|| format!("failed to write baseline {}", baseline_path.display()))?;
        info!(path = %baseline_path.display(), "baseline updated");
        return Ok(());
    }

    // Gate against the committed baseline.
    let baseline: Option<EvalMetrics> = std::fs::read_to_string(&baseline_path)
        .ok()
        .and_then(|s| serde_json::from_str(&s).ok());

    let Some(base) = baseline else {
        warn!(
            path = %baseline_path.display(),
            "no baseline found — skipping regression gate. Seed it with --update-baseline once the corpus + golden doc_ids are real."
        );
        return Ok(());
    };

    let mut regressions = Vec::new();
    for (label, cur, b) in [
        ("nDCG@k", metrics.ndcg_at_k, base.ndcg_at_k),
        ("Recall@k", metrics.recall_at_k, base.recall_at_k),
        ("MRR", metrics.mrr, base.mrr),
    ] {
        let drop = b - cur;
        if drop > args.tolerance {
            regressions.push(format!(
                "{label}: {cur:.4} < baseline {b:.4} (drop {drop:.4} > tol {:.4})",
                args.tolerance
            ));
        } else {
            info!(metric = label, current = %format!("{cur:.4}"), baseline = %format!("{b:.4}"), "OK");
        }
    }

    if !regressions.is_empty() {
        anyhow::bail!("RAG eval regression gate FAILED:\n  - {}", regressions.join("\n  - "));
    }
    info!("RAG eval regression gate PASSED");
    Ok(())
}

fn expand_tilde(path: &str) -> PathBuf {
    if let Some(rest) = path.strip_prefix("~/") {
        if let Some(home) = std::env::var_os("HOME") {
            return PathBuf::from(home).join(rest);
        }
    }
    PathBuf::from(path)
}
