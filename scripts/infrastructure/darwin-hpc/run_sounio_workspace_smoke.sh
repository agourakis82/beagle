#!/usr/bin/env bash
set -euo pipefail

ROOT="${ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)}"
KUBECTL="${KUBECTL:-}"
NAMESPACE="${NAMESPACE:-beagle}"
BEAGLE_DEPLOYMENT="${BEAGLE_DEPLOYMENT:-beagle-core}"
BEAGLE_SERVICE_NAME="${BEAGLE_SERVICE_NAME:-beagle-core}"
WORKSPACE_DEPLOYMENT="${WORKSPACE_DEPLOYMENT:-sounio-workspace}"
WORKSPACE_SERVICE_NAME="${WORKSPACE_SERVICE_NAME:-sounio-workspace}"
WORKSPACE_ID="${WORKSPACE_ID:-sounio-cluster-pilot}"
SESSION_ID="${SESSION_ID:-ws-cluster-sounio-habitat}"
WORKSTREAM_ID="${WORKSTREAM_ID:-sounio-lang-main}"
EXPECTED_REPO_URL="${EXPECTED_REPO_URL:-https://github.com/sounio-lang/sounio.git}"
EXPECTED_BRANCH="${EXPECTED_BRANCH:-main}"
EXPECTED_ROOT="${EXPECTED_ROOT:-/workspace/sounio}"
EXPECTED_ATTACH_ALIAS="${EXPECTED_ATTACH_ALIAS:-sounio-cluster-pilot.coder}"
OUT="${OUT:-${ROOT}/.artifacts/darwin-hpc/sounio-workspace}"
STAMP="${STAMP:-$(date +%m%d%H%M%S)}"
CORE_IMAGE_REF="${CORE_IMAGE_REF:-localhost/beagle-core:sounio-workspace-${STAMP}}"
WORKSPACE_IMAGE_REF="${WORKSPACE_IMAGE_REF:-localhost/sounio-workspace-ide:${STAMP}}"
SSH_IMAGE_REF="${SSH_IMAGE_REF:-localhost/beagle-workspace-ssh:b213}"
SECRET_NAME="${SECRET_NAME:-beagle-core-secrets}"
LOAD_IMAGE_SCRIPT="${LOAD_IMAGE_SCRIPT:-${ROOT}/scripts/infrastructure/beagle/load_core_image_t560.sh}"
HOST_SEED_HELPER="${HOST_SEED_HELPER:-${ROOT}/scripts/infrastructure/darwin-hpc/seed_workspace_git_checkout.sh}"
BEAGLE_LOCAL_PORT="${BEAGLE_LOCAL_PORT:-18391}"
WORKSPACE_LOCAL_PORT="${WORKSPACE_LOCAL_PORT:-18401}"
OPERATOR_API_TOKEN="${BEAGLE_OPERATOR_API_TOKEN:-${BEAGLE_API_TOKEN:-}}"
MAKE_CHECK_TARGET="${MAKE_CHECK_TARGET:-check}"

require() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "[FAIL] missing command: $1" >&2
    exit 1
  }
}

require curl
require jq
require podman
require rg
require sinfo
require ssh
require ss
require sudo

resolve_kubectl() {
  if [[ -n "${KUBECTL}" ]]; then
    printf '%s\n' "${KUBECTL}"
    return 0
  fi
  if [[ -r /etc/kubernetes/admin.conf ]]; then
    export KUBECONFIG=/etc/kubernetes/admin.conf
    printf '%s\n' kubectl
    return 0
  fi
  printf '%s\n' "sudo kubectl --kubeconfig=/etc/kubernetes/admin.conf"
}

choose_local_port() {
  local port="$1"
  local tries=0
  while (( tries < 20 )); do
    if ! ss -ltn "( sport = :${port} )" | tail -n +2 | grep -q .; then
      echo "${port}"
      return 0
    fi
    port=$((port + 1))
    tries=$((tries + 1))
  done
  echo "[FAIL] unable to find a free local port starting at $1" >&2
  exit 1
}

start_port_forward() {
  local service_name="$1"
  local local_port="$2"
  local remote_port="$3"
  local pf_log="$4"
  local pid_var="$5"

  : > "${pf_log}"
  # shellcheck disable=SC2086
  ${KUBECTL} -n "${NAMESPACE}" port-forward service/"${service_name}" "${local_port}:${remote_port}" >"${pf_log}" 2>&1 &
  local pf_pid=$!

  for _ in $(seq 1 30); do
    if grep -q "Forwarding from" "${pf_log}" 2>/dev/null; then
      printf -v "${pid_var}" '%s' "${pf_pid}"
      return 0
    fi
    if ! kill -0 "${pf_pid}" >/dev/null 2>&1; then
      echo "[FAIL] port-forward exited before binding local port ${local_port}" >&2
      cat "${pf_log}" >&2 || true
      exit 1
    fi
    sleep 1
  done

  echo "[FAIL] port-forward did not bind local port ${local_port}" >&2
  cat "${pf_log}" >&2 || true
  exit 1
}

stop_port_forward() {
  local pid_var="$1"
  local pid="${!pid_var:-}"
  if [[ -n "${pid}" ]]; then
    kill "${pid}" >/dev/null 2>&1 || true
    wait "${pid}" >/dev/null 2>&1 || true
    printf -v "${pid_var}" '%s' ""
  fi
}

cleanup() {
  stop_port_forward BEAGLE_PF_PID
  stop_port_forward WORKSPACE_PF_PID
}
trap cleanup EXIT

resolve_operator_api_token() {
  if [[ -n "${OPERATOR_API_TOKEN}" ]]; then
    printf '%s\n' "${OPERATOR_API_TOKEN}"
    return 0
  fi

  local encoded_token=""
  # shellcheck disable=SC2086
  encoded_token="$(${KUBECTL} -n "${NAMESPACE}" get secret "${SECRET_NAME}" -o jsonpath='{.data.BEAGLE_OPERATOR_API_TOKEN}' 2>/dev/null || true)"
  if [[ -z "${encoded_token}" ]]; then
    # shellcheck disable=SC2086
    encoded_token="$(${KUBECTL} -n "${NAMESPACE}" get secret "${SECRET_NAME}" -o jsonpath='{.data.BEAGLE_API_TOKEN}' 2>/dev/null || true)"
  fi
  if [[ -z "${encoded_token}" ]]; then
    echo "[FAIL] missing operator token in secret ${SECRET_NAME}" >&2
    exit 1
  fi
  printf '%s' "${encoded_token}" | base64 -d
}

KUBECTL="$(resolve_kubectl)"
require "${KUBECTL%% *}"
mkdir -p "${OUT}"
BEAGLE_LOCAL_PORT="$(choose_local_port "${BEAGLE_LOCAL_PORT}")"
WORKSPACE_LOCAL_PORT="$(choose_local_port "${WORKSPACE_LOCAL_PORT}")"
OPERATOR_API_TOKEN="$(resolve_operator_api_token)"
AUTH_HEADER="Authorization: Bearer ${OPERATOR_API_TOKEN}"
CONSUMER_HEADER="X-Beagle-Consumer: beagle-operator"

echo "[INFO] building beagle-core image ${CORE_IMAGE_REF}"
sudo podman build -t "${CORE_IMAGE_REF}" -f "${ROOT}/apps/beagle-monorepo/Dockerfile.core_server" "${ROOT}" > "${OUT}/build-core.log"
IMAGE_REF="${CORE_IMAGE_REF}" ARCHIVE_PATH="/tmp/beagle-core-sounio-${STAMP}.oci.tar" bash "${LOAD_IMAGE_SCRIPT}" > "${OUT}/load-core-image.log"

echo "[INFO] building sounio workspace ide image ${WORKSPACE_IMAGE_REF}"
sudo podman build -t "${WORKSPACE_IMAGE_REF}" -f "${ROOT}/k8s/sounio-workspace/Dockerfile.ide" "${ROOT}/k8s/sounio-workspace" > "${OUT}/build-workspace.log"
IMAGE_REF="${WORKSPACE_IMAGE_REF}" ARCHIVE_PATH="/tmp/sounio-workspace-ide-${STAMP}.oci.tar" bash "${LOAD_IMAGE_SCRIPT}" > "${OUT}/load-workspace-image.log"

echo "[INFO] building workspace ssh image ${SSH_IMAGE_REF}"
sudo podman build -t "${SSH_IMAGE_REF}" -f "${ROOT}/k8s/beagle-workspace/Dockerfile.ssh" "${ROOT}/k8s/beagle-workspace" > "${OUT}/build-workspace-ssh.log"
IMAGE_REF="${SSH_IMAGE_REF}" ARCHIVE_PATH="/tmp/beagle-workspace-ssh-${STAMP}.oci.tar" bash "${LOAD_IMAGE_SCRIPT}" > "${OUT}/load-workspace-ssh-image.log"

echo "[INFO] applying beagle-core configmap"
# shellcheck disable=SC2086
${KUBECTL} -n "${NAMESPACE}" apply -f "${ROOT}/k8s/beagle/configmap.yaml" > "${OUT}/apply-core-configmap.log"
echo "[INFO] setting beagle-core image"
# shellcheck disable=SC2086
${KUBECTL} -n "${NAMESPACE}" set image deployment/"${BEAGLE_DEPLOYMENT}" core-server="${CORE_IMAGE_REF}" > "${OUT}/rollout-core-set-image.log"
# shellcheck disable=SC2086
${KUBECTL} -n "${NAMESPACE}" rollout status deployment/"${BEAGLE_DEPLOYMENT}" --timeout=900s > "${OUT}/rollout-core.log"

echo "[INFO] applying sounio-workspace manifests"
# shellcheck disable=SC2086
${KUBECTL} apply -k "${ROOT}/k8s/sounio-workspace" > "${OUT}/apply-sounio-workspace.log"
echo "[INFO] setting sounio-workspace image"
# shellcheck disable=SC2086
${KUBECTL} -n "${NAMESPACE}" set image deployment/"${WORKSPACE_DEPLOYMENT}" workspace-ide="${WORKSPACE_IMAGE_REF}" > "${OUT}/rollout-workspace-set-image.log"
# shellcheck disable=SC2086
${KUBECTL} -n "${NAMESPACE}" set image deployment/"${WORKSPACE_DEPLOYMENT}" workspace-ssh="${SSH_IMAGE_REF}" > "${OUT}/rollout-workspace-ssh-set-image.log"
# shellcheck disable=SC2086
${KUBECTL} -n "${NAMESPACE}" rollout status deployment/"${WORKSPACE_DEPLOYMENT}" --timeout=900s > "${OUT}/rollout-workspace.log"

if ! ${KUBECTL} -n "${NAMESPACE}" exec deployment/"${WORKSPACE_DEPLOYMENT}" -c workspace-ide -- test -d "${EXPECTED_ROOT}/.git"; then
  echo "[INFO] seeding ${EXPECTED_ROOT} from host clone"
  bash "${HOST_SEED_HELPER}" \
    --namespace "${NAMESPACE}" \
    --deployment "${WORKSPACE_DEPLOYMENT}" \
    --container workspace-ide \
    --workspace-root "${EXPECTED_ROOT}" \
    --repo-url "${EXPECTED_REPO_URL}" \
    --branch "${EXPECTED_BRANCH}" \
    > "${OUT}/workspace-seed.log"
fi

start_port_forward "${BEAGLE_SERVICE_NAME}" "${BEAGLE_LOCAL_PORT}" 8080 "${OUT}/beagle-port-forward.log" BEAGLE_PF_PID
start_port_forward "${WORKSPACE_SERVICE_NAME}" "${WORKSPACE_LOCAL_PORT}" 8080 "${OUT}/workspace-port-forward.log" WORKSPACE_PF_PID

curl -fsS -H "${AUTH_HEADER}" -H "${CONSUMER_HEADER}" "http://127.0.0.1:${BEAGLE_LOCAL_PORT}/health" > "${OUT}/beagle-health.json"
curl -fsS "http://127.0.0.1:${WORKSPACE_LOCAL_PORT}/" > "${OUT}/workspace-root.html"

curl -fsS \
  -H "${AUTH_HEADER}" \
  -H "${CONSUMER_HEADER}" \
  "http://127.0.0.1:${BEAGLE_LOCAL_PORT}/api/darwin/workstreams/${WORKSTREAM_ID}/workspace-habitat" \
  > "${OUT}/workspace-habitat.json"

curl -fsS \
  -H "${AUTH_HEADER}" \
  -H "${CONSUMER_HEADER}" \
  "http://127.0.0.1:${BEAGLE_LOCAL_PORT}/api/darwin/workstreams/${WORKSTREAM_ID}/workspace-launch-resume" \
  > "${OUT}/workspace-launch-resume.json"

bash "${ROOT}/scripts/infrastructure/darwin-hpc/launch_managed_workspace_session.sh" \
  --workstream "${WORKSTREAM_ID}" \
  --client cursor \
  --out "${OUT}/managed-attach" \
  --json-out "${OUT}/launch-summary.json" \
  --context-env-out "${OUT}/workspace-context.env" \
  --context-packet-out "${OUT}/workspace-context-packet.json" \
  --remote-command "cd ${EXPECTED_ROOT} && pwd; whoami; git rev-parse --is-inside-work-tree; git remote get-url origin; git rev-parse --abbrev-ref HEAD; test -x bin/souc && echo SOUC_OK; SOUNIO_STDLIB_PATH=${EXPECTED_ROOT}/stdlib ${EXPECTED_ROOT}/bin/souc --version" \
  --remote-output "${OUT}/remote-command.txt"

SSH_CONFIG_PATH="$(jq -r '.ssh_config_path' "${OUT}/managed-attach/managed-attach-install.json")"
SSH_COMMAND="ssh -F ${SSH_CONFIG_PATH} ${EXPECTED_ATTACH_ALIAS}"

${SSH_COMMAND} "cd ${EXPECTED_ROOT} && make ${MAKE_CHECK_TARGET}" > "${OUT}/make-check.log"

${SSH_COMMAND} "cat ${EXPECTED_ROOT}/.beagle/context/workspace-hydration.json" > "${OUT}/workspace-hydration.json"
${SSH_COMMAND} "cat ${EXPECTED_ROOT}/.beagle/context/workspace-template.json" > "${OUT}/workspace-template.json"
${SSH_COMMAND} "cat ${EXPECTED_ROOT}/.beagle/context/external-workspace-registration.json" > "${OUT}/workspace-registration.json"

echo "[INFO] restarting sounio-workspace for identity proof"
# shellcheck disable=SC2086
${KUBECTL} -n "${NAMESPACE}" rollout restart deployment/"${WORKSPACE_DEPLOYMENT}" > "${OUT}/restart-workspace.log"
# shellcheck disable=SC2086
${KUBECTL} -n "${NAMESPACE}" rollout status deployment/"${WORKSPACE_DEPLOYMENT}" --timeout=900s > "${OUT}/restart-workspace-status.log"

stop_port_forward WORKSPACE_PF_PID
WORKSPACE_LOCAL_PORT="$(choose_local_port "${WORKSPACE_LOCAL_PORT}")"
start_port_forward "${WORKSPACE_SERVICE_NAME}" "${WORKSPACE_LOCAL_PORT}" 8080 "${OUT}/workspace-port-forward-after-restart.log" WORKSPACE_PF_PID
curl -fsS "http://127.0.0.1:${WORKSPACE_LOCAL_PORT}/" > "${OUT}/workspace-root-after-restart.html"

curl -fsS \
  -H "${AUTH_HEADER}" \
  -H "${CONSUMER_HEADER}" \
  "http://127.0.0.1:${BEAGLE_LOCAL_PORT}/api/darwin/workstreams/${WORKSTREAM_ID}/workspace-habitat" \
  > "${OUT}/workspace-habitat-after-restart.json"

bash "${ROOT}/scripts/infrastructure/darwin-hpc/launch_managed_workspace_session.sh" \
  --workstream "${WORKSTREAM_ID}" \
  --client cursor \
  --out "${OUT}/managed-attach-after-restart" \
  --json-out "${OUT}/launch-summary-after-restart.json" \
  --context-env-out "${OUT}/workspace-context-after-restart.env" \
  --context-packet-out "${OUT}/workspace-context-after-restart.json" \
  --remote-command "cd ${EXPECTED_ROOT} && git rev-parse --is-inside-work-tree; git remote get-url origin; git rev-parse --abbrev-ref HEAD; SOUNIO_STDLIB_PATH=${EXPECTED_ROOT}/stdlib ${EXPECTED_ROOT}/bin/souc --version" \
  --remote-output "${OUT}/remote-command-after-restart.txt"

{
  echo "[pods]"
  # shellcheck disable=SC2086
  ${KUBECTL} -n "${NAMESPACE}" get pods -o wide
  echo
  echo "[deployments]"
  # shellcheck disable=SC2086
  ${KUBECTL} -n "${NAMESPACE}" get deploy "${BEAGLE_DEPLOYMENT}" "${WORKSPACE_DEPLOYMENT}" -o wide
  echo
  echo "[slurm]"
  sinfo
} > "${OUT}/final-cluster-health.txt"

jq -nc \
  --arg workstream_id "${WORKSTREAM_ID}" \
  --arg workspace_id "${WORKSPACE_ID}" \
  --arg session_id "${SESSION_ID}" \
  --arg expected_repo_url "${EXPECTED_REPO_URL}" \
  --arg expected_branch "${EXPECTED_BRANCH}" \
  --arg expected_root "${EXPECTED_ROOT}" \
  --arg expected_attach_alias "${EXPECTED_ATTACH_ALIAS}" \
  --arg core_image_ref "${CORE_IMAGE_REF}" \
  --arg workspace_image_ref "${WORKSPACE_IMAGE_REF}" \
  --arg ssh_image_ref "${SSH_IMAGE_REF}" \
  --arg ssh_config_path "${SSH_CONFIG_PATH}" \
  --arg make_check_target "${MAKE_CHECK_TARGET}" \
  '{
    status: "ok",
    phase: "B26.7",
    workstream_id: $workstream_id,
    workspace_id: $workspace_id,
    session_id: $session_id,
    expected_repo_url: $expected_repo_url,
    expected_branch: $expected_branch,
    expected_root: $expected_root,
    expected_attach_alias: $expected_attach_alias,
    core_image_ref: $core_image_ref,
    workspace_image_ref: $workspace_image_ref,
    ssh_image_ref: $ssh_image_ref,
    ssh_config_path: $ssh_config_path,
    make_check_target: $make_check_target
  }' > "${OUT}/smoke.json"

echo "[OK] sounio workspace smoke completed"
