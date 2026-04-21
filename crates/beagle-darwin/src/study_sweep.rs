use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};

pub const STUDY_SWEEP_PHASE: &str = "B26.1";
pub const STUDY_SWEEP_KIND: &str = "study-sweep";
pub const STUDY_SWEEP_VERSION: &str = "beagle-study-sweep-v1";

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
pub struct StudySweepVariant {
    pub variant_id: String,
    pub variant_label: String,
    pub variant_kind: String,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub source_run_id: Option<String>,
    pub run_id: String,
    pub run_label: String,
    pub selected_subagent_id: String,
    pub task_family: String,
    pub compute_profile_id: String,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub replay_mode: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub compiler_profile_id: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub graphrag_query_mode: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub temporal_truth_view: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub recipe_kind: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub experiment_id: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
pub struct StudySweep {
    pub phase: String,
    pub contract_kind: String,
    pub contract_version: String,
    pub study_sweep_id: String,
    pub study_id: String,
    pub workstream_id: String,
    pub workspace_id: String,
    pub session_id: String,
    pub same_beagle_owned_identity: bool,
    pub generated_at: DateTime<Utc>,
    pub baseline_variant_id: String,
    pub variant_count: usize,
    pub run_count: usize,
    pub variants: Vec<StudySweepVariant>,
    pub note: String,
}
