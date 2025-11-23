//! PubMed search client using NCBI E-utilities API
//!
//! Implements search via ESearch + EFetch pipeline:
//! 1. ESearch: Find PubMed IDs matching query
//! 2. EFetch: Retrieve full article metadata
//!
//! Rate limits: Max 3 requests/second without API key, 10 req/s with key
//! Docs: https://www.ncbi.nlm.nih.gov/books/NBK25501/

use crate::types::{Author, Paper, SearchError, SearchQuery, SearchResult};
use crate::SearchClient;
use async_trait::async_trait;
use chrono::{DateTime, Utc};
use governor::{Quota, RateLimiter};
use serde::Deserialize;
use std::num::NonZeroU32;
use std::sync::Arc;
use std::time::Instant;
use tracing::{debug, info, warn};

const PUBMED_BASE_URL: &str = "https://eutils.ncbi.nlm.nih.gov/entrez/eutils";

/// PubMed search client
pub struct PubMedClient {
    client: reqwest::Client,
    api_key: Option<String>,
    rate_limiter: Arc<
        RateLimiter<
            governor::state::direct::NotKeyed,
            governor::state::InMemoryState,
            governor::clock::DefaultClock,
        >,
    >,
}

impl PubMedClient {
    /// Create new PubMed client
    ///
    /// # Arguments
    /// * `api_key` - Optional NCBI API key (increases rate limit to 10 req/s)
    pub fn new(api_key: Option<String>) -> Self {
        // Rate limit: 3 req/s without key, 10 req/s with key
        let requests_per_second = if api_key.is_some() { 10 } else { 3 };
        let quota = Quota::per_second(NonZeroU32::new(requests_per_second).unwrap());
        let rate_limiter = Arc::new(RateLimiter::direct(quota));

        Self {
            client: reqwest::Client::new(),
            api_key,
            rate_limiter,
        }
    }

    /// Create from environment variable NCBI_API_KEY
    pub fn from_env() -> Self {
        let api_key = std::env::var("NCBI_API_KEY").ok();
        if api_key.is_some() {
            info!("Using NCBI API key from environment");
        } else {
            warn!("No NCBI_API_KEY found, using rate-limited API (3 req/s)");
        }
        Self::new(api_key)
    }

    /// Execute ESearch to find PubMed IDs
    async fn esearch(&self, query: &SearchQuery) -> Result<Vec<String>, SearchError> {
        self.rate_limiter.until_ready().await;

        let url = format!("{}/esearch.fcgi", PUBMED_BASE_URL);
        let max_results_str = query.max_results.to_string();
        let offset_str = query.offset.to_string();

        let mut params = vec![
            ("db", "pubmed"),
            ("term", query.query.as_str()),
            ("retmax", max_results_str.as_str()),
            ("retstart", offset_str.as_str()),
            ("retmode", "json"),
        ];

        if let Some(ref key) = self.api_key {
            params.push(("api_key", key.as_str()));
        }

        // Add date range filter if specified
        let date_filter;
        if let Some(ref range) = query.date_range {
            date_filter = format!(
                "{}:{}[dp]",
                range.from.format("%Y/%m/%d"),
                range.to.format("%Y/%m/%d")
            );
            params.push(("term", date_filter.as_str()));
        }

        debug!("PubMed ESearch: {}", query.query);

        let response = self
            .client
            .get(&url)
            .query(&params)
            .send()
            .await?
            .error_for_status()
            .map_err(|e| SearchError::ApiError(format!("ESearch failed: {}", e)))?;

        let result: ESearchResponse = response.json().await?;

        if let Some(error) = result.error {
            return Err(SearchError::ApiError(format!("PubMed error: {}", error)));
        }

        Ok(result
            .esearchresult
            .ok_or_else(|| SearchError::ParseError("Missing esearchresult".into()))?
            .idlist)
    }

    /// Execute EFetch to retrieve full article metadata
    async fn efetch(&self, pmids: &[String]) -> Result<Vec<Paper>, SearchError> {
        if pmids.is_empty() {
            return Ok(Vec::new());
        }

        self.rate_limiter.until_ready().await;

        let id_list = pmids.join(",");
        let mut params = vec![
            ("db", "pubmed"),
            ("id", id_list.as_str()),
            ("retmode", "xml"),
        ];

        if let Some(ref key) = self.api_key {
            params.push(("api_key", key));
        }

        debug!("PubMed EFetch: {} articles", pmids.len());

        let response = self
            .client
            .get(&format!("{}/efetch.fcgi", PUBMED_BASE_URL))
            .query(&params)
            .send()
            .await?
            .text()
            .await?;

        self.parse_pubmed_xml(&response)
    }

    /// Parse PubMed XML response into Paper structs
    fn parse_pubmed_xml(&self, xml: &str) -> Result<Vec<Paper>, SearchError> {
        // Parse XML to extract article metadata
        // This is simplified - full implementation would handle all PubMed XML fields

        let mut papers = Vec::new();

        // Quick-xml parsing for PubmedArticle elements
        // Note: This is a simplified parser. Production code would use full XML schema.

        // For now, use regex-based extraction as fallback
        // In production, use proper XML SAX parser or quick-xml with full schema

        let article_pattern = regex::Regex::new(r"<PubmedArticle>(.*?)</PubmedArticle>")
            .map_err(|e| SearchError::ParseError(e.to_string()))?;

        for article_match in article_pattern.captures_iter(xml) {
            if let Some(article_xml) = article_match.get(1) {
                let article_text = article_xml.as_str();

                // Extract PMID
                let pmid = extract_xml_field(article_text, "PMID")
                    .unwrap_or_else(|| "unknown".to_string());

                // Extract title
                let title = extract_xml_field(article_text, "ArticleTitle")
                    .unwrap_or_else(|| "Untitled".to_string());

                // Extract abstract
                let abstract_text =
                    extract_xml_field(article_text, "AbstractText").unwrap_or_default();

                // Extract journal
                let journal = extract_xml_field(article_text, "Title"); // Journal title

                // Extract DOI
                let doi = extract_doi(article_text);

                // Extract authors (simplified)
                let authors = extract_authors(article_text);

                // Extract publication date
                let published_date = extract_pub_date(article_text);

                let mut paper = Paper::new(pmid.clone(), "pubmed".to_string(), title);
                paper.abstract_text = abstract_text;
                paper.authors = authors;
                paper.journal = journal;
                paper.doi = doi.clone();
                paper.published_date = published_date;
                paper.url = Some(format!("https://pubmed.ncbi.nlm.nih.gov/{}/", pmid));

                if let Some(ref doi_str) = doi {
                    paper.pdf_url = Some(format!("https://doi.org/{}", doi_str));
                }

                paper.metadata = serde_json::json!({
                    "pmid": pmid,
                    "source": "pubmed"
                });

                papers.push(paper);
            }
        }

        if papers.is_empty() && !xml.contains("<PubmedArticle>") {
            warn!("No articles parsed from PubMed XML response");
        }

        Ok(papers)
    }
}

#[async_trait]
impl SearchClient for PubMedClient {
    async fn search(&self, query: &SearchQuery) -> Result<SearchResult, SearchError> {
        let start_time = Instant::now();

        // Step 1: Search for PubMed IDs
        let pmids = self.esearch(query).await?;
        let total_count = pmids.len();

        // Step 2: Fetch full article metadata
        let papers = self.efetch(&pmids).await?;

        let search_time_ms = start_time.elapsed().as_millis() as u64;

        info!(
            "PubMed search completed: {} results in {}ms",
            papers.len(),
            search_time_ms
        );

        Ok(SearchResult {
            papers,
            total_count,
            query: query.query.clone(),
            backend: "pubmed".to_string(),
            search_time_ms,
        })
    }

    async fn fetch_paper(&self, pmid: &str) -> Result<Paper, SearchError> {
        let papers = self.efetch(&[pmid.to_string()]).await?;
        papers
            .into_iter()
            .next()
            .ok_or_else(|| SearchError::ApiError(format!("PMID not found: {}", pmid)))
    }

    fn backend_name(&self) -> &str {
        "pubmed"
    }
}

// ============================================================================
// Response Types
// ============================================================================

#[derive(Debug, Deserialize)]
struct ESearchResponse {
    #[serde(default)]
    error: Option<String>,
    esearchresult: Option<ESearchResult>,
}

#[derive(Debug, Deserialize)]
struct ESearchResult {
    idlist: Vec<String>,
    #[serde(default)]
    count: String,
}

// ============================================================================
// XML Parsing Helpers (simplified)
// ============================================================================

fn extract_xml_field(xml: &str, tag: &str) -> Option<String> {
    let pattern = format!(r"<{}>(.*?)</{}>", tag, tag);
    regex::Regex::new(&pattern)
        .ok()?
        .captures(xml)?
        .get(1)
        .map(|m| m.as_str().trim().to_string())
}

fn extract_doi(xml: &str) -> Option<String> {
    // DOI can be in multiple places, check ArticleId with IdType="doi"
    let pattern = regex::Regex::new(r#"<ArticleId IdType="doi">(.*?)</ArticleId>"#).ok()?;
    pattern
        .captures(xml)?
        .get(1)
        .map(|m| m.as_str().trim().to_string())
}

fn extract_authors(xml: &str) -> Vec<Author> {
    let mut authors = Vec::new();

    let author_pattern = match regex::Regex::new(r"<Author[^>]*>(.*?)</Author>") {
        Ok(pattern) => pattern,
        Err(_) => return authors,
    };

    for author_match in author_pattern.captures_iter(xml) {
        if let Some(author_xml) = author_match.get(1) {
            let author_text = author_xml.as_str();

            let last_name =
                extract_xml_field(author_text, "LastName").unwrap_or_else(|| "Unknown".to_string());
            let first_name = extract_xml_field(author_text, "ForeName");
            let initials = extract_xml_field(author_text, "Initials");

            authors.push(Author {
                first_name,
                last_name,
                initials,
                affiliation: None,
            });
        }
    }

    authors
}

fn extract_pub_date(xml: &str) -> Option<DateTime<Utc>> {
    // Try to extract PubDate Year/Month/Day
    let year = extract_xml_field(xml, "Year")?.parse::<i32>().ok()?;
    let month = extract_xml_field(xml, "Month")
        .and_then(|m| m.parse::<u32>().ok())
        .unwrap_or(1);
    let day = extract_xml_field(xml, "Day")
        .and_then(|d| d.parse::<u32>().ok())
        .unwrap_or(1);

    chrono::NaiveDate::from_ymd_opt(year, month, day)
        .and_then(|d| d.and_hms_opt(0, 0, 0))
        .map(|dt| DateTime::from_naive_utc_and_offset(dt, Utc))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[tokio::test]
    #[ignore] // Only run with --ignored flag (requires network)
    async fn test_pubmed_search() {
        let client = PubMedClient::from_env();
        let query = SearchQuery::new("CRISPR").with_max_results(5);

        let result = client.search(&query).await.unwrap();

        assert!(!result.papers.is_empty());
        assert_eq!(result.backend, "pubmed");

        // Print first result
        if let Some(paper) = result.papers.first() {
            println!("Title: {}", paper.title);
            println!("Authors: {:?}", paper.authors);
            println!("Citation: {}", paper.citation());
        }
    }

    #[tokio::test]
    #[ignore]
    async fn test_fetch_paper() {
        let client = PubMedClient::from_env();

        // Fetch a known paper (CRISPR discovery)
        let paper = client.fetch_paper("25326376").await.unwrap();

        assert_eq!(paper.source, "pubmed");
        assert!(!paper.title.is_empty());
        println!("Fetched: {}", paper.title);
    }
}
