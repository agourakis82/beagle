#!/usr/bin/env bash
set -euo pipefail

ns="${KUBE_NAMESPACE:-beagle}"
runner="${RUNNER_DEPLOYMENT:-deploy/project-cockpit}"
endpoint="${SSM_PROBE_ENDPOINT:-http://ssm-probe-serving.beagle.svc.cluster.local:8002}"
model="${SSM_PROBE_MODEL:-}"
out_dir="${SSM_PROBE_OUT_DIR:-/tmp/sounio-ssm-probe}"
run_id="${SSM_PROBE_RUN_ID:-ssm-probe-$(date -u +%Y%m%dT%H%M%SZ)}"

mkdir -p "${out_dir}"
jsonl="${out_dir}/${run_id}.jsonl"
summary="${out_dir}/${run_id}.summary.json"

api() {
  local path="$1"
  shift
  kubectl -n "${ns}" exec "${runner}" -- curl -fsS "$@" "${endpoint}${path}"
}

if [[ -z "${model}" ]]; then
  model="$(api /v1/models | jq -r '.data[0].id')"
fi

emit_case() {
  local name="$1"
  local body="$2"
  local started elapsed response rc
  started="$(date +%s%3N)"
  set +e
  response="$(api /v1/chat/completions -H 'content-type: application/json' -d "${body}" 2>&1)"
  rc=$?
  set -e
  elapsed="$(( $(date +%s%3N) - started ))"
  if [[ "${rc}" -ne 0 ]]; then
    jq -nc --arg name "${name}" --argjson elapsed_ms "${elapsed}" \
      --argjson curl_rc "${rc}" --arg error "${response}" \
      '{case:$name, elapsed_ms:$elapsed_ms, error:$error, curl_rc:$curl_rc}' \
      | tee -a "${jsonl}"
    return 0
  fi
  jq -c --arg name "${name}" --argjson elapsed_ms "${elapsed}" \
    '{case:$name, elapsed_ms:$elapsed_ms, content:.choices[0].message.content, usage:.usage, probe:.sounio_probe}' \
    <<<"${response}" | tee -a "${jsonl}"
}

exact_body="$(jq -nc --arg model "${model}" '{
  model:$model,
  messages:[
    {role:"system", content:"You obey exactly."},
    {role:"user", content:"Reply with exactly: darwin-ssm-probe-ok"}
  ],
  max_tokens:16,
  temperature:0
}')"

json_body="$(jq -nc --arg model "${model}" '{
  model:$model,
  messages:[
    {role:"system", content:"Return only valid compact JSON. No markdown."},
    {role:"user", content:"Create a JSON object with keys lane, decision, reason. lane must be ssm-probe. decision must be keep. reason must be under 8 words."}
  ],
  max_tokens:96,
  temperature:0
}')"

agent_body="$(jq -nc --arg model "${model}" '{
  model:$model,
  messages:[
    {role:"system", content:"You are an internal cluster agent. Be concise. Any command or action that may mutate state must include RISKY."},
    {role:"user", content:"A Kubernetes job failed with Forbidden: serviceaccount project-cockpit cannot create jobs.batch in namespace beagle. Give exactly 3 next actions."}
  ],
  max_tokens:160,
  temperature:0
}')"

long_body="$(
  python3 - "${model}" <<'PY'
import json
import sys

model = sys.argv[1]
context = "\n".join(f"fact_{i}: filler" for i in range(500))
print(json.dumps({
    "model": model,
    "messages": [
        {"role": "system", "content": "Answer with only the requested value."},
        {"role": "user", "content": f"{context}\nsecret_key: sounio-long-context-ok\nWhat is the secret_key value?"},
    ],
    "max_tokens": 32,
    "temperature": 0,
}))
PY
)"

: > "${jsonl}"
emit_case exact "${exact_body}"
emit_case json "${json_body}"
emit_case agent_triage "${agent_body}"
emit_case long_context "${long_body}"

jq -s --arg run_id "${run_id}" --arg model "${model}" '
  def ok_exact: map(select(.case=="exact" and ((.content // "")|gsub("\\n";"") == "darwin-ssm-probe-ok")))|length == 1;
  def ok_json:
    (map(select(.case=="json"))[0].content // "") as $content
    | try ($content | fromjson | .lane == "ssm-probe" and .decision == "keep") catch false;
  def ok_agent:
    (map(select(.case=="agent_triage"))[0].content // "") as $content
    | ($content | contains("RISKY")) and (($content | split("\n") | length) <= 5);
  def ok_long:
    map(select(.case=="long_context" and ((.content // "")|contains("sounio-long-context-ok"))))|length == 1;
  {
    run_id:$run_id,
    model:$model,
    cases:length,
    errors: map(select(.error != null) | {case, error, curl_rc}),
    checks:{
      exact: ok_exact,
      json: ok_json,
      agent_risk: ok_agent,
      long_context: ok_long
    },
    aggregate:{
      total_completion_tokens:(map(.usage.completion_tokens // 0)|add),
      avg_tokens_per_second:(map(.probe.tokens_per_second // 0)|add / length),
      avg_wall_tokens_per_second:(
        map(((.usage.completion_tokens // 0) / (((.elapsed_ms // 1) | if . <= 0 then 1 else . end) / 1000)))
        | add / length
      ),
      max_gpu_used_mib:(map(.probe.gpu_memory_after.used_mib // 0)|max)
    },
    records:.
  }
' "${jsonl}" | tee "${summary}"

echo "[ssm-probe-matrix] jsonl=${jsonl}"
echo "[ssm-probe-matrix] summary=${summary}"
