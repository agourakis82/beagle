use anyhow::{anyhow, Context, Result};
use beagle_config::beagle_data_dir;
use beagle_experiments::{
    expedition_002_blank_human_rating_template, expedition_002_build_human_eval_packet,
    load_experiment_tags_by_id, Expedition002HumanEvalSource, EXPEDITION_002_ID,
};
use beagle_feedback::load_all_events;
use clap::Parser;
use chrono::Utc;
use std::collections::HashSet;
use std::path::{Path, PathBuf};

#[derive(Parser)]
#[command(name = "prepare_expedition_002_human_eval", version)]
struct Cli {
    /// Experiment id (defaults to canonical Expedition 002 id)
    #[arg(long, default_value = EXPEDITION_002_ID)]
    experiment_id: String,

    /// Optional run_ids filter file (one run_id per line)
    #[arg(long)]
    run_ids_file: Option<PathBuf>,

    /// Output directory for packet/key/template artifacts
    #[arg(long)]
    output_dir: PathBuf,

    /// Optional stable packet id
    #[arg(long)]
    packet_id: Option<String>,

    /// Template evaluator id used in the blank ratings file
    #[arg(long, default_value = "pending-human")]
    evaluator_id: String,
}

fn main() -> Result<()> {
    let args = Cli::parse();
    let data_dir = beagle_data_dir();

    std::fs::create_dir_all(&args.output_dir)?;

    let run_id_filter = load_run_id_filter(args.run_ids_file.as_deref())?;
    let tags = load_experiment_tags_by_id(&data_dir, &args.experiment_id)?;
    if tags.is_empty() {
        return Err(anyhow!(
            "no experiment tags found for experiment_id={}",
            args.experiment_id
        ));
    }

    let events = load_all_events(&data_dir)?;
    let packet_id = args.packet_id.unwrap_or_else(|| {
        format!(
            "exp002-human-eval-{}",
            Utc::now().format("%Y%m%d%H%M%S")
        )
    });

    let mut sources = Vec::new();
    let mut source_summary = Vec::new();

    for tag in tags {
        if let Some(ref run_ids) = run_id_filter {
            if !run_ids.contains(&tag.run_id) {
                continue;
            }
        }

        let pipeline_event = events
            .iter()
            .rev()
            .find(|event| {
                event.run_id == tag.run_id
                    && event.experiment_id.as_deref() == Some(args.experiment_id.as_str())
                    && event.draft_md.is_some()
                    && event.question.is_some()
            })
            .cloned()
            .with_context(|| format!("missing pipeline source event for run_id={}", tag.run_id))?;

        let draft_md_path = pipeline_event
            .draft_md
            .clone()
            .context("draft_md missing in pipeline event")?;
        let draft_markdown = std::fs::read_to_string(&draft_md_path).with_context(|| {
            format!("unable to read localized draft markdown at {}", draft_md_path.display())
        })?;
        let question = pipeline_event
            .question
            .clone()
            .context("question missing in pipeline event")?;

        source_summary.push(serde_json::json!({
            "run_id": tag.run_id,
            "condition": tag.condition,
            "question": question,
            "draft_md_path": draft_md_path,
            "draft_pdf_path": pipeline_event.draft_pdf,
        }));

        sources.push(Expedition002HumanEvalSource {
            run_id: tag.run_id,
            condition: tag.condition,
            question,
            draft_md_path,
            draft_pdf_path: pipeline_event.draft_pdf,
            draft_markdown,
        });
    }

    if sources.is_empty() {
        return Err(anyhow!("no sources resolved for blinded human-eval packet"));
    }

    let (packet, key) =
        expedition_002_build_human_eval_packet(&args.experiment_id, &packet_id, sources);
    let blinded_item_ids: Vec<String> = packet
        .items
        .iter()
        .map(|item| item.blinded_item_id.clone())
        .collect();
    let template = expedition_002_blank_human_rating_template(
        &args.experiment_id,
        &packet_id,
        &args.evaluator_id,
        &blinded_item_ids,
    );

    std::fs::write(
        args.output_dir.join("human-eval-packet.json"),
        serde_json::to_string_pretty(&packet)?,
    )?;
    std::fs::write(
        args.output_dir.join("human-eval-key.json"),
        serde_json::to_string_pretty(&key)?,
    )?;
    std::fs::write(
        args.output_dir.join("human-eval-template.json"),
        serde_json::to_string_pretty(&template)?,
    )?;
    std::fs::write(
        args.output_dir.join("human-eval-source-summary.json"),
        serde_json::to_string_pretty(&source_summary)?,
    )?;

    println!("✅ Expedition 002 human-eval packet prepared");
    println!("   Experiment ID: {}", args.experiment_id);
    println!("   Packet ID: {}", packet_id);
    println!("   Items: {}", blinded_item_ids.len());
    println!(
        "   Output dir: {}",
        args.output_dir.as_path().display()
    );

    Ok(())
}

fn load_run_id_filter(path: Option<&Path>) -> Result<Option<HashSet<String>>> {
    let Some(path) = path else {
        return Ok(None);
    };

    let content = std::fs::read_to_string(path)?;
    let ids = content
        .lines()
        .map(str::trim)
        .filter(|line| !line.is_empty())
        .map(ToOwned::to_owned)
        .collect::<HashSet<_>>();
    Ok(Some(ids))
}
