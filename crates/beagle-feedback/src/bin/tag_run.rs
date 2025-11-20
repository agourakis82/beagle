//! CLI para marcar runs como bons/ruins
//!
//! Uso:
//!   cargo run --bin tag-run --package beagle-feedback -- <run_id> <accepted 0/1> [rating0-10] [notes...]

use beagle_config::load as load_config;
use beagle_feedback::{append_event, create_human_feedback_event};
use std::path::PathBuf;

fn main() -> anyhow::Result<()> {
    let args: Vec<String> = std::env::args().collect();
    
    if args.len() < 3 {
        eprintln!("Uso: tag-run <run_id> <accepted 0/1> [rating0-10] [notes...]");
        eprintln!();
        eprintln!("Exemplos:");
        eprintln!("  tag-run abc123 1 9 \"ótimo texto para introdução\"");
        eprintln!("  tag-run abc123 0 3");
        std::process::exit(1);
    }

    let run_id = &args[1];
    let accepted_str = &args[2];
    let accepted = accepted_str == "1" || accepted_str.to_lowercase() == "true";

    let rating: Option<u8> = args.get(3).and_then(|v| v.parse().ok());

    let notes: Option<String> = if args.len() > 4 {
        Some(args[4..].join(" "))
    } else {
        None
    };

    let cfg = load_config();
    let data_dir = PathBuf::from(&cfg.storage.data_dir);

    let event = create_human_feedback_event(
        run_id.clone(),
        accepted,
        rating,
        notes,
    );

    append_event(&data_dir, &event)?;

    println!("✅ Feedback humano registrado para run_id={}", run_id);
    println!("   Accepted: {}", accepted);
    if let Some(r) = rating {
        println!("   Rating: {}/10", r);
    }
    if let Some(ref n) = event.notes {
        println!("   Notes: {}", n);
    }

    Ok(())
}

