use anyhow::{Context, Result};
use std::path::Path;
use std::process::Command;

fn base_git_command(repo_path: &Path) -> Command {
    let mut cmd = Command::new("git");
    cmd.arg("-C").arg(repo_path);
    cmd.env("GIT_TERMINAL_PROMPT", "0");
    cmd
}

fn non_interactive_ssh_env(cmd: &mut Command) {
    // Prevent hanging on passphrase/password prompts.
    cmd.env(
        "GIT_SSH_COMMAND",
        "ssh -o BatchMode=yes -o StrictHostKeyChecking=accept-new -o ConnectTimeout=10",
    );
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
pub enum ChangeKind {
    Added,
    Modified,
    Deleted,
    Renamed,
}

#[derive(Debug, Clone)]
pub struct FileChange {
    pub kind: ChangeKind,
    pub path: String,
    pub old_path: Option<String>,
}

pub fn head_commit(repo_path: &Path) -> Result<String> {
    let out = base_git_command(repo_path)
        .args(["rev-parse", "HEAD"])
        .output()
        .context("failed to run git rev-parse")?;
    if !out.status.success() {
        anyhow::bail!(
            "git rev-parse failed: {}",
            String::from_utf8_lossy(&out.stderr)
        );
    }
    Ok(String::from_utf8_lossy(&out.stdout).trim().to_string())
}

pub fn is_git_repo(repo_path: &Path) -> bool {
    repo_path.join(".git").exists()
}

pub fn pull_ff_only(repo_path: &Path) -> Result<()> {
    let mut cmd = base_git_command(repo_path);
    non_interactive_ssh_env(&mut cmd);

    let out = cmd
        .args(["pull", "--ff-only", "--quiet"])
        .output()
        .context("failed to run git pull")?;
    if !out.status.success() {
        anyhow::bail!("git pull failed: {}", String::from_utf8_lossy(&out.stderr));
    }
    Ok(())
}

pub fn clone_repo(repo_url: &str, dest: &Path) -> Result<()> {
    if let Some(parent) = dest.parent() {
        std::fs::create_dir_all(parent).context("failed to create repos dir")?;
    }
    let mut cmd = Command::new("git");
    cmd.env("GIT_TERMINAL_PROMPT", "0");
    non_interactive_ssh_env(&mut cmd);
    let out = cmd
        .args(["clone", "--quiet", repo_url])
        .arg(dest)
        .output()
        .context("failed to run git clone")?;
    if !out.status.success() {
        anyhow::bail!("git clone failed: {}", String::from_utf8_lossy(&out.stderr));
    }
    Ok(())
}

pub fn diff_name_status(repo_path: &Path, from: &str, to: &str) -> Result<Vec<FileChange>> {
    let out = base_git_command(repo_path)
        .args(["diff", "--name-status", &format!("{from}..{to}")])
        .output()
        .context("failed to run git diff --name-status")?;
    if !out.status.success() {
        anyhow::bail!(
            "git diff failed: {}",
            String::from_utf8_lossy(&out.stderr)
        );
    }

    let stdout = String::from_utf8_lossy(&out.stdout);
    let mut changes = Vec::new();
    for line in stdout.lines() {
        let parts: Vec<&str> = line.split('\t').collect();
        if parts.is_empty() {
            continue;
        }
        let status = parts[0];
        match status.chars().next().unwrap_or('?') {
            'A' => {
                if let Some(path) = parts.get(1) {
                    changes.push(FileChange {
                        kind: ChangeKind::Added,
                        path: (*path).to_string(),
                        old_path: None,
                    });
                }
            }
            'M' => {
                if let Some(path) = parts.get(1) {
                    changes.push(FileChange {
                        kind: ChangeKind::Modified,
                        path: (*path).to_string(),
                        old_path: None,
                    });
                }
            }
            'D' => {
                if let Some(path) = parts.get(1) {
                    changes.push(FileChange {
                        kind: ChangeKind::Deleted,
                        path: (*path).to_string(),
                        old_path: None,
                    });
                }
            }
            'R'
                // R<score>\told\tnew
                if parts.len() >= 3 => {
                    changes.push(FileChange {
                        kind: ChangeKind::Renamed,
                        path: parts[2].to_string(),
                        old_path: Some(parts[1].to_string()),
                    });
                }
            _ => {}
        }
    }
    Ok(changes)
}
