FROM node:20-bookworm-slim

RUN apt-get update \
  && apt-get install -y --no-install-recommends \
    bash \
    ca-certificates \
    curl \
    g++ \
    git \
    make \
    openssh-client \
    procps \
    python3 \
  && rm -rf /var/lib/apt/lists/*

WORKDIR /app
COPY apps/beagle-workspace-agent/package.json ./package.json
COPY apps/beagle-workspace-agent/package-lock.json ./package-lock.json
RUN npm ci --omit=dev

COPY apps/beagle-workspace-agent/src ./src

ENV BEAGLE_WORKSPACE_AGENT_PORT=4371
ENV BEAGLE_PTY_SUPERVISOR_URL=http://127.0.0.1:4372
EXPOSE 4371

USER node
CMD ["node", "src/server.mjs"]
