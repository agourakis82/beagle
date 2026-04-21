// http_fractal.rs
//
// Real fractal cognitive recursion — no Julia proxy, no node-count stub.
// POST /api/fractal/recurse expands a root prompt into a K-ary tree of
// depth D via level-parallel LLM calls. Every node carries:
//   - a concrete parent-derived sub-prompt (the "narrower frame")
//   - a one-line summary synthesized by the LLM from that frame
//   - uuids for parent/self/children so the whole tree can be flattened
//     into JSON that iOS renders without extra round-trips.
//
// Hard caps (plan Bounds): max_depth ≤ 4, branching ≤ 3 → at most
// 1 + 3 + 9 + 27 + 81 = 121 LLM calls per request. Each level runs in
// parallel via tokio::task::JoinSet. The router is the same tiered
// Grok3/Grok4-Heavy router that powers /dev/debate and every other
// production LLM call, so "real" means literally "goes through the same
// surface humans already trust".

use crate::http::AppState;
use crate::jobs::FractalTreeSummary;
use axum::{extract::State, http::StatusCode, routing::post, Json, Router};
use beagle_smart_router::{query_beagle_with_hrv, HrvTierHint};
use chrono::Utc;
use serde::{Deserialize, Serialize};
use tokio::task::JoinSet;
use tracing::{info, warn};
use uuid::Uuid;

const HARD_MAX_DEPTH: u8 = 4;
const HARD_MAX_BRANCHING: u8 = 3;

#[derive(Deserialize)]
pub struct FractalRecurseRequest {
    pub root_prompt: String,
    #[serde(default = "default_depth")]
    pub max_depth: u8,
    #[serde(default = "default_branching")]
    pub branching: u8,
}

fn default_depth() -> u8 {
    2
}
fn default_branching() -> u8 {
    2
}

#[derive(Serialize, Clone, Debug)]
pub struct FractalNode {
    pub id: String,
    pub parent_id: Option<String>,
    pub depth: u8,
    pub prompt: String,
    pub summary: String,
    pub children: Vec<String>,
}

#[derive(Serialize)]
pub struct FractalRecurseResponse {
    pub root_id: String,
    pub max_depth: u8,
    pub branching: u8,
    pub node_count: usize,
    pub duration_ms: u64,
    pub nodes: Vec<FractalNode>,
    pub truth_mode: &'static str,
}

/// Ask the LLM to expand one prompt into a summary + N child prompts.
/// We constrain the output to JSON so parsing is mechanical; if the LLM
/// returns something unparseable we fall back to a linguistic split on
/// newlines (preserving the summary even under degraded output).
pub(crate) async fn expand_one(prompt: &str, branching: u8, hint: HrvTierHint) -> (String, Vec<String>) {
    let instruction = format!(
        "You are a recursive thinker. Take the input below and do TWO things:\n\
         1) Write exactly ONE sentence summarizing what the input is *really* asking or asserting.\n\
         2) Produce exactly {n} sharper, more specific sub-prompts that, answered together, would fully explore the input.\n\
         Output STRICT JSON with this shape and no other text:\n\
         {{\"summary\":\"one sentence\",\"children\":[\"sub-prompt 1\", ..., \"sub-prompt {n}\"]}}\n\
         Input: {p}",
        n = branching,
        p = prompt
    );

    let raw = query_beagle_with_hrv(&instruction, 0, hint).await;

    // Extract JSON substring — models sometimes wrap with markdown fences.
    let json_slice = extract_json_object(&raw).unwrap_or(&raw);
    #[derive(Deserialize)]
    struct Parsed {
        summary: String,
        children: Vec<String>,
    }
    match serde_json::from_str::<Parsed>(json_slice) {
        Ok(p) => {
            let mut children = p.children;
            children.truncate(branching as usize);
            // Pad if the model under-produced.
            while children.len() < branching as usize {
                children.push(format!("refine: {}", prompt));
            }
            (p.summary.trim().to_string(), children)
        }
        Err(e) => {
            warn!(
                "fractal: LLM JSON parse failed ({}); falling back to newline split",
                e
            );
            let mut lines: Vec<String> = raw.lines().map(|l| l.trim().to_string()).filter(|l| !l.is_empty()).collect();
            let summary = lines.first().cloned().unwrap_or_else(|| prompt.to_string());
            let children = if lines.len() > 1 {
                lines.drain(1..).take(branching as usize).collect()
            } else {
                (0..branching).map(|i| format!("aspect {}: {}", i + 1, prompt)).collect()
            };
            (summary, children)
        }
    }
}

fn extract_json_object(s: &str) -> Option<&str> {
    let start = s.find('{')?;
    let end = s.rfind('}')?;
    if end > start {
        Some(&s[start..=end])
    } else {
        None
    }
}

async fn fractal_recurse_handler(
    State(state): State<AppState>,
    Json(req): Json<FractalRecurseRequest>,
) -> Result<Json<FractalRecurseResponse>, (StatusCode, String)> {
    let max_depth = req.max_depth.min(HARD_MAX_DEPTH).max(1);
    let branching = req.branching.min(HARD_MAX_BRANCHING).max(1);
    let root_prompt = req.root_prompt.trim().to_string();
    if root_prompt.is_empty() {
        return Err((StatusCode::BAD_REQUEST, "root_prompt required".into()));
    }
    info!(
        "fractal: recurse depth={} branching={} prompt={:?}",
        max_depth,
        branching,
        &root_prompt.chars().take(80).collect::<String>()
    );

    let t0 = std::time::Instant::now();

    // Resolve HRV tier preference once from observer; every level below
    // inherits this hint so router calls route to the right tier.
    let physio = state.observer.latest_physio_snapshot().await;
    let hrv_level = physio.as_ref().and_then(|s| s.hrv_level.as_deref());
    let hint = HrvTierHint::from_flow_state(hrv_level);
    info!("fractal: hrv_hint={:?} (observed={})", hint, physio.is_some());

    // Depth-0 root.
    let (root_summary, root_children_prompts) = expand_one(&root_prompt, branching, hint).await;
    let root_id = Uuid::new_v4().to_string();
    let mut all: Vec<FractalNode> = Vec::new();

    // Seed level-1 frontier with (parent_id, depth, prompt) triples.
    let mut frontier: Vec<(String, u8, String)> = root_children_prompts
        .into_iter()
        .map(|p| (root_id.clone(), 1u8, p))
        .collect();

    let mut root_children_ids: Vec<String> = Vec::with_capacity(frontier.len());

    // Process each level in parallel.
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
                    // Terminal node — summary only, no further expansion.
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
                    // Record parent->self for root_children bookkeeping.
                    if parent_id == root_id && depth == 1 {
                        root_children_ids.push(my_id.clone());
                    } else {
                        // Patch parent's children list in `all`.
                        if let Some(parent_node) = all.iter_mut().find(|n| n.id == parent_id) {
                            parent_node.children.push(my_id.clone());
                        }
                    }
                    all.push(FractalNode {
                        id: my_id,
                        parent_id: Some(parent_id),
                        depth,
                        prompt,
                        summary,
                        children: child_ids,
                    });
                    let _ = d; // keep unused-warn quiet without a warning
                }
                Err(e) => {
                    warn!("fractal: task join error: {}", e);
                }
            }
        }
        frontier = next;
    }

    // Prepend the root.
    let mut nodes = Vec::with_capacity(all.len() + 1);
    nodes.push(FractalNode {
        id: root_id.clone(),
        parent_id: None,
        depth: 0,
        prompt: root_prompt.clone(),
        summary: root_summary,
        children: root_children_ids,
    });
    nodes.extend(all);

    let duration_ms = t0.elapsed().as_millis() as u64;
    let node_count = nodes.len();

    // Observability: push a summary into the registry for cognitive state.
    let summary = FractalTreeSummary {
        root_id: root_id.clone(),
        root_prompt: root_prompt.chars().take(160).collect(),
        max_depth,
        branching,
        node_count,
        generated_at: Utc::now(),
        duration_ms,
        truth_mode: "observed".to_string(),
    };
    state.fractals.append(summary.clone()).await;
    crate::cognitive_events::emit(
        &state.cognitive_tx,
        crate::cognitive_events::CognitiveEvent::Fractal(summary),
    );

    Ok(Json(FractalRecurseResponse {
        root_id,
        max_depth,
        branching,
        node_count,
        duration_ms,
        nodes,
        truth_mode: "observed",
    }))
}

/// For leaves we don't ask for children; just a summary so the tree's
/// terminal frontier carries real content, not empty strings.
pub(crate) async fn summarize_terminal(prompt: &str, hint: HrvTierHint) -> String {
    let instruction = format!(
        "In exactly ONE declarative sentence, state the answer or the clearest next-step \
         for this prompt. No preamble, no markdown, no lists.\nPrompt: {}",
        prompt
    );
    let raw = query_beagle_with_hrv(&instruction, 0, hint).await;
    raw.trim()
        .lines()
        .next()
        .unwrap_or(raw.trim())
        .to_string()
}

pub fn fractal_routes() -> Router<AppState> {
    Router::new().route("/api/fractal/recurse", post(fractal_recurse_handler))
}
