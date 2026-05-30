use anyhow::{Context, Result};
use beagle_rag_update::ledger::IngestionLedger;
use beagle_rag_update::knowledge::{index_document, DocType, DocumentMeta, KnowledgeConfig};
use beagle_search::{
    ArxivClient, CrossrefClient, EuropePmcClient, OpenAlexClient, PubMedClient, SearchClient,
    SearchQuery,
};
use clap::{Parser, ValueEnum};
use chrono::Datelike;
use regex::Regex;
use serde::Deserialize;
use std::collections::HashSet;
use std::path::{Path, PathBuf};
use tracing::{info, warn};

#[derive(Debug, Clone, Copy, ValueEnum, Deserialize, PartialEq, Eq, Hash)]
#[serde(rename_all = "lowercase")]
enum Backend {
    Pubmed,
    Arxiv,
    Openalex,
    Crossref,
    Europepmc,
    All,
}

#[derive(Debug, Parser)]
#[command(name = "darwin-research-harvester")]
#[command(about = "Fetch fresh papers (PubMed/arXiv) and index abstracts into Qdrant", long_about = None)]
struct Args {
    /// Qdrant base URL
    #[arg(long, env = "QDRANT_URL", default_value = "http://localhost:6333")]
    qdrant_url: String,

    /// Embedding server base URL (OpenAI-compatible, should end with /v1)
    #[arg(long, env = "EMBEDDING_URL", default_value = "http://localhost:8001/v1")]
    embedding_url: String,

    /// Embedding model name
    #[arg(long, env = "EMBEDDING_MODEL", default_value = "NV-Embed-v2")]
    embedding_model: String,

    /// Output directory for harvested markdown stubs (kept for traceability)
    #[arg(long, env = "DARWIN_HARVEST_DIR", default_value = "~/knowledge/papers/harvested")]
    out_dir: String,

    /// Knowledge collection names
    #[arg(long, default_value = "darwin-papers")]
    papers_collection: String,
    #[arg(long, default_value = "darwin-docs")]
    docs_collection: String,
    #[arg(long, default_value = "darwin-books")]
    books_collection: String,

    /// Max results per query per backend
    #[arg(long, default_value_t = 10)]
    max_results: usize,

    /// Which backend(s) to query
    #[arg(long, value_enum, default_value_t = Backend::All)]
    backend: Backend,

    /// Optional topics file (YAML/TOML/JSON) with multiple queries/backends/tags
    #[arg(long, env = "DARWIN_HARVEST_TOPICS_FILE")]
    topics_file: Option<String>,

    /// Only run specific topic(s) from the topics file (repeatable)
    #[arg(long)]
    topic: Vec<String>,

    /// Extra tags to attach to all ingested papers
    #[arg(long)]
    tag: Vec<String>,

    /// RSS/Atom feed URLs (repeatable). URLs are mapped to known paper backends (arXiv/DOI).
    #[arg(long)]
    rss: Vec<String>,

    /// arXiv categories to harvest (repeatable), e.g. `cs.AI`, `q-bio.NC`
    #[arg(long)]
    arxiv_category: Vec<String>,

    /// Max bytes to download per RSS feed
    #[arg(long, default_value_t = 2_000_000)]
    max_bytes: usize,

    /// Optional Postgres URL to enable the ingestion ledger
    #[arg(long, env = "DARWIN_LEDGER_DATABASE_URL")]
    ledger_db_url: Option<String>,

    /// Force re-index even if ledger indicates content is unchanged
    #[arg(long)]
    force: bool,

    /// One or more search queries (repeatable)
    #[arg(long)]
    query: Vec<String>,
}

#[tokio::main]
async fn main() -> Result<()> {
    tracing_subscriber::fmt()
        .with_env_filter(tracing_subscriber::EnvFilter::from_default_env())
        .init();

    let args = Args::parse();

    let ledger = init_ledger(args.ledger_db_url.as_deref()).await?;
    let cfg = KnowledgeConfig {
        qdrant_url: args.qdrant_url.clone(),
        embedding_url: args.embedding_url.clone(),
        embedding_model: args.embedding_model.clone(),
        chunk_size: 1500,
        chunk_overlap: 200,
        papers_collection: args.papers_collection.clone(),
        docs_collection: args.docs_collection.clone(),
        books_collection: args.books_collection.clone(),
        max_file_size: 5_000_000,
        ledger,
        force_reindex: args.force,
    };

    let out_dir = expand_tilde(&args.out_dir);
    std::fs::create_dir_all(&out_dir)
        .with_context(|| format!("failed to create {}", out_dir.display()))?;

    let pubmed = PubMedClient::from_env();
    let arxiv = ArxivClient::new();
    let openalex = OpenAlexClient::from_env();
    let crossref = CrossrefClient::from_env();
    let europepmc = EuropePmcClient::new();

    let mut total_chunks = 0usize;
    let mut total_papers = 0usize;
    let mut seen_doc_ids: HashSet<String> = HashSet::new();

    let jobs = build_jobs(&args)?;
    if jobs.is_empty() && args.rss.is_empty() && args.arxiv_category.is_empty() {
        anyhow::bail!("No queries provided. Use --query ... or --topics-file <path> or --rss/--arxiv-category.");
    }

    for job in jobs {
        info!(
            topic = %job.topic,
            query = %job.query,
            backends = ?job.backends,
            max_results = job.max_results,
            "harvesting"
        );

        let search_query = SearchQuery::new(&job.query).with_max_results(job.max_results);

        for backend in expand_backends(&job.backends) {
            let result = match backend {
                Backend::Pubmed => pubmed.search(&search_query).await,
                Backend::Arxiv => arxiv.search(&search_query).await,
                Backend::Openalex => openalex.search(&search_query).await,
                Backend::Crossref => crossref.search(&search_query).await,
                Backend::Europepmc => europepmc.search(&search_query).await,
                Backend::All => unreachable!("expand_backends() removes All"),
            };

            let mut result = match result {
                Ok(r) => r,
                Err(e) => {
                    warn!(topic = %job.topic, backend = ?backend, query = %job.query, "search failed: {e}");
                    continue;
                }
            };

            for paper in result.papers.drain(..) {
                let doc_id = format!("{}:{}", paper.source, paper.id);
                if !seen_doc_ids.insert(doc_id) {
                    continue;
                }

                match ingest_paper_stub(&cfg, &out_dir, &job.tags, &job.query, &paper.source, &paper)
                    .await
                {
                    Ok(chunks) => {
                        total_papers += 1;
                        total_chunks += chunks;
                    }
                    Err(e) => warn!(id = %paper.id, source = %paper.source, "ingest failed: {e:#}"),
                }
            }
        }
    }

    // arXiv categories (recent by submittedDate)
    for cat in &args.arxiv_category {
        let cat = cat.trim();
        if cat.is_empty() {
            continue;
        }
        let q = format!("cat:{cat}");
        info!(category = %cat, query = %q, max_results = args.max_results, "harvesting arXiv category");
        let search_query = SearchQuery::new(&q).with_max_results(args.max_results);
        let result = match arxiv.search(&search_query).await {
            Ok(r) => r,
            Err(e) => {
                warn!(category = %cat, "arXiv category search failed: {e}");
                continue;
            }
        };

        for paper in result.papers {
            let doc_id = format!("{}:{}", paper.source, paper.id);
            if !seen_doc_ids.insert(doc_id) {
                continue;
            }

            let mut tags = args.tag.clone();
            if !tags.contains(&cat.to_string()) {
                tags.push(cat.to_string());
            }

            match ingest_paper_stub(&cfg, &out_dir, &tags, &q, &paper.source, &paper).await {
                Ok(chunks) => {
                    total_papers += 1;
                    total_chunks += chunks;
                }
                Err(e) => warn!(id = %paper.id, source = %paper.source, "ingest failed: {e:#}"),
            }
        }
    }

    // RSS/Atom feeds: extract links, map to arXiv IDs or DOIs, then fetch metadata.
    if !args.rss.is_empty() {
        let http = reqwest::Client::builder()
            .user_agent("BEAGLE darwin-research-harvester (+https://github.com/agourakis82/beagle)")
            .timeout(std::time::Duration::from_secs(60))
            .build()?;

        for feed_url in &args.rss {
            let feed_url = feed_url.trim();
            if feed_url.is_empty() {
                continue;
            }
            info!(feed = %feed_url, "harvesting RSS feed");

            let xml = match fetch_text(&http, feed_url, args.max_bytes).await {
                Ok(t) => t,
                Err(e) => {
                    warn!(feed = %feed_url, "feed download failed: {e:#}");
                    continue;
                }
            };

            let links = extract_feed_links(&xml);
            let mut per_feed = 0usize;
            for link in links {
                if per_feed >= args.max_results {
                    break;
                }

                let Some(resolved) = normalize_http_url(&link) else {
                    continue;
                };

                if let Some(arxiv_id) = arxiv_id_from_url(&resolved) {
                    match arxiv.fetch_paper(&arxiv_id).await {
                        Ok(paper) => {
                            let doc_id = format!("{}:{}", paper.source, paper.id);
                            if !seen_doc_ids.insert(doc_id) {
                                continue;
                            }
                            let mut tags = args.tag.clone();
                            if !tags.contains(&"rss".to_string()) {
                                tags.push("rss".to_string());
                            }
                            per_feed += 1;
                            match ingest_paper_stub(&cfg, &out_dir, &tags, feed_url, &paper.source, &paper).await {
                                Ok(chunks) => {
                                    total_papers += 1;
                                    total_chunks += chunks;
                                }
                                Err(e) => warn!(id = %paper.id, source = %paper.source, "ingest failed: {e:#}"),
                            }
                        }
                        Err(e) => warn!(id = %arxiv_id, "arXiv fetch failed: {e}"),
                    }
                    continue;
                }

                if let Some(doi) = doi_from_url(&resolved) {
                    match crossref.fetch_paper(&doi).await {
                        Ok(paper) => {
                            let doc_id = format!("{}:{}", paper.source, paper.id);
                            if !seen_doc_ids.insert(doc_id) {
                                continue;
                            }
                            let mut tags = args.tag.clone();
                            if !tags.contains(&"rss".to_string()) {
                                tags.push("rss".to_string());
                            }
                            per_feed += 1;
                            match ingest_paper_stub(&cfg, &out_dir, &tags, feed_url, &paper.source, &paper).await {
                                Ok(chunks) => {
                                    total_papers += 1;
                                    total_chunks += chunks;
                                }
                                Err(e) => warn!(id = %paper.id, source = %paper.source, "ingest failed: {e:#}"),
                            }
                        }
                        Err(e) => warn!(doi = %doi, "Crossref fetch failed: {e}"),
                    }
                }
            }
        }
    }

    info!(total_papers, total_chunks, "harvest complete");
    Ok(())
}

#[derive(Debug, Clone)]
struct HarvestJob {
    topic: String,
    query: String,
    max_results: usize,
    backends: Vec<Backend>,
    tags: Vec<String>,
}

#[derive(Debug, Deserialize)]
struct TopicsFile {
    topics: Vec<TopicConfig>,
}

#[derive(Debug, Deserialize)]
struct TopicConfig {
    name: String,
    #[serde(default = "default_true")]
    enabled: bool,
    #[serde(default)]
    backends: Vec<Backend>,
    #[serde(default)]
    max_results: Option<usize>,
    #[serde(default)]
    tags: Vec<String>,
    #[serde(default)]
    queries: Vec<String>,
}

fn default_true() -> bool {
    true
}

fn build_jobs(args: &Args) -> Result<Vec<HarvestJob>> {
    let mut jobs = Vec::new();

    // CLI queries (ad-hoc)
    for q in &args.query {
        jobs.push(HarvestJob {
            topic: "cli".to_string(),
            query: q.clone(),
            max_results: args.max_results,
            backends: vec![args.backend],
            tags: args.tag.clone(),
        });
    }

    // Topics file
    if let Some(ref topics_file) = args.topics_file {
        let path = expand_tilde(topics_file);
        let cfg = config::Config::builder()
            .add_source(config::File::from(path.clone()))
            .build()
            .with_context(|| format!("failed to load topics file {}", path.display()))?;
        let topics: TopicsFile = cfg
            .try_deserialize()
            .context("failed to deserialize topics file into TopicsFile")?;

        let topic_filter: HashSet<String> = args.topic.iter().cloned().collect();
        for topic in topics.topics {
            if !topic.enabled {
                continue;
            }
            if !topic_filter.is_empty() && !topic_filter.contains(&topic.name) {
                continue;
            }

            let max_results = topic.max_results.unwrap_or(args.max_results);
            let mut tags = args.tag.clone();
            for t in topic.tags {
                if !tags.contains(&t) {
                    tags.push(t);
                }
            }

            let backends = if topic.backends.is_empty() {
                vec![args.backend]
            } else {
                topic.backends
            };

            for q in topic.queries {
                if q.trim().is_empty() {
                    continue;
                }
                jobs.push(HarvestJob {
                    topic: topic.name.clone(),
                    query: q,
                    max_results,
                    backends: backends.clone(),
                    tags: tags.clone(),
                });
            }
        }
    }

    Ok(jobs)
}

fn expand_backends(backends: &[Backend]) -> Vec<Backend> {
    let mut expanded = Vec::new();
    for b in backends {
        match b {
            Backend::All => expanded.extend([
                Backend::Pubmed,
                Backend::Arxiv,
                Backend::Openalex,
                Backend::Crossref,
                Backend::Europepmc,
            ]),
            other => expanded.push(*other),
        }
    }

    // Stable ordering + dedup
    let mut uniq = Vec::new();
    for b in expanded {
        if !uniq.contains(&b) {
            uniq.push(b);
        }
    }
    uniq
}

async fn ingest_paper_stub(
    cfg: &KnowledgeConfig,
    out_dir: &Path,
    base_tags: &[String],
    query: &str,
    source: &str,
    paper: &beagle_search::Paper,
) -> Result<usize> {
    let doc_id = format!("{source}:{}", paper.id);
    let safe_id = sanitize_filename(&paper.id);
    let dir = out_dir.join(source);
    std::fs::create_dir_all(&dir)?;

    let path = dir.join(format!("{safe_id}.md"));
    let authors = if paper.authors.is_empty() {
        None
    } else {
        Some(
            paper.authors
                .iter()
                .map(|a| a.full_name())
                .collect::<Vec<_>>()
                .join(", "),
        )
    };
    let year = paper.published_date.map(|d| d.year());

    let mut tags = base_tags.to_vec();
    for cat in &paper.categories {
        if !tags.contains(cat) {
            tags.push(cat.clone());
        }
    }

    let body = render_paper_stub(paper);
    std::fs::write(&path, body)?;

    let meta = DocumentMeta {
        title: paper.title.clone(),
        path,
        doc_id: Some(doc_id),
        author: authors,
        year,
        doi: paper.doi.clone(),
        tags,
        source: Some(source.to_string()),
        license: None,
        extra: serde_json::json!({
            "paper_id": paper.id,
            "backend": paper.source,
            "url": paper.url,
            "pdf_url": paper.pdf_url,
            "journal": paper.journal,
            "citation": paper.citation(),
            "query": query,
            "published_date": paper.published_date.map(|d| d.to_rfc3339()),
            "citation_count": paper.citation_count,
        }),
    };

    index_document(cfg, DocType::Paper, meta).await
}

fn render_paper_stub(paper: &beagle_search::Paper) -> String {
    let authors = if paper.authors.is_empty() {
        "Unknown".to_string()
    } else {
        paper.authors
            .iter()
            .map(|a| a.full_name())
            .collect::<Vec<_>>()
            .join(", ")
    };

    let published = paper
        .published_date
        .map(|d| d.to_rfc3339())
        .unwrap_or_else(|| "unknown".to_string());

    format!(
        "# {title}\n\n\
Source: {source}\n\
ID: {id}\n\
Published: {published}\n\
Authors: {authors}\n\
DOI: {doi}\n\
URL: {url}\n\
PDF: {pdf}\n\n\
## Abstract\n\n{abstract}\n",
        title = paper.title,
        source = paper.source,
        id = paper.id,
        published = published,
        authors = authors,
        doi = paper.doi.clone().unwrap_or_else(|| "n/a".to_string()),
        url = paper.url.clone().unwrap_or_else(|| "n/a".to_string()),
        pdf = paper.pdf_url.clone().unwrap_or_else(|| "n/a".to_string()),
        abstract = if paper.abstract_text.trim().is_empty() {
            "n/a".to_string()
        } else {
            paper.abstract_text.clone()
        },
    )
}

fn sanitize_filename(input: &str) -> String {
    let mut out = String::with_capacity(input.len());
    for c in input.chars() {
        if c.is_ascii_alphanumeric() || matches!(c, '-' | '_' | '.') {
            out.push(c);
        } else {
            out.push('_');
        }
    }
    if out.is_empty() {
        "paper".to_string()
    } else {
        out
    }
}

fn expand_tilde(path: &str) -> PathBuf {
    if let Some(rest) = path.strip_prefix("~/") {
        if let Ok(home) = std::env::var("HOME") {
            return PathBuf::from(home).join(rest);
        }
    }
    PathBuf::from(path)
}

async fn fetch_text(client: &reqwest::Client, url: &str, max_bytes: usize) -> Result<String> {
    let parsed = reqwest::Url::parse(url).context("invalid URL")?;
    if parsed.scheme() != "http" && parsed.scheme() != "https" {
        anyhow::bail!("unsupported URL scheme: {}", parsed.scheme());
    }

    let resp = client.get(parsed).send().await?;
    let status = resp.status();
    if !status.is_success() {
        anyhow::bail!("HTTP {}", status);
    }

    if let Some(len) = resp
        .headers()
        .get(reqwest::header::CONTENT_LENGTH)
        .and_then(|v| v.to_str().ok())
        .and_then(|s| s.parse::<usize>().ok())
    {
        if len > max_bytes {
            anyhow::bail!("content-length {} exceeds max-bytes {}", len, max_bytes);
        }
    }

    let bytes = resp.bytes().await?;
    if bytes.len() > max_bytes {
        anyhow::bail!("downloaded {} bytes exceeds max-bytes {}", bytes.len(), max_bytes);
    }

    Ok(String::from_utf8_lossy(&bytes).to_string())
}

fn extract_feed_links(xml: &str) -> Vec<String> {
    // RSS: <link>https://...</link>
    // Atom: <link href="https://..." .../>
    let mut out = Vec::new();

    if let Ok(re) = Regex::new(r#"(?is)<link[^>]*href=["']([^"']+)["'][^>]*/?>"#) {
        for cap in re.captures_iter(xml).take(50_000) {
            if let Some(u) = cap.get(1).map(|m| m.as_str().trim()) {
                out.push(u.to_string());
            }
        }
    }

    if let Ok(re) = Regex::new(r"(?is)<link>([^<]+)</link>") {
        for cap in re.captures_iter(xml).take(50_000) {
            if let Some(u) = cap.get(1).map(|m| m.as_str().trim()) {
                out.push(u.to_string());
            }
        }
    }

    // Dedup stable order
    let mut seen = HashSet::new();
    let mut uniq = Vec::new();
    for u in out {
        let u = u.trim();
        if u.is_empty() {
            continue;
        }
        if seen.insert(u.to_string()) {
            uniq.push(u.to_string());
        }
    }
    uniq
}

fn normalize_http_url(raw: &str) -> Option<String> {
    let s = raw.trim();
    if !s.starts_with("http://") && !s.starts_with("https://") {
        return None;
    }
    let mut url = reqwest::Url::parse(s).ok()?;
    url.set_fragment(None);
    Some(url.to_string())
}

fn arxiv_id_from_url(url: &str) -> Option<String> {
    let u = reqwest::Url::parse(url).ok()?;
    let host = u.host_str()?.to_lowercase();
    if !host.contains("arxiv.org") {
        return None;
    }

    let path = u.path().trim_matches('/');
    let id = if let Some(rest) = path.strip_prefix("abs/") {
        rest
    } else if let Some(rest) = path.strip_prefix("pdf/") {
        rest.trim_end_matches(".pdf")
    } else {
        return None;
    };

    let id = id.trim();
    if id.is_empty() {
        None
    } else {
        Some(id.to_string())
    }
}

fn doi_from_url(url: &str) -> Option<String> {
    let u = reqwest::Url::parse(url).ok()?;
    let host = u.host_str()?.to_lowercase();
    if !(host == "doi.org" || host.ends_with(".doi.org") || host.contains("doi.org")) {
        return None;
    }
    let doi = u.path().trim_start_matches('/').trim();
    if doi.is_empty() {
        None
    } else {
        Some(doi.to_string())
    }
}

async fn init_ledger(db_url: Option<&str>) -> Result<Option<IngestionLedger>> {
    let Some(db_url) = db_url else {
        return Ok(None);
    };
    let ledger = IngestionLedger::connect(db_url).await?;
    ledger.ensure_schema().await?;
    Ok(Some(ledger))
}
