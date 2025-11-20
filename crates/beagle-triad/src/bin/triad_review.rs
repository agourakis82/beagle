//! Binário CLI para revisão Triad
//!
//! Uso:
//!   cargo run --bin triad-review --package beagle-triad -- <run_id>

use beagle_core::BeagleContext;
use beagle_config::load as load_config;
use beagle_triad::{run_triad, TriadInput};
use std::path::PathBuf;
use tracing::info;

#[tokio::main]
async fn main() -> anyhow::Result<()> {
    tracing_subscriber::fmt()
        .with_env_filter(tracing_subscriber::EnvFilter::from_default_env())
        .init();

    let run_id = std::env::args()
        .nth(1)
        .ok_or_else(|| anyhow::anyhow!("Forneça o run_id como argumento"))?;

    info!("🔍 Iniciando Triad review para run_id: {}", run_id);

    let cfg = load_config();
    let data_root = PathBuf::from(&cfg.storage.data_dir);
    
    // Localiza draft
    let drafts_dir = data_root.join("papers").join("drafts");
    
    // Procura por arquivo com run_id no nome
    let mut draft_path = None;
    if let Ok(entries) = std::fs::read_dir(&drafts_dir) {
        for entry in entries {
            if let Ok(entry) = entry {
                let path = entry.path();
                if path.to_string_lossy().contains(&run_id) && path.extension() == Some(std::ffi::OsStr::new("md")) {
                    draft_path = Some(path);
                    break;
                }
            }
        }
    }
    
    let draft_path = draft_path
        .ok_or_else(|| anyhow::anyhow!("Draft não encontrado para run_id: {}", run_id))?;

    // Lê context_summary do run_report (simplificado - em produção, parsear JSON)
    let context_summary = format!("Contexto do run {}", run_id);

    let mut ctx = BeagleContext::new(cfg).await?;
    
    let input = TriadInput {
        run_id: run_id.clone(),
        draft_path,
        context_summary,
    };

    let report = run_triad(input, &mut ctx).await?;

    // Salva artefatos
    let output_dir = data_root.join("papers").join("triad");
    std::fs::create_dir_all(&output_dir)?;

    let reviewed_path = output_dir.join(format!("{}_reviewed.md", run_id));
    let report_path = output_dir.join(format!("{}_triad_report.json", run_id));

    std::fs::write(&reviewed_path, &report.final_draft)?;
    std::fs::write(&report_path, serde_json::to_string_pretty(&report)?)?;

    println!("\n=== BEAGLE TRIAD REVIEW CONCLUÍDO ===");
    println!("Run ID: {}", run_id);
    println!("Draft revisado: {}", reviewed_path.display());
    println!("Relatório Triad: {}", report_path.display());
    println!("\nOpiniões:");
    for opinion in &report.opinions {
        println!("  {}: Score {:.2}", opinion.agent, opinion.score);
    }

    Ok(())
}

