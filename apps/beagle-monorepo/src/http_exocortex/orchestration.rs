//! Orchestration + verification endpoints consumed by the BeagleCockpit A/B/C layer.
//!
//! POST /api/exocortex/v1/verify       — temporal memory verification for a chat message
//! POST /api/orchestration/plan/confirm — commit an agent plan (log + ack)

use super::{internal_error, memory_engine_recall, ExocortexRepository, RecallSource};
use axum::{extract::State, http::StatusCode, Json};
use beagle_config::beagle_data_dir;
use chrono::Utc;
use serde::{Deserialize, Serialize};
use std::io::Write as _;
use uuid::Uuid;

// ---------------------------------------------------------------------------
// POST /api/exocortex/v1/verify
// ---------------------------------------------------------------------------

#[derive(Debug, Deserialize)]
pub(crate) struct VerifyRequest {
    pub message_id: String,
    pub profile_id: String,
    pub lookback_days: Option<i64>,
    /// Optional: raw message text from client (improves query quality).
    #[serde(default)]
    pub content: Option<String>,
}

#[derive(Debug, Serialize)]
pub(crate) struct VerifyResponse {
    pub message_id: String,
    pub sources: Vec<EvidenceItem>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub temporal_conflict: Option<TemporalConflict>,
}

#[derive(Debug, Serialize)]
pub(crate) struct EvidenceItem {
    pub id: String,
    pub label: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub url: Option<String>,
    pub confidence: EvidenceConfidence,
}

#[derive(Debug, Serialize)]
#[serde(rename_all = "snake_case")]
pub(crate) enum EvidenceConfidence {
    Cited,
    Inferred,
    Unverified,
    Conflict,
}

#[derive(Debug, Serialize)]
pub(crate) struct TemporalConflict {
    pub summary: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub note_id: Option<String>,
    pub days_ago: i64,
}

/// Classify a recall source into an EvidenceConfidence tier.
fn classify_source(source: &RecallSource) -> EvidenceConfidence {
    let text_lower = source.text.to_lowercase();
    let has_conflict_signal = text_lower.contains("contradicts")
        || text_lower.contains("however,")
        || text_lower.contains("but note")
        || text_lower.contains("updated:")
        || text_lower.contains("superseded")
        || text_lower.contains("revise")
        || text_lower.contains("correction:");
    if has_conflict_signal {
        return EvidenceConfidence::Conflict;
    }
    if source.score >= 0.80 {
        EvidenceConfidence::Cited
    } else if source.score >= 0.50 {
        EvidenceConfidence::Inferred
    } else {
        EvidenceConfidence::Unverified
    }
}

/// Map profile_id to a domain query phrase for targeted memory recall.
fn profile_query(profile_id: &str, content: Option<&str>) -> String {
    if let Some(text) = content.filter(|s| !s.is_empty()) {
        // If content is provided, use it directly (up to 400 chars).
        let snippet: String = text.chars().take(400).collect();
        return format!("verify claim: {snippet}");
    }
    match profile_id {
        "darwin" | "Darwin" => {
            "recent medical claims, clinical notes, treatment decisions, and contradictions"
                .to_string()
        }
        "claudeCode" | "claude_code" => {
            "recent code decisions, technical patterns, architecture choices, and their rationale"
                .to_string()
        }
        "cluster" => {
            "recent cluster operations, infrastructure decisions, and configuration changes"
                .to_string()
        }
        "grok" => {
            "recent research claims, scientific findings, and epistemic notes".to_string()
        }
        "kimi" => {
            "recent long-context analysis, document summaries, and extracted facts".to_string()
        }
        "codex" => {
            "recent code reviews, refactoring decisions, and API design notes".to_string()
        }
        _ => "recent knowledge artifacts, claims, and decisions".to_string(),
    }
}

/// Estimate how many days ago a memory source was recorded, based on its date string.
/// Returns None if the date cannot be parsed or is absent.
fn days_ago(date_str: Option<&str>) -> Option<i64> {
    let s = date_str?;
    // Accept RFC3339 / ISO 8601 (the canonical exocortex format).
    let dt = chrono::DateTime::parse_from_rfc3339(s).ok()?;
    let diff = Utc::now().signed_duration_since(dt.with_timezone(&chrono::Utc));
    Some(diff.num_days().max(0))
}

pub(crate) async fn verify_handler(
    State(_state): State<crate::http::AppState>,
    Json(req): Json<VerifyRequest>,
) -> Result<Json<VerifyResponse>, StatusCode> {
    let lookback = req.lookback_days.unwrap_or(30).max(1).min(365);
    let query = profile_query(&req.profile_id, req.content.as_deref());

    // Recall up to 8 relevant memory atoms within the lookback window.
    let sources = memory_engine_recall(&query, &req.profile_id, 8).await;

    // Filter to lookback window and build evidence items.
    let mut temporal_conflict: Option<TemporalConflict> = None;
    let mut evidence: Vec<EvidenceItem> = Vec::new();

    for (i, src) in sources.iter().enumerate() {
        // If we have a date, check it's within the requested window.
        let age = days_ago(src.date.as_deref());
        if let Some(d) = age {
            if d > lookback {
                continue;
            }
        }

        let confidence = classify_source(src);

        // Surface first conflict as the temporal conflict block.
        if matches!(confidence, EvidenceConfidence::Conflict) && temporal_conflict.is_none() {
            let snippet: String = src.text.chars().take(120).collect();
            temporal_conflict = Some(TemporalConflict {
                summary: snippet,
                note_id: Some(format!("mem-{i}")),
                days_ago: age.unwrap_or(0),
            });
        }

        let label: String = src.text.chars().take(60).collect();
        evidence.push(EvidenceItem {
            id: Uuid::new_v4().to_string(),
            label,
            url: None,
            confidence,
        });

        if evidence.len() >= 6 {
            break;
        }
    }

    // If recall returned nothing, return a single unverified placeholder so the
    // iOS strip renders "? No local sources" rather than an empty state.
    if evidence.is_empty() {
        evidence.push(EvidenceItem {
            id: Uuid::new_v4().to_string(),
            label: "No local memory found for this query".to_string(),
            url: None,
            confidence: EvidenceConfidence::Unverified,
        });
    }

    Ok(Json(VerifyResponse {
        message_id: req.message_id,
        sources: evidence,
        temporal_conflict,
    }))
}

// ---------------------------------------------------------------------------
// POST /api/orchestration/plan/confirm
// ---------------------------------------------------------------------------

#[derive(Debug, Deserialize)]
pub(crate) struct ConfirmPlanRequest {
    pub plan_id: String,
    pub steps: Vec<ConfirmedStep>,
}

#[derive(Debug, Deserialize, Serialize)]
pub(crate) struct ConfirmedStep {
    pub id: String,
    pub depth: i64,
}

#[derive(Debug, Serialize)]
pub(crate) struct ConfirmPlanResponse {
    pub ok: bool,
    pub plan_id: String,
}

pub(crate) async fn confirm_plan_handler(
    State(_state): State<crate::http::AppState>,
    Json(req): Json<ConfirmPlanRequest>,
) -> Result<Json<ConfirmPlanResponse>, StatusCode> {
    let entry = serde_json::json!({
        "ts": Utc::now().to_rfc3339(),
        "kind": "plan_confirmed",
        "plan_id": req.plan_id,
        "steps": req.steps,
    });

    // Append to orchestration log in BEAGLE_DATA_DIR (fail-soft: log the error,
    // still return ok so the client doesn't retry on a simple file I/O hiccup).
    let data_dir = beagle_data_dir();
    let log_path = data_dir.join("orchestration_plans.jsonl");
    if let Err(e) = (|| -> anyhow::Result<()> {
        let mut f = std::fs::OpenOptions::new()
            .create(true)
            .append(true)
            .open(&log_path)?;
        writeln!(f, "{entry}")?;
        Ok(())
    })() {
        tracing::warn!("confirm_plan: could not write to {:?}: {e:#}", log_path);
    }

    let plan_id = req.plan_id.clone();
    Ok(Json(ConfirmPlanResponse { ok: true, plan_id }))
}
