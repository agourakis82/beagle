//! Common types for scientific paper search

use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};
use thiserror::Error;

/// Unified search query across all backends
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SearchQuery {
    /// Search terms (free text)
    pub query: String,

    /// Maximum number of results to return
    #[serde(default = "default_max_results")]
    pub max_results: usize,

    /// Starting offset for pagination
    #[serde(default)]
    pub offset: usize,

    /// Optional date range filter
    #[serde(default)]
    pub date_range: Option<DateRange>,

    /// Optional filters (backend-specific)
    #[serde(default)]
    pub filters: serde_json::Value,
}

fn default_max_results() -> usize {
    10
}

impl SearchQuery {
    pub fn new(query: impl Into<String>) -> Self {
        Self {
            query: query.into(),
            max_results: 10,
            offset: 0,
            date_range: None,
            filters: serde_json::json!({}),
        }
    }

    pub fn with_max_results(mut self, max: usize) -> Self {
        self.max_results = max;
        self
    }

    pub fn with_offset(mut self, offset: usize) -> Self {
        self.offset = offset;
        self
    }

    pub fn with_date_range(mut self, from: DateTime<Utc>, to: DateTime<Utc>) -> Self {
        self.date_range = Some(DateRange { from, to });
        self
    }
}

/// Date range filter
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct DateRange {
    pub from: DateTime<Utc>,
    pub to: DateTime<Utc>,
}

/// Search result containing papers and metadata
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SearchResult {
    /// Papers found
    pub papers: Vec<Paper>,

    /// Total number of results available (may be > papers.len())
    pub total_count: usize,

    /// Query that generated these results
    pub query: String,

    /// Backend that produced these results
    pub backend: String,

    /// Time taken to execute search (milliseconds)
    pub search_time_ms: u64,
}

/// Scientific paper metadata
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Paper {
    /// Unique ID (PubMed ID, arXiv ID, DOI, etc.)
    pub id: String,

    /// Backend source ("pubmed", "arxiv", etc.)
    pub source: String,

    /// Paper title
    pub title: String,

    /// Authors
    pub authors: Vec<Author>,

    /// Abstract/summary
    pub abstract_text: String,

    /// Publication date
    pub published_date: Option<DateTime<Utc>>,

    /// Journal/venue name
    pub journal: Option<String>,

    /// DOI (Digital Object Identifier)
    pub doi: Option<String>,

    /// arXiv categories (e.g., "cs.AI", "q-bio.QM")
    pub categories: Vec<String>,

    /// Full text URL (if available)
    pub url: Option<String>,

    /// PDF URL (if available)
    pub pdf_url: Option<String>,

    /// Citation count (if available)
    pub citation_count: Option<usize>,

    /// Additional metadata (backend-specific)
    pub metadata: serde_json::Value,
}

impl Paper {
    /// Create a minimal paper record
    pub fn new(id: String, source: String, title: String) -> Self {
        Self {
            id,
            source,
            title,
            authors: Vec::new(),
            abstract_text: String::new(),
            published_date: None,
            journal: None,
            doi: None,
            categories: Vec::new(),
            url: None,
            pdf_url: None,
            citation_count: None,
            metadata: serde_json::json!({}),
        }
    }

    /// Generate a citation string (APA-style)
    pub fn citation(&self) -> String {
        let authors_str = if self.authors.is_empty() {
            "Unknown Authors".to_string()
        } else if self.authors.len() == 1 {
            self.authors[0].full_name()
        } else if self.authors.len() == 2 {
            format!(
                "{} & {}",
                self.authors[0].last_name(),
                self.authors[1].last_name()
            )
        } else {
            format!("{} et al.", self.authors[0].last_name())
        };

        let year = self
            .published_date
            .map(|d| d.format("%Y").to_string())
            .unwrap_or_else(|| "n.d.".to_string());

        let journal_str = self
            .journal
            .as_ref()
            .map(|j| format!(". {}.", j))
            .unwrap_or_default();

        format!("{} ({}). {}{}", authors_str, year, self.title, journal_str)
    }
}

/// Paper author
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Author {
    pub first_name: Option<String>,
    pub last_name: String,
    pub initials: Option<String>,
    pub affiliation: Option<String>,
}

impl Author {
    pub fn new(last_name: String) -> Self {
        Self {
            first_name: None,
            last_name,
            initials: None,
            affiliation: None,
        }
    }

    pub fn full_name(&self) -> String {
        match &self.first_name {
            Some(first) => format!("{} {}", first, self.last_name),
            None => self.last_name.clone(),
        }
    }

    pub fn last_name(&self) -> &str {
        &self.last_name
    }
}

/// Search errors
#[derive(Debug, Error)]
pub enum SearchError {
    #[error("HTTP request failed: {0}")]
    HttpError(#[from] reqwest::Error),

    #[error("API error: {0}")]
    ApiError(String),

    #[error("Parse error: {0}")]
    ParseError(String),

    #[error("Rate limit exceeded")]
    RateLimitExceeded,

    #[error("Invalid query: {0}")]
    InvalidQuery(String),

    #[error("Backend error: {0}")]
    BackendError(String),
}
