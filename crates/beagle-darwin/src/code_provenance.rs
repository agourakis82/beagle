use crate::source_fingerprint::{
    build_source_fingerprint, LockfileFingerprint, SourceFingerprint,
    SourceFingerprintCaptureRequest, SourceFingerprintContext,
};
use crate::workspace_snapshot::{
    capture_workspace_snapshot, WorkspaceSnapshot, WorkspaceSnapshotCaptureRequest,
    WorkspaceSnapshotContext,
};
use anyhow::Result;
use serde::{Deserialize, Serialize};
const CODE_PROVENANCE_PHASE: &str = "B25.6";
const CODE_PROVENANCE_KIND: &str = "code-provenance";
const CODE_PROVENANCE_VERSION: &str = "beagle-code-provenance-v1";

#[derive(Debug, Clone, Serialize, Deserialize, Default)]
pub struct CodeProvenanceCaptureRequest {
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub workspace_snapshot: Option<WorkspaceSnapshotCaptureRequest>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub source_fingerprint: Option<SourceFingerprintCaptureRequest>,
}

#[derive(Debug, Clone)]
pub struct CodeProvenanceContext<'a> {
    pub workstream_id: &'a str,
    pub workspace_id: &'a str,
    pub session_id: &'a str,
    pub same_beagle_owned_identity: bool,
    pub selected_subagent_id: &'a str,
    pub workspace_root: &'a str,
    pub run_label: &'a str,
    pub submitted_job_id: u64,
    pub image_reference: Option<String>,
    pub image_digest: Option<String>,
    pub artifact_manifest_key: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct CodeProvenance {
    pub phase: String,
    pub contract_kind: String,
    pub contract_version: String,
    pub workstream_id: String,
    pub workspace_id: String,
    pub session_id: String,
    pub same_beagle_owned_identity: bool,
    pub selected_subagent_id: String,
    pub run_label: String,
    pub submitted_job_id: u64,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub repo_root: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub branch: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub commit: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub tree_ish: Option<String>,
    pub dirty_state: String,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub patch_ref: Option<String>,
    pub source_fingerprint: String,
    #[serde(default)]
    pub lockfile_fingerprints: Vec<LockfileFingerprint>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub image_reference: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub image_digest: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub artifact_manifest_key: Option<String>,
    pub capture_kind: String,
    pub note: String,
}

#[derive(Debug, Clone)]
pub struct CodeProvenanceBundle {
    pub code_provenance: CodeProvenance,
    pub workspace_snapshot: WorkspaceSnapshot,
    pub source_fingerprint: SourceFingerprint,
}

pub fn capture_code_provenance(
    context: &CodeProvenanceContext<'_>,
    request: Option<&CodeProvenanceCaptureRequest>,
) -> Result<CodeProvenanceBundle> {
    let workspace_snapshot = capture_workspace_snapshot(
        &WorkspaceSnapshotContext {
            workstream_id: context.workstream_id,
            workspace_id: context.workspace_id,
            session_id: context.session_id,
            same_beagle_owned_identity: context.same_beagle_owned_identity,
            selected_subagent_id: context.selected_subagent_id,
            workspace_root: context.workspace_root,
            run_label: context.run_label,
            submitted_job_id: context.submitted_job_id,
        },
        request.and_then(|value| value.workspace_snapshot.as_ref()),
    )?;

    let source_fingerprint = build_source_fingerprint(
        &SourceFingerprintContext {
            workstream_id: context.workstream_id,
            workspace_id: context.workspace_id,
            session_id: context.session_id,
            same_beagle_owned_identity: context.same_beagle_owned_identity,
            selected_subagent_id: context.selected_subagent_id,
            run_label: context.run_label,
            submitted_job_id: context.submitted_job_id,
        },
        &workspace_snapshot,
        request.and_then(|value| value.source_fingerprint.as_ref()),
    )?;

    let capture_kind = format!(
        "{}+{}",
        workspace_snapshot.capture_kind, source_fingerprint.capture_kind
    );
    let note = format!(
        "B25.6 binds Git-aware workspace snapshot data and source fingerprint data to run {} without introducing a second provenance plane.",
        context.run_label
    );

    Ok(CodeProvenanceBundle {
        code_provenance: CodeProvenance {
            phase: CODE_PROVENANCE_PHASE.to_string(),
            contract_kind: CODE_PROVENANCE_KIND.to_string(),
            contract_version: CODE_PROVENANCE_VERSION.to_string(),
            workstream_id: context.workstream_id.to_string(),
            workspace_id: context.workspace_id.to_string(),
            session_id: context.session_id.to_string(),
            same_beagle_owned_identity: context.same_beagle_owned_identity,
            selected_subagent_id: context.selected_subagent_id.to_string(),
            run_label: context.run_label.to_string(),
            submitted_job_id: context.submitted_job_id,
            repo_root: workspace_snapshot.repo_root.clone(),
            branch: workspace_snapshot.branch.clone(),
            commit: workspace_snapshot.commit.clone(),
            tree_ish: workspace_snapshot.tree_ish.clone(),
            dirty_state: workspace_snapshot.dirty_state.clone(),
            patch_ref: workspace_snapshot.patch_ref.clone(),
            source_fingerprint: source_fingerprint.source_fingerprint.clone(),
            lockfile_fingerprints: source_fingerprint.lockfile_fingerprints.clone(),
            image_reference: context.image_reference.clone(),
            image_digest: context.image_digest.clone(),
            artifact_manifest_key: context.artifact_manifest_key.clone(),
            capture_kind,
            note,
        },
        workspace_snapshot,
        source_fingerprint,
    })
}
