//! BEAGLE Experiments - Análise estatística de experimentos
//!
//! Padrão Q1, estilo HELM/AgentBench: agregação, métricas claras, exportação CSV/JSON.

use crate::ExperimentRunTag;
use beagle_feedback::FeedbackEvent;
use serde::{Deserialize, Serialize};
use std::collections::HashMap;
use std::path::Path;

/// Ponto de dados experimentais agregado
///
/// Join de ExperimentRunTag + FeedbackEvent + RunReport
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ExperimentDataPoint {
    pub tag: ExperimentRunTag,
    pub feedback: Option<FeedbackEvent>,
    pub run_report: Option<serde_json::Value>,
}

/// Métricas agregadas por condição
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ConditionMetrics {
    pub condition: String,
    pub n_runs: usize,
    pub n_with_feedback: usize,

    // Rating humano
    pub rating_mean: Option<f64>,
    pub rating_std: Option<f64>,
    pub rating_p50: Option<f64>,
    pub rating_p90: Option<f64>,
    pub clarity_mean: Option<f64>,
    pub adequacy_of_tone_mean: Option<f64>,
    pub usefulness_mean: Option<f64>,
    pub safety_or_emotional_fit_mean: Option<f64>,

    // Aceitação
    pub accepted_count: usize,
    pub accepted_ratio: Option<f64>,

    // Distribuição de severidades fisiológicas
    pub physio_severity_counts: HashMap<String, usize>,

    // Distribuição de severidades ambientais
    pub env_severity_counts: HashMap<String, usize>,

    // Distribuição de severidades de clima espacial
    pub space_severity_counts: HashMap<String, usize>,

    // Stress index
    pub stress_index_mean: Option<f64>,

    // Canonical pipeline physio usage
    pub pipeline_physio_used_count: usize,
    pub physio_snapshot_available_count: usize,
    pub pipeline_physio_hrv_level_counts: HashMap<String, usize>,
    pub physio_hr_mean: Option<f64>,
    pub physio_spo2_mean: Option<f64>,

    // LLM stats
    pub avg_tokens: Option<f64>,
    pub avg_grok3_calls: Option<f64>,
    pub avg_grok4_calls: Option<f64>,
}

/// Métricas agregadas de um experimento completo
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ExperimentMetrics {
    pub experiment_id: String,
    pub conditions: HashMap<String, ConditionMetrics>,
    pub total_runs: usize,
}

/// Carrega feedback events de um diretório
pub fn load_feedback_events(data_dir: &Path) -> anyhow::Result<Vec<FeedbackEvent>> {
    beagle_feedback::load_all_events(data_dir)
}

/// Carrega run reports de um diretório
pub fn load_run_reports(
    data_dir: &Path,
    run_ids: &[String],
) -> anyhow::Result<HashMap<String, serde_json::Value>> {
    use glob::glob;

    let mut reports = HashMap::new();
    let report_dir = data_dir.join("logs").join("beagle-pipeline");

    if !report_dir.exists() {
        return Ok(reports);
    }

    // Procura arquivos *_{run_id}.json
    for run_id in run_ids {
        let pattern = report_dir.join(format!("*_{}.json", run_id));

        if let Ok(paths) = glob(pattern.to_str().unwrap_or_default()) {
            for entry in paths.flatten() {
                if let Ok(content) = std::fs::read_to_string(&entry) {
                    if let Ok(report) = serde_json::from_str::<serde_json::Value>(&content) {
                        reports.insert(run_id.clone(), report);
                        break; // Primeiro match é suficiente
                    }
                }
            }
        }
    }

    Ok(reports)
}

/// Faz join de tags, feedback e reports por run_id
pub fn join_experiment_data(
    tags: Vec<ExperimentRunTag>,
    feedback: Vec<FeedbackEvent>,
    reports: HashMap<String, serde_json::Value>,
) -> Vec<ExperimentDataPoint> {
    // Indexa feedback por run_id preservando a sequência para escolher o melhor
    // evento canônico (prioridade: julgamento humano explícito).
    let mut feedback_by_run_id: HashMap<String, Vec<FeedbackEvent>> = HashMap::new();
    for event in feedback {
        feedback_by_run_id
            .entry(event.run_id.clone())
            .or_default()
            .push(event);
    }

    // Cria data points
    tags.into_iter()
        .map(|tag| {
            let feedback = feedback_by_run_id
                .get(&tag.run_id)
                .and_then(|events| select_canonical_feedback_event(events));
            let run_report = reports.get(&tag.run_id).cloned();

            ExperimentDataPoint {
                tag,
                feedback,
                run_report,
            }
        })
        .collect()
}

fn select_canonical_feedback_event(events: &[FeedbackEvent]) -> Option<FeedbackEvent> {
    events
        .iter()
        .rev()
        .find(|event| event.has_human_judgment())
        .cloned()
        .or_else(|| events.iter().rev().next().cloned())
}

/// Calcula métricas agregadas por condição
pub fn calculate_metrics(data_points: &[ExperimentDataPoint]) -> ExperimentMetrics {
    let experiment_id = data_points
        .first()
        .map(|dp| dp.tag.experiment_id.clone())
        .unwrap_or_else(|| "unknown".to_string());

    // Agrupa por condition
    let mut by_condition: HashMap<String, Vec<&ExperimentDataPoint>> = HashMap::new();
    for dp in data_points {
        by_condition
            .entry(dp.tag.condition.clone())
            .or_insert_with(Vec::new)
            .push(dp);
    }

    // Calcula métricas por condição
    let mut condition_metrics: HashMap<String, ConditionMetrics> = HashMap::new();

    for (condition, points) in &by_condition {
        let metrics = calculate_condition_metrics(condition, points);
        condition_metrics.insert(condition.clone(), metrics);
    }

    ExperimentMetrics {
        experiment_id,
        conditions: condition_metrics,
        total_runs: data_points.len(),
    }
}

/// Calcula métricas para uma condição específica
fn calculate_condition_metrics(
    condition: &str,
    points: &[&ExperimentDataPoint],
) -> ConditionMetrics {
    let n_runs = points.len();

    // Filtra pontos com feedback
    let points_with_feedback: Vec<_> = points
        .iter()
        .filter(|dp| {
            dp.feedback
                .as_ref()
                .map(|feedback| feedback.has_human_judgment())
                .unwrap_or(false)
        })
        .copied()
        .collect();
    let n_with_feedback = points_with_feedback.len();

    // Calcula ratings
    let ratings: Vec<u8> = points_with_feedback
        .iter()
        .filter_map(|dp| dp.feedback.as_ref()?.rating_0_10)
        .collect();

    let (rating_mean, rating_std, rating_p50, rating_p90) = if !ratings.is_empty() {
        let mean = ratings.iter().sum::<u8>() as f64 / ratings.len() as f64;
        let variance = ratings
            .iter()
            .map(|&r| {
                let diff = r as f64 - mean;
                diff * diff
            })
            .sum::<f64>()
            / ratings.len() as f64;
        let std = variance.sqrt();

        let mut sorted = ratings.clone();
        sorted.sort();
        let p50 = sorted[sorted.len() / 2] as f64;
        let p90_idx = (sorted.len() as f64 * 0.9) as usize;
        let p90 = sorted
            .get(p90_idx.min(sorted.len() - 1))
            .copied()
            .unwrap_or(0) as f64;

        (Some(mean), Some(std), Some(p50), Some(p90))
    } else {
        (None, None, None, None)
    };

    let clarity_scores: Vec<u8> = points_with_feedback
        .iter()
        .filter_map(|dp| dp.feedback.as_ref()?.clarity_0_10)
        .collect();
    let adequacy_scores: Vec<u8> = points_with_feedback
        .iter()
        .filter_map(|dp| dp.feedback.as_ref()?.adequacy_of_tone_0_10)
        .collect();
    let usefulness_scores: Vec<u8> = points_with_feedback
        .iter()
        .filter_map(|dp| dp.feedback.as_ref()?.usefulness_0_10)
        .collect();
    let safety_scores: Vec<u8> = points_with_feedback
        .iter()
        .filter_map(|dp| dp.feedback.as_ref()?.safety_or_emotional_fit_0_10)
        .collect();

    let mean_from_scores = |scores: &[u8]| -> Option<f64> {
        if scores.is_empty() {
            None
        } else {
            Some(scores.iter().map(|score| *score as f64).sum::<f64>() / scores.len() as f64)
        }
    };
    let clarity_mean = mean_from_scores(&clarity_scores);
    let adequacy_of_tone_mean = mean_from_scores(&adequacy_scores);
    let usefulness_mean = mean_from_scores(&usefulness_scores);
    let safety_or_emotional_fit_mean = mean_from_scores(&safety_scores);

    // Calcula aceitação
    let accepted_count = points_with_feedback
        .iter()
        .filter(|dp| {
            dp.feedback
                .as_ref()
                .and_then(|f| f.accepted)
                .unwrap_or(false)
        })
        .count();
    let accepted_ratio = if n_with_feedback > 0 {
        Some(accepted_count as f64 / n_with_feedback as f64)
    } else {
        None
    };

    // Distribuição de severidades
    let mut physio_severity_counts: HashMap<String, usize> = HashMap::new();
    let mut env_severity_counts: HashMap<String, usize> = HashMap::new();
    let mut space_severity_counts: HashMap<String, usize> = HashMap::new();

    for point in points {
        if let Some(ref report) = point.run_report {
            // Extrai severidades do Observer
            if let Some(observer) = report.get("observer") {
                if let Some(physio_sev) = observer.get("physio_severity").and_then(|v| v.as_str()) {
                    *physio_severity_counts
                        .entry(physio_sev.to_string())
                        .or_insert(0) += 1;
                }
                if let Some(env_sev) = observer.get("env_severity").and_then(|v| v.as_str()) {
                    *env_severity_counts.entry(env_sev.to_string()).or_insert(0) += 1;
                }
                if let Some(space_sev) = observer.get("space_severity").and_then(|v| v.as_str()) {
                    *space_severity_counts
                        .entry(space_sev.to_string())
                        .or_insert(0) += 1;
                }
            }
        }
    }

    // Stress index mean
    let stress_indices: Vec<f32> = points
        .iter()
        .filter_map(|dp| {
            dp.run_report
                .as_ref()?
                .get("observer")?
                .get("stress_index")?
                .as_f64()
                .map(|v| v as f32)
        })
        .collect();
    let stress_index_mean = if !stress_indices.is_empty() {
        Some(stress_indices.iter().sum::<f32>() as f64 / stress_indices.len() as f64)
    } else {
        None
    };

    let mut pipeline_physio_used_count = 0usize;
    let mut physio_snapshot_available_count = 0usize;
    let mut pipeline_physio_hrv_level_counts: HashMap<String, usize> = HashMap::new();
    let physio_hrs: Vec<f64> = points
        .iter()
        .filter_map(|dp| {
            let pipeline_physio = dp.run_report.as_ref()?.get("pipeline_physio")?;
            if pipeline_physio
                .get("used_in_pipeline")
                .and_then(|v| v.as_bool())
                .unwrap_or(false)
            {
                pipeline_physio_used_count += 1;
            }
            if pipeline_physio
                .get("snapshot_available")
                .and_then(|v| v.as_bool())
                .unwrap_or(false)
            {
                physio_snapshot_available_count += 1;
            }
            if let Some(level) = pipeline_physio.get("hrv_level").and_then(|v| v.as_str()) {
                *pipeline_physio_hrv_level_counts
                    .entry(level.to_string())
                    .or_insert(0) += 1;
            }
            pipeline_physio.get("hr").and_then(|v| v.as_f64())
        })
        .collect();
    let physio_spo2s: Vec<f64> = points
        .iter()
        .filter_map(|dp| {
            dp.run_report
                .as_ref()?
                .get("pipeline_physio")?
                .get("spo2")?
                .as_f64()
        })
        .collect();
    let physio_hr_mean = if physio_hrs.is_empty() {
        None
    } else {
        Some(physio_hrs.iter().sum::<f64>() / physio_hrs.len() as f64)
    };
    let physio_spo2_mean = if physio_spo2s.is_empty() {
        None
    } else {
        Some(physio_spo2s.iter().sum::<f64>() / physio_spo2s.len() as f64)
    };

    // LLM stats
    let mut total_tokens = 0u64;
    let mut total_grok3_calls = 0u32;
    let mut total_grok4_calls = 0u32;
    let mut n_with_llm_stats = 0;

    for point in points {
        if let Some(ref report) = point.run_report {
            if let Some(llm_stats) = report.get("llm_stats") {
                n_with_llm_stats += 1;
                if let Some(total) = llm_stats.get("total_tokens").and_then(|v| v.as_u64()) {
                    total_tokens += total;
                }
                if let Some(g3) = llm_stats.get("grok3_calls").and_then(|v| v.as_u64()) {
                    total_grok3_calls += g3 as u32;
                }
                if let Some(g4) = llm_stats.get("grok4_calls").and_then(|v| v.as_u64()) {
                    total_grok4_calls += g4 as u32;
                }
            }
        }
    }

    let avg_tokens = if n_with_llm_stats > 0 {
        Some(total_tokens as f64 / n_with_llm_stats as f64)
    } else {
        None
    };
    let avg_grok3_calls = if n_with_llm_stats > 0 {
        Some(total_grok3_calls as f64 / n_with_llm_stats as f64)
    } else {
        None
    };
    let avg_grok4_calls = if n_with_llm_stats > 0 {
        Some(total_grok4_calls as f64 / n_with_llm_stats as f64)
    } else {
        None
    };

    ConditionMetrics {
        condition: condition.to_string(),
        n_runs,
        n_with_feedback,
        rating_mean,
        rating_std,
        rating_p50,
        rating_p90,
        clarity_mean,
        adequacy_of_tone_mean,
        usefulness_mean,
        safety_or_emotional_fit_mean,
        accepted_count,
        accepted_ratio,
        physio_severity_counts,
        env_severity_counts,
        space_severity_counts,
        stress_index_mean,
        pipeline_physio_used_count,
        physio_snapshot_available_count,
        pipeline_physio_hrv_level_counts,
        physio_hr_mean,
        physio_spo2_mean,
        avg_tokens,
        avg_grok3_calls,
        avg_grok4_calls,
    }
}

/// Exporta resumo em formato CSV
pub fn export_summary_csv(data_points: &[ExperimentDataPoint]) -> anyhow::Result<String> {
    use csv::WriterBuilder;
    use std::io::Cursor;

    let mut wtr = WriterBuilder::new()
        .has_headers(true)
        .from_writer(Cursor::new(Vec::new()));

    // Cabeçalhos
    wtr.write_record(&[
        "experiment_id",
        "run_id",
        "condition",
        "triad_enabled",
        "hrv_aware",
        "serendipity_enabled",
        "space_aware",
        "rating_0_10",
        "accepted",
        "clarity_0_10",
        "adequacy_of_tone_0_10",
        "usefulness_0_10",
        "safety_or_emotional_fit_0_10",
        "evaluator_id",
        "judgment_protocol",
        "blinded_item_id",
        "physio_severity",
        "env_severity",
        "space_severity",
        "stress_index",
        "experiment_condition_report",
        "experiment_id_report",
        "pipeline_physio_snapshot_available",
        "pipeline_physio_used",
        "pipeline_physio_hrv_level",
        "pipeline_physio_hr",
        "pipeline_physio_spo2",
        "physio_event_trigger_count",
        "total_tokens",
        "grok3_calls",
        "grok4_calls",
    ])?;

    // Linhas
    for point in data_points {
        let rating = point
            .feedback
            .as_ref()
            .and_then(|f| f.rating_0_10)
            .map(|r| r.to_string())
            .unwrap_or_else(|| "".to_string());

        let accepted = point
            .feedback
            .as_ref()
            .and_then(|f| f.accepted)
            .map(|a| {
                if a {
                    "true".to_string()
                } else {
                    "false".to_string()
                }
            })
            .unwrap_or_else(|| "".to_string());
        let clarity = point
            .feedback
            .as_ref()
            .and_then(|f| f.clarity_0_10)
            .map(|v| v.to_string())
            .unwrap_or_default();
        let adequacy_of_tone = point
            .feedback
            .as_ref()
            .and_then(|f| f.adequacy_of_tone_0_10)
            .map(|v| v.to_string())
            .unwrap_or_default();
        let usefulness = point
            .feedback
            .as_ref()
            .and_then(|f| f.usefulness_0_10)
            .map(|v| v.to_string())
            .unwrap_or_default();
        let safety_or_emotional_fit = point
            .feedback
            .as_ref()
            .and_then(|f| f.safety_or_emotional_fit_0_10)
            .map(|v| v.to_string())
            .unwrap_or_default();
        let evaluator_id = point
            .feedback
            .as_ref()
            .and_then(|f| f.evaluator_id.clone())
            .unwrap_or_default();
        let judgment_protocol = point
            .feedback
            .as_ref()
            .and_then(|f| f.judgment_protocol.clone())
            .unwrap_or_default();
        let blinded_item_id = point
            .feedback
            .as_ref()
            .and_then(|f| f.blinded_item_id.clone())
            .unwrap_or_default();

        let physio_sev = point
            .run_report
            .as_ref()
            .and_then(|r| r.get("observer"))
            .and_then(|o| o.get("physio_severity"))
            .and_then(|v| v.as_str())
            .unwrap_or("");

        let env_sev = point
            .run_report
            .as_ref()
            .and_then(|r| r.get("observer"))
            .and_then(|o| o.get("env_severity"))
            .and_then(|v| v.as_str())
            .unwrap_or("");

        let space_sev = point
            .run_report
            .as_ref()
            .and_then(|r| r.get("observer"))
            .and_then(|o| o.get("space_severity"))
            .and_then(|v| v.as_str())
            .unwrap_or("");

        let stress_index = point
            .run_report
            .as_ref()
            .and_then(|r| r.get("observer"))
            .and_then(|o| o.get("stress_index"))
            .and_then(|v| v.as_f64())
            .map(|v| format!("{:.3}", v))
            .unwrap_or_default();

        let experiment_condition_report = point
            .run_report
            .as_ref()
            .and_then(|r| r.get("experiment"))
            .and_then(|e| e.get("condition"))
            .and_then(|v| v.as_str())
            .unwrap_or("");

        let experiment_id_report = point
            .run_report
            .as_ref()
            .and_then(|r| r.get("experiment"))
            .and_then(|e| e.get("experiment_id"))
            .and_then(|v| v.as_str())
            .unwrap_or("");

        let pipeline_physio_snapshot_available = point
            .run_report
            .as_ref()
            .and_then(|r| r.get("pipeline_physio"))
            .and_then(|p| p.get("snapshot_available"))
            .and_then(|v| v.as_bool())
            .map(|v| v.to_string())
            .unwrap_or_default();

        let pipeline_physio_used = point
            .run_report
            .as_ref()
            .and_then(|r| r.get("pipeline_physio"))
            .and_then(|p| p.get("used_in_pipeline"))
            .and_then(|v| v.as_bool())
            .map(|v| v.to_string())
            .unwrap_or_default();

        let pipeline_physio_hrv_level = point
            .run_report
            .as_ref()
            .and_then(|r| r.get("pipeline_physio"))
            .and_then(|p| p.get("hrv_level"))
            .and_then(|v| v.as_str())
            .unwrap_or("");

        let pipeline_physio_hr = point
            .run_report
            .as_ref()
            .and_then(|r| r.get("pipeline_physio"))
            .and_then(|p| p.get("hr"))
            .and_then(|v| v.as_f64())
            .map(|v| format!("{:.1}", v))
            .unwrap_or_default();

        let pipeline_physio_spo2 = point
            .run_report
            .as_ref()
            .and_then(|r| r.get("pipeline_physio"))
            .and_then(|p| p.get("spo2"))
            .and_then(|v| v.as_f64())
            .map(|v| format!("{:.1}", v))
            .unwrap_or_default();

        let physio_event_trigger_count = point
            .run_report
            .as_ref()
            .and_then(|r| r.get("physio_event"))
            .and_then(|e| e.get("triggers"))
            .and_then(|v| v.as_array())
            .map(|arr| arr.len().to_string())
            .unwrap_or_default();

        let total_tokens = point
            .run_report
            .as_ref()
            .and_then(|r| r.get("llm_stats"))
            .and_then(|s| s.get("total_tokens"))
            .and_then(|v| v.as_u64())
            .map(|v| v.to_string())
            .unwrap_or_else(|| "".to_string());

        let grok3_calls = point
            .run_report
            .as_ref()
            .and_then(|r| r.get("llm_stats"))
            .and_then(|s| s.get("grok3_calls"))
            .and_then(|v| v.as_u64())
            .map(|v| v.to_string())
            .unwrap_or_else(|| "".to_string());

        let grok4_calls = point
            .run_report
            .as_ref()
            .and_then(|r| r.get("llm_stats"))
            .and_then(|s| s.get("grok4_calls"))
            .and_then(|v| v.as_u64())
            .map(|v| v.to_string())
            .unwrap_or_else(|| "".to_string());

        wtr.write_record(&[
            &point.tag.experiment_id,
            &point.tag.run_id,
            &point.tag.condition,
            &point.tag.triad_enabled.to_string(),
            &point.tag.hrv_aware.to_string(),
            &point.tag.serendipity_enabled.to_string(),
            &point.tag.space_aware.to_string(),
            &rating,
            &accepted,
            &clarity,
            &adequacy_of_tone,
            &usefulness,
            &safety_or_emotional_fit,
            &evaluator_id,
            &judgment_protocol,
            &blinded_item_id,
            physio_sev,
            env_sev,
            space_sev,
            &stress_index,
            experiment_condition_report,
            experiment_id_report,
            &pipeline_physio_snapshot_available,
            &pipeline_physio_used,
            pipeline_physio_hrv_level,
            &pipeline_physio_hr,
            &pipeline_physio_spo2,
            &physio_event_trigger_count,
            &total_tokens,
            &grok3_calls,
            &grok4_calls,
        ])?;
    }

    wtr.flush()?;
    let cursor = wtr
        .into_inner()
        .map_err(|e| anyhow::anyhow!("CSV writer error: {}", e))?;
    let bytes = cursor.into_inner();
    Ok(String::from_utf8(bytes)?)
}

/// Exporta resumo em formato JSON
pub fn export_summary_json(metrics: &ExperimentMetrics) -> anyhow::Result<String> {
    Ok(serde_json::to_string_pretty(metrics)?)
}

#[cfg(test)]
mod tests {
    use super::{calculate_metrics, join_experiment_data};
    use crate::ExperimentRunTag;
    use beagle_feedback::{
        create_human_feedback_event, create_pipeline_event, create_structured_human_feedback_event,
        StructuredHumanJudgment,
    };
    use chrono::Utc;
    use std::collections::HashMap;
    use std::path::PathBuf;

    #[test]
    fn join_prefers_explicit_human_judgment() {
        let tag = ExperimentRunTag {
            experiment_id: "exp-002".to_string(),
            run_id: "run-1".to_string(),
            condition: "hrv_aware".to_string(),
            timestamp: Utc::now(),
            notes: None,
            triad_enabled: false,
            hrv_aware: true,
            serendipity_enabled: false,
            space_aware: false,
        };
        let pipeline = create_pipeline_event(
            "run-1".to_string(),
            "Q".to_string(),
            PathBuf::from("/tmp/draft.md"),
            PathBuf::from("/tmp/draft.pdf"),
            Some("low".to_string()),
            Some("grok3".to_string()),
        );
        let human = create_structured_human_feedback_event(
            "run-1".to_string(),
            StructuredHumanJudgment {
                accepted: true,
                rating_0_10: Some(8),
                clarity_0_10: Some(9),
                adequacy_of_tone_0_10: Some(8),
                usefulness_0_10: Some(9),
                safety_or_emotional_fit_0_10: Some(8),
                notes: Some("blind pass".to_string()),
                evaluator_id: Some("eval-1".to_string()),
                judgment_protocol: Some("b17.5".to_string()),
                blinded_item_id: Some("item-001".to_string()),
            },
        );

        let joined = join_experiment_data(vec![tag], vec![pipeline, human], HashMap::new());
        assert_eq!(joined.len(), 1);
        let feedback = joined[0].feedback.as_ref().expect("feedback should exist");
        assert_eq!(feedback.rating_0_10, Some(8));
        assert_eq!(feedback.evaluator_id.as_deref(), Some("eval-1"));
    }

    #[test]
    fn metrics_count_only_real_human_feedback() {
        let tags = vec![
            ExperimentRunTag {
                experiment_id: "exp-002".to_string(),
                run_id: "run-aware".to_string(),
                condition: "hrv_aware".to_string(),
                timestamp: Utc::now(),
                notes: None,
                triad_enabled: false,
                hrv_aware: true,
                serendipity_enabled: false,
                space_aware: false,
            },
            ExperimentRunTag {
                experiment_id: "exp-002".to_string(),
                run_id: "run-blind".to_string(),
                condition: "hrv_blind".to_string(),
                timestamp: Utc::now(),
                notes: None,
                triad_enabled: false,
                hrv_aware: false,
                serendipity_enabled: false,
                space_aware: false,
            },
        ];

        let pipeline_only = create_pipeline_event(
            "run-aware".to_string(),
            "aware".to_string(),
            PathBuf::from("/tmp/a.md"),
            PathBuf::from("/tmp/a.pdf"),
            Some("low".to_string()),
            Some("grok3".to_string()),
        );
        let judged = create_human_feedback_event(
            "run-blind".to_string(),
            true,
            Some(7),
            Some("bounded human eval".to_string()),
        );

        let joined = join_experiment_data(tags, vec![pipeline_only, judged], HashMap::new());
        let metrics = calculate_metrics(&joined);
        assert_eq!(metrics.conditions["hrv_aware"].n_with_feedback, 0);
        assert_eq!(metrics.conditions["hrv_blind"].n_with_feedback, 1);
        assert_eq!(metrics.conditions["hrv_blind"].rating_mean, Some(7.0));
    }
}
