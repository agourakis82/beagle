#!/usr/bin/env bash
set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib-kubeconfig.sh"

echo "[check] helm"
helm version --short

echo "[check] kubernetes nodes"
KUBECONFIG="${KUBECONFIG_PATH}" kubectl get nodes -L sounio.dev/accelerator-class,sounio.dev/pool,sounio.dev/orangefs-client

echo "[check] OrangeFS client mounts required on t560/r740/r770"
echo " - t560 control-plane visibility"
echo " - r740 compute"
echo " - r770 compute"

echo "[check] namespaces"
KUBECONFIG="${KUBECONFIG_PATH}" kubectl get ns | egrep '^(cert-manager|slurm-pilot|beagle)' || true

echo
echo "Prereq check finished."
