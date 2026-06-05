use anyhow::{Context, Result};
use beagle_rag_update::ledger::IngestionLedger;
use beagle_rag_update::knowledge::{index_document, DocType, DocumentMeta, KnowledgeConfig};
use clap::Parser;
use chrono::Datelike;
use regex::Regex;
use std::collections::{HashMap, HashSet, VecDeque};
use std::path::{Path, PathBuf};
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

    /// Ignore robots.txt (default: false)
    #[arg(long, env = "DARWIN_WEB_IGNORE_ROBOTS", default_value_t = false)]
    ignore_robots: bool,

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

    /// One or more URLs to fetch (repeatable). If omitted, use --rss/--sitemap.
    #[arg(long)]
    url: Vec<String>,
}

#[tokio::main]
async fn main() -> Result<()> {
    tracing_subscriber::fmt()
        .with_env_filter(tracing_subscriber::EnvFilter::from_default_env())
        .init();

    let args = Args::parse();

    if args.url.is_empty() && args.rss.is_empty() && args.sitemap.is_empty() {
        anyhow::bail!("provide at least one --url, --rss, or --sitemap");
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
    };

    let out_dir = expand_tilde(&args.out_dir);
    std::fs::create_dir_all(&out_dir)
        .with_context(|| format!("failed to create {}", out_dir.display()))?;

    let allowlist = build_allowlist(&args);
    let denylist = build_denylist(&args);
    let client = reqwest::Client::builder()
        .user_agent("BEAGLE darwin-web-harvester (+https://github.com/agourakis82/beagle)")
        .build()?;

    let mut total_docs = 0usize;
    let mut total_chunks = 0usize;

    let mut robots_cache: HashMap<String, RobotsRules> = HashMap::new();
    let mut queue: VecDeque<(reqwest::Url, usize, Option<String>)> = VecDeque::new();
    let mut seen: HashSet<String> = HashSet::new();

    let seeds = expand_sources(&client, &args).await?;
    for seed in seeds {
        if let Ok(u) = reqwest::Url::parse(&seed) {
            queue.push_back((u, 0, None));
        } else {
            warn!(url = %seed, "invalid seed URL (skipping)");
        }
    }

    while let Some((url, depth, seed_host)) = queue.pop_front() {
        if total_docs >= args.max_urls {
            break;
        }

        let normalized = normalize_url(&url);
        if !seen.insert(normalized.clone()) {
            continue;
        }

        let host = url.host_str().unwrap_or("unknown").to_lowercase();
        if !is_host_allowed(&host, &allowlist, &denylist) {
            continue;
        }

        if !args.allow_cross_host {
            if let Some(seed_host) = seed_host.as_ref() {
                if seed_host != &host {
                    continue;
                }
            }
        }

        if !args.ignore_robots {
            match robots_cache.get(&host) {
                Some(rules) => {
                    if !rules.allows(url.path()) {
                        warn!(url = %url, "robots.txt disallows path (skipping)");
                        continue;
                    }
                }
                None => match fetch_robots_rules(&client, &url, &args.robots_user_agent).await {
                    Ok(rules) => {
                        let allowed = rules.allows(url.path());
                        robots_cache.insert(host.clone(), rules);
                        if !allowed {
                            warn!(url = %url, "robots.txt disallows path (skipping)");
                            continue;
                        }
                    }
                    Err(e) => {
                        // Fail-open: if robots.txt cannot be fetched/parsed, proceed.
                        warn!(host = %host, "robots.txt check failed (proceeding): {e:#}");
                    }
                },
            }
        }

        let seed_host = seed_host.or_else(|| Some(host.clone()));
        match fetch_extract_index(
            &client,
            &cfg,
            &out_dir,
            &args.tag,
            args.license.as_deref(),
            args.max_bytes,
            &url,
        )
        .await
        {
            Ok(result) => {
                total_docs += 1;
                total_chunks += result.chunks;

                if depth < args.crawl_depth {
                    for next in result.discovered_links {
                        let next_host = next.host_str().unwrap_or("unknown").to_lowercase();
                        if !args.allow_cross_host && next_host != host {
                            continue;
                        }
                        queue.push_back((next, depth + 1, seed_host.clone()));
                    }
                }
            }
            Err(e) => warn!(url = %url, "ingest failed: {e:#}"),
        }
    }

    info!(total_docs, total_chunks, "web harvest complete");
    Ok(())
}

fn build_allowlist(args: &Args) -> HashSet<String> {
    let mut hosts: HashSet<String> = HashSet::new();
    for h in &args.allow_host {
        let h = h.trim().to_lowercase();
        if !h.is_empty() {
            hosts.insert(h);
        }
    }
    if let Some(ref h) = args.allow_hosts {
        for part in h.split(',') {
            let part = part.trim().to_lowercase();
            if !part.is_empty() {
                hosts.insert(part);
            }
        }
    }
    hosts
}

fn build_denylist(args: &Args) -> HashSet<String> {
    let mut hosts: HashSet<String> = HashSet::new();
    for h in &args.deny_host {
        let h = h.trim().to_lowercase();
        if !h.is_empty() {
            hosts.insert(h);
        }
    }
    if let Some(ref h) = args.deny_hosts {
        for part in h.split(',') {
            let part = part.trim().to_lowercase();
            if !part.is_empty() {
                hosts.insert(part);
            }
        }
    }
    hosts
}

fn is_host_allowed(host: &str, allow: &HashSet<String>, deny: &HashSet<String>) -> bool {
    if deny.contains(host) {
        return false;
    }
    if !allow.is_empty() && !allow.contains(host) {
        return false;
    }
    true
}

async fn expand_sources(client: &reqwest::Client, args: &Args) -> Result<Vec<String>> {
    let mut out = Vec::new();
    out.extend(args.url.clone());

    for feed in &args.rss {
        let xml = fetch_text(client, feed, args.max_bytes).await?;
        out.extend(extract_feed_links(&xml));
    }

    for sm in &args.sitemap {
        let xml = fetch_text(client, sm, args.max_bytes).await?;
        out.extend(extract_sitemap_locs(&xml));
    }

    // Dedup, stable order
    let mut seen: HashSet<String> = HashSet::new();
    let mut uniq = Vec::new();
    for u in out {
        let trimmed = u.trim();
        if trimmed.is_empty() {
            continue;
        }
        if seen.insert(trimmed.to_string()) {
            uniq.push(trimmed.to_string());
        }
    }
    Ok(uniq)
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

    let raw = String::from_utf8_lossy(&bytes).to_string();
    let title = extract_title(&raw).unwrap_or_else(|| derive_title_from_url(&final_url));
    let extracted = extract_text(&raw, &content_type);

    let doc_id = final_url.to_string();
    let safe_id = blake3::hash(doc_id.as_bytes()).to_hex().to_string();
    let dir = out_dir.join(&host);
    std::fs::create_dir_all(&dir)?;
    let path = dir.join(format!("{safe_id}.md"));

    let now = chrono::Utc::now();
    let body = format!(
        "# {title}\n\nURL: {url}\nContent-Type: {ct}\n\n## Content\n\n{content}\n",
        title = title,
        url = doc_id,
        ct = content_type,
        content = extracted
    );
    std::fs::write(&path, body)?;

    let mut tags = base_tags.to_vec();
    if !tags.contains(&host) {
        tags.push(host.clone());
    }

    let meta = DocumentMeta {
        title: title.clone(),
        path,
        doc_id: Some(doc_id.clone()),
        author: None,
        year: Some(now.year()),
        doi: None,
        tags,
        source: Some("web".to_string()),
        license: license.map(|s| s.to_string()),
        extra: serde_json::json!({
            "final_url": doc_id,
            "host": host,
            "content_type": content_type,
            "fetched_at": now.to_rfc3339(),
        }),
    };

    let chunks = index_document(cfg, DocType::Doc, meta).await?;

    let discovered_links = if content_type.to_lowercase().contains("text/html") {
        extract_links(&final_url, &raw, 500)
    } else {
        Vec::new()
    };

    Ok(FetchIndexResult {
        chunks,
        discovered_links,
    })
}

fn extract_title(raw: &str) -> Option<String> {
    // Very small heuristic: HTML <title> tag.
    let re = Regex::new(r"(?is)<title[^>]*>(.*?)</title>").ok()?;
    let cap = re.captures(raw)?;
    let title = cap.get(1)?.as_str();
    let clean = Regex::new(r"(?is)<[^>]+>")
        .ok()?
        .replace_all(title, " ")
        .split_whitespace()
        .collect::<Vec<_>>()
        .join(" ");
    let clean = clean.trim();
    if clean.is_empty() {
        None
    } else {
        Some(clean.to_string())
    }
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

fn extract_text(raw: &str, content_type: &str) -> String {
    if content_type.to_lowercase().contains("text/html") {
        // Remove scripts/styles then strip tags.
        let script_re = Regex::new(r"(?is)<script[^>]*>.*?</script>").unwrap();
        let style_re = Regex::new(r"(?is)<style[^>]*>.*?</style>").unwrap();
        let tags_re = Regex::new(r"(?is)<[^>]+>").unwrap();
        let no_script = script_re.replace_all(raw, " ");
        let no_style = style_re.replace_all(&no_script, " ");
        let no_tags = tags_re.replace_all(&no_style, " ");
        no_tags
            .split_whitespace()
            .take(80_000)
            .collect::<Vec<_>>()
            .join(" ")
    } else {
        raw.split_whitespace()
            .take(80_000)
            .collect::<Vec<_>>()
            .join(" ")
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

fn normalize_url(url: &reqwest::Url) -> String {
    let mut u = url.clone();
    u.set_fragment(None);
    u.to_string()
}

fn extract_links(base: &reqwest::Url, raw_html: &str, max_links: usize) -> Vec<reqwest::Url> {
    // Very small heuristic: extract href values.
    let re = match Regex::new(r#"(?is)\bhref\s*=\s*["']([^"'#]+)["']"#) {
        Ok(r) => r,
        Err(_) => return Vec::new(),
    };

    let mut out = Vec::new();
    for cap in re.captures_iter(raw_html).take(max_links) {
        let href = cap.get(1).map(|m| m.as_str()).unwrap_or("").trim();
        if href.is_empty() {
            continue;
        }
        if href.starts_with("mailto:") || href.starts_with("javascript:") {
            continue;
        }
        if let Ok(u) = base.join(href) {
            out.push(u);
        } else if let Ok(u) = reqwest::Url::parse(href) {
            out.push(u);
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

fn extract_feed_links(xml: &str) -> Vec<String> {
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
    _ua: &str,
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
    Ok(parse_robots_txt(&body))
}

fn parse_robots_txt(body: &str) -> RobotsRules {
    let mut allow = Vec::new();
    let mut disallow = Vec::new();

    // Minimal parser: only honors `User-agent: *` group.
    let mut in_global = false;
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
                in_global = value == "*";
            }
            "allow" if in_global
                && !value.is_empty() => {
                    allow.push(value.to_string());
                }
            "disallow" if in_global
                && !value.is_empty() => {
                    disallow.push(value.to_string());
                }
            _ => {}
        }
    }

    if allow.is_empty() && disallow.is_empty() {
        allow.push("/".to_string());
    }

    RobotsRules { allow, disallow }
}

async fn init_ledger(db_url: Option<&str>) -> Result<Option<IngestionLedger>> {
    let Some(db_url) = db_url else {
        return Ok(None);
    };
    let ledger = IngestionLedger::connect(db_url).await?;
    ledger.ensure_schema().await?;
    Ok(Some(ledger))
}
