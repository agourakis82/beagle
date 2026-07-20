# tmux 3.5a (matches t560 Debian trixie) baked in, so the pod runs as uid 1000 (socket owner)
# without needing root for a runtime apt. Minimal: just tmux + git for read-only state.
FROM debian:trixie-slim
RUN apt-get update \
 && apt-get install -y --no-install-recommends tmux git ca-certificates \
 && rm -rf /var/lib/apt/lists/*
CMD ["sleep", "infinity"]
