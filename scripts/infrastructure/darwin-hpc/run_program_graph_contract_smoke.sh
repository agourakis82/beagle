#!/usr/bin/env bash
set -euo pipefail

ROOT="${ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)}"
OUT="${OUT:-${ROOT}/.artifacts/darwin-hpc/program-graph-contract}"

DOC_FILE="${DOC_FILE:-${ROOT}/docs/darwin/hpc/B191_PROGRAM_GRAPH_AND_RESEARCH_CAMPAIGN_CONTRACT.md}"
GO_NO_GO_FILE="${GO_NO_GO_FILE:-${ROOT}/docs/darwin/hpc/B191_GO_NO_GO.md}"
KNOWN_LIMITS_FILE="${KNOWN_LIMITS_FILE:-${ROOT}/docs/darwin/hpc/B191_KNOWN_LIMITS.md}"
SCHEMA_FILE="${SCHEMA_FILE:-${ROOT}/docs/darwin/hpc/contracts/program-graph-schema.yaml}"
PROGRAMS_README_FILE="${PROGRAMS_README_FILE:-${ROOT}/docs/darwin/hpc/programs/README.md}"
CAMPAIGNS_README_FILE="${CAMPAIGNS_README_FILE:-${ROOT}/docs/darwin/hpc/campaigns/README.md}"
PROGRAM_FILE="${PROGRAM_FILE:-${ROOT}/docs/darwin/hpc/programs/beagle-physio-symbolic-exocortex.yaml}"
CAMPAIGN_GOVERNANCE_FILE="${CAMPAIGN_GOVERNANCE_FILE:-${ROOT}/docs/darwin/hpc/campaigns/darwin-hpc-governance.yaml}"
CAMPAIGN_EXP002_FILE="${CAMPAIGN_EXP002_FILE:-${ROOT}/docs/darwin/hpc/campaigns/expedition-002-hrv-aware.yaml}"
WORKSTREAM_REGISTRY_FILE="${WORKSTREAM_REGISTRY_FILE:-${ROOT}/docs/darwin/hpc/workstreams/registry.yaml}"

require() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "[FAIL] missing command: $1" >&2
    exit 1
  }
}

require jq
require python3
require rg

mkdir -p "${OUT}"

python3 - \
  "${ROOT}" \
  "${OUT}" \
  "${DOC_FILE}" \
  "${GO_NO_GO_FILE}" \
  "${KNOWN_LIMITS_FILE}" \
  "${SCHEMA_FILE}" \
  "${PROGRAMS_README_FILE}" \
  "${CAMPAIGNS_README_FILE}" \
  "${PROGRAM_FILE}" \
  "${CAMPAIGN_GOVERNANCE_FILE}" \
  "${CAMPAIGN_EXP002_FILE}" \
  "${WORKSTREAM_REGISTRY_FILE}" <<'PY'
from __future__ import annotations

import json
import sys
from pathlib import Path

import yaml

(
    root_arg,
    out_arg,
    doc_arg,
    go_no_go_arg,
    known_limits_arg,
    schema_arg,
    programs_readme_arg,
    campaigns_readme_arg,
    program_arg,
    governance_campaign_arg,
    expedition_campaign_arg,
    workstream_registry_arg,
) = sys.argv[1:]

root = Path(root_arg)
out = Path(out_arg)

paths = {
    "doc": Path(doc_arg),
    "go_no_go": Path(go_no_go_arg),
    "known_limits": Path(known_limits_arg),
    "schema": Path(schema_arg),
    "programs_readme": Path(programs_readme_arg),
    "campaigns_readme": Path(campaigns_readme_arg),
    "program": Path(program_arg),
    "campaign_governance": Path(governance_campaign_arg),
    "campaign_expedition_002": Path(expedition_campaign_arg),
    "workstream_registry": Path(workstream_registry_arg),
}


def rel(path: Path) -> str:
    return str(path.relative_to(root))


source_summary = {
    "status": "ok",
    "files": {
        name: {
            "path": rel(path),
            "present": path.exists(),
            "non_empty": path.exists() and path.stat().st_size > 0,
        }
        for name, path in paths.items()
    },
}

for meta in source_summary["files"].values():
    if not meta["present"] or not meta["non_empty"]:
        source_summary["status"] = "fail"

(out / "source-summary.json").write_text(json.dumps(source_summary, indent=2) + "\n")

if source_summary["status"] != "ok":
    raise SystemExit("required B19.1 source files are missing")


def load_yaml(path: Path):
    with path.open("r", encoding="utf-8") as fh:
        return yaml.safe_load(fh)


schema = load_yaml(paths["schema"])
program = load_yaml(paths["program"])
campaigns = [
    load_yaml(paths["campaign_governance"]),
    load_yaml(paths["campaign_expedition_002"]),
]
registry = load_yaml(paths["workstream_registry"])
registry_ids = [item["id"] for item in registry["workstreams"]]

required_program_fields = schema["entity_types"]["program"]["required_fields"]
required_campaign_fields = schema["entity_types"]["campaign"]["required_fields"]
required_experiment_fields = schema["entity_types"]["experiment"]["required_fields"]
required_evidence_fields = schema["entity_types"]["evidence_target"]["required_fields"]

program_missing_fields = [field for field in required_program_fields if field not in program]
campaign_missing_fields = {
    campaign["id"]: [field for field in required_campaign_fields if field not in campaign]
    for campaign in campaigns
}

program_summary = {
    "status": "ok",
    "program_id": program["id"],
    "title": program["title"],
    "status_value": program["status"],
    "program_kind": program["program_kind"],
    "source_phase": program["source_phase"],
    "north_star_present": bool(program.get("north_star", {}).get("statement", "").strip()),
    "campaign_count": len(program.get("campaigns", [])),
    "workstream_count": len(program.get("workstreams", [])),
    "experiment_count": len(program.get("experiments", [])),
    "evidence_target_count": len(program.get("evidence_targets", [])),
    "campaign_ids": [campaign["id"] for campaign in program.get("campaigns", [])],
    "workstream_ids": [item["id"] for item in program.get("workstreams", [])],
    "experiment_ids": [item["id"] for item in program.get("experiments", [])],
    "missing_required_fields": program_missing_fields,
}

if program_missing_fields or not program_summary["north_star_present"]:
    program_summary["status"] = "fail"

(out / "program-summary.json").write_text(
    json.dumps(program_summary, indent=2, sort_keys=True) + "\n"
)

campaign_summaries = []
for campaign in campaigns:
    missing_experiment_fields = {}
    for experiment in campaign.get("experiments", []):
        missing = [field for field in required_experiment_fields if field not in experiment]
        if missing:
            missing_experiment_fields[experiment.get("id", "<missing-id>")] = missing

    missing_evidence_fields = {}
    for target in campaign.get("evidence_targets", []):
        missing = [field for field in required_evidence_fields if field not in target]
        if missing:
            missing_evidence_fields[target.get("id", "<missing-id>")] = missing

    summary = {
        "id": campaign["id"],
        "program_id": campaign["program_id"],
        "title": campaign["title"],
        "status_value": campaign["status"],
        "campaign_kind": campaign["campaign_kind"],
        "source_phase": campaign["source_phase"],
        "workstream_ids": [item["id"] for item in campaign.get("workstreams", [])],
        "experiment_ids": [item["id"] for item in campaign.get("experiments", [])],
        "dataset_ids": [item["id"] for item in campaign.get("datasets", [])],
        "evidence_target_ids": [item["id"] for item in campaign.get("evidence_targets", [])],
        "missing_required_fields": campaign_missing_fields[campaign["id"]],
        "missing_experiment_fields": missing_experiment_fields,
        "missing_evidence_fields": missing_evidence_fields,
    }
    campaign_summaries.append(summary)

campaign_summary = {
    "status": "ok",
    "campaign_count": len(campaign_summaries),
    "campaigns": campaign_summaries,
}

if any(
    item["missing_required_fields"]
    or item["missing_experiment_fields"]
    or item["missing_evidence_fields"]
    for item in campaign_summaries
):
    campaign_summary["status"] = "fail"

(out / "campaign-summary.json").write_text(
    json.dumps(campaign_summary, indent=2, sort_keys=True) + "\n"
)

program_campaign_ids = [item["id"] for item in program.get("campaigns", [])]
program_campaign_files = {
    item["id"]: item["file"] for item in program.get("campaigns", [])
}
campaign_ids = [item["id"] for item in campaigns]
campaign_program_ids = {item["id"]: item["program_id"] for item in campaigns}
campaign_workstream_ids = {
    item["id"]: [ws["id"] for ws in item.get("workstreams", [])] for item in campaigns
}
campaign_experiment_ids = {
    item["id"]: [exp["id"] for exp in item.get("experiments", [])] for item in campaigns
}

missing_program_campaigns = sorted(set(program_campaign_ids) - set(campaign_ids))
campaign_file_resolution = {
    campaign_id: (root / file_path).exists()
    for campaign_id, file_path in program_campaign_files.items()
}
invalid_campaign_program_links = {
    campaign_id: program_id
    for campaign_id, program_id in campaign_program_ids.items()
    if program_id != program["id"]
}

referenced_workstream_ids = sorted(
    {
        ws["id"]
        for ws in program.get("workstreams", [])
    }
    | {
        ws_id
        for workstream_ids in campaign_workstream_ids.values()
        for ws_id in workstream_ids
    }
)
missing_workstreams = [
    workstream_id for workstream_id in referenced_workstream_ids if workstream_id not in registry_ids
]

experiment_doc_checks = []
for experiment in program.get("experiments", []):
    experiment_doc_checks.append(
        {
            "experiment_id": experiment["id"],
            "campaign_id": experiment["campaign_id"],
            "spec_doc": experiment["spec_doc"],
            "spec_doc_exists": (root / experiment["spec_doc"]).exists(),
            "results_doc": experiment["results_doc"],
            "results_doc_exists": (root / experiment["results_doc"]).exists(),
        }
    )

campaign_experiment_checks = []
for campaign in campaigns:
    for experiment in campaign.get("experiments", []):
        campaign_experiment_checks.append(
            {
                "campaign_id": campaign["id"],
                "experiment_id": experiment["id"],
                "spec_doc": experiment["spec_doc"],
                "spec_doc_exists": (root / experiment["spec_doc"]).exists(),
                "results_doc": experiment["results_doc"],
                "results_doc_exists": (root / experiment["results_doc"]).exists(),
            }
        )

evidence_target_checks = []
for target in program.get("evidence_targets", []):
    evidence_target_checks.append(
        {
            "scope": "program",
            "scope_id": program["id"],
            "target_id": target["id"],
            "kind": target["kind"],
            "path": target["path"],
            "path_exists": (root / target["path"]).exists(),
        }
    )
for campaign in campaigns:
    for target in campaign.get("evidence_targets", []):
        evidence_target_checks.append(
            {
                "scope": "campaign",
                "scope_id": campaign["id"],
                "target_id": target["id"],
                "kind": target["kind"],
                "path": target["path"],
                "path_exists": (root / target["path"]).exists(),
            }
        )

artifact_root_checks = []
for campaign in campaigns:
    for dataset in campaign.get("datasets", []):
        artifact_root = dataset.get("artifact_root")
        if artifact_root:
            artifact_root_checks.append(
                {
                    "campaign_id": campaign["id"],
                    "dataset_id": dataset["id"],
                    "artifact_root": artifact_root,
                    "artifact_root_exists": (root / artifact_root).exists(),
                }
            )

relation_summary = {
    "status": "ok",
    "program_contains_campaign": {
        "program_id": program["id"],
        "campaign_ids": program_campaign_ids,
        "campaign_files": program_campaign_files,
        "missing_campaigns": missing_program_campaigns,
        "campaign_file_resolution": campaign_file_resolution,
    },
    "campaign_uses_workstream": {
        "referenced_workstream_ids": referenced_workstream_ids,
        "registry_workstream_ids": registry_ids,
        "missing_workstreams": missing_workstreams,
        "campaign_workstream_ids": campaign_workstream_ids,
    },
    "campaign_runs_experiment": {
        "campaign_experiment_ids": campaign_experiment_ids,
        "program_experiment_ids": [item["id"] for item in program.get("experiments", [])],
        "program_experiment_docs": experiment_doc_checks,
        "campaign_experiment_docs": campaign_experiment_checks,
    },
    "result_informs_manuscript": {
        "evidence_targets": evidence_target_checks,
        "artifact_roots": artifact_root_checks,
    },
    "cross_links": {
        "invalid_campaign_program_links": invalid_campaign_program_links,
        "observer_context_contract": campaigns[1].get("observer_context", {}).get("contract"),
        "memory_context_contract": campaigns[1].get("memory_context", {}).get("query_contract"),
        "observer_contract_exists": (
            root / campaigns[1].get("observer_context", {}).get("contract", "")
        ).exists(),
        "memory_contract_exists": (
            root / campaigns[1].get("memory_context", {}).get("query_contract", "")
        ).exists(),
    },
}

if (
    missing_program_campaigns
    or not all(campaign_file_resolution.values())
    or missing_workstreams
    or invalid_campaign_program_links
    or not all(item["spec_doc_exists"] and item["results_doc_exists"] for item in experiment_doc_checks)
    or not all(item["spec_doc_exists"] and item["results_doc_exists"] for item in campaign_experiment_checks)
    or not all(item["path_exists"] for item in evidence_target_checks)
    or not all(item["artifact_root_exists"] for item in artifact_root_checks)
    or not relation_summary["cross_links"]["observer_contract_exists"]
    or not relation_summary["cross_links"]["memory_contract_exists"]
):
    relation_summary["status"] = "fail"

(out / "relation-summary.json").write_text(
    json.dumps(relation_summary, indent=2, sort_keys=True) + "\n"
)

consistency_summary = {
    "status": "ok",
    "phase": "B19.1",
    "schema_phase": schema["phase"],
    "schema_status": schema["status"],
    "program_id": program["id"],
    "program_status": program["status"],
    "campaign_ids": campaign_ids,
    "campaign_statuses": {campaign["id"]: campaign["status"] for campaign in campaigns},
    "program_kind": program["program_kind"],
    "campaign_kinds": {campaign["id"]: campaign["campaign_kind"] for campaign in campaigns},
    "matched_schema_phase": schema["phase"] == "B19.1",
    "matched_program_source_phase": program["source_phase"] == "B19.1",
    "matched_campaign_source_phases": all(campaign["source_phase"] == "B19.1" for campaign in campaigns),
    "canonical_program_present": program["id"] == "beagle-physio-symbolic-exocortex",
    "canonical_campaigns_present": sorted(campaign_ids)
    == ["darwin-hpc-governance", "expedition-002-hrv-aware"],
    "mapped_existing_workstreams": sorted(referenced_workstream_ids)
    == ["beagle-darwin-hpc-governance", "beagle-darwin-hpc-wave1"],
    "mapped_expedition_002": any(
        item["experiment_id"] == "beagle_exp_002_hrv_aware_vs_blind"
        and item["campaign_id"] == "expedition-002-hrv-aware"
        and item["spec_doc_exists"]
        and item["results_doc_exists"]
        for item in experiment_doc_checks
    ),
    "program_relations_ok": relation_summary["status"] == "ok",
    "required_relation_types_present": schema["relation_types"]
    == [
        "program_contains_campaign",
        "campaign_uses_workstream",
        "campaign_runs_experiment",
        "experiment_supports_result",
        "result_informs_manuscript",
        "physio_contextualizes_experiment",
    ],
}

if (
    program_summary["status"] != "ok"
    or campaign_summary["status"] != "ok"
    or relation_summary["status"] != "ok"
    or not consistency_summary["matched_schema_phase"]
    or not consistency_summary["matched_program_source_phase"]
    or not consistency_summary["matched_campaign_source_phases"]
    or not consistency_summary["canonical_program_present"]
    or not consistency_summary["canonical_campaigns_present"]
    or not consistency_summary["mapped_existing_workstreams"]
    or not consistency_summary["mapped_expedition_002"]
):
    consistency_summary["status"] = "fail"

(out / "consistency-summary.json").write_text(
    json.dumps(consistency_summary, indent=2, sort_keys=True) + "\n"
)

if consistency_summary["status"] != "ok":
    raise SystemExit("program graph consistency failed")
PY

echo "[OK] program graph contract smoke completed"
