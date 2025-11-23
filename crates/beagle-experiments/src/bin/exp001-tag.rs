//! CLI para marcar runs da Expedition 001 com feedback humano
//!
//! Uso:
//!   exp001-tag --run-id <run_id> --accepted <true|false> --rating <0-10> [--notes "..."]

use anyhow::Result;
use beagle_config::load as load_config;
use beagle_experiments::exp001::EXPEDITION_001_ID;
use beagle_feedback::{append_event, create_human_feedback_event};
use clap::Parser;
use std::path::PathBuf;

#[derive(Parser)]
#[command(name = "exp001-tag", version)]
struct Cli {
    /// ID da Expedição (default: beagle_exp_001_triad_vs_single)
    #[arg(long, default_value = EXPEDITION_001_ID)]
    experiment_id: String,

    /// run_id a ser marcado
    #[arg(long)]
    run_id: String,

    /// Aceito? (true/false)
    #[arg(long)]
    accepted: bool,

    /// Nota 0-10
    #[arg(long)]
    rating: u8,

    /// Comentário opcional
    #[arg(long)]
    notes: Option<String>,
}

fn main() -> Result<()> {
    tracing_subscriber::fmt()
        .with_env_filter(tracing_subscriber::EnvFilter::from_default_env())
        .init();

    let args = Cli::parse();

    // Valida rating
    if args.rating > 10 {
        anyhow::bail!("Rating deve estar entre 0 e 10, mas recebeu: {}", args.rating);
    }

    let cfg = load_config();
    let data_dir = PathBuf::from(&cfg.storage.data_dir);

    // Registra feedback humano via beagle-feedback
    let human_event = create_human_feedback_event(
        args.run_id.clone(),
        args.accepted,
        Some(args.rating),
        args.notes.clone(),
    );

    append_event(&data_dir, &human_event)?;

    println!("✅ Feedback humano registrado para Expedition 001");
    println!("   Experiment ID: {}", args.experiment_id);
    println!("   Run ID: {}", args.run_id);
    println!("   Accepted: {}", args.accepted);
    println!("   Rating: {}/10", args.rating);
    if let Some(ref n) = args.notes {
        println!("   Notes: {}", n);
    }
    println!();
    println!("💡 O run_id foi marcado com feedback. Use 'exp001-analyze' para ver estatísticas.");

    Ok(())
}

