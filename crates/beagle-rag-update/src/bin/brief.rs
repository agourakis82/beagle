use anyhow::{Context, Result};
use beagle_llm::{LlmCallsStats, RequestMeta, TieredRouter};
use beagle_rag_update::embed::EmbeddingClient;
use beagle_rag_update::qdrant::QdrantClient;
use clap::Parser;
use chrono::{DateTime, Duration, Utc};
use serde::{Deserialize, Serialize};
use std::collections::{HashMap, HashSet};
use std::path::{Path, PathBuf};
use tracing::{info, warn};
use regex::Regex;

#[derive(Debug, Parser)]
#[command(name = "darwin-brief")]
#[command(about = "Generate topic briefs from the current RAG corpus (LLM + citations)")]
struct Args {
    #[arg(long, env = "QDRANT_URL", default_value = "http://localhost:6333")]
    qdrant_url: String,

    #[arg(long, env = "EMBEDDING_URL", default_value = "http://localhost:8001/v1")]
    embedding_url: String,

    #[arg(long, env = "EMBEDDING_MODEL", default_value = "NV-Embed-v2")]
    embedding_model: String,

    /// Topics registry (YAML/TOML/JSON). Same format as darwin-research-harvester.
    #[arg(long, env = "DARWIN_HARVEST_TOPICS_FILE", default_value = "scripts/darwin-research-topics.yaml")]
    topics_file: String,

    /// Only run specific topic(s) from the topics file (repeatable).
    #[arg(long)]
    topic: Vec<String>,

    /// Output directory for generated briefs.
    #[arg(long, env = "DARWIN_BRIEF_DIR", default_value = "~/knowledge/briefs")]
    out_dir: String,

    /// Brief state file (used to compute per-topic changes between runs).
    #[arg(long, env = "DARWIN_BRIEF_STATE_FILE", default_value = "~/.darwin_brief_state.json")]
    state_file: String,

    /// Comma-separated collection list to search.
    #[arg(long, env = "BEAGLE_QDRANT_COLLECTIONS")]
    collections: Option<String>,

    /// Top-k per query per collection.
    #[arg(long, default_value_t = 10)]
    k: usize,

    /// Maximum number of distinct documents to include in the brief.
    #[arg(long, default_value_t = 12)]
    max_docs: usize,

    /// Max characters per snippet sent to the LLM.
    #[arg(long, default_value_t = 900)]
    max_snippet_chars: usize,

    /// Skip LLM synthesis and emit a retrieval report only.
    #[arg(long)]
    no_llm: bool,

    /// Also compute changes since N days ago (from brief state history). Use 0 to disable.
    #[arg(long, default_value_t = 7)]
    delta_days: i64,

    /// Fail the run if the LLM emits out-of-range bracket citations (e.g. `[99]` with only 12 sources).
    #[arg(long, env = "DARWIN_BRIEF_STRICT_CITATIONS", default_value_t = false)]
    strict_citations: bool,

    /// Minimum number of bracket citations required when LLM is enabled (0 disables).
    #[arg(long, env = "DARWIN_BRIEF_MIN_CITATIONS", default_value_t = 0)]
    min_citations: usize,
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
    tags: Vec<String>,
    #[serde(default)]
    queries: Vec<String>,
}

fn default_true() -> bool {
    true
}

#[derive(Debug, Clone, Serialize, Deserialize, Default)]
struct BriefState {
    last_run: Option<DateTime<Utc>>,
    topics: HashMap<String, TopicState>,
}

#[derive(Debug, Clone, Serialize, Deserialize, Default)]
struct TopicState {
    last_run: Option<DateTime<Utc>>,
    doc_ids: Vec<String>,
    #[serde(default)]
    history: Vec<TopicSnapshot>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
struct TopicSnapshot {
    at: DateTime<Utc>,
    docs: Vec<DocRef>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
struct DocRef {
    doc_id: String,
    title: String,
    url: Option<String>,
    doi: Option<String>,
    collection: String,
}

impl BriefState {
    fn load(path: &Path) -> Result<Self> {
        if !path.exists() {
            return Ok(Self::default());
        }
        let content = std::fs::read_to_string(path).context("failed to read brief state file")?;
        let state: Self = serde_json::from_str(&content).context("failed to parse brief state JSON")?;
        Ok(state)
    }

    fn save(&self, path: &Path) -> Result<()> {
        if let Some(parent) = path.parent() {
            std::fs::create_dir_all(parent).context("failed to create brief state dir")?;
        }
        let json = serde_json::to_string_pretty(self).context("failed to serialize brief state")?;
        std::fs::write(path, json).context("failed to write brief state file")?;
        Ok(())
    }
}

#[derive(Debug, Clone)]
struct DocHit {
    doc_id: String,
    title: String,
    url: Option<String>,
    doi: Option<String>,
    collection: String,
    score: f64,
    snippet: String,
}

#[derive(Debug)]
struct CitationReport {
    total: usize,
    unique: usize,
    invalid: Vec<usize>,
}

fn analyze_citations(markdown: &str, max_source_idx: usize) -> CitationReport {
    let re = Regex::new(r"\[(\d+)\]").expect("citation regex compile failed");
    let mut in_code = false;

    let mut total = 0usize;
    let mut seen: HashSet<usize> = HashSet::new();
    let mut invalid: Vec<usize> = Vec::new();

    for line in markdown.replace("\r\n", "\n").lines() {
        let trimmed = line.trim();
        if trimmed.starts_with("```") {
            in_code = !in_code;
            continue;
        }
        if in_code {
            continue;
        }

        for cap in re.captures_iter(line) {
            let Ok(n) = cap[1].parse::<usize>() else { continue };
            total += 1;
            seen.insert(n);
            if n == 0 || n > max_source_idx {
                invalid.push(n);
            }
        }
    }

    CitationReport {
        total,
        unique: seen.len(),
        invalid,
    }
}

#[tokio::main]
async fn main() -> Result<()> {
    tracing_subscriber::fmt()
        .with_env_filter(tracing_subscriber::EnvFilter::from_default_env())
        .init();

    let args = Args::parse();
    let topics_path = expand_tilde(&args.topics_file);
    let out_dir = expand_tilde(&args.out_dir);
    let state_path = expand_tilde(&args.state_file);

    std::fs::create_dir_all(&out_dir)
        .with_context(|| format!("failed to create {}", out_dir.display()))?;

    let cfg = config::Config::builder()
        .add_source(config::File::from(topics_path.clone()))
        .build()
        .with_context(|| format!("failed to load topics file {}", topics_path.display()))?;
    let topics: TopicsFile = cfg.try_deserialize().context("failed to deserialize topics file")?;

    let collections = parse_collections(args.collections.as_deref());
    if collections.is_empty() {
        anyhow::bail!("no collections provided (set BEAGLE_QDRANT_COLLECTIONS or pass --collections)");
    }

    let qdrant = QdrantClient::new(&args.qdrant_url);
    let embed = EmbeddingClient::new(&args.embedding_url, &args.embedding_model);

    let router = if args.no_llm {
        None
    } else {
        Some(TieredRouter::new().context("failed to init LLM router")?)
    };
    let mut llm_stats = LlmCallsStats::new();

    let mut state = BriefState::load(&state_path)?;
    let now = Utc::now();

    let topic_filter: HashSet<String> = args.topic.iter().cloned().collect();

    for topic in topics.topics {
        if !topic.enabled {
            continue;
        }
        if !topic_filter.is_empty() && !topic_filter.contains(&topic.name) {
            continue;
        }
        if topic.queries.iter().all(|q| q.trim().is_empty()) {
            warn!(topic = %topic.name, "topic has no queries (skipping)");
            continue;
        }

        info!(topic = %topic.name, collections = ?collections, "generating brief");

        let prev_topic_state = state.topics.get(&topic.name);
        let prev_doc_ids: HashSet<String> = prev_topic_state
            .map(|t| t.doc_ids.iter().cloned().collect())
            .unwrap_or_default();

        let last_titles: HashMap<String, String> = prev_topic_state
            .and_then(|t| t.history.iter().max_by_key(|s| s.at))
            .map(|s| {
                s.docs
                    .iter()
                    .map(|d| (d.doc_id.clone(), d.title.clone()))
                    .collect()
            })
            .unwrap_or_default();

        let delta_snapshot = if args.delta_days > 0 {
            let target = now - Duration::days(args.delta_days);
            prev_topic_state.and_then(|t| select_snapshot_for_delta(&t.history, target))
        } else {
            None
        };

        let hits = gather_hits(
            &qdrant,
            &embed,
            &collections,
            &topic.queries,
            args.k,
            args.max_docs,
            args.max_snippet_chars,
        )
        .await?;

        let current_doc_ids: Vec<String> = hits.iter().map(|h| h.doc_id.clone()).collect();
        let current_set: HashSet<String> = current_doc_ids.iter().cloned().collect();
        let current_titles: HashMap<String, String> = hits
            .iter()
            .map(|h| (h.doc_id.clone(), h.title.clone()))
            .collect();

        let mut added: Vec<String> = current_set
            .difference(&prev_doc_ids)
            .cloned()
            .collect();
        added.sort();
        let mut removed: Vec<String> = prev_doc_ids
            .difference(&current_set)
            .cloned()
            .collect();
        removed.sort();

        let delta_target = now - Duration::days(args.delta_days.max(0));
        let (delta_label, delta_at, delta_added, delta_removed, delta_titles) = compute_delta_changes(
            args.delta_days,
            delta_snapshot,
            delta_target,
            &current_set,
            &current_titles,
        );

        let changes_block = render_changes_block(
            &added,
            &removed,
            &current_titles,
            &last_titles,
            delta_label.as_deref(),
            delta_at,
            &delta_added,
            &delta_removed,
            &delta_titles,
        );

        let brief_md = if let Some(router) = &router {
            let prompt = build_brief_prompt(
                &topic.name,
                &topic.tags,
                &topic.queries,
                &hits,
                &changes_block,
            );
            let meta = RequestMeta::new(
                false,
                true,
                false,
                prompt.len() / 4,
                false,
                false,
                false,
            );
            let (client, tier) = router.choose_with_limits(&meta, &llm_stats);
            let output = client.complete(&prompt).await?;
            llm_stats.record_call(tier.as_str(), output.tokens_in_est as u32, output.tokens_out_est as u32);
            let sources_len = hits.len().min(20);
            let report = analyze_citations(&output.text, sources_len);

            if !report.invalid.is_empty() {
                let msg = format!(
                    "invalid citations: {:?} (sources 1..={})",
                    report.invalid, sources_len
                );
                if args.strict_citations {
                    anyhow::bail!("{msg}");
                } else {
                    warn!(topic = %topic.name, "{msg}");
                }
            }

            if args.min_citations > 0 && report.total < args.min_citations {
                let msg = format!(
                    "insufficient citations: total={} < min_citations={} (unique={})",
                    report.total, args.min_citations, report.unique
                );
                if args.strict_citations {
                    anyhow::bail!("{msg}");
                } else {
                    warn!(topic = %topic.name, "{msg}");
                }
            }

            output.text
        } else {
            render_retrieval_report(
                &topic.name,
                &topic.tags,
                &topic.queries,
                &hits,
                &changes_block,
            )
        };

        let topic_dir = out_dir.join(&topic.name);
        std::fs::create_dir_all(&topic_dir)
            .with_context(|| format!("failed to create {}", topic_dir.display()))?;

        let date = now.format("%Y-%m-%d").to_string();
        let dated_path = topic_dir.join(format!("{date}.md"));
        let latest_path = topic_dir.join("latest.md");
        std::fs::write(&dated_path, &brief_md)
            .with_context(|| format!("failed to write {}", dated_path.display()))?;
        std::fs::write(&latest_path, &brief_md)
            .with_context(|| format!("failed to write {}", latest_path.display()))?;

        let snapshot = TopicSnapshot {
            at: now,
            docs: hits.iter().map(DocRef::from_hit).collect(),
        };

        let topic_state = state.topics.entry(topic.name.clone()).or_default();
        topic_state.last_run = Some(now);
        topic_state.doc_ids = current_doc_ids;
        topic_state.history.push(snapshot);
        topic_state.history.sort_by_key(|s| s.at);
        topic_state.history.truncate(60);
    }

    state.last_run = Some(now);
    state.save(&state_path)?;

    if !args.no_llm {
        info!(
            total_calls = llm_stats.total_calls(),
            total_tokens = llm_stats.total_tokens(),
            estimated_cost_usd = llm_stats.estimated_cost_usd(),
            "brief generation complete"
        );
    }
    Ok(())
}

async fn gather_hits(
    qdrant: &QdrantClient,
    embed: &EmbeddingClient,
    collections: &[String],
    queries: &[String],
    k: usize,
    max_docs: usize,
    max_snippet_chars: usize,
) -> Result<Vec<DocHit>> {
    let mut by_doc: HashMap<String, DocHit> = HashMap::new();

    for q in queries {
        let q = q.trim();
        if q.is_empty() {
            continue;
        }

        let vectors = embed.embed_batch(&[q.to_string()]).await?;
        let query_vec = vectors
            .first()
            .cloned()
            .ok_or_else(|| anyhow::anyhow!("embedding returned empty vector list"))?;

        for collection in collections {
            let hits = qdrant
                .search_points(collection, &query_vec, k, true)
                .await
                .with_context(|| format!("qdrant search failed for collection={collection}"))?;

            for hit in hits {
                let score = hit.get("score").and_then(|v| v.as_f64()).unwrap_or(0.0);
                let Some(payload) = hit.get("payload") else { continue };

                let (doc_id, title, url, doi, snippet) =
                    extract_doc_fields(collection, payload, max_snippet_chars);
                if doc_id.is_empty() {
                    continue;
                }

                match by_doc.get(&doc_id) {
                    Some(prev) if prev.score >= score => {}
                    _ => {
                        by_doc.insert(
                            doc_id.clone(),
                            DocHit {
                                doc_id,
                                title,
                                url,
                                doi,
                                collection: collection.clone(),
                                score,
                                snippet,
                            },
                        );
                    }
                }
            }
        }
    }

    let mut out: Vec<DocHit> = by_doc.into_values().collect();
    out.sort_by(|a, b| b.score.total_cmp(&a.score));
    out.truncate(max_docs.clamp(1, 5_000));
    Ok(out)
}

fn extract_doc_fields(
    collection: &str,
    payload: &serde_json::Value,
    max_snippet_chars: usize,
) -> (String, String, Option<String>, Option<String>, String) {
    let doc_id = payload
        .get("doc_id")
        .and_then(|v| v.as_str())
        .map(|s| s.to_string())
        .or_else(|| {
            let repo = payload.get("repo").and_then(|v| v.as_str())?;
            let file = payload.get("file").and_then(|v| v.as_str())?;
            Some(format!("repo:{repo}/{file}"))
        })
        .unwrap_or_default();

    let title = payload
        .get("title")
        .and_then(|v| v.as_str())
        .map(|s| s.to_string())
        .unwrap_or_else(|| doc_id.clone());

    let doi = payload
        .get("doi")
        .and_then(|v| v.as_str())
        .map(|s| s.to_string());

    let url = payload
        .get("meta")
        .and_then(|m| m.get("final_url").or_else(|| m.get("url")))
        .and_then(|v| v.as_str())
        .map(|s| s.to_string())
        .or_else(|| {
            if doc_id.starts_with("http://") || doc_id.starts_with("https://") {
                Some(doc_id.clone())
            } else {
                None
            }
        });

    let snippet = payload
        .get("text")
        .and_then(|v| v.as_str())
        .unwrap_or("")
        .chars()
        .take(max_snippet_chars)
        .collect::<String>();

    let _ = collection; // reserved for future per-collection overrides
    (doc_id, title, url, doi, snippet)
}

fn build_brief_prompt(
    topic_name: &str,
    tags: &[String],
    queries: &[String],
    hits: &[DocHit],
    changes_block: &str,
) -> String {
    let mut sources = String::new();
    for (idx, h) in hits.iter().take(20).enumerate() {
        let n = idx + 1;
        let url = h.url.clone().unwrap_or_else(|| "n/a".to_string());
        let doi = h.doi.clone().unwrap_or_else(|| "n/a".to_string());
        sources.push_str(&format!(
            "[{n}] {title}\n    doc_id: {doc_id}\n    url: {url}\n    doi: {doi}\n    collection: {collection}\n\n",
            n = n,
            title = h.title,
            doc_id = h.doc_id,
            url = url,
            doi = doi,
            collection = h.collection,
        ));
    }

    let mut snippets = String::new();
    for (idx, h) in hits.iter().take(20).enumerate() {
        let n = idx + 1;
        snippets.push_str(&format!(
            "[{n}] {title}\n{snippet}\n\n",
            n = n,
            title = h.title,
            snippet = h.snippet
        ));
    }

    let tags = if tags.is_empty() {
        "n/a".to_string()
    } else {
        tags.join(", ")
    };
    let queries_rendered = queries
        .iter()
        .filter(|q| !q.trim().is_empty())
        .map(|q| format!("- {q}"))
        .collect::<Vec<_>>()
        .join("\n");

    format!(
        "You are BEAGLE ResearchOps.\n\
Write a concise research brief in Markdown for the topic below.\n\
\n\
Rules:\n\
- Use only the provided sources/snippets.\n\
- Cite claims with bracket citations like [1], [2].\n\
- If evidence is insufficient, say so explicitly.\n\
- Keep it practical (key findings + next actions).\n\
\n\
Topic: {topic}\n\
Tags: {tags}\n\
Queries:\n{queries}\n\
\n\
Changes:\n{changes}\n\
\n\
## Sources (numbered)\n\
{sources}\n\
## Snippets\n\
{snippets}\n",
        topic = topic_name,
        tags = tags,
        queries = queries_rendered,
        changes = changes_block,
        sources = sources,
        snippets = snippets
    )
}

fn render_retrieval_report(
    topic_name: &str,
    tags: &[String],
    queries: &[String],
    hits: &[DocHit],
    changes_block: &str,
) -> String {
    let tags = if tags.is_empty() {
        "n/a".to_string()
    } else {
        tags.join(", ")
    };

    let queries_rendered = queries
        .iter()
        .filter(|q| !q.trim().is_empty())
        .map(|q| format!("- {q}"))
        .collect::<Vec<_>>()
        .join("\n");

    let mut out = String::new();
    out.push_str(&format!("# {topic}\n\n", topic = topic_name));
    out.push_str(&format!("- Tags: {tags}\n"));
    out.push_str(&format!("- Changes:\n\n{changes_block}\n\n"));
    out.push_str("## Queries\n");
    out.push_str(&queries_rendered);
    out.push_str("\n\n## Top Sources\n");
    for (idx, h) in hits.iter().take(20).enumerate() {
        let n = idx + 1;
        let url = h.url.clone().unwrap_or_else(|| "n/a".to_string());
        out.push_str(&format!(
            "- [{n}] {title} (`{doc_id}`) — {url}\n",
            n = n,
            title = h.title,
            doc_id = h.doc_id,
            url = url
        ));
    }
    out.push_str("\n## Snippets\n");
    for (idx, h) in hits.iter().take(20).enumerate() {
        let n = idx + 1;
        out.push_str(&format!("\n### [{n}] {title}\n\n{snippet}\n", n = n, title = h.title, snippet = h.snippet));
    }
    out
}

impl DocRef {
    fn from_hit(hit: &DocHit) -> Self {
        Self {
            doc_id: hit.doc_id.clone(),
            title: hit.title.clone(),
            url: hit.url.clone(),
            doi: hit.doi.clone(),
            collection: hit.collection.clone(),
        }
    }
}

fn select_snapshot_for_delta<'a>(
    history: &'a [TopicSnapshot],
    target: DateTime<Utc>,
) -> Option<&'a TopicSnapshot> {
    history
        .iter()
        .filter(|s| s.at <= target)
        .max_by_key(|s| s.at)
        .or_else(|| history.iter().min_by_key(|s| s.at))
}

fn compute_delta_changes(
    delta_days: i64,
    snapshot: Option<&TopicSnapshot>,
    target: DateTime<Utc>,
    current_set: &HashSet<String>,
    current_titles: &HashMap<String, String>,
) -> (
    Option<String>,
    Option<DateTime<Utc>>,
    Vec<String>,
    Vec<String>,
    HashMap<String, String>,
) {
    if delta_days <= 0 {
        return (None, None, vec![], vec![], HashMap::new());
    }

    let label = Some(format!(
        "Since {delta_days}d ago (target {})",
        target.format("%Y-%m-%d")
    ));

    let Some(snapshot) = snapshot else {
        return (label, None, vec![], vec![], HashMap::new());
    };

    let delta_set: HashSet<String> = snapshot.docs.iter().map(|d| d.doc_id.clone()).collect();

    let mut added: Vec<String> = current_set.difference(&delta_set).cloned().collect();
    added.sort();
    let mut removed: Vec<String> = delta_set.difference(current_set).cloned().collect();
    removed.sort();

    let mut titles: HashMap<String, String> = snapshot
        .docs
        .iter()
        .map(|d| (d.doc_id.clone(), d.title.clone()))
        .collect();
    for (doc_id, title) in current_titles {
        titles.insert(doc_id.clone(), title.clone());
    }

    (label, Some(snapshot.at), added, removed, titles)
}

fn format_doc_list(ids: &[String], titles: &HashMap<String, String>) -> String {
    if ids.is_empty() {
        return "none".to_string();
    }

    ids.iter()
        .map(|id| match titles.get(id) {
            Some(title) => format!("- {id} — {title}"),
            None => format!("- {id}"),
        })
        .collect::<Vec<_>>()
        .join("\n")
}

fn render_changes_block(
    added: &[String],
    removed: &[String],
    current_titles: &HashMap<String, String>,
    last_titles: &HashMap<String, String>,
    delta_label: Option<&str>,
    delta_at: Option<DateTime<Utc>>,
    delta_added: &[String],
    delta_removed: &[String],
    delta_titles: &HashMap<String, String>,
) -> String {
    let mut out = String::new();
    out.push_str("Since last run:\n");
    out.push_str("Added:\n");
    out.push_str(&format_doc_list(added, current_titles));
    out.push_str("\n\nRemoved:\n");
    out.push_str(&format_doc_list(removed, last_titles));

    if let Some(label) = delta_label {
        let suffix = delta_at
            .map(|at| format!(" (snapshot {})", at.format("%Y-%m-%d")))
            .unwrap_or_else(|| " (no historical snapshot yet)".to_string());
        out.push_str("\n\n");
        out.push_str(label);
        out.push_str(&suffix);
        out.push_str(":\nAdded:\n");
        out.push_str(&format_doc_list(delta_added, delta_titles));
        out.push_str("\n\nRemoved:\n");
        out.push_str(&format_doc_list(delta_removed, delta_titles));
    }

    out
}

fn parse_collections(arg: Option<&str>) -> Vec<String> {
    let raw = arg
        .map(|s| s.to_string())
        .or_else(|| std::env::var("BEAGLE_QDRANT_COLLECTIONS").ok());

    if let Some(raw) = raw {
        let mut out = Vec::new();
        for part in raw.split(',') {
            let p = part.trim();
            if !p.is_empty() {
                out.push(p.to_string());
            }
        }
        if !out.is_empty() {
            return out;
        }
    }

    vec![
        "darwin-papers".to_string(),
        "darwin-docs".to_string(),
        "darwin-books".to_string(),
        "darwin-repos".to_string(),
    ]
}

fn expand_tilde(path: &str) -> PathBuf {
    if let Some(rest) = path.strip_prefix("~/") {
        if let Some(home) = std::env::var_os("HOME") {
            return PathBuf::from(home).join(rest);
        }
    }
    PathBuf::from(path)
}
