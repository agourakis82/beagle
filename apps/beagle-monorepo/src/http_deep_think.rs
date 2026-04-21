// http_deep_think.rs
//
// POST /api/cognitive/deep-think — chained cognitive journey that proves
// the three novelty endpoints (void, fractal, exocortex) can actually
// COOPERATE, not just coexist in parallel.
//
// Pipeline:
//   1. FRACTAL stage  — expand the root prompt into a tree of depth D,
//                       branching K. Reuses http_fractal::expand_one and
//                       summarize_terminal (same LLM path as /api/fractal/recurse).
//   2. VOID stage     — for up to 3 leaf nodes whose summary is "stuck"
//                       (short OR contains "unclear"/"error"/"don't know"),
//                       run pipeline_void::handle_deadlock. Real ndarray
//                       tensor math, same as /dev/void.
//   3. PHI stage      — build a substrate from the unified corpus of fractal
//                       summaries + void insights; run integrated_information
//                       (embedding-TPM via EmbeddingClient when available,
//                       else activation-TPM). Same formula as /api/exocortex/process.
//   4. DEEP_THINK     — close-out CognitiveEvent emitted for SSE subscribers
//                       to know the journey is complete.
//
// NO mocks. NO canned paths. Every LLM call goes through the real tiered
// router; every Φ number is computed from real inputs via the real MIP
// search. Bounds are enforced by HARD_MAX_DEPTH=2 and HARD_MAX_BRANCHING=2
// so a single call is at most 7 LLM fractal calls + 3 void journeys + 1
// Φ computation.

use crate::cognitive_events::{emit, CognitiveEvent};
use crate::http::AppState;
use crate::http_fractal::{expand_one, summarize_terminal, FractalNode};
use crate::jobs::{
    DeepThinkSummary, FractalTreeSummary, PhiMeasurementSummary, VoidJourneySummary,
};
use crate::phi_iit::{integrated_information, tpm_from_activations, tpm_from_embeddings, MAX_SUBSTRATE};
use axum::{extract::State, http::StatusCode, routing::post, Json, Router};
use beagle_llm::embedding::EmbeddingClient;
use beagle_smart_router::HrvTierHint;
use chrono::Utc;
use ndarray::Array2;
use once_cell::sync::Lazy;
use serde::{Deserialize, Serialize};
use tokio::task::JoinSet;
use tracing::{info, warn};
use uuid::Uuid;

const HARD_MAX_DEPTH: u8 = 2;
const HARD_MAX_BRANCHING: u8 = 2;
const MAX_VOID_LEAVES: usize = 3;

static EMBEDDING_CLIENT: Lazy<EmbeddingClient> = Lazy::new(|| {
    let url = std::env::var("EMBEDDING_URL")
        .unwrap_or_else(|_| "http://t560.local:8001/v1".to_string());
    EmbeddingClient::new(url)
});

#[derive(Deserialize)]
pub struct DeepThinkRequest {
    pub root_prompt: String,
    #[serde(default = "default_depth")]
    pub max_depth: u8,
    #[serde(default = "default_branching")]
    pub branching: u8,
    #[serde(default = "default_void_on_stuck")]
    pub void_on_stuck: bool,
}

fn default_depth() -> u8 {
    2
}
fn default_branching() -> u8 {
    2
}
fn default_void_on_stuck() -> bool {
    true
}

#[derive(Serialize)]
pub struct FractalBlock {
    pub root_id: String,
    pub node_count: usize,
    pub nodes: Vec<FractalNode>,
}

#[derive(Serialize)]
pub struct VoidJourneyBlock {
    pub journey_id: String,
    pub focus: String,
    pub insights: Vec<String>,
    pub raw_result: String,
}

#[derive(Serialize)]
pub struct PhiBlock {
    pub phi: f64,
    pub ei_full: f64,
    pub ei_cut: f64,
    pub mip_partition: (Vec<String>, Vec<String>),
    pub substrate: Vec<String>,
    pub tpm_source: String,
    pub awareness_level: String,
}

#[derive(Serialize)]
pub struct DeepThinkResponse {
    pub journey_id: String,
    pub root_prompt: String,
    pub duration_ms: u64,
    pub fractal: FractalBlock,
    pub void_journeys: Vec<VoidJourneyBlock>,
    pub phi_measurement: PhiBlock,
    pub hrv_tier: String,
    pub truth_mode: &'static str,
}

/// A leaf is "stuck" if the LLM response was very short or contains the
/// universal tells of frustration / inability. These leaves get a void
/// journey next — the whole point is to automate the escape from shallow
/// answers.
fn is_stuck_leaf(summary: &str) -> bool {
    let s = summary.trim().to_lowercase();
    if s.len() < 30 {
        return true;
    }
    let tells = [
        "unclear",
        "i don't know",
        "not sure",
        "error",
        "i cannot",
        "it is not",
        "i'm unable",
        "i am unable",
    ];
    tells.iter().any(|t| s.contains(t))
}

fn tokenize(text: &str) -> Vec<String> {
    const STOPWORDS: &[&str] = &[
        "a", "an", "and", "are", "as", "at", "be", "by", "for", "from", "has", "have", "he",
        "in", "is", "it", "its", "of", "on", "or", "that", "the", "this", "to", "was", "were",
        "will", "with", "what", "how", "why", "do", "does", "did", "can", "you", "i", "we",
        "they", "them", "me", "my", "your", "our", "their", "s", "t",
    ];
    text.to_lowercase()
        .split(|c: char| !c.is_alphanumeric())
        .filter(|w| w.len() >= 3 && !STOPWORDS.contains(w))
        .map(|w| w.to_string())
        .collect()
}

fn awareness_label(phi: f64) -> &'static str {
    if phi < 0.01 {
        "disintegrated"
    } else if phi < 0.1 {
        "minimal"
    } else if phi < 0.5 {
        "reflective"
    } else {
        "integrated"
    }
}

fn parse_void_insights(raw: &str) -> Vec<String> {
    raw.lines()
        .map(|l| l.trim())
        .filter(|l| l.starts_with('•'))
        .map(|l| l.trim_start_matches('•').trim().to_string())
        .collect()
}

fn extract_void_max_depth(raw: &str) -> Option<f64> {
    for line in raw.lines() {
        if line.contains("Profundidade:") {
            if let Some(val) = line.split(':').nth(1) {
                return val.trim().parse::<f64>().ok();
            }
        }
    }
    None
}

async fn deep_think_handler(
    State(state): State<AppState>,
    Json(req): Json<DeepThinkRequest>,
) -> Result<Json<DeepThinkResponse>, (StatusCode, String)> {
    let max_depth = req.max_depth.min(HARD_MAX_DEPTH).max(1);
    let branching = req.branching.min(HARD_MAX_BRANCHING).max(1);
    let root_prompt = req.root_prompt.trim().to_string();
    if root_prompt.is_empty() {
        return Err((StatusCode::BAD_REQUEST, "root_prompt required".into()));
    }
    let journey_id = format!("deep-think-{}", Uuid::new_v4());
    info!(
        "deep-think: id={} depth={} branching={} void_on_stuck={}",
        journey_id, max_depth, branching, req.void_on_stuck
    );
    let t0 = std::time::Instant::now();

    // Resolve HRV hint once — every inner LLM call inherits it.
    let physio = state.observer.latest_physio_snapshot().await;
    let hrv_level = physio.as_ref().and_then(|s| s.hrv_level.as_deref());
    let hint = HrvTierHint::from_flow_state(hrv_level);

    // ─── Stage 1: FRACTAL ───────────────────────────────────────────
    // Level-parallel recursion via JoinSet, same pattern as /api/fractal/recurse.
    let (root_summary, root_children_prompts) = expand_one(&root_prompt, branching, hint).await;
    let root_id = Uuid::new_v4().to_string();
    let mut all: Vec<FractalNode> = Vec::new();
    let mut frontier: Vec<(String, u8, String)> = root_children_prompts
        .into_iter()
        .map(|p| (root_id.clone(), 1u8, p))
        .collect();
    let mut root_children_ids: Vec<String> = Vec::with_capacity(frontier.len());

    for d in 1..=max_depth {
        if frontier.is_empty() {
            break;
        }
        let mut joins: JoinSet<(String, u8, String, String, Vec<String>)> = JoinSet::new();
        for (parent_id, depth, prompt) in frontier.drain(..) {
            let b = if depth < max_depth { branching } else { 0 };
            let hint_copy = hint;
            joins.spawn(async move {
                if b == 0 {
                    let summary = summarize_terminal(&prompt, hint_copy).await;
                    (parent_id, depth, prompt, summary, Vec::new())
                } else {
                    let (summary, children_prompts) = expand_one(&prompt, b, hint_copy).await;
                    (parent_id, depth, prompt, summary, children_prompts)
                }
            });
        }
        let mut next: Vec<(String, u8, String)> = Vec::new();
        while let Some(joined) = joins.join_next().await {
            match joined {
                Ok((parent_id, depth, prompt, summary, children_prompts)) => {
                    let my_id = Uuid::new_v4().to_string();
                    let mut child_ids: Vec<String> = Vec::with_capacity(children_prompts.len());
                    for cp in children_prompts {
                        let child_id = Uuid::new_v4().to_string();
                        child_ids.push(child_id.clone());
                        next.push((my_id.clone(), depth + 1, cp));
                    }
                    if parent_id == root_id && depth == 1 {
                        root_children_ids.push(my_id.clone());
                    } else if let Some(parent_node) =
                        all.iter_mut().find(|n| n.id == parent_id)
                    {
                        parent_node.children.push(my_id.clone());
                    }
                    all.push(FractalNode {
                        id: my_id,
                        parent_id: Some(parent_id),
                        depth,
                        prompt,
                        summary,
                        children: child_ids,
                    });
                    let _ = d;
                }
                Err(e) => warn!("deep-think: fractal task join error: {}", e),
            }
        }
        frontier = next;
    }

    let mut nodes: Vec<FractalNode> = Vec::with_capacity(all.len() + 1);
    nodes.push(FractalNode {
        id: root_id.clone(),
        parent_id: None,
        depth: 0,
        prompt: root_prompt.clone(),
        summary: root_summary.clone(),
        children: root_children_ids,
    });
    nodes.extend(all);
    let node_count = nodes.len();

    // Emit fractal CognitiveEvent — same shape as /api/fractal/recurse emits.
    let fractal_summary = FractalTreeSummary {
        root_id: root_id.clone(),
        root_prompt: root_prompt.chars().take(160).collect(),
        max_depth,
        branching,
        node_count,
        generated_at: Utc::now(),
        duration_ms: t0.elapsed().as_millis() as u64,
        truth_mode: "observed".to_string(),
    };
    state.fractals.append(fractal_summary.clone()).await;
    emit(&state.cognitive_tx, CognitiveEvent::Fractal(fractal_summary));

    // ─── Stage 2: VOID (conditional on stuck leaves) ────────────────
    let mut void_blocks: Vec<VoidJourneyBlock> = Vec::new();
    if req.void_on_stuck {
        let stuck_leaves: Vec<&FractalNode> = nodes
            .iter()
            .filter(|n| n.children.is_empty() && is_stuck_leaf(&n.summary))
            .take(MAX_VOID_LEAVES)
            .collect();
        info!("deep-think: {} stuck leaves → void", stuck_leaves.len());

        #[cfg(feature = "void")]
        {
            use crate::pipeline_void::handle_deadlock;
            for leaf in stuck_leaves {
                let vid = format!("void-{}", Uuid::new_v4());
                let focus = leaf.summary.chars().take(120).collect::<String>();
                match handle_deadlock(&vid, "fractal_leaf_stuck", &focus).await {
                    Ok(raw) => {
                        let insights = parse_void_insights(&raw);
                        let max_depth_v = extract_void_max_depth(&raw);
                        let v_summary = VoidJourneySummary {
                            journey_id: vid.clone(),
                            focus: focus.clone(),
                            target_depth: 4.0,
                            max_depth_reached: max_depth_v,
                            duration_ms: None,
                            insight_count: insights.len(),
                            probe_result: None,
                            completed_at: Utc::now(),
                            truth_mode: "observed".to_string(),
                        };
                        state.voids.append(v_summary.clone()).await;
                        emit(&state.cognitive_tx, CognitiveEvent::Void(v_summary));
                        void_blocks.push(VoidJourneyBlock {
                            journey_id: vid,
                            focus,
                            insights,
                            raw_result: raw,
                        });
                    }
                    Err(e) => {
                        warn!("deep-think: void journey {} failed: {}", vid, e);
                    }
                }
            }
        }
        #[cfg(not(feature = "void"))]
        {
            warn!("deep-think: void feature not compiled; skipping void stage");
        }
    }

    // ─── Stage 3: PHI (over unified corpus) ─────────────────────────
    // Corpus = every fractal summary + every void insight. We tokenize,
    // dedupe, cap at MAX_SUBSTRATE=8 distinct tokens.
    let mut corpus_text = String::new();
    for n in &nodes {
        corpus_text.push_str(&n.summary);
        corpus_text.push('\n');
    }
    for v in &void_blocks {
        for ins in &v.insights {
            corpus_text.push_str(ins);
            corpus_text.push('\n');
        }
    }
    let mut substrate: Vec<String> = {
        let mut seen = std::collections::BTreeSet::new();
        tokenize(&corpus_text)
            .into_iter()
            .filter(|t| seen.insert(t.clone()))
            .take(MAX_SUBSTRATE)
            .collect()
    };
    while substrate.len() < 2 {
        substrate.push(format!("_pad_{}", substrate.len()));
    }

    // Build TPM — embedding first, honest fallback.
    let substrate_refs: Vec<&str> = substrate.iter().map(|s| s.as_str()).collect();
    let (tpm, tpm_source): (Array2<f64>, String) =
        match EMBEDDING_CLIENT.embed_batch(&substrate_refs).await {
            Ok(vecs) if vecs.len() == substrate.len() => {
                (tpm_from_embeddings(&vecs), "embeddings".to_string())
            }
            Ok(_) | Err(_) => {
                // Fall back to activations using the run-history window.
                let recent = state.jobs.list_recent(50).await;
                let substrate_idx: std::collections::HashMap<&str, usize> = substrate
                    .iter()
                    .enumerate()
                    .map(|(i, s)| (s.as_str(), i))
                    .collect();
                let mut activations: Vec<Vec<usize>> = Vec::new();
                for run in &recent {
                    let toks = tokenize(&run.question);
                    let idxs: Vec<usize> = toks
                        .iter()
                        .filter_map(|t| substrate_idx.get(t.as_str()).copied())
                        .collect();
                    if idxs.len() >= 2 {
                        activations.push(idxs);
                    }
                }
                let self_idxs: Vec<usize> = tokenize(&corpus_text)
                    .iter()
                    .filter_map(|t| substrate_idx.get(t.as_str()).copied())
                    .collect();
                if self_idxs.len() >= 2 {
                    activations.push(self_idxs);
                }
                (
                    tpm_from_activations(substrate.len(), &activations, 0.5),
                    "activations".to_string(),
                )
            }
        };
    let phi_result = integrated_information(&tpm);
    let mip_partition = (
        phi_result
            .mip_lhs
            .iter()
            .map(|&i| substrate[i].clone())
            .collect::<Vec<_>>(),
        phi_result
            .mip_rhs
            .iter()
            .map(|&i| substrate[i].clone())
            .collect::<Vec<_>>(),
    );
    let awareness = awareness_label(phi_result.phi);

    // Emit phi CognitiveEvent (same shape as /api/exocortex/process emits).
    let phi_summary = PhiMeasurementSummary {
        query_snippet: root_prompt.chars().take(120).collect(),
        phi: phi_result.phi,
        substrate_size: substrate.len(),
        mip_partition: mip_partition.clone(),
        awareness_level: awareness.to_string(),
        router_tier: format!("deep-think+hrv={:?}", hint),
        measured_at: Utc::now(),
        duration_ms: t0.elapsed().as_millis() as u64,
        truth_mode: "observed".to_string(),
        tpm_source: tpm_source.clone(),
    };
    state.phis.append(phi_summary.clone()).await;
    emit(&state.cognitive_tx, CognitiveEvent::Phi(phi_summary));

    // ─── Close-out ──────────────────────────────────────────────────
    let duration_ms = t0.elapsed().as_millis() as u64;
    let dt_summary = DeepThinkSummary {
        journey_id: journey_id.clone(),
        root_prompt: root_prompt.chars().take(160).collect(),
        fractal_node_count: node_count,
        void_journey_count: void_blocks.len(),
        phi: phi_result.phi,
        tpm_source: tpm_source.clone(),
        hrv_tier: format!("{:?}", hint),
        duration_ms,
        generated_at: Utc::now(),
        truth_mode: "observed".to_string(),
    };
    state.deep_thinks.append(dt_summary.clone()).await;
    emit(&state.cognitive_tx, CognitiveEvent::DeepThink(dt_summary));

    Ok(Json(DeepThinkResponse {
        journey_id,
        root_prompt,
        duration_ms,
        fractal: FractalBlock {
            root_id,
            node_count,
            nodes,
        },
        void_journeys: void_blocks,
        phi_measurement: PhiBlock {
            phi: phi_result.phi,
            ei_full: phi_result.ei_full,
            ei_cut: phi_result.ei_cut,
            mip_partition,
            substrate,
            tpm_source,
            awareness_level: awareness.to_string(),
        },
        hrv_tier: format!("{:?}", hint),
        truth_mode: "observed",
    }))
}

pub fn deep_think_routes() -> Router<AppState> {
    Router::new().route("/api/cognitive/deep-think", post(deep_think_handler))
}
