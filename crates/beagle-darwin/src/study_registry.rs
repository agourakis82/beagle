use crate::replay_execution::ReplayExecutionReceipt;
use crate::run_capsule::RunCapsule;
use crate::run_diff::{read_run_diff, RunDiff};
use crate::study_dag::{StudyDag, StudyDagEdge, StudyDagNode, STUDY_DAG_KIND, STUDY_DAG_PHASE, STUDY_DAG_VERSION};
use crate::study_sweep::{StudySweep, StudySweepVariant, STUDY_SWEEP_KIND, STUDY_SWEEP_PHASE, STUDY_SWEEP_VERSION};
use crate::workspace_plane::workspace_plane_dir;
use anyhow::{anyhow, Context};
use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};
use std::collections::{BTreeMap, BTreeSet};
use std::fs;
use std::path::{Path, PathBuf};

const STUDY_REGISTRY_PHASE: &str = "B26.1";
const STUDY_REGISTRY_KIND: &str = "study-registry";
const STUDY_REGISTRY_VERSION: &str = "beagle-study-registry-v1";
const COMPARATIVE_RESULT_SUMMARY_KIND: &str = "comparative-result-summary";
const COMPARATIVE_RESULT_SUMMARY_VERSION: &str = "beagle-comparative-result-summary-v1";

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
pub struct StudyRunRegistration {
    pub run_id: String,
    pub run_label: String,
    pub submitted_job_id: u64,
    pub published_result_job_id: u64,
    pub selected_subagent_id: String,
    pub task_family: String,
    pub compute_profile_id: String,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub recipe_kind: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub experiment_id: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub source_branch: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub source_commit: Option<String>,
    pub source_dirty_state: String,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub source_fingerprint: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub replay_mode: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub source_run_id: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub replay_execution_id: Option<String>,
    pub run_role: String,
    pub same_beagle_owned_identity: bool,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
pub struct StudyRegistry {
    pub phase: String,
    pub contract_kind: String,
    pub contract_version: String,
    pub study_id: String,
    pub study_label: String,
    pub workstream_id: String,
    pub workspace_id: String,
    pub session_id: String,
    pub same_beagle_owned_identity: bool,
    pub created_at: DateTime<Utc>,
    pub updated_at: DateTime<Utc>,
    pub baseline_run_id: String,
    pub run_count: usize,
    pub variant_count: usize,
    pub run_ids: Vec<String>,
    pub variant_ids: Vec<String>,
    pub runs: Vec<StudyRunRegistration>,
    pub note: String,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
pub struct ComparativeRunSummary {
    pub run_id: String,
    pub run_label: String,
    pub run_role: String,
    pub submitted_job_id: u64,
    pub published_result_job_id: u64,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub source_run_id: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub replay_mode: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub source_branch: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub source_commit: Option<String>,
    pub source_dirty_state: String,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub source_fingerprint: Option<String>,
    pub changed_categories_vs_baseline: Vec<String>,
    pub same_beagle_owned_identity: bool,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
pub struct ComparativeResultSummary {
    pub phase: String,
    pub contract_kind: String,
    pub contract_version: String,
    pub comparative_result_summary_id: String,
    pub study_id: String,
    pub workstream_id: String,
    pub workspace_id: String,
    pub session_id: String,
    pub same_beagle_owned_identity: bool,
    pub generated_at: DateTime<Utc>,
    pub baseline_run_id: String,
    pub compared_run_count: usize,
    pub changed_categories_union: Vec<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub latest_run_diff_categories: Option<Vec<String>>,
    pub runs: Vec<ComparativeRunSummary>,
    pub note: String,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
pub struct StudyRegistrySweepBundle {
    pub status: String,
    pub phase: String,
    pub study_registry: StudyRegistry,
    pub study_dag: StudyDag,
    pub study_sweep: StudySweep,
    pub comparative_result_summary: ComparativeResultSummary,
}

pub fn ensure_study_registry_sweep(
    data_dir: &Path,
    workstream_id: &str,
    workspace_id: &str,
) -> anyhow::Result<StudyRegistrySweepBundle> {
    let capsules = read_run_capsules(data_dir, workspace_id)?;
    if capsules.is_empty() {
        return Err(anyhow!(
            "no run capsules available for workspace {}",
            workspace_id
        ));
    }
    let replay_executions = read_replay_executions(data_dir, workspace_id)?;

    let latest_capsule = capsules
        .iter()
        .max_by_key(|capsule| capsule.captured_at)
        .ok_or_else(|| anyhow!("latest run capsule missing for workspace {}", workspace_id))?;
    if latest_capsule.workstream_id != workstream_id {
        return Err(anyhow!(
            "run capsule workstream mismatch: expected '{}' but found '{}'",
            workstream_id,
            latest_capsule.workstream_id
        ));
    }

    let created_at = Utc::now();
    let study_id = format!(
        "{}-study-b261",
        sanitize_component(latest_capsule.session_id.as_str())
    );
    let study_label = format!(
        "b261-study-{}-{}",
        sanitize_component(latest_capsule.workspace_id.as_str()),
        sanitize_component(latest_capsule.session_id.as_str())
    );
    let baseline_run_id = baseline_run_id(&capsules, &replay_executions);
    let registry_runs = build_registry_runs(
        &capsules,
        &replay_executions,
        baseline_run_id.as_str(),
    );
    let capsule_index = capsules_by_id(&capsules);
    let same_beagle_owned_identity = registry_runs
        .iter()
        .all(|run| run.same_beagle_owned_identity)
        && registry_runs.iter().all(|run| {
            let capsule = capsule_index.get(run.run_id.as_str());
            match capsule {
                Some(capsule) => {
                    capsule.workstream_id == workstream_id
                        && capsule.workspace_id == workspace_id
                        && capsule.session_id == latest_capsule.session_id
                }
                None => false,
            }
        });

    let study_sweep = build_study_sweep(
        study_id.as_str(),
        latest_capsule,
        &registry_runs,
        &capsules,
        baseline_run_id.as_str(),
        created_at,
        same_beagle_owned_identity,
    );
    let study_registry = StudyRegistry {
        phase: STUDY_REGISTRY_PHASE.to_string(),
        contract_kind: STUDY_REGISTRY_KIND.to_string(),
        contract_version: STUDY_REGISTRY_VERSION.to_string(),
        study_id: study_id.clone(),
        study_label,
        workstream_id: workstream_id.to_string(),
        workspace_id: workspace_id.to_string(),
        session_id: latest_capsule.session_id.clone(),
        same_beagle_owned_identity,
        created_at,
        updated_at: created_at,
        baseline_run_id: baseline_run_id.clone(),
        run_count: registry_runs.len(),
        variant_count: study_sweep.variant_count,
        run_ids: registry_runs.iter().map(|run| run.run_id.clone()).collect(),
        variant_ids: study_sweep
            .variants
            .iter()
            .map(|variant| variant.variant_id.clone())
            .collect(),
        runs: registry_runs.clone(),
        note: "B26.1 registers one canonical bounded study inside the same Beagle workbench identity and ties multiple related runs through explicit run/variant bindings.".to_string(),
    };
    let study_dag = build_study_dag(
        &study_registry,
        &study_sweep,
        created_at,
    );
    let comparative_result_summary = build_comparative_result_summary(
        data_dir,
        &study_registry,
        &capsules,
        created_at,
    )?;

    write_study_registry(data_dir, workspace_id, &study_registry)?;
    write_study_dag(data_dir, workspace_id, &study_dag)?;
    write_study_sweep(data_dir, workspace_id, &study_sweep)?;
    write_comparative_result_summary(data_dir, workspace_id, &comparative_result_summary)?;

    Ok(StudyRegistrySweepBundle {
        status: "ok".to_string(),
        phase: STUDY_REGISTRY_PHASE.to_string(),
        study_registry,
        study_dag,
        study_sweep,
        comparative_result_summary,
    })
}

pub fn read_study_registry(
    data_dir: &Path,
    workspace_id: &str,
) -> anyhow::Result<Option<StudyRegistry>> {
    read_json(study_registry_path(data_dir, workspace_id))
}

pub fn read_study_dag(
    data_dir: &Path,
    workspace_id: &str,
) -> anyhow::Result<Option<StudyDag>> {
    read_json(study_dag_path(data_dir, workspace_id))
}

pub fn read_study_sweep(
    data_dir: &Path,
    workspace_id: &str,
) -> anyhow::Result<Option<StudySweep>> {
    read_json(study_sweep_path(data_dir, workspace_id))
}

pub fn read_comparative_result_summary(
    data_dir: &Path,
    workspace_id: &str,
) -> anyhow::Result<Option<ComparativeResultSummary>> {
    read_json(comparative_result_summary_path(data_dir, workspace_id))
}

fn build_study_sweep(
    study_id: &str,
    latest_capsule: &RunCapsule,
    registry_runs: &[StudyRunRegistration],
    capsules: &[RunCapsule],
    baseline_run_id: &str,
    generated_at: DateTime<Utc>,
    same_beagle_owned_identity: bool,
) -> StudySweep {
    let capsules_by_id = capsules_by_id(capsules);
    let mut variants = Vec::new();
    for run in registry_runs {
        let capsule = capsules_by_id.get(run.run_id.as_str());
        let variant_kind = if run.run_id == baseline_run_id {
            "baseline".to_string()
        } else if run.replay_mode.as_deref() == Some("bounded-workbench-branch-fork")
            || run.replay_mode.as_deref() == Some("branch-fork")
        {
            "branch-fork".to_string()
        } else if run.replay_mode.is_some() {
            "replay".to_string()
        } else {
            "direct".to_string()
        };
        let variant_id = format!(
            "{}-variant-{}",
            sanitize_component(study_id),
            sanitize_component(run.run_id.as_str())
        );
        variants.push(StudySweepVariant {
            variant_id,
            variant_label: format!("{}-{}", variant_kind, sanitize_component(run.run_label.as_str())),
            variant_kind,
            source_run_id: run.source_run_id.clone(),
            run_id: run.run_id.clone(),
            run_label: run.run_label.clone(),
            selected_subagent_id: run.selected_subagent_id.clone(),
            task_family: run.task_family.clone(),
            compute_profile_id: run.compute_profile_id.clone(),
            replay_mode: run.replay_mode.clone(),
            compiler_profile_id: capsule.and_then(|value| value.compiler_profile_id.clone()),
            graphrag_query_mode: capsule.and_then(|value| value.graphrag_query_mode.clone()),
            temporal_truth_view: capsule.and_then(|value| value.temporal_truth_view.clone()),
            recipe_kind: run.recipe_kind.clone(),
            experiment_id: run.experiment_id.clone(),
        });
    }
    variants.sort_by(|left, right| left.variant_label.cmp(&right.variant_label));
    let baseline_variant_id = variants
        .iter()
        .find(|variant| variant.run_id == baseline_run_id)
        .map(|variant| variant.variant_id.clone())
        .unwrap_or_else(|| {
            format!(
                "{}-variant-{}",
                sanitize_component(study_id),
                sanitize_component(baseline_run_id)
            )
        });
    StudySweep {
        phase: STUDY_SWEEP_PHASE.to_string(),
        contract_kind: STUDY_SWEEP_KIND.to_string(),
        contract_version: STUDY_SWEEP_VERSION.to_string(),
        study_sweep_id: format!("{}-study-sweep", sanitize_component(study_id)),
        study_id: study_id.to_string(),
        workstream_id: latest_capsule.workstream_id.clone(),
        workspace_id: latest_capsule.workspace_id.clone(),
        session_id: latest_capsule.session_id.clone(),
        same_beagle_owned_identity,
        generated_at,
        baseline_variant_id,
        variant_count: variants.len(),
        run_count: registry_runs.len(),
        variants,
        note: "B26.1 represents a bounded sweep as explicit baseline/replay/fork variants tied to canonical runs in the same workspace workbench lane.".to_string(),
    }
}

fn build_study_dag(
    registry: &StudyRegistry,
    sweep: &StudySweep,
    generated_at: DateTime<Utc>,
) -> StudyDag {
    let root_node_id = format!("{}-root", sanitize_component(registry.study_id.as_str()));
    let mut nodes = Vec::new();
    nodes.push(StudyDagNode {
        node_id: root_node_id.clone(),
        node_kind: "study".to_string(),
        label: registry.study_label.clone(),
        run_id: None,
        variant_id: None,
    });
    let mut edges = Vec::new();
    for variant in &sweep.variants {
        let variant_node_id = format!("{}-node", sanitize_component(variant.variant_id.as_str()));
        let run_node_id = format!("run-{}", sanitize_component(variant.run_id.as_str()));
        nodes.push(StudyDagNode {
            node_id: variant_node_id.clone(),
            node_kind: "variant".to_string(),
            label: variant.variant_label.clone(),
            run_id: Some(variant.run_id.clone()),
            variant_id: Some(variant.variant_id.clone()),
        });
        nodes.push(StudyDagNode {
            node_id: run_node_id.clone(),
            node_kind: "run".to_string(),
            label: variant.run_label.clone(),
            run_id: Some(variant.run_id.clone()),
            variant_id: Some(variant.variant_id.clone()),
        });
        edges.push(StudyDagEdge {
            edge_id: format!(
                "{}-contains-{}",
                sanitize_component(root_node_id.as_str()),
                sanitize_component(variant.variant_id.as_str())
            ),
            from_node_id: root_node_id.clone(),
            to_node_id: variant_node_id.clone(),
            relation: "contains-variant".to_string(),
        });
        edges.push(StudyDagEdge {
            edge_id: format!(
                "{}-executes-{}",
                sanitize_component(variant.variant_id.as_str()),
                sanitize_component(variant.run_id.as_str())
            ),
            from_node_id: variant_node_id,
            to_node_id: run_node_id.clone(),
            relation: "executes-run".to_string(),
        });
        if let Some(source_run_id) = &variant.source_run_id {
            edges.push(StudyDagEdge {
                edge_id: format!(
                    "{}-from-{}",
                    sanitize_component(variant.run_id.as_str()),
                    sanitize_component(source_run_id.as_str())
                ),
                from_node_id: format!("run-{}", sanitize_component(source_run_id.as_str())),
                to_node_id: run_node_id,
                relation: "derived-from-run".to_string(),
            });
        }
    }
    dedup_nodes(&mut nodes);
    dedup_edges(&mut edges);
    StudyDag {
        phase: STUDY_DAG_PHASE.to_string(),
        contract_kind: STUDY_DAG_KIND.to_string(),
        contract_version: STUDY_DAG_VERSION.to_string(),
        study_dag_id: format!("{}-study-dag", sanitize_component(registry.study_id.as_str())),
        study_id: registry.study_id.clone(),
        workstream_id: registry.workstream_id.clone(),
        workspace_id: registry.workspace_id.clone(),
        session_id: registry.session_id.clone(),
        same_beagle_owned_identity: registry.same_beagle_owned_identity,
        generated_at,
        root_node_id,
        node_count: nodes.len(),
        edge_count: edges.len(),
        nodes,
        edges,
        note: "B26.1 records a bounded study DAG linking study root, sweep variants, and concrete run nodes without introducing a parallel workflow engine.".to_string(),
    }
}

fn build_comparative_result_summary(
    data_dir: &Path,
    registry: &StudyRegistry,
    capsules: &[RunCapsule],
    generated_at: DateTime<Utc>,
) -> anyhow::Result<ComparativeResultSummary> {
    let capsules_by_id = capsules_by_id(capsules);
    let baseline = capsules_by_id
        .get(registry.baseline_run_id.as_str())
        .ok_or_else(|| anyhow!("baseline run {} missing from capsules", registry.baseline_run_id))?;
    let mut run_summaries = Vec::new();
    let mut changed_union = BTreeSet::new();
    for run in &registry.runs {
        let Some(capsule) = capsules_by_id.get(run.run_id.as_str()) else {
            continue;
        };
        let changed_categories = changed_categories_against_baseline(baseline, capsule);
        for category in &changed_categories {
            changed_union.insert(category.clone());
        }
        run_summaries.push(ComparativeRunSummary {
            run_id: run.run_id.clone(),
            run_label: run.run_label.clone(),
            run_role: run.run_role.clone(),
            submitted_job_id: run.submitted_job_id,
            published_result_job_id: run.published_result_job_id,
            source_run_id: run.source_run_id.clone(),
            replay_mode: run.replay_mode.clone(),
            source_branch: run.source_branch.clone(),
            source_commit: run.source_commit.clone(),
            source_dirty_state: run.source_dirty_state.clone(),
            source_fingerprint: run.source_fingerprint.clone(),
            changed_categories_vs_baseline: changed_categories,
            same_beagle_owned_identity: run.same_beagle_owned_identity
                && capsule.same_beagle_owned_identity,
        });
    }
    run_summaries.sort_by(|left, right| left.run_label.cmp(&right.run_label));
    let latest_run_diff_categories = read_run_diff(data_dir, &registry.workspace_id)?
        .map(|diff: RunDiff| diff.changed_categories);

    Ok(ComparativeResultSummary {
        phase: STUDY_REGISTRY_PHASE.to_string(),
        contract_kind: COMPARATIVE_RESULT_SUMMARY_KIND.to_string(),
        contract_version: COMPARATIVE_RESULT_SUMMARY_VERSION.to_string(),
        comparative_result_summary_id: format!(
            "{}-comparative-result-summary",
            sanitize_component(registry.study_id.as_str())
        ),
        study_id: registry.study_id.clone(),
        workstream_id: registry.workstream_id.clone(),
        workspace_id: registry.workspace_id.clone(),
        session_id: registry.session_id.clone(),
        same_beagle_owned_identity: registry.same_beagle_owned_identity
            && run_summaries
                .iter()
                .all(|summary| summary.same_beagle_owned_identity),
        generated_at,
        baseline_run_id: registry.baseline_run_id.clone(),
        compared_run_count: run_summaries.len(),
        changed_categories_union: changed_union.into_iter().collect(),
        latest_run_diff_categories,
        runs: run_summaries,
        note: "B26.1 produces a bounded comparative summary across related study runs so operators can inspect baseline vs variants without leaving the Beagle workbench identity plane.".to_string(),
    })
}

fn build_registry_runs(
    capsules: &[RunCapsule],
    replay_executions: &[ReplayExecutionReceipt],
    baseline_run_id: &str,
) -> Vec<StudyRunRegistration> {
    let capsules_by_id = capsules_by_id(capsules);
    let mut registrations = Vec::new();
    let mut seen = BTreeSet::new();

    for replay in replay_executions {
        for (run_id, role) in [
            (replay.source_run_id.as_str(), "source".to_string()),
            (replay.dispatched_run_id.as_str(), "variant".to_string()),
        ] {
            if !seen.insert(run_id.to_string()) {
                continue;
            }
            if let Some(capsule) = capsules_by_id.get(run_id) {
                registrations.push(StudyRunRegistration {
                    run_id: capsule.run_id.clone(),
                    run_label: capsule.run_label.clone(),
                    submitted_job_id: capsule.submitted_job_id,
                    published_result_job_id: capsule.published_result_job_id,
                    selected_subagent_id: capsule.selected_subagent_id.clone(),
                    task_family: capsule.task_family.clone(),
                    compute_profile_id: capsule.compute_profile_id.clone(),
                    recipe_kind: capsule.recipe_kind.clone(),
                    experiment_id: capsule.experiment_id.clone(),
                    source_branch: replay.source_branch.clone(),
                    source_commit: replay.source_commit.clone(),
                    source_dirty_state: replay.source_dirty_state.clone(),
                    source_fingerprint: replay.source_source_fingerprint.clone(),
                    replay_mode: Some(replay.replay_mode.clone()),
                    source_run_id: Some(replay.source_run_id.clone()),
                    replay_execution_id: Some(replay.replay_execution_id.clone()),
                    run_role: role,
                    same_beagle_owned_identity: replay.same_beagle_owned_identity
                        && capsule.same_beagle_owned_identity
                        && replay.workstream_id == capsule.workstream_id
                        && replay.workspace_id == capsule.workspace_id
                        && replay.session_id == capsule.session_id,
                });
            }
        }
    }

    let mut capsules_sorted = capsules.to_vec();
    capsules_sorted.sort_by_key(|capsule| capsule.captured_at);
    for capsule in capsules_sorted {
        if seen.insert(capsule.run_id.clone()) {
            registrations.push(StudyRunRegistration {
                run_id: capsule.run_id.clone(),
                run_label: capsule.run_label.clone(),
                submitted_job_id: capsule.submitted_job_id,
                published_result_job_id: capsule.published_result_job_id,
                selected_subagent_id: capsule.selected_subagent_id.clone(),
                task_family: capsule.task_family.clone(),
                compute_profile_id: capsule.compute_profile_id.clone(),
                recipe_kind: capsule.recipe_kind.clone(),
                experiment_id: capsule.experiment_id.clone(),
                source_branch: capsule.git.branch.clone(),
                source_commit: capsule.git.commit.clone(),
                source_dirty_state: display_option(capsule.code_provenance.as_ref().map(|code| code.dirty_state.as_str())),
                source_fingerprint: capsule
                    .source_fingerprint
                    .as_ref()
                    .map(|fingerprint| fingerprint.source_fingerprint.clone()),
                replay_mode: None,
                source_run_id: capsule.parent_run_id.clone(),
                replay_execution_id: None,
                run_role: if capsule.run_id == baseline_run_id {
                    "baseline".to_string()
                } else {
                    "direct".to_string()
                },
                same_beagle_owned_identity: capsule.same_beagle_owned_identity,
            });
        }
    }

    registrations.sort_by(|left, right| left.run_label.cmp(&right.run_label));
    registrations
}

fn baseline_run_id(capsules: &[RunCapsule], replay_executions: &[ReplayExecutionReceipt]) -> String {
    if let Some(first_replay) = replay_executions.iter().min_by_key(|receipt| receipt.recorded_at) {
        return first_replay.source_run_id.clone();
    }
    capsules
        .iter()
        .min_by_key(|capsule| capsule.captured_at)
        .map(|capsule| capsule.run_id.clone())
        .unwrap_or_default()
}

fn changed_categories_against_baseline(
    baseline: &RunCapsule,
    candidate: &RunCapsule,
) -> Vec<String> {
    let mut categories = Vec::new();
    let code_changed = baseline.git.branch != candidate.git.branch
        || baseline.git.commit != candidate.git.commit
        || baseline.git.tree_ish != candidate.git.tree_ish
        || baseline.git.patch_ref != candidate.git.patch_ref
        || baseline.git.dirty != candidate.git.dirty
        || baseline
            .source_fingerprint
            .as_ref()
            .map(|value| value.source_fingerprint.as_str())
            != candidate
                .source_fingerprint
                .as_ref()
                .map(|value| value.source_fingerprint.as_str());
    if code_changed {
        categories.push("code".to_string());
    }
    let config_changed = baseline.task_family != candidate.task_family
        || baseline.selected_subagent_id != candidate.selected_subagent_id
        || baseline.compute_profile_id != candidate.compute_profile_id
        || baseline.recipe_kind != candidate.recipe_kind
        || baseline.experiment_id != candidate.experiment_id
        || baseline.retrieval_query_type != candidate.retrieval_query_type
        || baseline.graphrag_query_mode != candidate.graphrag_query_mode
        || baseline.temporal_truth_view != candidate.temporal_truth_view
        || baseline.config_fingerprint != candidate.config_fingerprint;
    if config_changed {
        categories.push("config".to_string());
    }
    let environment_changed = baseline.environment.image_digest != candidate.environment.image_digest
        || baseline.environment.node_list != candidate.environment.node_list
        || baseline.environment.partition != candidate.environment.partition
        || baseline.environment.submit_mode != candidate.environment.submit_mode
        || baseline.environment.scheduler_kind != candidate.environment.scheduler_kind;
    if environment_changed {
        categories.push("environment".to_string());
    }
    let result_changed = baseline.published_result_job_id != candidate.published_result_job_id
        || baseline.published_result.job_id != candidate.published_result.job_id
        || baseline.published_result.state != candidate.published_result.state;
    if result_changed {
        categories.push("result".to_string());
    }
    categories
}

fn read_run_capsules(data_dir: &Path, workspace_id: &str) -> anyhow::Result<Vec<RunCapsule>> {
    let dir = workspace_plane_dir(data_dir)
        .join("run-capsules")
        .join(sanitize_component(workspace_id));
    read_json_dir::<RunCapsule>(&dir, "run capsule")
}

fn read_replay_executions(
    data_dir: &Path,
    workspace_id: &str,
) -> anyhow::Result<Vec<ReplayExecutionReceipt>> {
    let dir = workspace_plane_dir(data_dir)
        .join("replay-executions")
        .join(sanitize_component(workspace_id));
    read_json_dir::<ReplayExecutionReceipt>(&dir, "replay execution")
}

fn read_json_dir<T>(dir: &Path, label: &str) -> anyhow::Result<Vec<T>>
where
    T: for<'de> Deserialize<'de>,
{
    if !dir.exists() {
        return Ok(Vec::new());
    }
    let mut values = Vec::new();
    for entry in fs::read_dir(dir)
        .with_context(|| format!("failed to read {} dir {}", label, dir.display()))?
    {
        let entry = entry?;
        let path = entry.path();
        if path.extension().and_then(|value| value.to_str()) != Some("json") {
            continue;
        }
        let body = fs::read_to_string(&path)
            .with_context(|| format!("failed to read {} {}", label, path.display()))?;
        let value = serde_json::from_str::<T>(&body)
            .with_context(|| format!("failed to parse {} {}", label, path.display()))?;
        values.push(value);
    }
    Ok(values)
}

fn write_study_registry(
    data_dir: &Path,
    workspace_id: &str,
    registry: &StudyRegistry,
) -> anyhow::Result<()> {
    write_json(study_registry_path(data_dir, workspace_id), registry)
}

fn write_study_dag(
    data_dir: &Path,
    workspace_id: &str,
    dag: &StudyDag,
) -> anyhow::Result<()> {
    write_json(study_dag_path(data_dir, workspace_id), dag)
}

fn write_study_sweep(
    data_dir: &Path,
    workspace_id: &str,
    sweep: &StudySweep,
) -> anyhow::Result<()> {
    write_json(study_sweep_path(data_dir, workspace_id), sweep)
}

fn write_comparative_result_summary(
    data_dir: &Path,
    workspace_id: &str,
    summary: &ComparativeResultSummary,
) -> anyhow::Result<()> {
    write_json(comparative_result_summary_path(data_dir, workspace_id), summary)
}

fn write_json<T: Serialize>(path: PathBuf, value: &T) -> anyhow::Result<()> {
    if let Some(parent) = path.parent() {
        fs::create_dir_all(parent)
            .with_context(|| format!("failed to create dir {}", parent.display()))?;
    }
    let body = serde_json::to_string_pretty(value)?;
    fs::write(&path, body).with_context(|| format!("failed to write {}", path.display()))
}

fn read_json<T>(path: PathBuf) -> anyhow::Result<Option<T>>
where
    T: for<'de> Deserialize<'de>,
{
    if !path.exists() {
        return Ok(None);
    }
    let body = fs::read_to_string(&path)
        .with_context(|| format!("failed to read {}", path.display()))?;
    let value = serde_json::from_str::<T>(&body)
        .with_context(|| format!("failed to parse {}", path.display()))?;
    Ok(Some(value))
}

fn study_registry_path(data_dir: &Path, workspace_id: &str) -> PathBuf {
    workspace_plane_dir(data_dir)
        .join("study-registry")
        .join(format!("{}.json", sanitize_component(workspace_id)))
}

fn study_dag_path(data_dir: &Path, workspace_id: &str) -> PathBuf {
    workspace_plane_dir(data_dir)
        .join("study-dag")
        .join(format!("{}.json", sanitize_component(workspace_id)))
}

fn study_sweep_path(data_dir: &Path, workspace_id: &str) -> PathBuf {
    workspace_plane_dir(data_dir)
        .join("study-sweep")
        .join(format!("{}.json", sanitize_component(workspace_id)))
}

fn comparative_result_summary_path(data_dir: &Path, workspace_id: &str) -> PathBuf {
    workspace_plane_dir(data_dir)
        .join("comparative-result-summary")
        .join(format!("{}.json", sanitize_component(workspace_id)))
}

fn capsules_by_id(capsules: &[RunCapsule]) -> BTreeMap<&str, &RunCapsule> {
    capsules
        .iter()
        .map(|capsule| (capsule.run_id.as_str(), capsule))
        .collect()
}

fn dedup_nodes(nodes: &mut Vec<StudyDagNode>) {
    let mut seen = BTreeSet::new();
    nodes.retain(|node| seen.insert(node.node_id.clone()));
}

fn dedup_edges(edges: &mut Vec<StudyDagEdge>) {
    let mut seen = BTreeSet::new();
    edges.retain(|edge| seen.insert(edge.edge_id.clone()));
}

fn sanitize_component(value: &str) -> String {
    let sanitized = value
        .trim()
        .chars()
        .map(|character| {
            if character.is_ascii_alphanumeric() || character == '-' || character == '_' {
                character
            } else {
                '-'
            }
        })
        .collect::<String>();
    let compact = sanitized
        .split('-')
        .filter(|part| !part.is_empty())
        .collect::<Vec<_>>()
        .join("-");
    if compact.is_empty() {
        "value".to_string()
    } else {
        compact
    }
}

fn display_option(value: Option<&str>) -> String {
    value
        .map(str::trim)
        .filter(|value| !value.is_empty())
        .unwrap_or("unknown")
        .to_string()
}
