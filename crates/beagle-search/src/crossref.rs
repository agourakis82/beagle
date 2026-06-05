//! Crossref search client
//!
//! Crossref provides DOI-centric metadata. This client supports:
//! - Search works via `/works?query=...`
//! - Optional polite usage via `mailto=` (set `BEAGLE_CONTACT_EMAIL` or `CROSSREF_MAILTO`)
//!
//! Docs: https://api.crossref.org/

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

const CROSSREF_BASE_URL: &str = "https://api.crossref.org";

pub struct CrossrefClient {
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

impl CrossrefClient {
    pub fn new(mailto: Option<String>) -> Self {
        let quota = Quota::per_second(NonZeroU32::new(5).unwrap());
        let rate_limiter = Arc::new(RateLimiter::direct(quota));

        Self {
            client: reqwest::Client::new(),
            mailto,
            rate_limiter,
        }
    }

    pub fn from_env() -> Self {
        let mailto = std::env::var("CROSSREF_MAILTO")
            .ok()
            .or_else(|| std::env::var("BEAGLE_CONTACT_EMAIL").ok());
        if let Some(ref m) = mailto {
            info!(mailto = %m, "Crossref mailto configured");
        } else {
            warn!("Crossref mailto not configured (set BEAGLE_CONTACT_EMAIL or CROSSREF_MAILTO)");
        }
        Self::new(mailto)
    }

    fn normalize_doi(doi: &str) -> String {
        doi.trim()
            .strip_prefix("https://doi.org/")
            .or_else(|| doi.trim().strip_prefix("http://doi.org/"))
            .or_else(|| doi.trim().strip_prefix("doi:"))
            .unwrap_or(doi.trim())
            .to_string()
    }

    fn parse_date(parts: &DateParts) -> Option<chrono::DateTime<Utc>> {
        let dp = parts.date_parts.first()?;
        let year = dp.first().copied()?;
        let month = dp.get(1).copied().unwrap_or(1);
        let day = dp.get(2).copied().unwrap_or(1);
        let date = NaiveDate::from_ymd_opt(year, month as u32, day as u32)?;
        Some(Utc.from_utc_datetime(&date.and_hms_opt(0, 0, 0)?))
    }

    fn strip_tags(s: &str) -> String {
        // Crossref may return abstracts as JATS fragments with tags.
        let re = regex::Regex::new(r"<[^>]+>").unwrap();
        re.replace_all(s, " ").split_whitespace().collect::<Vec<_>>().join(" ")
    }
}

#[async_trait]
impl SearchClient for CrossrefClient {
    async fn search(&self, query: &SearchQuery) -> Result<SearchResult, SearchError> {
        self.rate_limiter.until_ready().await;
        let start = Instant::now();

        let rows = query.max_results.clamp(1, 1000);
        let offset = query.offset;

        let mut req = self.client.get(format!("{CROSSREF_BASE_URL}/works")).query(&[
            ("query", query.query.as_str()),
            ("rows", &rows.to_string()),
            ("offset", &offset.to_string()),
        ]);

        if let Some(ref mailto) = self.mailto {
            req = req.query(&[("mailto", mailto)]);
        }

        debug!(q = %query.query, rows, offset, "Crossref search");
        let resp = req
            .send()
            .await?
            .error_for_status()
            .map_err(|e| SearchError::ApiError(format!("Crossref search failed: {e}")))?;

        let body: CrossrefResponse = resp
            .json()
            .await
            .map_err(|e| SearchError::ParseError(format!("Crossref JSON parse error: {e}")))?;

        let total_count = body
            .message
            .total_results
            .unwrap_or(body.message.items.len() as u64) as usize;

        let mut papers = Vec::new();
        for item in body.message.items {
            let Some(doi_raw) = item.doi.as_deref() else { continue };
            let doi = Self::normalize_doi(doi_raw);

            let title = item
                .title
                .as_ref()
                .and_then(|t| t.first())
                .cloned()
                .unwrap_or_else(|| "Untitled".to_string());

            let mut paper = Paper::new(doi.clone(), "crossref".to_string(), title);
            paper.doi = Some(doi.clone());
            paper.journal = item
                .container_title
                .as_ref()
                .and_then(|t| t.first())
                .cloned();

            paper.published_date = item
                .issued
                .as_ref()
                .and_then(Self::parse_date)
                .or_else(|| item.published_online.as_ref().and_then(Self::parse_date))
                .or_else(|| item.published_print.as_ref().and_then(Self::parse_date));

            paper.authors = item
                .author
                .unwrap_or_default()
                .into_iter()
                .filter_map(|a| a.family.map(|last| (a.given, last)))
                .map(|(given, last)| Author {
                    first_name: given,
                    last_name: last,
                    initials: None,
                    affiliation: None,
                })
                .collect();

            paper.abstract_text = item
                .abstract_text
                .as_deref()
                .map(Self::strip_tags)
                .unwrap_or_default();

            paper.categories = item.subject.unwrap_or_default();

            paper.citation_count = item.is_referenced_by_count;

            paper.url = item.url.or_else(|| Some(format!("https://doi.org/{doi}")));

            paper.metadata = serde_json::json!({
                "type": item.item_type,
                "publisher": item.publisher,
            });

            papers.push(paper);
        }

        Ok(SearchResult {
            papers,
            total_count,
            query: query.query.clone(),
            backend: "crossref".to_string(),
            search_time_ms: start.elapsed().as_millis() as u64,
        })
    }

    async fn fetch_paper(&self, id: &str) -> Result<Paper, SearchError> {
        self.rate_limiter.until_ready().await;
        let start = Instant::now();

        let doi = Self::normalize_doi(id);
        let mut req = self
            .client
            .get(format!("{CROSSREF_BASE_URL}/works/{doi}"));
        if let Some(ref mailto) = self.mailto {
            req = req.query(&[("mailto", mailto)]);
        }

        let resp = req
            .send()
            .await?
            .error_for_status()
            .map_err(|e| SearchError::ApiError(format!("Crossref fetch failed: {e}")))?;

        let body: CrossrefWorkResponse = resp
            .json()
            .await
            .map_err(|e| SearchError::ParseError(format!("Crossref JSON parse error: {e}")))?;

        let item = body.message;
        let title = item
            .title
            .as_ref()
            .and_then(|t| t.first())
            .cloned()
            .unwrap_or_else(|| "Untitled".to_string());

        let mut paper = Paper::new(doi.clone(), "crossref".to_string(), title);
        paper.doi = Some(doi.clone());
        paper.journal = item
            .container_title
            .as_ref()
            .and_then(|t| t.first())
            .cloned();
        paper.published_date = item
            .issued
            .as_ref()
            .and_then(Self::parse_date)
            .or_else(|| item.published_online.as_ref().and_then(Self::parse_date))
            .or_else(|| item.published_print.as_ref().and_then(Self::parse_date));
        paper.authors = item
            .author
            .unwrap_or_default()
            .into_iter()
            .filter_map(|a| a.family.map(|last| (a.given, last)))
            .map(|(given, last)| Author {
                first_name: given,
                last_name: last,
                initials: None,
                affiliation: None,
            })
            .collect();
        paper.abstract_text = item
            .abstract_text
            .as_deref()
            .map(Self::strip_tags)
            .unwrap_or_default();
        paper.categories = item.subject.unwrap_or_default();
        paper.citation_count = item.is_referenced_by_count;
        paper.url = item.url.or_else(|| Some(format!("https://doi.org/{doi}")));
        paper.metadata = serde_json::json!({
            "fetch_time_ms": start.elapsed().as_millis() as u64,
            "type": item.item_type,
            "publisher": item.publisher,
        });
        Ok(paper)
    }

    fn backend_name(&self) -> &str {
        "crossref"
    }
}

#[derive(Debug, Deserialize)]
struct CrossrefResponse {
    message: CrossrefMessage,
}

#[derive(Debug, Deserialize)]
struct CrossrefWorkResponse {
    message: CrossrefItem,
}

#[derive(Debug, Deserialize)]
struct CrossrefMessage {
    #[serde(default)]
    items: Vec<CrossrefItem>,
    #[serde(rename = "total-results")]
    total_results: Option<u64>,
}

#[derive(Debug, Deserialize)]
struct CrossrefItem {
    #[serde(rename = "DOI")]
    doi: Option<String>,
    #[serde(default)]
    title: Option<Vec<String>>,
    #[serde(default)]
    author: Option<Vec<CrossrefAuthor>>,
    #[serde(default)]
    issued: Option<DateParts>,
    #[serde(rename = "published-online", default)]
    published_online: Option<DateParts>,
    #[serde(rename = "published-print", default)]
    published_print: Option<DateParts>,
    #[serde(rename = "container-title", default)]
    container_title: Option<Vec<String>>,
    #[serde(rename = "URL", default)]
    url: Option<String>,
    #[serde(default)]
    subject: Option<Vec<String>>,
    #[serde(rename = "is-referenced-by-count", default)]
    is_referenced_by_count: Option<usize>,
    #[serde(rename = "type", default)]
    item_type: Option<String>,
    #[serde(default)]
    publisher: Option<String>,
    #[serde(rename = "abstract", default)]
    abstract_text: Option<String>,
}

#[derive(Debug, Deserialize)]
struct CrossrefAuthor {
    #[serde(default)]
    given: Option<String>,
    #[serde(default)]
    family: Option<String>,
}

#[derive(Debug, Deserialize)]
struct DateParts {
    #[serde(rename = "date-parts")]
    date_parts: Vec<Vec<i32>>,
}
