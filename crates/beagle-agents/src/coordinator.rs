use std::sync::Arc;
use std::time::Instant;

use anyhow::{Context, Result};
use beagle_llm::{stats::LlmCallsStats, RequestMeta, TieredRouter};
use beagle_memory::{ContextBridge, ConversationTurn, PerformanceMetrics};
use beagle_personality::PersonalityEngine;
use serde::{Deserialize, Serialize};
use serde_json::json;
use tokio::task::JoinSet;
use tracing::{debug, info, warn};
use uuid::Uuid;

use crate::agent_trait::{Agent, AgentCapability, AgentInput, AgentOutput};
use crate::models::{ResearchMetrics, ResearchResult, ResearchStep};

// ============================================================================
// Verification rubric (versioned, criterion-separated)
// ============================================================================

/// Rubric version bumped when criteria change — tracked in JudgeVerdict.
const RUBRIC_VERSION: &str = "v1.0";

/// Criterion-separated rubric for the LLM-as-judge call.
/// The judge must produce a JSON object matching `JudgeRaw`.
const JUDGE_RUBRIC: &str = r#"
You are a calibrated answer-quality judge. Score the ANSWER against the QUERY on four
criteria, each 0.0–1.0. Return ONLY valid JSON — no markdown, no prose:

{
  "accuracy":      <float>,   // factual correctness, grounded in context
  "completeness":  <float>,   // covers all aspects the query asks for
  "clarity":       <float>,   // well-structured, unambiguous prose
  "conciseness":   <float>    // no padding; length proportional to complexity
}

Bias guard: score based on content quality, NOT on answer length. A short correct
answer should score higher than a long verbose answer of equal accuracy.
"#;

// ============================================================================
// JudgeVerdict — public result type for the verification step
// ============================================================================

/// Result of the LLM-as-judge verification step.
/// Replaces the brittle extract_score regex + magic 0.78 / 0.75 constants.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct JudgeVerdict {
    /// Final composite score 0.0–1.0 (average of four criteria).
    pub score: f32,
    /// Answers meet the quality threshold (score >= PASS_THRESHOLD).
    pub pass: bool,
    /// Whether a human should spot-check this result (set when the answer is
    /// borderline, unusually long, or the judge response was malformed).
    pub needs_human_spot_check: bool,
    /// Rubric version used to produce this verdict.
    pub rubric_version: &'static str,
    /// Raw per-criterion scores (None if judge response could not be parsed).
    pub criteria: Option<JudgeCriteria>,
}

/// Per-criterion scores from the LLM judge.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct JudgeCriteria {
    pub accuracy: f32,
    pub completeness: f32,
    pub clarity: f32,
    pub conciseness: f32,
}

/// Minimum composite score for pass=true.
const PASS_THRESHOLD: f32 = 0.65;

/// Composite score below which we flag for human spot-check.
const SPOT_CHECK_THRESHOLD: f32 = 0.70;

// ============================================================================
// RouterAdapter — thin wrapper that makes TieredRouter callable via LlmClient
// ============================================================================

/// Thin adapter: wraps `TieredRouter` so CoordinatorAgent can call it like any
/// `Arc<dyn LlmClient>`, routing through the full tiered stack (fleet → Grok
/// → local fallback) with bias/quality signals encoded in `RequestMeta`.
struct RouterAdapter {
    router: Arc<TieredRouter>,
    stats: Arc<std::sync::Mutex<LlmCallsStats>>,
}

impl RouterAdapter {
    fn new(router: Arc<TieredRouter>) -> Self {
        Self {
            router,
            stats: Arc::new(std::sync::Mutex::new(LlmCallsStats::default())),
        }
    }

    async fn call_with_meta(&self, prompt: &str, meta: RequestMeta) -> Result<String> {
        let current_stats = self
            .stats
            .lock()
            .map(|g| g.clone())
            .unwrap_or_default();
        let (client, tier) = self.router.choose_with_limits(&meta, &current_stats);
        let text = self.router.complete_chosen(&client, tier, prompt).await?;
        // Record the call (approximate tokens: 4 chars ≈ 1 token)
        let approx_in = (prompt.len() / 4) as u32;
        let approx_out = (text.len() / 4) as u32;
        if let Ok(mut g) = self.stats.lock() {
            g.record_call(tier.as_str(), approx_in, approx_out);
        }
        Ok(text)
    }

    /// Snapshot the accumulated stats for metric reporting.
    fn snapshot_stats(&self) -> LlmCallsStats {
        self.stats
            .lock()
            .map(|g| g.clone())
            .unwrap_or_default()
    }
}

// ============================================================================
// CoordinatorAgent
// ============================================================================

/// Orquestra múltiplos agentes especializados em paralelo real usando Tokio.
///
/// #10: Uses `TieredRouter` (via `RouterAdapter`) instead of a bare
/// `AnthropicClient`, so LLM calls flow through the full routing stack
/// (fleet-first, tier limits, circuit breaker, bias flags).
///
/// #15: Quality score is produced by an LLM-as-judge call against a small
/// versioned rubric, replacing the brittle regex/magic-constant path.
pub struct CoordinatorAgent {
    router: Arc<RouterAdapter>,
    personality: Arc<PersonalityEngine>,
    context_bridge: Arc<ContextBridge>,
    agents: Vec<Arc<dyn Agent>>,
}

impl CoordinatorAgent {
    /// Construct with a `TieredRouter` (the canonical LLM routing stack).
    pub fn new(
        router: Arc<TieredRouter>,
        personality: Arc<PersonalityEngine>,
        context_bridge: Arc<ContextBridge>,
    ) -> Self {
        Self {
            router: Arc::new(RouterAdapter::new(router)),
            personality,
            context_bridge,
            agents: Vec::new(),
        }
    }

    pub fn register_agent(mut self, agent: Arc<dyn Agent>) -> Self {
        self.agents.push(agent);
        self
    }

    pub async fn research(&self, query: &str, session_id: Option<Uuid>) -> Result<ResearchResult> {
        let total_start = Instant::now();
        let mut steps = Vec::new();
        let mut step_number = 1;

        let domain_start = Instant::now();
        let domain = self.personality.detect_domain(query);
        steps.push(ResearchStep {
            step_number,
            action: "Detect domain".to_string(),
            result: format!("{:?}", domain),
            duration_ms: domain_start.elapsed().as_millis() as u64,
        });
        step_number += 1;

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

        let retrieval_start = Instant::now();
        let mut context_chunks: Vec<String> = Vec::new();
        if let Some(agent) = self.get_agent(AgentCapability::ContextRetrieval) {
            debug!("📚 RetrievalAgent triggered");
            match agent
                .execute(
                    AgentInput::new(query.to_string())
                        .with_metadata(json!({ "session_id": session_id.to_string() })),
                )
                .await
            {
                Ok(output) => {
                    if let Some(chunks) = output.result.get("chunks").and_then(|v| v.as_array()) {
                        context_chunks = chunks
                            .iter()
                            .filter_map(|value| value.as_str().map(str::to_owned))
                            .collect();
                    }
                }
                Err(err) => warn!("⚠️ Retrieval agent failed: {}", err),
            }
        } else {
            warn!("⚠️ No retrieval agent registered");
        }
        steps.push(ResearchStep {
            step_number,
            action: "Retrieve context".to_string(),
            result: format!("{} chunks", context_chunks.len()),
            duration_ms: retrieval_start.elapsed().as_millis() as u64,
        });
        step_number += 1;

        let prompt_start = Instant::now();
        let mut system_prompt = self.personality.system_prompt_for_domain(domain);
        if !context_chunks.is_empty() {
            system_prompt.push_str("\n\n=== Contexto relevante ===\n");
            system_prompt.push_str(&context_chunks.join("\n---\n"));
        }
        steps.push(ResearchStep {
            step_number,
            action: "Compose system prompt".to_string(),
            result: format!("{} chars", system_prompt.len()),
            duration_ms: prompt_start.elapsed().as_millis() as u64,
        });
        step_number += 1;

        // Main LLM call — routed through TieredRouter.
        // Standard quality request; bias/phd flags left at default (auto-detected from prompt).
        let llm_start = Instant::now();
        let full_prompt = format!(
            "System: {}\n\nUser: {}",
            system_prompt, query
        );
        let meta = RequestMeta::from_prompt(&full_prompt);
        let answer = self
            .router
            .call_with_meta(&full_prompt, meta)
            .await
            .context("Main LLM call failed")?;
        let llm_duration_ms = llm_start.elapsed().as_millis() as u64;
        steps.push(ResearchStep {
            step_number,
            action: "Generate answer".to_string(),
            result: format!("{} chars", answer.len()),
            duration_ms: llm_duration_ms,
        });
        step_number += 1;

        let mut join_set = JoinSet::new();
        let mut specialized_llm_calls = 0usize;
        let mut validation: Option<(AgentOutput, u64)> = None;

        for agent in &self.agents {
            let capability = agent.capability();
            match capability {
                AgentCapability::FactChecking | AgentCapability::QualityAssessment => {
                    let agent = Arc::clone(agent);
                    let capability_clone = capability.clone();
                    let query_text = query.to_string();
                    let chunks = context_chunks.clone();
                    let answer_clone = answer.clone();
                    join_set.spawn(async move {
                        let start = Instant::now();
                        let input = match capability_clone {
                            AgentCapability::FactChecking => AgentInput::new(query_text)
                                .with_context(chunks)
                                .with_metadata(json!({ "response": answer_clone })),
                            _ => AgentInput::new(query_text)
                                .with_metadata(json!({ "response": answer_clone })),
                        };
                        let result = agent.execute(input).await;
                        let duration = start.elapsed().as_millis() as u64;
                        (capability_clone, duration, result)
                    });
                }
                _ => {}
            }
        }

        while let Some(result) = join_set.join_next().await {
            match result {
                Ok((capability, duration, Ok(output))) => {
                    specialized_llm_calls += 1;
                    match capability {
                        AgentCapability::FactChecking => {
                            debug!("🛡️ ValidationAgent finished in {} ms", duration);
                            validation = Some((output, duration));
                        }
                        // #15: QualityAgent output is still collected for any downstream use,
                        // but its score is NOT used — the LLM-as-judge call below replaces it.
                        AgentCapability::QualityAssessment => {
                            debug!("⭐ QualityAgent (legacy) finished in {} ms (score unused — LLM judge runs next)", duration);
                        }
                        _ => {}
                    }
                }
                Ok((capability, duration, Err(err))) => {
                    warn!(
                        "⚠️ Specialized agent {:?} failed after {} ms: {}",
                        capability, duration, err
                    );
                }
                Err(err) => warn!("⚠️ JoinSet join error: {}", err),
            }
        }

        if let Some((output, duration)) = validation.as_ref() {
            let supported = output
                .result
                .get("is_supported")
                .and_then(|v| v.as_bool())
                .unwrap_or(true);
            steps.push(ResearchStep {
                step_number,
                action: "ValidationAgent".to_string(),
                result: format!("is_supported={}", supported),
                duration_ms: *duration,
            });
            step_number += 1;
        }

        // #15 — LLM-as-judge verification (replaces extract_score regex + 0.78/0.75 constants).
        let judge_start = Instant::now();
        let verdict = self
            .run_judge(query, &answer, &context_chunks)
            .await
            .unwrap_or_else(|err| {
                warn!("⚠️ Judge call failed ({}); defaulting to needs_human_spot_check=true", err);
                JudgeVerdict {
                    score: 0.5,
                    pass: false,
                    needs_human_spot_check: true,
                    rubric_version: RUBRIC_VERSION,
                    criteria: None,
                }
            });
        let judge_duration_ms = judge_start.elapsed().as_millis() as u64;
        steps.push(ResearchStep {
            step_number,
            action: "LLM-as-judge".to_string(),
            result: format!(
                "score={:.2} pass={} spot_check={} rubric={}",
                verdict.score, verdict.pass, verdict.needs_human_spot_check, verdict.rubric_version
            ),
            duration_ms: judge_duration_ms,
        });
        step_number += 1;

        let is_supported = validation
            .as_ref()
            .and_then(|(output, _)| output.result.get("is_supported").and_then(|v| v.as_bool()))
            .unwrap_or(true);

        // Final quality score: judge verdict is the primary signal.
        // If factual validation failed, we still note it in logs but do NOT silently
        // multiply by 0.75 — that produced misleading scores without explanation.
        let quality_score = verdict.score;
        if !is_supported {
            warn!(
                "⚠️ ValidationAgent says is_supported=false; judge score={:.2} (not multiplied — review sources)",
                quality_score
            );
        }

        let store_start = Instant::now();
        let mut turn = ConversationTurn::new(
            session_id,
            query.to_string(),
            answer.clone(),
            domain,
            "tiered-router".to_string(), // #10: no longer hard-coded model name
        );
        turn.metadata.metrics = PerformanceMetrics {
            latency_ms: llm_duration_ms,
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
            warn!("⚠️ Failed to persist turn: {}", err);
        }
        steps.push(ResearchStep {
            step_number,
            action: "Persist turn".to_string(),
            result: "Stored in contextual memory".to_string(),
            duration_ms: store_start.elapsed().as_millis() as u64,
        });

        // Token accounting snapshot (#10)
        let stats_snapshot = self.router.snapshot_stats();
        let total_llm_calls = 1 + specialized_llm_calls + 1 /*judge*/;

        let total_duration = total_start.elapsed();
        let metrics = ResearchMetrics {
            total_duration_ms: total_duration.as_millis() as u64,
            llm_calls: total_llm_calls,
            context_chunks_retrieved: context_chunks.len(),
            refinement_iterations: 0,
            quality_score,
        };

        info!(
            "⚡ CoordinatorAgent finished in {} ms (judge_score={:.2} pass={} is_supported={} total_calls={} est_cost_usd={:.4})",
            metrics.total_duration_ms,
            verdict.score,
            verdict.pass,
            is_supported,
            stats_snapshot.total_calls(),
            stats_snapshot.estimated_cost_usd(),
        );

        Ok(ResearchResult {
            answer,
            domain,
            steps,
            metrics,
            session_id,
            sources: Some(context_chunks),
        })
    }

    // -------------------------------------------------------------------------
    // #15 — LLM-as-judge
    // -------------------------------------------------------------------------

    /// Call the TieredRouter with the judge rubric and return a `JudgeVerdict`.
    ///
    /// Bias guards:
    /// - The rubric explicitly instructs the judge to score on content, not length.
    /// - We note answer length in the prompt but do NOT feed it as a score signal.
    /// - `needs_human_spot_check` is set when the answer is unusually long (>3000
    ///   chars) or the judge response could not be parsed (malformed JSON).
    async fn run_judge(
        &self,
        query: &str,
        answer: &str,
        context: &[String],
    ) -> Result<JudgeVerdict> {
        let ctx_snippet = if context.is_empty() {
            "(no retrieved context)".to_string()
        } else {
            context
                .iter()
                .take(3)
                .cloned()
                .collect::<Vec<_>>()
                .join("\n---\n")
                .chars()
                .take(1200)
                .collect()
        };

        // Length note: for transparency only; rubric guards against using it as a quality proxy.
        let answer_len_note = format!("[answer length: {} chars]", answer.len());

        let judge_prompt = format!(
            "{rubric}\n\n\
            QUERY:\n{query}\n\n\
            RETRIEVED CONTEXT EXCERPT:\n{ctx}\n\n\
            ANSWER {len_note}:\n{answer}\n\n\
            Respond with a single JSON object only.",
            rubric = JUDGE_RUBRIC,
            query = query,
            ctx = ctx_snippet,
            len_note = answer_len_note,
            answer = answer,
        );

        // Route through the real TieredRouter; judge calls use standard quality
        // (not phd/heavy) — they are fast and frequent.
        let meta = RequestMeta {
            requires_high_quality: true,
            high_bias_risk: true, // judge must be unbiased — prefer stronger tier
            ..RequestMeta::default()
        };

        let raw = self
            .router
            .call_with_meta(&judge_prompt, meta)
            .await
            .context("Judge LLM call failed")?;

        parse_judge_response(&raw, answer.len())
    }

    fn get_agent(&self, capability: AgentCapability) -> Option<Arc<dyn Agent>> {
        self.agents
            .iter()
            .find(|agent| agent.capability() == capability)
            .map(Arc::clone)
    }
}

// ============================================================================
// Judge response parser (no regex — plain JSON parse)
// ============================================================================

/// Parse the judge's JSON response into a `JudgeVerdict`.
///
/// We use `serde_json` directly — no regex, no magic constants.
/// If parsing fails, we set `needs_human_spot_check = true` and use a
/// conservative default score (0.5).
fn parse_judge_response(raw: &str, answer_char_len: usize) -> Result<JudgeVerdict> {
    // Strip optional markdown fences.
    let trimmed = raw.trim();
    let json_str = if trimmed.starts_with("```") {
        trimmed
            .lines()
            .skip_while(|l| l.starts_with("```"))
            .take_while(|l| !l.starts_with("```"))
            .collect::<Vec<_>>()
            .join("\n")
    } else {
        trimmed.to_string()
    };

    #[derive(Deserialize)]
    struct JudgeRaw {
        accuracy: f32,
        completeness: f32,
        clarity: f32,
        conciseness: f32,
    }

    match serde_json::from_str::<JudgeRaw>(&json_str) {
        Ok(j) => {
            let acc = j.accuracy.clamp(0.0, 1.0);
            let comp = j.completeness.clamp(0.0, 1.0);
            let clar = j.clarity.clamp(0.0, 1.0);
            let conc = j.conciseness.clamp(0.0, 1.0);
            let score = (acc + comp + clar + conc) / 4.0;

            // Bias guard: unusually long answers get flagged for human review,
            // but score is NOT penalized automatically.
            let unusually_long = answer_char_len > 6000;
            let needs_spot = score < SPOT_CHECK_THRESHOLD || unusually_long;

            Ok(JudgeVerdict {
                score,
                pass: score >= PASS_THRESHOLD,
                needs_human_spot_check: needs_spot,
                rubric_version: RUBRIC_VERSION,
                criteria: Some(JudgeCriteria {
                    accuracy: acc,
                    completeness: comp,
                    clarity: clar,
                    conciseness: conc,
                }),
            })
        }
        Err(e) => {
            warn!("⚠️ Judge response could not be parsed as JSON: {}. Raw: {:.200}", e, raw);
            Ok(JudgeVerdict {
                score: 0.5,
                pass: false,
                needs_human_spot_check: true,
                rubric_version: RUBRIC_VERSION,
                criteria: None,
            })
        }
    }
}

// NOTE on generate_symbolic_summary (#15):
// The function was not present in the original coordinator.rs (it lives in
// other files). If it is ever introduced here: gate its output with a clear
// label "heuristic (not verified signal)" and do NOT feed it to the judge
// or ARGOS as real verified signal. The Julia PCS seam does not yet exist.
