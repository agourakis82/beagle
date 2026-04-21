#!/usr/bin/env bash
set -euo pipefail

if [[ $# -lt 2 || $# -gt 3 ]]; then
  echo "usage: $0 <node-hostname> <accelerator-label> [pod-name]" >&2
  exit 1
fi

NODE_HOSTNAME="$1"
ACCELERATOR_LABEL="$2"
POD_NAME="${3:-gpu-userspace-smoke}"
HOST_DRIVER_LIBS="${SOUNIO_SMOKE_HOST_DRIVER_LIBS:-1}"

extra_env=""
extra_volume_mounts=""
extra_volumes=""

if [[ "$HOST_DRIVER_LIBS" != "0" ]]; then
  extra_env=$(cat <<'EOF'
    env:
    - name: LD_LIBRARY_PATH
      value: /nvidia-host
EOF
)
  extra_volume_mounts=$(cat <<'EOF'
    volumeMounts:
    - name: host-libcuda
      mountPath: /nvidia-host/libcuda.so.1
      readOnly: true
    - name: host-libnvidia-ml
      mountPath: /nvidia-host/libnvidia-ml.so.1
      readOnly: true
EOF
)
  extra_volumes=$(cat <<'EOF'
  volumes:
  - name: host-libcuda
    hostPath:
      path: /lib/x86_64-linux-gnu/libcuda.so.1
      type: File
  - name: host-libnvidia-ml
    hostPath:
      path: /lib/x86_64-linux-gnu/libnvidia-ml.so.1
      type: File
EOF
)
fi

cat <<EOF
apiVersion: v1
kind: Pod
metadata:
  name: ${POD_NAME}
  namespace: beagle
spec:
  runtimeClassName: nvidia
  restartPolicy: Never
  securityContext:
    seccompProfile:
      type: Unconfined
  nodeSelector:
    kubernetes.io/hostname: ${NODE_HOSTNAME}
    sounio.dev/accelerator: ${ACCELERATOR_LABEL}
  tolerations:
  - operator: Exists
    effect: NoSchedule
  - operator: Exists
    effect: NoExecute
  containers:
  - name: smoke
    image: pytorch/pytorch:2.7.1-cuda12.8-cudnn9-runtime
    imagePullPolicy: IfNotPresent
    securityContext:
      privileged: true
${extra_env}
    resources:
      requests:
        cpu: "2"
        memory: 4Gi
        nvidia.com/gpu: "1"
      limits:
        cpu: "2"
        memory: 4Gi
        nvidia.com/gpu: "1"
${extra_volume_mounts}
    command:
    - bash
    - -lc
    args:
    - |
      python - <<'PY'
      import ctypes
      try:
          ctypes.CDLL("libcuda.so.1")
          print("libcuda_load", "ok")
      except Exception as exc:
          print("libcuda_load_err", repr(exc))
      PY
      python - <<'PY'
      import torch
      print("cuda_available", torch.cuda.is_available())
      print("cuda_count", torch.cuda.device_count())
      try:
          print("device0", torch.cuda.get_device_name(0))
      except Exception as exc:
          print("device0_err", repr(exc))
      PY
      command -v nvidia-smi || true
      nvidia-smi || true
${extra_volumes}
EOF
