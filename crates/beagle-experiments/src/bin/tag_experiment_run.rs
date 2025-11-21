//! CLI para marcar um run_id com tag experimental
//!
//! Uso:
//!   tag_experiment_run <experiment_id> <run_id> <condition> [notes...]

use beagle_experiments::{append_experiment_tag, ExperimentRunTag};
use beagle_config::beagle_data_dir;
use chrono::Utc;
use clap::Parser;
use tracing::info;

#[derive(Parser)]
#[command(name = "tag_experiment_run", version)]
struct Cli {
    /// ID do experimento (ex.: "triad_vs_ensemble", "hrv_aware_vs_blind")
    experiment_id: String,
    
    /// ID do run a ser marcado
    run_id: String,
    
    /// Condição experimental (ex.: "triad", "ensemble", "hrv_aware", "hrv_blind")
    condition: String,
    
    /// Notas adicionais (opcional)
    notes: Vec<String>,
}

fn main() -> anyhow::Result<()> {
    tracing_subscriber::fmt()
        .with_env_filter(tracing_subscriber::EnvFilter::from_default_env())
        .init();
    
    let args = Cli::parse();
    
    let data_dir = beagle_data_dir();
    std::fs::create_dir_all(&data_dir)?;
    
    let notes = if args.notes.is_empty() {
        None
    } else {
        Some(args.notes.join(" "))
    };
    
    let tag = ExperimentRunTag {
        experiment_id: args.experiment_id.clone(),
        run_id: args.run_id.clone(),
        condition: args.condition.clone(),
        timestamp: Utc::now(),
        notes,
    };
    
    append_experiment_tag(&data_dir, &tag)?;
    
    info!("✅ Tag experimental anexada:");
    info!("   Experiment ID: {}", tag.experiment_id);
    info!("   Run ID: {}", tag.run_id);
    info!("   Condition: {}", tag.condition);
    if let Some(ref notes) = tag.notes {
        info!("   Notes: {}", notes);
    }
    
    println!("✅ Tag experimental anexada com sucesso!");
    
    Ok(())
}

