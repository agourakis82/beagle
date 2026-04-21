#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib-kubeconfig.sh"
NS="${NS:-slurm-pilot}"
SLINKY_VERSION="${SLINKY_VERSION:-v1.1.0-rc1}"
WORKDIR="${WORKDIR:-/tmp/slurm-operator-${SLINKY_VERSION}}"
EXTERNAL_DB_HOST="${EXTERNAL_DB_HOST:-slurmdbd-mariadb-ext.darwin.lan}"
EXTERNAL_DB_PORT="${EXTERNAL_DB_PORT:-3306}"
EXTERNAL_DB_VALUES_FILE="${EXTERNAL_DB_VALUES_FILE:-${REPO_ROOT}/values/slurm-pilot-values.external-db.example.yaml}"
SMOKE_PARTITION="${SMOKE_PARTITION:-}"
ROLLBACK_ON_FAILURE="${ROLLBACK_ON_FAILURE:-yes}"
export KUBECONFIG="${KUBECONFIG_PATH}"
CUTOVER_APPLIED="no"

if [[ ! -d "${WORKDIR}/helm/slurm" ]]; then
  echo "missing ${WORKDIR}/helm/slurm; run 20-install-slurm-operator.sh first" >&2
  exit 1
fi

if [[ ! -f "${EXTERNAL_DB_VALUES_FILE}" ]]; then
  echo "missing external DB overlay: ${EXTERNAL_DB_VALUES_FILE}" >&2
  exit 1
fi

ACTIVE_JOBS="$(kubectl -n "${NS}" exec deploy/slurm-pilot-login-slinky -- bash -lc 'squeue -h | wc -l' | tr -d '[:space:]')"
if [[ "${ACTIVE_JOBS}" != "0" && "${FORCE_BUSY:-no}" != "yes" ]]; then
  echo "active Slurm jobs detected (${ACTIVE_JOBS}); aborting cutover. Set FORCE_BUSY=yes to override." >&2
  exit 1
fi

trap '
  status=$?
  if [[ $status -ne 0 && "${ROLLBACK_ON_FAILURE}" == "yes" && "${CUTOVER_APPLIED}" == "yes" ]]; then
    echo "cutover failed; attempting rollback to host-local backend"
    bash "${REPO_ROOT}/scripts/28-rollback-slurmdbd-to-host-db.sh" || true
  fi
  exit $status
' EXIT

echo "taking fresh accounting snapshot"
sudo bash "${REPO_ROOT}/scripts/19-export-slurmdbd-snapshot.sh"

echo "preflight against ${EXTERNAL_DB_HOST}:${EXTERNAL_DB_PORT}"
EXTERNAL_DB_HOST="${EXTERNAL_DB_HOST}" EXTERNAL_DB_PORT="${EXTERNAL_DB_PORT}" \
  bash "${REPO_ROOT}/scripts/25-preflight-external-slurmdbd-db.sh"

echo "cutting over slurm-pilot accounting backend"
CUTOVER_APPLIED="yes"
helm upgrade slurm-pilot "${WORKDIR}/helm/slurm" \
  --reset-values \
  --namespace "${NS}" \
  -f "${REPO_ROOT}/values/slurm-pilot-values.yaml" \
  -f "${EXTERNAL_DB_VALUES_FILE}" \
  --wait --timeout 20m

kubectl -n "${NS}" rollout status statefulset/slurm-pilot-accounting --timeout=10m
KUBECONFIG_PATH="${KUBECONFIG_PATH}" TIMEOUT_SECONDS=120 INTERVAL_SECONDS=5 \
  bash "${REPO_ROOT}/scripts/29-wait-slurm-accounting-ready.sh"
kubectl -n "${NS}" exec sts/slurm-pilot-accounting -- bash -lc "grep -nE 'Storage(Type|Host|Port|User|Loc)' /etc/slurm/slurmdbd.conf"
kubectl -n "${NS}" exec deploy/slurm-pilot-login-slinky -- bash -lc 'sacctmgr list cluster && echo --- && sacct -n -X -S now-2hours -o JobID,Partition,State,Elapsed | tail -n 20'

if [[ -z "${SMOKE_PARTITION}" ]]; then
  SMOKE_PARTITION="$(
    kubectl -n "${NS}" exec deploy/slurm-pilot-login-slinky -- \
      sinfo -h -o '%P' | sed 's/*//g' | sed '/^$/d' | head -n1
  )"
  SMOKE_PARTITION="$(echo "${SMOKE_PARTITION}" | tr -d '[:space:]')"
fi

if [[ -z "${SMOKE_PARTITION}" ]]; then
  echo "could not determine a valid Slurm partition for smoke validation" >&2
  exit 1
fi

echo "using smoke partition ${SMOKE_PARTITION}"

SMOKE_CMD='printf "%s\n" "#!/bin/bash" "echo slurmdbd-cutover-smoke" "hostname" "sleep 1" > /tmp/slurmdbd-cutover-smoke.sbatch && chmod +x /tmp/slurmdbd-cutover-smoke.sbatch && sbatch -p '"${SMOKE_PARTITION}"' --parsable /tmp/slurmdbd-cutover-smoke.sbatch'
SMOKE_JOB_ID="$(
  kubectl -n "${NS}" exec deploy/slurm-pilot-login-slinky -- bash -lc "${SMOKE_CMD}"
)"
SMOKE_JOB_ID="$(echo "${SMOKE_JOB_ID}" | tr -d '[:space:]')"
echo "submitted smoke job ${SMOKE_JOB_ID}"

kubectl -n "${NS}" exec deploy/slurm-pilot-login-slinky -- bash -lc \
  "timeout 120 bash -lc 'while squeue -h -j ${SMOKE_JOB_ID} | grep -q .; do sleep 2; done' && sacct -j ${SMOKE_JOB_ID} --format=JobID,JobName,Partition,State,Elapsed -P"

trap - EXIT
echo "cutover complete"
