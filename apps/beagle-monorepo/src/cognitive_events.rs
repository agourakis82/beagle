// cognitive_events.rs
//
// Single broadcast channel carrying every observable cognitive event so
// iOS / cockpit / dashboards can subscribe to a push stream instead of
// polling /api/v1/cognitive/state on a timer. Events are emitted by:
//
//   - void handler on a successful journey
//   - fractal handler on a completed tree
//   - exocortex handler on a Φ measurement
//   - /api/observer/physio on each new snapshot
//
// Design notes:
//   - Channel is `broadcast::channel(256)` — slow subscribers may miss
//     events (documented contract). iOS can reconcile with cognitive_state
//     on reconnect.
//   - Each registry + the physio handler call `state.cognitive_tx.send(...)`
//     best-effort; a zero-subscriber send is not an error.

use crate::jobs::{
    DeepThinkSummary, FractalTreeSummary, McpToolCallSummary, PhiMeasurementSummary,
    VoidJourneySummary,
};
use chrono::{DateTime, Utc};
use serde::Serialize;
use std::sync::Arc;
use tokio::sync::broadcast;

pub const CHANNEL_CAPACITY: usize = 256;

#[derive(Serialize, Clone, Debug)]
#[serde(tag = "event", rename_all = "snake_case")]
pub enum CognitiveEvent {
    Void(VoidJourneySummary),
    Fractal(FractalTreeSummary),
    Phi(PhiMeasurementSummary),
    Physio {
        source: String,
        hrv_ms: Option<f64>,
        hrv_level: Option<String>,
        flow_state: Option<String>,
        observed_at: DateTime<Utc>,
        truth_mode: String,
    },
    /// Composite event emitted once at the end of a /api/cognitive/deep-think
    /// run. Subscribers that want to wait for "journey complete" should key
    /// on this variant; the per-stage fractal/void/phi events fire just
    /// before it within the same request.
    DeepThink(DeepThinkSummary),
    /// One MCP tool invocation — pushed by the MCP server after every
    /// tools/call. Lets the platform measure Φ over the agents' own
    /// tool-usage rhythm, which is a second-order reflective signal.
    McpTool(McpToolCallSummary),
}

impl CognitiveEvent {
    /// SSE event name — iOS uses this to tag the handler for each variant.
    pub fn kind(&self) -> &'static str {
        match self {
            CognitiveEvent::Void(_) => "void",
            CognitiveEvent::Fractal(_) => "fractal",
            CognitiveEvent::Phi(_) => "phi",
            CognitiveEvent::Physio { .. } => "physio",
            CognitiveEvent::DeepThink(_) => "deep_think",
            CognitiveEvent::McpTool(_) => "mcp_tool",
        }
    }
}

/// Shareable sender. `Arc<broadcast::Sender<T>>` is the standard pattern;
/// `Sender` is already cheap to clone but wrapping in Arc matches the rest
/// of AppState's fields for consistency.
pub type CognitiveTx = Arc<broadcast::Sender<CognitiveEvent>>;

pub fn make_channel() -> (CognitiveTx, broadcast::Receiver<CognitiveEvent>) {
    let (tx, rx) = broadcast::channel(CHANNEL_CAPACITY);
    (Arc::new(tx), rx)
}

/// Best-effort send. Ignores zero-subscriber errors — these are expected
/// when no SSE client is currently connected.
pub fn emit(tx: &CognitiveTx, ev: CognitiveEvent) {
    let _ = tx.send(ev);
}
