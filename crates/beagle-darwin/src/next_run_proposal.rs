use crate::study_decision::StudyEvidenceRef;
use crate::study_registry::StudyRegistry;
use anyhow::Context;
use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};
use std::fs;
use std::path::{Path, PathBuf};

pub const NEXT_RUN_PROPOSAL_PHASE: &str = "B26.2";
pub const NEXT_RUN_PROPOSAL_KIND: &str = "next-run-proposal";
pub const NEXT_RUN_PROPOSAL_VERSION: &str = "beagle-next-run-proposal-v1";

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
pub struct NextRunProposal {
    pub phase: String,
    pub contract_kind: String,
    pub contract_version: String,
    pub proposal_id: String,
    pub study_id: String,
    pub workstream_id: String,
    pub workspace_id: String,
    pub session_id: String,
    pub same_beagle_owned_identity: bool,
    pub generated_at: DateTime<Utc>,
    pub study_decision_id: String,
    pub study_decision_basis_id: String,
    pub proposed_run_label: String,
    pub proposed_variant_id: String,
    pub proposed_variant_label: String,
    pub proposed_source_run_id: String,
    pub proposed_compute_profile_id: String,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub proposed_recipe_kind: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub proposed_experiment_id: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub proposed_replay_mode: Option<String>,
    pub recommended_action: String,
    pub operator_review_required: bool,
    pub evidence_refs: Vec<StudyEvidenceRef>,
    pub note: String,
}

pub fn build_next_run_proposal(
    study: &StudyRegistry,
    study_decision_id: &str,
    study_decision_basis_id: &str,
    recommended_action: &str,
    proposed_run_label: &str,
    proposed_variant_id: &str,
    proposed_variant_label: &str,
    proposed_source_run_id: &str,
    proposed_compute_profile_id: &str,
    proposed_recipe_kind: Option<&str>,
    proposed_experiment_id: Option<&str>,
    proposed_replay_mode: Option<&str>,
    evidence_refs: Vec<StudyEvidenceRef>,
    generated_at: DateTime<Utc>,
) -> NextRunProposal {
    NextRunProposal {
        phase: NEXT_RUN_PROPOSAL_PHASE.to_string(),
        contract_kind: NEXT_RUN_PROPOSAL_KIND.to_string(),
        contract_version: NEXT_RUN_PROPOSAL_VERSION.to_string(),
        proposal_id: format!("{}-next-run-proposal", sanitize_component(study.study_id.as_str())),
        study_id: study.study_id.clone(),
        workstream_id: study.workstream_id.clone(),
        workspace_id: study.workspace_id.clone(),
        session_id: study.session_id.clone(),
        same_beagle_owned_identity: study.same_beagle_owned_identity,
        generated_at,
        study_decision_id: study_decision_id.to_string(),
        study_decision_basis_id: study_decision_basis_id.to_string(),
        proposed_run_label: proposed_run_label.to_string(),
        proposed_variant_id: proposed_variant_id.to_string(),
        proposed_variant_label: proposed_variant_label.to_string(),
        proposed_source_run_id: proposed_source_run_id.to_string(),
        proposed_compute_profile_id: proposed_compute_profile_id.to_string(),
        proposed_recipe_kind: proposed_recipe_kind.map(ToString::to_string),
        proposed_experiment_id: proposed_experiment_id.map(ToString::to_string),
        proposed_replay_mode: proposed_replay_mode.map(ToString::to_string),
        recommended_action: recommended_action.to_string(),
        operator_review_required: true,
        evidence_refs,
        note: "B26.2 keeps the next-run proposal bounded and operator-visible: reuse the study decision basis, name the candidate variant explicitly, and do not auto-launch the proposal in this phase.".to_string(),
    }
}

pub fn read_next_run_proposal(
    data_dir: &Path,
    workspace_id: &str,
) -> anyhow::Result<Option<NextRunProposal>> {
    read_json(next_run_proposal_path(data_dir, workspace_id))
}

pub(crate) fn write_next_run_proposal(
    data_dir: &Path,
    workspace_id: &str,
    proposal: &NextRunProposal,
) -> anyhow::Result<()> {
    write_json(next_run_proposal_path(data_dir, workspace_id), proposal)
}

fn next_run_proposal_path(data_dir: &Path, workspace_id: &str) -> PathBuf {
    crate::workspace_plane::workspace_plane_dir(data_dir)
        .join("next-run-proposal")
        .join(format!("{}.json", sanitize_component(workspace_id)))
}

fn write_json<T: Serialize>(path: PathBuf, value: &T) -> anyhow::Result<()> {
    if let Some(parent) = path.parent() {
        fs::create_dir_all(parent)
            .with_context(|| format!("failed to create dir {}", parent.display()))?;
    }
    let body = serde_json::to_string_pretty(value)?;
    fs::write(&path, body).with_context(|| format!("failed to write {}", path.display()))
}

fn read_json<T>(path: PathBuf) -> anyhow::Result<Option<T>>
where
    T: for<'de> Deserialize<'de>,
{
    if !path.exists() {
        return Ok(None);
    }
    let body = fs::read_to_string(&path)
        .with_context(|| format!("failed to read {}", path.display()))?;
    let value = serde_json::from_str::<T>(&body)
        .with_context(|| format!("failed to parse {}", path.display()))?;
    Ok(Some(value))
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
