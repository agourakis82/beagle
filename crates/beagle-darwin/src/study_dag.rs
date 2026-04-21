use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};

pub const STUDY_DAG_PHASE: &str = "B26.1";
pub const STUDY_DAG_KIND: &str = "study-dag";
pub const STUDY_DAG_VERSION: &str = "beagle-study-dag-v1";

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
pub struct StudyDagNode {
    pub node_id: String,
    pub node_kind: String,
    pub label: String,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub run_id: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub variant_id: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
pub struct StudyDagEdge {
    pub edge_id: String,
    pub from_node_id: String,
    pub to_node_id: String,
    pub relation: String,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
pub struct StudyDag {
    pub phase: String,
    pub contract_kind: String,
    pub contract_version: String,
    pub study_dag_id: String,
    pub study_id: String,
    pub workstream_id: String,
    pub workspace_id: String,
    pub session_id: String,
    pub same_beagle_owned_identity: bool,
    pub generated_at: DateTime<Utc>,
    pub root_node_id: String,
    pub node_count: usize,
    pub edge_count: usize,
    pub nodes: Vec<StudyDagNode>,
    pub edges: Vec<StudyDagEdge>,
    pub note: String,
}
