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
  && curl -fsSL -o /usr/local/bin/kubectl "https://dl.k8s.io/release/v1.30.14/bin/linux/amd64/kubectl" \
  && chmod +x /usr/local/bin/kubectl \
  && rm -rf /var/lib/apt/lists/*

WORKDIR /app
COPY apps/project-cockpit/package.json ./package.json
COPY apps/project-cockpit/package-lock.json ./package-lock.json
RUN npm ci --omit=dev

COPY apps/project-cockpit/server ./server
COPY apps/project-cockpit/public ./public

ENV PROJECT_COCKPIT_HOST=0.0.0.0
ENV PROJECT_COCKPIT_PORT=4370
ENV PROJECT_COCKPIT_WORKBENCH_AUTHORITY=workspace-agent
EXPOSE 4370

USER node
CMD ["node", "server/index.mjs"]
