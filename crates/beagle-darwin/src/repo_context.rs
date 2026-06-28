use beagle_config::BeagleConfig;
use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};

fn default_repo_context_source() -> String {
    "workspace_config".to_string()
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct RepoContext {
    #[serde(default)]
    pub canonical_repo: String,
    #[serde(default)]
    pub canonical_branch: String,
    #[serde(default)]
    pub canonical_track: String,
    #[serde(default = "default_repo_context_source")]
    pub source: String,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub attached_at: Option<DateTime<Utc>>,
}

impl Default for RepoContext {
    fn default() -> Self {
        Self {
            canonical_repo: String::new(),
            canonical_branch: String::new(),
            canonical_track: String::new(),
            source: default_repo_context_source(),
            attached_at: None,
        }
    }
}

impl RepoContext {
    pub fn from_workspace_cfg(cfg: &BeagleConfig) -> Self {
        Self {
            canonical_repo: cfg.workspace.canonical_repo.clone(),
            canonical_branch: cfg.workspace.canonical_branch.clone(),
            canonical_track: cfg.workspace.canonical_track.clone(),
            source: default_repo_context_source(),
            attached_at: Some(Utc::now()),
        }
    }

    pub fn is_complete(&self) -> bool {
        !self.canonical_repo.trim().is_empty()
            && !self.canonical_branch.trim().is_empty()
            && !self.canonical_track.trim().is_empty()
    }
}
