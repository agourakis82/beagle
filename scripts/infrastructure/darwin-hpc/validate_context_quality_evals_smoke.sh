#!/usr/bin/env bash
set -euo pipefail

ROOT="${ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)}"
OUT="${OUT:-${ROOT}/.artifacts/darwin-hpc/context-quality-evals}"

require_file() {
  local path="$1"
  [[ -f "${path}" ]] || {
    echo "[FAIL] missing file: ${path}" >&2
    exit 1
  }
}

require_file "${OUT}/source-summary.json"
require_file "${OUT}/eval-cases.json"
require_file "${OUT}/implementation-policy-comparison.json"
require_file "${OUT}/analysis-policy-comparison.json"
require_file "${OUT}/manuscript-policy-comparison.json"
require_file "${OUT}/compiler-eval-report.json"
require_file "${OUT}/compiler-policy.json"
require_file "${OUT}/compiler-eval-report-after-restart.json"
require_file "${OUT}/smoke.json"
require_file "${OUT}/final-cluster-health.txt"

jq -e '.doc_present == 1' "${OUT}/source-summary.json" >/dev/null
jq -e '.go_no_go_present == 1' "${OUT}/source-summary.json" >/dev/null
jq -e '.known_limits_present == 1' "${OUT}/source-summary.json" >/dev/null
jq -e '.eval_case_contract_present == 1' "${OUT}/source-summary.json" >/dev/null
jq -e '.eval_report_contract_present == 1' "${OUT}/source-summary.json" >/dev/null
jq -e '.policy_contract_present == 1' "${OUT}/source-summary.json" >/dev/null
jq -e '.prior_compiler_artifacts_present == 1' "${OUT}/source-summary.json" >/dev/null

jq -e '.report_version == "beagle-compiler-eval-report-v1"' "${OUT}/eval-cases.json" >/dev/null
jq -e '.cases | length == 3' "${OUT}/eval-cases.json" >/dev/null
jq -e '[.cases[].task_profile] == ["implementation","analysis","manuscript"]' "${OUT}/eval-cases.json" >/dev/null

jq -e '.compiler_id == "b235-query-adaptive-memory-compiler"' "${OUT}/compiler-eval-report.json" >/dev/null
jq -e '.report_version == "beagle-compiler-eval-report-v1"' "${OUT}/compiler-eval-report.json" >/dev/null
jq -e '.comparisons | length == 3' "${OUT}/compiler-eval-report.json" >/dev/null

jq -e '.task_profile == "implementation"' "${OUT}/implementation-policy-comparison.json" >/dev/null
jq -e '.variants | length >= 2' "${OUT}/implementation-policy-comparison.json" >/dev/null
jq -e '.selected_budget_profile_id == "b235-budget-implementation"' "${OUT}/implementation-policy-comparison.json" >/dev/null

jq -e '.task_profile == "analysis"' "${OUT}/analysis-policy-comparison.json" >/dev/null
jq -e '.variants | length >= 3' "${OUT}/analysis-policy-comparison.json" >/dev/null
jq -e '.selected_budget_profile_id == "b235-budget-analysis"' "${OUT}/analysis-policy-comparison.json" >/dev/null

jq -e '.task_profile == "manuscript"' "${OUT}/manuscript-policy-comparison.json" >/dev/null
jq -e '.variants | length >= 2' "${OUT}/manuscript-policy-comparison.json" >/dev/null
jq -e '.selected_budget_profile_id == "b235-budget-manuscript"' "${OUT}/manuscript-policy-comparison.json" >/dev/null

jq -e '.policy_id == "b236-evidence-backed-compiler-policy"' "${OUT}/compiler-policy.json" >/dev/null
jq -e '.profiles | length == 3' "${OUT}/compiler-policy.json" >/dev/null
jq -e '[.profiles[].task_profile] == ["implementation","analysis","manuscript"]' "${OUT}/compiler-policy.json" >/dev/null
jq -e 'all(.profiles[]; (.evidence_basis | length) >= 4)' "${OUT}/compiler-policy.json" >/dev/null

jq -e '.phase == "B23.6"' "${OUT}/smoke.json" >/dev/null
jq -e '.compiler_id == "b235-query-adaptive-memory-compiler"' "${OUT}/smoke.json" >/dev/null
jq -e '.implementation_selected_budget_profile_id == "b235-budget-implementation"' "${OUT}/smoke.json" >/dev/null
jq -e '.analysis_selected_budget_profile_id == "b235-budget-analysis"' "${OUT}/smoke.json" >/dev/null
jq -e '.manuscript_selected_budget_profile_id == "b235-budget-manuscript"' "${OUT}/smoke.json" >/dev/null
jq -e '.policy_profile_count == 3' "${OUT}/smoke.json" >/dev/null
jq -e '.restart_recovered_session == true' "${OUT}/smoke.json" >/dev/null

grep -q 'Slurmctld(primary)' "${OUT}/final-cluster-health.txt"
grep -q 'beagle-core' "${OUT}/final-cluster-health.txt"

echo "[OK] context quality eval smoke artifacts validated"
