use crate::engine::MemoryRecord;
use crate::promotion::classify_memory_type;
use serde::{Deserialize, Serialize};

pub const TEMPORAL_MEMORY_VERSION: &str = "beagle-temporal-memory-v1";
pub const MEMORY_CONTRADICTION_VERSION: &str = "beagle-memory-contradiction-v1";
pub const TEMPORAL_QUERY_VERSION: &str = "beagle-temporal-query-v1";
pub const TEMPORAL_QUERY_RESULT_VERSION: &str = "beagle-temporal-query-result-v1";

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
pub struct TemporalMemorySchema {
    pub schema_version: String,
    pub policy_id: String,
    pub current_truth_rule: String,
    pub historical_truth_rule: String,
    pub contradiction_rule: String,
    pub validity_markers: Vec<String>,
    pub bounded_entity_types: Vec<String>,
    pub note: String,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct TemporalMemoryVersion {
    pub memory_id: String,
    pub memory_type: String,
    pub truth_status: String,
    pub version_index: usize,
    pub observed_at: String,
    pub valid_from: String,
    #[serde(default)]
    pub valid_until: Option<String>,
    #[serde(default)]
    pub workstream_id: Option<String>,
    #[serde(default)]
    pub campaign_id: Option<String>,
    #[serde(default)]
    pub session_id: Option<String>,
    #[serde(default)]
    pub claim_refs: Vec<String>,
    #[serde(default)]
    pub result_refs: Vec<String>,
    pub snippet: String,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct TemporalMemoryTrack {
    pub temporal_version: String,
    pub truth_key: String,
    pub entity_refs: Vec<String>,
    pub current_memory_id: String,
    #[serde(default)]
    pub historical_memory_ids: Vec<String>,
    pub version_count: usize,
    pub contradiction_count: usize,
    pub current_memory_type: String,
    #[serde(default)]
    pub latest_observed_at: Option<String>,
    pub versions: Vec<TemporalMemoryVersion>,
    pub note: String,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct MemoryContradiction {
    pub contradiction_version: String,
    pub contradiction_id: String,
    pub truth_key: String,
    pub contradiction_kind: String,
    pub contradiction_status: String,
    pub current_memory_id: String,
    pub contradicted_memory_id: String,
    pub entity_refs: Vec<String>,
    pub current_observed_at: String,
    pub contradicted_observed_at: String,
    pub reason: String,
    pub current_snippet: String,
    pub contradicted_snippet: String,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct TemporalQuery {
    pub query_version: String,
    pub query_text: String,
    pub truth_view: String,
    pub top_k: usize,
    pub dense_enabled: bool,
    pub sparse_enabled: bool,
    pub dense_weight: f32,
    pub sparse_weight: f32,
    pub filters: crate::retrieval::RetrievalFilters,
    #[serde(default)]
    pub root_entity_type: Option<String>,
    #[serde(default)]
    pub root_entity_id: Option<String>,
    #[serde(default)]
    pub subject_refs: Vec<String>,
    #[serde(default)]
    pub include_contradictions: bool,
    #[serde(default)]
    pub query_type_hint: Option<String>,
    #[serde(default)]
    pub query_mode_hint: Option<String>,
    #[serde(default)]
    pub rerank_hint: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct TemporalQueryResult {
    pub result_version: String,
    pub schema_version: String,
    pub truth_view: String,
    pub collection_name: String,
    pub query_type: String,
    pub retrieval_mode: String,
    pub dense_backend: String,
    pub sparse_backend: String,
    pub reranker_backend: String,
    pub reranking_applied: bool,
    pub applied_filters: crate::retrieval::RetrievalFilters,
    #[serde(default)]
    pub temporal_root_entity_type: Option<String>,
    #[serde(default)]
    pub temporal_root_entity_id: Option<String>,
    pub subject_refs: Vec<String>,
    pub track_count: usize,
    pub current_truth_count: usize,
    pub historical_truth_count: usize,
    pub contradiction_count: usize,
    pub top_current_memory_ids: Vec<String>,
    pub top_historical_memory_ids: Vec<String>,
    pub tracks: Vec<TemporalMemoryTrack>,
    pub contradictions: Vec<MemoryContradiction>,
    pub note: String,
}

pub fn temporal_memory_schema() -> TemporalMemorySchema {
    TemporalMemorySchema {
        schema_version: TEMPORAL_MEMORY_VERSION.to_string(),
        policy_id: "b234-temporal-memory-policy".to_string(),
        current_truth_rule: "Keep the newest valid memory version per canonical truth key as current truth.".to_string(),
        historical_truth_rule: "Preserve prior memory versions as historical truth rather than deleting them when a newer version supersedes them.".to_string(),
        contradiction_rule: "Mark contradiction explicitly when a newer version flips state against an older version over the same canonical subject.".to_string(),
        validity_markers: vec![
            "observed_at".to_string(),
            "valid_from".to_string(),
            "valid_until".to_string(),
            "version_index".to_string(),
            "truth_status".to_string(),
        ],
        bounded_entity_types: vec![
            "Program".to_string(),
            "Campaign".to_string(),
            "Workstream".to_string(),
            "Session".to_string(),
            "Experiment".to_string(),
            "Result".to_string(),
            "Claim".to_string(),
            "Manuscript".to_string(),
            "Procedure".to_string(),
        ],
        note: "B23.4 adds bounded temporal truth handling on top of Beagle-owned memories: current truth stays explicit, prior truth remains retrievable, and contradictions are surfaced instead of deleting history.".to_string(),
    }
}

pub fn normalize_truth_view(value: &str) -> &'static str {
    match value.trim().to_ascii_lowercase().as_str() {
        "current" => "current",
        "historical" => "historical",
        _ => "both",
    }
}

pub fn temporal_truth_keys(record: &MemoryRecord) -> Vec<String> {
    let mut keys = Vec::new();

    for claim_ref in &record.claim_refs {
        if let Some(value) = prefixed_ref("claim", claim_ref) {
            keys.push(value);
        }
    }
    if keys.is_empty() {
        for result_ref in &record.result_refs {
            if let Some(value) = prefixed_ref("result", result_ref) {
                keys.push(value);
            }
        }
    }
    if keys.is_empty() {
        if let Some(repo_path) = record
            .repo_path
            .as_deref()
            .map(str::trim)
            .filter(|value| !value.is_empty())
        {
            keys.push(format!("procedure:repo:{}", repo_path));
        } else if let Some(file_type) = record
            .file_type
            .as_deref()
            .map(str::trim)
            .filter(|value| !value.is_empty())
        {
            if let Some(workstream_id) = record
                .workstream_id
                .as_deref()
                .map(str::trim)
                .filter(|value| !value.is_empty())
            {
                keys.push(format!("procedure:file:{}:{}", workstream_id, file_type));
            } else {
                keys.push(format!("procedure:file:{}", file_type));
            }
        }
    }
    if keys.is_empty() {
        keys.push(format!("memory:{}", record.memory_id));
    }

    unique_strings(keys)
}

pub fn temporal_entity_refs(record: &MemoryRecord) -> Vec<String> {
    let mut refs = Vec::new();
    if let Some(program_id) = record
        .program_id
        .as_deref()
        .map(str::trim)
        .filter(|value| !value.is_empty())
    {
        refs.push(format!("program:{}", program_id));
    }
    if let Some(campaign_id) = record
        .campaign_id
        .as_deref()
        .map(str::trim)
        .filter(|value| !value.is_empty())
    {
        refs.push(format!("campaign:{}", campaign_id));
    }
    if let Some(workstream_id) = record
        .workstream_id
        .as_deref()
        .map(str::trim)
        .filter(|value| !value.is_empty())
    {
        refs.push(format!("workstream:{}", workstream_id));
    }
    if let Some(session_id) = record
        .session_id
        .as_deref()
        .map(str::trim)
        .filter(|value| !value.is_empty())
    {
        refs.push(format!("session:{}", session_id));
    }
    for claim_ref in &record.claim_refs {
        if let Some(value) = prefixed_ref("claim", claim_ref) {
            refs.push(value);
        }
    }
    for result_ref in &record.result_refs {
        if let Some(value) = prefixed_ref("result", result_ref) {
            refs.push(value);
        }
    }
    if let Some(repo_path) = record
        .repo_path
        .as_deref()
        .map(str::trim)
        .filter(|value| !value.is_empty())
    {
        refs.push(format!("procedure:repo:{}", repo_path));
    }
    unique_strings(refs)
}

pub fn temporal_version_from_record(
    record: &MemoryRecord,
    truth_status: &str,
    version_index: usize,
    valid_until: Option<String>,
) -> TemporalMemoryVersion {
    TemporalMemoryVersion {
        memory_id: record.memory_id.clone(),
        memory_type: classify_memory_type(record).to_string(),
        truth_status: truth_status.to_string(),
        version_index,
        observed_at: record.timestamp.to_rfc3339(),
        valid_from: record.timestamp.to_rfc3339(),
        valid_until,
        workstream_id: record.workstream_id.clone(),
        campaign_id: record.campaign_id.clone(),
        session_id: record.session_id.clone(),
        claim_refs: record.claim_refs.clone(),
        result_refs: record.result_refs.clone(),
        snippet: bounded_temporal_snippet(&record.text),
    }
}

pub fn detect_temporal_contradiction(
    current: &MemoryRecord,
    prior: &MemoryRecord,
) -> Option<(String, String)> {
    let current_signal = contradiction_signal(&current.text);
    let prior_signal = contradiction_signal(&prior.text);

    if let (Some(current_signal), Some(prior_signal)) = (current_signal, prior_signal) {
        if current_signal != prior_signal {
            return Some((
                "explicit-state-flip".to_string(),
                format!(
                    "same canonical subject flipped from {} to {} across preserved memory versions",
                    prior_signal, current_signal
                ),
            ));
        }
    }

    None
}

fn contradiction_signal(text: &str) -> Option<&'static str> {
    let normalized = normalize_text(text);
    let blocked = [
        "blocked",
        "not ready",
        "red",
        "disabled",
        "stale",
        "failed",
        "regression",
        "contradiction",
        "superseded",
    ]
    .iter()
    .any(|signal| normalized.contains(signal));
    let ready = [
        "ready",
        "green",
        "enabled",
        "active",
        "coherent",
        "working",
        "confirmed",
        "resolved",
    ]
    .iter()
    .any(|signal| normalized.contains(signal));

    if blocked {
        Some("blocked")
    } else if ready {
        Some("ready")
    } else {
        None
    }
}

fn prefixed_ref(prefix: &str, value: &str) -> Option<String> {
    let trimmed = value.trim();
    if trimmed.is_empty() {
        return None;
    }
    let prefix_with_colon = format!("{}:", prefix);
    if trimmed.to_ascii_lowercase().starts_with(&prefix_with_colon) {
        Some(trimmed.to_string())
    } else {
        Some(format!("{}{}", prefix_with_colon, trimmed))
    }
}

fn bounded_temporal_snippet(value: &str) -> String {
    value.split_whitespace().collect::<Vec<_>>().join(" ").chars().take(220).collect()
}

fn normalize_text(value: &str) -> String {
    value
        .split_whitespace()
        .collect::<Vec<_>>()
        .join(" ")
        .to_ascii_lowercase()
}

fn unique_strings(values: Vec<String>) -> Vec<String> {
    let mut unique = Vec::new();
    for value in values {
        let trimmed = value.trim();
        if trimmed.is_empty() {
            continue;
        }
        if unique.iter().any(|existing: &String| existing == trimmed) {
            continue;
        }
        unique.push(trimmed.to_string());
    }
    unique
}
