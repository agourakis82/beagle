//! CLI para etiquetar run_id com condição experimental (A/B testing)

use beagle_config::load as load_config;
use beagle_feedback::{append_event, create_human_feedback_event, FeedbackEvent};
use chrono::Utc;
use std::path::PathBuf;

fn main() -> anyhow::Result<()> {
    let args: Vec<String> = std::env::args().collect();
    
    if args.len() < 4 {
        eprintln!("Uso: tag-experiment <run_id> <experiment_id> <condition> [notes...]");
        eprintln!();
        eprintln!("Exemplos:");
        eprintln!("  tag-experiment abc123 exp-001 A \"Condição controle\"");
        eprintln!("  tag-experiment abc123 exp-001 B \"Condição tratamento\"");
        eprintln!("  tag-experiment abc123 exp-002 control");
        std::process::exit(1);
    }

    let run_id = &args[1];
    let experiment_id = &args[2];
    let condition = &args[3];
    let notes: Option<String> = if args.len() > 4 {
        Some(args[4..].join(" "))
    } else {
        None
    };

    let cfg = load_config();
    let data_dir = PathBuf::from(&cfg.storage.data_dir);

    // Carrega eventos existentes para encontrar o run_id
    let events = beagle_feedback::load_all_events(&data_dir)?;
    
    // Encontra o último evento do run_id
    let mut found_event: Option<FeedbackEvent> = None;
    for event in events.iter().rev() {
        if event.run_id == *run_id {
            found_event = Some(event.clone());
            break;
        }
    }

    if let Some(mut event) = found_event {
        // Atualiza o evento existente com condição experimental
        event.experiment_id = Some(experiment_id.clone());
        event.experiment_condition = Some(condition.clone());
        if let Some(ref n) = notes {
            event.notes = Some(format!("{} | Experiment: {}", event.notes.as_deref().unwrap_or(""), n));
        }
        
        // Cria novo evento HumanFeedback com a condição experimental
        let human_event = beagle_feedback::create_human_feedback_event(
            run_id.clone(),
            event.accepted.unwrap_or(false),
            event.rating_0_10,
            event.notes.clone(),
        );
        
        // Adiciona campos experimentais
        let mut final_event = human_event;
        final_event.experiment_id = Some(experiment_id.clone());
        final_event.experiment_condition = Some(condition.clone());
        
        append_event(&data_dir, &final_event)?;

        println!("✅ Condição experimental registrada para run_id={}", run_id);
        println!("   Experiment ID: {}", experiment_id);
        println!("   Condition: {}", condition);
        if let Some(ref n) = notes {
            println!("   Notes: {}", n);
        }
    } else {
        // Se não encontrou evento, cria um novo apenas com condição experimental
        let mut event = FeedbackEvent {
            event_type: beagle_feedback::FeedbackEventType::HumanFeedback,
            run_id: run_id.clone(),
            timestamp: Utc::now(),
            question: None,
            draft_md: None,
            draft_pdf: None,
            triad_final_md: None,
            triad_report_json: None,
            hrv_level: None,
            llm_provider_main: None,
            grok3_calls: None,
            grok4_heavy_calls: None,
            grok3_tokens_est: None,
            grok4_tokens_est: None,
            accepted: None,
            rating_0_10: None,
            notes,
            experiment_id: Some(experiment_id.clone()),
            experiment_condition: Some(condition.clone()),
        };
        
        append_event(&data_dir, &event)?;
        
        println!("✅ Condição experimental registrada (novo evento) para run_id={}", run_id);
        println!("   Experiment ID: {}", experiment_id);
        println!("   Condition: {}", condition);
    }

    Ok(())
}

