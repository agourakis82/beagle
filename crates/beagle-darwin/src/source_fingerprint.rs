use crate::workspace_snapshot::{candidate_lockfile_paths, WorkspaceSnapshot};
use anyhow::{Context, Result};
use serde::{Deserialize, Serialize};
use sha2::{Digest, Sha256};
use std::fs;
use std::path::Path;

const SOURCE_FINGERPRINT_PHASE: &str = "B25.6";
const SOURCE_FINGERPRINT_KIND: &str = "source-fingerprint";
const SOURCE_FINGERPRINT_VERSION: &str = "beagle-source-fingerprint-v1";

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
pub struct LockfileFingerprint {
    pub relative_path: String,
    pub sha256: String,
}

#[derive(Debug, Clone, Serialize, Deserialize, Default)]
pub struct SourceFingerprintCaptureRequest {
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub source_fingerprint: Option<String>,
    #[serde(default)]
    pub lockfile_fingerprints: Vec<LockfileFingerprint>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub note: Option<String>,
}

#[derive(Debug, Clone)]
pub struct SourceFingerprintContext<'a> {
    pub workstream_id: &'a str,
    pub workspace_id: &'a str,
    pub session_id: &'a str,
    pub same_beagle_owned_identity: bool,
    pub selected_subagent_id: &'a str,
    pub run_label: &'a str,
    pub submitted_job_id: u64,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SourceFingerprint {
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
    pub algorithm: String,
    pub source_fingerprint: String,
    #[serde(default)]
    pub lockfile_fingerprints: Vec<LockfileFingerprint>,
    pub capture_kind: String,
    pub note: String,
}

pub fn build_source_fingerprint(
    context: &SourceFingerprintContext<'_>,
    workspace_snapshot: &WorkspaceSnapshot,
    request: Option<&SourceFingerprintCaptureRequest>,
) -> Result<SourceFingerprint> {
    let repo_root_path = workspace_snapshot.repo_root.as_deref().map(Path::new);
    let lockfile_fingerprints = if let Some(requested) = request {
        if !requested.lockfile_fingerprints.is_empty() {
            requested.lockfile_fingerprints.clone()
        } else {
            capture_lockfile_fingerprints(repo_root_path)?
        }
    } else {
        capture_lockfile_fingerprints(repo_root_path)?
    };

    let source_fingerprint = if let Some(requested) = request.and_then(|value| value.source_fingerprint.clone()) {
        requested
    } else {
        hash_source_fingerprint_payload(workspace_snapshot, &lockfile_fingerprints)?
    };

    let capture_kind = match (
        request.and_then(|value| value.source_fingerprint.clone()).is_some(),
        workspace_snapshot.repo_accessible,
    ) {
        (true, true) => "request-attested-source-fingerprint+local-lockfile-fingerprint",
        (true, false) => "request-attested-source-fingerprint",
        (false, true) => "local-source-fingerprint",
        (false, false) => "opaque-source-fingerprint",
    }
    .to_string();

    let note = request
        .and_then(|value| value.note.clone())
        .unwrap_or_else(|| {
            "B25.6 computes a stable source fingerprint from the Git-aware workspace snapshot plus lockfile fingerprints, or preserves a bounded workspace-provided attestation when the runtime cannot see the checkout directly.".to_string()
        });

    Ok(SourceFingerprint {
        phase: SOURCE_FINGERPRINT_PHASE.to_string(),
        contract_kind: SOURCE_FINGERPRINT_KIND.to_string(),
        contract_version: SOURCE_FINGERPRINT_VERSION.to_string(),
        workstream_id: context.workstream_id.to_string(),
        workspace_id: context.workspace_id.to_string(),
        session_id: context.session_id.to_string(),
        same_beagle_owned_identity: context.same_beagle_owned_identity,
        selected_subagent_id: context.selected_subagent_id.to_string(),
        run_label: context.run_label.to_string(),
        submitted_job_id: context.submitted_job_id,
        repo_root: workspace_snapshot.repo_root.clone(),
        algorithm: "sha256".to_string(),
        source_fingerprint,
        lockfile_fingerprints,
        capture_kind,
        note,
    })
}

pub fn hash_source_fingerprint_payload(
    workspace_snapshot: &WorkspaceSnapshot,
    lockfile_fingerprints: &[LockfileFingerprint],
) -> Result<String> {
    let payload = serde_json::json!({
        "repo_root": workspace_snapshot.repo_root,
        "branch": workspace_snapshot.branch,
        "commit": workspace_snapshot.commit,
        "tree_ish": workspace_snapshot.tree_ish,
        "dirty_state": workspace_snapshot.dirty_state,
        "patch_ref": workspace_snapshot.patch_ref,
        "lockfile_fingerprints": lockfile_fingerprints,
    });
    let bytes = serde_json::to_vec(&payload)?;
    let mut hasher = Sha256::new();
    hasher.update(bytes);
    Ok(format!("{:x}", hasher.finalize()))
}

pub fn capture_lockfile_fingerprints(
    repo_root: Option<&Path>,
) -> Result<Vec<LockfileFingerprint>> {
    let Some(repo_root) = repo_root else {
        return Ok(Vec::new());
    };
    let mut fingerprints = Vec::new();
    for path in candidate_lockfile_paths(repo_root) {
        let relative_path = path
            .strip_prefix(repo_root)
            .unwrap_or(&path)
            .to_string_lossy()
            .to_string();
        let body = fs::read(&path)
            .with_context(|| format!("failed to read lockfile {}", path.display()))?;
        let mut hasher = Sha256::new();
        hasher.update(body);
        fingerprints.push(LockfileFingerprint {
            relative_path,
            sha256: format!("{:x}", hasher.finalize()),
        });
    }
    fingerprints.sort_by(|left, right| left.relative_path.cmp(&right.relative_path));
    Ok(fingerprints)
}
