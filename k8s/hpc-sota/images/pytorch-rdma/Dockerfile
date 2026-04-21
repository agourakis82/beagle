FROM docker.io/pytorch/pytorch:2.7.1-cuda12.8-cudnn9-runtime

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        rdma-core \
        ibverbs-providers \
        ibverbs-utils \
    && rm -rf /var/lib/apt/lists/*

# Host-provided NVIDIA userspace libraries remain mounted at runtime.
ENV LD_LIBRARY_PATH=/nvidia-host
