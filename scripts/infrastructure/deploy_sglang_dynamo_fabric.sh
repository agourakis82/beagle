#!/usr/bin/env bash
set -euo pipefail

namespace="${1:-beagle}"
repo_root="/home/devsounio/beagle"
image="${DYNAMO_SGLANG_IMAGE:-}"

DYNAMO_PLATFORM_VERSION="${DYNAMO_PLATFORM_VERSION:-1.0.1}" \
  "${repo_root}/scripts/infrastructure/setup_dynamo_platform.sh" dynamo-system

kubectl apply -f "${repo_root}/k8s/project-cockpit/serviceaccount.yaml"
kubectl apply -f "${repo_root}/k8s/project-cockpit/clusterrole.yaml"
kubectl apply -f "${repo_root}/k8s/project-cockpit/clusterrolebinding.yaml"
kubectl apply -f "${repo_root}/k8s/project-cockpit/sglang-serving-service.yaml"
kubectl apply -f "${repo_root}/k8s/project-cockpit/sglang-serving-deployment.yaml"
kubectl apply -f "${repo_root}/k8s/project-cockpit/dynamo-control-plane-service.yaml"
kubectl apply -f "${repo_root}/k8s/project-cockpit/dynamo-control-plane-deployment.yaml"

if [[ -n "${image}" ]]; then
  kubectl -n "${namespace}" set image deployment/sglang-serving sglang="${image}"
  kubectl -n "${namespace}" set image deployment/dynamo-control-plane dynamo="${image}"
fi

kubectl -n "${namespace}" patch deployment/sglang-serving --type='json' -p='[
  {"op":"remove","path":"/spec/template/spec/initContainers"},
  {"op":"remove","path":"/spec/template/spec/volumes/0"},
  {"op":"remove","path":"/spec/template/spec/containers/0/volumeMounts/0"},
  {"op":"add","path":"/spec/template/spec/containers/0/securityContext/seccompProfile","value":{"type":"Unconfined"}}
]' 2>/dev/null || true

kubectl -n "${namespace}" patch deployment/dynamo-control-plane --type='json' -p='[
  {"op":"remove","path":"/spec/template/spec/initContainers"},
  {"op":"remove","path":"/spec/template/spec/volumes"},
  {"op":"remove","path":"/spec/template/spec/containers/0/volumeMounts"},
  {"op":"add","path":"/spec/template/spec/containers/0/securityContext","value":{"privileged":true,"seccompProfile":{"type":"Unconfined"}}}
]' 2>/dev/null || true

kubectl -n "${namespace}" rollout status deployment/sglang-serving --timeout=20m
kubectl -n "${namespace}" rollout status deployment/dynamo-control-plane --timeout=20m

if [[ -n "${image}" ]]; then
  printf '%s\n' "${image}"
fi
