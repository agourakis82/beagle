use crate::retrieval::GraphRagQuery;
use serde::{Deserialize, Serialize};

pub const GRAPHRAG_QUERY_MODE_VERSION: &str = "beagle-graphrag-query-mode-v1";

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
pub struct GraphRagQueryModeDecision {
    pub mode_version: String,
    pub policy_id: String,
    pub query_mode: String,
    pub classifier_source: String,
    pub classifier_reason: String,
    pub effective_top_k: usize,
    pub effective_max_hops: usize,
    #[serde(default)]
    pub effective_root_entity_type: Option<String>,
    #[serde(default)]
    pub effective_root_entity_id: Option<String>,
    pub note: String,
}

pub fn derive_graphrag_query_mode(query: &GraphRagQuery) -> GraphRagQueryModeDecision {
    let requested_hint = query
        .query_mode_hint
        .as_deref()
        .map(normalize_selector);
    let query_text = normalize_selector(&query.query_text);
    let root_entity_type = query.root_entity_type.as_deref().map(normalize_selector);

    let (query_mode, classifier_source, classifier_reason) =
        if let Some(hint) = requested_hint.as_deref() {
            match hint {
                "local" | "global" | "drift" => (
                    hint.to_string(),
                    "explicit-hint".to_string(),
                    format!("query_mode_hint={} requested an explicit GraphRAG mode", hint),
                ),
                _ => (
                    "local".to_string(),
                    "invalid-hint-fallback".to_string(),
                    format!("query_mode_hint={} is unsupported; falling back to local", hint),
                ),
            }
        } else if query_text_signals_drift(&query_text) {
            (
                "drift".to_string(),
                "content-heuristic".to_string(),
                "query text asked for temporal change, cross-session difference, or drift analysis".to_string(),
            )
        } else if query.filters.session_id.is_some()
            || matches!(
                root_entity_type.as_deref(),
                Some("session" | "workstream" | "experiment" | "result" | "claim")
            )
        {
            (
                "local".to_string(),
                "payload-filter".to_string(),
                "session/workstream/root-entity scope requested a bounded local GraphRAG neighborhood".to_string(),
            )
        } else if query.program_id.is_some()
            || query.filters.campaign_id.is_some()
            || matches!(
                root_entity_type.as_deref(),
                Some("program" | "campaign" | "manuscript")
            )
            || query_text_signals_global(&query_text)
        {
            (
                "global".to_string(),
                "scope-heuristic".to_string(),
                "program/campaign/manuscript scope requested a broader GraphRAG view than a single local neighborhood".to_string(),
            )
        } else if filters_present(query) {
            (
                "local".to_string(),
                "bounded-default".to_string(),
                "payload filters were present, so the bounded local GraphRAG mode remains safer by default".to_string(),
            )
        } else {
            (
                "global".to_string(),
                "default-global".to_string(),
                "no local or drift signal was present, so the broader GraphRAG mode became the default".to_string(),
            )
        };

    let (effective_top_k, effective_max_hops, effective_root_entity_type, effective_root_entity_id) =
        match query_mode.as_str() {
            "drift" => (
                query.top_k.clamp(4, 6),
                query.max_hops.clamp(2, 3),
                query
                    .root_entity_type
                    .clone()
                    .or_else(|| query.filters.workstream_id.as_ref().map(|_| "workstream".to_string()))
                    .or_else(|| query.filters.campaign_id.as_ref().map(|_| "campaign".to_string())),
                query
                    .root_entity_id
                    .clone()
                    .or_else(|| query.filters.workstream_id.clone())
                    .or_else(|| query.filters.campaign_id.clone()),
            ),
            "global" => (
                query.top_k.clamp(4, 6),
                query.max_hops.clamp(2, 3),
                query
                    .root_entity_type
                    .clone()
                    .or_else(|| query.program_id.as_ref().map(|_| "program".to_string()))
                    .or_else(|| query.filters.campaign_id.as_ref().map(|_| "campaign".to_string())),
                query
                    .root_entity_id
                    .clone()
                    .or_else(|| query.program_id.clone())
                    .or_else(|| query.filters.campaign_id.clone()),
            ),
            _ => (
                query.top_k.clamp(1, 5),
                query.max_hops.clamp(1, 2),
                query.root_entity_type.clone(),
                query.root_entity_id.clone(),
            ),
        };

    GraphRagQueryModeDecision {
        mode_version: GRAPHRAG_QUERY_MODE_VERSION.to_string(),
        policy_id: "b232-graphrag-query-mode-policy".to_string(),
        query_mode,
        classifier_source,
        classifier_reason,
        effective_top_k,
        effective_max_hops,
        effective_root_entity_type,
        effective_root_entity_id,
        note: "B23.2 keeps GraphRAG mode routing bounded: local stays neighborhood-scoped, global broadens program/campaign context, and drift relaxes session scope to examine change over time.".to_string(),
    }
}

pub fn apply_graphrag_query_mode(
    query: &GraphRagQuery,
    decision: &GraphRagQueryModeDecision,
) -> GraphRagQuery {
    let mut effective = query.clone();
    effective.top_k = decision.effective_top_k;
    effective.max_hops = decision.effective_max_hops;
    effective.root_entity_type = decision.effective_root_entity_type.clone();
    effective.root_entity_id = decision.effective_root_entity_id.clone();

    match decision.query_mode.as_str() {
        "global" => {
            effective.filters.session_id = None;
        }
        "drift" => {
            effective.filters.session_id = None;
        }
        _ => {}
    }

    effective
}

fn normalize_selector(value: &str) -> String {
    value.trim().to_ascii_lowercase()
}

fn filters_present(query: &GraphRagQuery) -> bool {
    query.filters.workstream_id.is_some()
        || query.filters.campaign_id.is_some()
        || query.filters.session_id.is_some()
        || query.filters.source.is_some()
        || query.filters.role.is_some()
        || query.filters.domain.is_some()
        || query.filters.repo_path.is_some()
        || query.filters.file_type.is_some()
        || !query.filters.tags.is_empty()
}

fn query_text_signals_drift(value: &str) -> bool {
    [
        "drift",
        "changed",
        "change over time",
        "across sessions",
        "across runs",
        "regression",
        "shift",
        "difference",
        "compare",
        "timeline",
        "trend",
    ]
    .iter()
    .any(|candidate| value.contains(candidate))
}

fn query_text_signals_global(value: &str) -> bool {
    [
        "global",
        "program",
        "campaign",
        "overview",
        "landscape",
        "manuscript",
        "cross-workstream",
        "cross campaign",
    ]
    .iter()
    .any(|candidate| value.contains(candidate))
}
