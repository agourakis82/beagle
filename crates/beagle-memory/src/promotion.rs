use crate::engine::MemoryRecord;
use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};

pub const MEMORY_PROMOTION_POLICY_VERSION: &str = "beagle-memory-promotion-policy-v1";
pub const PROMOTED_MEMORY_VERSION: &str = "beagle-promoted-memory-v1";

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
pub struct MemoryPromotionRule {
    pub source_memory_type: String,
    pub target_memory_type: String,
    pub triggers: Vec<String>,
    pub bounded_requirements: Vec<String>,
    pub note: String,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
pub struct MemoryPromotionPolicy {
    pub policy_version: String,
    pub policy_id: String,
    pub rules: Vec<MemoryPromotionRule>,
    pub note: String,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
pub struct PromotedMemory {
    pub promotion_version: String,
    pub policy_id: String,
    pub source_memory_id: String,
    pub source_memory_type: String,
    pub target_memory_type: String,
    pub trigger: String,
    pub reason: String,
    #[serde(default)]
    pub workstream_id: Option<String>,
    #[serde(default)]
    pub campaign_id: Option<String>,
    #[serde(default)]
    pub session_id: Option<String>,
    pub supporting_refs: Vec<String>,
    pub retention_action: String,
    pub promoted_at: String,
    pub note: String,
}

pub fn memory_promotion_policy() -> MemoryPromotionPolicy {
    MemoryPromotionPolicy {
        policy_version: MEMORY_PROMOTION_POLICY_VERSION.to_string(),
        policy_id: "b232-memory-promotion-policy".to_string(),
        rules: vec![
            MemoryPromotionRule {
                source_memory_type: "episodic".to_string(),
                target_memory_type: "semantic".to_string(),
                triggers: vec![
                    "episodic text carries claim/evidence/result/manuscript language".to_string(),
                    "session recap hardens into reusable campaign knowledge".to_string(),
                ],
                bounded_requirements: vec![
                    "keep source memory_id and Beagle-owned identity".to_string(),
                    "only promote when explicit semantic language is present".to_string(),
                ],
                note: "B23.2 promotes episodic records into semantic memory only when the text itself has become reusable knowledge, not merely because it exists.".to_string(),
            },
            MemoryPromotionRule {
                source_memory_type: "episodic".to_string(),
                target_memory_type: "procedural".to_string(),
                triggers: vec![
                    "episodic text carries attach/launch/resume/config/script workflow language".to_string(),
                    "session recap becomes a reusable operator or repo-native procedure".to_string(),
                ],
                bounded_requirements: vec![
                    "keep source memory_id and Beagle-owned identity".to_string(),
                    "only promote when the text is actionable as procedure or runbook".to_string(),
                ],
                note: "B23.2 promotes episodic records into procedural memory when the content is now reusable execution know-how.".to_string(),
            },
        ],
        note: "B23.2 keeps promotion bounded: episodic memory does not disappear, but Beagle can explicitly recognize when it has hardened into semantic or procedural memory.".to_string(),
    }
}

pub fn classify_memory_type(record: &MemoryRecord) -> &'static str {
    let tags = record
        .tags
        .iter()
        .map(|value| value.to_ascii_lowercase())
        .collect::<Vec<_>>();
    let tag_refs = tags.iter().map(String::as_str).collect::<Vec<_>>();

    if record
        .repo_path
        .as_deref()
        .map(str::trim)
        .filter(|value| !value.is_empty())
        .is_some()
        || record
            .file_type
            .as_deref()
            .map(str::trim)
            .filter(|value| !value.is_empty())
            .is_some()
        || contains_any_strs(
            &tag_refs,
            &[
                "code",
                "config",
                "script",
                "workspace",
                "attach",
                "launch",
                "resume",
                "ssh",
                "k8s",
                "devcontainer",
                "procedural",
            ],
        )
    {
        return "procedural";
    }

    if !record.result_refs.is_empty()
        || !record.claim_refs.is_empty()
        || contains_any_strs(
            &tag_refs,
            &[
                "claim",
                "claims",
                "evidence",
                "semantic",
                "manuscript",
                "review",
                "release",
                "publication",
                "result",
            ],
        )
    {
        return "semantic";
    }

    "episodic"
}

pub fn derive_memory_promotion(
    record: &MemoryRecord,
    promoted_at: DateTime<Utc>,
    retention_action: &str,
) -> Option<PromotedMemory> {
    let source_memory_type = classify_memory_type(record);
    if source_memory_type != "episodic" {
        return None;
    }

    let (target_memory_type, trigger, reason, supporting_refs) =
        promotion_signal(record)?;

    Some(PromotedMemory {
        promotion_version: PROMOTED_MEMORY_VERSION.to_string(),
        policy_id: memory_promotion_policy().policy_id,
        source_memory_id: record.memory_id.clone(),
        source_memory_type: source_memory_type.to_string(),
        target_memory_type,
        trigger,
        reason,
        workstream_id: record.workstream_id.clone(),
        campaign_id: record.campaign_id.clone(),
        session_id: record.session_id.clone(),
        supporting_refs,
        retention_action: retention_action.to_string(),
        promoted_at: promoted_at.to_rfc3339(),
        note: "B23.2 promotion is bounded and explicit: Beagle preserves the source episodic memory while surfacing the hardened target memory type.".to_string(),
    })
}

pub fn promoted_target_memory_type(record: &MemoryRecord) -> Option<String> {
    promotion_signal(record).map(|(target_memory_type, _, _, _)| target_memory_type)
}

fn support_refs(record: &MemoryRecord, extra_ref: &str) -> Vec<String> {
    let mut refs = Vec::new();
    refs.extend(record.result_refs.iter().cloned());
    refs.extend(record.claim_refs.iter().cloned());
    if let Some(repo_path) = record.repo_path.as_ref().filter(|value| !value.trim().is_empty()) {
        refs.push(format!("repo_path:{}", repo_path.trim()));
    }
    if let Some(file_type) = record.file_type.as_ref().filter(|value| !value.trim().is_empty()) {
        refs.push(format!("file_type:{}", file_type.trim()));
    }
    refs.push(format!("signal:{}", extra_ref));
    unique_strings(refs)
}

fn promotion_signal(
    record: &MemoryRecord,
) -> Option<(String, String, String, Vec<String>)> {
    let text = normalize_text(&record.text);

    if contains_any_fragment(
        &text,
        &[
            "claim",
            "evidence",
            "finding",
            "result",
            "supports",
            "manuscript",
            "review bundle",
        ],
    ) {
        return Some((
            "semantic".to_string(),
            "text-semantic-signal".to_string(),
            "episodic text carried claim/evidence/manuscript language strong enough to harden into reusable semantic memory".to_string(),
            support_refs(record, "semantic-text"),
        ));
    }

    if contains_any_fragment(
        &text,
        &[
            "procedure",
            "runbook",
            "attach",
            "launch",
            "resume",
            "ssh",
            "kubectl",
            "config",
            "script",
            "workflow",
            "step ",
        ],
    ) {
        return Some((
            "procedural".to_string(),
            "text-procedural-signal".to_string(),
            "episodic text carried reusable operator or repo-native procedure language strong enough to harden into procedural memory".to_string(),
            support_refs(record, "procedural-text"),
        ));
    }

    None
}

fn normalize_text(value: &str) -> String {
    value
        .split_whitespace()
        .collect::<Vec<_>>()
        .join(" ")
        .to_ascii_lowercase()
}

fn contains_any_fragment(value: &str, candidates: &[&str]) -> bool {
    candidates
        .iter()
        .any(|candidate| value.contains(&candidate.to_ascii_lowercase()))
}

fn contains_any_strs(values: &[&str], expected: &[&str]) -> bool {
    values.iter().any(|value| {
        let normalized = value.trim().to_ascii_lowercase();
        expected
            .iter()
            .any(|candidate| normalized == *candidate || normalized.contains(candidate))
    })
}

fn unique_strings(values: Vec<String>) -> Vec<String> {
    let mut seen = std::collections::BTreeSet::new();
    let mut unique = Vec::new();
    for value in values {
        let normalized = value.trim().to_string();
        if !normalized.is_empty() && seen.insert(normalized.clone()) {
            unique.push(normalized);
        }
    }
    unique
}
