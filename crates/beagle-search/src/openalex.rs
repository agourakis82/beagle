//! OpenAlex search client
//!
//! OpenAlex provides a large, open bibliographic index. This client supports:
//! - Search works via `/works?search=...`
//! - Optional polite usage via `mailto=` (set `BEAGLE_CONTACT_EMAIL` or `OPENALEX_MAILTO`)
//! - Basic date filtering when `SearchQuery.date_range` is set
//!
//! Docs: https://docs.openalex.org/

use crate::types::{Author, Paper, SearchError, SearchQuery, SearchResult};
use crate::SearchClient;
use async_trait::async_trait;
use chrono::{NaiveDate, TimeZone, Utc};
use governor::{Quota, RateLimiter};
use serde::Deserialize;
use std::num::NonZeroU32;
use std::sync::Arc;
use std::time::Instant;
use tracing::{debug, info, warn};

const OPENALEX_BASE_URL: &str = "https://api.openalex.org";

pub struct OpenAlexClient {
    client: reqwest::Client,
    mailto: Option<String>,
    rate_limiter: Arc<
        RateLimiter<
            governor::state::direct::NotKeyed,
            governor::state::InMemoryState,
            governor::clock::DefaultClock,
        >,
    >,
}

impl OpenAlexClient {
    pub fn new(mailto: Option<String>) -> Self {
        // OpenAlex doesn't publish a strict global limit; be polite by default.
        let quota = Quota::per_second(NonZeroU32::new(5).unwrap());
        let rate_limiter = Arc::new(RateLimiter::direct(quota));

        Self {
            client: reqwest::Client::new(),
            mailto,
            rate_limiter,
        }
    }

    pub fn from_env() -> Self {
        let mailto = std::env::var("OPENALEX_MAILTO")
            .ok()
            .or_else(|| std::env::var("BEAGLE_CONTACT_EMAIL").ok());
        if let Some(ref m) = mailto {
            info!(mailto = %m, "OpenAlex mailto configured");
        } else {
            warn!("OpenAlex mailto not configured (set BEAGLE_CONTACT_EMAIL or OPENALEX_MAILTO)");
        }
        Self::new(mailto)
    }

    fn build_filter(query: &SearchQuery) -> Option<String> {
        let range = query.date_range.as_ref()?;
        let from = range.from.format("%Y-%m-%d").to_string();
        let to = range.to.format("%Y-%m-%d").to_string();
        Some(format!(
            "from_publication_date:{from},to_publication_date:{to}"
        ))
    }

    fn parse_date(s: &str) -> Option<chrono::DateTime<Utc>> {
        let date = NaiveDate::parse_from_str(s, "%Y-%m-%d").ok()?;
        Some(Utc.from_utc_datetime(&date.and_hms_opt(0, 0, 0)?))
    }

    fn normalize_openalex_id(id: &str) -> String {
        // OpenAlex IDs are typically URLs (https://openalex.org/W...)
        id.rsplit('/')
            .next()
            .filter(|s| !s.trim().is_empty())
            .unwrap_or(id)
            .to_string()
    }

    fn normalize_doi(doi: &str) -> String {
        doi.trim()
            .strip_prefix("https://doi.org/")
            .or_else(|| doi.trim().strip_prefix("http://doi.org/"))
            .or_else(|| doi.trim().strip_prefix("doi:"))
            .unwrap_or(doi.trim())
            .to_string()
    }

    fn authors_from_authorships(authorships: &[OpenAlexAuthorship]) -> Vec<Author> {
        authorships
            .iter()
            .filter_map(|a| a.author.as_ref()?.display_name.as_deref())
            .map(|display| {
                let parts: Vec<&str> = display.split_whitespace().collect();
                if parts.len() >= 2 {
                    let last = parts[parts.len() - 1].to_string();
                    let first = parts[..parts.len() - 1].join(" ");
                    Author {
                        first_name: Some(first),
                        last_name: last,
                        initials: None,
                        affiliation: None,
                    }
                } else {
                    Author::new(display.to_string())
                }
            })
            .collect()
    }

    fn reconstruct_abstract(index: &serde_json::Value) -> Option<String> {
        let obj = index.as_object()?;
        let mut max_pos: usize = 0;
        for positions in obj.values() {
            let Some(arr) = positions.as_array() else {
                continue;
            };
            for p in arr {
                if let Some(u) = p.as_u64() {
                    max_pos = max_pos.max(u as usize);
                }
            }
        }

        if max_pos == 0 && obj.is_empty() {
            return None;
        }

        let mut words: Vec<Option<&str>> = vec![None; max_pos.saturating_add(1)];
        for (word, positions) in obj.iter() {
            let Some(arr) = positions.as_array() else {
                continue;
            };
            for p in arr {
                let Some(u) = p.as_u64() else {
                    continue;
                };
                let idx = u as usize;
                if idx < words.len() {
                    words[idx] = Some(word.as_str());
                }
            }
        }

        let mut out = String::new();
        for w in words.into_iter().flatten() {
            if !out.is_empty() {
                out.push(' ');
            }
            out.push_str(w);
        }

        if out.trim().is_empty() {
            None
        } else {
            Some(out)
        }
    }
}

#[async_trait]
impl SearchClient for OpenAlexClient {
    async fn search(&self, query: &SearchQuery) -> Result<SearchResult, SearchError> {
        self.rate_limiter.until_ready().await;
        let start = Instant::now();

        let per_page = query.max_results.clamp(1, 200);
        let page = (query.offset / per_page).saturating_add(1);

        let mut req = self
            .client
            .get(format!("{OPENALEX_BASE_URL}/works"))
            .query(&[
                ("search", query.query.as_str()),
                ("per-page", &per_page.to_string()),
                ("page", &page.to_string()),
            ]);

        if let Some(filter) = Self::build_filter(query) {
            req = req.query(&[("filter", filter)]);
        }

        if let Some(ref mailto) = self.mailto {
            req = req.query(&[("mailto", mailto)]);
        }

        debug!(q = %query.query, per_page, page, "OpenAlex search");
        let resp = req
            .send()
            .await?
            .error_for_status()
            .map_err(|e| SearchError::ApiError(format!("OpenAlex search failed: {e}")))?;

        let body: OpenAlexWorksResponse = resp
            .json()
            .await
            .map_err(|e| SearchError::ParseError(format!("OpenAlex JSON parse error: {e}")))?;

        let mut papers = Vec::new();
        for w in body.results {
            let Some(raw_id) = w.id.as_deref() else {
                continue;
            };
            let id = Self::normalize_openalex_id(raw_id);
            let title = w
                .display_name
                .or(w.title)
                .unwrap_or_else(|| "Untitled".to_string());

            let mut paper = Paper::new(id.clone(), "openalex".to_string(), title);

            paper.authors = w
                .authorships
                .as_deref()
                .map(Self::authors_from_authorships)
                .unwrap_or_default();

            paper.published_date = w.publication_date.as_deref().and_then(Self::parse_date);

            paper.journal = w.host_venue.and_then(|h| h.display_name);

            paper.doi = w.doi.map(|d| Self::normalize_doi(&d));

            paper.citation_count = w.cited_by_count;

            paper.url = w
                .primary_location
                .as_ref()
                .and_then(|l| l.landing_page_url.clone())
                .or_else(|| Some(raw_id.to_string()));

            paper.pdf_url = w.best_oa_location.as_ref().and_then(|l| l.pdf_url.clone());

            paper.abstract_text = w
                .abstract_inverted_index
                .as_ref()
                .and_then(Self::reconstruct_abstract)
                .unwrap_or_default();

            if let Some(concepts) = w.concepts {
                let mut cats = Vec::new();
                for c in concepts.into_iter().take(8) {
                    if let Some(name) = c.display_name {
                        cats.push(name);
                    }
                }
                paper.categories = cats;
            }

            paper.metadata = serde_json::json!({
                "openalex_id": raw_id,
                "openalex_url": raw_id,
            });

            papers.push(paper);
        }

        Ok(SearchResult {
            total_count: body.meta.and_then(|m| m.count).unwrap_or(papers.len()),
            query: query.query.clone(),
            backend: "openalex".to_string(),
            search_time_ms: start.elapsed().as_millis() as u64,
            papers,
        })
    }

    async fn fetch_paper(&self, id: &str) -> Result<Paper, SearchError> {
        self.rate_limiter.until_ready().await;
        let start = Instant::now();

        // Accept either W... id or full OpenAlex URL.
        let work_id = if id.starts_with("http://") || id.starts_with("https://") {
            id.to_string()
        } else {
            format!("{OPENALEX_BASE_URL}/works/{id}")
        };

        let mut req = self.client.get(&work_id);
        if let Some(ref mailto) = self.mailto {
            req = req.query(&[("mailto", mailto)]);
        }

        let resp = req
            .send()
            .await?
            .error_for_status()
            .map_err(|e| SearchError::ApiError(format!("OpenAlex fetch failed: {e}")))?;

        let w: OpenAlexWork = resp
            .json()
            .await
            .map_err(|e| SearchError::ParseError(format!("OpenAlex JSON parse error: {e}")))?;

        let raw_id =
            w.id.clone()
                .unwrap_or_else(|| work_id.trim_end_matches('/').to_string());
        let norm_id = Self::normalize_openalex_id(&raw_id);
        let title = w
            .display_name
            .or(w.title)
            .unwrap_or_else(|| "Untitled".to_string());

        let mut paper = Paper::new(norm_id, "openalex".to_string(), title);
        paper.authors = w
            .authorships
            .as_deref()
            .map(Self::authors_from_authorships)
            .unwrap_or_default();
        paper.published_date = w.publication_date.as_deref().and_then(Self::parse_date);
        paper.journal = w.host_venue.and_then(|h| h.display_name);
        paper.doi = w.doi.map(|d| Self::normalize_doi(&d));
        paper.citation_count = w.cited_by_count;
        paper.url = w
            .primary_location
            .as_ref()
            .and_then(|l| l.landing_page_url.clone())
            .or_else(|| Some(raw_id.clone()));
        paper.pdf_url = w.best_oa_location.as_ref().and_then(|l| l.pdf_url.clone());
        paper.abstract_text = w
            .abstract_inverted_index
            .as_ref()
            .and_then(Self::reconstruct_abstract)
            .unwrap_or_default();
        paper.metadata = serde_json::json!({
            "openalex_id": raw_id,
            "fetch_time_ms": start.elapsed().as_millis() as u64,
        });
        Ok(paper)
    }

    fn backend_name(&self) -> &str {
        "openalex"
    }
}

#[derive(Debug, Deserialize)]
struct OpenAlexWorksResponse {
    results: Vec<OpenAlexWork>,
    #[serde(default)]
    meta: Option<OpenAlexMeta>,
}

#[derive(Debug, Deserialize)]
struct OpenAlexMeta {
    #[serde(default)]
    count: Option<usize>,
}

#[derive(Debug, Deserialize)]
struct OpenAlexWork {
    #[serde(default)]
    id: Option<String>,
    #[serde(default)]
    doi: Option<String>,
    #[serde(default)]
    title: Option<String>,
    #[serde(default)]
    display_name: Option<String>,
    #[serde(default)]
    publication_date: Option<String>,
    #[serde(default)]
    cited_by_count: Option<usize>,
    #[serde(default)]
    host_venue: Option<OpenAlexHostVenue>,
    #[serde(default)]
    primary_location: Option<OpenAlexLocation>,
    #[serde(default)]
    best_oa_location: Option<OpenAlexLocation>,
    #[serde(default)]
    authorships: Option<Vec<OpenAlexAuthorship>>,
    #[serde(default)]
    concepts: Option<Vec<OpenAlexConcept>>,
    #[serde(default)]
    abstract_inverted_index: Option<serde_json::Value>,
}

#[derive(Debug, Deserialize)]
struct OpenAlexHostVenue {
    #[serde(default)]
    display_name: Option<String>,
}

#[derive(Debug, Deserialize)]
struct OpenAlexLocation {
    #[serde(default)]
    landing_page_url: Option<String>,
    #[serde(default)]
    pdf_url: Option<String>,
}

#[derive(Debug, Deserialize)]
struct OpenAlexAuthorship {
    #[serde(default)]
    author: Option<OpenAlexAuthor>,
}

#[derive(Debug, Deserialize)]
struct OpenAlexAuthor {
    #[serde(default)]
    display_name: Option<String>,
}

#[derive(Debug, Deserialize)]
struct OpenAlexConcept {
    #[serde(default)]
    display_name: Option<String>,
}
