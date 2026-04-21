#!/usr/bin/env bash
set -euo pipefail

if [[ $# -lt 3 || $# -gt 4 ]]; then
  echo "usage: $0 <job-name> <accelerator-sku> <worker-replicas> [image]" >&2
  exit 1
fi

job_name="$1"
accelerator_sku="$2"
worker_replicas="$3"
image="${4:-pytorch/pytorch:2.7.1-cuda12.8-cudnn9-runtime}"
local_queue="${KUEUE_LOCAL_QUEUE:-}"
priority_class_name="${PRIORITY_CLASS_NAME:-}"
if [[ ! "${worker_replicas}" =~ ^[0-9]+$ ]]; then
  echo "worker_replicas must be an integer" >&2
  exit 1
fi
if (( worker_replicas < 2 )); then
  echo "need at least 2 worker replicas for a meaningful multi-node jobset" >&2
  exit 1
fi

metadata_labels_yaml=""
if [[ -n "${local_queue}" ]]; then
  metadata_labels_yaml="$(cat <<EOF
  labels:
    kueue.x-k8s.io/queue-name: ${local_queue}
EOF
)"
fi

priority_class_yaml=""
if [[ -n "${priority_class_name}" ]]; then
  priority_class_yaml="$(cat <<EOF
              priorityClassName: ${priority_class_name}
EOF
)"
fi

cat <<EOF
apiVersion: jobset.x-k8s.io/v1alpha2
kind: JobSet
metadata:
  name: ${job_name}
  namespace: beagle
${metadata_labels_yaml}
  annotations:
    alpha.jobset.sigs.k8s.io/exclusive-topology: kubernetes.io/hostname
spec:
  coordinator:
    replicatedJob: workers
    jobIndex: 0
    podIndex: 0
  network:
    enableDNSHostnames: true
    subdomain: ${job_name}
    publishNotReadyAddresses: true
  replicatedJobs:
    - name: workers
      replicas: ${worker_replicas}
      template:
        spec:
          parallelism: 1
          completions: 1
          backoffLimit: 0
          template:
            metadata:
              labels:
                sounio.dev/distributed-group: ${job_name}
            spec:
              restartPolicy: Never
${priority_class_yaml}
              securityContext:
                seccompProfile:
                  type: Unconfined
              tolerations:
                - key: sounio.dev/compute
                  operator: Equal
                  value: heavy
                  effect: NoSchedule
                - key: sounio.dev/pool
                  operator: Equal
                  value: gpu-batch
                  effect: NoSchedule
              nodeSelector:
                sounio.dev/accelerator: ${accelerator_sku}
              affinity:
                podAntiAffinity:
                  requiredDuringSchedulingIgnoredDuringExecution:
                    - labelSelector:
                        matchExpressions:
                          - key: sounio.dev/distributed-group
                            operator: In
                            values:
                              - ${job_name}
                      topologyKey: kubernetes.io/hostname
              containers:
                - name: trainer
                  image: ${image}
                  securityContext:
                    privileged: true
                  env:
                    - name: MASTER_HOST
                      valueFrom:
                        fieldRef:
                          fieldPath: metadata.annotations['jobset.sigs.k8s.io/coordinator']
                    - name: POD_NAMESPACE
                      valueFrom:
                        fieldRef:
                          fieldPath: metadata.namespace
                    - name: JOBSET_SUBDOMAIN
                      value: "${job_name}"
                    - name: MASTER_PORT
                      value: "29500"
                    - name: NNODES
                      value: "${worker_replicas}"
                    - name: NODE_RANK
                      valueFrom:
                        fieldRef:
                          fieldPath: metadata.labels['jobset.sigs.k8s.io/job-index']
                    - name: NCCL_SOCKET_IFNAME
                      value: eth0
                    - name: TORCH_NCCL_ASYNC_ERROR_HANDLING
                      value: "1"
                  command:
                    - /bin/bash
                    - -lc
                    - |
                      set -euo pipefail
                      resolve_master() {
                        python - <<'PY'
                      import os
                      import socket
                      import time

                      host = os.environ["MASTER_HOST"]
                      namespace = os.environ["POD_NAMESPACE"]
                      subdomain = os.environ["JOBSET_SUBDOMAIN"]
                      port = int(os.environ["MASTER_PORT"])

                      candidates = []

                      def add(candidate: str) -> None:
                          if candidate and candidate not in candidates:
                              candidates.append(candidate)

                      add(host)
                      if host.endswith(f".{subdomain}"):
                          add(f"{host}.{namespace}.svc")
                          add(f"{host}.{namespace}.svc.cluster.local")
                      elif "." not in host:
                          add(f"{host}.{subdomain}")
                          add(f"{host}.{subdomain}.{namespace}.svc")
                          add(f"{host}.{subdomain}.{namespace}.svc.cluster.local")
                          add(f"{host}.{namespace}.svc")
                          add(f"{host}.{namespace}.svc.cluster.local")

                      deadline = time.time() + 60
                      while time.time() < deadline:
                          for candidate in candidates:
                              try:
                                  infos = socket.getaddrinfo(
                                      candidate,
                                      port,
                                      family=socket.AF_INET,
                                      type=socket.SOCK_STREAM,
                                  )
                                  print(infos[0][4][0])
                                  raise SystemExit(0)
                              except OSError:
                                  pass
                          time.sleep(1)

                      raise SystemExit(
                          f"unable to resolve coordinator from host={host!r} candidates={candidates!r}"
                      )
                      PY
                      }
                      MASTER_ADDR_IP="\$(resolve_master)"
                      exec python -m torch.distributed.run \\
                        --nnodes="\${NNODES}" \\
                        --nproc_per_node=1 \\
                        --node_rank="\${NODE_RANK}" \\
                        --rdzv_backend=c10d \\
                        --rdzv_endpoint="\${MASTER_ADDR_IP}:\${MASTER_PORT}" \\
                        train.py
                  resources:
                    requests:
                      nvidia.com/gpu: "1"
                      cpu: "8"
                      memory: 24Gi
                    limits:
                      nvidia.com/gpu: "1"
                      cpu: "8"
                      memory: 24Gi
                  volumeMounts:
                    - name: libcuda1
                      mountPath: /usr/lib/x86_64-linux-gnu/libcuda.so.1
                      readOnly: true
                    - name: libnvidia-ml1
                      mountPath: /usr/lib/x86_64-linux-gnu/libnvidia-ml.so.1
                      readOnly: true
              volumes:
                - name: libcuda1
                  hostPath:
                    path: /usr/lib/x86_64-linux-gnu/libcuda.so.1
                    type: File
                - name: libnvidia-ml1
                  hostPath:
                    path: /usr/lib/x86_64-linux-gnu/libnvidia-ml.so.1
                    type: File
EOF
