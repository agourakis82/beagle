#!/usr/bin/env bash
set -euo pipefail

NS="${NS:-slurm-pilot}"

CONTROLLER_POD="$(
  kubectl -n "${NS}" get pods -o wide \
    | awk '$1 ~ /^slurm-pilot-controller-/ { print $1; exit }'
)"
LOGIN_POD="$(
  kubectl -n "${NS}" get pods -o wide \
    | awk '$1 ~ /^slurm-pilot-login-/ { print $1; exit }'
)"

if [[ -z "${CONTROLLER_POD}" || -z "${LOGIN_POD}" ]]; then
  echo "could not resolve controller/login pod" >&2
  exit 1
fi

echo "== Controller CR extraConf =="
kubectl -n "${NS}" get controller.slinky.slurm.net/slurm-pilot -o yaml \
  | sed -n '/extraConf: |/,+20p'

echo
echo "== Runtime /etc/slurm/slurm.conf SlurmctldParameters lines =="
kubectl -n "${NS}" exec "${CONTROLLER_POD}" -c slurmctld -- bash -lc \
  "nl -ba /etc/slurm/slurm.conf | grep 'SlurmctldParameters'"

echo
echo "== Runtime scontrol view =="
kubectl -n "${NS}" exec "${LOGIN_POD}" -- bash -lc \
  "scontrol show config | grep -i '^SlurmctldParameters'"

echo
echo "== Diagnosis =="
echo "- If runtime still shows two SlurmctldParameters lines, the base chart/operator render is injecting one before extraConf."
echo "- If the earlier line contains enable_stepmgr, changing Controller.spec.extraConf alone will not disable it."
echo "- Keep PAYLOAD_TRANSFER_MODE=embedded as the default until the chart/operator exposes stepmgr as a first-class value."
