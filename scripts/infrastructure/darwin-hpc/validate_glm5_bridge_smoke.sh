#!/usr/bin/env bash
set -euo pipefail

OUT="${OUT:?OUT is required}"

require() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "[FAIL] missing command: $1" >&2
    exit 1
  }
}

require jq

for file in \
  provider-summary.json \
  health.json \
  providers.json \
  execute-glm5.json \
  ledger-tail.jsonl \
  smoke.json \
  final-cluster-health.txt \
  expected-provider.txt \
  expected-model.txt \
  request-id.txt; do
  [[ -s "${OUT}/${file}" ]] || {
    echo "[FAIL] missing or empty artifact: ${OUT}/${file}" >&2
    exit 1
  }
done

EXPECTED_PROVIDER="$(cat "${OUT}/expected-provider.txt")"
EXPECTED_MODEL="$(cat "${OUT}/expected-model.txt")"
REQUEST_ID="$(cat "${OUT}/request-id.txt")"

jq -e \
  --arg expected_provider "${EXPECTED_PROVIDER}" \
  --arg expected_model "${EXPECTED_MODEL}" '
  .expected_provider == $expected_provider
  and .expected_model == $expected_model
  and (.source_execute_present == true or .source_execute_present == 1)
  and (.source_provider_present == true or .source_provider_present == 1)
  and (.secret_template_present == true or .secret_template_present == 1)
' "${OUT}/provider-summary.json" >/dev/null

jq -e '.status == "ok" and .ledger_enabled == true' "${OUT}/health.json" >/dev/null

jq -e \
  --arg expected_provider "${EXPECTED_PROVIDER}" \
  --arg expected_model "${EXPECTED_MODEL}" '
  map(select(.provider == $expected_provider)) | length == 1
  and (
    map(select(.provider == $expected_provider))[0].implemented == true
    and map(select(.provider == $expected_provider))[0].cluster_callable == true
    and map(select(.provider == $expected_provider))[0].default_model == $expected_model
  )
' "${OUT}/providers.json" >/dev/null

EXECUTE_STATUS="$(jq -r '.status // empty' "${OUT}/execute-glm5.json")"
EXECUTE_ERROR="$(jq -r '.error // empty' "${OUT}/execute-glm5.json")"

if [[ "${EXECUTE_STATUS}" != "success" ]]; then
  if [[ "${EXECUTE_ERROR}" == *"429 Too Many Requests"* ]] \
    || [[ "${EXECUTE_ERROR}" == *"余额不足"* ]] \
    || [[ "${EXECUTE_ERROR}" == *"无可用资源包"* ]]; then
    echo "[BLOCKER] glm5 live execute reached the provider but failed for external quota/balance reasons: ${EXECUTE_ERROR}" >&2
    exit 2
  fi

  echo "[FAIL] glm5 execute did not succeed: ${EXECUTE_ERROR:-status=${EXECUTE_STATUS}}" >&2
  exit 1
fi

jq -e \
  --arg expected_provider "${EXPECTED_PROVIDER}" \
  --arg expected_model "${EXPECTED_MODEL}" '
  .status == "success"
  and .provider == $expected_provider
  and .model == $expected_model
  and ((.output.text // "") | length) > 0
' "${OUT}/execute-glm5.json" >/dev/null

grep -Fq "\"request_id\":\"${REQUEST_ID}\"" "${OUT}/ledger-tail.jsonl"
grep -Fq "\"provider\":\"${EXPECTED_PROVIDER}\"" "${OUT}/ledger-tail.jsonl"
grep -Fq "\"success\":true" "${OUT}/ledger-tail.jsonl"

jq -e \
  --arg request_id "${REQUEST_ID}" \
  --arg expected_provider "${EXPECTED_PROVIDER}" \
  --arg expected_model "${EXPECTED_MODEL}" '
  .request_id == $request_id
  and .expected_provider == $expected_provider
  and .expected_model == $expected_model
  and .execute_status == "success"
  and .execute_provider == $expected_provider
  and .execute_model == $expected_model
' "${OUT}/smoke.json" >/dev/null

grep -Fq "deployment.apps/beagle-core" "${OUT}/final-cluster-health.txt"
grep -Fq "darwin-hpc-gateway" "${OUT}/final-cluster-health.txt"

echo "[OK] glm5 bridge smoke validation passed"
