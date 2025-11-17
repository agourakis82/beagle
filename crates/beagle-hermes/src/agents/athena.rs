//! ATHENA: Literature review and context gathering agent

use crate::{knowledge::ConceptCluster, Result};
use async_trait::async_trait;
use beagle_hypergraph::embeddings::{EmbeddingGenerator, MockEmbeddingGenerator, OpenAIEmbeddings};
use beagle_hypergraph::rag::LanguageModelError;
use beagle_hypergraph::{CachedPostgresStorage, LanguageModel, RAGPipeline};
use beagle_llm::{AnthropicClient, CompletionRequest, Message, ModelType};
use serde::{Deserialize, Serialize};
use std::sync::Arc;
use tracing::{debug, info, warn};

/// Wrapper for AnthropicClient to implement LanguageModel trait
struct AnthropicLanguageModel {
    client: Arc<AnthropicClient>,
}

#[async_trait]
impl LanguageModel for AnthropicLanguageModel {
    async fn generate(&self, prompt: &str) -> std::result::Result<String, LanguageModelError> {
        let request = CompletionRequest {
            model: ModelType::ClaudeSonnet45,
            messages: vec![Message::user(prompt)],
            max_tokens: 2048,
            temperature: 0.7,
            system: None,
        };

        let response = self
            .client
            .complete(request)
            .await
            .map_err(|e| LanguageModelError::Invocation(e.to_string()))?;

        Ok(response.content)
    }

    fn max_context_tokens(&self) -> Option<usize> {
        Some(200_000) // Claude Sonnet 4.5 context window
    }
}

pub struct AthenaAgent {
    rag_pipeline: Option<Arc<RAGPipeline>>,
    llm_client: Arc<AnthropicClient>,
}

impl AthenaAgent {
    pub async fn new() -> Result<Self> {
        // Initialize Anthropic client for fallback
        let api_key = std::env::var("ANTHROPIC_API_KEY").map_err(|_| {
            crate::HermesError::ConfigError("ANTHROPIC_API_KEY not set".to_string())
        })?;

        let llm_client =
            AnthropicClient::new(api_key).map_err(|e| crate::HermesError::LLMError(e))?;

        let llm_arc = Arc::new(llm_client);
        // Try to initialize RAG pipeline if storage is available
        let rag_pipeline = match Self::try_init_rag_pipeline(Arc::clone(&llm_arc)).await {
            Ok(pipeline) => {
                info!("ATHENA: RAG pipeline initialized successfully");
                Some(pipeline)
            }
            Err(e) => {
                warn!(
                    "ATHENA: Failed to initialize RAG pipeline: {}. Using fallback search.",
                    e
                );
                None
            }
        };

        Ok(Self {
            rag_pipeline,
            llm_client: llm_arc,
        })
    }

    async fn try_init_rag_pipeline(
        llm: Arc<AnthropicClient>,
    ) -> std::result::Result<Arc<RAGPipeline>, crate::HermesError> {
        // Try to get storage from environment
        let postgres_uri = std::env::var("DATABASE_URL")
            .map_err(|_| crate::HermesError::ConfigError("DATABASE_URL not set".to_string()))?;
        let redis_uri =
            std::env::var("REDIS_URL").unwrap_or_else(|_| "redis://localhost:6379".to_string());

        let storage = Arc::new(
            CachedPostgresStorage::new(&postgres_uri, &redis_uri)
                .await
                .map_err(|e| {
                    crate::HermesError::DatabaseError(sqlx::Error::Configuration(
                        format!("Hypergraph error: {}", e).into(),
                    ))
                })?,
        );

        // Create language model wrapper
        let language_model: Arc<dyn LanguageModel> =
            Arc::new(AnthropicLanguageModel { client: llm });

        // Initialize embedding generator
        // Try OpenAI first, fallback to Mock if API key not available
        let embeddings: Arc<dyn EmbeddingGenerator> =
            if let Ok(openai_key) = std::env::var("OPENAI_API_KEY") {
                Arc::new(OpenAIEmbeddings::new(openai_key))
            } else {
                warn!("OPENAI_API_KEY not set, using MockEmbeddingGenerator for ATHENA");
                Arc::new(MockEmbeddingGenerator)
            };

        // Create RAG pipeline
        let pipeline = Arc::new(RAGPipeline::new(storage, language_model, embeddings));

        Ok(pipeline)
    }

    /// Search for relevant papers given concept cluster
    pub async fn search_papers(&self, cluster: &ConceptCluster) -> Result<Vec<Paper>> {
        info!(
            "ATHENA: Searching papers for cluster: {}",
            cluster.concept_name
        );

        // 1. Extract key terms from cluster
        let mut query = cluster.concept_name.clone();
        // Add concepts from insights (limit to first 500 chars to avoid huge queries)
        let mut insight_text = String::new();
        for insight in &cluster.insights {
            if insight_text.len() > 500 {
                break;
            }
            insight_text.push_str(" ");
            insight_text.push_str(&insight.content);
        }
        query.push_str(&insight_text);

        debug!("ATHENA: Query: {} ({} chars)", query, query.len());

        // 2. Try RAG pipeline first, fallback to LLM-based search
        if let Some(ref pipeline) = self.rag_pipeline {
            match pipeline.query(&query).await {
                Ok(rag_response) => {
                    // Extract papers from RAG citations
                    let papers = self.extract_papers_from_rag(&rag_response).await?;
                    if !papers.is_empty() {
                        info!("ATHENA: Found {} papers via RAG pipeline", papers.len());
                        return Ok(papers);
                    }
                }
                Err(e) => {
                    warn!("ATHENA: RAG pipeline search failed: {}. Using fallback.", e);
                }
            }
        }

        // 3. Fallback: Use LLM to search and extract paper information
        let papers = self.llm_based_paper_search(&query).await?;
        info!("ATHENA: Found {} papers via LLM search", papers.len());
        Ok(papers)
    }

    async fn extract_papers_from_rag(
        &self,
        rag_response: &beagle_hypergraph::rag::RAGResponse,
    ) -> Result<Vec<Paper>> {
        // Use LLM to extract structured paper information from RAG response
        let context_text = format!(
            "RAG Response Answer: {}\n\nCitations: {}",
            rag_response.answer,
            rag_response
                .citations
                .iter()
                .enumerate()
                .map(|(i, c)| format!(
                    "[{}] Title: {:?}, Source: {:?}, URL: {:?}",
                    i + 1,
                    c.title.as_ref().unwrap_or(&"Unknown".to_string()),
                    c.source.as_ref().unwrap_or(&"Unknown".to_string()),
                    c.url.as_ref().unwrap_or(&"Unknown".to_string())
                ))
                .collect::<Vec<_>>()
                .join("\n")
        );

        let extraction_prompt = format!(
            r#"Extract scientific paper information from the following RAG response context.

Context:
{}

For each citation mentioned, extract:
- title: string
- authors: array of strings (if available, otherwise empty array)
- year: integer (if available, otherwise 2024)
- abstract: string (brief summary, 2-3 sentences if available)
- doi: string (if available in URL, otherwise empty)

Return JSON array format:
[
  {{
    "title": "...",
    "authors": ["Author1", "Author2"],
    "year": 2024,
    "abstract": "...",
    "doi": "..."
  }}
]

JSON only, no markdown:
"#,
            context_text
        );

        let request = CompletionRequest {
            model: ModelType::ClaudeSonnet45,
            messages: vec![Message::user(extraction_prompt)],
            max_tokens: 2048,
            temperature: 0.2, // Low temperature for structured extraction
            system: Some("You are an expert at extracting structured information from scientific literature.".to_string()),
        };

        let response = self
            .llm_client
            .complete(request)
            .await
            .map_err(|e| crate::HermesError::LLMError(e))?;

        // Parse JSON response
        let extracted_papers: Vec<Paper> =
            serde_json::from_str(&response.content).map_err(|e| {
                warn!(
                    "Failed to parse extracted papers JSON: {}. Response: {}",
                    e, response.content
                );
                crate::HermesError::SynthesisError(format!("Failed to parse papers JSON: {}", e))
            })?;

        // Assign relevance scores based on citation order (earlier = more relevant)
        let papers_with_scores: Vec<Paper> = extracted_papers
            .into_iter()
            .enumerate()
            .map(|(idx, mut paper)| {
                paper.relevance_score = 1.0 - (idx as f64 * 0.05).min(0.3); // Decrease by 5% per position
                paper
            })
            .collect();

        Ok(papers_with_scores)
    }

    async fn llm_based_paper_search(&self, query: &str) -> Result<Vec<Paper>> {
        // Use LLM to generate a search query and extract paper information
        let prompt = format!(
            r#"You are a scientific literature search assistant. Given the research topic below, 
generate a list of 10-15 relevant scientific papers in JSON format.

Research topic: {}

Return a JSON array of papers, each with:
- title: string
- authors: array of strings (first author first)
- year: integer
- abstract: string (brief, 2-3 sentences)
- doi: string (if known, otherwise empty string)

Format:
[
  {{
    "title": "...",
    "authors": ["Author1", "Author2"],
    "year": 2024,
    "abstract": "...",
    "doi": "..."
  }}
]

JSON only, no markdown:
"#,
            query
        );

        let request = CompletionRequest {
            model: ModelType::ClaudeSonnet45,
            messages: vec![Message::user(prompt)],
            max_tokens: 2048,
            temperature: 0.3, // Lower temperature for more consistent results
            system: Some(
                "You are an expert at finding relevant scientific literature.".to_string(),
            ),
        };

        let response = self
            .llm_client
            .complete(request)
            .await
            .map_err(|e| crate::HermesError::LLMError(e))?;

        // Parse JSON response
        let papers: Vec<Paper> = serde_json::from_str(&response.content).map_err(|e| {
            crate::HermesError::SynthesisError(format!("Failed to parse papers JSON: {}", e))
        })?;

        Ok(papers)
    }

    /// Extract key findings from papers
    pub async fn extract_key_findings(&self, papers: &[Paper]) -> Result<Vec<Finding>> {
        if papers.is_empty() {
            return Ok(Vec::new());
        }

        info!(
            "ATHENA: Extracting key findings from {} papers",
            papers.len()
        );

        // Prepare paper summaries for LLM
        let papers_text: String = papers
            .iter()
            .enumerate()
            .map(|(i, paper)| {
                format!(
                    "Paper {}: {}\nAuthors: {}\nYear: {}\nAbstract: {}\n",
                    i + 1,
                    paper.title,
                    paper.authors.join(", "),
                    paper.year,
                    paper.abstract_text
                )
            })
            .collect();

        let extraction_prompt = format!(
            r#"Extract key findings from the following scientific papers. For each paper, identify:

1. Main results (primary findings)
2. Methods used (key methodologies)
3. Limitations (acknowledged limitations)
4. Future directions (suggested future work)

Papers:
{}

Return JSON array format, one entry per paper:
[
  {{
    "paper_doi": "doi or empty",
    "findings": [
      {{"category": "MainResult", "text": "finding text"}},
      {{"category": "Method", "text": "method description"}},
      {{"category": "Limitation", "text": "limitation text"}},
      {{"category": "FutureDirection", "text": "future direction"}}
    ]
  }}
]

JSON only, no markdown:
"#,
            papers_text
        );

        let request = CompletionRequest {
            model: ModelType::ClaudeSonnet45,
            messages: vec![Message::user(extraction_prompt)],
            max_tokens: 4096,
            temperature: 0.3,
            system: Some("You are an expert at analyzing scientific literature and extracting structured findings.".to_string()),
        };

        let response = self
            .llm_client
            .complete(request)
            .await
            .map_err(|e| crate::HermesError::LLMError(e))?;

        // Parse structured response
        #[derive(Deserialize)]
        struct FindingResponse {
            paper_doi: String,
            findings: Vec<FindingEntry>,
        }

        #[derive(Deserialize)]
        struct FindingEntry {
            category: String,
            text: String,
        }

        let parsed: Vec<FindingResponse> =
            serde_json::from_str(&response.content).map_err(|e| {
                crate::HermesError::SynthesisError(format!("Failed to parse findings JSON: {}", e))
            })?;

        let mut all_findings = Vec::new();

        for paper_response in parsed {
            for finding_entry in paper_response.findings {
                let category = match finding_entry.category.as_str() {
                    "MainResult" => FindingCategory::MainResult,
                    "Method" => FindingCategory::Method,
                    "Limitation" => FindingCategory::Limitation,
                    "FutureDirection" => FindingCategory::FutureDirection,
                    _ => FindingCategory::MainResult, // Default
                };

                all_findings.push(Finding {
                    paper_doi: paper_response.paper_doi.clone(),
                    finding_text: finding_entry.text,
                    category,
                });
            }
        }

        info!("ATHENA: Extracted {} key findings", all_findings.len());
        Ok(all_findings)
    }
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Paper {
    pub title: String,
    pub authors: Vec<String>,
    pub year: i32,
    pub abstract_text: String,
    pub doi: String,
    pub relevance_score: f64,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Finding {
    pub paper_doi: String,
    pub finding_text: String,
    pub category: FindingCategory,
}

#[derive(Debug, Clone, Copy, Serialize, Deserialize)]
pub enum FindingCategory {
    MainResult,
    Method,
    Limitation,
    FutureDirection,
}
