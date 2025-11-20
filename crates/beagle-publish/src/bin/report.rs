use beagle_publish::run_log::{logs_dir, RunMetadata};
use std::fs;

fn main() -> anyhow::Result<()> {
    let limit: usize = std::env::args()
        .nth(1)
        .and_then(|v| v.parse().ok())
        .unwrap_or(10);

    let dir = logs_dir();
    if !dir.exists() {
        println!("Nenhum log encontrado em {:?}", dir);
        return Ok(());
    }

    let mut entries: Vec<_> = fs::read_dir(&dir)?
        .filter_map(|e| e.ok())
        .filter(|e| e.path().extension().and_then(|v| v.to_str()) == Some("json"))
        .collect();

    // Ordena por nome (timestamp + run_id)
    entries.sort_by_key(|e| e.file_name());

    for entry in entries.into_iter().rev().take(limit) {
        let path = entry.path();
        let data = fs::read_to_string(&path)?;
        let meta: RunMetadata = serde_json::from_str(&data)?;

        println!("{}", "─".repeat(80));
        println!("Run: {}", meta.run_id);
        println!("Time: {}", meta.timestamp_utc);
        println!("Component: {}", meta.component);
        println!("Target: {}", meta.target);
        println!("Paper: {}", meta.paper_title);
        println!("Mode: {} (SAFE_MODE={})", meta.publish_mode, meta.safe_mode);
        println!("DryRun: {}", meta.dry_run);
        if let Some(ref gc) = meta.git_commit {
            println!("Commit: {}", gc);
        }
        if let Some(ref notes) = meta.notes {
            println!("Notes: {}", notes);
        }
        println!("File: {:?}", path);
    }

    Ok(())
}
