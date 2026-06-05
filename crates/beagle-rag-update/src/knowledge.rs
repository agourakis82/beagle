use crate::chunk::chunk_paragraphs;
use crate::embed::EmbeddingClient;
use crate::ledger::{IngestionLedger, LedgerRecord, LedgerStatus};
use crate::qdrant::QdrantClient;
use anyhow::{Context, Result};
use chrono::Utc;
use std::path::{Path, PathBuf};
use tracing::{info, warn};

#[derive(Debug, Clone)]
pub struct KnowledgeConfig {
    pub qdrant_url: String,
    pub embedding_url: String,
    pub embedding_model: String,
    pub chunk_size: usize,
    pub chunk_overlap: usize,
    pub papers_collection: String,
    pub docs_collection: String,
    pub books_collection: String,
    pub max_file_size: u64,
    pub ledger: Option<IngestionLedger>,
    /// Force re-index even if ledger indicates content is unchanged.
    pub force_reindex: bool,
}

#[derive(Debug, Clone)]
pub enum DocType {
    Paper,
    Doc,
    Book,
}

#[derive(Debug, Clone)]
pub struct DocumentMeta {
    pub title: String,
    pub path: PathBuf,
    /// Stable external identifier when available (e.g., DOI, PubMed ID, arXiv ID).
    /// Used to make re-indexing idempotent and avoid title collisions.
    pub doc_id: Option<String>,
    pub author: Option<String>,
    pub year: Option<i32>,
    pub doi: Option<String>,
    pub tags: Vec<String>,
    pub source: Option<String>,
    pub license: Option<String>,
    /// Additional metadata to store in payload (backend-specific).
    pub extra: serde_json::Value,
}

fn collection_for(cfg: &KnowledgeConfig, doc_type: DocType) -> &str {
    match doc_type {
        DocType::Paper => &cfg.papers_collection,
        DocType::Doc => &cfg.docs_collection,
        DocType::Book => &cfg.books_collection,
    }
}

pub fn extract_text(path: &Path) -> Result<String> {
    let ext = path
        .extension()
        .and_then(|e| e.to_str())
        .unwrap_or("")
        .to_lowercase();
    if ext == "pdf" {
        let out = std::process::Command::new("pdftotext")
            .args(["-layout", "-nopgbrk"])
            .arg(path)
            .arg("-")
            .output()
            .context("failed to run pdftotext (install poppler-utils)")?;
        if !out.status.success() {
            anyhow::bail!("pdftotext failed: {}", String::from_utf8_lossy(&out.stderr));
        }
        Ok(String::from_utf8_lossy(&out.stdout).to_string())
    } else {
        Ok(std::fs::read_to_string(path)
            .with_context(|| format!("failed to read {}", path.display()))?)
    }
}

pub async fn index_document(
    cfg: &KnowledgeConfig,
    doc_type: DocType,
    meta: DocumentMeta,
) -> Result<usize> {
    let qdrant = QdrantClient::new(&cfg.qdrant_url);
    let embed = EmbeddingClient::new(&cfg.embedding_url, &cfg.embedding_model);

    let collection = collection_for(cfg, doc_type.clone()).to_string();
    let title = meta.title.clone();
    let doc_id = meta.doc_id.clone().unwrap_or_else(|| title.clone());
    let path_display = meta.path.to_string_lossy().to_string();
    let doc_type_str = match doc_type {
        DocType::Paper => "paper",
        DocType::Doc => "doc",
        DocType::Book => "book",
    };

    let file_meta = std::fs::metadata(&meta.path)?;
    if file_meta.len() > cfg.max_file_size
        && meta
            .path
            .extension()
            .and_then(|e| e.to_str())
            .unwrap_or("")
            .to_lowercase()
            != "pdf"
    {
        anyhow::bail!("file too large: {}", meta.path.display());
    }

    let text = extract_text(&meta.path)?;
    let content_hash = blake3::hash(text.as_bytes()).to_hex().to_string();
    let now = Utc::now();

    let source_url = meta
        .extra
        .get("final_url")
        .and_then(|v| v.as_str())
        .or_else(|| meta.extra.get("url").and_then(|v| v.as_str()))
        .map(|s| s.to_string())
        .or_else(|| {
            if doc_id.starts_with("http://") || doc_id.starts_with("https://") {
                Some(doc_id.clone())
            } else {
                None
            }
        });

    if let Some(ref ledger) = cfg.ledger {
        ledger.ensure_schema().await?;
        if !cfg.force_reindex {
            if let Some(prev_hash) = ledger.get_content_hash(&collection, &doc_id).await? {
                if prev_hash == content_hash {
                    ledger
                        .upsert(LedgerRecord {
                            collection: collection.clone(),
                            doc_id: doc_id.clone(),
                            doc_type: doc_type_str.to_string(),
                            source_type: meta.source.clone().unwrap_or_else(|| "file".to_string()),
                            source: meta.source.clone(),
                            source_path: Some(path_display.clone()),
                            source_url,
                            title: Some(title.clone()),
                            content_hash: content_hash.clone(),
                            tags: meta.tags.clone(),
                            license: meta.license.clone(),
                            status: LedgerStatus::SkippedUnchanged,
                            error: None,
                            fetched_at: Some(now),
                            indexed_at: None,
                            meta: meta.extra.clone(),
                        })
                        .await?;
                    info!(collection = %collection, doc_id = %doc_id, "skipping unchanged document (ledger)");
                    return Ok(0);
                }
            }
        }
    }

    if qdrant
        .get_collection_points_count(&collection)
        .await?
        .is_none()
    {
        let vectors = embed
            .embed_batch(&[String::from("darwin knowledge init")])
            .await?;
        let dim = vectors.first().map(|v| v.len()).unwrap_or(0);
        if dim == 0 {
            anyhow::bail!("failed to infer embedding dimension");
        }
        qdrant.ensure_collection(&collection, dim).await?;
    }

    let chunks = chunk_paragraphs(&text, cfg.chunk_size, cfg.chunk_overlap);
    if chunks.is_empty() {
        return Ok(0);
    }

    // Replace-by-doc_id semantics.
    qdrant
        .delete_by_payload_match(
            &collection,
            vec![("doc_id", serde_json::Value::String(doc_id.clone()))],
        )
        .await
        .ok();

    let mut upserted = 0usize;
    let batch_size = 8usize;
    for batch in chunks.chunks(batch_size) {
        let texts: Vec<String> = batch.iter().map(|c| c.text.clone()).collect();
        let vectors = embed.embed_batch(&texts).await?;
        let mut points = Vec::with_capacity(batch.len());
        for (chunk, vector) in batch.iter().zip(vectors) {
            let id = QdrantClient::stable_u64_id(&[&collection, &doc_id, &chunk.index.to_string()]);
            let mut payload = serde_json::json!({
                "doc_id": doc_id.clone(),
                "title": title.clone(),
                "chunk_idx": chunk.index,
                "text": chunk.text.clone(),
                "doc_type": doc_type_str,
                "path": path_display.clone(),
                "indexed_at": Utc::now().to_rfc3339(),
            });
            if let Some(author) = meta.author.clone() {
                payload["author"] = serde_json::Value::String(author);
            }
            if let Some(year) = meta.year {
                payload["year"] = serde_json::Value::from(year);
            }
            if let Some(doi) = meta.doi.clone() {
                payload["doi"] = serde_json::Value::String(doi);
            }
            if !meta.tags.is_empty() {
                payload["tags"] = serde_json::Value::Array(
                    meta.tags
                        .iter()
                        .cloned()
                        .map(serde_json::Value::String)
                        .collect(),
                );
            }
            if let Some(source) = meta.source.clone() {
                payload["source"] = serde_json::Value::String(source);
            }
            if let Some(license) = meta.license.clone() {
                payload["license"] = serde_json::Value::String(license);
            }
            if meta.extra != serde_json::Value::Null && meta.extra != serde_json::json!({}) {
                payload["meta"] = meta.extra.clone();
            }

            points.push(serde_json::json!({
                "id": id,
                "vector": vector,
                "payload": payload,
            }));
        }
        qdrant.upsert_points(&collection, points).await?;
        upserted += batch.len();
    }

    info!(collection = %collection, title = %meta.title, chunks = upserted, "indexed document");

    if let Some(ref ledger) = cfg.ledger {
        if let Err(e) = ledger
            .upsert(LedgerRecord {
                collection: collection.clone(),
                doc_id: doc_id.clone(),
                doc_type: doc_type_str.to_string(),
                source_type: meta.source.clone().unwrap_or_else(|| "file".to_string()),
                source: meta.source.clone(),
                source_path: Some(path_display.clone()),
                source_url,
                title: Some(title.clone()),
                content_hash,
                tags: meta.tags.clone(),
                license: meta.license.clone(),
                status: LedgerStatus::Indexed,
                error: None,
                fetched_at: Some(now),
                indexed_at: Some(now),
                meta: meta.extra.clone(),
            })
            .await
        {
            warn!(collection = %collection, doc_id = %doc_id, "failed to update ingestion ledger: {e:#}");
        }
    }

    Ok(upserted)
}
