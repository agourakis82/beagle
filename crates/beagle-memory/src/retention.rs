use serde::{Deserialize, Serialize};

pub const MEMORY_RETENTION_POLICY_VERSION: &str = "beagle-memory-retention-policy-v1";

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
pub struct MemoryRetentionRule {
    pub memory_type: String,
    pub retention_action: String,
    #[serde(default)]
    pub expires_after_days: Option<u32>,
    #[serde(default)]
    pub compact_by: Vec<String>,
    pub bounded_by: Vec<String>,
    pub note: String,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
pub struct MemoryRetentionPolicy {
    pub policy_version: String,
    pub policy_id: String,
    pub rules: Vec<MemoryRetentionRule>,
    pub note: String,
}

pub fn memory_retention_policy() -> MemoryRetentionPolicy {
    MemoryRetentionPolicy {
        policy_version: MEMORY_RETENTION_POLICY_VERSION.to_string(),
        policy_id: "b232-memory-retention-policy".to_string(),
        rules: vec![
            MemoryRetentionRule {
                memory_type: "episodic".to_string(),
                retention_action: "expire-or-compact".to_string(),
                expires_after_days: Some(14),
                compact_by: vec![
                    "conversation_id".to_string(),
                    "session_id".to_string(),
                    "recent-first".to_string(),
                ],
                bounded_by: vec![
                    "keep only bounded recent chronology".to_string(),
                    "allow promotion before expiry".to_string(),
                ],
                note: "Episodic memory is intentionally bounded: it preserves continuity first, then expires or compacts when no longer active.".to_string(),
            },
            MemoryRetentionRule {
                memory_type: "semantic".to_string(),
                retention_action: "retain-active-campaign-window".to_string(),
                expires_after_days: Some(90),
                compact_by: vec![
                    "claim_refs".to_string(),
                    "result_refs".to_string(),
                    "campaign_id".to_string(),
                ],
                bounded_by: vec![
                    "keep while claims/results remain live".to_string(),
                    "compact duplicates into canonical evidence-bearing references".to_string(),
                ],
                note: "Semantic memory should stay longer than episodic memory, but it still compacts around canonical claims and results.".to_string(),
            },
            MemoryRetentionRule {
                memory_type: "procedural".to_string(),
                retention_action: "retain-until-superseded".to_string(),
                expires_after_days: None,
                compact_by: vec![
                    "repo_path".to_string(),
                    "file_type".to_string(),
                    "workflow-signature".to_string(),
                ],
                bounded_by: vec![
                    "keep the newest working runbook".to_string(),
                    "compact stale procedural variants when superseded".to_string(),
                ],
                note: "Procedural memory persists as reusable know-how, but it compacts around the newest repo-native workflow signature.".to_string(),
            },
        ],
        note: "B23.2 makes forgetting explicit without deleting the canonical memory spine: episodic expires first, semantic compacts by evidence, procedural compacts by supersession.".to_string(),
    }
}

pub fn retention_action_for_memory_type(memory_type: &str) -> String {
    memory_retention_policy()
        .rules
        .into_iter()
        .find(|rule| rule.memory_type == memory_type)
        .map(|rule| rule.retention_action)
        .unwrap_or_else(|| "retain-bounded".to_string())
}
