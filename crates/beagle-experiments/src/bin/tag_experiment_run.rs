//! CLI para marcar um run_id com tag experimental
//!
//! Uso:
//!   tag_experiment_run <experiment_id> <run_id> <condition> [notes...]

use beagle_config::{beagle_data_dir, load as load_config};
use beagle_experiments::{append_experiment_tag, ExperimentRunTag};
use chrono::Utc;
use clap::Parser;
use std::path::PathBuf;
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

    // Carrega config atual para snapshot de flags
    let cfg = load_config();

    // Tenta inferir flags do run_report.json (mais preciso)
    let (triad_enabled, hrv_aware, serendipity_enabled, space_aware) =
        infer_flags_from_run_report(&data_dir, &args.run_id).unwrap_or_else(|| {
            // Fallback: usa config atual se run_report não existir
            (
                false, // triad_enabled: precisa inferir de run_report ou assumir false
                true,  // hrv_aware: assume true se observer está configurado
                cfg.serendipity_enabled(),
                false, // space_aware: assume false por padrão
            )
        });

    let tag = ExperimentRunTag {
        experiment_id: args.experiment_id.clone(),
        run_id: args.run_id.clone(),
        condition: args.condition.clone(),
        timestamp: Utc::now(),
        notes,
        triad_enabled,
        hrv_aware,
        serendipity_enabled,
        space_aware,
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

/// Infere flags experimentais do run_report.json (mais preciso que config atual)
fn infer_flags_from_run_report(
    data_dir: &PathBuf,
    run_id: &str,
) -> Option<(bool, bool, bool, bool)> {
    // Procura run_report.json em logs/beagle-pipeline/
    let report_dir = data_dir.join("logs").join("beagle-pipeline");
    if !report_dir.exists() {
        return None;
    }

    // Procura arquivo *_{run_id}.json
    if let Ok(entries) = std::fs::read_dir(&report_dir) {
        for entry in entries.flatten() {
            if let Some(name) = entry.file_name().to_str() {
                if name.ends_with(&format!("_{}.json", run_id)) {
                    if let Ok(content) = std::fs::read_to_string(entry.path()) {
                        if let Ok(report) = serde_json::from_str::<serde_json::Value>(&content) {
                            // Infere triad_enabled: se há triad_report_json ou draft_reviewed.md
                            let triad_enabled = report.get("triad_report_json").is_some()
                                || data_dir
                                    .join("triad")
                                    .join(run_id)
                                    .join("draft_reviewed.md")
                                    .exists();

                            // Infere hrv_aware: se há observer.physio_severity no report
                            let hrv_aware = report
                                .get("observer")
                                .and_then(|o| o.get("physio_severity"))
                                .is_some();

                            // Infere serendipity_enabled: do report se disponível, senão assume false
                            let serendipity_enabled = report.get("serendipity_score").is_some()
                                || report.get("serendipity_accidents").is_some();

                            // Infere space_aware: se há observer.space no report
                            let space_aware = report
                                .get("observer")
                                .and_then(|o| o.get("space_severity"))
                                .and_then(|s| s.as_str())
                                .map(|s| s != "Normal")
                                .unwrap_or(false);

                            return Some((
                                triad_enabled,
                                hrv_aware,
                                serendipity_enabled,
                                space_aware,
                            ));
                        }
                    }
                }
            }
        }
    }

    None
}
