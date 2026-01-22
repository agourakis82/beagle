use anyhow::{Context, Result};
use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};
use std::collections::HashMap;
use std::fs;
use std::path::Path;

#[derive(Debug, Clone, Serialize, Deserialize, Default)]
pub struct IndexState {
    pub last_run: Option<DateTime<Utc>>,
    pub repos: HashMap<String, RepoState>,
}

#[derive(Debug, Clone, Serialize, Deserialize, Default)]
pub struct RepoState {
    pub head: Option<String>,
    pub last_indexed_at: Option<DateTime<Utc>>,
}

impl IndexState {
    pub fn load(path: &Path) -> Result<Self> {
        if !path.exists() {
            return Ok(Self::default());
        }
        let content = fs::read_to_string(path).context("failed to read state file")?;
        let state: Self = serde_json::from_str(&content).context("failed to parse state JSON")?;
        Ok(state)
    }

    pub fn save(&self, path: &Path) -> Result<()> {
        if let Some(parent) = path.parent() {
            fs::create_dir_all(parent).context("failed to create state directory")?;
        }
        let json = serde_json::to_string_pretty(self).context("failed to serialize state")?;
        fs::write(path, json).context("failed to write state file")?;
        Ok(())
    }
}

