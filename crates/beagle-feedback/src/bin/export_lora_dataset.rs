//! Export para dataset de treino LoRA
//!
//! Uso:
//!   cargo run --bin export-lora-dataset --package beagle-feedback

use beagle_config::load as load_config;
use beagle_feedback::{load_all_events, FeedbackEventType};
use std::collections::HashMap;
use std::io::Write;
use std::path::PathBuf;

#[derive(Debug)]
struct RunArtifacts {
    question: Option<String>,
    draft_md: Option<String>,
    triad_final_md: Option<String>,
    accepted: bool,
    rating: Option<u8>,
}

fn main() -> anyhow::Result<()> {
    let cfg = load_config();
    let data_dir = PathBuf::from(&cfg.storage.data_dir);

    let events = load_all_events(&data_dir)?;

    let mut runs: HashMap<String, RunArtifacts> = HashMap::new();

    for ev in events {
        let ra = runs.entry(ev.run_id.clone()).or_insert(RunArtifacts {
            question: None,
            draft_md: None,
            triad_final_md: None,
            accepted: false,
            rating: None,
        });

        match ev.event_type {
            FeedbackEventType::PipelineRun => {
                if let Some(q) = ev.question {
                    ra.question = Some(q);
                }
                if let Some(path) = ev.draft_md {
                    if let Ok(text) = std::fs::read_to_string(&path) {
                        ra.draft_md = Some(text);
                    }
                }
            }
            FeedbackEventType::TriadCompleted => {
                if let Some(path) = ev.triad_final_md {
                    if let Ok(text) = std::fs::read_to_string(&path) {
                        ra.triad_final_md = Some(text);
                    }
                }
            }
            FeedbackEventType::HumanFeedback => {
                if let Some(a) = ev.accepted {
                    if a {
                        ra.accepted = true;
                    }
                }
                if let Some(r) = ev.rating_0_10 {
                    ra.rating = Some(r);
                }
            }
        }
    }

    let out_path = data_dir.join("feedback").join("lora_dataset.jsonl");
    let mut out = std::fs::File::create(&out_path)?;

    let mut count = 0usize;

    for (run_id, ra) in runs {
        // Critério de qualidade: accepted=true e rating >= 8
        if !ra.accepted {
            continue;
        }
        if let Some(r) = ra.rating {
            if r < 8 {
                continue;
            }
        } else {
            continue;
        }

        let question = match &ra.question {
            Some(q) => q,
            None => continue,
        };
        let draft_md = match &ra.draft_md {
            Some(d) => d,
            None => continue,
        };
        let final_md = match &ra.triad_final_md {
            Some(f) => f,
            None => continue,
        };

        let input = format!(
            "Pergunta:\n{}\n\nDraft inicial:\n{}\n",
            question, draft_md
        );
        let output = final_md;

        let json = serde_json::json!({
            "run_id": run_id,
            "input": input,
            "output": output,
        });

        writeln!(out, "{}", serde_json::to_string(&json)?)?;
        count += 1;
    }

    println!(
        "✅ Dataset LoRA exportado com {} exemplos em {}",
        count,
        out_path.display()
    );

    Ok(())
}

