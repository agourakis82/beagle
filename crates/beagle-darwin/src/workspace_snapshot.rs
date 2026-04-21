use anyhow::Result;
use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};
use sha2::{Digest, Sha256};
use std::path::{Path, PathBuf};
use std::process::Command;

const WORKSPACE_SNAPSHOT_PHASE: &str = "B25.6";
const WORKSPACE_SNAPSHOT_KIND: &str = "workspace-snapshot";
const WORKSPACE_SNAPSHOT_VERSION: &str = "beagle-workspace-snapshot-v1";

#[derive(Debug, Clone, Serialize, Deserialize, Default)]
pub struct WorkspaceSnapshotCaptureRequest {
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub repo_root: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub branch: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub commit: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub tree_ish: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub dirty_state: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub patch_ref: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub note: Option<String>,
}

#[derive(Debug, Clone)]
pub struct WorkspaceSnapshotContext<'a> {
    pub workstream_id: &'a str,
    pub workspace_id: &'a str,
    pub session_id: &'a str,
    pub same_beagle_owned_identity: bool,
    pub selected_subagent_id: &'a str,
    pub workspace_root: &'a str,
    pub run_label: &'a str,
    pub submitted_job_id: u64,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct WorkspaceSnapshot {
    pub phase: String,
    pub contract_kind: String,
    pub contract_version: String,
    pub workstream_id: String,
    pub workspace_id: String,
    pub session_id: String,
    pub same_beagle_owned_identity: bool,
    pub selected_subagent_id: String,
    pub workspace_root: String,
    pub run_label: String,
    pub submitted_job_id: u64,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub repo_root: Option<String>,
    pub repo_accessible: bool,
    pub capture_kind: String,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub branch: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub commit: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub tree_ish: Option<String>,
    pub dirty_state: String,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub patch_ref: Option<String>,
    pub captured_at: DateTime<Utc>,
    pub note: String,
}

#[derive(Debug, Clone)]
pub struct LocalGitSnapshot {
    pub repo_root: String,
    pub branch: Option<String>,
    pub commit: Option<String>,
    pub tree_ish: Option<String>,
    pub dirty_state: String,
    pub patch_ref: Option<String>,
}

pub fn capture_workspace_snapshot(
    context: &WorkspaceSnapshotContext<'_>,
    request: Option<&WorkspaceSnapshotCaptureRequest>,
) -> Result<WorkspaceSnapshot> {
    let local = detect_local_git_snapshot(context.workspace_root, request);
    let repo_root = request
        .and_then(|value| value.repo_root.clone())
        .or_else(|| local.as_ref().map(|value| value.repo_root.clone()));
    let repo_accessible = local.is_some();

    let branch = request
        .and_then(|value| value.branch.clone())
        .or_else(|| local.as_ref().and_then(|value| value.branch.clone()));
    let commit = request
        .and_then(|value| value.commit.clone())
        .or_else(|| local.as_ref().and_then(|value| value.commit.clone()));
    let tree_ish = request
        .and_then(|value| value.tree_ish.clone())
        .or_else(|| local.as_ref().and_then(|value| value.tree_ish.clone()));
    let dirty_state = request
        .and_then(|value| value.dirty_state.as_deref())
        .map(normalize_dirty_state)
        .unwrap_or_else(|| {
            local
                .as_ref()
                .map(|value| value.dirty_state.clone())
                .unwrap_or_else(|| "unknown".to_string())
        });
    let patch_ref = request
        .and_then(|value| value.patch_ref.clone())
        .or_else(|| local.as_ref().and_then(|value| value.patch_ref.clone()));

    let capture_kind = match (request.is_some(), repo_accessible) {
        (true, true) => "request-attested-git-snapshot+local-verification",
        (true, false) => "request-attested-git-snapshot",
        (false, true) => "local-git-snapshot",
        (false, false) => "git-snapshot-unavailable",
    }
    .to_string();

    let note = request
        .and_then(|value| value.note.clone())
        .unwrap_or_else(|| {
            if repo_accessible {
                "B25.6 captures a Git-aware workspace snapshot from the live workspace when available and accepts a bounded workspace-provided attestation when the runtime cannot see the checkout directly.".to_string()
            } else {
                "B25.6 records the workspace-attested Git snapshot when the runtime cannot access the checkout directly, instead of guessing branch or commit state.".to_string()
            }
        });

    Ok(WorkspaceSnapshot {
        phase: WORKSPACE_SNAPSHOT_PHASE.to_string(),
        contract_kind: WORKSPACE_SNAPSHOT_KIND.to_string(),
        contract_version: WORKSPACE_SNAPSHOT_VERSION.to_string(),
        workstream_id: context.workstream_id.to_string(),
        workspace_id: context.workspace_id.to_string(),
        session_id: context.session_id.to_string(),
        same_beagle_owned_identity: context.same_beagle_owned_identity,
        selected_subagent_id: context.selected_subagent_id.to_string(),
        workspace_root: context.workspace_root.to_string(),
        run_label: context.run_label.to_string(),
        submitted_job_id: context.submitted_job_id,
        repo_root,
        repo_accessible,
        capture_kind,
        branch,
        commit,
        tree_ish,
        dirty_state,
        patch_ref,
        captured_at: Utc::now(),
        note,
    })
}

pub fn normalize_dirty_state(value: &str) -> String {
    match value.trim().to_ascii_lowercase().as_str() {
        "clean" | "false" | "0" => "clean".to_string(),
        "dirty" | "true" | "1" => "dirty".to_string(),
        _ => "unknown".to_string(),
    }
}

pub fn dirty_state_to_bool(value: &str) -> Option<bool> {
    match normalize_dirty_state(value).as_str() {
        "clean" => Some(false),
        "dirty" => Some(true),
        _ => None,
    }
}

pub fn detect_local_git_snapshot(
    workspace_root: &str,
    request: Option<&WorkspaceSnapshotCaptureRequest>,
) -> Option<LocalGitSnapshot> {
    let mut candidates = Vec::new();
    if let Some(repo_root) = request.and_then(|value| value.repo_root.clone()) {
        candidates.push(repo_root);
    }
    if !workspace_root.trim().is_empty() {
        candidates.push(workspace_root.trim().to_string());
    }
    if let Ok(repo_root) = std::env::var("BEAGLE_REPO_ROOT") {
        if !repo_root.trim().is_empty() {
            candidates.push(repo_root);
        }
    }
    candidates.push("/workspace/beagle".to_string());
    candidates.push("/home/devsounio/beagle".to_string());
    if let Ok(current_dir) = std::env::current_dir() {
        if let Some(path) = current_dir.to_str() {
            candidates.push(path.to_string());
        }
    }

    for candidate in candidates {
        let Some(repo_root) = git_command_in(&candidate, &["rev-parse", "--show-toplevel"]) else {
            continue;
        };
        let branch = git_command_in(&repo_root, &["rev-parse", "--abbrev-ref", "HEAD"]);
        let commit = git_command_in(&repo_root, &["rev-parse", "HEAD"]);
        let tree_ish = git_command_in(&repo_root, &["rev-parse", "HEAD^{tree}"]);
        let dirty_state = git_dirty_state_in(&repo_root);
        let patch_ref = if dirty_state == "dirty" {
            git_diff_patch_ref_in(&repo_root)
        } else {
            None
        };
        return Some(LocalGitSnapshot {
            repo_root,
            branch,
            commit,
            tree_ish,
            dirty_state,
            patch_ref,
        });
    }
    None
}

pub fn git_command_in(repo_root: &str, args: &[&str]) -> Option<String> {
    let output = Command::new("git")
        .arg("-C")
        .arg(repo_root)
        .args(args)
        .output()
        .ok()?;
    if !output.status.success() {
        return None;
    }
    let text = String::from_utf8_lossy(&output.stdout).trim().to_string();
    if text.is_empty() {
        None
    } else {
        Some(text)
    }
}

pub fn git_dirty_state_in(repo_root: &str) -> String {
    let Some(output) = Command::new("git")
        .arg("-C")
        .arg(repo_root)
        .args(["status", "--porcelain", "--untracked-files=no"])
        .output()
        .ok() else {
        return "unknown".to_string();
    };
    if !output.status.success() {
        return "unknown".to_string();
    }
    if String::from_utf8_lossy(&output.stdout).trim().is_empty() {
        "clean".to_string()
    } else {
        "dirty".to_string()
    }
}

pub fn git_diff_patch_ref_in(repo_root: &str) -> Option<String> {
    let output = Command::new("git")
        .arg("-C")
        .arg(repo_root)
        .args(["diff", "--no-ext-diff", "--binary", "HEAD", "--"])
        .output()
        .ok()?;
    if !output.status.success() {
        return None;
    }
    let bytes = output.stdout;
    if bytes.is_empty() {
        return None;
    }
    let mut hasher = Sha256::new();
    hasher.update(bytes);
    Some(format!("patch-sha256:{:x}", hasher.finalize()))
}

pub fn candidate_lockfile_paths(repo_root: &Path) -> Vec<PathBuf> {
    [
        "Cargo.lock",
        "package-lock.json",
        "pnpm-lock.yaml",
        "yarn.lock",
        "bun.lockb",
        "uv.lock",
        "poetry.lock",
        "Manifest.toml",
    ]
    .into_iter()
    .map(|relative| repo_root.join(relative))
    .filter(|path| path.exists())
    .collect()
}
