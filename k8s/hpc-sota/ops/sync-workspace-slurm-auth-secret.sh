#!/usr/bin/env bash
set -euo pipefail

KUBECTL="${KUBECTL:-kubectl}"
SRC_NAMESPACE="${SRC_NAMESPACE:-slurm-pilot}"
SRC_SECRET="${SRC_SECRET:-slurm-pilot-auth-slurm}"
DST_NAMESPACE="${DST_NAMESPACE:-beagle}"
DST_SECRET="${DST_SECRET:-sounio-workspace-slurm-auth}"

slurm_key_b64="$(${KUBECTL} -n "${SRC_NAMESPACE}" get secret "${SRC_SECRET}" -o jsonpath='{.data.slurm\.key}')"
if [[ -z "${slurm_key_b64}" ]]; then
  echo "[FAIL] unable to read slurm.key from ${SRC_NAMESPACE}/${SRC_SECRET}" >&2
  exit 1
fi

current_b64="$(${KUBECTL} -n "${DST_NAMESPACE}" get secret "${DST_SECRET}" -o jsonpath='{.data.slurm\.key}' 2>/dev/null || true)"
if [[ "${current_b64}" == "${slurm_key_b64}" ]]; then
  echo "[OK] ${DST_NAMESPACE}/${DST_SECRET} already matches ${SRC_NAMESPACE}/${SRC_SECRET}"
  exit 0
fi

${KUBECTL} -n "${DST_NAMESPACE}" delete secret "${DST_SECRET}" --ignore-not-found >/dev/null

cat <<EOF | ${KUBECTL} apply -f -
apiVersion: v1
kind: Secret
metadata:
  name: ${DST_SECRET}
  namespace: ${DST_NAMESPACE}
  annotations:
    sounio.dev/source-secret: ${SRC_NAMESPACE}/${SRC_SECRET}
type: Opaque
immutable: true
data:
  slurm.key: ${slurm_key_b64}
EOF

echo "[OK] synced ${DST_NAMESPACE}/${DST_SECRET} from ${SRC_NAMESPACE}/${SRC_SECRET}"
