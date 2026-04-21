// http_cognitive.rs
//
// /api/v1/cognitive/state — single endpoint that aggregates everything an
// iOS home screen widget or Vision Pro spatial dashboard needs to render
// "current cognitive state":
//
//   - HRV / physio (from UniversalObserver)
//   - Recent runs / drafts (from JobRegistry)
//   - Recent science jobs (from ScienceJobRegistry)
//   - Recent feedback events (from beagle-feedback file store)
//
// Designed for low-frequency polling (every 30-60s), single round-trip.

use crate::cognitive_events::CognitiveEvent;
use crate::http::AppState;
use crate::jobs::{
    DeepThinkSummary, FractalTreeSummary, PhiMeasurementSummary, VoidJourneySummary,
    truth_mode_for_age,
};
use crate::phi_iit::{integrated_information, tpm_from_activations, MAX_SUBSTRATE};
use axum::{
    extract::State,
    response::sse::{Event, KeepAlive, Sse},
    routing::get,
    Json, Router,
};
use beagle_feedback::{FeedbackEvent, load_all_events};
use chrono::{DateTime, Utc};
use futures::stream::{Stream, StreamExt};
use serde::Serialize;
use std::convert::Infallible;
use std::path::PathBuf;
use tokio_stream::wrappers::BroadcastStream;

#[derive(Serialize)]
pub struct CognitiveStateResponse {
    pub generated_at: DateTime<Utc>,
    pub hrv: HrvBlock,
    pub recent_runs: Vec<RunSummary>,
    pub recent_science_jobs: Vec<ScienceJobSummary>,
    pub recent_feedback: Vec<FeedbackSummary>,
    // Three novelty surfaces: each carries per-entry truth_mode so a single
    // response can honestly say "this void journey observed, that phi stale".
    pub recent_void_journeys: Vec<VoidJourneySummary>,
    pub recent_fractal_trees: Vec<FractalTreeSummary>,
    pub recent_phi_measurements: Vec<PhiMeasurementSummary>,
    pub recent_deep_thinks: Vec<DeepThinkSummary>,
    pub truth_mode: &'static str,
}

#[derive(Serialize, Default)]
pub struct HrvBlock {
    pub latest_ms: Option<f64>,
    pub level: Option<String>,
    pub flow_state: Option<String>,
    pub source: Option<String>,
    pub observed_at: Option<DateTime<Utc>>,
    pub truth_mode: &'static str,
}

#[derive(Serialize)]
pub struct RunSummary {
    pub run_id: String,
    pub question: String,
    pub status: String,
    pub started_at: Option<DateTime<Utc>>,
    pub updated_at: Option<DateTime<Utc>>,
    pub error: Option<String>,
}

#[derive(Serialize)]
pub struct ScienceJobSummary {
    pub job_id: String,
    pub kind: String,
    pub status: String,
    pub started_at: Option<DateTime<Utc>>,
}

#[derive(Serialize)]
pub struct FeedbackSummary {
    pub event_type: String,
    pub run_id: String,
    pub timestamp: DateTime<Utc>,
    pub hrv_level: Option<String>,
    pub rating_0_10: Option<u8>,
    pub accepted: Option<bool>,
}

fn data_root() -> PathBuf {
    std::env::var("BEAGLE_DATA_DIR")
        .map(PathBuf::from)
        .unwrap_or_else(|_| PathBuf::from("/var/lib/beagle"))
}

fn classify_flow(hrv_ms: Option<f64>) -> Option<String> {
    let hrv = hrv_ms?;
    Some(
        if hrv > 80.0 { "flow".to_string() }
        else if hrv < 50.0 { "stress".to_string() }
        else { "normal".to_string() }
    )
}

async fn cognitive_state_handler(State(state): State<AppState>) -> Json<CognitiveStateResponse> {
    // ─── HRV via observer ──────────────────────────────────────────
    let physio = state.observer.latest_physio_snapshot().await;
    let hrv_block = if let Some(snap) = physio {
        HrvBlock {
            latest_ms: snap.hrv_ms,
            level: snap.hrv_level.clone(),
            flow_state: classify_flow(snap.hrv_ms),
            source: Some(snap.source.clone()),
            observed_at: Some(snap.timestamp),
            truth_mode: "observed",
        }
    } else {
        HrvBlock {
            truth_mode: "declared",
            ..HrvBlock::default()
        }
    };

    // ─── Recent runs via JobRegistry ───────────────────────────────
    let recent = state.jobs.list_recent(5).await;
    let recent_runs: Vec<RunSummary> = recent
        .into_iter()
        .map(|r| RunSummary {
            run_id: r.run_id,
            question: r.question,
            status: format!("{:?}", r.status),
            started_at: Some(r.created_at),
            updated_at: Some(r.updated_at),
            error: r.error,
        })
        .collect();

    // ─── Recent science jobs ───────────────────────────────────────
    let science = state.science_jobs.get_recent_jobs(5).await;
    let recent_science_jobs: Vec<ScienceJobSummary> = science
        .into_iter()
        .map(|j| ScienceJobSummary {
            job_id: j.job_id,
            kind: j.kind.kind_label(),
            status: j.status.to_string(),
            started_at: Some(j.created_at),
        })
        .collect();

    // ─── Recent feedback events ────────────────────────────────────
    let recent_feedback = read_recent_feedback(5).unwrap_or_default();

    // ─── Cognitive novelty surfaces ────────────────────────────────
    // Each registry entry was stamped with truth_mode="observed" at append
    // time; re-stamp to "stale" if aged past 10min so the response reflects
    // what's actually fresh.
    let recent_void_journeys: Vec<VoidJourneySummary> = state
        .voids
        .recent(5)
        .await
        .into_iter()
        .map(|mut v| {
            v.truth_mode = truth_mode_for_age(v.completed_at).to_string();
            v
        })
        .collect();
    let recent_fractal_trees: Vec<FractalTreeSummary> = state
        .fractals
        .recent(5)
        .await
        .into_iter()
        .map(|mut f| {
            f.truth_mode = truth_mode_for_age(f.generated_at).to_string();
            f
        })
        .collect();
    let recent_phi_measurements: Vec<PhiMeasurementSummary> = state
        .phis
        .recent(5)
        .await
        .into_iter()
        .map(|mut p| {
            p.truth_mode = truth_mode_for_age(p.measured_at).to_string();
            p
        })
        .collect();
    let recent_deep_thinks: Vec<DeepThinkSummary> = state
        .deep_thinks
        .recent(5)
        .await
        .into_iter()
        .map(|mut d| {
            d.truth_mode = truth_mode_for_age(d.generated_at).to_string();
            d
        })
        .collect();

    Json(CognitiveStateResponse {
        generated_at: Utc::now(),
        hrv: hrv_block,
        recent_runs,
        recent_science_jobs,
        recent_feedback,
        recent_void_journeys,
        recent_fractal_trees,
        recent_phi_measurements,
        recent_deep_thinks,
        truth_mode: "observed",
    })
}

fn read_recent_feedback(limit: usize) -> anyhow::Result<Vec<FeedbackSummary>> {
    let mut events: Vec<FeedbackEvent> = load_all_events(&data_root()).unwrap_or_default();
    events.sort_by(|a, b| b.timestamp.cmp(&a.timestamp));
    events.truncate(limit);
    Ok(events
        .into_iter()
        .map(|e| FeedbackSummary {
            event_type: format!("{:?}", e.event_type).to_lowercase(),
            run_id: e.run_id,
            timestamp: e.timestamp,
            hrv_level: e.hrv_level,
            rating_0_10: e.rating_0_10,
            accepted: e.accepted,
        })
        .collect())
}

// ─── SSE stream ────────────────────────────────────────────────────
//
// GET /api/v1/cognitive/stream — server-sent events. Each cognitive event
// (void / fractal / phi / physio) is tagged by its kind. iOS can register a
// single EventSource and dispatch per `event:` name. Backlog is bounded by
// the broadcast channel capacity (256); slow subscribers may see
// `Lagged(n)` — they should reconcile against /api/v1/cognitive/state.

async fn cognitive_stream_handler(
    State(state): State<AppState>,
) -> Sse<impl Stream<Item = Result<Event, Infallible>>> {
    let rx = state.cognitive_tx.subscribe();
    let stream = BroadcastStream::new(rx).filter_map(|res| async move {
        match res {
            Ok(ev) => {
                let kind = ev.kind();
                match serde_json::to_string(&ev) {
                    Ok(payload) => Some(Ok(Event::default().event(kind).data(payload))),
                    Err(_) => None,
                }
            }
            // Lagged(n) — tell the client it dropped n events; iOS reconciles.
            Err(tokio_stream::wrappers::errors::BroadcastStreamRecvError::Lagged(n)) => {
                Some(Ok(Event::default()
                    .event("lagged")
                    .data(format!("{{\"dropped\":{}}}", n))))
            }
        }
    });
    Sse::new(stream).keep_alive(KeepAlive::new().interval(std::time::Duration::from_secs(15)))
}

// ─── Meta-Φ over recent cognitive events ───────────────────────────
//
// GET /api/v1/cognitive/meta_phi — treats the last N entries across void /
// fractal / phi registries as a substrate of discrete cognitive "atoms".
// Builds a TPM from their chronological transitions (atom_i → atom_{i+1})
// and runs the same integrated_information() MIP search used by the
// per-query Φ endpoint. Result is "how integrated were my last N thoughts?"

#[derive(Serialize)]
pub struct MetaPhiResponse {
    pub meta_phi: f64,
    pub ei_full: f64,
    pub ei_cut: f64,
    pub substrate: Vec<String>,
    pub substrate_size: usize,
    pub mip_partition: (Vec<String>, Vec<String>),
    pub event_timeline: Vec<MetaEvent>,
    pub awareness_label: &'static str,
    pub computed_at: DateTime<Utc>,
    pub truth_mode: &'static str,
    /// Epistemic guardrail — when the measurement can't support an
    /// `observed` claim (substrate too small, EI below floor, trajectory
    /// too short), this carries the reason and truth_mode flips to
    /// `declared`. Absent when observed.
    #[serde(skip_serializing_if = "Option::is_none")]
    pub declared_reason: Option<String>,
}

#[derive(Serialize)]
pub struct MetaEvent {
    pub kind: &'static str,
    pub label: String,
    pub timestamp: DateTime<Utc>,
}

fn meta_awareness(phi: f64) -> &'static str {
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

async fn cognitive_meta_phi_handler(
    State(state): State<AppState>,
) -> Json<MetaPhiResponse> {
    // Pull up to 4 recent entries from each registry — 4+4+4 = 12 events
    // chronologically sorted, capped to MAX_SUBSTRATE=8 atoms.
    let voids = state.voids.recent(4).await;
    let fractals = state.fractals.recent(4).await;
    let phis = state.phis.recent(4).await;

    // Unified timeline with labels. We use each event's label as substrate.
    let mut events: Vec<(DateTime<Utc>, &'static str, String)> = Vec::new();
    for v in &voids {
        events.push((v.completed_at, "void", format!("v:{}", &v.focus.chars().take(40).collect::<String>())));
    }
    for f in &fractals {
        events.push((f.generated_at, "fractal", format!("f:{}", &f.root_prompt.chars().take(40).collect::<String>())));
    }
    for p in &phis {
        events.push((p.measured_at, "phi", format!("p:{}", &p.query_snippet.chars().take(40).collect::<String>())));
    }
    events.sort_by(|a, b| a.0.cmp(&b.0));

    // If fewer than 2 events across all registries, meta-Φ is undefined;
    // honest response instead of fake math.
    if events.len() < 2 {
        return Json(MetaPhiResponse {
            meta_phi: 0.0,
            ei_full: 0.0,
            ei_cut: 0.0,
            substrate: events.iter().map(|(_, _, l)| l.clone()).collect(),
            substrate_size: events.len(),
            mip_partition: (Vec::new(), Vec::new()),
            event_timeline: events
                .into_iter()
                .map(|(t, k, l)| MetaEvent { kind: k, label: l, timestamp: t })
                .collect(),
            awareness_label: "disintegrated",
            computed_at: Utc::now(),
            truth_mode: "declared",
            declared_reason: Some("only one cognitive event present — Φ requires ≥2 atoms".to_string()),
        });
    }

    // Deduplicate labels to build the substrate of distinct atoms.
    let mut substrate_labels: Vec<String> = Vec::new();
    let mut label_to_idx: std::collections::HashMap<String, usize> = std::collections::HashMap::new();
    for (_, _, label) in &events {
        if !label_to_idx.contains_key(label) {
            label_to_idx.insert(label.clone(), substrate_labels.len());
            substrate_labels.push(label.clone());
            if substrate_labels.len() >= MAX_SUBSTRATE {
                break;
            }
        }
    }
    let n = substrate_labels.len();
    if n < 2 {
        // Only one distinct atom → Φ undefined.
        return Json(MetaPhiResponse {
            meta_phi: 0.0,
            ei_full: 0.0,
            ei_cut: 0.0,
            substrate: substrate_labels,
            substrate_size: n,
            mip_partition: (Vec::new(), Vec::new()),
            event_timeline: events
                .into_iter()
                .map(|(t, k, l)| MetaEvent { kind: k, label: l, timestamp: t })
                .collect(),
            awareness_label: "disintegrated",
            computed_at: Utc::now(),
            truth_mode: "declared",
            declared_reason: Some(format!(
                "only {} distinct atom{} in substrate — Φ undefined below {} distinct",
                n, if n == 1 { "" } else { "s" }, crate::phi_iit::SUBSTRATE_CONFIDENCE_FLOOR
            )),
        });
    }

    // Chronological trajectory → single "document" of consecutive atom
    // indices. tpm_from_activations treats adjacent pairs as transitions.
    let trajectory: Vec<usize> = events
        .iter()
        .filter_map(|(_, _, l)| label_to_idx.get(l).copied())
        .collect();
    let tpm = tpm_from_activations(n, &[trajectory], 0.5);
    let phi_result = integrated_information(&tpm);

    let mip_partition = (
        phi_result.mip_lhs.iter().map(|&i| substrate_labels[i].clone()).collect::<Vec<_>>(),
        phi_result.mip_rhs.iter().map(|&i| substrate_labels[i].clone()).collect::<Vec<_>>(),
    );

    let declared_reason = crate::phi_iit::confidence_guard(
        phi_result.phi,
        phi_result.ei_full,
        events.len(),
        n,
    );
    let truth_mode = if declared_reason.is_some() { "declared" } else { "observed" };
    Json(MetaPhiResponse {
        meta_phi: phi_result.phi,
        ei_full: phi_result.ei_full,
        ei_cut: phi_result.ei_cut,
        substrate: substrate_labels,
        substrate_size: n,
        mip_partition,
        event_timeline: events
            .into_iter()
            .map(|(t, k, l)| MetaEvent { kind: k, label: l, timestamp: t })
            .collect(),
        awareness_label: meta_awareness(phi_result.phi),
        computed_at: Utc::now(),
        truth_mode,
        declared_reason,
    })
}

// ─── Φ of Φ (recursive / second-order IIT) ─────────────────────────
//
// GET /api/v1/cognitive/phi_of_phi?window=20&bins=4
//
// Reads the last N PhiMeasurementSummary entries chronologically,
// discretizes each measurement's phi into one of `bins` awareness bands,
// builds a TPM from band-to-band transitions across the trajectory, and
// runs the same integrated_information() MIP search. The result is a
// second-order Φ — "how integrated is the trajectory of my own awareness?"
//
// The substrate for this endpoint is the set of OCCUPIED bands (not every
// measurement), capped at MAX_SUBSTRATE=8. This keeps the math honest even
// when the user requests `bins=8` but only 3 are visited.

#[derive(serde::Deserialize)]
pub struct PhiOfPhiQuery {
    #[serde(default = "default_window")]
    pub window: usize,
    #[serde(default = "default_bins")]
    pub bins: usize,
}

fn default_window() -> usize {
    20
}
fn default_bins() -> usize {
    4
}

#[derive(Serialize)]
pub struct PhiOfPhiResponse {
    pub phi_of_phi: f64,
    pub ei_full: f64,
    pub ei_cut: f64,
    pub bins: usize,
    pub band_edges: Vec<f64>,
    pub band_labels: Vec<&'static str>,
    /// One band index per phi measurement, in chronological order.
    pub trajectory: Vec<usize>,
    /// MIP partition — two sets of band indices.
    pub mip_partition: (Vec<usize>, Vec<usize>),
    pub base_phi_count: usize,
    pub base_phi_range: (f64, f64),
    pub cognitive_rhythm: &'static str,
    pub computed_at: DateTime<Utc>,
    pub truth_mode: &'static str,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub declared_reason: Option<String>,
}

// Awareness-derived band edges matching the labels used in
// `http_exocortex::awareness_from_phi`. Guarantees continuity between the
// first-order awareness label and the Φ-of-Φ band labels.
const AWARENESS_EDGES: &[f64] = &[0.0, 0.01, 0.1, 0.5];
const AWARENESS_LABELS: &[&str] = &["disintegrated", "minimal", "reflective", "integrated"];

fn assign_band(phi: f64, edges: &[f64]) -> usize {
    // edges must be sorted ascending. Return the largest index i such that
    // edges[i] <= phi. Clamped to [0, edges.len()-1].
    let mut idx = 0usize;
    for (i, &e) in edges.iter().enumerate() {
        if phi >= e {
            idx = i;
        } else {
            break;
        }
    }
    idx
}

fn rhythm_label(trajectory: &[usize], bins: usize) -> &'static str {
    if trajectory.len() < 3 {
        return "insufficient";
    }
    let mean = trajectory.iter().sum::<usize>() as f64 / trajectory.len() as f64;
    let variance = trajectory
        .iter()
        .map(|&x| (x as f64 - mean).powi(2))
        .sum::<f64>()
        / trajectory.len() as f64;
    let stddev = variance.sqrt();

    // Simple linear regression on (i, band_i).
    let n = trajectory.len() as f64;
    let sx: f64 = (0..trajectory.len()).map(|i| i as f64).sum();
    let sy: f64 = trajectory.iter().map(|&y| y as f64).sum();
    let sxy: f64 = trajectory
        .iter()
        .enumerate()
        .map(|(i, &y)| i as f64 * y as f64)
        .sum();
    let sxx: f64 = (0..trajectory.len()).map(|i| (i as f64).powi(2)).sum();
    let denom = n * sxx - sx * sx;
    let slope = if denom.abs() < 1e-9 { 0.0 } else { (n * sxy - sx * sy) / denom };

    let threshold = 1.0 / bins as f64; // slope of one band per run of length bins = clearly directional
    if slope > threshold {
        "rising"
    } else if slope < -threshold {
        "falling"
    } else if stddev > 1.0 {
        "volatile"
    } else {
        "stable"
    }
}

async fn cognitive_phi_of_phi_handler(
    State(state): State<AppState>,
    axum::extract::Query(params): axum::extract::Query<PhiOfPhiQuery>,
) -> Json<PhiOfPhiResponse> {
    let window = params.window.clamp(1, 200);
    let bins_req = params.bins.clamp(2, MAX_SUBSTRATE);

    // Pull latest N measurements — registry returns newest-first; reverse
    // to get chronological order (oldest → newest) for TPM transitions.
    let mut recent: Vec<_> = state.phis.recent(window).await;
    recent.reverse();
    let base_phi_count = recent.len();

    // Pick band edges. Default: awareness-derived static edges. If bins_req
    // ≠ 4, fall back to equal-width bins over [min_phi, max_phi].
    let (edges, labels): (Vec<f64>, Vec<&'static str>) = if bins_req == 4 {
        (
            AWARENESS_EDGES.iter().copied().collect(),
            AWARENESS_LABELS.iter().copied().collect(),
        )
    } else if recent.is_empty() {
        (
            (0..bins_req).map(|i| i as f64 / bins_req as f64).collect(),
            vec!["band"; bins_req],
        )
    } else {
        let min_phi = recent.iter().map(|m| m.phi).fold(f64::INFINITY, f64::min);
        let max_phi = recent
            .iter()
            .map(|m| m.phi)
            .fold(f64::NEG_INFINITY, f64::max);
        let span = (max_phi - min_phi).max(1e-9);
        let step = span / bins_req as f64;
        let edges: Vec<f64> = (0..bins_req).map(|i| min_phi + i as f64 * step).collect();
        (edges, vec!["band"; bins_req])
    };

    let trajectory: Vec<usize> = recent
        .iter()
        .map(|m| assign_band(m.phi, &edges))
        .collect();

    let (min_phi, max_phi) = if recent.is_empty() {
        (0.0, 0.0)
    } else {
        (
            recent.iter().map(|m| m.phi).fold(f64::INFINITY, f64::min),
            recent
                .iter()
                .map(|m| m.phi)
                .fold(f64::NEG_INFINITY, f64::max),
        )
    };

    // Honest declared response when there's not enough data.
    let distinct_bands: std::collections::BTreeSet<usize> =
        trajectory.iter().copied().collect();
    if base_phi_count < 4 || distinct_bands.len() < 2 {
        let reason = if base_phi_count < 4 {
            format!("only {} Φ measurements in window — need ≥4 for second-order IIT", base_phi_count)
        } else {
            format!(
                "{} measurements all fell into {} distinct band{} — awareness trajectory has no structure to integrate",
                base_phi_count,
                distinct_bands.len(),
                if distinct_bands.len() == 1 { "" } else { "s" }
            )
        };
        return Json(PhiOfPhiResponse {
            phi_of_phi: 0.0,
            ei_full: 0.0,
            ei_cut: 0.0,
            bins: bins_req,
            band_edges: edges,
            band_labels: labels,
            trajectory,
            mip_partition: (Vec::new(), Vec::new()),
            base_phi_count,
            base_phi_range: (min_phi, max_phi),
            cognitive_rhythm: "insufficient",
            computed_at: Utc::now(),
            truth_mode: "declared",
            declared_reason: Some(reason),
        });
    }

    // Build TPM over the number of distinct bands actually seen. Indices
    // in the TPM are 0..occupied_count; we remap the trajectory.
    let occupied: Vec<usize> = distinct_bands.iter().copied().collect();
    let remap: std::collections::HashMap<usize, usize> = occupied
        .iter()
        .enumerate()
        .map(|(i, &b)| (b, i))
        .collect();
    let remapped: Vec<usize> = trajectory.iter().map(|b| remap[b]).collect();
    let tpm = crate::phi_iit::tpm_from_activations(occupied.len(), &[remapped.clone()], 0.1);
    let r = crate::phi_iit::integrated_information(&tpm);

    let rhythm = rhythm_label(&trajectory, bins_req);

    // Translate MIP indices back to original band indices for reporting.
    let mip_partition = (
        r.mip_lhs.iter().map(|&i| occupied[i]).collect::<Vec<_>>(),
        r.mip_rhs.iter().map(|&i| occupied[i]).collect::<Vec<_>>(),
    );

    let declared_reason = crate::phi_iit::confidence_guard(
        r.phi,
        r.ei_full,
        trajectory.len(),
        occupied.len(),
    );
    let truth_mode = if declared_reason.is_some() { "declared" } else { "observed" };
    Json(PhiOfPhiResponse {
        phi_of_phi: r.phi,
        ei_full: r.ei_full,
        ei_cut: r.ei_cut,
        bins: bins_req,
        band_edges: edges,
        band_labels: labels,
        trajectory,
        mip_partition,
        base_phi_count,
        base_phi_range: (min_phi, max_phi),
        cognitive_rhythm: rhythm,
        computed_at: Utc::now(),
        truth_mode,
        declared_reason,
    })
}

// ─── MCP tool-call ingest + tool-rhythm Φ ──────────────────────────
//
// POST /api/cognitive/mcp_tool_call — called by the MCP server after
// every tools/call. Each invocation becomes a CognitiveEvent::McpTool,
// broadcast on the SSE stream and stored in McpToolCallRegistry for Φ.

#[derive(serde::Deserialize)]
pub struct McpToolCallIngest {
    pub tool_name: String,
    #[serde(default)]
    pub caller: Option<String>,
    #[serde(default)]
    pub duration_ms: Option<u64>,
    #[serde(default)]
    pub is_error: Option<bool>,
}

#[derive(Serialize)]
pub struct McpToolCallIngestAck {
    pub ok: bool,
    pub recorded_at: DateTime<Utc>,
}

async fn cognitive_mcp_tool_call_handler(
    State(state): State<AppState>,
    Json(req): Json<McpToolCallIngest>,
) -> Json<McpToolCallIngestAck> {
    use crate::jobs::McpToolCallSummary;
    let now = Utc::now();
    let summary = McpToolCallSummary {
        tool_name: req.tool_name.clone(),
        caller: req.caller.unwrap_or_else(|| "unknown".to_string()),
        duration_ms: req.duration_ms,
        is_error: req.is_error.unwrap_or(false),
        invoked_at: now,
        truth_mode: "observed".to_string(),
    };
    state.mcp_tools.append(summary.clone()).await;
    crate::cognitive_events::emit(
        &state.cognitive_tx,
        crate::cognitive_events::CognitiveEvent::McpTool(summary),
    );
    Json(McpToolCallIngestAck { ok: true, recorded_at: now })
}

// GET /api/v1/cognitive/tool_rhythm_phi?window=100 — Φ over the
// chronological MCP tool-name sequence. Each distinct tool_name becomes
// a substrate atom, capped at MAX_SUBSTRATE. The trajectory is the
// temporal order of invocations. A cognitive agent that calls the same
// tool repeatedly has a low-entropy, highly-integrated rhythm (Φ is
// small-positive because the MIP finds no good cut); an agent that
// oscillates between unrelated tools has a high-entropy rhythm where
// the MIP finds a natural split.

#[derive(serde::Deserialize)]
pub struct ToolRhythmQuery {
    #[serde(default = "default_tool_window")]
    pub window: usize,
    /// Optional: restrict the rhythm to one caller (e.g. "claude-desktop")
    /// so Claude Desktop and Claude Code can be measured separately. When
    /// omitted, the rhythm is computed over the global stream.
    #[serde(default)]
    pub caller: Option<String>,
    /// When true, the response also carries a `by_caller` map with each
    /// distinct caller's current Φ / rhythm_label / trajectory length.
    /// Caps at 6 callers to bound cost.
    #[serde(default)]
    pub split: Option<bool>,
}

fn default_tool_window() -> usize {
    100
}

#[derive(Serialize)]
pub struct CallerRhythmSummary {
    pub caller: String,
    pub call_count: usize,
    pub unique_tools: usize,
    pub tool_rhythm_phi: f64,
    pub rhythm_label: &'static str,
}

#[derive(Serialize)]
pub struct PredictedNextTool {
    pub tool_name: String,
    pub probability: f64,
    pub from_tool: String,
}

#[derive(Serialize)]
pub struct PredictedTrajectoryStep {
    pub tool_name: String,
    pub conditional_probability: f64,
    pub joint_probability: f64,
}

#[derive(Serialize)]
pub struct RegretEntry {
    /// Position in the chronological trajectory (0 = oldest).
    pub position: usize,
    pub tool_name: String,
    /// Φ if this single call were removed from the trajectory minus current Φ.
    /// Negative → removing it would LOWER Φ → load-bearing.
    /// Positive → removing it would RAISE Φ → noisy.
    pub phi_delta: f64,
}

#[derive(Serialize)]
pub struct AdversarialAdd {
    /// The substrate index (and tool_name) that, if appended to the
    /// trajectory once, would maximize the resulting Φ.
    pub tool_name: String,
    /// Φ if the call were appended − current Φ. Always ≥ 0 in the
    /// reported entry (we pick the argmax). Negative deltas are
    /// dropped — those are calls that would only fragment further.
    pub phi_gain: f64,
    /// Φ achieved by the perturbation (i.e. current_phi + phi_gain).
    pub projected_phi: f64,
}

#[derive(Serialize)]
pub struct RegretAnalysis {
    /// Single most load-bearing call (largest negative phi_delta).
    /// None when trajectory is too short to compute.
    pub load_bearing: Option<RegretEntry>,
    /// Single noisiest call (largest positive phi_delta).
    pub noisiest: Option<RegretEntry>,
    pub all_deltas: Vec<RegretEntry>,
}

#[derive(Serialize)]
pub struct ToolRhythmPhiResponse {
    pub tool_rhythm_phi: f64,
    pub ei_full: f64,
    pub ei_cut: f64,
    pub substrate: Vec<String>,
    pub substrate_size: usize,
    pub trajectory: Vec<usize>,
    pub mip_partition: (Vec<String>, Vec<String>),
    pub call_count: usize,
    pub unique_tools: usize,
    pub rhythm_label: &'static str,
    pub caller_filter: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub by_caller: Option<Vec<CallerRhythmSummary>>,
    /// Given the last tool call in the trajectory, the most probable next
    /// call derived from the TPM row. This is a Markov prediction, not
    /// ground truth — ambient suffix renders it as "next likely: X (Pr)".
    #[serde(skip_serializing_if = "Option::is_none")]
    pub predicted_next_tool: Option<PredictedNextTool>,
    /// Beam-search over the TPM, 3 steps deep. Joint probability is the
    /// product of the conditional probabilities along the most-likely path.
    #[serde(skip_serializing_if = "Option::is_none")]
    pub predicted_trajectory: Option<Vec<PredictedTrajectoryStep>>,
    /// Per-call regret signal — Φ delta if that call were removed.
    /// Surfaces load-bearing vs noisy calls in the recent trajectory.
    #[serde(skip_serializing_if = "Option::is_none")]
    pub regret_analysis: Option<RegretAnalysis>,
    /// "If you wanted to maximize integration, your next call would be
    /// X." Computed by trying each substrate atom appended once and
    /// picking the argmax. Mirror image of the noisy regret signal.
    #[serde(skip_serializing_if = "Option::is_none")]
    pub adversarial_next: Option<AdversarialAdd>,
    /// Tool names penalized in the TPM because human feedback flagged
    /// them (rating < 5 OR accepted=false) and their name appeared in
    /// the notes. The prediction + adversarial signals reflect this.
    /// Empty when no human feedback flags any substrate tool.
    pub penalized_tools: Vec<String>,
    pub computed_at: DateTime<Utc>,
    pub truth_mode: &'static str,
}

/// Read recent low-rating human feedback events and extract the
/// tool_names mentioned in their notes. Those tools become "penalized
/// priors" in the tool_rhythm TPM — their transition probabilities are
/// halved after normalization, so the Markov predictor stops nudging
/// toward them. Closes the human-feedback → cognitive-substrate loop.
fn feedback_penalized_tools() -> Vec<String> {
    use std::path::PathBuf;
    let data_dir = std::env::var("BEAGLE_DATA_DIR")
        .map(PathBuf::from)
        .unwrap_or_else(|_| PathBuf::from("/var/lib/beagle"));
    let events = beagle_feedback::load_all_events(&data_dir).unwrap_or_default();
    // Only the last 30 events matter; older regret is past its prior.
    let recent: Vec<&beagle_feedback::FeedbackEvent> = events.iter().rev().take(30).collect();
    let mut penalized = std::collections::BTreeSet::new();
    for e in recent {
        // Low rating OR explicit rejection from a human evaluator.
        let low_rating = e.rating_0_10.map(|r| r < 5).unwrap_or(false);
        let rejected = e.accepted == Some(false);
        if !(low_rating || rejected) {
            continue;
        }
        // Skip MCP-self-feedback — those are the auto-generated noisy-
        // pattern alerts; they'd create a feedback loop that keeps
        // penalizing whatever is currently noisy even after the pattern
        // stops. Only human feedback counts as prior.
        if e.evaluator_id.as_deref() == Some("cockpit-mcp-server") {
            continue;
        }
        // Extract tool_name mentions from the notes. We accept any
        // `cognitive_*` or `cockpit_*` substring.
        if let Some(ref notes) = e.notes {
            for tok in notes.split(|c: char| !(c.is_alphanumeric() || c == '_')) {
                if tok.starts_with("cognitive_") || tok.starts_with("cockpit_") {
                    penalized.insert(tok.to_string());
                }
            }
        }
    }
    penalized.into_iter().collect()
}

async fn cognitive_tool_rhythm_phi_handler(
    State(state): State<AppState>,
    axum::extract::Query(params): axum::extract::Query<ToolRhythmQuery>,
) -> Json<ToolRhythmPhiResponse> {
    use crate::phi_iit::{integrated_information, tpm_from_activations, MAX_SUBSTRATE};
    let window = params.window.clamp(2, 500);
    let caller_filter = params.caller.clone();
    let split = params.split.unwrap_or(false);

    // Grab the last N tool names in chronological order, optionally
    // filtered by caller.
    let chrono = state
        .mcp_tools
        .trajectory_for(caller_filter.as_deref().unwrap_or(""), window)
        .await;
    let call_count = chrono.len();

    // Build the substrate: distinct tool names in their first-appearance
    // order, capped at MAX_SUBSTRATE. Tools past the cap are dropped from
    // the substrate but stay in the trajectory (remapped below).
    let mut substrate: Vec<String> = Vec::new();
    let mut idx_of: std::collections::HashMap<String, usize> =
        std::collections::HashMap::new();
    for name in &chrono {
        if substrate.len() >= MAX_SUBSTRATE {
            break;
        }
        if !idx_of.contains_key(name) {
            idx_of.insert(name.clone(), substrate.len());
            substrate.push(name.clone());
        }
    }
    let unique_tools = substrate.len();
    let trajectory: Vec<usize> = chrono
        .iter()
        .filter_map(|n| idx_of.get(n).copied())
        .collect();

    // Honest declared response when we don't have enough to talk about.
    if trajectory.len() < 4 || unique_tools < 2 {
        return Json(ToolRhythmPhiResponse {
            tool_rhythm_phi: 0.0,
            ei_full: 0.0,
            ei_cut: 0.0,
            substrate,
            substrate_size: unique_tools,
            trajectory,
            mip_partition: (Vec::new(), Vec::new()),
            call_count,
            unique_tools,
            rhythm_label: "insufficient",
            caller_filter,
            by_caller: None,
            predicted_next_tool: None,
            predicted_trajectory: None,
            regret_analysis: None,
            adversarial_next: None,
            penalized_tools: Vec::new(),
            computed_at: Utc::now(),
            truth_mode: "declared",
        });
    }

    let mut tpm = tpm_from_activations(unique_tools, &[trajectory.clone()], 0.1);

    // Apply human-feedback prior: tools flagged by low-rating feedback
    // events get their outgoing TPM rows multiplied by 0.5 and then
    // re-normalized. Incoming columns (being the target of transitions
    // from other tools) are halved too so the Markov predictor stops
    // recommending them as a next step. Mathematically equivalent to
    // putting a Bernoulli prior on "avoid this path".
    let penalized = feedback_penalized_tools();
    let penalized_applied: Vec<String> = penalized
        .iter()
        .filter(|p| substrate.contains(p))
        .cloned()
        .collect();
    if !penalized.is_empty() {
        for (i, name) in substrate.iter().enumerate() {
            if penalized.iter().any(|p| p == name) {
                for j in 0..unique_tools {
                    tpm[[i, j]] *= 0.5;
                    tpm[[j, i]] *= 0.5;
                }
            }
        }
        // Re-normalize rows (zero-sum protection: if every entry got
        // halved, row sum is 0.5 — normalize back to 1).
        for i in 0..unique_tools {
            let s: f64 = (0..unique_tools).map(|j| tpm[[i, j]]).sum();
            if s > 0.0 {
                for j in 0..unique_tools {
                    tpm[[i, j]] /= s;
                }
            } else {
                // Degenerate row — restore uniform so MIP doesn't crash.
                for j in 0..unique_tools {
                    tpm[[i, j]] = 1.0 / unique_tools as f64;
                }
            }
        }
    }

    let r = integrated_information(&tpm);
    let mip_partition = (
        r.mip_lhs
            .iter()
            .map(|&i| substrate[i].clone())
            .collect::<Vec<_>>(),
        r.mip_rhs
            .iter()
            .map(|&i| substrate[i].clone())
            .collect::<Vec<_>>(),
    );

    // Rhythm heuristic: entropy of the trajectory as a proxy for
    // exploratory vs focused agent behavior.
    let mut counts = vec![0f64; unique_tools];
    for &i in &trajectory {
        counts[i] += 1.0;
    }
    let total = trajectory.len() as f64;
    let entropy: f64 = counts
        .iter()
        .filter(|c| **c > 0.0)
        .map(|c| {
            let p = c / total;
            -p * p.log2()
        })
        .sum();
    let max_ent = (unique_tools as f64).log2().max(1e-9);
    let norm_ent = entropy / max_ent;
    let rhythm = if norm_ent < 0.25 {
        "focused"
    } else if norm_ent < 0.65 {
        "balanced"
    } else {
        "exploratory"
    };

    // Predictive Φ — given the last tool in the trajectory, walk the TPM
    // row and pick the j with max transition probability. That's the
    // Markov prediction of the next call. Self-loops allowed. Bail if
    // the last index is out of bounds (shouldn't happen, but be safe).
    let predicted_next_tool = trajectory.last().and_then(|&last| {
        if last >= unique_tools {
            return None;
        }
        let mut best_j = 0usize;
        let mut best_p = -1.0f64;
        for j in 0..unique_tools {
            let p = tpm[[last, j]];
            if p > best_p {
                best_p = p;
                best_j = j;
            }
        }
        if best_p <= 0.0 {
            return None;
        }
        Some(PredictedNextTool {
            tool_name: substrate[best_j].clone(),
            probability: best_p,
            from_tool: substrate[last].clone(),
        })
    });

    // Per-caller split — only compute when explicitly asked, because it
    // fans out calls across all distinct callers.
    let by_caller = if split {
        let callers = state.mcp_tools.callers().await;
        let mut out = Vec::new();
        for c in callers.into_iter().take(6) {
            let sub_chrono = state.mcp_tools.trajectory_for(&c, window).await;
            let mut sub_substrate: Vec<String> = Vec::new();
            let mut sub_idx: std::collections::HashMap<String, usize> =
                std::collections::HashMap::new();
            for name in &sub_chrono {
                if sub_substrate.len() >= MAX_SUBSTRATE {
                    break;
                }
                if !sub_idx.contains_key(name) {
                    sub_idx.insert(name.clone(), sub_substrate.len());
                    sub_substrate.push(name.clone());
                }
            }
            let sub_traj: Vec<usize> = sub_chrono
                .iter()
                .filter_map(|n| sub_idx.get(n).copied())
                .collect();
            let sub_unique = sub_substrate.len();
            let (sub_phi, sub_label) = if sub_traj.len() < 4 || sub_unique < 2 {
                (0.0, "insufficient")
            } else {
                let sub_tpm =
                    tpm_from_activations(sub_unique, &[sub_traj.clone()], 0.1);
                let sub_r = integrated_information(&sub_tpm);
                // Reuse the entropy-based rhythm label for the caller too.
                let mut sc = vec![0f64; sub_unique];
                for &i in &sub_traj {
                    sc[i] += 1.0;
                }
                let st = sub_traj.len() as f64;
                let sub_ent: f64 = sc
                    .iter()
                    .filter(|c| **c > 0.0)
                    .map(|c| {
                        let p = c / st;
                        -p * p.log2()
                    })
                    .sum();
                let sub_max = (sub_unique as f64).log2().max(1e-9);
                let sub_norm = sub_ent / sub_max;
                let label: &'static str = if sub_norm < 0.25 {
                    "focused"
                } else if sub_norm < 0.65 {
                    "balanced"
                } else {
                    "exploratory"
                };
                (sub_r.phi, label)
            };
            out.push(CallerRhythmSummary {
                caller: c,
                call_count: sub_chrono.len(),
                unique_tools: sub_unique,
                tool_rhythm_phi: sub_phi,
                rhythm_label: sub_label,
            });
        }
        Some(out)
    } else {
        None
    };

    // Multi-step beam-search over the TPM. Greedy walk from the last
    // observed tool index, picking argmax at each step, accumulating
    // joint probability. 3 steps gives a useful "you're about to do
    // X, then Y, then Z" intervention signal.
    let predicted_trajectory = trajectory.last().and_then(|&last_idx| {
        if last_idx >= unique_tools {
            return None;
        }
        let mut steps = Vec::new();
        let mut from = last_idx;
        let mut joint = 1.0f64;
        for _ in 0..3 {
            let mut best_j = 0usize;
            let mut best_p = -1.0f64;
            for j in 0..unique_tools {
                let p = tpm[[from, j]];
                if p > best_p {
                    best_p = p;
                    best_j = j;
                }
            }
            if best_p <= 0.0 {
                break;
            }
            joint *= best_p;
            steps.push(PredictedTrajectoryStep {
                tool_name: substrate[best_j].clone(),
                conditional_probability: best_p,
                joint_probability: joint,
            });
            from = best_j;
        }
        if steps.is_empty() {
            None
        } else {
            Some(steps)
        }
    });

    // Reverse-Φ regret. For each position in the trajectory, recompute
    // Φ over the trajectory with that single position dropped, then
    // compare to the current Φ. Negative delta → load-bearing call.
    // Positive delta → noisy call. Bound work: only run when trajectory
    // length ≤ 80 (the tighter the better; cost is O(n) MIP searches).
    let regret_analysis = if trajectory.len() <= 80 && trajectory.len() >= 6 {
        let mut deltas: Vec<RegretEntry> = Vec::new();
        for (pos, _) in trajectory.iter().enumerate() {
            let mut alt: Vec<usize> = trajectory.clone();
            alt.remove(pos);
            // Re-derive substrate over alt — atoms unused after removal
            // would otherwise inflate substrate_size and skew Φ.
            let mut alt_substrate: Vec<usize> = Vec::new();
            let mut seen: std::collections::BTreeSet<usize> = std::collections::BTreeSet::new();
            for &i in &alt {
                if seen.insert(i) {
                    alt_substrate.push(i);
                }
            }
            if alt_substrate.len() < 2 {
                continue;
            }
            let remap: std::collections::HashMap<usize, usize> = alt_substrate
                .iter()
                .enumerate()
                .map(|(new, &orig)| (orig, new))
                .collect();
            let alt_traj: Vec<usize> = alt.iter().map(|i| remap[i]).collect();
            let alt_tpm = tpm_from_activations(alt_substrate.len(), &[alt_traj], 0.1);
            let alt_r = integrated_information(&alt_tpm);
            let delta = alt_r.phi - r.phi;
            deltas.push(RegretEntry {
                position: pos,
                tool_name: substrate[trajectory[pos]].clone(),
                phi_delta: delta,
            });
        }
        let load_bearing = deltas
            .iter()
            .min_by(|a, b| a.phi_delta.partial_cmp(&b.phi_delta).unwrap())
            .map(|e| RegretEntry {
                position: e.position,
                tool_name: e.tool_name.clone(),
                phi_delta: e.phi_delta,
            });
        let noisiest = deltas
            .iter()
            .max_by(|a, b| a.phi_delta.partial_cmp(&b.phi_delta).unwrap())
            .map(|e| RegretEntry {
                position: e.position,
                tool_name: e.tool_name.clone(),
                phi_delta: e.phi_delta,
            });
        Some(RegretAnalysis {
            load_bearing,
            noisiest,
            all_deltas: deltas,
        })
    } else {
        None
    };

    // Adversarial Φ — the inverse of regret. For each substrate atom,
    // simulate appending it once to the trajectory, recompute Φ, and
    // keep the largest positive delta. Same O(n) cost as regret.
    let adversarial_next = if trajectory.len() < 80 {
        let mut best: Option<AdversarialAdd> = None;
        for cand in 0..unique_tools {
            let mut alt = trajectory.clone();
            alt.push(cand);
            let alt_tpm = tpm_from_activations(unique_tools, &[alt], 0.1);
            let alt_r = integrated_information(&alt_tpm);
            let gain = alt_r.phi - r.phi;
            if gain > 0.0 && best.as_ref().map_or(true, |b| gain > b.phi_gain) {
                best = Some(AdversarialAdd {
                    tool_name: substrate[cand].clone(),
                    phi_gain: gain,
                    projected_phi: alt_r.phi,
                });
            }
        }
        best
    } else {
        None
    };

    Json(ToolRhythmPhiResponse {
        tool_rhythm_phi: r.phi,
        ei_full: r.ei_full,
        ei_cut: r.ei_cut,
        substrate,
        substrate_size: unique_tools,
        trajectory,
        mip_partition,
        call_count,
        unique_tools,
        rhythm_label: rhythm,
        caller_filter,
        by_caller,
        predicted_next_tool,
        predicted_trajectory,
        regret_analysis,
        adversarial_next,
        penalized_tools: penalized_applied,
        computed_at: Utc::now(),
        truth_mode: "observed",
    })
}

// ─── Joint Φ — behavioral × semantic substrate ──────────────────────
//
// GET /api/v1/cognitive/joint_phi?window=50
//
// Builds a substrate that mixes tool-call behavior (tool_name) with
// semantic concepts (tokens extracted from recent phi_measurement query
// snippets). The TPM is built from co-occurrence across a unified
// interleaved trajectory: alternating tool_name → concept → tool_name.
// This is the spirit of "hypergraph-backed Φ" without touching the
// beagle-hypergraph crate — a pragmatic stopgap that gives the Φ math
// a substrate where the agent's acts and its concepts coexist.

#[derive(serde::Deserialize)]
pub struct JointPhiQuery {
    #[serde(default = "default_joint_window")]
    pub window: usize,
    /// Concept-expansion hops. 1 (default) = use only directly-extracted
    /// concept tokens. 2 = also include tokens that co-occurred with
    /// those tokens in past Φ measurements — a hypergraph-style 2-hop
    /// neighborhood without touching the beagle-hypergraph crate.
    #[serde(default = "default_hops")]
    pub hops: u8,
}

fn default_joint_window() -> usize {
    50
}
fn default_hops() -> u8 {
    1
}

#[derive(Serialize)]
pub struct JointPhiResponse {
    pub joint_phi: f64,
    pub ei_full: f64,
    pub ei_cut: f64,
    /// Substrate is a mix of tool_name atoms and concept tokens. Tool atoms
    /// are prefixed with "tool:" so you can tell them apart in MIP output.
    pub substrate: Vec<String>,
    pub substrate_size: usize,
    pub tool_atoms: usize,
    pub concept_atoms: usize,
    pub mip_partition: (Vec<String>, Vec<String>),
    pub trajectory_len: usize,
    pub hops_used: u8,
    /// Number of concept atoms added by the 2-hop expansion (zero when hops=1).
    pub expansion_added: usize,
    pub computed_at: DateTime<Utc>,
    pub truth_mode: &'static str,
}

fn extract_concept_tokens(text: &str, limit: usize) -> Vec<String> {
    const STOPWORDS: &[&str] = &[
        "a", "an", "and", "are", "as", "at", "be", "by", "for", "from", "has", "have",
        "in", "is", "it", "its", "of", "on", "or", "that", "the", "this", "to", "was",
        "were", "will", "with", "what", "how", "why", "do", "does", "did", "can",
        "you", "your", "my",
    ];
    let mut seen = std::collections::BTreeSet::new();
    let mut out = Vec::new();
    for w in text.to_lowercase().split(|c: char| !c.is_alphanumeric()) {
        if w.len() < 3 || STOPWORDS.contains(&w) {
            continue;
        }
        if seen.insert(w.to_string()) {
            out.push(w.to_string());
            if out.len() >= limit {
                break;
            }
        }
    }
    out
}

async fn cognitive_joint_phi_handler(
    State(state): State<AppState>,
    axum::extract::Query(params): axum::extract::Query<JointPhiQuery>,
) -> Json<JointPhiResponse> {
    use crate::phi_iit::{integrated_information, tpm_from_activations, MAX_SUBSTRATE};
    let window = params.window.clamp(4, 200);
    let hops = params.hops.clamp(1, 2);

    // Behavioral axis — last N distinct tool_name atoms.
    let chrono_tools = state.mcp_tools.trajectory(window).await;
    let mut substrate: Vec<String> = Vec::new();
    let mut idx: std::collections::HashMap<String, usize> =
        std::collections::HashMap::new();
    for name in &chrono_tools {
        if substrate.len() >= MAX_SUBSTRATE / 2 {
            break;
        }
        let key = format!("tool:{}", name);
        if !idx.contains_key(&key) {
            idx.insert(key.clone(), substrate.len());
            substrate.push(key);
        }
    }
    let tool_atoms = substrate.len();

    // Semantic axis — concepts extracted from recent phi measurements' queries.
    let recent_phi = state.phis.recent(window).await;
    for p in &recent_phi {
        for tok in extract_concept_tokens(&p.query_snippet, 4) {
            if substrate.len() >= MAX_SUBSTRATE {
                break;
            }
            if !idx.contains_key(&tok) {
                idx.insert(tok.clone(), substrate.len());
                substrate.push(tok);
            }
        }
        if substrate.len() >= MAX_SUBSTRATE {
            break;
        }
    }
    let direct_concepts = substrate.len() - tool_atoms;

    // 2-hop expansion — for each direct concept token, find other tokens
    // that co-occurred in the SAME phi-measurement query and pull them
    // into the substrate. Approximates a hypergraph 2-hop traversal:
    // direct concept → measurement → neighbor concept.
    let mut expansion_added = 0usize;
    if hops == 2 {
        let direct_set: std::collections::BTreeSet<String> = substrate
            .iter()
            .filter(|s| !s.starts_with("tool:"))
            .cloned()
            .collect();
        for p in &recent_phi {
            // Only walk this measurement's tokens if it contributed at
            // least one direct concept atom.
            let toks = extract_concept_tokens(&p.query_snippet, 8);
            let touches_direct = toks.iter().any(|t| direct_set.contains(t));
            if !touches_direct {
                continue;
            }
            for t in toks {
                if substrate.len() >= MAX_SUBSTRATE {
                    break;
                }
                if !idx.contains_key(&t) {
                    idx.insert(t.clone(), substrate.len());
                    substrate.push(t);
                    expansion_added += 1;
                }
            }
            if substrate.len() >= MAX_SUBSTRATE {
                break;
            }
        }
    }
    let concept_atoms = substrate.len() - tool_atoms;
    let _ = direct_concepts;
    let n = substrate.len();

    // Build an interleaved trajectory: tool_i → concepts_from_latest_phi → tool_{i+1}.
    // This gives the TPM transitions that cross the semantic/behavioral boundary.
    let mut trajectory: Vec<usize> = Vec::new();
    for (pos, name) in chrono_tools.iter().enumerate() {
        let key = format!("tool:{}", name);
        if let Some(&i) = idx.get(&key) {
            trajectory.push(i);
        }
        // Interleave with concept atoms from a phi measurement near this tool call.
        if let Some(p) = recent_phi.get(pos.min(recent_phi.len().saturating_sub(1))) {
            for tok in extract_concept_tokens(&p.query_snippet, 2) {
                if let Some(&i) = idx.get(&tok) {
                    trajectory.push(i);
                }
            }
        }
    }

    if trajectory.len() < 4 || n < 2 {
        return Json(JointPhiResponse {
            joint_phi: 0.0,
            ei_full: 0.0,
            ei_cut: 0.0,
            substrate,
            substrate_size: n,
            tool_atoms,
            concept_atoms,
            mip_partition: (Vec::new(), Vec::new()),
            trajectory_len: trajectory.len(),
            hops_used: hops,
            expansion_added,
            computed_at: Utc::now(),
            truth_mode: "declared",
        });
    }

    let tpm = tpm_from_activations(n, &[trajectory.clone()], 0.1);
    let r = integrated_information(&tpm);
    let mip_partition = (
        r.mip_lhs
            .iter()
            .map(|&i| substrate[i].clone())
            .collect::<Vec<_>>(),
        r.mip_rhs
            .iter()
            .map(|&i| substrate[i].clone())
            .collect::<Vec<_>>(),
    );

    Json(JointPhiResponse {
        joint_phi: r.phi,
        ei_full: r.ei_full,
        ei_cut: r.ei_cut,
        substrate,
        substrate_size: n,
        tool_atoms,
        concept_atoms,
        mip_partition,
        trajectory_len: trajectory.len(),
        hops_used: hops,
        expansion_added,
        computed_at: Utc::now(),
        truth_mode: "observed",
    })
}

pub fn cognitive_routes() -> Router<AppState> {
    Router::new()
        .route("/api/v1/cognitive/state", get(cognitive_state_handler))
        .route("/api/v1/cognitive/stream", get(cognitive_stream_handler))
        .route("/api/v1/cognitive/meta_phi", get(cognitive_meta_phi_handler))
        .route("/api/v1/cognitive/phi_of_phi", get(cognitive_phi_of_phi_handler))
        .route("/api/v1/cognitive/tool_rhythm_phi", get(cognitive_tool_rhythm_phi_handler))
        .route("/api/v1/cognitive/joint_phi", get(cognitive_joint_phi_handler))
        .route(
            "/api/cognitive/mcp_tool_call",
            axum::routing::post(cognitive_mcp_tool_call_handler),
        )
}
