FROM ghcr.io/slinkyproject/slurmd:25.11-ubuntu24.04

ARG DEBIAN_FRONTEND=noninteractive

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        gcc \
        libc6-dev \
    && rm -rf /var/lib/apt/lists/*

RUN command -v cc && cc --version | head -1

