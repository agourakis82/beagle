#!/usr/bin/env bash
set -euo pipefail

if [[ -z "${KUBECONFIG_PATH:-}" ]]; then
  if [[ -f "${HOME}/.kube/config" ]]; then
    KUBECONFIG_PATH="${HOME}/.kube/config"
  else
    KUBECONFIG_PATH="/etc/kubernetes/admin.conf"
  fi
fi
NS="${NS:-slurm-pilot}"
TARGET_NODE="${TARGET_NODE:-r770-proxmox}"
PARTITION="${PARTITION:-gpu-orangefs}"
SLURM_NODE_NAME="${SLURM_NODE_NAME:-gpuorangefs-${TARGET_NODE}}"
LOGIN_POD="${LOGIN_POD:-}"
NETCHECK_IMAGE="${NETCHECK_IMAGE:-ghcr.io/slinkyproject/slurmd:25.11-ubuntu24.04}"
SLURM_SMOKE_TIMEOUT_SEC="${SLURM_SMOKE_TIMEOUT_SEC:-120}"
SLURM_NODE_WAIT_SEC="${SLURM_NODE_WAIT_SEC:-90}"
ARTIFACT_ROOT="${ARTIFACT_ROOT:-/orangefs/training/sounio/slurm-smokes}"
NETCHECK_POD="gpuorangefs-netcheck-${TARGET_NODE//[^a-zA-Z0-9]/-}"
HEALTH_WAIT_SEC="${HEALTH_WAIT_SEC:-60}"
HEALTH_POLL_SEC="${HEALTH_POLL_SEC:-5}"

export KUBECONFIG="${KUBECONFIG_PATH}"

cleanup() {
  kubectl -n default delete pod "${NETCHECK_POD}" --ignore-not-found >/dev/null 2>&1 || true
}
trap cleanup EXIT

require() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "missing required command: $1" >&2
    exit 1
  }
}

require kubectl

echo "[gate] target node: ${TARGET_NODE}"

if [[ -z "${LOGIN_POD}" ]]; then
  LOGIN_POD="$(
    kubectl -n "${NS}" get pods -o jsonpath='{range .items[*]}{.metadata.name}{"\n"}{end}' \
      | awk '/^slurm-pilot-login-/{print; exit}'
  )"
fi

if [[ -z "${LOGIN_POD}" ]]; then
  echo "[gate] FAIL: could not resolve login pod in namespace ${NS}" >&2
  exit 1
fi

echo "[gate] login pod: ${LOGIN_POD}"

CONTROLLER_IP="$(kubectl -n "${NS}" get svc slurm-pilot-controller -o jsonpath='{.spec.clusterIP}')"
ACCOUNTING_IP="$(kubectl -n "${NS}" get svc slurm-pilot-accounting -o jsonpath='{.spec.clusterIP}')"
LOGIN_IP="$(kubectl -n "${NS}" get pod "${LOGIN_POD}" -o jsonpath='{.status.podIP}')"
KUBERNETES_IP="$(kubectl -n default get svc kubernetes -o jsonpath='{.spec.clusterIP}')"

echo "[gate] service IPs:"
echo "  kubernetes=${KUBERNETES_IP}:443"
echo "  controller=${CONTROLLER_IP}:6817"
echo "  accounting=${ACCOUNTING_IP}:6819"
echo "  login=${LOGIN_IP}:22"

CILIUM_POD="$(
  kubectl -n kube-system get pods \
    -l k8s-app=cilium \
    --field-selector "spec.nodeName=${TARGET_NODE}" \
    -o jsonpath='{.items[0].metadata.name}'
)"

if [[ -z "${CILIUM_POD}" ]]; then
  echo "[gate] FAIL: could not find cilium pod on ${TARGET_NODE}" >&2
  exit 1
fi

echo "[gate] cilium pod: ${CILIUM_POD}"
extract_health_section() {
  awk -v node="${TARGET_NODE}" '
    index($0, "  " node) == 1 {in_node=1; next}
    in_node && $0 ~ /^  [^ ]/ {exit}
    in_node {print}
  '
}

health_section_bad() {
  grep -Eqi 'Connection timed out|context deadline exceeded|unreachable|failed'
}

HEALTH_OUTPUT=""
HEALTH_SECTION=""
HEALTH_OK=0
for _ in $(seq 1 $((HEALTH_WAIT_SEC / HEALTH_POLL_SEC))); do
  HEALTH_OUTPUT="$(
    kubectl -n kube-system exec "${CILIUM_POD}" -- cilium-health status --verbose || true
  )"
  HEALTH_SECTION="$(printf '%s\n' "${HEALTH_OUTPUT}" | extract_health_section || true)"

  if [[ -n "${HEALTH_SECTION}" ]] && ! printf '%s\n' "${HEALTH_SECTION}" | health_section_bad; then
    HEALTH_OK=1
    break
  fi

  sleep "${HEALTH_POLL_SEC}"
done

echo "${HEALTH_OUTPUT}"

if [[ "${HEALTH_OK}" -ne 1 ]]; then
  echo "[gate] FAIL: cilium-health did not converge cleanly on ${TARGET_NODE} within ${HEALTH_WAIT_SEC}s" >&2
  exit 1
fi

echo "[gate] running ordinary pod netcheck on ${TARGET_NODE}"
kubectl -n default delete pod "${NETCHECK_POD}" --ignore-not-found >/dev/null 2>&1 || true
kubectl -n default run "${NETCHECK_POD}" \
  --image="${NETCHECK_IMAGE}" \
  --restart=Never \
  --overrides="$(cat <<EOF
{"spec":{"nodeSelector":{"kubernetes.io/hostname":"${TARGET_NODE}"},"tolerations":[{"key":"sounio.dev/pool","operator":"Equal","value":"gpu-batch","effect":"NoSchedule"},{"key":"sounio.dev/compute","operator":"Equal","value":"heavy","effect":"NoSchedule"}]}}
EOF
)"

kubectl -n default wait --for=condition=Ready "pod/${NETCHECK_POD}" --timeout=120s >/dev/null
kubectl -n default exec "${NETCHECK_POD}" -- bash -lc "
python3 - <<'PY'
import socket, sys
checks = [
    ('${KUBERNETES_IP}', 443, 'kubernetes'),
    ('${CONTROLLER_IP}', 6817, 'controller'),
    ('${ACCOUNTING_IP}', 6819, 'accounting'),
    ('${LOGIN_IP}', 22, 'login'),
]
failed = False
for host, port, name in checks:
    s = socket.socket()
    s.settimeout(3)
    try:
        s.connect((host, port))
        print(f'{name} {host}:{port} OK')
    except Exception as e:
        failed = True
        print(f'{name} {host}:{port} FAIL {e}')
    finally:
        s.close()
if failed:
    sys.exit(1)
PY
"

RUN_ID="gpuorangefs-gate-${TARGET_NODE}-$(date -u +%Y%m%dT%H%M%SZ)"
echo "[gate] waiting for Slurm node registration: ${SLURM_NODE_NAME}"
SLURM_NODE_READY=0
for _ in $(seq 1 $((SLURM_NODE_WAIT_SEC / 2))); do
  if kubectl -n "${NS}" exec "${LOGIN_POD}" -- bash -lc "scontrol show node '${SLURM_NODE_NAME}' >/dev/null 2>&1"; then
    SLURM_NODE_READY=1
    break
  fi
  sleep 2
done

if [[ "${SLURM_NODE_READY}" -ne 1 ]]; then
  echo "[gate] FAIL: Slurm node ${SLURM_NODE_NAME} did not register within ${SLURM_NODE_WAIT_SEC}s" >&2
  exit 1
fi

echo "[gate] submitting Slurm smoke: ${RUN_ID}"

kubectl -n "${NS}" exec -i "${LOGIN_POD}" -- bash -lc "
set -euo pipefail
RUN_ID='${RUN_ID}'
OUT='${ARTIFACT_ROOT}/'\"\${RUN_ID}\"
SBATCH_FILE=/tmp/\${RUN_ID}.sbatch
mkdir -p \"\${OUT}\"
cat > \"\${SBATCH_FILE}\"
sbatch \"\${SBATCH_FILE}\"
" <<EOF | tee /tmp/"${RUN_ID}".submit.txt >/dev/null
#!/usr/bin/env bash
#SBATCH -J ${RUN_ID}
#SBATCH -p ${PARTITION}
#SBATCH -w ${SLURM_NODE_NAME}
#SBATCH --gres=gpu:1
#SBATCH -N 1
#SBATCH -n 1
#SBATCH -t 00:05:00
#SBATCH -o ${ARTIFACT_ROOT}/${RUN_ID}/slurm-%j.out
set -euo pipefail
OUT='${ARTIFACT_ROOT}/${RUN_ID}'
hostname
ls /dev/nvidia* || true
ldconfig -p | grep 'libcuda\.so\.1'
ldconfig -p | grep 'libnvidia-ptxjitcompiler\.so\.1'
command -v nvidia-smi >/dev/null
nvidia-smi -L
python3 - <<'PY'
import ctypes
import sys
from ctypes import byref, c_int

ctypes.CDLL("libnvidia-ptxjitcompiler.so.1")
lib = ctypes.CDLL("libcuda.so.1")
rc = lib.cuInit(0)
if rc != 0:
    print(f"cuInit failed rc={rc}", file=sys.stderr)
    sys.exit(1)

count = c_int()
rc = lib.cuDeviceGetCount(byref(count))
if rc != 0:
    print(f"cuDeviceGetCount failed rc={rc}", file=sys.stderr)
    sys.exit(1)

print(f"CUDA driver probe OK count={count.value}")
print("PTX JIT runtime probe OK")
PY
echo OK > "${ARTIFACT_ROOT}/${RUN_ID}/ready.txt"
EOF

JOB_ID="$(awk '/Submitted batch job/ {print $4}' /tmp/"${RUN_ID}".submit.txt)"
if [[ -z "${JOB_ID}" ]]; then
  echo "[gate] FAIL: could not resolve submitted job id" >&2
  exit 1
fi

echo "[gate] waiting for job ${JOB_ID}"
for _ in $(seq 1 $((SLURM_SMOKE_TIMEOUT_SEC / 5))); do
  STATE="$(kubectl -n "${NS}" exec "${LOGIN_POD}" -- sacct -j "${JOB_ID}" --format=State --noheader | head -n1 | xargs)"
  case "${STATE}" in
    COMPLETED|FAILED|CANCELLED|TIMEOUT)
      break
      ;;
  esac
  sleep 5
done

kubectl -n "${NS}" exec "${LOGIN_POD}" -- sacct -j "${JOB_ID}" --format=JobID,JobName,State,ExitCode,Elapsed,NodeList --noheader
STATE="$(kubectl -n "${NS}" exec "${LOGIN_POD}" -- sacct -j "${JOB_ID}" --format=State --noheader | head -n1 | xargs)"

if [[ "${STATE}" != "COMPLETED" ]]; then
  echo "[gate] FAIL: Slurm smoke ended in state ${STATE}" >&2
  exit 1
fi

kubectl -n "${NS}" exec "${LOGIN_POD}" -- bash -lc "
set -euo pipefail
OUT='${ARTIFACT_ROOT}/${RUN_ID}'
test -f \"\${OUT}/ready.txt\"
test -f \"\${OUT}/slurm-${JOB_ID}.out\"
cat \"\${OUT}/ready.txt\"
echo '---'
cat \"\${OUT}/slurm-${JOB_ID}.out\"
"

echo "[gate] PASS: ${TARGET_NODE} passed cilium, netcheck, and Slurm smoke"
