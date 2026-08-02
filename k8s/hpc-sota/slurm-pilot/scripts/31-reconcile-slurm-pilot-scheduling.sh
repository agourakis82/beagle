#!/usr/bin/env bash
set -euo pipefail

NS="${NS:-slurm-pilot}"
KUBECTL_BIN="${KUBECTL_BIN:-kubectl}"
CONTROL_PLANE_NODE="${CONTROL_PLANE_NODE:-r770-proxmox}"
HEAVY_TOLERATIONS='[{"key":"sounio.dev/pool","operator":"Equal","value":"gpu-batch","effect":"NoSchedule"},{"key":"sounio.dev/compute","operator":"Equal","value":"heavy","effect":"NoSchedule"}]'
HEAVY_NODE_SELECTOR="{\"kubernetes.io/os\":\"linux\",\"kubernetes.io/hostname\":\"${CONTROL_PLANE_NODE}\",\"sounio.dev/compute\":\"heavy\"}"
LOGIN_NODE_SELECTOR="{\"kubernetes.io/os\":\"linux\",\"kubernetes.io/hostname\":\"${CONTROL_PLANE_NODE}\",\"sounio.dev/compute\":\"heavy\",\"sounio.dev/orangefs-client\":\"true\"}"

replace_node_selector() {
  local resource="$1"
  local selector_json="$2"
  if ${KUBECTL_BIN} -n "${NS}" get "${resource}" >/dev/null 2>&1; then
    ${KUBECTL_BIN} -n "${NS}" patch "${resource}" --type merge \
      -p="{\"spec\":{\"template\":{\"spec\":{\"nodeSelector\":${selector_json}}}}}" \
      >/dev/null 2>&1 || true
  fi
}

replace_tolerations() {
  local resource="$1"
  if ${KUBECTL_BIN} -n "${NS}" get "${resource}" >/dev/null 2>&1; then
    ${KUBECTL_BIN} -n "${NS}" patch "${resource}" --type json \
      -p="[{\"op\":\"replace\",\"path\":\"/spec/template/spec/tolerations\",\"value\":${HEAVY_TOLERATIONS}}]" \
      >/dev/null 2>&1 || true
  fi
}

replace_node_selector "controller.slinky.slurm.net/slurm-pilot" "${HEAVY_NODE_SELECTOR}"
replace_node_selector "accounting.slinky.slurm.net/slurm-pilot" "${HEAVY_NODE_SELECTOR}"
replace_node_selector "restapi.slinky.slurm.net/slurm-pilot" "${HEAVY_NODE_SELECTOR}"
replace_node_selector "loginsets.slinky.slurm.net/slurm-pilot-login-slinky" "${LOGIN_NODE_SELECTOR}"
replace_node_selector "statefulset.apps/slurm-pilot-controller" "${HEAVY_NODE_SELECTOR}"
replace_node_selector "statefulset.apps/slurm-pilot-accounting" "${HEAVY_NODE_SELECTOR}"
replace_node_selector "deployment.apps/slurm-pilot-restapi" "${HEAVY_NODE_SELECTOR}"
replace_node_selector "deployment.apps/slurm-pilot-login-slinky" "${LOGIN_NODE_SELECTOR}"

replace_tolerations "statefulset.apps/slurm-pilot-controller"
replace_tolerations "statefulset.apps/slurm-pilot-accounting"
replace_tolerations "deployment.apps/slurm-pilot-restapi"
replace_tolerations "deployment.apps/slurm-pilot-login-slinky"

${KUBECTL_BIN} -n "${NS}" delete pod \
  -l 'app.kubernetes.io/name in (slurmctld,slurmdbd,slurmrestd,login)' \
  --field-selector=status.phase!=Running \
  --ignore-not-found >/dev/null 2>&1 || true

echo "[OK] reconciled Slurm Pilot scheduling in ${NS}"
