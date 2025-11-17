//! Semantic Scholar API integration for scientific literature search
//!
//! Provides rate-limited access to Semantic Scholar's paper database
//! for building a corpus of existing research.

use anyhow::Result;
use serde::{Deserialize, Serialize};
use std::time::Duration;
use tracing::{info, warn};

const API_BASE: &str = "https://api.semanticscholar.org/graph/v1";
const RATE_LIMIT: Duration = Duration::from_millis(100); // 10 req/s max

/// Represents a scientific paper from Semantic Scholar
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Paper {
    pub paper_id: String,
    pub title: String,
    pub abstract_text: Option<String>,
    pub year: Option<u32>,
    pub citation_count: u32,
    pub authors: Vec<String>,
}

/// Client for Semantic Scholar API with rate limiting
pub struct ScholarAPI {
    client: reqwest::Client,
    last_request: std::sync::Mutex<std::time::Instant>,
}

impl ScholarAPI {
    /// Create a new Semantic Scholar API client
    pub fn new() -> Self {
        Self {
            client: reqwest::Client::builder()
                .timeout(Duration::from_secs(30))
                .build()
                .expect("Failed to create HTTP client"),
            last_request: std::sync::Mutex::new(std::time::Instant::now()),
        }
    }

    /// Enforce rate limiting (10 requests per second)
    async fn rate_limit(&self) {
        let mut last = self.last_request.lock().unwrap();
        let elapsed = last.elapsed();

        if elapsed < RATE_LIMIT {
            let sleep_time = RATE_LIMIT - elapsed;
            tokio::time::sleep(sleep_time).await;
        }

        *last = std::time::Instant::now();
    }

    /// Search for papers matching a query
    ///
    /// # Arguments
    /// * `query` - Search query (e.g., "pharmacokinetics PBPK modeling")
    /// * `limit` - Maximum number of results (default: 100)
    ///
    /// # Returns
    /// Vector of papers sorted by relevance
    pub async fn search(&self, query: &str, limit: usize) -> Result<Vec<Paper>> {
        self.rate_limit().await;

        let url = format!(
            "{}/paper/search?query={}&limit={}&fields=paperId,title,abstract,year,citationCount,authors",
            API_BASE,
            urlencoding::encode(query),
            limit
        );

        info!("🔍 Searching Semantic Scholar: {}", query);

        let response = self
            .client
            .get(&url)
            .timeout(Duration::from_secs(30))
            .send()
            .await?;

        if !response.status().is_success() {
            warn!("⚠️  Semantic Scholar API error: {}", response.status());
            return Ok(vec![]);
        }

        #[derive(Deserialize)]
        struct SearchResponse {
            data: Vec<PaperData>,
        }

        #[derive(Deserialize)]
        struct PaperData {
            #[serde(rename = "paperId")]
            paper_id: String,
            title: String,
            #[serde(rename = "abstract")]
            abstract_text: Option<String>,
            year: Option<u32>,
            #[serde(rename = "citationCount")]
            citation_count: u32,
            authors: Vec<AuthorData>,
        }

        #[derive(Deserialize)]
        struct AuthorData {
            name: String,
        }

        let search_response: SearchResponse = response.json().await?;

        let papers: Vec<Paper> = search_response
            .data
            .into_iter()
            .map(|p| Paper {
                paper_id: p.paper_id,
                title: p.title,
                abstract_text: p.abstract_text,
                year: p.year,
                citation_count: p.citation_count,
                authors: p
                    .authors
                    .into_iter()
                    .map(|a| a.name)
                    .collect::<Vec<String>>(),
            })
            .collect();

        info!("✅ Found {} papers", papers.len());

        Ok(papers)
    }

    /// Get papers that cite a given paper
    ///
    /// # Arguments
    /// * `paper_id` - Semantic Scholar paper ID
    /// * `limit` - Maximum number of results
    ///
    /// # Returns
    /// Vector of citing papers
    pub async fn get_citations(&self, paper_id: &str, limit: usize) -> Result<Vec<Paper>> {
        self.rate_limit().await;

        let url = format!(
            "{}/paper/{}/citations?limit={}&fields=contexts,intents,paperId,title,abstract,year,citationCount,authors",
            API_BASE,
            paper_id,
            limit
        );

        info!("🔗 Fetching citations for paper: {}", paper_id);

        let response = self
            .client
            .get(&url)
            .timeout(Duration::from_secs(30))
            .send()
            .await?;

        if !response.status().is_success() {
            warn!("⚠️  Failed to fetch citations: {}", response.status());
            return Ok(vec![]);
        }

        #[derive(Deserialize)]
        struct CitationResponse {
            data: Vec<CitationData>,
        }

        #[derive(Deserialize)]
        struct CitationData {
            #[serde(rename = "citingPaper")]
            citing_paper: PaperData,
        }

        #[derive(Deserialize)]
        struct PaperData {
            #[serde(rename = "paperId")]
            paper_id: String,
            title: String,
            #[serde(rename = "abstract")]
            abstract_text: Option<String>,
            year: Option<u32>,
            #[serde(rename = "citationCount")]
            citation_count: u32,
            authors: Vec<AuthorData>,
        }

        #[derive(Deserialize)]
        struct AuthorData {
            name: String,
        }

        let citation_response: CitationResponse = response.json().await?;

        let papers: Vec<Paper> = citation_response
            .data
            .into_iter()
            .map(|c| {
                let p = c.citing_paper;
                Paper {
                    paper_id: p.paper_id,
                    title: p.title,
                    abstract_text: p.abstract_text,
                    year: p.year,
                    citation_count: p.citation_count,
                    authors: p
                        .authors
                        .into_iter()
                        .map(|a| a.name)
                        .collect::<Vec<String>>(),
                }
            })
            .collect();

        info!("✅ Found {} citing papers", papers.len());

        Ok(papers)
    }

    /// Get related papers (recommendations)
    ///
    /// # Arguments
    /// * `paper_id` - Semantic Scholar paper ID
    /// * `limit` - Maximum number of results
    ///
    /// # Returns
    /// Vector of related papers
    pub async fn get_related(&self, paper_id: &str, limit: usize) -> Result<Vec<Paper>> {
        self.rate_limit().await;

        let url = format!(
            "{}/paper/{}/recommendations?limit={}&fields=paperId,title,abstract,year,citationCount,authors",
            API_BASE,
            paper_id,
            limit
        );

        info!("🔗 Fetching related papers for: {}", paper_id);

        let response = self
            .client
            .get(&url)
            .timeout(Duration::from_secs(30))
            .send()
            .await?;

        if !response.status().is_success() {
            warn!("⚠️  Failed to fetch related papers: {}", response.status());
            return Ok(vec![]);
        }

        // Similar parsing as search
        #[derive(Deserialize)]
        struct RecommendationResponse {
            data: Vec<PaperData>,
        }

        #[derive(Deserialize)]
        struct PaperData {
            #[serde(rename = "paperId")]
            paper_id: String,
            title: String,
            #[serde(rename = "abstract")]
            abstract_text: Option<String>,
            year: Option<u32>,
            #[serde(rename = "citationCount")]
            citation_count: u32,
            authors: Vec<AuthorData>,
        }

        #[derive(Deserialize)]
        struct AuthorData {
            name: String,
        }

        let rec_response: RecommendationResponse = response.json().await?;

        let papers: Vec<Paper> = rec_response
            .data
            .into_iter()
            .map(|p| Paper {
                paper_id: p.paper_id,
                title: p.title,
                abstract_text: p.abstract_text,
                year: p.year,
                citation_count: p.citation_count,
                authors: p
                    .authors
                    .into_iter()
                    .map(|a| a.name)
                    .collect::<Vec<String>>(),
            })
            .collect();

        info!("✅ Found {} related papers", papers.len());

        Ok(papers)
    }
}

impl Default for ScholarAPI {
    fn default() -> Self {
        Self::new()
    }
}
