use anyhow::{Context, Result};
use beagle_rag_update::embed::EmbeddingClient;
use beagle_rag_update::qdrant::QdrantClient;
use clap::Parser;
use serde::Deserialize;
use std::collections::HashSet;
use std::path::PathBuf;
use tracing::{info, warn};

#[derive(Debug, Parser)]
#[command(name = "darwin-eval")]
#[command(about = "Evaluate retrieval quality against golden queries (Qdrant)")]
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
    /// Expected doc_id values to appear in the top-k results.
    expect_doc_ids: Vec<String>,
    /// Optional per-test collection override.
    #[serde(default)]
    collections: Vec<String>,
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

        let mut best_rank: Option<usize> = None;
        let expected: HashSet<String> = test.expect_doc_ids.into_iter().collect();

        for collection in collections {
            let hits = qdrant
                .search_points(&collection, &query_vec, default_k, true)
                .await
                .with_context(|| format!("qdrant search failed for collection={collection}"))?;

            for (idx, hit) in hits.iter().enumerate() {
                let payload = hit.get("payload");
                let doc_id = payload
                    .and_then(|p| p.get("doc_id"))
                    .and_then(|v| v.as_str())
                    .map(|s| s.to_string())
                    .or_else(|| {
                        // Repo vectors don't have doc_id; fall back to title.
                        payload
                            .and_then(|p| p.get("title"))
                            .and_then(|v| v.as_str())
                            .map(|s| s.to_string())
                    });

                let Some(doc_id) = doc_id else { continue };
                if expected.contains(&doc_id) {
                    let rank = idx + 1;
                    best_rank = match best_rank {
                        Some(prev) => Some(prev.min(rank)),
                        None => Some(rank),
                    };
                }
            }
        }

        if let Some(rank) = best_rank {
            passed += 1;
            rr_sum += 1.0 / rank as f64;
            info!(name = %name, rank, k = default_k, "PASS");
        } else {
            warn!(name = %name, k = default_k, "FAIL");
        }
    }

    let mrr = if total == 0 { 0.0 } else { rr_sum / total as f64 };
    info!(total, passed, failed = total - passed, mrr, "eval summary");

    if passed != total {
        anyhow::bail!("eval failed: {}/{} tests passed", passed, total);
    }
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

