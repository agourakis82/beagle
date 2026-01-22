use anyhow::Result;
use beagle_rag_update::eval_harness::{run_eval, EvalGateConfig};
use clap::Parser;

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

    /// Append eval runs to this JSONL file for trend tracking.
    #[arg(long, env = "DARWIN_EVAL_HISTORY_FILE", default_value = "~/.darwin_eval_history.jsonl")]
    history_file: String,

    /// Fail if MRR is below this value.
    #[arg(long, env = "DARWIN_EVAL_MIN_MRR")]
    min_mrr: Option<f64>,

    /// Fail if MRR dropped by more than this value vs the previous run in the history file.
    #[arg(long, env = "DARWIN_EVAL_MAX_MRR_DROP")]
    max_mrr_drop: Option<f64>,

    /// Fail if recall@k is below this value.
    #[arg(long, env = "DARWIN_EVAL_MIN_RECALL")]
    min_recall: Option<f64>,

    /// Fail if recall@k dropped by more than this value vs the previous run in the history file.
    #[arg(long, env = "DARWIN_EVAL_MAX_RECALL_DROP")]
    max_recall_drop: Option<f64>,
}

#[tokio::main]
async fn main() -> Result<()> {
    tracing_subscriber::fmt()
        .with_env_filter(tracing_subscriber::EnvFilter::from_default_env())
        .init();

    let args = Args::parse();
    let _record = run_eval(EvalGateConfig {
        qdrant_url: args.qdrant_url,
        embedding_url: args.embedding_url,
        embedding_model: args.embedding_model,
        eval_file: args.eval_file,
        k: args.k,
        history_file: args.history_file,
        min_mrr: args.min_mrr,
        max_mrr_drop: args.max_mrr_drop,
        min_recall: args.min_recall,
        max_recall_drop: args.max_recall_drop,
    })
    .await?;

    Ok(())
}
