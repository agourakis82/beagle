use anyhow::{anyhow, Context, Result};
use beagle_config::beagle_data_dir;
use beagle_experiments::{
    Expedition002HumanEvalKey, Expedition002HumanRating, Expedition002HumanRatingBatch,
    EXPEDITION_002_HUMAN_EVAL_PROTOCOL,
};
use beagle_feedback::{
    append_event, create_structured_human_feedback_event, StructuredHumanJudgment,
};
use clap::Parser;
use std::collections::HashMap;
use std::path::PathBuf;

#[derive(Parser)]
#[command(name = "apply_expedition_002_human_eval", version)]
struct Cli {
    /// Filled ratings JSON that matches the blinded packet contract
    #[arg(long)]
    ratings_file: PathBuf,

    /// Audit key generated together with the blinded packet
    #[arg(long)]
    packet_key_file: PathBuf,

    /// Optional file to freeze the appended events
    #[arg(long)]
    appended_events_file: Option<PathBuf>,
}

fn main() -> Result<()> {
    let args = Cli::parse();
    let data_dir = beagle_data_dir();

    let batch: Expedition002HumanRatingBatch =
        serde_json::from_slice(&std::fs::read(&args.ratings_file)?)
            .context("unable to parse ratings file")?;
    let key: Expedition002HumanEvalKey =
        serde_json::from_slice(&std::fs::read(&args.packet_key_file)?)
            .context("unable to parse packet key file")?;

    if batch.protocol_version != EXPEDITION_002_HUMAN_EVAL_PROTOCOL {
        return Err(anyhow!(
            "unsupported protocol_version={}, expected={}",
            batch.protocol_version,
            EXPEDITION_002_HUMAN_EVAL_PROTOCOL
        ));
    }
    if batch.packet_id != key.packet_id {
        return Err(anyhow!(
            "ratings packet_id {} does not match key packet_id {}",
            batch.packet_id,
            key.packet_id
        ));
    }
    if batch.experiment_id != key.experiment_id {
        return Err(anyhow!(
            "ratings experiment_id {} does not match key experiment_id {}",
            batch.experiment_id,
            key.experiment_id
        ));
    }

    let key_by_item: HashMap<String, _> = key
        .entries
        .iter()
        .map(|entry| (entry.blinded_item_id.clone(), entry))
        .collect();
    let mut appended_events = Vec::new();

    for rating in &batch.ratings {
        validate_rating(rating)?;
        let entry = key_by_item
            .get(&rating.blinded_item_id)
            .with_context(|| format!("unknown blinded_item_id={}", rating.blinded_item_id))?;

        let mut event = create_structured_human_feedback_event(
            entry.run_id.clone(),
            StructuredHumanJudgment {
                accepted: rating.accepted.expect("validated accepted"),
                rating_0_10: rating.rating_global_0_10,
                clarity_0_10: rating.clarity_0_10,
                adequacy_of_tone_0_10: rating.adequacy_of_tone_0_10,
                usefulness_0_10: rating.usefulness_0_10,
                safety_or_emotional_fit_0_10: rating.safety_or_emotional_fit_0_10,
                notes: rating.notes.clone(),
                evaluator_id: Some(batch.evaluator_id.clone()),
                judgment_protocol: Some(batch.protocol_version.clone()),
                blinded_item_id: Some(rating.blinded_item_id.clone()),
            },
        );
        event.experiment_id = Some(batch.experiment_id.clone());
        event.experiment_condition = Some(entry.condition.clone());

        append_event(&data_dir, &event)?;
        appended_events.push(event);
    }

    if let Some(path) = args.appended_events_file {
        std::fs::write(path, serde_json::to_string_pretty(&appended_events)?)?;
    }

    println!("✅ Expedition 002 human ratings applied");
    println!("   Experiment ID: {}", batch.experiment_id);
    println!("   Packet ID: {}", batch.packet_id);
    println!("   Evaluator: {}", batch.evaluator_id);
    println!("   Ratings applied: {}", batch.ratings.len());

    Ok(())
}

fn validate_rating(rating: &Expedition002HumanRating) -> Result<()> {
    if rating.accepted.is_none() {
        return Err(anyhow!(
            "accepted must be provided for {}",
            rating.blinded_item_id
        ));
    }
    for (label, value) in [
        ("rating_global_0_10", rating.rating_global_0_10),
        ("clarity_0_10", rating.clarity_0_10),
        ("adequacy_of_tone_0_10", rating.adequacy_of_tone_0_10),
        ("usefulness_0_10", rating.usefulness_0_10),
        (
            "safety_or_emotional_fit_0_10",
            rating.safety_or_emotional_fit_0_10,
        ),
    ] {
        let Some(score) = value else {
            return Err(anyhow!(
                "{} must be provided for {}",
                label,
                rating.blinded_item_id
            ));
        };
        if score > 10 {
            return Err(anyhow!(
                "{} must be <= 10 for {}",
                label,
                rating.blinded_item_id
            ));
        }
    }
    Ok(())
}
