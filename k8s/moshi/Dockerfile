# Build stage: install moshi + deps (includes git for any pip VCS deps)
FROM python:3.11-slim AS builder

RUN apt-get update && apt-get install -y --no-install-recommends \
    git \
    && rm -rf /var/lib/apt/lists/*

# Pin exact version — verify against kyutai/moshi releases before rebuild.
# HF_TOKEN_PATH is read by huggingface_hub >= 0.20 via the token_path arg.
RUN pip install --no-cache-dir \
    moshi==0.2.2 \
    huggingface_hub>=0.20.0

# Runtime stage: no git, no build tools, minimal surface
FROM python:3.11-slim

RUN apt-get update && apt-get install -y --no-install-recommends \
    libopus0 \
    libopus-dev \
    libsndfile1 \
    ffmpeg \
    gcc \
    g++ \
    && rm -rf /var/lib/apt/lists/*

# moshi routes every attention Linear through bitsandbytes (unconditional
# `import bitsandbytes` in moshi/utils/quantize.py), which initializes Triton.
# Triton JIT-compiles its CUDA driver shim (cuda_utils, plain C) at runtime and
# needs a C compiler. This compile fires ONLY with a GPU present, so it cannot be
# pre-baked in the GPU-less kaniko build stage — the compiler must ship in the
# runtime image. Risk is mitigated deployment-side (drop ALL caps,
# allowPrivilegeEscalation:false) so a compiled exploit cannot pivot.
#
# MINIMAL-TOOLCHAIN FOLLOW-UP (not yet built): the strictly-minimal set is
# `gcc + libc6-dev` (NOT just gcc — the Debian gcc pkg omits libc6-dev, which
# g++ was transitively providing; dropping g++ alone breaks the compile). A
# rebuild to that set was blocked 2026-06-19 by r770 ephemeral-storage eviction.
ENV CC=gcc

COPY --from=builder /usr/local/lib/python3.11/site-packages /usr/local/lib/python3.11/site-packages
COPY --from=builder /usr/local/bin /usr/local/bin

ENV HF_HOME=/var/cache/huggingface

WORKDIR /app

EXPOSE 8998

CMD ["python", "-m", "moshi.server", "--host", "0.0.0.0", "--port", "8998"]
