use crate::embed::EmbeddingClient;
use crate::qdrant::QdrantClient;
use anyhow::{Context, Result};
use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};
use std::collections::HashSet;
use std::path::{Path, PathBuf};
use tracing::{info, warn};

#[derive(Debug, Clone)]
pub struct EvalGateConfig {
    pub qdrant_url: String,
    pub embedding_url: String,
    pub embedding_model: String,
    /// Path to eval file (YAML/TOML/JSON)
    pub eval_file: String,
    /// Default top-k per query (can be overridden in the eval file)
    pub k: usize,
    /// Append eval runs to this JSONL file for trend tracking.
    pub history_file: String,
    /// Fail if MRR is below this value.
    pub min_mrr: Option<f64>,
    /// Fail if MRR dropped by more than this value vs the previous run in the history file.
    pub max_mrr_drop: Option<f64>,
    /// Fail if recall@k is below this value.
    pub min_recall: Option<f64>,
    /// Fail if recall@k dropped by more than this value vs the previous run in the history file.
    pub max_recall_drop: Option<f64>,
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

#[derive(Debug, Serialize, Deserialize)]
pub struct EvalRunRecord {
    pub at: DateTime<Utc>,
    pub k: usize,
    pub collections: Vec<String>,
    pub total: usize,
    pub passed: usize,
    pub failed: usize,
    pub mrr: f64,
    #[serde(default)]
    pub expected_total: usize,
    #[serde(default)]
    pub found_total: usize,
    #[serde(default)]
    pub recall_at_k: Option<f64>,
    #[serde(default)]
    pub recall_at_k_macro: Option<f64>,
    pub tests: Vec<EvalTestRecord>,
}

#[derive(Debug, Serialize, Deserialize)]
pub struct EvalTestRecord {
    pub name: String,
    pub query: String,
    pub pass: bool,
    pub rank: Option<usize>,
    pub collection: Option<String>,
    #[serde(default)]
    pub expected: usize,
    #[serde(default)]
    pub found: usize,
    #[serde(default)]
    pub missing_doc_ids: Vec<String>,
    #[serde(default)]
    pub found_doc_ids: Vec<String>,
}

fn extract_hit_doc_id(payload: &serde_json::Value) -> Option<String> {
    if let Some(doc_id) = payload.get("doc_id").and_then(|v| v.as_str()) {
        let doc_id = doc_id.trim();
        if !doc_id.is_empty() {
            return Some(doc_id.to_string());
        }
    }

    // Repo vectors: derive stable doc_id from repo/file.
    let repo = payload.get("repo").and_then(|v| v.as_str());
    let file = payload.get("file").and_then(|v| v.as_str());
    if let (Some(repo), Some(file)) = (repo, file) {
        let repo = repo.trim();
        let file = file.trim();
        if !repo.is_empty() && !file.is_empty() {
            return Some(format!("repo:{repo}/{file}"));
        }
    }

    // Last resort: title.
    payload
        .get("title")
        .and_then(|v| v.as_str())
        .map(|s| s.trim().to_string())
        .filter(|s| !s.is_empty())
}

pub async fn run_eval(cfg: EvalGateConfig) -> Result<EvalRunRecord> {
    let eval_path = expand_tilde(&cfg.eval_file);
    let history_path = expand_tilde(&cfg.history_file);

    let file_cfg = config::Config::builder()
        .add_source(config::File::from(eval_path.clone()))
        .build()
        .with_context(|| format!("failed to load eval file {}", eval_path.display()))?;
    let eval: EvalFile = file_cfg
        .try_deserialize()
        .context("failed to deserialize eval file")?;

    let default_k = eval.k.unwrap_or(cfg.k).clamp(1, 200);
    if eval.tests.is_empty() {
        anyhow::bail!("eval file has no tests");
    }

    let embed = EmbeddingClient::new(&cfg.embedding_url, &cfg.embedding_model);
    let qdrant = QdrantClient::new(&cfg.qdrant_url);

    let prev_run = load_last_history_record(&history_path).ok().flatten();

    let mut total = 0usize;
    let mut passed = 0usize;
    let mut rr_sum = 0.0f64;
    let mut expected_total = 0usize;
    let mut found_total = 0usize;
    let mut recall_macro_sum = 0.0f64;
    let mut used_collections: HashSet<String> = HashSet::new();
    let mut test_records: Vec<EvalTestRecord> = Vec::new();

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
        for c in &collections {
            used_collections.insert(c.clone());
        }

        let vectors = embed.embed_batch(&[test.query.clone()]).await?;
        let query_vec = vectors
            .first()
            .cloned()
            .ok_or_else(|| anyhow::anyhow!("embedding returned empty vector list"))?;

        let mut best_rank: Option<usize> = None;
        let mut best_collection: Option<String> = None;
        let expected: HashSet<String> = test.expect_doc_ids.into_iter().collect();
        let mut found: HashSet<String> = HashSet::new();
        expected_total += expected.len();

        for collection in &collections {
            let hits = qdrant
                .search_points(collection, &query_vec, default_k, true)
                .await
                .with_context(|| format!("qdrant search failed for collection={collection}"))?;

            for (idx, hit) in hits.iter().enumerate() {
                let payload = hit.get("payload");
                let Some(doc_id) = payload.and_then(extract_hit_doc_id) else {
                    continue;
                };
                if expected.contains(&doc_id) {
                    found.insert(doc_id);
                    let rank = idx + 1;
                    best_rank = match best_rank {
                        Some(prev) if rank < prev => {
                            best_collection = Some(collection.clone());
                            Some(rank)
                        }
                        Some(prev) => Some(prev),
                        None => {
                            best_collection = Some(collection.clone());
                            Some(rank)
                        }
                    };
                }
            }
        }

        found_total += found.len();
        let expected_len = expected.len();
        let recall = if expected_len == 0 {
            0.0
        } else {
            found.len() as f64 / expected_len as f64
        };
        recall_macro_sum += recall;

        let mut missing_doc_ids: Vec<String> = expected.difference(&found).cloned().collect();
        missing_doc_ids.sort();
        let mut found_doc_ids: Vec<String> = found.into_iter().collect();
        found_doc_ids.sort();

        let pass = best_rank.is_some();
        if let Some(rank) = best_rank {
            passed += 1;
            rr_sum += 1.0 / rank as f64;
            info!(
                name = %name,
                rank,
                k = default_k,
                expected = expected_len,
                found = found_doc_ids.len(),
                recall = format!("{:.3}", recall),
                "PASS"
            );
        } else {
            warn!(
                name = %name,
                k = default_k,
                expected = expected_len,
                found = found_doc_ids.len(),
                recall = format!("{:.3}", recall),
                missing = ?missing_doc_ids,
                "FAIL"
            );
        }

        test_records.push(EvalTestRecord {
            name,
            query: test.query,
            pass,
            rank: best_rank,
            collection: best_collection,
            expected: expected_len,
            found: found_doc_ids.len(),
            missing_doc_ids,
            found_doc_ids,
        });
    }

    let mrr = if total == 0 { 0.0 } else { rr_sum / total as f64 };
    let recall_at_k = if expected_total == 0 {
        0.0
    } else {
        found_total as f64 / expected_total as f64
    };
    let recall_at_k_macro = if total == 0 {
        0.0
    } else {
        recall_macro_sum / total as f64
    };
    info!(
        total,
        passed,
        failed = total - passed,
        mrr,
        expected_total,
        found_total,
        recall_at_k = format!("{:.3}", recall_at_k),
        recall_at_k_macro = format!("{:.3}", recall_at_k_macro),
        "eval summary"
    );

    let mut collections: Vec<String> = used_collections.into_iter().collect();
    collections.sort();
    let record = EvalRunRecord {
        at: Utc::now(),
        k: default_k,
        collections,
        total,
        passed,
        failed: total - passed,
        mrr,
        expected_total,
        found_total,
        recall_at_k: Some(recall_at_k),
        recall_at_k_macro: Some(recall_at_k_macro),
        tests: test_records,
    };

    if let Err(e) = append_history_record(&history_path, &record) {
        warn!(path = %history_path.display(), "failed to write eval history: {e:#}");
    }

    apply_gates(&cfg, prev_run.as_ref(), &record)?;

    if record.passed != record.total {
        anyhow::bail!(
            "eval failed: {}/{} tests passed",
            record.passed,
            record.total
        );
    }

    Ok(record)
}

fn apply_gates(cfg: &EvalGateConfig, prev: Option<&EvalRunRecord>, record: &EvalRunRecord) -> Result<()> {
    let mrr = record.mrr;
    let recall_at_k = record.recall_at_k.unwrap_or(0.0);

    if let Some(min_mrr) = cfg.min_mrr {
        if mrr < min_mrr {
            anyhow::bail!("eval drift gate failed: mrr={mrr:.4} < min_mrr={min_mrr:.4}");
        }
    }

    if let Some(max_drop) = cfg.max_mrr_drop {
        if let Some(prev) = prev {
            let drop = prev.mrr - mrr;
            if drop > max_drop {
                anyhow::bail!(
                    "eval drift gate failed: mrr dropped {:.4} (prev {:.4} -> current {:.4}) > max_mrr_drop {:.4}",
                    drop,
                    prev.mrr,
                    mrr,
                    max_drop
                );
            }
        }
    }

    if let Some(min_recall) = cfg.min_recall {
        if recall_at_k < min_recall {
            anyhow::bail!(
                "eval drift gate failed: recall@k={recall_at_k:.4} < min_recall={min_recall:.4}"
            );
        }
    }

    if let Some(max_drop) = cfg.max_recall_drop {
        if let Some(prev) = prev.and_then(|p| p.recall_at_k) {
            let drop = prev - recall_at_k;
            if drop > max_drop {
                anyhow::bail!(
                    "eval drift gate failed: recall@k dropped {:.4} (prev {:.4} -> current {:.4}) > max_recall_drop {:.4}",
                    drop,
                    prev,
                    recall_at_k,
                    max_drop
                );
            }
        }
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

fn load_last_history_record(path: &Path) -> Result<Option<EvalRunRecord>> {
    if !path.exists() {
        return Ok(None);
    }
    let content = std::fs::read_to_string(path).context("failed to read eval history file")?;
    let line = content
        .lines()
        .rev()
        .find(|l| !l.trim().is_empty())
        .map(|l| l.trim());
    let Some(line) = line else {
        return Ok(None);
    };
    let record: EvalRunRecord =
        serde_json::from_str(line).context("failed to parse eval history JSONL line")?;
    Ok(Some(record))
}

fn append_history_record(path: &Path, record: &EvalRunRecord) -> Result<()> {
    if let Some(parent) = path.parent() {
        std::fs::create_dir_all(parent).context("failed to create eval history dir")?;
    }
    let mut file = std::fs::OpenOptions::new()
        .create(true)
        .append(true)
        .open(path)
        .context("failed to open eval history file")?;
    let json = serde_json::to_string(record).context("failed to serialize eval history record")?;
    use std::io::Write as _;
    writeln!(file, "{json}").context("failed to write eval history record")?;
    Ok(())
}

