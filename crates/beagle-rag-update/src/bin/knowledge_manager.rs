use anyhow::Result;
use beagle_rag_update::ledger::IngestionLedger;
use beagle_rag_update::knowledge::{index_document, DocType, DocumentMeta, KnowledgeConfig};
use beagle_rag_update::qdrant::QdrantClient;
use clap::{Parser, Subcommand};
use std::path::PathBuf;
use tracing_subscriber::EnvFilter;

#[derive(Debug, Parser)]
#[command(name = "darwin-knowledge-manager")]
#[command(about = "Index papers/docs/books into separate Qdrant collections")]
struct Args {
    #[arg(long, env = "QDRANT_URL", default_value = "http://localhost:6333")]
    qdrant_url: String,

    #[arg(long, env = "EMBEDDING_URL", default_value = "http://localhost:8001/v1")]
    embedding_url: String,

    #[arg(long, env = "EMBEDDING_MODEL", default_value = "NV-Embed-v2")]
    embedding_model: String,

    #[arg(long, default_value_t = 1500)]
    chunk_size: usize,

    #[arg(long, default_value_t = 200)]
    chunk_overlap: usize,

    #[arg(long, default_value = "darwin-papers")]
    papers_collection: String,

    #[arg(long, default_value = "darwin-docs")]
    docs_collection: String,

    #[arg(long, default_value = "darwin-books")]
    books_collection: String,

    #[arg(long, default_value_t = 5_000_000)]
    max_file_size: u64,

    /// Optional Postgres URL to enable the ingestion ledger
    #[arg(long, env = "DARWIN_LEDGER_DATABASE_URL")]
    ledger_db_url: Option<String>,

    /// Force re-index even if ledger indicates content is unchanged
    #[arg(long)]
    force: bool,

    #[command(subcommand)]
    cmd: Command,
}

#[derive(Debug, Subcommand)]
enum Command {
    /// Show points count for the knowledge collections (+ darwin-repos if present)
    List,
    /// Scan a base directory with `papers/`, `docs/`, `books/` subfolders
    Scan { dir: String },
    AddPaper {
        path: String,
        #[arg(long)]
        title: String,
        #[arg(long)]
        author: Option<String>,
        #[arg(long)]
        year: Option<i32>,
        #[arg(long)]
        doi: Option<String>,
        #[arg(long)]
        source: Option<String>,
        #[arg(long, num_args = 1..)]
        tags: Vec<String>,
    },
    AddDocs {
        path: String,
        #[arg(long)]
        title: String,
        #[arg(long)]
        source: Option<String>,
        #[arg(long, num_args = 1..)]
        tags: Vec<String>,
    },
    AddBook {
        path: String,
        #[arg(long)]
        title: String,
        #[arg(long)]
        author: Option<String>,
        #[arg(long)]
        year: Option<i32>,
        #[arg(long)]
        source: Option<String>,
        #[arg(long, num_args = 1..)]
        tags: Vec<String>,
    },
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

    let ledger = init_ledger(args.ledger_db_url.as_deref()).await?;
    let cfg = KnowledgeConfig {
        qdrant_url: args.qdrant_url.clone(),
        embedding_url: args.embedding_url.clone(),
        embedding_model: args.embedding_model.clone(),
        chunk_size: args.chunk_size,
        chunk_overlap: args.chunk_overlap,
        papers_collection: args.papers_collection.clone(),
        docs_collection: args.docs_collection.clone(),
        books_collection: args.books_collection.clone(),
        max_file_size: args.max_file_size,
        ledger,
        force_reindex: args.force,
    };

    match args.cmd {
        Command::List => {
            let qdrant = QdrantClient::new(&args.qdrant_url);
            for (label, name) in [
                ("papers", args.papers_collection),
                ("docs", args.docs_collection),
                ("books", args.books_collection),
                ("repos", "darwin-repos".to_string()),
            ] {
                match qdrant.get_collection_points_count(&name).await? {
                    Some(n) => println!("{label:8} {name:20} {n} points"),
                    None => println!("{label:8} {name:20} (missing)"),
                }
            }
        }
        Command::Scan { dir } => {
            let base = expand_tilde(&dir);
            let papers = base.join("papers");
            let docs = base.join("docs");
            let books = base.join("books");

            if papers.exists() {
                for entry in std::fs::read_dir(&papers)? {
                    let path = entry?.path();
                    if path.extension().and_then(|e| e.to_str()).unwrap_or("").eq_ignore_ascii_case("pdf") {
                        let title = path.file_stem().and_then(|s| s.to_str()).unwrap_or("paper").to_string();
                        let meta = DocumentMeta {
                            title,
                            path,
                            doc_id: None,
                            author: None,
                            year: None,
                            doi: None,
                            tags: vec![],
                            source: None,
                            license: None,
                            extra: serde_json::json!({}),
                        };
                        let _ = index_document(&cfg, DocType::Paper, meta).await?;
                    }
                }
            }

            if docs.exists() {
                for entry in std::fs::read_dir(&docs)? {
                    let path = entry?.path();
                    let ext = path.extension().and_then(|e| e.to_str()).unwrap_or("").to_lowercase();
                    if matches!(ext.as_str(), "md" | "txt" | "rst") {
                        let title = path.file_stem().and_then(|s| s.to_str()).unwrap_or("doc").to_string();
                        let meta = DocumentMeta {
                            title,
                            path,
                            doc_id: None,
                            author: None,
                            year: None,
                            doi: None,
                            tags: vec![],
                            source: None,
                            license: None,
                            extra: serde_json::json!({}),
                        };
                        let _ = index_document(&cfg, DocType::Doc, meta).await?;
                    }
                }
            }

            if books.exists() {
                for entry in std::fs::read_dir(&books)? {
                    let path = entry?.path();
                    if path.extension().and_then(|e| e.to_str()).unwrap_or("").eq_ignore_ascii_case("pdf") {
                        let title = path.file_stem().and_then(|s| s.to_str()).unwrap_or("book").to_string();
                        let meta = DocumentMeta {
                            title,
                            path,
                            doc_id: None,
                            author: None,
                            year: None,
                            doi: None,
                            tags: vec![],
                            source: None,
                            license: None,
                            extra: serde_json::json!({}),
                        };
                        let _ = index_document(&cfg, DocType::Book, meta).await?;
                    }
                }
            }
        }
        Command::AddPaper {
            path,
            title,
            author,
            year,
            doi,
            source,
            tags,
        } => {
            let meta = DocumentMeta {
                title,
                path: expand_tilde(&path),
                doc_id: None,
                author,
                year,
                doi,
                tags,
                source,
                license: None,
                extra: serde_json::json!({}),
            };
            index_document(&cfg, DocType::Paper, meta).await?;
        }
        Command::AddDocs {
            path,
            title,
            source,
            tags,
        } => {
            let meta = DocumentMeta {
                title,
                path: expand_tilde(&path),
                doc_id: None,
                author: None,
                year: None,
                doi: None,
                tags,
                source,
                license: None,
                extra: serde_json::json!({}),
            };
            index_document(&cfg, DocType::Doc, meta).await?;
        }
        Command::AddBook {
            path,
            title,
            author,
            year,
            source,
            tags,
        } => {
            let meta = DocumentMeta {
                title,
                path: expand_tilde(&path),
                doc_id: None,
                author,
                year,
                doi: None,
                tags,
                source,
                license: None,
                extra: serde_json::json!({}),
            };
            index_document(&cfg, DocType::Book, meta).await?;
        }
    }

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
