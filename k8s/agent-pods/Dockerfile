# Beagle Agent Pod — unified image supporting multiple agent kinds.
#
# Agents installed:
#   - claude-code (Anthropic CLI)
#   - codex (OpenAI CLI — optional, installed if available)
#   - bash (fallback)
#
# Build:
#   docker build -t beagle-agent:latest .
#   docker tag beagle-agent:latest ttl.sh/beagle-agent-$(date +%s):24h
#   docker push ttl.sh/beagle-agent-...

FROM node:22-bookworm-slim AS agent

RUN apt-get update && \
    apt-get install -y --no-install-recommends \
      tmux \
      git \
      curl \
      ca-certificates \
      jq \
      openssh-client \
      less \
      procps \
      python3 \
      build-essential \
    && rm -rf /var/lib/apt/lists/*

# Install Claude Code CLI
RUN npm install -g @anthropic-ai/claude-code@latest

# Install Codex CLI (if available — fail gracefully)
RUN npm install -g @openai/codex@latest || echo "codex not available"

# Non-root user — node:22 base already has UID 1000 as 'node'. Remove and replace
# with 'agent' so our StatefulSet runAsUser:1000 matches.
RUN userdel -r node 2>/dev/null || true && \
    useradd -u 1000 -m -s /bin/bash agent && \
    mkdir -p /workspace && \
    chown -R agent:agent /workspace

# Entrypoint
COPY entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh

USER agent
WORKDIR /workspace

# Tmux default config — preserve scrollback, reasonable key bindings
RUN cat > /home/agent/.tmux.conf <<'EOF'
set -g history-limit 50000
set -g mouse on
set -g default-terminal "xterm-256color"
set -ga terminal-overrides ",xterm-256color:Tc"
set -g status off
EOF

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
