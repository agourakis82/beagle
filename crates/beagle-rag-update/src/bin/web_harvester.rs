use anyhow::{Context, Result};
use beagle_rag_update::eval_harness::{run_eval, EvalGateConfig};
use beagle_rag_update::ledger::IngestionLedger;
use beagle_rag_update::knowledge::{index_document, DocType, DocumentMeta, KnowledgeConfig};
use clap::Parser;
use chrono::Datelike;
use quick_xml::events::Event as XmlEvent;
use quick_xml::Reader as XmlReader;
use serde::Deserialize;
use scraper::{Html, Selector};
use regex::Regex;
use std::collections::{HashMap, HashSet, VecDeque};
use std::io::Read;
use std::path::{Path, PathBuf};
use std::sync::Arc;
use tokio::sync::{Mutex, Semaphore};
use tokio::task::JoinSet;
use tokio::time::{Duration, Instant};
use tracing::{info, warn};

#[derive(Debug, Parser)]
#[command(name = "darwin-web-harvester")]
#[command(
    about = "Fetch web pages and index extracted text into Qdrant (darwin-docs)",
    long_about = None
)]
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
    #[arg(long, env = "DARWIN_WEB_HARVEST_DIR", default_value = "~/knowledge/docs/harvested")]
    out_dir: String,

    /// Knowledge collection names
    #[arg(long, default_value = "darwin-papers")]
    papers_collection: String,
    #[arg(long, default_value = "darwin-docs")]
    docs_collection: String,
    #[arg(long, default_value = "darwin-books")]
    books_collection: String,

    /// Max bytes to download per URL
    #[arg(long, default_value_t = 2_000_000)]
    max_bytes: usize,

    /// Global concurrency for fetch+index tasks
    #[arg(long, env = "DARWIN_WEB_CONCURRENCY", default_value_t = 4)]
    concurrency: usize,

    /// Max concurrent requests per host (helps avoid hammering a single docs site)
    #[arg(long, env = "DARWIN_WEB_PER_HOST_CONCURRENCY", default_value_t = 2)]
    per_host_concurrency: usize,

    /// Politeness delay (ms) between requests to the same host (best-effort; use per-host-concurrency=1 for strict)
    #[arg(long, env = "DARWIN_WEB_HOST_DELAY_MS", default_value_t = 0)]
    host_delay_ms: u64,

    /// Max discovered links to enqueue per page (HTML only)
    #[arg(long, env = "DARWIN_WEB_MAX_LINKS", default_value_t = 500)]
    max_links: usize,

    /// Optional allow-list for hosts (repeatable)
    #[arg(long)]
    allow_host: Vec<String>,

    /// Optional allow-list for hosts (comma-separated)
    #[arg(long, env = "DARWIN_WEB_ALLOW_HOSTS")]
    allow_hosts: Option<String>,

    /// Optional deny-list for hosts (repeatable)
    #[arg(long)]
    deny_host: Vec<String>,

    /// Optional deny-list for hosts (comma-separated)
    #[arg(long, env = "DARWIN_WEB_DENY_HOSTS")]
    deny_hosts: Option<String>,

    /// Optional allow-list for URL path regexes (repeatable), e.g. `^/docs/`
    #[arg(long)]
    allow_path_regex: Vec<String>,

    /// Optional allow-list for URL path regexes (comma-separated)
    #[arg(long, env = "DARWIN_WEB_ALLOW_PATH_REGEX")]
    allow_path_regex_csv: Option<String>,

    /// Optional deny-list for URL path regexes (repeatable), e.g. `^/blog/`
    #[arg(long)]
    deny_path_regex: Vec<String>,

    /// Optional deny-list for URL path regexes (comma-separated)
    #[arg(long, env = "DARWIN_WEB_DENY_PATH_REGEX")]
    deny_path_regex_csv: Option<String>,

    /// Ignore robots.txt (default: false)
    #[arg(long, env = "DARWIN_WEB_IGNORE_ROBOTS", default_value_t = false)]
    ignore_robots: bool,

    /// If robots.txt cannot be fetched/parsed, skip crawling that host (fail closed).
    #[arg(long, env = "DARWIN_WEB_ROBOTS_FAIL_CLOSED", default_value_t = false)]
    robots_fail_closed: bool,

    /// User-agent used for robots.txt rules (defaults to the HTTP user-agent)
    #[arg(long, env = "DARWIN_WEB_ROBOTS_UA", default_value = "BEAGLE darwin-web-harvester")]
    robots_user_agent: String,

    /// Allow crawling outside the seed host (default: false)
    #[arg(long, env = "DARWIN_WEB_ALLOW_CROSS_HOST", default_value_t = false)]
    allow_cross_host: bool,

    /// Crawl depth (0 = only the provided URLs)
    #[arg(long, env = "DARWIN_WEB_CRAWL_DEPTH", default_value_t = 0)]
    crawl_depth: usize,

    /// Max URLs to fetch across all sources (seeds + discovered)
    #[arg(long, env = "DARWIN_WEB_MAX_URLS", default_value_t = 50)]
    max_urls: usize,

    /// RSS/Atom feed URLs to expand into page URLs (repeatable)
    #[arg(long)]
    rss: Vec<String>,

    /// Sitemap URLs to expand into page URLs (repeatable)
    #[arg(long)]
    sitemap: Vec<String>,

    /// Optional sources file (YAML/TOML/JSON) with multiple URL/RSS/sitemap sources + tags
    #[arg(long, env = "DARWIN_WEB_SOURCES_FILE")]
    sources_file: Option<String>,

    /// Only run specific source(s) from the sources file (repeatable)
    #[arg(long)]
    source: Vec<String>,

    /// Extra tags to attach to all ingested docs
    #[arg(long)]
    tag: Vec<String>,

    /// Optional license string to attach to ingested docs (e.g. CC-BY-4.0)
    #[arg(long, env = "DARWIN_WEB_LICENSE")]
    license: Option<String>,

    /// Optional Postgres URL to enable the ingestion ledger
    #[arg(long, env = "DARWIN_LEDGER_DATABASE_URL")]
    ledger_db_url: Option<String>,

    /// Force re-index even if ledger indicates content is unchanged
    #[arg(long)]
    force: bool,

    /// Run eval gates after harvesting (darwin-eval) and fail if retrieval quality regressed.
    #[arg(long, env = "DARWIN_WEB_EVAL_AFTER", default_value_t = false)]
    eval_after: bool,

    /// Path to eval file (YAML/TOML/JSON)
    #[arg(long, env = "DARWIN_EVAL_FILE", default_value = "scripts/darwin-eval.yaml")]
    eval_file: String,

    /// Default top-k per query (can be overridden in the eval file)
    #[arg(long, default_value_t = 10)]
    eval_k: usize,

    /// Append eval runs to this JSONL file for trend tracking.
    #[arg(long, env = "DARWIN_EVAL_HISTORY_FILE", default_value = "~/.darwin_eval_history.jsonl")]
    eval_history_file: String,

    /// Fail if MRR is below this value.
    #[arg(long, env = "DARWIN_EVAL_MIN_MRR")]
    eval_min_mrr: Option<f64>,

    /// Fail if MRR dropped by more than this value vs the previous run in the history file.
    #[arg(long, env = "DARWIN_EVAL_MAX_MRR_DROP")]
    eval_max_mrr_drop: Option<f64>,

    /// Fail if recall@k is below this value.
    #[arg(long, env = "DARWIN_EVAL_MIN_RECALL")]
    eval_min_recall: Option<f64>,

    /// Fail if recall@k dropped by more than this value vs the previous run in the history file.
    #[arg(long, env = "DARWIN_EVAL_MAX_RECALL_DROP")]
    eval_max_recall_drop: Option<f64>,

    /// One or more URLs to fetch (repeatable). If omitted, use --rss/--sitemap.
    #[arg(long)]
    url: Vec<String>,
}

#[derive(Debug)]
struct HostThrottle {
    sem: Semaphore,
    last_request: Mutex<Option<Instant>>,
}

impl HostThrottle {
    fn new(concurrency: usize) -> Self {
        Self {
            sem: Semaphore::new(concurrency.max(1)),
            last_request: Mutex::new(None),
        }
    }

    async fn wait_politeness(&self, delay: Duration) {
        if delay.is_zero() {
            return;
        }

        let now = Instant::now();
        let sleep_for = {
            let last = self.last_request.lock().await;
            match *last {
                Some(prev) => delay.saturating_sub(now.saturating_duration_since(prev)),
                None => Duration::from_millis(0),
            }
        };

        if !sleep_for.is_zero() {
            tokio::time::sleep(sleep_for).await;
        }

        let mut last = self.last_request.lock().await;
        *last = Some(Instant::now());
    }
}

#[derive(Debug)]
enum WorkOutcome {
    Ingested {
        chunks: usize,
        discovered_links: Vec<reqwest::Url>,
        depth: usize,
        seed_host: Option<String>,
        url: reqwest::Url,
        tags: Vec<String>,
    },
    Skipped {
        url: reqwest::Url,
        reason: String,
    },
    Failed {
        url: reqwest::Url,
        error: String,
    },
}

#[derive(Debug, Clone)]
struct QueueItem {
    url: reqwest::Url,
    depth: usize,
    seed_host: Option<String>,
    tags: Vec<String>,
}

#[derive(Debug, Clone)]
struct SeedUrl {
    url: String,
    tags: Vec<String>,
}

#[derive(Debug, Deserialize)]
struct SourcesFile {
    #[serde(default)]
    sources: Vec<WebSource>,
}

#[derive(Debug, Deserialize)]
struct WebSource {
    name: String,
    #[serde(default = "default_true")]
    enabled: bool,
    #[serde(default)]
    tags: Vec<String>,
    #[serde(default)]
    urls: Vec<String>,
    #[serde(default)]
    rss: Vec<String>,
    #[serde(default)]
    sitemaps: Vec<String>,
}

fn default_true() -> bool {
    true
}

#[tokio::main]
async fn main() -> Result<()> {
    tracing_subscriber::fmt()
        .with_env_filter(tracing_subscriber::EnvFilter::from_default_env())
        .init();

    let args = Args::parse();

    if args.url.is_empty()
        && args.rss.is_empty()
        && args.sitemap.is_empty()
        && args.sources_file.is_none()
    {
        anyhow::bail!("provide at least one --url, --rss, --sitemap, or --sources-file");
    }

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
        max_file_size: args.max_bytes as u64,
        ledger,
        force_reindex: args.force,
        metadata_enricher: None,
    };

    let out_dir = expand_tilde(&args.out_dir);
    std::fs::create_dir_all(&out_dir)
        .with_context(|| format!("failed to create {}", out_dir.display()))?;

    let allowlist = build_allowlist(&args);
    let denylist = build_denylist(&args);
    let allow_paths = build_path_regexes(&args.allow_path_regex, &args.allow_path_regex_csv)?;
    let deny_paths = build_path_regexes(&args.deny_path_regex, &args.deny_path_regex_csv)?;
    let concurrency = args.concurrency.max(1);
    let per_host_concurrency = args.per_host_concurrency.max(1);
    let host_delay = Duration::from_millis(args.host_delay_ms);
    let client = reqwest::Client::builder()
        .user_agent("BEAGLE darwin-web-harvester (+https://github.com/agourakis82/beagle)")
        .build()?;

    let mut total_docs = 0usize;
    let mut total_chunks = 0usize;

    let mut queue: VecDeque<QueueItem> = VecDeque::new();
    let mut seen: HashSet<String> = HashSet::new();

    let robots_cache: Arc<Mutex<HashMap<String, RobotsRules>>> = Arc::new(Mutex::new(HashMap::new()));
    let host_throttles: Arc<Mutex<HashMap<String, Arc<HostThrottle>>>> = Arc::new(Mutex::new(HashMap::new()));
    let global_sem: Arc<Semaphore> = Arc::new(Semaphore::new(concurrency));
    let mut joinset: JoinSet<WorkOutcome> = JoinSet::new();

    let seeds = expand_sources(&client, &args).await?;
    if seeds.is_empty() {
        anyhow::bail!("no seed URLs produced (check --sources-file/--source filters)");
    }
    for seed in seeds {
        if let Ok(u) = reqwest::Url::parse(&seed.url) {
            queue.push_back(QueueItem {
                url: u,
                depth: 0,
                seed_host: None,
                tags: seed.tags,
            });
        } else {
            warn!(url = %seed.url, "invalid seed URL (skipping)");
        }
    }

    while total_docs < args.max_urls && (!queue.is_empty() || joinset.len() > 0) {
        while total_docs < args.max_urls && joinset.len() < concurrency {
            let Some(item) = queue.pop_front() else { break };
            let QueueItem {
                url,
                depth,
                seed_host,
                tags,
            } = item;

            let normalized = normalize_url(&url);
            if !seen.insert(normalized.clone()) {
                continue;
            }

            let host = url.host_str().unwrap_or("unknown").to_lowercase();
            if !is_host_allowed(&host, &allowlist, &denylist) {
                continue;
            }

            if !is_path_allowed(url.path(), &allow_paths, &deny_paths) {
                continue;
            }

            if !args.allow_cross_host {
                if let Some(seed_host) = seed_host.as_ref() {
                    if seed_host != &host {
                        continue;
                    }
                }
            }

            let seed_host = seed_host.or_else(|| Some(host.clone()));

            let client = client.clone();
            let cfg = cfg.clone();
            let out_dir = out_dir.clone();
            let base_tags = tags;
            let license = args.license.clone();
            let max_bytes = args.max_bytes;
            let max_links = args.max_links;
            let ignore_robots = args.ignore_robots;
            let robots_fail_closed = args.robots_fail_closed;
            let robots_ua = args.robots_user_agent.clone();
            let robots_cache = robots_cache.clone();
            let host_throttles = host_throttles.clone();
            let global_sem = global_sem.clone();
            joinset.spawn(async move {
                // Global concurrency permit.
                let _permit = match global_sem.acquire().await {
                    Ok(p) => p,
                    Err(_) => {
                        return WorkOutcome::Failed {
                            url,
                            error: "global semaphore closed".to_string(),
                        };
                    }
                };

                let throttle = {
                    let mut map = host_throttles.lock().await;
                    map.entry(host.clone())
                        .or_insert_with(|| Arc::new(HostThrottle::new(per_host_concurrency)))
                        .clone()
                };
                let _host_permit = match throttle.sem.acquire().await {
                    Ok(p) => p,
                    Err(_) => {
                        return WorkOutcome::Failed {
                            url,
                            error: "host semaphore closed".to_string(),
                        };
                    }
                };
                throttle.wait_politeness(host_delay).await;

                if !ignore_robots {
                    let cached = { robots_cache.lock().await.get(&host).cloned() };
                    let rules = match cached {
                        Some(r) => r,
                        None => match fetch_robots_rules(&client, &url, &robots_ua).await {
                            Ok(rules) => {
                                robots_cache.lock().await.insert(host.clone(), rules.clone());
                                rules
                            }
                            Err(e) => {
                                if robots_fail_closed {
                                    warn!(host = %host, "robots.txt check failed (skipping host): {e:#}");
                                    let rules = RobotsRules {
                                        allow: vec![],
                                        disallow: vec!["/".to_string()],
                                    };
                                    robots_cache.lock().await.insert(host.clone(), rules.clone());
                                    rules
                                } else {
                                    warn!(host = %host, "robots.txt check failed (proceeding): {e:#}");
                                    RobotsRules {
                                        allow: vec!["/".to_string()],
                                        disallow: vec![],
                                    }
                                }
                            }
                        },
                    };

                    if !rules.allows(url.path()) {
                        return WorkOutcome::Skipped {
                            url,
                            reason: "robots.txt disallows path".to_string(),
                        };
                    }
                }

                match fetch_extract_index(
                    &client,
                    &cfg,
                    &out_dir,
                    &base_tags,
                    license.as_deref(),
                    max_bytes,
                    max_links,
                    &url,
                )
                .await
                {
                    Ok(result) => WorkOutcome::Ingested {
                        chunks: result.chunks,
                        discovered_links: result.discovered_links,
                        depth,
                        seed_host,
                        url,
                        tags: base_tags,
                    },
                    Err(e) => WorkOutcome::Failed {
                        url,
                        error: format!("{e:#}"),
                    },
                }
            });
        }

        match joinset.join_next().await {
            Some(Ok(outcome)) => match outcome {
                WorkOutcome::Ingested {
                    chunks,
                    discovered_links,
                    depth,
                    seed_host,
                    url,
                    tags,
                } => {
                    total_docs += 1;
                    total_chunks += chunks;

                    if depth < args.crawl_depth {
                        let host = url.host_str().unwrap_or("unknown").to_lowercase();
                        for next in discovered_links {
                            let next_host = next.host_str().unwrap_or("unknown").to_lowercase();
                            if !args.allow_cross_host && next_host != host {
                                continue;
                            }
                            queue.push_back(QueueItem {
                                url: next,
                                depth: depth + 1,
                                seed_host: seed_host.clone(),
                                tags: tags.clone(),
                            });
                        }
                    }
                }
                WorkOutcome::Skipped { url, reason } => {
                    warn!(url = %url, "{reason} (skipping)");
                }
                WorkOutcome::Failed { url, error } => {
                    warn!(url = %url, "ingest failed: {error}");
                }
            },
            Some(Err(e)) => warn!("worker task failed: {e:#}"),
            None => break,
        }
    }

    info!(total_docs, total_chunks, "web harvest complete");

    if args.eval_after {
        info!("running post-harvest eval gates");
        let _record = run_eval(EvalGateConfig {
            qdrant_url: args.qdrant_url,
            embedding_url: args.embedding_url,
            embedding_model: args.embedding_model,
            eval_file: args.eval_file,
            k: args.eval_k,
            history_file: args.eval_history_file,
            min_mrr: args.eval_min_mrr,
            max_mrr_drop: args.eval_max_mrr_drop,
            min_recall: args.eval_min_recall,
            max_recall_drop: args.eval_max_recall_drop,
        })
        .await?;
    }

    Ok(())
}

#[derive(Debug, Clone)]
enum HostPattern {
    Exact(String),
    Suffix(String),
}

fn parse_host_pattern(s: &str) -> Option<HostPattern> {
    let raw = s.trim().trim_end_matches('.').to_lowercase();
    if raw.is_empty() {
        return None;
    }
    if let Some(rest) = raw.strip_prefix("*.") {
        let rest = rest.trim().to_string();
        if rest.is_empty() {
            return None;
        }
        return Some(HostPattern::Suffix(rest));
    }
    if let Some(rest) = raw.strip_prefix('.') {
        let rest = rest.trim().to_string();
        if rest.is_empty() {
            return None;
        }
        return Some(HostPattern::Suffix(rest));
    }
    Some(HostPattern::Exact(raw))
}

fn host_matches(host: &str, pattern: &HostPattern) -> bool {
    match pattern {
        HostPattern::Exact(p) => host == p,
        HostPattern::Suffix(base) => host == base || host.ends_with(&format!(".{base}")),
    }
}

fn build_allowlist(args: &Args) -> Vec<HostPattern> {
    let mut hosts: Vec<HostPattern> = Vec::new();
    for h in &args.allow_host {
        if let Some(p) = parse_host_pattern(h) {
            hosts.push(p);
        }
    }
    if let Some(ref h) = args.allow_hosts {
        for part in h.split(',') {
            if let Some(p) = parse_host_pattern(part) {
                hosts.push(p);
            }
        }
    }
    hosts
}

fn build_denylist(args: &Args) -> Vec<HostPattern> {
    let mut hosts: Vec<HostPattern> = Vec::new();
    for h in &args.deny_host {
        if let Some(p) = parse_host_pattern(h) {
            hosts.push(p);
        }
    }
    if let Some(ref h) = args.deny_hosts {
        for part in h.split(',') {
            if let Some(p) = parse_host_pattern(part) {
                hosts.push(p);
            }
        }
    }
    hosts
}

fn is_host_allowed(host: &str, allow: &[HostPattern], deny: &[HostPattern]) -> bool {
    if deny.iter().any(|p| host_matches(host, p)) {
        return false;
    }
    if !allow.is_empty() && !allow.iter().any(|p| host_matches(host, p)) {
        return false;
    }
    true
}

fn build_path_regexes(cli: &[String], csv: &Option<String>) -> Result<Vec<Regex>> {
    let mut patterns: Vec<String> = Vec::new();
    for p in cli {
        let p = p.trim();
        if !p.is_empty() {
            patterns.push(p.to_string());
        }
    }
    if let Some(csv) = csv.as_deref() {
        for p in csv.split(',') {
            let p = p.trim();
            if !p.is_empty() {
                patterns.push(p.to_string());
            }
        }
    }

    let mut out = Vec::with_capacity(patterns.len());
    for pattern in patterns {
        let re = Regex::new(&pattern)
            .with_context(|| format!("invalid URL path regex `{pattern}`"))?;
        out.push(re);
    }
    Ok(out)
}

fn is_path_allowed(path: &str, allow: &[Regex], deny: &[Regex]) -> bool {
    let path = if path.is_empty() { "/" } else { path };
    if deny.iter().any(|re| re.is_match(path)) {
        return false;
    }
    if !allow.is_empty() && !allow.iter().any(|re| re.is_match(path)) {
        return false;
    }
    true
}

async fn expand_sources(client: &reqwest::Client, args: &Args) -> Result<Vec<SeedUrl>> {
    let mut seeds: Vec<SeedUrl> = Vec::new();

    // CLI sources
    for u in &args.url {
        seeds.push(SeedUrl {
            url: u.clone(),
            tags: args.tag.clone(),
        });
    }

    for feed in &args.rss {
        let bytes = fetch_xml_bytes(client, feed, args.max_bytes).await?;
        let xml = String::from_utf8_lossy(&bytes).to_string();
        for link in extract_feed_links(&xml) {
            seeds.push(SeedUrl {
                url: link,
                tags: args.tag.clone(),
            });
        }
    }

    for sm in &args.sitemap {
        let urls = expand_sitemap(client, sm, args.max_bytes, args.max_urls).await?;
        for link in urls {
            seeds.push(SeedUrl {
                url: link,
                tags: args.tag.clone(),
            });
        }
    }

    // Sources file
    if let Some(ref sources_file) = args.sources_file {
        let path = expand_tilde(sources_file);
        let cfg = config::Config::builder()
            .add_source(config::File::from(path.clone()))
            .build()
            .with_context(|| format!("failed to load sources file {}", path.display()))?;
        let sources: SourcesFile = cfg
            .try_deserialize()
            .context("failed to deserialize sources file into SourcesFile")?;

        let filter: HashSet<String> = args.source.iter().cloned().collect();
        for source in sources.sources {
            if !source.enabled {
                continue;
            }
            if !filter.is_empty() && !filter.contains(&source.name) {
                continue;
            }

            let mut tags = args.tag.clone();
            extend_tags(&mut tags, &source.tags);
            if !tags.iter().any(|t| t.eq_ignore_ascii_case(&format!("source:{}", source.name))) {
                tags.push(format!("source:{}", source.name));
            }

            for u in source.urls {
                seeds.push(SeedUrl {
                    url: u,
                    tags: tags.clone(),
                });
            }

            for feed in source.rss {
                let bytes = fetch_xml_bytes(client, &feed, args.max_bytes).await?;
                let xml = String::from_utf8_lossy(&bytes).to_string();
                for link in extract_feed_links(&xml) {
                    seeds.push(SeedUrl {
                        url: link,
                        tags: tags.clone(),
                    });
                }
            }

            for sm in source.sitemaps {
                let urls = expand_sitemap(client, &sm, args.max_bytes, args.max_urls).await?;
                for link in urls {
                    seeds.push(SeedUrl {
                        url: link,
                        tags: tags.clone(),
                    });
                }
            }
        }
    }

    // Dedup + merge tags, stable order.
    let max_seeds = args.max_urls.saturating_mul(20).max(args.max_urls);
    let mut order: Vec<String> = Vec::new();
    let mut merged: HashMap<String, Vec<String>> = HashMap::new();

    for seed in seeds {
        let trimmed = seed.url.trim();
        if trimmed.is_empty() {
            continue;
        }
        let entry = merged.entry(trimmed.to_string()).or_insert_with(|| {
            order.push(trimmed.to_string());
            Vec::new()
        });
        extend_tags(entry, &seed.tags);
    }

    let mut out = Vec::new();
    for u in order {
        if out.len() >= max_seeds {
            break;
        }
        out.push(SeedUrl {
            url: u.clone(),
            tags: merged.remove(&u).unwrap_or_default(),
        });
    }

    Ok(out)
}

async fn fetch_bytes(
    client: &reqwest::Client,
    url: &str,
    max_bytes: usize,
) -> Result<(Vec<u8>, Option<String>)> {
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

    let content_type = resp
        .headers()
        .get(reqwest::header::CONTENT_TYPE)
        .and_then(|v| v.to_str().ok())
        .map(|s| s.to_string());

    let bytes = resp.bytes().await?;
    if bytes.len() > max_bytes {
        anyhow::bail!("downloaded {} bytes exceeds max-bytes {}", bytes.len(), max_bytes);
    }

    Ok((bytes.to_vec(), content_type))
}

async fn fetch_xml_bytes(client: &reqwest::Client, url: &str, max_bytes: usize) -> Result<Vec<u8>> {
    let (bytes, content_type) = fetch_bytes(client, url, max_bytes).await?;
    let ct = content_type.unwrap_or_default().to_lowercase();
    let needs_gunzip = url.to_lowercase().ends_with(".gz")
        || ct.contains("gzip")
        || bytes.starts_with(&[0x1f, 0x8b]);
    if !needs_gunzip {
        return Ok(bytes);
    }
    gunzip(&bytes)
}

fn gunzip(bytes: &[u8]) -> Result<Vec<u8>> {
    let mut decoder = flate2::read::GzDecoder::new(bytes);
    let mut out = Vec::new();
    decoder
        .read_to_end(&mut out)
        .context("failed to gunzip content")?;
    Ok(out)
}

async fn expand_sitemap(
    client: &reqwest::Client,
    sitemap_url: &str,
    max_bytes: usize,
    max_urls: usize,
) -> Result<Vec<String>> {
    let mut urls = Vec::new();
    let mut queue: VecDeque<String> = VecDeque::new();
    let mut seen: HashSet<String> = HashSet::new();

    queue.push_back(sitemap_url.to_string());

    while let Some(sm) = queue.pop_front() {
        if !seen.insert(sm.clone()) {
            continue;
        }
        if seen.len() > 200 {
            break;
        }

        let bytes = fetch_xml_bytes(client, &sm, max_bytes).await?;
        let xml = String::from_utf8_lossy(&bytes).to_string();
        let xml_lower = xml.to_lowercase();

        let locs = extract_sitemap_locs(&xml);
        if xml_lower.contains("<sitemapindex") {
            for loc in locs {
                if loc.starts_with("http://") || loc.starts_with("https://") {
                    queue.push_back(loc);
                }
            }
        } else {
            urls.extend(locs);
            // Keep seed list bounded (we only fetch up to --max-urls anyway).
            if urls.len() >= max_urls.saturating_mul(20).max(max_urls) {
                break;
            }
        }
    }

    Ok(urls)
}

struct FetchIndexResult {
    chunks: usize,
    discovered_links: Vec<reqwest::Url>,
}

async fn fetch_extract_index(
    client: &reqwest::Client,
    cfg: &KnowledgeConfig,
    out_dir: &Path,
    base_tags: &[String],
    license: Option<&str>,
    max_bytes: usize,
    max_links: usize,
    url: &reqwest::Url,
) -> Result<FetchIndexResult> {
    if url.scheme() != "http" && url.scheme() != "https" {
        anyhow::bail!("unsupported URL scheme: {}", url.scheme());
    }

    let host = url.host_str().unwrap_or("unknown").to_lowercase();

    let resp = client.get(url.clone()).send().await?;
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

    let content_type = resp
        .headers()
        .get(reqwest::header::CONTENT_TYPE)
        .and_then(|v| v.to_str().ok())
        .unwrap_or("unknown")
        .to_string();

    let final_url = resp.url().clone();
    let bytes = resp.bytes().await?;
    if bytes.len() > max_bytes {
        anyhow::bail!("downloaded {} bytes exceeds max-bytes {}", bytes.len(), max_bytes);
    }

    let doc_is_pdf = is_pdf_like(&final_url, &content_type, &bytes);
    let raw = if doc_is_pdf {
        String::new()
    } else {
        String::from_utf8_lossy(&bytes).to_string()
    };

    let canonical_url = if is_html_like(&content_type) {
        extract_canonical_url(&final_url, &raw)
    } else {
        None
    };

    let doc_url = canonical_url.clone().unwrap_or_else(|| final_url.clone());
    let doc_id = normalize_url(&doc_url);
    let safe_id = blake3::hash(doc_id.as_bytes()).to_hex().to_string();
    let dir = out_dir.join(&host);
    std::fs::create_dir_all(&dir)?;
    let md_path = dir.join(format!("{safe_id}.md"));
    let bin_path = if doc_is_pdf {
        Some(dir.join(format!("{safe_id}.pdf")))
    } else {
        None
    };

    let now = chrono::Utc::now();
    let title = if doc_is_pdf {
        derive_title_from_url(&doc_url)
    } else {
        extract_title_html(&raw).unwrap_or_else(|| derive_title_from_url(&doc_url))
    };

    let extracted = if doc_is_pdf {
        String::new()
    } else {
        extract_text(&raw, &content_type)
    };

    // Always write a Markdown stub for traceability, even when the indexed payload is a PDF.
    let body = if doc_is_pdf {
        format!(
            "# {title}\n\nURL: {url}\nContent-Type: {ct}\n\n## Notes\n\nDownloaded PDF (content extracted via `pdftotext` during indexing).\n",
            title = title,
            url = doc_id,
            ct = content_type,
        )
    } else {
        let canonical_line = canonical_url
            .as_ref()
            .map(|u| format!("Canonical: {u}\n"))
            .unwrap_or_default();
        format!(
            "# {title}\n\nURL: {url}\n{canonical}Content-Type: {ct}\n\n## Content\n\n{content}\n",
            title = title,
            url = doc_id,
            canonical = canonical_line,
            ct = content_type,
            content = extracted
        )
    };
    std::fs::write(&md_path, body)?;

    if let Some(ref bin_path) = bin_path {
        std::fs::write(bin_path, &bytes)?;
    }

    let mut tags = base_tags.to_vec();
    if !tags.contains(&host) {
        tags.push(host.clone());
    }

    if doc_is_pdf && !tags.iter().any(|t| t.eq_ignore_ascii_case("pdf")) {
        tags.push("pdf".to_string());
    }

    let meta = DocumentMeta {
        title: title.clone(),
        path: bin_path.clone().unwrap_or_else(|| md_path.clone()),
        doc_id: Some(doc_id.clone()),
        author: None,
        year: Some(now.year() as i32),
        doi: None,
        tags,
        source: Some("web".to_string()),
        license: license.map(|s| s.to_string()),
        extra: serde_json::json!({
            "doc_url": doc_id,
            "final_url": final_url.to_string(),
            "canonical_url": canonical_url.as_ref().map(|u| u.to_string()),
            "host": host,
            "content_type": content_type,
            "fetched_at": now.to_rfc3339(),
            "stub_path": md_path.to_string_lossy().to_string(),
            "download_path": bin_path.as_ref().map(|p| p.to_string_lossy().to_string()),
        }),
    };

    let chunks = index_document(cfg, DocType::Doc, meta).await?;

    let discovered_links = if !doc_is_pdf && is_html_like(&content_type) {
        extract_links(&final_url, &raw, max_links)
    } else {
        Vec::new()
    };

    Ok(FetchIndexResult {
        chunks,
        discovered_links,
    })
}

fn is_html_like(content_type: &str) -> bool {
    let ct = content_type.to_lowercase();
    ct.contains("text/html") || ct.contains("application/xhtml+xml")
}

fn is_pdf_like(url: &reqwest::Url, content_type: &str, bytes: &[u8]) -> bool {
    let ct = content_type.to_lowercase();
    if ct.contains("application/pdf") {
        return true;
    }
    if url
        .path()
        .to_lowercase()
        .split('?')
        .next()
        .unwrap_or("")
        .ends_with(".pdf")
    {
        return true;
    }
    bytes.starts_with(b"%PDF")
}

fn extract_title_html(raw_html: &str) -> Option<String> {
    let doc = Html::parse_document(raw_html);

    let meta_sel = Selector::parse(r#"meta[property="og:title"], meta[name="twitter:title"]"#)
        .ok()?;
    for el in doc.select(&meta_sel) {
        if let Some(content) = el.value().attr("content") {
            let clean = content.split_whitespace().collect::<Vec<_>>().join(" ");
            if !clean.trim().is_empty() {
                return Some(clean.trim().to_string());
            }
        }
    }

    let title_sel = Selector::parse("title").ok()?;
    if let Some(el) = doc.select(&title_sel).next() {
        let title = el.text().collect::<Vec<_>>().join(" ");
        let clean = title.split_whitespace().collect::<Vec<_>>().join(" ");
        if !clean.trim().is_empty() {
            return Some(clean.trim().to_string());
        }
    }

    let h1_sel = Selector::parse("h1").ok()?;
    if let Some(el) = doc.select(&h1_sel).next() {
        let title = el.text().collect::<Vec<_>>().join(" ");
        let clean = title.split_whitespace().collect::<Vec<_>>().join(" ");
        if !clean.trim().is_empty() {
            return Some(clean.trim().to_string());
        }
    }

    None
}

fn derive_title_from_url(url: &reqwest::Url) -> String {
    let host = url.host_str().unwrap_or("unknown");
    let path = url.path().trim_matches('/');
    if path.is_empty() {
        host.to_string()
    } else {
        format!("{host}/{path}")
    }
}

fn extract_canonical_url(base: &reqwest::Url, raw_html: &str) -> Option<reqwest::Url> {
    let doc = Html::parse_document(raw_html);
    let sel = Selector::parse(r#"link[rel="canonical"]"#).ok()?;
    let href = doc
        .select(&sel)
        .filter_map(|e| e.value().attr("href"))
        .map(|s| s.trim())
        .find(|s| !s.is_empty())?;

    if let Ok(u) = base.join(href) {
        return Some(u);
    }
    reqwest::Url::parse(href).ok()
}

fn extract_text(raw: &str, content_type: &str) -> String {
    if is_html_like(content_type) {
        extract_html_main_markdown(raw, 1_000_000)
    } else {
        clean_plain_text(raw, 1_000_000)
    }
}

fn expand_tilde(path: &str) -> PathBuf {
    if let Some(rest) = path.strip_prefix("~/") {
        if let Some(home) = std::env::var_os("HOME") {
            return PathBuf::from(home).join(rest);
        }
    }
    PathBuf::from(path)
}

fn extend_tags(tags: &mut Vec<String>, extra: &[String]) {
    for t in extra {
        let t = t.trim();
        if t.is_empty() {
            continue;
        }
        if !tags.iter().any(|x| x.eq_ignore_ascii_case(t)) {
            tags.push(t.to_string());
        }
    }
}

fn normalize_url(url: &reqwest::Url) -> String {
    let mut u = url.clone();
    u.set_fragment(None);
    strip_tracking_query_params(&mut u);
    u.to_string()
}

fn extract_links(base: &reqwest::Url, raw_html: &str, max_links: usize) -> Vec<reqwest::Url> {
    let mut out = Vec::new();
    let doc = Html::parse_document(raw_html);
    let sel = match Selector::parse("a[href]") {
        Ok(s) => s,
        Err(_) => return Vec::new(),
    };

    for el in doc.select(&sel).take(max_links.saturating_mul(5).max(max_links)) {
        let Some(href) = el.value().attr("href") else {
            continue;
        };
        let href = href.trim();
        if href.is_empty() || href.starts_with('#') {
            continue;
        }
        if href.starts_with("mailto:") || href.starts_with("javascript:") {
            continue;
        }

        let u = if let Ok(u) = base.join(href) {
            u
        } else if let Ok(u) = reqwest::Url::parse(href) {
            u
        } else {
            continue;
        };

        if u.scheme() != "http" && u.scheme() != "https" {
            continue;
        }

        if is_non_text_asset(&u) {
            continue;
        }

        out.push(u);
        if out.len() >= max_links {
            break;
        }
    }

    // Normalize + dedup
    let mut seen = HashSet::new();
    let mut uniq = Vec::new();
    for u in out {
        let norm = normalize_url(&u);
        if seen.insert(norm.clone()) {
            if let Ok(parsed) = reqwest::Url::parse(&norm) {
                uniq.push(parsed);
            }
        }
    }
    uniq
}

fn strip_tracking_query_params(url: &mut reqwest::Url) {
    let pairs: Vec<(String, String)> = url
        .query_pairs()
        .map(|(k, v)| (k.to_string(), v.to_string()))
        .collect();
    if pairs.is_empty() {
        return;
    }

    let mut kept = Vec::with_capacity(pairs.len());
    for (k, v) in pairs {
        let key = k.to_lowercase();
        let drop = key.starts_with("utm_")
            || matches!(
                key.as_str(),
                "gclid"
                    | "fbclid"
                    | "mc_cid"
                    | "mc_eid"
                    | "ref"
                    | "ref_src"
                    | "source"
                    | "s"
                    | "spm"
                    | "mkt_tok"
                    | "sessionid"
                    | "sid"
            );
        if !drop {
            kept.push((k, v));
        }
    }

    if kept.is_empty() {
        url.set_query(None);
        return;
    }

    // Stable normalization: sort keys for deduplication.
    kept.sort_by(|a, b| a.0.cmp(&b.0));
    url.query_pairs_mut().clear().extend_pairs(kept);
}

fn is_non_text_asset(url: &reqwest::Url) -> bool {
    let path = url.path().to_lowercase();
    let Some(last) = path.rsplit('/').next() else {
        return false;
    };
    let Some(ext) = last.rsplit('.').next() else {
        return false;
    };
    if ext == last {
        return false;
    }

    // Keep PDFs (handled explicitly), drop common binary assets.
    matches!(
        ext,
        "png"
            | "jpg"
            | "jpeg"
            | "gif"
            | "webp"
            | "svg"
            | "ico"
            | "css"
            | "js"
            | "map"
            | "woff"
            | "woff2"
            | "ttf"
            | "eot"
            | "zip"
            | "tar"
            | "gz"
            | "bz2"
            | "xz"
            | "7z"
            | "rar"
            | "mp3"
            | "mp4"
            | "m4a"
            | "mov"
            | "avi"
            | "mkv"
    )
}

fn extract_html_main_markdown(raw_html: &str, max_chars: usize) -> String {
    let doc = Html::parse_document(raw_html);

    let candidates_sel = Selector::parse(
        "main, article, .markdown-body, .content, #content, #main, #readme, .doc, .docs, .documentation, .post, .entry-content, .prose",
    )
    .unwrap();
    let body_sel = Selector::parse("body").unwrap();
    let block_sel = Selector::parse("h1,h2,h3,h4,h5,h6,pre,p,li,blockquote").unwrap();

    let mut best: Option<(scraper::ElementRef<'_>, usize)> = None;
    for cand in doc.select(&candidates_sel) {
        if is_noise_container(&cand) {
            continue;
        }
        let len = visible_text_len(&cand);
        if len < 200 {
            continue;
        }
        if best.as_ref().map(|(_, n)| len > *n).unwrap_or(true) {
            best = Some((cand, len));
        }
    }

    let root = best
        .map(|(el, _)| el)
        .or_else(|| doc.select(&body_sel).next())
        .unwrap_or_else(|| doc.root_element());

    let mut out = String::new();
    for el in root.select(&block_sel).take(8_000) {
        if is_in_noise_container(&el) {
            continue;
        }

        let name = el.value().name();
        // Avoid duplicating list text: skip paragraphs/headings nested inside list items.
        if matches!(name, "p" | "h1" | "h2" | "h3" | "h4" | "h5" | "h6") && has_ancestor_tag(&el, "li") {
            continue;
        }

        match name {
            "pre" => {
                let code = el.text().collect::<Vec<_>>().join("");
                let code = code.trim_matches('\n').trim_end();
                if code.is_empty() {
                    continue;
                }
                out.push_str("\n\n```");
                out.push('\n');
                out.push_str(code);
                out.push('\n');
                out.push_str("```\n");
            }
            "blockquote" => {
                let txt = collapse_ws(el.text().collect::<Vec<_>>().join(" "));
                if txt.is_empty() {
                    continue;
                }
                out.push_str("\n\n> ");
                out.push_str(&txt);
                out.push('\n');
            }
            "li" => {
                let txt = collapse_ws(el.text().collect::<Vec<_>>().join(" "));
                if txt.is_empty() {
                    continue;
                }
                out.push_str("\n- ");
                out.push_str(&txt);
            }
            "p" => {
                let txt = collapse_ws(el.text().collect::<Vec<_>>().join(" "));
                if txt.is_empty() {
                    continue;
                }
                out.push_str("\n\n");
                out.push_str(&txt);
                out.push('\n');
            }
            h if h.starts_with('h') && h.len() == 2 => {
                let level = h[1..].parse::<usize>().unwrap_or(2).clamp(1, 6);
                let txt = collapse_ws(el.text().collect::<Vec<_>>().join(" "));
                if txt.is_empty() {
                    continue;
                }
                out.push_str("\n\n");
                out.push_str(&"#".repeat(level));
                out.push(' ');
                out.push_str(&txt);
                out.push('\n');
            }
            _ => {}
        }

        if out.len() >= max_chars {
            break;
        }
    }

    clean_markdown_text(&out, max_chars)
}

fn clean_plain_text(raw: &str, max_chars: usize) -> String {
    let mut s = raw.replace("\r\n", "\n");
    if s.len() > max_chars {
        s.truncate(max_chars);
    }
    // Collapse whitespace a bit but keep line breaks.
    let mut out = String::new();
    for line in s.lines() {
        let trimmed = line.trim();
        if trimmed.is_empty() {
            out.push('\n');
            continue;
        }
        out.push_str(&collapse_ws(trimmed.to_string()));
        out.push('\n');
    }
    clean_markdown_text(&out, max_chars)
}

fn clean_markdown_text(raw: &str, max_chars: usize) -> String {
    let mut out = String::new();
    let mut in_code = false;
    let mut blank_run = 0usize;

    for line in raw.replace("\r\n", "\n").lines() {
        let trimmed = if in_code {
            line.trim_end()
        } else {
            line.trim()
        };

        if trimmed.starts_with("```") {
            in_code = !in_code;
            blank_run = 0;
            out.push_str(trimmed);
            out.push('\n');
            continue;
        }

        if !in_code && trimmed.is_empty() {
            blank_run += 1;
            if blank_run <= 2 {
                out.push('\n');
            }
            continue;
        }

        blank_run = 0;
        out.push_str(trimmed);
        out.push('\n');
        if out.len() >= max_chars {
            break;
        }
    }

    if out.len() > max_chars {
        out.truncate(max_chars);
    }
    out.trim().to_string()
}

fn collapse_ws(s: String) -> String {
    s.split_whitespace().collect::<Vec<_>>().join(" ")
}

fn visible_text_len(el: &scraper::ElementRef<'_>) -> usize {
    el.text()
        .map(|t| t.trim())
        .filter(|t| !t.is_empty())
        .map(|t| t.len())
        .sum()
}

fn has_ancestor_tag(el: &scraper::ElementRef<'_>, tag: &str) -> bool {
    el.ancestors()
        .skip(1)
        .filter_map(scraper::ElementRef::wrap)
        .any(|a| a.value().name() == tag)
}

fn is_in_noise_container(el: &scraper::ElementRef<'_>) -> bool {
    el.ancestors()
        .filter_map(scraper::ElementRef::wrap)
        .any(|a| is_noise_container(&a))
}

fn is_noise_container(el: &scraper::ElementRef<'_>) -> bool {
    let name = el.value().name();
    if matches!(name, "nav" | "header" | "footer" | "aside") {
        return true;
    }

    let id = el.value().attr("id").unwrap_or("").to_lowercase();
    let class = el.value().attr("class").unwrap_or("").to_lowercase();
    let hay = format!("{id} {class}");

    let noisy = [
        "nav",
        "navbar",
        "footer",
        "header",
        "sidebar",
        "menu",
        "breadcrumb",
        "breadcrumbs",
        "toc",
        "table-of-contents",
        "cookie",
        "banner",
        "modal",
        "subscribe",
        "search",
        "promo",
        "advert",
    ];
    noisy.iter().any(|k| hay.contains(k))
}

fn extract_feed_links(xml: &str) -> Vec<String> {
    // Prefer real XML parsing (RSS/Atom are often messy; regex misses namespaces and rel/type filters).
    match extract_feed_links_xml(xml) {
        Ok(links) if !links.is_empty() => links,
        _ => extract_feed_links_regex(xml),
    }
}

fn extract_feed_links_regex(xml: &str) -> Vec<String> {
    // RSS: <link>https://...</link>
    // Atom: <link href="https://..." .../>
    let mut out = Vec::new();
    if let Ok(re) = Regex::new(r#"(?is)<link[^>]*href=["']([^"']+)["'][^>]*/?>"#) {
        for cap in re.captures_iter(xml).take(5000) {
            if let Some(u) = cap.get(1).map(|m| m.as_str().trim()) {
                if u.starts_with("http://") || u.starts_with("https://") {
                    out.push(u.to_string());
                }
            }
        }
    }
    if let Ok(re) = Regex::new(r"(?is)<link>([^<]+)</link>") {
        for cap in re.captures_iter(xml).take(5000) {
            if let Some(u) = cap.get(1).map(|m| m.as_str().trim()) {
                if u.starts_with("http://") || u.starts_with("https://") {
                    out.push(u.to_string());
                }
            }
        }
    }
    out
}

fn extract_feed_links_xml(xml: &str) -> Result<Vec<String>> {
    // Extract item/entry URLs from RSS/Atom feeds.
    let mut reader = XmlReader::from_str(xml);
    reader.config_mut().trim_text(true);

    let mut buf = Vec::new();

    // Track whether we're inside an RSS <item> or Atom <entry>.
    let mut item_depth = 0usize;
    let mut entry_depth = 0usize;

    let mut in_rss_link_text = false;
    let mut rss_link_rel: Option<String> = None;
    let mut rss_link_type: Option<String> = None;

    let mut out: Vec<String> = Vec::new();

    for _ in 0..250_000 {
        match reader.read_event_into(&mut buf) {
            Ok(XmlEvent::Eof) => break,
            Ok(XmlEvent::Start(e)) => {
                let qname = e.name();
                let name = local_name(qname.as_ref());
                if name.eq_ignore_ascii_case(b"item") {
                    item_depth += 1;
                } else if name.eq_ignore_ascii_case(b"entry") {
                    entry_depth += 1;
                } else if name.eq_ignore_ascii_case(b"link") {
                    // RSS: <item><link>...</link></item> (no href attr).
                    // Atom: <entry><link href="..."/> (href attr).
                    if item_depth > 0 || entry_depth > 0 {
                        if let Some(href) = extract_href_if_allowed(&reader, &e)? {
                            out.push(href);
                        } else {
                            in_rss_link_text = true;
                            let (rel, typ) = extract_rel_type(&reader, &e)?;
                            rss_link_rel = rel;
                            rss_link_type = typ;
                        }
                    }
                }
            }
            Ok(XmlEvent::Empty(e)) => {
                let qname = e.name();
                let name = local_name(qname.as_ref());
                if name.eq_ignore_ascii_case(b"link") && (item_depth > 0 || entry_depth > 0) {
                    if let Some(href) = extract_href_if_allowed(&reader, &e)? {
                        out.push(href);
                    }
                }
            }
            Ok(XmlEvent::End(e)) => {
                let qname = e.name();
                let name = local_name(qname.as_ref());
                if name.eq_ignore_ascii_case(b"item") {
                    item_depth = item_depth.saturating_sub(1);
                } else if name.eq_ignore_ascii_case(b"entry") {
                    entry_depth = entry_depth.saturating_sub(1);
                } else if name.eq_ignore_ascii_case(b"link") {
                    in_rss_link_text = false;
                    rss_link_rel = None;
                    rss_link_type = None;
                }
            }
            Ok(XmlEvent::Text(e)) => {
                if !in_rss_link_text || item_depth == 0 {
                    continue;
                }
                let txt = e.unescape()?.trim().to_string();
                if txt.is_empty() {
                    continue;
                }
                if !is_http_url(&txt) {
                    continue;
                }
                if !rss_link_allowed(rss_link_rel.as_deref(), rss_link_type.as_deref()) {
                    continue;
                }
                out.push(txt);
            }
            Ok(XmlEvent::CData(e)) => {
                if !in_rss_link_text || item_depth == 0 {
                    continue;
                }
                let txt = String::from_utf8_lossy(e.as_ref()).trim().to_string();
                if txt.is_empty() {
                    continue;
                }
                if !is_http_url(&txt) {
                    continue;
                }
                if !rss_link_allowed(rss_link_rel.as_deref(), rss_link_type.as_deref()) {
                    continue;
                }
                out.push(txt);
            }
            Ok(_) => {}
            Err(_) => break,
        }

        if out.len() >= 50_000 {
            break;
        }
        buf.clear();
    }

    // Dedup preserving order.
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
        if uniq.len() >= 50_000 {
            break;
        }
    }
    Ok(uniq)
}

fn local_name(name: &[u8]) -> &[u8] {
    name.split(|b| *b == b':').last().unwrap_or(name)
}

fn extract_href_if_allowed<R: std::io::BufRead>(
    reader: &XmlReader<R>,
    el: &quick_xml::events::BytesStart<'_>,
) -> Result<Option<String>> {
    let mut href: Option<String> = None;
    let mut rel: Option<String> = None;
    let mut typ: Option<String> = None;

    for attr in el.attributes().with_checks(false) {
        let attr = match attr {
            Ok(a) => a,
            Err(_) => continue,
        };
        let key = local_name(attr.key.as_ref());
        let value = attr.unescape_value()?.to_string();
        match key {
            b"href" => href = Some(value),
            b"rel" => rel = Some(value),
            b"type" => typ = Some(value),
            _ => {}
        }
    }

    let Some(href) = href else {
        return Ok(None);
    };

    if !rss_link_allowed(rel.as_deref(), typ.as_deref()) {
        return Ok(None);
    }

    let href = href.trim();
    if href.is_empty() {
        return Ok(None);
    }
    // Decode entities already handled by unescape_value; validate scheme.
    if !is_http_url(href) {
        return Ok(None);
    }
    let _ = reader; // reserved for future base-url resolution
    Ok(Some(href.to_string()))
}

fn extract_rel_type<R: std::io::BufRead>(
    _reader: &XmlReader<R>,
    el: &quick_xml::events::BytesStart<'_>,
) -> Result<(Option<String>, Option<String>)> {
    let mut rel: Option<String> = None;
    let mut typ: Option<String> = None;
    for attr in el.attributes().with_checks(false) {
        let attr = match attr {
            Ok(a) => a,
            Err(_) => continue,
        };
        let key = local_name(attr.key.as_ref());
        let value = attr.unescape_value()?.to_string();
        match key {
            b"rel" => rel = Some(value),
            b"type" => typ = Some(value),
            _ => {}
        }
    }
    Ok((rel, typ))
}

fn rss_link_allowed(rel: Option<&str>, typ: Option<&str>) -> bool {
    // Atom feeds include multiple links; keep only item/entry URLs:
    // - rel=alternate or missing
    // - type not a feed type (rss/atom)
    if let Some(rel) = rel {
        let rel = rel.trim().to_lowercase();
        if rel == "self" || rel == "hub" || rel == "service" {
            return false;
        }
        if !rel.is_empty() && rel != "alternate" {
            // Unknown/other rel: ignore by default.
            return false;
        }
    }

    if let Some(typ) = typ {
        let typ = typ.trim().to_lowercase();
        if typ.contains("application/rss+xml")
            || typ.contains("application/atom+xml")
            || typ.contains("application/xml")
        {
            return false;
        }
    }

    true
}

fn is_http_url(u: &str) -> bool {
    u.starts_with("http://") || u.starts_with("https://")
}

fn extract_sitemap_locs(xml: &str) -> Vec<String> {
    let mut out = Vec::new();
    if let Ok(re) = Regex::new(r"(?is)<loc>([^<]+)</loc>") {
        for cap in re.captures_iter(xml).take(50_000) {
            if let Some(u) = cap.get(1).map(|m| m.as_str().trim()) {
                if u.starts_with("http://") || u.starts_with("https://") {
                    out.push(u.to_string());
                }
            }
        }
    }
    out
}

#[derive(Debug, Clone)]
struct RobotsRules {
    allow: Vec<String>,
    disallow: Vec<String>,
}

#[derive(Debug, Default)]
struct RobotsGroup {
    agents: Vec<String>,
    allow: Vec<String>,
    disallow: Vec<String>,
}

impl RobotsRules {
    fn allows(&self, path: &str) -> bool {
        let path = if path.is_empty() { "/" } else { path };

        let mut best_allow = 0usize;
        for a in &self.allow {
            if a == "/" || a.is_empty() {
                best_allow = best_allow.max(1);
            } else if path.starts_with(a) {
                best_allow = best_allow.max(a.len());
            }
        }

        let mut best_disallow = 0usize;
        for d in &self.disallow {
            if d.is_empty() {
                continue;
            }
            if path.starts_with(d) {
                best_disallow = best_disallow.max(d.len());
            }
        }

        best_allow >= best_disallow
    }
}

async fn fetch_robots_rules(
    client: &reqwest::Client,
    url: &reqwest::Url,
    ua: &str,
) -> Result<RobotsRules> {
    let scheme = url.scheme();
    let host = url.host_str().unwrap_or("unknown");
    let robots_url = format!("{scheme}://{host}/robots.txt");

    let resp = client.get(&robots_url).send().await?;
    if resp.status().as_u16() == 404 {
        return Ok(RobotsRules {
            allow: vec!["/".to_string()],
            disallow: vec![],
        });
    }
    let status = resp.status();
    if !status.is_success() {
        anyhow::bail!("robots.txt HTTP {}", status);
    }
    let body = resp.text().await.unwrap_or_default();
    Ok(parse_robots_txt(&body, ua))
}

fn parse_robots_txt(body: &str, ua: &str) -> RobotsRules {
    let ua = ua.to_lowercase();

    let mut groups: Vec<RobotsGroup> = Vec::new();
    let mut current = RobotsGroup::default();
    let mut has_group = false;
    let mut has_rules = false;

    for raw in body.lines() {
        let line = raw.split('#').next().unwrap_or("").trim();
        if line.is_empty() {
            continue;
        }
        let mut parts = line.splitn(2, ':');
        let key = parts.next().unwrap_or("").trim().to_lowercase();
        let value = parts.next().unwrap_or("").trim();

        match key.as_str() {
            "user-agent" => {
                let agent = value.to_lowercase();
                if agent.is_empty() {
                    continue;
                }
                if has_group && has_rules {
                    groups.push(current);
                    current = RobotsGroup::default();
                    has_rules = false;
                }
                current.agents.push(agent);
                has_group = true;
            }
            "allow" if has_group => {
                has_rules = true;
                current.allow.push(value.to_string());
            }
            "disallow" if has_group => {
                has_rules = true;
                current.disallow.push(value.to_string());
            }
            _ => {}
        }
    }

    if has_group {
        groups.push(current);
    }

    let mut best: Option<(usize, usize)> = None;
    for (idx, g) in groups.iter().enumerate() {
        let score = g
            .agents
            .iter()
            .filter_map(|a| match_user_agent_score(&ua, a))
            .max()
            .unwrap_or(0);
        if score == 0 {
            continue;
        }
        if best.map(|(s, _)| score > s).unwrap_or(true) {
            best = Some((score, idx));
        }
    }

    let Some((_, idx)) = best else {
        return RobotsRules {
            allow: vec!["/".to_string()],
            disallow: vec![],
        };
    };

    let mut allow: Vec<String> = groups[idx]
        .allow
        .iter()
        .map(|s| s.trim())
        .filter(|s| !s.is_empty())
        .map(|s| s.to_string())
        .collect();
    let disallow: Vec<String> = groups[idx]
        .disallow
        .iter()
        .map(|s| s.trim())
        .filter(|s| !s.is_empty())
        .map(|s| s.to_string())
        .collect();

    if allow.is_empty() && disallow.is_empty() {
        allow.push("/".to_string());
    }

    RobotsRules { allow, disallow }
}

fn match_user_agent_score(ua: &str, agent: &str) -> Option<usize> {
    let agent = agent.trim().to_lowercase();
    if agent.is_empty() {
        return None;
    }
    if agent == "*" {
        return Some(1);
    }
    if ua.starts_with(&agent) {
        return Some(agent.len());
    }
    None
}

async fn init_ledger(db_url: Option<&str>) -> Result<Option<IngestionLedger>> {
    let Some(db_url) = db_url else {
        return Ok(None);
    };
    let ledger = IngestionLedger::connect(db_url).await?;
    ledger.ensure_schema().await?;
    Ok(Some(ledger))
}
