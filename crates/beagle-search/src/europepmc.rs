//! Europe PMC search client
//!
//! Europe PMC aggregates biomedical literature (PubMed + full text sources).
//! This client supports basic search via the JSON API:
//! - `/search?query=...&format=json&pageSize=...`
//!
//! Docs: https://europepmc.org/RestfulWebService

use crate::types::{Author, Paper, SearchError, SearchQuery, SearchResult};
use crate::SearchClient;
use async_trait::async_trait;
use chrono::{NaiveDate, TimeZone, Utc};
use governor::{Quota, RateLimiter};
use serde::Deserialize;
use std::num::NonZeroU32;
use std::sync::Arc;
use std::time::Instant;
use tracing::{debug, warn};

const EUROPEPMC_BASE_URL: &str = "https://www.ebi.ac.uk/europepmc/webservices/rest";

pub struct EuropePmcClient {
    client: reqwest::Client,
    rate_limiter: Arc<
        RateLimiter<
            governor::state::direct::NotKeyed,
            governor::state::InMemoryState,
            governor::clock::DefaultClock,
        >,
    >,
}

impl EuropePmcClient {
    pub fn new() -> Self {
        let quota = Quota::per_second(NonZeroU32::new(3).unwrap());
        let rate_limiter = Arc::new(RateLimiter::direct(quota));
        Self {
            client: reqwest::Client::new(),
            rate_limiter,
        }
    }

    fn parse_date(s: &str) -> Option<chrono::DateTime<Utc>> {
        if let Ok(date) = NaiveDate::parse_from_str(s, "%Y-%m-%d") {
            return Some(Utc.from_utc_datetime(&date.and_hms_opt(0, 0, 0)?));
        }
        // Fallback: year-only
        if let Ok(year) = s.parse::<i32>() {
            let date = NaiveDate::from_ymd_opt(year, 1, 1)?;
            return Some(Utc.from_utc_datetime(&date.and_hms_opt(0, 0, 0)?));
        }
        None
    }

    fn parse_authors(author_string: &str) -> Vec<Author> {
        // Common format: "Smith A, Jones B, ..."
        author_string
            .split(',')
            .map(|s| s.trim())
            .filter(|s| !s.is_empty())
            .map(|s| {
                // "Last I" or "Last First"
                let mut parts = s.split_whitespace();
                let last = parts.next().unwrap_or("Unknown").to_string();
                let rest = parts.collect::<Vec<_>>().join(" ");
                if rest.is_empty() {
                    Author::new(last)
                } else {
                    Author {
                        first_name: Some(rest),
                        last_name: last,
                        initials: None,
                        affiliation: None,
                    }
                }
            })
            .collect()
    }
}

impl Default for EuropePmcClient {
    fn default() -> Self {
        Self::new()
    }
}

#[async_trait]
impl SearchClient for EuropePmcClient {
    async fn search(&self, query: &SearchQuery) -> Result<SearchResult, SearchError> {
        self.rate_limiter.until_ready().await;
        let start = Instant::now();

        let page_size = query.max_results.clamp(1, 1000);
        let page = (query.offset / page_size).saturating_add(1);

        // EuropePMC supports date filters via query syntax. Keep it simple for now.
        let mut q = query.query.clone();
        if let Some(range) = &query.date_range {
            let from = range.from.format("%Y-%m-%d");
            let to = range.to.format("%Y-%m-%d");
            q = format!("({q}) AND FIRST_PDATE:[{from} TO {to}]");
        }

        debug!(q = %q, page_size, page, "EuropePMC search");
        let resp = self
            .client
            .get(format!("{EUROPEPMC_BASE_URL}/search"))
            .query(&[
                ("query", q.as_str()),
                ("format", "json"),
                ("pageSize", &page_size.to_string()),
                ("page", &page.to_string()),
            ])
            .send()
            .await?
            .error_for_status()
            .map_err(|e| SearchError::ApiError(format!("EuropePMC search failed: {e}")))?;

        let body: EuropePmcResponse = resp
            .json()
            .await
            .map_err(|e| SearchError::ParseError(format!("EuropePMC JSON parse error: {e}")))?;

        let total = body
            .hit_count
            .and_then(|s| s.parse::<usize>().ok())
            .unwrap_or(0);

        let mut papers = Vec::new();
        let results = body
            .result_list
            .map(|l| l.results)
            .unwrap_or_default();

        for r in results {
            let epmc_source = r.source.clone().unwrap_or_else(|| "unknown".to_string());
            let id = r
                .pmid
                .clone()
                .or(r.pmcid.clone())
                .or(r.doi.clone())
                .or(r.id.clone())
                .unwrap_or_else(|| "unknown".to_string());

            let title = r.title.clone().unwrap_or_else(|| "Untitled".to_string());
            let mut paper = Paper::new(id.clone(), "europepmc".to_string(), title);

            paper.abstract_text = r.abstract_text.unwrap_or_default();
            paper.journal = r.journal_title;
            paper.doi = r.doi.clone();
            paper.published_date = r
                .first_publication_date
                .as_deref()
                .and_then(Self::parse_date)
                .or_else(|| r.pub_year.as_deref().and_then(Self::parse_date));
            paper.authors = r
                .author_string
                .as_deref()
                .map(Self::parse_authors)
                .unwrap_or_default();
            paper.citation_count = r.cited_by_count.and_then(|s| s.parse::<usize>().ok());
            paper.url = Some(format!("https://europepmc.org/article/{}/{}", epmc_source, id));

            paper.metadata = serde_json::json!({
                "europepmc_source": epmc_source,
                "pmid": r.pmid,
                "pmcid": r.pmcid,
            });

            papers.push(paper);
        }

        let papers_len = papers.len();
        Ok(SearchResult {
            papers,
            total_count: if total > 0 { total } else { papers_len },
            query: query.query.clone(),
            backend: "europepmc".to_string(),
            search_time_ms: start.elapsed().as_millis() as u64,
        })
    }

    async fn fetch_paper(&self, id: &str) -> Result<Paper, SearchError> {
        // EuropePMC doesn't have a single canonical fetch-by-id endpoint across all sources.
        // Use a targeted search.
        let q = format!("EXT_ID:{id}");
        let query = SearchQuery::new(q).with_max_results(1);
        let result = self.search(&query).await?;
        result
            .papers
            .into_iter()
            .next()
            .ok_or_else(|| SearchError::ApiError("EuropePMC: no results for id".into()))
    }

    fn backend_name(&self) -> &str {
        "europepmc"
    }
}

#[derive(Debug, Deserialize)]
struct EuropePmcResponse {
    #[serde(rename = "hitCount", default)]
    hit_count: Option<String>,
    #[serde(rename = "resultList", default)]
    result_list: Option<EuropePmcResultList>,
}

#[derive(Debug, Deserialize)]
struct EuropePmcResultList {
    #[serde(rename = "result", default)]
    results: Vec<EuropePmcResult>,
}

#[derive(Debug, Deserialize)]
struct EuropePmcResult {
    #[serde(default)]
    id: Option<String>,
    #[serde(default)]
    source: Option<String>,
    #[serde(default)]
    title: Option<String>,
    #[serde(rename = "authorString", default)]
    author_string: Option<String>,
    #[serde(rename = "abstractText", default)]
    abstract_text: Option<String>,
    #[serde(rename = "journalTitle", default)]
    journal_title: Option<String>,
    #[serde(rename = "pubYear", default)]
    pub_year: Option<String>,
    #[serde(default)]
    doi: Option<String>,
    #[serde(default)]
    pmid: Option<String>,
    #[serde(default)]
    pmcid: Option<String>,
    #[serde(rename = "firstPublicationDate", default)]
    first_publication_date: Option<String>,
    #[serde(rename = "citedByCount", default)]
    cited_by_count: Option<String>,
}
