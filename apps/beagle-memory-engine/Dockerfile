FROM rust:1.89-bookworm AS builder

WORKDIR /workspace
COPY . .
RUN cargo build --release -p beagle-memory-engine

FROM debian:bookworm-slim

RUN apt-get update \
    && apt-get install -y --no-install-recommends ca-certificates python3 python3-pip python3-venv \
    && rm -rf /var/lib/apt/lists/*

COPY apps/beagle-memory-engine/requirements.txt /tmp/beagle-memory-engine-requirements.txt
RUN python3 -m pip install --break-system-packages --no-cache-dir -r /tmp/beagle-memory-engine-requirements.txt

COPY --from=builder /workspace/target/release/beagle-memory-engine /usr/local/bin/beagle-memory-engine
COPY apps/beagle-memory-engine/workers /opt/beagle-memory-engine/workers

ENV BEAGLE_MEMORY_ENGINE_BIND_ADDR=0.0.0.0:8090
EXPOSE 8090

USER 10001:10001
ENTRYPOINT ["/usr/local/bin/beagle-memory-engine"]
