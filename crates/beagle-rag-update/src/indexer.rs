use crate::chunk::{chunk_lines, chunk_paragraphs};
use crate::embed::EmbeddingClient;
use crate::git;
use crate::ledger::{IngestionLedger, LedgerRecord, LedgerStatus};
use crate::qdrant::{post_webhook_json, QdrantClient};
use crate::state::{IndexState, RepoState};
use anyhow::{Context, Result};

/// Opt-in: when on, the indexer writes Qdrant-native hybrid points (named dense +
/// IDF sparse) into a hybrid collection so `query_hybrid` (/points/query + RRF) has
/// sparse vectors to match. Off by default — the dense path is unchanged (plan #8).
fn hybrid_retrieval_enabled() -> bool {
    std::env::var("BEAGLE_HYBRID_RETRIEVAL")
        .map(|v| matches!(v.trim().to_ascii_lowercase().as_str(), "1" | "true" | "yes" | "on"))
        .unwrap_or(false)
}
use chrono::Utc;
use std::collections::{HashMap, HashSet};
use std::path::{Path, PathBuf};
use tracing::{info, warn};
use walkdir::WalkDir;

#[derive(Debug, Clone)]
pub struct IndexerConfig {
    pub repos_dir: PathBuf,
    pub state_file: PathBuf,
    pub qdrant_url: String,
    pub embedding_url: String,
    pub embedding_model: String,
    pub collection: String,
    pub chunk_size: usize,
    pub chunk_overlap: usize,
    pub extensions: HashSet<String>,
    pub ignore_dirs: HashSet<String>,
    pub max_file_size: u64,
    pub error_webhook_url: Option<String>,
    pub success_webhook_url: Option<String>,
    pub ledger: Option<IngestionLedger>,
}

#[derive(Debug, Clone)]
pub struct RepoTarget {
    pub name: String,
    pub path: PathBuf,
    pub url: Option<String>,
}

#[derive(Debug, Default, Clone)]
pub struct IndexSummary {
    pub repos: usize,
    pub files_added: usize,
    pub files_modified: usize,
    pub files_deleted: usize,
    pub files_skipped_unchanged: usize,
    pub chunks_upserted: usize,
}

#[derive(Debug, Clone)]
enum FileIndexOutcome {
    Indexed { chunks: usize },
    SkippedUnchanged,
}

fn is_ignored(path: &Path, ignore_dirs: &HashSet<String>) -> bool {
    path.components().any(|c| {
        let s = c.as_os_str().to_string_lossy();
        ignore_dirs.contains(s.as_ref())
    })
}

fn has_allowed_ext(path: &Path, extensions: &HashSet<String>) -> bool {
    let ext = path
        .extension()
        .and_then(|e| e.to_str())
        .unwrap_or("")
        .to_lowercase();
    extensions.contains(&format!(".{ext}"))
}

fn list_all_files(repo_path: &Path, cfg: &IndexerConfig) -> Result<Vec<String>> {
    let mut out = Vec::new();
    for entry in WalkDir::new(repo_path)
        .follow_links(false)
        .into_iter()
        .filter_entry(|e| !is_ignored(e.path(), &cfg.ignore_dirs))
    {
        let entry = entry?;
        let path = entry.path();
        if !entry.file_type().is_file() {
            continue;
        }
        if !has_allowed_ext(path, &cfg.extensions) {
            continue;
        }
        let meta = entry.metadata()?;
        if meta.len() > cfg.max_file_size {
            continue;
        }
        let rel = path
            .strip_prefix(repo_path)
            .unwrap_or(path)
            .to_string_lossy()
            .to_string();
        out.push(rel);
    }
    Ok(out)
}

fn chunk_for_path(path: &str, content: &str, cfg: &IndexerConfig) -> Vec<crate::chunk::Chunk> {
    let ext = Path::new(path)
        .extension()
        .and_then(|e| e.to_str())
        .unwrap_or("")
        .to_lowercase();
    match ext.as_str() {
        "md" | "txt" | "rst" => chunk_paragraphs(content, cfg.chunk_size, cfg.chunk_overlap),
        _ => chunk_lines(content, cfg.chunk_size, cfg.chunk_overlap),
    }
}

async fn index_file(
    qdrant: &QdrantClient,
    embed: &EmbeddingClient,
    cfg: &IndexerConfig,
    repo: &str,
    repo_path: &Path,
    file_path: &str,
    head: &str,
    repo_url: Option<&str>,
    allow_ledger_skip: bool,
) -> Result<FileIndexOutcome> {
    let full_path = repo_path.join(file_path);
    let content = std::fs::read_to_string(&full_path)
        .with_context(|| format!("failed to read {}", full_path.display()))?;

    let now = Utc::now();
    let content_hash = blake3::hash(content.as_bytes()).to_hex().to_string();
    let doc_id = format!("repo:{repo}/{file_path}");
    let title = format!("{repo}/{file_path}");

    if allow_ledger_skip {
        if let Some(ref ledger) = cfg.ledger {
            if let Some(prev_hash) = ledger.get_content_hash(&cfg.collection, &doc_id).await? {
                if prev_hash == content_hash {
                    let _ = ledger
                        .upsert(LedgerRecord {
                            collection: cfg.collection.clone(),
                            doc_id,
                            doc_type: "repo_file".to_string(),
                            source_type: "repo".to_string(),
                            source: Some(repo.to_string()),
                            source_path: Some(full_path.to_string_lossy().to_string()),
                            source_url: repo_url.map(|s| s.to_string()),
                            title: Some(title),
                            content_hash,
                            tags: vec![],
                            license: None,
                            status: LedgerStatus::SkippedUnchanged,
                            error: None,
                            fetched_at: Some(now),
                            indexed_at: None,
                            meta: serde_json::json!({
                                "repo": repo,
                                "file": file_path,
                                "commit": head,
                                "skip_reason": "ledger_hash_match",
                            }),
                        })
                        .await;
                    return Ok(FileIndexOutcome::SkippedUnchanged);
                }
            }
        }
    }

    let chunks = chunk_for_path(file_path, &content, cfg);
    if chunks.is_empty() {
        return Ok(FileIndexOutcome::Indexed { chunks: 0 });
    }

    qdrant
        .delete_by_payload_match(
            &cfg.collection,
            vec![
                ("repo", serde_json::Value::String(repo.to_string())),
                ("file", serde_json::Value::String(file_path.to_string())),
            ],
        )
        .await
        .context("failed to delete existing file chunks")?;

    let mut upserted = 0usize;
    let batch_size = 8usize;
    let hybrid = hybrid_retrieval_enabled();
    for batch in chunks.chunks(batch_size) {
        let texts: Vec<String> = batch.iter().map(|c| c.text.clone()).collect();
        let vectors = embed.embed_batch(&texts).await?;
        let mut points = Vec::with_capacity(batch.len());
        for (chunk, vector) in batch.iter().zip(vectors) {
            let id = QdrantClient::stable_u64_id(&[
                &cfg.collection,
                repo,
                file_path,
                &chunk.index.to_string(),
            ]);
            let title = format!("{repo}/{file_path}");
            let payload = serde_json::json!({
                "repo": repo,
                "file": file_path,
                "chunk_idx": chunk.index,
                "title": title,
                "text": chunk.text.clone(),
                "source_type": "repo",
                "commit": head,
                "indexed_at": Utc::now().to_rfc3339(),
            });
            if hybrid {
                let (indices, values) = crate::qdrant::sparse_from_text(&chunk.text);
                points.push(serde_json::json!({
                    "id": id,
                    "vector": { "dense": vector, "text": { "indices": indices, "values": values } },
                    "payload": payload,
                }));
            } else {
                points.push(serde_json::json!({
                    "id": id,
                    "vector": vector,
                    "payload": payload,
                }));
            }
        }
        if hybrid {
            qdrant.upsert_hybrid_points(&cfg.collection, points).await
        } else {
            qdrant.upsert_points(&cfg.collection, points).await
        }
        .context("failed to upsert points")?;
        upserted += batch.len();
    }

    if let Some(ref ledger) = cfg.ledger {
        let _ = ledger
            .upsert(LedgerRecord {
                collection: cfg.collection.clone(),
                doc_id,
                doc_type: "repo_file".to_string(),
                source_type: "repo".to_string(),
                source: Some(repo.to_string()),
                source_path: Some(full_path.to_string_lossy().to_string()),
                source_url: repo_url.map(|s| s.to_string()),
                title: Some(title),
                content_hash,
                tags: vec![],
                license: None,
                status: LedgerStatus::Indexed,
                error: None,
                fetched_at: Some(now),
                indexed_at: Some(now),
                meta: serde_json::json!({
                    "repo": repo,
                    "file": file_path,
                    "commit": head,
                    "chunks_upserted": upserted,
                }),
            })
            .await;
    }

    Ok(FileIndexOutcome::Indexed { chunks: upserted })
}

pub async fn run_incremental(
    cfg: &IndexerConfig,
    mut repos: Vec<RepoTarget>,
    force: bool,
    sync: bool,
) -> Result<IndexSummary> {
    let mut state = IndexState::load(&cfg.state_file)?;

    let qdrant = QdrantClient::new(&cfg.qdrant_url);
    let embed = EmbeddingClient::new(&cfg.embedding_url, &cfg.embedding_model);

    if let Some(ref ledger) = cfg.ledger {
        ledger.ensure_schema().await?;
    }

    // Ensure collection exists (create if missing) by probing embedding dimension.
    if qdrant
        .get_collection_points_count(&cfg.collection)
        .await?
        .is_none()
    {
        let vectors = embed
            .embed_batch(&[String::from("darwin indexer init")])
            .await?;
        let dim = vectors.first().map(|v| v.len()).unwrap_or_else(|| 0usize);
        if dim == 0 {
            anyhow::bail!("failed to infer embedding dimension");
        }
        if hybrid_retrieval_enabled() {
            qdrant.ensure_hybrid_collection(&cfg.collection, dim).await?;
        } else {
            qdrant.ensure_collection(&cfg.collection, dim).await?;
        }
    }

    let mut summary = IndexSummary::default();
    summary.repos = repos.len();
    let mut had_errors = false;

    for repo in repos.iter_mut() {
        info!(repo = %repo.name, path = %repo.path.display(), "indexing repo");

        if repo.url.is_some() && !repo.path.exists() {
            git::clone_repo(repo.url.as_ref().unwrap(), &repo.path)
                .with_context(|| format!("failed to clone {}", repo.url.as_ref().unwrap()))?;
        }

        if sync && git::is_git_repo(&repo.path) {
            if let Err(e) = git::pull_ff_only(&repo.path) {
                warn!(repo = %repo.name, "git pull failed (continuing): {e:#}");
                had_errors = true;
            }
        }

        let head = git::head_commit(&repo.path)
            .with_context(|| format!("failed to resolve HEAD for {}", repo.path.display()))?;

        let prev_head = state.repos.get(&repo.name).and_then(|rs| rs.head.clone());

        let changes = if force {
            None
        } else if let Some(prev) = &prev_head {
            match git::diff_name_status(&repo.path, prev, &head) {
                Ok(c) => Some(c),
                Err(e) => {
                    warn!(repo = %repo.name, "git diff failed, falling back to full scan: {e:#}");
                    None
                }
            }
        } else {
            None
        };

        let allow_ledger_skip = changes.is_none() && !force;

        let (to_index_added, to_index_modified, to_delete, stats_by_kind) =
            if let Some(changes) = changes {
                let mut added = HashSet::new();
                let mut modified = HashSet::new();
                let mut deleted = HashSet::new();
                let mut by_kind: HashMap<git::ChangeKind, usize> = HashMap::new();

                for ch in changes {
                    *by_kind.entry(ch.kind).or_insert(0) += 1;
                    match ch.kind {
                        git::ChangeKind::Added => {
                            added.insert(ch.path);
                        }
                        git::ChangeKind::Modified => {
                            modified.insert(ch.path);
                        }
                        git::ChangeKind::Deleted => {
                            deleted.insert(ch.path);
                        }
                        git::ChangeKind::Renamed => {
                            if let Some(old) = ch.old_path {
                                deleted.insert(old);
                            }
                            // treat rename as modified for counting purposes
                            modified.insert(ch.path);
                        }
                    }
                }
                (added, modified, deleted, by_kind)
            } else {
                let all = list_all_files(&repo.path, cfg)?;
                (
                    all.into_iter().collect(),
                    HashSet::new(),
                    HashSet::new(),
                    HashMap::new(),
                )
            };

        let mut filtered_add: Vec<String> = Vec::new();
        for rel in to_index_added.iter() {
            let full = repo.path.join(rel);
            if is_ignored(&full, &cfg.ignore_dirs) {
                continue;
            }
            if !has_allowed_ext(&full, &cfg.extensions) {
                continue;
            }
            if let Ok(meta) = std::fs::metadata(&full) {
                if meta.len() > cfg.max_file_size {
                    continue;
                }
            } else {
                continue;
            }
            filtered_add.push(rel.clone());
        }

        let mut filtered_modified: Vec<String> = Vec::new();
        for rel in to_index_modified.iter() {
            let full = repo.path.join(rel);
            if is_ignored(&full, &cfg.ignore_dirs) {
                continue;
            }
            if !has_allowed_ext(&full, &cfg.extensions) {
                continue;
            }
            if let Ok(meta) = std::fs::metadata(&full) {
                if meta.len() > cfg.max_file_size {
                    continue;
                }
            } else {
                continue;
            }
            filtered_modified.push(rel.clone());
        }

        let mut filtered_del: Vec<String> = Vec::new();
        for rel in to_delete {
            let full = Path::new(&rel);
            if !has_allowed_ext(full, &cfg.extensions) {
                continue;
            }
            filtered_del.push(rel);
        }

        info!(
            repo = %repo.name,
            add = filtered_add.len(),
            modified = filtered_modified.len(),
            del = filtered_del.len(),
            prev_head = prev_head.as_deref().unwrap_or("<none>"),
            head = %head,
            "detected changes"
        );
        if !stats_by_kind.is_empty() {
            info!(repo = %repo.name, "git stats: {:?}", stats_by_kind);
        }

        for rel in filtered_del.iter() {
            if let Err(e) = qdrant
                .delete_by_payload_match(
                    &cfg.collection,
                    vec![
                        ("repo", serde_json::Value::String(repo.name.clone())),
                        ("file", serde_json::Value::String(rel.clone())),
                    ],
                )
                .await
            {
                warn!(repo = %repo.name, file = %rel, "failed to delete chunks: {e:#}");
                had_errors = true;
            } else {
                summary.files_deleted += 1;
            }

            if let Some(ref ledger) = cfg.ledger {
                let doc_id = format!("repo:{}/{}", repo.name, rel);
                let prev_hash = match ledger.get_content_hash(&cfg.collection, &doc_id).await {
                    Ok(Some(h)) => h,
                    _ => "deleted".to_string(),
                };
                let _ = ledger
                    .upsert(LedgerRecord {
                        collection: cfg.collection.clone(),
                        doc_id,
                        doc_type: "repo_file".to_string(),
                        source_type: "repo".to_string(),
                        source: Some(repo.name.clone()),
                        source_path: None,
                        source_url: repo.url.clone(),
                        title: Some(format!("{}/{}", repo.name, rel)),
                        content_hash: prev_hash,
                        tags: vec![],
                        license: None,
                        status: LedgerStatus::Deleted,
                        error: None,
                        fetched_at: None,
                        indexed_at: Some(Utc::now()),
                        meta: serde_json::json!({
                            "repo": repo.name,
                            "file": rel,
                            "commit": head,
                        }),
                    })
                    .await;
            }
        }

        for rel in filtered_add.iter() {
            match index_file(
                &qdrant,
                &embed,
                cfg,
                &repo.name,
                &repo.path,
                rel,
                &head,
                repo.url.as_deref(),
                allow_ledger_skip,
            )
            .await
            {
                Ok(FileIndexOutcome::Indexed { chunks }) => {
                    summary.chunks_upserted += chunks;
                    summary.files_added += 1;
                }
                Ok(FileIndexOutcome::SkippedUnchanged) => {
                    summary.files_skipped_unchanged += 1;
                }
                Err(e) => {
                    warn!(repo = %repo.name, file = %rel, "failed to index file: {e:#}");
                    had_errors = true;
                    if let Some(ref ledger) = cfg.ledger {
                        let doc_id = format!("repo:{}/{}", repo.name, rel);
                        let prev_hash =
                            match ledger.get_content_hash(&cfg.collection, &doc_id).await {
                                Ok(Some(h)) => h,
                                _ => "error".to_string(),
                            };
                        let _ = ledger
                            .upsert(LedgerRecord {
                                collection: cfg.collection.clone(),
                                doc_id,
                                doc_type: "repo_file".to_string(),
                                source_type: "repo".to_string(),
                                source: Some(repo.name.clone()),
                                source_path: Some(
                                    repo.path.join(rel).to_string_lossy().to_string(),
                                ),
                                source_url: repo.url.clone(),
                                title: Some(format!("{}/{}", repo.name, rel)),
                                content_hash: prev_hash,
                                tags: vec![],
                                license: None,
                                status: LedgerStatus::Error,
                                error: Some(format!("{e:#}")),
                                fetched_at: Some(Utc::now()),
                                indexed_at: None,
                                meta: serde_json::json!({
                                    "repo": repo.name,
                                    "file": rel,
                                    "commit": head,
                                }),
                            })
                            .await;
                    }
                }
            }
        }

        for rel in filtered_modified.iter() {
            match index_file(
                &qdrant,
                &embed,
                cfg,
                &repo.name,
                &repo.path,
                rel,
                &head,
                repo.url.as_deref(),
                false,
            )
            .await
            {
                Ok(FileIndexOutcome::Indexed { chunks }) => {
                    summary.chunks_upserted += chunks;
                    summary.files_modified += 1;
                }
                Ok(FileIndexOutcome::SkippedUnchanged) => {
                    summary.files_skipped_unchanged += 1;
                }
                Err(e) => {
                    warn!(repo = %repo.name, file = %rel, "failed to index file: {e:#}");
                    had_errors = true;
                    if let Some(ref ledger) = cfg.ledger {
                        let doc_id = format!("repo:{}/{}", repo.name, rel);
                        let prev_hash =
                            match ledger.get_content_hash(&cfg.collection, &doc_id).await {
                                Ok(Some(h)) => h,
                                _ => "error".to_string(),
                            };
                        let _ = ledger
                            .upsert(LedgerRecord {
                                collection: cfg.collection.clone(),
                                doc_id,
                                doc_type: "repo_file".to_string(),
                                source_type: "repo".to_string(),
                                source: Some(repo.name.clone()),
                                source_path: Some(
                                    repo.path.join(rel).to_string_lossy().to_string(),
                                ),
                                source_url: repo.url.clone(),
                                title: Some(format!("{}/{}", repo.name, rel)),
                                content_hash: prev_hash,
                                tags: vec![],
                                license: None,
                                status: LedgerStatus::Error,
                                error: Some(format!("{e:#}")),
                                fetched_at: Some(Utc::now()),
                                indexed_at: None,
                                meta: serde_json::json!({
                                    "repo": repo.name,
                                    "file": rel,
                                    "commit": head,
                                }),
                            })
                            .await;
                    }
                }
            }
        }

        state.repos.insert(
            repo.name.clone(),
            RepoState {
                head: Some(head),
                last_indexed_at: Some(Utc::now()),
            },
        );
    }

    state.last_run = Some(Utc::now());
    state.save(&cfg.state_file)?;

    if let Some(collection_points) = qdrant.get_collection_points_count(&cfg.collection).await? {
        info!(collection = %cfg.collection, points = collection_points, "qdrant collection status");
    }

    if had_errors {
        if let Some(webhook_url) = &cfg.error_webhook_url {
            let _ = post_webhook_json(
                webhook_url,
                serde_json::json!({
                    "event": "darwin_indexer_error",
                    "at": Utc::now().to_rfc3339(),
                    "repos": summary.repos,
                    "files_added": summary.files_added,
                    "files_modified": summary.files_modified,
                    "files_deleted": summary.files_deleted,
                    "files_skipped_unchanged": summary.files_skipped_unchanged,
                    "chunks_upserted": summary.chunks_upserted,
                }),
            )
            .await;
        }
    } else if let Some(webhook_url) = &cfg.success_webhook_url {
        let _ = post_webhook_json(
            webhook_url,
            serde_json::json!({
                "event": "darwin_indexer_success",
                "at": Utc::now().to_rfc3339(),
                "repos": summary.repos,
                "files_added": summary.files_added,
                "files_modified": summary.files_modified,
                "files_deleted": summary.files_deleted,
                "files_skipped_unchanged": summary.files_skipped_unchanged,
                "chunks_upserted": summary.chunks_upserted,
            }),
        )
        .await;
    }

    Ok(summary)
}
