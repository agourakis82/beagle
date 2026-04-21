// http_feedback.rs
//
// Feedback REST API — exposes beagle-feedback crate via HTTP for iOS/cockpit
// clients. File-backed under $BEAGLE_DATA_DIR; reads JSONL stream.

use crate::http::AppState;
use axum::{
    extract::{Path as AxPath, Query, State},
    routing::{get, post},
    Json, Router,
};
use beagle_feedback::{FeedbackEvent, FeedbackEventType, load_all_events, load_events_by_run_id};
use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};
use std::path::PathBuf;

#[derive(Deserialize)]
pub struct FeedbackSubmitRequest {
    pub event_type: String,         // "pipeline_run" | "triad_completed" | "human_feedback"
    pub run_id: String,
    #[serde(default)]
    pub question: Option<String>,
    #[serde(default)]
    pub hrv_level: Option<String>,
    #[serde(default)]
    pub llm_provider_main: Option<String>,
    #[serde(default)]
    pub accepted: Option<bool>,
    #[serde(default)]
    pub rating_0_10: Option<u8>,
    #[serde(default)]
    pub notes: Option<String>,
    #[serde(default)]
    pub evaluator_id: Option<String>,
}

#[derive(Serialize)]
pub struct FeedbackSubmitResponse {
    pub ok: bool,
    pub run_id: String,
    pub appended_at: DateTime<Utc>,
    pub truth_mode: &'static str,
}

#[derive(Deserialize)]
pub struct FeedbackQueryParams {
    #[serde(default)]
    pub limit: Option<usize>,
    #[serde(default)]
    pub event_type: Option<String>,
    #[serde(default)]
    pub run_id: Option<String>,
}

#[derive(Serialize)]
pub struct FeedbackQueryResponse {
    pub events: Vec<FeedbackEvent>,
    pub total: usize,
    pub truth_mode: &'static str,
}

fn parse_event_type(s: &str) -> Result<FeedbackEventType, String> {
    match s.to_ascii_lowercase().as_str() {
        "pipeline_run" => Ok(FeedbackEventType::PipelineRun),
        "triad_completed" => Ok(FeedbackEventType::TriadCompleted),
        "human_feedback" => Ok(FeedbackEventType::HumanFeedback),
        other => Err(format!("unknown event_type: {}", other)),
    }
}

/// Root data directory — append_event will create a `feedback` subdir inside.
fn data_root(_state: &AppState) -> PathBuf {
    std::env::var("BEAGLE_DATA_DIR")
        .map(PathBuf::from)
        .unwrap_or_else(|_| PathBuf::from("/var/lib/beagle"))
}

async fn feedback_submit_handler(
    State(state): State<AppState>,
    Json(req): Json<FeedbackSubmitRequest>,
) -> Result<Json<FeedbackSubmitResponse>, (axum::http::StatusCode, String)> {
    let event_type = parse_event_type(&req.event_type)
        .map_err(|e| (axum::http::StatusCode::BAD_REQUEST, e))?;

    let now = Utc::now();
    let event = FeedbackEvent {
        event_type,
        run_id: req.run_id.clone(),
        timestamp: now,
        question: req.question,
        draft_md: None,
        draft_pdf: None,
        triad_final_md: None,
        triad_report_json: None,
        hrv_level: req.hrv_level,
        llm_provider_main: req.llm_provider_main,
        grok3_calls: None,
        grok4_heavy_calls: None,
        grok3_tokens_est: None,
        grok4_tokens_est: None,
        accepted: req.accepted,
        rating_0_10: req.rating_0_10,
        clarity_0_10: None,
        adequacy_of_tone_0_10: None,
        usefulness_0_10: None,
        safety_or_emotional_fit_0_10: None,
        notes: req.notes,
        evaluator_id: req.evaluator_id,
        judgment_protocol: None,
        blinded_item_id: None,
        experiment_condition: None,
        experiment_id: None,
    };

    let root = data_root(&state);
    std::fs::create_dir_all(&root)
        .map_err(|e| (axum::http::StatusCode::INTERNAL_SERVER_ERROR, format!("mkdir: {}", e)))?;

    beagle_feedback::append_event(&root, &event)
        .map_err(|e| (axum::http::StatusCode::INTERNAL_SERVER_ERROR, format!("append: {}", e)))?;

    Ok(Json(FeedbackSubmitResponse {
        ok: true,
        run_id: req.run_id,
        appended_at: now,
        truth_mode: "observed",
    }))
}

async fn feedback_query_handler(
    State(state): State<AppState>,
    Query(params): Query<FeedbackQueryParams>,
) -> Result<Json<FeedbackQueryResponse>, (axum::http::StatusCode, String)> {
    let root = data_root(&state);
    let limit = params.limit.unwrap_or(50);
    let event_type_filter = params
        .event_type
        .as_deref()
        .and_then(|s| parse_event_type(s).ok());
    let run_id_filter = params.run_id;

    let all = load_all_events(&root)
        .map_err(|e| (axum::http::StatusCode::INTERNAL_SERVER_ERROR, format!("load: {}", e)))?;

    let mut events: Vec<FeedbackEvent> = all
        .into_iter()
        .filter(|e| {
            if let Some(ref t) = event_type_filter {
                if &e.event_type != t {
                    return false;
                }
            }
            if let Some(ref rid) = run_id_filter {
                if e.run_id != *rid {
                    return false;
                }
            }
            true
        })
        .collect();

    // Reverse chronological — latest first
    events.sort_by(|a, b| b.timestamp.cmp(&a.timestamp));
    events.truncate(limit);

    let total = events.len();

    Ok(Json(FeedbackQueryResponse {
        events,
        total,
        truth_mode: "observed",
    }))
}

async fn feedback_run_handler(
    State(state): State<AppState>,
    AxPath(run_id): AxPath<String>,
) -> Result<Json<FeedbackQueryResponse>, (axum::http::StatusCode, String)> {
    let root = data_root(&state);
    let mut events = load_events_by_run_id(&root, &run_id)
        .map_err(|e| (axum::http::StatusCode::INTERNAL_SERVER_ERROR, format!("load: {}", e)))?;
    events.sort_by(|a, b| a.timestamp.cmp(&b.timestamp));
    let total = events.len();

    Ok(Json(FeedbackQueryResponse {
        events,
        total,
        truth_mode: "observed",
    }))
}

pub fn feedback_routes() -> Router<AppState> {
    Router::new()
        .route("/api/v1/feedback", post(feedback_submit_handler))
        .route("/api/v1/feedback", get(feedback_query_handler))
        .route("/api/v1/feedback/:run_id", get(feedback_run_handler))
}
