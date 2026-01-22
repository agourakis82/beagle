use crate::chunk::chunk_paragraphs;
use crate::embed::EmbeddingClient;
use crate::ledger::{IngestionLedger, LedgerRecord, LedgerStatus};
use crate::qdrant::QdrantClient;
use anyhow::{Context, Result};
use chrono::{Datelike, Utc};
use regex::Regex;
use std::path::{Path, PathBuf};
use std::sync::Arc;
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
    /// Optional metadata enricher for DOI/arXiv extraction + external lookup (Crossref/OpenAlex/arXiv).
    pub metadata_enricher: Option<Arc<MetadataEnricher>>,
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

/// Best-effort metadata enrichment for knowledge documents.
///
/// Fills missing `doc_id`/`doi` by extracting identifiers from the content (or filename),
/// then queries Crossref/OpenAlex/arXiv to enrich title/authors/year/tags.
pub struct MetadataEnricher {
    crossref: beagle_search::CrossrefClient,
    openalex: beagle_search::OpenAlexClient,
    arxiv: beagle_search::ArxivClient,
}

impl std::fmt::Debug for MetadataEnricher {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.debug_struct("MetadataEnricher").finish_non_exhaustive()
    }
}

impl MetadataEnricher {
    pub fn from_env() -> Self {
        Self {
            crossref: beagle_search::CrossrefClient::from_env(),
            openalex: beagle_search::OpenAlexClient::from_env(),
            arxiv: beagle_search::ArxivClient::new(),
        }
    }

    pub async fn enrich(&self, meta: &mut DocumentMeta, text: &str) {
        let mut enrichment = serde_json::json!({});

        let stem = meta
            .path
            .file_stem()
            .and_then(|s| s.to_str())
            .unwrap_or("")
            .to_string();

        // 1) Extract identifiers from content/filename.
        let mut doi = meta.doi.clone().or_else(|| extract_doi(text));
        let mut arxiv_id = extract_arxiv_id(text).or_else(|| extract_arxiv_id(&stem));

        // 2) If we only have arXiv, fetch arXiv first (may yield DOI).
        if doi.is_none() {
            if let Some(ref id) = arxiv_id {
                match beagle_search::SearchClient::fetch_paper(&self.arxiv, id).await {
                    Ok(paper) => {
                        enrichment["arxiv"] = serde_json::json!({
                            "id": paper.id,
                            "url": paper.url,
                            "pdf_url": paper.pdf_url,
                            "doi": paper.doi,
                            "categories": paper.categories,
                        });

                        if meta.title == stem || meta.title.eq_ignore_ascii_case("paper") {
                            meta.title = paper.title.clone();
                        }
                        if meta.author.is_none() && !paper.authors.is_empty() {
                            meta.author = Some(
                                paper.authors
                                    .iter()
                                    .map(|a| a.full_name())
                                    .collect::<Vec<_>>()
                                    .join(", "),
                            );
                        }
                        if meta.year.is_none() {
                            meta.year = paper.published_date.map(|d| d.year() as i32);
                        }
                        if meta.tags.is_empty() && !paper.categories.is_empty() {
                            meta.tags = paper.categories.clone();
                        } else {
                            extend_tags(&mut meta.tags, &paper.categories);
                        }

                        if meta.doi.is_none() {
                            meta.doi = paper.doi.clone();
                        }
                        doi = meta.doi.clone().or_else(|| paper.doi.clone());
                    }
                    Err(e) => {
                        warn!(arxiv_id = %id, "metadata enrichment: arXiv fetch failed: {e}");
                    }
                }
            }
        }

        // 3) If DOI found, normalize + enrich with Crossref/OpenAlex.
        if let Some(ref raw_doi) = doi {
            let norm_doi = normalize_doi(raw_doi);
            doi = Some(norm_doi.clone());
            if meta.doi.is_none() {
                meta.doi = Some(norm_doi.clone());
            } else {
                meta.doi = Some(norm_doi.clone());
            }

            if meta.doc_id.is_none() {
                meta.doc_id = Some(norm_doi.clone());
            }

            match beagle_search::SearchClient::fetch_paper(&self.crossref, &norm_doi).await {
                Ok(paper) => {
                    enrichment["crossref"] = serde_json::json!({
                        "doi": paper.doi,
                        "url": paper.url,
                        "journal": paper.journal,
                        "citation_count": paper.citation_count,
                        "categories": paper.categories,
                    });

                    if meta.title == stem
                        || meta.title.eq_ignore_ascii_case("paper")
                        || meta.title.eq_ignore_ascii_case("doc")
                        || meta.title.eq_ignore_ascii_case("book")
                    {
                        meta.title = paper.title.clone();
                    }
                    if meta.author.is_none() && !paper.authors.is_empty() {
                        meta.author = Some(
                            paper.authors
                                .iter()
                                .map(|a| a.full_name())
                                .collect::<Vec<_>>()
                                .join(", "),
                        );
                    }
                    if meta.year.is_none() {
                        meta.year = paper.published_date.map(|d| d.year() as i32);
                    }
                    extend_tags(&mut meta.tags, &paper.categories);
                }
                Err(e) => {
                    warn!(doi = %norm_doi, "metadata enrichment: Crossref fetch failed: {e}");
                }
            }

            let query = beagle_search::SearchQuery::new(&norm_doi).with_max_results(3);
            match beagle_search::SearchClient::search(&self.openalex, &query).await {
                Ok(result) => {
                    if let Some(paper) = result.papers.into_iter().next() {
                        enrichment["openalex"] = serde_json::json!({
                            "id": paper.id,
                            "doi": paper.doi,
                            "url": paper.url,
                            "pdf_url": paper.pdf_url,
                            "citation_count": paper.citation_count,
                            "categories": paper.categories,
                        });
                        if meta.year.is_none() {
                            meta.year = paper.published_date.map(|d| d.year() as i32);
                        }
                        extend_tags(&mut meta.tags, &paper.categories);
                        if meta.source.is_none() {
                            meta.source = Some("openalex".to_string());
                        }
                        if meta.extra.get("pdf_url").is_none() {
                            if let Some(pdf) = paper.pdf_url {
                                ensure_object(&mut meta.extra)
                                    .insert("pdf_url".to_string(), serde_json::Value::String(pdf));
                            }
                        }
                    }
                }
                Err(e) => {
                    warn!(doi = %norm_doi, "metadata enrichment: OpenAlex search failed: {e}");
                }
            }
        }

        if meta.doc_id.is_none() {
            if let Some(ref d) = doi {
                meta.doc_id = Some(d.clone());
            } else if let Some(id) = arxiv_id.take() {
                meta.doc_id = Some(format!("arxiv:{id}"));
            }
        }

        // Store enrichment summary under meta.extra.enrichment (best-effort).
        if enrichment != serde_json::json!({}) {
            ensure_object(&mut meta.extra).insert("enrichment".to_string(), enrichment);
        }
    }
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
            anyhow::bail!(
                "pdftotext failed: {}",
                String::from_utf8_lossy(&out.stderr)
            );
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
    mut meta: DocumentMeta,
) -> Result<usize> {
    let qdrant = QdrantClient::new(&cfg.qdrant_url);
    let embed = EmbeddingClient::new(&cfg.embedding_url, &cfg.embedding_model);

    let collection = collection_for(cfg, doc_type.clone()).to_string();
    let path_display = meta.path.to_string_lossy().to_string();
    let doc_type_str = match doc_type {
        DocType::Paper => "paper",
        DocType::Doc => "doc",
        DocType::Book => "book",
    };

    let file_meta = std::fs::metadata(&meta.path)?;
    if file_meta.len() > cfg.max_file_size && meta.path.extension().and_then(|e| e.to_str()).unwrap_or("").to_lowercase() != "pdf" {
        anyhow::bail!("file too large: {}", meta.path.display());
    }

    let text = extract_text(&meta.path)?;
    let content_hash = blake3::hash(text.as_bytes()).to_hex().to_string();
    let now = Utc::now();

    if let Some(ref enricher) = cfg.metadata_enricher {
        enricher.enrich(&mut meta, &text).await;
    }

    let title = meta.title.clone();
    let doc_id = meta.doc_id.clone().unwrap_or_else(|| title.clone());

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
        for (chunk, vector) in batch.iter().zip(vectors.into_iter()) {
            let id = QdrantClient::stable_u64_id(&[
                &collection,
                &doc_id,
                &chunk.index.to_string(),
            ]);
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

fn normalize_doi(doi: &str) -> String {
    doi.trim()
        .strip_prefix("https://doi.org/")
        .or_else(|| doi.trim().strip_prefix("http://doi.org/"))
        .or_else(|| doi.trim().strip_prefix("doi:"))
        .unwrap_or(doi.trim())
        .trim_matches(|c: char| c.is_ascii_punctuation())
        .to_string()
}

fn extract_doi(text: &str) -> Option<String> {
    let re = Regex::new(r"(?i)10\\.\\d{4,9}/[-._;()/:A-Z0-9]+").ok()?;
    let m = re.find(text)?;
    Some(normalize_doi(m.as_str()))
}

fn extract_arxiv_id(text: &str) -> Option<String> {
    // New style: 2401.01234v2 (often shown as "arXiv:2401.01234")
    let re_new = Regex::new(r"(?i)arxiv\\s*[:]?\\s*(\\d{4}\\.\\d{4,5}(?:v\\d+)?)").ok()?;
    if let Some(cap) = re_new.captures(text) {
        return cap.get(1).map(|m| m.as_str().to_string());
    }
    // Also accept raw new-style IDs in filenames like "2401.01234.pdf"
    let re_raw_new = Regex::new(r"\\b(\\d{4}\\.\\d{4,5}(?:v\\d+)?)\\b").ok()?;
    if let Some(cap) = re_raw_new.captures(text) {
        return cap.get(1).map(|m| m.as_str().to_string());
    }
    // Old style: hep-th/9901001v1
    let re_old =
        Regex::new(r"(?i)arxiv\\s*[:]?\\s*([a-z-]+(?:\\.[A-Z]{2})?/\\d{7}(?:v\\d+)?)").ok()?;
    cap1(&re_old, text)
}

fn cap1(re: &Regex, text: &str) -> Option<String> {
    re.captures(text)
        .and_then(|c| c.get(1).map(|m| m.as_str().to_string()))
}

fn ensure_object(v: &mut serde_json::Value) -> &mut serde_json::Map<String, serde_json::Value> {
    if !v.is_object() {
        *v = serde_json::json!({});
    }
    v.as_object_mut().expect("meta.extra must be object")
}

fn extend_tags(tags: &mut Vec<String>, new_tags: &[String]) {
    for t in new_tags {
        if !tags.iter().any(|x| x.eq_ignore_ascii_case(t)) {
            tags.push(t.clone());
        }
    }
}
