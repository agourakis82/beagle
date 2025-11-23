//! arXiv search client using arXiv API
//!
//! API docs: https://info.arxiv.org/help/api/index.html
//! Rate limit: Max 1 request per 3 seconds
//!
//! arXiv covers: physics, mathematics, computer science, biology, finance, etc.

use crate::types::{Author, Paper, SearchError, SearchQuery, SearchResult};
use crate::SearchClient;
use async_trait::async_trait;
use chrono::{DateTime, Utc};
use governor::{Quota, RateLimiter};
use std::num::NonZeroU32;
use std::sync::Arc;
use std::time::{Duration, Instant};
use tracing::{debug, info, warn};

const ARXIV_API_URL: &str = "http://export.arxiv.org/api/query";

/// arXiv search client
pub struct ArxivClient {
    client: reqwest::Client,
    rate_limiter: Arc<
        RateLimiter<
            governor::state::direct::NotKeyed,
            governor::state::InMemoryState,
            governor::clock::DefaultClock,
        >,
    >,
}

impl ArxivClient {
    /// Create new arXiv client with rate limiting (1 req per 3 seconds)
    pub fn new() -> Self {
        // arXiv API: Max 1 request per 3 seconds
        let quota = Quota::with_period(Duration::from_secs(3))
            .unwrap()
            .allow_burst(NonZeroU32::new(1).unwrap());
        let rate_limiter = Arc::new(RateLimiter::direct(quota));

        Self {
            client: reqwest::Client::builder()
                .timeout(Duration::from_secs(30))
                .build()
                .unwrap(),
            rate_limiter,
        }
    }

    /// Parse arXiv Atom XML response
    fn parse_atom_feed(&self, xml: &str) -> Result<Vec<Paper>, SearchError> {
        let mut papers = Vec::new();

        // Parse <entry> elements from Atom feed
        let entry_pattern = regex::Regex::new(r"<entry>(.*?)</entry>")
            .map_err(|e| SearchError::ParseError(e.to_string()))?;

        for entry_match in entry_pattern.captures_iter(xml) {
            if let Some(entry_xml) = entry_match.get(1) {
                let entry_text = entry_xml.as_str();

                // Extract arXiv ID from <id>
                let id_url =
                    extract_xml_field(entry_text, "id").unwrap_or_else(|| "unknown".to_string());
                let arxiv_id = id_url.split('/').last().unwrap_or("unknown").to_string();

                // Extract title
                let title = extract_xml_field(entry_text, "title")
                    .map(|t| t.replace('\n', " ").trim().to_string())
                    .unwrap_or_else(|| "Untitled".to_string());

                // Extract summary (abstract)
                let abstract_text = extract_xml_field(entry_text, "summary")
                    .map(|s| s.replace('\n', " ").trim().to_string())
                    .unwrap_or_default();

                // Extract authors
                let authors = extract_atom_authors(entry_text);

                // Extract publication date
                let published_date = extract_xml_field(entry_text, "published")
                    .and_then(|s| DateTime::parse_from_rfc3339(&s).ok())
                    .map(|dt| dt.with_timezone(&Utc));

                // Extract categories
                let categories = extract_categories(entry_text);

                // Build URLs
                let url = Some(format!("https://arxiv.org/abs/{}", arxiv_id));
                let pdf_url = Some(format!("https://arxiv.org/pdf/{}.pdf", arxiv_id));

                // Extract DOI if present
                let doi = extract_arxiv_doi(entry_text);

                // Extract journal reference if present
                let journal = extract_xml_field(entry_text, "arxiv:journal_ref");

                let mut paper = Paper::new(arxiv_id.clone(), "arxiv".to_string(), title);
                paper.abstract_text = abstract_text;
                paper.authors = authors;
                paper.published_date = published_date;
                paper.categories = categories.clone();
                paper.url = url;
                paper.pdf_url = pdf_url;
                paper.doi = doi;
                paper.journal = journal;

                paper.metadata = serde_json::json!({
                    "arxiv_id": arxiv_id,
                    "source": "arxiv",
                    "categories": categories
                });

                papers.push(paper);
            }
        }

        if papers.is_empty() && !xml.contains("<entry>") {
            // Check for errors in response
            if let Some(error_msg) = extract_xml_field(xml, "title") {
                if error_msg.contains("Error") {
                    return Err(SearchError::ApiError(format!("arXiv error: {}", error_msg)));
                }
            }
            warn!("No entries parsed from arXiv Atom feed");
        }

        Ok(papers)
    }
}

impl Default for ArxivClient {
    fn default() -> Self {
        Self::new()
    }
}

#[async_trait]
impl SearchClient for ArxivClient {
    async fn search(&self, query: &SearchQuery) -> Result<SearchResult, SearchError> {
        let start_time = Instant::now();

        self.rate_limiter.until_ready().await;

        // Build arXiv API query
        // Syntax: search_query=all:electron or ti:quantum or au:einstein
        let search_query = format!("all:{}", query.query);

        let params = [
            ("search_query", search_query.as_str()),
            ("start", &query.offset.to_string()),
            ("max_results", &query.max_results.to_string()),
            ("sortBy", "relevance"),
            ("sortOrder", "descending"),
        ];

        debug!("arXiv API query: {}", query.query);

        let response = self
            .client
            .get(ARXIV_API_URL)
            .query(&params)
            .send()
            .await?
            .error_for_status()
            .map_err(|e| SearchError::ApiError(format!("arXiv request failed: {}", e)))?
            .text()
            .await?;

        let papers = self.parse_atom_feed(&response)?;
        let total_count = papers.len(); // arXiv doesn't provide total count easily

        let search_time_ms = start_time.elapsed().as_millis() as u64;

        info!(
            "arXiv search completed: {} results in {}ms",
            papers.len(),
            search_time_ms
        );

        Ok(SearchResult {
            papers,
            total_count,
            query: query.query.clone(),
            backend: "arxiv".to_string(),
            search_time_ms,
        })
    }

    async fn fetch_paper(&self, arxiv_id: &str) -> Result<Paper, SearchError> {
        self.rate_limiter.until_ready().await;

        let params = [("id_list", arxiv_id)];

        let response = self
            .client
            .get(ARXIV_API_URL)
            .query(&params)
            .send()
            .await?
            .text()
            .await?;

        let mut papers = self.parse_atom_feed(&response)?;
        papers
            .pop()
            .ok_or_else(|| SearchError::ApiError(format!("arXiv ID not found: {}", arxiv_id)))
    }

    fn backend_name(&self) -> &str {
        "arxiv"
    }
}

// ============================================================================
// XML Parsing Helpers
// ============================================================================

fn extract_xml_field(xml: &str, tag: &str) -> Option<String> {
    // Handle both <tag>value</tag> and <prefix:tag>value</prefix:tag>
    let pattern = format!(r"<[^:>]*:?{}[^>]*>(.*?)</[^:>]*:?{}>", tag, tag);
    regex::Regex::new(&pattern)
        .ok()?
        .captures(xml)?
        .get(1)
        .map(|m| m.as_str().trim().to_string())
}

fn extract_atom_authors(xml: &str) -> Vec<Author> {
    let mut authors = Vec::new();

    let author_pattern = match regex::Regex::new(r"<author>(.*?)</author>") {
        Ok(pattern) => pattern,
        Err(_) => return authors,
    };

    for author_match in author_pattern.captures_iter(xml) {
        if let Some(author_xml) = author_match.get(1) {
            let author_text = author_xml.as_str();

            if let Some(name) = extract_xml_field(author_text, "name") {
                // Parse "FirstName LastName" format
                let parts: Vec<&str> = name.split_whitespace().collect();
                let (first_name, last_name) = if parts.len() >= 2 {
                    (
                        Some(parts[..parts.len() - 1].join(" ")),
                        parts[parts.len() - 1].to_string(),
                    )
                } else {
                    (None, name.clone())
                };

                authors.push(Author {
                    first_name,
                    last_name,
                    initials: None,
                    affiliation: None,
                });
            }
        }
    }

    authors
}

fn extract_categories(xml: &str) -> Vec<String> {
    let mut categories = Vec::new();

    // arXiv categories are in <category term="cs.AI" .../>
    let category_pattern = match regex::Regex::new(r#"<category term="([^"]+)""#) {
        Ok(pattern) => pattern,
        Err(_) => return categories,
    };

    for cap in category_pattern.captures_iter(xml) {
        if let Some(cat) = cap.get(1) {
            categories.push(cat.as_str().to_string());
        }
    }

    categories
}

fn extract_arxiv_doi(xml: &str) -> Option<String> {
    extract_xml_field(xml, "arxiv:doi")
}

#[cfg(test)]
mod tests {
    use super::*;

    #[tokio::test]
    #[ignore] // Only run with --ignored flag (requires network)
    async fn test_arxiv_search() {
        let client = ArxivClient::new();
        let query = SearchQuery::new("quantum computing").with_max_results(5);

        let result = client.search(&query).await.unwrap();

        assert!(!result.papers.is_empty());
        assert_eq!(result.backend, "arxiv");

        // Print first result
        if let Some(paper) = result.papers.first() {
            println!("Title: {}", paper.title);
            println!("arXiv ID: {}", paper.id);
            println!("Categories: {:?}", paper.categories);
            println!("Authors: {:?}", paper.authors);
            if let Some(url) = &paper.pdf_url {
                println!("PDF: {}", url);
            }
        }
    }

    #[tokio::test]
    #[ignore]
    async fn test_fetch_paper() {
        let client = ArxivClient::new();

        // Fetch a known paper (Attention Is All You Need)
        let paper = client.fetch_paper("1706.03762").await.unwrap();

        assert_eq!(paper.source, "arxiv");
        assert!(paper.title.contains("Attention"));
        println!("Fetched: {}", paper.title);
    }
}
