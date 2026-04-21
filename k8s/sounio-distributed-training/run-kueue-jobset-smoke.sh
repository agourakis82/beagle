#!/usr/bin/env bash
set -euo pipefail

if kubectl config current-context >/dev/null 2>&1; then
  k() { kubectl "$@"; }
elif sudo kubectl config current-context >/dev/null 2>&1; then
  k() { sudo kubectl "$@"; }
else
  echo "unable to find a working kubectl context via kubectl or sudo kubectl" >&2
  exit 1
fi

root="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
manifest="${root}/jobset-gpu-ddp-smoke-kueue.yaml"
jobset_name="sounio-gpu-ddp-kq"
namespace="beagle"
local_queue="${LOCAL_QUEUE:-hpc-training}"

"${root}/preflight.sh"

k get crd localqueues.kueue.x-k8s.io >/dev/null
k -n "${namespace}" get localqueue "${local_queue}" >/dev/null

k -n "${namespace}" delete jobset "${jobset_name}" --ignore-not-found --wait=true >/dev/null
for _ in $(seq 1 60); do
  old_pods="$(k -n "${namespace}" get pods -l jobset.sigs.k8s.io/jobset-name="${jobset_name}" --no-headers 2>/dev/null | wc -l | tr -d ' ')"
  old_jobs="$(k -n "${namespace}" get jobs -l jobset.sigs.k8s.io/jobset-name="${jobset_name}" --no-headers 2>/dev/null | wc -l | tr -d ' ')"
  if [[ "${old_pods}" == "0" && "${old_jobs}" == "0" ]]; then
    break
  fi
  sleep 2
done

k apply -f "${manifest}"

echo "== queue status =="
k -n "${namespace}" get localqueue "${local_queue}" -o wide

echo
echo "== workloads =="
k -n "${namespace}" get workloads -o wide || true

echo
echo "== waiting for JobSet child jobs =="
for _ in $(seq 1 120); do
  jobs_json="$(k -n "${namespace}" get jobs -l jobset.sigs.k8s.io/jobset-name=${jobset_name} -o json 2>/dev/null || echo '{"items":[]}' )"
  [[ -n "${jobs_json}" ]] || jobs_json='{"items":[]}'
  total="$(jq '.items | length' <<<"${jobs_json}")"
  complete="$(jq '[.items[] | select((.status.succeeded // 0) >= 1)] | length' <<<"${jobs_json}")"
  failed="$(jq '[.items[] | select((.status.failed // 0) >= 1)] | length' <<<"${jobs_json}")"
  if [[ "${failed}" -gt 0 ]]; then
    echo "FAIL: one or more child jobs failed" >&2
    break
  fi
  if [[ "${total}" -ge 2 && "${complete}" -eq "${total}" ]]; then
    break
  fi
  sleep 2
done

echo
echo "== placements =="
k -n "${namespace}" get jobs,pods -l jobset.sigs.k8s.io/jobset-name="${jobset_name}" -o wide

echo
echo "== logs =="
for job in $(k -n "${namespace}" get jobs -l jobset.sigs.k8s.io/jobset-name="${jobset_name}" -o jsonpath='{range .items[*]}{.metadata.name}{"\n"}{end}'); do
  echo "--- ${job} ---"
  k -n "${namespace}" logs "job/${job}" || true
done
