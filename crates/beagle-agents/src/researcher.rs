use std::sync::Arc;
use std::time::Instant;

use anyhow::{Context, Result};
use beagle_core::BeagleContext;
use beagle_llm::{AnthropicClient, CompletionRequest, Message, ModelType};
use beagle_memory::{ContextBridge, ConversationTurn, PerformanceMetrics, RetrievedContext};
use beagle_personality::PersonalityEngine;
use beagle_search::{ArxivClient, Paper, PubMedClient, SearchClient, SearchQuery};
use tracing::{info, warn};
use uuid::Uuid;

use crate::models::{ResearchMetrics, ResearchResult, ResearchStep};

/// Quality threshold for accepting answers without refinement
const QUALITY_THRESHOLD: f32 = 0.7;

/// Maximum number of refinement iterations
const MAX_REFINEMENTS: usize = 3;

/// Agente sequencial (baseline) responsável pela execução Self-RAG em série.
///
/// Now enhanced with live paper search capabilities (PubMed, arXiv)
pub struct ResearcherAgent {
    anthropic: Arc<AnthropicClient>,
    personality: Arc<PersonalityEngine>,
    context_bridge: Arc<ContextBridge>,
    /// Optional: BeagleContext for Neo4j graph storage
    beagle_ctx: Option<Arc<BeagleContext>>,
    /// PubMed search client
    pubmed: Arc<PubMedClient>,
    /// arXiv search client
    arxiv: Arc<ArxivClient>,
}

impl ResearcherAgent {
    pub fn new(
        anthropic: Arc<AnthropicClient>,
        personality: Arc<PersonalityEngine>,
        context_bridge: Arc<ContextBridge>,
    ) -> Self {
        Self {
            anthropic,
            personality,
            context_bridge,
            beagle_ctx: None,
            pubmed: Arc::new(PubMedClient::from_env()),
            arxiv: Arc::new(ArxivClient::new()),
        }
    }

    /// Create with Neo4j graph storage support
    pub fn with_graph(mut self, ctx: Arc<BeagleContext>) -> Self {
        self.beagle_ctx = Some(ctx);
        self
    }

    /// Critique answer quality using LLM as a critic
    ///
    /// Returns (quality_score, critique_text)
    async fn critique_answer(&self, query: &str, answer: &str) -> Result<(f32, String)> {
        let critique_prompt = format!(
            r#"You are an expert research critic. Evaluate the following answer to a research question.

QUESTION: {}

ANSWER: {}

Provide a detailed critique addressing:
1. Accuracy - Is the information correct and well-supported?
2. Completeness - Does it fully address the question?
3. Clarity - Is it clear and well-structured?
4. Citations - Are sources properly referenced?

Rate the overall quality from 0.0 (poor) to 1.0 (excellent).
Format: SCORE: [0.0-1.0]
Then provide detailed critique."#,
            query, answer
        );

        let critique_response = self
            .anthropic
            .complete(CompletionRequest {
                model: ModelType::ClaudeHaiku45,
                messages: vec![Message::user(&critique_prompt)],
                max_tokens: 800,
                temperature: 0.3, // Lower temp for more consistent critique
                system: Some("You are a rigorous academic reviewer.".to_string()),
            })
            .await?;

        // Parse score from response
        let score = if let Some(score_line) = critique_response
            .content
            .lines()
            .find(|line| line.to_uppercase().starts_with("SCORE:"))
        {
            score_line
                .split(':')
                .nth(1)
                .and_then(|s| s.trim().parse::<f32>().ok())
                .unwrap_or(0.5)
        } else {
            // If no explicit score, estimate from critique content
            let positive_words = ["excellent", "good", "accurate", "comprehensive", "clear"];
            let negative_words = ["poor", "incomplete", "unclear", "missing", "incorrect"];

            let text_lower = critique_response.content.to_lowercase();
            let pos_count = positive_words
                .iter()
                .filter(|w| text_lower.contains(*w))
                .count();
            let neg_count = negative_words
                .iter()
                .filter(|w| text_lower.contains(*w))
                .count();

            ((pos_count as f32 - neg_count as f32) / 10.0 + 0.5).clamp(0.0, 1.0)
        };

        Ok((score, critique_response.content))
    }

    /// Refine answer based on critique
    async fn refine_answer(
        &self,
        query: &str,
        previous_answer: &str,
        critique: &str,
        system_prompt: &str,
    ) -> Result<String> {
        let refinement_prompt = format!(
            r#"Original question: {}

Previous answer:
{}

Critique of previous answer:
{}

Based on this critique, provide an improved answer that addresses all the issues raised.
Focus on accuracy, completeness, and proper citation of sources."#,
            query, previous_answer, critique
        );

        let refined = self
            .anthropic
            .complete(CompletionRequest {
                model: ModelType::ClaudeHaiku45,
                messages: vec![Message::user(&refinement_prompt)],
                max_tokens: 1500,
                temperature: 0.8,
                system: Some(system_prompt.to_string()),
            })
            .await?;

        Ok(refined.content)
    }

    /// Search for scientific papers and store in Neo4j
    ///
    /// Searches both PubMed and arXiv, stores results in graph,
    /// and returns paper citations for inclusion in research context.
    async fn search_and_store_papers(&self, query: &str, max_results: usize) -> Result<Vec<Paper>> {
        let mut all_papers = Vec::new();

        // Determine which backend to use based on query
        let use_pubmed = query.to_lowercase().contains("gene")
            || query.to_lowercase().contains("protein")
            || query.to_lowercase().contains("disease")
            || query.to_lowercase().contains("drug")
            || query.to_lowercase().contains("clinical");

        let use_arxiv = query.to_lowercase().contains("quantum")
            || query.to_lowercase().contains("algorithm")
            || query.to_lowercase().contains("machine learning")
            || query.to_lowercase().contains("neural")
            || query.to_lowercase().contains("physics")
            || query.to_lowercase().contains("math");

        // Default to both if unclear
        let (search_pubmed, search_arxiv) = if !use_pubmed && !use_arxiv {
            (true, true)
        } else {
            (use_pubmed, use_arxiv)
        };

        // Search PubMed
        if search_pubmed {
            match self
                .pubmed
                .search(&SearchQuery::new(query).with_max_results(max_results / 2))
                .await
            {
                Ok(results) => {
                    info!("PubMed: Found {} papers", results.papers.len());
                    all_papers.extend(results.papers);
                }
                Err(e) => warn!("PubMed search failed: {}", e),
            }
        }

        // Search arXiv
        if search_arxiv {
            match self
                .arxiv
                .search(&SearchQuery::new(query).with_max_results(max_results / 2))
                .await
            {
                Ok(results) => {
                    info!("arXiv: Found {} papers", results.papers.len());
                    all_papers.extend(results.papers);
                }
                Err(e) => warn!("arXiv search failed: {}", e),
            }
        }

        // Store in Neo4j if context available
        if let Some(ref ctx) = self.beagle_ctx {
            for paper in &all_papers {
                // Store paper node
                let (cypher, params) = beagle_search::storage::create_paper_query(paper);
                if let Err(e) = ctx
                    .graph
                    .cypher_query(&cypher, serde_json::to_value(&params)?)
                    .await
                {
                    warn!("Failed to store paper {}: {}", paper.id, e);
                    continue;
                }

                // Store authors
                for (cypher, params) in
                    beagle_search::storage::create_authors_query(&paper.id, &paper.authors)
                {
                    if let Err(e) = ctx
                        .graph
                        .cypher_query(&cypher, serde_json::to_value(&params)?)
                        .await
                    {
                        warn!("Failed to store authors for {}: {}", paper.id, e);
                    }
                }

                // Store categories (arXiv)
                if !paper.categories.is_empty() {
                    for (cypher, params) in beagle_search::storage::create_categories_query(
                        &paper.id,
                        &paper.categories,
                    ) {
                        if let Err(e) = ctx
                            .graph
                            .cypher_query(&cypher, serde_json::to_value(&params)?)
                            .await
                        {
                            warn!("Failed to store categories for {}: {}", paper.id, e);
                        }
                    }
                }
            }

            info!(
                "Stored {} papers in Neo4j knowledge graph",
                all_papers.len()
            );
        }

        Ok(all_papers)
    }

    pub async fn research(&self, query: &str, session_id: Option<Uuid>) -> Result<ResearchResult> {
        let total_start = Instant::now();
        let mut steps = Vec::new();
        let mut step_number = 1;

        // 1) Detecção de domínio
        let detect_start = Instant::now();
        let domain = self.personality.detect_domain(query);
        steps.push(ResearchStep {
            step_number,
            action: "Detect domain".to_string(),
            result: format!("{:?}", domain),
            duration_ms: detect_start.elapsed().as_millis() as u64,
        });
        step_number += 1;

        // 2) Search scientific papers (NEW!)
        let search_start = Instant::now();
        let papers = self
            .search_and_store_papers(query, 10)
            .await
            .unwrap_or_default();
        let mut paper_sources = Vec::new();
        for paper in &papers {
            paper_sources.push(format!(
                "{} ({}) - {}",
                paper.title,
                paper.source,
                paper.citation()
            ));
        }
        steps.push(ResearchStep {
            step_number,
            action: "Search papers".to_string(),
            result: format!("{} papers found and stored", papers.len()),
            duration_ms: search_start.elapsed().as_millis() as u64,
        });
        step_number += 1;

        // 3) Garantir sessão
        let session_start = Instant::now();
        let (session_id, created) = match session_id {
            Some(id) => (id, false),
            None => {
                let session = self
                    .context_bridge
                    .create_session(None)
                    .await
                    .context("Failed to create conversation session")?;
                (session.id, true)
            }
        };
        steps.push(ResearchStep {
            step_number,
            action: "Select session".to_string(),
            result: if created {
                format!("Created session {}", session_id)
            } else {
                format!("Using session {}", session_id)
            },
            duration_ms: session_start.elapsed().as_millis() as u64,
        });
        step_number += 1;

        // 4) Recuperar contexto
        let context_start = Instant::now();
        let mut retrieved = match self
            .context_bridge
            .retrieve_similar_context(query, 6, 0.35)
            .await
        {
            Ok(mut context) => {
                context.truncate_to_budget(1800);
                context
            }
            Err(err) => {
                warn!("⚠️ Failed to retrieve semantic context: {}", err);
                RetrievedContext {
                    turns: vec![],
                    relevance_scores: vec![],
                    total_tokens: 0,
                }
            }
        };

        if retrieved.turns.is_empty() {
            match self.context_bridge.get_session_history(session_id, 5).await {
                Ok(history) if !history.is_empty() => {
                    let token_estimate: usize =
                        history.iter().map(|turn| turn.char_count() / 4).sum();
                    retrieved.turns = history;
                    retrieved.relevance_scores = vec![1.0; retrieved.turns.len()];
                    retrieved.total_tokens = token_estimate;
                }
                Ok(_) => {}
                Err(err) => warn!("⚠️ Failed to load session history: {}", err),
            }
        }

        let context_string = self.context_bridge.build_context_string(&retrieved);
        steps.push(ResearchStep {
            step_number,
            action: "Retrieve context".to_string(),
            result: format!(
                "{} chunks ({} tokens)",
                retrieved.turns.len(),
                retrieved.total_tokens
            ),
            duration_ms: context_start.elapsed().as_millis() as u64,
        });
        step_number += 1;

        // 5) Montar prompt
        let prompt_start = Instant::now();
        let mut system_prompt = self.personality.system_prompt_for_domain(domain);
        if !context_string.is_empty() {
            system_prompt.push_str("\n\n");
            system_prompt.push_str(&context_string);
        }

        // Add paper citations to context if found
        if !papers.is_empty() {
            system_prompt.push_str("\n\nRELEVANT SCIENTIFIC PAPERS:\n");
            for (idx, paper) in papers.iter().take(5).enumerate() {
                system_prompt.push_str(&format!(
                    "\n{}. {}\n   Abstract: {}\n   Source: {} | URL: {}\n",
                    idx + 1,
                    paper.citation(),
                    paper.abstract_text.chars().take(300).collect::<String>(),
                    paper.source,
                    paper.url.as_ref().unwrap_or(&"N/A".to_string())
                ));
            }
        }

        steps.push(ResearchStep {
            step_number,
            action: "Compose system prompt".to_string(),
            result: format!(
                "{} chars ({} papers cited)",
                system_prompt.len(),
                papers.len()
            ),
            duration_ms: prompt_start.elapsed().as_millis() as u64,
        });
        step_number += 1;

        // 6) Geração
        let llm_start = Instant::now();
        let completion = self
            .anthropic
            .complete(CompletionRequest {
                model: ModelType::ClaudeHaiku45,
                messages: vec![Message::user(query)],
                max_tokens: 1200,
                temperature: 0.8,
                system: Some(system_prompt.clone()),
            })
            .await
            .context("Anthropic completion failed")?;
        steps.push(ResearchStep {
            step_number,
            action: "Generate answer".to_string(),
            result: format!("{} chars", completion.content.len()),
            duration_ms: llm_start.elapsed().as_millis() as u64,
        });
        step_number += 1;

        // 7) Reflexion loop - critique and refine if quality is low
        let mut final_answer = completion.content.clone();
        let mut refinement_iterations = 0;
        let mut quality_score;

        loop {
            let critique_start = Instant::now();
            let (score, critique_text) = self
                .critique_answer(query, &final_answer)
                .await
                .unwrap_or((0.5, "Unable to critique".to_string()));

            quality_score = score;

            steps.push(ResearchStep {
                step_number,
                action: format!("Critique (iteration {})", refinement_iterations + 1),
                result: format!(
                    "Quality score: {:.2} - {}",
                    score,
                    if score >= QUALITY_THRESHOLD {
                        "ACCEPTED"
                    } else {
                        "NEEDS REFINEMENT"
                    }
                ),
                duration_ms: critique_start.elapsed().as_millis() as u64,
            });
            step_number += 1;

            // Accept if quality is high enough or max iterations reached
            if score >= QUALITY_THRESHOLD || refinement_iterations >= MAX_REFINEMENTS {
                if refinement_iterations >= MAX_REFINEMENTS && score < QUALITY_THRESHOLD {
                    warn!(
                        "Max refinements reached with quality {:.2} (target: {:.2})",
                        score, QUALITY_THRESHOLD
                    );
                }
                break;
            }

            // Refine the answer
            refinement_iterations += 1;
            info!(
                "Refining answer (iteration {}, score: {:.2})",
                refinement_iterations, score
            );

            let refine_start = Instant::now();
            match self
                .refine_answer(query, &final_answer, &critique_text, &system_prompt)
                .await
            {
                Ok(refined) => {
                    final_answer = refined;
                    steps.push(ResearchStep {
                        step_number,
                        action: format!("Refine answer (iteration {})", refinement_iterations),
                        result: format!("{} chars", final_answer.len()),
                        duration_ms: refine_start.elapsed().as_millis() as u64,
                    });
                    step_number += 1;
                }
                Err(e) => {
                    warn!("Refinement failed: {}", e);
                    break;
                }
            }
        }

        // 8) Persistir na memória
        let store_start = Instant::now();
        let mut turn = ConversationTurn::new(
            session_id,
            query.to_string(),
            final_answer.clone(),
            domain,
            completion.model.clone(),
        );
        turn.metadata.metrics = PerformanceMetrics {
            latency_ms: llm_start.elapsed().as_millis() as u64,
            tokens_input: None,
            tokens_output: None,
            cost_usd: None,
        };
        turn.metadata.system_prompt_preview = Some(
            system_prompt
                .chars()
                .take(200)
                .collect::<String>()
                .replace('\n', " "),
        );

        if let Err(err) = self.context_bridge.store_turn(turn).await {
            warn!("⚠️ Failed to persist conversation turn: {}", err);
        }
        steps.push(ResearchStep {
            step_number,
            action: "Persist turn".to_string(),
            result: "Stored in contextual memory".to_string(),
            duration_ms: store_start.elapsed().as_millis() as u64,
        });

        let total_duration = total_start.elapsed();

        // Calculate total LLM calls (initial + critique + refinements)
        let total_llm_calls = 1 + (refinement_iterations * 2); // 1 initial + (critique + refine) per iteration

        let metrics = ResearchMetrics {
            total_duration_ms: total_duration.as_millis() as u64,
            llm_calls: total_llm_calls,
            context_chunks_retrieved: retrieved.turns.len(),
            refinement_iterations,
            quality_score,
        };

        info!(
            "ResearcherAgent finished in {} ms (quality {:.2}, {} refinements)",
            metrics.total_duration_ms, metrics.quality_score, refinement_iterations
        );

        Ok(ResearchResult {
            answer: final_answer,
            domain,
            steps,
            metrics,
            session_id,
            sources: if paper_sources.is_empty() {
                None
            } else {
                Some(paper_sources)
            },
        })
    }
}
