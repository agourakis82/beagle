# Multi-stage Dockerfile for HERMES BPSE
# Optimized for production deployment

# ============================================
# Stage 1: Builder
# ============================================
FROM rust:1.75-slim as builder

# Install build dependencies
RUN apt-get update && apt-get install -y \
    pkg-config \
    libssl-dev \
    python3 \
    python3-pip \
    && rm -rf /var/lib/apt/lists/*

# Install Python ML dependencies
COPY python/requirements.txt /tmp/requirements.txt
RUN pip3 install --no-cache-dir -r /tmp/requirements.txt && \
    python3 -m spacy download en_core_web_sm

# Set working directory
WORKDIR /build

# Copy workspace root files
COPY Cargo.toml Cargo.lock ./

# Copy all crates (for dependency resolution)
COPY crates/ ./crates/

# Build the application
# Docker layer caching will work because we copy Cargo files first
RUN cargo build --release --package beagle-hermes

# ============================================
# Stage 2: Runtime
# ============================================
FROM debian:bookworm-slim

# Install runtime dependencies
RUN apt-get update && apt-get install -y \
    ca-certificates \
    libssl3 \
    python3 \
    python3-pip \
    curl \
    && rm -rf /var/lib/apt/lists/*

# Install Python runtime dependencies (minimal)
COPY python/requirements.txt /tmp/requirements.txt
RUN pip3 install --no-cache-dir \
    torch==2.3.0 \
    transformers==4.35.0 \
    sentence-transformers==2.2.2 \
    whisper==1.1.10 \
    spacy==3.7.2 \
    numpy==1.26.4 \
    pydantic==2.5.0 && \
    python3 -m spacy download en_core_web_sm

# Create non-root user
RUN useradd -m -u 1000 hermes && \
    mkdir -p /app /data /logs && \
    chown -R hermes:hermes /app /data /logs

# Copy binary from builder
COPY --from=builder /build/target/release/beagle-hermes /app/hermes
COPY --from=builder /build/crates/beagle-hermes/python/ /app/python/

# Copy configuration files
COPY crates/beagle-hermes/docker/docker-entrypoint.sh /app/entrypoint.sh
COPY crates/beagle-hermes/observability/ /app/observability/
COPY crates/beagle-hermes/migrations/ /app/migrations/

# Set permissions
RUN chmod +x /app/hermes /app/entrypoint.sh && \
    chown -R hermes:hermes /app

# Switch to non-root user
USER hermes

# Set working directory
WORKDIR /app

# Expose ports
EXPOSE 8080 9090

# Health check
HEALTHCHECK --interval=30s --timeout=10s --start-period=40s --retries=3 \
    CMD curl -f http://localhost:8080/health || exit 1

# Environment variables
ENV RUST_LOG=info
ENV RUST_BACKTRACE=1
ENV PYTHONUNBUFFERED=1

# Entry point
ENTRYPOINT ["/app/entrypoint.sh"]
CMD ["/app/hermes"]

