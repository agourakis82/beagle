//! B26.6 — Next-study seed derived from an adopted bounded baseline (no auto-launch).

use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};

pub const NEXT_STUDY_SEED_PHASE: &str = "B26.6";
pub const NEXT_STUDY_SEED_KIND: &str = "next-study-seed";
pub const NEXT_STUDY_SEED_VERSION: &str = "beagle-next-study-seed-v1";

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
pub struct NextStudySeed {
    pub phase: String,
    pub contract_kind: String,
    pub contract_version: String,
    pub seed_id: String,
    pub parent_study_id: String,
    pub baseline_adoption_id: String,
    pub promoted_variant_receipt_id: String,
    pub workstream_id: String,
    pub workspace_id: String,
    pub session_id: String,
    pub same_beagle_owned_identity: bool,
    pub seeded_baseline_variant_id: String,
    pub seeded_baseline_run_id: String,
    pub seeded_baseline_compute_profile_id: String,
    pub suggested_next_study_id: String,
    pub auto_launch_new_study: bool,
    pub deferred_launch_reason: String,
    pub comparator_variant_ids_hint: Vec<String>,
    pub generated_at: DateTime<Utc>,
    pub scientific_readiness_limits_acknowledged: bool,
    pub note: String,
}

#[allow(clippy::too_many_arguments)]
pub fn build_next_study_seed(
    receipt_id: &str,
    adoption_id: &str,
    study_id: &str,
    workstream_id: &str,
    workspace_id: &str,
    session_id: &str,
    same_beagle_owned_identity: bool,
    promoted_variant_id: &str,
    promoted_run_id: &str,
    promoted_compute_profile_id: &str,
    archived_variant_ids: &[String],
    generated_at: DateTime<Utc>,
) -> NextStudySeed {
    let suggested_next_study_id = format!(
        "{}-next-{}",
        sanitize_component(study_id),
        generated_at.timestamp_millis()
    );
    NextStudySeed {
        phase: NEXT_STUDY_SEED_PHASE.to_string(),
        contract_kind: NEXT_STUDY_SEED_KIND.to_string(),
        contract_version: NEXT_STUDY_SEED_VERSION.to_string(),
        seed_id: format!("{}-next-study-seed", sanitize_component(study_id)),
        parent_study_id: study_id.to_string(),
        baseline_adoption_id: adoption_id.to_string(),
        promoted_variant_receipt_id: receipt_id.to_string(),
        workstream_id: workstream_id.to_string(),
        workspace_id: workspace_id.to_string(),
        session_id: session_id.to_string(),
        same_beagle_owned_identity,
        seeded_baseline_variant_id: promoted_variant_id.to_string(),
        seeded_baseline_run_id: promoted_run_id.to_string(),
        seeded_baseline_compute_profile_id: promoted_compute_profile_id.to_string(),
        suggested_next_study_id,
        auto_launch_new_study: false,
        deferred_launch_reason: "B26.6 explicitly defers study launch; operators must open a new comparative study using this seed.".to_string(),
        comparator_variant_ids_hint: archived_variant_ids.to_vec(),
        generated_at,
        scientific_readiness_limits_acknowledged: true,
        note: "Seed preserves Beagle-owned workspace/session anchors and references the adopted baseline variant/run for a future bounded comparative study.".to_string(),
    }
}

fn sanitize_component(value: &str) -> String {
    let sanitized = value
        .trim()
        .chars()
        .map(|character| {
            if character.is_ascii_alphanumeric() || character == '-' || character == '_' {
                character
            } else {
                '-'
            }
        })
        .collect::<String>();
    let compact = sanitized
        .split('-')
        .filter(|part| !part.is_empty())
        .collect::<Vec<_>>()
        .join("-");
    if compact.is_empty() {
        "value".to_string()
    } else {
        compact
    }
}
