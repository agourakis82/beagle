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
# Triton JIT-compiles its CUDA driver shim at runtime and needs a C compiler.
# Python.h and Triton's bundled cuda.h are already in the image; only the
# compiler was missing. Triton resolves it via `cc`/$CC — gcc provides both.
ENV CC=gcc

COPY --from=builder /usr/local/lib/python3.11/site-packages /usr/local/lib/python3.11/site-packages
COPY --from=builder /usr/local/bin /usr/local/bin

ENV HF_HOME=/var/cache/huggingface

WORKDIR /app

EXPOSE 8998

CMD ["python", "-m", "moshi.server", "--host", "0.0.0.0", "--port", "8998"]
