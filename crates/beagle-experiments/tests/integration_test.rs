//! Testes end-to-end de tagging e análise de experimentos
//!
//! Cria dados sintéticos (feedback events, run reports) e verifica:
//! - tag_experiment_run funciona e cria experiments/events.jsonl
//! - analyze_experiments agrupa corretamente e produz métricas coerentes

use beagle_experiments::{
    append_experiment_tag,
    load_experiment_tags_by_id,
    analysis::{
        load_feedback_events,
        load_run_reports,
        join_experiment_data,
        calculate_metrics,
    },
    ExperimentRunTag,
};
use beagle_feedback::{append_event, create_pipeline_event, FeedbackEvent};
use beagle_config::beagle_data_dir;
use chrono::Utc;
use std::path::PathBuf;
use tempfile::TempDir;
use tracing::info;

#[tokio::test]
async fn test_tag_experiment_run_and_analysis() -> anyhow::Result<()> {
    // Setup: cria tempdir e seta BEAGLE_DATA_DIR
    let temp_dir = TempDir::new()?;
    let temp_path = temp_dir.path().to_path_buf();
    std::env::set_var("BEAGLE_DATA_DIR", temp_path.to_string_lossy().to_string());
    
    // Cria estrutura de diretórios
    let feedback_dir = temp_path.join("feedback");
    let experiments_dir = temp_path.join("experiments");
    let logs_dir = temp_path.join("logs").join("beagle-pipeline");
    std::fs::create_dir_all(&feedback_dir)?;
    std::fs::create_dir_all(&experiments_dir)?;
    std::fs::create_dir_all(&logs_dir)?;
    
    let experiment_id = "test_triad_vs_single_v1";
    
    // Cria 4-6 runs com feedback sintético
    let run_ids = vec![
        ("run1", "triad", true, Some(8u8)),
        ("run2", "triad", true, Some(9u8)),
        ("run3", "single", false, Some(6u8)),
        ("run4", "single", false, Some(7u8)),
    ];
    
    for (run_id, condition, accepted, rating) in &run_ids {
        // Cria feedback event
        let event = create_pipeline_event(
            run_id.to_string(),
            format!("Test question for {}", run_id),
            PathBuf::from(format!("draft_{}.md", run_id)),
            None, // draft_pdf
        );
        
        // Atualiza com avaliação humana
        let mut feedback_event = event.clone();
        feedback_event.accepted = Some(*accepted);
        feedback_event.rating_0_10 = *rating;
        feedback_event.experiment_id = Some(experiment_id.to_string());
        feedback_event.experiment_condition = Some(condition.to_string());
        
        append_event(&temp_path, &feedback_event)?;
        
        // Cria run_report.json sintético
        let report = serde_json::json!({
            "run_id": run_id,
            "question": format!("Test question for {}", run_id),
            "observer": {
                "physio_severity": "Normal",
                "env_severity": "Normal",
                "space_severity": "Normal",
                "stress_index": 0.5,
            },
            "llm_stats": {
                "grok3_calls": 5,
                "grok4_calls": 0,
                "total_tokens": 1000,
            },
        });
        
        let report_path = logs_dir.join(format!("report_{}.json", run_id));
        std::fs::write(&report_path, serde_json::to_string_pretty(&report)?)?;
        
        // Cria experiment tag
        let tag = ExperimentRunTag {
            experiment_id: experiment_id.to_string(),
            run_id: run_id.to_string(),
            condition: condition.to_string(),
            timestamp: Utc::now(),
            notes: None,
            triad_enabled: condition == "triad",
            hrv_aware: true,
            serendipity_enabled: false,
            space_aware: false,
        };
        
        append_experiment_tag(&temp_path, &tag)?;
    }
    
    // Verifica que experiments/events.jsonl foi criado
    let events_file = experiments_dir.join("events.jsonl");
    assert!(events_file.exists(), "experiments/events.jsonl deve existir");
    
    // Carrega tags e verifica
    let tags = load_experiment_tags_by_id(&temp_path, experiment_id)?;
    assert_eq!(tags.len(), 4, "Deve haver 4 tags");
    
    // Faz join e calcula métricas
    let feedback_events = load_feedback_events(&temp_path)?;
    let run_ids_vec: Vec<String> = tags.iter().map(|t| t.run_id.clone()).collect();
    let run_reports = load_run_reports(&temp_path, &run_ids_vec)?;
    
    let data_points = join_experiment_data(tags.clone(), feedback_events, run_reports);
    assert_eq!(data_points.len(), 4, "Deve haver 4 data points");
    
    // Calcula métricas
    let metrics = calculate_metrics(&data_points);
    assert_eq!(metrics.experiment_id, experiment_id);
    assert_eq!(metrics.total_runs, 4);
    assert_eq!(metrics.conditions.len(), 2, "Deve haver 2 condições");
    
    // Verifica métricas por condição
    let triad_metrics = metrics.conditions.get("triad").unwrap();
    assert_eq!(triad_metrics.n_runs, 2);
    assert_eq!(triad_metrics.n_with_feedback, 2);
    assert_eq!(triad_metrics.accepted_count, 2);
    assert!(triad_metrics.rating_mean.unwrap() >= 8.0);
    
    let single_metrics = metrics.conditions.get("single").unwrap();
    assert_eq!(single_metrics.n_runs, 2);
    assert_eq!(single_metrics.n_with_feedback, 2);
    assert_eq!(single_metrics.accepted_count, 2);
    assert!(single_metrics.rating_mean.unwrap() < 8.0);
    
    info!("✅ Teste de tagging e análise passou!");
    
    Ok(())
}

