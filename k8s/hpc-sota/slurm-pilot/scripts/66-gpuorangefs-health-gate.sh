#!/usr/bin/env bash
set -euo pipefail

NS="${NS:-slurm-pilot}"
KUBE_NS="${KUBE_NS:-kube-system}"
NODE=""
AUTO_ADMIT="${AUTO_ADMIT:-0}"
AUTO_QUARANTINE="${AUTO_QUARANTINE:-0}"
KEEP_NETCHECK_POD="${KEEP_NETCHECK_POD:-0}"
SMOKE_TIMEOUT_SECS="${SMOKE_TIMEOUT_SECS:-120}"

usage() {
  cat <<'EOF'
usage: 66-gpuorangefs-health-gate.sh --node <node-name>

Runs a gpuorangefs admission gate:
1. Cilium health from the node-local cilium pod
2. ordinary pod netcheck to controller/accounting/login
3. minimal Slurm smoke pinned to the target node

Optional env:
  AUTO_ADMIT=1         label node into sounio.dev/slurm-worker-gpuorangefs=true on success
  AUTO_QUARANTINE=1    remove that label on failure
  KEEP_NETCHECK_POD=1  keep the temporary pod for inspection
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --node)
      NODE="${2:?missing value for --node}"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "unknown argument: $1" >&2
      usage >&2
      exit 1
      ;;
  esac
done

if [[ -z "${NODE}" ]]; then
  usage >&2
  exit 1
fi

if [[ "${AUTO_ADMIT}" = "1" || "${AUTO_QUARANTINE}" = "1" ]]; then
  echo "66-gpuorangefs-health-gate.sh is validation-only now." >&2
  echo "Use 68-manage-gpuorangefs-worker.sh for admit/quarantine mutations." >&2
  exit 2
fi

RUN_ID="gpuorangefs-gate-${NODE}-$(date -u +%Y%m%dT%H%M%SZ)"
NETCHECK_POD="gogate-$(date -u +%H%M%S)"
SMOKE_OUT="/orangefs/training/sounio/slurm-smokes/${RUN_ID}"

cleanup() {
  if [[ "${KEEP_NETCHECK_POD}" != "1" ]]; then
    kubectl -n default delete pod "${NETCHECK_POD}" --ignore-not-found >/dev/null 2>&1 || true
  fi
}
trap cleanup EXIT

fail_gate() {
  local message="$1"
  echo "FAIL: ${message}" >&2
  if [[ "${AUTO_QUARANTINE}" = "1" ]]; then
    kubectl label node "${NODE}" sounio.dev/slurm-worker-gpuorangefs- >/dev/null 2>&1 || true
    echo "Quarantined ${NODE} from gpuorangefs pool." >&2
  fi
  exit 1
}

CILIUM_POD="$(
  kubectl -n "${KUBE_NS}" get pods -o wide \
    | awk -v node="${NODE}" '$1 ~ /^cilium-/ && $7 == node { print $1 }' \
    | sed -n '1p'
)"
LOGIN_POD="$(
  kubectl -n "${NS}" get pods -o wide \
    | awk '$1 ~ /^slurm-pilot-login-/ { print $1 }' \
    | sed -n '1p'
)"

if [[ -z "${CILIUM_POD}" || -z "${LOGIN_POD}" ]]; then
  fail_gate "could not resolve cilium/login pod"
fi

KUBERNETES_IP="$(kubectl -n default get svc kubernetes -o jsonpath='{.spec.clusterIP}')"
CONTROLLER_IP="$(kubectl -n "${NS}" get svc slurm-pilot-controller -o jsonpath='{.spec.clusterIP}')"
ACCOUNTING_IP="$(kubectl -n "${NS}" get svc slurm-pilot-accounting -o jsonpath='{.spec.clusterIP}')"
LOGIN_IP="$(kubectl -n "${NS}" get pod "${LOGIN_POD}" -o jsonpath='{.status.podIP}')"

echo "== Cilium health on ${NODE} =="
CILIUM_HEALTH_OUTPUT="$(
  kubectl -n "${KUBE_NS}" exec "${CILIUM_POD}" -- sh -lc 'cilium-health status --verbose' 2>&1
)" || fail_gate "cilium-health failed on ${NODE}"
sed -n '1,80p' <<<"${CILIUM_HEALTH_OUTPUT}"

echo
echo "== Ordinary pod netcheck on ${NODE} =="
kubectl run -n default "${NETCHECK_POD}" \
  --image=ghcr.io/slinkyproject/slurmd:25.11-ubuntu24.04 \
  --overrides="{\"spec\":{\"nodeSelector\":{\"kubernetes.io/hostname\":\"${NODE}\"},\"tolerations\":[{\"key\":\"sounio.dev/pool\",\"operator\":\"Equal\",\"value\":\"gpu-batch\",\"effect\":\"NoSchedule\"},{\"key\":\"sounio.dev/compute\",\"operator\":\"Equal\",\"value\":\"heavy\",\"effect\":\"NoSchedule\"}]}}" \
  --restart=Never -- sleep 120 >/dev/null

for _ in $(seq 1 24); do
  phase="$(kubectl -n default get pod "${NETCHECK_POD}" -o jsonpath='{.status.phase}' 2>/dev/null || true)"
  if [[ "${phase}" = "Running" ]]; then
    break
  fi
  sleep 2
done

phase="$(kubectl -n default get pod "${NETCHECK_POD}" -o jsonpath='{.status.phase}' 2>/dev/null || true)"
if [[ "${phase}" != "Running" ]]; then
  fail_gate "netcheck pod did not reach Running on ${NODE} (phase=${phase:-unknown})"
fi

NETCHECK_OUTPUT="$(
  kubectl -n default exec "${NETCHECK_POD}" -- bash -lc 'python3 - <<PY
import socket
targets=[("${KUBERNETES_IP}",443),("${CONTROLLER_IP}",6817),("${ACCOUNTING_IP}",6819),("${LOGIN_IP}",22)]
ok=True
for host, port in targets:
    s=socket.socket()
    s.settimeout(3)
    try:
        s.connect((host, port))
        print(f"{host} {port} OK")
    except Exception as e:
        ok=False
        print(f"{host} {port} FAIL {e}")
    finally:
        s.close()
raise SystemExit(0 if ok else 1)
PY' 2>&1
)" || {
  echo "${NETCHECK_OUTPUT}" >&2
  fail_gate "ordinary pod netcheck failed on ${NODE}"
}
printf '%s\n' "${NETCHECK_OUTPUT}"

echo
echo "== Slurm smoke on ${NODE} =="
SUBMIT_OUTPUT="$(
  kubectl -n "${NS}" exec "${LOGIN_POD}" -- bash -lc "
set -euo pipefail
mkdir -p '${SMOKE_OUT}'
cat > /tmp/${RUN_ID}.sbatch <<'EOF'
#!/bin/bash
#SBATCH -J ${RUN_ID}
#SBATCH -p gpu-orangefs
#SBATCH -w ${NODE}
#SBATCH --gres=gpu:1
#SBATCH -N 1
#SBATCH -n 1
#SBATCH -t 00:05:00
#SBATCH -o ${SMOKE_OUT}/slurm-%j.out
set -euo pipefail
hostname
ls -1 /dev/nvidia* 2>/dev/null || true
echo OK > ${SMOKE_OUT}/ready.txt
EOF
sbatch /tmp/${RUN_ID}.sbatch
" 2>&1
)"
printf '%s\n' "${SUBMIT_OUTPUT}"
JOB_ID="$(printf '%s\n' "${SUBMIT_OUTPUT}" | awk '/Submitted batch job/ {print $4; exit}')"
if [[ -z "${JOB_ID}" ]]; then
  fail_gate "failed to parse Slurm job id for ${NODE} smoke"
fi

deadline=$((SECONDS + SMOKE_TIMEOUT_SECS))
while (( SECONDS < deadline )); do
  state="$(
    kubectl -n "${NS}" exec "${LOGIN_POD}" -- bash -lc \
      "sacct -j ${JOB_ID} --format=State --noheader | sed '/^$/d' | head -n 1"
  )"
  case "${state}" in
    COMPLETED|FAILED|CANCELLED|TIMEOUT)
      break
      ;;
  esac
  sleep 5
done

state="$(
  kubectl -n "${NS}" exec "${LOGIN_POD}" -- bash -lc \
    "sacct -j ${JOB_ID} --format=State --noheader | sed '/^$/d' | head -n 1"
)"
if [[ "${state}" != "COMPLETED" ]]; then
  fail_gate "Slurm smoke ended in state ${state:-unknown} on ${NODE}"
fi

kubectl -n "${NS}" exec "${LOGIN_POD}" -- bash -lc "test -f '${SMOKE_OUT}/ready.txt'"
kubectl -n "${NS}" exec "${LOGIN_POD}" -- bash -lc "cat '${SMOKE_OUT}/ready.txt'"
kubectl -n "${NS}" exec "${LOGIN_POD}" -- bash -lc "for f in '${SMOKE_OUT}'/slurm-*.out; do [ -f \"\$f\" ] && cat \"\$f\"; done"

echo
echo "PASS: ${NODE} passed Cilium health, pod netcheck, and Slurm smoke"
