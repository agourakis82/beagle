use anyhow::Result;
use beagle_rag_update::indexer::{run_incremental, IndexerConfig, RepoTarget};
use beagle_rag_update::ledger::IngestionLedger;
use clap::Parser;
use std::collections::HashSet;
use std::path::PathBuf;
use tracing_subscriber::EnvFilter;

#[derive(Debug, Parser)]
#[command(name = "darwin-incremental-indexer")]
#[command(about = "Continuous RAG incremental indexer (git-based)")]
struct Args {
    /// Directory that contains cloned repos (used with --repo-url)
    #[arg(long, env = "DARWIN_REPOS_DIR", default_value = "~/repos")]
    repos_dir: String,

    /// State file storing last indexed commit per repo
    #[arg(long, env = "DARWIN_INDEX_STATE_FILE", default_value = "~/.darwin_index_state.json")]
    state_file: String,

    #[arg(long, env = "QDRANT_URL", default_value = "http://localhost:6333")]
    qdrant_url: String,

    #[arg(long, env = "EMBEDDING_URL", default_value = "http://localhost:8001/v1")]
    embedding_url: String,

    #[arg(long, env = "EMBEDDING_MODEL", default_value = "NV-Embed-v2")]
    embedding_model: String,

    #[arg(long, env = "DARWIN_QDRANT_COLLECTION", default_value = "darwin-repos")]
    collection: String,

    #[arg(long, default_value_t = 1500)]
    chunk_size: usize,

    #[arg(long, default_value_t = 200)]
    chunk_overlap: usize,

    /// Comma-separated list of extensions (including the dot), e.g. ".rs,.md"
    #[arg(long, default_value = ".py,.rs,.md,.txt,.json,.yaml,.yml,.toml")]
    extensions: String,

    /// Comma-separated list of ignored directory names
    #[arg(long, default_value = ".git,node_modules,target,__pycache__,.venv,venv")]
    ignore_dirs: String,

    #[arg(long, default_value_t = 500_000)]
    max_file_size: u64,

    /// Re-index everything (ignores git diff state)
    #[arg(long)]
    force: bool,

    /// Run `git pull --ff-only` before indexing
    #[arg(long)]
    sync: bool,

    /// One or more local repo paths to index
    #[arg(long)]
    repo_path: Vec<String>,

    /// One or more git clone URLs to index (cloned into --repos-dir)
    #[arg(long)]
    repo_url: Vec<String>,

    /// Optional webhook URL to notify only when errors occur
    #[arg(long, env = "DARWIN_INDEX_ERROR_WEBHOOK_URL")]
    error_webhook_url: Option<String>,

    /// Optional webhook URL to notify on success
    #[arg(long, env = "DARWIN_INDEX_SUCCESS_WEBHOOK_URL")]
    success_webhook_url: Option<String>,

    /// Optional Postgres URL to enable the ingestion ledger
    #[arg(long, env = "DARWIN_LEDGER_DATABASE_URL")]
    ledger_db_url: Option<String>,
}

fn expand_tilde(s: &str) -> PathBuf {
    if let Some(rest) = s.strip_prefix("~/") {
        if let Some(home) = std::env::var_os("HOME") {
            return PathBuf::from(home).join(rest);
        }
    }
    PathBuf::from(s)
}

#[tokio::main]
async fn main() -> Result<()> {
    tracing_subscriber::fmt()
        .with_env_filter(EnvFilter::from_default_env())
        .init();

    let args = Args::parse();

    let repos_dir = expand_tilde(&args.repos_dir);
    let state_file = expand_tilde(&args.state_file);
    let ledger = init_ledger(args.ledger_db_url.as_deref()).await?;

    let extensions: HashSet<String> = args
        .extensions
        .split(',')
        .map(|s| s.trim().to_lowercase())
        .filter(|s| !s.is_empty())
        .collect();
    let ignore_dirs: HashSet<String> = args
        .ignore_dirs
        .split(',')
        .map(|s| s.trim().to_string())
        .filter(|s| !s.is_empty())
        .collect();

    let mut repos = Vec::new();
    for p in args.repo_path {
        let path = expand_tilde(&p);
        let name = path
            .file_name()
            .and_then(|s| s.to_str())
            .unwrap_or("repo")
            .to_string();
        repos.push(RepoTarget {
            name,
            path,
            url: None,
        });
    }
    for url in args.repo_url {
        let name = url
            .split('/')
            .next_back()
            .unwrap_or("repo")
            .trim_end_matches(".git")
            .to_string();
        let path = repos_dir.join(&name);
        repos.push(RepoTarget {
            name,
            path,
            url: Some(url),
        });
    }

    if repos.is_empty() {
        anyhow::bail!("provide at least one --repo-path or --repo-url");
    }

    let cfg = IndexerConfig {
        repos_dir,
        state_file,
        qdrant_url: args.qdrant_url,
        embedding_url: args.embedding_url,
        embedding_model: args.embedding_model,
        collection: args.collection,
        chunk_size: args.chunk_size,
        chunk_overlap: args.chunk_overlap,
        extensions,
        ignore_dirs,
        max_file_size: args.max_file_size,
        error_webhook_url: args.error_webhook_url,
        success_webhook_url: args.success_webhook_url,
        ledger,
    };

    let summary = run_incremental(&cfg, repos, args.force, args.sync).await?;
    println!(
        "repos={} files_added={} files_modified={} files_deleted={} files_skipped_unchanged={} chunks_upserted={}",
        summary.repos,
        summary.files_added,
        summary.files_modified,
        summary.files_deleted,
        summary.files_skipped_unchanged,
        summary.chunks_upserted
    );
    Ok(())
}

async fn init_ledger(db_url: Option<&str>) -> Result<Option<IngestionLedger>> {
    let Some(db_url) = db_url else {
        return Ok(None);
    };
    let ledger = IngestionLedger::connect(db_url).await?;
    ledger.ensure_schema().await?;
    Ok(Some(ledger))
}
