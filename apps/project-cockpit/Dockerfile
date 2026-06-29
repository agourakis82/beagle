# kubectl as a build stage so we COPY the binary instead of curl-downloading it.
# curl inside a kaniko RUN fails with "getaddrinfo() thread failed to start" (its
# threaded resolver can't spawn under kaniko, on every node); COPY sidesteps it.
FROM registry.k8s.io/kubectl:v1.30.14 AS kubectl

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

COPY --from=kubectl /bin/kubectl /usr/local/bin/kubectl
RUN chmod +x /usr/local/bin/kubectl

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
