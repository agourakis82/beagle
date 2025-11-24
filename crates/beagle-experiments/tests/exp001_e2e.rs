//! Testes end-to-end para Beagle Expedition 001
//!
//! Valida que:
//! - Tags são criadas corretamente com experiment_id beagle_exp_001_triad_vs_single
//! - analyze_experiments detecta condições e calcula métricas corretamente
//! - Effect size (diferença de médias) é calculado corretamente

use beagle_config::beagle_data_dir;
use beagle_experiments::{
    analysis::{calculate_metrics, join_experiment_data, load_feedback_events, load_run_reports},
    append_experiment_tag,
    exp001::EXPEDITION_001_ID,
    load_experiment_tags_by_id, ExperimentRunTag,
};
use beagle_feedback::{append_event, create_human_feedback_event, create_pipeline_event};
use chrono::Utc;
use std::path::PathBuf;
use tempfile::TempDir;

#[tokio::test]
async fn test_expedition_001_tagging_and_analysis() -> anyhow::Result<()> {
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

    let experiment_id = EXPEDITION_001_ID;

    // Cria 10 runs sintéticos (5 triad, 5 single) com dados consistentes
    let triad_runs = vec![
        ("run_triad_1", true, Some(8u8)),
        ("run_triad_2", true, Some(9u8)),
        ("run_triad_3", true, Some(8u8)),
        ("run_triad_4", true, Some(7u8)),
        ("run_triad_5", true, Some(9u8)),
    ];

    let single_runs = vec![
        ("run_single_1", false, Some(6u8)),
        ("run_single_2", false, Some(7u8)),
        ("run_single_3", false, Some(6u8)),
        ("run_single_4", false, Some(5u8)),
        ("run_single_5", false, Some(7u8)),
    ];

    // Processa runs triad
    for (run_id, accepted, rating) in &triad_runs {
        // Cria feedback event inicial (PipelineRun)
        let pipeline_event = create_pipeline_event(
            run_id.to_string(),
            format!("Expedition 001 test question for {}", run_id),
            PathBuf::from(format!("draft_{}.md", run_id)),
            None,
        );
        append_event(&temp_path, &pipeline_event)?;

        // Cria feedback humano
        let human_feedback = create_human_feedback_event(
            run_id.to_string(),
            *accepted,
            *rating,
            Some(format!("Test feedback for {}", run_id)),
        );
        append_event(&temp_path, &human_feedback)?;

        // Cria run_report.json sintético
        let report = serde_json::json!({
            "run_id": run_id,
            "question": format!("Expedition 001 test question for {}", run_id),
            "observer": {
                "physio_severity": "Normal",
                "env_severity": "Normal",
                "space_severity": "Normal",
                "stress_index": 0.5,
            },
            "llm_stats": {
                "grok3_calls": 6,
                "grok4_calls": 0,
                "total_tokens": 1200,
            },
        });

        let report_path = logs_dir.join(format!("report_{}.json", run_id));
        std::fs::write(&report_path, serde_json::to_string_pretty(&report)?)?;

        // Cria experiment tag
        let tag = ExperimentRunTag {
            experiment_id: experiment_id.to_string(),
            run_id: run_id.to_string(),
            condition: "triad".to_string(),
            timestamp: Utc::now(),
            notes: None,
            triad_enabled: true,
            hrv_aware: true,
            serendipity_enabled: false,
            space_aware: false,
        };

        append_experiment_tag(&temp_path, &tag)?;
    }

    // Processa runs single
    for (run_id, accepted, rating) in &single_runs {
        // Cria feedback event inicial (PipelineRun)
        let pipeline_event = create_pipeline_event(
            run_id.to_string(),
            format!("Expedition 001 test question for {}", run_id),
            PathBuf::from(format!("draft_{}.md", run_id)),
            None,
        );
        append_event(&temp_path, &pipeline_event)?;

        // Cria feedback humano
        let human_feedback = create_human_feedback_event(
            run_id.to_string(),
            *accepted,
            *rating,
            Some(format!("Test feedback for {}", run_id)),
        );
        append_event(&temp_path, &human_feedback)?;

        // Cria run_report.json sintético
        let report = serde_json::json!({
            "run_id": run_id,
            "question": format!("Expedition 001 test question for {}", run_id),
            "observer": {
                "physio_severity": "Normal",
                "env_severity": "Normal",
                "space_severity": "Normal",
                "stress_index": 0.52,
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
            condition: "single".to_string(),
            timestamp: Utc::now(),
            notes: None,
            triad_enabled: false,
            hrv_aware: true,
            serendipity_enabled: false,
            space_aware: false,
        };

        append_experiment_tag(&temp_path, &tag)?;
    }

    // Verifica que experiments/events.jsonl foi criado
    let events_file = experiments_dir.join("events.jsonl");
    assert!(
        events_file.exists(),
        "experiments/events.jsonl deve existir"
    );

    // Carrega tags e verifica
    let tags = load_experiment_tags_by_id(&temp_path, experiment_id)?;
    assert_eq!(tags.len(), 10, "Deve haver 10 tags (5 triad + 5 single)");

    // Verifica que condições foram registradas corretamente
    let triad_count = tags.iter().filter(|t| t.condition == "triad").count();
    let single_count = tags.iter().filter(|t| t.condition == "single").count();
    assert_eq!(triad_count, 5, "Deve haver 5 tags triad");
    assert_eq!(single_count, 5, "Deve haver 5 tags single");

    // Verifica flags de snapshot
    for tag in &tags {
        if tag.condition == "triad" {
            assert!(tag.triad_enabled, "Tags triad devem ter triad_enabled=true");
        } else {
            assert!(
                !tag.triad_enabled,
                "Tags single devem ter triad_enabled=false"
            );
        }
        assert!(
            tag.hrv_aware,
            "Todas as tags devem ter hrv_aware=true (Expedition 001)"
        );
        assert!(
            !tag.serendipity_enabled,
            "Todas as tags devem ter serendipity_enabled=false (Expedition 001)"
        );
        assert!(
            !tag.space_aware,
            "Todas as tags devem ter space_aware=false (Expedition 001)"
        );
    }

    // Faz join e calcula métricas
    let feedback_events = load_feedback_events(&temp_path)?;
    let run_ids_vec: Vec<String> = tags.iter().map(|t| t.run_id.clone()).collect();
    let run_reports = load_run_reports(&temp_path, &run_ids_vec)?;

    let data_points = join_experiment_data(tags.clone(), feedback_events, run_reports);
    assert_eq!(data_points.len(), 10, "Deve haver 10 data points");

    // Calcula métricas
    let metrics = calculate_metrics(&data_points);
    assert_eq!(metrics.experiment_id, experiment_id);
    assert_eq!(metrics.total_runs, 10);
    assert_eq!(metrics.conditions.len(), 2, "Deve haver 2 condições");

    // Verifica métricas por condição
    let triad_metrics = metrics.conditions.get("triad").unwrap();
    assert_eq!(triad_metrics.n_runs, 5);
    assert_eq!(triad_metrics.n_with_feedback, 5);
    assert_eq!(triad_metrics.accepted_count, 5); // Todos aceitos
    assert!(triad_metrics.rating_mean.unwrap() >= 8.0); // Média deve ser >= 8.0
    assert!(triad_metrics.rating_mean.unwrap() <= 8.5); // Média deve ser <= 8.5 (8,9,8,7,9 = 8.2)

    let single_metrics = metrics.conditions.get("single").unwrap();
    assert_eq!(single_metrics.n_runs, 5);
    assert_eq!(single_metrics.n_with_feedback, 5);
    assert_eq!(single_metrics.accepted_count, 5); // Todos aceitos
    assert!(single_metrics.rating_mean.unwrap() < 7.0); // Média deve ser < 7.0 (6,7,6,5,7 = 6.2)

    // Verifica effect size (diferença de médias)
    let delta = triad_metrics.rating_mean.unwrap() - single_metrics.rating_mean.unwrap();
    assert!(
        delta > 0.0,
        "Triad deve ter rating maior que Single (effect positivo)"
    );
    assert!(delta >= 1.0, "Effect size deve ser substancial (>= 1.0)");

    // Verifica distribuição de severidades
    assert_eq!(triad_metrics.physio_severity_counts.get("Normal"), Some(&5));
    assert_eq!(
        single_metrics.physio_severity_counts.get("Normal"),
        Some(&5)
    );

    // Verifica stress_index
    assert!(triad_metrics.stress_index_mean.is_some());
    assert!(single_metrics.stress_index_mean.is_some());

    println!("✅ Teste Expedition 001 passou!");
    println!(
        "   Triad rating mean: {:.2}",
        triad_metrics.rating_mean.unwrap()
    );
    println!(
        "   Single rating mean: {:.2}",
        single_metrics.rating_mean.unwrap()
    );
    println!("   Effect size (Δ): {:.2}", delta);

    Ok(())
}
