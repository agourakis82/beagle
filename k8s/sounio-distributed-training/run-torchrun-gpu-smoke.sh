#!/usr/bin/env bash
set -euo pipefail

namespace="${NAMESPACE:-beagle}"
nodes_csv="${1:-r770-proxmox,r740-proxmox}"
IFS=',' read -r -a nodes <<< "$nodes_csv"
world_size="${#nodes[@]}"
job_name="ddp$(date +%m%d%H%M%S)"

if (( world_size < 2 )); then
  echo "need at least 2 nodes for a multi-node smoke" >&2
  exit 1
fi

if kubectl config current-context >/dev/null 2>&1; then
  k() { kubectl "$@"; }
elif sudo kubectl config current-context >/dev/null 2>&1; then
  k() { sudo kubectl "$@"; }
else
  echo "unable to find a working kubectl context via kubectl or sudo kubectl" >&2
  exit 1
fi

node_yaml="$(printf '%s\n' "${nodes[@]}" | sed 's/^/                              - /')"

cat <<EOF | k -n "$namespace" apply -f -
apiVersion: jobset.x-k8s.io/v1alpha2
kind: JobSet
metadata:
  name: ${job_name}
spec:
  network:
    enableDNSHostnames: true
    publishNotReadyAddresses: true
    subdomain: ddp
  coordinator:
    replicatedJob: w
    jobIndex: 0
    podIndex: 0
  replicatedJobs:
    - name: w
      template:
        spec:
          completionMode: Indexed
          parallelism: ${world_size}
          completions: ${world_size}
          backoffLimit: 0
          template:
            metadata:
              labels:
                app.kubernetes.io/name: sounio-torchrun-gpu-smoke
            spec:
              restartPolicy: Never
              tolerations:
                - key: sounio.dev/pool
                  operator: Equal
                  value: gpu-batch
                  effect: NoSchedule
                - key: sounio.dev/compute
                  operator: Equal
                  value: heavy
                  effect: NoSchedule
              affinity:
                nodeAffinity:
                  requiredDuringSchedulingIgnoredDuringExecution:
                    nodeSelectorTerms:
                      - matchExpressions:
                          - key: kubernetes.io/hostname
                            operator: In
                            values:
${node_yaml}
              containers:
                - name: trainer
                  image: docker.io/pytorch/pytorch:2.5.1-cuda12.1-cudnn9-runtime
                  imagePullPolicy: IfNotPresent
                  env:
                    - name: MASTER_ADDR
                      valueFrom:
                        fieldRef:
                          fieldPath: metadata.annotations['jobset.sigs.k8s.io/coordinator']
                    - name: MASTER_PORT
                      value: "29500"
                    - name: WORLD_SIZE
                      value: "${world_size}"
                    - name: RANK
                      valueFrom:
                        fieldRef:
                          fieldPath: metadata.annotations['batch.kubernetes.io/job-completion-index']
                    - name: PYTHONUNBUFFERED
                      value: "1"
                    - name: NCCL_DEBUG
                      value: "INFO"
                    - name: NCCL_SOCKET_IFNAME
                      value: "eth0"
                    - name: NCCL_IB_DISABLE
                      value: "1"
                  command:
                    - /bin/bash
                    - -lc
                    - |
                      python - <<'PY'
                      import os
                      import socket
                      import time
                      import torch
                      import torch.distributed as dist

                      master_addr = os.environ["MASTER_ADDR"]
                      master_port = os.environ["MASTER_PORT"]
                      rank = int(os.environ["RANK"])
                      world_size = int(os.environ["WORLD_SIZE"])
                      backend = "nccl" if torch.cuda.is_available() else "gloo"
                      device = "cuda" if torch.cuda.is_available() else "cpu"

                      if torch.cuda.is_available():
                          torch.cuda.set_device(0)

                      if rank != 0:
                          deadline = time.time() + 60
                          while time.time() < deadline:
                              try:
                                  with socket.create_connection((master_addr, int(master_port)), timeout=2):
                                      break
                              except OSError:
                                  time.sleep(1)

                      print(f"BOOT host={socket.gethostname()} rank={rank}/{world_size} backend={backend} device={device} master={master_addr}:{master_port}", flush=True)
                      dist.init_process_group(
                          backend=backend,
                          init_method=f"tcp://{master_addr}:{master_port}",
                          rank=rank,
                          world_size=world_size,
                      )
                      t = torch.tensor([rank + 1.0], device=device)
                      dist.all_reduce(t, op=dist.ReduceOp.SUM)
                      gpu_name = torch.cuda.get_device_name(0) if torch.cuda.is_available() else "cpu"
                      print(f"RESULT host={socket.gethostname()} rank={rank} gpu={gpu_name} reduced={t.item()}", flush=True)
                      dist.barrier()
                      dist.destroy_process_group()
                      PY
                  resources:
                    limits:
                      cpu: "8"
                      memory: 24Gi
                      nvidia.com/gpu: "1"
EOF

echo "$job_name"
