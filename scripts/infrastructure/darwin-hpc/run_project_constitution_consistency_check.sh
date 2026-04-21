#!/usr/bin/env bash
set -euo pipefail

ROOT="${ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)}"
OUT="${OUT:-${ROOT}/.artifacts/darwin-hpc/project-constitution-consistency-check}"

CHARTER_FILE="${CHARTER_FILE:-${ROOT}/docs/darwin/hpc/B152_ASPIRATIONAL_BEAGLE_CHARTER.md}"
GO_NO_GO_FILE="${GO_NO_GO_FILE:-${ROOT}/docs/darwin/hpc/B152_GO_NO_GO.md}"
KNOWN_LIMITS_FILE="${KNOWN_LIMITS_FILE:-${ROOT}/docs/darwin/hpc/B152_KNOWN_LIMITS.md}"
LINEAGE_FILE="${LINEAGE_FILE:-${ROOT}/docs/darwin/hpc/PROGRAM_LINEAGE.md}"
CONSTITUTION_FILE="${CONSTITUTION_FILE:-${ROOT}/docs/darwin/hpc/contracts/project-constitution.yaml}"
REGISTRY_FILE="${REGISTRY_FILE:-${ROOT}/docs/darwin/hpc/workstreams/registry.yaml}"
WORKSTREAM_SPEC_FILE="${WORKSTREAM_SPEC_FILE:-${ROOT}/docs/darwin/hpc/workstreams/beagle-darwin-hpc-governance.yaml}"
TOOL_BRIDGE_POLICY_FILE="${TOOL_BRIDGE_POLICY_FILE:-${ROOT}/docs/darwin/hpc/contracts/tool-bridge-policy.yaml}"
CONFIGMAP_FILE="${CONFIGMAP_FILE:-${ROOT}/k8s/beagle/configmap.yaml}"
DEPLOYMENT_FILE="${DEPLOYMENT_FILE:-${ROOT}/k8s/beagle/deployment.yaml}"
SERVICE_FILE="${SERVICE_FILE:-${ROOT}/k8s/beagle/service.yaml}"
CONTROL_ROOM_FILE="${CONTROL_ROOM_FILE:-${ROOT}/crates/beagle-darwin/src/workstream_control_room.rs}"
WORKSPACE_PLANE_FILE="${WORKSPACE_PLANE_FILE:-${ROOT}/crates/beagle-darwin/src/workspace_plane.rs}"
HTTP_DARWIN_HPC_FILE="${HTTP_DARWIN_HPC_FILE:-${ROOT}/apps/beagle-monorepo/src/http_darwin_hpc.rs}"
CORE_SERVER_FILE="${CORE_SERVER_FILE:-${ROOT}/apps/beagle-monorepo/src/bin/core_server.rs}"

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
  "${CHARTER_FILE}" \
  "${GO_NO_GO_FILE}" \
  "${KNOWN_LIMITS_FILE}" \
  "${LINEAGE_FILE}" \
  "${CONSTITUTION_FILE}" \
  "${REGISTRY_FILE}" \
  "${WORKSTREAM_SPEC_FILE}" \
  "${TOOL_BRIDGE_POLICY_FILE}" \
  "${CONFIGMAP_FILE}" \
  "${DEPLOYMENT_FILE}" \
  "${SERVICE_FILE}" \
  "${CONTROL_ROOM_FILE}" \
  "${WORKSPACE_PLANE_FILE}" \
  "${HTTP_DARWIN_HPC_FILE}" \
  "${CORE_SERVER_FILE}" <<'PY'
from __future__ import annotations

import json
import sys
from pathlib import Path

import yaml

(
    root_arg,
    out_arg,
    charter_arg,
    go_no_go_arg,
    known_limits_arg,
    lineage_arg,
    constitution_arg,
    registry_arg,
    workstream_arg,
    bridge_policy_arg,
    configmap_arg,
    deployment_arg,
    service_arg,
    control_room_arg,
    workspace_plane_arg,
    http_darwin_hpc_arg,
    core_server_arg,
) = sys.argv[1:]

root = Path(root_arg)
out = Path(out_arg)

paths = {
    "charter": Path(charter_arg),
    "go_no_go": Path(go_no_go_arg),
    "known_limits": Path(known_limits_arg),
    "lineage": Path(lineage_arg),
    "constitution": Path(constitution_arg),
    "registry": Path(registry_arg),
    "workstream_spec": Path(workstream_arg),
    "tool_bridge_policy": Path(bridge_policy_arg),
    "configmap": Path(configmap_arg),
    "deployment": Path(deployment_arg),
    "service": Path(service_arg),
    "control_room": Path(control_room_arg),
    "workspace_plane": Path(workspace_plane_arg),
    "http_darwin_hpc": Path(http_darwin_hpc_arg),
    "core_server": Path(core_server_arg),
}

source_summary = {
    "status": "ok",
    "files": {
        name: {
            "path": str(path.relative_to(root)),
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
    raise SystemExit("required constitutional source files are missing")


def load_yaml(path: Path):
    with path.open("r", encoding="utf-8") as fh:
        return yaml.safe_load(fh)


constitution = load_yaml(paths["constitution"])
registry = load_yaml(paths["registry"])
workstream = load_yaml(paths["workstream_spec"])
tool_bridge_policy = load_yaml(paths["tool_bridge_policy"])
configmap = load_yaml(paths["configmap"])
deployment = load_yaml(paths["deployment"])
service = load_yaml(paths["service"])

(out / "constitution-normalized.json").write_text(
    json.dumps(constitution, indent=2, sort_keys=True) + "\n"
)

configmap_data = configmap.get("data", {})
registry_entry = registry["workstreams"][0]
workstream_id = registry["registry"]["current_canonical_workstreams"][0]
cheap_lane = tool_bridge_policy["runtime"]

current_state_summary = {
    "status": "ok",
    "workstream_id": workstream_id,
    "registry_state": registry_entry["promotion_state"],
    "registry_last_transition": registry_entry["governance_last_transition"],
    "workstream_scope": workstream["scope"],
    "workstream_default_dev_plane": workstream["default_dev_plane"],
    "workstream_vm_fallback_role": workstream["vm_fallback_role"],
    "deployment_name": deployment["metadata"]["name"],
    "service_name": service["metadata"]["name"],
    "bind_addr": configmap_data["BEAGLE_BIND_ADDR"],
    "profile": configmap_data["BEAGLE_PROFILE"],
    "default_dev_plane": configmap_data["BEAGLE_WORKSPACE_DEFAULT_DEV_PLANE"],
    "vm_fallback_role": configmap_data["BEAGLE_WORKSPACE_VM_FALLBACK_ROLE"],
    "promotion_scope": configmap_data["BEAGLE_WORKSPACE_PROMOTION_SCOPE"],
    "cutover_workstream": configmap_data["BEAGLE_WORKSPACE_CUTOVER_WORKSTREAM"],
    "cutover_state": configmap_data["BEAGLE_WORKSPACE_CUTOVER_STATE"],
    "last_transition": configmap_data["BEAGLE_WORKSTREAM_LAST_TRANSITION"],
    "compute_profiles": {
        "default": configmap_data["BEAGLE_WORKSTREAM_DEFAULT_PROFILE"],
        "batch": configmap_data["BEAGLE_WORKSTREAM_BATCH_PROFILE"],
        "advanced": configmap_data["BEAGLE_WORKSTREAM_ADVANCED_PROFILE"],
    },
    "result_plane": {
        "publication": configmap_data["BEAGLE_WORKSTREAM_RESULT_PUBLICATION"],
        "retrieval": configmap_data["BEAGLE_WORKSTREAM_RESULT_RETRIEVAL"],
        "retention_policy": configmap_data["BEAGLE_WORKSTREAM_RESULT_RETENTION_POLICY"],
    },
    "consumer_policy": {
        "operator": configmap_data["BEAGLE_WORKSTREAM_OPERATOR_CONSUMER_POLICY"],
        "darwin_research": configmap_data["BEAGLE_WORKSTREAM_RESEARCH_CONSUMER_POLICY"],
    },
    "cheap_lane_status": cheap_lane["cheap_lane_matrix_status"],
    "cheap_lane_live_providers": cheap_lane["live_providers"],
    "cheap_lane_defaults": cheap_lane["canonical_defaults"],
}

(out / "current-state-summary.json").write_text(
    json.dumps(current_state_summary, indent=2, sort_keys=True) + "\n"
)

lineage_text = paths["lineage"].read_text(encoding="utf-8")
lineage_summary = {
    "status": "ok",
    "mentions": {
        "darwin_v2": "darwin-v2" in lineage_text,
        "B14_1": "B14.1" in lineage_text,
        "B14_2": "B14.2" in lineage_text,
        "B14_3": "B14.3" in lineage_text,
        "B14_4": "B14.4" in lineage_text,
        "B15_1": "B15.1" in lineage_text,
        "B15_2": "B15.2" in lineage_text,
        "workstream_os": "Workstream OS" in lineage_text,
    },
}
if not all(lineage_summary["mentions"].values()):
    lineage_summary["status"] = "fail"
(out / "lineage-summary.json").write_text(
    json.dumps(lineage_summary, indent=2, sort_keys=True) + "\n"
)

consistency_summary = {
    "status": "ok",
    "phase": constitution["phase"],
    "mode": constitution["mode"],
    "north_star_present": bool(
        constitution.get("north_star", {}).get("statement", "").strip()
    ),
    "operational_beagle_status": constitution["identity"]["operational_beagle"]["status"],
    "aspirational_beagle_status": constitution["identity"]["aspirational_beagle"]["status"],
    "matched_default_dev_plane": constitution["current_canonical_state"]["canonical_defaults"]["default_dev_plane"]
    == current_state_summary["default_dev_plane"]
    == workstream["default_dev_plane"],
    "matched_vm_fallback_role": constitution["current_canonical_state"]["canonical_defaults"]["vm_fallback_role"]
    == current_state_summary["vm_fallback_role"]
    == workstream["vm_fallback_role"],
    "matched_promotion_scope": constitution["current_canonical_state"]["canonical_defaults"]["promotion_scope"]
    == current_state_summary["promotion_scope"]
    == workstream["scope"],
    "matched_canonical_workstream": constitution["current_canonical_state"]["canonical_defaults"]["canonical_workstream"]
    == current_state_summary["cutover_workstream"]
    == workstream["id"]
    == workstream_id,
    "matched_governance_state": constitution["current_canonical_state"]["canonical_defaults"]["governance_state"]
    == current_state_summary["cutover_state"]
    == registry_entry["promotion_state"]
    == workstream["promotion_state"]["state"],
    "matched_governance_last_transition": constitution["current_canonical_state"]["canonical_defaults"]["governance_last_transition"]
    == current_state_summary["last_transition"]
    == registry_entry["governance_last_transition"]
    == workstream["promotion_state"]["last_transition"],
    "matched_compute_profiles": constitution["current_canonical_state"]["compute_profiles"]
    == current_state_summary["compute_profiles"]
    == workstream["compute_profiles"],
    "matched_result_plane": constitution["current_canonical_state"]["result_plane"]
    == current_state_summary["result_plane"]
    == workstream["result_plane"],
    "matched_cheap_lane_status": constitution["current_canonical_state"]["cheap_lane"]["status"]
    == current_state_summary["cheap_lane_status"],
    "matched_cheap_lane_live_providers": constitution["current_canonical_state"]["cheap_lane"]["live_providers"]
    == current_state_summary["cheap_lane_live_providers"],
    "matched_cheap_lane_defaults": constitution["current_canonical_state"]["cheap_lane"]["canonical_defaults"]
    == current_state_summary["cheap_lane_defaults"],
    "matched_live_service": constitution["current_canonical_state"]["live_service"]["deployment"]
    == current_state_summary["deployment_name"]
    and constitution["current_canonical_state"]["live_service"]["service"]
    == current_state_summary["service_name"]
    and constitution["current_canonical_state"]["live_service"]["bind_addr"]
    == current_state_summary["bind_addr"]
    and constitution["current_canonical_state"]["live_service"]["profile"]
    == current_state_summary["profile"],
    "matched_governance_model": constitution["workstream_model"]["governance_model"]
    == registry["registry"]["governance_model"],
    "matched_registry_root": constitution["workstream_model"]["registry_root"]
    == registry["registry"]["root"],
    "matched_recipe_root": constitution["workstream_model"]["recipe_root"]
    == registry["registry"]["recipe_root"],
    "matched_canonical_workstreams": constitution["workstream_model"]["canonical_workstreams"][0]["id"]
    == workstream_id,
    "matched_governance_states": constitution["governance_states"]["allowed_states"]
    == workstream["promotion_state"]["allowed_states"],
    "matched_governance_transitions": constitution["governance_states"]["allowed_transitions"]
    == workstream["promotion_state"]["allowed_transitions"],
    "matched_proven_phases": constitution["current_canonical_state"]["proven_phases"]
    == {
        "B14.1": "GO",
        "B14.2": "GO",
        "B14.3": "GO",
        "B14.4": "GO",
        "B15.1": "GO",
    },
    "lineage_ok": lineage_summary["status"] == "ok",
}

plane_files = {
    "workspace_session": root / constitution["canonical_planes"]["workspace_session"]["authority"],
    "control_room": root / constitution["canonical_planes"]["control_room"]["authority"],
    "provider_bridge": root / constitution["canonical_planes"]["provider_bridge"]["authority"],
}
consistency_summary["plane_authorities_present"] = all(path.exists() for path in plane_files.values())

if not all(
    [
        consistency_summary["north_star_present"],
        consistency_summary["matched_default_dev_plane"],
        consistency_summary["matched_vm_fallback_role"],
        consistency_summary["matched_promotion_scope"],
        consistency_summary["matched_canonical_workstream"],
        consistency_summary["matched_governance_state"],
        consistency_summary["matched_governance_last_transition"],
        consistency_summary["matched_compute_profiles"],
        consistency_summary["matched_result_plane"],
        consistency_summary["matched_cheap_lane_status"],
        consistency_summary["matched_cheap_lane_live_providers"],
        consistency_summary["matched_cheap_lane_defaults"],
        consistency_summary["matched_live_service"],
        consistency_summary["matched_governance_model"],
        consistency_summary["matched_registry_root"],
        consistency_summary["matched_recipe_root"],
        consistency_summary["matched_canonical_workstreams"],
        consistency_summary["matched_governance_states"],
        consistency_summary["matched_governance_transitions"],
        consistency_summary["matched_proven_phases"],
        consistency_summary["lineage_ok"],
        consistency_summary["plane_authorities_present"],
        consistency_summary["operational_beagle_status"] == "proven",
        consistency_summary["aspirational_beagle_status"] == "declared",
    ]
):
    consistency_summary["status"] = "fail"

(out / "consistency-summary.json").write_text(
    json.dumps(consistency_summary, indent=2, sort_keys=True) + "\n"
)
PY

echo "[OK] project constitution consistency artifacts written to ${OUT}"
