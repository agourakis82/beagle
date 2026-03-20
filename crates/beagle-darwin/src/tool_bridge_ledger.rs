use crate::tool_bridge_types::{BridgeKind, BridgeMode, BridgeProvider, BridgeTokenUsage};
use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};
use std::collections::VecDeque;
use std::fs::OpenOptions;
use std::io::Write;
use std::path::{Path, PathBuf};

const TOOL_BRIDGE_DIR: &str = "tool-bridge";
const TOOL_BRIDGE_LEDGER_FILE: &str = "tool_bridge_events.jsonl";

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct BridgeLedgerEntry {
    pub request_id: String,
    pub timestamp: DateTime<Utc>,
    pub bridge_kind: BridgeKind,
    pub bridge_mode: BridgeMode,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub provider: Option<BridgeProvider>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub model: Option<String>,
    pub task_type: String,
    pub latency_ms: u128,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub token_usage: Option<BridgeTokenUsage>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub estimated_cost_usd: Option<f64>,
    pub success: bool,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub error: Option<String>,
}

pub fn ledger_dir(data_dir: &Path) -> PathBuf {
    data_dir.join(TOOL_BRIDGE_DIR)
}

pub fn ledger_file_path(data_dir: &Path) -> PathBuf {
    ledger_dir(data_dir).join(TOOL_BRIDGE_LEDGER_FILE)
}

pub fn append_ledger_entry(data_dir: &Path, entry: &BridgeLedgerEntry) -> anyhow::Result<()> {
    let dir = ledger_dir(data_dir);
    std::fs::create_dir_all(&dir)?;

    let path = ledger_file_path(data_dir);
    let mut file = OpenOptions::new().create(true).append(true).open(path)?;
    writeln!(file, "{}", serde_json::to_string(entry)?)?;

    Ok(())
}

pub fn read_recent_ledger_entries(
    data_dir: &Path,
    limit: usize,
) -> anyhow::Result<Vec<BridgeLedgerEntry>> {
    if limit == 0 {
        return Ok(Vec::new());
    }

    let path = ledger_file_path(data_dir);
    if !path.exists() {
        return Ok(Vec::new());
    }

    let content = std::fs::read_to_string(path)?;
    let mut entries = VecDeque::with_capacity(limit);

    for line in content.lines().filter(|line| !line.trim().is_empty()) {
        let entry: BridgeLedgerEntry = serde_json::from_str(line)?;
        if entries.len() == limit {
            entries.pop_front();
        }
        entries.push_back(entry);
    }

    Ok(entries.into_iter().collect())
}
