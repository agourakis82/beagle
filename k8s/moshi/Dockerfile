FROM python:3.11-slim

RUN apt-get update && apt-get install -y --no-install-recommends \
    libopus0 \
    libopus-dev \
    libsndfile1 \
    ffmpeg \
    git \
    && rm -rf /var/lib/apt/lists/*

RUN pip install --no-cache-dir moshi

ENV HF_HOME=/var/cache/huggingface

WORKDIR /app

EXPOSE 8998

CMD ["python", "-m", "moshi.server", "--host", "0.0.0.0", "--port", "8998"]
