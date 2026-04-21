use crate::run_capsule::{
    read_latest_run_capsule, read_prior_run_capsule, read_replay_request, ReplayRequest,
    RunCapsule,
};
use anyhow::anyhow;
use serde::{Deserialize, Serialize};
use std::path::Path;

const RUN_DIFF_PHASE: &str = "B25.6";
const RUN_DIFF_KIND: &str = "run-diff";
const RUN_DIFF_VERSION: &str = "beagle-run-diff-v2";

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct RunDiffCategory {
    pub changed: bool,
    pub changed_fields: Vec<String>,
    pub prior_summary: String,
    pub current_summary: String,
    pub explanation: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct RunDiff {
    pub phase: String,
    pub contract_kind: String,
    pub contract_version: String,
    pub workstream_id: String,
    pub workspace_id: String,
    pub session_id: String,
    pub same_beagle_owned_identity: bool,
    pub current_run_id: String,
    pub prior_run_id: String,
    pub current_submitted_job_id: u64,
    pub prior_submitted_job_id: u64,
    pub lineage_relation: String,
    pub changed_categories: Vec<String>,
    pub code: RunDiffCategory,
    pub config: RunDiffCategory,
    pub environment: RunDiffCategory,
    pub result: RunDiffCategory,
    pub note: String,
}

pub fn read_run_diff(
    data_dir: &Path,
    workspace_id: &str,
) -> anyhow::Result<Option<RunDiff>> {
    let Some(current) = read_latest_run_capsule(data_dir, workspace_id)? else {
        return Ok(None);
    };
    let Some(prior) = read_prior_run_capsule(data_dir, workspace_id)? else {
        return Ok(None);
    };
    Ok(Some(generate_run_diff(&prior, &current)))
}

pub fn read_reproducibility_bundle(
    data_dir: &Path,
    workstream_id: &str,
    workspace_id: &str,
) -> anyhow::Result<Option<(RunCapsule, RunCapsule, RunDiff, ReplayRequest)>> {
    let Some(current) = read_latest_run_capsule(data_dir, workspace_id)? else {
        return Ok(None);
    };
    let Some(prior) = read_prior_run_capsule(data_dir, workspace_id)? else {
        return Ok(None);
    };
    let diff = generate_run_diff(&prior, &current);
    let replay_request = read_replay_request(data_dir, workstream_id, workspace_id)?
        .ok_or_else(|| anyhow!("latest replay request missing for workspace {}", workspace_id))?;
    Ok(Some((current, prior, diff, replay_request)))
}

pub fn generate_run_diff(prior: &RunCapsule, current: &RunCapsule) -> RunDiff {
    let code = code_diff(prior, current);
    let config = config_diff(prior, current);
    let environment = environment_diff(prior, current);
    let result = result_diff(prior, current);

    let mut changed_categories = Vec::new();
    if code.changed {
        changed_categories.push("code".to_string());
    }
    if config.changed {
        changed_categories.push("config".to_string());
    }
    if environment.changed {
        changed_categories.push("environment".to_string());
    }
    if result.changed {
        changed_categories.push("result".to_string());
    }

    let lineage_relation = if current.parent_run_id.as_deref() == Some(prior.run_id.as_str()) {
        "direct-parent".to_string()
    } else {
        "latest-two".to_string()
    };

    RunDiff {
        phase: RUN_DIFF_PHASE.to_string(),
        contract_kind: RUN_DIFF_KIND.to_string(),
        contract_version: RUN_DIFF_VERSION.to_string(),
        workstream_id: current.workstream_id.clone(),
        workspace_id: current.workspace_id.clone(),
        session_id: current.session_id.clone(),
        same_beagle_owned_identity: current.same_beagle_owned_identity
            && prior.same_beagle_owned_identity
            && current.workstream_id == prior.workstream_id
            && current.workspace_id == prior.workspace_id
            && current.session_id == prior.session_id,
        current_run_id: current.run_id.clone(),
        prior_run_id: prior.run_id.clone(),
        current_submitted_job_id: current.submitted_job_id,
        prior_submitted_job_id: prior.submitted_job_id,
        lineage_relation,
        changed_categories,
        code,
        config,
        environment,
        result,
        note: "B25.6 compares two run capsules in-place and makes code, config, environment, and result differences explicit with Git-aware code provenance bound to the same run lineage.".to_string(),
    }
}

fn code_diff(prior: &RunCapsule, current: &RunCapsule) -> RunDiffCategory {
    let prior_code = code_state_view(prior);
    let current_code = code_state_view(current);
    let mut changed_fields = Vec::new();
    if prior_code.repo_root != current_code.repo_root {
        changed_fields.push("code.repo_root".to_string());
    }
    if prior_code.branch != current_code.branch {
        changed_fields.push("code.branch".to_string());
    }
    if prior_code.commit != current_code.commit {
        changed_fields.push("code.commit".to_string());
    }
    if prior_code.tree_ish != current_code.tree_ish {
        changed_fields.push("code.tree_ish".to_string());
    }
    if prior_code.patch_ref != current_code.patch_ref {
        changed_fields.push("code.patch_ref".to_string());
    }
    if prior_code.dirty_state != current_code.dirty_state {
        changed_fields.push("code.dirty_state".to_string());
    }
    if prior_code.source_fingerprint != current_code.source_fingerprint {
        changed_fields.push("code.source_fingerprint".to_string());
    }
    if prior_code.lockfile_fingerprints != current_code.lockfile_fingerprints {
        changed_fields.push("code.lockfile_fingerprints".to_string());
    }
    RunDiffCategory {
        changed: !changed_fields.is_empty(),
        changed_fields,
        prior_summary: format_code_summary(&prior_code),
        current_summary: format_code_summary(&current_code),
        explanation: "The code diff tracks the Git-aware workspace snapshot Beagle captured for the run capsule: repo root, branch, commit, tree-ish, patch reference, dirty state, and source fingerprint. Missing fields remain explicit rather than guessed.".to_string(),
    }
}

fn config_diff(prior: &RunCapsule, current: &RunCapsule) -> RunDiffCategory {
    let mut changed_fields = Vec::new();
    if prior.selected_subagent_id != current.selected_subagent_id {
        changed_fields.push("selected_subagent_id".to_string());
    }
    if prior.task_family != current.task_family {
        changed_fields.push("task_family".to_string());
    }
    if prior.recipe_kind != current.recipe_kind {
        changed_fields.push("recipe_kind".to_string());
    }
    if prior.experiment_id != current.experiment_id {
        changed_fields.push("experiment_id".to_string());
    }
    if prior.retrieval_query_type != current.retrieval_query_type {
        changed_fields.push("retrieval_query_type".to_string());
    }
    if prior.retrieval_profile != current.retrieval_profile {
        changed_fields.push("retrieval_profile".to_string());
    }
    if prior.compiler_profile_id != current.compiler_profile_id {
        changed_fields.push("compiler_profile_id".to_string());
    }
    if prior.graphrag_query_mode != current.graphrag_query_mode {
        changed_fields.push("graphrag_query_mode".to_string());
    }
    if prior.temporal_truth_view != current.temporal_truth_view {
        changed_fields.push("temporal_truth_view".to_string());
    }
    if prior.config_fingerprint != current.config_fingerprint {
        changed_fields.push("config_fingerprint".to_string());
    }
    RunDiffCategory {
        changed: !changed_fields.is_empty(),
        changed_fields,
        prior_summary: format!(
            "subagent={} task_family={} recipe_kind={} experiment_id={} retrieval_query_type={} graphrag={} temporal={} fingerprint={}",
            prior.selected_subagent_id,
            prior.task_family,
            display_option(prior.recipe_kind.as_deref()),
            display_option(prior.experiment_id.as_deref()),
            display_option(prior.retrieval_query_type.as_deref()),
            display_option(prior.graphrag_query_mode.as_deref()),
            display_option(prior.temporal_truth_view.as_deref()),
            prior.config_fingerprint
        ),
        current_summary: format!(
            "subagent={} task_family={} recipe_kind={} experiment_id={} retrieval_query_type={} graphrag={} temporal={} fingerprint={}",
            current.selected_subagent_id,
            current.task_family,
            display_option(current.recipe_kind.as_deref()),
            display_option(current.experiment_id.as_deref()),
            display_option(current.retrieval_query_type.as_deref()),
            display_option(current.graphrag_query_mode.as_deref()),
            display_option(current.temporal_truth_view.as_deref()),
            current.config_fingerprint
        ),
        explanation: "The config diff isolates workload intent and reasoning configuration so Beagle can explain whether two runs differed because the plan changed rather than because the scheduler or result plane drifted.".to_string(),
    }
}

fn environment_diff(prior: &RunCapsule, current: &RunCapsule) -> RunDiffCategory {
    let mut changed_fields = Vec::new();
    if prior.compute_profile_id != current.compute_profile_id {
        changed_fields.push("compute_profile_id".to_string());
    }
    if prior.environment.scheduler_kind != current.environment.scheduler_kind {
        changed_fields.push("environment.scheduler_kind".to_string());
    }
    if prior.environment.submit_mode != current.environment.submit_mode {
        changed_fields.push("environment.submit_mode".to_string());
    }
    if prior.environment.image_reference != current.environment.image_reference {
        changed_fields.push("environment.image_reference".to_string());
    }
    if prior.environment.image_digest != current.environment.image_digest {
        changed_fields.push("environment.image_digest".to_string());
    }
    if prior.environment.node_list != current.environment.node_list {
        changed_fields.push("environment.node_list".to_string());
    }
    if prior.environment.partition != current.environment.partition {
        changed_fields.push("environment.partition".to_string());
    }
    RunDiffCategory {
        changed: !changed_fields.is_empty(),
        changed_fields,
        prior_summary: format!(
            "profile={} scheduler={} submit_mode={} image={} digest={} node={} partition={}",
            prior.compute_profile_id,
            prior.environment.scheduler_kind,
            prior.environment.submit_mode,
            display_option(prior.environment.image_reference.as_deref()),
            display_option(prior.environment.image_digest.as_deref()),
            display_option(prior.environment.node_list.as_deref()),
            display_option(prior.environment.partition.as_deref())
        ),
        current_summary: format!(
            "profile={} scheduler={} submit_mode={} image={} digest={} node={} partition={}",
            current.compute_profile_id,
            current.environment.scheduler_kind,
            current.environment.submit_mode,
            display_option(current.environment.image_reference.as_deref()),
            display_option(current.environment.image_digest.as_deref()),
            display_option(current.environment.node_list.as_deref()),
            display_option(current.environment.partition.as_deref())
        ),
        explanation: "The environment diff captures compute lane and runtime envelope changes, including profile, scheduler mode, image metadata when available, and execution placement.".to_string(),
    }
}

fn result_diff(prior: &RunCapsule, current: &RunCapsule) -> RunDiffCategory {
    let mut changed_fields = Vec::new();
    if prior.submitted_job_id != current.submitted_job_id {
        changed_fields.push("submitted_job_id".to_string());
    }
    if prior.published_result_job_id != current.published_result_job_id {
        changed_fields.push("published_result_job_id".to_string());
    }
    if prior.run_label != current.run_label {
        changed_fields.push("run_label".to_string());
    }
    if prior.published_result.artifact_manifest_key != current.published_result.artifact_manifest_key {
        changed_fields.push("published_result.artifact_manifest_key".to_string());
    }
    if prior.published_result.artifact_sha256 != current.published_result.artifact_sha256 {
        changed_fields.push("published_result.artifact_sha256".to_string());
    }
    if prior.result_refs.len() != current.result_refs.len() {
        changed_fields.push("result_refs.len".to_string());
    }
    RunDiffCategory {
        changed: !changed_fields.is_empty(),
        changed_fields,
        prior_summary: format!(
            "submitted_job_id={} published_result_job_id={} run_label={} manifest_key={} checksum={} refs={}",
            prior.submitted_job_id,
            prior.published_result_job_id,
            prior.run_label,
            prior.published_result.artifact_manifest_key,
            prior.published_result.artifact_sha256,
            prior.result_refs.len()
        ),
        current_summary: format!(
            "submitted_job_id={} published_result_job_id={} run_label={} manifest_key={} checksum={} refs={}",
            current.submitted_job_id,
            current.published_result_job_id,
            current.run_label,
            current.published_result.artifact_manifest_key,
            current.published_result.artifact_sha256,
            current.result_refs.len()
        ),
        explanation: "The result diff shows whether the published output, manifest identity, or checksum changed between runs, which is the minimum needed to explain regressions or successful variants.".to_string(),
    }
}

fn display_option(value: Option<&str>) -> &str {
    value.unwrap_or("none")
}

fn display_bool(value: Option<bool>) -> &'static str {
    match value {
        Some(true) => "true",
        Some(false) => "false",
        None => "unknown",
    }
}

#[derive(Debug, Clone, PartialEq, Eq)]
struct CodeStateView {
    repo_root: Option<String>,
    branch: Option<String>,
    commit: Option<String>,
    tree_ish: Option<String>,
    patch_ref: Option<String>,
    dirty_state: String,
    source_fingerprint: Option<String>,
    lockfile_fingerprints: Vec<String>,
}

fn code_state_view(capsule: &RunCapsule) -> CodeStateView {
    let lockfile_fingerprints = capsule
        .source_fingerprint
        .as_ref()
        .map(|fingerprint| {
            fingerprint
                .lockfile_fingerprints
                .iter()
                .map(|entry| format!("{}={}", entry.relative_path, entry.sha256))
                .collect::<Vec<_>>()
        })
        .unwrap_or_default();
    CodeStateView {
        repo_root: capsule
            .code_provenance
            .as_ref()
            .and_then(|value| value.repo_root.clone())
            .or_else(|| capsule.git.repo_root.clone()),
        branch: capsule
            .code_provenance
            .as_ref()
            .and_then(|value| value.branch.clone())
            .or_else(|| capsule.git.branch.clone()),
        commit: capsule
            .code_provenance
            .as_ref()
            .and_then(|value| value.commit.clone())
            .or_else(|| capsule.git.commit.clone()),
        tree_ish: capsule
            .code_provenance
            .as_ref()
            .and_then(|value| value.tree_ish.clone())
            .or_else(|| capsule.git.tree_ish.clone()),
        patch_ref: capsule
            .code_provenance
            .as_ref()
            .and_then(|value| value.patch_ref.clone())
            .or_else(|| capsule.git.patch_ref.clone()),
        dirty_state: capsule
            .code_provenance
            .as_ref()
            .map(|value| value.dirty_state.clone())
            .unwrap_or_else(|| display_bool(capsule.git.dirty).to_string()),
        source_fingerprint: capsule
            .code_provenance
            .as_ref()
            .map(|value| value.source_fingerprint.clone())
            .or_else(|| {
                capsule
                    .source_fingerprint
                    .as_ref()
                    .map(|value| value.source_fingerprint.clone())
            }),
        lockfile_fingerprints,
    }
}

fn format_code_summary(code: &CodeStateView) -> String {
    format!(
        "repo_root={} branch={} commit={} tree_ish={} patch_ref={} dirty_state={} source_fingerprint={} lockfiles={}",
        display_option(code.repo_root.as_deref()),
        display_option(code.branch.as_deref()),
        display_option(code.commit.as_deref()),
        display_option(code.tree_ish.as_deref()),
        display_option(code.patch_ref.as_deref()),
        code.dirty_state,
        display_option(code.source_fingerprint.as_deref()),
        code.lockfile_fingerprints.len()
    )
}

#[cfg(test)]
mod tests {
    use super::generate_run_diff;
    use crate::run_capsule::{
        RunCapsule, RunCapsuleEnvironmentSnapshot, RunCapsuleGitSnapshot, RunCapsuleInputManifest,
    };
    use crate::result_catalog::ResultCatalogEntry;
    use crate::workbench_result_binding::WorkbenchBoundResultRef;
    use chrono::Utc;

    #[test]
    fn detects_config_and_result_changes_between_capsules() {
        let base = RunCapsule {
            phase: "B25.5".to_string(),
            contract_kind: "run-capsule".to_string(),
            contract_version: "v1".to_string(),
            capsule_id: "capsule-a".to_string(),
            captured_at: Utc::now(),
            workstream_id: "ws".to_string(),
            workspace_id: "wk".to_string(),
            session_id: "sess".to_string(),
            same_beagle_owned_identity: true,
            run_id: "run-a".to_string(),
            parent_run_id: None,
            reservation_id: "res-a".to_string(),
            submitted_job_id: 1,
            published_result_job_id: 1,
            run_label: "run-a".to_string(),
            selected_subagent_id: "experiments".to_string(),
            task_family: "analysis".to_string(),
            compute_profile_id: "cpu-short-v1".to_string(),
            recipe_kind: Some("recipe-a".to_string()),
            experiment_id: Some("exp-a".to_string()),
            canonical_repo: "agourakis82/beagle".to_string(),
            canonical_branch: "main".to_string(),
            canonical_track: "darwin-hpc".to_string(),
            git: RunCapsuleGitSnapshot {
                repo_root: Some("/workspace/beagle".to_string()),
                branch: Some("main".to_string()),
                commit: Some("abc".to_string()),
                tree_ish: Some("tree-a".to_string()),
                patch_ref: None,
                dirty: Some(false),
            },
            environment: RunCapsuleEnvironmentSnapshot {
                scheduler_kind: "slurm".to_string(),
                submit_mode: "bounded".to_string(),
                image_reference: None,
                image_digest: None,
                node_list: Some("n1".to_string()),
                partition: Some("cpu".to_string()),
            },
            retrieval_query_type: Some("general".to_string()),
            retrieval_profile: Some("dense+sparse-hybrid".to_string()),
            compiler_profile_id: None,
            graphrag_query_mode: Some("local".to_string()),
            temporal_truth_view: Some("both".to_string()),
            config_fingerprint: "fingerprint-a".to_string(),
            code_provenance: None,
            workspace_snapshot: None,
            source_fingerprint: None,
            input_manifest: RunCapsuleInputManifest {
                requested_by: "partner-dev".to_string(),
                requester_role_id: "partner-dev".to_string(),
                intent_text: "run".to_string(),
                requested_run_label: "run-a".to_string(),
                retrieval_query_text: Some("query".to_string()),
                retrieval_query_type: Some("general".to_string()),
                retrieval_mode: Some("dense+sparse-hybrid".to_string()),
                dense_backend: Some("voyage".to_string()),
                sparse_backend: Some("local".to_string()),
                compiler_profile_id: None,
                graphrag_query_mode: Some("local".to_string()),
                temporal_truth_view: Some("both".to_string()),
                top_memory_ids: vec!["m1".to_string()],
                memory_hit_count: 1,
            },
            published_result: ResultCatalogEntry {
                artifact_bucket: "bucket".to_string(),
                artifact_manifest_key: "m1".to_string(),
                artifact_object_key: Some("o1".to_string()),
                artifact_prefix: "p1".to_string(),
                artifact_sha256: "sha-a".to_string(),
                end_time: None,
                exit_code: None,
                job_id: 1,
                job_name: "job-a".to_string(),
                node_list: "n1".to_string(),
                partition: Some("cpu".to_string()),
                profile_id: "cpu-short-v1".to_string(),
                publication_time: None,
                retention_scope: String::new(),
                run_label: "run-a".to_string(),
                source_phase: Some("B25.4".to_string()),
                source_run_id: Some("run-a".to_string()),
                start_time: None,
                state: "COMPLETED".to_string(),
                submit_time: None,
            },
            artifact_manifest: crate::object_results::JobArtifactManifest {
                artifact_mime_type: Some("application/json".to_string()),
                artifact_path: Some("/tmp/out.json".to_string()),
                artifact_sha256: Some("sha-a".to_string()),
                artifact_size: Some(1),
                cleanup_boundary: None,
                end_time: None,
                exit_code: Some(0),
                job_id: 1,
                job_name: Some("job-a".to_string()),
                node_list: Some("n1".to_string()),
                profile_id: Some("cpu-short-v1".to_string()),
                retention_scope: None,
                retrieval_time: None,
                run_label: Some("run-a".to_string()),
                start_time: None,
                state: Some("COMPLETED".to_string()),
                stderr_path: None,
                stdout_path: None,
                submit_time: None,
            },
            published_result_manifest: crate::object_results::ObjectResultManifest {
                artifact_source: None,
                end_time: None,
                exit_code: Some(0),
                gateway_retrieval_time: None,
                job_id: 1,
                job_name: Some("job-a".to_string()),
                manifest_format: Some("json".to_string()),
                manifest_object_key: "manifest-1".to_string(),
                node_list: Some("n1".to_string()),
                object_bucket: "bucket".to_string(),
                object_key: "obj-1".to_string(),
                object_manifest_resolved_key: Some("manifest-1".to_string()),
                object_retrieval_mode: Some("object".to_string()),
                partition: Some("cpu".to_string()),
                profile_id: Some("cpu-short-v1".to_string()),
                publication_target_id: None,
                publication_time: None,
                published_checksum: "sha-a".to_string(),
                published_objects: Vec::new(),
                retrieval_source: None,
                run_label: Some("run-a".to_string()),
                source_manifest_path: None,
                source_phase: None,
                source_run_id: None,
                start_time: None,
                state: Some("COMPLETED".to_string()),
                submit_time: None,
            },
            result_refs: vec![WorkbenchBoundResultRef {
                ref_id: "result-1".to_string(),
                ref_kind: "published-result".to_string(),
                locator: "/api/darwin/hpc/results/1".to_string(),
                summary: "result".to_string(),
            }],
            deterministic_result_lookup_scope: "submitted-job-and-run-label".to_string(),
            deterministic_identity_confirmed: true,
            note: "x".to_string(),
        };
        let mut current = base.clone();
        current.run_id = "run-b".to_string();
        current.parent_run_id = Some("run-a".to_string());
        current.submitted_job_id = 2;
        current.published_result_job_id = 2;
        current.git.commit = Some("def".to_string());
        current.git.tree_ish = Some("tree-b".to_string());
        current.compute_profile_id = "cpu-batch-v1".to_string();
        current.recipe_kind = Some("recipe-b".to_string());
        current.experiment_id = Some("exp-b".to_string());
        current.config_fingerprint = "fingerprint-b".to_string();
        current.run_label = "run-b".to_string();
        current.published_result.job_id = 2;
        current.published_result.run_label = "run-b".to_string();
        current.published_result.artifact_manifest_key = "m2".to_string();
        current.published_result.artifact_sha256 = "sha-b".to_string();
        current.environment.partition = Some("cpu-batch".to_string());

        let diff = generate_run_diff(&base, &current);
        assert_eq!(diff.lineage_relation, "direct-parent");
        assert!(diff.code.changed);
        assert!(diff.config.changed);
        assert!(diff.environment.changed);
        assert!(diff.result.changed);
        assert!(!diff.changed_categories.is_empty());
    }
}
